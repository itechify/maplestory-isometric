// Extract the Maple Island item set from MeowDB MS Classic into game/data/canonical/items/<item id>.json
// (one item per file, MeowDB item ids).
//
//   node tools/meowdb/extract_items.mjs            # cache-first (tools/meowdb/.cache); fetches only what is missing
//   node tools/meowdb/extract_items.mjs --refresh  # re-download every page (new retrieved_at values)
//
// Which items: ITEM_IDS below (the ids referenced by the maps / monsters / drops / quests / npcs / shops domains),
// plus every item in game/data/canonical/shops/*.json and the Beginner starter weapons in
// game/data/canonical/formulas/beginner.json (both are already in ITEM_IDS; the script stops if one is not).
//
// Pages read per item (all cache-first through lib.mjs, so retrieved_at comes from the cache meta):
//   /item-db/<id>                              primary: everything rendered server-side (header, requirements, stat
//                                              rows, flags, weapon details, shops, MSEA reference drops, quest rewards,
//                                              "Needed By", breakables, crafting recipes, change history)
//   /api/items/<id>?locale=en&preview=1        MeowDB's item hover-preview JSON (msclassic layout chunk): structured
//                                              stats, requirements, in-game description, icon key, slotMax, sell price
//   /api/drops?itemId=<id>                     community-sourced monster drops (the page's "Dropped By" list loads
//                                              client-side from this endpoint; it only carries monster ids and votes)
//   /_next/static/chunks/782-*.js              the monster list bundled with the item page (export IW: {id, name,
//                                              level, ...}); the page itself uses it to name the community drops
//   /guides/beginners-guide-first-steps-in-maple-world   the character-creation weapon choice (starter weapons)
//   /quest-tracker/<quest id>                  only for "Quest Reward" rows with a random-reward share "(N%)": the item
//                                              page rounds that share to a whole percent; the quest page's structured
//                                              rewardRandom pool gives it to one decimal plus the pool's totalWeight
//                                              (e.g. 14.3 = 1 of 7). The quest page value is used; differences are
//                                              recorded per file in "discrepancies".
//
// Deterministic: no clocks, fixed key order, lists in MeowDB's display order. Re-running reproduces the files exactly.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { fetchPage, fetchUrl, rsc, jsonAt, pageText, source, writeJson, BASE_URL } from './lib.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..');
const CANON = path.join(ROOT, 'game', 'data', 'canonical');
const OUT_DIR = path.join(CANON, 'items');

// Item ids requested for Iteration Two (MeowDB ids). Order here does not matter; output is one file per id.
const ITEM_IDS = [
  59, 61, 139, 143, 177, 209, 213, 236, 237, 270, 320, 321, 322, 324, 327, 347, 348, 349, 350, 351, 356, 413, 414, 415,
  417, 441, 442, 483, 522, 541, 543, 558, 562, 576, 577, 589, 595, 608, 633, 651, 666, 709, 710, 711, 713, 714, 715,
  724, 731, 900, 933, 934, 935, 937, 938, 939, 940, 945, 960, 963, 1157, 1160, 1163, 1168, 1175, 1177, 1181, 1195,
  1305, 1308, 1314, 1317, 1325, 1327, 1439, 1440, 235, 239, 269, 271, 438, 585, 1158, 1161, 1306, 439, 440, 559, 708,
  712, 525, 238, 240, 273, 551,
].map(String);

const GUIDE_PATH = '/guides/beginners-guide-first-steps-in-maple-world';
const itemPagePath = (id) => '/item-db/' + id;
const itemApiUrl = (id) => BASE_URL + '/api/items/' + id + '?locale=en&preview=1';
const dropsApiUrl = (id) => BASE_URL + '/api/drops?itemId=' + id;
const MONSTER_LIST_MARKER = '{id:1,name:"Tutorial Jr. Sentinel"';
// Tooltip of the "COT2 prices" badge on every "Where to buy" row (checked on every row; documented once in items.md).
const SHOP_PRICE_TITLE = 'Every price in this shop was read from in-game footage of the second Closed Beta.';

const freshFetches = [];
// Counters of cross-checks performed (printed at the end so a silent no-op check is visible).
const CHECKS = { description_vs_page: 0, description_vs_cot2_text: 0, stat_rows_vs_api: 0, base_stats_vs_rows: 0, quest_reward_chance_vs_quest_page: 0, shop_rows_vs_shops_domain: 0, drop_rows_vs_drops_domain: 0 };
async function get(u) {
  const r = u.startsWith('http') ? await fetchUrl(u) : await fetchPage(u);
  if (!r.fromCache) freshFetches.push(r.url);
  return r;
}
const at = (r) => ({ url: r.url, retrieved_at: r.retrieved_at });

// ---------------------------------------------------------------------------------------------------------------
// React Server Component payload -> plain node tree.
// Pages render into the flight payload as ["$", type, key, props] elements; children may be lazy references
// "$L<hex>" to other rows. normalize() resolves those and returns {t, k, p, c, parent} nodes (strings for text).
function makeTree(html, itemId) {
  const r = rsc(html);
  const rowCache = new Map();
  const row = (id) => {
    if (rowCache.has(id)) return rowCache.get(id);
    let v = null;
    const needle = '\n' + id + ':';
    for (let i = r.indexOf(needle); i >= 0 && v == null; i = r.indexOf(needle, i + 1)) {
      const c = r[i + needle.length];
      if (c === '[' || c === '{' || c === '"') {
        try { v = jsonAt(r, i + needle.length).value; } catch { v = null; }
      }
    }
    rowCache.set(id, v);
    return v;
  };
  const resolve = (n, guard = 0) => (typeof n === 'string' && /^\$L[0-9a-f]+$/.test(n) && guard < 50 ? resolve(row(n.slice(2)), guard + 1) : n);
  const isEl = (n) => Array.isArray(n) && n[0] === '$' && typeof n[1] === 'string';
  function normalize(n, parent, depth = 0) {
    n = resolve(n);
    if (n == null || n === false || n === true || depth > 400) return [];
    if (typeof n === 'number') return [String(n)];
    if (typeof n === 'string') return n.startsWith('$') ? [] : [n];
    if (isEl(n)) {
      const { children, ...p } = n[3] && typeof n[3] === 'object' ? n[3] : {};
      const node = { t: n[1], k: n[2] ?? null, p, c: [], parent };
      node.c = normalize(children, node, depth + 1);
      return [node];
    }
    if (Array.isArray(n)) return n.flatMap((x) => normalize(x, parent, depth + 1));
    return [];
  }
  // Root: the payload row that holds the item page body, recognised by its ["$","$L..",null,{"kind":"item","id":N}] child.
  const marker = '{"kind":"item","id":' + itemId + '}';
  const mi = r.indexOf(marker);
  if (mi < 0) throw new Error('item ' + itemId + ': page body marker not found');
  const ls = r.lastIndexOf('\n', mi);
  const m = /^\n([0-9a-f]+):/.exec(r.slice(ls, ls + 12));
  if (!m) throw new Error('item ' + itemId + ': page body row not found');
  const body = { t: 'root', k: null, p: {}, c: [], parent: null };
  body.c = normalize(row(m[1]), body);
  return { r, body };
}

