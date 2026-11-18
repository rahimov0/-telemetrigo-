// Aktivite sayfası: liste, detay (harita, splitler, grafikler) ve fotoğraf şablon editörü.
import { parseGpx } from './gpx.js';
import { putAct, getAct, delAct, listActs, TYPES } from './store.js';
import { analyze, fitRoute, routePath, visibleRange, fmtDur, fmtPace, fmtKm, fmtNum, photoTime, guessType } from './activity.js';
import { drawTiles, MAP_STYLES, onTile, tilesIdle } from './tiles.js';
import { compose, TEMPLATES, FORMATS, ROUTE_COLORS, FIELDS } from './compose.js';

const $ = id => document.getElementById(id);
const esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const isApp = /TelemetriGoApp/.test(navigator.userAgent);
if (isApp) document.documentElement.classList.add('inapp');
const css = v => getComputedStyle(document.documentElement).getPropertyValue(v).trim();
function setMsg(html, kind = 'err') { $('msg').innerHTML = html ? `<div class="msg ${kind}">${html}</div>` : ''; }
const prefs = JSON.parse(localStorage.getItem('tg-act-prefs') || '{}');
const savePrefs = () => localStorage.setItem('tg-act-prefs', JSON.stringify(prefs));

let cur = null;   // { rec, g, A, pins: [{i, t, url}] }

// ---------- başlık metinleri ----------
function titleFor(type, start) {
  const h = new Date(start).getHours();
  const part = h < 5 ? 'Gece' : h < 11 ? 'Sabah' : h < 14 ? 'Öğle' : h < 18 ? 'Öğleden sonra' : h < 22 ? 'Akşam' : 'Gece';
  return `${part} ${{ yuruyus: 'yürüyüşü', kosu: 'koşusu', bisiklet: 'bisiklet turu', motor: 'sürüşü' }[type] || 'aktivitesi'}`;
}
const dateStr = t => new Date(t).toLocaleDateString('tr-TR', { day: 'numeric', month: 'long', year: 'numeric' }) + ' · ' + new Date(t).toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' });

// ---------- içe aktarma ----------
async function importGpx(text, name, extra = {}) {
  const g = parseGpx(text, extra.type ? { type: extra.type } : {});
  const type = extra.type || (TYPES[g.type] ? g.type : guessType(g));
  const id = extra.id || 'g' + g.start;
  const A = analyze(g, type);
  const rec = { id, name: name || g.name || 'GPX', type, start: g.start, end: g.end, dist: A.dist, moving: A.movingTime, gpx: text, src: extra.src || 'gpx', steps: extra.steps || null };
  await putAct(rec);
  return rec;
}
$('importBtn').onclick = () => $('gpxIn').click();
$('gpxIn').onchange = async () => {
  const files = [...$('gpxIn').files]; $('gpxIn').value = ''; let last = null, bad = 0;
  for (const f of files) { try { last = await importGpx(await f.text(), f.name.replace(/\.gpx$/i, '')); } catch (e) { bad++; setMsg(esc(f.name) + ': ' + esc(e.message)); } }
  if (files.length === 1 && last) location.hash = last.id; else renderList();
  if (!bad) setMsg('');
};
// GPS Kaydedici'nin son kaydı (eski sürümlerde geçmişe yazılmamış olabilir)
async function syncLast() {
  try {
    const L = JSON.parse(localStorage.getItem('tg-last-gpx') || 'null'); if (!L?.gpx) return null;
    const id = 'w' + L.start;
    if (await getAct(id)) return id;
    await importGpx(L.gpx, L.name?.replace(/\.gpx$/i, ''), { id, type: L.type, src: 'web' });
    return id;
  } catch { return null; }
}
// iOS uygulaması aktiviteyi buradan verir (sayfa açılırken window.__TG_PENDING ile, ya da çağrıyla)
async function openPending(P) {
  const rec = await importGpx(P.gpx, P.name, { type: P.type, src: 'app', steps: P.steps, id: 'a' + Date.parse((P.gpx.match(/<time>([^<]+)<\/time>/) || [])[1] || '') || undefined });
  const h = rec.id + (P.view === 'photo' ? '/foto' : '');
  history.replaceState(null, '', '#' + h);
  await openDetail(rec.id, P.view === 'photo');
  return true;
}
window.TelemetriGo = Object.assign(window.TelemetriGo || {}, {
  async receiveActivity(gpx, name, type, view, steps) { return openPending({ gpx, name, type, view, steps }); },
});

