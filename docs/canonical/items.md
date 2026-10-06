# Canonical data: items (Maple Island set)

Authority: **MeowDB MS Classic** (`https://meowdb.com/msclassic`). It documents MapleStory Classic World (Nexon, 2026).
Every id is a MeowDB item id (for example `270` = Red Potion), not a GMS id.

- Data: `game/data/canonical/items/<item id>.json`, one item per file. There is no index file, so every file in the folder is an item.
- Extractor: `node tools/meowdb/extract_items.mjs`. It runs offline: the cache (`tools/meowdb/.cache`) first, then the hand-read captures (`tools/meowdb/lib.mjs`); network access is off unless `MEOWDB_ALLOW_NETWORK=1` (see [README.md](README.md)). Two runs on the same cache give byte-identical output (checked with `diff -r` and `git status`).
- **API-only items.** An item with no cached `/item-db/<id>` page but a captured item API body (`tools/meowdb/captures/items_api.json`) is built from that body alone (`buildItemFromApiOnly`). No item of this set is built that way today. Green Apple (`242`) was, from Iteration Three until the owner removed it from the subset on 2026-10-06 (#32): since the drop sources changed it is not a drop member, a quest item or a shop item, so the game cannot give it. Its captures (`items_api.json`, `item_242.txt`) stay as dated records that nothing reads, and the extractor notes that when it runs. On that path every value cites the capture in `field_sources` (`capture`, `capture_pointer`, `from`), `source.capture` names the file, and every field only the item page shows is `null` and listed in `gaps` (Tradeable tag, MSEA drops, quest rewards, breakables, recipes, "Needed By", change history); `retrieved_at` is the capture's session time, approximate to the minute (`notes`). **Item page text captures.** When the item page itself was later read by hand and its rendered text saved as `tools/meowdb/captures/item_<id>.txt` (parsed by `tools/sources/captures.mjs`), the rows that text shows are read from it instead: "Max per Stack" (`max_stack`), the Tradeable/Untradeable tag (`tradeable`), the "NPC Sell-back" row (`sell_price_mesos`, and `sell_price_basis` from its label; `sell_price_source: item_page`) and the "MSEA Reference Drops" (`sources.msea_reference_drops`; the text has no monster link, so each `monster_id` is the one monster with that name and level in the monster list bundled with the item pages, a derived field). Each cites the capture in `field_sources` (`url` of the item page, `read_at`, `capture`). The rest of what the text shows (name, type, subtype, number, recovery rows, the sell-back value, the description, an empty "Dropped By") is cross-checked with the API body; a section the trimmed capture leaves out stays a gap. The extractor stops when an item page capture belongs to an item of the subset that has a cached page (nothing would read it).
- The extractor is strict. It stops with an error on any stat row, tag, section heading, weapon row, attack-cycle row, reach row or breakable row it does not recognise, so it cannot silently drop a value.

## TL;DR for the game programmer

- **Inventory tab** is `inventory_tab` (`equip` / `use` / `setup` / `etc`; no Cash items are in this set). **Equip slot** is `equip_slot` (`weapon`, `hat`, `top`, `bottom`, `shoes`, `gloves`, `earrings`; `null` when not equipment). Both are *derived* from MeowDB's `type` / `subtype` (see "Derived fields").
- **Equipment bonuses** are in `stats`. It lists only the stats MeowDB shows. A missing key means the item gives no bonus for that stat. `upgrade_slots` is the scroll slot count.
- **Requirements** are in `requirements`: `level`, `job` (`null` = any job, Beginner included), `str` / `dex` / `int` / `luk` / `fame` (`0` = none).
- **Weapons**: `weapon.attack_speed` is the tier (2 = faster … 9 = slower; lower is faster), and `weapon.attack_speed_name` is MeowDB's label. Use `weapon.multipliers` for the damage formula, `weapon.attack_cycle_ms` for timing, and `weapon.basic_attacks[].box_px` for hit boxes.
- **Potions and food**: `consumable.hp_restore` / `consumable.mp_restore` are flat HP/MP amounts. No item in this set restores a percentage or gives a timed buff.
- **Scrolls**: `scroll.stat_bonus_on_success` is added to the target equipment when the scroll succeeds. Scrolls have **no** entries in `stats`.
- **Chairs (Setup)**: `setup.hp_recovery_bonus` HP every `setup.interval_s` seconds while sitting.
- **Selling**: `sell_price_mesos`, with `sell_price_basis` `per_unit` (stackables) or `per_item`. **Buying**: the price at each shop is in `sources.shops[]`. Use the shops domain (`game/data/canonical/shops/`) for Maple Island shop prices. `npc_buy_price_mesos` is the cheapest price at any NPC shop in the world.
- **Stack size**: `max_stack`. It is `null` for all equipment because MeowDB gives no value (see Gaps).
- **Starting equipment**: the Beginner picks one of `541` Sword, `576` Hand Axe or `585` Wooden Club at character creation (`beginner_creation_weapon: true`). MeowDB does not document starting clothes.
- **Drop sources**: `sources.monster_drops` holds community-confirmed Classic drops (votes only, **no rates**). `sources.msea_reference_drops` holds historical pre-Big-Bang MapleSEA sources. Drop chances are not published anywhere on MeowDB (same conclusion as `docs/canonical/monsters.md`).

## What is included and why

**94 items, all from item pages.** The owner removed two on 2026-10-06 (#32): Shoes Jump Scroll: Greater (`177`) and Green Apple (`242`, added in Iteration Three), drop members only under the earlier drop sources, which the game can no longer give. `177` stays on the Orange Mushroom's MSEA reference list (`drops/9.json` `msea_reference`, `item_id` `null`: reference data only, no local record). These are the ids the Iteration Two orchestrator collected from the other Maple Island domains (monster drop tables, quest rewards and requirements, NPC shops, the Beginner formulas). The extractor also adds every `item_id` in `game/data/canonical/shops/*.json` and every `starter_weapons.items[].item_id` in `game/data/canonical/formulas/beginner.json`. All of these were already in the list, so nothing was added. A scan of every other domain's JSON for `item_id` / `item_cost_id` finds only 4 ids not in this set (`519`, `2692`, `2697`, `294`). The shops files mention them in their sell-back cross-check metadata. They are not shop stock, so they are out of scope.

No item names had to be resolved to ids. The "names without ids" list was empty.

| Group | Count | Ids |
|---|---|---|
| Use | 16 | 59, 61, 139, 143 (scrolls); 209, 213 (arrows); 235-240 (food); 269 (pet food); 270, 271, 273 (potions) |
| Etc | 21 | 320-327 (gems); 347-356 (monster drops); 413-417 (ores); 438-442, 483 (quest items) |
| Setup | 2 | 522 The Green Relaxer, 525 Sky-blue Wooden Chair |
| Equip: weapons | 15 | 541, 543, 551, 558, 559, 562, 576, 577, 585, 589, 595, 608, 633, 651, 666 |
| Equip: armor and accessories | 40 | hats 708-715, 724, 731; earrings 900; tops 933-963; bottoms 1157-1195; shoes 1305-1327; gloves 1439, 1440 |

### Beginner starting equipment

The only MeowDB statement about starting gear is the Beginner's guide (`/guides/beginners-guide-first-steps-in-maple-world`): *"Choose the Wooden Club at character creation. It has 19 W.ATK; the Sword and Hand Axe have 17."* The guide links the three names to `/item-db/541`, `/item-db/576` and `/item-db/585`, and the extractor checks those links. Those three files carry `beginner_creation_weapon: true` and a `notes` entry quoting the sentence (`field_sources.notes` = the guide).

**Starting clothes / starting inventory: not documented.** Searched: the Beginner's guide, `formulas/beginner.json` (`starter_clothes: null`), and `/beauty` (Hair & Face). `/beauty` lists the *Character creation* hair, face, hair-colour and skin options, but no clothes. Pan's 50-meso tops/bottoms/shoes (933-940, 1157-1161, 1305, 1306) are shop stock. Nothing says they are creation outfits, so do not treat them as starting gear.

### Item summary (copied from the files)

**Use**

| id | Name | Subtype | Effect | Stack | Buy / sell (mesos) | Tradeable |
|---|---|---|---|---|---|---|
| 59 | Cape Magic Def. Scroll: Intermediate | Scroll | Cape, 60%: W.DEF +2, M.DEF +4 | 100 | - / 1 | yes |
| 61 | Cape Weapon Def. Scroll: Intermediate | Scroll | Cape, 60%: W.DEF +4, M.DEF +2 | 100 | - / 1 | yes |
| 139 | Overall Armor DEX Scroll: Greater | Scroll | Overall, 10%: DEX +3 | 100 | - / 1 | yes |
| 143 | Overall Armor DEF Scroll: Intermediate | Scroll | Overall, 60%: W.DEF +4, M.DEF +2 | 100 | - / 1 | yes |
| 209 | Arrows for Bows | Arrow | - | 1000 | 1 / 0 | yes |
| 213 | Arrows for Crossbows | Arrow | - | 1000 | 1 / 0 | yes |
| 235 | Roger's Apple | Food | HP +30 | 100 | - / 0 | no |
| 236 | Apple | Food | HP +40 | 100 | 20 / 2 | yes |
| 237 | Egg | Food | HP +60 | 100 | 30 / 3 | yes |
| 238 | Meat | Food | HP +160 | 100 | 80 / 8 | yes |
| 239 | Orange | Food | MP +50 | 100 | 50 / 5 | yes |
| 240 | Lemon | Food | MP +150 | 100 | 150 / 15 | yes |
| 269 | Pet Food | Pet Food | pet fullness +30 | 200 | 30 (Lucy: 35) / 15 | yes |
| 270 | Red Potion | Potion | HP +100 | 100 | 50 / 5 | yes |
| 271 | Orange Potion | Potion | HP +250 | 100 | 150 / 15 | yes |
| 273 | Blue Potion | Potion | MP +200 | 100 | 220 / 22 | yes |

**Etc**

| id | Name | Subtype | Stack | Sell | Tradeable |
|---|---|---|---|---|---|
| 320 / 321 / 322 / 324 / 327 | Garnet / Amethyst / Aquamarine / Opal / Diamond Ore | Gem | 100 | 40 / 200 / 40 / 160 / 240 | yes |
| 347 | Jr. Sentinel Shellpiece | Monster Drop | 200 | 0 | no |
| 348 / 349 / 350 / 351 / 356 | Snail Shell / Blue Snail Shell / Mushroom Spore / Red Snail Shell / Orange Mushroom Cap | Monster Drop | 200 | 1 / 2 / 3 / 4 / 8 | yes |
| 413 / 414 / 415 / 417 | Bronze / Iron / Mithril / Silver Ore | Ore & Mineral | 100 | 20 / 20 / 40 / 80 | yes |
| 438 / 439 / 440 | Sera's Mirror / Maria's Letter / Lucas's Letter | Quest Item | 100 | 0 / 1 / 0 | no |
| 441 / 442 | Rusty Screw / Old Wooden Board | Quest Item | 100 | 0 / 0 | no |
| 483 | Monster Card | Quest Item | 100 | 1 | no |

**Setup**: 522 The Green Relaxer (HP +30 every 10 s while sitting, untradeable, stack 1, sell 1, Pio's quest 1012 reward). 525 Sky-blue Wooden Chair (same effect, requires Lv 5, tradeable, buy 1000 from Mina in Lith Harbor, sell 500).

**Weapons**

| id | Name | Subtype | Req (Lv / job / stats) | W.ATK / M.ATK | Speed | Slots | Buy / sell |
|---|---|---|---|---|---|---|---|
| 541 | Sword | One-Handed Sword | 0 | 17 | Fast (4) | 7 | 50 / 0 |
| 543 | Long Sword | One-Handed Sword | 10 / STR 20 | 27 | Fast (4) | 7 | 3000 / 1500 |
| 551 | Gladius | One-Handed Sword | 30 / Warrior / STR 65 DEX 30 | 47 | Fast (4) | 7 | 22000 / 5500 |
| 558 | Razor | Dagger | 5 | 23 | Fast (4) | 7 | 500 / 250 |
| 559 | Fruit Knife | Dagger | 8 | 23 | Faster (3) | 7 | 1500 / 750 |
| 562 | Field Dagger | Dagger | 15 / Warrior/Thief / DEX 10 LUK 20 | 30 | Faster (3) | 7 | 5000 / 2500 |
| 576 | Hand Axe | One-Handed Axe | 0 | 17 | Fast (4) | 7 | 50 / 0 |
| 577 | Double Axe | One-Handed Axe | 10 / STR 20 | 27 | Fast (4) | 7 | 3000 / 1500 |
| 585 | Wooden Club | One-Handed Blunt Weapon | 0 | 19 | Fast (5) | 7 | 50 / 0 |
| 589 | Leather Purse | One-Handed Blunt Weapon | 12 / STR 15 | 31 | Fast (5) | 7 | 3800 / 1900 |
| 595 | Iron Mace | One-Handed Blunt Weapon | 20 / Warrior/Mage / STR 30 | 39 | Fast (5) | 7 | 10500 / 3500 |
| 608 | Wooden Sword | Two-Handed Sword | 10 / Warrior/Bowman/Thief / STR 25 | 30 | Fast (5) | 7 | 5000 / 2500 |
| 633 | Spear | Spear | 10 / Warrior/Bowman/Thief / STR 25 | 32 | Slow (7) | 7 | 5000 / 2500 |
| 651 | Metal Wand | Wand | 20 / INT 40 LUK 10 | 21 / 41 | Normal (6) | 7 | 10500 / 3500 |
| 666 | Hunter's Bow | Bow | 20 / Bowman / STR 20 DEX 45 | 42 (KB 20%) | Normal (6) | 7 | 13500 / 4500 |

**Armor and accessories** (all `upgrade_slots` 7, except shoes, gloves and earrings, which have 5)

| id | Name | Slot | Gender | Req (Lv / job / stats) | Bonuses | Buy / sell |
|---|---|---|---|---|---|---|
| 708 / 709 / 710 | Brown / Green / Red Skullcap | hat | any | 5 | W.DEF 6 | 600 (708 only) / 300 |
| 711 | Red Headband | hat | any | 5 | W.DEF 6, HP 5 | 600 / 300 |
| 712 / 713 / 714 | Black / Green / Yellow Headband | hat | any | 5 | W.DEF 6, ACC 1 | 600 / 300 |
| 715 | Blue Headband | hat | any | 5 | W.DEF 6, MP 5 | 600 / 300 |
| 724 | Bronze Koif | hat | any | 10 / Warrior / STR 10 | W.DEF 22, DEX 1, ACC 1 | 1200 / 600 |
| 731 | Green Winter Hat | hat | any | 10 / Bowman / DEX 10 | W.DEF 15, DEX 1 | 1200 / 600 |
| 900 | Amethyst Earrings | earrings | any | 15 | M.DEF 19 | 4500 / 2250 |
| 933 / 934 / 935 | White Undershirt / Grey T-Shirt / Undershirt | top | male | 0 | W.DEF 6 | 50 / 0 |
| 937 / 938 / 939 / 940 | White Tube Top / Yellow T-Shirt / Green T-Shirt / Red Striped Top | top | female | 0 | W.DEF 6 | 50 / 0 |
| 945 | Brown Training Shirt | top | male | 10 / Mage / INT 10 | W.DEF 13, M.DEF 18, LUK 1 | 2000 / 1000 |
| 960 | Blue One-lined T-Shirt | top | male | 12 | W.DEF 26, HP 12 | 2400 / 1200 |
| 963 | Red Striped T-Shirt | top | female | 12 | W.DEF 26, MP 12 | 2400 / 1200 |
| 1157 / 1158 | Blue Jean Shorts / Brown Cotton Shorts | bottom | male | 0 | W.DEF 4 | 50 / 0 |
| 1160 / 1161 | Red Miniskirt / Indigo Miniskirt | bottom | female | 0 | W.DEF 4 | 50 / 0 |
| 1163 | Jean Capris | bottom | male | 5 | W.DEF 7, HP 5 | 800 / 400 |
| 1168 | Red Cloth Pants | bottom | male | 10 / Thief / LUK 10 | W.DEF 17, STR 1 | 1600 / 800 |
| 1175 | Green Avelin Skirt | bottom | female | 10 / Bowman / DEX 10 | W.DEF 17, DEX 1 | 1600 / 800 |
| 1177 | Red Cloth Pants | bottom | female | 10 / Thief / LUK 10 | W.DEF 17, STR 1 | - / 800 |
| 1181 | Grey Thick Sweat Pants | bottom | male | 12 | W.DEF 18, HP 12 | 1920 / 960 |
| 1195 | Ice Jeans | bottom | any | 17 / FAME 20 | W.DEF 21, MP 17 | - / 1360 |
| 1305 / 1306 / 1308 | Leather Sandals / Red Rubber Boots / Blue Rubber Boots | shoes | any | 0 | W.DEF 2 | 50 / 0 |
| 1314 | Brown Hard Leather Boots | shoes | any | 10 / Bowman / DEX 10 | W.DEF 10, AVOID 1, Speed 1 | 1200 / 600 |
| 1317 | White Gomushin | shoes | any | 11 | W.DEF 11, Speed 1 | 1980 / 660 |
| 1325 | Brown Woodsman Boots | shoes | any | 15 / Bowman / DEX 20 | W.DEF 12, STR 1, HP 5, AVOID 1 | 1800 / 900 |
| 1327 | Red Ninja Sandals | shoes | any | 15 / Thief / LUK 20 | W.DEF 12, STR 1, HP 5, AVOID 1 | 1800 / 900 |
| 1439 | Basic Archer Gloves | gloves | any | 15 / Bowman / DEX 20 | W.DEF 8, DEX 1, CRIT% 1 | - / 1800 |
| 1440 | Brown Duo | gloves | any | 15 / Thief / LUK 20 | W.DEF 8, STR 1, CRIT% 1 | - / 1800 |

## Pages read

All pages are cache-first through `tools/meowdb/lib.mjs`. Each file's `source` / `field_sources` give the exact URL and `retrieved_at` from the cache meta.

| Page | Retrieved (UTC, 2026-10-04) | Used for |
|---|---|---|
| `https://meowdb.com/msclassic/item-db/<id>` (94 pages) | 10:05:55 to 10:47:16 | **Primary** (`source`). Server-rendered flight payload: name, type/subtype, "No.", requirement block, stat rows, tags (Tradeable / gender), weapon details (multipliers, attack cycle, reach, hit boxes), "Where to buy", "MSEA Reference Drops", "Quest Reward", "Needed By", "Found in Breakables", "Craftable", "Change history", and the `<!-- item:N gid:G -->` comment (game item id) |
| `https://meowdb.com/msclassic/api/items/<id>?locale=en&preview=1` (94) | 10:22:26 to 10:47:19 | MeowDB's item hover-preview JSON (`fetch` in the msclassic layout chunk). In-game `description`; `levelReq`; structured `stats` (`reqStr`/`reqDex`/`reqInt`/`reqLuk`/`reqFame`/`reqJob`, `slotMax`, `price` = NPC sell-back, scroll `grade`/`target`/`statType`/`successRate`). Fills values the page omits and cross-checks every value both show |
| `https://meowdb.com/msclassic/api/drops?itemId=<id>` (94) | 10:42:57 to 10:47:20 | Community drops. The page's "Dropped By" list says "Loading…" in the HTML and is filled client-side from this endpoint (`fetch(\`/msclassic/api/drops?itemId=${t}\`)` in the `item-db/[id]` page chunk). It returns monster ids and votes only |
| `https://meowdb.com/_next/static/chunks/782-bb5a5ee666dc6188.js` | 10:05:48 | The monster list bundled with the item page (export `IW`, `{id, name, level, …}`). The page uses it to name community drops, and so does the extractor. The extractor finds the chunk by its content, not by its hash |
| `https://meowdb.com/msclassic/monsters/700000` | 10:56:20 | Name/level (JSON-LD) of the one community-drop monster missing from the bundled list (Mushmom, Lv 40) |
| `https://meowdb.com/msclassic/guides/beginners-guide-first-steps-in-maple-world` | 10:06:38 | Character-creation weapon choice |
| `https://meowdb.com/msclassic/quest-tracker/<id>` for the 8 quests with a random-reward share on an item page: 1008, 1011 (cached by the quests domain), 10201, 10202, 10203, 10509, 12119, 12121 | 10:07:25 to 11:19:49 | The quest's structured `rewardRandom` pool (`chance` to one decimal plus `totalWeight`). Used for `sources.quest_rewards[].chance_pct`, because the item page rounds the share to a whole percent (see Discrepancies) |
| `https://meowdb.com/msclassic/beauty` | 10:49:53 | Checked for creation outfits (none; hair/face/skin only). Not used in any file |

Not used: the item page's "Free Market", "Observed Stat Rolls", "Animations" (GIF art), "Similar … items" / "Compare … items" (navigation) and comments widgets. Also not used: "Meow Notes" (`320` only: an admin comment, "The most in-demand ore in COT2!") and "Revision history" (`900` only: one MeowDB edit to `color_tags`, no gameplay field). Also skipped on purpose: the "NiaMeowDB Description" block (MeowDB's own visual description of some equips, e.g. 945 "Tan short-sleeved training shirt…") and the item API's `colorTags` / `flavorText` fields. These are editorial or cosmetic, not gameplay. No images, icons or animations were downloaded.

## File format (every field)

| Field | Meaning / units | Source |
|---|---|---|
| `id` | MeowDB item id (string) | URL |
| `name` | Item name (page heading) | page (cross-checked with API `name`) |
| `game_item_id` | The item's game id as MeowDB exposes it (page comment `gid`, e.g. `1302000`), as a string. Equals API `iconKey` for all 94 | page |
| `type` | MeowDB type: `Equip`, `Use`, `Setup`, `Etc` (raw) | page (= API) |
| `subtype` | MeowDB subtype, raw (`One-Handed Sword`, `Top`, `Potion`, `Quest Item`, …; `null` for Setup) | page (= API) |
| `inventory_tab` | **Derived**: `equip` / `use` / `setup` / `etc` / `cash` from `type` | extractor |
| `equip_slot` | **Derived** from `subtype` (table below); `null` for non-equipment | extractor |
| `quest_item` | **Derived**: `subtype == "Quest Item"` | extractor |
| `description` | In-game description text (`\n` = line break). `""` for every equipment item: MeowDB has no in-game text for these equips | API (= page text box for non-equipment, = "In-game text COT2") |
| `requirements.level` | Required character level (0 = none) | API `levelReq` (= page "REQ LEV" / "Required Level") |
| `requirements.job` | Allowed jobs as an array (`["Warrior","Thief"]`), or `null` = no job requirement (Beginner can equip) | page "JOB" (= API `reqJob`), split on `/` |
| `requirements.job_raw` | Raw string as shown (`Warrior/Bowman/Thief`, `Mage`) | page |
| `requirements.str/dex/int/luk/fame` | Minimum base stat / fame. `0` = MeowDB shows no such requirement | page `reqStr`… (= API) |
| `stats` | Equipment bonuses. Only the keys MeowDB shows: `watk`, `matk`, `wdef`, `mdef`, `str`, `dex`, `int`, `luk`, `hp` (Max HP +), `mp` (Max MP +), `acc`, `avoid`, `speed`, `jump`, `knockback_pct` (page "KB 20%"), `crit_rate_pct` (page "CRIT% +1"), `upgrade_slots` | page rows (= API `stats`, = page `baseStats`) |
| `weapon` | `null` unless a weapon | page "Weapon Details" |
| `weapon.weapon_type` | = subtype | |
| `weapon.attack_speed` / `attack_speed_name` | Speed tier (lower is faster) and MeowDB's label, exactly as shown ("Fast (5)") | page (= API `attackSpeed`/`attackSpeedName`) |
| `weapon.multipliers` | Weapon multiplier per basic-attack kind: `swing` / `stab`, or for bows `firing` / `close_range` | page "Weapon Multipliers" |
| `weapon.multipliers_note` | "Basic attacks. Skills may use a specific action." | page |
| `weapon.attack_cycle_ms` / `attack_cycle_with_booster_ms` | One basic-attack cycle in ms, plain and with a Booster skill; `null` when the page splits it by kind | page |
| `weapon.attack_cycle_by_kind_ms` | Spear only: `{swing: {ms: 870, with_booster_ms: 750}, stab: {ms: 810, with_booster_ms: 720}}` | page |
| `weapon.attack_cycle_note` | Wand: "magicians have no Attack Speed Booster in 1st or 2nd job" | page |
| `weapon.basic_attack_mix_pct` | Chance a normal attack is a swing vs a stab (`{swing: 60, stab: 40}`; wand 100/0; `null` for bow) | page component props |
| `weapon.reach` | `avg_horizontal_px`, `horizontal_range_px` [min, max] across basic attacks, `avg_vertical_px`, `vertical_range_px`. Wand: "Same for every normal attack" becomes [v, v] | page |
| `weapon.arrow_range_px` / `arrow_range_note` | Bow: `[300, 420]`, "420 px with The Eye of Amazon maxed" | page |
| `weapon.required_ammunition` / `required_ammunition_item_id` | Bow: "Arrows for Bows" / `"209"`. The id is **derived** by exact name match within this set | page |
| `weapon.basic_attacks[]` | Each basic attack: `action` (`swingO1`, `stabO2`, `proneStab`…), `label`, `kind` (`swing`/`stab`/`crouch`), `near_px`, `far_px`, `top_px`, `box_px` [left, top, right, bottom], `in_average` (`false` for the crouched attack and the bow's close-range whacks) | page component props |
| `consumable` | `hp_restore` / `mp_restore` (flat points), `pet_fullness_restore`; `null` if none | page rows (= API `hpRecover`/`mpRecover`/`fullness`) |
| `scroll` | `target_equipment`, `stat_type`, `grade`, `success_rate_pct`, `stat_bonus_on_success` ({stat: +n}) | API `stats` (+ page rows for the bonus) |
| `setup` | `hp_recovery_bonus` (HP per tick while sitting), `interval_s` (10, parsed from the description "every 10 seconds") | page row (= API `hpRecoverBonus`); interval: API description |
| `npc_buy_price_mesos` | **Derived**: lowest NPC shop price anywhere (mesos, one unit); `null` = not sold by NPCs | page "Where to buy" |
| `sell_price_mesos` / `sell_price_basis` / `sell_price_source` | NPC sell-back in mesos; `per_unit` (page label "NPC Sell-back (per unit)", stackables) or `per_item`; `item_page` or `item_api` (the page omits the row when the value is 0; the API then records `price: 0`) | page / API |
| `recharge_cost_mesos_per_unit` | Throwing-star recharge cost; `null` for every item here | page / API |
| `max_stack` | Max per stack (slot max); `null` for equipment (not published) | page "Max per Stack", else API `slotMax` (chairs) |
| `tradeable` | `true` / `false` from the page tag "Tradeable" / "Untradeable" | page |
| `gender` | Equipment: `any` ("Male + Female"), `male` ("Male only"), `female` ("Female only"); `null` for non-equipment | page tag |
| `sources.shops[]` | Every NPC that sells it: `npc_id`, `npc_name`, `npc_role`, `map_id` (9-digit), `map_name`, `town`, `price_mesos`, `cheapest` (MeowDB's "cheapest" mark), `price_label` ("COT2 prices") | page "Where to buy" |
| `sources.monster_drops[]` | Community-confirmed Classic drops: `monster_id`, `monster_name`, `monster_level`, `upvotes`, `downvotes`, `score`, `disputed` (**derived**: `score <= 0`; MeowDB dims these rows), `community_drop_entry_id`, `shown_on_item_page` | `/api/drops?itemId=` + monster list |
| `sources.msea_reference_drops[]` / `msea_reference_note` | Pre-Big-Bang MapleSEA sources (`monster_id`, `monster_name`, `monster_level`) and MeowDB's caveat, verbatim. From an item page text capture (no item today; Green Apple, 242, until #32) the `monster_id` is **derived** (the one monster with that name and level in the bundled monster list; listed in `derived_fields`) and the caveat is `null` (not in the trimmed text) | page (or its text capture) |
| `sources.quest_rewards[]` | `quest_id` (MeowDB quest-tracker id), `quest_name`, `when` (`on_completion` / `on_accept`), `chance_pct` (random-reward share in percent, one decimal, e.g. 50, 14.3; `null` = not random), `label` (raw page text, e.g. `"(14%)"`, rounded), `row_key` | page "Quest Reward" (row key `<quest>-c--n` / `<quest>-a--n`); `chance_pct` from the quest page's `rewardRandom` |
| `sources.breakables[]` | `breakable_id`, `name`, `score` (votes) | page "Found in Breakables" |
| `sources.crafting_recipes[]` | Recipes that make this item: `recipe_key`, `discipline`, `category`, `produces_quantity`, `required_craft_level`, `craft_exp`, `meso_cost`, `ingredients[]` (`item_id`, `name`, `quantity`, `optional`) | page "Craftable" |
| `used_in.quests[]` | Quests that ask for it: `quest_id`, `quest_name`, `quest_npc_name`, `quest_level`, `quantity` | page "Needed By" |
| `used_in.recipes[]` | Recipes that consume it: `makes_item_id`, `makes_item_name`, `skill`, `quantity` | page "Needed By" |
| `change_history` | COT1 to COT2 changes: `updated_label`, `rows[]` (`key`, `stat`, `cot1`, `cot2`, `change`, raw strings), `notes[]`, `in_game_text` {`cot1`, `cot2`}; `null` if none | page |
| `beginner_creation_weapon` | `true` on 541 / 576 / 585 only (field absent elsewhere) | Beginner's guide |
| `derived_fields` | Fields computed by the extractor rather than shown by MeowDB | |
| `source` / `field_sources` | Page URL + `retrieved_at`; per-field overrides (API, drops API, monster list chunk, guide, monster page) | cache meta |
| `notes` / `gaps` / `discrepancies` | Per-item notes, missing values, conflicting values | |

### Derived fields (not MeowDB fields)

| MeowDB `type` | `inventory_tab` |
|---|---|
| Equip | equip |
| Use | use |
| Setup | setup |
| Etc | etc |
| Cash, Cash Equip | cash (none in this set) |

| MeowDB `subtype` | `equip_slot` |
|---|---|
| One-Handed Sword / Axe / Blunt Weapon, Two-Handed Sword / Axe / Blunt Weapon, Dagger, Spear, Polearm, Bow, Crossbow, Wand, Staff, Claw | weapon |
| Hat / Top / Bottom / Overall / Shoes / Gloves / Cape / Shield | hat / top / bottom / overall / shoes / gloves / cape / shield |
| Earring | earrings |

An Equip subtype outside this table gives `equip_slot: null` and a gap. No item in this set hits that case.

## Rules a game programmer must know

1. **Absent stat = no bonus.** MeowDB lists only non-zero bonuses and requirements. The files keep that for `stats` (keys present only) and write `0` for absent stat/fame requirements.
2. **Jobs.** `requirements.job: null` means any job, so a Beginner can wear it if level and stat requirements are met (`formulas/beginner.json` `equipment_restrictions`). MeowDB writes the Magician job as **`Mage`** on item pages (`945` Brown Training Shirt, `595` Iron Mace). Its character builder maps magician to `"Mage"` the same way. Match jobs by that string.
3. **Item names are not unique.** Two items in this set share the name "Red Cloth Pants": `1168` (male) and `1177` (female). "Jr. Sentinel Shellpiece" is `347` (game id `4000000`, the Maple Island one that Todd's quest 1005 asks for) and also `2584` (game id `4000067`, not extracted; MeowDB's item page code lists it as a material from an area not in the current release). `npcs/7.json` records that Todd's dialogue links the name to `2584`. Always key by id, never by name.
4. **Scroll numbers are not scroll stats.** `59`/`61`/`139`/`143` have empty `stats`. The bonus is applied to the target equip on success (`scroll.success_rate_pct`). MeowDB gives no rule here for failure (slot loss) or boom chance.
5. **Selling.** `sell_price_basis: per_unit` means mesos per unit in a stack. 25 items sell for **0** mesos: the 50-meso Pan/Sid equipment (`541`, `576`, `585`, `933`-`940`, `1157`-`1161`, `1305`, `1306`) plus `1308`, the arrows (`209`, `213`), Roger's Apple (`235`), Jr. Sentinel Shellpiece (`347`) and quest items `438`, `440`, `441`, `442`. The page omits the row and the API records `0`. This matches the shops domain (`shops.md`, "Sell-back 0").
6. **Buying.** A listed price buys one unit (`shops.md`). Prices differ by shop for some items: Pet Food costs 35 at Lucy but 30 elsewhere, so `npc_buy_price_mesos` = 30. For Maple Island, use `game/data/canonical/shops/*.json`. Every "Where to buy" row carries MeowDB's badge "COT2 prices", tooltip: *"Every price in this shop was read from in-game footage of the second Closed Beta."*
7. **Attack speed.** Tier names follow MeowDB exactly: 3 = Faster, 4 and 5 = Fast, 6 = Normal, 7 = Slow. `attack_cycle_ms` matches `formulas/attack_speed.json` `speed_tiers[].ordinary_attack_ms` (4: 720, 5: 750, 6: 810, 3: 660). Booster = tier - 2. Spear stab uses the spear column (tier 7: 810 ms). The wand cycle (810 ms) has no booster for magicians in 1st/2nd job.
8. **Hit boxes.** `box_px` = [left, top, right, bottom] in MapleStory px relative to the attacker's feet, **facing left**, y down. Mirror x when facing right. This is the same convention as `formulas/attack_styles.json`. A normal attack picks one of the `in_average: true` attacks. MeowDB's page text (rendered client-side): *"A normal attack picks one of the attacks, each with equal odds (60% swing, 40% thrust), and the averages use those attacks. Crouched attack is left out of average calculations."*
9. **Multipliers** are the weapon multipliers of the damage formula (`formulas/damage.json`). Sword 1.8/1.8, Axe and Blunt 2.4/1.2, Dagger 1.0/2.0, 2H Sword 2.5/2.5, Spear 1.5/3.5, Wand 1.8/1.8, Bow firing 2.5 / close-range 1.0.
10. **Food wording.** Apple and Egg say "Restores **around** 40 / 60 HP". MeowDB's value is exactly 40 / 60 and no variance is published. Use the flat value.
11. **Quest items** (`438`-`442`, `483`) are Untradeable with stack 100. `438`/`439`/`440` are handed out **on accept** by quests 1001/1007/1008 (`sources.quest_rewards[].when = on_accept`) and asked for by the same quest (`used_in.quests`).
12. **Random quest rewards.** `chance_pct` is MeowDB's share of the random pick, taken from the quest page to one decimal: Lucas's Reply (1008) gives one of seven hats (708-715 except 710) at 14.3% each. Biggs's Collection (1011) gives Razor or Fruit Knife at 50% each. The item page rounds these to whole percents ("(14%)", kept in `label`), so seven hats would add up to 98%. To roll a reward, use the quest file's `rewards.random[].total_weight` (`game/data/canonical/quests/<id>.json`; 1008 = 7 equal weights), not these percentages.
13. **Equipment stat rolls.** The item page says "Player-submitted drops compared with the clean stats. NPC shop copies always roll clean." So dropped equipment can differ from the clean `stats`, but MeowDB publishes no variance rule (gap). Use clean stats.
14. **Quest ids** are MeowDB quest-tracker ids. The Maple Island ones (`1000`-`1019`) have files in `game/data/canonical/quests/`. `10000`+, `12000`+, `506000`+ and `80000`+ are other regions, kept so the source lists stay complete.

## Gaps (MeowDB does not provide these)

- **Equipment stack size**: no "Max per Stack" for any Equip item (`max_stack: null` plus a per-file gap on all 55 equips). Non-stacking equipment would be a game-design decision, not MeowDB data.
- **Starting clothes / starting inventory** at character creation: not documented (see above). Only the weapon choice is documented.
- **Drop chances / quantities** for any monster drop: not published (votes only). Same as the drops domain.
- **Equipment stat variance** on drops: not published.
- **Scroll failure / slot-consumption rules**: not on item pages.
- **Knockback (`knockback_pct`, Hunter's Bow "KB 20%")**: the item page does not say what the value means.
- **Two-handedness**: only implied by subtype names ("Two-Handed Sword"). Item pages do not say whether Bow / Spear / Wand block a shield.
- **Arrow consumption per shot and arrow damage**: the arrow pages carry no stat beyond stack and price.
- **Consumable cooldowns / use animation**: not published.
- **Spear attack cycle** has no single value on MeowDB. It is published per kind (`attack_cycle_by_kind_ms`), so `attack_cycle_ms` is `null` on purpose for `633`.
- **Cash items**: none in scope; `inventory_tab: cash` is mapped but unused.

## Discrepancies

**Random quest-reward shares: item page vs quest page (15 files).** The item page's "Quest Reward" row rounds the share to a whole percent. The quest page's structured `rewardRandom` pool gives the same share to one decimal, with the pool's `totalWeight`. They disagree in display only:

| Quest | Items | Item page | Quest page (totalWeight) |
|---|---|---|---|
| 1008 Lucas's Reply | 708, 709, 711, 712, 713, 714, 715 | 14 | 14.3 (7) |
| 10202 Collecting 70 Cursed Dolls | 320, 321, 322, 324 | 14 | 14.3 (7) |
| 10201 Collecting 50 Cursed Dolls | 413, 414, 415, 417 | 17 | 16.7 (6) |

The files use the quest page value, the more precise rendering of the same weight. This follows the same rule as `requirements.level`, where the structured value wins. Each file records both values, the chosen one and the reason in `discrepancies`, and gives the quest page in `field_sources["sources.quest_rewards[quest_id=N].chance_pct"]`. `label` keeps the raw page text ("(14%)"). The other 6 random-share rows agree (1011: 50 ×2; 10203: 50; 10509: 50; 12119: 25 ×2; a seventh, 12121: 25, left with item 177, #32). The original extraction kept the rounded item-page values and did not record this disagreement. An adversarial verification pass found and fixed it.

**No other disagreement between MeowDB pages for the same value.** The extractor compares page vs item API for name, type, subtype, game id, level, job, every stat/requirement both show, attack speed, consumable values, chair bonus, sell price, max stack, tradeable flag and description. It also checks page rows against the page's own `baseStats` props. All of these agree. A future disagreement would be recorded per file in `discrepancies` (both values, the chosen one, and why).

Differences that are omissions, not conflicts (recorded as `notes`):

- **Untradeable flag**: the page tags 7 quest/monster items (`347`, `438`-`442`, `483`) as Untradeable, but the API has no `untradeable` field for them. It has `untradeable: true` only for `235` and `522`. The page tag is used.
- **Hidden community drop**: `/api/drops` lists **Mushmom (`700000`, Lv 40)** as a community drop of `271` Orange Potion and `273` Blue Potion. The item page hides it because Mushmom is missing from the monster list bundled with the page. The files keep it with `shown_on_item_page: false`; name and level come from `/monsters/700000`.
- **Sell-back 0**: 25 items have no sell-back row on the page; the API gives `0` (`sell_price_source: item_api`).

## Cross-checks performed

Printed on every run (`cross-checks: {...}`):

| Check | Count |
|---|---|
| Non-equipment page description box = API description | 39 |
| Page "In-game text" COT2 = API description | 30 |
| Page stat/requirement row = API stat | 95 |
| Page stat row = page `baseStats` props | 88 |
| Random quest-reward share found once on the quest page (`rewardRandom`, matched by game id and checked against the quest's `itemRefs` id); 15 of the 21 were rounded on the item page (see Discrepancies) | 21 |
| Every Maple Island shop row (`shops/*.json`) is in the item's "Where to buy" with the same price and sell-back | 23 |
| Every community entry in `drops/*.json` (by `community_drop_entry_id`) is in the item's `monster_drops` with the same monster and score | 83 |

Also checked by hand: every Maple Island quest link (1001, 1005-1012, 1019) in `quest_rewards` / `used_in.quests` matches `game/data/canonical/quests/<id>.json`, and every item a quest file names exists here. The API preview's top-3 drop and shop names all appear in the extracted lists. `attack_cycle_ms` values match `formulas/attack_speed.json`.

An adversarial verification pass re-derived every field of all 95 page-built files of the time (`177` among them, removed since by #32) without the extractor's flight-payload tree. It parsed the server-rendered HTML instead: visible text, plus `<a href>` ids for NPCs, maps, monsters, quests, breakables and recipe ingredients. It also read the item API and `/api/drops`. Header, requirements, stats, scroll bonuses, consumable/chair values, sell-back, stack, tags, description, weapon details (multipliers, attack cycle, reach, arrow range, every attack row), shops, MSEA list (with its count), quest rewards, Needed By, breakables, recipes, change history and community drops all matched. The quest-reward chance (above) was the only problem. The pass also checked these:

- Every weapon's `box_px` equals a hit-zone set in `formulas/attack_styles.json`. Only the bow labels differ, as that file's `action_labels` explains.
- Monster names and levels match `monsters/*.json`.
- Breakable rows and MSEA rows match `drops/*.json` in both directions.
- The item page code confirms the two derived drop flags: `score <= 0` rows get `opacity-60` (`disputed`), and monsters missing from the bundled list are not rendered (`shown_on_item_page`).

## Notes on tooling

- `lib.mjs` was used unchanged; no bugs found. The item page's body is found through the flight-payload row that contains `{"kind":"item","id":N}`, not a fixed row number (row ids differ by page). Lazy `$L` references are resolved into a plain node tree.
- Some page text is rendered only by client components (for example the reach explanation in rule 8). It is not in the flight payload, so it is quoted here rather than extracted per item.
- Cross-domain references in the files: crafting ingredients and products outside this set (`305`-`336`, `358`, `363`, `420`-`424`, `520`, `521`, `650`, `663`, `720`-`734`, `2722`), 157 quest ids, 135 monster ids, 28 NPC ids and breakable `0000001`. These are not extracted; they are references only.
