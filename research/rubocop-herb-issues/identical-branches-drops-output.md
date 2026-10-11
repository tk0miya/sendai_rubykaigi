# `-A` moves `<%= foo %>` out of a conditional as `_ = foo` and the template stops rendering it

## Summary

When both branches of a conditional end with the same output tag, `Style/IdenticalConditionalBranches` moves it after the conditional. Its correction copies the converted Ruby code (`_ = foo`) into the source and puts it into the `<% end %>` tag. The output tag `<%= foo %>` becomes a plain `_ = foo` statement in a `<% %>` tag, so `foo` is no longer rendered.

`CorrectionGuard` accepts this correction because the HTML between ERB tags is unchanged and no Herb parse error is added.

The cop's autocorrect is unsafe, so this happens with `-A`, not with `-a`.

## Environment

- rubocop-herb `6601d3efd1dd1310f5d896a9e0e643061af835ff`
- rubocop 1.91.0
- herb 0.11.0
- ruby 4.0.5

## Steps to reproduce

In a checkout of rubocop-herb (`--except Herb/Linting` only avoids the herb-lint setup error when `@herb-tools/linter` is not installed):

```console
$ printf '<%% if a %%>\n  <%%= foo %%>\n<%% else %%>\n  <%%= foo %%>\n<%% end %%>\n' \
    | bin/rubocop -c config/develop/rubocop.yml --except Herb/Linting -A --only Style/IdenticalConditionalBranches --stdin test.html.erb
```

Input:

```erb
<% if a %>
  <%= foo %>
<% else %>
  <%= foo %>
<% end %>
```

## Expected

Either the output tag is moved as an output tag:

```erb
<% if a %>
<% else %>
<% end %>
<%= foo %>
```

or the offense is reported without autocorrect.

## Actual

```
test.html.erb:2:3: C: [Corrected] Style/IdenticalConditionalBranches: Move _ = foo out of the conditional.
test.html.erb:4:3: C: [Corrected] Style/IdenticalConditionalBranches: Move _ = foo out of the conditional.
```

Corrected output:

```erb
<% if a %>
<% else %>
<% end
   _ = foo %>
```

`foo` was rendered in both branches. It is not rendered at all now.

The same happens when the branches have other statements before the identical tail (`<%= bar %>` + `<%= foo %>`), and when the conditional is inside an HTML element (`<div>…</div>`).

Moving an identical head that is not an output tag (`<% x = 1 %>`) produces `<% x = 1\n   if a %>`, which renders the same.

## Analysis

`bin/erb2ruby` shows the converted Ruby code:

```ruby
   if a;
  _ = foo;
   else;
  _ = foo;
   end;
```

`Style/IdenticalConditionalBranches` removes the tail statements and inserts `_ = foo` (the source of the statement in the converted code) after `end`. In the ERB source, `_ =` stands at the position of `<%=`, so the inserted text is not the original tag.

`CorrectionValidator#valid?` compares only:

- the HTML parts between ERB tags (`html_segments_of`), and
- the number of Herb parse errors.

ERB tokens (`TOKEN_ERB_START`, `TOKEN_ERB_CONTENT`, `TOKEN_ERB_END`) are dropped as separators, so a correction that changes the kind of an ERB tag (`<%=` to `<%`) or moves Ruby code between tags is accepted as long as the HTML is kept.

## Possible directions

- Reject a correction if the corrected source contains the output marker `_ =` at a position that is not the start of an output tag, or more generally, if the sequence of ERB tag openings (`<%`, `<%=`, `<%==`, `<%-`) changes in a way other than removing whole tags.
- Or disable `Style/IdenticalConditionalBranches` when the identical statements are output tags. `ImmovableExpressionCollector` already disables the cop for expressions adjacent to HTML.
