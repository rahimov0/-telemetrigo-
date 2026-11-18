// Fotoğraf + aktivite verisi şablonları. Tasarım birimi: 1080 genişlik (u = W/1080).
import { fitRoute, routePath, visibleRange, fmtDur, fmtPace, fmtKm, fmtNum } from './activity.js';
import { drawTiles, MAP_STYLES } from './tiles.js';
import { TYPES } from './store.js';

export const TEMPLATES = {
  rota: 'Rota + değerler', buyuk: 'Büyük rakam', bant: 'Alt bant', kart: 'Harita kartı', saydam: 'Saydam etiket',
};
export const FORMATS = { '9:16': [1080, 1920], '4:5': [1080, 1350], '1:1': [1080, 1080], 'orij': null };
export const ROUTE_COLORS = { turuncu: '#FF5A1F', beyaz: '#FFFFFF', sari: '#FFD23F', yesil: '#4ADE80', mavi: '#38BDF8', kirmizi: '#FB4D4D', siyah: '#0A0A0A' };
export const FIELDS = {
  dist: 'Mesafe', time: 'Süre', pace: 'Tempo / hız', gain: 'Yükseliş', max: 'Maks hız', elapsed: 'Geçen süre', steps: 'Adım', kcal: 'Kalori',
};
const FONT = '-apple-system, BlinkMacSystemFont, "SF Pro Display", "Segoe UI", system-ui, Roboto, Arial, sans-serif';

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

// Blok tanımları: { w, h } (u biriminde) + çizim. Konum: merkez (0..1).
function layout(tpl, W, H) {
  const tall = H / W > 1.5;
  switch (tpl) {
    case 'rota': return { route: { w: 760, h: tall ? 760 : 560, cx: .5, cy: tall ? .44 : .4 }, stats: { w: 980, h: 210, cx: .5, cy: tall ? .82 : .84 } };
    case 'buyuk': return { route: { w: 380, h: 380, cx: .74, cy: tall ? .2 : .24 }, stats: { w: 980, h: 520, cx: .5, cy: tall ? .74 : .66 } };
    case 'bant': return { band: { w: 1080, h: 420, cx: .5, cy: 1 - 210 / (H / (W / 1080)) } };
    case 'kart': return { card: { w: 960, h: tall ? 1120 : Math.min(1180, H / (W / 1080) - 120), cx: .5, cy: .5 } };
    case 'saydam': return { route: { w: 860, h: tall ? 900 : 640, cx: .5, cy: tall ? .4 : .38 }, stats: { w: 980, h: 210, cx: .5, cy: tall ? .78 : .84 } };
  }
  return {};
}

/** Çiz. s = { tpl, W, H, photo, pan:{x,y,z}, mapStyle, color, fields[], hide, sign, pos:{id:{cx,cy}}, scale:{id} }
 *  data = { g, A, title }  Dönüş: blok kutuları (sürükleme için, piksel) */
export function compose(ctx, s, data, { fetchTiles = true } = {}) {
  if (s.fields && !(data.A?.steps > 0)) s = { ...s, fields: s.fields.filter(k => k !== 'steps') };
  if (s.fields && !(data.A?.kcal > 0)) s = { ...s, fields: s.fields.filter(k => k !== 'kcal') };
  const { W, H } = s, u = W / 1080, { g, A } = data;
  ctx.clearRect(0, 0, W, H);
  // arka plan fotoğraf
  if (s.photo && s.tpl !== 'saydam') {
    const p = s.photo, z = Math.max(1, s.pan?.z || 1);
    const k = Math.max(W / p.width, H / p.height) * z, dw = p.width * k, dh = p.height * k;
    const ox = (W - dw) / 2 + (s.pan?.x || 0) * (dw - W) / 2, oy = (H - dh) / 2 + (s.pan?.y || 0) * (dh - H) / 2;
    ctx.drawImage(p, ox, oy, dw, dh);
    // okunabilirlik: hafif alt/üst karartma
    const gr = ctx.createLinearGradient(0, 0, 0, H);
    gr.addColorStop(0, 'rgba(0,0,0,.18)'); gr.addColorStop(.45, 'rgba(0,0,0,0)'); gr.addColorStop(.62, 'rgba(0,0,0,0)'); gr.addColorStop(1, 'rgba(0,0,0,.5)');
    ctx.fillStyle = gr; ctx.fillRect(0, 0, W, H);
  } else if (s.tpl !== 'saydam') { ctx.fillStyle = '#0B0B0D'; ctx.fillRect(0, 0, W, H); }

  const L = layout(s.tpl, W, H), boxes = {};
  const col = ROUTE_COLORS[s.color] || '#fff';
  for (const [id, b] of Object.entries(L)) {
    const sc = (s.scale?.[id] || 1), pos = s.pos?.[id] || b, w = b.w * u * sc, h = b.h * u * sc;
    const x = pos.cx * W - w / 2, y = pos.cy * H - h / 2;
    boxes[id] = { x, y, w, h };
    ctx.save(); ctx.translate(x, y); ctx.scale(u * sc, u * sc);
    DRAW[id](ctx, b.w, b.h, s, data, col, fetchTiles);
    ctx.restore();
  }
  if (s.sign !== false) {
    const dark = s.tpl === 'saydam' ? false : true;
    txt(ctx, 'TelemetriGo', W - 36 * u, H - 34 * u, 22 * u, 600, dark ? 'rgba(255,255,255,.6)' : 'rgba(255,255,255,.75)', 'right', 'alphabetic', 0.5 * u);
  }
  return boxes;
}