// ---------- liste ----------
async function renderList() {
  const acts = await listActs();
  const now = new Date(), wk = new Date(now); wk.setHours(0, 0, 0, 0); wk.setDate(wk.getDate() - ((wk.getDay() + 6) % 7));
  const mo = new Date(now.getFullYear(), now.getMonth(), 1).getTime();
  const sum = from => acts.filter(a => a.start >= from).reduce((s, a) => [s[0] + (a.dist || 0), s[1] + (a.moving || (a.end - a.start) / 1000), s[2] + 1], [0, 0, 0]);
  const W = sum(wk.getTime()), M = sum(mo);
  $('totals').innerHTML = [
    ['Bu hafta', `${fmtKm(W[0], 1)}<small>km</small>`], ['Bu hafta süre', fmtDur(W[1])],
    ['Bu ay', `${fmtKm(M[0], 1)}<small>km</small>`], ['Bu ay aktivite', String(M[2])],
  ].map(([k, v]) => `<div class="stat"><div class="k">${k}</div><div class="v">${v}</div></div>`).join('');
  if (!acts.length) {
    $('acts').innerHTML = `<div class="card empty"><div class="ic"><svg class="i"><use href="#i-route"/></svg></div><b style="color:var(--text)">Henüz aktivite yok</b><p class="small" style="margin:6px 0 var(--s4)">GPS Kaydedici ile yeni bir kayıt başlat ya da bir GPX dosyası ekle.</p><a class="btn primary" href="kayit.html">Kayda başla</a></div>`;
    return;
  }
  $('acts').innerHTML = '<div class="list">' + acts.map(a => {
    const T = TYPES[a.type] || {}, mv = a.moving || (a.end - a.start) / 1000, v = a.dist / Math.max(1, mv);
    return `<a class="li" href="#${esc(a.id)}"><span class="ic"><svg class="i"><use href="#t-${TYPES[a.type] ? a.type : 'motor'}"/></svg></span>
      <span class="t"><b>${esc(titleFor(a.type, a.start))}</b><small>${esc(dateStr(a.start))} · ${esc(T.name || '')}</small></span>
      <span class="meta"><b>${fmtKm(a.dist)} km</b><small>${fmtDur(mv)} · ${T.pace ? fmtPace(v) + ' /km' : fmtNum(v * 3.6, 1) + ' km/h'}</small></span>
      <svg class="i chev"><use href="#i-chev"/></svg></a>`;
  }).join('') + '</div>';
}

