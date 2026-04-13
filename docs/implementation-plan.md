# bp-review Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a personal global Claude Code skill `bp-review` that audits `~/.claude/` against the latest official best-practice docs and user-curated sources, producing a report + draft patches without touching originals.

**Architecture:** A small shell-script-based skill under `~/.claude/skills/bp-review/`. The skill orchestrates via `SKILL.md` (instructions to Claude), with helper shell scripts for the mechanical parts (redact, collect, check-skills). Secrets are redacted before any file contents enter the model's context. Draft patches are written to a separate runtime directory (`~/.claude/bp-review/`) that is cleanly isolated from the skill package.

**Tech Stack:**
- Bash 3.2+ (macOS default — no bash 4 features)
- `jq` for JSON redaction
- `sed` / `grep` for text redaction
- `git` for skill-clone freshness checks
- Claude Code WebFetch tool for remote fetching (driven by SKILL.md instructions)

**Spec reference:** `~/.claude/plans/2026-04-12-bp-review-design.md`

**Important handling:**
- `~/.claude/settings.json` may contain secrets. Any task that reads it MUST pipe through `scripts/redact.sh` first. Task 10 (hook registration) requires **explicit user permission** before running — never modify `settings.json` without confirmation.

---

## File Structure

```
~/.claude/skills/bp-review/
├── SKILL.md                           # Claude-facing skill instructions
├── sources.yml                        # Official URLs + user extensions
├── README.md                          # Human-facing overview + operational notes
├── scripts/
│   ├── redact.sh                      # JSON/text secret redaction
│   ├── collect-local.sh               # Gather redacted local config snapshot
│   ├── check-skills.sh                # git fetch + ahead/behind for ~/.claude/skills/*
│   └── test/
│       ├── test-redact.sh             # Shell-level tests for redact.sh
│       └── fixtures/
│           ├── settings-with-secrets.json
│           └── settings-redacted.expected.json
└── references/
    └── redact-patterns.md             # Canonical redact rules

~/.claude/hooks/
└── bp-review-nudge.sh                 # SessionStart hook: stale reminder

~/.claude/bp-review/                    # Runtime artifacts (created on first run)
├── .gitignore                         # Ignore everything — pure scratch space
├── last_check.txt                     # Timestamp (touched by skill; read by hook)
├── reports/                           # <YYYY-MM-DD>.md reports go here
└── proposed/                          # <file>.proposed draft patches go here
```

---

## Task 1: Create directory skeleton

**Files:**
- Create: `~/.claude/skills/bp-review/` (dir)
- Create: `~/.claude/skills/bp-review/scripts/` (dir)
- Create: `~/.claude/skills/bp-review/scripts/test/` (dir)
- Create: `~/.claude/skills/bp-review/scripts/test/fixtures/` (dir)
- Create: `~/.claude/skills/bp-review/references/` (dir)
- Create: `~/.claude/bp-review/` (dir)
- Create: `~/.claude/bp-review/reports/` (dir)
- Create: `~/.claude/bp-review/proposed/` (dir)

- [ ] **Step 1: Verify parent directory exists**

Run: `test -d ~/.claude/skills && echo OK`
Expected: `OK`

- [ ] **Step 2: Create skill package directories**

Run:
```bash
mkdir -p ~/.claude/skills/bp-review/scripts/test/fixtures \
         ~/.claude/skills/bp-review/references \
         ~/.claude/bp-review/reports \
         ~/.claude/bp-review/proposed
```

- [ ] **Step 3: Verify tree**

Run: `find ~/.claude/skills/bp-review ~/.claude/bp-review -type d | sort`
Expected (each on its own line):
```
~/.claude/bp-review
~/.claude/bp-review/proposed
~/.claude/bp-review/reports
~/.claude/skills/bp-review
~/.claude/skills/bp-review/references
~/.claude/skills/bp-review/scripts
~/.claude/skills/bp-review/scripts/test
~/.claude/skills/bp-review/scripts/test/fixtures
```
(Paths will be expanded to absolute paths by `find`.)

- [ ] **Step 4: Create `.gitignore` in runtime dir**

Create file `~/.claude/bp-review/.gitignore`:
```
*
!.gitignore
```

- [ ] **Step 5: Commit note (no repo yet — skip commit)**

Since the skill package is not yet a git repo, defer commit to Task 12. Just verify the tree again and move on.

---

## Task 2: Write redact.sh test fixtures (TDD)

**Files:**
- Create: `~/.claude/skills/bp-review/scripts/test/fixtures/settings-with-secrets.json`
- Create: `~/.claude/skills/bp-review/scripts/test/fixtures/settings-redacted.expected.json`

