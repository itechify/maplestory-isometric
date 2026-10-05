# Interaction, NPC presentation, dialogue and shop windows, ground loot (Iteration Two, wave 2)

Everything the player touches in the world besides monsters. It covers these parts of the brief:

- Phase 10: drops appear, exist, can be picked up and expire.
- Phase 13: meso pickup.
- Phase 14: "NPC Interaction" steps 1 to 8.
- The "Dialogue UI" section.
- Phase 15: the shop UI.

The rules underneath belong to other systems: `NpcInteraction` and `DialogueRunner` (QUESTS_AND_DIALOGUE.md), `ShopService`, `ItemService`, `DropRoller` and `DropRates` (ITEMS.md), and `MapInstanceState`, `IslandWorld`, `WorldNpc` and `PortalInteractor` (WORLD_RUNTIME.md). This system presents those rules and connects them to the keys.

## Files

| Path | Class | Role |
|---|---|---|
| `scenes/systems/interaction_system.tscn` | `InteractionSystem` | root: the context prompt, the interact key, NPC presenters, modal arbitration |
| `scripts/systems/interaction/interaction_resolver.gd` | `InteractionResolver` | pure: which one interactable the prompt names, and whether F talks |
| `scripts/systems/interaction/interaction_prompt.gd` | `InteractionPrompt` | the prompt widget (`[F] Talk to Roger`) |
| `scripts/systems/interaction/world_ui_services.gd` | `WorldUiServices` | finds the shared `NpcInteraction`, the autoloads, input presses; null-safe |
| `scripts/systems/interaction/sandbox/world_ui_sandbox.tscn` (+ `.gd`) | | sandbox and headless integration check on the real island |
| `scripts/systems/interaction/sandbox/world_ui_main_checks.tscn` (+ `.gd`) | | the world UI driven inside the real `main.tscn` (checks and screenshots) |
| `scripts/actors/npcs/npc_presenter.gd` | `NpcPresenter` | per-NPC child node: name tag, quest marker, idle bob, facing the player |
| `scripts/actors/npcs/npc_name_tag.gd`, `quest_marker.gd` | `NpcNameTag`, `QuestMarker` | the tag under the feet, the marker above the head (screen space) |
| `scenes/ui/npc_ui.tscn` | `NpcUi` | root: the dialogue window and the shop window |
| `scripts/ui/npc/dialogue_window.gd` | `DialogueWindow` | renders every dialogue VIEW and forwards answers |
| `scripts/ui/npc/dialogue_rich_text.gd` | `DialogueRichText` | text segments to BBCode (bold, red, highlighted references), escaped |
| `scripts/ui/npc/npc_portrait.gd` | `NpcPortrait` | the NPC's own proxy model rendered in a SubViewport, or an initial badge |
| `scripts/ui/npc/shop_window.gd` | `ShopWindow` | Buy and Sell tabs, quantity picker, meso check, result messages |
| `scripts/ui/npc/npc_ui_style.gd` | `NpcUiStyle` | MisoTheme bridge (loaded by path) plus the local paper and overlay styles |
| `scripts/ui/npc/loot_item_icon.gd` | `LootItemIcon` | fallback icon drawn in the item's ground-drop shape |
| `scenes/systems/loot_system.tscn` | `LootSystem` | root: drops on the ground, pickup, expiry, persistence |
| `scripts/actors/loot/ground_drop.gd` | `GroundDrop` | one drop: toss arc, hover, bob and spin, expiry blink |
| `scripts/actors/loot/loot_visuals.gd` | `LootVisuals` | procedural drop models and styles from `loot_visuals.json` |
| `scripts/actors/loot/loot_rules.gd` | `LootPickupRules` | pure: pickup box in 3D, pickup target, scatter, notices, record helpers |
| `data/misostory/loot_visuals.json` | | adaptation: drop shapes, colours, sizes, motion, placement, pickup repeat |

## Integration (what the game shell does)

`SubsystemInstaller.DEFAULT_SUBSYSTEMS` already lists the three scenes:

| Scene | Parent | `setup(ctx)` |
|---|---|---|
| `res://scenes/systems/loot_system.tscn` | `ctx.systems` | Takes `ctx.player` and connects `Events.loot_dropped` / `map_left` / `map_entered`. Registers the console commands `loot`, `drop_item` and `drop_mesos`. Drop nodes are its children, in world space. |
| `res://scenes/systems/interaction_system.tscn` | `ctx.systems` | Takes `ctx.world` and `ctx.player`. Adds a `WorldOverlay` CanvasLayer at `ctx.ui_root.layer - 1` (tags, markers, prompt: above the 3D world, under the HUD and windows). Attaches an `NpcPresenter` to every `world.npc_nodes` entry and refreshes markers on quest events. |
| `res://scenes/ui/npc_ui.tscn` | `ctx.ui_root` | Gives both windows the context: they push and pop the modal and register on the window stack, and Esc is left to `MainShell.handle_menu_action()`. Binds the shared `NpcInteraction` (`view_changed`, `shop_requested`) and `Events.shop_open_requested`. Keeps one NPC window open at a time and closes both on a map change (`MapSession.transition_started`, `Events.map_left`). |

