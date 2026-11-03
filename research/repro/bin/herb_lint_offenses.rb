# frozen_string_literal: true

# herb-lint --json の出力を、rubocop の emacs 形式に似た 1 行 1 件の形にする
#
#   npx herb-lint --json cases | ruby bin/herb_lint_offenses.rb

require "json"

offenses = JSON.parse($stdin.read).fetch("offenses")
lines = offenses.map do |o|
  start = o.dig("location", "start")
  [o["filename"], start["line"], start["column"], "#{o["severity"]}: [#{o["code"]}] #{o["message"]}"]
end
lines.sort_by { |file, line, column, _| [file, line, column] }.each do |file, line, column, message|
  puts "#{file}:#{line}:#{column}: #{message}"
end
