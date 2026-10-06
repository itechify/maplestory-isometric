// Pure parsers for the raw values in the dated source captures (tools/meowdb, tools/kurodb, tools/hiddenstreet
// captures). Development-time only; nothing here touches the network or the disk.
//
// Rules every parser follows (Iteration Three brief, "Probability handling"; docs/ITERATION_LOG.md D3-3..D3-8):
//   - The raw string is kept verbatim in the result (`raw`), so a reviewer can always compare value and source.
//   - A value that cannot be read exactly throws SourceParseError. Nothing is guessed, rounded or defaulted:
//     negative numbers, more than 100%, NaN, an unknown "| ..." segment, a range with min > max all throw.
//   - Percentages are converted with exact decimal arithmetic on the digits as written, never with parseInt/parseFloat
//     on a partial string, so "0.0700%" is 0.0007 (not 0, not 0.07, not 7e-5).
//   - A KuroDB percentage ("N% base") and a KuroDB reactor value ("Chance value N") are different formats with
//     different parsers. Each parser rejects the other format, so N% can never be read as 1/N or the reverse.
//
//   parseKuroPercent("0.0700% base | Qty 1")         -> {probability: 0.0007, qty: {min: 1, max: 1}, quest: null, ...}
//   parseKuroPercent("100.00% base | Qty 1 | Quest 1035") -> {probability: 1, quest: "1035", ...}
//   parseKuroPercent("40% base | Meso drop")         -> {kind: "meso", probability: 0.4, qty: null, ...}
//   parseReactorChanceValue("Chance value 4")        -> {raw_n: 4, probability: 0.25, interpretation: "1/N", ...}
//   parseHiddenStreetMesos("Mesos: 4-6")             -> {state: "resolved", min: 4, max: 6}
//   parseHiddenStreetMesos("Mesos: ?")               -> {state: "unresolved", min: null, max: null}
//   normalizeItemName("Blue Training Shirt (M)")     -> {normalized: "blue training shirt", gender: "M", ...}

/** Thrown for any raw value that cannot be read exactly. `raw` is the offending input. */
export class SourceParseError extends Error {
  constructor(message, raw) {
    super(`${message}: ${JSON.stringify(raw)}`);
    this.name = 'SourceParseError';
    this.raw = raw;
  }
}

/** The decision that makes "Chance value N" a 1/N probability (docs/ITERATION_LOG.md). */
export const REACTOR_DECISION = 'D3-7';

const DECIMAL = /^(\d+)(?:\.(\d+))?$/;

/**
 * Exact decimal division by 10^places on the digits as written: decimalShift("0.0700", 2) -> "0.0007",
 * decimalShift("100.00", 2) -> "1", decimalShift("2", 2) -> "0.02". Throws on anything but an unsigned decimal.
 */
export function decimalShift(text, places) {
  const m = DECIMAL.exec(String(text));
  if (!m) throw new SourceParseError('not an unsigned decimal number', text);
  if (!Number.isInteger(places) || places < 0) throw new SourceParseError('places must be a non-negative integer', places);
  const digits = m[1] + (m[2] || '');
  let point = m[1].length - places; // position of the decimal point in `digits`
  let padded = digits;
  if (point <= 0) {
    padded = '0'.repeat(1 - point) + digits;
    point = 1;
  }
  let intPart = padded.slice(0, point).replace(/^0+(?=\d)/, '');
  let frac = padded.slice(point).replace(/0+$/, '');
  if (intPart === '') intPart = '0';
  return frac ? `${intPart}.${frac}` : intPart;
}

/** A decimal string as a Number, refusing anything that does not round-trip to a finite value. */
function toNumber(text) {
  const n = Number(text);
  if (!Number.isFinite(n)) throw new SourceParseError('not a finite number', text);
  return n;
}

/** "Qty 1" -> {min: 1, max: 1}; "Qty 1-3" / "Qty 1 ~ 3" -> {min: 1, max: 3}. Throws on 0, negatives or min > max. */
function parseQty(seg, raw) {
  const m = /^Qty\s+(\d+)(?:\s*[-~]\s*(\d+))?$/.exec(seg);
  if (!m) return null;
  const min = Number(m[1]);
  const max = m[2] != null ? Number(m[2]) : min;
  if (min < 1) throw new SourceParseError('quantity must be at least 1', raw);
  if (max < min) throw new SourceParseError('quantity range has min > max', raw);
  return { min, max };
}

