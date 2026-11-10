# ERB を、元の ERB と文字位置が揃った Ruby にする
#
#   ruby semantics/extract_ruby.rb SRC_DIR OUT_DIR [norm|empty]
#
# HTML を空白にする方式（herb gem の Herb.extract_ruby）で Ruby にする。
# norm を付けると、開始タグの幅を揃えてから Ruby にする（<%= や <%- を <% と同じ 3 文字にする）。
# empty を付けると、空白だけの行の空白を除く（HTML だけの行が空行になる）。
# 環境変数 MARKER=1 を付けると、tk0miya-rubocop-herb のマーカー方式で Ruby にする
# （BUNDLE_GEMFILE="$RUBOCOP_HERB/Gemfile" bundle exec ruby で実行する）。
# herb gem（0.11.1 で確認）が必要。
require "herb"
require "fileutils"

def to_ruby(path, erb)
  return Herb.extract_ruby(erb) unless ENV["MARKER"]

  require "rubocop"
  require "rubocop/herb"
  RuboCop::Herb::RubyRenderer.render(RuboCop::Herb::ErbParser.parse(path, erb))
end

src_root, out_root, mode = ARGV
Dir.glob("#{src_root}/**/*.html.erb").each do |f|
  erb = File.read(f)
  erb = erb.gsub(/<%(?![%#])[=-]?[ \t]*/, "<% ") if mode == "norm"
  ruby = to_ruby(f, erb)
  ruby = ruby.gsub(/^[ \t]+$/, "") if mode == "empty"
  out = File.join(out_root, f.delete_prefix(src_root).sub(/\.html\.erb\z/, ".rb"))
  FileUtils.mkdir_p(File.dirname(out))
  File.write(out, ruby)
end
