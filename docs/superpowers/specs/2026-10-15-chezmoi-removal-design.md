# chezmoi 撤去(→ mise `[dotfiles]`)と oh-my-zsh → sheldon 移行 設計

- 日付: 2026-10-15
- 前提 spec: [2026-10-15-mise-bootstrap-migration-design.md](2026-10-15-mise-bootstrap-migration-design.md)(os-setup → mise bootstrap)
- 対象マシン: 個人 WSL / 会社 WSL / Mac

## 目的と範囲

**目的:** chezmoi をやめる。dotfiles の配置を mise bootstrap の `[dotfiles]` に移し、chezmoi の externals で取得していた
oh-my-zsh 一式を sheldon に置き換える。

**範囲:**
- chezmoi のソース・設定・hook・CI・renovate 設定の撤去と、mise `[dotfiles]` への置き換え
- oh-my-zsh(本体 + プラグイン + alien テーマ)の取得・読み込みを sheldon に置き換え
- テスト、CI、手順書、README の更新

**範囲外:** starship 等へのプロンプトの置き換え(alien は継続)。

**前提 spec からの変更:** 前提 spec の「将来フェーズ」にある oh-my-zsh の「決定: 案 A(継続)」は、決定理由が記録されておらず、
本 spec で撤回して sheldon(案 B)に変更する。

## 決定事項

| 論点 | 決定 | 理由 |
|---|---|---|
| 配置方式 | すべて copy / template(symlink は使わない) | アプリが書き込んでも bootstrap チェックアウトが dirty にならず、週次の `--update` が止まらない(前提 spec Q7)。chezmoi と同じ実ファイル配置 |
| アプリが書き換える設定(`~/.claude/settings.json`、`~/.codex/config.toml`) | 丸ごと上書き(copy) | 現状(`chezmoi apply --force`)と同じ挙動 |
| WSL 判定 | wsl module の var `is_wsl`(既定 `"false"`、`mise.wsl.toml` で `"true"`) | `use_1password` と同じ仕組み。CI で `-E wsl` により WSL 分岐を検証できる |
| `~/.zshrc.local` / `~/.zprofile.local`(chezmoi の `create_`) | post-dotfiles hook で「無ければ作る」 | `create_` と同じ挙動で、既存ファイルに触れない |
| ソースの配置 | `home/` 直下の `.` 始まりの名前だけ `dot_` に置き換え(ディレクトリの中身はアプリ側の名前のまま)、テンプレートは `.tera` を付ける。`**/.ssh/**` 等の Claude の deny ルールや、mise / Claude Code が `home/.config` `home/.claude` を設定として拾うことを避ける。配置先との対応も見て分かる |
| zsh 構成 | sheldon。oh-my-zsh は使わず、必要な挙動(補完・キーバインド・履歴・ディレクトリ・見た目、git エイリアス 18 個)は zshrc に自分で書く | ユーザー決定(2026-10-16。当初は lib と git プラグインを sheldon で読む案だったが、oh-my-zsh 自体を廃止することにした) |
| プラグインの版管理 | 全部固定 + renovate(zsh-users / alien は tag) | 全台が同じ版になり、壊れたら PR 単位で戻せる |
| 展開順 | 2 段階。① Mac / 会社 WSL を今の main(chezmoi あり)で os-setup から移行 → ② 本ブランチで 3 台を移行してからマージ | 変更を 1 つずつ入れ、失敗時の切り分けと切り戻しを簡単にする |

## 現状の棚卸し(chezmoi が担っているもの)

`chezmoi managed`(個人 WSL、2026-10-15)と、リポジトリ内の参照を全件確認した結果。

### 配置しているファイル