The shared `NpcInteraction` is `Game.npc_talk`, which the shell wires in `game_state.gd`. `WorldUiServices.npc_talk(ctx)` looks it up in this order:

1. `ctx.npc_talk`;
2. `Game.npc_talk`;
3. `NpcInteraction.new(Game.quests)`;
4. a fallback `QuestService` built on `Events`, for when nothing above exists. It logs a warning. The game never needs it.

`NpcUi` checks the instance every frame and follows it if it changes. No calls beyond `setup(ctx)` are required. Every null field means "not available": each root also runs standalone (the tests and the sandbox inject their own collaborators).

## Keys: who acts on what (no double handling)

| Key | Who acts | The prompt says |
|---|---|---|
| `interact` (F) | 1. the player controller grabs a ladder/rope in reach (priority 0, first); 2. `PortalInteractor` (priority 100) enters the portal when `world.nearest_interactable()` is a portal; 3. `InteractionSystem` (priority 110) talks when the resolver's choice is an NPC, never while climbing, during a warp, with input off or under a modal | `[F] Talk to Roger` |
| `portal_enter` (Up) | the controller (ladders), `PortalInteractor` (portals) | `[Up] Climb`, `[Up] Enter portal` + the destination name |
| `climb_down` (Down) | the controller (ladder tops) | `[Down] Climb down` |
| `pickup` (Z) | `LootSystem` (priority 120), never while climbing; holding repeats every `pickup.hold_repeat_s` over the drops not refused during that hold | `[Z] Pick up Snail Shell` |

The prompt's precedence follows the order above, so it always names what the key will do:

1. blocked (a modal is open, a warp is running, the player is dead or has no input) or climbing: no prompt;
2. a grabbable ladder: climb;
3. `nearest_interactable()`: an NPC, or a portal if the portal is nearer;
4. the portal the player stands in. Hidden type-1 portals work but show no prompt, as in classic;
5. the drop the pickup key takes (`LootSystem.pickup_target`).

All presses are read through `player.input_source`, so the traversal bot can press them. One consequence: an NPC standing within 0.8 m of a ladder's line cannot be talked to from that spot, because F grabs the ladder. No map has that overlap today.

**Modal arbitration.** The dialogue uses the arrows for its choices, so Up in a menu must never enter a portal. The world's `PortalInteractor` refuses presses itself while the player's input is off or a modal is open (`PortalInteractor.blocked`, WORLD_RUNTIME.md), and this system's own keys check `WorldUiServices.player_can_act`. Until that world fix landed, `InteractionSystem` paused the interactor during modals; the workaround is gone (review, 2026-10-04), so only the world decides whether its interactor runs. `test_interaction_main_flow` checks Up in Rain's quiz menu while standing in a portal: the highlight moves, no warp, and the portal works again after the chat.

## Dialogue window

`NpcInteraction.view_changed` sends every VIEW to `DialogueWindow.show_view`. Every shape renders:

- `say` with Next, `say` with OK, Back;
- `yes_no`;
- `menu`: quest lists, quizzes, reward picks, End Chat;
- the speaker kinds `npc`, `journal` (quest cards) and `system` ("Notice", an "i" badge);
- empty text, unknown types, and the closed view.

It is built in code. On the left are the portrait and the name plate. On the right are the QUEST, QUIZ or SYSTEM badge and the quest title, the text on a paper body, then the choices and the buttons.

- **Text.** `DialogueRichText` turns segments into BBCode:
  - bold stays bold and red stays red;
  - references are highlighted by kind: items blue, monsters dark red, NPCs green, maps amber, quests violet;
  - canonical `[`/`]` characters are escaped, so they can never become markup.
- **Choices.** A numbered row per choice, with a mini marker for quest entries: offer `!`, ready turn-in `?`, waiting `...`, lost item `!`. The window passes the choice's runner `index` to `choose()`, not its position in the list.
- **Keys** (handled in `_input`, swallowed while open):
  - Enter or Space: Next/OK, or the highlighted button or choice;
  - Backspace: Back;
  - Y / N;
  - Up/Down (or W/S) through choices, Left/Right (or A/D) between Yes and No;
  - 1-9 pick a choice directly. Digits are swallowed even without a choice, so they never reach the quickslots.
- **Mouse.** Every button and choice row is clickable. Buttons never take focus, so Enter cannot press a button twice.
- **End Chat** is always offered, and Esc closes the window through the shell's window stack. Closing is safe at any point, because display nodes never run actions. `DialogueWindow.close()` guards against re-entry: `npc_talk.close()` sends `{"open": false}` back through `show_view`. `dialogue_closed` fires once.
- **Rewards and feedback.** These come from data and events, not from the VIEW:
  - An offer (`q<id>.offer.<n>`) lists the quest's canonical rewards from `QuestDef`: EXP, mesos, fame, items, "one of" and "your choice of".
  - When an accept or turn-in happens, the window collects the events of that step: `exp_gained` with source `quest:<id>`, `item_gained` and `mesos_changed`. The next view shows "Quest accepted: ... · Received ..." or "Quest complete: ... · +30 EXP, +Egg x3", including random rewards. If the chat ends right after, that line goes to `Events.notice` instead.
