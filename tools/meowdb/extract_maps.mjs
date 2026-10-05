// Extract the 25 Maple Island maps from MeowDB MS Classic into game/data/canonical/maps/<id>.json,
// then write the Iteration One crosswalk (game/data/misostory/map_id_crosswalk.json) and the
// MeowDB-vs-Iteration-One diff (docs/canonical/topology_diff.md).
//
//   node tools/meowdb/extract_maps.mjs            (cache-first: all 25 map pages are already cached)
//
// Deterministic: output depends only on the cached pages and the Iteration One files in docs/ and
// src/misostory/layout.py. No timestamps are generated; retrieved_at comes from the cache meta.
// MeowDB data is never filled from memory: anything MeowDB does not give is null and listed in "gaps".
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { fetchPage, rsc, jsonAt, pageText, source, writeJson, BASE_URL } from './lib.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..');
const OUT_DIR = path.join(ROOT, 'game', 'data', 'canonical', 'maps');
const CROSSWALK_FILE = path.join(ROOT, 'game', 'data', 'misostory', 'map_id_crosswalk.json');
const DIFF_FILE = path.join(ROOT, 'docs', 'canonical', 'topology_diff.md');

// The 25 Maple Island maps, MeowDB ids (9-digit strings, MeowDB's own numbering).
export const MAP_IDS = [
  '000000001', '000000010', '000000020', '000000021', '000000030', '000000040', '000000041', '000000042',
  '000000050', '000000060', '000000061', '000001000', '000001001', '000001002', '000001003', '000001004',
  '000001005', '000001006', '000001010', '000001011', '000001012', '000001013', '000001014', '000001020',
  '000001021',
];

// The map-page client bundle; read once by hand to establish units and the viewer's coordinate formula.
// The extractor does NOT depend on it; it is cited in docs and in field notes only.
const VIEWER_CHUNK_URL = 'https://meowdb.com/_next/static/chunks/app/msclassic/%5Blocale%5D/maps/%5Bid%5D/page-a7e2d98c08322572.js';
const VIEWER_CHUNK_RETRIEVED_AT = '2026-10-04T10:07:45.500Z'; // cache meta of that chunk when it was read

// --------------------------------------------------------------------------------------------
// RSC helpers (local; lib.mjs is not modified)
// --------------------------------------------------------------------------------------------

/** Split a decoded flight payload into rows: { "3f": <json value>, ... } (module "I[...]" and text rows skipped). */
function parseRows(s) {
  const rows = {};
  const re = /(?:^|\n)([0-9a-f]+):/g;
  let m;
  while ((m = re.exec(s))) {
    const start = m.index + m[0].length;
    const c = s[start];
    if (c === '[' || c === '{' || c === '"' || s.startsWith('null', start)) {
      try {
        const { value, end } = jsonAt(s, start);
        rows[m[1]] = value;
        re.lastIndex = end;
      } catch { /* not a JSON row */ }
    }
  }
  return rows;
}

/** Inline "$L3f" / "$3f" row references. */
function resolveRefs(v, rows, depth = 0) {
  if (depth > 60) return v;
  if (typeof v === 'string') {
    const mm = /^\$L?([0-9a-f]+)$/.exec(v);
    if (mm && rows[mm[1]] !== undefined) return resolveRefs(rows[mm[1]], rows, depth + 1);
    return v;
  }
  if (Array.isArray(v)) return v.map((x) => resolveRefs(x, rows, depth + 1));
  if (v && typeof v === 'object') {
    const o = {};
    for (const [k, x] of Object.entries(v)) o[k] = resolveRefs(x, rows, depth + 1);
    return o;
  }
  return v;
}

const isEl = (v) => Array.isArray(v) && v.length === 4 && v[0] === '$' && typeof v[1] === 'string';
const props = (el) => (el && el[3]) || {};

/** Depth-first list of every React element ["$", type, key, props] in v. */
function elements(v, out = []) {
  if (Array.isArray(v)) {
    if (isEl(v)) {
      out.push(v);
      const p = props(v);
      for (const [k, x] of Object.entries(p)) if (k !== 'className') elements(x, out);
    } else v.forEach((x) => elements(x, out));
  } else if (v && typeof v === 'object') {
    for (const x of Object.values(v)) elements(x, out);
  }
  return out;
}

/** Visible text of an element tree (strings + numbers, "$undefined" etc. skipped). */
function textOf(v) {
  const out = [];
  const walk = (x) => {
    if (typeof x === 'string') { if (!x.startsWith('$')) out.push(x); }
    else if (typeof x === 'number') out.push(String(x));
    else if (Array.isArray(x)) {
      if (isEl(x)) { if (props(x).children !== undefined) walk(props(x).children); }
      else x.forEach(walk);
    }
  };
  walk(v);
  return out.join('');
}

const find = (els, pred) => els.find(pred);
const filt = (els, pred) => els.filter(pred);
const hasText = (el, re) => re.test(textOf(el));

// --------------------------------------------------------------------------------------------
// Page extraction
// --------------------------------------------------------------------------------------------

function failIf(cond, msg) { if (cond) throw new Error(msg); }

async function loadPage(id) {
  const page = await fetchPage('/maps/' + id);
  const s = rsc(page.html);
  const rows = parseRows(s);
  const rootKey = Object.keys(rows).find((k) => JSON.stringify(rows[k] ?? null).includes('"data-map-header-facts"'));
  failIf(!rootKey, `${id}: page root row not found`);
  const root = resolveRefs(rows[rootKey], rows);
  const els = elements(root);
  const viewer = find(els, (e) => props(e).map && typeof props(e).map === 'object' && props(e).map.id === id);
  failIf(!viewer, `${id}: map viewer props not found`);
  return { page, s, rows, root, els, vp: props(viewer), map: props(viewer).map };
}

function headerFacts(els) {
  const dl = find(els, (e) => e[1] === 'dl' && props(e)['data-map-header-facts']);
  const out = {};
  for (const div of filt(elements(props(dl).children), (e) => e[1] === 'div' && typeof e[2] === 'string')) {
    const sub = elements(props(div).children);
    const dt = find(sub, (e) => e[1] === 'dt');
    const dd = find(sub, (e) => e[1] === 'dd');
    out[div[2].replace(/-/g, '_')] = { label: textOf(dt), value: textOf(dd) };
  }
  return out;
}

function overviewText(els) {
  const det = find(els, (e) => e[1] === 'details' && hasText(e, /^Map overview/));
  const p = det && find(elements(props(det).children), (e) => e[1] === 'p');
  return p ? textOf(p) : null;
}

function summaryBlock(els, id) {
  // "Map Summary": respawn-map link, safe-zone line, NPC talkers, BGM.
  const link = find(els, (e) => typeof props(e).href === 'string' && /^\/msclassic\/maps\/\d{9}$/.test(props(e).href) && hasText(e, /^Respawn Map/));
  const respawn = link ? { id: props(link).href.split('/').pop(), name: textOf(props(link).children).replace(/^Respawn Map/, '').replace(/Where you return after dying.*$/, '') } : null;
  const safe = find(els, (e) => e[1] === 'p' && hasText(e, /^Safe zone\./));
  const bgmEl = find(els, (e) => typeof props(e).bgm === 'string' && 'length' in props(e));
  const talkerEl = find(els, (e) => Array.isArray(props(e).talkers));
  const talkers = talkerEl ? props(talkerEl).talkers : [];
  const npcLinks = filt(els, (e) => typeof props(e).href === 'string' && /^\/msclassic\/npcs\/\d+$/.test(props(e).href) && props(e)['data-npc-talker'] !== undefined)
    .map((e) => ({ id: props(e).href.split('/').pop(), talker: props(e)['data-npc-talker'], name: textOf(find(elements(props(e).children), (x) => props(x)['data-npc-name'] !== undefined)) }));
  failIf(talkers.length !== npcLinks.length, `${id}: talkers (${talkers.length}) != npc links (${npcLinks.length})`);
  return {
    respawn,
    safeZoneText: safe ? textOf(safe) : null,
    bgm: bgmEl ? { bgm: props(bgmEl).bgm, name: props(bgmEl).name, length: props(bgmEl).length } : null,
    rates: (find(els, (e) => props(e).rates && typeof props(e).rates === 'object') || [])[3]?.rates ?? null,
    talkersById: Object.fromEntries(npcLinks.map((l) => [l.id, { name: l.name, lines: talkers[l.talker].lines, talker_name: talkers[l.talker].name }])),
  };
}

function monsterTable(els) {
  // Monsters table rows: <tr key=mobId> ... <a href=/msclassic/monsters/<id>> ... <span title=desc>label</span>
  const rows = filt(els, (e) => e[1] === 'tr' && typeof e[2] === 'string' && /^\d+$/.test(e[2]));
  const out = {};
  for (const tr of rows) {
    const sub = elements(props(tr).children);
    const a = find(sub, (e) => typeof props(e).href === 'string' && /^\/msclassic\/monsters\/\d+$/.test(props(e).href));
    if (!a) continue;
    const mv = find(sub, (e) => e[1] === 'span' && typeof props(e).title === 'string' && !/spawn points/.test(props(e).title));
    out[props(a).href.split('/').pop()] = { label: mv ? textOf(mv) : null, description: mv ? props(mv).title : null };
  }
  return out;
}

function spawnRulesText(els) {
  const div = find(els, (e) => Array.isArray(props(e).children) && isEl(props(e).children[0]) && textOf(props(e).children[0]) === 'How spawns work.');
  const mobRate = find(els, (e) => e[1] === 'p' && Array.isArray(props(e).children) && isEl(props(e).children[0]) && textOf(props(e).children[0]) === 'About mob rate.');
  // Adjacent <span>s render as separate lines; restore the sentence break textOf() glues together.
  return { spawnRules: div ? textOf(div).replace(/\s+/g, ' ').replace(/\.(?=[A-Z])/g, '. ').trim() : null, mobRate: mobRate ? textOf(mobRate).replace(/\s+/g, ' ').trim() : null };
}

