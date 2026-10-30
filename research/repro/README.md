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
$ (cd "$TMPDIR/rubocop-herb" && git checkout 6601d3efd1dd1310f5d896a9e0e643061af835ff && bundle install)
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
- `herb/app/views/samples/cross_tag_variables.html.erb` の `<% unused = 1 %>` は `<% 1 %>` になる。続いて出る `Lint/Void` は、修正すると `<%` が消えるので修正されない（autocorrect できない offense として残る。下の「未解決の問題」）

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

- `missing_close.html.erb`、`cross_tag_variables.html.erb`、`identical_branches_output.html.erb` に、herb-lint 単体と同じ offense が `Herb/Linting: [rule-name] …` として出る
- `missing_end.html.erb` には herb-lint 単体では `parser-no-errors` が出るが、`Herb/Linting` は出ない（Ruby の構文エラーがあるファイルでは herb-lint を実行しない）。`Lint/Syntax` は出る
- `herb/` で実行すると、`@herb-tools/linter is not installed in …/research/repro` というエラーが出る

### 未解決の問題

`rubocop-herb/` の再現例です。autocorrect はコピーに対して実行します。

```console
$ cd rubocop-herb
$ rubocop-herb .
$ cp -R . "$TMPDIR/rubocop-herb-ac" && cd "$TMPDIR/rubocop-herb-ac"
$ rubocop-herb -A --only Style/IdenticalConditionalBranches .
$ diff -r "$OLDPWD" .
```

- 同じ出力タグを分岐の外に移すと、出力されなくなる（`identical_branches_output.html.erb`）: `Style/IdenticalConditionalBranches`（`[Correctable]`。安全でない修正なので `-a` では修正されない）が出る。`-A` で、両方の分岐の `<%= foo %>` が消え、`<% end %>` が `<% end`⏎`   _ = foo %>` になる（`foo` が出力されなくなる）
- `--only` を付けずに `-A` すると、続けて `Style/EmptyElse` なども修正される

```console
$ rubocop-herb -a useless_assignment_leaves_void.html.erb
$ diff "$OLDPWD/useless_assignment_leaves_void.html.erb" useless_assignment_leaves_void.html.erb
```

- 未使用の変数への代入が `<% 1 %>` で止まる（`useless_assignment_leaves_void.html.erb`）: `-a` で `Lint/UselessAssignment` が修正され、`<% unused = 1 %>` が `<% 1 %>` になる。続いて出る `Lint/Void` は修正されず（`[Correctable]` が付かない）、offense が残る。同じ内容の Ruby ファイルなら、代入文ごと消える

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
