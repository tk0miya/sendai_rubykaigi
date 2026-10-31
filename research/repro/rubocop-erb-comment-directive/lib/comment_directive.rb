# frozen_string_literal: true

# rubocop-erb 0.8.2 に `<%# rubocop:disable … %>` のサポートを足す 3 つの方策の試作。
# 環境変数 ERB_COMMENT_DIRECTIVE で方策を選ぶ。
#
# - render_all:     Herb.extract_ruby に comments: true を付け、ERB コメントをすべて Ruby のコメントにする
# - render_safe:    右側（同じ行の後ろ）に Ruby のコードがない ERB コメントだけを Ruby のコメントにする
# - directive_only: Ruby のコードは変えず、ERB コメントを無効化コメントとして CommentConfig だけに渡す
#
# 未設定か none なら何もしない（0.8.2 のまま）。
require 'herb'
require 'rubocop'
require 'rubocop/erb'

module ErbCommentDirective
  def self.mode
    ENV.fetch('ERB_COMMENT_DIRECTIVE', nil)
  end

  # `<%# … %>` と、`#` で始まる 1 行のタグ `<% # … %>`。どちらも extract_ruby が空白にする
  def self.comment_nodes(herb_root)
    nodes = []
    visitor = Class.new(Herb::Visitor) do
      define_method(:visit_erb_comment_node) do |node|
        nodes << node
        super(node)
      end
      define_method(:visit_erb_content_node) do |node|
        nodes << node if node.content.value.match?(/\A\s*#/) && !node.content.value.include?("\n")
        super(node)
      end
    end
    visitor.new.visit(herb_root)
    nodes
  end

  # ERB のコメントのタグ（バイト列）を、同じ長さの Ruby のコメントにする。
  # 2 行目以降は、行頭の空白 1 文字を `#` に置き換える。空白だけの行はそのまま。
  # 行頭に空白のない行があると、長さを変えずに `#` を置けないので nil を返す
  def self.render_comment(source, node)
    opening = node.tag_opening.value
    head = opening == '<%#' ? '  #' : ' ' * opening.bytesize
    content = source.byteslice(node.content.range.from, node.content.range.to - node.content.range.from)
    first, *rest = (content + (' ' * node.tag_closing.value.bytesize)).split("\n", -1)
    rest = rest.map do |line|
      next line if line.strip.empty?
      return nil unless line.start_with?(' ', "\t")

      "##{line.byteslice(1..)}"
    end
    head + [first, *rest].join("\n")
  end

  # 方策 1・2: Ruby の取り出しを変える
  module ExtractorPatch
    private

    def extracted_ruby_bytes
      case ErbCommentDirective.mode
      when 'render_all'
        Herb.extract_ruby(template_source, comments: true)
      when 'render_safe'
        render_safe
      else
        Herb.extract_ruby(template_source)
      end
    end

    # 右側（同じ行の残り）に Ruby のコードがないコメントだけを、render_comment で Ruby のコメントにする
    def render_safe
      plain = Herb.extract_ruby(template_source)
      source = template_source.b
      result = plain.b
      ErbCommentDirective.comment_nodes(Herb.parse(template_source).value).each do |node|
        from = node.tag_opening.range.from
        to = node.tag_closing.range.to
        rest = result.byteslice(to, (result.byteindex("\n", to) || result.bytesize) - to) # 行の残り（Ruby 以外は空白）
        next unless rest.strip.empty?

        rendered = ErbCommentDirective.render_comment(source, node)
        result[from, to - from] = rendered if rendered
      end
      result.force_encoding(Encoding::UTF_8)
    end

    # 0.8.2 の extracted_ruby の Herb.extract_ruby(template_source) を差し替えたもの
    def extracted_ruby
      extracted = extracted_ruby_bytes
      return extracted if extracted.length == template_source.length

      realigned = +''
      byte_index = 0
      template_source.each_char do |char|
        size = char.bytesize
        chunk = extracted.byteslice(byte_index, size)
        realigned << (size == 1 || chunk == char ? chunk : ' ')
        byte_index += size
      end
      realigned
    end
  end

  # 方策 3: ERB コメントを、Ruby のコードに出さずに無効化コメントとして渡す
  class ErbComment < Parser::Source::Comment
    def initialize(range, text)
      @erb_text = text.freeze
      super(range)
    end

    def text
      @erb_text
    end
  end

  class ErbCommentConfig < RuboCop::CommentConfig
    def initialize(processed_source)
      super
      @no_directives = !processed_source.template_source.include?('rubocop')
    end

    private

    def each_directive(&block)
      super
      processed_source.erb_comments.each do |comment|
        directive = RuboCop::DirectiveComment.new(comment, registry)
        yield directive if directive.cop_names
      end
    end
  end

  module ERBSourcePatch
    def comment_config
      return super unless ErbCommentDirective.mode == 'directive_only'

      @comment_config ||= ErbCommentConfig.new(self)
    end

    # コメントの行ごとに、無効化コメントの候補を作る。1 行目は `#` から、2 行目以降は行頭から始まる。
    # text は ERB に書かれた文字列で、2 行目以降は行頭の空白 1 文字を `#` に置き換える（空白がなければ `#` を足す）
    def erb_comments
      source = template_source.b
      @erb_comments ||= ErbCommentDirective.comment_nodes(erb_root).flat_map do |node|
        start = node.tag_opening.value == '<%#' ? node.tag_opening.range.to - 1 : node.content.range.from + node.content.value.index('#')
        body = source.byteslice(start, node.content.range.to - start)
        offset = start
        body.split("\n", -1).each_with_index.filter_map do |line, index|
          line_start = offset
          offset += line.bytesize + 1
          stripped = line.rstrip
          next if stripped.empty?

          text = if index.zero? then stripped
                 elsif stripped.start_with?(' ', "\t") then "#" + stripped.byteslice(1..)
                 else "#" + stripped
                 end
          range = herb_range_to_parser_range(Herb::Range.new(line_start, line_start + stripped.bytesize))
          ErbComment.new(range, text.force_encoding(Encoding::UTF_8))
        end
      end
    end
  end
end

RuboCop::Erb::RubyExtractor.prepend(ErbCommentDirective::ExtractorPatch)
RuboCop::Erb::ERBSource.prepend(ErbCommentDirective::ERBSourcePatch)
