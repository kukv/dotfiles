#!/bin/sh
# Dry checks for bootstrap/init.sh: argument handling and the generated miserc.
set -eu
repo="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

out="$(INIT_DRY_RUN=1 HOME="$tmp" sh "$repo/bootstrap/init.sh" --env wsl,work --branch migration)"
grep -qx 'env = \["wsl", "work"\]' "$tmp/.config/mise/miserc.local.toml" || fail "miserc env"
echo "$out" | grep -q 'mise bootstrap --from https://github.com/kukv/dotfiles.git?ref=migration --prompt-vars' || fail "bootstrap command"
grep -qx 'export MISE_AUTO_ENV=true' "$repo/bootstrap/init.sh" || fail "init.sh must export MISE_AUTO_ENV=true"
grep -qx 'export MISE_AUTO_ENV=true' "$repo/bootstrap/scheduled-run.sh" || fail "scheduled-run.sh must export MISE_AUTO_ENV=true"
[ "$(stat -c %a "$tmp/.local/etc/bootstrap.env" 2>/dev/null || stat -f %Lp "$tmp/.local/etc/bootstrap.env")" = "600" ] || fail "bootstrap.env mode"

rm -rf "$tmp/.config"
INIT_DRY_RUN=1 HOME="$tmp" sh "$repo/bootstrap/init.sh" >/dev/null
[ ! -f "$tmp/.config/mise/miserc.local.toml" ] || fail "no --env must not write miserc"

sh "$repo/bootstrap/init.sh" --bogus >/dev/null 2>&1 && fail "unknown option must fail"
echo PASS
