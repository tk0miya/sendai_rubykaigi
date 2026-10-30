# 既存 ERB linter の問題の再現例

[../existing-erb-linters.md](../existing-erb-linters.md) で挙げた問題を再現するための最小例です。

## 確認環境（2026-10-06）

- ruby 4.0.5
- erb_lint 0.9.0 / rubocop 1.91.0 / rubocop-erb 0.7.1 / ruumba 0.1.17（`Gemfile` で固定）
- @herb-tools/linter 0.11.0（node v26.9.0）

## セットアップ

```console
$ cd research/repro
$ bundle install
$ (cd herb && npm install)
$ export BUNDLE_GEMFILE="$PWD/Gemfile"   # コピー先のディレクトリでも bundle exec できるように
```

以下のコマンドは、特に断りがない限り `research/repro` から実行します。

## erb_lint

`erb_lint/all_cops/` は全 cop を有効にした設定、`erb_lint/recommended/` は README の推奨どおりに cop を無効化した設定です（rubocop-rails を入れていないため `Rails/OutputSafety` は除外）。

```console
$ cd erb_lint/all_cops
$ bundle exec erb_lint --config .erb_lint.yml per_tag_file_cops.html.erb useless_assignment.html.erb
```

- `per_tag_file_cops.html.erb`: タグごとに `Layout/InitialIndentation`、`Layout/TrailingEmptyLines`、`Style/FrozenStringLiteralComment` が出る
- `useless_assignment.html.erb`: 次のタグで使っている変数に `Lint/UselessAssignment` が出る（誤検知）

```console
$ cd erb_lint/recommended
$ bundle exec erb_lint --config .erb_lint.yml if_condition.html.erb control_flow.html.erb unused_block_arg.html.erb
```

- `if_condition.html.erb`, `control_flow.html.erb`, `unused_block_arg.html.erb`: offense は 0 件（見逃し）
- 同じ内容の Ruby を `plain_ruby/` で `bundle exec rubocop equivalent.rb` すると、`Style/NilComparison`、`Style/NegatedUnless`、`Lint/UnusedBlockArgument` など 8 件出る

### autocorrect（ファイルを書き換えるので、コピーに対して実行すること）

```console
$ cp -R erb_lint "$TMPDIR/erb_lint" && cd "$TMPDIR/erb_lint/all_cops"
$ bundle exec erb_lint --config .erb_lint.yml -a autocorrect_output_tag.html.erb useless_assignment.html.erb
$ cd ../recommended
$ bundle exec erb_lint --config .erb_lint.yml -a autocorrect_multiline_tag.html.erb
```

- `autocorrect_output_tag.html.erb`: `<%=` が消え、`# frozen_string_literal: true` が HTML 本文に挿入される
- `useless_assignment.html.erb`: 代入が消え、`'Alice'` だけが残る
- `autocorrect_multiline_tag.html.erb`: 推奨設定でも `Layout/LeadingEmptyLines` の修正で `<%` が消える

## rubocop-erb

```console
$ cd rubocop-erb
$ bundle exec rubocop
```

- `negated_if.html.erb`: `Style/NegatedIf` が出ない（見逃し）
- `symbol_proc.html.erb`: `Style/SymbolProc` が出ない（見逃し）
- `syntax_errors_ignored.html.erb`: 構文エラーになる断片が黙って無視される
- `autocorrect_*.html.erb`: autocorrect 対象の offense が出る

autocorrect はコピーに対して実行します。

```console
$ cp -R rubocop-erb "$TMPDIR/rubocop-erb" && cd "$TMPDIR/rubocop-erb"
$ bundle exec rubocop -A
```

- `autocorrect_local_variable.html.erb`: `count -1` が `count(-1)`、`item *2` が `item(2)` に書き換わる（ローカル変数がメソッド呼び出しになる）
- `autocorrect_safe_navigation.html.erb`: `user && user.admin?` が `user&&.admin?` に書き換わる（構文エラー）。rubocop 1.86.1 では `user&.admin?` に正しく修正される

## ruumba

