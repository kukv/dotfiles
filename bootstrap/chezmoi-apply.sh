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

# Run from $HOME so mise does not load this repo's mise.toml (its required vars
# are only needed by the outer bootstrap run, not by chezmoi).
cd "$HOME"

# --force: overwrite files changed at runtime (e.g. ~/.claude/settings.json) without a TTY.
# shellcheck disable=SC2086
exec mise exec chezmoi@latest -- chezmoi apply --force ${CHEZMOI_APPLY_ARGS:-}
