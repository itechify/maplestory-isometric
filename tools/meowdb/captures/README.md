# MeowDB captures (live pages read by hand)

MeowDB MS Classic (<https://meowdb.com/msclassic>) stays MisoStory's primary authority. Its bulk data comes from the
extractors' local cache (`tools/meowdb/.cache`, git-ignored, read 2026-10-04). Since Iteration Three the extractors
read that cache (decision D3-1 in `docs/ITERATION_LOG.md`): `tools/meowdb/lib.mjs` touches the network only with
`MEOWDB_ALLOW_NETWORK=1`. Facts that are newer than the cache, or missing from it, have come in as these dated
captures: pages read one at a time by a person in a normal
browser on 2026-10-05 and saved here.

| File | Page | What it gives |
|---|---|---|
| `monster_1.json`, `monster_2.txt`, `monster_3.json`, `monster_4.json`, `monster_5.json`, `monster_9.json` | the six Maple Island monster pages | the stagger time (`STAGGER 0.6 seconds`, `stagger_ms` in the monster records; the cache predates the field), the Snail's meso report (`Mesos: 2 per kill \| 1 report`, decision D3-12), MeowDB's community drop list "Drops (MS Classic)" with its votes (the drop records' membership, every entry, decision D3-11) and its MSEA reference list (kept as `meowdb_reference`, never a member), and the Maple Island spawn rows (`node tools/sources/check_spawn_captures.mjs`) |
| `breakable_0000001.txt` | Wooden Box | the box's drop membership (Old Wooden Board, Rusty Screw, Apple, Egg; D3-11), hits to break, the maps it spawns on |
| `quest_tracker_maple_island.txt` | the quest tracker, Maple Island area | that the cached 20 quests (1000-1019) are still the whole Maple Island set (D3-2), their chains, and the `Missable` and `COT2` tags written into every quest record |
| `quest_1008.txt` | Lucas's Reply | a spot check that the cached quest pages still match the live site (random reward table, dialogue); no record reads it |
| `items_api.json` | item API bodies 242, 486, 495, 498 | Nothing today: none of the four items is extracted. Green Apple (242) has no cached item page, and its record was built from this body (`extract_items.mjs`, served by `lib.mjs` for exactly that URL) until #32 removed it from the item subset (2026-10-06). The three "Omok Piece: Mushroom" items were never extracted. The bodies stay as dated records |
| `item_242.txt` | Green Apple's item page (read 2026-10-05T22:11:30.520Z) | Nothing today (#32, as above; `extract_items.mjs` notes the capture and skips it). It gave the rows the API body lacks: Max per Stack 100, the Tradeable tag, "NPC Sell-back (per unit)" 3 mesos (the per-unit basis) and the MSEA reference drop (Mano, Lv 20) |

One exception to "read by navigating", recorded in D3-1: items 495, 498 and 242 were read through the page's own
`fetch()` at human pace (3 requests, 1.5 s apart), not by opening each URL. `items_api.json` records only a session
time in its `method` text, so the loader derives its read time and flags it `read_at_approximate`.

## Formats

- **`.txt`**: `KEY: value` header lines, a `---` line, then the rendered page text trimmed to the record. An item page
  (`item_<id>.txt`) is read only for what its text shows: the card's value rows and tags, the description line and the
  sections present; a section the trimmed text leaves out is never read as empty. `URL` and
  `READ_AT` (ISO 8601 with a zone) are required; `METHOD` and `PURPOSE` say how and why it was read, and a value may
  continue on indented lines. The quest tracker capture's `READ_AT_NOTE` explains its normalised read time.
- **`monster_<id>.json`**: `{url, read_at, method, head, drops, maple_island_map_rows}`, the page text split into the
  record's head, its drop sections and its Maple Island spawn rows.
- **`items_api.json`**: `{method, search_results, items: {<id>: {url, body}}, conclusions}`, each `body` the API's JSON
  verbatim.

`tools/sources/captures.mjs` loads every file here (this README is skipped). A file name it does not know, a read time
that is not ISO, or a parsed row that is not in the captured text stops it, so a new capture is never silently ignored:
a new kind of page needs a reader there first. Check a change with `node --test tools/sources/test/`.

## Using and updating a capture

Every value taken from a capture cites the capture's path next to the page URL (`field_sources`, `provenance`,
`membership_source`), and `bash scripts/validate_data.sh` checks that the file exists. Do not re-collect these pages
automatically. To update a value, read the page again in a browser, replace the capture with the new reading and its
own read time, then regenerate what reads it (`node tools/meowdb/extract_monsters.mjs`, `extract_quests.mjs` or
`extract_items.mjs`, then `node tools/meowdb/build_sources_index.mjs`). How to capture a page:
`docs/runtime/HOWTO.md` "Capture a source page by hand".
