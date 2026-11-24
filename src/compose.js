// Fotoğraf + aktivite verisi şablonları. Tasarım birimi: 1080 genişlik (u = W/1080).
import { fitRoute, routePath, visibleRange, fmtDur, fmtPace, fmtKm, fmtNum } from './activity.js';
import { drawTiles, MAP_STYLES } from './tiles.js';
import { TYPES } from './store.js';

export const TEMPLATES = {
  rota: 'Rota + değerler', buyuk: 'Büyük rakam', liste: 'Dikey liste', bant: 'Alt bant', kart: 'Harita kartı', saydam: 'Saydam etiket',
};
export const SHAPES = { yuvarlak: 'Yuvarlak köşe', daire: 'Daire', keskin: 'Keskin' };
export const TEXT_COLORS = { otomatik: 'Otomatik', beyaz: 'Beyaz', siyah: 'Siyah', rota: 'Rota rengi', sari: 'Sarı' };
export const TEXT_HEX = { beyaz: '#FFFFFF', siyah: '#0A0A0A', sari: '#FFD23F' };
export const FONTS = { standart: 'Standart', yuvarlak: 'Yuvarlak', mono: 'Teknik', serif: 'Klasik' };
export const MAX_FIELDS = 6;
export const FORMATS = { '3:4': [1080, 1440], '9:16': [1080, 1920], '4:5': [1080, 1350], '1:1': [1080, 1080], 'orij': null };
export const ROUTE_COLORS = { turuncu: '#FF5A1F', beyaz: '#FFFFFF', sari: '#FFD23F', yesil: '#4ADE80', mavi: '#38BDF8', kirmizi: '#FB4D4D', siyah: '#0A0A0A' };
export const FIELDS = {
  dist: 'Mesafe', time: 'Süre', pace: 'Tempo / hız', gain: 'Yükseliş', max: 'Maks hız', elapsed: 'Geçen süre', steps: 'Adım', kcal: 'Kalori',
};
const BASE = '-apple-system, BlinkMacSystemFont, "SF Pro Display", "Segoe UI", system-ui, Roboto, Arial, sans-serif';
const FONT_SETS = { standart: BASE, yuvarlak: 'ui-rounded, "SF Pro Rounded", ' + BASE, mono: 'ui-monospace, "SF Mono", Menlo, Consolas, monospace', serif: 'ui-serif, "New York", Georgia, serif' };
let FONT = BASE;

export function fieldValue(k, A) {
  switch (k) {
    case 'dist': return ['Mesafe', fmtKm(A.dist), 'km'];
    case 'time': return ['Süre', fmtDur(A.movingTime), ''];
    case 'steps': return ['Adım', fmtNum(A.steps || 0), ''];
    case 'kcal': return ['Kalori', fmtNum(A.kcal || 0), 'kcal'];
    case 'elapsed': return ['Geçen süre', fmtDur(A.elapsed), ''];
    case 'pace': return A.pace ? ['Tempo', fmtPace(A.avg), '/km'] : ['Ort. hız', fmtNum(A.avg * 3.6, 1), 'km/h'];
    case 'gain': return ['Yükseliş', isFinite(A.gain) ? fmtNum(A.gain) : '—', 'm'];
    case 'max': return A.pace ? ['En iyi tempo', fmtPace(A.vmax), '/km'] : ['Maks hız', fmtNum(A.vmax * 3.6), 'km/h'];
  }
  return ['', '', ''];
}

function txt(ctx, s, x, y, size, weight, color, align = 'left', base = 'alphabetic', track = 0) {
  ctx.font = `${weight} ${size}px ${FONT}`; ctx.fillStyle = color; ctx.textAlign = align; ctx.textBaseline = base;
  if ('letterSpacing' in ctx) ctx.letterSpacing = `${track}px`;
  ctx.fillText(s, x, y);
  if ('letterSpacing' in ctx) ctx.letterSpacing = '0px';
  return ctx.measureText(s).width;
}
function rr(ctx, x, y, w, h, r) { ctx.beginPath(); ctx.roundRect ? ctx.roundRect(x, y, w, h, r) : ctx.rect(x, y, w, h); }
function hex(c) { c = c.replace('#', ''); return [0, 2, 4].map(i => parseInt(c.slice(i, i + 2), 16)); }
const rgba = (c, a) => { const [r, g, b] = hex(c); return `rgba(${r},${g},${b},${a})`; };
const isLight = c => { const [r, g, b] = hex(c); return (r * 299 + g * 587 + b * 114) / 1000 > 150; };
const fieldList = s => (s.fields?.length ? s.fields : ['dist', 'time', 'pace']).slice(0, MAX_FIELDS);
const gridOf = n => { const rows = n > 4 ? 2 : 1; return { rows, cols: Math.ceil(n / rows) }; };

