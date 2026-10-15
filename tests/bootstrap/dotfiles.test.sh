#!/bin/sh
# Tests for the [dotfiles] entries and dotfiles hooks in mise.toml: apply them into a
# throwaway HOME per machine selection and check what only rendering can show.
# A missing source or a non-idempotent entry is caught by `mise dot status --missing`.
# shellcheck disable=SC2016,SC2088  # single-quoted greps match literal $ text; "~" is only in messages
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
  grep -qx '    name = CI User' "$h/.gitconfig" || fail ".gitconfig not rendered"
  grep -qx '    email = ci@example.com' "$h/.gitconfig" || fail ".gitconfig email"
  if grep -q linuxbrew "$h/.zprofile"; then fail "linuxbrew left in .zprofile"; fi
  if grep -q chezmoi "$h/.gitconfig" "$h/.zprofile"; then fail "chezmoi reference left"; fi
  grep -qxF 'if (( $+commands[sheldon] )); then eval "$(sheldon source)"; else autoload -Uz compinit && compinit; fi' "$h/.zshrc" || fail ".zshrc does not load sheldon"
  if grep -q 'oh-my-zsh.sh' "$h/.zshrc"; then fail "oh-my-zsh.sh still sourced"; fi
  if grep -q 'os-setup' "$h/.zshrc"; then fail "os-setup reference left in .zshrc"; fi
  if grep -q ohmyzsh "$h/.config/sheldon/plugins.toml"; then fail "oh-my-zsh still in sheldon plugins"; fi
  if grep -q 'ZSH_CACHE_DIR' "$h/.zshrc"; then fail "ZSH_CACHE_DIR left in .zshrc"; fi
  [ -f "$h/.config/sheldon/plugins.toml" ] || fail "sheldon plugins.toml missing"
}

check_linux() {
  h="$1"
  [ ! -e "$h/Library" ] || fail "iTerm2 profile deployed on Linux"
  grep -qx '    signingkey = '"$h"'/.ssh/git_signing_key.pub' "$h/.gitconfig" || fail "default signingkey"
  if grep -q 'ssh.exe' "$h/.gitconfig"; then fail "WSL sshCommand leaked into native Linux"; fi
  if grep -q 'op-ssh-sign' "$h/.gitconfig"; then fail "signer program on native Linux"; fi
  if grep -q allowedSignersFile "$h/.gitconfig"; then fail "allowedSignersFile on a 1Password machine"; fi
  grep -qx 'export JOBMAX=$(nproc)' "$h/.zprofile" || fail "linux JOBMAX"
  [ ! -e "$h/.ssh/config" ] || fail ".ssh/config deployed on Linux"
  [ ! -e "$h/.ssh/allowed_signers" ] || fail "allowed_signers on a 1Password machine"
  grep -qx "alias update_os='systemctl --user start dev.mise.mise-bootstrap.service'" "$h/.zshrc" || fail "linux update_os"
  if grep -q "alias ssh='ssh.exe'" "$h/.zshrc"; then fail "WSL ssh alias leaked into native Linux"; fi
  if grep -q 'ALIEN_USE_NERD_FONT' "$h/.zshrc"; then fail "Nerd Font on Linux"; fi
}

check_wsl() {
  h="$1"
  [ ! -e "$h/Library" ] || fail "iTerm2 profile deployed on WSL"
  grep -qx '    sshCommand = ssh.exe' "$h/.gitconfig" || fail "WSL sshCommand"
  grep -qx '    program = op-ssh-sign-wsl.exe' "$h/.gitconfig" || fail "WSL signer"
  if grep -q 'MacOS/op-ssh-sign' "$h/.gitconfig"; then fail "macOS signer leaked into WSL"; fi
  [ ! -e "$h/.ssh/config" ] || fail ".ssh/config deployed on WSL"
  [ ! -e "$h/.ssh/allowed_signers" ] || fail "allowed_signers on a 1Password WSL machine"
  grep -qx "alias ssh='ssh.exe'" "$h/.zshrc" || fail "WSL ssh alias"
}

