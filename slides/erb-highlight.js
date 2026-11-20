// ERB のタグ構造を見せるためのハイライト。
//
// このトークでは Ruby の構文ではなく、ERB のタグ構造を見せたい。そのため highlight.js は使わず、
// <code class="language-erb"> を次の 3 つに分けて色を付ける。
//   - .erb-delim: タグの区切り（<% <%= <%# <%- %> -%>）
//   - .erb-code:  タグの中に書いたコード
//   - .erb-html:  タグの外（HTML とテキスト）
//
// 変換後の Ruby（<code class="language-converted">）は構文から判定できないので、
// このスクリプトは何もしない。
(() => {
  const escape = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  const span = (cls, s) => (s ? `<span class="${cls}">${escape(s)}</span>` : '');

  document.querySelectorAll('code.language-erb').forEach(code => {
    const src = code.textContent;
    const tag = /(<%[=#-]?)([\s\S]*?)(-?%>)/g;
    let html = '';
    let last = 0;
    for (const m of src.matchAll(tag)) {
      html += span('erb-html', src.slice(last, m.index));
      // コードの前後の空白は .erb-code に含めない（枠で囲うときに、コードだけを囲うため）
      const [, lead, body, trail] = m[2].match(/^(\s*)([\s\S]*?)(\s*)$/);
      html += span('erb-delim', m[1]) + escape(lead) + span('erb-code', body) + escape(trail) + span('erb-delim', m[3]);
      last = m.index + m[0].length;
    }
    html += span('erb-html', src.slice(last));
    code.innerHTML = html;
  });
})();
