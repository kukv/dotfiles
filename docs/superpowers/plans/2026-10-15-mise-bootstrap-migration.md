# os-setup (Ansible) → mise bootstrap 移行 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `kukv/os-setup`(Ansible)の責務をすべて dotfiles リポジトリの mise bootstrap 設定へ移し、Ansible を撤去する。

**Architecture:** dotfiles リポジトリのルートに mise bootstrap プロジェクト(`mise.toml` + platform ファイル + module ファイル)を置き、`mise bootstrap --from kukv/dotfiles` で適用する。
chezmoi は残し、pre-tools hook から `home/` をソースとして apply する。
OS 差分は platform ファイル(`mise.linux.toml` / `mise.macos.toml`)、マシン役割差分は module(`mise.wsl.toml` / `mise.work.toml`)、マシン固有値は `[vars]` の prompt で表す。

**Tech Stack:** mise 2026.10.x(bootstrap / vars / hooks / tasks)、chezmoi(`mise exec chezmoi@latest` で実行)、POSIX sh、GitHub Actions

**Spec:** `docs/superpowers/specs/2026-10-15-mise-bootstrap-migration-design.md`

## Global Constraints

- 作業ブランチは `migration`。**main には全台の移行が終わるまでマージしない**(未移行マシンの Ansible が main の chezmoi ソースを適用し続けるため)。
- `home/` 配下の chezmoi テンプレートは、Task 9 で明示した 2 箇所(`dot_zprofile.tmpl` の linuxbrew 行、`dot_zshrc.tmpl` の `update_os`)以外は変更しない。
- マシン選択: Mac は env なし、個人 WSL は `env = ["wsl"]`、会社 WSL は `env = ["wsl", "work"]`(`~/.config/mise/miserc.local.toml`、非コミット)。
- bootstrap チェックアウト: `~/.local/share/mise/bootstrap-repo`(`$MISE_DATA_DIR/bootstrap-repo` の既定値)。
- 秘密情報ファイル: `~/.local/etc/bootstrap.env`(0600)。`MISE_GITHUB_TOKEN` / `HOMEBREW_GITHUB_API_TOKEN` を置く。
- 定期実行は週次。Mac は日曜 21:00。
- シェルスクリプトは POSIX sh(`#!/bin/sh`)、`set -eu`、shellcheck を通す。冪等であること(hook と bootstrap task は毎回走る)。
- base(`mise.toml` と platform ファイル)には全マシン共通のものだけを置く。差分は module に置く。
- **テストと動作確認は Docker の Ubuntu コンテナ内で行い、ホスト(実機)を汚さない。** ファイル編集・`chmod`・`git` はホストで、`Run(コンテナ):` と書いたコマンドは `tests/docker/exec.sh '<command>'` で実行する(既定の `dev` サービスでは cwd が `/dotfiles` = このリポジトリの読み取り専用マウント)。
- コンテナで確認できないもの: resolv.conf の symlink(Docker が bind mount しているため。`wsl-base.sh` は `/.dockerenv` があればスキップする)、WSL 固有の実挙動(interop・`ssh.exe`・再起動後の systemd)、macOS 全般。WSL 固有は Task 12 の個人 WSL 移行時に確認し、**macOS の動作確認は別計画**で行う(本計画では macos CI runner の `plan` までを確認する)。
- 実機への**適用**は Task 12 以降でのみ行い、ユーザーの確認を取ってから実施する。

## File Structure

| ファイル | 責務 |
|---|---|
| `.miserc.toml` | `auto_env = true`(platform ファイルを読ませる) |
| `mise.toml` | base: `[vars]`、chezmoi 連携の pre-tools hook、`[tasks.bootstrap]` |
| `mise.linux.toml` | apt パッケージ、DNS drop-in + systemd-resolved、login shell、linux base hook、linger hook、systemd user timer |
| `mise.macos.toml` | brew formulae / casks / mas、brew upgrade hook、launchd agent |
| `mise.wsl.toml` | `/etc/wsl.conf`、WSL base hook(resolv.conf / wslu) |
| `mise.work.toml` | `[vars] use_1password = "false"` |
| `bootstrap/init.sh` | 初回構築(mise 導入 → env 選択 → `mise bootstrap --from`) |
| `bootstrap/chezmoi-apply.sh` | vars から chezmoi.toml を生成して `chezmoi apply --force` |
| `bootstrap/linux-base.sh` | locale / timezone(宣言で書けない Linux 設定) |
| `bootstrap/wsl-base.sh` | resolv.conf の symlink、wslu(Ubuntu < 26.04) |
| `bootstrap/macos-brew.sh` | cirruslabs/cli の tap + trust、`brew upgrade --formula` |
| `bootstrap/post-tools.sh` | corepack 無効化、herdr プラグイン、Claude skills、Claude Code CLI |
| `bootstrap/scheduled-run.sh` | 定期実行ラッパー(env 読み込み → self-update → bootstrap) |
| `tests/bootstrap/chezmoi-apply.test.sh` | chezmoi-apply.sh のテスト |
| `tests/bootstrap/plan.sh` | env の組み合わせごとに `mise bootstrap plan` を流すスモークテスト |
| `tests/bootstrap/init.test.sh` | init.sh の引数処理と生成物のテスト |
| `tests/docker/Dockerfile` | テスト用 Ubuntu 26.04 + systemd(`base`: E2E 用の素の状態、`dev`: mise と shellcheck 入り) |
| `tests/docker/compose.yaml` | `dev`(リポジトリを `/dotfiles` に読み取り専用でマウント)と `e2e` の 2 サービス |
| `tests/docker/exec.sh` | コンテナ内でユーザー `tech` としてコマンドを実行するラッパー |
| `.github/workflows/ci.yaml` | 上記テストと shellcheck を流すジョブを追加(runner 上で直接実行。Docker は使わない) |

`bootstrap/` 配下のスクリプトはすべて `git update-index --chmod=+x` で実行ビットを付ける。

---

### Task 0: テスト用 Docker 環境

**Files:**
- Create: `tests/docker/Dockerfile`, `tests/docker/compose.yaml`, `tests/docker/exec.sh`

**Interfaces:**
- Produces: `tests/docker/exec.sh [-s dev|e2e] '<command>'`。ユーザー `tech`(uid 1000)、`XDG_RUNTIME_DIR=/run/user/1000`、PATH 先頭に `~/.local/bin`。cwd は `dev` なら `/dotfiles`、`e2e` なら `/home/tech`。
  コンテナの初期化は `docker compose -f tests/docker/compose.yaml down && docker compose -f tests/docker/compose.yaml up -d --build <service>`。

- [ ] **Step 1: Dockerfile を書く**

`tests/docker/Dockerfile`(ベースイメージは os-setup の `docker/mock` と同じ digest):

```dockerfile
# Throwaway Ubuntu with systemd as PID 1, for exercising mise bootstrap without
# touching a real machine. Targets:
#   base: nothing preinstalled (end-to-end test of bootstrap/init.sh)
#   dev:  mise + shellcheck (iterating on the bootstrap config)
FROM ubuntu:26.04@sha256:2260313b31c8c011cd2eebe728008efac1b3982be73eb71348ea2648d2c0e09b AS base

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
        systemd systemd-sysv systemd-resolved dbus sudo curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# The image ships an "ubuntu" user at uid 1000; replace it with tech (uid 1000)
# to match the real machines. The test-only sudoers file is named so that
# init.sh still creates /etc/sudoers.d/tech itself.
RUN userdel -r ubuntu 2>/dev/null || true && \
    useradd -m -u 1000 -s /bin/bash tech && \
    echo 'tech ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/00-test && \
    chmod 0440 /etc/sudoers.d/00-test

CMD ["/sbin/init"]

FROM base AS dev
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends git shellcheck && \
    rm -rf /var/lib/apt/lists/*
USER tech
RUN curl -fsSL https://mise.run | sh
USER root
```

- [ ] **Step 2: compose.yaml と exec.sh を書く**

`tests/docker/compose.yaml`:

```yaml
---
services:
  dev:
    build:
      context: "."
      target: "dev"
    hostname: "mise-dev"
    privileged: true
    tty: true
    volumes:
      - "../..:/dotfiles:ro"

  e2e:
    build:
      context: "."
      target: "base"
    hostname: "mise-e2e"
    privileged: true
    tty: true
```

`tests/docker/exec.sh`:

```sh
#!/bin/sh
# Run a command as tech inside a test container.
# usage: exec.sh [-s dev|e2e] '<command>'   (default service: dev)
set -eu
svc=dev
if [ "${1:-}" = "-s" ]; then svc="$2"; shift 2; fi
case "$svc" in
  dev) workdir=/dotfiles ;;
  *)   workdir=/home/tech ;;
esac
exec docker compose -f "$(cd "$(dirname "$0")" && pwd)/compose.yaml" exec \
  -u tech -w "$workdir" \
  -e XDG_RUNTIME_DIR=/run/user/1000 \
  -e PATH=/home/tech/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  "$svc" bash -lc "$1"
```

- [ ] **Step 3: 起動して確認する**

Run(ホスト):

```bash
chmod +x tests/docker/exec.sh
docker compose -f tests/docker/compose.yaml up -d --build dev
tests/docker/exec.sh 'systemctl is-system-running --wait; id; mise --version; ls /dotfiles/home | head -3'
```

