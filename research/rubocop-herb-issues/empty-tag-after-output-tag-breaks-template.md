# `-a` removes the `%>` of an output tag followed by an empty ERB tag

## Summary

When an output tag is followed by an empty ERB tag on the same line, and the template has another empty ERB tag before them, `rubocop -a` removes the closing `%>` of the output tag. The result is an unclosed ERB tag, which Herb reports as a parse error.

The corrections come from two cops, both enabled by default: `Layout/SpaceBeforeSemicolon` and `Herb/EmptyErbTag`. Each of them alone keeps the template valid.

## Environment

- rubocop-herb `96d31cf8dff39109dbe4506b808e19693a92b2e2`
- rubocop 1.92.0
- herb 0.11.0
- ruby 4.0.5

## Steps to reproduce

In a checkout of rubocop-herb (`--except Herb/Linting` only avoids the herb-lint setup error when `@herb-tools/linter` is not installed):

```console
$ printf '<%% %%>\n<%%= b %%><%% %%>\n' > test.html.erb
$ bin/rubocop -c config/develop/rubocop.yml --except Herb/Linting -a test.html.erb
$ cat test.html.erb
```

Input:

```erb
<% %>
<%= b %><% %>
```

## Expected

Both empty tags are removed, and the output tag is kept:

```erb
<%= b %>
```

## Actual

```
test.html.erb:1:1: C: [Corrected] Herb/EmptyErbTag: Remove the empty ERB tag.
test.html.erb:1:6: C: [Corrected] Layout/TrailingWhitespace: Trailing whitespace detected.
test.html.erb:2:7: C: [Corrected] Layout/SpaceBeforeSemicolon: Space found before semicolon.
test.html.erb:2:9: C: [Corrected] Herb/EmptyErbTag: Remove the empty ERB tag.
```

Corrected output (with a trailing space after `b`):

```erb
<%= b 
```

With each cop alone (`--only`), the result is valid:

| Cops | Result |
|---|---|
| `Herb/EmptyErbTag` | `<%= b %>` |
| `Layout/SpaceBeforeSemicolon` | `<% %>`⏎`<%= b  %>` (the two tags on line 2 are joined) |
| `Herb/EmptyErbTag,Layout/SpaceBeforeSemicolon` | `<%= b ` |

Without the first line (`<%= b %><% %>` only), the result is `<%= b %>`.

## Analysis

The converted Ruby code of line 2 is `_ = b;    ;`. The four spaces before the second `;` are the `%><%` between the two tags.

Logging the correctors of each cop and the collated corrector in `RuboCop::Cop::Team#collate_corrections` (positions in characters of the whole source) shows:

- `Layout/SpaceBeforeSemicolon` removes 12...16 (`%><%`). `CopCorrectionGuard` accepts it: the HTML, the number of output tags and the parse errors do not change, though the two tags are joined into one
- `Herb/EmptyErbTag` removes 0...6 (`<% %>` and its newline) and 14...19 (`<% %>` on line 2). The cops of rubocop-herb skip `CopCorrectionGuard` (`return super if cop_name.start_with?("Herb/")`)
- The collated corrector removes 0...6 and 12...19 (`%><% %>`). The two deletions on line 2 cross each other, and `RuboCop::Cop::Corrector` is created with `crossing_deletions: :accept`, so they are merged into one deletion, which also removes the `%>` of the output tag

`CopCorrectionGuard` validates the correction of each cop separately, so it never sees the collated result.

Without the first line, `Layout/SpaceBeforeSemicolon` removes 6...10 and `Herb/EmptyErbTag` removes 8...13, but the collated corrector removes only 8...13, and the result is valid. Why the two cases are collated differently was not investigated.

## Possible directions

- Do not let `Layout/SpaceBeforeSemicolon` (and other corrections removing the whitespace between two ERB tags) join two tags: trim or reject a removal that covers the `%>` of one tag and the `<%` of the next one. `CorrectionAdjuster` cannot trim it now, because the removal neither starts nor ends inside the content of a tag
- Validate the merged corrections of all cops once more before they are applied (e.g. in `Team#collate_corrections` for ERB sources), and drop the corrections of the cops that break the template
