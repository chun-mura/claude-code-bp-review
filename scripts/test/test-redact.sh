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
json_nested=$(mktemp)
json_nested_out=$(mktemp)
text_in=$(mktemp)
text_out=$(mktemp)
trap 'rm -f "$tmp" "$json_nested" "$json_nested_out" "$text_in" "$text_out"' EXIT

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

# Test 5: JSON subtree redaction — object/array values under secret-named
# keys must be fully redacted, not just string values.
cat > "$json_nested" <<'EOF'
{
  "credentials": {
    "pass": "FAKE_NESTED_SECRET"
  },
  "tokens": [
    "FAKE_ARRAY_TOKEN"
  ],
  "apiKeys": {
    "prod": "FAKE_PROD_KEY"
  }
}
EOF
"$REDACT" json "$json_nested" > "$json_nested_out"
assert_not_contains "nested object under credentials leaked" "$json_nested_out" "FAKE_NESTED_SECRET"
assert_not_contains "string array under tokens leaked" "$json_nested_out" "FAKE_ARRAY_TOKEN"
assert_not_contains "object under apiKeys leaked" "$json_nested_out" "FAKE_PROD_KEY"
assert_contains "marker present for nested subtree redaction" "$json_nested_out" "\[REDACTED\]"

# Test 6: text mode — "key": "value" pairs are redacted, including the iv pattern.
cat > "$text_in" <<'EOF'
some notes
"apiKey": "FAKE_TEXT_KEY"
"enc_iv": "FAKE_TEXT_IV"
"password": "FAKE_TEXT_PW"
"derivative": "NOT_A_SECRET"
EOF
"$REDACT" text "$text_in" > "$text_out"
assert_not_contains "text mode apiKey leaked" "$text_out" "FAKE_TEXT_KEY"
assert_not_contains "text mode enc_iv leaked" "$text_out" "FAKE_TEXT_IV"
assert_not_contains "text mode password leaked" "$text_out" "FAKE_TEXT_PW"
assert_contains "text mode derivative not redacted" "$text_out" "NOT_A_SECRET"

echo
echo "Result: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
