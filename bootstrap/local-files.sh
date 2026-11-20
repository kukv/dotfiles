#!/bin/sh
# Create the machine-local, untracked files once; never overwrite them.
# Runs from the post-dotfiles hook in mise.toml on every bootstrap; keep it idempotent.
set -eu
# .zshrc.local holds secrets: create both files owner-only, whatever the umask.
umask 077

if [ ! -e "$HOME/.zshrc.local" ]; then
  printf '%s\n' '# ~/.zshrc.local — machine-local zsh config (untracked). Put secrets, environment variables, and per-machine tweaks here.' >"$HOME/.zshrc.local"
fi
if [ ! -e "$HOME/.zprofile.local" ]; then
  printf '%s\n' '# ~/.zprofile.local — machine-local login-shell config (untracked).' >"$HOME/.zprofile.local"
fi
# Only where ~/.ssh/config is deployed (macOS): it Includes this file.
if [ -e "$HOME/.ssh/config" ] && [ ! -e "$HOME/.ssh/config.local" ]; then
  printf '%s\n' '# ~/.ssh/config.local — machine-local ssh hosts (untracked). Included before the managed hosts in ~/.ssh/config.' >"$HOME/.ssh/config.local"
fi
