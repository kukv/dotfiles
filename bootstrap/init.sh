#!/bin/sh
# First-time setup for a new machine: install mise, pick this machine's modules,
# then hand over to `mise bootstrap --from kukv/dotfiles`.
#
#   curl -fsSL https://raw.githubusercontent.com/kukv/dotfiles/main/bootstrap/init.sh | sh -s -- --env wsl
#
# Run as your own user (not root); sudo is used where needed.
set -eu

ENVS=""
BRANCH="main"
REPO_URL="https://github.com/kukv/dotfiles.git"

usage() {
  cat <<'USAGE'
Usage: init.sh [--env <module,...>] [--branch <ref>]
  --env     modules for this machine (e.g. "wsl" or "wsl,work"; none on macOS)
  --branch  dotfiles branch to bootstrap from (default: main)
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --env) ENVS="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

# INIT_DRY_RUN=1 prints system-changing commands instead of running them (tests).
run() {
  if [ -n "${INIT_DRY_RUN:-}" ]; then echo "$*"; else "$@"; fi
}

case "$(uname -s)" in
  Darwin)
    if ! xcode-select -p >/dev/null 2>&1; then
      echo "Xcode Command Line Tools required: xcode-select --install" >&2
      exit 1
    fi
    if [ ! -x /opt/homebrew/bin/brew ]; then
      run /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    run /opt/homebrew/bin/brew install mise
    MISE=/opt/homebrew/bin/mise
    ;;
  Linux)
    # Scheduled runs use sudo for apt and /etc; they cannot answer a password prompt.
    sudoers="/etc/sudoers.d/$(id -un)"
    if ! sudo test -f "$sudoers"; then
      run sh -c "echo '$(id -un) ALL=(ALL) NOPASSWD: ALL' | sudo tee '$sudoers' >/dev/null && sudo chmod 440 '$sudoers'"
    fi
    run sudo apt-get update
    run sudo apt-get install -y git curl
    if [ ! -x "$HOME/.local/bin/mise" ]; then
      run sh -c "curl -fsSL https://mise.run | sh"
    fi
    MISE="$HOME/.local/bin/mise"
    ;;
  *) echo "Unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac

if [ -n "$ENVS" ]; then
  mkdir -p "$HOME/.config/mise"
  # "wsl,work" -> env = ["wsl", "work"]
  list="$(echo "$ENVS" | sed 's/[[:space:]]//g; s/,/", "/g')"
  printf 'env = ["%s"]\n' "$list" > "$HOME/.config/mise/miserc.local.toml"
fi

mkdir -p "$HOME/.local/etc"
if [ ! -f "$HOME/.local/etc/bootstrap.env" ]; then
  (umask 077 && : > "$HOME/.local/etc/bootstrap.env")
fi

run "$MISE" bootstrap --from "$REPO_URL?ref=$BRANCH" --prompt-vars
