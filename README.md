# dotfiles

[chezmoi](https://www.chezmoi.io/) で管理する個人 dotfiles です。
WSL (Linux) と macOS で共有し、OS 固有の差分は `.tmpl` の `.chezmoi.os` 分岐で吸収します。

通常は [`kukv/os-setup`](https://github.com/kukv/os-setup) のプロビジョニングから
自動的に適用されます。

---

## リポジトリ構成

chezmoi 管理のソースは `.chezmoiroot` により **`home/` 配下**に集約しています。
リポジトリのルートにはメタ情報（README / CI / renovate 設定）だけが並びます。

```
dotfiles/
├── .chezmoiroot              # 中身は "home"（ソースルートを home/ に指定）
├── README.md
├── renovate.json
├── .github/workflows/ci.yaml # ubuntu/macOS で chezmoi apply を検証
└── home/                     # ← chezmoi のソースルート
    ├── .chezmoi.toml.tmpl        # chezmoi data（git identity）の取得定義
    ├── .chezmoiexternal.toml     # 外部依存（oh-my-zsh / プラグイン）
    ├── .chezmoiignore            # OS 別に無視するファイル
    ├── dot_zshrc.tmpl            # → ~/.zshrc
    ├── dot_zprofile.tmpl         # → ~/.zprofile
    ├── dot_gitconfig.tmpl        # → ~/.gitconfig
    ├── create_dot_zshrc.local    # → ~/.zshrc.local（初回のみ生成）
    ├── create_dot_zprofile.local # → ~/.zprofile.local（初回のみ生成）
    ├── dot_config/{mise,nvim}/   # → ~/.config/mise, ~/.config/nvim
    ├── private_dot_ssh/          # → ~/.ssh（macOS のみ）
    └── Library/                  # → ~/Library（macOS iTerm2 プロファイル）
```

chezmoi の命名規則: `dot_` → `.`、`private_` → 権限 `0600`、`create_` → 既存があれば上書きしない、`.tmpl` → テンプレート。

---

## 適用方法

### 自動（推奨）
`kukv/os-setup` の Ansible 実行が `chezmoi init --apply kukv/dotfiles` を行います。
git identity は os-setup が `~/.config/chezmoi/chezmoi.toml` に注入します。

### 手動（単体で使う場合）
```bash
chezmoi init --apply https://github.com/kukv/dotfiles.git
```
`.chezmoiroot` は自動で解釈されます。git identity（`user.name` / `user.email` / 署名鍵）は
chezmoi data として要求され、未設定なら初回に prompt されます。

---

## 編集

```bash
chezmoi edit ~/.zshrc   # ソース（home/dot_zshrc.tmpl）を編集
chezmoi apply           # ~/ に反映
```

---

## マシンローカル設定・秘密情報

マシン固有の環境変数や秘密は `~/.zshrc.local` / `~/.zprofile.local` に置きます。
これらは `create_` で**初回に一度だけ生成**され、以後 chezmoi が上書きせず、リポジトリにも追跡されません。

---

## OS 分岐の仕組み

- `.tmpl` テンプレート内で `.chezmoi.os`（`linux` / `darwin`）により分岐
  - 例: WSL は `alias ssh='ssh.exe'`、macOS は git の 1Password 署名や `~/.ssh/config`
- 外部依存（oh-my-zsh 本体・zsh プラグイン・テーマ）は `home/.chezmoiexternal.toml` で取得
  - バージョンは固定し、renovate が更新を追従します

---

## 収録物

- `~/.zshrc` / `~/.zprofile`（OS 分岐）/ `~/.gitconfig`
- `~/.config/mise/config.toml`（ツールバージョン定義）
- `~/.config/nvim`（LazyVim、ベンダリング）
- Oh-My-Zsh + プラグイン / テーマ（chezmoi externals、固定 + renovate 追従）
- macOS のみ: `~/.ssh/config`、iTerm2 の Dynamic Profile
