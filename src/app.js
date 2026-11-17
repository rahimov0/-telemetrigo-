import {
  Input, Output, Conversion, BlobSource, BufferTarget, StreamTarget, Mp4OutputFormat,
  ALL_FORMATS, QUALITY_HIGH, canEncodeVideo,
} from 'mediabunny';
import { readGoProTelemetry, emptyTelemetry, calibrateAt, applyCalibration } from './gpmf.js';
import { parseGpx, coverage, autoSync } from './gpx.js';
import { drawOverlay, drawGaugeThumb, mergeOpts, applyPreset, PRESETS, ACCENTS, THEMES, GAUGES, gaugeAvailable } from './overlay.js';

const $ = id => document.getElementById(id);
const fileEl = $('file'), gpxEl = $('gpxFile'), video = $('video'), ov = $('ov'), msgEl = $('msg');
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
  const ids = Object.keys(GAUGES), avail = id => !state.tel || gaugeAvailable(id, data());
  const row = id => {
    const G = GAUGES[id], ok = avail(id), r = document.createElement('div');
    r.className = 'grow-row' + (state.sel === id ? ' sel' : '') + (ok ? '' : ' na');
    const sub = !ok ? (G.needs === 'gps' ? 'GPX ekleyince açılır' : 'Bu videoda sensör verisi yok') : (G.styles ? (G.styles[opts.g[id].style] || Object.values(G.styles)[0]) + ' · ' + Object.keys(G.styles).length + ' stil' : 'Boyut ve konum');
    r.innerHTML = `<button class="gname" aria-expanded="${state.sel === id}" ${ok ? '' : 'disabled'}><b>${G.name}</b><small>${sub}</small></button>
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
  box.innerHTML = `${G.styles ? '<div class="styles" data-r="style" role="radiogroup" aria-label="Stil"></div>' : ''}
    <div class="slider"><label>Bu göstergenin boyutu <b class="num">%${g.scale}</b></label><input type="range" min="50" max="200" step="5" value="${g.scale}" aria-label="Gösterge boyutu"></div>
    <div class="row" style="margin-top:var(--s2)"><button class="btn sm grow" data-r="edit">Önizlemede taşı</button><button class="btn sm ghost" data-r="reset">Varsayılana dön</button></div>`;
  if (G.styles && state.tel) {
    const wrap = box.querySelector('[data-r=style]'), t = video.currentTime || 0;
    for (const [st, name] of Object.entries(G.styles)) {
      const b = document.createElement('button'); b.className = (g.style || Object.keys(G.styles)[0]) === st ? 'on' : '';
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
  state.rects = drawOverlay(ctx, cw, ch, video.currentTime || 0, data(), opts, state.meta, { highlight: state.sel, edit: state.edit });
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
    Object.assign(state, { file: f, tel, info, meta: { created: tel.created, device: tel.device }, tzNote: 0 });
    if (state.gps) { state.gbase = gpsBase(); updateGpsUI(); }
    if (state.url) URL.revokeObjectURL(state.url);
    state.url = URL.createObjectURL(f); video.src = state.url;
    showInfo(); renderGaugeList();
    $('pickCard').classList.add('hidden'); $('recCard')?.classList.add('hidden'); $('work').classList.remove('hidden');
    setMsg(canDecode ? '' : 'Bu tarayıcı bu videonun formatını (' + (info.codec || '?') + ') çözemiyor; dışa aktarma çalışmayabilir. iPhone\'da Safari veya bilgisayarda güncel Chrome dene.', 'err');
    if (canDecode && noImu) setMsg('Bu videoda yatış/eğim sensör verisi yok' + (tel.device === 'GoPro' ? ' (WhatsApp vb. ile gönderilen GoPro videolarında silinir; orijinal dosyayı kullan)' : '') + '. <b>GPX ekleyerek hız, rota, pusula ve irtifa göstergeleri ekleyebilirsin.</b>', 'warn');
    else if (canDecode && !tel.hasAccel) setMsg('Bu videoda ivmeölçer verisi yok; G-kuvveti göstergesi gizlendi.', 'warn');
    drawPreview(); autoLast();
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
function gpsBase(g = state.gps) {
  const created = state.meta?.created?.getTime();
  state.syncSrc = created ? 'saat' : 'gpx';
  if (!created) return g.start;
  const cs = (g.camStarts || []).map(t => [Math.abs(t - created), t]).sort((a, b) => a[0] - b[0])[0];
  if (cs && cs[0] < 10000) { state.syncSrc = 'kamera'; return cs[1]; }
  // Bazı kameralar (ör. DJI) yerel saati UTC gibi yazar: örtüşme yoksa tam/yarım saatlik farkları dene
  state.tzFix = 0;
  const dur = state.info?.duration || 60;
  if (coverage(g, created, 0, dur) === 0) {
    for (const h of [3, -3, 1, -1, 2, -2, 4, -4, 5, -5, 6, -6, 7, -7, 8, -8, 9, -9, 10, -10, 11, -11, 12, -12, 3.5, 4.5, 5.5, 5.75, 6.5, 9.5, -3.5, 13, 14])
      if (coverage(g, created - h * 3600000, 0, dur) > 0.5) { state.tzFix = h; return created - h * 3600000; }
  }
  return created;
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
function autoLast() {
  if (state.gps || !last?.gpx || !state.info) return;
  try {
    const g = parseGpx(last.gpx), base = gpsBase(g);
    if (coverage(g, base, 0, state.info.duration) > 0.3) { useGpx(last.gpx, last.name); setMsg('Bu videonun zamanına denk gelen GPS kaydı otomatik eklendi.', 'ok'); }
  } catch {}
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
    state.gps = g; state.gpxName = name; state.goff = 0; state.gbase = gpsBase(); state.offRemembered = false;
    if (state.syncSrc !== 'kamera') {
      let m = NaN; try { m = parseFloat(localStorage.getItem(offKey())); } catch {}
      if (isFinite(m) && m !== 0) { state.goff = m; state.offRemembered = true; }
    }
    if (state.tzFix && state.meta?.created) {   // saat göstergesi de doğru saati göstersin
      state.meta.created = new Date(state.meta.created.getTime() - state.tzFix * 3600000);
      state.tzNote = state.tzFix; state.tzFix = 0;
    }
    for (const id of ['speed', 'map', 'compass']) if (!saved?.g?.[id]) opts.g[id].on = true;
    updateGpsUI(); renderGaugeList(); drawPreview();
    const cov = coverage(g, state.gbase, 0, state.info.duration);
    if (cov < 0.5 && state.tel?.hasAccel && state.syncSrc !== 'kamera') runAutoSync(true);
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
    + (state.offRemembered ? `<br>Bu kamera için daha önce ayarladığın <b>${state.goff > 0 ? '+' : ''}${state.goff.toFixed(1).replace('.', ',')} sn</b> kaydırma uygulandı.` : '')
    + (g.stillCount || g.dropped ? `<br>Temizlik: ${g.stillCount ? g.stillCount + ' duruş noktasındaki GPS kayması sıfırlandı' : ''}${g.stillCount && g.dropped ? ', ' : ''}${g.dropped ? g.dropped + ' hatalı nokta atıldı' : ''}` : '');
  const vStart = state.gbase - state.goff * 1000;
  const status = cov >= 0.95 ? ['ok', 'GPX bu videonun tamamını kapsıyor.']
    : cov > 0 ? ['warn', `GPX videonun %${Math.round(cov * 100)}'ini kapsıyor; kalan kısımda GPS göstergeleri "—" gösterir.`]
    : ['err', `GPX bu videonun zamanıyla örtüşmüyor. Video ${hhmm(vStart)}'de başlıyor, GPX ${hhmm(g.start)}–${hhmm(g.end)} arası. Doğru GPX'i seçtiğinden emin ol ya da "Otomatik eşitle"yi dene.`];
  if (g.total < 20) status[0] = 'err', status[1] = `Bu GPS kaydında neredeyse hiç hareket yok (${Math.round(g.total)} m). Telefon kayıt sırasında gerçek GPS almamış olabilir (kapalı alan ya da "Kesin Konum" kapalı). ` + (cov > 0 ? 'Hız 0 ve rota tek nokta görünecek.' : status[1]);
  $('gpsCov').className = 'msg ' + status[0]; $('gpsCov').textContent = status[1];
  $('off').value = state.goff; $('offV').textContent = `${state.goff > 0 ? '+' : ''}${state.goff.toFixed(1).replace('.', ',')} sn`;
}
// Elle yapılan kaydırma kamera başına hatırlanır (kamera saati genelde hep aynı yöne kayar)
const offKey = () => 'tg-off-' + (state.meta?.device || 'Kamera');
function setOffset(v, remember = true) {
  state.goff = Math.round(Math.max(-600, Math.min(600, v)) * 10) / 10;
  if (remember && state.syncSrc !== 'kamera') { try { localStorage.setItem(offKey(), String(state.goff)); } catch {} state.offRemembered = false; }
  updateGpsUI(); drawPreview();
}
$('off').oninput = e => setOffset(Number(e.target.value));
document.querySelectorAll('[data-off]').forEach(b => b.onclick = () => setOffset(state.goff + Number(b.dataset.off)));
$('gpxRemove').onclick = () => { state.gps = null; updateGpsUI(); renderGaugeList(); drawPreview(); $('syncMsg').textContent = ''; };
$('autoSync').onclick = () => runAutoSync(false);
function runAutoSync(silent) {
  if (!state.gps || !state.tel?.hasAccel) return;
  const r = autoSync(state.gps, state.gbase, state.tel, { range: 300, step: 0.1 });
  const el = $('syncMsg');
  if (!r || r.score < 0.3) {
    el.textContent = silent ? '' : 'Otomatik eşitleme güvenilir bir sonuç bulamadı. Video kısa olabilir, hız fazla değişmemiş olabilir ya da kamera kaskta olabilir. Kaydırmayı elle ayarla: videoda bir fren/kalkış anında hız göstergesini gerçeğe uydur.';
    return;
  }
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
        process: sample => { sample.draw(ctx, 0, 0, W, H); drawOverlay(ctx, W, H, sample.timestamp, D, O, meta); return canvas; },
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
window.__tg = { state, opts, loadFile, setEdit, select, setOffset, // test için
  snap: (W = 1920, H = 1080) => { const c = document.createElement('canvas'); c.width = W; c.height = H; const x = c.getContext('2d');
    x.drawImage(video, 0, 0, W, H); drawOverlay(x, W, H, video.currentTime, data(), opts, state.meta); return c.toDataURL('image/jpeg', 0.85); } };
