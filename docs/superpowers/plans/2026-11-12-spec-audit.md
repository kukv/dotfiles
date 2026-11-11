# spec-audit スキル Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 仕様・設計資料の網羅性と整合性を点検して報告ファイルを書き出す `/spec-audit` スキルを `home/dot_claude/skills/spec-audit/` に作る。

**Architecture:** スキルは Markdown のみで構成する。SKILL.md に手順を書き、`report-template.md`（報告書の章立て）と `verifier-prompt.md`（検証パス用の指示文）を分ける。実行時は、単一エージェントが Step ごとに中間ファイルを `docs/audit/run-N/` に書き出し、最後に独立したサブエージェントの検証パスを挟む。資料の本文はスクラッチパッドにスナップショットとして保存し、リポジトリには入れない。

**Tech Stack:** Claude Code skills（SKILL.md の frontmatter）、mise の `[dotfiles]`（`~/.claude` は `home/dot_claude` をコピーして配置する）、POSIX sh のテスト。

**Spec:** `docs/superpowers/specs/2026-11-12-spec-audit-design.md`

## Global Constraints

- 配置先: `home/dot_claude/skills/spec-audit/`
- frontmatter には `disable-model-invocation: true` を指定し、`/spec-audit` での手動起動に限る
- 引数: `spec=`（必須）、`req=`、`src=`、`viewpoints=`、`out=`（いずれも任意）。`out` の既定は `docs/audit`
- 出力: 常に `<out>/run-N/`（N は既存の最大番号に 1 を足した値。既存がなければ 1）
- スナップショット: `<スクラッチパッド>/spec-audit/run-N/sources/` に置く。スクラッチパッドがなければ `${TMPDIR:-/tmp}` を使う。リポジトリ内には置かない
- 外部サービスには読み取り専用でアクセスする。外部ソースはレポートに要約で載せる。ローカルファイルはそのまま引用してよい
- URL の配下が50ページを超えるときは、続行するか利用者に確認する
- スキル本文は日本語で書く

## File Structure

| ファイル | 役割 |
|---|---|
| Create `home/dot_claude/skills/spec-audit/SKILL.md` | 起動、引数、出力、実行フロー、全体ルール |
| Create `home/dot_claude/skills/spec-audit/report-template.md` | `coverage-report.md` と中間ファイルの表の書式 |
| Create `home/dot_claude/skills/spec-audit/verifier-prompt.md` | 検証パスのサブエージェントに渡す指示文 |
| Modify `tests/bootstrap/dotfiles.test.sh:40` | 配置確認の1行を追加する |
| スクラッチパッド `spec-audit-fixture/` | 欠陥を仕込んだテスト用の資料（リポジトリには入れない） |

---

### Task 1: テスト用フィクスチャと期待検出リスト（RED の準備）

**Files:**
- Create（スクラッチパッド）: `$SP/spec-audit-fixture/spec/01-overview.md`、`spec/02-detail.md`、`req/2026-09-01-meeting.md`、`src/order.py`、`expected.md`

`$SP` はセッションのスクラッチパッドを指す（`/tmp/claude-1000/-home-tech-dev-ghq-github-com-kukv-dotfiles/53a7686d-b82a-4835-ab4a-36d94d19e5c8/scratchpad`）。

**Interfaces:**
- Produces: フィクスチャのパスと期待欠陥 D1〜D8。Task 5 で照合に使う。

- [ ] **Step 1: `spec/01-overview.md` を作成**

```markdown
# 注文管理システム 仕様書 概要
版: v1.0 / 更新日: 2026-08-15

## アクター
- 顧客: 商品を注文する利用者
- 管理者: 注文を発送する担当者

## 用語
- 顧客: 会員登録を済ませた利用者

## 注文の状態
受付 → 発送済 → 完了。受付の間だけキャンセルでき、キャンセルすると「キャンセル」状態になる。

## ルール
- R1: 購入金額が10,000円以上なら送料無料
- R2: ポイントの有効期限は付与から365日

## ユースケース
### UC1 注文する（顧客）
基本フロー: 顧客が商品を選び、注文を確定すると、注文が「受付」で作成される。
### UC2 発送する（管理者）
基本フロー: 管理者が「受付」の注文を発送し、「発送済」にする。
### UC3 キャンセルする（顧客）
基本フロー: 顧客が「受付」の注文をキャンセルする。
```

