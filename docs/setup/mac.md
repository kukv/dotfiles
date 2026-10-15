# Mac セットアップ手順

TODO: 未整備。

## 新規

TODO

## 移行(os-setup → mise bootstrap)

TODO

手順を起こすときに漏らさないための、os-setup が Mac に残すもの:

- LaunchAgent: `~/Library/LaunchAgents/com.kukv.os-setup.plist` / `com.kukv.os-setup-log-rotation.plist`(`launchctl bootout` してから削除)
- スクリプト: `~/.local/bin/os-setup-pull.sh` / `~/.local/bin/os-setup-log-rotation.sh`
- ログ: `~/.local/log/ansible`
- 設定・秘密: `~/.local/etc/extra_vars.yaml` / `~/.local/etc/os-setup.env`(token は `bootstrap.env` へ、git の値は mise vars へ)
- brew formula: `ansible`(旧 init.sh が導入)、`chezmoi`(mise の `[tools]` に移行済み)
- `~/.ansible`(galaxy の collections / token)
- `~/.local/share/chezmoi`(旧チェックアウト)
- herdr plugin: `kukv.github-dash` / `official.browser`(今は管理していない)
