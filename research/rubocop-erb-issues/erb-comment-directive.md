# Support `rubocop:disable` directives written in ERB comments (`<%# … %>`)

## Summary

`Herb.extract_ruby` blanks ERB comments, so a directive such as `<%# rubocop:disable Style/StringLiterals %>` never reaches RuboCop. I'd like to propose supporting directives in ERB comments.

ERB comments are the usual place for notes in templates, and herb-lint already uses the same syntax for its own directives (`<%# herb:disable rule-name %>`). Today, the only form that disables a cop for a range of lines in rubocop-erb 0.8.2 is a Ruby comment inside a multi-line tag:

```erb
<%
  # rubocop:disable Style/StringLiterals
%>
```

herb-format collapses this tag into `<% # rubocop:disable … %>`, which rubocop-erb 0.8.2 also blanks. The directive then stops working without any warning. A Ruby comment at the end of a tag (`<%= "a" # rubocop:disable … %>`) works but triggers `Lint/CopDirectiveSyntax`, because `extract_ruby` appends `  ;` to the comment.

The proposal: in the extracted Ruby, turn **only the directive lines** of ERB comments into Ruby comments, in place and without changing their length. Report directives that can't be turned into Ruby comments this way with a new cop.

## Environment

- rubocop-erb 0.8.2
- rubocop 1.92.0
- herb 0.11.0 (the `extract_ruby` output was also checked with 0.11.1)
- ruby 3.3.6

## Current behavior

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

## Proposal

### Render directive lines in place

On top of the output of `Herb.extract_ruby`:

- Look at `<%# … %>` and single-line `<% # … %>` tags (both are blanked by `extract_ruby`), one line at a time.
- A line is a directive line if it reads as `# rubocop:…`. On the first line, the `#` of `<%#` is used. On later lines of a multi-line comment, the text from the start of the line is used.
- Write the directive line back into the extracted Ruby at the same position:
  - On the first line, the `#` of `<%#` stays where it is.
  - On later lines, the first whitespace character of the line becomes `#`.
  - `%>` is not copied.
- Leave every other line, and every ERB comment without a directive, blank as today.

```erb
<div>
  <%#
    Keep the legacy markup as is.
    rubocop:disable Style/StringLiterals
  %>
  <%= "a" %>
</div>
```

becomes (`·` is a space)

```
·····
·····
·································
#···rubocop:disable·Style/StringLiterals
····
······"a"··;
······
```

Because the length and the number of lines do not change, every position stays aligned with the template, and nothing else in RuboCop needs to know about ERB comments. Directive lines are ordinary Ruby comments, so `CommentConfig`, `Lint/RedundantCopDisableDirective`, `Lint/RedundantCopEnableDirective`, `Lint/MissingCopEnableDirective`, `Lint/CopDirectiveSyntax` and `Style/DirectiveScope` all work as they do for Ruby files. Whether a directive applies to one line or to a range is decided by RuboCop as usual: a directive on a line with Ruby code applies to that line, and a directive on its own line applies until `rubocop:enable`.

### Report directives that cannot be rendered

Two kinds of directive lines cannot become a Ruby comment without changing the meaning or the positions:

- **Ruby code follows on the same line**, e.g. `<%# rubocop:disable Lint/LiteralAsCondition %><% if 'hello' %>`. An ERB comment ends at `%>`, but a Ruby comment runs to the end of the line, so the `if` would be commented out.
- **A later line of a multi-line comment that starts at column 0**, e.g.

  ```erb
  <%#
  rubocop:disable Style/StringLiterals
  %>
  ```

  There is no character to replace with `#`.

These lines are left blank, so the directives don't take effect. A new cop (`Erb/IgnoredCopDirective` in my prototype) reports them, so a directive never stops working silently:

```
test.html.erb:1:3: C: Erb/IgnoredCopDirective: This directive is ignored because Ruby code follows it on the same line.
test.html.erb:1:53: W: Lint/LiteralAsCondition: Literal `'hello'` appeared as a condition.
```

## Why not render all ERB comments (`Herb.extract_ruby(source, comments: true)`)

This is a one-line change, but:

- **ERB semantics.** Ruby code after a comment on the same line is commented out:
  - `<%# heading %><% if signed_in? %>` … `<% end %>` (a valid template without any directive) reports `Lint/Syntax: unexpected token end`.
  - `<%# rubocop:disable … %><%= link_to("a", path %>` (a real syntax error) no longer reports `Lint/Syntax`.
  - In a multi-line comment, code after the closing `%>` (`%><%= "a" %>`) is commented out.
- **Positions.** With herb 0.11.0 and 0.11.1, `comments: true` makes the output longer for multi-line comments whose `%>` or text lines start at column 0:

  ```ruby
  Herb.extract_ruby("<%# a\n  b\n%>\n<%= x %>\n", comments: true)
  # => "#   a\n# b\n#  \n    x  ;\n"   (22 bytes in, 23 bytes out)
  ```

  `RubyExtractor#extracted_ruby` treats any length difference as coming from multi-byte characters, so later positions shift. With

  ```erb
  <%# multi-line comment
    second line
  %>
  <%= link_to "a", url, {remote: true} %>
  ```

  `rubocop -A` turns the last line into `<%= link_to "'a' url, {r emote: true}  %>`. With a `rubocop:disable` line at column 0, `Layout/LeadingCommentSpace` keeps inserting spaces into the comment until RuboCop stops with "Infinite loop detected". In kaigionrails/conference-app, `app/views/admin/kaminari/_page.html.erb` starts with such a comment, and its offenses on line 11 move one column to the right.
