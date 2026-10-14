#!/bin/sh
# Tests for bootstrap/chezmoi-apply.sh in a throwaway HOME.
set -eu
repo="$(cd "$(dirname "$0")/../.." && pwd)"
script="$repo/bootstrap/chezmoi-apply.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

run() {
  HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" "$@"
}

mkdir -p "$tmp/home"

echo "== 1Password machine: config generated, no signing key line"
run env GIT_NAME="Ada" GIT_EMAIL="ada@example.com" USE_1PASSWORD=true GIT_SIGNING_KEY_FILE="" \
  CHEZMOI_SKIP_APPLY=1 "$script" "$repo"
conf="$tmp/home/.config/chezmoi/chezmoi.toml"
[ -f "$conf" ] || fail "chezmoi.toml not created"
grep -qx "sourceDir = \"$repo\"" "$conf" || fail "sourceDir"
grep -qx '    git_name = "Ada"' "$conf" || fail "git_name"
grep -qx '    git_email = "ada@example.com"' "$conf" || fail "git_email"
grep -qx '    use_1password = true' "$conf" || fail "use_1password"
! grep -q git_signing_key_file "$conf" || fail "signing key must be omitted when empty"
[ "$(stat -c %a "$conf" 2>/dev/null || stat -f %Lp "$conf")" = "600" ] || fail "mode 600"

echo "== local-key machine: signing key written"
run env GIT_NAME="Ada" GIT_EMAIL="ada@example.com" USE_1PASSWORD=false GIT_SIGNING_KEY_FILE="/k.pub" \
  CHEZMOI_SKIP_APPLY=1 "$script" "$repo"
grep -qx '    use_1password = false' "$conf" || fail "use_1password=false"
grep -qx '    git_signing_key_file = "/k.pub"' "$conf" || fail "git_signing_key_file"

echo "== apply renders templates into HOME (externals skipped)"
run env GIT_NAME="Ada" GIT_EMAIL="ada@example.com" USE_1PASSWORD=true GIT_SIGNING_KEY_FILE="" \
  CHEZMOI_APPLY_ARGS="--exclude=externals" "$script" "$repo"
grep -q 'name = Ada' "$tmp/home/.gitconfig" || fail ".gitconfig not rendered"

echo "PASS"
