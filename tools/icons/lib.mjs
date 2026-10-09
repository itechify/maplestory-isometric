// maplestory.io fetch/cache helpers for the icon pack (build time only; the game never talks to maplestory.io).
// The pattern is tools/meowdb/lib.mjs's, for binary bodies.
//
// - Cache first. fetchAnswer reads tools/icons/.cache/ (git-ignored; ICONS_CACHE_DIR overrides the folder) first. A
//   cache miss is fetched once and written there, so the next run reads it from the cache and makes no request.
// - Only definitive answers are cached: a 200 (whatever its body) and a 404. Anything else (a network error, a timeout,
//   403, 429, 5xx) is no answer: the request is tried a few times, then given up for this run, and never cached.
// - >= 1.2 s between network requests across ALL processes (the gate file lives in the cache folder). After three
//   URLs in a row got no answer, the run stops asking: a build without a network ends in seconds, not an hour.
// - --refresh re-fetches cached answers. --offline never fetches: a URL missing from the cache gets no answer.
//   --offline with --refresh is an error.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// The one place the source is pinned: maplestory.io's Classic World (MCW), version CBT2 (its second closed test).
// Moving the version is #57.
export const SOURCE = { service: 'maplestory.io', region: 'MCW', version: 'CBT2' };
export const API = 'https://maplestory.io/api';
const HERE = path.dirname(fileURLToPath(import.meta.url));
export const CACHE_DIR = process.env.ICONS_CACHE_DIR ? path.resolve(process.env.ICONS_CACHE_DIR) : path.join(HERE, '.cache');
const UA = 'MisoStory icon pack fetcher (+https://github.com/itechify/maplestory-isometric)';
const MIN_GAP_MS = 1200; // global across processes (parallel runs share one polite request budget)
const GATE_FILE = path.join(CACHE_DIR, '.last_fetch');
const TIMEOUT_MS = 30000;
const ATTEMPTS = 3;
const GIVE_UP_AFTER = 3; // URLs in a row without an answer before the run stops asking

/** The run's view of the network: `down` once GIVE_UP_AFTER URLs in a row got no answer (tests reset it). */
export const network = { failures: 0, down: false };

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const cacheKey = (url) => url.replace(/^https?:\/\/[^/]+/, '').replace(/^\/+/, '').replace(/[^A-Za-z0-9._-]+/g, '_').slice(0, 180);

/** An item's metadata (its JSON carries metaInfo.iconOrigin and metaInfo.iconRawOrigin). */
export const itemUrl = (id) => `${API}/${SOURCE.region}/${SOURCE.version}/item/${id}`;

/** An item icon variant (icon, iconRaw): a PNG. */
export const itemIconUrl = (id, variant) => `${itemUrl(id)}/${variant}`;

/**
 * A skill icon variant (icon, iconMouseOver, iconDisabled): a 32x32 PNG. Without `_Canvas` the same path answers a
 * blank 1x1 PNG. The .img file is the job's: skill 0001000 is job 000 (Beginner), 1001004 is job 100.
 */
export const skillIconUrl = (id, variant) =>
  `${API}/wz/img/${SOURCE.region}/${SOURCE.version}/Skill/_Canvas/${jobImg(id)}/skill/${id}/${variant}`;

/** The Skill.wz image of a skill's job: the skill ID without its last four digits, at least three digits wide. */
export function jobImg(skillId) {
  return String(Math.floor(Number(skillId) / 10000)).padStart(3, '0') + '.img';
}

