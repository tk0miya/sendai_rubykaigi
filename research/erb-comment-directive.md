# `<%#` に書いた rubocop:disable と herb-format の整形

調査日: 2026-10-31

ERB のコメント `<%# rubocop:disable … %>` を、ほかの ERB タグと同じ行やブロックの中に書いたときに、各 linter で無効化が効くかを調べました。あわせて、herb-lint と herb-format がこのコメントの行をどうインデントするか、整形した後も無効化が同じ範囲に効くかを調べました。比較のため、herb-lint の無効化コメント `<%# herb:disable … %>` を herb-format がどう扱うかも調べました。
【実測】は手元で実行して確かめたこと（再現手順は [repro/README.md](repro/README.md#erb-コメントの無効化コメント)）、【出典】はドキュメントで確かめたこと、【推測】は解釈です。

## 対象

- erb_lint 0.9.0（README の推奨設定。rubocop 1.91.0）
- rubocop-erb 0.7.2 / 0.8.2（rubocop 1.92.0、herb 0.11.0）
- marcoroth/herb#2260 の rubocop-herb（`d0323df`。以下「herb#2260」）
- ruumba 0.1.17（README の推奨設定）
- tk0miya/rubocop-herb `96d31cf8dff39109dbe4506b808e19693a92b2e2`（以下「rubocop-herb」。`Herb/Linting` は無効）
- @herb-tools/linter 0.11.0（herb-lint）/ @herb-tools/formatter 0.11.0（herb-format）
- 入力は [repro/erb-comment/](repro/erb-comment/) の 9 ファイル。`empty_if.html.erb` 以外は、`Lint/LiteralAsCondition` を無効にするコメントと、その対象になる `<% if 'hello' %>` を含む。`herb:disable` の入力は [repro/erb-comment/herb-disable/](repro/erb-comment/herb-disable/) の 4 ファイル（[herb:disable と herb-format](#herbdisable-と-herb-format実測出典)）

| ファイル | 内容 |
|---|---|
| `trailing.html.erb` | `<% if 'hello' %>world<% end %><%# rubocop:disable … %>` |
| `leading.html.erb` | `<%# rubocop:disable … %><% if 'hello' %>world<% end %>` |
| `after_if.html.erb` | `<% if 'hello' %><%# rubocop:disable … %>` の後に本文と `<% end %>` |
| `not_erb_tag.html.erb` | `<% if 'hello' %>world<% end %><# rubocop:disable … %>`（`%` のない `<#`） |
| `indent.html.erb` | 独立した行の `<%# rubocop:disable … %>` と `<%# rubocop:enable … %>`。インデントが入れ子の深さと合っていない |
| `multiline_comment.html.erb` | `<%#`⏎`  rubocop:disable …`⏎`%>` の後に `<% if 'hello' %>` |
| `multiline_tag.html.erb` | `<%`⏎`  # rubocop:disable …`⏎`%>` の後に `<% if 'hello' %>` |
| `trailing_in_tag.html.erb` | `<% if 'hello' # rubocop:disable … %>` の後に本文と `<% end %>`（`<%#` ではなく、タグの中の行末の Ruby のコメント） |
| `empty_if.html.erb` | `<% if some_error %><%# rubocop:disable Lint/EmptyConditionalBody %>`⏎`<% end %>`（本文が空の `if`） |

## まとめ

- `<%#` の右側に何もない行（`trailing.html.erb`、`after_if.html.erb`）で無効化が効くのは、rubocop-herb と ruumba だけです。rubocop-erb 0.8.2 と herb#2260 では、`<%#` をどこに書いても効きません
- `<%#` の右側にタグや HTML がある行（`leading.html.erb`）では、rubocop-herb は無効化を無視して `Herb/IgnoredCopDirective` を出します。ruumba では後ろの `<% if %>` がコメントに入り、検査されなくなります
- erb_lint と rubocop-erb 0.7.2 は、タグを 1 つずつ検査するので、`<% if 'hello' %>` を構文エラーとして飛ばします。この入力では、無効化が効くかを確かめられません
- herb-lint には、ERB コメントの行のインデント（入れ子の深さ）を検査するルールがありません。`--fix` をかけても変わりません
- herb-format は、同じ行に並んだタグを別々の行に分け、`<%#` を入れ子の深さに合わせてインデントします。`<%#` が独立した行になるか、前後どちらのタグの行に残るかはファイルによって違い、行単位で効いていた無効化の範囲が変わります。rubocop-herb では、`trailing.html.erb` と `after_if.html.erb` の無効化が整形の後に効かなくなります
- herb-format は、複数行のタグ `<%`⏎`  # rubocop:disable …`⏎`%>` を `<% # rubocop:disable … %>` の 1 行にまとめます。これは rubocop-erb 0.8.2 で範囲を指定して無効にできる書き方ですが（[rubocop-erb-0.8.md](rubocop-erb-0.8.md#無効化コメントのサポート実測)）、整形の後は効かなくなります。herb-lint はまとめた行に `erb-comment-syntax` を出し、`--fix` で `<%#` に直しますが、0.8.2 ではそれも効きません。タグの中の行末のコメント（`trailing_in_tag.html.erb`）は、herb-format が書き換えないので、整形の後も 0.8.2 で効きます（`Lint/CopDirectiveSyntax` は出ます）
- 本文が空の `if` の行末に書いた `<%#`（`empty_if.html.erb`）は、herb-format で `if` の本文に移ります。rubocop-herb では、コメントだけの本文は空と見なされないので `Lint/EmptyConditionalBody` は出ないままですが、無効化はファイルの終わりまで効くようになります。offense が消えたまま無効化の範囲だけが広がるので、整形で意味が変わったことに気づきにくくなります
- herb-format は `<%# herb:disable … %>` を特別に扱い、整形の後も行末に書き戻します。`rubocop:disable` にはこの扱いがありません。ただし、書き戻す行はアンカーにしたノードのテキストで出力を検索して決めるので、`if` の中に書いたときや、同じ内容のタグが前にあるときは別の行に付きます

## `<%#` の無効化が効くか【実測】

1 ファイルずつ実行しました。「効く」は無効にした cop（`Lint/LiteralAsCondition` か `Lint/EmptyConditionalBody`）が出ないこと、「効かない」は出ることです。

| ファイル | erb_lint | rubocop-erb 0.7.2 | rubocop-erb 0.8.2 / herb#2260 | ruumba | rubocop-herb |
|---|---|---|---|---|---|
| `trailing.html.erb` | 確かめられない | 確かめられない | 効かない | 効く | 効く |
| `leading.html.erb` | 確かめられない | 確かめられない | 効かない | `if` が検査されない | 効かない。`Herb/IgnoredCopDirective` が出る |
| `after_if.html.erb` | 確かめられない | 確かめられない | 効かない | 効く | 効く |
| `not_erb_tag.html.erb` | 確かめられない | 確かめられない | 効かない | 効かない | 効かない |
| `indent.html.erb` | 確かめられない | 確かめられない | 効かない | 効く | 効く |
| `multiline_comment.html.erb` | 確かめられない | 確かめられない | 効かない | 効く | 効く |
| `multiline_tag.html.erb` | 確かめられない | 確かめられない | 効く | 効く | 効く |
| `trailing_in_tag.html.erb` | 確かめられない | 確かめられない | 効くが、`Lint/CopDirectiveSyntax` が出る | 効く | 効く |
| `empty_if.html.erb` | 確かめられない | 確かめられない | 確かめられない（`.erb` では `Lint/EmptyConditionalBody` を除外） | 出ない | 効く |

- erb_lint と rubocop-erb 0.7.2 は、`<% if 'hello' %>` と `<% end %>` を 1 つずつ Ruby として検査するので、どちらも構文エラーとして黙って飛ばします。0.7.2 では、`multiline_tag.html.erb` に `Lint/MissingCopEnableDirective` と `Lint/RedundantCopDisableDirective` が、`trailing_in_tag.html.erb` に `Lint/RedundantCopDisableDirective` が出ます。erb_lint では、`multiline_tag.html.erb` に `Layout/CommentIndentation` と `Layout/LeadingEmptyLines` が出ます（誤検知）。ほかのファイルでは offense 0 件です
- herb#2260 の結果は 0.8.2 と同じです。ほかに `Layout/ExtraSpacing` が出ます。`empty_if.html.erb` では、無効化コメントを消しても `Lint/EmptyConditionalBody` は出ません
- ruumba の `empty_if.html.erb` は、コメントが `if` と同じ行の Ruby のコメントになり、`Lint/EmptyConditionalBody` は出ません
- ruumba は `<%# … %>` を `# …` という Ruby のコメントにします。`leading.html.erb` は `# rubocop:disable Lint/LiteralAsCondition ;     if 'hello' ;          end` という 1 行のコメントになり、`if` が消えます。代わりに `Lint/CopDirectiveSyntax`、`Lint/MissingCopEnableDirective`、`Lint/RedundantCopDisableDirective` が出ます。ほかのファイルでも `Layout/CommentIndentation` などの誤検知が出ます
- rubocop-herb は、右側に何もない `<%#` を Ruby のコメントにします。コードと同じ行にあれば、その行だけに効きます（`trailing.html.erb`、`after_if.html.erb`）。独立した行にあれば、`rubocop:enable` までの範囲に効きます（`indent.html.erb`、`multiline_comment.html.erb`）
- rubocop-herb は、`multiline_comment.html.erb` の `<%#` だけの行に `Layout/EmptyComment` を出します（誤検知）
- `not_erb_tag.html.erb` の `<# … %>` は ERB のタグではなく、HTML のテキストとしてそのまま出力されます。herb-lint は `%>` に `STRAY_ERB_CLOSING_TAG_ERROR`（`parser-no-errors`）を出します。ほかのファイルには、herb-lint の offense は出ません
- herb-lint は、本文が空の `if` に `erb-no-empty-control-flow` を出します（hint）。ただし `<%#` も本文として数えるので、`empty_if.html.erb` には出ません。中身が無効化のコメントだけでも、herb-lint にとっては空ではない `if` です

## herb-lint とインデント【出典・実測】

herb-lint 0.11.0 のルールのうち、インデントに関わるものは次の 2 つです【出典: `@herb-tools/linter` の `docs/rules/`】。

- `source-indentation`: インデントの文字が設定（`formatter.indentStyle`、既定は空白）と合っているかだけを見る。入れ子の深さは見ない
- `erb-closing-tag-indent`: 複数行のタグの `%>` の位置を見る。ERB コメントと、Ruby のコメントを含むタグは対象外

インデントがずれた `indent.html.erb` に、herb-lint の offense は出ません。`--fix` をかけても、ファイルは変わりません【実測】。

インデントを直すのは herb-format です。0.11.0 の herb-format は experimental preview で、`.herb.yml` で `formatter.enabled: true` にするか、`--force` を付けないと動きません【出典: `@herb-tools/formatter` の README】。

### herb-format の整形【実測】

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

- 独立した行の `<%#` は、ほかのタグと同じく入れ子の深さに合わせてインデントされる（`indent.html.erb`）
- 同じ行に並んだタグは、別々の行に分けられる。コメントの置き場所は、前後どちらのタグと同じ行に残るかで変わる
  - `trailing.html.erb`: `<% if 'hello' %>`⏎`  world`⏎`<% end %><%# rubocop:disable … %>`。コメントは `<% end %>` の行に残る
  - `leading.html.erb`: `<%# rubocop:disable … %>`⏎`<% if 'hello' %>`⏎`  world`⏎`<% end %>`。コメントは独立した行になる
  - `after_if.html.erb`: `<% if 'hello' %>`⏎`    <%# rubocop:disable … %>`。コメントは次の行に移り、`if` の本文としてインデントされる
- 複数行のコメントやタグは 1 行にまとめられ、その後に空行が入る
  - `multiline_comment.html.erb`: `<%# rubocop:disable … %>`
  - `multiline_tag.html.erb`: `<% # rubocop:disable … %>`。herb-lint が `erb-comment-syntax` を出し、`--fix` で `<%# rubocop:disable … %>` に直す
- `world` を独立した行にするので、出力される空白が変わる（`world` が `\n  world\n` になる）
  - `empty_if.html.erb`: `<% if some_error %>`⏎`  <%# rubocop:disable … %>`⏎`<% end %>`。コメントは次の行に移り、`if` の本文としてインデントされる
- タグの中の行末のコメント（`trailing_in_tag.html.erb`）は書き換えない
- `not_erb_tag.html.erb` はパースエラーがあるので、書き換えずに飛ばす

### 整形すると無効化の範囲が変わる【実測】

herb-format で整形したファイル（`multiline_tag.html.erb` は、さらに herb-lint の `--fix` をかけたものも）を、rubocop-erb 0.8.2 と rubocop-herb にかけ直しました。

| ファイル | rubocop-erb 0.8.2（整形前 → 整形後） | rubocop-herb（整形前 → 整形後） |
|---|---|---|
| `trailing.html.erb` | 効かない → 効かない | 効く → **効かない**。コメントが `<% end %>` の行に移り、その行だけに効く。`Lint/RedundantCopDisableDirective` も出る |
| `after_if.html.erb` | 効かない → 効かない | 効く → **効かない**。コメントが本文の行に移り、そこからの範囲に効く。`Lint/MissingCopEnableDirective` と `Lint/RedundantCopDisableDirective` も出る |
| `leading.html.erb` | 効かない → 効かない | 効かない → 効く。独立した行になり、ファイルの終わりまで効く（`Lint/MissingCopEnableDirective`） |
| `indent.html.erb` | 効かない → 効かない | 効く → 効く |
| `multiline_comment.html.erb` | 効かない → 効かない | 効く → 効く。`Layout/EmptyComment` は出なくなる |
| `multiline_tag.html.erb` | 効く → **効かない**（`--fix` で `<%#` にしても効かない） | 効く → 効く |
| `trailing_in_tag.html.erb` | 効く → 効く（整形で変わらない。`Lint/CopDirectiveSyntax` は出る） | 効く → 効く |
| `empty_if.html.erb` | 確かめられない | 効く → 出ない。ただし無効化が効いたからではない（下を参照） |

`empty_if.html.erb` の rubocop-herb は、整形の後も `Lint/EmptyConditionalBody` を出しません。この cop は既定で `AllowComments: true` なので、コメントだけの本文を空と見なさないからです。無効化は何も抑えていないので `Lint/RedundantCopDisableDirective` が出ます。また独立した行の無効化になったので `Lint/MissingCopEnableDirective` も出て、無効化はファイルの終わりまで効きます。後ろに別の空の `if` があれば、その指摘も出なくなります。

## herb:disable と herb-format【実測・出典】

herb-format は、`<%# herb:disable … %>` を、ほかの `<%#` とは別に扱います【出典: `@herb-tools/formatter` の `dist/index.cjs` の `HerbDisableCollector` と `spliceHerbDisableComments`】。

- 整形の前に、`herb:disable` のコメントを構文木から外し、同じ行で直前にあるノードを「アンカー」として覚える
- 整形の後、アンカーのテキスト（ERB タグなら `<%= … %>` の全文、要素なら `</div` のようなタグ名）を出力の先頭から検索し、最初に見つかった行の末尾に空白 1 つを挟んでコメントを付け直す
- アンカーがない、またはテキストで検索できないノード（`if` などの制御構文）のときは、親のノードのテキストで検索する。それも見つからなければ、出力の最後の行に付ける

[repro/erb-comment/herb-disable/](repro/erb-comment/herb-disable/) の 4 ファイルを整形した結果です【実測】。

| ファイル | 整形前 | 整形後 | herb-lint の結果（整形前 → 整形後） |
|---|---|---|---|
| `img.html.erb` | `<img src="a.png"> <%# herb:disable html-img-require-alt %>` | 同じ行の行末に残る（インデントだけ直る） | 効く → 効く |
| `same_anchor.html.erb` | 同じ `<img src="a.png">` が 2 行並び、2 行目の行末に `herb:disable` | 1 行目の `<img>` の行末に付く | 効く → **効かない**（2 行目の `<img>` に `html-img-require-alt` が出る） |
| `empty_if.html.erb` | `<% if some_error %><%# herb:disable erb-no-empty-control-flow %>`⏎`<% end %>` | `<% end %> <%# herb:disable … %>`（最後の行） | 不要 → **効かない**（`if` に `erb-no-empty-control-flow` が出る） |
| `if_sibling.html.erb` | `<div>` の中で `<% if some_error %><%# herb:disable … %><% end %>` | `</div> <%# herb:disable … %>` | 不要 → **効かない**（`if` に `erb-no-empty-control-flow` が出る） |

- `empty_if.html.erb` と `if_sibling.html.erb` では、整形の前に `herb-disable-comment-unnecessary` が出ます。`herb:disable` のコメント自体が `if` の本文になり、`if` が空でなくなるからです。整形でコメントが `if` の外に出ると `if` が空になり、`erb-no-empty-control-flow` が出ます。移った先の行でも `herb-disable-comment-unnecessary` が出ます
- `same_anchor.html.erb` は、アンカーをテキストで検索するため、同じ内容の 1 行目に付きます

## 考察【推測】

- rubocop-herb の行単位の無効化は、`<%#` がコードと同じ行の右端にあることを前提にしています。herb-format を使うプロジェクトでは、整形でこの前提が崩れ、無効化が外れます。多くの場合は offense が出るので気づけますが、`empty_if.html.erb` のように offense が出ないまま無効化の範囲だけが広がることもあります。herb-format と併用するなら、無効化コメントは独立した行に書き、`rubocop:enable` で閉じるのが確実です
- rubocop-erb 0.8 系と herb-format を併用すると、0.8 系で範囲を指定して無効にする書き方（複数行のタグ）が、整形で `<% # … %>` になって効かなくなります。今回試した書き方のうち、整形の後も 0.8.2 で効くのはタグの中の行末のコメントだけで、`Lint/CopDirectiveSyntax` が出るうえ、効くのはその行だけです
- `<%#` の右側にタグがあるときに rubocop-herb が `Herb/IgnoredCopDirective` を出すことは、ruumba のように後ろのコードを黙って検査から外すより安全です
- `herb:disable` は herb-format で行末に残るように作られている一方、`rubocop:disable` の `<%#` は整形で動きます。ERB の中で使う 2 つの無効化コメントのうち、行末に書けるのが片方だけというのは釣り合いが取れていません。ただ、`herb:disable` の書き戻しもテキスト検索に頼っていて、制御構文や同じ内容のタグでは別の行に付きます。行末の無効化コメントを整形でどう保つかは、`herb:disable` と `rubocop:disable` をまとめて仕様を議論する必要があります

## 今後の検討事項

- herb-format が `<%# rubocop:disable … %>`（と `<%# rubocop:enable … %>`）を、`herb:disable` と同じく行末に残すべきか。残すなら、どの行に付けるか（アンカーの決め方）
- `herb:disable` の書き戻しの行を、テキスト検索ではなくノードの位置で決められないか（`same_anchor.html.erb`、`empty_if.html.erb`、`if_sibling.html.erb`）
- 無効化のコメントだけを本文に持つ `if` を、空として扱うか。herb-lint の `erb-no-empty-control-flow` は `<%#` を本文として数え、rubocop の `Lint/EmptyConditionalBody` は `AllowComments: true` でコメントだけの本文を許す。どちらも、無効化のコメントが指摘を消してしまう
