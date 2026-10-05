# KuroDB captures (drop probabilities only)

KuroDB (<https://playkuro.com/database/>, the KuroMS player database) is MisoStory's **narrow secondary authority**: it
supplies drop and meso-drop *probabilities* for drops whose *membership* another source already establishes: Hidden
Street's per-monster drop lists for monsters (owner decision D3-6) and MeowDB for the Wooden Box. It never adds an item
to a drop table, and nothing else is taken from it (its monster stats, ids and maps belong to a different
game version: its Snail has 8 HP, MeowDB's has 45).

These files are dated, hand-read captures. KuroDB sits behind a Cloudflare bot check (automated requests get HTTP 403),
so there is no extractor: the project owner passed the check in a normal browser on 2026-10-05, and each page was read
one at a time and saved here verbatim (rendered text plus the drop rows' item links).

| File | Page | What it gives |
|---|---|---|
| `100100.json` | Snail | item and meso drop chances |
| `100101.json` | Blue Snail | item and meso drop chances |
| `120100.json` | Shroom | item and meso drop chances |
| `130101.json` | Red Snail | item and meso drop chances |
| `1210102.json` | Orange Mushroom | item and meso drop chances |
| `9300018.json` | Tutorial Jr. Sentinel | item drop chance (no meso row) |
| `reactor_2001_items.json` | item pages for Old Wooden Board, Rusty Screw, Apple, Egg | reactor ("breakable") drop values |

## Reading the raw values

- Monster drops are shown as `"<p>% base | Qty <n>"`: a percentage of the server's base rate before any server-wide
  multiplier. `"0.0700% base"` is 0.0007 as a probability, `"100% base"` is 1.0.
- Reactor drops are shown as `"Chance value <N>"`, **not** a percentage. Whether that is 1/N or something else is an
  interpretation; it is recorded as such wherever it is used.
- Item ids are KuroMS (GMS-style) ids and do **not** match MeowDB's ids or icon keys (Snail Shell is 4000019 here and
  icon key 4000001 on MeowDB), so drops are joined to MeowDB items through a reviewed name crosswalk.

Do not re-collect these pages automatically. To update a value, read the page again in a browser and replace the
capture with the new reading and its own `read_at` (ISO 8601 with a zone), then regenerate the drop records
(`node tools/meowdb/extract_monsters.mjs`; `docs/runtime/HOWTO.md` "Capture a source page by hand").
