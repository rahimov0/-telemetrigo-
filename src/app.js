import {
  Input, Output, Conversion, BlobSource, BufferTarget, StreamTarget, Mp4OutputFormat,
  ALL_FORMATS, QUALITY_HIGH, canEncodeVideo,
} from './mediabunny.min.mjs';
import { readGoProTelemetry, emptyTelemetry, calibrateAt, applyCalibration } from './gpmf.js';
import { parseGpx, coverage, autoSync } from './gpx.js';
import { MAP_STYLES, onTile, prefetchRoute, tilesIdle, lastZoom } from './tiles.js';
import { cards, addCard, removeCard, rebuild, drawCards, importNative, setCardsListener, activityChoices, CARD_TPLS, SHAPES, TEXT_COLORS, ROUTE_COLORS as CARD_COLORS, MAP_STYLES as CARD_MAPS, titleFor, dateStr } from './cards.js';
import { tabButton } from './dockui.js';
import { drawOverlay, drawGaugeThumb, mergeOpts, applyPreset, PRESETS, ACCENTS, THEMES, GAUGES, gaugeAvailable, kindOf, gaugeFits, allowedStyles, styleFor, gaugeName } from './overlay.js';

const $ = id => document.getElementById(id);
const fileEl = $('file'), gpxEl = $('gpxFile'), video = $('video'), ov = $('ov'), msgEl = $('msg');
onTile(() => { if (typeof drawPreview === 'function') requestAnimationFrame(() => drawPreview()); });
const state = { file: null, tel: null, meta: null, info: null, url: null, conv: null, outFile: null, res: '1080',
  gps: null, gbase: 0, goff: 0, gpxName: '', sel: null, edit: false, rects: [] };

// ---- ayarlar (yerel olarak hatırlanır) ----
let saved = null; try { saved = JSON.parse(localStorage.getItem('tg-opts2') || 'null'); } catch {}
const opts = mergeOpts(saved);
const save = () => { try { localStorage.setItem('tg-opts2', JSON.stringify(opts)); } catch {} };
const data = () => ({ tel: state.tel, gps: state.gps, gbase: state.gbase, goff: state.goff });

