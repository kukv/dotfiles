# Mac 移行手順(os-setup → mise bootstrap)

os-setup (Ansible) で構築済みの Mac を、この dotfiles の mise bootstrap に切り替える手順。
まっさらな Mac は [mac-new.md](mac-new.md) を使う。

- コマンドはそのまま貼れるように書いてある。シェル変数は使わない(シェルを開き直しても続きから実行できる)。
- 自分のユーザーで、デスクトップにログインした状態のターミナル(Terminal.app / iTerm2 など)で実行する。LaunchAgent は GUI ログインセッション(`gui/<uid>`)にしか登録できないため、SSH 経由では実行しない。
- WSL 版([wsl-migration.md](wsl-migration.md))と違い、Homebrew と brew の mise はそのまま使う。

## 1. 移行前の状態を保存する

`~/.claude/settings.json` / `~/.claude/CLAUDE.md` は chezmoi が `--force` で上書きするため、Claude Code が実行中に書き足した設定(`autoMode` など)や手元だけの編集が消える。残したいものがあれば適用後にバックアップから戻す。

```bash
mkdir -p ~/migration-backup
cp -p ~/.gitconfig ~/.zshrc ~/.zprofile ~/.config/mise/config.toml ~/.config/chezmoi/chezmoi.toml ~/.claude/settings.json ~/migration-backup/
cp -p ~/.claude/CLAUDE.md ~/migration-backup/claude_CLAUDE.md
cp -p ~/.ssh/config ~/migration-backup/ssh_config
ls -la ~/migration-backup
```

## 2. mise を最新にする

```bash
brew upgrade mise
mise --version
```

## 3. 旧定期実行を止める

```bash
launchctl bootout gui/$(id -u)/com.kukv.os-setup
launchctl bootout gui/$(id -u)/com.kukv.os-setup-log-rotation
rm -f ~/Library/LaunchAgents/com.kukv.os-setup.plist ~/Library/LaunchAgents/com.kukv.os-setup-log-rotation.plist
rm -f ~/.local/bin/os-setup-pull.sh ~/.local/bin/os-setup-log-rotation.sh
launchctl list | grep os-setup
```

期待値:

- 最後の `grep` で何も出ない

## 4. token を移す

`os-setup.env` から必要な 2 行だけを `bootstrap.env` に写す。token は画面に出ない。

```bash
(umask 077 && grep -E '^(MISE_GITHUB_TOKEN|HOMEBREW_GITHUB_API_TOKEN)=' ~/.local/etc/os-setup.env > ~/.local/etc/bootstrap.env)
chmod 600 ~/.local/etc/bootstrap.env
sed -E 's/=.*/=<redacted>/' ~/.local/etc/bootstrap.env
```

期待値:

- `MISE_GITHUB_TOKEN=<redacted>` と `HOMEBREW_GITHUB_API_TOKEN=<redacted>` の 2 行が出る

## 5. チェックアウトを用意し、git の値を移す

`--from` の `--dry-run` はチェックアウトが無いと clone せずに止まるので、先に clone しておく。
origin URL が `--from` の URL と一致すれば、mise はそのチェックアウトを使う。
`mise vars prompt` はチェックアウトの `mise.toml` にある `[vars]` を読むので、チェックアウト内で実行する。

```bash
git clone https://github.com/kukv/dotfiles.git ~/.local/share/dotfiles
cd ~/.local/share/dotfiles
MISE_AUTO_ENV=true mise trust .
cat ~/.local/etc/extra_vars.yaml
MISE_AUTO_ENV=true mise vars prompt
MISE_AUTO_ENV=true mise vars
```

- `mise vars prompt` の質問に、extra_vars の `git.user.name` / `git.user.email` の値を入力する。
- Mac は 1Password で署名するので、module(`miserc.local.toml`)と `git_signing_key_file` は設定しない(`use_1password = true` は既定値、署名鍵は既定の `~/.ssh/git_signing_key.pub`)。

## 6. 差分を確認してから適用する

```bash
cd ~/.local/share/dotfiles
MISE_AUTO_ENV=true mise bootstrap plan
MISE_AUTO_ENV=true mise bootstrap status
MISE_AUTO_ENV=true mise bootstrap --dry-run
mise exec chezmoi@latest -- chezmoi diff --source ~/.local/share/dotfiles --exclude=externals,scripts
```

