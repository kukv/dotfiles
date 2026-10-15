# chezmoi 撤去と sheldon 移行 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** chezmoi をやめて dotfiles を mise `[dotfiles]` で配置し、oh-my-zsh 一式を sheldon で読み込む構成にする。

**Architecture:** `home/` を並べ替え(直下の `.` を `dot_` に)、`mise.toml` の `[dotfiles]` で copy / template する。テンプレートは Tera で、
OS は `os()`、WSL は `vars.is_wsl`(wsl module)、1Password は `vars.use_1password`(work module)で分岐する。
zsh プラグインは `~/.config/sheldon/plugins.toml` で版を固定して sheldon が取得し、bootstrap task で `sheldon lock` する。

**Tech Stack:** mise 2026.10.x(`[dotfiles]`、`[bootstrap.hooks]`、vars、Tera)、sheldon(mise tool `sheldon`)、POSIX sh、GitHub Actions、renovate、Docker(`tests/docker`)。

**Spec:** [docs/superpowers/specs/2026-10-15-chezmoi-removal-design.md](../specs/2026-10-15-chezmoi-removal-design.md)

## Global Constraints

- 配置方式は copy / template のみ。symlink は使わない。
- `~/.claude/settings.json` と `~/.codex/config.toml` は丸ごと上書き(copy)。merge は使わない。
- WSL 判定は `vars.is_wsl`(既定 `"false"`、`mise.wsl.toml` で `"true"`)。カーネル文字列は読まない。
- vars は文字列。`vars.use_1password == "true"` / `vars.is_wsl == "true"` と文字列で比較する。
- `home/` 直下の `.` 始まりの名前は `dot_` に置き換える(例: `home/dot_zshrc.tera`、`home/dot_config/`)。ディレクトリの中身(`nvim/.gitignore` など)はそのまま。テンプレートだけ `.tera` を付ける。
- プラグインの版: zsh-users と alien は tag。renovate で追従する。oh-my-zsh は一切使わない(必要な挙動は zshrc に自分で書く)。
- 配置先の集合は現状の `chezmoi managed` と同じにする(`~/.config/nvim/.gitignore` と `.neoconf.json` は配置しない)。新規は `~/.config/sheldon/plugins.toml` のみ。
- 作業ブランチは全台の移行が終わるまで main にマージしない。push と各マシンへの適用はユーザーの確認を取ってから行う。
- worktree で作業する。`git -C <別ディレクトリ>` は使わない。
- スクリプトのコメントは英語、ドキュメントは日本語(既存に合わせる)。

## ファイル構成

| ファイル | 変更 | 役割 |
|---|---|---|
| `home/**` | rename / modify | 配置元。`git mv` で直下の `.` を `dot_` に。テンプレートは `.tera` |
| `home/dot_config/sheldon/plugins.toml` | create | zsh プラグインの定義 |
| `mise.toml` | modify | `[dotfiles]`、`is_wsl` var、pre/post-dotfiles hook。pre-tools hook を削除 |
| `mise.wsl.toml` | modify | `is_wsl = "true"` |
| `bootstrap/local-files.sh` | create | `~/.zshrc.local` / `~/.zprofile.local` を初回だけ作る |
| `bootstrap/post-tools.sh` | modify | `sheldon lock`、コメント |
| `bootstrap/init.sh` | modify | コメント |
| `bootstrap/chezmoi-apply.sh`、`tests/bootstrap/chezmoi-apply.test.sh`、`.chezmoiroot`、`home/.chezmoi*`、`home/create_*` | delete | |
| `tests/bootstrap/dotfiles.test.sh` | create | `[dotfiles]` と hook のテスト |
| `tests/bootstrap/zsh.test.sh` | create | zsh 起動のスモークテスト |
| `tests/bootstrap/plan.sh` | modify | `is_wsl` の assert |
| `.github/workflows/ci.yaml` | modify | `apply` ジョブ削除、新テスト追加 |
| `renovate.json` | modify | sheldon の plugins.toml を追従 |
| `README.md`、`docs/setup/*`、`docs/superpowers/specs/2026-10-15-mise-bootstrap-migration-design.md` | modify / create / delete | ドキュメント |

タスクの途中では chezmoi のソースが崩れるため、作業ブランチで `mise bootstrap` を実機に流さないこと(Task 7 の Docker まで実機適用しない)。

---

### Task 1: ソースの並べ替え、chezmoi 撤去、copy エントリ

**Files:**
- Rename: `home/**`(下表)
- Delete: `.chezmoiroot`、`home/.chezmoi.toml.tmpl`、`home/.chezmoiexternal.toml`、`home/.chezmoiignore`、`home/create_dot_zshrc.local`、`home/create_dot_zprofile.local`、`bootstrap/chezmoi-apply.sh`、`tests/bootstrap/chezmoi-apply.test.sh`
- Modify: `mise.toml`、`home/dot_config/mise/config.toml`
- Test: `tests/bootstrap/dotfiles.test.sh`(新規)

**Interfaces:**
- Produces: `tests/bootstrap/dotfiles.test.sh` の関数 `in_home <home> <cmd…>`、`named <home> <cmd…>`、`apply <name> [env]`、
  `check_common <home>`、`check_linux <home>`、`check_wsl <home>`、`check_work <home>`、`check_mac <home>`。後続タスクはこれらの関数の中に assert を足す。
- Produces: `[dotfiles]` テーブル(`mise.toml`)。後続タスクはここにエントリを足す。

- [ ] **Step 1: 並べ替え**

```bash
git mv home/dot_zshrc.tmpl home/dot_zshrc.tera
git mv home/dot_zprofile.tmpl home/dot_zprofile.tera
git mv home/dot_gitconfig.tmpl home/dot_gitconfig.tera
git mv home/private_dot_ssh home/dot_ssh
git mv home/dot_ssh/private_config.tmpl home/dot_ssh/config.tera
git mv home/dot_ssh/allowed_signers.tmpl home/dot_ssh/allowed_signers.tera
git mv home/dot_claude home/dot_claude
git mv home/dot_claude/scripts/executable_statusline.py home/dot_claude/scripts/statusline.py
git mv home/dot_claude/skills/hunk-review/executable_ensure-hunk-pane.sh home/dot_claude/skills/hunk-review/ensure-hunk-pane.sh
git update-index --chmod=+x home/dot_claude/skills/hunk-review/ensure-hunk-pane.sh
chmod +x home/dot_claude/skills/hunk-review/ensure-hunk-pane.sh
git mv home/dot_codex home/dot_codex
git mv home/dot_config home/dot_config
git rm -q .chezmoiroot home/.chezmoi.toml.tmpl home/.chezmoiexternal.toml home/.chezmoiignore \
  home/create_dot_zshrc.local home/create_dot_zprofile.local bootstrap/chezmoi-apply.sh tests/bootstrap/chezmoi-apply.test.sh
git ls-files -s home | awk '$1=="100755"{print $4}'
```

Expected(最後の行): `home/dot_claude/scripts/statusline.py` と `home/dot_claude/skills/hunk-review/ensure-hunk-pane.sh` の 2 行。

- [ ] **Step 2: 失敗するテストを書く**

`tests/bootstrap/dotfiles.test.sh`(`chmod +x`):

