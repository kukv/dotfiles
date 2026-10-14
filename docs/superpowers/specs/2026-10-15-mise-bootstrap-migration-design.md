# os-setup (Ansible) → mise bootstrap 移行 設計

- 日付: 2026-10-15
- ブランチ: `migration`(dotfiles)
- 対象マシン: Mac / 個人 WSL / 会社 WSL

## 目的と範囲

**目的:** Ansible をやめる。`kukv/os-setup` が担っている OS 設定・パッケージ導入・オーケストレーション・定期実行を、
dotfiles リポジトリ内の mise bootstrap 設定へ移し、os-setup を廃止する。

**今回の範囲:** Ansible の撤去まで。chezmoi は残し、mise bootstrap の hook から呼ぶ。

**範囲外(将来フェーズ):** chezmoi → mise `[dotfiles]` への移行、oh-my-zsh の扱い。検討内容は末尾「将来フェーズ」に記録する。

**採用しなかった案:**
- Nix(nix-darwin / NixOS-WSL / home-manager): 世代管理・ロールバックが不要で、学習・移行コストに見合わない。
- `--adopt`(グローバル設定リポジトリ方式): 現 dotfiles(chezmoi 構成)と形が合わない。
- bootstrap 専用リポジトリ新設: リポジトリが 2 つ残り目的に反する。

## 現行構成の分岐軸(移行で保持すべきもの)

| 軸 | 現在の表現 | 影響箇所 |
|---|---|---|
| OS(mac / linux) | chezmoi `.chezmoi.os`、Ansible `os_family` | zprofile(brew / Toolbox / LC_ALL / JOBMAX)、zshrc(Nerd Font / docker 補完 / `update_os`)、`.chezmoiignore`(`.ssh/config`・`Library` は mac のみ)、Ansible 全 role |
| WSL か否か | chezmoi は kernel 文字列、Ansible は `is_wsl` | gitconfig(`sshCommand = ssh.exe`、`op-ssh-sign-wsl.exe`)、zshrc(`ssh`/`ssh-add`/`scp` → `.exe`)、`wsl.conf`・wslu・resolv.conf |
| 1Password 利用(= 会社 PC か否か) | chezmoi data `use_1password`(会社 PC のみ `false`) | gitconfig(署名 program / `allowedSignersFile`)、ssh config(`Include ~/.ssh/1Password/config`)、zshrc(`SSH_AUTH_SOCK`、mac)、`allowed_signers` |
| マシン固有値 | chezmoi `promptStringOnce` / extra_vars / os-setup.env | `git_name`・`git_email`・`git_signing_key_file`・`github_token`・`provisioning_schedule` |

## 設計

### 1. ファイル配置と差分の表現

```
dotfiles/
├── .miserc.toml        # auto_env = true(platform ファイル有効化)
├── mise.toml           # base:全マシン共通(vars / hooks / bootstrap task / 共通 packages)
├── mise.linux.toml     # platform:apt、locale/TZ/DNS、login shell、systemd user timer
├── mise.macos.toml     # platform:brew formulae/casks/taps、mas、launchd agent
├── mise.wsl.toml       # module:wsl.conf、resolv.conf → stub、wslu
├── mise.work.toml      # module:[vars] use_1password = "false"
├── bootstrap/          # init.sh、hook / timer から呼ぶスクリプト
├── home/               # 既存 chezmoi ソース(テンプレートは変更しない)
└── docs/
```

- **OS 差分:** platform ファイル(`mise.linux.toml` / `mise.macos.toml`)。1 行単位なら `os = "macos"`。
- **マシン役割差分:** Machine modules。各マシンの `~/.config/mise/miserc.local.toml`(非コミット)で選択する。

| マシン | `env` |
|---|---|
| Mac | なし |
| 個人 WSL | `["wsl"]` |
| 会社 WSL | `["wsl", "work"]` |

