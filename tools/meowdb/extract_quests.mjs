// Extract every Maple Island quest (plus its NPC dialogue) from MeowDB MS Classic into
// game/data/canonical/quests/<id>.json (one quest per file).
//
//   node tools/meowdb/extract_quests.mjs            # cache-first; re-running reproduces the files exactly
//   node tools/meowdb/extract_quests.mjs --refresh  # re-fetch every page (lib.mjs handles the flag)
//
// Pages read (all cache-first through lib.mjs; nothing else is contacted):
//   /quest-tracker/all            quest index: the region filter (area id) and a cross-check of every quest object
//   /quest-tracker/<id>           quest detail: quest object, prereqs, follow-ups, quest line, NPC placements,
//                                 itemRefs (name -> MeowDB item-db id), and the server-rendered "NPC Dialogue" tree
//   /npcs                         NPC index: independent check of start/turn-in NPC ids, maps and quest lists
//   /item-db/<id>                 one page per referenced item: name + icon key check, and Roger's Apple's icon key
//   /monsters/<id>                one page per monster objective: name check
//   _next/static/chunks/*.js      the quest page's own JS: area-id -> region label table, completion-action text,
//                                 quest database "Requirement type" labels
//   /_data/safe-to-sell.json      MeowDB dataset of items needed by quests (qty): cross-check of every hand-in count,
//                                 the only MeowDB count for Roger's Apple (1002), and its ambiguous item-name list
//
// One dated capture (read by hand, never fetched; decision D3-2), through tools/sources/captures.mjs:
//   tools/meowdb/captures/quest_tracker_maple_island.txt   the live quest tracker filtered to Maple Island: each quest's
//                                 tags ("COT2 · Missable"), which the cached pages do not carry. Written as missable and
//                                 tracker_tags with provenance.<field> citing the capture; the row's name, start NPC,
//                                 level and chain step are cross-checked against the cached quest object.
//
// Quizzes: MeowDB marks the correct choice. Where it does not (1018), the choice is inferred only from MeowDB's own
// dialogue (QUIZ_INFERENCES, guarded on the quoted lines) and labelled correct_choice_basis "inferred_from_meowdb_responses".
//
// Item ids: MeowDB's quest payload lists items as {"name","count","itemId"} where itemId is the item's ICON KEY
// (e.g. Egg = 2010002), not its MeowDB item-db id. The page's itemRefs map gives the item-db id (Egg = 237).
// Output uses item_id = MeowDB item-db id (string) and item_icon_key = the payload's itemId (string).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { fetchPage, fetchUrl, rsc, jsonAt, pageText, source, writeJson, BASE_URL } from './lib.mjs';
import { loadCaptures } from '../sources/captures.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..');
const OUT_DIR = path.join(ROOT, 'game', 'data', 'canonical', 'quests');
const SITE = 'https://meowdb.com';
const SAFE_TO_SELL_URL = `${SITE}/_data/safe-to-sell.json`; // MeowDB's dataset behind /item-db/safe-to-sell
const REGION_NAME = 'Maple Island';

const problems = []; // hard validation failures -> non-zero exit
const report = []; // informational cross-check lines printed at the end
const fail = (msg) => problems.push(msg);

// ---------------------------------------------------------------------------------------------------------------
// RSC (React Server Components "flight") helpers
// ---------------------------------------------------------------------------------------------------------------

/** Split a decoded flight payload into rows: {id -> {type: json|import|hint|text|error, value}}. */
function parseRows(s) {
  const rows = {};
  let p = 0;
  while (p < s.length) {
    while (s[p] === '\n') p++;
    if (p >= s.length) break;
    const m = /^([0-9a-f]*):/.exec(s.slice(p, p + 24));
    if (!m) throw new Error('unparseable RSC row at ' + p + ': ' + JSON.stringify(s.slice(p, p + 60)));
    const id = m[1];
    p += m[0].length;
    const c = s[p];
    if (c === 'I' || (c === 'H' && s[p + 1] === 'L')) {
      const { value, end } = jsonAt(s, s.indexOf('[', p));
      rows[id] = { type: c === 'I' ? 'import' : 'hint', value };
      p = end;
    } else if (c === 'T') {
      const comma = s.indexOf(',', p);
      const len = parseInt(s.slice(p + 1, comma), 16); // UTF-8 byte length
      let q = comma + 1;
      for (let bytes = 0; bytes < len; q++) bytes += Buffer.byteLength(s[q]);
      rows[id] = { type: 'text', value: s.slice(comma + 1, q) };
      p = q;
    } else if (c === 'E') {
      const { value, end } = jsonAt(s, p + 1);
      rows[id] = { type: 'error', value };
      p = end;
    } else {
      const { value, end } = jsonAt(s, p);
      rows[id] = { type: 'json', value };
      p = end;
    }
  }
  return rows;
}

/** Inline lazy "$Lxx"/"$xx" references to JSON rows so the element tree is self-contained. */
function resolveTree(n, rows, seen = new Set()) {
  if (typeof n === 'string') {
    const m = /^\$L?([0-9a-f]+)$/.exec(n);
    if (m && rows[m[1]]?.type === 'json' && !seen.has(m[1])) return resolveTree(rows[m[1]].value, rows, new Set([...seen, m[1]]));
    return n;
  }
  if (Array.isArray(n)) {
    if (n[0] === '$' && typeof n[1] === 'string') {
      const [, tag, key, props] = n;
      return ['$', tag, key, props ? { ...props, children: resolveTree(props.children, rows, seen) } : props];
    }
    return n.map((c) => resolveTree(c, rows, seen));
  }
  return n;
}

const isEl = (n) => Array.isArray(n) && n[0] === '$' && typeof n[1] === 'string';
const elTag = (n) => n[1];
const elKey = (n) => n[2];
const elProps = (n) => n[3] || {};
const cls = (n) => (typeof elProps(n).className === 'string' ? elProps(n).className : '');
/** Flatten children into a list of elements/strings, dropping null/false/"$undefined". */
function kids(n) {
  const out = [];
  const add = (c) => {
    if (c == null || c === false || c === '$undefined' || c === '') return;
    if (Array.isArray(c) && !isEl(c)) c.forEach(add);
    else out.push(c);
  };
  add(isEl(n) ? elProps(n).children : n);
  return out;
}
function allText(n) {
  if (typeof n === 'string') return n === '$undefined' ? '' : n;
  if (isEl(n)) return elTag(n) === 'br' ? '\n' : allText(elProps(n).children);
  if (Array.isArray(n)) return n.map(allText).join('');
  return n == null || n === false ? '' : String(n);
}

// ---------------------------------------------------------------------------------------------------------------
// Dialogue tree -> structured lines
// ---------------------------------------------------------------------------------------------------------------

