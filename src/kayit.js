// TelemetriGo GPS Kaydedici: tarayıcının konum servisinden (iPhone'da GPS + Doppler hızı) GPX kaydı.
import { putAct, TYPES } from './store.js';
const $ = id => document.getElementById(id);
const KEY = 'tg-rec', LAST = 'tg-last-gpx';
const R = 6371008.8, rad = d => d * Math.PI / 180;
const hav = (a, b) => { const dLa = rad(b[1] - a[1]), dLo = rad(b[2] - a[2]); const x = Math.sin(dLa / 2) ** 2 + Math.cos(rad(a[1])) * Math.cos(rad(b[1])) * Math.sin(dLo / 2) ** 2; return 2 * R * Math.asin(Math.min(1, Math.sqrt(x))); };
const num = (v, d) => v.toFixed(d).replace('.', ',');

// nokta: [t(ms), lat, lon, alt, acc, spd(m/s|null), course|null, altAcc]
let type = localStorage.getItem('tg-type') || 'motor';
const isPace = () => TYPES[type]?.pace;
const paceStr = v => { if (!v || v < 0.5) return '—'; const s = 1000 / v; return `${Math.floor(s / 60)}:${String(Math.round(s % 60)).padStart(2, '0')}`; };
let rec = null, watchId = null, lastFix = null, recent = [], geoErr = false, staleSince = 0, wake = null, tick = 0, hiddenAt = 0, gpxFile = null;

function setMsg(html, kind = 'warn') { $('msg').innerHTML = html ? `<div class="msg ${kind}">${html}</div>` : ''; }
function store() { try { localStorage.setItem(KEY, JSON.stringify(rec)); } catch {} }

// --- saat (senkron ekranı) ---
function clock() {
  const d = new Date(), ms = d.getMilliseconds();
  $('clock').innerHTML = `${d.toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit', second: '2-digit' })}<small>,${Math.floor(ms / 100)}</small>`;
  requestAnimationFrame(clock);
}
requestAnimationFrame(clock);

// --- konum ---
function quality(acc) {
  if (!isFinite(acc)) return ['Konum bekleniyor', ''];
  if (acc <= 10) return [`Sinyal iyi · ±${Math.round(acc)} m`, 'ok'];
  if (acc <= 25) return [`Sinyal orta · ±${Math.round(acc)} m`, 'warn'];
  return [`Sinyal zayıf · ±${Math.round(acc)} m`, 'rec'];
}
function onFix(pos) {
  const c = pos.coords;
  const p = [pos.timestamp || Date.now(), c.latitude, c.longitude, c.altitude ?? null, c.accuracy,
    (c.speed != null && isFinite(c.speed) && c.speed >= 0) ? c.speed : null,
    (c.heading != null && isFinite(c.heading) && c.heading >= 0) ? c.heading : null, c.altitudeAccuracy ?? null];
  // canlı hız: cihaz hızı (Doppler) varsa o, yoksa son iki noktadan; duruş eşiği altı 0
  if (geoErr && (!lastFix || lastFix[1] !== p[1] || lastFix[2] !== p[2])) { geoErr = false; setMsg(''); }
  recent.push(p); while (recent.length > 2 && p[0] - recent[0][0] > 4000) recent.shift();
  let v = p[5];
  if (v === null && recent.length > 1) {
    // cihaz hızı yoksa: son ~4 sn'deki net yer değiştirme; GPS hata payından küçükse duruyor say
    const a = recent[0], dt = (p[0] - a[0]) / 1000, D = hav(a, p);
    v = dt >= 1 ? (D > Math.max(a[4], p[4]) ? D / dt : 0) : null;
  }
  if (p[4] > 50) v = null; else if (v !== null && v < 0.9) v = 0;
  // Konum hiç değişmiyorsa telefon gerçek GPS almıyor (kapalı alan, ya da "Kesin Konum" kapalı)
  if (!lastFix || lastFix[1] !== p[1] || lastFix[2] !== p[2]) staleSince = p[0];
  const stale = p[0] - staleSince > 20000 && p[5] === null;
  if (stale && !geoErr) { geoErr = true; setMsg('Konum 20 saniyedir hiç değişmiyor: telefon gerçek GPS sinyali almıyor olabilir. Açık alana çık. iPhone\'da Ayarlar → Gizlilik ve Güvenlik → Konum Servisleri → Safari Web Siteleri → <b>Kesin Konum</b> açık olsun.'); }
  lastFix = p;
  const [txt, col] = quality(p[4]);
  $('acc').querySelector('span:last-child').textContent = txt; $('acc').className = 'badge ' + col;
  $('spd').textContent = v === null ? '—' : isPace() ? paceStr(v) : Math.round(v * 3.6);
  if (!rec) return;
  const prev = rec.pts[rec.pts.length - 1];
  if (prev && p[0] <= prev[0]) return;
  rec.pts.push(p.map((x, i) => (x === null ? null : i === 1 || i === 2 ? +x.toFixed(7) : i === 0 ? x : +(+x).toFixed(2))));
  if (prev && p[4] <= 50 && (v ?? 0) > 0) rec.dist += hav(prev, p);
  if (v !== null) rec.max = Math.max(rec.max, v);
  if (++tick % 5 === 0) store();
  stats();
}
function onErr(e) {
  const m = { 1: 'Konum izni verilmedi. Ayarlar → Gizlilik → Konum Servisleri → Safari Web Siteleri → "Uygulamayı Kullanırken" seç ve sayfayı yenile.', 2: 'Konum alınamıyor. Açık alana çık ve bekle.', 3: 'Konum zaman aşımı; sinyal bekleniyor…' };
  geoErr = true; setMsg(m[e.code] || 'Konum hatası: ' + e.message, e.code === 1 ? 'err' : 'warn');
}
function stats() {
  if (!rec) return;
  const s = Math.floor(((rec.end || Date.now()) - rec.start) / 1000);
  $('dur').textContent = `${Math.floor(s / 3600) ? Math.floor(s / 3600) + ':' : ''}${String(Math.floor(s / 60) % 60).padStart(Math.floor(s / 3600) ? 2 : 1, '0')}:${String(s % 60).padStart(2, '0')}`;
  $('dist').textContent = num(rec.dist / 1000, 2); $('cnt').textContent = rec.pts.length;
  $('max').textContent = isPace() ? (rec.dist > 50 && s > 0 ? paceStr(rec.dist / s) : '—') : Math.round(rec.max * 3.6);
}
setInterval(stats, 1000);

