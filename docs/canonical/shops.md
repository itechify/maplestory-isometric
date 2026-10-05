# Canonical data: NPC shops (Maple Island)

Authority: **MeowDB MS Classic** (`https://meowdb.com/msclassic`), which documents MapleStory Classic World (Nexon, 2026).
All ids are MeowDB ids, not GMS ids.

- Data: `game/data/canonical/shops/<shop id>.json`, one shop per file. There is no index file, so every file in the folder is a shop.
- Extractor: `node tools/meowdb/extract_shops.mjs`. It reads from the cache first (`tools/meowdb/.cache`) and fetches only pages that are missing. `--refresh` downloads everything again. Running it twice on the same cache gives byte-identical output.

## What is included and why

Maple Island has exactly **three NPC shops**:

| Shop id (`id`) | NPC (`npc_id`) | Function | Map (`map_id`) | Rows |
|---|---|---|---|---|
| `maple-road-lucy` | Lucy (`21`) | Grocer | `000001013` Rainbow Street: Amherst Department Store | 6 |
| `maple-road-pan` | Pan (`16`) | Armor Seller | `000000061` Maple Road: Southperry Armor Store | 13 |
| `maple-road-sid` | Sid (`20`) | Weapon Seller | `000001011` Rainbow Street: Amherst Weapon Store | 4 |

The extractor checks this scope several ways and stops with an error if any check fails:

1. **NPC index (`/npcs`).** 21 NPCs have a map with `region: "MapleIsland"` (ids 1 to 21). Only 16, 20 and 21 have the role `Shopkeeper`.
2. **Shops index (`/npc-shops`).** It lists 43 shops. A shop is in scope when its `npcId` is a Maple Island NPC. The set this gives must equal the index's own "Maple Road (Beginner Zone)" group (`town: "maple-road"`).
3. **All 21 Maple Island NPC pages (`/npcs/1` to `/npcs/21`).** Only 16, 20 and 21 have a "Shop inventory" section.
4. **Map pages.** The `npcs` list on each shop's map page includes the shop's NPC.

### Shop contents

Buy prices come from the shops index and are the price of **one unit** (see Rules). Sell-back values come from each item's page. Where the page shows no sell-back row, they come from MeowDB's item API, which records `0` for those items (see Rules, "Sell-back 0").

**Lucy (Grocer), Amherst Department Store**

| # | item_id | Name | Type / subtype | Buy (mesos) | Max per stack | NPC sell-back (mesos) |
|---|---|---|---|---|---|---|
| 1 | 270 | Red Potion | Use / Potion | 50 | 100 | 5 per unit (COT1: 25) |
| 2 | 271 | Orange Potion | Use / Potion | 150 | 100 | 15 per unit (COT1: 75) |
| 3 | 236 | Apple | Use / Food | 20 | 100 | 2 per unit (COT1: 10) |
| 4 | 237 | Egg | Use / Food | 30 | 100 | 3 per unit (COT1: 15) |
| 5 | 239 | Orange | Use / Food | 50 | 100 | 5 per unit (COT1: 25) |
| 6 | 269 | Pet Food | Use / Pet Food | 35 | 200 | 15 per unit |

**Pan (Armor Seller), Southperry Armor Store.** Every row costs 50 mesos and has NPC sell-back 0 (item API `stats.price`; the item pages omit a 0 sell-back row). All are Equip.

| # | item_id | Name (item page) | Shop list name | Subtype |
|---|---|---|---|---|
| 1 | 933 | White Undershirt | same | Top |
| 2 | 934 | Grey T-Shirt | same | Top |
| 3 | 935 | Undershirt | same | Top |
| 4 | 937 | White Tube Top | same (renamed in COT2 from "White Tubetop") | Top |
| 5 | 938 | Yellow T-Shirt | same | Top |
| 6 | 939 | Green T-Shirt | same | Top |
| 7 | 940 | Red Striped Top | Red-Striped top | Top |
| 8 | 1157 | Blue Jean Shorts | Blue Jeans Shorts | Bottom |
| 9 | 1158 | Brown Cotton Shorts | same | Bottom |
| 10 | 1160 | Red Miniskirt | same | Bottom |
| 11 | 1161 | Indigo Miniskirt | same | Bottom |
| 12 | 1305 | Leather Sandals | same | Shoes |
| 13 | 1306 | Red Rubber Boots | same | Shoes |