```sh
#!/bin/sh
# Tests for the [dotfiles] entries and dotfiles hooks in mise.toml: apply them into a
# throwaway HOME per machine selection and check what only rendering can show.
# A missing source or a non-idempotent entry is caught by `mise dot status --missing`.
set -eu
repo="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

# in_home <home> <cmd...>: run from the checkout with HOME=<home> and no XDG overrides,
# so mise reads only this repo's config and keeps its state under <home>.
in_home() {
  h="$1"; shift
  (cd "$repo" && env -u XDG_CONFIG_HOME -u XDG_DATA_HOME -u XDG_STATE_HOME -u XDG_CACHE_HOME HOME="$h" "$@")
}
# named <home> <cmd...>: in_home with git_name / git_email answered (the environment wins over saved answers).
named() {
  h="$1"; shift
  in_home "$h" env git_name="CI User" git_email="ci@example.com" "$@"
}

# apply <name> [env]: deploy into $tmp/<name>, then require a clean status.
apply() {
  h="$tmp/$1"; mkdir -p "$h"
  in_home "$h" mise trust . >/dev/null 2>&1
  if [ -n "${2:-}" ]; then set -- "$1" -E "$2"; else set -- "$1"; fi
  shift
  named "$h" mise "$@" dot apply >/dev/null
  named "$h" mise "$@" dot status --missing >/dev/null || fail "$h: dot status --missing after apply"
}

check_common() {
  h="$1"
  [ -x "$h/.claude/scripts/statusline.py" ] || fail "statusline.py not executable"
  [ -x "$h/.claude/skills/hunk-review/ensure-hunk-pane.sh" ] || fail "ensure-hunk-pane.sh not executable"
  [ -f "$h/.config/nvim/init.lua" ] || fail "nvim not deployed"
  [ ! -e "$h/.config/nvim/.gitignore" ] || fail "nvim/.gitignore must not be deployed"
  [ ! -e "$h/.config/nvim/.neoconf.json" ] || fail "nvim/.neoconf.json must not be deployed"
}

check_linux() {
  h="$1"
  [ ! -e "$h/Library" ] || fail "iTerm2 profile deployed on Linux"
}

check_wsl() {
  h="$1"
  [ ! -e "$h/Library" ] || fail "iTerm2 profile deployed on WSL"
}

check_work() {
  h="$1"
  [ ! -e "$h/Library" ] || fail "iTerm2 profile deployed on work WSL"
}

check_mac() {
  h="$1"
  [ -f "$h/Library/Application Support/iTerm2/DynamicProfiles/default_profile.json" ] || fail "iTerm2 profile missing"
}

case "$(uname -s)" in
  Linux)
    echo "== linux (no module)"
    apply linux; check_common "$tmp/linux"; check_linux "$tmp/linux"
    echo "== wsl"
    apply wsl wsl; check_common "$tmp/wsl"; check_wsl "$tmp/wsl"
    echo "== wsl,work (local signing key)"
    mkdir -p "$tmp/work/.ssh"
    ssh-keygen -t ed25519 -f "$tmp/work/.ssh/git_signing_key" -N "" -q -C ci
    apply work wsl,work; check_common "$tmp/work"; check_work "$tmp/work"
    ;;
  Darwin)
    echo "== macos"
    apply mac; check_common "$tmp/mac"; check_mac "$tmp/mac"
    ;;
esac

echo PASS
```

- [ ] **Step 3: 失敗を確認する**

Run: `tests/bootstrap/dotfiles.test.sh`
Expected: `FAIL: statusline.py not executable`(`[dotfiles]` がまだ無いため)

- [ ] **Step 4: `mise.toml` の chezmoi 部分を置き換える**

`mise.toml` の `# chezmoi (kept for now; …)` 見出しから `[bootstrap.hooks.pre-tools]` の `run = …` 行まで(4 行)を削除し、同じ位置に次を入れる:

```toml
# ==========================================================================
# dotfiles (copied / rendered into ~ by the dotfiles step, before tools).
# Sources live in home/ under their real names; *.tera files are templates.
# ==========================================================================
[dotfiles]
"~/.claude" = { source = "home/dot_claude", mode = "copy" }
"~/.codex/config.toml" = { source = "home/dot_codex/config.toml", mode = "copy" }
"~/.config/git/ignore" = { source = "home/dot_config/git/ignore", mode = "copy" }
"~/.config/herdr/config.toml" = { source = "home/dot_config/herdr/config.toml", mode = "copy" }
"~/.config/mise/config.toml" = { source = "home/dot_config/mise/config.toml", mode = "copy" }
# chezmoi never deployed these (it ignores dot-prefixed sources); keep it that way.
"~/.config/nvim" = { source = "home/dot_config/nvim", mode = "copy", exclude = ["/.gitignore", "/.neoconf.json"] }
"~/Library/Application Support/iTerm2/DynamicProfiles/default_profile.json" = { source = "home/Library/Application Support/iTerm2/DynamicProfiles/default_profile.json", mode = "copy", variants = [{ os = "macos" }] }
```

同じファイルの vars のコメントを直す:
- `# bootstrap/chezmoi-apply.sh fails if they are still empty.` → `# The pre-dotfiles hook fails if they are still empty.`
- `# Empty: chezmoi templates fall back to <homeDir>/.ssh/git_signing_key.pub.` → `# Empty: home/dot_gitconfig.tera falls back to ~/.ssh/git_signing_key.pub.`

`home/dot_config/mise/config.toml`:
- 1 行目 `# Managed by chezmoi — edit with: chezmoi edit ~/.config/mise/config.toml` → `# Managed by mise [dotfiles] — edit home/dot_config/mise/config.toml in kukv/dotfiles`
- 次の 2 行を削除:

```toml
# bootstrap の hook は `mise exec chezmoi@<固定版>` で別に実行する。こちらは手元の chezmoi edit / diff 用
chezmoi = "latest"
```

- [ ] **Step 5: テストが通ることを確認する**

Run: `tests/bootstrap/dotfiles.test.sh`
Expected: `PASS`(Linux では 3 パターン)。`exclude` の効き方や `variants` が想定と違って失敗した場合は、mise のドキュメント(`https://mise.jdx.dev/dotfiles/reference.html`)で書き方を確認して直す。テストのほうを緩めて通すことはしない。

- [ ] **Step 6: shellcheck**

Run: `shellcheck tests/bootstrap/dotfiles.test.sh`
Expected: 出力なし

- [ ] **Step 7: Commit**

```bash
git add -A home mise.toml tests/bootstrap
git commit -m "refactor(dotfiles): chezmoi をやめ、home/ を mise [dotfiles] の copy で配置する"
```

---

### Task 2: テンプレート(gitconfig / zprofile / ssh)と is_wsl

**Files:**
- Modify: `home/dot_gitconfig.tera`、`home/dot_zprofile.tera`、`home/dot_ssh/config.tera`、`home/dot_ssh/allowed_signers.tera`、`mise.toml`、`mise.wsl.toml`
- Test: `tests/bootstrap/dotfiles.test.sh`、`tests/bootstrap/plan.sh`

**Interfaces:**
- Consumes: Task 1 の `check_*` 関数と `[dotfiles]`。
- Produces: var `is_wsl`(`"true"` / `"false"`)。Task 3 の zshrc が使う。

- [ ] **Step 1: 失敗するテストを足す**

`tests/bootstrap/dotfiles.test.sh` の各関数の末尾に追記する。

`check_common` に:

```sh
  grep -qx '    name = CI User' "$h/.gitconfig" || fail ".gitconfig not rendered"
  grep -qx '    email = ci@example.com' "$h/.gitconfig" || fail ".gitconfig email"
  if grep -q linuxbrew "$h/.zprofile"; then fail "linuxbrew left in .zprofile"; fi
  if grep -q chezmoi "$h/.gitconfig" "$h/.zprofile"; then fail "chezmoi reference left"; fi
```

`check_linux` に:

```sh
  grep -qx '    signingkey = '"$h"'/.ssh/git_signing_key.pub' "$h/.gitconfig" || fail "default signingkey"
  if grep -q 'ssh.exe' "$h/.gitconfig"; then fail "WSL sshCommand leaked into native Linux"; fi
  if grep -q 'op-ssh-sign' "$h/.gitconfig"; then fail "signer program on native Linux"; fi
  if grep -q allowedSignersFile "$h/.gitconfig"; then fail "allowedSignersFile on a 1Password machine"; fi
  grep -qx 'export JOBMAX=$(nproc)' "$h/.zprofile" || fail "linux JOBMAX"
  [ ! -e "$h/.ssh/config" ] || fail ".ssh/config deployed on Linux"
  [ ! -e "$h/.ssh/allowed_signers" ] || fail "allowed_signers on a 1Password machine"
```

`check_wsl` に:

```sh
  grep -qx '    sshCommand = ssh.exe' "$h/.gitconfig" || fail "WSL sshCommand"
  grep -qx '    program = op-ssh-sign-wsl.exe' "$h/.gitconfig" || fail "WSL signer"
  if grep -q 'MacOS/op-ssh-sign' "$h/.gitconfig"; then fail "macOS signer leaked into WSL"; fi
  [ ! -e "$h/.ssh/config" ] || fail ".ssh/config deployed on WSL"
```

`check_work` に:

```sh
  grep -qx '    sshCommand = ssh.exe' "$h/.gitconfig" || fail "work WSL sshCommand"
  if grep -q 'op-ssh-sign' "$h/.gitconfig"; then fail "1Password signer leaked into local-key gitconfig"; fi
  grep -qx '    allowedSignersFile = '"$h"'/.ssh/allowed_signers' "$h/.gitconfig" || fail "allowedSignersFile"
  grep -q '^ci@example.com ssh-ed25519 ' "$h/.ssh/allowed_signers" || fail "allowed_signers not generated from the key"
  [ "$(mode "$h/.ssh")" = 700 ] || fail "~/.ssh mode"
```

`check_mac` に:

```sh
  grep -qx '    program = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign"' "$h/.gitconfig" || fail "macOS signer"
  if grep -q 'ssh.exe' "$h/.gitconfig"; then fail "WSL routing leaked into macOS"; fi
  grep -qx 'eval "$(/opt/homebrew/bin/brew shellenv)"' "$h/.zprofile" || fail "brew shellenv"
  grep -qx 'Include ~/.ssh/1Password/config' "$h/.ssh/config" || fail "ssh config Include"
  [ "$(mode "$h/.ssh/config")" = 600 ] || fail "ssh config mode"
  [ "$(mode "$h/.ssh")" = 700 ] || fail "~/.ssh mode"
```

`tests/bootstrap/plan.sh` の `echo "== work module flips use_1password"` ブロックの直後に:

```sh
echo "== wsl module sets is_wsl"
[ "$(mise -E wsl vars is_wsl)" = "true" ]
[ "$(mise vars is_wsl)" = "false" ]
```

- [ ] **Step 2: 失敗を確認する**

Run: `tests/bootstrap/dotfiles.test.sh`
Expected: `FAIL: .gitconfig not rendered`

- [ ] **Step 3: テンプレートを書く**

`home/dot_gitconfig.tera`(全置換):

```
{%- set op = vars.use_1password == "true" -%}
{%- set wsl = vars.is_wsl == "true" -%}
{%- set key_file = vars.git_signing_key_file -%}
{%- if key_file == "" -%}{%- set key_file = env.HOME ~ "/.ssh/git_signing_key.pub" -%}{%- endif -%}
# Managed by mise [dotfiles] — edit home/dot_gitconfig.tera in kukv/dotfiles
[user]
    name = {{ vars.git_name }}
    email = {{ vars.git_email }}
    # git requires user.signingkey for SSH signing even when a signing program
    # is configured, so pin the public-key file here (the signer resolves the
    # matching private key). Override via mise var git_signing_key_file.
    signingkey = {{ key_file }}
[core]
    quotepath = false
{%- if wsl %}
    # WSL: route git's ssh through the Windows host, where the SSH agent (1Password or Windows OpenSSH) holds the key.
    sshCommand = ssh.exe
{%- endif %}
[ghq]
    root = {{ env.HOME }}/dev/ghq
[color]
    ui = auto
[gpg]
    format = ssh
[gpg "ssh"]
{%- if op %}
{%- if os() == "macos" %}
    program = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign"
{%- elif wsl %}
    # WSL: resolved via the Windows PATH (WSL interop), same mechanism as ssh.exe above
    program = op-ssh-sign-wsl.exe
{%- endif %}
{%- else %}
    # No 1Password: verify local-key signatures against this file (rendered from home/dot_ssh/allowed_signers.tera).
    allowedSignersFile = {{ env.HOME }}/.ssh/allowed_signers
{%- endif %}
[commit]
    gpgsign = true
[tag]
    gpgsign = true
```

`home/dot_zprofile.tera`(全置換):

```
# Managed by mise [dotfiles] — edit home/dot_zprofile.tera in kukv/dotfiles
# Machine-local, untracked overrides go in ~/.zprofile.local

export PATH="$HOME/.local/bin:$PATH"
{% if os() == "macos" %}
# ========================================================
# = Homebrew (macOS)
# ========================================================
eval "$(/opt/homebrew/bin/brew shellenv)"

# ========================================================
# = JetBrains Toolbox
# ========================================================
export PATH="${PATH}:${HOME}/Library/Application Support/JetBrains/Toolbox/scripts"

# ========================================================
# = Locale
# ========================================================
export LC_ALL=en_US.UTF-8

# ========================================================
# = Build parallelization
# ========================================================
export JOBMAX=$(sysctl -n hw.logicalcpu)
{%- else %}
# ========================================================
# = Build parallelization
# ========================================================
export JOBMAX=$(nproc)
{%- endif %}
export MAKEFLAGS="-j$JOBMAX"

# ========================================================
# = Machine-local overrides (untracked)
# ========================================================
[ -f ~/.zprofile.local ] && source ~/.zprofile.local
```

`home/dot_ssh/config.tera`: 先頭 4 行(`# Managed by chezmoi …` 〜 `{{- if $op }}`)を次の 2 行に、`{{- end }}` を `{%- endif %}` に置き換える。`Host github` 以降は変更しない。

```
# Managed by mise [dotfiles] — edit home/dot_ssh/config.tera in kukv/dotfiles
{%- if vars.use_1password == "true" %}
```

(置き換え後の先頭は `# Managed…` / `{%- if … %}` / 空行 / `Include ~/.ssh/1Password/config` / `{%- endif %}` / 空行 / `Host github`。)

`home/dot_ssh/allowed_signers.tera`(全置換):

```
{# Local-key machines only: verify our own commit signatures. Renders empty (and the
   [dotfiles] entry's remove_empty deletes the file) on 1Password machines and until
   the key file exists. #}
{%- set key_file = vars.git_signing_key_file -%}
{%- if key_file == "" -%}{%- set key_file = env.HOME ~ "/.ssh/git_signing_key.pub" -%}{%- endif -%}
{%- if vars.use_1password != "true" and key_file is file -%}
{{ vars.git_email }} {{ read_file(path=key_file) | trim }}
{% endif -%}
```

- [ ] **Step 4: エントリと var を足す**

`mise.toml` の `[dotfiles]` の先頭に:

```toml
"~/.zprofile" = { source = "home/dot_zprofile.tera", mode = "template" }
"~/.gitconfig" = { source = "home/dot_gitconfig.tera", mode = "template" }
"~/.ssh" = { permissions = "0700" }
"~/.ssh/config" = { source = "home/dot_ssh/config.tera", mode = "template", permissions = "0600", variants = [{ os = "macos" }] }
"~/.ssh/allowed_signers" = { source = "home/dot_ssh/allowed_signers.tera", mode = "template", remove_empty = true }
```