// Blok tanımları: { w, h } (u biriminde) + çizim. Konum: merkez (0..1).
function layout(tpl, W, H, s) {
  const tall = H / W > 1.5, hu = H / (W / 1080), n = fieldList(s).length, { rows } = gridOf(n);
  const sq = (b) => s.shape === 'daire' ? { ...b, w: Math.min(b.w, b.h), h: Math.min(b.w, b.h) } : b;
  switch (tpl) {
    case 'rota': return { route: sq({ w: 760, h: tall ? 760 : 560, cx: .5, cy: tall ? .44 : .4 }), stats: { w: 980, h: 210 * rows, cx: .5, cy: (tall ? .82 : .84) - (rows - 1) * .04 } };
    case 'buyuk': { const r2 = Math.max(1, Math.ceil(Math.max(0, n - 1) / 3)); return { route: sq({ w: 380, h: 380, cx: .74, cy: tall ? .2 : .24 }), stats: { w: 980, h: 520 + (r2 - 1) * 150, cx: .5, cy: (tall ? .74 : .66) - (r2 - 1) * .035 } }; }
    case 'liste': { const h = 130 * n + 40; return { route: sq({ w: 440, h: 440, cx: .72, cy: tall ? .3 : .3 }), stats: { w: 560, h, cx: 330 / 1080, cy: 1 - (h / 2 + 140) / hu } }; }
    case 'bant': return { band: { w: 1080, h: 420, cx: .5, cy: 1 - 210 / hu } };
    case 'kart': return { card: { w: 960, h: tall ? 1120 : Math.min(1180, hu - 120), cx: .5, cy: .5 } };
    case 'saydam': return { route: sq({ w: 860, h: tall ? 900 : 640, cx: .5, cy: tall ? .4 : .38 }), stats: { w: 980, h: 210 * rows, cx: .5, cy: (tall ? .78 : .84) - (rows - 1) * .04 } };
  }
  return {};
}

/** Çiz. s = { tpl, W, H, photo, pan, mapStyle, shape, color, textColor, font, fields[], hide, sign, transparent, pos, scale }
 *  data = { g, A, title }  Dönüş: blok kutuları (sürükleme için, piksel) */
export function compose(ctx, s, data, { fetchTiles = true } = {}) {
  if (s.fields && !(data.A?.steps > 0)) s = { ...s, fields: s.fields.filter(k => k !== 'steps') };
  if (s.fields && !(data.A?.kcal > 0)) s = { ...s, fields: s.fields.filter(k => k !== 'kcal') };
  FONT = FONT_SETS[s.font] || BASE;
  const { W, H } = s, u = W / 1080, { g, A } = data;
  ctx.clearRect(0, 0, W, H);
  if (s.photo && s.tpl !== 'saydam' && !s.transparent) {
    const p = s.photo, z = Math.max(1, s.pan?.z || 1);
    const k = Math.max(W / p.width, H / p.height) * z, dw = p.width * k, dh = p.height * k;
    const ox = (W - dw) / 2 + (s.pan?.x || 0) * (dw - W) / 2, oy = (H - dh) / 2 + (s.pan?.y || 0) * (dh - H) / 2;
    ctx.drawImage(p, ox, oy, dw, dh);
    const gr = ctx.createLinearGradient(0, 0, 0, H);
    gr.addColorStop(0, 'rgba(0,0,0,.18)'); gr.addColorStop(.45, 'rgba(0,0,0,0)'); gr.addColorStop(.62, 'rgba(0,0,0,0)'); gr.addColorStop(1, 'rgba(0,0,0,.5)');
    ctx.fillStyle = gr; ctx.fillRect(0, 0, W, H);
  } else if (s.tpl !== 'saydam' && !s.transparent) { ctx.fillStyle = '#0B0B0D'; ctx.fillRect(0, 0, W, H); }

  const L = layout(s.tpl, W, H, s), boxes = {};
  const col = ROUTE_COLORS[s.color] || '#fff';
  const tc = s.textColor === 'rota' ? col : TEXT_HEX[s.textColor] || null;   // null = otomatik (şablona göre)
  for (const [id, b] of Object.entries(L)) {
    const sc = (s.scale?.[id] || 1), pos = s.pos?.[id] || b, w = b.w * u * sc, h = b.h * u * sc;
    const x = pos.cx * W - w / 2, y = pos.cy * H - h / 2;
    boxes[id] = { x, y, w, h };
    ctx.save(); ctx.translate(x, y); ctx.scale(u * sc, u * sc);
    DRAW[id](ctx, b.w, b.h, s, data, col, fetchTiles, tc);
    ctx.restore();
  }
  if (s.sign !== false && !s.transparent) drawSignature(ctx, W, H, s);
  return boxes;
}

