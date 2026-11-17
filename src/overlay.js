// Telemetri göstergeleri. Tasarım birimleri 4K (3840x2160) içindir; k ölçeğiyle her çözünürlüğe uyar.
import { sampleAt } from './gpmf.js';
import { gpsAt } from './gpx.js';

export const ACCENTS = { turuncu: '#FF7A1A', mavi: '#29D3FF', yesil: '#50E68C', kirmizi: '#FF4D5E', sari: '#FFD23F', beyaz: '#F2F4F8' };
export const THEMES = { panel: 'Koyu panel', cam: 'Cam', minimal: 'Minimal' };

// Göstergeler: x,y = 0..1 arası konum (0 sol/üst, 1 sağ/alt). needs: 'gps' | 'accel' | 'imu'
export const GAUGES = {
  lean:     { name: 'Yatış açısı', needs: 'imu', styles: { bike: 'Motor', arc: 'Yay' }, def: { on: true, x: 0, y: 1 } },
  speed:    { name: 'Hız', needs: 'gps', styles: { dial: 'Kadran', digital: 'Dijital' }, def: { on: true, x: 0.5, y: 1 } },
  gforce:   { name: 'G-kuvveti', needs: 'accel', def: { on: true, x: 1, y: 1 } },
  map:      { name: 'Rota', needs: 'gps', def: { on: true, x: 1, y: 0.42 } },
  alt:      { name: 'İrtifa', needs: 'gps', def: { on: false, x: 0, y: 0.5 } },
  compass:  { name: 'Pusula', needs: 'gps', def: { on: true, x: 0.5, y: 0 } },
  attitude: { name: 'Eğim / ufuk', needs: 'imu', def: { on: true, x: 0, y: 0 } },
  chart:    { name: 'Grafik (10 sn)', needs: 'imu', def: { on: false, x: 0.5, y: 0.55 } },
  clock:    { name: 'Saat', def: { on: true, x: 1, y: 0 } },
};
const SIZES = {
  lean: s => s === 'arc' ? [760, 500] : [760, 560], gforce: () => [760, 500], attitude: () => [760, 300], clock: () => [760, 150],
  speed: s => s === 'digital' ? [600, 300] : [540, 540], map: () => [480, 480], alt: () => [600, 280],
  compass: () => [900, 180], chart: () => [1000, 300],
};

export const DEFAULTS = {
  size: 100, opacity: 78, accent: 'turuncu', theme: 'panel', leanRange: 45, gRange: 0.5,
  g: Object.fromEntries(Object.entries(GAUGES).map(([k, v]) => [k, { scale: 100, style: v.styles ? Object.keys(v.styles)[0] : null, ...v.def }])),
};
export function mergeOpts(saved) {
  const o = { ...DEFAULTS, ...(saved || {}), g: {} };
  for (const k of Object.keys(GAUGES)) o.g[k] = { ...DEFAULTS.g[k], ...(saved?.g?.[k] || {}) };
  return o;
}

const FONT = '-apple-system, BlinkMacSystemFont, "SF Pro Display", "Segoe UI", Inter, Roboto, "Helvetica Neue", Arial, sans-serif';
const WHITE = '#fff', GREY = 'rgba(255,255,255,.6)', DIM = 'rgba(255,255,255,.16)', GREEN = '#50E68C', RED = '#FF4D5E', CYAN = '#29D3FF';
const rad = d => d * Math.PI / 180;
const fmt = (v, d = 0) => Math.abs(v).toFixed(d).replace('.', ',');
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const dash = '—';

function rr(ctx, x, y, w, h, r) {
  ctx.beginPath(); ctx.moveTo(x + r, y); ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath();
}
function panel(ctx, w, h, o) {
  if (o.theme === 'minimal') { ctx.shadowColor = 'rgba(0,0,0,.75)'; ctx.shadowBlur = 14; return; }
  rr(ctx, 0, 0, w, h, 36);
  const a = o.opacity / 100;
  if (o.theme === 'cam') {
    ctx.fillStyle = `rgba(255,255,255,${0.06 + a * 0.16})`; ctx.fill();
    ctx.lineWidth = 2.5; ctx.strokeStyle = 'rgba(255,255,255,.32)'; ctx.stroke();
    ctx.shadowColor = 'rgba(0,0,0,.45)'; ctx.shadowBlur = 8;
  } else {
    ctx.fillStyle = `rgba(12,14,20,${a})`; ctx.fill();
    ctx.lineWidth = 2; ctx.strokeStyle = 'rgba(255,255,255,.16)'; ctx.stroke();
  }
}
function text(ctx, s, x, y, size, weight = 600, color = WHITE, align = 'left', base = 'alphabetic') {
  ctx.font = `${weight} ${size}px ${FONT}`; ctx.fillStyle = color; ctx.textAlign = align; ctx.textBaseline = base;
  ctx.fillText(s, x, y);
}
const label = (ctx, s, x, y, align = 'left') => text(ctx, s.toLocaleUpperCase('tr-TR'), x, y, 30, 600, GREY, align);
const side = r => r > 0.5 ? 'SAĞ' : r < -0.5 ? 'SOL' : 'DÜZ';
function maxDots(ctx, s, RNG, at) {
  ctx.fillStyle = WHITE;
  for (const [m, sg] of [[s.maxL, -1], [s.maxR, 1]]) if (m > 0.5) { const [x, y] = at(sg * Math.min(m, RNG)); ctx.beginPath(); ctx.arc(x, y, 7, 0, 7); ctx.fill(); }
}

