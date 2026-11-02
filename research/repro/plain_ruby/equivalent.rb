# frozen_string_literal: true

# Plain Ruby equivalent of cases/control_flow/{nil_comparison,if_then_elsif_else,unused_block_arg}.html.erb
if foo == nil
  puts 'yes'
end

if !foo.nil? then
  puts 'a'
elsif bar == nil
  puts 'b'
else
end
unless !x
end

items.each do |i|
  puts 'item'
end