- [ ] **Step 2: `spec/02-detail.md` を作成**

```markdown
# 注文管理システム 詳細仕様
版: v1.0 / 更新日: 2026-08-15

## 送料
- 購入金額が8,000円以下の場合、送料は500円

## ポイント
- 会員が注文するとポイントが付与される
- ポイントの有効期限は付与から180日

## 在庫切れ
- 注文時に在庫がない場合、注文は「保留」状態になる

## 問い合わせ
### UC4 問い合わせる（会員）
基本フロー: 会員が問い合わせを送信すると、「問い合わせ履歴」が作成される。
```

- [ ] **Step 3: `req/2026-09-01-meeting.md` を作成**

```markdown
# 定例議事録 2026-09-01

## 決定事項
- 発送済の注文もキャンセルできるようにする（返品扱い）
- 退会機能を追加する
```

- [ ] **Step 4: `src/order.py` を作成**

```python
class Order:
    def __init__(self, amount):
        self.amount = amount
        self.status = "受付"

    def cancel(self):
        if self.status != "受付":
            raise ValueError("受付の間だけキャンセルできる")
        self.status = "キャンセル"

    def apply_coupon(self, rate):
        self.amount = int(self.amount * (1 - rate))
```

- [ ] **Step 5: `expected.md`（期待検出リスト）を作成**

```markdown
| ID | 欠陥 | 合格条件 |
|---|---|---|
| D1 | 用語の揺れ: 顧客（01）と会員（02） | 矛盾一覧の「用語」に載っている |
| D2 | 有効期限 365日（01 R2）と 180日（02） | 矛盾一覧に載り、正誤は「判断不可」で質問リスト行きになっている（同じ版・同じ日付なので根拠がない） |
| D3 | 送料の範囲の隙間 8,001〜9,999円 | 矛盾（範囲の隙間）または漏れとして載っている |
| D4 | 「保留」状態から抜け出せない | 状態遷移表で抜け出せない状態として検出されている |
| D5 | 問い合わせ履歴が作成されるだけで参照されない | CRUD 表の漏れとして検出されている |
| D6 | 議事録（2026-09-01）では発送済もキャンセル可、仕様（v1.0、2026-08-15）は受付のみ | 資料間の矛盾として、日付を根拠に記録されている |
| D7 | 退会機能が議事録にあり、仕様にない | 突き合わせの「要件にあるが仕様にない」に載っている |
| D8 | apply_coupon が実装にあり、仕様にない | 突き合わせの「実装にあるが仕様にない」に載っている |

追加の合格条件:
- 質問リストが ID / 対象要素 / 種別 / 質問 / 重要度 / 判断が必要な理由 の形式になっている
- 推測による補完（例: 保留からの遷移先を勝手に決める）をしていない
- spec/req/src のハッシュが実行前後で一致する
- リポジトリ側（fixture/docs/audit）に sources/ が作られていない
```

- [ ] **Step 6: 実行前のハッシュを記録**

Run: `cd $SP/spec-audit-fixture && find spec req src -type f -exec sha256sum {} + | sort > ../fixture.sha256 && cat ../fixture.sha256`
Expected: 4行が出力される

（フィクスチャはスクラッチパッドにあるのでコミットしない）

---

### Task 2: report-template.md

**Files:**
- Create: `home/dot_claude/skills/spec-audit/report-template.md`

**Interfaces:**
- Produces: 中間ファイル `00`〜`06`、`questions.md`、`coverage-report.md` の書式。SKILL.md（Task 3）から「`report-template.md` を読め」と参照される。

- [ ] **Step 1: ファイルを作成**

````markdown
# 出力書式

各ファイルの冒頭には、`# <タイトル>` と run 番号と作成日時を書く。表の空きセルは空欄にせず、`—`（該当なし）または `空` で明示する。

## 00-inputs.md

| 区分 | 対象（パス、または URL＋ページタイトル） | 日付・版・更新履歴 | 取得日時 | 最終更新日時（メタデータ） | スナップショット |
|---|---|---|---|---|---|

