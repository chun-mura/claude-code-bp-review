#!/usr/bin/env bash
# nudge.sh — SessionStart nudge hook for bp-review.
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
# Probe GNU stat first with -c %Y (prints modification time in seconds);
# on macOS/BSD, -c is rejected, so we fall back to BSD stat -f %m.
# On Linux, -f is a filesystem mode where %m is not a valid directive and
# may exit 0 while printing garbage, so we must probe GNU first.
if ! mtime=$(stat -c %Y "$STAMP" 2>/dev/null); then
  mtime=$(stat -f %m "$STAMP")
fi
# Validate mtime is a number; if unparseable, stay silent rather than crash.
case "$mtime" in
  ''|*[!0-9]*) exit 0 ;;
esac

age_days=$(( (now - mtime) / 86400 ))

if [ "$age_days" -ge "$NUDGE_DAYS" ]; then
  echo "bp-review: last checked ${age_days} days ago — consider running /bp-review"
fi
exit 0