`mise.toml` の `[vars.git_signing_key_file]` ブロックの後に:

```toml
# Overridden to "true" by mise.wsl.toml (templates route ssh / signing through Windows).
[vars.is_wsl]
default = "false"
```

`mise.wsl.toml` の先頭コメント行の直後に:

```toml

[vars]
is_wsl = "true"
```

- [ ] **Step 5: テストが通ることを確認する**

Run: `tests/bootstrap/dotfiles.test.sh && tests/bootstrap/plan.sh`
Expected: 両方 exit 0、`PASS`。

失敗したときの観点:
- Tera の `set` が `if` の中で効いていない(`signingkey` が空になる)。
- `key_file is file` が変数を受け付けない。
- `os()` の戻り値が `macos` ではない。

いずれの場合も、mise のテンプレートのドキュメント(`https://mise.jdx.dev/templates.html`)で確認して書き方を直す。

- [ ] **Step 6: chezmoi の出力と比べる(一度だけ。コミットしない)**

この WSL 機の chezmoi(`/home/tech/.local/share/mise/installs/chezmoi/2.73.1/chezmoi`)で main をレンダリングし、mise の出力と diff する。
chezmoi はカーネル文字列で WSL と判定するため、比べられるのは `wsl` と `wsl,work` だけ(素の Linux は Step 1 の assert でカバーする)。
スクリプトは scratchpad に置く。`<scratch>` は Claude の scratchpad の絶対パスに読み替える。

`<scratch>/equiv.sh`:

```sh
#!/bin/sh
# Compare chezmoi (origin/main) with mise [dotfiles] renders for the same HOME path.
# usage: equiv.sh <repo> <workdir> <env> <use_1password true|false>
set -eu
repo="$1"; w="$2"; envs="$3"; op="$4"
chezmoi=/home/tech/.local/share/mise/installs/chezmoi/2.73.1/chezmoi
rm -rf "$w"; mkdir -p "$w/src" "$w/home"
(cd "$repo" && git archive origin/main home .chezmoiroot) | tar -x -C "$w/src"
rm "$w/src/home/.chezmoiexternal.toml"
h="$w/home"
key() { mkdir -p "$h/.ssh"; [ "$op" = true ] || ssh-keygen -t ed25519 -f "$h/.ssh/git_signing_key" -N "" -q -C ci; }
key
printf '[data]\n    git_name = "CI User"\n    git_email = "ci@example.com"\n    use_1password = %s\n' "$op" > "$w/chezmoi.toml"
HOME="$h" "$chezmoi" apply --source "$w/src" --destination "$h" -c "$w/chezmoi.toml" --no-tty --force --exclude=scripts
mkdir -p "$w/chezmoi"
for f in .gitconfig .zprofile .ssh/allowed_signers; do [ -e "$h/$f" ] && cp "$h/$f" "$w/chezmoi/$(echo "$f" | tr / _)"; done
rm -rf "$h"; mkdir -p "$h"; key
(cd "$repo" && env -u XDG_CONFIG_HOME -u XDG_DATA_HOME -u XDG_STATE_HOME -u XDG_CACHE_HOME HOME="$h" mise trust . >/dev/null 2>&1)
(cd "$repo" && env -u XDG_CONFIG_HOME -u XDG_DATA_HOME -u XDG_STATE_HOME -u XDG_CACHE_HOME HOME="$h" git_name="CI User" git_email=ci@example.com mise -E "$envs" dot apply >/dev/null)
for f in .gitconfig .zprofile .ssh/allowed_signers; do
  echo "--- $f"
  diff -u "$w/chezmoi/$(echo "$f" | tr / _)" "$h/$f" || true
done
```

Run:

```bash
sh <scratch>/equiv.sh "$PWD" <scratch>/equiv-wsl wsl true
sh <scratch>/equiv.sh "$PWD" <scratch>/equiv-work wsl,work false
```

Expected: 差分は `#` で始まるコメント行(ヘッダ、`Override via …`、`Detect via the kernel string …`、`(generated by chezmoi)`)だけ。
空行の増減や設定行の差分が出たら、テンプレートの空白制御(`{%-` / `-%}`)を直して再実行する。

- [ ] **Step 7: shellcheck と Commit**

```bash
shellcheck tests/bootstrap/*.sh
git add home mise.toml mise.wsl.toml tests/bootstrap
git commit -m "feat(dotfiles): gitconfig / zprofile / ssh を Tera テンプレートにし、WSL 判定を is_wsl var にする"
```

---

### Task 3: zsh(sheldon)

**Files:**
- Create: `home/dot_config/sheldon/plugins.toml`、`tests/bootstrap/zsh.test.sh`
- Modify: `home/dot_zshrc.tera`、`home/dot_config/mise/config.toml`、`mise.toml`、`bootstrap/post-tools.sh`
- Test: `tests/bootstrap/dotfiles.test.sh`、`tests/bootstrap/zsh.test.sh`

**Interfaces:**
- Consumes: `vars.is_wsl`、`vars.use_1password`、Task 1 の `check_*`。
- Produces: `~/.config/sheldon/plugins.toml` のプラグイン名 `zsh-completions` `omz-setup` `ohmyzsh` `alien` `zsh-autosuggestions` `zsh-history-substring-search` `omz-list-colors` `zsh-syntax-highlighting`(Task 5 の renovate が `github = "…"` / `tag = "…"` / `rev = "…"` の行に依存する)。

- [ ] **Step 1: 失敗するテストを足す**

`check_common` に:

```sh
  grep -qx 'eval "$(sheldon source)"' "$h/.zshrc" || fail ".zshrc does not load sheldon"
  if grep -q 'oh-my-zsh.sh' "$h/.zshrc"; then fail "oh-my-zsh.sh still sourced"; fi
  if grep -q 'os-setup' "$h/.zshrc"; then fail "os-setup reference left in .zshrc"; fi
  [ -f "$h/.config/sheldon/plugins.toml" ] || fail "sheldon plugins.toml missing"
```

`check_linux` に:

```sh
  grep -qx "alias update_os='systemctl --user start dev.mise.mise-bootstrap.service'" "$h/.zshrc" || fail "linux update_os"
  if grep -q "alias ssh='ssh.exe'" "$h/.zshrc"; then fail "WSL ssh alias leaked into native Linux"; fi
  if grep -q 'ALIEN_USE_NERD_FONT' "$h/.zshrc"; then fail "Nerd Font on Linux"; fi
```

`check_wsl` と `check_work` の両方に:

```sh
  grep -qx "alias ssh='ssh.exe'" "$h/.zshrc" || fail "WSL ssh alias"
```

`check_mac` に:

```sh
  grep -qx 'export ALIEN_USE_NERD_FONT=1' "$h/.zshrc" || fail "Nerd Font on macOS"
  grep -q '^export SSH_AUTH_SOCK=' "$h/.zshrc" || fail "1Password agent on macOS"
  grep -qx "alias update_os='~/.local/share/dotfiles/bootstrap/scheduled-run.sh'" "$h/.zshrc" || fail "macOS update_os"
  if grep -q "alias ssh='ssh.exe'" "$h/.zshrc"; then fail "WSL ssh alias leaked into macOS"; fi
```

`tests/bootstrap/zsh.test.sh`(新規、`chmod +x`):

