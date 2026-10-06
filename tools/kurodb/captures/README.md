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
| `item_<kuro item id>.json` (none yet) | one item page | which item a monster page's row is (decision D3-8) |

File names say what the page is: `<kuro monster id>.json` is a monster page (its text starts `MONSTER · <id>`), and
`item_<kuro item id>.json` an item page (`ITEM · <id>`). The loader (`tools/sources/captures.mjs`) refuses an item page
saved under a bare number, and any other name.

## An item page read to settle a candidate row (pending source read)

The Orange Mushroom page has a row "Scroll for Shoes for Jump" (2040705, `0.0300% base | Qty 1`) that may be Hidden
Street's member "Scroll for Shoes for Jump 10%" (MeowDB 177, Shoes Jump Scroll: Greater: success rate 10%, Jump +3).
The row's name carries no success rate, so until its item page is read it is a `pending_kuro_candidates` row of
`game/data/canonical/drops/9.json`, and the member never rolls. To apply the read:

1. Open <https://playkuro.com/database/#items/2040705> in a normal browser (the Cloudflare check needs a person).
2. Save `item_2040705.json` here, in the shape of the monster captures:
   `{"kuro_item_id": "2040705", "url": "https://playkuro.com/database/#items/2040705", "read_at": "<ISO 8601 with a
   zone>", "method": "<how it was read>", "site_updated_label": "<the page's 'Updated ...' label>", "text": "<the
   rendered page text, verbatim, starting 'ITEM · 2040705'>"}`. Do not edit the text: the loader reads the name,
   category, description, the `ITEM STATS` label/value lines, `MONSTER DROPS` and `REACTOR DROPS (N)` from it, and
   the success rate (an `ITEM STATS` row whose label names `SUCCESS`, else "Success rate: N%" in the description) and
   the `+N` stat bonuses (`ITEM STATS` rows valued `+N`, else the description). The page's item name must be the
   monster page row's name exactly ("Scroll for Shoes for Jump"): both come from one site's item data, so a different
   name means the page changed since the monster page was read, and the merge stops with an error rather than judge
   it (read the monster page again too). The validator then also checks that the capture the record cites exists.
3. `node tools/meowdb/extract_monsters.mjs` (twice: byte-identical). The merge (`tools/sources/drops_merge.mjs`
   `judgeKuroCandidate`, crosswalk rule `confirm_with: meowdb_scroll`) then decides from the page alone: the same success
   rate and exactly the same stat bonuses as MeowDB 177 make the row the member's chance (`alias_with_evidence`, the page
   cited in `chance_source.match_evidence`); another rate or stat moves it to `excluded_kuro_only` (rejected), and a page
   that shows neither leaves it excluded as not settled. Either way it leaves `pending_kuro_candidates`.
4. Remove the `drop:9/scroll-for-shoes-for-jump-10` declaration from `tools/parity/rules.json` `pending_source_reads`
   (the parity build fails on it as stale), update the crosswalk row's `reviewer_note`, then run
   `node tools/meowdb/build_sources_index.mjs`, `node --test tools/sources/test/` (the drop tests follow the capture:
   no test pins the pending state), `bash scripts/validate_data.sh --report`, the unit suite and the parity build.

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
