// Build the Maple Island parity manifest: docs/maple_island_parity.json and docs/MAPLE_ISLAND_PARITY.md.
//
//   node tools/parity/build_parity.mjs --tests <evidence.json> [--tests ...] [--playtest <report.json | dir> ...]
//   node tools/parity/build_parity.mjs --check ...      # exit 1 when the committed files differ from a fresh build
//                                                        # (pass the same --tests / --playtest the committed build used:
//                                                        # its "Evidence used" section lists them)
//
// Usual sequence: TEST_EVIDENCE_OUT=_scratch/ev/full.json ISOLATE=<name> INCLUDE_WORLD=1 bash scripts/test.sh, then
// bash scripts/validate_data.sh --report, playtests with --out (every scenario the manifest cites, the every-quest set
// through scripts/playtest_quests.sh --out <dir>, the clean-character playthrough), then this script with the evidence
// and report paths. The generated markdown ends its "Evidence used" section with the exact command it was built with.
// Playtest checks count with their own parity keys plus those tools/parity/rules.json playtest_tags gives them.
// The clean-character playthrough: pass its report (or directory) with one more --playtest. Its checks verify the
// playthrough:<slug> rows (rules.json mechanics with category "playthrough") when they carry those keys (or a
// playtest_tags rule for that scenario gives them), and only when the report is a clean run: a passing report, strict
// mode ok, not one console or api step in the report, and the departure boundary reached: the run's final boundary
// check passed and no PLAYTHROUGH_STOP flag (parity.mjs cleanRun; "Evidence used" says why a report is not one). Its
// quest:, npc:, map: ... keys count as usual.
//
// Inputs (offline, deterministic; nothing is fetched):
//   game/data/canonical, game/data/misostory     the entities (maps, portals, monsters, drops, items, quests, ...)
//   tools/parity/rules.json                      the runtime declarations, mechanics, validation rows, out-of-scope keys,
//                                                pending source reads (values published on a page not read yet)
//   docs/provenance_report.json                  validation findings per record (bash scripts/validate_data.sh --report)
//   --tests <file>                               unit test evidence (TEST_EVIDENCE_OUT=<file> bash scripts/test.sh)
//   --playtest <file|dir>                        playtest report.json files (a directory is searched for report.json;
//                                                a report reached twice, e.g. a directory inside another, counts once)
//   the code under game/, scripts/ and tools/    to check the runtime declarations
// Options: --provenance <file> (default docs/provenance_report.json), --out-json <file>, --out-md <file>.
// The state rule is in tools/parity/parity.mjs and in the generated markdown.
//
// Evidence provenance (contract C6): unit evidence records its commit, a dirty flag and world_present; a playtest
// report.json records its commit and a dirty flag ("git"). The keys of a unit test that needs the exported world
// (its file names INCLUDE_WORLD) are refused from evidence that did not record the world present. On the console only
// (the manifest must not depend on the checkout), this script warns when evidence records no commit or a dirty tree,
// when evidence commits differ from each other, and when an evidence commit's game/, tools/ or scripts/ tree differs
// from HEAD's (git rev-parse <commit>:<tree>).
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { buildParity, toMarkdown } from './parity.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const rel = (p) => path.relative(ROOT, path.resolve(p)).split(path.sep).join('/');
const readJson = (p) => JSON.parse(fs.readFileSync(p, 'utf8'));

function parseArgs(argv) {
  const o = { tests: [], playtests: [], provenance: path.join(ROOT, 'docs', 'provenance_report.json'),
    outJson: path.join(ROOT, 'docs', 'maple_island_parity.json'), outMd: path.join(ROOT, 'docs', 'MAPLE_ISLAND_PARITY.md'), check: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const val = () => {
      if (i + 1 >= argv.length) throw new Error(`${a} needs a value`);
      return argv[++i];
    };
    if (a === '--tests') o.tests.push(val());
    else if (a === '--playtest') o.playtests.push(val());
    else if (a === '--provenance') o.provenance = val();
    else if (a === '--out-json') o.outJson = val();
    else if (a === '--out-md') o.outMd = val();
    else if (a === '--check') o.check = true;
    else if (a === '--help' || a === '-h') {
      console.log(fs.readFileSync(fileURLToPath(import.meta.url), 'utf8').split('\n').filter((l) => l.startsWith('//')).map((l) => l.slice(3)).join('\n'));
      process.exit(0);
    } else throw new Error(`unknown argument ${a}`);
  }
  return o;
}

