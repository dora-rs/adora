#!/usr/bin/env bash
# scripts/qa/ci-lint.sh — lint GitHub Actions workflow files for structural issues
#
# Checks:
#   1. Checkout version: all workflows must use actions/checkout@v4
#   2. Rust version pinning: `rustup default stable` is banned;
#      dtolnay/rust-toolchain must reference ${{ env.RUST_VERSION }}
#   3. Matrix fail-fast: every strategy.matrix must have fail-fast: false
#
# Exit 0 on pass, 1 on failure.

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
  echo -e "${YELLOW}WARNING${RESET} $1"
  issues=$((issues + 1))
}

echo -e "${BOLD}CI workflow structure lint${RESET}"
echo "Scanning ${WORKFLOW_DIR}/*.yml ..."
echo

# ── Check 1: Checkout version ─────────────────────────────────────────
echo -e "${BOLD}[1/3] Checkout action version (must be @v4)${RESET}"

while IFS= read -r line; do
  file=$(echo "$line" | cut -d: -f1)
  lineno=$(echo "$line" | cut -d: -f2)
  content=$(echo "$line" | cut -d: -f3-)
  warn "  ${file}:${lineno} — outdated checkout:${content}"
done < <(grep -n 'actions/checkout@' ${WORKFLOW_DIR}/*.yml | grep -v '@v4' || true)

# ── Check 2: Rust version pinning ─────────────────────────────────────
echo -e "${BOLD}[2/3] Rust version pinning${RESET}"

# 2a. Ban `rustup default stable`
while IFS= read -r line; do
  file=$(echo "$line" | cut -d: -f1)
  lineno=$(echo "$line" | cut -d: -f2)
  warn "  ${file}:${lineno} — uses 'rustup default stable' (must pin a specific version)"
done < <(grep -n 'rustup default stable' ${WORKFLOW_DIR}/*.yml || true)

# 2b. dtolnay/rust-toolchain must use ${{ env.RUST_VERSION }}
# Find all dtolnay/rust-toolchain lines, then check the next few lines
# for toolchain: ${{ env.RUST_VERSION }}
for f in ${WORKFLOW_DIR}/*.yml; do
  while IFS= read -r lineno; do
    # Look at the next 3 lines for the toolchain directive
    toolchain_line=$(sed -n "$((lineno+1)),$((lineno+3))p" "$f" | grep 'toolchain:' || true)
    if [[ -n "$toolchain_line" ]]; then
      if ! echo "$toolchain_line" | grep -q 'env\.RUST_VERSION'; then
        warn "  ${f}:${lineno} — dtolnay/rust-toolchain does not use \${{ env.RUST_VERSION }}"
      fi
    fi
  done < <(grep -n 'dtolnay/rust-toolchain' "$f" | cut -d: -f1)
done

# ── Check 3: Matrix fail-fast ─────────────────────────────────────────
echo -e "${BOLD}[3/3] Matrix strategy fail-fast: false${RESET}"

for f in ${WORKFLOW_DIR}/*.yml; do
  while IFS= read -r lineno; do
    # Check if fail-fast appears within 3 lines after strategy:
    has_ff=$(sed -n "$((lineno+1)),$((lineno+3))p" "$f" | grep -c 'fail-fast' || true)
    if [[ "$has_ff" -eq 0 ]]; then
      warn "  ${f}:${lineno} — strategy.matrix missing 'fail-fast: false'"
    fi
  done < <(grep -n 'strategy:' "$f" | cut -d: -f1)
done

# ── Summary ────────────────────────────────────────────────────────────
echo
if [[ "$issues" -eq 0 ]]; then
  echo -e "${GREEN}${BOLD}PASS${RESET} — no workflow structure issues found"
  exit 0
else
  echo -e "${RED}${BOLD}FAIL${RESET} — ${issues} issue(s) found"
  exit 1
fi
