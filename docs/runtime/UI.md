# HUD and character windows (Iteration Two)

This system is brief Phase 18 (HUD), Phase 17 (quest UI), the Phase 11 inventory UI, the equipment UI and the Phase 6
stat/AP window. It also provides **MisoTheme**, the shared look every MisoStory UI uses. The visual language is
MapleStory-inspired and built entirely in code:

- soft blue-grey translucent windows with light borders and rounded corners;
- a dark title strip with a gold title, orange call-to-action buttons and orange tabs;
- dark recessed content areas;
- outlined text for HUD numbers;
- procedural item icons;
- a gold "LEVEL UP!" with a star burst.

No MapleStory/Nexon sprite, icon, font or sound is used. The only vendored asset is the OFL font Nunito.

The UI only displays state and calls the existing services. It never changes game state by any other route:

- items, equipment and consumables go through `ItemService`;
- AP goes through `Game.allocate_ap`;
- quests are read through `QuestEngine`.

So every change it makes fires the usual `Events`.

## Files

| Path | Class | Role |
|---|---|---|
| `scripts/ui/theme/miso_theme.gd` | `MisoTheme` | The shared `Theme` (cached) plus colours, fonts, style boxes, gauge styling, label helpers, check-box textures |
| `assets/fonts/nunito/` | | `Nunito-Variable.ttf` (google/fonts, unmodified), `OFL.txt`, `SOURCE.md` |
| `scenes/ui/hud.tscn` → `scripts/ui/hud/hud.gd` | `MisoHud` | HUD root, `setup(ctx)` |
| `scripts/ui/hud/status_bar.gd` | `MisoStatusBar` | Bottom bar: level, name, job, HP/MP/EXP gauges, mesos, window buttons, quickslots |
| `scripts/ui/hud/quickslot_bar.gd` | `MisoQuickslotBar` | The 8 quickslots (bind by drop, use, move, clear) |
| `scripts/ui/hud/notice_log.gd` | `MisoNoticeLog` | Message log (fading lines + history) |
| `scripts/ui/hud/map_banner.gd` | `MisoMapBanner` | Street + map name on arrival |
| `scripts/ui/hud/level_up_flourish.gd` | `MisoLevelUpFlourish` | "LEVEL UP!" pop with procedural stars |
| `scenes/ui/windows.tscn` → `scripts/ui/windows/windows_root.gd` | `MisoWindowsRoot` | Windows root, `setup(ctx)`, hotkeys, shared tooltip |
| `scripts/ui/windows/inventory_window.gd` | `MisoInventoryWindow` | Item Inventory (I) |
| `scripts/ui/windows/equipment_window.gd` + `doll_backdrop.gd` | `MisoEquipmentWindow`, `MisoDollBackdrop` | Equipment (E) |
| `scripts/ui/windows/stats_window.gd` | `MisoStatsWindow` | Character Stats (C) |
| `scripts/ui/windows/quest_window.gd` | `MisoQuestWindow` | Quest Log (Q / L) |
| `scripts/ui/common/ui_env.gd` | `MisoUiEnv` | Resolves character / content / bus / game / quest engine / ctx for in-game, standalone and tests |
| `scripts/ui/common/miso_window.gd` | `MisoWindow` | Base window: title strip, key hint, close, drag, clamp, ctx registration, status line |
| `scripts/ui/common/item_slot.gd` | `MisoItemSlot` | One item square: icon, count, caption, key label, click/double-click/right-click/hover, drag-and-drop hooks |
| `scripts/ui/common/item_icon.gd` | `MisoItemIcon` | Procedural item icon (shape per category/item, tint from the name) |
| `scripts/ui/common/item_tooltip.gd` | `MisoItemTooltip` | Inspect card; `describe()` is the pure part |
| `scripts/ui/common/gauge.gd` | `MisoGauge` | Bar + tag + outlined value text |
| `scripts/ui/common/coin_icon.gd` | `MisoCoinIcon` | Procedural meso coin |
| `scripts/ui/common/quickslots.gd` | `MisoQuickslots` | Quickslot bindings in `CharacterState.quickslots` (bind / unbind / move / use / notify) |
| `scripts/ui/common/ui_text.gd` | `MisoUiText` | Player-facing wording: result messages, log lines, objective rows |
| `scripts/ui/common/sandbox/ui_sandbox.tscn` | | UI sandbox (populated character, screenshots) |
| `scripts/ui/common/sandbox/ui_game_check.tscn` | | Screenshot check through the real game shell (`main.tscn`) |
| `tests/unit/test_ui_theme.gd`, `test_ui_hud.gd`, `test_ui_windows.gd` | | 30 tests |