/** {domain: {id: record}} from game/data/canonical (the root canonical_sources.json is not a domain). */
function loadCanonical() {
  const base = path.join(ROOT, 'game', 'data', 'canonical');
  const out = {};
  for (const d of fs.readdirSync(base, { withFileTypes: true })) {
    if (!d.isDirectory()) continue;
    out[d.name] = {};
    for (const f of fs.readdirSync(path.join(base, d.name)).filter((x) => x.endsWith('.json')).sort()) {
      out[d.name][f.slice(0, -5)] = readJson(path.join(base, d.name, f));
    }
  }
  return out;
}

/** {"<folder>/<basename>" | "<basename>": data} from game/data/misostory. */
function loadMiso() {
  const base = path.join(ROOT, 'game', 'data', 'misostory');
  const out = {};
  const walk = (dir, prefix) => {
    for (const d of fs.readdirSync(dir, { withFileTypes: true })) {
      if (d.isDirectory()) walk(path.join(dir, d.name), `${prefix}${d.name}/`);
      else if (d.name.endsWith('.json')) out[`${prefix}${d.name.slice(0, -5)}`] = readJson(path.join(dir, d.name));
    }
  };
  walk(base, '');
  return out;
}

/** The code the runtime declarations are checked against: repo paths under game/ (no data, assets or import cache), scripts/, tools/. */
function loadRuntime() {
  const files = new Set();
  const skip = new Set(['game/assets', 'game/data', 'game/.godot', 'tools/node_modules', 'tools/meowdb/.cache']);
  const walk = (relDir) => {
    for (const d of fs.readdirSync(path.join(ROOT, relDir), { withFileTypes: true })) {
      const p = `${relDir}/${d.name}`;
      if (skip.has(p)) continue;
      if (d.isDirectory()) walk(p);
      else files.add(p);
    }
  };
  for (const top of ['game', 'scripts', 'tools']) if (fs.existsSync(path.join(ROOT, top))) walk(top);
  const cache = new Map();
  return { files, read: (p) => { if (!cache.has(p)) cache.set(p, fs.readFileSync(path.join(ROOT, p), 'utf8')); return cache.get(p); } };
}

/** The trees whose code the evidence proves (the manifest's states hold for the code the evidence ran on). */
export const CODE_TREES = ['game', 'tools', 'scripts'];

