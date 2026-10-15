# Mac chezmoi 撤去の移行手順(chezmoi → mise `[dotfiles]`、oh-my-zsh → sheldon)

mise bootstrap で動いている Mac を、chezmoi を使わない構成(作業ブランチ `chezmoi-removal`)に切り替える手順。
WSL は [wsl-chezmoi-removal.md](wsl-chezmoi-removal.md) を使う。
個人 WSL → 会社 WSL → Mac の順に行い、3 台すべてで完了してから `chezmoi-removal` を main にマージする。

- コマンドはそのまま貼れるように書いてある。シェル変数は使わない。
- 自分のユーザーで、デスクトップにログインした状態のターミナル(Terminal.app / iTerm2 など)で実行する。bootstrap は LaunchAgent を GUI ログインセッション(`gui/<uid>`)に登録し直すため、SSH 経由では実行しない。
- 移行が終わるまで `chezmoi-removal` を force-push / 書き換えしない(各マシンがこのブランチを追従する)。
- `~/.oh-my-zsh` は消さない(切り戻しで使う)。消すのは 7 の後片付けで。

## 1. mise bootstrap に移行済みであることを確認する

```bash
ls ~/.local/share/dotfiles/mise.toml
launchctl print gui/$(id -u)/dev.mise.mise-bootstrap | head -3
ls ~/Library/LaunchAgents | grep os-setup
```

期待値:

- `mise.toml` のパスが出る
- `launchctl print` がエラーにならない
- 最後の `grep` で何も出ない

os-setup のままなら、main の `docs/setup/mac-migration.md` で先に mise bootstrap へ移行する(このブランチでは削除済み)。

## 2. 移行前の状態を保存する

Mac は 1Password で署名するため、`~/.ssh/allowed_signers` は無い。

```bash
mkdir -p ~/chezmoi-removal-backup
cp -p ~/.gitconfig ~/.zshrc ~/.zprofile ~/.config/mise/config.toml ~/chezmoi-removal-backup/
cp -p ~/.claude/settings.json ~/chezmoi-removal-backup/claude-settings.json
cp -p ~/.codex/config.toml ~/chezmoi-removal-backup/codex-config.toml
cp -p ~/.ssh/config ~/chezmoi-removal-backup/ssh_config
ls -la ~/chezmoi-removal-backup
time zsh -ic exit
```

最後の行の時間を控えておく(6 で比べる)。

## 3. チェックアウトを作業ブランチに切り替える

```bash
cd ~/.local/share/dotfiles
git status --short
```

何か出たら止める(未コミットの変更があると切り替えと週次の更新が失敗する)。何も出なければ続ける。

```bash
git fetch origin
git checkout chezmoi-removal
git log --oneline -1
cd ~
```

移行期間中の週次実行はこのブランチを追従する。

## 4. 差分を確認する

```bash
cd ~/.local/share/dotfiles
MISE_AUTO_ENV=true mise trust .
MISE_AUTO_ENV=true mise bootstrap plan
MISE_AUTO_ENV=true mise dot diff
cd ~
```

期待値(`mise dot diff` に出るのは次の 6 つだけ):

- `~/.zshrc`: ヘッダコメント、oh-my-zsh → mise / シェルオプション / 補完 / キーバインド / git エイリアス / sheldon への置き換え
- `~/.config/sheldon/plugins.toml`: 新規(`current: ... missing`)
- `~/.zprofile`: ヘッダコメントだけ
- `~/.gitconfig`: ヘッダコメントと `signingkey` の上のコメントだけ。name / email / `signingkey` / 署名の設定は変わらない
- `~/.ssh/config`: ヘッダコメントだけ(`Include ~/.ssh/1Password/config` は変わらない)
- `~/.config/mise/config.toml`: ヘッダコメントと、tool の `chezmoi` → `sheldon`

`~/.claude`、`~/.codex`、iTerm2 の DynamicProfiles が出たら、手元で書き換わったもの。想定外の差分があれば止める。

## 5. 適用する

Mac の `update_os` は出力をすべてログに書くため、ターミナルには何も出ない。終わるまで待ってからログを見る。
進み具合を見たい場合は、別のターミナルで `tail -f ~/.local/log/mise-bootstrap/$(date +%Y%m%d).log` を開いておく。

```bash
update_os
tail -n 50 ~/.local/log/mise-bootstrap/$(ls -t ~/.local/log/mise-bootstrap | head -1)
```

期待値:

- `update_os` がエラーなしで戻る
- ログ末尾にエラーが無い

