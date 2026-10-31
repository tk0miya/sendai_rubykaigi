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

I prototyped three approaches on top of rubocop-erb 0.8.2 and compared them. I propose approach 3 below: pass ERB comments to RuboCop as directive comments only, without changing the extracted Ruby.

## Environment

- rubocop-erb 0.8.2
- rubocop 1.92.0, rubocop-ast 1.50.0
- herb 0.11.0 (the `extract_ruby` output was also checked with 0.11.1)
- ruby 3.3.6

## Current behavior

```erb
<%# rubocop:disable Style/StringLiterals %>
<p><%= "a" %></p>
<%# rubocop:enable Style/StringLiterals %>
```

`.rubocop.yml`:

```yaml
plugins:
  - rubocop-erb
AllCops:
  NewCops: enable
  SuggestExtensions: false
  TargetRubyVersion: 3.4
```

```console
$ bundle exec rubocop --format emacs --stdin test.html.erb < test.html.erb
test.html.erb:2:8: C: [Correctable] Style/StringLiterals: Prefer single-quoted strings when you don't need string interpolation or special symbols.
```

## Approaches considered

### 1. `Herb.extract_ruby(source, comments: true)`

This is a one-line change, but it does not follow ERB semantics. An ERB comment ends at `%>`, while a Ruby comment runs to the end of the line, so any Ruby code after the comment on the same line is commented out:

- `<%# heading %><% if signed_in? %>` … `<% end %>` (a valid template, no directive) reports `Lint/Syntax: unexpected token end`
- `<%# rubocop:disable … %><%= link_to("a", path %>` (a real syntax error) no longer reports `Lint/Syntax`
- in a multi-line comment, code after the closing `%>` (`%><%= "a" %>`) is commented out

With herb 0.11.0 and 0.11.1, `comments: true` also stops preserving positions for multi-line comments whose `%>` or text lines start at column 0. `extract_ruby` inserts `#` at the start of each line, so those lines get longer:

```ruby
Herb.extract_ruby("<%# a\n  b\n%>\n<%= x %>\n", comments: true)
# => "#   a\n# b\n#  \n    x  ;\n"   (22 bytes in, 23 bytes out)
```

`RubyExtractor#extracted_ruby` treats any length difference as coming from multi-byte characters, so every position after the comment shifts. Autocorrect then breaks templates:

```erb
<%# multi-line comment
  second line
%>
<%= link_to "a", url, {remote: true} %>
```

`rubocop -A` turns the last line into `<%= link_to "'a' url, {r emote: true}  %>`. With `rubocop:disable` at column 0 inside a multi-line comment, `Layout/LeadingCommentSpace` keeps inserting spaces into the comment until RuboCop stops with "Infinite loop detected". This also happens in real views: in kaigionrails/conference-app, `app/views/admin/kaminari/_page.html.erb` starts with a multi-line comment, and its offenses on line 11 move one column to the right.

Finally, every ERB comment becomes visible to cops that inspect comments. `Style/CommentAnnotation` (`<%# TODO fix this %>` is autocorrected to `<%# TODO: fix this %>`), `Layout/LeadingCommentSpace`, `Layout/EmptyComment` and `Layout/EmptyLineAfterMagicComment` (`<%# encoding: utf-8 -%>`) start reporting. `Lint/EmptyConditionalBody` (`AllowComments: true`) stops reporting an empty `if` that contains a comment:

```erb
<% if x %><%# note %>
<% end %>
```

(rubocop-erb excludes `Lint/EmptyConditionalBody` for `*.erb` by default. It was enabled for this check and for the `@comment_index` case below.)

### 2. Render a comment only when it is safe

Turn an ERB comment into a Ruby comment only when no Ruby code follows it on the same line. tk0miya/rubocop-herb uses a stricter version of this (it also requires that no tag or HTML follows). It avoids the syntax problems above. However, whether a directive works now depends on details that users cannot see, and when it doesn't work, nothing reports it:

