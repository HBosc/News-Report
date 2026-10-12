(() => {
  const $ = (s) => document.querySelector(s);
  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const state = { tab: 'all', q: '', archive: null };
  try { state.tab = localStorage.getItem('tab') || 'all'; } catch {}

  // Theme toggle (remembers choice per browser).
  try { const t = localStorage.getItem('theme'); if (t) document.documentElement.dataset.theme = t; } catch {}
  $('#theme').onclick = () => {
    const root = document.documentElement;
    const dark = root.dataset.theme ? root.dataset.theme === 'dark' : matchMedia('(prefers-color-scheme: dark)').matches;
    root.dataset.theme = dark ? 'light' : 'dark';
    try { localStorage.setItem('theme', root.dataset.theme); } catch {}
  };

  const ago = (iso) => {
    const m = Math.round((Date.now() - new Date(iso)) / 60000);
    if (m < 1) return 'just now';
    if (m < 60) return m + 'm ago';
    const h = Math.round(m / 60);
    if (h < 24) return h + 'h ago';
    const d = Math.round(h / 24);
    return d === 1 ? 'yesterday' : d + 'd ago';
  };
  const img = (a, cls = '') => a.image
    ? `<img class="${cls}" src="${esc(a.image)}" alt="" loading="lazy" referrerpolicy="no-referrer">` : '';
  // Drop broken images. A capturing listener, because the CSP blocks inline onerror= handlers.
  document.addEventListener('error', (e) => { if (e.target.tagName === 'IMG') e.target.remove(); }, true);
  const byline = (a) => `<div class="byline"><span class="src">${esc(a.source)}</span><span>·</span><time datetime="${esc(a.date)}" title="${esc(new Date(a.date).toLocaleString())}">${ago(a.date)}</time></div>`;
  const catStyle = (id) => `style="--cat: var(--c-${esc(id)}, var(--accent))"`;

  const matches = (a) => !state.q || (a.title + ' ' + a.summary + ' ' + a.source).toLowerCase().includes(state.q);

  function frontSection(cat) {
    const list = cat.articles.filter(matches);
    if (!list.length) return '';
    const [lead, ...rest] = list;
    return `<section class="cat" ${catStyle(cat.id)}>
      <div class="cat-head"><h2>${esc(cat.name)}</h2><button data-go="${esc(cat.id)}">All ${list.length} stories →</button></div>
      <div class="front">
        <a class="lead" href="${esc(lead.link)}" target="_blank" rel="noopener">
          ${img(lead)}${byline(lead)}<h3>${esc(lead.title)}</h3><p class="summary">${esc(lead.summary)}</p>
        </a>
        <div class="side">${rest.slice(0, 6).map(a =>
          `<a href="${esc(a.link)}" target="_blank" rel="noopener">${byline(a)}<h3>${esc(a.title)}</h3></a>`).join('')}
        </div>
      </div>
    </section>`;
  }

  function gridSection(cat) {
    const list = cat.articles.filter(matches);
    return `<section class="cat" ${catStyle(cat.id)}>
      <div class="cat-head"><h2>${esc(cat.name)}</h2><span class="byline">${list.length} stories</span></div>
      ${list.length ? `<div class="grid">${list.map(a =>
        `<a class="card" href="${esc(a.link)}" target="_blank" rel="noopener">${img(a)}
          <div class="body">${byline(a)}<h3>${esc(a.title)}</h3><p class="summary">${esc(a.summary)}</p></div></a>`).join('')}</div>`
        : '<p class="empty">No stories match.</p>'}
    </section>`;
  }

  function render() {
    const data = window.NEWS_DATA;
    $('#today').textContent = new Date().toLocaleDateString(undefined, { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' });
    if (!data) {
      $('#main').innerHTML = `<div class="notice">${state.archive
        ? `No archive found for <b>${esc(state.archive)}</b>. <a href="#" id="back"><u>Back to today</u></a>`
        : 'No news yet. The next update will fetch today\'s stories.'}</div>`;
      const back = $('#back'); if (back) back.onclick = (e) => { e.preventDefault(); location.reload(); };
      return;
    }
    const cats = data.categories;
    if (state.tab !== 'all' && !cats.some(c => c.id === state.tab)) state.tab = 'all';

    $('#updated').textContent = 'Updated ' + ago(data.generated) + ' · ' + new Date(data.generated).toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' });
    $('#tabs').innerHTML = [{ id: 'all', name: 'Front Page' }, ...cats].map(c =>
      `<button class="tab" role="tab" data-go="${esc(c.id)}" aria-selected="${c.id === state.tab}">${esc(c.name)}</button>`).join('');

    let html = state.archive ? `<div class="notice">Viewing the archive for <b>${esc(state.archive)}</b>. <a href="#" id="back"><u>Back to today</u></a></div>` : '';
    if (state.tab === 'all') {
      const body = cats.map(frontSection).join('');
      html += body || '<p class="empty">No stories match your search.</p>';
    } else {
      html += gridSection(cats.find(c => c.id === state.tab));
    }
    $('#main').innerHTML = html;
    const back = $('#back'); if (back) back.onclick = (e) => { e.preventDefault(); location.reload(); };

    const failed = (data.sources || []).filter(s => !s.ok);
    const okCount = (data.sources || []).length - failed.length;
    $('#foot').innerHTML = `${okCount} sources loaded` +
      (failed.length ? ` · <span class="bad">Unavailable: ${failed.map(s => esc(s.name)).join(', ')}</span>` : '') +
      ` · Headlines link to the original publishers.`;
  }

  document.addEventListener('click', (e) => {
    const go = e.target.closest('[data-go]');
    if (!go) return;
    state.tab = go.dataset.go;
    try { localStorage.setItem('tab', state.tab); } catch {}
    render();
    window.scrollTo({ top: 0 });
  });

  let t;
  $('#q').addEventListener('input', (e) => {
    clearTimeout(t);
    t = setTimeout(() => { state.q = e.target.value.trim().toLowerCase(); render(); }, 120);
  });

  // Archive: load data/archive/YYYY-MM-DD.js via a script tag (works from file:// too).
  const dayInput = $('#day');
  dayInput.max = new Date().toLocaleDateString('en-CA');
  dayInput.addEventListener('change', () => {
    const d = dayInput.value;
    if (!d) return;
    window.NEWS_DATA = null;
    state.archive = d;
    const s = document.createElement('script');
    s.src = `data/archive/${d}.js?` + Date.now();
    s.onload = s.onerror = () => { render(); s.remove(); };
    document.body.appendChild(s);
  });

  render();
  // Keep the "x min ago" labels fresh without re-rendering (which would reset images/scroll).
  setInterval(() => {
    document.querySelectorAll('time[datetime]').forEach(el => { el.textContent = ago(el.dateTime); });
    if (window.NEWS_DATA) $('#updated').textContent = 'Updated ' + ago(window.NEWS_DATA.generated) + ' · ' +
      new Date(window.NEWS_DATA.generated).toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' });
  }, 60000);
})();
