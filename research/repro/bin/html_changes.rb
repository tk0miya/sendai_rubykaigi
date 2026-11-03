# frozen_string_literal: true

# autocorrect の前後のディレクトリを比べ、書き換わった ERB のうち
# HTML（ERB タグ以外。空白の違いは無視）が変わったものと、Herb のパースエラーが増えたものを数える
#
#   bundle exec ruby html_changes.rb BEFORE_DIR AFTER_DIR

require "herb"

before_dir, after_dir = ARGV
rewritten = html_changed = errors_increased = 0

Dir.glob("**/*.erb", base: before_dir).each do |path|
  before = File.read(File.join(before_dir, path))
  after = File.read(File.join(after_dir, path))
  next if before == after

  rewritten += 1
  html_changed += 1 if Herb.extract_html(before).split != Herb.extract_html(after).split
  errors_increased += 1 if Herb.parse(after).errors.size > Herb.parse(before).errors.size
end

puts "rewritten=#{rewritten} html_changed=#{html_changed} parse_errors_increased=#{errors_increased}"
