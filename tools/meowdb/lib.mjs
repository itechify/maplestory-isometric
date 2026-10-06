// MeowDB MS Classic fetch/cache/extract helpers (development-time only; the game never talks to MeowDB).
//
// - Cache first. fetchUrl reads tools/meowdb/.cache/ (git-ignored; MEOWDB_CACHE_DIR overrides the folder) first. On a
//   cache miss it serves a MeowDB API body captured by hand in a normal browser, when one exists for exactly that URL
//   (tools/meowdb/captures/items_api.json, read through tools/sources/captures.mjs apiCaptureFor): the result then has
//   fromCapture: true, `capture` (file, pointer, read_at note) and retrieved_at = the capture's read_at. Rendered-text
//   page captures (monster, breakable and quest pages) are never served as pages; tools/sources/captures.mjs parses
//   them for the drop join and cross-checks. Anything else is fetched once and written to the cache, so the next run
//   reads it from there.
// - >= 1.2 s between network requests across ALL processes; --refresh re-fetches cached pages (and skips the capture
//   fallback).
// - --offline never fetches: a page missing from the cache and the captures throws "not cached". The reproducibility
//   check (scripts/check_canonical.sh) runs every extractor this way. --offline with --refresh is an error.
// - Pages are Next.js App Router pages; the data lives in the React Server Component ("flight") payload pushed via
//   self.__next_f.push([1, "..."]). rsc() decodes it; jsonAt()/objectsWithKey() pull plain JSON values out of it.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { apiCaptureFor } from '../sources/captures.mjs';

export const AUTHORITY = 'MeowDB MS Classic';
export const BASE_URL = 'https://meowdb.com/msclassic'; // single constant: MeowDB is rebranding to NiaDB (old links keep working)
const HERE = path.dirname(fileURLToPath(import.meta.url));
export const CACHE_DIR = process.env.MEOWDB_CACHE_DIR ? path.resolve(process.env.MEOWDB_CACHE_DIR) : path.join(HERE, '.cache');
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36';
const MIN_GAP_MS = 1200; // global across processes (parallel extractors share one polite request budget)
const GATE_FILE = path.join(CACHE_DIR, '.last_fetch');

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const cacheKey = (p) => p.replace(/^https?:\/\/[^/]+/, '').replace(/^\/+/, '').replace(/[^A-Za-z0-9._-]+/g, '_').slice(0, 180) || 'index';

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

/** True when the command line has --offline (see the header: a cache miss throws instead of fetching). */
export function offline() {
  return process.argv.includes('--offline');
}

/** The cache files of a page path or absolute meowdb.com URL ({htmlFile, metaFile}; they may not exist). */
function cacheFiles(pathOrUrl) {
  const url = pathOrUrl.startsWith('http') ? pathOrUrl : BASE_URL + pathOrUrl;
  const key = cacheKey(url.replace(BASE_URL, '').replace(/\?/g, '_q_'));
  return {
    htmlFile: path.join(CACHE_DIR, key + (key.endsWith('.js') || key.endsWith('.json') ? '' : '.html')),
    metaFile: path.join(CACHE_DIR, key + '.meta.json'),
  };
}

/** True when a page path or URL is in the local cache (no network, no capture fallback). */
export function hasCached(pathOrUrl) {
  const { htmlFile, metaFile } = cacheFiles(pathOrUrl);
  return fs.existsSync(htmlFile) && fs.existsSync(metaFile);
}

/** Fetch BASE_URL + p (e.g. "/maps/000000010"), cache-first. Returns {html, url, retrieved_at, fromCache}. */
export async function fetchPage(p, opts = {}) {
  return fetchUrl(p.startsWith('http') ? p : BASE_URL + p, opts);
}

/**
 * Fetch any absolute meowdb.com URL (pages, /msclassic/api/... JSON, /_next/static JS chunks), cache-first.
 * Returns {html, text, url, retrieved_at, fromCache} (html === text; the body is returned verbatim).
 * `refresh` and `offline` default to the --refresh and --offline flags.
 */
