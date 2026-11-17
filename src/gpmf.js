// GoPro GPMF okuyucu: MP4 içindeki 'gpmd' veri izini dosyanın tamamını belleğe almadan okur
// ve yatış/eğim/G-kuvveti/dönüş hızı serilerini hesaplar.

const CONTAINERS = new Set(['moov', 'trak', 'mdia', 'minf', 'stbl', 'edts', 'dinf']);

async function bytes(file, pos, len) {
  return new Uint8Array(await file.slice(pos, pos + len).arrayBuffer());
}
const u32 = (b, o) => ((b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]) >>> 0;
const u64 = (b, o) => u32(b, o) * 4294967296 + u32(b, o + 4);
const str4 = (b, o) => String.fromCharCode(b[o], b[o + 1], b[o + 2], b[o + 3]);

async function findMoov(file) {
  let pos = 0;
  while (pos + 8 <= file.size) {
    const h = await bytes(file, pos, 16);
    let size = u32(h, 0); const type = str4(h, 4); let hdr = 8;
    if (size === 1) { size = u64(h, 8); hdr = 16; } else if (size === 0) size = file.size - pos;
    if (size < 8) break;
    if (type === 'moov') return bytes(file, pos, size);
    pos += size;
  }
  throw new Error('MP4 yapısı okunamadı (moov bulunamadı).');
}

function boxes(b, start, end) {
  const out = []; let p = start;
  while (p + 8 <= end) {
    let size = u32(b, p); const type = str4(b, p + 4); let hdr = 8;
    if (size === 1) { size = u64(b, p + 8); hdr = 16; } else if (size === 0) size = end - p;
    if (size < 8 || p + size > end) break;
    out.push({ type, start: p, data: p + hdr, end: p + size });
    p += size;
  }
  return out;
}
function child(b, box, type) { return boxes(b, box.data, box.end).find(x => x.type === type); }
function path(b, box, ...types) {
  let cur = box;
  for (const t of types) { if (!cur) return null; cur = child(b, cur, t); }
  return cur;
}

function parseTrak(b, trak) {
  const mdia = child(b, trak, 'mdia'); if (!mdia) return null;
  const hdlr = child(b, mdia, 'hdlr'); const mdhd = child(b, mdia, 'mdhd');
  const stbl = path(b, mdia, 'minf', 'stbl'); if (!stbl || !mdhd) return null;
  const v = b[mdhd.data];
  const timescale = v === 1 ? u32(b, mdhd.data + 20) : u32(b, mdhd.data + 12);
  const stsd = child(b, stbl, 'stsd');
  // edit list: medyanın sunum zamanına kaydırması (saniye)
  let mediaStart = 0; const elst = path(b, trak, 'edts', 'elst');
  if (elst) {
    const ev = b[elst.data], n = u32(b, elst.data + 4);
    for (let i = 0; i < n; i++) {
      const o = elst.data + 8 + i * (ev ? 20 : 12);
      const mt = ev ? u64(b, o + 8) : (u32(b, o + 4) | 0);
      if (mt >= 0 && mt < 4294967295) { mediaStart = mt / timescale; break; }
    }
  }
  const format = stsd ? str4(b, stsd.data + 12) : '';
  return { handler: hdlr ? str4(b, hdlr.data + 8) : '', format, timescale, stbl, mediaStart };
}