/** `git <args>` in the repository, trimmed; null when git fails (no git, or the object is not in this clone). */
function git(args) {
  try {
    return execFileSync('git', ['-C', ROOT, ...args], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch {
    return null;
  }
}

/**
 * Console warnings about where the evidence came from (contract C6 provenance), never written into the manifest (it
 * must not depend on the checkout): evidence without a commit, evidence from a dirty tree or several commits, evidence
 * commits that differ from each other, and evidence commits whose game/, tools/ or scripts/ tree differs from HEAD's.
 * `gitFn(args)` runs git (injectable for tests). Returns the warning lines.
 */
export function provenanceWarnings(inputs, gitFn = git) {
  const out = [];
  const items = [
    ...inputs.tests.map((t) => ({ what: `unit evidence ${t.file}`, commit: t.commit, dirty: t.dirty, mixed: false })),
    ...inputs.playtests.map((p) => ({ what: `playtest ${p.file}`, commit: p.commit, dirty: p.dirty, mixed: p.mixed })),
  ];
  const noCommit = items.filter((i) => !i.commit);
  if (noCommit.length) {
    out.push(`${noCommit.length} evidence file(s) record no commit, so nothing ties them to the code: ${noCommit.slice(0, 5).map((i) => i.what).join('; ')}${noCommit.length > 5 ? '; ...' : ''}`);
  }
  for (const i of items) {
    if (i.dirty === true) out.push(`${i.what} ran on a dirty tree (game/, tools/ or scripts/ differed from commit ${i.commit})`);
    if (i.mixed) out.push(`${i.what} spans several commits (its phases ran on different code)`);
  }
  const commits = [...new Set(items.map((i) => i.commit).filter(Boolean))].sort();
  if (commits.length > 1) {
    out.push(`the evidence comes from ${commits.length} commits: ${commits.map((c) => `${c.slice(0, 10)} (${items.filter((i) => i.commit === c).length} file(s))`).join(', ')}`);
  }
  if (!commits.length) return out;
  const head = Object.fromEntries(CODE_TREES.map((t) => [t, gitFn(['rev-parse', `HEAD:${t}`])]));
  for (const c of commits) {
    const differs = [];
    for (const t of CODE_TREES) {
      const tree = gitFn(['rev-parse', `${c}:${t}`]);
      if (tree == null || head[t] == null) {
        differs.push(`${t}/ (cannot compare: is ${c.slice(0, 10)} in this clone?)`);
        continue;
      }
      if (tree !== head[t]) differs.push(`${t}/`);
    }
    if (differs.length) out.push(`evidence commit ${c.slice(0, 10)} differs from HEAD in ${differs.join(', ')}: the states it gives may not hold for the code at HEAD`);
  }
  return out;
}

/** report.json files: the file itself, or every report.json under a directory. */
function playtestFiles(arg) {
  if (!fs.existsSync(arg)) throw new Error(`playtest report not found: ${arg}`);
  if (fs.statSync(arg).isFile()) return [arg];
  const out = [];
  const walk = (dir) => {
    for (const d of fs.readdirSync(dir, { withFileTypes: true })) {
      if (d.isDirectory()) walk(path.join(dir, d.name));
      else if (d.name === 'report.json') out.push(path.join(dir, d.name));
    }
  };
  walk(arg);
  return out.sort();
}

function main() {
  const o = parseArgs(process.argv.slice(2));
  const tests = o.tests.map((f) => ({ file: rel(f), doc: readJson(f) }));
  // One entry per report file: `--playtest _scratch/pt --playtest _scratch/pt/<run>` must not count a run twice.
  const playtests = [...new Set(o.playtests.flatMap(playtestFiles).map((f) => rel(f)))].sort()
    .map((f) => ({ file: f, doc: readJson(path.join(ROOT, f)) }));
  const provenance = fs.existsSync(o.provenance) ? readJson(o.provenance) : null;
  if (!provenance) console.warn(`no provenance report at ${rel(o.provenance)} (bash scripts/validate_data.sh --report): validation findings are not applied`);
  const doc = buildParity({
    canonical: loadCanonical(), miso: loadMiso(), rules: readJson(path.join(ROOT, 'tools', 'parity', 'rules.json')),
    runtime: loadRuntime(), provenance, tests, playtests,
  });
  if (provenance && provenance.counts?.records !== Object.values(loadCanonical()).reduce((n, d) => n + Object.keys(d).length, 0)) {
    console.warn('the provenance report counts a different number of records than game/data/canonical: regenerate it');
  }
  if (doc.inputs.unknown_evidence_keys.length) {
    console.warn(`${doc.inputs.unknown_evidence_keys.length} tagged key(s) name no manifest entry (a typo, or a row missing from rules.json): ${doc.inputs.unknown_evidence_keys.join(', ')}`);
  }
  for (const u of doc.inputs.playtest_tag_rules_unmatched) {
    console.warn(`playtest_tags rule ${u.rule} matched no check in ${u.reports} report(s) of ${u.scenarios.join(', ')}`);
  }
  for (const t of doc.inputs.tests) {
    if (t.world_refused?.tests) {
      const keys = t.world_refused.keys;
      console.warn(`${t.file}: ${t.world_refused.tests} world-dependent test(s) refused, the run did not record the world present ` +
        `(INCLUDE_WORLD=1); ${keys.length} key(s): ${keys.slice(0, 12).join(', ')}${keys.length > 12 ? ', ...' : ''}`);
    }
  }
  for (const w of provenanceWarnings(doc.inputs)) console.warn(`provenance: ${w}`);
  const json = JSON.stringify(doc, null, 2) + '\n';
  const md = toMarkdown(doc) + '\n';
  const t = doc.totals.all;
  const summary = `${t.entries} entries: ${t.verified} verified, ${t.implemented} implemented, ${t.partial} partial, ${t.missing} missing; ` +
    `${t.source_data_gap} source-data gaps, ${t.pending_source_read} pending source reads; ${doc.totals.open_for_exit} open for the exit criterion`;
  if (o.check) {
    const same = fs.existsSync(o.outJson) && fs.readFileSync(o.outJson, 'utf8') === json && fs.existsSync(o.outMd) && fs.readFileSync(o.outMd, 'utf8') === md;
    console.log(`${summary}\n${same ? 'PARITY_CHECK_PASSED: the committed manifest is current' : 'PARITY_CHECK_FAILED: the committed manifest differs from a fresh build'}`);
    process.exit(same ? 0 : 1);
  }
  fs.mkdirSync(path.dirname(o.outJson), { recursive: true });
  fs.writeFileSync(o.outJson, json);
  fs.writeFileSync(o.outMd, md);
  console.log(`${summary}\nwrote ${rel(o.outJson)} and ${rel(o.outMd)}`);
}

// Run only as a script (tools/parity/test imports provenanceWarnings).
const norm = (p) => (process.platform === 'win32' ? path.resolve(p).toLowerCase() : path.resolve(p));
if (process.argv[1] && norm(process.argv[1]) === norm(fileURLToPath(import.meta.url))) {
  try {
    main();
  } catch (e) {
    console.error(`build_parity: ${e.message}`);
    process.exit(2);
  }
}