function setMsg(html, kind = 'err') { msgEl.innerHTML = html ? `<div class="msg ${kind}">${html}</div>` : ''; }
const fmtSize = b => b > 1e9 ? (b / 1e9).toFixed(2).replace('.', ',') + ' GB' : (b / 1e6).toFixed(1).replace('.', ',') + ' MB';
const fmtDur = s => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, '0')}`;
const hhmm = ms => new Date(ms).toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit', second: '2-digit' });
const esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

// ---- genel ayarlar ----
function bindSettings() {
  document.querySelectorAll('[data-k]').forEach(el => {
    const k = el.dataset.k; el.value = opts[k];
    const upd = () => {
      opts[k] = Number(el.value);
      const v = $(k + 'V'); if (v) v.textContent = k === 'leanRange' ? `±${opts[k]}°` : `%${opts[k]}`;
      save(); drawPreview();
    };
    el.addEventListener('input', upd); upd();
  });
  const chips = $('chips');
  for (const [name, col] of Object.entries(ACCENTS)) {
    const b = document.createElement('button'); b.className = 'chip' + (opts.accent === name ? ' on' : '');
    b.style.background = col; b.title = name; b.setAttribute('aria-label', name);
    b.onclick = () => { opts.accent = name; save(); chips.querySelectorAll('.chip').forEach(c => c.classList.toggle('on', c === b)); drawPreview(); renderGaugeList(); };
    chips.appendChild(b);
  }
  seg($('theme'), THEMES, () => opts.theme, v => { opts.theme = v; save(); drawPreview(); renderGaugeList(); });
  $('res').querySelectorAll('button').forEach(b => b.onclick = () => {
    if (b.disabled) return; state.res = b.dataset.v; $('res').querySelectorAll('button').forEach(x => x.classList.toggle('on', x === b));
  });
}
function seg(el, items, get, set) {
  el.innerHTML = '';
  for (const [v, name] of Object.entries(items)) {
    const b = document.createElement('button'); b.textContent = name; b.className = get() === v ? 'on' : '';
    b.onclick = () => { set(v); el.querySelectorAll('button').forEach(x => x.classList.toggle('on', x === b)); };
    el.appendChild(b);
  }
}

// ---- gösterge listesi ve düzenleyici ----
function renderGaugeList() {
  const list = $('gauges'); list.innerHTML = '';
  const kind = kindOf(state.gps), ids = Object.keys(GAUGES).filter(id => gaugeFits(id, kind)), avail = id => !state.tel || gaugeAvailable(id, data());
  const row = id => {
    const G = GAUGES[id], ok = avail(id), r = document.createElement('div'), AS = allowedStyles(id, kind);
    r.className = 'grow-row' + (state.sel === id ? ' sel' : '') + (ok ? '' : ' na');
    const sub = !ok ? (G.needs === 'gps' ? 'GPX ekleyince açılır' : 'Bu videoda sensör verisi yok') : (G.styles ? (AS[styleFor(id, opts.g[id].style, kind)]) + ' · ' + Object.keys(AS).length + ' stil' : 'Boyut ve konum');
    r.innerHTML = `<button class="gname" aria-expanded="${state.sel === id}" ${ok ? '' : 'disabled'}><b>${gaugeName(id, kind)}</b><small>${sub}</small></button>
      <input type="checkbox" class="switch" ${opts.g[id].on && ok ? 'checked' : ''} ${ok ? '' : 'disabled'} aria-label="${G.name} göster">`;
    r.querySelector('input').onchange = e => { opts.g[id].on = e.target.checked; save(); if (e.target.checked) select(id); else drawPreview(); };
    r.querySelector('.gname').onclick = () => select(state.sel === id ? null : id);
    list.appendChild(r);
    if (state.sel === id && ok) list.appendChild(editorFor(id));
  };
  ids.filter(avail).forEach(row);
  const na = ids.filter(id => !avail(id));
  if (na.length) {
    const d = document.createElement('details'); d.className = 'na-group';
    d.innerHTML = `<summary>Bu videoda kullanılamayanlar (${na.length})</summary>`;
    list.appendChild(d); const keep = list; na.forEach(id => { row(id); d.appendChild(keep.lastChild); });
  }
}
function editorFor(id) {
  const G = GAUGES[id], g = opts.g[id], box = document.createElement('div'); box.className = 'geditor';
  const kind = kindOf(state.gps), AS = allowedStyles(id, kind), cur = G.styles ? styleFor(id, g.style, kind) : null, multi = AS && Object.keys(AS).length > 1;
  box.innerHTML = `${multi ? '<div class="styles" data-r="style" role="radiogroup" aria-label="Stil"></div>' : ''}
    ${id === 'map' ? '<div class="field-l" style="font-size:12.5px;color:var(--text-3);margin:var(--s3) 0 6px">Harita arka planı</div><div class="seg" data-r="tiles"></div>' : ''}
    <div class="slider"><label>Bu göstergenin boyutu <b class="num">%${g.scale}</b></label><input type="range" min="50" max="200" step="5" value="${g.scale}" aria-label="Gösterge boyutu"></div>
    <div class="row" style="margin-top:var(--s2)"><button class="btn sm grow" data-r="edit">Önizlemede taşı</button><button class="btn sm ghost" data-r="reset">Varsayılana dön</button></div>`;
  if (multi && state.tel) {
    const wrap = box.querySelector('[data-r=style]'), t = video.currentTime || 0;
    for (const [st, name] of Object.entries(AS)) {
      const b = document.createElement('button'); b.className = cur === st ? 'on' : '';
      b.setAttribute('role', 'radio'); b.setAttribute('aria-checked', b.className === 'on');
      const c = document.createElement('canvas'), dpr = window.devicePixelRatio || 1, W = 104;
      c.width = W * dpr * 2; c.height = W * dpr * 2;
      const ctx = c.getContext('2d');
      const h = drawGaugeThumb(ctx, id, st, c.width, t, data(), opts, state.meta);
      c.height = Math.ceil(h); drawGaugeThumb(c.getContext('2d'), id, st, c.width, t, data(), opts, state.meta);
      b.append(c); const sm = document.createElement('small'); sm.textContent = name; b.append(sm);
      b.onclick = () => { g.style = st; save(); drawPreview(); renderGaugeList(); };
      wrap.append(b);
    }
  }
  const tw = box.querySelector('[data-r=tiles]');
  if (tw) for (const [k, v] of Object.entries(MAP_STYLES)) {
    const b = document.createElement('button'); b.type = 'button'; b.textContent = v.name; b.className = (g.tiles || 'yok') === k ? 'on' : '';
    b.onclick = () => { g.tiles = k; save(); tw.querySelectorAll('button').forEach(x => x.classList.toggle('on', x === b)); drawPreview(); };
    tw.append(b);
  }
  const r = box.querySelector('input[type=range]');
  r.oninput = () => { g.scale = Number(r.value); r.previousElementSibling.querySelector('b').textContent = `%${g.scale}`; save(); drawPreview(); };
  box.querySelector('[data-r=reset]').onclick = () => { g.x = G.def.x; g.y = G.def.y; g.scale = 100; save(); renderGaugeList(); drawPreview(); };
  box.querySelector('[data-r=edit]').onclick = () => { setEdit(true); $('stage').scrollIntoView({ behavior: 'smooth', block: 'center' }); };
  return box;
}
function renderPresets() {
  const el = $('presets'); el.innerHTML = '';
  for (const [k, P] of Object.entries(PRESETS)) {
    const b = document.createElement('button'); b.className = 'btn sm'; b.textContent = P.name;
    b.onclick = () => { applyPreset(opts, k); save(); seg($('theme'), THEMES, () => opts.theme, v => { opts.theme = v; save(); drawPreview(); renderGaugeList(); }); renderGaugeList(); drawPreview(); };
    el.append(b);
  }
}
function select(id) { state.sel = id; renderGaugeList(); drawPreview(); }

// ---- önizleme ----
function drawPreview() {
  if (!state.tel) return;
  const w = video.clientWidth, h = video.clientHeight; if (!w || !h) return;
  const vw = state.info.width, vh = state.info.height;
  const sc = Math.min(w / vw, h / vh), dw = vw * sc, dh = vh * sc, dpr = window.devicePixelRatio || 1;
  ov.style.left = (w - dw) / 2 + 'px'; ov.style.top = (h - dh) / 2 + 'px'; ov.style.width = dw + 'px'; ov.style.height = dh + 'px';
  const cw = Math.round(dw * dpr), ch = Math.round(dh * dpr);
  if (ov.width !== cw || ov.height !== ch) { ov.width = cw; ov.height = ch; }
  const ctx = ov.getContext('2d'); ctx.clearRect(0, 0, cw, ch);
  state.rects = state.mode === 'card' ? [] : drawOverlay(ctx, cw, ch, video.currentTime || 0, data(), opts, state.meta, { highlight: state.sel, edit: state.edit });
  if (state.mode !== 'live') drawCards(ctx, cw, ch, video.currentTime || 0);
}
let raf = 0;
function loop() { drawPreview(); raf = video.paused ? 0 : requestAnimationFrame(loop); }
video.addEventListener('play', () => { if (state.edit) setEdit(false); if (!raf) raf = requestAnimationFrame(loop); });
['seeked', 'timeupdate', 'loadeddata', 'pause'].forEach(e => video.addEventListener(e, drawPreview));
window.addEventListener('resize', drawPreview);
video.addEventListener('error', () => setMsg('Bu tarayıcı videoyu önizlemede oynatamıyor (çoğunlukla H.265/HEVC desteği yüzünden). Dışa aktarmayı yine de deneyebilirsin.', 'warn'));

// ---- sürükle-bırak ----
function setEdit(on) {
  state.edit = on; $('stage').classList.toggle('editing', on);
  $('editBtn').classList.toggle('on', on); $('editBtn').querySelector('span').textContent = on ? 'Bitti' : 'Konumları düzenle';
  $('editHint').classList.toggle('hidden', !on);
  if (on) video.pause();
  drawPreview();
}
$('editBtn').onclick = () => setEdit(!state.edit);
let drag = null;
ov.addEventListener('pointerdown', e => {
  if (!state.edit) return;
  const k = ov.width / ov.clientWidth, px = e.offsetX * k, py = e.offsetY * k;
  const hit = [...state.rects].reverse().find(r => px >= r.x && px <= r.x + r.w && py >= r.y && py <= r.y + r.h);
  if (!hit) { select(null); return; }
  e.preventDefault(); ov.setPointerCapture(e.pointerId);
  drag = { id: hit.id, sx: px, sy: py, r: hit, k };
  if (state.sel !== hit.id) select(hit.id);
});
ov.addEventListener('pointermove', e => {
  if (!drag) return;
  const px = e.offsetX * drag.k, py = e.offsetY * drag.k, r = drag.r, W = ov.width, H = ov.height;
  const fx = W - 2 * r.m - r.w, fy = H - 2 * r.m - r.h, g = opts.g[drag.id];
  const snap = v => [0, 0.5, 1].reduce((a, s) => Math.abs(v - s) < 0.025 ? s : a, v);
  if (fx > 0) g.x = snap(Math.max(0, Math.min(1, (r.x + px - drag.sx - r.m) / fx)));
  if (fy > 0) g.y = snap(Math.max(0, Math.min(1, (r.y + py - drag.sy - r.m) / fy)));
  drawPreview();
});
const endDrag = () => { if (drag) { drag = null; save(); } };
ov.addEventListener('pointerup', endDrag); ov.addEventListener('pointercancel', endDrag);

// ---- dosya yükleme ----
fileEl.addEventListener('change', async () => { const f = fileEl.files[0]; if (!f) return; fileEl.value = ''; await loadFile(f); });
{ const dz = $('dropZone');
  if (dz) {
    ['dragenter', 'dragover'].forEach(ev => dz.addEventListener(ev, e => { e.preventDefault(); dz.classList.add('over'); }));
    ['dragleave', 'drop'].forEach(ev => dz.addEventListener(ev, () => dz.classList.remove('over')));
    dz.addEventListener('drop', e => { e.preventDefault(); const f = e.dataTransfer?.files?.[0]; if (f) loadFile(f); });
  } }

async function loadFile(f) {
  resetResult(); setMsg(`<span class="spinner"></span>Sensör verisi okunuyor…`, 'warn');
  try {
    let tel = await readGoProTelemetry(f);
    const input = new Input({ source: new BlobSource(f), formats: ALL_FORMATS });
    const vt = await input.getPrimaryVideoTrack();
    if (!vt) throw new Error('Videoda görüntü izi yok.');
    const stats = await vt.computePacketStats(120);
    const duration = await input.computeDuration();
    const canDecode = await vt.canDecode();
    const info = { width: vt.displayWidth, height: vt.displayHeight, fps: stats.averagePacketRate, duration, codec: vt.codec, canDecode };
    input.dispose?.();
    // Sensör verisi yoksa (DJI, telefon videosu ya da verisi silinmiş GoPro) sadece GPS göstergeleriyle devam
    const noImu = !tel.found;
    if (noImu) {
      const device = /^DJI_/i.test(f.name) ? 'DJI' : /^G[HXL]\d/i.test(f.name) ? 'GoPro' : 'Kamera';
      tel = { ...emptyTelemetry(duration), created: tel.created, device };
    }
    Object.assign(state, { file: f, tel, info, meta: { created: tel.created, device: tel.device, nameTime: nameTime(f.name) }, tzNote: 0 });
    if (state.gps) { state.gbase = gpsBase(); updateGpsUI(); }
    if (state.url) URL.revokeObjectURL(state.url);
    state.url = URL.createObjectURL(f); video.src = state.url;
    showInfo(); renderGaugeList();
    $('pickCard').classList.add('hidden'); $('recCard')?.classList.add('hidden'); $('work').classList.remove('hidden'); cards.length = 0; selCard = null; renderCards();
    setMsg(canDecode ? '' : 'Bu tarayıcı bu videonun formatını (' + (info.codec || '?') + ') çözemiyor; dışa aktarma çalışmayabilir. iPhone\'da Safari veya bilgisayarda güncel Chrome dene.', 'err');
    if (canDecode && noImu) setMsg('Bu videoda yatış/eğim sensör verisi yok' + (tel.device === 'GoPro' ? ' (WhatsApp vb. ile gönderilen GoPro videolarında silinir; orijinal dosyayı kullan)' : '') + '. <b>GPX ekleyerek hız, rota, pusula ve irtifa göstergeleri ekleyebilirsin.</b>', 'warn');
    else if (canDecode && !tel.hasAccel) setMsg('Bu videoda ivmeölçer verisi yok; G-kuvveti göstergesi gizlendi.', 'warn');
    drawPreview(); if (!applyLead()) autoLast();
  } catch (e) { console.error(e); setMsg('Video okunamadı: ' + esc(e.message || e)); }
}

function showInfo() {
  const { info, tel } = state;
  const sens = tel.hasImu === false ? 'Yok (yalnızca GPS)' : ['Yerçekimi', tel.hasAccel && 'İvme', tel.hasGyro && 'Jiroskop'].filter(Boolean).join(' · ');
  $('info').innerHTML = [
    [tel.device, 'Kamera'], [`${info.width}×${info.height}`, 'Çözünürlük'],
    [`${Math.round(info.fps)} fps`, 'Kare hızı'], [fmtDur(info.duration), 'Süre'], [sens, 'Sensörler'],
  ].map(([b, s]) => `<span>${s}: <b>${esc(b)}</b></span>`).join('');
  const imu = tel.hasImu !== false;
  for (const id of ['calBtn', 'calInfo']) $(id).classList.toggle('hidden', !imu);
  $('calClr').classList.add('hidden');
  const short = Math.min(info.width, info.height), origBtn = $('res').querySelector('[data-v="orig"]');
  if (short <= 1080) { origBtn.disabled = true; $('origLbl').textContent = 'video zaten 1080p'; $('res').querySelector('[data-v="1080"]').click(); }
  else { origBtn.disabled = false; $('origLbl').textContent = `${short >= 2160 ? '4K' : short + 'p'} · daha yavaş`; }
}

// ---- GPX ----
const isApp = /TelemetriGoApp/.test(navigator.userAgent);
// Zaman tabanı: GoPro bu GPS kaydı sırasında uygulamadan başlatıldıysa o an (en hassas), yoksa kameranın saati
// Dosya adındaki çekim saati (DJI_20261123085241_0001_D.MP4, VID_20261123_085241...): kameranın yerel saati, saniyesine kadar
function nameTime(name) {
  const m = /(20\d\d)(\d\d)(\d\d)[_\-T ]?(\d\d)(\d\d)(\d\d)/.exec(name || ''); if (!m) return null;
  const d = new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]);
  return !isNaN(d) && d.getMonth() === +m[2] - 1 && +m[4] < 24 && +m[5] < 60 && +m[6] < 60 ? d : null;
}
// Videonun başlangıç saatini bul: 1) GoPro uygulamasından başlatıldıysa kesin kayıt işareti 2) dosya adındaki saat 3) dosya bilgisindeki saat.
// Kamera saati yerel yazılmış olabilir: örtüşme yoksa tam/yarım saatlik farkları dener.
function gpsBase(g = state.gps) {
  const created = state.meta?.created?.getTime(), nt = state.meta?.nameTime?.getTime();
  state.tzFix = 0; state.srcName = '';
  if (!created && !nt) { state.syncSrc = 'gpx'; return g.start; }
  state.syncSrc = 'saat';
  const cs = (g.camStarts || []).map(t => [Math.abs(t - (nt || created)), t]).sort((a, b) => a[0] - b[0])[0];
  if (cs && cs[0] < 10000) { state.syncSrc = 'kamera'; return cs[1]; }
  const dur = state.info?.duration || 60, cands = [nt && ['dosya adı', nt], created && ['dosya bilgisi', created]].filter(Boolean);
  const shifts = [0, 3, -3, 1, -1, 2, -2, 4, -4, 5, -5, 6, -6, 7, -7, 8, -8, 9, -9, 10, -10, 11, -11, 12, -12, 3.5, 4.5, 5.5, 5.75, 6.5, 9.5, -3.5, 13, 14];
  for (const [label, t] of cands) for (const h of shifts)
    if (coverage(g, t - h * 3600000, 0, dur) > 0.5) { state.tzFix = h; state.srcName = label; return t - h * 3600000; }
  state.srcName = cands[0][0]; return cands[0][1];
}
$('gpxBtn').onclick = () => gpxEl.click();
gpxEl.addEventListener('change', async () => {
  const f = gpxEl.files[0]; if (!f) return; gpxEl.value = '';
  useGpx(await f.text(), f.name);
});
let last = null; try { last = JSON.parse(localStorage.getItem('tg-last-gpx') || 'null'); } catch {}
function showLast() {
  if (!last?.gpx) return;
  const b = $('lastGpx'); b.classList.remove('hidden');
  b.textContent = `Son GPS kaydını kullan (${new Date(last.start).toLocaleString('tr-TR', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })})`;
  b.onclick = () => useGpx(last.gpx, last.name);
}
showLast();
// Video seçilince: son GPS kaydı bu videonun zamanını kapsıyorsa kendiliğinden ekle
// Uygulamada bir aktivitenin içinden "Videoya ekle" denildiyse: o aktivitenin verisi eşleşme aranmadan kullanılır
function applyLead() {
  if (!isApp || !window.__TG_LEAD || state.gps) return false;
  const a = (window.__TG_ACTS || [])[0]; if (!a?.gpx) return false;
  useGpx(a.gpx, a.name); syncActSel(0);
  setMsg(`<b>${esc(a.name)}</b> verisi eklendi. Videoyla zamanı tutmuyorsa Hizalama sekmesinden ayarlayabilirsin.`, 'ok');
  return true;
}
function syncActSel(i) { const sel = $('actSel'); if (sel) sel.value = String(i); }
function buildActPick() {
  const L = window.__TG_ACTS; if (!isApp || !Array.isArray(L) || !L.length) return;
  const sel = $('actSel'); $('actPick').classList.remove('hidden');
  const when = g => { const m = (g.match(/<time>([^<]+)<\/time>/) || [])[1], d = m && new Date(m); return d && !isNaN(d) ? d.toLocaleString('tr-TR', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }) : ''; };
  sel.innerHTML = '<option value="-1">Aktivite seç…</option>' + L.map((a, i) => `<option value="${i}">${esc(a.name)} · ${esc(when(a.gpx))}</option>`).join('');
  sel.value = '-1';
  sel.onchange = () => { const a = L[+sel.value]; if (a && state.info) useGpx(a.gpx, a.name); };
}
function autoLast() {
  if (state.gps || !state.info) return;
  // uygulamada: son aktivitelerden videonun zamanına denk geleni bul; yoksa son GPS kaydına bak
  const cands = [...(isApp ? (window.__TG_ACTS || []) : []), ...(last?.gpx ? [last] : [])];
  let best = null;
  for (const c of cands) {
    try { const g = parseGpx(c.gpx), cv = coverage(g, gpsBase(g), 0, state.info.duration); if (cv > 0.3 && (!best || cv > best.cv)) best = { c, cv }; } catch {}
  }
  if (best) { useGpx(best.c.gpx, best.c.name); const i = (window.__TG_ACTS || []).indexOf(best.c); if (i >= 0) syncActSel(i); setMsg('Bu videonun zamanına denk gelen GPS kaydı otomatik eklendi.', 'ok'); }
}
// iOS uygulaması GPX'i buraya verir
window.TelemetriGo = {
  receiveGpx({ name, gpx }) {
    try {
      const g = parseGpx(gpx);
      last = { name, gpx, start: g.start, end: g.end, saved: Date.now() };
      try { localStorage.setItem('tg-last-gpx', JSON.stringify(last)); } catch {}
      showLast();
      if (state.info) useGpx(gpx, name);
      else setMsg('GPS kaydı hazır. Şimdi aynı sürüşün GoPro videosunu seç; kayıt videoya otomatik eklenecek.', 'ok');
    } catch (e) { setMsg('GPS kaydı okunamadı: ' + esc(e.message || e)); }
  },
};
function useGpx(text, name) {
  try {
    const g = parseGpx(text);
    state.gps = g; state.gpxName = name; state.goff = 0; state.gbase = gpsBase(); state.syncMode = null; state.syncScore = 0;
    try { for (const k of Object.keys(localStorage)) if (k.startsWith('tg-off-')) localStorage.removeItem(k); } catch {}   // eski sürümlerin "hatırlanan kaydırma"sı yanlış eşleşme yapıyordu
    if (state.syncSrc === 'saat' && state.meta) {   // saat göstergesi de eşleşen saati göstersin
      state.meta.created = new Date(state.gbase); state.tzNote = state.tzFix; state.tzFix = 0;
    }
    for (const id of ['speed', 'map', 'compass']) if (!saved?.g?.[id]) opts.g[id].on = true;
    updateGpsUI(); renderGaugeList(); drawPreview();
    const cov = coverage(g, state.gbase, 0, state.info.duration);
    const gd = (g.end - g.start) / 1000;
    if (state.tel?.hasAccel && state.syncSrc !== 'kamera' && (cov < 0.95 || gd > state.info.duration * 1.5)) runAutoSync(false);
  } catch (e) { setMsg('GPX okunamadı: ' + esc(e.message || e)); }
}
function updateGpsUI() {
  const g = state.gps, has = !!g;
  $('gpxBtn').textContent = has ? 'Başka GPX seç' : 'GPX dosyası ekle';
  $('gpsBox').classList.toggle('hidden', !has); $('gpxRemove').classList.toggle('hidden', !has);
  if (!has) return;
  const cov = state.info ? coverage(g, state.gbase, state.goff, state.info.duration) : 0;
  const durMin = Math.round((g.end - g.start) / 60000);
  $('gpsInfo').innerHTML = `<b>${esc(state.gpxName)}</b><br>${g.n} nokta · ${(g.total / 1000).toFixed(1).replace('.', ',')} km · ${durMin} dk · ${hhmm(g.start)}–${hhmm(g.end)}`
    + `<br>Hız verisi: ${g.unit === 'konum' ? 'konumdan hesaplandı' : 'GPX içinden (' + g.unit + ')'} · Maks ${Math.round(g.vMax * 3.6)} km/h`
    + `<br>Zamanlama: ${state.syncSrc === 'kamera' ? '<b>GoPro kayıt başlangıcıyla eşleşti</b> (uygulamadan başlatıldı)' : state.syncSrc === 'saat' ? 'kameranın saatine göre' + (state.tzNote ? ` (kamera saati ${Math.abs(state.tzNote)} saat ${state.tzNote > 0 ? 'ileri' : 'geri'} yazılmış, düzeltildi)` : '') : 'GPX başlangıcına göre (videoda saat bilgisi yok; kaydırmayı elle ayarla)'}`
    + (g.stillCount || g.dropped ? `<br>Temizlik: ${g.stillCount ? g.stillCount + ' duruş noktasındaki GPS kayması sıfırlandı' : ''}${g.stillCount && g.dropped ? ', ' : ''}${g.dropped ? g.dropped + ' hatalı nokta atıldı' : ''}` : '');
  const vStart = state.gbase - state.goff * 1000;
  const gdur = (g.end - g.start) / 1000, vdur = state.info?.duration || 0;
  const conf = state.syncMode === 'elle' ? ['ok', 'Elle ayarlandı']
    : state.syncMode === 'oto' ? [state.syncScore >= 0.6 ? 'ok' : 'warn', `Otomatik eşitlendi (uyum %${Math.round((state.syncScore || 0) * 100)})`]
    : state.syncSrc === 'kamera' ? ['ok', 'Kesin (kamera uygulamadan başlatıldı)']
    : state.syncSrc === 'saat' ? ['warn', 'Tahmini (dosyanın saatine göre)'] : ['err', 'Belirsiz (videoda saat bilgisi yok)'];
  const cut = vdur > 0 && gdur > vdur * 1.5 && !state.syncMode && state.syncSrc !== 'kamera';
  $('gpsInfo').innerHTML += `<br>Eşleşme güveni: <b>${conf[1]}</b>`;
  const status = cut ? ['warn', 'GPX videonun tamamını kapsıyor ama video GPX\'ten çok daha kısa; video kesilmiş olabilir ve başlangıç saati güvenilmez. Önizlemede hızı kontrol et; yanlışsa "Otomatik eşitle" ya da "Oynatılan kareyi GPX anına oturt"u kullan.']
    : cov >= 0.95 ? ['ok', 'GPX bu videonun tamamını kapsıyor.']
    : cov > 0 ? ['warn', `GPX videonun %${Math.round(cov * 100)}'ini kapsıyor; kalan kısımda GPS göstergeleri "—" gösterir.`]
    : ['err', `GPX bu videonun zamanıyla örtüşmüyor. Video ${hhmm(vStart)}'de başlıyor, GPX ${hhmm(g.start)}–${hhmm(g.end)} arası. Doğru GPX'i seçtiğinden emin ol ya da "Otomatik eşitle"yi dene.`];
  if (g.total < 20) status[0] = 'err', status[1] = `Bu GPS kaydında neredeyse hiç hareket yok (${Math.round(g.total)} m). Telefon kayıt sırasında gerçek GPS almamış olabilir (kapalı alan ya da "Kesin Konum" kapalı). ` + (cov > 0 ? 'Hız 0 ve rota tek nokta görünecek.' : status[1]);
  $('gpsCov').className = 'msg ' + status[0]; $('gpsCov').textContent = status[1];
  // sade durum satırı
  const srcTxt = state.srcName === 'dosya adı' ? 'dosya adındaki saat' : 'dosya bilgisindeki saat';
  const al = state.syncMode === 'elle' ? ['ok', 'Eşleşti. Elle ayarladın.']
    : state.syncMode === 'oto' ? [state.syncScore >= 0.6 ? 'ok' : 'warn', state.syncScore >= 0.6 ? 'Eşleşti. Sensör verisiyle otomatik eşitlendi.' : 'Sensörle eşitlendi ama uyum düşük. Önizlemede kontrol et.']
    : state.syncSrc === 'kamera' ? ['ok', 'Eşleşti. GoPro kaydı uygulamadan başlatıldı, zaman kesin.']
    : state.syncSrc === 'gpx' ? ['warn', 'Videoda saat bilgisi yok. GPS kaydı videonun başına konuldu; saat damgası görüyorsan aşağıya yaz.']
    : cov >= 0.95 ? ['ok', `Eşleşti. Videonun ${srcTxt} ile GPS saati örtüşüyor.`]
    : cov > 0 ? ['warn', `Kısmen eşleşti: GPS videonun %${Math.round(cov * 100)}'ini kapsıyor.`]
    : ['err', 'Videonun saati GPS kaydıyla örtüşmüyor. Videoda saat damgası görüyorsan aşağıya yaz.'];
  $('alStatus').className = 'msg ' + al[0]; $('alStatus').textContent = al[1];
  $('alInfo').textContent = `Video ${hhmm(vStart)} ile başlıyor · GPS kaydı ${hhmm(g.start)}–${hhmm(g.end)}`;
  updAlNow();
  const lim = Math.max(60, Math.ceil((Math.abs(state.goff) + 60) / 60) * 60);
  $('off').min = -lim; $('off').max = lim;
  $('gAt').max = Math.max(1, Math.floor(gdur)); syncGpsPos();
  $('off').value = state.goff; $('offV').textContent = `${state.goff > 0 ? '+' : ''}${state.goff.toFixed(1).replace('.', ',')} sn`;
}
function updAlNow() {
  const el = $('alNow'); if (!el) return;
  if (!state.gps || !state.info) { el.textContent = ''; return; }
  const T = state.gbase + ((video.currentTime || 0) - state.goff) * 1000, ok = T >= state.gps.start - 1500 && T <= state.gps.end + 1500;
  el.textContent = ok ? `Bu karede GPS'e göre saat: ${hhmm(T)}. Videodaki damgayla aynı değilse, damgadaki saati yazıp eşitle.` : 'Bu kare GPS kaydının dışında kalıyor.';
}
['seeked', 'timeupdate', 'loadedmetadata'].forEach(ev => video.addEventListener(ev, updAlNow));
$('clkSet').onclick = () => {
  const g = state.gps, v = $('clkIn').value; if (!g || !v) { $('clkMsg').textContent = 'Önce videodaki saati yaz.'; return; }
  const [h, m, sec] = v.split(':').map(Number), d = new Date(g.start);
  let T = new Date(d.getFullYear(), d.getMonth(), d.getDate(), h, m, sec || 0).getTime();
  if (T < g.start - 12 * 3600000) T += 86400000; else if (T > g.end + 12 * 3600000) T -= 86400000;
  if (T < g.start - 1500 || T > g.end + 1500) { $('clkMsg').textContent = `Bu saat GPS kaydının (${hhmm(g.start)}–${hhmm(g.end)}) dışında. Doğru aktiviteyi seçtiğinden emin ol.`; return; }
  const sc = (T - g.start) / 1000, tv = video.currentTime || 0;
  setOffset(tv - sc - (g.start - state.gbase) / 1000);
  $('clkMsg').textContent = `Eşitlendi: bu karede saat ${hhmm(T)}.`;
};
function setOffset(v, remember = true) {
  state.goff = Math.round(Math.max(-7200, Math.min(7200, v)) * 10) / 10;
  state.syncMode = remember ? 'elle' : 'oto';
  updateGpsUI(); drawPreview();
}
// Videonun o anki karesi GPX'in kaçıncı saniyesine denk geliyor (ve tersi)
function gpxSecAtVideo(tv) { return tv - (state.gps.start - state.gbase) / 1000 - state.goff; }
function speedAt(T) {
  const g = state.gps; let lo = 0, hi = g.n - 1;
  while (hi - lo > 1) { const m = (lo + hi) >> 1; if (g.t[m] <= T) lo = m; else hi = m; }
  return g.spd[lo] * 3.6;
}
function showGAt(sc) {
  const g = state.gps; if (!g) return;
  const T = g.start + sc * 1000;
  $('gAtV').textContent = `${Math.floor(sc / 60)}:${String(Math.floor(sc % 60)).padStart(2, '0')}`;
  $('gAtInfo').textContent = `GPX saati ${hhmm(T)} · hız ${Math.round(speedAt(T))} km/h`;
}
function syncGpsPos() {
  if (!state.gps || !state.info) return;
  const gdur = (state.gps.end - state.gps.start) / 1000;
  const sc = Math.max(0, Math.min(gdur, gpxSecAtVideo(video.currentTime || 0)));
  $('gAt').value = sc; showGAt(sc);
}
video.addEventListener('seeked', syncGpsPos);
$('gAt').oninput = e => showGAt(Number(e.target.value));
$('gSet').onclick = () => {
  if (!state.gps) return;
  const sc = Number($('gAt').value), tv = video.currentTime || 0;
  setOffset(tv - sc - (state.gps.start - state.gbase) / 1000);
  $('syncMsg').textContent = `Eşleştirildi: videonun ${Math.floor(tv / 60)}:${String(Math.floor(tv % 60)).padStart(2, '0')}. saniyesi = GPX'in ${Math.floor(sc / 60)}:${String(Math.floor(sc % 60)).padStart(2, '0')}. saniyesi.`;
};
$('off').oninput = e => setOffset(Number(e.target.value));
document.querySelectorAll('[data-off]').forEach(b => b.onclick = () => setOffset(state.goff + Number(b.dataset.off)));
$('gpxRemove').onclick = () => { state.gps = null; updateGpsUI(); renderGaugeList(); drawPreview(); $('syncMsg').textContent = ''; };
$('autoSync').onclick = () => runAutoSync(false);
$('gReset').onclick = () => { state.syncMode = null; state.syncScore = 0; setOffset(0, false); state.syncMode = null; updateGpsUI(); $('syncMsg').textContent = 'Kaydırma sıfırlandı (dosyanın saatine göre).'; };
function runAutoSync(silent) {
  if (!state.gps || !state.tel?.hasAccel) { if (!silent) $('syncMsg').textContent = 'Bu videoda ivme verisi yok (yalnızca GoPro sensör verisi okunabilir). Kareyi GPX anına oturtarak elle eşleştir.'; return; }
  const gdur = (state.gps.end - state.gps.start) / 1000;
  const R = Math.min(3600, Math.max(300, gdur));          // kesilmiş videoda GPX'in tamamı taranır
  const coarse = autoSync(state.gps, state.gbase, state.tel, { range: R, step: 0.5 });
  let r = coarse;
  if (coarse) {
    const c = coarse.offset, fine = autoSync(state.gps, state.gbase - c * 1000, state.tel, { range: 1.5, step: 0.1 });
    if (fine && fine.score >= coarse.score - 0.02) r = { offset: Math.round((fine.offset + c) * 10) / 10, score: fine.score, overlap: fine.overlap };
  }
  const el = $('syncMsg');
  const minScore = R > 300 ? 0.55 : 0.3;      // geniş taramada yanlış eşleşme olasılığı yüksek: daha sıkı eşik
  if (!r || r.score < minScore) {
    el.textContent = silent ? '' : 'Otomatik eşitleme güvenilir bir sonuç bulamadı (video kısa olabilir, hız fazla değişmemiş olabilir ya da kamera kaskta olabilir). Videoda bir fren/kalkış anına gel, "Videonun şu karesi GPX\'te" kaydırıcısıyla aynı anı seç ve "Oynatılan kareyi bu GPX anına oturt"a bas.';
    return;
  }
  state.syncScore = r.score;
  setOffset(r.offset, false);
  el.textContent = `Eşitlendi: ${r.offset > 0 ? '+' : ''}${r.offset.toFixed(1).replace('.', ',')} sn · uyum %${Math.round(r.score * 100)}${r.score < 0.6 ? ' (düşük; önizlemede kontrol et)' : ''}`;
}

