# WSL 新規セットアップ手順

まっさらな WSL ディストリビューションに、この dotfiles の mise bootstrap を適用する手順。

- コマンドはそのまま貼れるように書いてある。シェル変数は使わない(シェルを開き直しても続きから実行できる)。
- WSL 側のコマンドは自分のユーザーで実行する。root では実行せず、必要な箇所だけ sudo を使う。

## 1. WSL ディストリビューションを用意する

PowerShell で実行する。Ubuntu 以外を使う場合は `-d` の値を読み替える。

```powershell
wsl --install -d Ubuntu
```

初回起動時に聞かれる UNIX ユーザー名とパスワードを設定する。

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

`bootstrap.env` は週次実行(`update_os` を含む)でしか読まれず、初回実行には効かない。
初回から token を使いたい場合は、手順 4 を実行するシェルで先に export しておく。

```bash
export MISE_GITHUB_TOKEN=<token>
```

## 4. init.sh を実行する

work module を使うマシンは `--env wsl,work` にする。

```bash
curl -fsSL https://raw.githubusercontent.com/kukv/dotfiles/main/bootstrap/init.sh | sh -s -- --env wsl
```

- 最初の sudo でパスワードを 1 回聞かれる。以降は init.sh が `/etc/sudoers.d/<ユーザー名>` に NOPASSWD を書く。
- 途中で git の name / email を聞かれる(`~/.local/state/mise/vars.toml` に保存される)。
- 署名鍵を既定(`~/.ssh/git_signing_key.pub`)以外に置く場合は、完了後に `~/.local/bin/mise vars git_signing_key_file=<パス>` を実行し、手順 7 の `update_os` で反映する。

## 5. GitHub token を保存する

init.sh が空の `~/.local/etc/bootstrap.env`(0600)を作っている。週次実行で使う token を書く。

```bash
vi ~/.local/etc/bootstrap.env
```

```
MISE_GITHUB_TOKEN=<token>
```

## 6. WSL を再起動する

`/etc/wsl.conf`(hostname / resolv.conf 生成の無効化)を反映するため、PowerShell で実行する。

```powershell
wsl --shutdown
```

## 7. 成功条件を確認する

WSL を開き直して実行する。

```bash
cd ~/.local/share/dotfiles && MISE_AUTO_ENV=true mise trust . && MISE_AUTO_ENV=true mise bootstrap status && MISE_AUTO_ENV=true mise dot status --missing; echo "dot-exit=$?"; cd ~
zsh -ic 'alias gst; alias md'
readlink /etc/resolv.conf
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
- `getent hosts github.com` が即座に返る(5 秒待たされない)
- `alias ssh` が `ssh=ssh.exe`
- `list-timers` に mise-bootstrap の timer が出る
- `journalctl` の末尾が `Finished`
