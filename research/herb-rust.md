# Herb の Rust 化

調査日: 2026-10-10

スライド 20（「いまは子プロセス、将来は Rust 版 Herb」）の裏付けとして、Marco Roth 氏の「Herb の linter / formatter を Rust で書き直す」構想を調べたメモです。
【出典】は公開情報・ソースコードで確かめたこと、【推測】は解釈です。手元での実行はしていません。

## まとめ

- 書き直しの対象はパーサではなく **linter と formatter**。パーサは今も C 製で、Rust からは FFI バインディングで呼ぶ【出典】
- 目的は「Ruby と JavaScript の両方から使える単一の実装と、同じ API」。速度の改善も挙げている【出典】
- Rust 製の linter は**動くプロトタイプがある**が、未マージのブランチ（`rust-linter`）にあり、リリースされていない。リリース時期の表明は見つからなかった【出典】
- Marco Roth 氏は、Rust 製 linter を Ruby に公開する仕組みと、**herb-lint の全ルールを RuboCop に公開する RuboCop プラグイン**のプロトタイプも作っている【出典】
- そのプラグインは ERB に対して RuboCop の `Lint` / `Style` / `Layout` を除外し、Herb のルールだけを実行する。つまり HTML 側の担当で、Ruby パートを RuboCop で検査する tk0miya/rubocop-herb とは役割が重ならない【出典・推測】
- rubygems の `rubocop-herb` 0.0.1 と `herb-linter` 0.0.1（どちらも Marco Roth 氏、2026-08）は、この計画のための名前と思われる。gem 名の衝突は、偶然ではなく本家の計画とぶつかっている【推測】
- Marco Roth 氏自身が「調整が必要」と述べている（herb#475）。発表で「将来は Rust 版 Herb 経由で」と言うなら、事前に話しておくのがよい【推測】

## 時系列【出典】

