# bp-review

A Claude Code skill that reviews your global `~/.claude/` configuration against the latest official best-practice documentation and user-curated sources, producing a report + draft patches without touching the originals.

See `SKILL.md` for the Claude-facing invocation flow and `docs/design.md` for the rationale.

## Relationship to other tooling

- [`claude-health`](https://github.com/tw93/claude-health) (`/health`) — internal six-layer audit by tw93. Run first.
- `bp-review` (`/bp-review`) — external best-practice drift check. Run second.

## Install

1. Clone into your skills directory:

   ```sh
   git clone https://github.com/chun-mura/claude-code-bp-review ~/.claude/skills/bp-review
   ```

2. Register the nudge hook in `~/.claude/settings.json` under `.hooks.SessionStart[]`:

   ```json
   {
     "hooks": {
       "SessionStart": [
         {
           "matcher": "",
           "hooks": [
             { "type": "command", "command": "bash ~/.claude/skills/bp-review/scripts/nudge.sh" }
           ]
         }
       ]
     }
   }
   ```

3. Verify by running the redactor tests:

   ```sh
   bash ~/.claude/skills/bp-review/scripts/test/test-redact.sh
   ```

4. From Claude Code, run `/bp-review` to execute the first audit. The runtime directory `~/.claude/bp-review/` will be populated with `reports/`, `proposed/`, and `last_check.txt`.

## Operational cadence

Suggested review rhythm:

1. **Session-start nudge** — the `SessionStart` hook fires on every new Claude Code session. `scripts/nudge.sh` prints a one-line reminder if the last run is older than `BP_REVIEW_NUDGE_DAYS` (default: 7). No reminder is printed on fresh installs — the timestamp file is only written after the first `/bp-review` run.
2. **After each run of `/health`** — run `/bp-review` to cover the external frontier that `/health` cannot see.
3. **Ad hoc** — also run when:
   - A new Claude Code release lands (watch the release-notes source health for `STALE_FETCH` as an early signal of upstream changes).
   - Setting up a new machine.
   - Adopting a new skill or plugin.

## Customization

Add trusted sources to the `user:` block in `sources.yml`. Keep in mind that user-tier sources only contribute to informational findings, never to draft patches.

## Testing the redactor

```
bash scripts/test/test-redact.sh
```

All tests must pass before committing any change to `scripts/redact.sh` or the patterns in `references/redact-patterns.md`.
