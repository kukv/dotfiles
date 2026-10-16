#!/bin/sh
# Setup that needs tools from [tools]. Runs as the `bootstrap` task (last step of
# mise bootstrap) on every run; keep it idempotent.
set -eu

# corepack shims in node's bin shadow the pnpm / yarn that mise manages, and
# mise's npm backend then picks the wrong pnpm (ERR_PNPM_NO_GLOBAL_BIN_DIR).
for shim in "$HOME"/.local/share/mise/installs/node/*/bin/pnpm; do
  if [ -e "$shim" ]; then
    mise exec node -- corepack disable
    break
  fi
done

# zsh plugins: fetch them here (plugins.toml is pinned) so a new shell does not
# clone anything at startup.
# Clones must not be group/other-writable (compaudit would flag them and compinit
# would prompt), whatever the umask; chmod also fixes clones made under umask 002.
# Retry: network / DNS flakes.
(
  umask 022
  for i in 1 2 3; do
    sheldon lock && break
    [ "$i" = 3 ] && exit 1
    sleep 10
  done
)
chmod -R go-w "${XDG_DATA_HOME:-$HOME/.local/share}/sheldon"

# herdr plugins: "<plugin_id> <repo>". Install dir layout differs across herdr
# versions, so ask herdr what is installed. kukv.github-dash (moved to the
# octoscope tool) and official.browser (deprecated upstream) no longer ship a
# plugin manifest and cannot be installed.
while read -r id repo; do
  herdr plugin list 2>/dev/null </dev/null | grep -q "^- $id " || herdr plugin install "$repo" --yes </dev/null
done <<'EOT'
herdr-file-viewer smarzban/herdr-file-viewer
hunk.diff edmundmiller/herdr-plugin-hunk
EOT

# Claude Code CLI (self-updating; install once).
if ! command -v claude >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/claude" ]; then
  curl -fsSL https://claude.ai/install.sh | bash
fi
