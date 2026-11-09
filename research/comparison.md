# 第 1 部 ERB linter の比較

ERB の中の Ruby を検査するツールを、仕組みと、同じ入力にかけた結果で比べます。
対象の版と凡例は [README.md](README.md) にあります。tk0miya-rubocop-herb の仕組みは [第 2 部](tk0miya-rubocop-herb.md) で説明します。

## 目次

1. [ERB から Ruby を取り出す 2 つの方式](#1-erb-から-ruby-を取り出す-2-つの方式)
2. [ツール一覧](#2-ツール一覧)
3. [タグ単位の方式](#3-タグ単位の方式)（erb_lint、rubocop-erb 0.7 系）
4. [文書全体を 1 本の Ruby にする方式](#4-文書全体を-1-本の-ruby-にする方式)（ruumba、rubocop-erb 0.8 系、herb-rubocop-herb、Herb）
5. [同じ入力での比較](#5-同じ入力での比較)（検証用 ERB、正しいものと直すべきものの区別、autocorrect、実際のビュー、指摘の表示）
6. [無効化コメント](#6-無効化コメント)（書き方、`<%#` の置き場所、herb-format の整形）
7. [その他のツール](#7-その他のツール)
8. [Herb の今後（Rust 化）](#8-herb-の今後rust-化)
9. [既存ツールから tk0miya-rubocop-herb に切り替えるか](#9-既存ツールから-tk0miya-rubocop-herb-に切り替えるか)
10. [要フォローアップ](#10-要フォローアップ)
11. [主な出典](#11-主な出典)

## 1. ERB から Ruby を取り出す 2 つの方式

既存ツールの Ruby の扱いは、次の 2 系統に分かれます。

1. **タグ単位に分割する**（erb_lint、rubocop-erb 0.7 系、better_html、erb-formatter、Rufo など）
   - ERB タグ 1 つを 1 つの Ruby プログラムとして扱う
   - 制御構造（`if`〜`end`）、変数スコープ、ファイルという 3 つの文脈が失われる
   - その結果、誤検知・見逃し・テンプレートを壊す autocorrect が起きる
2. **文書全体を 1 本の Ruby にする**（ruumba、rubocop-erb 0.8 系、herb-rubocop-herb、Herb の構文チェック、Steep の提案、tk0miya-rubocop-herb）
   - タグを跨いだ制御構造や変数スコープは保たれる
   - ERB タグの外を空白にすると、`<%=` の「出力する」という意味と HTML の存在が失われ、別の誤検知が出る（[5.2 節](#52-erb-として正しいものと直すべきものの区別)）
   - tk0miya-rubocop-herb だけは、`<%=` と HTML を Ruby の文として書き込んで、ERB の意味を残す（[第 2 部 2 章](tk0miya-rubocop-herb.md#2-erb-から-ruby-への変換)）

ERB は、テキストと `<%=` を `_erbout` への追記という**文**にコンパイルします【出典】。

```ruby
# ERB.new('<p>Hello, <%= user.name %></p>').src（先頭の行を除く）
_erbout = +''; _erbout.<< "<p>Hello, ".freeze; _erbout.<<(( user.name ).to_s); _erbout.<< "</p>".freeze; _erbout
```

同じ ERB を、3 つの方式で Ruby にすると次のようになります（行末の空白は省略）【実測】。

```erb
<% if user %>
  Welcome!
  <%= user.name %>
<% end %>
```

| タグ単位（rubocop-erb 0.7 系） | `Herb.extract_ruby`（rubocop-erb 0.8 系、herb-rubocop-herb） | tk0miya-rubocop-herb（`bin/erb2ruby`） |
|---|---|---|
| `user`、`user.name` の 2 つの断片（`if` と `end` は削る） | `   if user  ;`⏎（空行）⏎`      user.name  ;`⏎`   end  ;` | `   if user;`⏎`  _a;`⏎`  _ = user.name;`⏎`   end;` |

| ERB | ERB のコンパイル結果 | `Herb.extract_ruby` | tk0miya-rubocop-herb |
|---|---|---|---|
| `<%= expr %>` | `_erbout << (expr).to_s` | `expr  ;`（値を捨てる式） | `_ = expr;`（値を使う文） |
| `<% expr %>` | `expr` | `expr  ;` | `expr;` |
| `<div>`、`</div>` | `_erbout << "<div>"` | 空白 | `div;` |
| テキスト、HTML コメント、`<%%` | `_erbout << "text"` | 空白 | `_a;`（置けるときだけ） |

空白にすると文の数が減ります。上の `if` の本文は、ERB では 2 文、`extract_ruby` では値を捨てる式 1 つ、tk0miya-rubocop-herb では 2 文です。

## 2. ツール一覧

凡例: ◎ 本格対応 / ○ 対応 / △ 限定的 / × なし

| ツール | HTML 構造 | Ruby の構文 | Ruby のスタイル (RuboCop) | タグを跨いだ Ruby 解析 | autocorrect | 型・意味解析 |
|---|---|---|---|---|---|---|
| erb_lint (Rubocop linter) | ○ (better_html) | △ (タグ単位。不完全な文はスキップ) | △ (タグ単位) | × | △ (テンプレートを壊す) | × |
| rubocop-erb 0.7 系 | × | △ (タグ単位。Lint/Syntax を除外) | △ (タグ単位。53 cop を除外) | × | △ (意味・構文を壊す) | × |
| rubocop-erb 0.8 系 | × | ○ (文書全体) | △ (文書全体。65 cop を除外) | ○ | ○ (1 つのタグの Ruby に収まらない修正は捨てる) | × |
| herb-rubocop-herb (Draft) | × | ○ (文書全体) | △ (文書全体。48 cop を除外。出力・HTML 本文が失われ誤検知) | ○ | × (`-a` でもテンプレートを壊す) | × |
| ruumba (メンテ停止) | × | ○ (文書全体) | △ (文書全体。出力・HTML 本文が失われ誤検知) | ○ | △ (実験的。黙って書き戻さないことがある) | × |
| **tk0miya-rubocop-herb** | ◎ (Herb/Linting で herb-lint を実行。Node.js が必要) | ○ (文書全体) | ○ (文書全体。10 cop を除外し、31 cop を行単位で無効化) | ○ | ○ (テンプレートを壊す修正は捨てる) | × |
| Herb (herb-lint) | ◎ | ◎ (Prism で文書全体) | × | ○ (未使用変数など) | ○ (約 40 ルール) | × |
| herb-format | ◎ | △ | × (Ruby は trim のみ) | × | ○ (整形) | × |
| better_html (非推奨) | ○ | △ (タグ単位) | × | × | × | × |
| erb-formatter | ○ | △ | △ (syntax_tree でタグ単位) | × | ○ (整形) | × |
| htmlbeautifier | △ (インデントのみ) | × | × | × | ○ (整形) | × |
| Rufo (ERB) | × | △ | △ (タグ単位) | × | ○ (整形) | × |
| `erb -x \| ruby -c` | × | ○ (Rails の `<%= … do %>` で誤検出) | × | ○ (構文のみ) | × | × |
| Steep ([#1409](https://github.com/soutaro/steep/issues/1409) / PR [#1836](https://github.com/soutaro/steep/pull/1836)) | × | ○ (予定) | × | ○ (予定) | × | ◎ (未マージ) |
| sorbet_erb / sorbet_view | × | ○ | × | ○ | × | ○ (注釈が必要) |
| erblint-github | ○ (a11y 16 ルール) | × | × | × | △ | × |

利用状況（rubygems.org、2026-10-31 時点の累計 DL）【出典】

| gem | 最新 | 累計 DL |
|---|---|---|
| erb_lint | 0.9.0 | 2,250 万 |
| herb | 0.11.1 | 236 万 |
| rubocop-erb | 0.8.2 | 91 万 |
| ruumba | 0.1.17 | 50 万 |
| tk0miya-rubocop-herb（tk0miya） | 未公開 | - |

「HTML と Ruby の両方を理解したうえで、RuboCop のスタイル検査と autocorrect を安全に行う」既存ツールはありません。Ruby だけを取り出す方式では、分割しても、HTML を空白にして連結しても、文脈の一部が失われます。

## 3. タグ単位の方式

### 3.1 erb_lint（Rubocop linter）

- リポジトリ: https://github.com/Shopify/erb_lint
- 最新: 0.9.0（2025-01-20）。2025-05 以降は依存更新のみで、性能改善 PR（[#454](https://github.com/Shopify/erb_lint/pull/454), [#457](https://github.com/Shopify/erb_lint/pull/457)）や autocorrect のバグ（[#461](https://github.com/Shopify/erb_lint/issues/461)）が open のまま

#### 仕組み【出典】

`lib/erb_lint/linters/rubocop.rb` は、better_html で取り出した ERB タグ 1 つずつを、それぞれ別の Ruby ファイルとして `RuboCop::ProcessedSource` に渡します。

```ruby
trimmed_source = original_source.sub(BLOCK_EXPR, "").sub(SUFFIX_EXPR, "")
aligned_source = "#{" " * alignment_column}#{trimmed_source}"
source = rubocop_processed_source(aligned_source, processed_source.filename)
return unless source.valid_syntax?
```

- README にも "Each ruby statement (between ERB tags `<% ... %>`) is parsed and analyzed independently of each other." と明記されている
- `<% if foo %>` や `<% end %>` のような不完全な文は `valid_syntax?` で弾かれ、**黙ってスキップ**される。PR [#457](https://github.com/Shopify/erb_lint/pull/457) によると、断片の約 38% がこうしたタグ
- `<% items.each do |i| %>` は末尾の `do |i|` を正規表現（`BLOCK_EXPR`）で削り、`items.each` だけを検査する
- `<%=` と `<%` を区別しない（出力されることを RuboCop は知らない）

#### 誤検知【実測】

全 cop を有効にした設定（`bin/lint erb_lint-all`）で次の結果になります。

| ERB | 結果 |
|---|---|
| `<%= "hello" %>`（`cases/output/string_literal`） | `Layout/InitialIndentation`、`Layout/TrailingEmptyLines`、`Style/FrozenStringLiteralComment` が**タグごとに**出る |
| `<% total = items.sum(&:price) %>` + `<p><%= total %></p>`（`cases/variables/cross_tag_variables`） | `Lint/UselessAssignment` が出る。次のタグで使っているので誤検知 |

`cases/` の 74 ファイルでは、`Style/FrozenStringLiteralComment` が 94 件、`Layout/TrailingEmptyLines` が 89 件、`Layout/InitialIndentation` が 89 件、`Lint/UselessAssignment` が 15 件出ます。

README はこれらの cop を無効化するよう推奨しています（InitialIndentation, LineLength, TrailingEmptyLines, TrailingWhitespace, FileName, FrozenStringLiteralComment, UselessAssignment, Rails/OutputSafety）。issue [#126](https://github.com/Shopify/erb_lint/issues/126) ではメンテナが UselessAssignment について「this is normal … Consider disabling this cop」と回答しています。

#### 見逃し【実測】

推奨設定（`bin/lint erb_lint-recommended`）での結果と、同じ内容の Ruby（`repro/plain_ruby/equivalent.rb`。`bin/lint plain-ruby`）に RuboCop をかけた結果の比較です。

| ERB | erb_lint | 同じ内容の Ruby |
|---|---|---|
| `<% if foo == nil %>…<% end %>`（`cases/control_flow/nil_comparison`） | 0 件 | `Style/NilComparison`, `Style/IfUnlessModifier` |
| `<% if !foo.nil? then %>…<% elsif bar == nil %>…<% else %><% end %>`（`cases/control_flow/if_then_elsif_else`） | 0 件 | `Style/MultilineIfThen`, `Style/NilComparison`, `Style/EmptyElse` |
| `<% unless !x %><% end %>`（同上） | 0 件 | `Style/NegatedUnless`, `Lint/EmptyConditionalBody` |
| `<% items.each do \|i\| %>…<% end %>`（`i` 未使用。`cases/control_flow/unused_block_arg`） | 0 件 | `Lint/UnusedBlockArgument` |

`if` の条件式が検査されない問題は issue [#332](https://github.com/Shopify/erb_lint/issues/332) として報告されています（open）。

#### autocorrect がテンプレートを壊す【実測】

| 設定 | 修正前 | `erb_lint -a` 後 |
|---|---|---|
| 全 cop | `<%= link_to "x", path, class: 'btn' %>` | `# frozen_string_literal: true`⏎`link_to 'x', path, class: 'btn'`⏎` %>` |
| 全 cop | `<% total = items.sum(&:price) %>` | `# frozen_string_literal: true`⏎`items.sum(&:price)`⏎` %>` |
| 推奨設定 | `<%`⏎`  x = 1`⏎`  y = 2`⏎`%>` | `x = 1`⏎`  y = 2`⏎`%>` |
| 推奨設定 | `<% count = items.size %>`⏎`<p><%= count -1 %></p>` | `<%= count(-1) %>`（前のタグの変数が見えず、メソッド呼び出しと解釈する。rubocop-erb 0.7 系と同じ） |

- `<%=` や `<%` が消え、マジックコメントが HTML 本文に挿入される
- 推奨設定でも、README のリストに入っていない `Layout/LeadingEmptyLines` の修正で `<%` が消える。`cases/` の 74 ファイルでは、推奨設定の `-a` で 6 ファイル（`<%` の直後で改行する複数行のタグと、`<% # … %>` のタグ）の `<%` が消え、全 cop の設定では書き換えた 49 ファイルすべてで HTML が変わる
- 同系統の issue: [#142](https://github.com/Shopify/erb_lint/issues/142)（2019 年から open）, [#228](https://github.com/Shopify/erb_lint/issues/228), [#326](https://github.com/Shopify/erb_lint/issues/326), [#331](https://github.com/Shopify/erb_lint/issues/331), [#383](https://github.com/Shopify/erb_lint/issues/383), [#461](https://github.com/Shopify/erb_lint/issues/461)。修正 PR [#413](https://github.com/Shopify/erb_lint/pull/413) も open のまま

#### RuboCop 以外の機能【出典】

erb_lint 0.9.0 には、Rubocop linter のほかに 22 個の linter と 5 個の reporter が同梱されています（`lib/erb_lint/linters/`, `lib/erb_lint/reporters/`）。

- linter: `ErbSafety`, `HardCodedString`, `DeprecatedClasses`, `SelfClosingTag`, `SpaceAroundErbTag`, `ClosingErbTagIndent`, `PartialInstanceVariable`, `RequireScriptNonce`, `StrictLocals` など
- reporter: `compact`, `multiline`, `json`, `junit`, `gitlab`
- Ruby でユーザー独自の linter を書ける。erblint-github（a11y 16 ルール）や erblint-agent のようなプラグインもある
- better_html で HTML を解析するので、**Ruby だけで動く**（Node.js が要らない）

これらの多くは herb-lint にも同等のルールがあります（`erb-closing-tag-indent`, `erb-right-trim`, `erb-no-unsafe-raw`, `erb-no-instance-variables-in-partials`, `html-require-script-nonce`, `actionview-strict-locals-*` など。herb-lint v0.11.0 の `docs/rules`）。一方、`HardCodedString`（i18n の漏れ）と `DeprecatedClasses`（指定した CSS クラスの禁止）に当たるルールは、名前からは見当たりませんでした。

#### その他【出典】

- 性能: タグごとに `Team.mobilize` で全 cop を作り直す。改善 PR [#454](https://github.com/Shopify/erb_lint/pull/454)（25 タグ/ファイルで 8.94s → 5.56s）、[#457](https://github.com/Shopify/erb_lint/pull/457) は未マージ
- キャッシュが RuboCop のバージョンや `.rubocop.yml` の変更を考慮しない（[#299](https://github.com/Shopify/erb_lint/issues/299), [#300](https://github.com/Shopify/erb_lint/pull/300), [#464](https://github.com/Shopify/erb_lint/pull/464)）

### 3.2 rubocop-erb 0.7 系

- リポジトリ: https://github.com/r7kamura/rubocop-erb
- 対象: 0.7.2（2026-10-06。タグ単位の方式の最後の版）。0.7.0 で ERB パーサを better_html から Herb に移行（[#57](https://github.com/r7kamura/rubocop-erb/issues/57), [#59](https://github.com/r7kamura/rubocop-erb/pull/59)）
- 0.8.0（2026-10-29）で、Ruby の取り出し方を文書全体の変換に切り替えた（[4.2 節](#42-rubocop-erb-08-系)）

#### 仕組み【出典】

RuboCop の ruby_extractors API（rubocop PR [#10839](https://github.com/rubocop/rubocop/pull/10839)、r7kamura 氏が導入）を使うプラグインです。

- extractor は `[{offset: Integer, processed_source: RuboCop::ProcessedSource}, ...]` を返す
- cop は fragment ごとに独立した ProcessedSource として実行され（`Team#investigate_fragments`）、位置は `range.begin_pos + offset` で元ファイルに戻される
- つまり **1 つの fragment は元ファイル上の連続した 1 区間でなければならない**【推測】。タグを跨いだ構文を、タグごとの fragment の組として渡すことはできない

Ruby の取り出し方（`lib/rubocop/erb/ruby_extractor.rb`）:

- Herb の AST から ERB タグ 1 つを 1 fragment として取り出す
- `KeywordRemover` が正規表現で先頭の `if` / `unless` / `else` / `end` などと、末尾の `do |x|` / `{ |x|` / `then` を削る
- `<% if foo %>` は `foo` として、`<% items.each do |i| %>` は `items.each` として検査される

r7kamura 氏自身が issue [#6](https://github.com/r7kamura/rubocop-erb/issues/6) で「`if a` / `c` / `end` をまとめて抽出しても、offense を元 ERB の位置に戻す仕組みがない」と述べています。

`config/default.yml` で 53 個の cop が `**/*.erb` から除外されています。Layout 系の大半、`Lint/Syntax`、`Lint/UselessAssignment`、`Lint/Void`、`Style/FrozenStringLiteralComment`、`Style/IfUnlessModifier`、`Metrics/BlockLength` などです。

#### 見逃し【実測】

`bin/lint rubocop-erb-0.7` の結果です。

| ERB | 結果 |
|---|---|
| `<% if !user.nil? %>…<% end %>` | `Style/NegatedIf` が出ない（`if` が削られるため）。削った後の条件式は検査するので、`<% if foo == nil %>` の `Style/NilComparison` は出る |
| `<% if !foo.nil? then %>` / `<% unless !x %>` | `Style/MultilineIfThen`、`Style/NegatedUnless` が出ない |
| `<%= items.map do \|i\| %>…<% end.join(", ") %>` | 構文エラーになる断片が黙って無視される |
| `<% result = if foo %>…<% end %>` | 同上 |
| `end` の抜け（`cases/syntax/missing_end`） | `Lint/Syntax` を除外しているので出ない |

#### autocorrect が意味・構文を壊す【実測】

| 修正前 | `rubocop -A` 後 | 原因 |
|---|---|---|
| `<% count = items.size %>`⏎`<p><%= count -1 %></p>` | `<%= count(-1) %>` | 前のタグのローカル変数が見えず、`count` をメソッド呼び出しと解釈する（`Lint/AmbiguousOperator`） |
| `<% items.each do \|item\| %>`⏎`<%= item *2 %>` | `<%= item(2) %>` | 同上（`Lint/AmbiguousOperator`, `Lint/RedundantSplatExpansion`） |
| `<% if user && user.admin? %>` | `<% if user&&.admin? %>`（構文エラー） | `Style/SafeNavigation` の修正。rubocop 1.86.1 では正しく `user&.admin?` になる |
| `<%%= link_to "a", a_path %>` | `<%%= link_to 'a', a_path %>` | エスケープしたタグの中身（Ruby ではない文字列）を Ruby として検査する |

`&&.` は rubocop 1.86.2 以降で起きます。1.86.2 で入った fragment ごとの corrector の統合方式（[#14954](https://github.com/rubocop/rubocop/pull/14954)）の副作用と思われますが【推測】、既存の issue は見つかっていません。

## 4. 文書全体を 1 本の Ruby にする方式

### 4.1 ruumba

- リポジトリ: https://github.com/ericqweinstein/ruumba
- 最新: 0.1.17（2021-01-16）。2021-08 以降は push がない。GitHub スター 95（2026-10-06 時点）

erb_lint や rubocop-erb より前からある RuboCop ベースの ERB linter です。

#### 仕組み【出典】

`lib/ruumba/parser.rb` は次のように ERB を Ruby に変換します。

- 正規表現 `/<%[-=]?(.*?)-?%>/m` で ERB タグの中身を取り出す
- HTML とタグの区切りは空白に置き換え、同じ行で続くタグの間にだけ `;` を補う
- 解析の前に `<%==` を `<%= raw` に置き換える

例えば `<% if foo == nil %>⏎  <p>yes</p>⏎<% end %>` は `"   if foo == nil   \n            \n   end   \n"` になります。これを一時ディレクトリに `.rb` として書き出し、`rubocop` コマンドを子プロセスで実行します（`lib/ruumba/rubocop_runner.rb`）。

autocorrect のときは、各タグの中身の前後にマーカー行を挿入してから RuboCop にかけます。修正後のコードからマーカーを手がかりに各タグの中身を切り出し、ERB に書き戻します（`Parser#replace`）。

#### 新たに生じる問題【実測】

タグ単位の方式の見逃し（`Style/NilComparison`、`Style/NegatedIf` など）、`Lint/UselessAssignment` の誤検知、`count(-1)` への書き換えは起きません（[5.1 節](#51-検証用-erb-での結果実測)）。一方で、次の問題が生じます。

**`<%=` の「出力する」という意味が失われる**

| ERB | 結果 |
|---|---|
| `<p><%= total %></p>` | `total` に `Lint/Void` が出る |
| `<% items.each do \|item\| %>`⏎`<%= item.name %>`⏎`<% end %>` | `Style/SymbolProc` が `items.each(&:name)` を提案する。従うと出力がなくなるので、提案自体が誤り |

**HTML 本文が失われる**

| ERB | 結果 |
|---|---|
| `<% if foo == nil %>`⏎`<p>yes</p>`⏎`<% end %>` | `Lint/EmptyConditionalBody` が出る |
| `<% items.each do \|i\| %>`⏎`<li>item</li>`⏎`<% end %>` | `Lint/EmptyBlock` が出る |

ERB では、本文が HTML だけの `if` やブロックはごく普通に書かれるので、日常的に誤検知になります。

**空白で埋めたことによる Layout 系の誤検知**

- `cases/` の 74 ファイルのうち 69 ファイルで、`Layout/TrailingWhitespace` が計 243 件、`Layout/InitialIndentation` が計 65 件出た
- ほかに `Layout/IndentationConsistency`, `Layout/ExtraSpacing`, `Layout/SpaceBeforeSemicolon`, `Layout/BlockAlignment`, `Layout/EndAlignment` なども出る
- `<%= a %><%= b %>` に補った `;` にも `Style/Semicolon` が出る
- `<%%= link_to "a", a_path %>`（エスケープしたタグ。中身は Ruby ではない）も正規表現でタグとして取り出すので、`Lint/Syntax` が出る
- README の推奨設定で無効化しているのは 5 個（FrozenStringLiteralComment, HashAlignment, ParameterAlignment, IndentationWidth, TrailingEmptyLines）だけで、これらは抑えられない

**autocorrect が当てにならない**

- 推奨設定のまま `--auto-correct` すると、`cases/` の 74 ファイルで「1122 offenses corrected」と表示されるが、ERB ファイルは 1 つも書き換わらない。Layout 系の修正でマーカー行がずれ、`Parser#replace` が `nil` を返して黙って書き戻しを諦めるため
- ソースにも "auto-correct is still experimental and can cause invalid ruby to be generated when extracting ruby from ERBs" というコメントがある
- `--only` で Style 系の cop に絞ると修正は反映される（`--only Style/NilComparison,Style/NegatedIf,Style/StringLiterals` で 19 ファイル）。ただし、関係のない `<%== raw_html %>` が `<%= raw raw_html %>` に書き換わる。解析前の `<%==` → `<%= raw` の置換がそのまま書き戻されるため
- autocorrect のときはマーカー行を挿入したコードを検査するので、lint のときとは結果が変わる。例えば `Style/SymbolProc` は autocorrect のときには検出されない（ブロックの中身にマーカー行が入るため）

#### その他【出典】

- RuboCop で非推奨の `--auto-correct` を渡すため、警告が出る
- CLI の `-a` が `--auto-gen-config` と `--auto-correct` の 2 つに重複して定義されている（`bin/ruumba`）
- `<%` の取り出しは正規表現だけで、HTML の構造は見ない

### 4.2 rubocop-erb 0.8 系

#### 経緯【出典】

- 0.8.0 で、Ruby の取り出し方をタグ単位から `Herb.extract_ruby` による文書全体の変換に切り替えた（[r7kamura/rubocop-erb#70](https://github.com/r7kamura/rubocop-erb/pull/70)）
- PR #70 の作者は Cody Cutrer 氏（Instructure）。2026-06 に出され、2026-10-29 に r7kamura 氏がマージして 0.8.0 として公開した。issue [#6](https://github.com/r7kamura/rubocop-erb/issues/6)（タグを跨いだ構文を扱えない）を閉じている
- r7kamura 氏は、Redmine の ERB 534 ファイルで試し、壊れていた autocorrect が正しく動くようになったと述べている
- 同じコメントで、herb 0.9 系と 0.11 系で ERB タグの列の単位（バイト / 文字）が違い、マルチバイト文字を含む行の修正が黙って捨てられる問題を挙げ、0.8.0 で修正した（[#74](https://github.com/r7kamura/rubocop-erb/pull/74)）
- 0.8.1 では `Rails/Presence` を除外した（[#77](https://github.com/r7kamura/rubocop-erb/pull/77)）。`<% if a.present? %><%= a %><% end %>` が `if a.present?; a; end` に見えるため。0.8.2（2026-10-30）では `Layout/EmptyLines` と `Layout/MultilineBlockLayout` を除外した（[#81](https://github.com/r7kamura/rubocop-erb/pull/81), [#82](https://github.com/r7kamura/rubocop-erb/pull/82)）
- PR の説明では、除外した cop は「ERB の文脈を理解させる PR で、今後有効に戻す」としている

0.8 系は、0.7 系の見逃し（`Style/NegatedIf` など）、`Lint/Syntax` の除外、`count -1` を `count(-1)` にするような意味を壊す autocorrect を、いずれも起こしません。0.7 系から上げない理由はありません【推測】。

#### 仕組み【出典】

`lib/rubocop/erb/ruby_extractor.rb`（`lib/` 全体で 386 行）。

- `.erb` のファイルで `Herb.extract_ruby` を呼び、ファイル全体を 1 つの fragment（`offset: 0`）として返す。変換の結果は herb-rubocop-herb と同じで、`<%= foo %>` は `foo  ;`、HTML は空白、`<%# … %>` と `<% # … %>` の中身も空白になる（[1 章](#1-erb-から-ruby-を取り出す-2-つの方式)）
- HTML のマルチバイト文字は、`extract_ruby` が出すバイト数の空白を 1 文字の空白に戻し、文字位置を元の ERB と揃える
- `ERBSource`（`ProcessedSource` のサブクラス）が、元の ERB と `Herb.parse` の結果を持ち、各 ERB タグの範囲を引けるようにする

autocorrect の検査は `lib/rubocop/erb/corrector.rb` で、`RuboCop::Cop::Corrector` に prepend されます。

- 修正の操作ごとに、範囲が 1 つの ERB タグの Ruby の部分（`<%` と `%>` の間）に収まっているかを調べる
- 1 つでも外れる操作があれば、その offense の修正をすべて捨てる（`empty?` が真を返す）。offense は残り、`[Correctable]` の表示も残るが、修正されない
- 例外として、ERB タグで始まる行の行頭のインデントだけを変える空白の修正は通す。`Layout/CaseIndentation` のように範囲が `<%` に掛かるものは、行頭の空白だけに縮める
- 修正の結果を Herb でパースし直したり、HTML を比べたりはしない。範囲だけで判断する

#### 除外している cop【出典】

`config/default.yml` で、`AllCops/Include` に `**/*.erb` を加え、次の 65 個の cop を `**/*.erb` から除外しています。

- Layout 37 個: `ArgumentAlignment`, `ArrayAlignment`, `BlockAlignment`, `ClosingParenthesisIndentation`, `CommentIndentation`, `ElseAlignment`, `EmptyLineAfterGuardClause`, `EmptyLines`, `EmptyLinesAroundBlockBody`, `EndAlignment`, `ExtraSpacing`, `FirstArgumentIndentation`, `FirstArrayElementIndentation`, `FirstArrayElementLineBreak`, `FirstHashElementIndentation`, `FirstHashElementLineBreak`, `FirstMethodArgumentLineBreak`, `FirstParameterIndentation`, `HashAlignment`, `IndentationConsistency`, `IndentationWidth`, `InitialIndentation`, `LeadingEmptyLines`, `LineEndStringConcatenationIndentation`, `LineLength`, `MultilineArrayBraceLayout`, `MultilineAssignmentLayout`, `MultilineBlockLayout`, `MultilineHashBraceLayout`, `MultilineMethodCallBraceLayout`, `MultilineMethodCallIndentation`, `MultilineMethodDefinitionBraceLayout`, `MultilineOperationIndentation`, `ParameterAlignment`, `SpaceBeforeSemicolon`, `TrailingEmptyLines`, `TrailingWhitespace`
- Lint 6 個: `DuplicateBranch`, `EmptyBlock`, `EmptyConditionalBody`, `EmptyFile`, `EmptyWhen`, `Void`
- Style 21 個: `EmptyElse`, `FrozenStringLiteralComment`, `IdenticalConditionalBranches`, `IfInsideElse`, `IfUnlessModifier`, `IfWithSemicolon`, `MultilineTernaryOperator`, `NestedTernaryOperator`, `Next`, `ParallelAssignment`, `RedundantCondition`, `RescueModifier`, `SafeNavigation`, `Semicolon`, `SoleNestedConditional`, `SymbolProc`, `TrailingCommaInArguments`, `TrailingCommaInArrayLiteral`, `TrailingCommaInHashLiteral`, `WhileUntilDo`, `WhileUntilModifier`
- `Rails/Presence`

`Lint/Syntax` と `Lint/UselessAssignment` は除外していません（0.7 系は除外している）。`Style/BlockDelimiters`、`Style/SingleLineDoEndBlock`、`Style/ConditionalAssignment`、`Naming/FileName` も除外していません。

### 4.3 herb-rubocop-herb（marcoroth/herb#2260。herb 公式の rubocop-herb の提案）

herb 本体のリポジトリに提案されている RuboCop プラグイン（[marcoroth/herb#2260](https://github.com/marcoroth/herb/pull/2260)）です。

#### PR の状況【出典】

- 作者は Joel Hawksley 氏（GitHub）。GitHub で erb_lint をやめて Herb に移るにあたり、erb_lint の RuboCop linter の代わりが必要だというのが動機
- Marco Roth 氏の整理では、herb 公式の rubocop-herb gem には 2 つの役割がある。(1) Herb の linter のルールを RuboCop の実行の中で動かす、(2) 設定済みの RuboCop の cop を ERB の中の Ruby に適用する。この PR は (2) だけを実装する
- レビューでは、`Lint/Syntax` と `Lint/Void` を除外しないこと、`Style/WhileUntilDo` と `Lint/OutOfRangeRegexpRef` を除外の一覧から外すことが求められ、反映されている。`Lint/Void` は [marcoroth/herb#1619](https://github.com/marcoroth/herb/issues/1619)（`<%= %>` の中の複数行の Ruby で、演算子の優先順位の誤りを `Lint/Void` が見つけた例）を理由にしている
- 作者は、RuboCop と Herb の「バイト位置と文字位置」の扱いの違いを調べるため、Draft に戻している

#### 仕組み【出典】

`gems/rubocop-herb/lib/rubocop/herb/plugin.rb`（74 行）と `config/default.yml`（108 行）がすべてです。

- `.erb` と `.herb` のファイルで、`Herb.extract_ruby` を呼ぶ。C の lexer が出すトークンを順に見て、ERB タグの中身だけを残し、それ以外を同じバイト数の空白にする。タグの終わりには `;` を補う
- `<%=` も `<%` も空白になる。`<%= foo %>` は、ただの式 `foo;` になる
- `<%# … %>` と、`<% # … %>` のように `#` で始まる 1 行のタグの中身は、空白になる。`<%%` も空白になる
- HTML のマルチバイト文字は、バイト数の空白に置き換わる。`position_preserving_ruby` が元の 1 文字を 1 文字の空白に戻し、文字位置を元の ERB と揃える
- `Extractor` は、ファイル全体を 1 つの fragment として返す。ERB 以外のファイルでは `nil` を返して、RuboCop の通常の処理に任せる。Ruby が空のファイルでは `[]` を返し、何も検査しない
- autocorrect の結果を検査する仕組みはない

`AllCops/Include` に `**/*.erb` と `**/*.herb` を加え、次の 48 個の cop を同じパターンのファイルから除外しています。

- Layout 33 個: `ArgumentAlignment`, `ArrayAlignment`, `BlockAlignment`, `ClosingParenthesisIndentation`, `CommentIndentation`, `InitialIndentation`, `EmptyLineAfterGuardClause`, `EndAlignment`, `FirstArgumentIndentation`, `FirstArrayElementIndentation`, `FirstArrayElementLineBreak`, `FirstHashElementIndentation`, `FirstHashElementLineBreak`, `FirstMethodArgumentLineBreak`, `FirstParameterIndentation`, `HashAlignment`, `IndentationConsistency`, `IndentationWidth`, `LeadingEmptyLine`（存在しない cop 名）, `LeadingEmptyLines`, `LineEndStringConcatenationIndentation`, `LineLength`, `MultilineArrayBraceLayout`, `MultilineAssignmentLayout`, `MultilineHashBraceLayout`, `MultilineMethodCallBraceLayout`, `MultilineMethodCallIndentation`, `MultilineMethodDefinitionBraceLayout`, `MultilineOperationIndentation`, `ParameterAlignment`, `SpaceBeforeSemicolon`, `TrailingEmptyLines`, `TrailingWhitespace`
- Lint 2 個: `EmptyFile`, `EmptyConditionalBody`
- その他: `Metrics/BlockLength`, `Naming/FileName`, `Rails/Presence`, `Style/FrozenStringLiteralComment`, `Style/EmptyElse`, `Style/IdenticalConditionalBranches`, `Style/IfWithSemicolon`, `Style/IfUnlessModifier`, `Style/MultilineTernaryOperator`, `Style/NestedTernaryOperator`, `Style/Next`, `Style/Semicolon`, `Style/WhileUntilModifier`

`Layout/ExtraSpacing`、`Lint/Void`、`Lint/EmptyBlock`、`Lint/EmptyWhen`、`Style/SymbolProc`、`Style/BlockDelimiters`、`Style/SingleLineDoEndBlock` は除外していません。

### 4.4 Herb（herb-lint / herb-format）

- リポジトリ: https://github.com/marcoroth/herb
- 最新: v0.11.1。開発は活発。[rails/rails#58552](https://github.com/rails/rails/pull/58552) で ActionView に Herb ハンドラが追加された

#### できること【出典・実測】

- C 製の HTML+ERB パーサで、HTML と ERB を統合した AST を持つ
- 構文チェックは、HTML を空白に置き換えて各タグの末尾に `;` を補い、Prism で**文書全体を 1 本のプログラムとして**解析する（`src/analyze/parse_errors.c`）
- `end` の抜けを `RUBY_PARSE_ERROR` と `MISSING_ERB_END_TAG_ERROR` で検出する【実測】
- `erb-no-unused-local-variable` はタグを跨いで変数を追跡し、本当に未使用の変数だけを検出する【実測】
- ほかにも ERB の構造を見るルールがある。`erb-no-unused-block-argument`（未使用のブロック引数）、`erb-no-unused-expressions`（`<% count + 1 %>` のように値を捨てる `<%` のタグ）、`erb-no-empty-control-flow`（本当に空の分岐やブロック。本文が HTML なら出ない）など【実測】
- lint ルールは 168 個（146 個がデフォルトで有効）

#### 限界

- **RuboCop を実行しない**。`<%= link_to( 'Home',root_path ) %>` のようなスタイル違反は検出されない【実測】
  - RuboCop 連携は issue [#356](https://github.com/marcoroth/herb/issues/356) で要望されたまま open
  - [#356](https://github.com/marcoroth/herb/issues/356) では Earlopain 氏が「`Herb.extract_ruby` を試したが、空ブロックや余分な空白など誤検出が多すぎる」とコメントしている
- herb-format は、タグ内の Ruby を `trim()` するだけで整形しない。README で "experimental preview" と明記。外部フォーマッタ連携は [#670](https://github.com/marcoroth/herb/issues/670) で要望中
- 型・意味解析はしない。未定義メソッドは検出されない【実測】。Sorbet 連携の要望 [#2285](https://github.com/marcoroth/herb/issues/2285) に対し、作者は「Sorbet 側の仕事」と回答
- linter は Node 製で、Ruby のツール（RuboCop, Ruby LSP）とは連携できない

## 5. 同じ入力での比較

### 5.1 検証用 ERB での結果【実測】

[repro/cases/](repro/cases/) の 74 ファイルに、各ツールをかけた結果です（`bin/lint TOOL`。結果の全体は [repro/results/lint/](repro/results/lint/)）。tk0miya-rubocop-herb は `Herb/Linting` を外しています。

| | erb_lint（全 cop） | erb_lint（推奨設定） | rubocop-erb 0.7.2 | ruumba | rubocop-erb 0.8.2 | herb-rubocop-herb | tk0miya-rubocop-herb |
|---|---|---|---|---|---|---|---|
| offense の数 | 335 | 43 | 46 | 518 | 65 | 283 | 87 |

主なケースの結果です。「誤」は誤検知、「—」は何も出ないことを表します。

| ケース | erb_lint（推奨設定） | rubocop-erb 0.7.2 | ruumba | rubocop-erb 0.8.2 | herb-rubocop-herb | tk0miya-rubocop-herb |
|---|---|---|---|---|---|---|
| `control_flow/nil_comparison`（`<% if foo == nil %>`、本文は HTML） | — | `Style/NilComparison` | `Style/NilComparison`、`Lint/EmptyConditionalBody`（誤） | `Style/NilComparison` | `Style/NilComparison` | `Style/NilComparison` |
| `control_flow/negated_if`（`<% if !user.nil? %>`） | — | — | `Style/NegatedIf`、`Lint/EmptyConditionalBody`（誤） | `Style/NegatedIf` | `Style/NegatedIf` | `Style/NegatedIf` |
| `control_flow/if_then_elsif_else`（`then`、`elsif bar == nil`、本当に空の `else` と `unless !x`） | — | `Style/NilComparison` だけ | `Style/MultilineIfThen`、`Style/NilComparison`、`Style/NegatedUnless`、`Style/EmptyElse` と、`Lint/EmptyConditionalBody` 3 件（うち 2 件は HTML の本文への誤検知） | `Style/MultilineIfThen`、`Style/NilComparison`、`Style/NegatedUnless`（空の本文は除外） | 0.8.2 と同じ | 0.8.2 の 3 つと、`Style/EmptyElse`、`Lint/EmptyConditionalBody` |
| `control_flow/unused_block_arg`（`\|i\|` が未使用、本文は HTML） | — | — | `Lint/EmptyBlock`（誤） | — | `Lint/EmptyBlock`（誤） | `Lint/UnusedBlockArgument` |
| `control_flow/case_when`（`when` の本文が HTML） | — | — | `Lint/EmptyWhen`（誤） | — | `Lint/EmptyWhen`（誤） | — |
| `control_flow/single_line_block`（1 行の `<%= cache … do %>…<% end %>`） | — | — | `Style/SingleLineDoEndBlock` など（誤） | `Style/SingleLineDoEndBlock`、`Style/BlockDelimiters`（誤） | 0.8.2 と同じと `Lint/EmptyBlock`（誤） | — |
| `control_flow/cond_assign`（各分岐で `<% x = 1 %>`） | — | — | `Style/ConditionalAssignment`（ERB に合わない） | 同左 | 同左 | — |
| `control_flow/safe_navigation`（`<% if user && user.admin? %>`） | — | `Style/SafeNavigation`（`-A` で構文エラー） | `Style/SafeNavigation` | —（除外） | `Style/SafeNavigation` | `Style/SafeNavigation` |
| `variables/cross_tag_variables`（使う変数と、未使用の `unused`） | — | — | `Lint/UselessAssignment`、`Lint/Void`（誤）、`Style/SymbolProc`（誤） | `Lint/UselessAssignment` | ruumba と同じ | `Lint/UselessAssignment` |
| `variables/ambiguous_operator`（`<%= count -1 %>`、`count` は前のタグの変数） | `Lint/AmbiguousOperator`（誤） | `Lint/AmbiguousOperator`（誤） | `Layout/SpaceAroundOperators`、`Lint/Void`（誤） | `Layout/SpaceAroundOperators` | ruumba と同じ | `Layout/SpaceAroundOperators` |
| `marker/symbol_proc_ok`（`<li><%= item.name %></li>` を出力するブロック） | — | — | `Style/SymbolProc`（誤） | — | `Style/SymbolProc`（誤） | — |
| `output/symbol_proc_map`（`users.map { \|u\| u.name }`） | `Style/SymbolProc` | `Style/SymbolProc` | `Style/SymbolProc` | —（除外） | `Style/SymbolProc` | `Style/SymbolProc` |
| `output/escaped_tag`（`<%%= link_to "a", a_path %>` の行） | — | `Style/StringLiterals`（誤） | `Lint/Syntax`（誤） | — | — | — |
| `syntax/missing_end`（`end` の抜け） | — | —（除外） | `Lint/Syntax` | `Lint/Syntax` | `Lint/Syntax` | `Lint/Syntax` |
| `syntax/syntax_errors_ignored`（`<% end.join(", ") %>` など） | — | — | `Lint/UselessAssignment` と `Lint/EmptyConditionalBody`（誤） | `Lint/UselessAssignment` | `Lint/UselessAssignment` | `Lint/UselessAssignment` |
| `comment/ruby_comment`（`<% # note %>`） | — | `Style/CommentAnnotation` | `Style/CommentAnnotation` | —（空白になる） | — | — |
| `comment/commented_out_output`（`<% name = user.name # … %><%= name %>`） | — | — | `Lint/UselessAssignment` | `Lint/UselessAssignment` | `Lint/UselessAssignment` | `Lint/UselessAssignment` |

- erb_lint の全 cop の設定では、このほかに `Lint/UselessAssignment` の誤検知と、タグごとの `Style/FrozenStringLiteralComment` などが出る（[3.1 節](#31-erb_lintrubocop-linter)）
- ruumba は、このほかに Layout 系の誤検知が多数出る（[4.1 節](#41-ruumba)）。herb-rubocop-herb は、ほぼすべての ERB タグに `Layout/ExtraSpacing` が出る（187 件）
- `comment/commented_out_output` の `Lint/UselessAssignment` は誤検知ではない。ERB はテンプレートを行を保ったまま Ruby にコンパイルするので、行末のコメントは後ろの `<%= name %>` までコメントにし、`name` は本当に使われない。文書全体を変換するツールはどれもこれを再現する。この書き方自体は、herb-lint の `erb-no-trailing-comment` ルール（[marcoroth/herb#2871](https://github.com/marcoroth/herb/pull/2871)。`@herb-tools/linter` 0.11.2 で入った。検証環境の 0.11.1 にはない）が報告する
- herb-lint（`bin/lint herb-lint`）は RuboCop の cop を実行しないので、`Style/NilComparison` などは出ない。`end` の抜け、未使用の変数とブロック引数、本当に空の分岐は検出する（[4.4 節](#44-herbherb-lint--herb-format)）

herb-rubocop-herb と tk0miya-rubocop-herb で、`Layout/ExtraSpacing` を除いて片方にだけ出る offense をまとめると、次のようになります。

| cop | herb-rubocop-herb だけ | tk0miya-rubocop-herb だけ |
|---|---|---|
| `Lint/Void` | 7 ファイル。`<p><%= total %></p>`、`<%= user.name.nil? ? "anon" : user.name %>` など、出力する式（誤） | |
| `Style/SymbolProc` | 4 ファイル。出力するブロック（誤） | |
| `Lint/EmptyBlock`、`Lint/EmptyWhen`、`Style/SingleLineDoEndBlock`、`Style/BlockDelimiters`、`Style/ConditionalAssignment` | 本文が HTML のブロックや分岐（誤） | |
| `Style/SafeNavigation`、`Style/SoleNestedConditional`、`Lint/DuplicateBranch`、`Style/CombinableLoops` | ERB として正しいテンプレート（誤。[5.2 節](#52-erb-として正しいものと直すべきものの区別)） | |
| `Lint/LiteralAsCondition`、`Style/StringLiterals`、`Lint/CopDirectiveSyntax` | 無効化コメントが効かない（[6 章](#6-無効化コメント)） | |
| `Lint/UnusedBlockArgument`、`Style/EmptyElse`、`Lint/EmptyConditionalBody`、`Style/IdenticalConditionalBranches` | | 本当に未使用の引数、本当に空の分岐、分岐の外に移せる出力（herb-rubocop-herb はファイル全体で除外しているか、本文を空と見なす） |
| `Lint/MissingCopEnableDirective` | | 効いた無効化コメント |
| `Herb/IgnoredCopDirective` | | tk0miya-rubocop-herb の cop |

マルチバイト文字（`cases/multibyte/`）を含むテンプレートでは、文書全体を変換するツールはどれも、offense の位置が正しく、`-a` の結果も元の位置に書き戻されます。tk0miya-rubocop-herb では、`<%-` / `-%>` のタグ（`control_flow/trim`）や属性値の中のタグ（`output/attr`）も位置がずれずに修正され、`<%= form_with … do |f| %>…<% end %>`（`control_flow/form_block`）は変更されません。

### 5.2 ERB として正しいものと直すべきものの区別

`Herb.extract_ruby` は、ERB タグの中身以外をすべて空白にします。`<%= x %>` と `<% x %>` は同じ Ruby になり、HTML だけを本文に持つブロックと、本当に空のブロックも同じ Ruby になります。

[repro/cases/marker/](repro/cases/marker/) に、cop ごとに、ERB として正しいテンプレート（`*_ok`）と、同じ形で本当に直すべきテンプレート（`*_ng`）を 1 つずつ置きました【実測】。

| cop | `*_ok`（ERB として正しい） | `*_ng`（直すべき） |
|---|---|---|
| `Lint/Void` | `<p><%= count + 1 %> items</p>` | `<p><% count + 1 %> items</p>`（`=` の書き忘れ） |
| `Style/SymbolProc` | `<% items.each do \|item\| %>` `<li><%= item.name %></li>` `<% end %>` | `<% items.each do \|item\| %>` `<% item.touch %>` `<% end %>` |
| `Lint/EmptyBlock` | `<% items.each do %>` `<li>item</li>` `<% end %>` | `<% items.each do %>` `<% end %>` |
| `Lint/EmptyConditionalBody` | `<% if user.admin? %>` `You are an administrator.` `<% end %>` | `<% if user.admin? %>` `<% end %>` |
| `Style/EmptyElse` | `<% else %>` `You are not an administrator.` `<% end %>` | `<% else %>` `<% end %>` |
| `Style/SafeNavigation` | `<% if user %>` `Last login: <% user.touch %>` `<% end %>` | `<% if user %>` `<% user.touch %>` `<% end %>` |
| `Style/SoleNestedConditional` | 外側の `if` の本文に `Welcome!` と内側の `if` | 外側の `if` の本文が内側の `if` だけ |
| `Lint/DuplicateBranch` | `Good morning, <%= user.name %>` と `Hello, <%= user.name %>` | `<%= user.name %>` と `<%= user.name %>` |
| `Style/CombinableLoops` | 2 つの `items.each` の間に `Prices:` | 2 つの `items.each` が連続 |

各ツールで、その cop が `*_ok` と `*_ng` のどちらに出たかです（`Layout` と、`Style/FrozenStringLiteralComment`、`Style/Semicolon`、`Style/StringLiterals` を除いて実行した。`rubocop-erb-0.8-noexclude` は 0.8.2 の除外を外した設定）。

| cop | 0.8.2 | 0.8.2（除外を外す） | herb-rubocop-herb | tk0miya-rubocop-herb |
|---|---|---|---|---|
| `Lint/Void` | 出ない（除外） | 両方 | 両方 | `*_ng` だけ |
| `Style/SymbolProc` | 出ない（除外） | 両方 | 両方 | `*_ng` だけ |
| `Lint/EmptyBlock` | 出ない（除外） | 両方 | 両方 | `*_ng` だけ |
| `Lint/EmptyConditionalBody` | 出ない（除外） | 両方 | 出ない（除外） | `*_ng` だけ |
| `Style/EmptyElse` | 出ない（除外） | 両方 | 出ない（除外） | `*_ng` だけ |
| `Style/SafeNavigation` | 出ない（除外） | 両方 | 両方 | `*_ng` だけ |
| `Style/SoleNestedConditional` | 出ない（除外） | 両方 | 両方 | `*_ng` だけ |
| `Lint/DuplicateBranch` | 出ない（除外） | 両方 | 両方 | `*_ng` だけ |
| `Style/CombinableLoops` | 両方 | 両方 | 両方 | `*_ng` だけ |

- 0.8.2 の除外を外すと、9 組すべてで `*_ok` と `*_ng` に同じ cop が出る。変換後の Ruby が同じなので、cop には区別する手がかりがない
- 0.8.2 は 8 個を除外しているので、`*_ng` の 8 件を見逃す。除外していない `Style/CombinableLoops` は `*_ok` にも出る（`-a` では修正されない）
- herb-rubocop-herb は `Lint/EmptyConditionalBody` と `Style/EmptyElse` を除外し、ほかの 7 組では `*_ok` にも出る
- tk0miya-rubocop-herb は 9 組すべてで `*_ng` だけに出る。このほか、`duplicate_branch_ok` の 2 つの `<%= user.name %>` に `Style/IdenticalConditionalBranches` が出る。どちらの分岐も最後が同じ出力タグなので、分岐の後ろに 1 つにまとめられる。妥当な指摘で、autocorrect はされない
- RuboCop ではない herb-lint（`bin/lint herb-lint cases/marker`）は、HTML を空白にせずに ERB の構造を見るので、ルールのある組では `*_ng` だけに出る。`erb-no-empty-control-flow` が空のブロック・`if`・`else` の 3 組、`erb-no-unused-expressions` が `<% count + 1 %>` と `<% item.touch %>`、`erb-no-duplicate-branch-elements` が同じ内容の分岐に出る。ただし `erb-no-unused-expressions` は、値を使わない `<% user.touch %>` を `safe_navigation_ok` でも指摘する
- 0.8.2 の除外を外したときは、このほかに `Style/IfWithSemicolon`（`if user;` を三項演算子にせよ）と `Style/IfUnlessModifier` も `*_ok` と `*_ng` の両方に出る。どちらも、タグの終わりに補った `;` や、空白にした本文から生じる

区別できない以上、空白にする方式で取れる道は 2 つしかありません。両方を報告するか（誤検知）、cop ごと止めるか（見逃し）です。herb-rubocop-herb は前者に近く、0.8.2 は後者です。tk0miya-rubocop-herb は `<%=` と HTML の存在を Ruby に書き込むので、2 つが別の Ruby になります（[第 2 部 3 章](tk0miya-rubocop-herb.md#3-なぜ--と-html-を-ruby-として描画するのか)）。

### 5.3 autocorrect【実測】

検証用 ERB（74 ファイル）と実際のビュー（333 ファイル）で、`-a` と `-A` の前後を比べた結果です（`bin/autocorrect`。[html_changes.rb](repro/bin/html_changes.rb) で、HTML は空白の違いを無視して比べる。結果の全体は [repro/results/autocorrect/](repro/results/autocorrect/) と [repro/results/views/](repro/results/views/)）。

| | 検証用 ERB: 書き換わった / HTML が変わった / パースエラーが増えた | 実際のビュー: 書き換わった / HTML が変わった / パースエラーが増えた |
|---|---|---|
| erb_lint（全 cop）`-a` | 49 / 49 / 49 | — |
| erb_lint（推奨設定）`-a` | 25 / 6 / 6 | — |
| rubocop-erb 0.7.2 `-a` | 25 / 0 / 0 | 143 / 0 / 0 |
| rubocop-erb 0.7.2 `-A` | 27 / 0 / 1 | 143 / 0 / 2 |
| ruumba `--auto-correct` | 0 / 0 / 0（黙って書き戻さない） | — |
| rubocop-erb 0.8.2 `-a` | 26 / 0 / 0 | 143 / 0 / 0 |
| rubocop-erb 0.8.2 `-A` | 26 / 0 / 0 | 145 / 0 / 0 |
| herb-rubocop-herb `-a` | 67 / 22 / 17 | 251 / 63 / 59 |
| herb-rubocop-herb `-A` | 67 / 25 / 17 | 251 / 63 / 56 |
| tk0miya-rubocop-herb `-a` | 31 / 9 / 0 | 140 / 0 / 0 |
| tk0miya-rubocop-herb `-A` | 37 / 9 / 0 | 142 / 0 / 0 |

- rubocop-erb 0.7.2 の `-A` でパースエラーが増えたのは `control_flow/safe_navigation`（`user&&.admin?`）
- tk0miya-rubocop-herb の検証用 ERB の値は `Herb/Linting` を含み、HTML が変わった 9 ファイルは、どれも herb-lint の修正（`<%= "hello" %>` を `hello` にする `erb-prefer-direct-output` など）によるもの。`Herb/Linting` を外すと `-a` が 26 / 0 / 0、`-A` が 31 / 0 / 0 になる。実際のビューの値は `Herb/Linting` を外したもので、含めると `-a` が 232 / 30 / 0、`-A` が 234 / 30 / 0（herb-lint 単体の `--fix` でも、HTML が変わるのは 30 ファイル）。[第 2 部 7.1 節](tk0miya-rubocop-herb.md#71-herblinting)
- `html_changes.rb` は HTML とパースエラーしか見ないので、Ruby の意味が変わる修正（`count(-1)`、出力がなくなる `Style/SymbolProc` など）は数えていない

修正の中身です。

| 修正前 | 結果 |
|---|---|
| `<%= link_to "x", path, class: 'btn' %>` | erb_lint（全 cop）: `<%=` が消え、`# frozen_string_literal: true` が HTML 本文に入る |
| `<%`⏎`  x = 1`⏎`  y = 2`⏎`%>` | erb_lint（推奨設定）: `<%` が消える |
| `<% count = items.size %>`⏎`<p><%= count -1 %></p>` | erb_lint / rubocop-erb 0.7.2: `count(-1)`（意味が変わる）。0.8.2 / tk0miya-rubocop-herb: `count - 1` |
| `<% if user && user.admin? %>` | rubocop-erb 0.7.2 `-A`: `user&&.admin?`（構文エラー）。0.8.2: 変わらない（除外）。tk0miya-rubocop-herb `-A`: `user&.admin?` |
| `<%== raw_html %>` | ruumba（`--only` で Style に絞ったとき）: `<%= raw raw_html %>` |
| `<td><%= user.name %></td><td><%= user.email %></td>` | herb-rubocop-herb `-a`: `<td><%= user.name%> user.email%></td>` |
| `<% if a %>A<% else %>B<% end %>` | herb-rubocop-herb `-a`: `<% if a%> else%> end%>` |
| `<% total = items.sum(&:price) %>`⏎`<p><%= total %></p>`⏎`<% unused = 1 %>`⏎（ループ） | herb-rubocop-herb `-a`: `<% items.sum(&:price)%>%></p>%>`⏎…。0.8.2 `-A`: `<% unused = 1 %>` が `<% 1 %>` になって残る（`Lint/Void` を除外しているので、offense も出ない）。tk0miya-rubocop-herb `-a`: `<% unused = 1 %>` の行が消える |
| `<% end.join(", ") %>`、`<% result = if foo %>`（`syntax/syntax_errors_ignored`） | erb_lint（推奨設定）/ 0.7.2: 変わらない（黙って飛ばす）。0.8.2 / tk0miya-rubocop-herb: `", "` が `', '` になり、`-A` では使われていない `result =` も消える。tk0miya-rubocop-herb では、さらに `Herb/Linting` が `<%= items.map do |i| %>` を `<% items.map do |i| %>` にする（herb-lint の `erb-no-output-control-flow`） |
| `<%= cache "fragment" do %>This bit is cached<% end %>` | 0.8.2 `-a`: `<%= cache 'fragment' do`⏎` %>This bit is cached<% `⏎`end %>`（出力は変わらないが、タグの中に改行が入る）。tk0miya-rubocop-herb: `'fragment'` だけ |
| `<% unless a %>`…`<% else %>`…`<% end %>`（本文に HTML） | 0.8.2、tk0miya-rubocop-herb: `Style/UnlessElse` の修正は捨てられる |

herb-rubocop-herb が壊す理由【実測・出典】:

- `two_tags_line` と `inline_if` は `Layout/ExtraSpacing` の修正。同じ行の 2 つの ERB タグの間（`%></td><td><%=` や `%>A<%`）は、Ruby では `;` と次の式の間の空白に見えるので、まとめて削除される
- `cross_tag_variables` は `Lint/Void` と `Lint/UselessAssignment` の修正。`<%= total %>` の `total` などを前後の空白ごと削除するときに、`%></p>` や次の行の `<%` も消える
- 修正対象ではないタグでも、`%>` の前の空白が `Layout/ExtraSpacing` で削除される（`<% end %>` → `<% end%>`）
- `-A` では、さらに `Style/SymbolProc` で、出力するブロックが `<% items.each(&:name)%>` になり、出力がなくなる。`marker/` の ERB として正しい側では、`Last login: <% user.touch %>` が `<% user&.touch%>` に、`<% if user %>` 以降がすべて消える（`Style/SoleNestedConditional`）などの例がある

herb-rubocop-herb の誤検知と壊れる autocorrect は、変換の段階で `<%=` の意味と HTML の存在を落としていることから生じています。除外する cop を増やせば `Layout/ExtraSpacing` などは止められますが、`Lint/Void` のように除外しないと決めた cop では、出力する式の誤検知が残ります。`Layout/ExtraSpacing` は RuboCop の既定で有効なので、herb-rubocop-herb を既定の設定で入れて `rubocop -a` を実行すると、同じ行に ERB タグが 2 つ以上あるテンプレートが壊れます。修正後の ERB を検査する仕組みがない限り、autocorrect を安全に使えません【推測】。

0.8.2 の修正範囲の検査は単純ですが効果が大きく、herb-rubocop-herb を壊していた `Layout/ExtraSpacing` や `Lint/Void` の修正は、どれも範囲が ERB の区切りや HTML に掛かるので捨てられます【推測】。ただし範囲しか見ないので、範囲がタグの中に収まる限り、ERB に合わない修正（`Style/SingleLineDoEndBlock` の改行の挿入）や、`<%= foo %>` の式を消すような修正も通ります。

### 5.4 実際のビュー【実測】

rails/rails と kaigionrails/conference-app の `*.html.erb`（333 ファイル）にかけた結果です（`bin/record-views`。tk0miya-rubocop-herb は `Herb/Linting` を外した）。

| | rubocop-erb 0.7.2 | rubocop-erb 0.8.2 | herb-rubocop-herb | tk0miya-rubocop-herb |
|---|---|---|---|---|
| offense の数 | 762 | 763 | 2,455 | 933 |
| offense のあるファイル | 143 | 151 | 252 | 165 |
| `-A` の後に残る offense | — | 9 | — | 194（うち `Layout/LineLength` 166） |
| 実行時間（`--cache false`、検出のみ） | 5.6 秒 | 2.0 秒 | 1.8 秒 | 3.0 秒 |

#### rubocop-erb 0.7.2 と 0.8.2 の違い

- 0.7.2 だけに出るもの: `Style/StringLiterals` 18 件は、rails の認証ジェネレーターのテンプレート（`passwords/edit.html.erb` など 3 ファイル）の `<%%= form.submit "Save" %>` の中身。`<%%=` は `<%=` という文字列を出力するエスケープで、中身は Ruby ではない。**0.7.2 は `-a` でこれを `'Save'` に書き換え、ジェネレーターが生成するコードを変える**。`html_changes.rb` は `<%%` をテキストとして比べないので、この変化を数えていない
- 0.7.2 だけに出るもの: `Layout/ExtraSpacing` 6 件と `Layout/SpaceBeforeFirstArg` 2 件（`<%= render              "header" %>` など。0.8.2 は `Layout/ExtraSpacing` を除外）、`Style/SafeNavigation` 2 件と `Style/SymbolProc` 1 件（0.8.2 は除外）
- 0.7.2 の `-A` は、`<% if @part && @part.mime_type %>` を `@part&&.mime_type`（構文エラー）に、`<%= !!user_bookmarks.find { … } %>` を `!user_bookmarks.find { … }.nil?.nil?`（常に `true`）に書き換える
- 0.8.2 だけに出るもの: `Lint/AssignmentInCondition` 3 件、`Lint/LiteralAsCondition` 2 件、`Naming/VariableNumber` 2 件、`Style/HashEachMethods` 1 件、`Lint/Syntax` 1 件（rails の `syntax_error.html.erb`。わざと構文エラーにした fixture）。いずれもタグを跨いで読めるようになったことによるもので、tk0miya-rubocop-herb にも同じものが出る
- 0.8.2 だけに出るもの: `Naming/FileName` 3 件（`_FooBar.html.erb`、`_a-in.html.erb`、`hello_world.pt-BR.html.erb`）。0.7.2 はタグ 1 つを 1 ファイルとして検査するので出ない。tk0miya-rubocop-herb は ERB で除外している
- 0.8.2 だけに出るもの: `Style/SingleLineDoEndBlock` 10 件、`Style/BlockDelimiters` 8 件。8 ファイルとも、rails のテスト用 fixture の `<%= cache "fragment" do %>This bit's fragment cached<% end %>` のように、1 行に書いた本文が HTML のブロック。`Style/BlockDelimiters` の `{ … }` にせよという指摘は、ERB では従えない（herb-lint の `erb-prefer-do-end-blocks` も `do`〜`end` を勧める）。`Style/SingleLineDoEndBlock` の修正は検査を通り、`-a` で 8 ファイルにタグの中の改行が入る

#### rubocop-erb 0.8.2 と tk0miya-rubocop-herb の違い

| cop | 0.8.2 | tk0miya-rubocop-herb | 内容 |
|---|---|---|---|
| `Layout/LineLength` | 0 | 162 | 0.8.2 は除外（下記） |
| `Lint/EmptyFile` | 0 | 16 | 0.8.2 は除外（下記） |
| `Layout/ExtraSpacing` | 0 | 4 | 0.8.2 は除外。タグの中に書いた余分な空白（`<%= render    partial:  "form" %>`、`<%=  @live_streams[:day1][:red_ja] %>` など）で、妥当な指摘 |
| `Layout/HashAlignment` | 0 | 3 | 0.8.2 は除外。複数行に渡る `link_to` の引数の揃え |
| `Lint/EmptyBlock` | 0 | 2 | 0.8.2 は除外。2 件とも本当に空のブロック（`<%= check_box_tag … do %>`⏎`<% end %>` など） |
| `Style/SymbolProc` | 0 | 1 | 0.8.2 は除外。`<%= local_assigns.keys.map {\|k\| k.to_s }.sort.join(",") -%>` で、妥当な指摘 |
| `Style/SafeNavigation` | 0 | 1 | 0.8.2 は除外。`<% if @part && @part.mime_type %>` で、妥当な指摘 |
| `Style/RescueModifier` | 0 | 1 | 0.8.2 は除外。`<% corrections = exception_wrapper.corrections rescue [] %>`。tk0miya-rubocop-herb は `-a` で `begin`〜`end` に展開する |
| `Style/IfUnlessModifier` | 0 | 1 | 0.8.2 は除外。`<%= '\|' unless names.last == name %>` の行（HTML を含めて 121 桁）に、修飾子の `unless` で行が長すぎると出る。`-a` では修正されない |
| `Style/SingleLineDoEndBlock` | 10 | 0 | 上記 |
| `Style/BlockDelimiters` | 8 | 0 | 上記 |
| `Naming/FileName` | 3 | 0 | tk0miya-rubocop-herb は除外。`hello_world.pt-BR.html.erb` はロケール付きのテンプレートで、Rails はこの名前で探すので名前を変えられない。`_FooBar.html.erb` と `_a-in.html.erb` は、大文字やハイフンを含む partial 名を確かめる rails のテスト用 fixture |

`Lint/Syntax` は両方に 1 件出ます（同じファイルで、報告する位置が違う）。

#### herb-rubocop-herb と tk0miya-rubocop-herb の違い

| cop | herb-rubocop-herb | tk0miya-rubocop-herb | 内容 |
|---|---|---|---|
| `Layout/ExtraSpacing` | 1,606 | 4 | herb-rubocop-herb は、`%>` が `;` の前の空白になることによる誤検知。tk0miya-rubocop-herb の 4 件は、タグの中に書いた余分な空白 |
| `Lint/Void` | 50 | 0 | 変数 29 件（`<%= event.name %>` など）、リテラル 20 件（`<%= event.ongoing? ? "true" : "" %>`、`<%= ' current' if page.current? %>` など）、演算子 1 件。いずれも出力する式 |
| `Lint/EmptyBlock` | 30 | 2 | herb-rubocop-herb の 28 件は、本文が HTML だけのブロック（`<%= link_to path do %>…<% end %>` など）。2 件は両方に出る、本当に空のブロック |
| `Style/SingleLineDoEndBlock`, `Style/BlockDelimiters` | 10, 8 | 0, 0 | 1 行に書いた、本文が HTML のブロック |
| `Layout/LineLength`、`Lint/EmptyFile` | 0 | 162、16 | herb-rubocop-herb は除外 |

`Lint/Void` の誤検知には、[marcoroth/herb#1619](https://github.com/marcoroth/herb/issues/1619) のもとになった rails の `active_storage/blobs/_blob.html.erb`（`<%= blob.representable? ? "preview" : "file" %>`）も含まれます。

#### rubocop-erb 0.8.2 の除外で何が消えているか

0.8.2 が `**/*.erb` から除外している 65 個の cop のうち 64 個（`Rails/Presence` は rubocop-rails を入れていないので除く）だけを、除外を外した設定（[repro/tools/rubocop-erb-0.8/erb-noexclude.yml](repro/tools/rubocop-erb-0.8/erb-noexclude.yml)。`bin/lint rubocop-erb-0.8-noexclude`）と tk0miya-rubocop-herb でかけました。64 個の cop で、除外を外した 0.8.2 は 9,310 件、tk0miya-rubocop-herb は 282 件です。

内容に関わる cop の結果です。妥当かどうかは、1 件ずつテンプレートを見て判断しました。

| cop | 0.8.2（除外を外す） | うち妥当 | tk0miya-rubocop-herb | 0.8.2 の誤検知の内容 |
|---|---|---|---|---|
| `Lint/Void` | 50 | 0 | 0 | `<%= event.name %>` などの出力する式 |
| `Lint/EmptyBlock` | 30 | 2 | 2 | 本文が HTML だけのブロック（`<%= link_to path do %>…<% end %>` など） |
| `Style/IfUnlessModifier` | 17 | 1 | 1 | 本文が HTML と出力タグの `if` |
| `Lint/EmptyFile` | 16 | 16 | 16 | （0 バイトのテンプレート。すべて妥当） |
| `Lint/EmptyConditionalBody` | 4 | 0 | 0 | 本文が HTML だけの `if` |
| `Style/Next` | 4 | 0 | 0 | ループの本文の `if` が HTML を出す。ERB では `<% next unless … %>` にする理由がない |
| `Style/SafeNavigation` | 3 | 2 | 1 | `<% if @routes_inspector %>` の本文が HTML |
| `Style/EmptyElse` | 2 | 0 | 0 | 本文が HTML だけの `else` |
| `Style/RedundantCondition` | 2 | 0 | 0 | `<% if x %>#<%= x %><% end %>`（`#` が空白になる） |
| `Style/SymbolProc` | 2 | 1 | 1 | `<%= form_with(url: "/") do \|f\| %><%= f.message %><% end %>` |
| `Style/RescueModifier` | 1 | 1 | 1 | |
| 合計 | 131 | 23 | 22 | |

- tk0miya-rubocop-herb の 22 件は、どれも 0.8.2 が除外で捨てている妥当な指摘
- `Style/SafeNavigation` の妥当な 2 件のうち、`<%= @request.parameters["controller"].camelize if @request.parameters["controller"] %>` は tk0miya-rubocop-herb では出ない（[第 2 部 3.3 節](tk0miya-rubocop-herb.md#33-マーカーの限界実測出典)）
- 内容に関わらない cop では、0.8.2 の除外を外すと、`Style/Semicolon` が 1,554 件、`Style/FrozenStringLiteralComment` が 254 件、`Style/IfWithSemicolon` が 62 件、`Layout` の 15 個の cop が計 7,308 件出る。どれも、タグの終わりに補った `;` や、空白にした HTML と ERB の区切りから生じる。tk0miya-rubocop-herb は、このうち `Style/FrozenStringLiteralComment` と `Layout` の 5 個を除外し、`Style/Semicolon`、`Style/IfWithSemicolon`、`Layout/TrailingWhitespace`、`Layout/ExtraSpacing` は変換で書いた文字への指摘だけを除き、残りの多くは誤検知になる行だけで無効にしている（[第 2 部 5 章](tk0miya-rubocop-herb.md#5-erb-で止めている-cop出典)）。`Layout/LineLength`（162 件）、`Layout/ExtraSpacing`（4 件）、`Layout/HashAlignment`（3 件）は tk0miya-rubocop-herb でも出る

誤検知が 8 割を超える cop を除外するのは、空白にする方式では合理的な判断です。ただしその判断は、`<% count + 1 %>`（`=` の書き忘れ）や本当に空の `else` も見逃すことと引き換えです【推測】。

#### tk0miya-rubocop-herb だけに出る指摘の内容

**`Layout/LineLength`**: tk0miya-rubocop-herb は、ERB タグを含む行について、HTML も含めた行全体の長さを測ります。ERB タグを含まない行と、`<%%` だけの行（テキスト）は測りません。162 件を、行のうち ERB タグ（`<%` 〜 `%>`）が占める長さで分けると、次のようになります。

| 区分 | 件数 | 例 |
|---|---|---|
| ERB タグ 1 つだけで 120 桁を超える | 86（conference-app 81） | `<%= f.select :status, Announcement.statuses, {}, class: "block rounded-sm border-1 cursor-pointer disabled:bg-gray-200 …", disabled: @announcement.published? %>`（タグだけで 191 桁） |
| 周りの HTML を除いても、ERB タグとインデントで超える | 23 | `<%= f.color_field :border_color_code, class: "block mb-4", data: { action: "…" } %>` |
| 周りの HTML を含めると超える | 53 | `<span class="rounded-xl bg-theme-primary-300 px-3 text-sm ml-2"><%= current_user!.unread_announcement_count %></span>`（131 桁のうちタグは 46 桁） |

- 前の 2 つ（109 件）は、Tailwind の長い `class:` の文字列をヘルパーに渡しているものがほとんど。ERB タグの中の Ruby を引数ごとに改行すれば短くできる
- 残りの 53 件は、タグの外の HTML を改行すれば短くできる（属性を 1 行に 1 つずつ並べるなど）。RuboCop では autocorrect できないが、Herb の formatter（`herb-format`）が `maxLineLength` で属性やテキストを折り返す
- `herb-format` の `maxLineLength` の既定値は 80（`javascript/packages/formatter/src/options.ts`）で、`Layout/LineLength` の既定値 120 と異なる
- ERB タグの中の引数の後ろで改行すると、行は短くならず `%>` が次の行に移る。ガードはこの修正を捨てて指摘だけを残すので、上の `f.select` の行は `-a` でも変わらない。ガードを通って適用される修正（`Layout/LineLength` だけをかけた `-a` で 7 ファイルの 12 件）には、ERB に合わない形が残る（[第 2 部 8 章](tk0miya-rubocop-herb.md#8-既知の問題実測推測)）

- 120 桁は RuboCop の既定値で、conference-app は RuboCop を導入していない

**`Lint/EmptyFile`**:

- 16 件とも 0 バイトのテンプレート。HTML だけのテンプレート、改行だけのテンプレート、`<%# … %>` だけのテンプレートには出ない。Ruby のファイルと同じく、0 バイトのときだけ出る
- conference-app の `admin/signage_devices/edit.html.erb` は、ルーティング（`resources :signage_devices, only: [:new, :create, :edit, :update]`）とコントローラーの `edit` があるのに、テンプレートが空。編集画面が空のページになる
- rails の 15 件は、空のテンプレートの描画を確かめるテスト用の fixture（actionmailer のメールのパート、actionview の digestor のテストなど）

これらの指摘に対する評価は [第 2 部 8 章](tk0miya-rubocop-herb.md#8-既知の問題実測推測) にまとめます。

### 5.5 指摘の表示【実測・出典】

- 指摘の行の表示（`--format clang` などのソースの抜粋とキャレット）は、0.7.2、0.8.2、tk0miya-rubocop-herb とも元の ERB の行になる。HTML やマルチバイト文字を含む行でも、HTML は空白にならず、キャレットの位置も同じ（`multibyte/show`）
  - RuboCop 1.92 は、extractor が返した fragment で見つかった offense の範囲を、元のファイルのバッファに付け替えてから報告する（`RuboCop::Cop::Base#range_for_original`）。0.8 系も tk0miya-rubocop-herb も文字位置を元の ERB に揃えているので、付け替えた範囲がそのまま元の ERB の正しい位置になる
- 実際のビュー 333 ファイルで、同じ位置に出た offense のメッセージは、0.8.2 と tk0miya-rubocop-herb で 1 件を除いて同じだった。違ったのは rails の `syntax_error.html.erb` の `Lint/Syntax` で、0.8.2 は「unexpected ';'; expected an argument」、tk0miya-rubocop-herb は「unexpected end-of-input; expected a `)` to close the arguments」
- 構文エラーのメッセージには、ERB に書かれていない `;` が出ることがある。0.8.2 も tk0miya-rubocop-herb もタグの終わりに `;` を補うためで、`<p><%= link_to("a", path %></p>` には両方で「unexpected ';'; expected a `)` to close the arguments」が出る（`syntax/unclosed_paren`）。キャレットは、0.8.2 では `%>` の `>` を、tk0miya-rubocop-herb では `%>` の前の空白を指す
- メッセージにコードを引用する cop では、変換後の Ruby が出ることがある。tk0miya-rubocop-herb の `Style/IdenticalConditionalBranches` は、`<%= user.name %>` について「Move `_ = user.name` out of the conditional.」と報告する（`marker/duplicate_branch_ng`）。`_ =` は tk0miya-rubocop-herb が `<%=` の位置に書く印で、ERB には書かれていない。0.8 系はこの cop を除外しているので出ない

## 6. 無効化コメント

### 6.1 書き方ごとの比較【実測】

[repro/cases/rubocop_disable/](repro/cases/rubocop_disable/) の 6 ファイルで、`Style/StringLiterals` を無効にするコメントを書き方ごとに試した結果です。どのファイルも、コメントの後の行に `"a"` などの二重引用符の文字列があります。

| ファイル | 書き方 | rubocop-erb 0.7.2 | rubocop-erb 0.8.2 / herb-rubocop-herb | tk0miya-rubocop-herb |
|---|---|---|---|---|
| `erb_comment` | `<%# rubocop:disable Style/StringLiterals %>` | 効かない | 効かない | 効く |
| `ruby_comment_tag` | `<% # rubocop:disable Style/StringLiterals %>` | 効かない（同じタグの中だけに効く） | 効かない | 効くが、`Lint/CopDirectiveSyntax` が出る |
| `trailing_ruby_comment` | `<% x = "b" # rubocop:disable Style/StringLiterals %>` | その行に効く | その行に効くが、`Lint/CopDirectiveSyntax` が出る | その行に効くが、`Lint/CopDirectiveSyntax` が出る |
| `trailing_ruby_comment_output` | `<%= "a" # rubocop:disable Style/StringLiterals %>` | その行に効く | その行に効くが、`Lint/CopDirectiveSyntax` が出る | その行に効くが、`Lint/CopDirectiveSyntax` が出る |
| `multiline_tag` | `<%`⏎`  # rubocop:disable Style/StringLiterals`⏎`  x = "b"`⏎`%>` の後に `<%= "c" %>` | 同じタグの中の `x = "b"` だけに効く | 後の `<%= "c" %>` にも効く | 後の `<%= "c" %>` にも効く |
| `multiline_range` | `<%`⏎`  # rubocop:disable …`⏎`%>` と `<%`⏎`  # rubocop:enable …`⏎`%>` で範囲を区切る | 効かない | 範囲の中だけに効く | 範囲の中だけに効く |

- 0.8.2 と herb-rubocop-herb では、`Herb.extract_ruby` が `<%# … %>` と、`#` で始まる 1 行のタグ（`<% # … %>`）の中身を空白にするので、そこに書いた無効化コメントは RuboCop に届かない。rubocop-erb には、`<%#` に書いた `rubocop:` の無効化コメントだけを、後ろに Ruby のコードがない場合に書き戻す実装を提案している（[r7kamura/rubocop-erb#84](https://github.com/r7kamura/rubocop-erb/issues/84)、open）
- タグの中の行末に書いたコメントは届くが、`extract_ruby` がタグの終わりに補う `  ;` がコメントの中に入り（`# rubocop:disable Style/StringLiterals  ;`）、`Lint/CopDirectiveSyntax`（Malformed directive comment）が出る。無効化そのものは効く
- コメントの後で改行してから `%>` を書けば、補われる `;` が次の行に回るので、通常の Ruby のコメントとして扱われる。ファイル全体に効き、`# rubocop:enable` で範囲を区切れる
- 0.7.2 はタグ 1 つを 1 つの Ruby として検査するので、無効化コメントは同じタグの中にしか効かない。`<% # rubocop:disable … %>` では、そのタグに `Lint/MissingCopEnableDirective` が出る
- tk0miya-rubocop-herb は、右側に別のタグや HTML がない `<%# … %>` を Ruby のコメントに変換するので、どの書き方でも効く。右側にタグや HTML があって効かない書き方は、`Herb/IgnoredCopDirective` が報告する（[第 2 部 7 章](tk0miya-rubocop-herb.md#7-tk0miya-rubocop-herb-の-cop)）
- tk0miya-rubocop-herb でも、タグの中の行末に書いたコメント（`<% # … %>` を含む）には、補う `;` がコメントの中に入るので `Lint/CopDirectiveSyntax` が出る。無効化そのものは効く

`<%# rubocop:disable … %>` が効かないことは、既存のテンプレートに 0.8 系を入れるときの障害になりえます。このコメントで抑えていた指摘が、まとめて出ます。0.8 系で無効化コメントを使うなら、Ruby のコメントだけを書いた複数行のタグにするのが確実です【推測】。

### 6.2 `<%#` の置き場所【実測】

[repro/cases/erb_comment/](repro/cases/erb_comment/) の 9 ファイルで、`<%# rubocop:disable … %>` をほかの ERB タグと同じ行やブロックの中に書いたときに、無効化が効くかを調べました。`empty_if` 以外は、`Lint/LiteralAsCondition` を無効にするコメントと、その対象になる `<% if 'hello' %>` を含みます。

| ファイル | 内容 |
|---|---|
| `trailing` | `<% if 'hello' %>world<% end %><%# rubocop:disable … %>` |
| `leading` | `<%# rubocop:disable … %><% if 'hello' %>world<% end %>` |
| `after_if` | `<% if 'hello' %><%# rubocop:disable … %>` の後に本文と `<% end %>` |
| `not_erb_tag` | `<% if 'hello' %>world<% end %><# rubocop:disable … %>`（`%` のない `<#`） |
| `indent` | 独立した行の `<%# rubocop:disable … %>` と `<%# rubocop:enable … %>`。インデントが入れ子の深さと合っていない |
| `multiline_comment` | `<%#`⏎`  rubocop:disable …`⏎`%>` の後に `<% if 'hello' %>` |
| `multiline_tag` | `<%`⏎`  # rubocop:disable …`⏎`%>` の後に `<% if 'hello' %>` |
| `trailing_in_tag` | `<% if 'hello' # rubocop:disable … %>` の後に本文と `<% end %>`（`<%#` ではなく、タグの中の行末の Ruby のコメント） |
| `empty_if` | `<% if some_error %><%# rubocop:disable Lint/EmptyConditionalBody %>`⏎`<% end %>`（本文が空の `if`） |

「効く」は無効にした cop（`Lint/LiteralAsCondition` か `Lint/EmptyConditionalBody`）が出ないこと、「効かない」は出ることです。

| ファイル | erb_lint | rubocop-erb 0.7.2 | rubocop-erb 0.8.2 / herb-rubocop-herb | ruumba | tk0miya-rubocop-herb |
|---|---|---|---|---|---|
| `trailing` | 確かめられない | 確かめられない | 効かない | 効く | 効く |
| `leading` | 確かめられない | 確かめられない | 効かない | `if` が検査されない | 効かない。`Herb/IgnoredCopDirective` が出る |
| `after_if` | 確かめられない | 確かめられない | 効かない | 効く | 効く |
| `not_erb_tag` | 確かめられない | 確かめられない | 効かない | 効かない | 効かない |
| `indent` | 確かめられない | 確かめられない | 効かない | 効く | 効く |
| `multiline_comment` | 確かめられない | 確かめられない | 効かない | 効く | 効く |
| `multiline_tag` | 確かめられない | 確かめられない | 効く | 効く | 効く |
| `trailing_in_tag` | 確かめられない | 確かめられない | 効くが、`Lint/CopDirectiveSyntax` が出る | 効く | 効くが、`Lint/CopDirectiveSyntax` が出る |
| `empty_if` | 確かめられない | 確かめられない | 確かめられない（`.erb` では `Lint/EmptyConditionalBody` を除外） | 出ない | 効く |

- erb_lint と rubocop-erb 0.7.2 は、`<% if 'hello' %>` と `<% end %>` を 1 つずつ Ruby として検査するので、どちらも構文エラーとして黙って飛ばす。0.7.2 では、`multiline_tag` に `Lint/MissingCopEnableDirective` と `Lint/RedundantCopDisableDirective` が、`trailing_in_tag` に `Lint/RedundantCopDisableDirective` が出る。erb_lint では、`multiline_tag` に `Layout/CommentIndentation` と `Layout/LeadingEmptyLines` が出る（誤検知）。ほかのファイルでは offense 0 件
- herb-rubocop-herb の結果は 0.8.2 と同じで、ほかに `Layout/ExtraSpacing` が出る。`empty_if` では、無効化コメントを消しても `Lint/EmptyConditionalBody` は出ない
- ruumba の `empty_if` は、コメントが `if` と同じ行の Ruby のコメントになり、`Lint/EmptyConditionalBody` は出ない
- ruumba は `<%# … %>` を `# …` という Ruby のコメントにする。`leading` は `# rubocop:disable Lint/LiteralAsCondition ;     if 'hello' ;          end` という 1 行のコメントになり、`if` が消える。代わりに `Lint/CopDirectiveSyntax`、`Lint/MissingCopEnableDirective`、`Lint/RedundantCopDisableDirective` が出る。ほかのファイルでも `Layout/CommentIndentation` などの誤検知が出る
- tk0miya-rubocop-herb は、右側に何もない `<%#` を Ruby のコメントにする。コードと同じ行にあれば、その行だけに効く（`trailing`、`after_if`）。独立した行にあれば、`rubocop:enable` までの範囲に効く（`indent`、`multiline_comment`）
- `not_erb_tag` の `<# … %>` は ERB のタグではなく、HTML のテキストとしてそのまま出力される。herb-lint は `%>` に `STRAY_ERB_CLOSING_TAG_ERROR`（`parser-no-errors`）を出す。ほかのファイルには、herb-lint の offense は出ない
- herb-lint は、本文が空の `if` に `erb-no-empty-control-flow` を出す（hint）。ただし `<%#` も本文として数えるので、`empty_if` には出ない。中身が無効化のコメントだけでも、herb-lint にとっては空ではない `if`

`<%#` の右側にタグがあるときに tk0miya-rubocop-herb が `Herb/IgnoredCopDirective` を出すことは、ruumba のように後ろのコードを黙って検査から外すより安全です【推測】。

### 6.3 herb-format の整形と無効化コメント

#### herb-lint とインデント【出典・実測】

herb-lint 0.11.1 のルールのうち、インデントに関わるものは次の 2 つです（`@herb-tools/linter` の `docs/rules/`）。

- `source-indentation`: インデントの文字が設定（`formatter.indentStyle`、既定は空白）と合っているかだけを見る。入れ子の深さは見ない
- `erb-closing-tag-indent`: 複数行のタグの `%>` の位置を見る。ERB コメントと、Ruby のコメントを含むタグは対象外

インデントがずれた `indent` に、herb-lint の offense は出ません。`--fix` をかけても、ファイルは変わりません【実測】。

インデントを直すのは herb-format です。0.11.1 の herb-format は experimental preview で、`.herb.yml` で `formatter.enabled: true` にするか、`--force` を付けないと動きません（`@herb-tools/formatter` の README）。

#### herb-format の整形【実測】

`bin/autocorrect herb-format --force -- cases/erb_comment` の結果です。

```diff
 <div>
   <ul>
-<%# rubocop:disable Lint/LiteralAsCondition %>
+    <%# rubocop:disable Lint/LiteralAsCondition %>
     <% if 'hello' %>
-            <%# rubocop:enable Lint/LiteralAsCondition %>
+      <%# rubocop:enable Lint/LiteralAsCondition %>
       <li>world</li>
     <% end %>
   </ul>
```

- 独立した行の `<%#` は、ほかのタグと同じく入れ子の深さに合わせてインデントされる（`indent`）
- 同じ行に並んだタグは、別々の行に分けられる。コメントの置き場所は、前後どちらのタグと同じ行に残るかで変わる
  - `trailing`: `<% if 'hello' %>`⏎`  world`⏎`<% end %><%# rubocop:disable … %>`。コメントは `<% end %>` の行に残る
  - `leading`: `<%# rubocop:disable … %>`⏎`<% if 'hello' %>`⏎`  world`⏎`<% end %>`。コメントは独立した行になる
  - `after_if`: `<% if 'hello' %>`⏎`    <%# rubocop:disable … %>`。コメントは次の行に移り、`if` の本文としてインデントされる
  - `empty_if`: `<% if some_error %>`⏎`  <%# rubocop:disable … %>`⏎`<% end %>`。コメントは次の行に移り、`if` の本文としてインデントされる
- 複数行のコメントやタグは 1 行にまとめられ、その後に空行が入る
  - `multiline_comment`: `<%# rubocop:disable … %>`
  - `multiline_tag`: `<% # rubocop:disable … %>`。herb-lint が `erb-comment-syntax` を出し、`--fix` で `<%# rubocop:disable … %>` に直す
- `world` を独立した行にするので、出力される空白が変わる（`world` が `\n  world\n` になる）
- タグの中の行末のコメント（`trailing_in_tag`）は書き換えない
- `not_erb_tag` はパースエラーがあるので、書き換えずに飛ばす

#### 整形すると無効化の範囲が変わる【実測】

herb-format で整形したファイル（`multiline_tag` は、さらに herb-lint の `--fix` をかけたものも）を、rubocop-erb 0.8.2 と tk0miya-rubocop-herb にかけ直しました。

| ファイル | rubocop-erb 0.8.2（整形前 → 整形後） | tk0miya-rubocop-herb（整形前 → 整形後） |
|---|---|---|
| `trailing` | 効かない → 効かない | 効く → **効かない**。コメントが `<% end %>` の行に移り、その行だけに効く。`Lint/RedundantCopDisableDirective` も出る |
| `after_if` | 効かない → 効かない | 効く → **効かない**。コメントが本文の行に移り、そこからの範囲に効く。`Lint/MissingCopEnableDirective` と `Lint/RedundantCopDisableDirective` も出る |
| `leading` | 効かない → 効かない | 効かない → 効く。独立した行になり、ファイルの終わりまで効く（`Lint/MissingCopEnableDirective`） |
| `indent` | 効かない → 効かない | 効く → 効く |
| `multiline_comment` | 効かない → 効かない | 効く → 効く |
| `multiline_tag` | 効く → **効かない**（`--fix` で `<%#` にしても効かない） | 効く → 効く |
| `trailing_in_tag` | 効く → 効く（整形で変わらない。`Lint/CopDirectiveSyntax` は出る） | 効く → 効く |
| `empty_if` | 確かめられない | 効く → 出ない。ただし無効化が効いたからではない（下を参照） |

`empty_if` の tk0miya-rubocop-herb は、整形の後も `Lint/EmptyConditionalBody` を出しません。この cop は既定で `AllowComments: true` なので、コメントだけの本文を空と見なさないからです。無効化は何も抑えていないので `Lint/RedundantCopDisableDirective` が出ます。また独立した行の無効化になったので `Lint/MissingCopEnableDirective` も出て、無効化はファイルの終わりまで効きます。後ろに別の空の `if` があれば、その指摘も出なくなります。

#### herb:disable と herb-format【実測・出典】

herb-format は、herb-lint の無効化コメント `<%# herb:disable … %>` を、ほかの `<%#` とは別に扱います（`@herb-tools/formatter` の `dist/index.cjs` の `HerbDisableCollector` と `spliceHerbDisableComments`）。

- 整形の前に、`herb:disable` のコメントを構文木から外し、同じ行で直前にあるノードを「アンカー」として覚える
- 整形の後、アンカーのテキスト（ERB タグなら `<%= … %>` の全文、要素なら `</div` のようなタグ名）を出力の先頭から検索し、最初に見つかった行の末尾に空白 1 つを挟んでコメントを付け直す
- アンカーがない、またはテキストで検索できないノード（`if` などの制御構文）のときは、親のノードのテキストで検索する。それも見つからなければ、出力の最後の行に付ける

[repro/cases/herb_disable/](repro/cases/herb_disable/) の 4 ファイルを整形した結果です。

| ファイル | 整形前 | 整形後 | herb-lint の結果（整形前 → 整形後） |
|---|---|---|---|
| `img` | `<img src="a.png"> <%# herb:disable html-img-require-alt %>` | 同じ行の行末に残る（インデントだけ直る） | 効く → 効く |
| `same_anchor` | 同じ `<img src="a.png">` が 2 行並び、2 行目の行末に `herb:disable` | 1 行目の `<img>` の行末に付く | 効く → **効かない**（2 行目の `<img>` に `html-img-require-alt` が出る） |
| `empty_if` | `<% if some_error %><%# herb:disable erb-no-empty-control-flow %>`⏎`<% end %>` | `<% end %> <%# herb:disable … %>`（最後の行） | 不要 → **効かない**（`if` に `erb-no-empty-control-flow` が出る） |
| `if_sibling` | `<div>` の中で `<% if some_error %><%# herb:disable … %><% end %>` | `</div> <%# herb:disable … %>` | 不要 → **効かない**（`if` に `erb-no-empty-control-flow` が出る） |

- `empty_if` と `if_sibling` では、整形の前に `herb-disable-comment-unnecessary` が出る。`herb:disable` のコメント自体が `if` の本文になり、`if` が空でなくなるから。整形でコメントが `if` の外に出ると `if` が空になり、`erb-no-empty-control-flow` が出る。移った先の行でも `herb-disable-comment-unnecessary` が出る
- `same_anchor` は、アンカーをテキストで検索するため、同じ内容の 1 行目に付く

#### 考察【推測】

- tk0miya-rubocop-herb の行単位の無効化は、`<%#` がコードと同じ行の右端にあることを前提にしている。herb-format を使うプロジェクトでは、整形でこの前提が崩れ、無効化が外れる。多くの場合は offense が出るので気づけるが、`empty_if` のように offense が出ないまま無効化の範囲だけが広がることもある。herb-format と併用するなら、無効化コメントは独立した行に書き、`rubocop:enable` で閉じるのが確実
- tk0miya-rubocop-herb の `Herb/Formatting` cop で整形すると（`rubocop -A`）、整形で動いた無効化コメントを、同じ実行の `Lint/RedundantCopDisableDirective` が消す。`trailing`、`after_if`、`empty_if` ではコメントが消え、抑えていた offense がまた出る（[第 2 部 7.2 節](tk0miya-rubocop-herb.md#72-herbformatting)）。外れた無効化に気づく手がかりは offense だけになる
- rubocop-erb 0.8 系と herb-format を併用すると、0.8 系で範囲を指定して無効にする書き方（複数行のタグ）が、整形で `<% # … %>` になって効かなくなる。今回試した書き方のうち、整形の後も 0.8.2 で効くのはタグの中の行末のコメントだけで、`Lint/CopDirectiveSyntax` が出るうえ、効くのはその行だけ。また、タグの中の行末のコメントは、ERB や Erubi ではタグの後ろに生成されるコードまでコメントにするので、構文エラーになったり、テンプレートの残りが黙って出力されなくなったりする（`cases/comment/commented_out_*`）。構文エラーのもとになる書き方なので、非推奨とし、無効化コメントの書き方としてもサポートしなくてよいと考える。herb-lint にこの書き方を報告する `erb-no-trailing-comment` ルールを提案し（[marcoroth/herb#2867](https://github.com/marcoroth/herb/issues/2867)）、実装した PR がマージされ、`@herb-tools/linter` 0.11.2 でリリースされた（[marcoroth/herb#2871](https://github.com/marcoroth/herb/pull/2871)。検証環境は 0.11.1 なので、この節の実測には出ない）。tk0miya-rubocop-herb はこの書き方を報告する cop を持たず、herb-lint に任せる。ルールは既定で有効（severity は `error`）で、`template_engine: herb` のときは報告しない（`Herb::Engine` は行末のコメントを扱える）。autofix はコメントを別の `<%# %>` タグに移す（unsafe）
- `herb:disable` は herb-format で行末に残るように作られている一方、`rubocop:disable` の `<%#` は整形で動く。ERB の中で使う 2 つの無効化コメントのうち、行末に書けるのが片方だけというのは釣り合いが取れていない。ただ、`herb:disable` の書き戻しもテキスト検索に頼っていて、制御構文や同じ内容のタグでは別の行に付く。行末の無効化コメントを整形でどう保つかは、`herb:disable` と `rubocop:disable` をまとめて仕様を議論する必要がある

#### 今後の検討事項

- herb-format が `<%# rubocop:disable … %>`（と `<%# rubocop:enable … %>`）を、`herb:disable` と同じく行末に残すべきか。残すなら、どの行に付けるか（アンカーの決め方）。タグの直後の `<%# rubocop:disable … %>` が次の行に移ることを報告している（[marcoroth/herb#2868](https://github.com/marcoroth/herb/issues/2868)、open）
- `herb:disable` の書き戻しの行を、テキスト検索ではなくノードの位置で決められないか（`same_anchor`、`empty_if`、`if_sibling`）
- 無効化のコメントだけを本文に持つ `if` を、空として扱うか。herb-lint の `erb-no-empty-control-flow` は `<%#` を本文として数え、rubocop の `Lint/EmptyConditionalBody` は `AllowComments: true` でコメントだけの本文を許す。どちらも、無効化のコメントが指摘を消してしまう

## 7. その他のツール

- **better_html**（Shopify）: ERB パーサと安全性検査。Ruby は whitequark の parser でタグ単位に解析し、`do |x|` は正規表現で削る。v2.2.0（2025-09）で非推奨になり、README は Herb への移行を案内している【出典】
- **erb-formatter**（nebulab）: 単独で解析できないタグを「ブロックの開始」とみなし、それ以外のタグだけを syntax_tree で整形する。構文エラーのあるタグも「開始」扱いになり、エラーとして報告されない【出典】
- **htmlbeautifier**: 正規表現で `if` / `do` などを見てインデントするだけで、Ruby は解析しない【出典】
- **Rufo**（ERB）: タグ単位の整形。不完全な断片は `end` を補う、`begin … end` で包むなどの候補を Ripper で総当たりして解析する【出典】
- **syntax_tree-erb**: 2025-08 に作者が非推奨化。理由は「空白や好みの扱い、エッジケースが本当に難しい」【出典】
- **`erb -x | ruby -c`**: 標準 ERB は `<%= form_with … do |f| %>` を `_erbout.<<(( form_with … do |f| ).to_s)` に展開するため、Rails のブロック付き出力タグが常に SyntaxError になる。Rails は Erubi の `BLOCK_EXPR` 正規表現でこの形を特別扱いしている【出典】
- **Steep**: [soutaro/steep#1409](https://github.com/soutaro/steep/issues/1409)（2024-12、open）で ERB 対応が提案されている。実装 PR [#1836](https://github.com/soutaro/steep/pull/1836) は未マージ【出典】
- **sorbet_erb / sorbet_view**: ERB から Ruby を抽出して .rb を生成し、`srb tc` にかける。`self` や locals の型は注釈で補う必要がある【出典】
- **erblint-github**: erb_lint のプラグインで、アクセシビリティ系 16 ルール。Ruby の部分は見ない【出典】

rubygems.org の search API で `erb`, `erb lint`, `herb`, `rubocop erb` などを検索して見つかったもののうち、上で扱わなかったものです（2026-10-06 時点。DL 数は累計）【出典】。

| gem | 最終リリース | 累計 DL | 対象外とした理由 |
|---|---|---|---|
| erbcop | 0.5.0（2023-04） | 3.8 万 | r7kamura 氏による rubocop-erb の前身。リポジトリは archive 済みで、README で rubocop-erb への移行を案内している |
| rails-erb-lint | 1.2.6（2022-08） | 21.3 万 | ActionView で ERB をコンパイルして妥当性を見る構文チェック。リポジトリは削除済み |
| rails-erb-check | 0.1.0（2011-04） | 2.0 万 | Rails の ERB としての構文チェックのみ |
| erb-linter（nebulab） | 0.2.1（2021-09） | 1.5 万 | 閉じタグ・インデント・属性など HTML 側の検査 |
| erblint-agent | 0.2.0（2025-09） | 0.5 万 | erb_lint のプラグイン（ルール集）。Ruby 部分の扱いは erb_lint と同じ |
| herb-embedded | 0.10.3.0（2026-08） | 0.2 万 | Herb の JS 製 linter を mini_racer で Ruby から実行する仕組み。検査能力は Herb と同じ |
| standard-erb | 0.1.0（2026-08） | 0.2 万 | rubocop-erb を Standard から読み込むアダプタ。中身は rubocop-erb |
| herb-linter / rubocop-herb（Marco Roth） | 0.0.1（2026-08） | 各 0.2 万 | 依存のない 0.0.1。Herb の Rust 化の計画のための名前と思われる（[8 章](#8-herb-の今後rust-化)）【推測】 |

ほかに、erb_lint や Herb のランナー（pronto-erb_lint, pronto-herb, guard-erb_lint, spring-commands-erb_lint, erb_lint_daemon）があります。

## 8. Herb の今後（Rust 化）

Marco Roth 氏の「Herb の linter / formatter を Rust で書き直す」構想です（2026-10-10 時点）。手元での実行はしていません。

### まとめ

- 書き直しの対象はパーサではなく **linter と formatter**。パーサは今も C 製で、Rust からは FFI バインディングで呼ぶ【出典】
- 目的は「Ruby と JavaScript の両方から使える単一の実装と、同じ API」。速度の改善も挙げている【出典】
- Rust 製の linter は**動くプロトタイプがある**が、未マージのブランチ（`rust-linter`）にあり、リリースされていない。リリース時期の表明は見つからなかった【出典】
- Marco Roth 氏は、Rust 製 linter を Ruby に公開する仕組みと、**herb-lint の全ルールを RuboCop に公開する RuboCop プラグイン**のプロトタイプも作っている【出典】
- そのプラグインは ERB に対して RuboCop の `Lint` / `Style` / `Layout` を除外し、Herb のルールだけを実行する。つまり HTML 側の担当で、Ruby パートを RuboCop で検査する tk0miya-rubocop-herb とは役割が重ならない【出典・推測】
- rubygems の `rubocop-herb` 0.0.1 と `herb-linter` 0.0.1（どちらも Marco Roth 氏、2026-08）は、この計画のための名前と思われる。gem 名の衝突は、偶然ではなく本家の計画とぶつかっている【推測】
- Marco Roth 氏自身が「調整が必要」と述べている（herb#475）。発表で「将来は Rust 版 Herb 経由で」と言うなら、事前に話しておくのがよい【推測】

### 時系列【出典】

| 日付 | 出来事 |
|---|---|
| 2025-08-27 | PR [#455](https://github.com/marcoroth/herb/pull/455)「Rubygem: Implement multi-backend architecture including Node.js」。Ruby から linter / formatter を呼べるようにする PR。open のまま |
| 2025-09-08 | issue [#475](https://github.com/marcoroth/herb/issues/475)（`bundle exec herb lint/format`?）で、linter / formatter を純粋な Ruby で再実装するのは現時点では意味がない、と回答し #455 を案内 |
| 2025-11-02 | PR [#767](https://github.com/marcoroth/herb/pull/767) で Rust の FFI バインディングを追加（C パーサを Rust から呼ぶ） |
| 2026-02-25〜28 | ブランチ `rubocop-herb` に「Linter: Implement Linter in Rust」「RuboCop Herb: Implement Herb Integration for Herb」 |
| 2026-02-28〜 | ブランチ `rust-linter` で Rust 製 linter の開発が始まる |
| 2026-03-06 | issue [#1239 のコメント](https://github.com/marcoroth/herb/issues/1239#issuecomment-4013290572)で「Linter と Formatter を Rust で書き直すことを検討していて、動くプロトタイプがある」。Node.js 版と Rust 版の実行時間のスクリーンショットを掲載 |
| 2026-03-13 | [v0.9 のリリース記事](https://herb-tools.dev/blog/whats-new-in-herb-v0-9)に「Exploring a Rust-based Linter and Formatter」の節。今後の予定にも挙げる |
| 2026-03-17 | issue #475 で tk0miya が herb-tools-ruby / tk0miya-rubocop-herb を紹介。Marco Roth 氏が「Rust 経由で linter / formatter を Ruby に公開する方法に取り組んでいて、既存の linter ルールをすべて RuboCop に公開する RuboCop プラグインのプロトタイプがある。調整が必要そうだ」と返信（[コメント](https://github.com/marcoroth/herb/issues/475#issuecomment-4076915733)） |
| 2026-07-31〜08-09 | Rust の周辺 crate が main にマージされる: `herb-config`（設定の検証・統合）、`herb-printer`（AST からソースへの出力）、`herb-analysis`（Rubydex ベースの解析）、`herb-highlighter` |
| 2026-08-01 | rubygems に `rubocop-herb` 0.0.1（"Herb Integration for RuboCop"、依存は `herb` のみ）。homepage の `marcoroth/rubocop-herb` リポジトリは存在しない（2026-10-10 時点） |
| 2026-08-08 | `rust-linter` ブランチの最終コミット。TypeScript 版とのルールの一致（parity）を詰める作業が中心 |
| 2026-08-13 | rubygems に `herb-linter` 0.0.1（依存なし） |
| 2026-08-18 / 09-24 | v0.10 / v0.11 のリリース記事。Rust 製 linter / formatter への言及はない |

### v0.9 のリリース記事の記述【出典】

[What's new in Herb v0.9](https://herb-tools.dev/blog/whats-new-in-herb-v0-9)（2026-03-13）より。

> Beyond the bindings, we have been exploring rewriting the Linter and Formatter in Rust. There is a working prototype that can lint files using the same rule set as the current Node.js-based linter.

> The idea is to have a single implementation that can be used from both Ruby and JavaScript, with identical APIs on both sides.

> This is still early and exploratory, but the results are promising. More on this in a future release.

今後の予定（Future Work）の節:

> Early experiments with a Rust implementation of the core linter and formatter have shown promising results. A Rust-based implementation would allow us to share a single codebase across Ruby and JavaScript bindings with identical APIs, while also bringing significant performance improvements. This is something we are actively exploring.

同じ記事で、Herb の Ruby gem が Node.js 製の `herb-lint` / `herb-format` のバイナリを公開するようになったことも書かれています（"Node.js binaries"）。

### ブランチの中身【出典】

`rust-linter`:

- main から 78 コミット先行、553 コミット遅れ（2026-10-10 時点）。2026-08-08 以降は更新されていない
- `rust/herb-linter/`: Rust 製の linter 本体。ルール、autofix、`herb:disable` コメント、パーシャルの索引、CLI（rayon で並列実行）
- `herb-linter/`: Ruby の gem。gemspec の説明は "Built on the Herb parser with lint rules implemented in Rust"。`herb-lint` コマンドを持ち、C 拡張として Rust のライブラリを呼ぶ
- コミットの多くは TypeScript 版に合わせる作業（"Port the ten new rules from main to Rust"、"Match main's rule defaults in Rust" など）

`rubocop-herb`:

- 3 コミット（2026-02-25〜28）。main から 1,206 コミット遅れ（2026-10-10 時点）
- `ext/herb/linter.c`: `Herb::Linter.lint(source, config_json, file_name)` を Ruby に公開する C 拡張。Rust 製 linter の C API（`herb_lint`）を呼ぶ
- `lib/rubocop/cop/herb/linting.rb`: `Herb/Linting` cop。Herb の linter を 1 回実行し、結果を RuboCop の offense に変換する。個々のルールの設定は `.rubocop.yml` ではなく `.herb.yml` で行う
- `lib/rubocop/herb/default.yml`: `*.erb` / `*.html` などを対象に加え、そのファイルでは `Lint` / `Style` / `Layout` を除外する

### tk0miya-rubocop-herb との関係【推測】

| | tk0miya/rubocop-herb | Marco Roth 氏のプロトタイプ |
|---|---|---|
| Ruby パート | 独自の変換で RuboCop の cop をかける | 検査しない（`Lint` / `Style` / `Layout` を除外） |
| HTML パート | `Herb/Linting` cop が Node.js の herb-lint を子プロセスで実行 | `Herb/Linting` cop が Rust 製 linter を同じプロセス内で実行 |
| 状態 | 開発中（未公開） | 未マージのブランチ。gem 名だけ確保 |

- 2 つは補い合う関係にある。Rust 製 linter がリリースされれば、tk0miya-rubocop-herb の `Herb/Linting` cop は子プロセスをやめて Rust 製 linter を直接呼べる。Node.js も要らなくなる
- 一方で、どちらも「RuboCop で ERB を検査するプラグイン」で、gem 名も HTML 側の cop 名（`Herb/Linting`）も同じなので、利用者から見ると 2 つの `rubocop-herb` が並ぶことになる。統合するのか、名前を分けるのかは Marco Roth 氏と相談が必要
- herb-rubocop-herb（[4.3 節](#43-herb-rubocop-herbmarcorothherb2260herb-公式の-rubocop-herb-の提案)）は Ruby パートを担当する提案なので、Marco Roth 氏の整理の (2) に当たる。小さく、herb 本体の C 実装に乗っているので保守しやすい。herb 公式の gem として出すための土台としては妥当で、`<%=` を `_ =` にするような変換を `extract_ruby` のオプションとして C 側に足す方向もありうる

### 未確認

- Rust 製 formatter のプロトタイプ。v0.9 の記事では linter と並べて挙げているが、ブランチは見つからなかった（`formatter` などのブランチは中身を見ていない）
- Rust 製 linter を Node.js から使う方法（N-API / WebAssembly など）
- 発表で言及することについての Marco Roth 氏の意向

## 9. 既存ツールから tk0miya-rubocop-herb に切り替えるか

利用者の立場から「既存ツールを使い続ける理由」「tk0miya-rubocop-herb に切り替える理由」「切り替えられない理由」を整理します。

### まとめ【推測】

- **切り替える理由は、Ruby 部分の検査の正しさ**。既存ツールの見逃し・誤検知・テンプレートを壊す autocorrect は、検証用 ERB ではほぼすべて起きない。`.rubocop.yml` と `rubocop` コマンドに一本化できることも大きい
- **使い続ける理由は、実績と、RuboCop 以外の機能**。erb_lint は利用者が桁違いに多く、Ruby だけで動く HTML 検査や、独自 linter・プラグインの資産がある
- **今すぐ切り替えられない理由は 2 種類ある**
  - tk0miya-rubocop-herb 側で解消できるもの: rubygems に未公開（gem 名も衝突）
  - 利用者の環境や資産によるもの: HTML 検査に Node.js が必要、erb_lint の独自 linter・プラグインに移行先がない、Ruby 3.3 以上が必要
- rubocop-erb 0.8 系は、tk0miya-rubocop-herb と同じく文書全体を検査し、テンプレートを壊す修正を捨てる。tk0miya-rubocop-herb との差は、ファイル全体で除外する cop の数（65 個と 9 個）、`<%# rubocop:disable %>` が効くか、修正の検査の細かさ
- 既存ツールごとに見ると、ruumba と rubocop-erb 0.7 系の利用者は失うものがほぼなく、移行しやすい。rubocop-erb 0.8 系の利用者にとっては、移行の利点は検査できる cop の多さに限られる。erb_lint の利用者は Ruby 部分だけを tk0miya-rubocop-herb に移す併用が現実的。herb-lint の利用者にとっては、tk0miya-rubocop-herb は置き換えではなく追加になる

### 既存ツールを使い続ける理由

**実績と情報の多さ**

- erb_lint の累計 DL は 2,250 万で、rubocop-erb の約 25 倍【出典】。設定例や CI への組み込み方の情報が多い
- 周辺ツール（pronto-erb_lint, guard-erb_lint, erb_lint_daemon など）がある（[7 章](#7-その他のツール)）

**RuboCop 以外の機能（erb_lint）**

- 22 個の linter と 5 個の reporter が同梱され、Ruby で独自の linter を書ける。better_html で HTML を解析するので Ruby だけで動く（[3.1 節](#31-erb_lintrubocop-linter)）
- 多くは herb-lint にも同等のルールがあるが、`HardCodedString` と `DeprecatedClasses` に当たるルールは見当たらない

**見逃しが多い分、導入時の負担が小さい【推測】**

- タグ単位の方式では、`if` の条件式などが検査されない。裏返すと、既存のテンプレートに入れたときの offense が少ない
- tk0miya-rubocop-herb はプロジェクトの `.rubocop.yml` をそのまま ERB に当てるので、Ruby のファイルと同じ水準の offense が一度に出る。大きなプロジェクトでは、導入時に `.rubocop_todo.yml` で抑えるなどの作業が要る（`--auto-gen-config` が ERB で期待どおりに動くかは未確認）

**既知の問題を避ける設定がすでにある**

- erb_lint の利用者は、README の推奨どおりに誤検知の cop を無効化して運用していることが多いと思われる【推測】
- ただし、推奨設定でも `-a` でテンプレートが壊れる例がある（`Layout/LeadingEmptyLines` で `<%` が消える）。「安全な設定がある」わけではない

### tk0miya-rubocop-herb に切り替える理由

**検査できる範囲が広い【実測】**

- タグを跨いだ制御構造: `<% if foo == nil %>` の `Style/NilComparison`、`<% if !user.nil? %>` の `Style/NegatedIf`、`then` / `elsif` / `unless !x`、本当に空の `else`
- タグを跨いだ変数: 本当に未使用の変数だけに `Lint/UselessAssignment` が出る
- `Lint/Syntax`: `end` の抜けを検出する（rubocop-erb 0.7 系は `Lint/Syntax` を除外している。0.8 系は検出する）
- herb-lint では検出されないスタイル違反（`link_to( 'Home',root_path )` など）

**誤検知が少ない【実測・出典】**

- erb_lint の `Lint/UselessAssignment` やタグごとの `Style/FrozenStringLiteralComment`、ruumba の `Lint/Void`・`Style/SymbolProc`・`Lint/EmptyConditionalBody`・Layout 系の誤検知は、いずれも出ない
- ファイル全体で除外する cop は 9 個（rubocop-erb は 0.7 系が 53 個、0.8 系が 65 個）。変換で書いた文字（`;`、`_ =`、区切りの位置の空白）に反応する 22 個は、ERB タグに書かれたコードの上の offense だけを報告する。それ以外の誤検知になる cop（20 個）は、HTML を本文に持つ分岐や、ERB タグに跨がる `<% end %>` など、誤検知になる行だけで無効にする
- rubocop-erb 0.8 系が除外している `Lint/EmptyBlock`、`Style/SymbolProc`、`Style/SafeNavigation` なども、誤検知にならない行では検出する。実際のビューでは、本当に空のブロックや `map { |k| k.to_s }` を検出した（[5.4 節](#54-実際のビュー実測)）

**autocorrect がテンプレートを壊さない【実測・出典】**

- rubocop-erb 0.7 系が意味・構文を壊す `count -1`、`item *2`、`user && user.admin?` が正しく修正される
- erb_lint で `<%=` や `<%` が消えていた例も、正しく修正されるか、変更されない
- 文字位置を変えずに変換するので、ruumba のように黙って書き戻しを諦めることがない
- 修正を元の ERB に当ててみて、HTML が変わる修正、出力タグの数が変わる修正、パースエラーが増える修正は適用しない（[第 2 部 6 章](tk0miya-rubocop-herb.md#6-autocorrect-の検査copcorrectionguard)）
- `<% unused = 1 %>` は、通常の Ruby ファイルと同じく `-a` でタグごと消える（`Herb/EmptyErbTag`）
- ただし、ガードは cop ごとの修正を検査し、RuboCop が複数の cop の修正をまとめた結果は検査しない
- `Herb/Linting` と `Herb/Formatting` が適用する herb-lint と herb-format の修正も検査しない。herb-lint の `erb-comment-syntax` の修正は、`<% # コメント`⏎`  コード %>` のコードをコメントにする（[第 2 部 7.1 節](tk0miya-rubocop-herb.md#71-herblinting)）

**RuboCop に一本化できる【出典・推測】**

- 設定は `.rubocop.yml` だけ。Ruby のファイルと同じ規約が ERB にも当たり、`.erb_lint.yml` で cop を二重管理しなくてよい
- 実行は `rubocop` コマンドだけ。RuboCop の結果キャッシュ、`--parallel`、formatter、`rubocop:disable` コメントがそのまま使える（RuboCop と同じプロセス内で動く）
- `Herb/Linting` cop で herb-lint の結果も同じ出力に並び、`rubocop -a` / `-A` で herb-lint の修正も適用される。herb-lint の設定（`.herb.yml`、`.herb/rules/` の独自ルール、`herb:disable` コメント）もそのまま効く（README）
- `.herb.yml` で formatter を有効にすれば、`Herb/Formatting` cop で herb-format の整形も `rubocop -A` に入る（README）
- エディタの RuboCop 連携（Ruby LSP など）で ERB も検査できる見込み【推測。未確認】

**既存ツールの開発が止まりつつある【出典】**

- erb_lint は 2025-05 以降は依存更新のみで、性能改善 PR や autocorrect のバグが open のまま
- ruumba は 2021 年からメンテ停止
- better_html は非推奨になり、Herb への移行を案内している。rubocop-erb も ERB パーサを Herb に移し、0.8 系では `Herb.extract_ruby` で文書全体を変換している
- tk0miya-rubocop-herb は、開発が活発な Herb の上に作られている

### 切り替えられない理由

**tk0miya-rubocop-herb 側で解消できるもの**

| 理由 | 影響 | 解消の見込み |
|---|---|---|
| rubygems に未公開。gem 名が Marco Roth 氏の `rubocop-herb` 0.0.1 と衝突している。README の Installation が雛形のまま | Gemfile に git で指定するしかない。業務のプロジェクトでは導入しにくい | gem 名を決めて公開すれば解消 |

autocorrect については、壊す修正を捨てる仕組みがあり、検証用 ERB でも実際のビューでも、RuboCop の cop の修正は `-a`・`-A` ともテンプレートを壊しませんでした。ただし、これは見つかった問題にひとつずつ対処した結果で、すべての問題を解決したとは言えないので、「autocorrect は常に安全」とまでは言えません。ガードは複数の cop の修正をまとめた結果を検査せず、`Herb/Linting` と `Herb/Formatting` が適用する herb-lint と herb-format の修正も検査しません。herb-lint の `erb-comment-syntax` の修正が複数行のタグのコードをコメントにするバグも、そのまま適用されます（[第 2 部 8 章](tk0miya-rubocop-herb.md#8-既知の問題実測推測)）。

**利用者の環境や資産によるもの**

| 理由 | 影響 |
|---|---|
| HTML の検査（`Herb/Linting`）に Node.js と `@herb-tools/linter` が必要（README） | Node.js を入れられない環境では、HTML 構造の検査を RuboCop に統合できない。erb_lint は Ruby だけで HTML を検査できる |
| `@herb-tools/linter` を `Gemfile` のあるディレクトリから読み込む【実測・出典】（[第 2 部 7 章](tk0miya-rubocop-herb.md#7-tk0miya-rubocop-herb-の-cop)） | `package.json` を `Gemfile` と別のディレクトリ（`frontend/` など）に置いているプロジェクトでは、`Herb/Linting` が動かない。読み込み先を変える設定はない |
| erb_lint の独自 linter・プラグイン（erblint-github など）や、`HardCodedString`・`DeprecatedClasses` の移行先がない | これらを使っているプロジェクトは、erb_lint を残す必要がある。herb-lint の独自ルール（`.herb/rules/`）は JavaScript で書き直すことになる【推測】 |
| Ruby 3.3 以上、rubocop 1.90 以上が必要（gemspec） | 古い Ruby のプロジェクトでは使えない |
| 既定で対象にするのは `.html.erb` だけ（`Configuration::DEFAULT_EXTENSIONS`） | `.js.erb` や `.text.erb` は対象外。`extensions` 設定で追加できるが、HTML として解析されるので期待どおりに動くかは未確認【推測】 |
| Ruby の構文エラーがあるファイルでは herb-lint が動かない。他のテンプレートを参照するルール（パーシャルと呼び出し元など）はプロジェクト全体の解析なしで動く（README） | herb-lint を単独で使う場合より、HTML 側の検査が一部弱くなる |
| ERB タグに跨がる構造では Layout 系の cop を無効にしている（`Layout/IndentationWidth`, `Layout/EndAlignment` など） | 1 つのタグの中の Ruby は検査されるが、タグに跨がる本文や `<% end %>` のインデントは検査されない。HTML の構造に沿ったインデントは herb-format などの役割として残る |

### 既存ツールごとの判断【推測】

| いま使っているもの | 切り替えたときに得るもの | 失うもの | 判断 |
|---|---|---|---|
| ruumba | 誤検知の解消、正しく書き戻される autocorrect、メンテされている実装 | ほぼない | 公開されれば移行しやすい |
| rubocop-erb 0.7 系 | タグを跨いだ検査、`Lint/Syntax`、意味を壊さない autocorrect | ほぼない（どちらも RuboCop プラグイン） | 公開されれば移行しやすい。0.8 系に上げるだけでも前の 3 つは得られる |
| rubocop-erb 0.8 系 | 除外されていた cop（`Lint/EmptyBlock`、`Style/SymbolProc`、`Layout/LineLength` など）の検査、`<%# rubocop:disable %>`、修正後の ERB の検査、herb-lint の統合 | 利用実績 | 移行の利点は検査できる cop の多さ。急いで切り替える理由は小さい |
| erb_lint（Rubocop linter のみ） | 同上と、`.rubocop.yml` への一本化 | 導入時の offense の増加 | Ruby 部分は移行する価値がある |
| erb_lint（HTML 系 linter・プラグインも利用） | Ruby 部分の検査の正しさ | 独自 linter・プラグイン、Node.js 不要という性質 | Ruby 部分だけ tk0miya-rubocop-herb に移し、erb_lint の Rubocop linter を無効にして併用する |
| herb-lint | Ruby のスタイル検査（herb-lint にはない）、RuboCop との統合 | ほぼない（herb-lint の autocorrect も `Herb/Linting` で適用される） | 置き換えではなく追加。`Herb/Linting` cop で 1 コマンドにまとめられる |

### 発表に向けて

- 提案では「チェックできる範囲、auto correct できる範囲が広がっています」と書いている。範囲が広がったことは検証用 ERB で示せ、テンプレートを壊す修正を捨てる仕組みも説明できる。ただし、見つかった問題にひとつずつ対処しただけで、すべての問題を解決したとは言えないので、「autocorrect は常に安全」とは言わないほうがよい。herb-lint の修正のバグ（`erb-comment-syntax`）は `rubocop -a` でも適用される（[第 2 部 8 章](tk0miya-rubocop-herb.md#8-既知の問題実測推測)）
- rubocop-erb 0.8 系が同じ方式（文書全体の変換と修正範囲の検査）なので、比べる相手は 0.7 系だけでなく 0.8 系も含める。0.8 系との違いは、除外する cop の数と、`<%=` と HTML の意味を残す変換にある
- 「切り替えられない理由」のうち、tk0miya-rubocop-herb 側で解消できるもの（rubygems への公開）は、発表までに片付けておきたい
- 利用者の環境によるもの（Node.js、erb_lint の独自 linter）は、「erb_lint と併用できる」「herb-lint を Ruby から使える」という形で、移行の道筋として示せる
- 「同じ Ruby になる 2 つの ERB」: `<p><%= count + 1 %> items</p>` と `<p><% count + 1 %> items</p>` は、`extract_ruby` ではどちらも `count + 1  ;`。0.8.2 はどちらにも何も言わず、herb-rubocop-herb はどちらにも `Lint/Void` を出し、tk0miya-rubocop-herb は後者だけを指摘する
- 「除外で捨てているもの」: 実際のビューで、0.8.2 が除外している内容の指摘 131 件のうち、妥当な指摘が 23 件。tk0miya-rubocop-herb は誤検知を出さずに、そのうち 22 件を報告する
- 「誤検知は壊れる autocorrect になる」: herb-rubocop-herb の `-A` で、`Last login: <% user.touch %>` が `<% user&.touch%>` に、`<li><%= item.name %></li>` のループが `<% items.each(&:name)%>` になる。tk0miya-rubocop-herb では誤検知が出ないので、修正も提案されない

## 10. 要フォローアップ

- **gem 名の衝突**: rubygems に Marco Roth 氏の `rubocop-herb` 0.0.1（2026-08-01 公開、"Herb Integration for RuboCop"）が登録されている【出典: rubygems API】。tk0miya/rubocop-herb の gem 名を検討する必要がある（[8 章](#8-herb-の今後rust-化)）
- **rubocop 本体のリグレッション**: `Style/SafeNavigation` の `user&&.admin?` は rubocop 1.86.2 以降で起きる（rubocop-erb 0.7 系）。ERB 以外の再現手順を作れれば upstream に報告できる

## 11. 主な出典

- erb_lint: https://github.com/Shopify/erb_lint （`lib/erb_lint/linters/rubocop.rb`、README の Rubocop 節、issues [#126](https://github.com/Shopify/erb_lint/issues/126), [#142](https://github.com/Shopify/erb_lint/issues/142), [#228](https://github.com/Shopify/erb_lint/issues/228), [#299](https://github.com/Shopify/erb_lint/issues/299), [#326](https://github.com/Shopify/erb_lint/issues/326), [#331](https://github.com/Shopify/erb_lint/issues/331), [#332](https://github.com/Shopify/erb_lint/issues/332), [#383](https://github.com/Shopify/erb_lint/issues/383), [#461](https://github.com/Shopify/erb_lint/issues/461)、PRs [#300](https://github.com/Shopify/erb_lint/pull/300), [#413](https://github.com/Shopify/erb_lint/pull/413), [#454](https://github.com/Shopify/erb_lint/pull/454), [#457](https://github.com/Shopify/erb_lint/pull/457), [#464](https://github.com/Shopify/erb_lint/pull/464)）
- rubocop-erb: https://github.com/r7kamura/rubocop-erb （`lib/rubocop/erb/ruby_extractor.rb`、`lib/rubocop/erb/corrector.rb`、`config/default.yml`、issues [#5](https://github.com/r7kamura/rubocop-erb/issues/5), [#6](https://github.com/r7kamura/rubocop-erb/issues/6), [#84](https://github.com/r7kamura/rubocop-erb/issues/84)、PRs [#70](https://github.com/r7kamura/rubocop-erb/pull/70), [#74](https://github.com/r7kamura/rubocop-erb/pull/74), [#77](https://github.com/r7kamura/rubocop-erb/pull/77), [#81](https://github.com/r7kamura/rubocop-erb/pull/81), [#82](https://github.com/r7kamura/rubocop-erb/pull/82)）
- herb-rubocop-herb: https://github.com/marcoroth/herb/pull/2260 （`gems/rubocop-herb/lib/rubocop/herb/plugin.rb`、`gems/rubocop-herb/config/default.yml`）、[marcoroth/herb#1619](https://github.com/marcoroth/herb/issues/1619)
- ruumba: https://github.com/ericqweinstein/ruumba （`lib/ruumba/parser.rb`、`lib/ruumba/analyzer.rb`、`lib/ruumba/rubocop_runner.rb`、`bin/ruumba`、README）
- RuboCop ruby_extractors API: https://github.com/rubocop/rubocop/pull/10839 、[#14954](https://github.com/rubocop/rubocop/pull/14954)
- Herb: https://github.com/marcoroth/herb （`src/analyze/parse_errors.c`、`javascript/packages/formatter/src/format-printer.ts`、issues [#356](https://github.com/marcoroth/herb/issues/356), [#475](https://github.com/marcoroth/herb/issues/475), [#670](https://github.com/marcoroth/herb/issues/670), [#1239](https://github.com/marcoroth/herb/issues/1239), [#2285](https://github.com/marcoroth/herb/issues/2285), [#2867](https://github.com/marcoroth/herb/issues/2867), [#2868](https://github.com/marcoroth/herb/issues/2868)、PRs [#455](https://github.com/marcoroth/herb/pull/455), [#767](https://github.com/marcoroth/herb/pull/767), [#2871](https://github.com/marcoroth/herb/pull/2871)、ブランチ `rust-linter` と `rubocop-herb`）、https://github.com/rails/rails/pull/58552
- better_html: https://github.com/Shopify/better-html
- erb-formatter: https://github.com/nebulab/erb-formatter
- htmlbeautifier: https://github.com/threedaymonk/htmlbeautifier
- Rufo: https://github.com/ruby-formatter/rufo
- syntax_tree-erb: https://github.com/davidwessman/syntax_tree-erb
- Steep: https://github.com/soutaro/steep/issues/1409 、https://github.com/soutaro/steep/pull/1836
- sorbet_erb: https://github.com/franklinhu/sorbet_erb 、sorbet_view: https://github.com/kazzix14/sorbet_view
- erblint-github: https://github.com/github/erblint-github
