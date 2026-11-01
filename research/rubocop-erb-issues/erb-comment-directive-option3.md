FWIW, here is one more approach. I looked into it before opening the issue but did not propose it because of its technical problems. It has drawbacks, but it does not need a new cop.

## Option 3: Pass directives to RuboCop without rendering them

Keep the extracted Ruby as it is, and add only the directives in ERB comments to `processed_source.comments` as comment objects.

- Pros
  - RuboCop decides which cops are disabled where by reading `processed_source.comments`, so every directive works wherever it is written, with the same rule as in Ruby. So no cop is needed.
  - The extracted Ruby is not changed, so this does not depend further on the output of `Herb.extract_ruby`.
- Cons
  - It does not work together with existing cops that look for comments in the source text instead of `processed_source.comments`, because the source text is blank where the ERB comments are.
    - `Lint/RedundantCopEnableDirective` does nothing unless `processed_source.raw_source` contains `enable`, so a redundant `<%# rubocop:enable … %>` is never reported.
    - About 20 cops decide whether a line is a comment line from the source text (`RuboCop::Cop::Util#comment_line?`), so they see a directive line as an empty line. For example, `Lint/SuppressedException` (`AllowComments`) reports a `rescue` whose body is only a directive, which it doesn't in Ruby. The directive itself cannot suppress this offense, because it applies only from the next line.
    - Patching each of these cops is not realistic.

**Example**

Template:

```erb
<% begin %>
  <%= render 'a' %>
<% rescue StandardError %>
  <%# rubocop:disable Lint/SuppressedException %>
<% end %>
<%# rubocop:enable Lint/SuppressedException %>
<%# rubocop:enable Style/StringLiterals %>
```

Compared with the same comments in a Ruby file, `Lint/SuppressedException` is reported on line 3, and `Lint/RedundantCopEnableDirective` is not reported on line 7. The two offenses on line 4 are reported in Ruby too.

```console
$ rubocop app/views/posts/show.html.erb
Inspecting 1 file
W

Offenses:

app/views/posts/show.html.erb:3:4: W: Lint/SuppressedException: Do not suppress exceptions.
<% rescue StandardError %>
   ^^^^^^^^^^^^^^^^^^^^^^^
app/views/posts/show.html.erb:4:5: W: Lint/RedundantCopDisableDirective: Unnecessary disabling of Lint/SuppressedException.
  <%# rubocop:disable Lint/SuppressedException %>
    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
app/views/posts/show.html.erb:4:5: C: Style/DirectiveScope: Use disable-next instead of a disable/enable pair around a single statement.
  <%# rubocop:disable Lint/SuppressedException %>
    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

1 file inspected, 3 offenses detected
```

I did not propose this because it does not work together with these existing cops.
