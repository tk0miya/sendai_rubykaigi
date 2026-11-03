# Cops that verify corrections by reparsing drop offenses and corrections in templates with HTML

## Summary

Since rubocop 1.92.0, `Style/MethodCallWithoutArgsParentheses`, `Style/RedundantParentheses` and `Style/TernaryParentheses` use `RuboCop::Cop::ReparsedEquivalence`: they apply the correction to the source, parse the result again, and only report the offense (or apply the correction) when the new AST is equal to the original one.

In a template that contains any HTML, this check always fails in rubocop-herb:

- `Style/MethodCallWithoutArgsParentheses` and `Style/RedundantParentheses` report nothing
- `Style/TernaryParentheses` reports the offense but does not autocorrect it

Templates without HTML are not affected. rubocop-erb 0.8.2, which passes the output of `Herb.extract_ruby` to RuboCop as is, reports and corrects all three in the same templates.

## Environment

- rubocop-herb `4d915335e559aa93b7e3ec82adbbe203054e631e`
- rubocop 1.92.1
- herb 0.11.1
- ruby 4.0.5

## Steps to reproduce

In a checkout of rubocop-herb (`--except Herb/Linting` only avoids the herb-lint setup error when `@herb-tools/linter` is not installed):

```console
$ printf '<div>\n  <%%= link_to root_path() %%>\n  <%%= (a == b) ? 1 : 2 %%>\n  <%%= (foo) %%>\n</div>\n' \
    | bin/rubocop -c config/develop/rubocop.yml --except Herb/Linting --stdin test.html.erb
```

Input:

```erb
<div>
  <%= link_to root_path() %>
  <%= (a == b) ? 1 : 2 %>
  <%= (foo) %>
</div>
```

## Expected

The same offenses as without the `<div>`, all autocorrectable:

```
test.html.erb:2:24: C: [Correctable] Style/MethodCallWithoutArgsParentheses: Do not use parentheses for method calls with no arguments.
test.html.erb:3:7: C: [Correctable] Style/TernaryParentheses: Omit parentheses for ternary conditions.
test.html.erb:4:7: C: [Correctable] Style/RedundantParentheses: Don't use parentheses around a method call.
```

## Actual

```
test.html.erb:3:7: C: Style/TernaryParentheses: Omit parentheses for ternary conditions.
```

Without the `<div>` and `</div>` lines, the expected three offenses are reported and corrected by `-a`.

In real views, `<%= link_to "All events talks", admin_talks_path(), class: "…" %>` in kaigionrails/conference-app (`app/views/admin/talks/index.html.erb`) has no `Style/MethodCallWithoutArgsParentheses` offense, and `<%= (name == trace_to_show) ? 'block' : 'none' %>` in rails/rails (`actionpack/lib/action_dispatch/middleware/templates/rescues/_trace.html.erb`) is reported but not corrected.

## Analysis

`ReparsedEquivalence#corrections_verify?` (rubocop 1.92.1, `lib/rubocop/cop/mixin/reparsed_equivalence.rb`) applies the corrections with `Corrector.new(processed_source)`, parses `corrector.process`, and compares the result with `processed_source.ast` (`parses_equivalently?`).

`RuboCop::Herb::ProcessedSource#parse` transforms the AST with `RuboCopASTTransformer`, which renames the method of each node rendered from HTML (`div` → `div__html0`), so that the HTML at different positions never compares equal (e.g. in `Lint/DuplicateBranch` and `Style/IdenticalConditionalBranches`). The reparsed AST is not transformed, so it has `(send nil :div)` where `processed_source.ast` has `(send nil :div__html0)`, and the comparison always fails.

With `uniquify_html_method_name` turned into a no-op (diagnostic only; this breaks the cops above), the three offenses are reported and marked as correctable.

The other cops that use `ReparsedEquivalence` in rubocop 1.92.1 are `Layout/RedundantLineBreak`, `Style/RedundantLineContinuation`, `Style/SoleNestedConditional`, `Style/ConditionalAssignment` and `Style/MethodCallWithArgsParentheses` (`omit_parentheses` style). They are likely affected in the same way.

## Possible directions

- Apply the same transformation to the reparsed AST. `ReparsedEquivalence` has a hook for it, `normalize_reparsed_ast(node)`, but it is called on both sides, and the original side is already transformed. Prepending a module that transforms the reparsed AST for `RuboCop::Herb::ProcessedSource` would make both sides equal.
- Keep the untransformed AST and compare the reparsed AST with it.
- Add a spec with HTML around the ERB tags for each of the cops above, so that a future RuboCop release that moves another cop to `ReparsedEquivalence` is caught.
