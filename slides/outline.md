# スライド構成（たたき台）

- トーク: Building a Unified Ecosystem for ERB Development Experience（[proposal.md](../proposal.md)）
- 枠: 15 分
- 材料: [research/README.md](../research/README.md)。ツールの比較は [comparison.md](../research/comparison.md)、rubocop-herb の実装は [tk0miya-rubocop-herb.md](../research/tk0miya-rubocop-herb.md)、ERB に合わない cop の 4 分類は [erb-and-rubocop.md](../research/erb-and-rubocop.md)

## 方針

- **lint（RuboCop × ERB）を主軸にする**。ERB の lint の技術的な課題と、ここまでの歩みを話す。フォーマット・型チェック・LSP は、分量と時間の余裕を見て付け足すかを決める
- 聴衆: ERB のツールを導入していない人、導入しているが効果をぼんやりとしか理解していない人。ruby_extractors API などの内部の話はノートに回す
- メッセージは 3 つ
  1. これまでのツール（タグ単位）は不完全だった
  2. 改善が進んでいる（文書全体方式への移行）
  3. tk0miya-rubocop-herb は、残る問題への解決策の萌芽
- 流れ: タグ単位 → 文書全体（rubocop-erb 0.8 系）→ それでも残る 4 つの問題 → tk0miya-rubocop-herb の対策 → autocorrect の歩み → 現状
- 文書全体方式の例は、リリース済みで誰でも使える rubocop-erb 0.8 系にする。Herb 本家の PR（marcoroth/herb#2260）は 1 行だけ触れる
- 0.8 系の扱いは批判ではなく構造の話にする。「`<%=` と HTML の意味がない Ruby では cop が区別できないので、誤検知を出すか、除外して見逃すしかない」。0.8 系の PR 自身が「除外した cop は ERB の文脈を理解させる PR で今後有効に戻す」としているので、その先を試したのが tk0miya-rubocop-herb、とつなげる
- 既存ツールの問題は、どれも検証用 ERB（`research/repro/cases/`）か実際のビュー（rails/rails、kaigionrails/conference-app の 333 ファイル）で実測したものだけを見せる
- 「すべての問題を解決した」とは言わない。変換で生まれる問題は変換で解決し、ERB 特有の問題は RuboCop と ERB のツールの境界を引いて分担する、と 2 段で話す。herb-lint / herb-format の修正は検査しないので、そのバグ（`erb-comment-syntax` が複数行のタグのコードをコメントにする）もそのまま適用される（[comparison.md](../research/comparison.md#発表に向けて)）

## 時間配分

| パート | 枚数 | 時間 |
|---|---|---|
| 0. 導入 | 2 | 0:45 |
| 1. タグ単位の lint は不完全だった | 4 | 2:15 |
| 2. 文書全体へ | 2 | 1:30 |
| 3. それでも残る 4 つの問題 | 5 | 3:15 |
| 4. tk0miya-rubocop-herb | 4 | 4:00 |
| 5. autocorrect の歩み | 2 | 1:30 |
| 6. 現状とまとめ | 2 | 1:30 |
| 合計 | 21 | 14:45 |

## 0. 導入（0:45）

### 1. タイトル

- Building a Unified Ecosystem for ERB Development Experience
- 名前、所属

### 2. 自己紹介

- Steep、rbs_rails へのコントリビュート
- Steep への ERB 対応の提案（[soutaro/steep#1409](https://github.com/soutaro/steep/issues/1409)）
- → 「ERB でも Ruby と同じ開発体験がほしい」が動機

## 1. タグ単位の lint は不完全だった（2:15）

### 3. ERB の中の Ruby に、RuboCop は効いていますか？

```erb
<% if foo == nil %>
  <p>yes</p>
<% else %>
<% end %>
```

- erb_lint（推奨設定）: 0 件
- 同じ内容の `.rb`: `Style/NilComparison`、`Style/EmptyElse`
- ノート: 「ERB の Ruby は、思ったほど lint されていない」と問いかける

### 4. よく使われている ERB の linter

- erb_lint（累計 2,250 万 DL）、rubocop-erb（91 万 DL）
- どちらも、ERB の中の Ruby を RuboCop で検査する
- 数字は rubygems.org の 2026-10-31 時点の累計 DL

### 5. タグ単位で Ruby を取り出す

- ERB タグ 1 つずつを、独立した Ruby として RuboCop にかける（erb_lint、rubocop-erb 0.7 系）
- 図: 同じ ERB が、`if foo == nil` / `end` のような断片の列になる様子
- 失われる文脈
  - 制御構造（`if` 〜 `end` がタグを跨ぐ）
  - 変数スコープ（前のタグで定義した変数）
  - ファイル（タグ 1 つが 1 ファイル扱い）
- ノート: erb_lint は README に "parsed and analyzed independently" と明記。不完全な文（`<% if foo %>` など）は黙ってスキップされ、PR #457 によると断片の約 38%。RuboCop の ruby_extractors API は「1 fragment = 元ファイル上の連続した 1 区間」なので、タグを跨ぐ文を 1 つにまとめられない（rubocop-erb#6）

### 6. 見逃しと誤検知

| ERB | 結果 |
|---|---|
| `<% if foo == nil %>` | erb_lint は見逃す（タグを跨ぐ `if` の条件式が検査されない） |
| `<% if !user.nil? %>` | erb_lint、rubocop-erb 0.7 系とも見逃す（`Style/NegatedIf`） |
| `<% total = items.sum(&:price) %>` + `<%= total %>` | `Lint/UselessAssignment`（誤検知） |
| `<%= "hello" %>` | `Style/FrozenStringLiteralComment` がタグごとに出る |
| `end` の抜け | `Lint/Syntax` を除外しているので気づけない（rubocop-erb 0.7 系） |

- ノート: erb_lint の README は誤検知になる cop の無効化を推奨。rubocop-erb 0.7 系は 53 個の cop を除外している

## 2. 文書全体へ（1:30）

### 7. 文書全体を 1 本の Ruby にする

- rubocop-erb 0.8 系（2026-10-29）が、タグ単位から文書全体の変換に切り替えた（[r7kamura/rubocop-erb#70](https://github.com/r7kamura/rubocop-erb/pull/70)）
- Herb の `Herb.extract_ruby` で、HTML を空白に置き換え、ERB タグの中身を元の位置に残した 1 本の Ruby にする
- Herb 本家でも、同じ方式の rubocop-herb の PR が出ている（[marcoroth/herb#2260](https://github.com/marcoroth/herb/pull/2260)。Draft）
- 図: 同じ ERB が、空白入りの 1 本の Ruby になる様子
- ノート: 文書全体方式そのものは ruumba が先行していたが、普及せず 2021 年にメンテが止まった。質問されたら答える

### 8. タグを跨いで検査できるようになった

- パート 1 の見逃し・誤検知は、0.8 系では起きない
  - `<% if foo == nil %>` に `Style/NilComparison` が出る
  - 前のタグで定義した変数が見えるので、`Lint/UselessAssignment` の誤検知が出ない
  - `Lint/Syntax` を除外しない
- 実際のビュー 333 ファイルで、タグを跨いで読めるようになって新しく見つかる指摘（`Lint/AssignmentInCondition` など）
- → 「改善は進んでいる」

## 3. それでも残る 4 つの問題（3:15）

### 9. `<%=` と HTML が Ruby から消える

```erb
<p><%= count + 1 %> items</p>   →   count + 1
<p><% count + 1 %> items</p>    →   count + 1
```

- `Herb.extract_ruby` は ERB タグの中身以外を空白にするので、出力する `<%=` と出力しない `<%` が同じ Ruby になる。HTML だけの本文と、本当に空の本文も同じ Ruby になる
- cop には区別する手がかりがない → 誤検知を出すか、cop を除外して見逃すかの二択
- 0.8 系は 65 個の cop を除外している（誤検知を避けるため）
- 残る問題は 4 つに分けられる。前半 2 つは変換で生まれるもの、後半 2 つは ERB と Ruby の書き方の違いによるもの
- ノート: 0.8 系の PR は、除外した cop を「ERB の文脈を理解させる PR で今後有効に戻す」としている

### 10. 変換で生まれる問題 1: 区切りへの指摘

- ERB の区切りの位置に変換で書いた `;` や空白に、cop が反応する（`Style/Semicolon`、`Style/IfWithSemicolon`、`Layout/ExtraSpacing` など）
- 0.8 系はこれらを除外する → タグの中に書いた本当の問題も見逃す
  - 例: `<%= render    partial:  "form" %>` の余分な空白（実際のビューで 4 件）

### 11. 変換で生まれる問題 2: HTML が見えないことによる指摘

- HTML を空白にすると、HTML だけの本文が空に見える（`Lint/EmptyConditionalBody`、`Lint/EmptyBlock`、`Style/EmptyElse` など）。`<%=` の値を使わない式と見る（`Lint/Void`、`Style/SymbolProc`）
- 0.8 系はこれらを除外する → ERB として直すべきものも見逃す

| ERB として正しい | 直すべき（0.8 系は見逃す） |
|---|---|
| `<p><%= count + 1 %> items</p>` | `<p><% count + 1 %> items</p>`（`=` の書き忘れ） |
| `<% if user.admin? %>` `You are an administrator.` `<% end %>` | `<% if user.admin? %>` `<% end %>` |

- 出典: [comparison.md 5.2 節](../research/comparison.md#52-erb-として正しいものと直すべきものの区別)の `cases/marker/`

### 12. ERB 特有の問題 1: ERB の書き方に合わない指摘

- Ruby の規範で、ERB の自然な書き方を直させる
- 0.8 系は除外していない → 誤検知が出る
  - `<%= cache "fragment" do %>This bit is cached<% end %>` に `Style/SingleLineDoEndBlock`（実際のビューで 10 件）と `Style/BlockDelimiters`（8 件）
  - `Style/SingleLineDoEndBlock` に従って複数行にすると、出力に改行と空白が入る（`content_for(:title)` が `"Hello B"` から `"  Hello B\n"` に変わる）
  - `Style/BlockDelimiters` が勧める `{ … }` は、ERB では避ける書き方（herb-lint の `erb-prefer-do-end-blocks`）
- 出典: [erb-and-rubocop.md 6 章](../research/erb-and-rubocop.md#6-erb-の書き方に合わない指摘)

### 13. ERB 特有の問題 2: 配置への指摘

- ERB の中の Ruby の位置は、Ruby の構造ではなく、開始タグの幅と HTML の構造で決まる

```erb
<%= form_with(model: user) do |f| %>
  <%= f.text_field :name %>
<% end %>
```

- `<%=` は 4 文字、`<%` は 3 文字なので、`form_with` と `end` は必ず 1 文字ずれる（`Layout/BlockAlignment`）
- インデントは HTML の入れ子に従う。`<pre>` の中では、cop に従ってインデントすると出力が変わる
- 0.8 系は Layout の cop を 37 個除外する → 1 つのタグの中の Ruby の配置（複数行の `link_to` の引数の揃えなど）も見逃す
- 出典: [erb-and-rubocop.md 7 章](../research/erb-and-rubocop.md#7-配置への指摘)

## 4. tk0miya-rubocop-herb（4:00）

### 14. アイデア: ERB の意味を Ruby の上に残す

```erb
<div class="user">
  <%= @user.name %>
</div>
<% if a %>
  text
<% end %>
```

↓

```ruby
div;
  _ = @user.name;
div;
   if a;
  _a;
   end;
```

- Herb の AST（HTML + ERB の統合 AST）から、文字位置を変えずに Ruby を組み立てる
- `<%=` は `_ =` に → 「出力する」という意味が残る
- HTML のタグやテキストは、元の位置に識別子（`div;`、`_a;`）として書き込む → 「本文がある」ことが見える
- RuboCop のプラグインとして、`rubocop` コマンドからそのまま動く。offense の位置も、元の ERB の行がそのまま出る
- 変換結果は rubocop-herb `4cbe906` の `bin/erb2ruby` の出力（行末の空白は省略）
- ノート: ファイル全体を 1 fragment（`offset: 0`）にして、ruby_extractors API の「連続した 1 区間」の制約を回避している。同じプロセス内で動くので、キャッシュ・`--parallel`・`rubocop:disable` がそのまま使える

### 15. 変換で生まれる問題は、変換で解決する

- 区切りへの指摘: 変換で書いた文字（タグの終わりに補った `;`、`_ =`、区切りの位置の空白）への指摘だけを捨てる。cop は止めない
  - → `<% a = 1; b = 2 %>` のようにタグの中に書いた `;` や、`<%= render    partial: … %>` の余分な空白は検出できる
- HTML が見えないことによる指摘: HTML を識別子として書き込むので、cop は止めない
  - → `<% count + 1 %>` の `=` の書き忘れ、本当に空の `if` / `else` は検出できる
- ファイル全体で除外する cop は 9 個（0.8 系は 65 個）
- ノート: 短すぎて識別子を置けないテキスト（`|` 1 文字など）は空白のままなので、本文が HTML の分岐でだけ、この分類の cop を止めている

### 16. ERB 特有の問題は、境界を引いて分担する

- ERB の書き方と配置への指摘は、変換をどう工夫しても残る（ERB と Ruby の書き方の違い、RuboCop と ERB のツールの役割の違い）
- 誤りになる**その行だけ**で cop を止める
  - タグに跨がるブロックの `Style/SingleLineDoEndBlock`、`Style/BlockDelimiters`
  - タグに跨がる `<% end %>` や本文の `Layout/EndAlignment`、`Layout/IndentationWidth` など → 1 つのタグの中の Ruby の配置は検査する
- ERB の書き方や HTML の構造は、ERB のツール（herb-lint / herb-format）に任せる
  - `Herb/Linting` cop が herb-lint の結果を RuboCop の offense として報告する
  - `rubocop` 1 つで、Ruby の lint と HTML / ERB の lint が並ぶ。設定は `.rubocop.yml`、`.herb.yml` や `herb:disable` もそのまま効く
- 図: 1 つの ERB の、タグの中の Ruby は RuboCop、HTML と ERB の構造は herb-lint、という境界
- ノート: HTML のルールを自前で作り直さず、活発に開発されている herb-lint に任せるのがポイント

### 17. Before / After（rubocop-erb 0.8 系と並べる）

| ERB | rubocop-erb 0.8 系 | tk0miya-rubocop-herb |
|---|---|---|
| `<p><% count + 1 %> items</p>` | 見逃す（`Lint/Void` を除外） | `Lint/Void` |
| `<% if user.admin? %><% end %>` | 見逃す（除外） | `Lint/EmptyConditionalBody` |
| `<% if @part && @part.mime_type %>` | 見逃す（除外） | `Style/SafeNavigation` → `@part&.mime_type` |
| `<%= render    partial:  "form" %>` | 見逃す（除外） | `Layout/ExtraSpacing` |
| `<%= cache "fragment" do %>…<% end %>` | `Style/SingleLineDoEndBlock`（誤検知） | 出ない |
| `<p><%= count + 1 %> items</p>` | 出ない | 出ない |

- デモ: 1 つの ERB に 0.8 系と tk0miya-rubocop-herb をかけて並べる（録画にしておく）
- 出典: [comparison.md 5.2 節、5.4 節](../research/comparison.md#5-同じ入力での比較)

## 5. autocorrect の歩み（1:30）

### 18. タグ単位 → 文書全体 → 修正後の ERB の検査

| 時代 | autocorrect |
|---|---|
| タグ単位（erb_lint、rubocop-erb 0.7 系） | テンプレートを壊す。erb_lint は `<%=` を消して `# frozen_string_literal: true` を HTML に入れる。0.7 系は `<%= count -1 %>` を `count(-1)` に、`<% if user && user.admin? %>` を `user&&.admin?`（構文エラー）にする |
| 文書全体（rubocop-erb 0.8 系） | 修正の範囲が 1 つのタグの Ruby に収まらない修正を捨てる。検証用 ERB でも実際のビューでも HTML は変わらない。ただし範囲しか見ないので、`<%= cache 'fragment' do`⏎` %>` のようにタグの中に改行が入る修正は通る |
| tk0miya-rubocop-herb | 修正を元の ERB に当ててみて、HTML が変わる・出力タグの数が変わる・Herb のパースエラーが増える修正を捨てる。捨てた offense は「autocorrect できない」として指摘だけ残す |

- 出典: [comparison.md 5.3 節](../research/comparison.md#53-autocorrect実測)

### 19. 修正後の ERB を検査する

- 問題: Ruby では空白でも、ERB では区切りや HTML の部分を corrector が書き換える
  - 例: `Lint/Void` が `<% 1 %>` の `1` を左の空白ごと消す → `<% ` も消え、` %>` だけが残る
- ERB の区切りまで消す修正は、タグの中身に収まるよう切り詰めてから検査する。`<% 1 %>` は `<% %>` になり、空のタグを `Herb/EmptyErbTag` が行ごと消す（Ruby ファイルで文が消えるのと同じ結果）
- cop を個別に除外しなくても、未知の cop の壊れ方も止められる
- 確実でない修正はせず、指摘だけ残す（誤検知ゼロを最優先）

## 6. 現状とまとめ（1:30）

### 20. 現状と今後

- できていること: RuboCop の cop の autocorrect は、検証用 ERB でも実際のビュー 333 ファイルでもテンプレートを壊さなかった
- 既知の問題: `Herb/Linting` が適用する herb-lint の修正は検査しない。`erb-comment-syntax` の修正が複数行のタグのコードをコメントにするバグも、`rubocop -a` で適用される
- 制約: herb-lint は TypeScript（Node.js）製なので、`Herb/Linting` cop が Node.js の子プロセスで herb-lint を起動する。Node.js と `@herb-tools/linter` が必要
- 今後: Herb の linter / formatter を Rust で書き直す計画がある（動くプロトタイプあり、未リリース）。実現すれば、子プロセスを介さずに herb-lint のルールを呼べ、Node.js も要らなくなる
- 出典: [v0.9 のリリース記事](https://herb-tools.dev/blog/whats-new-in-herb-v0-9)、[herb#1239 のコメント](https://github.com/marcoroth/herb/issues/1239#issuecomment-4013290572)
- ノート: 「構想」ではなく「プロトタイプがある段階」と言える。リリース時期は表明されていないので言わない

### 21. まとめ

- タグ単位の lint は、文脈を失うので見逃し・誤検知・壊れる autocorrect が起きていた
- 文書全体方式への移行で、タグを跨いで検査できるようになった（rubocop-erb 0.8 系）
- それでも `<%=` と HTML の意味が消えるため、誤検知か見逃しの二択が残る
- tk0miya-rubocop-herb は、ERB の意味を Ruby に残し、RuboCop と ERB のツールの境界を引くことで、その先を試している
- 今こそ、ERB でもモダンな開発を
- リポジトリの URL

## 発表までに決めること・確かめること

- **プロポーザルとの差**: プロポーザルは「フォーマット」「Ruby LSP」「Steep」を実演すると書いているが、トークは lint を主軸にする。フォーマット・LSP・Steep を付け足すかは、構成の分量と時間の余裕を見て決める。プロポーザルの成果物に挙げた herb-tools-ruby は、Rust 版 Herb の計画を受けて開発を止めたので扱わない
- **スライド 16 の herb-lint の裏付け**: 「ERB の書き方は herb-lint に任せる」と言うので、対応するルール（`erb-prefer-do-end-blocks` など）を具体的に 1 つ見せられるようにする。HTML の構造に従う配置も、herb-lint / herb-format でどこまで検査できるかを確かめる
- **gem 名**: rubygems に Marco Roth 氏の `rubocop-herb` 0.0.1 があり衝突している。まとめで「インストールしてください」と言うなら、公開名を決めておく
- **デモ**: ライブか録画か。15 分ならスライド 17 の Before / After を録画で見せるのが安全