- [ ] **Step 1: Create input fixture with realistic secret shapes**

Create file `~/.claude/skills/bp-review/scripts/test/fixtures/settings-with-secrets.json`:
```json
{
  "model": "claude-opus-4-6",
  "hooks": {
    "SessionStart": [
      { "command": "bash ~/.claude/hooks/bark-notify.sh" }
    ]
  },
  "mcpServers": {
    "example": {
      "command": "npx",
      "args": ["-y", "example-mcp"],
      "env": {
        "EXAMPLE_API_KEY": "sk-live-abcdef1234567890",
        "OPENAI_API_KEY": "sk-proj-xxxxxxxx",
        "DATABASE_URL": "postgres://user:p@ssw0rd@host/db"
      }
    }
  },
  "apiKey": "top-secret-123",
  "token": "ghp_exampleexampleexampleexample",
  "secret": "shhhh",
  "password": "hunter2"
}
```

- [ ] **Step 2: Create expected-output fixture**

Create file `~/.claude/skills/bp-review/scripts/test/fixtures/settings-redacted.expected.json`:
```json
{
  "model": "claude-opus-4-6",
  "hooks": {
    "SessionStart": [
      {
        "command": "bash ~/.claude/hooks/bark-notify.sh"
      }
    ]
  },
  "mcpServers": {
    "example": {
      "command": "npx",
      "args": [
        "-y",
        "example-mcp"
      ],
      "env": {
        "EXAMPLE_API_KEY": "[REDACTED]",
        "OPENAI_API_KEY": "[REDACTED]",
        "DATABASE_URL": "[REDACTED]"
      }
    }
  },
  "apiKey": "[REDACTED]",
  "token": "[REDACTED]",
  "secret": "[REDACTED]",
  "password": "[REDACTED]"
}
```

Note: `jq` pretty-printing uses 2-space indent by default; the expected file matches that.

---

## Task 3: Write test-redact.sh (failing test)

**Files:**
- Create: `~/.claude/skills/bp-review/scripts/test/test-redact.sh`

- [ ] **Step 1: Write the failing test**

Create file `~/.claude/skills/bp-review/scripts/test/test-redact.sh`:
```bash
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
assert_contains "marker present for apiKey" "$tmp" "[REDACTED]"

# Test 3: No raw secret substrings leak through
assert_not_contains "raw sk-live leaked" "$tmp" "sk-live-abcdef"
assert_not_contains "raw ghp_ token leaked" "$tmp" "ghp_example"
assert_not_contains "raw password leaked" "$tmp" "hunter2"
assert_not_contains "raw db password leaked" "$tmp" "p@ssw0rd"

# Test 4: Non-secret fields preserved
assert_contains "model preserved" "$tmp" "claude-opus-4-6"
assert_contains "hook command preserved" "$tmp" "bark-notify.sh"

echo
echo "Result: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x ~/.claude/skills/bp-review/scripts/test/test-redact.sh`

- [ ] **Step 3: Run it to verify it fails (redact.sh does not exist yet)**

Run: `bash ~/.claude/skills/bp-review/scripts/test/test-redact.sh 2>&1 | tail -5`
Expected: failure — output contains something like `redact.sh: No such file or directory` and a non-zero exit.

---

## Task 4: Write redact.sh (make the test pass)

**Files:**
- Create: `~/.claude/skills/bp-review/scripts/redact.sh`

- [ ] **Step 1: Write minimal implementation**

Create file `~/.claude/skills/bp-review/scripts/redact.sh`:
```bash
#!/usr/bin/env bash
# redact.sh — secret redaction helper for bp-review.
#
# Modes:
#   json <path>   Redact a JSON file using jq. Removes values for any key
#                 whose name (case-insensitive) matches a secret pattern,
#                 replacing them with the literal string "[REDACTED]".
#   text <path>   Regex-based fallback for non-JSON files. Redacts inline
#                 "key": "value" pairs where key matches the pattern list.
#
# Exit codes: 0 on success, non-zero on error.

set -euo pipefail

SECRET_KEY_PATTERN='^(.*([aA][pP][iI][_-]?[kK][eE][yY]|[tT][oO][kK][eE][nN]|[sS][eE][cC][rR][eE][tT]|[pP][aA][sS][sS][wW][oO][rR][dD]|[dD][aA][tT][aA][bB][aA][sS][eE]_?[uU][rR][lL]).*)$'

redact_json() {
  local file="$1"
  if ! command -v jq >/dev/null 2>&1; then
    echo "redact.sh: jq is required for json mode" >&2
    return 2
  fi
  # Walk the JSON tree. For every string value whose key name matches the
  # secret pattern, replace it with "[REDACTED]". Non-string values and
  # keys that do not match are untouched.
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
  # Matches `"<key>"<spaces>:<spaces>"<value>"` where key contains one of
  # api_key / api-key / apiKey / token / secret / password / database_url.
  sed -E 's/("([aA][pP][iI][_-]?[kK][eE][yY]|[tT][oO][kK][eE][nN]|[sS][eE][cC][rR][eE][tT]|[pP][aA][sS][sS][wW][oO][rR][dD]|[dD][aA][tT][aA][bB][aA][sS][eE]_?[uU][rR][lL])"[[:space:]]*:[[:space:]]*")[^"]*/\1[REDACTED]/g' "$file"
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
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x ~/.claude/skills/bp-review/scripts/redact.sh`