`ruumba/.ruumba.yml` は ruumba の README の推奨設定です。ruumba は `rubocop` コマンドを子プロセスで実行するので、`bundle exec` 経由で Gemfile の rubocop を使わせます。

erb_lint / rubocop-erb の再現例にかけると、タグ単位の方式の問題が解消されていることを確認できます。

```console
$ bundle exec ruumba -D -e -c ruumba/.ruumba.yml erb_lint rubocop-erb
```

- `if_condition.html.erb`, `control_flow.html.erb`, `negated_if.html.erb`: `Style/NilComparison`、`Style/NegatedIf` などを検出する
- `useless_assignment.html.erb`: `Lint/UselessAssignment` は出ない
- `autocorrect_local_variable.html.erb`: `Lint/AmbiguousOperator` は出ない（`count` をローカル変数と認識する）
- どのファイルにも `Layout/TrailingWhitespace` や `Layout/InitialIndentation` が出る（空白で埋めたことによる誤検知）

`ruumba/` の再現例では、文書全体を 1 本の Ruby にする方式で新たに生じる問題を確認できます。

```console
$ cd ruumba
$ bundle exec ruumba -D -e -c .ruumba.yml .
```

- `control_flow.html.erb`: `Style/NilComparison` と `Style/NegatedIf` を検出する一方、本文が HTML だけの `if` に `Lint/EmptyConditionalBody` が出る
- `local_variable.html.erb`: `<%= name %>: <%= count -1 %>` が `name; count -1` と連結され、`name` に `Lint/Void` が出る
- `output_in_block.html.erb`: `Style/SymbolProc` が `items.each(&:name)` を提案する（従うと出力がなくなる）
- `same_line_tags.html.erb`: 補った `;` に `Style/Semicolon` が出る

### autocorrect（コピーに対して実行すること）

```console
$ cp -R ruumba "$TMPDIR/ruumba" && cd "$TMPDIR/ruumba"
$ bundle exec ruumba -e -c .ruumba.yml --auto-correct .
```

「88 offenses corrected」と表示されますが、ERB ファイルは 1 つも書き換わりません（Layout 系の修正でマーカー行がずれ、書き戻しが黙って中止される）。

```console
$ bundle exec ruumba -e -c .ruumba.yml --auto-correct --only Style/NilComparison,Style/NegatedIf,Style/StringLiterals .
```

- `control_flow.html.erb`: `foo == nil` が `foo.nil?`、`if !user.nil?` が `unless user.nil?` に正しく修正される
- `raw_output.html.erb`: 修正対象ではない `<%== raw_html %>` が `<%= raw raw_html %>` に書き換わる

## Herb（herb-lint）

```console
$ cd herb
$ npx herb-lint app/views/samples
```

- `cross_tag_variables.html.erb`: タグを跨いだ変数を追跡し、本当に未使用の `unused` だけを `erb-no-unused-local-variable` で検出する
- `missing_end.html.erb`: `end` の抜けを `RUBY_PARSE_ERROR` と `MISSING_ERB_END_TAG_ERROR` で検出する
- `ruby_style.html.erb`: `link_to( 'Home',root_path )` のようなスタイル違反や未定義メソッドは検出されない（offense 0 件）

## rubocop-herb

[../report.md](../report.md) の再現手順です。rubocop-herb は rubygems に公開されていないので、リポジトリを clone して、その `Gemfile` と開発用の設定（`config/develop/rubocop.yml`）を使います。

```console
$ git clone https://github.com/tk0miya/rubocop-herb "$TMPDIR/rubocop-herb"
$ (cd "$TMPDIR/rubocop-herb" && git checkout 96d31cf8dff39109dbe4506b808e19693a92b2e2 && bundle install)
$ export RUBOCOP_HERB="$TMPDIR/rubocop-herb"
$ alias rubocop-herb='BUNDLE_GEMFILE="$RUBOCOP_HERB/Gemfile" bundle exec rubocop --cache false --except Herb/Linting -c "$RUBOCOP_HERB/config/develop/rubocop.yml"'
```

