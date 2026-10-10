# 既存の ERB linter から rubocop-herb に切り替えるか

調査日: 2026-10-10

[existing-erb-linters.md](existing-erb-linters.md)（既存ツール）と [report.md](report.md)（rubocop-herb）の結果をもとに、利用者の立場から「既存ツールを使い続ける理由」「rubocop-herb に切り替える理由」「切り替えられない理由」を整理したメモです。
【実測】は手元で実行して確かめたこと、【出典】はソースコードや公開情報で確かめたこと、【推測】は解釈です。ここで新たに確かめた事実には印を付け、既存の 2 文書で確かめた事実は、その文書へのリンクで示します。

## 比較の前提

- 既存ツールは、Ruby 部分を RuboCop で検査する **erb_lint**（Rubocop linter）、**rubocop-erb**、**ruumba** と、HTML 構造を検査する **herb-lint** を対象にする。中心は利用者が最も多い erb_lint
- rubocop-herb は `14830806e5deb61e27744e9fed09c5380ccbeee7`（2026-10-11 時点の main）
- 利用状況（rubygems.org、2026-10-10 時点の累計 DL）【出典】

| gem | 最新 | 累計 DL |
|---|---|---|
| erb_lint | 0.9.0 | 2,193 万 |
| herb | 0.11.0 | 202 万 |
| rubocop-erb | 0.7.2 | 85 万 |
| ruumba | 0.1.17 | 49 万 |
| rubocop-herb（tk0miya） | 未公開 | - |

## まとめ

- **切り替える理由は、Ruby 部分の検査の正しさ**。既存ツールの見逃し・誤検知・テンプレートを壊す autocorrect は、research の再現例ではほぼすべて解消している。`.rubocop.yml` と `rubocop` コマンドに一本化できることも大きい
- **使い続ける理由は、実績と、RuboCop 以外の機能**。erb_lint は利用者が桁違いに多く、Ruby だけで動く HTML 検査や、独自 linter・プラグインの資産がある
- **今すぐ切り替えられない理由は 2 種類ある**
  - rubocop-herb 側で解消できるもの: rubygems に未公開（gem 名も衝突）、`-a` でテンプレートを壊す問題が 1 件残っている
  - 利用者の環境や資産によるもの: HTML 検査に Node.js が必要、erb_lint の独自 linter・プラグインに移行先がない、Ruby 3.3 以上が必要
- 既存ツールごとに見ると、ruumba と rubocop-erb の利用者は失うものがほぼなく、移行しやすい。erb_lint の利用者は Ruby 部分だけを rubocop-herb に移す併用が現実的。herb-lint の利用者にとっては、rubocop-herb は置き換えではなく追加になる【推測】

## 既存ツールを使い続ける理由

### 実績と情報の多さ

