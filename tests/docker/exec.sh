#!/bin/sh
# Run a command as tech inside a test container.
# usage: exec.sh [-s dev|e2e] '<command>'   (default service: dev)
set -eu
svc=dev
if [ "${1:-}" = "-s" ]; then svc="$2"; shift 2; fi
case "$svc" in
  dev) workdir=/dotfiles ;;
  *)   workdir=/home/tech ;;
esac
exec docker compose -f "$(cd "$(dirname "$0")" && pwd)/compose.yaml" exec \
  -u tech -w "$workdir" \
  -e XDG_RUNTIME_DIR=/run/user/1000 \
  -e PATH=/home/tech/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  "$svc" bash -lc "$1"