None of Pan's item pages shows an "NPC Sell-back" row. The item API gives `stats.price: 0` for all 13 (`sell_price_source: "item_api"`).

**Sid (Weapon Seller), Amherst Weapon Store.** All are Equip.

| # | item_id | Name | Subtype | Buy (mesos) | NPC sell-back (mesos) |
|---|---|---|---|---|---|
| 1 | 541 | Sword | One-Handed Sword | 50 | 0 (item API) |
| 2 | 576 | Hand Axe | One-Handed Axe | 50 | 0 (item API) |
| 3 | 585 | Wooden Club | One-Handed Blunt Weapon | 50 | 0 (item API) |
| 4 | 558 | Razor | Dagger | 500 | 250 per item (item page; the API agrees) |

Referenced item ids (23): `270, 271, 236, 237, 239, 269, 933, 934, 935, 937, 938, 939, 940, 1157, 1158, 1160, 1161, 1305, 1306, 541, 576, 585, 558`.
Every shop item must exist in the items domain under these ids.

## Pages read

Times are `retrieved_at` from the cache meta.

| Page | Retrieved | Used for |
|---|---|---|
| `/npc-shops` | 2026-10-04T09:57:45.024Z | **Primary.** The flight payload has a `shops` array: `slug`, `region`, `town`, `npcName`, `npcId`, `npcFunction`, `location`, `videoMapName`, `mapId`, `patch`, `priceSource`, `opensNoShop`, `source`, `stats`, and `items[]` (`name`, `itemId`, `iconKey`, `classicPrice`, `mseaPrice`, `priceDelta`, `matchSource`, `hsSlug`, `citizenReq`). |
| `/npcs` | 2026-10-04T09:57:42.013Z | Maple Island NPC set (`region: "MapleIsland"`), roles, and maps for the scope checks. |
| `/npcs/1` to `/npcs/21` | 16: 10:05:25Z, 20: 10:05:27Z, 21: 10:05:29Z; the other 18 were already in the cache before this extractor first ran | The "Shop inventory (N items)" table (rows keyed `<itemId>-<index>`, price per row, "COT2 prices" badge, "Sold at" map). Also confirms that no other Maple Island NPC has a shop. |
| `/maps/000000061`, `/maps/000001011`, `/maps/000001013` | 09:56:51Z, 09:57:04Z, 09:57:07Z | The shop NPC appears in the map's `npcs` list. |
| `/item-db/<id>` for the 23 shop items | 10:05:55Z to 10:08:25Z (per item in `items[].item_page`) | Item-page name, type and subtype, "Max per Stack", "NPC Sell-back", "Recharge Cost", Change history (COT1 to COT2), and the "Where to buy" row for this NPC (price and map cross-check). |
| `/api/items/<id>?locale=en&preview=1` for the 23 shop items and 294 | 10:22:26Z to 10:22:58Z (per item in `items[].item_api`) | MeowDB's per-item JSON. The site's item hover preview fetches it (msclassic layout chunk: ``fetch(`/msclassic/api/items/${e}?locale=…&preview=1`)``). `stats.price` is the NPC sell-back: it equals the page's "NPC Sell-back" on all 7 shop rows that show one, and on Subi (250). `stats.unitPrice` is the "Recharge Cost" (Subi 0.3; absent on all 23 shop items). It is the source of `sell_price_mesos` when the page has no sell-back row. |
| `/api/items?search=<name>&page=1` for the 3 Safe-to-Sell `droppedNoPrice` items (Glowing Mushroom 519, Luminous Magical Resonance 2697, Rotten Root Fragment 2692) | 10:26:28Z to 10:30:09Z | Shows how MeowDB marks "no value": these items have **no `price` key** in `stats`. So `price: 0` on the shop equipment is a recorded value, not a missing one. |
| `/item-db/294` (Subi Throwing Stars) | 10:08:26.478Z | Reference only: shows how MeowDB documents recharging (see Rules). It is not sold on Maple Island. |
| `https://meowdb.com/_data/safe-to-sell.json` | 10:09:42.024Z | The data file behind the client-rendered `/item-db/safe-to-sell` page. It was found by reading that page's JS chunk (`fetch("/_data/safe-to-sell.json")`). Its `rows[].price` is the NPC sell price, used here as a cross-check. `generated: "2026-08-11"`. It covers only items needed by quests or crafting, so only Apple, Egg and Orange appear. |
| `/npc-shops/item-efficiency` (the "Shop Item Efficiency" tab), `/beginner`, `/consumables` | 10:05:33Z, 10:08:28Z, 10:08:30Z | A guide derived from the same shop data: price per HP/MP/WATK/WDEF, plus "Sold by". Its rows (`<itemId>-<idx>`, item link, NPC links, Price column) are used as a buy-price and name cross-check. Its "`<stat>` / meso" columns divide one item's stat by the listed price (Red Potion: 100 HP / 50 = 2.000). The extractor recomputes that ratio for every guide row of these shops (22/22 match), and the consumables tab says "Arrows are 1 meso each". Together these are the source of `quantity_per_purchase: 1`. The class tabs (warrior, bowman, thief, magician) were not read: every Maple Island item is any-class and appears on the Beginner tab. |
| `/item-db/safe-to-sell` (HTML) | 10:05:39.382Z | Client-rendered ("Loading the list..."). Its text says shop badges show "recorded NPC stock, but access can depend on the current launch area and your citizenship". |
| `/formulas/leveling` | 10:04:44.928Z | Citizenship shop-discount formula (see Rules). |
| `/citizenship` | 10:08:27.596Z | The citizenship towns are only Henesys and Kerning City. Discounts apply only in the active citizenship town, on eligible items. |
| `/guides/beginners-guide-first-steps-in-maple-world` | 10:06:38.610Z | "COT2 cut many consumable and material sell-back values"; "Gloves and capes are never sold at NPC shops"; "The number above is the NPC sell-back price". |
| `/formulas`, `/formulas/{attack-speed,damage,damage-taken,pets,spawns,targeting}`, `/guides/maplestory-classic-glossary`, `/item-db` | cached | Searched for sell, recharge and shop rules. **Nothing relevant** apart from the citizenship discount on `/formulas/leveling`. The word "recharge" appears on no cached page except the throwing-star item page. |