- **Portrait.** The world NPC's own `_library.glb` proxy is duplicated into a SubViewport with its own lights, in a three-quarter view of the upper body. Without a world it is a coloured initial badge.
- **Modal.** `ctx.push_modal(window)` and `ctx.window_opened(window)` on open; the reverse on close, with one
  exception. When a **key** ends the chat (Enter/Space on the last line, Y on an offer, a digit), the window leaves the
  window stack at once but keeps the modal until a physics step has run after that key event, then pops it
  (`is_holding_modal()`). The gameplay code polls `Input` in `_physics_process`, the window handles the key in `_input`
  before that step, and Space is also the jump key: popping at once made the player jump on the press that closed the
  chat (found in the real game). Every other close (End Chat, Esc through the window stack, a death, `handle_key` from
  tests) releases at once, and a new chat or the window leaving the tree cancels or releases a held modal.
- **Placement.** Bottom-centre, above any bottom-wide bar of another UI layer (`NpcUi.bottom_inset()`: a visible
  direct child of a sibling under `ctx.ui_root` anchored across the bottom edge, i.e. the HUD's status bar), so the
  chat never covers the HP/MP/EXP gauges. The shop is centred in the area above that bar. Both windows use MisoTheme's
  window frame made opaque (`NpcUiStyle.window_frame`): the theme's 0.93-alpha body let the HUD's arrival banner show
  through Lucy's shop header. The project stretches `canvas_items` / `expand` from 1600x900, so the fixed sizes (chat
  860 px wide, shop 940x600) always fit; checked at 1600x900 and 1280x720.
- **One NPC window at a time** (`NpcUi`). A shop opening while a chat is open ends the chat, deferred to the end of the
  frame: a shopkeeper's greeting opens the shop from inside its own last step and then ends by itself, so the deferred
  close normally finds nothing to do. A chat starting while the shop is open closes the shop. Before the review a
  `shop_open_requested` during a chat left both modal windows open, the shop eating the chat's keys.
- **A map change closes both windows** (`NpcUi.close_all()` on `MapSession.transition_started`, and on
  `Events.map_left` when there is no session). Before the review a console `warp` with a chat open carried the chat
  (still answerable) into the next map. A death closes them through the shell's window stack (DeathController).

## Shop window

The shop opens from `npc_talk.shop_requested` (a shopkeeper's greeting runs `open_shop`) or from `Events.shop_open_requested`, and it emits `shop_opened` and `shop_closed`. Opening the shop that is already open does nothing. Everything shown comes from data:

- **Buy tab.** `ShopService.stock` in canonical `position` order. Each row shows the icon (`MisoItemIcon`, the same icon as the inventory), the name, the price (with a bundle size if it is above 1) and the owned count. The detail panel shows the canonical description, the stat lines, requirements and restores, the price, how many you have, and a quantity picker (−, +, Max). The requirements are the level and stat requirements ("Req. Level 5") and, for a gendered item, its canonical gender in the inventory tooltip's words ("For female characters"). The panel lists requirements in one colour; unlike the tooltip, it does not turn an unmet one red. A gendered item is shown to every character, and anyone may buy it, as in classic; `Equipment` refuses the equip on a mismatch (`gender_mismatch`). Before the Test G review, Pan's White Tube Top showed no gender line to a male buyer. The picker is capped at what the mesos pay for and what fits, but is always at least 1, so a click still explains why it fails. The live total turns red, with the `ShopService.quote_buy` reason, when the purchase would fail.
- **Sell tab.** One sub-tab per inventory tab (1-5). The rows are the tab's non-empty slots, with the canonical sell-back price per unit and the slot quantity. A sale goes through `ShopService.sell_slot`, so the exact equipment instance is sold.
- **Results.** Every buy or sell goes through `ShopService`, so prices, the meso check, the space check and the Events are the items system's.
  - Success: "Bought Red Potion x5 for 250 mesos." / "Sold Snail Shell x4 for 4 mesos.".
  - Failure: `ItemCodes.message(result)`, for example "Your inventory is full.". Insufficient mesos adds the numbers: "(costs 50, you have 40)".
  - The meso display and the owned counts refresh on `mesos_changed` and `inventory_changed`.
- **Keys:**
  - Up/Down (W/S): choose a row;
  - Left/Right (A/D): change the quantity (Shift: by 10);
  - Enter: buy or sell, once the shop has been open for `confirm_arm_s` (0.3 s of frame time);
  - Space: swallowed, never buys or sells;
  - Tab: switch between Buy and Sell;
  - 1-5: inventory tab (all digits are swallowed, so they never reach the quickslots);
  - Esc: through the shell.

  Double-clicking a selected row and the Buy/Sell button also confirm, never delayed. The arm time and the dead Space
  key are a review fix: Space advances the dialogue (and jumps) and Enter is the dialogue's Next, so mashing either
  through Lucy's one-page greeting bought a Red Potion on the very next press. `confirm_arm_s` is a UI feel value (a
  `ShopWindow` var), counted in `_process` frame time so it is the same under `--fixed-fps`.

