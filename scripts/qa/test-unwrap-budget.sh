#!/usr/bin/env bash
# scripts/qa/test-unwrap-budget.sh — regression test for unwrap-budget counting logic
#
# Creates a temporary Rust project with known .unwrap()/.expect() placements,
# runs the same counting pipeline used by unwrap-budget.sh, and asserts the
# result matches the expected count.
#
# Expected count: 5 (3 from lib.rs production code + 2 from helper.rs)
# Excluded: tests/ dir, examples/ dir, build.rs, tests.rs files, code after #[cfg(test)]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ── helpers ──────────────────────────────────────────────────────────────────

cleanup() { [[ -n "${TMP_DIR:-}" ]] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT

pass() { printf '\033[32mPASS\033[0m %s\n' "$1"; }
fail() { printf '\033[31mFAIL\033[0m %s\n' "$1"; EXIT_CODE=1; }

EXIT_CODE=0

# ── create fixture project ───────────────────────────────────────────────────

TMP_DIR="$(mktemp -d)"

mkdir -p "$TMP_DIR/src/inner" "$TMP_DIR/tests" "$TMP_DIR/examples"

# src/lib.rs — 3 production unwraps, then #[cfg(test)] with 5 (should not count)
cat > "$TMP_DIR/src/lib.rs" <<'RUST'
pub fn a() {
    let x = Some(1).unwrap();
    let y = Some(2).unwrap();
    let z = Some(3).expect("three");
}

#[cfg(test)]
mod tests {
    fn t1() { Some(1).unwrap(); }
    fn t2() { Some(2).unwrap(); }
    fn t3() { Some(3).unwrap(); }
    fn t4() { Some(4).unwrap(); }
    fn t5() { Some(5).unwrap(); }
}
RUST

# src/helper.rs — 2 production unwraps, no test section
cat > "$TMP_DIR/src/helper.rs" <<'RUST'
pub fn b() {
    let a = Some(10).unwrap();
    let b = Some(20).expect("twenty");
}
RUST

# src/inner/tests.rs — 10 unwraps (excluded: file named tests.rs)
cat > "$TMP_DIR/src/inner/tests.rs" <<'RUST'
fn t() {
    Some(1).unwrap();
    Some(2).unwrap();
    Some(3).unwrap();
    Some(4).unwrap();
    Some(5).unwrap();
    Some(6).unwrap();
    Some(7).unwrap();
    Some(8).unwrap();
    Some(9).unwrap();
    Some(10).unwrap();
}
RUST

# tests/integration.rs — 7 unwraps (excluded: under tests/ dir)
cat > "$TMP_DIR/tests/integration.rs" <<'RUST'
fn t() {
    Some(1).unwrap();
    Some(2).unwrap();
    Some(3).unwrap();
    Some(4).unwrap();
    Some(5).unwrap();
    Some(6).unwrap();
    Some(7).unwrap();
}
RUST

# examples/demo.rs — 4 unwraps (excluded: under examples/ dir)
cat > "$TMP_DIR/examples/demo.rs" <<'RUST'
fn main() {
    Some(1).unwrap();
    Some(2).unwrap();
    Some(3).unwrap();
    Some(4).unwrap();
}
RUST

# build.rs — 2 unwraps (excluded: build script)
cat > "$TMP_DIR/build.rs" <<'RUST'
fn main() {
    Some(1).unwrap();
    Some(2).unwrap();
}
RUST

# ── counting logic (same pipeline as unwrap-budget.sh) ───────────────────────
#
# The only difference from unwrap-budget.sh is that we scan the temp dir
# instead of the repo's libraries/ binaries/ apis/ directories.

count_unwraps() {
  local dir="$1"
  local total=0
  local file
  while IFS= read -r file; do
    # Rule 2: drop test submodule files
    case "$file" in
      */tests.rs) continue ;;
    esac
    # Rule 3: truncate at first #[cfg(test)] line, count unwraps in head
    local n
    n=$(awk '
      /^[[:space:]]*#\[cfg\(test\)\]/ { exit }
      {
        n = gsub(/\.unwrap\(\)|\.expect\(/, "&")
        if (n > 0) count += n
      }
      END { print count + 0 }
    ' "$file")
    total=$((total + n))
  done < <(
    rg --files --type rust \
      -g '!**/tests/**' \
      -g '!**/benches/**' \
      -g '!**/examples/**' \
      -g '!**/build.rs' \
      "$dir" 2>/dev/null
  )
  echo "$total"
}

# ── assertions ───────────────────────────────────────────────────────────────

EXPECTED=5
ACTUAL=$(count_unwraps "$TMP_DIR")

echo "=== unwrap-budget counting logic regression test ==="
echo "Expected: $EXPECTED"
echo "Actual:   $ACTUAL"
echo

if [[ "$ACTUAL" -eq "$EXPECTED" ]]; then
  pass "total unwrap count matches expected ($EXPECTED)"
else
  fail "total unwrap count mismatch: expected $EXPECTED, got $ACTUAL"
fi

# ── edge-case: cfg(test) with leading whitespace ─────────────────────────────

cat > "$TMP_DIR/src/lib.rs" <<'RUST'
pub fn c() {
    let x = Some(1).unwrap();
}

  #[cfg(test)]
mod tests {
    fn t() { Some(1).unwrap(); Some(2).unwrap(); }
}
RUST

EXPECTED_EDGE=1
ACTUAL_EDGE=$(count_unwraps "$TMP_DIR")
# helper.rs still has 2, lib.rs now has 1 => 3 total
EXPECTED_EDGE=3

echo "--- edge case: #[cfg(test)] with leading whitespace ---"
echo "Expected: $EXPECTED_EDGE"
echo "Actual:   $ACTUAL_EDGE"

if [[ "$ACTUAL_EDGE" -eq "$EXPECTED_EDGE" ]]; then
  pass "leading-whitespace cfg(test) correctly truncates"
else
  fail "leading-whitespace cfg(test) not handled: expected $EXPECTED_EDGE, got $ACTUAL_EDGE"
fi

echo
if [[ "$EXIT_CODE" -eq 0 ]]; then
  echo "All assertions passed."
else
  echo "Some assertions failed."
fi

exit "$EXIT_CODE"
