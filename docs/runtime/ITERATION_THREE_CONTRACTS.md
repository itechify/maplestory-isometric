# Iteration Three contracts

These are the interfaces that the parallel Iteration Three work packages build against. Each package works in its own
git worktree, and the packages are merged afterwards, so each must produce and consume exactly what is written here. If
a package must deviate, it records the deviation in its report. Source decisions are in
[`../ITERATION_LOG.md`](../ITERATION_LOG.md) (Phase D3).

## C1. Canonical drop record, schema v2 (`game/data/canonical/drops/<owner id>.json`)

The drops package writes these records with an offline join over the dated captures (`tools/*/captures/`). The data
validators and the runtime drop roller read them. There is one file per owner: the 6 monsters (`1 2 3 4 5 9`) and the
Wooden Box (`0000001`).

```jsonc
{
  "id": "2", "name": "Snail drop table", "schema_version": 2,
  "owner": {"kind": "monster", "id": "2", "name": "Snail"},          // kind: "monster" | "breakable"
  "membership_authority": "Hidden Street",                          // monsters; "MeowDB MS Classic" for the Wooden Box
  "entries": [{
    "key": "snail-shell",                    // stable slug of the membership name
    "name": "Snail Shell",                   // as written by the membership source
    "item_id": "348",                        // local MeowDB item id, or null when unresolved
    "item_resolution": {"state": "resolved", // resolved | ambiguous | not_in_snapshot | not_in_classic
                        "method": "exact",   // exact | normalized | alias_with_evidence | none
                        "candidates": [],    // MeowDB ids considered (ambiguous cases)
                        "note": ""},
    "membership_source": {"authority": "Hidden Street", "url": "...", "read_at": "...",
                          "raw_value": "Etc. drop: Snail Shell"},
    "chance_source": {                      // null when no KuroDB row matches (an unresolved chance)
      "authority": "KuroDB", "url": "...", "read_at": "...",
      "kuro_item_id": "4000019", "kuro_name": "Snail Shell", "match_method": "exact",
      "raw_value": "100% base | Qty 1",
      "format": "percent_base",             // percent_base | reactor_chance_value
      "normalized_probability": 1.0,
      "conversion": "100 / 100",            // or "1 / 4 (interpretation, decision D3-7)"
      "interpretation": null,               // text when the conversion is an interpretation (reactor values)
      "kuro_quest_condition": null          // KuroDB's "| Quest N" flag (e.g. "1035" on Jr. Sentinel Shellpiece),
                                            // or null; recorded as corroboration only, never the gate itself
    },
    "chance_state": "resolved",              // resolved | unresolved
    "probability": 1.0,                      // runtime chance in [0, 1]; null when unresolved
    "quantity": {"min": 1, "max": 1, "source": "KuroDB 'Qty 1'"},   // null when unresolved
    "quest_gate": null,                      // {"quest_id": "1012", "basis": "..."}: rolls only while that MeowDB quest
                                             // is in progress (see the gate rule below)
    "notes": []
  }],
  "excluded_kuro_only": [{"kuro_item_id": "2380000", "name": "Snail Card", "raw_value": "26% base | Qty 1",
                          "reason": "not on the membership list (KuroDB never adds members)"}],
  "meowdb_reference": {"community_drops": [/* MeowDB entries with votes */], "msea_reference": [/* ... */]},
  "meso": {                                  // null for owners that never drop mesos
    "amount_state": "resolved",              // resolved | unresolved
    "min": 2, "max": 2,                      // integers; null when unresolved
    "amount_source": {"authority": "MeowDB MS Classic", "url": "...", "read_at": "...",
                      "raw_value": "Mesos: 2 per kill | 1 report",
                      "interpretation": null},  // e.g. "Hidden Street range 4-6 read as a uniform integer in [4, 6]"
    "chance_state": "resolved", "probability": 0.4,
    "chance_source": {"authority": "KuroDB", "url": "...", "read_at": "...", "raw_value": "40% base | Meso drop",
                      "format": "percent_base", "normalized_probability": 0.4, "conversion": "40 / 100"},
    "discrepancies": [{"authority": "Hidden Street", "raw_value": "Mesos: 1", "note": "MeowDB report kept (D3-5)"}]
  },
  "provenance": {                            // per-property authorities (see C7)
    "membership": {"authority": "Hidden Street", "...": "..."},
    "probability": {"authority": "KuroDB"},
    "mesos.amount": {"authority": "MeowDB MS Classic"},
    "mesos.probability": {"authority": "KuroDB"}
  },
  "source": {/* MeowDB URL of the owner page, as before */}, "field_sources": {}, "gaps": [], "discrepancies": []
}
```

Runtime rule (the drop roller):

- An item entry rolls only when `chance_state == "resolved"`, `item_id != null`, and either `quest_gate == null` or
  the gate quest is in progress.
- The meso bag rolls only when both `amount_state` and `chance_state` are `resolved`. The amount is a uniform integer
  in `[min, max]`.
