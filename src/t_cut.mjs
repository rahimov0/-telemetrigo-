import { buildTrack, autoSync } from './app/gpx.js';
const T0 = Date.UTC(2026, 10, 15, 12, 0, 0);
const v = t => 14 + 6 * Math.sin(t / 9) + 3 * Math.sin(t / 2.7 + 1) + 2 * Math.sin(t / 1.3) + 4 * Math.sin(t / 61) + 2 * Math.sin(t * t / 4000);
const dv = t => (6 / 9) * Math.cos(t / 9) + (3 / 2.7) * Math.cos(t / 2.7 + 1) + (2 / 1.3) * Math.cos(t / 1.3) + (4 / 61) * Math.cos(t / 61) + 2 * Math.cos(t * t / 4000) * (2 * t / 4000);
const G = 3000;
const pts = []; let x = 0;
for (let s = 0; s <= G; s++) { x += v(s); pts.push({ t: T0 + s * 1000, lat: 41 + x / 111000, lon: 29, ele: 30, spd: v(s) }); }
const g = buildTrack(pts, 'test');
function two(base, tel) {
  const gdur = (g.end - g.start) / 1000, R = Math.min(3600, Math.max(300, gdur));
  const c = autoSync(g, base, tel, { range: R, step: 0.5 });
  const f = autoSync(g, base - c.offset * 1000, tel, { range: 1.5, step: 0.1 });
  return { offset: Math.round((f.offset + c.offset) * 10) / 10, score: f.score };
}
let ok = 0, n = 0;
for (const [startSec, dur] of [[1200, 120], [300, 90], [2500, 120], [0, 120], [1800, 60]]) {
  for (const clockErr of [0, 5.5]) {
    const N = dur * 100, lon = new Float32Array(N);
    for (let i = 0; i < N; i++) lon[i] = dv(startSec + i / 100) / 9.80665 + 0.03 * (Math.random() * 2 - 1);
    const base = T0 + clockErr * 1000;                       // geçersiz (kesim sonrası) başlangıç saati
    const realStart = T0 + startSec * 1000;
    const want = (base - realStart) / 1000;
    const r = two(base, { lon });
    const good = Math.abs(r.offset - want) < 0.6; n++; if (good) ok++;
    console.log(`klip ${startSec}s+${dur}s saatHata ${clockErr}: beklenen ${want} bulunan ${r.offset} skor ${r.score.toFixed(2)} ${good ? 'OK' : 'HATA'}`);
  }
}
console.log(`${ok}/${n}`);
