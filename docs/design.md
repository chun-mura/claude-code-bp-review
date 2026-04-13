# bp-review Skill — Design Spec

- **Date**: 2026-04-12
- **Author**: chun-mura (via brainstorming with Claude)
- **Status**: Draft — awaiting user review before implementation plan

## 1. Purpose & Scope

### 1.1 Purpose

Create a global Claude Code skill (`bp-review`) that periodically reviews the user's global configuration (`~/.claude/`) against the latest official best practices and user-curated sources, then reports divergence with draft patches. The skill must **not** duplicate `claude-health`'s internal consistency audit; it tracks the *moving frontier* (new features, changed recommendations, deprecated settings).

### 1.2 Out of Scope (delegated to claude-health)

- Six-layer internal consistency audit (`CLAUDE.md → rules → skills → hooks → subagents → verifiers`)
- Signal/noise ratio of `CLAUDE.md`
- Hook / MCP / skill security static audit
- Project-side configuration details

### 1.3 Boundary

- `claude-health` = "is my current config broken?" (static rules, internal integrity)
- `bp-review` = "is my current config out-of-date?" (external sources, frontier tracking)

### 1.4 Coverage

- **Target**: `~/.claude/` only (`CLAUDE.md`, `settings.json`, `hooks/`, `skills/`, `plugins/`)
- **Project configs**: NOT inspected. Report ends with a pointer suggesting `/health` for project-side audits.

## 2. Design Decisions

Brainstorming decisions that shaped this spec:

| Question | Choice | Rationale |
|---|---|---|
| Q1: Relationship with claude-health | Complementary — tracks external best-practice evolution | claude-health's static ruleset lags new features; external diff is a distinct layer |
| Q2: Scope | Global only + pointer hints for project-side | Clean separation; project audits belong to `/health` |
| Q3: Information sources | Official docs + user-extensible `sources.yml` | Balances trust and extensibility |
| Q4: Output format | Report + draft patches in `.proposed` files (never touches originals) | Safe, git-diff friendly, user retains control |
| Q5: Trigger mechanism | Manual slash command + lightweight SessionStart hook nudge | Avoids cron fragility and external scheduling dependencies |

## 3. Information Sources

### 3.1 `sources.yml` structure

`min_length` is measured in **characters** (not tokens) for implementation simplicity and determinism.


```yaml
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
    label: Release notes
    expect: ["version", "release"]
    min_length: 300

user:
  - url: https://tw93.fun/en/2026-03-12/claude.html
    label: tw93 six-layer framework
    expect: ["six-layer", "CLAUDE.md"]
    min_length: 500
```

- `official` block ships with the skill and is version-controlled.
- `user` block is user-editable. Users are responsible for the trustworthiness of URLs they add.
- **URLs in `user` are treated as less-trusted**: their fetch results only contribute to informational diff, never to auto-generated patches.

### 3.2 Stale-fetch detection (REQUIRED)

Every fetch MUST be verified before use:

1. **Length check**: if response body < `min_length` → `STALE_FETCH (too short)`
2. **Landmark check**: if fewer than half of `expect` keywords are present → `STALE_FETCH (landmarks missing)`
3. **Transport check**: WebFetch error, redirect, or non-200 → `FETCH_ERROR`

**Consequences of failure**:

- Sources flagged `STALE_FETCH` or `FETCH_ERROR` are **excluded from diff analysis**.
- The report's **Source Health** section lists every source (PASS and FAIL) with status — silent skipping is explicitly forbidden.
- Two consecutive failures for the same URL trigger a suggestion to update `sources.yml`.

## 4. Secrets Handling (REQUIRED)

### 4.1 Principle: redact-before-context

Settings files and hook scripts under `~/.claude/` may contain API keys, tokens, or other credentials. The skill must **never** place raw secret values into the model's context.

### 4.2 Approaches

Per user guidance, use one of:

**Option A — regex redact**:
```bash
sed -E 's/("(api[_-]?key|token|secret|password)"\s*:\s*")[^"]+/\1[REDACTED]/gi'
```

**Option B — structural extraction**:
```bash
jq 'del(.. | .apiKey?, .token?, .secret?, .password?)'
```

Use Option B for JSON files (safer, less prone to regex evasion). Fall back to Option A only for non-JSON files (shell scripts, YAML).

### 4.3 Scope of redaction

| File | Handling |
|---|---|
| `~/.claude/settings.json` | `jq` redact (Option B) |
| `~/.claude/hooks/*.sh` | Extract shebang + top-level function names + file names only; do NOT include body |
| `~/.claude/CLAUDE.md` | Pattern-grep for known secret markers; if found, block with an error instead of auto-redacting |
| `~/.claude/skills/*/SKILL.md` | Frontmatter only; body excluded |
| `~/.claude/plugins/` (if present) | List names only |

### 4.4 User-visible safety mode

Provide an optional `--show-redact-diff` flag that prints a diff of pre-redact vs post-redact content, so the user can verify that no secret was leaked into the context.

## 5. Processing Flow

