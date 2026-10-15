# os-setup (Ansible) から mise bootstrap への移行手順

os-setup で構築済みのマシンを、この dotfiles の mise bootstrap に切り替える手順。
新規マシンは README の「セットアップ」を使う(この手順は不要)。

- コマンドはそのまま貼れるように書いてある。シェル変数は使わない(シェルを開き直しても続きから実行できる)。
- 対象: 個人 WSL / 会社 WSL / Mac。マシンごとの違いは各手順の **WSL** / **Mac** / **会社 WSL** の注記に従う。
- main へのマージ前は `-b migration` で clone する。マージ後は `-b migration` を外す。

## 1. 移行前の状態を保存する

```bash
mkdir -p ~/migration-backup
cp -p ~/.gitconfig ~/.zshrc ~/.zprofile ~/.config/mise/config.toml ~/.config/chezmoi/chezmoi.toml ~/migration-backup/
[ -f ~/.ssh/config ] && cp -p ~/.ssh/config ~/migration-backup/ssh_config
ls -la ~/migration-backup
```

存在しないファイルの `cp` エラーは無視してよい。

## 2. (WSL のみ)mise を入れ直す

linuxbrew の mise から mise.run 版に切り替える。以降の手順は brew を外した後も動くよう `~/.local/bin/mise` をフルパスで使う。

```bash
curl -fsSL https://mise.run | sh
~/.local/bin/mise --version
```

**Mac**: この手順は不要。以降の `~/.local/bin/mise` は `mise` に読み替える。

## 3. 旧定期実行を止める

**WSL**:

```bash
sudo systemctl disable --now os-setup.timer
sudo rm -f /etc/systemd/system/os-setup.service /etc/systemd/system/os-setup.timer
sudo systemctl daemon-reload
systemctl list-timers --all | grep os-setup
```

最後の行で何も出なければよい。

**Mac**:

```bash
for p in ~/Library/LaunchAgents/com.kukv.os-setup*.plist; do launchctl bootout "gui/$(id -u)" "$p" 2>/dev/null || true; rm -f "$p"; done
rm -f ~/.local/bin/os-setup-pull.sh
ls ~/Library/LaunchAgents | grep os-setup
```

## 4. 秘密情報・vars・env を設定する

旧環境の GitHub token を確認する。

```bash
grep github_token /etc/ansible/extra_vars.yaml
```

**Mac**: 代わりに `cat ~/.local/etc/os-setup.env` で確認する。

`bootstrap.env` を作り、確認した token で 2 行書く。

```bash
mkdir -p ~/.local/etc
(umask 077 && touch ~/.local/etc/bootstrap.env)
vi ~/.local/etc/bootstrap.env
```

```
MISE_GITHUB_TOKEN=<token>
HOMEBREW_GITHUB_API_TOKEN=<token>
```

git の name / email を確認し、`mise vars prompt` の質問に表示された値を入力する。

```bash
grep -E 'git_name|git_email' ~/.config/chezmoi/chezmoi.toml
~/.local/bin/mise vars prompt
```

**会社 WSL**: 署名鍵を既定(`~/.ssh/git_signing_key.pub`)以外に置いている場合だけ、`~/.local/bin/mise vars git_signing_key_file=<パス>` も実行する。

module を選ぶ。

```bash
printf 'env = ["wsl"]\n' > ~/.config/mise/miserc.local.toml
```

**会社 WSL**: `printf 'env = ["wsl", "work"]\n' > ~/.config/mise/miserc.local.toml`

**Mac**: このファイルは作らない。

## 5. (WSL のみ)linuxbrew を外す

```bash
NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"
sudo rm -rf /home/linuxbrew
```

ここで開いたシェルでは `.zprofile` が brew を見つけられずエラーを出すが、6 の適用で直る。
古いシェルの `mise` は brew の mise を呼ぶ関数なので使えない(`~/.local/bin/mise` を使う)。

## 6. 差分を確認してから適用する