Expected: `running` または `degraded`(コンテナでは一部 unit が失敗しても可)、`uid=1000(tech)`、mise のバージョン、`home/` の中身が表示される。

- [ ] **Step 4: Commit**

```bash
git add tests/docker/Dockerfile tests/docker/compose.yaml tests/docker/exec.sh
git update-index --chmod=+x tests/docker/exec.sh
git commit -m "test: mise bootstrap 検証用の Docker(Ubuntu + systemd)環境を追加"
```

---

### Task 1: スパイク — mise の未確認挙動をコンテナで確かめる

この結果で後続タスクの分岐(★印)が決まる。コードは捨てる。

**Files:**
- Modify: `docs/superpowers/specs/2026-10-15-mise-bootstrap-migration-design.md`(末尾に「検証結果」節を追加)

**Interfaces:**
- Produces: 「検証結果」節の Q1〜Q7 の答え。後続タスクの ★ はこれを参照する。

以下の Step 1〜8 はすべて `dev` コンテナ内で実行する(`tests/docker/exec.sh` を 1 回ずつ呼ぶか、`docker compose -f tests/docker/compose.yaml exec -u tech dev bash -l` で入って実行する)。
ホストの `~/.config/mise` には一切触れない。

- [ ] **Step 1: 使い捨てプロジェクトを作る**

```bash
mkdir -p /tmp/spike && cd /tmp/spike && git init -q
cat > .miserc.toml <<'EOF'
auto_env = true
EOF
cat > mise.toml <<'EOF'
[vars.probe_base]
default = "base"
[bootstrap.hooks]
pre-dotfiles = "echo HOOK pre-dotfiles"
pre-tools = "echo HOOK pre-tools vars={{ vars.probe_base }} root={{ config_root }}"
EOF
cat > mise.linux.toml <<'EOF'
[vars]
probe_platform = "linux"
EOF
cat > mise.macos.toml <<'EOF'
[vars]
probe_platform = "macos"
EOF
cat > mise.wsl.toml <<'EOF'
[vars]
probe_module = "wsl"
EOF
mise trust
```

- [ ] **Step 2: Q1 platform ファイル(auto_env を .miserc.toml で有効化できるか)**

Run: `mise vars probe_platform`
Expected: `linux`(Mac なら `macos`)。空またはエラーなら `auto_env` は `.miserc.toml` で効かない → `MISE_AUTO_ENV=true` を init.sh / scheduled-run.sh / CI で export する方式にする(★Q1)。

- [ ] **Step 3: Q2 グローバル miserc.local.toml の env が、プロジェクトの module を選ぶか**

```bash
mkdir -p ~/.config/mise
printf 'env = ["wsl"]\n' > ~/.config/mise/miserc.local.toml
mise vars probe_module
rm ~/.config/mise/miserc.local.toml
```

Expected: `wsl`。だめなら `-E` を明示する方式にする(★Q2)。

- [ ] **Step 4: Q3 hook のテンプレート展開と、[dotfiles] 未宣言時の pre-dotfiles hook**

Run: `mise bootstrap --dry-run --only dotfiles,tools 2>&1 | grep HOOK`
Expected: `pre-tools` 行に `vars=base root=/tmp/spike` が展開されて出る。`pre-dotfiles` 行の有無を記録する(本計画は pre-tools を使うので、無くても問題ない)。

- [ ] **Step 5: Q4 同名の環境変数で var を一時上書きできるか(テスト用。保存済みの答えを汚さないため)**

Run: `probe_base=ci mise vars probe_base`
Expected: `ci`。出なければ `MISE_VAR_probe_base=ci` など docs の表記を `mise vars --help` で確認し、使える形を記録する(★Q4)。

- [ ] **Step 6: Q5 hook 内で配置したグローバル設定の tools が、同じ実行の tools ステップで入るか**

```bash
cat >> mise.toml <<'EOF'
[bootstrap.hooks.post-packages]
run = "printf '[tools]\ntokei = \"latest\"\n' > {{ config_root }}/mise.local.toml"
EOF
mise bootstrap --yes --only packages,tools 2>&1 | tail -5
mise ls tokei
```

Expected: `tokei` が installed。入っていなければ「tools は実行開始時の設定を使う」→ `[tasks.bootstrap]` の先頭で `mise install` を呼ぶ(★Q5)。
(実際に hook が置くのはグローバルの `~/.config/mise/config.toml` だが、実行途中に現れた設定ファイルを読むかの代理確認としてプロジェクトの `mise.local.toml` を使う。)
確認後 `mise uninstall tokei --all`。

- [ ] **Step 7: Q6 `--from` チェックアウトは trust 済みとして扱われるか / ref 付きで clone されるか**

ネットワークを使う。ローカルの bare リポジトリで代用する:

```bash
cd /tmp && git clone -q --bare spike spike.git
cd spike && git -c user.name=t -c user.email=t@t add -A && git -c user.name=t -c user.email=t@t commit -qm spike && git push -q ../spike.git HEAD:main && cd ..
git clone -q spike.git spike-co   # --dry-run はチェックアウトが無いと止まるため先に clone
mise bootstrap --from "file:///tmp/spike.git" --from-dir /tmp/spike-co --dry-run 2>&1 | tail -10
```

Expected: trust を求めるプロンプトやエラーが出ないこと。出るなら init.sh で clone 後に `mise trust <checkout>` を挟む(★Q6)。

- [ ] **Step 8: Q7 `--update` は dirty なチェックアウトで止まるか**

```bash
echo x >> /tmp/spike-co/mise.toml
mise bootstrap --from "file:///tmp/spike.git" --from-dir /tmp/spike-co --update --dry-run 2>&1 | tail -5
```

Expected: 挙動(エラー / 警告して続行)を記録する。エラーで止まる場合、spec §4 の注意書きのとおり運用で回避する(コード対応はしない)。

- [ ] **Step 9: 結果を spec に記録してコミット**

spec 末尾に以下の形式で追記する(値は実測で埋める):

```markdown
## 検証結果(Task 1 スパイク、mise <version>)

| # | 確認事項 | 結果 | 採用した方式 |
|---|---|---|---|
| Q1 | `.miserc.toml` の `auto_env` で platform ファイルが読まれる | | |
| Q2 | グローバル `miserc.local.toml` の `env` がプロジェクト module を選ぶ | | |
| Q3 | hook で `vars.*` / `config_root` が展開される。pre-dotfiles hook の有無 | | |
| Q4 | 同名の環境変数で var を上書きできる(変数名の形式) | | |
| Q5 | hook で配置した設定の tools が同じ実行で入る | | |
| Q6 | `--from` チェックアウトで trust を求められない | | |
| Q7 | dirty なチェックアウトで `--update` が止まる | | |
```

```bash
cd /home/tech/dev/ghq/github.com/kukv/dotfiles
git add docs/superpowers/specs/2026-10-15-mise-bootstrap-migration-design.md
git commit -m "docs: mise bootstrap の挙動検証結果を記録"
# コンテナを初期状態に戻す(スパイクの残骸を消す)
docker compose -f tests/docker/compose.yaml down && docker compose -f tests/docker/compose.yaml up -d --build dev
```

---

### Task 2: bootstrap プロジェクトの骨格(vars・module・plan スモークテスト・CI)

**Files:**
- Create: `.miserc.toml`, `mise.toml`, `mise.linux.toml`, `mise.macos.toml`, `mise.wsl.toml`, `mise.work.toml`
- Create: `tests/bootstrap/plan.sh`
- Modify: `.github/workflows/ci.yaml`(ジョブ追加)

**Interfaces:**
- Produces: vars `git_name` / `git_email` / `use_1password`(`"true"`/`"false"` の文字列)/ `git_signing_key_file`(空文字可)。`tests/bootstrap/plan.sh` は引数なしで全組み合わせを流し、失敗で非 0 を返す。

- [ ] **Step 1: スモークテストを書く**

`tests/bootstrap/plan.sh`:

```sh
#!/bin/sh
# Run `mise bootstrap plan` for every machine selection this repo supports.
# Fails on config errors (unknown keys, bad templates, conflicting entries).
set -eu
cd "$(dirname "$0")/../.."
mise trust .

# required vars may have no saved answer (CI); the process environment wins
# over saved answers, so this never touches this machine's real answers.
export git_name=ci git_email=ci@example.com

for envs in "" "wsl" "wsl,work"; do
  echo "== plan (env: ${envs:-none})"
  if [ -n "$envs" ]; then
    mise -E "$envs" bootstrap plan
  else
    mise bootstrap plan
  fi
done

echo "== work module flips use_1password"
[ "$(mise -E wsl,work vars use_1password)" = "false" ]
[ "$(mise vars use_1password)" = "true" ]
```

★Q2 が「-E 必須」でもこのテストは `-E` を使うので変更不要。★Q4 で環境変数の形式が `git_name` と異なった場合は `export` 行をその形式に合わせる。

- [ ] **Step 2: 失敗を確認する**

Run(ホスト): `chmod +x tests/bootstrap/plan.sh`
Run(コンテナ): `tests/docker/exec.sh 'tests/bootstrap/plan.sh'`
Expected: FAIL(`mise.toml` が無いので vars が見つからない / `use_1password` が空)

