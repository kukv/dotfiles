# WSL chezmoi 撤去の移行手順(chezmoi → mise `[dotfiles]`、oh-my-zsh → sheldon)

mise bootstrap で動いている WSL を、chezmoi を使わない構成(作業ブランチ `chezmoi-removal`)に切り替える手順。
Mac は [mac-chezmoi-removal.md](mac-chezmoi-removal.md) を使う。
個人 WSL → 会社 WSL → Mac の順に行い、3 台すべてで完了してから `chezmoi-removal` を main にマージする。

- 前提: そのマシンが os-setup から mise bootstrap に移行済みであること(`~/.local/share/dotfiles` がある)。
- コマンドはそのまま貼れるように書いてある。シェル変数は使わない。
- 移行が終わるまで `chezmoi-removal` を force-push / 書き換えしない(各マシンがこのブランチを追従する)。
- `~/.oh-my-zsh` は消さない(切り戻しで使う)。消すのは 6 の後片付けで。

## 1. 移行前の状態を保存する

```bash
mkdir -p ~/chezmoi-removal-backup
cp -p ~/.gitconfig ~/.zshrc ~/.zprofile ~/.config/mise/config.toml ~/chezmoi-removal-backup/
cp -p ~/.claude/settings.json ~/chezmoi-removal-backup/claude-settings.json
cp -p ~/.codex/config.toml ~/chezmoi-removal-backup/codex-config.toml
[ -f ~/.ssh/config ] && cp -p ~/.ssh/config ~/chezmoi-removal-backup/ssh_config
[ -f ~/.ssh/allowed_signers ] && cp -p ~/.ssh/allowed_signers ~/chezmoi-removal-backup/allowed_signers
ls -la ~/chezmoi-removal-backup
time zsh -ic exit
```

最後の行の時間を控えておく(5 で比べる)。

## 2. チェックアウトを作業ブランチに切り替える

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

## 3. 差分を確認する

```bash
cd ~/.local/share/dotfiles
MISE_AUTO_ENV=true mise trust .
MISE_AUTO_ENV=true mise bootstrap plan
MISE_AUTO_ENV=true mise dot diff
cd ~
```

期待値: dotfiles の差分は、ヘッダコメントの書き換え、zshrc の oh-my-zsh → sheldon + 自前の設定への置き換え、`~/.config/mise/config.toml` の chezmoi → sheldon だけ。
git の name / email、署名の設定、ssh の設定が変わっていないこと。想定外の差分があれば止める。

## 4. 適用する

```bash
update_os
journalctl --user -u dev.mise.mise-bootstrap -n 50 --no-pager
```

期待値: 末尾が成功で終わっている(`Finished`)。

## 5. 成功条件を確認する

```bash
cd ~/.local/share/dotfiles && MISE_AUTO_ENV=true mise dot status --missing; echo "dot-exit=$?"; cd ~
diff ~/chezmoi-removal-backup/.gitconfig ~/.gitconfig
diff ~/chezmoi-removal-backup/.zprofile ~/.zprofile
diff ~/chezmoi-removal-backup/.zshrc ~/.zshrc
[ -f ~/chezmoi-removal-backup/ssh_config ] && diff ~/chezmoi-removal-backup/ssh_config ~/.ssh/config
[ -f ~/chezmoi-removal-backup/allowed_signers ] && diff ~/chezmoi-removal-backup/allowed_signers ~/.ssh/allowed_signers
```

期待値: `dot-exit=0`。diff はヘッダなどのコメント行と、zshrc の oh-my-zsh → sheldon の部分だけ。

oh-my-zsh の git エイリアスは `g` `gst` `ga` `gaa` `gc` `gd` `gds` `gb` `gco` `gsw` `gswc` `gf` `gl` `gp` `grb` `glog` `gsta` `gstp` の 18 個だけ残る。他を使っていた場合は `~/.zshrc.local` か `home/dot_zshrc.tera` に足す。

新しいターミナルを開いて確認する:

```bash
time zsh -ic exit
zsh -ic 'alias gst; alias gl; alias gsw; alias md; [[ -o autocd ]] && echo autocd-ok'
```

期待値: 起動時間が 1 と大きく変わらない。エラーが出ない。

```bash
zsh -ic 'autoload -Uz compaudit; compaudit'
```

期待値: 何も出ない。

`dot status --missing` が `~/.claude/settings.json` の差異を報告したら、その間に Claude Code が書き換えたもの。`update_os` をもう一度実行する(その 1 件だけなら無視してよい)。

目で確認する: alien のプロンプト / Tab の補完メニュー / ↑ で入力中の文字列から始まる履歴を検索 / 構文ハイライト / 自動補完の候補 / `..` で移動 / git の操作(コミットに署名が付く: `git log --show-signature -1`) / ターミナルのタイトルに今のディレクトリが出る / 貼り付けた URL が自動でクォートされる。

## 切り戻し(問題があったとき)

```bash
cd ~/.local/share/dotfiles
git checkout main
cd ~
update_os
```

main の chezmoi hook が元の dotfiles を書き戻す。`~/.oh-my-zsh` は残っているので、新しいターミナルで元のシェルに戻る。
`~/.config/sheldon` と `~/.local/share/sheldon` は残るが無害。

## 6. 後片付け(3 台とも完了し、main にマージした後)

このリポジトリはマージ済みブランチを自動削除する(delete_branch_on_merge)。PR #75 のマージ後は `origin/chezmoi-removal` が消え、まだこのブランチにいるマシンは週次の `--update` が失敗する。マージ直後、次の日曜 21:00 の実行より前に、3 台とも下の手順を行う。

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
