// Telemetri göstergelerini bir Canvas 2D bağlamına çizer.
// Tasarım birimleri 4K (3840x2160) için; k ölçeğiyle her çözünürlüğe uyar.
import { sampleAt } from './gpmf.js';

export const ACCENTS = {
  turuncu: '#FF7A1A', mavi: '#29D3FF', yesil: '#50E68C', kirmizi: '#FF4D5E', sari: '#FFD23F',
};
export const DEFAULTS = {
  lean: true, gforce: true, attitude: true, clock: true,
  size: 100, opacity: 78, accent: 'turuncu', leanRange: 45, gRange: 0.5,
};

const FONT = '-apple-system, BlinkMacSystemFont, "SF Pro Display", "Segoe UI", Inter, Roboto, "Helvetica Neue", Arial, sans-serif';
const WHITE = '#fff', GREY = 'rgba(255,255,255,.58)', DIM = 'rgba(255,255,255,.16)', GREEN = '#50E68C', RED = '#FF4D5E';
const PW = 760;

function rr(ctx, x, y, w, h, r) {
  ctx.beginPath(); ctx.moveTo(x + r, y); ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath();
}
function panel(ctx, w, h, o) {
  rr(ctx, 0, 0, w, h, 36);
  ctx.fillStyle = `rgba(12,14,20,${o.opacity / 100})`; ctx.fill();
  ctx.lineWidth = 2; ctx.strokeStyle = 'rgba(255,255,255,.16)'; ctx.stroke();
}
function text(ctx, s, x, y, size, weight = 600, color = WHITE, align = 'left', base = 'alphabetic') {
  ctx.font = `${weight} ${size}px ${FONT}`; ctx.fillStyle = color; ctx.textAlign = align; ctx.textBaseline = base;
  ctx.fillText(s, x, y);
}
const label = (ctx, s, x, y, align = 'left') => text(ctx, s.toLocaleUpperCase('tr-TR'), x, y, 30, 600, GREY, align);
const rad = d => d * Math.PI / 180;
const fmt = (v, d = 0) => Math.abs(v).toFixed(d).replace('.', ',');

function leanPanel(ctx, s, o, A) {
  const H = 500; panel(ctx, PW, H, o);
  const cx = PW / 2, cy = 340, r = 250, RNG = o.leanRange;
  label(ctx, 'Yatış açısı', 40, 64);
  const ang = d => rad(-90 + d * 90 / RNG); // RNG derece = 90° yay
  ctx.lineCap = 'round';
  ctx.lineWidth = 18; ctx.strokeStyle = DIM; ctx.beginPath(); ctx.arc(cx, cy, r, ang(-RNG), ang(RNG)); ctx.stroke();
  const v = Math.max(-RNG, Math.min(RNG, s.roll));
  if (Math.abs(v) > 0.3) {
    ctx.strokeStyle = A; ctx.beginPath(); ctx.arc(cx, cy, r, ang(Math.min(0, v)), ang(Math.max(0, v))); ctx.stroke();
  }
  ctx.lineCap = 'butt'; ctx.lineWidth = 3; ctx.strokeStyle = GREY;
  for (let t = -RNG; t <= RNG + 0.01; t += RNG / 3) {
    const a = ang(t), r2 = Math.abs(t) < 0.01 || Math.abs(Math.abs(t) - RNG) < 0.01 ? r - 50 : r - 40;
    ctx.beginPath(); ctx.moveTo(cx + Math.cos(a) * (r - 30), cy + Math.sin(a) * (r - 30));
    ctx.lineTo(cx + Math.cos(a) * r2, cy + Math.sin(a) * r2); ctx.stroke();
  }
  text(ctx, `${RNG}°`, cx - r, cy + 58, 28, 500, GREY, 'center');
  text(ctx, `${RNG}°`, cx + r, cy + 58, 28, 500, GREY, 'center');
  for (const [m, sg] of [[s.maxL, -1], [s.maxR, 1]]) {
    if (m > 0.5) {
      const a = ang(sg * Math.min(m, RNG)); ctx.fillStyle = WHITE;
      ctx.beginPath(); ctx.arc(cx + Math.cos(a) * (r + 24), cy + Math.sin(a) * (r + 24), 7, 0, 7); ctx.fill();
    }
  }
  const a = ang(v); const tx = cx + Math.cos(a) * r, ty = cy + Math.sin(a) * r;
  ctx.fillStyle = A; ctx.strokeStyle = WHITE; ctx.lineWidth = 5;
  ctx.beginPath(); ctx.arc(tx, ty, 17, 0, 7); ctx.fill(); ctx.stroke();
  text(ctx, `${fmt(s.roll)}°`, cx + 20, cy - 30, 130, 700, WHITE, 'center');
  const side = s.roll > 0.5 ? 'SAĞ' : s.roll < -0.5 ? 'SOL' : 'DÜZ';
  text(ctx, side, cx, cy + 18, 32, 700, A, 'center');
  text(ctx, `MAKS SOL  ${fmt(s.maxL)}°`, 40, H - 40, 28, 500, GREY);
  text(ctx, `MAKS SAĞ  ${fmt(s.maxR)}°`, PW - 40, H - 40, 28, 500, GREY, 'right');
}