末尾に次の3つを書く: スナップショットの保存先、区切り方の宣言（例: 「UC 単位で区切る」）、`viewpoints` の値。

## 01-elements.md

種別（アクター A- / 外部システム X- / エンティティ E- / 状態 S- / ユースケース UC- / イベント EV- / ルール R- / 用語 T-）ごとに節を分ける。

| ID | 名前 | 内容（ローカルは引用可、外部は要約） | 出典（すべて） | 確度 |
|---|---|---|---|---|

- 出典は `ファイル名#見出し`、または `ページタイトル <URL>#見出し` と書く。出典が複数ある場合は `; ` で区切る
- 確度は confirmed / inferred / TBD のいずれか
- UC 節には「基本 / 代替 / 例外フローの有無」の列を追加する
- 状態節には「属するエンティティ」の列を追加する

## 02-matrices.md

5つの表をこの順で並べ、それぞれの直後に「検出した漏れ」の箇条書きを置く。漏れがない場合は「確認内容: … / 漏れなし」と書く。

1. 情報 × UC（CRUD）: 行はエンティティ、列は UC。セルは C/R/U/D の組み合わせ、または `空`
2. 状態 × イベント: 行は状態、列はイベント。セルは遷移先の状態 ID、`未定義`、または `—`（起こり得ないと資料に明記されている場合のみ）。表の下に、到達できない状態と抜け出せない状態を列挙する
3. アクター × UC: セルは `担当`、`権限あり`、または `空`
4. UC × フロー種別: 列は基本 / 代替 / 例外。セルは出典、または `未定義`
5. 外部システム × 連携: 列は送信 / 受信 / 失敗時 / タイムアウト時 / 重複受信時。外部システムがなければ「外部システムなし（確認した資料: …）」と書く

## 03-viewpoints.md

行は UC、列は観点（取消・差し戻し・やり直し / 同時操作・排他制御 / 時間起点の処理 / 権限・代理操作 / 入力の境界値 / 履歴・監査ログ / データ移行・初期データ / 外部連携の失敗と復旧 / `viewpoints` で渡された観点）。
セルは `考慮あり（出典）`、`漏れ`、`N/A（理由）` のいずれか。

## 04-contradictions.md

### 比較記録
出典が複数ある要素をすべて載せる。

| 要素 ID | 比較した出典 | 結果（矛盾なし / 矛盾 → C-n） |
|---|---|---|

### 矛盾一覧

| ID | 分類（用語 / 定義・値 / ルール・条件 / 状態遷移 / 権限 / 資料間） | 該当箇所 A | 記述 A | 該当箇所 B | 記述 B | どちらが正しいか（根拠。なければ「判断不可」） | 影響範囲 |
|---|---|---|---|---|---|---|---|

- 資料間の矛盾では、根拠として日付と版を必ず書く
- 「判断不可」の行は、`questions.md` に対応する質問を作る

## 05-traceability.md

4つの節を設ける: 要件にあるが仕様にない / 仕様にあるが実装にない / 実装にあるが仕様にない / 仕様と実装で振る舞いが違う。
該当する引数が渡されていない節には「対象外（引数なし）」と書く。各節には、確認した範囲と結果（該当なしの場合も含む）を書く。

## questions.md

| ID | 対象要素 | 種別（漏れ / 矛盾 / 不明点 / 懸念） | 質問 | 重要度（高 / 中 / 低） | 判断が必要な理由 | 発生 Step |
|---|---|---|---|---|---|---|

## 06-verification.md

| # | 検証役の指摘 | 確認結果（元資料の該当箇所） | 扱い（反映: どのファイルか / 不採用: 理由） |
|---|---|---|---|

検証パスを実行できなかった場合は、その理由を書く。

## coverage-report.md

1. サマリ: 漏れの件数、矛盾の件数、重大なものの上位5件（ID と1行の説明）、検証パスで追加・修正した件数、対象と run の情報
2. 要素一覧（01 の内容）
3. 各マトリクスと検出された漏れ（02 の内容）
4. 観点チェック結果（03 の内容）
5. 矛盾一覧（04 の内容。比較記録も含める）
6. 突き合わせ結果（05 の内容）
7. 確認が必要な質問リスト（questions.md の内容。重要度が高いものから並べる）

