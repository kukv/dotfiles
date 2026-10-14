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
