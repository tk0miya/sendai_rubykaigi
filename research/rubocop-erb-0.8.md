# rubocop-erb 0.8 系と 0.7 系、tk0miya/rubocop-herb の比較

調査日: 2026-10-31

rubocop-erb は 0.8.0 で、ERB から Ruby を取り出す方式をタグ単位から `Herb.extract_ruby` による文書全体の変換に切り替えました（[r7kamura/rubocop-erb#70](https://github.com/r7kamura/rubocop-erb/pull/70)）。0.7 系（タグ単位）、0.8 系、tk0miya/rubocop-herb（以下「rubocop-herb」）の 3 つを、同じ入力にかけて比べた結果です。
【実測】は手元で実行して確かめたこと（再現手順は [repro/README.md](repro/README.md#rubocop-erb-08)）、【出典】はソースコードや PR の議論で確かめたこと、【推測】は解釈です。

## 対象

- rubocop-erb 0.7.2（2026-10-06。タグ単位の方式の最後の版。0.7.1 との違いは、存在しない cop 名を設定から消しただけ）
- rubocop-erb 0.8.2（2026-10-30。最新）
- rubocop-herb: https://github.com/tk0miya/rubocop-herb の `96d31cf8dff39109dbe4506b808e19693a92b2e2`（2026-10-29 時点の main）
- herb 0.11.0（rubygems のビルド済み gem）/ rubocop 1.92.0 / ruby 4.0.5。rubocop と herb は、3 つとも rubocop-herb の `Gemfile.lock` に揃えた
- 設定は 3 つとも `NewCops: enable`、`TargetRubyVersion: 3.4`。rubocop-herb はリポジトリの `config/develop/rubocop.yml` を継承し、`Herb/Linting` を無効にした（[repro/rubocop-erb-0.8/](repro/rubocop-erb-0.8/)）
- 入力
  - [repro/](repro/) の既存ツールの再現例と、[repro/herb-pr2260/edge/](repro/herb-pr2260/edge/) の境界ケース（32 ファイル）
  - 0.8 系向けの境界ケース（[repro/rubocop-erb-0.8/edge/](repro/rubocop-erb-0.8/edge/)、9 ファイル）
  - 無効化コメントの書き方ごとの例（[repro/rubocop-erb-0.8/disable/](repro/rubocop-erb-0.8/disable/)、6 ファイル）
  - 指摘の表示を見るための例（[repro/rubocop-erb-0.8/display/](repro/rubocop-erb-0.8/display/)、3 ファイル）
  - 実際のビュー: rails/rails `0f591639b8` と kaigionrails/conference-app `25a02cc` の `*.html.erb`（333 ファイル）

## まとめ

- 0.8 系は、marcoroth/herb#2260（[herb-pr2260.md](herb-pr2260.md)）と同じく `Herb.extract_ruby` で文書全体を 1 本の Ruby にします。0.7 系の見逃し（`Style/NegatedIf` など）、`Lint/Syntax` の除外、`count -1` を `count(-1)` にするような意味を壊す autocorrect は、いずれも解消しています
- herb#2260 との大きな違いは、**autocorrect の修正範囲を検査する仕組みがある**ことです。修正の範囲が 1 つの ERB タグの Ruby の中に収まらなければ、その offense の修正をまるごと捨てます。実際のビュー 333 ファイルで `-a`、`-A` とも HTML が変わったファイル、パースエラーが増えたファイルは 0 でした。0.7 系は `-A` で 2 ファイルを構文エラーにしました
- 誤検知への対策は、cop をファイル全体で除外することです。除外は 65 個（0.7 系は 53 個、rubocop-herb は 9 個）で、`Lint/Void`、`Lint/EmptyBlock`、`Style/SymbolProc`、`Style/SafeNavigation`、`Layout/LineLength` なども除外しています。このため、ERB でも妥当な指摘（本当に空のブロック、`map { |k| k.to_s }` など）も出ません
- 除外していない cop には、HTML が空白になることによる誤検知が残ります。実際のビューでは、`<%= cache "x" do %>…<% end %>` のように 1 行に書いたブロックに `Style/SingleLineDoEndBlock` と `Style/BlockDelimiters` が出て、`-a` で `do`⏎` %>…<% `⏎`end %>` のようにタグの中に改行が入ります（8 ファイル。出力は変わらない）
- 無効化コメントは、ERB でよく書く `<%# rubocop:disable … %>` が効きません。確実に効くのは、Ruby のコメントだけを書いた複数行のタグ（`<%`⏎`  # rubocop:disable …`⏎`%>`）です。タグの中の行末の `# rubocop:disable …` は効きますが、`Lint/CopDirectiveSyntax` が出ます（[無効化コメントのサポート](#無効化コメントのサポート実測)）
- 実際のビューで、0.8.2 と rubocop-herb の offense は、rubocop-herb の `Layout/LineLength`（162 件）などを除けばほぼ同じです。一方、**rubocop-herb には、HTML を含むファイルで `Style/MethodCallWithoutArgsParentheses` などの指摘や修正が消える問題**が見つかりました（[rubocop-herb-issues/reparse-cops-skip-html-files.md](rubocop-herb-issues/reparse-cops-skip-html-files.md)）。0.8.2 では起きません

## 0.8 系の仕組み【出典】

### 経緯

- PR #70 の作者は Cody Cutrer 氏（Instructure）。2026-06 に出され、2026-10-29 に r7kamura 氏がマージして 0.8.0 として公開した。issue [#6](https://github.com/r7kamura/rubocop-erb/issues/6)（タグを跨いだ構文を扱えない）を閉じている
- r7kamura 氏は、Redmine の ERB 534 ファイルで試し、壊れていた autocorrect が正しく動くようになったと述べている
- 同じコメントで、herb 0.9 系と 0.11 系で ERB タグの列の単位（バイト / 文字）が違い、マルチバイト文字を含む行の修正が黙って捨てられる問題を挙げ、0.8.0 で修正した（[#74](https://github.com/r7kamura/rubocop-erb/pull/74)）
- 0.8.1 では `Rails/Presence` を除外した（[#77](https://github.com/r7kamura/rubocop-erb/pull/77)）。`<% if a.present? %><%= a %><% end %>` が `if a.present?; a; end` に見えるため。0.8.2 では `Layout/EmptyLines` と `Layout/MultilineBlockLayout` を除外した（[#81](https://github.com/r7kamura/rubocop-erb/pull/81), [#82](https://github.com/r7kamura/rubocop-erb/pull/82)）
- PR の説明では、除外した cop は「ERB の文脈を理解させる PR で、今後有効に戻す」としている

### Ruby の取り出し

`lib/rubocop/erb/ruby_extractor.rb`（`lib/` 全体で 386 行）。

- `.erb` のファイルで `Herb.extract_ruby` を呼び、ファイル全体を 1 つの fragment（`offset: 0`）として返す。変換の結果は herb#2260 と同じで、`<%= foo %>` は `foo  ;`、HTML は空白、`<%# … %>` と `<% # … %>` の中身も空白になる（[herb-pr2260.md の変換の例](herb-pr2260.md#ruby-の取り出し)）
- HTML のマルチバイト文字は、`extract_ruby` が出すバイト数の空白を 1 文字の空白に戻し、文字位置を元の ERB と揃える
- `ERBSource`（`ProcessedSource` のサブクラス）が、元の ERB と `Herb.parse` の結果を持ち、各 ERB タグの範囲を引けるようにする

### autocorrect の検査

`lib/rubocop/erb/corrector.rb` が `RuboCop::Cop::Corrector` に prepend されます。

- 修正の操作ごとに、範囲が 1 つの ERB タグの Ruby の部分（`<%` と `%>` の間）に収まっているかを調べる
- 1 つでも外れる操作があれば、その offense の修正をすべて捨てる（`empty?` が真を返す）。offense は残り、`[Correctable]` の表示も残るが、修正されない
- 例外として、ERB タグで始まる行の行頭のインデントだけを変える空白の修正は通す。`Layout/CaseIndentation` のように範囲が `<%` に掛かるものは、行頭の空白だけに縮める
- 修正の結果を Herb でパースし直したり、HTML を比べたりはしない。範囲だけで判断する

### 除外している cop

`config/default.yml` で、`AllCops/Include` に `**/*.erb` を加え、次の 65 個の cop を `**/*.erb` から除外しています。

- Layout 37 個: `ArgumentAlignment`, `ArrayAlignment`, `BlockAlignment`, `ClosingParenthesisIndentation`, `CommentIndentation`, `ElseAlignment`, `EmptyLineAfterGuardClause`, `EmptyLines`, `EmptyLinesAroundBlockBody`, `EndAlignment`, `ExtraSpacing`, `FirstArgumentIndentation`, `FirstArrayElementIndentation`, `FirstArrayElementLineBreak`, `FirstHashElementIndentation`, `FirstHashElementLineBreak`, `FirstMethodArgumentLineBreak`, `FirstParameterIndentation`, `HashAlignment`, `IndentationConsistency`, `IndentationWidth`, `InitialIndentation`, `LeadingEmptyLines`, `LineEndStringConcatenationIndentation`, `LineLength`, `MultilineArrayBraceLayout`, `MultilineAssignmentLayout`, `MultilineBlockLayout`, `MultilineHashBraceLayout`, `MultilineMethodCallBraceLayout`, `MultilineMethodCallIndentation`, `MultilineMethodDefinitionBraceLayout`, `MultilineOperationIndentation`, `ParameterAlignment`, `SpaceBeforeSemicolon`, `TrailingEmptyLines`, `TrailingWhitespace`
- Lint 6 個: `DuplicateBranch`, `EmptyBlock`, `EmptyConditionalBody`, `EmptyFile`, `EmptyWhen`, `Void`
- Style 21 個: `EmptyElse`, `FrozenStringLiteralComment`, `IdenticalConditionalBranches`, `IfInsideElse`, `IfUnlessModifier`, `IfWithSemicolon`, `MultilineTernaryOperator`, `NestedTernaryOperator`, `Next`, `ParallelAssignment`, `RedundantCondition`, `RescueModifier`, `SafeNavigation`, `Semicolon`, `SoleNestedConditional`, `SymbolProc`, `TrailingCommaInArguments`, `TrailingCommaInArrayLiteral`, `TrailingCommaInHashLiteral`, `WhileUntilDo`, `WhileUntilModifier`
- `Rails/Presence`

`Lint/Syntax` と `Lint/UselessAssignment` は除外していません（0.7 系は除外していた）。`Style/BlockDelimiters`、`Style/SingleLineDoEndBlock`、`Style/ConditionalAssignment`、`Naming/FileName` も除外していません。

### 3 つの違い

| | 0.7 系 | 0.8 系 | rubocop-herb |
|---|---|---|---|
| ERB の読み方 | Herb の AST からタグを 1 つずつ | `Herb.extract_ruby`（Herb の lexer） | Herb の AST |
| 単位 | タグ 1 つ = 1 fragment。`if` / `end` などを正規表現で削る | 文書全体で 1 fragment | 文書全体で 1 fragment |
| `<%= foo %>` | `foo` | `foo  ;` | `_ = foo;` |
| HTML | なし（タグの外は渡さない） | 空白 | `div;` などの識別子 |
| `Lint/Syntax` | 除外 | 有効 | 有効 |
| 誤検知への対策 | 53 個の cop をファイル全体で除外 | 65 個の cop をファイル全体で除外 | 9 個をファイル全体で除外し、ほかは ERB の構造を見て誤検知になる行だけで無効にする（[report.md](report.md#除外している-cop-と行単位で無効にしている-cop)） |
| autocorrect の検査 | なし | 修正範囲が 1 つのタグの Ruby に収まるか | 修正後の ERB の HTML とパース結果を比べる（`CopCorrectionGuard`。[report.md](report.md#autocorrect-の検査copcorrectionguard)） |
| `<%# rubocop:disable … %>` | 効かない【実測】 | 効かない【実測】 | 効く【実測】 |
| 無効化コメントの範囲 | 同じタグの中だけ【実測】 | ファイル全体。ただし Ruby のコメントだけを書いた複数行のタグか、タグの中の行末に書いたときだけ効く【実測】 | ファイル全体【実測】 |
| `<%%= … %>`（エスケープしたタグ） | 中身を Ruby として検査し、`-a` で書き換える【実測】 | 検査しない | 検査しない |
| 規模（`lib/`） | 466 行 | 386 行 | 約 3,200 行 |

## 既存の再現例と境界ケースでの結果【実測】

`erb_lint`、`rubocop-erb`、`ruumba`、`herb/app`、`herb-pr2260/edge` の 32 ファイルにかけた結果です。

| | 0.7.2 | 0.8.2 | rubocop-herb |
|---|---|---|---|
| offense の数 | 24 | 33 | 37 |

0.7.2 だけに出るもの、出ないもの:

- `Lint/AmbiguousOperator`（3 件）、`Lint/RedundantSplatExpansion`（1 件）: `<% count = items.size %>` の後の `<%= count -1 %>` など。前のタグの変数が見えないための誤検知（[existing-erb-linters.md](existing-erb-linters.md#rubocop-erb)）。0.8.2 と rubocop-herb は `Layout/SpaceAroundOperators` を出す
- `Style/NegatedIf`、`Style/NegatedUnless`、`Style/MultilineIfThen`、`Lint/UselessAssignment`、`Lint/Syntax` は 0.7.2 では出ない（タグ単位で `if` を削る、または除外しているため）

0.8.2 と rubocop-herb の違い:

| cop | 例 | 0.8.2 | rubocop-herb |
|---|---|---|---|
| `Lint/UnusedBlockArgument` | `<% items.each do \|i\| %><li>item</li><% end %>` | 出ない。本文が空のブロックに見え、RuboCop の既定（`IgnoreEmptyBlocks`）で対象外になる | 出る |
| `Style/EmptyElse`, `Lint/EmptyConditionalBody` | `erb_lint/recommended/control_flow.html.erb` の本当に空の `else` / `unless` | 除外しているので出ない | 出る |
| `Style/SafeNavigation` | `<% if user && user.admin? %>` | 除外しているので出ない | 出る。`-A` で `user&.admin?` に正しく修正 |
| `Style/CommentAnnotation` | `<% # note %>` | 出ない（コメントが空白になる） | 出る |
| `<%# rubocop:disable Style/StringLiterals %>` | `herb-pr2260/edge/disable.html.erb` | 効かず、次の行の `"a"` に `Style/StringLiterals` が出る | 効く。`Lint/MissingCopEnableDirective` が出る |
| `<% x = "b" # rubocop:disable … %>` | 同上 | 効くが、`Lint/CopDirectiveSyntax`（Malformed directive comment）が出る。`extract_ruby` がタグの終わりに補う `  ;` がコメントの中に入るため | 効く |

0.8 系向けの境界ケース（[repro/rubocop-erb-0.8/edge/](repro/rubocop-erb-0.8/edge/)、9 ファイル）の結果です。

| ファイル | 0.7.2 | 0.8.2 | rubocop-herb |
|---|---|---|---|
| `single_line_block.html.erb`（`<%= cache "fragment" do %>…<% end %>`） | 出ない | `Style/SingleLineDoEndBlock`、`Style/BlockDelimiters`（誤検知） | 出ない（その行だけで無効にしている） |
| `cond_assign.html.erb`（`if` / `else` の各分岐で `<% x = 1 %>`） | 出ない | `Style/ConditionalAssignment`（`x = if a … end` にせよ）。ERB には合わない指摘。修正は捨てられる | 出ない |
| `unless_else.html.erb`（`unless` / `else` の本文が HTML） | 出ない | `Style/UnlessElse`。修正は捨てられる | `Style/UnlessElse` |
| `empty_lines.html.erb`（ERB タグの間に空行を含む HTML） | 出ない | 出ない（除外） | `Layout/EmptyLines`（誤検知） |
| `symbol_proc.html.erb`（`<% users.map { \|u\| u.name }.each do \|name\| %>`） | `Style/SymbolProc` | 出ない（除外） | `Style/SymbolProc` |
| `escaped_tag.html.erb`（`<%%= link_to "a", a_path %>`） | `<%%=` の中身に `Style/StringLiterals` | 出ない | 出ない |
| `multibyte.html.erb`（HTML と Ruby に絵文字と日本語） | 位置は正しい | 位置は正しく、`-A` の結果も元の位置に書き戻される | 同左 |
| `reparse_cops_in_html.html.erb`（`<div>` の中の `root_path()`、`(a == b) ? …`、`(foo)`） | 3 つとも出る | 3 つとも出て、`-A` で正しく修正 | `Style/MethodCallWithoutArgsParentheses` と `Style/RedundantParentheses` が出ない。`Style/TernaryParentheses` は出るが修正されない（下記） |
| `disable_inline.html.erb`（タグの中の行末の `# rubocop:disable`） | 出ない | `Lint/CopDirectiveSyntax`（誤検知） | 出ない |

## 無効化コメントのサポート【実測】

[repro/rubocop-erb-0.8/disable/](repro/rubocop-erb-0.8/disable/) の 6 ファイルで、`Style/StringLiterals` を無効にするコメントを書き方ごとに試した結果です。どのファイルも、コメントの後の行に `"a"` などの二重引用符の文字列があります。

| ファイル | 書き方 | 0.7.2 | 0.8.2 | rubocop-herb |
|---|---|---|---|---|
| `erb_comment.html.erb` | `<%# rubocop:disable Style/StringLiterals %>` | 効かない | 効かない | 効く |
| `ruby_comment_tag.html.erb` | `<% # rubocop:disable Style/StringLiterals %>` | 効かない（同じタグの中だけに効く） | 効かない | 効く |
| `trailing.html.erb` | `<% x = "b" # rubocop:disable Style/StringLiterals %>` | その行に効く | その行に効くが、`Lint/CopDirectiveSyntax` が出る | その行に効く |
| `trailing_output_tag.html.erb` | `<%= "a" # rubocop:disable Style/StringLiterals %>` | その行に効く | その行に効くが、`Lint/CopDirectiveSyntax` が出る | その行に効く |
| `multiline_tag.html.erb` | `<%`⏎`  # rubocop:disable Style/StringLiterals`⏎`  x = "b"`⏎`%>` の後に `<%= "c" %>` | 同じタグの中の `x = "b"` だけに効く | 後の `<%= "c" %>` にも効く | 後の `<%= "c" %>` にも効く |
| `multiline_range.html.erb` | `<%`⏎`  # rubocop:disable …`⏎`%>` と `<%`⏎`  # rubocop:enable …`⏎`%>` で範囲を区切る | 効かない | 範囲の中だけに効く | 範囲の中だけに効く |

- 0.8.2 では、`Herb.extract_ruby` が `<%# … %>` と、`#` で始まる 1 行のタグ（`<% # … %>`）の中身を空白にするので、そこに書いた無効化コメントは RuboCop に届かない
- タグの中の行末に書いたコメントは届くが、`extract_ruby` がタグの終わりに補う `  ;` がコメントの中に入り（`# rubocop:disable Style/StringLiterals  ;`）、`Lint/CopDirectiveSyntax`（Malformed directive comment）が出る。無効化そのものは効く
- コメントの後で改行してから `%>` を書けば、補われる `;` が次の行に回るので、通常の Ruby のコメントとして扱われる。ファイル全体に効き、`# rubocop:enable` で範囲を区切れる
- 0.7.2 はタグ 1 つを 1 つの Ruby として検査するので、無効化コメントは同じタグの中にしか効かない。`<% # rubocop:disable … %>` では、そのタグに `Lint/MissingCopEnableDirective` が出る
- rubocop-herb は、右側に別のタグや HTML がない `<%# … %>` を Ruby のコメントに変換するので、どの書き方でも効く。右側にタグや HTML があって効かない書き方は、`Herb/IgnoredCopDirective` が報告する（[report.md](report.md#herbignoredcopdirective-cop)）

## 指摘の表示【実測・出典】

0.8 系は、HTML を空白にした Ruby（`Herb.extract_ruby` の出力）を RuboCop に渡します。rubocop-herb は、HTML を識別子にした Ruby を渡し、表示用に HTML を書き戻したソース（hybrid code）を使います。指摘の表示に違いが出るかを確かめました。

- 指摘の行の表示（`--format clang` などのソースの抜粋とキャレット）は、3 つとも元の ERB の行になる。HTML やマルチバイト文字を含む行でも、HTML は空白にならず、キャレットの位置も同じ（`display/show.html.erb`）
  - RuboCop 1.92 は、extractor が返した fragment で見つかった offense の範囲を、元のファイルのバッファに付け替えてから報告する（`RuboCop::Cop::Base#range_for_original`）。0.8 系は文字位置を元の ERB に揃えているので、付け替えた範囲がそのまま元の ERB の正しい位置になる
- 実際のビュー 333 ファイルで、同じ位置に出た offense のメッセージは、0.8.2 と rubocop-herb で 1 件を除いて同じだった。違ったのは rails の `syntax_error.html.erb` の `Lint/Syntax` で、0.8.2 は「unexpected ';'; expected an argument」、rubocop-herb は「unexpected end-of-input; expected a `)` to close the arguments」
- 構文エラーのメッセージには、ERB に書かれていない `;` が出ることがある。0.8.2 も rubocop-herb もタグの終わりに `;` を補うためで、`<p><%= link_to("a", path %></p>` には両方で「unexpected ';'; expected a `)` to close the arguments」が出る（`display/unclosed_paren.html.erb`）。キャレットは、0.8.2 では `%>` の `>` を、rubocop-herb では `%>` の前の空白を指す
- メッセージにコードを引用する cop では、変換後の Ruby が出ることがある。rubocop-herb の `Style/IdenticalConditionalBranches` は、`<%= foo %>` について「Move `_ = foo` out of the conditional.」と報告する（`display/identical_branches.html.erb`）。`_ =` は rubocop-herb が `<%=` の位置に書く印で、ERB には書かれていない。0.8 系はこの cop を除外しているので出ない

## autocorrect の結果【実測】

既存の再現例と境界ケース（32 ファイル）で、`-a` と `-A` の前後を比べた結果です（[html_changes.rb](repro/herb-pr2260/html_changes.rb)。HTML は空白の違いを無視して比べる）。

| | 書き換わったファイル | HTML が変わった | パースエラーが増えた |
|---|---|---|---|
| 0.7.2 `-a` | 15 | 0 | 0 |
| 0.7.2 `-A` | 16 | 0 | 1 |
| 0.8.2 `-a` | 18 | 0 | 0 |
| 0.8.2 `-A` | 18 | 0 | 0 |
| rubocop-herb `-a` | 18 | 0 | 0 |
| rubocop-herb `-A` | 19 | 0 | 0 |

`html_changes.rb` は HTML とパースエラーだけを見るので、Ruby の意味が変わる修正は数えていません。修正の中身は次のとおりです。

| 修正前 | 0.7.2 `-A` | 0.8.2 `-A` | rubocop-herb `-A` |
|---|---|---|---|
| `<% count = items.size %>`⏎`<p><%= count -1 %></p>` | `count(-1)`（意味が変わる） | `count - 1` | `count - 1` |
| `<%= item *2 %>`（ブロック引数） | `item(2)`（意味が変わる） | `item * 2` | `item * 2` |
| `<% if user && user.admin? %>` | `user&&.admin?`（構文エラー） | 変わらない（`Style/SafeNavigation` を除外） | `user&.admin?` |
| `<% if !user.nil? %>` | 変わらない | `unless user.nil?` | `unless user.nil?` |
| `<% unused = 1 %>`（未使用の変数） | 変わらない | `<% 1 %>` が残る（`Lint/Void` を除外しているので、offense も出ない） | タグごと消える |
| `<% items.each do \|i\| %>`（`i` は未使用） | 変わらない | 変わらない | `\|_i\|` |
| `<% if !foo.nil? then %>`…`<% else %>`⏎`<% end %>`（空の `else`） | 変わらない | `then` を消す。空の `else` は残る | `then` と空の `else` を消す |
| `<%= cache "fragment" do %>This bit is cached<% end %>`（`rubocop-erb-0.8/edge/single_line_block.html.erb`） | `'fragment'` だけ | `<%= cache 'fragment' do`⏎` %>This bit is cached<% `⏎`end %>` | `'fragment'` だけ |

- 0.8.2 で捨てられた修正（`Style/UnlessElse`、`Style/ConditionalAssignment` など）は、`[Correctable]` の表示のまま offense として残る
- 0.8.2 の `Style/SingleLineDoEndBlock` の修正は、`do` の後と `end` の前に改行を入れる。範囲がそれぞれ 1 つのタグの Ruby に収まるので、検査を通る。改行はタグの中に入るので出力は変わらないが、`%>` が行頭に、`<% ` が行末の空白付きで残る

## 実際のビューでの結果【実測】

rails/rails と kaigionrails/conference-app の `*.html.erb`（333 ファイル）にかけた結果です。

| | 0.7.2 | 0.8.2 | rubocop-herb |
|---|---|---|---|
| offense の数 | 762 | 763 | 933 |
| offense のあるファイル | 143 | 151 | 167 |
| `-a` で書き換わったファイル | 143 | 143 | 140 |
| うち HTML が変わったファイル | 0 | 0 | 0 |
| `-A` でパースエラーが増えたファイル | 2 | 0 | 0 |
| `-A` の後に残る offense | — | 9 | 126（うち `Layout/LineLength` 94） |
| 実行時間（`--cache false`、検出のみ） | 6.0〜7.5 秒 | 2.2 秒 | 3.3 秒 |

### 0.7.2 と 0.8.2 の違い

- 0.7.2 だけに出るもの: `Style/StringLiterals` 18 件は、rails の認証ジェネレーターのテンプレート（`passwords/edit.html.erb` など 3 ファイル）の `<%%= form.submit "Save" %>` の中身。`<%%=` は `<%=` という文字列を出力するエスケープで、中身は Ruby ではない。**0.7.2 は `-a` でこれを `'Save'` に書き換え、ジェネレーターが生成するコードを変える**。`html_changes.rb` は `<%%` をテキストとして比べないので、この変化を数えていない
- 0.7.2 だけに出るもの: `Layout/ExtraSpacing` 6 件と `Layout/SpaceBeforeFirstArg` 2 件（`<%= render              "header" %>` など。0.8.2 は `Layout/ExtraSpacing` を除外）、`Style/SafeNavigation` 2 件と `Style/SymbolProc` 1 件（0.8.2 は除外）
- 0.7.2 の `-A` は、`<% if @part && @part.mime_type %>` を `@part&&.mime_type`（構文エラー）に、`<%= !!user_bookmarks.find { … } %>` を `!user_bookmarks.find { … }.nil?.nil?`（常に `true`）に書き換える
- 0.8.2 だけに出るもの: `Lint/AssignmentInCondition` 3 件、`Lint/LiteralAsCondition` 2 件、`Naming/VariableNumber` 2 件、`Style/HashEachMethods` 1 件、`Lint/Syntax` 1 件（rails の `syntax_error.html.erb`。わざと構文エラーにした fixture）、`Naming/FileName` 3 件。いずれもタグを跨いで読めるようになったことによるもので、rubocop-herb にも同じものが出る
- 0.8.2 だけに出るもの: `Style/SingleLineDoEndBlock` 10 件、`Style/BlockDelimiters` 8 件。下記

### 0.8.2 と rubocop-herb の違い

| cop | 0.8.2 | rubocop-herb | 内容 |
|---|---|---|---|
| `Layout/LineLength` | 0 | 162 | 0.8.2 は除外。rubocop-herb の指摘の内容は [herb-pr2260.md](herb-pr2260.md#layoutlinelength) |
| `Lint/EmptyFile` | 0 | 16 | 0.8.2 は除外。0 バイトのテンプレート |
| `Layout/EmptyLineAfterMagicComment` | 0 | 3 | `<%# encoding: utf-8 -%>` の次の行。0.8.2 では `<%# … %>` が空白になるので出ない。rubocop-herb は `-a` で空行を挿入し、テンプレートの出力が変わる（[herb-pr2260.md](herb-pr2260.md#layoutemptylineaftermagiccomment)） |
| `Layout/HashAlignment` | 0 | 3 | 0.8.2 は除外。複数行に渡る `link_to` の引数の揃え |
| `Lint/EmptyBlock` | 0 | 2 | 0.8.2 は除外。2 件とも本当に空のブロック（`<%= check_box_tag … do %>`⏎`<% end %>` など） |
| `Style/SymbolProc` | 0 | 1 | 0.8.2 は除外。`<%= local_assigns.keys.map {\|k\| k.to_s }.sort.join(",") -%>` で、妥当な指摘 |
| `Style/SafeNavigation` | 0 | 1 | 0.8.2 は除外。`<% if @part && @part.mime_type %>` で、妥当な指摘 |
| `Style/RescueModifier` | 0 | 1 | 0.8.2 は除外。`<% corrections = exception_wrapper.corrections rescue [] %>`。rubocop-herb は `-a` で `begin`〜`end` に展開する |
| `Style/IfUnlessModifier` | 0 | 1 | 0.8.2 は除外。rubocop-herb の指摘は HTML を含めた行の長さによる |
| `Style/SingleLineDoEndBlock` | 10 | 0 | 下記 |
| `Style/BlockDelimiters` | 8 | 0 | 下記 |
| `Style/MethodCallWithoutArgsParentheses` | 2 | 0 | conference-app の `admin_talks_path()`。rubocop-herb の見逃し（下記） |

`Lint/Syntax` は両方に 1 件出ます（同じファイルで、報告する位置が違う）。

#### `Style/SingleLineDoEndBlock` と `Style/BlockDelimiters`

- 8 ファイルとも、rails のテスト用 fixture の `<%= cache "fragment" do %>This bit's fragment cached<% end %>` のように、1 行に書いた本文が HTML のブロック。HTML が空白になるので、Ruby としては 1 行の `do`〜`end` ブロックに見える
- `Style/BlockDelimiters` の `{ … }` にせよという指摘は、ERB では従えない（herb-lint の `erb-prefer-do-end-blocks` も `do`〜`end` を勧める）。修正は 3 件だけ `[Correctable]` が付くが、`-A` でも捨てられる
- `Style/SingleLineDoEndBlock` の修正は検査を通り、`-a` で 8 ファイルが次のように書き換わる。出力は変わらない

```erb
<%= cache 'fragment' do
 %>This bit's fragment cached<% 
end %>
```

#### rubocop-herb の `Style/MethodCallWithoutArgsParentheses` の見逃し

conference-app の `admin/talks/index.html.erb` の `<%= link_to "All events talks", admin_talks_path(), class: "…" %>` に、0.7.2 と 0.8.2 は `Style/MethodCallWithoutArgsParentheses` を出しますが、rubocop-herb は出しません。

- RuboCop 1.92.0 の `Style/MethodCallWithoutArgsParentheses` は、括弧を外した結果をパースし直し、AST が変わらないことを確かめてから offense を出す（`ReparsedEquivalence`）。`Style/RedundantParentheses` も同じ確認をし、`Style/TernaryParentheses` は修正の前に同じ確認をする
- rubocop-herb は、HTML を含むファイルでは、`ProcessedSource` のバッファの中身を、HTML を戻した文字列（hybrid code）に置き換え、AST の HTML の識別子の名前も書き換える（`div` → `div__html0`）。このため、パースし直す対象が Ruby ではなくなり、確認が必ず失敗する
- 結果として、HTML を 1 つでも含むテンプレートでは、`Style/MethodCallWithoutArgsParentheses` と `Style/RedundantParentheses` の offense が消え、`Style/TernaryParentheses` は offense は出るものの修正されない。HTML を含まないテンプレートでは起きない
- 実際のビューでは、`Style/TernaryParentheses` の `<%= (name == trace_to_show) ? 'block' : 'none' %>`（rails の `rescues/_trace.html.erb`）を、0.8.2 は `-a` で修正し、rubocop-herb は修正しない
- 再現レポート: [rubocop-herb-issues/reparse-cops-skip-html-files.md](rubocop-herb-issues/reparse-cops-skip-html-files.md)

## 評価【推測】

- 0.8 系で、rubocop-erb は ruumba・herb#2260・rubocop-herb と同じ「文書全体を 1 本の Ruby にする」方式になった。0.7 系の見逃しと、意味や構文を壊す autocorrect は解消しており、0.7 系から上げない理由はない
- 0.8 系の修正範囲の検査は単純だが効果が大きい。herb#2260 を壊していた `Layout/ExtraSpacing` や `Lint/Void` の修正は、どれも範囲が ERB の区切りや HTML に掛かるので、仮に有効にしても捨てられる。実際のビューで HTML を壊さなかった点は rubocop-herb と同じ
- ただし範囲しか見ないので、範囲がタグの中に収まる限り、ERB に合わない修正も通る。`Style/SingleLineDoEndBlock` の改行の挿入がその例。出力は変わらないが、ERB としては不自然な形になる。`<%= foo %>` の式を消すような修正（出力が変わる）も、範囲がタグの中なら止まらない。今回の入力では、`<% unused = 1 %>` → `<% 1 %>` のように `<%` のタグの中で起きた例だけだった
- 誤検知への対策がファイル全体での除外なので、0.8 系では妥当な指摘も失われる。`Lint/EmptyBlock`、`Style/SymbolProc`、`Style/SafeNavigation`、`Style/EmptyElse` などは、rubocop-herb では ERB の構造を見て誤検知になる行だけで無効にしているので、本当に空のブロックや `map { |k| k.to_s }` を指摘できる。PR #70 の説明どおり、ERB の文脈を cop に教える改修が進めば差は縮まる
- `Lint/Void` を除外しているので、`Lint/UselessAssignment` の修正の後に `<% 1 %>` が黙って残る。offense も出ないので、利用者は気付きにくい
- `<%# rubocop:disable … %>` が効かないことは、既存のテンプレートに 0.8 系を入れるときの障害になりうる。このコメントで抑えていた指摘が、まとめて出る。タグの中の行末のコメントは効くが、`Lint/CopDirectiveSyntax` が出るので、実用上は使いにくい。0.8 系で無効化コメントを使うなら、Ruby のコメントだけを書いた複数行のタグにするのが確実
- rubocop-herb にとっては、0.8 系が同じ土俵の比較対象になった。rubocop-herb の利点は、`<%=` と HTML の意味を残した変換と行単位の無効化により、除外する cop が少ないこと、修正後の ERB を検査すること、`<%# rubocop:disable %>` が効くこと。一方で、変換が複雑なぶん、`ReparsedEquivalence` のような RuboCop 側の仕組みと噛み合わない箇所がある。0.8 系は `Herb.extract_ruby` の結果をそのまま RuboCop に渡すので、この種の問題は起きにくい
