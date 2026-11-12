# スライド構成（たたき台）

- トーク: Building a Unified Ecosystem for ERB Development Experience（[proposal.md](../proposal.md)）
- 枠: 15 分
- 材料: [research/README.md](../research/README.md)。ツールの比較は [comparison.md](../research/comparison.md)、rubocop-herb の実装は [tk0miya-rubocop-herb.md](../research/tk0miya-rubocop-herb.md)、ERB に合わない cop の 4 分類は [erb-and-rubocop.md](../research/erb-and-rubocop.md)

## 方針

- **lint（RuboCop × ERB）を主軸にする**。ERB の lint の技術的な課題と、ここまでの歩みを話す。フォーマット・型チェック・LSP は、分量と時間の余裕を見て付け足すかを決める
- 聴衆: ERB のツールを導入していない人、導入しているが効果をぼんやりとしか理解していない人。ruby_extractors API などの内部の話は扱わない
- メッセージは 3 つ
  1. これまでのツール（タグ単位）は不完全だった
  2. 改善が進んでいる（文書全体方式への移行）
  3. tk0miya-rubocop-herb は、残る問題への解決策の萌芽
- 流れ: タグ単位 → 文書全体（rubocop-erb 0.8 系）→ それでも残る 4 つの問題 → tk0miya-rubocop-herb の対策（ここまでが Ruby パートの lint の精度の話）→ ERB ファイル全体へ（herb-lint / herb-format との統合）→ autocorrect の歩み → 現状
- 文書全体方式の例は、リリース済みで誰でも使える rubocop-erb 0.8 系にする。Herb 本家の PR（marcoroth/herb#2260）は扱わない
- 0.8 系の扱いは批判ではなく構造の話にする。「`<%=` と HTML の意味がない Ruby では cop が区別できないので、誤検知を出すか、除外して見逃すしかない」。0.8 系の PR 自身が「除外した cop は ERB の文脈を理解させる PR で今後有効に戻す」としているので、その先を試したのが tk0miya-rubocop-herb、とつなげる
- 既存ツールの問題は、どれも検証用 ERB（`research/repro/cases/`）か実際のビュー（rails/rails、kaigionrails/conference-app の 333 ファイル）で実測したものだけを見せる
- 「すべての問題を解決した」とは言わない。変換で生まれる問題は変換で解決し、ERB 特有の問題は ERB の構文で決まる部分を検査の対象から外す（書き手が 1 つのタグの中に書いたコードだけを検査する）、と 2 段で話す。herb-lint / herb-format との統合は、4 つの問題とは別のプラスアルファとして話す。herb-lint / herb-format の修正は検査しないので、そのバグ（`erb-comment-syntax` が複数行のタグのコードをコメントにする）もそのまま適用される（[comparison.md](../research/comparison.md#発表に向けて)）

## 時間配分

| パート | 枚数 | 時間 |
|---|---|---|
| 0. 導入 | 2 | 0:45 |
| 1. タグ単位の lint は不完全だった | 5 | 2:45 |
| 2. 文書全体へ | 2 | 1:30 |
| 3. それでも残る 4 つの問題 | 6 | 3:30 |
| 4. tk0miya-rubocop-herb: Ruby パートの lint の精度を上げる | 5 | 3:30 |
| 5. Ruby パートから ERB ファイル全体へ | 1 | 0:45 |
| 6. autocorrect の歩み | 2 | 1:15 |
| 7. 現状とまとめ | 2 | 1:15 |
| 合計 | 25 | 15:15 |

## 0. 導入（0:45）

### 1. タイトル

- Building a Unified Ecosystem for ERB Development Experience
- 名前、所属

### 2. 自己紹介

- Steep、rbs_rails へのコントリビュート
- Steep への ERB 対応の提案（[soutaro/steep#1409](https://github.com/soutaro/steep/issues/1409)）
- → 「ERB でも Ruby と同じ開発体験がほしい」が動機

## 1. タグ単位の lint は不完全だった（2:45）

### 3. あなたの ERB に RuboCop は効いていますか?

```erb
<% count = items.size %>
<% if foo == nil %>
  <p>yes</p>
<% else %>
<% end %>
```

- erb_lint（推奨設定）: 0 件
- 同じ内容の `.rb`: `Lint/UselessAssignment`（`count` を使っていない）、`Style/NilComparison`、`Style/EmptyElse`
- この ERB はトークを通して使う例にする。スライド 9（rubocop-erb 0.8 系）とスライド 20（tk0miya-rubocop-herb）で同じ ERB をもう一度見せ、検出できる指摘が 0 → 2 → 3 件と増えていくことを示す

### 4. よく使われている ERB の linter

- erb_lint（累計 2,250 万 DL）、rubocop-erb（91 万 DL）
- どちらも、ERB の中の Ruby を RuboCop で検査する
- 数字は rubygems.org の 2026-10-31 時点の累計 DL

### 5. タグ単位で Ruby を取り出す

- ERB タグ 1 つずつを、独立した Ruby として RuboCop にかける（erb_lint、rubocop-erb 0.7 系）
- 図: スライド 3 の ERB が、`count = items.size` / `if foo == nil` / `else` / `end` という断片の列になる様子
- 失われる文脈
  - 制御構造（`if` 〜 `end` がタグを跨ぐ）
  - 変数スコープ（前のタグで定義した変数）
  - ファイル（タグ 1 つが 1 ファイル扱い）

### 6. なぜ見逃すのか

- スライド 3 の ERB で、erb_lint（推奨設定）が 3 つの指摘を見逃す理由

| 見逃す指摘 | ERB | 見逃す理由 |
|---|---|---|
| `Style/NilComparison` | `<% if foo == nil %>` | タグ 1 つだけでは `end` のない不完全な Ruby なので、構文エラーとして黙ってスキップされる |
| `Style/EmptyElse` | `<% else %>`⏎`<% end %>` | `<% else %>` も `<% end %>` も単独では不完全な Ruby なのでスキップされ、`else` が空かどうかを確かめられない |
| `Lint/UselessAssignment` | `<% count = items.size %>` | 後ろのタグが見えないので、使っている変数まで指摘される。そのため README が cop の無効化を推奨している |

- 前の 2 つは制御構造、最後の 1 つは変数スコープと、どれもスライド 5 の「失われる文脈」から来る
- 出典: [comparison.md 3.1 節](../research/comparison.md#31-erb_lintrubocop-linter)。スライド 3 の ERB を、erb_lint（推奨設定・全 cop）、rubocop-erb 0.7 系、同じ内容の `.rb` にかけた結果

### 7. ほかにも見逃している

| ERB | erb_lint（推奨設定）・rubocop-erb 0.7 系が見逃す指摘 | 見逃す理由 |
|---|---|---|
| `<% items.each_with_index do \|item, i\| %>`⏎`  <li><%= item.name %></li>`⏎`<% end %>`（`i` を使わない） | `Lint/UnusedBlockArgument` | タグを跨ぐブロックが見えない |
| `<% if !user.nil? %>`⏎`  <p>hi</p>`⏎`<% end %>` | `Style/NegatedIf` | `if` を含むタグは単独では不完全な Ruby。erb_lint はスキップし、0.7 系は `if` を削って条件式だけを検査するので、`if` と否定の組み合わせが見えない |
| `<% if admin? %>`⏎`  <p>admin</p>`（`end` の抜け） | `Lint/Syntax` | タグを跨ぐ構文を検査できない（0.7 系は cop を除外） |

- どれも、同じ内容の `.rb` なら RuboCop が指摘する
- 出典: [comparison.md 3 章、5.1 節](../research/comparison.md#3-タグ単位の方式)（`cases/control_flow/unused_block_arg_output`、`cases/control_flow/negated_if`、`cases/syntax/missing_end`）

## 2. 文書全体へ（1:30）

### 8. 文書全体を 1 本の Ruby にする

- rubocop-erb 0.8 系（2026-10-29）が、タグ単位から文書全体の変換に切り替えた（[r7kamura/rubocop-erb#70](https://github.com/r7kamura/rubocop-erb/pull/70)）
- HTML を空白に置き換え、ERB タグの中身を元の位置に残して、ファイル全体を 1 本の Ruby にする
- スライド 3 の ERB は、次の Ruby になる（行末の空白は省略）

```erb
<% count = items.size %>
<% if foo == nil %>
  <p>yes</p>
<% else %>
<% end %>
```

↓

```ruby
   count = items.size  ;
   if foo == nil  ;

   else  ;
   end  ;
```


### 9. タグを跨いで検査できるようになった

- スライド 3 の ERB に、0.8 系では `Style/NilComparison` と `Lint/UselessAssignment` が出る（0 件 → 2 件）
  - タグを跨ぐ変数が見えるので、`Lint/UselessAssignment` を止めずに、本当に使わない `count` だけを検出できる
  - ただし空の `else` の `Style/EmptyElse` は出ない（スライド 15 で回収する）
- スライド 7 の見逃しは、0.8 系ではどれも検出される（`Lint/UnusedBlockArgument`、`Style/NegatedIf`、`Lint/Syntax`）
- → 「改善は進んでいる」

## 3. それでも残る 4 つの問題（3:30）

### 10. 見逃しは減ったが…

- 文書全体方式で、タグを跨ぐ見逃しは減った。しかし、スライド 8 の Ruby には ERB の情報（HTML、タグの区切り、ERB 風の書き方、ERB のレイアウト）が残っていない
- そのため cop は、ERB として正しいものと直すべきものを区別できない。cop をそのまま動かすと、正しい ERB にも指摘が出る（誤検知）
- この問題は、どのツールの実装かによらず、HTML を空白にして 1 本の Ruby にする方式そのものから来る
- 問題は 4 つに分けられる。前半 2 つは変換で生まれるもの、後半 2 つは ERB と Ruby の書き方の違いによるもの
  1. 消えた HTML が産む指摘
  2. タグ変換への指摘
  3. ERB 風の書き方への指摘
  4. レイアウトへの指摘
- ツールがこれにどう対処しているかは、スライド 15 でまとめて扱う
- スライド 11〜14 の指摘は、rubocop-erb 0.8 系から ERB 向けの cop の除外を外した設定（`bin/lint rubocop-erb-0.8-noexclude`）で実測したもの
- 出典: [erb-and-rubocop.md 3 章](../research/erb-and-rubocop.md#3-4-つの分類)

### 11. 消えた HTML が産む指摘

```erb
<% if morning? %>
  Good morning, <%= user.name %>
<% else %>
  Hello, <%= user.name %>
<% end %>
```

↓

```ruby
   if morning?  ;
                    user.name  ;
   else  ;
             user.name  ;
   end  ;
```

- HTML を空白にすると、HTML だけが違う分岐が同じに見える
  - 例: 上の ERB に `Lint/DuplicateBranch`（両方の分岐が同じ）が出る。挨拶が違うので誤検知
- 変換後の Ruby では、ERB として正しいものと直すべきものが同じ形になる。cop には見分けられない

| ERB として正しい（誤検知になる） | 直すべき（指摘したい） |
|---|---|
| 分岐ごとに挨拶が違う（上の ERB） | 両方の分岐が `<%= user.name %>` だけ（`Lint/DuplicateBranch`） |

- 出典: [comparison.md 5.2 節](../research/comparison.md#52-erb-として正しいものと直すべきものの区別)の `cases/marker/duplicate_branch_*`

### 12. タグ変換への指摘

```erb
<div class="<% if admin? %>admin<% end %>">
```

↓

```ruby
               if admin?  ;        end  ;
```

- 区切りの位置に変換で書いた `;` や空白に、cop が反応する
  - 例: よく見かける 1 行の `if` に、`Style/IfWithSemicolon`（`if admin?;` を三項演算子にせよ）、`Style/Semicolon`、`Layout/ExtraSpacing` が出る。`;` も空白も書き手が書いたものではない
- 一方で、同じ cop はタグの中に書いた本当の問題も指摘する
  - 例: `<%= render    partial:  "form" %>` の余分な空白（`Layout/ExtraSpacing`）
- cop から見ると、変換で書いた空白と書き手が書いた空白は区別できない
- 出典: `cases/control_flow/attr_if`

### 13. ERB 風の書き方への指摘

```erb
<%= link_to(user_path(user)) do %>Profile<% end %>
```

- Ruby の規範で、ERB の自然な書き方を直させる。変換をどう工夫しても、ERB の構文で決まる形なので残る
  - `Style/BlockDelimiters`: 1 行のブロックは `{ … }` にせよ → `<%= link_to(user_path(user)) { %>Profile<% } %>` は、ERB では避ける書き方（herb-lint の `erb-prefer-do-end-blocks`）
  - `Style/SingleLineDoEndBlock`: 複数行にせよ → 従うと、リンクの文字列の前後に改行と空白が入る（`<a href="/users/1">\n  Profile\n</a>`）
- 出典: [erb-and-rubocop.md 6 章](../research/erb-and-rubocop.md#6-erb-の書き方に合わない指摘)、`cases/control_flow/single_line_link_to`

### 14. レイアウトへの指摘

- ERB の中の Ruby の位置は、Ruby の構造ではなく、開始タグの幅と HTML の構造で決まる
- 開始タグの幅: `<%=` は 4 文字、`<%` は 3 文字なので、`form_with` と `end` は必ず 1 文字ずれる（`Layout/BlockAlignment`）

```erb
<%= form_with model: @user do |f| %>
  <%= f.text_field :name %>
<% end %>
```

- HTML の入れ子: インデントは HTML の入れ子に従うので、`render` が `if` から 5 文字下がる（`Layout/IndentationWidth`）

```erb
<% if admin %>
  <div class="admin">
    <%= render "admin" %>
  </div>
<% end %>
```

- どちらも ERB として正しい書き方なので誤検知。一方で、同じ Layout の cop は 1 つのタグの中の Ruby の配置（複数行の `link_to` の引数の揃えなど）も検査する
- 出典: [erb-and-rubocop.md 7 章](../research/erb-and-rubocop.md#7-配置への指摘)、`cases/control_flow/form_block`、`cases/style/html_nesting`

### 15. rubocop-erb 0.8 系の戦略: cop の除外

- rubocop-erb 0.8 系は、4 つの問題による誤検知を避けるために、cop を除外した（65 個）
- その副作用で、本来検出したい問題も見逃す
- 例: `Lint/EmptyConditionalBody`（本文が空の `if`）

| ERB として正しい | 本当に空（直すべき） |
|---|---|
| `<% if foo %>`⏎`  hello`⏎`<% end %>` | `<% if foo %>`⏎`<% end %>` |
| 除外しないと誤検知（`hello` が空白になり、本文が空に見える） | 除外しないと検出できる |
| 0.8 系: 出ない | 0.8 系: 出ない（見逃す） |

- 左の誤検知を避けるための除外が、右の本当の問題まで見えなくしている。スライド 3 の空の `else` に `Style/EmptyElse` が出ないのも、同じ理由
- 出典: [comparison.md 4.2 節](../research/comparison.md#42-rubocop-erb-08-系)、[5.2 節](../research/comparison.md#52-erb-として正しいものと直すべきものの区別)の `cases/marker/empty_conditional_*`。上の 2 つの ERB を、0.8 系と除外を外した 0.8 系（`rubocop-erb-0.8-noexclude`）にかけた結果

## 4. tk0miya-rubocop-herb: Ruby パートの lint の精度を上げる（3:30）

### 16. 文書全体方式の精度を上げる

- 文書全体方式で、誤検知も見逃しも減らすために、RuboCop のプラグイン rubocop-herb（tk0miya/rubocop-herb）を作った
- 3 つのアプローチ
  1. `<%=` と HTML を Ruby に残す（スライド 17）
  2. 変換で書いた文字への指摘を捨てる（スライド 18）
  3. タグの中に書いたコードだけを検査する（スライド 19）

### 17. 消えた HTML が産む指摘: `<%=` と HTML を Ruby に残す

- スライド 11 の ERB は、次の Ruby になる（行末の空白は省略）

```erb
<% if morning? %>
  Good morning, <%= user.name %>
<% else %>
  Hello, <%= user.name %>
<% end %>
```

↓

```ruby
   if morning?;
  _a;           _ = user.name;
   else;
  _a;    _ = user.name;
   end;
```

- 変換のルールを変えて、ERB の意味を Ruby の上に残す
  - HTML のタグは `div;` や `span;` に、テキストは `_a;` に変換する → 「本文がある」ことが見える
  - 識別子は位置ごとに別の名前として扱う → HTML がある分岐どうしは、別の分岐に見える
  - `<%=` は代入文（`_ =`）に変換する → 「値を出力に使う」という意味が残る
- これにより、次の誤検知がなくなる
  - `Lint/DuplicateBranch`: 挨拶が違う上の ERB に出ない
  - `Lint/EmptyConditionalBody`、`Style/EmptyElse` など: HTML だけの本文が空に見えない（スライド 15 の `hello`）
  - `Lint/Void`: `<%= total %>` が値を捨てる式（`total`）に見えない
- 直すべき側（両方の分岐が `<%= user.name %>` だけ、本当に空の `if`）は、これまでどおり検出する
- 出典: [tk0miya-rubocop-herb.md 2.1 節、3.1 節](../research/tk0miya-rubocop-herb.md#2-erb-から-ruby-への変換)、`cases/marker/duplicate_branch_*`、`cases/marker/empty_conditional_*`、`cases/variables/cross_tag_variables`

### 18. タグ変換への指摘: 変換で書いた文字への指摘を捨てる

- 原因として、変換例を上に小さく置く

```erb
<p><%= link_to "Home",  root_path %></p>
```

↓ 変換

```ruby
p; _ = link_to "Home",  root_path;  p;
```

- RuboCop は、変換後の Ruby に 6 件の指摘を出す。そのうち、ERB タグの中に収まる指摘だけを報告し、変換で書いた文字（`p;`、タグの終わりの `;`、区切りの位置の空白）への指摘は捨てる。cop は止めない
- 図（スライドの中心）: 指摘がフィルタされる様子
  1. ERB と変換後の Ruby を、等幅で位置を揃えて上下に並べる
  2. ERB タグの中身（`link_to "Home",  root_path`）の範囲に、「タグの中」の色の帯を引く
  3. 6 件の指摘を、反応した文字の位置にマーカーで置く
  4. 帯の外の 5 件（`p;` の `;` が 2 つ、補った `;`、`%>` の位置の空白、行末の空白）はグレーにして取り消し線を引く。帯の中の 1 件（`"Home",  root_path` の余分な空白、`Layout/ExtraSpacing`）だけを強調色で残す
  5. 「指摘 6 件 → タグの中の 1 件だけ報告」と要約する
- 出典: [tk0miya-rubocop-herb.md 5.2 節](../research/tk0miya-rubocop-herb.md#52-変換で書いた文字への指摘を除く-cop)、`cases/output/spacing_in_tag`

### 19. ERB 風の書き方・レイアウトへの指摘: タグの中に書いたコードだけを検査する

- ERB 風の書き方とレイアウトへの指摘は、変換をどう工夫しても残る。形が ERB の構文（タグに跨がる構造、開始タグの幅、HTML の入れ子）で決まるから
- そこで、ERB の構文で形が決まる部分（タグに跨がる構造）では、その行だけで cop を止める。書き手が 1 つのタグの中に書いた Ruby は検査を続ける

ERB 風の書き方:

```erb
<%# タグに跨がる 1 行のブロック: ERB の構文で決まる → 指摘しない %>
<%= link_to(user_path(user)) do %>Profile<% end %>

<%# 1 つのタグの中に 1 行で書いたブロック: 書き手が書いた → Style/BlockDelimiters、Style/SingleLineDoEndBlock %>
<%= link_to(user_path(user)) do "Profile" end %>
```

レイアウト:

```erb
<%# タグに跨がるブロック: <%= と <% の幅で end がずれる → 指摘しない %>
<%= form_with model: @user do |f| %>
  <%= f.text_field :name %>
<% end %>

<%# 1 つのタグの中の引数の揃え: 書き手が書いた → Layout/ArgumentAlignment %>
<%= link_to "Profile",
      user_path(user),
        class: "btn" %>
```

- 0.8 系は、タグに跨がる 1 行のブロックに誤検知を出し、Layout の cop を 37 個除外しているので引数の揃えも見逃す
- 問題を解決したのではなく、ERB 特有の部分を検査の対象から外した。ただし、止める範囲は ERB の構文で決まる部分だけなので、cop をまとめて除外するより見逃しが少ない
- 図: ERB のコメントの中に `%>` は書けないので、スライドではコメントではなく注釈の吹き出しにする
- 出典: [tk0miya-rubocop-herb.md 5.2 節、5.3 節](../research/tk0miya-rubocop-herb.md#5-erb-で止めている-cop出典)、`cases/control_flow/single_line_link_to`、`cases/control_flow/single_line_block_in_tag`、`cases/control_flow/form_block`、`cases/style/argument_alignment`

### 20. Before / After（rubocop-erb 0.8 系と並べる）

- スライド 3 の ERB をもう一度見せる

| ツール | `Lint/UselessAssignment` | `Style/NilComparison` | `Style/EmptyElse` |
|---|---|---|---|
| rubocop-erb 0.8 系 | 出る | 出る | 出ない |
| tk0miya-rubocop-herb | 出る | 出る | 出る |

- → tk0miya-rubocop-herb では、3 件すべてが出る
- ファイル全体で除外する cop は 9 個（0.8 系は 65 個）
- 出典: [comparison.md 5.2 節](../research/comparison.md#52-erb-として正しいものと直すべきものの区別)

## 5. Ruby パートから ERB ファイル全体へ（0:45）

### 21. HTML パートの検査も rubocop に統合する

- rubocop-erb は、ERB の Ruby パートだけを検査する。HTML パートを検査するには、別に herb-lint を実行する必要がある
- tk0miya/rubocop-herb は、herb-lint と herb-format を内部で実行する
  - HTML パートの検査は herb-lint（`Herb/Linting` cop）
  - HTML パートの整形は herb-format（`Herb/Formatting` cop）
- `rubocop` を実行するだけで、HTML + ERB を lint と整形できる → タイトルの "Unified Ecosystem"
- 図: 1 つの ERB が、Ruby パートは RuboCop、HTML パートは herb-lint / herb-format に分かれ、`rubocop` の 1 つの出力に合流する
- 出典: [tk0miya-rubocop-herb.md 7 章](../research/tk0miya-rubocop-herb.md#7-tk0miya-rubocop-herb-の-cop)

## 6. autocorrect の歩み（1:15）

### 22. タグ単位 → 文書全体 → 修正後の ERB の検査

| 時代 | autocorrect |
|---|---|
| タグ単位（erb_lint、rubocop-erb 0.7 系） | テンプレートを壊す。erb_lint は `<%=` を消して `# frozen_string_literal: true` を HTML に入れる。0.7 系は `<%= count -1 %>` を `count(-1)` に、`<% if user && user.admin? %>` を `user&&.admin?`（構文エラー）にする |
| 文書全体（rubocop-erb 0.8 系） | 修正の範囲が 1 つのタグの Ruby に収まらない修正を捨てる。検証用 ERB でも実際のビューでも HTML は変わらない。ただし範囲しか見ないので、`<%= cache 'fragment' do`⏎` %>` のようにタグの中に改行が入る修正は通る |
| tk0miya-rubocop-herb | 修正を元の ERB に当ててみて、HTML が変わる・出力タグの数が変わる・Herb のパースエラーが増える修正を捨てる。捨てた offense は「autocorrect できない」として指摘だけ残す |

- 出典: [comparison.md 5.3 節](../research/comparison.md#53-autocorrect実測)

### 23. 修正後の ERB を検査する

- 問題: Ruby では空白でも、ERB では区切りや HTML の部分を corrector が書き換える
  - 例: `Lint/Void` が `<% 1 %>` の `1` を左の空白ごと消す → `<% ` も消え、` %>` だけが残る
- ERB の区切りまで消す修正は、タグの中身に収まるよう切り詰めてから検査する。`<% 1 %>` は `<% %>` になり、空のタグを `Herb/EmptyErbTag` が行ごと消す（Ruby ファイルで文が消えるのと同じ結果）
- cop を個別に除外しなくても、未知の cop の壊れ方も止められる
- 確実でない修正はせず、指摘だけ残す（誤検知ゼロを最優先）

## 7. 現状とまとめ（1:15）

### 24. 現状と課題

- できていること: RuboCop の cop の autocorrect は、検証用 ERB でも実際のビュー 333 ファイルでもテンプレートを壊さなかった
- 課題
  - 問題ごとに細かく対策を実装しているので、RuboCop と密結合になっている。変換で書いた文字への指摘を捨てる cop が 22 個、行単位で止める cop が 20 個あり、どれも cop ごとの誤検知の形に合わせている。RuboCop の更新や新しい cop のたびに追従が要る
  - HTML のテキストを `_a;` に変換するには、3 文字以上のテキストが必要。短いテキストには対応しておらず、空白のままになるので、空白にする方式と同じ誤検知が残る。例: `<% if user %>`⏎`  |<% user.touch %>`⏎`<% end %>` の `|` が見えず、`Style/SafeNavigation`（`&.` にせよ）が出る（`cases/marker/safe_navigation_short`）
  - `Herb/Linting` が適用する herb-lint の修正は検査しない。`erb-comment-syntax` の修正が複数行のタグのコードをコメントにするバグも、`rubocop -a` で適用される
- 制約: herb-lint / herb-format は TypeScript（Node.js）製なので、`Herb/Linting` / `Herb/Formatting` cop が Node.js の子プロセスで起動する。Node.js と `@herb-tools/linter`（整形には `@herb-tools/formatter`）が必要
- 今後: Herb の linter / formatter を Rust で書き直す計画がある（動くプロトタイプあり、未リリース）。実現すれば、子プロセスを介さずに herb-lint / herb-format を呼べ、Node.js も要らなくなる
- 出典: [v0.9 のリリース記事](https://herb-tools.dev/blog/whats-new-in-herb-v0-9)、[herb#1239 のコメント](https://github.com/marcoroth/herb/issues/1239#issuecomment-4013290572)

### 25. まとめ

- タグ単位の lint は、文脈を失うので見逃し・誤検知・壊れる autocorrect が起きていた
- 文書全体方式への移行で、タグを跨いで検査できるようになった（rubocop-erb 0.8 系）
- それでも `<%=` と HTML の意味が消えるため、誤検知か見逃しの二択が残る
- tk0miya-rubocop-herb は、ERB の意味を Ruby に残し、書き手が書いたコードだけを検査することで、その先を試している
- さらに、`rubocop` をフロントエンドに、Ruby の lint、HTML + ERB の lint と整形を 1 つにまとめる
- 今こそ、ERB でもモダンな開発を
- リポジトリの URL

## 発表までに決めること・確かめること

- **プロポーザルとの差**: プロポーザルは「フォーマット」「Ruby LSP」「Steep」を実演すると書いているが、トークは lint を主軸にする。フォーマット・LSP・Steep を付け足すかは、構成の分量と時間の余裕を見て決める。プロポーザルの成果物に挙げた herb-tools-ruby は、Rust 版 Herb の計画を受けて開発を止めたので扱わない
- **gem 名**: rubygems に Marco Roth 氏の `rubocop-herb` 0.0.1 があり衝突している。まとめで「インストールしてください」と言うなら、公開名を決めておく
