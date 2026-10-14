# Iteration Three contracts

These are the interfaces that the parallel Iteration Three work packages build against. Each package works in its own
git worktree, and the packages are merged afterwards, so each must produce and consume exactly what is written here. If
a package must deviate, it records the deviation in its report. Source decisions are in
[`../ITERATION_LOG.md`](../ITERATION_LOG.md) (Phase D3).

## C1. Canonical drop record, schema 3 (`game/data/canonical/drops/<owner id>.json`)

`tools/meowdb/extract_monsters.mjs` is the only writer of these records. It builds them offline through
`tools/sources/drops_merge.mjs` from the dated captures (`tools/meowdb/captures/`, `tools/henesys/captures/`) and the
MeowDB cache. The data validators and the runtime drop roller read them. There is one file per owner: the 6 monsters
(`1 2 3 4 5 9`) and the Wooden Box (`0000001`). A record holds only sourced facts: who drops what, which item it is,
its rarity and the inputs of its chance category. It never holds a probability, a quantity or a made-up meso amount.
Those come from the project owner's two rule files (below), which the runtime reads.

```jsonc
{
  "id": "5", "name": "Red Snail drop table", "schema_version": 3,
  "owner": {"kind": "monster", "id": "5", "name": "Red Snail"},      // kind: "monster" | "breakable"
  "membership_authority": "MeowDB MS Classic",
  "membership_list": "Drops (MS Classic)",                           // MeowDB's community list, every entry
  "entries": [{
    "key": "red-cloth-pants",                // stable slug of the name
    "name": "Red Cloth Pants",               // as MeowDB's list writes it
    "item_id": "1168",                       // local MeowDB item id, or null when unresolved
    "item_resolution": {
      "state": "resolved",                   // resolved | ambiguous | not_in_snapshot
      "method": "meowdb_drop_entry",         // exact_name (the one local item with the name) | meowdb_drop_entry
                                             // (several local items share the name; MeowDB's own cached drop entry
                                             // for this owner carries the id) | none
      "candidates": ["1168", "1177"],
      "evidence": "2 local items are named \"Red Cloth Pants\" (1168, 1177); MeowDB's own drop entry ... carries 1168"
    },
    "membership_source": {"authority": "MeowDB MS Classic", "url": "https://meowdb.com/msclassic/monsters/5",
      "read_at": "...", "capture": "tools/meowdb/captures/monster_5.json", "list": "Drops (MS Classic)",
      "list_group": "EQUIPMENT", "raw_value": "Red Cloth Pants\nLv 10 · Thief\n▲\n4\n▼\n0",
      "votes": {"up": 4, "down": 0, "score": 4}},   // recorded only: nothing is excluded for votes
    "rarity": {                              // null when Henesys.gg has no row: the entry stays, unresolved, and never drops
      "label": "Common",                     // Common | Rare | Very Rare | Extremely Rare
      "source": {"authority": "Henesys.gg", "url": "https://henesys.gg/loot", "read_at": "...",
                 "capture": "tools/henesys/captures/item_rarity.json", "row": "Red Cloth Pants | Bottom · Thief | ... | Common"}
    },
    "category_inputs": {"item_type": "Equip", "item_subtype": "Bottom", "quest_gated": false,
                        "item": "game/data/canonical/items/1168.json"},
    "chance_category": "equip",              // the table row (rule below), or null when it cannot be derived
    "quest_gate": null,                      // {"quest_id": "1012", "basis", "rule", "decision": "D3-9", "verified": false}
    "notes": []
  }],
  "meowdb_reference": {                      // monsters: MeowDB's read-only MSEA list, never a member (null for the box)
    "note": "...", "source": {/* the live page */},
    "msea_reference": [{"name": "Overall Armor DEX Scroll: Greater", "category": "USE", "detail": "Scroll", "item_id": "139"}]
  },
  "meso": {                                  // monsters only; null for a breakable (MeowDB has no meso reports for them)
    "amount_state": "not_reported",          // reported | not_reported
    "min": null, "max": null,                // whole numbers when reported (MeowDB's player report), else null
    "amount_source": null,                   // when reported: {authority: "MeowDB MS Classic", url, read_at | retrieved_at,
                                             //  capture?, raw_value: "Mesos: 2 per kill | 1 report", report_count,
                                             //  decision: "D3-12", interpretation}
    "sources_compared": [/* the live page line and the cached report API summary, each with its date */],
    "gaps": ["meso amount: MeowDB has no player meso report ...", "meso chance: MeowDB publishes none ..."]
  },
  "provenance": {                            // per-property authorities (see C7)
    "membership": {"authority": "MeowDB MS Classic", "url": "...", "read_at": "...", "capture": "...", "decision": "D3-11"},
    "rarity": {"authority": "Henesys.gg", "url": "https://henesys.gg/loot", "read_at": "...", "capture": "...", "decision": "D3-11"},
    "mesos.amount": {"authority": "MeowDB MS Classic", "...": "..."}   // only when MeowDB has a report (the Snail)
  },
  "source": {/* MeowDB URL of the owner page */}, "field_sources": {}, "gaps": [], "discrepancies": [], "notes": []
}
```

