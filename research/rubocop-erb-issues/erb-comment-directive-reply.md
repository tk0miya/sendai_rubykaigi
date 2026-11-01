Thank you for the reply, and for keeping the issue open.

I'd like to clarify one point about option 2. Directives that cannot be applied are not reported by a warning. A cop reports them as regular RuboCop offenses, alongside the other offenses. They appear in editors in the same way, and they fail CI (exit status 1) until they are fixed. The message also tells users how to fix them.

For example, with this template:

```erb
<%# rubocop:disable Lint/LiteralAsCondition %><% if 'b' %>
  <p>b</p>
<% end %>
```

`rubocop` reports:

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

After moving the directive as the message says, there are no offenses:

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

So a directive never stops working silently: either it takes effect, or RuboCop reports it. The rule users need to know is also the one they already follow in Ruby: a `# rubocop:disable` comment cannot be followed by code on the same line.

What do you think?