// ---- dışa aktarma ----
function outSize() {
  const { width: w, height: h } = state.info;
  if (state.res === 'orig') return [w & ~1, h & ~1];
  const short = Math.min(w, h); if (short <= 1080) return [w & ~1, h & ~1];
  const k = 1080 / short; return [Math.round(w * k / 2) * 2, Math.round(h * k / 2) * 2];
}
async function makeTarget(name) {
  try {
    const root = await navigator.storage.getDirectory();
    try { await root.removeEntry(name); } catch {}
    const fh = await root.getFileHandle(name, { create: true });
    if (!fh.createWritable) throw 0;
    const w = await fh.createWritable();
    return { target: new StreamTarget(w, { chunked: true }), format: new Mp4OutputFormat({ fastStart: false }), get: () => fh.getFile() };
  } catch {
    const target = new BufferTarget();
    return { target, format: new Mp4OutputFormat({ fastStart: 'in-memory' }), get: async () => new Blob([target.buffer], { type: 'video/mp4' }) };
  }
}
let wakeLock = null;
async function keepAwake(on) {
  try {
    if (on && 'wakeLock' in navigator) wakeLock = await navigator.wakeLock.request('screen');
    else if (!on && wakeLock) { await wakeLock.release(); wakeLock = null; }
  } catch {}
}

