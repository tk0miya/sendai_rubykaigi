# ERB を、元の ERB と文字位置が揃った Ruby にする（herb gem の Herb.extract_ruby）
#
#   ruby semantics/extract_ruby.rb SRC_DIR OUT_DIR [norm]
#
# norm を付けると、開始タグの幅を揃えてから Ruby にする（<%= や <%- を <% と同じ 3 文字にする）。
# herb gem（0.11.1 で確認）が必要。
require "herb"
require "fileutils"

src_root, out_root, mode = ARGV
Dir.glob("#{src_root}/**/*.html.erb").each do |f|
  erb = File.read(f)
  erb = erb.gsub(/<%(?![%#])[=-]?[ \t]*/, "<% ") if mode == "norm"
  out = File.join(out_root, f.delete_prefix(src_root).sub(/\.html\.erb\z/, ".rb"))
  FileUtils.mkdir_p(File.dirname(out))
  File.write(out, Herb.extract_ruby(erb))
end