- [ ] **Step 3: 骨格ファイルを作る**

`.miserc.toml`(★Q1 が不可なら作らず、各スクリプトで `MISE_AUTO_ENV=true` を export する):

```toml
# Read before any other config: load mise.linux.toml / mise.macos.toml automatically.
auto_env = true
```

`mise.toml`:

```toml
# mise bootstrap project for kukv/dotfiles.
# Base: settings every machine shares. OS differences live in mise.{linux,macos}.toml,
# machine roles in modules (mise.wsl.toml, mise.work.toml) selected per machine in
# ~/.config/mise/miserc.local.toml. See docs/superpowers/specs/2026-10-15-mise-bootstrap-migration-design.md

# ==========================================================================
# vars (per-machine answers are saved by `mise bootstrap --prompt-vars`)
# ==========================================================================
[vars.git_name]
prompt = "Git user.name"
required = "Run `mise vars prompt` to set git_name"

[vars.git_email]
prompt = "Git user.email"
required = "Run `mise vars prompt` to set git_email"

# Overridden to "false" by mise.work.toml (company PC signs with a local key).
[vars.use_1password]
default = "true"

# Empty: chezmoi templates fall back to <homeDir>/.ssh/git_signing_key.pub.
[vars.git_signing_key_file]
default = ""
```

`mise.linux.toml` / `mise.macos.toml` / `mise.wsl.toml`(中身は後続タスクで足す):

```toml
# Linux-only bootstrap settings (loaded automatically on Linux).
```

```toml
# macOS-only bootstrap settings (loaded automatically on macOS).
```

```toml
# Module "wsl": select with env = ["wsl"] in ~/.config/mise/miserc.local.toml on WSL machines.
```

`mise.work.toml`:

```toml
# Module "work": company PC. Select with env = ["wsl", "work"].
[vars]
# The company PC has no 1Password; commits are signed with a local SSH key.
use_1password = "false"
```

- [ ] **Step 4: テストが通ることを確認する**

Run(コンテナ): `tests/docker/exec.sh 'tests/bootstrap/plan.sh'`
Expected: 3 つの `== plan` が全て成功し、最後の 2 つの比較が通って exit 0

- [ ] **Step 5: CI ジョブを追加する**

`.github/workflows/ci.yaml` の `jobs:` に追記(既存 `apply` ジョブは変更しない):

```yaml
  bootstrap:
    strategy:
      fail-fast: false
      matrix:
        os: [ ubuntu-latest, macos-latest ]
    runs-on: ${{ matrix.os }}
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false

      - name: Install mise
        run: |
          curl -fsSL https://mise.run | sh
          echo "$HOME/.local/bin" >> "$GITHUB_PATH"

      - name: shellcheck bootstrap scripts
        if: runner.os == 'Linux'
        run: |
          files=$(git ls-files 'bootstrap/*.sh' 'tests/bootstrap/*.sh')
          [ -z "$files" ] || shellcheck $files

      - name: mise bootstrap plan (every machine selection)
        run: tests/bootstrap/plan.sh
```

- [ ] **Step 6: Commit**

```bash
git add .miserc.toml mise.toml mise.linux.toml mise.macos.toml mise.wsl.toml mise.work.toml tests/bootstrap/plan.sh .github/workflows/ci.yaml
git update-index --chmod=+x tests/bootstrap/plan.sh
git commit -m "feat(bootstrap): mise bootstrap プロジェクトの骨格と plan スモークテストを追加"
```

---

### Task 3: chezmoi 連携(chezmoi-apply.sh + pre-tools hook)

**Files:**
- Create: `bootstrap/chezmoi-apply.sh`
- Create: `tests/bootstrap/chezmoi-apply.test.sh`
- Modify: `mise.toml`(hook 追加)

**Interfaces:**
- Consumes: Task 2 の vars。
- Produces: `bootstrap/chezmoi-apply.sh <source_dir>`。環境変数 `GIT_NAME` `GIT_EMAIL` `USE_1PASSWORD`(`true`/`false`)`GIT_SIGNING_KEY_FILE`(空可)を読む。`CHEZMOI_SKIP_APPLY=1` なら設定ファイル生成のみ。

- [ ] **Step 1: 失敗するテストを書く**

`tests/bootstrap/chezmoi-apply.test.sh`:

```sh
#!/bin/sh
# Tests for bootstrap/chezmoi-apply.sh in a throwaway HOME.
set -eu
repo="$(cd "$(dirname "$0")/../.." && pwd)"
script="$repo/bootstrap/chezmoi-apply.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

run() {
  HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" "$@"
}

mkdir -p "$tmp/home"

echo "== 1Password machine: config generated, no signing key line"
run env GIT_NAME="Ada" GIT_EMAIL="ada@example.com" USE_1PASSWORD=true GIT_SIGNING_KEY_FILE="" \
  CHEZMOI_SKIP_APPLY=1 "$script" "$repo"
conf="$tmp/home/.config/chezmoi/chezmoi.toml"
[ -f "$conf" ] || fail "chezmoi.toml not created"
grep -qx "sourceDir = \"$repo\"" "$conf" || fail "sourceDir"
grep -qx '    git_name = "Ada"' "$conf" || fail "git_name"
grep -qx '    git_email = "ada@example.com"' "$conf" || fail "git_email"
grep -qx '    use_1password = true' "$conf" || fail "use_1password"
! grep -q git_signing_key_file "$conf" || fail "signing key must be omitted when empty"
[ "$(stat -c %a "$conf" 2>/dev/null || stat -f %Lp "$conf")" = "600" ] || fail "mode 600"

echo "== local-key machine: signing key written"
run env GIT_NAME="Ada" GIT_EMAIL="ada@example.com" USE_1PASSWORD=false GIT_SIGNING_KEY_FILE="/k.pub" \
  CHEZMOI_SKIP_APPLY=1 "$script" "$repo"
grep -qx '    use_1password = false' "$conf" || fail "use_1password=false"
grep -qx '    git_signing_key_file = "/k.pub"' "$conf" || fail "git_signing_key_file"

echo "== apply renders templates into HOME (externals skipped)"
run env GIT_NAME="Ada" GIT_EMAIL="ada@example.com" USE_1PASSWORD=true GIT_SIGNING_KEY_FILE="" \
  CHEZMOI_APPLY_ARGS="--exclude=externals" "$script" "$repo"
grep -q 'name = Ada' "$tmp/home/.gitconfig" || fail ".gitconfig not rendered"

echo "PASS"
```

- [ ] **Step 2: 失敗を確認する**

Run(ホスト): `chmod +x tests/bootstrap/chezmoi-apply.test.sh`
Run(コンテナ): `tests/docker/exec.sh 'tests/bootstrap/chezmoi-apply.test.sh'`
Expected: FAIL(`bootstrap/chezmoi-apply.sh: not found`)

- [ ] **Step 3: 実装する**

`bootstrap/chezmoi-apply.sh`:

```sh
#!/bin/sh
# Seed chezmoi data from mise vars, then apply the chezmoi source in this repo.
# Called from the pre-tools hook in mise.toml (before tools, because chezmoi
# places ~/.config/mise/config.toml, which declares the tools).
#
# usage: chezmoi-apply.sh <source_dir>
# env:   GIT_NAME GIT_EMAIL USE_1PASSWORD(true|false) GIT_SIGNING_KEY_FILE(may be empty)
#        CHEZMOI_SKIP_APPLY=1   only write the config (tests)
#        CHEZMOI_APPLY_ARGS     extra args for `chezmoi apply` (tests)
set -eu

src="$1"
conf_dir="${XDG_CONFIG_HOME:-$HOME/.config}/chezmoi"

mkdir -p "$conf_dir"
chmod 700 "$conf_dir"
(
  umask 077
  {
    # sourceDir points at the bootstrap checkout; .chezmoiroot selects home/.
    echo "sourceDir = \"$src\""
    echo "[data]"
    echo "    git_name = \"$GIT_NAME\""
    echo "    git_email = \"$GIT_EMAIL\""
    echo "    use_1password = $USE_1PASSWORD"
    if [ -n "$GIT_SIGNING_KEY_FILE" ]; then
      echo "    git_signing_key_file = \"$GIT_SIGNING_KEY_FILE\""
    fi
  } > "$conf_dir/chezmoi.toml"
)
chmod 600 "$conf_dir/chezmoi.toml"

[ -n "${CHEZMOI_SKIP_APPLY:-}" ] && exit 0

# --force: overwrite files changed at runtime (e.g. ~/.claude/settings.json) without a TTY.
# shellcheck disable=SC2086
exec mise exec chezmoi@latest -- chezmoi apply --force ${CHEZMOI_APPLY_ARGS:-}
```

- [ ] **Step 4: テストが通ることを確認する**

Run(ホスト): `chmod +x bootstrap/chezmoi-apply.sh`
Run(コンテナ): `tests/docker/exec.sh 'tests/bootstrap/chezmoi-apply.test.sh'`
Expected: `PASS`

- [ ] **Step 5: hook を追加する**

`mise.toml` の末尾に追記:

