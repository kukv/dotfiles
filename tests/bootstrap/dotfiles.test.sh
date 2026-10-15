#!/bin/sh
# Tests for the [dotfiles] entries and dotfiles hooks in mise.toml: apply them into a
# throwaway HOME per machine selection and check what only rendering can show.
# A missing source or a non-idempotent entry is caught by `mise dot status --missing`.
set -eu
repo="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

# in_home <home> <cmd...>: run from the checkout with HOME=<home> and no XDG overrides,
# so mise reads only this repo's config and keeps its state under <home>. The ceiling stops
# mise walking up into the caller's real ~/.config/mise when the checkout lives under it.
in_home() {
  h="$1"; shift
  (cd "$repo" && env -u XDG_CONFIG_HOME -u XDG_DATA_HOME -u XDG_STATE_HOME -u XDG_CACHE_HOME \
    MISE_CEILING_PATHS="$(dirname "$repo")" HOME="$h" "$@")
}
# named <home> <cmd...>: in_home with git_name / git_email answered (the environment wins over saved answers).
named() {
  h="$1"; shift
  in_home "$h" env git_name="CI User" git_email="ci@example.com" "$@"
}

# apply <name> [env]: deploy into $tmp/<name>, then require a clean status.
apply() {
  h="$tmp/$1"; mkdir -p "$h"
  in_home "$h" mise trust . >/dev/null 2>&1
  if [ -n "${2:-}" ]; then set -- "$1" -E "$2"; else set -- "$1"; fi
  shift
  named "$h" mise "$@" dot apply >/dev/null
  named "$h" mise "$@" dot status --missing >/dev/null || fail "$h: dot status --missing after apply"
}

check_common() {
  h="$1"
  [ -x "$h/.claude/scripts/statusline.py" ] || fail "statusline.py not executable"
  [ -x "$h/.claude/skills/hunk-review/ensure-hunk-pane.sh" ] || fail "ensure-hunk-pane.sh not executable"
  [ -f "$h/.config/nvim/init.lua" ] || fail "nvim not deployed"
  [ ! -e "$h/.config/nvim/.gitignore" ] || fail "nvim/.gitignore must not be deployed"
  [ ! -e "$h/.config/nvim/.neoconf.json" ] || fail "nvim/.neoconf.json must not be deployed"
}

check_linux() {
  h="$1"
  [ ! -e "$h/Library" ] || fail "iTerm2 profile deployed on Linux"
}

check_wsl() {
  h="$1"
  [ ! -e "$h/Library" ] || fail "iTerm2 profile deployed on WSL"
}

check_work() {
  h="$1"
  [ ! -e "$h/Library" ] || fail "iTerm2 profile deployed on work WSL"
}

check_mac() {
  h="$1"
  [ -f "$h/Library/Application Support/iTerm2/DynamicProfiles/default_profile.json" ] || fail "iTerm2 profile missing"
}

case "$(uname -s)" in
  Linux)
    echo "== linux (no module)"
    apply linux; check_common "$tmp/linux"; check_linux "$tmp/linux"
    echo "== wsl"
    apply wsl wsl; check_common "$tmp/wsl"; check_wsl "$tmp/wsl"
    echo "== wsl,work (local signing key)"
    mkdir -p "$tmp/work/.ssh"
    ssh-keygen -t ed25519 -f "$tmp/work/.ssh/git_signing_key" -N "" -q -C ci
    apply work wsl,work; check_common "$tmp/work"; check_work "$tmp/work"
    ;;
  Darwin)
    echo "== macos"
    apply mac; check_common "$tmp/mac"; check_mac "$tmp/mac"
    ;;
esac

echo PASS
