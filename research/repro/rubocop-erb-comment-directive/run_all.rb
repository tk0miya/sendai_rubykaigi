# frozen_string_literal: true

# 方策ごとに、入力を 1 ファイルずつ rubocop にかける（無効化がファイルをまたがないように）。
#   BUNDLE_GEMFILE=../rubocop-erb-0.8/v0.8.2/Gemfile bundle exec ruby run_all.rb FILE...
require 'rubocop'

MODES = %w[none render_all render_safe directive_only directive_only_cops comments_all].freeze
dir = __dir__

ARGV.each do |file|
  config = if File.basename(file).start_with?('empty_if') then 'config_empty_if.yml'
           elsif File.basename(file).start_with?('inline_comment') then 'config_inline_comment.yml'
           elsif File.basename(file).start_with?('excluded_') then 'config_excluded_cops.yml'
           else 'config.yml'
           end
  MODES.each do |mode|
    ENV['ERB_COMMENT_DIRECTIVE'] = mode
    puts "== #{mode} #{file}"
    $stdout.flush
    RuboCop::CLI.new.run(['--cache', 'false', '-c', File.join(dir, config), '--format', 'emacs', file])
  end
end