- [ ] **Step 3: Run the test suite**

Run: `bash ~/.claude/skills/bp-review/scripts/test/test-redact.sh`
Expected:
```
PASS: json redaction matches expected
PASS: marker present for apiKey
PASS: raw sk-live leaked
PASS: raw ghp_ token leaked
PASS: raw password leaked
PASS: raw db password leaked
PASS: model preserved
PASS: hook command preserved

Result: 8 passed, 0 failed
```

- [ ] **Step 4: If any test fails, debug**

If the json test fails due to jq indentation or key ordering differences, regenerate the expected fixture from the actual output, diff it visually to verify no secret leaked, and save as the new expected:
```bash
bash ~/.claude/skills/bp-review/scripts/redact.sh json \
  ~/.claude/skills/bp-review/scripts/test/fixtures/settings-with-secrets.json \
  > ~/.claude/skills/bp-review/scripts/test/fixtures/settings-redacted.expected.json
```
Then re-run the test suite. Only do this if you have manually confirmed the output has zero secrets.

---

## Task 5: Write collect-local.sh

**Files:**
- Create: `~/.claude/skills/bp-review/scripts/collect-local.sh`

- [ ] **Step 1: Write implementation**

Create file `~/.claude/skills/bp-review/scripts/collect-local.sh`:
```bash
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
  if grep -E -i '(api[_-]?key|token|secret|password)\s*[:=]\s*[^[:space:]]' "$CLAUDE_HOME/CLAUDE.md" >/dev/null; then
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
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x ~/.claude/skills/bp-review/scripts/collect-local.sh`

- [ ] **Step 3: Smoke test**

Run: `bash ~/.claude/skills/bp-review/scripts/collect-local.sh | head -50`
Expected: output with labeled sections; `settings.json (redacted)` section contains `[REDACTED]` markers if any secrets exist, or a clean structure if not; no raw secret values visible.

- [ ] **Step 4: Verify no leakage by grepping for known secret patterns in the output**

Run:
```bash
bash ~/.claude/skills/bp-review/scripts/collect-local.sh \
  | grep -E -i 'sk-[a-z0-9]{10,}|ghp_[a-z0-9]{10,}|password.*[a-z0-9]{5,}' \
  || echo "no secret leakage detected"
```
Expected: `no secret leakage detected`

If anything matches, the redaction has a gap. Inspect which key name pattern is missing and extend `redact.sh`'s `SECRET_KEY_PATTERN` + re-run Task 4 Step 3.

---

## Task 6: Write check-skills.sh

**Files:**
- Create: `~/.claude/skills/bp-review/scripts/check-skills.sh`

- [ ] **Step 1: Write implementation**

Create file `~/.claude/skills/bp-review/scripts/check-skills.sh`:
```bash
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
  git -C "$d" fetch --quiet 2>/dev/null || {
    printf '%-40s %-8s %-12s %s\n' "$name" "-" "-" "fetch-failed"
    continue
  }
  behind="$(git -C "$d" rev-list --count HEAD..@{upstream} 2>/dev/null || echo "?")"
  ahead="$(git -C "$d" rev-list --count @{upstream}..HEAD 2>/dev/null || echo "?")"
  last="$(git -C "$d" log -1 --format='%as' 2>/dev/null || echo "?")"
  state="clean"
  [ "$ahead" != "0" ] && state="ahead-$ahead"
  [ "$behind" != "0" ] && [ "$behind" != "?" ] && state="${state}/behind"
  printf '%-40s %-8s %-12s %s\n' "$name" "$behind" "$last" "$state"
done
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x ~/.claude/skills/bp-review/scripts/check-skills.sh`

- [ ] **Step 3: Smoke test**

Run: `bash ~/.claude/skills/bp-review/scripts/check-skills.sh`
Expected: a table like:
```
SKILL                                    BEHIND   LAST_COMMIT  STATE
-----                                    ------   -----------  -----
claude-health                            0        2026-04-12   clean
-session-logger                     ...
...
```
Skills without a `.git` directory are silently skipped. Skills without an upstream are marked `no-upstream`.