```sh
#!/bin/sh
# Start an interactive zsh with the deployed ~/.zshrc and sheldon plugins in a
# throwaway HOME. Needs zsh, and network for sheldon to clone the plugins.
set -eu
repo="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

command -v zsh >/dev/null 2>&1 || fail "zsh is required"
# Resolve sheldon before HOME changes: mise installs live under the real HOME.
sheldon_bin="$(mise x sheldon@latest -- sh -c 'command -v sheldon')"
h="$tmp/home"
mkdir -p "$h"

# run <dir> <cmd...>: run in <dir> with the throwaway HOME and sheldon on PATH.
run() {
  d="$1"; shift
  (cd "$d" && env -u XDG_CONFIG_HOME -u XDG_DATA_HOME -u XDG_STATE_HOME -u XDG_CACHE_HOME \
    HOME="$h" PATH="$(dirname "$sheldon_bin"):$PATH" MISE_STATUS_MESSAGE_MISSING_TOOLS=never \
    git_name="CI User" git_email="ci@example.com" "$@")
}

run "$repo" mise trust . >/dev/null 2>&1
run "$repo" mise dot apply >/dev/null
run "$h" sheldon lock

out="$(run "$h" zsh -ic '
  alias gst >/dev/null || print -u2 "no gst alias (oh-my-zsh git plugin)"
  alias md >/dev/null || print -u2 "no md alias (oh-my-zsh lib/directories)"
  [[ -o autocd ]] || print -u2 "autocd off (oh-my-zsh lib/directories)"
  (( $+functions[compdef] )) || print -u2 "compinit did not run"
  (( $+functions[_zsh_autosuggest_start] )) || print -u2 "zsh-autosuggestions not loaded"
  (( $+functions[_zsh_highlight] )) || print -u2 "zsh-syntax-highlighting not loaded"
  (( $+functions[history-substring-search-up] )) || print -u2 "zsh-history-substring-search not loaded"
  [[ -n $PROMPT ]] || print -u2 "empty PROMPT (alien)"
  print ok' 2>"$tmp/err")" || true
if [ -s "$tmp/err" ]; then cat "$tmp/err" >&2; fail "zsh startup wrote to stderr"; fi
[ "$out" = ok ] || fail "unexpected output: $out"
echo PASS
```

- [ ] **Step 2: 失敗を確認する**

Run: `tests/bootstrap/dotfiles.test.sh`
Expected: `FAIL: .zshrc does not load sheldon`

- [ ] **Step 3: plugins.toml と zshrc を書く**

oh-my-zsh の rev は計画作成時点の master(`964ddf789b022b6958b27d02d7fa54f552de21e9`、2026-10-13)。実装時に `gh api repos/ohmyzsh/ohmyzsh/commits/master --jq .sha` で最新に更新してよい。

`home/dot_config/sheldon/plugins.toml`(新規):

```toml
# Managed by mise [dotfiles] — edit home/dot_config/sheldon/plugins.toml in kukv/dotfiles.
# Plugins load in this order. Versions are pinned; renovate tracks them (see renovate.json).
shell = "zsh"

# Its plugin file adds src/ to fpath, so it must come before compinit.
[plugins.zsh-completions]
github = "zsh-users/zsh-completions"
tag = "0.36.0"

# What oh-my-zsh.sh did before loading lib/ (ZSH_CACHE_DIR is exported in ~/.zshrc).
[plugins.omz-setup]
inline = '''
mkdir -p "$ZSH_CACHE_DIR/completions"
(( ${fpath[(Ie)$ZSH_CACHE_DIR/completions]} )) || fpath=("$ZSH_CACHE_DIR/completions" $fpath)
autoload -Uz compinit && compinit
'''

# oh-my-zsh: only lib/ (completion, key bindings, history, directories, ...) and the git plugin.
[plugins.ohmyzsh]
github = "ohmyzsh/ohmyzsh"
rev = "964ddf789b022b6958b27d02d7fa54f552de21e9"
use = ["lib/*.zsh", "plugins/git/git.plugin.zsh"]

# Theme. Its libs/ are git submodules, which sheldon clones recursively.
[plugins.alien]
github = "eendroroy/alien"
tag = "2.1.2"
use = ["alien.zsh"]

[plugins.zsh-autosuggestions]
github = "zsh-users/zsh-autosuggestions"
tag = "v0.7.1"

[plugins.zsh-history-substring-search]
github = "zsh-users/zsh-history-substring-search"
tag = "v1.1.0"

# oh-my-zsh.sh ran this after loading the theme.
[plugins.omz-list-colors]
inline = '[[ -z "$LS_COLORS" ]] || zstyle ":completion:*" list-colors "${(s.:.)LS_COLORS}"'

# Must be loaded last.
[plugins.zsh-syntax-highlighting]
github = "zsh-users/zsh-syntax-highlighting"
tag = "0.8.0"
```

`home/dot_zshrc.tera`: 先頭から `# = mise` セクション(`eval "$(mise activate zsh)"` の行)までを次で置き換える。`# = peco` 以降は残し、そのうち `alias ccw='claude -w'` の後ろから `# = Zsh history` の直前まで(update_os と WSL の分岐)も次で置き換える。

先頭部分:

```
# Managed by mise [dotfiles] — edit home/dot_zshrc.tera in kukv/dotfiles
# Machine-local, untracked overrides go in ~/.zshrc.local

# ==========================================================================
# = mise
# ==========================================================================
# Before sheldon below: sheldon is installed as a mise tool.
eval "$(mise activate zsh)"

# ==========================================================================
# = alien theme (read when sheldon loads it)
# ==========================================================================
export ALIEN_SECTIONS_LEFT=(
    time
    user
    path
    ssh
    venv
    vcs_branch:async
    vcs_status:async
    vcs_dirty:async
    exit
    newline
    prompt
)
export ALIEN_SECTION_TIME_FORMAT="%Y-%m-%d %H:%M:%S"
export ALIEN_SECTION_USER_HOST=1
export ALIEN_THEME="blue"
{%- if os() == "macos" %}
export ALIEN_USE_NERD_FONT=1
{%- endif %}

# ==========================================================================
# = zsh plugins (sheldon: ~/.config/sheldon/plugins.toml)
# ==========================================================================
# oh-my-zsh's lib/*.zsh keeps its caches here (oh-my-zsh.sh used to set it).
export ZSH_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
eval "$(sheldon source)"
{% if os() == "macos" %}
{%- if vars.use_1password == "true" %}
# ==========================================================================
# = 1Password SSH agent (macOS)
# ==========================================================================
export SSH_AUTH_SOCK=~/Library/Group\ Containers/2BUA8C4S2C.com.1password/t/agent.sock
{% endif %}
# ==========================================================================
# = Docker completions (macOS)
# ==========================================================================
fpath=(${HOME}/.docker/completions $fpath)
{%- endif %}
```

update_os と WSL の分岐:

```
{%- if os() == "macos" %}
# provision this machine now (mise bootstrap; log: ~/.local/log/mise-bootstrap/)
alias update_os='~/.local/share/dotfiles/bootstrap/scheduled-run.sh'
{%- elif os() == "linux" %}
# provision this machine now (mise bootstrap user unit; log: journalctl --user -u dev.mise.mise-bootstrap)
alias update_os='systemctl --user start dev.mise.mise-bootstrap.service'
{%- endif %}
{%- if vars.is_wsl == "true" %}

# WSL only: route ssh through the Windows host (1Password lives on the Windows side).
alias ssh='ssh.exe'
alias ssh-add='ssh-add.exe'
alias scp='scp.exe'
{%- endif %}
```

置き換え後、ファイル内に `{{ .` / `{{-` / `chezmoi` / `oh-my-zsh.sh` / `ZSH_THEME` / `plugins=(` が残っていないこと:

Run: `grep -nE '\{\{[-. ]|chezmoi|oh-my-zsh\.sh|ZSH_THEME|plugins=\(' home/dot_zshrc.tera`
Expected: 出力なし

- [ ] **Step 4: エントリ・ツール・lock を足す**

`mise.toml` の `[dotfiles]` の先頭に:

