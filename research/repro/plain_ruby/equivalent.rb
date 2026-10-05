# frozen_string_literal: true

# Plain Ruby equivalent of erb_lint/recommended/*.html.erb
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
