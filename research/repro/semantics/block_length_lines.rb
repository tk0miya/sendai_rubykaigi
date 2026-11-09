# Metrics/BlockLength の offense（--format emacs）を標準入力から読み、ブロックの本文の行を
# ERB タグを含む行と HTML だけの行に分けて数える
#
#   BUNDLE_GEMFILE=$RUBOCOP_HERB/Gemfile bundle exec rubocop --cache false -c semantics/block_length.yml \
#     --only Metrics/BlockLength --format emacs work/views | ruby semantics/block_length_lines.rb
$stdin.each_line do |line|
  next unless line.include?("Metrics/BlockLength")

  path, lineno, _column, message = line.split(":", 4)
  length = message[%r{\[(\d+)/}, 1].to_i
  body = File.readlines(path)[lineno.to_i, length]
  erb_lines = body.count { _1.match?(/<%(?!#)/) }
  html_lines = body.count { !_1.include?("<%") && !_1.strip.empty? }
  puts "#{path.sub(%r{.*work/views/}, "")}:#{lineno} length=#{length} lines_with_erb_tags=#{erb_lines} html_only_lines=#{html_lines}"
end