```toml
"~/.zshrc" = { source = "home/dot_zshrc.tera", mode = "template" }
"~/.config/sheldon/plugins.toml" = { source = "home/dot_config/sheldon/plugins.toml", mode = "copy" }
```

`home/dot_config/mise/config.toml` の `ghq = "latest"` の次の行に:

```toml
# zsh plugins (~/.config/sheldon/plugins.toml); ~/.zshrc runs `sheldon source`
sheldon = "latest"
```

`bootstrap/post-tools.sh` の corepack の for ループの後に:

```sh

# zsh plugins: fetch them here (plugins.toml is pinned) so a new shell does not
# clone anything at startup.
sheldon lock
```

同じファイルの hunk-review のコメント `# the self-made loader in ~/.claude/skills/hunk-review (chezmoi) matches the` の `(chezmoi)` を `(mise [dotfiles])` にする。

- [ ] **Step 5: テストが通ることを確認する**

Run: `tests/bootstrap/dotfiles.test.sh && tests/bootstrap/zsh.test.sh`
Expected: 両方 `PASS`

`zsh.test.sh` が stderr で失敗したときの観点:
- oh-my-zsh の lib が `oh-my-zsh.sh` の前提(`$ZSH` など)を参照している。不足している前提は `omz-setup` の inline に足す。lib を読む対象から外すのは最後の手段で、その場合は spec と README に外した lib を書く。
- `mise activate` の直後に sheldon が PATH 上に無い。
- alien が TTY の無い環境で警告を出す(テストの環境に起因するなら、その旨をコメントに書いて `zsh.test.sh` 側で回避する)。

- [ ] **Step 6: 手元で見た目を確認する(一度だけ)**

```bash
<scratch>/zsh-home を HOME にして、Step 5 の zsh.test.sh と同じ手順で apply + sheldon lock し、
HOME=<scratch>/zsh-home zsh -i
```

alien のプロンプト、Tab の補完メニュー、↑ の前方一致の履歴検索、構文ハイライト、自動補完の候補表示、`..` の移動を目で確認する。
起動時間を `time zsh -ic exit` で、今のシェル(`time zsh -ic exit`)と比べる。結果はタスクの報告に書く。

- [ ] **Step 7: shellcheck と Commit**

```bash
shellcheck tests/bootstrap/*.sh bootstrap/*.sh
git add home mise.toml bootstrap/post-tools.sh tests/bootstrap
git commit -m "feat(zsh): oh-my-zsh を sheldon で読み込む構成に切り替える"
```

---

### Task 4: dotfiles の hook(git_name のチェック、local ファイル)

**Files:**
- Create: `bootstrap/local-files.sh`
- Modify: `mise.toml`、`bootstrap/init.sh`
- Test: `tests/bootstrap/dotfiles.test.sh`

**Interfaces:**
- Consumes: Task 1 の `in_home` / `named`。

- [ ] **Step 1: 失敗するテストを足す**

`tests/bootstrap/dotfiles.test.sh` の `echo PASS` の直前に:

```sh
echo "== bootstrap: empty git_name stops before the dotfiles step"
h="$tmp/noname"; mkdir -p "$h"
in_home "$h" mise trust . >/dev/null 2>&1
rc=0
in_home "$h" mise bootstrap --only dotfiles --yes >"$tmp/noname.out" 2>&1 || rc=$?
[ "$rc" -ne 0 ] || fail "bootstrap must fail when git_name is empty"
[ ! -e "$h/.gitconfig" ] || fail "dotfiles must not be applied when git_name is empty"
grep -q 'mise vars prompt' "$tmp/noname.out" || fail "message must mention mise vars prompt"

echo "== bootstrap: local files are created once and never overwritten"
h="$tmp/local"; mkdir -p "$h"
echo keep > "$h/.zprofile.local"
in_home "$h" mise trust . >/dev/null 2>&1
named "$h" mise bootstrap --only dotfiles --yes >/dev/null
grep -q 'machine-local' "$h/.zshrc.local" || fail ".zshrc.local not created"
[ "$(cat "$h/.zprofile.local")" = keep ] || fail ".zprofile.local was overwritten"
```

- [ ] **Step 2: 失敗を確認する**

Run: `tests/bootstrap/dotfiles.test.sh`
Expected: `FAIL: bootstrap must fail when git_name is empty`

- [ ] **Step 3: hook とスクリプトを書く**

`bootstrap/local-files.sh`(新規、`chmod +x`):

```sh
#!/bin/sh
# Create the machine-local, untracked shell files once; never overwrite them.
# Runs from the post-dotfiles hook in mise.toml on every bootstrap; keep it idempotent.
set -eu

if [ ! -e "$HOME/.zshrc.local" ]; then
  printf '%s\n' '# ~/.zshrc.local — machine-local zsh config (untracked). Put secrets, environment variables, and per-machine tweaks here.' >"$HOME/.zshrc.local"
fi
if [ ! -e "$HOME/.zprofile.local" ]; then
  printf '%s\n' '# ~/.zprofile.local — machine-local login-shell config (untracked).' >"$HOME/.zprofile.local"
fi
```

`mise.toml` の `[dotfiles]` テーブルの直前に:

```toml
# git_name / git_email default to "" (see [vars]); stop before rendering ~/.gitconfig without them.
[bootstrap.hooks.pre-dotfiles]
run = "test -n '{{ vars.git_name }}' && test -n '{{ vars.git_email }}' || { echo 'error: git_name / git_email are empty. Run `mise vars prompt` (or re-run bootstrap with --prompt-vars).' >&2; exit 1; }"

[bootstrap.hooks.post-dotfiles]
run = "'{{ config_root }}/bootstrap/local-files.sh'"
```

`bootstrap/init.sh` のコメント `# Hooks (chezmoi-apply.sh's \`mise exec\`) look up mise on PATH, which a fresh machine does not have yet.` を
`# Hooks and the bootstrap task (\`mise exec\`) look up mise on PATH, which a fresh machine does not have yet.` にする。

- [ ] **Step 4: テストが通ることを確認する**

Run: `tests/bootstrap/dotfiles.test.sh`
Expected: `PASS`

`--only dotfiles` で post-dotfiles hook が走らずに失敗した場合は、`mise bootstrap --only dotfiles --dry-run` の出力で hook が表示されるかを確認し、結果を報告する(設計の前提が崩れるため、勝手に別の方式に変えない)。

- [ ] **Step 5: chezmoi の参照が残っていないことを確認する**

Run: `grep -rn -i chezmoi --exclude-dir=.git --exclude-dir=superpowers --exclude-dir=setup . ; grep -rn -i chezmoi README.md`
Expected: README 以外に出力なし(README と `docs/setup` は Task 6 で直す)。`renovate.json` と `.github/workflows/ci.yaml` も出るなら、Task 5 で直すので残してよい。

- [ ] **Step 6: shellcheck と Commit**

```bash
shellcheck bootstrap/*.sh tests/bootstrap/*.sh
git add mise.toml bootstrap tests/bootstrap
git commit -m "feat(dotfiles): git_name のチェックと local ファイルの初回生成を dotfiles hook にする"
```

---

### Task 5: CI と renovate

**Files:**
- Modify: `.github/workflows/ci.yaml`、`renovate.json`

**Interfaces:**
- Consumes: `tests/bootstrap/{dotfiles,zsh,plan,init}.test.sh` / `plan.sh`、`home/dot_config/sheldon/plugins.toml` の `github` / `tag` / `rev` の行。

- [ ] **Step 1: CI を書き換える**

`.github/workflows/ci.yaml` の `apply:` ジョブ全体(`jobs:` 直下の `apply:` から `bootstrap:` の直前まで)を削除する。
`bootstrap:` ジョブの最後のステップ群を次にする(`chezmoi-apply.sh` ステップを置き換え、`init.sh` ステップはそのまま残す):