/**
 * KuroDB monster/item drop value "<p>% base | Qty <n>[ | Quest <q>][ | ID <id>]" or "<p>% base | Meso drop".
 * `<p>` is a percentage of the server's base rate. Returns
 * {raw, format: "percent_base", kind: "item"|"meso", percent_text, percent, probability_text, probability,
 *  conversion: "<p> / 100", qty: {min, max}|null, quest: string|null, source_id: string|null}.
 * An item page's global drop rule (KuroDB item 2040705's "LHC global 10% scroll" row) also carries
 * "| Maps <from>-<to>" (or "| Maps <id>") and "| Excludes bosses" / "| Excludes friendly mobs"; such a row adds
 * maps: {from, to} and excludes: ["bosses", "friendly mobs"] (other rows have neither key).
 */
export function parseKuroPercent(raw) {
  if (typeof raw !== 'string') throw new SourceParseError('KuroDB value must be a string', raw);
  const text = raw.trim();
  if (/^chance value\b/i.test(text)) {
    throw new SourceParseError('this is a KuroDB reactor value ("Chance value N"), not a percentage; use parseReactorChanceValue', raw);
  }
  const m = /^(\S+?)\s*%\s*base\s*(?:\|(.*))?$/.exec(text);
  if (!m) throw new SourceParseError('not a KuroDB "<p>% base" value', raw);
  const percentText = m[1];
  if (!DECIMAL.test(percentText)) throw new SourceParseError('percentage is not an unsigned decimal number', raw);
  const probabilityText = decimalShift(percentText, 2);
  const percent = toNumber(decimalShift(percentText, 0));
  const probability = toNumber(probabilityText);
  if (probability > 1) throw new SourceParseError('percentage above 100%', raw);
  const out = {
    raw, format: 'percent_base', kind: 'item', percent_text: percentText, percent, probability_text: probabilityText,
    probability, conversion: `${percentText} / 100`, qty: null, quest: null, source_id: null,
  };
  const segments = m[2] == null ? [] : m[2].split('|').map((s) => s.trim());
  for (const seg of segments) {
    if (seg === '') throw new SourceParseError('empty "|" segment', raw);
    const qty = parseQty(seg, raw);
    if (qty) {
      if (out.qty) throw new SourceParseError('two quantities', raw);
      out.qty = qty;
      continue;
    }
    let s;
    if ((s = /^Quest\s+(\d+)$/.exec(seg))) {
      if (out.quest) throw new SourceParseError('two quest conditions', raw);
      out.quest = s[1];
    } else if (/^Meso drop$/i.test(seg)) {
      out.kind = 'meso';
    } else if ((s = /^ID\s+(\d+)$/.exec(seg))) {
      out.source_id = s[1];
    } else if ((s = /^Maps\s+(\d+)(?:\s*-\s*(\d+))?$/.exec(seg))) {
      if (out.maps) throw new SourceParseError('two map ranges', raw);
      const to = s[2] ?? s[1];
      if (Number(to) < Number(s[1])) throw new SourceParseError('map range has from > to', raw);
      out.maps = { from: s[1], to };
    } else if ((s = /^Excludes\s+(bosses|friendly mobs)$/i.exec(seg))) {
      const what = s[1].toLowerCase();
      out.excludes = out.excludes ?? [];
      if (out.excludes.includes(what)) throw new SourceParseError(`"Excludes ${what}" twice`, raw);
      out.excludes.push(what);
    } else {
      throw new SourceParseError(`unknown segment "${seg}"`, raw);
    }
  }
  if (out.kind === 'meso' && out.qty) throw new SourceParseError('a meso row has no item quantity', raw);
  return out;
}

/**
 * KuroDB reactor ("breakable") drop value "Chance value <N>[ | Quest <q>]". N is read as a 1/N chance: an
 * interpretation by the project owner's decision D3-7 (it matches the OdinMS-family reactor code), never a percentage.
 * Returns {raw, format: "reactor_chance_value", raw_n, probability, interpretation: "1/N", decision, conversion, quest}.
 */