## File format (every field)

Top level:

| Field | Type | Meaning |
|---|---|---|
| `id` | string | The shop slug MeowDB uses as the anchor on `/npc-shops` (the NPC page links to `/msclassic/npc-shops#maple-road-pan`). MeowDB has **no numeric shop id**. |
| `name` | string | The MeowDB shop card heading, which is the NPC's name. No shop title was invented. |
| `npc_id`, `npc_name` | string | Owner NPC (MeowDB NPC id, e.g. `"16"`). Join with the npcs domain using `npc_id`. |
| `npc_function` | string | MeowDB's label (`Grocer`, `Armor Seller`, `Weapon Seller`), from the shops index. |
| `region`, `town_slug` | string | Shop index grouping ("Maple Road (Beginner Zone)", `maple-road`). |
| `map_id` | string | 9-digit MeowDB map id where the shop NPC stands. |
| `map_name`, `map_display_name` | string | The index's `location` ("Amherst Weapon Store") and `videoMapName` ("Rainbow Street: Amherst Weapon Store"). |
| `currency` | string | Always `"mesos"`. |
| `price_patch` | string | MeowDB's price-freshness tag. `COT2` means "re-read in game [in the second Closed Beta] and current". `COT1` would mean last checked in the first Closed Beta. All three shops are `COT2`. |
| `opens_no_shop` | bool | MeowDB flag for NPCs whose shop window opens empty. `false` for all three. |
| `meowdb_record_source` | string | The index's `source` field. `classic-only` means the shop was recorded from Classic itself, not matched from a reference list. |
| `item_count` | int | Number of rows. It equals the NPC page heading "Shop inventory (N items)". |
| `items` | array | Shop rows in **display order** (see Rules). |
| `source` | object | `{authority, url: ".../npc-shops#<id>", retrieved_at}`. |
| `field_sources` | object | Fields that do not come from the shops index. Item-page fields use the URL template `.../item-db/{item_id}`, with the exact URL and time per row in `items[].item_page`. `sell_price_mesos` also has `fallback_url` (the item API template, per-row time in `items[].item_api`). `quantity_per_purchase` cites the Shop Item Efficiency guide. |
| `cross_checks` | object | What the extractor compared and the result (see Cross-checks). |
| `discrepancies`, `gaps`, `notes` | arrays | Per-shop copies of the sections below. |