## NPC presentation

`NpcPresenter.attach(world_npc, overlay, db)` adds a `Presenter` child to each `WorldNpc`; `world_npc.gd` itself is not edited. Each presenter:

- **Name tag** under the feet, MapleStory style: a dark plate with the name in yellow, and the canonical `function_title` on a second line for shopkeepers ("Grocer"). It is drawn in screen space, so it stays crisp, and it shows only for current-map NPCs on screen (`WorldNpc.interaction_enabled`). The world's placeholder Label3D is hidden.
- **Quest marker** above the head, from `npc_talk.marker(id)`, refreshed every 0.3 s and on quest, item and level events:
  - available: a gold badge with "!" that bounces;
  - in progress: a slate badge with "..." that stays still;
  - ready to complete: a green badge with "?" and a pulsing ring.

  Colour, glyph and motion all differ.
- **Idle bob** of the model: 2.5 cm, a 2.6 s period, with a phase per NPC.
- **Facing.** While the player talks to this NPC, the model turns toward the player (`lerp_angle`, rate 8), then turns back.

## Ground loot

```
Events.loot_dropped(drops, kill_pos, map_id)          the monster system: DropRoller.roll output
  -> DropRoller.ground_records(drops, Game.clock, "player", db)        expires_at, owner, free_at, offset_m
  -> landing = kill_pos + offset_m along the camera's ground-right axis; grounded on the kill's tier
  -> record + uid + pos_local (map frame, [x, y, z]) -> MapSession.instance_state.add_drop(record)
  -> GroundDrop node: toss arc from 0.5 m above the kill point, then hover, bob, spin; blink in the last 10 s
Z -> LootPickupRules.pick_target(feet, landed drops, DropRates.pickup_box_m)  nearest drop in the canonical box
  -> DropRoller.may_pick_up (owner window) -> ItemService.pickup(record)
     ok: MapInstanceState.remove_drop(uid), node freed, Events.notice("You have gained an item (Snail Shell)"
         / "You have gained an item (Red Potion x3)" / "You have gained mesos (+1,500)"): word for word the HUD's own
         item_gained / mesos_changed lines, which the HUD log (it drops a line repeating the previous one) shows once
     refused (inventory full / meso cap): the drop stays; Events.notice("Your inventory is full."), the same sentence
         the HUD logs for Events.inventory_full, so the log shows one line; holding Z does not retry a refused drop
every frame: MapInstanceState.expire_drops(now) (the instance also expires on its own tick); nodes follow the records
map_left: nodes freed (records stay; MapSession snapshots the instance) / map_entered or a new state object: nodes
rebuilt from the restored records at rest, with their remaining lifetime (expires_at is on the pausable Game.clock)
```

- **Persistence** follows MAP_ARCHITECTURE §4.7.7. The records live in the live `MapInstanceState`, so the map cache's snapshot carries them. A return within the LRU window finds them with the same `expires_at`. An evicted map is fresh, and drops are never saved to disk, as in classic. A quit to title clears them too (`MapSession.reset()` on `detach_world`), so a continued game starts with no drops.
- **The instance API.** The loot system adds with `add_drop`, removes a picked-up record with `remove_drop(uid)` and expires with `expire_drops(now)`; it only reads `drops` to rebuild nodes. `LootPickupRules.UID_KEY` is `MapInstanceState.DROP_UID_KEY`.
- **Visuals** come from `loot_visuals.json`. They are procedural shapes from the canonical type and subtype:

  | Shape | Items |
  |---|---|
  | chest | equipment |
  | green crate | setup |
  | bottle | potions |
  | fruit | food |
  | rolled paper | scrolls |
  | arrow bundle | arrows |
  | faceted stone | ores and gems |
  | tied pouch | other Etc items |

  Name keywords tint the body (Red Potion red, Blue Snail Shell blue). Mesos change art with the amount: a bronze coin, a gold coin, a pile, then a bag. Every model has a soft shadow disc and slight emission, so it still reads in shade.
- **Debug console:**
  - `loot <owner_id> [kills]`: rolls a drop table at the player's feet;
  - `drop_item <item_id> [qty]`;
  - `drop_mesos <amount>`.

## Public API (the parts other systems or tests call)

- `InteractionSystem`:
  - `setup(ctx)`, `snapshot()`, `update_prompt() -> Dictionary`;
  - `handle_interact() -> bool`, `talk_to(npc_id) -> view`;
  - `attach_presenters()`, `attach_presenter(npc)`, `refresh_markers()`;
  - signals `prompt_changed(prompt)` and `talk_started(npc_id)`;
  - fields `prompt` and `presenters`.
