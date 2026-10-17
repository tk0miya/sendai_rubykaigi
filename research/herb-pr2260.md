# herb 公式の rubocop-herb（marcoroth/herb#2260）と tk0miya/rubocop-herb の比較

調査日: 2026-10-16

herb 本体のリポジトリに提案されている RuboCop プラグイン（[marcoroth/herb#2260](https://github.com/marcoroth/herb/pull/2260)、以下「PR 版」）を、tk0miya/rubocop-herb（以下「rubocop-herb」）と比べた結果です。
【実測】は手元で実行して確かめたこと（再現手順は [repro/README.md](repro/README.md#herb-pr-2260)）、【出典】はソースコードや PR の議論で確かめたこと、【推測】は解釈です。

## 対象

- PR 版: `d0323df360553502e31b14ff570990f907f46b2a`（2026-10-06 時点の PR の head。Draft）の `gems/rubocop-herb`
- rubocop-herb: https://github.com/tk0miya/rubocop-herb の `2cf8414fb988dac08bc5d78cabf9c5bfe1328a8c`（2026-10-16 時点の main）
- herb 0.11.0（rubygems のビルド済み gem）/ rubocop 1.91.0 / ruby 4.0.5
- 設定は両方とも `NewCops: enable`、`TargetRubyVersion: 3.4`。rubocop-herb はリポジトリの `config/develop/rubocop.yml` を継承し、`Herb/Linting` を無効にした（[repro/herb-pr2260/](repro/herb-pr2260/)）
- 入力
  - [repro/](repro/) の既存ツールの再現例と rubocop-herb の再現例（22 ファイル）
  - 境界ケース（[repro/herb-pr2260/edge/](repro/herb-pr2260/edge/)、12 ファイル）
  - 実際のビュー: rails/rails `0f591639b8` と kaigionrails/conference-app `25a02cc` の `*.html.erb`（333 ファイル）

## まとめ

- PR 版も rubocop-herb と同じく、**文書全体を位置を保った 1 本の Ruby にして**、RuboCop の ruby_extractors API に渡す方式です
- ただし変換は `Herb.extract_ruby` で ERB タグ以外を空白にするだけで、`<%=` の「出力する」という意味が残りません。HTML も空白になるので、HTML だけを本文に持つ分岐やブロックは空に見えます。誤検知への対策は、cop をファイル全体で除外することだけです
- autocorrect の結果を検査する仕組みがありません。このため **`-a`（安全な修正だけ）でもテンプレートを壊します**。実際のビュー 333 ファイルでは、63 ファイルで HTML が変わり、59 ファイルで Herb のパースエラーが増えました。rubocop-herb では、どちらも 0 ファイルでした
- 主な原因は、既定で有効な `Layout/ExtraSpacing` と、メンテナの要望で除外を外した `Lint/Void` です。どちらも、空白にした HTML や ERB の区切りを Ruby の空白として扱い、修正で削除します
- rubocop-herb の側にも、PR 版では出ない誤検知が実際のビューで 3 種類ありました（`Lint/EmptyFile`、`Naming/FileName`、`Layout/EmptyLineAfterMagicComment`）

## PR の状況【出典】

- 作者は Joel Hawksley 氏（GitHub）。GitHub で erb_lint をやめて Herb に移るにあたり、erb_lint の RuboCop linter の代わりが必要だというのが動機
- Marco Roth 氏の整理では、herb 公式の rubocop-herb gem には 2 つの役割がある。(1) Herb の linter のルールを RuboCop の実行の中で動かす、(2) 設定済みの RuboCop の cop を ERB の中の Ruby に適用する。この PR は (2) だけを実装する
- レビューでは、`Lint/Syntax` と `Lint/Void` を除外しないこと、`Style/WhileUntilDo` と `Lint/OutOfRangeRegexpRef` を除外の一覧から外すことが求められ、反映されている。`Lint/Void` は [marcoroth/herb#1619](https://github.com/marcoroth/herb/issues/1619)（`<%= %>` の中の複数行の Ruby で、演算子の優先順位の誤りを `Lint/Void` が見つけた例）を理由にしている
- 作者は、RuboCop と Herb の「バイト位置と文字位置」の扱いの違いを調べるため、Draft に戻している

## 仕組み【出典】

### Ruby の取り出し

`gems/rubocop-herb/lib/rubocop/herb/plugin.rb`（74 行）がすべてです。

- `.erb` と `.herb` のファイルで、`Herb.extract_ruby` を呼ぶ。C の lexer が出すトークンを順に見て、ERB タグの中身だけを残し、それ以外を同じバイト数の空白にする。タグの終わりには `;` を補う
- `<%=` も `<%` も空白になる。`<%= foo %>` は、ただの式 `foo;` になる
- `<%# … %>` と、`<% # … %>` のように `#` で始まる 1 行のタグの中身は、空白になる
- `<%%` は空白になる
- HTML のマルチバイト文字は、バイト数の空白に置き換わる。`position_preserving_ruby` が元の 1 文字を 1 文字の空白に戻し、文字位置を元の ERB と揃える
- `Extractor` は `[{ offset: 0, processed_source: … }]`、つまりファイル全体を 1 つの fragment として返す。ERB 以外のファイルでは `nil` を返して、RuboCop の通常の処理に任せる。Ruby が空のファイルでは `[]` を返し、何も検査しない

変換の例（`Herb.extract_ruby` の出力。行末の空白は省略）【実測】:

```erb
<div>
  <%= @user.name %>
</div>
<% if a %>
  text
<% end %>
<% items.each do |item| %>
  <li><%= item.name %></li>
<% end %>
```

```ruby

      @user.name  ;

   if a  ;

   end  ;
   items.each do |item|  ;
          item.name  ;
   end  ;
```

### 除外している cop

`config/default.yml` で、`AllCops/Include` に `**/*.erb` と `**/*.herb` を加え、次の 48 個の cop を同じパターンのファイルから除外しています。

- Layout 33 個: `ArgumentAlignment`, `ArrayAlignment`, `BlockAlignment`, `ClosingParenthesisIndentation`, `CommentIndentation`, `InitialIndentation`, `EmptyLineAfterGuardClause`, `EndAlignment`, `FirstArgumentIndentation`, `FirstArrayElementIndentation`, `FirstArrayElementLineBreak`, `FirstHashElementIndentation`, `FirstHashElementLineBreak`, `FirstMethodArgumentLineBreak`, `FirstParameterIndentation`, `HashAlignment`, `IndentationConsistency`, `IndentationWidth`, `LeadingEmptyLine`（存在しない cop 名）, `LeadingEmptyLines`, `LineEndStringConcatenationIndentation`, `LineLength`, `MultilineArrayBraceLayout`, `MultilineAssignmentLayout`, `MultilineHashBraceLayout`, `MultilineMethodCallBraceLayout`, `MultilineMethodCallIndentation`, `MultilineMethodDefinitionBraceLayout`, `MultilineOperationIndentation`, `ParameterAlignment`, `SpaceBeforeSemicolon`, `TrailingEmptyLines`, `TrailingWhitespace`
- Lint 2 個: `EmptyFile`, `EmptyConditionalBody`
- その他: `Metrics/BlockLength`, `Naming/FileName`, `Rails/Presence`, `Style/FrozenStringLiteralComment`, `Style/EmptyElse`, `Style/IdenticalConditionalBranches`, `Style/IfWithSemicolon`, `Style/IfUnlessModifier`, `Style/MultilineTernaryOperator`, `Style/NestedTernaryOperator`, `Style/Next`, `Style/Semicolon`, `Style/WhileUntilModifier`

`Layout/ExtraSpacing`、`Lint/Void`、`Lint/EmptyBlock`、`Lint/EmptyWhen`、`Style/SymbolProc`、`Style/BlockDelimiters`、`Style/SingleLineDoEndBlock` は除外していません。

### rubocop-herb との違い

| | PR 版 | rubocop-herb |
|---|---|---|
| 規模 | plugin.rb 74 行 + default.yml 108 行 | `lib/` 全体で約 3,100 行 |
| ERB の読み方 | Herb の lexer のトークン（C 実装） | Herb の AST |
| `<%= foo %>` | `foo;` | `_ = foo;` |
| HTML | 空白 | `div;` や `_a;` などの識別子 |
| 誤検知への対策 | 48 個の cop をファイル全体で除外 | 9 個をファイル全体で除外し、ほかは ERB の構造を見て誤検知になる行だけで無効にする（[report.md](report.md#除外している-cop-と行単位で無効にしている-cop)） |
| autocorrect の検査 | なし | `CopCorrectionGuard`（[report.md](report.md#autocorrect-の検査copcorrectionguard)） |
| `<%# rubocop:disable … %>` | 効かない（コメントは空白になる）。タグの中の行末のコメントは効く【実測】 | 効く【実測】 |
| herb-lint の実行 | なし（PR の対象外） | `Herb/Linting` cop |

## 既存の再現例での結果【実測】

`erb_lint`、`rubocop-erb`、`ruumba`、`rubocop-herb`、`herb/app` の 22 ファイルにかけた結果です。

| | PR 版 | rubocop-herb |
|---|---|---|
| offense の数 | 97 | 32 |
| `Layout/ExtraSpacing` | 62 | 0 |

`Layout/ExtraSpacing` を除くと、次の offense が片方にだけ出ます。

PR 版だけに出るもの（すべて誤検知）:

| cop | 例 | 理由 |
|---|---|---|
| `Layout/ExtraSpacing`（62 件） | ほぼすべての ERB タグ | `%>` が `;` の前の 2 つの空白になる |
| `Lint/Void`（4 件） | `<p><%= total %></p>`、`<%= name %>: <%= count -1 %>`、`<%= user.name.nil? ? "anon" : user.name %>` | 出力する式が、ただの式文になる |
| `Style/SymbolProc`（3 件） | `<% items.each do \|item\| %><%= item.name %><% end %>` | 同上。`-A` で従うと出力がなくなる |
| `Lint/EmptyBlock`（1 件） | `<% items.each do \|i\| %><li>item</li><% end %>` | 本文の HTML が空白になる |

rubocop-herb だけに出るもの:

| cop | 例 | |
|---|---|---|
| `Lint/UnusedBlockArgument` | 上の `\|i\|` | PR 版は本文が空のブロックとみなすので出ない |
| `Style/EmptyElse`, `Lint/EmptyConditionalBody` | `erb_lint/recommended/control_flow.html.erb` の本当に空の `else` / `unless` | PR 版はファイル全体で除外している |
| `Style/IdenticalConditionalBranches` | `rubocop-herb/identical_branches_output.html.erb` の 2 つの `<%= foo %>` | PR 版はファイル全体で除外している。rubocop-herb では autocorrect できない offense として報告され、`-A` でも修正されない |

## 境界ケースでの結果【実測】

[repro/herb-pr2260/edge/](repro/herb-pr2260/edge/) の 12 ファイルの結果です。

- マルチバイト文字: `<p>日本語 <%= x=1 %></p>` と `<%# 日本語のコメント %>` の次の行で、両方とも offense の位置は正しく、`-a` の結果も元の位置に書き戻される
- `case` / `when` の本文が HTML だけのとき、PR 版では各 `when` に `Lint/EmptyWhen` が出る
- `<% # note %>` は、PR 版では空白になる。rubocop-herb では Ruby のコメントとして扱われ、`Style/CommentAnnotation` が出る
- `<%# rubocop:disable Style/StringLiterals %>` は、PR 版では効かない。`<% x = "b" # rubocop:disable Style/StringLiterals %>` は、両方で効く

## autocorrect の結果【実測】

PR 版は、`-a` でも次のようにテンプレートを壊します。ファイルごとの `-a` の前後です。

`repro/herb-pr2260/edge/two_tags_line.html.erb`:

```erb
<td><%= user.name %></td><td><%= user.email %></td>
```

↓ `-a`

```erb
<td><%= user.name%> user.email%></td>
```

`repro/herb-pr2260/edge/inline_if.html.erb`:

```erb
<% if a %>A<% else %>B<% end %>
```

↓ `-a`

```erb
<% if a%> else%> end%>
```

`repro/herb/app/views/samples/cross_tag_variables.html.erb`:

```erb
<% total = items.sum(&:price) %>
<p><%= total %></p>
<% unused = 1 %>
<% items.each do |item| %>
  <li><%= item.name %></li>
<% end %>
```

↓ `-a`

```erb
<% items.sum(&:price)%>%></p>%>
<% items.each do |item|%>
  <li><%= item.name%></li>
<% end%>
```

- `two_tags_line.html.erb` と `inline_if.html.erb` は `Layout/ExtraSpacing` の修正です。同じ行の 2 つの ERB タグの間（`%></td><td><%=` や `%>A<%`）は、Ruby では `;` と次の式の間の空白に見えるので、まとめて削除されます
- `cross_tag_variables.html.erb` は `Lint/Void` と `Lint/UselessAssignment` の修正です。`<%= total %>` の `total` などを前後の空白ごと削除するときに、`%></p>` や次の行の `<%` も消えます
- 修正対象ではないタグでも、`%>` の前の空白が `Layout/ExtraSpacing` で削除される（`<% end %>` → `<% end%>`）
- `-A` では、さらに `Style/SymbolProc` で、`cross_tag_variables.html.erb` の出力するブロックが `<% items.each(&:name)%>` になり、出力がなくなる

再現例と境界ケース（34 ファイル）で、`-a` の前後を比べた結果です（[html_changes.rb](repro/herb-pr2260/html_changes.rb)。HTML は空白の違いを無視して比べる）。

| | 書き換わったファイル | HTML が変わった | パースエラーが増えた |
|---|---|---|---|
| PR 版 `-a` | 33 | 9 | 9 |
| PR 版 `-A` | 33 | 9 | 9 |
| rubocop-herb `-a` | 19 | 0 | 0 |
| rubocop-herb `-A` | 20 | 0 | 0 |

`html_changes.rb` は HTML とパースエラーだけを見るので、`Style/SymbolProc` で出力がなくなるような変化は数えていません。

## 実際のビューでの結果【実測】

rails/rails と kaigionrails/conference-app の `*.html.erb`（333 ファイル）にかけた結果です。

| | PR 版 | rubocop-herb |
|---|---|---|
| offense の数 | 2,455 | 992 |
| `-a` で書き換わったファイル | 251 | 140 |
| うち HTML が変わったファイル | 63 | 0 |
| うちパースエラーが増えたファイル | 59 | 0 |
| 実行時間（`--cache false`、検出のみ） | 2.4 秒 | 3.0 秒 |

片方にだけ多く出る cop:

| cop | PR 版 | rubocop-herb | 内容 |
|---|---|---|---|
| `Layout/ExtraSpacing` | 1,606 | 0 | 上記の誤検知 |
| `Lint/Void` | 50 | 0 | 変数 29 件（`<%= event.name %>` など）、リテラル 20 件（`<%= event.ongoing? ? "true" : "" %>`、`<%= ' current' if page.current? %>` など）、演算子 1 件。いずれも出力する式 |
| `Lint/EmptyBlock` | 30 | 2 | PR 版の 28 件は、本文が HTML だけのブロック（`<%= link_to path do %>…<% end %>` など）。2 件は両方に出る、本当に空のブロック |
| `Style/SingleLineDoEndBlock`, `Style/BlockDelimiters` | 10, 8 | 0, 0 | `<%= cache "fragment" do %><p>ERB</p><% end %>` のように 1 行に書いた、本文が HTML のブロック |
| `Layout/LineLength` | 0 | 217 | PR 版はファイル全体で除外している。rubocop-herb は ERB の行の長さを検査する |
| `Lint/EmptyFile` | 0 | 16 | 0 バイトのテンプレート（rails のテスト用の fixture、conference-app の `admin/signage_devices/edit.html.erb`） |
| `Naming/FileName` | 0 | 3 | `_FooBar.html.erb`、`_a-in.html.erb`、`hello_world.pt-BR.html.erb` |
| `Layout/EmptyLineAfterMagicComment` | 0 | 3 | `<%# encoding: utf-8 -%>` の次の行 |

`Lint/Void` の誤検知には、[marcoroth/herb#1619](https://github.com/marcoroth/herb/issues/1619) のもとになった rails の `active_storage/blobs/_blob.html.erb`（`<%= blob.representable? ? "preview" : "file" %>`）も含まれます。

## 評価【推測】

- PR 版の誤検知と壊れる autocorrect は、変換の段階で `<%=` の意味と HTML の存在を落としていることから生じている。除外する cop を増やせば `Layout/ExtraSpacing` などは止められるが、`Lint/Void` のように除外しないと決めた cop では、出力する式の誤検知が残る
- `Layout/ExtraSpacing` は RuboCop の既定で有効なので、PR 版を既定の設定で入れて `rubocop -a` を実行すると、同じ行に ERB タグが 2 つ以上あるテンプレートが壊れる。修正後の ERB を検査する仕組み（rubocop-herb の `CopCorrectionGuard` に当たるもの）がない限り、autocorrect を安全に使えない
- 一方で、PR 版は小さく、herb 本体の C 実装に乗っているので保守しやすい。herb 公式の gem として出すための土台としては妥当で、`<%=` を `_ =` にするような変換を `extract_ruby` のオプションとして C 側に足す方向もありうる
- rubocop-herb で実際のビューに出た `Lint/EmptyFile`、`Naming/FileName`、`Layout/EmptyLineAfterMagicComment` は、テンプレートでは誤検知とみなせる。ERB の既定の設定で除外を検討する余地がある
