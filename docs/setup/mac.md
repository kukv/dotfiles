# Mac セットアップ手順

まっさらな Mac に、この dotfiles の mise bootstrap を適用する手順。

- コマンドはそのまま貼れるように書いてある。シェル変数を使わないので、シェルを開き直しても途中の手順から続けられる。
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

## 2. (任意)GitHub token を用意する

token が無いと、未認証の GitHub API の rate limit(60 回/時)に当たってツールのインストールや Homebrew の処理が失敗することがある。
権限なしの token(fine-grained なら Public repositories の読み取りのみ、classic なら scope なし)で足りる。2 つの変数に同じ token を設定してよい。

初回の init.sh は `bootstrap.env` を読まない。初回から token を使う場合は、手順 3 を実行するシェルで先に export しておく。

```bash
export MISE_GITHUB_TOKEN=<token>
export HOMEBREW_GITHUB_API_TOKEN=<token>
```

## 3. init.sh を実行する

macOS は module を使わないので `--env` は付けない。

```bash
curl -fsSL https://raw.githubusercontent.com/kukv/dotfiles/main/bootstrap/init.sh | sh
```

- Homebrew が無ければインストーラが起動し、sudo のパスワードと確認を聞かれる。
- 途中で `Git user.name` / `Git user.email` を聞かれる。答えは `~/.local/state/mise/vars.toml` に保存され、次からは聞かれない。空のまま進めると、bootstrap は dotfiles を適用する前に止まる。
- cask のインストールで sudo のパスワードを聞かれることがある。

## 4. GitHub token を保存する

init.sh が空の `~/.local/etc/bootstrap.env`(0600)を作ってある。このファイルは定期実行と `update_os` が読み込む。
sh のスクリプトとして読み込まれるので、`KEY=value` の形で 1 行に 1 つずつ書く(`export` は不要)。

```bash
vi ~/.local/etc/bootstrap.env
```

```
MISE_GITHUB_TOKEN=<token>
HOMEBREW_GITHUB_API_TOKEN=<token>
```

token を使わないなら空のままでよい。各変数の説明は README の「bootstrap.env」にある。

## 5. 1Password の SSH agent と署名鍵を用意する

`~/.gitconfig` の設定で、git は 1Password の `op-ssh-sign` を使って署名する。`~/.ssh/config` は `~/.ssh/1Password/config` を読み込む。

1. bootstrap で入った 1Password.app にサインインする。
2. 設定 → 開発者 で「SSH エージェントを使用」と「Git コミットに署名」を有効にする。
3. 署名に使う鍵の公開鍵を `~/.ssh/git_signing_key.pub` に書く。`~/.gitconfig` の `user.signingkey` は既定でこのファイルを指す。

```bash
vi ~/.ssh/git_signing_key.pub
```

別の場所にある公開鍵を使う場合は、このファイルを作らずに、そのパスを mise の var `git_signing_key_file` に絶対パスで保存する。手順 7 の `update_os` で `~/.gitconfig` に反映される。
`-C` でチェックアウトを指定しないと、`no var named ...` で失敗する。

```bash
/opt/homebrew/bin/mise -C ~/.local/share/dotfiles vars git_signing_key_file="$HOME/.ssh/id_ed25519.pub"
```

## 6. 管理外のアプリを手で入れる

sudo が必要な pkg 形式の cask と Homebrew 外のアプリは管理していない。必要なら手で入れる。

- cloudflare-warp / logi-options+ / microsoft-office / onedrive / zoom / tart / softnet / LocalStack Desktop

## 7. 成功条件を確認する

新しいターミナルを開いて実行する。

```bash
cd ~/.local/share/dotfiles && MISE_AUTO_ENV=true mise trust . && MISE_AUTO_ENV=true mise bootstrap status && MISE_AUTO_ENV=true mise dot status --missing; echo "dot-exit=$?"; cd ~
zsh -ic 'alias gst; alias md'
plutil -p ~/Library/LaunchAgents/dev.mise.mise-bootstrap.plist
update_os
tail -30 ~/.local/log/mise-bootstrap/$(ls -t ~/.local/log/mise-bootstrap | head -1)
cd ~/.local/share/dotfiles && git commit-tree -S HEAD^{tree} -m signing-test | xargs git cat-file -p | grep -c gpgsig; cd ~
```

期待値:

- `bootstrap status` が全項目 installed / unchanged / set、`launchd mise-bootstrap` が loaded
- `dot-exit=0`
- `alias gst` / `alias md` が表示され、zsh の起動でエラーが出ない
- `plutil -p` の `ProgramArguments` が `/Users/<user>/.local/share/dotfiles/bootstrap/scheduled-run.sh`、`StartCalendarInterval` が日曜 21:00(`Weekday => 0`, `Hour => 21`)
- `update_os` のログ末尾にエラーが無い
- 1Password の承認ダイアログが出て、承認すると `1` が出る(署名付きのコミットオブジェクトが作られる。ブランチは動かない)
  - 1Password で署名する Mac には `allowed_signers` が無いため、`git log --show-signature` では検証できない