- `<%# rubocop:disable … %><% if 'hello' %>` (code to the right)
- `<%#` … `%><%= "a" %>` (code after the closing tag of a multi-line comment)
- a multi-line comment with a line starting at column 0. Such a line cannot become a Ruby comment without changing its length, because there is no space for the `#`.

A separate cop would be needed to report ignored directives (rubocop-herb has `Herb/IgnoredCopDirective`). The side effects on comment-inspecting cops from approach 1 remain.

### 3. Pass ERB comments to `CommentConfig` only (proposed)

Keep the extracted Ruby as it is. Build `Parser::Source::Comment` objects from the ERB comments, and give them only to the `CommentConfig` that `ERBSource#comment_config` returns.

- Both `<%# … %>` and single-line `<% # … %>` are covered (`extract_ruby` blanks both)
- Each line of a multi-line ERB comment becomes its own comment. `DirectiveComment` only reads the first `# rubocop:` of a comment text, so passing the whole comment as one text would silently ignore a second directive and a directive written after a description line
- The comment text is the template text (`# rubocop:disable …`), and the range points at the template, so `DirectiveComment#range` and offense locations match the ERB source. The exception is a line of a multi-line comment that starts at column 0: there `#` is prepended, so the text is one character longer than its range
- Whether a directive covers one line or a range is left to RuboCop (whether the line has Ruby tokens). `<%# rubocop:disable … %><% if 'hello' %>` therefore applies to that line only, the same way as `herb:disable` applies to the line it is written on

The rest of RuboCop does not see these comments, so the other offenses and autocorrections stay exactly as in 0.8.2.

Two cases need extra care:

- `CommentConfig#initialize` skips everything when `raw_source` does not include `rubocop`. For an `ERBSource`, `raw_source` is the extracted Ruby, so this check has to use the template instead.
- Some cops find directives without going through `CommentConfig`, so they don't see the ERB comments:

  | Cop | Where it looks |
  |---|---|
  | `Lint/RedundantCopEnableDirective` | runs only if `processed_source.raw_source` includes `enable` / `pop`. Orphan `pop`s are looked up in `processed_source.comments` |
  | `Lint/CopDirectiveSyntax` | `processed_source.comments` |
  | `Style/DirectiveScope` | `processed_source.comments` |
  | `Style/DisableCopsWithinSourceCodeDirective` (disabled by default) | `processed_source.comments` (not tested) |

  In the prototype, these cops see the ERB comments only during their own `on_new_investigation`. Two details matter:

  - Keep the `ERBSource` object itself and change only its behavior (`comments` / `raw_source`) during the investigation. `RuboCop::Erb::Corrector` checks correction ranges only when `processed_source.is_a?(ERBSource)`. When I swapped in a `SimpleDelegator`, `-A` rewrote `<%# rubocop:pop %>` into a bare `<%`.
  - Reset `@comment_index` and `@ast_with_comments` before the investigation and restore them afterwards. rubocop-ast memoizes both from `comments`. Without this, a `comment_index` built by `Style/DirectiveScope` leaks the ERB comments to later cops, and `Lint/EmptyConditionalBody` stopped reporting an empty `if` that contained `<%# note %>`.

## Prototype results

All inputs were run one file at a time. "Works" means the disabled cop is not reported.