- `InteractionResolver`: `resolve(snapshot, key_label := Callable()) -> {kind, action, key, verb, target_id, detail, text}`, `interact_talks(snapshot)`.
- `LootSystem`:
  - `setup(ctx)`, `spawn_drops(drops, world_pos, map_id := "") -> records`, `tick(delta)`;
  - `pickup_target(feet) -> {uid, position, label, record}`, `try_pickup(feet) -> ItemService result | {code: "nothing"}`, `remove_record(uid)`;
  - `clear_nodes()`, `nodes()`, `node_for(uid)`, `current_state()`;
  - signals `drop_spawned`, `drop_picked_up(record, result)`, `pickup_refused(record, result)` and `drop_expired(uid)`.
- `LootPickupRules`: `in_pickup_box`, `pick_target`, `scatter_points`, `pickup_notice`, `refusal_notice`, `drop_label`, `local_pos`, `time_left`.
- `NpcUi`: `setup(ctx)`, `bind_talk(talk)`, `open_shop(shop_id, npc_id)`, `close_all()`, `is_chat_close_queued()`, `model_for(npc_id)`, `bottom_inset()`, fields `dialogue`, `shop` and `session` (null = the MapSession autoload; tests inject one).
- `DialogueWindow`:
  - `show_view(view)`, `press(button)`, `choose_position(i)`, `activate()`, `close()`, `handle_key(event)`;
  - `visible_buttons()`, `body_text()`, `choice_texts()`, `pending_banner()`, `shown_banner()`, `is_open()`.
- `ShopWindow`:
  - `open_shop(shop_id, npc_id := "")`, `close()`, `set_mode("buy" | "sell")`, `set_sell_tab(tab)`;
  - `select(i)`, `select_buy_item(id)`, `select_sell_slot(tab, index)`;
  - `set_quantity(n)`, `change_quantity(d)`, `max_quantity()`;
  - `confirm()`, `buy_selected()`, `sell_selected()`;
  - `handle_key(event)`, `confirm_key_armed()`, fields `status_text`, `last_result` and `confirm_arm_s`.

## Canonical sources used

- `formulas/loot_rules.json` `player_pickup_box_px`, read through `DropRates.pickup_box_m`, which converts with `WorldScale.actor`.
- `data/misostory/drops.json`, read through `DropRates`. It is the items system's adaptation: ground lifetime 180 s, owner window 15 s, scatter 25 px.
- `shops/*.json` stock, order and prices through `ShopService`, and items' `sell_price_mesos`, names, types and descriptions.
- `npcs/*.json` names and `function_title`; `quests/*.json` names and rewards through `QuestDef`.
- Every dialogue line is MeowDB's own, resolved by `DialogueText`.

## Adaptations and why

| What | Where | Why |
|---|---|---|
| Drop shapes, colours, sizes (item 0.58 m, coin 0.36 m), meso tiers (<50 bronze, <100 gold, <1000 pile, bag) | `loot_visuals.json` | MeowDB's item and meso art are Nexon sprites, which MisoStory never uses. The sizes are set so a drop reads at the gameplay camera's 50-75 px per meter, close to a classic 32 px icon next to a character. |
| Toss 0.5 s / 1.1 m, hover 0.15 m, bob 5 cm, spin 70°/s, blink at 4 Hz in the last 10 s | `loot_visuals.json` motion | MeowDB documents no drop animation beyond "loot drops as soon as the mob dies" |
| Scatter along the camera's ground-right axis; a scatter point more than 0.6 m above or below the kill's ground is pulled back (half the offset, then none) | `loot_visuals.json` placement; `LootSystem._landing` | Classic drops spread across the screen and stay on the monster's foothold. 0.6 m is the spawn tier tolerance. |
| Holding Z picks up every 0.2 s | `loot_visuals.json` pickup | Classic hold-to-loot; MeowDB documents no rate |
| The pickup box's left/right become a horizontal radius around the feet; above/below stay vertical | `LootPickupRules.in_pickup_box` | The 2D box has no depth axis. Both canonical sides are 25 px. |
| Only landed drops can be picked up (not mid-toss) | `LootSystem.pickup_target` | readability; the toss lasts 0.5 s |
| A meso pickup at the meso cap that adds nothing leaves the drop; a partial add consumes it | `ItemService.pickup` semantics | the items system's rule, kept as is |
| Prompt precedence: climb > NPC/portal (nearest) > portal > drop; one prompt | `InteractionResolver` | The prompt must name what the key does, and the controller grabs ladders first |
| End Chat always offered; Esc ends any chat | `DialogueWindow` | Closing is always safe (actions only run on transitions), and MapleStory's chat has End Chat on every page |
| One NPC window at a time; a map change closes the chat and the shop | `NpcUi` | Both are modal and read the same keys; a chat or a shop has no meaning away from its NPC |
| Enter buys only after the shop has been open 0.3 s; Space never buys | `ShopWindow.confirm_arm_s` (UI feel, code) | Enter and Space advance the shopkeeper's greeting: mashing them must not spend mesos |
| Quest accept/complete summaries and offer reward lines | `DialogueWindow` | The VIEW does not carry them, but the brief asks for "reward summary lines". Rewards come from canonical `QuestDef`, the summary from the actual events. |
| Name tag under the feet, quest marker above the head, idle bob 2.5 cm / 2.6 s, turn rate 8, marker refresh 0.3 s | `NpcPresenter`, `QuestMarker` (code constants) | Cosmetic presentation constants, not gameplay values. This system owns no NPC presentation data file. |
| NPC portrait = the world proxy in a SubViewport | `NpcPortrait` | No NPC art may be used, and the proxy is MisoStory's own |
| Paper body for the dialogue text and the shop lists; everything else MisoTheme | `NpcUiStyle` | Canonical text carries red, blue and green emphasis that reads best dark on light, like MapleStory's NPC chat. The frame, buttons and font match the HUD's MisoTheme. |