// ---------- detay ----------
async function openDetail(id, edit) {
  const rec = await getAct(id);
  if (!rec) { setMsg('Aktivite bulunamadı.'); location.hash = ''; return; }
  if (cur?.rec.id !== id) {
    const g = parseGpx(rec.gpx, { type: rec.type });
    cur = { rec, g, A: analyze(g, rec.type), pins: [] }; cur.A.steps = rec.steps || 0;
  }
  const { g, A } = cur, T = TYPES[A.type] || {};
  $('dType').textContent = T.name || ''; $('dTitle').textContent = titleFor(A.type, g.start); $('dSub').textContent = dateStr(g.start);
  $('dTypeSel').innerHTML = Object.entries(TYPES).map(([k, v]) => `<option value="${k}" ${k === A.type ? 'selected' : ''}>${v.name}</option>`).join('');
  const st = [
    ['Mesafe', `${fmtKm(A.dist)}<small>km</small>`], ['Hareket süresi', fmtDur(A.movingTime)],
    A.pace ? ['Ort. tempo', `${fmtPace(A.avg)}<small>/km</small>`] : ['Ort. hız', `${fmtNum(A.avg * 3.6, 1)}<small>km/h</small>`],
    A.pace ? ['En iyi tempo', `${fmtPace(A.vmax)}<small>/km</small>`] : ['Maks hız', `${fmtNum(A.vmax * 3.6)}<small>km/h</small>`],
    ['Yükseliş', g.hasEle ? `${fmtNum(A.gain)}<small>m</small>` : '—'], ['Geçen süre', fmtDur(A.elapsed)],
  ];
  $('dStats').innerHTML = st.map(([k, v]) => `<div class="stat"><div class="k">${k}</div><div class="v">${v}</div></div>`).join('');
  // splitler
  const full = A.splits.filter(s => !s.partial), best = full.length > 1 ? Math.min(...full.map(s => s.time / s.len)) : -1;
  const slow = Math.max(...A.splits.map(s => s.time / s.len), 1e-6);
  $('splits').innerHTML = `<tr><th>Km</th><th>${A.pace ? 'Tempo' : 'Hız'}</th><th>Yükseklik</th><th></th></tr>` + (A.splits.length ? A.splits.map(s => {
    const v = s.len / Math.max(1, s.time), r = (s.time / s.len) / slow;
    return `<tr class="${s.time / s.len === best ? 'best' : ''}"><td>${s.partial ? fmtNum(s.len / 1000, 2) : s.km}</td><td>${A.pace ? fmtPace(v) : fmtNum(v * 3.6, 1) + ' km/h'}</td>
      <td>${isFinite(s.ele) ? (s.ele >= 0 ? '+' : '') + fmtNum(s.ele) + ' m' : '—'}</td><td class="b"><div class="bar2" style="width:${A.pace ? Math.round((1 / r) * 100 * 0.6 + 10) : Math.round((1 / r) * 90)}%"></div></td></tr>`;
  }).join('') : `<tr><td colspan="4" class="muted">1 km'den kısa</td></tr>`);
  $('spdH').textContent = A.pace ? 'Tempo' : 'Hız';
  $('eleCard').classList.toggle('hidden', !g.hasEle);
  const a = $('dlGpx'); if (a.href.startsWith('blob:')) URL.revokeObjectURL(a.href);
  a.href = URL.createObjectURL(new Blob([rec.gpx], { type: 'application/gpx+xml' })); a.download = (rec.name || 'aktivite') + '.gpx';
  show(edit ? 'vEdit' : 'vDetail');
  if (edit) openEditor(); else { requestAnimationFrame(() => { drawMap(); drawCharts(); }); }
}
$('dTypeSel').onchange = async () => {
  const t = $('dTypeSel').value; cur.rec.type = t; const g = parseGpx(cur.rec.gpx, { type: t });
  cur.g = g; cur.A = analyze(g, t); cur.A.steps = cur.rec.steps || 0; cur.rec.dist = cur.A.dist; cur.rec.moving = cur.A.movingTime; await putAct(cur.rec); openDetail(cur.rec.id);
};
$('delAct').onclick = async () => {
  if (!confirm('Bu aktivite bu cihazdan silinsin mi? Bu işlem geri alınamaz.')) return;
  await delAct(cur.rec.id); cur = null; location.hash = '';
};
$('toPhoto').onclick = () => { location.hash = cur.rec.id + '/foto'; };
$('toVideo').onclick = () => {
  const r = cur.rec;
  if (isApp && window.webkit?.messageHandlers?.tg) { window.webkit.messageHandlers.tg.postMessage({ action: 'video', name: r.name + '.gpx', gpx: r.gpx }); return; }
  localStorage.setItem('tg-last-gpx', JSON.stringify({ name: (r.name || 'aktivite') + '.gpx', saved: Date.now(), start: r.start, end: r.end, gpx: r.gpx, type: r.type }));
  location.href = './?gpx=son';
};

