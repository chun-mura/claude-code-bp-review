#!/usr/bin/env bash
# Tests for redact.sh — runs without bats/external deps.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$SCRIPT_DIR/test/fixtures"
REDACT="$SCRIPT_DIR/redact.sh"

pass=0
fail=0

assert_equal_files() {
  local label="$1" actual="$2" expected="$3"
  if diff -u "$expected" "$actual" > /dev/null; then
    echo "PASS: $label"
    pass=$((pass + 1))
  else
    echo "FAIL: $label"
    diff -u "$expected" "$actual" || true
    fail=$((fail + 1))
  fi
}

assert_contains() {
  local label="$1" file="$2" needle="$3"
  if grep -q -- "$needle" "$file"; then
    echo "PASS: $label"
    pass=$((pass + 1))
  else
    echo "FAIL: $label (needle '$needle' not found in $file)"
    fail=$((fail + 1))
  fi
}

assert_not_contains() {
  local label="$1" file="$2" needle="$3"
  if grep -q -- "$needle" "$file"; then
    echo "FAIL: $label (forbidden needle '$needle' found in $file)"
    fail=$((fail + 1))
  else
    echo "PASS: $label"
    pass=$((pass + 1))
  fi
}

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

# Test 1: JSON redaction produces expected output
"$REDACT" json "$FIXTURES/settings-with-secrets.json" > "$tmp"
assert_equal_files "json redaction matches expected" "$tmp" "$FIXTURES/settings-redacted.expected.json"

# Test 2: Redacted output contains [REDACTED] markers
assert_contains "marker present for apiKey" "$tmp" "\[REDACTED\]"

# Test 3: No raw secret substrings leak through
assert_not_contains "raw sk-live leaked" "$tmp" "sk-live-abcdef"
assert_not_contains "raw ghp_ token leaked" "$tmp" "ghp_example"
assert_not_contains "raw password leaked" "$tmp" "hunter2"
assert_not_contains "raw db password leaked" "$tmp" "p@ssw0rd"
assert_not_contains "FAKE BARK device key leaked" "$tmp" "FAKE_DEVICE_KEY"
assert_not_contains "FAKE BARK encrypt key leaked" "$tmp" "FAKE_ENCRYPT_KEY"
assert_not_contains "FAKE BARK IV leaked" "$tmp" "FAKE_IV"
assert_not_contains "private key marker leaked" "$tmp" "BEGIN RSA PRIVATE KEY"

# Test 4: Non-secret fields preserved
assert_contains "model preserved" "$tmp" "claude-opus-4-6"
assert_contains "hook command preserved" "$tmp" "bark-notify.sh"
assert_contains "CLAUDE_CODE_NO_FLICKER preserved" "$tmp" "CLAUDE_CODE_NO_FLICKER"
assert_contains "ENABLE_TOOL_SEARCH preserved" "$tmp" "ENABLE_TOOL_SEARCH"

echo
echo "Result: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