function questSection(els) {
  const sec = find(els, (e) => props(e).id === 'quests-on-this-map');
  if (!sec) return null;
  const out = {};
  for (const section of filt(elements(props(sec).children), (e) => e[1] === 'section')) {
    const sub = elements(props(section).children);
    const h3 = find(sub, (e) => e[1] === 'h3');
    const title = textOf(h3);
    const m = /^(.*) \((\d+)\)$/.exec(title);
    failIf(!m, 'unexpected quest section header ' + title);
    const key = m[1].toLowerCase().replace(/[^a-z]+/g, '_');
    const items = filt(sub, (e) => typeof props(e).href === 'string' && /^\/msclassic\/quest-tracker\/\d+$/.test(props(e).href)).map((a) => {
      const s2 = elements(props(a).children);
      const img = find(s2, (e) => e[1] === 'img');
      const nameEl = find(s2, (e) => e[1] === 'span' && typeof props(e).children === 'string');
      const byKey = (k) => { const el = find(s2, (e) => e[2] === k); return el ? textOf(el).replace(/^·/, '').trim() : null; };
      const objectives = filt(s2, (e) => e[1] === 'span' && typeof e[2] === 'string' && /^\d+-\d+$/.test(e[2])).map((o) => {
        const parts = props(o).children;
        const count = Array.isArray(parts) ? parts.filter((x) => typeof x === 'number').pop() ?? null : null;
        return { mob_id: o[2].split('-')[0], text: textOf(o).replace(/\s+/g, ' ').trim().replace(/^·\s*/, ''), count };
      });
      const q = {
        id: props(a).href.split('/').pop(),
        name: nameEl ? props(nameEl).children : null,
        npc_name: img ? props(img).alt : null,
      };
      // Keyed info spans (level, area, exp, mesos, and any other key the page adds), verbatim.
      const LABEL = { level: 'level_label', area: 'area_label', exp: 'exp_reward_label', mesos: 'meso_reward_label' };
      for (const el of filt(s2, (e) => e[1] === 'span' && typeof e[2] === 'string' && /^[a-z]+$/.test(e[2]))) {
        q[LABEL[el[2]] ?? el[2] + '_label'] = byKey(el[2]);
      }
      if (objectives.length) q.objectives_on_this_map = objectives;
      return q;
    });
    failIf(items.length !== Number(m[2]), `quest section ${title}: ${items.length} items`);
    out[key] = items;
  }
  return out;
}

