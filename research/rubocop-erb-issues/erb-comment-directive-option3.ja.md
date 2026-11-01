[erb-comment-directive-option3.md](erb-comment-directive-option3.md)（[r7kamura/rubocop-erb#84](https://github.com/r7kamura/rubocop-erb/issues/84) への返信の下書き）の日本語版です。

ご検討の材料として、もう 1 つの方針を共有させてください。issue を出す前に検討しましたが、技術上の問題があって提案しなかったものです。欠点はありますが、新しい cop は要りません。

## 方針 3: 無効化コメントを出力せずに RuboCop に渡す

取り出した Ruby はそのままにします。ERB のコメントからコメントのオブジェクトを作り、RuboCop の `CommentConfig`（どの行でどの cop を無効にするかを決める部分）にだけ渡します。

- Pros
  - どこに書いた directive も、Ruby と同じ規則で効く。コードのある行に書けばその行に、独立した行に書けば `rubocop:enable` までの範囲に効く。そのため cop は要らない
  - 取り出した Ruby を変えないので、`Herb.extract_ruby` の出力にさらに依存することはない
- Cons
  - RuboCop の内部に依存する。private な `CommentConfig#each_directive` を上書きし、`CommentConfig` の内部の変数 `@no_directives` を判定し直す
  - `CommentConfig` を通さずに directive を探す cop には届かない。`Lint/RedundantCopEnableDirective`（`processed_source.raw_source` を調べる）、`Lint/CopDirectiveSyntax` と `Style/DirectiveScope`（`processed_source.comments` を読む）で、cop ごとにパッチが要る。代わりに ERB のコメントを `processed_source.comments` に足す形もうまくいかない。ソースの行の文字列でコメントの行を見分ける cop が 20 個ほどあり、その位置のソースは空白なので、`processed_source.comments` と食い違う。たとえば `Style/InlineComment` が、独立した行の `<%# heading %>` を行末のコメントとして報告する

**例**

テンプレート：

```erb
<%# rubocop:disable Lint/LiteralAsCondition %><% if 'b' %>
  <p>b</p>
<% end %>
```

`rubocop` の offense は 0 件です。0.8.2 では 1 行目に `Lint/LiteralAsCondition` が出ます。

```console
$ rubocop app/views/posts/show.html.erb
Inspecting 1 file
.

1 file inspected, no offenses detected
```

RuboCop の内部への依存と、cop ごとのパッチが必要なことから、提案しませんでした。これらを避けるには、`processed_source.comments` 以外から directive を足す口が RuboCop 本体に要ります。
