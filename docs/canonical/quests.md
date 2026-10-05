# Canonical data: Quests (Maple Island) and quest dialogue

- Authority: MeowDB MS Classic (https://meowdb.com/msclassic). No other source was used. No external values were filled in.
  Everything comes from the local cache (2026-10-04) except the quest tracker tags (`missable`, `tracker_tags`), which
  come from one dated capture of the live tracker read by hand (2026-10-05, decision D3-2; see §1).
- Output: `game/data/canonical/quests/<quest_id>.json`, one quest per file, 20 files (ids 1000–1019).
- Extractor: `node tools/meowdb/extract_quests.mjs`. It is cache-first, deterministic and validating. `--verbose` prints the item back-link checks. Re-running it reproduces the files byte for byte.

## 1. Pages read

| Page | Used for | retrieved_at (cache) |
|---|---|---|
| `/quest-tracker/all` | Quest index (322 quests). Selects the region by `area` id. Every quest object is compared field by field with its detail page. | 2026-10-04T10:04:38.951Z |
| `/quest-tracker/1000` … `/quest-tracker/1019` | The record itself: `quest` object, `prereqs`, `nextQuests`, `questLine`, `nextQuestGrants`, `itemRefs`, `npcPlacements`, and the server-rendered "NPC Dialogue" tree | 2026-10-04T09:59:45Z (1002), 10:07:11Z – 10:07:39Z (others) |
| `_next/static/chunks/7829-2a485fd328590c45.js` (the quest page's own JS) | The area-id → region label table (`{id:1,name:"Maple Island"}`), the completion-rule text "To complete: use Roger's Apple, then talk to Roger.", and the quest database "Requirement type" filter labels ("Item hand-in only", "Monster kills only", "Items + monster kills") | 2026-10-04T10:06:23.984Z |
| `/npcs` (NPC index) | Independent check: NPC id/name, map ids, `region: "MapleIsland"`, quests given, turn-in quests | 2026-10-04T09:57:42.013Z |
| `https://meowdb.com/_data/safe-to-sell.json` (MeowDB's dataset behind `/item-db/safe-to-sell`, `generated: 2026-08-11`) | Items needed by quests (`rows[].quests[].qty`). Cross-checks every hand-in count and that no quest item is missing. It is also the only MeowDB count for Roger's Apple in 1002 (qty 1, see §6 and §9), and its `ambiguous` item-name list is used as evidence in the 1005 discrepancy. | 2026-10-04T10:09:42.024Z |
| `/item-db/<id>` for every referenced item (235, 237, 239, 347, 349, 356, 438–442, 522, 558, 559, 708, 709, 711–715, plus 2584 and 270 linked from dialogue) | Item name and icon key match the quest data. Roger's Apple icon key. Back-links to the quest. | 2026-10-04T10:05Z – 10:17Z |
| `/monsters/1,2,3,4,5,9` | Monster name matches the kill objective | 2026-10-04T09:57Z – 10:07Z |
| `/guides/beginners-guide-first-steps-in-maple-world` | Human cross-check only (not extracted). It lists the Maple Island quests "straight from the quest tracker". Its totals (Rain's quiz 245 EXP = 20+25+…+50, Mai's chain 170 EXP and 15 Eggs) agree with the records. | 2026-10-04T10:06:38.610Z |
| `/quest-tracker?area=1`, the live tracker filtered to Maple Island, as the dated capture `tools/meowdb/captures/quest_tracker_maple_island.txt` (read by hand in a normal browser, never fetched; read through `tools/sources/captures.mjs`) | Each quest's tags ("COT2 · Missable"), which the cached pages do not carry: `missable` and `tracker_tags`. The row's name, start NPC, level ("Level N", absent = `min_level` 0) and chain step ("Step k of n" = `quest_line`) are cross-checked against the cached quest object. The page collapses Rain's quiz chain into one row ("Rain's Maple Quiz 1 … 7", "Step 1 … 7 of 7"), which is expanded to quests 1013–1019. | read_at 2026-10-05T07:30Z (normalized: the minute was not written down; see the capture's READ_AT_NOTE) |

Each JSON file carries its own `source` (the quest detail page), `field_sources` (the fields that came from another page) and `cross_checks` (the pages it was verified against). The two tracker fields are cited per property in `provenance.missable` and `provenance.tracker_tags` (contract C7: authority, URL, `read_at`, `capture`, the verbatim row as `raw_value`).

## 2. Which quests are included and why

Selection rule: every quest in `/quest-tracker/all` whose `area` is the id the quest page JS labels "Maple Island" (area 1). That gives exactly 20 quests, 1000–1019.

It was verified two independent ways. The extractor fails if either check breaks.

1. **By NPC and map.** In `/npcs`, the NPCs standing on maps with `region: "MapleIsland"` give or take turn-ins for exactly the set {1000…1019}. No Maple Island NPC is attached to a quest from any other area, and no other-area quest names a Maple Island NPC.
2. **Per quest.** The start and end NPC ids, names and map ids on the quest page match `/npcs`, and all of those maps are in region MapleIsland.

| id | name | start NPC (npc_id) @ map | end NPC (npc_id) @ map | min Lv | job | prereq | objectives | rewards | given on accept | follow-up |
|---|---|---|---|---|---|---|---|---|---|---|
| 1000 | Borrowing Sera's Mirror | Heena (1) @ 000000001 | Sera (2) @ 000000001 | 1 | Beginner | - | talk only | none | - (1001 starts with Sera's Mirror) | 1001 |
| 1001 | Bringing a Mirror to Heena | Sera (2) @ 000000001 | Heena (1) @ 000000001 | 0 | (none) | 1000 | hand in Sera's Mirror (438) x1 | 2 EXP | Sera's Mirror x1 (438) | - |
| **1002** | **Roger's Apple** | Roger (3) @ 000000010 | Roger (3) @ 000000010 | 1 | Beginner | - | use Roger's Apple (235) x1 (count from safe-to-sell.json, see §6), then talk to Roger | none | **none listed (see §6)** | - |
| 1003 | What Sen wants to eat | Nina (4) @ 000000020 | Sen (5) @ 000000021 | 1 | Beginner | - | talk only | none | - | 1004 |
| 1004 | Returning to Nina | Sen (5) @ 000000021 | Nina (4) @ 000000020 | 0 | Beginner | 1003 | talk only | 3 EXP | - | - |
| 1005 | Todd's How-to-Hunt | Todd (7) @ 000000030 | Peter (6) @ 000000030 | 1 | Beginner | - | kill Tutorial Jr. Sentinel (mob 1) x3; hand in Jr. Sentinel Shellpiece (347) x3 | 10 EXP | - | - |
| **1006** | **Sam's Suggestion** | Sam (9) @ 000000040 | Mai (11) @ 000000050 | 1 | Beginner | - | kill Snail (mob 2) x10 | 30 EXP; Egg (237) x3 | - | 1009 |
| 1007 | Letter for Lucas | Maria (10) @ 000000050 | Lucas (17) @ 000001010 | 2 | Beginner | - | hand in Maria's Letter (439) x1 | none | Maria's Letter x1 (439) | 1008 |
| 1008 | Lucas's Reply | Lucas (17) @ 000001010 | Maria (10) @ 000000050 | 0 | Beginner | 1007 | hand in Lucas's Letter (440) x1 | 50 EXP; random one of 7 hats (708, 709, 711–715), 14.3% each | Lucas's Letter x1 (440) | - |
| 1009 | Mai's Training | Mai (11) @ 000000050 | Mai (11) | 3 | Beginner | 1006 | kill Blue Snail (3) x10, Shroom (4) x10, Red Snail (5) x5 | 70 EXP; Egg (237) x5 | - | 1010 |
| 1010 | Mai's Final Training | Mai (11) @ 000000050 | Mai (11) | 0 | Beginner | 1009 | kill Orange Mushroom (9) x1 | 100 EXP; 150 mesos; Egg (237) x10 | - | - |
| 1011 | Biggs's Collection of Items | Biggs (12) @ 000000060 | Biggs (12) | 3 | Beginner | - | hand in Blue Snail Shell (349) x10, Orange Mushroom Cap (356) x1 | 70 EXP; random Fruit Knife (559) or Razor (558), 50% each | - | - |
| 1012 | Pio's Collecting Recycled Goods | Pio (18) @ 000001010 | Pio (18) | 5 | Beginner | - | hand in Rusty Screw (441) x3, Old Wooden Board (442) x3 | 100 EXP; 150 mesos; The Green Relaxer (522) x1 | - | - |
| 1013–1019 | Rain's Maple Quiz 1–7 | Rain (19) @ 000001010 | Rain (19) | 5 | Beginner | previous quiz | answer one quiz question each (1018: correct answer not marked by MeowDB, see §4) | 20 / 25 / 30 / 35 / 40 / 45 / 50 EXP; quiz 7 also Orange (239) x10 | - | next quiz |

Quest chains (MeowDB `questLine`): 1000→1001 · 1003→1004 · 1006→1009→1010 · 1007→1008 · 1013→1014→…→1019. 1002, 1005, 1011 and 1012 are standalone.

## 3. File format (every field)

All ids are strings exactly as MeowDB uses them (quest "1006", npc "9", mob "2", item-db "237", map "000000040").

| Field | Meaning / units |
|---|---|
| `id`, `name` | MeowDB quest id and name. |
| `region` | Label of MeowDB `area` from the quest page JS table ("Maple Island"). `area_id` is the raw MeowDB area number (1). |
| `quest_group` | MeowDB `parent`: the umbrella title shown under the quest name (e.g. "Sera's Mirror", "Rain's Maple Quiz"), or null. This is not a quest id. |
| `start_npc` / `end_npc` | `{npc_id, name}`. `end_npc` is MeowDB `completeNpc` when present, otherwise the start NPC. MeowDB shows "Start: X · Turn in: Y" when the two differ and a single "NPC: X" when they do not. `end_npc_listed_separately` is true when `completeNpc` exists. |
| `start_maps` / `end_maps` | `[{map_id, map_name, street_name}]` where the start/end NPC stands (MeowDB `npcPlacements`). The map name is MeowDB's (two different maps are both called "Mushroom Town": 000000010 and 000000020). |
| `min_level` | MeowDB `levelMin`, raw. **0 means MeowDB lists no level requirement.** All chain follow-ups (1001, 1004, 1008, 1010) have 0. |
| `max_level` | Always null: MeowDB has no maximum level. |
| `completion_min_level` | MeowDB `completeLevelMin` (level needed to turn in). Null for every Maple Island quest. |
| `job_restriction` | MeowDB `jobReq` (e.g. `["Beginner"]`, shown as "Beginner only"), or null when MeowDB lists none. 1001 has none. `class_key` is MeowDB `classKey` (null for all). |
| `prerequisites.quests` | `[{quest_id, name}]` that must be completed first (MeowDB `prereqs` / `requiresAll`). |
| `prerequisites.items`, `skills`, `fame_min`, `citizenship`, `acceptance_meso_cost`, `must_not_have_items`, `unresolved` | MeowDB's other prerequisite kinds. All are empty or null for Maple Island and exist so the schema covers later regions. |
| `repeatable`, `repeat_type` | false/null for all. MeowDB has `isRepeatable`/`isDaily`/`isWeekly` flags and none is set. `self_start`: MeowDB `selfStart` (false). |
| `missable`, `tracker_tags` | From the live quest tracker capture (§1): `tracker_tags` are the row's tags in page order (`["COT2", "Missable"]` for all 20) and `missable` is true when they include "Missable" (all 20). Null, with a gap, for a quest the capture has no row for. MeowDB does not explain either tag on the page; "Missable" is recorded as shown, not interpreted. `provenance.missable` / `provenance.tracker_tags` cite the capture. |
| `objectives.monster_kills` | `[{mob_id, name, count}]` from MeowDB `need` entries with `mobId` ("Defeat X"). Each name was verified on `/monsters/<id>`. |
| `objectives.item_collection` | `[{item_id, item_icon_key, name, count, hand_in: true}]` from `need` entries with `itemId`. MeowDB's quest database filter labels item-only requirements "Item hand-in only" (see `items_removed_on_completion`). |
| `objectives.item_usage` | `[{item_id, item_icon_key, name, count}]`. Only 1002 has one: Roger's Apple, count 1. The quest page gives no count; the 1 comes from `safe-to-sell.json` (`field_sources["objectives.item_usage[0].count"]`, recorded as a discrepancy, see §6). |
| `objectives.npc_talk` | `[{npc_id, name, purpose: "turn_in"}]`. Every quest is completed by talking to its end NPC. |
| `objectives.map_visit` | Always empty. MeowDB has no map-visit objectives. |
| `objectives.other` | `[{type: "quiz", ...}]` for 1013–1019. The question is in `dialogue.on_completion.quiz`. |
| `completion_action`, `completion_action_text` | MeowDB `completionAction` (only `"use-rogers-apple"` on 1002) and its UI text from the page JS. |
| `rewards.exp`, `rewards.mesos`, `rewards.fame` | Raw MeowDB numbers given on completion. EXP is character EXP, mesos is the meso amount, fame is fame points. Fame is 0 when MeowDB lists none (no Maple Island quest gives fame). |
| `rewards.items` | `[{item_id, item_icon_key, name, count, given: "on_completion"}]` (MeowDB `get`). |
| `rewards.random` | `[{job_name, total_weight, items:[{item_id, item_icon_key, name, count, chance_pct}]}]` (MeowDB `rewardRandom`, "Random reward - one of"). The player gets **one** item. `chance_pct` is MeowDB's rounded percent (7 × 14.3 = 100.1). `total_weight` equals the item count, so the weights look equal, but MeowDB does not list per-item weights. |
| `rewards.selection` | MeowDB `rewardChoices` ("Pick one (class-specific)"). Empty for Maple Island. |
| `items_given_on_accept` | `[{..., given: "on_accept"}]` (MeowDB `acceptItems`, shown as "On Acceptance"). |
| `items_removed_on_completion` | `{explicit_in_meowdb: false, basis, items}`. MeowDB has **no** explicit "taken on completion" field. The list repeats the item requirements, because MeowDB's quest database "Requirement type" filter treats item requirements as hand-ins: quests whose `need` is all items are listed as "Item hand-in only", items plus kills as "Items + monster kills". The labels are read from the quest page JS (`field_sources["items_removed_on_completion.basis"]`). |
| `followup_quests` | MeowDB `nextQuests` (quests unlocked by this one). |
| `next_quest_grants` | MeowDB `nextQuestGrants` ("{quest} starts with:"): items the follow-up quest hands over when it starts. Example: 1000 → "1001 starts with Sera's Mirror". These are the same items as the follow-up's `items_given_on_accept`. |
| `quest_line` | `{steps:[{quest_id, name, npc, min_level}], position (1-based), total, end_fork, split}` from MeowDB `questLine`. |
| `journal` | `raw` = MeowDB `description`. `lines` = raw split on newlines (the same split MeowDB's page uses). `summary` = line 1 (shown as "Description 01"). `entries` = the rest (shown under "Quest journal" 02, 03…). See §5. |
| `dialogue` | See §4. |
| `provenance` | Per-property sources (contract C7) for the fields that do not come from the record's own `source` page: `missable` and `tracker_tags`. |
| `source`, `field_sources`, `cross_checks`, `notes`, `gaps`, `discrepancies` | Provenance and honesty fields. |

### Item ids: `item_id` vs `item_icon_key`

MeowDB's quest payload lists items as `{"name","count","itemId"}`, and that `itemId` (e.g. Egg = 2010002) is **not** the MeowDB item-db id. It equals the item's icon/asset key (`/msclassic/api/assets/icons/2010002`, and `itemRefs[...].iconKey`). The page's `itemRefs` map gives the MeowDB item-db id (Egg = 237, `/item-db/237`). The records store:

- `item_id`: the MeowDB item-db id. **Use this to join with `game/data/canonical/items/`.**
- `item_icon_key`: the payload's `itemId`, kept for traceability.

Every pair was checked against the item's own page (name and icon key).

## 4. Dialogue (`dialogue`)

MeowDB shows NPC dialogue in two sections. Each one maps to an object or null:

- `dialogue.on_accept`: MeowDB "On accept", the start conversation.
- `dialogue.on_completion`: MeowDB "On completion", the turn-in conversation.

Each section is `{heading, chips, lines, branches, quiz}`:

- `lines`: what the NPC says first, before any branch.
- `branches`: `[{key, state, heading, lines}]`. `key` is MeowDB's own key. `state` is the extractor's name for it:

| MeowDB key | state | MeowDB heading | Meaning for the game |
|---|---|---|---|
| `yes` (in on_accept) | `accepted` | If you accept | NPC lines after the player accepts |
| `no` | `declined` | If you decline | NPC line when the player declines |
| `yes` (in on_completion) | `ready` | When you have everything ready | Turn-in success lines |
| `stopItem` | `missing_items` | If you don't have the items yet | Talking to the turn-in NPC with items missing (in-progress text) |
| `stopMob` | `missing_kills` | If you haven't defeated enough monsters | Talking to the turn-in NPC with kills missing (in-progress text) |
| `stopNpc` | `wrong_npc` | If you haven't met the right NPC yet | In-progress line when the turn-in NPC has not been reached. MeowDB files it under On completion. The wording reads as the start NPC speaking (1006: "Have you not gone to Mai yet? She is the pretty gal at A Split Road."), but MeowDB does not name the speaker |
| `lost` | `lost_items` | If you lost the items | Line when the player lost a quest item (1001: Sera re-issues the mirror) |

MeowDB's branch headings contain a doubled apostrophe ("don''t"). The extractor normalizes it to "don't" in `heading` only. Dialogue text is not modified.

- `quiz` (1013–1019, chip "Quiz"):
  - `question`: a line.
  - `choices`: `[{text, segments, correct, raw_markup}]` in MeowDB document order, which is the in-game selection order (`#L0`, `#L1`, …).
    - `correct` is MeowDB's own marker: `true` = marked "Correct answer", `false` = shown as an option and not marked, `null` = option reconstructed from unparsed game markup (MeowDB shows no marker for it).
    - `raw_markup` is null unless the choice was reconstructed. In that case it holds MeowDB's raw text.
  - `correct_choice_index` (0-based index into `choices`) and `correct_choice_basis`:
    - `"meowdb_marker"`: MeowDB marks exactly one choice as correct (1013–1017, 1019).
    - `"inferred_from_meowdb_responses"`: MeowDB marks none, and the index is inferred from MeowDB's own dialogue (1018 only, see below).

    **Use `correct_choice_index` to grade answers**, not `choices[].correct`.
  - `wrong_answer_heading` and `wrong_answer_responses` (lines in MeowDB order). MeowDB does not tie each one to a particular wrong choice. The text makes the pairing obvious, but it is not encoded.
  - `correct_answer_heading` and `correct_answer_response`.

  MeowDB renders the choice rows nested inside each other (a markup artifact). The extractor flattens them in document order and drops their bold styling.

  **1018 (Rain's Maple Quiz 6).** MeowDB renders only two options, "1 point" and "2 points". The third appears as raw game text `#L2 # 5 points` inside the "2 points" row: the tag is malformed, with a space before the closing `#`, so MeowDB did not parse it. MeowDB also marks no choice as correct.
  - The extractor splits the raw tag into its own choice: "5 points", `correct: null`, `raw_markup: "#L2 # 5 points"`. The tag index 2 equals its position, which confirms that document order is the selection order.
  - `correct_choice_index` 2 is inferred only from MeowDB's own lines. "When you answer correctly" says "You get 5 AP with each level". The two wrong-answer lines answer "1 point" ("Come on, you get more than 1 measly point!") and "2 points" ("Nope, not 2 points. Think again.").
  - The inference is guarded in the extractor (`QUIZ_INFERENCES`): if any quoted line changes on a `--refresh`, the run fails instead of guessing. It is recorded in the 1018 `gaps` and `notes`.

A **line** is `{text, segments}`:

- `text` is plain text. A `\n` is a line break (MeowDB `<br>`).
- `segments` is `[{text, bold?, red?, ref?, icon_key?}]`:
  - `bold`: MeowDB renders the run bold.
  - `red`: MeowDB renders it in red (rose).
  - `ref`: `{type: npc|monster|item|map, id}` is the entity MeowDB links that run to.
  - `icon_key`: an inline item icon (text is ""). The icon itself is not stored, and no art was downloaded.

  The styles describe MeowDB's rendering of the in-game text markup. They are not the game's color codes.

A check confirmed that every text string in MeowDB's dialogue tree appears in the records, except the UI labels "NPC Dialogue", "On accept", "On completion", "Quiz" and "Correct answer", plus the choice-number markers ("1.", "2.", …) and the "✓" glyph. Every extracted line was also found in the page's visible text. No dialogue text contains game markup (`#` followed by a letter); the run fails if one does. The only leaked tag, 1018's `#L2 #`, is split out as described above.

## 5. Quest journal text

`journal.lines` is MeowDB's `description` split by line. MeowDB presents line 1 as the description ("Talk to Roger.") and the remaining lines as the "Quest journal" entries. The numbered entries on every page (01, 02, …) were checked against `journal.lines`. Most Maple Island quests have 3 lines, which read as:

- line 1: available or start text
- middle line(s): in-progress text
- last line: completed text

There are two exceptions. 1001, 1004 and 1008 have only 2 lines: line 1 is a start/in-progress line ("…I have to take it to Heena now."), and line 2 is the completed text. 1010 has 4 lines (two middle lines). MeowDB does **not** label the lines by state, so the records do not either.

## 6. Roger's Apple (1002): implementation notes

MeowDB data:

- Start and turn-in: Roger (npc 3), Mushroom Town (map 000000010, Maple Road).
- Requirements: Lv 1+, Beginner only. No prerequisite quest.
- Completion rule: `completionAction: "use-rogers-apple"`, shown as "To complete: use Roger's Apple, then talk to Roger."
- Usage count: `objectives.item_usage[0].count` = **1**, from MeowDB's `safe-to-sell.json`, where row "Roger's Apple" (itemId 235) has `quests: [{id: "1002", qty: 1}]`. This is recorded as a discrepancy because the sources do not line up:
  - The quest page lists no item requirement (`need: []`, "Talk quest, no items required or rewarded.") and gives no count.
  - `/item-db/235` has no "Needed By" entry for 1002.
  - `safe-to-sell.json` is a derived dataset (generated 2026-08-11), and its `qty` means "the quest asks for N", not explicitly "use N".
  - It is still the only MeowDB number. Its `ambiguous` list does not include "Roger's Apple", so the name maps only to item-db 235.
- Rewards: EXP 0, mesos 0, no items. MeowDB says "Talk quest, no items required or rewarded."
- Roger's Apple is item-db **235** (icon key 2010000), a Use/Food item. Its page says "HP Recovery +30" and "Restores 30 HP."; restore values belong to the items domain.
- Journal:
  1. "Talk to Roger."
  2. "Press the hotkey I to open your inventory, navigate to the Use tab, and double-click Roger's Apple to consume it. Then, talk to Roger."
  3. "You learned how to use items! This will make life much easier!"
- Dialogue: only one MeowDB line, On completion → If you don't have the items yet: "Eat the Roger's Apple I gave you by opening your inventory and clicking the Use tab. Double-click the Roger's Apple to recover some HP."

**What MeowDB does not have (gaps):**

- **No "On accept" dialogue.** MeowDB has no start text or accept/decline lines for 1002.
- **No item given on acceptance** (`acceptItems` is empty). The dialogue nevertheless says "the Roger's Apple I gave you". MeowDB records neither how many apples Roger gives nor exactly when. This is recorded as a discrepancy in 1002.json. `items_given_on_accept` stays `[]`, and nothing was filled in from memory.
- The quest page has no item-usage count. The rule only says "use Roger's Apple". The count of 1 comes from `safe-to-sell.json` (see above). That file says nothing about how many apples Roger hands out.
- Nothing about HP being reduced or any other start-of-quest effect.

To implement 1002 end-to-end, the game needs a MisoStory adaptation decision for the apple hand-out: quantity and timing. That decision must be recorded as an adaptation (or as an `external` value with `verified: false`), not as canonical data. None of these MeowDB pages say anything about the hand-out: Roger's NPC page (`/npcs/3`, only idle chatter about the inventory), the item page (`/item-db/235`), `safe-to-sell.json`, or the beginner's guide (its quest table lists Roger's Apple with no EXP and no reward).

## 7. Sam's Suggestion (1006): implementation notes

- Start: Sam (npc 9) at Snail Hunting Ground I (000000040). Turn in: Mai (npc 11) at A Split Road (000000050). Lv 1+, Beginner only, no prerequisite.
- Objective: defeat 10 Snails (mob "2"). No items required.
- Rewards on completion: 30 EXP and Egg ×3 (item-db 237, icon key 2010002). No mesos and no fame.
- Follow-up: unlocks 1009 Mai's Training (chain 1006 → 1009 → 1010).
- Journal:
  1. "Sam has some advice for beginner adventurers..."
  2. "Sam told me to head east and hunt 10 Snails before meeting up with Mai."
  3. "As Sam suggested, you hunted 10 Snails, then met Mai. Is this person a master? …"
- Dialogue has full on_accept text (with accept and decline) and full on_completion text, with branches:
  - `ready`: "Well, defeating 10 Snails is a piece of cake! Haha!" …
  - `missing_kills`: "I'm sure I told you to defeat 10 Snails. Check your quest progress in the Quest Log."
  - `wrong_npc`: "Have you not gone to Mai yet? She is the pretty gal at A Split Road. …"

## 8. Gaps (what MeowDB lacks)

- **All quests:**
  - No max level.
  - No map-visit objectives or per-objective map restrictions.
  - No explicit "items removed on completion" field (derived from the "Item hand-in only" / "Items + monster kills" filter labels, see §3).
  - No marker for which completion lines come before or after the reward.
  - No split into in-game chat pages (Next/OK windows).
  - No per-state labels on journal lines.
  - No quest-start effects (e.g. HP changes) and no accept-time EXP.
- **1002:** no On accept dialogue and no acceptance item (quantity and timing of the apple hand-out are unknown). The quest page also has no usage count; count 1 comes only from `safe-to-sell.json` (see §6).
- **1001:** MeowDB lists no job requirement, so `job_restriction` is null. MeowDB does not say whether that means "any job" or "not recorded"; 1000, its chain partner, is Beginner only.
- **Random rewards (1008, 1011):** only rounded `chance_pct` and `total_weight`, no per-item weights.
- **Quizzes:** wrong-answer responses are not linked to specific choices, and MeowDB does not say whether the player can retry. The 1015 on-accept line ("I let you keep trying until you get them right") suggests retries, but that is dialogue, not a rule.
- **1018:** MeowDB marks no correct answer and does not render the third option (raw `#L2 # 5 points`); see §4.
- **Not quest data:** NPC coordinates exist in `/npcs` (`x`, `y`) but belong to the NPC domain. They are not copied into the quest records.

## 9. Discrepancies

1. **1005, item id of "Jr. Sentinel Shellpiece".** The quest data (`itemRefs`) says item-db **347**. The NPC dialogue links "Jr. Sentinel Shellpiece(s)" to item-db **2584**.
   - **Chosen: 347.** Its icon key (4000000) equals the quest payload's `itemId`, and its page lists "Needed By: Todd's How-to-Hunt, qty 3".
   - 2584 is a different item with the same name. Its icon key is 4000067, it is needed by "Collecting Huckle's Magic Ingredients" (qty 30), and its page does not link quest 1005.
   - MeowDB's `safe-to-sell.json` lists "Jr. Sentinel Shellpiece" in its `ambiguous` item-name list (ids 347, 2584) and resolves it by name to 2584. MeowDB's own name-based resolution therefore produces 2584 for this name, independent of the quest. This is recorded as a third value in the 1005 discrepancy.
   - The dialogue link appears to be resolved by name. The dialogue segment keeps MeowDB's raw link (2584), so do not use dialogue refs as item ids.
2. **1002, items given on accept.** The structured data (`acceptItems: []`) disagrees with the dialogue ("the Roger's Apple I gave you").
   - **Chosen:** keep the structured value (empty) and record the gap. No MeowDB page resolves it.
3. **1002, Roger's Apple usage count.** The quest page (`need: []`, no count) and `/item-db/235` (no "Needed By") say nothing; `safe-to-sell.json` gives qty 1 for quest 1002.
   - **Chosen: 1**, the only MeowDB number, recorded with `field_sources` and the caveats in §6.
4. **Index vs detail.** No differences. All 20 quest objects in `/quest-tracker/all` are identical to their detail pages. The extractor records any future difference automatically, preferring the detail page.

## 10. Things a game programmer must know

- **Join items by `item_id`** (MeowDB item-db id), never by `item_icon_key` or by dialogue `ref` ids (see discrepancy 1).
- **`min_level` 0 means no level requirement.** In practice the prerequisite quest gates these follow-ups.
- **The end NPC is the start NPC unless `end_npc_listed_separately` is true.** For 1000/1001, 1003/1004, 1005, 1006, 1007/1008 the quest is accepted from one NPC and turned in to another, sometimes on another map (1007: Maria at A Split Road → Lucas in Amherst).
- **Items given on accept:**
  - 1001 gives Sera's Mirror ×1.
  - 1007 gives Maria's Letter ×1.
  - 1008 gives Lucas's Letter ×1.
  - The previous quest's `next_quest_grants` mentions the same items, so do not grant them twice.
  - The `lost` branch of 1001 suggests Sera re-issues the mirror if it is lost; MeowDB gives no other rule for that.
- **Random rewards** (1008 hats, 1011 Fruit Knife/Razor) give exactly one item from the list.
- **Quizzes** (1013–1019): the player must pick `quiz.choices[quiz.correct_choice_index]`. Grade by `correct_choice_index`, not by `choices[].correct`: in 1018 no choice has `correct: true`, and the right answer ("5 points") is an option MeowDB did not render, with `correct: null`. Its index is inferred from MeowDB's own dialogue (`correct_choice_basis: "inferred_from_meowdb_responses"`). Show the wrong-answer response on a miss; MeowDB does not say whether the player can retry. Rain's chain runs in order and each part needs the previous one.
- **Dialogue styling:** `bold`/`red` and inline `icon_key` describe how MeowDB rendered the text. Item icons are referenced by key only; MisoStory must supply its own art.
- **1012** "If you accept" text contains "Rusty Screw 0/3 / Old Wooden Board 0/3". The "0" is MeowDB rendering an in-game counter placeholder, so substitute the live count.
- **Dialogue references to non-quest entities:** 1005 → NPC 313 "Grendel the Really Old", 1016 → item 270 "Red Potion", 1019 → NPC 15 "Shanks", and maps 000000060 (Southperry) / 000001010 (Amherst). In 1011 the monsters Blue Snail (3) and Orange Mushroom (9) are mentioned as drop sources.

## 11. Referenced ids

- **Items (item-db):**
  - In quest data: 235, 237, 239, 347, 349, 356, 438, 439, 440, 441, 442, 522, 558, 559, 708, 709, 711, 712, 713, 714, 715.
  - Dialogue links only: 270 (Red Potion), 2584 (the wrong Shellpiece link).
- **NPCs:**
  - Start/turn-in: 1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 12, 17, 18, 19.
  - Dialogue only: 15 (Shanks), 313 (Grendel the Really Old).
- **Monsters:** 1 (Tutorial Jr. Sentinel), 2 (Snail), 3 (Blue Snail), 4 (Shroom), 5 (Red Snail), 9 (Orange Mushroom).
- **Maps:** 000000001, 000000010, 000000020, 000000021, 000000030, 000000040, 000000050, 000000060, 000001010.

## 12. Extractor validation (fails with a non-zero exit if any check breaks)

- The region table comes from the quest page JS. The NPC-index check must give the same quest set as the area filter.
- Every quest object field is known to the extractor; a new MeowDB field makes the run fail.
- Index and detail objects are compared, and any difference becomes a discrepancy.
- Start and end NPC id, name and maps agree with `/npcs`, and the quest appears in that NPC's quest or turn-in list.
- Every item: its `itemRefs` icon key equals the payload's `itemId`, and its item page has the same name and icon key.
- Every kill objective: the monster page name matches.
- Prerequisite list equals `requiresAll`.
- Every dialogue line and journal line is found in the page's visible text.
- An unknown dialogue block, branch key or inline element makes the parser fail rather than silently drop text.
- No dialogue text may contain game markup (`#` + letter). Raw `#L<n>#` quiz tags are split into their own choice, and the tag index must equal the choice position.
- Every quiz must have exactly one MeowDB-marked correct choice, or a guarded `QUIZ_INFERENCES` rule whose quoted lines are all present. Otherwise the run fails.
- Every hand-in item and its count must match `safe-to-sell.json` (`quests[].qty`). A differing item id is allowed only if that file lists the name as ambiguous. Every item that file lists for a quest must be in the record.
- The quest tracker capture: every Maple Island row parses, names exactly one selected quest (and every selected quest has a row), and its start NPC, level and chain step agree with the cached quest object.

Notes for maintainers:

- `lib.mjs` was used unmodified and no bug was found in it.
- When calling helper scripts from Git Bash with arguments like `/npcs/3`, set `MSYS_NO_PATHCONV=1`. Otherwise MSYS rewrites the argument into a Windows path. The extractor itself takes no path arguments.
