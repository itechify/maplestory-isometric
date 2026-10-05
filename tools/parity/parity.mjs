// The Maple Island parity manifest (brief "Iteration Three Core Objective"): every canonical Maple Island entity and
// mechanic the player meets, with a state (missing | partial | implemented | verified), the evidence behind it and the
// source-data gaps that excuse it. Pure: buildParity() takes everything as data; build_parity.mjs reads the files.
//
// State rule (documented in docs/MAPLE_ISLAND_PARITY.md, contract C6 for the evidence):
//   missing      the runtime the category or mechanic needs is not there (tools/parity/rules.json declares which
//                files or code markers make up that runtime; a declaration whose files are absent is "missing")
//   partial      the runtime is there, but the entry has an open issue: a validation error on its record, a value the
//                runtime still takes from a placeholder, a referenced item without a definition, an unresolved value
//                that is not a source-data gap, a failing tagged check, or (a canonical-verification row) shipped
//                data not yet in the state the row describes (rules.json requires, e.g. drop records still schema v1)
//   implemented  the runtime is there, the data validates and every unresolved value is a documented source-data gap,
//                but no passing check is tagged with the entry's key
//   verified     as implemented, plus at least one passing check tagged with the entry's key (or a key it accepts, e.g.
//                an objective accepts its quest's key) and no failing one. Quests, their objectives and rewards need
//                that check from the real game: a playtest report.json check, not a unit test (brief "Full Quest
//                Playthrough Requirement"). A chain is derived from its member quests and also needs a real-game
//                check of one of its links (RULE_TEXT.chains). A drop probability can only be verified when its sources
//                resolve (a KuroDB chance for a member of the membership list); an unresolved one is a source-data gap.
//   source_data_gap  (a flag next to the state) the entry cannot be completed because the sources were read and do not
//                give a value (KuroDB's page for that monster has no row for the member; Hidden Street gives no meso
//                amount): it is excused from the exit criterion "every in-scope entry verified".
//   pending_source_read  (a flag next to the state, never set together with source_data_gap) a value the entry needs
//                is published on a page nobody has read yet, so it is NOT a source-data gap and is NOT excused: the
//                entry stays partial and counts as open until the page is read and the data updated. A drop record
//                marks one itself: a KuroDB row drops_merge.mjs excluded as a possible match for a member (any
//                excluded_kuro_only reason but the KuroDB-only one) makes that member's unresolved chance pending, even
//                when undeclared. Other entries are declared in rules.json pending_source_reads (the read that resolves
//                it, and for a record the fields its gaps name). A declaration the data no longer supports fails the
//                build (stale), so a finished read cannot stay labelled pending. An entry that also has a real gap
//                (e.g. an item no source names) stays a source-data gap, with the pending part listed beside it.
//   in_scope     false for content outside Iteration Three (rules.json out_of_scope, e.g. the Lith Harbor chair).
import { entryKey } from '../sources/parse.mjs';

export const FORMAT = 3;
/**
 * The excluded_kuro_only reason tools/sources/drops_merge.mjs gives a KuroDB row that matches no member. Any other
 * reason is a crosswalk "candidate": a row that may be a member but was not accepted (decision D3-8).
 */
export const KURO_ONLY_REASON = 'not on the membership list (KuroDB never adds members)';
/** How many passing checks an entry lists in the JSON (all are counted; failing ones are always all listed). */
export const EVIDENCE_LISTED = 5;
export const STATES = ['missing', 'partial', 'implemented', 'verified'];

/**
 * The categories, in manifest order: [id, title]. The brief's list ("Iteration Three Core Objective"), then the rows
 * of its Definition of Done that are not one canonical record each (rules.json `mechanics` rows name their category),
 * then the validator's own requirements.
 */
export const CATEGORIES = [
  ['maps', 'Maps'], ['portals', 'Portals'], ['monster-species', 'Monster species'],
  ['monster-populations', 'Monster populations'], ['monster-spawn-rules', 'Monster spawn rules'],
  ['monster-stats', 'Monster stats'], ['monster-drops', 'Monster drops'], ['meso-drops', 'Meso drops'],
  ['items', 'Items (Etc and Set-up)'], ['equipment', 'Equipment'], ['consumables', 'Consumables'], ['npcs', 'NPCs'],
  ['shops', 'Shops'], ['quests', 'Quests'], ['quest-chains', 'Quest chains'], ['quest-objectives', 'Quest objectives'],
  ['quest-rewards', 'Quest rewards'], ['beginner-skills', 'Beginner skills and mechanics'], ['breakables', 'Breakables'],
  ['chairs', 'Chairs'], ['map-mechanics', 'Map mechanics'],
  ['monster-behaviour', 'Monster behaviour, hit areas and spawning (Phases 5-6)'],
  ['drop-rules', 'Drop rules (Drop Testing, placeholder removal)'],
  ['persistence', 'Persistence (Phase 14)'],
  ['ui', 'UI and world feedback (Phases 11-12, quest log, skill UI)'],
  ['playthrough', 'Clean-character playthrough (Definition of Done: Gameplay)'],
  ['cross-reference-validation', 'Cross-reference validation (Phase 16)'],
  ['canonical-verification', 'Canonical verification (Phase 17, probability handling)'],
];

/** Categories whose verified state needs real-game (playtest) evidence. A rules.json row can also ask for it (real_game). */
export const REAL_GAME_CATEGORIES = new Set(['quests', 'quest-objectives', 'quest-rewards', 'quest-chains', 'playthrough']);

/** Categories a rules.json `mechanics` row may name (the brief's categories and the Definition of Done rows). */
const RULE_ROW_CATEGORIES = new Set(CATEGORIES.map(([id]) => id).filter((id) => !['cross-reference-validation', 'canonical-verification'].includes(id)));

const byKey = (a, b) => (a.key < b.key ? -1 : a.key > b.key ? 1 : 0);
const sortedKeys = (o) => Object.keys(o || {}).sort();
const arr = (v) => (Array.isArray(v) ? v : []);

/**
 * Builds the manifest.
 *   canonical   {domain: {id: record}}            (game/data/canonical, without canonical_sources)
 *   miso        {"<folder>/<basename>" or "<basename>": data}   (game/data/misostory)
 *   rules       tools/parity/rules.json
 *   runtime     {files: Set of repo paths, read(path) -> text}  (what exists in game/scripts)
 *   provenance  docs/provenance_report.json or null
 *   tests       [{file (the evidence file), doc (TEST_EVIDENCE_OUT document)}]
 *   playtests   [{file, doc (report.json)}]
 */
