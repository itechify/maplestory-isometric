# Quests, NPCs and dialogue (Iteration Two)

This covers the quest framework (brief Phase 16, "Quest Data Authority", "One Authentic Maple Island Quest"), the
NPC framework (Phase 14, the pure part), the dialogue engine (NPC Interaction, Dialogue UI data) and the data side of
the quest UI (Phase 17). Everything here is pure `RefCounted` code in `game/scripts/core/{quests,npcs,dialogue}/`:
no scene tree. Content is data only. No code path names a quest or an NPC, so a new quest needs only its canonical
record and, if MeowDB has a gap, an adaptation file.

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
| `scripts/core/npcs/npc_def.gd`, `npc_catalog.gd` | `NpcDef`, `NpcCatalog` | NPC identity, relationships, behaviours, validation |
| `scripts/core/npcs/npc_interaction.gd` | `NpcInteraction` | talk to an NPC: builds and runs its conversation, routes actions through `QuestService` |
| `scripts/core/dialogue/dialogue_graph.gd` | `DialogueGraph` | branching dialogue format, override merge, validation |
| `scripts/core/dialogue/dialogue_context.gd` | `DialogueContext` | conditions and actions |
| `scripts/core/dialogue/dialogue_runner.gd` | `DialogueRunner` | runs a graph, history for Back, produces UI views |
| `scripts/core/dialogue/dialogue_text.gd` | `DialogueText` | line references → UI text segments |
| `scripts/core/dialogue/npc_dialogue_builder.gd` | `NpcDialogueBuilder` | generates every NPC's conversation from canonical data |
| `data/misostory/quests/1002.json` | | Roger's Apple hand-out (adaptation) |
| `data/misostory/dialogue/_system.json`, `16.json`, `20.json`, `21.json` | | system lines; shop greetings |
| `data/misostory/dialogue/18.json` | | Pio: live item counters in 1012's accept line |
| `data/misostory/npcs/15.json` | | Shanks' transport disabled (out of scope) |

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
`npc_talk.shop_requested(shop_id, npc_id)`. Quest markers come from `npc_talk.marker(npc_id)`, and the quest window
from `Game.quests.engine.quest_summaries()`.

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
  respects the meso cap), fame and items, and marks the quest completed at `clock()`. Follow-ups unlock through
  their own prerequisites and are listed in `followups_available`. They are not auto-started (see Adaptations).
- **Forfeit** (`forfeit(id)`): progress is dropped, and accept items still held are taken back, up to the amount
  given.
- **Lost items** (`lost_items`, `reissue_lost_items`): an accept item is lost when an unfinished objective still
  needs it and it is no longer held. That is MeowDB's "If you lost the items" branch.
- **Results.** Every mutating call returns `{ok, reason, quest_id, effects, ...}`. `effects` is the ordered list of
  changes (`quest_started`, `item_gained`, `exp_gained`, ...); `QuestService.dispatch` turns them into Events.
  The failure reasons are listed in the `QuestEngine` class comment.
- **UI queries**:
  - `npc_marker(npc_id)` returns `"completable" | "available" | "in_progress" | ""`, and `npc_entries(npc_id)`
    returns the entries behind it.
  - `quest_summary(id)` and `quest_summaries([statuses])` give the name, status, journal text, objective rows
    (current/required/done) and `can_complete`.
  - `journal_text(id)`: line 1 is shown when the quest is available, the middle lines while in progress, and the
    last line once completed.

### QuestLog (save format)

```json
{"format": 1, "quests": {"1006": {"status": "in_progress",
  "progress": {"kills": {"2": 4}, "used": {}, "talked": [], "visited": [], "other": {}},
  "started_at": 12.5, "completed_at": -1.0, "completions": 0}}}
```

- A quest with no entry is `not_started`.
- `started_at` / `completed_at` are game-clock seconds (`Game.clock`); -1 means never.
- `from_dict` wraps JSON floats back into ints, ignores malformed entries, and turns `{}` into an empty log.

## NPCs

