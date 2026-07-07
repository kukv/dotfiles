# Neovim キーマップ / オプション メモ

LazyVim ベース。標準キーマップは LazyVim 既定
（https://lazyvim.github.io/keymaps）に従う。ここにはこの構成で
**追加/意識すべきもの** と設定状況をまとめる。

## 記法（キーの読み方）

Vim/LazyVim のドキュメントは下の記号で書かれる。慣れるまでの対応表:

| 記号 | 意味 | 実際の操作 |
|---|---|---|
| `<leader>` | リーダーキー。この構成では **スペース** | スペースキーを押す |
| `<C-x>` | Ctrl を押しながら `x` | 例: `<C-t>` = **Ctrl + t** |
| `<S-x>` | Shift を押しながら `x` | 例: `<S-h>` = **Shift + h** |
| `<CR>` | Enter（改行） | Enter キー |
| `<Esc>` | Escape | Esc キー |
| 大文字（例 `J`, `V`） | Shift + そのキー | `J` = **Shift + j** |

**連続表記の読み方:** `<leader>gd` は「まとめて1キー」ではなく
**順番に押す**。つまり `スペース → g → d`。
`<leader>` 始まりのキーは、スペースを押すと候補メニュー（which-key）が
出るので、続きのキーを見ながら押せる。

## 設定状況

- `lua/config/keymaps.lua` … 未カスタム（LazyVim 既定のまま）
- `lua/config/options.lua` … 未カスタム（LazyVim 既定のまま）
- `lua/config/autocmds.lua` … 未カスタム（LazyVim 既定のまま）
- カスタムは `lua/plugins/*.lua` のプラグイン定義側で付与している。

## ファイル/UI

| キー（Vim記法） | 押すキー | 動作 | 由来 |
|---|---|---|---|
| `<leader>e` | スペース → e | ファイルツリー（neo-tree）トグル | LazyVim 標準 |
| `<C-t>` | Ctrl + t | フロート端末トグル | toggleterm.lua |

## Git

| キー（Vim記法） | 押すキー | 動作 | 由来 |
|---|---|---|---|
| `<leader>gg` | スペース → g → g | lazygit | LazyVim 標準（Snacks） |
| `<leader>gh…` | スペース → g → h → … | hunk ステージ/移動など | gitsigns（LazyVim 標準） |
| `<leader>gd` | スペース → g → d | Diffview を開く | diffview.lua |
| `<leader>gV` | スペース → g → Shift + v | ファイル履歴（Diffview） | diffview.lua |

## Java / Spring Boot（javaファイルで有効）

| キー（Vim記法） | 押すキー | 動作 | 由来 |
|---|---|---|---|
| `<leader>Jr` | スペース → Shift + j → r | Spring Boot プロジェクト実行 | springboot.lua |
| `<leader>Jc` | スペース → Shift + j → c | Java クラス生成 | springboot.lua |
| `<leader>Ji` | スペース → Shift + j → i | Java インターフェース生成 | springboot.lua |
| `<leader>Je` | スペース → Shift + j → e | Java enum 生成 | springboot.lua |

## その他プラグイン（キーマップ無し／自動動作）

- neoscroll.nvim … スムーススクロール（`<C-d>` = Ctrl+d、`<C-u>` = Ctrl+u
  などのスクロールが滑らかになる）
- hlchunk.nvim … インデント/チャンクのハイライト
- render-markdown.nvim … Markdown をバッファ内で装飾表示（`lang.markdown` extra）

## 言語サポート（LazyVim extras）

Java / Kotlin / TypeScript(React,JS) / Python / Ruby / Rust / Terraform /
YAML(Ansible,GH Actions) / JSON / Markdown / Docker を有効化。
HTML/CSS/emmet は `lua/plugins/web.lua` で追加。
LSP は各ファイルを開くと mason 経由で自動導入・attach される。
