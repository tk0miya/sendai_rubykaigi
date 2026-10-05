# 既存の ERB linter と、その限界

調査日: 2026-10-06

「既存の ERB linter は、ERB に埋め込まれた Ruby 片を正しく lint できない」ことを確かめるための調査メモです。
【実測】は手元で実行して確かめたこと（再現手順は [repro/README.md](repro/README.md)）、【出典】はソースコードや issue で確かめたこと、【推測】は解釈です。

## まとめ

既存ツールの Ruby の扱いは、次の 2 系統に分かれます。

1. **タグ単位に分割する**（erb_lint, rubocop-erb, better_html, erb-formatter, Rufo など）
   - ERB タグ 1 つを 1 つの Ruby プログラムとして扱う
   - 制御構造（`if`〜`end`）、変数スコープ、ファイルという 3 つの文脈が失われる
   - その結果、誤検知・見逃し・テンプレートを壊す autocorrect が起きる
2. **HTML を空白で埋めて、文書全体を 1 本の Ruby にする**（ruumba, Herb, Steep の提案）
   - タグを跨いだ制御構造や変数スコープは保たれる
   - この方式で RuboCop をかけたのは ruumba だけ。タグ単位の方式の問題は解消するが、`<%=` の「出力する」という意味と HTML 本文が失われるため、別の誤検知が出る。autocorrect も安全ではない
   - Herb は構文チェックと一部のルールに使うだけで、RuboCop はかけていない

つまり「HTML と Ruby の両方を理解したうえで、RuboCop のスタイル検査と autocorrect を安全に行う」ツールは存在しません。Ruby だけを取り出す方式では、分割しても連結しても文脈の一部が失われます。

## ツール一覧と比較

凡例: ◎ 本格対応 / ○ 対応 / △ 限定的 / × なし

| ツール | HTML 構造 | Ruby の構文 | Ruby のスタイル (RuboCop) | タグを跨いだ Ruby 解析 | autocorrect | 型・意味解析 |
|---|---|---|---|---|---|---|
| erb_lint (Rubocop linter) | ○ (better_html) | △ (タグ単位。不完全な文はスキップ) | △ (タグ単位) | × | △ (テンプレートを壊す) | × |
| rubocop-erb | × | △ (タグ単位。Lint/Syntax を除外) | △ (タグ単位。約 55 cop を除外) | × | △ (意味・構文を壊す) | × |
| ruumba (メンテ停止) | × | ○ (文書全体) | △ (文書全体。出力・HTML 本文が失われ誤検知) | ○ | △ (実験的。黙って書き戻さないことがある) | × |
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

## erb_lint（Rubocop linter）