---

## Task 7: Write sources.yml

**Files:**
- Create: `~/.claude/skills/bp-review/sources.yml`

- [ ] **Step 1: Write the default sources file**

Create file `~/.claude/skills/bp-review/sources.yml`:
```yaml
# bp-review source definitions.
#
# The `official` block ships with the skill. Do not remove entries; only
# update URLs when upstream docs relocate.
#
# The `user` block is user-editable. URLs here are treated as less-trusted:
# their fetch results may inform informational diff but will never be used
# to auto-generate patches.
#
# Each entry supports:
#   url         - absolute https URL
#   label       - short human label
#   expect      - list of substring landmarks that must appear in the fetched
#                 content. If fewer than half are present, the source is
#                 marked STALE_FETCH and excluded from diff analysis.
#   min_length  - minimum character count of the fetched content. Below this
#                 threshold, the source is marked STALE_FETCH.

official:
  - url: https://docs.claude.com/en/docs/claude-code/overview
    label: Claude Code Docs (overview)
    expect: ["Claude Code", "CLAUDE.md"]
    min_length: 500
  - url: https://docs.claude.com/en/docs/claude-code/settings
    label: settings.json reference
    expect: ["settings.json", "permissions", "hooks"]
    min_length: 800
  - url: https://docs.claude.com/en/docs/claude-code/hooks
    label: Hooks reference
    expect: ["PreToolUse", "SessionStart", "pattern"]
    min_length: 800
  - url: https://docs.claude.com/en/docs/claude-code/skills
    label: Skills reference
    expect: ["SKILL.md", "frontmatter", "description"]
    min_length: 500
  - url: https://docs.claude.com/en/release-notes/claude-code
    label: Claude Code release notes
    expect: ["version", "release"]
    min_length: 300

user:
  - url: https://tw93.fun/en/2026-03-12/claude.html
    label: tw93 six-layer framework
    expect: ["six-layer", "CLAUDE.md"]
    min_length: 500
```

- [ ] **Step 2: Validate with a YAML parser**

Run: `python3 -c 'import yaml; print(len(yaml.safe_load(open("'$HOME'/.claude/skills/bp-review/sources.yml"))))'`
Expected: `2` (two top-level keys: `official` and `user`)

If `python3` or PyYAML is missing, skip this step — the skill itself does not rely on a YAML parser at runtime (SKILL.md instructions parse it with `yq` or `grep`).

---

## Task 8: Write references/redact-patterns.md

**Files:**
- Create: `~/.claude/skills/bp-review/references/redact-patterns.md`

- [ ] **Step 1: Write the reference doc**

Create file `~/.claude/skills/bp-review/references/redact-patterns.md`:
```markdown
# Redact Patterns

This document lists the key-name patterns that `redact.sh` treats as secrets.
When extending redaction, update both this file and the `SECRET_KEY_PATTERN`
variable in `scripts/redact.sh`, then re-run `scripts/test/test-redact.sh`.

## Currently Matched (case-insensitive, substring match on key name)

| Pattern | Example key names |
|---|---|
| `api[_-]?key` | `apiKey`, `api_key`, `api-key`, `API_KEY` |
| `token` | `token`, `accessToken`, `ghToken` |
| `secret` | `secret`, `clientSecret` |
| `password` | `password`, `dbPassword` |
| `database_?url` | `DATABASE_URL`, `databaseUrl` |

## Not Matched (intentional)

These are considered safe because they do not commonly hold credentials:

- `model`, `modelName`
- `command`, `args`
- `hooks`, `mcpServers` (container keys)
- `label`, `description`

## Redaction Modes

- **json**: Walks the JSON tree via `jq`. For every string value whose key
  matches the pattern, the value is replaced with `"[REDACTED]"`. Non-string
  values and non-matching keys are preserved.

- **text**: Regex-based fallback using `sed` for non-JSON files. Only
  matches inline `"key": "value"` pairs. Less robust; prefer `json` mode
  whenever possible.

## Adding a New Pattern

1. Add a row to the table above.
2. Extend `SECRET_KEY_PATTERN` in `scripts/redact.sh`.
3. Add a test case to `scripts/test/fixtures/settings-with-secrets.json` that
   uses the new key name and a clearly-fake secret value.
4. Regenerate `settings-redacted.expected.json`:
   ```
   bash scripts/redact.sh json scripts/test/fixtures/settings-with-secrets.json \
     > scripts/test/fixtures/settings-redacted.expected.json
   ```
5. Verify visually that the expected file has the new key redacted and no
   other secret leaked.
6. Run `bash scripts/test/test-redact.sh` — expect all tests pass.
```