function setupCanvas(cv) {
  const r = cv.getBoundingClientRect(), d = Math.min(3, devicePixelRatio || 1);
  cv.width = Math.round(r.width * d); cv.height = Math.round(r.height * d);
  const ctx = cv.getContext('2d'); ctx.setTransform(d, 0, 0, d, 0, 0); return [ctx, r.width, r.height];
}
const mapStyle = () => prefs.map || 'koyu';
function drawMap() {
  if (!cur || $('vDetail').classList.contains('hidden')) return;
  const [ctx, w, h] = setupCanvas($('map')), { g, A } = cur, style = mapStyle();
  const F = fitRoute(g, { x: 0, y: 0, w, h }, { pad: .1 });
  const S = MAP_STYLES[style], dark = style === 'yok' ? !matchMedia('(prefers-color-scheme: light)').matches : S.dark;
  ctx.fillStyle = style === 'yok' ? css('--raised') : dark ? '#1a1a1d' : '#e9e9ec'; ctx.fillRect(0, 0, w, h);
  if (style !== 'yok') drawTiles(ctx, style, g, F.M, F.view);
  const path = routePath(g, F.P);
  ctx.lineCap = 'round'; ctx.lineJoin = 'round';
  ctx.strokeStyle = dark ? 'rgba(0,0,0,.6)' : 'rgba(255,255,255,.9)'; ctx.lineWidth = 7; ctx.stroke(path);
  ctx.strokeStyle = dark ? '#FAFAFA' : '#0A0A0A'; ctx.lineWidth = 3.5; ctx.stroke(path);
  // km işaretleri
  ctx.font = `600 10px ${css('--font')}`; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
  for (const s of A.splits) if (!s.partial) {
    const [x, y] = F.P(g.x[s.i1], g.y[s.i1]);
    ctx.beginPath(); ctx.arc(x, y, 9, 0, 7); ctx.fillStyle = dark ? '#FAFAFA' : '#0A0A0A'; ctx.fill();
    ctx.fillStyle = dark ? '#0A0A0A' : '#FAFAFA'; ctx.fillText(String(s.km), x, y + .5);
  }
  const dot = (i, fill) => { const [x, y] = F.P(g.x[i], g.y[i]); ctx.beginPath(); ctx.arc(x, y, 6, 0, 7); ctx.fillStyle = fill; ctx.fill(); ctx.lineWidth = 2.5; ctx.strokeStyle = dark ? '#000' : '#fff'; ctx.stroke(); };
  dot(0, css('--ok')); dot(g.n - 1, css('--rec'));
  for (const p of cur.pins) { const [x, y] = F.P(g.x[p.i], g.y[p.i]); ctx.beginPath(); ctx.roundRect?.(x - 8, y - 8, 16, 16, 4); ctx.fillStyle = '#fff'; ctx.fill(); ctx.strokeStyle = '#000'; ctx.lineWidth = 2; ctx.stroke(); }
  if (style !== 'yok') { ctx.font = `500 10px ${css('--font')}`; ctx.textAlign = 'right'; ctx.textBaseline = 'alphabetic'; ctx.fillStyle = dark ? 'rgba(255,255,255,.7)' : 'rgba(0,0,0,.6)'; ctx.fillText(S.attr, w - 8, h - 8); }
}
onTile(() => { requestAnimationFrame(drawMap); if (!$('vEdit').classList.contains('hidden')) scheduleEd(); });