Build rules (`tools/sources/drops_merge.mjs`, decision D3-11):

- **Membership** is MeowDB's community list "Drops (MS Classic)" for the owner, every entry, in page order. The newest
  dated source wins: the live page captures (`tools/meowdb/captures/monster_<id>.*`, read 2026-10-05; the Wooden Box's
  `breakable_0000001.txt`) over the 2026-10-04 cache; a cache/live difference is a record `discrepancies` row. Of two
  captures of one page the one with the later `read_at` is the page (a tie is an error), and a cache read after the
  capture that names other members stops the build until the page is captured again. The validator holds each record
  to its owner's own page capture, the newest one. MeowDB's "MSEA reference drops" list stays in `meowdb_reference`
  and never adds a member.
- **Item**: the member's name resolves to the one local item with that name. Where several local items share it (Red
  Cloth Pants: 1168 and 1177), the id MeowDB's own cached drop entry for that owner carries decides, and the record says
  so. A member whose cached entry carries a different id than its one local item stops the build, and so does a list
  group (ETC, USE, EQUIPMENT, SETUP) that is not the item's type.
- **Rarity** is Henesys.gg's per-item label from `tools/henesys/captures/item_rarity.json`, matched by MeowDB's name
  (today every name is the same on both sites; a differing name would need a small name map in the builder).
- **Chance category**, from the local item's MeowDB type and subtype and the quest gate:
  `etc_own_leftover` (Etc, subtype "Monster Drop"), `etc_quest_gated` (Etc, subtype "Quest Item", gated by the rule
  below), `etc_other` (any other Etc: ores, gems, Monster Card), `use_consumable` (Use other than "Scroll"),
  `use_scroll` (Use, "Scroll"), `equip` (any Equip), `setup` (any Setup). Another type gets null (never drops).
- **Quest-gate rule** (decision D3-9, a MisoStory derivation recorded with `verified: false`): an entry is gated only
  when its item's MeowDB subtype is "Quest Item" **and** a Maple Island quest objective requires that item; the gate
  is that quest. Old Wooden Board and Rusty Screw are gated to Pio's quest 1012; Jr. Sentinel Shellpiece (MeowDB subtype
  "Monster Drop") is not gated.
- **Mesos**: MeowDB's player report from the newest dated source (the live page's "Mesos: N per kill | K reports"
  line, or the cached report API's summary). When a newer capture or cache gains a report for a monster, the next
  extraction writes it here and the runtime uses it; otherwise `amount_state` is `not_reported`. The validator refuses a
  record that leaves out a report its page capture shows (unless a newer source in `sources_compared` decides).

The project owner's rule files (MisoStory adaptations, `verified: false`):

- `game/data/misostory/drop_rates.json` (decision D3-11): `chance_table[category][rarity]`, a chance in [0, 1] for
  every category x rarity; `quantity_per_drop` 1. The same table applies to the Wooden Box.

  | Category | Common | Rare | Very Rare | Extremely Rare |
  |---|---|---|---|---|
  | `etc_own_leftover` | 100% | 50% | 20% | 5% |
  | `etc_quest_gated` | 100% | 100% | 100% | 100% |
  | `etc_other` | 3% | 1% | 0.3% | 0.1% |
  | `use_consumable` | 2% | 0.5% | 0.1% | 0.02% |
  | `use_scroll` | 0.1% | 0.03% | 0.01% | 0.003% |
  | `equip` | 0.1% | 0.04% | 0.01% | 0.002% |
  | `setup` | 0.05% | 0.02% | 0.005% | 0.001% |

- `game/data/misostory/meso_rules.json` (decision D3-12): the amount is the record's MeowDB report when there is one,
  otherwise a uniform integer in [level x `amount_level_multiplier_min`, level x `amount_level_multiplier_max`] = [level,
  2 x level] of the monster's canonical level; the chance is `chance` (60%) for every monster that drops mesos, also
  one with a MeowDB amount; `no_mesos` lists the owners that never drop mesos (the Tutorial Jr. Sentinel, the owner's
  choice, and the Wooden Box).

Runtime rule (`DropRates` / `DropRoller`):

- An item entry rolls only when `item_id` names a local item, `rarity.label` is one of the four labels, the table has a
  cell for `chance_category` x `rarity.label`, and either `quest_gate == null` or the gate quest is in progress. It rolls
  at that cell's chance, one item per drop.