$('go').onclick = async () => {
  const { file, meta } = state; if (!file) return;
  resetResult(); setMsg(''); if (state.edit) setEdit(false);
  const [W, H] = outSize(), D = data(), O = JSON.parse(JSON.stringify(opts));
  const base = file.name.replace(/\.[^.]+$/, '');
  const outName = `${base}_telemetri_${state.res === 'orig' ? (H >= 2160 ? '4K' : H + 'p') : '1080p'}.mp4`;
  $('go').disabled = true; $('prog').classList.remove('hidden'); $('barI').style.width = '0%'; $('progT').textContent = 'Hazırlanıyor…';
  video.pause(); await keepAwake(true);
  const t0 = performance.now();
  try {
    // haritalı rota: gereken döşemeleri önceden indir (dışa aktarma sırasında eksik kalmasın)
    const ts = O.g.map?.tiles;
    if (D.gps && O.g.map?.on && ts && ts !== 'yok') {
      $('progT').textContent = 'Harita indiriliyor…';
      const oc = new OffscreenCanvas(W, H), octx = oc.getContext('2d'), dur = video.duration || 1;
      const zs = new Set();
      for (const f of [0.05, 0.5, 0.95]) { drawOverlay(octx, W, H, dur * f, D, O, meta); if (lastZoom) zs.add(lastZoom); }
      await tilesIdle(6000);
      const Rm = Math.max(150, Math.min(1500, D.gps.total / 5));
      await prefetchRoute(ts, D.gps, [...zs], Rm * 1.6, f => { $('progT').textContent = `Harita indiriliyor… %${Math.round(f * 100)}`; });
    }
    let codec = 'avc';
    if (!(await canEncodeVideo('avc', { width: W, height: H }))) {
      if (await canEncodeVideo('hevc', { width: W, height: H })) codec = 'hevc';
      else throw new Error(`Bu cihaz ${W}×${H} video kodlayamıyor. 1080p seçeneğini dene.`);
    }
    const out = await makeTarget(outName);
    const input = new Input({ source: new BlobSource(file), formats: ALL_FORMATS });
    const output = new Output({ format: out.format, target: out.target });
    const canvas = typeof OffscreenCanvas !== 'undefined' ? new OffscreenCanvas(W, H) : Object.assign(document.createElement('canvas'), { width: W, height: H });
    const ctx = canvas.getContext('2d');
    const conv = await Conversion.init({
      input, output,
      video: {
        width: W, height: H, fit: 'fill', codec, bitrate: QUALITY_HIGH, forceTranscode: true, processedWidth: W, processedHeight: H,
        process: sample => { sample.draw(ctx, 0, 0, W, H); if (state.mode !== 'card') drawOverlay(ctx, W, H, sample.timestamp, D, O, meta); if (state.mode !== 'live') drawCards(ctx, W, H, sample.timestamp); return canvas; },
      },
    });
    if (!conv.isValid) throw new Error('Dönüştürme başlatılamadı: ' + conv.discardedTracks.map(d => `${d.track.type}: ${d.reason}`).join(', '));
    state.conv = conv;
    conv.onProgress = p => {
      $('barI').style.width = (p * 100).toFixed(1) + '%';
      const el = (performance.now() - t0) / 1000, eta = p > 0.02 ? el / p - el : 0;
      $('progT').textContent = `%${Math.floor(p * 100)}` + (eta ? ` · yaklaşık ${eta > 90 ? Math.ceil(eta / 60) + ' dk' : Math.ceil(eta) + ' sn'} kaldı` : '');
    };
    await conv.execute();
    const blob = await out.get();
    state.outFile = new File([blob], outName, { type: 'video/mp4' });
    const secs = ((performance.now() - t0) / 1000).toFixed(0);
    $('doneT').innerHTML = `<b>Hazır!</b> ${esc(outName)} · ${W}×${H} · ${fmtSize(state.outFile.size)} · ${secs} sn sürdü`;
    $('dl').href = URL.createObjectURL(state.outFile); $('dl').download = outName;
    $('done').classList.remove('hidden');
  } catch (e) {
    if (e?.name === 'ConversionCanceledError' || /cancel/i.test(e?.message || '')) setMsg('İşlem iptal edildi.', 'warn');
    else { console.error(e); setMsg('Video oluşturulamadı: ' + esc(e.message || e)); }
  } finally {
    state.conv = null; $('go').disabled = false; $('prog').classList.add('hidden'); keepAwake(false);
  }
};
$('cancel').onclick = () => state.conv?.cancel();
$('share').onclick = async () => {
  const f = state.outFile; if (!f) return;
  if (isApp) { $('dl').click(); return; }   // uygulama indirmeyi yakalayıp paylaşım ekranını açar
  try { if (navigator.canShare?.({ files: [f] })) await navigator.share({ files: [f], title: f.name }); else $('dl').click(); }
  catch (e) { if (e.name !== 'AbortError') $('dl').click(); }
};
function resetResult() {
  $('done').classList.add('hidden');
  if ($('dl').href.startsWith('blob:')) URL.revokeObjectURL($('dl').href);
  state.outFile = null;
}
$('again').onclick = () => fileEl.click();
document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible' && state.conv) keepAwake(true); });

