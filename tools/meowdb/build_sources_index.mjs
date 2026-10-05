// Build game/data/canonical/canonical_sources.json: for every canonical record, where its values came from.
//
//   node tools/meowdb/build_sources_index.mjs
//
// Answers "where did this gameplay value come from?" without searching history. Reads only the local data files.
// game/scripts/core/validation/provenance_checks.gd (_expected_row) re-derives every row and fails on drift, so the two
// must change together.
//
// Each row lists the record's own source (authority, url, retrieved_at), its field_sources URLs, external entries and
// gap/discrepancy counts. Two keys appear only when the record has them (so MeowDB-only records stay unchanged):
//   capture_files     every dated capture the record cites (any "capture" key, at any depth: tools/*/captures/...)
//   property_sources  per-property authorities and URLs (Iteration Three contract C7): the record-level
//                     provenance.<property> blocks plus, in schema v2 drop records (contract C1), each entry's
//                     membership_source ("membership") and chance_source ("probability") and the meso amount_source
//                     ("mesos.amount") and chance_source ("mesos.probability")
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const CANON = path.join(ROOT, 'game', 'data', 'canonical');
const OUT = path.join(CANON, 'canonical_sources.json');

// Per-entry and meso source keys of a schema v2 drop record -> the property they supply (ProvenanceChecks mirrors this).
const ENTRY_SOURCE_PROPERTIES = { membership_source: 'membership', chance_source: 'probability' };
const MESO_SOURCE_PROPERTIES = { amount_source: 'mesos.amount', chance_source: 'mesos.probability' };

const byKey = ([a], [b]) => (a < b ? -1 : a > b ? 1 : 0);

/** Every string under a "capture" key, at any depth. */
function captureFiles(node, out = new Set()) {
  if (Array.isArray(node)) node.forEach((x) => captureFiles(x, out));
  else if (node && typeof node === 'object') {
    for (const [k, v] of Object.entries(node)) {
      if (k === 'capture' && typeof v === 'string') out.add(v);
      else captureFiles(v, out);
    }
  }
  return out;
}

/** [property, source object] pairs: provenance.<property>, then (drops schema v2) entries[] and meso sources. */
function sourceObjects(domain, rec) {
  const out = [];
  const prov = rec.provenance;
  if (prov && typeof prov === 'object' && !Array.isArray(prov)) for (const [p, s] of Object.entries(prov)) out.push([p, s]);
  if (domain === 'drops' && rec.schema_version === 2) {
    for (const e of Array.isArray(rec.entries) ? rec.entries : []) {
      for (const [k, p] of Object.entries(ENTRY_SOURCE_PROPERTIES)) if (e && e[k] && typeof e[k] === 'object') out.push([p, e[k]]);
    }
    const meso = rec.meso;
    if (meso && typeof meso === 'object') for (const [k, p] of Object.entries(MESO_SOURCE_PROPERTIES)) if (meso[k] && typeof meso[k] === 'object') out.push([p, meso[k]]);
  }
  return out;
}

/** {property: {authorities: [..], urls: [..]}} with sorted keys and lists; URLs from url and urls[]. */
function propertySources(domain, rec) {
  const acc = new Map();
  for (const [p, s] of sourceObjects(domain, rec)) {
    if (!s || typeof s !== 'object' || Array.isArray(s)) continue;
    if (!acc.has(p)) acc.set(p, { authorities: new Set(), urls: new Set() });
    const a = acc.get(p);
    if (typeof s.authority === 'string' && s.authority) a.authorities.add(s.authority);
    if (typeof s.url === 'string' && s.url) a.urls.add(s.url);
    for (const u of Array.isArray(s.urls) ? s.urls : []) if (typeof u === 'string' && u) a.urls.add(u);
  }
  return Object.fromEntries([...acc.entries()].sort(byKey).map(([p, a]) => [p, { authorities: [...a.authorities].sort(), urls: [...a.urls].sort() }]));
}

const records = [];
const urls = new Set();
const captures = new Set();
let externalCount = 0;
for (const domain of fs.readdirSync(CANON).sort()) {
  const dir = path.join(CANON, domain);
  if (!fs.statSync(dir).isDirectory()) continue;
  for (const f of fs.readdirSync(dir).filter((x) => x.endsWith('.json')).sort()) {
    const rec = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
    // Every URL a field source cites: url, fallback_url, pages[] and urls[] (strings or {url}), as ProvenanceChecks
    // (_field_source_urls) validates them.
    const extra = new Set();
    for (const v of Object.values(rec.field_sources || {})) {
      if (!v || typeof v !== 'object') continue;
      for (const k of ['url', 'fallback_url']) if (typeof v[k] === 'string' && v[k]) extra.add(v[k]);
      for (const list of [v.pages, v.urls]) {
        for (const p of Array.isArray(list) ? list : []) {
          const u = typeof p === 'string' ? p : p && p.url;
          if (typeof u === 'string' && u) extra.add(u);
        }
      }
    }
    const external = (rec.external || []).map((e) => ({ field: e.field, source_url: e.source_url, verified: !!e.verified }));
    externalCount += external.length;
    const src = rec.source || {};
    if (src.url) urls.add(src.url);
    extra.forEach((u) => urls.add(u));
    const row = {
      domain,
      id: String(rec.id ?? path.basename(f, '.json')),
      name: rec.name ?? null,
      file: `res://data/canonical/${domain}/${f}`,
      authority: src.authority ?? null,
      url: src.url ?? null,
      retrieved_at: src.retrieved_at ?? null,
      field_source_urls: [...extra].sort(),
      external,
      gap_count: (rec.gaps || []).length,
      discrepancy_count: (rec.discrepancies || []).length,
    };
    const caps = [...captureFiles(rec)].sort();
    if (caps.length) row.capture_files = caps;
    caps.forEach((c) => captures.add(c));
    const props = propertySources(domain, rec);
    if (Object.keys(props).length) row.property_sources = props;
    for (const p of Object.values(props)) p.urls.forEach((u) => urls.add(u));
    records.push(row);
  }
}

const index = {
  id: 'canonical_sources',
  description: 'Provenance index for game/data/canonical. Generated by tools/meowdb/build_sources_index.mjs; do not edit.',
  authority: 'MeowDB MS Classic (https://meowdb.com/msclassic)',
  attribution: 'Gameplay facts courtesy of NiaMeowDB (meowdb.com); each record links to its source page. Game names and text are property of Nexon Co., Ltd.',
  totals: { records: records.length, distinct_source_urls: urls.size, external_values: externalCount, capture_files: captures.size },
  records,
};
fs.writeFileSync(OUT, JSON.stringify(index, null, 2) + '\n');
console.log(`canonical_sources.json: ${records.length} records, ${urls.size} source urls, ${externalCount} external values, ${captures.size} capture files`);