/** Cross-process rate gate: wait until MIN_GAP_MS has passed since the last request by any process. */
async function gate() {
  const lock = GATE_FILE + '.lock';
  for (;;) {
    let fd;
    try {
      fd = fs.openSync(lock, 'wx');
    } catch {
      try { if (Date.now() - fs.statSync(lock).mtimeMs > 10000) fs.rmSync(lock, { force: true }); } catch {}
      await sleep(100 + Math.random() * 200);
      continue;
    }
    try {
      const last = fs.existsSync(GATE_FILE) ? Number(fs.readFileSync(GATE_FILE, 'utf8')) || 0 : 0;
      const wait = last + MIN_GAP_MS - Date.now();
      if (wait > 0) await sleep(wait);
      fs.writeFileSync(GATE_FILE, String(Date.now()));
      return;
    } finally {
      fs.closeSync(fd);
      fs.rmSync(lock, { force: true });
    }
  }
}

/** The cache files of a URL ({bodyFile, metaFile}; they may not exist). */
export function cacheFiles(url) {
  const key = cacheKey(url);
  return { bodyFile: path.join(CACHE_DIR, key + '.body'), metaFile: path.join(CACHE_DIR, key + '.meta.json') };
}

/** True when a URL's answer is in the local cache. */
export function hasCached(url) {
  const { bodyFile, metaFile } = cacheFiles(url);
  return fs.existsSync(bodyFile) && fs.existsSync(metaFile);
}

/**
 * The answer to a GET of `url`, cache first. A definitive answer is
 *   {url, status: 200 | 404, contentType, body: Buffer, retrieved_at, fromCache}
 * and no answer is {url, status: null, reason, fromCache: false} (offline and not cached, a network error, a timeout,
 * another status). `refresh` and `offline` default to the --refresh and --offline flags.
 */
export async function fetchAnswer(url, { refresh = process.argv.includes('--refresh'), offline = process.argv.includes('--offline'), attempts = ATTEMPTS } = {}) {
  if (refresh && offline) throw new Error('--refresh re-fetches every answer and --offline fetches none: pass one or the other');
  const { bodyFile, metaFile } = cacheFiles(url);
  if (!refresh && fs.existsSync(bodyFile) && fs.existsSync(metaFile)) {
    let meta = null;
    try {
      meta = JSON.parse(fs.readFileSync(metaFile, 'utf8'));
    } catch {
      meta = null; // a damaged cache entry is fetched again
    }
    if (meta && (meta.status === 200 || meta.status === 404)) {
      return { url, status: meta.status, contentType: meta.content_type, body: fs.readFileSync(bodyFile), retrieved_at: meta.retrieved_at, fromCache: true };
    }
  }
  if (offline) return { url, status: null, reason: 'not cached (--offline)', fromCache: false };
  if (network.down) return { url, status: null, reason: 'network unavailable', fromCache: false };
  fs.mkdirSync(CACHE_DIR, { recursive: true });
  let reason = '';
  for (let attempt = 1; attempt <= attempts; attempt++) {
    if (attempt > 1) await sleep(2000 * (attempt - 1));
    await gate();
    let res;
    try {
      res = await fetch(url, { headers: { 'User-Agent': UA, Accept: 'image/png,application/json;q=0.9,*/*;q=0.8' }, signal: AbortSignal.timeout(TIMEOUT_MS) });
    } catch (e) {
      reason = `network error: ${e.cause?.code ?? e.name ?? e.message}`;
      continue;
    }
    if (res.status === 200 || res.status === 404) {
      const body = Buffer.from(await res.arrayBuffer());
      const contentType = res.headers.get('content-type') ?? '';
      const retrieved_at = new Date().toISOString();
      fs.writeFileSync(bodyFile, body);
      fs.writeFileSync(metaFile, JSON.stringify({ url, status: res.status, content_type: contentType, retrieved_at }, null, 1));
      network.failures = 0;
      return { url, status: res.status, contentType, body, retrieved_at, fromCache: false };
    }
    reason = `http ${res.status}`;
  }
  if (++network.failures >= GIVE_UP_AFTER && !network.down) {
    network.down = true;
    console.error(`icons: ${GIVE_UP_AFTER} requests in a row got no answer (last: ${reason}); not asking maplestory.io again this run`);
  }
  return { url, status: null, reason, fromCache: false };
}
