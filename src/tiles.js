// Harita döşemeleri (web mercator). Rota yerel metre koordinatında (x doğu, y kuzey) çizilir;
// döşemeler aynı koordinata afin dönüşümle oturtulur. Tarayıcıdan CORS ile çekilir, tuval kirlenmez.
export const MAP_STYLES = {
  yok:    { name: 'Çizgi' },
  koyu:   { name: 'Koyu', url: (z, x, y) => `https://${'abcd'[(x + y) % 4]}.basemaps.cartocdn.com/dark_all/${z}/${x}/${y}.png`, px: 256, max: 20, attr: '© OpenStreetMap © CARTO', dark: true },
  acik:   { name: 'Açık', url: (z, x, y) => `https://${'abcd'[(x + y) % 4]}.basemaps.cartocdn.com/light_all/${z}/${x}/${y}.png`, px: 256, max: 20, attr: '© OpenStreetMap © CARTO', dark: false },
  renkli: { name: 'Renkli', url: (z, x, y) => `https://${'abcd'[(x + y) % 4]}.basemaps.cartocdn.com/rastertiles/voyager/${z}/${x}/${y}.png`, px: 256, max: 20, attr: '© OpenStreetMap © CARTO', dark: false },
  uydu:   { name: 'Uydu', url: (z, x, y) => `https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/${z}/${y}/${x}`, px: 256, max: 19, attr: 'Görüntü © Esri', dark: true },
};
const C = 2 * Math.PI * 6371008.8;
const cache = new Map();          // anahtar → ImageBitmap | Promise | 'err'
let listeners = new Set();
export const onTile = fn => { listeners.add(fn); return () => listeners.delete(fn); };
let errCount = 0, inflight = 0;
export let lastZoom = 0;
export const tileErrors = () => errCount;

const worldX = (lon, z) => (lon + 180) / 360 * 256 * 2 ** z;
const worldY = (lat, z) => { const s = Math.sin(lat * Math.PI / 180); return (0.5 - Math.log((1 + s) / (1 - s)) / (4 * Math.PI)) * 256 * 2 ** z; };
const mpp = (lat, z) => C * Math.cos(lat * Math.PI / 180) / (256 * 2 ** z);

function load(style, z, x, y) {
  const key = `${style}/${z}/${x}/${y}`, have = cache.get(key);
  if (have) return have;
  const S = MAP_STYLES[style]; inflight++;
  const p = fetch(S.url(z, x, y), { mode: 'cors', credentials: 'omit' })
    .then(r => { if (!r.ok) throw new Error(r.status); return r.blob(); })
    .then(b => createImageBitmap(b))
    .then(bmp => { cache.set(key, bmp); listeners.forEach(f => f()); return bmp; })
    .catch(() => { cache.set(key, 'err'); errCount++; listeners.forEach(f => f()); return 'err'; })
    .finally(() => { inflight--; });
  cache.set(key, p);
  return p;
}
const ready = v => v && typeof v === 'object' && !(v instanceof Promise);

// Ekrandaki ölçeğe göre uygun yakınlaştırma (döşemenin her pikseli ~1 ekran pikseli)
export function zoomFor(style, lat, pxPerMeter) {
  const S = MAP_STYLES[style], k = S.px / 256;
  const z = Math.log2(C * Math.cos(lat * Math.PI / 180) * pxPerMeter / (256 * k));
  return Math.max(2, Math.min(S.max, Math.round(z)));
}

/** Döşemeleri çiz.
 *  geo = { lat0, lon0 } yerel izdüşümün merkezi (x=0,y=0)
 *  toScreen = DOMMatrix: yerel metre (x doğu, y kuzey) → ctx koordinatı (mevcut ctx dönüşümüne göre)
 *  view = [x0,y0,x1,y1] metre cinsinden görünür alan (rotasyon varsa kapsayan kutu)
 *  fetchMissing: eksik döşemeleri indir (önizleme). Dönüş: eksik döşeme var mı */