const isNode = (n) => n && typeof n === 'object';
function textOf(n) {
  const out = [];
  const rec = (x) => { if (typeof x === 'string') out.push(x); else if (isNode(x)) x.c.forEach(rec); };
  rec(n);
  return out.join('').replace(/\s+/g, ' ').trim();
}
function rawText(n) {
  const out = [];
  const rec = (x) => { if (typeof x === 'string') out.push(x); else if (isNode(x)) x.c.forEach(rec); };
  rec(n);
  return out.join('');
}
function findAll(n, pred, out = []) {
  if (!isNode(n)) return out;
  for (const c of n.c) {
    if (!isNode(c)) continue;
    if (pred(c)) out.push(c);
    findAll(c, pred, out);
  }
  return out;
}
const find = (n, pred) => findAll(n, pred)[0] ?? null;
const kids = (n) => (isNode(n) ? n.c.filter(isNode) : []);
function closest(n, pred, maxUp = 12) {
  for (let x = n?.parent, i = 0; x && i < maxUp; x = x.parent, i++) if (pred(x)) return x;
  return null;
}
const hrefOf = (n) => (isNode(n) && typeof n.p.href === 'string' ? n.p.href : '');
const hrefId = (n, kind) => {
  const m = new RegExp('^/msclassic/' + kind + '/([0-9]+)(?:[?#].*)?$').exec(hrefOf(n));
  return m ? m[1] : null;
};
const num = (s) => {
  if (s == null) return null;
  const m = /-?\d[\d,]*(?:\.\d+)?/.exec(String(s));
  return m ? Number(m[0].replace(/,/g, '')) : null;
};
/** A labelled row: <div key=K><div><span>label</span><span>value</span></div>[<div>sub</div>]</div>. */
function rowParts(rowNode) {
  const inner = kids(rowNode)[0];
  if (!inner) return null;
  const spans = kids(inner).filter((x) => x.t === 'span');
  if (spans.length < 2) return null;
  const sub = kids(rowNode)[1];
  return { label: textOf(spans[0]), value: textOf(spans[1]), sub: sub ? textOf(sub) : null };
}

