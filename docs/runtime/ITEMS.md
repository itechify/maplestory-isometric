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
| `game/scripts/core/items/chairs.gd` | `Chairs` | Using a chair: sit down or stand up through the player (contract C5) |
| `game/scripts/core/items/mesos.gd` | `Mesos` | Meso add/spend rules and the cap |
| `game/scripts/core/items/item_codes.gd` | `ItemCodes` | Result codes and default messages |
| `game/scripts/core/items/item_service.gd` | `ItemService` | The seam: mutates a `CharacterState` and emits `Events` |
| `game/scripts/core/shop/shop_service.gd` | `ShopService` | Buying and selling against canonical shop data |
| `game/scripts/core/drops/drop_rates.gd` | `DropRates` | Reads the canonical drop records (schema 3) and the owner's two rule files: rolling entries and their table chance, quest gates, the meso rule, unresolved members |
| `game/scripts/core/drops/drop_roller.gd` | `DropRoller` | Turns a kill into drops with a seeded RNG and the roll context (quests in progress) |
| `game/scripts/core/validation/drop_checks.gd` | `DropChecks` | The drop policy over the shipped records (data validator) |
| `game/data/misostory/inventory.json` | | Tab sizes, equipment stack size, slots and conflicts, weapon metadata, job tags, meso cap, shop rules |
| `game/data/misostory/drop_rates.json` | | The project owner's drop chance table by item category x rarity, one item per drop, and the quest-gate rule (decision D3-11, `verified: false`) |
| `game/data/misostory/meso_rules.json` | | The project owner's meso rule: MeowDB's report, else [level, 2 x level]; 60%; the owners without mesos (decision D3-12, `verified: false`) |
| `game/data/misostory/drops.json` | | Ground lifetime, owner-only time and drop scatter |

## Data flow

