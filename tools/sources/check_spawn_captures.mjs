// Compares the canonical spawn rows (game/data/canonical/maps/<id>.json monsters[], from the 2026-10-04 MeowDB cache)
// with the dated live MeowDB monster pages (tools/meowdb/captures/monster_<id>.json|txt, read 2026-10-05: each page's
// "Map Locations" table, one row per Maple Island map). Cache-only and offline: it reads files, never the network.
//
//   node tools/sources/check_spawn_captures.mjs           # a line per mismatch and a summary; exit 1 on any mismatch
//   node tools/sources/check_spawn_captures.mjs --json    # the whole comparison as JSON
//
// Per (map, species) row it checks: the spawn-point count, the share "<count>/<map total> <pct>%" (numerator, the
// map's total spawn points as denominator, the rounded percentage), the number of species on the map ("TYPES"), the
// map mob rate ("1.5x") and the respawn column ("~7.5s", within 0.1 s of formulas/spawn_rate.json's global tick).
// Every canonical row must have its capture row and every captured Maple Island row a canonical row. A species with
// spawns but no capture is reported too. The spawns audit found the 51 rows equal (docs/review/it3_audit.json
// "spawns"); this script keeps it so for future re-extractions and captures.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadCaptures, REPO_ROOT } from './captures.mjs';

const MAPS_DIR = 'game/data/canonical/maps';
const SPAWN_RATE = 'game/data/canonical/formulas/spawn_rate.json';

/** Every canonical map record under `root` (id -> record). */
export function loadCanonicalMaps({ root = REPO_ROOT } = {}) {
  const dir = path.join(root, MAPS_DIR);
  const out = {};
  for (const f of fs.readdirSync(dir).filter((x) => x.endsWith('.json')).sort()) {
    const rec = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
    out[String(rec.id ?? f.replace(/\.json$/, ''))] = rec;
  }
  return out;
}

/** "1.5x" -> 1.5; null when unreadable. */
export function parseMobRate(text) {
  const m = /^(\d+(?:\.\d+)?)x$/.exec(String(text ?? '').trim());
  return m ? Number(m[1]) : null;
}

/** "40/40 100%" -> {count: 40, total: 40, pct: 100}; null when unreadable. */
export function parseShare(text) {
  const m = /^(\d+)\/(\d+)\s+(\d+)%$/.exec(String(text ?? '').trim());
  return m ? { count: Number(m[1]), total: Number(m[2]), pct: Number(m[3]) } : null;
}

/** "~7.5s" -> 7.5; null when unreadable. */
export function parseRespawn(text) {
  const m = /^~?(\d+(?:\.\d+)?)\s*s$/.exec(String(text ?? '').trim());
  return m ? Number(m[1]) : null;
}

/**
 * The comparison. `maps` (id -> canonical record) and `captures` (loadCaptures()) may be injected (tests).
 * Returns {rows: [{map_id, map_name, mob_id, mob_name, canonical, capture, problems: []}], unmatched_capture_rows,
 * missing_captures, tick_s, checked, mismatches}.
 */
export function checkSpawnCaptures({ root = REPO_ROOT, maps = null, captures = null } = {}) {
  const canon = maps ?? loadCanonicalMaps({ root });
  const caps = captures ?? loadCaptures({ root });
  const tick = Number(JSON.parse(fs.readFileSync(path.join(root, SPAWN_RATE), 'utf8')).global_respawn_tick_s);
  const rows = [];
  const used = new Set();
  const missing = new Set();
  for (const [mapId, rec] of Object.entries(canon)) {
    const monsters = (rec.monsters || []).filter((m) => m && Number(m.count) > 0);
    if (!monsters.length) continue;
    const total = (rec.spawns || []).length;
    for (const mon of monsters) {
      const mobId = String(mon.id);
      const canonical = { count: Number(mon.count), total, types: monsters.length, mob_rate: Number(rec.mob_rate ?? 1) };
      const row = { map_id: mapId, map_name: rec.name, street: rec.street_name ?? null, mob_id: mobId, mob_name: mon.name, canonical,
        capture: null, problems: [] };
      rows.push(row);
      const cap = caps.meowdb.monsters[mobId];
      if (!cap) {
        missing.add(mobId);
        row.problems.push(`no dated capture of monster ${mobId} (tools/meowdb/captures/monster_${mobId}.*)`);
        continue;
      }
      const hits = cap.map_rows.filter((r) => r.map_name === rec.name && (r.region == null || rec.street_name == null || r.region === rec.street_name));
      if (hits.length !== 1) {
        row.problems.push(hits.length ? `${hits.length} capture rows for this map` : 'no capture row for this map');
        continue;
      }
      const r = hits[0];
      used.add(`${mobId}|${r.raw}`);
      const share = parseShare(r.share);
      const rate = parseMobRate(r.mob_rate);
      const respawn = parseRespawn(r.respawn);
      row.capture = { file: cap.file, read_at: cap.read_at, raw: r.raw, count: r.count, share, types: r.types, mob_rate: rate, respawn_s: respawn };
      if (r.count !== canonical.count) row.problems.push(`count ${r.count} (capture) vs ${canonical.count} (canonical)`);
      if (!share) row.problems.push(`unreadable share ${JSON.stringify(r.share)}`);
      else {
        if (share.count !== canonical.count) row.problems.push(`share numerator ${share.count} vs count ${canonical.count}`);
        if (share.total !== total) row.problems.push(`share denominator ${share.total} vs ${total} canonical spawn points`);
        if (total > 0 && Math.abs(share.pct - (100 * canonical.count) / total) > 0.5 + 1e-9) {
          row.problems.push(`share ${share.pct}% vs ${((100 * canonical.count) / total).toFixed(1)}%`);
        }
      }
      if (r.types !== canonical.types) row.problems.push(`types ${r.types} vs ${canonical.types} species on the map`);
      if (rate == null || Math.abs(rate - canonical.mob_rate) > 1e-9) row.problems.push(`mob rate ${JSON.stringify(r.mob_rate)} vs ${canonical.mob_rate}`);
      if (respawn == null || Math.abs(respawn - tick) > 0.1) row.problems.push(`respawn ${JSON.stringify(r.respawn)} vs the ${tick} s global tick`);
    }
  }
  const unmatched = [];
  for (const [mobId, cap] of Object.entries(caps.meowdb.monsters)) {
    for (const r of cap.map_rows) {
      if (!used.has(`${mobId}|${r.raw}`)) unmatched.push({ mob_id: mobId, file: cap.file, raw: r.raw });
    }
  }
  const mismatches = rows.filter((r) => r.problems.length).length + unmatched.length;
  return { rows, unmatched_capture_rows: unmatched, missing_captures: [...missing].sort(), tick_s: tick, checked: rows.length, mismatches };
}

function main(argv) {
  const res = checkSpawnCaptures();
  if (argv.includes('--json')) {
    process.stdout.write(JSON.stringify(res, null, 2) + '\n');
  } else {
    for (const r of res.rows) {
      for (const p of r.problems) console.log(`MISMATCH ${r.map_id} ${r.map_name} / ${r.mob_id} ${r.mob_name}: ${p}`);
    }
    for (const u of res.unmatched_capture_rows) console.log(`MISMATCH capture row with no canonical row: monster ${u.mob_id} ${JSON.stringify(u.raw)} (${u.file})`);
    const maps = new Set(res.rows.map((r) => r.map_id)).size;
    console.log(`spawn rows: ${res.checked} canonical (map, species) rows on ${maps} maps compared with the dated captures; ${res.mismatches} mismatches`);
  }
  return res.mismatches === 0 ? 0 : 1;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2));
}
