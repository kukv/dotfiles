#!/bin/sh
# Create the machine-local, untracked shell files once; never overwrite them.
# Runs from the post-dotfiles hook in mise.toml on every bootstrap; keep it idempotent.
set -eu

if [ ! -e "$HOME/.zshrc.local" ]; then
  printf '%s\n' '# ~/.zshrc.local — machine-local zsh config (untracked). Put secrets, environment variables, and per-machine tweaks here.' >"$HOME/.zshrc.local"
fi
if [ ! -e "$HOME/.zprofile.local" ]; then
  printf '%s\n' '# ~/.zprofile.local — machine-local login-shell config (untracked).' >"$HOME/.zprofile.local"
fi