// ---------------------------------------------------------------------------------------------------------------
// /item-db/<id> parser
function parseItemPage(html, itemId) {
  const { body } = makeTree(html, itemId);
  const gid = /<!-- item:(\d+) gid:(\d+) -->/.exec(html);
  const h1 = find(body, (x) => x.t === 'h1');
  if (!h1) throw new Error('item ' + itemId + ': no h1');
  const card = h1.parent;
  const name = textOf(h1);

  // Header: "<type link> · <subtype link> · No. 0541"
  const header = kids(card).find((x) => x.t === 'div' && /No\. /.test(textOf(x)));
  let type = null, subtype = null, number = null;
  if (header) {
    for (const l of findAll(header, (x) => /^\/msclassic\/item-db\/[a-z]/.test(hrefOf(x)))) {
      if (/[?&]subtype=/.test(hrefOf(l))) subtype = textOf(l);
      else if (type == null) type = textOf(l);
    }
    const nm = /No\. (\d+)/.exec(textOf(header));
    number = nm ? nm[1] : null;
  }

  // Requirement block: <span>REQ LEV</span><span>17</span><span key=reqStr>...<span>20</span></span><span>JOB</span><span>Bowman</span>
  const req = {};
  const reqBlock = kids(card).find((x) => x.t === 'div' && kids(x).some((s) => s.t === 'span' && (textOf(s) === 'REQ LEV' || /^req[A-Z]/.test(s.k || '') || textOf(s) === 'JOB')));
  if (reqBlock) {
    const ks = kids(reqBlock);
    for (let i = 0; i < ks.length; i++) {
      const s = ks[i];
      const t = textOf(s);
      if (t === 'REQ LEV') req.level = num(textOf(ks[i + 1]));
      else if (t === 'JOB') req.job = textOf(ks[i + 1]);
      else if (/^req[A-Z]/.test(s.k || '')) req[s.k] = num(textOf(kids(s).at(-1)));
    }
  }

  // Stat rows (outside the weapon details box) and the weapon details box
  const details = find(card, (x) => x.t === 'details' && /^Weapon Details/.test(textOf(kids(x)[0] || '')));
  const inDetails = (x) => details && (x === details || closest(x, (a) => a === details, 40));
  const rows = [];
  for (const d of findAll(card, (x) => x.t === 'div' && typeof x.k === 'string' && !inDetails(x))) {
    const parts = rowParts(d);
    if (parts) rows.push({ key: d.k, ...parts });
  }
  const tags = findAll(card, (x) => x.t === 'span' && /rounded-full/.test(x.p.className || '')).map(textOf);

  let weapon = null;
  if (details) {
    const drows = [];
    for (const d of findAll(details, (x) => x.t === 'div' && typeof x.k === 'string')) {
      const parts = rowParts(d);
      if (parts) drows.push({ key: d.k, ...parts });
    }
    const multBox = find(details, (x) => x.t === 'div' && kids(x)[0]?.t === 'span' && textOf(kids(x)[0]) === 'Weapon Multipliers');
    const multKeys = new Set(multBox ? findAll(multBox, (x) => x.t === 'div' && typeof x.k === 'string').map((x) => x.k) : []);
    const multNote = multBox ? kids(multBox).slice(1).filter((x) => x.t === 'div' && !findAll(x, (y) => typeof y.k === 'string').length).map(textOf)[0] ?? null : null;
    // Attack cycle: either one value ("Attack cycle 720 ms" + "with Booster 600 ms") or one row per action kind
    // ("Swing 870ms · Booster 750ms", "Stab 810ms · Booster 720ms").
    const cycleSpan = find(details, (x) => x.t === 'span' && textOf(x) === 'Attack cycle');
    const cycleBox = cycleSpan ? cycleSpan.parent.parent : null;
    let cycleMs = null, cycleBoosterMs = null, cycleByKind = null, cycleNote = null;
    if (cycleSpan) {
      let valueNode = kids(cycleSpan.parent)[1];
      if (valueNode && valueNode.t === 'span') {
        cycleMs = num(textOf(valueNode));
        const booster = kids(cycleBox).find((x) => /^with Booster/.test(textOf(x)));
        cycleBoosterMs = booster ? num(textOf(booster)) : null;
        // e.g. wands: "magicians have no Attack Speed Booster in 1st or 2nd job"
        const other = kids(cycleBox).filter((x) => x !== cycleSpan.parent && x !== booster && !find(x, (y) => hrefOf(y)) && !hrefOf(x)).map(textOf).filter(Boolean);
        if (other.length) cycleNote = other.join(' ');
      } else {
        // per-kind layout: <div><span>Attack cycle</span></div><div>[<div><div><span>Swing</span><span>870ms · Booster 750ms</span>...]</div>
        const sib = kids(cycleBox);
        valueNode = sib[sib.indexOf(cycleSpan.parent) + 1];
        if (!valueNode) throw new Error('item ' + itemId + ': attack cycle value not found');
        cycleByKind = {};
        for (const sub of kids(valueNode)) {
          const sp = findAll(sub, (x) => x.t === 'span');
          if (sp.length < 2) continue;
          const m = /^(\d+)\s*ms(?:\s*·\s*Booster\s*(\d+)\s*ms)?$/.exec(textOf(sp[1]));
          if (!m) throw new Error('item ' + itemId + ': unparsed attack cycle row "' + textOf(sub) + '"');
          cycleByKind[textOf(sp[0]).toLowerCase()] = { ms: Number(m[1]), with_booster_ms: m[2] ? Number(m[2]) : null };
        }
      }
    }
    const attacksNode = find(details, (x) => Array.isArray(x.p.attacks));
    weapon = {
      rows: drows,
      multiplier_keys: [...multKeys],
      multiplier_note: multNote,
      attack_cycle_ms: cycleMs,
      attack_cycle_with_booster_ms: cycleBoosterMs,
      attack_cycle_by_kind: cycleByKind,
      attack_cycle_note: cycleNote,
      attacks: attacksNode ? attacksNode.p.attacks : null,
      weapon_name: attacksNode ? attacksNode.p.weaponName ?? null : null,
      swing_pct: attacksNode && typeof attacksNode.p.swingPct === 'number' ? attacksNode.p.swingPct : null,
      stab_pct: attacksNode && typeof attacksNode.p.stabPct === 'number' ? attacksNode.p.stabPct : null,
    };
  }

  // "Worn on" box sits next to the card; the base-stat component props are a cross-check for the stat rows.
  const baseStatsNode = find(body, (x) => isNode(x) && x.p && typeof x.p.baseStats === 'object' && x.p.baseStats !== null);
  const baseStats = baseStatsNode ? baseStatsNode.p.baseStats : null;

  // Description box: first text block after the watch-alerts anchor
  const watch = find(body, (x) => x.p.id === 'watch-alerts');
  let descriptionBlock = null;
  if (watch) {
    const after = kids(watch.parent)[kids(watch.parent).indexOf(watch) + 1];
    const first = after ? kids(after)[0] : null;
    if (first && first.t === 'div') descriptionBlock = rawText(first);
  }

  // Sections, located by their heading
  const h2s = findAll(body, (x) => x.t === 'h2');
  const heading = (re) => h2s.find((h) => re.test(textOf(h))) || null;
  const containerOf = (h, pred) => { for (let x = h?.parent, i = 0; x && i < 6; x = x.parent, i++) if (pred(x)) return x; return null; };

  // Where to buy
  const shops = [];
  const wtbH = heading(/^Where to buy$/);
  const wtb = wtbH ? closest(wtbH, (x) => x.t === 'section') : null;
  if (wtb) {
    for (const li of findAll(wtb, (x) => x.t === 'li')) {
      const npcLink = find(li, (x) => hrefId(x, 'npcs'));
      const mapLink = find(li, (x) => hrefId(x, 'maps'));
      const npcSpans = npcLink ? kids(npcLink.parent).filter((x) => x.t === 'span').map(textOf) : [];
      const townSpan = mapLink ? kids(mapLink.parent).find((x) => x.t === 'span') : null;
      const priceBox = kids(li).at(-1);
      const pk = kids(priceBox);
      const badge = pk.find((x) => x.t === 'span');
      if (pk[1] && textOf(pk[1]) !== 'mesos') throw new Error('item ' + itemId + ': shop price unit "' + textOf(pk[1]) + '"');
      if (badge && badge.p.title !== SHOP_PRICE_TITLE) throw new Error('item ' + itemId + ': unexpected price badge title "' + badge.p.title + '"');
      shops.push({
        npc_id: npcLink ? hrefId(npcLink, 'npcs') : null,
        npc_name: npcLink ? textOf(npcLink) : null,
        npc_role: npcSpans.find((s) => s !== 'cheapest') ?? null,
        map_id: mapLink ? hrefId(mapLink, 'maps') : null,
        map_name: mapLink ? textOf(mapLink) : null,
        town: townSpan ? textOf(townSpan).replace(/^·\s*/, '') : null,
        price_mesos: num(textOf(pk[0])),
        cheapest: npcSpans.includes('cheapest'),
        price_label: badge ? textOf(badge) : null,
      });
    }
  }

  // MSEA Reference Drops
  const msea = [];
  let mseaNote = null;
  const mseaH = heading(/^MSEA Reference Drops$/);
  const mseaBox = mseaH ? containerOf(mseaH, (x) => !!find(x, (y) => hrefId(y, 'monsters'))) : null;
  if (mseaBox) {
    const p = find(mseaBox, (x) => x.t === 'p');
    mseaNote = p ? textOf(p) : null;
    for (const a of findAll(mseaBox, (x) => hrefId(x, 'monsters'))) {
      const nameSpan = find(a, (x) => x.t === 'span');
      const t = textOf(a);
      const lv = /Lv (\d+)\s*$/.exec(t);
      msea.push({ monster_id: hrefId(a, 'monsters'), monster_name: nameSpan ? textOf(nameSpan) : null, monster_level: lv ? Number(lv[1]) : null });
    }
  }

  // Quest Reward: rows keyed "<questId>-<c|a>--<n>" (c = on completion, a = on accept); optional "(50%)" / "on accept"
  const questRewards = [];
  const qrH = heading(/^Quest Reward$/);
  const qrBox = qrH ? containerOf(qrH, (x) => !!find(x, (y) => hrefId(y, 'quest-tracker'))) : null;
  if (qrBox) {
    for (const d of findAll(qrBox, (x) => typeof x.k === 'string' && /^\d+-[a-z]+--\d+$/.test(x.k))) {
      const [, qid, kind] = /^(\d+)-([a-z]+)--/.exec(d.k);
      const link = find(d, (x) => hrefId(x, 'quest-tracker'));
      const extra = kids(d).filter((x) => x.t === 'span').map(textOf);
      const pct = extra.map((s) => /^\((\d+(?:\.\d+)?)%\)$/.exec(s)).find(Boolean);
      questRewards.push({
        quest_id: link ? hrefId(link, 'quest-tracker') : qid,
        quest_name: link ? textOf(link) : null,
        when: kind === 'a' ? 'on_accept' : kind === 'c' ? 'on_completion' : kind,
        chance_pct: pct ? Number(pct[1]) : null,
        label: extra.length ? extra.join(' ') : null,
        row_key: d.k,
      });
    }
  }

  // Needed By: quests table (#required-for-quests) and recipes table (#used-in-recipes)
  const neededQuests = [];
  const neededRecipes = [];
  const nbQ = find(body, (x) => x.p.id === 'required-for-quests');
  if (nbQ) {
    for (const tr of findAll(nbQ, (x) => x.t === 'tr' && x.k != null)) {
      const tds = kids(tr).filter((x) => x.t === 'td');
      const link = find(tds[0], (x) => hrefId(x, 'quest-tracker'));
      const giver = kids(tds[0]).find((x) => x.t === 'div');
      neededQuests.push({
        quest_id: link ? hrefId(link, 'quest-tracker') : tr.k,
        quest_name: link ? textOf(link) : null,
        quest_npc_name: giver ? textOf(giver) : null,
        quest_level: num(textOf(tds[1])),
        quantity: num(textOf(tds[2])),
      });
    }
  }
  const nbR = find(body, (x) => x.p.id === 'used-in-recipes');
  if (nbR) {
    for (const tr of findAll(nbR, (x) => x.t === 'tr' && x.k != null)) {
      const tds = kids(tr).filter((x) => x.t === 'td');
      const link = find(tds[0], (x) => hrefId(x, 'item-db'));
      neededRecipes.push({
        makes_item_id: link ? hrefId(link, 'item-db') : null,
        makes_item_name: link ? textOf(link) : textOf(tds[0]),
        skill: textOf(tds[1]),
        quantity: num(textOf(tds[2])),
      });
    }
  }
  const nbSection = find(body, (x) => x.p.id === 'needed-by');
  const nbNote = nbSection ? (find(nbSection, (x) => x.t === 'p') ? textOf(find(nbSection, (x) => x.t === 'p')) : null) : null;

  // Found in Breakables
  const breakables = [];
  const brH = heading(/^Found in Breakables$/);
  const brBox = brH ? containerOf(brH, (x) => !!find(x, (y) => /^\/msclassic\/breakables\/\d+$/.test(hrefOf(y)))) : null;
  if (brBox) {
    for (const a of findAll(brBox, (x) => /^\/msclassic\/breakables\/\d+$/.test(hrefOf(x)))) {
      // <a><img/><div><div>Wooden Box</div><div>0000001</div></div><div><span>▲ 2</span></div></a>
      const divs = kids(a).filter((x) => x.t === 'div');
      const parts = kids(divs[0]).map(textOf);
      const scoreText = divs[1] ? textOf(divs[1]) : '';
      if (!/^▲\s*-?\d+$/.test(scoreText) || parts[1] !== hrefOf(a).split('/').pop()) throw new Error('item ' + itemId + ': unparsed breakable row "' + textOf(a) + '"');
      breakables.push({ breakable_id: hrefOf(a).split('/').pop(), name: parts[0] ?? null, score: num(scoreText) });
    }
  }

  // Craftable recipes (keyed "<Discipline>-<n>-<i>")
  const recipes = [];
  const crH = heading(/^Craftable/);
  const crBox = crH ? containerOf(crH, (x) => !!find(x, (y) => typeof y.k === 'string' && /^[A-Za-z]+-\d+-\d+$/.test(y.k))) : null;
  if (crBox) {
    for (const rd of findAll(crBox, (x) => typeof x.k === 'string' && /^[A-Za-z]+-\d+-\d+$/.test(x.k) && x.t === 'div')) {
      const [top, info, ingr] = kids(rd);
      const topSpans = kids(top).filter((x) => x.t === 'span').map(textOf);
      const discipline = textOf(find(top, (x) => hrefOf(x) === '/msclassic/crafting') || '');
      const info2 = {};
      for (const d of kids(info)) {
        const sp = kids(d).filter((x) => x.t === 'span');
        if (sp.length >= 2) info2[textOf(sp[0])] = textOf(sp[1]);
      }
      const ingredients = [];
      const ingrList = kids(ingr)[1];
      for (const it of kids(ingrList)) {
        const link = find(it, (x) => hrefId(x, 'item-db'));
        const spans = findAll(it, (x) => x.t === 'span').map(textOf);
        const qty = spans.map((s) => /^×(\d+)$/.exec(s)).find(Boolean);
        ingredients.push({
          item_id: link ? hrefId(link, 'item-db') : null,
          name: link ? textOf(link) : null,
          quantity: qty ? Number(qty[1]) : null,
          optional: spans.includes('Optional'),
        });
      }
      const produces = topSpans.map((s) => /^Produces ×(\d+)$/.exec(s)).find(Boolean);
      recipes.push({
        recipe_key: rd.k,
        discipline,
        category: topSpans.find((s) => !/^Produces/.test(s)) ?? null,
        produces_quantity: produces ? Number(produces[1]) : null,
        required_craft_level: num(info2['Req. Level']),
        craft_exp: num(info2['Craft EXP']),
        meso_cost: num(info2['Meso Cost']),
        ingredients,
      });
    }
  }

  // Change history
  let change = null;
  const chH = heading(/^Change history$/);
  const chBox = chH ? closest(chH, (x) => x.t === 'details') : null;
  if (chBox) {
    const rowsCH = [];
    for (const tr of findAll(chBox, (x) => x.t === 'tr' && x.k != null)) {
      const cells = kids(tr).map(textOf);
      rowsCH.push({ key: tr.k, stat: cells[0] ?? null, cot1: cells[1] ?? null, cot2: cells[2] ?? null, change: cells[3] ?? null });
    }
    const notes = findAll(chBox, (x) => x.t === 'li').map(textOf);
    const text = {};
    for (const dl of findAll(chBox, (x) => x.t === 'dl')) {
      for (const d of kids(dl)) {
        const dt = find(d, (x) => x.t === 'dt');
        const dd = find(d, (x) => x.t === 'dd');
        if (dt && dd) text[textOf(dt).toLowerCase()] = rawText(dd);
      }
    }
    const badge = kids(kids(chH.parent.parent)[0] ? chH.parent : chH.parent).find((x) => x.t === 'span' && x !== chH);
    change = { updated_label: badge ? textOf(badge) : null, rows: rowsCH, notes, in_game_text: Object.keys(text).length ? text : null };
  }

  const headings = h2s.map(textOf);
  return {
    name, type, subtype, number, game_item_id: gid ? gid[2] : null, gid_item: gid ? gid[1] : null,
    req, rows, tags, weapon, baseStats, descriptionBlock,
    shops, msea, mseaNote, questRewards, neededQuests, neededRecipes, nbNote, breakables, recipes, change, headings,
  };
}