## Testing

```bash
ISOLATE=worldui bash scripts/test.sh loot_ interaction_ npc_ui shop_ui   # 74 tests (the main-scene one SKIPs without the world)
ISOLATE=worldui INCLUDE_WORLD=1 bash scripts/test.sh interaction_main      # the world UI inside the real main.tscn (96 checks)
ISOLATE=worldui INCLUDE_WORLD=1 bash scripts/test.sh                      # the full suite
ISOLATE=worldui bash scripts/validate_data.sh                             # loot_visuals.json follows the convention
```

| File | Covers |
|---|---|
| `test_interaction_resolver.gd` | prompt texts and keys (F, Up, Down, Z); precedence climb > NPC > portal > drop; nothing while blocked or climbing; hidden portals; `interact_talks` only for NPCs |
| `test_interaction_system.gd` | with a duck-typed world and player: F talks to the nearest NPC through the shared `NpcInteraction`; no talk after the controller grabbed a ladder, on a nearer portal, or under a modal; the climb-down prompt; the drop prompt from `LootSystem`; presenters (tag, height from the model, markers available → in progress → completable through Sam/Mai, facing and turning back, bob); off-map NPCs stay quiet; presenters survive a freed overlay; a modal leaves the world's `PortalInteractor` to its own rule (no prompt, no talk, the interactor keeps running) |
| `test_npc_ui_dialogue.gd` | Roger's Apple and Sam's Suggestion end to end through the window's keys (offer rewards, accept summary to the notice log, item references, completion summary, Enter/Space/Esc); decline + Back + Left/Right; Rain's quiz with 1-9 and arrows; the system line on a full inventory; every VIEW shape (say/yes_no/menu/journal/system/empty/unknown, escaped brackets, ref colours); the runner index (not the position) is passed; closing mid-chat announces `dialogue_closed` once and accepts nothing; modal + window stack with a `GameContext` (Esc left to the shell); a walk through all 21 NPCs' conversations; BBCode rules; portrait badge vs model; a key that ends the chat holds the modal through the physics step (and a new chat, a non-key close or leaving the tree release it); both windows sit above another layer's bottom-wide bar; one NPC window at a time (a shop request ends the chat, a chat closes the shop, Lucy's greeting still hands over to her shop) and a map change (`transition_started`, `map_left`) closes both |
| `test_shop_ui_window.gd` | canonical stock in order with prices; buy with quantity (mesos, inventory, Events, status, meso display, owned count); insufficient mesos with the numbers; full inventory; the picker's limits; sell from tabs at the canonical sell-back price; selling an equipment slot; every shop renders; unknown shops refused; keys; Space never buys or sells and Enter waits for `confirm_arm_s` (the Buy button never does); modal + window stack; `NpcUi` opens the shop from Lucy's greeting and from `Events.shop_open_requested` |
| `test_loot_system.gd` | `loot_dropped` → records (uid, pos_local, expires_at, owner) + nodes, scatter in m, toss; another map's loot ignored; pos_local in the map frame; pickup into the inventory with notices (single, stack, mesos); inventory full leaves the drop; the canonical box through `WorldScale.actor` and the nearest drop first; the owner window; Z through the player's input source (not under a modal, not on a ladder) and hold-to-repeat; holding Z with a full inventory announces the refusal once and still takes the meso bag next to it; the pickup notices are word for word the HUD's lines (thousands separators); blink then expiry; records expired by the map instance lose their node; leaving and returning keeps drops with their remaining lifetime; expired after a long absence; 20 seeded Snail kills picked up exactly |
| `test_loot_visuals.gd` | `loot_visuals.json` labelled; shapes by canonical type/subtype; keyword tints; meso tiers; a model for every drop-table item and meso tier; toss arc, hover and bob; the blink window |
| `test_interaction_main_flow.gd` | the real game in a child process (`world_ui_main_checks.tscn --scenario main`, see below) |

**Sandbox and headless integration check.** This runs on the real island with the real player, camera, MapSession, the `Game.npc_talk` wiring and real key presses (`Input.parse_input_event`). It prints `CHECK` lines, and with `--quit` it exits non-zero on any failure:

```bash
G="bash scripts/godot.sh --path _scratch/godot_runs/worldui/game"     # after an ISOLATE=worldui INCLUDE_WORLD=1 test run
$G --headless res://scripts/systems/interaction/sandbox/world_ui_sandbox.tscn -- --scenario roger --quit   # 11 checks
$G --headless res://scripts/systems/interaction/sandbox/world_ui_sandbox.tscn -- --scenario shop --quit    # 5 checks
$G --headless res://scripts/systems/interaction/sandbox/world_ui_sandbox.tscn -- --scenario loot --quit    # 6 checks
$G --headless res://scripts/systems/interaction/sandbox/world_ui_sandbox.tscn -- --scenario kills --quit   # 4 checks (needs monster_system.tscn)
$G --resolution 1600x900 --disable-vsync res://scripts/systems/interaction/sandbox/world_ui_sandbox.tscn -- --scenario loot --shot <dir> --crop --quit
$G --resolution 1600x900 res://scripts/systems/interaction/sandbox/world_ui_sandbox.tscn -- --scenario play   # WASD, F, Z, L drops loot, Esc
```

The scenarios:

- **roger:** the Mushroom Town prompt, F, the offer, Y, the apple, the in-progress line, Enter, eating the apple, F, completion and its summary, then Esc through the window stack.
- **shop:** Lucy in the Amherst Department Store: the prompt, F, the greeting, Enter, the shop, buying 3, the Sell tab, then Esc.
- **loot:** 13 drops in Snail Hunting Ground I, the pickup prompt, Z twice, then 000000010 and back with the remaining drops kept.
- **kills:** the monster system's own `kill_all()` in Snail Hunting Ground I. On 2026-10-04, 30 kills gave 28-32 drops through `Events.loot_dropped`, and every one landed as a node and a record in the live map instance. That is the real monster → loot path, end to end.

**The real game (review, 2026-10-04).** The sandbox wires its own `GameContext`; `world_ui_main_checks.tscn` drives
`res://scenes/main.tscn` itself (title → creation → `GameSession` → `SubsystemInstaller`, with the HUD, the monster
system and the death controller) with real key presses, and `test_interaction_main_flow.gd` runs it in a child
process:

```bash
G="bash scripts/godot.sh --path _scratch/godot_runs/<isolate>/game"   # after an ISOLATE=<isolate> INCLUDE_WORLD=1 test run
$G --headless --fixed-fps 60 res://scripts/systems/interaction/sandbox/world_ui_main_checks.tscn -- --scenario main   # 96 checks
$G --resolution 1600x900 --disable-vsync res://scripts/systems/interaction/sandbox/world_ui_main_checks.tscn -- --scenario shots --out <abs dir>
```

`main` covers (96 checks):

- the three subsystems installed by the shell;
- **Roger's Apple:** the prompt, tag and marker; F; Esc through the shell (no pause menu); Y accepts with the summary
  notice; Space on the last line ends the chat without a jump and the keyboard is back right after; the chat sits above
  the HUD's status bar; after eating the apple, F and Enter through the completion page, whose summary reads "Quest
  complete: Roger's Apple" (the quest has no canonical reward);
- a portal prompt with the destination name and Up entering it; a ladder's "[Up] Climb" and F climbing (no chat);
- **Lucy:** greeting → shop; Enter, Space, Enter mashed right after the shop opened buy nothing; Right + Enter buys 2 at
  the canonical price with "Bought Red Potion x2 for 100 mesos."; Space never buys; Tab, 2, Down, Right, Enter sells 2
  back at the canonical 5 mesos each; the Orange Potion with 10 mesos is refused with "(costs 150, you have 10)" and
  the red check line; a full Use tab is refused with "Your inventory is full." and costs nothing; Esc leaves, Esc again
  pauses;
- **Snail Hunting Ground I:** the monster system's real kills land as drops and records; Z with its notice; the map round
  trip; a full Etc tab (the drop stays, one refusal line while Z is held);
- **Sam's Suggestion:** a console `warp`; Sam's prompt and offer with its reward line; Enter on the highlighted Yes
  accepts with the summary; Backspace goes back a page; the console's `kill all` until 10 Snails count; every drop of
  those kills picked up with Z (one notice each); in A Split Road Mai's "?" marker, Enter through the completion page
  ("Quest complete: Sam's Suggestion · +30 EXP, +Egg x3"), 30 EXP and 3 Eggs;
- **robustness:** Rain's quiz menu; held W/S/A/D and the arrows move the highlight and never walk the player;
  Backspace without Back does nothing; Esc ends the quiz (still in progress); Up three times in the menu while standing
  in an Amherst portal moves the highlight and never warps, and after the chat Up enters that portal; a console warp
  with the chat open closes it, and with the shop open closes the shop; a shop request during a chat replaces it and
  one Esc leaves nothing behind; a death in a chat closes it and the respawn hands the keyboard back;
- a death with the shop open; quit to title and continue (the new loot system shows exactly the live instance's
  drops, none after `MapSession.reset()`, and its console commands work).

`shots` writes the prompt over Roger, the dialogue, Lucy's shop, a pickup after real kills, Rain's quiz menu, the Sell
tab and the insufficient-mesos line.

### Visual check (2026-10-04, 1600x900)

- **Prompt.** "[F] Talk to Roger" appears as a dark pill with a key cap above Roger. His gold "!" marker sits above his head and the "Roger" tag under his feet.
- **Dialogue.** The window sits bottom-centre. Roger's own proxy is rendered as the portrait, with the name plate, the QUEST badge and the "Roger's Apple" title. The canonical text is on the paper body, with End Chat, No and Yes, and Yes is highlighted.
- **In-progress line.** "Roger's Apple" shows red (canonical) and blue (item reference), and "Use tab" is bold. Roger's marker has turned to the grey "...". The notice log reads "Quest accepted: Roger's Apple · Received Roger's Apple".
- **Shop.** The window shows Lucy's portrait, "Lucy's Shop", "Grocer · Rainbow Street: Amherst Department Store" and the six canonical rows with icons, prices and owned counts. The detail panel shows the description, "Recovers 250 HP", the picker clamped at the affordable 5 and the total. The status line reads "Bought Orange Potion x3 for 450 mesos.", and the meso display shows 784. The Sell tab shows the Etc sub-tab with "Snail Shell 1 mesos x12".
- **Loot.** Two kills' worth of drops lie in two rows across the screen. In the first: a gold coin pile, an egg, a chest, a red potion, a blue shell pouch, a bronze coin, an amethyst gem. In the second: an arrow bundle, a white box (an undershirt), a scroll, a gold coin, a meso bag, a green chair crate. The "[Z] Pick up Snail Shell" prompt shows above them. After real monster kills, the drops (blue shell pouches, coins, arrows) lie where the snails died.
- **Fixes after the first look:**
  - The first build of the dialogue was a screen-tall empty panel: wrapping RichTextLabels had no width before their first layout. The text column now has a fixed width.
  - Drops were too small at the field camera (0.42 m to 0.58 m).
  - A lone coin standing on its edge read as a stick at most angles; it now lies flat and is larger (0.36 m).
  - The quest marker grew from 34 px to 40 px.
- **Review in the real game (main.tscn, 1600x900).** The prompt, tag and "!" over Roger and Lucy's shop (centred
  above the HUD bar) read well. The dialogue was placed 28 px above the screen bottom, over the HUD's status bar: the
  HP/MP/EXP texts showed through its bottom row and the hint line was unreadable. It now sits above the bar
  (`NpcUi.bottom_inset`), and the gauges stay readable. Loot after real kills shows the pickup prompt and the HUD log
  lines ("You have gained an item (Arrows for Bows)").