export function buildParity({ canonical, miso, rules, runtime, provenance = null, tests = [], playtests = [] }) {
  const tagStats = [];
  const refused = [];
  const worldTest = (file) => {
    const p = `game/tests/unit/${file}`;
    return !!runtime?.files?.has(p) && needsWorld(runtime.read(p));
  };
  const evidence = collectEvidence(tests, playtests, arr(rules.playtest_tags), tagStats, { worldTest, refused });
  const findings = recordFindings(provenance);
  const runtimeOf = (spec) => runtimeState(spec, runtime);
  const categoryRuntime = Object.fromEntries(CATEGORIES.map(([id]) => [id, runtimeOf(rules.categories?.[id]?.runtime)]));
  const ctx = { canonical, miso, rules, evidence, findings, categoryRuntime, runtimeOf, unmatchedCandidates: [] };
  const entries = enumerate(ctx);
  const undeclaredPending = applyPendingReads(entries, rules, canonical);
  // A key names exactly one entry: evidence tagged with a shared key would silently count for every entry holding it.
  const seenKeys = new Set();
  const duplicateKeys = new Set();
  for (const e of entries) (seenKeys.has(e.key) ? duplicateKeys : seenKeys).add(e.key);
  if (duplicateKeys.size) throw new Error(`duplicate parity keys: ${[...duplicateKeys].sort().join(', ')}`);
  // A hand-declared alias (a rules.json row's `accepts`) must name nothing else: not another entry's key, and not an
  // alias of another row. (Generated entries accept their parent's key on purpose: an objective accepts its quest.)
  const aliasOwner = new Map();
  for (const e of entries) {
    for (const a of arr(e.rule_accepts)) {
      if (seenKeys.has(a)) throw new Error(`rules.json: ${e.key} accepts ${a}, which is the key of another entry`);
      if (aliasOwner.has(a)) throw new Error(`rules.json: ${a} is accepted by both ${aliasOwner.get(a)} and ${e.key}`);
      aliasOwner.set(a, e.key);
    }
    delete e.rule_accepts;
  }
  const accepted = new Set(entries.flatMap((e) => e.accepts));
  // Chains are derived from their member quests once those have states.
  const byKeyMap = new Map(entries.map((e) => [e.key, e]));
  const out = [];
  for (const [id, title] of CATEGORIES) {
    const list = entries.filter((e) => e.category === id).sort(byKey);
    for (const e of list) finish(e, ctx, byKeyMap);
    out.push({ category: id, title, runtime: categoryRuntime[id], entries: list });
  }
  const totals = totalsOf(out);
  return {
    format: FORMAT,
    generated_by: 'node tools/parity/build_parity.mjs',
    rule: RULE_TEXT,
    inputs: {
      tests: tests.map((t) => {
        const mine = refused.filter((x) => x.evidence === t.file);
        return { file: t.file, run_at: t.doc.run_at ?? null, commit: t.doc.commit ?? null, dirty: t.doc.dirty ?? null,
          world_present: typeof t.doc.world_present === 'boolean' ? t.doc.world_present : null, totals: t.doc.totals ?? null,
          world_refused: { tests: mine.length, keys: [...new Set(mine.flatMap((x) => x.keys))].sort() } };
      }),
      playtests: playtests.map((p) => ({ file: p.file, scenario: p.doc.scenario ?? null, result: p.doc.result ?? null, seed: p.doc.seed ?? null,
        ...gitOf(p.doc),
        checks: arr(p.doc.checks).length, tagged_checks: arr(p.doc.checks).filter((c) => arr(c.parity).length).length,
        rule_tagged_checks: tagStats.filter((s) => s.file === p.file).reduce((n, s) => n + s.matched, 0),
        failed_checks: arr(p.doc.checks).filter((c) => !c.soft && !c.ok).map((c) => `#${c.i ?? '?'} ${c.name}`),
        // Only the clean-character playthrough's reports say whether they are a clean run (and why not).
        ...(p.doc.scenario === 'playthrough' ? { clean_run: cleanRun(p.doc), not_clean_because: cleanRunProblems(p.doc) } : {}) })),
      playtest_tag_rules_unmatched: unmatchedTagRules(tagStats),
      provenance: provenance ? { errors: provenance.validation?.errors ?? null, warnings: provenance.validation?.warnings ?? null,
        records: provenance.counts?.records ?? null } : null,
      unknown_evidence_keys: [...evidence.keys()].filter((k) => !byKeyMap.has(k) && !accepted.has(k)).sort(),
      // Entries a drop record marks pending (an excluded KuroDB candidate row) that rules.json does not declare yet.
      undeclared_pending_reads: undeclaredPending,
      // Excluded KuroDB candidate rows whose member could not be found in the record's entries (their notes).
      unmatched_kuro_candidates: ctx.unmatchedCandidates.sort(),
    },
    totals,
    source_data_gaps: sourceDataGaps(out),
    pending_source_reads: pendingSourceReads(out),
    categories: out,
  };
}

export const RULE_TEXT = {
  missing: 'The runtime the category or mechanic needs is absent (tools/parity/rules.json declares the files or code markers).',
  partial: 'The runtime exists but the entry has an open issue: a validation error on its record, a placeholder value, a missing item definition, an unresolved value that is not a source-data gap, a failing tagged check, or (a canonical-verification row) shipped data not yet in the state the row describes (tools/parity/rules.json requires: the tests prove the validator rule, not the data).',
  implemented: 'Runtime present, data valid, every unresolved value a documented source-data gap, but no passing check tagged with the key.',
  verified: 'As implemented, plus at least one passing check tagged with the key (or an accepted parent key or alias) and no failing one, in the evidence given. Quests, objectives and rewards need a passing playtest (real-game) check; quest chains follow their own rule (chains, below); the clean-character playthrough rows need one from a clean run (a passing report, strict mode ok, no console or api step in the report, and the departure boundary reached: its final boundary check passed and no PLAYTHROUGH_STOP flag); a drop probability is verified only when its sources resolve.',
  chains: 'A quest chain (chain:<first quest>) is derived from its member quests: missing when a member is missing, partial when a member is partial or a check tagged with the chain key fails, verified only when every member quest is verified (each by its own real-game checks) and at least one passing real-game check is tagged with the chain key: a link of the chain, the quest runner\'s "<quest>: its follow-up <next> (...) is available" check made right after the predecessor was completed through play (tools/parity/rules.json playtest_tags give the chain key); otherwise implemented.',
  source_data_gap: 'The sources were read and do not give a value the entry needs (the KuroDB page has no chance for a member, no meso amount, no MeowDB rule for a mechanic): the entry is excused from the exit criterion.',
  pending_source_read: 'A source publishes a value the entry needs on a page that has not been read yet (for example KuroDB item 2040705, or a MeowDB item page only the item API of which was captured). Unlike a source-data gap it is not excused: the entry stays partial and counts as open for the exit criterion until the page is read and the data updated. tools/parity/rules.json pending_source_reads names the read for each; an excluded KuroDB candidate row in a drop record makes its member pending even when undeclared.',
  in_scope: 'false for content outside Iteration Three (rules.json out_of_scope).',
  evidence: 'A unit test declares the keys it proves in its file\'s parity_keys(); a playtest check carries them in report.json (checks[].parity), or tools/parity/rules.json playtest_tags gives them to the checks of a scenario whose names match a pattern (hand-reviewed: only checks that prove the key). A soft check is never evidence.',
};

// --- evidence ----------------------------------------------------------------------------------------------------

/**
 * The keys a rules.json playtest_tags rule gives a check name, or null when the rule does not apply. A rule is
 * {scenario: name | [names], match: regex source (on the check name), keys: [templates], why}; a template may use the
 * match's groups ($1 .. $9).
 */
export function tagKeysFor(rule, scenario, name) {
  const scenarios = Array.isArray(rule.scenario) ? rule.scenario : [rule.scenario];
  if (!scenarios.includes(scenario)) return null;
  const m = new RegExp(rule.match).exec(String(name));
  if (!m) return null;
  return arr(rule.keys).map((t) => String(t).replace(/\$(\d)/g, (_, g) => m[Number(g)] ?? ''));
}

/**
 * key -> {passed: [...], failed: [...]} from unit test evidence and playtest checks (hard checks only). Playtest checks
 * keep their own parity keys and gain those of every matching rules.json playtest_tags rule (each key once per check).
 * tagStats (optional, filled in) receives one {file, rule, matched} per report and rule of its scenario; a rule that
 * matches no check in any report of its scenario is what playtest_tag_rules_unmatched lists (unmatchedTagRules).
 */