`NpcCatalog.new(db).get_def(id)` → `NpcDef`. Its fields:
- `name`, `map_id`, `position_px` (canonical px; the 3D placement comes from Blender markers);
- `roles`, `function_title`, `quests_started`, `quests_completed`, `shop_id`, `transport`;
- `dialogue_lines`, `idle_chatter` (`idle_line(i)` for speech bubbles);
- `portrait`, `visual`;
- `behaviors`, in a fixed order: `quest`, `shop`, `transport`, `talk`. These are derived from the data, because
  MeowDB has no interaction-type field.

`data/misostory/npcs/<id>.json` may set `portrait` (default `npc_<id>`), `visual` (free-form hints for the actor
layer) and `disabled_behaviors`. Every such file needs a top-level `reason` and `verified`.

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
- `{"system": key}`;
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
- `all` / `any` / `not`.

**Actions:**
- `accept_quest`, `complete_quest` (with optional `quiz_choice` / `selection_index`), `answer_quiz` (`choice`:
  grades the answer without completing; fails with `wrong_answer`), `forfeit_quest`, `reissue_quest_items`;
- `open_shop`: an `open_shop` effect, which `NpcInteraction` turns into `shop_requested`;
- `give_item`, `take_item`, `set_flag`.

**VIEW** (`DialogueRunner.view()`, returned by every `NpcInteraction` call):
`{open, node_id, type, npc_id, speaker_id, speaker_name, portrait, speaker_kind: npc|system|journal, title (quest
name), text, segments, source, choices: [{index, text, segments, quest_id, tag}], buttons}`. `buttons` is a subset
of `back`, `next`, `ok`, `yes`, `no` and `end`.

**Generated conversations** (`NpcDialogueBuilder`, node ids in its class comment). Which quests an NPC starts and
ends comes from the quest records (the same lookups as `npc_marker`), so a quest added as data is offered even
before the NPC record lists it; `NpcCatalog.validate()` reports such a mismatch, and `disabled_behaviors: ["quest"]`
switches quest entries off. When the player talks to an NPC, these entries are evaluated live:
- the turn-in of an in-progress quest that ends here;
- a lost accept item of a quest started here (canonical `lost` lines, then the item is re-issued);
- the reminder for a quest started here that ends elsewhere (canonical `wrong_npc`);
- the offer of an available quest started here.