```
1. Prerequisite notice
   - Unconditionally print a one-line reminder suggesting `/health` be run first for internal-consistency audit.
   - Do NOT attempt to auto-detect prior /health runs (no reliable signal); keep the check trivial.

2. Skill clone freshness check (optional)
   - Enumerate ~/.claude/skills/*/.git/ directories.
   - Run `git fetch` on each and report ahead/behind counts.
   - Offer to `git pull --ff-only` but do not execute without confirmation.

3. Local collect (redact-applied)
   - Read CLAUDE.md, settings.json (redact), hooks/ (shebang+names), skills/ (frontmatter).
   - Materialize the redacted bundle into a temp directory for inspection.

4. Remote fetch
   - Read sources.yml.
   - For each URL, call WebFetch and run stale-fetch detection (§3.2).
   - Build a Source Health map (PASS/FAIL per source).

5. Diff analysis
   - For each PASS source, compare local config against source content.
   - Detect:
       a. Features mentioned in docs but absent in local settings.json
       b. Settings keys deprecated or renamed in release notes
       c. New hook patterns / new MCP allowlist syntax / etc.
   - Classify findings as Critical / Suggested / Info.

6. Report & patch draft
   - Write report to ~/.claude/bp-review/reports/YYYY-MM-DD.md
   - If patchable, write draft files under ~/.claude/bp-review/proposed/
       (e.g., CLAUDE.md.proposed, settings.json.proposed)
   - Original files are never modified.
   - Print a terminal summary (counts per severity).

7. Timestamp update
   - Write current time to ~/.claude/bp-review/last_check.txt
```

### 5.1 Expected runtime

WebFetch (steps 4) + analysis (step 5) together: 10–30 seconds for default `official` set.

## 6. Directory Layout

### 6.1 Skill files (versioned)

```
~/.claude/skills/bp-review/
├── SKILL.md                 # skill definition (frontmatter + instructions)
├── sources.yml              # default official URLs + user extensions
├── scripts/
│   ├── redact.sh            # settings.json redaction
│   ├── collect-local.sh     # local info collection (post-redact)
│   └── check-skills.sh      # skills/*/.git ahead/behind check
└── references/
    └── redact-patterns.md   # canonical redact rules
```

### 6.2 Runtime artifacts (separate from skill)

```
~/.claude/bp-review/
├── last_check.txt           # timestamp for SessionStart hook
├── reports/
│   └── 2026-04-12.md        # generated reports
└── proposed/
    └── CLAUDE.md.proposed   # draft patches (originals untouched)
```

## 7. Trigger & Operational Flow

### 7.1 Manual invocation

- Slash command: `/bp-review` (auto-generated from skill name)

### 7.2 SessionStart hook nudge

- Script: `~/.claude/hooks/bp-review-nudge.sh`
- Behavior: reads `~/.claude/bp-review/last_check.txt`, and if > 7 days stale, prints a single line to stdout:
  `bp-review: last checked N days ago — consider running /bp-review`
- **No network access**. Completes within ~20ms.
- Registered in `~/.claude/settings.json` under `hooks.SessionStart[]`.

### 7.3 Rationale

- Cron/`schedule`-based triggers depend on machine uptime and network presence at scheduled time; nudges rely on the user actually opening a session, which is a better proxy for "when do I need current best practices".

## 8. Skill Clone Freshness Mechanism

Separate from `bp-review`'s own runs, the user wants installed skills (especially `claude-health`) to stay current. Approach:

- **Primary**: `bp-review`'s own step 2 performs the fetch + report + proposed-pull.
- **Secondary**: SessionStart hook stays lightweight and does NOT auto-fetch. Staleness surfaces through `bp-review` runs, not every session.

This keeps session startup fast and concentrates network I/O at the user-triggered review moment.

## 9. Known Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Official docs HTML structure changes break WebFetch summaries | Landmark keyword validation (§3.2); surface `STALE_FETCH` explicitly in report |
| User-added `sources.yml` URL contains prompt injection | Trust tiering: user sources feed informational diff only, never auto-patches; SKILL.md warns users |
| `settings.json` redaction regex misses an unknown key name | Prefer `jq` structural extraction (Option B) over regex; provide `--show-redact-diff` for user verification |
| Diff detection has high false-positive rate | Start with simple keyword-based matching; iterate based on actual run experience |
| Skill stops being useful because `sources.yml` defaults drift | Stale-fetch detection forces the issue to surface — users will notice broken sources within one run |
| `claude-health` itself evolves and this skill fails to integrate | Treat `/health` as a prerequisite hint, not a hard dependency |

## 10. Explicit Non-Goals

- This skill does NOT automatically apply patches.
- This skill does NOT silently skip failed sources.
- This skill does NOT inspect project-specific `.claude/` configs.
- This skill does NOT reimplement the six-layer audit.
- This skill does NOT fetch in the SessionStart hook (hook stays fast).

## 11. Open Questions (for user review)

None at time of writing — all Q1–Q5 decisions are captured above. Implementation plan (task decomposition) follows after spec approval.