期待値:

- `plan` は brew / cask / mas のパッケージが全て `unchanged`(未宣言の formula / cask は消されない)
- `status` で `launchd mise-bootstrap ... missing`(これから作られる)
- `chezmoi diff` は `.zshrc` の `update_os` が `scheduled-run.sh` に変わる、`.gitconfig` のコメント、`~/.config/mise/config.toml` の追加行、`~/.claude/` の差分程度

想定外の削除・上書きが無いことを確認してから適用する。適用中に `brew update` / `brew upgrade --formula` も走る。

```bash
cd ~
(set -a && . ~/.local/etc/bootstrap.env && set +a && MISE_AUTO_ENV=true mise bootstrap --from https://github.com/kukv/dotfiles.git --from-dir ~/.local/share/dotfiles)
```

## 7. 成功条件を確認する

新しいターミナルを開いて実行する。

```bash
cd ~/.local/share/dotfiles && MISE_AUTO_ENV=true mise bootstrap status; cd ~
mise exec chezmoi@latest -- chezmoi diff; echo "diff-exit=$?"
diff ~/migration-backup/.gitconfig ~/.gitconfig
diff ~/migration-backup/.zshrc ~/.zshrc
diff ~/migration-backup/.zprofile ~/.zprofile
diff ~/migration-backup/ssh_config ~/.ssh/config
grep sourceDir ~/.config/chezmoi/chezmoi.toml
plutil -p ~/Library/LaunchAgents/dev.mise.mise-bootstrap.plist
launchctl print gui/$(id -u)/dev.mise.mise-bootstrap | head -5
alias update_os
```

期待値:

- `bootstrap status` が全項目 installed / unchanged / set(`launchd mise-bootstrap` も installed)
- `diff-exit=0`
- バックアップとの diff が意図した変更だけ(`update_os` の alias など)。git の name / email、署名設定、ssh 設定が変わっていないこと
- `sourceDir = "/Users/<user>/.local/share/dotfiles"`
- `plutil -p` の `ProgramArguments` が `/Users/<user>/.local/share/dotfiles/bootstrap/scheduled-run.sh`(`~` が展開済み)、`StartCalendarInterval` が日曜 21:00(`Weekday => 0`, `Hour => 21`)
- `launchctl print` でエラーにならない(ロード済み)

定期実行と同じ経路(LaunchAgent が呼ぶスクリプトそのもの)を手で一度通し、git の署名も確認する。

```bash
update_os
ls -t ~/.local/log/mise-bootstrap | head -1
tail -30 ~/.local/log/mise-bootstrap/$(ls -t ~/.local/log/mise-bootstrap | head -1)
cd ~/.local/share/dotfiles && git log -1 --show-signature; cd ~
```

期待値:

- `update_os` のログ末尾にエラーが無い
- `git log --show-signature` で署名が検証される(`Good "git" signature`)

## 8. 旧環境を片付ける

旧チェックアウト、galaxy の collections / token、ansible のログ、旧設定・秘密、旧 init.sh が入れた ansible と brew の chezmoi(mise の `[tools]` に移行済み)を消す。

```bash
rm -rf ~/.local/share/chezmoi ~/.ansible ~/.local/log/ansible
rm -f ~/.local/etc/extra_vars.yaml ~/.local/etc/os-setup.env
brew uninstall ansible chezmoi
brew autoremove --dry-run
```

`autoremove --dry-run` の一覧に使っているものが無ければ `brew autoremove` を実行する(ansible の依存だった python@3.14 などが対象になる)。
一覧に `mise.macos.toml` で宣言している formula(`tree` など)が出ていた場合は、実行後に `update_os` で入れ直す。

```bash
brew autoremove
update_os
cd ~/.local/share/dotfiles && MISE_AUTO_ENV=true mise bootstrap status | grep -v -E 'installed|unchanged|set|loaded'; cd ~
```

期待値:

- 最後の `grep` で何も出ない

os-setup が入れていた herdr plugin のうち、今は管理していない 2 つを外す(入っていなければエラーになるだけ)。

```bash
herdr plugin uninstall kukv.github-dash
herdr plugin uninstall official.browser
herdr plugin list
```

- 問題が無ければ `~/migration-backup` も削除してよい。
