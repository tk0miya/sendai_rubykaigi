# Should `rubocop:disable` directives in ERB comments (`<%# … %>`) be supported?

## Summary

`Herb.extract_ruby` blanks ERB comments, so a directive such as `<%# rubocop:disable Style/StringLiterals %>` never reaches RuboCop. I'd like to ask:

1. whether supporting directives written in ERB comments is in scope for rubocop-erb, and
2. if so, which implementation direction you would prefer.

Below are the background, two directions I looked into, and the open points I'd like your opinion on. I have a prototype for the second direction and can open a PR once the direction is settled.

## Background

ERB comments are the usual place for notes in templates, and herb-lint already uses the same syntax for its own directives (`<%# herb:disable rule-name %>`). In rubocop-erb 0.8.2, the only form that disables a cop for a range of lines is a Ruby comment inside a multi-line tag:

```erb
<%
  # rubocop:disable Style/StringLiterals
%>
```

herb-format collapses this tag into `<% # rubocop:disable … %>`, which rubocop-erb 0.8.2 also blanks, so the directive stops working without any warning. A Ruby comment at the end of a tag (`<%= "a" # rubocop:disable … %>`) works but triggers `Lint/CopDirectiveSyntax`, because `extract_ruby` appends `  ;` to the comment.

### Current behavior

Environment: rubocop-erb 0.8.2, rubocop 1.92.0, herb 0.11.0, ruby 3.3.6.

`.rubocop.yml`:

```yaml
plugins:
  - rubocop-erb
AllCops:
  NewCops: enable
  SuggestExtensions: false
  TargetRubyVersion: 3.4
```

```erb
<%# rubocop:disable Style/StringLiterals %>
<p><%= "a" %></p>
<%# rubocop:enable Style/StringLiterals %>
```

```console
$ bundle exec rubocop --format emacs --stdin test.html.erb < test.html.erb
test.html.erb:2:8: C: [Correctable] Style/StringLiterals: Prefer single-quoted strings when you don't need string interpolation or special symbols.
```

## Possible directions

### A. Render all ERB comments (`Herb.extract_ruby(source, comments: true)`)

This is a one-line change, but I don't think it is acceptable as the default:

- **It breaks ERB semantics.** An ERB comment ends at `%>`, but a Ruby comment runs to the end of the line, so Ruby code after the comment is commented out:
  - `<%# heading %><% if signed_in? %>` … `<% end %>` (a valid template without any directive) reports `Lint/Syntax: unexpected token end`.
  - `<%# rubocop:disable … %><%= link_to("a", path %>` (a real syntax error) no longer reports `Lint/Syntax`.
- **It shifts positions.** With herb 0.11.0 and 0.11.1, `comments: true` makes the output longer for multi-line comments whose `%>` or text lines start at column 0:

  ```ruby
  Herb.extract_ruby("<%# a\n  b\n%>\n<%= x %>\n", comments: true)
  # => "#   a\n# b\n#  \n    x  ;\n"   (22 bytes in, 23 bytes out)
  ```

  `RubyExtractor#extracted_ruby` treats any length difference as coming from multi-byte characters, so later positions shift. In my tests, `rubocop -A` turned `<%= link_to "a", url, {remote: true} %>` after such a comment into `<%= link_to "'a' url, {r emote: true}  %>`, and a column-0 `rubocop:disable` line made RuboCop stop with "Infinite loop detected".
- **It adds offenses to ordinary comments**, so CI that passes today would start failing:
  - `Style/CommentAnnotation` (`<%# TODO fix this %>`)
  - `Layout/LeadingCommentSpace` (`<%#no space %>`)
  - `Layout/EmptyComment` (the `<%#` line of a multi-line comment)
  - `Layout/EmptyLineAfterMagicComment` (`<%# encoding: utf-8 -%>`)

### B. Render only directives that meet certain conditions (proposed)

Keep ERB comments blank as today, except directive lines (`# rubocop:…`) that can be written into the extracted Ruby in place, without changing the length or the meaning:

- On the first line of an ERB comment, the `#` of `<%#` is already where a Ruby comment would start.
- Nothing but HTML may follow the directive on the same line. Otherwise the Ruby code after it would be commented out, as in A.

Ordinary comments are untouched, so the existing results do not change. Directive lines become ordinary Ruby comments, so the directive-related cops (`Lint/RedundantCopDisableDirective`, `Lint/RedundantCopEnableDirective`, `Lint/MissingCopEnableDirective`, `Lint/CopDirectiveSyntax`, `Style/DirectiveScope`) work as they do for Ruby files, with no changes to RuboCop.

Some directives cannot be supported this way, for example `<%# rubocop:disable Lint/LiteralAsCondition %><% if 'hello' %>`, where Ruby code follows on the same line. These would not take effect.

In my prototype on 333 real views (rails/rails `0f591639b8` and kaigionrails/conference-app `25a02cc`, none of which contain `rubocop:` in ERB comments), B reports the same 763 offenses as 0.8.2, and `rubocop -A` never rewrites an ERB comment.

## Questions

1. **Is this in scope?** Would you accept support for directives written in ERB comments in rubocop-erb?
2. **Direction.** Is B acceptable, or would you prefer another approach?
3. **Multi-line comments.** Should B handle directives inside multi-line ERB comments, and if so, how?
   - **Only single-line `<%# rubocop:… %>` comments.** The only condition is that no Ruby code follows on the same line. Directives inside multi-line comments are not supported.
   - **Each line of a multi-line comment.** This allows a description before the directive and several directives in one comment, for example:

     ```erb
     <%#
       Keep the legacy markup as is.
       rubocop:disable Style/StringLiterals
     %>
     ```

     It needs more conditions: the line must be indented by at least two characters (so `# ` fits in front), Ruby code must not follow the closing `%>`, and `#rubocop:` without a space has to be excluded. Otherwise `Layout/LeadingCommentSpace` would autocorrect the ERB comment.
4. **Directives that cannot be supported.** How should users learn that a directive is ignored?
   - a new cop such as `Erb/IgnoredCopDirective`, which would be rubocop-erb's first cop
   - a warning from the extractor
   - documentation only
5. **Edge cases.** Are these acceptable as they are?
   - **Lines with only HTML.** `<%# rubocop:disable … %><p>a</p>` has no Ruby tokens on its line, so the directive applies until `rubocop:enable` or the end of the file, as a directive on its own line does in Ruby.
   - **Comment-only bodies.** A directive that is the only content of an `if` body counts as a comment for `Lint/EmptyConditionalBody` (`AllowComments: true`). Ruby behaves the same.
   - **Removing redundant directives.** `Lint/RedundantCopDisableDirective` reports a redundant ERB directive, but `RuboCop::Erb::Corrector` discards the correction, because the range starts at the `#` of `<%#`. Removing such a directive would probably mean removing the whole tag.
