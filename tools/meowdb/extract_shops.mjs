// Extract every NPC shop owned by a Maple Island NPC from MeowDB MS Classic into
// game/data/canonical/shops/<shop slug>.json (one shop per file).
//
//   node tools/meowdb/extract_shops.mjs            # cache-first (tools/meowdb/.cache); fetches only what is missing
//   node tools/meowdb/extract_shops.mjs --refresh  # re-download every page (new retrieved_at values)
//
// Pages read (all cache-first through lib.mjs, so retrieved_at comes from the cache meta):
//   /npc-shops                         primary: every shop, its NPC, map, items in display order and Classic buy prices
//   /npcs                              NPC index: which NPCs are on Maple Island (region "MapleIsland") and their roles
//   /npcs/<id>  (every Maple Island NPC)  cross-check: only shopkeepers have a "Shop inventory" table; rows/prices agree
//   /maps/<mapId>                      cross-check: the shop NPC stands on the shop's map
//   /item-db/<itemId>                  per item: canonical name, type/subtype, NPC sell-back, max per stack, recharge cost,
//                                      COT1->COT2 change history, and the "Where to buy" price for this NPC
//   /api/items/<itemId>?locale=en&preview=1   per item JSON (MeowDB's item hover-preview endpoint): stats.price is the
//                                      NPC sell-back. Used when the item page omits its "NPC Sell-back" row (it does so
//                                      when the value is 0) and as a cross-check of every row the page does show.
//   /api/items?search=<name>&page=1    for each Safe-to-Sell "droppedNoPrice" item: proves MeowDB marks "no value" by
//                                      omitting stats.price, so an explicit 0 is a recorded value (else 0 is not trusted)
//   https://meowdb.com/_data/safe-to-sell.json   cross-check of NPC sell price (MeowDB's Safe-to-Sell data file)
//   /npc-shops/item-efficiency/{beginner,consumables}   cross-check of buy prices in the Shop Item Efficiency guide, and
//                                      the evidence that a listed price buys ONE unit (its "<stat> / meso" columns)
//
// Deterministic: no clocks, fixed key order, items in MeowDB's display order. Re-running reproduces the files exactly.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { fetchPage, fetchUrl, rsc, jsonAt, valuesForKey, pageText, source, writeJson, BASE_URL } from './lib.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..');
const OUT_DIR = path.join(ROOT, 'game', 'data', 'canonical', 'shops');
const MAPLE_ISLAND_REGION = 'MapleIsland'; // region value used by the /npcs index
// MeowDB's per-item JSON endpoint (the site's item hover-preview fetch in the msclassic layout chunk:
// fetch(`/msclassic/api/items/${id}?locale=${locale}&preview=1`)). Its stats.price is the NPC sell-back value.
const itemApiUrl = (id) => BASE_URL + '/api/items/' + id + '?locale=en&preview=1';

const freshFetches = [];
async function page(p) {
  const r = await fetchPage(p);
  if (!r.fromCache) freshFetches.push(r.url);
  return r;
}
async function url(u, opts) {
  const r = await fetchUrl(u, opts);
  if (!r.fromCache) freshFetches.push(r.url);
  return r;
}
const pageUrl = (p) => BASE_URL + p;
const at = (r) => ({ url: r.url, retrieved_at: r.retrieved_at });