```toml
# ==========================================================================
# chezmoi (kept for now; see spec "将来フェーズ")
# ==========================================================================
[bootstrap.hooks.pre-tools]
run = "GIT_NAME='{{ vars.git_name }}' GIT_EMAIL='{{ vars.git_email }}' USE_1PASSWORD='{{ vars.use_1password }}' GIT_SIGNING_KEY_FILE='{{ vars.git_signing_key_file }}' '{{ config_root }}/bootstrap/chezmoi-apply.sh' '{{ config_root }}'"
```

- [ ] **Step 6: dry-run で展開を確認する**

Run(コンテナ): `tests/docker/exec.sh 'git_name=ci git_email=ci@example.com mise -E wsl,work bootstrap --dry-run --only tools 2>&1 | grep chezmoi-apply'`
Expected: `GIT_NAME='ci'`、`USE_1PASSWORD='false'`、`'/dotfiles/bootstrap/chezmoi-apply.sh' '/dotfiles'` が展開された 1 行が表示される。

- [ ] **Step 7: CI にテストを追加して Commit**

`.github/workflows/ci.yaml` の `bootstrap` ジョブ末尾に追記:

```yaml
      - name: chezmoi-apply.sh
        run: tests/bootstrap/chezmoi-apply.test.sh
```

```bash
git add bootstrap/chezmoi-apply.sh tests/bootstrap/chezmoi-apply.test.sh mise.toml .github/workflows/ci.yaml
git update-index --chmod=+x bootstrap/chezmoi-apply.sh tests/bootstrap/chezmoi-apply.test.sh
git commit -m "feat(bootstrap): pre-tools hook で vars から chezmoi を適用する"
```

---

### Task 4: Linux 基盤(apt・locale/TZ・DNS・login shell)

**Files:**
- Create: `bootstrap/linux-base.sh`
- Modify: `mise.linux.toml`

**Interfaces:**
- Produces: `bootstrap/linux-base.sh`(引数なし、sudo を内部で使う、冪等)。

- [ ] **Step 1: 期待する plan 項目をテストに足す(失敗させる)**

`tests/bootstrap/plan.sh` の末尾に追記:

```sh
if [ "$(uname -s)" = Linux ]; then
  echo "== linux declarations are present"
  out="$(mise bootstrap plan 2>&1)"
  for want in apt:language-pack-ja apt:zsh apt:libssl-dev apt:qemu-system-arm \
              /etc/systemd/resolved.conf.d/dns.conf systemd-resolved /usr/bin/zsh; do
    echo "$out" | grep -q "$want" || { echo "FAIL: plan lacks $want" >&2; exit 1; }
  done
fi
```

Run(コンテナ): `tests/docker/exec.sh 'tests/bootstrap/plan.sh'`
Expected: `FAIL: plan lacks apt:language-pack-ja`

- [ ] **Step 2: linux-base.sh を書く**

```sh
#!/bin/sh
# Linux settings that mise bootstrap cannot declare: locale and timezone.
# Runs from the post-packages hook in mise.linux.toml on every bootstrap; keep it idempotent.
set -eu

if ! locale -a 2>/dev/null | grep -qix 'ja_JP\.utf8'; then
  sudo locale-gen ja_JP.UTF-8
fi
if ! grep -qx 'LANG=ja_JP.UTF-8' /etc/default/locale 2>/dev/null; then
  sudo update-locale LANG=ja_JP.UTF-8
fi

if command -v timedatectl >/dev/null 2>&1 &&
  [ "$(timedatectl show -p Timezone --value 2>/dev/null)" != "Asia/Tokyo" ]; then
  sudo timedatectl set-timezone Asia/Tokyo
fi
```

- [ ] **Step 3: mise.linux.toml を書く**

```toml
# Linux-only bootstrap settings (loaded automatically on Linux).

# ==========================================================================
# packages
# ==========================================================================
[bootstrap.packages]
# base
"apt:acl" = "latest"
"apt:apt-transport-https" = "latest"
"apt:bzip2" = "latest"
"apt:ca-certificates" = "latest"
"apt:curl" = "latest"
"apt:dnsutils" = "latest"
"apt:gnupg" = "latest"
"apt:lsb-release" = "latest"
"apt:software-properties-common" = "latest"
"apt:sshpass" = "latest"
"apt:tree" = "latest"
"apt:unzip" = "latest"
"apt:zip" = "latest"
"apt:zsh" = "latest"
# Japanese locale
"apt:language-pack-ja" = "latest"
"apt:manpages-ja" = "latest"
"apt:manpages-ja-dev" = "latest"
# Ruby build prerequisites
"apt:libssl-dev" = "latest"
"apt:libyaml-dev" = "latest"
"apt:zlib1g-dev" = "latest"
"apt:libgmp-dev" = "latest"
"apt:libffi-dev" = "latest"
"apt:autoconf" = "latest"
"apt:rustc" = "latest"
# ARM cross-compile toolchain
"apt:qemu-system-arm" = "latest"
"apt:g++-aarch64-linux-gnu" = "latest"

# ==========================================================================
# DNS
# ==========================================================================
[bootstrap.directories."/etc/systemd/resolved.conf.d"]
owner = "root"
group = "root"
mode = "0755"

[bootstrap.files."/etc/systemd/resolved.conf.d/dns.conf"]
content = """
# Managed by mise bootstrap (kukv/dotfiles)
[Resolve]
DNS=8.8.8.8 1.1.1.1
FallbackDNS=8.8.4.4 1.0.0.1
"""
owner = "root"
group = "root"
mode = "0644"
notify = ["systemd-resolved"]

[bootstrap.services.systemd-resolved]
on_change = "restart"

# ==========================================================================
# login shell
# ==========================================================================
[bootstrap.user]
login_shell = "/usr/bin/zsh"

# ==========================================================================
# hooks
# ==========================================================================
[bootstrap.hooks.post-packages]
run = "'{{ config_root }}/bootstrap/linux-base.sh'"
```

- [ ] **Step 4: テストと shellcheck を通す**

Run(ホスト): `chmod +x bootstrap/linux-base.sh`
Run(コンテナ): `tests/docker/exec.sh 'shellcheck bootstrap/*.sh && tests/bootstrap/plan.sh'`
Expected: exit 0。

- [ ] **Step 4b: コンテナに実際に適用して結果を確かめる**

Run(コンテナ):

```bash
tests/docker/exec.sh 'git_name=ci git_email=ci@example.com mise bootstrap --yes --only packages,files,services,user'
tests/docker/exec.sh 'locale -a | grep -i ja_JP.utf8; grep LANG /etc/default/locale; timedatectl show -p Timezone --value; resolvectl dns | head -3; getent passwd tech | cut -d: -f7'
tests/docker/exec.sh 'git_name=ci git_email=ci@example.com mise bootstrap --yes --only packages,files,services,user'   # 2 回目
```

Expected: 1 回目が exit 0。確認コマンドで `ja_JP.utf8`、`LANG=ja_JP.UTF-8`、`Asia/Tokyo`、`8.8.8.8 1.1.1.1` を含む行、`/usr/bin/zsh`。2 回目は変更なしで exit 0(冪等)。

- [ ] **Step 5: Commit**

```bash
git add bootstrap/linux-base.sh mise.linux.toml tests/bootstrap/plan.sh
git update-index --chmod=+x bootstrap/linux-base.sh
git commit -m "feat(bootstrap): Linux の apt・locale・TZ・DNS・login shell を宣言"
```

---

### Task 5: WSL module

**Files:**
- Create: `bootstrap/wsl-base.sh`
- Modify: `mise.wsl.toml`

- [ ] **Step 1: テストに WSL module の期待値を足す(失敗させる)**

`tests/bootstrap/plan.sh` の末尾に追記:

```sh
if [ "$(uname -s)" = Linux ]; then
  echo "== wsl module declarations are present only with -E wsl"
  mise -E wsl bootstrap plan 2>&1 | grep -q /etc/wsl.conf || { echo "FAIL: wsl.conf missing" >&2; exit 1; }
  ! mise bootstrap plan 2>&1 | grep -q /etc/wsl.conf || { echo "FAIL: wsl.conf leaked into base" >&2; exit 1; }
fi
```

Run(コンテナ): `tests/docker/exec.sh 'tests/bootstrap/plan.sh'`
Expected: `FAIL: wsl.conf missing`

- [ ] **Step 2: wsl-base.sh を書く**

```sh
#!/bin/sh
# WSL settings that mise bootstrap cannot declare. Runs from the post-packages
# hook in mise.wsl.toml on every bootstrap; keep it idempotent.
set -eu

# glibc sends A and AAAA queries in parallel on one UDP socket and WSL2's NAT
# drops one reply, so pointing resolv.conf at external servers stalls every
# lookup for 5s. Use the local systemd-resolved stub instead.
# ([bootstrap.files] cannot create symlinks.)
# Skipped in the Docker test container, where Docker bind-mounts resolv.conf.
stub="../run/systemd/resolve/stub-resolv.conf"
if [ ! -f /.dockerenv ] && [ "$(readlink /etc/resolv.conf 2>/dev/null || true)" != "$stub" ]; then
  sudo ln -sfn "$stub" /etc/resolv.conf
fi

# wslu is not packaged for Ubuntu 26.04 and later.
. /etc/os-release
if dpkg --compare-versions "$VERSION_ID" lt 26.04 && ! dpkg -s wslu >/dev/null 2>&1; then
  sudo apt-get install -y wslu
fi
```

- [ ] **Step 3: mise.wsl.toml を書く**

