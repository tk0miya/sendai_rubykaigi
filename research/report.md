# rubocop-herb と既存の ERB linter の比較

調査日: 2026-10-31

[existing-erb-linters.md](existing-erb-linters.md) で調べた既存の ERB linter と、tk0miya/rubocop-herb を比較した結果です。
【実測】は手元で実行して確かめたこと（再現手順は [repro/README.md](repro/README.md#rubocop-herb)）、【出典】はソースコードで確かめたこと、【推測】は解釈です。

## 対象

- rubocop-herb: https://github.com/tk0miya/rubocop-herb の `96d31cf8dff39109dbe4506b808e19693a92b2e2`（2026-10-29 時点の main）
- rubocop 1.92.0 / herb 0.11.0（同リポジトリの `Gemfile.lock`）
- ruby 4.0.5
- 設定はリポジトリの `config/develop/rubocop.yml`
- 特に断りがない限り、`Herb/Linting` cop（herb-lint の実行）は無効にして、RuboCop の結果だけを比べた。`Herb/Linting` は「Herb/Linting cop」の節で、`@herb-tools/linter` 0.11.0 を入れて別に確かめた

## まとめ

- rubocop-herb は、ruumba と同じく **文書全体を 1 本の Ruby にする**方式です。HTML は空白で埋めるのではなく、元の位置に識別子（`div;` など）として書き込みます
- タグ単位の方式（erb_lint, rubocop-erb 0.7 系）で起きていた見逃し・誤検知・テンプレートを壊す autocorrect は、research の再現例ではすべて解消しています
- ruumba で新たに生じていた問題も、大半は解消しています
  - `<%=` を `_ =` に置き換えて「出力する」という意味を残すので、`Lint/Void` や `Style/SymbolProc` の誤検知が出ない
  - 文字位置を変えずに変換するので、autocorrect の結果をそのまま元の ERB に書き戻せる（ruumba のように黙って書き戻しを諦めることがない）
  - HTML が識別子として見えるので、HTML だけを本文に持つ分岐やブロックも「空」には見えない。識別子を置けない短いテキストなどの分は、空の本文を指摘する cop をその行だけ無効にする
  - ファイル全体で除外する cop は 9 個だけ。Layout 系などの誤検知は、ERB の構造を見て該当する行だけで cop を無効にする
- **テンプレートを壊す autocorrect を捨てる仕組み**（`CopCorrectionGuard`）があります。修正を元の ERB に当ててみて、HTML が変わる修正、出力タグの数が変わる修正、Herb のパースエラーが増える修正は適用せず、「autocorrect できない offense」として報告します。ERB の区切りまで消す修正は、タグの中身に収まるように切り詰めてから検査します
- 文を消す修正で空になったタグは、`Herb/EmptyErbTag` cop が行ごと消します。`<% unused = 1 %>` は、通常の Ruby ファイルと同じく `-a` でタグごと消えます
- 一方で、**`-a` でテンプレートが壊れる問題が 1 件**あります。出力タグの直後に空の ERB タグがあるとき、`Layout/SpaceBeforeSemicolon` と `Herb/EmptyErbTag` の削除が重なり、出力タグの `%>` まで消えます。ガードは cop ごとの修正を検査するので、重ねた結果を見ていません
- また、**HTML を含むテンプレートでは、`Style/MethodCallWithoutArgsParentheses` などの指摘や修正が消えます**。RuboCop 1.92 の、修正後のコードをパースし直して確かめる cop が、rubocop-herb の変換と噛み合わないためです
- `Herb/Linting` cop で herb-lint も同時に実行でき、HTML の構造の誤りも RuboCop の出力に並びます（Node.js と `@herb-tools/linter` が必要）

## 仕組み【出典】

### Ruby の取り出し

`Converter`（`lib/rubocop/herb/converter.rb`）が、Herb の AST をもとに ERB を Ruby に変換します。

- 元の ERB をいったんすべて空白に置き換え（改行は残す）、ERB タグの中身を元と同じ文字位置に書き戻す（`RubyRenderer`）
- タグの中身の直後に `;` を補う。`<%` `%>` の分の空白があるので、位置はずれない
- `<%=` と `<%==` は常に `_ =` に置き換える
- `<%%`（エスケープしたタグ）はテキストとして扱い、HTML のテキストと同じく `_a;` などにする
- `<%# … %>` は、右側に別のタグや HTML がない場合だけ Ruby のコメントにする
- HTML のタグやテキストも、元の位置に Ruby の識別子として書き込む。要素の開始タグ・終了タグは `div;` などのタグ名に、本文のテキストは `_a;` などになる。要素は入れ子のブロックにせず平坦に並べる。識別子を置けないほど短いテキストは空白のままになる
- 正規表現ではなく Herb の AST で ERB の構造を読むので、`<%-` / `-%>` や属性値の中のタグも扱える

変換の例（`bin/erb2ruby` の出力。行末の空白は省略）【実測】:

```erb
<div class="user">
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
div;
  _ = @user.name;
div;
   if a;
  _a;
   end;
   items.each do |item|;
  li; _ = item.name;  li;
   end;
```

- エラーの表示では、`hybrid_code`（識別子の部分を元の HTML に戻したもの）を表示用のソースとして使い、`RuboCopASTTransformer` が AST の位置情報を元の HTML の範囲に置き換える

### RuboCop との連携

- LintRoller プラグインとして読み込まれ、RuboCop の ruby_extractors API に `Extractor` を登録する（`lib/rubocop/herb/plugin.rb`）
- `Extractor` は `[{ offset: 0, processed_source: … }]`、つまり **ファイル全体を 1 つの fragment** として返す（`lib/rubocop/herb/extractor.rb`）
- 文字位置が元の ERB と一致しているので、offense の位置も autocorrect の修正範囲も、変換せずに元のファイルに適用できる
- rubocop-erb の制約（[existing-erb-linters.md](existing-erb-linters.md#rubocop-erb) の「1 つの fragment は元ファイル上の連続した 1 区間」）は、ファイル全体を 1 区間にすることで回避している
- RuboCop と同じプロセス内で動く。ruumba のように一時ファイルや子プロセスを使わない

### autocorrect の検査（CopCorrectionGuard）

`lib/rubocop/herb/cop_correction_guard.rb` と `lib/rubocop/herb/correction_validator.rb` です。

- `RuboCop::Cop::Base` に prepend され、cop が `correct` を呼ぶたびに、修正をいったん別の corrector に作らせて検査する。ERB 以外のファイルには影響しない
- 検査の前に、`CorrectionAdjuster`（`lib/rubocop/herb/correction_adjuster.rb`）が、ERB タグの外から始まる（または外で終わる）修正を、はみ出した部分が変換後の Ruby で空白のときに限り、タグの中身に収まるよう切り詰める。`Lint/Void` が `<% 1 %>` の `1` を左側の空白ごと消すと `<%` まで消えるが、切り詰めると `1` だけが消える。切り詰めた修正と元の修正のうち、検査に通るものを切り詰めた方から選ぶ
- `CorrectionValidator#valid?` は、修正を元の ERB に当てた結果について、次の 3 点を確かめる
  - ERB タグの間の HTML（両端の空白を除く。`<%%` のタグはテキストとして含める）が、修正前と同じ並びで残っている
  - 出力タグ（`<%=` / `<%==`）の数が変わっていない
  - Herb のパースエラーが増えていない
- 検査に通らなかった修正は捨て、その offense は「autocorrect できない」（`[Correctable]` が付かない）として報告する
- HTML の両端の空白は無視するので、ERB タグをインデントや改行ごと削除する修正（`else` + `if` → `elsif` など）は通る
- `Herb/` で始まる rubocop-herb の cop は、ERB を直接書き換えるので検査しない
- 検査は cop ごとの修正に対して行う。RuboCop が複数の cop の修正を 1 つにまとめた結果は検査しない（下記「未解決の問題」）
- ERB タグの中身は比べていないので、HTML と出力タグの数とパースエラーが変わらなければ、2 つのタグを 1 つにつなげる修正も通る（`<%= b %><% %>` の間の `%><%` を `Layout/SpaceBeforeSemicolon` が消して `<%= b  %>` にする、など）

ERB では `--disable-uncorrectable` も無効にします（挿入される `# rubocop:todo` コメントがテンプレートを壊すため）。

### 除外している cop と、行単位で無効にしている cop

`lib/rubocop/herb/configuration.rb` で、次の 9 個の cop を `**/*.html.erb` から除外しています。

`Layout/CommentIndentation`, `Layout/ExtraSpacing`, `Layout/IndentationConsistency`, `Layout/InitialIndentation`, `Layout/LeadingEmptyLines`, `Layout/TrailingEmptyLines`, `Metrics/BlockLength`, `Style/FrozenStringLiteralComment`, `Style/Semicolon`

rubocop-erb は 0.7 系が 53 個、0.8 系が 65 個（[rubocop-erb-0.8.md](rubocop-erb-0.8.md#除外している-cop)）、ruumba の推奨設定は 5 個です。`Lint/Syntax`、`Lint/UselessAssignment`、`Lint/Void` は除外していません。

さらに、ERB の構造を見て、誤検知になる行でだけ cop を無効にしています（`<%# rubocop:disable %>` と同じ仕組み）。対象は 31 個です。

| cop | 無効にする場所 | 実装 |
|---|---|---|
| `Lint/EmptyConditionalBody`, `Style/EmptyElse`, `Lint/EmptyWhen`, `Lint/EmptyInPattern`, `Lint/EmptyBlock`, `Lint/SuppressedException`, `Lint/EmptyEnsure` | 本文に HTML を含む分岐・ブロック | `DisabledCopsCollector` |
| `Lint/DuplicateBranch` | Ruby に現れない HTML だけが異なる分岐 | `DisabledCopsCollector` |
| `Style/ConditionalAssignment` | `case` / `case in`（どの分岐の出力も `_ =` になるため）、ERB タグに跨がる条件分岐 | `DisabledCopsCollector` |
| `Style/IfUnlessModifier`, `Style/IfWithSemicolon`, `Style/RedundantCondition`, `Style/Next` | ERB タグに跨がる条件分岐 | `DisabledCopsCollector` |
| `Style/OneLineConditional` | 1 行に書いた、ERB タグに跨がる条件分岐 | `DisabledCopsCollector` |
| `Style/BlockDelimiters`, `Style/SingleLineDoEndBlock` | 1 行に書いた、ERB タグに跨がるブロック | `DisabledCopsCollector` |
| `Style/WhenThen`, `Style/InPatternThen` | ERB タグに跨がる `when` / `in` | `DisabledCopsCollector` |
| `Lint/ElseLayout` | `<% else %>` と同じ行に続く出力タグ | `DisabledCopsCollector` |
| `Layout/EndAlignment`, `Layout/BlockAlignment`, `Layout/BlockEndNewline`, `Layout/BeginEndAlignment` | ERB タグに跨がる分岐・ループ・ブロック・`begin` の `<% end %>` | `DisabledCopsCollector` |
| `Layout/ElseAlignment`, `Layout/CaseIndentation`, `Layout/RescueEnsureAlignment` | ERB タグに跨がる `else` / `elsif`、`when` / `in`、`rescue` / `ensure` | `DisabledCopsCollector` |
| `Layout/IndentationWidth` | 複数の ERB タグに跨がる本文の、最初の内容から最初の ERB タグまで | `DisabledCopsCollector` |
| `Layout/SpaceAroundOperators` | `<%=` の直後に空白がない出力タグ（`<%=foo%>` が `_ =foo;` になる） | `DisabledCopsCollector` |
| `Layout/TrailingWhitespace` | 変換で空白になった ERB の区切りや HTML による行末の空白（利用者が書いた行末の空白は検出する） | `TrailingWhitespaceCollector` |
| `Layout/LineLength` | ERB タグを含まない行（HTML の行の長さは herb-format に任せる） | `LineLengthCollector` |
| `Style/IdenticalConditionalBranches` | HTML と隣り合っていて分岐の外に移せない式、条件分岐の最初と最後の行 | `ImmovableExpressionCollector` |

1 つの ERB タグの中に書いた Ruby は、これらの cop でも検査されます。本当に空の `else` や、入れ子の空の `if` も検出されることを確認しました【実測】。

### Herb/Linting cop

`Herb/Linting`（`lib/rubocop/cop/herb/linting.rb`）は、herb-lint を Node.js のプロセスで実行し、その結果を RuboCop の offense として報告します。

- 既定で有効。`@herb-tools/linter` が入っていなければ、セットアップを促すエラーを 1 回だけ報告する（README に記載。【実測】）
- Node.js のプロセスは RuboCop のプロセスごとに 1 つ起動し、全ファイルで使い回す
- herb-lint の autocorrect には対応していない（README に記載）
- herb-lint の `erb-no-empty-tags` は報告しない。同じ内容を `Herb/EmptyErbTag` cop が報告し、autocorrect する（README に記載）

`repro/herb/app` の再現例に閉じタグ漏れの例と `repro/rubocop-herb` の例を加え、herb-lint 単体（`npx herb-lint`）の結果と比べました（`@herb-tools/linter` 0.11.0、node v26.9.0）【実測】。

| ERB | herb-lint 単体 | `Herb/Linting` |
|---|---|---|
| `<div><span></div>` | `parser-no-errors`（`MISSING_CLOSING_TAG_ERROR`） | 同じ。`E: Herb/Linting: [parser-no-errors] Opening tag <span> at (1:6) doesn't have a matching closing tag </span> in the same scope. (MISSING_CLOSING_TAG_ERROR)` |
| `cross_tag_variables.html.erb`（本当に未使用の `unused`） | `erb-no-unused-local-variable` | 同じ。RuboCop の `Lint/UselessAssignment` と同じ位置に並ぶ |
| `empty_tag_after_output_tag.html.erb`（空の `<% %>` が 2 つ） | `erb-no-empty-tags` が 2 件 | 出ない。`Herb/EmptyErbTag` が 2 件出る |
| `missing_end.html.erb`（`end` の抜け） | `parser-no-errors` が 3 件（`RUBY_PARSE_ERROR` ×2、`MISSING_ERB_END_TAG_ERROR`） | 出ない（Ruby の構文エラーがあるファイルでは herb-lint を実行しない。README に記載）。RuboCop の `Lint/Syntax` は出る |
| `ruby_style.html.erb` | 出ない | 出ない（RuboCop の Layout / Style は出る） |

- 6 ファイルで `rubocop` 全体の実行時間は約 2 秒（Node.js の起動を含む）
- `@herb-tools/linter` と `.herb.yml` は、RuboCop のプロジェクトのルート（`RuboCop::ConfigFinder.project_root`。カレントディレクトリから上へたどって最初に見つかった `Gemfile` / `gems.rb` のディレクトリ。なければカレントディレクトリ）から読み込む【出典: `lib/rubocop/cop/herb/linting.rb`】
- そのため、`Gemfile` と `package.json` が別のディレクトリにあると使えない。`repro/herb/node_modules` に入れて `repro/herb` で実行すると、`repro/Gemfile` のある `repro` がルートになり、「`@herb-tools/linter is not installed in …/research/repro`」というエラーになった【実測】。上の比較は、`repro/herb` を `Gemfile` のないディレクトリにコピーして実行した
- 設定で読み込み先を変える方法は見当たらない（`Herb/Linting` の設定は `NodeCommand` のみ）【出典】。フロントエンドを別ディレクトリ（`frontend/` など）に分けているプロジェクトでは困る可能性がある【推測】

### Herb/EmptyErbTag cop

`Herb/EmptyErbTag`（`lib/rubocop/cop/herb/empty_erb_tag.rb`。既定で有効）は、空の ERB タグ（`<% %>`）と空の ERB コメント（`<%# %>`）を報告し、autocorrect で消します。

- `CorrectionAdjuster` は、`Lint/Void` などがタグの Ruby をまるごと消すときも区切りを残すので、空のタグが残る。この cop がそれを消し、通常の Ruby ファイルで文が消えるのと同じ結果にする
- タグが行に 1 つだけ（または空のタグだけ）なら行ごと消す。行末のタグなら、前の空白も消す。`<%-` / `-%>` で取り除かれる空白も一緒に消す
- 出力タグ（`<%= %>`）と `<%% %>` は対象外

### Herb/IgnoredCopDirective cop

- ERB のコメントは、右側に別のタグや HTML がない場合だけ Ruby のコメントになる。そのため `<%# rubocop:disable Lint/Void %><%= user.name %>` のような行では、`rubocop:disable` が効かない
- `Herb/IgnoredCopDirective`（既定で有効）は、このように黙って無視される rubocop のディレクティブを報告する（`<% x # rubocop:disable … %><%= y %>` のようなタグ末尾のコメントも対象）
- autocorrect はしない（改行を入れると出力される空白が変わるため。README に記載）

## 既存ツールの問題に対する結果【実測】

research の再現例（`repro/erb_lint`, `repro/rubocop-erb`, `repro/ruumba`, `repro/herb/app`）にかけた結果です。

| ERB | 既存ツールの結果 | rubocop-herb |
|---|---|---|
| `<% if foo == nil %>…<% end %>` | erb_lint / rubocop-erb: 見逃す | `Style/NilComparison` を検出し、`foo.nil?` に修正 |
| `<% if !user.nil? %>…<% end %>` | erb_lint / rubocop-erb: 見逃す | `Style/NegatedIf` を検出し、`unless user.nil?` に修正 |
| `then` / `elsif bar == nil` / `unless !x` | erb_lint: 見逃す | `Style/MultilineIfThen`, `Style/NilComparison`, `Style/NegatedUnless` を検出し、正しく修正 |
| 本当に空の `<% else %>` / `<% unless !x %><% end %>` | erb_lint: 見逃す | `Style/EmptyElse`, `Lint/EmptyConditionalBody` を検出し、`<% else %>` を削除 |
| `<% items.each do \|i\| %>`（`i` 未使用、本文は HTML だけ） | erb_lint: 見逃す | `Lint/UnusedBlockArgument` を検出し、`_i` に修正 |
| `<% name = "Alice" %>` + `<%= name %>` | erb_lint: `Lint/UselessAssignment`（誤検知） | 出ない |
| 本当に未使用の `<% unused = 1 %>` | Herb: 検出する | `Lint/UselessAssignment` を検出する。`-a` で `Lint/UselessAssignment`、`Lint/Void`、`Herb/EmptyErbTag` が順に修正し、行ごと消える |
| `<% count = items.size %>` + `<%= count -1 %>` | rubocop-erb: `count(-1)` に書き換える | ローカル変数と認識し、`Layout/SpaceAroundOperators` で `count - 1` に修正 |
| `<% items.each do \|item\| %>` + `<%= item *2 %>` | rubocop-erb: `item(2)` に書き換える | `item * 2` に修正 |
| `<% if user && user.admin? %>` | rubocop-erb: `user&&.admin?`（構文エラー） | `user&.admin?` に正しく修正（`-A`） |
| `<% end.join(", ") %>`、`<% result = if foo %>` | rubocop-erb: 黙って無視する | 解析でき、`", "` は `', '` に正しく修正される。使われていない `result` には `Lint/UselessAssignment` が出て、`-A` で代入が消える |
| `<p><%= name %>: <%= count -1 %></p>` | ruumba: `name` に `Lint/Void` | 出ない |
| `<% items.each do \|item\| %>` + `<%= item.name %>` | ruumba: `Style/SymbolProc`（誤った提案） | 出ない |
| 本文が HTML だけの `if` | ruumba: `Lint/EmptyConditionalBody` | 出ない |
| `<%= a %><%= b %>` | ruumba: 補った `;` に `Style/Semicolon` | 出ない（cop を除外） |
| `Layout/TrailingWhitespace`, `Layout/InitialIndentation` など | ruumba: 17 ファイルで 71 件 | 出ない |
| `Style/FrozenStringLiteralComment` | erb_lint: タグごとに出る | 出ない（cop を除外） |
| `<%= link_to "x", path, class: 'btn' %>` の autocorrect | erb_lint: `<%=` が消え、マジックコメントが入る | `'x'` だけが修正される |
| `<%`⏎`  x = 1`⏎`  y = 2`⏎`%>` の autocorrect | erb_lint: `<%` が消える | 変更なし |
| `<%== raw_html %>` | ruumba: `<%= raw raw_html %>` に書き換える | 変更なし |
| `end` の抜け | Herb: 検出する / rubocop-erb: `Lint/Syntax` を除外 | `Lint/Syntax` を検出する |
| `<%= link_to( 'Home',root_path ) %>` | Herb: 検出しない | `Layout/SpaceInsideParens`, `Layout/SpaceAfterComma` を検出し、修正 |

このほか、次のケースも位置がずれずに修正できることを確認しました。

- 日本語を含む行（`<p>こんにちは</p><%= link_to( "ホーム",root_path ) %>`）
- `<%-` / `-%>` を使ったタグ
- 属性値の中のタグ（`<div class="<%= active ? "on" : "off" %>">`）
- `<%= form_with … do |f| %>…<% end %>`（変更なし）

### ガードが捨てた修正【実測】

次の修正は、offense は報告されるが適用されません（`[Correctable]` が付かない）。

| ERB | cop | そのまま適用した場合の結果 |
|---|---|---|
| `<% unless a %>`…`<% else %>`…`<% end %>`（本文に HTML） | `Style/UnlessElse` | 分岐を入れ替えた結果、`<% if a ;`⏎`  <p>y</p>`⏎`   else`…`end %>` のように HTML が 1 つの ERB タグの中に入る |
| `<% if !a %>`…`<% else %>`…`<% end %>`（本文に HTML） | `Style/NegatedIfElseCondition` | 同上 |
| `<% else %>` の中が `<% if b %>…<% end %>` だけ | `Style/IfInsideElse` | `<% elsif b %>` にした結果、内側の本文が `<% <p>z</p> %>` になる |
| `<% if a %>`⏎`  <%= foo %>`⏎`<% else %>`⏎`  <%= foo %>`⏎`<% end %>` | `Style/IdenticalConditionalBranches`（`-A`） | 両方の分岐の `<%= foo %>` が消え、`<% end`⏎`   _ = foo %>` になる（`foo` が出力されなくなる） |

- `Style/UnlessElse` と `Style/NegatedIfElseCondition` は、HTML の並びが変わり、Herb のパースエラーも増えるので捨てられる（検査の途中経過を出力して確認）
- `Style/IfInsideElse` は、`CorrectionAdjuster` が切り詰めた結果、何も変えない修正になる
- `Style/IdenticalConditionalBranches` は、HTML とパースエラーは変わらないが、出力タグが 2 つから 1 つに減るので捨てられる

`Lint/Void` は、`CorrectionAdjuster` が切り詰めるので適用されます。`<p>a</p>`⏎`<% 1 %>`⏎`<%= b %>` は `-a` で `<% %>` になり、`Herb/EmptyErbTag` が行ごと消します。`<% 1; foo %>` は `<%; foo %>` になります（出力は変わらない）。

## 未解決の問題【実測】

詳しい再現手順は、upstream に報告する再現レポート（[rubocop-herb-issues/](rubocop-herb-issues/)）にまとめています。

| 問題 | 影響 | 条件 |
|---|---|---|
| 出力タグの直後の空のタグを消すと、出力タグの `%>` も消える: `<% %>`⏎`<%= b %><% %>` が `-a` で `<%= b ` になる（[再現レポート](rubocop-herb-issues/empty-tag-after-output-tag-breaks-template.md)） | **`-a` でテンプレートが壊れる**（閉じていない ERB タグになり、Herb のパースエラーが増える） | 出力タグの直後に空の `<% %>` があり、前の行にも空のタグがある場合（確かめた例）。`Layout/SpaceBeforeSemicolon` と `Herb/EmptyErbTag` の修正が重なる |
| HTML を含むテンプレートで、パースし直して確かめる cop の指摘・修正が消える: `<div>` の中の `<%= link_to root_path() %>` に `Style/MethodCallWithoutArgsParentheses` が出ない（[再現レポート](rubocop-herb-issues/reparse-cops-skip-html-files.md)） | 見逃し。`Style/MethodCallWithoutArgsParentheses` と `Style/RedundantParentheses` は出ず、`Style/TernaryParentheses` は出るが修正されない | HTML を 1 つでも含むテンプレート。RuboCop 1.92 で `ReparsedEquivalence` を使う cop |

### `%>` が消える原因【出典・推測】

- `Layout/SpaceBeforeSemicolon` は、`_ = b;    ;` の 2 つ目の `;` の前の空白、つまり元の ERB の `%><%` を消す。HTML、出力タグの数、パースエラーは変わらないので、ガードは通す（2 つのタグが 1 つにつながる）
- `Herb/EmptyErbTag` は、2 つ目のタグ `<% %>` を消す。rubocop-herb の cop なので、ガードは検査しない
- RuboCop は、交差する削除をまとめることを許す（`crossing_deletions: :accept`）ので、2 つの削除が `%><% %>` の削除になり、出力タグの `%>` も消える。ガードは cop ごとの修正しか見ていない
- 空のタグが 1 つ目の行にないとき（`<%= b %><% %>` だけのとき）は、まとめた修正が空のタグの削除だけになり、壊れない。違いが生じる理由は調べていない

2 つのタグの間の `%><%` をまたぐ削除を切り詰めるか捨てる、または RuboCop がまとめた修正をもう一度検査すれば防げる見込みです【推測】。

### 指摘・修正が消える原因【出典】

- RuboCop 1.92 の `Style/MethodCallWithoutArgsParentheses`、`Style/RedundantParentheses`、`Style/TernaryParentheses` などは、修正を当てたコードをパースし直し、AST が元と同じときだけ offense を出す（または修正する）（`ReparsedEquivalence`）
- rubocop-herb は、HTML を含むテンプレートでは、バッファの中身を HTML を戻した hybrid code に置き換え、AST の HTML の識別子の名前を `div__html0` のように書き換える。パースし直す対象が Ruby でなくなり、AST も一致しないので、確認が必ず失敗する
- 両方を無効にすると、3 つの cop の offense が出て `[Correctable]` が付くことを確かめた（診断のためだけの変更）

## 比較表への追加

[existing-erb-linters.md](existing-erb-linters.md#ツール一覧と比較) の比較表に rubocop-herb を加えると、次のようになります。

| ツール | HTML 構造 | Ruby の構文 | Ruby のスタイル (RuboCop) | タグを跨いだ Ruby 解析 | autocorrect | 型・意味解析 |
|---|---|---|---|---|---|---|
| erb_lint (Rubocop linter) | ○ (better_html) | △ (タグ単位。不完全な文はスキップ) | △ (タグ単位) | × | △ (テンプレートを壊す) | × |
| rubocop-erb 0.7 系 | × | △ (タグ単位。Lint/Syntax を除外) | △ (タグ単位。53 cop を除外) | × | △ (意味・構文を壊す) | × |
| rubocop-erb 0.8 系 | × | ○ (文書全体) | △ (文書全体。65 cop を除外) | ○ | ○ (1 つのタグの Ruby に収まらない修正は捨てる) | × |
| ruumba (メンテ停止) | × | ○ (文書全体) | △ (文書全体。出力・HTML 本文が失われ誤検知) | ○ | △ (実験的。黙って書き戻さないことがある) | × |
| **rubocop-herb** | ◎ (Herb/Linting で herb-lint を実行。Node.js が必要) | ○ (文書全体) | ○ (文書全体。9 cop を除外し、31 cop を行単位で無効化。HTML を含むファイルで一部の cop が働かない) | ○ | ○ (テンプレートを壊す修正は捨てる。ただし 2 つの cop の修正が重なって壊れる例が 1 件) | × |

## その他【出典】

- README は Usage（autocorrect、`Layout/LineLength`、`Herb/Linting`、`Herb/IgnoredCopDirective`、`Herb/EmptyErbTag`）が書かれているが、冒頭・Installation・Contributing などは `bundle gem` の雛形のまま
- `CHANGELOG.md` は `## [Unreleased]` のみで、version は未リリース
- gem 名が、rubygems に登録済みの Marco Roth 氏の `rubocop-herb` 0.0.1 と衝突している（[existing-erb-linters.md](existing-erb-linters.md#要フォローアップ) で既出）
- マルチバイト文字を含むテキストや HTML コメントが `hybrid_code` に戻らない issue（[#72](https://github.com/tk0miya/rubocop-herb/issues/72)）が open のまま
