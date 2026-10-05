# Building a Unified Ecosystem for ERB Development Experience

## Abstract

ERBはRailsのビューを支える中心的な機能です。しかし、Rails の Ruby 部分の開発体験がリンターや型チェッカーの進化によって向上する一方、ERB の開発体験はなかなか向上していません。これまでも ERB の開発補助ツールが提供されてきましたが、Ruby ほどの開発体験を提供してはいません。

本トークでは、ERB の開発体験向上させる新しいツール、アーキテクチャを提案します。とくにこのトークでは HTML + ERB をメインで取り扱います。ERB を「コンテンツと Ruby コード片の集合」ではなく「構造化されたドキュメント」として扱うことで、以下のような包括的なDXの実現を実演します。

* 総合的なリントとフォーマット: HTMLとRubyの解析を協調させ、インデントから冗長なロジックに至るまで、あらゆる問題を修正します。
* セマンティック解析: Ruby LSPによるモダンなIDE機能や、Steepによる静的解析を提供し、テンプレートとRailsアプリケーション本体との乖離を解消します。

今こそ、ERBでもモダンな開発を行いましょう。

## Details

ERB が抱える根本的な課題は、ツリー構造を持つHTMLと、命令型で記述されるRubyのフローが混在している点にあります。既存のツールでは、HTML パートのみを扱ったり、Ruby パートのみを扱おうとしており、提供されている機能が不完全でした。また、RuboCop の制約により Ruby 部分のチェックも不完全なものにとどまっていました。本アプローチでは、ハイブリッドパーサーを用いて HTML と Ruby のふたつの側面でリントやフォーマットを実現します。


時間が許せば、この統合された基盤がどのように高度な機能を実現するのか、簡単に解説します。

* ERB の型チェック
* Language Serverの統合


成果物:

* https://github.com/tk0miya/herb-tools-ruby
  * Ruby 版の herb-lint, herb-format コマンドです
  * オリジナル版は TypeScript 製のため RubyLSP や RuboCop と連携できないため、Ruby 向けに書き換えました
* https://github.com/tk0miya/rubocop-herb
  * HTML+ERB 用の RuboCop プラグインです
  * 既存の erb 向けの RuboCop 拡張と比べ、チェックできる範囲、auto correct できる範囲が広がっています

## Pitch

「ERB問題」は、Rails開発者にとって普遍的な悩みの種です。HTMLとRubyそれぞれのツールは存在しますが、統合されたエコシステムが欠如しているために、ERB はサポートが薄い部分です。本トークでは、モダンな構成要素を用いてこの溝を埋めるための技術的なロードマップを提示します。

登壇者としての適格性
私はSteepやrbs_railsへの貢献など、Rubyの型システムの向上に尽力してきました。私は以前SteepリポジトリへのERBサポートの提案や、関連する修正の提案も行ってきました（参考: https://github.com/soutaro/steep/issues/1409）。