check_work() {
  h="$1"
  [ ! -e "$h/Library" ] || fail "iTerm2 profile deployed on work WSL"
  grep -qx '    sshCommand = ssh.exe' "$h/.gitconfig" || fail "work WSL sshCommand"
  if grep -q 'op-ssh-sign' "$h/.gitconfig"; then fail "1Password signer leaked into local-key gitconfig"; fi
  grep -qx '    allowedSignersFile = '"$h"'/.ssh/allowed_signers' "$h/.gitconfig" || fail "allowedSignersFile"
  grep -q '^ci@example.com ssh-ed25519 ' "$h/.ssh/allowed_signers" || fail "allowed_signers not generated from the key"
  grep -qx "alias ssh='ssh.exe'" "$h/.zshrc" || fail "WSL ssh alias"
  [ "$(mode "$h/.ssh")" = 700 ] || fail "~/.ssh mode"
}

check_mac() {
  h="$1"
  [ -f "$h/Library/Application Support/iTerm2/DynamicProfiles/default_profile.json" ] || fail "iTerm2 profile missing"
  grep -qx '    program = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign"' "$h/.gitconfig" || fail "macOS signer"
  if grep -q 'ssh.exe' "$h/.gitconfig"; then fail "WSL routing leaked into macOS"; fi
  grep -qx 'eval "$(/opt/homebrew/bin/brew shellenv)"' "$h/.zprofile" || fail "brew shellenv"
  grep -qx 'Include ~/.ssh/1Password/config' "$h/.ssh/config" || fail "ssh config Include"
  [ "$(mode "$h/.ssh/config")" = 600 ] || fail "ssh config mode"
  grep -qx 'export ALIEN_USE_NERD_FONT=1' "$h/.zshrc" || fail "Nerd Font on macOS"
  grep -q '^export SSH_AUTH_SOCK=' "$h/.zshrc" || fail "1Password agent on macOS"
  grep -qx "alias update_os='~/.local/share/dotfiles/bootstrap/scheduled-run.sh'" "$h/.zshrc" || fail "macOS update_os"
  if grep -q "alias ssh='ssh.exe'" "$h/.zshrc"; then fail "WSL ssh alias leaked into macOS"; fi
  [ "$(mode "$h/.ssh")" = 700 ] || fail "~/.ssh mode"
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

echo "== bootstrap: empty git_name stops before the dotfiles step"
h="$tmp/noname"; mkdir -p "$h"
in_home "$h" mise trust . >/dev/null 2>&1
rc=0
in_home "$h" mise bootstrap --only dotfiles --yes >"$tmp/noname.out" 2>&1 || rc=$?
[ "$rc" -ne 0 ] || fail "bootstrap must fail when git_name is empty"
[ ! -e "$h/.gitconfig" ] || fail "dotfiles must not be applied when git_name is empty"
grep -q 'mise vars prompt' "$tmp/noname.out" || fail "message must mention mise vars prompt"

echo "== bootstrap: local files are created once and never overwritten"
h="$tmp/local"; mkdir -p "$h"
echo keep > "$h/.zprofile.local"
in_home "$h" mise trust . >/dev/null 2>&1
named "$h" mise bootstrap --only dotfiles --yes >/dev/null
grep -q 'machine-local' "$h/.zshrc.local" || fail ".zshrc.local not created"
[ "$(cat "$h/.zprofile.local")" = keep ] || fail ".zprofile.local was overwritten"

echo "== bootstrap: a quote in git_name is passed through safely"
h="$tmp/quote"; mkdir -p "$h"
in_home "$h" mise trust . >/dev/null 2>&1
in_home "$h" env git_name="O'Brien" git_email=ci@example.com mise bootstrap --only dotfiles --yes >/dev/null \
  || fail "bootstrap must succeed with a quote in git_name"
grep -qx "    name = O'Brien" "$h/.gitconfig" || fail ".gitconfig must contain the quoted name"

echo PASS