/** "/msclassic/npcs/9" -> {type:"npc", id:"9"} etc. */
function parseHref(href) {
  const m = /^\/msclassic\/(npcs|monsters|item-db|maps|quest-tracker)\/([^/?#]+)$/.exec(href || '');
  if (!m) throw new Error('unknown dialogue link ' + href);
  return { type: { npcs: 'npc', monsters: 'monster', 'item-db': 'item', maps: 'map', 'quest-tracker': 'quest' }[m[1]], id: m[2] };
}

const BOLD = 'font-semibold text-maple-text';
const RED = 'text-rose-400';
const PASSTHROUGH = new Set(['', 'inline-flex items-baseline gap-0.5 align-baseline', 'font-medium']);
const isChoice = (n) => isEl(n) && elTag(n) === 'span' && /^block ml-[24] my-/.test(cls(n));
const isChoiceMarker = (n) => isEl(n) && elTag(n) === 'span' && /^font-mono /.test(cls(n));
const isCorrectBadge = (n) => isEl(n) && elTag(n) === 'span' && cls(n).startsWith('ml-2 inline-flex') && allText(n).includes('Correct answer');

/**
 * Walk inline content into segments [{text, bold?, red?, ref?, icon_key?}].
 * When `choices` is given, quiz answer rows are collected there (each with fresh styling) instead of inline.
 */
function segmentsOf(node, choices = null) {
  const segs = [];
  const walk = (n, st, out) => {
    if (n == null || n === false || n === '$undefined') return;
    if (typeof n === 'string') {
      out.push({ text: n, ...st });
      return;
    }
    if (Array.isArray(n) && !isEl(n)) return n.forEach((c) => walk(c, st, out));
    if (!isEl(n)) throw new Error('unexpected dialogue node ' + JSON.stringify(n).slice(0, 80));
    const tag = elTag(n);
    const p = elProps(n);
    if (tag === 'br') return out.push({ text: '\n', ...st });
    if (tag === 'img') {
      const m = /^\/msclassic\/api\/assets\/icons\/([^/?#]+)$/.exec(p.src || '');
      if (!m) throw new Error('unknown inline image ' + p.src);
      return out.push({ text: '', ...st, icon_key: m[1] });
    }
    if (p.href) return walk(p.children, { ...st, ref: parseHref(p.href) }, out);
    if (choices && isChoice(n)) {
      const choice = { correct: cls(n).includes('emerald'), segs: [] };
      choices.push(choice);
      for (const c of kids(n)) {
        if (isChoiceMarker(c)) continue;
        if (isCorrectBadge(c)) {
          choice.correct = true;
          continue;
        }
        walk(c, {}, choice.segs);
      }
      return;
    }
    if (isCorrectBadge(n)) throw new Error('correct-answer badge outside a choice');
    const c = cls(n);
    if (tag === 'span' && c === BOLD) return walk(p.children, { ...st, bold: true }, out);
    if (tag === 'span' && c === RED) return walk(p.children, { ...st, red: true }, out);
    if (tag === 'span' && PASSTHROUGH.has(c)) return walk(p.children, st, out);
    throw new Error(`unknown inline element <${tag} class="${c}">`);
  };
  walk(isEl(node) ? elProps(node).children : node, {}, segs);
  return segs;
}

/** Merge adjacent same-style segments, trim the outer whitespace of the line, return {text, segments}. */
function finishLine(segs) {
  const same = (a, b) => !!a.bold === !!b.bold && !!a.red === !!b.red && JSON.stringify(a.ref) === JSON.stringify(b.ref) && !a.icon_key && !b.icon_key;
  const merged = [];
  for (const s of segs.filter((x) => x.text !== '' || x.icon_key)) {
    const last = merged[merged.length - 1];
    if (last && same(last, s)) last.text += s.text;
    else merged.push({ ...s });
  }
  // trim leading/trailing whitespace of the whole line (keep icon segments, drop empty text segments)
  while (merged.length && !merged[0].icon_key && !merged[0].text.replace(/^\s+/, '')) merged.shift();
  while (merged.length && !merged.at(-1).icon_key && !merged.at(-1).text.replace(/\s+$/, '')) merged.pop();
  if (merged.length && !merged[0].icon_key) merged[0].text = merged[0].text.replace(/^\s+/, '');
  if (merged.length && !merged.at(-1).icon_key) merged.at(-1).text = merged.at(-1).text.replace(/\s+$/, '');
  const segments = merged.map((s) => {
    const o = { text: s.text };
    if (s.bold) o.bold = true;
    if (s.red) o.red = true;
    if (s.ref) o.ref = { type: s.ref.type, id: s.ref.id };
    if (s.icon_key) o.icon_key = s.icon_key;
    return o;
  });
  return { text: segments.map((s) => s.text).join(''), segments };
}
const line = (node) => finishLine(segmentsOf(node));

const BRANCH_STATE = {
  yes: null, // set per section: on_accept -> "accepted", on_completion -> "ready"
  no: 'declined',
  stopItem: 'missing_items',
  stopMob: 'missing_kills',
  stopNpc: 'wrong_npc',
  lost: 'lost_items',
};
const fixHeading = (h) => h.replace(/''/g, "'"); // MeowDB's branch labels carry a doubled apostrophe ("don''t")

/** div.space-y-2 > p* -> lines */
function linesOf(spaceDiv) {
  return kids(spaceDiv).map((p) => {
    if (!isEl(p) || !['p', 'li'].includes(elTag(p))) throw new Error('unexpected line element ' + JSON.stringify(p).slice(0, 80));
    return line(p);
  });
}

function parseBranch(div, sectionState) {
  const [head, body, ...rest] = kids(div);
  if (rest.length || !head || !body) throw new Error('unexpected branch layout ' + elKey(div));
  const key = elKey(div);
  if (!(key in BRANCH_STATE)) throw new Error('unknown dialogue branch key ' + key);
  const state = key === 'yes' ? (sectionState === 'on_accept' ? 'accepted' : 'ready') : BRANCH_STATE[key];
  return { key, state, heading: fixHeading(allText(head)), lines: linesOf(body) };
}

/**
 * MeowDB renders each in-game "#L<n>#" selection as a choice row. When the game text has a malformed tag
 * (Rain's quiz 6: "#L2 # 5 points", with a space), MeowDB leaves it as plain text inside the PREVIOUS choice row.
 * Split such text out into its own choice so the option list is complete. The reconstructed choice keeps the raw
 * text in raw_markup and gets correct: null (MeowDB rendered it as text, so it carries no correct/incorrect marker).
 */
const RAW_CHOICE_TAG = /#L(\d+)\s*#\s*/g;
function splitRawChoices(choices) {
  const out = [];
  for (const c of choices) {
    let cur = { correct: c.correct, segs: [], raw_markup: null, markup_index: null };
    out.push(cur);
    for (const s of c.segs) {
      const text = s.text ?? '';
      const tags = [...text.matchAll(RAW_CHOICE_TAG)];
      if (!tags.length) {
        cur.segs.push(s);
        continue;
      }
      const before = text.slice(0, tags[0].index);
      if (before) cur.segs.push({ ...s, text: before });
      tags.forEach((m, k) => {
        const end = k + 1 < tags.length ? tags[k + 1].index : text.length;
        cur = { correct: null, segs: [{ ...s, text: text.slice(m.index + m[0].length, end) }], raw_markup: text.slice(m.index, end).trim(), markup_index: Number(m[1]) };
        out.push(cur);
      });
    }
  }
  return out;
}

function parseQuiz(block, correctDiv) {
  const [qdiv, wrongDiv, ...rest] = kids(block);
  if (rest.length || !qdiv || !wrongDiv) throw new Error('unexpected quiz layout');
  const choices = [];
  const question = finishLine(segmentsOf(qdiv, choices));
  const [wrongHead, wrongUl] = kids(wrongDiv);
  const [correctHead, correctP] = correctDiv ? kids(correctDiv) : [];
  const split = splitRawChoices(choices);
  split.forEach((c, i) => {
    // the game's selection index (#L<n>) must equal the choice position, i.e. document order = in-game order
    if (c.markup_index !== null && c.markup_index !== i) throw new Error(`raw quiz choice tag #L${c.markup_index} found at position ${i}`);
  });
  return {
    question,
    // choice rows are nested inside each other's bold spans in MeowDB's markup; styling is dropped, refs are kept
    choices: split.map((c) => ({ ...finishLine(c.segs.map(({ bold, red, ...s }) => s)), correct: c.correct, raw_markup: c.raw_markup })),
    correct_choice_index: null, // filled in buildQuest (MeowDB marker, or a documented inference)
    correct_choice_basis: null,
    wrong_answer_heading: fixHeading(allText(wrongHead)),
    wrong_answer_responses: kids(wrongUl).map(line),
    correct_answer_heading: correctHead ? fixHeading(allText(correctHead)) : null,
    correct_answer_response: correctP ? line(correctP) : null,
  };
}

const SECTION_STATE = { 'On accept': 'on_accept', 'On completion': 'on_completion' };

function parseDialogue(tree) {
  const top = kids(tree);
  if (allText(top[0]) !== 'NPC Dialogue') throw new Error('dialogue heading missing');
  const out = { on_accept: null, on_completion: null };
  for (const card of kids(top[1])) {
    const [header, ...content] = kids(card);
    const [h2, ...chipEls] = kids(header);
    const heading = allText(h2);
    const state = SECTION_STATE[heading];
    if (!state) throw new Error('unknown dialogue section ' + heading);
    const section = { heading, chips: chipEls.map((c) => ({ label: allText(c), title: elProps(c).title ?? null })), lines: [], branches: [], quiz: null };
    for (let i = 0; i < content.length; i++) {
      const el = content[i];
      const c = cls(el);
      if (c === 'space-y-2') section.lines.push(...linesOf(el));
      else if (elKey(el) in BRANCH_STATE && c.startsWith('mt-3 rounded-lg')) section.branches.push(parseBranch(el, state));
      else if (elKey(el) === '0' && (c === '' || c === '$undefined')) {
        const next = content[i + 1];
        const correct = next && !elKey(next) && cls(next).startsWith('mt-4 rounded-lg border border-emerald') ? next : null;
        if (correct) i++;
        if (section.quiz) throw new Error('two quiz blocks in one section');
        section.quiz = parseQuiz(el, correct);
      } else throw new Error(`unknown dialogue block key=${elKey(el)} class="${c}"`);
    }
    if (out[state]) throw new Error('duplicate dialogue section ' + heading);
    out[state] = section;
  }
  return out;
}

/** Every dialogue line object in a parsed dialogue (for validation and reference collection). */
function dialogueLines(d) {
  const out = [];
  for (const sec of [d.on_accept, d.on_completion]) {
    if (!sec) continue;
    out.push(...sec.lines);
    for (const b of sec.branches) out.push(...b.lines);
    if (sec.quiz) {
      out.push(sec.quiz.question, ...sec.quiz.choices, ...sec.quiz.wrong_answer_responses);
      if (sec.quiz.correct_answer_response) out.push(sec.quiz.correct_answer_response);
    }
  }
  return out;
}

// ---------------------------------------------------------------------------------------------------------------
// Page loaders
// ---------------------------------------------------------------------------------------------------------------

const pageUrl = (p) => BASE_URL + p;

async function loadPage(p) {
  const r = await fetchPage(p);
  return { url: pageUrl(p), retrieved_at: r.retrieved_at, html: r.html, flight: rsc(r.html) };
}

/** The quest-tracker detail page component props ({quest, prereqs, ...}). */
function questProps(flight, id) {
  const needle = '{"quest":{"id":' + JSON.stringify(id) + ',';
  const k = flight.indexOf(needle);
  if (k < 0) throw new Error('quest props not found for ' + id);
  return jsonAt(flight, k).value;
}

/** Area id -> label table and the completion-action UI strings, read from the quest page's own JS chunks. */
async function loadQuestUiTables(detailFlight) {
  const rows = parseRows(detailFlight);
  const imp = Object.values(rows).find((r) => r.type === 'import' && r.value[1].some((c) => c.includes('quest-tracker/%5Bid%5D/page')));
  if (!imp) throw new Error('quest page import row not found');
  const chunks = imp.value[1].filter((c) => typeof c === 'string' && c.endsWith('.js'));
  let areas = null;
  let areaSrc = null;
  const strings = {};
  let stringsSrc = null;
  for (const c of chunks) {
    const url = `${SITE}/_next/${c}`;
    const r = await fetchUrl(url);
    const js = r.text;
    const am = /\[(\{id:1,name:"Maple Island"[^\]]*)\]/.exec(js);
    if (am && !areas) {
      areas = {};
      for (const m of am[1].matchAll(/\{id:(\d+),name:"([^"]+)"/g)) areas[m[1]] = m[2];
      areaSrc = { url, retrieved_at: r.retrieved_at };
    }
    const sm = /"quest-tracker\.useRogersApple":\{"en":"((?:[^"\\]|\\.)*)"/.exec(js);
    if (sm && !strings.useRogersApple) {
      strings.useRogersApple = JSON.parse('"' + sm[1].replace(/\\'/g, "'") + '"');
      stringsSrc = { url, retrieved_at: r.retrieved_at };
    }
    // quest database "Requirement type" filter labels (items-only / kills-only / mixed `need` lists)
    for (const k of ['requirementType', 'requirementItems', 'requirementKills', 'requirementMixed']) {
      const rm = new RegExp(`"quest-tracker\\.database\\.${k}":\\{"en":"((?:[^"\\\\]|\\\\.)*)"`).exec(js);
      if (rm && !strings[k]) {
        strings[k] = JSON.parse('"' + rm[1].replace(/\\'/g, "'") + '"');
        if (stringsSrc && stringsSrc.url !== url) throw new Error('quest UI strings split across chunks; extend field_sources');
        stringsSrc = { url, retrieved_at: r.retrieved_at };
      }
    }
    if (areas && strings.useRogersApple && strings.requirementItems && strings.requirementMixed) break;
  }
  if (!areas) throw new Error('area table not found in quest page chunks');
  if (!strings.useRogersApple) throw new Error('completion-action strings not found in quest page chunks');
  for (const k of ['requirementType', 'requirementItems', 'requirementKills', 'requirementMixed']) if (!strings[k]) throw new Error(`quest database label ${k} not found in quest page chunks`);
  return { areas, areaSrc, strings, stringsSrc };
}

/** NPC index: [{id,name,roles,maps:[{mapId,mapName,streetName,region,x,y}],quests,turnInQuests,...}] */
async function loadNpcIndex() {
  const pg = await loadPage('/npcs');
  const k = pg.flight.indexOf('"npcs":[{');
  if (k < 0) throw new Error('npc index array not found');
  return { ...pg, npcs: jsonAt(pg.flight, k + '"npcs":'.length).value };
}

const itemPages = new Map();
async function itemPage(id) {
  if (!itemPages.has(id)) {
    const pg = await loadPage('/item-db/' + id);
    const m = /"src":"\/msclassic\/api\/assets\/icons\/([^"]+)","alt":"((?:[^"\\]|\\.)*) icon - MapleStory Classic"/.exec(pg.flight);
    if (!m) throw new Error('item page header not found for ' + id);
    itemPages.set(id, { ...pg, icon_key: m[1], name: JSON.parse('"' + m[2] + '"') });
  }
  return itemPages.get(id);
}

const monsterPages = new Map();
async function monsterPage(id) {
  if (!monsterPages.has(id)) {
    const pg = await loadPage('/monsters/' + id);
    const m = /<title>([^<]*?) - MapleStory Classic/.exec(pg.html);
    if (!m) throw new Error('monster page title not found for ' + id);
    const name = m[1].replace(/&#x27;|&#39;/g, "'").replace(/&amp;/g, '&');
    monsterPages.set(id, { ...pg, name });
  }
  return monsterPages.get(id);
}

// ---------------------------------------------------------------------------------------------------------------
// Quest record assembly
// ---------------------------------------------------------------------------------------------------------------

const deepEqual = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const sortKeys = (o) => (Array.isArray(o) ? o.map(sortKeys) : o && typeof o === 'object' ? Object.fromEntries(Object.keys(o).sort().map((k) => [k, sortKeys(o[k])])) : o);
const squash = (s) => s.replace(/\s+/g, '');
const KNOWN_QUEST_KEYS = new Set(['id', 'name', 'parent', 'area', 'description', 'npc', 'levelMin', 'exp', 'mesos', 'need', 'get', 'requires', 'requiresAll', 'jobReq', 'completeNpc', 'acceptItems', 'completionAction', 'rewardRandom', 'rewardChoices', 'completeLevelMin', 'isRepeatable', 'isDaily', 'isWeekly', 'fame', 'fameReq', 'acceptanceMesoCost', 'acceptanceItemExclusions', 'startDate', 'endDate', 'skillReq', 'selfStart', 'citizenshipReq', 'unresolvedPrerequisites', 'classKey']);

/**
 * Quizzes whose correct answer MeowDB does not mark. Each rule names the choice and quotes the MeowDB lines that
 * identify it. Every quoted line must be present verbatim and every other choice must be answered by a quoted
 * wrong-answer line, otherwise the inference is not applied and the run fails.
 */
const QUIZ_INFERENCES = {
  1018: {
    choice: '5 points',
    correct_response: 'You get 5 AP with each level',
    wrong: { '1 point': 'Come on, you get more than 1 measly point!', '2 points': 'Nope, not 2 points. Think again.' },
  },
};
function inferQuizAnswer(id, quiz) {
  const rule = QUIZ_INFERENCES[id];
  if (!rule) return null;
  const index = quiz.choices.findIndex((c) => c.text === rule.choice);
  if (index < 0 || quiz.choices[index].correct === true) return null;
  if (!quiz.correct_answer_response?.text.includes(rule.correct_response)) return null;
  const wrongTexts = quiz.wrong_answer_responses.map((l) => l.text);
  const others = quiz.choices.map((c) => c.text).filter((t) => t !== rule.choice);
  if (others.length !== Object.keys(rule.wrong).length || !others.every((t) => rule.wrong[t] && wrongTexts.includes(rule.wrong[t]))) return null;
  return {
    index,
    evidence: [
      `the "${quiz.correct_answer_heading}" line says "${rule.correct_response}"`,
      ...others.map((t) => `"${quiz.wrong_answer_heading}" answers the other choice "${t}" with "${rule.wrong[t]}"`),
    ],
  };
}

async function buildQuest(id, indexQuest, ctx) {
  const pg = await loadPage('/quest-tracker/' + id);
  const props = questProps(pg.flight, id);
  const q = props.quest;
  const rows = parseRows(pg.flight);
  const notes = [];
  const gaps = [];
  const discrepancies = [];
  const fieldSources = {};
  const qid = `quest ${id}`;

  for (const k of Object.keys(q)) if (!KNOWN_QUEST_KEYS.has(k)) fail(`${qid}: unknown quest field "${k}" (extend the extractor)`);

  // --- index vs detail cross-check -------------------------------------------------------------------------
  if (!deepEqual(sortKeys(q), sortKeys(indexQuest))) {
    for (const k of new Set([...Object.keys(q), ...Object.keys(indexQuest)])) {
      if (!deepEqual(q[k], indexQuest[k])) {
        discrepancies.push({
          field: k,
          values: [
            { url: pg.url, value: q[k] ?? null },
            { url: ctx.index.url, value: indexQuest[k] ?? null },
          ],
          chosen: pg.url,
          reason: 'The quest detail page is the specific record for this quest; the index is a summary list.',
        });
      }
    }
  }

  // --- region --------------------------------------------------------------------------------------------
  const region = ctx.ui.areas[String(q.area)] ?? null;
  if (region !== REGION_NAME) fail(`${qid}: area ${q.area} is "${region}", expected ${REGION_NAME}`);
  fieldSources.region = { url: ctx.ui.areaSrc.url, retrieved_at: ctx.ui.areaSrc.retrieved_at };

  // --- NPCs and maps ---------------------------------------------------------------------------------------
  const placements = props.npcPlacements || {};
  const npcRef = (name) => {
    if (!name) return null;
    const pl = placements[name];
    if (!pl) {
      gaps.push(`No NPC placement on the quest page for "${name}".`);
      return { npc_id: null, name };
    }
    return { npc_id: String(pl.npcId), name };
  };
  const mapsOf = (name) => (placements[name]?.locations || []).map((l) => ({ map_id: l.mapId, map_name: l.mapName, street_name: l.streetName }));
  const startNpc = npcRef(q.npc);
  const endNpcName = q.completeNpc || q.npc;
  const endNpc = npcRef(endNpcName);
  const startMaps = mapsOf(q.npc);
  const endMaps = mapsOf(endNpcName);
  for (const [name, pl] of Object.entries(placements)) if (pl.routeMapId) notes.push(`MeowDB gives a route map ${pl.routeMapId} for ${name}.`);

  // NPC index cross-check (independent MeowDB page)
  for (const [role, ref, maps] of [['start', startNpc, startMaps], ['end', endNpc, endMaps]]) {
    const n = ctx.npcIndex.npcs.find((x) => String(x.id) === ref.npc_id);
    if (!n) {
      fail(`${qid}: ${role} NPC ${ref.npc_id} not in /npcs index`);
      continue;
    }
    if (n.name !== ref.name) fail(`${qid}: ${role} NPC id ${ref.npc_id} is "${n.name}" in /npcs, "${ref.name}" on the quest page`);
    const idxMaps = (n.maps || []).map((m) => m.mapId).sort();
    if (!deepEqual(idxMaps, maps.map((m) => m.map_id).sort())) fail(`${qid}: ${role} NPC maps differ between quest page and /npcs`);
    if (!(n.maps || []).every((m) => m.region === 'MapleIsland')) fail(`${qid}: ${role} NPC ${ref.name} has a map outside region MapleIsland in /npcs`);
    if (role === 'start' && !(n.quests || []).some((x) => x.id === id)) fail(`${qid}: /npcs does not list ${id} under ${n.name}'s quests`);
    if (role === 'end' && q.completeNpc && !(n.turnInQuests || []).some((x) => x.id === id)) fail(`${qid}: /npcs does not list ${id} under ${n.name}'s turn-in quests`);
  }

  // --- dialogue --------------------------------------------------------------------------------------------
  const slot = props.dialogueSlot;
  const dialogue = slot ? parseDialogue(resolveTree(slot, rows)) : { on_accept: null, on_completion: null };
  const dLines = dialogueLines(dialogue);
  const visible = squash(pageText(pg.html));
  for (const l of dLines) if (!visible.includes(squash(l.text))) fail(`${qid}: dialogue line not found in visible page text: ${l.text.slice(0, 60)}`);
  for (const l of dLines) if (/#[A-Za-z]/.test(l.text)) fail(`${qid}: dialogue text still contains game markup: ${JSON.stringify(l.text.slice(0, 60))}`);
  const dRefs = dLines.flatMap((l) => l.segments.filter((s) => s.ref).map((s) => ({ ...s.ref, text: s.text })));
  const quiz = dialogue.on_completion?.quiz;
  if (dialogue.on_accept?.quiz) fail(`${qid}: quiz in On accept (extend the extractor)`);
  if (quiz) {
    const marked = quiz.choices.flatMap((c, i) => (c.correct === true ? [i] : []));
    if (marked.length === 1) {
      quiz.correct_choice_index = marked[0];
      quiz.correct_choice_basis = 'meowdb_marker';
    } else if (marked.length === 0) {
      const inf = inferQuizAnswer(id, quiz);
      if (!inf) fail(`${qid}: MeowDB marks no quiz choice as correct and no documented inference applies`);
      else {
        quiz.correct_choice_index = inf.index;
        quiz.correct_choice_basis = 'inferred_from_meowdb_responses';
        gaps.push(
          `MeowDB marks no quiz choice as the correct answer${quiz.choices.some((c) => c.raw_markup) ? ', and shows the last option only as unparsed game markup (' + quiz.choices.filter((c) => c.raw_markup).map((c) => JSON.stringify(c.raw_markup)).join(', ') + '); that option is reconstructed in choices with correct: null' : ''}.`,
        );
        notes.push(`quiz.correct_choice_index ${inf.index} ("${quiz.choices[inf.index].text}") is inferred from MeowDB's own dialogue, not from a MeowDB correct-answer marker: ${inf.evidence.join('; ')}.`);
      }
    } else fail(`${qid}: ${marked.length} quiz choices marked correct`);
  }
  if (!dialogue.on_accept) gaps.push('MeowDB shows no "On accept" (quest start) dialogue for this quest.');
  if (!dialogue.on_completion) gaps.push('MeowDB shows no "On completion" dialogue for this quest.');

  // dialogue NPC links must agree with placements
  for (const r of dRefs.filter((r) => r.type === 'npc')) {
    const pl = Object.entries(placements).find(([, v]) => String(v.npcId) === r.id);
    const idx = ctx.npcIndex.npcs.find((x) => String(x.id) === r.id);
    if (!idx) fail(`${qid}: dialogue links unknown NPC ${r.id}`);
    else if (pl && pl[0] !== idx.name) fail(`${qid}: dialogue NPC ${r.id} name mismatch`);
  }

  // --- items -----------------------------------------------------------------------------------------------
  const itemRefs = props.itemRefs || {};
  const verifiedItems = new Set();
  const item = async (e, extra = {}) => {
    const ref = itemRefs[e.name];
    if (!ref) {
      gaps.push(`No MeowDB item-db id for "${e.name}" (icon key ${e.itemId}) on the quest page.`);
      return { item_id: null, item_icon_key: String(e.itemId), name: e.name, count: e.count, ...extra };
    }
    if (String(ref.iconKey) !== String(e.itemId)) fail(`${qid}: itemRefs icon key ${ref.iconKey} != payload itemId ${e.itemId} for ${e.name}`);
    const ip = await itemPage(String(ref.id));
    if (ip.name !== e.name) fail(`${qid}: item-db ${ref.id} is "${ip.name}", quest says "${e.name}"`);
    if (ip.icon_key !== String(e.itemId)) fail(`${qid}: item-db ${ref.id} icon key ${ip.icon_key} != ${e.itemId}`);
    verifiedItems.add(String(ref.id));
    return { item_id: String(ref.id), item_icon_key: String(e.itemId), name: e.name, count: e.count, ...extra };
  };
  const itemPageLinksQuest = (itemId) => itemPages.get(itemId)?.flight.includes(`"/msclassic/quest-tracker/${id}"`) ?? false;

  /** Dialogue item links that point at a different item-db id than the quest data uses for the same name. */
  async function checkDialogueItemLinks(questItems) {
    const known = new Map(questItems.filter((i) => i.item_id).map((i) => [i.item_id, i]));
    const seen = new Set();
    for (const r of dRefs.filter((r) => r.type === 'item')) {
      if (known.has(r.id) || seen.has(r.id)) continue;
      seen.add(r.id);
      const other = await itemPage(r.id);
      const twin = [...known.values()].find((i) => i.name === other.name);
      if (!twin) {
        notes.push(`Dialogue links item-db ${r.id} ("${other.name}"), which is not otherwise part of this quest's data.`);
        continue;
      }
      const tp = itemPages.get(twin.item_id);
      const values = [
        { url: pg.url, where: 'itemRefs (quest data)', value: twin.item_id },
        { url: pg.url, where: `NPC dialogue link ("${r.text.trim()}")`, value: r.id },
      ];
      let reason =
        `item-db ${twin.item_id} has icon key ${tp.icon_key}, equal to the quest payload's itemId, and its page ${tp.url} ` +
        `${itemPageLinksQuest(twin.item_id) ? 'links this quest' : 'does not link this quest'}; item-db ${r.id} is a different item with the same name ` +
        `(icon key ${other.icon_key}; its page ${other.flight.includes(`"/msclassic/quest-tracker/${id}"`) ? 'links' : 'does not link'} this quest). The dialogue link appears to be resolved by name.`;
      const amb = ctx.sts.data.ambiguous.find((a) => a.name === twin.name);
      if (amb) {
        values.push({ url: ctx.sts.url, where: `"ambiguous" item-name list (name "${amb.name}")`, value: { ids: amb.ids.map(String), chose: String(amb.chose) } });
        reason +=
          ` ${ctx.sts.url} lists "${amb.name}" as an ambiguous name (item-db ${amb.ids.join(', ')}) and resolves it by name to ${amb.chose}` +
          `${String(amb.chose) === r.id ? ', the same id as the dialogue link' : ''}: MeowDB's own name-based resolution produces ${amb.chose} for this name, independent of the quest.`;
      }
      discrepancies.push({ field: `item id of "${twin.name}"`, values, chosen: twin.item_id, reason });
    }
  }

  // --- objectives ------------------------------------------------------------------------------------------
  const monsterKills = [];
  const itemCollection = [];
  for (const e of q.need) {
    if (e.mobId !== undefined) {
      const mobName = e.name.startsWith('Defeat ') ? e.name.slice(7) : e.name;
      const mp = await monsterPage(String(e.mobId));
      if (mp.name !== mobName) fail(`${qid}: monster ${e.mobId} page is "${mp.name}", quest says "${mobName}"`);
      monsterKills.push({ mob_id: String(e.mobId), name: mobName, count: e.count });
    } else if (e.itemId !== undefined) {
      itemCollection.push(await item(e, { hand_in: true }));
    } else fail(`${qid}: requirement without mobId/itemId: ${JSON.stringify(e)}`);
  }
  const killIds = new Set(monsterKills.map((m) => m.mob_id));
  for (const r of dRefs.filter((r) => r.type === 'monster')) {
    if (!killIds.has(r.id)) notes.push(`Dialogue mentions monster ${r.id} ("${r.text.trim()}"), which is not a kill objective of this quest.`);
  }
  const itemUsage = [];
  let completionActionText = null;
  if (q.completionAction) {
    if (q.completionAction !== 'use-rogers-apple') fail(`${qid}: unknown completionAction ${q.completionAction}`);
    completionActionText = ctx.ui.strings.useRogersApple;
    fieldSources.completion_action_text = { url: ctx.ui.stringsSrc.url, retrieved_at: ctx.ui.stringsSrc.retrieved_at };
    const link = dRefs.find((r) => r.type === 'item' && r.text.trim() === "Roger's Apple");
    if (!link) fail(`${qid}: no Roger's Apple item link found in the dialogue`);
    const ip = await itemPage(link.id);
    if (ip.name !== "Roger's Apple") fail(`${qid}: item ${link.id} is "${ip.name}"`);
    fieldSources['objectives.item_usage[0].item_icon_key'] = { url: ip.url, retrieved_at: ip.retrieved_at };
    // The quest page has no count. MeowDB's safe-to-sell.json (items needed by quests) is the only MeowDB number.
    const stsRow = ctx.sts.data.rows.find((r) => String(r.itemId) === link.id && r.name === ip.name);
    const stsQ = stsRow?.quests.find((x) => x.id === id);
    let count = null;
    if (stsQ) {
      count = stsQ.qty;
      fieldSources['objectives.item_usage[0].count'] = { url: ctx.sts.url, retrieved_at: ctx.sts.retrieved_at };
      const nameAmbiguous = ctx.sts.data.ambiguous.some((a) => a.name === ip.name);
      discrepancies.push({
        field: 'objectives.item_usage[0].count',
        values: [
          { url: pg.url, where: `quest data "need" (requirements: ${JSON.stringify(q.need)}) and completion rule "${completionActionText}"`, value: null },
          { url: ip.url, where: 'item page "Needed By"', value: itemPageLinksQuest(link.id) ? 'lists this quest' : 'does not list this quest' },
          { url: ctx.sts.url, where: `rows[name "${stsRow.name}", itemId ${stsRow.itemId}].quests[id "${id}"].qty`, value: stsQ.qty },
        ],
        chosen: stsQ.qty,
        reason:
          `The quest page gives the completion rule without a count and lists no item requirement; ${ctx.sts.url} is the only MeowDB source with a number. ` +
          `Caveats: that file is a derived dataset (generated ${ctx.sts.data.generated}) that resolves items by name (its "ambiguous" list records ${ctx.sts.data.ambiguous.length} names it resolved to one of several ids; ` +
          `"${ip.name}" is ${nameAmbiguous ? '' : 'not '}among them), and its qty means "the quest asks for N", not explicitly "use N".`,
      });
    } else gaps.push('Item-usage count is not given by MeowDB (completion rule text: "' + completionActionText + '").');
    itemUsage.push({ item_id: link.id, item_icon_key: ip.icon_key, name: ip.name, count });
  }
  // Every quest is turned in by talking to its end NPC (MeowDB "Turn in: X", or the single "NPC: X" when no separate
  // turn-in NPC is listed; Roger's completion text says so explicitly).
  const npcTalk = [{ ...endNpc, purpose: 'turn_in' }];
  const sectionQuiz = dialogue.on_completion?.quiz || null;
  const other = [];
  if (sectionQuiz) other.push({ type: 'quiz', description: 'Answer the NPC quiz question correctly on completion (see dialogue.on_completion.quiz).' });

  // --- rewards ---------------------------------------------------------------------------------------------
  const rewardItems = [];
  for (const e of q.get) rewardItems.push(await item(e, { given: 'on_completion' }));
  const selection = [];
  for (const g of q.rewardChoices || []) {
    const items = [];
    for (const e of g.items) items.push(await item(e, e.chance !== undefined ? { chance_pct: e.chance } : {}));
    selection.push({ job_name: g.jobName, items });
  }
  const random = [];
  for (const g of q.rewardRandom || []) {
    const items = [];
    for (const e of g.items) items.push(await item(e, { chance_pct: e.chance }));
    random.push({ job_name: g.jobName, total_weight: g.totalWeight ?? null, items });
  }
  const acceptItems = [];
  for (const e of q.acceptItems || []) acceptItems.push(await item(e, { given: 'on_accept' }));
  const nextQuestGrants = [];
  for (const g of props.nextQuestGrants || []) {
    const items = [];
    for (const e of g.items) items.push(await item(e));
    nextQuestGrants.push({ quest_id: g.id, name: g.name, items });
  }

  await checkDialogueItemLinks([...itemCollection, ...rewardItems, ...acceptItems, ...random.flatMap((g) => g.items), ...selection.flatMap((g) => g.items), ...itemUsage, ...nextQuestGrants.flatMap((g) => g.items)]);

  // safe-to-sell.json cross-check (independent MeowDB dataset of items needed by quests): every hand-in count matches,
  // and every item it lists for this quest is a requirement (or the item-usage objective) of this record.
  const stsRows = ctx.sts.data.rows.filter((r) => (r.quests || []).some((x) => x.id === id));
  for (const it of itemCollection) {
    const row = stsRows.find((r) => r.name === it.name);
    if (!row) {
      fail(`${qid}: "${it.name}" is not listed for this quest in safe-to-sell.json`);
      continue;
    }
    const qty = row.quests.find((x) => x.id === id).qty;
    if (qty !== it.count) fail(`${qid}: safe-to-sell.json qty ${qty} != count ${it.count} for ${it.name}`);
    if (String(row.itemId) !== it.item_id && !ctx.sts.data.ambiguous.some((a) => a.name === it.name && a.ids.map(String).includes(it.item_id))) {
      fail(`${qid}: safe-to-sell.json gives item-db ${row.itemId} for "${it.name}", quest data ${it.item_id}, and the name is not listed as ambiguous`);
    }
  }
  for (const row of stsRows) if (![...itemCollection, ...itemUsage].some((it) => it.name === row.name)) fail(`${qid}: safe-to-sell.json lists "${row.name}" for this quest but the record has no such requirement`);
  const stsChecks = stsRows.length ? [{ url: ctx.sts.url, retrieved_at: ctx.sts.retrieved_at, checked: 'item quantities the quest asks for (quests[].qty) and that no listed quest item is missing from the record' }] : [];

  // reward/requirement items should be linked back from their item pages (informational)
  for (const it of [...itemCollection, ...rewardItems, ...acceptItems, ...random.flatMap((g) => g.items), ...itemUsage]) {
    if (it.item_id) report.push(`${id} item ${it.item_id} (${it.name}): item page links this quest = ${itemPageLinksQuest(it.item_id)}`);
  }

  // --- prerequisites, chain ---------------------------------------------------------------------------------
  const prereqQuests = (props.prereqs || []).map((p) => ({ quest_id: p.id, name: p.name }));
  if (!deepEqual(prereqQuests.map((p) => p.quest_id), q.requiresAll || [])) fail(`${qid}: prereqs ${JSON.stringify(prereqQuests)} != requiresAll ${JSON.stringify(q.requiresAll)}`);
  if ((q.requires ?? null) !== ((q.requiresAll || [])[0] ?? null) || (q.requiresAll || []).length > 1) notes.push(`MeowDB requires=${JSON.stringify(q.requires)} requiresAll=${JSON.stringify(q.requiresAll)}.`);
  const line_ = props.questLine;
  const questLine = line_
    ? {
        steps: line_.steps.map((s) => ({ quest_id: s.id, name: s.name, npc: s.npc ?? null, min_level: s.levelMin ?? null })),
        position: line_.currentIndex + 1,
        total: line_.total,
        end_fork: line_.endFork || [],
        split: line_.split ?? null,
      }
    : null;

  // --- journal (description) --------------------------------------------------------------------------------
  const descLines = q.description.split(/\r?\n+/).map((s) => s.trim()).filter(Boolean);
  for (const l of descLines) if (!visible.includes(squash(l))) fail(`${qid}: description line not visible on page: ${l.slice(0, 50)}`);

  // --- gaps common to all quests ---------------------------------------------------------------------------
  if (!q.jobReq) gaps.push("MeowDB lists no job requirement for this quest (job_restriction is null; MeowDB does not distinguish 'any job' from 'not recorded').");
  gaps.push('MeowDB has no maximum level for quests (max_level is null).');
  gaps.push('MeowDB has no map-visit objectives or per-objective map restrictions for quests.');
  const S = ctx.ui.strings;
  if (itemCollection.length) {
    gaps.push(`MeowDB has no explicit "items removed on completion" field; items_removed_on_completion is derived from MeowDB's quest database "${S.requirementType}" filter, which labels item requirements "${S.requirementItems}" / "${S.requirementMixed}".`);
    fieldSources['items_removed_on_completion.basis'] = { url: ctx.ui.stringsSrc.url, retrieved_at: ctx.ui.stringsSrc.retrieved_at };
  }
  gaps.push('MeowDB does not say which "On completion" lines are shown before vs after the reward is given, or how dialogue pages are split into NPC chat windows.');

  // --- live tracker tags (dated capture, decision D3-2) -----------------------------------------------------
  const tracker = trackerRowFor(qid, q, startNpc.name, questLine, ctx);
  if (!tracker) gaps.push(`The quest tracker capture (${ctx.tracker.file}) has no row for this quest, so missable and tracker_tags are null.`);

  // --- assemble --------------------------------------------------------------------------------------------
  const repeatType = q.isDaily ? 'daily' : q.isWeekly ? 'weekly' : q.isRepeatable ? 'repeatable' : null;
  const record = {
    id,
    name: q.name,
    region,
    area_id: q.area,
    quest_group: q.parent ?? null,
    start_npc: startNpc,
    end_npc: endNpc,
    end_npc_listed_separately: !!q.completeNpc,
    start_maps: startMaps,
    end_maps: endMaps,
    min_level: q.levelMin,
    max_level: null,
    completion_min_level: q.completeLevelMin ?? null,
    job_restriction: q.jobReq ?? null,
    class_key: q.classKey ?? null,
    prerequisites: {
      quests: prereqQuests,
      items: [],
      fame_min: q.fameReq ?? null,
      skills: (q.skillReq || []).map((s) => ({ name: s.name, min_level: s.levelMin })),
      citizenship: q.citizenshipReq ?? null,
      acceptance_meso_cost: q.acceptanceMesoCost ?? null,
      must_not_have_items: (q.acceptanceItemExclusions || []).map((e) => e.name),
      unresolved: q.unresolvedPrerequisites ?? [],
    },
    repeatable: repeatType !== null,
    repeat_type: repeatType,
    self_start: !!q.selfStart,
    missable: tracker ? tracker.tags.includes('Missable') : null,
    tracker_tags: tracker ? tracker.tags : null,
    objectives: {
      monster_kills: monsterKills,
      item_collection: itemCollection,
      item_usage: itemUsage,
      npc_talk: npcTalk,
      map_visit: [],
      other,
    },
    completion_action: q.completionAction ?? null,
    completion_action_text: completionActionText,
    rewards: {
      exp: q.exp,
      mesos: q.mesos,
      fame: q.fame ?? 0,
      items: rewardItems,
      selection,
      random,
    },
    items_given_on_accept: acceptItems,
    items_removed_on_completion: {
      explicit_in_meowdb: false,
      basis: itemCollection.length
        ? `Derived, not explicit: MeowDB's quest database "${S.requirementType}" filter treats item requirements as hand-ins (quests whose requirements are all items are listed as "${S.requirementItems}", items plus kills as "${S.requirementMixed}"). MeowDB has no field saying which items are taken on completion.`
        : 'No item requirements.',
      items: itemCollection.map(({ item_id, item_icon_key, name, count }) => ({ item_id, item_icon_key, name, count })),
    },
    followup_quests: (props.nextQuests || []).map((n) => ({ quest_id: n.id, name: n.name })),
    next_quest_grants: nextQuestGrants,
    quest_line: questLine,
    journal: {
      raw: q.description,
      lines: descLines,
      summary: descLines[0] ?? null,
      entries: descLines.slice(1),
    },
    dialogue,
    ...(tracker ? { provenance: { missable: trackerSource(tracker, ctx), tracker_tags: trackerSource(tracker, ctx) } } : {}),
    source: source(pg.url, pg.retrieved_at),
    field_sources: fieldSources,
    cross_checks: [
      { url: ctx.index.url, retrieved_at: ctx.index.retrieved_at, checked: 'quest object identical to detail page unless listed in discrepancies' },
      { url: ctx.npcIndex.url, retrieved_at: ctx.npcIndex.retrieved_at, checked: 'start/end NPC ids, names, maps, region MapleIsland, quest and turn-in lists' },
      ...[...verifiedItems].sort((a, b) => a - b).map((i) => ({ url: itemPages.get(i).url, retrieved_at: itemPages.get(i).retrieved_at, checked: 'item name and icon key' })),
      ...monsterKills.map((m) => ({ url: monsterPages.get(m.mob_id).url, retrieved_at: monsterPages.get(m.mob_id).retrieved_at, checked: 'monster name' })),
      ...stsChecks,
    ],
    notes,
    gaps,
    discrepancies: discrepancies.map(({ key, ...d }) => d),
  };
  return record;
}

// ---------------------------------------------------------------------------------------------------------------
// The live quest tracker capture (tags per quest)
// ---------------------------------------------------------------------------------------------------------------

/**
 * Maple Island rows of the quest tracker capture, keyed by quest name:
 * {name, raw, level, npc, tags: ["COT2", "Missable"], step, total, collapsed}. A row reads
 * "<name>  [Level N · ]<start NPC> · Maple Island · <tag> · <tag>  [Step k of n]"; the page collapses a long chain into
 * one row ("Rain's Maple Quiz 1 … 7 ... Step 1 … 7 of 7"), which is expanded into one row per quest ("Rain's Maple
 * Quiz 1" ... "Rain's Maple Quiz 7", steps 1 to 7). Any line naming Maple Island that does not parse is a problem.
 */
function trackerRows(tracker) {
  const rows = new Map();
  for (const line of tracker.text.split('\n')) {
    if (!line.includes(` · ${REGION_NAME} · `)) continue;
    const m = /^\s*(.+?)\s{2,}(.+?)\s*$/.exec(line);
    if (!m) { fail(`quest tracker capture: unreadable row ${JSON.stringify(line)}`); continue; }
    let rest = m[2];
    let step = null, total = null;
    const st = /\s{2,}Step (.+) of (\d+)$/.exec(rest);
    if (st) { step = st[1]; total = Number(st[2]); rest = rest.slice(0, st.index); }
    const parts = rest.split(' · ').map((s) => s.trim());
    const level = /^Level (\d+)$/.exec(parts[0] ?? '');
    if (level) parts.shift();
    const [npc, region, ...tags] = parts;
    if (region !== REGION_NAME || !npc || tags.length === 0) { fail(`quest tracker capture: unreadable row ${JSON.stringify(line)}`); continue; }
    const base = { raw: line.trim(), level: level ? Number(level[1]) : null, npc, tags, total };
    const range = /^(.+) (\d+) … (\d+)$/.exec(m[1]);
    const stepRange = step ? /^(\d+) … (\d+)$/.exec(step) : null;
    if (range) {
      const [lo, hi] = [Number(range[2]), Number(range[3])];
      if (!stepRange || Number(stepRange[1]) !== lo || Number(stepRange[2]) !== hi) fail(`quest tracker capture: collapsed row ${JSON.stringify(m[1])} has steps ${JSON.stringify(step)}`);
      for (let i = lo; i <= hi; i++) rows.set(`${range[1]} ${i}`, { ...base, name: `${range[1]} ${i}`, step: i, collapsed: true });
    } else {
      rows.set(m[1], { ...base, name: m[1], step: step == null ? null : Number(step), collapsed: false });
    }
  }
  return rows;
}

/** The tracker row for quest `q` (the cached quest object), cross-checked; null (with a problem) when absent. */
function trackerRowFor(qid, q, startNpcName, questLine, ctx) {
  const row = ctx.trackerRows.get(q.name);
  if (!row) { fail(`${qid} ${q.name}: no row in the quest tracker capture (${ctx.tracker.file})`); return null; }
  ctx.trackerUsed.add(q.name);
  if (row.npc !== startNpcName) fail(`${qid}: quest tracker start NPC ${JSON.stringify(row.npc)} != ${JSON.stringify(startNpcName)}`);
  if ((row.level ?? 0) !== q.levelMin) fail(`${qid}: quest tracker level ${row.level ?? '(none)'} != levelMin ${q.levelMin}`);
  const pos = questLine ? questLine.position : null;
  const tot = questLine ? questLine.total : null;
  if (row.step !== pos || row.total !== tot) fail(`${qid}: quest tracker step ${row.step} of ${row.total} != quest line ${pos} of ${tot}`);
  return row;
}

/** The C7 source object citing the tracker capture for a field read from `row`. */
function trackerSource(row, ctx) {
  const t = ctx.tracker;
  const src = { authority: 'MeowDB MS Classic', url: t.url, read_at: t.read_at, capture: t.file, method: t.method, raw_value: row.raw };
  if (t.read_at_note) src.read_at_note = t.read_at_note;
  if (row.collapsed) src.note = `The tracker shows this chain as one collapsed row ("${row.raw.split(/\s{2,}/)[0]}"); its tags apply to each quest of the chain.`;
  return src;
}

// ---------------------------------------------------------------------------------------------------------------
// Per-quest notes that are about MeowDB's own content (kept here so they are reproduced on every run)
// ---------------------------------------------------------------------------------------------------------------
function addSpecialNotes(rec) {
  const texts = dialogueLines(rec.dialogue).map((l) => l.text);
  // Guarded on the data it describes, so a --refresh that changes MeowDB never leaves a stale claim behind.
  if (rec.id === '1002' && rec.items_given_on_accept.length === 0 && texts.some((t) => t.includes("Roger's Apple I gave you"))) {
    rec.gaps.push(
      'MeowDB lists no items given on acceptance (acceptItems is empty) and no "On accept" dialogue, but the completion stop-dialogue says "Eat the Roger\'s Apple I gave you". MeowDB does not record how many Roger\'s Apples Roger gives or exactly when.',
    );
    rec.discrepancies.push({
      field: 'items_given_on_accept',
      values: [
        { url: rec.source.url, where: 'quest data acceptItems', value: [] },
        { url: rec.source.url, where: 'On completion / If you don\'t have the items yet dialogue', value: 'implies Roger gave the player Roger\'s Apple (item-db 235), quantity not stated' },
      ],
      chosen: 'items_given_on_accept kept empty (structured data); the implication is recorded here and in gaps',
      reason: 'No MeowDB page states the quantity or timing, and values must not be filled from memory.',
    });
  }
  if (rec.completion_action === 'use-rogers-apple' && rec.rewards.exp === 0 && rec.rewards.mesos === 0 && !rec.rewards.items.length) {
    rec.notes.push('MeowDB marks this quest with completionAction "use-rogers-apple": the completion condition is using Roger\'s Apple, then talking to Roger. It gives no EXP, mesos or items (MeowDB: "Talk quest, no items required or rewarded.").');
  }
  if (rec.objectives.other.some((o) => o.type === 'quiz')) {
    rec.notes.push(
      'Quiz choices are listed in MeowDB document order, which is the in-game selection order (#L0, #L1, ...; quiz 6 leaks a raw "#L2" tag exactly at position 2). MeowDB renders the choice rows nested inside each other (a markup artifact); the extractor flattens them in document order. choices[].correct is MeowDB\'s marker: true = marked "Correct answer", false = rendered as an option and not marked, null = option reconstructed from unparsed game markup (raw_markup). Wrong-answer responses are listed in MeowDB order and are not linked to a specific choice by MeowDB.',
    );
  }
  if (rec.id === '1012' && (rec.dialogue.on_accept?.branches || []).some((b) => b.lines.some((l) => /\b0\/3\b/.test(l.text)))) {
    rec.notes.push('The second "If you accept" line ends with an item list ("Rusty Screw 0/3", "Old Wooden Board 0/3", each with an inline item icon); the bold "0" appears to be MeowDB rendering an in-game current-count placeholder as 0.');
  }
}

// ---------------------------------------------------------------------------------------------------------------
async function main() {
  const indexPg = await loadPage('/quest-tracker/all');
  const qk = indexPg.flight.indexOf('"quests":[{');
  if (qk < 0) throw new Error('quest index array not found');
  const allQuests = jsonAt(indexPg.flight, qk + '"quests":'.length).value;

  const firstDetail = await loadPage('/quest-tracker/1002');
  const ui = await loadQuestUiTables(firstDetail.flight);
  const areaId = Object.entries(ui.areas).find(([, n]) => n === REGION_NAME)?.[0];
  if (!areaId) throw new Error('Maple Island area id not found');
  const npcIndex = await loadNpcIndex();
  const stsRes = await fetchUrl(SAFE_TO_SELL_URL);
  const sts = { url: SAFE_TO_SELL_URL, retrieved_at: stsRes.retrieved_at, data: JSON.parse(stsRes.text) };
  if (!Array.isArray(sts.data.rows) || !Array.isArray(sts.data.ambiguous)) throw new Error('safe-to-sell.json layout changed');

  const selected = allQuests.filter((q) => String(q.area) === areaId).sort((a, b) => Number(a.id) - Number(b.id));

  // Independent check: every quest given or turned in by an NPC standing on a Maple Island map is selected.
  const miNpcs = npcIndex.npcs.filter((n) => (n.maps || []).some((m) => m.region === 'MapleIsland'));
  const viaNpcs = new Set(miNpcs.flatMap((n) => [...(n.quests || []), ...(n.turnInQuests || [])].map((q) => q.id)));
  const selIds = new Set(selected.map((q) => q.id));
  for (const id of viaNpcs) if (!selIds.has(id)) fail(`quest ${id} is given/turned in by a Maple Island NPC but its area is not ${REGION_NAME}`);
  for (const id of selIds) if (!viaNpcs.has(id)) fail(`quest ${id} has area ${REGION_NAME} but no Maple Island NPC lists it`);

  const tracker = loadCaptures().meowdb.quest_tracker;
  if (!tracker) throw new Error('quest tracker capture missing (tools/meowdb/captures/quest_tracker_maple_island.txt)');
  const ctx = { index: indexPg, ui, npcIndex, sts, tracker, trackerRows: trackerRows(tracker), trackerUsed: new Set() };
  fs.mkdirSync(OUT_DIR, { recursive: true });
  const written = [];
  for (const iq of selected) {
    const rec = await buildQuest(iq.id, iq, ctx);
    addSpecialNotes(rec);
    writeJson(path.join(OUT_DIR, `${rec.id}.json`), rec);
    written.push(rec);
  }
  // Every Maple Island row of the live tracker is one of the selected quests (D3-2: the same 20).
  for (const name of ctx.trackerRows.keys()) if (!ctx.trackerUsed.has(name)) fail(`quest tracker capture lists "${name}", which is not a selected ${REGION_NAME} quest`);
  // stale files from an earlier run that are no longer selected
  for (const f of fs.readdirSync(OUT_DIR)) if (f.endsWith('.json') && !selIds.has(f.replace(/\.json$/, ''))) fail(`stale file ${f} in ${OUT_DIR}`);

  console.log(`quests: ${written.length} written to ${path.relative(ROOT, OUT_DIR)} (area ${areaId} = ${REGION_NAME}, index has ${allQuests.length})`);
  for (const r of written) {
    const d = r.dialogue;
    const nLines = dialogueLines(d).length;
    console.log(`  ${r.id} ${r.name} | ${r.start_npc.name} -> ${r.end_npc.name} | Lv ${r.min_level} | EXP ${r.rewards.exp} mesos ${r.rewards.mesos} | dialogue lines ${nLines} | discrepancies ${r.discrepancies.length}`);
  }
  if (process.argv.includes('--verbose')) for (const l of report) console.log('  ' + l);
  if (problems.length) {
    console.error(`\n${problems.length} validation problem(s):`);
    for (const p of problems) console.error('  - ' + p);
    process.exitCode = 1;
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
