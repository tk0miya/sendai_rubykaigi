# ERB の書き換えの前後を ActionView で描画して比べ、ERB がコンパイルされる Ruby を表示する
#
#   ruby semantics/render.rb
#
# actionview gem（8.1.4.1 で確認）が必要。

require "action_view"
class V < ActionView::Base
  def badge = "<b>new</b>".html_safe
  def path = "/users/1"
end
def tmpl(src, fmt = :html) = ActionView::Template.new(src, "t.#{fmt}.erb", ActionView::Template::Handlers::ERB.new, locals: %i[a b c admin active items x], format: fmt)
def render(src, fmt = :html, **l)
  view = V.with_empty_template_cache.with_view_paths([])
  tmpl(src, fmt).render(view, { a: nil, b: "B", c: "C", admin: true, active: true, items: [1, 2, 3], x: 1 }.merge(l))
end
def cmp(title, before, after, fmt = :html, cases: [{}])
  puts "## #{title}"
  cases.each do |l|
    r1 = render(before, fmt, **l); r2 = render(after, fmt, **l)
    puts "  #{l.inspect} same=#{r1 == r2}"; puts "    before: #{r1.inspect}"; puts "    after:  #{r2.inspect}" unless r1 == r2
  end
end
def src(erb) = puts("## src #{erb.inspect}\n" + ActionView::Template::Handlers::ERB::Erubi.new(erb).src)

src '<%= a %><%= b %>'
src '<% if active %>on<% else %>off<% end %>'
src "<% case x %>\n<% when 1 %>\n  one\n<% end %>"
src '<% if a %><p>x</p><% end %>'
cmp "IfUnlessModifier", '<% if admin %><%= badge %><% end %>', '<%= badge if admin %>', cases: [{admin: true}, {admin: false}]
cmp "OneLineConditional", '<% if a %><%= b %><% else %><%= c %><% end %>', '<%= a ? b : c %>', cases: [{a: true}, {a: false}]
cmp "IfWithSemicolon attr", '<div class="<% if active %>on<% else %>off<% end %>">x</div>', %q{<div class="<%= active ? "on" : "off" %>">x</div>}, cases: [{active: true}, {active: false}]
cmp "Next", "<% items.each do |i| %>\n<% if i.odd? %>\n<li>\n<%= i %>\n</li>\n<% end %>\n<% end %>\n", "<% items.each do |i| %>\n<% next unless i.odd? %>\n<li>\n<%= i %>\n</li>\n<% end %>\n"
cmp "ConditionalAssignment", '<% if a %><% y = 1 %><% else %><% y = 2 %><% end %><%= y %>', '<% y = a ? 1 : 2 %><%= y %>', cases: [{a: true}, {a: false}]
cmp "BlockDelimiters", '<%= link_to(path) do %>Profile<% end %>', '<%= link_to(path) { %>Profile<% } %>'
cmp "SingleLineDoEndBlock content_for", '<% content_for(:title) do %>Hello <%= b %><% end %><%= content_for(:title).inspect %>', "<% content_for(:title) do %>\n  Hello <%= b %>\n<% end %><%= content_for(:title).inspect %>"
cmp "SingleLineDoEndBlock inline link", 'Click<%= link_to(path) do %>here<% end %>.', "Click<%= link_to(path) do %>\n  here\n<% end %>."
cmp "SingleLineDoEndBlock attr", '<div class="<% items.each do |i| %>c<%= i %> <% end %>">x</div>', "<div class=\"<% items.each do |i| %>\n  c<%= i %>\n<% end %>\">x</div>"
cmp "SingleLineDoEndBlock text", 'Items: <% items.each do |i| %><%= i %>,<% end %>', "Items: <% items.each do |i| %>\n  <%= i %>,\n<% end %>", :text
cmp "ElseLayout", '<% if a %>x<% else %><%= b %><% end %>', "<% if a %>x<% else %>\n<%= b %><% end %>", cases: [{a: false}]
cmp "BlockEndNewline", '<% items.each do |i| %><p><%= i %></p><% end %>', "<% items.each do |i| %><p><%= i %></p>\n<% end %>"