| 配置先 | 現ソース | 備考 |
|---|---|---|
| `~/.zshrc` | `home/dot_zshrc.tmpl` | OS / WSL / use_1password で分岐 |
| `~/.zprofile` | `home/dot_zprofile.tmpl` | OS 分岐 |
| `~/.gitconfig` | `home/dot_gitconfig.tmpl` | OS / WSL / use_1password / git_signing_key_file |
| `~/.zshrc.local` / `~/.zprofile.local` | `home/create_dot_*.local` | 初回のみ生成 |
| `~/.ssh/config` | `home/private_dot_ssh/private_config.tmpl` | macOS のみ(`.chezmoiignore`)、0600 |
| `~/.ssh/allowed_signers` | `home/private_dot_ssh/allowed_signers.tmpl` | 空なら削除。`~/.ssh` は 0700(`private_`) |
| `~/.claude/{CLAUDE.md,settings.json,scripts/statusline.py,skills/hunk-review/*}` | `home/dot_claude/` | `statusline.py` と `ensure-hunk-pane.sh` は実行可能(`executable_`) |
| `~/.codex/config.toml` | `home/dot_codex/config.toml` | |
| `~/.config/{git/ignore,herdr/config.toml,mise/config.toml}` | `home/dot_config/` | |
| `~/.config/nvim/**` | `home/dot_config/nvim/` | **`.gitignore` と `.neoconf.json` は配置していない**(chezmoi は `.` 始まりのソースを無視するため) |
| `~/Library/Application Support/iTerm2/DynamicProfiles/default_profile.json` | `home/Library/…` | macOS のみ |
| `~/.oh-my-zsh/**` | `home/.chezmoiexternal.toml` | 本体(master、168h ごと)、alien(tag + submodule)、zsh-users 4 つ(tag の tarball) |

### chezmoi を参照している箇所

`.chezmoiroot`、`home/.chezmoi*`、`bootstrap/chezmoi-apply.sh`、`mise.toml`(pre-tools hook とコメント)、
`home/dot_config/mise/config.toml`(`chezmoi = "latest"`)、`renovate.json`(2 件)、`.github/workflows/ci.yaml`(`apply` ジョブ、
`chezmoi-apply.sh` のテスト)、`tests/bootstrap/chezmoi-apply.test.sh`、`bootstrap/init.sh` と `bootstrap/post-tools.sh` のコメント、
各テンプレートのヘッダコメント、README、`docs/setup/{wsl-new,wsl-migration,mac}.md`。

## 設計

### 1. ファイル配置(mise `[dotfiles]`)

`git mv` で `home/` を並べ替える(直下の `.` を `dot_` に)。

```
home/
├── dot_zshrc.tera
├── dot_zprofile.tera
├── dot_gitconfig.tera
├── dot_ssh/{config.tera,allowed_signers.tera}
├── dot_claude/{CLAUDE.md,settings.json,scripts/statusline.py,skills/hunk-review/}
├── dot_codex/config.toml
├── dot_config/{git/ignore,herdr/config.toml,mise/config.toml,nvim/,sheldon/plugins.toml}
└── Library/Application Support/iTerm2/DynamicProfiles/default_profile.json
```

`mise.toml` の `[dotfiles]`:

| 配置先 | 方式 |
|---|---|
| `~/.zshrc` `~/.zprofile` `~/.gitconfig` | `mode = "template"` |
| `~/.ssh/config` | template、`permissions = "0600"`、`variants = [{ os = "macos" }]` |
| `~/.ssh/allowed_signers` | template、`remove_empty = true` |
| `~/.ssh` | `permissions = "0700"` のみ |
| `~/.claude` | ディレクトリを copy(追加のみで、既存の他ファイルは残る。settings.json も丸ごと上書き) |
| `~/.codex/config.toml`、`~/.config/git/ignore`、`~/.config/herdr/config.toml`、`~/.config/mise/config.toml`、`~/.config/sheldon/plugins.toml` | copy |
| `~/.config/nvim` | ディレクトリを copy、`exclude = ["/.gitignore", "/.neoconf.json"]` |
| iTerm2 `default_profile.json` | copy、`variants = [{ os = "macos" }]` |

