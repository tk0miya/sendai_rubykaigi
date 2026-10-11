# `-a` turns `<% unused = 1 %>` into `<% 1 %>` and leaves a `Lint/Void` offense that cannot be autocorrected

## Summary

In a Ruby file, `rubocop -a` removes an unused assignment completely: `Lint/UselessAssignment` turns `unused = 1` into `1`, and `Lint/Void` then removes `1`.

In an ERB file, `Lint/UselessAssignment` turns `<% unused = 1 %>` into `<% 1 %>`, but `CopCorrectionGuard` discards the `Lint/Void` correction because it would also remove `<% ` (the whitespace on the left in the converted Ruby code). The template is left with `<% 1 %>` and a `Lint/Void` offense that is not autocorrectable, so `rubocop -a` still fails.

The rendered output does not change. The problem is that the autocorrect stops halfway and leaves code that the user has to remove by hand.

## Environment

- rubocop-herb `6601d3efd1dd1310f5d896a9e0e643061af835ff`
- rubocop 1.91.0
- herb 0.11.0
- ruby 4.0.5

## Steps to reproduce

In a checkout of rubocop-herb (`--except Herb/Linting` only avoids the herb-lint setup error when `@herb-tools/linter` is not installed):

```console
$ printf '<p>a</p>\n<%% unused = 1 %%>\n<%%= b %%>\n' \
    | bin/rubocop -c config/develop/rubocop.yml --except Herb/Linting -a --stdin test.html.erb
```

Input:

```erb
<p>a</p>
<% unused = 1 %>
<%= b %>
```

## Expected

The same result as in a Ruby file: the whole statement is removed. Since the statement is the whole content of the tag, the tag can be removed with it:

```erb
<p>a</p>
<%= b %>
```

## Actual

```
test.html.erb:2:4: W: [Corrected] Lint/UselessAssignment: Useless assignment to variable - unused.
test.html.erb:2:4: W: Lint/Void: Literal 1 used in void context.
```

Corrected output:

```erb
<p>a</p>
<% 1 %>
<%= b %>
```

The same Ruby code in a method body (`puts 0` / `unused = 1` / `b`) is corrected by both cops and `unused = 1` disappears.

A tag that has `<% 1 %>` from the beginning has the same problem: `Lint/Void` is reported but not autocorrected.

## Analysis

`Lint/Void#autocorrect_void_expression` in rubocop 1.91.0 (`lib/rubocop/cop/lint/void.rb`) removes the node with this range:

```ruby
corrector.remove(range_with_surrounding_space(range: node.source_range, side: :left))
```

In the converted Ruby code, the whitespace to the left of `1` is the newline after `<p>a</p>` and 3 spaces. In the ERB source, they are the newline and `<% `. Applied as is, the correction leaves ` %>` at the end of the previous line. `CorrectionValidator` sees that the HTML changes and discards the correction, which is the right call for this range, but nothing removes the statement instead.

## Possible directions

- When a correction removes the whole Ruby code of a `<% %>` tag (possibly with whitespace or delimiters around it), expand it to remove the whole tag, including its line if the tag is the only thing on the line. Then validate the expanded correction as usual.
- Only for `<% %>` tags. Removing the code of a `<%= %>` tag changes the output, though `Lint/Void` does not report output tags because they are converted to `_ = …`.
