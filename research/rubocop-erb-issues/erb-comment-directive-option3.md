FWIW, here is one more approach. I looked into it before opening the issue but did not propose it because of its technical problems. It has drawbacks, but it does not need a new cop.

## Option 3: Pass directives to RuboCop without rendering them

Keep the extracted Ruby as it is, and add only the directives in ERB comments to `processed_source.comments` as comment objects.

- Pros
  - RuboCop decides which cops are disabled where by reading `processed_source.comments`, so every directive works wherever it is written, with the same rule as in Ruby. So no cop is needed.
  - The extracted Ruby is not changed, so this does not depend further on the output of `Herb.extract_ruby`.
- Cons
  - It relies on RuboCop internals. `processed_source.comments` is built by RuboCop from the parser result, and RuboCop provides no way for plugins to add comments to it.
  - It does not work together with existing cops that look for comments in the source text instead of `processed_source.comments`, because the source text is blank where the ERB comments are.
    - `Lint/RedundantCopEnableDirective` does nothing unless `processed_source.raw_source` contains `enable`, so a redundant `<%# rubocop:enable … %>` is never reported.
    - About 20 cops decide whether a line is a comment line from the source text (`RuboCop::Cop::Util#comment_line?`), so they see a directive line as an empty line. For example, `Lint/SuppressedException` (`AllowComments`) reports a `rescue` whose body is only a directive, which it doesn't in Ruby. The directive itself cannot suppress this offense, because it applies only from the next line.
    - Patching each of these cops is not realistic.

**Example**

Template:

```erb
<%# TODO fix this %>
<%# rubocop:disable Style/StringLiterals %>
<p><%= "a" %></p>
<%# rubocop:disable Lint/LiteralAsCondition %><% if x %>
  <p>b</p>
<% end %>
```

Extracted Ruby (unchanged from 0.8.2):

```
1:
2:
3:        "a"  ;
4:                                                  if x  ;
5:
6:    end  ;
```

`processed_source.comments`:

```
line 2: "# rubocop:disable Style/StringLiterals"
line 4: "# rubocop:disable Lint/LiteralAsCondition"
```

Both directives take effect, including the one on line 4 that is followed by code. In the extracted Ruby, however, lines 2 and 4 have no comment, so cops that look for comments in the source text don't see these directives.

I did not propose this because it does not work together with these existing cops.