- **運用ルール:** base(`mise.toml` と platform ファイル)には全マシン共通のものだけを置く。差分は module に置く。
  base の何かを特定マシンで不要にしたくなったら、`state = "absent"` で打ち消さず、base から外して module(例: `personal`)へ移す。
  「module × OS」の差分が増えたら conf.d フォルダ(`conf.d/work/mise.toml` + `conf.d/work/mise.linux.toml`)に分ける。

### 2. 初回構築(init.sh)と mise 本体

`bootstrap/init.sh`(`curl -fsSL https://raw.githubusercontent.com/kukv/dotfiles/main/bootstrap/init.sh | sh -s -- --env wsl,work [--branch <b>]`)。
**本人ユーザーで実行**し、必要箇所のみ sudo を使う。役割は mise bootstrap が動ける状態を作ることだけ。

| 処理 | Linux | Mac |
|---|---|---|
| 前提 | sudoers NOPASSWD 設定(定期実行の sudo 用、初回のみパスワード入力)、`apt install git curl` | Xcode CLT 確認、Homebrew 導入 |
| mise 導入 | `curl https://mise.run \| sh` → `~/.local/bin/mise` | `brew install mise` |
| 設定 | `~/.config/mise/miserc.local.toml` に `env` を書く。`~/.local/etc/bootstrap.env` を空・0600 で作成 | 同左 |
| 実行 | `mise bootstrap --from https://github.com/kukv/dotfiles.git?ref=<branch> --prompt-vars` | 同左 |

- **mise の更新:** Mac は `mise.macos.toml` に `brew:mise` を宣言し brew で更新。Linux は定期実行ラッパーで `mise self-update --yes`。
- **Linux の Homebrew は廃止する**(用途が mise / chezmoi 導入のみだったため)。
- **chezmoi** は hook 内で `mise exec aqua:twpayne/chezmoi -- chezmoi …` として取得・実行する(`tools` ステップより先に hook が走るため、`[tools]` には置かない)。

### 3. Ansible タスクの移し先

| 元 | 移し先 | 方法 |
|---|---|---|
| os_base: 基本 apt(acl, apt-transport-https, bzip2, ca-certificates, curl, dnsutils, gnupg, lsb-release, software-properties-common, sshpass, tree, unzip, zip) | `mise.linux.toml` | `"apt:…"` |
| os_base: language-pack-ja / manpages-ja / manpages-ja-dev、`locale-gen ja_JP.UTF-8`、`/etc/default/locale` の `LANG` | `mise.linux.toml` | apt + post-packages hook スクリプト ※ |
| os_base: TZ Asia/Tokyo | `mise.linux.toml` | hook(`timedatectl set-timezone`)※ |
| os_base: resolved.conf の DNS(8.8.8.8 1.1.1.1 / fallback 8.8.4.4 1.0.0.1)+ restart | `mise.linux.toml` | `[bootstrap.files]` で `/etc/systemd/resolved.conf.d/dns.conf`、restart は hook ※ |
| os_base: zsh 導入 + chsh | `mise.linux.toml` | `apt:zsh` + `[bootstrap.user] login_shell` |
| os_base: Linux Homebrew + gcc/cmake | 廃止 | — |
| os_base(WSL): `/etc/wsl.conf`(systemd=true / generateResolvConf=false / hostname=wsl2 / automount options) | `mise.wsl.toml` | `[bootstrap.files]` |
| os_base(WSL): `/etc/resolv.conf` → `../run/systemd/resolve/stub-resolv.conf` | `mise.wsl.toml` | hook(`[bootstrap.files]` は symlink を作れないため) |
| os_base(WSL): wslu(Ubuntu < 26.04 のみ) | `mise.wsl.toml` | hook でバージョン判定 ※ |
| os_base(Mac): `brew upgrade --formula`(sudo を要する cask は除外) | `mise.macos.toml` | post-packages hook(`packages upgrade` は cask も対象にし sudo で落ちる恐れ ※) |
| packages: Ruby ビルド依存、ARM クロス toolchain | `mise.linux.toml` | apt |
| packages(Mac): tap `cirruslabs/cli` + `brew trust` | `mise.macos.toml` | hook(`brew tap` + `brew trust`。mise の brew manager は tap 宣言なしで formula を扱えるが、手動導入の tart を `brew upgrade` するため tap と trust は維持)※ |
| packages(Mac): formulae / casks / mas | `mise.macos.toml` | `brew:` / `brew-cask:` / `mas:`(sudo 必須 cask は従来どおり手動) |
| packages: Claude Code CLI | `mise.toml` | `bootstrap` task(`which claude` で冪等化) |
| tools: chezmoi data 注入 + `chezmoi update --force` | `mise.toml` | pre-tools hook(§4) |
| tools: corepack disable、herdr plugins、Claude skills | `mise.toml` | `bootstrap` task |
| tools: `mise install`(token 付き) | bootstrap `tools` ステップ | token は環境変数(§4) |
| scheduler | §5 | — |