// ---------- Yatış: yay ----------
function leanArc(ctx, d, o, A) {
  const s = d.s, W = 760, H = 500, cx = W / 2, cy = 340, r = 250, RNG = o.leanRange;
  label(ctx, 'Yatış açısı', 40, 64);
  const ang = v => rad(-90 + v * 90 / RNG);
  ctx.lineCap = 'round'; ctx.lineWidth = 18; ctx.strokeStyle = DIM;
  ctx.beginPath(); ctx.arc(cx, cy, r, ang(-RNG), ang(RNG)); ctx.stroke();
  const v = clamp(s.roll, -RNG, RNG);
  if (Math.abs(v) > 0.3) { ctx.strokeStyle = A; ctx.beginPath(); ctx.arc(cx, cy, r, ang(Math.min(0, v)), ang(Math.max(0, v))); ctx.stroke(); }
  ctx.lineCap = 'butt'; ctx.lineWidth = 3; ctx.strokeStyle = GREY;
  for (let t = -RNG; t <= RNG + 0.01; t += RNG / 3) {
    const a = ang(t), r2 = Math.abs(t) < 0.01 || Math.abs(Math.abs(t) - RNG) < 0.01 ? r - 50 : r - 40;
    ctx.beginPath(); ctx.moveTo(cx + Math.cos(a) * (r - 30), cy + Math.sin(a) * (r - 30));
    ctx.lineTo(cx + Math.cos(a) * r2, cy + Math.sin(a) * r2); ctx.stroke();
  }
  text(ctx, `${RNG}°`, cx - r, cy + 58, 28, 500, GREY, 'center'); text(ctx, `${RNG}°`, cx + r, cy + 58, 28, 500, GREY, 'center');
  maxDots(ctx, s, RNG, a => [cx + Math.cos(ang(a)) * (r + 24), cy + Math.sin(ang(a)) * (r + 24)]);
  const a = ang(v); ctx.fillStyle = A; ctx.strokeStyle = WHITE; ctx.lineWidth = 5;
  ctx.beginPath(); ctx.arc(cx + Math.cos(a) * r, cy + Math.sin(a) * r, 17, 0, 7); ctx.fill(); ctx.stroke();
  text(ctx, `${fmt(s.roll)}°`, cx + 20, cy - 30, 130, 700, WHITE, 'center');
  text(ctx, side(s.roll), cx, cy + 18, 32, 700, A, 'center');
  text(ctx, `MAKS SOL  ${fmt(s.maxL)}°`, 40, H - 40, 28, 500, GREY);
  text(ctx, `MAKS SAĞ  ${fmt(s.maxR)}°`, W - 40, H - 40, 28, 500, GREY, 'right');
}

