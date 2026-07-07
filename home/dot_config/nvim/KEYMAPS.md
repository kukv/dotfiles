# Neovim キーマップ / オプション メモ

LazyVim ベース。leader キーは `<Space>`。標準キーマップは
LazyVim 既定（https://lazyvim.github.io/keymaps）に従う。ここには
この構成で **追加/意識すべきもの** と設定状況をまとめる。

## 設定状況

- `lua/config/keymaps.lua` … 未カスタム（LazyVim 既定のまま）
- `lua/config/options.lua` … 未カスタム（LazyVim 既定のまま）
- `lua/config/autocmds.lua` … 未カスタム（LazyVim 既定のまま）
- カスタムは `lua/plugins/*.lua` のプラグイン定義側で付与している。

## ファイル/UI

| キー | 動作 | 由来 |
|---|---|---|
| `<leader>e` | ファイルツリー（neo-tree）トグル | LazyVim 標準 |
| `<C-t>` | フロート端末トグル | toggleterm.lua |

## Git

| キー | 動作 | 由来 |
|---|---|---|
| `<leader>gg` | lazygit | LazyVim 標準（Snacks） |
| `<leader>gh*` | hunk ステージ/移動など | gitsigns（LazyVim 標準） |
| `<leader>gd` | Diffview を開く | diffview.lua |
| `<leader>gV` | ファイル履歴（Diffview） | diffview.lua |

## Java / Spring Boot（javaファイルで有効）

| キー | 動作 | 由来 |
|---|---|---|
| `<leader>Jr` | Spring Boot プロジェクト実行 | springboot.lua |
| `<leader>Jc` | Java クラス生成 | springboot.lua |
| `<leader>Ji` | Java インターフェース生成 | springboot.lua |
| `<leader>Je` | Java enum 生成 | springboot.lua |

## その他プラグイン（キーマップ無し／自動動作）

- neoscroll.nvim … スムーススクロール（`<C-d>`/`<C-u>` 等が滑らかになる）
- hlchunk.nvim … インデント/チャンクのハイライト
- render-markdown.nvim … Markdown をバッファ内で装飾表示（`lang.markdown` extra）

## 言語サポート（LazyVim extras）

Java / Kotlin / TypeScript(React,JS) / Python / Ruby / Rust / Terraform /
YAML(Ansible,GH Actions) / JSON / Markdown / Docker を有効化。
HTML/CSS/emmet は `lua/plugins/web.lua` で追加。
LSP は各ファイルを開くと mason 経由で自動導入・attach される。
