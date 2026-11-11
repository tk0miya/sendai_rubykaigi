# 第 2 部 tk0miya-rubocop-herb の実装

tk0miya/rubocop-herb（以下「tk0miya-rubocop-herb」）が、ERB をどう Ruby にし、RuboCop の誤検知と壊れる autocorrect をどう防いでいるかを説明します。
対象の版と凡例は [README.md](README.md) にあります。既存ツールとの比較の結果は [第 1 部](comparison.md) にあります。

- tk0miya-rubocop-herb: https://github.com/tk0miya/rubocop-herb の `4cbe9062156f28b95d94d27ebc59ab3f9da35f33`（2026-11-09 時点の main と `lib/` が同じ。main は rubocop を 1.92.2 に上げているので、ほかのツールと揃えるためにこのコミットを使う）
- rubocop 1.92.1 / herb 0.11.1（同リポジトリの `Gemfile.lock`）/ ruby 4.0.5
- 設定はリポジトリの `config/develop/rubocop.yml`（`bin/lint tk0miya-rubocop-herb`）。特に断りがない限り、`Herb/Linting` cop（herb-lint の実行）は外して、RuboCop の結果だけを見た。`Herb/Formatting` cop（herb-format の実行）は、`.herb.yml` で formatter を有効にしていないので何もしない（有効にした結果は [7.2 節](#72-herbformatting)）

## 目次

1. [概要](#1-概要)（[方針](#11-方針)）
2. [ERB から Ruby への変換](#2-erb-から-ruby-への変換)
3. [なぜ `<%=` と HTML を Ruby として描画するのか](#3-なぜ--と-html-を-ruby-として描画するのか)
4. [RuboCop との連携](#4-rubocop-との連携出典)
5. [ERB で止めている cop](#5-erb-で止めている-cop出典)
6. [autocorrect の検査（CopCorrectionGuard）](#6-autocorrect-の検査copcorrectionguard)
7. [tk0miya-rubocop-herb の cop](#7-tk0miya-rubocop-herb-の-cop)
8. [既知の問題](#8-既知の問題実測推測)
9. [その他](#9-その他出典)

## 1. 概要

- ruumba、rubocop-erb 0.8 系と同じく、**文書全体を 1 本の Ruby にする**方式。ただし HTML は空白で埋めるのではなく、元の位置に識別子（`div;` など）として書き込む。`<%=` は `_ =` にして、「出力する」という意味を残す
- 文字位置を変えずに変換するので、offense の位置も autocorrect の修正範囲も、そのまま元の ERB に当てられる
- ファイル全体で除外する cop は 9 個だけ。変換で書いた文字（HTML、区切り、`;`）に反応する cop は、ERB タグに書かれたコードの上の offense だけを報告する。ほかの誤検知は、ERB の構造を見て該当する行だけで cop を無効にする
- **テンプレートを壊す autocorrect を捨てる仕組み**（`CopCorrectionGuard`）がある。修正を元の ERB に当ててみて、HTML が変わる修正、出力タグの数が変わる修正、Herb のパースエラーが増える修正は適用せず、「autocorrect できない offense」として報告する
- 文を消す修正で空になったタグは、`Herb/EmptyErbTag` cop が行ごと消す。`<% unused = 1 %>` は、通常の Ruby ファイルと同じく `-a` でタグごと消える
- `Herb/Linting` cop で herb-lint も同時に実行でき、HTML の構造の誤りも RuboCop の出力に並ぶ（Node.js と `@herb-tools/linter` が必要）。herb-lint の修正も `rubocop -a` / `-A` で適用する
- `Herb/Formatting` cop は、`.herb.yml` で formatter を有効にしたときだけ herb-format を実行し、`rubocop -A` で整形する
- 規模は `lib/` の Ruby で 3,505 行（herb-rubocop-herb は 74 行、rubocop-erb 0.8.2 は 386 行）。うち 701 行は herb-lint / herb-format との連携

### 1.1 方針

tk0miya-rubocop-herb は、作者の次の方針で作られています。この文書での評価も、この方針に従います。

- **誤検知（false positive）を限りなくゼロにすることを最優先にする**。誤検知が多いと、AI のコーディングエージェントや CI のブロッカーになる
- **autocorrect は、決定的に、確実に正しく修正できるものだけにする**。修正を間違えうるものは、offense を報告するだけにして、修正は AI に任せる。AI の進化で、指摘されたコードを直すこと自体は容易になった
- そのため、ガード（[6 章](#6-autocorrect-の検査copcorrectionguard)）が修正を捨てて「autocorrect できない offense」として報告するのは、意図どおりの扱い。`-a` の後に残る offense が多いことは問題にしない
- 問題として扱うのは、誤検知と、適用されてしまう誤った修正。見逃し（false negative）は、誤検知より優先度が低い

## 2. ERB から Ruby への変換

### 2.1 変換の規則【出典】

`Converter`（`lib/rubocop/herb/converter.rb`）が、Herb の AST をもとに ERB を Ruby に変換します。文字の書き込みは `RubyRenderer`（`lib/rubocop/herb/ruby_renderer.rb`、302 行）が行います。

- 元の ERB をいったんすべて空白に置き換え（改行は残す）、ERB タグの中身を元と同じ文字位置に書き戻す
- タグの中身の直後に `;` を補う。`<%` `%>` の分の空白があるので、位置はずれない。空のタグ（`<% %>`）には補わない
- `<%=` と `<%==` は常に `_ =` に置き換える
- `<%%`（エスケープしたタグ）はテキストとして扱い、HTML のテキストと同じく `_a;` などにする
- `<%# … %>` は、右側に別のタグや HTML がない場合だけ Ruby のコメントにする
- タグの中の行末の Ruby のコメント（`<% x # comment %>`）は、そのまま書き込み、補う `;` もコメントの中に入る。ERB はテンプレートを行を保ったまま Ruby にコンパイルするので、このコメントは同じ行の後ろのタグや HTML までコメントにする。tk0miya-rubocop-herb もそれに合わせ、後ろのコードを検査しない（[2.4 節](#24-タグの中の行末の-ruby-のコメント)）
- HTML のタグやテキストも、元の位置に Ruby の識別子として書き込む。要素の開始タグ・終了タグは `div;` などのタグ名に、本文のテキストは `_a;` などになる。要素は入れ子のブロックにせず平坦に並べる。識別子を置けないほど短いテキストは空白のままになる（[3.3 節](#33-マーカーの限界実測出典)）
- 正規表現ではなく Herb の AST で ERB の構造を読むので、`<%-` / `-%>` や属性値の中のタグも扱える

### 2.2 変換の例【実測】

`bin/erb2ruby`（tk0miya-rubocop-herb のリポジトリにある。標準入力の ERB を変換して出力する）の出力です。行末の空白は省略しています。

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

同じ ERB の `Herb.extract_ruby`（rubocop-erb 0.8 系、herb-rubocop-herb）の出力は次のとおりで、HTML と `<%=` が空白になります。

```ruby

      @user.name  ;

   if a  ;

   end  ;
   items.each do |item|  ;
          item.name  ;
   end  ;
```

### 2.3 AST の書き換え【出典】

`RuboCopASTTransformer`（`lib/rubocop/herb/rubocop_ast_transformer.rb`）は、パースした AST で、HTML から書き込んだ識別子のメソッド名を、位置ごとに一意な名前（`div` → `div__html0` など）に書き換えます。別の位置の同じ HTML が同じ式と見なされないようにするためです（`Lint/DuplicateBranch`、`Style/IdenticalConditionalBranches`）。`RuboCop::Herb::ProcessedSource#parse` がパースの直後に呼びます。

RuboCop 1.92 の `Style/MethodCallWithoutArgsParentheses`、`Style/RedundantParentheses`、`Style/TernaryParentheses` などは、修正を当てたコードをパースし直し、AST が元と同じときだけ offense を出す（または修正する）（`RuboCop::Cop::ReparsedEquivalence`）。パースし直した AST は書き換えていないので、書き換えた AST と比べると HTML の識別子の名前（`div` と `div__html0`）が一致しません。`ReparsedEquivalenceAdapter`（`lib/rubocop/herb/reparsed_equivalence_adapter.rb`）は `ReparsedEquivalence` に prepend され、書き換える前の AST と比べさせます。`<div>` の中の `<%= link_to root_path() %>`、`<%= (a == b) ? 1 : 2 %>`、`<%= (foo) %>` には 3 つの cop が出て、`-a` で修正されることを確かめました【実測】。

### 2.4 タグの中の行末の Ruby のコメント

- ERB は、各タグのコードの後ろにコードを足しながら、行を保ってテンプレートを Ruby にコンパイルする。そのため、タグの中の行末の Ruby のコメントは、足したコードまでコメントにする
  - 出力タグ（`<%= user.name # the full name %>`）では、結果を出力するために足したコードがコメントになり、構文エラーになる
  - ほかのタグでは、同じ行の後ろのタグや HTML がコメントになる。`<% name = user.name # the full name %><%= name %>` では `<%= name %>` が出力されず、`<% if admin? # only for admins %><p>admin</p><% end %>` は `end` がコメントになって構文エラーになる（`cases/comment/commented_out_*`）。後ろに何もなくても、タグや HTML を置いた時点で壊れる
- tk0miya-rubocop-herb には、この書き方を報告する cop はない。herb-lint の `erb-no-trailing-comment` ルールに任せる（[marcoroth/herb#2871](https://github.com/marcoroth/herb/pull/2871)。`@herb-tools/linter` 0.11.2 で入った。検証環境の 0.11.1 にはない。[第 1 部 6.3 節](comparison.md#63-herb-format-の整形と無効化コメント)）。0.11.2 を入れれば、`Herb/Linting` cop を通して RuboCop の出力にも並ぶ【推測】。ただし、`Herb/Linting` は Ruby の構文エラーがあるファイルでは herb-lint を実行しない（[7.1 節](#71-herblinting)）ので、`<% end %>` がコメントになって構文エラーになったファイルには出ない【推測】
- tk0miya-rubocop-herb は ERB と同じくこのコメントで後ろのコードを隠すので、隠れたコードは検査されない。上の例の `name` には `Lint/UselessAssignment` が出る【実測】
- コメントに書いた `rubocop:disable` は効くが、補った `;` がコメントの中に入るので `Lint/CopDirectiveSyntax` も出る（`cases/rubocop_disable/trailing_ruby_comment*`、`ruby_comment_tag`、`cases/erb_comment/trailing_in_tag`）【実測】
- 実際のビュー 333 ファイルには 2 件ある（`<% talks.reverse.each do |talk| # want to place … %>` と `<% # Template Dependency: events/* %>`）。どちらも後ろに何もない行で、今は壊れていない【実測】

## 3. なぜ `<%=` と HTML を Ruby として描画するのか

### 3.1 空白にすると、正しい ERB と直すべき ERB が同じ Ruby になる

ERB は、テキストと `<%=` を `_erbout` への追記という文にコンパイルします。`Herb.extract_ruby` はこの文を落とし、tk0miya-rubocop-herb は短い文で置き換えます（[第 1 部 1 章](comparison.md#1-erb-から-ruby-を取り出す-2-つの方式)）。

| ERB | ERB のコンパイル結果 | `Herb.extract_ruby` | tk0miya-rubocop-herb |
|---|---|---|---|
| `<%= expr %>` | `_erbout << (expr).to_s` | `expr  ;`（値を捨てる式） | `_ = expr;`（値を使う文） |
| `<% expr %>` | `expr` | `expr  ;` | `expr;` |
| `<div>`、`</div>` | `_erbout << "<div>"` | 空白 | `div;` |
| テキスト、HTML コメント、`<%%` | `_erbout << "text"` | 空白 | `_a;`（置けるときだけ） |

`_ =` と `_a;` は、ERB のコンパイル結果にある文を、元の文字位置に収まる長さで書いたものです。

空白にすると、`<p><%= count + 1 %> items</p>` と `<p><% count + 1 %> items</p>`（`=` の書き忘れ）は、どちらも `count + 1  ;` になります。HTML だけを本文に持つブロックと、本当に空のブロックも同じ Ruby になります。cop には区別する手がかりがないので、両方を報告する（誤検知）か、cop ごと止める（見逃し）しかありません。

組にしたサンプル 9 組（[repro/cases/marker/](repro/cases/marker/)）では、次のようになりました【実測】（詳しくは [第 1 部 5.2 節](comparison.md#52-erb-として正しいものと直すべきものの区別)）。

- rubocop-erb 0.8.2 の除外を外すと、9 組すべてで正しい側にも直すべき側にも同じ指摘が出る
- herb-rubocop-herb は 48 個の cop を除外し、残りは両方を報告する。9 組中 7 組で正しい側にも指摘が出て、`-A` で正しい側の 5 ファイルの HTML や出力タグを消す
- rubocop-erb 0.8.2 は 65 個の cop を除外する。直すべき側 9 件のうち 8 件を見逃し、除外しなかった `Style/CombinableLoops` では正しい側にも指摘が出る
- tk0miya-rubocop-herb は、**直すべき側の 9 件をすべて検出し、正しい側には誤検知を出さない**。`-A` でも正しい側は 1 つも変えない（`Style/StringLiterals` の修正を除く）

直すべき側に `-A` をかけると、tk0miya-rubocop-herb は ERB の構造を保ったまま修正します【実測】。`<% if user %>`⏎`  <% user.touch %>`⏎`<% end %>` は `<% user&.touch %>` に、連続した 2 つの `items.each` は 1 つのループにまとまります（`Style/CombinableLoops`。間のタグは `Herb/EmptyErbTag` が消す）。`<p><% count + 1 %> items</p>` は `<p> items</p>` になります（`Lint/Void` で値を捨てる式が消える）。

実際のビュー 333 ファイルでは、0.8.2 が除外している内容の指摘 131 件のうち、妥当な指摘は 23 件でした。tk0miya-rubocop-herb は同じ cop で 22 件を報告し、すべて妥当な指摘でした（[第 1 部 5.4 節](comparison.md#54-実際のビュー実測)）。

### 3.2 実装の規模【出典】

| | Ruby の取り出し | 誤検知への対策 | 規模（`lib/`） |
|---|---|---|---|
| herb-rubocop-herb | `Herb.extract_ruby` | 48 個の cop をファイル全体で除外 | 74 行（`plugin.rb`） |
| rubocop-erb 0.8.2 | `Herb.extract_ruby` | 65 個の cop をファイル全体で除外 | 386 行 |
| tk0miya-rubocop-herb | 独自（`RubyRenderer`、302 行） | 9 個の cop をファイル全体で除外する。変換で書いた文字への指摘を除き、ほかは ERB の構造を見て誤検知になる行だけで無効にする | 3,505 行（うち herb-lint / herb-format との連携 701 行） |

- ファイル全体で除外する 9 個は、どれも ERB のファイルとしての性質（どの位置からでも書き始められる、マジックコメントを置かない、ファイル名にロケールが入る、空行が出力になるなど）から ERB に合わない cop で、マーカーでは解決しない（[5.1 節](#51-ファイル全体で除外している-cop)）
- 変換で書いた文字への指摘を除く仕組み（`VerbatimCode`、`CopOffenseFilter`、計 70 行）は、タグの終わりに補った `;` や `_ =` など、変換そのものが生む誤検知を扱う。offense の範囲だけで判断するので、ERB の形ごとに場所を探す必要がない（[5.2 節](#52-変換で書いた文字への指摘を除く-cop)）
- 行単位の無効化（`lib/rubocop/herb/erb_parser/` と `*_collector.rb`、計 757 行）は、ERB タグに跨がる `if` や `<% end %>` の位置合わせなど、Ruby として書けない ERB の構造を扱う。HTML を本文に持つ分岐やブロックを空とみなす cop の無効化は、主にマーカーを置けない短いテキストのためにある
- `CopCorrectionGuard` まわり（`CopCorrectionGuard`、`CorrectionAdjuster`、`CorrectionValidator`、計 455 行）は、修正後の ERB の HTML、出力タグの数、パースエラーなどを検査する。誤検知そのものが出なければ、誤った修正も提案されないので、この検査は変換で防げない壊れ方に備えるものになる

### 3.3 マーカーの限界【実測・出典】

- **短いテキストにはマーカーを置けない**。`_a;` は、テキストの中に 3 文字と後ろの空白か改行、または 2 文字と改行がないと置けない（`TEXT_MARKER_POSITION`）。`|` 1 文字などは空白のままになり、空白にする方式と同じ誤検知が起きる。[repro/cases/marker/safe_navigation_short.html.erb](repro/cases/marker/safe_navigation_short.html.erb)（`<% if user %>` の本文が `|<% user.touch %>`）には、tk0miya-rubocop-herb でも `Style/SafeNavigation` が出る。行単位の無効化は、`Lint/EmptyBlock` などについてこの穴を塞いでいるが、`Style/SafeNavigation` などは塞いでいない
- **`_ =` が隠す指摘がある**。`<%= x.camelize if x %>` は `_ = x.camelize if x` になり、`Style/SafeNavigation` の対象にならない。実際のビューでは 1 件あり、0.8.2 の除外を外すと出る
- **メッセージに `_ =` が出る**。`Style/IdenticalConditionalBranches` は「Move `_ = user.name` out of the conditional.」と報告する

### 3.4 評価【推測】

- `Herb.extract_ruby` で生じる誤検知は、cop の側の問題ではなく、変換で ERB の意味（出力する、HTML がある）を落としたことの帰結。落とした情報は cop からは取り戻せないので、ERB として正しいものと直すべきものは原理的に区別できない。除外は「誤検知を消す」ことではなく、「その cop が見つけるはずの問題ごと捨てる」ことになる
- tk0miya-rubocop-herb は、ERB のコンパイル結果にある文を `_ =` と `_a;` で残し、Ruby の上で ERB と同じ文の数と値の使われ方を再現している。誤検知の原因が変換の段階で消えるので、cop を除外せずに済み、妥当な指摘が残る。autocorrect も、ERB の構造を変える修正が提案されなくなる
- 実装の規模は、herb-rubocop-herb の約 47 倍、0.8.2 の約 9 倍（herb-lint / herb-format との連携を除くと、約 38 倍と約 7 倍）。それでも、除外で済ませる方式では、除外の一覧が「ERB で誤検知になる cop」をすべて把握している必要があり、RuboCop に cop が増えるたびに追いかけることになる。`NewCops: enable` の利用者には、除外の一覧に入る前の新しい cop の誤検知がそのまま届く。変換で意味を残す方式は、未知の cop にも同じ Ruby を見せるので、この追いかけっこが小さくなる
- 一方で、変換が複雑なぶん、`ReparsedEquivalence` のような RuboCop 側の仕組みと噛み合わせる処理が要る（[2.3 節](#23-ast-の書き換え出典)）。0.8 系は `Herb.extract_ruby` の結果をそのまま RuboCop に渡すので、この種の処理は要らない
- マーカーは万能ではない。短いテキストの穴と、`_ =` が隠す指摘があり、それぞれ行単位の無効化と見逃しとして残っている

## 4. RuboCop との連携【出典】

- LintRoller プラグインとして読み込まれ、RuboCop の ruby_extractors API に `Extractor` を登録する（`lib/rubocop/herb/plugin.rb`）
- `Extractor` は `[{ offset: 0, processed_source: … }]`、つまり **ファイル全体を 1 つの fragment** として返す（`lib/rubocop/herb/extractor.rb`）
- 文字位置が元の ERB と一致しているので、offense の位置も autocorrect の修正範囲も、変換せずに元のファイルに適用できる
- ruby_extractors API では 1 つの fragment が元ファイル上の連続した 1 区間でなければならない（[第 1 部 3.2 節](comparison.md#32-rubocop-erb-07-系)）。tk0miya-rubocop-herb はファイル全体を 1 区間にすることで、タグを跨いだ構文を 1 つの AST にしている
- エラーの表示は、変換後の Ruby ではなく元の ERB の行になる。RuboCop は、extractor が返した fragment で見つかった offense の範囲を、元のファイルのバッファに付け替えてから報告する（`RuboCop::Cop::Base#range_for_original`。[第 1 部 5.5 節](comparison.md#55-指摘の表示実測出典)）
- RuboCop と同じプロセス内で動く。ruumba のように一時ファイルや子プロセスを使わない
- ERB では `--disable-uncorrectable` も無効にする（挿入される `# rubocop:todo` コメントがテンプレートを壊すため）

## 5. ERB で止めている cop【出典】

tk0miya-rubocop-herb は、ERB で誤検知になる cop を 3 つの方法で止めています。ファイル全体での除外が 9 個、変換で書いた文字への指摘だけを除くものが 22 個、ERB の構造を見て行単位で無効にするものが 20 個です。止める理由の分類は [第 3 部](erb-and-rubocop.md) にあります。

### 5.1 ファイル全体で除外している cop

`lib/rubocop/herb/configuration.rb` の `EXCLUDED_COPS` で、次の 9 個の cop を `**/*.html.erb` から除外しています。

`Layout/CommentIndentation`, `Layout/EmptyLineAfterMagicComment`, `Layout/IndentationConsistency`, `Layout/InitialIndentation`, `Layout/LeadingEmptyLines`, `Layout/TrailingEmptyLines`, `Metrics/BlockLength`, `Naming/FileName`, `Style/FrozenStringLiteralComment`

`Naming/FileName` は、ロケールなどを含むテンプレートの名前（`show.pt-BR.html.erb` など）を snake_case でないと報告するため除外しています。`Layout/EmptyLineAfterMagicComment` は、`<%# encoding: utf-8 -%>` の後ろに挿入する空行がテンプレートの出力を変えるうえ、herb-format がその空行を消すので除外しています。ERB の空行は herb-lint と herb-format に任せます。rubocop-erb は 0.7 系が 53 個、0.8 系が 65 個、herb-rubocop-herb は 48 個、ruumba の推奨設定は 5 個です。`Lint/Syntax`、`Lint/UselessAssignment`、`Lint/Void` は除外していません。

### 5.2 変換で書いた文字への指摘を除く cop

`Configuration::VERBATIM_CODE_COPS` の 22 個は、ERB タグに書かれたコードの上の offense だけを報告します（`lib/rubocop/herb/cop_offense_filter.rb`、`lib/rubocop/herb/verbatim_code.rb`）。

- `CopOffenseFilter` が `RuboCop::Cop::Base#enabled_lines?` を上書きし、offense の範囲が 1 つの ERB タグの中身（区切りを除く）に収まり、範囲の文字が元の ERB と同じときだけ報告する。変換で書いた HTML の識別子、`_ =`、区切りの位置の空白、タグの終わりに補った `;` に掛かる offense は、`rubocop:disable` で止めた行の offense と同じ扱いになる
- 誤検知を除くための仕組みなので、`--ignore-disable-comments` を付けても報告しない
- ERB の構造を調べて場所を探すのではなく、offense の範囲だけで判断する。cop ごとに誤検知になる形を調べる必要がない

| cop | 反応する、変換で書いた文字 |
|---|---|
| `Style/Semicolon` | タグの終わりに補った `;` |
| `Style/IfWithSemicolon`, `Style/WhenThen`, `Style/InPatternThen` | `<% if a %>`、`<% when 1 %>`、`<% in 1 %>` の終わりに補った `;`（`if a;`、`when 1;`、`in 1;`） |
| `Lint/ElseLayout` | `<% else %>` の終わりに補った `;` と、同じ行に続く出力タグ（`else;  _ = x;`） |
| `Style/OneLineConditional`, `Style/SingleLineDoEndBlock` | 1 行に書いた、タグに跨がる条件分岐とブロック（`if a; …; end`、`foo do …; end`） |
| `Style/ConditionalAssignment`, `Style/RedundantCondition` | 分岐の出力タグがどれも `_ = …` になる（`if a; _ = a; else; _ = b; end`） |
| `Layout/SpaceAroundOperators` | `<%=` を書き換えた `_ =`（`<%=foo%>` が `_ =foo;` になる） |
| `Layout/ExtraSpacing`, `Layout/TrailingWhitespace` | 区切りや HTML の位置の空白 |
| `Layout/BlockEndNewline` | `<% end %>` の前の HTML が、`end` の前の式になる |
| `Layout/EmptyComment` | 複数行の ERB コメントの 1 行目が、空のコメントになる |
| `Layout/EmptyLines`, `Layout/EmptyLinesAroundArguments`, `Layout/EmptyLinesAroundBeginBody`, `Layout/EmptyLinesAroundBlockBody`, `Layout/EmptyLinesAroundClassBody`, `Layout/EmptyLinesAroundExceptionHandlingKeywords`, `Layout/EmptyLinesAroundMethodBody`, `Layout/EmptyLinesAroundModuleBody` | タグの間の空行（HTML の中の空行は herb-lint の `erb-no-extra-newline` に任せる） |

例えば `<p><%= link_to "Home",  root_path %></p>`（[repro/cases/output/spacing_in_tag.html.erb](repro/cases/output/spacing_in_tag.html.erb)）は `p; _ = link_to "Home",  root_path;  p;  ` になります。この Ruby を `.rb` のファイルとして RuboCop にかけると、`Style/Semicolon`、`Layout/ExtraSpacing`、`Layout/TrailingWhitespace` の指摘が 6 件出ます。tk0miya-rubocop-herb が報告するのは、タグの中に書いた余分な空白への 1 件だけです【実測】。

| 位置 | 変換後の Ruby で反応する文字 | cop | 結果 |
|---|---|---|---|
| 1:2 | `<p>` から書いた `p;` の `;` | `Style/Semicolon` | 捨てる |
| 1:23 | `"Home",  root_path` の余分な空白（タグの中に書いたもの） | `Layout/ExtraSpacing` | 報告する |
| 1:34 | タグの終わりに補った `;` | `Style/Semicolon` | 捨てる |
| 1:35 | `%>` の位置の空白 | `Layout/ExtraSpacing` | 捨てる |
| 1:38 | `</p>` から書いた `p;` の `;` | `Style/Semicolon` | 捨てる |
| 1:39 | 行末の、`</p>` の位置の空白 | `Layout/TrailingWhitespace` | 捨てる |

1 つのタグの中に書いたコードは、Ruby のファイルと同じく検査されます【実測】。

| ERB | 結果 |
|---|---|
| `<% a = 1; b = 2 %>` | `Style/Semicolon`（autocorrect はしない。[6.1 節](#61-仕組み出典)） |
| `<% if a; b; end %>` | `Style/IfWithSemicolon`、`Style/IfUnlessModifier` |
| `<% items.each do \|i\| foo(i) end %>` | `Style/SingleLineDoEndBlock`、`Style/BlockDelimiters` |
| `<% case x; when 1; foo; end %>` | `Style/WhenThen` |
| 複数行のタグの中の行末の空白 | `Layout/TrailingWhitespace` |
| `<div class="<% if a %>on<% else %>off<% end %>">`、`<%= link_to(path) do %>Profile<% end %>`、`<% case x %><% when 1 %>one<% end %>`、`<%=foo%>`、HTML の行末の空白 | 出ない |

実際のビュー 333 ファイルでは、`Layout/ExtraSpacing` が 4 件出ます。rails の fixture の `<%= render    partial:  "form" %>` などの 2 件と、conference-app の `<%=  @live_streams[:day1][:red_ja] %>` などの 2 件で、どれもタグの中に書いた余分な空白です。`-a` で直り、HTML は変わりません【実測】。

### 5.3 行単位で無効にしている cop

ERB の構造を見て、誤検知になる行でだけ cop を無効にしています（`<%# rubocop:disable %>` と同じ仕組み。`RuboCop::Herb::ProcessedSource#comment_config`）。対象は 20 個です。

| cop | 無効にする場所 | 実装 |
|---|---|---|
| `Lint/EmptyConditionalBody`, `Style/EmptyElse`, `Lint/EmptyWhen`, `Lint/EmptyInPattern`, `Lint/EmptyBlock`, `Lint/SuppressedException`, `Lint/EmptyEnsure` | 本文に HTML を含む分岐・ブロック | `DisabledCopsCollector` |
| `Lint/DuplicateBranch` | Ruby に現れない HTML だけが異なる分岐 | `DisabledCopsCollector` |
| `Style/IfUnlessModifier`, `Style/Next` | ERB タグに跨がる条件分岐 | `DisabledCopsCollector` |
| `Style/BlockDelimiters` | 1 行に書いた、ERB タグに跨がるブロック | `DisabledCopsCollector` |
| `Layout/EndAlignment`, `Layout/BlockAlignment`, `Layout/BeginEndAlignment` | ERB タグに跨がる分岐・ループ・ブロック・`begin` の `<% end %>` | `DisabledCopsCollector` |
| `Layout/ElseAlignment`, `Layout/CaseIndentation`, `Layout/RescueEnsureAlignment` | ERB タグに跨がる `else` / `elsif`、`when` / `in`、`rescue` / `ensure` | `DisabledCopsCollector` |
| `Layout/IndentationWidth` | 複数の ERB タグに跨がる本文の、最初の内容から最初の ERB タグまで | `DisabledCopsCollector` |
| `Layout/LineLength` | ERB タグを含まない行（HTML の行の長さは herb-format に任せる） | `HtmlOnlyLineCollector` |
| `Style/IdenticalConditionalBranches` | HTML と隣り合っていて分岐の外に移せない式、条件分岐の最初と最後の行 | `ImmovableExpressionCollector` |

- `Style/IfUnlessModifier`、`Style/Next`、`Style/BlockDelimiters` は、変換で書いた文字ではなく、ERB の書き方に合わない修正を勧めることが理由（修飾子の `if` にすると HTML が落ちる、`next` にすると `<% end %>` の閉じが残る、ERB では `{ … }` を避ける。ソースのコメント）。offense の範囲（`if` や `do`）はタグの中に収まるので、5.2 節の仕組みでは止まらない【推測】
- `Layout/LineLength` は、行を超えた部分が同じ行の HTML のこともあるので、5.2 節の仕組みではなく行単位で止める（ソースのコメント）

1 つの ERB タグの中に書いた Ruby は、これらの cop でも検査されます。本当に空の `else` や、入れ子の空の `if` も検出されることを確かめました【実測】。

ERB タグに跨がる構造では Layout 系の cop を無効にしているので、タグに跨がる本文や `<% end %>` のインデントは検査されません。HTML の構造に沿ったインデントは herb-format などの役割として残ります。

## 6. autocorrect の検査（CopCorrectionGuard）

### 6.1 仕組み【出典】

`lib/rubocop/herb/cop_correction_guard.rb` と `lib/rubocop/herb/correction_validator.rb` です。

- `RuboCop::Cop::Base` に prepend され、cop が `correct` を呼ぶたびに、修正をいったん別の corrector に作らせて検査する。ERB 以外のファイルには影響しない
- 検査の前に、`CorrectionAdjuster`（`lib/rubocop/herb/correction_adjuster.rb`）が、ERB タグの外から始まる（または外で終わる）修正を、はみ出した部分が変換後の Ruby で空白のときに限り、タグの中身に収まるよう切り詰める。`Lint/Void` が `<% 1 %>` の `1` を左側の空白ごと消すと `<%` まで消えるが、切り詰めると `1` だけが消える。切り詰めた修正と元の修正のうち、検査に通るものを切り詰めた方から選ぶ
- `CorrectionValidator#valid?` は、修正を元の ERB に当てた結果について、次の点を確かめる
  - ERB タグの間の HTML（両端の空白を除く。`<%%` のタグはテキストとして含める）が、修正前と同じ並びで残っている
  - 出力タグ（`<%=` / `<%==`）の数が変わっていない
  - ERB タグの中身に `<%` が増えていない（`%>` が消えて、タグが後ろのタグを飲み込んでいない）
  - コードのタグ（`<%#` 以外）が増えていない（ERB コメントの `#` が消えて、コメントがコードになっていない）
  - Herb のパースエラーが増えていない
  - 同じ行にある ERB タグのコードと `%>` の間に、改行を入れていない。変換で `%>` の前の空白に `;` を補うので、`Layout/LineLength` がその後ろで改行すると、行は短くならず `%>` だけが次の行に移る
- 検査に通らなかった修正は捨て、その offense は「autocorrect できない」（`[Correctable]` が付かない）として報告する
- `Style/Semicolon` の修正は、検査せずに常に捨てる（`Configuration::UNCORRECTABLE_COPS`）。`;` の位置で改行すると、次の文がインデントされずに行頭から始まるため。README に、手で直すよう書かれている
- HTML の両端の空白は無視するので、ERB タグをインデントや改行ごと削除する修正（`else` + `if` → `elsif` など）は通る
- `Herb/` で始まる tk0miya-rubocop-herb の cop は、ERB を直接書き換えるので検査しない。`Herb/Linting` と `Herb/Formatting` が適用する herb-lint と herb-format の修正も検査しない（[7 章](#7-tk0miya-rubocop-herb-の-cop)）
- 検査は cop ごとの修正に対して行う。RuboCop が複数の cop の修正を 1 つにまとめた結果は検査しない
- ERB タグの中身は比べていないので、HTML と出力タグの数とパースエラーが変わらなければ、2 つのタグを 1 つにつなげる修正も通る【出典】

rubocop-erb 0.8 系の検査（修正の範囲が 1 つのタグの Ruby に収まるか）と比べると、修正後の ERB そのものを見るので、範囲がタグの中に収まっていても出力タグを消す修正は止められます。一方で、範囲がタグの外に掛かっていても、HTML と出力タグとパースエラーが変わらない修正は通します。

### 6.2 ガードが捨てた修正【実測】

次の修正は、offense は報告されるが適用されません（`[Correctable]` が付かない）。

| ERB | cop | そのまま適用した場合の結果 |
|---|---|---|
| `<% unless a %>`…`<% else %>`…`<% end %>`（本文に HTML。`cases/control_flow/unless_else`） | `Style/UnlessElse` | 分岐を入れ替えた結果、`<% if a ;`⏎`  <p>y</p>`⏎`   else`…`end %>` のように HTML が 1 つの ERB タグの中に入る |
| `<% if !a %>`…`<% else %>`…`<% end %>`（本文に HTML） | `Style/NegatedIfElseCondition` | 同上 |
| `<% else %>` の中が `<% if b %>…<% end %>` だけ | `Style/IfInsideElse` | `<% elsif b %>` にした結果、内側の本文が `<% <p>z</p> %>` になる |
| `<% if a %>`⏎`  <%= foo %>`⏎`<% else %>`⏎`  <%= foo %>`⏎`<% end %>` | `Style/IdenticalConditionalBranches`（`-A`） | 両方の分岐の `<%= foo %>` が消え、`<% end`⏎`   _ = foo %>` になる（`foo` が出力されなくなる） |
| `<%= f.select :status, Announcement.statuses, {}, class: "…", disabled: @announcement.published? %>`（ERB タグだけで 191 桁。実際のビュー） | `Layout/LineLength` | 引数の後ろで改行し、`%>` が次の行の行頭に移る。2 行目は 120 桁を超えたまま |

- `Style/UnlessElse` と `Style/NegatedIfElseCondition` は、HTML の並びが変わり、Herb のパースエラーも増えるので捨てられる（検査の途中経過を出力して確認）
- `Style/IfInsideElse` は、`CorrectionAdjuster` が切り詰めた結果、何も変えない修正になる
- `Style/IdenticalConditionalBranches` は、HTML とパースエラーは変わらないが、出力タグが 2 つから 1 つに減るので捨てられる
- `Layout/LineLength` は、`%>` の前に改行を入れるので捨てられる。実際のビューの 162 件のうち、`Layout/LineLength` だけをかけて `-a` で修正されるのは 7 ファイルの 12 件で、残りは捨てられる。修正される 12 件は、`{ |b|` の後ろや、HTML の中（`<option` と `<%=` の間）で改行するもの（[8.2 節](#82-tk0miya-rubocop-herb-の問題)）

`Lint/Void` は、`CorrectionAdjuster` が切り詰めるので適用されます。`<p>a</p>`⏎`<% 1 %>`⏎`<%= b %>` は `-a` で `<% %>` になり、`Herb/EmptyErbTag` が行ごと消します。`<% 1; foo %>` は `<%; foo %>` になります（出力は変わらない）。

検証用 ERB（79 ファイル）では、`Herb/Linting` を外すと、`-a` で 29 ファイル、`-A` で 34 ファイルが書き換わり、HTML が変わったファイルもパースエラーが増えたファイルも 0 でした。実際のビュー 333 ファイルでは、`-a`、`-A` とも HTML が変わったファイルもパースエラーが増えたファイルも 0 でした（[第 1 部 5.3 節](comparison.md#53-autocorrect実測)）。`Herb/Linting` も含めると HTML が変わるファイルが出ますが、どれも herb-lint の修正によるものです（[7.1 節](#71-herblinting)）。

## 7. tk0miya-rubocop-herb の cop

### 7.1 Herb/Linting

`Herb/Linting`（`lib/rubocop/cop/herb/linting.rb`）は、herb-lint を Node.js のプロセスで実行し、その結果を RuboCop の offense として報告します【出典】。

- 既定で有効。`@herb-tools/linter` が入っていなければ、セットアップを促すエラーを 1 回だけ報告する（README に記載。【実測】）
- Node.js のプロセスは RuboCop のプロセスごとに 1 つ起動し、全ファイルで使い回す
- herb-lint の `erb-no-empty-tags` は報告しない。同じ内容を `Herb/EmptyErbTag` cop が報告し、autocorrect する（README に記載）

`repro/cases/` の 4 ファイルで、herb-lint 単体（`bin/lint herb-lint`）の結果と比べました（`@herb-tools/linter` 0.11.1）【実測】。

| ERB | herb-lint 単体 | `Herb/Linting` |
|---|---|---|
| `syntax/missing_close`（`<div><span></div>`） | `parser-no-errors`（`MISSING_CLOSING_TAG_ERROR`） | 同じ。``E: Herb/Linting: [parser-no-errors] Opening tag `<span>` at (1:6) doesn't have a matching closing tag `</span>` in the same scope. (`MISSING_CLOSING_TAG_ERROR`)`` |
| `variables/cross_tag_variables`（本当に未使用の `unused`） | `erb-no-unused-local-variable` | 同じ。RuboCop の `Lint/UselessAssignment` と同じ位置に並ぶ |
| `syntax/missing_end`（`end` の抜け） | `parser-no-errors` が 3 件（`RUBY_PARSE_ERROR` ×2、`MISSING_ERB_END_TAG_ERROR`） | 出ない（Ruby の構文エラーがあるファイルでは herb-lint を実行しない。README に記載）。RuboCop の `Lint/Syntax` は出る |
| `style/ruby_style` | 出ない | 出ない（RuboCop の Layout / Style は出る） |

- 実際のビュー 333 ファイルで、`rubocop` 全体の実行時間は、`Herb/Linting` を含めると約 6 秒、外すと約 3 秒（`--cache false`、Node.js の起動を含む）
- `.herb.yml` は、RuboCop のプロジェクトのルート（`RuboCop::ConfigFinder.project_root`。カレントディレクトリから上へたどって最初に見つかった `Gemfile` / `gems.rb` のディレクトリ。なければカレントディレクトリ）から上へたどって探す。モノレポのルートに置いた `.herb.yml` も使える（README に記載）
- `@herb-tools/linter` は、プロジェクトのルートを起点に Node.js の規則で探す（`lib/rubocop/herb/node_server.cjs` の `requireFromProject`。ルートとその上の `node_modules`）【出典】
- そのため、`package.json` が `Gemfile` より下のディレクトリにあると使えない。`repro/node_modules` に入れたまま、上の `research/` に空の `Gemfile` を置いて `repro` で実行すると、`research/` がルートになり、「`@herb-tools/linter is not installed in …/research`」というエラーになった【実測】。上の比較は、上のどのディレクトリにも `Gemfile` がない `repro` で実行した
- 設定で読み込み先を変える方法は見当たらない（`Herb/Linting` の設定は `NodeCommand` のみ）【出典】。フロントエンドを別ディレクトリ（`frontend/` など）に分けているプロジェクトでは困る可能性がある【推測】
- Marco Roth 氏の Rust 製 linter がリリースされれば、子プロセスをやめて同じプロセスから呼べる見込み（[第 1 部 8 章](comparison.md#8-herb-の今後rust-化)）【推測】

#### autocorrect【実測・出典】

`rubocop -a` は `herb-lint --fix` が適用する修正を、`rubocop -A` はさらに `herb-lint --fix-unsafely` が適用する修正も適用します（README）。herb-lint が修正した結果から、元との差分を 1 つの置換として受け取ります（`herb_lint_server.cjs`）。

- `cases/` に `--only Herb/Linting` で `-a` / `-A` をかけた結果は、`herb-lint --fix` / `--fix-unsafely` の結果と全ファイルで一致した（11 / 12 ファイル）
- そのうち 9 ファイルで HTML が変わる。`erb-prefer-direct-output` が `<%= "hello" %>` を `hello` にし、`erb-no-duplicate-branch-elements` が分岐の両方にある `<p>` を分岐の外に出す（`control_flow/unless_else`）。herb-lint の修正どおりの変更
- 実際のビューでは、`Herb/Linting` の offense が 320 件（うち autocorrect できるもの 187 件）。RuboCop の cop と合わせた `-a` で 232 ファイルが書き換わり、HTML が変わったのは 30 ファイル、パースエラーが増えたファイルは 0。herb-lint 単体の `--fix` でも、HTML が変わるのは 30 ファイル
- RuboCop の修正と同じ実行で組み合わさる。`<%# rubocop:disable Style/StringLiterals %>`⏎`<%= "a" %>`（`rubocop_disable/erb_comment`）は、`erb-prefer-direct-output` で `"a"` が HTML の `a` になり、不要になった無効化コメントを `Lint/RedundantCopDisableDirective` と `Herb/EmptyErbTag` が消して、`a` だけが残る
- 範囲を指定した無効化（`rubocop_disable/multiline_range`）では、`rubocop:disable` のタグだけが消え、`rubocop:enable` のタグが残る。ERB では `Lint/RedundantCopEnableDirective` が出ない（`<%# rubocop:enable Style/StringLiterals %>` だけのテンプレートにも出ない。同じ内容の Ruby のファイルには出る）
- `syntax/syntax_errors_ignored` の `<%= items.map do |i| %>` は、`erb-no-output-control-flow` で `<% items.map do |i| %>` になる。修正の後には `erb-prefer-each-over-map`（`each` にせよ）が出るが、autocorrect はされない。`<% end.join(', ') %>` の `join` も残る

herb-lint の修正は `CopCorrectionGuard` の検査を通らないので（[6.1 節](#61-仕組み出典)）、herb-lint の修正に誤りがあれば、そのまま `rubocop -a` で適用されます。

- `erb-comment-syntax` の修正は、`<% #` を `<%#` にするだけで、タグの中身を見ない（`@herb-tools/linter` 0.11.1 の `ERBCommentSyntax#autofix`。herb の main でも同じ）【出典】
- そのため、1 行目がコメントで 2 行目以降にコードがある複数行のタグでは、コードごと ERB のコメントになる。`<% # set up the name`⏎`  name = user.name %>`⏎`<p><%= name %></p>` は、`rubocop -a` で `<%# set up the name`⏎`  name = user.name %>` になり、`name` が定義されなくなる（描画すると `NameError`）。`herb-lint --fix` 単体でも同じ【実測】
- 実際のビュー 333 ファイルには、この形のタグはない。`<% #` は 1 件（`<% # Template Dependency: events/* %>`）で、1 行のタグなので `<%#` にしても壊れない【実測】

### 7.2 Herb/Formatting

`Herb/Formatting`（`lib/rubocop/cop/herb/formatting.rb`）は、herb-format を Node.js のプロセスで実行し、整形で変わる部分を offense として報告し、autocorrect で整形します【出典】。

- 既定で有効だが、`.herb.yml` の `formatter.enabled` が `true` のときだけ動く（herb-format は既定で無効）。無効なら Node.js も起動しない
- autocorrect は unsafe で、`rubocop -A` でだけ適用される（herb-format は experimental preview で、HTML の空白を変えるため。README に記載）
- 整形で変わる部分ごとに offense を出す（行のインデントなど）

`.herb.yml` に `formatter: { enabled: true }` を足して試しました【実測】。

- `cases/` では 32 ファイルに 42 件。`--only Herb/Formatting -A` の結果は、`herb-format --force` の結果と全ファイルで一致した（29 ファイル）。`-a` では何も変わらない
- 実際のビューでは 233 ファイルに 1,060 件。`--only Herb/Formatting -A` の結果は、0 バイトのテンプレート 16 ファイルを除いて `herb-format --force` と一致した。herb-format の CLI は 0 バイトのファイルに改行を書き込み、`Herb/Formatting` は書き込まない
- 実行時間は、`Herb/Linting` と合わせて約 7 秒（333 ファイル、`--cache false`）
- RuboCop の cop、`Herb/Linting` と合わせた `-A` では、`cases/` の 54 ファイル、実際のビューの 266 ファイルが書き換わり、パースエラーが増えたファイルは 0

RuboCop の修正、herb-lint の修正、herb-format の整形が同じ実行で繰り返されるので、herb-format と herb-lint のバグが組み合わさって、無効化コメントが消えたり、コードが ERB のコメントになったりします（[8.1 節](#81-herb-lint--herb-format-の修正)）。

### 7.3 Herb/EmptyErbTag

`Herb/EmptyErbTag`（`lib/rubocop/cop/herb/empty_erb_tag.rb`。既定で有効）は、空の ERB タグ（`<% %>`）と空の ERB コメント（`<%# %>`）を報告し、autocorrect で消します【出典】。

- `CorrectionAdjuster` は、`Lint/Void` などがタグの Ruby をまるごと消すときも区切りを残すので、空のタグが残る。この cop がそれを消し、通常の Ruby ファイルで文が消えるのと同じ結果にする
- タグが行に 1 つだけ（または空のタグだけ）なら行ごと消す。行頭のタグなら、後ろの空白も消す（`<%-` を除く）。`<%-` / `-%>` で取り除かれる空白も一緒に消す
- 行末のタグを消した後に残る行末の空白は消さない。herb-lint の `erb-no-trailing-whitespace` に任せる（`Herb/Linting` が autocorrect する）
- 出力タグ（`<%= %>`）と `<%% %>` は対象外
- `cases/variables/cross_tag_variables` の `<% unused = 1 %>` は、`-a` で `Lint/UselessAssignment`、`Lint/Void`、`Herb/EmptyErbTag` が順に修正し、行ごと消える【実測】

### 7.4 Herb/IgnoredCopDirective

- ERB のコメントは、右側に別のタグや HTML がない場合だけ Ruby のコメントになる。そのため `<%# rubocop:disable Lint/Void %><%= user.name %>` のような行では、`rubocop:disable` が効かない
- `Herb/IgnoredCopDirective`（既定で有効）は、このように黙って無視される ERB のコメントの rubocop のディレクティブを報告する（`cases/erb_comment/leading`）
- autocorrect はしない（改行を入れると出力される空白が変わるため。README に記載）

## 8. 既知の問題【実測・推測】

[1.1 節](#11-方針)の方針に従い、誤検知と、適用されてしまう誤った修正（テンプレートを壊す修正や ERB に合わない修正）を問題として挙げます。offense を報告して autocorrect しない（ガードが修正を捨てる）ものは挙げません。

### 8.1 herb-lint / herb-format の修正

`CopCorrectionGuard` は `Herb/Linting` と `Herb/Formatting` の修正を検査しないので（[6.1 節](#61-仕組み出典)）、herb-lint と herb-format のバグは `rubocop -a` / `-A` でそのまま適用されます。tk0miya-rubocop-herb の変換の問題ではありませんが、`rubocop` 1 回で適用されるので、利用者からは tk0miya-rubocop-herb の autocorrect が壊したように見えます。

| 問題 | どこのバグか | 起きる条件 | 状態 |
|---|---|---|---|
| 1 行目がコメントの複数行のタグ（`<% # set up the name`⏎`  name = user.name %>`）が、コードごと ERB のコメント（`<%# …`）になる（[7.1 節](#71-herblinting)） | herb-lint。`erb-comment-syntax` の修正が `<% #` を `<%#` にするだけで、2 行目以降のコードを見ない。`herb-lint --fix` 単体で再現する | 既定の設定の `rubocop -a`（`Herb/Linting` が有効） | 未報告 |
| コードの右に書いた `<%# rubocop:disable … %>` が別の行に移り、同じ実行の `Lint/RedundantCopDisableDirective` が消す。抑えていた offense がまた出る（`erb_comment/after_if`、`trailing`、`empty_if`） | herb-format。`<%#` を次の行に移す（[第 1 部 6.3 節](comparison.md#63-herb-format-の整形と無効化コメント)） | formatter を有効にした `rubocop -A` | 報告済み（[marcoroth/herb#2868](https://github.com/marcoroth/herb/issues/2868)） |
| `rubocop_disable/multiline_tag`（`<%`⏎`  # rubocop:disable Style/StringLiterals`⏎`  x = "b"`⏎`%>`⏎`<%= x %>`⏎`<%= "c" %>`）が `<%# x = "b" %>`⏎`<%= x %> c` になり、`x` が定義されなくなる | herb-lint（上の `erb-comment-syntax`）。herb-format が複数行のタグを `<% # rubocop:disable Style/StringLiterals`⏎`  x = "b" %>` に整形したことがきっかけ。整形の結果は Ruby として同じ意味で、壊すのは `erb-comment-syntax` の修正 | formatter を有効にした `rubocop -A` | 上の herb-lint の問題と同じ原因 |

- `multiline_tag` の流れ: `erb-prefer-direct-output` で `<%= "c" %>` が `c` になる → herb-format が複数行のタグを整形する（後ろが出力タグのままなら複数行を保つ）→ `erb-comment-syntax` の修正がタグ全体をコメントにする → `Lint/RedundantCopDisableDirective` がディレクティブを消す。`<%= "c" %>` を `c` にしたファイルに `herb-format --force` と `herb-lint --fix` だけをかけても、`<%# rubocop:disable Style/StringLiterals`⏎`  x = "b" %> <%= x %> c` になる【実測】
- `CorrectionValidator` は「コードのタグが増えない」ことを見るが、「減らない」ことは見ないので、herb-lint の修正を検査の対象にしても `erb-comment-syntax` の問題は止められない【出典】
- 実際のビュー 333 ファイルには、`erb-comment-syntax` の問題が起きる形のタグはない【実測】

### 8.2 tk0miya-rubocop-herb の問題

- **`Layout/LineLength` の修正のうち、ガードを通るもの**: `%>` を次の行に移す修正はガードが捨て、指摘だけが残る（[6.2 節](#62-ガードが捨てた修正実測)）。一方、`%>` の直前以外で改行する修正は通る。`Layout/LineLength` だけをかけた `-a` では、実際のビューの 7 ファイルで 12 件が修正され、ERB に合わない形が残る。どれも出力は変わらない
  - `{ |b|` の後ろで改行し、次の行を行頭から始める（`<%= b.label(class: "inline-block mr-2") {`⏎` b.check_box(…) } %>`）。後続の `Style/BlockDelimiters` などで `do`〜`end` に直る
  - HTML の中で改行する（`<option <%= request.format == Mime[:html] ? 'selected' : '' %> value="…">` が `<option`⏎` <%= … %> value="…">`）。改行の後は行頭から始まり、HTML のインデントが崩れる。HTML の両端の空白の違いはガードが無視するので通る
  - 属性値の中の三項演算子（`class="w-full h-full <%= user_bookmarks.find { |b| b.talk_id == talk.id } ? "hidden" : "" %>"`）では、`{ |b|` の後ろの改行から `Style/BlockDelimiters`、`Style/MultilineTernaryOperator` と Layout 系の修正が続き、`-a` で `class` 属性の中に 7 行の `if`〜`else`〜`end` ができる。インデントは `<svg` の行の 130 桁あたりに揃うので、行はかえって長くなる（`talks/_bookmark_button` の `Layout/LineLength` は 2 件から 14 件に増える）
- **`Lint/RedundantCopEnableDirective` が出ない**: ERB では、対応する `rubocop:disable` のない `rubocop:enable` を報告しない（`<%# rubocop:enable Style/StringLiterals %>` だけのテンプレートにも出ない。同じ内容の Ruby のファイルには出る）。`rubocop:disable` のタグが autocorrect で消えた後に残る `rubocop:enable` のタグ（[7.1 節](#71-herblinting)の `rubocop_disable/multiline_range`）も報告されない。見逃しで、誤編集ではない

### 8.3 tk0miya-rubocop-herb だけに出る指摘の評価

実際のビューと検証用 ERB で、tk0miya-rubocop-herb だけに出る指摘のうち、ERB では扱いを考える必要があるものです。指摘の内容は [第 1 部 5.4 節](comparison.md#54-実際のビュー実測) にあります。

- **`Layout/LineLength`**: 行全体の長さを測るので、HTML が原因の長い行も指摘する。テンプレートも読むためのソースファイルなので、どれも改行で短くすべき行と言える。違いは直す道具で、ERB タグの中は RuboCop、タグの外の HTML は `herb-format` が直す。両方を使うなら、`Layout/LineLength` の `Max` と `herb-format` の `maxLineLength` を揃えないと、基準が食い違う（README に記載）
- **`Lint/EmptyFile`**: 作りかけの空のテンプレートを見つけられる。わざと空にしたテンプレートは、`<%# … %>` を置けば指摘されない

## 9. その他【出典】

- README は Usage（autocorrect、`Layout/LineLength`、`Herb/Linting`、`Herb/Formatting`、`Herb/IgnoredCopDirective`、`Herb/EmptyErbTag`）が書かれているが、冒頭・Installation・Contributing などは `bundle gem` の雛形のまま
- `CHANGELOG.md` は `## [Unreleased]` のみで、version は未リリース
- gem 名が、rubygems に登録済みの Marco Roth 氏の `rubocop-herb` 0.0.1 と衝突している（[第 1 部 10 章](comparison.md#10-要フォローアップ)）
- Ruby 3.3 以上、rubocop 1.90 以上が必要（gemspec）
- 既定で対象にするのは `.html.erb` だけ（`Configuration::DEFAULT_EXTENSIONS`）。`extensions` 設定で追加できる
