// GPX okuma, video zamanına hizalama ve otomatik eşitleme.
const R_EARTH = 6371008.8;
const toRad = d => d * Math.PI / 180;

function haversine(aLat, aLon, bLat, bLon) {
  const dLat = toRad(bLat - aLat), dLon = toRad(bLon - aLon);
  const x = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(aLat)) * Math.cos(toRad(bLat)) * Math.sin(dLon / 2) ** 2;
  return 2 * R_EARTH * Math.asin(Math.min(1, Math.sqrt(x)));
}
function bearing(aLat, aLon, bLat, bLon) {
  const y = Math.sin(toRad(bLon - aLon)) * Math.cos(toRad(bLat));
  const x = Math.cos(toRad(aLat)) * Math.sin(toRad(bLat)) - Math.sin(toRad(aLat)) * Math.cos(toRad(bLat)) * Math.cos(toRad(bLon - aLon));
  return (Math.atan2(y, x) * 180 / Math.PI + 360) % 360;
}
const median = a => { const s = [...a].sort((x, y) => x - y); return s.length ? s[s.length >> 1] : NaN; };

export function parseGpx(text) {
  const doc = new DOMParser().parseFromString(text, 'application/xml');
  if (doc.getElementsByTagName('parsererror').length) throw new Error('GPX dosyası okunamadı (bozuk XML).');
  const nodes = [...doc.getElementsByTagName('trkpt')];
  if (!nodes.length) nodes.push(...doc.getElementsByTagName('rtept'));
  const pts = [];
  for (const n of nodes) {
    const lat = parseFloat(n.getAttribute('lat')), lon = parseFloat(n.getAttribute('lon'));
    const timeEl = [...n.children].find(c => c.localName === 'time');
    if (!isFinite(lat) || !isFinite(lon) || !timeEl) continue;
    const t = Date.parse(timeEl.textContent.trim()); if (!isFinite(t)) continue;
    const eleEl = [...n.children].find(c => c.localName === 'ele');
    let spd = null;
    for (const el of n.getElementsByTagName('*')) if (el.localName === 'speed') { const v = parseFloat(el.textContent); if (isFinite(v) && v >= 0) spd = v; }
    pts.push({ t, lat, lon, ele: eleEl ? parseFloat(eleEl.textContent) : NaN, spd });
  }
  if (pts.length < 2) throw new Error('GPX dosyasında zaman bilgisi olan yeterli nokta yok.');
  pts.sort((a, b) => a.t - b.t);
  const name = doc.querySelector('trk > name, metadata > name')?.textContent?.trim() || '';
  return buildTrack(pts, name);
}

export function buildTrack(pts, name) {
  const n = pts.length;
  const t = new Float64Array(n), lat = new Float64Array(n), lon = new Float64Array(n), ele = new Float32Array(n);
  const spd = new Float32Array(n), course = new Float32Array(n), dist = new Float64Array(n);
  pts.forEach((p, i) => { t[i] = p.t; lat[i] = p.lat; lon[i] = p.lon; ele[i] = p.ele; });
  // mesafe ve konumdan hız
  const dSpd = new Float32Array(n);
  for (let i = 1; i < n; i++) dist[i] = dist[i - 1] + haversine(lat[i - 1], lon[i - 1], lat[i], lon[i]);
  for (let i = 0; i < n; i++) {
    const a = Math.max(0, i - 1), b = Math.min(n - 1, i + 1), dt = (t[b] - t[a]) / 1000;
    dSpd[i] = dt > 0 && dt < 10 ? (dist[b] - dist[a]) / dt : 0;
  }
  // cihazın kaydettiği hız: birimi (m/s mi km/h mi) konumdan hesaplanan hızla karşılaştırarak bul
  const withSpd = pts.filter(p => p.spd !== null).length > n * 0.5;
  let unit = 'konum';
  if (withSpd) {
    const ratios = []; for (let i = 0; i < n; i++) if (pts[i].spd > 0.5 && dSpd[i] > 2) ratios.push(pts[i].spd / dSpd[i]);
    const r = median(ratios);
    const k = !isFinite(r) ? 1 : r > 2.5 && r < 5 ? 1 / 3.6 : r > 1.6 && r < 2.6 ? 1 / 2.23694 : 1;
    unit = k === 1 ? 'm/s' : k < 0.3 ? 'km/h' : 'mph';
    for (let i = 0; i < n; i++) spd[i] = pts[i].spd !== null ? pts[i].spd * k : dSpd[i];
  } else spd.set(dSpd);
  // yön: en az 8 m ilerleyince güncellenir, yavaşken son geçerli yön korunur
  let last = NaN, j = 0;
  for (let i = 0; i < n; i++) {
    while (j < n - 1 && dist[j] - dist[i] < 8) j++;
    if (dist[j] - dist[i] >= 8 && spd[i] > 1.4) last = bearing(lat[i], lon[i], lat[j], lon[j]);
    course[i] = last;
  }
  // harita için yerel metrik izdüşüm
  const lat0 = (Math.min(...lat) + Math.max(...lat)) / 2, lon0 = (Math.min(...lon) + Math.max(...lon)) / 2;
  const kx = R_EARTH * Math.cos(toRad(lat0)) * Math.PI / 180, ky = R_EARTH * Math.PI / 180;
  const x = new Float32Array(n), y = new Float32Array(n);
  for (let i = 0; i < n; i++) { x[i] = (lon[i] - lon0) * kx; y[i] = (lat[i] - lat0) * ky; }
  const hasEle = [...ele].filter(isFinite).length > n * 0.5;
  let eMin = Infinity, eMax = -Infinity; for (const e of ele) if (isFinite(e)) { eMin = Math.min(eMin, e); eMax = Math.max(eMax, e); }
  let vMax = 0; for (const v of spd) vMax = Math.max(vMax, v);
  return { name, n, t, lat, lon, ele, spd, course, dist, x, y, hasEle, eMin, eMax, vMax, unit,
    start: t[0], end: t[n - 1], total: dist[n - 1] };
}