function gPanel(ctx, s, o, tel) {
  const H = 500; panel(ctx, PW, H, o);
  const cx = 225, cy = 268, r = 180, RNG = o.gRange, C = '#29D3FF';
  label(ctx, 'G-kuvveti', 40, 64);
  ctx.lineWidth = 2;
  ctx.strokeStyle = GREY; ctx.beginPath(); ctx.arc(cx, cy, r, 0, 7); ctx.stroke();
  ctx.strokeStyle = DIM; ctx.beginPath(); ctx.arc(cx, cy, r / 2, 0, 7); ctx.stroke();
  ctx.beginPath(); ctx.moveTo(cx - r, cy); ctx.lineTo(cx + r, cy); ctx.moveTo(cx, cy - r); ctx.lineTo(cx, cy + r); ctx.stroke();
  text(ctx, fmt(RNG / 2, 2), cx + 6, cy - r / 2 - 6, 24, 500, GREY);
  text(ctx, `${fmt(RNG, 1)} G`, cx + 6, cy - r - 6, 24, 500, GREY);
  const pos = (la, lo) => {
    let x = la / RNG, y = lo / RNG; const m = Math.hypot(x, y); if (m > 1) { x /= m; y /= m; }
    return [cx + x * r, cy - y * r];
  };
  const n = Math.round(1.2 * tel.hz), i1 = s.i, i0 = Math.max(0, i1 - n);
  ctx.lineCap = 'round'; ctx.lineWidth = 5;
  let prev = null;
  for (let i = i0; i <= i1; i += 2) {
    const p = pos(tel.lat[i], tel.lon[i]);
    if (prev) { ctx.strokeStyle = `rgba(41,211,255,${0.8 * (i - i0) / (i1 - i0 + 1)})`; ctx.beginPath(); ctx.moveTo(...prev); ctx.lineTo(...p); ctx.stroke(); }
    prev = p;
  }
  const [px, py] = pos(s.lat, s.lon);
  ctx.fillStyle = C; ctx.strokeStyle = WHITE; ctx.lineWidth = 4;
  ctx.beginPath(); ctx.arc(px, py, 16, 0, 7); ctx.fill(); ctx.stroke();
  const tx = 450, acc = s.lon >= 0;
  text(ctx, acc ? 'HIZLANMA' : 'FREN', tx, 150, 30, 700, acc ? GREEN : RED);
  text(ctx, `${fmt(s.lon, 2)} G`, tx, 220, 60, 700);
  text(ctx, 'YANAL', tx, 300, 30, 600, GREY);
  text(ctx, `${fmt(s.lat, 2)} G`, tx, 370, 60, 700);
  text(ctx, `MAKS  ${fmt(s.maxG, 2)} G`, 40, H - 40, 28, 500, GREY);
}

