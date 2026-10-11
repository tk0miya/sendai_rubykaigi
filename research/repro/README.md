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

[../report.md](../report.md) の再現手順です。rubocop-herb は rubygems に公開されていないので、リポジトリを clone して、その `Gemfile` と開発用の設定（`config/develop/*.yml`）を使います。

```console
$ git clone https://github.com/tk0miya/rubocop-herb "$TMPDIR/rubocop-herb"
$ (cd "$TMPDIR/rubocop-herb" && git checkout 14830806e5deb61e27744e9fed09c5380ccbeee7 && bundle install)
$ export RUBOCOP_HERB="$TMPDIR/rubocop-herb"
$ alias rubocop-herb='BUNDLE_GEMFILE="$RUBOCOP_HERB/Gemfile" bundle exec rubocop --cache false --except Herb/Linting'
```

- `--except Herb/Linting` は、herb-lint（Node.js の `@herb-tools/linter`）を入れていない環境で、セットアップを促すエラーを出さないためのものです。RuboCop の結果だけを比べます

### 既存ツールの再現例にかける

```console
$ rubocop-herb -c "$RUBOCOP_HERB/config/develop/rubocop.yml" erb_lint rubocop-erb ruumba herb/app
```

- erb_lint / rubocop-erb で見逃していた `Style/NilComparison`、`Style/NegatedIf` などを検出する
- erb_lint の `Lint/UselessAssignment`、ruumba の `Lint/Void`・`Style/SymbolProc`・`Lint/EmptyConditionalBody`・Layout 系の誤検知は出ない
- `erb_lint/recommended/control_flow.html.erb` の本当に空の `else` / `unless` には `Style/EmptyElse` / `Lint/EmptyConditionalBody` が出る
- `herb/app/views/samples/missing_end.html.erb` に `Lint/Syntax` が出る

autocorrect はコピーに対して実行します。

```console
$ cp -R . "$TMPDIR/repro-herb" && cd "$TMPDIR/repro-herb"
$ rubocop-herb -c "$RUBOCOP_HERB/config/develop/rubocop.yml" -A erb_lint rubocop-erb ruumba herb/app
$ diff -r "$OLDPWD" .
```

- `count -1` は `count - 1`、`user && user.admin?` は `user&.admin?` に正しく修正される
- `herb/app/views/samples/cross_tag_variables.html.erb` は壊れる（下の「文の削除が `<%` ごと消す」）

### 未解決の問題

`rubocop-herb/` の再現例です。autocorrect はコピーに対して実行します。

```console
$ cd rubocop-herb
$ rubocop-herb -c "$RUBOCOP_HERB/config/develop/rubocop.yml" .
$ cp -R . "$TMPDIR/rubocop-herb-ac" && cd "$TMPDIR/rubocop-herb-ac"
$ rubocop-herb -c "$RUBOCOP_HERB/config/develop/rubocop.yml" -a .
$ diff -r "$OLDPWD" .
```

- 文の削除が `<%` ごと消す（`void_removal.html.erb`, `useless_assignment_removal.html.erb`）: `-a` で `<% 1 %>` や `<% x = 1 %>` の `<% …` の部分が消え、` %>` だけが残る（前に行があれば、その行の末尾につながる）