- `--except Herb/Linting` は、herb-lint（Node.js の `@herb-tools/linter`）を入れていない環境で、セットアップを促すエラーを出さないためのものです。RuboCop の結果だけを比べます

### 既存ツールの再現例にかける

```console
$ rubocop-herb erb_lint rubocop-erb ruumba herb/app
```

- erb_lint / rubocop-erb で見逃していた `Style/NilComparison`、`Style/NegatedIf`、`Lint/UnusedBlockArgument` などを検出する
- erb_lint の `Lint/UselessAssignment`、ruumba の `Lint/Void`・`Style/SymbolProc`・`Lint/EmptyConditionalBody`・Layout 系の誤検知は出ない
- `erb_lint/recommended/control_flow.html.erb` の本当に空の `else` / `unless` には `Style/EmptyElse` / `Lint/EmptyConditionalBody` が出る
- `herb/app/views/samples/missing_end.html.erb` に `Lint/Syntax` が出る

autocorrect はコピーに対して実行します。

```console
$ cp -R . "$TMPDIR/repro-herb" && cd "$TMPDIR/repro-herb"
$ rubocop-herb -A erb_lint rubocop-erb ruumba herb/app
$ diff -r "$OLDPWD" .
```

- `count -1` は `count - 1`、`user && user.admin?` は `user&.admin?` に正しく修正される
- `herb/app/views/samples/cross_tag_variables.html.erb` の `<% unused = 1 %>` は、行ごと消える（`Lint/UselessAssignment`、`Lint/Void`、`Herb/EmptyErbTag` の順に修正される）

### Herb/Linting（herb-lint）

`Herb/Linting` は `@herb-tools/linter` を RuboCop のプロジェクトのルート（上へたどって最初に見つかる `Gemfile` のディレクトリ）から読み込みます。`herb/` で実行すると `research/repro/Gemfile` のある `research/repro` がルートになって見つからないので、`Gemfile` のないディレクトリにコピーして実行します。

```console
$ (cd herb && npm install)
$ mkdir "$TMPDIR/herb-lint" && cp -R herb/. "$TMPDIR/herb-lint/" && cp rubocop-herb/*.html.erb "$TMPDIR/herb-lint/app/views/samples/"
$ printf '<div><span></div>\n' > "$TMPDIR/herb-lint/app/views/samples/missing_close.html.erb"
$ cd "$TMPDIR/herb-lint"
$ BUNDLE_GEMFILE="$RUBOCOP_HERB/Gemfile" bundle exec rubocop --cache false -c "$RUBOCOP_HERB/config/develop/rubocop.yml" app
$ npx herb-lint app/views/samples
```

- `missing_close.html.erb`、`cross_tag_variables.html.erb` に、herb-lint 単体と同じ offense が `Herb/Linting: [rule-name] …` として出る
- `empty_tag_after_output_tag.html.erb` には herb-lint 単体では `erb-no-empty-tags` が出るが、`Herb/Linting` は出さない。代わりに `Herb/EmptyErbTag` が出る
- `missing_end.html.erb` には herb-lint 単体では `parser-no-errors` が出るが、`Herb/Linting` は出ない（Ruby の構文エラーがあるファイルでは herb-lint を実行しない）。`Lint/Syntax` は出る
- `herb/` で実行すると、`@herb-tools/linter is not installed in …/research/repro` というエラーが出る

### 未解決の問題

`rubocop-herb/` の再現例です。autocorrect はコピーに対して実行します。

```console
$ cd rubocop-herb
$ rubocop-herb .
$ cp -R . "$TMPDIR/rubocop-herb-ac" && cd "$TMPDIR/rubocop-herb-ac"
$ rubocop-herb -a .
$ diff -r "$OLDPWD" .
```