内容は中間ファイルから転記する。統合の段階で要約したり省略したりしない。
````

- [ ] **Step 2: Commit**

```bash
git add home/dot_claude/skills/spec-audit/report-template.md
git commit -m "feat(skills): spec-audit の出力書式テンプレートを追加"
```

---

### Task 3: verifier-prompt.md

**Files:**
- Create: `home/dot_claude/skills/spec-audit/verifier-prompt.md`

**Interfaces:**
- Consumes: Task 2 の中間ファイル名
- Produces: SKILL.md の Step 6 で、この全文に `{SOURCES}`、`{RUN_DIR}` を埋め込んで Agent に渡す。

- [ ] **Step 1: ファイルを作成**

```markdown
# 検証役への指示

あなたは仕様点検の結果を検証する役です。点検作業の経緯は知りません。渡されたファイルだけを根拠に判断してください。
ファイルの作成・変更は一切しないでください。結果は最後のメッセージで返してください。

## 入力
- 元資料のスナップショット: {SOURCES}
- 点検結果: {RUN_DIR} 配下の 00-inputs.md 〜 05-traceability.md、questions.md

## 点検すること
1. **要素の漏れ**: 元資料をすべて読み、01-elements.md に載っていないアクター、外部システム、エンティティ、状態、ユースケース、イベント、ルール、定義済みの用語を挙げる。出典が載っているのに、別の出典が記録されていない要素も挙げる。
2. **根拠のない断定**: 資料に書かれていない内容を補っている箇所、根拠なしに「どちらが正しいか」を決めている箇所、confirmed なのに資料に明記されていない要素を挙げる。
3. **未確認のセル**: 02-matrices.md と 03-viewpoints.md で、空欄のセル、理由のない N/A、行や列の不足（01 の ID と照らして）を挙げる。
4. **比較の抜け**: 出典が複数ある要素のうち、04-contradictions.md の比較記録にないものを挙げる。

## 返却形式
指摘ごとに次の形式で書く。指摘がない観点は「指摘なし（確認範囲: …）」と書く。

- 観点: 1〜4 のいずれか
- 対象: ファイル名と該当箇所（ID や行）
- 内容: 何が問題か
- 根拠: 元資料のファイル名と見出し
```

- [ ] **Step 2: Commit**

```bash
git add home/dot_claude/skills/spec-audit/verifier-prompt.md
git commit -m "feat(skills): spec-audit の検証パス用プロンプトを追加"
```

---

### Task 4: SKILL.md と配置テスト

**Files:**
- Create: `home/dot_claude/skills/spec-audit/SKILL.md`
- Modify: `tests/bootstrap/dotfiles.test.sh:40`（hunk-review の行の直後）

**Interfaces:**
- Consumes: `report-template.md`、`verifier-prompt.md`（`{SOURCES}`、`{RUN_DIR}`）

- [ ] **Step 1: 配置テストを追加（失敗する状態で）**

`tests/bootstrap/dotfiles.test.sh` の40行目の直後に、次の1行を追加する。