export function parseReactorChanceValue(raw) {
  if (typeof raw !== 'string') throw new SourceParseError('reactor value must be a string', raw);
  const text = raw.trim();
  if (/%/.test(text)) throw new SourceParseError('this is a percentage, not a reactor "Chance value N"; use parseKuroPercent', raw);
  const m = /^Chance value\s+(\S+)\s*(?:\|(.*))?$/.exec(text);
  if (!m) throw new SourceParseError('not a KuroDB "Chance value N" reactor value', raw);
  if (!/^\d+$/.test(m[1])) throw new SourceParseError('N must be a positive whole number', raw);
  const n = Number(m[1]);
  if (n < 1) throw new SourceParseError('N must be at least 1 (1/0 is not a probability)', raw);
  const out = {
    raw, format: 'reactor_chance_value', raw_n: n, probability: 1 / n, interpretation: '1/N', decision: REACTOR_DECISION,
    conversion: `1 / ${n} (interpretation, decision ${REACTOR_DECISION})`, quest: null,
  };
  const segments = m[2] == null ? [] : m[2].split('|').map((s) => s.trim());
  for (const seg of segments) {
    const q = /^Quest\s+(\d+)$/.exec(seg);
    if (!q || out.quest) throw new SourceParseError(`unknown segment "${seg}"`, raw);
    out.quest = q[1];
  }
  return out;
}

/** Whole numbers only; "4.5" or "-1" throw. */
function wholeNumber(text, raw) {
  if (!/^\d+$/.test(text)) throw new SourceParseError('meso amount must be a whole number', raw);
  return Number(text);
}

/**
 * Hidden Street meso amount "Mesos: <a>" | "Mesos: <a>-<b>" | "Mesos: ?" (the "Mesos:" label is optional).
 * Returns {raw, state: "resolved", min, max} or {raw, state: "unresolved", min: null, max: null} for "?".
 */
export function parseHiddenStreetMesos(raw) {
  if (typeof raw !== 'string') throw new SourceParseError('meso value must be a string', raw);
  const value = raw.trim().replace(/^Mesos\s*:\s*/i, '').trim();
  if (value === '?') return { raw, state: 'unresolved', min: null, max: null };
  const range = /^(\S+)\s*-\s*(\S+)$/.exec(value);
  const min = wholeNumber(range ? range[1] : value, raw);
  const max = range ? wholeNumber(range[2], raw) : min;
  if (max < min) throw new SourceParseError('meso range has min > max', raw);
  return { raw, state: 'resolved', min, max };
}

/**
 * MeowDB's player meso report line "Mesos: <a>[-<b>] per kill | <n> report(s)".
 * Returns {raw, state: "resolved", min, max, reports}.
 */
export function parseMeowdbMesoReport(raw) {
  if (typeof raw !== 'string') throw new SourceParseError('meso report must be a string', raw);
  const m = /^Mesos:\s*(\d+)(?:\s*-\s*(\d+))?\s+per kill\s*\|\s*(\d+)\s+reports?$/.exec(raw.trim());
  if (!m) throw new SourceParseError('not a MeowDB "Mesos: N per kill | K report(s)" line', raw);
  const min = Number(m[1]);
  const max = m[2] != null ? Number(m[2]) : min;
  if (max < min) throw new SourceParseError('meso range has min > max', raw);
  return { raw, state: 'resolved', min, max, reports: Number(m[3]) };
}

/**
 * Item-name key for crosswalk joins between MeowDB, KuroDB and Hidden Street. Case, hyphens ("Red-Striped" vs
 * "Red Striped"), spacing around ":" ("Omok Piece : Mushroom" vs "Omok Piece: Mushroom"), "/" and ",", and curly
 * quotes are normalized. A trailing gender suffix "(M)" / "(F)" is NOT silently dropped: it is removed from
 * `normalized` and reported in `gender` ("M" | "F" | null) and `suffix`, so a join must compare it explicitly
 * (Red Cloth Pants (M) is MeowDB 1168, the female one 1177). Plurals and other aliases ("Arrow for Bow" vs
 * "Arrows for Bows") are not normalized: they need an alias with evidence.
 * Returns {raw, base, normalized, gender, suffix}.
 */
