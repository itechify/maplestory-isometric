# Items, inventory, equipment, consumables, mesos, shops and drops

Brief phases 10 to 13 and 15 ("Drop Architecture" included). This system holds the pure rules for everything a
character carries, wears, uses, buys, sells and picks up, plus the one seam that announces those changes on the
`Events` bus. It builds no nodes and changes no scene tree. The one lookup it makes is the `Game` autoload, read only
to ask whether the live character is dead (see "Dead characters cannot use items"). Actors, UI and the HUD call it.

## Files

| Path | Class | Role |
|---|---|---|
| `game/scripts/core/items/item_def.gd` | `ItemDef` | Typed read-only view of one canonical item |
| `game/scripts/core/items/items_config.gd` | `ItemsConfig` | Reader for `data/misostory/inventory.json` |
| `game/scripts/core/items/inventory.gd` | `Inventory` | Five-tab inventory (**contract**) |
| `game/scripts/core/items/equipment.gd` | `Equipment` | Equipped pieces, requirements, slot conflicts (**contract**) |
| `game/scripts/core/items/consumables.gd` | `Consumables` | Using potions and food |
| `game/scripts/core/items/mesos.gd` | `Mesos` | Meso add/spend rules and the cap |
| `game/scripts/core/items/item_codes.gd` | `ItemCodes` | Result codes and default messages |
| `game/scripts/core/items/item_service.gd` | `ItemService` | The seam: mutates a `CharacterState` and emits `Events` |
| `game/scripts/core/shop/shop_service.gd` | `ShopService` | Buying and selling against canonical shop data |
| `game/scripts/core/drops/drop_rates.gd` | `DropRates` | Resolves placeholder rates against canonical drop tables |
| `game/scripts/core/drops/drop_roller.gd` | `DropRoller` | Turns a kill into drops with a seeded RNG |
| `game/data/misostory/inventory.json` | | Tab sizes, equipment stack size, slots and conflicts, weapon metadata, job tags, meso cap, shop rules |
| `game/data/misostory/drop_rates.json` | | Placeholder drop chances, quantities and meso amounts |
| `game/data/misostory/drops.json` | | Ground lifetime, owner-only time and drop scatter |

## Data flow

```
data/canonical/items/<id>.json ──► ItemDef ──► Inventory / Equipment / Consumables / ShopService
data/canonical/shops/<id>.json ──────────────────────────────────────► ShopService.stock / buy / sell
data/canonical/drops/<owner>.json ─┐
data/misostory/drop_rates.json ────┴► DropRates ──► DropRoller.roll(owner, db, rng) ──► [{kind, item_id, qty} | {kind: mesos, amount}]
data/misostory/drops.json + formulas/loot_rules.json ──► DropRoller.ground_records(drops, now, owner, db)
    ──► MapInstanceState.add_drop(record + pos_local) ──► ItemService.pickup(record)
data/misostory/inventory.json ──► ItemsConfig ──► Inventory, Equipment, Mesos, ShopService

CharacterState.inventory / .equipment / .mesos  ◄── pure rules (no signals)
            ▲
ItemService(character, db, bus) ── emits ──► Events.item_gained, item_lost, item_used, inventory_changed,
                                              inventory_full, equipment_changed, stats_changed, hp_changed,
                                              mp_changed, mesos_changed
```

`Inventory` and `Equipment` live inside `CharacterState` and own their `to_dict()` / `from_dict()`. Mesos are
`CharacterState.mesos`. A save therefore persists all three with no extra work.

### The event seam

The rules never emit signals. Gameplay code wraps the live character in an `ItemService` and passes in the bus:

```gdscript
var items := ItemService.new(Game.character, Data.db, Events)
items.gain("270", 5)                    # item_gained, inventory_changed (+ inventory_full if not everything fit)
items.pickup(drop)                      # all-or-nothing for items; mesos up to the cap
items.use_item("270")                   # item_used, item_lost, inventory_changed, hp_changed / mp_changed
items.dead_check = func() -> bool: return dead   # optional: who decides "dead" (default: Game, live character)
items.equip("541"); items.unequip("weapon")   # equipment_changed per slot, inventory_changed, stats_changed
items.clear_inventory()                 # debug "clear inventory": item_lost per item id, inventory_changed
ShopService.buy(Game.character, "maple-road-lucy", "270", 10, Data.db, Events)
```