- 実行ビットは git の mode で持たせる(copy で保持されることを確認済み)。`ensure-hunk-pane.sh` を 100755 にする。
- `~/.config/mise/config.toml` は dotfiles ステップ(tools より前)で配置され、mise が設定を読み直す。pre-tools hook で置く必要は無くなる。
- テンプレートは Go template → Tera:
  - `.chezmoi.os` → `os()`(`linux` / `macos`)
  - `.chezmoi.homeDir` → `env.HOME`
  - カーネル文字列での WSL 判定 → `vars.is_wsl == "true"`
  - `hasKey . "use_1password"` の分岐 → 不要(vars は常に定義される)。`vars.use_1password == "true"` と文字列で比較する
  - `git_signing_key_file` は既定値が `""` なので、`== ""` で分岐して `env.HOME ~ "/.ssh/git_signing_key.pub"` に倒す
  - `allowed_signers` は `is file` テストと `read_file()` を使う
  - ヘッダの `# Managed by chezmoi — edit with: chezmoi edit …` は mise 向けの文言に変える
- vars: `[vars.is_wsl] default = "false"`(`mise.toml`)、`is_wsl = "true"`(`mise.wsl.toml`)。
- hooks:
  - pre-dotfiles: `git_name` / `git_email` が空なら `mise vars prompt` を案内して exit 1(`chezmoi-apply.sh` のチェックの代わり)
  - post-dotfiles: `~/.zshrc.local` と `~/.zprofile.local` が無ければヘッダコメント付きで作る
- 削除: `.chezmoiroot`、`home/.chezmoi.toml.tmpl`、`home/.chezmoiexternal.toml`、`home/.chezmoiignore`、`home/create_*`、
  `bootstrap/chezmoi-apply.sh`、`mise.toml` の pre-tools hook、`home/dot_config/mise/config.toml` の `chezmoi = "latest"`。

### 2. zsh(oh-my-zsh → sheldon)

- 導入: `home/dot_config/mise/config.toml` の `[tools]` に `sheldon = "latest"`(registry: `aqua:rossmacarthur/sheldon`)。
- `~/.config/sheldon/plugins.toml`(この順に読み込む):

| plugin | 取得元 | 固定 | 読み込み |
|---|---|---|---|
| zsh-completions | `zsh-users/zsh-completions` | tag `0.36.0` | `apply = ["fpath"]`(`src`) |
| compinit | inline | — | `autoload -Uz compinit && compinit` |
| alien | `eendroroy/alien` | tag `2.1.2` | `use = ["alien.zsh"]`(submodule は sheldon が再帰的に取得) |
| zsh-autosuggestions | `zsh-users/zsh-autosuggestions` | tag `v0.7.1` | source |
| zsh-history-substring-search | `zsh-users/zsh-history-substring-search` | tag `v1.1.0` | source |
| zsh-syntax-highlighting | `zsh-users/zsh-syntax-highlighting` | tag `0.8.0` | source(最後に読む決まり) |

