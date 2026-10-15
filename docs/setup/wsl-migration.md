# WSL 移行手順(os-setup → mise bootstrap)

os-setup (Ansible) で構築済みの WSL を、この dotfiles の mise bootstrap に切り替える手順。
まっさらな WSL は [wsl-new.md](wsl-new.md) を使う。

- コマンドはそのまま貼れるように書いてある。シェル変数は使わない(シェルを開き直しても続きから実行できる)。
- 途中で linuxbrew を外すため、mise は `~/.local/bin/mise` をフルパスで使う。

## 1. 移行前の状態を保存する

```bash
mkdir -p ~/migration-backup
cp -p ~/.gitconfig ~/.zshrc ~/.zprofile ~/.config/mise/config.toml ~/.config/chezmoi/chezmoi.toml ~/migration-backup/
[ -f ~/.ssh/config ] && cp -p ~/.ssh/config ~/migration-backup/ssh_config
ls -la ~/migration-backup
```

存在しないファイルの `cp` エラーは無視してよい。

## 2. mise を入れ直す

linuxbrew の mise から mise.run 版に切り替える。

```bash
curl -fsSL https://mise.run | sh
~/.local/bin/mise --version
```

## 3. 旧定期実行を止める

```bash
sudo systemctl disable --now os-setup.timer
sudo rm -f /etc/systemd/system/os-setup.service /etc/systemd/system/os-setup.timer
sudo systemctl daemon-reload
systemctl list-timers --all | grep os-setup
```

最後の行で何も出なければよい。

## 4. 秘密情報・vars・module を設定する

旧環境の GitHub token を確認する。

```bash
grep github_token /etc/ansible/extra_vars.yaml
```

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

module を選ぶ。

```bash
printf 'env = ["wsl"]\n' > ~/.config/mise/miserc.local.toml
```

work module を使うマシンは代わりに次を実行する。

```bash
printf 'env = ["wsl", "work"]\n' > ~/.config/mise/miserc.local.toml
```

work module で署名鍵を既定(`~/.ssh/git_signing_key.pub`)以外に置いている場合だけ、`~/.local/bin/mise vars git_signing_key_file=<パス>` も実行する。

## 5. linuxbrew を外す

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
git clone https://github.com/kukv/dotfiles.git ~/.local/share/dotfiles
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
journalctl --user -u dev.mise.mise-bootstrap -n 30 --no-pager
```

期待値:

- `bootstrap status` が全項目 installed / unchanged / set
- `diff-exit=0`
- バックアップとの diff が意図した変更だけ(linuxbrew の行が消え、`update_os` が systemd user unit を起動する alias になっている、など)。git の name / email や ssh 設定が変わっていないこと
- `journalctl` の末尾が `Finished`

続けて確認する。

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
sudo rm -rf /var/log/ansible /etc/ansible/extra_vars.yaml
```

`/etc/systemd/resolved.conf` に Ansible の `# BEGIN DNS SETUP` ブロックが残るが、drop-in と同じ値なので無害。消す場合は手で削除する。
問題が無ければ `~/migration-backup` も削除してよい。

## 付録: チェックアウトが旧パス(`~/.local/share/mise/bootstrap-repo`)にある場合

以前の手順で移行し、チェックアウトが旧パスに残っているマシンだけ実行する。`~/.local/share/dotfiles` に移して再適用する。

```bash
mise trust --untrust ~/.local/share/mise/bootstrap-repo
mv ~/.local/share/mise/bootstrap-repo ~/.local/share/dotfiles
git -C ~/.local/share/dotfiles pull --ff-only
cd ~/.local/share/dotfiles
MISE_AUTO_ENV=true mise trust .
cd ~
MISE_AUTO_ENV=true mise bootstrap --from https://github.com/kukv/dotfiles.git --from-dir ~/.local/share/dotfiles
```

確認は 7 と同じ(`bootstrap status` の systemd unit が新パスを指していること)。
