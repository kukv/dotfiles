# Mac 新規セットアップ手順

まっさらな Mac に、この dotfiles の mise bootstrap を適用する手順。
os-setup (Ansible) で構築済みの Mac は [mac-migration.md](mac-migration.md) を使う。

- コマンドはそのまま貼れるように書いてある。シェル変数は使わない(シェルを開き直しても続きから実行できる)。
- 自分のユーザーで、デスクトップにログインした状態のターミナル(Terminal.app / iTerm2 など)で実行する。LaunchAgent は GUI ログインセッション(`gui/<uid>`)にしか登録できないため、SSH 経由では実行しない。

## 1. Xcode Command Line Tools を入れる

ダイアログに従ってインストールし、完了を待つ。

```bash
xcode-select --install
```

完了したら確認する。

```bash
xcode-select -p
```

期待値:

- パスが出る

## 2. App Store にサインインする

`mas` で LINE / Kindle / Xcode を入れるため、App Store.app を開いてサインインしておく。

## 3. (任意)GitHub token を用意する

`bootstrap.env` は週次実行(`update_os` を含む)でしか読まれず、初回実行には効かない。
初回から token を使いたい場合(API の rate limit 対策)は、手順 4 を実行するシェルで先に export しておく。

```bash
export MISE_GITHUB_TOKEN=<token>
export HOMEBREW_GITHUB_API_TOKEN=<token>
```

## 4. init.sh を実行する

```bash
curl -fsSL https://raw.githubusercontent.com/kukv/dotfiles/main/bootstrap/init.sh | sh
```

- Homebrew が無ければインストーラが起動し、sudo のパスワードと確認を聞かれる。
- 途中で git の name / email を聞かれる(`~/.local/state/mise/vars.toml` に保存される)。
- cask のインストールで sudo のパスワードを聞かれることがある。
- Xcode を含むため初回は時間がかかる。

## 5. GitHub token を保存する

init.sh が空の `~/.local/etc/bootstrap.env`(0600)を作っている。週次実行で使う token を書く。

```bash
vi ~/.local/etc/bootstrap.env
```

```
MISE_GITHUB_TOKEN=<token>
HOMEBREW_GITHUB_API_TOKEN=<token>
```

## 6. 1Password の SSH agent と署名鍵を用意する

`~/.gitconfig` は 1Password の `op-ssh-sign` で署名し、`~/.ssh/config` は `~/.ssh/1Password/config` を読む。

1. bootstrap で入った 1Password.app にサインインする。
2. 設定 → 開発者 で「SSH エージェントを使用」と「Git コミットに署名」を有効にする。
3. 署名に使う鍵の公開鍵を `~/.ssh/git_signing_key.pub` に保存する(`~/.gitconfig` の `user.signingkey` が指すファイル)。

```bash
vi ~/.ssh/git_signing_key.pub
```

## 7. 管理外のアプリを手で入れる

sudo が必要な pkg 形式の cask と Homebrew 外のアプリは管理していない。必要なら手で入れる。

- cloudflare-warp / logi-options+ / microsoft-office / onedrive / zoom / tart / softnet / LocalStack Desktop

## 8. 成功条件を確認する

新しいターミナルを開いて実行する。

```bash
cd ~/.local/share/dotfiles && MISE_AUTO_ENV=true mise bootstrap status; cd ~
mise exec chezmoi@latest -- chezmoi diff; echo "diff-exit=$?"
plutil -p ~/Library/LaunchAgents/dev.mise.mise-bootstrap.plist
update_os
tail -30 ~/.local/log/mise-bootstrap/$(ls -t ~/.local/log/mise-bootstrap | head -1)
cd ~/.local/share/dotfiles && git log -1 --show-signature; cd ~
```

期待値:

- `bootstrap status` が全項目 installed / unchanged / set、`launchd mise-bootstrap` が loaded
- `diff-exit=0`
- `plutil -p` の `ProgramArguments` が `/Users/<user>/.local/share/dotfiles/bootstrap/scheduled-run.sh`、`StartCalendarInterval` が日曜 21:00(`Weekday => 0`, `Hour => 21`)
- `update_os` のログ末尾にエラーが無い
- `git log --show-signature` で署名が検証される(`Good "git" signature`)