```yaml
      - name: mise bootstrap plan (every machine selection)
        run: tests/bootstrap/plan.sh

      - name: dotfiles (every machine selection)
        run: tests/bootstrap/dotfiles.test.sh

      - name: Install zsh
        if: runner.os == 'Linux'
        run: sudo apt-get update && sudo apt-get install -y zsh

      - name: zsh startup (sheldon plugins)
        run: tests/bootstrap/zsh.test.sh

      - name: init.sh
        run: tests/bootstrap/init.test.sh
```

- [ ] **Step 2: renovate を書き換える**

`renovate.json` の `customManagers` を次で全置換する:

```json
  "customManagers": [
    {
      "customType": "regex",
      "managerFilePatterns": [
        "/^home/dot_config/sheldon/plugins\\.toml$/"
      ],
      "matchStrings": [
        "github = \"(?<depName>[^\"]+)\"\\s+tag = \"(?<currentValue>[^\"]+)\""
      ],
      "datasourceTemplate": "github-tags"
    },
    {
      "customType": "regex",
      "managerFilePatterns": [
        "/^home/dot_config/sheldon/plugins\\.toml$/"
      ],
      "matchStrings": [
        "github = \"ohmyzsh/ohmyzsh\"\\s+rev = \"(?<currentDigest>[0-9a-f]{40})\""
      ],
      "depNameTemplate": "ohmyzsh/ohmyzsh",
      "packageNameTemplate": "https://github.com/ohmyzsh/ohmyzsh",
      "currentValueTemplate": "master",
      "datasourceTemplate": "git-refs"
    }
  ]
```

- [ ] **Step 3: 検証する**

```bash
mise x node@lts -- npx -y --package renovate -- renovate-config-validator renovate.json
mise x node@lts -- npx -y --package renovate -- renovate --platform=local --dry-run=lookup 2>&1 | grep -E 'zsh-users|eendroroy|ohmyzsh' | head
mise x actionlint -- actionlint .github/workflows/ci.yaml
```

Expected: validator が `Config validated successfully`。lookup の出力に 6 依存(zsh-users 4、alien、ohmyzsh)が出る。actionlint は出力なし。
`--platform=local` の lookup が環境の都合で動かない場合は、matchStrings を `plugins.toml` に対して `rg -U` で当てて 6 件ヒットすることを確認し、そのことを報告する。

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yaml renovate.json
git commit -m "ci: chezmoi の apply ジョブを dotfiles / zsh のテストに置き換え、renovate を sheldon に向ける"
```

---

### Task 6: ドキュメント

**Files:**
- Create: `docs/setup/chezmoi-removal.md`
- Modify: `README.md`、`docs/setup/wsl-new.md`、`docs/setup/mac.md`、`docs/superpowers/specs/2026-10-15-mise-bootstrap-migration-design.md`
- Delete: `docs/setup/wsl-migration.md`
- Memory(リポジトリ外): `/home/tech/.claude/projects/-home-tech-dev-ghq-github-com-kukv-dotfiles/memory/claude-skills-provisioning.md`

- [ ] **Step 1: 移行手順書を書く**

`docs/setup/chezmoi-removal.md`:

````markdown
# chezmoi 撤去の移行手順(chezmoi → mise `[dotfiles]`、oh-my-zsh → sheldon)

mise bootstrap で動いているマシンを、chezmoi を使わない構成(作業ブランチ `chezmoi-removal`)に切り替える手順。
個人 WSL → 会社 WSL → Mac の順に行い、3 台すべてで完了してから `chezmoi-removal` を main にマージする。

- 前提: そのマシンが os-setup から mise bootstrap に移行済みであること(`~/.local/share/dotfiles` がある)。
- コマンドはそのまま貼れるように書いてある。シェル変数は使わない。
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

期待値: dotfiles の差分は、ヘッダコメントの書き換え、zshrc の sheldon 化、`~/.config/mise/config.toml` の chezmoi → sheldon だけ。
git の name / email、署名の設定、ssh の設定が変わっていないこと。想定外の差分があれば止める。

## 4. 適用する

```bash
update_os
```

WSL:

```bash
journalctl --user -u dev.mise.mise-bootstrap -n 50 --no-pager
```

Mac:

```bash
tail -n 50 ~/.local/log/mise-bootstrap/$(date +%Y%m%d).log
```

期待値: 末尾が成功で終わっている(WSL は `Finished`)。

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

新しいターミナルを開いて確認する:

```bash
time zsh -ic exit
zsh -ic 'alias gst; alias md; [[ -o autocd ]] && echo autocd-ok'
```

期待値: 起動時間が 1 と大きく変わらない。エラーが出ない。

目で確認する: alien のプロンプト / Tab の補完メニュー / ↑ で入力中の文字列から始まる履歴を検索 / 構文ハイライト / 自動補完の候補 / `..` で移動 / git の操作(コミットに署名が付く: `git log --show-signature -1`)。

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

```bash
cd ~/.local/share/dotfiles
git checkout main
git pull --ff-only
cd ~
update_os
```

`mise dot status --missing` が 0 で終わることを確認してから消す:

```bash
rm -rf ~/.oh-my-zsh ~/.config/chezmoi ~/.cache/chezmoi
mise uninstall chezmoi --all
rm -f ~/.zcompdump-*
rm -rf ~/chezmoi-removal-backup
```
````

- [ ] **Step 2: wsl-new.md を直す**

`docs/setup/wsl-new.md` の 7 の最初の 2 行:

```bash
cd ~/.local/share/dotfiles && MISE_AUTO_ENV=true mise bootstrap status; cd ~
mise exec chezmoi@latest -- chezmoi diff; echo "diff-exit=$?"
```

を次にする:

```bash
cd ~/.local/share/dotfiles && MISE_AUTO_ENV=true mise trust . && MISE_AUTO_ENV=true mise bootstrap status && MISE_AUTO_ENV=true mise dot status --missing; echo "dot-exit=$?"; cd ~
zsh -ic 'alias gst; alias md'
```

期待値の `- \`diff-exit=0\`` を次の 2 行にする:

```markdown
- `dot-exit=0`
- `alias gst` / `alias md` が表示され、zsh の起動でエラーが出ない
```

- [ ] **Step 3: os-setup からの移行手順を削除する**

```bash
git rm -q docs/setup/wsl-migration.md
```

`docs/setup/mac.md` は `## 移行(os-setup → mise bootstrap)` の見出しから末尾までを削除する(`# Mac セットアップ手順`、`TODO: 未整備。`、`## 新規`、`TODO` は残す)。
`docs/setup/wsl-new.md` 冒頭の `os-setup (Ansible) で構築済みの WSL は [wsl-migration.md](wsl-migration.md) を使う。` の行を削除する。

- [ ] **Step 4: README を書き換える**

`README.md` の冒頭から `## 適用方法` の直前までを次に置き換える:

````markdown
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
````

`## 適用方法` 内:
- `dotfiles(chezmoi)` → `dotfiles`
- `- [WSL 移行(os-setup から)](docs/setup/wsl-migration.md)` の行を削除
- `### 構成` の見出しと 3 行(`- mise.toml(全マシン共通)…`〜`…home/(chezmoi ソース)`)を削除(上のリポジトリ構成と重複するため)

`## 編集` から末尾までを次に置き換える:

````markdown
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
````

- [ ] **Step 5: 旧 spec に追記する**

`docs/superpowers/specs/2026-10-15-mise-bootstrap-migration-design.md` の `### oh-my-zsh` 見出しの直後に:

```markdown

> **2026-10-15 追記:** 本節の決定(案 A)は撤回した。chezmoi の撤去と oh-my-zsh → sheldon の移行は
> [2026-10-15-chezmoi-removal-design.md](2026-10-15-chezmoi-removal-design.md) を参照。
```

