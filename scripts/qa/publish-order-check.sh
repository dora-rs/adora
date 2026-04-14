#!/usr/bin/env bash
# scripts/qa/publish-order-check.sh — validate crate publish order in release workflows
#
# Checks:
#   1. List completeness: every publishable non-Python workspace member appears in release.yml
#   2. Divergence report: differences between release.yml and cargo-release.yml crate lists
#   3. Topological order: no crate appears before its workspace dependency in release.yml
#
# Requires: cargo, python3 (for JSON parsing — jq replacement)
# Exit 0 on pass, 1 on failure.

set -euo pipefail

cd "$(dirname "$0")/../.."

# Colors (if terminal supports them)
if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  RED='' GREEN='' YELLOW='' BOLD='' RESET=''
fi

issues=0

warn() {
  echo -e "  ${YELLOW}WARN${RESET} $1"
  issues=$((issues + 1))
}

fail() {
  echo -e "  ${RED}FAIL${RESET} $1"
  issues=$((issues + 1))
}

pass() {
  echo -e "  ${GREEN}OK${RESET} $1"
}

echo -e "${BOLD}Crate publish order validation${RESET}"
echo

# ── Prerequisite checks ──────────────────────────────────────────────
for cmd in cargo python3; do
  if ! command -v "$cmd" &>/dev/null; then
    echo -e "${RED}ERROR${RESET}: required command '$cmd' not found"
    exit 1
  fi
done

RELEASE_YML=".github/workflows/release.yml"
CARGO_RELEASE_YML=".github/workflows/cargo-release.yml"

for f in "$RELEASE_YML" "$CARGO_RELEASE_YML"; do
  if [[ ! -f "$f" ]]; then
    echo -e "${RED}ERROR${RESET}: workflow file not found: $f"
    exit 1
  fi
done

# ── Extract crate lists from workflow files ───────────────────────────

# release.yml: CRATES=( ... ) array, one crate per line
extract_release_crates() {
  sed -n '/^          CRATES=(/,/^          )/p' "$RELEASE_YML" \
    | grep -v 'CRATES=(' | grep -v ')' \
    | sed 's/#.*//' | tr -d ' ' | grep -v '^$'
}

# cargo-release.yml: publish_if_not_exists <crate> lines
extract_cargo_release_crates() {
  grep 'publish_if_not_exists ' "$CARGO_RELEASE_YML" \
    | sed 's/.*publish_if_not_exists //' | tr -d ' '
}

mapfile -t RELEASE_CRATES < <(extract_release_crates)
mapfile -t CARGO_RELEASE_CRATES < <(extract_cargo_release_crates)

