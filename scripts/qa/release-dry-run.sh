#!/usr/bin/env bash
# scripts/qa/release-dry-run.sh — cargo publish dry-run for pre-release validation
#
# Runs `cargo publish --dry-run` for publishable workspace crates to catch
# missing metadata, broken dependency resolution, and packaging issues
# before actually publishing.
#
# Usage:
#   scripts/qa/release-dry-run.sh                    # all publishable crates
#   scripts/qa/release-dry-run.sh dora-message dora-core  # specific crates only
#
# This is a manual pre-release tool, NOT for CI (full workspace compile is too slow).
# --allow-dirty is used because the working directory may have uncommitted changes.
# --dry-run does NOT actually publish — it only packages and validates.

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

# ── Determine crate list ────────────────────────────────────────────────

RELEASE_YML=".github/workflows/release.yml"

extract_release_crates() {
  sed -n '/^          CRATES=(/,/^          )/p' "$RELEASE_YML" \
    | grep -v 'CRATES=(' | grep -v ')' \
    | sed 's/#.*//' | tr -d ' ' | grep -v '^$'
}

if [[ $# -gt 0 ]]; then
  CRATES=("$@")
  echo -e "${BOLD}Cargo publish dry-run (${#CRATES[@]} specified crate(s))${RESET}"
else
  if [[ ! -f "$RELEASE_YML" ]]; then
    echo -e "${RED}ERROR${RESET}: workflow file not found: $RELEASE_YML"
    exit 1
  fi
  mapfile -t CRATES < <(extract_release_crates)
  if [[ ${#CRATES[@]} -eq 0 ]]; then
    echo -e "${RED}ERROR${RESET}: could not extract crate list from $RELEASE_YML"
    exit 1
  fi
  echo -e "${BOLD}Cargo publish dry-run (all ${#CRATES[@]} publishable crates)${RESET}"
fi

echo

# ── Run dry-run for each crate ──────────────────────────────────────────

passed=()
failed=()

for crate in "${CRATES[@]}"; do
  echo -e "${BOLD}[$((${#passed[@]} + ${#failed[@]} + 1))/${#CRATES[@]}]${RESET} $crate ..."

  output=$(cargo publish -p "$crate" --dry-run --allow-dirty 2>&1) && rc=0 || rc=$?

  if [[ $rc -eq 0 ]]; then
    echo -e "  ${GREEN}PASS${RESET}"
    passed+=("$crate")
  else
    echo -e "  ${RED}FAIL${RESET}"
    # Show last 10 lines of output for context
    echo "$output" | tail -n 10 | sed 's/^/    /'
    failed+=("$crate")
  fi
done

echo

# ── Summary ─────────────────────────────────────────────────────────────

echo -e "${BOLD}Summary${RESET}"
echo -e "  ${GREEN}Passed: ${#passed[@]}${RESET}"
echo -e "  ${RED}Failed: ${#failed[@]}${RESET}"
echo

if [[ ${#failed[@]} -gt 0 ]]; then
  echo -e "${YELLOW}Failed crates:${RESET}"
  for crate in "${failed[@]}"; do
    echo -e "  - $crate"
  done
  echo
  echo -e "${YELLOW}Note: Some crates may fail due to path dependencies that cannot be${RESET}"
  echo -e "${YELLOW}resolved outside the workspace. This is expected for local-only crates.${RESET}"
  exit 1
fi

echo -e "${GREEN}All crates passed dry-run validation.${RESET}"
exit 0
