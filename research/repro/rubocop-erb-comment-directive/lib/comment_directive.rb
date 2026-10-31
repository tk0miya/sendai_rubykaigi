# frozen_string_literal: true

# rubocop-erb 0.8.2 に `<%# rubocop:disable … %>` のサポートを足す 3 つの方策の試作。
# 環境変数 ERB_COMMENT_DIRECTIVE で方策を選ぶ。
#
# - render_all:     Herb.extract_ruby に comments: true を付け、ERB コメントをすべて Ruby のコメントにする
# - render_safe:    右側（同じ行の後ろ）に Ruby のコードがない ERB コメントだけを Ruby のコメントにする
# - directive_only: Ruby のコードは変えず、ERB コメントを無効化コメントとして CommentConfig だけに渡す
# - directive_only_cops: directive_only に加え、processed_source.comments や raw_source から無効化コメントを探す cop に
#                        ERB コメントを見せる
#
# 未設定か none なら何もしない（0.8.2 のまま）。
require 'herb'
require 'rubocop'
require 'rubocop/erb'

module ErbCommentDirective
  def self.mode
    ENV.fetch('ERB_COMMENT_DIRECTIVE', nil)
  end

  def self.directive_only?
    %w[directive_only directive_only_cops].include?(mode)
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
      # directive_only_cops の cop の調査中は processed_source.comments が ERB コメントを含むので、
      # super では ERB コメントを見せず、同じ無効化コメントを 2 回渡さないようにする
      ErbCommentDirective.without_view { super }
      processed_source.erb_comments.each do |comment|
        directive = RuboCop::DirectiveComment.new(comment, registry)
        yield directive if directive.cop_names
      end
    end
  end

  module ERBSourcePatch
    def comment_config
      return super unless ErbCommentDirective.directive_only?

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

# directive_only_cops: 無効化コメントを CommentConfig を通さずに探す cop に、ERB コメントを見せる。
# その cop の on_new_investigation の間だけ、ERBSource の comments に ERB コメントを足し、raw_source を元の ERB にする。
# processed_source を別のオブジェクト（SimpleDelegator など）に差し替えると、rubocop-erb の Corrector が
# ERBSource と見なさず、修正範囲の検査を飛ばすので、ERBSource のまま振る舞いを変える
module ErbCommentDirective
  module DirectiveViewPatch
    def comments
      return super unless Thread.current[:erb_comment_directive_view]

      (super + erb_comments).sort_by { |comment| comment.source_range.begin_pos }
    end

    def raw_source
      Thread.current[:erb_comment_directive_view] ? template_source : super
    end
  end

  def self.without_view
    view = Thread.current[:erb_comment_directive_view]
    Thread.current[:erb_comment_directive_view] = false
    yield
  ensure
    Thread.current[:erb_comment_directive_view] = view
  end

  # rubocop-ast の ProcessedSource が comments から作って覚える値。調査の前に消して ERB コメントを含めて作り直させ、
  # 調査の後に元に戻す。戻さないと、後の cop（Lint/EmptyConditionalBody など）に ERB コメントが見える
  MEMOIZED_FROM_COMMENTS = %i[@comment_index @ast_with_comments].freeze

  module CopPatch
    def on_new_investigation
      source = processed_source
      return super unless ErbCommentDirective.mode == 'directive_only_cops' && source.is_a?(RuboCop::Erb::ERBSource)

      saved = MEMOIZED_FROM_COMMENTS.to_h { |name| [name, source.instance_variable_get(name)] }
      begin
        MEMOIZED_FROM_COMMENTS.each { |name| source.instance_variable_set(name, nil) }
        Thread.current[:erb_comment_directive_view] = true
        super
      ensure
        Thread.current[:erb_comment_directive_view] = false
        saved.each { |name, value| source.instance_variable_set(name, value) }
      end
    end
  end

  [
    RuboCop::Cop::Lint::RedundantCopEnableDirective, # raw_source に 'enable' / 'pop' がなければ調べない
    RuboCop::Cop::Lint::CopDirectiveSyntax,          # processed_source.comments を調べる
    RuboCop::Cop::Style::DirectiveScope              # processed_source.comments を調べる
  ].each { |cop| cop.prepend(CopPatch) }
end

RuboCop::Erb::ERBSource.prepend(ErbCommentDirective::DirectiveViewPatch)
RuboCop::Erb::RubyExtractor.prepend(ErbCommentDirective::ExtractorPatch)
RuboCop::Erb::ERBSource.prepend(ErbCommentDirective::ERBSourcePatch)