- **New offenses on ordinary comments.** Every ERB comment becomes visible to comment cops, so CI that passes today would start failing:
  - `Style/CommentAnnotation`: `<%# TODO fix this %>` is autocorrected to `<%# TODO: fix this %>`.
  - `Layout/LeadingCommentSpace`.
  - `Layout/EmptyComment`, for the `<%#` line of a multi-line comment.
  - `Layout/EmptyLineAfterMagicComment`, for `<%# encoding: utf-8 -%>`.

  Rendering whole comments only when no code follows them avoids the syntax problems, but still causes these new offenses. Rendering only directive lines avoids them.

## Prototype results

I prototyped the proposal on top of rubocop-erb 0.8.2. Each input was run on its own. "Works" means the disabled cop is not reported.

| Input | 0.8.2 | Proposal |
|---|---|---|
| `<% if 'hello' %>world<% end %><%# rubocop:disable … %>` | no | works |
| standalone `<%# rubocop:disable … %>` / `<%# rubocop:enable … %>` | no | works |
| `<% # rubocop:disable … %>` | no | works |
| `<%# rubocop:disable-next … %>` | no | works |
| `<p>日本語</p><%# rubocop:disable … %>` (multi-byte characters before the comment) | no | works |
| `<%#`⏎`  rubocop:disable …`⏎` %>` | no | works |
| `<%#`⏎`  description`⏎`  rubocop:disable …`⏎`%>` | no | works |
| two directives in one multi-line comment | no | both work |
| `<%= "a" %><%#`⏎`  rubocop:disable …`⏎`%>` | no | works from line 2 |
| `<%#`⏎`  rubocop:disable …`⏎`%><%= "a" %>` | no | works |
| `<%# rubocop:disable … %><% if 'hello' %>…` | no | not applied, `Erb/IgnoredCopDirective` |
| `<%#`⏎`rubocop:disable …`⏎`%>` (column 0) | no | not applied, `Erb/IgnoredCopDirective` |
| `<%# rubocop:disable %>` (no cop name) | — | `Lint/CopDirectiveSyntax` |
| `<%# rubocop:enable X %>` without a matching disable | — | `Lint/RedundantCopEnableDirective` |
| `<%# rubocop:pop %>` without a matching push | — | `Lint/RedundantCopEnableDirective` |
| disable/enable pair around a single statement | — | `Style/DirectiveScope` |
| ordinary comments (`<%# TODO fix this %>`, `<%#no space %>`, `<% if x %><%# note %>`, …) | — | same as 0.8.2 |

- On 333 real views (rails/rails `0f591639b8` and kaigionrails/conference-app `25a02cc`, none of which contain `rubocop:` in ERB comments), the proposal reports the same 763 offenses as 0.8.2.
- With `rubocop -A`, the proposal changes the same code as 0.8.2, except where a directive now suppresses the offense. ERB comments are never rewritten.
- Lines with directives behave as they would in Ruby. With rubocop-erb's ERB exclusion of `Layout/EmptyLineAfterGuardClause` lifted, a guard clause followed by `<%# rubocop:enable … %>` and then code reports that cop. A `rescue` whose body is only a directive comment is not reported by `Lint/SuppressedException` (`AllowComments`). Ordinary ERB comments stay blank, so they behave as in 0.8.2.

## Open questions

- **A new cop.** rubocop-erb has no cops of its own yet. Reporting ignored directives needs one (a department name such as `Erb`, a default configuration, documentation). Alternatively, the extractor could print a warning, but an offense works better with CI.
- **Comment-only bodies.** `<% if some_error %><%# rubocop:disable Lint/EmptyConditionalBody %>`⏎`<% end %>` reports nothing, but not because of the directive: `Lint/EmptyConditionalBody` (`AllowComments: true`, enabled for `.erb` for this check) treats the directive as the body. `Lint/RedundantCopDisableDirective` is not reported either. Ruby behaves the same way with a `# rubocop:disable` comment as the only body, so this is not specific to ERB.
- **Lines with only HTML.** `<%# rubocop:disable … %><p>a</p>` has no Ruby tokens on its line, so RuboCop treats the directive as being on its own line, and it applies until `rubocop:enable` or the end of the file. This follows the Ruby rule, but it may be surprising in a template.
- **Removing redundant directives.** `Lint/RedundantCopDisableDirective` and `Lint/RedundantCopEnableDirective` report redundant directives, but `RuboCop::Erb::Corrector` discards their corrections, because the range starts at the `#` of `<%#`. Even if the correction were allowed, removing only the directive text would likely leave parts of the tag behind. A proper correction should probably remove the whole tag (or the whole line of a multi-line comment).

## Prototype

The core of the extractor change:

```ruby
# For each directive line of each ERB comment:
#   hash_pos   - byte offset of the `#` (the `#` of `<%#` on the first line, the line start on later lines)
#   text       - the Ruby comment to write there, without `%>`
#   renderable - false when Ruby code follows on the same line, or a later line starts at column 0
def extracted_ruby
  ruby = Herb.extract_ruby(template_source).b
  directive_lines.each do |line|
    ruby[line[:hash_pos], line[:text].bytesize] = line[:text].b if line[:renderable]
  end
  # ... then the existing realignment for multi-byte characters
end
```

I have a working prototype of the extractor change and the cop, and can open a PR if this direction looks acceptable.
