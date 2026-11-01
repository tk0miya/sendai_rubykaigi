While you consider this, let me share one more approach. I looked into it before opening the issue but did not propose it because of its technical problems. It has drawbacks, but it does not need a new cop.

## Option 3: Pass directives to RuboCop without rendering them

Keep the extracted Ruby as it is. Build comment objects from the ERB comments, and pass them only to RuboCop's `CommentConfig`, which decides which cops are disabled on which lines.

- Pros
  - Every directive works wherever it is written, with the same rule as in Ruby. On a line with code, it applies to that line. On its own line, it applies until `rubocop:enable`. So no cop is needed.
  - The extracted Ruby is not changed, so this does not depend further on the output of `Herb.extract_ruby`.
- Cons
  - It relies on RuboCop internals: it overrides the private `CommentConfig#each_directive` and recomputes `CommentConfig`'s internal `@no_directives`.
  - Some cops find directives without going through `CommentConfig`, so they don't see these: `Lint/RedundantCopEnableDirective` (it checks `processed_source.raw_source`), `Lint/CopDirectiveSyntax` and `Style/DirectiveScope` (they read `processed_source.comments`). Each needs a patch. Adding the ERB comments to `processed_source.comments` instead doesn't work either: about 20 cops tell comment lines apart by the source text, which is blank there, so they disagree with `processed_source.comments`. For example, `Style/InlineComment` then reports a standalone `<%# heading %>` as a trailing comment.

**Example**

Template:

```erb
<%# rubocop:disable Lint/LiteralAsCondition %><% if 'b' %>
  <p>b</p>
<% end %>
```

`rubocop` reports no offenses. With 0.8.2, `Lint/LiteralAsCondition` is reported on line 1.

```console
$ rubocop app/views/posts/show.html.erb
Inspecting 1 file
.

1 file inspected, no offenses detected
```

I did not propose this because of the dependency on RuboCop internals and the patches for each cop. To avoid them, RuboCop itself would need a way to add directive comments that are not in `processed_source.comments`.