function attPanel(ctx, s, o, A) {
  const H = 300; panel(ctx, PW, H, o);
  const cx = 160, cy = 150, r = 105, PX = 3;
  ctx.save(); ctx.beginPath(); ctx.arc(cx, cy, r, 0, 7); ctx.clip();
  ctx.translate(cx, cy); ctx.rotate(rad(-s.roll));
  const off = -s.pitch * PX;
  ctx.fillStyle = 'rgba(60,130,200,.92)'; ctx.fillRect(-2 * r, -2 * r, 4 * r, 2 * r + off);
  ctx.fillStyle = 'rgba(150,95,50,.92)'; ctx.fillRect(-2 * r, off, 4 * r, 2 * r);
  ctx.strokeStyle = WHITE; ctx.lineWidth = 3; ctx.beginPath(); ctx.moveTo(-2 * r, off); ctx.lineTo(2 * r, off); ctx.stroke();
  ctx.strokeStyle = 'rgba(255,255,255,.6)'; ctx.lineWidth = 2;
  for (const p of [-20, -10, 10, 20]) {
    const y = off - p * PX, w = Math.abs(p) === 10 ? 30 : 45;
    ctx.beginPath(); ctx.moveTo(-w, y); ctx.lineTo(w, y); ctx.stroke();
  }
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
  label(ctx, 'Dönüş hızı', tx, 196);
  text(ctx, `${fmt(s.yaw)}°/s`, tx, 262, 60, 700);
}

function clockPanel(ctx, s, o, created, device) {
  const H = 150; panel(ctx, PW, H, o);
  ctx.fillStyle = (Math.floor(s.t * 2) % 2 === 0) ? RED : 'rgba(255,77,94,.35)';
  ctx.beginPath(); ctx.arc(51, 63, 11, 0, 7); ctx.fill();
  text(ctx, 'TELEMETRİ', 80, 74, 30, 700);
  text(ctx, `${device} · sensör verisi`, 80, 116, 26, 500, GREY);
  if (created) {
    const d = new Date(created.getTime() + s.t * 1000);
    const hh = d.toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit', second: '2-digit' });
    text(ctx, hh, PW - 40, 92, 64, 600, WHITE, 'right');
  }
  const m = Math.floor(s.t / 60), sec = (s.t % 60).toFixed(1).padStart(4, '0').replace('.', ',');
  text(ctx, `${String(m).padStart(2, '0')}:${sec}`, PW - 40, 128, 26, 500, GREY, 'right');
}

// Ana çizim: ctx üzerine W x H alana, video zamanı t için
export function drawOverlay(ctx, W, H, t, tel, opts, meta = {}) {
  const o = { ...DEFAULTS, ...opts }; const A = ACCENTS[o.accent] || ACCENTS.turuncu;
  const s = sampleAt(tel, t);
  const k = Math.min(W / 3840, H / 2160) * o.size / 100 * (W < H ? 1.6 : 1); // dikey videoda biraz büyüt
  const m = 60 * k;
  const place = (fn, x, y, ph) => { ctx.save(); ctx.translate(x, y); ctx.scale(k, k); fn(); ctx.restore(); };
  if (o.lean) place(() => leanPanel(ctx, s, o, A), m, H - m - 500 * k);
  if (o.gforce && tel.hasAccel) place(() => gPanel(ctx, s, o, tel), W - m - PW * k, H - m - 500 * k);
  if (o.attitude) place(() => attPanel(ctx, s, o, A), m, m);
  if (o.clock) place(() => clockPanel(ctx, s, o, meta.created, meta.device || 'GoPro'), W - m - PW * k, m);
}
