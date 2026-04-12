#!/usr/bin/env bash
# collect-local.sh — gather a redacted snapshot of ~/.claude/ for bp-review.
#
# Output is printed to stdout in labeled sections. The caller (SKILL.md
# instructions) pipes this into a temp file and references it during
# analysis. No file paths from ~/.claude/ except those explicitly handled
# below should ever be included.

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REDACT="$SCRIPT_DIR/redact.sh"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"

section() { printf '\n===== %s =====\n' "$1"; }

section "CLAUDE.md"
if [ -f "$CLAUDE_HOME/CLAUDE.md" ]; then
  if grep -E -i '(api[_-]?key|token|secret|password)[[:space:]]*[:=][[:space:]]*[^[:space:]]' "$CLAUDE_HOME/CLAUDE.md" >/dev/null; then
    echo "(blocked: CLAUDE.md appears to contain secret-shaped content — aborting to avoid leakage)"
    exit 3
  fi
  cat "$CLAUDE_HOME/CLAUDE.md"
else
  echo "(absent)"
fi

section "settings.json (redacted)"
if [ -f "$CLAUDE_HOME/settings.json" ]; then
  "$REDACT" json "$CLAUDE_HOME/settings.json"
else
  echo "(absent)"
fi

section "hooks/"
if [ -d "$CLAUDE_HOME/hooks" ]; then
  for f in "$CLAUDE_HOME"/hooks/*; do
    [ -f "$f" ] || continue
    printf -- '- %s\n' "$(basename "$f")"
    head -n 1 "$f" | sed 's/^/    shebang: /'
  done
else
  echo "(absent)"
fi

section "skills/"
if [ -d "$CLAUDE_HOME/skills" ]; then
  for d in "$CLAUDE_HOME"/skills/*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    printf -- '- %s\n' "$name"
    if [ -f "$d/SKILL.md" ]; then
      awk '/^---/{c++; next} c==1{print "    " $0} c>1{exit}' "$d/SKILL.md"
    fi
  done
else
  echo "(absent)"
fi

section "plugins/"
if [ -d "$CLAUDE_HOME/plugins" ]; then
  ls -1 "$CLAUDE_HOME/plugins" 2>/dev/null || echo "(empty)"
else
  echo "(absent)"
fi