| Input | 0.8.2 | 1 | 2 | 3 |
|---|---|---|---|---|
| `<% if 'hello' %>world<% end %><%# rubocop:disable … %>` | no | works | works | works |
| `<%# rubocop:disable … %><% if 'hello' %>world<% end %>` | no | `if` is commented out | no (silently) | works (that line) |
| standalone `<%# rubocop:disable … %>` / `<%# rubocop:enable … %>` | no | works | works | works |
| `<% # rubocop:disable … %>` | no | works, plus `Lint/CopDirectiveSyntax` | works | works |
| `<%# rubocop:disable-next … %>` | no | works | works | works |
| `<%#`⏎`  rubocop:disable …`⏎` %>` | no | works | works | works |
| `<%#`⏎`  description`⏎`  rubocop:disable …`⏎`%>` | no | works | works | works |
| two directives in one multi-line comment | no | both work | both work | both work |
| `<%#`⏎`  rubocop:disable …`⏎`%><%= "a" %>` | no | `"a"` is commented out | no (silently) | works |
| `<%#`⏎`rubocop:disable …`⏎`%>` (column 0) | no | works, positions shift | no (silently) | works |
| `<%# rubocop:disable %>` (no cop name) | — | `Lint/CopDirectiveSyntax` | `Lint/CopDirectiveSyntax` | `Lint/CopDirectiveSyntax`* |
| `<%# rubocop:enable X %>` without a matching disable | — | `Lint/RedundantCopEnableDirective` | same | same* |
| `<%# rubocop:pop %>` without a matching push | — | `Lint/RedundantCopEnableDirective` | same | same* |
| disable/enable pair around a single statement | — | `Style/DirectiveScope` | same | same* |

\* with the cop patches described above. Without them, approach 3 reports nothing for these four inputs.

On 333 real views (rails/rails `0f591639b8` and kaigionrails/conference-app `25a02cc`, none of which contain `rubocop:` in ERB comments), approach 3 reports the same 763 offenses as 0.8.2. Approaches 1 and 2 report 766: `Layout/EmptyLineAfterMagicComment` on three files that start with `<%# encoding: utf-8 -%>`, and with approach 1, the shifted columns mentioned above. With `rubocop -A`, approach 3 changes the same code as 0.8.2, except where a directive now suppresses the offense. The cop patches do not change the `-A` results.

## Open questions

- **Dependency on RuboCop internals.** Approach 3 overrides the private `CommentConfig#each_directive`, recomputes `@no_directives`, and patches three cops. It also relies on rubocop-ast's memoization of `comment_index` / `ast_with_comments`. These are not public APIs. A long-term option would be a hook in RuboCop for adding directive comments that are not in `processed_source.comments`, which `CommentConfig` and the directive-related cops would all use. I'd be happy to hear whether you'd rather keep the patches in rubocop-erb for now, or raise this with RuboCop first.
- **Removing redundant directives.** `Lint/RedundantCopDisableDirective` and `Lint/RedundantCopEnableDirective` report redundant ERB directives, but their corrections are discarded by `RuboCop::Erb::Corrector`, because the range starts at the `#` of `<%#`. This is the same for all three approaches. Even if the correction were allowed, removing only the directive text would likely leave parts of the tag behind. A proper correction should probably remove the whole tag.
- **Lines with only HTML.** `<%# rubocop:disable … %><p>a</p>` has no Ruby tokens on its line, so RuboCop treats it as a comment-only line, and the directive applies until `rubocop:enable` or the end of the file. All three approaches behave this way. This follows the Ruby rule, but it may be surprising in a template.

## Prototype

```ruby
# ERBSource: one comment per line of each ERB comment (`<%# … %>` and single-line `<% # … %>`).
# The text is the template text; the first line starts at the `#` of `<%#`, later lines at the line start
# (with the first whitespace character replaced by `#`, or `#` prepended when there is none).
def erb_comments
  # ...
end

def comment_config
  @comment_config ||= ErbCommentConfig.new(self)
end

class ErbCommentConfig < RuboCop::CommentConfig
  def initialize(processed_source)
    super
    @no_directives = !processed_source.template_source.include?('rubocop')
  end

  private

  def each_directive(&block)
    super # without the ERB comments, even while a patched cop is running
    processed_source.erb_comments.each do |comment|
      directive = RuboCop::DirectiveComment.new(comment, registry)
      yield directive if directive.cop_names
    end
  end
end
```

I have a working prototype of approach 3, including the cop patches, and can open a PR if this direction looks acceptable.
