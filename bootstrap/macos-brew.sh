#!/bin/sh
# Homebrew upkeep mise bootstrap does not cover. Runs from the post-packages hook
# in mise.macos.toml on every bootstrap; keep it idempotent.
set -eu
brew=/opt/homebrew/bin/brew

# tart / softnet are installed by hand (the tap's formula uses a syntax current
# Homebrew rejects), but keep the tap trusted so `brew upgrade` can handle them.
"$brew" tap cirruslabs/cli >/dev/null
"$brew" trust cirruslabs/cli >/dev/null

# Formulae only: upgrading casks such as docker-desktop asks for sudo, which a
# scheduled (non-interactive) run cannot answer.
"$brew" update
"$brew" upgrade --formula
