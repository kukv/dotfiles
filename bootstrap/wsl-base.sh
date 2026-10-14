#!/bin/sh
# WSL settings that mise bootstrap cannot declare. Runs from the post-packages
# hook in mise.wsl.toml on every bootstrap; keep it idempotent.
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

# wslu is not packaged for Ubuntu 26.04 and later.
# shellcheck source=/dev/null
. /etc/os-release
if dpkg --compare-versions "$VERSION_ID" lt 26.04 && ! dpkg -s wslu >/dev/null 2>&1; then
  sudo apt-get install -y wslu
fi