One entry is entered directly, several are listed in a menu, and none falls back to default talk.
- **Offer:** the canonical On accept lines, with the last line as the Yes/No prompt. Yes accepts and shows the
  `accepted` lines, No shows the `declined` lines.
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
- **Default talk:**
  - quest NPCs say their first "What X Says" line, and the last one once all their quests are completed;
  - townsfolk say all their lines in order;
  - NPCs without quoted lines say their first idle-chatter line.

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
| Shanks only talks | `data/misostory/npcs/15.json` | the Lith Harbor boat leaves Maple Island (out of scope); MeowDB has no boarding text |
| `wrong_npc` and `lost` branches are spoken by the start NPC | builder | MeowDB files them under On completion, but they read as the start NPC (npcs.md speaker caveat) |
| Quest with no On accept text (1002) is offered as a quest card with its journal text | builder | MeowDB gap; journal text is canonical, NPC speech would be invented |
| Main completion lines come before the reward; `ready` lines after it | builder | MeowDB does not say which lines precede the reward |
| Wrong quiz answers pair with wrong choices in order; a wrong answer ends the chat, retry by talking again | builder | MeowDB does not link them (the counts match for every quiz) and does not say whether retries are allowed (1015's text suggests they are) |
| Quest NPC talk: first line before, last line after all their quests | builder | MeowDB does not label when each "What X Says" line shows |
| Completing a quest does not auto-start its follow-up; `next_quest_grants` items are given when the follow-up is accepted | engine | the follow-ups have canonical decline branches (1001), and quests.md says not to grant the items twice |
| Forfeit takes back accept items still held | engine | MeowDB is silent; prevents duplicating quest items by forfeit/re-accept |
| Kill counts cap at the required count; only kills while in progress count | engine | classic quest log behaviour; MeowDB does not specify |
| Random rewards weighted by `chance_pct` | engine | MeowDB publishes only rounded percentages, no weights |
| Turn-in talk recorded only after the other objectives | engine | the canonical rule "use Roger's Apple, then talk to Roger" |
| Pio's 1012 accept line shows the live Rusty Screw / Old Wooden Board counts instead of MeowDB's literal "0" | `data/misostory/dialogue/18.json` (`patch_nodes`, `counters`) | MeowDB renders the game's counter as a literal; quests.md §10 and npcs.md say to substitute the live count |

## Testing

```bash
ISOLATE=quests bash scripts/test.sh quest dialogue npc
```

| File | Covers |
|---|---|
| `tests/unit/test_quest_log.gd` | states, timestamps, caps, JSON round trip (int restoration), garbage tolerance, `CharacterState` composition |
| `tests/unit/test_quest_engine.gd` | shipped data validates; unsupported `other` and unknown objective kinds are reported and never complete; level / job / prerequisite gating; 1002 end to end (apple given, use, talk, 0 rewards); 1006 Snail-only kills, exactly 30 EXP (the character's total EXP grows by 30 across the level-up) + 3 Eggs, refused when the Use tab is full; 1011 hand-in removal + deterministic random reward; chance weights; selection rewards; 1012; chain 1007→1008 (letter given once); lost letter re-issue; quizzes 1013 and 1018; a refused 1019 completion keeps the quiz unanswered; save mid-quest and continue; forfeit; markers; journal; quest summaries |
| `tests/unit/test_quest_save_load.gd` | brief Test E from a clean `CharacterFactory` character: accept, progress halfway, save through `SaveDocument.build` → JSON → `SaveDocument.decode`, reload into a fresh session, finish and verify the exact canonical reward (1006: +30 EXP, +3 Eggs; 1002: the apple survives the save, is eaten through `ItemService.use_item`, 0 rewards); completion persists |
| `tests/unit/test_quest_service.gd` | Events in/out on a private `events.gd` bus; quest level-ups announced like `Game.gain_exp` (one `leveled_up` per level, `hp_changed`/`mp_changed`, `stats_changed`), including a multi-level reward (1010 at level 1); inventory_full announcement, character provider, detach, debug commands |
| `tests/unit/test_dialogue_runner.gd` | hand-written graphs: Next/Back, Yes/No, menu conditions (level, mesos, flag, job, items, quest), branch, auto-single, actions clear history, on_fail routing, shop request, give/take, objective conditions, validation errors, overrides and patches, counter validation, `answer_quiz`, no crash without content |
| `tests/unit/test_dialogue_npc_conversations.gd` | every NPC's generated conversation validates and opens; Sam → Mai full flow with Events; decline; full inventory at Mai; Roger's Apple conversation; Rain 1013 wrong/right and 1018; Heena/Sera chain with a lost mirror; 1005 item ref remap; Pio's live 1012 counters; a synthetic quiz + selection quest completed from data alone; shop greeting → shop request; townsfolk Back; Shanks |
| `tests/unit/test_npc_catalog.gd` | 21 NPCs, validation, Roger, shops, quest relationships equal the quest records, Shanks override, NPCs per map, idle lines |

Data validation for this system is `QuestCatalog.new(db).validate()`, `NpcCatalog.new(db).validate()` and
`NpcDialogueBuilder.new(db).validate_all()`. The tests assert that all three are clean. `scripts/validate_data.sh`
(`DataValidator`, owned by the validation system) does not call them yet, so an unsupported `other` objective in new
quest data is reported by the unit tests but not by the headless data validation until it does.

## Known gaps

- An NPC with both quests and a shop shows the shop only when it has no quest entry (no such NPC on Maple Island).
- A Roger's Apple lost before it is eaten is not re-issued in dialogue (MeowDB has no "lost" branch for 1002); the
  player can forfeit 1002 and accept it again, which hands over a new apple.
- The amount and timing of Roger's apple, and the quiz retry rule, are unverified adaptations (see above).