```toml
# Module "wsl": select with env = ["wsl"] in ~/.config/mise/miserc.local.toml on WSL machines.

[bootstrap.files."/etc/wsl.conf"]
content = """
# Managed by mise bootstrap (kukv/dotfiles). Restart WSL (wsl --shutdown) after changes.
[boot]
systemd=true

[network]
generateResolvConf=false
hostname=wsl2

[automount]
options="metadata,uid=1000,gid=1000,umask=22,fmask=11"
"""
owner = "root"
group = "root"
mode = "0644"

[bootstrap.hooks.post-packages]
run = "'{{ config_root }}/bootstrap/wsl-base.sh'"
```

★Q3: base(mise.linux.toml)と module の post-packages hook が「結合される」ことは docs 記載どおりだが、Step 4 の dry-run で両方の行が出ることを目視で確認する。

- [ ] **Step 4: テストを通す**

Run(ホスト): `chmod +x bootstrap/wsl-base.sh`
Run(コンテナ): `tests/docker/exec.sh 'shellcheck bootstrap/*.sh && tests/bootstrap/plan.sh && git_name=ci git_email=ci@example.com mise -E wsl bootstrap --dry-run 2>&1 | grep -E "linux-base|wsl-base"'`
Expected: exit 0、dry-run に `linux-base.sh` と `wsl-base.sh` の両方が出る。

- [ ] **Step 4b: コンテナに適用する**

Run(コンテナ):

```bash
tests/docker/exec.sh 'git_name=ci git_email=ci@example.com mise -E wsl bootstrap --yes --only packages,files && cat /etc/wsl.conf'
```

Expected: exit 0、`/etc/wsl.conf` の内容が表示される。resolv.conf の symlink は `/.dockerenv` によりスキップされる(実機確認は Task 12)。

- [ ] **Step 5: Commit**

```bash
git add bootstrap/wsl-base.sh mise.wsl.toml tests/bootstrap/plan.sh
git update-index --chmod=+x bootstrap/wsl-base.sh
git commit -m "feat(bootstrap): WSL module(wsl.conf・resolv.conf・wslu)を追加"
```

---

### Task 6: macOS パッケージと brew 更新

**Files:**
- Create: `bootstrap/macos-brew.sh`
- Modify: `mise.macos.toml`

- [ ] **Step 1: テストに macOS の期待値を足す(失敗させる)**

`tests/bootstrap/plan.sh` の末尾に追記:

```sh
if [ "$(uname -s)" = Darwin ]; then
  echo "== macos declarations are present"
  out="$(mise bootstrap plan 2>&1)"
  for want in brew:mise brew:mas brew-cask:1password brew-cask:docker-desktop mas:497799835; do
    echo "$out" | grep -q "$want" || { echo "FAIL: plan lacks $want" >&2; exit 1; }
  done
fi
```

Run: macos CI runner(Mac 実機での確認は別計画)。この時点では push せず、Step 4 でまとめて確認してよい。
Expected: `FAIL: plan lacks brew:mise`

- [ ] **Step 2: macos-brew.sh を書く**

```sh
#!/bin/sh
# Homebrew upkeep mise bootstrap does not cover. Runs from the post-packages hook
# in mise.macos.toml on every bootstrap; keep it idempotent.
set -eu
brew=/opt/homebrew/bin/brew

# tart / softnet are installed by hand (the tap's formula uses a syntax current
# Homebrew rejects), but keep the tap trusted so `brew upgrade` can handle them.
"$brew" tap cirruslabs/cli >/dev/null
"$brew" trust cirruslabs/cli >/dev/null

# Formulae only: upgrading casks such as docker-desktop asks for sudo, which a
# scheduled (non-interactive) run cannot answer.
"$brew" update
"$brew" upgrade --formula
```

- [ ] **Step 3: mise.macos.toml を書く**

```toml
# macOS-only bootstrap settings (loaded automatically on macOS).

# ==========================================================================
# packages
# ==========================================================================
[bootstrap.packages]
"brew:mise" = "latest"
"brew:git" = "latest"
"brew:tree" = "latest"
"brew:nkf" = "latest"
"brew:ffmpeg" = "latest"
"brew:plantuml" = "latest"
"brew:nmap" = "latest"
"brew:gnupg" = "latest"
"brew:mas" = "latest"

"brew-cask:font-hack-nerd-font" = "latest"
"brew-cask:google-chrome" = "latest"
"brew-cask:visual-studio-code" = "latest"
"brew-cask:raycast" = "latest"
"brew-cask:1password" = "latest"
"brew-cask:1password-cli" = "latest"
"brew-cask:jetbrains-toolbox" = "latest"
"brew-cask:slack" = "latest"
"brew-cask:notion" = "latest"
"brew-cask:discord" = "latest"
"brew-cask:iterm2" = "latest"
"brew-cask:spotify" = "latest"
"brew-cask:clipy" = "latest"
"brew-cask:daisydisk" = "latest"
"brew-cask:thebrowsercompany-dia" = "latest"
"brew-cask:onyx" = "latest"
"brew-cask:raspberry-pi-imager" = "latest"
"brew-cask:vnc-viewer" = "latest"
"brew-cask:drawio" = "latest"
"brew-cask:docker-desktop" = "latest"
"brew-cask:linear" = "latest"
# pkg/installer casks that require sudo are NOT managed here (a scheduled run
# cannot answer the password prompt). Install/upgrade manually:
#   cloudflare-warp, logi-options+, microsoft-office, onedrive, zoom
# LocalStack Desktop is not distributed via Homebrew or the App Store.

# Mac App Store (requires App Store sign-in)
"mas:539883307" = "latest"  # LINE
"mas:302584613" = "latest"  # Amazon Kindle
"mas:497799835" = "latest"  # Xcode

# ==========================================================================
# hooks
# ==========================================================================
[bootstrap.hooks.post-packages]
run = "'{{ config_root }}/bootstrap/macos-brew.sh'"
```

- [ ] **Step 4: テストを通す**

Run(ホスト): `chmod +x bootstrap/macos-brew.sh`
Run(コンテナ): `tests/docker/exec.sh 'shellcheck bootstrap/*.sh && tests/bootstrap/plan.sh'`(Linux 側が壊れていないこと)
macOS 側は Task 10 Step 6 の push 後、macos CI runner の `bootstrap` ジョブで確認する。Mac 実機での `plan` / 適用確認は別計画で行う。
Expected: コンテナで exit 0。CI の macos ジョブで plan.sh が exit 0。

- [ ] **Step 5: Commit**

```bash
git add bootstrap/macos-brew.sh mise.macos.toml tests/bootstrap/plan.sh
git update-index --chmod=+x bootstrap/macos-brew.sh
git commit -m "feat(bootstrap): macOS の brew formulae・casks・mas と brew 更新を宣言"
```

---

### Task 7: bootstrap task(corepack・herdr・Claude skills・Claude Code)

**Files:**
- Create: `bootstrap/post-tools.sh`
- Modify: `mise.toml`

- [ ] **Step 1: テストに task の存在確認を足す(失敗させる)**

`tests/bootstrap/plan.sh` の末尾に追記:

```sh
echo "== bootstrap task is defined"
mise tasks ls 2>/dev/null | grep -q '^bootstrap' || { echo "FAIL: bootstrap task missing" >&2; exit 1; }
```

Run(コンテナ): `tests/docker/exec.sh 'tests/bootstrap/plan.sh'`
Expected: `FAIL: bootstrap task missing`

- [ ] **Step 2: post-tools.sh を書く**

```sh
#!/bin/sh
# Setup that needs tools from [tools]. Runs as the `bootstrap` task (last step of
# mise bootstrap) on every run; keep it idempotent.
set -eu

# corepack shims in node's bin shadow the pnpm / yarn that mise manages, and
# mise's npm backend then picks the wrong pnpm (ERR_PNPM_NO_GLOBAL_BIN_DIR).
for shim in "$HOME"/.local/share/mise/installs/node/*/bin/pnpm; do
  if [ -e "$shim" ]; then
    mise exec node -- corepack disable
    break
  fi
done

# herdr plugins: "<plugin_id> <repo>" (plugin_id is the install dir prefix).
while read -r id repo; do
  set -- "$HOME"/.config/herdr/plugins/github/"$id"-*
  [ -e "$1" ] || herdr plugin install "$repo" --yes
done <<'EOF'
kukv.github-dash kukv/herdr-plugin-github-dash
herdr-file-viewer smarzban/herdr-file-viewer
hunk.diff edmundmiller/herdr-plugin-hunk
official.browser ogulcancelik/herdr-browser
EOF

# Claude Code skills: "<skill> <repo>". hunk-review is intentionally absent:
# the self-made loader in ~/.claude/skills/hunk-review (chezmoi) matches the
# mise-managed npm:hunkdiff version.
while read -r name repo; do
  [ -e "$HOME/.claude/skills/$name" ] ||
    skills add "$repo" --skill "$name" --agent claude-code --global --yes
done <<'EOF'
herdr herdrdev/herdr
find-skills vercel-labs/skills
ax yusukebe/ax
ast-grep ast-grep/agent-skill
ast-grep-outline ast-grep/agent-skill
EOF

# Claude Code CLI (self-updating; install once).
if ! command -v claude >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/claude" ]; then
  curl -fsSL https://claude.ai/install.sh | bash
fi
```