※ = mise の宣言だけで表現できるかを実装の最初に実機で確認する。不可なら冪等なシェルスクリプトを hook から呼ぶ。

### 4. vars・秘密情報・chezmoi 連携

```toml
# mise.toml
[vars.git_name]
prompt = "Git user.name"
default = ""   # required は使わない(未回答でも他の mise コマンドを動かすため)。空なら chezmoi-apply.sh が mise vars prompt を案内して exit 1
[vars.git_email]
prompt = "Git user.email"
default = ""   # required は使わない(未回答でも他の mise コマンドを動かすため)。空なら chezmoi-apply.sh が mise vars prompt を案内して exit 1
[vars.use_1password]
default = "true"
[vars.git_signing_key_file]
default = ""   # 空なら chezmoi data に書かず、テンプレート側の既定値(<homeDir>/.ssh/git_signing_key.pub)を使う

# mise.work.toml
[vars]
use_1password = "false"
```

- prompt の答えは `$MISE_STATE_DIR/vars.toml`(マシンローカル)に保存される。聞くのは `--prompt-vars` / `mise vars prompt` のときだけ。
- var の優先順位: 環境変数 > config ファイルの値 > 保存済みの答え > default。`use_1password` は module で決まるので prompt を付けない。
- **chezmoi 連携:** pre-tools hook で(`[dotfiles]` を宣言しないので dotfiles ステップの hook が走るか不確実なこと、chezmoi が配置する `~/.config/mise/config.toml` を tools ステップより前に置く必要があることから pre-tools を使う) `{{ config_root }}/bootstrap/chezmoi-apply.sh` を呼ぶ。
  1. vars から `~/.config/chezmoi/chezmoi.toml`(0600)を生成する。`[data]` に git_name / git_email / use_1password / git_signing_key_file を書き、`sourceDir` は bootstrap チェックアウト(`$MISE_DATA_DIR/bootstrap-repo`、`.chezmoiroot` により `home/` が解釈される)にする。
  2. `chezmoi apply --force` を実行する。
- `~/.local/share/chezmoi` の別チェックアウトは廃止する。bootstrap チェックアウトは直接編集しない(編集は開発用 clone → push → `--update`)。
  チェックアウトに未コミット変更があると `--update` の fast-forward が失敗し得る(現行の `--autostash` より厳しい。挙動は実装時に確認)。
- **秘密情報:** `~/.local/etc/bootstrap.env`(0600)に `MISE_GITHUB_TOKEN` / `HOMEBREW_GITHUB_API_TOKEN` を置き、定期実行ラッパーと `update_os` が source する。
  テンプレートで使う秘密情報が無いので `[bootstrap.secrets]` は使わない。
- `provisioning_schedule` は廃止し、週次で固定する。

### 5. 定期実行

`bootstrap/scheduled-run.sh`:

```sh
set -a; [ -f ~/.local/etc/bootstrap.env ] && . ~/.local/etc/bootstrap.env; set +a
[ "$(uname)" = Linux ] && mise self-update --yes
mise bootstrap --from https://github.com/kukv/dotfiles.git --update --yes
```

