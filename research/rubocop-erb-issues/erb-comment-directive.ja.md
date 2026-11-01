# ERB のコメント（`<%# … %>`）に書いた `rubocop:disable` をサポートしてほしい

[erb-comment-directive.md](erb-comment-directive.md)（英語で出す issue の下書き）の日本語版です。

素晴らしい gem をありがとうございます。0.8 で `Herb.extract_ruby` を使うようになったことによる改善をうれしく思っています。

今回は、ERB のコメント（`<%# … %>`）に書いた `rubocop:disable` のサポートを提案したいと考えています。今は `Herb.extract_ruby` が ERB のコメントを空白にするので、`<%# rubocop:disable Style/StringLiterals %>` は効きません。テンプレートで無効化コメントを書く場所としては ERB のコメントが自然で、herb-lint も自分の無効化コメントに同じ形（`<%# herb:disable … %>`）を使っています。

実装の方針は 2 つ考えられ、2 つ目を勧めます。

## 方針 1: ERB のコメントをすべて出力する

`Herb.extract_ruby(source, comments: true)` を使い、すべての ERB のコメントを Ruby のコメントにします。

- Pros
  - 変更は 1 行で済む
- Cons
  - 本来 ERB ではレンダリングされないコメントノードがレンダリングされるため、意図せぬ挙動を引き起こす。具体的には、コメントの後ろにあるコードがコメント扱いされる

**例**

テンプレート：

```erb
<%# TODO fix this %>
<%# rubocop:disable Style/StringLiterals %>
<p><%= "a" %></p>
<%# rubocop:disable Lint/LiteralAsCondition %><% if x %>
  <p>b</p>
<% end %>
```

取り出した Ruby（4 行目の `if` がコメントに入るので、6 行目に `Lint/Syntax` が出る）：

```
1:   # TODO fix this
2:   # rubocop:disable Style/StringLiterals
3:        "a"  ;
4:   # rubocop:disable Lint/LiteralAsCondition      if x  ;
5:
6:    end  ;
```

## 方針 2: 安全なときだけ無効化コメントを出力する（推奨）

`rubocop:` の無効化コメントだけを、取り出した Ruby にその場で書き戻します。同じ行の後ろに Ruby のコードが続くときは書き戻しません。

- Pros
  - コードを破損するコメントは書き戻さないので、コードがコメント扱いされることはない
  - ほかの ERB のコメントは今までどおり空白のままなので、既存の結果は変わらない。試作では、rails/rails と kaigionrails/conference-app の実際のビュー 333 ファイルで、0.8.2 と同じ 763 件だった
- Cons
  - 一部の directive（同じ行の後ろに Ruby のコードが続くもの。例: `<%# rubocop:disable … %><% if x %>`）は書き戻されないため効果を発揮しない。暗黙的な動作であり、ユーザーを混乱させる可能性がある
    - これは無効なコメントを検知する cop などで回避できる
  - 通常のコメントは書き戻されないので、lint の対象にならない（0.8.2 と同じ）。たとえば `<%# TODO fix this %>` に `Style/CommentAnnotation` が出ない
  - 方針 1 より実装が大きい

**例**

テンプレート：

```erb
<%# TODO fix this %>
<%# rubocop:disable Style/StringLiterals %>
<p><%= "a" %></p>
<%# rubocop:disable Lint/LiteralAsCondition %><% if x %>
  <p>b</p>
<% end %>
```

取り出した Ruby（1 行目の通常のコメントと、後ろにコードが続く 4 行目の無効化コメントは空白のまま）：

```
1:
2:   # rubocop:disable Style/StringLiterals
3:        "a"  ;
4:                                                  if x  ;
5:
6:    end  ;
```

方針 2 の試作があるので、この方向でよければ PR を出せます。