export function collectEvidence(tests, playtests, tagRules = [], tagStats = null, { worldTest = null, refused = null } = {}) {
  const ev = new Map();
  const add = (key, ok, item) => {
    if (!ev.has(key)) ev.set(key, { passed: [], failed: [] });
    ev.get(key)[ok ? 'passed' : 'failed'].push(item);
  };
  for (const t of tests) {
    for (const r of arr(t.doc.tests)) {
      // A test that needs the exported world passes with a SKIP line without it: its keys count only from a run that
      // recorded the world present (contract C6 world_present; older evidence records nothing, so it does not count).
      const needs = typeof r.needs_world === 'boolean' ? r.needs_world : !!worldTest?.(String(r.file));
      if (needs && t.doc.world_present !== true) {
        if (arr(r.parity).length) refused?.push({ evidence: t.file, test: `${String(r.file).replace(/\.gd$/, '')}::${r.name}`, keys: arr(r.parity) });
        continue;
      }
      for (const k of arr(r.parity)) add(k, !!r.ok, { kind: 'unit', id: `${String(r.file).replace(/\.gd$/, '')}::${r.name}` });
    }
  }
  for (const p of playtests) {
    const scenario = p.doc.scenario ?? null;
    const clean = cleanRun(p.doc);
    const rules = arr(tagRules).map((rule, i) => ({ rule, i, matched: 0 }))
      .filter((r) => (Array.isArray(r.rule.scenario) ? r.rule.scenario : [r.rule.scenario]).includes(scenario));
    for (const c of arr(p.doc.checks)) {
      if (c.soft) continue; // a soft check is a warning, never evidence
      const keys = new Set(arr(c.parity));
      for (const r of rules) {
        const extra = tagKeysFor(r.rule, scenario, c.name);
        if (!extra) continue;
        r.matched++;
        for (const k of extra) keys.add(k);
      }
      for (const k of [...keys].sort()) add(k, !!c.ok, { kind: 'playtest', id: `${scenario ?? p.file}#${c.i ?? '?'} ${c.name}`, ...(clean ? { clean: true } : {}) });
    }
    if (tagStats) for (const r of rules) tagStats.push({ file: p.file, scenario, rule: `${r.i}: ${r.rule.match}`, matched: r.matched });
  }
  return ev;
}

/**
 * What marks a unit test file as needing the exported world (game/tests/test_runner.gd WORLD_MARKER): its SKIP line
 * says "run with INCLUDE_WORLD=1". Evidence entries carry needs_world (format 2); for older evidence the generator reads
 * the test file itself.
 */
export const WORLD_MARKER = 'INCLUDE_WORLD';
export const needsWorld = (source) => String(source ?? '').includes(WORLD_MARKER);

/** A playtest report's provenance (report.json "git", contract C6): {commit, dirty, mixed, reused_copy}, nulls when absent. */
export function gitOf(report) {
  const g = report?.git && typeof report.git === 'object' ? report.git : {};
  return { commit: g.commit ?? null, dirty: typeof g.dirty === 'boolean' ? g.dirty : null, mixed: g.mixed === true, reused_copy: g.reused_copy === true };
}

/**
 * The clean-character playthrough's final boundary check (game/tools/playtest/scenarios/playthrough.gd `_finish`): it
 * is made only after every step of the route ran, and passes only when Shanks' departure flag is set. A run without
 * it passing never reached the departure boundary (the brief's end of Maple Island).
 */
export const DEPARTURE_BOUNDARY_CHECK = 'ready to depart: the End of Maple Island screen reached in Southperry';
/** What scenarios/playthrough.gd leaves in a report that PLAYTHROUGH_STOP=<step> ended early: a carry key and a note. */
export const STOP_CARRY_KEY = 'stopped_after';
const STOP_NOTE = /(?:^|\] )PLAYTHROUGH_STOP=/;

/**
 * Why a report is not a clean-character run ([] when it is one): it must pass (result PASS: a run stopped by a failed
 * step is not one), run in strict mode with strict ok, hold not one console or api step in the whole report (no setup
 * either), so everything after character creation was played with real input, and have reached the departure
 * boundary: the final boundary check (DEPARTURE_BOUNDARY_CHECK) passed as a hard check, and no stop flag (a
 * PLAYTHROUGH_STOP development run ends early with a passing report). Only such a report's checks can verify the
 * clean-character playthrough rows (brief Definition of Done, Gameplay: "From a completely clean character" ... "arrive
 * ready to depart"); several of those rows are tagged on per-quest or per-level checks that a run stopped early still
 * passes.
 */
export function cleanRunProblems(report) {
  const out = [];
  const steps = report?.counts?.steps ?? {};
  if (report?.result !== 'PASS') out.push(`result ${report?.result ?? '?'}, not PASS`);
  if (report?.strict?.enabled !== true || report?.strict?.ok !== true) out.push('strict mode off or not ok');
  if (Number(steps.console ?? 1) !== 0) out.push(`${steps.console ?? '?'} console step(s)`);
  if (Number(steps.api ?? 1) !== 0) out.push(`${steps.api ?? '?'} api step(s)`);
  const stopped = report?.carry?.[STOP_CARRY_KEY] ?? null;
  const stopNote = arr(report?.notes).find((n) => STOP_NOTE.test(String(n)));
  if (stopped != null || stopNote) out.push(`stopped early (PLAYTHROUGH_STOP${stopped != null ? ` after step '${stopped}'` : ''})`);
  if (!arr(report?.checks).some((c) => !c.soft && c.ok && c.name === DEPARTURE_BOUNDARY_CHECK)) {
    out.push(`the departure boundary was not reached (no passing check "${DEPARTURE_BOUNDARY_CHECK}")`);
  }
  return out;
}

/** A clean-character run: no cleanRunProblems. */
export function cleanRun(report) {
  return cleanRunProblems(report).length === 0;
}

/**
 * The playtest_tags rules that matched no check in any of the reports of their scenario (renamed checks would
 * otherwise silently stop counting): [{rule, scenarios, reports}]. A rule whose scenario has no report is not listed.
 */
export function unmatchedTagRules(tagStats) {
  const byRule = new Map();
  for (const s of tagStats) {
    const r = byRule.get(s.rule) ?? { rule: s.rule, scenarios: new Set(), reports: 0, matched: 0 };
    r.scenarios.add(s.scenario);
    r.reports++;
    r.matched += s.matched;
    byRule.set(s.rule, r);
  }
  return [...byRule.values()].filter((r) => r.matched === 0)
    .map((r) => ({ rule: r.rule, scenarios: [...r.scenarios].sort(), reports: r.reports }));
}

/** "domain/id" -> [error messages] from the provenance report's validation findings. */
function recordFindings(provenance) {
  const out = new Map();
  for (const f of arr(provenance?.validation?.findings)) {
    if (f.severity !== 'error') continue;
    const k = `${f.domain}/${f.id}`;
    if (!out.has(k)) out.set(k, []);
    out.get(k).push(`[${f.check}] ${f.message}`);
  }
  return out;
}

// --- runtime declarations ----------------------------------------------------------------------------------------

/**
 * {state: "present" | "partial" | "absent", files: [...], missing: [...], note}. A spec is
 * {files: [paths or globs], contains: [{glob, text}], partial: {files, contains, issue}}: every file must exist and
 * every marker must be found in some file matching its glob. With no spec the category needs no runtime of its own.
 */
export function runtimeState(spec, runtime) {
  if (!spec) return { state: 'present', files: [], missing: [], note: 'no runtime of its own' };
  const check = (s) => {
    const found = [];
    const missing = [];
    for (const f of arr(s.files)) {
      const hits = matchFiles(f, runtime.files);
      if (hits.length) found.push(...hits.slice(0, 3));
      else missing.push(f);
    }
    for (const c of arr(s.contains)) {
      const hit = matchFiles(c.glob, runtime.files).find((f) => runtime.read(f).includes(c.text));
      if (hit) found.push(`${hit} (${JSON.stringify(c.text)})`);
      else missing.push(`${c.glob} containing ${JSON.stringify(c.text)}`);
    }
    return { found, missing };
  };
  const main = check(spec);
  if (main.missing.length === 0) return { state: 'present', files: main.found, missing: [], note: spec.note ?? null };
  if (spec.partial) {
    const p = check(spec.partial);
    if (p.missing.length === 0) return { state: 'partial', files: p.found, missing: main.missing, note: spec.partial.issue ?? null };
  }
  return { state: 'absent', files: main.found, missing: main.missing, note: spec.note ?? null };
}