```
data/canonical/items/<id>.json ──► ItemDef ──► Inventory / Equipment / Consumables / ShopService
data/canonical/shops/<id>.json ──────────────────────────────────────► ShopService.stock / buy / sell
data/canonical/drops/<owner>.json (schema 3) + data/misostory/drop_rates.json, meso_rules.json ──► DropRates ──► DropRoller.roll(owner, db, rng, ctx) ──► [{kind, item_id, qty} | {kind: mesos, amount}]
                       ctx = DropRoller.context_for(character) = {"quests_in_progress": character.quests.active_ids()}
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
| Drop records | `data/canonical/drops/*.json` (schema 3, contract C1) | members (MeowDB's community list), their items, Henesys.gg rarity and chance category, quest gates, MeowDB's meso report, owner kind; the chance is `drop_rates.json`'s cell and the meso rule `meso_rules.json` |
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
  full HP is still consumed. Pet Food, scrolls, equipment and Etc items return `not_usable`; so does a chair passed
  to `Consumables.use`, because chairs go through `ItemService.use_item` to `Chairs.use` (below).
- **Chairs** (contract C5). A chair is a Setup item with canonical `setup` data (`ItemDef.is_chair()`: The Green
  Relaxer, 522; the Sky-blue Wooden Chair, 525, is off-island). `ItemService.use_item(chair)` is not consumed: it
  hands the chair to `Chairs.use`, which sits the player down on it, stands it up when it already sits on that chair,
  or moves it over to another chair (`{"action": "sit" | "stand"}`). `Chairs.sit_key` is the X key: stand up, or sit
  on the first chair in the Set-up tab (an adaptation, `recovery.json sitting`). Refusals: `not_enough_items` (not
  owned), `level_too_low`, `dead`, `cannot_sit` (the player is walking, airborne, in a modal or warp), `no_chair`. The
  seated state itself and the chair's bonus clock belong to the player ([PLAYER_AND_CAMERA.md](PLAYER_AND_CAMERA.md)).
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
  from any shop. MeowDB documents no sell restrictions; MisoStory adds one: a shop refuses to buy a quest-critical
  item (a quest item, an untradeable item, or one handed out on accept) below the quantity an in-progress quest still
  needs (`quest_item_needed`, `QuestItemGuard`, `misostory/quests/_quest_items.json`), because selling Roger's Apple
  during 1002 made the quest uncompletable. Tradeable drops stay sellable. Shop equipment is clean (empty instance
  data).
- **Drops.** `DropRoller.roll(owner, db, rng, ctx)` first rolls one meso bag (when the record's meso amount and chance
  are both resolved; the amount is a uniform integer in `[min, max]`), then each rolling entry in the record's order.
  An entry rolls when its chance is resolved and its item is a local item, and, if it has a `quest_gate`, only while
  that quest is in progress (`ctx.quests_in_progress`, contract C2; no context = never). Each rolling entry uses one
  `randf()`, gated or not, and a drop uses a `randi_range` only for a quantity range, so a seed reproduces a kill
  exactly and a quest starting never shifts the other entries' rolls. Drops spawn at death (canonical).
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
| `inventory.json:unpublished_max_stack` | 1 | Fallback for a non-equip item with null `max_stack`: none today (Green Apple, 242, used it until its item page was read: `tools/meowdb/captures/item_242.txt`, Max per Stack 100) |
| `inventory.json:meso_cap` | 2,147,483,647 | No cap documented; signed 32-bit counter limit so mesos cannot overflow |
| `inventory.json:equipment_slots` | 10 brief slots + face/eye accessory, pendant, ring 1-4 | Remaining classic slots, so future content is data only |
| `inventory.json:slot_conflicts` | overall <-> top/bottom, two-handed <-> shield | Classic rules; item pages do not state them |
| `inventory.json:weapon_subtypes` | damage family / multiplier / action-odds keys, `two_handed` | Keys follow `damage.json` labels. Two-handedness is a MeowDB gap: names say "Two-Handed"; Spear, Polearm, Bow, Crossbow, Claw follow the classic client; Wand, Staff are one-handed |
| `inventory.json:job_item_tags` | beginner [], warrior Warrior, magician Mage, bowman Bowman, thief Thief (+ pirate guess) | Transcribed from MeowDB's character-builder code in `beginner.json` |
| `inventory.json:shop.sell_zero_value_items` | true | MeowDB does not say whether NPCs refuse 0-value items; MisoStory takes them for 0 |
| `inventory.json:shop.max_bundles_per_purchase` | null (no limit) | MeowDB documents no per-purchase cap |
| `drop_rates.json:chance_table` | the owner's table, category x rarity (below) | MeowDB publishes no drop chance; Henesys.gg gives only a rarity label per item (decision D3-11) |
| `drop_rates.json:quantity_per_drop` | 1 | No source gives a drop quantity (D3-11) |
| `drop_rates.json:quest_gate_rule` | the C1 gate rule (D3-9) | MeowDB does not say who may loot a quest item |
| `meso_rules.json` | MeowDB's report, else uniform integer in [level, 2 x level]; chance 0.6; none for the Tutorial Jr. Sentinel and the Wooden Box | MeowDB has one meso report (the Snail) and no meso chance (decision D3-12) |
| `drops.json:ground_lifetime_s` | 180 | Undocumented; commonly remembered classic value |
| `drops.json:owner_exclusive_s` | 15 | Ownership exists (formulas/pets) but its duration is undocumented |
| `drops.json:scatter_spacing_px` | 25 | Drop spacing is undocumented |

### Drop rates (canonical records and the owner's rule files, contract C1)

The canonical drop record, `data/canonical/drops/<owner>.json` (schema 3; field reference in
[`../canonical/monsters.md`](../canonical/monsters.md#drops-schema-3-records)), says who drops what and how rare each
item is; it holds no probability. The chance and the meso rule are the project owner's two rule files, MisoStory
adaptations (`verified: false`) the owner can tune cell by cell. `DropRates.validate` holds both files complete and in
range (the data validator reports a broken file as a `drop_policy` error through `DropChecks`), and a table that is not
schema 3 rolls nothing.

| Property | Source |
|---|---|
| Members (what can drop) | MeowDB's community list "Drops (MS Classic)" for the monster or the Wooden Box, every entry (decision D3-11) |
| Rarity | Henesys.gg's per-item label (Common, Rare, Very Rare, Extremely Rare), in the record (D3-11) |
| Chance | `drop_rates.json` `chance_table[chance_category][rarity]`, the owner's table (D3-11); one item per drop |
| Meso amount | MeowDB's player report where there is one (the Snail: 2), else a uniform integer in [level, 2 x level] (`meso_rules.json`, D3-12) |
| Meso chance | `meso_rules.json` `chance`, 0.6; none for the Tutorial Jr. Sentinel and the Wooden Box (D3-12) |

| Category (`chance_category`) | Common | Rare | Very Rare | Extremely Rare |
|---|---|---|---|---|
| `etc_own_leftover` (Etc, MeowDB subtype "Monster Drop") | 1.0 | 0.5 | 0.2 | 0.05 |
| `etc_quest_gated` (Etc, "Quest Item", gated by D3-9) | 1.0 | 1.0 | 1.0 | 1.0 |
| `etc_other` (other Etc: ores, gems, Monster Card) | 0.03 | 0.01 | 0.003 | 0.001 |
| `use_consumable` (Use: potions, food, arrows) | 0.02 | 0.005 | 0.001 | 0.0002 |
| `use_scroll` (Use, "Scroll") | 0.001 | 0.0003 | 0.0001 | 0.00003 |
| `equip` (any Equip) | 0.001 | 0.0004 | 0.0001 | 0.00002 |
| `setup` (chairs) | 0.0005 | 0.0002 | 0.00005 | 0.00001 |

`DropRates.effective_entries(owner, db)` gives one row per member: `{key, name, item_id, chance, min_quantity,
max_quantity, quest_gate, excluded, source, item_state, rarity, category}`; `source` says where the chance came from
(`"drop_rates.json equip x Common = 0.001 (D3-11)"`). A member whose item, rarity or category is unresolved has
`chance` 0 and `excluded` = `unresolved_item` / `unresolved_rarity` / `unresolved_category` (or `unknown_item`,
`no_table_chance`); it never rolls. `DropRates.unresolved(owner, db)` lists them (the data validator reports each as
a `drop_unresolved` warning). `DropRates.meso_rule(owner, db)` returns `{chance, min, max, source, excluded,
amount_kind}`, `amount_kind` being `meowdb_report` or `level_formula`.

What rolls today (per kill; all 86 members resolve, all Common except one Rare scroll): every monster drops its own
leftover (Snail Shell, Blue Snail Shell, Mushroom Spore, Red Snail Shell, Orange Mushroom Cap, Jr. Sentinel
Shellpiece) at 1.0; the ores, gems and Monster Card on its list at 0.03; Red Potion and the two arrow bundles at 0.02
(not the Sentinel); Overall Armor DEF Scroll: Intermediate (Red Snail, Rare) at 0.0003; each listed equip at 0.001; a
meso bag at 0.6 (not the Sentinel): 2 mesos from the Snail (MeowDB), [2, 4] Blue Snail, [3, 6] Shroom, [4, 8] Red
Snail and [8, 16] Orange Mushroom. The Wooden Box drops Apple and Egg at 0.02 and, while Pio's quest 1012 is in
progress, one Old Wooden Board and one Rusty Screw every time.

**Quest-gated drops.** An entry with `quest_gate` rolls only while that quest is in progress (C1 rule, D3-9:
`drop_rates.json quest_gate_rule`). The monster system passes `DropRoller.context_for(character)`; a breakable must do
the same. Old Wooden Board and Rusty Screw are gated to 1012; the Jr. Sentinel Shellpiece is not.

**Quest items are always obtainable.** `test_quest_items_are_obtainable` derives every item a Maple Island quest asks
for from `quests/*.json` (minus items handed out on accept) and requires a rolling source while that quest is in
progress, or a shop. The validator also treats an unresolved member that a quest needs as a progression blocker when
no other drop record, shop or quest gives the item ([DATA_VALIDATION.md](DATA_VALIDATION.md#progression-blockers)).

The debug console's `drops <monster|owner id> [kills] [seed]` simulates kills under the character's quests in progress
and prints each member's observed and configured rate, its source and why a member never rolls.

## Result codes

Every operation returns `{"ok": bool, "code": String, ...details}`. `ItemCodes.message(result)` gives a default
English line. The codes are:

| Codes | Operations |
|---|---|
| `ok`, `unknown_item`, `invalid_quantity` | all |
| `inventory_full`, `not_enough_items` | inventory |
| `insufficient_mesos`, `meso_cap` | mesos |
| `unknown_shop`, `not_sold_here`, `citizenship_required`, `no_sell_price`, `zero_value_refused`, `quest_item_needed` | shops |
| `not_equipment`, `unknown_slot`, `slot_empty`, `level_too_low`, `job_mismatch`, `stat_too_low`, `fame_too_low`, `gender_mismatch` | equipment |
| `not_usable`, `dead` | consumables |
| `cannot_sit`, `no_chair` (and `not_enough_items`, `level_too_low`, `dead`) | chairs |

Details carry the relevant numbers, for example `stat_too_low {stat, required, actual}` and buy
`{cost, units, mesos}`.

## Testing

```bash
ISOLATE=items bash scripts/test.sh inventory equipment consumable shop drop mesos chairs   # items, shops, drops, chairs
ISOLATE=items bash scripts/validate_data.sh                                          # data convention + references + drop policy
node --test tools/sources/test/                                                      # the drop record builder against the captures
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
| `test_shop_quest_items.gd` | the sell guard (a quest item an in-progress quest still needs is refused, and says why; the rest sells) and Roger's re-issue of a lost apple during 1002 |
| `test_chairs_use.gd` | chairs are the Setup items with setup data; the canonical bonus; the first chair in slot order; the refusals; use sits and stands; a quickslot-bound chair sits the live player (PLAYER_AND_CAMERA.md) |
| `test_drops_data.gd` | every monster has its record, every record schema 3 and through the drop policy, every member's item exists or is unresolved, both rule files complete labelled adaptations, every rolling chance the table cell, the rolling members per owner, an edited table cell reaches the runtime unchanged, quest items (under their quest) and Three Snails shells obtainable, the meso rule (MeowDB's report, else the formula) |
| `test_drops_roller.gd` | same seed gives the same drops (with and without a quest context), only rolling entries drop, unresolved members never do, Board and Screw only during 1012 (and the gate costs its roll), tutorial shellpiece every kill, meso amounts from MeowDB or the formula over [min, max], a newer MeowDB report replaces the formula, box never drops mesos, an older schema supplies nothing, rolled drops picked up, ground records (lifetime, owner window, scatter in px and m), canonical pickup box through `WorldScale.actor` |
| `test_drop_sources.gd` | against the captures themselves: membership is exactly MeowDB's community list on the owner's newest page capture, no MSEA-only item is a member, every rarity is the Henesys.gg capture's label, every category follows the rule, Red Cloth Pants is MeowDB's own item 1168; corrupted records fail `DropChecks` (a member removed or added, an MSEA item, a wrong rarity or category, another owner's page, an older capture, a dropped meso report, an incomplete chance table); a quest item that never rolls is a progression blocker unless another drop record (a monster or a Wooden Box), a shop or another quest gives it |
| `test_drop_simulation.gd` | 120,000 seeded kills per owner: each observed rate within 5 sigma of the table's chance, the box with and without quest 1012, meso bag rate and uniform amounts (a sanity check, never a source) |

## Gaps and follow-ups

- **Gender.** `CharacterState` has no gender, so gendered clothes (Pan's tops and bottoms) are wearable by anyone
  until it does.
- **Requirement basis.** Total stats are used, as the brief says. `items.md` calls the fields "minimum base stat".
  Re-check against MeowDB when possible.
- **Not built yet.** Scroll application (failure, slot use), equipment stat variance on drops, recharging, pets and
  pet food. MeowDB documents none of these. Chairs work (above).
- **The Green Relaxer can be sold.** The sell guard holds only what an in-progress quest needs, and no quest needs
  the chair after 1012; whether to protect it (untradeable, not obtainable again) is an owner decision.
- **A chair refused for level** reads "You need to be level N to equip that." (`MisoUiText.result_message` words
  `level_too_low` for equipment); only 525, an off-island chair, has a level requirement.
- **Unresolved drops.** None today: all 86 drop members resolve. A member that stops resolving never rolls until a
  source resolves it (see [`../canonical/monsters.md`](../canonical/monsters.md#drops-schema-3-records)); the
  validator lists each one.
- **Shop rules live in `inventory.json`.** The `shop` section is there only because this system owns no shop
  adaptation file. It can move to `shop.json`.
