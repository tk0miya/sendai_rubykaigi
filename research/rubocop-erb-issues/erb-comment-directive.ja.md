# ERB のコメント（`<%# … %>`）に書いた `rubocop:disable` をサポートしませんか

[erb-comment-directive.md](erb-comment-directive.md)（英語で出す issue の下書き）の日本語版です。

`Herb.extract_ruby` は ERB のコメントを空白にするので、`<%# rubocop:disable Style/StringLiterals %>` は効きません。テンプレートで無効化コメントを書く場所としては ERB のコメントが自然です（herb-lint も `<%# herb:disable … %>` を使います）。今の回避策は複数行のタグの中に Ruby のコメントを書く形（`<%`⏎`  # rubocop:disable …`⏎`%>`）ですが、herb-format がこのタグを `<% # … %>` にまとめると効かなくなります。

このサポートを受け入れてもらえますか。受け入れてもらえる場合、考えている方針は次のとおりです。

## 提案

安全なときだけ、無効化コメントを取り出した Ruby にその場で書き戻します。

- `<%# rubocop:disable … %>` は `  # rubocop:disable …` になります。`<%#` の `#` が Ruby のコメントの始まりの位置にそのまま来るので、位置は変わりません
- 同じ行の後ろに Ruby のコードが続くときは書き戻しません。書き戻すと、そのコードもコメントに入るためです
- ほかの ERB のコメントは今までどおり空白のままなので、既存の結果は変わりません。試作では、rails/rails と kaigionrails/conference-app の実際のビュー 333 ファイルで、0.8.2 と同じ 763 件でした

## `Herb.extract_ruby(source, comments: true)` を使わない理由

- 同じ行でコメントの後ろにあるコードがコメントに入ります。`<%# note %><% if x %>` … `<% end %>` に `Lint/Syntax` が出ます
- 一部の複数行のコメントの後ろで位置がずれ、autocorrect がテンプレートを壊します
- 普通のコメントに新しい offense（`Style/CommentAnnotation`、`Layout/EmptyComment` など）が出て、今通っている CI が通らなくなります

## 相談したい点

- **複数行のコメント**: 1 行の `<%# rubocop:… %>` だけを対象にするか、複数行のコメントの中の無効化コメントの行も対象にするか。後者には、字下げなどの条件が加わります
- **適用できない無効化コメント**（同じ行の後ろに Ruby のコードが続くもの）: 新しい cop で報告するか、警告を出すか、ドキュメントに書くだけにするか

試作があるので、方針が決まれば PR を出せます。