Per item row (`items[]`):

| Field | Type / unit | Source | Meaning |
|---|---|---|---|
| `position` | int, 1-based | index order | Display order in the shop window. |
| `item_id` | string | index `itemId` | MeowDB item id, the URL form (`"933"`). Item pages show it zero-padded ("No. 0933"). Do not copy the padding. |
| `name` | string | item page heading | Canonical item name. |
| `shop_list_name` | string | index `name` | The name as written in MeowDB's shop list. It differs from `name` for 940 and 1157 (see Discrepancies). |
| `icon_key` | string | index `iconKey` | MeowDB's icon key. **It is not the item id.** Use it only as an opaque cross-reference and never to fetch art. |
| `item_type`, `item_subtype` | string | item page breadcrumb | e.g. `Use` / `Potion`, `Equip` / `Top`. |
| `price_mesos` | int, mesos | index `classicPrice` | Base buy price of **one unit** (see Rules). |
| `quantity_per_purchase` | int (`1`) | Shop Item Efficiency guide | Units bought for `price_mesos`. It is `1` on every row: MeowDB's guide divides one item's stat by this price (re-checked on 22/22 rows; Pet Food is in no ratio table but uses the same list format) and says "Arrows are 1 meso each". This is **not** a limit on how many units the player may buy at once; MeowDB documents no such limit. The extractor sets it to `null` if the check ever fails. |
| `stock_limit` | null | none | **Gap.** MeowDB documents no stock limits. |
| `citizen_req` | null or string | index `citizenReq` | Citizenship grade needed to buy the row (e.g. "Helpful Stranger" on Henesys/Kerning civic shops). `null` on all Maple Island rows, so no restriction applies. |
| `max_per_stack` | int or null | item page "Max per Stack" | Stack size in the inventory. `null` for equipment (the page has no such row). This is **not** a purchase bundle. |
| `sell_price_mesos` | number or null, mesos | item page "NPC Sell-back", else item API `stats.price` | What an NPC pays when the player sells this item. The page omits the row when the value is 0, so the 16 cheap equipment rows (Pan's 13; Sid's Sword, Hand Axe, Wooden Club) come from the API and are `0`. `null` only if neither source has a value (no row today). |
| `sell_price_basis` | `"per_unit"`, `"per_item"` or null | item page row label | `per_unit` when the label is "NPC Sell-back (per unit)" (stackables). `per_item` when it is just "NPC Sell-back" (Razor). For API-sourced rows there is no label: `per_unit` if the item page has a "Max per Stack" row, else `per_item`. That rule reproduces the label on all 7 labelled rows. All 16 API rows are `per_item`. |
| `sell_price_source` | `"item_page"`, `"item_api"` or null | | Which source `sell_price_mesos` came from. |
| `rechargeable` | bool | item page | `true` only if the item page has a "Recharge Cost" row. It is `false` for all 23 rows. |
| `recharge_cost_mesos_per_unit` | number or null | item page "Recharge Cost" | `null` for all 23 rows. |
| `sell_price_history` | array of `{cot1_mesos, cot2_mesos}` | item page Change history | The "Sell-back price" change between tests. |
| `other_change_history` | array of `{stat, cot1, cot2}` | item page Change history | Other changed stats, e.g. Sword "Shop price (mesos)" 3,000 → 50. The page notes "Sold by Karl (Henesys).", so MeowDB ties that COT1 3,000 observation to Karl's shop. It does not say what Sid charged in COT1. Sid's current price is `price_mesos`. |
| `change_notes` | array of strings | item page Change history | e.g. "Renamed in COT2. It was called White Tubetop." |
| `price_match_source` | string | index `matchSource` | MeowDB's internal provenance tag for how the row was matched. It is `hand` on every row. |
| `item_page` | `{url, retrieved_at}` | | The item page each item-page field came from. |
| `item_api` | `{url, retrieved_at}` | | The item API response used for the sell-back fallback and cross-checks. |

Index fields that were dropped: `mseaPrice` and `priceDelta` (`null` on every Maple Island row), `hsSlug` (`null`), `npcPortrait` (an image path), and `stats` (`{expectedCount, priced, extraCount}`; for all three shops expected = priced = row count and extra = 0).

