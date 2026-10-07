# Quests, NPCs and dialogue (Iterations Two and Three)

This covers the quest framework (brief Phase 16, "Quest Data Authority", "One Authentic Maple Island Quest"), the
NPC framework (Phase 14, the pure part), the dialogue engine (NPC Interaction, Dialogue UI data) and the data side of
the quest UI (Phase 17). Everything here is pure `RefCounted` code in `game/scripts/core/{quests,npcs,dialogue}/`:
no scene tree. Content is data only. No code path names a quest or an NPC, so a new quest needs only its canonical
record and, if MeowDB has a gap, an adaptation file.

Iteration Three added (contract C3 and the quests package of the Iteration Three brief):

- **QuestLog format 2**: every completion records `rewards_received` (the EXP, mesos and items actually given and
  the random draws); format 1 loads, and unknown keys and unreadable entries survive a load and a save.
- **The Quest Log for the whole island**: chain progression ("Mai's Training 2/3"), the start and turn-in NPCs with
  their maps, MeowDB's `missable` tag, the random reward received, and "Return to X" only for an NPC already met.
- **Shanks' departure boundary**: the canonical route (Lith Harbor, 300 mesos, level 7) is offered and checked, the
  unfinished Maple Island quests are listed under the guide's own advice, and boarding records
  `flags.maple_island_departure_ready_at` and shows the end-of-island screen (no travel, no fare).
- **Quest-critical items**: a shop refuses to buy a quest item an in-progress quest still needs; Roger re-issues a
  lost Roger's Apple.
- **Dialogue rules as data**: `data/misostory/dialogue/_rules.json` records the rules MeowDB does not give (which
  On accept line is the Yes/No, the default-talk line, the quiz retry, the shop window title).

```
data/canonical/quests/<id>.json ─┐                         data/canonical/npcs/<id>.json ─┐
data/misostory/quests/<id>.json ─┴─ QuestCatalog → QuestDef  data/misostory/npcs/<id>.json ─┴─ NpcCatalog → NpcDef
                                          │                                                        │
CharacterState.quests (QuestLog) ── QuestEngine (pure rules, returns results + effects) ◄──────────┤
                                          │                                                        │
Events bus ◄──► QuestService (Events in → hooks; effects → Events out)                              │
                                          │                                                        │
data/misostory/dialogue/<npc>.json ── NpcDialogueBuilder → DialogueGraph ── DialogueRunner + DialogueContext
                                                                                   │
                                                          NpcInteraction (talk / press / choose → VIEW for the UI)
```

## Files