`--from` の `--dry-run` はチェックアウトが無いと clone せずに止まるので、先に clone しておく
(origin URL が `--from` の URL と一致すれば、mise はそのチェックアウトを使う)。

```bash
git clone -b migration https://github.com/kukv/dotfiles.git ~/.local/share/dotfiles
cd ~/.local/share/dotfiles
MISE_AUTO_ENV=true ~/.local/bin/mise trust .
MISE_AUTO_ENV=true ~/.local/bin/mise bootstrap plan
MISE_AUTO_ENV=true ~/.local/bin/mise bootstrap --dry-run
```

想定外の削除・上書きが無いことを確認してから適用する。

```bash
cd ~
MISE_AUTO_ENV=true ~/.local/bin/mise bootstrap --from https://github.com/kukv/dotfiles.git --from-dir ~/.local/share/dotfiles
```

## 7. 成功条件を確認する

新しいシェルを開いて実行する。

```bash
cd ~/.local/share/dotfiles && MISE_AUTO_ENV=true mise bootstrap status; cd ~
mise exec chezmoi@latest -- chezmoi diff; echo "diff-exit=$?"
diff ~/migration-backup/.gitconfig ~/.gitconfig
diff ~/migration-backup/.zshrc ~/.zshrc
diff ~/migration-backup/.zprofile ~/.zprofile
[ -f ~/migration-backup/ssh_config ] && diff ~/migration-backup/ssh_config ~/.ssh/config
update_os
```

期待値:

- `bootstrap status` が全項目 installed / unchanged / set
- `diff-exit=0`
- diff は `update_os` の行と `.zprofile` の linuxbrew 行だけ
- `update_os` の結果: **WSL** は `journalctl --user -u dev.mise.mise-bootstrap -n 30 --no-pager` の末尾が `Finished`、**Mac** は `~/.local/log/mise-bootstrap/` のログ

**WSL** では続けて確認する。

```bash
readlink /etc/resolv.conf
getent hosts github.com
zsh -ic 'alias ssh'
```

期待値: `../run/systemd/resolve/stub-resolv.conf` / 即座に返る(5 秒待たされない)/ `ssh=ssh.exe`

PowerShell で `wsl --shutdown` を実行し、WSL を開き直して確認する。

```bash
systemctl --user list-timers | grep mise-bootstrap
```

## 8. 後片付け

```bash
rm -rf ~/.local/share/chezmoi
```

**WSL**:

```bash
sudo rm -rf /var/log/ansible /etc/ansible/extra_vars.yaml
```

**Mac**:

```bash
rm -f ~/.local/etc/extra_vars.yaml ~/.local/etc/os-setup.env
```

WSL の `/etc/systemd/resolved.conf` に Ansible の `# BEGIN DNS SETUP` ブロックが残るが、drop-in と同じ値なので無害。消す場合は手で削除する。
問題が無ければ `~/migration-backup` も削除してよい。

## 9. main へのマージ後

`--from` は既存チェックアウトのブランチを切り替えないので、`-b migration` で clone したマシンは手で main に切り替える
(そのままだと週次実行が migration ブランチを追い続ける)。

```bash
git -C ~/.local/share/dotfiles fetch --prune
git -C ~/.local/share/dotfiles switch main
git -C ~/.local/share/dotfiles branch -D migration
```

## 旧パス(`~/.local/share/mise/bootstrap-repo`)で移行済みのマシン

チェックアウトを `~/.local/share/dotfiles` に移して再適用する。

```bash
mise trust --untrust ~/.local/share/mise/bootstrap-repo
mv ~/.local/share/mise/bootstrap-repo ~/.local/share/dotfiles
git -C ~/.local/share/dotfiles pull --ff-only
cd ~/.local/share/dotfiles
MISE_AUTO_ENV=true mise trust .
cd ~
MISE_AUTO_ENV=true mise bootstrap --from https://github.com/kukv/dotfiles.git --from-dir ~/.local/share/dotfiles
```

確認は 7 と同じ(`bootstrap status` の systemd / LaunchAgent が新パスを指していること)。