## Rules a game programmer must know

What MeowDB states:

- **Buying.** `price_mesos` is the base price of **one unit**, in mesos (`quantity_per_purchase: 1`). Buying N units costs N × `price_mesos`. MeowDB's Shop Item Efficiency guide computes "HP / meso" as one Red Potion's 100 HP / 50 mesos = 2.000, Wooden Club's WATK / meso as 19 / 50 = 0.380, and says "Arrows are 1 meso each". MeowDB documents no per-purchase maximum. On discounts: the Victoria Island "scroll-pass" shops (Mina, Silver, Arturo and others) carry the price note "citizenship-discounted rows recorded at their struck-through base price". The three Maple Island shops carry a different note (the community-screenshots one) and have no discounted rows (`citizen_req` is null everywhere), so their prices are base prices either way.
- **Display order** is the index order. The `priceSource` for all three shops reads: "Community screenshots 2026-08-12 (COT2) posted in Discord by SiuoL93; each list read top-to-bottom and found IDENTICAL to the first test - re-dated, not repriced." The NPC page's rows (`<itemId>-<index>`) are in the same order.
- **Citizenship discount** (`/formulas/leveling`, `/citizenship`): `Shop discount = (2 × Grade + 3)%` at Grades 1 to 9 and 25% at Grade 10. `Price = round(Base × (100 − Discount) / 100)`. It applies only in the player's *active citizenship town*, which is Henesys or Kerning City (the only two), and only on eligible tagged items. Citizenship unlocks at level 12. **It never applies in these three Maple Island shops.** A generic shop system still needs the `citizen_req` field and the discount hook for later towns.
- **Equipment bought from an NPC has clean stats.** Item pages say: "NPC shop copies always roll clean." Do not randomize stats on equipment bought from a shop.
- **Selling.** The NPC pays `sell_price_mesos`, per unit for stackables (`per_unit`). COT2 cut many consumable sell-back values: for example, Red Potion went from 25 to 5 (COT1 to COT2) and Orange Potion from 75 to 15. Use the COT2 value, which is the one in `sell_price_mesos`. MeowDB gives no general sell-price formula (for example, a fraction of the buy price). Do not derive one: 5/50, 15/150, 15/35, 250/500 and 0/50 are not a constant ratio. MeowDB documents no restrictions on which NPC buys what.
- **Sell-back 0.** The 16 cheap equipment rows (all of Pan's, plus Sid's Sword, Hand Axe and Wooden Club) have `sell_price_mesos: 0`. The evidence:
  - The item API records `stats.price: 0` for them.
  - The item page shows no "NPC Sell-back" row when the value is 0. Where it does show one, the row equals `stats.price` on 7/7 shop rows and on Subi.
  - Items MeowDB truly has no value for (the Safe-to-Sell `droppedNoPrice` items) have no `price` key at all.

  MeowDB does not say whether the NPC refuses a 0-value item or accepts it for 0 mesos. Either is consistent with the data, and neither pays anything.
- **Recharging** (throwing stars and similar). MeowDB shows a per-unit "Recharge Cost" on rechargeable items: Subi Throwing Stars (`/item-db/294`) costs 0.3 mesos per unit (item API `stats.unitPrice` 0.3), with a max stack of 500 and a sell-back of 250 per unit. The item text says "Once they run out, they need to be recharged". **No Maple Island shop sells a rechargeable item**, and MeowDB does not say which NPCs offer recharging.
- **Gloves and capes are never sold at NPC shops** (beginner guide). This applies to future shops.

## Gaps (MeowDB does not provide these)

