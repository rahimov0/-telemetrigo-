// Aktivite geçmişi: tarayıcıda IndexedDB (yalnızca bu cihazda).
const DB = 'telemetrigo', ST = 'acts';
let dbp = null;
function db() {
  if (!dbp) dbp = new Promise((res, rej) => {
    const r = indexedDB.open(DB, 1);
    r.onupgradeneeded = () => { const s = r.result.createObjectStore(ST, { keyPath: 'id' }); s.createIndex('start', 'start'); };
    r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error);
  });
  return dbp;
}
const tx = async (mode, fn) => { const d = await db(); return new Promise((res, rej) => { const t = d.transaction(ST, mode); const out = fn(t.objectStore(ST)); t.oncomplete = () => res(out?.result ?? out); t.onerror = () => rej(t.error); }); };
export const putAct = a => tx('readwrite', s => s.put(a));
export const delAct = id => tx('readwrite', s => s.delete(id));
export const getAct = id => tx('readonly', s => s.get(id));
export async function listActs() {
  const all = await tx('readonly', s => s.getAll());
  return (all || []).map(({ gpx, ...m }) => m).sort((a, b) => b.start - a.start);
}
export const TYPES = {
  yuruyus: { name: 'Yürüyüş', pace: true }, kosu: { name: 'Koşu', pace: true },
  bisiklet: { name: 'Bisiklet', pace: false }, motor: { name: 'Motor', pace: false },
};