- zshrc:
  - 削除: `ZSH` / `ZSH_THEME` / `plugins=()` / `source $ZSH/oh-my-zsh.sh`、手書きの `fpath+=…` と `compinit`
  - `eval "$(mise activate zsh)"` を `eval "$(sheldon source)"` より前に移す(sheldon を mise で入れるため)
  - `ALIEN_*` の export は sheldon より前に置く
  - **oh-my-zsh は一切使わない(2026-10-16 ユーザー決定)。** `lib/*.zsh` が提供していた挙動のうち、次を zshrc に自分で書く:
    - 補完: `menu select`、大文字小文字を区別しない / 部分一致の `matcher-list`、候補の色、キャッシュ(`~/.cache/zsh`)、`bashcompinit`、
      `auto_menu` / `complete_in_word` / `always_to_end`
    - キーバインド: `bindkey -e`、↑↓ に `up/down-line-or-beginning-search`、Home / End / Delete、Ctrl+←→、Shift+Tab(`reverse-menu-complete`)、
      Ctrl+X Ctrl+E(`edit-command-line`)
    - 履歴: `share_history`、`hist_ignore_dups`、`hist_ignore_space`、`hist_verify`、`hist_expire_dups_first`
    - ディレクトリ: `auto_cd`、`auto_pushd`、`pushd_ignore_dups`、`pushdminus`、`...`〜`......` のグローバルエイリアス、`-`、`1`〜`9`、`md`、`rd`
    - 見た目・その他: `ls` / `grep` の色、ターミナルのタイトル更新、`url-quote-magic` / `bracketed-paste-magic`、`interactive_comments`、`multios`、`long_list_jobs`
    - git エイリアス(oh-my-zsh と同じ定義)18 個: `g` `gst` `ga` `gaa` `gc` `gd` `gds` `gb` `gco` `gsw` `gswc` `gf` `gl` `gp` `grb` `glog` `gsta`(`git stash push`) `gstp`
  - 選ばなかったもの(`omz` コマンド、残りの git エイリアス、`_`、`lsa`、`afind` など)は無くなる。zshrc が上書きしていた `ll` / `la` / `l` と Ctrl+R(peco)は従来どおり
- 取得のタイミング: bootstrap task(`bootstrap/post-tools.sh`)で `sheldon lock` を実行し、シェル起動時にネットワークへ取りに行かないようにする。
- renovate: `home/dot_config/sheldon/plugins.toml` を regex で追従する。zsh-users / alien は `github-tags`。`.chezmoiexternal` 用と chezmoi 本体用の customManager は削除する。
- `bootstrap/post-tools.sh` の hunk-review に関するコメントを、chezmoi から mise `[dotfiles]` に直す。

### 3. テストと検証

**自動テスト(CI と手元の両方で実行):**
- `tests/bootstrap/chezmoi-apply.test.sh` を削除し、`tests/bootstrap/dotfiles.test.sh` を追加する。一時 HOME で
  `mise -E <env> dot apply` を、組み合わせ(Linux: なし / `wsl` / `wsl,work`、macOS: なし)ごとに実行する。
  - 現 CI の assert をすべて移植する: テンプレートのレンダリング、WSL 用の設定が素の Linux に混入しない、macOS の署名プログラムと ssh config、
    ローカル鍵マシンの `allowedSignersFile` と `allowed_signers` の生成(1Password の署名プログラムが混入しない)、linuxbrew / os-setup の残骸が無い。
  - 追加: `-E wsl` で `ssh.exe` / `op-ssh-sign-wsl.exe` が入る。apply 直後の `mise dot status --missing` が exit 0。
    nvim の除外ファイルが配置されていない。実行ビットが付いている。`git_name` が空だと bootstrap が dotfiles ステップより前で失敗する。
- zsh のスモークテスト: 一時 HOME で `sheldon lock` → `zsh -ic` で起動し、stderr が空であること、`gst` / `gl` / `gsw` エイリアス、`share_history`、`auto_cd`、emacs モード、↑ の前方一致検索、プロンプトが設定されていること(ubuntu runner には zsh を入れる)。
- `tests/bootstrap/plan.sh`: `-E wsl` で `is_wsl` が `"true"` になる assert を追加する。
- CI: `apply` ジョブを削除し、`bootstrap` ジョブで上記を ubuntu / macOS の両方で実行する。

**一度だけ行う同等性チェック:** 今の main を chezmoi でレンダリングした結果と、新テンプレートを mise でレンダリングした結果を
Linux の 3 パターンで diff し、差分がヘッダコメント(と zshrc の sheldon 化)だけであることを確認する。