- **Shop id:** MeowDB has no numeric shop id, so the slug is used.
- **Per-purchase limit.** A price buys one unit (`quantity_per_purchase: 1`), but MeowDB does not say how many units one purchase may buy.
- **Stock limits and restocking** (`stock_limit` is null).
- **What selling a 0-value item does.** Sell-back is `0` for 16 of the 17 equipment rows: 933, 934, 935, 937, 938, 939, 940, 1157, 1158, 1160, 1161, 1305, 1306 (Pan) and 541, 576, 585 (Sid). MeowDB does not say whether the NPC refuses these or pays 0. The beginner guide's sell-back table covers other weapons (Long Sword and others) and was **not** used for these items.
- **A sell-price formula and sell restrictions:** neither is documented.
- **Recharge:** MeowDB does not say whether Lucy (or any Maple Island NPC) recharges stars, or what a recharge costs at a particular NPC.
- **MSEA reference prices:** `mseaPrice` is null for every Maple Island row. These are Classic-only records.
- **Level or job buy restrictions** are not part of the shop data. Item requirements (e.g. Razor's level) belong to the items domain.

## Discrepancies

1. **Item 940 name.** The shop list (index and NPC page) shows "Red-Striped top". The item page shows "Red Striped Top" and says "Renamed in COT2. It was called Red-Striped Top." The Shop Item Efficiency guide also shows "Red Striped Top". **Chosen:** `name` = "Red Striped Top" (the item's own page plus the rename note), and `shop_list_name` keeps "Red-Striped top". The shop list carries the pre-COT2 name, and even that differs in letter case.
2. **Item 1157 name.** The shop list shows "Blue Jeans Shorts". The item page and the efficiency guide show "Blue Jean Shorts", with no rename note. **Chosen:** `name` = "Blue Jean Shorts", and `shop_list_name` = "Blue Jeans Shorts".

The NPC page and the index render the same dataset, so their agreement does not confirm the data independently. The item pages and the efficiency guide do give independent views.

There were no price discrepancies.

## Cross-checks performed (all passed)

- **NPC page table vs index:** same item ids, same order, same prices and same names. The "Shop inventory (N items)" count matches, and the "Sold at" map matches `map_id`. Lucy 6/6, Pan 13/13, Sid 4/4.
- **Item page "Where to buy"** row for this NPC: same price and same map, for 23/23 rows.
- **NPC index:** each owner has role `Shopkeeper` and lists the shop map. **Map page:** the owner is in the map's `npcs` list.
- **`safe-to-sell.json` sell price vs item-page sell-back:** Apple 2, Egg 3 and Orange 5 match (3/3). The other 20 items are not in that file.
- **Item API vs item page** (`cross_checks.item_api`): `stats.price` equals the page sell-back on 7/7 labelled rows, and on Subi. `stats.unitPrice` agrees with "Recharge Cost" on 23/23 (absent on both). The API name equals the page name on 23/23. The `per_unit`/`per_item` rule from "Max per Stack" reproduces the page label on 7/7. The 3 `droppedNoPrice` reference items have no `price` key (`zero_is_recorded_value: true`). If that ever stops holding, the extractor stops trusting an API `0` and leaves the value `null`.
- **Per-unit pricing** (`cross_checks.shop_item_efficiency_guide.per_unit_ratio_rows`): the guide's "`<stat>` / meso" equals one unit's stat ÷ `price_mesos` on 22/22 rows (Lucy 5, Pan 13, Sid 4), and "Arrows are 1 meso each" is present.
- **Shop Item Efficiency guide** buy price for rows listing this NPC as seller: Lucy 5/5 rows found, Pan 13/13, Sid 4/4. All match. Lucy's Pet Food is not checked: the guide's Pet Food table lists only the cheapest seller ("Doofus (Henesys) is the pet food specialist with a 5-meso discount", 30 mesos). That fits Lucy's 35.

## Notes on tooling

- `lib.mjs` works as documented. No bugs were found.
- The Safe-to-Sell data lives at the site root (`https://meowdb.com/_data/safe-to-sell.json`), outside `/msclassic`. `fetchUrl` caches it as `.cache/_data_safe-to-sell.json`.
- The item API (`/msclassic/api/items/<id>?locale=en&preview=1`) is cached as `.cache/api_items_<id>_q_locale_en_preview_1.html` (JSON body; `lib.mjs` appends `.html` to keys that do not end in `.js` or `.json`). Its `stats` is an object. In the list and search endpoints (`/api/items?type=…&subtype=…&page=N`, `/api/items?search=…&page=1`), `stats` is a JSON **string** and must be parsed a second time. The extractor handles both.
- Git Bash rewrites command-line arguments that start with `/` (e.g. `/_next/static/...`) into Windows paths. Set `MSYS_NO_PATHCONV=1`, or build the URL inside the script, when passing such paths to a helper script.
