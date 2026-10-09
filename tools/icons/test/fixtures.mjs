// Shared by the icon tests; import it before anything from tools/icons. It points ICONS_CACHE_DIR (the cache and the
// cross-process rate gate) at a fresh temporary folder for this process, removed at exit, so no test touches the real
// cache or the network. It also makes PNGs, stub answers and throwaway data and pack folders.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import zlib from 'node:zlib';

export const CACHE = fs.mkdtempSync(path.join(os.tmpdir(), 'icons-cache-test-'));
process.env.ICONS_CACHE_DIR = CACHE;
const temps = [CACHE];
process.on('exit', () => temps.forEach((d) => fs.rmSync(d, { recursive: true, force: true })));

/** A new empty folder, removed at exit. */
export function tempDir(prefix = 'icons-test-') {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), prefix));
  temps.push(d);
  return d;
}

/** A transparent RGBA PNG of w x h pixels; `seed` changes the bytes (one pixel's alpha) without changing the size. */
export function png(w, h, seed = 0) {
  const chunk = (type, data) => {
    const head = Buffer.alloc(4);
    head.writeUInt32BE(data.length);
    const body = Buffer.concat([Buffer.from(type, 'latin1'), data]);
    const crc = Buffer.alloc(4);
    crc.writeUInt32BE(zlib.crc32(body));
    return Buffer.concat([head, body, crc]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // RGBA
  const rows = Buffer.alloc((w * 4 + 1) * h);
  rows[4] = seed & 0xff;
  const sig = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  return Buffer.concat([sig, chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(rows)), chunk('IEND', Buffer.alloc(0))]);
}

/**
 * Replaces globalThis.fetch for the duration of `fn`; returns the calls [{url, at, headers}]. `answer(url)` gives
 * {status, body, type} (status defaults to 200) or throws to stand for a network error.
 */
export async function withFetch(fn, answer) {
  const calls = [];
  const real = globalThis.fetch;
  globalThis.fetch = async (url, init = {}) => {
    calls.push({ url: String(url), at: Date.now(), headers: init.headers ?? {} });
    const a = answer(String(url));
    return new Response(a.body ?? null, { status: a.status ?? 200, headers: a.type ? { 'content-type': a.type } : {} });
  };
  try {
    await fn();
  } finally {
    globalThis.fetch = real;
  }
  return calls;
}

/** A game/data folder naming these item and skill IDs (one item through a quest's item_icon_key only). */
export function dataDir({ items = [], keyed = [], skills = [] }) {
  const root = tempDir('icons-data-');
  const write = (rel, obj) => {
    fs.mkdirSync(path.dirname(path.join(root, rel)), { recursive: true });
    fs.writeFileSync(path.join(root, rel), JSON.stringify(obj));
  };
  items.forEach((id, i) => write(`canonical/items/${i + 1}.json`, { id: String(i + 1), game_item_id: id }));
  write('canonical/quests/1.json', { rewards: keyed.map((id) => ({ item_icon_key: id })) });
  write('canonical/formulas/job.json', { skills: skills.map((id) => ({ skill_id: id })) });
  return root;
}

/** maplestory.io's metadata answer for an item, with the two origins. */
export function itemJson(id, icon = { x: -3, y: 30 }, iconRaw = { x: -3, y: 30 }) {
  return JSON.stringify({ id: Number(id), metaInfo: { iconOrigin: { ...icon, isEmpty: false }, iconRawOrigin: { ...iconRaw, isEmpty: false } } });
}
