# スライド構成（たたき台）

- トーク: Building a Unified Ecosystem for ERB Development Experience（[proposal.md](../proposal.md)）
- 枠: 15 分
- 材料: [existing-erb-linters.md](../research/existing-erb-linters.md)、[report.md](../research/report.md)、[switching-decision.md](../research/switching-decision.md)

## 方針

- 15 分なので、**lint（RuboCop × ERB）に絞る**。フォーマット・型チェック・LSP は最後に「この基盤の先」として 1〜2 枚で触れる
- 話の軸は「Ruby だけを取り出すと、分割しても連結しても文脈が失われる → HTML と Ruby の両方を理解して解析する」
- 既存ツールの問題は、どれも再現例（`research/repro/`）で実測したものだけを見せる
- `-a` でテンプレートを壊す例が残っているうちは「autocorrect が安全」とは言わない（[switching-decision.md](../research/switching-decision.md#発表に向けて)）

## 時間配分

| パート | 枚数 | 時間 |
|---|---|---|
| 0. 導入 | 2 | 0:45 |
| 1. 問題提起 | 3 | 2:00 |
| 2. 既存ツールはなぜ正しく lint できないのか | 7 | 4:15 |
| 3. rubocop-herb | 8 | 5:30 |
| 4. 現状と課題 | 2 | 1:15 |
| 5. この基盤の先・まとめ | 2 | 1:15 |
| 合計 | 24 | 15:00 |

## 0. 導入（0:45）

### 1. タイトル

- Building a Unified Ecosystem for ERB Development Experience
- 名前、所属

### 2. 自己紹介

- Steep、rbs_rails へのコントリビュート
- Steep への ERB 対応の提案（[soutaro/steep#1409](https://github.com/soutaro/steep/issues/1409)）
- → 「ERB でも Ruby と同じ開発体験がほしい」が動機

## 1. 問題提起（2:00）

### 3. Ruby の開発体験は進化した。ERB は？

- Ruby: RuboCop、Steep / Sorbet、Ruby LSP
- ERB: Rails のビューの中心なのに、ツールの支援が薄い
- ノート: 「ERB の中の Ruby に、普段の RuboCop が効いていますか？」と問いかける

### 4. ERB のツールはたくさんある

- erb_lint（累計 2,193 万 DL）、rubocop-erb、ruumba、Herb（herb-lint / herb-format）、erb-formatter、Rufo …
- 図: ツール名を並べたロゴ風のスライド。比較表はパート 4 で出すので、ここでは数を見せるだけ

### 5. でも、このコードに何も言われない

```erb
<% if foo == nil %>
  <p>yes</p>
<% end %>
```

- erb_lint（推奨設定）: 0 件
- 同じ内容の `.rb`: `Style/NilComparison`
- ノート: 「ERB の Ruby は、思ったほど lint されていない」で次のパートへ

## 2. 既存ツールはなぜ正しく lint できないのか（4:15）

### 6. Ruby の取り出し方は 2 系統

- **タグ単位に分割する**: erb_lint、rubocop-erb、better_html、erb-formatter、Rufo
- **HTML を空白で埋めて、文書全体を 1 本の Ruby にする**: ruumba、Herb（構文チェック）、Steep の提案
- 図: 同じ ERB が、左は断片の列、右は空白入りの 1 本の Ruby になる様子

### 7. タグ単位: 3 つの文脈が失われる

- 制御構造（`if` 〜 `end` がタグを跨ぐ）
- 変数スコープ（前のタグで定義した変数）
- ファイル（タグ 1 つが 1 ファイル扱い）
- ノート: erb_lint は README に "parsed and analyzed independently" と明記。不完全な文（`<% if foo %>` など）は黙ってスキップされ、PR #457 によると断片の約 38%

### 8. 見逃し・誤検知

| ERB | 結果 |
|---|---|
| `<% if foo == nil %>` / `<% if !user.nil? %>` | 見逃す（条件式が検査されない） |
| `<% name = "Alice" %>` + `<%= name %>` | `Lint/UselessAssignment`（誤検知） |
| `<%= "hello" %>` | `Style/FrozenStringLiteralComment` がタグごとに出る |

- ノート: README は誤検知になる cop の無効化を推奨。rubocop-erb は約 55 cop を除外している

### 9. autocorrect がテンプレートを壊す

- erb_lint: `<%= link_to "x", …%>` → `<%=` が消え、`# frozen_string_literal: true` が HTML に入る
- rubocop-erb: `<%= count -1 %>` → `<%= count(-1) %>`（前のタグのローカル変数が見えない）
- rubocop-erb: `<% if user && user.admin? %>` → `user&&.admin?`（構文エラー）
- ノート: 一番インパクトがあるスライド。Before / After を大きく見せる

### 10. なぜ直せないのか

- RuboCop の ruby_extractors API は「1 fragment = 元ファイル上の連続した 1 区間」
- `if a` / `c` / `end` をまとめて渡しても、offense を元の ERB の位置に戻せない（r7kamura 氏、rubocop-erb#6）
- → タグ単位の方式は API の制約で構造的に解消できない

### 11. 文書全体方式（ruumba）: 別の文脈が失われる

- 制御構造・変数スコープは保たれ、パート 2 の見逃し・誤検知は解消する
- しかし `<%=` の「出力する」という意味と HTML 本文が失われる
  - `<p><%= name %>: <%= count -1 %></p>` → `name` に `Lint/Void`
  - `<% items.each do |item| %><%= item.name %><% end %>` → `Style/SymbolProc`（従うと出力が消える）
  - 本文が HTML だけの `if` → `Lint/EmptyConditionalBody`
- autocorrect は「88 offenses corrected」と表示して 1 ファイルも書き換えない
- 2021 年からメンテ停止

### 12. パート 2 のまとめ

- Ruby だけを取り出すと、**分割しても連結しても**文脈の一部が失われる
- Herb は HTML と Ruby を両方理解しているが、RuboCop はかけていない（herb#356 で要望のまま）
- → 「HTML と Ruby の両方を理解したうえで RuboCop をかける」ツールが必要

## 3. rubocop-herb（5:30）

### 13. アイデア: ERB を「構造化されたドキュメント」として扱う

- Herb の AST（HTML + ERB の統合 AST）から Ruby を組み立てる
- 正規表現ではなく AST なので、`<%-` / `-%>` や属性値の中のタグも扱える
- RuboCop のプラグイン（LintRoller）として、`rubocop` コマンドからそのまま動く

### 14. 変換: 文字位置を変えない

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

- タグの中身は元の位置に、それ以外は空白に（改行は残す）
- `<%=` は `_ =` に → 「出力する」意味が残るので `Lint/Void` / `Style/SymbolProc` の誤検知が出ない
- `<%` `%>` の分の空白があるので `;` を補っても位置がずれない
- 変換結果は rubocop-herb `1483080` の `bin/erb2ruby` の出力（行末の空白は省略）

### 15. HTML も Ruby として見せる

- HTML のタグやテキストも、元の位置に識別子（`div;`、`_a;`）として書き込む
- HTML を空白にするだけだと、`<% if a %>text<% end %>` は空の `if` に見える
  - 空の本文の誤検知（ruumba の `Lint/EmptyConditionalBody`）
  - 入れ子の `if` を `-a` で統合して、間の HTML を消す（`Style/SoleNestedConditional`）
- 識別子を書き込めば、RuboCop から「本文がある」ことが見える
- エラー表示は、識別子を元の HTML に戻した `hybrid_code` で行う
- ノート: 短すぎて識別子を置けないテキストは空白のままなので、HTML だけの本文に対する cop の無効化（スライド 17）も併用する

### 16. RuboCop との連携: ファイル全体を 1 fragment に

- extractor が `[{ offset: 0, processed_source: … }]` を返す
- 文字位置が一致しているので、offense の位置も autocorrect の修正範囲も変換なしで元の ERB に適用できる
- ruby_extractors API の「連続した 1 区間」の制約を、ファイル全体を 1 区間にすることで回避
- 同じプロセス内で動くので、キャッシュ・`--parallel`・formatter・`rubocop:disable` がそのまま使える

### 17. 残る誤検知は ERB の構造を見て抑える

- ファイル全体で除外する cop は 9 個だけ（rubocop-erb は約 55 個）。`Lint/Syntax`、`Lint/UselessAssignment` は除外しない
- それ以外は、誤検知になる**その行だけ**で cop を無効化（19 個）
  - 本文に HTML を含む分岐・ブロック: `Lint/EmptyConditionalBody` など → 本当に空の `else` は検出できる
  - ERB タグに跨がる `<% end %>` や本文: `Layout/EndAlignment`、`Layout/IndentationWidth` など → 1 つのタグの中に書いた Ruby は検査される
- 図: ERB の上に「この行ではこの cop を無効化」を重ねて示す

### 18. Before / After

| ERB | 既存ツール | rubocop-herb |
|---|---|---|
| `<% if foo == nil %>` | 見逃す | `foo.nil?` に修正 |
| `<% if !user.nil? %>` | 見逃す | `unless user.nil?` に修正 |
| `<% name = "Alice" %>` + `<%= name %>` | `Lint/UselessAssignment` | 出ない |
| `<%= count -1 %>` | `count(-1)` に書き換え | `count - 1` に修正 |
| `<% if user && user.admin? %>` | `user&&.admin?` | `user&.admin?` に修正 |
| `<%= item.name %>` in `each` | `Style/SymbolProc` | 出ない |
| `end` の抜け | `Lint/Syntax` を除外 | `Lint/Syntax` を検出 |

- デモ候補: 1 つの ERB に既存ツールと rubocop-herb をかけて並べる（録画にしておく）

### 19. Ruby は RuboCop、HTML は herb-lint

- 役割分担
  - Ruby パート: rubocop-herb の独自実装（Herb の AST → 文字位置を保った Ruby → RuboCop）
  - HTML パート: herb-lint（Herb 本家の linter をそのまま使う）
- `Herb/Linting` cop が herb-lint の結果を RuboCop の offense として報告する
  - `<div><span></div>` → `E: Herb/Linting: [parser-no-errors] Opening tag <span> at (1:6) doesn't have a matching closing tag </span> in the same scope. (MISSING_CLOSING_TAG_ERROR)`
- 設定は `.rubocop.yml`、実行は `rubocop` だけで 2 種類の lint が並ぶ。`.herb.yml` や `herb:disable` もそのまま効く
- 図: 1 つの ERB が Ruby パートと HTML パートに分かれ、RuboCop の 1 つの出力に合流する
- ノート: HTML のルールを自前で作り直さず、活発に開発されている herb-lint に任せるのがポイント

### 20. いまは子プロセス、将来は Rust 版 Herb

- 現在: herb-lint は TypeScript（Node.js）製なので、Ruby から直接は呼べない
  - `Herb/Linting` cop が Node.js の子プロセスで herb-lint を起動する
  - プロセスは RuboCop のプロセスごとに 1 つだけ起動し、全ファイルで使い回す
  - 制約: Node.js と `@herb-tools/linter` が必要。herb-lint の autocorrect には未対応
- 将来: Marco Roth 氏が Herb の linter / formatter を Rust で書き直そうとしている（[herb-rust.md](../research/herb-rust.md)）
  - 狙いは「Ruby と JavaScript の両方から使える、同じ API の単一の実装」（v0.9 のリリース記事）
  - 動くプロトタイプはあるが、未マージのブランチにあり、まだリリースされていない
  - 実現すれば、子プロセスを介さずに rubocop-herb から herb-lint のルールを呼べ、Node.js も要らなくなる
  - → Ruby も HTML も、rubocop-herb 経由で 1 つのプロセスで lint できる
- 図: 現在（RuboCop → 子プロセス → Node.js の herb-lint）と将来（RuboCop → Rust 製 linter）の 2 段
- 出典: [v0.9 のリリース記事](https://herb-tools.dev/blog/whats-new-in-herb-v0-9)、[herb#1239 のコメント](https://github.com/marcoroth/herb/issues/1239#issuecomment-4013290572)
- ノート: 「構想」ではなく「プロトタイプがある段階」と言える。リリース時期は表明されていないので言わない

## 4. 現状と課題（1:15）

### 21. 比較表

| ツール | HTML 構造 | Ruby の構文 | Ruby のスタイル | タグを跨いだ解析 | autocorrect |
|---|---|---|---|---|---|
| erb_lint | ○ | △ | △ | × | △ |
| rubocop-erb | × | △ | △ | × | △ |
| ruumba | × | ○ | △ | ○ | △ |
| herb-lint | ◎ | ◎ | × | ○ | ○ |
| **rubocop-herb** | ◎ | ○ | ○ | ○ | △ → ○ にしたい |

### 22. 残っている課題（正直に）

- `-a` で文の削除が `<%` ごと消す（`Lint/Void`, `Lint/UselessAssignment`）
- 原因: Ruby では空白でも、ERB では区切りの部分を corrector が書き換える
- 方針: 修正範囲が ERB タグの中身の外にかかる修正を捨てる（`Team#collate_corrections` で cop ごとに検査）
- ノート: 発表までに直せていれば「直した」話に差し替える。1 枚で「どう直したか」を見せられると強い

## 5. この基盤の先・まとめ（1:15）

### 23. この基盤の先

- Ruby LSP: エディタで ERB にも RuboCop の診断
- Steep: 同じ「文字位置を保った Ruby」で ERB の型チェック（steep#1409）
- ノート: 時間が押したらこのスライドは 30 秒で流す

### 24. まとめ

- 既存ツールは Ruby だけを取り出すため、分割しても連結しても文脈が失われる
- rubocop-herb は Herb の AST で HTML と Ruby の両方を理解し、文字位置を保ったまま RuboCop にかける
- HTML は herb-lint に任せ、`rubocop` 1 つで 2 種類の lint を実行する
- いま使っているツールからの移行: ruumba / rubocop-erb → 置き換え、erb_lint → Ruby 部分だけ移して併用、herb-lint → 追加
- 今こそ、ERB でもモダンな開発を
- リポジトリの URL

## 発表までに決めること・確かめること

- **プロポーザルとの差**: プロポーザルは「フォーマット」「Ruby LSP」「Steep」を実演すると書いているが、15 分では lint で手一杯。パート 5 で構想として触れる形でよいか。プロポーザルの成果物に挙げた herb-tools-ruby は、Rust 版 Herb の計画を受けて開発を止めたので扱わない
- **autocorrect の課題**: 直してから発表するか、課題として見せるか（スライド 22 の扱いが変わる）
- **Marco Roth 氏との調整**: 氏は Rust 製 linter を RuboCop に公開する RuboCop プラグインのプロトタイプも作っていて、herb#475 で「調整が必要」と述べている。rubygems の `rubocop-herb` / `herb-linter` 0.0.1 もこの計画のためと思われる（[herb-rust.md](../research/herb-rust.md)）。スライド 20 で氏の計画に触れる前に、役割分担（Ruby パートはこちら、HTML パートは Rust 製 linter）と gem 名について話しておきたい
- **gem 名**: rubygems に Marco Roth 氏の `rubocop-herb` 0.0.1 があり衝突している。まとめで「インストールしてください」と言うなら、公開名を決めておく
- **デモ**: ライブか録画か。15 分ならスライド 18 の Before / After を録画で見せるのが安全
