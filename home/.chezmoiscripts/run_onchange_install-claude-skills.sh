#!/bin/sh
# Managed by chezmoi.
#
# skills CLI (https://www.skills.sh/) で Claude Code のグローバルスキルを導入する。
# lockfile からの復元コマンド (skills install / sync) が未実装のため、入れたいスキルは
# ここで宣言的に持つ。run_onchange_ なのでこのファイルの内容が変わったときだけ再実行される。
# スキルを増やすときはこの末尾に skills add を 1 行足して chezmoi apply するだけでよい。
set -eu

# 初回プロビジョニングでは os-setup の chezmoi update が mise install より先に走るため、
# この時点では skills CLI が未導入。os-setup が mise install 後に apply を再実行する。
export PATH="$HOME/.local/share/mise/shims:$PATH"
if ! command -v skills >/dev/null 2>&1; then
    echo "skills CLI not found; skipping (will run after mise install)" >&2
    exit 0
fi

# hunk-review は modem-dev/hunk にも同名スキルがあるが、ここでは導入しない。
# 自作のローダー (~/.claude/skills/hunk-review) が hunk バイナリ同梱スキルを実行時解決して
# おり、そちらの方が mise の npm:hunkdiff と版が一致する。-g で入れると上書きされてしまう。
skills add herdrdev/herdr     --skill herdr       --agent claude-code --global --yes
skills add vercel-labs/skills --skill find-skills --agent claude-code --global --yes