## 6. 成功条件を確認する

```bash
cd ~/.local/share/dotfiles && MISE_AUTO_ENV=true mise dot status --missing; echo "dot-exit=$?"; cd ~
diff ~/chezmoi-removal-backup/.gitconfig ~/.gitconfig
diff ~/chezmoi-removal-backup/.zprofile ~/.zprofile
diff ~/chezmoi-removal-backup/.zshrc ~/.zshrc
diff ~/chezmoi-removal-backup/ssh_config ~/.ssh/config
ls ~/.local/share/sheldon/repos/github.com
```

期待値:

- `dot-exit=0`
- diff は 4 で見た差分と同じ
- `ls` に `eendroroy` と `zsh-users` が出る(`sheldon lock` が bootstrap task で済んでいる)

`dot status --missing` が `~/.claude/settings.json` の差異を報告したら、その間に Claude Code が書き換えたもの。`update_os` をもう一度実行する(その 1 件だけなら無視してよい)。

oh-my-zsh の git エイリアスは `g` `gst` `ga` `gaa` `gc` `gd` `gds` `gb` `gco` `gsw` `gswc` `gf` `gl` `gp` `grb` `glog` `gsta` `gstp` の 18 個だけ残る。他を使っていた場合は `~/.zshrc.local` か `home/dot_zshrc.tera` に足す。

新しいターミナルを開いて確認する:

```bash
time zsh -ic exit
zsh -ic 'alias gst; alias gl; alias gsw; alias md; [[ -o autocd ]] && echo autocd-ok'
zsh -ic 'autoload -Uz compaudit; compaudit'
```

期待値:

- 起動時間が 2 と大きく変わらない。エラーが出ない
- エイリアスが表示され、`autocd-ok` が出る
- `compaudit` は何も出ない

`compaudit` が `/opt/homebrew/share/zsh` 以下を出したら、Homebrew のディレクトリがグループ書き込み可になっている。権限を落としてから、新しいターミナルでもう一度確認する。

```bash
chmod -R go-w /opt/homebrew/share/zsh
```

目で確認する(iTerm2):

- alien のプロンプトが Nerd Font のアイコン付きで出る
- Tab で補完メニューが出る
- ↑ で入力中の文字列から始まる履歴を検索できる
- 構文ハイライトと自動補完の候補が出る
- `..` で移動できる
- ターミナルのタイトルに今のディレクトリが出る
- 貼り付けた URL が自動でクォートされる
- `Ctrl-R`(peco の履歴検索)と `Ctrl-]`(ghq のリポジトリ選択)が動く
- git の操作ができ、コミットに 1Password で署名が付く

1Password の Mac には `allowed_signers` が無く、`git log --show-signature` では検証できない(`gpg.ssh.allowedSignersFile needs to be configured` と出る)。
代わりに、ブランチを動かさずに署名付きのコミットオブジェクトを作り、署名が付くことを確かめる。

```bash
cd ~/.local/share/dotfiles && git commit-tree -S HEAD^{tree} -m signing-test | xargs git cat-file -p | grep -c gpgsig; cd ~
```

期待値:

- 1Password の承認ダイアログが出て、承認すると `1` が出る

## 切り戻し(問題があったとき)

```bash
cd ~/.local/share/dotfiles
git checkout main
cd ~
update_os
```

main の chezmoi hook が元の dotfiles を書き戻す。`~/.oh-my-zsh` は残っているので、新しいターミナルで元のシェルに戻る。
`~/.config/sheldon` と `~/.local/share/sheldon` は残るが無害。

## 7. 後片付け(3 台とも完了し、main にマージした後)

このリポジトリはマージ済みブランチを自動削除する(delete_branch_on_merge)。PR #75 のマージ後は `origin/chezmoi-removal` が消え、まだこのブランチにいるマシンは週次の `--update` が失敗する。マージ直後、次の日曜 21:00 の実行より前に、下の手順を行う。

```bash
cd ~/.local/share/dotfiles
git checkout main
git pull --ff-only
cd ~
update_os
```

先に `mise dot status --missing` が 0 で終わることを確認する:

```bash
cd ~/.local/share/dotfiles && MISE_AUTO_ENV=true mise dot status --missing; echo "dot-exit=$?"; cd ~
```

`dot-exit=0` なら次へ進み、消す:

```bash
rm -rf ~/.oh-my-zsh ~/.config/chezmoi ~/.cache/chezmoi
mise uninstall chezmoi --all
rm -f ~/.zcompdump-*
rm -rf ~/chezmoi-removal-backup
```
