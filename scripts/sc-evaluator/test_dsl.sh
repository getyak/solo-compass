#!/usr/bin/env bash
# scripts/sc-evaluator/test_dsl.sh — DSL validation tests.
#
# Unit-style tests for the journey DSL. Verifies that invoking run.sh with a
# journey containing an unknown step name exits non-zero AND prints the
# offending step. Also covers the missing-required-arg case.
#
# Exits 0 when all tests pass, 1 otherwise.

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_SH="$SCRIPT_DIR/run.sh"
JOURNEYS_DIR="$SCRIPT_DIR/journeys"

FAILURES=0

mkfix() {
  local name="$1" body="$2"
  printf "%s" "$body" > "$JOURNEYS_DIR/${name}.yml"
}

cleanup() {
  rm -f "$JOURNEYS_DIR/_dsl-test-"*.yml
}
trap cleanup EXIT

assert_invalid() {
  local label="$1" name="$2" expect_match="$3"
  local out rc tmp
  tmp="$(mktemp)"
  "$RUN_SH" "$name" --no-build >"$tmp" 2>&1
  rc=$?
  out="$(cat "$tmp")"
  rm -f "$tmp"
  if [[ "$rc" -eq 0 ]]; then
    echo "FAIL [$label]: expected non-zero exit, got $rc" >&2
    echo "$out" | sed 's/^/    /' >&2
    FAILURES=$((FAILURES + 1))
    return
  fi
  if ! grep -qF "$expect_match" <<< "$out"; then
    echo "FAIL [$label]: stderr did not mention '$expect_match'" >&2
    echo "$out" | sed 's/^/    /' >&2
    FAILURES=$((FAILURES + 1))
    return
  fi
  echo "PASS [$label]"
}

# --- test 1: unknown step name ---
mkfix "_dsl-test-unknown-step" "$(cat <<'YAML'
steps:
  - launch:
  - taap:
      accessibilityId: "chat.openButton"
YAML
)"
assert_invalid "unknown-step" "_dsl-test-unknown-step" "taap"

# --- test 2: missing required arg ---
mkfix "_dsl-test-missing-arg" "$(cat <<'YAML'
steps:
  - launch:
  - screenshot: {}
YAML
)"
assert_invalid "missing-arg" "_dsl-test-missing-arg" "screenshot"

# --- test 3: tap with neither coords nor accessibilityId ---
mkfix "_dsl-test-tap-empty" "$(cat <<'YAML'
steps:
  - tap: {}
YAML
)"
assert_invalid "tap-empty" "_dsl-test-tap-empty" "tap"

# --- test 4: tap with both coords AND accessibilityId ---
mkfix "_dsl-test-tap-both" "$(cat <<'YAML'
steps:
  - tap:
      x: 100
      y: 200
      accessibilityId: "btn"
YAML
)"
assert_invalid "tap-both" "_dsl-test-tap-both" "tap"

if [[ "$FAILURES" -gt 0 ]]; then
  echo "${FAILURES} test(s) failed" >&2
  exit 1
fi
echo "all DSL tests passed"
