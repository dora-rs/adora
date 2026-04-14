#!/usr/bin/env bash
# scripts/qa/ci-parity-check.sh — detect drift between CI and local Makefile exclude lists
#
# Compares --exclude flags used in:
#   - CI clippy vs Makefile qa-clippy
#   - CI test   vs Makefile qa-test
#
# Exit 0 if parity matches, exit 1 if divergence found.

set -euo pipefail

cd "$(dirname "$0")/../.."

CI_FILE=".github/workflows/ci.yml"
MAKEFILE="Makefile"
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
  echo -e "  ${YELLOW}DRIFT${RESET} $1"
  issues=$((issues + 1))
}

# Extract --exclude values from a range of lines
# Usage: extract_excludes <file> <start_pattern> <end_pattern>
# Reads from start_pattern to end_pattern (or next blank line) and pulls --exclude args
extract_excludes_ci() {
  local file="$1" start_pattern="$2" stop_pattern="$3"
  sed -n "/${start_pattern}/,/${stop_pattern}/p" "$file" \
    | grep -oP '(?<=--exclude )\S+' \
    | sort -u
}

extract_excludes_makefile() {
  local file="$1" start_pattern="$2" stop_pattern="$3"
  sed -n "/${start_pattern}/,/${stop_pattern}/p" "$file" \
    | grep -oP '(?<=--exclude )\S+' \
    | sed 's/ *\\$//' \
    | sort -u
}

echo -e "${BOLD}CI vs Local parity check${RESET}"
echo "Comparing exclude lists: ${CI_FILE} vs ${MAKEFILE}"
echo

# ── Clippy excludes ───────────────────────────────────────────────────
echo -e "${BOLD}[1/2] Clippy excludes${RESET}"

ci_clippy=$(extract_excludes_ci "$CI_FILE" "cargo clippy --all" "-- -D warnings")
mk_clippy=$(extract_excludes_makefile "$MAKEFILE" "qa-clippy:" "-- -D warnings")

ci_only_clippy=$(comm -23 <(echo "$ci_clippy") <(echo "$mk_clippy"))
mk_only_clippy=$(comm -13 <(echo "$ci_clippy") <(echo "$mk_clippy"))

if [[ -z "$ci_only_clippy" && -z "$mk_only_clippy" ]]; then
  echo -e "  ${GREEN}OK${RESET} — clippy excludes match"
else
  if [[ -n "$ci_only_clippy" ]]; then
    while IFS= read -r crate; do
      warn "clippy: ${crate} excluded in CI but NOT in Makefile"
    done <<< "$ci_only_clippy"
  fi
  if [[ -n "$mk_only_clippy" ]]; then
    while IFS= read -r crate; do
      warn "clippy: ${crate} excluded in Makefile but NOT in CI"
    done <<< "$mk_only_clippy"
  fi
fi

echo

# ── Test excludes ─────────────────────────────────────────────────────
echo -e "${BOLD}[2/2] Test excludes${RESET}"

ci_test=$(extract_excludes_ci "$CI_FILE" "cargo test --all" "multiple-daemons-example-operator")
mk_test=$(extract_excludes_makefile "$MAKEFILE" "qa-test:" "qa-coverage:")

ci_only_test=$(comm -23 <(echo "$ci_test") <(echo "$mk_test"))
mk_only_test=$(comm -13 <(echo "$ci_test") <(echo "$mk_test"))

if [[ -z "$ci_only_test" && -z "$mk_only_test" ]]; then
  echo -e "  ${GREEN}OK${RESET} — test excludes match"
else
  if [[ -n "$ci_only_test" ]]; then
    while IFS= read -r crate; do
      warn "test: ${crate} excluded in CI but NOT in Makefile"
    done <<< "$ci_only_test"
  fi
  if [[ -n "$mk_only_test" ]]; then
    while IFS= read -r crate; do
      warn "test: ${crate} excluded in Makefile but NOT in CI"
    done <<< "$mk_only_test"
  fi
fi

# ── Summary ───────────────────────────────────────────────────────────
echo
if [[ "$issues" -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}PASS${RESET} — CI and local exclude lists are in sync"
  exit 0
else
  echo -e "${RED}${BOLD}FAIL${RESET} — ${issues} divergence(s) found between CI and local excludes"
  echo -e "  Fix by aligning ${CI_FILE} and ${MAKEFILE}, or document why they differ."
  exit 1
fi