function lineChart(cv, xs, ys, { invert = false, fmtY = v => v, fill = true } = {}) {
  const [ctx, w, h] = setupCanvas(cv), pl = 40, pr = 8, pt = 10, pb = 22;
  ctx.clearRect(0, 0, w, h);
  let y0 = Infinity, y1 = -Infinity; for (const v of ys) if (isFinite(v)) { y0 = Math.min(y0, v); y1 = Math.max(y1, v); }
  if (!isFinite(y0)) return;
  if (y1 - y0 < 1e-6) { y0 -= 1; y1 += 1; }
  const pad = (y1 - y0) * .1; y0 -= pad; y1 += pad;
  const X = x => pl + (w - pl - pr) * x / xs[xs.length - 1], Y = v => invert ? pt + (h - pt - pb) * (v - y0) / (y1 - y0) : h - pb - (h - pt - pb) * (v - y0) / (y1 - y0);
  ctx.strokeStyle = css('--line'); ctx.lineWidth = 1; ctx.fillStyle = css('--text-3'); ctx.font = `11px ${css('--font')}`; ctx.textAlign = 'right'; ctx.textBaseline = 'middle';
  for (let k = 0; k <= 3; k++) { const v = y0 + (y1 - y0) * k / 3, y = Y(v); ctx.beginPath(); ctx.moveTo(pl, y); ctx.lineTo(w - pr, y); ctx.stroke(); ctx.fillText(fmtY(v), pl - 6, y); }
  ctx.textAlign = 'center'; ctx.textBaseline = 'top';
  const km = xs[xs.length - 1] / 1000, stepKm = km > 40 ? 10 : km > 15 ? 5 : km > 6 ? 2 : km > 2 ? 1 : 0.5;
  for (let d = 0; d <= km + 1e-6; d += stepKm) ctx.fillText(fmtNum(d, stepKm < 1 ? 1 : 0), X(d * 1000), h - pb + 6);
  const path = new Path2D(); let first = true;
  xs.forEach((x, i) => { if (!isFinite(ys[i])) return; first ? path.moveTo(X(x), Y(ys[i])) : path.lineTo(X(x), Y(ys[i])); first = false; });
  if (fill) { const a = new Path2D(path); a.lineTo(X(xs[xs.length - 1]), h - pb); a.lineTo(X(xs[0]), h - pb); a.closePath(); ctx.fillStyle = css('--hover'); ctx.fill(a); }
  ctx.strokeStyle = css('--text'); ctx.lineWidth = 1.5; ctx.lineJoin = 'round'; ctx.stroke(path);
}
function drawCharts() {
  const { g, A } = cur, N = 300, xs = [], vs = [], es = [];
  for (let k = 0; k < N; k++) {
    const D = A.dist * k / (N - 1); let i = 0; let lo = 0, hi = g.n - 1;
    while (lo < hi) { const m = (lo + hi) >> 1; if (A.dd[m] < D) lo = m + 1; else hi = m; } i = lo;
    // 30 sn civarı ortalama hız
    let a = i, b = i; while (a > 0 && g.t[i] - g.t[a] < 15000) a--; while (b < g.n - 1 && g.t[b] - g.t[i] < 15000) b++;
    const mt = A.moving[b] - A.moving[a], v = mt > 2 ? (A.dd[b] - A.dd[a]) / mt : 0;
    xs.push(D); vs.push(A.pace ? (v > 0.5 ? 1000 / v / 60 : NaN) : v * 3.6); es.push(A.eleS ? A.eleS[i] : NaN);
  }
  if (A.pace) { const med = [...vs].filter(isFinite).sort((a, b) => a - b), cap = med[Math.floor(med.length * .95)] * 1.2; for (let i = 0; i < vs.length; i++) if (vs[i] > cap) vs[i] = NaN; }
  lineChart($('cSpd'), xs, vs, { invert: A.pace, fmtY: A.pace ? v => fmtPace(1000 / (v * 60)) : v => fmtNum(v), fill: !A.pace });
  if (g.hasEle) lineChart($('cEle'), xs, es, { fmtY: v => fmtNum(v) + ' m' });
}
function segButtons(el, items, get, set) {
  el.innerHTML = '';
  for (const [v, name] of Object.entries(items)) {
    const b = document.createElement('button'); b.textContent = name; b.className = get() === v ? 'on' : ''; b.type = 'button';
    b.onclick = () => { set(v); el.querySelectorAll('button').forEach(x => x.classList.toggle('on', x === b)); };
    el.appendChild(b);
  }
}
segButtons($('mapStyle'), Object.fromEntries(Object.entries(MAP_STYLES).map(([k, v]) => [k, v.name])), mapStyle, v => { prefs.map = v; savePrefs(); drawMap(); });
addEventListener('resize', () => { if (!$('vDetail').classList.contains('hidden')) { drawMap(); drawCharts(); } else if (!$('vEdit').classList.contains('hidden')) scheduleEd(); });

// fotoğrafları rotaya yerleştir
$('pinBtn').onclick = () => $('pinIn').click();
$('pinIn').onchange = async () => {
  const files = [...$('pinIn').files]; $('pinIn').value = ''; const { g } = cur; let out = 0;
  for (const f of files) {
    const t = (await photoTime(f)) ?? f.lastModified;
    if (t < g.start - 60000 || t > g.end + 60000) { out++; continue; }
    let lo = 0, hi = g.n - 1; while (lo < hi) { const m = (lo + hi) >> 1; if (g.t[m] < t) lo = m + 1; else hi = m; }
    cur.pins.push({ i: lo, t, name: f.name, file: f });
  }
  cur.pins.sort((a, b) => a.t - b.t);
  $('pinList').innerHTML = cur.pins.map(p => `<button type="button" class="on">${esc(fmtKm(cur.A.dd[p.i], 1))} km · ${new Date(p.t).toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' })}</button>`).join('');
  if (out) setMsg(`${out} fotoğraf bu aktivitenin saatleri dışında çekilmiş; rotaya eklenmedi.`, 'warn'); else setMsg('');
  drawMap();
};