// ---------- Yatış: motor silüeti (TV yayını tarzı) ----------
function drawBike(ctx, A) {
  // arkadan görünüş (sürücüyle); (0,0) = lastiğin yere değdiği nokta, yukarı negatif
  const body = '#f4f5f7', dark = '#15171d';
  ctx.lineJoin = 'round'; ctx.lineCap = 'round';
  rr(ctx, -28, -140, 56, 140, 26); ctx.fillStyle = dark; ctx.fill(); ctx.lineWidth = 5; ctx.strokeStyle = body; ctx.stroke(); // lastik
  ctx.fillStyle = body;
  ctx.beginPath(); ctx.moveTo(-46, -128); ctx.lineTo(46, -128); ctx.lineTo(60, -190); ctx.lineTo(-60, -190); ctx.closePath(); ctx.fill(); // kuyruk
  ctx.fillStyle = RED; rr(ctx, -34, -176, 68, 16, 7); ctx.fill(); // stop lambası
  ctx.fillStyle = body;
  ctx.beginPath(); ctx.moveTo(-64, -196); ctx.lineTo(64, -196); ctx.lineTo(78, -228); ctx.lineTo(-78, -228); ctx.closePath(); ctx.fill(); // sele/depo
  ctx.strokeStyle = body; ctx.lineWidth = 10;
  ctx.beginPath(); ctx.moveTo(-132, -242); ctx.lineTo(132, -242); ctx.stroke(); // gidon
  ctx.fillStyle = body; rr(ctx, -170, -270, 46, 24, 10); ctx.fill(); rr(ctx, 124, -270, 46, 24, 10); ctx.fill(); // aynalar
  ctx.fillStyle = A;
  ctx.beginPath(); ctx.moveTo(-62, -226); ctx.lineTo(62, -226); ctx.lineTo(50, -332); ctx.lineTo(-50, -332); ctx.closePath(); ctx.fill(); // sürücü gövdesi
  ctx.strokeStyle = A; ctx.lineWidth = 20;
  ctx.beginPath(); ctx.moveTo(-46, -316); ctx.lineTo(-112, -248); ctx.moveTo(46, -316); ctx.lineTo(112, -248); ctx.stroke(); // kollar
  ctx.fillStyle = body; ctx.beginPath(); ctx.arc(0, -374, 42, 0, 7); ctx.fill(); // kask
  ctx.fillStyle = dark; rr(ctx, -30, -388, 60, 16, 8); ctx.fill();
}
function leanBike(ctx, d, o, A) {
  const s = d.s, W = 760, H = 560, cx = W / 2, cy = 430, r = 340, RNG = Math.min(o.leanRange, 60);
  label(ctx, 'Yatış', 40, 64);
  const at = (a, rr_) => [cx + Math.sin(rad(a)) * rr_, cy - Math.cos(rad(a)) * rr_];
  ctx.lineCap = 'round'; ctx.lineWidth = 14; ctx.strokeStyle = DIM;
  ctx.beginPath(); ctx.arc(cx, cy, r, rad(-90 - RNG), rad(-90 + RNG)); ctx.stroke();
  const v = clamp(s.roll, -RNG, RNG);
  if (Math.abs(v) > 0.3) { ctx.strokeStyle = A; ctx.beginPath(); ctx.arc(cx, cy, r, rad(-90 + Math.min(0, v)), rad(-90 + Math.max(0, v))); ctx.stroke(); }
  ctx.lineCap = 'butt'; ctx.strokeStyle = GREY; ctx.lineWidth = 3;
  for (let a = -RNG; a <= RNG + 0.01; a += 15) {
    const [x1, y1] = at(a, r - 24), [x2, y2] = at(a, r - (a % 30 === 0 ? 50 : 40));
    ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke();
    if (a !== 0 && a % 30 === 0) { const [lx, ly] = at(a, r + 30); text(ctx, `${Math.abs(a)}°`, lx, ly, 26, 500, GREY, 'center', 'middle'); }
  }
  ctx.strokeStyle = 'rgba(255,255,255,.25)'; ctx.lineWidth = 2; ctx.setLineDash([8, 10]);
  ctx.beginPath(); ctx.moveTo(cx, cy); ctx.lineTo(cx, cy - 310); ctx.stroke(); ctx.setLineDash([]);
  ctx.save(); ctx.translate(cx, cy); ctx.rotate(rad(s.roll)); ctx.scale(0.74, 0.74); drawBike(ctx, A); ctx.restore();
  ctx.fillStyle = WHITE; ctx.strokeStyle = '#15171d'; ctx.lineWidth = 3;
  for (const [m, sg] of [[s.maxL, -1], [s.maxR, 1]]) if (m > 0.5) { const [x, y] = at(sg * Math.min(m, RNG), r); ctx.beginPath(); ctx.arc(x, y, 9, 0, 7); ctx.fill(); ctx.stroke(); }
  ctx.strokeStyle = 'rgba(255,255,255,.12)'; ctx.lineWidth = 2; ctx.beginPath(); ctx.moveTo(40, cy + 8); ctx.lineTo(W - 40, cy + 8); ctx.stroke();
  text(ctx, `${fmt(s.roll)}°`, 40, H - 36, 96, 700);
  ctx.font = `700 96px ${FONT}`; const nw = ctx.measureText(`${fmt(s.roll)}°`).width;
  text(ctx, side(s.roll), 52 + nw, H - 40, 32, 700, A);
  text(ctx, `SOL ${fmt(s.maxL)}°`, W - 40, H - 76, 28, 500, GREY, 'right');
  text(ctx, `SAĞ ${fmt(s.maxR)}°`, W - 40, H - 38, 28, 500, GREY, 'right');
}