---

## Task 9: Write SKILL.md

**Files:**
- Create: `~/.claude/skills/bp-review/SKILL.md`

- [ ] **Step 1: Write the full SKILL.md**

Create file `~/.claude/skills/bp-review/SKILL.md`:
```markdown
---
name: bp-review
description: Personal skill () — review the user's global ~/.claude/ configuration against the latest official Claude Code best-practice docs and user-curated sources. Produces a dated report and draft patches in ~/.claude/bp-review/ without modifying any original files. Complements claude-health (internal audit) by tracking the moving frontier (new features, deprecated settings, changed recommendations). Use when the user asks to "review Claude Code config freshness", "check global Claude config against best practices", or types /bp-review, or when the SessionStart nudge fires.
---

# bp-review

Audit the user's global Claude Code configuration for drift from the latest upstream best practices.

## Relationship to claude-health

- `claude-health` (`/health`) = internal consistency audit using a static 6-layer framework.
- `bp-review` (this skill) = external diff against live documentation sources.

They are complementary. When both apply, run `/health` first, then `/bp-review`.

## Non-goals

- Do NOT perform the 6-layer internal audit — that is claude-health's job.
- Do NOT inspect project-specific `.claude/` configs. Scope is `~/.claude/` only.
- Do NOT modify any original file. Produce reports and `.proposed` drafts only.
- Do NOT silently skip a source that failed to fetch — always surface it.

## Prerequisites reminder

At the start of every run, print one line:

> Reminder: run `/health` (claude-health) first for internal-consistency audit. `/bp-review` focuses on external best-practice drift only.

This is informational; do not block if the user has not run `/health`.

## Processing flow

Execute these steps in order. Tell the user briefly what is happening between steps.

### Step 1 — Skill clone freshness check

Run the skill's `check-skills.sh` script:

```
bash ~/.claude/skills/bp-review/scripts/check-skills.sh
```

Show the table to the user. For each skill that is behind upstream, offer to run `git -C <path> pull --ff-only` but do NOT run it without explicit user confirmation. Ask one combined question: "Pull updates for N behind skills? (y/N)".

### Step 2 — Collect redacted local snapshot

Run:

```
bash ~/.claude/skills/bp-review/scripts/collect-local.sh > /tmp/bp-review-local.txt
```

Read `/tmp/bp-review-local.txt`. If the script exits with code 3 (CLAUDE.md contained secret-shaped content), stop and tell the user — this requires manual cleanup before the skill can safely proceed.

**Redaction invariant**: every value in `settings.json` that could hold a credential MUST appear as `[REDACTED]` in the collected snapshot. Do not read `~/.claude/settings.json` directly at any point.

### Step 3 — Fetch remote sources

Parse `~/.claude/skills/bp-review/sources.yml`. For each entry in `official` and `user`:

1. Call WebFetch with the `url`.
2. Check the returned content against `expect` and `min_length`:
   - If the content has fewer than half of the `expect` substrings → mark `STALE_FETCH (landmarks missing)`.
   - If the content is shorter than `min_length` characters → mark `STALE_FETCH (too short)`.
   - If WebFetch errors out or redirects → mark `FETCH_ERROR`.
3. Build a Source Health map:
   ```
   source_health:
     - label: "..."
       status: PASS | STALE_FETCH | FETCH_ERROR
       detail: "..."  # e.g., which landmarks were missing
   ```

**All sources — including PASS — MUST appear in the Source Health section of the report.** Silent skipping is forbidden.

### Step 4 — Diff analysis

For each source marked PASS, compare against the local redacted snapshot:

- Features or settings keys mentioned in docs but absent from local `settings.json`.
- Keys in local `settings.json` that are marked deprecated or renamed in release notes.
- New hook patterns / MCP allowlist syntax / plugin options.
- New skill authoring conventions (e.g., frontmatter fields).

**Trust tiering**: `official` sources may contribute to Critical/Suggested findings AND to draft patches. `user` sources may contribute only to Info findings and may NOT drive draft patches.

Classify findings:

- **Critical** — local config clearly violates a current documented requirement, or uses a deprecated/removed setting.
- **Suggested** — a new feature is available and likely beneficial, but not required.
- **Info** — observations from user-tier sources; not actionable without manual review.

### Step 5 — Write report and draft patches

Write a report to `~/.claude/bp-review/reports/YYYY-MM-DD.md` with this structure:

```markdown
# bp-review report — YYYY-MM-DD

## Source Health

| Source | Status | Detail |
|--------|--------|--------|
| ...    | PASS   | ...    |

## Skill Freshness

(paste the check-skills.sh table)

## Findings