// ---------- fotoğraf editörü ----------
const ed = {
  tpl: prefs.tpl || 'rota', fmt: prefs.fmt || '9:16', mapStyle: prefs.edMap || 'yok', color: prefs.color || 'turuncu',
  fields: prefs.fields || ['dist', 'time', 'pace'], hide: prefs.hide !== false, sign: prefs.sign !== false,
  photo: null, pan: { x: 0, y: 0, z: 1 }, pos: {}, scale: {}, sel: null, boxes: {},
};
function openEditor() {
  segButtons($('tpl'), TEMPLATES, () => ed.tpl, v => { ed.tpl = v; prefs.tpl = v; ed.pos = {}; ed.scale = {}; savePrefs(); scheduleEd(); });
  segButtons($('fmt'), { '9:16': '9:16 Hikâye', '4:5': '4:5 Gönderi', '1:1': '1:1 Kare', orij: 'Fotoğraf' }, () => ed.fmt, v => { ed.fmt = v; prefs.fmt = v; ed.pos = {}; savePrefs(); scheduleEd(); });
  segButtons($('edMap'), Object.fromEntries(Object.entries(MAP_STYLES).map(([k, v]) => [k, v.name])), () => ed.mapStyle, v => { ed.mapStyle = v; prefs.edMap = v; savePrefs(); scheduleEd(); });
  const cc = $('edColor'); cc.innerHTML = '';
  for (const [k, c] of Object.entries(ROUTE_COLORS)) {
    const b = document.createElement('button'); b.className = 'chip' + (ed.color === k ? ' on' : ''); b.style.background = c; b.setAttribute('aria-label', k); b.type = 'button';
    b.onclick = () => { ed.color = k; prefs.color = k; savePrefs(); cc.querySelectorAll('.chip').forEach(x => x.classList.toggle('on', x === b)); scheduleEd(); };
    cc.appendChild(b);
  }
  renderFields(); $('addPh').classList.toggle('hidden', !!ed.photo);
  $('hide').checked = ed.hide; $('sign').checked = ed.sign;
  $('edBack').href = '#' + cur.rec.id;
  scheduleEd();
}
function renderFields() {
  const el = $('fields'); el.innerHTML = '';
  for (const [k, name] of Object.entries(FIELDS)) {
    if (k === 'steps' && !(cur.A.steps > 0)) continue;
    const b = document.createElement('button'); b.type = 'button';
    b.textContent = k === 'pace' ? (cur.A.pace ? 'Tempo' : 'Ort. hız') : k === 'max' ? (cur.A.pace ? 'En iyi tempo' : 'Maks hız') : name;
    b.className = ed.fields.includes(k) ? 'on' : '';
    b.onclick = () => {
      if (ed.fields.includes(k)) ed.fields = ed.fields.filter(x => x !== k); else if (ed.fields.length < 4) ed.fields.push(k);
      prefs.fields = ed.fields; savePrefs(); renderFields(); scheduleEd();
    };
    el.appendChild(b);
  }
}
$('hide').onchange = () => { ed.hide = prefs.hide = $('hide').checked; savePrefs(); scheduleEd(); };
$('sign').onchange = () => { ed.sign = prefs.sign = $('sign').checked; savePrefs(); scheduleEd(); };
$('photoBtn').onclick = () => $('photoIn').click();
// Boş durumda yalnızca önizlemedeki büyük "Fotoğraf seç" görünsün; ikinci düğme tekrar olmasın
{ const sync = () => $('photoCard').classList.toggle('hidden', !$('addPh').classList.contains('hidden')); new MutationObserver(sync).observe($('addPh'), { attributes: true, attributeFilter: ['class'] }); sync(); }
$('addPhBtn').onclick = () => $('photoIn').click();
$('addPhSkip').onclick = () => $('addPh').classList.add('hidden');
$('photoIn').onchange = async () => {
  const f = $('photoIn').files[0]; $('photoIn').value = ''; if (!f) return;
  try { ed.photo = await createImageBitmap(f, { imageOrientation: 'from-image' }); }
  catch { setMsg('Bu fotoğraf açılamadı. JPEG veya PNG dene.'); return; }
  ed.pan = { x: 0, y: 0, z: 1 }; $('zoom').value = 100; $('zoomV').textContent = '%100';
  $('addPh').classList.add('hidden'); $('photoClr').classList.remove('hidden'); $('zoomRow').classList.remove('hidden'); $('photoBtn').querySelector('span').textContent = 'Fotoğrafı değiştir';
  if (ed.tpl === 'saydam') { ed.tpl = 'rota'; openEditor(); }
  scheduleEd();
};
$('photoClr').onclick = () => { ed.photo = null; $('addPh').classList.remove('hidden'); $('photoClr').classList.add('hidden'); $('zoomRow').classList.add('hidden'); $('photoBtn').querySelector('span').textContent = 'Fotoğraf seç'; scheduleEd(); };
$('zoom').oninput = () => { ed.pan.z = $('zoom').value / 100; $('zoomV').textContent = `%${$('zoom').value}`; scheduleEd(); };
$('scale').oninput = () => { const id = ed.sel || Object.keys(ed.boxes)[0]; if (!id) return; ed.scale[id] = $('scale').value / 100; $('scaleV').textContent = `%${$('scale').value}`; scheduleEd(); };