/** Repo paths matching a path or a glob ("**" any folders, "*" within a name). */
export function matchFiles(pattern, files) {
  if (!/[*?]/.test(pattern)) return files.has(pattern) ? [pattern] : [];
  const re = new RegExp('^' + pattern.split('**/').map((part) => part.split('*').map(escapeRe).join('[^/]*')).join('(?:.*/)?') + '$');
  return [...files].filter((f) => re.test(f)).sort();
}
const escapeRe = (s) => s.replace(/[.+^${}()|[\]\\?]/g, '\\$&');

// --- enumeration -------------------------------------------------------------------------------------------------

function entry(category, key, name, extra = {}) {
  return { category, key, name, accepts: [], record: null, issues: [], source_gaps: [], source_data_gap: false,
    pending_source_read: false, pending_reads: [], adaptations: [], notes: [], ...extra };
}

function recordGaps(rec) {
  return arr(rec?.gaps).map(String);
}

/** The adaptation every spawn-rule row lists: the switch that decides whether the canonical mob rate is applied. */
export const MOB_RATE_ADAPTATION = 'game/data/misostory/presentation.json#map_mob_rate';

/** presentation.json map_mob_rate as {apply, verified}, or null when the file or the section is absent. */
function mobRateAdaptation(miso) {
  const m = miso?.presentation?.map_mob_rate;
  return m && typeof m === 'object' ? { apply: m.apply === true, verified: m.verified ?? null } : null;
}

/**
 * A rules.json adaptation reference: "game/data/misostory/<file>.json", or "<file>.json#<key>" for one top-level
 * section of it. Returns the reference when the file exists, null when it does not (the row lists no adaptation), and
 * throws when the file exists without the named section (a stale reference).
 */