- [ ] **Step 3: mise.toml に task を追加する**

`mise.toml` の末尾に追記(★Q5 が「同じ実行では入らない」なら `run` の先頭に `"mise install --yes"` を足す):

```toml
# ==========================================================================
# bootstrap task (runs last in `mise bootstrap`, with [tools] on PATH)
# ==========================================================================
[tasks.bootstrap]
description = "Post-tools setup: corepack, herdr plugins, Claude skills, Claude Code"
run = ["'{{ config_root }}/bootstrap/post-tools.sh'"]
```

- [ ] **Step 4: テストと単体実行で確認する**

Run(ホスト): `chmod +x bootstrap/post-tools.sh`
Run(コンテナ): `tests/docker/exec.sh 'shellcheck bootstrap/*.sh && tests/bootstrap/plan.sh'`
Expected: exit 0

- [ ] **Step 4b: コンテナで bootstrap 全体を初めて通す**

chezmoi で `~/.config/mise/config.toml` が配置され、全ツールが入るので時間がかかる(数十分)。

Run(コンテナ):

```bash
tests/docker/exec.sh 'git_name=ci git_email=ci@example.com mise -E wsl bootstrap --yes'
tests/docker/exec.sh 'ls ~/.config/herdr/plugins/github/; ls ~/.claude/skills/; command -v claude; grep -c "name = ci" ~/.gitconfig'
tests/docker/exec.sh 'git_name=ci git_email=ci@example.com mise -E wsl bootstrap --yes'   # 2 回目
```

Expected: 1 回目 exit 0。herdr プラグイン 4 つ、skills 5 つ(+ chezmoi が置く hunk-review)、`claude` のパス、`1` が表示される。2 回目はインストールが走らず exit 0。
★Q5 が「同じ実行では tools が入らない」だった場合、1 回目で tools が入らず task が失敗するので、Step 3 の注記どおり `mise install` を task の先頭に足してから再実行する。

- [ ] **Step 5: Commit**

```bash
git add bootstrap/post-tools.sh mise.toml tests/bootstrap/plan.sh
git update-index --chmod=+x bootstrap/post-tools.sh
git commit -m "feat(bootstrap): corepack・herdr・Claude skills・Claude Code を bootstrap task に移す"
```

---

### Task 8: 定期実行(ラッパー・systemd user timer・launchd agent・linger)

**Files:**
- Create: `bootstrap/scheduled-run.sh`
- Modify: `mise.linux.toml`, `mise.macos.toml`

**Interfaces:**
- Produces: unit 名 `dev.mise.mise-bootstrap.service` / `dev.mise.mise-bootstrap-weekly.timer`(Linux)、agent 名 `dev.mise.mise-bootstrap`(Mac)。Task 9 の `update_os` alias が参照する。

- [ ] **Step 1: テストに期待値を足す(失敗させる)**

`tests/bootstrap/plan.sh` の末尾に追記:

```sh
echo "== scheduler is declared"
out="$(mise bootstrap plan 2>&1)"
case "$(uname -s)" in
  Linux)  want=mise-bootstrap-weekly ;;
  Darwin) want=dev.mise.mise-bootstrap ;;
esac
echo "$out" | grep -q "$want" || { echo "FAIL: plan lacks $want" >&2; exit 1; }
```

Run(コンテナ): `tests/docker/exec.sh 'tests/bootstrap/plan.sh'`
Expected: `FAIL: plan lacks mise-bootstrap-weekly`

- [ ] **Step 2: scheduled-run.sh を書く**

```sh
#!/bin/sh
# Weekly re-provisioning: pull kukv/dotfiles and re-apply mise bootstrap.
# Started by the systemd user timer (Linux) or the LaunchAgent (macOS), and by
# the `update_os` alias. Neither scheduler gives us the login shell's PATH.
set -eu
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

# Secrets (MISE_GITHUB_TOKEN, HOMEBREW_GITHUB_API_TOKEN) via the environment,
# never argv.
if [ -f "$HOME/.local/etc/bootstrap.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$HOME/.local/etc/bootstrap.env"
  set +a
fi

if [ "$(uname -s)" = Darwin ]; then
  # Dated files so old logs age out (a single appended file never would).
  log_dir="$HOME/.local/log/mise-bootstrap"
  mkdir -p "$log_dir"
  find "$log_dir" -type f -mtime +90 -delete
  exec >>"$log_dir/$(date +%Y%m%d).log" 2>&1
else
  # Linux installs mise with mise.run; macOS updates it through Homebrew.
  mise self-update --yes
fi

exec mise bootstrap --from https://github.com/kukv/dotfiles.git --update --yes
```

- [ ] **Step 3: Linux の timer と linger を宣言する**

`mise.linux.toml` の末尾に追記:

```toml
# ==========================================================================
# scheduled re-provisioning (weekly)
# ==========================================================================
[bootstrap.linux.systemd.units.mise-bootstrap]
description = "Re-apply kukv/dotfiles mise bootstrap"
type = "oneshot"
exec_start = "~/.local/share/mise/bootstrap-repo/bootstrap/scheduled-run.sh"
start = false
wanted_by = []

[bootstrap.linux.systemd.units.mise-bootstrap-weekly]
on_calendar = "weekly"
persistent = true
unit = "mise-bootstrap"

# Keep the user manager (and the timer) running while logged out.
[bootstrap.hooks.post-user]
run = "loginctl show-user \"$USER\" -p Linger --value | grep -qx yes || sudo loginctl enable-linger \"$USER\""
```

- [ ] **Step 4: macOS の agent を宣言する**

`mise.macos.toml` の末尾に追記:

```toml
# ==========================================================================
# scheduled re-provisioning (Sundays 21:00)
# ==========================================================================
[bootstrap.macos.launchd.agents.mise-bootstrap]
program = "~/.local/share/mise/bootstrap-repo/bootstrap/scheduled-run.sh"
start_calendar_interval = [{ weekday = 0, hour = 21, minute = 0 }]
```

- [ ] **Step 5: テストを通す**

Run(ホスト): `chmod +x bootstrap/scheduled-run.sh`
Run(コンテナ): `tests/docker/exec.sh 'shellcheck bootstrap/*.sh && tests/bootstrap/plan.sh'`
Expected: exit 0

- [ ] **Step 5b: コンテナで timer と linger を確かめる**

Run(コンテナ):

```bash
tests/docker/exec.sh 'git_name=ci git_email=ci@example.com mise bootstrap --yes --only linux-systemd-units,user'
tests/docker/exec.sh 'loginctl show-user tech -p Linger --value; systemctl --user list-timers | grep mise-bootstrap; systemctl --user cat dev.mise.mise-bootstrap.service | grep ExecStart'
```

Expected: `yes`、timer の行、`ExecStart=…/.local/share/mise/bootstrap-repo/bootstrap/scheduled-run.sh`。
(timer の実行そのものは `--from` のチェックアウトが前提なので Task 11 で確認する。)

- [ ] **Step 6: Commit**

```bash
git add bootstrap/scheduled-run.sh mise.linux.toml mise.macos.toml tests/bootstrap/plan.sh
git update-index --chmod=+x bootstrap/scheduled-run.sh
git commit -m "feat(bootstrap): 週次の定期実行を systemd user timer / LaunchAgent で宣言"
```

---

### Task 9: chezmoi テンプレートの追随(linuxbrew・update_os)

**Files:**
- Modify: `home/dot_zprofile.tmpl:25-35`
- Modify: `home/dot_zshrc.tmpl:110-116`
- Modify: `.github/workflows/ci.yaml`(既存 `apply` ジョブに assert を 1 つ追加)

- [ ] **Step 1: 既存 CI ジョブに失敗する assert を足す**

`.github/workflows/ci.yaml` の `apply` ジョブ、「Assert native Linux ssh routing」ステップの直後に追加する
(既存コメントが「存在確認の assert は足すな」としているので、残骸が無いことだけを確認する):

```yaml
      - name: Assert no os-setup / linuxbrew remnants
        run: |
          if grep -q linuxbrew "$DEST/.zprofile"; then echo 'linuxbrew left in zprofile' >&2; exit 1; fi
          if grep -q 'os-setup' "$DEST/.zshrc"; then echo 'os-setup reference left in zshrc' >&2; exit 1; fi
```

コンテナで同等の確認:

```bash
tests/docker/exec.sh 'mise exec chezmoi@latest -- chezmoi --source /dotfiles --config /dev/null execute-template < home/dot_zprofile.tmpl | grep -q linuxbrew && echo "FAIL (expected before fix)"'
```

Expected: `FAIL (expected before fix)`

- [ ] **Step 2: dot_zprofile.tmpl の linuxbrew ブロックを削除する**

変更前(25〜35 行):

```
{{- else }}
# ========================================================
# = Homebrew (Linux / WSL)
# ========================================================
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

# ========================================================
# = Build parallelization
# ========================================================
export JOBMAX=$(nproc)
{{- end }}
```

変更後:

```
{{- else }}
# ========================================================
# = Build parallelization
# ========================================================
export JOBMAX=$(nproc)
{{- end }}
```

- [ ] **Step 3: dot_zshrc.tmpl の update_os を差し替える**

変更前(110〜116 行):