function edSize() {
  if (ed.fmt === 'orij' && ed.photo) { const k = Math.min(1, 2160 / Math.max(ed.photo.width, ed.photo.height)); return [Math.round(ed.photo.width * k), Math.round(ed.photo.height * k)]; }
  return FORMATS[ed.fmt] || FORMATS['9:16'];
}
let edRaf = 0;
function scheduleEd() { if (!edRaf) edRaf = requestAnimationFrame(() => { edRaf = 0; drawEd(); }); }
function edState(W, H) { return { ...ed, W, H, pos: ed.pos, scale: ed.scale }; }
function edData() { return { g: cur.g, A: cur.A, title: titleFor(cur.A.type, cur.g.start), subtitle: dateStr(cur.g.start), pins: cur.pins }; }
function drawEd() {
  if (!cur || $('vEdit').classList.contains('hidden')) return;
  const cv = $('ed'), [W, H] = edSize();
  // önizleme: ekrana sığan boyutta (hızlı), dışa aktarma tam boyutta
  const box = cv.parentElement.getBoundingClientRect(), maxH = innerWidth < 900 ? innerHeight * .42 : innerHeight * .7;
  const k = Math.min((box.width - 24) / W, maxH / H), d = Math.min(2, devicePixelRatio || 1);
  cv.style.width = Math.round(W * k) + 'px'; cv.style.height = Math.round(H * k) + 'px';
  cv.width = Math.round(W * k * d); cv.height = Math.round(H * k * d);
  const ctx = cv.getContext('2d'); ctx.setTransform(k * d, 0, 0, k * d, 0, 0);
  ed.boxes = compose(ctx, edState(W, H), edData());
  ed.view = { k, W, H };
  if (ed.sel && ed.boxes[ed.sel]) {
    const b = ed.boxes[ed.sel]; ctx.setLineDash([10, 8]); ctx.strokeStyle = 'rgba(255,255,255,.85)'; ctx.lineWidth = 2 / k; ctx.strokeRect(b.x, b.y, b.w, b.h); ctx.setLineDash([]);
  }
  const ids = Object.keys(ed.boxes); $('scaleRow').classList.toggle('hidden', !ids.length || ed.tpl === 'bant');
  $('expInfo').textContent = `${W}×${H} ${ed.tpl === 'saydam' ? 'PNG (saydam)' : 'JPEG'}`;
}
// sürükleme: blok taşı veya fotoğrafı kaydır
let drag = null;
$('ed').addEventListener('pointerdown', e => {
  if (!ed.view) return;
  const r = $('ed').getBoundingClientRect(), x = (e.clientX - r.left) / ed.view.k, y = (e.clientY - r.top) / ed.view.k;
  const hit = Object.entries(ed.boxes).reverse().find(([, b]) => x >= b.x && x <= b.x + b.w && y >= b.y && y <= b.y + b.h);
  if (hit && ed.tpl !== 'bant') {
    const [id, b] = hit; ed.sel = id; $('scale').value = Math.round((ed.scale[id] || 1) * 100); $('scaleV').textContent = `%${$('scale').value}`;
    drag = { id, dx: x - (b.x + b.w / 2), dy: y - (b.y + b.h / 2) };
  } else if (ed.photo) { drag = { pan: true, x0: e.clientX, y0: e.clientY, p0: { ...ed.pan } }; ed.sel = null; }
  else { ed.sel = null; }
  $('ed').setPointerCapture(e.pointerId); scheduleEd();
});
$('ed').addEventListener('pointermove', e => {
  if (!drag) return;
  const r = $('ed').getBoundingClientRect(), { W, H, k } = ed.view;
  if (drag.pan) {
    const p = ed.photo, z = ed.pan.z, sc = Math.max(W / p.width, H / p.height) * z, ex = (p.width * sc - W) / 2, ey = (p.height * sc - H) / 2;
    ed.pan.x = ex > 0 ? Math.max(-1, Math.min(1, drag.p0.x + (e.clientX - drag.x0) / k / ex)) : 0;
    ed.pan.y = ey > 0 ? Math.max(-1, Math.min(1, drag.p0.y + (e.clientY - drag.y0) / k / ey)) : 0;
  } else {
    const x = (e.clientX - r.left) / k - drag.dx, y = (e.clientY - r.top) / k - drag.dy;
    // ortaya mıknatıs
    let cx = x / W, cy = y / H; if (Math.abs(cx - .5) < .02) cx = .5;
    ed.pos[drag.id] = { cx: Math.max(0, Math.min(1, cx)), cy: Math.max(0, Math.min(1, cy)) };
  }
  scheduleEd();
});
['pointerup', 'pointercancel'].forEach(ev => $('ed').addEventListener(ev, () => { drag = null; }));