function restrictions(els) {
  const h2 = find(els, (e) => e[1] === 'h2' && textOf(e) === 'Map restrictions');
  if (!h2) return [];
  return filt(els, (e) => e[1] === 'li' && typeof e[2] === 'string' && hasText(e, /\S/) && filt(elements(props(e).children), (x) => x[1] === 'img' && /\/api\/assets\/icons\//.test(props(x).src || '')).length > 0)
    .map((li) => {
      const spans = filt(elements(props(li).children), (e) => e[1] === 'span' && typeof props(e).children === 'string');
      return { key: li[2], label: spans[0] ? props(spans[0]).children : null, description: spans[1] ? props(spans[1]).children : null };
    });
}

function portalListSection(els) {
  // Only on some pages ("Portals (N)"): e.g. 000001020 lists in00 as "Inside portal -> Tomato Field".
  const out = {};
  for (const li of filt(els, (e) => e[1] === 'li' && typeof e[2] === 'string' && /^[a-z]+\d+-\d+$/.test(e[2]))) {
    const sub = elements(props(li).children);
    const a = find(sub, (e) => typeof props(e).href === 'string' && /^\/msclassic\/maps\/\d{9}$/.test(props(e).href));
    const label = textOf(find(sub, (e) => e[1] === 'span'));
    out[li[2].replace(/-\d+$/, '')] = { label, to_map_id: a ? props(a).href.split('/').pop() : null };
  }
  return out;
}

// --------------------------------------------------------------------------------------------
// Build one canonical map entity
// --------------------------------------------------------------------------------------------

function buildMap(id, P) {
  const { page, els, vp, map: m } = P;
  const facts = headerFacts(els);
  const sum = summaryBlock(els, id);
  const mtab = monsterTable(els);
  const rules = spawnRulesText(els);
  const quests = questSection(els);
  const restr = restrictions(els);
  const plist = portalListSection(els);
  const notes = [];
  const gaps = [];

  failIf(m.id !== id, 'id mismatch');
  failIf(!sum.respawn || !sum.respawn.name, `${id}: Map Summary respawn link not found`);
  failIf(!sum.bgm || !sum.bgm.name || sum.bgm.bgm !== m.bgm, `${id}: BGM props not found or disagree with map.bgm`);
  failIf(!overviewText(els), `${id}: map overview text not found`);
  failIf(sum.respawn && sum.respawn.id !== m.returnMap, `${id}: summary respawn link ${sum.respawn?.id} != returnMap ${m.returnMap}`);
  failIf(m.spawns.length !== m.totalMobCount, `${id}: spawns ${m.spawns.length} != totalMobCount ${m.totalMobCount}`);
  failIf(m.monsters.reduce((a, x) => a + x.count, 0) !== m.spawns.length, `${id}: monster counts do not sum to spawns`);
  failIf(m.intraPortals.length !== 0, `${id}: intraPortals present; extend the extractor`);
  for (const sp of m.spawns) failIf(!m.monsters.some((x) => x.id === sp.mobId), `${id}: spawn of unknown mob ${sp.mobId}`);

  const movement = vp.mobMovement || {};
  const breakableLabels = vp.breakableLabels || {};

  // Minimap rectangle -> px bounds. The viewer places a marker at left% = (x + miniMapCenterX) / minimapWidth.
  const hasMinimap = m.minimapWidth > 0 && m.minimapHeight > 0;
  const bounds = hasMinimap ? {
    x_min: -m.miniMapCenterX, x_max: m.minimapWidth - m.miniMapCenterX,
    y_min: -m.miniMapCenterY, y_max: m.minimapHeight - m.miniMapCenterY,
  } : null;
  if (!hasMinimap) gaps.push('MeowDB has no minimap rectangle for this map (all minimap fields are 0), so bounds_px_derived is null.');
  else {
    const pts = [...m.spawns.map((p) => ['spawn ' + p.mobId, p]), ...m.playerSpawns.map((p) => ['player spawn', p]), ...m.npcs.map((p) => ['npc ' + p.id, p]), ...m.portals.map((p) => ['portal ' + p.name, p]), ...m.reactors.map((p) => ['reactor ' + p.id, p])];
    const outside = pts.filter(([, p]) => p.x < bounds.x_min || p.x > bounds.x_max || p.y < bounds.y_min || p.y > bounds.y_max);
    if (outside.length) notes.push(`${outside.length} placed point(s) fall outside the minimap rectangle (bounds_px_derived), so it is not a hard map boundary: ${outside.map(([k, p]) => `${k} at (${p.x},${p.y})`).join('; ')}.`);
  }

  const isSafe = sum.safeZoneText !== null;
  const hasMobs = m.monsters.length > 0;
  const overview = overviewText(els);
  const overviewKind = overview ? (/ is a town in /.test(overview) ? 'town' : / is a hunting ground in /.test(overview) ? 'hunting ground' : null) : null;
  if (m.mobRate !== 1) {
    notes.push(`mob_rate is ${m.mobRate}. MeowDB pages disagree on its effect: this page says it multiplies how many monsters stay alive ("best reading from closed-beta play", not applied to its own estimates); the spawn-engine guide says MapleStory Classic ignores it and the spawn formula page's capacity formula omits it. See docs/canonical/maps.md, Discrepancies.`);
  }
  if (m.isTown && overviewKind === 'hunting ground') {
    notes.push('isTown is true but the page prose calls this map "a hunting ground" and the header shows monster facts instead of "Map type: Town" (the prose follows whether the map has monsters). is_town keeps the structured isTown value.');
  }

  const out = {
    id: m.id,
    name: m.name,
    street_name: m.streetName,
    region: m.region,
    location_label: facts.location?.value ?? null,
    is_town: m.isTown,
    page_map_type_label: facts.type?.value ?? null,
    overview_text: overview,
    return_map_id: m.returnMap,
    return_map_name: sum.respawn?.name ?? null,
    safe_zone: isSafe,
    safe_zone_text: sum.safeZoneText,
    field_limit: m.fieldLimit,
    field_restrictions: restr,
    bgm: sum.bgm ? { path: sum.bgm.bgm, name: sum.bgm.name, length: sum.bgm.length } : { path: m.bgm, name: null, length: null },
    mob_rate: m.mobRate,
    total_mob_count: m.totalMobCount,
    page_facts: Object.fromEntries(Object.entries(facts).filter(([k]) => k !== 'location' && k !== 'type').map(([k, v]) => [k, v.value])),
    connected_maps: m.connectedMaps.map((c) => ({ map_id: c.mapId, map_name: c.mapName, street_name: c.streetName })),
    portals: m.portals.map((p) => {
      const o = {
        name: p.name,
        type: p.type,
        x_px: p.x,
        y_px: p.y,
        to_map_id: p.toMapId,
        to_map_name: p.toMapName,
        to_street_name: p.toStreetName,
        to_portal: null, // filled by reverse lookup below
        to_portal_derivation: null,
      };
      if (plist[p.name]) {
        failIf(plist[p.name].to_map_id !== p.toMapId, `${id}: portal list ${p.name} target mismatch`);
        o.page_label = plist[p.name].label;
      }
      return o;
    }),
    player_spawns: m.playerSpawns.map((p) => ({ x_px: p.x, y_px: p.y })),
    npcs: m.npcs.map((n) => {
      const t = sum.talkersById[n.id];
      failIf(t && t.name !== n.name, `${id}: npc talker name mismatch ${n.id}`);
      return { id: n.id, name: n.name, x_px: n.x, y_px: n.y, idle_speech_lines: t ? t.lines : [] };
    }),
    monsters: m.monsters.map((x) => ({
      id: x.id,
      name: x.name,
      count: x.count,
      respawn_min_s: x.respawnMin,
      respawn_max_s: x.respawnMax,
      wave_spawn_count: x.waveSpawnCount,
      movement: movement[x.id] ?? null,
      movement_label: mtab[x.id]?.label ?? null,
      movement_description: mtab[x.id]?.description ?? null,
    })),
    spawns: m.spawns.map((sp) => ({ mob_id: sp.mobId, x_px: sp.x, y_px: sp.y, mob_time_s: sp.mobTime })),
    intra_portals: [],
    reactors: m.reactors.map((r) => ({ id: r.id, name: breakableLabels[r.id] ?? null, x_px: r.x, y_px: r.y, respawn_s: r.respawn })),
    minimap: {
      width_px: m.minimapWidth,
      height_px: m.minimapHeight,
      center_x_px: m.miniMapCenterX,
      center_y_px: m.miniMapCenterY,
      has_image: m.hasMinimapImage,
    },
    bounds_px_derived: bounds,
    quests: quests ?? {},
  };

  if (hasMobs) {
    const r = sum.rates;
    failIf(!r || r.id !== id, `${id}: rates block missing`);
    out.meowdb_spawn_estimates = {
      note: "MeowDB's own spawn/EXP model (page 'Map Summary' and 'How this estimate works'); not raw game data. Monster level/EXP live in the monsters domain.",
      total_spawn_points: r.totalSpawnPoints,
      capacity_solo: r.capacity,
      capacity_full_party: r.capacityFullParty,
      mobs_per_hour: r.mobsPerHour,
      mobs_per_hour_full_party: r.mobsPerHourFullParty,
      exp_per_hour: r.expPerHour,
      exp_per_hour_full_party: r.expPerHourFullParty,
      exp_rank: r.expRank,
      exp_rank_total: r.expRankTotal,
      per_mob: r.perMob.map((x) => ({
        id: String(x.id),
        name: x.name,
        spawn_points: x.spawnPoints,
        wave_spawn_points: x.waveSpawnPoints,
        timed_spawn_points: x.timedSpawnPoints,
        timed_respawn_avg_s: x.timedRespawnAvg,
        mobs_per_hour: x.mobsPerHour,
        mobs_per_hour_full_party: x.mobsPerHourFullParty,
        exp_per_hour: x.expPerHour,
        exp_per_hour_full_party: x.expPerHourFullParty,
      })),
    };
    out.spawn_rules_text = rules.spawnRules;
    out.mob_rate_text = rules.mobRate;
    for (const x of r.perMob) {
      const mm = m.monsters.find((y) => y.id === String(x.id));
      failIf(!mm || mm.count !== x.spawnPoints, `${id}: rates per-mob ${x.id} disagrees with monsters`);
    }
  }

  // Gaps: what MeowDB does not provide for this map.
  gaps.push('to_portal (destination portal name) is not given by MeowDB; derived by reverse lookup (see to_portal_derivation).');
  gaps.push('Portal "type" is a raw integer; MeowDB does not label its meaning on the page or in the viewer code.');
  gaps.push('No foothold/platform/ladder/rope geometry is published on the page (only point positions and the minimap rectangle).');
  gaps.push('MeowDB does not say whether npc/spawn y is the raw WZ life y or the foothold-snapped y.');
  if (!hasMobs) gaps.push('No monsters on this map (MeowDB lists none).');
  if (m.npcs.some((n) => !sum.talkersById[n.id])) gaps.push('Idle speech lines missing for some NPCs.');

  out.source = source(`${BASE_URL}/maps/${id}`, page.retrieved_at);
  out.field_sources = {
    to_portal: { url: `${BASE_URL}/maps/<to_map_id>`, retrieved_at: null, derivation: 'reverse lookup over the destination map page (see docs/canonical/maps.md)' },
  };
  if (bounds) out.field_sources.bounds_px_derived = { url: VIEWER_CHUNK_URL, retrieved_at: VIEWER_CHUNK_RETRIEVED_AT, derivation: 'x in [-center_x_px, width_px - center_x_px], y in [-center_y_px, height_px - center_y_px] (viewer formula left% = (x + miniMapCenterX) / minimapWidth)' };
  if (notes.length) out.notes = notes;
  out.gaps = gaps;
  return out;
}

// --------------------------------------------------------------------------------------------
// Reverse lookup of destination portals
// --------------------------------------------------------------------------------------------

function deriveToPortals(maps) {
  const byId = Object.fromEntries(maps.map((m) => [m.id, m]));
  const cacheMeta = (id) => byId[id]?.source.retrieved_at ?? null;
  for (const m of maps) {
    for (const p of m.portals) {
      const dest = byId[p.to_map_id];
      failIf(!dest, `${m.id}.${p.name}: destination ${p.to_map_id} is outside the 25-map set`);
      const back = dest.portals.filter((q) => q.to_map_id === m.id);
      failIf(back.length > 1, `${m.id}.${p.name}: ambiguous reverse lookup (${back.map((q) => q.name).join(', ')})`);
      if (back.length === 1) {
        p.to_portal = back[0].name;
        p.to_portal_derivation = 'reverse_lookup';
      } else {
        p.to_portal = null;
        p.to_portal_derivation = 'none';
        p.arrival_note = `No portal in ${dest.id} (${dest.name}) leads back to ${m.id}; arrive at one of ${dest.id}'s player_spawns (${dest.player_spawns.length} listed).`;
      }
    }
  }
  // Re-point field_sources.to_portal at real destination pages (one entry per destination).
  for (const m of maps) {
    const dests = [...new Set(m.portals.map((p) => p.to_map_id))];
    m.field_sources.to_portal = {
      derivation: 'reverse lookup: the unique portal in the destination map whose to_map_id is this map; "none" when no such portal exists',
      pages: dests.map((d) => ({ url: `${BASE_URL}/maps/${d}`, retrieved_at: cacheMeta(d) })),
    };
  }
}

// --------------------------------------------------------------------------------------------
// Iteration One (GMS v8) side
// --------------------------------------------------------------------------------------------

function loadIterationOne() {
  const topo = JSON.parse(fs.readFileSync(path.join(ROOT, 'docs', 'topology.json'), 'utf8'));
  const manifest = JSON.parse(fs.readFileSync(path.join(ROOT, 'docs', 'manifest.json'), 'utf8'));
  const entities = JSON.parse(fs.readFileSync(path.join(ROOT, 'docs', 'research', 'entities.json'), 'utf8'));
  // Raw GMS v8 WZ portal nodes per map (incl. pt 0 "sp" player spawns and non-exit points such as h001/tp).
  const portalsXml = JSON.parse(fs.readFileSync(path.join(ROOT, 'docs', 'research', 'portals_xml.json'), 'utf8'));
  const layout = fs.readFileSync(path.join(ROOT, 'src', 'misostory', 'layout.py'), 'utf8');
  const block = (name) => {
    const i = layout.indexOf('\n' + name + ' = ');
    failIf(i < 0, 'layout.py: ' + name + ' not found');
    const open = layout.indexOf(name === 'ONE_WAY' ? '{' : '[', i);
    let depth = 0;
    for (let j = open; j < layout.length; j++) {
      if ('[{('.includes(layout[j])) depth++;
      else if (')]}'.includes(layout[j])) { depth--; if (depth === 0) return layout.slice(open, j + 1); }
    }
    throw new Error('unterminated ' + name);
  };
  const links = [...block('LINKS').matchAll(/\((\d+),\s*"(\w+)",\s*(\d+),\s*"(\w+)",\s*([\d.]+),\s*(-?[\d.]+)\)/g)]
    .map((x) => ({ child: Number(x[1]), child_anchor: x[2], parent: Number(x[3]), parent_anchor: x[4] }));
  const doorLinks = [...block('DOOR_LINKS').matchAll(/\((\d+),\s*"(\w+)",\s*(\d+),\s*"(\w+)"\)/g)]
    .map((x) => ({ map: Number(x[1]), portal: x[2], interior: Number(x[3]), interior_portal: x[4] }));
  const oneWay = [...block('ONE_WAY').matchAll(/\((\d+),\s*"(\w+)"\)/g)].map((x) => ({ map: Number(x[1]), portal: x[2] }));
  // Parse checks against Iteration One's own topology rather than fixed counts: layout.py is the live Blender layout
  // and changes (Iteration Two kept only the arrival of MeowDB's one-way link in ONE_WAY, as headline 1 recommends);
  // docs/topology.json does not. LINKS (trails) and DOOR_LINKS (interiors) together must join exactly the map pairs
  // of docs/topology.json, once each, and every ONE_WAY anchor must be an arrival point of its map there.
  const pairOf = (a, b) => [a, b].sort((x, y) => x - y).join('~');
  const layoutPairs = [...links.map((l) => pairOf(l.child, l.parent)), ...doorLinks.map((d) => pairOf(d.map, d.interior))];
  const topoPairs = topo.connections.map((c) => pairOf(c.a, c.b));
  failIf(new Set(layoutPairs).size !== layoutPairs.length || layoutPairs.length !== topoPairs.length || topoPairs.some((p) => !layoutPairs.includes(p)),
    `layout.py parse: ${links.length} LINKS + ${doorLinks.length} DOOR_LINKS do not join exactly the ${topoPairs.length} map pairs of docs/topology.json`);
  const arrivalOf = (o) => (topo.maps.find((t) => t.id === o.map)?.arrival_points || []).some((a) => a.portal === o.portal);
  failIf(oneWay.length === 0 || !oneWay.every(arrivalOf), `layout.py parse: ONE_WAY ${JSON.stringify(oneWay)} must name arrival points of docs/topology.json`);
  // ONE_WAY as Iteration One built it: the landing anchors of the one-way connections in docs/topology.json.
  const oneWayIterationOne = topo.connections.filter((c) => !c.bidirectional).map((c) => ({ map: c.b, portal: c.b_portal }));
  return { topo, manifest, entities, portalsXml, links, doorLinks, oneWay, oneWayIterationOne };
}

/** Pair every MeowDB map with an Iteration One map by evidence (never by id arithmetic). */
function crosswalk(maps, I1) {
  const score = (m, t) => {
    const ev = [];
    let s = 0;
    if (m.name === t.name) { s += 3; ev.push('same name'); }
    if (m.street_name === t.street) { s += 1; }
    const tPortals = [...t.exits.map((e) => ({ name: e.portal, x: e.x, y: e.y })), ...(t.arrival_points || []).map((a) => ({ name: a.portal, x: a.x, y: a.y }))];
    const sameXY = m.portals.filter((p) => tPortals.some((q) => q.name === p.name && q.x === p.x_px && q.y === p.y_px)).map((p) => p.name);
    const sameName = m.portals.filter((p) => tPortals.some((q) => q.name === p.name)).map((p) => p.name);
    s += sameName.length + 3 * sameXY.length;
    if (sameXY.length) ev.push(`portal coordinates identical (${sameXY.join(', ')})`);
    const npcSame = m.npcs.filter((n) => t.npcs.some((q) => q.name === n.name)).map((n) => n.name);
    const npcXY = m.npcs.filter((n) => t.npcs.some((q) => q.name === n.name && q.x === n.x_px)).map((n) => n.name);
    s += 2 * npcSame.length + 2 * npcXY.length;
    if (npcSame.length) ev.push(`same NPCs (${npcSame.join(', ')})`);
    if (npcXY.length) ev.push(`NPC x identical (${npcXY.join(', ')})`);
    if (m.street_name === t.street) ev.push('same street');
    if (m.player_spawns.length === t.spawn_points) { s += 1; ev.push(`same player-spawn count (${t.spawn_points})`); }
    const ms = m.monsters.map((x) => x.name).sort().join('|');
    const ts = Object.keys(t.mobs).sort().join('|');
    if (ms && ms === ts) { s += 1; ev.push('same monster species'); }
    return { s, ev };
  };
  const rows = [];
  const used = new Set();
  for (const m of maps) {
    const ranked = I1.topo.maps.map((t) => ({ t, ...score(m, t) })).sort((a, b) => b.s - a.s);
    failIf(ranked[0].s === ranked[1].s, `${m.id}: crosswalk tie between ${ranked[0].t.id} and ${ranked[1].t.id}`);
    failIf(used.has(ranked[0].t.id), `${m.id}: Iteration One map ${ranked[0].t.id} matched twice`);
    used.add(ranked[0].t.id);
    const t = ranked[0].t;
    const man = I1.manifest.maps.find((x) => x.id === t.id);
    failIf(!man || man.slug !== t.slug, `${t.id}: manifest slug mismatch`);
    rows.push({
      meowdb_id: m.id,
      gms_v8_id: t.id,
      iteration_one_slug: t.slug,
      name: m.name,
      iteration_one_name: t.name,
      match_basis: ranked[0].ev.join('; '),
      match_score: ranked[0].s,
      runner_up_score: ranked[1].s,
    });
  }
  failIf(used.size !== 25, 'crosswalk is not a bijection');
  return rows;
}

// --------------------------------------------------------------------------------------------
// Diff
// --------------------------------------------------------------------------------------------

const IMPACT_ORDER = { high: 0, medium: 1, low: 2 };

function computeDiff(maps, I1, cw, X0 = {}) {
  const g = Object.fromEntries(cw.map((r) => [r.meowdb_id, r.gms_v8_id]));
  const mid = Object.fromEntries(cw.map((r) => [r.gms_v8_id, r.meowdb_id]));
  const byId = Object.fromEntries(maps.map((m) => [m.id, m]));
  const tmap = Object.fromEntries(I1.topo.maps.map((t) => [t.id, t]));
  const man = Object.fromEntries(I1.manifest.maps.map((x) => [x.id, x]));
  const label = (id) => `${id} ${byId[id].name} (v8 ${g[id]})`;
  const D = []; // {area, map, subject, meowdb, iteration_one, change, impact, recommendation}
  const add = (o) => D.push(o);

  // ---- map properties
  for (const m of maps) {
    const t = tmap[g[m.id]];
    if (m.name !== t.name) add({ area: 'map', map: m.id, subject: 'name', meowdb: m.name, iteration_one: t.name, change: 'renamed', impact: 'low', recommendation: 'Display the MeowDB name in UI (map banner, world map, save files). Keep the Blender collection/slug unchanged; the crosswalk resolves it.' });
    if (m.street_name !== t.street) add({ area: 'map', map: m.id, subject: 'street', meowdb: m.street_name, iteration_one: t.street, change: 'street changed', impact: 'low', recommendation: 'Use the MeowDB street name in UI.' });
    if (m.is_town !== t.is_town) add({ area: 'map', map: m.id, subject: 'is_town', meowdb: m.is_town, iteration_one: t.is_town, change: 'town flag changed', impact: 'medium', recommendation: 'Use MeowDB is_town.' });
    if (m.return_map_id !== mid[t.return_map]) add({ area: 'map', map: m.id, subject: 'return_map', meowdb: m.return_map_id, iteration_one: t.return_map, change: 'respawn map changed', impact: 'high', recommendation: 'Use MeowDB return_map_id for death/return.' });
    if (m.bgm.path !== t.bgm) add({ area: 'map', map: m.id, subject: 'bgm', meowdb: m.bgm.path, iteration_one: t.bgm, change: 'BGM changed', impact: 'low', recommendation: 'Use the MeowDB BGM key.' });
    if (m.mob_rate !== t.mob_rate) add({ area: 'map', map: m.id, subject: 'mob_rate', meowdb: m.mob_rate, iteration_one: t.mob_rate, change: 'mob rate changed', impact: 'medium', recommendation: 'Use MeowDB mob_rate when computing how many monsters stay alive.' });
    if (m.player_spawns.length !== t.spawn_points) add({ area: 'map', map: m.id, subject: 'player spawn count', meowdb: m.player_spawns.length, iteration_one: t.spawn_points, change: 'player-spawn count changed', impact: 'low', recommendation: 'Author one 3D spawn transform per MeowDB player spawn (or one shared region).' });
    const tKindHasMobs = Object.keys(t.mobs).length > 0;
    if ((m.monsters.length > 0) !== tKindHasMobs) add({ area: 'map', map: m.id, subject: 'has monsters', meowdb: m.monsters.length > 0, iteration_one: tKindHasMobs, change: m.monsters.length > 0 ? 'map gains monsters' : 'map loses monsters', impact: 'high', recommendation: m.monsters.length > 0 ? `Iteration One classed ${t.id} as "${t.kind}" with no monsters. Add a spawn region in the Blender map and spawn MeowDB's monsters; do not treat is_town as "no combat".` : 'Remove the spawn regions.' });
  }

  // ---- links (connection level)
  const meowLinks = [];
  const seen = new Set();
  for (const m of maps) for (const p of m.portals) {
    const back = p.to_portal ? byId[p.to_map_id].portals.find((q) => q.name === p.to_portal) : null;
    const key = back ? [m.id + ':' + p.name, p.to_map_id + ':' + back.name].sort().join('|') : m.id + ':' + p.name + '>';
    if (seen.has(key)) continue;
    seen.add(key);
    meowLinks.push({ a: m.id, a_portal: p.name, b: p.to_map_id, b_portal: back ? back.name : null, two_way: !!back });
  }
  const i1Links = I1.topo.connections.map((c) => ({ a: mid[c.a], a_portal: c.a_portal, b: mid[c.b], b_portal: c.b_portal, two_way: c.bidirectional }));
  const pairKey = (l) => [l.a, l.b].sort().join('~');
  const i1ByPair = Object.fromEntries(i1Links.map((l) => [pairKey(l), l]));
  const meowByPair = Object.fromEntries(meowLinks.map((l) => [pairKey(l), l]));
  const linkRows = [];
  for (const k of [...new Set([...Object.keys(meowByPair), ...Object.keys(i1ByPair)])].sort()) {
    const ml = meowByPair[k];
    const il = i1ByPair[k];
    const desc = (l) => (l ? `${l.a}:${l.a_portal} ${l.two_way ? '<->' : '->'} ${l.b}:${l.b_portal ?? '(player spawn)'}` : 'absent');
    const descI = (l) => (l ? `${g[l.a]}:${l.a_portal} ${l.two_way ? '<->' : '->'} ${g[l.b]}:${l.b_portal}` : 'absent');
    let change = 'same';
    if (!ml) change = 'link removed';
    else if (!il) change = 'link added';
    else if (ml.two_way && !il.two_way) change = 'one-way became two-way';
    else if (!ml.two_way && il.two_way) change = 'two-way became one-way';
    else if (ml.a_portal !== il.a_portal && !(ml.a === il.b && ml.a_portal === il.b_portal)) change = 'portal names differ';
    linkRows.push({ pair: k, meowdb: desc(ml), iteration_one: descI(il), change, ml, il });
    if (change !== 'same') {
      add({
        area: 'link', map: ml ? ml.a : il.a, subject: `${(ml || il).a} <-> ${(ml || il).b}`, meowdb: desc(ml), iteration_one: descI(il), change,
        impact: 'high',
        recommendation: change === 'one-way became two-way'
          ? `Make the trail walkable in both directions and turn the arrival-only marker (layout.py ONE_WAY, asset Portal_Arrival) at ${g[ml.b]}:${ml.b_portal} into a real two-way portal that leads back to ${g[ml.a]}:${ml.a_portal}.`
          : 'Rebuild the connection to match MeowDB.',
      });
    }
  }

  // ---- portals (portal level)
  for (const m of maps) {
    const t = tmap[g[m.id]];
    const tP = [
      ...t.exits.map((e) => ({ name: e.portal, x: e.x, y: e.y, to: mid[e.to_map], to_portal: e.to_portal, pt: e.pt, arrival: false })),
      ...(t.arrival_points || []).map((a) => ({ name: a.portal, x: a.x, y: a.y, to: null, to_portal: null, pt: a.pt, arrival: true })),
    ];
    for (const p of m.portals) {
      const q = tP.find((x) => x.name === p.name);
      const subj = `portal ${p.name}`;
      if (!q) { add({ area: 'portal', map: m.id, subject: subj, meowdb: `-> ${p.to_map_id}`, iteration_one: 'absent', change: 'portal added', impact: 'high', recommendation: 'Add the portal in Blender.' }); continue; }
      if (q.arrival) {
        add({ area: 'portal', map: m.id, subject: subj, meowdb: `type ${p.type} -> ${p.to_map_id}:${p.to_portal}`, iteration_one: `arrival point only (pt ${q.pt}, no target)`, change: 'arrival-only point became an exit', impact: 'high', recommendation: `Promote the existing Blender anchor ${g[m.id]}:${p.name} (an arrival marker today) to an exit portal to ${g[p.to_map_id]}:${p.to_portal}. Its MeowDB position (${p.x_px},${p.y_px}) equals the v8 arrival point${q.x === p.x_px && q.y === p.y_px ? '' : ' NOT (check)'}, so the anchor needs no move.` });
        continue;
      }
      if (q.to !== p.to_map_id) add({ area: 'portal', map: m.id, subject: subj, meowdb: `-> ${p.to_map_id}`, iteration_one: `-> ${q.to}`, change: 'destination changed', impact: 'high', recommendation: 'Use the MeowDB destination.' });
      if (q.to_portal !== p.to_portal) add({ area: 'portal', map: m.id, subject: subj + ' to_portal', meowdb: p.to_portal ?? `null (${p.to_portal_derivation})`, iteration_one: q.to_portal, change: 'destination portal differs', impact: 'medium', recommendation: 'Use the reverse-lookup to_portal; when it is null, arrive at a player spawn.' });
      if (q.pt !== p.type) add({ area: 'portal', map: m.id, subject: subj + ' type', meowdb: p.type, iteration_one: q.pt, change: 'portal type differs', impact: 'low', recommendation: 'Keep MeowDB type as data; it does not change routing.' });
      if (q.x !== p.x_px || q.y !== p.y_px) {
        const d = Math.round(Math.hypot(q.x - p.x_px, q.y - p.y_px));
        add({ area: 'portal', map: m.id, subject: subj + ' position', meowdb: `(${p.x_px},${p.y_px})`, iteration_one: `(${q.x},${q.y})`, change: `moved ${d} px`, impact: d > 50 ? 'medium' : 'low', recommendation: 'Keep the Blender anchor: exact portal transforms are MisoStory adaptation data (brief, "Map Data Authority"). The MeowDB px position describes a different 2D layout; do not project it onto the v8-based 3D geometry.' });
      }
    }
    for (const q of tP) {
      if (m.portals.some((p) => p.name === q.name)) continue;
      if (q.arrival) {
        add({ area: 'portal', map: m.id, subject: `portal ${q.name}`, meowdb: 'absent (MeowDB lists only portals with a destination)', iteration_one: `arrival point (pt ${q.pt}) at (${q.x},${q.y})`, change: 'arrival point not in MeowDB', impact: 'medium', recommendation: `Arrivals from ${g[byId[m.id].connected_maps.map((c) => c.map_id).find((x) => byId[x].portals.some((p) => p.to_map_id === m.id && p.to_portal_derivation === 'none'))] ?? '?'} have no destination portal: spawn the player at a MeowDB player spawn of ${m.id}. The Blender anchor ${g[m.id]}:${q.name} may stay as the 3D arrival transform (adaptation), but it must not be an exit.` });
      } else {
        add({ area: 'portal', map: m.id, subject: `portal ${q.name}`, meowdb: 'absent', iteration_one: `-> ${q.to}:${q.to_portal}`, change: 'portal removed', impact: 'high', recommendation: 'Remove or disable the portal in the runtime.' });
      }
    }
  }

  // ---- player spawns (positions) and v8 non-exit portal points, against the raw v8 WZ portal nodes
  //      (docs/research/portals_xml.json: pt 0 "sp" = player spawn; other targetless nodes such as h001/tp).
  const fmtPts = (ps) => ps.map((p) => `(${p.x},${p.y})`).join(' ');
  const nonExitSeen = [];
  for (const m of maps) {
    const t = tmap[g[m.id]];
    const v8 = I1.portalsXml[String(t.id)];
    failIf(!v8 || !Array.isArray(v8.portals), `${t.id}: portals_xml.json entry missing`);
    const sp = v8.portals.filter((p) => p.pt === 0).map((p) => ({ x: p.x, y: p.y }));
    failIf(sp.length !== t.spawn_points, `${t.id}: portals_xml sp count ${sp.length} != topology spawn_points ${t.spawn_points}`);
    const left = sp.map((p) => `${p.x},${p.y}`);
    const moved = [];
    for (const p of m.player_spawns) {
      const i = left.indexOf(`${p.x_px},${p.y_px}`);
      if (i >= 0) left.splice(i, 1);
      else moved.push({ x: p.x_px, y: p.y_px });
    }
    const unmatched = left.map((k) => { const [x, y] = k.split(',').map(Number); return { x, y }; });
    if (moved.length || unmatched.length) {
      const meanY = (ps) => ps.reduce((a, p) => a + p.y, 0) / ps.length;
      const dy = moved.length && unmatched.length ? Math.round(meanY(moved) - meanY(unmatched)) : null;
      // When does the runtime use this map's player spawns? Derived from MeowDB data (plus Iteration One's start map).
      const uses = [];
      const deathFrom = maps.filter((x) => x.return_map_id === m.id).map((x) => x.id);
      if (deathFrom.length) uses.push(`death respawn (return map of ${deathFrom.length === 1 ? deathFrom[0] : deathFrom.length + ' maps'})`);
      const arriveFrom = maps.flatMap((x) => x.portals.filter((p) => p.to_map_id === m.id && p.to_portal === null).map((p) => `${x.id} ${p.name}`));
      if (arriveFrom.length) uses.push(`arrival from ${arriveFrom.join(', ')} (no destination portal)`);
      if (t.id === I1.topo.start_map) uses.push('new characters (Iteration One\'s start map; MeowDB marks no start map)');
      const useText = uses.length
        ? `On this map the player spawns are used for: ${uses.join('; ')}.`
        : `No MeowDB data routes players to these spawns (no map returns here on death, and every portal into ${m.id} has a destination portal); they matter only if the runtime spawns players here directly.`;
      add({
        area: 'player_spawn', map: m.id, subject: 'player spawn positions',
        meowdb: `${moved.length} of ${m.player_spawns.length} not at a v8 point: ${fmtPts(moved)}`,
        iteration_one: `v8 sp with no MeowDB match: ${fmtPts(unmatched)} (docs/research/portals_xml.json)`,
        change: `${moved.length} of ${m.player_spawns.length} moved` + (dy === null ? '' : `; MeowDB's moved points are on average ${Math.abs(dy)} px ${dy > 0 ? 'lower' : 'higher'} (y down)`),
        impact: 'medium',
        recommendation: `${useText} MeowDB's points describe a different 2D layout from v8 here: do not project the px onto the v8-based Blender geometry. Author 3D spawn transforms that follow MeowDB's relative placement (which tier, which side of the map).`,
      });
    }
    // v8 portal nodes that are neither player spawns, nor v8 exits/arrival points (rows above), nor MeowDB portals.
    const known = new Set([...t.exits.map((e) => e.portal), ...(t.arrival_points || []).map((a) => a.portal), ...m.portals.map((p) => p.name)]);
    const groups = new Map();
    for (const p of v8.portals) {
      if (p.pt === 0 || known.has(p.pn)) continue;
      const k = `${p.pn}|${p.pt}`;
      if (!groups.has(k)) groups.set(k, []);
      groups.get(k).push(p);
    }
    for (const [k, ps] of groups) {
      const [pn, pt] = k.split('|');
      nonExitSeen.push(`${t.id}:${pn}x${ps.length}`);
      add({
        area: 'portal', map: m.id, subject: `v8 point ${pn}${ps.length > 1 ? ` x${ps.length}` : ''}`,
        meowdb: 'absent (no MeowDB portal by this name)',
        iteration_one: `${ps.length} v8 node(s), type ${pt}, no target, at ${fmtPts(ps)}; never built as an exit`,
        change: 'v8 non-exit point not in MeowDB', impact: 'low',
        recommendation: 'No action: there is nothing in MeowDB to place, and Iteration One never built it as an exit.',
      });
    }
  }
  failIf(nonExitSeen.sort().join(' ') !== '1010000:tpx6 60000:h001x1 60000:tpx6', 'v8 non-exit points changed: ' + nonExitSeen.join(' ') + ' (update section 8 text)');

  // ---- NPCs
  for (const m of maps) {
    const t = tmap[g[m.id]];
    for (const n of m.npcs) {
      const q = t.npcs.find((x) => x.name === n.name);
      if (!q) {
        const elsewhere = I1.topo.maps.find((x) => x.npcs.some((y) => y.name === n.name));
        add({ area: 'npc', map: m.id, subject: `${n.name} (MeowDB npc ${n.id})`, meowdb: `on ${m.id} at (${n.x_px},${n.y_px})`, iteration_one: elsewhere ? `on ${elsewhere.id} ${elsewhere.name}` : 'absent from all 25 maps', change: elsewhere ? 'NPC moved to another map' : 'NPC added', impact: 'high', recommendation: elsewhere ? `Move ${n.name} from the ${elsewhere.slug} collection to ${t.slug}; choose a 3D spot that matches MeowDB's relative position.` : `Add an NPC proxy for ${n.name} to ${t.slug} near MeowDB's (${n.x_px},${n.y_px}).` });
      } else if (q.x !== n.x_px || q.y !== n.y_px) {
        const d = Math.round(Math.hypot(q.x - n.x_px, q.y - n.y_px));
        add({ area: 'npc', map: m.id, subject: `${n.name} position`, meowdb: `(${n.x_px},${n.y_px})`, iteration_one: `(${q.x},${q.y})`, change: `offset ${q.x - n.x_px === 0 ? '' : `dx ${n.x_px - q.x} `}dy ${n.y_px - q.y} (${d} px)`.replace('  ', ' '), impact: d > 20 ? 'medium' : 'low', recommendation: d > 20 ? 'Re-place the NPC in Blender if fidelity matters: MeowDB puts it somewhere else on this map.' : 'No change: the offset is a y reference difference (Iteration One stored the foothold-snapped y).' });
      }
    }
    for (const q of t.npcs) {
      if (m.npcs.some((n) => n.name === q.name)) continue;
      const elsewhere = maps.find((x) => x.npcs.some((y) => y.name === q.name));
      add({ area: 'npc', map: m.id, subject: `${q.name} (v8 npc ${q.id})`, meowdb: elsewhere ? `on ${elsewhere.id} ${elsewhere.name}` : 'absent from all 25 maps', iteration_one: `on ${t.id} at (${q.x},${q.y})`, change: elsewhere ? 'NPC moved to another map' : 'NPC removed', impact: 'high', recommendation: elsewhere ? 'See the matching "moved" row.' : `Do not spawn ${q.name}: MeowDB has no such NPC on Maple Island. The Blender proxy (built_npcs) should be excluded from the runtime NPC list.` });
    }
  }

  // ---- monsters
  for (const m of maps) {
    const t = tmap[g[m.id]];
    const mm = Object.fromEntries(m.monsters.map((x) => [x.name, x.count]));
    const names = [...new Set([...Object.keys(mm), ...Object.keys(t.mobs)])].sort();
    for (const k of names) {
      const a = mm[k] ?? 0;
      const b = t.mobs[k] ?? 0;
      if (a === b) continue;
      const built = man[t.id].built_mobs[k] ?? 0;
      if (!b) add({ area: 'monster', map: m.id, subject: k, meowdb: a, iteration_one: 0, change: 'species added', impact: 'high', recommendation: `Spawn ${k} (MeowDB id ${m.monsters.find((x) => x.name === k).id}) here; Iteration One has no ${k} proxy in ${t.slug}.` });
      else if (!a) add({ area: 'monster', map: m.id, subject: k, meowdb: 0, iteration_one: b, change: 'species removed', impact: 'high', recommendation: `Do not spawn ${k} here.${built ? ` Drop the ${built} representative ${k} proxy(ies) in ${t.slug} from the runtime.` : ''}` });
      else add({ area: 'monster', map: m.id, subject: k, meowdb: a, iteration_one: b, change: `count ${a - b > 0 ? '+' : ''}${a - b}`, impact: 'medium', recommendation: 'Use MeowDB counts as the spawn-point count for this species.' });
    }
  }

  // ---- off-island travel (not a portal): Shanks' ship from Southperry
  if (X0.shanks) {
    const br = I1.topo.branches.find((b) => b.from === 60000 && b.maps.length === 0);
    const i1Fare = br && /(\d+) mesos/.exec(br.description);
    const s = X0.shanks;
    add({
      area: 'travel', map: '000000060', subject: "Shanks' ship (MeowDB NPC 15)",
      meowdb: `one-way to ${s.to}, ${s.fare} mesos, level ${s.level}+ (MeowDB beginner's guide, ${s.url})`,
      iteration_one: br ? `one-way to Lith Harbor, ${i1Fare ? i1Fare[1] : '?'} mesos, no level requirement recorded (era wikis; docs/topology.json branches)` : 'absent',
      change: 'fare and level requirement differ', impact: 'medium',
      recommendation: 'Not a portal and outside the 25 maps: implement as NPC travel owned by the npcs domain (game/data/canonical/npcs/15.json "transport"). Use the MeowDB fare and level gate.',
    });
  }

  D.sort((x, y) => IMPACT_ORDER[x.impact] - IMPACT_ORDER[y.impact] || MAP_IDS.indexOf(x.map) - MAP_IDS.indexOf(y.map) || x.area.localeCompare(y.area) || x.subject.localeCompare(y.subject));
  return { D, linkRows, meowLinks, i1Links, g, mid, byId, tmap, man };
}

// --------------------------------------------------------------------------------------------
// Docs: topology_diff.md
// --------------------------------------------------------------------------------------------

const esc = (v) => String(v ?? '').replace(/\|/g, '\\|');

function renderDiff(maps, I1, cw, X) {
  const { D, linkRows, g, byId, tmap, man } = X;
  const L = [];
  const counts = { high: 0, medium: 0, low: 0 };
  for (const d of D) counts[d.impact]++;
  const areaCount = (a) => D.filter((d) => d.area === a).length;

  L.push('# MeowDB MS Classic vs Iteration One: topology and content diff', '');
  L.push('Generated by `node tools/meowdb/extract_maps.mjs` from the cached MeowDB map pages and the Iteration One files');
  L.push('`docs/topology.json`, `docs/manifest.json`, `docs/research/portals_xml.json` (raw v8 portal nodes, incl. `sp` player spawns),');
  L.push('`docs/research/entities.json` and `src/misostory/layout.py` (`LINKS`, `DOOR_LINKS`, `ONE_WAY`).');
  L.push('Do not hand-edit: change the script and re-run it.', '');
  L.push('MeowDB (MapleStory Classic World, MeowDB ids) is canonical. Iteration One was built from GMS v8 data (GMS ids).');
  L.push('Per the brief, MeowDB decides **what** belongs on a map and **where each portal leads**; the Blender world decides');
  L.push('**exact 3D transforms**. Every recommendation below follows that split.', '');
  L.push('Impact levels:', '');
  L.push('- **high**: changes routing, what the player can interact with, or which monsters exist (portals, links, NPC sets, species).');
  L.push('- **medium**: changes numbers or placement the runtime must honour (spawn counts, mob rate, arrival handling, large position moves).');
  L.push('- **low**: cosmetic or reference-only (names, small y offsets, raw portal type codes).', '');
  L.push(`**Totals:** ${D.length} differences (high ${counts.high}, medium ${counts.medium}, low ${counts.low}): ` +
    `${areaCount('link')} link, ${areaCount('portal')} portal, ${areaCount('player_spawn')} player-spawn, ${areaCount('npc')} NPC, ${areaCount('monster')} monster, ${areaCount('map')} map-property, ${areaCount('travel')} off-island travel.`, '');
  failIf(D.some((d) => !['link', 'portal', 'player_spawn', 'npc', 'monster', 'map', 'travel'].includes(d.area)), 'unknown diff area');

  L.push('## 1. Headline changes and the 3D adaptation', '');
  L.push(...HEADLINES);
  L.push('');

  L.push('## 2. Map id crosswalk', '');
  L.push('Pairs were found by evidence (portal names and coordinates, NPCs, player-spawn counts, species), never by id arithmetic.');
  L.push('MeowDB ids do not follow one rule from GMS ids (0 -> 000000001 but 20001 -> 000000021). Machine-readable copy:');
  L.push('`game/data/misostory/map_id_crosswalk.json`.', '');
  L.push('| MeowDB id | GMS v8 id | Iteration One slug | MeowDB name | Iteration One name | Match basis |');
  L.push('|---|---|---|---|---|---|');
  for (const r of cw) L.push(`| ${r.meowdb_id} | ${r.gms_v8_id} | \`${r.iteration_one_slug}\` | ${esc(r.name)} | ${esc(r.iteration_one_name)} | ${esc(r.match_basis)} |`);
  L.push('');

  L.push('## 3. Connections (map to map)', '');
  const addedRemoved = linkRows.filter((r) => r.change === 'link added' || r.change === 'link removed').length;
  const destChanged = D.filter((d) => d.change === 'destination changed').length;
  L.push(`MeowDB has ${X.meowLinks.length} connections (${X.meowLinks.filter((l) => l.two_way).length} two-way, ${X.meowLinks.filter((l) => !l.two_way).length} one-way); ` +
    `Iteration One has ${X.i1Links.length} (${X.i1Links.filter((l) => l.two_way).length} two-way, ${X.i1Links.filter((l) => !l.two_way).length} one-way). ` +
    `Connections added or removed: ${addedRemoved}. Portals whose destination map changed: ${destChanged}. ` +
    (addedRemoved === 0 && destChanged === 0 ? 'The map graph is the same; only link direction differs.' : 'See section 4.'), '');
  L.push('| Maps | MeowDB (MeowDB ids) | Iteration One (GMS ids) | Change |');
  L.push('|---|---|---|---|');
  for (const r of linkRows) L.push(`| ${r.pair.replace('~', ' / ')} | ${esc(r.meowdb)} | ${esc(r.iteration_one)} | ${r.change === 'same' ? 'same' : '**' + r.change + '**'} |`);
  L.push('');
  L.push(`Iteration One's \`layout.py\` LINKS (${I1.links.length} trail links), DOOR_LINKS (${I1.doorLinks.length} interiors on the remote interior stage) and ONE_WAY ` +
    `(${I1.oneWayIterationOne.map((o) => `${o.map}:${o.portal}`).join(', ')}, the landing anchors of the one-way connections in \`docs/topology.json\`) ` +
    'cover the same 24 map pairs; the ONE_WAY set is where the direction changes land.');
  // MeowDB's one-way links, as the GMS anchors they land on (the arrival-only markers layout.py ONE_WAY should hold).
  const landings = linkRows.filter((r) => r.ml && !r.ml.two_way && r.il).map((r) => `${g[r.ml.b]}:${r.il.b === r.ml.b ? r.il.b_portal : r.il.a_portal}`).sort();
  const current = I1.oneWay.map((o) => `${o.map}:${o.portal}`).sort();
  const sameSet = landings.length === current.length && landings.every((x, i) => x === current[i]);
  L.push(`Today's \`layout.py\` ONE_WAY is (${current.join(', ')}): ` + (sameSet
    ? `exactly the landing anchor${landings.length === 1 ? '' : 's'} of MeowDB's one-way link${landings.length === 1 ? '' : 's'}, as headline 1 recommends.`
    : `**not** the landing anchors of MeowDB's one-way links (${landings.join(', ') || 'none'}); headline 1's adaptation is not applied.`), '');

  L.push('## 4. Every difference, by impact', '');
  L.push('Columns: MeowDB value, Iteration One value (GMS v8 baseline), change, impact, recommended adaptation. Map ids are MeowDB ids; the GMS id is in brackets.', '');
  for (const imp of ['high', 'medium', 'low']) {
    L.push(`### ${imp[0].toUpperCase() + imp.slice(1)} impact (${counts[imp]})`, '');
    L.push('| Map | Area | Subject | MeowDB | Iteration One | Change | Recommendation |');
    L.push('|---|---|---|---|---|---|---|');
    for (const d of D.filter((x) => x.impact === imp)) {
      L.push(`| ${d.map} ${esc(byId[d.map].name)} [${g[d.map]}] | ${d.area} | ${esc(d.subject)} | ${esc(d.meowdb)} | ${esc(d.iteration_one)} | ${esc(d.change)} | ${esc(d.recommendation)} |`);
    }
    L.push('');
  }

  L.push('## 5. What is identical', '');
  const same = (f) => maps.every(f);
  const checks = [
    ['street names', same((m) => m.street_name === tmap[g[m.id]].street)],
    ['return (respawn) maps', same((m) => m.return_map_id === X.mid[tmap[g[m.id]].return_map])],
    ['BGM keys', same((m) => m.bgm.path === tmap[g[m.id]].bgm)],
    ['town flags', same((m) => m.is_town === tmap[g[m.id]].is_town)],
    ['player-spawn counts', same((m) => m.player_spawns.length === tmap[g[m.id]].spawn_points)],
    ['portal destinations (every MeowDB portal that is also a v8 exit leads to the same map)',
      same((m) => m.portals.every((p) => { const e = tmap[g[m.id]].exits.find((x) => x.portal === p.name); return !e || X.mid[e.to_map] === p.to_map_id; }))],
  ];
  for (const [k, v] of checks) L.push(`- ${k}: ${v ? 'identical on all 25 maps' : 'NOT identical (see section 4)'}`);
  // The hand-written HEADLINES assume these facts; fail loudly if a refreshed cache changes them.
  const has = (pred) => D.some(pred);
  failIf(!checks.every(([, v]) => v), 'HEADLINES item 7 is out of date');
  failIf(linkRows.filter((r) => r.change === 'one-way became two-way').length !== 3 || linkRows.filter((r) => r.change !== 'same' && r.change !== 'one-way became two-way').length, 'HEADLINES item 1 is out of date');
  failIf(!['Todd', 'Sam'].every((n) => has((d) => d.area === 'npc' && d.change === 'NPC added' && d.subject.startsWith(n))), 'HEADLINES item 2 (added) is out of date');
  failIf(!['Paul', 'Tia', 'Maple Administrator'].every((n) => has((d) => d.area === 'npc' && d.change === 'NPC removed' && d.subject.startsWith(n))), 'HEADLINES item 2 (removed) is out of date');
  failIf(!has((d) => d.subject.startsWith('Mai ') && d.change === 'NPC moved to another map'), 'HEADLINES item 2 (Mai) is out of date');
  failIf(D.filter((d) => d.area === 'map' && d.subject === 'name').length !== 1, 'HEADLINES item 5 is out of date');
  failIf(D.filter((d) => d.area === 'portal' && / position$/.test(d.subject)).map((d) => `${d.map}:${d.subject}`).join(' ') !==
    '000000001:portal out00 position 000000020:portal out00 position 000000042:portal east00 position', 'HEADLINES item 4 (portal moves) is out of date');
  failIf(!has((d) => d.map === '000000001' && d.subject === 'Heena position'), 'HEADLINES item 4 (Heena) is out of date');
  failIf(D.filter((d) => d.area === 'player_spawn').map((d) => `${d.map}:${d.change}`).join(' | ') !==
    "000000001:4 of 4 moved; MeowDB's moved points are on average 345 px lower (y down) | 000001021:5 of 9 moved; MeowDB's moved points are on average 361 px higher (y down)",
    'HEADLINES item 4 (player spawns) is out of date');
  const unchangedMaps = maps.filter((m) => !D.some((d) => d.map === m.id)).map((m) => `${m.id} ${m.name} [${g[m.id]}]`);
  L.push(`- maps with no difference at all: ${unchangedMaps.length ? unchangedMaps.join('; ') : 'none'}`);
  L.push('');

  L.push('## 6. Monster spawn totals and NPC sets per map', '');
  L.push('Monster counts are spawn points (MeowDB `monsters[].count`, Iteration One v8 `mobs`). "Built" is what Iteration One actually placed');
  L.push('in Blender (`built_mobs`/`built_npcs` in docs/manifest.json: 1-2 representative proxies per species).', '');
  L.push('| Map | MeowDB monsters | Iteration One v8 monsters | Built proxies | MeowDB NPCs | Iteration One NPCs |');
  L.push('|---|---|---|---|---|---|');
  for (const m of maps) {
    const t = tmap[g[m.id]];
    const mt = m.monsters.reduce((a, x) => a + x.count, 0);
    const tt = Object.values(t.mobs).reduce((a, x) => a + x, 0);
    const fmt = (o) => Object.entries(o).map(([k, v]) => `${k} ${v}`).join(', ');
    L.push(`| ${m.id} [${g[m.id]}] | ${mt ? `${mt}: ${fmt(Object.fromEntries(m.monsters.map((x) => [x.name, x.count])))}` : '-'} | ${tt ? `${tt}: ${fmt(t.mobs)}` : '-'} | ${fmt(man[t.id].built_mobs) || '-'} | ${m.npcs.map((n) => `${n.name} (${n.id})`).join(', ') || '-'} | ${t.npcs.map((n) => `${n.name} (${n.id})`).join(', ') || '-'} |`);
  }
  const mt = maps.reduce((a, m) => a + m.monsters.reduce((b, x) => b + x.count, 0), 0);
  const tt = I1.topo.maps.reduce((a, t) => a + Object.values(t.mobs).reduce((b, x) => b + x, 0), 0);
  L.push('', `Island total: MeowDB ${mt} monster spawn points, Iteration One v8 ${tt}.`, '');

  L.push('## 7. NPC and monster id crosswalk (by name; informational)', '');
  L.push('MeowDB NPC and monster ids are MeowDB\'s own numbering and do not equal GMS ids. Pairs below are by exact name on the same');
  L.push('island, with GMS ids from Iteration One\'s `docs/topology.json` / `docs/research/entities.json`. Canonical data uses the MeowDB id only.', '');
  L.push('| MeowDB NPC id | Name | MeowDB map | GMS NPC id (Iteration One research, with era) |');
  L.push('|---|---|---|---|');
  const allNpcs = maps.flatMap((m) => m.npcs.map((n) => ({ ...n, map: m.id })));
  const gNpc = (name) => Object.entries(I1.entities.npcs).filter(([, v]) => v.name === name).map(([k, v]) => `${k} (${v.era})`);
  for (const n of [...allNpcs].sort((a, b) => Number(a.id) - Number(b.id))) L.push(`| ${n.id} | ${n.name} | ${n.map} | ${gNpc(n.name).join(', ') || 'none'} |`);
  const goneNpcs = I1.topo.maps.flatMap((t) => t.npcs.filter((q) => !allNpcs.some((n) => n.name === q.name)).map((q) => `${q.name} (GMS ${q.id}, ${t.id})`));
  L.push('', `Iteration One NPCs with no MeowDB counterpart on Maple Island: ${goneNpcs.join(', ') || 'none'}.`, '');
  L.push('| MeowDB monster id | Name | GMS mob id (Iteration One research, with era) |');
  L.push('|---|---|---|');
  const allMobs = [...new Map(maps.flatMap((m) => m.monsters.map((x) => [x.id, x.name]))).entries()].sort((a, b) => Number(a[0]) - Number(b[0]));
  for (const [id, name] of allMobs) L.push(`| ${id} | ${name} | ${Object.entries(I1.entities.mobs).filter(([, v]) => v.name === name).map(([k, v]) => `${k} (${v.era})`).join(', ') || 'none'} |`);
  L.push('');

  L.push('## 8. MeowDB content Iteration One never modelled', '');
  const reactorMaps = maps.filter((m) => m.reactors.length);
  L.push(`- **Breakable reactors** ("${[...new Set(maps.flatMap((m) => m.reactors.map((r) => r.name)))].join('", "')}", MeowDB reactor id ${[...new Set(maps.flatMap((m) => m.reactors.map((r) => r.id)))].join(', ')}): ` +
    reactorMaps.map((m) => `${m.id} x${m.reactors.length}`).join(', ') + '. Respawn in seconds is in each map file. Iteration One has none; add breakable props at adapted positions.');
  L.push('- **Field restrictions**: ' + maps.filter((m) => m.field_restrictions.length).map((m) => `${m.id} (${m.field_restrictions.map((r) => r.label).join(', ')}; field_limit ${m.field_limit})`).join(', ') + '. Iteration One has no field-limit data.');
  L.push('- **Quests per map** (starts here / progress here) and **NPC idle speech lines**: in each map file under `quests` and `npcs[].idle_speech_lines`.');
  L.push('');
  L.push('Absent from MeowDB, present in Iteration One\'s research (low impact, no action): the v8 non-exit portal points listed in');
  L.push('docs/MAP_INVENTORY.md section 1 ("Not listed as exits"): Southperry `h001` (type 1, no target) and the six `tp` points (type 6)');
  L.push('each in Southperry and Amherst. Every portal MeowDB lists has a destination, and targetless points (like v8\'s arrival-only');
  L.push('40000 `in00`) do not appear, so these points have no canonical counterpart; Iteration One never built them as exits either.');
  L.push('They are the low-impact "v8 point" rows in section 4 (the extractor asserts this set against `docs/research/portals_xml.json`).');
  L.push('- **Monster spawn points and player spawns with px coordinates**: Iteration One kept only per-species monster counts and placed 1-2 representative proxies per species (`built_mobs` in docs/manifest.json). Its research has the v8 player-spawn px (`sp` nodes, compared in section 4), but the Blender build has no player-spawn anchors.');
  L.push('');

  L.push('## 9. External cross-check: GMS v8 destination portal names (not canonical)', '');
  L.push('The `tn` (target portal) values below come from Iteration One\'s `docs/topology.json` (raw GMS v8 WZ, maplestory.io). They are an');
  L.push('external cross-check only and are NOT used in the canonical files. Canonical `to_portal` is MeowDB reverse lookup.', '');
  L.push('| MeowDB portal | MeowDB to_portal (reverse lookup) | GMS v8 tn (Iteration One) | Agree? |');
  L.push('|---|---|---|---|');
  let agree = 0, total = 0;
  for (const m of maps) for (const p of m.portals) {
    const t = tmap[g[m.id]];
    const e = t.exits.find((x) => x.portal === p.name);
    const tn = e ? e.to_portal : null;
    total++;
    const ok = tn === p.to_portal;
    if (ok) agree++;
    L.push(`| ${m.id}:${p.name} -> ${p.to_map_id} | ${p.to_portal ?? 'null (' + p.to_portal_derivation + ')'} | ${tn ?? (e ? 'none' : 'no v8 exit (arrival point only)')} | ${ok ? 'yes' : 'no'} |`);
  }
  L.push('', `${agree} of ${total} agree. The disagreements are exactly the portals that are arrival-only points in v8 (no tn) and the`);
  L.push('one MeowDB portal with no reverse match (v8 targets an arrival point that MeowDB does not list).', '');
  return L.join('\n') + '\n';
}

// Narrative for section 1. Kept here so a re-run reproduces the doc; every claim is backed by a row in section 4.
const HEADLINES = [
  '1. **The Mushroom Town funnel is two-way in MeowDB except its last step.** Iteration One modelled 0 -> 10000 -> 20000 -> 30000 -> 40000',
  '   as four one-way links (v8 `in00` points are type 1 arrival-only). In MeowDB, `in00` on 000000010, 000000020 and 000000030 is a type 2',
  '   portal back to the previous map, at exactly the v8 arrival coordinates. Only 000000030 `out00` -> 000000040 stays one-way:',
  '   000000040 has no `in00` at all, so arrivals there use its player spawns (`to_portal: null`, `to_portal_derivation: "none"`).',
  '   **Adaptation:** in `layout.py` keep only `(40000, "in00")` in `ONE_WAY`; give the 10000, 20000 and 30000 `in00` anchors a',
  '   `Portal_Swirl` exit back west; make the three trails between them walkable both ways (check traversal for drop-only steps). Keep',
  '   the 40000 `in00` anchor as the arrival transform for 000000030 `out00`, not as an exit.',
  '2. **NPC set changes.** Todd (000000030), Sam (000000040) are new; Mai moves from Amherst to A Split Road (000000050); Paul, Tia and',
  '   the Maple Administrator, built into Iteration One\'s Southperry, do not exist in MeowDB\'s Southperry. **Adaptation:** add Todd and',
  '   Sam proxies, move Mai\'s proxy, and leave the three Southperry extras out of the runtime NPC list (the geometry can stay).',
  '3. **Monsters.** 000000030 East Entrance to Mushroom Town (a town map, `is_town: true`, mob rate 0.6) has 6 Tutorial Jr. Sentinels',
  '   that Iteration One never placed; Blue Snails are gone from 000000040; Orange Mushrooms appear in 000001014 Snail Field of Flowers;',
  '   almost every hunting map has fewer spawn points than v8. **Adaptation:** spawn definitions must come from MeowDB `spawns`/`monsters`',
  '   counts; Iteration One\'s representative proxies are only visual placeholders. Combat code must not assume "town = no monsters".',
  '4. **Some maps have a different 2D layout than v8.** The portal moves on 000000001 `out00`, 000000020 `out00` and 000000042 `east00`',
  '   match the positions Iteration One itself recorded as the GMS v22 variant (docs/topology.json notes, docs/research/portals_xml.json',
  '   `cross_version`). Heena\'s new spot and all 4 player spawns on 000000001 (about 345 px lower than v8\'s spawn plateau) lie in the',
  '   west half that those notes say v22 re-lays out, but Iteration One recorded no v22 positions for them, so no match is claimed. On',
  '   000001021 Tomato Field, 5 of the 9 player spawns sit about 361 px higher than the v8 ground-tier spawns they replace, although',
  '   Iteration One recorded Tomato Field\'s v22 portals as identical to v8. This is an in-repo cross-reference, not a claim that',
  '   MapleStory Classic World equals v22. **Adaptation:** keep the Blender anchors (exact transforms are MisoStory data); do not project',
  '   MeowDB px positions onto the v8-shaped 3D geometry of these maps; place 3D player spawns that follow MeowDB\'s relative placement.',
  '5. **Name change.** GMS 0 "West Entrance to Mushroom Town" is MeowDB 000000001 "Mushroom Town - West Entrance". The UI should show',
  '   the MeowDB name; the Blender slug `WestEntranceMushroomTown_0` stays and is resolved through the crosswalk.',
  '6. **Small y offsets (2-9 px) on Roger, Nina, Pan and Sid** are a y-reference difference: Iteration One stored the foothold-snapped',
  '   y, and its `docs/topology.json` unit_note says the raw WZ life y is 2-9 px smaller for exactly these NPCs, which is what MeowDB shows.',
  '   MeowDB itself does not document its y reference. No action.',
  '7. **Unchanged:** the map graph (same 24 map pairs, same destinations), street names, respawn maps, BGM keys, town flags and',
  '   player-spawn counts (section 5).',
];

// --------------------------------------------------------------------------------------------
// main
// --------------------------------------------------------------------------------------------

async function main() {
  const maps = [];
  for (const id of MAP_IDS) maps.push(buildMap(id, await loadPage(id)));
  deriveToPortals(maps);

  // Self-checks on the reverse lookup.
  const byId = Object.fromEntries(maps.map((m) => [m.id, m]));
  let none = 0;
  for (const m of maps) for (const p of m.portals) {
    if (p.to_portal_derivation === 'none') { none++; continue; }
    const q = byId[p.to_map_id].portals.find((x) => x.name === p.to_portal);
    failIf(!q || q.to_map_id !== m.id, `${m.id}.${p.name}: reverse lookup inconsistent`);
  }
  // Cross-page consistency: names on the source page agree with the destination's own page, and
  // connectedMaps is exactly the union of outgoing portal targets and maps with a portal into this one.
  for (const m of maps) {
    for (const p of m.portals) {
      const d = byId[p.to_map_id];
      failIf(p.to_map_name !== d.name || p.to_street_name !== d.street_name, `${m.id}.${p.name}: destination name/street disagrees with ${d.id}'s page`);
    }
    const expect = new Set([...m.portals.map((p) => p.to_map_id), ...maps.filter((x) => x.portals.some((p) => p.to_map_id === m.id)).map((x) => x.id)]);
    const got = new Set(m.connected_maps.map((c) => c.map_id));
    failIf(expect.size !== got.size || [...expect].some((x) => !got.has(x)), `${m.id}: connected_maps is not outgoing+incoming`);
    for (const c of m.connected_maps) failIf(c.map_name !== byId[c.map_id].name, `${m.id}: connected map name disagrees for ${c.map_id}`);
    for (const qs of Object.values(m.quests)) for (const q of qs) for (const o of q.objectives_on_this_map || []) {
      failIf(!m.monsters.some((x) => x.id === o.mob_id), `${m.id}: quest ${q.id} objective mob ${o.mob_id} not on map`);
    }
  }

  // Key order: id, name first; then domain fields; source/field_sources/notes/gaps last (as built).
  fs.mkdirSync(OUT_DIR, { recursive: true });
  for (const f of fs.readdirSync(OUT_DIR)) if (/^\d{9}\.json$/.test(f) && !MAP_IDS.includes(f.slice(0, 9))) fs.rmSync(path.join(OUT_DIR, f));
  for (const m of maps) writeJson(path.join(OUT_DIR, m.id + '.json'), m);

  const I1 = loadIterationOne();
  const cw = crosswalk(maps, I1);
  writeJson(CROSSWALK_FILE, cw.map(({ meowdb_id, gms_v8_id, iteration_one_slug, name, iteration_one_name, match_basis }) => ({ meowdb_id, gms_v8_id, iteration_one_slug, name, iteration_one_name, match_basis })));
  // Shanks' ship facts live on MeowDB's beginner guide (cache-first; owned by the npcs domain, used here only for the diff).
  const GUIDE = '/guides/beginners-guide-first-steps-in-maple-world';
  const guide = await fetchPage(GUIDE);
  const gm = /Shanks at the dock sails you to ([A-Z][a-z]+(?: [A-Z][a-z]+)*) for ([\d,]+) mesos once you reach level (\d+)\. The boat is one-way\./.exec(pageText(guide.html).replace(/\s+/g, ' '));
  failIf(!gm, "beginner guide: Shanks' ship sentence not found; update the regex rather than silently dropping the diff row");
  const shanks = { to: gm[1], fare: Number(gm[2].replace(/,/g, '')), level: Number(gm[3]), url: `${BASE_URL}${GUIDE}` };
  const X = computeDiff(maps, I1, cw, { shanks });
  fs.mkdirSync(path.dirname(DIFF_FILE), { recursive: true });
  fs.writeFileSync(DIFF_FILE, renderDiff(maps, I1, cw, X));

  const portals = maps.reduce((a, m) => a + m.portals.length, 0);
  console.log(`maps: ${maps.length} files -> ${path.relative(ROOT, OUT_DIR)}`);
  console.log(`portals: ${portals} (${portals - none} reverse_lookup, ${none} none)`);
  console.log(`crosswalk: ${cw.length} rows -> ${path.relative(ROOT, CROSSWALK_FILE)}`);
  console.log(`diff: ${X.D.length} differences -> ${path.relative(ROOT, DIFF_FILE)}`);
}

main().catch((e) => { console.error(e); process.exit(1); });