- リポジトリ: https://github.com/Shopify/erb_lint
- 最新: 0.9.0（2025-01-20）。2025-05 以降は依存更新のみで、性能改善 PR（[#454](https://github.com/Shopify/erb_lint/pull/454), [#457](https://github.com/Shopify/erb_lint/pull/457)）や autocorrect のバグ（[#461](https://github.com/Shopify/erb_lint/issues/461)）が open のまま

### 仕組み【出典】

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

### 誤検知【実測】

全 cop を有効にした設定（`repro/erb_lint/all_cops`）で次の結果になります。

| ERB | 結果 |
|---|---|
| `<%= "hello" %>` | `Layout/InitialIndentation`、`Layout/TrailingEmptyLines`、`Style/FrozenStringLiteralComment` が**タグごとに**出る |
| `<% name = "Alice" %>` + `<p><%= name %></p>` | `Lint/UselessAssignment` が出る。次のタグで使っているので誤検知 |

README はこれらの cop を無効化するよう推奨しています（InitialIndentation, LineLength, TrailingEmptyLines, TrailingWhitespace, FileName, FrozenStringLiteralComment, UselessAssignment, Rails/OutputSafety）。issue [#126](https://github.com/Shopify/erb_lint/issues/126) ではメンテナが UselessAssignment について「this is normal … Consider disabling this cop」と回答しています。

### 見逃し【実測】

推奨設定（`repro/erb_lint/recommended`）での結果と、同じ内容の Ruby（`repro/plain_ruby/equivalent.rb`）に RuboCop をかけた結果の比較です。

| ERB | erb_lint | 同じ内容の Ruby |
|---|---|---|
| `<% if foo == nil %>…<% end %>` | 0 件 | `Style/NilComparison`, `Style/IfUnlessModifier` |
| `<% if !foo.nil? then %>…<% elsif bar == nil %>…<% else %><% end %>` | 0 件 | `Style/MultilineIfThen`, `Style/NilComparison`, `Style/EmptyElse` |
| `<% unless !x %><% end %>` | 0 件 | `Style/NegatedUnless`, `Lint/EmptyConditionalBody` |
| `<% items.each do \|i\| %>…<% end %>`（`i` 未使用） | 0 件 | `Lint/UnusedBlockArgument` |

`if` の条件式が検査されない問題は issue [#332](https://github.com/Shopify/erb_lint/issues/332) として報告されています（open）。

### autocorrect がテンプレートを壊す【実測】

| 設定 | 修正前 | `erb_lint -a` 後 |
|---|---|---|
| 全 cop | `<%= link_to "x", path, class: 'btn' %>` | `# frozen_string_literal: true`⏎`link_to 'x', path, class: 'btn'`⏎` %>` |
| 全 cop | `<% name = "Alice" %>` | `# frozen_string_literal: true`⏎`'Alice'`⏎` %>` |
| 推奨設定 | `<%`⏎`  x = 1`⏎`  y = 2`⏎`%>` | `x = 1`⏎`  y = 2`⏎`%>` |

- `<%=` や `<%` が消え、マジックコメントが HTML 本文に挿入される
- 推奨設定でも、README のリストに入っていない `Layout/LeadingEmptyLines` の修正で `<%` が消える
- 同系統の issue: [#142](https://github.com/Shopify/erb_lint/issues/142)（2019 年から open）, [#228](https://github.com/Shopify/erb_lint/issues/228), [#326](https://github.com/Shopify/erb_lint/issues/326), [#331](https://github.com/Shopify/erb_lint/issues/331), [#383](https://github.com/Shopify/erb_lint/issues/383), [#461](https://github.com/Shopify/erb_lint/issues/461)。修正 PR [#413](https://github.com/Shopify/erb_lint/pull/413) も open のまま

### その他【出典】

- 性能: タグごとに `Team.mobilize` で全 cop を作り直す。改善 PR [#454](https://github.com/Shopify/erb_lint/pull/454)（25 タグ/ファイルで 8.94s → 5.56s）、[#457](https://github.com/Shopify/erb_lint/pull/457) は未マージ
- キャッシュが RuboCop のバージョンや `.rubocop.yml` の変更を考慮しない（[#299](https://github.com/Shopify/erb_lint/issues/299), [#300](https://github.com/Shopify/erb_lint/pull/300), [#464](https://github.com/Shopify/erb_lint/pull/464)）

## rubocop-erb

- リポジトリ: https://github.com/r7kamura/rubocop-erb
- 最新: 0.7.1（2026-03-29）。0.7.0 で ERB パーサを better_html から Herb に移行（[#57](https://github.com/r7kamura/rubocop-erb/issues/57), [#59](https://github.com/r7kamura/rubocop-erb/pull/59)）

### 仕組み【出典】

RuboCop の ruby_extractors API（rubocop PR [#10839](https://github.com/rubocop/rubocop/pull/10839)、r7kamura 氏が導入）を使うプラグインです。

- extractor は `[{offset: Integer, processed_source: RuboCop::ProcessedSource}, ...]` を返す
- cop は fragment ごとに独立した ProcessedSource として実行され（`Team#investigate_fragments`）、位置は `range.begin_pos + offset` で元ファイルに戻される
- つまり **1 つの fragment は元ファイル上の連続した 1 区間でなければならない**【推測】。タグを跨いだ構文を 1 つの AST として渡すことは、この API では表現できない

Ruby の取り出し方（`lib/rubocop/erb/ruby_extractor.rb`）:

- Herb の AST から ERB タグ 1 つを 1 fragment として取り出す
- `KeywordRemover` が正規表現で先頭の `if` / `unless` / `else` / `end` などと、末尾の `do |x|` / `{ |x|` / `then` を削る
- `<% if foo %>` は `foo` として、`<% items.each do |i| %>` は `items.each` として検査される

r7kamura 氏自身が issue [#6](https://github.com/r7kamura/rubocop-erb/issues/6) で「`if a` / `c` / `end` をまとめて抽出しても、offense を元 ERB の位置に戻す仕組みがない」と述べています。

### 除外されている cop【出典】

`config/default.yml` で約 55 個の cop が `**/*.erb` から除外されています。Layout 系の大半、`Lint/Syntax`、`Lint/UselessAssignment`、`Lint/Void`、`Style/FrozenStringLiteralComment`、`Style/IfUnlessModifier`、`Metrics/BlockLength` などです。

### 見逃し【実測】

`repro/rubocop-erb` で `bundle exec rubocop` を実行した結果です。

| ERB | 結果 |
|---|---|
| `<% if !user.nil? %>…<% end %>` | `Style/NegatedIf` が出ない（`if` が削られるため） |
| `<% items.each do \|item\| %><%= item.name %><% end %>` | `Style/SymbolProc` が出ない |
| `<%= items.map do \|i\| %>…<% end.join(", ") %>` | 構文エラーになる断片が黙って無視される |
| `<% result = if foo %>…<% end %>` | 同上 |

### autocorrect が意味・構文を壊す【実測】

| 修正前 | `rubocop -A` 後 | 原因 |
|---|---|---|
| `<% count = items.size %>`⏎`<p><%= count -1 %></p>` | `<%= count(-1) %>` | 前のタグのローカル変数が見えず、`count` をメソッド呼び出しと解釈する（`Lint/AmbiguousOperator`） |
| `<% items.each do \|item\| %>`⏎`<%= item *2 %>` | `<%= item(2) %>` | 同上（`Lint/AmbiguousOperator`, `Lint/RedundantSplatExpansion`） |
| `<% if user && user.admin? %>` | `<% if user&&.admin? %>`（構文エラー） | `Style/SafeNavigation` の修正。rubocop 1.86.1 では正しく `user&.admin?` になる |

`&&.` は rubocop 1.86.2 以降で起きます。1.86.2 で入った fragment ごとの corrector の統合方式（[#14954](https://github.com/rubocop/rubocop/pull/14954)）の副作用と思われますが【推測】、既存の issue は見つかっていません。

## ruumba

- リポジトリ: https://github.com/ericqweinstein/ruumba
- 最新: 0.1.17（2021-01-16）。2021-08 以降は push がない
- 利用状況: 累計 48.6 万 DL（rubocop-erb の約半分）、直近 30 日で 2.0 万 DL、GitHub スター 95（2026-10-06 時点）

erb_lint や rubocop-erb より前からある RuboCop ベースの ERB linter です。タグ単位ではなく文書全体を 1 本の Ruby にして RuboCop をかけるので、タグ単位の方式の問題が解消されているかを確認しました。

### 仕組み【出典】

`lib/ruumba/parser.rb` は次のように ERB を Ruby に変換します。

- 正規表現 `/<%[-=]?(.*?)-?%>/m` で ERB タグの中身を取り出す
- HTML とタグの区切りは空白に置き換え、同じ行で続くタグの間にだけ `;` を補う
- 解析の前に `<%==` を `<%= raw` に置き換える

例えば `<% if foo == nil %>⏎  <p>yes</p>⏎<% end %>` は `"   if foo == nil   \n            \n   end   \n"` になります。これを一時ディレクトリに `.rb` として書き出し、`rubocop` コマンドを子プロセスで実行します（`lib/ruumba/rubocop_runner.rb`）。

autocorrect のときは、各タグの中身の前後にマーカー行を挿入してから RuboCop にかけます。修正後のコードからマーカーを手がかりに各タグの中身を切り出し、ERB に書き戻します（`Parser#replace`）。

### タグ単位の方式の問題は解消している【実測】

erb_lint / rubocop-erb で使った再現例（`repro/erb_lint`, `repro/rubocop-erb`）にかけた結果です（ruumba 0.1.17, rubocop 1.91.0, README の推奨設定）。

| ERB | erb_lint / rubocop-erb | ruumba |
|---|---|---|
| `<% if foo == nil %>…<% end %>` | 見逃し | `Style/NilComparison` を検出し、`foo.nil?` に修正 |
| `<% if !user.nil? %>…<% end %>` | 見逃し | `Style/NegatedIf` を検出し、`unless user.nil?` に修正 |
| `then` / `elsif bar == nil` / 空の `else` / `unless !x` | 見逃し | `Style/MultilineIfThen`, `Style/NilComparison`, `Style/EmptyElse`, `Style/NegatedUnless` を検出 |
| `<% name = "Alice" %>` + `<%= name %>` | `Lint/UselessAssignment`（誤検知） | 出ない |
| `<% count = items.size %>` + `<%= count -1 %>` | `count(-1)` に書き換え（rubocop-erb） | ローカル変数と認識され、`Lint/AmbiguousOperator` は出ない |
| `<% end.join(", ") %>` など | 黙って無視（rubocop-erb） | 正しく解析される |
| `Style/FrozenStringLiteralComment` など | タグごとに出る | ファイルに 1 回だけ |

制御構造・変数スコープ・ファイルという 3 つの文脈は保たれています。

### 新たに生じる問題【実測】

README の推奨設定を使った結果です（`repro/ruumba` ほか）。

**`<%=` の「出力する」という意味が失われる**

| ERB | 結果 |
|---|---|
| `<p><%= name %>: <%= count -1 %></p>` | `name; count -1` と連結され、`name` に `Lint/Void` が出る |
| `<p><%= count -1 %></p>`（後ろにもタグが続く） | `-` に `Lint/Void` が出る |
| `<% items.each do \|item\| %>`⏎`<%= item.name %>`⏎`<% end %>` | `Style/SymbolProc` が `items.each(&:name)` を提案する。従うと出力がなくなるので、提案自体が誤り |

**HTML 本文が失われる**

| ERB | 結果 |
|---|---|
| `<% if foo == nil %>`⏎`<p>yes</p>`⏎`<% end %>` | `Lint/EmptyConditionalBody` が出る |
| `<% items.each do \|i\| %>`⏎`<li>item</li>`⏎`<% end %>` | `Lint/EmptyBlock` が出る |

ERB では、本文が HTML だけの `if` やブロックはごく普通に書かれるので、日常的に誤検知になります。

**空白で埋めたことによる Layout 系の誤検知**

- `repro/` の再現例 17 ファイル（erb_lint, rubocop-erb, ruumba の各ディレクトリ）に対して、`Layout/TrailingWhitespace` が 54 件、`Layout/InitialIndentation` が 17 件出た
- ほかに `Layout/IndentationConsistency`, `Layout/ExtraSpacing`, `Layout/SpaceBeforeSemicolon`, `Layout/BlockAlignment`, `Layout/EndAlignment` なども出る
- `<%= a %><%= b %>` に補った `;` にも `Style/Semicolon` が出る
- README の推奨設定で無効化しているのは 5 個（FrozenStringLiteralComment, HashAlignment, ParameterAlignment, IndentationWidth, TrailingEmptyLines）だけで、これらは抑えられない

**autocorrect が当てにならない**

- 推奨設定のまま `--auto-correct` すると「88 offenses corrected」と表示されるが、ERB ファイルは 1 つも書き換わらない。Layout 系の修正でマーカー行がずれ、`Parser#replace` が `nil` を返して黙って書き戻しを諦めるため
- ソースにも "auto-correct is still experimental and can cause invalid ruby to be generated when extracting ruby from ERBs" というコメントがある
- `--only` で Style 系の cop に絞ると修正は反映される。ただし、関係のない `<%== raw_html %>` が `<%= raw raw_html %>` に書き換わる。解析前の `<%==` → `<%= raw` の置換がそのまま書き戻されるため
- autocorrect のときはマーカー行を挿入したコードを検査するので、lint のときとは結果が変わる。例えば `Style/SymbolProc` は autocorrect のときには検出されない（ブロックの中身にマーカー行が入るため）

### その他【出典】

- RuboCop で非推奨の `--auto-correct` を渡すため、警告が出る
- CLI の `-a` が `--auto-gen-config` と `--auto-correct` の 2 つに重複して定義されている（`bin/ruumba`）
- `<%` の取り出しは正規表現だけで、HTML の構造は見ない

## Herb（herb-lint / herb-format）

- リポジトリ: https://github.com/marcoroth/herb
- 最新: v0.11.0（2026-09-24）。開発は活発。[rails/rails#58552](https://github.com/rails/rails/pull/58552) で ActionView に Herb ハンドラが追加された

### できること【出典・実測】

- C 製の HTML+ERB パーサで、HTML と ERB を統合した AST を持つ
- 構文チェックは、HTML を空白に置き換えて各タグの末尾に `;` を補い、Prism で**文書全体を 1 本のプログラムとして**解析する（`src/analyze/parse_errors.c`）
- `end` の抜けを `RUBY_PARSE_ERROR` と `MISSING_ERB_END_TAG_ERROR` で検出する【実測】
- `erb-no-unused-local-variable` はタグを跨いで変数を追跡し、本当に未使用の変数だけを検出する【実測】
- lint ルールは 168 個（146 個がデフォルトで有効）

### 限界

- **RuboCop を実行しない**。`<%= link_to( 'Home',root_path ) %>` のようなスタイル違反は検出されない【実測】
  - RuboCop 連携は issue [#356](https://github.com/marcoroth/herb/issues/356) で要望されたまま open
  - [#356](https://github.com/marcoroth/herb/issues/356) では Earlopain 氏が「`Herb.extract_ruby` を試したが、空ブロックや余分な空白など誤検出が多すぎる」とコメントしている
- herb-format は、タグ内の Ruby を `trim()` するだけで整形しない。README で "experimental preview" と明記。外部フォーマッタ連携は [#670](https://github.com/marcoroth/herb/issues/670) で要望中
- 型・意味解析はしない。未定義メソッドは検出されない【実測】。Sorbet 連携の要望 [#2285](https://github.com/marcoroth/herb/issues/2285) に対し、作者は「Sorbet 側の仕事」と回答
- linter は Node 製で、Ruby のツール（RuboCop, Ruby LSP）とは連携できない

## その他のツール

- **better_html**（Shopify）: ERB パーサと安全性検査。Ruby は whitequark の parser でタグ単位に解析し、`do |x|` は正規表現で削る。v2.2.0（2025-09）で非推奨になり、README は Herb への移行を案内している【出典】
- **erb-formatter**（nebulab）: 単独で解析できないタグを「ブロックの開始」とみなし、それ以外のタグだけを syntax_tree で整形する。構文エラーのあるタグも「開始」扱いになり、エラーとして報告されない【出典】
- **htmlbeautifier**: 正規表現で `if` / `do` などを見てインデントするだけで、Ruby は解析しない【出典】
- **Rufo**（ERB）: タグ単位の整形。不完全な断片は `end` を補う、`begin … end` で包むなどの候補を Ripper で総当たりして解析する【出典】
- **syntax_tree-erb**: 2025-08 に作者が非推奨化。理由は「空白や好みの扱い、エッジケースが本当に難しい」【出典】
- **`erb -x | ruby -c`**: 標準 ERB は `<%= form_with … do |f| %>` を `_erbout.<<(( form_with … do |f| ).to_s)` に展開するため、Rails のブロック付き出力タグが常に SyntaxError になる。Rails は Erubi の `BLOCK_EXPR` 正規表現でこの形を特別扱いしている【出典】
- **Steep**: [soutaro/steep#1409](https://github.com/soutaro/steep/issues/1409)（2024-12、open）で ERB 対応が提案されている。実装 PR [#1836](https://github.com/soutaro/steep/pull/1836) は未マージ【出典】
- **sorbet_erb / sorbet_view**: ERB から Ruby を抽出して .rb を生成し、`srb tc` にかける。`self` や locals の型は注釈で補う必要がある【出典】
- **erblint-github**: erb_lint のプラグインで、アクセシビリティ系 16 ルール。Ruby の部分は見ない【出典】

## rubygems.org で見つかった、その他の候補

rubygems.org の search API で `erb`, `erb lint`, `herb`, `rubocop erb` などを検索して見つかったもののうち、上で扱わなかったものです（2026-10-06 時点。DL 数は累計）。

| gem | 最終リリース | 累計 DL | 対象外とした理由 |
|---|---|---|---|
| erbcop | 0.5.0（2023-04） | 3.8 万 | r7kamura 氏による rubocop-erb の前身。リポジトリは archive 済みで、README で rubocop-erb への移行を案内している |
| rails-erb-lint | 1.2.6（2022-08） | 21.3 万 | ActionView で ERB をコンパイルして妥当性を見る構文チェック。リポジトリは削除済み |
| rails-erb-check | 0.1.0（2011-04） | 2.0 万 | Rails の ERB としての構文チェックのみ |
| erb-linter（nebulab） | 0.2.1（2021-09） | 1.5 万 | 閉じタグ・インデント・属性など HTML 側の検査 |
| erblint-agent | 0.2.0（2025-09） | 0.5 万 | erb_lint のプラグイン（ルール集）。Ruby 部分の扱いは erb_lint と同じ |
| herb-embedded | 0.10.3.0（2026-08） | 0.2 万 | Herb の JS 製 linter を mini_racer で Ruby から実行する仕組み。検査能力は Herb と同じ |
| standard-erb | 0.1.0（2026-08） | 0.2 万 | rubocop-erb を Standard から読み込むアダプタ。中身は rubocop-erb |
| herb-linter / rubocop-herb（Marco Roth） | 0.0.1（2026-08） | 各 0.2 万 | 依存のない 0.0.1 で、名前の確保と思われる【推測】 |

ほかに、erb_lint や Herb のランナー（pronto-erb_lint, pronto-herb, guard-erb_lint, spring-commands-erb_lint, erb_lint_daemon）があります。

## 要フォローアップ

- **gem 名の衝突**: rubygems に Marco Roth 氏の `rubocop-herb` 0.0.1（2026-08-01 公開、"Herb Integration for RuboCop"）が登録されている【出典: rubygems API】。中身はプレースホルダとの報告あり。tk0miya/rubocop-herb の gem 名を検討する必要がある
- **rubocop 本体のリグレッション**: `Style/SafeNavigation` の `user&&.admin?` は rubocop 1.86.2 以降で起きる。ERB 以外の再現手順を作れれば upstream に報告できる

## 主な出典

- erb_lint: https://github.com/Shopify/erb_lint （`lib/erb_lint/linters/rubocop.rb`、README の Rubocop 節、issues [#126](https://github.com/Shopify/erb_lint/issues/126), [#142](https://github.com/Shopify/erb_lint/issues/142), [#228](https://github.com/Shopify/erb_lint/issues/228), [#299](https://github.com/Shopify/erb_lint/issues/299), [#326](https://github.com/Shopify/erb_lint/issues/326), [#331](https://github.com/Shopify/erb_lint/issues/331), [#332](https://github.com/Shopify/erb_lint/issues/332), [#383](https://github.com/Shopify/erb_lint/issues/383), [#461](https://github.com/Shopify/erb_lint/issues/461)、PRs [#300](https://github.com/Shopify/erb_lint/pull/300), [#413](https://github.com/Shopify/erb_lint/pull/413), [#454](https://github.com/Shopify/erb_lint/pull/454), [#457](https://github.com/Shopify/erb_lint/pull/457), [#464](https://github.com/Shopify/erb_lint/pull/464)）
- rubocop-erb: https://github.com/r7kamura/rubocop-erb （`lib/rubocop/erb/ruby_extractor.rb`、`config/default.yml`、issues [#5](https://github.com/r7kamura/rubocop-erb/issues/5), [#6](https://github.com/r7kamura/rubocop-erb/issues/6)）
- ruumba: https://github.com/ericqweinstein/ruumba （`lib/ruumba/parser.rb`、`lib/ruumba/analyzer.rb`、`lib/ruumba/rubocop_runner.rb`、`bin/ruumba`、README）
- RuboCop ruby_extractors API: https://github.com/rubocop/rubocop/pull/10839 、[#14954](https://github.com/rubocop/rubocop/pull/14954)
- Herb: https://github.com/marcoroth/herb （`src/analyze/parse_errors.c`、`javascript/packages/formatter/src/format-printer.ts`、issues [#356](https://github.com/marcoroth/herb/issues/356), [#670](https://github.com/marcoroth/herb/issues/670), [#2285](https://github.com/marcoroth/herb/issues/2285)）、https://github.com/rails/rails/pull/58552
- better_html: https://github.com/Shopify/better-html
- erb-formatter: https://github.com/nebulab/erb-formatter
- htmlbeautifier: https://github.com/threedaymonk/htmlbeautifier
- Rufo: https://github.com/ruby-formatter/rufo
- syntax_tree-erb: https://github.com/davidwessman/syntax_tree-erb
- Steep: https://github.com/soutaro/steep/issues/1409 、https://github.com/soutaro/steep/pull/1836
- sorbet_erb: https://github.com/franklinhu/sorbet_erb 、sorbet_view: https://github.com/kazzix14/sorbet_view
- erblint-github: https://github.com/github/erblint-github