### [!] Critical

- ...

### [~] Suggested

- ...

### [-] Info

- ...

## Draft patches

See ~/.claude/bp-review/proposed/ for any `.proposed` files generated this run.

## Pointer

For project-side config audits, run `/health` inside each project.
```

If any finding is patchable (e.g., add a new key to `CLAUDE.md`), write the draft to `~/.claude/bp-review/proposed/<filename>.proposed`. Never modify the original file under `~/.claude/`.

### Step 6 — Update timestamp

Run:

```
date -u +%Y-%m-%dT%H:%M:%SZ > ~/.claude/bp-review/last_check.txt
```

The SessionStart nudge hook reads this file.

### Step 7 — Summarize to the user

Print a short terminal summary:

```
bp-review complete.
  Sources: <N PASS> / <N total>  (<stale count> stale, <error count> error)
  Skills behind: <N>
  Findings: <critical> critical, <suggested> suggested, <info> info
  Report: ~/.claude/bp-review/reports/YYYY-MM-DD.md
  Drafts: ~/.claude/bp-review/proposed/ (<N> files)
```

Ask: "Review the report now? (y/N)"

## Secrets handling — NEVER VIOLATE

- Never read `~/.claude/settings.json` directly. Always go through `collect-local.sh` (which pipes through `redact.sh`).
- Never read hook script bodies into context. `collect-local.sh` only captures shebang lines and filenames.
- If `CLAUDE.md` contains secret-shaped content, `collect-local.sh` aborts with exit code 3. Surface the abort to the user and stop.
- When running `WebFetch`, pass only URLs from `sources.yml` — never URLs derived from file contents.
```

- [ ] **Step 2: Sanity-check frontmatter**

Run:
```bash
head -5 ~/.claude/skills/bp-review/SKILL.md
```
Expected: starts with `---`, has `name: bp-review`, has a `description:` line, ends the frontmatter block with `---`.

---

## Task 10: Create SessionStart nudge hook

**Files:**
- Create: `~/.claude/hooks/bp-review-nudge.sh`

- [ ] **Step 1: Write the hook script**

Create file `~/.claude/hooks/bp-review-nudge.sh`:
```bash
#!/usr/bin/env bash
# bp-review-nudge.sh — SessionStart hook for bp-review.
#
# Prints a single reminder line if the last bp-review run is older than
# NUDGE_DAYS days. Does nothing on first run (no timestamp file yet) to
# avoid nagging on a fresh install — the user will discover the skill
# when they want it.
#
# Fast path: no network, no heavy I/O. Completes in ~20ms.

set -eu

NUDGE_DAYS="${BP_REVIEW_NUDGE_DAYS:-7}"
STAMP="${CLAUDE_HOME:-$HOME/.claude}/bp-review/last_check.txt"

[ -f "$STAMP" ] || exit 0

now=$(date +%s)
if stat -f %m "$STAMP" >/dev/null 2>&1; then
  # macOS / BSD stat
  mtime=$(stat -f %m "$STAMP")
else
  # GNU stat
  mtime=$(stat -c %Y "$STAMP")
fi

age_days=$(( (now - mtime) / 86400 ))

if [ "$age_days" -ge "$NUDGE_DAYS" ]; then
  echo "bp-review: last checked ${age_days} days ago — consider running /bp-review"
fi
exit 0
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x ~/.claude/hooks/bp-review-nudge.sh`

- [ ] **Step 3: Smoke test in the "no stamp yet" case**

Run: `bash ~/.claude/hooks/bp-review-nudge.sh; echo "exit: $?"`
Expected: no output, `exit: 0` (since `last_check.txt` does not exist yet)

- [ ] **Step 4: Smoke test in the "stale stamp" case**

Run:
```bash
echo "2020-01-01T00:00:00Z" > ~/.claude/bp-review/last_check.txt
touch -t 202001010000 ~/.claude/bp-review/last_check.txt
bash ~/.claude/hooks/bp-review-nudge.sh
```
Expected: a single line like `bp-review: last checked NNNN days ago — consider running /bp-review`

- [ ] **Step 5: Clean up the fake stamp**

Run: `rm ~/.claude/bp-review/last_check.txt`

---

## Task 11: Register hook in settings.json (REQUIRES EXPLICIT USER PERMISSION)

**Files:**
- Modify: `~/.claude/settings.json`

**⚠️ This task touches a file that may contain secrets. Per `feedback_no_read_secrets.md`, do NOT proceed without explicit user permission. When executing this task:**

1. **Stop and ask**: "Task 11 needs to read/modify `~/.claude/settings.json` to register the SessionStart hook. May I proceed? I will work on a redacted copy and show you the minimal diff before writing anything back."
2. **Wait for a clear yes.** If unclear, default to showing the user the exact edit they should make manually.

