items.each do |i|
  if i.odd?
    _erbout << "<li>"
    _erbout << i
    _erbout << "</li>"
  end
end
