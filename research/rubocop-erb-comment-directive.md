# rubocop-erb で `<%# rubocop:disable %>` を効かせる方策の比較

調査日: 2026-10-31

rubocop-erb 0.8 系は、`Herb.extract_ruby` が ERB のコメント（`<%# … %>`）を空白にするので、そこに書いた無効化コメントが RuboCop に届きません（[rubocop-erb-0.8.md](rubocop-erb-0.8.md#無効化コメントのサポート実測)）。ERB のコメントは無効化コメントを書く場所として自然で、herb-lint の `<%# herb:disable … %>` とも書き方が揃うので、rubocop-erb に `<%# rubocop:disable … %>` のサポートを提案するため、考えられる 3 つの方策を 0.8.2 へのパッチとして試作し、同じ入力にかけて比べました。
【実測】は手元で実行して確かめたこと（再現手順は [repro/README.md](repro/README.md#rubocop-erb-で-erb-コメントの無効化コメントを効かせる方策)）、【出典】はソースコードで確かめたこと、【推測】は解釈です。

## 対象

- rubocop-erb 0.8.2 / rubocop 1.92.0 / herb 0.11.0（`Herb.extract_ruby` の出力は 0.11.1 でも確かめた）/ ruby 3.3.6
- 試作: [repro/rubocop-erb-comment-directive/lib/comment_directive.rb](repro/rubocop-erb-comment-directive/lib/comment_directive.rb)。環境変数 `ERB_COMMENT_DIRECTIVE` で方策を選ぶ
- 入力
  - [repro/erb-comment/](repro/erb-comment/) の 9 ファイル（[erb-comment-directive.md](erb-comment-directive.md#対象)）
  - [repro/rubocop-erb-0.8/disable/](repro/rubocop-erb-0.8/disable/) の 6 ファイル（[rubocop-erb-0.8.md](rubocop-erb-0.8.md#無効化コメントのサポート実測)）
  - 方策の違いを見るための例（[repro/rubocop-erb-comment-directive/input/](repro/rubocop-erb-comment-directive/input/)、18 ファイル。下の表）
  - 実際のビュー: rails/rails `0f591639b8` と kaigionrails/conference-app `25a02cc` の `*.html.erb`（333 ファイル。`<%#` を含むのは 17 ファイルで、`rubocop:` を書いたものはない）

| ファイル | 内容 |
|---|---|
| `leading_plain_comment.html.erb` | `<%# 見出し %><% if signed_in? %>` の後に本文と `<% end %>`（無効化ではないコメント） |
| `leading_syntax_error.html.erb` | `<%# rubocop:disable … %><%= link_to("a", path %>`（`)` が足りない） |
| `html_after_comment.html.erb` | `<%# rubocop:disable … %><p>a</p>` の次の行に `<%= "b" %>`（右側が HTML だけ） |
| `multibyte.html.erb` | `<%= "a" %><p>日本語</p><%# rubocop:disable … %>` |
| `disable_next.html.erb` | `<%# rubocop:disable-next … %>` の後に `<%= "a" %>` と `<%= "b" %>` |
| `malformed.html.erb` | cop 名のない `<%# rubocop:disable %>` |
| `redundant.html.erb` | 何も抑えない `<%# rubocop:disable Style/StringLiterals %>` |
| `plain_comments.html.erb` | `<%# TODO fix this %>` と `<%#no space %>`（無効化ではないコメント） |
| `empty_if_plain_comment.html.erb` | `<% if some_error %><%# note %>`⏎`<% end %>`（本文が空の `if` と、無効化ではないコメント） |
| `multiline_comment_autocorrect.html.erb` | 複数行の `<%# multi-line comment`⏎`  second line`⏎`%>` の後に `<%= link_to "a", url, {remote: true} %>` |
| `multiline_directive.html.erb` | `<%#`⏎`  rubocop:disable …`⏎` %>` の後に `<%= "a" %>` |
| `multiline_text.html.erb` | `<%#`⏎`  blah blah`⏎`  blah blah`⏎` %>` の後に `<%= link_to "a", url, {remote: true} %>`（無効化ではないコメント） |
| `multiline_second_line.html.erb` | `<%#`⏎`  Keep the legacy markup as is.`⏎`  rubocop:disable …`⏎`%>` の後に `<%= "a" %>`（説明の後に無効化） |
| `multiline_two_directives.html.erb` | `<%#`⏎`  rubocop:disable Style/StringLiterals`⏎`  rubocop:disable Layout/SpaceInsideHashLiteralBraces`⏎`%>` の後に `<%= link_to "a", url, {remote: true} %>` |
| `multiline_code_before.html.erb` | `<%= "a" %><%#`⏎`  rubocop:disable …`⏎`%>` の後に `<%= "b" %>`（`<%#` の前にコード） |
| `multiline_code_after.html.erb` | `<%#`⏎`  rubocop:disable …`⏎`%><%= "a" %>` の後に `<%= "b" %>`（`%>` の後ろにコード） |
| `multiline_column0.html.erb` | `<%#`⏎`rubocop:disable …`⏎`%>` の後に `<%= "a" %>`（無効化が行頭にある） |
| `multiline_column0_text.html.erb` | `<%#`⏎`- item`⏎`%>` の後に `<%= link_to "a", url, {remote: true} %>`（本文が行頭にある） |

## 試作した方策【出典】

| 方策 | 試作での名前 | 仕組み |
|---|---|---|
| 1. すべてのコメントを Ruby にする | `render_all` | `Herb.extract_ruby(source, comments: true)` を使う。`<%# a %>` は `  # a   `、`<% # a %>` は `   # a  ;` になる |
| 2. 安全なときだけ Ruby にする | `render_safe` | タグの右側（`%>` と同じ行の残り）に Ruby のコードがないコメントだけを、長さを変えずに Ruby のコメントにする。HTML は空白になるので、右側が HTML だけなら Ruby にする。複数行のコメントは、2 行目以降の行頭の空白 1 文字を `#` に置き換える。行頭に空白のない行があるコメントは、長さを変えずに `#` を置けないので空白のままにする |
| 3. 無効化コメントとしてだけ渡す | `directive_only` | 取り出す Ruby は変えない。ERB のコメントの行ごとに `Parser::Source::Comment` を作り、`ERBSource#comment_config` が返す `CommentConfig` にだけ渡す |

- 方策 2 の条件は、tk0miya/rubocop-herb（右側にタグも HTML もないときだけコメントにする）より緩い。右側の HTML は空白になり、コメントにしても Ruby の意味が変わらないからです
- 方策 2 は、`Herb.extract_ruby(comments: true)` の出力を使わず、Ruby のコメントを rubocop-erb の側で作った。`comments: true` は複数行のコメントで出力の長さを変えるため（[方策 1 で位置がずれる](#方策-1-で位置がずれる実測出典)）。`<% # … %>` は、中身をそのまま Ruby のコメントにする（`  ;` を補わない）
- 方策 3 のコメントは、ERB のコメントの 1 行につき 1 つ作る。1 行目は `<%#` の `#` から行末まで、2 行目以降は行頭から行末まで。テキストは ERB に書かれた文字列で、2 行目以降は行頭の空白 1 文字を `#` に置き換える（空白がなければ `#` を足す）。1 行目と、行頭に空白のある行は、`DirectiveComment#range` の位置が元の ERB と揃う
- 方策 3 で、複数行のコメント全体を 1 つのコメントとして渡すと、2 つ目以降の無効化コメントと、説明の行の後に書いた無効化コメントは認識されない。`DirectiveComment` は、テキストの中の最初の `# rubocop:` だけを見て、`#` と `rubocop:` の間に空白（改行を含む）しか許さないため【実測】
- 方策 3 では、`CommentConfig` のサブクラスで `each_directive`（private）を上書きし、`processed_source.comments` の後に ERB のコメントを足す。`processed_source.comments` 自体は変えないので、コメントを見る cop には届かない
- 方策 3 では、`CommentConfig#initialize` が `@no_directives`（`raw_source` に `rubocop` を含まなければ解析を飛ばす）を立てるので、元の ERB で判定し直す必要がある。`ERBSource` の `raw_source` は取り出した Ruby で、`<%#` の中身は空白になっているため
- 無効化が 1 行だけに効くか、`rubocop:enable` までの範囲に効くかは、どの方策でも RuboCop の判定（その行に Ruby のトークンがあるか）に任せた。HTML は空白なので、`<%# … %>` と HTML だけの行は「コメントだけの行」になる

## まとめ

- 3 つの方策とも、`<%#` の右側に Ruby のコードがない書き方（行末、独立した行、各行の行頭に空白がある複数行の `<%#`）では無効化が効きます。`disable-next` も効きます
- 複数行のコメントは、どの方策にも影響します。方策 1 は、`%>` か本文が行頭にあると位置がずれて autocorrect がテンプレートを壊し、`%>` の後ろのコードをコメントに入れます。方策 2 は、本文が行頭にあるコメントや `%>` の後ろにコードがあるコメントで、無効化が黙って効きません。方策 3 は、コメントを行ごとに分けて渡せば、試したすべての書き方で効きます（[複数行のコメント](#複数行のコメント実測)）
- 方策 1 は、ERB と違う Ruby を作ります。`<%#` の右側にある Ruby のコードがコメントに入るので、正しいテンプレートに `Lint/Syntax` が出たり（`leading_plain_comment.html.erb`）、構文エラーが報告されなくなったりします（`leading_syntax_error.html.erb`）。無効化コメントでない普通のコメントでも起きます
- 方策 1 は、herb 0.11 の `Herb.extract_ruby(comments: true)` が、`%>` か本文が行頭にある複数行の `<%#` で出力を長くするため、それより後ろの位置がずれます。autocorrect で `{remote: true}` が `{r emote: true}  %>` になり、テンプレートが壊れました（`multiline_comment_autocorrect.html.erb`、実際のビューの 1 ファイル）。無効化が行頭にある `multiline_column0.html.erb` では、コメントの中に空白を足し続けて RuboCop が無限ループを検出しました
- 方策 2 は、方策 1 の構文の問題を避けますが、`<%#` の右側にコードがあると無効化が黙って効きません（`leading.html.erb`）。効かないことを知らせる仕組みが別に要ります
- 方策 1 と 2 は、ERB のコメントがすべて Ruby のコメントとして cop に見えます。`Style/CommentAnnotation`、`Layout/LeadingCommentSpace`、`Layout/EmptyComment`、`Layout/EmptyLineAfterMagicComment` が新たに出て、`Lint/EmptyConditionalBody` はコメントを本文と見なして出なくなります
- 方策 3 は、取り出す Ruby を変えないので、無効化コメント以外の結果は 0.8.2 と同じです。実際のビュー 333 ファイルで offense に差はありませんでした。`<%#` の右側にコードがあっても、その行に効きます
- 方策 3 の弱点は、`processed_source.comments` を見る仕組みに ERB のコメントが届かないことです。cop 名のない `<%# rubocop:disable %>` に `Lint/CopDirectiveSyntax` が出ません。また、RuboCop の private なメソッド（`CommentConfig#each_directive`）と内部の変数（`@no_directives`）に依存します
- autocorrect で不要な無効化コメントを消す（`Lint/RedundantCopDisableDirective`）のは、3 つの方策のどれでも働きません。rubocop-erb の修正範囲の検査が、`<%#` の `#` を含む範囲の修正を捨てるからです。方策 3 だけ autocorrect が効かないわけではありません
- 【推測】提案するなら方策 3 がよいと考えます。ERB の意味（コメントは `%>` で終わる）を保ったまま無効化だけを効かせられ、既存の結果を変えないからです

## 無効化が効くか【実測】

1 ファイルずつ実行しました。「効く」は無効にした cop が出ないこと、「効かない」は出ることです。`empty_if.html.erb` は `Lint/EmptyConditionalBody` を `.erb` でも有効にした設定で実行しました。

| ファイル | 0.8.2 | 方策 1 | 方策 2 | 方策 3 |
|---|---|---|---|---|
| `erb-comment/trailing.html.erb` | 効かない | 効く | 効く | 効く |
| `erb-comment/after_if.html.erb` | 効かない | 効く | 効く | 効く |
| `erb-comment/leading.html.erb` | 効かない | `if` が検査されない | 効かない | 効く（その行だけ） |
| `erb-comment/indent.html.erb` | 効かない | 効く | 効く | 効く |
| `erb-comment/multiline_comment.html.erb` | 効かない | 効く。`Layout/EmptyComment` が出る | 効く。`Layout/EmptyComment` が出る | 効く |
| `erb-comment/empty_if.html.erb` | 効かない | 出ない（コメントを本文と見なす） | 出ない（同左） | 効く |
| `disable/erb_comment.html.erb` | 効かない | 効く | 効く | 効く |
| `disable/ruby_comment_tag.html.erb`（`<% # … %>`） | 効かない | 効くが、`Lint/CopDirectiveSyntax` が出る | 効く | 効く |
| `input/html_after_comment.html.erb` | 効かない | 効く（範囲） | 効く（範囲） | 効く（範囲） |
| `input/multibyte.html.erb` | 効かない | 効く | 効く | 効く |
| `input/disable_next.html.erb` | 効かない | 効く | 効く | 効く |

- `rubocop:enable` で閉じない独立した行の無効化には、どの方策でも `Lint/MissingCopEnableDirective` が出ます。位置は `<%#` の `#` です
- `leading.html.erb`（`<%# rubocop:disable … %><% if 'hello' %>…`）の方策 1 では、`if` から行末までがコメントになります。`Lint/LiteralAsCondition` は出ませんが、代わりに `Lint/CopDirectiveSyntax`、`Lint/MissingCopEnableDirective`、`Lint/RedundantCopDisableDirective` が出ます
- `leading.html.erb` の方策 2 では、コメントを Ruby にしないので無効化は効かず、効かないことを知らせる offense も出ません
- `leading.html.erb` の方策 3 では、同じ行に `if` のトークンがあるので、無効化はその行だけに効きます
- `html_after_comment.html.erb`（`<%# rubocop:disable … %><p>a</p>`）は、どの方策でも「コメントだけの行」として扱われ、ファイルの終わりまで効きます
- `empty_if.html.erb` の方策 1・2 は、無効化が効いたからではなく、`Lint/EmptyConditionalBody`（既定で `AllowComments: true`）がコメントだけの本文を空と見なさないからです
- `<% # … %>` の方策 1 は、`Herb.extract_ruby(comments: true)` がタグの終わりに `  ;` を補い（`# rubocop:disable Style/StringLiterals  ;`）、`Lint/CopDirectiveSyntax` が出ます。タグの中の行末のコメントと同じ問題です（[rubocop-erb-0.8.md](rubocop-erb-0.8.md#無効化コメントのサポート実測)）。方策 2 は `;` を補わないので出ません
- 変わらないもの: `not_erb_tag.html.erb`（`<# … %>` は ERB のタグではない）は、どの方策でも効きません。`multiline_tag.html.erb`、`multiline_range.html.erb`、タグの中の行末のコメント（`trailing_in_tag.html.erb`、`disable/trailing.html.erb`、`disable/trailing_output_tag.html.erb`）は、0.8.2 と同じ結果です

## 複数行のコメント【実測】

`<%#`⏎`  …`⏎`%>` のように複数行にわたる ERB のコメントは、ERB として正しい書き方です。行頭の空白の有無、無効化コメントの位置、前後のコードを変えて試しました。「効く」「効かない」は前の節と同じ意味です。

| ファイル | 0.8.2 | 方策 1 | 方策 2 | 方策 3 |
|---|---|---|---|---|
| `multiline_directive.html.erb` | 効かない | 効く | 効く。`Layout/EmptyComment` が出る | 効く |
| `multiline_text.html.erb`（無効化なし） | offense は同じ | 0.8.2 と同じ | `Layout/EmptyComment` が出る | 0.8.2 と同じ |
| `multiline_second_line.html.erb` | 効かない | 効く | 効く。`Layout/EmptyComment` が出る | 効く |
| `multiline_two_directives.html.erb` | 効かない | 2 つとも効く | 2 つとも効く。`Layout/EmptyComment` が出る | 2 つとも効く |
| `multiline_code_before.html.erb` | 効かない | 効く（2 行目から）。`Layout/EmptyComment`、`Layout/SpaceAfterSemicolon`、`Layout/SpaceBeforeComment` が出る | 効く（2 行目から）。`Layout/EmptyComment` が出る | 効く（2 行目から） |
| `multiline_code_after.html.erb` | 効かない | `%>` の後ろの `<%= "a" %>` がコメントに入る | 効かない | 効く |
| `multiline_column0.html.erb` | 効かない | 効くが、位置がずれ、`Layout/LeadingCommentSpace` が出る | 効かない | 効く |
| `multiline_column0_text.html.erb`（無効化なし） | offense は同じ | 位置がずれ、`Layout/LeadingCommentSpace` が出る | 0.8.2 と同じ | 0.8.2 と同じ |
| `multiline_comment_autocorrect.html.erb`（無効化なし） | offense は同じ | 位置がずれる | 0.8.2 と同じ | 0.8.2 と同じ |

- 無効化が効くときは、どの方策でも、無効化コメントを書いた行（`<%#` の行ではない）から `rubocop:enable` までの範囲に効きます。`multiline_code_before.html.erb` では、1 行目の `<%= "a" %>` には効かず、`<%= "b" %>` に効きます
- `multiline_directive.html.erb` と `multiline_text.html.erb`（どの行も行頭に空白がある）は、方策 1 でも出力の長さが変わらず、位置はずれません。位置がずれるのは、`%>` か本文が行頭にあるときです
- `multiline_code_after.html.erb` の方策 1 では、`%>` の行が `#      "a"  ;` になり、後ろのコードがコメントに入ります。1 行のコメントで右側のコードがコメントに入るのと同じ問題です（`leading.html.erb`）
- `multiline_code_after.html.erb` の方策 2 は、右側にコードがあるので Ruby にしません。`multiline_column0.html.erb` の方策 2 は、行頭に空白のない行（`rubocop:disable …`）に、長さを変えずに `#` を置けないので Ruby にしません。どちらも、効かないことを知らせる offense は出ません
- 方策 2 の `Layout/EmptyComment` は、`<%#` だけの 1 行目が `  #` になるためです。方策 1 は、herb が 1 行目の `#` を行頭に置き、次の行のコメントと続いた 1 つのコメントになるので出ません（`erb-comment/multiline_comment.html.erb` のように `<%#` がインデントされていると、方策 1 でも出ます）

### autocorrect

| ファイル | 0.8.2・方策 2・方策 3 | 方策 1 |
|---|---|---|
| `multiline_comment_autocorrect.html.erb` | `<%= link_to 'a', url, { remote: true } %>` | `<%= link_to "'a' url, {r emote: true}  %>` |
| `multiline_column0_text.html.erb` | `<%= link_to 'a', url, { remote: true } %>` | コメントの `- item` が `-  item` に、コードが `<%= link_to "a'a'url, {re mote: true} %>` になる |
| `multiline_column0.html.erb` | （方策 3 では無効化が効いて変わらない） | コメントの `rubocop:disable` の `r` の後ろに空白が 200 個以上入り、RuboCop が「Infinite loop detected」で止まる |

- 方策 1 の `Layout/LeadingCommentSpace`（`#` の後ろに空白がない）の修正は、ずれた位置で ERB のコメントの中に空白を足します。【推測】足した空白が `#` と `rubocop:` の間に入らないので、次の回の変換でも同じ offense が出続けると考えます

## 方策ごとの副作用【実測】

| ファイル | 0.8.2 | 方策 1 | 方策 2 | 方策 3 |
|---|---|---|---|---|
| `leading_plain_comment.html.erb`（正しいテンプレート） | offense なし | `Lint/Syntax`（unexpected token end） | offense なし | offense なし |
| `leading_syntax_error.html.erb`（構文エラー） | `Lint/Syntax` | `Lint/Syntax` が出ない。無効化コメントの offense が 3 件出る | `Lint/Syntax` | `Lint/Syntax` |
| `plain_comments.html.erb` | offense なし | `Style/CommentAnnotation`、`Layout/LeadingCommentSpace` | 同左 | offense なし |
| `empty_if_plain_comment.html.erb` | `Lint/EmptyConditionalBody` | `Lint/EmptyConditionalBody` が出ない。`Style/CommentAnnotation`（`note` をキーワードと見なす）が出る | 同左 | `Lint/EmptyConditionalBody` |
| `malformed.html.erb`（cop 名がない） | — | `Lint/CopDirectiveSyntax` | `Lint/CopDirectiveSyntax` | 出ない |

- 方策 1 では、`<%#` の右側にある Ruby のコードがすべてコメントに入ります。`leading_plain_comment.html.erb` では `if` が消えて `end` だけが残り、`leading_syntax_error.html.erb` では閉じていない `link_to(` が消えます。どちらも無効化コメントがなくても起きます（前者のコメントは「見出し」）
- 方策 1・2 で新たに出る cop は、ERB のコメントをテンプレートのメモとして書く使い方と合いません。`Layout/CommentIndentation` は、rubocop-erb が `.erb` で除外しているので出ません。`<%# TODO fix this %>` は autocorrect で `<%# TODO: fix this %>` に書き換わります
- 方策 3 は、ERB のコメントを `processed_source.comments` に入れないので、コメントを見る cop には何も起きません。その代わり、無効化コメントの書き方の誤り（`Lint/CopDirectiveSyntax`）も検出されません

### 実際のビュー（333 ファイル）

| | 0.8.2 | 方策 1 | 方策 2 | 方策 3 |
|---|---|---|---|---|
| offense の数 | 763 | 766 | 766 | 763 |
| 0.8.2 との差 | — | `Layout/EmptyLineAfterMagicComment` 3 件、列のずれ 2 件 | `Layout/EmptyLineAfterMagicComment` 3 件 | なし |

- `Layout/EmptyLineAfterMagicComment` は、rails のテストの `<%# encoding: utf-8 -%>` で始まる 3 ファイルに出ます。コメントになった `# encoding: utf-8` を Ruby のマジックコメントと見なすためです
- 列のずれは、conference-app の `admin/kaminari/_page.html.erb`（1〜9 行目が複数行の `<%#`）の 11 行目です。`Layout/SpaceInsideHashLiteralBraces` 2 件の列が、方策 1 だけ 1 つ右にずれます（次の節）

## 方策 1 で位置がずれる【実測・出典】

`Herb.extract_ruby` は、既定では入力と同じ長さの文字列を返します。`comments: true` を付けると、`%>` か本文が行頭にある複数行の `<%#` で、出力が入力より長くなります。herb 0.11.0 と 0.11.1 で同じです。

| 入力 | 入力のバイト数 | 出力のバイト数 | 出力 |
|---|---|---|---|
| `<%# a⏎  b⏎%>⏎<%= x %>⏎` | 22 | 23 | `#   a⏎# b⏎#  ⏎    x  ;⏎` |
| `<%# a⏎- b⏎%>⏎` | 13 | 15 | `#   a⏎#- b⏎#  ⏎` |
| `<%#⏎  a⏎ %>⏎`（どの行も行頭に空白がある） | 12 | 12 | `#  ⏎# a⏎#  ⏎` |
| `<%# a -%>⏎<%= x %>⏎`（1 行） | 19 | 19 | `  # a    ⏎    x  ;⏎` |

- 各行の先頭に `#` を置く。行頭に空白があれば、その 1 文字を `#` に置き換えるので長さは変わらない。行頭の `%>`（2 バイト）は `#  `（3 バイト）になり、行頭に空白がない行（`- b`）は `#` を足した分だけ長くなる
- rubocop-erb 0.8.2 の `RubyExtractor#extracted_ruby` は、出力の長さが入力と違えば、マルチバイト文字のせいだと見なして 1 文字ずつ並べ直す【出典】。長さの違いがマルチバイト文字によるものでないと、それより後ろの位置が 1 文字ずつずれる
- ずれた位置で autocorrect をかけると、テンプレートが壊れる。`multiline_comment_autocorrect.html.erb` の `<%= link_to "a", url, {remote: true} %>` は、方策 1 の `-A` で `<%= link_to "'a' url, {r emote: true}  %>` になる。0.8.2 と方策 2・3 では `<%= link_to 'a', url, { remote: true } %>` になる
- 【推測】行頭に空白のない行を、長さと行の数を変えずに Ruby のコメントにする方法はない。`#` を置く場所がなく、`=begin`/`=end` も行頭に独立した行が要るため。方策 1・2 のようにコメントを Ruby にする方策は、この行を位置をずらして Ruby にするか、Ruby にしない（無効化が効かない）かを選ぶことになる

## autocorrect と無効化コメント【実測・出典】

- `redundant.html.erb` の `Lint/RedundantCopDisableDirective` は、3 つの方策のどれでも `[Correctable]` として報告されず、`-A` でもファイルは変わらない
- rubocop-erb の `Corrector` は、修正の範囲が 1 つの ERB タグの Ruby の部分（`<%#` と `%>` の間）に収まらなければ修正を捨てる【出典: `lib/rubocop/erb/corrector.rb`】。無効化コメントの範囲は `#` から始まり、`#` は `<%#` の一部なので、どの方策でも修正が捨てられる
- 【推測】仮にこの検査を通しても、RuboCop が消すのは Ruby のコメントとしての範囲なので、`<%` や `%>` が残るおそれがある。不要な無効化コメントを消すには、タグ全体を消す扱いが別に要る
- 方策 3 で無効化コメント以外の cop の autocorrect が変わることはない。取り出す Ruby も、`processed_source.comments` も変えないため

## 考察【推測】

- 方策 1 は、実装は 1 行で済みますが、ERB のコメントが `%>` で終わるという意味を壊します。無効化コメントに限らず、`<%# メモ %><% if … %>` のような普通の書き方で誤った `Lint/Syntax` が出るので、既定の動作にはできません。herb の位置のずれ（複数行の `<%#`）も、先に直す必要があります
- 方策 2 は、方策 1 の構文の問題を避けますが、効く書き方と効かない書き方の境目（右側に Ruby のコードがあるか、複数行のコメントの行頭に空白があるか）がユーザーから見えません。tk0miya/rubocop-herb の `Herb/IgnoredCopDirective` のように、効かない無効化コメントを報告する cop が要ります。また、ERB のコメントがすべて Ruby のコメントとして cop に見える副作用は、方策 1 と同じく残ります。無効化コメント（`rubocop:` を含むもの）だけを Ruby にすれば、`Style/CommentAnnotation` などは避けられますが、`Lint/EmptyConditionalBody` がコメントを本文と見なす問題は残ります
- 方策 3 は、ERB の意味を変えずに、無効化の情報だけを RuboCop に渡します。`<%#` の右側にコードがあっても、その行に効くので、効く書き方と効かない書き方の境目がありません。herb-lint の `herb:disable` が書かれた行に効くのとも揃います
- 複数行のコメントは、方策 3 でも扱いを決める必要があります。コメント全体を 1 つの無効化コメントとして渡すと、2 つ目以降の無効化や、説明の後に書いた無効化が黙って無視されます。行ごとに分けて渡せば、方策 1 と同じく無効化を書いた行から効き、Ruby のコードも変えずに済みます。行頭に空白のない行でも効きます
- 方策 3 の課題は 2 つです。1 つは、RuboCop の private なメソッドへの依存です。`ProcessedSource` に「コメント以外から無効化コメントを足す」口があれば、それを使えます。もう 1 つは、`Lint/CopDirectiveSyntax` などの、`processed_source.comments` を見て無効化コメントの書き方を検査する仕組みに届かないことです。rubocop-erb が ERB のコメントだけを対象にした検査を持つか、RuboCop 側の口でまとめて扱う必要があります
- autocorrect については、どの方策でも不要な無効化コメントは消えないので、方策 3 の弱点ではありません。むしろ方策 3 は、コメントの範囲を rubocop-erb が決められるので、タグ全体を消す扱いを足しやすいと考えます

## 提案に含める点

- 方策 3（ERB のコメントを、取り出す Ruby には入れずに、無効化コメントとしてだけ RuboCop に渡す）を提案する。理由は、ERB の意味を保つこと、既存の結果を変えないこと（実際のビュー 333 ファイルで差なし）、どこに書いても効くこと
- 方策 1（`comments: true`）を採らない理由として、`leading_plain_comment.html.erb`、`leading_syntax_error.html.erb`、`multiline_comment_autocorrect.html.erb`、`multiline_code_after.html.erb`、`multiline_column0.html.erb`（autocorrect の無限ループ）の結果を示す。方策 2 を採らない理由として、複数行のコメントで無効化が黙って効かない書き方（`multiline_code_after.html.erb`、`multiline_column0.html.erb`）を示す
- 対象にするコメントは `<%# … %>` と、`#` で始まる 1 行のタグ `<% # … %>`。どちらも `Herb.extract_ruby` が空白にする
- 複数行の `<%#` は行ごとに無効化コメントとして扱い、無効化を書いた行から効かせる。1 つのコメントに複数の無効化を書けること、説明の後に無効化を書けること、行頭に空白がなくても効くことを示す（`multiline_second_line.html.erb`、`multiline_two_directives.html.erb`、`multiline_column0.html.erb`）
- 未解決の点として、`Lint/CopDirectiveSyntax` が働かないこと、RuboCop の private なメソッドへの依存、不要な無効化コメントの autocorrect を挙げる
- herb には別に、`Herb.extract_ruby(comments: true)` が、`%>` か本文が行頭にある複数行の `<%#` で位置を保たないことを報告できる