async function renderFull() {
  const [W, H] = edSize(), cv = new OffscreenCanvas(W, H), ctx = cv.getContext('2d');
  // haritalı şablonlarda döşemelerin yüklenmesini kısa süre bekle
  if (ed.mapStyle !== 'yok') {   // tam çözünürlükte gereken döşemeleri indir (iki tur: yakınlaştırma değişebilir)
    for (let i = 0; i < 2; i++) { compose(ctx, edState(W, H), edData()); await tilesIdle(); }
  }
  compose(ctx, edState(W, H), edData(), { fetchTiles: false });
  const png = ed.tpl === 'saydam';
  const blob = await cv.convertToBlob({ type: png ? 'image/png' : 'image/jpeg', quality: .92 });
  const d = new Date(cur.g.start), pad = n => String(n).padStart(2, '0');
  return new File([blob], `TelemetriGo_${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}_${ed.tpl}.${png ? 'png' : 'jpg'}`, { type: blob.type });
}
$('exp').onclick = async () => {
  const b = $('exp'); b.disabled = true;
  try {
    const f = await renderFull();
    if (navigator.canShare?.({ files: [f] })) await navigator.share({ files: [f] });
    else { const a = document.createElement('a'); a.href = URL.createObjectURL(f); a.download = f.name; a.click(); setTimeout(() => URL.revokeObjectURL(a.href), 4000); }
  } catch (e) { if (e.name !== 'AbortError') setMsg('Görsel oluşturulamadı: ' + esc(e.message)); }
  b.disabled = false;
};
$('expDl').onclick = async e => {
  e.preventDefault(); const f = await renderFull();
  const a = document.createElement('a'); a.href = URL.createObjectURL(f); a.download = f.name; a.click(); setTimeout(() => URL.revokeObjectURL(a.href), 4000);
};

// ---------- yönlendirme ----------
function show(v) { for (const id of ['vList', 'vDetail', 'vEdit']) $(id).classList.toggle('hidden', id !== v); scrollTo(0, 0); }
async function route() {
  const P = window.__TG_PENDING;
  if (P) { window.__TG_PENDING = null; try { await openPending(P); } catch (e) { setMsg('Aktivite açılamadı: ' + esc(e.message)); show('vList'); renderList(); } return; }
  let h = decodeURIComponent(location.hash.slice(1));
  if (h === 'son') { const id = await syncLast(); if (id) { location.replace('#' + id); return; } h = ''; }
  if (!h) { show('vList'); renderList(); return; }
  const [id, sub] = h.split('/');
  try { await openDetail(id, sub === 'foto'); } catch (e) { setMsg('Aktivite açılamadı: ' + esc(e.message)); show('vList'); renderList(); }
}
addEventListener('hashchange', route);
(isApp ? route() : syncLast().finally(route));
window.__act = { get cur() { return cur; }, ed, importGpx, compose };