- **Second review (main.tscn, 1600x900 and 1280x720).** Rain's quiz: the QUIZ badge, "Rain's Maple Quiz 1", the four
  numbered answers on the paper body with the second highlighted, End Chat and the key hint, above the HUD bar. Lucy's
  Sell tab: the 1-5 sub-tabs with "2 Use" active, "Egg 3 mesos x3", the detail panel with "Sells for: 3 mesos each",
  the picker and the Sell button. The unaffordable Orange Potion: the red total and check line, and the status "You do
  not have enough mesos. (costs 150, you have 10)". One fix: the HUD's arrival banner ("Amherst Department Store")
  showed through the shop's header, because MisoTheme's window body is 0.93 alpha; the NPC windows' frame is now
  opaque. At 1280x720 the `canvas_items` stretch scales both windows and the HUD together, with nothing clipped.

## Known gaps and requested changes

- **The real game has no ladders (another system's gap).** Nothing in the shell or the world runtime registers the
  sidecars' `climbables` with the player (`PlayerController.set_climbables` / `add_climbables_from_sidecar` are called
  only by the player sandbox), so in `main.tscn` `grabbable_climbable()` is always null and no ladder or rope can be
  climbed. The world runtime (or `GameSession`) should hand every chunk's climbables to the player. The main-scene
  check loads them itself to test the climb prompt and F. (Still true on 2026-10-04, second review.)
