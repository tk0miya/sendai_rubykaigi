# `Lint/UnusedBlockArgument` is not reported when the block body is only HTML (`html_visualization: false`)

## Summary

With the default `html_visualization: false`, a block whose body contains only HTML becomes an empty block in the converted Ruby code. `Lint/UnusedBlockArgument` ignores empty blocks by default (`IgnoreEmptyBlocks: true`), so an unused block argument is not reported.

With `html_visualization: true`, it is reported as expected.

## Environment

- rubocop-herb `46ae1f50959736530280d75eea69deeaf739b317`
- rubocop 1.91.0
- herb 0.11.0
- ruby 4.0.5
- `html_visualization: false` (default, `config/develop/rubocop.yml`)

## Steps to reproduce

In a checkout of rubocop-herb (`--except Herb/Lint` only avoids the herb-lint setup error when `@herb-tools/linter` is not installed):

```console
$ printf '<%% items.each do |item| %%>\n  <li>item</li>\n<%% end %%>\n' \
    | bin/rubocop -c config/develop/rubocop.yml --except Herb/Lint --stdin test.html.erb
$ printf '<%% items.each do |item| %%>\n  <li>item</li>\n<%% end %%>\n' \
    | bin/rubocop -c config/develop/rubocop-html-visualization.yml --except Herb/Lint --stdin test.html.erb
```

Input:

```erb
<% items.each do |item| %>
  <li>item</li>
<% end %>
```

## Expected

`Lint/UnusedBlockArgument` is reported for `item` in both configurations. The block is not empty in the template, and `item` is not used.

## Actual

- `html_visualization: false`: `no offenses detected`
- `html_visualization: true`:

  ```
  test.html.erb:1:19: W: [Correctable] Lint/UnusedBlockArgument: Unused block argument - item. You can omit the argument if you don't care about it.
  ```

Setting `Lint/UnusedBlockArgument: IgnoreEmptyBlocks: false` makes the first configuration report the offense too.

## Analysis

`bin/erb2ruby --disable-html-visualization` shows the converted Ruby code:

```ruby
   items.each do |item|;

   end;
```

The HTML body is replaced with whitespace, so the block is empty, and `Lint/UnusedBlockArgument` skips it (`IgnoreEmptyBlocks: true` by default).

This is the false-negative side of the problem that `DisabledCopsCollector` handles for false positives (`Lint/EmptyBlock`, `Lint/EmptyConditionalBody`, and so on): without `html_visualization`, RuboCop cannot tell an HTML-only body from an empty body.

## Possible directions

- Set `Lint/UnusedBlockArgument: IgnoreEmptyBlocks: false` for ERB files when `html_visualization` is disabled. A block that is empty in the template itself is probably rare, so this is unlikely to cause many false positives.
- Or document that some offenses are only detected with `html_visualization: true`, and consider making it the default.