// ---------------------------------------------------------------------------------------------------------------
// Minimal React Server Component tree walker. Pages render their tables into the flight payload as
// ["$", type, key, props] elements; children may be lazy references "$L<hex>" to other rows of the payload.
function makeTree(html) {
  const r = rsc(html);
  const cache = new Map();
  const chunk = (id) => {
    if (cache.has(id)) return cache.get(id);
    let v = null;
    const i = r.indexOf('\n' + id + ':');
    if (i >= 0) {
      const c = r[i + id.length + 2];
      if (c === '[' || c === '{') {
        try { v = jsonAt(r, i + id.length + 2).value; } catch { v = null; }
      }
    }
    cache.set(id, v);
    return v;
  };
  const resolve = (n, guard = 0) => (typeof n === 'string' && /^\$L[0-9a-f]+$/.test(n) && guard < 50 ? resolve(chunk(n.slice(2)), guard + 1) : n);
  const isEl = (n) => Array.isArray(n) && n[0] === '$' && typeof n[1] === 'string';
  const props = (n) => (isEl(n) && n[3] && typeof n[3] === 'object' ? n[3] : {});
  function walk(n, fn, depth = 0) {
    n = resolve(n);
    if (n == null || depth > 500) return;
    if (Array.isArray(n)) {
      if (isEl(n)) {
        if (fn(n) === false) return;
        walk(props(n).children, fn, depth + 1);
        return;
      }
      for (const c of n) walk(c, fn, depth + 1);
    }
  }
  function text(n, out = []) {
    n = resolve(n);
    if (n == null || n === false || n === true) return out;
    if (typeof n === 'string') { if (!n.startsWith('$')) out.push(n); return out; }
    if (typeof n === 'number') { out.push(String(n)); return out; }
    if (Array.isArray(n)) {
      if (isEl(n)) text(props(n).children, out);
      else for (const c of n) text(c, out);
    }
    return out;
  }
  const textOf = (n) => text(n).join('').replace(/\s+/g, ' ').trim();
  const kids = (n) => {
    const c = resolve(props(n).children);
    if (c == null) return [];
    return isEl(c) ? [c] : Array.isArray(c) ? c.map((x) => resolve(x)) : [c];
  };
  function findAll(n, pred) {
    const out = [];
    walk(n, (e) => { if (pred(e)) out.push(e); });
    return out;
  }
  // Every top-level payload row that is an element/array is a potential root; walking from all roots and de-duplicating
  // by identity is unnecessary for our lookups because each lookup below searches for a unique structure.
  const roots = [];
  const re = /\n([0-9a-f]+):\[/g;
  let m;
  while ((m = re.exec(r))) roots.push(chunk(m[1]));
  const all = (pred) => {
    const out = [];
    const seen = new Set();
    for (const root of roots) for (const e of findAll(root, pred)) if (!seen.has(e)) { seen.add(e); out.push(e); }
    return out;
  };
  return { r, resolve, isEl, props, walk, textOf, kids, findAll, all };
}

const num = (s) => {
  if (s == null) return null;
  const m = /-?\d[\d,]*(?:\.\d+)?/.exec(String(s));
  return m ? Number(m[0].replace(/,/g, '')) : null;
};
const hrefId = (href, kind) => {
  const m = new RegExp('^/msclassic/' + kind + '/([0-9]+)(?:[?#].*)?$').exec(href || '');
  return m ? m[1] : null;
};

// ---------------------------------------------------------------------------------------------------------------
// Page parsers

/** /item-db/<id>: name, type/subtype, labelled stat rows, "Where to buy" rows, change history. */
function parseItemPage(html) {
  const T = makeTree(html);
  const h1 = T.all((e) => e[1] === 'h1')[0];
  const name = h1 ? T.textOf(h1) : null;
  // Breadcrumb under the name: <a href="/msclassic/item-db/use">Use</a> · <a href="...?subtype=Potion">Potion</a> · No. 0270
  let itemType = null, itemSubtype = null;
  const crumb = T.all((e) => e[1] === 'div' && T.textOf(e).includes(' · No. ') && T.findAll(e, (x) => /^\/msclassic\/item-db\/[a-z]/.test(T.props(x).href || '')).length > 0)
    .sort((a, b) => T.textOf(a).length - T.textOf(b).length)[0];
  if (crumb) {
    const links = T.findAll(crumb, (x) => /^\/msclassic\/item-db\/[a-z]/.test(T.props(x).href || ''));
    for (const l of links) {
      const href = T.props(l).href;
      if (/[?&]subtype=/.test(href)) itemSubtype = T.textOf(l);
      else if (itemType == null) itemType = T.textOf(l);
    }
  }
  // Labelled stat rows: ["$","div","<Label>",{children:[<label span>, <value span>]}]
  const stats = {};
  for (const e of T.all((x) => x[1] === 'div' && typeof x[2] === 'string' && x[2].length < 60)) {
    const t = T.textOf(e);
    if (t.startsWith(e[2])) stats[e[2]] = t.slice(e[2].length).trim();
  }
  // Where to buy
  const whereToBuy = [];
  const wtb = T.all((e) => e[1] === 'section' && T.findAll(e, (x) => x[1] === 'h2' && T.textOf(x) === 'Where to buy').length > 0)[0];
  if (wtb) {
    for (const li of T.findAll(wtb, (x) => x[1] === 'li')) {
      const npcLink = T.findAll(li, (x) => hrefId(T.props(x).href, 'npcs'))[0];
      const mapLink = T.findAll(li, (x) => /^\/msclassic\/maps\/\d+$/.test(T.props(x).href || ''))[0];
      const priceDiv = T.findAll(li, (x) => x[1] === 'div' && /\bfont-mono\b/.test(T.props(x).className || ''))[0];
      whereToBuy.push({
        npc_id: npcLink ? hrefId(T.props(npcLink).href, 'npcs') : null,
        npc_name: npcLink ? T.textOf(npcLink) : null,
        map_id: mapLink ? T.props(mapLink).href.split('/').pop() : null,
        price_mesos: priceDiv ? num(T.textOf(priceDiv)) : null,
      });
    }
  }
  // Change history (<details> with h2 "Change history"): stat rows and note list items
  const changeHistory = [];
  const changeNotes = [];
  const ch = T.all((e) => e[1] === 'details' && T.findAll(e, (x) => x[1] === 'h2' && T.textOf(x) === 'Change history').length > 0)[0];
  if (ch) {
    for (const tr of T.findAll(ch, (x) => x[1] === 'tr' && typeof x[2] === 'string')) {
      const cells = T.kids(tr).filter((c) => T.isEl(c)).map((c) => T.textOf(c));
      changeHistory.push({ stat: cells[0] ?? null, cot1: num(cells[1]), cot2: num(cells[2]), change: num(cells[3]) });
    }
    for (const li of T.findAll(ch, (x) => x[1] === 'li')) changeNotes.push(T.textOf(li));
  }
  return { name, itemType, itemSubtype, stats, whereToBuy, changeHistory, changeNotes };
}

/** /npcs/<id>: the "Shop inventory (N items)" section, if any. */
function parseNpcShopSection(html) {
  const T = makeTree(html);
  const sec = T.all((e) => e[1] === 'section' && T.findAll(e, (x) => x[1] === 'h2' && /^Shop inventory/.test(T.textOf(x))).length > 0)[0];
  if (!sec) return null;
  const heading = T.textOf(T.findAll(sec, (x) => x[1] === 'h2')[0]);
  const badge = T.findAll(sec, (x) => x[1] === 'span' && /prices$/.test(T.textOf(x)))[0];
  const soldAt = T.findAll(sec, (x) => /^\/msclassic\/maps\/\d+$/.test(T.props(x).href || ''))[0];
  const rows = [];
  for (const tr of T.findAll(sec, (x) => x[1] === 'tr' && typeof x[2] === 'string' && /^\d+-\d+$/.test(x[2]))) {
    const [id, idx] = tr[2].split('-');
    const link = T.findAll(tr, (x) => hrefId(T.props(x).href, 'item-db'))[0];
    const cells = T.kids(tr).filter((c) => T.isEl(c));
    rows.push({ row_key_item_id: id, index: Number(idx), item_id: link ? hrefId(T.props(link).href, 'item-db') : null, name: link ? T.textOf(link) : null, price_mesos: num(T.textOf(cells[cells.length - 1])) });
  }
  return {
    heading,
    heading_item_count: num(heading),
    price_badge: badge ? T.textOf(badge) : null,
    sold_at_map_id: soldAt ? T.props(soldAt).href.split('/').pop() : null,
    sold_at_text: soldAt ? T.textOf(soldAt) : null,
    rows,
  };
}

/** /npc-shops/item-efficiency/<tab>: per table, align header cells with row cells to read the Price column. */
function parseEfficiencyRows(html) {
  const T = makeTree(html);
  const out = [];
  for (const table of T.all((e) => e[1] === 'table')) {
    const thead = T.findAll(table, (x) => x[1] === 'thead')[0];
    const htr = thead && T.findAll(thead, (x) => x[1] === 'tr')[0];
    if (!htr) continue;
    const headers = T.kids(htr).map((c) => (T.isEl(c) ? T.textOf(c) : null));
    const priceCol = headers.indexOf('Price');
    for (const tr of T.findAll(table, (x) => x[1] === 'tr' && typeof x[2] === 'string' && /^\d+-\d+$/.test(x[2]))) {
      const cells = T.kids(tr);
      const link = T.findAll(tr, (x) => hrefId(T.props(x).href, 'item-db'))[0];
      const sellers = T.findAll(tr, (x) => hrefId(T.props(x).href, 'npcs')).map((x) => hrefId(T.props(x).href, 'npcs'));
      const ok = priceCol >= 0 && cells.length === headers.length && T.isEl(cells[priceCol]);
      out.push({
        item_id: link ? hrefId(T.props(link).href, 'item-db') : tr[2].split('-')[0],
        name: link ? T.textOf(link) : null,
        price_mesos: ok ? num(T.textOf(cells[priceCol])) : null,
        parsed: ok,
        npc_ids: [...new Set(sellers)],
        // every cell keyed by its column header (used to re-check the guide's "<stat> / meso" ratio columns)
        cells: ok ? Object.fromEntries(headers.map((h, k) => [h, T.isEl(cells[k]) ? T.textOf(cells[k]) : null])) : null,
      });
    }
  }
  return out;
}

/**
 * Per-unit evidence from one Shop Item Efficiency row. The guide divides ONE item's stat by the listed price
 * (e.g. Red Potion: "HP restored" 100, "Price" 50, "HP / meso" 2.000). If that recomputes, the listed price buys one unit.
 * Returns null when the row has no single-stat "<stat> / meso" column (e.g. the Pet Food table, the dual-restore table).
 */
function perUnitRatio(row) {
  if (!row.cells || row.price_mesos == null || row.price_mesos <= 0) return null;
  const ratioHeader = Object.keys(row.cells).find((h) => / \/ meso$/.test(h));
  if (!ratioHeader) return null;
  const stat = ratioHeader.replace(/ \/ meso$/, '');
  const statHeader = Object.keys(row.cells).find((h) => h === stat || h === stat + ' restored');
  const statText = statHeader ? row.cells[statHeader] : null;
  const ratioText = row.cells[ratioHeader];
  if (statText == null || ratioText == null || /\+/.test(statText)) return null; // dual restores ("100 + 100 MP") are not single-stat
  const statValue = num(statText);
  const guideRatio = num(ratioText);
  if (statValue == null || guideRatio == null) return null;
  const decimals = ((/\.(\d+)/.exec(ratioText) || [])[1] || '').length;
  const recomputed = (statValue / row.price_mesos).toFixed(decimals);
  return { stat_column: statHeader, stat_value: statValue, price_mesos: row.price_mesos, ratio_column: ratioHeader, guide_ratio: guideRatio, recomputed_ratio: Number(recomputed), consistent: recomputed === guideRatio.toFixed(decimals) };
}

function renameReason(rename, shopListName, itemPageName, guideNames) {
  const guide = guideNames.length
    ? (guideNames.every((n) => n === itemPageName) ? ' The Shop Item Efficiency guide uses the item-page spelling.' : ` The Shop Item Efficiency guide shows: ${guideNames.map((n) => JSON.stringify(n)).join(', ')}.`)
    : '';
  const base = "The item page is the item's own detail page; the shop list (the /npc-shops index and the NPC page render one dataset) spells it differently." + guide +
    ' "name" uses the item-page name and the shop list spelling is kept in "shop_list_name".';
  if (!rename) return base + ' MeowDB gives no rename note for this item.';
  const old = (/It was called (.+)\.$/.exec(rename) || [])[1] || null;
  if (old === shopListName) return base + ` The item page says "${rename}", so the shop list still shows the pre-COT2 name.`;
  if (old && old.toLowerCase() === shopListName.toLowerCase()) return base + ` The item page says "${rename}"; the shop list shows that pre-COT2 name with different letter case.`;
  return base + ` The item page says "${rename}"`;
}

// ---------------------------------------------------------------------------------------------------------------
async function main() {
  // 1. Shops index
  const shopsPage = await page('/npc-shops');
  const shopsRsc = rsc(shopsPage.html);
  const shops = valuesForKey(shopsRsc, 'shops').find((v) => Array.isArray(v) && v.length && v[0].slug);
  if (!shops) throw new Error('shops array not found in /npc-shops payload');

  // 2. NPC index -> Maple Island NPCs
  const npcsPage = await page('/npcs');
  const npcs = valuesForKey(rsc(npcsPage.html), 'npcs').find((v) => Array.isArray(v) && v.length && v[0].id != null && v[0].roles);
  if (!npcs) throw new Error('npcs array not found in /npcs payload');
  const mapleIslandNpcs = npcs.filter((n) => (n.maps || []).some((m) => m.region === MAPLE_ISLAND_REGION));
  const mapleIslandNpcIds = new Set(mapleIslandNpcs.map((n) => String(n.id)));

  // A shop is in scope when its NPC is a Maple Island NPC. Cross-check against the index's own region grouping.
  const inScope = shops.filter((s) => s.npcId != null && mapleIslandNpcIds.has(String(s.npcId)));
  const byRegionGroup = shops.filter((s) => s.town === 'maple-road');
  const scopeIds = inScope.map((s) => s.slug).join(',');
  if (scopeIds !== byRegionGroup.map((s) => s.slug).join(',')) {
    throw new Error(`scope mismatch: by NPC region [${scopeIds}] vs index group maple-road [${byRegionGroup.map((s) => s.slug)}]`);
  }

  // 3. Every Maple Island NPC page: only the shop NPCs may carry a "Shop inventory" table.
  const npcPageShop = new Map();
  for (const n of mapleIslandNpcs) {
    const p = await page('/npcs/' + n.id);
    npcPageShop.set(String(n.id), { page: p, shop: parseNpcShopSection(p.html) });
  }
  const shopNpcIds = new Set(inScope.map((s) => String(s.npcId)));
  for (const [id, v] of npcPageShop) {
    if (!!v.shop !== shopNpcIds.has(id)) throw new Error(`NPC ${id}: shop section present=${!!v.shop} but in-scope shop=${shopNpcIds.has(id)}`);
  }

  // 4. Shared cross-check sources
  const safeToSell = await url('https://meowdb.com/_data/safe-to-sell.json', { accept: 'application/json' });
  const safeJson = JSON.parse(safeToSell.text);
  const safeById = new Map();
  for (const row of safeJson.rows || []) if (!safeById.has(String(row.itemId))) safeById.set(String(row.itemId), row);
  const effPages = [];
  for (const tab of ['beginner', 'consumables']) {
    const p = await page('/npc-shops/item-efficiency/' + tab);
    effPages.push({ tab, page: p, rows: parseEfficiencyRows(p.html) });
  }

  // Purchase unit. MeowDB never prints "price per unit" on the shop list, but its Shop Item Efficiency guide divides one
  // item's stat by the listed price, and the consumables tab says arrows are "1 meso each". Re-check every guide row that
  // lists an in-scope NPC as seller; quantity_per_purchase is 1 only if all of them recompute and the sentence is present.
  const consumablesTab = effPages.find((e) => e.tab === 'consumables');
  const ARROW_SENTENCE = 'Arrows are 1 meso each';
  const arrowSentencePresent = pageText(consumablesTab.page.html).includes(ARROW_SENTENCE);
  const perUnitEvidence = [];
  for (const s of inScope) {
    for (const it of s.items) {
      for (const ep of effPages) {
        for (const row of ep.rows.filter((r) => r.item_id === String(it.itemId) && r.npc_ids.includes(String(s.npcId)))) {
          const ev = perUnitRatio(row);
          if (ev) perUnitEvidence.push({ shop: s.slug, item_id: String(it.itemId), tab: ep.tab, ...ev });
        }
      }
    }
  }
  const PER_UNIT_OK = arrowSentencePresent && perUnitEvidence.length > 0 && perUnitEvidence.every((e) => e.consistent);

  // Sell-back 0 vs unknown. The item API is only trusted for a 0 when MeowDB demonstrably marks "no value" differently:
  // the Safe-to-Sell file lists the items it dropped for having no price ("droppedNoPrice"); in the item API those items
  // must have NO price key at all. Reference item 294 (Subi Throwing Stars) checks stats.price/unitPrice against its page.
  const noPriceReference = [];
  for (const name of safeJson.droppedNoPrice || []) {
    const r = await url(BASE_URL + '/api/items?search=' + encodeURIComponent(name).replace(/%20/g, '+') + '&page=1', { accept: 'application/json' });
    for (const h of (JSON.parse(r.text).items || []).filter((x) => x.name === name)) {
      const st = typeof h.stats === 'string' ? JSON.parse(h.stats) : (h.stats || {});
      noPriceReference.push({ item_id: String(h.id), name, has_price_key: Object.prototype.hasOwnProperty.call(st, 'price'), ...at(r) });
    }
  }
  const ZERO_IS_RECORDED = noPriceReference.length > 0 && noPriceReference.every((x) => !x.has_price_key);
  const subiPage = await page('/item-db/294');
  const subi = parseItemPage(subiPage.html);
  const subiApi = await url(itemApiUrl('294'), { accept: 'application/json' });
  const subiStats = (() => { const j = JSON.parse(subiApi.text); return typeof j.stats === 'string' ? JSON.parse(j.stats) : (j.stats || {}); })();
  const subiCheck = {
    item_id: '294', name: subi.name, item_page: at(subiPage), item_api: at(subiApi),
    page_sell_back_per_unit: num(subi.stats['NPC Sell-back (per unit)']), api_stats_price: subiStats.price ?? null,
    page_recharge_cost: num(subi.stats['Recharge Cost']), api_stats_unitPrice: subiStats.unitPrice ?? null,
  };
  subiCheck.matches = subiCheck.page_sell_back_per_unit === subiCheck.api_stats_price && subiCheck.page_recharge_cost === subiCheck.api_stats_unitPrice;

  fs.mkdirSync(OUT_DIR, { recursive: true });
  const written = [];
  const allItemIds = [];
  const outs = [];

  for (const s of inScope) {
    const npcId = String(s.npcId);
    const npcIdx = npcs.find((n) => String(n.id) === npcId);
    const mapPage = await page('/maps/' + s.mapId);
    const mapNpcs = valuesForKey(rsc(mapPage.html), 'npcs').find((v) => Array.isArray(v)) || [];
    const npcOnMap = mapNpcs.find((n) => String(n.id) === npcId) || null;
    const npcShop = npcPageShop.get(npcId);

    const discrepancies = [];
    const gaps = [];
    const items = [];
    const crossItemPages = { rows_checked: 0, rows_matching: 0, mismatches: [] };
    const crossSafe = { items_present: 0, sell_price_matches: 0, mismatches: [] };
    const crossEff = { rows_found: 0, rows_matching: 0, rows_unparsed: 0, mismatches: [] };
    const crossApi = { rows_checked: 0, page_sell_back_rows: 0, page_api_price_matches: 0, api_only_rows: 0, api_only_zero_rows: 0, no_price_anywhere_rows: 0, basis_rule_checked: 0, basis_rule_holds: 0, recharge_consistent_rows: 0, mismatches: [] };
    const missingSell = [];
    const zeroSell = [];

    for (let i = 0; i < s.items.length; i++) {
      const it = s.items[i];
      const itemId = String(it.itemId);
      allItemIds.push(itemId);
      const ip = await page('/item-db/' + itemId);
      const parsed = parseItemPage(ip.html);
      const api = await url(itemApiUrl(itemId), { accept: 'application/json' });
      const apiJson = JSON.parse(api.text);
      const apiStats = typeof apiJson.stats === 'string' ? JSON.parse(apiJson.stats) : (apiJson.stats || {});
      if (String(apiJson.id) !== itemId) throw new Error(`item API for ${itemId} returned id ${apiJson.id}`);
      const apiPrice = Object.prototype.hasOwnProperty.call(apiStats, 'price') && typeof apiStats.price === 'number' ? apiStats.price : null;
      crossApi.rows_checked++;

      // Sell-back. Primary: the item page row. Stackables show "NPC Sell-back (per unit)", single items "NPC Sell-back".
      // The page omits the row when MeowDB's value is 0, so when there is no row the item API's stats.price is used.
      // MeowDB separates "no value" (stats has no price key, e.g. the Safe-to-Sell "droppedNoPrice" items) from 0.
      const hasStack = parsed.stats['Max per Stack'] != null;
      const stackBasis = hasStack ? 'per_unit' : 'per_item'; // MeowDB labels stackables "(per unit)"; checked below on every labelled row
      let sell = null, sellBasis = null, sellSource = null;
      if (parsed.stats['NPC Sell-back (per unit)'] != null) { sell = num(parsed.stats['NPC Sell-back (per unit)']); sellBasis = 'per_unit'; sellSource = 'item_page'; }
      else if (parsed.stats['NPC Sell-back'] != null) { sell = num(parsed.stats['NPC Sell-back']); sellBasis = 'per_item'; sellSource = 'item_page'; }
      if (sellSource === 'item_page') {
        crossApi.page_sell_back_rows++;
        if (apiPrice === sell) crossApi.page_api_price_matches++;
        else crossApi.mismatches.push({ item_id: itemId, field: 'sell_price_mesos', item_page: sell, item_api_stats_price: apiPrice });
        crossApi.basis_rule_checked++;
        if (sellBasis === stackBasis) crossApi.basis_rule_holds++;
        else crossApi.mismatches.push({ item_id: itemId, field: 'sell_price_basis', item_page_label_basis: sellBasis, max_per_stack_rule_basis: stackBasis });
      } else if (apiPrice != null && (apiPrice !== 0 || ZERO_IS_RECORDED)) {
        sell = apiPrice; sellBasis = stackBasis; sellSource = 'item_api';
        crossApi.api_only_rows++;
        if (apiPrice === 0) { crossApi.api_only_zero_rows++; zeroSell.push(`${itemId} ${parsed.name}`); }
      } else {
        crossApi.no_price_anywhere_rows++;
        missingSell.push(`${itemId} ${parsed.name}`);
      }
      const rechargeCost = parsed.stats['Recharge Cost'] != null ? num(parsed.stats['Recharge Cost']) : null;
      const apiUnitPrice = typeof apiStats.unitPrice === 'number' ? apiStats.unitPrice : null;
      if (apiUnitPrice === rechargeCost) crossApi.recharge_consistent_rows++;
      else crossApi.mismatches.push({ item_id: itemId, field: 'recharge_cost_mesos_per_unit', item_page: rechargeCost, item_api_stats_unitPrice: apiUnitPrice });
      if (apiJson.name !== parsed.name) crossApi.mismatches.push({ item_id: itemId, field: 'name', item_page: parsed.name, item_api: apiJson.name });

      const sellHistory = parsed.changeHistory.filter((r) => r.stat === 'Sell-back price');
      const otherHistory = parsed.changeHistory.filter((r) => r.stat !== 'Sell-back price');

      // name discrepancy: shop list vs item page
      if (parsed.name && parsed.name !== it.name) {
        const rename = parsed.changeNotes.find((n) => /^Renamed in /.test(n)) || null;
        discrepancies.push({
          field: `items[${i}].name`,
          item_id: itemId,
          values: [
            { value: it.name, source: pageUrl('/npc-shops') + '#' + s.slug, also_on: pageUrl('/npcs/' + npcId) },
            { value: parsed.name, source: pageUrl('/item-db/' + itemId) },
          ],
          chosen: parsed.name,
          reason: renameReason(rename, it.name, parsed.name, [...new Set(effPages.flatMap((ep) => ep.rows.filter((r) => r.item_id === itemId).map((r) => r.name)))]),
        });
      }

      // cross-check: item page "Where to buy" row for this NPC
      const wtb = parsed.whereToBuy.find((w) => w.npc_id === npcId);
      crossItemPages.rows_checked++;
      if (wtb && wtb.price_mesos === it.classicPrice && wtb.map_id === s.mapId) crossItemPages.rows_matching++;
      else crossItemPages.mismatches.push({ item_id: itemId, index_price_mesos: it.classicPrice, item_page_row: wtb || null });

      // cross-check: safe-to-sell.json sell price
      const safe = safeById.get(itemId);
      if (safe) {
        crossSafe.items_present++;
        if (safe.price === sell) crossSafe.sell_price_matches++;
        else crossSafe.mismatches.push({ item_id: itemId, item_page_sell_price_mesos: sell, safe_to_sell_price_mesos: safe.price });
      }

      // cross-check: Shop Item Efficiency guide rows that list this NPC as a seller
      for (const ep of effPages) {
        for (const row of ep.rows.filter((r) => r.item_id === itemId && r.npc_ids.includes(npcId))) {
          crossEff.rows_found++;
          if (!row.parsed) crossEff.rows_unparsed++;
          else if (row.price_mesos === it.classicPrice) crossEff.rows_matching++;
          else crossEff.mismatches.push({ item_id: itemId, tab: ep.tab, guide_price_mesos: row.price_mesos, index_price_mesos: it.classicPrice });
        }
      }

      items.push({
        position: i + 1,
        item_id: itemId,
        name: parsed.name ?? it.name,
        shop_list_name: it.name,
        icon_key: it.iconKey ?? null,
        item_type: parsed.itemType,
        item_subtype: parsed.itemSubtype,
        price_mesos: it.classicPrice ?? null,
        quantity_per_purchase: PER_UNIT_OK ? 1 : null,
        stock_limit: null,
        citizen_req: it.citizenReq ?? null,
        max_per_stack: parsed.stats['Max per Stack'] != null ? num(parsed.stats['Max per Stack']) : null,
        sell_price_mesos: sell,
        sell_price_basis: sellBasis,
        sell_price_source: sellSource,
        rechargeable: rechargeCost != null,
        recharge_cost_mesos_per_unit: rechargeCost,
        sell_price_history: sellHistory.map((r) => ({ cot1_mesos: r.cot1, cot2_mesos: r.cot2 })),
        other_change_history: otherHistory.map((r) => ({ stat: r.stat, cot1: r.cot1, cot2: r.cot2 })),
        change_notes: parsed.changeNotes,
        price_match_source: it.matchSource ?? null,
        item_page: at(ip),
        item_api: at(api),
      });
    }

    // cross-check: NPC page shop table vs index
    const ns = npcShop.shop;
    const npcRowsMatch = !!ns && ns.rows.length === s.items.length && ns.rows.every((r, k) =>
      r.index === k && r.item_id === String(s.items[k].itemId) && r.row_key_item_id === r.item_id && r.price_mesos === s.items[k].classicPrice && r.name === s.items[k].name);
    if (!npcRowsMatch) discrepancies.push({ field: 'items', note: 'NPC page shop table differs from the /npc-shops index', npc_page_rows: ns ? ns.rows : null });
    if (ns && ns.heading_item_count !== s.items.length) discrepancies.push({ field: 'item_count', values: [{ value: s.items.length, source: pageUrl('/npc-shops') }, { value: ns.heading_item_count, source: pageUrl('/npcs/' + npcId) }] });
    if (ns && ns.sold_at_map_id !== s.mapId) discrepancies.push({ field: 'map_id', values: [{ value: s.mapId, source: pageUrl('/npc-shops') }, { value: ns.sold_at_map_id, source: pageUrl('/npcs/' + npcId) }] });
    const npcIndexMapIds = (npcIdx.maps || []).map((m) => m.mapId);
    if (!npcIndexMapIds.includes(s.mapId)) discrepancies.push({ field: 'map_id', note: 'NPC index lists a different map for this NPC', npc_index_map_ids: npcIndexMapIds });
    if (!npcOnMap) discrepancies.push({ field: 'map_id', note: `NPC ${npcId} is not in the npcs list of map ${s.mapId}` });
    if (s.npcName !== npcIdx.name) discrepancies.push({ field: 'npc_name', values: [{ value: s.npcName, source: pageUrl('/npc-shops') }, { value: npcIdx.name, source: pageUrl('/npcs') }] });
    for (const m of crossApi.mismatches) discrepancies.push({ field: `items[].${m.field}`, item_id: m.item_id, note: 'item page and item API disagree', ...m });

    const shopPerUnit = perUnitEvidence.filter((e) => e.shop === s.slug);
    gaps.push('MeowDB has no numeric shop id; "id" is the shop slug MeowDB uses as the /npc-shops anchor.');
    if (PER_UNIT_OK) gaps.push('Purchase quantity: MeowDB prices one unit (quantity_per_purchase = 1) but documents no limit on how many units one purchase may buy.');
    else gaps.push('quantity_per_purchase: the per-unit check against the Shop Item Efficiency guide failed, so MeowDB\'s purchase unit is left unknown.');
    gaps.push('stock_limit: MeowDB documents no stock limits (finite or restocking) for NPC shops.');
    if (missingSell.length) gaps.push(`sell_price_mesos: neither the item page nor the item API gives a usable sell-back value for ${missingSell.length} item(s): ${missingSell.join('; ')}.`);
    if (zeroSell.length) gaps.push(`Selling 0-mesos items: MeowDB records sell-back 0 for ${zeroSell.length} item(s) here but does not say whether the NPC refuses them or pays 0 mesos.`);
    gaps.push('Recharge: no item in this shop has a "Recharge Cost" row, and MeowDB does not say whether this NPC recharges throwing stars.');
    gaps.push('Sell rules: MeowDB documents per-item sell-back values only; it gives no general sell-price formula and no shop-specific sell restrictions.');

    const notes = [];
    notes.push(`MeowDB price note for this shop: "${s.priceSource}"`);
    notes.push('price_mesos is the base price of ONE unit, in mesos. The citizenship discount (formulas/leveling, citizenship) applies only in Henesys or Kerning City, so it never applies to this shop; citizen_req is null on every row.');
    if (zeroSell.length) notes.push({ zero_sell_placeholder: zeroSell }); // replaced after all shops are read (needs global counts)
    if (items.some((x) => x.item_type === 'Equip')) notes.push('Equipment item pages note: "NPC shop copies always roll clean." Equipment bought here has the item\'s clean (base) stats.');
    notes.push('icon_key is MeowDB\'s icon key for the item. It is not the MeowDB item id; use item_id to join with items data.');

    // Item-page fields come from one page per row: each field source lists every row's page ({url, retrieved_at}, in
    // display order, as in items[].item_page), so it cites real URLs, never a URL template.
    const itemPages = items.map((x) => x.item_page);
    const fromItemPages = (note) => ({ pages: itemPages, note });
    const out = {
      id: s.slug,
      name: s.npcName,
      npc_id: npcId,
      npc_name: s.npcName,
      npc_function: s.npcFunction || null,
      region: s.region,
      town_slug: s.town,
      map_id: s.mapId,
      map_name: s.location,
      map_display_name: s.videoMapName,
      currency: 'mesos',
      price_patch: s.patch ?? null,
      opens_no_shop: s.opensNoShop ?? null,
      meowdb_record_source: s.source ?? null,
      item_count: s.items.length,
      items,
      source: source(pageUrl('/npc-shops') + '#' + s.slug, shopsPage.retrieved_at),
      field_sources: {
        'items[].name': fromItemPages("item detail page heading"),
        'items[].item_type': fromItemPages("item page breadcrumb (category link)"),
        'items[].item_subtype': fromItemPages("item page breadcrumb (?subtype= link)"),
        'items[].max_per_stack': fromItemPages("\"Max per Stack\" row"),
        'items[].quantity_per_purchase': {
          url: consumablesTab.page.url, retrieved_at: consumablesTab.page.retrieved_at,
          also: effPages.filter((e) => e !== consumablesTab).map((e) => at(e.page)),
          note: `1 = price_mesos buys one unit. MeowDB's Shop Item Efficiency guide divides one item's stat by the listed price (e.g. Red Potion: 100 HP / 50 mesos = "HP / meso" 2.000) and says "${ARROW_SENTENCE}". Re-checked on ${perUnitEvidence.filter((e) => e.consistent).length}/${perUnitEvidence.length} guide rows for these shops; see cross_checks.shop_item_efficiency_guide.per_unit_ratio_rows.`,
        },
        'items[].sell_price_mesos': {
          pages: itemPages,
          fallback_pages: items.filter((x) => x.sell_price_source === 'item_api').map((x) => x.item_api),
          note: "item page \"NPC Sell-back (per unit)\" or \"NPC Sell-back\" row; when the page has no such row, the item API's stats.price (the page omits the row when the value is 0). sell_price_source says which one was used; fallback_pages lists the item API responses of the rows that took it.",
        },
        'items[].sell_price_basis': fromItemPages("per_unit when the row label is \"NPC Sell-back (per unit)\", per_item when it is \"NPC Sell-back\". For rows taken from the item API (no label), per_unit if the item page has a \"Max per Stack\" row, else per_item; this rule reproduces the label on every labelled row (cross_checks.item_api.basis_rule_holds)."),
        'items[].sell_price_source': fromItemPages("\"item_page\" or \"item_api\" (null if neither has a value)"),
        'items[].rechargeable': fromItemPages("true only when the item page has a \"Recharge Cost\" row"),
        'items[].recharge_cost_mesos_per_unit': fromItemPages("\"Recharge Cost\" row"),
        'items[].sell_price_history': fromItemPages("Change history table, \"Sell-back price\" row (COT1 -> COT2)"),
        'items[].other_change_history': fromItemPages("Change history table, other rows"),
        'items[].change_notes': fromItemPages("Change history notes"),
      },
      cross_checks: {
        npc_index: { ...at(npcsPage), roles: npcIdx.roles, map_ids: npcIndexMapIds, maple_island: true },
        npc_page: { ...at(npcShop.page), heading: ns ? ns.heading : null, price_badge: ns ? ns.price_badge : null, sold_at: ns ? ns.sold_at_text : null, rows_match_index: npcRowsMatch },
        map_page: { ...at(mapPage), npc_listed_on_map: !!npcOnMap },
        item_pages_where_to_buy: crossItemPages,
        item_api: {
          ...crossApi,
          zero_is_recorded_value: ZERO_IS_RECORDED,
          no_price_reference: noPriceReference,
          reference_item_294: subiCheck,
        },
        safe_to_sell_json: { ...at(safeToSell), generated: safeJson.generated ?? null, ...crossSafe },
        shop_item_efficiency_guide: {
          pages: effPages.map((e) => at(e.page)), ...crossEff,
          per_unit_sentence: { text: ARROW_SENTENCE, present: arrowSentencePresent },
          per_unit_ratio_rows: shopPerUnit.map(({ shop, ...e }) => e),
        },
      },
      discrepancies,
      gaps,
      notes,
    };
    outs.push(out);
  }

  // Global page-vs-API agreement (all shops + reference item 294), then write.
  const pageRows = outs.reduce((n, o) => n + o.cross_checks.item_api.page_sell_back_rows, 0);
  const pageMatches = outs.reduce((n, o) => n + o.cross_checks.item_api.page_api_price_matches, 0);
  for (const out of outs) {
    out.notes = out.notes.map((n) => (n && n.zero_sell_placeholder
      ? `sell_price_mesos is 0 for ${n.zero_sell_placeholder.join('; ')}: the item API records stats.price 0 and the item page omits its "NPC Sell-back" row when the value is 0. Where the page does show the row, it equals the API value (${pageMatches}/${pageRows} rows across the Maple Island shops, and reference item 294${subiCheck.matches ? '' : ' NOT'} matching). Items MeowDB has no value for (the Safe-to-Sell "droppedNoPrice" items: ${noPriceReference.map((x) => x.item_id + ' ' + x.name).join(', ')}) have no price key at all, so 0 is a recorded value, not a gap.`
      : n));
    const file = path.join(OUT_DIR, out.id + '.json');
    writeJson(file, out);
    written.push(path.relative(ROOT, file).replace(/\\/g, '/'));
  }

  // Recharge rule reference (no Maple Island shop sells a rechargeable item); printed for the doc's reproducibility.
  console.log(`recharge reference: item 294 ${subi.name}: Recharge Cost = ${subi.stats['Recharge Cost']}, NPC Sell-back (per unit) = ${subi.stats['NPC Sell-back (per unit)']}, Max per Stack = ${subi.stats['Max per Stack']}; item API stats.price = ${subiCheck.api_stats_price}, unitPrice = ${subiCheck.api_stats_unitPrice}`);
  console.log(`sell-back: item page vs item API ${pageMatches}/${pageRows}; 0 is a recorded value: ${ZERO_IS_RECORDED} (no-price reference: ${noPriceReference.map((x) => `${x.item_id} ${x.name} has_price_key=${x.has_price_key}`).join(', ')})`);
  console.log(`per unit: ${PER_UNIT_OK} (${perUnitEvidence.filter((e) => e.consistent).length}/${perUnitEvidence.length} guide ratio rows recompute; "${ARROW_SENTENCE}" present: ${arrowSentencePresent})`);
  console.log(`maple island npcs: ${mapleIslandNpcs.length}; shops in scope: ${inScope.map((s) => `${s.slug} (npc ${s.npcId}, map ${s.mapId}, ${s.items.length} items)`).join(', ')}`);
  console.log(`referenced item ids (${new Set(allItemIds).size}): ${[...new Set(allItemIds)].join(',')}`);
  console.log('wrote:\n  ' + written.join('\n  '));
  if (freshFetches.length) console.log(`NOTE: ${freshFetches.length} page(s) were not cached and were fetched now:\n  ` + freshFetches.join('\n  '));
}

main().catch((e) => { console.error(e); process.exit(1); });