- **Linux:** `[bootstrap.linux.systemd.units]` で user の `mise-bootstrap.service` + `.timer`(`OnCalendar=weekly`)。
  post-user hook で `loginctl enable-linger`(冪等)。ログは journald(`journalctl --user -u mise-bootstrap`)。
- **Mac:** `[bootstrap.macos.launchd.agents]` で `com.kukv.mise-bootstrap`(日曜 21:00)。
  ログは `~/.local/log/mise-bootstrap/` に日付別ファイル。ローテーションはラッパー末尾の `find … -mtime +90 -delete` とし、専用 agent は廃止する。
- **`update_os` alias:** Linux は `systemctl --user start mise-bootstrap.service`、Mac はラッパーを直接実行する。
- `--from` は既存チェックアウトの ref を動かさない(clone したときの `?ref=` に固定される)。
- 失敗時の通知は現行同様に入れない。

### 6. 移行手順

順番: 個人 WSL → Mac → 会社 WSL。**3 台すべてを `?ref=migration` で移行してから main にマージする**(未移行マシンは Ansible が main を適用し続けるため、移行中に main を壊さない)。

各マシンで以下を行う。
1. 移行前の `~/.gitconfig` `~/.ssh/config` `~/.zshrc` `~/.zprofile` `~/.config/mise/config.toml` を保存する。
2. 旧定期実行を停止・削除する。Linux: `os-setup.timer` / `.service`。Mac: `com.kukv.os-setup` とログローテーション agent、`~/.local/bin/os-setup-pull.sh`。
3. extra_vars / os-setup.env の秘密情報を `~/.local/etc/bootstrap.env` へ移す。
4. 既存の `~/.config/chezmoi/chezmoi.toml` の値を `mise vars git_name=… git_email=…` で保存し、`miserc.local.toml` に `env` を書く。
5. (Linux)mise.run で mise を入れ直してから linuxbrew をアンインストールする。`dot_zprofile.tmpl` の linuxbrew 行は migration ブランチで削除する(main は全台移行まで変更しないため、未移行マシンには影響しない)。
6. `mise bootstrap --from …?ref=migration` を `--dry-run` → `plan` で確認してから適用する。
7. 旧 `~/.local/share/chezmoi` を削除する。

3 台完了後: migration を main へマージし、各マシンのチェックアウトを clone し直して main を追うようにする。
os-setup は README に移転先を書いてアーカイブする(アーカイブ実施前にユーザー確認)。

### 7. 検証と CI

**成功条件:**
- 各マシンで `mise bootstrap status` が全項目一致している。
- 各マシンで `chezmoi diff` が空。
- 手順 1 の保存ファイルとの差分が意図したもの(`update_os`、zprofile)だけ。
- timer / agent を手動で起動して成功する。
- Docker の素の Ubuntu 26.04(systemd を PID 1 にしたコンテナ、`tests/docker/`)で、init.sh からゼロ構築できる。
- テストと動作確認は原則このコンテナで行い、実機を汚さない。コンテナで確認できない項目(resolv.conf の symlink、WSL の interop と再起動後の挙動)は個人 WSL の移行時に確認する。
- Mac の動作確認は別計画で行う(本計画では macos CI runner の `plan` まで)。

**最初に実機で確認する項目:**
1. `--from` プロジェクトにグローバル `miserc.local.toml` の `env` が効くか(不可なら `-E` を明示する)。
2. `auto_env` を `.miserc.toml` で有効化できるか。
3. 初回実行で、hook により chezmoi が配置した `~/.config/mise/config.toml` の tools が同じ実行内で入るか(不可なら `bootstrap` task で `mise install`)。
4. §3 の ※ 項目。

**CI(dotfiles):** 既存の chezmoi ジョブは維持する。ubuntu / macos runner で env の組み合わせ(なし / `wsl` / `wsl,work`)ごとに `mise bootstrap plan` を実行するジョブを追加する(実適用はしない)。

## 将来フェーズ(今回は実施しない)

