#!/bin/sh
# Seed chezmoi data from mise vars, then apply the chezmoi source in this repo.
# Called from the pre-tools hook in mise.toml (before tools, because chezmoi
# places ~/.config/mise/config.toml, which declares the tools).
#
# usage: chezmoi-apply.sh <source_dir>
# env:   GIT_NAME GIT_EMAIL USE_1PASSWORD(true|false) GIT_SIGNING_KEY_FILE(may be empty)
#        CHEZMOI_SKIP_APPLY=1   only write the config (tests)
#        CHEZMOI_APPLY_ARGS     extra args for `chezmoi apply` (tests)
set -eu

src="$1"
conf_dir="${XDG_CONFIG_HOME:-$HOME/.config}/chezmoi"

# mise vars default to "" so other mise commands work without answers; enforce here.
if [ -z "${GIT_NAME:-}" ] || [ -z "${GIT_EMAIL:-}" ]; then
  echo "error: git_name / git_email are empty. Run \`mise vars prompt\` (or re-run bootstrap with --prompt-vars)." >&2
  exit 1
fi

mkdir -p "$conf_dir"
chmod 700 "$conf_dir"
(
  umask 077
  {
    # sourceDir points at the bootstrap checkout; .chezmoiroot selects home/.
    echo "sourceDir = \"$src\""
    echo "[data]"
    echo "    git_name = \"$GIT_NAME\""
    echo "    git_email = \"$GIT_EMAIL\""
    echo "    use_1password = $USE_1PASSWORD"
    if [ -n "$GIT_SIGNING_KEY_FILE" ]; then
      echo "    git_signing_key_file = \"$GIT_SIGNING_KEY_FILE\""
    fi
  } > "$conf_dir/chezmoi.toml"
)
chmod 600 "$conf_dir/chezmoi.toml"

[ -n "${CHEZMOI_SKIP_APPLY:-}" ] && exit 0

# Run from $HOME so mise does not load this repo's mise.toml (not needed by chezmoi).
cd "$HOME"

# Pinned (not "latest") so mise need not query the GitHub API to resolve the version.
# renovate: datasource=github-releases depName=twpayne/chezmoi
chezmoi_version="2.73.1"

# The old Ansible role used 60s; mise's default is too short without a token.
export MISE_FETCH_REMOTE_VERSIONS_TIMEOUT=60

# --force: overwrite files changed at runtime (e.g. ~/.claude/settings.json) without a TTY.
# shellcheck disable=SC2086
exec mise exec "chezmoi@$chezmoi_version" -- chezmoi apply --force ${CHEZMOI_APPLY_ARGS:-}
