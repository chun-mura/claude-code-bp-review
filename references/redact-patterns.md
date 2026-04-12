# Redact Patterns

This document lists the key-name patterns that `redact.sh` treats as secrets.
When extending redaction, update both this file and the `SECRET_KEY_PATTERN`
variable in `scripts/redact.sh`, then re-run `scripts/test/test-redact.sh`.

## Philosophy

Err on the side of over-redacting. False positives (e.g., `MAX_THINKING_TOKENS`
being redacted because it contains `token`) are acceptable; under-redaction is
not. Context leakage of secrets cannot be recovered.

## Currently Matched (case-insensitive, substring match on key name)

| Pattern | Example key names that match |
|---|---|
| `key` | `apiKey`, `api_key`, `API_KEY`, `BARK_DEVICE_KEY`, `BARK_ENCRYPT_KEY`, `privateKey`, `sshKey` |
| `secret` | `secret`, `clientSecret`, `webhookSecret` |
| `password` | `password`, `dbPassword`, `DB_PASSWORD` |
| `token` | `token`, `accessToken`, `ghToken`, `bearerToken`, `MAX_THINKING_TOKENS` (false positive — acceptable) |
| `credential` | `credential`, `credentials` |
| `bearer` | `bearer`, `bearerToken` |
| `database_?url` | `DATABASE_URL`, `databaseUrl`, `database-url` |
| `(^\|_)iv(_\|$)` | `IV`, `iv`, `BARK_ENCRYPT_IV`, `enc_iv` — without matching `derivative` / `privative` |

## Not Matched (intentional)

These are considered safe because they do not commonly hold credentials and
would produce excessive false positives:

- `model`, `modelName`
- `command`, `args`
- `hooks`, `mcpServers`, `permissions`, `env` (container keys)
- `label`, `description`
- `url` alone (only `database_url` is flagged)

## Redaction Modes

- **json**: Walks the JSON tree via `jq`. For every string value whose key
  matches the pattern, the value is replaced with `"[REDACTED]"`. Non-string
  values and non-matching keys are preserved. This is the primary and
  preferred mode.

- **text**: Regex-based fallback using `sed` for non-JSON files. Only
  matches inline `"key": "value"` pairs. Less robust; prefer `json` mode
  whenever possible.

## Known Gaps

These shapes will NOT be caught by the current redaction:

- Secrets stored under keys that do not contain any of the listed substrings
  (e.g., `"endpoint": "https://user:pass@host"`). Mitigation: prefer structured
  config keys that include a recognizable suffix like `_url` or `_key`.
- Secrets embedded in free-form text (`"notes": "the api key is ..."`). This is
  outside the scope of redaction.

## Adding a New Pattern

1. Add a row to the "Currently Matched" table above.
2. Extend `SECRET_KEY_PATTERN` in `scripts/redact.sh`.
3. Add a test case to `scripts/test/fixtures/settings-with-secrets.json` that
   uses the new key name with an **obviously fake** secret value (e.g.,
   `"FAKE_..."`).
4. Regenerate `settings-redacted.expected.json`:
   ```
   bash scripts/redact.sh json scripts/test/fixtures/settings-with-secrets.json \
     > scripts/test/fixtures/settings-redacted.expected.json
   ```
5. Visually verify the expected file has the new key redacted and no other
   unintended change.
6. Add explicit `assert_not_contains` lines to `scripts/test/test-redact.sh`
   for each new fake-secret value.
7. Run `bash scripts/test/test-redact.sh` — expect all tests pass.