- An unresolved entry never rolls, and validation lists it.
- **Quest-gate rule** (a MisoStory derivation, recorded with `verified: false`): an entry gets a `quest_gate` only when
  two things hold. First, the membership source, or MeowDB's own item subtype, marks the item as a quest item (MeowDB
  subtype "Quest Item"). Second, a Maple Island quest objective requires that item; the gate is that quest. KuroDB's
  "| Quest N" flag is recorded only as corroboration. Under this rule Old Wooden Board and Rusty Screw (MeowDB "Quest
  Item", required by 1012) are gated to 1012. Jr. Sentinel Shellpiece (MeowDB subtype "Monster Drop", a plain Etc.
  drop on Hidden Street) is **not** gated, even though KuroDB flags it.
- Nothing outside these records may supply a chance, quantity or meso amount. `game/data/misostory/drop_rates.json`
  stops holding placeholder rates; only non-canonical ground rules (lifetime, ownership, scatter) remain, in
  `game/data/misostory/drops.json`.

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
| `natural_recovery` | `{"hp_rest_s": float}`: eligible seconds accumulated toward the next tick, in [0, interval) | mechanics |
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

- `TEST_EVIDENCE_OUT=<file> bash scripts/test.sh ...` makes the unit test runner write
  `{"run_at", "totals", "tests": [{"file", "name", "ok", "parity": [keys]}]}`. A test declares parity keys through
  an optional `func parity_keys() -> Dictionary` in its file, mapping test names to `["quest:1005", ...]`.
- A playtest check may carry `"parity": [keys]`, and `report.json` keeps them.
- Parity keys are `<category>:<id>`, for example `quest:1005`, `monster:2`, `npc:7`, `shop:maple-road-pan`,
  `item:348`, `map:000000010`, `portal:000000010/out00`, `skill:0001000`, `breakable:0000001`,
  `mechanic:natural-hp-regen`, `drop:2/snail-shell` and `chair:522`.
- The parity manifest reads that evidence: `node tools/parity/build_parity.mjs` writes `docs/maple_island_parity.json`
  (`format` 3) and `docs/MAPLE_ISLAND_PARITY.md`. Every entry has a `state` (`missing`, `partial`, `implemented`,
  `verified`; the rule is in `tools/parity/parity.mjs` and the markdown) and two labels that are never set together:
  - `source_data_gap`: the sources were read and do not give a value the entry needs (no KuroDB chance for a member,
    no meso amount, no MeowDB rule). The entry stays `partial` but is excused from the exit criterion.
  - `pending_source_read` (new in format 3): a source publishes the value on a page nobody has read yet. It is not a
    gap and not excused: the entry stays `partial` and open until the page is read and the data regenerated. Such
    reads are declared in `tools/parity/rules.json` `pending_source_reads` (the read, what it resolves, and for a
    record the fields its `gaps` name); a drop record's excluded KuroDB candidate row marks its member pending even
    when undeclared. A declaration the data no longer supports fails the build as stale. Format 3 lists them apart
    (`pending_source_reads`, the entries' `pending_reads`) and counts them per category (`totals.*.pending_source_read`)
    beside `source_data_gaps`.
- Quests, objectives, rewards and chains are verified only by a playtest (real-game) check. The `playthrough:*` rows
  are verified only by checks of a clean-character run: a passing report in strict mode with no console or api step
  that reached the departure boundary (its final boundary check "ready to depart: the End of Maple Island screen
  reached in Southperry" passed, and no `PLAYTHROUGH_STOP` flag); the manifest's "Evidence used" says why a
  playthrough report is not one.

## C7. Provenance authorities

The validators accept these authorities, each with URL and `read_at` rules:

- `MeowDB MS Classic`
- `KuroDB` (`https://playkuro.com/database/#...`, drop and meso probabilities only)
- `Hidden Street` (`https://bc.hidden-street.net/...`, monster drop membership and meso amounts only)
- `Project owner` (the natural-regen rule; owner decisions D3-5 to D3-7)

A record may name a different authority per property, using `provenance.<property>` as in C1. A value from a dated
capture cites the capture's file path under `tools/*/captures/` together with the page URL.

## C8. Breakables

The breakable package places the Wooden Box placements from `maps/<id>.json reactors` (19, with per-placement respawn
seconds) on walkable ground at runtime, the same way monster spawn slots are placed. Interior maps (Amherst Department
Store ×1, Amherst Weapon Store ×2, Amherst Townstreet ×2) have no species-tagged spawn regions. For them, and for any
map whose regions cannot hold a box, the planner samples walkable floor inside the map's footprint and region
extensions, seeded and deterministic per map. It keeps the same clearances as spawn slots (portals and arrivals, NPC
interaction spaces, walls, other placements). This is a recorded MisoStory adaptation (`verified: false`), and every
box position is checked by a physics test. The box breaks after
`hits_to_break` landed hits (4) and drops through `DropRoller.roll("0000001", db, rng, ctx)`. It respawns after its
placement's respawn time, and it is not persisted.