if [[ ${#RELEASE_CRATES[@]} -eq 0 ]]; then
  echo -e "${RED}ERROR${RESET}: could not extract crate list from $RELEASE_YML"
  exit 1
fi
if [[ ${#CARGO_RELEASE_CRATES[@]} -eq 0 ]]; then
  echo -e "${RED}ERROR${RESET}: could not extract crate list from $CARGO_RELEASE_YML"
  exit 1
fi

echo "  Found ${#RELEASE_CRATES[@]} crates in release.yml"
echo "  Found ${#CARGO_RELEASE_CRATES[@]} crates in cargo-release.yml"
echo

# ── Fetch workspace metadata ─────────────────────────────────────────

METADATA_JSON=$(cargo metadata --no-deps --format-version=1 2>/dev/null)

# Get publishable non-Python crate names
mapfile -t PUBLISHABLE_CRATES < <(echo "$METADATA_JSON" | python3 -c "
import json, sys, os
data = json.load(sys.stdin)
workspace_root = data['workspace_root']
for p in sorted(data['packages'], key=lambda x: x['name']):
    publish = p.get('publish')
    # publish=None means publishable; publish=[] means not publishable
    if publish is not None and len(publish) == 0:
        continue
    # Skip Python packages
    if 'python' in p['name']:
        continue
    # Skip example and test crates (under examples/ or tests/ directories)
    manifest = p.get('manifest_path', '')
    rel = os.path.relpath(manifest, workspace_root) if manifest else ''
    if rel.startswith('examples/') or rel.startswith('tests/'):
        continue
    print(p['name'])
")

echo "  Found ${#PUBLISHABLE_CRATES[@]} publishable non-Python workspace crates"
echo

# ── Check 1: List completeness ───────────────────────────────────────
echo -e "${BOLD}[1/3] List completeness (publishable crates in release.yml)${RESET}"

# Build a set of release.yml crates for fast lookup
declare -A RELEASE_SET
for c in "${RELEASE_CRATES[@]}"; do
  RELEASE_SET["$c"]=1
done

missing_from_release=0
for c in "${PUBLISHABLE_CRATES[@]}"; do
  if [[ -z "${RELEASE_SET[$c]:-}" ]]; then
    fail "$c is publishable but missing from release.yml"
    missing_from_release=$((missing_from_release + 1))
  fi
done

if [[ $missing_from_release -eq 0 ]]; then
  pass "All publishable non-Python crates appear in release.yml"
fi
echo

# ── Check 2: Divergence report ───────────────────────────────────────
echo -e "${BOLD}[2/3] Divergence between release.yml and cargo-release.yml${RESET}"

declare -A CARGO_RELEASE_SET
for c in "${CARGO_RELEASE_CRATES[@]}"; do
  CARGO_RELEASE_SET["$c"]=1
done

# Crates in release.yml but not in cargo-release.yml
in_release_only=()
for c in "${RELEASE_CRATES[@]}"; do
  if [[ -z "${CARGO_RELEASE_SET[$c]:-}" ]]; then
    in_release_only+=("$c")
  fi
done

# Crates in cargo-release.yml but not in release.yml
in_cargo_release_only=()
for c in "${CARGO_RELEASE_CRATES[@]}"; do
  if [[ -z "${RELEASE_SET[$c]:-}" ]]; then
    in_cargo_release_only+=("$c")
  fi
done

if [[ ${#in_release_only[@]} -gt 0 ]]; then
  warn "Crates in release.yml but NOT in cargo-release.yml (${#in_release_only[@]}):"
  for c in "${in_release_only[@]}"; do
    echo -e "    - $c"
  done
fi

if [[ ${#in_cargo_release_only[@]} -gt 0 ]]; then
  warn "Crates in cargo-release.yml but NOT in release.yml (${#in_cargo_release_only[@]}):"
  for c in "${in_cargo_release_only[@]}"; do
    echo -e "    - $c"
  done
fi

if [[ ${#in_release_only[@]} -eq 0 && ${#in_cargo_release_only[@]} -eq 0 ]]; then
  pass "Both workflow files list the same crates"
fi
echo

# ── Check 3: Topological order validation ─────────────────────────────
echo -e "${BOLD}[3/3] Topological order validation (release.yml)${RESET}"

# Get full metadata (with deps) for topological check
FULL_METADATA_JSON=$(cargo metadata --format-version=1 2>/dev/null)

topo_errors=$(echo "$FULL_METADATA_JSON" | python3 -c "
import json, sys

data = json.load(sys.stdin)

# Build lookup: package id -> name
id_to_name = {}
for p in data['packages']:
    id_to_name[p['id']] = p['name']

# Build workspace member set
workspace_ids = set(data.get('workspace_members', []))

# Build workspace package name -> deps (only workspace deps)
workspace_names = set()
ws_deps = {}  # name -> set of workspace dep names

for p in data['packages']:
    if p['id'] not in workspace_ids:
        continue
    workspace_names.add(p['name'])

for p in data['packages']:
    if p['id'] not in workspace_ids:
        continue
    deps = set()
    for dep in p.get('dependencies', []):
        dep_name = dep['name']
        # Skip dev-dependencies and optional dependencies:
        # - dev deps are not needed at publish time
        # - optional deps do not block publishing
        kind = dep.get('kind')  # None = normal, 'dev', 'build'
        if kind == 'dev':
            continue
        if dep.get('optional', False):
            continue
        if dep_name in workspace_names:
            deps.add(dep_name)
    ws_deps[p['name']] = deps

# Read the release.yml order from stdin args
release_order = sys.argv[1:]

# Build position map
pos = {}
for i, name in enumerate(release_order):
    pos[name] = i

# Check: for each crate in the list, all its workspace deps must appear earlier
errors = 0
for crate in release_order:
    if crate not in ws_deps:
        continue
    for dep in sorted(ws_deps[crate]):
        if dep in pos and pos[dep] > pos[crate]:
            print(f'{crate} (position {pos[crate]}) depends on {dep} (position {pos[dep]}) which comes AFTER it')
            errors += 1

sys.exit(0)
" "${RELEASE_CRATES[@]}" 2>&1)

if [[ -n "$topo_errors" ]]; then
  while IFS= read -r line; do
    fail "$line"
  done <<< "$topo_errors"
else
  pass "All crates in release.yml appear after their dependencies"
fi
echo

# ── Summary ───────────────────────────────────────────────────────────
echo -e "${BOLD}Summary${RESET}"
if [[ $issues -eq 0 ]]; then
  echo -e "${GREEN}All checks passed.${RESET}"
  exit 0
else
  echo -e "${RED}Found $issues issue(s).${RESET}"
  exit 1
fi
