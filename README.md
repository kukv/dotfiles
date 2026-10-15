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
├── mise.work.toml            # module: 会社 PC(use_1password = false)
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
# 会社 WSL
curl -fsSL https://raw.githubusercontent.com/kukv/dotfiles/main/bootstrap/init.sh | sh -s -- --env wsl,work
```
mise を導入し、`mise bootstrap --from kukv/dotfiles` で OS 設定・パッケージ・dotfiles・ツールを適用します。
初回に git の name / email を聞かれます(`~/.local/state/mise/vars.toml` に保存)。WSL は適用後に `wsl --shutdown` で再起動してください。
GitHub token は `~/.local/etc/bootstrap.env`(0600)に `MISE_GITHUB_TOKEN=…` / `HOMEBREW_GITHUB_API_TOKEN=…` として置きます。

詳しい手順は `docs/setup/` を参照してください。
- [WSL 新規](docs/setup/wsl-new.md)
- [Mac](docs/setup/mac.md)(未整備)

### 再適用
週次で自動実行されます(Linux: systemd user timer、macOS: LaunchAgent)。手動では `update_os`。
チェックアウト外から `mise bootstrap --from ...` を手で実行する場合は `MISE_AUTO_ENV=true` が必要です(`.miserc.toml` の `auto_env` は cwd がチェックアウトのときだけ効くため。`update_os` なら不要)。

---

## 編集

開発用 clone(`ghq get kukv/dotfiles`)で `home/` と `mise.toml` を編集して push し、`update_os` で反映します。
bootstrap 用チェックアウト(`~/.local/share/dotfiles`)は直接編集しません(未コミットの変更があると週次の更新が止まり得るため)。

push 前に手元で試す場合は、開発用 clone で次を実行します(WSL は `-E wsl`、会社 PC は `-E wsl,work` を付ける):

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
- zsh のプラグイン(oh-my-zsh の lib と git プラグイン、zsh-users の各プラグイン、alien テーマ)は sheldon(`home/dot_config/sheldon/plugins.toml`)で取得します。版は固定し、renovate が追従します

---

## 収録物

- `~/.zshrc` / `~/.zprofile`(OS 分岐)/ `~/.gitconfig`
- `~/.config/mise/config.toml`(ツールバージョン定義)
- `~/.config/sheldon/plugins.toml`(zsh プラグイン)
- `~/.config/nvim`(LazyVim、ベンダリング)
- `~/.config/herdr/config.toml`(ターミナルワークスペースのキーバインド定義)
- `~/.config/git/ignore`、`~/.claude`(CLAUDE.md / settings.json / スキル)、`~/.codex/config.toml`
- macOS のみ: `~/.ssh/config`、iTerm2 の Dynamic Profile