- An unresolved entry (no item, no rarity or no category) never rolls, and validation lists it as a warning.
- The meso bag rolls at `meso_rules.json` `chance` unless the owner is in `no_mesos`; the amount is a uniform integer in
  [min, max] (the MeowDB report, else the level formula).
- Nothing else supplies a chance, quantity or meso amount: the canonical records hold none, and the validators refuse
  a probability key in them. `game/data/misostory/drops.json` keeps only the ground rules (lifetime, ownership, scatter).

## C2. Drop roll context (quest-gated drops)

```gdscript
DropRoller.roll(owner_id: String, db: ContentDB, rng: RandomNumberGenerator, ctx: Dictionary = {}) -> Array
# ctx = {"quests_in_progress": PackedStringArray}   (CharacterState.quests.active_ids())
```

The monster system and the breakable system both pass the context. If the context is missing, gated entries do not
roll.

## C3. CharacterState fields and the save schema (save_version 2)

The saves package owns `character_state.gd`, `save_migrations.gd` and the v1 → v2 migration. The other packages use
these fields:

| Field | Shape | Owner of the behaviour |
|---|---|---|
| `natural_recovery` | `{"hp_rest_s": float}`: eligible seconds accumulated toward the next tick, in [0, interval). `CharacterState.from_dict` holds a loaded value to that range (`clamp_rest_s`, interval = `recovery.json natural_hp.tick_s`): below 0 or not a number becomes 0, a whole tick or more becomes one tick's worth less `NaturalRecoveryRule.EPSILON_S`, so a hand-edited save pays at most one tick at once | mechanics |
| `skills` | `{skill_id: level}` with canonical ids (`"0001000"` Three Snails, `"0001001"` Recovery, `"0001002"` Nimble Feet) | skills |
| `sp` | int (exists) | skills |
| `cooldowns` | `{skill_id: remaining_s}`: remaining seconds, never absolute clock times | skills |
| `effects` | `[{"id": String, "source": "skill:0001001", "remaining_s": float, "data": {}}]` | skills |
| `quickslots` | `{key: {"kind": "item" \| "skill", "id": String}}`; a v1 bare item id migrates to `{"kind": "item", "id": ...}` | skills (UI) |
| quest entries | gain `"rewards_received": {"exp", "mesos", "items": [{"item_id", "qty"}], "random_picks": [{"group", "item_id", "qty"}]}` at completion; v1 completed entries migrate to `{"recorded": false}`. QuestLog keeps unknown keys on load. | quests |

The seated state is not persisted (the player stands on load). Breakable state, monsters and ground drops are not
persisted either. Each of these has a test that says so.

## C4. Player activity (`PlayerController.activity() -> StringName`)

The activity is one of `&"still"`, `&"walking"`, `&"jumping"` (any airborne state), `&"climbing"`, `&"attacking"` (a
melee swing or a skill cast in progress), `&"seated"`, `&"hitstun"`, `&"dead"` or `&"other"`. The mechanics package
implements it. Natural recovery reads it, and so may skills, the HUD and playtests.

