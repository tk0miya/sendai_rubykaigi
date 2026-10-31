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
  - 方策の違いを見るための例（[repro/rubocop-erb-comment-directive/input/](repro/rubocop-erb-comment-directive/input/)、38 ファイル。下の表）
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
| `redundant_enable.html.erb` | `<%= 'a' %>` の後に、無効にしていない cop の `<%# rubocop:enable Style/StringLiterals %>` |
| `orphan_pop.html.erb` | `<%= 'a' %>` の後に、対応する `push` のない `<%# rubocop:pop %>` |
| `directive_scope.html.erb` | `<%# rubocop:disable … %>`、`<%= "a" %>`、`<%# rubocop:enable … %>`（1 つの文だけを囲む） |
| `suppressed_exception.html.erb` | `<% begin %>`、`<%= render "a" %>`、`<% rescue %>` の後に、本文がコメントだけの `<%# ignore errors from the partial %>` と `<% end %>`（各タグが別の行） |
| `consecutive_annotations.html.erb` | `<%# TODO fix this %>` と `<%# TODO fix that %>` が続く 2 行 |
| `inline_comment.html.erb` | 独立した行の `<%# heading %>` の後に `<%= foo %>`（`Style/InlineComment` を有効にして実行） |
| `multiline_hash.html.erb`、`multiline_column0_hash.html.erb` | 複数行の `<%#` の中に、`#` を付けて `  # rubocop:disable …` / 行頭から `# rubocop:disable …` と書いたもの |
| `multiline_tab_hash.html.erb` | 複数行の `<%#` の中に、タブで字下げして `# rubocop:disable …` と書いたもの |
| `no_space.html.erb`、`multiline_no_space.html.erb` | `#` の後に空白のない `<%#rubocop:disable … %>` / 複数行の `<%#` の中の `  #rubocop:disable …` |
| `multiline_one_space.html.erb`、`multiline_tab.html.erb` | 複数行の `<%#` の中の `rubocop:disable …` を、空白 1 文字 / タブ 1 文字で字下げしたもの |
| `excluded_*.html.erb`（6 ファイル） | `while` の 1 行目・本文・`end` の行に `<%# … %>` があるもの、ガード節（`<% next if … %>`）の次の行に `<%# … %>` があるもの、`rescue` の本文が `<%# rubocop:disable Lint/SuppressedException %>` だけのもの。rubocop-erb が `.erb` で除外している cop を有効にして実行（[除外されている cop](#除外されている-cop実測)） |
| `empty_if_with_directive.html.erb` | `directive_scope.html.erb` と同じ 3 行の後に、`<% if x %><%# note %>`⏎`<% end %>`（本文が空の `if`） |
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
| 2. 条件を満たす無効化コメントの行だけを Ruby にする | `render_directives` | ERB のコメントのうち、無効化コメントを書いた行だけを、その場で長さを変えずに Ruby のコメントにする。ほかの行とほかの ERB のコメントは空白のまま。Ruby のコメントにできない行は、試作の cop `Erb/IgnoredCopDirective` が報告する（[方策 2](#方策-2無効化コメントの行だけを-ruby-にする実測)） |
| 2a. （参考）安全なときだけコメント全体を Ruby にする | `render_safe` | タグの右側（`%>` と同じ行の残り）に Ruby のコードがないコメントだけを、長さを変えずに Ruby のコメントにする。HTML は空白になるので、右側が HTML だけなら Ruby にする。複数行のコメントは、2 行目以降の行頭の空白 1 文字を `#` に置き換える。行頭に空白のない行があるコメントは、長さを変えずに `#` を置けないので空白のままにする |
| 3. 無効化コメントとしてだけ渡す | `directive_only` | 取り出す Ruby は変えない。ERB のコメントの行ごとに `Parser::Source::Comment` を作り、`ERBSource#comment_config` が返す `CommentConfig` にだけ渡す |
| 3'. 方策 3 ＋ cop へのパッチ | `directive_only_cops` | 方策 3 に加え、`CommentConfig` を通さずに無効化コメントを探す 3 つの cop にパッチを当てる（[方策 3 で働かない cop](#方策-3-で働かない-cop実測出典)） |
| 3''. `processed_source.comments` に足す | `comments_all` | 取り出す Ruby は変えない。方策 3 と同じコメントを `ERBSource#comments` に足し、すべての cop に見せる（[processed_source.comments に足す場合](#processed_sourcecomments-に足す場合実測出典)） |

- 方策 2a は、方策 2 の比較のために測った参考の形で、提案には含めない。無効化コメントに限らず、ERB のコメント全体を Ruby のコメントにする
- 方策 2a の条件は、tk0miya/rubocop-herb（右側にタグも HTML もないときだけコメントにする）より緩い。右側の HTML は空白になり、コメントにしても Ruby の意味が変わらないからです
- 方策 2a は、`Herb.extract_ruby(comments: true)` の出力を使わず、Ruby のコメントを rubocop-erb の側で作った。`comments: true` は複数行のコメントで出力の長さを変えるため（[方策 1 で位置がずれる](#方策-1-で位置がずれる実測出典)）。`<% # … %>` は、中身をそのまま Ruby のコメントにする（`  ;` を補わない）
- 方策 3 のコメントは、ERB のコメントの 1 行につき 1 つ作る。1 行目は `<%#` の `#` から行末まで、2 行目以降は行頭から行末まで。テキストは ERB に書かれた文字列で、2 行目以降は行頭の空白 1 文字を `#` に置き換える（空白がなければ `#` を足す）。1 行目と、行頭に空白のある行は、`DirectiveComment#range` の位置が元の ERB と揃う
- 方策 3 で、複数行のコメント全体を 1 つのコメントとして渡すと、2 つ目以降の無効化コメントと、説明の行の後に書いた無効化コメントは認識されない。`DirectiveComment` は、テキストの中の最初の `# rubocop:` だけを見て、`#` と `rubocop:` の間に空白（改行を含む）しか許さないため【実測】
- 方策 3 では、`CommentConfig` のサブクラスで `each_directive`（private）を上書きし、`processed_source.comments` の後に ERB のコメントを足す。`processed_source.comments` 自体は変えないので、コメントを見る cop には届かない
- 方策 3 では、`CommentConfig#initialize` が `@no_directives`（`raw_source` に `rubocop` を含まなければ解析を飛ばす）を立てるので、元の ERB で判定し直す必要がある。`ERBSource` の `raw_source` は取り出した Ruby で、`<%#` の中身は空白になっているため
- 無効化が 1 行だけに効くか、`rubocop:enable` までの範囲に効くかは、どの方策でも RuboCop の判定（その行に Ruby のトークンがあるか）に任せた。HTML は空白なので、`<%# … %>` と HTML だけの行は「コメントだけの行」になる

## まとめ

- 提案は方策 2（無効化コメントを書いた行だけを、その場で Ruby のコメントにする）を軸にします。Ruby のコメントにできない書き方は、効かないことを cop で報告します。実際のビュー 333 ファイルの offense は 0.8.2 と同じで、試した入力でも、0.8.2 との違いは無効化コメントに関係するものだけでした（[方策 2](#方策-2無効化コメントの行だけを-ruby-にする実測)）
- 方策 2 で Ruby のコメントにできないのは、次の 2 つです。どちらも `Erb/IgnoredCopDirective` が報告します
  - 無効化コメントの行の後ろに、同じ行で Ruby のコードが続くもの（`<%# rubocop:disable … %><% if … %>`）。ERB のコメントは `%>` で終わりますが、Ruby のコメントは行末まで続くので、後ろのコードもコメントに入るためです
  - 複数行のコメントの 2 行目以降で、行頭の空白が 2 文字より少ないもの（`#` を付けて書いた行を除く）。長さを変えずに `# ` を置く場所がないためです
- 方策 1（`Herb.extract_ruby(comments: true)`）は採りません。`<%#` の右側にある Ruby のコードがコメントに入り、正しいテンプレートに `Lint/Syntax` が出たり（`leading_plain_comment.html.erb`）、構文エラーが報告されなくなったりします（`leading_syntax_error.html.erb`）。herb 0.11 の `comments: true` は、`%>` か本文が行頭にある複数行の `<%#` で出力を長くするので、位置がずれて autocorrect がテンプレートを壊します（`multiline_comment_autocorrect.html.erb`。`multiline_column0.html.erb` では無限ループ）。普通の ERB のコメントにも、`Style/CommentAnnotation`、`Layout/EmptyComment`、`Layout/EmptyLineAfterMagicComment` などが新たに出ます
- 参考として、右側に Ruby のコードがない ERB のコメントをまるごと Ruby のコメントにする形（方策 2a）も測りました。方策 1 の構文の問題は避けられますが、普通の ERB のコメントに方策 1 と同じ新しい offense が出ます。方策 2 は、条件を満たす無効化コメントの行だけを Ruby にするので、これが起きません
- 方策 3（取り出す Ruby を変えずに、ERB のコメントを無効化コメントとしてだけ RuboCop に渡す）は採りません。3 つの方策の中でもっとも RuboCop の内部に依存し、扱いが込み入っているためです
  - `CommentConfig` だけに渡すと、`Lint/RedundantCopEnableDirective`、`Lint/CopDirectiveSyntax`、`Style/DirectiveScope` が働かず、cop ごとのパッチが要ります（方策 3'）。パッチの当て方を誤ると、テンプレートを壊したり、ERB のコメントがほかの cop に漏れたりしました
  - `processed_source.comments` に足すと（方策 3''）、ソースの行でコメントを見分ける 23 個の cop と食い違い、`Style/InlineComment` などの誤検知が出ます。CI で RuboCop を通すことを考えると、この誤検知は受け入れられません
  - どちらの形でも、ERB のコメントの行は取り出した Ruby では空白のままなので、rubocop-erb が `.erb` で除外している `Style/WhileUntilModifier` や `Layout/EmptyLineAfterGuardClause` を有効にしたとき、Ruby と違う判断になります。方策 2 では、無効化コメントの行は Ruby のコメントになるので、Ruby と同じ判断になります（[除外されている cop](#除外されている-cop実測)）
- 不要な無効化コメントを autocorrect で消す（`Lint/RedundantCopDisableDirective`）のは、どの方策でも働きません。rubocop-erb の修正範囲の検査が、`<%#` の `#` を含む範囲の修正を捨てるからです

## 無効化が効くか【実測】

1 ファイルずつ実行しました。「効く」は無効にした cop が出ないこと、「効かない」は出ることです。`empty_if.html.erb` は `Lint/EmptyConditionalBody` を `.erb` でも有効にした設定で実行しました。

| ファイル | 0.8.2 | 方策 1 | 方策 2a | 方策 3 |
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
- `leading.html.erb` の方策 2a では、コメントを Ruby にしないので無効化は効かず、効かないことを知らせる offense も出ません
- `leading.html.erb` の方策 3 では、同じ行に `if` のトークンがあるので、無効化はその行だけに効きます
- `html_after_comment.html.erb`（`<%# rubocop:disable … %><p>a</p>`）は、どの方策でも「コメントだけの行」として扱われ、ファイルの終わりまで効きます
- `empty_if.html.erb` の方策 1・2a は、無効化が効いたからではなく、`Lint/EmptyConditionalBody`（既定で `AllowComments: true`）がコメントだけの本文を空と見なさないからです
- `<% # … %>` の方策 1 は、`Herb.extract_ruby(comments: true)` がタグの終わりに `  ;` を補い（`# rubocop:disable Style/StringLiterals  ;`）、`Lint/CopDirectiveSyntax` が出ます。タグの中の行末のコメントと同じ問題です（[rubocop-erb-0.8.md](rubocop-erb-0.8.md#無効化コメントのサポート実測)）。方策 2a は `;` を補わないので出ません
- 変わらないもの: `not_erb_tag.html.erb`（`<# … %>` は ERB のタグではない）は、どの方策でも効きません。`multiline_tag.html.erb`、`multiline_range.html.erb`、タグの中の行末のコメント（`trailing_in_tag.html.erb`、`disable/trailing.html.erb`、`disable/trailing_output_tag.html.erb`）は、0.8.2 と同じ結果です

## 複数行のコメント【実測】

`<%#`⏎`  …`⏎`%>` のように複数行にわたる ERB のコメントは、ERB として正しい書き方です。行頭の空白の有無、無効化コメントの位置、前後のコードを変えて試しました。「効く」「効かない」は前の節と同じ意味です。

| ファイル | 0.8.2 | 方策 1 | 方策 2a | 方策 3 |
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
- `multiline_code_after.html.erb` の方策 2a は、右側にコードがあるので Ruby にしません。`multiline_column0.html.erb` の方策 2a は、行頭に空白のない行（`rubocop:disable …`）に、長さを変えずに `#` を置けないので Ruby にしません。どちらも、効かないことを知らせる offense は出ません
- 方策 2a の `Layout/EmptyComment` は、`<%#` だけの 1 行目が `  #` になるためです。方策 1 は、herb が 1 行目の `#` を行頭に置き、次の行のコメントと続いた 1 つのコメントになるので出ません（`erb-comment/multiline_comment.html.erb` のように `<%#` がインデントされていると、方策 1 でも出ます）

### autocorrect

| ファイル | 0.8.2・方策 2a・方策 3 | 方策 1 |
|---|---|---|
| `multiline_comment_autocorrect.html.erb` | `<%= link_to 'a', url, { remote: true } %>` | `<%= link_to "'a' url, {r emote: true}  %>` |
| `multiline_column0_text.html.erb` | `<%= link_to 'a', url, { remote: true } %>` | コメントの `- item` が `-  item` に、コードが `<%= link_to "a'a'url, {re mote: true} %>` になる |
| `multiline_column0.html.erb` | （方策 3 では無効化が効いて変わらない） | コメントの `rubocop:disable` の `r` の後ろに空白が 200 個以上入り、RuboCop が「Infinite loop detected」で止まる |

- 方策 1 の `Layout/LeadingCommentSpace`（`#` の後ろに空白がない）の修正は、ずれた位置で ERB のコメントの中に空白を足します。【推測】足した空白が `#` と `rubocop:` の間に入らないので、次の回の変換でも同じ offense が出続けると考えます

## 方策ごとの副作用【実測】

| ファイル | 0.8.2 | 方策 1 | 方策 2a | 方策 3 |
|---|---|---|---|---|
| `leading_plain_comment.html.erb`（正しいテンプレート） | offense なし | `Lint/Syntax`（unexpected token end） | offense なし | offense なし |
| `leading_syntax_error.html.erb`（構文エラー） | `Lint/Syntax` | `Lint/Syntax` が出ない。無効化コメントの offense が 3 件出る | `Lint/Syntax` | `Lint/Syntax` |
| `plain_comments.html.erb` | offense なし | `Style/CommentAnnotation`、`Layout/LeadingCommentSpace` | 同左 | offense なし |
| `empty_if_plain_comment.html.erb` | `Lint/EmptyConditionalBody` | `Lint/EmptyConditionalBody` が出ない。`Style/CommentAnnotation`（`note` をキーワードと見なす）が出る | 同左 | `Lint/EmptyConditionalBody` |
| `malformed.html.erb`（cop 名がない） | — | `Lint/CopDirectiveSyntax` | `Lint/CopDirectiveSyntax` | 出ない（方策 3' では出る） |
| `redundant_enable.html.erb` | — | `Lint/RedundantCopEnableDirective` | 同左 | 出ない（方策 3' では出る） |
| `orphan_pop.html.erb` | — | `Lint/RedundantCopEnableDirective`（`pop`） | 同左 | 出ない（方策 3' では出る） |
| `directive_scope.html.erb` | `Style/StringLiterals` | `Style/DirectiveScope` | 同左 | 出ない（方策 3' では出る） |

- 方策 1 では、`<%#` の右側にある Ruby のコードがすべてコメントに入ります。`leading_plain_comment.html.erb` では `if` が消えて `end` だけが残り、`leading_syntax_error.html.erb` では閉じていない `link_to(` が消えます。どちらも無効化コメントがなくても起きます（前者のコメントは「見出し」）
- 方策 1・2a で新たに出る cop は、ERB のコメントをテンプレートのメモとして書く使い方と合いません。`Layout/CommentIndentation` は、rubocop-erb が `.erb` で除外しているので出ません。`<%# TODO fix this %>` は autocorrect で `<%# TODO: fix this %>` に書き換わります
- 方策 3 は、ERB のコメントを `processed_source.comments` に入れないので、コメントを見る cop には何も起きません。その代わり、無効化コメントを検査する cop の一部も働きません（次の節）

### 実際のビュー（333 ファイル）

| | 0.8.2 | 方策 1 | 方策 2a | 方策 3 | 方策 3' |
|---|---|---|---|---|---|
| offense の数 | 763 | 766 | 766 | 763 | 763 |
| 0.8.2 との差 | — | `Layout/EmptyLineAfterMagicComment` 3 件、列のずれ 2 件 | `Layout/EmptyLineAfterMagicComment` 3 件 | なし | なし |

- `Layout/EmptyLineAfterMagicComment` は、rails のテストの `<%# encoding: utf-8 -%>` で始まる 3 ファイルに出ます。コメントになった `# encoding: utf-8` を Ruby のマジックコメントと見なすためです
- 列のずれは、conference-app の `admin/kaminari/_page.html.erb`（1〜9 行目が複数行の `<%#`）の 11 行目です。`Layout/SpaceInsideHashLiteralBraces` 2 件の列が、方策 1 だけ 1 つ右にずれます（次の節）

## 方策 3 で働かない cop【実測・出典】

RuboCop 1.92.0 で、無効化コメントを扱う cop が無効化コメントをどこから探すかを調べました【出典】。

| cop | 探す場所 | 方策 3 での結果 |
|---|---|---|
| `Lint/RedundantCopDisableDirective` | `CommentConfig`（無効にした範囲） | 働く |
| `Lint/MissingCopEnableDirective` | `CommentConfig` | 働く |
| `Lint/RedundantCopEnableDirective` | `processed_source.raw_source` に `enable` か `pop` を含むときだけ調べる。`enable` は `CommentConfig#extra_enabled_comments`、`pop` は `processed_source.comments` から探す | 働かない |
| `Lint/CopDirectiveSyntax` | `processed_source.comments` | 働かない |
| `Style/DirectiveScope` | `processed_source.comments`（と `CommentConfig`） | 働かない |
| `Style/DisableCopsWithinSourceCodeDirective`（既定で無効） | `processed_source.comments` | 試していない |

- `ERBSource` の `raw_source` は取り出した Ruby で、`<%#` の中身は空白になっています。`Lint/RedundantCopEnableDirective` は `enable` の判定自体は `CommentConfig` で行うので、方策 3 の `CommentConfig` で ERB のコメントが届いていても、手前の文字列の確認で止まります。`CommentConfig#initialize` の `@no_directives` と同じ形の確認です
- `processed_source.comments` に ERB のコメントを足すと、この 3 つの cop には届きますが、コメントを見るほかの cop（`Style/CommentAnnotation` など）にも届き、方策 1・2a と同じ副作用が出ます【推測】

### cop へのパッチ（方策 3'）

試作では、3 つの cop の `on_new_investigation` の間だけ、`ERBSource#comments` が ERB のコメントを足して返し、`ERBSource#raw_source` が元の ERB を返すようにしました。

- `redundant_enable.html.erb`、`orphan_pop.html.erb`、`malformed.html.erb`、`directive_scope.html.erb` に、方策 1 と同じ offense（[方策ごとの副作用](#方策ごとの副作用実測)の表の cop）が出ます。`empty_if_with_directive.html.erb` にも `Style/DirectiveScope` が出ます【実測】
- そのほかの入力の offense と、`-A` の結果は、方策 3 と同じです。実際のビュー 333 ファイルでも 0.8.2 と同じ 763 件です【実測】
- 3 つの cop の autocorrect は、どれも `<%#` の `#` を含む範囲を書き換えるので、rubocop-erb の修正範囲の検査で捨てられ、`[Correctable]` も付きません【実測】
- `processed_source` を別のオブジェクト（`SimpleDelegator` で `comments` と `raw_source` だけを変えたもの）に差し替える形にすると、autocorrect がテンプレートを壊しました。`orphan_pop.html.erb` の `<%# rubocop:pop %>` と、`redundant_enable.html.erb` の `<%# rubocop:enable … %>` が、`-A` でどちらも `<%` になります。rubocop-erb の `Corrector` は、`processed_source.is_a?(ERBSource)` のときだけ修正範囲を検査するので、差し替えたオブジェクトでは検査が外れるためです【実測・出典: `lib/rubocop/erb/corrector.rb`】
- rubocop-ast の `ProcessedSource` は、`comments` から作った値（`comment_index` と `ast_with_comments`）を最初に使われたときに覚えます。パッチの cop の調査中に作られた値をそのまま残すと、後の cop にも ERB のコメントが見えます。`empty_if_with_directive.html.erb` では、`Style/DirectiveScope` の調査中に `comment_index` が作られ、後の `Lint/EmptyConditionalBody` がコメントを本文と見なして `if` を報告しなくなりました。試作では、調査の前にこの 2 つを消して作り直させ、調査の後に元の値に戻しています。戻すと `Lint/EmptyConditionalBody` は方策 3 と同じく出ます【実測・出典】
- パッチの cop の調査中は `processed_source.comments` が ERB のコメントを含むので、そのとき `CommentConfig` が呼ばれると、同じ ERB のコメントを 2 回数えます。試作の `CommentConfig` は、`processed_source.comments` を読む間だけ ERB のコメントを外しています【出典】
- 【推測】パッチは cop ごとに、その cop が無効化コメントを探す場所に合わせて当てる必要があり、RuboCop の cop の実装が変わると効かなくなります。無効化コメントを扱う cop が増えたときも、個別に追う必要があります

## processed_source.comments に足す場合【実測・出典】

方策 3 のコメントを `CommentConfig` だけでなく `ERBSource#comments` にも足し、すべての cop に見せる形（方策 3''、`comments_all`）を試しました。`CommentConfig` は `processed_source.comments` から無効化コメントを読むので、`@no_directives` を元の ERB で判定し直すだけで無効化が効きます。

### ソースの行でコメントを見分ける cop

RuboCop 1.92.0 には、コメントの行かどうかを `processed_source.lines` などソースの行の文字列で判定する cop が 23 個あります【出典】。21 個が `RuboCop::Cop::Util#comment_line?`（`/^\s*#/`）を使い、`Layout/ClassStructure` と `Layout/CommentIndentation` は自前の `/\A\s*#/` を使います。

| 使い方 | cop |
|---|---|
| `CodeLength`（`CountComments: false` のときコメントの行を数えない） | `Metrics/BlockLength`、`Metrics/ClassLength`、`Metrics/MethodLength`、`Metrics/ModuleLength` |
| `EmptyLinesAroundBody`（コメントの行を飛ばして前の行を探す） | `Layout/EmptyLinesAroundBeginBody`、`Layout/EmptyLinesAroundBlockBody`、`Layout/EmptyLinesAroundClassBody`、`Layout/EmptyLinesAroundExceptionHandlingKeywords`、`Layout/EmptyLinesAroundMethodBody`、`Layout/EmptyLinesAroundModuleBody` |
| `DocumentationComment`（直前のコメントがコメントの行か） | `Style/Documentation`、`Style/DocumentationMethod` |
| コメントが行末のものか、独立した行のものか | `Style/InlineComment`、`Style/CommentAnnotation`、`Layout/CommentIndentation` |
| 範囲の中にコメントの行があるか | `Lint/SuppressedException`（`AllowComments`）、`Lint/EmptyFile` |
| 直前の行がコメントか | `Layout/EmptyLinesAroundAccessModifier`、`Style/AccessorGrouping`、`Layout/ClassStructure`、`Layout/FirstArgumentIndentation` |
| その他 | `Bundler/GemComment`、`InternalAffairs/CopDescription` |

- `ERBSource` の行は取り出した Ruby の行で、ERB のコメントは空白です。`processed_source.comments` にはコメントがあるのに、その行は `#` で始まらないので、コメントの位置と行の文字列から判断する cop が食い違います
- rubocop-erb 0.8.2 が `.erb` で除外しているのは、このうち `Layout/EmptyLinesAroundBlockBody`、`Layout/FirstArgumentIndentation`、`Lint/EmptyFile`、`Layout/CommentIndentation` だけです

### 結果【実測】

| ファイル | 方策 1（Ruby のコメント） | 方策 3・3' | 方策 3'' |
|---|---|---|---|
| `inline_comment.html.erb`（`Style/InlineComment` を有効） | 出ない | 出ない | 独立した行の `<%# heading %>` に `Style/InlineComment` が出る |
| `consecutive_annotations.html.erb` | `Style/CommentAnnotation` が 1 つ目のコメント（2 行目）だけ | 出ない | `Style/CommentAnnotation` が 2 つとも（2 行目と 3 行目） |
| `suppressed_exception.html.erb` | 出ない（コメントを本文と見なす） | `Lint/SuppressedException` | `Lint/SuppressedException` |

- `Style/InlineComment` と `Style/CommentAnnotation` は、コメントのある行が `#` で始まらないので、どの ERB のコメントも行末のコメントと見なします。`Style/CommentAnnotation` は、続いたコメントの 2 行目以降を本来は調べませんが、行末のコメントは 1 つずつ調べるので、2 行とも報告します
- `Lint/SuppressedException` の `AllowComments` は、`rescue` から `end` までにコメントの行があるかを行の文字列で調べます。方策 3・3'・3'' と 0.8.2 では、ERB のコメントは空白の行なので、コメントだけの `rescue` を報告します
- そのほか、方策 3'' では、方策 1・2a と同じく `Style/CommentAnnotation`、`Layout/LeadingCommentSpace`、`Layout/EmptyComment`、`Layout/EmptyLineAfterMagicComment` が新たに出て、`Lint/EmptyConditionalBody` がコメントだけの `if` を報告しなくなります。実際のビューは 766 件（`Layout/EmptyLineAfterMagicComment` 3 件）です。`Layout/EmptyComment` は、複数行の `<%#` の `<%#` だけの 1 行目（`#` になる）に出ます
- `Lint/RedundantCopEnableDirective` は、方策 3'' でも `raw_source` の確認で止まり、`redundant_enable.html.erb` と `orphan_pop.html.erb` に何も出ません。`Lint/CopDirectiveSyntax` と `Style/DirectiveScope` は働きます
- 方策 3・3' は、ERB のコメントを `CommentConfig`（と、3' ではパッチを当てた 3 つの cop の調査中）にしか見せないので、この食い違いは起きません。パッチを当てた 3 つの cop は、ソースの行の文字列を使いません（`Style/DirectiveScope` は修正の範囲を行単位で作りますが、その修正は rubocop-erb が捨てます）【出典】

### 除外されている cop【実測】

rubocop-erb 0.8.2 は、`Layout/EmptyLineAfterGuardClause`、`Style/WhileUntilModifier`、`Style/IfUnlessModifier` を `.erb` で除外しています【出典】。これらもコメントの有無で判断を変える cop です。除外を外して（`config_excluded_cops.yml`）、`excluded_*.html.erb` にかけました。方策 1（ERB のコメントを Ruby のコメントにする）の結果が、Ruby として書いたときの結果です。

| ファイル | 方策 1・2a | 0.8.2・方策 3・3' | 方策 3'' |
|---|---|---|---|
| `excluded_while_first_line.html.erb`（`<% while … %><%# … %>`） | 出ない | `Style/WhileUntilModifier` | 出ない |
| `excluded_while_last_line.html.erb`（`<% end %><%# … %>`） | 出ない | `Style/WhileUntilModifier` | 出ない |
| `excluded_while_body_line.html.erb`（本文に `<%# … %>` だけの行） | 出ない | `Style/WhileUntilModifier` | `Style/WhileUntilModifier` |
| `excluded_guard_note.html.erb`（ガード節の次の行に `<%# … %>`） | `Layout/EmptyLineAfterGuardClause` | 出ない | 出ない |
| `excluded_guard_enable.html.erb`（ガード節の次の行に `<%# rubocop:enable … %>`、その次にコード） | `Layout/EmptyLineAfterGuardClause` | 出ない | 出ない |
| `excluded_suppressed_directive.html.erb`（`rescue` の本文が `<%# rubocop:disable Lint/SuppressedException %>` だけ） | 出ない | `Lint/SuppressedException` | `Lint/SuppressedException` |

- 0.8.2 と方策 3・3' の結果は、どの入力でも同じです。ERB のコメントの行は、取り出した Ruby では空白の行なので、無効化コメントがあってもなくても、Ruby とは違う判断になります
- `Style/WhileUntilModifier` は、1 行目と最後の行のコメントを `comment_at_line` などで調べます（`processed_source.comments` から探す）。本文の行数は、空白でない行を数えます（ソースの行）。方策 3'' は前者だけ Ruby と同じになり、本文の行は 0.8.2 と同じく数えません
- `Layout/EmptyLineAfterGuardClause` は、ガード節の次の行が空白か（ソースの行）を先に調べます。ERB のコメントの行は空白なので、方策 3・3'・3'' のどれでも、空行があるものとして扱います
- `excluded_suppressed_directive.html.erb` では、`Lint/SuppressedException` は `rescue` の行（3 行目）に出ますが、無効化コメントは 4 行目から効くので、この offense を抑えられません。Ruby では、コメントがあるので `AllowComments` によって出ません
- 【推測】rubocop-erb が除外している cop を有効に戻すには、ERB のコメントの行が、ソースの行としても `processed_source.comments` としてもコメントに見える必要があります。そうできるのは、コメントを Ruby のコメントにする方策 1・2・2a だけです。方策 2 は無効化コメントの行だけを Ruby にするので、無効化コメントでない ERB のコメントは 0.8.2 と同じ判断のままです

## 方策 2：無効化コメントの行だけを Ruby にする【実測】

試作（`render_directives`）の仕組みです【出典】。

- 対象は `<%# … %>` と、`#` で始まる 1 行のタグ `<% # … %>`。ERB のコメントを行ごとに見て、`#`、空白、`rubocop:` の順で始まる行だけを Ruby のコメントにする。1 行目は `<%#` の `#` から見る。2 行目以降は、行頭の空白を除いた文字列が `#` で始まればそのまま、そうでなければ前に `# ` を補って見る
- 1 行目は `<%#` の `#` をそのまま使う。2 行目以降は、行頭の空白 1 文字を `#` に置き換える（`  rubocop:disable …` は `# rubocop:disable …` になる）。空白の後が `#` で始まる行（`  # rubocop:disable …`）は、そのままで Ruby のコメントなので、字下げのタブを空白にする（`Layout/IndentationStyle` を出さないため）ほかは書き換えない。`%>` は含めない。長さと行の数を変えないので、位置はずれない
- 無効化コメントでない行と、無効化コメントを含まない ERB のコメントは、0.8.2 と同じく空白のまま
- 次の行は Ruby のコメントにせず、`Erb/IgnoredCopDirective` が報告する
  - 無効化コメントの行が ERB のコメントの最後の行で、`%>` の後ろに同じ行で Ruby のコードが続くもの
  - 2 行目以降で、空白の後が `#` で始まらず、行頭の空白が 2 文字より少ないもの。`#` の後ろに空白を置けず、`#rubocop:` になると `Layout/LeadingCommentSpace` の autocorrect が ERB のコメントを書き換えるため
  - `#rubocop:` のように、`#` の後に空白がないもの。Ruby では無効化として効く書き方ですが、`Layout/LeadingCommentSpace` の autocorrect が ERB のコメントを書き換えるので、同じ理由で Ruby にしない

### 結果

| 入力 | 0.8.2 | 方策 2 |
|---|---|---|
| 行末、独立した行、`disable-next`、`<% # … %>`、マルチバイト文字のある行 | 効かない | 効く |
| 複数行のコメント（`multiline_directive`、`multiline_second_line`、`multiline_two_directives`、`multiline_code_before`、`erb-comment/multiline_comment`） | 効かない | 効く。`Layout/EmptyComment` は出ない |
| `multiline_code_after.html.erb`（`%><%= "a" %>`。無効化は 2 行目） | 効かない | 効く |
| `erb-comment/leading.html.erb`（`<%# rubocop:disable … %><% if 'hello' %>`） | 効かない | 効かない。`Erb/IgnoredCopDirective` が出る |
| `multiline_column0.html.erb`（行頭の `rubocop:disable …`）、`multiline_one_space.html.erb`（空白 1 文字）、`multiline_tab.html.erb`（タブ 1 文字） | 効かない | 効かない。`Erb/IgnoredCopDirective` が出る |
| `multiline_hash.html.erb`（`  # rubocop:disable …`）、`multiline_column0_hash.html.erb`（行頭の `# rubocop:disable …`）、`multiline_tab_hash.html.erb`（タブの後の `# rubocop:disable …`） | 効かない | 効く |
| `no_space.html.erb`、`multiline_no_space.html.erb`（`#rubocop:disable …`） | 効かない | 効かない。`Erb/IgnoredCopDirective` が出る |
| `redundant_enable`、`orphan_pop`、`malformed`、`directive_scope` | 出ない | `Lint/RedundantCopEnableDirective`、`Lint/CopDirectiveSyntax`、`Style/DirectiveScope` が出る |
| 普通の ERB のコメント（`plain_comments`、`consecutive_annotations`、`inline_comment`、`empty_if_plain_comment`、`suppressed_exception`、`leading_plain_comment`） | — | 0.8.2 と同じ |

- 実際のビュー 333 ファイルでは、0.8.2 と同じ 763 件でした。`<%# encoding: utf-8 -%>` は無効化コメントではないので、`Layout/EmptyLineAfterMagicComment` は出ません
- `-A` の結果は、無効化が効いて offense が出なくなった箇所を除いて、0.8.2 と同じでした。ERB のコメントが書き換わることはありません
- rubocop-erb が除外している cop を有効にすると（`excluded_*.html.erb`）、無効化コメントの行は Ruby と同じ判断になります。`excluded_guard_enable.html.erb` には、Ruby と同じく `Layout/EmptyLineAfterGuardClause` が出ます。`excluded_suppressed_directive.html.erb` には `Lint/SuppressedException` が出ず、代わりに `Lint/RedundantCopDisableDirective` と `Lint/MissingCopEnableDirective` が出ます（方策 1・2a と同じ）。無効化コメントでない ERB のコメントは空白のままなので、`excluded_while_*.html.erb` と `excluded_guard_note.html.erb` は 0.8.2 と同じです
- 複数行のコメントをどこまで扱うかは、決める必要があります。試作は行ごとに見て、条件を満たす無効化コメントの行を Ruby にしています。複数行のコメントは扱わず、1 行の `<%# rubocop:… %>` だけを対象にする（複数行のコメントの中の無効化は `Erb/IgnoredCopDirective` で報告する）という線の引き方もあります【推測】
- `erb-comment/empty_if.html.erb`（本文が空の `if` の行末の `<%# rubocop:disable Lint/EmptyConditionalBody %>`）では、`Lint/EmptyConditionalBody` は出ませんが、無効化が効いたからではありません。この cop の `AllowComments: true` が、無効化コメントを本文と見なすためです。`Lint/RedundantCopDisableDirective` も出ません

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
- ずれた位置で autocorrect をかけると、テンプレートが壊れる。`multiline_comment_autocorrect.html.erb` の `<%= link_to "a", url, {remote: true} %>` は、方策 1 の `-A` で `<%= link_to "'a' url, {r emote: true}  %>` になる。0.8.2 と方策 2a・3 では `<%= link_to 'a', url, { remote: true } %>` になる
- 【推測】行頭に空白のない行を、長さと行の数を変えずに Ruby のコメントにする方法はない。`#` を置く場所がなく、`=begin`/`=end` も行頭に独立した行が要るため。方策 1・2a のようにコメントを Ruby にする方策は、この行を位置をずらして Ruby にするか、Ruby にしない（無効化が効かない）かを選ぶことになる

## autocorrect と無効化コメント【実測・出典】

- `redundant.html.erb` の `Lint/RedundantCopDisableDirective` は、3 つの方策のどれでも `[Correctable]` として報告されず、`-A` でもファイルは変わらない
- rubocop-erb の `Corrector` は、修正の範囲が 1 つの ERB タグの Ruby の部分（`<%#` と `%>` の間）に収まらなければ修正を捨てる【出典: `lib/rubocop/erb/corrector.rb`】。無効化コメントの範囲は `#` から始まり、`#` は `<%#` の一部なので、どの方策でも修正が捨てられる
- 【推測】仮にこの検査を通しても、RuboCop が消すのは Ruby のコメントとしての範囲なので、`<%` や `%>` が残るおそれがある。不要な無効化コメントを消すには、タグ全体を消す扱いが別に要る
- 方策 3 で無効化コメント以外の cop の autocorrect が変わることはない。取り出す Ruby も、`processed_source.comments` も変えないため
- 方策 3' で働くようになる `Lint/RedundantCopEnableDirective` の autocorrect も、同じ理由で捨てられる（[cop へのパッチ](#cop-へのパッチ方策-3)）

## 考察【推測】

- 方策 2 は、無効化コメントを Ruby のコメントとして RuboCop に見せるので、無効化コメントを扱う cop（`Lint/RedundantCopEnableDirective` など）にも、コメントの有無で判断を変える cop にも、パッチが要りません。rubocop-erb の側で要るのは、`Herb.extract_ruby` の出力の上に `#` と行の中身を書き戻す処理だけです
- 一方で、Ruby のコメントにできない書き方が残ります。`<%# rubocop:disable … %>` の後ろに同じ行でコードを書く形は、Ruby のコメントの意味（行末まで）とぶつかるので、コメントにはできません。ユーザーには `Erb/IgnoredCopDirective` で知らせ、無効化コメントを独立した行か、コードの行の末尾に書くよう促すのがよいと考えます。herb-lint の `herb:disable` もコードの後ろに書く形なので、書き方の習慣とも合います
- 字下げの足りない複数行のコメントの行（行頭の空白が 2 文字より少ない `rubocop:disable …`）も、`Erb/IgnoredCopDirective` で知らせます。2 文字以上字下げするか、`# rubocop:disable …` と `#` を付けて書けば効きます
- 複数行のコメントを対象にするかは、方針として決める必要があります。対象にすれば、説明の後に無効化を書けるなど書き方の自由は増えますが、条件（字下げ、`#` の有無、最後の行の後ろのコード）が増えます。1 行の `<%# rubocop:… %>` だけを対象にすれば条件は「同じ行の後ろに Ruby のコードがないこと」だけになり、ユーザーへの説明も簡単です
- 無効化コメントだけを本文に持つ `if` などは、`Lint/EmptyConditionalBody` の `AllowComments` で空と見なされません。Ruby で `# rubocop:disable` だけを本文に書いたときと同じ扱いですが、無効化コメントが offense を消すことになります。ERB に限った問題ではないので、提案では触れる程度にします
- rubocop-erb は今のところ独自の cop を持たないので、`Erb/IgnoredCopDirective` を足すなら、部署の名前（`Erb`）と既定の設定も決める必要があります

## 提案に含める点

rubocop-erb への issue の下書きは [rubocop-erb-issues/erb-comment-directive.md](rubocop-erb-issues/erb-comment-directive.md)（日本語版は [erb-comment-directive.ja.md](rubocop-erb-issues/erb-comment-directive.ja.md)）です。issue は実装を示すものではなく、対応の是非と実装方針をメンテナーに問うものにする。

- 問うこと: ERB のコメントに書いた無効化コメントのサポートを rubocop-erb で受け入れるか。受け入れるなら、方策 2 の方向でよいか
- 方策 1（`comments: true`）を既定にできない理由として、ERB の意味が壊れること（`leading_plain_comment.html.erb`、`leading_syntax_error.html.erb`）、位置がずれて autocorrect がテンプレートを壊すこと（`multiline_comment_autocorrect.html.erb`、`multiline_column0.html.erb`）、普通の ERB のコメントに新しい offense が出て CI が通らなくなることを示す
- 方策 2 は、条件を満たす無効化コメントだけを Ruby のコメントにする方向として示す。普通の ERB のコメントは変えないこと、無効化コメントを扱う cop が RuboCop を変えずに働くこと、実際のビュー 333 ファイルで 0.8.2 と同じ結果になることを添える
- 判断を仰ぐ点として、複数行のコメントを対象にするか（1 行の `<%# rubocop:… %>` だけにするか、行ごとに見るか）と、効かない無効化コメントをどう知らせるか（cop、警告、文書のみ）を挙げる。issue は短くまとめ、細かい点（HTML だけの行に書いた無効化コメントの範囲など）は議論の中で扱う
- 方策 2a と方策 3 は issue では示さない
- herb には別に、`Herb.extract_ruby(comments: true)` が、`%>` か本文が行頭にある複数行の `<%#` で位置を保たないことを報告できる