- [ ] **Step 1: Ask user for permission**

Confirm with the user in the chat before touching `settings.json`. Do not proceed otherwise.

- [ ] **Step 2: Work on a redacted copy**

Run:
```bash
bash ~/.claude/skills/bp-review/scripts/redact.sh json ~/.claude/settings.json \
  > /tmp/settings.redacted.json
```

Read `/tmp/settings.redacted.json` to understand the current structure of `hooks.SessionStart`.

- [ ] **Step 3: Compute the minimal JSON patch**

The desired addition (append to `.hooks.SessionStart[]`):
```json
{ "command": "bash ~/.claude/hooks/bp-review-nudge.sh" }
```

Using `jq`, produce the proposed full file:
```bash
jq '.hooks.SessionStart += [{"command": "bash ~/.claude/hooks/bp-review-nudge.sh"}]' \
  ~/.claude/settings.json > ~/.claude/settings.json.bp-review.proposed
```

**Note**: this read is allowed because the user explicitly authorized it in Step 1, and the output goes to a `.proposed` file that the user will review.

- [ ] **Step 4: Show the user the diff**

Run:
```bash
diff -u ~/.claude/settings.json ~/.claude/settings.json.bp-review.proposed
```

Show the diff. Confirm it contains only the SessionStart addition and no unrelated changes (no secret values rewritten).

- [ ] **Step 5: Ask final confirmation and apply**

Ask: "Apply this diff to settings.json? (y/N)"

On yes:
```bash
cp ~/.claude/settings.json ~/.claude/settings.json.bak-bp-review
mv ~/.claude/settings.json.bp-review.proposed ~/.claude/settings.json
```

On no: leave the `.proposed` file in place and tell the user they can apply it later manually.

- [ ] **Step 6: Verify**

Run: `jq '.hooks.SessionStart' ~/.claude/settings.json`
Expected: the array now contains an entry with `"command": "bash ~/.claude/hooks/bp-review-nudge.sh"`.

---

## Task 12: Initialize git repo for skill package and commit

**Files:**
- Create: `~/.claude/skills/bp-review/.gitignore`
- Create: `~/.claude/skills/bp-review/README.md`
- Git-init the skill package

- [ ] **Step 1: Write README**

Create file `~/.claude/skills/bp-review/README.md`:
```markdown
# bp-review

Personal Claude Code skill that reviews `~/.claude/` against the latest official best-practice documentation and user-curated sources, producing a report + draft patches without touching originals.

See `SKILL.md` for Claude-facing invocation instructions and the design spec at `~/.claude/plans/2026-04-12-bp-review-design.md` for rationale.

## Operational notes

Suggested cadence:

1. The SessionStart nudge hook reminds you if the last run is >7 days old.
2. Run `/health` (claude-health) first for internal audit.
3. Run `/bp-review` for external drift check.
4. Also run ad-hoc when:
   - A new Claude Code release (watch the release notes source for `STALE_FETCH` as an early signal that upstream changed a lot)
   - Setting up a new machine
   - Adopting a new skill or plugin

## Customization

Add trusted sources to the `user:` block in `sources.yml`. Keep in mind that user-tier sources only contribute to informational findings, never to draft patches.

## Testing the redactor

```
bash scripts/test/test-redact.sh
```

All tests must pass before committing any change to `scripts/redact.sh` or the patterns in `references/redact-patterns.md`.
```

- [ ] **Step 2: Write .gitignore**

Create file `~/.claude/skills/bp-review/.gitignore`:
```
# No runtime artifacts — those live in ~/.claude/bp-review/
/tmp/
*.bak
*.bak-*
```

- [ ] **Step 3: Initialize git and commit**

Run:
```bash
cd ~/.claude/skills/bp-review
git init -q
git add .
git -c user.email='@local' -c user.name='' commit -q -m "feat: initial bp-review skill"
git log -1 --format='%h %s'
```
Expected: a single commit hash + message.

If `git init` fails because a parent directory is already a git repo, stop and report that — the skills dir should not be inside another repo.

- [ ] **Step 4: Verify tests still pass**

Run: `bash ~/.claude/skills/bp-review/scripts/test/test-redact.sh`
Expected: `Result: 8 passed, 0 failed`

---

## Task 13: End-to-end dry run with mocked WebFetch

**Files:** none (verification only)

- [ ] **Step 1: Run collect-local.sh and inspect output**

Run: `bash ~/.claude/skills/bp-review/scripts/collect-local.sh > /tmp/bp-review-local.txt && wc -l /tmp/bp-review-local.txt`
Expected: a non-zero line count and no secrets in the file (re-run the grep from Task 5 Step 4 to confirm).

