#!/bin/sh
# Weekly re-provisioning: pull kukv/dotfiles and re-apply mise bootstrap.
# Started by the systemd user timer (Linux) or the LaunchAgent (macOS), and by
# the `update_os` alias. Neither scheduler gives us the login shell's PATH.
set -eu
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
# cwd is not the checkout, so its .miserc.toml (auto_env) is not read; platform files need this.
export MISE_AUTO_ENV=true

# Secrets (MISE_GITHUB_TOKEN, HOMEBREW_GITHUB_API_TOKEN) via the environment,
# never argv.
if [ -f "$HOME/.local/etc/bootstrap.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$HOME/.local/etc/bootstrap.env"
  set +a
fi

if [ "$(uname -s)" = Darwin ]; then
  # Dated files so old logs age out (a single appended file never would).
  log_dir="$HOME/.local/log/mise-bootstrap"
  mkdir -p "$log_dir"
  find "$log_dir" -type f -mtime +90 -delete
  exec >>"$log_dir/$(date +%Y%m%d).log" 2>&1
else
  # Linux installs mise with mise.run; macOS updates it through Homebrew.
  mise self-update --yes || echo "mise self-update failed; continuing" >&2
fi

exec mise bootstrap --from https://github.com/kukv/dotfiles.git --from-dir "$HOME/.local/share/dotfiles" --update --yes
