# Henesys.gg captures (rarity labels read by hand)

Henesys.gg's item database (<https://henesys.gg/loot>, MapleStory Classic World) gives each item a rarity label:
Common, Rare, Very Rare or Extremely Rare. MisoStory uses that label for one property only, the `rarity` of a drop
record entry (decision D3-11 in `docs/ITERATION_LOG.md`). The label picks the column of the project owner's drop
chance table (`game/data/misostory/drop_rates.json`); Henesys.gg gives a rarity per item, not per monster, and no
drop chance. Everything else about a drop (who drops what, item ids, item data, meso reports) comes from MeowDB MS
Classic.

| File | Page | What it gives |
|---|---|---|
| `item_rarity.json` | the loot page, read 2026-10-06 | the rarity label of every item on the MeowDB community drop lists of the six Maple Island monsters and the Wooden Box (64 items). All are Common except "Overall Armor DEF Scroll: Intermediate" (Rare). `row` keeps the row as the page showed it |

## How the labels were read

The labels here were read by a person in a normal browser, through the page's own search box over the list it loads
once.

## Format

`item_rarity.json`: `{site, url, read_at, read_started_at, method, scope, site_notice, rarity_labels_seen, items:
{<item name>: {row, rarity, note?}}}`. The item name is MeowDB's name for the item (today every name is the same on
both sites; a name that differed would need a small MeowDB-name to Henesys-name map in
`tools/sources/drops_merge.mjs`). `tools/sources/captures.mjs` loads it and checks that the URL is the loot page, the
read time is ISO 8601, every rarity is one of the four labels, every `row` starts with the item's name, and each page
row it quotes ends with that label (two rows with one name are joined by "  /  "; a note in place of a repeated row,
such as Red Cloth Pants' "(a second row with the same name and values)", quotes no row and is not checked).

## Updating

Read the page again in a browser, update the rows that changed and `read_at`, then regenerate the drop records
(`node tools/meowdb/extract_monsters.mjs`, then `node tools/meowdb/build_sources_index.mjs`) and run
`bash scripts/validate_data.sh`. A drop-list item with no row here keeps `rarity: null`: it stays in the record,
listed as unresolved, and never drops.