// ---------------------------------------------------------------------------------------------------------------
// Mapping tables (documented in docs/canonical/items.md)

// Page stat-row keys (= item API stats keys) -> output stat keys.
const STAT_KEYS = {
  watk: 'watk', matk: 'matk', wdef: 'wdef', mdef: 'mdef',
  str: 'str', dex: 'dex', int: 'int', luk: 'luk',
  hp: 'hp', mp: 'mp', acc: 'acc', avoid: 'avoid', speed: 'speed', jump: 'jump',
  knockback: 'knockback_pct', critRate: 'crit_rate_pct',
};
// Derived (not a MeowDB field): inventory tab from MeowDB "type".
const TAB_BY_TYPE = { Equip: 'equip', Use: 'use', Setup: 'setup', Etc: 'etc', Cash: 'cash', 'Cash Equip': 'cash' };
// Derived (not a MeowDB field): equipment slot from MeowDB "subtype".
const WEAPON_SUBTYPES = new Set([
  'One-Handed Sword', 'One-Handed Axe', 'One-Handed Blunt Weapon', 'Two-Handed Sword', 'Two-Handed Axe',
  'Two-Handed Blunt Weapon', 'Dagger', 'Spear', 'Polearm', 'Bow', 'Crossbow', 'Wand', 'Staff', 'Claw',
]);
const SLOT_BY_SUBTYPE = {
  Hat: 'hat', Top: 'top', Bottom: 'bottom', Overall: 'overall', Shoes: 'shoes', Gloves: 'gloves', Cape: 'cape',
  Shield: 'shield', Earring: 'earrings', Earrings: 'earrings',
};
const GENDER_BY_TAG = { 'Male + Female': 'any', 'Male only': 'male', 'Female only': 'female' };
const KNOWN_TAGS = new Set(['Tradeable', 'Untradeable', 'Male + Female', 'Male only', 'Female only']);
// Section headings: parsed ones, plus navigation/community widgets that are deliberately not exported.
const KNOWN_HEADINGS = [
  /^Where to buy$/, /^MSEA Reference Drops$/, /^Quest Reward$/, /^Needed By$/, /^Found in Breakables$/, /^Craftable/,
  /^Change history$/,
  /^Similar .* items$/, /^Compare .* items$/, // navigation lists of other items
  /^Sitting preview$/, // chair avatar preview (art)
];
const ROW_LABEL_KEYS = new Set([
  'Upgrade Slots', 'Attack Speed', 'NPC Sell-back', 'NPC Sell-back (per unit)', 'Max per Stack', 'Recharge Cost',
  'Required Level', 'Required Ammunition',
]);
const CONSUMABLE_KEYS = { hpRecover: 'hp_restore', mpRecover: 'mp_restore', fullness: 'pet_fullness_restore' };

// ---------------------------------------------------------------------------------------------------------------
async function monsterNames(firstItemHtml) {
  // The item page's client chunks (listed in its flight payload) include the bundled monster list; pick the chunk that
  // exports it instead of hard-coding a content hash.
  const chunks = [...new Set([...firstItemHtml.matchAll(/static\/chunks\/(\d+-[0-9a-f]+\.js)/g)].map((m) => m[1]))];
  const ordered = chunks.filter((c) => c.startsWith('782-')).concat(chunks.filter((c) => !c.startsWith('782-')));
  for (const c of ordered) {
    const r = await get('https://meowdb.com/_next/static/chunks/' + c);
    if (!r.text.includes(MONSTER_LIST_MARKER)) continue;
    const map = new Map();
    for (const m of r.text.matchAll(/\{id:(\d+),name:"((?:[^"\\]|\\.)*)",level:(\d+),/g)) {
      if (!map.has(m[1])) map.set(m[1], { name: JSON.parse('"' + m[2] + '"'), level: Number(m[3]) });
    }
    return { map, extra: new Map(), ref: at(r) };
  }
  throw new Error('monster list chunk not found');
}

/** /monsters/<id>: name and level from the page's schema.org JSON-LD block. */
function monsterFromPage(html, id) {
  const r = rsc(html);
  const i = r.indexOf('{"@context":"https://schema.org","@type":"Thing","@id":"https://meowdb.com/msclassic/monsters/' + id + '"');
  if (i < 0) throw new Error('monster ' + id + ': JSON-LD not found');
  const ld = jsonAt(r, i).value;
  const lv = (ld.additionalProperty || []).find((p) => p.name === 'Level');
  return { name: ld.name ?? null, level: lv ? lv.value : null };
}

/**
 * /quest-tracker/<id>: the quest's random-reward pools ("rewardRandom": [{jobName, items: [{name, count, itemId (game id),
 * chance}], totalWeight}]) and its itemRefs table (name -> {id: MeowDB item id, iconKey}).
 */