function sampleTable(b, stbl) {
  const stsz = child(b, stbl, 'stsz'), stsc = child(b, stbl, 'stsc'), stts = child(b, stbl, 'stts');
  const stco = child(b, stbl, 'stco'), co64 = child(b, stbl, 'co64');
  const fixed = u32(b, stsz.data + 4), n = u32(b, stsz.data + 8);
  const sizes = []; for (let i = 0; i < n; i++) sizes.push(fixed || u32(b, stsz.data + 12 + i * 4));
  const chunks = [];
  if (stco) { const c = u32(b, stco.data + 4); for (let i = 0; i < c; i++) chunks.push(u32(b, stco.data + 8 + i * 4)); }
  else { const c = u32(b, co64.data + 4); for (let i = 0; i < c; i++) chunks.push(u64(b, co64.data + 8 + i * 8)); }
  const sc = []; const scn = u32(b, stsc.data + 4);
  for (let i = 0; i < scn; i++) sc.push([u32(b, stsc.data + 8 + i * 12), u32(b, stsc.data + 12 + i * 12)]);
  const offsets = []; let s = 0;
  for (let c = 0; c < chunks.length && s < n; c++) {
    let per = 0; for (const [first, cnt] of sc) if (c + 1 >= first) per = cnt;
    let off = chunks[c];
    for (let k = 0; k < per && s < n; k++, s++) { offsets.push(off); off += sizes[s]; }
  }
  const times = [], durs = []; let t = 0; const en = u32(b, stts.data + 4);
  for (let i = 0; i < en; i++) {
    const cnt = u32(b, stts.data + 8 + i * 8), d = u32(b, stts.data + 12 + i * 8);
    for (let k = 0; k < cnt; k++) { times.push(t); durs.push(d); t += d; }
  }
  return { sizes, offsets, times, durs };
}

// --- GPMF KLV ---
const TYPES = { b: [1, 'getInt8'], B: [1, 'getUint8'], s: [2, 'getInt16'], S: [2, 'getUint16'], l: [4, 'getInt32'], L: [4, 'getUint32'], f: [4, 'getFloat32'], d: [8, 'getFloat64'] };
const WANT = new Set(['ACCL', 'GYRO', 'GRAV']);

function parseGpmf(buf, t0, t1, acc, info) {
  const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  const walk = (start, end, ctx) => {
    let p = start;
    while (p + 8 <= end) {
      const key = String.fromCharCode(buf[p], buf[p + 1], buf[p + 2], buf[p + 3]);
      const type = String.fromCharCode(buf[p + 4]); const ss = buf[p + 5]; const rep = dv.getUint16(p + 6);
      const size = ss * rep; const d = p + 8; p = d + Math.ceil(size / 4) * 4;
      if (buf[d - 4] === 0) { walk(d, d + size, key === 'STRM' ? {} : ctx); continue; }
      if (key === 'DVNM' && !info.device) info.device = new TextDecoder().decode(buf.subarray(d, d + size)).replace(/\0.*$/, '');
      else if (key === 'SCAL') {
        const [n, fn] = TYPES[type]; const c = size / n; ctx.scal = [];
        for (let i = 0; i < c; i++) ctx.scal.push(dv[fn](d + i * n));
      } else if (key === 'ORIN') ctx.orin = new TextDecoder().decode(buf.subarray(d, d + size));
      else if (WANT.has(key) && TYPES[type]) {
        const [n, fn] = TYPES[type]; const per = ss / n; const sc = ctx.scal || [1];
        const series = acc[key] || (acc[key] = { t: [], v: [], orin: null });
        if (ctx.orin) series.orin = ctx.orin;
        for (let r = 0; r < rep; r++) {
          const row = [];
          for (let k = 0; k < per; k++) row.push(dv[fn](d + (r * per + k) * n) / (sc.length === per ? sc[k] : sc[0]));
          series.v.push(row); series.t.push(t0 + (t1 - t0) * (r + 0.5) / rep);
        }
      }
    }
  };
  walk(0, buf.length, {});
}

