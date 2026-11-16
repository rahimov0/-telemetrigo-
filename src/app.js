import {
  Input, Output, Conversion, BlobSource, BufferTarget, StreamTarget, Mp4OutputFormat,
  ALL_FORMATS, QUALITY_HIGH, canEncodeVideo,
} from 'mediabunny';
import { readGoProTelemetry } from './gpmf.js';
import { parseGpx, coverage, autoSync } from './gpx.js';
import { drawOverlay, mergeOpts, ACCENTS, THEMES, GAUGES, gaugeAvailable } from './overlay.js';

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
    b.onclick = () => { opts.accent = name; save(); chips.querySelectorAll('.chip').forEach(c => c.classList.toggle('on', c === b)); drawPreview(); };
    chips.appendChild(b);
  }
  seg($('theme'), THEMES, () => opts.theme, v => { opts.theme = v; save(); drawPreview(); });
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
  for (const [id, G] of Object.entries(GAUGES)) {
    const avail = !state.tel || gaugeAvailable(id, data());
    const row = document.createElement('div'); row.className = 'grow' + (state.sel === id ? ' sel' : '') + (avail ? '' : ' na');
    row.innerHTML = `<button class="gname"><b>${G.name}</b><small>${!avail ? (G.needs === 'gps' ? 'GPX gerekli' : 'veri yok') : (G.styles ? G.styles[opts.g[id].style] + ' · ' : '') + 'düzenle'}</small></button>
      <input type="checkbox" ${opts.g[id].on ? 'checked' : ''} ${avail ? '' : 'disabled'} aria-label="${G.name}">`;
    row.querySelector('input').onchange = e => { opts.g[id].on = e.target.checked; save(); if (e.target.checked) select(id); else drawPreview(); };
    row.querySelector('.gname').onclick = () => select(state.sel === id ? null : id);
    list.appendChild(row);
    if (state.sel === id) list.appendChild(editorFor(id));
  }
}
function editorFor(id) {
  const G = GAUGES[id], g = opts.g[id], box = document.createElement('div'); box.className = 'geditor';
  box.innerHTML = `${G.styles ? '<div class="seg small" data-r="style"></div>' : ''}
    <div class="slider"><label>Bu göstergenin boyutu <b>%${g.scale}</b></label><input type="range" min="50" max="200" step="5" value="${g.scale}"></div>
    <div class="row"><button class="btn sm" data-r="reset">Konumu sıfırla</button><button class="btn sm" data-r="edit">Önizlemede taşı</button></div>`;
  if (G.styles) seg(box.querySelector('[data-r=style]'), G.styles, () => g.style, v => { g.style = v; save(); drawPreview(); renderGaugeList(); });
  const r = box.querySelector('input[type=range]');
  r.oninput = () => { g.scale = Number(r.value); r.previousElementSibling.querySelector('b').textContent = `%${g.scale}`; save(); drawPreview(); };
  box.querySelector('[data-r=reset]').onclick = () => { g.x = G.def.x; g.y = G.def.y; g.scale = 100; save(); renderGaugeList(); drawPreview(); };
  box.querySelector('[data-r=edit]').onclick = () => { setEdit(true); $('stage').scrollIntoView({ behavior: 'smooth', block: 'center' }); };
  return box;
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
  $('editBtn').classList.toggle('on', on); $('editBtn').textContent = on ? 'Bitti' : 'Konumları düzenle';
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
    const tel = await readGoProTelemetry(f);
    if (!tel.found) {
      setMsg('Bu videoda GoPro sensör verisi bulunamadı.<br>• Dosya WhatsApp, Instagram veya bir düzenleme uygulamasından geçtiyse veri silinmiş olur.<br>• iPhone\'da Fotoğraf Arşivi\'nden seçince iPhone videoyu sıkıştırıp veriyi silebilir: videoyu önce <b>Dosyalara Kaydet</b>, sonra burada <b>Gözat</b>\'tan seç.<br>• En garantisi: SD karttan veya Quik ile indirilen orijinal dosya.');
      return;
    }
    const input = new Input({ source: new BlobSource(f), formats: ALL_FORMATS });
    const vt = await input.getPrimaryVideoTrack();
    if (!vt) throw new Error('Videoda görüntü izi yok.');
    const stats = await vt.computePacketStats(120);
    const duration = await input.computeDuration();
    const canDecode = await vt.canDecode();
    const info = { width: vt.displayWidth, height: vt.displayHeight, fps: stats.averagePacketRate, duration, codec: vt.codec, canDecode };
    input.dispose?.();
    Object.assign(state, { file: f, tel, info, meta: { created: tel.created, device: tel.device } });
    if (state.gps) { state.gbase = gpsBase(); updateGpsUI(); }
    if (state.url) URL.revokeObjectURL(state.url);
    state.url = URL.createObjectURL(f); video.src = state.url;
    showInfo(); renderGaugeList();
    $('pickCard').classList.add('hidden'); $('recCard').classList.add('hidden'); $('work').classList.remove('hidden');
    setMsg(canDecode ? '' : 'Bu tarayıcı bu videonun formatını (' + (info.codec || '?') + ') çözemiyor; dışa aktarma çalışmayabilir. iPhone\'da Safari veya bilgisayarda güncel Chrome dene.', 'err');
    if (canDecode && !tel.hasAccel) setMsg('Bu videoda ivmeölçer verisi yok; G-kuvveti göstergesi gizlendi.', 'warn');
    drawPreview();
  } catch (e) { console.error(e); setMsg('Video okunamadı: ' + esc(e.message || e)); }
}

