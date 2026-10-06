# Drop item crosswalk (reviewed)

`drop_items.json` joins every member of a drop owner's membership list to a local MeowDB item and to a row of the
owner's KuroDB page, **by name**. The three sites use unrelated item ids (decision D3-4): KuroDB 4000019 is Snail
Shell, while MeowDB's `game_item_id` 4000001 is Snail Shell and KuroDB 4000001 is Orange Mushroom Cap. A join by id
silently produces wrong drops, so nothing in the drop pipeline does one.

| Owner | Membership (what can drop) | Chance (how often) |
|---|---|---|
| Monsters 1 2 3 4 5 9 | Hidden Street "Before Chaos" lists, `tools/hiddenstreet/captures/monsters.json` (D3-6) | KuroDB monster page, `tools/kurodb/captures/<kuro id>.json` |
| Wooden Box 0000001 | MeowDB's live breakable page, `tools/meowdb/captures/breakable_0000001.txt` (D3-7) | KuroDB reactor 2001 rows on the item pages, `tools/kurodb/captures/reactor_2001_items.json` |

Each row has:

- `meowdb`: `state` (`resolved` | `not_in_snapshot` | `ambiguous`), `item_id` (a local item, only when resolved),
  `method` (`exact` | `normalized` | `alias_with_evidence` | `none`), `candidates` (MeowDB ids seen in the cache) and
  `evidence`. `normalized` uses `tools/sources/parse.mjs normalizeItemName`; a `(M)`/`(F)` suffix must match the local
  item's `gender`.
- `kurodb`: `state` (`matched` | `none`) with `kuro_item_id`, `kuro_name`, `method`, `evidence`; optionally, on a
  `none` row, a `candidate`: a KuroDB row that may be the member under another name (D3-8), with a `reason` and
  `confirm_with`, the rule its KuroDB item page is judged by (`meowdb_scroll`: the page shows the success rate and
  exactly the `+N` stat bonuses of the member's MeowDB scroll). Until the page is captured as
  `tools/kurodb/captures/item_<kuro id>.json` the row is written to the record's `pending_kuro_candidates` (the
  member's chance is a pending source read, not a gap). With the capture, the merge confirms it (the member's chance,
  `alias_with_evidence`, the page cited in `chance_source.match_evidence`), or excludes it (`excluded_kuro_only`, with
  what the page showed: another rate or stat rejects it, a page that shows neither does not settle it). See
  `tools/kurodb/captures/README.md` for the capture and the steps after it.
- `reviewer_note` (required, never empty): the reviewer's verdict on the row, what was re-checked and what follows (it
  rolls, or why it never does). The merge copies it into the record entry's `notes[0]`.

`tools/sources/drops_merge.mjs` reads it (through `tools/meowdb/extract_monsters.mjs`, the single writer of
`game/data/canonical/drops/*.json`) and fails on anything the captures or the local items do not support: a member
without a row, a row without a member, a KuroDB claim that is not on the page (by KuroDB's own id and name), a `none`
whose page does list the member, a resolved item that is not local or whose name does not match, an unresolved row
whose candidate has become a local item, a row without a reviewer note, an item page capture whose name is not the
candidate's. A KuroDB row no member claims becomes an `excluded_kuro_only` row; a candidate waiting for its item page
is a `pending_kuro_candidates` row instead.

## Changing a row

1. Read the evidence again (the dated capture, the local item, the MeowDB cache file named in the row).
2. Edit the row and its evidence. Do not resolve an ambiguous name by guessing: leave it `ambiguous` and say why.
3. `node tools/meowdb/extract_monsters.mjs` (twice: the output must be byte-identical), then
   `node tools/meowdb/build_sources_index.mjs` and `node --test tools/sources/test/`.

## Open rows (all unresolved and visible in the records' `gaps`)

- `Omok Piece : Mushroom` (Orange Mushroom): KuroDB gives 1%, but MeowDB has three items of that name (486, 495, 498),
  all quest items with no drop source (D3-8).
- `Scroll for Shoes for Jump 10%` (Orange Mushroom): resolved to MeowDB 177 (Shoes Jump Scroll: Greater, 10%), but its
  KuroDB row "Scroll for Shoes for Jump" (2040705, 0.03%) has no success rate and the KuroDB item page was not read
  (D3-8), so the chance is unresolved: a `pending_kuro_candidates` row (a pending source read) until
  `tools/kurodb/captures/item_2040705.json` exists.
- Gender-suffixed names with two MeowDB items each: Blue Cloth Vest (M) (949/958), Black Cloth Pants (M)/(F)
  (1170/1179), Blue Cloth Pants (M) (1169/1178).
- No MeowDB item in the local cache: Pan Lid, Wooden Samurai Sword, Pistol.
- 22 more rows (20 distinct MeowDB ids) have a MeowDB id in the cache but no local item definition
  (`not_in_snapshot`). None of them has a KuroDB chance, so none would drop even once resolved.
