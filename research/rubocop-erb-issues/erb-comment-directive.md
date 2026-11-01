# Support `rubocop:disable` in ERB comments (`<%# … %>`)

`Herb.extract_ruby` blanks ERB comments, so `<%# rubocop:disable Style/StringLiterals %>` has no effect. I'd like rubocop-erb to support directives written in ERB comments. ERB comments are the natural place for them in templates, and herb-lint uses the same form for its own directives (`<%# herb:disable … %>`).

I see two ways to implement this, and I recommend the second.

## Option 1: Render all ERB comments

Use `Herb.extract_ruby(source, comments: true)`, which turns every ERB comment into a Ruby comment.

- Pros
  - A one-line change.
- Cons
  - Code after a comment on the same line is commented out, because an ERB comment ends at `%>` but a Ruby comment runs to the end of the line. A valid template such as `<%# note %><% if x %>` … `<% end %>` reports `Lint/Syntax`, and a real syntax error after a comment goes unreported.

## Option 2: Render only directives, when it is safe (recommended)

Write only `rubocop:` directives back into the extracted Ruby, in place. For example, `<%# rubocop:disable … %>` becomes `  # rubocop:disable …`. A directive is written back only when no Ruby code follows it on the same line.

- Pros
  - Code is never commented out.
  - Other ERB comments stay blank, so existing results don't change. In my prototype, 333 real views from rails/rails and kaigionrails/conference-app give the same 763 offenses as 0.8.2.
- Cons
  - A directive followed by Ruby code on the same line (`<%# rubocop:disable … %><% if x %>`) cannot be supported. Users need to be told about it, for example by a cop.
  - More code than option 1.

I have a prototype of option 2 and can open a PR if this direction sounds good.