- [ ] **Step 2: Run check-skills.sh**

Run: `bash ~/.claude/skills/bp-review/scripts/check-skills.sh`
Expected: a table with at least `claude-health` listed.

- [ ] **Step 3: Simulate a full bp-review invocation manually**

In Claude Code, invoke `/bp-review`. Observe:
- The prerequisite reminder is printed.
- `check-skills.sh` runs and shows the freshness table.
- `collect-local.sh` runs and the result is ingested redacted.
- `sources.yml` URLs are fetched via WebFetch.
- Each source reports a Source Health status.
- A report file is created at `~/.claude/bp-review/reports/YYYY-MM-DD.md`.
- `last_check.txt` is updated.
- A summary line is printed.

- [ ] **Step 4: Verify the report**

Run: `ls -la ~/.claude/bp-review/reports/ && cat ~/.claude/bp-review/reports/*.md | head -50`
Expected: at least one report file exists and starts with the `# bp-review report — YYYY-MM-DD` header.

- [ ] **Step 5: Verify the nudge hook (fast-forward test)**

Run:
```bash
touch -t 202001010000 ~/.claude/bp-review/last_check.txt
bash ~/.claude/hooks/bp-review-nudge.sh
```
Expected: a single reminder line.

Reset:
```bash
date -u +%Y-%m-%dT%H:%M:%SZ > ~/.claude/bp-review/last_check.txt
```

- [ ] **Step 6: Final commit (if anything was edited during dry-run)**

Run:
```bash
cd ~/.claude/skills/bp-review
git status
```
If anything is dirty, review it, then:
```bash
git add .
git -c user.email='@local' -c user.name='' commit -q -m "chore: dry-run fixups"
```

---

## Self-Review (author's pass)

### Spec coverage

| Spec section | Plan task(s) |
|---|---|
| §1 Purpose & scope | SKILL.md (T9) — "Non-goals" + "Relationship to claude-health" |
| §2 Design decisions | Captured in SKILL.md and README.md |
| §3.1 sources.yml | T7 |
| §3.2 Stale-fetch detection | SKILL.md Step 3 (T9) — enforced at invocation time |
| §4 Secrets handling | T2–T4 (redact.sh + tests), T5 (collect-local.sh), SKILL.md "Secrets handling" section (T9), T11 explicit permission gate |
| §5 Processing flow | SKILL.md Steps 1–7 (T9) |
| §6 Directory layout | T1 (dirs), T9 (SKILL.md), T10 (hook), T11 (settings registration) |
| §7 Trigger & operational flow | T9 (slash command via skill name), T10 (SessionStart nudge), T11 (hook registration) |
| §8 Skill clone freshness | T6 (check-skills.sh), T9 SKILL.md Step 1 |
| §9 Known risks | README (T12) documents user-tier trust tiering; SKILL.md enforces it in Step 4 |
| §10 Non-goals | SKILL.md (T9) |

### Placeholder scan

No "TBD", "TODO", "fill in", or "similar to Task N" references remain. Every code block is the actual content to write.

### Type consistency

- `collect-local.sh` section labels match what SKILL.md reads (`CLAUDE.md`, `settings.json (redacted)`, `hooks/`, `skills/`, `plugins/`).
- `redact.sh` invocation signature is `redact.sh <mode> <file>` and is used consistently in collect-local.sh and T11.
- `sources.yml` keys (`url`, `label`, `expect`, `min_length`) are referenced by those names in SKILL.md Step 3.
- `last_check.txt` is written by SKILL.md Step 6 and read by `bp-review-nudge.sh`.

### Known gaps acknowledged

- Diff analysis logic (SKILL.md Step 4) is intentionally high-level — the actual comparison is model-driven, not script-driven. This matches the spec's §5 "keyword-based matching, iterate based on experience" note.
- `sources.yml` parsing at runtime is delegated to the model (no `yq` dependency introduced) to keep the skill portable.

---

## Execution Handoff

Plan complete and saved to `~/.claude/plans/2026-04-12-bp-review-plan.md`. Two execution options:

**1. Subagent-Driven** — dispatch a fresh subagent per task with review between tasks. Adds overhead for a 13-task plan; probably overkill for a personal skill this size.

**2. Inline Execution** — execute tasks in this session using `superpowers:executing-plans`, with checkpoints at Task 4 (redact tests pass), Task 9 (SKILL.md complete), and Task 11 (settings.json edit — user permission gate).

**Recommendation: Inline Execution.** This is a small, self-contained personal skill with one sensitive checkpoint (T11). Subagent overhead is not worth it.

Which approach?
