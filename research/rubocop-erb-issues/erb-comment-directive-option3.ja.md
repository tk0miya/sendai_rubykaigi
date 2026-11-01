[erb-comment-directive-option3.md](erb-comment-directive-option3.md)（[r7kamura/rubocop-erb#84](https://github.com/r7kamura/rubocop-erb/issues/84) への返信の下書き）の日本語版です。

ご検討の材料として、もう 1 つの方針を共有させてください。issue を出す前に検討しましたが、技術上の問題があって提案しなかったものです。欠点はありますが、新しい cop は要りません。

## 方針 3: ERB のコメントを出力せずに RuboCop に渡す

取り出した Ruby はそのままにして、ERB のコメントをコメントのオブジェクトとして `processed_source.comments` に足します。

- Pros
  - RuboCop は `processed_source.comments` を見て、どこでどの cop を無効にするかを決めるので、どこに書いた directive も Ruby と同じ規則で効く。そのため cop は要らない
  - 取り出した Ruby を変えないので、`Herb.extract_ruby` の出力にさらに依存することはない
- Cons
  - コメントを `processed_source.comments` ではなく、ソースの文字列から探す cop が正しく動かない。ERB のコメントの位置のソースは空白だから
    - `Lint/RedundantCopEnableDirective` は、`processed_source.raw_source` に `enable` が含まれないと何もしないので、不要な `<%# rubocop:enable … %>` を報告しない
    - 20 個ほどの cop は、コメントの行かどうかをソースの文字列で判断する（`RuboCop::Cop::Util#comment_line?`）ので、`processed_source.comments` と食い違う。`Metrics/MethodLength` や `Lint/SuppressedException`（`AllowComments`）のように、コードを検査する cop も含まれる。たとえば `Style/CommentAnnotation` は、ERB のコメントをすべて行末のコメントと見なして、続いたコメントの各行を調べる。Ruby では、続いたコメントは 1 行目だけを調べる
    - 直すには、これらの cop に 1 つずつパッチを当てる必要がある

**例**

テンプレート：

```erb
<%# rubocop:disable Lint/LiteralAsCondition %><% if 'b' %>
  <p>b</p>
<% end %>
<%# rubocop:enable Style/StringLiterals %>
<div>
  <%# TODO fix this %>
  <%# TODO fix that %>
</div>
```

1 行目の directive は効くので、`Lint/LiteralAsCondition` は出ません。一方で、4 行目の不要な `rubocop:enable` は報告されず、`Style/CommentAnnotation` は 6 行目と 7 行目の両方に出ます。同じコメントを Ruby のファイルに書くと、`Lint/RedundantCopEnableDirective` が出て、`Style/CommentAnnotation` は 1 つ目の `TODO` の行にだけ出ます。

```console
$ rubocop app/views/posts/show.html.erb
Inspecting 1 file
C

Offenses:

app/views/posts/show.html.erb:6:7: C: [Correctable] Style/CommentAnnotation: Annotation keywords like TODO should be all upper case, followed by a colon, and a space, then a note describing the problem.
  <%# TODO fix this %>
      ^^^^^
app/views/posts/show.html.erb:7:7: C: [Correctable] Style/CommentAnnotation: Annotation keywords like TODO should be all upper case, followed by a colon, and a space, then a note describing the problem.
  <%# TODO fix that %>
      ^^^^^

1 file inspected, 2 offenses detected, 2 offenses autocorrectable
```

これらの cop に 1 つずつパッチが要ることから、提案しませんでした。これを避けるには、ソースの文字列にないコメントをこれらの cop に伝える仕組みが、RuboCop 本体に要ります。
