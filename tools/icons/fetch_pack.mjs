// Build the maplestory_io icon pack (format 1, #49) from maplestory.io MCW/CBT2: the PNGs (git-ignored) and pack.json
// (tracked) in game/assets/icon_packs/maplestory_io/. Only the IDs the game data refers to are fetched (pack.mjs
// wantedIds): per item its metadata (for the origins) and the icon and iconRaw PNGs, per skill the icon,
// iconMouseOver and iconDisabled PNGs. Cache first (lib.mjs), so a second run makes no request.
//
//   node tools/icons/fetch_pack.mjs              # fetch what the cache lacks, write the PNGs and pack.json
//   node tools/icons/fetch_pack.mjs --offline    # never touch the network: the PNGs the cache holds, pack.json untouched
//   node tools/icons/fetch_pack.mjs --refresh    # re-fetch every answer (a variant whose bytes changed gets a new date)
//   ICONS_CACHE_DIR=<dir> node tools/icons/fetch_pack.mjs   # keep the cache elsewhere (shared by several checkouts)
// Options: --pack-dir <dir> (default game/assets/icon_packs/maplestory_io), --data-dir <dir> (default game/data).
// Then import the new PNGs: bash scripts/godot.sh --headless --path game --import
//
// A miss never fails the run: it prints one line such as
// "icons: 94/94 items, 3/3 skills present (maplestory.io MCW/CBT2)" and exits 0. Exit 2 is a bad command line.
// pack.json is rewritten only when its text changes, and never by --offline (a fresh clone's offline build must not
// overwrite the committed manifest with every ID missing).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { fetchAnswer, itemUrl, itemIconUrl, skillIconUrl, network } from './lib.mjs';
import { KINDS, wantedIds, judgeImage, originsOf, nextPack, stringifyPack, pngPath, presentCounts, summaryLine } from './pack.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
export const DEFAULT_PACK_DIR = path.join(ROOT, 'game', 'assets', 'icon_packs', 'maplestory_io');
export const DEFAULT_DATA_DIR = path.join(ROOT, 'game', 'data');

function parseArgs(argv) {
  const o = { packDir: DEFAULT_PACK_DIR, dataDir: DEFAULT_DATA_DIR, offline: false, refresh: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const val = () => {
      if (i + 1 >= argv.length) throw new Error(`${a} needs a value`);
      return argv[++i];
    };
    if (a === '--offline') o.offline = true;
    else if (a === '--refresh') o.refresh = true;
    else if (a === '--pack-dir') o.packDir = path.resolve(val());
    else if (a === '--data-dir') o.dataDir = path.resolve(val());
    else if (a === '--help' || a === '-h') {
      console.log(fs.readFileSync(fileURLToPath(import.meta.url), 'utf8').split('\n').filter((l) => l.startsWith('//')).map((l) => l.slice(3)).join('\n'));
      process.exit(0);
    } else throw new Error(`unknown argument ${a}`);
  }
  if (o.offline && o.refresh) throw new Error('--refresh re-fetches every answer and --offline fetches none: pass one or the other');
  return o;
}

/** Writes `body` to `file` unless it already holds exactly those bytes (an unchanged PNG is not re-imported). */
function writeIfChanged(file, body) {
  if (fs.existsSync(file) && fs.readFileSync(file).equals(body)) return;
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, body);
}

/**
 * One run: fetch (cache first), write the PNGs, write pack.json when its text changed (never with `offline`).
 * Returns {line, wrote, ids, outcomes}; `line` is the summary line.
 */
export async function run({ packDir = DEFAULT_PACK_DIR, dataDir = DEFAULT_DATA_DIR, offline = false, refresh = false } = {}) {
  const ids = wantedIds(dataDir);
  const outcomes = new Map();
  let gone = 0;
  let none = 0;
  let why = offline ? '--offline' : '';
  const settle = async (kind, id, variant, url, origin) => {
    const answer = await fetchAnswer(url, { offline, refresh });
    const judged = judgeImage(answer);
    const file = pngPath(packDir, kind, id, variant);
    if (judged.state === 'ok') {
      writeIfChanged(file, judged.body);
      // Without the item's metadata the origin is unknown this run: the PNG is kept, pack.json keeps what it had.
      outcomes.set(`${kind}/${id}/${variant}`, origin === undefined ? { state: 'none' }
        : { state: 'ok', record: { url: judged.url, sha256: judged.sha256, size: judged.size, origin, fetched: judged.fetched } });
    } else if (judged.state === 'gone') {
      fs.rmSync(file, { force: true });
      fs.rmSync(file + '.import', { force: true });
      outcomes.set(`${kind}/${id}/${variant}`, { state: 'gone', reason: judged.reason });
      gone++;
    } else {
      none++;
      if (!why) why = judged.reason;
    }
  };
  for (const id of ids.items) {
    const origins = originsOf(await fetchAnswer(itemUrl(id), { offline, refresh }));
    for (const variant of KINDS.item.variants) await settle('item', id, variant, itemIconUrl(id, variant), origins ? origins[variant] : undefined);
  }
  for (const id of ids.skills) {
    for (const variant of KINDS.skill.variants) await settle('skill', id, variant, skillIconUrl(id, variant), null);
  }
  if (network.down) why = 'network unavailable';
  const manifest = path.join(packDir, 'pack.json');
  const before = fs.existsSync(manifest) ? fs.readFileSync(manifest, 'utf8') : null;
  let prev = null;
  try {
    prev = before === null ? null : JSON.parse(before);
  } catch {
    prev = null; // an unreadable manifest is rebuilt from this run's answers
  }
  const text = stringifyPack(nextPack(prev, ids, outcomes));
  const wrote = !offline && text !== before;
  if (wrote) {
    fs.mkdirSync(packDir, { recursive: true });
    fs.writeFileSync(manifest, text);
  }
  return { line: summaryLine(presentCounts(packDir, ids), ids, { gone, none, why }), wrote, ids, outcomes };
}

// Run only as a script (the tests import run).
const norm = (p) => (process.platform === 'win32' ? path.resolve(p).toLowerCase() : path.resolve(p));
if (process.argv[1] && norm(process.argv[1]) === norm(fileURLToPath(import.meta.url))) {
  let o;
  try {
    o = parseArgs(process.argv.slice(2));
  } catch (e) {
    console.error(`fetch_pack: ${e.message}`);
    process.exit(2);
  }
  const { line } = await run(o);
  console.log(line);
}