**Docker e2e(`tests/docker`):**
1. 新規構築: `init.sh --branch <作業ブランチ>` でゼロから構築し、`bootstrap status`・`mise dot status --missing`・zsh スモークがすべて通る。
2. 移行の再現: 今の main(chezmoi あり)で構築 → チェックアウトを作業ブランチに切り替え → `scheduled-run.sh` で適用。
   - chezmoi が書いた既存ファイルが衝突せずに上書きされる(`--force-dotfiles` が要らない)
   - 結果のファイルが 1. と一致する
   - `~/.oh-my-zsh` に触れていない
   - 切り戻し手順(チェックアウトを main に戻して再適用)で元の状態に戻る
- e2e では init.sh が GitHub から clone するため、作業ブランチの push が必要(push する時点でユーザーの確認を取る)。

**macOS:** CI の macos runner でレンダリングと `plan` まで確認する。実機での確認は Mac の移行時に行う。

**実装時に最初に確認する未検証事項:**
1. chezmoi が書いた既存ファイルを copy / template が `--force` なしで上書きできるか(e2e 2)。
2. Tera と zsh の記法の衝突(`{#` など)や、空白制御の違い(同等性チェック)。
3. oh-my-zsh 抜きで書き直した補完・キーバインド・履歴・ディレクトリ・見た目の設定が効いているか(zsh スモークと下の検証項目)。
4. `mise activate zsh` の直後に、同じ zshrc 内で sheldon が PATH 上に見えるか。

**zsh の検証項目(Docker の対話シェルで確認):** 起動時にエラーが出ない / alien のプロンプト / `gst` などの git エイリアス /
補完のメニュー選択 / ↑ での前方一致の履歴検索 / 構文ハイライトと自動補完の候補表示 / `..` エイリアス / 起動時間が今と大きく変わらない。

### 4. 展開手順

**マージの条件:** Mac と会社 WSL が今の main(chezmoi あり)のまま os-setup から mise bootstrap に移行し終えていること。
os-setup のマシンが残ったまま main から `.chezmoiroot` を消すと、os-setup の chezmoi がリポジトリのルートをソースとして解釈し、
`~/mise.toml` などを ~ に撒くため。Mac は先に `docs/setup/mac.md` を整備する。本ブランチの開発は並行して進める。

**各マシンの移行**(個人 WSL → 会社 WSL → Mac。手順書 `docs/setup/{wsl,mac}-chezmoi-removal.md` を新規作成):
1. バックアップ: `~/.gitconfig` `~/.zshrc` `~/.zprofile` `~/.ssh/config` `~/.ssh/allowed_signers` `~/.claude/settings.json`
   `~/.codex/config.toml` `~/.config/mise/config.toml`
2. `~/.local/share/dotfiles` で `fetch` → `checkout <作業ブランチ>`(移行期間中の週次実行はこのブランチを追従する)
3. `mise bootstrap plan` と `--dry-run` で差分を確認してから `update_os`
4. 確認: `mise dot status --missing` が exit 0 / バックアップとの diff がヘッダコメントと zshrc の sheldon 化だけ / 新しいシェルで zsh の検証項目
5. 切り戻し: チェックアウトを main に戻して `update_os`。chezmoi の hook が元の dotfiles を書き戻し、`~/.oh-my-zsh` も残っているため元のシェルに戻る。

**3 台とも完了したら:** マージ → 各マシンのチェックアウトを main に戻す → 後片付け:
- `~/.oh-my-zsh`
- `~/.config/chezmoi`(state DB を含む)
- `~/.cache/chezmoi`
- `mise uninstall chezmoi --all`
- 古い `~/.zcompdump*`

**ドキュメント:**
- README: 構成図、編集方法(開発用 clone で編集 → push → `update_os`。手元で試すときは clone 内で `mise dot apply`)、sheldon。
- `docs/setup/wsl-new.md`: 成功条件を `chezmoi diff` から `mise dot status --missing` に変え、`mise trust` を追加する。
- `docs/setup/wsl-migration.md` と `docs/setup/mac.md` の移行の章: マージ時点で os-setup のマシンは残っていないため削除する。
- 前提 spec の「将来フェーズ」に、本 spec へのリンクと「案 A は撤回して sheldon に変更」を追記する。

