# ERB linter の検証環境

research の文書で挙げた挙動を確かめるための、検証用 ERB とツールの設定です。
**入力は `cases/` の 1 セットだけ**で、`bin/lint` の第 1 引数でツールを切り替えて同じ入力にかけます。

## 構成

| パス | 内容 |
|---|---|
| `cases/` | 検証用 ERB（75 ファイル）。[ケースの一覧](#ケースの一覧) |
| `plain_ruby/` | 比較用の Ruby。`cases/control_flow/` のいくつかのケースと同じ内容を、普通の Ruby として書いたもの |
| `tools/TOOL/` | ツールごとの `Gemfile` と設定 |
| `package.json`, `.herb.yml` | herb-lint / herb-format（`@herb-tools/linter`、`@herb-tools/formatter`） |
| `bin/lint` | ツールを切り替えて検査する |
| `bin/autocorrect` | `cases/` のコピーに autocorrect をかけ、元との diff を出す |
| `bin/record`, `bin/record-views` | すべてのツールの結果を `results/` に書き出す |
| `bin/fetch-views` | 実際のビュー（rails/rails と kaigionrails/conference-app）を取得する |
| `results/` | `bin/record`、`bin/record-views` の結果 |
| `semantics/` | ERB と cop の関係を確かめるスクリプトと Ruby（[第 3 部](../erb-and-rubocop.md)）。[使い方](#erb-と-cop-の関係の確認) |

統合していない入力は次の 2 つです。

- `plain_ruby/equivalent.rb`: ERB ではなく Ruby なので、ERB のツールにはかけない。ERB と同じ内容を普通の Ruby として書くと RuboCop が何を出すかを示す比較の基準
- 実際のビュー: 外部のリポジトリのファイルなので、コミットを固定して `bin/fetch-views` で取得する（`work/views/`。git には入れない）

## 確認環境

- ruby 4.0.5
- rubocop 1.92.1（すべてのツールで共通）
- herb 0.11.1（marcoroth/herb#2260 だけは、gemspec が固定している 0.11.0）
- @herb-tools/linter 0.11.1 / @herb-tools/formatter 0.11.1（node v26.9.0）

| TOOL | ツール | 設定 |
|---|---|---|
| `erb_lint-all` | erb_lint 0.9.0 の Rubocop linter | 全 cop を有効（`tools/erb_lint/all_cops.yml`） |
| `erb_lint-recommended` | 同上 | README の推奨どおりに cop を無効化（`tools/erb_lint/recommended.yml`。rubocop-rails を入れていないので `Rails/OutputSafety` は除く） |
| `rubocop-erb-0.7` | rubocop-erb 0.7.2（タグ単位） | `tools/rubocop-erb-0.7/erb.yml` |
| `rubocop-erb-0.8` | rubocop-erb 0.8.2（`Herb.extract_ruby` で文書全体） | `tools/rubocop-erb-0.8/erb.yml` |
| `rubocop-erb-0.8-noexclude` | 同上 | 0.8.2 が ERB から除外している 65 個の cop のうち、`Rails/Presence` を除く 64 個の除外を外す（`tools/rubocop-erb-0.8/erb-noexclude.yml`） |
| `herb-rubocop-herb` | [marcoroth/herb#2260](https://github.com/marcoroth/herb/pull/2260) の rubocop-herb（`d0323df`） | `tools/herb-rubocop-herb/pr.yml` |
| `ruumba` | ruumba 0.1.17 | README の推奨設定（`tools/ruumba/.ruumba.yml`） |
| `tk0miya-rubocop-herb` | tk0miya/rubocop-herb `4cbe9062156f28b95d94d27ebc59ab3f9da35f33` | リポジトリの `config/develop/rubocop.yml` を継承（`tools/tk0miya-rubocop-herb/tk.yml`） |
| `herb-lint` | @herb-tools/linter | `.herb.yml`（`framework: actionview`） |
| `herb-format` | @herb-tools/formatter | 同上 |
| `plain-ruby` | rubocop 1.92.1（`plain_ruby/` だけを検査） | `plain_ruby/.rubocop.yml` |

rubocop 系の設定は、どれも `NewCops: enable`、`TargetRubyVersion: 3.4` に揃えてあります。

## セットアップ

```console
$ cd research/repro
$ for d in tools/*/; do [ -f "$d/Gemfile" ] && (cd "$d" && BUNDLE_FROZEN=true bundle install); done
$ npm install
$ git clone https://github.com/tk0miya/rubocop-herb "$TMPDIR/rubocop-herb"
$ (cd "$TMPDIR/rubocop-herb" && git checkout 4cbe9062156f28b95d94d27ebc59ab3f9da35f33 && bundle install)
$ export RUBOCOP_HERB="$TMPDIR/rubocop-herb"
```

- herb はビルド済みの gem（`herb-0.11.1-arm64-darwin` など）を使う。`Gemfile.lock` からは `ruby` プラットフォーム（ソースからビルドする gem）を外してある
- `bundle install` は必ず `BUNDLE_FROZEN=true` を付けて実行する。付けないと、`Gemfile.lock` にないプラットフォームでは Bundler がそのプラットフォームを足して解決し直し、ビルド済み gem がなければソースの gem を選んでビルドを始める。付けると「Add the current platform to the lockfile」というエラーで止まる
- `herb-rubocop-herb` は、PR の head の `gems/rubocop-herb/*.gemspec` だけを Bundler の git ソースで読む。herb のリポジトリで `rake compile` をする必要はない（`Herb.extract_ruby` の C 実装は、v0.11.0 と PR の head で同じ）。実行すると `already initialized constant Herb::VERSION` という警告が出るが、影響はない
- tk0miya-rubocop-herb は rubygems に公開されていないので、clone して、その `Gemfile` で実行する

## 使い方

コマンドはすべて `research/repro` で実行します。

```console
$ bin/lint tk0miya-rubocop-herb                           # cases/ 全体
$ bin/lint herb-rubocop-herb --format emacs cases/marker  # オプションとパスを渡す
$ bin/lint tk0miya-rubocop-herb --except Herb/Linting,Layout cases/marker
$ bin/lint herb-lint cases/erb_comment
$ bin/lint plain-ruby
```

- オプションは各ツールにそのまま渡す。パスを省略すると `cases/` 全体を検査する
- `tk0miya-rubocop-herb` は `Herb/Linting` cop で herb-lint も実行する。RuboCop の結果だけを見るときは `--except Herb/Linting` を付ける。`--except` は最後の指定だけが効くので、ほかの cop と 1 つにまとめる。`-a` / `-A` では herb-lint の修正も適用する
- `tk0miya-rubocop-herb` の `Herb/Formatting` cop（herb-format の実行）は、`.herb.yml` で `formatter.enabled: true` にしたときだけ動く。この `.herb.yml` では有効にしていないので、何もしない
- `Herb/Linting` は、`@herb-tools/linter` を RuboCop のプロジェクトのルート（上へたどって最初に見つかる `Gemfile` のディレクトリ。なければカレントディレクトリ）の `node_modules` から読み込む。`research/repro` とその上には `Gemfile` がないので、`research/repro/node_modules` が使われる。`research/` に空の `Gemfile` を置くと、`research/` がルートになり、「`@herb-tools/linter is not installed in …/research`」というエラーになる

### autocorrect

autocorrect はファイルを書き換えるので、`bin/autocorrect` でコピーに対して実行します。

```console
$ bin/autocorrect tk0miya-rubocop-herb -a
$ bin/autocorrect herb-rubocop-herb -A -- cases/marker
$ bin/autocorrect ruumba --auto-correct --only Style/NilComparison,Style/NegatedIf,Style/StringLiterals
$ bin/autocorrect herb-format --force -- cases/erb_comment cases/herb_disable
$ bin/autocorrect herb-lint --fix -- cases/erb_comment
```

- `-- PATHS` の前がツールに渡すオプション。パスを省略すると `cases/` 全体
- `work/TOOL/orig/` にコピーし、`work/TOOL/corrected/` を書き換える。ツールの出力は `work/TOOL/output.txt`
- 最後に、`bin/html_changes.rb` で、書き換わったファイルの数、そのうち HTML（ERB タグ以外。空白の違いは無視）が変わったファイル、Herb のパースエラーが増えたファイルの数を出す。HTML とパースエラーしか見ないので、出力がなくなるような Ruby の変化は数えない
- コピーを `research/repro` の中（`work/`）に置くのは、rubocop が設定ファイルの `**/*.erb` などのパターンをカレントディレクトリからの相対パスで照合するため。外に置くと、rubocop-erb などの除外の設定が効かなくなる。RuboCop が既定で除外する `tmp/` も使えない
- macOS のファイルシステムは大文字と小文字を区別しないので、`-a` と `-A` の結果を `foo-a` / `foo-A` のような名前で分けない（同じファイルになる）。`results/` では `safe` / `all` と呼ぶ

### 結果の記録

```console
$ bin/record
$ bin/fetch-views && bin/record-views
```

| ファイル | 内容 |
|---|---|
| `results/lint/TOOL.txt` | `cases/` の offense（`file:line:col: …` の 1 行 1 件。行順） |
| `results/autocorrect/TOOL-safe.diff`, `TOOL-all.diff` | `-a`、`-A` の前後の diff |
| `results/autocorrect/summary.txt` | 書き換わったファイル、HTML が変わったファイル、パースエラーが増えたファイルの数 |
| `results/views/TOOL.txt` | 実際のビューでの cop ごとの offense の数 |
| `results/views/TOOL-safe.txt`, `TOOL-all.txt` | `-a`、`-A` の後に残る offense の数 |
| `results/views/TOOL-excluded-cops.txt` | rubocop-erb 0.8.2 が ERB から除外している 64 個の cop だけをかけた結果 |
| `results/views/summary.txt` | 実際のビューでの autocorrect の集計 |

ツールの版やケースを変えたら、記録し直して `git diff results/` で変化を確かめます。
`bin/fetch-views` は git の clone を使うので、`.git` を作れない sandbox の中では動きません。

## ERB と cop の関係の確認

[第 3 部](../erb-and-rubocop.md) の実測です。

```console
$ ruby semantics/render.rb                 # ERB の書き換えの前後を ActionView で描画して比べ、コンパイルされる Ruby を表示する
$ ruby semantics/count_structures.rb       # 実際のビューで、タグに跨がるブロックのうち 1 行に書いたものを数える
$ BUNDLE_GEMFILE="$PWD/tools/rubocop-erb-0.8/Gemfile" bundle exec rubocop --cache false -c plain_ruby/.rubocop.yml \
    --only Lint/EmptyConditionalBody,Style/EmptyElse,Lint/EmptyWhen,Lint/DuplicateBranch,Style/RedundantCondition,Style/IfWithSemicolon,Style/Next,Style/ConditionalAssignment semantics/ruby
$ BUNDLE_GEMFILE="$RUBOCOP_HERB/Gemfile" bundle exec rubocop --cache false -c semantics/block_length.yml \
    --only Metrics/BlockLength --format emacs work/views | ruby semantics/block_length_lines.rb
$ ruby semantics/extract_ruby.rb semantics/layout "$TMPDIR/layout"          # 7 章の例を、文字位置の揃った Ruby にする
$ ruby semantics/extract_ruby.rb work/views "$TMPDIR/views"                 # 実際のビューを Ruby にする
$ ruby semantics/extract_ruby.rb work/views "$TMPDIR/views_norm" norm       # 開始タグの幅を揃えてから Ruby にする
$ BUNDLE_GEMFILE="$PWD/tools/rubocop-erb-0.8/Gemfile" bundle exec rubocop --cache false -c plain_ruby/.rubocop.yml \
    --only Layout/EndAlignment,Layout/BlockAlignment,Layout/IndentationWidth,Layout/IndentationConsistency \
    --format emacs "$TMPDIR/layout"                                         # "$TMPDIR/views"、"$TMPDIR/views_norm" も同じように検査して件数を比べる
$ BUNDLE_GEMFILE="$PWD/tools/rubocop-erb-0.8/Gemfile" bundle exec rubocop --cache false -c plain_ruby/.rubocop.yml \
    --only Layout/EmptyLines,Layout/EmptyLinesAroundBlockBody semantics/ruby/blank_lines.rb
$ BUNDLE_GEMFILE="$PWD/tools/rubocop-erb-0.8/Gemfile" bundle exec rubocop --cache false -c plain_ruby/.rubocop.yml \
    --only Lint/Void semantics/ruby/kept_literal.rb semantics/ruby/kept_if.rb
$ ruby semantics/extract_ruby.rb work/views "$TMPDIR/views_empty" empty   # HTML を空白にする方式で、空白だけの行を空行にする
$ MARKER=1 BUNDLE_GEMFILE="$RUBOCOP_HERB/Gemfile" bundle exec ruby semantics/extract_ruby.rb work/views "$TMPDIR/views_marker" empty
$ BUNDLE_GEMFILE="$PWD/tools/rubocop-erb-0.8/Gemfile" bundle exec rubocop --cache false -c plain_ruby/.rubocop.yml \
    --only Layout/EmptyLines,Layout/EmptyLinesAroundBlockBody --format emacs "$TMPDIR/views_empty" \
    | ruby semantics/empty_lines_by_line.rb work/views "$TMPDIR/views_empty"   # "$TMPDIR/views_marker" も同じように数える
$ bin/lint tk0miya-rubocop-herb --only Layout/EmptyLines semantics/empty_lines.html.erb   # タグの中の空行だけを指摘する
```

- `semantics/ruby/` は、ERB と同じ形の Ruby。`blank_*.rb` は HTML を空白にした形、`kept_*.rb` は HTML を出力の文（`_erbout << "<p>x</p>"`）として残した形。`if_semicolon.rb`、`next.rb`、`cond_assign.rb` は、タグに跨がる構造を Ruby にした形。`blank_lines.rb` は、HTML だけの行を空行にした形。`kept_literal.rb` は、HTML を文字列リテラルだけにした形
- `semantics/layout/` は、第 3 部 7 章の配置への指摘の ERB。`extract_ruby.rb` は herb gem の `Herb.extract_ruby` で、元の ERB と文字位置の揃った Ruby を作る。`norm` を付けると `<%=` と `<%-` を `<%` にしてから Ruby にする。`empty` を付けると空白だけの行を空行にする。`MARKER=1` を付けると tk0miya-rubocop-herb のマーカー方式で Ruby にする
- `empty_lines.html.erb` は、タグの中、HTML の後ろ、ブロックの本文の前後に空行を置いた ERB。`empty_lines_by_line.rb` は、空行の cop の指摘を、元の ERB の行（HTML の行、タグの外の空行、タグの中の空行）で分けて数える
- `tools/rubocop-erb-0.8/Gemfile` は rubocop 1.92.1 を使うために借りているだけで、rubocop-erb は読み込まない（`plain_ruby/.rubocop.yml` はプラグインを使わない）
- `render.rb`、`count_structures.rb`、`extract_ruby.rb` は、actionview 8.1.4.1 と herb 0.11.1 の gem で確かめた

## ケースの一覧

各ケースは、どこかの文書の主張を確かめるためのものです。同じ形のケースをツールごとに持たず、1 つのケースをすべてのツールにかけます。

### `control_flow/`: タグを跨ぐ制御構造

| ファイル | 内容 | 確かめること |
|---|---|---|
| `nil_comparison` | `<% if foo == nil %>` の本文が HTML | タグ単位の方式は条件式を検査しない（`Style/NilComparison` の見逃し）。HTML を空白にする方式は本文を空と見なす |
| `negated_if` | `<% if !user.nil? %>` | rubocop-erb 0.7 系は `if` を削るので `Style/NegatedIf` が出ない |
| `if_then_elsif_else` | `then`、`elsif bar == nil`、本当に空の `else`、`unless !x` | タグ単位の方式の見逃し。本当に空の `else` / `unless` を検出できるか |
| `unless_else` | `unless` / `else` の本文が HTML | `Style/UnlessElse` の修正は HTML を ERB タグの中に入れるので、捨てるべき |
| `case_when` | `when` の本文が HTML だけ | HTML を空白にすると `Lint/EmptyWhen` が出る |
| `inline_if` | `<% if a %>A<% else %>B<% end %>` | 同じ行のタグの間の HTML を `Layout/ExtraSpacing` が消す |
| `cond_assign` | `if` / `else` の各分岐で `<% x = 1 %>` | `Style/ConditionalAssignment` は ERB には合わない |
| `safe_navigation` | `<% if user && user.admin? %>` | rubocop 1.86.2 以降の rubocop-erb 0.7 系で `user&&.admin?`（構文エラー）になる |
| `single_line_block` | `<%= cache "fragment" do %>…<% end %>` を 1 行で | HTML を空白にすると `Style/SingleLineDoEndBlock` が出る |
| `unused_block_arg` | `<% items.each do \|i\| %>` の本文が HTML | `i` の未使用（`Lint/UnusedBlockArgument`）。本文を空と見なすと出ない |
| `unused_block_arg_output` | `<% items.each_with_index do \|item, i\| %>` の本文に出力タグ | `i` の未使用（`Lint/UnusedBlockArgument`）。タグ単位ではブロック全体が見えないので出ない |
| `form_block` | `<%= form_with … do \|f\| %>` | ブロック付きの出力タグ |
| `trim` | `<%-` / `-%>` | トリムのあるタグでも位置がずれないか |

### `variables/`: タグを跨ぐ変数

| ファイル | 内容 | 確かめること |
|---|---|---|
| `cross_tag_variables` | 次のタグで使う `total` と、本当に未使用の `unused` | 本当に未使用の変数だけを検出するか。タグ単位の方式は `total` に `Lint/UselessAssignment` を出し（誤検知）、erb_lint の autocorrect が代入を消す |
| `ambiguous_operator` | `<%= count -1 %>`、`<%= item *2 %>`（`count`、`item` は前のタグの変数） | タグ単位の方式は変数が見えず、`count(-1)` に書き換える |

### `output/`: 出力タグと同じ行のタグ

| ファイル | 内容 | 確かめること |
|---|---|---|
| `symbol_proc_map` | `<% users.map { \|u\| u.name }.each do \|name\| %>` | 1 つのタグの中の、妥当な `Style/SymbolProc` |
| `string_literal` | `<%= "hello" %>` | タグごとに出るファイル単位の cop（erb_lint）。autocorrect でマジックコメントが入る |
| `link_to_class` | `<%= link_to "x", path, class: 'btn' %>` | erb_lint の autocorrect で `<%=` が消える |
| `raw_output` | `<%== raw_html %>` | ruumba が `<%= raw raw_html %>` に書き換える |
| `same_line_tags` | `<%= a %><%= b %>` | 補った `;` への `Style/Semicolon` |
| `two_tags_line` | `<td><%= user.name %></td><td><%= user.email %></td>` | 同じ行のタグの間の HTML を `Layout/ExtraSpacing` が消す |
| `one_tag_line` | `<li><%= link_to "a", a_path %></li>` | 行に 1 つだけのタグ |
| `attr` | 属性値の中のタグ | 属性値の中のタグも位置がずれないか |
| `escaped_tag` | `<%%= link_to "a", a_path %>` | エスケープしたタグの中身は Ruby ではない |

### `style/`: スタイル

| ファイル | 内容 | 確かめること |
|---|---|---|
| `ruby_style` | `<%= link_to( 'Home',root_path ) %>` など | herb-lint はスタイル違反を見ない |
| `multiline_tag` | `<%`⏎`  x = 1`⏎`  y = 2`⏎`%>` | erb_lint の推奨設定でも、`Layout/LeadingEmptyLines` の修正で `<%` が消える |
| `empty_lines` | タグの間に空行を含む HTML | HTML の中の空行に `Layout/EmptyLines` が出るか |

### `syntax/`: 構文エラー

| ファイル | 内容 | 確かめること |
|---|---|---|
| `missing_end` | `end` の抜け | `Lint/Syntax` を検出するか（rubocop-erb 0.7 系は除外） |
| `syntax_errors_ignored` | `<% end.join(", ") %>`、`<% result = if foo %>` | タグ単位の方式は構文エラーになる断片を黙って飛ばす |
| `unclosed_paren` | `<p><%= link_to("a", path %></p>` | 構文エラーのメッセージに、ERB にない `;` が出る |

### `multibyte/`: マルチバイト文字

| ファイル | 内容 | 確かめること |
|---|---|---|
| `emoji` | 絵文字と日本語を HTML と Ruby の両方に含む | マルチバイト文字の後ろでも、offense と修正の位置がずれないか |
| `multibyte_comment` | `<%# 日本語のコメント %>` の次の行 | 同上（ERB のコメント） |
| `show` | HTML と日本語を含む行の `link_to( "ホーム",root_path )` など | 指摘の行が元の ERB のまま表示されるか（`--format clang`） |

### `comment/`: タグの中の Ruby のコメント

| ファイル | 内容 | 確かめること |
|---|---|---|
| `ruby_comment` | `<% # note %>` | `Herb.extract_ruby` は空白にする。tk0miya-rubocop-herb は Ruby のコメントとして扱う |
| `commented_out_output` | `<% name = user.name # the full name %><%= name %>` | ERB では行末のコメントが後ろの出力タグまでコメントにする（herb-lint の `erb-no-trailing-comment`） |
| `commented_out_end` | `<% if admin? # only for admins %><p>admin</p><% end %>` | 同上。`<% end %>` がコメントになって構文エラーになる |

### `rubocop_disable/`: `Style/StringLiterals` を無効にするコメントの書き方

どのファイルも、コメントの後に `"a"` などの二重引用符の文字列があります。

| ファイル | 書き方 |
|---|---|
| `erb_comment` | `<%# rubocop:disable Style/StringLiterals %>` |
| `ruby_comment_tag` | `<% # rubocop:disable Style/StringLiterals %>` |
| `trailing_ruby_comment` | `<% x = "b" # rubocop:disable Style/StringLiterals %>` |
| `trailing_ruby_comment_output` | `<%= "a" # rubocop:disable Style/StringLiterals %>` |
| `multiline_tag` | `<%`⏎`  # rubocop:disable Style/StringLiterals`⏎`  x = "b"`⏎`%>` の後に `<%= "c" %>` |
| `multiline_range` | `<%`⏎`  # rubocop:disable …`⏎`%>` と `<%`⏎`  # rubocop:enable …`⏎`%>` で範囲を区切る |

### `erb_comment/`: `<%# rubocop:disable %>` の置き場所と herb-format の整形

`empty_if` 以外は、`Lint/LiteralAsCondition` を無効にするコメントと、その対象になる `<% if 'hello' %>` を含みます。

| ファイル | 内容 |
|---|---|
| `trailing` | `<% if 'hello' %>world<% end %><%# rubocop:disable … %>` |
| `leading` | `<%# rubocop:disable … %><% if 'hello' %>world<% end %>` |
| `after_if` | `<% if 'hello' %><%# rubocop:disable … %>` の後に本文と `<% end %>` |
| `not_erb_tag` | `<% if 'hello' %>world<% end %><# rubocop:disable … %>`（`%` のない `<#`） |
| `indent` | 独立した行の `<%# rubocop:disable … %>` と `<%# rubocop:enable … %>`。インデントが入れ子の深さと合っていない |
| `multiline_comment` | `<%#`⏎`  rubocop:disable …`⏎`%>` の後に `<% if 'hello' %>` |
| `multiline_tag` | `<%`⏎`  # rubocop:disable …`⏎`%>` の後に `<% if 'hello' %>` |
| `trailing_in_tag` | `<% if 'hello' # rubocop:disable … %>` の後に本文と `<% end %>` |
| `empty_if` | `<% if some_error %><%# rubocop:disable Lint/EmptyConditionalBody %>`⏎`<% end %>` |

### `herb_disable/`: `<%# herb:disable %>` と herb-format の整形

herb-lint / herb-format のためのケースです。rubocop 系のツールにもかけますが、ほかのケースと同じ観点の結果しか出ません。

| ファイル | 内容 |
|---|---|
| `img` | `<img src="a.png"> <%# herb:disable html-img-require-alt %>` |
| `same_anchor` | 同じ `<img src="a.png">` が 2 行並び、2 行目の行末に `herb:disable` |
| `empty_if` | `<% if some_error %><%# herb:disable erb-no-empty-control-flow %>`⏎`<% end %>` |
| `if_sibling` | `<div>` の中で `<% if some_error %><%# herb:disable … %><% end %>` |

### `marker/`: ERB として正しいものと直すべきものの組

cop ごとに、ERB として正しいテンプレート（`*_ok`）と、同じ形で本当に直すべきテンプレート（`*_ng`）を 1 つずつ置いています。`Herb.extract_ruby` で変換すると、組の 2 つが同じ Ruby になります。

| cop（ファイル） | `*_ok`（ERB として正しい） | `*_ng`（直すべき） |
|---|---|---|
| `Lint/Void`（`void`） | `<p><%= count + 1 %> items</p>` | `<p><% count + 1 %> items</p>`（`=` の書き忘れ） |
| `Style/SymbolProc`（`symbol_proc`） | `<% items.each do \|item\| %>` `<li><%= item.name %></li>` `<% end %>` | `<% items.each do \|item\| %>` `<% item.touch %>` `<% end %>` |
| `Lint/EmptyBlock`（`empty_block`） | `<% items.each do %>` `<li>item</li>` `<% end %>` | `<% items.each do %>` `<% end %>` |
| `Lint/EmptyConditionalBody`（`empty_conditional`） | `<% if user.admin? %>` `You are an administrator.` `<% end %>` | `<% if user.admin? %>` `<% end %>` |
| `Style/EmptyElse`（`empty_else`） | `<% else %>` `You are not an administrator.` `<% end %>` | `<% else %>` `<% end %>` |
| `Style/SafeNavigation`（`safe_navigation`） | `<% if user %>` `Last login: <% user.touch %>` `<% end %>` | `<% if user %>` `<% user.touch %>` `<% end %>` |
| `Style/SoleNestedConditional`（`sole_nested_conditional`） | 外側の `if` の本文に `Welcome!` と内側の `if` | 外側の `if` の本文が内側の `if` だけ |
| `Lint/DuplicateBranch`（`duplicate_branch`） | `Good morning, <%= user.name %>` と `Hello, <%= user.name %>` | `<%= user.name %>` と `<%= user.name %>` |
| `Style/CombinableLoops`（`combinable_loops`） | 2 つの `items.each` の間に `Prices:` | 2 つの `items.each` が連続 |

`safe_navigation_short` は、`<% if user %>` の本文が `|<% user.touch %>` のものです。テキストが短くて tk0miya-rubocop-herb がマーカーを置けない例です。

組にした比較では、内容に関わらない cop を外して実行します。

```console
$ X=Layout,Style/FrozenStringLiteralComment,Style/Semicolon,Style/StringLiterals
$ for t in rubocop-erb-0.8 rubocop-erb-0.8-noexclude herb-rubocop-herb; do bin/lint $t --except $X --format emacs cases/marker; done
$ bin/lint tk0miya-rubocop-herb --except Herb/Linting,$X --format emacs cases/marker
```

## 実際のビュー

rails/rails `0f591639b864de6bf3fd760a6921f5eda17b2905` と kaigionrails/conference-app `25a02cc871861dd94d76a4af983fad7b08008333` の `*.html.erb`（333 ファイル）です。

```console
$ bin/fetch-views
$ bin/lint tk0miya-rubocop-herb --except Herb/Linting --format offenses work/views
$ bin/autocorrect herb-rubocop-herb -a -- work/views
$ bin/record-views
```