export async function fetchUrl(url, { refresh = process.argv.includes('--refresh'), offline: cacheOnly = offline(), accept = 'text/html,application/xhtml+xml,application/json,*/*' } = {}) {
  if (refresh && cacheOnly) throw new Error('--refresh re-fetches every page and --offline fetches none: pass one or the other');
  fs.mkdirSync(CACHE_DIR, { recursive: true });
  const { htmlFile, metaFile } = cacheFiles(url);
  if (!refresh && fs.existsSync(htmlFile) && fs.existsSync(metaFile)) {
    const meta = JSON.parse(fs.readFileSync(metaFile, 'utf8'));
    const body = fs.readFileSync(htmlFile, 'utf8');
    return { html: body, text: body, url: meta.url, retrieved_at: meta.retrieved_at, fromCache: true };
  }
  if (!refresh) {
    const cap = apiCaptureFor(url);
    if (cap) return { html: cap.text, text: cap.text, url: cap.url, retrieved_at: cap.read_at, fromCache: false, fromCapture: true, capture: cap };
  }
  if (cacheOnly) throw new Error(`not cached: ${url} (--offline reads only the cache and the captures)`);
  for (let attempt = 1; attempt <= 4; attempt++) {
    await gate();
    let res;
    try {
      res = await fetch(url, { headers: { 'User-Agent': UA, Accept: accept, 'Accept-Language': 'en' } });
    } catch (e) {
      if (attempt === 4) throw e;
      await sleep(2000 * attempt);
      continue;
    }
    if (res.status === 200) {
      const html = await res.text();
      const retrieved_at = new Date().toISOString();
      fs.writeFileSync(htmlFile, html);
      fs.writeFileSync(metaFile, JSON.stringify({ url, retrieved_at, status: 200 }, null, 1));
      return { html, text: html, url, retrieved_at, fromCache: false };
    }
    if (res.status === 404) throw new Error(`404 ${url}`);
    if (attempt === 4) throw new Error(`HTTP ${res.status} ${url}`);
    await sleep(3000 * attempt);
  }
}

/** Decode the Next.js flight payload of a page into one string. */
export function rsc(html) {
  const out = [];
  const re = /self\.__next_f\.push\(\[1,"((?:[^"\\]|\\.)*)"\]\)/gs;
  let m;
  while ((m = re.exec(html))) out.push(JSON.parse('"' + m[1] + '"'));
  return out.join('');
}

/** Parse the JSON value (object/array/string/number) that starts at index i of s. Returns {value, end}. */
export function jsonAt(s, i) {
  while (/\s/.test(s[i])) i++;
  const open = s[i];
  if (open !== '{' && open !== '[') {
    const m = /^("(?:[^"\\]|\\.)*"|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|true|false|null)/.exec(s.slice(i));
    if (!m) throw new Error('no JSON value at ' + i);
    return { value: JSON.parse(m[1]), end: i + m[1].length };
  }
  let depth = 0, inStr = false;
  for (let j = i; j < s.length; j++) {
    const c = s[j];
    if (inStr) {
      if (c === '\\') j++;
      else if (c === '"') inStr = false;
      continue;
    }
    if (c === '"') inStr = true;
    else if (c === '{' || c === '[') depth++;
    else if (c === '}' || c === ']') {
      depth--;
      if (depth === 0) return { value: JSON.parse(s.slice(i, j + 1)), end: j + 1 };
    }
  }
  throw new Error('unterminated JSON at ' + i);
}

/** Every JSON value that follows `"key":` in s (in order). */
export function valuesForKey(s, key) {
  const out = [];
  const needle = JSON.stringify(key) + ':';
  let i = 0;
  while ((i = s.indexOf(needle, i)) >= 0) {
    try {
      const { value, end } = jsonAt(s, i + needle.length);
      out.push(value);
      i = end;
    } catch {
      i += needle.length;
    }
  }
  return out;
}

/** First value for key whose predicate holds. */
export function firstValue(s, key, pred = () => true) {
  return valuesForKey(s, key).find(pred);
}

/** Visible text of a page (scripts/styles stripped), for human-readable cross-checks. */
export function pageText(html) {
  return html
    .replace(/<script[\s\S]*?<\/script>/g, '')
    .replace(/<style[\s\S]*?<\/style>/g, '')
    .replace(/<[^>]+>/g, '\n')
    .replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#x27;|&#39;/g, "'")
    .replace(/[ \t]+/g, ' ')
    .replace(/\n\s*\n+/g, '\n');
}

export function source(url, retrieved_at, extra = {}) {
  return { authority: AUTHORITY, url, retrieved_at, ...extra };
}

export function writeJson(file, obj) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(obj, null, 2) + '\n');
}
