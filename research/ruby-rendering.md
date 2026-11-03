# rubocop-herb が `<%=` と HTML を Ruby として描画する理由

調査日: 2026-11-03

rubocop-erb 0.8 系と herb 公式の rubocop-herb（[marcoroth/herb#2260](https://github.com/marcoroth/herb/pull/2260)、以下「PR 版」）は、`Herb.extract_ruby` で ERB から Ruby を取り出します。tk0miya/rubocop-herb（以下「rubocop-herb」）は、Herb の AST から独自に Ruby を組み立てます。`<%=` を `_ =` に、HTML のタグを `div;` に、テキストを `_a;` にして、ERB の意味を Ruby の上に残します。
この違いが誤検知と、cop の除外による見逃しにどう効くかを比べた結果です。
【実測】は手元で実行して確かめたこと（検証用 ERB と手順は [repro/README.md](repro/README.md)）、【出典】はソースコードで確かめたこと、【推測】は解釈です。

## 対象

- rubocop-erb 0.8.2（herb 0.11.1）
- PR 版: `d0323df360553502e31b14ff570990f907f46b2a`（2026-10-06 時点の PR の head）の `gems/rubocop-herb`（herb 0.11.0）
- rubocop-herb: https://github.com/tk0miya/rubocop-herb の `4d915335e559aa93b7e3ec82adbbe203054e631e`（2026-11-03 時点の main。rubocop 1.92.1 / herb 0.11.1）
- rubocop 1.92.1 / ruby 4.0.5。設定はどれも `NewCops: enable`、`TargetRubyVersion: 3.4`
- 入力
  - 組にしたサンプル（[repro/cases/marker/](repro/cases/marker/) の `*_ok` と `*_ng`、18 ファイル）。cop ごとに、ERB として正しいもの（`*_ok`）と、同じ形で本当に直すべきもの（`*_ng`）を 1 つずつ置いた
  - 実際のビュー: rails/rails `0f591639b8` と kaigionrails/conference-app `25a02cc` の `*.html.erb`（333 ファイル）

## まとめ

- `Herb.extract_ruby` は、ERB タグの中身以外をすべて空白にします。`<%= x %>` と `<% x %>` は同じ Ruby になり、HTML だけを本文に持つブロックと、本当に空のブロックも同じ Ruby になります
- そのため、**ERB として正しいテンプレートと、直すべきテンプレートを RuboCop が区別できません**。組にしたサンプル 9 組で、rubocop-erb 0.8.2 の除外を外すと、9 組すべてで正しい側にも直すべき側にも同じ指摘が出ました
- 区別できない以上、取れる道は 2 つしかありません。両方を報告するか（誤検知）、cop ごと止めるか（見逃し）です
  - PR 版は 48 個の cop を除外し、残りは両方を報告します。サンプルでは 9 組中 7 組で正しい側にも指摘が出て、`-A` でテンプレートが壊れます
  - rubocop-erb 0.8.2 は 65 個の cop を除外します。サンプルでは、直すべき側 9 件のうち 8 件を見逃します。除外しなかった `Style/CombinableLoops` では、正しい側にも指摘が出ます
- rubocop-herb は `<%=` と HTML の存在を Ruby に書き込むので、2 つが別の Ruby になります。サンプルでは、**直すべき側の 9 件をすべて検出し、正しい側には誤検知を出しません**（1 件だけ出る `Style/IdenticalConditionalBranches` は、分岐の外に移せる式への妥当な指摘）。ファイル全体で除外する cop は 10 個です
- 実際のビュー 333 ファイルで、0.8.2 が除外している cop の除外を外すと、内容に関わる cop だけで 131 件出ます。妥当な指摘は 23 件で、残りの 108 件は誤検知でした。0.8.2 はこの 131 件をまとめて捨てています。rubocop-herb は同じ cop で 22 件を報告し、すべて妥当な指摘でした
- autocorrect でも差が出ます。サンプルの正しい側に `-A` をかけると、PR 版は 5 ファイルで HTML や出力タグを消します。rubocop-herb は 1 つも変えません
- 実装の規模は、PR 版が 74 行、0.8.2 が 386 行、rubocop-herb が約 3,000 行です。rubocop-herb はこの差で、cop を止めて誤検知を消すのではなく、誤検知の原因を変換の段階で取り除いています

## 2 つの変換【出典】

ERB は、テキストと `<%=` を `_erbout` への追記という**文**にコンパイルします。

```ruby
# ERB.new('<p>Hello, <%= user.name %></p>').src（先頭の行を除く）
_erbout = +''; _erbout.<< "<p>Hello, ".freeze; _erbout.<<(( user.name ).to_s); _erbout.<< "</p>".freeze; _erbout
```

`Herb.extract_ruby` はこの文を落とし、rubocop-herb は短い文で置き換えます。

```erb
<% if user %>
  Welcome!
  <%= user.name %>
<% end %>
```

`Herb.extract_ruby`（0.8.2、PR 版。行末の空白は省略）:

```ruby
   if user  ;

      user.name  ;
   end  ;
```

rubocop-herb（`bin/erb2ruby`。行末の空白は省略）:

```ruby
   if user;
  _a;
  _ = user.name;
   end;
```

| ERB | ERB のコンパイル結果 | `Herb.extract_ruby` | rubocop-herb |
|---|---|---|---|
| `<%= expr %>` | `_erbout << (expr).to_s` | `expr  ;`（値を捨てる式） | `_ = expr;`（値を使う文） |
| `<% expr %>` | `expr` | `expr  ;` | `expr;` |
| `<div>`、`</div>` | `_erbout << "<div>"` | 空白 | `div;` |
| テキスト、HTML コメント、`<%%` | `_erbout << "text"` | 空白 | `_a;`（置けるときだけ。下記「マーカーの限界」） |

- `_ =` と `_a;` は、ERB のコンパイル結果にある文を、元の文字位置に収まる長さで書いたもの（`lib/rubocop/herb/ruby_renderer.rb`）
- 空白にすると文の数が減ります。`<% if user %>Welcome!<%= user.name %><% end %>` の `if` の本文は、ERB では 2 文、`extract_ruby` では値を捨てる式 1 つ、rubocop-herb では 2 文です

## 空白にすると、正しい ERB と直すべき ERB が同じ Ruby になる【実測】

[repro/cases/marker/](repro/cases/marker/) の 9 組です。`*_ok` は ERB として正しいテンプレート、`*_ng` は同じ形で本当に直すべきテンプレートです。

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

各ツールで、その cop が `*_ok` と `*_ng` のどちらに出たかです（`Layout` と、`Style/FrozenStringLiteralComment`、`Style/Semicolon`、`Style/StringLiterals` を除いて実行した）。

| cop | 0.8.2 | 0.8.2（除外を外す） | PR 版 | rubocop-herb |
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
- PR 版は `Lint/EmptyConditionalBody` と `Style/EmptyElse` を除外し、ほかの 7 組では `*_ok` にも出る
- rubocop-herb は 9 組すべてで `*_ng` だけに出る。このほか、`duplicate_branch_ok` の 2 つの `<%= user.name %>` に `Style/IdenticalConditionalBranches` が出る。どちらの分岐も最後が同じ出力タグなので、分岐の後ろに 1 つにまとめられる。妥当な指摘で、autocorrect はされない
- RuboCop ではない herb-lint（`bin/lint herb-lint cases/marker`）は、HTML を空白にせずに ERB の構造を見るので、ルールのある組では `*_ng` だけに出る。`erb-no-empty-control-flow` が空のブロック・`if`・`else` の 3 組、`erb-no-unused-expressions` が `<% count + 1 %>` と `<% item.touch %>`、`erb-no-duplicate-branch-elements` が同じ内容の分岐に出る。ただし `erb-no-unused-expressions` は、値を使わない `<% user.touch %>` を `safe_navigation_ok` でも指摘する
- 0.8.2 の除外を外したときは、このほかに `Style/IfWithSemicolon`（`if user;` を三項演算子にせよ）と `Style/IfUnlessModifier` も `*_ok` と `*_ng` の両方に出る。どちらも、タグの終わりに補った `;` や、空白にした本文から生じる

### `-A` の結果（`*_ok`）

`*_ok` のコピーに `-A` をかけた結果です（`Style/StringLiterals` の修正は省略）。

| ファイル | PR 版 | rubocop-herb |
|---|---|---|
| `void.html.erb` | `<% count = items.size%>%> items</p>`（`<p><%= count + 1` が消える） | 変わらない |
| `symbol_proc.html.erb` | `<% items.each(&:name)%>`（`<li>` が消える） | 変わらない |
| `safe_navigation.html.erb` | `<% user&.touch%>`（`Last login:` が消える） | 変わらない |
| `sole_nested_conditional.html.erb` | `<% if user`（以降がすべて消える） | 変わらない |
| `combinable_loops.html.erb` | 2 つのループが `<% items.each(&:name)%>` と `<% items.each(&:price)%>` になる（出力がなくなる） | 変わらない |

- 0.8.2 は、除外を外しても、内容の修正は修正範囲の検査（1 つのタグの中に収まるか）で捨てる。`-A` で変わるのは、`%>` の前の空白などの `Layout` の修正と `Style/StringLiterals` の修正だけだった
- PR 版の詳細は [herb-rubocop-herb.md](herb-rubocop-herb.md#autocorrect-の結果実測)

## 除外で何が消えているか（実際のビュー）【実測】

実際のビュー 333 ファイルに、0.8.2 が `**/*.erb` から除外している 65 個の cop のうち 64 個（`Rails/Presence` は rubocop-rails を入れていないので除く）だけをかけました。0.8.2 は除外を外した設定（[repro/tools/rubocop-erb-0.8/erb-noexclude.yml](repro/tools/rubocop-erb-0.8/erb-noexclude.yml)。`bin/lint rubocop-erb-0.8-noexclude`）で実行しています。

内容に関わる cop の結果です。妥当かどうかは、1 件ずつテンプレートを見て判断しました。

| cop | 0.8.2（除外を外す） | うち妥当 | rubocop-herb | 0.8.2 の誤検知の内容 |
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

- rubocop-herb の 22 件は、どれも 0.8.2 が除外で捨てている妥当な指摘
  - `Style/SymbolProc`: `<%= local_assigns.keys.map {|k| k.to_s }.sort.join(",") -%>`
  - `Style/SafeNavigation`: `<% if @part && @part.mime_type %>`
  - `Style/RescueModifier`: `corrections = exception_wrapper.corrections rescue []`
  - `Lint/EmptyBlock`: `<%= check_box_tag "save_and_assign", …, class: "w-4 h-4 rounded-sm" do %>`⏎`<% end %>` など
  - `Style/IfUnlessModifier`: HTML を含めて 121 桁の行（[herb-rubocop-herb.md](herb-rubocop-herb.md#実際のビューでの結果実測)）
- `Style/SafeNavigation` の妥当な 2 件のうち、`<%= @request.parameters["controller"].camelize if @request.parameters["controller"] %>` は rubocop-herb では出ない（下記「マーカーの限界」）
- 内容に関わらない cop では、0.8.2 の除外を外すと、`Style/Semicolon` が 1,554 件、`Style/FrozenStringLiteralComment` が 254 件、`Style/IfWithSemicolon` が 62 件、`Layout` の 15 個の cop が計 7,308 件出る。どれも、タグの終わりに補った `;` や、空白にした HTML と ERB の区切りから生じる。rubocop-herb は、このうち `Style/Semicolon`、`Style/FrozenStringLiteralComment` と `Layout` の 6 個を除外し、残りの多くは誤検知になる行だけで無効にしている。`Layout/LineLength`（162 件）と `Layout/HashAlignment`（3 件）は rubocop-herb でも出る（[report.md](report.md#除外している-cop-と行単位で無効にしている-cop)）

## 実装の規模【出典】

| | Ruby の取り出し | 誤検知への対策 | 規模（`lib/`） |
|---|---|---|---|
| PR 版 | `Herb.extract_ruby` | 48 個の cop をファイル全体で除外 | 74 行（`plugin.rb`） |
| 0.8.2 | `Herb.extract_ruby` | 65 個の cop をファイル全体で除外 | 386 行 |
| rubocop-herb | 独自（`RubyRenderer`、312 行） | 10 個の cop をファイル全体で除外し、ほかは ERB の構造を見て誤検知になる行だけで無効にする | 3,004 行 |

- rubocop-herb がファイル全体で除外する 10 個は、`Layout/CommentIndentation`、`Layout/ExtraSpacing`、`Layout/IndentationConsistency`、`Layout/InitialIndentation`、`Layout/LeadingEmptyLines`、`Layout/TrailingEmptyLines`、`Metrics/BlockLength`、`Naming/FileName`、`Style/FrozenStringLiteralComment`、`Style/Semicolon`（`lib/rubocop/herb/configuration.rb`）。どれも、ERB のファイルとしての性質（どの位置からでも書き始められる、マジックコメントを置かない、ファイル名にロケールが入るなど）から ERB に合わない cop で、マーカーでは解決しない
- 行単位の無効化（`lib/rubocop/herb/erb_parser/` と `*_collector.rb`、計 870 行）は、ERB タグに跨がる `if` や `<% end %>` の位置合わせなど、Ruby として書けない ERB の構造を扱う。HTML を本文に持つ分岐やブロックを空とみなす cop の無効化は、主にマーカーを置けない短いテキストのためにある（下記）
- `CopCorrectionGuard` まわり（`CopCorrectionGuard`、`CorrectionAdjuster`、`CorrectionValidator`、計約 300 行）は、修正後の ERB の HTML、出力タグの数、パースエラーを検査する。誤検知そのものが出なければ、誤った修正も提案されないので、この検査は変換で防げない壊れ方に備えるものになる

## マーカーの限界【実測・出典】

- **短いテキストにはマーカーを置けない**。`_a;` は、テキストの中に 3 文字と後ろの空白か改行、または 2 文字と改行がないと置けない（`TEXT_MARKER_POSITION`）。`|` 1 文字などは空白のままになり、空白にする方式と同じ誤検知が起きる。[repro/cases/marker/safe_navigation_short.html.erb](repro/cases/marker/safe_navigation_short.html.erb)（`<% if user %>` の本文が `|<% user.touch %>`）には、rubocop-herb でも `Style/SafeNavigation` が出る。行単位の無効化は、`Lint/EmptyBlock` などについてこの穴を塞いでいるが、`Style/SafeNavigation` などは塞いでいない
- **`_ =` が隠す指摘がある**。`<%= x.camelize if x %>` は `_ = x.camelize if x` になり、`Style/SafeNavigation` の対象にならない。実際のビューでは 1 件あり、0.8.2 の除外を外すと出る
- **メッセージに `_ =` が出る**。`Style/IdenticalConditionalBranches` は「Move `_ = user.name` out of the conditional.」と報告する

## 評価【推測】

- `Herb.extract_ruby` で生じる誤検知は、cop の側の問題ではなく、変換で ERB の意味（出力する、HTML がある）を落としたことの帰結です。落とした情報は cop からは取り戻せないので、ERB として正しいものと直すべきものは原理的に区別できません。除外は「誤検知を消す」ことではなく、「その cop が見つけるはずの問題ごと捨てる」ことになります
- 実際のビューでは、0.8.2 の除外が捨てている内容の指摘 131 件のうち、妥当な指摘は 23 件でした。誤検知が 8 割を超える cop を除外するのは、空白にする方式では合理的な判断です。ただしその判断は、`<% count + 1 %>`（`=` の書き忘れ）や本当に空の `else` も見逃すことと引き換えです
- rubocop-herb は、ERB のコンパイル結果にある文を `_ =` と `_a;` で残し、Ruby の上で ERB と同じ文の数と値の使われ方を再現しています。誤検知の原因が変換の段階で消えるので、cop を除外せずに済み、妥当な指摘が残ります。autocorrect も、ERB の構造を変える修正が提案されなくなります
- 実装の規模は、PR 版の約 40 倍、0.8.2 の約 8 倍です。それでも、除外で済ませる方式では、除外の一覧が「ERB で誤検知になる cop」をすべて把握している必要があり、RuboCop に cop が増えるたびに追いかけることになります。`NewCops: enable` の利用者には、除外の一覧に入る前の新しい cop の誤検知がそのまま届きます。変換で意味を残す方式は、未知の cop にも同じ Ruby を見せるので、この追いかけっこが小さくなります
- マーカーは万能ではありません。短いテキストの穴と、`_ =` が隠す指摘があり、それぞれ行単位の無効化と見逃しとして残っています

### 発表で使えそうな材料

- 「同じ Ruby になる 2 つの ERB」: `<p><%= count + 1 %> items</p>` と `<p><% count + 1 %> items</p>` は、`extract_ruby` ではどちらも `count + 1  ;`。0.8.2 はどちらにも何も言わず、PR 版はどちらにも `Lint/Void` を出し、rubocop-herb は後者だけを指摘する
- 「除外で捨てているもの」: 実際のビューで、0.8.2 が除外している内容の指摘 131 件のうち、妥当な指摘が 23 件。rubocop-herb は誤検知を出さずに、そのうち 22 件を報告する
- 「誤検知は壊れる autocorrect になる」: PR 版の `-A` で、`Last login: <% user.touch %>` が `<% user&.touch%>` に、`<li><%= item.name %></li>` のループが `<% items.each(&:name)%>` になる。rubocop-herb では誤検知が出ないので、修正も提案されない