/** KROVA imzası: K rota logosu (+ ROVA / KROVA yazısı, isteğe bağlı rota çizgisi). Stil, konum, boyut seçilebilir. */
export function drawSignature(ctx, W, H, s) {
  const u = W / 1080, h = ({ k: 36, o: 46, b: 64 }[s.signSize] || 46) * u, sc = h / 80.2;
  const label = s.signText === 'logo' ? '' : s.signText === 'krova' ? 'KROVA' : 'ROVA', fs = h * 0.72, gap = h * 0.14;
  const markW = 60.1 * sc;
  ctx.save();
  ctx.font = `500 ${fs}px ${FONT}`; if ('letterSpacing' in ctx) ctx.letterSpacing = `${h * 0.1}px`;
  const tw = label ? ctx.measureText(label).width : 0, totalW = markW + (label ? gap + tw : 0);
  if ('letterSpacing' in ctx) ctx.letterSpacing = '0px';
  const tall = H > W * 1.6, mx = 36 * u, bottom = H - (tall ? H * 0.11 : Math.max(H * 0.032, 30 * u));
  const pos = s.signPos || 'altorta';
  let x = pos === 'solalt' ? mx : pos === 'sagalt' ? W - mx - totalW : (W - totalW) / 2;
  let y = pos === 'ust' ? Math.max(H * 0.06, 48 * u) : bottom - h;
  if (pos === 'solalt' || pos === 'sagalt') y = H - Math.max(H * 0.04, 36 * u) - h;
  // otomatik: arkadaki görüntünün parlaklığına bakıp açık/koyu seç
  let st = s.signStyle || 'renkli';
  if (st === 'oto') {
    st = 'beyaz';
    try {
      const t = ctx.getTransform(), a = Math.max(1, Math.round(x * t.a + t.e)), b = Math.max(1, Math.round(y * t.d + t.f));
      const d = ctx.getImageData(a, b, Math.max(1, Math.round(totalW * t.a)), Math.max(1, Math.round(h * t.d))).data;
      let sum = 0, n = 0; for (let i = 0; i < d.length; i += 16) { sum += (d[i] * 299 + d[i + 1] * 587 + d[i + 2] * 114) / 1000; n++; }
      if (n && sum / n > 165) st = 'siyah';
    } catch {}
  }
  const orange = '#FF5A1F', ink = '#15171B';
  const C = st === 'siyah' ? { bar: ink, arm: ink, dot: '#E9E6DD', text: ink, sh: 'rgba(255,255,255,.35)' }
    : st === 'beyaz' ? { bar: '#fff', arm: '#fff', dot: '#15171B', text: '#fff', sh: 'rgba(0,0,0,.4)' }
    : { bar: '#fff', arm: orange, dot: '#fff', text: '#fff', sh: 'rgba(0,0,0,.5)' };
  ctx.translate(x, y);
  ctx.shadowColor = C.sh; ctx.shadowBlur = 14 * u; ctx.shadowOffsetY = 2 * u;
  const P = (px, py) => [(px - 36) * sc, (py - 26.9) * sc];
  ctx.fillStyle = C.bar; ctx.beginPath(); ctx.roundRect(0, (28 - 26.9) * sc, 12 * sc, 74 * sc, 6 * sc); ctx.fill();
  ctx.lineCap = 'round'; ctx.lineJoin = 'round'; ctx.strokeStyle = C.arm; ctx.lineWidth = 12 * sc;
  ctx.beginPath(); ctx.moveTo(...P(50, 66)); ctx.lineTo(...P(88, 33)); ctx.moveTo(...P(50, 66)); ctx.lineTo(...P(90, 101)); ctx.stroke();
  for (const [px, py] of [[88, 33], [90, 101]]) { const [cx, cy] = P(px, py); ctx.fillStyle = C.dot; ctx.beginPath(); ctx.arc(cx, cy, 6.1 * sc, 0, 7); ctx.fill(); }
  if (label) {
    ctx.shadowColor = C.sh;
    ctx.font = `500 ${fs}px ${FONT}`; ctx.fillStyle = C.text; ctx.textAlign = 'left'; ctx.textBaseline = 'middle';
    if ('letterSpacing' in ctx) ctx.letterSpacing = `${h * 0.1}px`;
    ctx.fillText(label, markW + gap, h * 0.5 + fs * 0.04);
    if ('letterSpacing' in ctx) ctx.letterSpacing = '0px';
  }
  // rota çizgisi: alt koldaki noktadan çıkıp yazının altından akar (yazı varsa)
  if (label && (s.signLine || 'alt') === 'alt') {
    const [sx, sy] = P(90, 101), ex = markW + gap + tw, ey = h * 0.96;
    ctx.strokeStyle = C.arm; ctx.lineWidth = Math.max(2, h * 0.07);
    ctx.beginPath(); ctx.moveTo(sx, sy);
    const w = ex - sx;
    ctx.bezierCurveTo(sx + w * .18, h * 1.08, sx + w * .3, h * .88, sx + w * .55, h * .98);
    ctx.bezierCurveTo(sx + w * .75, h * 1.06, sx + w * .9, h * .93, ex, ey); ctx.stroke();
    ctx.fillStyle = C.dot; ctx.beginPath(); ctx.arc(ex, ey, h * 0.06, 0, 7); ctx.fill();
  }
  ctx.restore();
}