## 検証結果

実行日: 2026-10-16 / 検証対象: `origin/chezmoi-removal` の HEAD `2f8f7c8`(`91f4011` に main をマージしたもの)/ 環境: `tests/docker`(e2e サービス、Ubuntu 26.04、systemd)

### Step 2: 新規構築 — 合格

- `init.sh --env wsl --branch chezmoi-removal` は exit 0(1 回目は後述のネットワーク失敗、再実行で成功)。`mise vars` は exit 0。
- `mise bootstrap status` は exit 0。dotfiles 12 件が `applied`(`~/.zshrc`、`~/.config/sheldon/plugins.toml` を含む)。
- `mise dot status --missing` は `✓ 11 entries up to date`、`dot-exit=0`。
- `zsh -lic` は終了コード 0、stderr は空。`gst` / `gl` / `gsw` / `md` のエイリアスが定義され、`sharehistory` と `autocd` が有効。
- `dev.mise.mise-bootstrap.service` は `Result=success`、`ExecMainStatus=0`。
- sheldon のプラグイン 5 件(zsh-autosuggestions / zsh-completions / zsh-history-substring-search / zsh-syntax-highlighting / alien)が `~/.local/share/sheldon/repos/github.com` に取得された。

### Step 3: 移行(main → chezmoi-removal) — 合格

- main で構築後に `chezmoi-removal` をチェックアウトして `dev.mise.mise-bootstrap.service` を起動した。`--force-dotfiles` は不要で、衝突は発生しなかった(`~/.zshrc` の `oh-my-zsh.sh` 参照は 1 件から 0 件に変わった)。
- `mise dot status --missing` は `dot-exit=0`。
- `~/.oh-my-zsh` は手つかずのまま残った(ディレクトリ自体の mtime と `oh-my-zsh.sh` の mtime が不変)。
- `~/.gitconfig` / `~/.zshrc` / `~/.zprofile` は新規構築の結果と `diff -r` で一致(`same-as-fresh`)。
- zsh は終了コード 0、stderr は空(下記 1 の再実行後)。

### Step 4: 切り戻し(main に戻す) — 合格

- `service` は `Result=success`、`ExecMainStatus=0`。`~/.zshrc` の `oh-my-zsh.sh` 参照は 1 件に戻った。
- `chezmoi diff` は exit 0。差分はファイルのパーミッション(664 と 644 など、2271 件)のみで、内容の差分はない。
- `zsh -lic "alias gst"` は終了コード 0、stderr は空。

### 見つかった問題

1. **sheldon の並列 clone が github.com への接続拒否で失敗することがある**(コードの不具合ではなく環境起因の可能性が高い)。新規構築の 1 回目と Step 3 の初回 service 起動で、5 件の並列 clone のうち 1 件が `failed to connect to github.com: Connection refused` で失敗し、`post-tools.sh` が exit 2 になった。再実行すると成功した。冪等で、再実行で回復する。失敗直後は未取得のプラグインを `.zshrc` 側の sheldon が clone するため、zsh の stderr に `CLONED` が出る。
2. 手順書の `omz-untouched` 判定(`ls -la ~/.oh-my-zsh | head -3 | diff`)は、3 行目に `..`(= `$HOME`)の mtime を含むため、HOME 直下にファイルが増えると偽の差分になる。`~/.oh-my-zsh` 自身の mtime(`stat`)で比較すること。
3. 切り戻し後の `chezmoi diff` にパーミッションのみの差分(2271 件)が出る。mise 側の配置でファイルのモードが 664 / 775 になっていることが原因とみられる。`chezmoi apply` で戻る。内容は一致しており、`diff-exit=0` の判定は満たす。