if (isApp) { document.documentElement.classList.add('inapp'); $('recCard').remove(); document.querySelector('#gpsRecLink')?.remove(); document.querySelector('footer')?.remove(); }
// ---- açı kalibrasyonu: motorun dik durduğu an ----
$('calBtn').onclick = () => {
  if (!state.tel?.raw) return;
  const t = video.currentTime || 0; calibrateAt(state.tel, t);
  $('calClr').classList.remove('hidden');
  $('calInfo').innerHTML = `Yatış ve eğim, videonun <b>${t.toFixed(1).replace('.', ',')}. saniyesindeki</b> duruşa göre sıfırlandı. Yanlış anı seçtiysen başka bir ana gidip tekrar bas.`;
  drawPreview(); renderGaugeList();
};
$('calClr').onclick = () => {
  if (!state.tel?.raw) return; applyCalibration(state.tel, null); $('calClr').classList.add('hidden');
  $('calInfo').innerHTML = 'Sıfırlama kaldırıldı; açılar kameranın kendi eksenine göre.'; drawPreview(); renderGaugeList();
};
$('goMobile').onclick = () => { $('exportCard').scrollIntoView({ behavior: 'smooth', block: 'center' }); if (!$('go').disabled) $('go').click(); };
new MutationObserver(() => $('gobar').classList.toggle('hidden', $('work').classList.contains('hidden'))).observe($('work'), { attributes: true });