export function drawTiles(ctx, style, geo, toScreen, view, { fetchMissing = true } = {}) {
  const S = MAP_STYLES[style]; if (!S?.url) return false;
  const m = ctx.getTransform().multiply(toScreen);
  const pxPerMeter = Math.sqrt(Math.abs(m.a * m.d - m.b * m.c));
  const z = zoomFor(style, geo.lat0, pxPerMeter), res = mpp(geo.lat0, z); lastZoom = z;
  const X0 = worldX(geo.lon0, z), Y0 = worldY(geo.lat0, z);
  // görünür alan → döşeme aralığı
  const wx = x => X0 + x / res, wy = y => Y0 - y / res;
  const tx0 = Math.floor(wx(view[0]) / 256), tx1 = Math.floor(wx(view[2]) / 256);
  const ty0 = Math.floor(wy(view[3]) / 256), ty1 = Math.floor(wy(view[1]) / 256);
  if ((tx1 - tx0 + 1) * (ty1 - ty0 + 1) > 400) return false;
  ctx.save();
  ctx.transform(toScreen.a, toScreen.b, toScreen.c, toScreen.d, toScreen.e, toScreen.f);
  ctx.scale(res, -res); ctx.translate(-X0, -Y0);       // artık dünya pikseli (z) koordinatındayız
  ctx.imageSmoothingEnabled = true; ctx.imageSmoothingQuality = 'high';
  let missing = false; const n = 2 ** z;
  for (let ty = ty0; ty <= ty1; ty++) for (let tx = tx0; tx <= tx1; tx++) {
    if (ty < 0 || ty >= n) continue;
    const x = ((tx % n) + n) % n;
    const v = cache.get(`${style}/${z}/${x}/${ty}`);
    if (ready(v)) { ctx.drawImage(v, tx * 256, ty * 256, 256.6, 256.6); continue; }
    if (v !== 'err') { missing = true; if (fetchMissing && !v) load(style, z, x, ty); }
    // yüklenene kadar üst seviyedeki döşemeyi büyüterek göster
    for (let up = 1; up <= 4; up++) {
      const pz = z - up, px = x >> up, py = ty >> up, f = 2 ** up, pv = cache.get(`${style}/${pz}/${px}/${py}`);
      if (!ready(pv)) continue;
      const sub = pv.width / f, sx = (x - px * f) * sub, sy = (ty - py * f) * sub;
      ctx.drawImage(pv, sx, sy, sub, sub, tx * 256, ty * 256, 256.6, 256.6); break;
    }
  }
  ctx.restore();
  return missing;
}

/** Dışa aktarmadan önce rotanın çevresindeki döşemeleri indir.
 *  zooms: kullanılacak yakınlaştırmalar; pad: rota çevresinde metre */
export async function prefetchRoute(style, g, zooms, padM = 300, onProgress) {
  const S = MAP_STYLES[style]; if (!S?.url) return;
  const keys = new Map();
  for (const z of zooms) {
    const pad = Math.max(1, Math.ceil(padM / mpp(g.lat0, z) / 256));
    const step = Math.max(1, Math.floor(g.n / 4000));
    for (let i = 0; i < g.n; i += step) {
      const cx = Math.floor(worldX(g.lon[i], z) / 256), cy = Math.floor(worldY(g.lat[i], z) / 256);
      for (let dy = -pad; dy <= pad; dy++) for (let dx = -pad; dx <= pad; dx++) keys.set(`${z}/${cx + dx}/${cy + dy}`, [z, cx + dx, cy + dy]);
    }
  }
  const list = [...keys.values()].slice(0, 1500); let done = 0;
  const queue = list.slice(), workers = Array.from({ length: 6 }, async () => {
    while (queue.length) { const [z, x, y] = queue.shift(); await load(style, z, x, y); onProgress?.(++done / list.length); }
  });
  await Promise.all(workers);
}
export { mpp as metersPerPixel };
// Bekleyen indirmeler bitene kadar bekle (en fazla ms)
export async function tilesIdle(ms = 8000) {
  const t0 = Date.now();
  while (inflight > 0 && Date.now() - t0 < ms) await new Promise(r => setTimeout(r, 100));
}
