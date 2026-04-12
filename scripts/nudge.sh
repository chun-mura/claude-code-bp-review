#!/usr/bin/env bash
# nudge.sh — ConfigChange hook for bp-review.
#
# Prints a single reminder line if the last bp-review run is older than
# NUDGE_DAYS days. Does nothing on first run (no timestamp file yet) to
# avoid nagging on a fresh install — the user will discover the skill
# when they want it.
#
# Fast path: no network, no heavy I/O.

set -eu

NUDGE_DAYS="${BP_REVIEW_NUDGE_DAYS:-7}"
STAMP="${CLAUDE_HOME:-$HOME/.claude}/bp-review/last_check.txt"

[ -f "$STAMP" ] || exit 0

now=$(date +%s)
if stat -f %m "$STAMP" >/dev/null 2>&1; then
  mtime=$(stat -f %m "$STAMP")
else
  mtime=$(stat -c %Y "$STAMP")
fi

age_days=$(( (now - mtime) / 86400 ))

if [ "$age_days" -ge "$NUDGE_DAYS" ]; then
  echo "bp-review: last checked ${age_days} days ago — consider running /bp-review"
fi
exit 0