- [ ] **Step 6: 参照の残りを確認する**

Run: `grep -rn -i -E 'chezmoi|wsl-migration' --exclude-dir=.git --exclude-dir=superpowers . | grep -v '^./docs/setup/chezmoi-removal.md'`
Expected: 出力なし

- [ ] **Step 7: Commit**

```bash
git add -A README.md docs
git commit -m "docs: chezmoi 撤去に合わせて README と手順書を更新し、移行手順書を追加"
```

- [ ] **Step 8: memory を更新する(リポジトリ外、コミットなし)**

`claude-skills-provisioning.md` の本文で、chezmoi を現役の仕組みとして書いている箇所を確認する。`run_onchange` の検証の話は「過去に chezmoi で試した理由」として残し、
`hunk-review` のローダーの配置元を「mise `[dotfiles]`(`home/dot_claude/skills/hunk-review`)」と明記する。MEMORY.md の該当行の説明も、
「chezmoi run_onchange が使えない理由つき」→「chezmoi 時代に run_onchange が使えなかった理由つき」にする。

---

### Task 7: Docker e2e(新規構築・移行・切り戻し)

**前提:** Task 1〜6 がコミット済み。**このタスクの最初に、ユーザーにブランチの push の可否を確認する**(push 先: `origin` の `chezmoi-removal`)。

**Files:** なし(検証のみ。見つかった不具合は該当タスクのファイルを直してコミットする)

- [ ] **Step 1: push(ユーザーの確認後)**

```bash
git push -u origin HEAD:chezmoi-removal
```

- [ ] **Step 2: 新規構築**

```bash
docker compose -f tests/docker/compose.yaml down
docker compose -f tests/docker/compose.yaml up -d --build e2e
tests/docker/exec.sh -s e2e 'export git_name="CI User" git_email=ci@example.com; curl -fsSL https://raw.githubusercontent.com/kukv/dotfiles/chezmoi-removal/bootstrap/init.sh | sh -s -- --env wsl --branch chezmoi-removal'
tests/docker/exec.sh -s e2e '~/.local/bin/mise vars git_name="CI User" git_email=ci@example.com'
tests/docker/exec.sh -s e2e 'cd ~/.local/share/dotfiles && export MISE_AUTO_ENV=true && ~/.local/bin/mise trust . && ~/.local/bin/mise bootstrap status && ~/.local/bin/mise dot status --missing; echo "dot-exit=$?"'
tests/docker/exec.sh -s e2e 'zsh -lic "alias gst; alias md; print -r -- \$PROMPT" 2>&1 | tail -5'
tests/docker/exec.sh -s e2e 'systemctl --user start dev.mise.mise-bootstrap.service; systemctl --user show dev.mise.mise-bootstrap.service -p Result -p ExecMainStatus'
tests/docker/exec.sh -s e2e 'mkdir -p /tmp/fresh && cp ~/.gitconfig ~/.zshrc ~/.zprofile /tmp/fresh/ && ls ~/.local/share/sheldon/repos | head'
docker compose -f tests/docker/compose.yaml cp e2e:/tmp/fresh <scratch>/e2e-fresh
```

Expected: init が exit 0 / `bootstrap status` exit 0 / `dot-exit=0` / zsh がエラーなしでエイリアスとプロンプトを表示 / `Result=success`、`ExecMainStatus=0`。

- [ ] **Step 3: 移行の再現(main → 作業ブランチ)**

```bash
docker compose -f tests/docker/compose.yaml down
docker compose -f tests/docker/compose.yaml up -d e2e
tests/docker/exec.sh -s e2e 'export git_name="CI User" git_email=ci@example.com; curl -fsSL https://raw.githubusercontent.com/kukv/dotfiles/main/bootstrap/init.sh | sh -s -- --env wsl'
tests/docker/exec.sh -s e2e '~/.local/bin/mise vars git_name="CI User" git_email=ci@example.com'
tests/docker/exec.sh -s e2e 'test -f ~/.oh-my-zsh/oh-my-zsh.sh && ls -la --time-style=+%s ~/.oh-my-zsh | head -3 > /tmp/omz-before'
tests/docker/exec.sh -s e2e 'cd ~/.local/share/dotfiles && git fetch origin && git checkout chezmoi-removal'
tests/docker/exec.sh -s e2e 'systemctl --user start dev.mise.mise-bootstrap.service; systemctl --user show dev.mise.mise-bootstrap.service -p Result -p ExecMainStatus'
tests/docker/exec.sh -s e2e 'journalctl --user -u dev.mise.mise-bootstrap -n 80 --no-pager | grep -i -E "conflict|error|force" || echo no-conflict'
tests/docker/exec.sh -s e2e 'cd ~/.local/share/dotfiles && export MISE_AUTO_ENV=true && ~/.local/bin/mise trust . && ~/.local/bin/mise dot status --missing; echo "dot-exit=$?"'
tests/docker/exec.sh -s e2e 'ls -la --time-style=+%s ~/.oh-my-zsh | head -3 | diff /tmp/omz-before - && echo omz-untouched'
tests/docker/exec.sh -s e2e 'mkdir -p /tmp/migrated && cp ~/.gitconfig ~/.zshrc ~/.zprofile /tmp/migrated/'
docker compose -f tests/docker/compose.yaml cp e2e:/tmp/migrated <scratch>/e2e-migrated
diff -r <scratch>/e2e-fresh <scratch>/e2e-migrated && echo same-as-fresh
tests/docker/exec.sh -s e2e 'zsh -lic "alias gst; alias md" 2>&1 | tail -3'
```

Expected: `Result=success` / `no-conflict`(`--force-dotfiles` を要求されない)/ `dot-exit=0` / `omz-untouched` / `same-as-fresh` / zsh がエラーなし。

`no-conflict` にならない場合(chezmoi が書いた既存ファイルが衝突扱いになる場合)は、ここで止めてユーザーに報告する。
対処の候補は、移行手順書で初回だけ `--force-dotfiles` を付ける、など。どれにするかは spec の変更になるため、勝手に決めない。

- [ ] **Step 4: 切り戻しの確認**

```bash
tests/docker/exec.sh -s e2e 'cd ~/.local/share/dotfiles && git checkout main'
tests/docker/exec.sh -s e2e 'systemctl --user start dev.mise.mise-bootstrap.service; systemctl --user show dev.mise.mise-bootstrap.service -p Result -p ExecMainStatus'
tests/docker/exec.sh -s e2e 'grep -c "oh-my-zsh.sh" ~/.zshrc; mise exec chezmoi@latest -- chezmoi diff; echo "diff-exit=$?"'
tests/docker/exec.sh -s e2e 'zsh -lic "alias gst" 2>&1 | tail -3'
```

Expected: `Result=success` / `1`(oh-my-zsh に戻った)/ `diff-exit=0` / zsh がエラーなし。

- [ ] **Step 5: 片付けと報告**

```bash
docker compose -f tests/docker/compose.yaml down
```

`docs/superpowers/specs/2026-10-15-chezmoi-removal-design.md` の末尾に `## 検証結果` を追加し、Step 2〜4 の結果(実行日、HEAD の SHA、各 Expected の合否、見つけて直した不具合)を書いてコミットする:

```bash
git add docs/superpowers/specs/2026-10-15-chezmoi-removal-design.md
git commit -m "docs: chezmoi 撤去の Docker e2e 検証結果を記録"
git push
```

この後の実機での移行(`docs/setup/chezmoi-removal.md`)は、マージ条件(Mac と会社 WSL の os-setup からの移行)を満たしてから、1 台ずつユーザーと進める。
