# ERB のコメント（`<%# … %>`）に書いた `rubocop:disable` をサポートしてほしい

[erb-comment-directive.md](erb-comment-directive.md)（英語で出す issue の下書き）の日本語版です。

`Herb.extract_ruby` は ERB のコメントを空白にするので、`<%# rubocop:disable Style/StringLiterals %>` は効きません。ERB のコメントに書いた無効化コメントを、rubocop-erb でサポートしてほしいと考えています。テンプレートで無効化コメントを書く場所としては ERB のコメントが自然で、herb-lint も自分の無効化コメントに同じ形（`<%# herb:disable … %>`）を使っています。

実装の方針は 2 つ考えられ、2 つ目を勧めます。

## 方針 1: ERB のコメントをすべて出力する

`Herb.extract_ruby(source, comments: true)` を使い、すべての ERB のコメントを Ruby のコメントにします。変更は 1 行で済みますが、本来 ERB では処理されないコメントが Ruby のコードになるので、RuboCop が意図しない解釈をします。

- **後ろのコードがコメントに入る**: ERB のコメントは `%>` で終わりますが、Ruby のコメントは行末まで続きます。`<%# note %><% if x %>` … `<% end %>` のような正しいテンプレートに `Lint/Syntax` が出て、逆に同じ行でコメントの後ろにある本当の構文エラーは報告されなくなります
- **複数行のコメントでも壊れる**: 次のような正しいテンプレートでも、`%>` の後ろの `if` がコメントに入り、`Lint/Syntax: unexpected token end` が出ます

  ```erb
  <%#
    Show the menu only to signed-in users.
  %><% if signed_in? %>
    <p>menu</p>
  <% end %>
  ```

## 方針 2: 安全なときだけ無効化コメントを出力する（推奨）

`rubocop:` の無効化コメントだけを、取り出した Ruby にその場で書き戻します。

- `<%# rubocop:disable … %>` は `  # rubocop:disable …` になります。`<%#` の `#` が Ruby のコメントの始まりの位置にそのまま来るので、位置は変わりません
- 同じ行の後ろに Ruby のコードが続くときは書き戻しません。書き戻せない無効化コメントは、cop などでユーザーに知らせる必要があります
- ほかの ERB のコメントは今までどおり空白のままなので、既存の結果は変わりません。試作では、rails/rails と kaigionrails/conference-app の実際のビュー 333 ファイルで、0.8.2 と同じ 763 件でした

方針 2 の試作があるので、この方向でよければ PR を出せます。
