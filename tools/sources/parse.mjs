// Pure parsers for the raw values in the dated source captures (tools/meowdb and tools/henesys captures).
// Development-time only; nothing here touches the network or the disk.
//
// Rules every parser follows (Iteration Three brief, "Probability handling"; docs/ITERATION_LOG.md D3-11, D3-12):
//   - The raw string is kept verbatim in the result (`raw`), so a reviewer can always compare value and source.
//   - A value that cannot be read exactly throws SourceParseError. Nothing is guessed, rounded or defaulted:
//     negative numbers, NaN, a range with min > max all throw.
//
//   parseMeowdbMesoReport("Mesos: 2 per kill | 1 report")  -> {state: "resolved", min: 2, max: 2, reports: 1}
//   entryKey("Overall Armor DEF Scroll: Intermediate")     -> "overall-armor-def-scroll-intermediate"

/** Thrown for any raw value that cannot be read exactly. `raw` is the offending input. */
export class SourceParseError extends Error {
  constructor(message, raw) {
    super(`${message}: ${JSON.stringify(raw)}`);
    this.name = 'SourceParseError';
    this.raw = raw;
  }
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
  if (Number(m[3]) < 1) throw new SourceParseError('a report line with 0 reports', raw);
  return { raw, state: 'resolved', min, max, reports: Number(m[3]) };
}

/** Stable slug for a drop entry key (contract C1 `key`): "Snail Shell" -> "snail-shell". */
export function entryKey(name) {
  const k = String(name).normalize('NFKC').toLowerCase().replace(/['’]/g, '').replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
  if (!k) throw new SourceParseError('name has no letters or digits for a key', name);
  return k;
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