```sh
  [ -f "$h/.claude/skills/spec-audit/SKILL.md" ] || fail "spec-audit skill not deployed"
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `sh tests/bootstrap/dotfiles.test.sh`
Expected: `FAIL: spec-audit skill not deployed`

- [ ] **Step 3: SKILL.md を作成**

````markdown
---
name: spec-audit
description: 仕様・設計資料の網羅性と整合性を点検し、漏れ・矛盾・確認すべき質問を docs/audit/run-N/coverage-report.md にまとめる。点検のみで、対象は変更しない。/spec-audit spec=... で手動起動する。
disable-model-invocation: true
argument-hint: spec=<path|url...> [req=<path|url...>] [src=<path|url...>] [viewpoints="観点1,観点2"] [out=<dir>]
---

# 仕様の網羅性・整合性点検

引数: $ARGUMENTS

これまで作成された仕様・設計の網羅性と整合性を点検する。**点検のみを行い、対象は一切変更しない。** 結果は報告ファイルにまとめる。

## 1. 引数

| 引数 | 必須 | 内容 |
|---|---|---|
| `spec` | 必須 | 仕様・設計資料 |
| `req` | 任意 | 元になった要件・議事録 |
| `src` | 任意 | 突き合わせに使う実装コード |
| `viewpoints` | 任意 | Step 3 に加える固有の観点（カンマ区切り） |
| `out` | 任意 | 出力先のルート。既定は `docs/audit` |

- `spec`・`req`・`src` には、空白区切りで複数の対象を渡せる。対象として受け付けるのは、ファイル、グロブ、ディレクトリ（配下を再帰的に読む）、URL のいずれか。
- URL のサービスは問わない。そのセッションで使える手段（該当サービスの MCP コネクタ、Web 取得、`gh` などの CLI）で読む。
  - 子ページやページツリーは配下まですべて読む。データベースは全行を読む。
  - 配下が50ページを超える場合は、一覧を示して続行するか利用者に確認する。

次の場合は停止する。
- `spec` がない場合は、上の表と起動例（`/spec-audit spec=docs/specs/ req=https://www.notion.so/... src=src/`）を示して停止する。
- パスが存在しない、グロブが何にも一致しない、URL を読む手段がない、または読み込みに失敗した場合は、該当する対象を示して停止する。

対象を自分で探したり推定したりしない。

## 2. 出力先

- **リポジトリ側**: `<out>/run-N/`。N は `<out>/run-*` の最大番号に 1 を足した値で、既存がなければ 1。前回の run の結果は参照しない。
- **スナップショット**: `<スクラッチパッド>/spec-audit/run-N/sources/`。スクラッチパッドはシステムプロンプトに示されたディレクトリで、ない場合は `${TMPDIR:-/tmp}` を使う。**リポジトリ内には置かない。**
- この2か所以外には書き込まない。

## 3. 全体のルール

- 推測で仕様を補完しない。わからないことは `questions.md` に入れる。
- 矛盾について、どちらが正しいかを根拠なく決めない。判断できないものは「判断不可」とし、`questions.md` に入れる。
- ルールどうしは整合していても、業務として成り立たないと思われる箇所は、種別「懸念」として `questions.md` に入れる。
- 「問題なし」と判断した項目も、何を確認したかを残す（確認していない項目と区別するため）。
- 途中で省略しない。対象が多い場合はユースケース単位で区切って進め、すべての区切りを処理する。
- 外部サービスには読み取り専用でアクセスする。コメント、編集、ページ作成などの書き込み系ツールは呼ばない。
- 出典は `ファイル名#見出し`、または `ページタイトル <URL>#見出し` と書く。
- 本文の引用: 外部ソースの記述は要約と該当箇所で示し、本文をそのまま引用しない。ローカルファイルの記述は、そのまま引用してよい。
- 各ファイルの書式は `report-template.md`（このスキルと同じディレクトリにある）に従う。最初に読んでおくこと。
- **各 Step の終わりに、書き出したファイルを読み直し、欠けがないことを確認してから次へ進む。次の Step は、記憶ではなく前の Step のファイルを読んでから始める。**

## 4. 手順

### Step 0: 入力の確定 → `00-inputs.md`
1. 引数を解釈し、run 番号 N を決める。
2. 対象をすべて列挙し、本文をスナップショット置き場に保存する（ローカルファイルもコピーする）。以降はスナップショットだけを読む。
3. 各資料の日付・版・更新履歴を記録する。本文に書かれていなければ、サービスのメタデータ（最終更新日時など）を使う。外部ソースは取得日時も記録する。
4. 対象が多い場合は、区切り方を宣言する。

### Step 1: 要素の棚卸し → `01-elements.md`
解釈や補完をせず、次の要素をすべて抽出し、ID を振る。
- アクター（利用者・役割）
- 外部システム
- 情報（エンティティ）とその状態
- ユースケース／業務（基本フロー・代替フロー・例外フロー）
- イベント（画面操作、外部からの受信、時間起点の処理）
- ビジネスルール・条件・バリエーション
- 用語（定義が書かれているもの）

各要素には、出典（同じ要素が複数箇所に書かれていればすべて）と確度を付ける。確度は次の3つ。
- confirmed: 資料に明記されている
- inferred: 資料から推測した
- TBD: 存在が示唆されるが、内容が不明