function showInfo() {
  const { info, tel } = state;
  const sens = ['Yerçekimi', tel.hasAccel && 'İvme', tel.hasGyro && 'Jiroskop'].filter(Boolean).join(' · ');
  $('info').innerHTML = [
    [tel.device, 'Kamera'], [`${info.width}×${info.height}`, 'Çözünürlük'],
    [`${Math.round(info.fps)} fps`, 'Kare hızı'], [fmtDur(info.duration), 'Süre'], [sens, 'Sensörler'],
  ].map(([b, s]) => `<div><b>${esc(b)}</b><small>${s}</small></div>`).join('');
  const short = Math.min(info.width, info.height), origBtn = $('res').querySelector('[data-v="orig"]');
  if (short <= 1080) { origBtn.disabled = true; $('origLbl').textContent = 'video zaten 1080p'; $('res').querySelector('[data-v="1080"]').click(); }
  else { origBtn.disabled = false; $('origLbl').textContent = `${short >= 2160 ? '4K' : short + 'p'} · daha yavaş`; }
}

// ---- GPX ----
const gpsBase = () => state.meta?.created ? state.meta.created.getTime() : state.gps.start;
$('gpxBtn').onclick = () => gpxEl.click();
gpxEl.addEventListener('change', async () => {
  const f = gpxEl.files[0]; if (!f) return; gpxEl.value = '';
  useGpx(await f.text(), f.name);
});
let last = null; try { last = JSON.parse(localStorage.getItem('tg-last-gpx') || 'null'); } catch {}
if (last?.gpx) {
  const b = $('lastGpx'); b.classList.remove('hidden');
  b.textContent = `Son GPS kaydını kullan (${new Date(last.start).toLocaleString('tr-TR', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })})`;
  b.onclick = () => useGpx(last.gpx, last.name);
}
function useGpx(text, name) {
  try {
    const g = parseGpx(text);
    state.gps = g; state.gpxName = name; state.goff = 0; state.gbase = gpsBase();
    for (const id of ['speed', 'map', 'compass']) if (!saved?.g?.[id]) opts.g[id].on = true;
    updateGpsUI(); renderGaugeList(); drawPreview();
    const cov = coverage(g, state.gbase, 0, state.info.duration);
    if (cov < 0.5 && state.tel?.hasAccel) runAutoSync(true);
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
    + (g.stillCount || g.dropped ? `<br>Temizlik: ${g.stillCount ? g.stillCount + ' duruş noktasındaki GPS kayması sıfırlandı' : ''}${g.stillCount && g.dropped ? ', ' : ''}${g.dropped ? g.dropped + ' hatalı nokta atıldı' : ''}` : '');
  const vStart = state.gbase - state.goff * 1000;
  const status = cov >= 0.95 ? ['ok', 'GPX bu videonun tamamını kapsıyor.']
    : cov > 0 ? ['warn', `GPX videonun %${Math.round(cov * 100)}'ini kapsıyor; kalan kısımda GPS göstergeleri "—" gösterir.`]
    : ['err', `GPX bu videonun zamanıyla örtüşmüyor. Video ${hhmm(vStart)}'de başlıyor, GPX ${hhmm(g.start)}–${hhmm(g.end)} arası. Doğru GPX'i seçtiğinden emin ol ya da "Otomatik eşitle"yi dene.`];
  $('gpsCov').className = 'msg ' + status[0]; $('gpsCov').textContent = status[1];
  $('off').value = state.goff; $('offV').textContent = `${state.goff > 0 ? '+' : ''}${state.goff.toFixed(1).replace('.', ',')} sn`;
}
function setOffset(v) { state.goff = Math.round(Math.max(-600, Math.min(600, v)) * 10) / 10; updateGpsUI(); drawPreview(); }
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
  setOffset(r.offset);
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

bindSettings(); renderGaugeList(); updateGpsUI();
window.__tg = { state, opts, loadFile, setEdit, select, setOffset, // test için
  snap: (W = 1920, H = 1080) => { const c = document.createElement('canvas'); c.width = W; c.height = H; const x = c.getContext('2d');
    x.drawImage(video, 0, 0, W, H); drawOverlay(x, W, H, video.currentTime, data(), opts, state.meta); return c.toDataURL('image/jpeg', 0.85); } };