`bus` is any object that has the `Events` signals. Pass `null` for silent use. Tests pass a fresh instance of
`events.gd`. `ShopService` mutates through an `ItemService` too, so all of these signals come from one place. Code
that changes `character.inventory` directly gets no signals. It must emit them itself, or the HUD and UI will not
update. An id that is not a canonical item is a data bug, not a full bag: `gain` / `gain_all` add nothing, emit
nothing (no `inventory_full`) and push a warning.

## Canonical sources used

| Data | File | Used for |
|---|---|---|
| Items | `data/canonical/items/*.json` | tab (`inventory_tab`), `max_stack`, `equip_slot`, `requirements`, `stats`, `weapon`, `consumable`, `npc_buy_price_mesos`, `sell_price_mesos` / `sell_price_basis`, `tradeable`, `quest_item`, `gender`, `setup`, `scroll` |
| Shops | `data/canonical/shops/*.json` | stock and display order, `price_mesos`, `quantity_per_purchase`, `citizen_req`, `stock_limit` |
| Drop tables | `data/canonical/drops/*.json` | which items each owner drops (`status`, `disputed`), owner kind, meso player reports |
| Monsters | `data/canonical/monsters/*.json` | `level`, for the meso placeholder |
| Formulas | `formulas/loot_rules.json`, `recovery.json`, `beginner.json`, `damage.json`, `derived_stats.json` | inventory-full rule, "mobs drop potions rarely", the job-to-item-tag map (character builder code), weapon formula key names, the total-stats statement |

No canonical number appears in code. Tests read expected values from the same records.

## Rules

- **Tabs and stacking.** Every item goes into its canonical `inventory_tab`. An add first tops up existing stacks of
  the item, then fills empty slots in order. `add` returns how many were added; partial adds are allowed. `remove`
  takes from the last slots first, and from clean stacks before stacks that carry instance data. Stacks only merge
  when both have empty instance data.
- **Slots.** A slot holds `{item_id, qty, data}`. `data` is per-instance state: empty for clean items, and the place
  for future scroll results. `Equipment.total_bonuses` honours `data.stats`. Capacity belongs to each inventory and
  is saved with it, so slot expansions are save state. Defaults come from `inventory.json`.
- **Saves.** `to_dict` is lossless: capacities, slot indices, quantities and instance data. `from_dict` converts
  JSON floats back to ints, also inside instance data, and never drops a valid item. A saved slot past capacity
  grows the tab. Ids from saves and entry lists go through `ItemDef.id_of` (`541` or `541.0` becomes `"541"`), so
  a numeric id never crashes a load. Entries that cannot be an item (no id, qty <= 0, a tab outside `TABS`) are
  skipped with a warning.
- **Equip requirements** (`Equipment.equip_check`), in this order:
  1. level;
  2. job (`requirements.job` against `inventory.json job_item_tags`; a Beginner matches only "no job"; a job slug
     the table does not list, such as a later advancement, uses its base class from `StatCalculator.JOBS`);
  3. STR/DEX/INT/LUK as **total** stats (`StatCalculator.total_stat`, which includes current equipment);
  4. fame;
  5. gender.

  `items.md` labels the requirement fields "Minimum base stat". The brief says to use total stats, and
  `derived_stats.json` only says "Equipment requirements only decide whether you can equip an item". This is an
  open question. **Gender** is checked only when known. `CharacterState` has no gender field, so the check reads a
  `gender` property if one is added later, else `flags.gender`.
- **Equip and unequip.** Equipping takes the item out of the inventory. The previous occupant and any conflicting
  pieces go back, and the first of them takes the slot the new item left. The slot conflicts come from data:
  - an overall removes the top and the bottom;
  - a top or a bottom removes an overall;
  - a two-handed weapon removes the shield;
  - a shield removes a two-handed weapon.

  N displaced pieces need N - 1 free slots beyond the one the new item frees, or the result is `inventory_full` and
  nothing changes. Unequip needs one free equip slot. After an equipment change, `ItemService` clamps HP and MP to
  the new maxima.
- **Consumables.** These are flat `hp_restore` / `mp_restore`. Percentage restores (`hp_restore_pct`, floored) and
  buffs (`consumable.buffs`, returned in the result for the effect system) are supported as data, but no current item
  has them. Restores are clamped to `StatCalculator.max_hp` / `max_mp`, and one unit is consumed. A potion used at
  full HP is still consumed. Pet Food, scrolls, chairs, equipment and Etc items return `not_usable`.
