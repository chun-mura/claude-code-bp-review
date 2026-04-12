#!/usr/bin/env bash
# redact.sh — secret redaction helper for bp-review.
#
# Modes:
#   json <path>   Redact a JSON file using jq. Replaces values for any key
#                 whose name (case-insensitive) matches a secret pattern
#                 with the literal string "[REDACTED]".
#   text <path>   Regex-based fallback for non-JSON files.
#
# Philosophy: err on the side of over-redacting. False positives (e.g.,
# MAX_THINKING_TOKENS being redacted because it contains "token") are
# acceptable; under-redaction is not.
#
# Exit codes: 0 on success, non-zero on error.

set -euo pipefail

# Case-insensitive substring patterns that flag a key as a secret.
# Keep in sync with references/redact-patterns.md.
#
# Components:
#   key            — catches anything containing "key" (apiKey, privateKey,
#                    BARK_DEVICE_KEY, BARK_ENCRYPT_KEY, etc.)
#   secret         — secret, clientSecret
#   password       — password, dbPassword
#   token          — token, accessToken, bearerToken, MAX_THINKING_TOKENS (fp)
#   credential     — credential, credentials
#   bearer         — bearer (Authorization: Bearer ...)
#   database_?url  — DATABASE_URL, databaseUrl
#   (^|_)iv(_|$)   — IV as word-ish boundary (BARK_ENCRYPT_IV, initIv, IV)
#                    without matching "privative" / "derivative".
SECRET_KEY_PATTERN='key|secret|password|token|credential|bearer|database_?url|(^|_)iv(_|$)'

redact_json() {
  local file="$1"
  if ! command -v jq >/dev/null 2>&1; then
    echo "redact.sh: jq is required for json mode" >&2
    return 2
  fi
  jq --arg pat "$SECRET_KEY_PATTERN" '
    def redact_walk:
      if type == "object" then
        with_entries(
          if (.key | test($pat; "i")) and (.value | type == "string")
          then .value = "[REDACTED]"
          else .value |= redact_walk
          end
        )
      elif type == "array" then
        map(redact_walk)
      else
        .
      end;
    redact_walk
  ' "$file"
}

redact_text() {
  local file="$1"
  # Fallback: regex match on `"key": "value"` where key contains any of
  # the sensitive substrings. Less robust than json mode.
  sed -E 's/("([^"]*([kK][eE][yY]|[sS][eE][cC][rR][eE][tT]|[pP][aA][sS][sS][wW][oO][rR][dD]|[tT][oO][kK][eE][nN]|[cC][rR][eE][dD][eE][nN][tT][iI][aA][lL]|[bB][eE][aA][rR][eE][rR]|[dD][aA][tT][aA][bB][aA][sS][eE]_?[uU][rR][lL])[^"]*)"[[:space:]]*:[[:space:]]*")[^"]*/\1[REDACTED]/g' "$file"
}

usage() {
  cat >&2 <<EOF
Usage: $0 json <file>
       $0 text <file>
EOF
  exit 2
}

if [ "$#" -ne 2 ]; then usage; fi

case "$1" in
  json) redact_json "$2" ;;
  text) redact_text "$2" ;;
  *)    usage ;;
esac
