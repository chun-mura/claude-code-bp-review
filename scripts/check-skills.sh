#!/usr/bin/env bash
# check-skills.sh — report freshness of installed skill clones under
# ~/.claude/skills/. For each skill that has a .git directory, this runs
# `git fetch` and reports ahead/behind counts relative to @{upstream}.
#
# Does NOT pull automatically. The skill's SKILL.md instructions describe
# how to ask the user before running `git pull --ff-only`.

set -u

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
SKILLS_DIR="$CLAUDE_HOME/skills"

if [ ! -d "$SKILLS_DIR" ]; then
  echo "(no skills directory at $SKILLS_DIR)"
  exit 0
fi

printf '%-40s %-8s %-12s %s\n' "SKILL" "BEHIND" "LAST_COMMIT" "STATE"
printf '%-40s %-8s %-12s %s\n' "-----" "------" "-----------" "-----"

for d in "$SKILLS_DIR"/*/; do
  [ -d "$d/.git" ] || continue
  name="$(basename "$d")"
  if ! git -C "$d" rev-parse --abbrev-ref @{upstream} >/dev/null 2>&1; then
    printf '%-40s %-8s %-12s %s\n' "$name" "-" "-" "no-upstream"
    continue
  fi
  if ! git -C "$d" fetch --quiet 2>/dev/null; then
    printf '%-40s %-8s %-12s %s\n' "$name" "-" "-" "fetch-failed"
    continue
  fi
  behind="$(git -C "$d" rev-list --count HEAD..@{upstream} 2>/dev/null || echo "?")"
  ahead="$(git -C "$d" rev-list --count @{upstream}..HEAD 2>/dev/null || echo "?")"
  last="$(git -C "$d" log -1 --format='%as' 2>/dev/null || echo "?")"
  state="clean"
  [ "$ahead" != "0" ] && state="ahead-$ahead"
  if [ "$behind" != "0" ] && [ "$behind" != "?" ]; then
    if [ "$state" = "clean" ]; then
      state="behind"
    else
      state="${state}/behind"
    fi
  fi
  printf '%-40s %-8s %-12s %s\n' "$name" "$behind" "$last" "$state"
done