```
{{- if eq .chezmoi.os "darwin" }}
# provision this machine now (kukv/os-setup launchd wrapper; ~/.local/bin is on PATH)
alias update_os='os-setup-pull.sh'
{{- else if eq .chezmoi.os "linux" }}
# provision this machine now (kukv/os-setup systemd service; root-owned unit)
alias update_os='sudo systemctl start os-setup.service'
{{- end }}
```

変更後:

```
{{- if eq .chezmoi.os "darwin" }}
# provision this machine now (mise bootstrap; log: ~/.local/log/mise-bootstrap/)
alias update_os='~/.local/share/mise/bootstrap-repo/bootstrap/scheduled-run.sh'
{{- else if eq .chezmoi.os "linux" }}
# provision this machine now (mise bootstrap user unit; log: journalctl --user -u dev.mise.mise-bootstrap)
alias update_os='systemctl --user start dev.mise.mise-bootstrap.service'
{{- end }}
```

- [ ] **Step 4: 確認する**

Run(コンテナ): `tests/docker/exec.sh 'tests/bootstrap/chezmoi-apply.test.sh'` と Step 1 のコンテナ確認コマンド
Expected: テストは `PASS`、ローカル確認は何も出力しない(linuxbrew が消えた)

- [ ] **Step 5: Commit**

```bash
git add home/dot_zprofile.tmpl home/dot_zshrc.tmpl .github/workflows/ci.yaml
git commit -m "feat(dotfiles): linuxbrew を外し update_os を mise bootstrap に向ける"
```

---

### Task 10: 初回構築スクリプト(init.sh)と README

**Files:**
- Create: `bootstrap/init.sh`
- Modify: `README.md`(「適用方法」節)

**Interfaces:**
- Consumes: Task 8 のチェックアウトパス。
- Produces: `init.sh [--env <a,b>] [--branch <ref>]`

- [ ] **Step 1: 引数処理のテストを書く(失敗させる)**

`tests/bootstrap/init.test.sh`:

```sh
#!/bin/sh
# Dry checks for bootstrap/init.sh: argument handling and the generated miserc.
set -eu
repo="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

out="$(INIT_DRY_RUN=1 HOME="$tmp" sh "$repo/bootstrap/init.sh" --env wsl,work --branch migration)"
grep -qx 'env = \["wsl", "work"\]' "$tmp/.config/mise/miserc.local.toml" || fail "miserc env"
echo "$out" | grep -q 'mise bootstrap --from https://github.com/kukv/dotfiles.git?ref=migration --prompt-vars' || fail "bootstrap command"
[ "$(stat -c %a "$tmp/.local/etc/bootstrap.env" 2>/dev/null || stat -f %Lp "$tmp/.local/etc/bootstrap.env")" = "600" ] || fail "bootstrap.env mode"

rm -rf "$tmp/.config"
INIT_DRY_RUN=1 HOME="$tmp" sh "$repo/bootstrap/init.sh" >/dev/null
[ ! -f "$tmp/.config/mise/miserc.local.toml" ] || fail "no --env must not write miserc"

sh "$repo/bootstrap/init.sh" --bogus >/dev/null 2>&1 && fail "unknown option must fail"
echo PASS
```

Run(ホスト): `chmod +x tests/bootstrap/init.test.sh`
Run(コンテナ): `tests/docker/exec.sh 'tests/bootstrap/init.test.sh'`
Expected: FAIL(init.sh が無い)

- [ ] **Step 2: init.sh を書く**

```sh
#!/bin/sh
# First-time setup for a new machine: install mise, pick this machine's modules,
# then hand over to `mise bootstrap --from kukv/dotfiles`.
#
#   curl -fsSL https://raw.githubusercontent.com/kukv/dotfiles/main/bootstrap/init.sh | sh -s -- --env wsl
#
# Run as your own user (not root); sudo is used where needed.
set -eu

ENVS=""
BRANCH="main"
REPO_URL="https://github.com/kukv/dotfiles.git"

usage() {
  cat <<'EOF'
Usage: init.sh [--env <module,...>] [--branch <ref>]
  --env     modules for this machine (e.g. "wsl" or "wsl,work"; none on macOS)
  --branch  dotfiles branch to bootstrap from (default: main)
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --env) ENVS="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

# INIT_DRY_RUN=1 prints system-changing commands instead of running them (tests).
run() {
  if [ -n "${INIT_DRY_RUN:-}" ]; then echo "$*"; else "$@"; fi
}

case "$(uname -s)" in
  Darwin)
    if ! xcode-select -p >/dev/null 2>&1; then
      echo "Xcode Command Line Tools required: xcode-select --install" >&2
      exit 1
    fi
    if [ ! -x /opt/homebrew/bin/brew ]; then
      run /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    run /opt/homebrew/bin/brew install mise
    MISE=/opt/homebrew/bin/mise
    ;;
  Linux)
    # Scheduled runs use sudo for apt and /etc; they cannot answer a password prompt.
    sudoers="/etc/sudoers.d/$(id -un)"
    if ! sudo test -f "$sudoers"; then
      run sh -c "echo '$(id -un) ALL=(ALL) NOPASSWD: ALL' | sudo tee '$sudoers' >/dev/null && sudo chmod 440 '$sudoers'"
    fi
    run sudo apt-get update
    run sudo apt-get install -y git curl
    if [ ! -x "$HOME/.local/bin/mise" ]; then
      run sh -c "curl -fsSL https://mise.run | sh"
    fi
    MISE="$HOME/.local/bin/mise"
    ;;
  *) echo "Unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac

if [ -n "$ENVS" ]; then
  mkdir -p "$HOME/.config/mise"
  # "wsl,work" -> env = ["wsl", "work"]
  list="$(echo "$ENVS" | sed 's/[[:space:]]//g; s/,/", "/g')"
  printf 'env = ["%s"]\n' "$list" > "$HOME/.config/mise/miserc.local.toml"
fi

mkdir -p "$HOME/.local/etc"
if [ ! -f "$HOME/.local/etc/bootstrap.env" ]; then
  (umask 077 && : > "$HOME/.local/etc/bootstrap.env")
fi

run "$MISE" bootstrap --from "$REPO_URL?ref=$BRANCH" --prompt-vars
```

★Q6: trust を求められる場合は最終行の前に、自前で clone して trust する 2 行を挟む(`--dry-run` はチェックアウトが無いと clone せずに止まるため使えない):

```sh
[ -d "$HOME/.local/share/mise/bootstrap-repo/.git" ] || run git clone -b "$BRANCH" "$REPO_URL" "$HOME/.local/share/mise/bootstrap-repo"
run "$MISE" trust "$HOME/.local/share/mise/bootstrap-repo"
```

- [ ] **Step 3: テストを通す**

Run(ホスト): `chmod +x bootstrap/init.sh`
Run(コンテナ): `tests/docker/exec.sh 'shellcheck bootstrap/init.sh && tests/bootstrap/init.test.sh'`
Expected: `PASS`

注: Linux では INIT_DRY_RUN でも `sudo test -f` が走る。コンテナと CI runner は NOPASSWD なので問題ない。

- [ ] **Step 4: README を更新する**

`README.md` の「## 適用方法」節を以下に置き換える:

````markdown
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
mise を導入し、`mise bootstrap --from kukv/dotfiles` で OS 設定・パッケージ・dotfiles(chezmoi)・ツールを適用します。
初回に git の name / email を聞かれます(`~/.local/state/mise/vars.toml` に保存)。WSL は適用後に `wsl --shutdown` で再起動してください。
GitHub token は `~/.local/etc/bootstrap.env`(0600)に `MISE_GITHUB_TOKEN=…` / `HOMEBREW_GITHUB_API_TOKEN=…` として置きます。

### 構成
- `mise.toml`(全マシン共通)/ `mise.linux.toml`・`mise.macos.toml`(OS 別、自動で読まれる)
- `mise.wsl.toml`・`mise.work.toml`(module。`~/.config/mise/miserc.local.toml` の `env` で選ぶ)
- `bootstrap/`(init と hook 用スクリプト)、`home/`(chezmoi ソース)

### 再適用
週次で自動実行されます(Linux: systemd user timer、macOS: LaunchAgent)。手動では `update_os`。
````