// konum izleme sayfa açılınca başlar (kayıt öncesi sinyali görmek için)
function watch() {
  if (!('geolocation' in navigator)) { setMsg('Bu tarayıcı konum desteklemiyor.', 'err'); return; }
  if (watchId !== null) navigator.geolocation.clearWatch(watchId);
  watchId = navigator.geolocation.watchPosition(onFix, onErr, { enableHighAccuracy: true, maximumAge: 0, timeout: 15000 });
}

// --- ekranı açık tut ---
async function awake(on) {
  const v = $('nosleep');
  if (on) {
    try { if ('wakeLock' in navigator) wake = await navigator.wakeLock.request('screen'); } catch {}
    try { await v.play(); } catch {}
  } else {
    try { await wake?.release(); } catch {} wake = null; v.pause();
  }
}
document.addEventListener('visibilitychange', () => {
  if (!rec || rec.end) return;
  if (document.visibilityState === 'hidden') { hiddenAt = Date.now(); store(); }
  else {
    awake(true); watch();
    const gap = Math.round((Date.now() - hiddenAt) / 1000);
    if (hiddenAt && gap > 3) { rec.gaps.push([hiddenAt, Date.now()]); setMsg(`Sayfa ${gap} sn arka planda kaldı; bu aralıkta GPS kaydı olmayabilir. Kayıt sürerken ekranı kapatma.`); }
    hiddenAt = 0;
  }
});