bindSettings(); renderPresets(); renderGaugeList(); updateGpsUI();
window.__tg = { state, opts, cards, loadFile, setEdit, select, setOffset, // test için
  snap: (W = 1920, H = 1080) => { const c = document.createElement('canvas'); c.width = W; c.height = H; const x = c.getContext('2d');
    x.drawImage(video, 0, 0, W, H); if (state.mode !== 'card') drawOverlay(x, W, H, video.currentTime, data(), opts, state.meta); if (state.mode !== 'live') drawCards(x, W, H, video.currentTime); return c.toDataURL('image/jpeg', 0.85); } };
if (new URLSearchParams(location.search).get('gpx') === 'son' && last?.gpx) setMsg(`Aktivitenin GPS kaydı hazır (<b>${esc(last.name || 'GPX')}</b>). Şimdi o sırada çektiğin videoyu seç; zamanı eşleşirse otomatik eklenir.`, 'ok');

// ---- aktivite kartı paneli ----
let selCard = null;
const Q = new URLSearchParams(location.search);
state.mode = isApp ? (Q.get('mode') === 'card' ? 'card' : 'live') : null;   // uygulamada: canlı veri YA DA kart
setCardsListener(c => { if (c && c === selCard) { const b = $('cardBusy'); if (b) b.textContent = c.busy ? 'Hazırlanıyor…' : c.err || ''; } drawPreview(); });
video.addEventListener('seeked', () => drawPreview());
const movePlayhead = () => { const d = video.duration || 1; document.querySelectorAll('.tlPlay').forEach(p => { p.style.left = (video.currentTime / d * 100) + '%'; }); };
['timeupdate', 'seeked', 'loadedmetadata'].forEach(ev => video.addEventListener(ev, movePlayhead));
function slider(label, min, max, step, val, fmt, on) {
  const w = document.createElement('div'); w.className = 'slider';
  w.innerHTML = `<label>${label} <b class="num"></b></label><input type="range" min="${min}" max="${max}" step="${step}">`;
  const inp = w.querySelector('input'), out = w.querySelector('b'); inp.value = val; out.textContent = fmt(+val);
  inp.oninput = () => { out.textContent = fmt(+inp.value); on(+inp.value); };
  return w;
}
function field(label, el) { const d = document.createElement('div'); d.className = 'fld'; d.innerHTML = `<div class="field-l">${label}</div>`; d.append(el); return d; }
function showAt(c) { video.pause(); video.currentTime = Math.min(Math.max(0, (video.duration || 0) - .05), c.t0 + Math.min(.8, c.dur / 2)); }
const tfmt = t => `${Math.floor(t / 60)}:${String(Math.floor(t % 60)).padStart(2, '0')}${t % 1 ? ',' + Math.round(t % 1 * 10) : ''}`;
/** Zaman çizelgesi: kartın hangi saniyede başlayıp ne kadar kalacağı. Gövdeyi sürükle = kaydır, kenarları sürükle = süreyi ayarla. */
function timeline(c, dur) {
  const w = document.createElement('div'); w.className = 'tl';
  w.innerHTML = '<div class="tlTrack"><div class="tlSeg"><i class="tlH l"></i><i class="tlH r"></i></div><div class="tlPlay"></div></div><div class="tlRead"></div><div class="tlAxis"><span>0:00</span><span></span></div>';
  const track = w.querySelector('.tlTrack'), seg = w.querySelector('.tlSeg'), read = w.querySelector('.tlRead');
  w.querySelector('.tlAxis span:last-child').textContent = tfmt(dur);
  const clamp = (v, a, b) => Math.min(b, Math.max(a, v)), snap = v => Math.round(v * 2) / 2;
  const draw = () => { seg.style.left = c.t0 / dur * 100 + '%'; seg.style.width = c.dur / dur * 100 + '%'; read.innerHTML = `<span><small>Başlar</small><b>${tfmt(c.t0)}</b></span><span><small>Süre</small><b>${c.dur.toFixed(1).replace('.', ',')} sn</b></span><span><small>Biter</small><b>${tfmt(c.t0 + c.dur)}</b></span>`; };
  const at = e => { const r = track.getBoundingClientRect(); return clamp((e.clientX - r.left) / r.width * dur, 0, dur); };
  let mode = null, off = 0;
  track.onpointerdown = e => {
    track.setPointerCapture(e.pointerId); const t = at(e), h = e.target.closest('.tlH');
    if (h) mode = h.classList.contains('l') ? 'l' : 'r';
    else { mode = 'm'; off = e.target.closest('.tlSeg') ? t - c.t0 : c.dur / 2; if (!e.target.closest('.tlSeg')) c.t0 = clamp(snap(t - off), 0, dur - c.dur); }
    draw(); drawPreview();
  };
  track.onpointermove = e => {
    if (!mode) return; const t = snap(at(e));
    if (mode === 'm') c.t0 = clamp(snap(at(e) - off), 0, Math.max(0, dur - c.dur));
    else if (mode === 'l') { const end = c.t0 + c.dur, n = clamp(t, 0, end - 1); c.dur = end - n; c.t0 = n; }
    else c.dur = clamp(t - c.t0, 1, dur - c.t0);
    draw(); drawPreview();
  };
  track.onpointerup = track.onpointercancel = () => { if (mode) { mode = null; showAt(c); } };
  draw(); return w;
}
async function renderCards() {
  const bc = $('cbC'), bt = $('cbT'), bl = $('cbL'); if (!bc) return;
  [bc, bt, bl].forEach(b => { b.innerHTML = ''; });
  const acts = await activityChoices(), dur = video.duration || state.info?.duration || 60;
  if (!acts.length) { const m = document.createElement('div'); m.className = 'empty-note'; m.innerHTML = '<b>Henüz kayıtlı aktivite yok</b><span>Özet sekmesinden bir kayıt yap; sonra burada kart olarak kullanabilirsin.</span>'; bc.append(m); return; }
  if (!cards.length && state.mode === 'card') { selCard = await addCard(acts[0].id, 6); selCard.t0 = 0; }
  if (!selCard && cards.length) selCard = cards[0];
  const row = document.createElement('div'); row.className = 'crow';
  cards.forEach((c, i) => { const b = document.createElement('button'); b.type = 'button'; b.className = 'pill' + (c === selCard ? ' on' : ''); b.textContent = 'Kart ' + (i + 1); b.onclick = () => { selCard = c; renderCards(); showAt(c); }; row.append(b); });
  if (cards.length < 3) { const b = document.createElement('button'); b.type = 'button'; b.className = 'pill add'; b.textContent = '+ Kart'; b.onclick = async () => { selCard = await addCard(acts[0].id, Math.min(6, dur)); selCard.t0 = Math.min(Math.round((video.currentTime || 0) * 2) / 2, Math.max(0, dur - selCard.dur)); renderCards(); showAt(selCard); }; row.append(b); }
  bc.append(row);
  const c = selCard; if (!c) return;
  const sel = document.createElement('select'); sel.className = 'typesel'; sel.style.width = '100%';
  sel.innerHTML = acts.map(a => `<option value="${a.id}" ${a.id === c.actId ? 'selected' : ''}>${esc(titleFor(a.type, a.start))} · ${esc(dateStr(a.start))}</option>`).join('');
  sel.onchange = () => { c.actId = sel.value; rebuild(c); };
  bc.append(field('Aktivite', sel));
  const mk = (items, get, set) => { const d = document.createElement('div'); d.className = 'seg wrap'; seg(d, items, get, v => { set(v); rebuild(c); }); return d; };
  bc.append(field('Şablon', mk(CARD_TPLS, () => c.tpl, v => { c.tpl = v; })));
  bc.append(field('Harita', mk(Object.fromEntries(Object.entries(CARD_MAPS).map(([k, v]) => [k, v.name])), () => c.mapStyle, v => { c.mapStyle = v; })));
  bc.append(field('Biçim', mk(SHAPES, () => c.shape, v => { c.shape = v; })));
  const cc = document.createElement('div'); cc.className = 'chips';
  for (const [k, hx] of Object.entries(CARD_COLORS)) { const b = document.createElement('button'); b.type = 'button'; b.className = 'chip' + (c.color === k ? ' on' : ''); b.style.background = hx; b.onclick = () => { c.color = k; cc.querySelectorAll('.chip').forEach(x => x.classList.toggle('on', x === b)); rebuild(c); }; cc.append(b); }
  bc.append(field('Rota rengi', cc));
  bc.append(field('Yazı rengi', mk(Object.fromEntries(Object.entries(TEXT_COLORS).filter(([k]) => k !== 'otomatik')), () => c.textColor, v => { c.textColor = v; })));
  const st = document.createElement('p'); st.id = 'cardBusy'; st.className = 'muted small'; st.style.margin = '4px 2px'; st.textContent = c.busy ? 'Hazırlanıyor…' : c.err || ''; bc.append(st);
  const del = document.createElement('button'); del.type = 'button'; del.className = 'btn ghost block'; del.textContent = 'Bu kartı kaldır';
  del.onclick = () => { removeCard(c); selCard = cards[0] || null; renderCards(); }; bc.append(del);
  // zaman
  const hint = document.createElement('p'); hint.className = 'muted small'; hint.style.margin = '0 2px 10px'; hint.textContent = 'Kartın videonun hangi kısmında, ne kadar süre görüneceğini ayarla. Ortadan sürükle: kaydır. Kenarlardan sürükle: süreyi değiştir.'; bt.append(hint);
  bt.append(timeline(c, dur));
  const nowBtn = document.createElement('button'); nowBtn.type = 'button'; nowBtn.className = 'btn block'; nowBtn.textContent = 'Başlangıcı oynatılan an yap';
  nowBtn.onclick = () => { c.t0 = Math.min(Math.round((video.currentTime || 0) * 2) / 2, Math.max(0, dur - c.dur)); renderCards(); drawPreview(); }; bt.append(nowBtn);
  bt.append(field('Geçiş', mk({ y: 'Yok', k: 'Kısa', u: 'Uzun' }, () => ({ 0: 'y', 0.5: 'k', 1: 'u' }[c.fade] || 'k'), v => { c.fade = { y: 0, k: 0.5, u: 1 }[v]; })));
  // yerleşim
  bl.append(slider('Boyut', 20, 100, 5, Math.round(c.size * 100), v => `%${v}`, v => { c.size = v / 100; drawPreview(); }));
  const pos = document.createElement('div'); pos.className = 'posgrid';
  const P = [['Sol üst', 'l', 't'], ['Üst', 'c', 't'], ['Sağ üst', 'r', 't'], ['Sol', 'l', 'm'], ['Orta', 'c', 'm'], ['Sağ', 'r', 'm'], ['Sol alt', 'l', 'b'], ['Alt', 'c', 'b'], ['Sağ alt', 'r', 'b']];
  P.forEach(([n, x, y]) => { const b = document.createElement('button'); b.type = 'button'; b.setAttribute('aria-label', n); b.innerHTML = `<i style="left:${x === 'l' ? 14 : x === 'r' ? 66 : 40}%;top:${y === 't' ? 16 : y === 'b' ? 66 : 40}%"></i>`; b.onclick = () => {
    const vw = state.info.width, vh = state.info.height, hf = c.bmp ? c.size * c.bmp.height / c.bmp.width * vw / vh : .2;
    c.cx = x === 'l' ? .04 + c.size / 2 : x === 'r' ? .96 - c.size / 2 : .5; c.cy = y === 't' ? .05 + hf / 2 : y === 'b' ? .95 - hf / 2 : .5; drawPreview(); }; pos.append(b); });
  bl.append(field('Konum', pos));
}
importNative().then(() => { if (!$('work').classList.contains('hidden')) renderCards(); });