### chezmoi → mise `[dotfiles]`

| chezmoi | mise |
|---|---|
| `dot_*.tmpl` + `.chezmoi.os` 分岐 | `[dotfiles]` `mode = "template"`(Tera)+ platform ファイル |
| kernel 文字列による WSL 判定 | `wsl` module |
| data(`use_1password` 等) | vars(本フェーズで移行済み) |
| `private_`(0600) | `permissions` |
| `create_`(初回のみ生成) | `line` 編集 または hook |
| `.chezmoiignore` | エントリを platform ファイル / module に振り分け |
| `.chezmoiexternal` | `[bootstrap.repos]` + renovate customManager regex(下記 oh-my-zsh 参照。案 A で決定済み) |
| `.claude/settings.json` 等の `--force` 上書き | `merge = true` / `merge = "missing"` |
| CI の chezmoi ジョブ | `mise dot diff` ベースに置換 |

### oh-my-zsh

**決定: 案 A(oh-my-zsh を継続)。chezmoi 撤去と同時に、取得方法を `.chezmoiexternal` から `[bootstrap.repos]` へ切り替える。**
本フェーズでは `.chezmoiexternal` のまま変更しない。

`[bootstrap.repos]` は git clone 専用で、archive 取得と submodule 指定の機能が無い。そのため切り替え時に以下を行う。

- **zsh-* プラグイン:** タグの tarball をやめ、`url = "https://github.com/<owner>/<repo>.git", ref = "<tag>"` で clone する。
  renovate の customManager regex を `url = ".../(?<depName>[^/]+/[^/.]+)\.git", ref = "(?<currentValue>[^"]+)"` 形式に書き換える(datasource は `github-tags`)。
- **oh-my-zsh 本体:** `ref` を付けず、`mise bootstrap --update` で fast-forward する(現行の master を週次更新する運用と同等)。
- **alien テーマ:** `ref` はタグで固定し、submodule は post-repos hook で `git submodule update --init` を実行する。
- **要検証:** clone を `~/.oh-my-zsh/custom/…` の中に入れ子にするため、oh-my-zsh 側の `.gitignore` が `custom/` 配下を無視していないと、untracked 扱いで apply が止まる可能性がある。
- **取得方式の変化:** tarball から shallow ではない git clone に変わる。

**案 A で問題が出た場合の代替案:**

| 案 | 評価 |
|---|---|
| B. sheldon | mise `[tools]` で導入(registry: `aqua:rossmacarthur/sheldon`)。プラグインとタグを `plugins.toml` で宣言し、renovate regex で追従する。oh-my-zsh の `plugins/git` だけ読み込み、alien は単体で読み込む(alien の `zsh-async` submodule を sheldon 側で解決できるか要検証) |
| C. B + starship | プロンプトを starship に置き換える(mise registry にあり、renovate の mise manager で追従)。見た目が変わる |

## 検証結果(Task 1 スパイク、mise 2026.10.9)

