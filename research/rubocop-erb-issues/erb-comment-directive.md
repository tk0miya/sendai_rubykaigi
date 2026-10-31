# Support `rubocop:disable` in ERB comments (`<%# … %>`)?

`Herb.extract_ruby` blanks ERB comments, so `<%# rubocop:disable Style/StringLiterals %>` has no effect. ERB comments are the natural place for directives in templates (herb-lint uses `<%# herb:disable … %>`). The current workaround is a Ruby comment in a multi-line tag (`<%`⏎`  # rubocop:disable …`⏎`%>`), and it stops working once herb-format collapses the tag into `<% # … %>`.

Would you accept support for this? If so, this is the direction I have in mind.

## Proposal

Write only directive comments back into the extracted Ruby, in place, when it is safe:

- `<%# rubocop:disable … %>` becomes `  # rubocop:disable …`. The `#` of `<%#` is already where the Ruby comment starts, so no position changes.
- This happens only when no Ruby code follows on the same line. Otherwise that code would be commented out.
- All other ERB comments stay blank, so existing results don't change. In my prototype, 333 real views from rails/rails and kaigionrails/conference-app give the same 763 offenses as 0.8.2.

## Why not `Herb.extract_ruby(source, comments: true)`

- It comments out code that follows a comment on the same line: `<%# note %><% if x %>` … `<% end %>` reports `Lint/Syntax`.
- It shifts positions after some multi-line comments, and autocorrect then breaks the template.
- It adds offenses to ordinary comments (`Style/CommentAnnotation`, `Layout/EmptyComment`, …), so CI that passes today would fail.

## Open questions

- **Multi-line comments.** Support only single-line `<%# rubocop:… %>`, or also directive lines inside multi-line comments? The latter needs extra conditions, such as indentation.
- **Directives that can't be applied** (Ruby code follows on the same line). Should they be reported by a new cop, by a warning, or only in the documentation?

I have a prototype and can open a PR once the direction is agreed.
