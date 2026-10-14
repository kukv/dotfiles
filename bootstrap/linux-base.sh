#!/bin/sh
# Linux settings that mise bootstrap cannot declare: locale, timezone and linger.
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

# Keep the user manager (and the mise-bootstrap timer) running while logged out.
# Done here, before the systemd-units step, so a fresh machine gets the timer in one run.
user="$(id -un)"
if [ "$(loginctl show-user "$user" -p Linger --value 2>/dev/null)" != "yes" ]; then
  sudo loginctl enable-linger "$user"
fi