function questRandomPools(html, questId) {
  const r = rsc(html);
  const needle = '"quest":{"id":"' + questId + '"';
  const i = r.indexOf(needle);
  if (i < 0) throw new Error('quest ' + questId + ': quest object not found on the quest page');
  const quest = jsonAt(r, i + '"quest":'.length).value;
  const ri = r.indexOf('"itemRefs":');
  const itemRefs = ri >= 0 ? jsonAt(r, ri + '"itemRefs":'.length).value : {};
  return { pools: Array.isArray(quest.rewardRandom) ? quest.rewardRandom : [], itemRefs };
}

function starterWeaponsFromGuide(html) {
  const t = pageText(html).replace(/\s+/g, ' ');
  const s1 = /Choose the Wooden Club at character creation\. It has 19 W\.ATK ?; the Sword and Hand Axe have 17\./.exec(t);
  return { creation: s1 ? s1[0].replace(' ;', ';') : null };
}

// ---------------------------------------------------------------------------------------------------------------
function buildItem(id, page, pageRes, api, apiRes, drops, dropsRes, monsters, starter, questPages) {
  const gaps = [];
  const discrepancies = [];
  const notes = [];
  const fieldSources = {};
  const apiRef = at(apiRes);
  const useApi = (field) => { fieldSources[field] = apiRef; };
  const s = api.stats || {};

  if (page.name !== api.name) discrepancies.push({ field: 'name', item_page: page.name, item_api: api.name, chosen: page.name, reason: 'item page heading is the primary source' });
  if (page.type !== api.type) discrepancies.push({ field: 'type', item_page: page.type, item_api: api.type, chosen: page.type, reason: 'item page is the primary source' });
  if ((page.subtype ?? null) !== (api.subtype ?? null)) discrepancies.push({ field: 'subtype', item_page: page.subtype, item_api: api.subtype, chosen: page.subtype, reason: 'item page is the primary source' });
  if (page.game_item_id && api.iconKey && page.game_item_id !== api.iconKey) discrepancies.push({ field: 'game_item_id', item_page: page.game_item_id, item_api_icon_key: api.iconKey, chosen: page.game_item_id, reason: 'page comment "gid" is the item\'s game id; iconKey is only the icon' });
  if (page.number && Number(page.number) !== Number(id)) discrepancies.push({ field: 'id', item_page_number: page.number, url_id: id, chosen: id, reason: 'MeowDB url id' });

  // In-game description: the item API text; cross-checked with the page's description box (non-equipment pages show
  // the in-game text there; equipment pages show a MeowDB-written summary instead) and the "In-game text" COT2 entry.
  const norm = (t) => (t ?? '').replace(/\s+/g, ' ').trim();
  if (page.type !== 'Equip' && page.descriptionBlock != null) CHECKS.description_vs_page++;
  if (page.change?.in_game_text?.cot2 != null) CHECKS.description_vs_cot2_text++;
  if (page.type !== 'Equip' && page.descriptionBlock != null && norm(page.descriptionBlock) !== norm(api.description)) {
    discrepancies.push({ field: 'description', item_page: page.descriptionBlock, item_api: api.description, chosen: api.description, reason: 'item API description is the in-game text field' });
  }
  const cot2Text = page.change?.in_game_text?.cot2;
  if (cot2Text != null && norm(cot2Text) !== norm(api.description)) {
    discrepancies.push({ field: 'description', item_page_change_history_cot2: cot2Text, item_api: api.description, chosen: api.description, reason: 'item API description is the in-game text field' });
  }

  const type = page.type ?? api.type;
  const subtype = page.subtype ?? api.subtype ?? null;
  const rowByKey = new Map(page.rows.map((r) => [r.key, r]));
  // Strict: every card row, tag and section heading must be one this extractor understands (or knowingly skips).
  for (const r of page.rows) {
    if (!STAT_KEYS[r.key] && !ROW_LABEL_KEYS.has(r.key) && !CONSUMABLE_KEYS[r.key] && r.key !== 'hpRecoverBonus') throw new Error('item ' + id + ': unhandled stat row "' + r.key + '" (' + r.label + ': ' + r.value + ')');
  }
  for (const t of page.tags) if (!KNOWN_TAGS.has(t)) throw new Error('item ' + id + ': unhandled tag "' + t + '"');
  for (const h of page.headings) if (!KNOWN_HEADINGS.some((re) => re.test(h))) throw new Error('item ' + id + ': unhandled section "' + h + '"');
  if (page.weapon) {
    const known = new Set([...page.weapon.multiplier_keys, 'Avg horizontal reach', 'Avg vertical reach', 'Arrow range']);
    for (const r of page.weapon.rows) if (!known.has(r.key)) throw new Error('item ' + id + ': unhandled weapon row "' + r.key + '"');
  }

  // --- requirements -------------------------------------------------------------------------------------------
  const pageLevel = page.req.level ?? num(rowByKey.get('Required Level')?.value);
  const level = api.levelReq ?? pageLevel ?? null;
  if (pageLevel != null && api.levelReq != null && pageLevel !== api.levelReq) discrepancies.push({ field: 'requirements.level', item_page: pageLevel, item_api: api.levelReq, chosen: api.levelReq, reason: 'API levelReq is the structured value' });
  if (pageLevel == null && api.levelReq) gaps.push('requirements.level: the item page shows no level row; value from the item API');
  const jobRaw = page.req.job ?? s.reqJob ?? api.reqJob ?? null;
  const apiJob = s.reqJob ?? api.reqJob ?? null;
  if (page.req.job != null && apiJob != null && page.req.job !== apiJob) discrepancies.push({ field: 'requirements.job', item_page: page.req.job, item_api: apiJob, chosen: page.req.job, reason: 'item page is the primary source' });
  const reqStat = (k, apiK) => {
    const p = page.req[k] ?? null;
    const a = s[apiK] ?? null;
    if (p != null && a != null && p !== a) discrepancies.push({ field: 'requirements.' + apiK, item_page: p, item_api: a, chosen: p, reason: 'item page is the primary source' });
    return p ?? a ?? 0;
  };
  const requirements = {
    level,
    job: jobRaw ? jobRaw.split('/').map((x) => x.trim()) : null,
    job_raw: jobRaw,
    str: reqStat('reqStr', 'reqStr'),
    dex: reqStat('reqDex', 'reqDex'),
    int: reqStat('reqInt', 'reqInt'),
    luk: reqStat('reqLuk', 'reqLuk'),
    fame: reqStat('reqFame', 'reqFame'),
  };

  // --- stats (equipment bonuses) --------------------------------------------------------------------------------
  const isScroll = subtype === 'Scroll';
  const stats = {};
  const pageStatKeys = page.rows.filter((r) => STAT_KEYS[r.key]).map((r) => r.key);
  for (const k of Object.keys(STAT_KEYS)) {
    const r = rowByKey.get(k);
    const pv = r ? num(r.value) : null;
    const av = s[k] ?? null;
    if (pv != null && av != null) CHECKS.stat_rows_vs_api++;
    if (pv != null && av != null && pv !== av) discrepancies.push({ field: 'stats.' + STAT_KEYS[k], item_page: pv, item_api: av, chosen: pv, reason: 'item page is the primary source' });
    if (pv == null && av != null && !isScroll) { stats[STAT_KEYS[k]] = av; useApi('stats.' + STAT_KEYS[k]); }
    else if (pv != null && !isScroll) stats[STAT_KEYS[k]] = pv;
  }
  if (page.baseStats) {
    for (const [k, v] of Object.entries(page.baseStats)) {
      const out = STAT_KEYS[k];
      CHECKS.base_stats_vs_rows++;
      if (out && stats[out] !== v) discrepancies.push({ field: 'stats.' + out, item_page_row: stats[out] ?? null, item_page_base_stats: v, chosen: stats[out] ?? null, reason: 'stat row is the displayed value' });
    }
  }
  const slotsRow = rowByKey.get('Upgrade Slots');
  if (slotsRow || s.slots != null) {
    const pv = slotsRow ? num(slotsRow.value) : null;
    if (pv != null && s.slots != null && pv !== s.slots) discrepancies.push({ field: 'stats.upgrade_slots', item_page: pv, item_api: s.slots, chosen: pv, reason: 'item page is the primary source' });
    stats.upgrade_slots = pv ?? s.slots;
    if (pv == null) useApi('stats.upgrade_slots');
  }

  // --- weapon --------------------------------------------------------------------------------------------------
  let weapon = null;
  const isWeapon = WEAPON_SUBTYPES.has(subtype);
  if (isWeapon || page.weapon || s.attackSpeed != null) {
    const asRow = rowByKey.get('Attack Speed');
    const asm = asRow ? /^(.*?)\s*\((\d+)\)$/.exec(asRow.value) : null;
    const speed = asm ? Number(asm[2]) : s.attackSpeed ?? null;
    const speedName = asm ? asm[1] : s.attackSpeedName ?? null;
    if (asm && s.attackSpeed != null && (Number(asm[2]) !== s.attackSpeed || asm[1] !== s.attackSpeedName)) discrepancies.push({ field: 'weapon.attack_speed', item_page: asRow.value, item_api: s.attackSpeed + ' ' + s.attackSpeedName, chosen: asRow.value, reason: 'item page is the primary source' });
    const w = page.weapon || { rows: [], multiplier_keys: [] };
    const multipliers = {};
    for (const k of w.multiplier_keys) {
      const r = w.rows.find((x) => x.key === k);
      if (r) multipliers[k.toLowerCase().replace(/[^a-z0-9]+/g, '_')] = num(r.value);
    }
    const rowOf = (k) => w.rows.find((x) => x.key === k) || null;
    const range = (t) => { const m = /(\d+)\s*-\s*(\d+)/.exec(t || ''); return m ? [Number(m[1]), Number(m[2])] : null; };
    // "73-102 px by attack", or "Same for every normal attack" (one basic attack, e.g. wands) -> [avg, avg]
    const rangeOrSame = (r) => {
      const v = range(r.sub);
      if (v) return v;
      if (r.sub === 'Same for every normal attack') return [num(r.value), num(r.value)];
      throw new Error('item ' + id + ': unparsed reach row "' + r.key + ': ' + r.value + ' / ' + r.sub + '"');
    };
    const hr = rowOf('Avg horizontal reach');
    const vr = rowOf('Avg vertical reach');
    const ar = rowOf('Arrow range');
    const ammoRow = rowByKey.get('Required Ammunition');
    weapon = {
      weapon_type: subtype,
      attack_speed: speed,
      attack_speed_name: speedName,
      multipliers: Object.keys(multipliers).length ? multipliers : null,
      multipliers_note: w.multiplier_note ?? null,
      attack_cycle_ms: w.attack_cycle_ms ?? null,
      attack_cycle_with_booster_ms: w.attack_cycle_with_booster_ms ?? null,
      attack_cycle_by_kind_ms: w.attack_cycle_by_kind ?? null,
      attack_cycle_note: w.attack_cycle_note ?? null,
      basic_attack_mix_pct: w.swing_pct != null || w.stab_pct != null ? { swing: w.swing_pct, stab: w.stab_pct } : null,
      reach: hr || vr ? {
        avg_horizontal_px: hr ? num(hr.value) : null,
        horizontal_range_px: hr ? rangeOrSame(hr) : null,
        avg_vertical_px: vr ? num(vr.value) : null,
        vertical_range_px: vr ? rangeOrSame(vr) : null,
      } : null,
      arrow_range_px: ar ? range(ar.value) : null,
      arrow_range_note: ar ? ar.sub : null,
      required_ammunition: ammoRow ? ammoRow.value : null,
      required_ammunition_item_id: null, // filled in main() by exact name match within the extracted set
      basic_attacks: w.attacks ? w.attacks.map((a) => ({
        action: a.action, label: a.label, kind: a.kind, near_px: a.near, far_px: a.far, top_px: a.top, box_px: a.box,
        in_average: a.averaged,
      })) : null,
    };
    if (isWeapon && !w.attacks) gaps.push('weapon.basic_attacks: the item page has no attack hitbox data for this weapon');
    if (isWeapon && w.attack_cycle_ms == null && !w.attack_cycle_by_kind) gaps.push('weapon.attack_cycle_ms: not shown on the item page');
  }

  // --- consumable / scroll / setup ------------------------------------------------------------------------------
  let consumable = null;
  for (const [k, out] of Object.entries(CONSUMABLE_KEYS)) {
    const r = rowByKey.get(k);
    const pv = r ? num(r.value) : null;
    const av = s[k] ?? null;
    if (pv != null && av != null && pv !== av) discrepancies.push({ field: 'consumable.' + out, item_page: pv, item_api: av, chosen: pv, reason: 'item page is the primary source' });
    if (pv != null || av != null) {
      consumable = consumable || {};
      consumable[out] = pv ?? av;
      if (pv == null) useApi('consumable.' + out);
    }
  }
  let scroll = null;
  if (isScroll || s.successRate != null) {
    const bonus = {};
    for (const k of Object.keys(STAT_KEYS)) {
      const r = rowByKey.get(k);
      const pv = r ? num(r.value) : null;
      const av = s[k] ?? null;
      if (pv != null || av != null) bonus[STAT_KEYS[k]] = pv ?? av;
    }
    scroll = {
      target_equipment: s.target ?? null,
      stat_type: s.statType ?? null,
      grade: s.grade ?? null,
      success_rate_pct: s.successRate ?? null,
      stat_bonus_on_success: bonus,
    };
    useApi('scroll');
    notes.push('Scroll: stat_bonus_on_success is added to the target equipment when the scroll succeeds; it is not a stat of the scroll itself.');
  }
  let setup = null;
  if (s.hpRecoverBonus != null || rowByKey.has('hpRecoverBonus')) {
    const r = rowByKey.get('hpRecoverBonus');
    const pv = r ? num(r.value) : null;
    if (pv != null && s.hpRecoverBonus != null && pv !== s.hpRecoverBonus) discrepancies.push({ field: 'setup.hp_recovery_bonus', item_page: pv, item_api: s.hpRecoverBonus, chosen: pv, reason: 'item page is the primary source' });
    const iv = /every (\d+) seconds/.exec(api.description || '');
    setup = { hp_recovery_bonus: pv ?? s.hpRecoverBonus, interval_s: iv ? Number(iv[1]) : null };
    if (iv) fieldSources['setup.interval_s'] = { ...apiRef, from: 'description text "every ' + iv[1] + ' seconds"' };
    else gaps.push('setup.interval_s: no recovery interval in MeowDB text');
  }

  // --- economy & flags ------------------------------------------------------------------------------------------
  const sellRow = rowByKey.get('NPC Sell-back (per unit)') || rowByKey.get('NPC Sell-back');
  let sellPrice = null, sellBasis = null, sellSource = null;
  if (sellRow) {
    sellPrice = num(sellRow.value);
    sellBasis = sellRow.key === 'NPC Sell-back (per unit)' ? 'per_unit' : 'per_item';
    sellSource = 'item_page';
    if (s.price != null && s.price !== sellPrice) discrepancies.push({ field: 'sell_price_mesos', item_page: sellPrice, item_api: s.price, chosen: sellPrice, reason: 'item page is the primary source' });
  } else if (s.price != null) {
    sellPrice = s.price;
    sellBasis = rowByKey.has('Max per Stack') || s.slotMax != null ? 'per_unit' : 'per_item';
    sellSource = 'item_api';
    useApi('sell_price_mesos');
    if (s.price === 0) notes.push('Sell-back 0: the item page shows no "NPC Sell-back" row and the item API records stats.price = 0.');
  } else gaps.push('sell_price_mesos: neither the item page nor the item API gives an NPC sell-back value');

  const stackRow = rowByKey.get('Max per Stack');
  let maxStack = stackRow ? num(stackRow.value) : null;
  if (stackRow && s.slotMax != null && s.slotMax !== maxStack) discrepancies.push({ field: 'max_stack', item_page: maxStack, item_api: s.slotMax, chosen: maxStack, reason: 'item page is the primary source' });
  if (maxStack == null && s.slotMax != null) { maxStack = s.slotMax; useApi('max_stack'); }
  if (maxStack == null) gaps.push(type === 'Equip' ? 'max_stack: MeowDB gives no stack size for equipment' : 'max_stack: MeowDB gives no stack size for this item');

  const tradeTag = page.tags.find((t) => t === 'Tradeable' || t === 'Untradeable') ?? null;
  const tradeable = tradeTag === 'Tradeable' ? true : tradeTag === 'Untradeable' ? false : (s.untradeable ? false : null);
  if (tradeTag == null) gaps.push('tradeable: the item page shows no Tradeable/Untradeable tag');
  if (tradeTag === 'Tradeable' && s.untradeable === true) discrepancies.push({ field: 'tradeable', item_page: 'Tradeable', item_api: 'untradeable: true', chosen: true, reason: 'item page is the primary source' });
  if (tradeTag === 'Untradeable' && s.untradeable !== true) notes.push('Untradeable comes from the item page tag; the item API omits the untradeable flag for this item.');
  const genderTag = page.tags.find((t) => GENDER_BY_TAG[t]) ?? null;
  const gender = genderTag ? GENDER_BY_TAG[genderTag] : null;
  if (type === 'Equip' && !genderTag) gaps.push('gender: no gender tag on the item page');

  const rechargeRow = rowByKey.get('Recharge Cost');

  // --- sources -------------------------------------------------------------------------------------------------
  const prices = page.shops.map((x) => x.price_mesos).filter((x) => x != null);
  const community = drops.drops.map((d) => {
    const mid = String(d.monsterId);
    const m = monsters.map.get(mid) || monsters.extra.get(mid) || null;
    if (!monsters.map.has(mid) && m) {
      fieldSources['sources.monster_drops[monster_id=' + mid + ']'] = { url: m.url, retrieved_at: m.retrieved_at, from: 'monster page JSON-LD (name, Level)' };
      notes.push('Community drop from monster ' + mid + ' (' + m.name + '): the item page hides it because the monster is missing from the monster list bundled with the page; name and level come from /monsters/' + mid + '.');
    }
    return {
      monster_id: mid,
      monster_name: m ? m.name : null,
      monster_level: m ? m.level : null,
      upvotes: d.upvotes, downvotes: d.downvotes, score: d.score,
      disputed: d.score <= 0, // MeowDB dims rows with score <= 0 on the item page
      community_drop_entry_id: String(d.id),
      shown_on_item_page: monsters.map.has(mid),
    };
  });
  for (const c of community) if (c.monster_name == null) gaps.push('sources.monster_drops: monster ' + c.monster_id + ' has no name in MeowDB');
  // Cross-check: the API hover preview lists up to three drop and shop names.
  const pd = api.previewSources?.drops || [];
  const names = new Set(community.map((c) => c.monster_name));
  for (const n of pd) if (!names.has(n)) discrepancies.push({ field: 'sources.monster_drops', item_api_preview_drop: n, note: 'name in the item API preview is not in the community drop list', chosen: 'community drop list (/api/drops)' });
  const ps = api.previewSources?.shops || [];
  const shopNames = new Set(page.shops.map((x) => x.npc_name));
  for (const n of ps) if (!shopNames.has(n)) discrepancies.push({ field: 'sources.shops', item_api_preview_shop: n, note: 'shop in the item API preview is not in the item page "Where to buy" list', chosen: 'item page list' });

  // Random quest-reward shares: the item page shows "(14%)", rounded to a whole percent. The quest page's rewardRandom
  // pool has the same share to one decimal (14.3) and the pool's totalWeight (7), so it is the more precise value.
  const gameId = page.game_item_id ?? api.iconKey ?? null;
  for (const q of page.questRewards) {
    if (q.chance_pct == null) continue;
    const qp = questPages.get(q.quest_id);
    const field = 'sources.quest_rewards[quest_id=' + q.quest_id + '].chance_pct';
    const hits = [];
    for (const pool of qp.pools) for (const it of pool.items || []) if (String(it.itemId) === gameId) hits.push({ ...it, totalWeight: pool.totalWeight, jobName: pool.jobName });
    const refOk = hits.every((h) => !qp.itemRefs[h.name] || String(qp.itemRefs[h.name].id) === id);
    const chances = [...new Set(hits.map((h) => h.chance))];
    if (!hits.length || !refOk || chances.length !== 1) {
      gaps.push(field + ': the quest page has no single random-reward share for this item (' + (hits.length ? (refOk ? 'several shares' : 'itemRefs id mismatch') : 'not in rewardRandom') + '); the item page\'s rounded value is kept');
      continue;
    }
    CHECKS.quest_reward_chance_vs_quest_page++;
    const h = hits[0];
    if (h.chance !== q.chance_pct) {
      discrepancies.push({
        field, item_page: q.chance_pct, quest_page: h.chance, quest_page_total_weight: h.totalWeight, chosen: h.chance,
        reason: 'same share: the item page rounds it to a whole percent; the quest page\'s structured rewardRandom pool gives it to one decimal (pool totalWeight ' + h.totalWeight + ')',
      });
      q.chance_pct = h.chance;
      fieldSources[field] = { ...qp.ref, from: 'rewardRandom chance (pool "' + h.jobName + '", totalWeight ' + h.totalWeight + ')' };
    }
  }

  const out = {
    id,
    name: page.name,
    game_item_id: page.game_item_id ?? api.iconKey ?? null,
    type,
    subtype,
    inventory_tab: TAB_BY_TYPE[type] ?? null,
    equip_slot: type === 'Equip' ? (isWeapon ? 'weapon' : SLOT_BY_SUBTYPE[subtype] ?? null) : null,
    quest_item: subtype === 'Quest Item',
    description: api.description ?? null,
    requirements,
    stats,
    weapon,
    consumable,
    scroll,
    setup,
    npc_buy_price_mesos: prices.length ? Math.min(...prices) : null,
    sell_price_mesos: sellPrice,
    sell_price_basis: sellBasis,
    sell_price_source: sellSource,
    recharge_cost_mesos_per_unit: rechargeRow ? num(rechargeRow.value) : s.unitPrice ?? null,
    max_stack: maxStack,
    tradeable,
    gender,
    sources: {
      shops: page.shops,
      monster_drops: community,
      msea_reference_drops: page.msea,
      msea_reference_note: page.mseaNote,
      quest_rewards: page.questRewards,
      breakables: page.breakables,
      crafting_recipes: page.recipes,
    },
    used_in: { quests: page.neededQuests, recipes: page.neededRecipes },
    change_history: page.change,
    derived_fields: ['inventory_tab', 'equip_slot', 'quest_item', 'npc_buy_price_mesos', 'requirements.job', 'sources.monster_drops[].disputed'],
    source: source(pageRes.url, pageRes.retrieved_at),
    field_sources: {},
  };
  if (type === 'Equip' && out.equip_slot == null) gaps.push('equip_slot: subtype "' + subtype + '" has no slot mapping');
  if (!page.game_item_id) { fieldSources.game_item_id = { ...apiRef, from: 'iconKey' }; }
  fieldSources.description = apiRef;
  fieldSources['sources.monster_drops'] = at(dropsRes);
  fieldSources['sources.monster_drops[].monster_name'] = { ...monsters.ref, from: 'monster list bundled with the item page (export IW)' };
  if (api.levelReq != null) fieldSources['requirements.level'] = apiRef;
  if (page.req.job == null && apiJob != null) fieldSources['requirements.job'] = apiRef;

  if (starter && starter.ids.includes(id)) {
    notes.push('Beginner starting equipment: the Beginner\'s guide names this as one of the three character-creation weapons: "' + starter.creation + '"');
    fieldSources.notes = starter.ref;
    out.beginner_creation_weapon = true;
  }

  // Order field_sources deterministically
  out.field_sources = Object.fromEntries(Object.entries(fieldSources).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)));
  if (!Object.keys(out.field_sources).length) delete out.field_sources;
  if (notes.length) out.notes = notes;
  if (gaps.length) out.gaps = gaps;
  if (discrepancies.length) out.discrepancies = discrepancies;
  return out;
}

