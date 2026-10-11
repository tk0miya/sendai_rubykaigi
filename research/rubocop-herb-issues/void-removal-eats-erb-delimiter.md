# Removing a statement with `-a` also removes `<%` and the preceding newline

## Summary

When `Lint/Void` removes a statement, it also removes the whitespace on its left. In ERB, that "whitespace" is the preceding newline and the opening `<% ` of the tag. With `rubocop -a`, the tag loses its opening delimiter and ` %>` is joined to the end of the previous line.

`Lint/UselessAssignment` leads to the same result: it first turns `<% x = 1 %>` into `<% 1 %>`, and `Lint/Void` then removes `1`. Both corrections are safe, so this happens with `-a`, not only with `-A`.

## Environment

- rubocop-herb `14830806e5deb61e27744e9fed09c5380ccbeee7`
- rubocop 1.91.0
- herb 0.11.0
- ruby 4.0.5

## Steps to reproduce

In a checkout of rubocop-herb (`--except Herb/Linting` only avoids the herb-lint setup error when `@herb-tools/linter` is not installed):

```console
$ printf '<p>a</p>\n<%% 1 %%>\n<%%= b %%>\n' \
    | bin/rubocop -c config/develop/rubocop.yml --except Herb/Linting -a --stdin test.html.erb
$ printf '<p>a</p>\n<%% x = 1 %%>\n<%%= b %%>\n' \
    | bin/rubocop -c config/develop/rubocop.yml --except Herb/Linting -a --stdin test.html.erb
```

Input (the first case):

```erb
<p>a</p>
<% 1 %>
<%= b %>
```

## Expected

Either the whole tag (`<% 1 %>`) is removed, or the offense is reported without autocorrect. In any case, the output should be a valid template.

## Actual

```
test.html.erb:2:4: W: [Corrected] Lint/Void: Literal 1 used in void context.
```

Corrected output:

```erb
<p>a</p> %>
<%= b %>
```

The second case (`<% x = 1 %>`) reports `Lint/UselessAssignment` and then `Lint/Void`, and produces the same output.

If the tag is on the first line, only ` %>` is left on that line.

## Analysis

`bin/erb2ruby` shows the converted Ruby code (trailing whitespace omitted):

```ruby
p;
   1;
_ = b;
```

`Lint/Void#autocorrect_void_expression` in rubocop 1.91.0 (`lib/rubocop/cop/lint/void.rb:274`) removes the node with this range:

```ruby
corrector.remove(range_with_surrounding_space(range: node.source_range, side: :left))
```

In the Ruby code, the whitespace to the left of `1` is the newline at the end of the first line and 3 spaces. In the ERB source, they are the newline and `<% `. So the correction removes `\n<% 1` and leaves ` %>`.

## Possible directions

Characters that are whitespace in the converted Ruby code may be ERB delimiters or HTML in the source, and RuboCop's correctors freely remove or rewrite surrounding whitespace (`range_with_surrounding_space`, `range_by_whole_lines`, and so on).

Excluding individual cops would not cover all of them. Some ideas:

- Before applying a correction, reject it (or skip the offense's autocorrect) if its range touches characters outside ERB tag contents. `RuboCop::Cop::Team#collate_corrections` (rubocop 1.91.0, `lib/rubocop/cop/team.rb:324`) merges the corrector of each cop one by one, so the check could be done per cop there.
- Or expand a removal that covers the whole content of a `<% %>` tag to remove the whole tag.
