#!/usr/bin/env bash
# Claude Code の UserPromptSubmit hook。
# プロンプトの先頭 30 文字を herdr のペインメタデータ ($task) としてサイドバーに出す。
# herdr 外では何もしない。失敗しても Claude を止めないよう常に exit 0 し、stdout には何も出さない
# （UserPromptSubmit の stdout はコンテキストに追加されるため）。

[ "${HERDR_ENV:-}" = "1" ] || exit 0
[ -n "${HERDR_PANE_ID:-}" ] || exit 0

task=$(jq -r '.prompt // "" | gsub("\\s+"; " ") | ltrimstr(" ") | .[0:30]' 2>/dev/null) || exit 0
[ -n "$task" ] || exit 0

herdr pane report-metadata "$HERDR_PANE_ID" \
  --source claude-task --agent claude --token "task=$task" >/dev/null 2>&1
exit 0
