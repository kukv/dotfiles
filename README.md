# dotfiles

[mise](https://mise.jdx.dev/) の bootstrap で管理する個人 dotfiles です。
WSL (Linux) と macOS で共有し、差分は mise の platform ファイル・module と、テンプレート(Tera)の分岐で吸収します。

---

## リポジトリ構成

```
dotfiles/
├── .miserc.toml              # auto_env(platform ファイルを読む)
├── mise.toml                 # 全マシン共通: vars / [dotfiles] / hooks / bootstrap task
├── mise.linux.toml           # Linux(自動で読まれる)
├── mise.macos.toml           # macOS(自動で読まれる)
├── mise.wsl.toml             # module: WSL(is_wsl、wsl.conf など)
├── mise.work.toml            # module: 作業用 PC(use_1password = false)
├── bootstrap/                # init.sh と hook / 定期実行用スクリプト
├── home/                     # ~ に配置するファイル(直下の dot_ は ~ の . に対応。*.tera はテンプレート)
├── tests/                    # bootstrap / dotfiles / zsh のテストと Docker 環境
└── docs/
```

配置先と方式は `mise.toml` の `[dotfiles]` に書いてあります(copy / template。symlink は使いません)。

## 適用方法

### 新しいマシン
```bash
# macOS
curl -fsSL https://raw.githubusercontent.com/kukv/dotfiles/main/bootstrap/init.sh | sh
# 個人 WSL
curl -fsSL https://raw.githubusercontent.com/kukv/dotfiles/main/bootstrap/init.sh | sh -s -- --env wsl
# 作業用 WSL
curl -fsSL https://raw.githubusercontent.com/kukv/dotfiles/main/bootstrap/init.sh | sh -s -- --env wsl,work
```
init.sh は次を行い、最後に `mise bootstrap --from kukv/dotfiles --prompt-vars` で OS 設定・パッケージ・dotfiles・ツールを適用します。

- mise を入れる(macOS: Homebrew、Linux: `~/.local/bin/mise`)
- `--env` の値を `~/.config/mise/miserc.local.toml` に `env = ["wsl", "work"]` の形で書く(module の選択)
- 空の `~/.local/etc/bootstrap.env`(0600)を作る
- Linux のみ: `/etc/sudoers.d/<ユーザー名>` に NOPASSWD を書く(定期実行の sudo 用)

途中で git の name / email を聞かれます(下の「mise vars」)。WSL は適用後に `wsl --shutdown` で再起動してください。

手順の全体は `docs/setup/` を参照してください。
- [WSL](docs/setup/wsl.md)
- [Mac](docs/setup/mac.md)

### 再適用
週次で自動実行されます(Linux: systemd user timer、macOS: LaunchAgent)。手動では `update_os`。
チェックアウト外から `mise bootstrap --from ...` を手で実行する場合は `MISE_AUTO_ENV=true` が必要です(`.miserc.toml` の `auto_env` は cwd がチェックアウトのときだけ効くため。`update_os` なら不要)。

---

## マシンごとの設定

### mise vars

テンプレートが参照する値です。`mise.toml` の `[vars]` で宣言しています。

| var | 設定のしかた | 用途 |
|---|---|---|
| `git_name` | 初回 bootstrap で聞かれる(必須) | `~/.gitconfig` の `user.name` |
| `git_email` | 初回 bootstrap で聞かれる(必須) | `~/.gitconfig` の `user.email`、`~/.ssh/allowed_signers` |
| `git_signing_key_file` | 任意。手で設定する | 署名用公開鍵のパス。空なら `~/.ssh/git_signing_key.pub` |
| `use_1password` | module が決める(work で `false`) | `false` ならローカル鍵で署名し `~/.ssh/allowed_signers` を作る |
| `is_wsl` | module が決める(wsl で `true`) | ssh / 署名を Windows 側(`ssh.exe` / `op-ssh-sign-wsl.exe`)に回す |

`git_name` / `git_email` が空のままだと `pre-dotfiles` hook が止めます。
答えや手で設定した値は `~/.local/state/mise/vars.toml` に保存されます。保存値は `default` より優先されますが、module(`mise.wsl.toml` / `mise.work.toml`)の `[vars]` が書いた値には負けます。`use_1password` / `is_wsl` は module の選択(`miserc.local.toml` の `env`)で決めるもので、`mise vars` では保存しません。

`mise vars` は bootstrap 用チェックアウトの `[vars]` を読むので、`-C ~/.local/share/dotfiles` を付けて実行します(付けないと `no var named ...` になる)。

```bash
# 一覧(値と、どのファイルから来ているか)
mise -C ~/.local/share/dotfiles vars

# 値を直接保存する(パスは絶対パスで書く。~ はテンプレート側で展開されない)
mise -C ~/.local/share/dotfiles vars git_signing_key_file="$HOME/.ssh/id_ed25519.pub"

# name / email を聞き直す
mise -C ~/.local/share/dotfiles vars unset git_name git_email
mise -C ~/.local/share/dotfiles vars prompt
```

変更は次の適用で `~` に反映されます(すぐ反映するなら `update_os`)。

### bootstrap.env

`~/.local/etc/bootstrap.env`(0600、リポジトリ管理外)は、定期実行と `update_os` が使う `bootstrap/scheduled-run.sh` だけが読みます。
`set -a` の下で sh の `.` で読み込むため、`KEY=value` を 1 行ずつ書きます(`export` は不要。空白や記号を含む値はクォートする)。

```
MISE_GITHUB_TOKEN=github_pat_xxxxxxxx
# macOS のみ
HOMEBREW_GITHUB_API_TOKEN=github_pat_xxxxxxxx
```

| 変数 | 対象 | 用途 |
|---|---|---|
| `MISE_GITHUB_TOKEN` | 全マシン | mise がツールの版解決・ダウンロードで叩く GitHub API の認証 |
| `HOMEBREW_GITHUB_API_TOKEN` | macOS | Homebrew が叩く GitHub API の認証 |

どちらも任意で、空ファイルのままでも動きます。無いと未認証の GitHub API の rate limit(60 回/時)に当たって失敗することがあります。
管理しているツールはすべて公開リポジトリなので、token は権限なし(fine-grained なら Public repositories の読み取りのみ、classic なら scope なし)で足ります。同じ token を両方に使って構いません。

初回の `init.sh` はこのファイルを読みません。初回から token を使う場合は、init.sh を実行するシェルで先に `export` しておきます。
対話シェルで手動実行する mise は、`~/.config/mise/config.toml` の `credential_command = "gh auth token"` で gh の token を使います。

---

## 編集

開発用 clone(`ghq get kukv/dotfiles`)で `home/` と `mise.toml` を編集して push し、`update_os` で反映します。
bootstrap 用チェックアウト(`~/.local/share/dotfiles`)は直接編集しません(未コミットの変更があると週次の更新が止まり得るため)。

push 前に手元で試す場合は、開発用 clone で次を実行します(WSL は `-E wsl`、作業用 PC は `-E wsl,work` を付ける):

```bash
mise trust .
mise dot diff     # 反映される差分
mise dot apply    # ~ に反映
```

`~` 側のファイルを直接編集しても、次の適用で上書きされます。

---

## マシンローカル設定・秘密情報

マシン固有の環境変数や秘密は `~/.zshrc.local` / `~/.zprofile.local` に置きます。
bootstrap が**初回に一度だけ生成**し(`bootstrap/local-files.sh`)、以後は上書きせず、リポジトリにも追跡されません。

---

## 差分の仕組み

- テンプレート(`home/*.tera`、Tera)の中で分岐します
  - `os()`(`linux` / `macos`): 例: macOS の git の 1Password 署名、Homebrew
  - `vars.is_wsl`(wsl module): 例: WSL の `alias ssh='ssh.exe'`、`sshCommand = ssh.exe`
  - `vars.use_1password`(work module で `false`): ローカル鍵での署名と `~/.ssh/allowed_signers`
- macOS だけのファイルは `[dotfiles]` の `variants = [{ os = "macos" }]`
- zsh のプラグイン(zsh-users の各プラグインと alien テーマ)は sheldon(`home/dot_config/sheldon/plugins.toml`)で取得します。版は固定し、renovate が追従します。oh-my-zsh は使わず、補完・キーバインド・履歴などの設定と git エイリアスは `home/dot_zshrc.tera` に直接書いています

---

## 収録物

- `~/.zshrc` / `~/.zprofile`(OS 分岐)/ `~/.gitconfig`
- `~/.config/mise/config.toml`(ツールバージョン定義)
- `~/.config/sheldon/plugins.toml`(zsh プラグイン)
- `~/.config/nvim`(LazyVim、ベンダリング)
- `~/.config/herdr/config.toml`(ターミナルワークスペースのキーバインド定義)
- `~/.config/git/ignore`、`~/.claude`(CLAUDE.md / settings.json / スキル)、`~/.codex/config.toml`
- macOS のみ: `~/.ssh/config`、iTerm2 の Dynamic Profile
