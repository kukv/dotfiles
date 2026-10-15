#!/bin/sh
# Start an interactive zsh with the deployed ~/.zshrc and sheldon plugins in a
# throwaway HOME. Needs zsh, and network for sheldon to clone the plugins.
# shellcheck disable=SC2016  # the zsh -ic script is single-quoted on purpose: zsh expands it
set -eu
repo="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

command -v zsh >/dev/null 2>&1 || fail "zsh is required"
# Resolve sheldon before HOME changes: mise installs live under the real HOME.
sheldon_bin="$(mise x sheldon@latest -- sh -c 'command -v sheldon')"
h="$tmp/home"
mkdir -p "$h"

# run <dir> <cmd...>: run in <dir> with the throwaway HOME and sheldon on PATH.
# The ceiling stops mise walking up into the caller's real ~/.config/mise when the
# checkout lives under it.
run() {
  d="$1"; shift
  (cd "$d" && env -u XDG_CONFIG_HOME -u XDG_DATA_HOME -u XDG_STATE_HOME -u XDG_CACHE_HOME \
    MISE_CEILING_PATHS="$(dirname "$repo")" \
    HOME="$h" PATH="$(dirname "$sheldon_bin"):$PATH" MISE_STATUS_MESSAGE_MISSING_TOOLS=never \
    git_name="CI User" git_email="ci@example.com" "$@")
}

run "$repo" mise trust . >/dev/null 2>&1
run "$repo" mise dot apply >/dev/null
run "$h" sheldon lock

out="$(run "$h" zsh -ic '
  alias gst >/dev/null || print -u2 "no gst alias (oh-my-zsh git plugin)"
  alias md >/dev/null || print -u2 "no md alias (oh-my-zsh lib/directories)"
  [[ -o autocd ]] || print -u2 "autocd off (oh-my-zsh lib/directories)"
  (( $+functions[compdef] )) || print -u2 "compinit did not run"
  (( $+functions[_zsh_autosuggest_start] )) || print -u2 "zsh-autosuggestions not loaded"
  (( $+functions[_zsh_highlight] )) || print -u2 "zsh-syntax-highlighting not loaded"
  (( $+functions[history-substring-search-up] )) || print -u2 "zsh-history-substring-search not loaded"
  [[ -n $PROMPT ]] || print -u2 "empty PROMPT (alien)"
  alias gl >/dev/null || print -u2 "no gl alias"
  alias gsw >/dev/null || print -u2 "no gsw alias"
  [[ -o sharehistory ]] || print -u2 "share_history off"
  [[ -o interactivecomments ]] || print -u2 "interactive_comments off"
  [[ $(bindkey -lL main) == *emacs* ]] || print -u2 "keymap is not emacs"
  [[ $(bindkey "^[[A") == *up-line-or-beginning-search* ]] || print -u2 "up arrow is not prefix history search"
  (( $+functions[_title_precmd] )) || print -u2 "no terminal title hook"
  print ok' 2>"$tmp/err")" || true
if [ -s "$tmp/err" ]; then cat "$tmp/err" >&2; fail "zsh startup wrote to stderr"; fi
[ "$out" = ok ] || fail "unexpected output: $out"
echo PASS