| File | Class | Role |
|---|---|---|
| `scripts/core/quests/quest_log.gd` | `QuestLog` | per-quest state, saved inside `CharacterState` (contract: `to_dict`, `static from_dict`) |
| `scripts/core/quests/quest_def.gd` | `QuestDef` | one quest normalized from canonical + adaptation |
| `scripts/core/quests/quest_catalog.gd` | `QuestCatalog` | all quests, lookups by NPC, quest data validation |
| `scripts/core/quests/quest_engine.gd` | `QuestEngine` | availability, accept, progress hooks, completion, rewards, forfeit, NPC markers, journal |
| `scripts/core/quests/quest_service.gd` | `QuestService` | Events ⇄ engine seam, debug console commands |
| `scripts/core/quests/quest_json.gd` | `QuestJson` | null-safe JSON readers (JSON numbers are floats, nulls are common) |
| `scripts/core/quests/quest_item_guard.gd` | `QuestItemGuard` | which quest-critical items an in-progress quest still needs (the shop's sell guard) |
| `scripts/core/npcs/npc_def.gd`, `npc_catalog.gd` | `NpcDef`, `NpcCatalog` | NPC identity, relationships, behaviours, validation |
| `scripts/core/npcs/npc_interaction.gd` | `NpcInteraction` | talk to an NPC: builds and runs its conversation, routes actions through `QuestService` |
| `scripts/core/npcs/npc_transport.gd` | `NpcTransport` | canonical transport routes, the departure boundary, boarding (`depart`), the unfinished-quest text |
| `scripts/core/dialogue/dialogue_graph.gd` | `DialogueGraph` | branching dialogue format, override merge, validation |
| `scripts/core/dialogue/dialogue_context.gd` | `DialogueContext` | conditions and actions |
| `scripts/core/dialogue/dialogue_runner.gd` | `DialogueRunner` | runs a graph, history for Back, produces UI views |
| `scripts/core/dialogue/dialogue_text.gd` | `DialogueText` | line references → UI text segments |
| `scripts/core/dialogue/npc_dialogue_builder.gd` | `NpcDialogueBuilder` | generates every NPC's conversation from canonical data |
| `data/misostory/quests/1002.json` | | Roger's Apple hand-out and its re-issue when lost (adaptations) |
| `data/misostory/quests/_quest_items.json` | | the sell guard for quest-critical items (adaptation) |
| `data/misostory/dialogue/_system.json`, `16.json`, `20.json`, `21.json` | | system lines (incl. the quest card's offer prompt and the transport lines); shop greetings |
| `data/misostory/dialogue/_rules.json` | | the dialogue rules MeowDB does not give: offer prompt, default talk, quizzes, shop title |
| `data/misostory/dialogue/15.json` | | Shanks' greeting: his canonical speech-bubble line 1 |
| `data/misostory/dialogue/18.json` | | Pio: live item counters in 1012's accept line |
| `data/misostory/npcs/15.json` | | Shanks' departure boundary (no travel, no fare, the flag, the warning's quest region) |
| `data/misostory/npcs/_speech_bubbles.json` | | speech-bubble timing (the presentation side is in INTERACTION_AND_NPC_UI.md) |

A file whose name starts with `_` in `misostory/quests`, `misostory/npcs` or `misostory/dialogue` is a shared table,
not an adaptation of one quest or NPC; the catalog validations skip it (as `AdaptationChecks.SHARED_TABLE_PREFIX`).

## Wiring it into the game (wave 2)

In the `Game` autoload (`scripts/autoload/game_state.gd`), once, after `character` exists:

```gdscript
var quests: QuestService
var npc_talk: NpcInteraction

func _ready() -> void:
	rng.randomize()
	quests = QuestService.create(Events, Data.db, character, rng, func() -> float: return clock)
	quests.character_provider = func() -> CharacterState: return character   # follows new game / load
	quests.attach()                                                          # connects the input signals
	quests.register_debug_commands(Debug)                                    # optional
	npc_talk = NpcInteraction.new(quests)
```

The NPC actor calls `Game.npc_talk.talk(npc_id)` when the player presses interact. The dialogue UI renders the
returned VIEW (or listens to `npc_talk.view_changed`) and calls `npc_talk.press("next" | "ok" | "back" | "yes" |
"no" | "end")` or `npc_talk.choose(choice.index)`. The shop UI connects
`npc_talk.shop_requested(shop_id, npc_id)`, and the shell's `DepartureScreen` connects
`npc_talk.departure_requested(npc_id, departure)`. Quest markers come from `npc_talk.marker(npc_id)`, and the quest
window from `Game.quests.engine.quest_summaries()`.

**Events.** In: `monster_killed`, `item_used`, `item_gained`, `item_lost`, `npc_talked`, `map_entered`. Out:
`quest_started`, `quest_progressed`, `quest_completed`, `quest_forfeited`. A quest also causes changes, and
`QuestService` announces those too, because `QuestEngine` and `Progression` are pure and nobody else would:
- `item_gained` / `item_lost` / `inventory_changed`: accept items, hand-ins and rewards.
- the EXP reward exactly as `Game.gain_exp()` announces EXP: `exp_gained(exp_added, "quest:<id>")`, one
  `leveled_up(level)` per level gained (in order), `hp_changed` / `mp_changed` with the derived maxima after a
  level-up (Progression raises base max HP/MP and the level-up heal applies), and `stats_changed`.
- `mesos_changed(mesos, delta)`.
- `inventory_full(item_id)`, when an accept or turn-in is refused because the inventory is full.

`NpcInteraction.talk()` emits `npc_talked(npc_id)` and `dialogue_opened(npc_id)`. The end of the conversation emits
`dialogue_closed(npc_id)`.

The consumable system must emit `item_used(item_id)` (its `ItemService.use_item` already does). The combat system
must emit `monster_killed(monster_id, map_id)`.

## Quest data and rules

`QuestDef` is built from `game/data/canonical/quests/<id>.json` (see `docs/canonical/quests.md`) plus
`game/data/misostory/quests/<id>.json`:

- **Availability** (`availability(id)` → `{ok, reasons}`):
  - not in progress, and not completed unless `repeatable`;
  - `min_level` (0 = none); `max_level` (null = none);
  - `job_restriction` (null = any job; a display name like "Beginner" matches the character's slug through
    `formulas/<slug>.json` `name`);
  - every `prerequisites.quests` entry completed;
  - `prerequisites.items` held, `must_not_have_items` not held, `fame_min`, `acceptance_meso_cost`.
  - Prerequisite kinds the engine cannot evaluate (`skills`, `citizenship`, `unresolved`) make the quest
    unavailable, and validation reports them.
- **Accept** (`accept(id, at_npc_id)`): the quest must be available, and the NPC must be the start NPC when given.
  - The accept items are canonical `items_given_on_accept`, plus the `next_quest_grants` other quests list for this
    one (merged without granting an item twice), plus the adaptation's `accept_items`.
  - All of them must fit (`Inventory.can_add_all`). Otherwise the accept is refused (`inventory_full`) and nothing
    changes.
- **Objectives** (`objective_status(id)`), one row per objective, `key` = `<kind>:<id>`:
  - `monster_kills`: counted by `on_monster_killed`, only while in progress, capped at the required count.
  - `item_collection`: the live `Inventory.count`, as in classic. Nothing is stored.
  - `item_usage`: counted by `on_item_used`.
  - `npc_talk`: purpose `turn_in` is the talk to the end NPC. It is satisfied by completing at that NPC, and it is
    recorded by `on_npc_talk` only once every other objective is done (the "use the apple, then talk to Roger"
    order).
  - `map_visit`: `on_map_entered`.
  - `other`: only `quiz` is supported. It is satisfied by a correct answer graded against canonical
    `correct_choice_index`. Any other `other` type never passes, and `QuestCatalog.validate()` reports it.
- **Complete** (`complete(id, {at_npc_id, quiz_choice, selection_index})`). Before changing anything it checks:
  - the quest is in progress and the NPC is the end NPC;
  - the quiz answer (when given) and every objective;
  - the rewards it rolls: one item per `rewards.random` group (weighted by MeowDB `chance_pct`, drawn with the
    engine's injected RNG) and the player's pick for `rewards.selection`;
  - that every reward item fits (`Inventory.can_add_all`). If not, the completion is refused and nothing changes.
    A quiz answer graded in the same call is undone on any refusal (an answer from an earlier `answer_quiz` call is
    kept), so a full inventory never leaves the quiz marked answered.
  - The space check runs before the hand-ins are removed, as in classic. No Maple Island quest takes and gives items
    in the same inventory tab, so this never refuses a completion that would have fit.

  Then it removes `items_removed_on_completion` and grants EXP (`Progression.gain_exp`), mesos (`Mesos.add`, which
  respects the meso cap), fame and items, and marks the quest completed at `clock()`, recording what it actually
  gave in the log (`rewards_received`, see below). Follow-ups unlock through their own prerequisites and are listed
  in `followups_available`. They are not auto-started (see Adaptations). The result's `random_picks` rows are
  `{group, item_id, count}`; `group` is the index of the draw's group in the canonical `rewards.random` list.
- **Forfeit** (`forfeit(id)`): progress is dropped, and accept items still held are taken back, up to the amount
  given; the quest can then be accepted again from its start NPC. The player forfeits from the Quest Log (owner
  ruling #10): an in-progress quest has a Forfeit button (or Delete), a confirmation asks first, and confirming calls
  `QuestService.forfeit`, the path the debug console's `quest forfeit` takes (UI.md "Quest Log"). A lost Roger's
  Apple is still re-issued by Roger, so 1002 never needs a forfeit.
- **Lost items** (`lost_items`, `reissue_lost_items`): an accept item is lost when an unfinished objective still
  needs it and it is no longer held. That is MeowDB's "If you lost the items" branch. `QuestDef.reissues_lost_items()`
  is true when the record has that branch or the adaptation sets `reissue_lost_accept_items` (1002: MeowDB has no
  branch, see Adaptations).
- **Quest-critical items** (`QuestItemGuard.needed(character, item_id, db)`): how many of an item the in-progress
  quests still need it to keep, for the shop's sell guard. An item counts when an unfinished objective names it
  (item_collection: the count; item_usage: the uses left) and it is quest-critical (canonical `quest_item`, or
  `tradeable: false`, or handed over by that quest on accept). `ShopService.quote_sell` refuses a sale that would go
  below it with `ShopService.QUEST_ITEM_NEEDED` ({quest_id, quest_name, needed}); the shop window says
  "Roger's Apple is needed for Roger's Apple (keep 1). The shop will not buy it while the quest is in progress."
  The switch is `data/misostory/quests/_quest_items.json`. The Green Relaxer (1012's reward) is not a quest item once
  1012 is done; it is held by the shops' own protected list instead (`protected_item`, ITEMS.md).
- **Unfinished quests** (`unfinished_quests(region)`): the quests of a canonical region ("Maple Island", the record's
  `region`) not yet completed; Shanks' warning lists them (see Transport).
- **Results.** Every mutating call returns `{ok, reason, quest_id, effects, ...}`. `effects` is the ordered list of
  changes (`quest_started`, `item_gained`, `exp_gained`, ...); `QuestService.dispatch` turns them into Events.
  The failure reasons are listed in the `QuestEngine` class comment.
- **UI queries**:
  - `npc_marker(npc_id)` returns `"completable" | "available" | "in_progress" | ""`, and `npc_entries(npc_id)`
    returns the entries behind it.
  - `quest_summary(id)` and `quest_summaries([statuses])` give the name, status, journal text, objective rows
    (current/required/done), `can_complete`, the start and end NPC with their canonical map names
    (`start_npc_name`, `start_map_name`, `end_npc_name`, `end_map_name`), `min_level`, `missable`, `chain` and the
    log's `rewards_received` / `rewards_recorded`.
  - `chain_info(id)`: `{name, position, total, steps: [{quest_id, name, status}]}` from the canonical `quest_line`,
    or `{}` for a standalone quest. The name is the quest's `quest_group`, or the first step's that has one (1006 has
    none; its chain is "Mai's Training"). The five chains: Sera's Mirror (1000-1001), Nina and Sen's Dinner Menu
    (1003-1004), Mai's Training (1006, 1009, 1010), Please bring this letter to Lucas (1007-1008), Rain's Maple Quiz
    (1013-1019).
  - `npc_met(npc_id)`: the player has dealt with that NPC through a quest (it started a quest that is in progress or
    done, or ended a completed one). `objective_status` adds it to npc_talk rows as `met`, and the quest log writes
    a turn-in row as "Return to X" only when `met`, else "Talk to X" (1006 sends a new Beginner to Mai: "Talk to
    Mai"; 1001 sends them back to Heena: "Return to Heena").
  - `journal_text(id)`: line 1 is shown when the quest is available, the middle lines while in progress, and the
    last line once completed.
- **Missable.** `QuestDef.missable` reads the record's `missable` (a flag, or a sourced `{"value": ...}` object; false
  when absent). MeowDB's live quest tracker tags every Maple Island quest "Missable"; the provenance step records it,
  and the quest log shows the tag without interpreting it.

### QuestLog (save format)

```json
{"format": 2, "quests": {
  "1006": {"status": "in_progress",
    "progress": {"kills": {"2": 4}, "used": {}, "talked": [], "visited": [], "other": {}},
    "started_at": 12.5, "completed_at": -1.0, "completions": 0},
  "1008": {"status": "completed", "progress": {...}, "started_at": 3.0, "completed_at": 90.0, "completions": 1,
    "rewards_received": {"exp": 50, "mesos": 0, "items": [{"item_id": "713", "qty": 1}],
      "random_picks": [{"group": 0, "item_id": "713", "qty": 1}]}}}}
```

- A quest with no entry is `not_started`.
- `started_at` / `completed_at` are game-clock seconds (`Game.clock`); -1 means never.
- `rewards_received` (contract C3) is what the last completion actually gave: the EXP and mesos added (less than the
  reward only at a cap), every item granted (fixed, random and selected) and the weighted draws (`group` = index into
  the canonical `rewards.random`). A completion this build did not see (a format 1 save, or `QuestLog.complete`
  called without rewards) is `{"recorded": false}`; `rewards_recorded(id)` tells them apart. The quest log shows
  "Received: Green Headband" for a recorded random reward.
- `from_dict` wraps JSON floats back into ints and turns `{}` into an empty log. It reads format 1 (a completed
  entry without `rewards_received` gains `{"recorded": false}`; a record the save migration already wrote is kept)
  and keeps every key it does not know: at the top of the log, in an entry, in `progress` and in `rewards_received`.
  An entry it cannot read (an unknown status, a `not_started` entry, a non-dictionary) is not played but kept in
  `unread_entries`; an entry this build writes for that quest replaces it. `to_dict` writes all of them back, so a
  save from a newer build survives this one.

## NPCs

`NpcCatalog.new(db).get_def(id)` → `NpcDef`. Its fields:
- `name`, `map_id`, `position_px` (canonical px; the 3D placement comes from Blender markers);
- `roles`, `function_title`, `quests_started`, `quests_completed`, `shop_id`, `transport`;
- `dialogue_lines`, `idle_chatter` (`idle_line(i)` for speech bubbles);
- `portrait`, `visual`;
- `behaviors`, in a fixed order: `quest`, `shop`, `transport`, `talk`. These are derived from the data, because
  MeowDB has no interaction-type field.

`data/misostory/npcs/<id>.json` may set `portrait` (default `npc_<id>`), `visual` (free-form hints for the actor
layer), `disabled_behaviors` and `departure` (below). Every such file needs a top-level `reason` and `verified`.

### Transport and the departure boundary (Shanks)

`NpcTransport` reads an NPC's canonical `transport.routes` (Shanks, npc 15: Southperry 000000060 → Lith Harbor
010000000, `fare_mesos` 300, `min_level` 7, `one_way`, and the beginner guide's `source_quote`). Victoria Island is
not built, so a route only works at a **departure boundary**, the adaptation block in `misostory/npcs/<id>.json`:

```json
"departure": {"boundary": true, "charge_fare": false, "flag": "maple_island_departure_ready_at",
              "unfinished_quests_region": "Maple Island", "reasons": {...}, "verified": false}
```

`NpcTransport.depart(engine, npc_id, route)` re-checks the canonical level and fare (fails `level_too_low`,
`not_enough_mesos`; `no_route`; `not_built` when the NPC has no boundary), spends the fare only when `charge_fare`
(Maple Island: no), sets `character.flags[flag]` to the game clock, and returns the effect
`{"type": "departure_requested", npc_id, route_index, route, flag, at, fare_charged, region, unfinished_quests}`.
`NpcInteraction` re-emits it as `departure_requested(npc_id, departure)`; the shell's `DepartureScreen` shows "End of
Maple Island" (INTERACTION_AND_NPC_UI.md). The character stays in Southperry. `NpcCatalog.validate()` reports an
NPC whose transport is enabled without a boundary.

## Dialogue

**Format** (`DialogueGraph`). The graph is `{id, npc_id, start, nodes}`. Node types:
- `say`: a line with Next, or OK at the end;
- `yes_no`;
- `menu`: multiple choice; choices can carry a `condition`. `auto_single` takes a lone visible choice without
  showing the menu, and `empty_next` is used when no choice is visible;
- `branch`: conditional routing, never shown;
- `action`: side effects, never shown; `on_fail` routes by failure reason;
- `end`.

Display nodes never run actions, and running any action clears the Back history, so Back can never undo an
accept or a hand-over.

**Text.** Nodes store a line reference, not text:
- `{"quest", "section", "branch"?, "line"}`;
- `{"quest", "quiz": "question" | "choice" | "wrong" | "right", "line"?}`;
- `{"quest", "journal"}`, `{"quest", "name": true}`;
- `{"npc", "field": "dialogue" | "idle_chatter", "line"}`;
- `{"npc", "route": i, "quote": true}`: the canonical `source_quote` of an NPC's transport route (Shanks' guide
  sentence);
- `{"system": key}`, optionally with `"args": {name: value}` (fills `{name}` placeholders in the system text: the
  canonical destination, fare and level of a route), `"args_source"` (appended to the source) and
  `"live": {name: {"type": "unfinished_quests", "region"}}` (args the runner fills from the character when the line is
  shown, `DialogueContext.live_value`; without a running conversation the `{name}` placeholder stays, so validation
  still resolves the line);
- `{"parts": [line spec, ...]}`: several lines on one page, one paragraph each (a blank line between them);
  the source is the parts' sources joined with ` + `. Validation checks every part, so a dead part is reported even
  though the others still show. `counters` go on the `parts` line itself (they index the joined segments, with one
  paragraph-break segment between parts); counters on a part are never applied, and validation reports them;
- or literal `{"text", "source"}`.

Any line spec may add `"counters": [{"segment", "item_id"}]`: those segments of the resolved line show the live
inventory count of the item (`DialogueText.apply_counters`, applied by the runner on every view). It exists for
MeowDB lines that render an in-game counter as a literal (1012's "Rusty Screw 0/3", `docs/canonical/quests.md` §10).
Validation fails when a counter segment is out of range or not a number, so a data refresh that moves the segments
is caught.

Canonical text therefore stays MeowDB's verbatim and keeps its provenance (`view.source`). `DialogueText`
normalizes both canonical segment styles into UI segments:
`{"text", "bold", "color": "" | "red", "ref"?: {"kind", "id", "known"}, "icon"?: {"kind": "item", "id", "icon_key"}}`.

**Conditions:**
- `quest_status`, `quest_available`, `quest_ready` (ready to turn in here, quiz pending), `quest_can_complete`,
  `quest_items_lost`;
- `objective` (`kind`, optional `id`, `done`);
- `level` (min/max), `job`, `item_count`, `flag` (`CharacterState.flags`), `mesos`;
- `unfinished_quests` (`region`): a quest of that canonical region is not completed;
- `all` / `any` / `not`.

**Actions:**
- `accept_quest`, `complete_quest` (with optional `quiz_choice` / `selection_index`), `answer_quiz` (`choice`:
  grades the answer without completing; fails with `wrong_answer`), `forfeit_quest`, `reissue_quest_items`;
- `open_shop`: an `open_shop` effect, which `NpcInteraction` turns into `shop_requested`;
- `give_item`, `take_item`, `set_flag`;
- `depart` (`route`): `NpcTransport.depart`; its `departure_requested` effect becomes
  `NpcInteraction.departure_requested`.

**VIEW** (`DialogueRunner.view()`, returned by every `NpcInteraction` call):
`{open, node_id, type, npc_id, speaker_id, speaker_name, portrait, speaker_kind: npc|system|journal, title (quest
name), text, segments, source, choices: [{index, text, segments, quest_id, tag}], buttons}`. `buttons` is a subset
of `back`, `next`, `ok`, `yes`, `no` and `end`.

**Generated conversations** (`NpcDialogueBuilder`, node ids in its class comment). Which quests an NPC starts and
ends comes from the quest records (the same lookups as `npc_marker`), so a quest added as data is offered even
before the NPC record lists it; `NpcCatalog.validate()` reports such a mismatch, and `disabled_behaviors: ["quest"]`
switches quest entries off. When the player talks to an NPC, these entries are evaluated live:
- the turn-in of an in-progress quest that ends here;
- a lost accept item of a quest started here and ended elsewhere (canonical `lost` lines, then the item is
  re-issued). A quest the NPC both starts and ends gets no second entry: its turn-in routes to the re-issue when the
  item is lost. With only the adaptation (1002: MeowDB has no `lost` lines) the item is handed over first, then the
  canonical `missing_items` lines play (Roger: "Eat the Roger's Apple I gave you ..."), so no speech is invented;
- the reminder for a quest started here that ends elsewhere (canonical `wrong_npc`);
- the offer of an available quest started here.

One entry is entered directly, several are listed in a menu, and none falls back to default talk.
- **Offer:** the canonical On accept lines, with the last line as the Yes/No prompt. Yes accepts and shows the
  `accepted` lines, No shows the `declined` lines.
- **Offer without On accept text** (MeowDB gap; on Maple Island only 1002 Roger's Apple): NPC speech would be
  invented, so the quest is offered as one quest card (speaker `journal`: the NPC's portrait and name, the QUEST tag,
  the quest name as title). Its text is the canonical journal summary (journal line 1; the quest name if there is no
  journal) and, under it, the generic system prompt `offer_prompt` ("Accept this quest?", `_system.json`) as the
  Yes/No. Yes accepts, then shows the canonical `accepted` lines if MeowDB has any, otherwise the in-progress journal
  lines (the middle lines of a 3+ line journal, `q<id>.brief.<i>`, also quest cards): for 1002, "Talk to Roger." /
  "Accept this quest?", then "Press the hotkey I to open your inventory, ... Then, talk to Roger." A 1- or 2-line
  journal has nothing after line 1, so the chat ends on Yes. No shows the `declined` lines, or ends the chat.
- **Turn-in:** if the quest is ready, the main On completion lines are shown, then the quiz (if any), then the
  reward pick (if `rewards.selection` applies), then `complete`, then the `ready` lines. A quest with no completion
  text completes silently and returns to the menu, so Sera's 1000 flows straight into her 1001 offer. If the quest is
  not ready, `missing_kills` / `missing_items` is shown.
- **Quizzes:** the question is a menu of the choices, and each choice runs `complete_quest` with its
  `quiz_choice`. The correct answer shows `correct_answer_response` (then the `ready` lines, if any); a wrong one
  shows its wrong-answer line and ends the chat (the quest stays in progress, so talking again retries). A quiz quest
  that also has a selection reward grades the choice with `answer_quiz` instead, and the correct-answer line leads to
  the reward pick, which completes the quest.
- **Shops:** a greeting line, then `open_shop`.
- **Transport** (an NPC with routes and a departure boundary: Shanks): the greeting (his canonical speech-bubble line
  1, "I'll take you anywhere you want to go.", picked by `dialogue/15.json`), then the route's guide quote as a
  Notice ("Shanks at the dock sails you to Lith Harbor for 300 mesos once you reach level 7. The boat is one-way. Hand
  in every Maple Island quest before you board."), then:
  - below `min_level`: "You need to be at least level 7 to sail to Lith Harbor." and the chat ends;
  - below the fare: "The fare to Lith Harbor is 300 mesos. Come back when you have enough.";
  - with unfinished quests of the boundary's region: "You still have unfinished Maple Island quests: Roger's Apple,
    Mai's Training (2 of 3 left), Rain's Maple Quiz (7 of 7 left), ..." (chains grouped), a warning only;
  - then the Yes/No "Sail to Lith Harbor? The fare is 300 mesos." Yes runs `depart` (it re-checks level and fare);
    No ends the chat. MeowDB has no boarding dialogue for Shanks, so every line after the greeting is the guide's
    canonical sentence or a system line (`_system.json`). Several routes would get a destination menu first.
- **Default talk:**
  - quest NPCs say their first "What X Says" line, and the last one once all their quests are completed;
  - except a line of `default_talk.in_progress_lines` (owner ruling #9), which shows only while its quest is in
    progress (node `talk.during.<k>`); the rule above runs over the NPC's other lines. Sera's "Did you give my mirror
    to Heena?" is tied to 1001 and Sen's "What did my sister say?" to 1004, so both say line 0 before and after.
    Sera's talk is reached during 1001 only when no quest entry shows: her conversation opens on the canonical
    reminder ("It looks like you haven't delivered the mirror to Heena yet.") or the lost-mirror branch first, as
    before. 1004 has no reminder, so Sen says his line whenever he is talked to during it;
  - townsfolk say all their lines in order;
  - NPCs without quoted lines say their first idle-chatter line.

**Rules as data.** `data/misostory/dialogue/_rules.json` records the rules above that MeowDB does not give, each with
its reason and `verified: false`: `offer_prompt.line` ("last_on_accept_line"), `default_talk.quest_npc`
("first_line_until_all_own_quests_completed_then_last_line", or "all_lines_in_order"),
`default_talk.in_progress_lines` (rows `{npc_id, line, quest_id, reason, verified, decision}`: the line, 0-based,
shows only while the quest is in progress), `default_talk.townsfolk`, `default_talk.no_quoted_lines`,
`quiz.wrong_answer`, `quiz.after_right_answer` and `shop_window_title.format` ("{npc}'s Shop", read by the shop window
through `NpcDialogueBuilder.shop_title`). The builder reads them, falls back to the same behaviour when the file is
absent, and `validate_all()` (`validate_rules()`) fails on a value the code does not implement, and on an
in-progress line whose NPC, line or quest does not exist, that repeats a row, or that leaves its NPC no other line.

**Overrides.** `data/misostory/dialogue/<npc_id>.json` takes `{reason, verified, remove_nodes: [...], nodes: {id:
node} (add or replace), patch_nodes: {id: {key: value}} (replace single keys of a generated node), start?}`, applied
in that order. A patch for a node that does not exist is a validation error. System lines live in
`data/misostory/dialogue/_system.json`.

## Canonical sources used

- `game/data/canonical/quests/1000–1019.json`: requirements, objectives, rewards, accept items, hand-ins,
  follow-ups, `next_quest_grants`, journal, dialogue and quizzes. Their rules come from `docs/canonical/quests.md`:
  - grade by `correct_choice_index` (1018 is inferred);
  - join items by `item_id`;
  - `min_level` 0 means no requirement.
- `game/data/canonical/npcs/1–21.json`: identity, map, position, roles, quests started and completed, shop link,
  transport, "What X Says" lines and idle chatter. The NPC files' corrected dialogue links (`ref.meowdb_link_id`)
  remap quest-dialogue item refs: 1005's "Jr. Sentinel Shellpiece" links item 2584 in the quest file and is shown as
  347.
- `game/data/canonical/items/*.json`: inventory tabs and stacks (through `Inventory`), names, and `game_item_id` for
  inline item icons.
- `game/data/canonical/formulas/beginner.json`: job display name ↔ slug.
- `game/data/canonical/shops/*.json`: shop ids (validation).

## Adaptations (MisoStory decisions) and why

| What | Where | Why |
|---|---|---|
| Roger hands over 1 Roger's Apple on accepting 1002 | `data/misostory/quests/1002.json` (`verified: false`) | MeowDB lists no accept items, but the quest needs 1 use and the dialogue says "the Roger's Apple I gave you"; 1 is the minimum that makes it completable |
| Shop greetings reuse a canonical idle-chatter line (Pan 1, Sid 1, Lucy 2) | `data/misostory/dialogue/16.json`, `20.json`, `21.json` | MeowDB has no shop greeting; no NPC speech is invented |
| System lines (inventory full, cannot accept/complete) | `data/misostory/dialogue/_system.json` | MeowDB publishes no client messages; shown as speaker "system" |
| Shanks' boat ends at an "End of Maple Island" screen: the canonical level and fare are checked, nothing is charged, nobody travels, `flags.maple_island_departure_ready_at` is set to the game clock | `data/misostory/npcs/15.json` `departure` (`verified: false`) | Victoria Island is out of scope ("The Southperry departure boundary is enough"); without a voyage the fare is not taken; the flag lets a later build and the playthrough see the boundary was reached |
| Shanks warns with the guide's sentence and the character's unfinished Maple Island quests, but still offers the boat | builder; `departure_unfinished_quests` in `_system.json` | the canonical advice is "Hand in every Maple Island quest before you board"; MeowDB says nothing about refusing, so it is a warning, not a block |
| Shanks' greeting is his speech-bubble line 1; the transport pages are system lines with the canonical route values | `data/misostory/dialogue/15.json`; `transport_*` and `cannot_travel` in `_system.json` | MeowDB has no boarding dialogue, refusal or Yes/No text for Shanks |
| A lost Roger's Apple is re-issued at Roger while 1002 is in progress (then his canonical "Eat the Roger's Apple I gave you" line) | `data/misostory/quests/1002.json` `reissue_lost_accept_items` | MeowDB has no "lost" branch for 1002, and the old workaround (forfeit and re-accept) needed the debug console |
| A shop refuses to buy a quest-critical item an in-progress quest still needs, and says why | `data/misostory/quests/_quest_items.json`; `QuestItemGuard`, `ShopService.quote_sell` | MeowDB documents no sell restriction, but selling Roger's Apple mid-1002 made the quest uncompletable; tradeable drops (Blue Snail Shell, Orange Mushroom Cap) and extra copies stay sellable |
| The quest log says "Return to X" only for an NPC already met through a quest, else "Talk to X" | `QuestEngine.npc_met`, `MisoUiText.objective_text` | UI wording; "Return to Mai" was wrong for a Beginner sent to Mai by Sam |
| The dialogue rules below live in data with reasons | `data/misostory/dialogue/_rules.json` | they were code-only inferences (Iteration Three audit); the provenance audit must see them |
| `wrong_npc` and `lost` branches are spoken by the start NPC | builder | MeowDB files them under On completion, but they read as the start NPC (npcs.md speaker caveat) |
| Quest with no On accept text (1002) is offered as a quest card: journal summary + "Accept this quest?", then the in-progress journal lines after Yes | builder; prompt in `data/misostory/dialogue/_system.json` (`offer_prompt`, `verified: false`) | MeowDB gap; the journal text is canonical and NPC speech would be invented. The summary ("Talk to Roger.") is a description, not a question, so a generic system prompt that names nothing asks it; the instructions read as what to do next, so they follow the accept |
| Main completion lines come before the reward; `ready` lines after it | builder | MeowDB does not say which lines precede the reward |
| Wrong quiz answers pair with wrong choices in order; a wrong answer ends the chat, retry by talking again; the next quiz needs a new talk | builder; `_rules.json` `quiz` | MeowDB does not link them (the counts match for every quiz) and does not say whether retries are allowed (1015's text suggests they are) |
| The last On accept line is the Yes/No prompt, even when it is a statement (1000's Quest Helper tip; 1014-1019 "talk to me when you're ready...") | builder; `_rules.json` `offer_prompt` | MeowDB does not mark the prompt line; writing a question would invent NPC speech |
| Quest NPC talk: first line before, last line after all their quests | builder; `_rules.json` `default_talk` | MeowDB does not label when each "What X Says" line shows |
| Sera's "Did you give my mirror to Heena?" shows only while 1001 is in progress, Sen's "What did my sister say?" only while 1004 is; otherwise each says line 0 | builder; `_rules.json` `default_talk.in_progress_lines` (`verified: false`, decision #9) | Owner ruling #9 (2026-10-06): under the general rule these mid-quest lines showed after completion |
| The shop window is titled "<NPC>'s Shop" | `_rules.json` `shop_window_title` | MeowDB has no shop title |
| Completing a quest does not auto-start its follow-up; `next_quest_grants` items are given when the follow-up is accepted | engine | the follow-ups have canonical decline branches (1001), and quests.md says not to grant the items twice |
| Forfeit takes back accept items still held | engine | MeowDB is silent; prevents duplicating quest items by forfeit/re-accept |
| The player can forfeit an in-progress quest from the Quest Log, after a confirmation | `MisoQuestWindow`, `MisoForfeitPrompt` (UI.md) | Owner ruling #10 (2026-10-06): before it only the debug console could forfeit; MeowDB documents no forfeit |
| Kill counts cap at the required count; only kills while in progress count | engine | classic quest log behaviour; MeowDB does not specify |
| Random rewards weighted by `chance_pct` | engine | MeowDB publishes only rounded percentages, no weights |
| Turn-in talk recorded only after the other objectives | engine | the canonical rule "use Roger's Apple, then talk to Roger" |
| Pio's 1012 accept line shows the live Rusty Screw / Old Wooden Board counts instead of MeowDB's literal "0" | `data/misostory/dialogue/18.json` (`patch_nodes`, `counters`) | MeowDB renders the game's counter as a literal; quests.md §10 and npcs.md say to substitute the live count |

## Testing

```bash
ISOLATE=quests bash scripts/test.sh quest dialogue npc shop
```

Every test file of this system declares `parity_keys()` (contract C6) for the tests that prove a canonical or brief
requirement (`quest:1005`, `npc:15`, `shop:maple-road-lucy`, `mechanic:quest-rewards-received`, ...).

| File | Covers |
|---|---|
| `tests/unit/test_quest_log.gd` | states, timestamps, caps, JSON round trip (int restoration), garbage tolerance, `CharacterState` composition |
| `tests/unit/test_quest_engine.gd` | shipped data validates; unsupported `other` and unknown objective kinds are reported and never complete; level / job / prerequisite gating; 1002 end to end (apple given, use, talk, 0 rewards); 1006 Snail-only kills, exactly 30 EXP (the character's total EXP grows by 30 across the level-up) + 3 Eggs, refused when the Use tab is full; 1011 hand-in removal + deterministic random reward; chance weights; selection rewards; 1012; chain 1007→1008 (letter given once); lost letter re-issue; quizzes 1013 and 1018; a refused 1019 completion keeps the quiz unanswered; save mid-quest and continue; forfeit; markers; journal; quest summaries |
| `tests/unit/test_quest_save_load.gd` | brief Test E from a clean `CharacterFactory` character: accept, progress halfway, save through `SaveDocument.build` → JSON → `SaveDocument.decode`, reload into a fresh session, finish and verify the exact canonical reward (1006: +30 EXP, +3 Eggs; 1002: the apple survives the save, is eaten through `ItemService.use_item`, 0 rewards); completion persists |
| `tests/unit/test_quest_service.gd` | Events in/out on a private `events.gd` bus; quest level-ups announced like `Game.gain_exp` (one `leveled_up` per level, `hp_changed`/`mp_changed`, `stats_changed`), including a multi-level reward (1010 at level 1); inventory_full announcement, character provider, detach, debug commands |
| `tests/unit/test_dialogue_runner.gd` | hand-written graphs: Next/Back, Yes/No, menu conditions (level, mesos, flag, job, items, quest), branch, auto-single, actions clear history, on_fail routing, shop request, give/take, objective conditions, validation errors, overrides and patches, counter validation, `parts` lines (paragraphs, sources, styling, every part validated, counters on a part reported), `answer_quiz`, no crash without content |
| `tests/unit/test_dialogue_npc_conversations.gd` | every NPC's generated conversation validates and opens; Sam → Mai full flow with Events; decline; full inventory at Mai; Roger's Apple conversation (offer card, instructions after Yes, decline); every quest's offer is canonical NPC speech or (1002 only) a quest card, Sam's offer carries no system text; synthetic card offers (4-line journal: two instruction pages; 2-line: none; no journal: the quest name; canonical accept/decline branches kept); Rain 1013 wrong/right and 1018; Heena/Sera chain with a lost mirror; 1005 item ref remap; Pio's live 1012 counters; a synthetic quiz + selection quest completed from data alone; shop greeting → shop request; townsfolk Back; Shanks |
| `tests/unit/test_quest_forfeit_ui.gd` | the Quest Log's Forfeit (owner ruling #10): the button only on an in-progress quest; a real click asks first (modal), Cancel changes nothing, Forfeit forfeits through `Game.quests` (one `quest_forfeited`, the mirror taken back), the log updates and Sera offers 1001 again; Delete, the focus on Cancel, Left/Right, Enter, Y, N, Esc and the window stack's Esc; Space and key repeat press nothing; quiet under another modal; closing the log cancels; no quest service, no change |
| `tests/unit/test_dialogue_default_talk.gd` | the in-progress lines (owner ruling #9): Sera before, during and after 1001 (during: the canonical reminder first, her default talk the mirror line) and Sen before, during and after 1004; every other NPC's conversation is node for node what it is without the overrides, and Heena still says her last line after her quests; `validate_rules()` accepts the shipped rows (unverified, decision #9, the rule's reason cites #9) and rejects a line, NPC or quest that does not exist, a repeated row and an NPC left without a line |
| `tests/unit/test_npc_catalog.gd` | 21 NPCs, validation, Roger, shops, quest relationships equal the quest records, Shanks' canonical route and departure boundary (and a transport NPC without one is reported), NPCs per map, idle lines |
| `tests/unit/test_quest_rewards_received.gd` | QuestLog format 2: 1006 (30 EXP, 3 Eggs), 1008 (the random hat, its group, survives a save; other seeds record other hats), 1011 (the random weapon), 1012 (150 mesos, The Green Relaxer) recorded; unrecorded completions; a format 1 log loads; a migration-written record is kept; unknown keys at every level survive load and save, and the engine still works on that log; entries it cannot read (unknown status, not_started, non-dictionary) survive load and save |
| `tests/unit/test_quest_log_window.gd` | chain_info for every chain; chain steps follow quest state; npc_met and the turn-in wording (Talk to Mai / Return to Roger, Heena, Maria); quest_summary NPCs and maps; missable parsing (flag, sourced object, default false); the window: "Mai's Training 2/3" with steps and maps, "Rain's Maple Quiz 4/7", "Talk to Mai", the Missable tag, "Received: <hat>" after a reload |
| `tests/unit/test_quest_every_quest.gd` | markers for all 20 quests through their states (hidden below level, available, in progress, one kill short, ready, gone once completed); every Rain quiz 1013-1019 answered with each wrong choice (its paired canonical line, still in progress) and the right one (canonical line, exact EXP, 245 in all, 10 Oranges) through the conversation; 1003 → 1004 (Nina's reminder, Sen completes 1003 and offers 1004, +3 EXP); 1005 (only mob 1, capped at 3, missing-kills / missing-items lines, +10 EXP, 3 Shellpieces taken) |
| `tests/unit/test_npc_shanks_departure.gd` | Shanks: level 6 refused, level 7 with 299 mesos refused, a ready character reaches the boundary (flag = game clock, saved; no mesos taken; no travel; the canonical route in the effect), the unfinished-quest list (chains grouped, completed ones left out), No leaves nothing, boarding re-checks the fare, no boundary = `not_built`, a charging boundary takes the fare |
| `tests/unit/test_shop_quest_items.gd` | the sell guard: Roger's Apple during 1002 (refused with the message; an extra copy sells; free once eaten), Shellpieces during 1005 (only the 3 needed are held), tradeable drops for 1011 stay sellable, Sera's Mirror during 1001, the adaptation switch, the shop window's check line and status; Roger re-issues a lost apple (canonical line after, no duplicate while held, 1002 then completes), no room = the system line, one menu entry |

**Real-game coverage.** Every one of the 20 quests is played in the real game with real input by the every-quest set
(`bash scripts/playtest_quests.sh`, PLAYTEST_HARNESS.md): offer, accept, objectives, saves and process restarts in
the middle, the exact reward and the follow-ups, strict after a logged setup. On the integrated Iteration Three build it passes 20 of
20 (seed 1, 2026-10-05). `test_e_quest` also plays 1002, 1006 (across a save and reload), 1007 and 1008. `quest_forfeit` (strict) accepts
1000 from Heena, forfeits it by clicking in the Quest Log (after a Cancel and an Esc that change nothing) and accepts
it again. The Shanks
boundary and the speech bubbles are unit-tested; their real-key scenarios were checked during the quests package
(22 and 4 checks) but are not committed.

Data validation for this system is `QuestCatalog.new(db).validate()`, `NpcCatalog.new(db).validate()` and
`NpcDialogueBuilder.new(db).validate_all()`. The tests assert that all three are clean, and `scripts/validate_data.sh`
runs them too (`GameplayDataChecks`, checks `quest_data`, `npc_data`, `dialogue_data`; DATA_VALIDATION.md) once the
structural checks found no error.

## Known gaps

- An NPC with both quests and a shop shows the shop only when it has no quest entry (no such NPC on Maple Island).
- The amount and timing of Roger's apple, its re-issue, and the quiz retry rule are unverified adaptations (see
  above).
- `quest_progressed` requests a debounced autosave since the save package added it to `Game.AUTOSAVE_TRIGGERS`, so
  mid-quest kill and use counts survive a crash.
- `flags.maple_island_departure_ready_at` is overwritten at every boarding, so it records the latest, not the first.