| 日付 | 出来事 |
|---|---|
| 2025-08-27 | PR [#455](https://github.com/marcoroth/herb/pull/455)「Rubygem: Implement multi-backend architecture including Node.js」。Ruby から linter / formatter を呼べるようにする PR。open のまま |
| 2025-09-08 | issue [#475](https://github.com/marcoroth/herb/issues/475)（`bundle exec herb lint/format`?）で、linter / formatter を純粋な Ruby で再実装するのは現時点では意味がない、と回答し #455 を案内 |
| 2025-11-02 | PR [#767](https://github.com/marcoroth/herb/pull/767) で Rust の FFI バインディングを追加（C パーサを Rust から呼ぶ） |
| 2026-02-25〜28 | ブランチ `rubocop-herb` に「Linter: Implement Linter in Rust」「RuboCop Herb: Implement Herb Integration for Herb」 |
| 2026-02-28〜 | ブランチ `rust-linter` で Rust 製 linter の開発が始まる |
| 2026-03-06 | issue [#1239 のコメント](https://github.com/marcoroth/herb/issues/1239#issuecomment-4013290572)で「Linter と Formatter を Rust で書き直すことを検討していて、動くプロトタイプがある」。Node.js 版と Rust 版の実行時間のスクリーンショットを掲載 |
| 2026-03-13 | [v0.9 のリリース記事](https://herb-tools.dev/blog/whats-new-in-herb-v0-9)に「Exploring a Rust-based Linter and Formatter」の節。今後の予定にも挙げる |
| 2026-03-17 | issue #475 で tk0miya が herb-tools-ruby / rubocop-herb を紹介。Marco Roth 氏が「Rust 経由で linter / formatter を Ruby に公開する方法に取り組んでいて、既存の linter ルールをすべて RuboCop に公開する RuboCop プラグインのプロトタイプがある。調整が必要そうだ」と返信（[コメント](https://github.com/marcoroth/herb/issues/475#issuecomment-4076915733)） |
| 2026-07-31〜08-09 | Rust の周辺 crate が main にマージされる: `herb-config`（設定の検証・統合）、`herb-printer`（AST からソースへの出力）、`herb-analysis`（Rubydex ベースの解析）、`herb-highlighter` |
| 2026-08-01 | rubygems に `rubocop-herb` 0.0.1（"Herb Integration for RuboCop"、依存は `herb` のみ）。homepage の `marcoroth/rubocop-herb` リポジトリは存在しない（2026-10-10 時点） |
| 2026-08-08 | `rust-linter` ブランチの最終コミット。TypeScript 版とのルールの一致（parity）を詰める作業が中心 |
| 2026-08-13 | rubygems に `herb-linter` 0.0.1（依存なし） |
| 2026-08-18 / 09-24 | v0.10 / v0.11 のリリース記事。Rust 製 linter / formatter への言及はない |

## v0.9 のリリース記事の記述【出典】

[What's new in Herb v0.9](https://herb-tools.dev/blog/whats-new-in-herb-v0-9)（2026-03-13）より。

> Beyond the bindings, we have been exploring rewriting the Linter and Formatter in Rust. There is a working prototype that can lint files using the same rule set as the current Node.js-based linter.

> The idea is to have a single implementation that can be used from both Ruby and JavaScript, with identical APIs on both sides.

> This is still early and exploratory, but the results are promising. More on this in a future release.

今後の予定（Future Work）の節:

> Early experiments with a Rust implementation of the core linter and formatter have shown promising results. A Rust-based implementation would allow us to share a single codebase across Ruby and JavaScript bindings with identical APIs, while also bringing significant performance improvements. This is something we are actively exploring.

同じ記事で、Herb の Ruby gem が Node.js 製の `herb-lint` / `herb-format` のバイナリを公開するようになったことも書かれている（"Node.js binaries"）。

## ブランチの中身【出典】

### `rust-linter`

- main から 78 コミット先行、553 コミット遅れ（2026-10-10 時点）。2026-08-08 以降は更新されていない
- `rust/herb-linter/`: Rust 製の linter 本体。ルール、autofix、`herb:disable` コメント、パーシャルの索引、CLI（rayon で並列実行）
- `herb-linter/`: Ruby の gem。gemspec の説明は "Built on the Herb parser with lint rules implemented in Rust"。`herb-lint` コマンドを持ち、C 拡張として Rust のライブラリを呼ぶ
- コミットの多くは TypeScript 版に合わせる作業（"Port the ten new rules from main to Rust"、"Match main's rule defaults in Rust" など）

### `rubocop-herb`

- 3 コミット（2026-02-25〜28）。main から 1,206 コミット遅れ
- `ext/herb/linter.c`: `Herb::Linter.lint(source, config_json, file_name)` を Ruby に公開する C 拡張。Rust 製 linter の C API（`herb_lint`）を呼ぶ
- `lib/rubocop/cop/herb/linting.rb`: `Herb/Linting` cop。Herb の linter を 1 回実行し、結果を RuboCop の offense に変換する。個々のルールの設定は `.rubocop.yml` ではなく `.herb.yml` で行う
- `lib/rubocop/herb/default.yml`: `*.erb` / `*.html` などを対象に加え、そのファイルでは `Lint` / `Style` / `Layout` を除外する

## tk0miya/rubocop-herb との関係【推測】

| | tk0miya/rubocop-herb | Marco Roth 氏のプロトタイプ |
|---|---|---|
| Ruby パート | 独自の変換で RuboCop の cop をかける | 検査しない（`Lint` / `Style` / `Layout` を除外） |
| HTML パート | `Herb/Linting` cop が Node.js の herb-lint を子プロセスで実行 | `Herb/Linting` cop が Rust 製 linter を同じプロセス内で実行 |
| 状態 | 開発中（未公開） | 未マージのブランチ。gem 名だけ確保 |

- 2 つは補い合う関係にある。Rust 製 linter がリリースされれば、tk0miya/rubocop-herb の `Herb/Linting` cop は子プロセスをやめて Rust 製 linter を直接呼べる。Node.js も要らなくなる
- 一方で、どちらも「RuboCop で ERB を検査するプラグイン」で、gem 名も HTML 側の cop 名（`Herb/Linting`）も同じなので、利用者から見ると 2 つの `rubocop-herb` が並ぶことになる。統合するのか、名前を分けるのかは Marco Roth 氏と相談が必要

## 未確認

- Rust 製 formatter のプロトタイプ。v0.9 の記事では linter と並べて挙げているが、ブランチは見つからなかった（`formatter` などのブランチは中身を見ていない）
- Rust 製 linter を Node.js から使う方法（N-API / WebAssembly など）
- 発表で言及することについての Marco Roth 氏の意向
