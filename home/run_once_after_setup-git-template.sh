#!/bin/sh
# git init.templateDir(~/.gitconfig の [init] 参照)に pre-commit hook を生成する。
# これにより全ての git clone / git init で pre-commit が自動有効化される。
# 生成物はマシン固有パスを含むため chezmoi では管理せず、ここで再生成する。
set -eu

# chezmoi apply 実行時は mise activate 前のことがあるため shims を明示
PATH="$HOME/.local/share/mise/shims:$PATH"
export PATH

if command -v pre-commit >/dev/null 2>&1; then
  pre-commit init-templatedir "$HOME/.git-template"
else
  echo "pre-commit not found; skipped git-template setup (run: pre-commit init-templatedir ~/.git-template)" >&2
fi
