# WSL セットアップ手順

まっさらな WSL ディストリビューションに、この dotfiles の mise bootstrap を適用する手順。

- コマンドはそのまま貼れるように書いてある。シェル変数を使わないので、シェルを開き直しても途中の手順から続けられる。
- WSL 側のコマンドは自分のユーザーで実行する。root では実行せず、必要な箇所だけ sudo を使う。

## 1. WSL ディストリビューションを用意する

PowerShell で実行する。Ubuntu 以外を使う場合は `-d` の値を読み替える。

```powershell
wsl --install -d Ubuntu
```

初回起動時に聞かれる UNIX ユーザー名とパスワードを設定する。

WSL からは外部の DNS サーバーに直接問い合わせられないので、Windows 経由で名前解決する DNS トンネルを有効にする。`%UserProfile%\.wslconfig` に次を書く(bootstrap は systemd-resolved の上流をこのトンネルの `10.255.255.254` に向ける)。

```
[wsl2]
dnsTunneling=true
```

## 2. systemd が動いていることを確認する

```bash
[ -d /run/systemd/system ] && echo systemd-ok
```

期待値:

- `systemd-ok` が出る

出ない場合は `/etc/wsl.conf` に次を書き、PowerShell で `wsl --shutdown` を実行してから WSL を開き直す。

```bash
sudo vi /etc/wsl.conf
```

```
[boot]
systemd=true
```

## 3. (任意)GitHub token を用意する

token が無いと、未認証の GitHub API の rate limit(60 回/時)に当たってツールのインストールが失敗することがある。
権限なしの token(fine-grained なら Public repositories の読み取りのみ、classic なら scope なし)で足りる。

初回の init.sh は `bootstrap.env` を読まない。初回から token を使う場合は、手順 4 を実行するシェルで先に export しておく。

```bash
export MISE_GITHUB_TOKEN=<token>
```

## 4. init.sh を実行する

WSL は `--env wsl` を付ける。
指定した値は `~/.config/mise/miserc.local.toml` に `env = [...]` として保存され、読み込む module がこれで決まる。

```bash
curl -fsSL https://raw.githubusercontent.com/kukv/dotfiles/main/bootstrap/init.sh | sh -s -- --env wsl
```

- 最初の sudo でパスワードを 1 回聞かれる。init.sh が `/etc/sudoers.d/<ユーザー名>` に NOPASSWD を書くので、以降は聞かれない。
- 途中で `Git user.name` / `Git user.email` を聞かれる。答えは `~/.local/state/mise/vars.toml` に保存され、次からは聞かれない。空のまま進めると、bootstrap は dotfiles を適用する前に止まる。

## 5. 署名鍵を置く

`~/.gitconfig` の `user.signingkey` は、既定で `~/.ssh/git_signing_key.pub` を指す。署名に使う公開鍵をこのファイルに書く。

```bash
vi ~/.ssh/git_signing_key.pub
```

別の場所にある公開鍵を使う場合は、このファイルを作らずに、そのパスを mise の var `git_signing_key_file` に絶対パスで保存する。
`-C` でチェックアウトを指定しないと、`no var named ...` で失敗する。

```bash
~/.local/bin/mise -C ~/.local/share/dotfiles vars git_signing_key_file="$HOME/.ssh/id_ed25519.pub"
```

- 個人 WSL(1Password): 署名は Windows 側の `op-ssh-sign-wsl.exe` が行う。1Password の「Git コミットに署名」で使う鍵の公開鍵を置く。
- 会社 WSL(work): ローカルの鍵で署名する。bootstrap がこの公開鍵から `~/.ssh/allowed_signers` を作る。

どちらの場合も、手順 8 の `update_os` で `~/.gitconfig` と `~/.ssh/allowed_signers` に反映される。

## 6. GitHub token を保存する

init.sh が空の `~/.local/etc/bootstrap.env`(0600)を作ってある。このファイルは定期実行と `update_os` が読み込む。
sh のスクリプトとして読み込まれるので、`KEY=value` の形で 1 行に 1 つずつ書く(`export` は不要)。

```bash
vi ~/.local/etc/bootstrap.env
```

```
MISE_GITHUB_TOKEN=<token>
```

token を使わないなら空のままでよい。各変数の説明は README の「bootstrap.env」にある。

## 7. WSL を再起動する

bootstrap が書いた `/etc/wsl.conf`(hostname の設定、resolv.conf の自動生成の停止など)を反映するため、PowerShell で実行する。

```powershell
wsl --shutdown
```

## 8. 成功条件を確認する

WSL を開き直して実行する。

```bash
cd ~/.local/share/dotfiles && MISE_AUTO_ENV=true mise trust . && MISE_AUTO_ENV=true mise bootstrap status && MISE_AUTO_ENV=true mise dot status --missing; echo "dot-exit=$?"; cd ~
zsh -ic 'alias gst; alias md'
readlink /etc/resolv.conf
resolvectl status | grep 'DNS Servers'
getent hosts github.com
zsh -ic 'alias ssh'
systemctl --user list-timers | grep mise-bootstrap
update_os
journalctl --user -u dev.mise.mise-bootstrap -n 30 --no-pager
```

期待値:

- `bootstrap status` が全項目 installed / unchanged / set
- `dot-exit=0`
- `alias gst` / `alias md` が表示され、zsh の起動でエラーが出ない
- `readlink` が `../run/systemd/resolve/stub-resolv.conf`
- `DNS Servers` が `10.255.255.254` だけ
- `getent hosts github.com` が即座に返る(5 秒待たされない)
- `alias ssh` が `ssh=ssh.exe`
- `list-timers` に mise-bootstrap の timer が出る
- `journalctl` の末尾が `Finished`
