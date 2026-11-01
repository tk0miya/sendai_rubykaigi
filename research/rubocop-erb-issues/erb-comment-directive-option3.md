While you consider this, let me share one more approach. I looked into it before opening the issue but did not propose it because of its technical problems. It has drawbacks, but it does not need a new cop.

## Option 3: Pass ERB comments to RuboCop without rendering them

Keep the extracted Ruby as it is, and add the ERB comments to `processed_source.comments` as comment objects.

- Pros
  - RuboCop decides which cops are disabled where by reading `processed_source.comments`, so every directive works wherever it is written, with the same rule as in Ruby. So no cop is needed.
  - The extracted Ruby is not changed, so this does not depend further on the output of `Herb.extract_ruby`.
- Cons
  - Cops that check comments themselves don't work correctly, because they read the source text instead of `processed_source.comments`, and the source text is blank where the ERB comments are.
    - `Lint/RedundantCopEnableDirective` does nothing unless `processed_source.raw_source` contains `enable`, so a redundant `<%# rubocop:enable … %>` is never reported.
    - About 20 cops (those using `RuboCop::Cop::Util#comment_line?`) decide whether a line is a comment line from the source text, so they disagree with `processed_source.comments`. For example, `Style/CommentAnnotation` treats each ERB comment as a trailing comment and checks every line of consecutive comments, while in Ruby only the first line of a comment block is checked.
    - Fixing this would need a patch for each of these cops.

**Example**

Template:

```erb
<%# rubocop:disable Lint/LiteralAsCondition %><% if 'b' %>
  <p>b</p>
<% end %>
<%# rubocop:enable Style/StringLiterals %>
<div>
  <%# TODO fix this %>
  <%# TODO fix that %>
</div>
```

The directive on line 1 works, so `Lint/LiteralAsCondition` is not reported. However, the redundant `rubocop:enable` on line 4 is not reported, and `Style/CommentAnnotation` is reported on both lines 6 and 7. The same comments in a Ruby file get `Lint/RedundantCopEnableDirective`, and `Style/CommentAnnotation` only on the first `TODO` line.

```console
$ rubocop app/views/posts/show.html.erb
Inspecting 1 file
C

Offenses:

app/views/posts/show.html.erb:6:7: C: [Correctable] Style/CommentAnnotation: Annotation keywords like TODO should be all upper case, followed by a colon, and a space, then a note describing the problem.
  <%# TODO fix this %>
      ^^^^^
app/views/posts/show.html.erb:7:7: C: [Correctable] Style/CommentAnnotation: Annotation keywords like TODO should be all upper case, followed by a colon, and a space, then a note describing the problem.
  <%# TODO fix that %>
      ^^^^^

1 file inspected, 2 offenses detected, 2 offenses autocorrectable
```

I did not propose this because the cops that check comments would need patches one by one. To avoid this, RuboCop itself would need a way to tell these cops about comments that are not in the source text.
