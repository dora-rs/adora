#!/usr/bin/env bash
# scripts/qa/release-config-check.sh — validate release configuration consistency
#
# Checks:
#   1. Workspace version sharing: all non-0.0.0 crates resolve to the same version
#   2. Every crate in release.yml is a real workspace member
#   3. Tag pattern consistency between release.toml and release.yml
#
# Requires: cargo, python3
# Exit 0 on pass, 1 on failure.

set -euo pipefail

cd "$(dirname "$0")/../.."

issues=0

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

warn() {
  echo -e "${YELLOW}WARNING${RESET} $1"
  issues=$((issues + 1))
}

fail() {
  echo -e "${RED}FAIL${RESET} $1"
  issues=$((issues + 1))
}

echo -e "${BOLD}Release configuration consistency check${RESET}"
echo

# Prefetch cargo metadata once, extract name/version/manifest_path via python3
METADATA_RAW=$(cargo metadata --no-deps --format-version=1 2>/dev/null)
WORKSPACE_ROOT=$(echo "$METADATA_RAW" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data['workspace_root'])
")
# Each line: "name version manifest_path"
PACKAGES=$(echo "$METADATA_RAW" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for p in data['packages']:
    print(p['name'], p['version'], p['manifest_path'])
")

# ── Check 1: Workspace version sharing ────────────────────────────────
echo -e "${BOLD}[1/3] Workspace version sharing${RESET}"

# Read the canonical workspace version from root Cargo.toml [workspace.package]
WORKSPACE_VERSION=$(grep -A10 '\[workspace.package\]' Cargo.toml | grep '^version' | head -1 | sed 's/.*"\(.*\)".*/\1/')
echo "  Workspace version: ${WORKSPACE_VERSION}"

# Exclude example crates and 0.0.0 crates from the check.
# Example crates may pin their own version; 0.0.0 means unpublished.
EXAMPLES_PREFIX="${WORKSPACE_ROOT}/examples/"
NON_EXAMPLE_PACKAGES=$(echo "$PACKAGES" | while read -r name ver path; do
  if [[ "$path" != "${EXAMPLES_PREFIX}"* ]] && [[ "$ver" != "0.0.0" ]]; then
    echo "$name $ver"
  fi
done)

NON_MATCHING=$(echo "$NON_EXAMPLE_PACKAGES" | awk -v wv="$WORKSPACE_VERSION" '$2 != wv {print}')

if [[ -n "$NON_MATCHING" ]]; then
  fail "  Some non-example crates do not match workspace version ${WORKSPACE_VERSION}:"
  while read -r name ver; do
    echo "    ${name}: ${ver}"
  done <<< "$NON_MATCHING"
else
  crate_count=$(echo "$NON_EXAMPLE_PACKAGES" | wc -l)
  echo -e "  ${GREEN}OK${RESET} — all ${crate_count} non-example crates share version ${WORKSPACE_VERSION}"
fi

# ── Check 2: release.yml crates are workspace members ─────────────────
echo -e "${BOLD}[2/3] release.yml crates are workspace members${RESET}"

# Extract crate names from the CRATES array in release.yml
RELEASE_CRATES=$(sed -n '/CRATES=(/,/)/p' .github/workflows/release.yml | grep -v 'CRATES=(' | grep -v ')' | sed 's/#.*//' | tr -d ' ' | grep -v '^$')

# Get all workspace member names
WORKSPACE_MEMBERS=$(echo "$PACKAGES" | awk '{print $1}')

missing=0
while IFS= read -r crate; do
  if ! echo "$WORKSPACE_MEMBERS" | grep -qx "$crate"; then
    fail "  Crate '${crate}' in release.yml is not a workspace member"
    missing=$((missing + 1))
  fi
done <<< "$RELEASE_CRATES"

if [[ "$missing" -eq 0 ]]; then
  crate_count=$(echo "$RELEASE_CRATES" | wc -l)
  echo -e "  ${GREEN}OK${RESET} — all ${crate_count} release crates are workspace members"
fi

# ── Check 3: Tag pattern consistency ──────────────────────────────────
echo -e "${BOLD}[3/3] Tag pattern consistency (release.toml vs release.yml)${RESET}"

# Extract tag-name template from release.toml
TAG_TEMPLATE=$(grep '^tag-name' release.toml | sed 's/.*= *"//' | sed 's/".*//')
echo "  release.toml tag-name: ${TAG_TEMPLATE}"

# Extract tag pattern from release.yml
TAG_PATTERN=$(grep -A1 'tags:' .github/workflows/release.yml | tail -1 | sed "s/.*'\(.*\)'.*/\1/" | sed 's/.*"\(.*\)".*/\1/')
echo "  release.yml tag pattern: ${TAG_PATTERN}"

# Generate a sample tag from the template using the current workspace version
SAMPLE_TAG=$(echo "$TAG_TEMPLATE" | sed "s/{{version}}/${WORKSPACE_VERSION}/g")
echo "  Sample tag for v${WORKSPACE_VERSION}: ${SAMPLE_TAG}"

# Convert the glob pattern to a regex for matching
# v[0-9]+.[0-9]+.[0-9]+ -> ^v[0-9]+\.[0-9]+\.[0-9]+$
TAG_REGEX=$(echo "$TAG_PATTERN" | sed 's/\./\\./g')
TAG_REGEX="^${TAG_REGEX}$"

if echo "$SAMPLE_TAG" | grep -qE "$TAG_REGEX"; then
  echo -e "  ${GREEN}OK${RESET} — sample tag '${SAMPLE_TAG}' matches release.yml pattern"
else
  fail "  Sample tag '${SAMPLE_TAG}' does NOT match release.yml pattern '${TAG_PATTERN}'"
fi

# Also verify the template starts with 'v' (convention check)
if [[ "$TAG_TEMPLATE" != v* ]]; then
  warn "  Tag template '${TAG_TEMPLATE}' does not start with 'v' (convention is vX.Y.Z)"
fi

# ── Summary ────────────────────────────────────────────────────────────
echo
if [[ "$issues" -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}PASS${RESET} — release configuration is consistent"
  exit 0
else
  echo -e "${RED}${BOLD}FAIL${RESET} — ${issues} issue(s) found"
  exit 1
fi