// ---------- G-kuvveti ----------
function gforce(ctx, d, o) {
  const { s, tel } = d, H = 500, cx = 225, cy = 262, r = 172, RNG = o.gRange;
  label(ctx, 'G-kuvveti', 40, 64);
  ctx.lineWidth = 2; ctx.strokeStyle = GREY; ctx.beginPath(); ctx.arc(cx, cy, r, 0, 7); ctx.stroke();
  ctx.strokeStyle = DIM; ctx.beginPath(); ctx.arc(cx, cy, r / 2, 0, 7); ctx.stroke();
  ctx.beginPath(); ctx.moveTo(cx - r, cy); ctx.lineTo(cx + r, cy); ctx.moveTo(cx, cy - r); ctx.lineTo(cx, cy + r); ctx.stroke();
  text(ctx, fmt(RNG / 2, 2), cx + 6, cy - r / 2 - 6, 24, 500, GREY); text(ctx, `${fmt(RNG, 1)} G`, cx + 6, cy - r - 6, 24, 500, GREY);
  const pos = (la, lo) => { let x = la / RNG, y = lo / RNG; const m = Math.hypot(x, y); if (m > 1) { x /= m; y /= m; } return [cx + x * r, cy - y * r]; };
  const n = Math.round(1.2 * tel.hz), i1 = s.i, i0 = Math.max(0, i1 - n);
  ctx.lineCap = 'round'; ctx.lineWidth = 5; let prev = null;
  for (let i = i0; i <= i1; i += 2) {
    const p = pos(tel.lat[i], tel.lon[i]);
    if (prev) { ctx.strokeStyle = `rgba(41,211,255,${0.8 * (i - i0) / (i1 - i0 + 1)})`; ctx.beginPath(); ctx.moveTo(...prev); ctx.lineTo(...p); ctx.stroke(); }
    prev = p;
  }
  const [px, py] = pos(s.lat, s.lon); ctx.fillStyle = CYAN; ctx.strokeStyle = WHITE; ctx.lineWidth = 4;
  ctx.beginPath(); ctx.arc(px, py, 16, 0, 7); ctx.fill(); ctx.stroke();
  const tx = 450, acc = s.lon >= 0;
  text(ctx, acc ? 'HIZLANMA' : 'FREN', tx, 150, 30, 700, acc ? GREEN : RED); text(ctx, `${fmt(s.lon, 2)} G`, tx, 220, 60, 700);
  text(ctx, 'YANAL', tx, 300, 30, 600, GREY); text(ctx, `${fmt(s.lat, 2)} G`, tx, 370, 60, 700);
  text(ctx, `MAKS  ${fmt(s.maxG, 2)} G`, 40, H - 40, 28, 500, GREY);
}

// ---------- Eğim / ufuk ----------
function attitude(ctx, d, o, A) {
  const s = d.s, cx = 160, cy = 150, r = 105, PX = 3;
  ctx.save(); ctx.beginPath(); ctx.arc(cx, cy, r, 0, 7); ctx.clip(); ctx.shadowBlur = 0;
  ctx.translate(cx, cy); ctx.rotate(rad(-s.roll));
  const off = -s.pitch * PX;
  ctx.fillStyle = 'rgba(60,130,200,.92)'; ctx.fillRect(-2 * r, -2 * r, 4 * r, 2 * r + off);
  ctx.fillStyle = 'rgba(150,95,50,.92)'; ctx.fillRect(-2 * r, off, 4 * r, 2 * r);
  ctx.strokeStyle = WHITE; ctx.lineWidth = 3; ctx.beginPath(); ctx.moveTo(-2 * r, off); ctx.lineTo(2 * r, off); ctx.stroke();
  ctx.strokeStyle = 'rgba(255,255,255,.6)'; ctx.lineWidth = 2;
  for (const p of [-20, -10, 10, 20]) { const y = off - p * PX, w = Math.abs(p) === 10 ? 30 : 45; ctx.beginPath(); ctx.moveTo(-w, y); ctx.lineTo(w, y); ctx.stroke(); }
  ctx.restore();
  ctx.strokeStyle = WHITE; ctx.lineWidth = 3; ctx.beginPath(); ctx.arc(cx, cy, r, 0, 7); ctx.stroke();
  ctx.strokeStyle = A; ctx.lineWidth = 6; ctx.lineCap = 'round';
  ctx.beginPath(); ctx.moveTo(cx - 55, cy); ctx.lineTo(cx - 18, cy); ctx.moveTo(cx + 18, cy); ctx.lineTo(cx + 55, cy); ctx.stroke();
  ctx.fillStyle = A; ctx.beginPath(); ctx.arc(cx, cy, 6, 0, 7); ctx.fill();
  const tx = 320;
  label(ctx, 'Eğim', tx, 66);
  const sign = s.pitch >= 0.5 ? '+' : s.pitch <= -0.5 ? '−' : '';
  text(ctx, `${sign}${fmt(s.pitch)}°`, tx, 134, 60, 700);
  text(ctx, s.pitch > 0.5 ? 'YUKARI' : s.pitch < -0.5 ? 'AŞAĞI' : 'DÜZ', tx + 190, 132, 28, 700, A);
  label(ctx, 'Dönüş hızı', tx, 196); text(ctx, `${fmt(s.yaw)}°/s`, tx, 262, 60, 700);
}

