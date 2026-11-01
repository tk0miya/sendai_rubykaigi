# Support `rubocop:disable` in ERB comments (`<%# … %>`)

`Herb.extract_ruby` blanks ERB comments, so `<%# rubocop:disable Style/StringLiterals %>` has no effect. I'd like rubocop-erb to support directives written in ERB comments. ERB comments are the natural place for them in templates, and herb-lint uses the same form for its own directives (`<%# herb:disable … %>`).

I see two ways to implement this, and I recommend the second.

## Option 1: Render all ERB comments

Use `Herb.extract_ruby(source, comments: true)`, which turns every ERB comment into a Ruby comment. It is a one-line change, but ERB comments are never processed by ERB, and this turns them into Ruby code, which RuboCop then misreads:

- **Code after a comment is commented out.** An ERB comment ends at `%>`, but a Ruby comment runs to the end of the line. A valid template such as `<%# note %><% if x %>` … `<% end %>` reports `Lint/Syntax`, and a real syntax error after a comment on the same line goes unreported.
- **Multi-line comments break too.** In a valid template like the one below, the `if` after `%>` is commented out, and RuboCop reports `Lint/Syntax: unexpected token end`:

  ```erb
  <%#
    Show the menu only to signed-in users.
  %><% if signed_in? %>
    <p>menu</p>
  <% end %>
  ```

## Option 2: Render only directives, when it is safe (recommended)

Write only `rubocop:` directives back into the extracted Ruby, in place:

- `<%# rubocop:disable … %>` becomes `  # rubocop:disable …`. The `#` of `<%#` is already where a Ruby comment would start, so no position changes.
- A directive is written back only when no Ruby code follows it on the same line. Directives that cannot be written back would need to be reported to users, for example by a cop.
- All other ERB comments stay blank, so existing results don't change. In my prototype, 333 real views from rails/rails and kaigionrails/conference-app give the same 763 offenses as 0.8.2.

I have a prototype of option 2 and can open a PR if this direction sounds good.
