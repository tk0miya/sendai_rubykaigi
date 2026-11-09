# 第 3 部 ERB に合わない RuboCop の cop

ERB の中の Ruby を RuboCop で検査すると、Ruby のファイルでは妥当な cop が、ERB では誤検知になったり、ERB に合わない書き方を勧めたりします。
この部では、ERB と RuboCop の cop の関係を、cop が ERB に合わない理由で整理します。どのツールで検査するかには依りません。
対象の版と凡例は [README.md](README.md) にあります。

## 目次

1. [概要](#1-概要)
2. [ERB がコンパイルされる Ruby](#2-erb-がコンパイルされる-ruby実測)
3. [4 つの分類](#3-4-つの分類)
4. [区切りへの指摘](#4-区切りへの指摘)
5. [HTML が見えないことによる指摘](#5-html-が見えないことによる指摘)
6. [ERB の書き方に合わない指摘](#6-erb-の書き方に合わない指摘)
7. [配置への指摘](#7-配置への指摘)
8. [理想の姿](#8-理想の姿推測)
9. [今後の検討事項](#9-今後の検討事項)

## 1. 概要

- ERB は Ruby にコンパイルされる。タグの区切りは `;` か改行に、HTML とテキストは出力の文になる。RuboCop で ERB を検査するときは、この Ruby を元の文字位置に合わせて書いたものを cop に見せる
- 対象の cop は、tk0miya-rubocop-herb が ERB で止めている 51 個（[第 2 部 5 章](tk0miya-rubocop-herb.md#5-erb-で止めている-cop出典)）。ERB に合わない理由で 4 つに分ける
  - 区切りへの指摘: 書き手が書いていない `;` や空白に反応する
  - HTML が見えないことによる指摘: HTML の本文を空と見る
  - ERB の書き方に合わない指摘: Ruby の規範で、ERB の書き方を直させる
  - 配置への指摘: Ruby の位置が、開始タグの幅（`<%` と `<%=`）や HTML の構造で決まる
- ERB の例を、cop が勧めるとおりに書き換えて ActionView で描画し、出力が変わるかを確かめた。ERB の書き方に合わない指摘は、従うと出力が変わるもの（`Style/SingleLineDoEndBlock` など）と、変わらないスタイルの選択（`Style/IfUnlessModifier` など）に分かれる【実測】
- 検証のスクリプトは [repro/semantics/](repro/semantics/)。ERB の描画とコンパイルは actionview 8.1.4.1、cop は rubocop 1.92.1 で確かめた

## 2. ERB がコンパイルされる Ruby【実測】

ActionView（Erubi）は、ERB を次の Ruby にコンパイルします（`ActionView::Template::Handlers::ERB::Erubi.new(erb).src`。末尾の `@output_buffer` を除く）。

| ERB | コンパイルされた Ruby |
|---|---|
| `<%= a %><%= b %>` | ` @output_buffer.append=( a ); @output_buffer.append=( b );` |
| `<% if active %>on<% else %>off<% end %>` | ` if active ; @output_buffer.safe_append='on'.freeze; else ; @output_buffer.safe_append='off'.freeze; end ;` |
| `<% if a %>`⏎`  <p>x</p>`⏎`<% end %>` | ` if a `⏎` @output_buffer.safe_append='  <p>x</p>`⏎`'.freeze; end `⏎ |

- タグの区切りは、同じ行に続くときは `;` に、行末では改行になる。`;` は書き手が書いたものではなく、ERB のコンパイラが入れる
- HTML とテキストは、出力の文（`@output_buffer.safe_append=…`）になる。HTML だけの本文も、Ruby では空ではない
- `<%=` は、式の値を出力する文になる

RuboCop で ERB を検査するときは、この Ruby をそのまま使わず、元の ERB と文字位置が揃った Ruby を作ります。offense の位置をそのまま ERB に当てるためです。タグの中のコードを元の位置に書き、区切りの位置には `;` や空白を書きます。HTML は、空白にするか、識別子（tk0miya-rubocop-herb の `div;` など）にします（[第 1 部 1 章](comparison.md#1-erb-から-ruby-を取り出す-2-つの方式)）。

## 3. 4 つの分類

| 分類 | ERB との関係 | cop の数 | 理想の姿【推測】 |
|---|---|---|---|
| [区切りへの指摘](#4-区切りへの指摘) | 書き手が書いていない `;` や空白に反応する | 9 | 区切りへの指摘だけを捨て、タグの中のコードは検査する |
| [HTML が見えないことによる指摘](#5-html-が見えないことによる指摘) | HTML の本文を空と見る | 10 | HTML の存在を Ruby に残し、cop を止めない |
| [ERB の書き方に合わない指摘](#6-erb-の書き方に合わない指摘) | Ruby の規範で、ERB の書き方を直させる | 14 | 出力が変わる書き換えは勧めない。スタイルの選択は選べるようにする |
| [配置への指摘](#7-配置への指摘) | Ruby の位置が、開始タグの幅や HTML の構造で決まる | 19 | 開始タグの幅によるずれは捨てる。HTML の構造に従う配置は ERB のツールに任せる |

`Style/ConditionalAssignment` は、`case` では区切りへの指摘、タグに跨がる `if` では ERB の書き方に合わない指摘なので、両方に数えました（51 個で、のべ 52）。

## 4. 区切りへの指摘

ERB の区切りの位置に書いた `;` や空白に、cop が反応します。どれも ERB のソースには書かれていない文字です（2 章）【実測】。

| cop | 反応するもの |
|---|---|
| `Style/Semicolon` | 区切りの位置の `;` |
| `Style/IfWithSemicolon` | `<% if a %>` の区切りの `;`（`if a;`） |
| `Style/WhenThen`, `Style/InPatternThen` | `<% when 1 %>`、`<% in 1 %>` の区切りの `;`（`when 1;`、`in 1;`） |
| `Style/ConditionalAssignment` | `case` のどの分岐の出力も `_ =` になる（tk0miya-rubocop-herb は `<%=` を `_ =` にする） |
| `Layout/SpaceAroundOperators` | `<%=foo%>` から作った `_ =foo` |
| `Layout/ExtraSpacing` | 区切りの位置の空白 |
| `Layout/TrailingWhitespace` | 行末の区切りや HTML の位置の空白 |
| `Layout/EmptyComment` | 複数行の ERB コメントの 1 行目が、空のコメントになる |

- ERB のコンパイラは、同じ行に続くタグを `;` で、行末のタグを改行で区切る（2 章）。区切りの位置にいつも `;` を書くと、複数行に書いた `<% if a %>`〜`<% end %>` も `if a;`⏎`  x`⏎`end` になり、`Style/IfWithSemicolon` が「三項演算子にせよ」と報告する（[repro/semantics/ruby/if_semicolon.rb](repro/semantics/ruby/if_semicolon.rb)）【実測】
- どの cop も、書き手がタグの中に書いたコードでは本来の問題を見つける。実際のビューにも、タグの中に書いた余分な空白（rails の fixture の `<%= render    partial:  "form" %>`、conference-app の `<%=  @live_streams[:day1][:red_ja] %>`）がある【実測】。cop ごと止めると、これらも見逃す

## 5. HTML が見えないことによる指摘

ERB では、HTML だけの本文も出力の文になり、空ではありません（2 章）。HTML を空白にすると、Ruby の上では本文が空に見えます。

| cop | ERB | HTML を空白にした Ruby で出る指摘 |
|---|---|---|
| `Lint/EmptyConditionalBody` | `<% if a %>`⏎`<p>x</p>`⏎`<% end %>` | `if` の本文が空 |
| `Style/EmptyElse` | `<% else %>` の本文が HTML だけ | 冗長な `else` |
| `Lint/EmptyWhen`, `Lint/EmptyInPattern` | `<% when 1 %>` の本文が HTML だけ | `when` の本文が空 |
| `Lint/EmptyBlock`, `Lint/SuppressedException`, `Lint/EmptyEnsure` | ブロックや `rescue`、`ensure` の本文が HTML だけ | 本文が空 |
| `Lint/DuplicateBranch` | `<% if a %><p>A</p><%= x %><% else %><p>B</p><%= x %><% end %>` | HTML だけが異なる分岐を、同じと見る |
| `Style/RedundantCondition` | `<% if x %>#<%= x %><% end %>` | `#` が空白になり、`x` だけを返す冗長な条件に見える |
| `Style/IdenticalConditionalBranches` | 分岐の最後の出力タグの後ろに HTML がある | HTML の前の出力を、分岐の外に移せると見る |

- `Lint/EmptyConditionalBody`、`Style/EmptyElse`、`Lint/EmptyWhen`、`Lint/DuplicateBranch`、`Style/RedundantCondition` は、HTML を空白にした Ruby では出て、HTML を出力の文（`_erbout << "<p>x</p>"`）として残した Ruby では出ない（[repro/semantics/ruby/](repro/semantics/ruby/)）【実測】
- この分類の cop は、ERB でも本来検出したい問題（本当に空の `else`、`=` を書き忘れた `<% count + 1 %>` など）を見つける。HTML の存在を Ruby に残せば、cop を止めずに済む
- tk0miya-rubocop-herb は HTML を識別子として書き込むが、識別子を置けない短いテキスト（`|` 1 文字など）は空白のままなので、この分類の cop を本文が HTML の分岐でだけ止めている（[第 2 部 3.3 節](tk0miya-rubocop-herb.md#33-マーカーの限界実測出典)）

## 6. ERB の書き方に合わない指摘

ERB では HTML の中に制御構造を埋め込むので、Ruby とは違う書き方が自然になります。表の ERB には、それぞれの cop が出ます（タグをまたぐ構造を Ruby にした形で確かめた。`Style/Next` と `Style/ConditionalAssignment` は [repro/semantics/ruby/](repro/semantics/ruby/) の `next.rb`、`cond_assign.rb`）。cop が勧めるとおりに ERB を書き換え、ActionView で描画して出力を比べました（[repro/semantics/render.rb](repro/semantics/render.rb)）【実測】。

### 6.1 従うと出力が変わるもの

| cop | ERB | 勧めるとおりに書き換えた ERB | 出力 |
|---|---|---|---|
| `Style/SingleLineDoEndBlock` | `<% content_for(:title) do %>Hello <%= b %><% end %>` | `do %>`⏎`  Hello <%= b %>`⏎`<% end %>` | `content_for(:title)` が `"Hello B"` から `"  Hello B\n"` に変わる |
| 同上 | `Click<%= link_to(path) do %>here<% end %>.` | 同上の形 | リンクの文字列の前後に改行と空白が入る（`<a href="/users/1">\n  here\n</a>`） |
| 同上 | `<div class="<% items.each do \|i\| %>c<%= i %> <% end %>">` | 同上の形 | `class` の値に改行と空白が入る |
| 同上 | `.text.erb` の `Items: <% items.each do \|i\| %><%= i %>,<% end %>` | 同上の形 | `Items: 1,2,3,` が 7 行になる |
| `Lint/ElseLayout` | `<% if a %>x<% else %><%= b %><% end %>` | `<% else %>` の後ろで改行 | 出力の先頭に改行が入る（`"B"` が `"\nB"`） |

- `Style/SingleLineDoEndBlock` が出るのは、タグに跨がるブロックを 1 行に書いたとき。実際のビュー 333 ファイルでは、タグに跨がるブロック 188 個のうち 10 個が 1 行に書かれている（[repro/semantics/count_structures.rb](repro/semantics/count_structures.rb)）【実測】
- 1 行の書き方は、空白を出力に入れないための書き方でもある。空白が意味を持つかどうかは、HTML の文脈と、ブロックの値の使い方で決まる
- 複数行への整形は herb-format の役割になる。herb-format 0.11.1 は、本文のブロックを行の長さに関係なく `do %>`⏎`  Profile of <%= user.name %>`⏎`<% end %>` に整形する。属性の値の中のブロックは、長くしても整形しない【実測】。整形は利用者が明示的に頼んだときだけ動くので、空白が変わることを受け入れたうえで使える

### 6.2 従っても出力が変わらないもの

| cop | ERB | 勧めるとおりに書き換えた ERB | 出力 |
|---|---|---|---|
| `Style/IfUnlessModifier` | `<% if admin %><%= badge %><% end %>` | `<%= badge if admin %>` | 同じ |
| `Style/OneLineConditional` | `<% if a %><%= b %><% else %><%= c %><% end %>` | `<%= a ? b : c %>` | 同じ |
| `Style/Next` | ループの本文が `<% if i.odd? %>`〜`<% end %>` だけで、その本文が 3 行の HTML（`<li>`⏎`<%= i %>`⏎`</li>`） | `<% next unless i.odd? %>` を使う形 | 同じ |
| `Style/ConditionalAssignment` | `<% if a %><% y = 1 %><% else %><% y = 2 %><% end %>` | `<% y = a ? 1 : 2 %>` | 同じ |
| `Style/BlockDelimiters` | `<%= link_to(path) do %>Profile<% end %>` | `<%= link_to(path) { %>Profile<% } %>` | 同じ |

- どれも ERB として成り立つ書き換えで、従うかどうかはスタイルの選択になる
- `Style/IfUnlessModifier`、`Style/OneLineConditional` は、本文や分岐に HTML があると書き換えられない。HTML を出力するなら、タグを分けて書くしかない
- `Style/BlockDelimiters` が勧める `{ … }` は、ERB では避ける書き方とされる（herb-lint の `erb-prefer-do-end-blocks`）
- 属性の値の中で HTML のテキストを切り替える `class="<% if active %>on<% else %>off<% end %>"` は、`class="<%= active ? "on" : "off" %>"` と同じ出力になる。この形を勧める cop はなく、`Style/IfWithSemicolon` が三項演算子に触れるのは区切りの `;` に反応した結果（4 章）

### 6.3 ファイルとしての性質

| cop | ERB との関係 |
|---|---|
| `Style/FrozenStringLiteralComment` | ActionView は、テンプレートのマジックコメントではなく `ActionView::Template.frozen_string_literal` の設定で、コンパイルした Ruby に `# frozen_string_literal: true` を付ける（`action_view/template.rb`）【出典】 |
| `Naming/FileName` | テンプレートの名前にはロケールなどが入り、Rails はその名前で探す（`hello_world.pt-BR.html.erb`。[第 1 部 5.4 節](comparison.md#54-実際のビュー実測)） |
| `Layout/InitialIndentation` | テンプレートは HTML の途中のインデントから書き始められる（partial など） |
| `Layout/LeadingEmptyLines`, `Layout/TrailingEmptyLines`, `Layout/EmptyLineAfterMagicComment` | 空行がそのまま出力になる。`"\n<p>x</p>\n\n"` は、先頭と末尾の空行ごと出力される【実測】 |
| `Metrics/BlockLength` | 本文の HTML も行数に入る。実際のビュー 333 ファイルで 25 行を超えるブロックは 7 個（29〜41 行）で、どれも ERB タグを含む行だけを数えると 12〜21 行【実測】 |

## 7. 配置への指摘

ERB の中の Ruby の位置は、Ruby の構造ではなく、開始タグの幅と HTML の構造で決まります。Ruby の位置や空行を見る cop は、このどちらかに反応します。表の例は [repro/semantics/layout/](repro/semantics/layout/) の ERB を、元の ERB と文字位置が揃った Ruby にして確かめました（herb gem の `Herb.extract_ruby`。[repro/semantics/extract_ruby.rb](repro/semantics/extract_ruby.rb)）【実測】。

| 原因 | cop |
|---|---|
| [開始タグの幅](#71-開始タグの幅による指摘) | `Layout/EndAlignment`, `Layout/BlockAlignment`, `Layout/BeginEndAlignment`, `Layout/ElseAlignment`, `Layout/CaseIndentation`, `Layout/RescueEnsureAlignment`, `Layout/IndentationWidth`, `Layout/IndentationConsistency`, `Layout/CommentIndentation` |
| [HTML の構造](#72-html-の構造による指摘) | 上の cop に加えて `Layout/BlockEndNewline`, `Layout/LineLength` |
| [HTML の行が空行に見える](#73-html-の行が空行に見える指摘) | `Layout/EmptyLines`, `Layout/EmptyLinesAroundArguments`, `Layout/EmptyLinesAroundBeginBody`, `Layout/EmptyLinesAroundBlockBody`, `Layout/EmptyLinesAroundClassBody`, `Layout/EmptyLinesAroundExceptionHandlingKeywords`, `Layout/EmptyLinesAroundMethodBody`, `Layout/EmptyLinesAroundModuleBody` |

### 7.1 開始タグの幅による指摘

Ruby のコードは開始タグの後ろから始まります。`<%` と空白は 3 文字、`<%=` や `<%-` と空白は 4 文字なので、タグの位置を揃えて書いても、開始タグが違えば Ruby の位置は 1 文字ずれます。

| ERB | Ruby の位置 | 指摘 |
|---|---|---|
| `<%= form_with(model: user) do \|f\| %>`⏎`  <%= f.text_field :name %>`⏎`<% end %>` | `form_with` は 4 桁目、`end` は 3 桁目 | `Layout/BlockAlignment`、`Layout/IndentationWidth`（3 文字） |
| `<% if admin %>`⏎`  <%= badge %>`⏎`<% end %>` | 本文の `badge` が `if` から 3 文字下がる | `Layout/IndentationWidth` |
| `<% title = "Users" %>`⏎`<%= title %>` | 並んだ 2 つの文が 1 文字ずれる | `Layout/IndentationConsistency` |
| `<%- if admin -%>`⏎`  <p>admin</p>`⏎`<% end %>` | `if` は 4 桁目、`end` は 3 桁目 | `Layout/EndAlignment` |

- 値を出力するブロック（`form_with`、`link_to`、`content_for` など）は `<%=` で開き、`<% end %>` で閉じる。タグをどう揃えて書いても、ブロックの開始と `end` は必ず 1 文字ずれる。cop に従うには `<%  end %>` のように、タグの中の空白で位置を合わせるしかない
- このずれは ERB の構文から来るもので、書き手が書いたものではない。区切りの `;`（4 章）と同じ性質を持つ
- 実際のビュー 333 ファイルで、開始タグの幅を揃えて（`<%=` と `<%-` を `<%` にして）から検査すると、`Layout/BlockAlignment` は 91 件から 1 件に、`Layout/IndentationWidth` は 217 件から 131 件に、`Layout/IndentationConsistency` は 484 件から 464 件に減る【実測】
- 1 つのタグの中の Ruby の配置（複数行のメソッド呼び出しの引数の位置など）は、開始タグの幅に左右されない。Ruby のファイルと同じく RuboCop が検査できる

### 7.2 HTML の構造による指摘

ERB のインデントは、HTML の入れ子に従います。Ruby から見ると、タグの位置は HTML の深さの分だけ動きます。

| ERB | 指摘 |
|---|---|
| `<% if admin %>`⏎`  <div>`⏎`    <% count = 1 %>`⏎`  </div>`⏎`  <% total = 2 %>`⏎`<% end %>` | `Layout/IndentationWidth`（4 文字）、`Layout/IndentationConsistency`（`count` と `total` の深さが違う） |
| `<% items.each do \|i\| %>`⏎`  <li>`⏎`    <% i %>`⏎`  </li>`⏎`<% end %>` | `Layout/IndentationWidth`（4 文字） |

- 開始タグの幅を揃えても残る指摘は、ほとんどがこの種類になる。実際のビューで揃えても残る `Layout/BlockAlignment` の 1 件は、`<% end %>` を HTML の上で 2 文字ずらして書いたもの（conference-app の `talks/index.html.erb`）で、HTML のインデントの誤りでもある【実測】
- タグを HTML の後ろに続けて書くと、Ruby の位置は HTML の長さで決まる。rails の `rescues/_source.html.erb` は、`<pre>` の中で `<div class="line…">` の後ろに `<% if source.is_a?(Array) -%>` を書き、`<% else -%>` と `<% end -%>` を行頭に書いている（`Layout/ElseAlignment`、`Layout/EndAlignment`）。`<pre>` の中では空白が出力に出るので、cop に従ってインデントすると出力が変わる【実測】
- `Layout/BlockEndNewline` に従って `<% items.each do |i| %><p><%= i %></p><% end %>` の `<% end %>` を次の行に移すと、`<p>1</p><p>2</p><p>3</p>` の間に改行が入る【実測】
- `Layout/LineLength` は、HTML だけの行も、HTML とタグが混ざる行も、HTML の長さを含めて数える
- HTML の構造に合わせたインデントや改行を検査し、整形するのは herb-format / herb-lint の領域になる

### 7.3 HTML の行が空行に見える指摘

HTML だけの行を空行にした Ruby では、空行の cop が HTML の行を空行と見ます。実際のビュー 333 ファイルで、`Herb.extract_ruby` の結果から空白だけの行の空白を除いて検査すると、`Layout/EmptyLines` が 1,247 件、`Layout/EmptyLinesAroundBlockBody` が 123 件出る（[repro/semantics/ruby/blank_lines.rb](repro/semantics/ruby/blank_lines.rb)）【実測】。

- HTML の行を空白のまま残すと空行の cop は出ないが、その空白に `Layout/TrailingWhitespace` が反応する（4 章）
- 5 章と同じく、HTML の存在が Ruby から見えないことによる指摘でもある

## 8. 理想の姿【推測】

| 分類 | 理想の姿 |
|---|---|
| 区切りへの指摘 | 区切りの位置の文字への指摘だけを捨て、cop そのものは止めない。タグの中に書いたコードは検査する |
| HTML が見えないことによる指摘 | HTML の存在を Ruby に残し、cop を止めない |
| ERB の書き方に合わない指摘 | 従うと出力が変わる指摘は出さない。出力が変わらないものは、チームのスタイルとして選べる。ERB での書き方は、herb-lint の `erb-prefer-do-end-blocks` のように ERB のルールとして示す |
| 配置への指摘 | 開始タグの幅によるずれは、ERB の構文から来るものとして指摘しない（Ruby の位置ではなく開始タグの位置で測れば、タグを揃えて書いたかは検査できる）。HTML の構造に従う配置は ERB のツール、1 つのタグの中の Ruby の配置は RuboCop、と境界がはっきりしている |

- cop の本来の検査を削らずに済むのは、区切りへの指摘、HTML が見えないことによる指摘、配置への指摘のうち開始タグの幅と空行によるもの。どれも ERB の構文や、ERB をどう Ruby にするかから来る
- ERB の書き方に合わない指摘と、HTML の構造に従う配置への指摘は、Ruby への変換をどう工夫しても残る。ERB と Ruby の書き方の違い、RuboCop と ERB のツールの役割の違いから来る
- 止める範囲は、ファイル全体よりも誤りになる場所だけのほうが、本来の検査を残せる

## 9. 今後の検討事項

- 51 個のほかに、ERB で誤検知になる cop がないかを調べ、同じ 4 つに分類する（`Lint/Void` は `<%=` の値を使わない式と見るので、区切りへの指摘に近い）