export function normalizeItemName(name) {
  if (typeof name !== 'string' || name.trim() === '') throw new SourceParseError('item name must be a non-empty string', name);
  let base = name.normalize('NFKC').trim();
  let gender = null;
  let suffix = null;
  const g = /\s*\(([MF])\)\s*$/i.exec(base);
  if (g) {
    gender = g[1].toUpperCase();
    suffix = `(${gender})`;
    base = base.slice(0, g.index).trim();
  }
  const normalized = base
    .toLowerCase()
    .replace(/[‘’‛`´]/g, "'")
    .replace(/[‐-―_-]+/g, ' ')
    .replace(/\s*:\s*/g, ': ')
    .replace(/\s*\/\s*/g, ' / ')
    .replace(/\s*,\s*/g, ', ')
    .replace(/\s+/g, ' ')
    .trim();
  return { raw: name, base, normalized, gender, suffix };
}

/** True when two names denote the same item for a join: same normalized name AND same gender suffix. */
export function sameItemName(a, b) {
  const x = normalizeItemName(a);
  const y = normalizeItemName(b);
  return x.normalized === y.normalized && x.gender === y.gender;
}

/** Stable slug for a drop entry key (contract C1 `key`): "Snail Shell" -> "snail-shell", "(M)" -> "-m". */
export function entryKey(name) {
  const k = String(name).normalize('NFKC').toLowerCase().replace(/['’]/g, '').replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
  if (!k) throw new SourceParseError('name has no letters or digits for a key', name);
  return k;
}

/** The drop-list categories of a Hidden Street "Before Chaos" monster page, in page order. */
export const HIDDEN_STREET_DROP_CATEGORIES = [
  'Etc. drop', 'Common equipment', 'Warrior equipment', 'Magician equipment', 'Bowman equipment', 'Thief equipment',
  'Pirate equipment', 'Ore drop', 'Maker item', 'Useable drop',
];

/**
 * A Hidden Street monster page's rendered text (tools/hiddenstreet/captures/monsters.json monsters[].text).
 * Returns {name, level, hp, mp, exp, kb, mesos (parseHiddenStreetMesos), lists: {<category>: [names]},
 *  items: [{name, normalized, gender, categories: [..], raw_lines: [..]}]} with items in first-seen order.
 * Every category of HIDDEN_STREET_DROP_CATEGORIES must appear exactly once ("-" = empty list).
 */
export function parseHiddenStreetMonsterText(text) {
  if (typeof text !== 'string') throw new SourceParseError('page text must be a string', text);
  const lines = text.split('\n');
  const out = { name: lines[0].trim(), level: null, hp: null, mp: null, exp: null, kb: null, mesos: null, lists: {}, items: [] };
  const byName = new Map();
  for (const line of lines.slice(1)) {
    for (const cell of line.split('\t').map((c) => c.trim()).filter(Boolean)) {
      const kv = /^([A-Za-z.]+)\s*:\s*(.*)$/.exec(cell);
      if (!kv) continue;
      const [, key, value] = kv;
      if (key === 'Mesos') out.mesos = parseHiddenStreetMesos(cell);
      else if (['Level', 'HP', 'MP', 'EXP', 'KB'].includes(key) && /^\d+$/.test(value)) out[key.toLowerCase()] = Number(value);
    }
    const cat = HIDDEN_STREET_DROP_CATEGORIES.find((c) => line.startsWith(c + ':'));
    if (!cat) continue;
    if (cat in out.lists) throw new SourceParseError(`category "${cat}" appears twice`, text);
    const rawLine = line.replace(/\s+$/, '');
    const body = line.slice(cat.length + 1).trim();
    const names = body === '-' || body === '' ? [] : body.split(',').map((s) => s.trim()).filter(Boolean);
    out.lists[cat] = names;
    for (const name of names) {
      if (!byName.has(name)) {
        const n = normalizeItemName(name);
        const item = { name, normalized: n.normalized, gender: n.gender, categories: [], raw_lines: [] };
        byName.set(name, item);
        out.items.push(item);
      }
      const item = byName.get(name);
      item.categories.push(cat);
      item.raw_lines.push(rawLine);
    }
  }
  for (const c of HIDDEN_STREET_DROP_CATEGORIES) {
    if (!(c in out.lists)) throw new SourceParseError(`category "${c}" is missing (page layout changed?)`, text);
  }
  if (out.mesos == null) throw new SourceParseError('no "Mesos:" value', text);
  return out;
}

/** ISO 8601 date-time with an explicit zone, naming a real date and time (mirrors ProvenanceChecks.is_iso_timestamp). */
export function isIsoTimestamp(text) {
  if (typeof text !== 'string') return false;
  const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?(?:Z|[+-](\d{2}):(\d{2}))$/.exec(text);
  if (!m) return false;
  const [y, mo, d, h, mi, s, zh, zm] = m.slice(1).map((v) => (v == null ? null : Number(v)));
  const leap = (y % 4 === 0 && y % 100 !== 0) || y % 400 === 0;
  const days = mo === 2 ? (leap ? 29 : 28) : [4, 6, 9, 11].includes(mo) ? 30 : 31;
  if (mo < 1 || mo > 12 || d < 1 || d > days || h > 23 || mi > 59) return false;
  if (s != null && s > 60) return false;
  if (zh != null && (zh > 23 || zm > 59)) return false;
  return true;
}
