# rubocop-herb と既存の ERB linter の比較

調査日: 2026-10-10（2026-10-11 に `1483080` で再確認）

[existing-erb-linters.md](existing-erb-linters.md) で調べた既存の ERB linter と、tk0miya/rubocop-herb を比較した結果です。
【実測】は手元で実行して確かめたこと（再現手順は [repro/README.md](repro/README.md#rubocop-herb)）、【出典】はソースコードで確かめたこと、【推測】は解釈です。

## 対象

- rubocop-herb: https://github.com/tk0miya/rubocop-herb の `14830806e5deb61e27744e9fed09c5380ccbeee7`（2026-10-11 時点の main）
- rubocop 1.91.0 / herb 0.11.0（同リポジトリの `Gemfile.lock`）
- ruby 4.0.5
- 設定はリポジトリの `config/develop/rubocop.yml`
- 特に断りがない限り、`Herb/Linting` cop（herb-lint の実行）は無効にして、RuboCop の結果だけを比べた

## まとめ

- rubocop-herb は、ruumba と同じく **HTML を空白で埋めて、文書全体を 1 本の Ruby にする**方式です
- タグ単位の方式（erb_lint, rubocop-erb）で起きていた見逃し・誤検知・テンプレートを壊す autocorrect は、research の再現例ではすべて解消しています
- ruumba で新たに生じていた問題も、大半は解消しています
  - `<%=` を `_ =` に置き換えて「出力する」という意味を残すので、`Lint/Void` や `Style/SymbolProc` の誤検知が出ない
  - 文字位置を変えずに変換するので、autocorrect の結果をそのまま元の ERB に書き戻せる（ruumba のように黙って書き戻しを諦めることがない）
  - HTML だけを本文に持つ分岐やブロックでは、空の本文を指摘する cop をその行だけ無効にする。cop 全体を除外しないので、本当に空の `else` などは検出できる
  - ファイル全体で除外する cop は 9 個だけ。Layout 系などの誤検知は、ERB の構造を見て該当する行だけで cop を無効にする
- `Herb/Linting` cop で herb-lint も同時に実行でき、HTML の構造の誤りも RuboCop の出力に並びます（Node.js と `@herb-tools/linter` が必要）
- 一方で、**`-a`（安全な autocorrect）でテンプレートを壊す**問題が 1 件残っています

## 仕組み【出典】

### Ruby の取り出し

`Converter`（`lib/rubocop/herb/converter.rb`）が、Herb の AST をもとに ERB を Ruby に変換します。

- 元の ERB をいったんすべて空白に置き換え（改行は残す）、ERB タグの中身を元と同じ文字位置に書き戻す（`RubyRenderer#bleach_code`, `#render_code_node`）
- タグの中身の直後に `;` を補う。`<%` `%>` の分の空白があるので、位置はずれない
- `<%=` は常に `_ =` に置き換える（`#render_output_marker`）
- `<%# … %>` は、右側に別のタグがない場合だけ Ruby のコメントにする
- 正規表現ではなく Herb の AST で ERB の構造を読むので、`<%-` / `-%>` や属性値の中のタグも扱える

HTML も Ruby の識別子として書き込みます【実測】。

```erb
<div class="user">
  <%= @user.name %>
</div>
<% if a %>
  text
<% end %>
```

```ruby
div;
  _ = @user.name;
div;
   if a;
  _a;
   end;
```

- 要素の開始タグ・終了タグは `div;` などのタグ名に、本文のテキストは `_a;` などになる。要素は入れ子のブロックにせず平坦に並べる。識別子を置けないほど短いテキストは空白のままになる
- HTML だけの本文も空にならないので、空の本文の誤検知や、入れ子の条件を統合して HTML を消す autocorrect（`Style/SoleNestedConditional` など）が起きない
- エラーの表示では、`hybrid_code`（識別子の部分を元の HTML に戻したもの）を表示用のソースとして使い、`RuboCopASTTransformer` が AST の位置情報を元の HTML の範囲に置き換える

### RuboCop との連携

- LintRoller プラグインとして読み込まれ、RuboCop の ruby_extractors API に `Extractor` を登録する（`lib/rubocop/herb/plugin.rb`）
- `Extractor` は `[{ offset: 0, processed_source: … }]`、つまり **ファイル全体を 1 つの fragment** として返す（`lib/rubocop/herb/extractor.rb`）
- 文字位置が元の ERB と一致しているので、offense の位置も autocorrect の修正範囲も、変換せずに元のファイルに適用できる
- rubocop-erb の制約（[existing-erb-linters.md](existing-erb-linters.md#rubocop-erb) の「1 つの fragment は元ファイル上の連続した 1 区間」）は、ファイル全体を 1 区間にすることで回避している
- RuboCop と同じプロセス内で動く。ruumba のように一時ファイルや子プロセスを使わない

### 除外している cop と、行単位で無効にしている cop

`lib/rubocop/herb/configuration.rb` で、次の 9 個の cop を `**/*.html.erb` から除外しています。

- `Layout/CommentIndentation`, `Layout/ExtraSpacing`, `Layout/IndentationConsistency`, `Layout/InitialIndentation`, `Layout/LeadingEmptyLines`, `Layout/TrailingEmptyLines`
- `Metrics/BlockLength`
- `Style/FrozenStringLiteralComment`, `Style/Semicolon`

rubocop-erb は約 55 個、ruumba の推奨設定は 5 個です。`Lint/Syntax` と `Lint/UselessAssignment` は除外していません。

それ以外の誤検知は、ERB の構造を見て、誤検知になる行でだけ cop を無効にしています（`<%# rubocop:disable %>` と同じ仕組み）。対象は 19 個です。

| cop | 無効にする場所 | 実装 |
|---|---|---|
| `Lint/EmptyConditionalBody`, `Style/EmptyElse`, `Lint/EmptyWhen`, `Lint/EmptyInPattern`, `Lint/EmptyBlock`, `Lint/SuppressedException`, `Lint/EmptyEnsure` | 本文に HTML を含む分岐・ブロック | `DisabledCopsCollector` |
| `Style/IfWithSemicolon`, `Style/IfUnlessModifier`, `Style/ConditionalAssignment`, `Style/RedundantCondition`, `Style/Next` | 複数の ERB タグに跨がる条件分岐 | `DisabledCopsCollector` |
| `Style/OneLineConditional` | 1 行で書かれた、複数の ERB タグに跨がる条件分岐 | `DisabledCopsCollector` |
| `Style/BlockDelimiters` | 1 行で書かれた、複数の ERB タグに跨がるブロック | `DisabledCopsCollector` |
| `Layout/EndAlignment`, `Layout/BlockAlignment` | 複数の ERB タグに跨がる分岐・ループ・ブロックの `<% end %>` | `DisabledCopsCollector` |
| `Layout/IndentationWidth` | 複数の ERB タグに跨がる本文の、最初の内容から最初の ERB タグまで | `DisabledCopsCollector` |
| `Style/IdenticalConditionalBranches` | HTML と隣り合っていて、分岐の外に移せない式 | `ImmovableExpressionCollector` |
| `Layout/TrailingWhitespace` | 変換で空白になった ERB の区切りや HTML による行末の空白（利用者が書いた行末の空白は検出する） | `TrailingWhitespaceCollector` |

1 つの ERB タグの中に書かれた条件分岐・ブロック・本文は、どの cop も無効にせず検査します【出典】。

入れ子の空の `if` は、外側の分岐に HTML があっても検出されることを確認しました【実測】。

### Herb/Linting cop

`Herb/Linting`（`lib/rubocop/cop/herb/linting.rb`）は、herb-lint を Node.js のプロセスで実行し、その結果を RuboCop の offense として報告します。

- 既定で有効。`@herb-tools/linter` が入っていなければ、セットアップを促すエラーを 1 回だけ報告する（README に記載）
- Node.js のプロセスは RuboCop のプロセスごとに 1 つ起動し、全ファイルで使い回す
- herb-lint の autocorrect には対応していない（README に記載）
- `<div><span></div>` の閉じタグ漏れが `E: Herb/Linting: [parser-no-errors] Opening tag <span> at (1:6) doesn't have a matching closing tag </span> in the same scope. (MISSING_CLOSING_TAG_ERROR)` として、RuboCop の offense と同じ出力に並ぶことを確認した（`@herb-tools/linter` 0.11.0）【実測】

## 既存ツールの問題に対する結果【実測】

research の再現例（`repro/erb_lint`, `repro/rubocop-erb`, `repro/ruumba`, `repro/herb/app`）にかけた結果です。

| ERB | 既存ツールの結果 | rubocop-herb |
|---|---|---|
| `<% if foo == nil %>…<% end %>` | erb_lint / rubocop-erb: 見逃す | `Style/NilComparison` を検出し、`foo.nil?` に修正 |
| `<% if !user.nil? %>…<% end %>` | erb_lint / rubocop-erb: 見逃す | `Style/NegatedIf` を検出し、`unless user.nil?` に修正 |
| `then` / `elsif bar == nil` / `unless !x` | erb_lint: 見逃す | `Style/MultilineIfThen`, `Style/NilComparison`, `Style/NegatedUnless` を検出し、正しく修正 |
| 本当に空の `<% else %>` / `<% unless !x %><% end %>` | erb_lint: 見逃す | `Style/EmptyElse`, `Lint/EmptyConditionalBody` を検出し、`<% else %>` を削除 |
| `<% name = "Alice" %>` + `<%= name %>` | erb_lint: `Lint/UselessAssignment`（誤検知） | 出ない |
| 本当に未使用の `<% unused = 1 %>` | Herb: 検出する | `Lint/UselessAssignment` を検出する（ただし autocorrect でテンプレートが壊れる。下記「文の削除が `<%` ごと消す」） |
| `<% count = items.size %>` + `<%= count -1 %>` | rubocop-erb: `count(-1)` に書き換える | ローカル変数と認識し、`Layout/SpaceAroundOperators` で `count - 1` に修正 |
| `<% items.each do \|item\| %>` + `<%= item *2 %>` | rubocop-erb: `item(2)` に書き換える | `item * 2` に修正 |
| `<% if user && user.admin? %>` | rubocop-erb: `user&&.admin?`（構文エラー） | `user&.admin?` に正しく修正（`-A`） |
| `<% end.join(", ") %>`、`<% result = if foo %>` | rubocop-erb: 黙って無視する | 解析でき、`", "` は `', '` に正しく修正される。使われていない `result` には `Lint/UselessAssignment` が出る |
| `<p><%= name %>: <%= count -1 %></p>` | ruumba: `name` に `Lint/Void` | 出ない |
| `<% items.each do \|item\| %>` + `<%= item.name %>` | ruumba: `Style/SymbolProc`（誤った提案） | 出ない |
| 本文が HTML だけの `if` | ruumba: `Lint/EmptyConditionalBody` | 出ない（その分岐で cop を無効にする） |
| `<%= a %><%= b %>` | ruumba: 補った `;` に `Style/Semicolon` | 出ない（cop を除外） |
| `Layout/TrailingWhitespace`, `Layout/InitialIndentation` など | ruumba: 17 ファイルで 71 件 | 出ない（`Layout/TrailingWhitespace` は変換で生じた空白の行だけで無効化、`Layout/InitialIndentation` は除外） |
| `Style/FrozenStringLiteralComment` | erb_lint: タグごとに出る | 出ない（cop を除外） |
| `<%= link_to "x", path, class: 'btn' %>` の autocorrect | erb_lint: `<%=` が消え、マジックコメントが入る | `'x'` だけが修正される |
| `<%`⏎`  x = 1`⏎`  y = 2`⏎`%>` の autocorrect | erb_lint: `<%` が消える | 変更なし（`Layout/LeadingEmptyLines` を除外） |
| `<%== raw_html %>` | ruumba: `<%= raw raw_html %>` に書き換える | 変更なし |
| `end` の抜け | Herb: 検出する / rubocop-erb: `Lint/Syntax` を除外 | `Lint/Syntax` を検出する |
| `<%= link_to( 'Home',root_path ) %>` | Herb: 検出しない | `Layout/SpaceInsideParens`, `Layout/SpaceAfterComma` を検出し、修正 |

このほか、次のケースも位置がずれずに修正できることを確認しました。

- 日本語を含む行（`<p>こんにちは</p><%= link_to( "ホーム",root_path ) %>`）
- `<%-` / `-%>` を使ったタグ
- 属性値の中のタグ（`<div class="<%= active ? "on" : "off" %>">`）
- `<%= form_with … do |f| %>…<% end %>`（変更なし）

## 未解決の問題【実測】

詳しい再現手順は、upstream に報告する再現レポート（[rubocop-herb-issues/](rubocop-herb-issues/)）にまとめています。

| 問題 | 影響 | 条件 |
|---|---|---|
| 文の削除が `<%` ごと消す: 文を削除する修正（`Lint/Void` など）が、左側の `<%` や改行ごと削除する | **`-a` でテンプレートを壊す** | 値を使わないリテラルや、未使用の変数への代入の後ろに、別の文が続く場合 |

### autocorrect がテンプレートを壊す原因【出典・推測】

この autocorrect は、修正範囲が ERB タグの中身の外にはみ出しています【実測】。`Lint/Void` は `range_with_surrounding_space(side: :left)` で、削除する文の左側の空白もまとめて削除します。その空白は、元の ERB では改行と `<% ` です。

変換後の Ruby では空白でも、元の ERB では区切りに当たる部分を、RuboCop の修正処理が書き換えています。周囲の空白ごと削除・置換する修正はほかの cop にもあり（`range_with_surrounding_space`, `range_by_whole_lines` など）、cop を個別に除外・無効化するだけでは防ぎきれません【推測】。

修正範囲が ERB タグの中身の外にかかる修正を、適用する前に捨てる仕組みがあれば防げます。RuboCop 1.91.0 の `Team#collate_corrections`（`lib/rubocop/cop/team.rb:324`）は cop ごとの corrector を 1 つずつ統合しているので、そこで cop ごとに検査できる見込みです【推測】。

## 比較表への追加

[existing-erb-linters.md](existing-erb-linters.md#ツール一覧と比較) の比較表に rubocop-herb を加えると、次のようになります。

| ツール | HTML 構造 | Ruby の構文 | Ruby のスタイル (RuboCop) | タグを跨いだ Ruby 解析 | autocorrect | 型・意味解析 |
|---|---|---|---|---|---|---|
| erb_lint (Rubocop linter) | ○ (better_html) | △ (タグ単位。不完全な文はスキップ) | △ (タグ単位) | × | △ (テンプレートを壊す) | × |
| rubocop-erb | × | △ (タグ単位。Lint/Syntax を除外) | △ (タグ単位。約 55 cop を除外) | × | △ (意味・構文を壊す) | × |
| ruumba (メンテ停止) | × | ○ (文書全体) | △ (文書全体。出力・HTML 本文が失われ誤検知) | ○ | △ (実験的。黙って書き戻さないことがある) | × |
| **rubocop-herb** | ◎ (Herb/Linting で herb-lint を実行。Node.js が必要) | ○ (文書全体) | ○ (文書全体。9 cop を除外し、19 cop を行単位で無効化) | ○ | △ (大半は正しいが、文を削除する cop がテンプレートを壊す) | × |

## その他【出典】

- README は使い方と `Herb/Linting` の説明が加わったが、Installation や Contributing などは `bundle gem` の雛形のまま
- gem 名が、rubygems に登録済みの Marco Roth 氏の `rubocop-herb` 0.0.1 と衝突している（[existing-erb-linters.md](existing-erb-linters.md#要フォローアップ) で既出）
- マルチバイト文字を含むテキストや HTML コメントが `hybrid_code` に戻らない issue（[#72](https://github.com/tk0miya/rubocop-herb/issues/72)）が open のまま