// ---- Uygulama içi video editörü: sabit önizleme + mod seçimi + sekmeli alt panel ----
function buildVideoDock() {
  const root = $('work'); if (root.dataset.dock) return; root.dataset.dock = '1';
  const mk = (tag, cls) => { const e = document.createElement(tag); if (cls) e.className = cls; return e; };
  const cardEls = [...root.querySelectorAll('.right > section.card')];   // GPS, Göstergeler, Kart, Görünüm, Dışa aktar
  const prev = root.querySelector('.previewcard'), info = root.querySelector('.infocard'), again = $('again');
  const dock = mk('div', 'vdock'), modes = mk('div', 'modes'), tabs = mk('div', 'dockTabs'), pane = mk('div', 'vdPane');
  const g = (...els) => { const w = mk('div', 'dk-g'); w.append(...els); w.hidden = true; pane.append(w); return w; };
  cardEls.forEach(c => c.querySelector('.sec-h')?.remove());
  const W = { Göstergeler: g(cardEls[1]), Hizalama: g(cardEls[0], info), Görünüm: g(cardEls[3]), İçerik: g($('cbC')), Zaman: g($('cbT')), Yerleşim: g($('cbL')), 'Dışa aktar': g(cardEls[4], again) };
  cardEls[2].remove();
  const TABS = { live: ['Göstergeler', 'Hizalama', 'Görünüm', 'Dışa aktar'], card: ['İçerik', 'Zaman', 'Yerleşim', 'Dışa aktar'] };
  let tab = null;
  const show = n => { tab = n; Object.entries(W).forEach(([k, w]) => { w.hidden = k !== n; }); [...tabs.children].forEach(b => b.classList.toggle('on', b.textContent === n)); pane.scrollTop = 0;
    if ((n === 'Zaman' || n === 'Yerleşim') && selCard) showAt(selCard); };
  const setMode = m => {
    state.mode = m; state.sel = null; if (state.edit) setEdit(false);
    [...modes.children].forEach(b => b.classList.toggle('on', b.dataset.m === m)); $('stage').classList.toggle('cardmode', m === 'card');
    tabs.replaceChildren(...TABS[m].map(n => tabButton(n, () => show(n))));
    $('editBtn').closest('.toolbar')?.classList.toggle('hidden', m === 'card');
    renderCards().then(() => { show(TABS[m][0]); if (m === 'card' && selCard) showAt(selCard); drawPreview(); });
  };
  [['live', 'Canlı veri'], ['card', 'Aktivite kartı']].forEach(([m, n]) => { const b = mk('button'); b.type = 'button'; b.dataset.m = m; b.textContent = n; b.onclick = () => setMode(m); modes.append(b); });
  const bar = $('gobar'); dock.append(modes, pane, tabs, bar);
  root.replaceChildren(prev, dock);
  $('goMobile').onclick = () => { show('Dışa aktar'); if (!$('go').disabled) $('go').click(); };
  window.__tgShowTab = show; window.__tgSetMode = setMode;
  window.__tgInitDock = () => setMode(state.mode || 'live');
  setMode(state.mode || 'live');
}
// kartı doğrudan video üstünde sürükle (kart modu)
{ let cd = null;
  ov.addEventListener('pointerdown', e => {
    const c = selCard; if (state.mode !== 'card' || !c?.bmp || !state.info) return;
    const t = video.currentTime || 0; if (t < c.t0 - 0.05 || t > c.t0 + c.dur + 0.05) return;
    const nx = e.offsetX / ov.clientWidth, ny = e.offsetY / ov.clientHeight, w = c.size, h = c.size * c.bmp.height / c.bmp.width * state.info.width / state.info.height;
    if (Math.abs(nx - c.cx) > w / 2 || Math.abs(ny - c.cy) > h / 2) return;
    e.preventDefault(); ov.setPointerCapture(e.pointerId); cd = { sx: nx, sy: ny, x0: c.cx, y0: c.cy, w, h };
  });
  ov.addEventListener('pointermove', e => {
    if (!cd || !selCard) return; const c = selCard, nx = e.offsetX / ov.clientWidth, ny = e.offsetY / ov.clientHeight;
    const snap = v => Math.abs(v - 0.5) < 0.025 ? 0.5 : v, cl = (v, half) => Math.min(1 - half, Math.max(half, v));
    c.cx = snap(cl(cd.x0 + nx - cd.sx, Math.min(.5, cd.w / 2))); c.cy = snap(cl(cd.y0 + ny - cd.sy, Math.min(.5, cd.h / 2))); drawPreview();
  });
  const end = () => { cd = null; }; ov.addEventListener('pointerup', end); ov.addEventListener('pointercancel', end);
}
if (isApp) {
  video.controls = false;
  const bar = document.createElement('div'); bar.className = 'vplay';
  bar.innerHTML = '<button type="button" aria-label="Oynat / durdur"><svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg></button><input type="range" min="0" max="1000" value="0" aria-label="Video konumu"><span>0:00</span>';
  const [btn, rng, tm] = bar.children, PLAY = 'M8 5v14l11-7z', PAUSE = 'M6 5h4v14H6zM14 5h4v14h-4z';
  btn.onclick = () => (video.paused ? video.play() : video.pause());
  const upd = () => { const d = video.duration || 0; rng.value = d ? video.currentTime / d * 1000 : 0; tm.textContent = fmtDur(video.currentTime || 0); };
  ['timeupdate', 'seeked', 'loadedmetadata'].forEach(ev => video.addEventListener(ev, upd));
  video.addEventListener('play', () => btn.querySelector('path').setAttribute('d', PAUSE));
  video.addEventListener('pause', () => btn.querySelector('path').setAttribute('d', PLAY));
  rng.oninput = () => { if (video.duration) video.currentTime = rng.value / 1000 * video.duration; };
  $('stage').after(bar);
}
if (isApp) {
  buildVideoDock(); buildActPick();
  $('pickCard').append(fileEl);
  $('pkText').textContent = state.mode === 'card'
    ? 'Aktivitenin rota ve değerleri, videonun istediğin kısmında kart olarak belirir. Hangi saniyede başlayacağını ve ne kadar kalacağını sonra ayarlarsın.'
    : 'GoPro sensör verisi ya da GPS kaydıyla hız, rota ve eğim göstergeleri video boyunca canlı akar.';
}