- **Dead characters cannot use items** (`dead`, checked after the item checks). "Dead" is not "HP 0": the game
  shell takes a death's loss at the moment of death (GAME_SHELL.md "Death and respawn"), so while the death notice is
  up the character already holds its respawn HP (`death.json`). `Consumables.is_dead(character, db, dead_check)` is
  true when either of these holds:
  1. the canonical trigger, `Progression.is_dead` (HP 0, `formulas/death.json`). This also covers the moment
     between HP 0 and MapSession's `DEAD`, and a death during a warp;
  2. the dead check, a zero-argument `Callable` returning bool. `Game.is_character_dead` fits as is. It is passed to
     `Consumables.use(..., dead_check)` or set as `ItemService.dead_check`.

  With no check injected (the default), `Consumables.default_dead_check(character, game = null)` asks the `Game`
  autoload's `is_character_dead()`, which also reads MapSession's `DEAD` state. It does so only when `character` is
  `Game.character`, by identity, resolved at each use, so a new game or a load is followed. Any other character (a
  test fixture, a sandbox) gets only the HP trigger, so it never inherits the live game's death. Inject a check to
  keep the rules off the scene tree. The `game` argument is the test seam.
- **Mesos.** Mesos can never go negative. Earning adds only up to the cap. A sale that would pass the cap is refused
  (`meso_cap`).
- **Shops.** One purchase of a row costs `price_mesos` and gives `quantity_per_purchase` units. `quantity` counts
  purchases. Checks run in this order:
  1. the shop exists;
  2. the shop sells the item;
  3. the quantity is valid;
  4. citizenship (`citizen_req`; no Maple Island row has one);
  5. mesos;
  6. inventory space.

  The citizenship discount has a hook (`price_for`) that returns the base price, because no Maple Island shop is
  eligible. Cost and units are saturating products, so an absurd quantity reads as unaffordable instead of wrapping
  to a small 64-bit cost. Selling pays the item's canonical `sell_price_mesos` per unit (`per_unit`) or per item (`per_item`),
  from any shop. MeowDB documents no sell restrictions. Shop equipment is clean (empty instance data).
- **Drops.** `DropRoller.roll` first rolls one meso bag, then rolls each eligible table entry in canonical order. Each
  eligible roll uses one `randf()`, and each drop uses one `randi_range`, so a seed reproduces a kill exactly. Drops
  spawn at death (canonical).
- **Ground records.** `DropRoller.ground_records(drops, now, owner, db)` turns rolled drops into the
  `MapInstanceState` record shape (`{item_id | mesos, amount, pos_local, expires_at, owner}`, MAP_ARCHITECTURE
  4.7.2). It adds `expires_at` = now + `ground_lifetime_s`, `owner`, `free_at` = now + `owner_exclusive_s`, and a
  scatter offset along the ground (0, +s, -s, +2s, ... with s = `scatter_spacing_px`) as `offset_px` and
  `offset_m` (`WorldScale.h`). The caller adds the kill position. `DropRoller.may_pick_up(record, who, now)`
  applies the ownership window. `DropRates.pickup_box_px` / `pickup_box_m` give the canonical player pickup box
  (`loot_rules.json player_pickup_box_px`), converted with `WorldScale.actor`.