// ---------------------------------------------------------------------------------------------------------------
async function main() {
  // Scope: requested ids + every shop item + Beginner starter weapons
  const ids = new Set(ITEM_IDS);
  const extra = [];
  const shopDir = path.join(CANON, 'shops');
  for (const f of fs.readdirSync(shopDir).filter((f) => f.endsWith('.json')).sort()) {
    const shop = JSON.parse(fs.readFileSync(path.join(shopDir, f), 'utf8'));
    for (const it of shop.items || []) if (!ids.has(String(it.item_id))) { ids.add(String(it.item_id)); extra.push(String(it.item_id)); }
  }
  const beginner = JSON.parse(fs.readFileSync(path.join(CANON, 'formulas', 'beginner.json'), 'utf8'));
  for (const w of beginner.starter_weapons?.items || []) if (!ids.has(String(w.item_id))) { ids.add(String(w.item_id)); extra.push(String(w.item_id)); }
  if (extra.length) console.warn('NOTE: added ids from shops/beginner not in ITEM_IDS: ' + extra.join(', '));
  const allIds = [...ids].sort((a, b) => Number(a) - Number(b));

  // Starter weapons: the guide's character-creation sentence names Sword, Hand Axe and Wooden Club.
  const guide = await get(GUIDE_PATH);
  const st = starterWeaponsFromGuide(guide.html);
  if (!st.creation) throw new Error('starter weapon sentences not found in the Beginner\'s guide');
  const starterIds = [];
  for (const [nm, href] of [['Sword', '541'], ['Hand Axe', '576'], ['Wooden Club', '585']]) {
    // the guide links each name to its item page; confirm the link target rather than trusting the name
    if (!guide.html.includes('href="/msclassic/item-db/' + href + '"')) throw new Error('guide has no link to item ' + href + ' (' + nm + ')');
    starterIds.push(href);
  }
  const starter = { ids: starterIds, creation: st.creation, ref: at(guide) };

  let monsters = null;
  const items = [];
  const questPages = new Map(); // quest id -> {pools, itemRefs, ref}; only quests with a random-reward share on an item page
  for (const id of allIds) {
    const pageRes = await get(itemPagePath(id));
    const apiRes = await get(itemApiUrl(id));
    const dropsRes = await get(dropsApiUrl(id));
    if (!monsters) monsters = await monsterNames(pageRes.html);
    const page = parseItemPage(pageRes.html, id);
    const api = JSON.parse(apiRes.text);
    const drops = JSON.parse(dropsRes.text);
    for (const d of drops.drops) {
      const mid = String(d.monsterId);
      if (monsters.map.has(mid) || monsters.extra.has(mid)) continue;
      const mp = await get('/monsters/' + mid);
      monsters.extra.set(mid, { ...monsterFromPage(mp.html, mid), ...at(mp) });
    }
    for (const q of page.questRewards) {
      if (q.chance_pct == null || questPages.has(q.quest_id)) continue;
      const qr = await get('/quest-tracker/' + q.quest_id);
      questPages.set(q.quest_id, { ...questRandomPools(qr.html, q.quest_id), ref: at(qr) });
    }
    if (String(api.id) !== id) throw new Error('item API returned id ' + api.id + ' for ' + id);
    items.push(buildItem(id, page, pageRes, api, apiRes, drops, dropsRes, monsters, starter, questPages));
  }

  // "Required Ammunition" is shown as a name only; resolve it to an id when exactly one extracted item has that name.
  for (const it of items) {
    const ammo = it.weapon?.required_ammunition;
    if (!ammo) continue;
    const hits = items.filter((x) => x.name === ammo);
    if (hits.length === 1) {
      it.weapon.required_ammunition_item_id = hits[0].id;
      if (!it.derived_fields.includes('weapon.required_ammunition_item_id')) it.derived_fields.push('weapon.required_ammunition_item_id');
    } else (it.gaps = it.gaps || []).push('weapon.required_ammunition_item_id: "' + ammo + '" does not match exactly one extracted item');
  }

  // Cross-check against the shops domain: every Maple Island shop row must appear in the item's "Where to buy".
  const crossProblems = [];
  for (const f of fs.readdirSync(shopDir).filter((f) => f.endsWith('.json')).sort()) {
    const shop = JSON.parse(fs.readFileSync(path.join(shopDir, f), 'utf8'));
    for (const it of shop.items || []) {
      const item = items.find((x) => x.id === String(it.item_id));
      const row = item?.sources.shops.find((x) => x.npc_id === String(shop.npc_id));
      CHECKS.shop_rows_vs_shops_domain++;
      if (!row) crossProblems.push(`${f}: item ${it.item_id} has no "Where to buy" row for NPC ${shop.npc_id}`);
      else if (row.price_mesos !== it.price_mesos) crossProblems.push(`${f}: item ${it.item_id} price ${it.price_mesos} vs item page ${row.price_mesos}`);
      if (item && item.sell_price_mesos !== it.sell_price_mesos) crossProblems.push(`${f}: item ${it.item_id} sell ${it.sell_price_mesos} vs ${item.sell_price_mesos}`);
    }
  }
  // Cross-check against the drops domain (same /api/drops records, fetched per monster): entry ids and votes agree.
  const dropsDir = path.join(CANON, 'drops');
  if (fs.existsSync(dropsDir)) {
    for (const f of fs.readdirSync(dropsDir).filter((f) => f.endsWith('.json')).sort()) {
      const table = JSON.parse(fs.readFileSync(path.join(dropsDir, f), 'utf8'));
      if (table.owner?.kind !== 'monster') continue;
      for (const e of table.entries || []) {
        if (!e.community_drop_entry_id) continue;
        const item = items.find((x) => x.id === String(e.item_id));
        if (!item) { crossProblems.push(`drops/${f}: item ${e.item_id} not extracted`); continue; }
        CHECKS.drop_rows_vs_drops_domain++;
        const row = item.sources.monster_drops.find((x) => x.community_drop_entry_id === e.community_drop_entry_id);
        if (!row) crossProblems.push(`drops/${f}: entry ${e.community_drop_entry_id} (item ${e.item_id}) missing from the item's community drops`);
        else if (row.monster_id !== String(table.owner.id) || row.score !== e.votes?.score) crossProblems.push(`drops/${f}: entry ${e.community_drop_entry_id} monster/score ${table.owner.id}/${e.votes?.score} vs item side ${row.monster_id}/${row.score}`);
      }
    }
  }
  if (crossProblems.length) console.warn('CROSS-DOMAIN CHECK:\n  ' + crossProblems.join('\n  '));

  fs.mkdirSync(OUT_DIR, { recursive: true });
  const keep = new Set(items.map((x) => x.id + '.json'));
  for (const f of fs.readdirSync(OUT_DIR)) if (f.endsWith('.json') && !keep.has(f)) fs.rmSync(path.join(OUT_DIR, f));
  for (const it of items) writeJson(path.join(OUT_DIR, it.id + '.json'), it);

  const nGaps = items.reduce((a, x) => a + (x.gaps?.length || 0), 0);
  const nDisc = items.reduce((a, x) => a + (x.discrepancies?.length || 0), 0);
  console.log('cross-checks: ' + JSON.stringify(CHECKS));
  console.log(`items: ${items.length} written to ${path.relative(ROOT, OUT_DIR)} (gaps ${nGaps}, discrepancies ${nDisc}, fresh fetches ${freshFetches.length})`);
}

main().catch((e) => { console.error(e); process.exit(1); });
