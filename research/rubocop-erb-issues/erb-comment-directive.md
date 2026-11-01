# Support `rubocop:disable` in ERB comments (`<%# … %>`)

`Herb.extract_ruby` blanks ERB comments, so `<%# rubocop:disable Style/StringLiterals %>` has no effect. I'd like rubocop-erb to support directives written in ERB comments. ERB comments are the natural place for them in templates, and herb-lint uses the same form for its own directives (`<%# herb:disable … %>`).

I see two ways to implement this, and I recommend the second.

## Option 1: Render all ERB comments

Use `Herb.extract_ruby(source, comments: true)`, which turns every ERB comment into a Ruby comment.

- Pros
  - A one-line change.
- Cons
  - Comment nodes, which ERB never renders, are rendered, and this causes unintended behavior. Specifically, code after a comment is treated as part of the comment.
    - For example, a valid template such as `<%# note %><% if x %>` … `<% end %>` reports `Lint/Syntax`, and a real syntax error after a comment goes unreported.

## Option 2: Render only directives, when it is safe (recommended)

Write only `rubocop:` directives back into the extracted Ruby, in place. For example, `<%# rubocop:disable … %>` becomes `  # rubocop:disable …`. A directive is written back only when no Ruby code follows it on the same line.

- Pros
  - Comments that would break code are not written back, so code is never treated as part of a comment.
  - Other ERB comments stay blank, so existing results don't change. In my prototype, 333 real views from rails/rails and kaigionrails/conference-app give the same 763 offenses as 0.8.2.
- Cons
  - Some directives are not written back and have no effect: those followed by Ruby code on the same line, such as `<%# rubocop:disable … %><% if x %>`. This happens implicitly and may confuse users.
    - A cop that detects such directives would avoid this.
  - Ordinary comments are not written back, so they are not linted (same as 0.8.2). For example, `<%# TODO fix this %>` gets no `Style/CommentAnnotation`.
  - More code than option 1.

I have a prototype of option 2 and can open a PR if this direction sounds good.