- **Pickup.** `ItemService.pickup` accepts `DropRoller` output, ground records and the map-instance shape. A drop is
  a meso bag when its `kind` says so, or (no `kind`) when it has a `mesos` key and no `item_id`; an item record
  that also carries a `mesos` key stays an item. Quantities are parsed defensively (`ItemService.quantity_of`).
  An item that does not fit stays on the ground (Roger: "When your Item Inventory is full, you won't be able to
  pick up new items").

## Adaptations (MeowDB publishes none of these)

Every value below is marked `"verified": false` with a reason in its file. The validator
(`scripts/validate_data.sh`) and `test_drops_data` / `test_inventory_item_def` enforce that.

| File:key | Value | Why |
|---|---|---|
| `inventory.json:tab_slots` | 24 per tab | No inventory size on MeowDB; commonly remembered pre-Big-Bang start size |
| `inventory.json:equipment_max_stack` | 1 | MeowDB has no "Max per Stack" for equipment; unstackable so each piece can carry instance data |
| `inventory.json:unpublished_max_stack` | 1 | Fallback for a non-equip item with null `max_stack` (none today) |
| `inventory.json:meso_cap` | 2,147,483,647 | No cap documented; signed 32-bit counter limit so mesos cannot overflow |
| `inventory.json:equipment_slots` | 10 brief slots + face/eye accessory, pendant, ring 1-4 | Remaining classic slots, so future content is data only |
| `inventory.json:slot_conflicts` | overall <-> top/bottom, two-handed <-> shield | Classic rules; item pages do not state them |
| `inventory.json:weapon_subtypes` | damage family / multiplier / action-odds keys, `two_handed` | Keys follow `damage.json` labels. Two-handedness is a MeowDB gap: names say "Two-Handed"; Spear, Polearm, Bow, Crossbow, Claw follow the classic client; Wand, Staff are one-handed |
| `inventory.json:job_item_tags` | beginner [], warrior Warrior, magician Mage, bowman Bowman, thief Thief (+ pirate guess) | Transcribed from MeowDB's character-builder code in `beginner.json` |
| `inventory.json:shop.sell_zero_value_items` | true | MeowDB does not say whether NPCs refuse 0-value items; MisoStory takes them for 0 |
| `inventory.json:shop.max_bundles_per_purchase` | null (no limit) | MeowDB documents no per-purchase cap |
| `drop_rates.json` | see below | No drop chance, quantity or meso amount is published |
| `drops.json:ground_lifetime_s` | 180 | Undocumented; commonly remembered classic value |
| `drops.json:owner_exclusive_s` | 15 | Ownership exists (formulas/pets) but its duration is undocumented |
| `drops.json:scatter_spacing_px` | 25 | Drop spacing is undocumented |

### Drop placeholders (`drop_rates.json`)

Each field (`chance`, `min_quantity`, `max_quantity`) comes from the first level of this list that has it:

1. `owner_item_overrides[owner][item]`
2. `item_overrides[item]`
3. `subtype_rates["Type/Subtype"]`
4. `type_rates[Type]`
5. `default_rate`

Type and subtype come from the canonical item. An override is an explicit decision: it applies even to excluded
entries, and the status multiplier is not applied to it. `global_rate_multiplier` (1.0) scales every item chance.
`DropRates.effective_entries` reports where each chance came from.

| Level | Chance | Justification |
|---|---|---|
| status `classic_confirmed` | x1.0 | Players saw it drop in Classic World |
| status `msea_reference` | off | MeowDB: "historical reference only"; enabling it is a labelled design decision |
| `disputed` (score <= 0) | off | At least as many players report not seeing it |
| `Etc/Monster Drop` | 0.40 | The signature drop of every table; 10 Blue Snail Shells take about 25 kills |
| `Use/Potion`, `Use/Food`, `Use/Arrow` | 0.02 | MeowDB's Beginner's guide: "Mobs drop them rarely" |
| `Use/Scroll` | 0.001 | The rarest classic drops |
| `Etc/Gem` / `Etc/Ore & Mineral` | 0.005 / 0.01 | Valuable crafting materials |
| `Equip` | 0.005 | About 1 in 200 kills per listed piece |
| `Setup` | 0.002 | Chairs are rare trophies |
| default | 0.01, quantity 1 | Anything else |

**Quest items are always obtainable.** Each item a Maple Island quest asks the player to collect has an explicit
override:

- 347 Jr. Sentinel Shellpiece from monster 1: 1.0 (Todd's tutorial cannot stall);
- 349 from Blue Snail and 356 from Orange Mushroom: 0.4 (quest 1011);
- 441 and 442 from the Wooden Box `0000001`: 0.5 (quest 1012). Box food drops at 0.3.

`test_quest_items_are_obtainable` derives the list from `quests/*.json` objectives, minus the items a quest hands
out on accept, so a new quest without a source fails the test.

**Mesos.** Chance 0.6 per kill. Where a monster has MeowDB player reports, the amount is read from canonical
`drops/<id>.json meso.median_min/max` at roll time (Snail: one report, 2 mesos). Otherwise the amount is a uniform
integer in `[max(1, floor(level x 1.5)), ceil(level x 2.5)]`: Blue Snail 3-5, Shroom 4-8, Red Snail 6-10, Orange
Mushroom 12-20. The Tutorial Jr. Sentinel drops none (`by_owner`). Breakables drop none (canonical status
`not_applicable`).

## Result codes

Every operation returns `{"ok": bool, "code": String, ...details}`. `ItemCodes.message(result)` gives a default
English line. The codes are:

| Codes | Operations |
|---|---|
| `ok`, `unknown_item`, `invalid_quantity` | all |
| `inventory_full`, `not_enough_items` | inventory |
| `insufficient_mesos`, `meso_cap` | mesos |
| `unknown_shop`, `not_sold_here`, `citizenship_required`, `no_sell_price`, `zero_value_refused` | shops |
| `not_equipment`, `unknown_slot`, `slot_empty`, `level_too_low`, `job_mismatch`, `stat_too_low`, `fame_too_low`, `gender_mismatch` | equipment |
| `not_usable`, `dead` | consumables |

Details carry the relevant numbers, for example `stat_too_low {stat, required, actual}` and buy
`{cost, units, mesos}`.

## Testing

```bash
ISOLATE=items bash scripts/test.sh inventory equipment consumable shop drops mesos   # 147 tests, 12 files (with test_shop_ui_window)
ISOLATE=items bash scripts/validate_data.sh                                          # data convention + references
```

| File | Covers |
|---|---|
| `test_inventory_core.gd` | add/remove/count, stacking, overflow into new slots, full tab, `can_add_all`, move/merge/swap, instance data, lossless and JSON round trips, numeric ids and garbage in saves, `clear` |
| `test_inventory_item_def.gd` | every canonical item builds; tab, stack, stats to BONUS_KEYS, requirements, consumables, prices, flags, weapon keys present in `damage.json` and identical to `WeaponProfile.SUBTYPES`; `inventory.json` labelled |
| `test_inventory_service.gd` | the exact `Events` emitted by gain/lose/pickup/move/clear; atomic `gain_all` / `lose_all`; every drop record shape; unknown ids and malformed entries change nothing |
| `test_inventory_flow.gd` | brief Test D: Snail meso bag, potion and weapon as ground records, pickup, use, equip, W.ATK, JSON save and reload with identical derived stats |
| `test_equipment_core.gd` | equip/swap/unequip (also with a full equip tab), level, job, total-stat (worn bonuses count), fame and gender failures, overall <-> top/bottom, two-handed <-> shield (synthetic overall and shield on a private db copy), `total_bonuses`, Max HP, W.ATK, damage and CRIT% through `StatCalculator`, HP clamp on unequip, round trips and numeric ids, equipment signals |
| `test_consumable_use.gd` | HP/MP restore and clamp, decrement, full-HP use, Roger's Apple, every potion and food Lucy sells, unusable items, dead at HP 0, persistence, `item_used` |
| `test_consumable_dead.gd` | an injected dead check refuses use at positive HP, HP 0 is dead whatever the check says, the check runs at each use and after the item checks, `ItemService.dead_check` refuses silently, `default_dead_check` resolves to `Game.is_character_dead` for the live character only (on a private `GameState` and against the autoload, unchanged), and a committed death (private MapSession and `DeathRules`) refuses potions at the respawn HP until the respawn, leaving the `MapSession` autoload as it was |
| `test_mesos_wallet.gd` | add/spend validation, never negative, cap, `mesos_changed`, persistence |
| `test_shop_buy_sell.gd` | stock equals canonical rows, price x quantity, exact affordability, insufficient mesos, full inventory, clean equipment, bad requests, sell-back, 0-value sales, meso cap, `sell_slot`, signals, no 64-bit cost wrap |
| `test_drops_data.gd` | every drop item exists, `DropRates.validate`, labelled placeholders, sources, MSEA/disputed off, overrides win, quest items and Three Snails shells obtainable, meso rules |
| `test_drops_roller.gd` | same seed gives the same drops, membership and quantity bounds, frequencies within 4 sigma of resolved rates (20,000 kills), tutorial shellpiece, Snail meso report, box, global multiplier, rolled drops picked up, ground records (lifetime, owner window, scatter in px and m), canonical pickup box through `WorldScale.actor` |

## Gaps and follow-ups

- **Gender.** `CharacterState` has no gender, so gendered clothes (Pan's tops and bottoms) are wearable by anyone
  until it does.
- **Requirement basis.** Total stats are used, as the brief says. `items.md` calls the fields "minimum base stat".
  Re-check against MeowDB when possible.
- **Not built yet.** Scroll application (failure, slot use), equipment stat variance on drops, recharging, pets and
  pet food, chairs (sitting is another system's job) and quest-gated drops. MeowDB documents none of these.
- **Shop rules live in `inventory.json`.** The `shop` section is there only because this system owns no shop
  adaptation file. It can move to `shop.json`.
