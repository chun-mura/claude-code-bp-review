# bp-review

グローバルな `~/.claude/` 設定を、最新の公式ベストプラクティス文書とユーザーが選んだソースと照合してレビューし、レポートとパッチ案を生成する Claude Code スキルです。元の設定ファイルは変更しません。

Claude 向けの呼び出しフローは `SKILL.md`、設計の背景は `docs/design.md` を参照してください。

## 他ツールとの関係

- [`claude-health`](https://github.com/tw93/claude-health) (`/health`) — tw93 による内部の6層監査。先に実行する。
- `bp-review` (`/bp-review`) — 外部ベストプラクティスとの乖離チェック。次に実行する。

## インストール

1. スキルディレクトリにクローンする:

   ```sh
   git clone https://github.com/chun-mura/claude-code-bp-review ~/.claude/skills/bp-review
   ```

2. `~/.claude/settings.json` の `.hooks.SessionStart[]` に nudge フックを登録する:

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

3. redactor のテストを実行して動作を確認する:

   ```sh
   bash ~/.claude/skills/bp-review/scripts/test/test-redact.sh
   ```

4. Claude Code から `/bp-review` を実行して初回監査を行う。ランタイムディレクトリ `~/.claude/bp-review/` に `reports/`、`proposed/`、`last_check.txt` が作成される。

## 運用サイクル

推奨するレビュー頻度:

1. **セッション開始時の nudge** — `SessionStart` フックは Claude Code の新規セッションごとに発火する。`scripts/nudge.sh` は、前回実行から `BP_REVIEW_NUDGE_DAYS`（デフォルト: 7日）以上経過している場合に1行のリマインダーを表示する。初回インストール時はリマインダーは出ない。タイムスタンプファイルは最初の `/bp-review` 実行後にのみ書き込まれる。
2. **`/health` 実行のたび** — `/health` がカバーできない外部の最新動向を確認するため `/bp-review` を実行する。
3. **随時** — 次のタイミングでも実行する:
   - 新しい Claude Code リリースが出たとき（上流の変更の早期シグナルとして、リリースノートソースの `STALE_FETCH` を確認する）。
   - 新しいマシンをセットアップするとき。
   - 新しいスキルやプラグインを導入するとき。

## カスタマイズ

`sources.yml` の `user:` ブロックに信頼できるソースを追加できる。`user` ティアのソースは情報提供用の所見にのみ寄与し、パッチ案には反映されない点に注意する。

## redactor のテスト

```
bash scripts/test/test-redact.sh
```

`scripts/redact.sh` や `references/redact-patterns.md` のパターンを変更する場合は、コミット前にすべてのテストが通ることを確認する。
