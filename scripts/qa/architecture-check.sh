#!/usr/bin/env bash
# scripts/qa/architecture-check.sh — architectural fitness tests
#
# Enforces dependency layering and structural invariants across the workspace.
#
# Checks:
#   1. Library -> Binary layering: no crate under libraries/ depends on binaries/
#   2. No duplicate major versions of critical deps (tokio, arrow)
#   3. Publishable crates have a description field (required by crates.io)
#
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

# Locate jq
if command -v jq &>/dev/null; then
  JQ=jq
elif [[ -x /tmp/jq ]]; then
  JQ=/tmp/jq
else
  echo -e "${RED}ERROR${RESET} jq is required but not found. Install it or place a binary at /tmp/jq."
  exit 1
fi

echo -e "${BOLD}Architectural fitness tests${RESET}"
echo

# Cache metadata (--no-deps is fast)
METADATA=$(cargo metadata --no-deps --format-version=1)

# ── Check 1: Library -> Binary layering ──────────────────────────────
echo -e "${BOLD}[1/3] Library -> Binary layering (libraries/ must not depend on binaries/)${RESET}"

# Build list of binary crate names (manifest_path contains /binaries/)
BINARY_CRATES=$( echo "$METADATA" | "$JQ" -r '
  [.packages[] | select(.manifest_path | contains("/binaries/")) | .name] | .[]
')

# For each library crate, check if any dependency name matches a binary crate
while IFS=$'\t' read -r lib_name dep_name; do
  warn "  ${lib_name} depends on binary crate ${dep_name}"
done < <(
  echo "$METADATA" | "$JQ" -r --argjson bins "$(
    echo "$METADATA" | "$JQ" '[.packages[] | select(.manifest_path | contains("/binaries/")) | .name]'
  )" '
    .packages[]
    | select(.manifest_path | contains("/libraries/"))
    | . as $pkg
    | .dependencies[]
    | select(.kind == null or .kind == "normal" or .kind == "build")
    | select(.name as $dep | $bins | index($dep))
    | "\($pkg.name)\t\(.name)"
  ' 2>/dev/null || true
)

# ── Check 2: No duplicate major versions of critical deps ────────────
echo -e "${BOLD}[2/3] No duplicate major versions of critical deps (tokio, arrow)${RESET}"

DUPES=$(cargo tree -d 2>&1 | grep -E '^(tokio|arrow) v' || true)

if [[ -n "$DUPES" ]]; then
  while IFS= read -r line; do
    warn "  duplicate: $line"
  done <<< "$DUPES"
fi

# ── Check 3: Publishable crates have description ─────────────────────
echo -e "${BOLD}[3/3] Publishable crates have description${RESET}"

while IFS= read -r name; do
  warn "  ${name} is publishable but has no description"
done < <(
  echo "$METADATA" | "$JQ" -r '
    .packages[]
    | select(.publish != [])
    | select(.description == null or .description == "")
    | .name
  ' 2>/dev/null || true
)

# ── Summary ───────────────────────────────────────────────────────────
echo
if [[ "$issues" -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}PASS${RESET} — no architectural issues found"
  exit 0
else
  echo -e "${RED}${BOLD}FAIL${RESET} — ${issues} issue(s) found"
  exit 1
fi