function shadowOn(ctx, on = true, color = 'rgba(0,0,0,.45)') { ctx.shadowColor = on ? color : 'transparent'; ctx.shadowBlur = on ? 18 : 0; ctx.shadowOffsetY = on ? 2 : 0; }
const shadowFor = (ctx, c, on = true) => shadowOn(ctx, on, isLight(c) ? 'rgba(0,0,0,.45)' : 'rgba(255,255,255,.35)');
const shapeR = (s, w, h) => s.shape === 'daire' ? Math.min(w, h) / 2 : s.shape === 'keskin' ? 0 : 36;

function drawRouteIn(ctx, w, h, s, data, col, fetchTiles, { radius = 0, pad = .08, mapBg = true } = {}) {
  const { g } = data, [i0, i1] = visibleRange(g, s.hide ? 200 : 0);
  if (i1 <= i0) return;
  const box = { x: 0, y: 0, w, h };
  const F = fitRoute(g, box, { pad, i0, i1 });
  const style = mapBg ? s.mapStyle : 'yok';
  if (style && style !== 'yok') {
    ctx.save(); rr(ctx, 0, 0, w, h, radius); ctx.clip();
    ctx.fillStyle = MAP_STYLES[style].dark ? '#1a1a1d' : '#e9e9ec'; ctx.fillRect(0, 0, w, h);
    drawTiles(ctx, style, g, F.M, F.view, { fetchMissing: fetchTiles });
    ctx.restore();
    if (radius < Math.min(w, h) / 2 - 1) txt(ctx, MAP_STYLES[style].attr, w - 14, h - 12, 15, 500, MAP_STYLES[style].dark ? 'rgba(255,255,255,.7)' : 'rgba(0,0,0,.6)', 'right');
    else txt(ctx, MAP_STYLES[style].attr.split(',')[0], w / 2, h - 26, 13, 500, MAP_STYLES[style].dark ? 'rgba(255,255,255,.65)' : 'rgba(0,0,0,.55)', 'center');
    ctx.save(); rr(ctx, 1.5, 1.5, w - 3, h - 3, radius); ctx.lineWidth = 3; ctx.strokeStyle = MAP_STYLES[style].dark ? 'rgba(255,255,255,.16)' : 'rgba(0,0,0,.12)'; ctx.stroke(); ctx.restore();
  }
  const path = routePath(g, F.P, i0, i1);
  ctx.lineCap = 'round'; ctx.lineJoin = 'round';
  const onMap = style && style !== 'yok';
  ctx.strokeStyle = onMap ? (col === '#0A0A0A' ? '#fff' : 'rgba(0,0,0,.55)') : 'rgba(0,0,0,.35)';
  ctx.lineWidth = onMap ? 15 : 14; if (!onMap) shadowOn(ctx); ctx.stroke(path); shadowOn(ctx, false);
  ctx.strokeStyle = col; ctx.lineWidth = 9; ctx.stroke(path);
  const [sx, sy] = F.P(g.x[i0], g.y[i0]), [ex, ey] = F.P(g.x[i1], g.y[i1]);
  for (const [x, y, f] of [[sx, sy, '#fff'], [ex, ey, col]]) {
    ctx.beginPath(); ctx.arc(x, y, 13, 0, 7); ctx.fillStyle = f; ctx.fill(); ctx.lineWidth = 5; ctx.strokeStyle = 'rgba(0,0,0,.7)'; ctx.stroke();
  }
  for (const ph of data.pins || []) {
    if (ph.i < i0 || ph.i > i1) continue;
    const [x, y] = F.P(g.x[ph.i], g.y[ph.i]);
    ctx.beginPath(); ctx.arc(x, y, 10, 0, 7); ctx.fillStyle = '#fff'; ctx.fill(); ctx.lineWidth = 4; ctx.strokeStyle = '#000'; ctx.stroke();
  }
}

