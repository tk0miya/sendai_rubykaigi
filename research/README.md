# ERB の Ruby を RuboCop で検査するツールの調査

調査日: 2026-11-03

「既存の ERB linter は、ERB に埋め込まれた Ruby を正しく lint できない」ことと、tk0miya/rubocop-herb がそれをどう解決しているかを調べた結果です。
発表（[proposal.md](../proposal.md)、[slides/outline.md](../slides/outline.md)）の裏付けとして使います。

文書は 3 部に分かれています。

- [第 1 部 ERB linter の比較](comparison.md): 既存のツールと tk0miya-rubocop-herb を、同じ入力にかけて比べた結果
- [第 2 部 tk0miya-rubocop-herb の実装](tk0miya-rubocop-herb.md): tk0miya-rubocop-herb が ERB をどう Ruby にし、RuboCop の誤検知と壊れる autocorrect をどう防いでいるか
- [第 3 部 ERB に合わない RuboCop の cop](erb-and-rubocop.md): ERB に合わない cop を、ERB との関係で分類し、ERB と RuboCop の役割の境界を考える

## 凡例

- 【実測】: 手元で実行して確かめたこと。検証用 ERB と手順は [repro/README.md](repro/README.md)
- 【出典】: ソースコード、issue、ドキュメントなどの公開情報で確かめたこと
- 【推測】: 解釈

## 対象

| ツール | 版 | 方式 |
|---|---|---|
| erb_lint（Rubocop linter） | 0.9.0 | タグ単位 |
| rubocop-erb 0.7 系 | 0.7.2 | タグ単位 |
| rubocop-erb 0.8 系 | 0.8.2 | 文書全体（`Herb.extract_ruby`） |
| marcoroth/herb#2260 の rubocop-herb（以下「herb-rubocop-herb」） | `d0323df360553502e31b14ff570990f907f46b2a`（2026-10-06 時点の PR の head。Draft） | 文書全体（`Herb.extract_ruby`） |
| ruumba | 0.1.17 | 文書全体（正規表現） |
| tk0miya/rubocop-herb（以下「tk0miya-rubocop-herb」） | `4cbe9062156f28b95d94d27ebc59ab3f9da35f33`（2026-11-09 時点の main と `lib/` が同じ） | 文書全体（Herb の AST から独自に変換） |
| herb-lint / herb-format | @herb-tools/linter 0.11.1 / @herb-tools/formatter 0.11.1 | RuboCop を使わない |

- rubocop 1.92.1、herb 0.11.1（herb-rubocop-herb だけは gemspec が固定している 0.11.0）、ruby 4.0.5、node v26.9.0
- rubocop 系の設定は、どれも `NewCops: enable`、`TargetRubyVersion: 3.4`。erb_lint と ruumba は README の推奨設定、tk0miya-rubocop-herb はリポジトリの `config/develop/rubocop.yml`
- 入力は 2 つ
  - 検証用 ERB: [repro/cases/](repro/cases/) の 78 ファイル。どのツールも同じファイルにかけた
  - 実際のビュー: rails/rails `0f591639b8` と kaigionrails/conference-app `25a02cc` の `*.html.erb`（333 ファイル）

## まとめ

- ERB から Ruby を取り出す方式は 2 つある。**タグ単位に分割する**方式（erb_lint、rubocop-erb 0.7 系）は、制御構造・変数スコープ・ファイルという文脈を失い、見逃し・誤検知・テンプレートを壊す autocorrect が起きる（[第 1 部 3 章](comparison.md#3-タグ単位の方式)）
- **文書全体を 1 本の Ruby にする**方式（ruumba、rubocop-erb 0.8 系、herb-rubocop-herb、tk0miya-rubocop-herb）は文脈を保つ。ただし、ERB タグの外を空白にすると `<%=` の「出力する」という意味と HTML の存在が消え、ERB として正しいテンプレートと直すべきテンプレートが同じ Ruby になる。cop には区別できないので、誤検知を出すか、cop を除外して見逃すしかない（[第 1 部 5.2 節](comparison.md#52-erb-として正しいものと直すべきものの区別)）
  - herb-rubocop-herb は誤検知が多く、`-a` でもテンプレートを壊す。実際のビュー 333 ファイルのうち 63 ファイルで HTML が変わる
  - rubocop-erb 0.8 系は 65 個の cop を除外し、修正の範囲を検査するので、テンプレートを壊さない。代わりに、除外した cop の妥当な指摘も失う
- tk0miya-rubocop-herb は、`<%=` を `_ =` に、HTML を `div;` などの識別子にして、ERB の意味を Ruby の上に残す。ファイル全体で除外する cop は 9 個。変換で書いた文字（`;`、`_ =`、区切りの位置の空白）への指摘は、ERB タグに書かれたコードの上のものだけを残し、ほかの誤検知は ERB の構造を見て該当する行だけで無効にする。修正後の ERB を検査して、テンプレートを壊す autocorrect を捨てる（[第 2 部](tk0miya-rubocop-herb.md)）
- tk0miya-rubocop-herb の RuboCop の cop の autocorrect は、検証用 ERB でも実際のビューでもテンプレートを壊さなかった。ERB に合わない修正は、捨てて指摘だけを残す。ただし、`Herb/Linting` と `Herb/Formatting` が適用する herb-lint と herb-format の修正は検査しないので、herb-lint の `erb-comment-syntax` の修正が複数行のタグのコードをコメントにするバグも、`rubocop -a` で適用される（[第 2 部 8 章](tk0miya-rubocop-herb.md#8-既知の問題実測推測)）
- ERB に合わない cop は、ERB との関係で 4 つに分けられる。区切りへの指摘、HTML が見えないことによる指摘、ERB の書き方に合わない指摘、配置への指摘。配置への指摘には、`<%=` と `<% end %>` の幅の違いで `form_with` などのブロックの開始と `end` が必ずずれる、という ERB 特有のものがある。ERB の書き方に合わない指摘は、従うと出力が変わるもの（`Style/SingleLineDoEndBlock` など）と、出力が変わらないスタイルの選択（`Style/IfUnlessModifier` など）に分かれる（[第 3 部](erb-and-rubocop.md)）
- tk0miya-rubocop-herb に切り替える理由は Ruby 部分の検査の正しさで、使い続ける理由は既存ツールの実績と RuboCop 以外の機能（[第 1 部 9 章](comparison.md#9-既存ツールから-tk0miya-rubocop-herb-に切り替えるか)）

## 関連する文書

- [repro/README.md](repro/README.md): 検証用 ERB（`cases/`）、ツールを切り替える `bin/lint`、結果（`results/`）