// ---------- Saat ----------
function clock(ctx, d) {
  const { s, meta } = d, W = 760;
  ctx.fillStyle = (Math.floor(s.t * 2) % 2 === 0) ? RED : 'rgba(255,77,94,.35)'; ctx.beginPath(); ctx.arc(51, 63, 11, 0, 7); ctx.fill();
  text(ctx, 'TELEMETRİ', 80, 74, 30, 700);
  text(ctx, `${meta.device || 'Kamera'}${d.gps ? ' · GPS' : ''}`, 80, 116, 26, 500, GREY);
  if (meta.created) {
    const dt = new Date(meta.created.getTime() + s.t * 1000);
    text(ctx, dt.toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit', second: '2-digit' }), W - 40, 92, 64, 600, WHITE, 'right');
  }
  const m = Math.floor(s.t / 60), sec = (s.t % 60).toFixed(1).padStart(4, '0').replace('.', ',');
  text(ctx, `${String(m).padStart(2, '0')}:${sec}`, W - 40, 128, 26, 500, GREY, 'right');
}

// ---------- Hız ----------
const speedScale = g => Math.max(60, Math.ceil(g.vMax * 3.6 / 20) * 20);
function speedDial(ctx, d, o, A) {
  const { p, gps } = d, W = 540, cx = 270, cy = 285, r = 210, MAX = speedScale(gps);
  const ang = v => rad(135 + 270 * clamp(v, 0, MAX) / MAX);
  ctx.lineCap = 'round'; ctx.lineWidth = 24; ctx.strokeStyle = DIM;
  ctx.beginPath(); ctx.arc(cx, cy, r, ang(0), ang(MAX)); ctx.stroke();
  const v = p.valid ? p.speed * 3.6 : 0;
  if (p.valid && v > 0.5) {
    const grad = ctx.createLinearGradient(cx - r, 0, cx + r, 0); grad.addColorStop(0, A); grad.addColorStop(1, '#ff3d6e');
    ctx.strokeStyle = grad; ctx.beginPath(); ctx.arc(cx, cy, r, ang(0), ang(v)); ctx.stroke();
  }
  const major = MAX > 160 ? 40 : 20;
  ctx.lineCap = 'butt';
  for (let k = 0; k <= MAX; k += 10) {
    const a = ang(k), mj = k % major === 0;
    ctx.strokeStyle = mj ? WHITE : GREY; ctx.lineWidth = mj ? 4 : 2;
    const r1 = r - 26, r2 = r - (mj ? 50 : 40);
    ctx.beginPath(); ctx.moveTo(cx + Math.cos(a) * r1, cy + Math.sin(a) * r1); ctx.lineTo(cx + Math.cos(a) * r2, cy + Math.sin(a) * r2); ctx.stroke();
    if (mj) text(ctx, `${k}`, cx + Math.cos(a) * (r - 72), cy + Math.sin(a) * (r - 72), 26, 600, GREY, 'center', 'middle');
  }
  if (p.valid && p.maxSpeed > 0) { const a = ang(p.maxSpeed * 3.6); ctx.fillStyle = WHITE; ctx.beginPath(); ctx.arc(cx + Math.cos(a) * (r + 28), cy + Math.sin(a) * (r + 28), 7, 0, 7); ctx.fill(); }
  text(ctx, p.valid ? `${Math.round(v)}` : dash, cx, cy + 34, 118, 700, WHITE, 'center');
  text(ctx, 'km/h', cx, cy + 82, 30, 600, GREY, 'center');
  text(ctx, `MAKS ${p.valid ? Math.round(p.maxSpeed * 3.6) : dash}`, 40, 515, 28, 500, GREY);
  text(ctx, p.valid ? `${fmt(p.dist / 1000, 1)} km` : '', W - 40, 515, 28, 500, GREY, 'right');
}
function speedDigital(ctx, d, o, A) {
  const { p, gps } = d, W = 600, MAX = speedScale(gps), v = p.valid ? p.speed * 3.6 : 0;
  label(ctx, 'Hız', 40, 64);
  text(ctx, p.valid ? `${Math.round(v)}` : dash, 40, 200, 170, 700);
  text(ctx, 'km/h', 330, 200, 36, 600, GREY);
  text(ctx, `MAKS ${p.valid ? Math.round(p.maxSpeed * 3.6) : dash}`, W - 40, 64, 28, 500, GREY, 'right');
  text(ctx, p.valid ? `${fmt(p.dist / 1000, 1)} km` : '', W - 40, 104, 28, 500, GREY, 'right');
  rr(ctx, 40, 240, W - 80, 18, 9); ctx.fillStyle = DIM; ctx.fill();
  if (v > 0.5) { rr(ctx, 40, 240, Math.max(18, (W - 80) * clamp(v / MAX, 0, 1)), 18, 9); ctx.fillStyle = A; ctx.fill(); }
}

// ---------- Rota haritası ----------
function mapPts(g) {
  if (g._map) return g._map;
  const step = Math.max(1, Math.floor(g.n / 1500)), idx = [];
  for (let i = 0; i < g.n; i += step) idx.push(i);
  if (idx[idx.length - 1] !== g.n - 1) idx.push(g.n - 1);
  let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity;
  for (const i of idx) { x0 = Math.min(x0, g.x[i]); x1 = Math.max(x1, g.x[i]); y0 = Math.min(y0, g.y[i]); y1 = Math.max(y1, g.y[i]); }
  return (g._map = { idx, x0, x1, y0, y1 });
}
function mapGauge(ctx, d, o, A) {
  const { p, gps } = d, W = 480, H = 480, pad = 50, top = 90;
  label(ctx, 'Rota', 40, 64);
  text(ctx, 'K', W - 44, 70, 28, 700, WHITE, 'center');
  ctx.fillStyle = WHITE; ctx.beginPath(); ctx.moveTo(W - 44, 22); ctx.lineTo(W - 54, 40); ctx.lineTo(W - 34, 40); ctx.fill();
  const m = mapPts(gps), bw = W - 2 * pad, bh = H - top - pad;
  const sc = Math.min(bw / Math.max(1, m.x1 - m.x0), bh / Math.max(1, m.y1 - m.y0));
  const ox = pad + (bw - (m.x1 - m.x0) * sc) / 2, oy = top + (bh - (m.y1 - m.y0) * sc) / 2;
  const P = (x, y) => [ox + (x - m.x0) * sc, oy + (m.y1 - y) * sc];
  ctx.lineCap = 'round'; ctx.lineJoin = 'round';
  ctx.strokeStyle = 'rgba(255,255,255,.35)'; ctx.lineWidth = 5; ctx.beginPath();
  m.idx.forEach((i, k) => { const [x, y] = P(gps.x[i], gps.y[i]); k ? ctx.lineTo(x, y) : ctx.moveTo(x, y); }); ctx.stroke();
  if (!p.valid) return;
  ctx.strokeStyle = A; ctx.lineWidth = 7; ctx.beginPath(); let first = true;
  for (const i of m.idx) { if (i > p.i) break; const [x, y] = P(gps.x[i], gps.y[i]); first ? ctx.moveTo(x, y) : ctx.lineTo(x, y); first = false; }
  const [cx, cy] = P(p.x, p.y); if (!first) ctx.lineTo(cx, cy); ctx.stroke();
  ctx.save(); ctx.translate(cx, cy);
  ctx.fillStyle = 'rgba(255,255,255,.25)'; ctx.beginPath(); ctx.arc(0, 0, 30, 0, 7); ctx.fill();
  ctx.fillStyle = A; ctx.strokeStyle = WHITE; ctx.lineWidth = 4;
  if (isFinite(p.course)) {
    ctx.rotate(rad(p.course)); ctx.beginPath(); ctx.moveTo(0, -22); ctx.lineTo(15, 16); ctx.lineTo(0, 8); ctx.lineTo(-15, 16); ctx.closePath(); ctx.fill(); ctx.stroke();
  } else { ctx.beginPath(); ctx.arc(0, 0, 13, 0, 7); ctx.fill(); ctx.stroke(); }
  ctx.restore();
}

// ---------- İrtifa ----------
function altGauge(ctx, d, o, A) {
  const { p, gps } = d, W = 600, H = 280;
  label(ctx, 'İrtifa', 40, 64);
  if (!gps.hasEle) { text(ctx, 'GPX\'te irtifa yok', 40, 160, 34, 600, GREY); return; }
  text(ctx, p.valid && isFinite(p.ele) ? `${Math.round(p.ele)} m` : dash, W - 40, 72, 56, 700, WHITE, 'right');
  if (!gps._prof) {
    const N = 240, pr = new Float32Array(N); let j = 0;
    for (let k = 0; k < N; k++) { const T = gps.start + (gps.end - gps.start) * k / (N - 1); while (j < gps.n - 1 && gps.t[j + 1] < T) j++; pr[k] = isFinite(gps.ele[j]) ? gps.ele[j] : gps.eMin; }
    gps._prof = pr;
  }
  const pr = gps._prof, x0 = 40, x1 = W - 40, y0 = 110, y1 = H - 40, span = Math.max(10, gps.eMax - gps.eMin);
  const X = k => x0 + (x1 - x0) * k / (pr.length - 1), Y = e => y1 - (y1 - y0) * (e - gps.eMin) / span;
  const area = () => { ctx.beginPath(); ctx.moveTo(x0, y1); pr.forEach((e, k) => ctx.lineTo(X(k), Y(e))); ctx.lineTo(x1, y1); ctx.closePath(); };
  area(); ctx.fillStyle = 'rgba(255,255,255,.12)'; ctx.fill();
  ctx.beginPath(); pr.forEach((e, k) => k ? ctx.lineTo(X(k), Y(e)) : ctx.moveTo(X(k), Y(e))); ctx.strokeStyle = 'rgba(255,255,255,.55)'; ctx.lineWidth = 3; ctx.stroke();
  if (!p.valid) return;
  const f = clamp((p.T - gps.start) / (gps.end - gps.start), 0, 1), cx = x0 + (x1 - x0) * f;
  const e = isFinite(p.ele) ? p.ele : pr[Math.round(f * (pr.length - 1))];
  ctx.save(); ctx.beginPath(); ctx.rect(x0, y0 - 10, cx - x0, y1 - y0 + 10); ctx.clip(); area(); ctx.globalAlpha = 0.35; ctx.fillStyle = A; ctx.fill(); ctx.restore();
  ctx.strokeStyle = WHITE; ctx.lineWidth = 2; ctx.beginPath(); ctx.moveTo(cx, y0); ctx.lineTo(cx, y1); ctx.stroke();
  ctx.fillStyle = A; ctx.strokeStyle = WHITE; ctx.lineWidth = 4; ctx.beginPath(); ctx.arc(cx, Y(e), 11, 0, 7); ctx.fill(); ctx.stroke();
}

// ---------- Pusula şeridi ----------
const CARD = { 0: 'K', 45: 'KD', 90: 'D', 135: 'GD', 180: 'G', 225: 'GB', 270: 'B', 315: 'KB' };
function compass(ctx, d, o, A) {
  const { p } = d, W = 900, H = 180, cx = W / 2, PX = 5.2, HALF = 75, base = H - 20;
  const ok = p.valid && isFinite(p.course), c = ok ? p.course : 0;
  ctx.save(); rr(ctx, 20, 70, W - 40, H - 70, 24); ctx.clip();
  for (let a = Math.ceil((c - HALF) / 5) * 5; a <= c + HALF; a += 5) {
    const x = cx + (a - c) * PX, aa = ((a % 360) + 360) % 360, fade = 1 - Math.abs(a - c) / HALF;
    ctx.globalAlpha = ok ? 0.2 + 0.8 * fade : 0.2;
    const major = aa % 45 === 0, mid = aa % 15 === 0;
    ctx.strokeStyle = WHITE; ctx.lineWidth = major ? 4 : 2;
    ctx.beginPath(); ctx.moveTo(x, base); ctx.lineTo(x, base - (major ? 30 : mid ? 20 : 12)); ctx.stroke();
    if (major) text(ctx, CARD[aa], x, base - 42, aa % 90 === 0 ? 38 : 30, 700, aa === 0 ? A : WHITE, 'center');
    else if (mid) text(ctx, `${aa}`, x, base - 42, 24, 500, GREY, 'center');
  }
  ctx.restore(); ctx.globalAlpha = 1;
  rr(ctx, cx - 70, 14, 140, 50, 14); ctx.fillStyle = 'rgba(0,0,0,.55)'; ctx.fill();
  text(ctx, ok ? `${Math.round(c) % 360}°` : dash, cx, 40, 34, 700, WHITE, 'center', 'middle');
  ctx.fillStyle = A; ctx.beginPath(); ctx.moveTo(cx - 14, 68); ctx.lineTo(cx + 14, 68); ctx.lineTo(cx, 86); ctx.closePath(); ctx.fill();
  ctx.fillRect(cx - 1.5, 86, 3, base - 86);
}

// ---------- Grafik (son 10 sn) ----------
function chart(ctx, d, o, A) {
  const { tel, gps, gbase, goff, s } = d, W = 1000, H = 300, x0 = 40, x1 = W - 40, y0 = 90, y1 = H - 40, WIN = 10, mid = (y0 + y1) / 2;
  label(ctx, 'Son 10 saniye', 40, 64);
  ctx.strokeStyle = DIM; ctx.lineWidth = 2; ctx.beginPath(); ctx.moveTo(x0, mid); ctx.lineTo(x1, mid); ctx.stroke();
  const t1 = s.t, t0 = t1 - WIN, X = t => x0 + (x1 - x0) * (t - t0) / WIN;
  const line = (col, w, step, f) => {
    ctx.strokeStyle = col; ctx.lineWidth = w; ctx.lineJoin = 'round'; ctx.beginPath(); let first = true;
    for (let t = Math.max(0, t0); t <= t1 + 1e-6; t += step) { const y = f(t); if (y === null) { first = true; continue; } first ? ctx.moveTo(X(t), y) : ctx.lineTo(X(t), y); first = false; }
    ctx.stroke();
  };
  let sec = 'İVME';
  if (gps) {
    sec = 'HIZ'; const MAX = speedScale(gps);
    line(CYAN, 4, 0.1, t => { const q = gpsAt(gps, gbase, goff, t); return q.valid ? y1 - clamp(q.speed * 3.6 / MAX, 0, 1) * (y1 - y0) : null; });
  } else if (tel.hasAccel) line(CYAN, 4, 0.05, t => mid - clamp(sampleAt(tel, t).lon / o.gRange, -1, 1) * (y1 - y0) / 2);
  line(A, 5, 0.05, t => mid - clamp(sampleAt(tel, t).roll / o.leanRange, -1, 1) * (y1 - y0) / 2);
  ctx.fillStyle = A; ctx.fillRect(x1 - 300, 44, 26, 8); text(ctx, 'YATIŞ', x1 - 264, 56, 26, 600, GREY);
  ctx.fillStyle = CYAN; ctx.fillRect(x1 - 130, 44, 26, 8); text(ctx, sec, x1 - 94, 56, 26, 600, GREY);
}

const DRAW = {
  lean: (c, d, o, A, st) => st === 'arc' ? leanArc(c, d, o, A) : leanBike(c, d, o, A),
  speed: (c, d, o, A, st) => st === 'digital' ? speedDigital(c, d, o, A) : speedDial(c, d, o, A),
  gforce, attitude, clock, map: mapGauge, alt: altGauge, compass, chart,
};

export function gaugeAvailable(id, data) {
  const need = GAUGES[id].needs;
  return !(need === 'gps' && !data.gps) && !(need === 'accel' && !data.tel.hasAccel) && !(need === 'imu' && data.tel.hasImu === false);
}
export function gaugeSize(id, style) { return SIZES[id](style); }

// Ana çizim. data = { tel, gps, gbase, goff }. ui = { highlight, edit } (yalnızca önizleme). Dönüş: gösterge kutuları
export function drawOverlay(ctx, W, H, t, data, o, meta = {}, ui = {}) {
  const A = ACCENTS[o.accent] || ACCENTS.turuncu;
  const base = Math.min(W / 3840, H / 2160) * (W < H ? 1.6 : 1);
  const k0 = base * o.size / 100, m = 60 * base;
  const d = { s: sampleAt(data.tel, t), p: data.gps ? gpsAt(data.gps, data.gbase, data.goff, t) : { valid: false },
    tel: data.tel, gps: data.gps, gbase: data.gbase, goff: data.goff, meta };
  const rects = [];
  for (const id of Object.keys(GAUGES)) {
    const g = o.g[id]; if (!g.on || !gaugeAvailable(id, data)) continue;
    const [pw, ph] = SIZES[id](g.style), k = k0 * (g.scale || 100) / 100;
    const x = m + clamp(g.x, 0, 1) * Math.max(0, W - 2 * m - pw * k), y = m + clamp(g.y, 0, 1) * Math.max(0, H - 2 * m - ph * k);
    ctx.save(); ctx.translate(x, y); ctx.scale(k, k);
    ctx.save(); panel(ctx, pw, ph, o); DRAW[id](ctx, d, o, A, g.style); ctx.restore();
    if (ui.highlight === id || ui.edit) {
      const sel = ui.highlight === id;
      ctx.setLineDash(sel ? [] : [16, 12]); ctx.lineWidth = (sel ? 8 : 4) / Math.max(0.15, k / base);
      ctx.strokeStyle = sel ? A : 'rgba(255,255,255,.6)'; rr(ctx, -8, -8, pw + 16, ph + 16, 42); ctx.stroke(); ctx.setLineDash([]);
    }
    ctx.restore();
    rects.push({ id, x, y, w: pw * k, h: ph * k, m });
  }
  return rects;
}