// --- kayıt ---
$('start').onclick = async () => {
  rec = { start: Date.now(), end: 0, pts: [], dist: 0, max: 0, gaps: [], ua: navigator.userAgent, type };
  $('type').querySelectorAll('button').forEach(b => b.disabled = b.dataset.v !== type);
  gpxFile = null; store(); await awake(true); watch(); setMsg('');
  $('start').classList.add('hidden'); $('stop').classList.remove('hidden'); $('after').classList.add('hidden');
};
$('stop').onclick = async () => {
  if (!rec) return;
  rec.end = Date.now(); store(); await awake(false);
  $('stop').classList.add('hidden');
  if (rec.pts.length < 2) { setMsg('Kayıtta yeterli konum noktası yok. Sinyal "iyi" olana kadar bekleyip tekrar dene.', 'err'); $('start').classList.remove('hidden'); return; }
  finish();
};
function finish() {
  const gpx = toGpx(rec);
  const d = new Date(rec.start), pad = n => String(n).padStart(2, '0');
  const name = `TelemetriGo_${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}_${pad(d.getHours())}-${pad(d.getMinutes())}.gpx`;
  gpxFile = new File([gpx], name, { type: 'application/gpx+xml' });
  try { localStorage.setItem(LAST, JSON.stringify({ name, saved: Date.now(), start: rec.start, end: rec.end, gpx, type: rec.type })); } catch {}
  const id = 'w' + rec.start;
  putAct({ id, name, type: rec.type || type, start: rec.start, end: rec.end, dist: rec.dist, gpx, src: 'web' }).catch(() => {});
  $('toAct').href = 'aktivite.html#' + id;
  $('type').querySelectorAll('button').forEach(b => b.disabled = false);
  try { localStorage.removeItem(KEY); } catch {}
  const a = $('dl'); if (a.href.startsWith('blob:')) URL.revokeObjectURL(a.href);
  a.href = URL.createObjectURL(gpxFile); a.download = name;
  $('after').classList.remove('hidden');
  const goodShare = rec.pts.filter(p => p[4] <= 25).length / rec.pts.length;
  setMsg(`Kayıt tamam: ${rec.pts.length} nokta, ${num(rec.dist / 1000, 2)} km.` + (goodShare < 0.7 ? ' Noktaların çoğunda sinyal zayıftı; hız ve rota hatalı olabilir.' : ''), goodShare < 0.7 ? 'warn' : 'ok');
  stats();
}
function toGpx(r) {
  const esc = s => String(s).replace(/[<&]/g, c => (c === '<' ? '&lt;' : '&amp;'));
  const pts = r.pts.map(p => {
    let s = `<trkpt lat="${p[1]}" lon="${p[2]}">`;
    if (p[3] !== null) s += `<ele>${p[3]}</ele>`;
    s += `<time>${new Date(p[0]).toISOString()}</time><extensions>`;
    if (p[5] !== null) s += `<tg:speed>${p[5]}</tg:speed>`;
    if (p[6] !== null) s += `<tg:course>${p[6]}</tg:course>`;
    s += `<tg:hacc>${p[4]}</tg:hacc>`;
    if (p[7] !== null) s += `<tg:vacc>${p[7]}</tg:vacc>`;
    return s + '</extensions></trkpt>';
  }).join('\n');
  return `<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="TelemetriGo GPS Kaydedici" xmlns="http://www.topografix.com/GPX/1/1" xmlns:tg="https://rahimov0.github.io/-telemetrigo-/gpx/1">
<metadata><name>${esc('TelemetriGo ' + new Date(r.start).toLocaleString('tr-TR'))}</name><time>${new Date(r.start).toISOString()}</time></metadata>
<trk><name>TelemetriGo</name><type>${r.type || 'motor'}</type><trkseg>
${pts}
</trkseg></trk></gpx>
`;
}
$('share').onclick = async () => {
  if (!gpxFile) return;
  try { if (navigator.canShare?.({ files: [gpxFile] })) await navigator.share({ files: [gpxFile], title: gpxFile.name }); else $('dl').click(); }
  catch (e) { if (e.name !== 'AbortError') $('dl').click(); }
};
$('new').onclick = () => { rec = null; gpxFile = null; $('after').classList.add('hidden'); $('start').classList.remove('hidden'); setMsg(''); ['dur', 'dist', 'max', 'cnt'].forEach(id => $(id).textContent = id === 'dist' ? '0,00' : id === 'dur' ? '0:00' : '0'); };
function setType(v) {
  type = v; localStorage.setItem('tg-type', v);
  $('type').querySelectorAll('button').forEach(b => b.classList.toggle('on', b.dataset.v === v));
  $('spdUnit').textContent = isPace() ? 'dk/km tempo' : 'km/h';
  $('maxK').textContent = isPace() ? 'Ort. tempo' : 'Maks hız';
  if (!rec) $('spd').textContent = '—'; else stats();
}
$('type').querySelectorAll('button').forEach(b => b.onclick = () => { if (!rec || rec.end) setType(b.dataset.v); });
setType(type);

// --- yarım kalmış kaydı kurtar ---
try {
  const old = JSON.parse(localStorage.getItem(KEY) || 'null');
  if (old && old.pts?.length > 1) {
    setMsg(`Yarım kalmış bir kayıt bulundu (${new Date(old.start).toLocaleString('tr-TR')}, ${old.pts.length} nokta). <button id="recover" class="btn sm" style="margin-top:8px">Kaydı kurtar ve GPX yap</button>`);
    $('recover').onclick = () => { rec = old; if (old.type) setType(old.type); rec.end = rec.end || rec.pts[rec.pts.length - 1][0]; $('start').classList.add('hidden'); finish(); };
  }
} catch {}
watch();
window.__rec = { get rec() { return rec; }, toGpx }; // test için
