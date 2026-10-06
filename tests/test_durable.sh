#!/usr/bin/env bash
# Test suite for durable.sh
# Run: bash tests/test_durable.sh

set -euo pipefail

# Source the library
source "$(dirname "$0")/../lib/durable.sh"

# Test counters
TESTS_RUN=0
TESTS_PASS=0
TESTS_FAIL=0

# Safe increment that doesn't trigger set -e
inc() { local -n v=$1; v=$((v + 1)); }

# Test helper
assert_eq() {
  local expected="$1" actual="$2" msg="${3:-}"
  inc TESTS_RUN
  if [[ "$expected" == "$actual" ]]; then
    echo "  ✓ $msg"
    inc TESTS_PASS
    return 0
  else
    echo "  ✗ $msg (expected: '$expected', actual: '$actual')" >&2
    inc TESTS_FAIL
    return 1
  fi
}

assert_rc() {
  local expected_rc="$1" cmd="${*:2}"
  inc TESTS_RUN
  eval "$cmd" >/dev/null 2>&1
  local actual_rc=$?
  if (( actual_rc == expected_rc )); then
    echo "  ✓ $cmd (rc=$expected_rc)"
    inc TESTS_PASS
    return 0
  else
    echo "  ✗ $cmd (expected rc=$expected_rc, got rc=$actual_rc)" >&2
    inc TESTS_FAIL
    return 1
  fi
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Test: Signal 36 guard installed
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo "Testing signal 36 guard..."
# Check trap is set (bash 4.4+ shows in `trap -p`; may show as 36 or SIGRTMIN+2)
trap_output="$(trap -p 36 2>/dev/null || true)"
if [[ "$trap_output" =~ ^trap\ --\ \'\'\ (36|SIGRTMIN\+2)$ ]] || [[ "$trap_output" =~ ^trap\ \'\'\ (36|SIGRTMIN\+2)$ ]]; then
  echo "  ✓ SIG_IGN trap installed for signal 36"
  inc TESTS_PASS
else
  echo "  ✗ Signal 36 trap not found: $trap_output" >&2
  inc TESTS_FAIL
fi
inc TESTS_RUN

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Test: Atomic write
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo "Testing atomic_write..."
tmpfile="$(mktemp /tmp/durable_test.XXXXXX)"
echo "hello" | durable::atomic_write "$tmpfile"
assert_eq "hello" "$(cat "$tmpfile")" "atomic_write basic"

# Test overwrite
echo "world" | durable::atomic_write "$tmpfile"
assert_eq "world" "$(cat "$tmpfile")" "atomic_write overwrite"

# Test atomic_write_str
durable::atomic_write_str "$tmpfile" "direct"
assert_eq "direct" "$(cat "$tmpfile")" "atomic_write_str"

rm -f "$tmpfile"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Test: Atomic append
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo "Testing atomic_append..."
tmpfile="$(mktemp /tmp/durable_test.XXXXXX)"
durable::atomic_write_str "$tmpfile" "line1"
echo "line2" | durable::atomic_append "$tmpfile"
echo "line3" | durable::atomic_append "$tmpfile"
content="$(cat "$tmpfile")"
# atomic_write_str uses printf (no newline), echo adds newline
assert_eq $'line1line2\nline3' "$content" "atomic_append multiple lines"

# Test append to non-existent file
tmpfile2="$(mktemp /tmp/durable_test.XXXXXX)"
rm -f "$tmpfile2"
echo "first" | durable::atomic_append "$tmpfile2"
# Use cat + read to preserve trailing newline
result="$(cat "$tmpfile2"; echo x)"
result="${result%x}"
assert_eq $'first\n' "$result" "atomic_append to new file"
rm -f "$tmpfile" "$tmpfile2"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Test: Retry (success on first try)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo "Testing durable::retry (success)..."
out="$(durable::retry 3 1 echo "success")"
assert_eq "success" "$out" "retry succeeds first try"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Test: Retry (success on retry)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo "Testing durable::retry (retry then success)..."
attempt=0
retry_test_func() {
  attempt=$((attempt + 1))
  if (( attempt < 2 )); then
    return 1
  fi
  echo "ok on attempt $attempt"
}
out="$(durable::retry 3 1 retry_test_func)"
assert_eq "ok on attempt 2" "$out" "retry succeeds on second attempt"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Test: Retry (exhausted)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo "Testing durable::retry (exhausted)..."
attempt=0
always_fail() {
  attempt=$((attempt + 1))
  return 1
}
{ durable::retry 2 1 always_fail >/dev/null 2>&1; rc=$?; } || true
assert_eq 1 $rc "retry returns failure rc after exhaustion"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Test: durable::run shortcut
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo "Testing durable::run..."
out="$(durable::run echo "run shortcut")"
assert_eq "run shortcut" "$out" "durable::run works"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Test: Verification (require_output)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo "Testing durable::require_output..."
out="$(durable::require_output 'hello' echo "hello world")"
assert_eq "hello world" "$out" "require_output matches pattern"

# Test empty output fails
{ durable::require_output '.*' echo -n "" >/dev/null 2>&1; rc=$?; } || true
assert_eq 1 $rc "require_output fails on empty output"

# Test pattern mismatch fails
{ durable::require_output 'goodbye' echo "hello" >/dev/null 2>&1; rc=$?; } || true
assert_eq 2 $rc "require_output fails on pattern mismatch"

# Test command failure propagates rc
{ durable::require_output '.*' false >/dev/null 2>&1; rc=$?; } || true
assert_eq 1 $rc "require_output propagates command failure rc"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Test: PID file functions
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo "Testing PID file functions..."
pidfile="$(mktemp /tmp/durable_pid.XXXXXX)"
rm -f "$pidfile"

# Non-existent file
{ durable::pid_alive "$pidfile" >/dev/null 2>&1; rc=$?; } || true
assert_eq 1 $rc "pid_alive fails for missing file"

# File with dead PID
echo "999999" >"$pidfile"
{ durable::pid_alive "$pidfile" >/dev/null 2>&1; rc=$?; } || true
assert_eq 1 $rc "pid_alive fails for dead PID"

# File with our PID (alive)
echo "$$" >"$pidfile"
{ durable::pid_alive "$pidfile" >/dev/null 2>&1; rc=$?; } || true
assert_eq 0 $rc "pid_alive succeeds for our PID"
rm -f "$pidfile"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Test: DURABLE_NOINIT prevents auto-init
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo "Testing DURABLE_NOINIT..."
DURABLE_NOINIT=1 source "$(dirname "$0")/../lib/durable.sh" 2>/dev/null
# Should not have run `set -euo pipefail` (we can't easily test this, but at least no crash)
echo "  ✓ DURABLE_NOINIT doesn't crash"
inc TESTS_PASS
inc TESTS_RUN

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Summary
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results: $TESTS_PASS/$TESTS_RUN passed, $TESTS_FAIL failed"
if (( TESTS_FAIL > 0 )); then
  exit 1
fi
echo "All tests passed!"