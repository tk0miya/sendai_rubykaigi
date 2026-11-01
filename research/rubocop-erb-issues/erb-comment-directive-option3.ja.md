[erb-comment-directive-option3.md](erb-comment-directive-option3.md)（[r7kamura/rubocop-erb#84](https://github.com/r7kamura/rubocop-erb/issues/84) への返信の下書き）の日本語版です。

参考までに、もう 1 つの方針を置いておきます。issue を出す前に検討しましたが、技術上の問題があって提案しなかったものです。欠点はありますが、新しい cop は要りません。

## 方針 3: 無効化コメントを出力せずに RuboCop に渡す

取り出した Ruby はそのままにして、ERB のコメントのうち無効化コメントだけを、コメントのオブジェクトとして `processed_source.comments` に足します。

- Pros
  - RuboCop は `processed_source.comments` を見て、どこでどの cop を無効にするかを決めるので、どこに書いた directive も Ruby と同じ規則で効く。そのため cop は要らない
  - 取り出した Ruby を変えないので、`Herb.extract_ruby` の出力にさらに依存することはない
- Cons
  - コメントを `processed_source.comments` ではなく、ソースの文字列から探す既存の cop と併用できない。ERB のコメントの位置のソースは空白なので、これらの cop には directive が見えないから
    - `Lint/RedundantCopEnableDirective` は、`processed_source.raw_source` に `enable` が含まれないと何もしないので、不要な `<%# rubocop:enable … %>` を報告しない
    - 20 個ほどの cop は、コメントの行かどうかをソースの文字列で判断する（`RuboCop::Cop::Util#comment_line?`）ので、directive の行を空行と見なす。たとえば `Lint/SuppressedException`（`AllowComments`）は、本文が directive だけの `rescue` を報告する。Ruby では報告しない。directive は次の行から効くので、その directive でこの指摘を抑えることもできない
    - これらの cop に 1 つずつパッチを当てるのは現実的ではない

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

取り出した Ruby（0.8.2 と同じ）：

```
1:
2:
3:        "a"  ;
4:                                                  if x  ;
5:
6:    end  ;
```

`processed_source.comments`：

```
line 2: "# rubocop:disable Style/StringLiterals"
line 4: "# rubocop:disable Lint/LiteralAsCondition"
```

後ろにコードが続く 4 行目も含めて、2 つの directive はどちらも効きます。一方で、取り出した Ruby の 2 行目と 4 行目にはコメントがないので、ソースの文字列からコメントを探す cop には、これらの directive が見えません。

これらの既存の cop と併用できないことから、提案しませんでした。
