# Canonical data: NPCs (and their dialogue)

Authority: MeowDB MS Classic (https://meowdb.com/msclassic), the database for MapleStory Classic World. All ids are
MeowDB ids (NPC `"1"` = Heena, map `"000000001"` = Mushroom Town - West Entrance, quest `"1000"`, item `"438"`). They
are not GMS ids.

- Output: `game/data/canonical/npcs/<id>.json`, one NPC per file, 21 files.
- Extractor: `node tools/meowdb/extract_npcs.mjs`. It reads only from the `tools/meowdb/.cache` page cache through
  `lib.mjs` and prints `"network_fetches": 0` when the cache is complete. Re-running it reproduces the files byte for
  byte. `--checks` also prints the cross-check log. The exit code is non-zero if any extracted line is missing from
  the visible text of its source page.

## Pages read

| Page | Count | Retrieved (UTC, 2026-10-04) | Used for |
|---|---|---|---|
| `/maps/<id>` for the 25 Maple Island maps | 25 | 09:56:36 to 09:57:12 | Which NPCs stand on each map (`npcs: [{id, name, x, y}]`), px positions, speech-bubble preview (`talkers`) |
| `/npcs/<id>` for ids 1 to 21 | 21 | 10:04:26 to 10:06:41 | Name, role tags, function title, location, "What X Says" (dialogue and idle chatter), Quests Given / Turned In, shop block, "What They Do" |
| `/npcs/all` | 1 | 10:06:43 | Cross-check: the index category each NPC is filed under |
| `/npc-shops` | 1 | 09:57:45 | Cross-check: shop slug, `npcId`, `mapId`, item ids |
| `/quest-tracker/<id>` for quests 1000 to 1019 | 20 | 09:59:45 to 10:07:39 | Start and completion NPC (`quest.npc`, `quest.completeNpc`), the "NPC Dialogue" sections, `itemRefs` |
| `/item-db/347`, `/item-db/2584` | 2 | 10:11:48, 10:11:49 | Resolving one dialogue item-link discrepancy (see Discrepancies) |
| `/guides/beginners-guide-first-steps-in-maple-world` | 1 | 10:06:38 | Shanks' boat: destination, fare, level, one-way |
| `/world-map` | 1 | 10:10:07 | Map id of Lith Harbor (`010000000`) |

The exact `retrieved_at` of every page is in each file's `source` / `field_sources`.

How the data is stored on the pages: NPC pages have no single JSON object for the NPC. The content is a server-rendered
React tree in the Next.js flight payload, split over lazily referenced rows (`"$L4a"`). The extractor resolves those
references into one tree and walks it by structure (h1, section headings, `blockquote` keys `d0..`, `li` keys `c0..`,
`tr` keys `<itemId>-<n>`). Map and quest pages do carry plain JSON (`npcs`, `quest`, `itemRefs`, `npcPlacements`).
The extractor reads those directly. No images are fetched or stored. Portraits and icon URLs are skipped.

## Which NPCs and why

The list comes from the 25 map pages, not from memory. 14 maps have NPCs. These 11 maps have none: 000000041,
000000042, 000001000 to 000001006, 000001012, 000001014, 000001020, 000001021. Together the 14 maps hold exactly
21 NPCs, MeowDB ids 1 to 21, and each NPC appears on exactly one map:

| id | name | map | x_px, y_px | roles | quests (given / turned in) | other |
|---|---|---|---|---|---|---|
| 1 | Heena | 000000001 Mushroom Town - West Entrance | -46, 280 | Quest Giver | 1000 / 1001 | |
| 2 | Sera | 000000001 Mushroom Town - West Entrance | 833, 125 | Quest Giver | 1001 / 1000 | |
| 3 | Roger | 000000010 Mushroom Town | 233, 58 | Quest Giver | 1002 / - | completes 1002 itself |
| 4 | Nina | 000000020 Mushroom Town | -59, 86 | Quest Giver | 1003 / 1004 | |
| 5 | Sen | 000000021 Mushroom Town Townstreet | 24, 246 | Quest Giver | 1004 / 1003 | |
| 6 | Peter | 000000030 East Entrance to Mushroom Town | 1314, -925 | Quest Giver | - / 1005 | |
| 7 | Todd | 000000030 East Entrance to Mushroom Town | -21, 202 | Quest Giver | 1005 / - | |
| 8 | Robin | 000000040 Snail Hunting Ground I | 69, 275 | Townsfolk | - | |
| 9 | Sam | 000000040 Snail Hunting Ground I | 1602, 211 | Quest Giver | 1006 / - | |
| 10 | Maria | 000000050 A Split Road | 159, 65 | Quest Giver | 1007 / 1008 | |
| 11 | Mai | 000000050 A Split Road | 1891, -182 | Quest Giver | 1009, 1010 / 1006 | completes 1009, 1010 itself |
| 12 | Biggs | 000000060 Southperry | 950, -193 | Quest Giver | 1011 / - | completes 1011 itself |
| 13 | Yoona | 000000060 Southperry | -18, 287 | Townsfolk | - | |
| 14 | Bari | 000000060 Southperry | 1013, 527 | Townsfolk | - | |
| 15 | Shanks | 000000060 Southperry | 3223, -13 | Transport | - | boat to Lith Harbor (out of scope) |
| 16 | Pan | 000000061 Southperry Armor Store | -270, 138 | Shopkeeper ("Armor Seller") | - | shop `maple-road-pan` |
| 17 | Lucas | 000001010 Amherst | 1790, 154 | Quest Giver | 1008 / 1007 | |
| 18 | Pio | 000001010 Amherst | 547, 274 | Quest Giver | 1012 / - | completes 1012 itself |
| 19 | Rain | 000001010 Amherst | 103, 274 | Quest Giver | 1013 to 1019 / - | completes 1013 to 1019 itself (quiz) |
| 20 | Sid | 000001011 Amherst Weapon Store | -270, 138 | Shopkeeper ("Weapon Seller") | - | shop `maple-road-sid` |
| 21 | Lucy | 000001013 Amherst Department Store | -258, 84 | Shopkeeper ("Grocer") | - | shop `maple-road-lucy` |

## File format (every field)

```jsonc
{
  "id": "1",                       // MeowDB NPC id (string)
  "name": "Heena",                 // NPC page h1
  "roles": ["Quest Giver"],        // role tag(s) under the name on the NPC page. Values seen: Quest Giver, Townsfolk, Transport, Shopkeeper
  "function_title": null,          // italic subtitle under the name, only on shopkeepers: "Armor Seller" | "Weapon Seller" | "Grocer"
  "locations": [{                  // one entry per map the NPC page lists (always exactly one here)
    "map_id": "000000001",         // MeowDB 9-digit map id
    "map_name": "Mushroom Town - West Entrance",
    "street_name": "Maple Road",   // MeowDB "street" (region label) shown next to the map name
    "x_px": -46, "y_px": 280       // MapleStory map px, y DOWN, same space as that map's portals/footholds (from the map page)
  }],
  "dialogue": [Line],              // quoted lines under "What <name> Says" (blockquotes d0, d1, ...), page order
  "idle_chatter": [Line],          // the "Idle chatter" list (li c0, c1, ...). This is also the speech-bubble pool
  "quests": {
    "given":     [{"id", "name"}], // "Quests Given (n)" on the NPC page, page order
    "turned_in": [{"id", "name"}], // "Quests Turned In (n)" on the NPC page. Only quests whose completion NPC differs from the start NPC
    "started_here":   ["1000"],    // derived from the quest pages: quest.npc == this NPC (always equals given)
    "completed_here": ["1001"]     // derived from the quest pages: (quest.completeNpc ?? quest.npc) == this NPC. Includes self-completed quests
  },
  "quest_dialogue": [QuestDialogue],
  "shop": null | {
    "shop_id": "maple-road-pan",   // MeowDB has no numeric shop id; this is the /npc-shops anchor slug, the same id as game/data/canonical/shops/<slug>.json
    "sold_at_map_id": "000000061",
    "item_ids": ["933", ...],      // MeowDB item-db ids, NPC page shop-table order
    "item_names": ["White Undershirt", ...]   // same order. Prices are deliberately NOT here; they belong to the shops domain
  },
  "transport": null | { "routes": [Route] },  // Shanks only
  "what_they_do": ["..."],         // "What They Do" bullet list, verbatim (shopkeepers and Shanks only)
  "source": { "authority": "MeowDB MS Classic", "url": ".../npcs/<id>", "retrieved_at": "..." },
  "field_sources": { ... },        // see below
  "notes": [...], "gaps": [...], "discrepancies": [...]   // only when non-empty
}
```

`Line`: `{ "text": "plain text" }`, plus `"segments"` when the line has any markup. `text` is the concatenation of
the segments, with leading and trailing whitespace trimmed and `\n` where MeowDB renders a `<br>`. Segments mirror
MeowDB's rendering of MapleStory script markup:

- `{ "text", "bold": true }`: emphasised words (MeowDB `font-semibold text-maple-text`). These are keys, UI names,
  NPC, map and item names (for example "Jr. Sentinel Shellpiece" in 1005 and "Orange Mushroom Cap" in 1011), and quest
  item counts.
- `{ "text", "color": "red" }`: red text (MeowDB `text-rose-400`). It marks:
  - monster names (quests 1005, 1006, 1009, 1010, 1011) and Roger's Apple (1002);
  - kill counts ("3 " in 1005, "10 " in 1006, "1" in 1010);
  - keys ("Z", "Ctrl" in 1005; "Key Config" and the correct-answer "up arrow key" in 1013);
  - "ship" in 1019.
- `{ "text", "ref": { "kind": "npc" | "map" | "item" | "monster" | "quest", "id": "<MeowDB id>" } }`: a linked name.
  The link's item id comes from its href. The icon of an inline item (`#i`/`#t` style) is dropped. If an inline item
  had no link, its id would come from the quest page's `itemRefs`, but no such case occurs today.
  `ref.meowdb_link_id` appears only where the extractor corrected a link (see Discrepancies).
- These keys combine. When MeowDB wraps a link in a styled span, the `ref` segment also carries that span's `bold` or
  `color`. Examples: quest 1000's "Sera" is `{bold, ref npc 2}`, and quest 1009's "Blue Snail" is
  `{color "red", ref monster 3}`. A styled span holding a count and a link ("3 " + "Tutorial Jr. Sentinels") becomes
  two segments with the same style. Per quest page, the styled segments account for every `font-semibold` /
  `text-rose-400` span MeowDB renders in the dialogue.

`QuestDialogue` holds one dialogue section of one quest:

```jsonc
{
  "quest_id": "1001", "quest_name": "Bringing a Mirror to Heena",   // name from the quest page
  "npc_role": "start" | "complete",   // "start": the "On accept" section, filed under quest.npc
                                      // "complete": the "On completion" section, filed under quest.completeNpc ?? quest.npc
  "start_npc_id": "2", "complete_npc_id": "1",
  "section": "On accept" | "On completion",          // MeowDB heading, verbatim
  "lines": [Line],                    // the section's main pages, in order (each <p> is one dialogue window page)
  "branches": [{ "key": "yes", "label": "If you accept", "lines": [Line] }],
  "quiz": null | {
    "question": Line,
    "options": [{ ...Line, "correct": true | false | null, "malformed_markup"?: "#L2 #" }],   // display order
    "correct_option_index": 2 | null,   // 0-based index into options; null when MeowDB marks none
    "notes"?: [...]
  },
  "notes"?: [...]
}
```

Branch `key` is MeowDB's own element key, kept verbatim. The `label` is MeowDB's text, also verbatim:

| key | label (verbatim) | section | meaning as MeowDB labels it |
|---|---|---|---|
| `yes` | If you accept | On accept | player accepted |
| `no` | If you decline | On accept | player declined |
| `yes` | When you have everything ready | On completion | completion conditions met |
| `stopItem` | If you don''t have the items yet | On completion | required items missing |
| `stopMob` | If you haven''t defeated enough monsters | On completion | kill count not reached |
| `stopNpc` | If you haven''t met the right NPC yet | On completion | wrong NPC / not delivered yet |
| `lost` | If you lost the items | On completion | quest item lost, re-issue |
| `null` | If you pick the wrong answer | On completion (quiz) | one line per wrong option, in option order |
| `null` | When you answer correctly | On completion (quiz) | correct answer response |

The doubled apostrophe in `don''t` / `haven''t` is how MeowDB itself renders those labels (an escaping artifact on
MeowDB's side). It is kept verbatim. Fix it in the UI layer if the label is ever shown; the labels are not player-facing
dialogue.

`field_sources` keys: `locations/<map_id>` (the map page that supplied `x_px`, `y_px`), `quest_dialogue/<quest_id>/<npc_role>`
(the quest page of that block), `shop` (the `/npc-shops` page, used as a cross-check only), and `transport` /
`transport/to_map_id`. Each value is `{url, retrieved_at}`, plus `fields` or `note` where the scope needs saying.

## Using the data in the game

- **Interaction behaviour**: derive it from the data. MeowDB has no "interaction type" field. Quest NPCs have
  `quest_dialogue`. Shopkeepers have `shop` (open `game/data/canonical/shops/<shop_id>.json`). Shanks has `transport`.
  Robin, Yoona and Bari only have `dialogue` and `idle_chatter`.
- **Default talk**: `dialogue` is what MeowDB quotes under "What <name> Says". Every quest giver and townsperson has
  exactly two lines (`d0`, `d1`). MeowDB does not say when each is shown. For quest NPCs the second line often reads
  like a post-quest line (Heena: "Now I can examine my face with this mirror"; Maria: "I'm so glad my message was
  delivered"), but that is not labelled, so the files do not tag it. Choosing the line by quest state is a MisoStory
  design decision.
- **Speech bubbles**: `idle_chatter` is exactly the `lines` array the NPC page feeds to its speech-bubble component.
  MeowDB gives no display interval or ordering rule.
- **Quest dialogue partition**: every quest dialogue section is in exactly one NPC file. "On accept" goes to the start
  NPC and "On completion" to the completion NPC. The 20 quests give 39 sections, because quest 1002 has no "On accept".
  To get all dialogue of a quest, read the start NPC's `start` block and the completion NPC's `complete` block, using
  `start_npc_id` and `complete_npc_id`. The quests domain (`game/data/canonical/quests/`) carries the same dialogue
  per quest. Treat that domain as authoritative for objectives and rewards. This file carries no rewards, levels or
  requirements.
- **Speaker caveat**: MeowDB groups branches under "On accept" or "On completion" but never names the speaker of a
  branch. When start and completion NPCs differ, the completion section's `stopNpc` and `lost` texts read as if the
  start NPC says them. Example: quest 1001's `stopNpc` "It looks like you haven't delivered the mirror to Heena yet"
  is filed under Heena but reads as Sera's line. Those entries carry a `notes` line saying so. The files keep MeowDB's
  grouping. The routing decision belongs to the quest framework.
- **Quizzes (Rain, 1013 to 1019)**: each quiz is the "On completion" section of its quest. `options` are in MeowDB's
  display order. MeowDB numbers them oddly ("1., 1., 2., 3.") because its renderer nests the options, so those
  numbers are dropped. The first option of each quiz often has a `bold` segment. That is a side effect of the same
  nesting, because MeowDB wraps the later options inside the first option's emphasis span. Ignore it when rendering.
  `correct` comes from MeowDB's "Correct answer" marker. Quiz 6 (1018) has no marker, and its
  third option arrives as raw markup (`#L2 # 5 points`). The extractor splits that into a third option, flags it with
  `malformed_markup`, and leaves every `correct` null. MeowDB's "When you answer correctly" line for 1018 says
  "You get 5 AP with each level". Whether to rely on that is a gameplay decision; nothing was filled in.
  The wrong-answer lines address the first two options ("more than 1 measly point", "not 2 points").
  `game/data/canonical/quests/1018.json` does it differently. It keeps the malformed text fused into one choice
  (`"2 points\n#L2 # 5 points"`, 2 choices) and marks both choices `correct: false`, not null.
- **Rendered counters**: Pio's quest 1012 accept line ends with "Rusty Screw 0/3" and "Old Wooden Board 0/3". The `0`
  is a bold literal that MeowDB rendered. It reads like the player's current item count, but MeowDB does not label it
  as one. Treat it as a placeholder rather than fixed text if the UI shows progress.
- **Positions**: `x_px`/`y_px` are MapleStory px from the map page (y grows downward), in the same frame as that map's
  portals and footholds. Pan (000000061) and Sid (000001011) share the same coordinates (-270, 138) because the two
  shop interiors use the same layout. This is not an error. The 3D adaptation belongs in `data/misostory`, not here.
- **Shanks**: `transport.routes[0]` = Southperry (`000000060`) to Lith Harbor (`010000000`), `fare_mesos: 300`,
  `min_level: 7`, `one_way: true`, with the guide sentence verbatim in `source_quote`. It is recorded but out of scope
  for Iteration Two gameplay, because it leaves Maple Island. Supporting text elsewhere on MeowDB: Pio's second
  `dialogue` line ("You'll need to take a ship from Southperry and head to Victoria Island") and Rain's quiz 7
  correct-answer line ("talk to Shanks, and get on the ship that heads to Victoria Island").

## Cross-checks performed (all passed)

- Every NPC on the 25 map pages has an NPC page, and every NPC page's Location map lists that NPC. The map page and
  NPC page agree on names and map names.
- The role tags on the NPC page match the category `/npcs/all` files the NPC under (Quest Giver 14, Townsfolk 3,
  Transport 1, Shopkeeper 3).
- "Quests Given" equals the set of quest pages whose `quest.npc` is this NPC. "Quests Turned In" equals the quest pages
  whose `completeNpc` is this NPC. Quest names agree between NPC pages and quest pages.
- Shop blocks: the slug, `npcId`, `mapId`, item ids (same order) and `npcFunction` on `/npc-shops` agree with the NPC page.
- The map pages' speech-bubble `talkers.lines` are a prefix of the NPC page's idle chatter for all 21 NPCs (see below).
- Every extracted dialogue, chatter, quiz question and option line appears in the visible text of its source page.

An independent review (2026-10-04, separate scripts, cache only) re-checked all of this and found one extractor bug,
now fixed. Before the fix, `bold` / `color` was dropped on any linked segment, so "Roger's Apple" (1002) and every red
monster name had no `color`. The review checks were:

- **Visible text, in order.** Every NPC page's "What X Says" and every quest page's "NPC Dialogue" was consumed in
  order from the files. Nothing was missing and nothing was left over except headings, labels and quiz numbering.
- **Line splits.** `<p>` / `<li>` counts equal the line counts for all 20 quests.
- **Links.** Every link became a ref with the href's id.
- **Quiz answers.** The correct option of every quiz is the emerald-styled option that carries the "Correct answer"
  marker. It agrees with each "When you answer correctly" line.
- **Styled spans.** The raw bold/red span counts are fully accounted for by the styled segments.
- **Quests domain.** Line texts are identical to `game/data/canonical/quests/` except quiz 1018's malformed third
  option (see Quizzes).

## Discrepancies

1. **Dialogue item link for "Jr. Sentinel Shellpiece" (quest 1005; Todd's `start` block, Peter's `complete` block).**
   The dialogue links item-db **2584**. The same quest page's `itemRefs` table uses item-db **347**
   ("Jr. Sentinel Shellpiece", icon key 4000000, which equals the quest payload's item). Item 2584 is a different entry
   with the same name (icon key 4000067). Chosen: **347**. The dialogue link looks name-resolved, and 347 is the
   item the quest actually uses. `segments[].ref.meowdb_link_id: "2584"` keeps the original link, and both NPC files
   have a structured `discrepancies` entry. Item 347's page lists "Needed By: Todd's How-to-Hunt" (qty 3). Item 2584's
   page lists "Collecting Huckle's Magic Ingredients" (qty 30) instead.
   The quests domain also picks 347 (for its objective), but its dialogue segments keep MeowDB's raw link
   (`ref.id: "2584"`). So when joining dialogue refs across the two domains, map 2584 to 347 for this quest, or compare
   `meowdb_link_id`.

Not a discrepancy, but easy to misread: map pages show at most the first 4 idle-chatter lines in their talker preview
(Heena 4 of 8, Sera 4 of 9, Roger 4 of 9, Peter, Todd, Robin and Sam 4 of 10, Rain 4 of 8). The NPC page has the full
list, and `idle_chatter` uses it.

## Gaps (what MeowDB does not provide)

- **Conditions for `dialogue` lines**: `d0` and `d1` are unlabelled. MeowDB never says which line shows before or
  after the NPC's quest.
- **Shop greeting**: Pan, Sid and Lucy have no separate shop-open greeting and no quoted dialogue. "What <name> Says"
  lists only their bubble lines. MeowDB also shows no buy/sell confirmation text.
- **Shanks**: no quoted dialogue (only the two bubble lines). No boarding prompt or Yes/No text, no
  insufficient-mesos or level-too-low text, no arrival map or spawn point, no travel time. The route facts come from
  one prose sentence in MeowDB's editorial beginner guide (updated 2026-10-02), not from structured data. The
  destination id is the world-map spot "Lith Harbor" (`010000000`), which may not be the exact arrival map.
- **Quest dialogue holes, exactly as MeowDB shows them**:
  - 1002 Roger's Apple has no "On accept" at all. Its "On completion" is only the `stopItem` branch.
  - "On completion" has no main lines, only conditional branches, for 1000 (only `stopNpc`), 1003 (only `stopNpc`)
    and 1007 (`stopItem`, `stopNpc`, `lost`).
  - Rain's quizzes 2 to 7 have no accept or decline branches, only the main "On accept" line.
  - 1018's quiz has no correct-answer marker and has malformed option markup (see above).
- **Speaker per branch**: not labelled (see Speaker caveat).
- **NPC presentation**: no facing direction or flip, foothold, hide/visibility flags, script names, or NPC size or
  touch box. Portraits exist on MeowDB but are proprietary art and intentionally not stored.
- **Minimap marker**: the NPC page has a minimap marker (`leftPct`/`topPct`) for 18 of the 21 NPCs. It is not
  extracted because the map page's px position is exact and the marker is derived from it. Pan, Sid and Lucy have
  `marker: null`.
- **Idle chatter timing**: no interval, no randomisation rule, no range.

## Referenced ids (for other domains)

- Quests (start/complete links): 1000 to 1019.
- Shops: `maple-road-pan` (NPC 16), `maple-road-sid` (NPC 20), `maple-road-lucy` (NPC 21).
- Items:
  - In shop blocks: 933, 934, 935, 937, 938, 939, 940, 1157, 1158, 1160, 1161, 1305, 1306 (Pan); 541, 576, 585,
    558 (Sid); 270, 271, 236, 237, 239, 269 (Lucy).
  - In quest dialogue: 235 Roger's Apple, 347 Jr. Sentinel Shellpiece (MeowDB link 2584), 349 Blue Snail Shell,
    356 Orange Mushroom Cap, 438 Sera's Mirror, 441 Rusty Screw, 442 Old Wooden Board, 270 Red Potion.
- Monsters named in dialogue: 1 Tutorial Jr. Sentinel, 2 Snail, 3 Blue Snail, 4 Shroom, 5 Red Snail, 9 Orange Mushroom.
- NPCs outside this domain named in dialogue: 313 Grendel the Really Old (in Todd's quest 1005 text).
- Maps named in dialogue or transport: 000000050, 000000060, 000001010, and 010000000 (Lith Harbor, Victoria Island).
