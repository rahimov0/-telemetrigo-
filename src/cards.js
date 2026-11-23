// Videoya sabit "aktivite kartı" ekleme: rota + değerler görseli, istenen saniyede ve sürede ekranda kalır.
import { compose, TEMPLATES, SHAPES, TEXT_COLORS, ROUTE_COLORS, MAX_FIELDS } from './compose.js';
import { parseGpx } from './gpx.js';
import { analyze, guessType } from './activity.js';
import { putAct, getAct, listActs, TYPES } from './store.js';
import { MAP_STYLES, tilesIdle } from './tiles.js';

export const cards = [];   // { id, actId, name, tpl, mapStyle, shape, color, textColor, bmp, t0, dur, fade, size, cx, cy, busy }
let onChange = () => {};
export const setCardsListener = f => { onChange = f; };

const CARD_TPLS = Object.fromEntries(Object.entries(TEMPLATES).filter(([k]) => k !== 'bant'));
const titleFor = (type, start) => {
  const h = new Date(start).getHours(), part = h < 5 ? 'Gece' : h < 11 ? 'Sabah' : h < 14 ? 'Öğle' : h < 18 ? 'Öğleden sonra' : h < 22 ? 'Akşam' : 'Gece';
  return `${part} ${{ yuruyus: 'yürüyüşü', kosu: 'koşusu', tirmanis: 'tırmanışı', bisiklet: 'bisiklet turu', motor: 'sürüşü', arac: 'yolculuğu' }[type] || 'aktivitesi'}`;
};
const dateStr = t => new Date(t).toLocaleDateString('tr-TR', { day: 'numeric', month: 'long', year: 'numeric' });

/** iOS uygulaması son aktiviteleri sayfa açılırken verir (window.__TG_ACTS); yerel depoya yaz. */
export async function importNative() {
  const L = window.__TG_ACTS; if (!Array.isArray(L)) return;
  for (const P of L) {
    try {
      const id = 'a' + Date.parse((P.gpx.match(/<time>([^<]+)<\/time>/) || [])[1] || '');
      if (!id || id === 'aNaN' || await getAct(id)) continue;
      const g = parseGpx(P.gpx, P.type ? { type: P.type } : {}), type = P.type || (TYPES[g.type] ? g.type : guessType(g)), A = analyze(g, type);
      await putAct({ id, name: P.name || g.name || 'GPX', type, start: g.start, end: g.end, dist: A.dist, moving: A.movingTime, gpx: P.gpx, src: 'app', steps: P.steps || null, kcal: P.kcal || null });
    } catch (e) { console.warn("import", e.message); }
  }
}

async function render(c) {
  const rec = await getAct(c.actId); if (!rec) throw new Error('Aktivite bulunamadı');
  const g = parseGpx(rec.gpx, { type: rec.type }), A = analyze(g, rec.type); A.steps = rec.steps || 0; A.kcal = rec.kcal || 0;
  const data = { g, A, title: titleFor(rec.type, g.start), subtitle: dateStr(g.start), pins: [] };
  const prefs = JSON.parse(localStorage.getItem('tg-act-prefs') || '{}');
  const S = { tpl: c.tpl, W: 1080, H: 1080, mapStyle: c.mapStyle, shape: c.shape, color: c.color, textColor: c.textColor === 'otomatik' ? 'beyaz' : c.textColor,
    font: prefs.font || 'standart', fields: prefs.fields || ['dist', 'time', 'pace'], hide: true, sign: false, transparent: true, pos: {}, scale: {} };
  const cv = document.createElement('canvas'); cv.width = 1080; cv.height = 1080; const ctx = cv.getContext('2d');
  let boxes = compose(ctx, S, data);
  if (c.mapStyle !== 'yok') { await tilesIdle(6000); boxes = compose(ctx, S, data); }
  const list = Object.values(boxes), pad = 20;
  const x0 = Math.max(0, Math.min(...list.map(b => b.x)) - pad), y0 = Math.max(0, Math.min(...list.map(b => b.y)) - pad);
  const x1 = Math.min(1080, Math.max(...list.map(b => b.x + b.w)) + pad), y1 = Math.min(1080, Math.max(...list.map(b => b.y + b.h)) + pad);
  return createImageBitmap(cv, Math.round(x0), Math.round(y0), Math.round(x1 - x0), Math.round(y1 - y0));
}

let timer = 0;
export function rebuild(c) {
  clearTimeout(timer); c.busy = true; onChange(c);
  timer = setTimeout(async () => {
    try { c.bmp = await render(c); c.err = ''; } catch (e) { c.err = e.message; }
    c.busy = false; onChange(c);
  }, 250);
}

export async function addCard(actId, dur) {
  const prefs = JSON.parse(localStorage.getItem('tg-act-prefs') || '{}');
  const c = { id: Math.random().toString(36).slice(2, 8), actId, tpl: prefs.tpl && CARD_TPLS[prefs.tpl] ? prefs.tpl : 'rota', mapStyle: prefs.edMap || 'yok', shape: prefs.shape || 'yuvarlak',
    color: prefs.color || 'turuncu', textColor: 'beyaz', t0: 0, dur: Math.min(8, Math.max(2, dur || 8)), fade: 0.5, size: 0.5, cx: 0.5, cy: 0.5, bmp: null, busy: false, err: '' };
  cards.push(c); rebuild(c); return c;
}
export function removeCard(c) { const i = cards.indexOf(c); if (i >= 0) cards.splice(i, 1); onChange(null); }

export function drawCards(ctx, W, H, t) {
  for (const c of cards) {
    if (!c.bmp) continue;
    const t1 = c.t0 + c.dur; if (t < c.t0 || t > t1) continue;
    const a = c.fade > 0 ? Math.min(1, (t - c.t0) / c.fade, (t1 - t) / c.fade) : 1;
    const w = W * c.size, h = w * c.bmp.height / c.bmp.width;
    ctx.save(); ctx.globalAlpha = Math.max(0, Math.min(1, a)); ctx.drawImage(c.bmp, c.cx * W - w / 2, c.cy * H - h / 2, w, h); ctx.restore();
  }
}
export async function activityChoices() { return listActs(); }
export { CARD_TPLS, SHAPES, TEXT_COLORS, ROUTE_COLORS, MAP_STYLES, titleFor, dateStr, MAX_FIELDS };