- erb_lint の累計 DL は 2,193 万で、rubocop-erb の約 26 倍【出典】。設定例や CI への組み込み方の情報が多い
- 周辺ツール（pronto-erb_lint, guard-erb_lint, erb_lint_daemon など）がある（[existing-erb-linters.md](existing-erb-linters.md#rubygemsorg-で見つかったその他の候補)）

### RuboCop 以外の機能（erb_lint）

erb_lint 0.9.0 には、Rubocop linter のほかに 22 個の linter と 5 個の reporter が同梱されています【出典: `lib/erb_lint/linters/`, `lib/erb_lint/reporters/`】。

- linter: `ErbSafety`, `HardCodedString`, `DeprecatedClasses`, `SelfClosingTag`, `SpaceAroundErbTag`, `ClosingErbTagIndent`, `PartialInstanceVariable`, `RequireScriptNonce`, `StrictLocals` など
- reporter: `compact`, `multiline`, `json`, `junit`, `gitlab`
- Ruby でユーザー独自の linter を書ける。erblint-github（a11y 16 ルール）や erblint-agent のようなプラグインもある（[existing-erb-linters.md](existing-erb-linters.md#その他のツール)）
- better_html で HTML を解析するので、**Ruby だけで動く**（Node.js が要らない）

これらの多くは herb-lint にも同等のルールがあります（`erb-closing-tag-indent`, `erb-right-trim`, `erb-no-unsafe-raw`, `erb-no-instance-variables-in-partials`, `html-require-script-nonce`, `actionview-strict-locals-*` など。herb-lint v0.11.0 の `docs/rules`【出典】）。一方、`HardCodedString`（i18n の漏れ）と `DeprecatedClasses`（指定した CSS クラスの禁止）に当たるルールは、名前からは見当たりませんでした【出典】。

### 見逃しが多い分、導入時の負担が小さい【推測】

- タグ単位の方式では、`if` の条件式などが検査されない（[existing-erb-linters.md](existing-erb-linters.md#見逃し実測)）。裏返すと、既存のテンプレートに入れたときの offense が少ない
- rubocop-herb はプロジェクトの `.rubocop.yml` をそのまま ERB に当てるので、Ruby のファイルと同じ水準の offense が一度に出る。大きなプロジェクトでは、導入時に `.rubocop_todo.yml` で抑えるなどの作業が要る（`--auto-gen-config` が ERB で期待どおりに動くかは未確認）

### 既知の問題を避ける設定がすでにある

- erb_lint の利用者は、README の推奨どおりに誤検知の cop を無効化して運用していることが多いと思われる【推測】
- ただし、推奨設定でも `-a` でテンプレートが壊れる例がある（`Layout/LeadingEmptyLines` で `<%` が消える。[existing-erb-linters.md](existing-erb-linters.md#autocorrect-がテンプレートを壊す実測)）。「安全な設定がある」わけではない

## rubocop-herb に切り替える理由

### 検査できる範囲が広い【実測】

[report.md](report.md#既存ツールの問題に対する結果実測) の再現例では、次のものが検出・修正されます。

- タグを跨いだ制御構造: `<% if foo == nil %>` の `Style/NilComparison`、`<% if !user.nil? %>` の `Style/NegatedIf`、`then` / `elsif` / `unless !x`、本当に空の `else`
- タグを跨いだ変数: 本当に未使用の変数だけに `Lint/UselessAssignment` が出る
- `Lint/Syntax`: `end` の抜けを検出する（rubocop-erb は `Lint/Syntax` を除外している）
- herb-lint では検出されないスタイル違反（`link_to( 'Home',root_path )` など）

### 誤検知が少ない【実測・出典】

- erb_lint の `Lint/UselessAssignment` やタグごとの `Style/FrozenStringLiteralComment`、ruumba の `Lint/Void`・`Style/SymbolProc`・`Lint/EmptyConditionalBody`・Layout 系の誤検知は、いずれも出ない
- ファイル全体で除外する cop は 9 個（rubocop-erb は約 55 個）。それ以外の誤検知になる cop（19 個）は、HTML を本文に持つ分岐や、ERB タグに跨がる `<% end %>` など、誤検知になる行だけで無効にする

### autocorrect の大半が正しい【実測】

- rubocop-erb で意味・構文を壊していた `count -1`、`item *2`、`user && user.admin?` が正しく修正される
- erb_lint で `<%=` や `<%` が消えていた例も、正しく修正されるか、変更されない
- 文字位置を変えずに変換するので、ruumba のように黙って書き戻しを諦めることがない
- ただし、文の削除で壊す例が残っている（後述）

### RuboCop に一本化できる【出典・推測】

- 設定は `.rubocop.yml` だけ。Ruby のファイルと同じ規約が ERB にも当たり、`.erb_lint.yml` で cop を二重管理しなくてよい
- 実行は `rubocop` コマンドだけ。RuboCop の結果キャッシュ、`--parallel`、formatter、`rubocop:disable` コメントがそのまま使える（RuboCop と同じプロセス内で動く。[report.md](report.md#rubocop-との連携)）
- `Herb/Linting` cop で herb-lint の結果も同じ出力に並ぶ。herb-lint の設定（`.herb.yml`、`.herb/rules/` の独自ルール、`herb:disable` コメント）もそのまま効く【出典: README】
- エディタの RuboCop 連携（Ruby LSP など）で ERB も検査できる見込み【推測。未確認】

### 既存ツールの開発が止まりつつある【出典】

- erb_lint は 2025-05 以降は依存更新のみで、性能改善 PR や autocorrect のバグが open のまま
- ruumba は 2021 年からメンテ停止
- better_html は非推奨になり、Herb への移行を案内している。rubocop-erb も ERB パーサを Herb に移した
- rubocop-herb は、開発が活発な Herb の上に作られている

## 切り替えられない理由

### rubocop-herb 側で解消できるもの

| 理由 | 影響 | 解消の見込み |
|---|---|---|
| rubygems に未公開。gem 名が Marco Roth 氏の `rubocop-herb` 0.0.1 と衝突している。README の Installation が雛形のまま | Gemfile に git で指定するしかない。業務のプロジェクトでは導入しにくい | gem 名を決めて公開すれば解消 |
| `-a` で文の削除が `<%` ごと消す（`Lint/Void`, `Lint/UselessAssignment`） | **安全な autocorrect でテンプレートを壊す**。CI での自動修正や、保存時の自動修正に組み込めない | 修正範囲が ERB タグの中身の外にかかる修正を捨てる仕組みで防げる見込み（[report.md](report.md#autocorrect-がテンプレートを壊す原因出典推測)） |
| マルチバイト文字を含むテキストや HTML コメントが `hybrid_code` に戻らない（[#72](https://github.com/tk0miya/rubocop-herb/issues/72)、open） | エラー表示【推測】 | issue で対応中 |
| herb-lint の autocorrect に対応していない【出典: README】 | HTML 側の修正には `herb-lint --fix` を別に実行する必要がある | 実装すれば解消 |

最初の 2 件は、どれも「既存ツールより良い」と言える範囲を狭めます。特に autocorrect の問題は、erb_lint や rubocop-erb と同じ種類の問題（テンプレートを壊す）なので、解消するまでは「autocorrect が安全になった」とは言えません。

### 利用者の環境や資産によるもの

| 理由 | 影響 |
|---|---|
| HTML の検査（`Herb/Linting`）に Node.js と `@herb-tools/linter` が必要【出典: README】 | Node.js を入れられない環境では、HTML 構造の検査を RuboCop に統合できない。erb_lint は Ruby だけで HTML を検査できる |
| erb_lint の独自 linter・プラグイン（erblint-github など）や、`HardCodedString`・`DeprecatedClasses` の移行先がない | これらを使っているプロジェクトは、erb_lint を残す必要がある。herb-lint の独自ルール（`.herb/rules/`）は JavaScript で書き直すことになる【推測】 |
| Ruby 3.3 以上、rubocop 1.90 以上が必要【出典: gemspec】 | 古い Ruby のプロジェクトでは使えない |
| 既定で対象にするのは `.html.erb` だけ【出典: `Configuration::DEFAULT_EXTENSIONS`】 | `.js.erb` や `.text.erb` は対象外。`extensions` 設定で追加できるが、HTML として解析されるので期待どおりに動くかは未確認【推測】 |
| Ruby の構文エラーがあるファイルでは herb-lint が動かない。他のテンプレートを参照するルール（パーシャルと呼び出し元など）はプロジェクト全体の解析なしで動く【出典: README】 | herb-lint を単独で使う場合より、HTML 側の検査が一部弱くなる |
| ERB タグに跨がる構造では Layout 系の cop を無効にしている（`Layout/IndentationWidth`, `Layout/EndAlignment` など）【出典】 | 1 つのタグの中の Ruby は検査されるが、タグに跨がる本文や `<% end %>` のインデントは検査されない。HTML の構造に沿ったインデントは herb-format などの役割として残る |

## 既存ツールごとの判断【推測】

| いま使っているもの | 切り替えたときに得るもの | 失うもの | 判断 |
|---|---|---|---|
| ruumba | 誤検知の解消、正しく書き戻される autocorrect、メンテされている実装 | ほぼない | 公開されれば移行しやすい |
| rubocop-erb | タグを跨いだ検査、`Lint/Syntax`、意味を壊さない autocorrect | ほぼない（どちらも RuboCop プラグイン） | 公開されれば移行しやすい。ただし `-a` で `<%` ごと消すのは rubocop-erb にない種類の壊れ方 |
| erb_lint（Rubocop linter のみ） | 同上と、`.rubocop.yml` への一本化 | 導入時の offense の増加 | Ruby 部分は移行する価値がある |
| erb_lint（HTML 系 linter・プラグインも利用） | Ruby 部分の検査の正しさ | 独自 linter・プラグイン、Node.js 不要という性質 | Ruby 部分だけ rubocop-herb に移し、erb_lint の Rubocop linter を無効にして併用する |
| herb-lint | Ruby のスタイル検査（herb-lint にはない）、RuboCop との統合 | herb-lint の autocorrect（`herb-lint --fix` は別に実行すれば残る） | 置き換えではなく追加。`Herb/Linting` cop で 1 コマンドにまとめられる |

## 発表に向けて

- 提案では「チェックできる範囲、auto correct できる範囲が広がっています」と書いている。範囲が広がったことは再現例で示せるが、`-a` でテンプレートを壊す例が残っているうちは、「autocorrect が安全」とまでは言わないほうがよい
- 「切り替えられない理由」のうち、rubocop-herb 側で解消できるもの（公開、autocorrect の問題）は、発表までに片付けておきたい
- 利用者の環境によるもの（Node.js、erb_lint の独自 linter）は、「erb_lint と併用できる」「herb-lint を Ruby から使える」という形で、移行の道筋として示せる