- 出力タグの直後の空のタグを消すと、出力タグの `%>` も消える（`empty_tag_after_output_tag.html.erb`）: `-a` で `<% %>`⏎`<%= b %><% %>` が `<%= b ` になる。`--only Herb/EmptyErbTag` や `--only Layout/SpaceBeforeSemicolon` を付けて片方だけ修正すると壊れない
- HTML を含むテンプレートで、パースし直して確かめる cop の指摘・修正が消える（`reparse_cops_in_html.html.erb`）: `<div>` の中の `root_path()`、`(foo)` に `Style/MethodCallWithoutArgsParentheses`、`Style/RedundantParentheses` が出ない。`(a == b) ? …` に `Style/TernaryParentheses` は出るが、`[Correctable]` が付かず修正されない。`<div>` と `</div>` の行を消すと、3 つとも出て修正される

## herb PR #2260

[../herb-pr2260.md](../herb-pr2260.md) の再現手順です。herb 本体のリポジトリに提案されている rubocop-herb（[marcoroth/herb#2260](https://github.com/marcoroth/herb/pull/2260)）と、tk0miya/rubocop-herb を同じ入力にかけて比べます。

### セットアップ

PR 版の gem（`gems/rubocop-herb`）は Ruby だけでできているので、herb のリポジトリはビルドしません。`herb-pr2260/Gemfile` は次のように作ってあります。

- herb は rubygems のビルド済み gem（`herb-0.11.0-arm64-darwin` など）を使う。`Gemfile.lock` からは `ruby` プラットフォーム（ソースからビルドする gem）を外してある
- `bundle install` は必ず `BUNDLE_FROZEN=true` を付けて実行する。付けないと、`Gemfile.lock` にないプラットフォームでは Bundler がそのプラットフォームを足して解決し直し、ビルド済み gem がなければソースの gem を選んでビルドを始める。付けると「Add the current platform to the lockfile」というエラーで止まる
- PR 版の gem は Bundler の git ソースで、PR の head（`d0323df`）の `gems/rubocop-herb/*.gemspec` だけを読む。herb のリポジトリで `bundle install` や `rake compile` をする必要はない（`Herb.extract_ruby` の C 実装は、v0.11.0 と PR の head で同じ）
- 実行すると `already initialized constant Herb::VERSION` という警告が出る。PR 版の gemspec が、git から取ってきたリポジトリの `lib/herb/version.rb` を読むためで、どちらも 0.11.0 なので影響はない

```console
$ cd research/repro
$ (cd herb-pr2260 && BUNDLE_FROZEN=true bundle install)
$ git clone https://github.com/tk0miya/rubocop-herb "$TMPDIR/rubocop-herb-24ec034"
$ (cd "$TMPDIR/rubocop-herb-24ec034" && git checkout 24ec03477642aa4c8162d2d7d075aa623c72d062 && bundle install)
$ export PR2260="$PWD/herb-pr2260" RUBOCOP_HERB="$TMPDIR/rubocop-herb-24ec034"
$ alias pr2260='BUNDLE_GEMFILE="$PR2260/Gemfile" bundle exec rubocop --cache false -c "$PR2260/pr.yml"'
$ alias rubocop-herb-head='BUNDLE_GEMFILE="$RUBOCOP_HERB/Gemfile" bundle exec rubocop --cache false --except Herb/Linting -c "$PR2260/tk.yml"'
```

- `pr.yml` は PR 版を読み込む設定、`tk.yml` は `$RUBOCOP_HERB/config/develop/rubocop.yml` を継承する設定。どちらも `NewCops: enable` と `TargetRubyVersion: 3.4` に揃えてある
- 比べる対象の rubocop-herb のコミットが「rubocop-herb」の節と違うので、別のディレクトリに clone する

### 再現例と境界ケースにかける

```console
$ pr2260 --format offenses erb_lint rubocop-erb ruumba herb/app
$ rubocop-herb-head --format offenses erb_lint rubocop-erb ruumba herb/app
$ pr2260 --format emacs herb-pr2260/edge
$ rubocop-herb-head --format emacs herb-pr2260/edge
```

- 再現例 20 ファイルで、PR 版は 88 件（うち `Layout/ExtraSpacing` 55 件）、rubocop-herb は 28 件
- PR 版だけに `Lint/Void`、`Style/SymbolProc`、`Lint/EmptyBlock` が、rubocop-herb だけに `Lint/UnusedBlockArgument`、`Style/EmptyElse`、`Lint/EmptyConditionalBody` が出る
- `herb-pr2260/edge/case.html.erb` に、PR 版だけ `Lint/EmptyWhen` が出る。`herb-pr2260/edge/disable.html.erb` の `<%# rubocop:disable … %>` は PR 版では効かない

### autocorrect（コピーに対して実行すること）

```console
$ W="$TMPDIR/pr2260-ac" && mkdir -p "$W/orig/herb"
$ for d in erb_lint rubocop-erb ruumba; do ditto "$d" "$W/orig/$d"; done
$ ditto herb/app "$W/orig/herb/app" && ditto herb-pr2260/edge "$W/orig/edge"
$ for t in pr-safe pr-all tk-safe tk-all; do ditto "$W/orig" "$W/$t"; done
$ (cd "$W/pr-safe" && pr2260 -a .)
$ (cd "$W/pr-all" && pr2260 -A .)
$ (cd "$W/tk-safe" && rubocop-herb-head -a .)
$ (cd "$W/tk-all" && rubocop-herb-head -A .)
$ diff -r "$W/orig" "$W/pr-safe"
$ for t in pr-safe pr-all tk-safe tk-all; do BUNDLE_GEMFILE="$PR2260/Gemfile" bundle exec ruby herb-pr2260/html_changes.rb "$W/orig" "$W/$t"; done
```

- macOS のファイルシステムは大文字と小文字を区別しないので、`-a` と `-A` のコピーに `pr_a` / `pr_A` のような名前を付けない（同じディレクトリになる）
- `html_changes.rb` は、書き換わったファイルのうち、HTML（空白の違いは無視）が変わったものと Herb のパースエラーが増えたものを数える
- PR 版は `-a` でも 8 ファイルで HTML が変わる。`edge/two_tags_line.html.erb` が `<td><%= user.name%> user.email%></td>` に、`edge/inline_if.html.erb` が `<% if a%> else%> end%>` になる。rubocop-herb は `-a`、`-A` とも 0 ファイル

### 実際のビューにかける

rails/rails と kaigionrails/conference-app の `*.html.erb` を、コミットを固定して取得します。

```console
$ S="$TMPDIR/views-src" && mkdir -p "$S/rails" "$S/conference-app"
$ (cd "$S/rails" && git init -q && git fetch --depth 1 https://github.com/rails/rails.git 0f591639b864de6bf3fd760a6921f5eda17b2905 && git checkout -q FETCH_HEAD)
$ (cd "$S/conference-app" && git init -q && git fetch --depth 1 https://github.com/kaigionrails/conference-app.git 25a02cc871861dd94d76a4af983fad7b08008333 && git checkout -q FETCH_HEAD)
$ V="$TMPDIR/views" && rsync -a --prune-empty-dirs --exclude node_modules --exclude vendor --exclude tmp --exclude .git --include '*/' --include '*.html.erb' --exclude '*' "$S/" "$V/orig/"
$ (cd "$V/orig" && pr2260 --format offenses .)
$ (cd "$V/orig" && rubocop-herb-head --format offenses .)
$ ditto "$V/orig" "$V/pr" && ditto "$V/orig" "$V/tk"
$ (cd "$V/pr" && pr2260 -a .) ; (cd "$V/tk" && rubocop-herb-head -a .)
$ for t in pr tk; do BUNDLE_GEMFILE="$PR2260/Gemfile" bundle exec ruby herb-pr2260/html_changes.rb "$V/orig" "$V/$t"; done
```

- 333 ファイルで、PR 版は 2,455 件（うち `Layout/ExtraSpacing` 1,606 件、`Lint/Void` 50 件）、rubocop-herb は 935 件
- `-a` で HTML が変わるファイルは、PR 版が 63、rubocop-herb が 0

## rubocop-erb 0.8

[../rubocop-erb-0.8.md](../rubocop-erb-0.8.md) の再現手順です。rubocop-erb 0.7.2（タグ単位）、0.8.2（`Herb.extract_ruby`）、tk0miya/rubocop-herb を同じ入力にかけて比べます。

### セットアップ

`rubocop-erb-0.8/v0.7.2/` と `rubocop-erb-0.8/v0.8.2/` に、それぞれの版の `Gemfile` があります。herb はビルド済みの gem を使うので、「herb PR #2260」の節と同じく `BUNDLE_FROZEN=true` を付けて `bundle install` します。rubocop と herb のバージョンは、比べる rubocop-herb の `Gemfile.lock`（rubocop 1.92.0、herb 0.11.0）に揃えてあります。

```console
$ cd research/repro
$ (cd rubocop-erb-0.8/v0.7.2 && BUNDLE_FROZEN=true bundle install)
$ (cd rubocop-erb-0.8/v0.8.2 && BUNDLE_FROZEN=true bundle install)
$ git clone https://github.com/tk0miya/rubocop-herb "$TMPDIR/rubocop-herb-96d31cf"
$ (cd "$TMPDIR/rubocop-herb-96d31cf" && git checkout 96d31cf8dff39109dbe4506b808e19693a92b2e2 && bundle install)
$ export R="$PWD/rubocop-erb-0.8" RUBOCOP_HERB="$TMPDIR/rubocop-herb-96d31cf"
$ erb072() { BUNDLE_GEMFILE="$R/v0.7.2/Gemfile" bundle exec rubocop --cache false -c "$R/erb.yml" "$@"; }
$ erb082() { BUNDLE_GEMFILE="$R/v0.8.2/Gemfile" bundle exec rubocop --cache false -c "$R/erb.yml" "$@"; }
$ tkherb() { BUNDLE_GEMFILE="$RUBOCOP_HERB/Gemfile" bundle exec rubocop --cache false --except Herb/Linting -c "$R/tk.yml" "$@"; }
```

- `erb.yml` は rubocop-erb を読み込む設定（0.7.2 と 0.8.2 で共通）、`tk.yml` は `$RUBOCOP_HERB/config/develop/rubocop.yml` を継承する設定。どちらも `NewCops: enable` と `TargetRubyVersion: 3.4` に揃えてある
- zsh では、入力のディレクトリを変数にまとめるときは配列（`IN=(erb_lint rubocop-erb …)` と `$IN`）にする。文字列にすると 1 つの引数として渡る

### 再現例と境界ケースにかける

```console
$ for t in erb072 erb082 tkherb; do $t --format offenses erb_lint rubocop-erb ruumba herb/app herb-pr2260/edge; done
$ for t in erb072 erb082 tkherb; do $t --format emacs rubocop-erb-0.8/edge; done
```

- 32 ファイルで、0.7.2 は 24 件、0.8.2 は 33 件、rubocop-herb は 37 件
- `rubocop-erb-0.8/edge/single_line_block.html.erb` に、0.8.2 だけ `Style/SingleLineDoEndBlock` と `Style/BlockDelimiters` が出る
- `rubocop-erb-0.8/edge/reparse_cops_in_html.html.erb` に、rubocop-herb だけ `Style/MethodCallWithoutArgsParentheses` と `Style/RedundantParentheses` が出ない
- `rubocop-erb-0.8/edge/disable_inline.html.erb` に、0.8.2 だけ `Lint/CopDirectiveSyntax` が出る

無効化コメントの書き方ごとの例は、無効化がファイルをまたがないよう、1 ファイルずつ実行します。

```console
$ for f in rubocop-erb-0.8/disable/*.html.erb; do for t in erb072 erb082 tkherb; do echo "== $t $f"; $t --format emacs "$f"; done; done
```

- `erb_comment.html.erb`（`<%# rubocop:disable … %>`）は、0.7.2 と 0.8.2 では効かず、`Style/StringLiterals` が出る。rubocop-herb では効く
- `trailing.html.erb`、`trailing_output_tag.html.erb`（タグの中の行末のコメント）は 3 つとも効くが、0.8.2 だけ `Lint/CopDirectiveSyntax` が出る
- `multiline_range.html.erb`（複数行のタグで `rubocop:disable` と `rubocop:enable` を書く）は、0.8.2 と rubocop-herb では範囲の中だけに効く。0.7.2 では効かない

### autocorrect（コピーに対して実行すること）

```console
$ W="$TMPDIR/rerb-ac" && mkdir -p "$W/orig/herb"
$ for d in erb_lint rubocop-erb ruumba; do ditto "$d" "$W/orig/$d"; done
$ ditto herb/app "$W/orig/herb/app" && ditto herb-pr2260/edge "$W/orig/edge"
$ for t in o-safe o-all n-safe n-all tk-safe tk-all; do ditto "$W/orig" "$W/$t"; done
$ (cd "$W/o-safe" && erb072 -a .) ; (cd "$W/o-all" && erb072 -A .)
$ (cd "$W/n-safe" && erb082 -a .) ; (cd "$W/n-all" && erb082 -A .)
$ (cd "$W/tk-safe" && tkherb -a .) ; (cd "$W/tk-all" && tkherb -A .)
$ diff -r "$W/orig" "$W/n-all"
$ for t in o-safe o-all n-safe n-all tk-safe tk-all; do BUNDLE_GEMFILE="$R/v0.8.2/Gemfile" bundle exec ruby herb-pr2260/html_changes.rb "$W/orig" "$W/$t"; done
```

- 0.7.2 の `-A` で `rubocop-erb/autocorrect_safe_navigation.html.erb` が `user&&.admin?` になる。0.8.2 と rubocop-herb は HTML を変えない

`rubocop-erb-0.8/edge/` の autocorrect も同じようにコピーに対して実行します。

```console
$ E="$TMPDIR/edge08-ac" && for t in o n tk; do ditto rubocop-erb-0.8/edge "$E/$t"; done
$ (cd "$E/o" && erb072 -A .) ; (cd "$E/n" && erb082 -A .) ; (cd "$E/tk" && tkherb -A .)
$ for t in o n tk; do diff -r rubocop-erb-0.8/edge "$E/$t"; done
```

- 0.8.2 で、`single_line_block.html.erb` の 1 行のブロックが 3 行に分かれる
- rubocop-herb で、`reparse_cops_in_html.html.erb` の `root_path()`、`(a == b)`、`(foo)` の括弧が残る

### 実際のビューにかける

ビューの取得は「herb PR #2260」の節と同じです（`$V/orig` に 333 ファイル）。

```console
$ (cd "$V/orig" && for t in erb072 erb082 tkherb; do $t --format offenses .; done)
$ for t in o-safe o-all n-safe n-all tk-safe tk-all; do ditto "$V/orig" "$V/$t"; done
$ (cd "$V/o-safe" && erb072 -a .) ; (cd "$V/o-all" && erb072 -A .)
$ (cd "$V/n-safe" && erb082 -a .) ; (cd "$V/n-all" && erb082 -A .)
$ (cd "$V/tk-safe" && tkherb -a .) ; (cd "$V/tk-all" && tkherb -A .)
$ for t in o-safe o-all n-safe n-all tk-safe tk-all; do BUNDLE_GEMFILE="$R/v0.8.2/Gemfile" bundle exec ruby herb-pr2260/html_changes.rb "$V/orig" "$V/$t"; done
$ (cd "$V/n-all" && erb082 --format offenses .) ; (cd "$V/tk-all" && tkherb --format offenses .)
$ diff -r "$V/orig/rails/railties/lib/rails/generators" "$V/o-safe/rails/railties/lib/rails/generators"
```

- 333 ファイルで、0.7.2 は 762 件、0.8.2 は 763 件、rubocop-herb は 933 件
- `-a`・`-A` で HTML が変わるファイルは、3 つとも 0。`-A` でパースエラーが増えるファイルは、0.7.2 が 2、ほかの 2 つは 0
- `-A` の後に残る offense は、0.8.2 が 9 件、rubocop-herb が 126 件
- 0.7.2 の `-a` は、rails の認証ジェネレーターのテンプレートの `<%%= … %>` の中身を書き換える（`html_changes.rb` では数えられない）