function shadowOn(ctx, on = true) { ctx.shadowColor = on ? 'rgba(0,0,0,.45)' : 'transparent'; ctx.shadowBlur = on ? 18 : 0; ctx.shadowOffsetY = on ? 2 : 0; }

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
    txt(ctx, MAP_STYLES[style].attr, w - 14, h - 12, 15, 500, MAP_STYLES[style].dark ? 'rgba(255,255,255,.7)' : 'rgba(0,0,0,.6)', 'right');
  }
  const path = routePath(g, F.P, i0, i1);
  ctx.lineCap = 'round'; ctx.lineJoin = 'round';
  const onMap = style && style !== 'yok';
  // kontur (harita üzerinde okunurluk)
  ctx.strokeStyle = onMap ? (col === '#0A0A0A' ? '#fff' : 'rgba(0,0,0,.55)') : 'rgba(0,0,0,.35)';
  ctx.lineWidth = onMap ? 15 : 14; if (!onMap) shadowOn(ctx); ctx.stroke(path); shadowOn(ctx, false);
  ctx.strokeStyle = col; ctx.lineWidth = 9; ctx.stroke(path);
  // başlangıç ve bitiş
  const [sx, sy] = F.P(g.x[i0], g.y[i0]), [ex, ey] = F.P(g.x[i1], g.y[i1]);
  for (const [x, y, f] of [[sx, sy, '#fff'], [ex, ey, col]]) {
    ctx.beginPath(); ctx.arc(x, y, 13, 0, 7); ctx.fillStyle = f; ctx.fill(); ctx.lineWidth = 5; ctx.strokeStyle = 'rgba(0,0,0,.7)'; ctx.stroke();
  }
  // fotoğraf işaretleri
  for (const ph of data.pins || []) {
    if (ph.i < i0 || ph.i > i1) continue;
    const [x, y] = F.P(g.x[ph.i], g.y[ph.i]);
    ctx.beginPath(); ctx.arc(x, y, 10, 0, 7); ctx.fillStyle = '#fff'; ctx.fill(); ctx.lineWidth = 4; ctx.strokeStyle = '#000'; ctx.stroke();
  }
}

function statsRow(ctx, w, h, s, A, color = '#fff', shadow = true) {
  const f = (s.fields?.length ? s.fields : ['dist', 'time', 'pace']).slice(0, 4), n = f.length, cw = w / n;
  f.forEach((k, i) => {
    const [lab, val, unit] = fieldValue(k, A), cx = cw * i + cw / 2;
    if (shadow) shadowOn(ctx);
    txt(ctx, lab.toLocaleUpperCase('tr-TR'), cx, 58, 26, 600, color === '#fff' ? 'rgba(255,255,255,.82)' : 'rgba(0,0,0,.6)', 'center', 'alphabetic', 2);
    ctx.font = `700 ${n > 3 ? 64 : 76}px ${FONT}`;
    const vw = ctx.measureText(val).width; ctx.font = `600 30px ${FONT}`; const uw = unit ? ctx.measureText(' ' + unit).width : 0;
    const x0 = cx - (vw + uw) / 2;
    txt(ctx, val, x0, 150, n > 3 ? 64 : 76, 700, color, 'left', 'alphabetic', -1);
    if (unit) txt(ctx, ' ' + unit, x0 + vw, 150, 30, 600, color === '#fff' ? 'rgba(255,255,255,.85)' : 'rgba(0,0,0,.65)');
    shadowOn(ctx, false);
    if (i) { ctx.fillStyle = color === '#fff' ? 'rgba(255,255,255,.28)' : 'rgba(0,0,0,.15)'; ctx.fillRect(cw * i, 30, 2, 140); }
  });
}