function statsRow(ctx, w, h, s, A, color = '#fff', shadow = true) {
  const f = fieldList(s), n = f.length, { rows, cols } = gridOf(n), light = isLight(color);
  const big = n > 4 ? 60 : n > 3 ? 64 : 76;
  f.forEach((k, i) => {
    const r = Math.floor(i / cols), inRow = r === rows - 1 ? n - cols * (rows - 1) : cols, c = i - r * cols, cw = w / inRow;
    const [lab, val, unit] = fieldValue(k, A), cx = cw * c + cw / 2, oy = 210 * r;
    if (shadow) shadowFor(ctx, color);
    txt(ctx, lab.toLocaleUpperCase('tr-TR'), cx, oy + 58, 26, 600, rgba(color, .8), 'center', 'alphabetic', 2);
    ctx.font = `700 ${big}px ${FONT}`;
    const vw = ctx.measureText(val).width; ctx.font = `600 30px ${FONT}`; const uw = unit ? ctx.measureText(' ' + unit).width : 0;
    const x0 = cx - (vw + uw) / 2;
    txt(ctx, val, x0, oy + 150, big, 700, color, 'left', 'alphabetic', -1);
    if (unit) txt(ctx, ' ' + unit, x0 + vw, oy + 150, 30, 600, rgba(color, .85));
    shadowOn(ctx, false);
    if (c) { ctx.fillStyle = rgba(color, light ? .28 : .15); ctx.fillRect(cw * c, oy + 30, 2, 140); }
  });
}

