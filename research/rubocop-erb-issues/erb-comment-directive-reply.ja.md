[erb-comment-directive-reply.md](erb-comment-directive-reply.md)（[r7kamura/rubocop-erb#84](https://github.com/r7kamura/rubocop-erb/issues/84) への返信の下書き）の日本語版です。

返信と、issue を開いたままにしてくださったことに感謝します。

方針 2 について、1 点補足させてください。適用できない directive は、警告で知らせるのではありません。cop が、ほかの offense と同じく RuboCop の通常の指摘として報告します。エディタにも同じように表示され、直すまで CI は失敗します（終了コード 1）。メッセージには直し方も書きます。

たとえば、次のテンプレートでは

```erb
<%# rubocop:disable Lint/LiteralAsCondition %><% if 'b' %>
  <p>b</p>
<% end %>
```

`rubocop` は次のように報告します。

```console
$ rubocop app/views/posts/show.html.erb
Inspecting 1 file
W

Offenses:

app/views/posts/show.html.erb:1:3: C: Erb/IgnoredCopDirective: This directive has no effect because Ruby code follows it on the same line. Move it after the code or to its own line.
<%# rubocop:disable Lint/LiteralAsCondition %><% if 'b' %>
  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
app/views/posts/show.html.erb:1:53: W: Lint/LiteralAsCondition: Literal 'b' appeared as a condition.
<%# rubocop:disable Lint/LiteralAsCondition %><% if 'b' %>
                                                    ^^^

1 file inspected, 2 offenses detected
```

メッセージのとおりに directive を移すと、offense はなくなります。

```erb
<% if 'b' %><%# rubocop:disable Lint/LiteralAsCondition %>
  <p>b</p>
<% end %>
```

```console
$ rubocop app/views/posts/show.html.erb
Inspecting 1 file
.

1 file inspected, no offenses detected
```

つまり、directive が黙って効かなくなることはありません。効くか、RuboCop が指摘するかのどちらかです。利用者が知る必要のある規則も、Ruby ですでに守っているものと同じです。`# rubocop:disable` のコメントの後ろに、同じ行でコードを書くことはできません。

いかがでしょうか。
