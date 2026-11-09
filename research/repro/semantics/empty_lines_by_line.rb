# 空行の cop の指摘を、元の ERB の行の種類で分けて数える
#
#   rubocop --format emacs OUT_DIR | ruby semantics/empty_lines_by_line.rb SRC_DIR OUT_DIR
#
# OUT_DIR は semantics/extract_ruby.rb で SRC_DIR から作った Ruby。
src_root, out_root = ARGV
counts = Hash.new(0)
$stdin.each_line do |line|
  next unless (m = line.match(/\A(.+)\.rb:(\d+):\d+: \w: (?:\[Correctable\] )?(Layout\/\w+):/))

  cop = m[3]
  lineno = m[2].to_i
  erb_path = File.join(src_root, File.expand_path(m[1]).delete_prefix(File.expand_path(out_root)) + ".html.erb")
  src = File.read(erb_path)
  erb_line = src.lines[lineno - 1].to_s
  kind =
    if !erb_line.strip.empty?
      "HTML の行"
    else
      before = src.lines[0...lineno - 1].join
      (before.rindex("<%") || -1) > (before.rindex("%>") || -1) ? "空行（タグの中）" : "空行（タグの外）"
    end
  counts[[cop, kind]] += 1
end
counts.sort.each { |(cop, kind), n| puts "#{cop}\t#{kind}\t#{n}" }