- **Ladder and portal overlap.** Up and F both grab a ladder and enter a portal when a ladder is in reach inside a portal trigger (controller plus `PortalInteractor`). No map has that overlap, and the prompt shows the ladder.
- **No NPC presentation data file.** NPC presentation constants live in code (cosmetic); a data file could hold them if wanted.
- **An NPC next to a ladder.** An NPC standing within 0.8 m of a ladder's line cannot be talked to from that spot, because F grabs the ladder first.
- **Enter on a Yes/No accepts.** Yes is highlighted on an offer, so Enter (the Next key) accepts a quest; mashing Enter
  through an NPC's pages accepts its offer. Kept: an accepted quest can be forfeited, and Y/N stay explicit. The shop,
  where a press spends mesos, has the arm time instead.
- **The portrait is re-made on every page.** `NpcPortrait.show_speaker` duplicates the NPC's proxy into its SubViewport
  for each view. Cheap for the island's proxies; a cache by NPC id would avoid it.
- **Resolved in the second review (2026-10-04):** the `PortalInteractor` modal workaround is gone (the world's
  interactor applies the rule itself); pickup and expiry use `MapInstanceState.remove_drop` / `expire_drops`; drops no
  longer survive a quit to title (`MapSession.reset()`); the `events.gd` comment on `shop_open_requested` is fixed.
