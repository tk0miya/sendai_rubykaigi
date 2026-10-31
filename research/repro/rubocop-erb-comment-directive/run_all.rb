# frozen_string_literal: true

# 方策ごとに、入力を 1 ファイルずつ rubocop にかける（無効化がファイルをまたがないように）。
#   BUNDLE_GEMFILE=../rubocop-erb-0.8/v0.8.2/Gemfile bundle exec ruby run_all.rb FILE...
require 'rubocop'

MODES = %w[none render_all render_safe directive_only directive_only_cops].freeze
dir = __dir__

ARGV.each do |file|
  config = File.basename(file).start_with?('empty_if') ? 'config_empty_if.yml' : 'config.yml'
  MODES.each do |mode|
    ENV['ERB_COMMENT_DIRECTIVE'] = mode
    puts "== #{mode} #{file}"
    $stdout.flush
    RuboCop::CLI.new.run(['--cache', 'false', '-c', File.join(dir, config), '--format', 'emacs', file])
  end
end