`kukv/os-setup` への言及(冒頭の「通常は kukv/os-setup のプロビジョニングから…」と「### 自動(推奨)」)も削除し、「マシンローカル設定・秘密情報」以降の節は変更しない。

- [ ] **Step 5: CI にテストを足して Commit**

`.github/workflows/ci.yaml` の `bootstrap` ジョブ末尾に追記:

```yaml
      - name: init.sh
        run: tests/bootstrap/init.test.sh
```

```bash
git add bootstrap/init.sh tests/bootstrap/init.test.sh README.md .github/workflows/ci.yaml
git update-index --chmod=+x bootstrap/init.sh tests/bootstrap/init.test.sh
git commit -m "feat(bootstrap): 初回構築用の init.sh と README を追加"
```

- [ ] **Step 6: push して CI を確認する**

```bash
git push -u origin migration
gh run watch "$(gh run list --branch migration --limit 1 --json databaseId -q '.[0].databaseId')"
```

Expected: `apply` と `bootstrap` の全マトリクスが成功。失敗したらログを読んで該当タスクに戻る。

---

### Task 11: ゼロ構築の検証(Docker の素の Ubuntu で init.sh から)

**Files:** なし(検証のみ。結果は spec の「検証結果」節に追記)

前提: Task 10 Step 6 で `migration` ブランチが push 済み。

- [ ] **Step 1: 素のコンテナを起動する**

Run(ホスト):

```bash
docker compose -f tests/docker/compose.yaml down
docker compose -f tests/docker/compose.yaml up -d --build e2e
tests/docker/exec.sh -s e2e 'command -v mise git || echo "clean"'
```

Expected: `clean`(mise も git も無い)

- [ ] **Step 2: init.sh を migration ブランチで流す**

Run(ホスト、対話あり):

```bash
tests/docker/exec.sh -s e2e 'curl -fsSL https://raw.githubusercontent.com/kukv/dotfiles/migration/bootstrap/init.sh | sh -s -- --env wsl,work --branch migration'
```

Expected: git name / email を聞かれ(テスト用の値を入力)、最後まで exit 0。全ツールを入れるので数十分かかる。
`--env wsl,work` で、全 module が載った最も重い組み合わせを通す。

- [ ] **Step 3: 成功条件を確認する**

Run(コンテナ):

```bash
tests/docker/exec.sh -s e2e 'mise bootstrap status'
tests/docker/exec.sh -s e2e 'mise exec chezmoi@latest -- chezmoi diff; echo "diff-exit=$?"'
tests/docker/exec.sh -s e2e 'grep -E "allowedSignersFile|op-ssh-sign" ~/.gitconfig; mise vars use_1password'
tests/docker/exec.sh -s e2e 'getent passwd tech | cut -d: -f7; systemctl --user list-timers | grep mise-bootstrap'
tests/docker/exec.sh -s e2e 'systemctl --user start dev.mise.mise-bootstrap.service; journalctl --user -u dev.mise.mise-bootstrap -n 20 --no-pager'
```

Expected:
- status が全項目 applied / installed / unchanged
- chezmoi diff の出力が空で `diff-exit=0`
- gitconfig に `allowedSignersFile`(work module により 1Password 無し)、`false`
- `/usr/bin/zsh`、timer の行
- 手動起動した定期実行が `--update` を含めて成功している(ログ末尾にエラーが無い)

- [ ] **Step 4: 片付けと記録**

```bash
docker compose -f tests/docker/compose.yaml down
git add docs/superpowers/specs/2026-10-15-mise-bootstrap-migration-design.md
git commit -m "docs: Docker でのゼロ構築検証結果を記録"
```

結果(問題と対処)は commit 前に spec の「検証結果」節へ追記する。

---

### Task 12: 既存マシンの移行(個人 WSL → Mac → 会社 WSL)【ユーザー操作あり】

マシンごとに以下を実施する。各マシンでユーザーの確認を取ってから始める。
**Mac は別計画の動作確認が完了してから実施する**(手順は以下の Mac 向け記述に従う)。全 3 台が終わるまで Task 13 に進まない。

- [ ] **Step 1: 移行前の状態を保存する**

```bash
b=~/migration-backup-$(date +%Y%m%d); mkdir -p "$b"
cp -p ~/.gitconfig ~/.zshrc ~/.zprofile ~/.config/mise/config.toml "$b"/ 2>/dev/null || true
[ -f ~/.ssh/config ] && cp -p ~/.ssh/config "$b"/ssh_config
cp -p ~/.config/chezmoi/chezmoi.toml "$b"/ 2>/dev/null || true
```

- [ ] **Step 2: 旧定期実行を止める**

Linux:

```bash
sudo systemctl disable --now os-setup.timer
sudo rm -f /etc/systemd/system/os-setup.service /etc/systemd/system/os-setup.timer
sudo systemctl daemon-reload
```

Mac:

```bash
for p in ~/Library/LaunchAgents/com.kukv.os-setup*.plist; do launchctl bootout "gui/$(id -u)" "$p" 2>/dev/null || true; rm -f "$p"; done
rm -f ~/.local/bin/os-setup-pull.sh
```

- [ ] **Step 3: 秘密情報と vars を移す**

```bash
mkdir -p ~/.local/etc && (umask 077 && touch ~/.local/etc/bootstrap.env)
# Linux: /etc/ansible/extra_vars.yaml の github_token を、Mac: ~/.local/etc/os-setup.env の値を転記する
${EDITOR:-vi} ~/.local/etc/bootstrap.env    # MISE_GITHUB_TOKEN=… / HOMEBREW_GITHUB_API_TOKEN=…
grep -E 'git_name|git_email' ~/.config/chezmoi/chezmoi.toml   # 値を確認
mise vars git_name="<上の値>" git_email="<上の値>"
```

会社 WSL で `git_signing_key_file` を既定以外にしている場合のみ: `mise vars git_signing_key_file="<値>"`

- [ ] **Step 4: env を選ぶ**

```bash
printf 'env = ["wsl"]\n' > ~/.config/mise/miserc.local.toml          # 個人 WSL
printf 'env = ["wsl", "work"]\n' > ~/.config/mise/miserc.local.toml  # 会社 WSL
# Mac は作らない
```

- [ ] **Step 5: (Linux のみ)mise を入れ直して linuxbrew を外す**

```bash
curl -fsSL https://mise.run | sh
~/.local/bin/mise --version
NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"
sudo rm -rf /home/linuxbrew
```

- [ ] **Step 6: 差分を確認してから適用する**

`--from` の `--dry-run` はチェックアウトが無いと clone せずに止まるので、先に自前で clone する
(origin URL が `--from` に渡す URL と一致すれば、mise はそのチェックアウトをそのまま使う)。

```bash
m="$(command -v mise || echo ~/.local/bin/mise)"
co=~/.local/share/mise/bootstrap-repo
git clone -b migration https://github.com/kukv/dotfiles.git "$co"
(cd "$co" && "$m" trust . && "$m" bootstrap plan && "$m" bootstrap --dry-run)
"$m" bootstrap --from "https://github.com/kukv/dotfiles.git"
```

Expected: plan / dry-run で、想定外の削除や上書きが無いことをユーザーと確認してから最終行で適用する。

- [ ] **Step 7: 成功条件を確認する**

```bash
mise bootstrap status
mise exec chezmoi@latest -- chezmoi diff
for f in .gitconfig .zshrc .zprofile; do diff "$b/$f" ~/"$f"; done
[ -f "$b/ssh_config" ] && diff "$b/ssh_config" ~/.ssh/config
update_os   # 新しいシェルで。Linux は journalctl --user -u dev.mise.mise-bootstrap で結果確認、Mac は ~/.local/log/mise-bootstrap/
```

Expected: status 全一致、chezmoi diff 空、diff は `update_os` 行と zprofile の linuxbrew 行だけ。

WSL のみ、Docker では確認できなかった項目をここで確認する:

```bash
readlink /etc/resolv.conf            # ../run/systemd/resolve/stub-resolv.conf
getent hosts github.com              # 即座に返る(5 秒待たされない)
alias ssh                            # ssh='ssh.exe'
```

PowerShell で `wsl --shutdown` → 再度開いて、`systemctl --user list-timers | grep mise-bootstrap` が出ること。

- [ ] **Step 8: 後片付け**

```bash
rm -rf ~/.local/share/chezmoi
# Linux: 旧 Ansible の残骸
sudo rm -rf /var/log/ansible /etc/ansible/extra_vars.yaml
# Mac: 旧ファイル
rm -f ~/.local/etc/extra_vars.yaml ~/.local/etc/os-setup.env
```

Linux で旧 `/etc/systemd/resolved.conf` に Ansible の `# BEGIN DNS SETUP` ブロックが残るが、drop-in と同じ値なので無害。消す場合は手で削除する。

---

### Task 13: main へのマージと切り替え・os-setup の撤去【ユーザー確認あり】

- [ ] **Step 1: PR を作ってマージする**(全 3 台の Task 12 完了後)

```bash
gh pr create --base main --head migration --title "os-setup (Ansible) から mise bootstrap へ移行" --body "$(cat <<'EOF'
os-setup(Ansible)の責務を mise bootstrap に移し、dotfiles 単体でマシンを構築・定期再適用できるようにする。

- 設計: docs/superpowers/specs/2026-10-15-mise-bootstrap-migration-design.md
- 計画: docs/superpowers/plans/2026-10-15-mise-bootstrap-migration.md
- 3 台(Mac / 個人 WSL / 会社 WSL)とも migration ブランチで移行・検証済み

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

マージはユーザーが行う。

- [ ] **Step 2: 各マシンのチェックアウトを main に切り替える**

```bash
co=~/.local/share/mise/bootstrap-repo
rm -rf "$co"
git clone https://github.com/kukv/dotfiles.git "$co"   # main
mise trust "$co"
mise bootstrap --from https://github.com/kukv/dotfiles.git
```

- [ ] **Step 3: os-setup をアーカイブする(ユーザー確認の上で実施)**

os-setup の README 冒頭に移転先を書いて main に push してから、アーカイブする:

```markdown
> **このリポジトリはアーカイブされました。** マシン構築は [kukv/dotfiles](https://github.com/kukv/dotfiles) の mise bootstrap に移行しました。
```

```bash
gh repo archive kukv/os-setup --yes
```