export async function readGoProTelemetry(file, onProgress = () => {}) {
  const moov = await findMoov(file);
  const top = { data: 8, end: moov.length };
  const mvhd = child(moov, top, 'mvhd');
  let created = null;
  if (mvhd) {
    const v = moov[mvhd.data];
    const secs = v === 1 ? u64(moov, mvhd.data + 4) : u32(moov, mvhd.data + 4);
    if (secs > 0) created = new Date((secs - 2082844800) * 1000);
  }
  const traks = boxes(moov, 8, moov.length).filter(x => x.type === 'trak').map(t => parseTrak(moov, t)).filter(Boolean);
  const meta = traks.find(t => t.format === 'gpmd');
  if (!meta) return { found: false, created };
  const tab = sampleTable(moov, meta.stbl);
  const vid = traks.find(t => t.handler === 'vide');
  const shift = meta.mediaStart - (vid ? vid.mediaStart : 0);
  const acc = {}; const info = {};
  for (let i = 0; i < tab.sizes.length; i++) {
    const buf = await bytes(file, tab.offsets[i], tab.sizes[i]);
    const t0 = tab.times[i] / meta.timescale - shift, t1 = (tab.times[i] + tab.durs[i]) / meta.timescale - shift;
    parseGpmf(buf, t0, t1, acc, info);
    onProgress((i + 1) / tab.sizes.length);
  }
  if (!acc.ACCL && !acc.GRAV) return { found: false, created, device: info.device };
  return { found: true, created, device: info.device || 'GoPro', ...computeSeries(acc) };
}

// --- Hesaplama: 100 Hz düzenli zaman ızgarası ---
const HZ = 100;
function resample(series, col, grid) {
  const t = series.t, v = series.v, out = new Float32Array(grid.length); let j = 0;
  for (let i = 0; i < grid.length; i++) {
    const x = grid[i];
    while (j < t.length - 2 && t[j + 1] < x) j++;
    if (x <= t[0]) out[i] = v[0][col];
    else if (x >= t[t.length - 1]) out[i] = v[t.length - 1][col];
    else { const a = (x - t[j]) / (t[j + 1] - t[j]); out[i] = v[j][col] * (1 - a) + v[j + 1][col] * a; }
  }
  return out;
}
function smooth(x, n) {
  if (n < 2) return x;
  const out = new Float32Array(x.length), h = n >> 1; let s = 0; const q = [];
  // ortalanmış hareketli ortalama (kenarlarda tekrar)
  const at = i => x[Math.min(x.length - 1, Math.max(0, i))];
  for (let i = -h; i <= h; i++) s += at(i);
  for (let i = 0; i < x.length; i++) { out[i] = s / (2 * h + 1); s += at(i + h + 1) - at(i - h); }
  return out;
}

function computeSeries(acc) {
  const src = acc.GRAV || acc.ACCL;
  const end = Math.max(...[acc.ACCL, acc.GRAV, acc.GYRO].filter(Boolean).map(s => s.t[s.t.length - 1]));
  const N = Math.max(2, Math.ceil(end * HZ) + 1);
  const grid = new Float32Array(N); for (let i = 0; i < N; i++) grid[i] = i / HZ;  // t = 0: videonun ilk karesi

  // ACCL eksen sırası (varsayılan ZXY): sütun0 = dikey, sütun1 = yanal, sütun2 = ileri/geri
  let a0, a1, a2;
  if (acc.ACCL) {
    a0 = resample(acc.ACCL, 0, grid).map(v => v / 9.80665);
    a1 = resample(acc.ACCL, 1, grid).map(v => v / 9.80665);
    a2 = resample(acc.ACCL, 2, grid).map(v => v / 9.80665);
  }
  // Yukarı vektörü (GRAV düzeninde): g0 = + sağa yatık, g1 = dikey, g2 = + burun aşağı
  let g0, g1, g2;
  if (acc.GRAV) { g0 = resample(acc.GRAV, 0, grid); g1 = resample(acc.GRAV, 1, grid); g2 = resample(acc.GRAV, 2, grid); }
  else {
    g0 = smooth(a1, HZ); g1 = smooth(a0, HZ); g2 = smooth(a2, HZ);
    for (let i = 0; i < N; i++) { const m = Math.hypot(g0[i], g1[i], g2[i]) || 1; g0[i] /= m; g1[i] /= m; g2[i] /= m; }
  }
  const D = 180 / Math.PI;
  let yaw = new Float32Array(N);
  if (acc.GYRO) yaw = smooth(resample(acc.GYRO, 0, grid).map(v => v * D), 13);
  const tel = { hz: HZ, duration: end, yaw, hasAccel: !!a0, hasGyro: !!acc.GYRO, hasImu: true,
    raw: { g0, g1, g2, ax: a1 || null, ay: a0 || null, az: a2 || null }, ref: null };
  applyCalibration(tel, null);
  return tel;
}

