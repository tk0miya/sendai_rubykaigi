# ERB のコメント（`<%# … %>`）に書いた `rubocop:disable` をサポートしてほしい

[erb-comment-directive.md](erb-comment-directive.md)（英語で出す issue の下書き）の日本語版です。

`Herb.extract_ruby` は ERB のコメントを空白にするので、`<%# rubocop:disable Style/StringLiterals %>` は効きません。ERB のコメントに書いた無効化コメントを、rubocop-erb でサポートしてほしいと考えています。テンプレートで無効化コメントを書く場所としては ERB のコメントが自然で、herb-lint も自分の無効化コメントに同じ形（`<%# herb:disable … %>`）を使っています。

実装の方針は 2 つ考えられ、2 つ目を勧めます。

## 方針 1: ERB のコメントをすべて出力する

`Herb.extract_ruby(source, comments: true)` を使い、すべての ERB のコメントを Ruby のコメントにします。

- Pros
  - 変更は 1 行で済む
- Cons
  - 本来 ERB ではレンダリングされないコメントノードがレンダリングされるため、意図せぬ挙動を引き起こす。具体的には、コメントの後ろにあるコードがコメント扱いされる
    - たとえば `<%# note %><% if x %>` … `<% end %>` のような正しいテンプレートに `Lint/Syntax` が出て、逆にコメントの後ろにある本当の構文エラーは報告されなくなる

## 方針 2: 安全なときだけ無効化コメントを出力する（推奨）

`rubocop:` の無効化コメントだけを、取り出した Ruby にその場で書き戻します。たとえば `<%# rubocop:disable … %>` は `  # rubocop:disable …` になります。同じ行の後ろに Ruby のコードが続くときは書き戻しません。

- Pros
  - コードがコメントに入ることはない
  - ほかの ERB のコメントは今までどおり空白のままなので、既存の結果は変わらない。試作では、rails/rails と kaigionrails/conference-app の実際のビュー 333 ファイルで、0.8.2 と同じ 763 件だった
- Cons
  - 同じ行の後ろに Ruby のコードが続く無効化コメント（`<%# rubocop:disable … %><% if x %>`）はサポートできない。cop などでユーザーに知らせる必要がある
  - 方針 1 より実装が大きい

方針 2 の試作があるので、この方向でよければ PR を出せます。
