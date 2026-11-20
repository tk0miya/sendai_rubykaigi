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
- スライド 4 の ERB をトークを通して使う。スライド 11（rubocop-erb 0.8 系）とスライド 29（tk0miya-rubocop-herb）でもう一度見せ、検出できる指摘が erb_lint の 0 件・rubocop-erb 0.7 系の 1 件 → 0.8 系の 2 件 → 3 件と増えていくことを示す
- 見出しだけのスライド（扉）は置かず、フラットに並べる
- 4 つの問題のスライド（14〜19）は、コード例 → 解説（数件の箇条書き）の順に並べる。最初にコード例があったほうが目を引くため
- 流れ: タグ単位 → 文書全体（rubocop-erb 0.8 系）→ 空の `else` の指摘が出ない → それは cop を無効化しているから → なぜ無効化するのか: 原理的に起きる 4 つの問題 → cop の無効化と副作用 → tk0miya-rubocop-herb の対策（ここまでが Ruby パートの lint の精度の話）→ rubocop-erb との比較 → rubocop-herb の課題 → その他の機能（herb-lint / herb-format との連携、autocorrect）→ まとめ
- 文書全体方式の例は、リリース済みで誰でも使える rubocop-erb 0.8 系にする。Herb 本家の PR（marcoroth/herb#2260）は扱わない
- 0.8 系の扱いは批判ではなく構造の話にする。「`<%=` と HTML の意味がない Ruby では cop が区別できないので、誤検知を出すか、除外して見逃すしかない」。0.8 系の PR 自身が「除外した cop は ERB の文脈を理解させる PR で今後有効に戻す」としているので、その先を試したのが tk0miya-rubocop-herb、とつなげる
- 既存ツールの問題は、どれも検証用 ERB（`research/repro/cases/`）か実際のビュー（rails/rails、kaigionrails/conference-app の 333 ファイル）で実測したものだけを見せる
- 「すべての問題を解決した」とは言わない。変換で生まれる問題は変換で解決し、ERB 特有の問題は ERB の構文で決まる部分を検査の対象から外す（書き手が 1 つのタグの中に書いたコードだけを検査する）、と 2 段で話す。herb-lint / herb-format との統合は、4 つの問題とは別のプラスアルファとして話す。herb-lint / herb-format の修正は検査しないので、そのバグ（`erb-comment-syntax` が複数行のタグのコードをコメントにする）もそのまま適用される（[comparison.md](../research/comparison.md#発表に向けて)）

## 時間配分

| スライド | 内容 | 時間 |
|---|---|---|
| 1〜2 | 導入 | 0:45 |
| 3〜8 | タグ単位の lint は不完全だった | 2:15 |
| 9〜12 | rubocop-erb 0.8: 文書全体へ | 1:45 |
| 13〜22 | 文書全体方式と誤検知 | 4:30 |
| 23〜31 | tk0miya-rubocop-herb: Ruby パートの lint の精度を上げる | 4:00 |
| 32 | その他の機能（herb-lint / herb-format との連携、autocorrect） | 2:00 |
| 33 | まとめ | 1:15 |
| 合計 33 枚 | | 16:30 |

## スライド

### 1. タイトル

- Building a Unified Ecosystem for ERB Development Experience
- 名前、所属

### 2. 自己紹介

- Steep、rbs_rails へのコントリビュート
- Steep への ERB 対応の提案（[soutaro/steep#1409](https://github.com/soutaro/steep/issues/1409)）
- → 「ERB でも Ruby と同じ開発体験がほしい」が動機

### 3. あなたの ERB に RuboCop は効いていますか?

- ERB ファイルに RuboCop を効かせる gem がある
  - erb_lint
  - rubocop-erb
- どちらも、ERB の中の Ruby コードを RuboCop で検査する

### 4. あなたの ERB に RuboCop は効いていますか?

- 次の ERB に erb_lint / rubocop-erb をかけてみる

```erb
<% count = items.size %>
<% if foo == nil %>
  <p>yes</p>
<% else %>
<% end %>
```

### 5. あなたの ERB に RuboCop は効いていますか?

- 次の ERB に erb_lint / rubocop-erb をかけてみる

```erb
<% count = items.size %>
<% if foo == nil %>
  <p>yes</p>
<% else %>
<% end %>
```

- 指摘件数
  - erb_lint: 0 件
  - rubocop-erb: 1 件

### 6. あなたの ERB に RuboCop は効いていますか?

- 次の ERB に erb_lint / rubocop-erb をかけてみる

```erb
<% count = items.size %>
<% if foo == nil %>
  <p>yes</p>
<% else %>
<% end %>
```

- 指摘件数
  - erb_lint: 0 件
  - rubocop-erb: 1 件
- erb_lint / rubocop-erb は取りこぼしがある
  - `Lint/UselessAssignment`
  - `Style/NilComparison`（erb_lint のみ）
  - `Style/EmptyElse`
- 出典: [comparison.md 3.1 節、3.2 節](../research/comparison.md#3-タグ単位の方式)。erb_lint は推奨設定、rubocop-erb は 0.7 系の結果

### 7. なぜ取りこぼすのか

- ERB タグごとに Lint をかけている
  - `count = items.size`
  - `if foo == nil`
  - `else`
  - `end`
- 制御構文が入っていた場合の動きは、ツールごとに異なる
  - erb_lint: タグごと無視
  - rubocop-erb: 制御構文（`if`、`else`、`do |xx|` など）を削除して Lint
- 図: スライド 4 の ERB が、タグごとの断片の列になる様子
- 出典: erb_lint 0.9.0 の `lib/erb_lint/linters/rubocop.rb`（末尾の `do |x|` を削り、`valid_syntax?` が偽ならスキップ）、rubocop-erb 0.7.2 の `lib/rubocop/erb/keyword_remover.rb`（先頭の `if` / `else` / `end` などと末尾の `then` / `do |x|` を削り、空になったタグは検査しない）

### 8. なぜ取りこぼすのか

- Lint の際に文脈が失われている
  - 制御構造
  - 変数スコープ
  - HTML
- スライド 4 の取りこぼしとの対応
  - `Style/NilComparison`、`Style/EmptyElse`: 制御構造（`if` 〜 `end` がタグをまたぐ）
  - `Lint/UselessAssignment`: 変数スコープ（後ろのタグで使う変数まで指摘されるので、erb_lint の README は cop の無効化を推奨し、rubocop-erb 0.7 系は除外している）
- HTML は文書全体方式でも失われ、スライド 16 の誤検知（HTML 消去による問題）につながる
- 出典: [comparison.md 3.1 節、3.2 節](../research/comparison.md#3-タグ単位の方式)

### 9. rubocop-erb-0.8

- 先日 rubocop-erb 0.8 がリリースされた
  - Change ERB=>Ruby Processing Strategy
- ERB の処理方式が大きく変わった
  - これまで: ERB タグ単位で Lint
  - これから: ERB ファイルを Ruby に変換し、文書全体で Lint
- 出典: [r7kamura/rubocop-erb#70](https://github.com/r7kamura/rubocop-erb/pull/70)（0.8.0、2026-10-29 リリース）。「Change ERB=>Ruby Processing Strategy」はこの PR のタイトル

### 10. rubocop-erb-0.8

- HTML を空白に置き換え、ERB タグの中身を元の位置に残して、ファイル全体を 1 本の Ruby にする
- スライド 4 の ERB は、次の Ruby になる（行末の空白は省略）

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


### 11. rubocop-erb-0.8

- 文書全体で Lint することで情報が増えた
- 指摘件数が増加: 1 件 → 2 件
  - 未使用変数を検出（`Lint/UselessAssignment`）
- スライド 4 の ERB での結果。1 件目は `Style/NilComparison`
- 出典: [comparison.md 4.2 節](../research/comparison.md#42-rubocop-erb-08-系)

### 12. rubocop-erb-0.8

- 文書全体で Lint することで情報が増えた
- 指摘件数が増加: 1 件 → 2 件
  - 未使用変数を検出（`Lint/UselessAssignment`）
- else ブロックが空という指摘は出てこない（`Style/EmptyElse`）
  - rubocop-erb-0.8 では 65 個の cop を無効化している
- 出典: [comparison.md 4.2 節](../research/comparison.md#42-rubocop-erb-08-系)（`config/default.yml` で 65 個の cop を `**/*.erb` から除外）

### 13. なぜ cop を無効化するのか

- Ruby コードへの変換により、誤検知を産んでいる
- rubocop-erb は誤検知を避けるため、cop を無効化している
- 発生しうる問題
  1. コード変換による問題
  2. HTML 消去による問題
  3. ERB 風の Ruby の書き方の問題
  4. レイアウトに対する指摘
- スライド 14〜19 の指摘は、rubocop-erb 0.8 系から ERB 向けの cop の除外を外した設定（`bin/lint rubocop-erb-0.8-noexclude`）で実測したもの
- 出典: [erb-and-rubocop.md 3 章](../research/erb-and-rubocop.md#3-4-つの分類)

### 14. コード変換による問題 (1)

```erb
<%= link_to "Home", root_path %>
```

↓

```ruby
    link_to "Home", root_path  ;
```

- 変換で生まれたスペースやセミコロンに対する指摘
  - `Layout/ExtraSpacing`: `;` の前の 2 つの空白
  - `Style/Semicolon`: 文の終わりの `;`
- 出典: `bin/lint rubocop-erb-0.8-noexclude` で実測（`Layout/SpaceBeforeSemicolon` も出る）。同じ形の検証用 ERB は `cases/output/link_to_class`、`cases/output/string_literal`

### 15. コード変換による問題 (2)

```erb
<h1><%= @title %></h1>
<p><%= @description %></p>
```

↓

```ruby
        @title  ;
       @description  ;
```

- `<%=` で出力している式に、`Lint/Void`（値を使わない式）が出る
  - 変換で `<%=` が消え、`@title` は値を捨てる文に見える
- 出典: `bin/lint rubocop-erb-0.8-noexclude` で実測（最後の `@description` には出ない）。同じ形の検証用 ERB は `cases/marker/void_ok`。実際のビュー 333 ファイルでも、同じ変換（`Herb.extract_ruby`）をする herb-rubocop-herb で 50 件出て、すべて `<%= event.name %>` などの出力する式への誤検知（[comparison.md 5.4 節](../research/comparison.md#54-実際のビュー実測)）

### 16. HTML 消去による問題

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
- 出典: [comparison.md 5.2 節](../research/comparison.md#52-erb-として正しいものと直すべきものの区別)の `cases/marker/duplicate_branch_ok`

### 17. ERB 風の Ruby の書き方の問題

```erb
<%= link_to(user_path(user)) do %>Profile<% end %>
```

- ERB では `{ ... }` より `do`/`end` の方が自然に見える
- Ruby 向けの cop では ERB に不向きなものがある
  - `Style/BlockDelimiters`: 1 行のブロックは `{ … }` にせよ → `<%= link_to(user_path(user)) { %>Profile<% } %>` は、ERB では避ける書き方（herb-lint の `erb-prefer-do-end-blocks`）
  - `Style/SingleLineDoEndBlock`: 複数行にせよ → 従うと、リンクの文字列の前後に改行と空白が入る（`<a href="/users/1">\n  Profile\n</a>`）
- 出典: [erb-and-rubocop.md 6 章](../research/erb-and-rubocop.md#6-erb-の書き方に合わない指摘)、`cases/control_flow/single_line_link_to`

### 18. レイアウトに対する指摘 (1)

```erb
<% if admin %>
  <div class="admin">
    <%= render "admin" %>
  </div>
<% end %>
```

↓

```ruby
   if admin  ;

        render "admin"  ;

   end  ;
```

- HTML パートによって ERB タグの記述位置が変化する
- インデントに対する指摘は誤検知
  - 例: `Layout/IndentationWidth`
- 出典: [erb-and-rubocop.md 7 章](../research/erb-and-rubocop.md#7-配置への指摘)、`cases/style/html_nesting`。変換後の Ruby は行末の空白を省いて表示している

### 19. レイアウトに対する指摘 (2)

```erb
<%= form_with do |f| %>
  <%= f.text_field :name %>
<% end %>
```

↓

```ruby
    form_with do |f|  ;
      f.text_field :name  ;
   end  ;
```

- `form_with` と `end` の位置のズレを指摘される（`Layout/BlockAlignment`）
- ERB の開始タグの文字数によるもので誤検知
- 出典: [erb-and-rubocop.md 7 章](../research/erb-and-rubocop.md#7-配置への指摘)。`bin/lint rubocop-erb-0.8-noexclude` で実測（`Layout/IndentationWidth` も出る）。`model: @user` を付けた同じ形の検証用 ERB は `cases/control_flow/form_block`

### 20. rubocop-erb-0.8 の cop の無効化

- rubocop-erb-0.8 では 65 個の cop を無効化している
- 4 つの問題による誤検知を回避するため
  1. コード変換による問題
  2. HTML 消去による問題
  3. ERB 風の Ruby の書き方の問題
  4. レイアウトに対する指摘
- 出典: [comparison.md 4.2 節](../research/comparison.md#42-rubocop-erb-08-系)

### 21. cop の無効化による副作用 (1)

```erb
<% count = items.size %>
<% if foo == nil %>
  <p>yes</p>
<% else %>
<% end %>
```

- 本来検出したい問題を見逃す
  - `Style/EmptyElse`
- スライド 4 の ERB の再掲
- 出典: スライド 4 の ERB を `research/repro/work/` に置いて実測。0.8 系は `Lint/UselessAssignment` と `Style/NilComparison` だけ。除外を外した 0.8 系（`rubocop-erb-0.8-noexclude`）では、`Style/EmptyElse` が出る一方で、HTML の本文（`<p>yes</p>`）が空に見えて `Lint/EmptyConditionalBody` の誤検知も出る。[comparison.md 5.2 節](../research/comparison.md#52-erb-として正しいものと直すべきものの区別)の `cases/marker/empty_else_*` も同じ

### 22. cop の無効化による副作用 (2)

```erb
<%= link_to "Profile",
      user_path(user),
        class: "btn" %>
```

- 本来検出したい問題を見逃す
- Ruby コード片内のアラート
  - `Layout/ArgumentAlignment`: 複数行のメソッド呼び出しで、引数の揃えがずれている
- 出典: `cases/style/argument_alignment`。0.8 系では出ず、除外を外した 0.8 系と tk0miya-rubocop-herb では 2 行目・3 行目に出る

### 23. さらなる精度を求めて

- 誤検知は抑えたまま、見逃しは減らしたい
  - 誤検知: false positive
  - 見逃し: false negative
- オリジナルの RuboCop プラグインを開発した
  - tk0miya/rubocop-herb
  - （未リリース）

### 24. tk0miya/rubocop-herb

- 文書全体方式を採用
- 検知精度を上げるため、4 つのアプローチを採用
  1. 埋め込みブロックを代入に変換
  2. HTML を Ruby 式に変換
  3. 変換で生まれた文字への指摘を除外
  4. タグをまたいだ構造への指摘を除外

### 25. 埋め込みブロックを代入に変換

```erb
<%= @title %>
<%= @description %>
```

↓

```ruby
_ = @title;
_ = @description;
```

- `<%=` は代入文（`_ =`）に変換する → 「値を出力に使う」という意味が残る
- `Lint/Void`: `@title` が値を捨てる式に見えないので、誤検知が出ない
- 出典: [tk0miya-rubocop-herb.md 2.1 節](../research/tk0miya-rubocop-herb.md#2-erb-から-ruby-への変換)。変換結果は tk0miya-rubocop-herb の `bin/erb2ruby`（行末の空白は省略）。スライド 15 の ERB から HTML を外した形を `research/repro/work/` に置いて実測し、指摘は 0 件（除外を外した 0.8 系では `@title` に `Lint/Void` が出る）

### 26. HTML を Ruby 式に変換

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

- HTML のタグは `div;` に、テキストは `_a;` に変換する
  - さらに AST 上では HTML ごとに別の識別子を与え、区別可能とする
- これにより、次の誤検知がなくなる
  - `Lint/DuplicateBranch`: 挨拶が違う上の ERB に出ない
  - `Lint/EmptyConditionalBody`、`Style/EmptyElse` など: HTML だけの本文が空に見えない（スライド 4 の ERB の `<p>yes</p>`）
- スライド 16 の ERB。変換後の Ruby は行末の空白を省略
- 出典: [tk0miya-rubocop-herb.md 2.1 節、2.3 節、3.1 節](../research/tk0miya-rubocop-herb.md#2-erb-から-ruby-への変換)（AST の書き換えは `RuboCopASTTransformer`。`_a` は `_a__html20` のように元の ERB での位置を付けた名前になる）、`cases/marker/duplicate_branch_*`、`cases/marker/empty_conditional_*`

### 27. 変換で生まれた文字への指摘を除外

```
<p><% @title = 'Home';  @nav = :home %></p>
p;    @title = 'Home';  @nav = :home;  p;
 ~                   ~              ~   ~    : Style/Semicolon
  ~~~                 ~              ~       : Layout/ExtraSpacing
                                         ~~  : Layout/TrailingWhitespace
```

- 変換コードに関わる cop は、ERB タグ内のみ指摘を受け付ける
  - `Style/Semicolon`、`Layout/ExtraSpacing` など（23 個）
- 上の行は ERB、下の行は変換後の Ruby（桁がそろう。行末の空白 2 文字は見えない）。`~` は変換後の Ruby で RuboCop が指摘した位置
- スライド化する際、ERB タグの範囲に赤枠を付け（ERB と Ruby の 2 行にまたがる）、範囲外にグレー枠をオーバーレイするなどして、破棄する指摘を可視化する
- 出典: [tk0miya-rubocop-herb.md 5.2 節](../research/tk0miya-rubocop-herb.md#52-変換で書いた文字への指摘を除く-cop)（対象は `Configuration::VERBATIM_CODE_COPS` の 23 個）。`research/repro/work/` に置いて実測。tk0miya-rubocop-herb の変換後の Ruby（`p;    @title = 'Home';  @nav = :home;  p;  `）を素の RuboCop にかけると、上の 8 件と `Style/FrozenStringLiteralComment` が出る（`Style/FrozenStringLiteralComment` は tk0miya-rubocop-herb がファイル全体で除外）。`<%` を同じ幅の空白に変換するので、変換後の Ruby と ERB の桁はそろう。tk0miya-rubocop-herb はタグの中の 2 件（書き手が書いた `;` と余分な空白）を報告し、ほかに herb-lint の `erb-no-multiple-statements`（1 行のタグに複数の文）を `Herb/Linting` として報告する

### 28. タグをまたいだ構造への指摘を除外

```erb
<%# タグをまたいだブロック定義 → レイアウト問題は指摘しない %>
<%= form_with do |f| %>
  <%= f.text_field :name %>
<% end %>

<%# 1 つのタグで閉じたブロック → レイアウト問題を指摘する（Layout/BlockAlignment） %>
<%= form_with do |f|
      f.text_field :name
    end %>
```

- 制御構造が複数の ERB タグをまたぐ場合の誤検知を減らす
  - レイアウトに対する指摘: Layout 系 7 個（`Layout/BlockAlignment` など）
  - ERB 風の書き方の問題: Style 系 4 個（`Style/BlockDelimiters` など）
- 1 つのタグ内に書いた場合は指摘をする
- 図: ERB のコメントの中に `%>` は書けないので、スライドではコメントではなく注釈の吹き出しにする
- 出典: [tk0miya-rubocop-herb.md 5.3 節](../research/tk0miya-rubocop-herb.md#53-行単位で無効にしている-cop)、`lib/rubocop/herb/erb_parser/disabled_cops_collector.rb`、`cases/control_flow/form_block`（`model: @user` を付けた形。外した形も指摘が出ないことを実測）。1 つのタグで閉じた `form_with` は `research/repro/work/` に置いて実測
  - 下の ERB: tk0miya-rubocop-herb は `Layout/BlockAlignment` の 1 件だけ（`end` は `<%=` の 0 桁目に揃えるべき、という指摘。`end` を 0 桁目に置いた形は 0 件）
  - Layout の 7 個: `BlockAlignment`、`EndAlignment`、`BeginEndAlignment`、`ElseAlignment`、`CaseIndentation`、`RescueEnsureAlignment`、`IndentationWidth`
  - Style の 4 個: `BlockDelimiters`（1 行に書いたブロック）、`IfUnlessModifier`、`Next`（条件分岐）、`WhileUntilModifier`（ループ）。1 つのタグの中に書いた `<% if a; b; end %>` や `<% items.each do |item| concat item.name end %>` には指摘が出る
  - 同じ仕組みで、本文に HTML を含む分岐の `Lint/EmptyConditionalBody` などの 8 個も止めている。これは短いテキストを Ruby 式に変換しないための例外対応で、HTML 消去への対応の主軸はスライド 26 の変換なので、このスライドでは扱わない

### 29. rubocop-herb と rubocop-erb の比較 (1)

```erb
<% count = items.size %>
<% if foo == nil %>
  <p>yes</p>
<% else %>
<% end %>
```

| ツール | `Lint/UselessAssignment` | `Style/NilComparison` | `Style/EmptyElse` |
|---|---|---|---|
| rubocop-erb 0.8 系 | 出る | 出る | 出ない |
| tk0miya-rubocop-herb | 出る | 出る | 出る |

- → tk0miya-rubocop-herb では、3 件すべてが出る
- ファイル全体で除外する cop は 9 個（0.8 系は 65 個）
- スライド 4 の ERB
- 出典: [comparison.md 5.2 節](../research/comparison.md#52-erb-として正しいものと直すべきものの区別)。`research/repro/work/` に置いて実測。tk0miya-rubocop-herb はほかに herb-lint の `erb-no-unused-local-variable`（1 行目）と `erb-no-empty-control-flow`（4 行目）を `Herb/Linting` として報告する（スライド 32 の話題なので表には載せない）

### 30. rubocop-herb と rubocop-erb の比較 (2)

- kaigionrails/conference-app の ERB（76 ファイル）
- rubocop-erb 0.8 系が除外している cop に、妥当な指摘が 2 件ある

| ツール | 指摘 | 誤検知 |
|---|---|---|
| rubocop-erb 0.8 系 | 0 件 | 0 件 |
| tk0miya-rubocop-herb | 2 件 | 0 件 |

- 空のテンプレート（`Lint/EmptyFile`）: 編集画面のテンプレートが 0 バイトで、空のページになる
- 空のブロック（`Lint/EmptyBlock`）: `<%= check_box_tag … do %>` 〜 `<% end %>` の本文が空

- どちらのツールも標準の設定（rubocop-erb 0.8 系は同梱の除外を有効にしたまま）
- 妥当な指摘 2 件の求め方: rubocop-erb 0.8 系の除外を外し、内容に関わる 11 個の cop（`Lint/Void`、`Lint/EmptyBlock`、`Lint/EmptyFile`、`Style/SafeNavigation` など）で出た 33 件を、1 件ずつテンプレートを見て判断した。誤検知は、この 11 個の cop で数えた
- 空のテンプレートは `admin/signage_devices/edit.html.erb`（ルーティングとコントローラーの `edit` はある）、空のブロックは `profile_badges/new.html.erb`
- 出典: [comparison.md 5.4 節](../research/comparison.md#54-実際のビュー実測)。conference-app だけの件数は、`bin/lint rubocop-erb-0.8-noexclude` と `bin/lint tk0miya-rubocop-herb --except Herb/Linting` に `--only <11 個の cop>` を付けて `work/views/conference-app` にかけて実測

### 31. rubocop-herb の課題

- 1〜2 文字の短いテキストでは `_a;` を出力できず、誤検知が残ってしまう
- きめ細かく対応しているので、RuboCop と密結合になっている
  - コード量は rubocop-erb の約 9 倍

- 短いテキスト: `_a;` を置くには、前の空白と合わせて 3 文字（行末なら 2 文字）が必要。行頭や ERB タグの直後から書いた短いテキストは空白のままになり、空白にする方式と同じ誤検知が残る。例: `<% if user %>`⏎`|<% user.touch %>`⏎`<% end %>` の `|` が見えず、`Style/SafeNavigation`（`&.` にせよ）が出る（`cases/marker/safe_navigation_short`）。`Lint/EmptyBlock` などは行単位の無効化でこの穴を塞いでいるが、`Style/SafeNavigation` などは塞いでいない
- 密結合: 変換で書いた文字への指摘を除く cop が 23 個、行単位で止める cop が 21 個あり、どれも cop ごとの誤検知の形に合わせている。RuboCop の更新や新しい cop のたびに追従が要る
- コード量: `lib/` が tk0miya-rubocop-herb は 3,660 行（うち herb-lint / herb-format との連携 701 行）、rubocop-erb 0.8.2 は 386 行
- 出典: [tk0miya-rubocop-herb.md 3.2 節、3.3 節](../research/tk0miya-rubocop-herb.md#32-実装の規模出典)

### 32. tk0miya/rubocop-herb: その他の機能

- herb-lint、herb-format との連携
  - HTML パートの Lint / Format を両ツールで実施
  - RuboCop を実行するだけで、HTML パート、Ruby パートを検査できる
- AutoCorrect に対応
  - 誤修正や破損を防ぐ仕組みを持たせている
  - うまく適用できない場合は修正をスキップし、指摘だけ残す

- herb-lint は `Herb/Linting` cop、herb-format は `Herb/Formatting` cop として実行する。`rubocop` 1 つで HTML + ERB の lint と整形ができることが、タイトルの "Unified Ecosystem" につながる
- 誤修正や破損を防ぐ仕組み: 修正を元の ERB に当ててみて、HTML が変わる・出力タグの数が変わる・Herb のパースエラーが増える修正を捨てる。捨てた offense は「autocorrect できない」として指摘だけ残す。RuboCop の cop の修正は、検証用 ERB でも実際のビューでもテンプレートを壊さなかった
- この仕組みが検査するのは RuboCop の cop の修正だけで、`Herb/Linting` が適用する herb-lint の修正は検査しない（`erb-comment-syntax` の修正が複数行のタグのコードをコメントにするバグも、`rubocop -a` で適用される）
- 出典: [tk0miya-rubocop-herb.md 6 章、7 章](../research/tk0miya-rubocop-herb.md#6-autocorrect-の検査copcorrectionguard)、[comparison.md 5.3 節](../research/comparison.md#53-autocorrect実測)

### 33. まとめ

- かつての gem は見逃しが多かった（タグ単位方式）
- rubocop-erb 0.8 で大きな改善があった（文書全体方式）
- tk0miya/rubocop-herb
  - 4 つのアプローチで誤検知を抑え、見逃しを減らす
  - RuboCop ひとつで ERB 全体を検査する
- 今こそ ERB でもモダンな開発を
- https://github.com/tk0miya/rubocop-herb

## 発表までに決めること・確かめること

- **プロポーザルとの差**: プロポーザルは「フォーマット」「Ruby LSP」「Steep」を実演すると書いているが、トークは lint を主軸にする。フォーマット・LSP・Steep を付け足すかは、構成の分量と時間の余裕を見て決める。プロポーザルの成果物に挙げた herb-tools-ruby は、Rust 版 Herb の計画を受けて開発を止めたので扱わない
- **gem 名**: rubygems に Marco Roth 氏の `rubocop-herb` 0.0.1 があり衝突している。まとめで「インストールしてください」と言うなら、公開名を決めておく