Natural HP recovery (the owner's rule): 10 HP per 10 s of eligible time. Only `still` and `seated` are eligible. Every
other activity **pauses** the clock and never resets it. HP never goes above Max HP. Recovery stops while HP is full
(the clock holds). MP has no natural recovery, because MeowDB documents none.

## C5. Chairs

A chair is any Setup item that has `setup` data (The Green Relaxer, 522). Using one sits the player down: double-click
it in the Set-up tab, bind it to a quickslot, or press X, which sits on the first chair you own (an adaptation).
Sitting is allowed only when the player is grounded, still, alive and has no modal open. Any movement, jump, attack,
skill, knockback, death or warp stands the player up. While seated: natural recovery is eligible, and the chair's own
`setup.hp_recovery_bonus` per `setup.interval_s` is added on a separate clock.

## C6. Machine-readable test evidence

- `TEST_EVIDENCE_OUT=<file> bash scripts/test.sh ...` makes the unit test runner write (format 2)
  `{"run_at", "commit", "dirty", "world_present", "art_pack_present", "totals", "tests": [{"file", "name", "ok",
  "parity": [keys], "needs_world"}]}`. A test declares parity keys through an optional `func parity_keys() ->
  Dictionary` in its file, mapping test names to `["quest:1005", ...]`. `commit` is the checked-out commit and `dirty`
  whether `game/`, `tools/` or `scripts/` held changes or untracked files (`null` when git could not tell);
  `world_present` is whether the run saw the exported world (`INCLUDE_WORLD=1`), `art_pack_present` whether it had the
  art pack (not `NO_ART_PACK=1`); a test `needs_world` when its file names `INCLUDE_WORLD` (it prints SKIP and passes
  without the world), and the parity generator refuses its keys from a run without the world (and from
  older evidence that does not record it).
- A playtest check may carry `"parity": [keys]`, and `report.json` keeps them. `report.json` also records
  `"git": {"commit", "dirty", "mixed", "reused_copy"}` (from `scripts/playtest.sh`: the first phase's commit, whether
  any phase's tree was dirty, whether the phases ran different commits, whether a reused copy was played).
- `tools/parity/build_parity.mjs` warns on the console, never in the manifest, when evidence records no commit or a
  dirty tree, when the evidence commits differ from each other, and when an evidence commit's `game/`, `tools/` or
  `scripts/` tree differs from HEAD's.
- Parity keys are `<category>:<id>`, for example `quest:1005`, `monster:2`, `npc:7`, `shop:maple-road-pan`,
  `item:348`, `map:000000010`, `portal:000000010/out00`, `skill:0001000`, `breakable:0000001`,
  `mechanic:natural-hp-regen`, `drop:2/snail-shell` and `chair:522`.
- The parity manifest reads that evidence: `node tools/parity/build_parity.mjs` writes `docs/maple_island_parity.json`
  (`format` 3) and `docs/MAPLE_ISLAND_PARITY.md`. Every entry has a `state` (`missing`, `partial`, `implemented`,
  `verified`; the rule is in `tools/parity/parity.mjs` and the markdown) and two labels that are never set together:
  - `source_data_gap`: the sources were read and do not give a value the entry needs (no Henesys.gg rarity for a
    drop member, an item no local record has, no MeowDB rule). The entry stays `partial` but is excused from the exit
    criterion.
  - `pending_source_read` (new in format 3): a source publishes the value on a page nobody has read yet. It is not a
    gap and not excused: the entry stays `partial` and open until the page is read and the data regenerated. Such
    reads are declared in `tools/parity/rules.json` `pending_source_reads` (the read, what it resolves, and the record
    fields its `gaps` name). A declaration the data no longer supports fails the build as stale. Format 3 lists them
    apart (`pending_source_reads`, the entries' `pending_reads`) and counts them per category
    (`totals.*.pending_source_read`) beside `source_data_gaps`.
- Quests, objectives, rewards and chains are verified only by a playtest (real-game) check. The `playthrough:*` rows
  are verified only by checks of a clean-character run: a passing report in strict mode with no console or api step
  that reached the departure boundary (its final boundary check "ready to depart: the End of Maple Island screen
  reached in Southperry" passed, and no `PLAYTHROUGH_STOP` flag); the manifest's "Evidence used" says why a
  playthrough report is not one.

## C7. Provenance authorities

The validators accept these authorities, each with URL and `read_at` rules
(`game/scripts/core/validation/provenance_authorities.gd`):

- `MeowDB MS Classic` (`https://meowdb.com/msclassic...`, any property): drop membership, item ids, meso reports and
  every other canonical fact.
- `Henesys.gg` (`https://henesys.gg/...`, the property `rarity` only; `read_at` and `capture` required): the rarity
  label of a drop member, read by hand into `tools/henesys/captures/item_rarity.json` (decision D3-11).
- `Project owner` (no URL; a `decision` required): the natural-regen rule, the drop chance table (D3-11) and the meso
  rule (D3-12).

A record may name a different authority per property, using `provenance.<property>` as in C1; in a drop record the
per-entry sources are `entries[].membership_source` ("membership") and `entries[].rarity.source` ("rarity"), and the
meso block's `amount_source` ("mesos.amount"). A value from a dated capture cites the capture's file path under
`tools/*/captures/` together with the page URL.

## C8. Breakables

The breakable package places the Wooden Box placements from `maps/<id>.json reactors` (19, with per-placement respawn
seconds) on walkable ground at runtime, the same way monster spawn slots are placed. Interior maps (Amherst Department
Store ×1, Amherst Weapon Store ×2, Amherst Townstreet ×2) have no species-tagged spawn regions. For them, and for any
map whose regions cannot hold a box, the planner samples walkable floor inside the map's footprint and region
extensions, seeded and deterministic per map. It keeps the same clearances as spawn slots (portals and arrivals, NPC
interaction spaces, walls, other placements) and needs a clear line toward the gameplay camera, tested against the
collision and against the tree canopies (`breakables.json` `placement.canopies`, a canopy box per tree asset measured
from the export: canopies have no collision). With the canopy rule, Amherst's boxes 000001010:2, :4 and :5 moved to
(257.61, 6.00, 611.37), (214.55, 6.00, 605.54) and (216.34, 6.00, 580.98); the other 16 are unchanged. This is a
recorded MisoStory adaptation (`verified: false`), and every box position is checked by a physics test. The box
breaks after `hits_to_break` landed hits (4 basic attacks; skills never count, the owner's ruling in #5) and drops
through `DropRoller.roll("0000001", db, rng, ctx)`. It respawns after its placement's respawn time, and it is not
persisted.