export function adaptationRef(ref, miso) {
  const [file, section] = String(ref).split('#');
  const data = miso[file.replace(/^game\/data\/misostory\//, '').replace(/\.json$/, '')];
  if (!data) return null;
  if (section !== undefined && !(typeof data === 'object' && Object.hasOwn(data, section))) {
    throw new Error(`rules.json: adaptation ${ref}: ${file} has no section ${JSON.stringify(section)}`);
  }
  return ref;
}

function enumerate(ctx) {
  const { canonical: C, miso, rules } = ctx;
  const out = [];
  const maps = C.maps || {};
  const monsters = C.monsters || {};
  const items = C.items || {};
  const quests = C.quests || {};
  const drops = C.drops || {};
  const name = (domain, id) => C[domain]?.[id]?.name ?? id;
  const adaptationOf = (folder, id) => (miso[`${folder}/${id}`] ? [`game/data/misostory/${folder}/${id}.json`] : []);

  for (const id of sortedKeys(maps)) {
    const m = maps[id];
    out.push(entry('maps', `map:${id}`, `${m.name} (${id})`, { record: `maps/${id}`, source_gaps: recordGaps(m), adaptations: adaptationOf('maps', id) }));
    for (const p of arr(m.portals)) {
      out.push(entry('portals', `portal:${id}/${p.name}`, `${m.name} ${p.name} -> ${name('maps', p.to_map_id)}`,
        { record: `maps/${id}`, accepts: [] }));
    }
    const species = new Map();
    for (const s of arr(m.monsters)) species.set(String(s.id), s);
    if (species.size) {
      // The canonical rule names the map's MeowDB mob rate; whether the runtime applies it is the MisoStory switch
      // presentation.json map_mob_rate (an owner decision between MeowDB pages), so the row says which and lists it.
      const mobRate = mobRateAdaptation(miso);
      const rateText = `MeowDB mob rate ${m.mob_rate ?? '?'}${mobRate ? ` (${mobRate.apply ? 'applied' : 'not applied'}: presentation.json map_mob_rate)` : ''}`;
      const sr = entry('monster-spawn-rules', `spawn-rule:${id}`, `${m.name}: ${arr(m.spawns).length} spawn points, ${rateText}`,
        { record: `maps/${id}`, adaptations: mobRate ? [MOB_RATE_ADAPTATION] : [] });
      if (mobRate) {
        sr.notes.push(`mob rate ${m.mob_rate ?? '?'} ${mobRate.apply ? 'applied' : 'deliberately not applied'} (presentation.json map_mob_rate.apply ` +
          `${mobRate.apply}, verified: ${mobRate.verified}; capacity = floor(spawn points x player scalar)${mobRate.apply ? ' x mob rate, capped at the spawn points' : ''})`);
      }
      out.push(sr);
    }
    for (const [mob, s] of species) {
      out.push(entry('monster-populations', `population:${id}/${mob}`, `${m.name}: ${s.name} x${s.count ?? '?'}`,
        { record: `maps/${id}`, accepts: [`spawn-rule:${id}`] }));
    }
    // A placement accepts its breakable's key and the map-wide key of a test that checks every placement on the map.
    arr(m.reactors).forEach((r, i) => {
      out.push(entry('breakables', `placement:${id}/${i}`, `${r.name ?? r.id} placement ${i} on ${m.name} (respawn ${r.respawn_s ?? '?'} s)`,
        { record: `maps/${id}`, accepts: [`breakable:${r.id}`, `breakable-placement:${id}`] }));
    });
    // Every playable map has its own minimap (brief Phase 11).
    out.push(entry('ui', `minimap:${id}`, `Minimap of ${m.name} (${id}): player, map shape, exits, NPCs, name`, { record: `maps/${id}` }));
  }
  for (const id of sortedKeys(monsters)) {
    const m = monsters[id];
    out.push(entry('monster-species', `monster:${id}`, m.name, { record: `monsters/${id}`, source_gaps: recordGaps(m), adaptations: adaptationOf('monsters', id) }));
    out.push(entry('monster-stats', `monster-stats:${id}`, `${m.name}: level ${m.level}, HP ${m.hp}, EXP ${m.exp}`,
      { record: `monsters/${id}`, accepts: [`monster:${id}`] }));
  }
  for (const id of sortedKeys(drops)) {
    const t = drops[id];
    const owner = t.owner || {};
    const breakable = owner.kind === 'breakable';
    const v2 = t.schema_version === 2;
    // An entry without its own key (schema v1) is keyed by the slug of its name (tools/sources/parse.mjs entryKey, as
    // v2 keys are made). Two v1 entries may share a name (Red Snail: Red Cloth Pants 1168 and 1177), so every entry of
    // a shared slug gets its item id appended ("red-cloth-pants-1168"): no entry silently owns the bare key.
    const slugOf = (e) => {
      try { return entryKey(e.name ?? e.item_name ?? e.item_id); } catch { return String(e.item_id); }
    };
    const slugCount = new Map();
    for (const e of arr(t.entries)) if (e.key == null) slugCount.set(slugOf(e), (slugCount.get(slugOf(e)) ?? 0) + 1);
    // An entry also accepts drop:<owner>/<item id> (the form playtest checks use) when that item id is its own alone.
    const idCount = new Map();
    for (const e of arr(t.entries)) if (e.item_id != null) idCount.set(String(e.item_id), (idCount.get(String(e.item_id)) ?? 0) + 1);
    // KuroDB rows excluded as a possible match for a member (drops_merge.mjs writes the member's note "KuroDB candidate
    // row <name> (<kuro id>, ..."): that member's chance is published but unread, a pending read and not a gap.
    const candidates = v2 ? arr(t.excluded_kuro_only).filter((x) => x?.reason && x.reason !== KURO_ONLY_REASON) : [];
    const candidateOf = (e) => candidates.filter((x) => arr(e.notes).some((n) => String(n).startsWith(`KuroDB candidate row ${x.name} (${x.kuro_item_id},`)));
    for (const x of candidates) {
      if (!arr(t.entries).some((e) => candidateOf(e).includes(x))) ctx.unmatchedCandidates.push(`drops/${id}: KuroDB ${x.kuro_item_id} ${x.name}`);
    }
    for (const e of arr(t.entries)) {
      const label = e.name ?? e.item_name ?? e.item_id;
      let key = e.key;
      if (key == null) {
        key = slugOf(e);
        if (slugCount.get(key) > 1) key = `${key}-${e.item_id}`;
      }
      const byId = e.item_id != null && idCount.get(String(e.item_id)) === 1 && String(e.item_id) !== key ? [`drop:${id}/${e.item_id}`] : [];
      const ent = entry(breakable ? 'breakables' : 'monster-drops', `drop:${id}/${key}`, `${name(breakable ? 'breakables' : 'monsters', owner.id)}: ${label}`,
        { record: `drops/${id}`, item_id: e.item_id ?? null, accepts: byId });
      if (!v2) {
        ent.issues.push('schema v1: the chance is null and the runtime rolls a placeholder rate (misostory/drop_rates.json); membership is MeowDB community votes, not the decided source (D3-6)');
      } else {
        if (e.item_resolution?.state !== 'resolved' || e.item_id == null) {
          ent.source_data_gap = true;
          ent.source_gaps.push(`item ${e.item_resolution?.state ?? 'unresolved'}${arr(e.item_resolution?.candidates).length ? ` (candidates ${e.item_resolution.candidates.join(', ')})` : ''}: never drops`);
        }
        if (e.chance_state !== 'resolved') {
          const cand = candidateOf(e);
          if (cand.length) {
            for (const x of cand) {
              ent.pending_reads.push({ read: `KuroDB item ${x.kuro_item_id} ("${x.name}", ${x.raw_value ?? '?'} on this monster's page)`,
                resolves: 'whether that row is this member, and so its chance', decision: null, detail: x.reason, declared: false });
            }
          } else {
            ent.source_data_gap = true;
            ent.source_gaps.push('no KuroDB chance for this member: never drops');
          }
        }
        if (e.quest_gate) ent.notes.push(`quest-gated to ${e.quest_gate.quest_id}`);
      }
      if (e.item_id != null && !items[e.item_id]) ent.issues.push(`item ${e.item_id} has no definition`);
      out.push(ent);
    }
    if (!breakable) {
      const ent = entry('meso-drops', `meso:${id}`, `${name('monsters', owner.id)} mesos`, { record: `drops/${id}` });
      const meso = t.meso;
      if (!v2) ent.issues.push('schema v1: the meso amount and chance come from the placeholders of misostory/drop_rates.json');
      else if (meso == null) ent.notes.push('drops no mesos');
      else {
        if (meso.amount_state !== 'resolved') { ent.source_data_gap = true; ent.source_gaps.push('meso amount unresolved: the meso bag never drops'); }
        if (meso.chance_state !== 'resolved') { ent.source_data_gap = true; ent.source_gaps.push('meso chance unresolved: the meso bag never drops'); }
      }
      out.push(ent);
    }
  }
  for (const id of sortedKeys(items)) {
    const it = items[id];
    const cat = it.type === 'Equip' ? 'equipment' : it.type === 'Use' ? 'consumables' : 'items';
    out.push(entry(cat, `item:${id}`, `${it.name} (${it.type}${it.subtype ? ` / ${it.subtype}` : ''})`, { record: `items/${id}`, source_gaps: recordGaps(it) }));
  }
  for (const id of sortedKeys(C.npcs || {})) {
    const n = C.npcs[id];
    out.push(entry('npcs', `npc:${id}`, n.name, { record: `npcs/${id}`, source_gaps: recordGaps(n), adaptations: [...adaptationOf('npcs', id), ...adaptationOf('dialogue', id)] }));
  }
  for (const id of sortedKeys(C.shops || {})) {
    const s = C.shops[id];
    out.push(entry('shops', `shop:${id}`, `${s.name} (${s.npc_name ?? s.npc_id}), ${arr(s.items).length} items`,
      { record: `shops/${id}`, source_gaps: recordGaps(s) }));
    for (const line of arr(s.items)) if (!items[line.item_id]) out[out.length - 1].issues.push(`stock item ${line.item_id} has no definition`);
  }
  const chains = new Map();
  for (const id of sortedKeys(quests)) {
    const q = quests[id];
    const qe = entry('quests', `quest:${id}`, q.name, { record: `quests/${id}`, source_gaps: recordGaps(q), adaptations: adaptationOf('quests', id) });
    if (q.missable === true) qe.notes.push('missable (live quest tracker)');
    out.push(qe);
    const ob = q.objectives || {};
    const targetOf = (o) => o.mob_id ?? o.item_id ?? o.npc_id ?? o.map_id ?? o.type ?? '?';
    for (const kind of Object.keys(ob)) {
      for (const o of arr(ob[kind])) {
        const label = o.name ?? o.type ?? targetOf(o);
        out.push(entry('quest-objectives', `objective:${id}/${kind}/${targetOf(o)}${kind === 'npc_talk' ? `/${o.purpose ?? ''}` : ''}`,
          `${q.name}: ${kind.replace(/_/g, ' ')} ${label}${o.count != null ? ` x${o.count}` : ''}`, { record: `quests/${id}`, accepts: [`quest:${id}`] }));
      }
    }
    const rw = q.rewards || {};
    const reward = (suffix, label) => out.push(entry('quest-rewards', `reward:${id}/${suffix}`, `${q.name}: ${label}`, { record: `quests/${id}`, accepts: [`quest:${id}`] }));
    if (rw.exp) reward('exp', `${rw.exp} EXP`);
    if (rw.mesos) reward('mesos', `${rw.mesos} mesos`);
    if (rw.fame) reward('fame', `${rw.fame} fame`);
    for (const it of arr(rw.items)) reward(`item/${it.item_id}`, `${it.name ?? it.item_id} x${it.count ?? 1}`);
    arr(rw.random).forEach((g, i) => reward(`random/${i}`, `one of ${arr(g.items).map((x) => x.name ?? x.item_id).join(', ')}`));
    arr(rw.selection).forEach((g, i) => reward(`selection/${i}`, `a choice of ${arr(g.items).map((x) => x.name ?? x.item_id).join(', ')}`));
    const line = q.quest_line;
    if (line && arr(line.steps).length > 1) {
      const first = String(line.steps[0].quest_id);
      if (!chains.has(first)) chains.set(first, arr(line.steps).map((s) => String(s.quest_id)));
    }
  }
  for (const [first, members] of chains) {
    out.push(entry('quest-chains', `chain:${first}`, `${members.map((m) => quests[m]?.name ?? m).join(' -> ')}`, { members }));
  }
  for (const fid of sortedKeys(C.formulas || {})) {
    const f = C.formulas[fid];
    for (const s of arr(f.skills)) {
      out.push(entry('beginner-skills', `skill:${s.skill_id}`, `${s.name} (max level ${s.max_level ?? '?'})`, { record: `formulas/${fid}` }));
    }
    for (const ch of arr(f.chairs)) {
      out.push(entry('chairs', `chair:${ch.item_id}`, `${ch.name ?? items[ch.item_id]?.name ?? ch.item_id} (${ch.how_to_get ?? ''})`,
        { record: `items/${ch.item_id}` }));
    }
  }
  for (const id of sortedKeys(C.breakables || {})) {
    const b = C.breakables[id];
    out.push(entry('breakables', `breakable:${id}`, `${b.name} (breaks in ${b.hits_to_break ?? '?'} hits)`, { record: `breakables/${id}`, source_gaps: recordGaps(b) }));
  }
  // A rules.json row: {key, name, brief, category (default map-mechanics), runtime (its own declaration; a row outside
  // map-mechanics without one uses its category's), accepts (aliases: test keys that prove the same thing),
  // real_game (needs a playtest check), source_gaps (the sources give no value: a documented source-data gap),
  // adaptations (misostory files)}.
  for (const m of arr(rules.mechanics)) {
    const category = m.category ?? 'map-mechanics';
    if (!RULE_ROW_CATEGORIES.has(category)) throw new Error(`rules.json: ${m.key} names an unknown category ${category}`);
    const ent = entry(category, m.key, m.name, { brief: m.brief ?? null, accepts: [...arr(m.accepts)], rule_accepts: arr(m.accepts),
      ...(typeof m.real_game === 'boolean' ? { real_game: m.real_game } : {}), adaptations: arr(m.adaptations).map((a) => adaptationRef(a, miso)).filter(Boolean) });
    if (m.runtime !== undefined || category === 'map-mechanics') ent.runtime_spec = m.runtime ?? null;
    if (arr(m.source_gaps).length) {
      ent.source_data_gap = true;
      ent.source_gaps.push(...arr(m.source_gaps).map(String));
    }
    if (m.note) ent.notes.push(String(m.note));
    out.push(ent);
  }
  for (const x of arr(rules.cross_reference)) {
    out.push(entry('cross-reference-validation', x.key, x.name, { brief: x.brief ?? null, accepts: [...arr(x.accepts)], rule_accepts: arr(x.accepts) }));
  }
  for (const x of arr(rules.canonical_verification)) {
    const ent = entry('canonical-verification', x.key, x.name, { brief: x.brief ?? null, accepts: [...arr(x.accepts)], rule_accepts: arr(x.accepts) });
    ent.issues.push(...dataRequirementIssues(x.requires, C));
    out.push(ent);
  }
  return out;
}

/**
 * Why the shipped data does not yet meet a canonical-verification row's `requires` (rules.json), as issues. Such a row
 * states a property of the data ("drop membership and chance are recorded from separate sources"); its tagged tests
 * prove the validator rule on fixtures, so the row stays partial until the data itself is in the required state.
 *   {drops_schema_version: N}   every drop record is schema N (contract C1: schema v2)
 */
export function dataRequirementIssues(requires, canonical) {
  const out = [];
  if (!requires || typeof requires !== 'object') return out;
  for (const k of Object.keys(requires).sort()) {
    if (k === 'drops_schema_version') {
      const want = requires[k];
      const behind = sortedKeys(canonical.drops).filter((id) => canonical.drops[id]?.schema_version !== want);
      if (behind.length) {
        out.push(`the shipped data is not there yet: drop record(s) ${behind.join(', ')} are not schema v${want} (contract C1); ` +
          'the passing tests prove the validator rule, not the shipped data');
      }
    } else {
      out.push(`unknown data requirement ${JSON.stringify(k)} in tools/parity/rules.json`);
    }
  }
  return out;
}

/**
 * Applies rules.json pending_source_reads and sets every entry's pending_source_read flag; returns the keys a drop
 * record marks pending (an excluded KuroDB candidate row) that are not declared. A declaration is
 *   {read: the page whose read resolves it, resolves: what it settles, decision: the log row (optional),
 *    fields: [record fields] (an entry other than a drop: each must still be named by one of the record's gaps)}
 * and fails the build when the data no longer supports it: a drop entry without an unread KuroDB candidate row, or a
 * record whose gaps no longer name a declared field (the read was done: remove the declaration). An entry with a real
 * source-data gap stays excused as one; its pending reads are listed beside it, but it is not flagged pending.
 */
export function applyPendingReads(entries, rules, canonical) {
  const byKey = new Map(entries.map((e) => [e.key, e]));
  const declared = rules.pending_source_reads ?? {};
  for (const key of Object.keys(declared).sort()) {
    const d = declared[key] ?? {};
    const e = byKey.get(key);
    if (!e) throw new Error(`rules.json pending_source_reads: ${key} names no entry`);
    if (!d.read || !d.resolves) throw new Error(`rules.json pending_source_reads: ${key} needs "read" and "resolves"`);
    const detected = e.pending_reads.filter((r) => !r.declared);
    const base = { read: String(d.read), resolves: String(d.resolves), decision: d.decision ?? null, declared: true };
    if (e.key.startsWith('drop:')) {
      if (!detected.length) {
        throw new Error(`rules.json pending_source_reads: ${key} is stale: its drop record has no unread KuroDB candidate row ` +
          'for it any more (the read was done or the entry resolved): remove the declaration');
      }
      e.pending_reads = [{ ...base, detail: detected.map((r) => r.detail).join('; ') }];
      continue;
    }
    const fields = arr(d.fields).map(String);
    if (!fields.length) throw new Error(`rules.json pending_source_reads: ${key} needs "fields" (the record fields its gaps name)`);
    const [domain, id] = String(e.record ?? '').split('/');
    const gaps = arr(canonical?.[domain]?.[id]?.gaps).map(String);
    const stale = fields.filter((f) => !gaps.some((g) => g.startsWith(f)));
    if (stale.length) {
      throw new Error(`rules.json pending_source_reads: ${key} is stale: record ${e.record ?? '?'} has no gap for ${stale.join(', ')} ` +
        'any more (the read was done): remove the declaration');
    }
    e.pending_reads.push({ ...base, fields, detail: gaps.filter((g) => fields.some((f) => g.startsWith(f))).join('; ') });
  }
  const undeclared = [];
  for (const e of entries) {
    if (e.pending_reads.some((r) => !r.declared)) undeclared.push(e.key);
    e.pending_source_read = !e.source_data_gap && e.pending_reads.length > 0;
  }
  return undeclared.sort();
}

// --- state ------------------------------------------------------------------------------------------------------

function finish(e, ctx, all) {
  const { rules, evidence, findings, categoryRuntime, runtimeOf } = ctx;
  const oos = rules.out_of_scope?.[e.key];
  e.in_scope = !oos;
  if (oos) e.notes.push(`out of scope: ${oos}`);
  const own = 'runtime_spec' in e;
  const rt = own ? runtimeOf(e.runtime_spec) : categoryRuntime[e.category];
  delete e.runtime_spec;
  if (own) e.runtime = rt;
  if (e.record && findings.has(e.record)) e.issues.push(...findings.get(e.record).map((m) => `validation: ${m}`));
  const keys = [e.key, ...e.accepts];
  const passed = [];
  const failed = [];
  for (const k of keys) {
    const ev = evidence.get(k);
    if (!ev) continue;
    passed.push(...ev.passed.map((x) => ({ ...x, key: k })));
    failed.push(...ev.failed.map((x) => ({ ...x, key: k })));
  }
  // Every failing check is listed; passing ones are counted and the first EVIDENCE_LISTED are listed (real-game
  // checks first), which keeps the JSON readable when a quest key carries hundreds of checks.
  const shown = [...passed.filter((p) => p.kind === 'playtest'), ...passed.filter((p) => p.kind !== 'playtest')].slice(0, EVIDENCE_LISTED);
  e.evidence = { passed_count: passed.length, failed_count: failed.length, passed: shown, failed };
  if (e.category === 'quest-chains') {
    // RULE_TEXT.chains: derived from the member quests, plus the chain's own real-game link checks.
    const members = e.members.map((m) => all.get(`quest:${m}`)).filter(Boolean);
    const states = members.map((m) => m.state);
    const links = passed.filter((p) => p.kind === 'playtest');
    if (failed.length) e.issues.push(`${failed.length} tagged check(s) failed`);
    if (rt.state === 'absent' || states.includes('missing')) e.state = 'missing';
    else if (states.length !== e.members.length || states.includes('partial') || failed.length) e.state = 'partial';
    else if (states.every((s) => s === 'verified') && links.length) e.state = 'verified';
    else e.state = 'implemented';
    e.notes.push(`members: ${e.members.map((m, i) => `${m} ${states[i] ?? 'absent'}`).join(', ')}`);
    if (e.state === 'implemented' && states.every((s) => s === 'verified')) {
      e.notes.push('needs a passing real-game check tagged with this key (a link of the chain: a follow-up available right after its predecessor was completed)');
    }
    return;
  }
  if (rt.state === 'absent') {
    e.state = 'missing';
    e.issues.push(`runtime missing: ${rt.missing.join('; ')}`);
    return;
  }
  if (rt.state === 'partial' && rt.note) e.issues.push(`runtime partial: ${rt.note}`);
  if (failed.length) e.issues.push(`${failed.length} tagged check(s) failed`);
  const needsRealGame = typeof e.real_game === 'boolean' ? e.real_game : REAL_GAME_CATEGORIES.has(e.category);
  // The clean-character playthrough rows count only checks of a clean run (cleanRun: PASS, strict, no console or api
  // step, the departure boundary reached and no stop flag).
  const needsClean = needsRealGame && e.category === 'playthrough';
  const real = needsRealGame ? passed.filter((p) => p.kind === 'playtest' && (!needsClean || p.clean)) : passed;
  if (e.issues.length) e.state = 'partial';
  else if (e.source_data_gap) e.state = 'partial';
  else if (e.pending_source_read) e.state = 'partial'; // a value still to be read: never verified, never excused
  else if (real.length) e.state = 'verified';
  else {
    e.state = 'implemented';
    if (needsClean) e.notes.push('needs a passing check tagged with this key in a clean-character playthrough report that is a clean run (passing, strict, no console or api step, the departure boundary reached, not stopped early)');
    else if (passed.length && needsRealGame) e.notes.push('unit-tested only: needs a real-game (playtest) check');
  }
}

function totalsOf(categories) {
  const blank = () => ({ missing: 0, partial: 0, implemented: 0, verified: 0, source_data_gap: 0, pending_source_read: 0, out_of_scope: 0, entries: 0 });
  const all = blank();
  const by = {};
  for (const c of categories) {
    const t = blank();
    for (const e of c.entries) {
      for (const tt of [t, all]) {
        tt.entries++;
        if (!e.in_scope) { tt.out_of_scope++; continue; }
        tt[e.state]++;
        if (e.source_data_gap) tt.source_data_gap++;
        if (e.pending_source_read) tt.pending_source_read++;
      }
    }
    by[c.category] = t;
  }
  // The exit criterion: every in-scope entry verified, except documented source-data gaps (a pending source read is
  // not one: it stays open until the page is read).
  const open = [];
  for (const c of categories) for (const e of c.entries) if (e.in_scope && e.state !== 'verified' && !e.source_data_gap) open.push(e.key);
  return { all, by_category: by, open_for_exit: open.length };
}

function sourceDataGaps(categories) {
  const out = [];
  for (const c of categories) {
    for (const e of c.entries) if (e.source_data_gap) out.push({ key: e.key, category: c.category, name: e.name, gaps: e.source_gaps });
  }
  return out;
}

/** The pending source reads (in scope or not), listed apart from the source-data gaps: [{key, category, name, reads}]. */
function pendingSourceReads(categories) {
  const out = [];
  for (const c of categories) {
    for (const e of c.entries) {
      if (e.pending_source_read) out.push({ key: e.key, category: c.category, name: e.name, in_scope: e.in_scope, reads: e.pending_reads });
    }
  }
  return out;
}

const readText = (r) => `read ${r.read}${r.decision ? ` (decision ${r.decision})` : ''} to settle ${r.resolves}`;

// --- markdown ---------------------------------------------------------------------------------------------------

const esc = (v) => String(v ?? '').replace(/\|/g, '\\|').replace(/\n/g, ' ');

export function toMarkdown(doc) {
  const L = [];
  L.push('# Maple Island parity manifest', '');
  L.push('Generated by `node tools/parity/build_parity.mjs` (see `--help`) from `game/data/canonical`, `game/data/misostory`,');
  L.push('[`provenance_report.json`](provenance_report.json), the unit test evidence (`TEST_EVIDENCE_OUT`) and playtest');
  L.push('`report.json` files. Do not edit: change the data, the code, the tests or `tools/parity/rules.json` and regenerate.');
  L.push('Machine-readable copy: [`maple_island_parity.json`](maple_island_parity.json).', '');
  L.push('## States', '');
  for (const s of [...STATES, 'chains', 'source_data_gap', 'pending_source_read', 'in_scope', 'evidence']) L.push(`- **${s}**: ${doc.rule[s]}`);
  L.push('- Parity keys are `<category>:<id>` (contract C6). A test file declares them in `parity_keys()`; a playtest check carries');
  L.push('  `parity`. "Implemented" is a declaration (`tools/parity/rules.json`: the runtime files or code markers per category');
  L.push('  and mechanic); only evidence makes an entry verified.', '');
  L.push('## Evidence used', '');
  if (!doc.inputs.tests.length && !doc.inputs.playtests.length) L.push('No evidence files were given.');
  const tree = (dirty) => (dirty === true ? 'dirty tree' : dirty === false ? 'clean tree' : 'tree state not recorded');
  for (const t of doc.inputs.tests) {
    const wr = t.world_refused ?? { tests: 0, keys: [] };
    L.push(`- Unit tests \`${t.file}\`: run ${t.run_at ?? '?'}, commit ${t.commit ?? '?'} (${tree(t.dirty)}), ` +
      `world ${t.world_present === true ? 'present' : t.world_present === false ? 'absent' : 'not recorded'}, ${t.totals?.tests ?? '?'} tests, ${t.totals?.failed ?? '?'} failed` +
      `${wr.tests ? `; ${wr.tests} world-dependent test(s) refused (the run did not record the world present): ${wr.keys.map((k) => `\`${k}\``).join(', ')}` : ''}`);
  }
  for (const p of doc.inputs.playtests) {
    L.push(`- Playtest \`${p.file}\`: ${p.scenario ?? '?'} seed ${p.seed ?? '?'}, ${p.result ?? '?'}, ` +
      `${p.commit ? `commit ${p.commit} (${tree(p.dirty)}${p.mixed ? ', several commits' : ''}${p.reused_copy ? ', reused copy' : ''})` : 'commit not recorded'}, ` +
      `${p.checks} checks (${p.tagged_checks} tagged by the scenario, ${p.rule_tagged_checks ?? 0} by rules.json playtest_tags)` +
      `${arr(p.failed_checks).length ? `; failed: ${p.failed_checks.map((f) => esc(f)).join('; ')}` : ''}` +
      `${p.clean_run === true ? '; a clean run (counts for the playthrough rows)' : p.clean_run === false ? `; not a clean run: ${esc(arr(p.not_clean_because).join('; '))}` : ''}`);
  }
  if (doc.inputs.provenance) L.push(`- Provenance report: ${doc.inputs.provenance.records} records, ${doc.inputs.provenance.errors} errors, ${doc.inputs.provenance.warnings} warnings`);
  if (doc.inputs.unknown_evidence_keys.length) L.push(`- Tagged keys that name no manifest entry: ${doc.inputs.unknown_evidence_keys.map((k) => `\`${k}\``).join(', ')}`);
  for (const u of arr(doc.inputs.playtest_tag_rules_unmatched)) {
    L.push(`- A playtest_tags rule matched no check in ${u.reports} report(s) of ${u.scenarios.join(', ')} (renamed checks?): \`${esc(u.rule)}\``);
  }
  if (arr(doc.inputs.undeclared_pending_reads).length) {
    L.push(`- Pending source reads a drop record marks that \`tools/parity/rules.json\` \`pending_source_reads\` does not declare: ${doc.inputs.undeclared_pending_reads.map((k) => `\`${k}\``).join(', ')}`);
  }
  if (arr(doc.inputs.unmatched_kuro_candidates).length) {
    L.push(`- Excluded KuroDB candidate rows whose member was not found: ${doc.inputs.unmatched_kuro_candidates.map((k) => esc(k)).join('; ')}`);
  }
  L.push('');
  L.push('How the evidence is made (each step writes git-ignored files under `_scratch/`):', '');
  L.push('1. `TEST_EVIDENCE_OUT=_scratch/ev/full.json ISOLATE=<name> INCLUDE_WORLD=1 bash scripts/test.sh`: the full unit suite.');
  L.push('   `INCLUDE_WORLD=1` is required: without the exported world the world tests (test_world_transitions,');
  L.push('   test_death_flow, test_death_quit_reload, the placed spawn tests) print SKIP and pass. The evidence records');
  L.push('   `world_present`, its commit and a `dirty` flag; the keys of a test that needs the world (its file names');
  L.push('   `INCLUDE_WORLD`) are refused from a run that did not record the world present.');
  L.push('2. `bash scripts/validate_data.sh --report`: `provenance_report.json` (validation findings per record).');
  L.push('3. `ISOLATE=<name> bash scripts/playtest.sh <scenario> --out _scratch/pt/<scenario>` for every scenario listed above, and');
  L.push('   `bash scripts/playtest_quests.sh --out _scratch/pt/quests` for the every-quest set. Each report.json records the');
  L.push('   commit it played and a dirty flag (`git`).');
  L.push('4. The clean-character playthrough: one more `--playtest <its report.json or directory>`. Its checks verify the');
  L.push('   `playthrough:*` rows when they carry those keys (or a `playtest_tags` rule gives them) and the report is a clean run');
  L.push('   (a passing report, strict mode ok, no console or api step, and the departure boundary reached: its final check');
  L.push(`   "${DEPARTURE_BOUNDARY_CHECK}" passed and no PLAYTHROUGH_STOP flag).`);
  L.push('5. `node tools/parity/build_parity.mjs` with every input, as below (`--check` instead of writing compares the committed files).');
  L.push('   It warns on the console (not in this file, which must not depend on the checkout) when evidence records no commit');
  L.push('   or a dirty tree, when the evidence commits differ from each other, and when an evidence commit\'s `game/`, `tools/`');
  L.push('   or `scripts/` tree differs from HEAD\'s: the states above hold for the code the evidence ran on.', '');
  L.push('```bash', regenerateCommand(doc.inputs), '```', '');
  L.push('## Totals', '');
  const t = doc.totals;
  L.push(`${t.all.entries} entries: ${t.all.verified} verified, ${t.all.implemented} implemented, ${t.all.partial} partial, ${t.all.missing} missing; ` +
    `${t.all.source_data_gap} source-data gaps, ${t.all.pending_source_read} pending source reads (not excused), ${t.all.out_of_scope} out of scope. ` +
    `**${t.open_for_exit}** in-scope entries are neither verified nor a source-data gap (the exit criterion needs 0).`, '');
  L.push('| Category | Entries | Verified | Implemented | Partial | Missing | Source-data gaps | Pending source reads | Out of scope |');
  L.push('|---|---|---|---|---|---|---|---|---|');
  for (const c of doc.categories) {
    const x = t.by_category[c.category];
    L.push(`| [${c.title}](#${anchor(c.title)}) | ${x.entries} | ${x.verified} | ${x.implemented} | ${x.partial} | ${x.missing} | ${x.source_data_gap} | ${x.pending_source_read} | ${x.out_of_scope} |`);
  }
  L.push('');
  L.push('## Source-data gaps', '');
  L.push('Values the sources were read for and do not give. These entries are excused from the exit criterion.', '');
  if (!doc.source_data_gaps.length) L.push('None recorded.');
  const byKey = new Map(doc.categories.flatMap((c) => c.entries).map((e) => [e.key, e]));
  for (const g of doc.source_data_gaps) {
    const pend = arr(byKey.get(g.key)?.pending_reads);
    const also = pend.length ? `; also pending, moot while the gap stands: ${pend.map(readText).join('; ')}` : '';
    L.push(`- \`${g.key}\` ${esc(g.name)}: ${esc(g.gaps.join('; ') + also)}`);
  }
  L.push('', 'Every canonical record also lists what MeowDB does not publish under `gaps` (counted per entry below; the texts are in');
  L.push('[`PROVENANCE_REPORT.md`](PROVENANCE_REPORT.md) "Unresolved values").', '');
  L.push('## Pending source reads', '');
  L.push('Values a source publishes on a page nobody has read yet. They are not source-data gaps and are not excused: each entry');
  L.push('stays partial and counts as open for the exit criterion until the page is read and the data regenerated (its declaration');
  L.push('in `tools/parity/rules.json` `pending_source_reads` then fails the build as stale and is removed).', '');
  if (!doc.pending_source_reads.length) L.push('None recorded.');
  for (const p of doc.pending_source_reads) {
    const reads = p.reads.map((r) => `${readText(r)}${r.detail ? `. ${r.detail}` : ''}`).join(' / ');
    L.push(`- \`${p.key}\` ${esc(p.name)}${p.in_scope ? '' : ' (out of scope)'}: ${esc(reads)}`);
  }
  L.push('');
  L.push('## Open entries', '');
  L.push('In-scope entries that are neither verified nor a source-data gap, by category, with why.', '');
  let anyOpen = false;
  for (const c of doc.categories) {
    const open = c.entries.filter((e) => e.in_scope && e.state !== 'verified' && !e.source_data_gap);
    if (!open.length) continue;
    anyOpen = true;
    const why = (e) => e.issues[0] ?? (e.pending_source_read ? `pending source read (${e.pending_reads.map((r) => r.read).join('; ')})` : null) ??
      (e.state === 'implemented' ? (e.notes.find((n) => /needs a/.test(n)) ?? 'no passing check is tagged with its key') : e.state);
    const groups = new Map();
    for (const e of open) {
      const w = `${e.state}: ${why(e)}`;
      if (!groups.has(w)) groups.set(w, []);
      groups.get(w).push(e.key);
    }
    L.push(`- **${c.title}** (${open.length})`);
    for (const [w, keys] of groups) L.push(`  - ${esc(w)}: ${keys.map((k) => `\`${k}\``).join(', ')}`);
  }
  if (!anyOpen) L.push('None.');
  L.push('');
  for (const c of doc.categories) {
    L.push(`## ${c.title}`, '');
    const rt = c.runtime;
    if (c.category !== 'map-mechanics') {
      L.push(`Runtime: ${rt.state}${rt.files.length ? ` (${rt.files.map((f) => `\`${f}\``).join(', ')})` : ''}${rt.missing.length ? `; missing: ${rt.missing.map((f) => `\`${f}\``).join(', ')}` : ''}${rt.note ? `; ${esc(rt.note)}` : ''}.`, '');
    }
    L.push('| Key | Name | State | Evidence | Gaps | Notes |');
    L.push('|---|---|---|---|---|---|');
    for (const e of c.entries) {
      const flag = e.source_data_gap ? ' (source-data gap)' : e.pending_source_read ? ' (pending source read)' : '';
      const state = e.in_scope ? `${e.state}${flag}` : `${e.state}${flag} (out of scope)`;
      const ev = [`${e.evidence.passed_count} pass`, e.evidence.failed_count ? `**${e.evidence.failed_count} fail**` : null].filter(Boolean).join(', ');
      const notes = [...e.issues, ...e.pending_reads.map((r) => `pending: ${readText(r)}`), ...e.notes, ...e.adaptations.map((a) => `adaptation: ${a.replace('game/data/misostory/', '')}`)];
      L.push(`| \`${e.key}\` | ${esc(e.name)} | ${state} | ${ev} | ${e.source_gaps.length || ''} | ${esc(notes.join('; '))} |`);
    }
    L.push('');
  }
  return L.join('\n');
}

const anchor = (title) => title.toLowerCase().replace(/[^a-z0-9 -]/g, '').replace(/ /g, '-');

/** The build_parity.mjs command line that rebuilds the manifest from the same evidence files. */
export function regenerateCommand(inputs) {
  const args = [...arr(inputs.tests).map((t) => `--tests ${t.file}`), ...arr(inputs.playtests).map((p) => `--playtest ${p.file}`)];
  return ['node tools/parity/build_parity.mjs', ...args].join(' \\\n  ');
}
