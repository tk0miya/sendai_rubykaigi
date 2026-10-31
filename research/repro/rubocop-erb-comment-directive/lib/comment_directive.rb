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

    def render_safe
      plain = Herb.extract_ruby(template_source)
      commented = Herb.extract_ruby(template_source, comments: true)
      result = plain.b
      ErbCommentDirective.comment_nodes(Herb.parse(template_source).value).each do |node|
        from = node.tag_opening.range.from
        to = node.tag_closing.range.to
        rest = plain.byteslice(to, (plain.byteindex("\n", to) || plain.bytesize) - to) # 行の残り（Ruby 以外は空白）
        next unless rest.strip.empty?

        result[from, to - from] = commented.b.byteslice(from, to - from)
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

    # `#` から `%>` の手前までを範囲とするコメント。text は ERB に書かれた文字列
    def erb_comments
      @erb_comments ||= ErbCommentDirective.comment_nodes(erb_root).map do |node|
        hash_pos = node.tag_opening.value == '<%#' ? node.tag_opening.range.to - 1 : node.content.range.from + node.content.value.index('#')
        range = herb_range_to_parser_range(Herb::Range.new(hash_pos, node.content.range.to))
        text = template_source.byteslice(hash_pos, node.content.range.to - hash_pos).rstrip
        ErbComment.new(range.resize(text.length), text)
      end
    end
  end
end

RuboCop::Erb::RubyExtractor.prepend(ErbCommentDirective::ExtractorPatch)
RuboCop::Erb::ERBSource.prepend(ErbCommentDirective::ERBSourcePatch)
