#!/bin/sh
# Linux settings that mise bootstrap cannot declare: locale and timezone.
# Runs from the post-packages hook in mise.linux.toml on every bootstrap; keep it idempotent.
set -eu

if ! locale -a 2>/dev/null | grep -qix 'ja_JP\.utf8'; then
  sudo locale-gen ja_JP.UTF-8
fi
if ! grep -qx 'LANG=ja_JP.UTF-8' /etc/default/locale 2>/dev/null; then
  sudo update-locale LANG=ja_JP.UTF-8
fi

if command -v timedatectl >/dev/null 2>&1 &&
  [ "$(timedatectl show -p Timezone --value 2>/dev/null)" != "Asia/Tokyo" ]; then
  sudo timedatectl set-timezone Asia/Tokyo
fi