/** Kamera eğik takılmış olabilir: "motor düzken" ölçülen yerçekimi yönünü referans alarak
 *  yatış/eğim ve G-kuvveti eksenlerini motora göre hesaplar. ref = null → kameranın kendi ekseni. */
export function applyCalibration(tel, ref) {
  const { g0, g1, g2, ax, ay, az } = tel.raw, N = g0.length, D = 180 / Math.PI;
  const norm = v => { const m = Math.hypot(...v) || 1; return v.map(x => x / m); };
  const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
  const u = norm(ref || [0, 1, 0]);
  const ex = [1, 0, 0], ez = [0, 0, 1];
  const l = norm(ex.map((x, k) => x - dot(ex, u) * u[k]));
  const f = norm(ez.map((x, k) => x - dot(ez, u) * u[k] - dot(ez, l) * l[k]));
  const roll = new Float32Array(N), pitch = new Float32Array(N);
  let lat = new Float32Array(N), lon = new Float32Array(N);
  for (let i = 0; i < N; i++) {
    const g = [g0[i], g1[i], g2[i]], gu = dot(g, u), gl = dot(g, l), gf = dot(g, f);
    roll[i] = Math.atan2(gl, Math.hypot(gu, gf)) * D;       // + sağa yatış (eğik montajda da doğru)
    pitch[i] = -Math.atan2(gf, Math.hypot(gu, gl)) * D;     // + burun yukarı
    if (ax) { const lin = [ax[i] - g[0], ay[i] - g[1], az[i] - g[2]]; lat[i] = -dot(lin, l); lon[i] = -dot(lin, f); }
  }
  lat = smooth(lat, 27); lon = smooth(lon, 27);
  const maxL = new Float32Array(N), maxR = new Float32Array(N), maxG = new Float32Array(N);
  let mL = 0, mR = 0, mG = 0;
  for (let i = 0; i < N; i++) {
    mL = Math.max(mL, -roll[i]); mR = Math.max(mR, roll[i]); mG = Math.max(mG, Math.hypot(lat[i], lon[i]));
    maxL[i] = mL; maxR[i] = mR; maxG[i] = mG;
  }
  Object.assign(tel, { roll, pitch, lat, lon, maxL, maxR, maxG, ref: ref ? u : null });
  return tel;
}

/** t saniyesinde (±0,5 sn ortalama) motoru "düz" kabul et ve açıları buna göre sıfırla */
export function calibrateAt(tel, t, win = 0.5) {
  const { g0, g1, g2 } = tel.raw, N = g0.length;
  const i0 = Math.max(0, Math.floor((t - win) * tel.hz)), i1 = Math.min(N - 1, Math.ceil((t + win) * tel.hz));
  const v = [0, 0, 0]; for (let i = i0; i <= i1; i++) { v[0] += g0[i]; v[1] += g1[i]; v[2] += g2[i]; }
  return applyCalibration(tel, v);
}

export function sampleAt(tel, t) {
  const N = tel.roll.length; const x = Math.min(N - 1, Math.max(0, t * tel.hz));
  const i = Math.floor(x), j = Math.min(N - 1, i + 1), a = x - i;
  const L = arr => arr[i] * (1 - a) + arr[j] * a;
  return { t, roll: L(tel.roll), pitch: L(tel.pitch), lat: L(tel.lat), lon: L(tel.lon), yaw: L(tel.yaw), maxL: tel.maxL[i], maxR: tel.maxR[i], maxG: tel.maxG[i], i };
}

// Sensör verisi olmayan videolar (DJI, telefon vb.) için boş seri: yalnızca GPS göstergeleri kullanılır
export function emptyTelemetry(duration) {
  const N = Math.max(2, Math.ceil(duration * HZ) + 1), z = () => new Float32Array(N);
  return { hz: HZ, duration, roll: z(), pitch: z(), lat: z(), lon: z(), yaw: z(), maxL: z(), maxR: z(), maxG: z(), hasAccel: false, hasGyro: false, hasImu: false };
}