## Integration (game shell)

`SubsystemInstaller` already does what is needed:

1. It instantiates `res://scenes/ui/hud.tscn` (root `MisoHud`) and `res://scenes/ui/windows.tscn` (root
   `MisoWindowsRoot`) under `ctx.ui_root`, HUD first so windows draw above it.
2. It calls `setup(ctx)` on each.

`setup(ctx)` builds a `MisoUiEnv.from_ctx(ctx)` and connects to the `Events` autoload and to `Game.character_replaced`.
It reads `Game.character`, `Data.db`, `Game.quests` and `MapSession.current_map` live, then redraws. It may be called
before or after the node enters the tree, and calling it again rebinds cleanly. `_exit_tree` disconnects everything;
re-entering the tree (a reparent) reconnects and redraws.

- **Esc.** The shell's `menu` handler calls `ctx.close_top_window()`. Every window registers with
  `ctx.window_opened(w)` when it opens or is clicked, and with `ctx.window_closed(w)` when it closes. Each window has
  `close()`, so Esc closes the newest window first.
- **No modal.** No window calls `push_modal`, so the player can walk with windows open, as in classic. While any
  modal is active (dialogue, shop, console, pause menu), the HUD's quickslot keys and the windows' `toggle_*` keys do
  nothing.
- **Standalone.** Without `setup()`, a root configures itself in `_ready` with `MisoUiEnv.standalone()`: the
  autoloads plus a private `GameContext`. It then handles Esc itself (`env.owns_ctx`).
- **Other UI.** Other UI can open windows without a reference:
  `get_tree().call_group(&"miso_windows", &"toggle_window", "inventory")`. The window names are `inventory`,
  `equipment`, `stats` and `quests`. `open_window`, `close_window`, `is_open` and `close_all` are also available. The
  HUD's buttons use this group, and fall back to sending the `toggle_*` input action.
- **Theme for other systems.** Set `root_control.theme = MisoTheme.get_theme()`, then use the type variations below.

## Data flow

```
Events (hp/mp/exp/level/mesos/stats/inventory/equipment/item/quest/map/notice/game_loaded) ──► MisoHud / MisoWindowsRoot
Game.character_replaced ─────────────────────────────────────────────────────────────────────► full redraw
                       │ every redraw re-reads: MisoUiEnv.character() (Game.character), Data.db
                       ▼
StatCalculator.snapshot / max_hp / max_mp · Progression.exp_to_next · Inventory.slots · Equipment.instance_in /
total_bonuses · QuestEngine.quest_summaries / quest_summary / is_available / definition · ItemDef.of
                       │ player actions
                       ▼
ItemService.use_item / equip / unequip / move (inventory, equipment, quickslots)   Game.allocate_ap (stats "+")
MisoQuickslots.bind/unbind/move → CharacterState.quickslots ("1".."8" → item id)    Events.notice (failures)
                       │
                       ▼ Events fire from the services → HUD, windows, quests and saves all update
```

