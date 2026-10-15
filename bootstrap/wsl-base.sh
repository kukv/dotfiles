#!/bin/sh
# WSL package that mise bootstrap cannot declare (version-conditional). Runs from the
# post-packages hook in mise.wsl.toml on every bootstrap; keep it idempotent.
set -eu

# wslu is not packaged for Ubuntu 26.04 and later.
# shellcheck source=/dev/null
. /etc/os-release
if dpkg --compare-versions "$VERSION_ID" lt 26.04 && ! dpkg -s wslu >/dev/null 2>&1; then
  sudo apt-get install -y wslu
fi
