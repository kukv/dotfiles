#!/bin/sh
# Point /etc/resolv.conf at the systemd-resolved stub. Runs from the pre-repos hook
# in mise.wsl.toml, i.e. after the files and services steps have written dns.conf and
# restarted systemd-resolved; switching earlier would leave the machine without DNS.
# Keep it idempotent.
set -eu

# glibc sends A and AAAA queries in parallel on one UDP socket and WSL2's NAT
# drops one reply, so pointing resolv.conf at external servers stalls every
# lookup for 5s. Use the local systemd-resolved stub instead.
# ([bootstrap.files] cannot create symlinks.)
# Skipped in the Docker test container, where Docker bind-mounts resolv.conf.
stub="../run/systemd/resolve/stub-resolv.conf"
if [ ! -f /.dockerenv ] && [ "$(readlink /etc/resolv.conf 2>/dev/null || true)" != "$stub" ]; then
  sudo ln -sfn "$stub" /etc/resolv.conf
fi
