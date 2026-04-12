---
name: bp-review
description: Review the user's global ~/.claude/ configuration against the latest official Claude Code best-practice docs and user-curated sources. Produces a dated report and draft patches in ~/.claude/bp-review/ without modifying any original files. Complements claude-health (internal audit) by tracking the moving frontier (new features, deprecated settings, changed recommendations). Use when the user asks to "review Claude Code config freshness", "check global Claude config against best practices", or types /bp-review, or when the SessionStart nudge fires at the start of a new Claude Code session.
---

# bp-review

Audit the user's global Claude Code configuration for drift from the latest upstream best practices.

## Relationship to claude-health

- `claude-health` (`/health`) = internal consistency audit using a static six-layer framework.
- `bp-review` (this skill) = external diff against live documentation sources.

They are complementary. When both apply, run `/health` first, then `/bp-review`.

## Non-goals

- Do NOT perform the six-layer internal audit — that is claude-health's job.
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

**Redaction invariant**: every value in `settings.json` that could hold a credential MUST appear as `[REDACTED]` in the collected snapshot. Do not read `~/.claude/settings.json` directly at any point. Do not echo the full collect-local.sh output into the chat; summarize it or reference sections.

### Step 3 — Fetch remote sources

Parse `~/.claude/skills/bp-review/sources.yml` (grep-based parsing is sufficient — no YAML library required). For each entry in `official` and `user`:

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

- Never read `~/.claude/settings.json` directly with the Read tool. Always go through `collect-local.sh` (which pipes through `redact.sh`).
- Never read hook script bodies into context. `collect-local.sh` only captures shebang lines and filenames.
- If `CLAUDE.md` contains secret-shaped content, `collect-local.sh` aborts with exit code 3. Surface the abort to the user and stop.
- When running `WebFetch`, pass only URLs from `sources.yml` — never URLs derived from file contents.
- When showing snippets from the redacted snapshot to the user, never dump the full snapshot verbatim into the chat. Summarize or quote specific sections.
