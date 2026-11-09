# 実際のビュー（work/views）で、ERB タグに跨がるブロックのうち 1 行に書いたものを数える
#
#   ruby semantics/count_structures.rb
#
# herb gem（0.11.1 で確認）が必要。
require "herb"

class BlockCounter < Herb::Visitor
  attr_reader :blocks, :one_line_blocks

  def initialize
    @blocks = 0
    @one_line_blocks = 0
    super
  end

  def visit_erb_block_node(node)
    @blocks += 1
    @one_line_blocks += 1 if node.location.start.line == node.location.end.line
    super
  end
end

counter = BlockCounter.new
files = Dir["work/views/**/*.html.erb"]
files.each { |f| Herb.parse(File.read(f)).value.accept(counter) }
puts "files: #{files.size}, blocks across ERB tags: #{counter.blocks}, written on one line: #{counter.one_line_blocks}"