The HUD shows the `hp_changed` and `mp_changed` payloads as they arrive (they are the emitter's facts). Every other
value is re-read from the character on each event. No character object is cached.

## Public API

### MisoTheme (`class_name MisoTheme`, all static)

- `get_theme() -> Theme` (cached) and `reset_cache()`.
- Fonts: `font(weight)`, `bold_font()`, `black_font()`. These are Nunito on the `wght` axis (`WEIGHT_REGULAR` 600,
  `WEIGHT_BOLD` 800, `WEIGHT_BLACK` 900). If the font cannot be loaded, the engine default font is used, emboldened.
- Style boxes:
  - `flat(bg, border_color, border, radius, margin)`;
  - `panel_style(kind)`, where kind is `window`, `inset`, `slot`, `slot_hover`, `slot_selected`, `hud`, `tooltip`,
    `banner` or `notice`;
  - `title_bar_style()`;
  - `button_style(state, accent)`;
  - `gauge_styles(color)` and `style_gauge(bar, color)`.
- Labels and helpers: `make_label(text, size, color, outline, weight)`, `style_label(...)`, `thousands(n)`
  ("1,234,567") and `check_texture(checked)`.
- Colours: `PANEL`, `PANEL_BORDER`, `INSET`, `TITLE_BAR`, `HUD_BG`, `ACCENT`, `ACCENT_LIGHT`, `ACCENT_DARK`, `GOLD`,
  `TEXT`, `TEXT_DIM`, `OUTLINE`, `BAD`, `GOOD`, `HP`, `MP`, `EXP`, `SLOT*` and the `LOG_*` line colours.
- Type variations (set `Control.theme_type_variation`):
  - Labels: `MisoTitle`, `MisoHeading`, `MisoDim`, `MisoSmall`, `MisoGold`, `MisoBad`, `MisoGood`, `MisoHudNumber`.
  - Panels: `MisoWindow`, `MisoInset`, `MisoSlot`, `MisoHud`, `MisoTitleBar`, `MisoTooltip`, `MisoBanner`,
    `MisoNotice`.
  - Buttons: `MisoAccentButton`, `MisoCloseButton`, `MisoTabButton`, `MisoFlatButton`.
- The theme also styles TabBar/TabContainer, ProgressBar, LineEdit/TextEdit, RichTextLabel, ItemList, PopupMenu,
  separators, scroll bars and CheckBox.

### MisoUiEnv

- Constructors: `from_ctx(ctx)`, `standalone()` and `isolated(character, db, bus, ctx := null, game := null)`. The
  last one is for tests and never looks up autoloads.
- Accessors:
  - `character()`, `get_db()`, `get_bus()`, `get_game()`;
  - `items()`, which returns a fresh `ItemService` on the live character;
  - `quest_service()` (`Game.quests`);
  - `quest_engine()`, a read-only engine on the live character that shares `Game.quests`' catalog;
  - `current_map_id()`.
- Actions: `allocate_ap(stat, n)`, `request_autosave(reason)`, `notice(text)`, `emit(sig, args)`.
- Context: `window_opened(w)`, `window_closed(w)`, `is_modal_active()`.
- Static: `key_label(action)`, which gives the first key bound to an InputMap action, and
  `release_attack_action()`, which item and window drags call when they start (see "Known gaps").

### Roots

- **`MisoHud`**:
  - `setup(ctx)`, `configure(env)`, `refresh_all()`;
  - `use_quickslot(key) -> Dictionary`;
  - `request_window(name)`;
  - parts: `status`, `log_panel`, `banner`, `flourish`, `tooltip`.
- **`MisoWindowsRoot`**:
  - `setup(ctx)`, `configure(env)`;
  - `window_by_name(name)`, `open_window`, `close_window`, `toggle_window`, `is_open`, `close_all`, `refresh_open`;
  - `default_position(name)` and `window_width(name)` (the first-open placement);
  - `show_item_tooltip(item_id, opts, anchor)` and `hide_item_tooltip()`;
  - the windows: `inventory`, `equipment`, `stats`, `quests`.

### Windows

- **`MisoWindow`** (base): `open()` (opens, or brings to the front), `close()`, `toggle()`, `refresh()`,
  `is_open()`, `focus_window()` (front + newest in the stack), `is_frontmost_at(point)`, `add_status_line()`,
  `set_status(text, bad)` and `static make_button(text, variation)`. Every button uses `FOCUS_NONE`, so Space and
  Enter never re-press a UI button while the player jumps.
- **`MisoInventoryWindow`**: `select_tab(tab)`, `select_slot(i)`, `activate_slot(i) -> result` (use or equip),
  `assign_quickslot(key)` and `visible_item_ids()`. Tabs come from `Inventory.TABS`; the slot count from
  `Inventory.capacity(tab)`.
- **`MisoEquipmentWindow`**: `unequip_slot(slot) -> result`, `equip_from_inventory(item_id, index) -> result` and
  `bonus_lines()`. Slots come from `ItemsConfig.equipment_slots(db)`; a slot the layout does not know is still
  placed, in the bottom rows.
- **`MisoStatsWindow`**: `add_point(stat) -> bool`, `value_text(key)` and `static allocatable_stats(db)` (canonical
  `beginner.json ap.allocatable_stats`).
- **`MisoQuestWindow`**: `select_tab("in_progress" | "available" | "completed")`, `select_quest(id)`,
  `objective_rows()` and `detail_texts()`.

## What the player sees and does

**HUD.**
- **Status bar.** Lv. (gold), name, job (canonical `formulas/<job>.json name`); HP and MP gauges with "cur / max"; the
  EXP gauge with "cur / needed [12.34%]" ("MAX" at the cap); mesos with a coin.
- **Window buttons.** `Item [I]`, `Equip [E]`, `Stat [C]`, `Quest [Q]`. Each key label comes from the InputMap. While
  AP is unspent, the Stat button turns orange and reads `Stat [C] +5`.
- **Quickslots.** Eight slots, 1-8:
  - each shows the key, the icon, and the inventory count (0 = greyed);
  - press the key or double-click the slot to use it;
  - drop a consumable from the inventory on a slot to bind it;
  - drag between slots to move a binding; right-click to clear it.

**Message log.** Fading lines above the bar:

| Event | Line |
|---|---|
| `item_gained` | "You have gained an item (Red Potion x5)" |
| `mesos_changed` | "You have gained mesos (+12)" when delta > 0; "You have spent 50 mesos." when delta < 0; nothing for delta 0 (a refresh) |
| `exp_gained` | "You have gained experience (+15)" |
| `leveled_up` | "Congratulations! You have reached level N." plus "You have N AP to distribute (press C)." |
| `quest_started`, `quest_completed`, `quest_forfeited` | "Quest started: ...", "Quest complete: ...", "Quest forfeited: ..." |
| `quest_progressed` | "Sam's Suggestion: Snail 7/10". The HUD compares objective counts with the last ones it saw, so the line names what moved |
| `inventory_full` | "Your inventory is full." |
| `player_died` | "You have died." |
| `notice` | The text as given |

An identical line within 1.5 s is dropped, so holding pickup at a full bag does not spam.

**Banner and flourish.** On `map_entered` the banner shows the canonical `street_name` above `name`, then fades. On
`leveled_up`, the flourish shows "LEVEL UP!", "Level N" and a star burst.

**Inventory (I).** Five tabs, a 4-column grid, stack counts, the selected slot outlined in orange, and mesos.
- Double-click, Enter or the action button uses or equips the item.
- Dragging onto another slot of the same tab moves, merges or swaps it (`ItemService.move`).
- `Set key` (or a right-click) shows the 1-8 picker for a consumable.
- Failures show red in the window's status line and go to the HUD log, for example "You need to be level 30 to equip
  that." or "Your Equip inventory is full."

**Equipment (E).** A paper doll of every slot, with a faint procedural figure behind it.
- Double-click a piece to take it off. With a full Equip tab this fails, the piece stays on, and the message says
  why.
- Drop equipment from the inventory on its slot to equip it.
- Below the doll, "Equipment bonuses" lists `Equipment.total_bonuses`.

**Character Stats (C).**
- Name, Job, Level, EXP "cur / needed (pct)", HP, MP, Fame.
- Ability Points (gold while above 0), and STR/DEX/INT/LUK as total, with "(base + bonus)" when gear adds to it.
- An orange "+" per allocatable stat while AP > 0.
- Damage "min ~ max" (the `StatCalculator` stat window), ACC, AVOID, W.DEF, M.DEF, Magic (`matk`, MagicTotal),
  Speed %, Jump %.

**Quest Log (Q / L).** In Progress, Available and Completed tabs, each with a count.
- In Progress entries that are ready to turn in show "[ready]".
- Available lists quests the character can accept now (`QuestEngine.is_available`). Quests whose start NPC stands on
  the current map come first, marked "[nearby]".
- The detail pane shows:
  - name, status, start NPC and turn-in NPC;
  - the journal text (`QuestEngine.journal_text`);
  - objectives with ticks and counts ("Snail 7/10", "Return to Mai", "Use Roger's Apple 0/1", "Answer the quiz");
  - canonical rewards: EXP, mesos, fame, items with icons, "One of these at random" and "Choose one" groups.

**Tooltip.** Hovering an inventory slot, an equipped piece or a quickslot shows:
- icon, name (with quantity), category and subtype;
- "Equipped", "Quest item" and "Untradeable" flags;
- requirements (REQ LEV/STR/DEX/INT/LUK/POP/JOB and gender), each **red when unmet** (total stats, the same basis as
  `Equipment.equip_check`);
- attack speed; stat lines in green (from instance data when a piece has scroll results); upgrades available;
- consumable effects (flat and % HP/MP, buffs, pet fullness, chair recovery);
- the canonical description, the sell price ("Sells for 25 mesos each"), and an action hint.

## Decisions and adaptations

No gameplay number lives in this system. Every number shown is read from canonical data or a service:

- tab sizes: `Inventory.capacity`;
- slot list: `ItemsConfig`;
- EXP needed: `Progression.exp_to_next`;
- derived stats: `StatCalculator`;
- AP stats: canonical `ap.allocatable_stats`;
- rewards: `QuestDef`;
- prices and effects: `ItemDef`.

So nothing here goes in `data/misostory/`. The constants that do live in code are presentation choices, not gameplay
values: layout sizes, fade timings, colours, the doll layout, log limits and wording. Each is a named constant with a
doc comment.

| Decision | Why |
|---|---|
| Item icons are procedural: a shape from type, subtype, equip slot and name keywords (potion, apple, sword, skullcap, shirt, shell, gem ...); the tint is the colour word in the name ("Red", "Amethyst", "Jean"), else a stable hue from the id | No proprietary icons may be used. `test_every_canonical_item_has_a_procedural_icon` fails if a new item kind has no shape |
| Font: Nunito (OFL), vendored with its license | A rounded, friendly sans close in spirit to the classic UI, and legally redistributable |
| Quickslot keys are `"1".."8"`, the suffix of the `quickslot_N` actions, stored as `CharacterState.quickslots[key] = item_id` | Matches the save tests (`test_save_roundtrip`). The count comes from the InputMap (8 by the Controls contract) |
| Only consumables (`ItemDef.is_consumable`) can be bound; an empty stack keeps its binding (greyed, count 0) and refills on pickup | Classic behaviour. Pressing an empty slot says "You have no X left." |
| A single click on a quickslot does nothing; double-click or the key uses it | A press would otherwise fire on the start of every drag |
| Binding changes notify the group `miso_quickslot_listeners` (`refresh_quickslots()`) instead of an `Events` signal | `events.gd` is a fixed contract and has no quickslot signal; HUD and inventory are separate scenes |
| Requirement colouring uses total stats | The same basis as `Equipment.equip_check` (ITEMS.md "Requirement basis") |
| "Shops will not buy this" when `sell_price_mesos` is null | `ShopService` refuses those (`no_sell_price`) |
| "Nearby" means the quest's start NPC (`npcs/<id>.json map_id`) is on `MapSession.current_map` | The brief asks for nearby available quests; MeowDB places NPCs by map |
| Log wording ("You have gained an item (...)") is MapleStory-inspired | MeowDB publishes no client messages. The wording is presentation, not canonical text |
| Windows first open side by side, placed from their measured widths: Character Stats then the Quest Log from the left edge, the Item Inventory then Equipment from the right edge (classic: bags on the right). The four never overlap on the 1600 x 900 base viewport or anything wider. They are draggable by the title strip and clamped so it stays on screen | Presentation. The first version used screen fractions, and the Equipment window then covered the Quest Log's right edge (its key hint, close button and journal text) |
| A press anywhere inside a window (its slots and buttons included) brings it to the front and makes it "newest" for Esc | Classic focus behaviour; Esc closes what the player touched last. Slots and buttons stop the mouse event, so this is done in `MisoWindow._input` from the frontmost control under the pointer |

## Testing

```bash
ISOLATE=hud bash scripts/test.sh test_ui_                   # this system: 30 tests
ISOLATE=hud INCLUDE_WORLD=1 bash scripts/test.sh            # everything
```

| File | Covers |
|---|---|
| `test_ui_theme.gd` | The theme builds and caches; every type variation is registered with the right base; the vendored Nunito loads (not the fallback) with its OFL text; weights differ; helpers (`thousands`, labels, gauges, check textures, panel and button styles) |
| `test_ui_hud.gd` | `hud.tscn` root has `setup`; initial values from the character (level, name, canonical job name, HP/MP, mesos separators, EXP percent, 8 quickslots); values follow `hp_changed`, `mp_changed`, `mesos_changed` (no line for delta 0), `exp_gained`, `item_gained`, `inventory_full`, `notice`, `equipment_changed`; level-up flourish and the AP highlight; map banner (canonical street and name, fade timeline); log cap, history, dedupe, fade; quickslot bind → use → count decrements → HP restored → `item_used` → the key path → JSON save round trip keeps the binding → empty stack greys out with a notice; non-consumables refused; drop, move, unbind; quest progress lines through a real `QuestService`; leaving and re-entering the tree keeps listening and redraws; no character or content: nothing breaks |
| `test_ui_windows.gd` | `windows.tscn` root has `setup` and four closed windows; inventory tabs and slots from the live inventory, counts, mesos, live refresh on pickup; use and equip through `ItemService` (`item_used`, `equipment_changed`, previous weapon back in the bag), a level-requirement refusal with message and notice, Etc not usable; quickslot assignment and drag-move (`ItemService.move`); equipment doll covers every slot, W.ATK contribution, unequip with a full Equip tab refused gracefully, then unequip and re-equip by drop; stats window: "+" only with AP, every derived value equals `StatCalculator.snapshot`, `Game.allocate_ap` (a real `GameState` on a private bus) spends AP and moves the damage range, "+" hidden at 0 AP; quest log: Sam's Suggestion available, then "Snail 7/10" after 7 `monster_killed` events through an attached `QuestService`, the turn-in row, the canonical EXP and item rewards, capped and ticked at 10/10; the ctx window stack (newest closes first, re-focus, close button, `window_changed`); hotkeys toggle and stay quiet under a modal; HUD buttons open windows through the group; standalone Esc; the four default window rects are disjoint and on screen whatever the opening order; a real mouse press on a slot of a back window (`Viewport.push_input`) makes it the newest, so Esc closes it first; dragging a window by its title follows the pointer, clamps at the edges and releases the attack action; a UI drag releases a mouse-held attack; tooltip rows (unmet requirement red, met plain, effect, price, description) and hover in the window; every canonical item has an icon shape |

All UI tests use a private `events.gd` bus and `MisoUiEnv.isolated(...)`. They never read or change autoload state.
Nodes go under the running scene and are freed after each test.

### Looking at it

The UI sandbox shows a populated character: level 5→6 with 25 AP, potions and food, Etc items, worn and carried
gear, mesos, four quickslots, Sam's Suggestion at 7/10 and one quest completed. Its backdrop is a bright procedural
landscape. Run it from an ISOLATE copy:

```bash
ISOLATE=hud bash scripts/test.sh test_ui_theme              # refresh the private copy + import
bash scripts/godot.sh --path _scratch/godot_runs/hud/game --resolution 1600x900 --disable-vsync \
    res://scripts/ui/common/sandbox/ui_sandbox.tscn                         # interactive
bash scripts/godot.sh --path _scratch/godot_runs/hud/game --resolution 1600x900 --disable-vsync \
    res://scripts/ui/common/sandbox/ui_sandbox.tscn -- --shots <abs dir>    # hud.png, windows_a.png, windows_b.png
```

The sandbox assigns `Game.character` directly and never calls `Game.new_game`, so it writes no save. In it, I/E/C/Q
open windows, 1-8 use quickslots, Esc closes the newest window, F1 levels up, F2 shows a banner and F4 adds a notice.

`ui_game_check.tscn` runs the real `main.tscn` with a quick-start game, takes `game_hud.png` and `game_windows.png`
(all four windows at their default places) and quits. That game is the real path: `SubsystemInstaller` and
`setup(ctx)` over the island. Starting a game writes a save, so the scene refuses to run unless the copy's
`project.godot` sets `application/config/use_custom_user_dir=true` and a `custom_user_dir_name`. Set that in the
ISOLATE copy only.

**Review (iteration 2).** An adversarial review drove the real `main.tscn` (quick start) with real input events
(`Input.parse_input_event`: keys, mouse moves, clicks, double-clicks, right-clicks and drags) through 63 checks: the
installer and `setup(ctx)`, HUD values, I/E/C/Q and Esc (newest window first, then pause, nothing while paused),
quickslot keys, hover tooltips, equip by double-click, drag to a quickslot, the "+" buttons, a click on a back window,
title drags, the close button, right-click clear, quest progress, save and load (bindings, HUD, windows), death
(modal: quickslots and hotkeys quiet), banner and flourish fades, and no swing from any of it. It found and fixed:
overlapping default window positions, swings while dragging an item or a window, a back window not raised by a click
on its slots or buttons, title dragging that read the OS cursor instead of the event, and the roots staying
disconnected after a reparent.

## Known gaps and requests

- **The left mouse button is also "attack".** `PlayerCombat` (combat system) ignores the button while the pointer
  is over a control, sampled on its physics tick. Two holes remain on its side:
  - **Drags.** An item dragged from the inventory to a quickslot, or a window dragged by its title and clamped at a
    screen edge, crosses the world with the button held, and the character swung all the way. Workaround here:
    both drags call `MisoUiEnv.release_attack_action()` when they start (`Input.action_release("attack")`; the next
    real press re-arms it). Requested: `PlayerCombat._clicking_ui()` should also return true while
    `get_viewport().gui_is_dragging()`.
  - **Very short clicks.** The guard reads `Input.is_mouse_button_pressed` on the physics tick. A click whose press
    and release both fall between two ticks (shorter than about 17 ms) is seen as `just_pressed` with the button
    already up, so a click on a window swings once. Human clicks (about 60 ms or more) did not swing in the
    real-game check. Requested: take the mouse attack from `_unhandled_input` (GUI-consumed presses never arrive),
    or record whether the pointer was over a control when the press happened.
- **Built-in tooltips may use the default theme.** Plain `tooltip_text` (close buttons, "+" buttons) is drawn by
  Godot's tooltip popup, and that may not inherit a Control's theme. This is unverified (no screenshot was taken of
  it). Setting `get_tree().root.theme = MisoTheme.get_theme()` once at boot (shell) would give every popup and screen
  the MisoStory look either way.
- **Quickslots hold consumables only.** Skills will need the same `CharacterState.quickslots` map with a typed value
  (for example `{"kind": "skill", "id"}`). `MisoQuickslots.item_for` already reads ids defensively.
- **Not built.** Dropping or discarding items, item sorting, a split-stack dialog and a forfeit button in the quest
  log. `QuestService.forfeit` exists, but the brief does not ask for this.
- **Sandbox location.** The sandbox scenes live under `scripts/ui/common/sandbox/`, because this system owns no path
  under `scenes/sandbox/`.
