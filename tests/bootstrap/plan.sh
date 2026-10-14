#!/bin/sh
# Run `mise bootstrap plan` for every machine selection this repo supports.
# Fails on config errors (unknown keys, bad templates, conflicting entries).
set -eu
cd "$(dirname "$0")/../.."
mise trust .

# required vars may have no saved answer (CI); the process environment wins
# over saved answers, so this never touches this machine's real answers.
export git_name=ci git_email=ci@example.com

for envs in "" "wsl" "wsl,work"; do
  echo "== plan (env: ${envs:-none})"
  if [ -n "$envs" ]; then
    mise -E "$envs" bootstrap plan
  else
    mise bootstrap plan
  fi
done

echo "== work module flips use_1password"
[ "$(mise -E wsl,work vars use_1password)" = "false" ]
[ "$(mise vars use_1password)" = "true" ]

if [ "$(uname -s)" = Linux ]; then
  echo "== linux declarations are present"
  out="$(mise bootstrap plan 2>&1)"
  for want in apt:language-pack-ja apt:zsh apt:libssl-dev apt:qemu-system-arm \
              /etc/systemd/resolved.conf.d/dns.conf systemd-resolved; do
    echo "$out" | grep -q "$want" || { echo "FAIL: plan lacks $want" >&2; exit 1; }
  done
  # plan does not cover the login shell; status does (as "user login_shell")
  mise bootstrap status 2>&1 | grep -q 'login_shell' || { echo "FAIL: status lacks login_shell" >&2; exit 1; }
fi

if [ "$(uname -s)" = Linux ]; then
  echo "== wsl module declarations are present only with -E wsl"
  mise -E wsl bootstrap plan 2>&1 | grep -q /etc/wsl.conf || { echo "FAIL: wsl.conf missing" >&2; exit 1; }
  ! mise bootstrap plan 2>&1 | grep -q /etc/wsl.conf || { echo "FAIL: wsl.conf leaked into base" >&2; exit 1; }
fi

if [ "$(uname -s)" = Darwin ]; then
  echo "== macos declarations are present"
  out="$(mise bootstrap plan 2>&1)"
  for want in brew:mise brew:mas brew-cask:1password brew-cask:docker-desktop mas:497799835; do
    echo "$out" | grep -q "$want" || { echo "FAIL: plan lacks $want" >&2; exit 1; }
  done
fi

echo "== bootstrap task is defined"
mise tasks ls 2>/dev/null | grep -q '^bootstrap' || { echo "FAIL: bootstrap task missing" >&2; exit 1; }