const DRAW = {
  route(ctx, w, h, s, data, col, ft) { drawRouteIn(ctx, w, h, s, data, col, ft, { radius: shapeR(s, w, h), pad: s.mapStyle && s.mapStyle !== 'yok' ? .1 : .04 }); },
  stats(ctx, w, h, s, data, col, ft, tc) {
    const fg = tc || '#FFFFFF';
    if (s.tpl === 'liste') {
      const f = fieldList(s);
      shadowFor(ctx, fg);
      f.forEach((k, i) => {
        const [lab, val, unit] = fieldValue(k, data.A), y = 20 + i * 130;
        txt(ctx, lab.toLocaleUpperCase('tr-TR'), 8, y + 34, 26, 600, rgba(fg, .8), 'left', 'alphabetic', 2.5);
        const vw = txt(ctx, val, 6, y + 104, 84, 750, fg, 'left', 'alphabetic', -2);
        if (unit) txt(ctx, ' ' + unit, 6 + vw, y + 104, 34, 600, rgba(fg, .85));
      });
      shadowOn(ctx, false);
      return;
    }
    if (s.tpl === 'buyuk') {
      const { A } = data, f = fieldList(s), [lab, val, unit] = fieldValue(f[0] || 'dist', A);
      shadowFor(ctx, fg);
      txt(ctx, (TYPES[A.type]?.name || '').toLocaleUpperCase('tr-TR') + ' · ' + lab.toLocaleUpperCase('tr-TR'), 30, 70, 30, 650, rgba(fg, .85), 'left', 'alphabetic', 3);
      const vw = txt(ctx, val, 22, 300, 250, 800, fg, 'left', 'alphabetic', -10);
      txt(ctx, unit, 40 + vw, 300, 64, 700, rgba(fg, .9));
      const rest = f.length > 1 ? f.slice(1) : ['time', 'pace'];
      rest.slice(0, 5).forEach((k, i) => {
        const [l, v, un] = fieldValue(k, A), x = 30 + (i % 3) * 320, y0 = 400 + Math.floor(i / 3) * 150;
        txt(ctx, l.toLocaleUpperCase('tr-TR'), x, y0, 24, 600, rgba(fg, .78), 'left', 'alphabetic', 2);
        txt(ctx, v + (un ? ' ' + un : ''), x, y0 + 68, 54, 700, fg);
      });
      shadowOn(ctx, false);
      return;
    }
    statsRow(ctx, w, h, s, data.A, fg);
  },
  band(ctx, w, h, s, data, col, ft, tc) {
    const { A } = data, fg = tc && !isLight(tc) === false ? tc : (tc || '#FFFFFF');
    ctx.fillStyle = 'rgba(10,10,12,.82)'; ctx.fillRect(0, 0, w, h);
    ctx.fillStyle = 'rgba(255,255,255,.08)'; ctx.fillRect(0, 0, w, 2);
    const m = 40, ms = h - 2 * m;
    ctx.save(); ctx.translate(m, m); drawRouteIn(ctx, ms, ms, s, data, col, ft, { radius: s.shape === 'daire' ? ms / 2 : s.shape === 'keskin' ? 0 : 22, pad: .1 }); ctx.restore();
    const x0 = m * 2 + ms, bandFg = isLight(fg) ? fg : '#FFFFFF';
    txt(ctx, data.title || '', x0, m + 44, 34, 650, bandFg);
    txt(ctx, data.subtitle || '', x0, m + 88, 26, 500, rgba(bandFg, .6));
    const f = fieldList(s).slice(0, 4);
    const cw = (w - x0 - m) / f.length, vs = f.length > 3 ? 44 : 54;
    f.forEach((k, i) => {
      const [lab, val, unit] = fieldValue(k, A), x = x0 + i * cw, y = h - m - 20;
      txt(ctx, lab, x, y - 70, 24, 550, rgba(bandFg, .6));
      const vw = txt(ctx, val, x, y, vs, 700, bandFg, 'left', 'alphabetic', -1);
      if (unit) txt(ctx, ' ' + unit, x + vw, y, 24, 600, rgba(bandFg, .7));
      if (i) { ctx.fillStyle = 'rgba(255,255,255,.14)'; ctx.fillRect(x - 18, y - 100, 2, 110); }
    });
  },
  card(ctx, w, h, s, data, col, ft, tc) {
    const { A } = data, light = s.mapStyle === 'acik' || s.mapStyle === 'renkli' || s.mapStyle === 'voyager' || s.mapStyle === 'topo';
    const rows = gridOf(fieldList(s).length).rows;
    rr(ctx, 0, 0, w, h, s.shape === 'keskin' ? 0 : 40); ctx.fillStyle = light ? 'rgba(255,255,255,.96)' : 'rgba(14,14,16,.9)'; ctx.fill();
    const fg = tc || (light ? '#0A0A0A' : '#fff'), sub = rgba(fg, .58);
    txt(ctx, data.title || '', 44, 82, 40, 700, fg);
    txt(ctx, data.subtitle || '', 44, 128, 26, 500, sub);
    const mh = h - 160 - 20 - 210 * rows - 20;
    ctx.save(); ctx.translate(24, 160); drawRouteIn(ctx, w - 48, mh, s, data, col === '#FFFFFF' && light ? '#0A0A0A' : col, ft, { radius: s.shape === 'daire' ? Math.min(w - 48, mh) / 2 : s.shape === 'keskin' ? 0 : 26, pad: .1 }); ctx.restore();
    ctx.save(); ctx.translate(0, 160 + mh + 20); statsRow(ctx, w, 210 * rows, s, A, fg, false); ctx.restore();
  },
};