資料に書かれていないものを推測で追加しない。

### Step 2: マトリクスによる交差チェック → `02-matrices.md`
次の表を作り、空きセルを洗い出す。「漏れはありそうか」と考えるのではなく、全行×全列を一つずつ確認する。行と列は `01-elements.md` の ID から組む。
1. 情報 × ユースケース（CRUD 表）
   - 作成されるのに、参照・更新・削除されない情報
   - 誰も作成していないのに、参照されている情報
2. 状態 × イベント（状態遷移表）
   - 遷移先が未定義の組み合わせ
   - 到達できない状態、抜け出せない状態
3. アクター × ユースケース
   - 担当アクターのいないユースケース
   - 権限が未定義の操作
4. ユースケース × フロー種別
   - 代替フロー・例外フローが未定義のユースケース
5. 外部システム × 連携
   - 送受信の失敗時・タイムアウト時・重複受信時の扱い

### Step 3: 横断観点のチェック → `03-viewpoints.md`
各ユースケースについて、次の観点が考慮されているかを確認する。該当しない場合は「N/A（理由）」と書く。
- 取消・差し戻し・やり直し
- 同時操作・排他制御
- 時間起点の処理（締め、期限切れ、バッチ）
- 権限・代理操作
- 入力の境界値（0件、上限、大量件数、空値）
- 履歴・監査ログ
- データ移行・初期データ
- 外部連携の失敗と復旧
- `viewpoints` で渡された観点

### Step 4: 矛盾の検出 → `04-contradictions.md`
「矛盾がありそうか」と考えるのではなく、Step 1 で出典が複数あった要素について、記述をすべて集めてから比較する。比較した要素はすべて比較記録に残す。
1. 用語の矛盾
   - 同じものが別の名前で呼ばれている（例: 「顧客」と「会員」）
   - 同じ名前が別の意味で使われている
2. 定義・値の矛盾
   - 同じ項目の型・桁数・必須／任意・初期値が、資料によって違う
   - 上限値・期限・件数などの数値が食い違っている
3. ルール・条件の矛盾
   - 同じ条件に対して、異なる処理が定義されている
   - 条件の組み合わせによって、2つのルールが同時に成立して衝突する
   - 条件の範囲に重なりや隙間がある（例: 「10以上」と「8以下」では 9 が隙間になる）
4. 状態遷移の矛盾
   - 状態遷移表とユースケースのフロー記述で、遷移先が違う
   - 禁止されているはずの遷移が、別のフローでは許されている
5. 権限の矛盾
   - アクターの権限定義と、ユースケース内で実際に行っている操作が合わない
6. 資料間の矛盾
   - 要件・議事録と仕様で内容が違う（新しい決定で上書きされた可能性も含めて、日付・版を根拠に記録する）

矛盾ごとに、次の4点を記録する。
- 該当箇所（両方）
- それぞれの記述
- どちらが正しいと考えられるか（根拠がなければ「判断不可」）
- 影響範囲

1〜5 は資料の種類を問わず比較する。6 は `req` がある場合だけ行う。

### Step 5: 突き合わせ → `05-traceability.md`
- 元の要件・議事録にあるのに、仕様に反映されていない事項（`req` がある場合）
- 仕様にあるのに、実装されていない事項（`src` がある場合）
- 実装にあるのに、仕様にない事項（`src` がある場合）
- 仕様と実装で振る舞いが違う事項（`src` がある場合）

引数がなくて実施しない節には「対象外（引数なし）」と書く。

### Step 6: 検証パス → `06-verification.md`
1. `verifier-prompt.md` を読み、`{SOURCES}` をスナップショット置き場のパスに、`{RUN_DIR}` を `<out>/run-N` の絶対パスに置き換える。
2. Agent ツールでサブエージェントを1体起動し、その全文を渡す（general-purpose 型。会話の経緯は渡さない）。
3. 返ってきた指摘は、1件ずつ元資料で確かめる。正しいものは該当する中間ファイルと `questions.md` に反映する。すべての指摘について、扱いを `06-verification.md` に記録する。
4. Agent ツールが使えない場合は、その旨を `06-verification.md` に書いて次へ進み、サマリにも明記する。

