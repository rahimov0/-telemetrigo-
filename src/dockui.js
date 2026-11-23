// Foto ve video editörü için ortak alt araç şeridi simgeleri
const P = {
  'Şablon': '<rect x="3" y="3" width="8" height="8" rx="2"/><rect x="13" y="3" width="8" height="5" rx="2"/><rect x="13" y="10" width="8" height="11" rx="2"/><rect x="3" y="13" width="8" height="8" rx="2"/>',
  'Boyut': '<path d="M6 2v14a2 2 0 0 0 2 2h14M2 6h14a2 2 0 0 1 2 2v14"/>',
  'Harita': '<path d="M3 6l6-3 6 3 6-3v15l-6 3-6-3-6 3z"/><path d="M9 3v15M15 6v15"/>',
  'Renk': '<circle cx="12" cy="12" r="9"/><circle cx="8" cy="10.5" r="1.2"/><circle cx="12" cy="7.5" r="1.2"/><circle cx="16" cy="10.5" r="1.2"/>',
  'Yazı': '<path d="M5 6V4h14v2M12 4v16M9 20h6"/>',
  'Değerler': '<path d="M4 6h16M4 12h10M4 18h13"/>',
  'Fotoğraf': '<rect x="3" y="4" width="18" height="16" rx="3"/><circle cx="9" cy="10" r="1.8"/><path d="m21 16-5-5-8 8"/>',
  'Gizlilik': '<rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>',
  'Göstergeler': '<path d="M4 17a8 8 0 0 1 16 0"/><path d="M12 17l4-5"/>',
  'Hizalama': '<path d="M4 12h16M8 8l-4 4 4 4M16 8l4 4-4 4"/>',
  'Görünüm': '<path d="M4 7h10M18 7h2M4 17h2M10 17h10"/><circle cx="16" cy="7" r="2"/><circle cx="8" cy="17" r="2"/>',
  'Dışa aktar': '<path d="M12 3v12M7 11l5 5 5-5M5 21h14"/>',
  'İçerik': '<rect x="3" y="5" width="18" height="14" rx="3"/><path d="M7 10h6M7 14h10"/>',
  'Zaman': '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
  'Yerleşim': '<rect x="3" y="3" width="18" height="18" rx="3"/><rect x="12" y="12" width="6" height="6" rx="1.5"/>',
};
/** Araç şeridi düğmesi: simge + kısa ad */
export function tabButton(name, onclick) {
  const b = document.createElement('button'); b.type = 'button';
  b.innerHTML = `<svg viewBox="0 0 24 24" aria-hidden="true">${P[name] || '<circle cx="12" cy="12" r="8"/>'}</svg><span>${name}</span>`;
  b.onclick = onclick; return b;
}
/** Şablon küçük resimleri: draw(ctx, w, h, key) ile her seçeneğin gerçek önizlemesi */
export function thumbStrip(el, items, get, set, draw, w = 132, h = 176) {
  el.className = 'thumbs';
  const paint = () => { el.querySelectorAll('canvas').forEach(c => { const x = c.getContext('2d'); x.clearRect(0, 0, w, h); try { draw(x, w, h, c.dataset.k); } catch {} }); };
  el.innerHTML = '';
  for (const [k, name] of Object.entries(items)) {
    const b = document.createElement('button'); b.type = 'button'; b.className = get() === k ? 'on' : '';
    const c = document.createElement('canvas'); c.width = w; c.height = h; c.dataset.k = k;
    const s = document.createElement('small'); s.textContent = name; b.append(c, s);
    b.onclick = () => { set(k); el.querySelectorAll('button').forEach(x => x.classList.toggle('on', x === b)); };
    el.append(b);
  }
  el._paint = paint; paint();
}
