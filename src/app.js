import {
  Input, Output, Conversion, BlobSource, BufferTarget, StreamTarget, Mp4OutputFormat,
  ALL_FORMATS, QUALITY_HIGH, canEncodeVideo,
} from 'mediabunny';
import { readGoProTelemetry } from './gpmf.js';
import { drawOverlay, DEFAULTS, ACCENTS } from './overlay.js';

const $ = id => document.getElementById(id);
const fileEl = $('file'), video = $('video'), ov = $('ov'), msgEl = $('msg');
let state = { file: null, tel: null, meta: null, info: null, url: null, conv: null, outFile: null, res: '1080' };

// ---- ayarlar (yerel olarak hatırlanır) ----
let opts = { ...DEFAULTS };
try { Object.assign(opts, JSON.parse(localStorage.getItem('tg-opts') || '{}')); } catch {}
const save = () => { try { localStorage.setItem('tg-opts', JSON.stringify(opts)); } catch {} };

function setMsg(html, kind = 'err') { msgEl.innerHTML = html ? `<div class="msg ${kind}">${html}</div>` : ''; }
const fmtSize = b => b > 1e9 ? (b / 1e9).toFixed(2).replace('.', ',') + ' GB' : (b / 1e6).toFixed(1).replace('.', ',') + ' MB';
const fmtDur = s => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, '0')}`;

function bindSettings() {
  document.querySelectorAll('[data-k]').forEach(el => {
    const k = el.dataset.k;
    if (el.type === 'checkbox') el.checked = !!opts[k]; else el.value = opts[k];
    const upd = () => {
      opts[k] = el.type === 'checkbox' ? el.checked : Number(el.value);
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
  $('res').querySelectorAll('button').forEach(b => b.onclick = () => {
    state.res = b.dataset.v; $('res').querySelectorAll('button').forEach(x => x.classList.toggle('on', x === b));
  });
}

// ---- önizleme ----
function drawPreview() {
  if (!state.tel) return;
  const w = video.clientWidth, h = video.clientHeight; if (!w || !h) return;
  const vw = state.info.width, vh = state.info.height;
  const sc = Math.min(w / vw, h / vh), dw = vw * sc, dh = vh * sc;
  const dpr = window.devicePixelRatio || 1;
  ov.style.left = (w - dw) / 2 + 'px'; ov.style.top = (h - dh) / 2 + 'px';
  ov.style.width = dw + 'px'; ov.style.height = dh + 'px';
  const cw = Math.round(dw * dpr), ch = Math.round(dh * dpr);
  if (ov.width !== cw || ov.height !== ch) { ov.width = cw; ov.height = ch; }
  const ctx = ov.getContext('2d'); ctx.clearRect(0, 0, cw, ch);
  drawOverlay(ctx, cw, ch, video.currentTime || 0, state.tel, opts, state.meta);
}
let raf = 0;
function loop() { drawPreview(); raf = video.paused ? 0 : requestAnimationFrame(loop); }
video.addEventListener('play', () => { if (!raf) raf = requestAnimationFrame(loop); });
['seeked', 'timeupdate', 'loadeddata', 'pause'].forEach(e => video.addEventListener(e, drawPreview));
window.addEventListener('resize', drawPreview);
video.addEventListener('error', () => setMsg('Bu tarayıcı videoyu önizlemede oynatamıyor (çoğunlukla H.265/HEVC desteği yüzünden). Dışa aktarmayı yine de deneyebilirsin.', 'warn'));

// ---- dosya yükleme ----
fileEl.addEventListener('change', async () => {
  const f = fileEl.files[0]; if (!f) return;
  fileEl.value = '';
  await loadFile(f);
});

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
    if (state.url) URL.revokeObjectURL(state.url);
    state.url = URL.createObjectURL(f); video.src = state.url;
    showInfo();
    $('pickCard').classList.add('hidden'); $('work').classList.remove('hidden');
    setMsg(canDecode ? '' : 'Bu tarayıcı bu videonun formatını (' + (info.codec || '?') + ') çözemiyor; dışa aktarma çalışmayabilir. iPhone\'da Safari veya bilgisayarda güncel Chrome dene.', canDecode ? 'ok' : 'err');
    if (!tel.hasAccel) setMsg('Bu videoda ivmeölçer verisi yok; G-kuvveti göstergesi gizlendi.', 'warn');
    drawPreview();
  } catch (e) {
    console.error(e); setMsg('Video okunamadı: ' + (e.message || e));
  }
}

function showInfo() {
  const { info, tel } = state;
  const sens = ['Yerçekimi', tel.hasAccel && 'İvme', tel.hasGyro && 'Jiroskop'].filter(Boolean).join(' · ');
  $('info').innerHTML = [
    [tel.device, 'Kamera'], [`${info.width}×${info.height}`, 'Çözünürlük'],
    [`${Math.round(info.fps)} fps`, 'Kare hızı'], [fmtDur(info.duration), 'Süre'], [sens, 'Sensörler'],
  ].map(([b, s]) => `<div><b>${b}</b><small>${s}</small></div>`).join('');
  const short = Math.min(info.width, info.height);
  const origBtn = $('res').querySelector('[data-v="orig"]');
  if (short <= 1080) { origBtn.disabled = true; $('origLbl').textContent = 'video zaten 1080p'; $('res').querySelector('[data-v="1080"]').click(); }
  else { origBtn.disabled = false; $('origLbl').textContent = `${short >= 2160 ? '4K' : short + 'p'} · daha yavaş`; }
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
    return { target: new StreamTarget(w, { chunked: true }), format: new Mp4OutputFormat({ fastStart: false }), get: () => fh.getFile(), kind: 'disk' };
  } catch {
    const target = new BufferTarget();
    return { target, format: new Mp4OutputFormat({ fastStart: 'in-memory' }), get: async () => new Blob([target.buffer], { type: 'video/mp4' }), kind: 'mem' };
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
  const { file, tel, meta } = state; if (!file) return;
  resetResult(); setMsg('');
  const [W, H] = outSize();
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
        width: W, height: H, fit: 'fill', codec, bitrate: QUALITY_HIGH, forceTranscode: true,
        processedWidth: W, processedHeight: H,
        process: sample => {
          sample.draw(ctx, 0, 0, W, H);
          drawOverlay(ctx, W, H, sample.timestamp, tel, opts, meta);
          return canvas;
        },
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
    $('doneT').innerHTML = `<b>Hazır!</b> ${outName} · ${W}×${H} · ${fmtSize(state.outFile.size)} · ${secs} sn sürdü`;
    $('dl').href = URL.createObjectURL(state.outFile); $('dl').download = outName;
    $('done').classList.remove('hidden');
  } catch (e) {
    if (e?.name === 'ConversionCanceledError' || /cancel/i.test(e?.message || '')) setMsg('İşlem iptal edildi.', 'warn');
    else { console.error(e); setMsg('Video oluşturulamadı: ' + (e.message || e)); }
  } finally {
    state.conv = null; $('go').disabled = false; $('prog').classList.add('hidden'); keepAwake(false);
  }
};
$('cancel').onclick = () => state.conv?.cancel();

$('share').onclick = async () => {
  const f = state.outFile; if (!f) return;
  try {
    if (navigator.canShare?.({ files: [f] })) await navigator.share({ files: [f], title: f.name });
    else $('dl').click();
  } catch (e) { if (e.name !== 'AbortError') $('dl').click(); }
};
function resetResult() {
  $('done').classList.add('hidden');
  if ($('dl').href.startsWith('blob:')) URL.revokeObjectURL($('dl').href);
  state.outFile = null;
}
$('again').onclick = () => fileEl.click();
document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible' && state.conv) keepAwake(true); });

bindSettings();
window.__tg = { state, opts, loadFile }; // test için
