#!/usr/bin/env bash
# 呼び出し元の herdr ペインの右隣に、この worktree の Hunk セッションを冪等に用意する。
#
# 標準出力: {"pane","pane_action","hunk_action","session"}
#   pane_action  split-created | split-reused
#   hunk_action  hunk-alive | hunk-launched | blocked
# 終了コード: 0 = 利用可能 / 2 = 右ペインが他用途で使用中（何もしていない）/ 1 = エラー
set -euo pipefail

repo="$(git rev-parse --show-toplevel)"
self="${HERDR_PANE_ID:-}"
[ -n "$self" ] || { echo "herdr の外で実行されている（HERDR_PANE_ID なし）" >&2; exit 1; }

# そのペインの前面プロセス pid 集合に含まれる Hunk セッションを返す。
# プロセス名では判定しない: npm ラッパー(node) が native hunk を子として起動するため、
# 起動直後は comm が MainThread/hunk で入れ替わり pid を取り違える。
pane_session() {
  local pids
  pids="$(herdr pane process-info --pane "$1" \
    | jq -c '[.result.process_info.foreground_processes[].pid]')"
  hunk session list --json \
    | jq -r --argjson pids "$pids" \
        '[.sessions[] | select(.pid as $p | $pids | index($p))] | .[0].sessionId // ""'
}

# 右隣のペインを layout の座標から求める。
# `herdr pane neighbor` は 0.7.4 では常に自分自身を返すため使えない。
# layout は自タブのペインしか返さないので、他タブ・他ワークスペースには構造的に届かない。
right="$(herdr pane layout --pane "$self" | jq -r --arg self "$self" '
  .result.layout.panes as $panes
  | ($panes[] | select(.pane_id == $self) | .rect) as $me
  | [ $panes[]
      | select(.pane_id != $self)
      | select(.rect.x == ($me.x + $me.width))
      | select(.rect.y < ($me.y + $me.height) and ($me.y < .rect.y + .rect.height))
    ] | .[0].pane_id // ""')"

if [ -n "$right" ]; then
  pane_action="split-reused"
else
  right="$(herdr pane split --pane "$self" --direction right --ratio 0.5 \
    --cwd "$repo" --no-focus | jq -r '.result.pane.pane_id')"
  pane_action="split-created"
fi

emit() { printf '{"pane":"%s","pane_action":"%s","hunk_action":"%s","session":"%s"}\n' \
  "$right" "$pane_action" "$1" "$2"; }

# 既に Hunk が動いていれば起動しない
sid="$(pane_session "$right")"
if [ -n "$sid" ]; then emit hunk-alive "$sid"; exit 0; fi

# 右ペインが素のシェル以外（nvim / サーバ / 別エージェント等）なら何も打ち込まない
fg="$(herdr pane process-info --pane "$right" \
  | jq -r '[.result.process_info.foreground_processes[].name] | join(",")')"
case "$fg" in
  "" | zsh | bash | sh | fish) ;;
  *)
    printf '{"pane":"%s","pane_action":"%s","hunk_action":"blocked","busy_with":"%s"}\n' \
      "$right" "$pane_action" "$fg"
    exit 2
    ;;
esac

# pane run は shell の入力バッファを消さずに追記するため、先に行をクリアする
herdr pane send-keys "$right" ctrl+u >/dev/null 2>&1 || true
herdr pane run "$right" 'hunk show --watch'

for _ in $(seq 1 60); do
  sid="$(pane_session "$right")"
  [ -n "$sid" ] && break
  sleep 0.25
done
[ -n "$sid" ] || { echo "右ペインで hunk が起動しなかった: $right" >&2; exit 1; }

emit hunk-launched "$sid"
