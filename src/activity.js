// Aktivite özeti: hareket süresi, tempo, km splitleri, yükseliş, gizlilik bölgesi.
import { TYPES } from './store.js';

export const fmtDur = s => {
  s = Math.max(0, Math.round(s)); const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, x = s % 60;
  return h ? `${h}:${String(m).padStart(2, '0')}:${String(x).padStart(2, '0')}` : `${m}:${String(x).padStart(2, '0')}`;
};
export const fmtPace = mps => { if (!(mps > 0.3)) return '—'; const s = Math.round(1000 / mps); return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`; };
export const fmtKm = (m, d = 2) => (m / 1000).toFixed(m >= 100000 ? 1 : d).replace('.', ',');
export const fmtNum = (v, d = 0) => v.toFixed(d).replace('.', ',');

export function guessType(g) {
  const v = g.total / Math.max(1, (g.end - g.start) / 1000);
  return v < 1.9 ? 'yuruyus' : v < 4.2 ? 'kosu' : v < 11 ? 'bisiklet' : 'motor';
}

export function analyze(g, type) {
  type = type || g.type && Object.keys(TYPES).find(k => k === g.type) || guessType(g);
  const n = g.n, moving = new Float64Array(n);   // her noktaya kadar hareket süresi (sn)
  // mesafe: GPS titremesi zikzak yapıp mesafeyi şişirmesin diye ±2,5 sn içinde yumuşatılmış konumdan
  const dd = new Float64Array(n), sx = new Float64Array(n), sy = new Float64Array(n);
  for (let i = 0, a = 0, b = 0; i < n; i++) {
    if (g.still?.[i]) { sx[i] = g.x[i]; sy[i] = g.y[i]; continue; }
    while (g.t[i] - g.t[a] > 2500) a++;
    while (b < n - 1 && g.t[b + 1] - g.t[i] <= 2500) b++;
    let X = 0, Y = 0, c = 0;
    for (let j = a; j <= b; j++) if (!g.still?.[j]) { const w = 1 / (1 + Math.abs(g.t[j] - g.t[i]) / 1000); X += g.x[j] * w; Y += g.y[j] * w; c += w; }
    sx[i] = X / c; sy[i] = Y / c;
  }
  for (let i = 1; i < n; i++) dd[i] = dd[i - 1] + (g.still?.[i] && g.still?.[i - 1] ? 0 : Math.hypot(sx[i] - sx[i - 1], sy[i] - sy[i - 1]));
  for (let i = 1; i < n; i++) {
    const dt = (g.t[i] - g.t[i - 1]) / 1000;
    const mv = !(g.still?.[i] && g.still?.[i - 1]) && dt < 30 && (dd[i] - dd[i - 1]) / Math.max(dt, 0.001) > 0.3;
    moving[i] = moving[i - 1] + (mv ? dt : 0);
  }
  const movingTime = moving[n - 1], elapsed = (g.end - g.start) / 1000, dist = dd[n - 1];
  const avg = movingTime > 0 ? dist / movingTime : 0;
  // maks hız: 5 sn kayan ortalama (tek nokta sıçramaları sayılmasın)
  let vmax = 0;
  for (let i = 0, j = 0; i < n; i++) {
    while (j < n - 1 && g.t[j + 1] - g.t[i] <= 5000) j++;
    const dt = (g.t[j] - g.t[i]) / 1000; if (dt >= 3) vmax = Math.max(vmax, (dd[j] - dd[i]) / dt);
  }
  if (TYPES[type]?.pace === false) vmax = Math.max(vmax, Math.min(g.vMax, vmax * 1.15));
  // yükseklik: mesafe bazlı yumuşatma + 2 m eşikli birikim
  let gain = 0, loss = 0, eleS = null;
  if (g.hasEle) {
    eleS = new Float32Array(n); const W = 40; let a = 0, b = 0, sum = 0, cnt = 0;
    for (let i = 0; i < n; i++) {
      while (b < n && g.dist[b] - g.dist[i] <= W) { if (isFinite(g.ele[b])) { sum += g.ele[b]; cnt++; } b++; }
      while (g.dist[i] - g.dist[a] > W) { if (isFinite(g.ele[a])) { sum -= g.ele[a]; cnt--; } a++; }
      eleS[i] = cnt ? sum / cnt : (i ? eleS[i - 1] : 0);
    }
    let ref = eleS[0];
    for (let i = 1; i < n; i++) { const d = eleS[i] - ref; if (d >= 2) { gain += d; ref = eleS[i]; } else if (d <= -2) { loss -= d; ref = eleS[i]; } }
  }
  // km splitleri (son kısmi split dahil)
  const splits = []; const step = 1000; let k = 1, prevT = 0, prevE = eleS ? eleS[0] : NaN, prevI = 0;
  const at = (arr, i, f) => arr[i] + (arr[i + 1] - arr[i]) * f;
  for (let i = 0; i < n - 1 && k * step <= dist; i++) {
    while (i < n - 1 && dd[i + 1] >= k * step && k * step <= dist) {
      const f = (k * step - dd[i]) / Math.max(1e-6, dd[i + 1] - dd[i]);
      const mt = at(moving, i, f), e = eleS ? at(eleS, i, f) : NaN;
      splits.push({ km: k, len: step, time: mt - prevT, ele: e - prevE, i0: prevI, i1: i + 1 });
      prevT = mt; prevE = e; prevI = i + 1; k++;
    }
  }
  const rest = dist - (k - 1) * step;
  if (rest > 50) splits.push({ km: k, len: rest, time: movingTime - prevT, ele: eleS ? eleS[n - 1] - prevE : NaN, i0: prevI, i1: n - 1, partial: true });
  return { type, dist, dd, movingTime, elapsed, avg, vmax, gain, loss, splits, eleS, moving, start: g.start, end: g.end, pace: !!TYPES[type]?.pace };
}

// Gizlilik: başlangıç ve bitişe yakın noktaları gizle (rota çizilirken)
export function visibleRange(g, hideM) {
  if (!hideM) return [0, g.n - 1];
  hideM = Math.min(hideM, g.total * 0.2);   // kısa rotada tamamı gizlenmesin
  let a = 0, b = g.n - 1;
  while (a < g.n - 1 && g.dist[a] < hideM) a++;
  while (b > 0 && g.total - g.dist[b] < hideM) b--;
  return a < b ? [a, b] : [0, -1];
}

// Rota yolunu oluştur (yerel metre → ekran). Çok uzun rotalarda nokta seyreltilir.
export function routePath(g, P, i0 = 0, i1 = g.n - 1, maxPts = 3000) {
  const path = new Path2D(), step = Math.max(1, Math.floor((i1 - i0) / maxPts));
  let first = true;
  for (let i = i0; i <= i1; i += step) { const [x, y] = P(g.x[i], g.y[i]); first ? path.moveTo(x, y) : path.lineTo(x, y); first = false; }
  if (!first) { const [x, y] = P(g.x[i1], g.y[i1]); path.lineTo(x, y); }
  return path;
}

// Rotayı kutuya sığdıran ölçek ve dönüşüm. rot: derece (saat yönü). Dönüş: { P, sc, M (DOMMatrix), view }
export function fitRoute(g, box, { pad = 0.08, i0 = 0, i1 = g.n - 1, rot = 0 } = {}) {
  const r = rot * Math.PI / 180, c = Math.cos(r), s = Math.sin(r);
  let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity;
  const step = Math.max(1, Math.floor((i1 - i0) / 4000));
  for (let i = i0; i <= i1; i += step) {
    const X = g.x[i] * c + g.y[i] * s, Y = -g.x[i] * s + g.y[i] * c;
    x0 = Math.min(x0, X); x1 = Math.max(x1, X); y0 = Math.min(y0, Y); y1 = Math.max(y1, Y);
  }
  const span = Math.max(x1 - x0, y1 - y0, 60);
  const pw = box.w * (1 - 2 * pad), ph = box.h * (1 - 2 * pad);
  const sc = Math.min(pw / Math.max(x1 - x0, span * 0.02, 30), ph / Math.max(y1 - y0, span * 0.02, 30));
  const cx = (x0 + x1) / 2, cy = (y0 + y1) / 2, ox = box.x + box.w / 2, oy = box.y + box.h / 2;
  const P = (x, y) => { const X = x * c + y * s, Y = -x * s + y * c; return [ox + (X - cx) * sc, oy - (Y - cy) * sc]; };
  // DOMMatrix: [a c e; b d f] → ekran = M · (x, y)
  const M = new DOMMatrix();
  M.a = c * sc; M.c = s * sc; M.e = ox - cx * sc;
  M.b = s * sc; M.d = -c * sc; M.f = oy + cy * sc;
  // görünür alan (metre) — dönen kutunun kapsayanı
  const inv = M.inverse(), pts = [[box.x, box.y], [box.x + box.w, box.y], [box.x, box.y + box.h], [box.x + box.w, box.y + box.h]].map(([X, Y]) => inv.transformPoint(new DOMPoint(X, Y)));
  const view = [Math.min(...pts.map(p => p.x)), Math.min(...pts.map(p => p.y)), Math.max(...pts.map(p => p.x)), Math.max(...pts.map(p => p.y))];
  return { P, sc, M, view };
}

// Fotoğraf EXIF zamanı (JPEG). Dönüş: ms veya null
export async function photoTime(file) {
  try {
    const buf = new DataView(await file.slice(0, 256 * 1024).arrayBuffer());
    if (buf.getUint16(0) !== 0xFFD8) return null;
    let o = 2;
    while (o < buf.byteLength - 4) {
      const mk = buf.getUint16(o), len = buf.getUint16(o + 2);
      if (mk === 0xFFE1 && buf.getUint32(o + 4) === 0x45786966) return readExif(buf, o + 10);
      o += 2 + len;
    }
  } catch {}
  return null;
}
function readExif(v, t) {
  const le = v.getUint16(t) === 0x4949, u16 = o => v.getUint16(t + o, le), u32 = o => v.getUint32(t + o, le);
  const str = (o, n) => { let s = ''; for (let i = 0; i < n; i++) { const c = v.getUint8(t + o + i); if (!c) break; s += String.fromCharCode(c); } return s; };
  const ifd = (o, want) => { const out = {}; const n = u16(o); for (let i = 0; i < n; i++) { const e = o + 2 + i * 12, tag = u16(e); if (want.includes(tag)) { const cnt = u32(e + 4); out[tag] = { type: u16(e + 2), cnt, off: cnt > 4 ? u32(e + 8) : e + 8 }; } } return out; };
  const ifd0 = ifd(u32(4), [0x8769, 0x0132]);
  let date = null, offs = null;
  if (ifd0[0x8769]) {
    const exOff = u32(ifd0[0x8769].off);
    const e2 = ifd(exOff, [0x9003, 0x9011]);
    if (e2[0x9003]) date = str(e2[0x9003].off, 19);
    if (e2[0x9011]) offs = str(e2[0x9011].off, 6);
  }
  if (!date && ifd0[0x0132]) date = str(ifd0[0x0132].off, 19);
  if (!date) return null;
  const m = date.match(/(\d{4}):(\d\d):(\d\d) (\d\d):(\d\d):(\d\d)/); if (!m) return null;
  const iso = `${m[1]}-${m[2]}-${m[3]}T${m[4]}:${m[5]}:${m[6]}${offs && /^[+-]\d\d:\d\d$/.test(offs) ? offs : ''}`;
  const ms = Date.parse(iso);
  return isFinite(ms) ? ms : null;
}
