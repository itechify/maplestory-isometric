// MeowDB MS Classic fetch/cache/extract helpers (development-time only; the game never talks to MeowDB).
//
// - Cache-only by default: every page was stored once under tools/meowdb/.cache/ (git-ignored) with its retrieval time,
//   and the extractors re-run from that cache. Network access needs MEOWDB_ALLOW_NETWORK=1 and should only be enabled
//   once MeowDB has granted permission (their Terms forbid automated collection without it; see docs/canonical/README.md).
// - When enabled: >= 1.2 s between network requests across ALL processes; --refresh re-fetches cached pages.
// - Pages are Next.js App Router pages; the data lives in the React Server Component ("flight") payload pushed via
//   self.__next_f.push([1, "..."]). rsc() decodes it; jsonAt()/objectsWithKey() pull plain JSON values out of it.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const AUTHORITY = 'MeowDB MS Classic';
export const BASE_URL = 'https://meowdb.com/msclassic'; // single constant: MeowDB is rebranding to NiaDB (old links keep working)
const HERE = path.dirname(fileURLToPath(import.meta.url));
export const CACHE_DIR = path.join(HERE, '.cache');
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

/** Fetch BASE_URL + p (e.g. "/maps/000000010"), cache-first. Returns {html, url, retrieved_at, fromCache}. */
export async function fetchPage(p, opts = {}) {
  return fetchUrl(p.startsWith('http') ? p : BASE_URL + p, opts);
}

/**
 * Fetch any absolute meowdb.com URL (pages, /msclassic/api/... JSON, /_next/static JS chunks), cache-first.
 * Returns {html, text, url, retrieved_at, fromCache} (html === text; the body is returned verbatim).
 */
export async function fetchUrl(url, { refresh = process.argv.includes('--refresh'), accept = 'text/html,application/xhtml+xml,application/json,*/*' } = {}) {
  fs.mkdirSync(CACHE_DIR, { recursive: true });
  const key = cacheKey(url.replace(BASE_URL, '').replace(/\?/g, '_q_'));
  const htmlFile = path.join(CACHE_DIR, key + (key.endsWith('.js') || key.endsWith('.json') ? '' : '.html'));
  const metaFile = path.join(CACHE_DIR, key + '.meta.json');
  if (!refresh && fs.existsSync(htmlFile) && fs.existsSync(metaFile)) {
    const meta = JSON.parse(fs.readFileSync(metaFile, 'utf8'));
    const body = fs.readFileSync(htmlFile, 'utf8');
    return { html: body, text: body, url: meta.url, retrieved_at: meta.retrieved_at, fromCache: true };
  }
  if (process.env.MEOWDB_ALLOW_NETWORK !== '1') {
    // MeowDB's Terms of Service forbid automated collection without permission, and its Content Reuse Policy
    // (https://meowdb.com/reuse) asks that bulk collection be cleared with contact@meowdb.com first. The extractors
    // therefore run cache-only by default; see docs/canonical/README.md before enabling network access.
    throw new Error(`not cached: ${url} (network access is disabled; see docs/canonical/README.md)`);
  }
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
