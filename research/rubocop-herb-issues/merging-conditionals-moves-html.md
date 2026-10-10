# `-a` merges nested conditionals and drops or moves HTML (`html_visualization: false`)

## Summary

With the default `html_visualization: false`, HTML next to a nested `<% if %>` is invisible to RuboCop. Cops that merge nested conditionals therefore see the inner `if` as the only statement of the outer branch, and their safe autocorrect changes the output of the template:

- `Style/SoleNestedConditional` merges `<% if a %>` and `<% if b %>` into `<% if a && b %>`. **The HTML before the inner `if` and the outer `<% end %>` are deleted.**
- `Style/IfInsideElse` converts `<% else %>` + `<% if b %>` into `<% elsif b %>`. The HTML in the `else` branch is moved under `elsif b`, so it is rendered only when `b` is true.

Both corrections are safe, so this happens with `-a`. With `html_visualization: true`, neither cop reports an offense, which is correct.

## Environment

- rubocop-herb `46ae1f50959736530280d75eea69deeaf739b317`
- rubocop 1.91.0
- herb 0.11.0
- ruby 4.0.5
- `html_visualization: false` (default, `config/develop/rubocop.yml`)

## Steps to reproduce

In a checkout of rubocop-herb (`--except Herb/Lint` only avoids the herb-lint setup error when `@herb-tools/linter` is not installed):

```console
$ printf '<%% if a %%>\n  <p>x</p>\n  <%% if b %%>\n    <p>y</p>\n  <%% end %%>\n<%% end %%>\n' \
    | bin/rubocop -c config/develop/rubocop.yml --except Herb/Lint -a --stdin test.html.erb
$ printf '<%% if a %%>\n  <p>x</p>\n<%% else %%>\n  <p>y</p>\n  <%% if b %%>\n    <p>z</p>\n  <%% end %%>\n<%% end %%>\n' \
    | bin/rubocop -c config/develop/rubocop.yml --except Herb/Lint -a --stdin test.html.erb
```

### Case 1: `Style/SoleNestedConditional`

Input:

```erb
<% if a %>
  <p>x</p>
  <% if b %>
    <p>y</p>
  <% end %>
<% end %>
```

Actual:

```
test.html.erb:3:6: C: [Corrected] Style/SoleNestedConditional: Consider merging nested conditions into outer if conditions.
```

```erb
<% if a && b %>
    <p>y</p>
  <% end %>
```

`<p>x</p>` is deleted.

### Case 2: `Style/IfInsideElse`

Input:

```erb
<% if a %>
  <p>x</p>
<% else %>
  <p>y</p>
  <% if b %>
    <p>z</p>
  <% end %>
<% end %>
```

Actual:

```
test.html.erb:5:6: C: [Corrected] Style/IfInsideElse: Convert if nested inside else to elsif.
```

```erb
<% if a %>
  <p>x</p>
<% elsif b %>
  <p>y</p>
    <p>z</p>
<% end %>
```

`<p>y</p>` was rendered whenever `a` is false. It is now rendered only when `b` is also true.

## Expected

No offense in either case. The inner `if` is not the only content of the outer branch, so the conditionals cannot be merged without changing the output.

## Analysis

`bin/erb2ruby --disable-html-visualization` shows the converted Ruby code of case 1:

```ruby
   if a;

     if b;

     end;
   end;
```

The HTML is replaced with whitespace, so the inner `if` looks like the sole statement of the outer `if`.

`DisabledCopsCollector` already disables cops such as `Lint/EmptyConditionalBody` and `Style/EmptyElse` at branches containing HTML. These two cops have the same cause, but they are not covered.

## Possible directions

- Disable `Style/SoleNestedConditional` and `Style/IfInsideElse` in `DisabledCopsCollector` when the outer branch contains HTML besides the inner conditional.
- Other cops that rely on "this statement is the only one in the branch" may have the same problem (for example `Style/GuardClause`; `Style/Next` is already excluded when `html_visualization` is disabled). A general check that rejects corrections whose ranges touch characters outside ERB tag contents would also stop both cases: the correction of case 1 replaces ` %>\n  <p>x</p>\n  <% if ` with ` && `, and the correction of case 2 removes the whole lines `  <% if b %>\n` and `  <% end %>\n`. Note that a check allowing removal of whole ERB tags would let case 2 through.