const DRAW = {
  route(ctx, w, h, s, data, col, ft) { drawRouteIn(ctx, w, h, s, data, col, ft, { radius: 36, pad: s.mapStyle && s.mapStyle !== 'yok' ? .1 : .04 }); },
  stats(ctx, w, h, s, data) {
    if (s.tpl === 'buyuk') {
      const { A } = data, [lab, val, unit] = fieldValue((s.fields || [])[0] || 'dist', A);
      shadowOn(ctx);
      txt(ctx, (TYPES[A.type]?.name || '').toLocaleUpperCase('tr-TR') + ' · ' + lab.toLocaleUpperCase('tr-TR'), 30, 70, 30, 650, 'rgba(255,255,255,.85)', 'left', 'alphabetic', 3);
      const vw = txt(ctx, val, 22, 300, 250, 800, '#fff', 'left', 'alphabetic', -10);
      txt(ctx, unit, 40 + vw, 300, 64, 700, 'rgba(255,255,255,.9)');
      const rest = (s.fields?.length ? s.fields.slice(1) : ['time', 'pace']).slice(0, 3);
      rest.forEach((k, i) => {
        const [l, v, un] = fieldValue(k, A), x = 30 + i * 320;
        txt(ctx, l.toLocaleUpperCase('tr-TR'), x, 400, 24, 600, 'rgba(255,255,255,.78)', 'left', 'alphabetic', 2);
        txt(ctx, v + (un ? ' ' + un : ''), x, 468, 54, 700, '#fff');
      });
      shadowOn(ctx, false);
      return;
    }
    statsRow(ctx, w, h, s, data.A);
  },
  band(ctx, w, h, s, data, col, ft) {
    const { A } = data;
    ctx.fillStyle = 'rgba(10,10,12,.82)'; ctx.fillRect(0, 0, w, h);
    ctx.fillStyle = 'rgba(255,255,255,.08)'; ctx.fillRect(0, 0, w, 2);
    const m = 40, ms = h - 2 * m;
    ctx.save(); ctx.translate(m, m); drawRouteIn(ctx, ms, ms, s, data, col, ft, { radius: 22, pad: .1 }); ctx.restore();
    const x0 = m * 2 + ms;
    txt(ctx, data.title || '', x0, m + 44, 34, 650, '#fff');
    txt(ctx, data.subtitle || '', x0, m + 88, 26, 500, 'rgba(255,255,255,.6)');
    const f = (s.fields?.length ? s.fields : ['dist', 'time', 'pace']).slice(0, 4);
    const cw = (w - x0 - m) / f.length, vs = f.length > 3 ? 44 : 54;
    f.forEach((k, i) => {
      const [lab, val, unit] = fieldValue(k, A), x = x0 + i * cw, y = h - m - 20;
      txt(ctx, lab, x, y - 70, 24, 550, 'rgba(255,255,255,.6)');
      const vw = txt(ctx, val, x, y, vs, 700, '#fff', 'left', 'alphabetic', -1);
      if (unit) txt(ctx, ' ' + unit, x + vw, y, 24, 600, 'rgba(255,255,255,.7)');
      if (i) { ctx.fillStyle = 'rgba(255,255,255,.14)'; ctx.fillRect(x - 18, y - 100, 2, 110); }
    });
  },
  card(ctx, w, h, s, data, col, ft) {
    const { A } = data, light = s.mapStyle === 'acik' || s.mapStyle === 'renkli';
    rr(ctx, 0, 0, w, h, 40); ctx.fillStyle = light ? 'rgba(255,255,255,.96)' : 'rgba(14,14,16,.9)'; ctx.fill();
    const fg = light ? '#0A0A0A' : '#fff', sub = light ? 'rgba(0,0,0,.55)' : 'rgba(255,255,255,.6)';
    txt(ctx, data.title || '', 44, 82, 40, 700, fg);
    txt(ctx, data.subtitle || '', 44, 128, 26, 500, sub);
    const mh = h - 160 - 230;
    ctx.save(); ctx.translate(24, 160); drawRouteIn(ctx, w - 48, mh, { ...s, mapStyle: s.mapStyle === 'yok' ? 'yok' : s.mapStyle }, data, col === '#FFFFFF' && light ? '#0A0A0A' : col, ft, { radius: 26, pad: .1 }); ctx.restore();
    ctx.save(); ctx.translate(0, 160 + mh + 20); statsRow(ctx, w, 210, s, A, light ? '#0A0A0A' : '#fff', false); ctx.restore();
  },
};