| # | 確認事項 | 結果 | 採用した方式 |
|---|---|---|---|
| Q1 | `.miserc.toml` の `auto_env` で platform ファイルが読まれる | 読まれる。`mise vars probe_platform` が `linux`(`mise.linux.toml`)。 | `.miserc.toml` に `auto_env = true`。`MISE_AUTO_ENV` の export は不要 |
| Q2 | グローバル `miserc.local.toml` の `env` がプロジェクト module を選ぶ | 選ぶ。`env = ["wsl"]` で `probe_module` が `wsl`(`mise.wsl.toml`)になり、platform ファイルも併せて読まれる。 | `~/.config/mise/miserc.local.toml` の `env`。`-E` 明示は不要 |
| Q3 | hook で `vars.*` / `config_root` が展開される。pre-dotfiles hook の有無 | 展開される(`vars=base root=/tmp/spike`)。`[dotfiles]` 未宣言でも pre-dotfiles hook は実行される(`--only dotfiles,tools` の dry-run で表示)。 | pre-tools hook を使う |
| Q4 | 同名の環境変数で var を上書きできる(変数名の形式) | 上書きできる。`probe_base=ci mise vars probe_base` が `ci`。`MISE_VAR_probe_base=ci` は効かない(`base` のまま)。 | var 名そのままの環境変数(`<name>=<value>`) |
| Q5 | hook で配置した設定の tools が同じ実行で入る | 入る。post-packages hook が置いた `mise.local.toml` の `jq` が、同じ `mise bootstrap --only packages,tools` の tools ステップで install された。 | 先頭での `mise install` は不要 |
| Q6 | `--from` チェックアウトで trust を求められない | bootstrap 実行中は求められない(未 trust のままでも hook 展開・tools まで進む)。ただし実行後も `mise trust --show` は untrusted で、そのチェックアウトで素の `mise` コマンドを実行すると "not trusted" エラーになる。ref 付き `?ref=main` は `git clone` の後に `git checkout main --` で実行される。`--from` の URL とチェックアウトの origin は文字列一致が必要(`/tmp/x.git` と `file:///tmp/x.git` は不一致でエラー)。 | bootstrap 後に素の mise を使うなら `mise trust <checkout>` を挟む。origin の表記は `--from` と揃える |
| Q7 | dirty なチェックアウトで `--update` が止まる | 一律には止まらない。`git pull` の fast-forward が dirty なファイルと衝突しない場合は成功(変更は保持)、同じファイルが上流で変わっていると git がエラーで中断し `bootstrap from repository failed`(終了コード 1)。`--update` なしでは dirty でも問題なく進む。`--dry-run --update` は fast-forward しない。 | 運用で回避(チェックアウトを dirty にしない)。コード対応なし |

### Task 11 E2E(Docker 素の Ubuntu、`init.sh --env wsl,work --branch migration`、HEAD a3b7772)

結果: **不合格(プロダクトのバグ 1 件)**。init.sh は exit 0(約 7 分)だが、初回実行で Linux 固有の宣言が適用されなかった。

- 通った: e2e コンテナは mise / git 無しで起動。init.sh は exit 0。`chezmoi diff` は空(`diff-exit=0`)。gitconfig に `allowedSignersFile`(`op-ssh-sign` 無し)。`use_1password` は `false`(mise.work.toml)。tools 77 件は全て installed。
- 失敗(バグ): `--from` 経由の初回実行(cwd が `~`)では、チェックアウト内の `.miserc.toml`(`auto_env = true`)が読まれず、`miserc.local.toml` の `env = ["wsl","work"]` だけが効く。その結果 `mise.linux.toml` が読まれず、apt packages 27 件・`/etc/systemd/resolved.conf.d/dns.conf`・systemd-resolved・linux-base.sh(locale/timezone/linger)・systemd user unit(timer)・login shell(`/usr/bin/zsh`)が全て未適用のまま終了した。`--dry-run` で再現: cwd `~` の `mise bootstrap --from ...` は linux-base.sh を含まず、チェックアウト内で実行すると含む。spike Q1/Q2 はチェックアウト内で確認していたため見落としていた。`scheduled-run.sh` も同じ cwd 依存の呼び出し(`mise bootstrap --from ... --update`)なので同様に影響する可能性がある。
- 切り分け: チェックアウトで `mise bootstrap --yes` を再実行すると全て適用され、`status` は全項目 installed / unchanged / set、timer も有効になった。`systemctl --user start dev.mise.mise-bootstrap.service` は `Result=success`、`ExecMainStatus=0`。
- 環境由来: init 中に chezmoi のバージョン取得が github API で 3 秒タイムアウトの WARN(無害)。Step 3 の `mise bootstrap status` は cwd がチェックアウトでないと tools しか表示されない(同じ原因)。
- 未修正。修正案は `init.sh` の miserc.local.toml に `auto_env` 相当(`env` に `linux` を含める等)か、`mise bootstrap` をチェックアウトへ cd して実行すること。コントローラの判断待ち。