// Video zamanı (sn) → GPX mutlak zamanı (ms): base + (tv - offset)*1000
export function gpsAt(g, base, offset, tv) {
  const T = base + (tv - offset) * 1000;
  if (T < g.start - 1500 || T > g.end + 1500) return { valid: false, T };
  let lo = 0, hi = g.n - 1;
  while (hi - lo > 1) { const m = (lo + hi) >> 1; if (g.t[m] <= T) lo = m; else hi = m; }
  if (T <= g.t[0]) hi = lo = 0; else if (T >= g.t[g.n - 1]) lo = hi = g.n - 1;
  const gap = (g.t[hi] - g.t[lo]) / 1000;
  if (gap > 6) return { valid: false, T, i: lo };
  const a = hi === lo ? 0 : (T - g.t[lo]) / (g.t[hi] - g.t[lo]);
  const L = arr => arr[lo] * (1 - a) + arr[hi] * a;
  let c0 = g.course[lo], c1 = g.course[hi], crs = c0;
  if (isFinite(c0) && isFinite(c1)) { let d = ((c1 - c0 + 540) % 360) - 180; crs = (c0 + d * a + 360) % 360; }
  return { valid: true, T, i: lo, a, lat: L(g.lat), lon: L(g.lon), ele: L(g.ele), speed: L(g.spd), course: crs,
    dist: L(g.dist), x: L(g.x), y: L(g.y), maxSpeed: maxUpTo(g, lo) };
}
function maxUpTo(g, i) {
  if (!g._cmax) { g._cmax = new Float32Array(g.n); let m = 0; for (let k = 0; k < g.n; k++) { m = Math.max(m, g.spd[k]); g._cmax[k] = m; } }
  return g._cmax[i];
}

// Kapsama: video [0, dur] aralığının ne kadarı GPX ile örtüşüyor
export function coverage(g, base, offset, dur) {
  const a = Math.max(0, (g.start - base) / 1000 + offset), b = Math.min(dur, (g.end - base) / 1000 + offset);
  return Math.max(0, b - a) / dur;
}

// Otomatik eşitleme: GPS hız değişimi (G) ile GoPro ileri-geri ivmesini karşılaştırır.
// tel.lon: 100 Hz, G cinsinden. Dönüş: { offset, score, overlap } ya da null
export function autoSync(g, base, tel, { range = 120, step = 0.1 } = {}) {
  const HZ = 10;
  // GoPro: 10 Hz, 1 sn yumuşatılmış
  const vN = Math.floor(tel.lon.length / 10);
  const vid = new Float32Array(vN);
  for (let i = 0; i < vN; i++) { let s = 0, c = 0; for (let k = -50; k < 50; k++) { const j = i * 10 + k; if (j >= 0 && j < tel.lon.length) { s += tel.lon[j]; c++; } } vid[i] = s / c; }
  // GPS: 10 Hz hız → türev (G)
  const gN = Math.floor((g.end - g.start) / 1000 * HZ);
  if (gN < 50) return null;
  const v = new Float32Array(gN), ok = new Uint8Array(gN);
  let j = 0;
  for (let i = 0; i < gN; i++) {
    const T = g.start + i * 1000 / HZ;
    while (j < g.n - 2 && g.t[j + 1] <= T) j++;
    const gap = (g.t[j + 1] - g.t[j]) / 1000;
    const a = Math.min(1, Math.max(0, (T - g.t[j]) / (g.t[j + 1] - g.t[j])));
    v[i] = g.spd[j] * (1 - a) + g.spd[j + 1] * a; ok[i] = gap <= 3 ? 1 : 0;
  }
  const acc = new Float32Array(gN);
  for (let i = 0; i < gN; i++) { const a = Math.max(0, i - 5), b = Math.min(gN - 1, i + 5); acc[i] = (v[b] - v[a]) / ((b - a) / HZ) / 9.80665; }
  const g0 = (g.start - base) / 1000; // GPX başlangıcının video zamanındaki yeri (offset = 0 için)
  let best = null; const minOverlap = Math.min(15, vN / HZ * 0.6) * HZ;
  for (let off = -range; off <= range + 1e-9; off += step) {
    // video örneği i (zaman i/HZ) ↔ GPX indeksi (i/HZ - off - g0) * HZ
    const shift = Math.round((-off - g0) * HZ);
    let n = 0, sx = 0, sy = 0, sxx = 0, syy = 0, sxy = 0;
    const i0 = Math.max(0, -shift), i1 = Math.min(vN, gN - shift);
    for (let i = i0; i < i1; i++) {
      const k = i + shift; if (!ok[k]) continue;
      const x = vid[i], y = acc[k]; n++; sx += x; sy += y; sxx += x * x; syy += y * y; sxy += x * y;
    }
    if (n < minOverlap) continue;
    const cov = sxy - sx * sy / n, vx = sxx - sx * sx / n, vy = syy - sy * sy / n;
    if (vx <= 1e-9 || vy <= 1e-9) continue;
    const r = cov / Math.sqrt(vx * vy);
    if (!best || r > best.score) best = { offset: Math.round(off * 10) / 10 + 0, score: r, overlap: n / HZ };
  }
  return best;
}