### Step 7: 統合 → `coverage-report.md`
`report-template.md` の章立てに従い、中間ファイルの内容を省略せずに統合する。

## 5. 完了時の報告

利用者には次の3点だけを短く伝える。
- `coverage-report.md` のパス
- 漏れと矛盾の件数、重要度「高」の質問の件数
- スナップショットはスクラッチパッドにあり、セッションの終了とともに消えること
````

- [ ] **Step 4: テストが通ることを確認**

Run: `sh tests/bootstrap/dotfiles.test.sh`
Expected: 失敗せずに終了する（exit 0）

- [ ] **Step 5: frontmatter を確認**

Run: `head -5 home/dot_claude/skills/spec-audit/SKILL.md`
Expected: `name: spec-audit` と `disable-model-invocation: true` が含まれる

- [ ] **Step 6: Commit**

```bash
git add home/dot_claude/skills/spec-audit/SKILL.md tests/bootstrap/dotfiles.test.sh
git commit -m "feat(skills): 仕様の網羅性・整合性点検スキル spec-audit を追加"
```

---

### Task 5: フィクスチャによる動作確認（GREEN）

**Files:**
- 必要に応じて修正: `home/dot_claude/skills/spec-audit/SKILL.md`、`report-template.md`、`verifier-prompt.md`

- [ ] **Step 1: サブエージェントでスキルを実行（1回目）**

general-purpose のサブエージェントに次の指示を渡す（会話の経緯は渡さない）。

```
/home/tech/dev/ghq/github.com/kukv/dotfiles/.claude/worktrees/lazy-mapping-candy/home/dot_claude/skills/spec-audit/SKILL.md を読み、
引数「spec=$SP/spec-audit-fixture/spec/ req=$SP/spec-audit-fixture/req/ src=$SP/spec-audit-fixture/src/ viewpoints="ポイント失効" out=$SP/spec-audit-fixture/docs/audit」
で起動されたものとして、その手順どおりに最後まで実行してください。
同じディレクトリの report-template.md と verifier-prompt.md も、SKILL.md の指示どおりに使ってください。
```

- [ ] **Step 2: expected.md と照合**

Run: `ls $SP/spec-audit-fixture/docs/audit/run-1/` と `cat .../run-1/coverage-report.md`
Expected: 00〜06、`questions.md`、`coverage-report.md` が揃っている。D1〜D8 がすべて合格条件を満たす。

照合結果を D ごとに「合格 / 不合格（理由）」で記録する。

- [ ] **Step 3: 不変条件を確認**

Run: `cd $SP/spec-audit-fixture && find spec req src -type f -exec sha256sum {} + | sort | diff - ../fixture.sha256 && echo UNCHANGED; find docs -name sources`
Expected: `UNCHANGED` が出力され、`find` は何も出力しない

- [ ] **Step 4: 不合格があれば直して再実行する**

不合格の原因になった手順の記述を修正してから、Step 1 から再実行する（新しい `run-N` ができる）。全項目が合格するまで繰り返す。修正内容は commit する。

```bash
git add home/dot_claude/skills/spec-audit/
git commit -m "fix(skills): spec-audit の手順を動作確認結果に合わせて修正"
```

- [ ] **Step 5: 採番を確認**

もう一度実行した後の `ls $SP/spec-audit-fixture/docs/audit/` に、`run-1` と `run-2`（Step 4 で再実行していればそれ以降の番号も）が並んでいることを確認する。

---

### Task 6: 外部ソースの手動確認（利用者と一緒に行う）

- [ ] **Step 1:** 利用者に、点検に使ってよい外部ページ（Notion など。子ページがあるもの）の URL を1件もらう。
- [ ] **Step 2:** `spec=<URL>` で Task 5 Step 1 と同じ方法で実行する（`out` はスクラッチパッド内にする）。
- [ ] **Step 3:** 次の点を確認する。
  - 配下のページまで読めている
  - `00-inputs.md` に取得日時と最終更新日時がある
  - レポートで外部ソースの本文がそのまま引用されず、要約になっている
  - 外部ページに変更（コメントなど）が加わっていない

  不備があれば SKILL.md を修正して commit する。
