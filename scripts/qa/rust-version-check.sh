#!/usr/bin/env bash
# scripts/qa/rust-version-check.sh — check Rust version pin consistency across the repo
#
# Checks:
#   1. Extract RUST_VERSION from .github/workflows/ci.yml
#   2. Extract rust-version (MSRV) from Cargo.toml [workspace.package]
#   3. Verify MSRV <= CI toolchain version
#   4. Flag any `rustup default stable` in workflow files
#   5. Flag any hardcoded version in `rustup default` calls (should use env var)
#
# Exit 0 on all checks pass, exit 1 on any failure.

set -euo pipefail

cd "$(dirname "$0")/../.."

WORKFLOW_DIR=".github/workflows"
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
  echo -e "  ${YELLOW}WARN${RESET} $1"
  issues=$((issues + 1))
}

pass() {
  echo -e "  ${GREEN}PASS${RESET} $1"
}

# Compare two semver strings: returns 0 if $1 <= $2
version_lte() {
  local IFS='.'
  read -ra a <<< "$1"
  read -ra b <<< "$2"
  for i in 0 1 2; do
    local va=${a[$i]:-0}
    local vb=${b[$i]:-0}
    if (( va < vb )); then return 0; fi
    if (( va > vb )); then return 1; fi
  done
  return 0  # equal
}

echo -e "${BOLD}Rust version pin consistency check${RESET}"
echo

# ── Check 1: Extract RUST_VERSION from ci.yml ────────────────────────
echo -e "${BOLD}[1/4] Extract CI toolchain version from ci.yml${RESET}"

CI_YML="${WORKFLOW_DIR}/ci.yml"
CI_RUST_VERSION=$(grep -E '^\s*RUST_VERSION:\s*"' "$CI_YML" | head -1 | sed 's/.*"\(.*\)".*/\1/')

if [[ -z "$CI_RUST_VERSION" ]]; then
  warn "Could not extract RUST_VERSION from ${CI_YML}"
else
  pass "RUST_VERSION = ${CI_RUST_VERSION} (from ${CI_YML})"
fi

# ── Check 2: Extract rust-version from Cargo.toml ────────────────────
echo -e "${BOLD}[2/4] Extract MSRV from Cargo.toml [workspace.package]${RESET}"

# Extract rust-version from the [workspace.package] section (not [package])
MSRV=$(sed -n '/\[workspace\.package\]/,/^\[/p' Cargo.toml | grep -E '^\s*rust-version\s*=' | head -1 | sed 's/.*"\(.*\)".*/\1/')

if [[ -z "$MSRV" ]]; then
  warn "Could not extract rust-version from Cargo.toml [workspace.package]"
else
  pass "MSRV = ${MSRV} (from Cargo.toml [workspace.package])"
fi

# ── Check 3: MSRV <= CI toolchain ────────────────────────────────────
echo -e "${BOLD}[3/4] MSRV <= CI toolchain version${RESET}"

if [[ -n "$CI_RUST_VERSION" && -n "$MSRV" ]]; then
  if version_lte "$MSRV" "$CI_RUST_VERSION"; then
    pass "${MSRV} <= ${CI_RUST_VERSION}"
  else
    warn "MSRV ${MSRV} is greater than CI toolchain ${CI_RUST_VERSION} — CI will fail MSRV builds"
  fi
else
  warn "Skipped — could not extract one or both versions"
fi

# ── Check 4: Scan workflows for rustup default issues ────────────────
echo -e "${BOLD}[4/4] Scan workflow files for rustup default issues${RESET}"

# 4a. Flag `rustup default stable`
while IFS= read -r line; do
  file=$(echo "$line" | cut -d: -f1)
  lineno=$(echo "$line" | cut -d: -f2)
  warn "${file}:${lineno} — uses 'rustup default stable' (should pin a specific version)"
done < <(grep -rn 'rustup default stable' ${WORKFLOW_DIR}/*.yml || true)

# 4b. Flag hardcoded version in `rustup default` (e.g., `rustup default 1.92.0`)
# Matches lines like `rustup default 1.XX.X` but NOT lines using ${{ env.RUST_VERSION }}
while IFS= read -r line; do
  file=$(echo "$line" | cut -d: -f1)
  lineno=$(echo "$line" | cut -d: -f2)
  content=$(echo "$line" | cut -d: -f3-)
  # Skip if it references env.RUST_VERSION or a variable expansion
  if echo "$content" | grep -qE '\$\{\{|env\.RUST_VERSION'; then
    continue
  fi
  warn "${file}:${lineno} — hardcoded version in 'rustup default':${content}"
done < <(grep -rn -E 'rustup default [0-9]+\.[0-9]+' ${WORKFLOW_DIR}/*.yml || true)

# ── Summary ───────────────────────────────────────────────────────────
echo
if [[ "$issues" -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}PASS${RESET} — all Rust version pins are consistent"
  exit 0
else
  echo -e "${RED}${BOLD}FAIL${RESET} — ${issues} issue(s) found"
  exit 1
fi
