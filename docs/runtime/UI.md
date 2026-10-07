# HUD and character windows (Iterations Two and Three)

This system is brief Phase 18 (HUD), Phase 17 (quest UI), the Phase 11 inventory UI, the equipment UI and the Phase 6
stat/AP window. Iteration Three adds the **minimap** (Iteration Three brief Phase 11, "Minimap" below), the
persistent map name, the **Skills window** (K) with skill quickslots, chairs in the inventory's Set-up tab, and the
Quest Log's chain progress, NPC maps and Missable tag. It also provides **MisoTheme**, the shared look every MisoStory UI uses. The visual language is
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
| `scripts/ui/hud/quickslot_bar.gd` | `MisoQuickslotBar` | The 8 quickslots (bind by drop, use, move, clear); item slots and skill slots (icon, MP greying, cooldown sweep) |
| `scripts/ui/hud/effects_bar.gd` | `MisoEffectsBar` | Active timed effects (Nimble Feet, Recovery) on top of the status bar: icon, time left, run-out sweep |
| `scripts/ui/hud/notice_log.gd` | `MisoNoticeLog` | Message log (fading lines + history) |
| `scripts/ui/hud/map_banner.gd` | `MisoMapBanner` | Street + map name on arrival; on a trail, the "-> destination" line under the map name |
| `scripts/ui/hud/level_up_flourish.gd` | `MisoLevelUpFlourish` | "LEVEL UP!" pop with procedural stars |
| `scenes/ui/windows.tscn` → `scripts/ui/windows/windows_root.gd` | `MisoWindowsRoot` | Windows root, `setup(ctx)`, hotkeys, shared tooltip |
| `scripts/ui/windows/inventory_window.gd` | `MisoInventoryWindow` | Item Inventory (I) |
| `scripts/ui/windows/equipment_window.gd` + `doll_backdrop.gd` | `MisoEquipmentWindow`, `MisoDollBackdrop` | Equipment (E) |
| `scripts/ui/windows/stats_window.gd` | `MisoStatsWindow` | Character Stats (C) |
| `scripts/ui/windows/quest_window.gd` | `MisoQuestWindow` | Quest Log (Q / L) |
| `scripts/ui/windows/forfeit_prompt.gd` | `MisoForfeitPrompt` | The Quest Log's "Forfeit quest?" confirmation (modal, Forfeit / Cancel) |
| `scripts/ui/windows/skills_window.gd` | `MisoSkillsWindow` | Skills (K): levels, SP, "+", description, Set key, drag to a quickslot |
| `scripts/ui/common/ui_env.gd` | `MisoUiEnv` | Resolves character / content / bus / game / map session / quest engine / ctx / UI preferences file for in-game, standalone and tests |
| `scripts/ui/common/ui_prefs.gd` | `MisoUiPrefs` | The player's UI preferences on this machine (the minimap's fold), a ConfigFile beside the save slots |
| `scripts/ui/common/miso_window.gd` | `MisoWindow` | Base window: title strip, key hint, close, drag, clamp, ctx registration, status line |
| `scripts/ui/common/item_slot.gd` | `MisoItemSlot` | One item square: icon, count, caption, key label, click/double-click/right-click/hover, drag-and-drop hooks |
| `scripts/ui/common/item_icon.gd` | `MisoItemIcon` | Procedural item icon (shape per category/item, tint from the name) |
| `scripts/ui/common/skill_icon.gd` | `MisoSkillIcon` | Procedural skill icon (shells, heart, winged boot) with the dim and cooldown-sweep overlays |
| `scripts/ui/common/item_tooltip.gd` | `MisoItemTooltip` | Inspect card; `describe()` is the pure part |
| `scripts/ui/common/gauge.gd` | `MisoGauge` | Bar + tag + outlined value text |
| `scripts/ui/common/coin_icon.gd` | `MisoCoinIcon` | Procedural meso coin |
| `scripts/ui/common/quickslots.gd` | `MisoQuickslots` | Typed quickslot bindings in `CharacterState.quickslots` (bind / bind_skill / unbind / move / use / notify) |
| `scripts/ui/common/ui_text.gd` | `MisoUiText` | Player-facing wording: result messages, log lines, objective rows |
| `scripts/ui/common/sandbox/ui_sandbox.tscn` | | UI sandbox (populated character, screenshots) |
| `scripts/ui/common/sandbox/ui_game_check.tscn` | | Screenshot check through the real game shell (`main.tscn`) |
| `scenes/ui/minimap.tscn` → `scripts/ui/minimap/minimap.gd` | `MisoMinimap` | Minimap root, `setup(ctx)`: title strip (street, map name, debug map id), M, the picture, `snapshot()` |
| `scripts/ui/minimap/minimap_view.gd` | `MisoMinimapView` | The picture: ground meshes by tier, portals, NPC dots, the player's arrow, labels, hover text |
| `scripts/ui/minimap/minimap_model.gd` | `MinimapModel` | Pure: what the minimap shows for one map (ground, portals, NPCs, climbables, trails), in minimap metres |
| `scripts/ui/minimap/minimap_projection.gd` | `MinimapProjection` | Pure: world point → the gameplay camera's image plane; fit, clamp |
| `scripts/ui/minimap/map_icons.gd` | `MapIcons` | Procedural icons (coin, boat, swirl, door, arrow, quest dot) and an NPC's role icon; shared with the NPC name tags |
| `tests/unit/test_ui_theme.gd`, `test_ui_hud.gd`, `test_ui_windows.gd`, `test_ui_drag_attack.gd` | | 38 tests |
| `tests/unit/test_skills_ui.gd` | | the Skills window, typed quickslots, skill slots, chairs, held skill keys (#20: one cast per lockout, one refusal notice per hold, items once per press), the five window positions (10 tests) |
| `tests/unit/test_ui_window_fit.gd` | | every window (and the largest shop) with its largest content inside exactly 1600 x 900 and off the HUD's status bar; the Skills window keeps one size and opens clear of the Quest Log (every pair's overlap printed and bounded); the effects row on top of the bar, 40 px icons, covering no gauge, button or quickslot; a window that grows, a drag and a smaller viewport are clamped back (8 tests) |
| `tests/unit/test_ui_minimap.gd`, `test_ui_minimap_projection.gd`, `test_ui_minimap_world.gd`, `test_ui_minimap_feedback.gd` | | the minimap and the world feedback (see "Testing") |

## Integration (game shell)

`SubsystemInstaller` already does what is needed:

1. It instantiates `res://scenes/ui/hud.tscn` (root `MisoHud`), `res://scenes/ui/minimap.tscn` (root
   `MisoMinimap`) and `res://scenes/ui/windows.tscn` (root `MisoWindowsRoot`) under `ctx.ui_root`, in that order, so
   windows draw above the minimap and the minimap above the HUD.
2. It calls `setup(ctx)` on each. The minimap also takes `ctx.world` (the map definitions and their ground),
   `ctx.player` and `ctx.camera` from the context.

`setup(ctx)` builds a `MisoUiEnv.from_ctx(ctx)` and connects to the `Events` autoload and to `Game.character_replaced`
(the HUD also to `MapSession.trail_changed`). It reads `Game.character`, `Data.db`, `Game.quests`,
`MapSession.current_map` and `MapSession.trail_destination` live, then redraws. It may be called
before or after the node enters the tree, and calling it again rebinds cleanly. `_exit_tree` disconnects everything;
re-entering the tree (a reparent) reconnects and redraws.

- **Esc.** The shell's `menu` handler calls `ctx.close_top_window()`. Every window registers with
  `ctx.window_opened(w)` when it opens or is clicked, and with `ctx.window_closed(w)` when it closes. Each window has
  `close()`, so Esc closes the newest window first.
- **No modal.** No window calls `push_modal`, so the player can walk with windows open, as in classic. The one
  exception is the Quest Log's forfeit question (`MisoForfeitPrompt`), modal only while it asks. While any
  modal is active (dialogue, shop, console, pause menu), the HUD's quickslot keys and the windows' `toggle_*` keys do
  nothing.
- **Standalone.** Without `setup()`, a root configures itself in `_ready` with `MisoUiEnv.standalone()`: the
  autoloads plus a private `GameContext`. It then handles Esc itself (`env.owns_ctx`).
- **Other UI.** Other UI can open windows without a reference:
  `get_tree().call_group(&"miso_windows", &"toggle_window", "inventory")`. The window names are `inventory`,
  `equipment`, `stats` and `quests`. `open_window`, `close_window`, `is_open` and `close_all` are also available. The
  HUD's buttons use this group, and fall back to sending the `toggle_*` input action.
- **Theme for other systems.** Set `root_control.theme = MisoTheme.get_theme()`, then use the type variations below.
  The shell also puts it on the root window at boot (`MainShell.apply_ui_theme`, GAME_SHELL.md), so Godot's built-in
  tooltip popups (plain `tooltip_text` on close and "+" buttons) share the look.

## Data flow

```
Events (hp/mp/exp/level/mesos/stats/inventory/equipment/item/quest/map/notice/game_loaded) ──► MisoHud / MisoWindowsRoot
Events.player_died / player_respawned ───────────────────────────────────────────────────────► MisoHud (HP gauge at 0 between them)
MapSession.trail_changed(dest_map_id) ───────────────────────────────────────────────────────► MisoHud (trail line, "" clears it)
Game.character_replaced ─────────────────────────────────────────────────────────────────────► full redraw
                       │ every redraw re-reads: MisoUiEnv.character() (Game.character), Data.db,
                       │ MapSession.current_map / trail_destination (the HUD's trail line)
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

The HUD shows the `hp_changed` and `mp_changed` payloads as they arrive (they are the emitter's facts), with one
exception: between `Events.player_died` and `Events.player_respawned` the HP gauge reads `0 / max`. A committed death
already holds the respawn HP (GAME_SHELL.md "Death and respawn"), so any refresh while the death notice is up
(`stats_changed`, `hp_changed`, `equipment_changed` ...) would otherwise show it. On `player_respawned` (the respawn
finished, the console's respawn out of `DEAD`, or a load out of `DEAD` once it completes) the HUD redraws from the
character. A replaced character
(`Game.character_replaced`) is not the one that died: the flag is re-read from `Game.is_character_dead()`. A load out
of a death (the console's `load` under the death notice) therefore shows the loaded character's HP from the start of
the load, not from its end: `MapSession` hears `character_replaced` first and has already left `DEAD` for the load's
warp (seen in the real game: `WARP_OUT`, the gauge at the loaded HP, the notice still up until `player_respawned`).
The gauge stays at 0 only while the game still says dead (a load `MapSession` refused, a character at HP 0), and a
HUD set up during a death starts at 0. The flag is never kept regardless of the game: a load queued behind a warp the
player died in runs from `IDLE`, and no `player_respawned` would clear it. Every other value is re-read from the
character on each event. No character object is cached.

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
- Injection: `map_session` (null = the `MapSession` autoload; tests set a private `map_session.gd` instance) and
  `prefs_path` (the UI preferences file; "" = `ui_prefs_path()`'s default).
- Accessors:
  - `character()`, `get_db()`, `get_bus()`, `get_game()`, `get_map_session()`;
  - `items()`, which returns a fresh `ItemService` on the live character;
  - `quest_service()` (`Game.quests`);
  - `quest_engine()`, a read-only engine on the live character that shares `Game.quests`' catalog;
  - `current_map_id()` and `trail_destination()` (`MapSession.trail_destination`, "" off trails);
  - `is_character_dead(fallback := false)`: `Game.is_character_dead()`, or `fallback` without a game that can tell;
  - `ui_prefs_path()`: `prefs_path`, else `ui_prefs.cfg` in the `Saves` autoload's `save_dir`, else "" (an isolated
    env keeps nothing).
- Actions: `allocate_ap(stat, n)`, `request_autosave(reason)`, `notice(text)`, `emit(sig, args)`.
- Signals: `connect_bus` / `disconnect_bus` (Events), `connect_session` / `disconnect_session` (the map session's
  `trail_changed`), `connect_character_replaced` / `disconnect_character_replaced`. All idempotent and null-safe.
- Context: `window_opened(w)`, `window_closed(w)`, `is_modal_active()`.
- Static: `key_label(action)`, which gives the first key bound to an InputMap action.

### Roots

- **`MisoHud`**:
  - `setup(ctx)`, `configure(env)`, `refresh_all()` (also re-syncs the trail line, without restarting the banner);
  - `use_quickslot(key) -> Dictionary`; `poll_held_skills() -> int` (the held skill keys' repeat casts, #20) and
    `held_skill_keys() -> Dictionary`;
  - `request_window(name)`, and `request_minimap()` (the "Map [M]" button: the `miso_minimap` group's `toggle`, else
    the `toggle_minimap` action);
  - `dead`: true between `player_died` and `player_respawned` (the HP gauge reads 0), or until a
    `character_replaced` after which `Game.is_character_dead()` is false;
  - parts: `status`, `log_panel`, `banner`, `flourish`, `tooltip`.
- **`MisoMapBanner`** (`hud.banner`): `show_map(map_id, db)` (arrival: fade in, hold, fade out),
  `show_trail(map_id, dest_map_id, db)` (the current map's street and name with `TRAIL_PREFIX` + the destination's
  name under them, held while the trail lasts; the same destination again changes nothing; "" clears),
  `clear_trail()`, `is_showing()`, `is_trail_showing()`, `advance(delta)` (tests), `static map_name(map_id, db)`
  (canonical `name`, the id when unknown), and the labels `street_label`, `name_label`, `trail_label`. Centred at the
  top of its parent, and recentred on the parent's `resized`.
- **`MisoMinimap`** (`minimap.tscn`, group `miso_minimap`):
  - `setup(ctx)`, `configure(env)` (tests set the stand-ins `world`, `player`, `camera_rig` and `debug` first);
  - `refresh_all()`, `show_map(map_id)`, `model_for(map_id)` (built once per map id; not kept while the world is still
    loading);
  - `toggle()`, `set_expanded(on)` (also saved in the UI preferences), `is_expanded()`; `title_text()` ("street · name", plus " [id]" in debug mode),
    `debug_mode()`;
  - `refresh_markers()`, `refresh_player()`, `advance(delta)` (tests);
  - `snapshot()` for playtests and tests: `{map_id, title, expanded, debug_id, portals, portal_dests, shop_doors,
    npcs, markers, roles, labels, ground, ground_source, meshes, player_in_view, player_clamped, trail_tag}`;
  - parts: `street_label`, `name_label`, `id_label`, `fold_button`, `view`.
- **`MisoMinimapView`** (`minimap.view`): `set_model(m)`, `update_dynamic(...)`, `to_px(q)`, `player_marker()`
  (`{pos, clamped, in_view, angle}`), `label_layout()` (`[{id, text, rect}]`), `trail_tag_layout()` (`{text, base,
  rect}`; a destination name it would overlap is not drawn), `describe_at(px)` (the hover text), `mesh_count()`,
  `static label_candidates(at, dir, size, area)`, `static preferred_size(m)`, `static build_meshes(m)`,
  `static tier_color(tier, interior)`.
- **`MinimapModel`** (pure): `static build(def, defs, db, ground_faces := [], projection := null)`; fields `map_id`,
  `map_name`, `street_name`, `interior`, `projection`, `bounds`, `ground` + `ground_tiers` (lower tiers first),
  `ground_source` (`collision` | `footprint`), `outline`, `routes`, `climbables`, `portals`, `npcs`, `trails`;
  `portal(id)`, `npc(id)`, `portal_ids()`, `npc_ids()`, `ground_count()`, `static shopkeepers_on(db, map_id)`,
  `static leaves(trail, map_id)` (a one-way trail is a way out only at its from end).
- **`MinimapProjection`** (pure): `static from_basis(b)`, `from_xform_array(a)`, `for_map(def, live_basis)`;
  `project(p)`, `project_dir(d)`, `depth(p)`, `bounds_of(points)`; `static fit(bounds, size, margin, max_scale)`,
  `scale_of(xf)`, `clamp_to_rect(pt, rect)`.
- **`MapIcons`** (static): `npc_role(rec)` (`shop` | `transport` | ""), `draw_role`, `draw_coin`, `draw_boat`,
  `draw_swirl`, `draw_door`, `draw_chevron`, `draw_arrow`, `draw_marker_dot`.
- **`MisoWindowsRoot`**:
  - `setup(ctx)`, `configure(env)`;
  - `window_by_name(name)`, `open_window`, `close_window`, `toggle_window`, `is_open`, `close_all`, `refresh_open`;
  - `default_position(name)`, `window_width(name)` and `window_size(name)` (the first-open placement: `LEFT_ROW`,
    `RIGHT_ROW`, and `BELOW` for the Skills window, which opens by the Quest Log because the five windows are wider
    together than the screen: under it when its whole height fits there, else beside it);
  - `show_item_tooltip(item_id, opts, anchor)` and `hide_item_tooltip()`;
  - the windows: `inventory`, `equipment`, `stats`, `quests`, `skills`.

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
- **`MisoStatsWindow`**: `add_point(stat) -> bool`, `value_text(key)`, `sp_label` and `static allocatable_stats(db)`
  (canonical `beginner.json ap.allocatable_stats`).
- **`MisoSkillsWindow`**: `add_point(skill_id) -> bool` (`SkillBook.learn`, then `Events.skill_leveled` and
  `stats_changed` and an autosave request), `select_skill(id)`, `assign_quickslot(key, skill_id = selected) -> bool`,
  `level_text(id)`, and the parts `rows` (per skill: `panel`, `icon` (a `SkillIconCell` drag source), `name`,
  `level`, `effect`, `plus`), `plus_buttons`, `key_buttons`, `key_button`, `sp_label`. Rows come from
  `SkillDef.catalog(job, db)`.
- **`MisoQuestWindow`**: `select_tab("in_progress" | "available" | "completed")`, `select_quest(id)`,
  `objective_rows()`, `detail_texts()`, `request_forfeit() -> bool` (opens the confirmation for the selected
  in-progress quest), `forfeit(id) -> result` (`env.quest_service().forfeit`), `forfeit_button` (null unless the
  detail shows an in-progress quest) and `forfeit_prompt`.
- **`MisoForfeitPrompt`** (a child of `MisoWindowsRoot`, `forfeit_prompt`): `open(quest_id, quest_name, npc_name)`,
  `confirm()`, `cancel()` (also `close()`, the window stack's hook), `is_open()`, signals `confirmed(quest_id)` and
  `cancelled(quest_id)`, and the parts `message_label`, `confirm_button`, `cancel_button`.

## What the player sees and does

**HUD.**
- **Status bar.** Lv. (gold), name, job (canonical `formulas/<job>.json name`); HP and MP gauges with "cur / max"; the
  EXP gauge with "cur / needed [12.34%]" ("MAX" at the cap); mesos with a coin. From the death to the end of the
  respawn the HP gauge reads "0 / max"; the EXP bar drops at the death (the penalty's `exp_gained(-lost, "death")`).
- **Window buttons.** `Item [I]`, `Equip [E]`, `Quest [Q]` / `Stat [C]`, `Skill [K]`, `Map [M]` (3 + 3). Each key
  label comes from the InputMap. While AP is unspent, the Stat button turns orange and reads `Stat [C] +5`; while SP
  is unspent, the Skill button does the same (`Skill [K] +1`; `MisoStatusBar.set_sp`, called by
  `MisoHud.refresh_all`). `Map [M]` folds or unfolds the minimap as M does (`MisoHud.request_minimap`); it fills the
  grid's sixth cell, so the bar keeps its size.
- **Quickslots.** Eight slots, 1-8. A binding is typed, `{"kind": "item" | "skill", "id"}` (contract C3); a bare item
  id from an older save still reads as an item:
  - an item slot shows the key, the icon, and the inventory count (0 = greyed). A consumable is used through
    `ItemService.use_item`, and so is a chair (a Setup item with setup data, The Green Relaxer): `ItemService` hands
    it to `Chairs.use`, which sits the player down on it or stands it up (contract C5);
  - a skill slot shows the skill's icon, greyed while the character lacks the MP or the shell item for its level, with
    the cooldown as a dark sweep and the seconds left; it casts through the player's `PlayerSkills`
    (`MisoQuickslots.use_skill`), and a refusal with a reason ("Nimble Feet is not ready yet (164 s).", "Not enough MP
    for Recovery.", "Three Snails needs a Snail Shell.") goes to the log. Its hover shows the skill's name and level;
  - press the key or double-click the slot to use it. A skill key held down casts again as soon as the lockout and any
    cooldown have ended (`MisoHud.poll_held_skills` every physics tick, gated by `PlayerSkills.ready_to_cast`), with
    no input buffer beyond the hold; releasing the key, a modal (window, console, pause menu) or a rebind ends the
    hold, and a refusal's line goes to the log once per hold (#20). An item key uses one item per press;
  - drop a consumable or a chair from the inventory, or a learned skill from the Skills window, on a slot to bind it;
  - drag between slots to move a binding; right-click to clear it.
- **Effects.** While Nimble Feet or Recovery runs (`CharacterState.effects`), its icon sits right on top of the status
  bar over the quickslots, newest last (`MisoEffectsBar`, placed by `MisoHud` from the bar's laid-out height). Each
  icon is a quickslot's size (40 px) with the time left under it in bold outlined text ("1:15", "30s"); a dark sweep
  grows over it as it runs out, and its hover gives the name, level and time left. The row grows left from the bar's
  right end and covers no gauge, button or quickslot (`test_ui_window_fit`); until issue #12 it sat at the top right
  with 30 px icons, far from the bar.

**Message log.** Fading lines above the bar:

| Event | Line |
|---|---|
| `item_gained` | "You have gained an item (Red Potion x5)" |
| `mesos_changed` | "You have gained mesos (+12)" when delta > 0; "You have spent 50 mesos." when delta < 0; nothing for delta 0 (a refresh) |
| `exp_gained` | "You have gained experience (+15)" when amount > 0; nothing for amount <= 0 (a refresh: the death penalty's -N, or 0), though the EXP bar still redraws |
| `leveled_up` | "Congratulations! You have reached level N." plus "You have N AP to distribute (press C)." and, while SP is unspent, "You have N SP to spend (press K)." |
| `quest_started`, `quest_completed`, `quest_forfeited` | "Quest started: ...", "Quest complete: ...", "Quest forfeited: ..." |
| `quest_progressed` | "Sam's Suggestion: Snail 7/10". The HUD compares objective counts with the last ones it saw, so the line names what moved (`MisoHud.quest_progress_line`); an NPC talked to en route reads "...: spoke to Mai". The turn-in talk (`npc_talk` purpose `turn_in`, the completion act) adds no line: "Quest complete: ..." follows. Nothing nameable moved: no line |
| `inventory_full` | "Your inventory is full." |
| `player_died` | "You have died." |
| `notice` | The text as given |

Every gain, spend, EXP and quest line is logged, even when the same text comes twice in a row: selling one Orange
Potion twice in half a second logs "You have gained mesos (+15)" twice. Only a notice or a warning (`MisoNoticeLog`
tones `info` and `warn`) that repeats the previous line within 1.5 s is dropped. That keeps holding pickup at a full
bag to one "Your inventory is full.", and shows a loot pickup once: its `Events.notice` words the HUD's own
`item_gained` / `mesos_changed` line again (`LootPickupRules.pickup_notice`). "You have spent ..." has its own tone,
`spend`, coloured as info but never dropped.

**Banner and flourish.** On `map_entered` the banner shows the canonical `street_name` above `name`, then fades (the
minimap's title strip keeps the name on screen afterwards). On `leveled_up`, the flourish shows "LEVEL UP!", "Level
N" and a star burst.

**Minimap (M).** Top left (12, 12), on by default, never needing the debug console:

- **Title strip**, always shown: the canonical `street_name` (gold) above the canonical `name`. While the debug
  overlay is on (F3, `Debug.overlay_enabled`) the canonical map id is added under them. The "-" / "+" button, M and
  the status bar's `Map [M]` button fold the picture away to this strip and back; the strip stays, so the map's name
  is on screen at all times. The fold survives map changes and loads, and a restart: it is saved in the UI
  preferences (`MisoUiPrefs`, below). Nothing happens on M while a modal (dialogue, shop, console, menu) owns the
  keyboard.
- **UI preferences.** The fold is the player's display choice on this machine, not character progress, so it is kept
  in no save slot (a load or another character does not change it). `MisoUiPrefs` writes it to `ui_prefs.cfg` (a
  ConfigFile, section `minimap`, key `expanded`) beside the slots in `SaveService.save_dir`: `user://saves/` in the
  game, `<out>/saves/` in a playtest, so a run never reads the player's own file and a fresh run starts unfolded.
  `SaveStore` lists only `.json` slots, so the file is never taken for one. Nothing in the project kept user
  settings before (the Controls panel only shows the keys); this file is where the next one goes.
- **The picture** is the map seen through the gameplay camera, scaled down (`MinimapProjection`: u = p · right,
  v = −(p · up) with the camera basis): what is up on screen is up on the minimap, and raised terraces sit higher, as
  in the game view. It fits the map's bounds into at most 330 x 215 px (at most 9 px per metre, at least 230 px wide).
  - Ground: the map's walkable collision (`IslandWorld.ground_faces`), upward faces only, coloured by height tier
    (1.5 m steps, grass tones; floor tones in interiors), drawn lowest first, each tier over a darker copy shifted
    down by one tier's projected height, which reads as the terrace's front face. Without collision (a tool, a test)
    the footprint is filled and the authored routes are drawn instead.
  - Ladders, ropes and vines (sidecar climbables) as short brown lines; the walkable trails leaving the map as dashed
    stubs from their portal. The one-way trail 000000030 → 000000040 has a stub on 000000030 only: on 000000040 it
    ends at the arrival gate below a ledge that cannot be climbed, so it is no way out.
  - Portals: the visible canonical (MeowDB type 2) portals only, a swirl for an edge and a door for a door, each with
    an outward chevron and its canonical destination name beside it (nearest exits first; outward, above, below,
    right, left or a corner, slid along the picture's edge where needed, covering no other name or glyph; a name
    with no free place covers as little of the NPC dots as it can, and the dots are drawn over it). Every map with up
    to five exits names them all; The Field West of Amherst names five of its eight in the suite's layout (the
    player away: `test_ui_minimap_world` prints "43 of 46 exits named"), the others are read by hovering; which ones
    show depends on where the player stands. A door with a shopkeeper behind it has a gold coin (Southperry to Pan,
    Amherst to Sid and Lucy).
  - NPCs: a yellow dot, or the quest marker's own badge colour and glyph ("!" available, "..." in progress, "?" ready
    to turn in, from `QuestEngine.npc_marker`, the rule of the badge over the NPC's head) for every NPC of the map, on
    screen or not; a coin beside shopkeepers and a boat beside Shanks (Transport).
  - The player: an orange arrow pointing where the character faces. Off the picture (far along a trail) it is held
    on the edge, pointing the way; on a trail it carries "-> <destination name>".
  - Hovering a portal or an NPC shows a tooltip: "Portal to Snail Hunting Ground II (Maple Road)", "Shop: Pan",
    "Mai" with "Quest ready to turn in", "Shanks, Transport".
- It is rebuilt on `map_entered`, `game_loaded` and `Game.character_replaced`; quest dots re-read on quest, item and
  level events and every 0.5 s; the arrow moves at 15 Hz.

**Trail line** (MAP_ARCHITECTURE §4.11). While the player walks a trail (`MapSession.trail_destination` non-empty,
announced by `MapSession.trail_changed(dest_map_id)` from the world's `RegionMonitor`), the banner shows the current
map's street and name with "-> <destination map name>" under them (canonical `name`; an unknown id shows the id). It
stays up for as long as the player is on the trail. Stepping off (`""`) hides the line and the banner fades out;
stepping back on mid-fade fades it back in from where it was. MapSession clears the trail before every map change, so
a gate commit hides the line and the new map's arrival banner follows. Turning back on the trail just walked shows the
way back ("-> <the map left>"). Because the line can hold the banner for minutes, the banner follows the HUD's
`resized` and stays centred when the window changes shape (stretch aspect `expand`: wider than 16:9 widens the HUD).
Checked in the real game (review, 2026-10-04): walking 000000040 -> 000000041 shows "-> Snail Hunting Ground II",
the gate commit clears it before the arrival banner, turning back shows "-> Snail Hunting Ground I" held past 5 s, and
a 2400 x 900 window keeps it centred (before the fix it stayed at x 800 of 2400).

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
- Ability Points (gold while above 0), Skill Points [K] (gold while above 0; spent in the Skills window), and
  STR/DEX/INT/LUK as total, with "(base + bonus)" when gear adds to it.
- An orange "+" per allocatable stat while AP > 0. Each stat keeps its own row, with its value beside its name, at any
  AP: the "+" sits in a cell (`MisoStatsWindow.PlusCell`) that keeps the button's size while the button is hidden. A
  `GridContainer` skips hidden children, so hiding the bare button at 0 AP used to reflow the 3-column grid into
  "STR 9 DEX" / "8 INT 4" / "LUK 4" (playtest Test C).
- Damage "min ~ max" (the `StatCalculator` stat window), ACC, AVOID, W.DEF, M.DEF, Magic (`matk`, MagicTotal),
  Speed %, Jump %.

**Skills (K).** One row per skill the character's job can learn (`SkillDef.catalog`: the canonical Beginner skills
Three Snails, Recovery, Nimble Feet), each with its procedural icon, name, "Lv. x / 3" and the current level's MeowDB
effect line ("MP -4; speed +10 for 10 sec. Cooldown: 3 min."), and the unspent Skill Points in the header.
- An orange "+" per skill while SP is left and the skill is below its max level: one SP, one level (`SkillBook.learn`;
  no refunds).
- Clicking a row selects it: the description shows the cast position, the description, the current level and the next
  level's effect.
- A learned skill's icon drags onto a HUD quickslot; or select it, press `Set key` and pick 1-8.
- It keeps one size whatever is learned or selected (about 570 px tall at 1600 x 900: 565 px in the windowed
  `test_skills` run, 573 px in `test_ui_window_fit`'s synchronous layout): every row reserves two lines for its
  effect text, the description scrolls inside five lines (`detail_scroll`), the status line keeps two lines and the
  1-8 picker's row is held while the picker is folded. The acceptance review saw it grow from 365 to 511 px after
  three "+" clicks, off the bottom of the windowed screen and over the HP gauge, with `Set key` at y 948 of 900.
- It opens by the Quest Log (`MisoWindowsRoot.BELOW`) and never over it: under it when its whole height fits above
  the HUD's status bar there (a tall screen), else beside it, 10 px to its right and as low as the bar allows. On
  1600 x 900 that is (896, 217): clear of the Quest Log, Character Stats and the Item Inventory, over the lower left
  corner of the Equipment window (226 x 228 px of it, below its title strip). No place on that screen is clear of all
  four: no two windows fit one above the other, and the five side by side are 1764 px wide. Until the owner's
  decision of 2026-10-06 (issue #8) it opened under the Quest Log, pulled up over its lower part (366 x 283 px).

**Every window stays on screen.** `MisoWindow` clamps its whole rect (not only the title strip) into
`screen_area()`: the viewport above the HUD's status bar (`MisoUiEnv.bottom_bar_inset`, found by layout as NpcUi
does, plus `BAR_GAP` 6 px; the whole viewport without a HUD). It does so when the window opens, while it is dragged,
whenever its size changes (`resized`) and when the viewport changes size. `test_ui_window_fit` opens every window with
its largest realistic content (all three skills learned, a row selected and the picker open; a full Use tab with its
picker; every Maple Island quest in progress and 1006 selected; the largest shop) on exactly 1600 x 900 and checks
that each lies on screen and off the status bar.

**Quest Log (Q / L).** In Progress, Available and Completed tabs, each with a count.
- In Progress entries that are ready to turn in show "[ready]" before the name, so a long name is what the ellipsis
  trims ("Borrowing Sera's Mirror" had its trailing tag clipped away).
- Available lists quests the character can accept now (`QuestEngine.is_available`). Quests whose start NPC stands on
  the current map come first, marked "[nearby]" (before the name), and the detail pane reads "Available nearby". The NPC's map is any
  of its canonical `locations[].map_id` (`MisoQuestWindow.npc_is_on_map`): in Snail Hunting Ground I (000000040),
  Sam's Suggestion (Sam, 9) is listed first and tagged.
- The detail pane shows:
  - name, status, start NPC and turn-in NPC;
  - the journal text (`QuestEngine.journal_text`);
  - objectives with ticks and counts ("Snail 7/10", "Return to Mai", "Use Roger's Apple 0/1", "Answer the quiz");
  - canonical rewards: EXP, mesos, fame, items with icons, "One of these at random" and "Choose one" groups.
- **Forfeit** (owner ruling #10). An in-progress quest's detail has a Forfeit button under the NPC line; completed
  and available quests have none. A click, or Delete while the log is open and no dialogue or shop owns the keyboard,
  asks first: "Forfeit quest?" over a dimmed screen, "Forfeit Borrowing Sera's Mirror? Its progress is lost, and items
  the quest gave you are taken back. You can accept it again from Heena.", with Forfeit and Cancel.
  - The question is modal (the player stands still, window hotkeys are quiet) and registered on the window stack, so
    Esc cancels it before it closes any window. Closing the log, a new game or a load cancels it too.
  - Keyboard: Cancel holds the focus; Left/Right move between the buttons and Enter presses the focused one; Y
    forfeits, N or Esc cancels. Space and Alt (the jump keys) and key repeat never press a button
    (`DeathNotice.ignores_key`). The log's own buttons keep `FOCUS_NONE`; only the question takes the keyboard, and
    hands it back when it closes.
  - Cancel changes nothing. Forfeit calls `Game.quests.forfeit` (`QuestService`, the debug console's path):
    `quest_forfeited` is announced (the HUD logs "Quest forfeited: ..." and an autosave follows), accept items still
    held are taken back, the log moves the quest back under Available, and its start NPC offers it again.

**Tooltip.** Hovering an inventory slot, an equipped piece or a quickslot shows a card. For inventory and Equipment
slots the card sits beside the slot and never covers it (`MisoItemTooltip.place_beside`). It goes to the slot's right
when it fits there, else to its left (the right-docked inventory, and usually the Equipment doll next to it), else
above or below. It slides only vertically to stay on screen. Before, a right-edge slot had the card clamped back over
itself. A quickslot's card sits above the bar. The card shows:
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
| Forfeit asks first, in a modal question whose Cancel holds the focus; Delete is its key | Owner ruling #10. A forfeit drops progress and takes accept items back, so one stray click must not do it; Enter already uses the selected inventory slot, and the windows never take the keyboard, so the question (not the button) does, as `DepartureScreen` and `DeathNotice` do |
| "Nearby" means one of the quest's start NPC's canonical locations (`npcs/<id>.json locations[].map_id`) is `MapSession.current_map` | The brief asks for nearby available quests; MeowDB places NPCs by map, in `locations[]` only (no top-level `map_id`; reading one left every quest un-tagged until the Test E playtest caught it) |
| The message log drops a repeated line only for notices and warnings, never for gains, spends, EXP or quest lines | The repeat filter exists for a full inventory announced again while pickup is held, and for loot pickup notices that word the HUD's own gain line again. Applied to every line, it also swallowed a second, separate sale (Test G) |
| Log wording ("You have gained an item (...)") is MapleStory-inspired | MeowDB publishes no client messages. The wording is presentation, not canonical text |
| Windows first open side by side, placed from their measured widths: Character Stats then the Quest Log from the left edge, the Item Inventory then Equipment from the right edge (classic: bags on the right). The four never overlap on the 1600 x 900 base viewport or anything wider; the Skills window opens by the Quest Log, never over it (see "Skills (K)"). They are draggable by the title strip, and the whole window is clamped above the HUD's status bar (on open, drag, resize and a viewport change) | Presentation. The first version used screen fractions, and the Equipment window then covered the Quest Log's right edge (its key hint, close button and journal text). The clamp kept only the title strip on screen, once, at the first open, so a window that grew afterwards (the Skills window after a "+") ran off the screen and over the gauges (acceptance review) |
| The Skills window keeps one size (reserved lines, a scrolling description, the picker's row held) | A window that grows under the pointer moves the button the player is clicking; a fixed size also lets it open where its whole height fits above the status bar |
| While the player sits, the status bar shows a green cue above the HP gauge: "Seated  ·  +10 HP / 10 s  ·  The Green Relaxer +30 HP / 10 s" (`MisoHud.seated_text`: the natural rate from `recovery.json` natural_hp and the chair's canonical bonus, `Chairs.bonus`); standing, a load or a replaced character clears it. Its line is held empty while standing, so the gauges never move | The acceptance review could not see the green chair on green grass and had no seated cue. Presentation; every number is read from data |
| A press anywhere inside a window (its slots and buttons included) brings it to the front and makes it "newest" for Esc | Classic focus behaviour; Esc closes what the player touched last. Slots and buttons stop the mouse event, so this is done in `MisoWindow._input` from the frontmost control under the pointer |
| The trail line lives in the map banner, held while on the trail, rather than in a separate widget | The banner is the HUD's only map-name element; §4.11 puts the line under the current map's name. The banner was already the arrival cue, so a trail reads as "still in this map, heading to that one" |
| The trail line's prefix is the ASCII "-> " | Nunito (the MisoTheme font) has no U+2192 arrow; Godot would draw a system fallback glyph, which differs per platform |
| UI drags (an item out of a slot, a window by its title) leave the "attack" action alone | The left button is an attack binding. `PlayerCombat` (`MouseAttackGate`) counts the mouse only through presses no GUI control consumed, outside a GUI drag, so a drag across the world never swings. Releasing the action at a drag start (the earlier workaround) also cut a held J; `test_ui_drag_attack` pins both from the UI side. Also checked in the real `main.tscn` (review, 2026-10-04, keyboard player, real input events): a world click swings once; a potion dragged from the inventory across the world for 60 ticks and dropped there does not swing; J held through such a drag keeps repeating at the 0.72 s lockout; a Character Stats window dragged by its title and clamped at the bottom-right corner does not swing |
| The HP gauge reads 0 between `player_died` and `player_respawned` | Classic shows the dead character at 0; the shell takes the death's loss (and sets the respawn HP) at the moment of death, so the gauge must not follow the character's HP then |
| The minimap is drawn from the 3D world through the gameplay camera's projection, never from MeowDB's minimap block | The canonical block is a 2D size and centre in px (0 x 0 for the three shops) with Nexon art; its frame does not match the isometric layout. The brief asks to adapt the isometric map. The basis is the live rig's `view_basis`, else the sidecar's `cameras.gameplay.xform` (the same on all 25 maps, and equal to camera.json's default; `test_ui_minimap_world` checks it) |
| The ground comes from the collision Ground trimeshes at runtime, upward faces only | No re-export is needed and it is the walkable truth. The Ground trimeshes are closed volumes (as many faces point down as up, down to 13 m below the base), and their steep faces are cliff sides; neither is seen from the camera. Faces whose centroid is more than 2 m outside the footprint are left out |
| Hidden portals (MeowDB type 1: 000001020 in00 to Tomato Field) and their hedge lane are not shown; arrival gates are not shown | Classic minimaps hide hidden portals; the type-1 portal has no swirl and no prompt in the world either. Arrival gates are adaptation geometry, not exits. The owner decided on 2026-10-06 that the portal is never shown (see "Known gaps") |
| M folds the picture to the title strip instead of hiding everything | The title strip is the persistent map name (Phase 12); a hidden minimap would take the name with it |
| "Debug mode" for the map id is the debug overlay (F3, `Debug.overlay_enabled` / `overlay_toggled`) | It is the existing developer switch, available in every build; the id must not need the console |
| Placed top left, under the windows | The classic place. The Stats and Quest windows open over it (they are installed later, so they draw above); the debug overlay is top right and the banner top centre, so neither covers it |
| A shop is marked by a coin on the door that leads to it and on the shopkeeper's name tag; Shanks gets a boat and "Transport" (his canonical MeowDB role) on his tag | All three shopkeepers stand in interiors, so from the town only the door could hint at a shop (Phase 12 "shop indication"). The role comes from the canonical record (`MapIcons.npc_role`: a `shop`, or the roles "Shopkeeper" / "Transport") |
| Destination labels are placed greedily, nearest exit first: first where they cover nothing, then where they cover the least of the NPC dots (drawn over them), and left out where they would cover another name or a portal glyph or leave the picture | A 330 px picture cannot hold eight long canonical names (000001000: six fit). Every other map names all its exits (`test_ui_minimap_world`, the `ui_minimap` scenario). Hovering always gives the name, so none is lost |

## Testing

```bash
ISOLATE=hud INCLUDE_WORLD=1 bash scripts/test.sh test_ui_   # this system's test_ui_* files (the minimap's: test_ui_minimap*)
ISOLATE=hud INCLUDE_WORLD=1 bash scripts/test.sh            # everything
```

| File | Covers |
|---|---|
| `test_ui_theme.gd` | The theme builds and caches; every type variation is registered with the right base; the vendored Nunito loads (not the fallback) with its OFL text; weights differ; helpers (`thousands`, labels, gauges, check textures, panel and button styles) |
| `test_ui_hud.gd` | `hud.tscn` root has `setup`; initial values from the character (level, name, canonical job name, HP/MP, mesos separators, EXP percent, 8 quickslots); values follow `hp_changed`, `mp_changed`, `mesos_changed` (no line for delta 0), `exp_gained`, `item_gained`, `inventory_full`, `notice`, `equipment_changed`; `exp_gained` amounts <= 0 (the death penalty's -N, and 0) redraw the bar with no line; level-up flourish and the AP highlight; map banner (canonical street and name, fade timeline, no trail line); the trail line on a private `map_session.gd` (`set_trail`): "-> " + the destination's canonical name under the current map's, held past the arrival banner's time, a refresh does not restart it, cleared by "" (fades out), back on mid-fade fades in from there, shown at once for a HUD set up on a trail, a gate commit (clear, then `map_entered`) leaves the new map's banner with no line, the way back after turning round, an unknown id shows the id, re-entering the tree re-syncs and keeps listening, `reset()` clears it; a held banner stays centred when the HUD resizes (wider and narrower than 1600 px) and the next banner is centred for the new width; the HP gauge at 0 from `player_died` to `player_respawned` through `stats_changed`, `hp_changed`, `equipment_changed`, `leveled_up` and `game_loaded` (the character holding its respawn HP), the HP back at the respawn, an announced death (HP above 0) also 0; `character_replaced` re-reads `is_character_dead()` (a stand-in game: still dead = 0, alive = its HP), a HUD configured during a death starts at 0; log cap, history, dedupe, fade; quickslot bind → use → count decrements → HP restored → `item_used` → the key path → JSON save round trip keeps the binding → empty stack greys out with a notice; non-consumables refused; drop, move, unbind; quest progress lines through a real `QuestService`; leaving and re-entering the tree keeps listening and redraws; no character or content: nothing breaks |
| `test_ui_windows.gd` | `windows.tscn` root has `setup` and four closed windows; inventory tabs and slots from the live inventory, counts, mesos, live refresh on pickup; use and equip through `ItemService` (`item_used`, `equipment_changed`, previous weapon back in the bag), a level-requirement refusal with message and notice, Etc not usable; quickslot assignment and drag-move (`ItemService.move`); equipment doll covers every slot, W.ATK contribution, unequip with a full Equip tab refused gracefully, then unequip and re-equip by drop; stats window: "+" only with AP, every derived value equals `StatCalculator.snapshot`, `Game.allocate_ap` (a real `GameState` on a private bus) spends AP and moves the damage range, "+" hidden at 0 AP; quest log: Sam's Suggestion available, then "Snail 7/10" after 7 `monster_killed` events through an attached `QuestService`, the turn-in row, the canonical EXP and item rewards, capped and ticked at 10/10; the ctx window stack (newest closes first, re-focus, close button, `window_changed`); hotkeys toggle and stay quiet under a modal; HUD buttons open windows through the group; standalone Esc; the four default window rects are disjoint and on screen whatever the opening order; a real mouse press on a slot of a back window (`Viewport.push_input`) makes it the newest, so Esc closes it first; dragging a window by its title follows the pointer, clamps at the edges and leaves the attack action alone; tooltip rows (unmet requirement red, met plain, effect, price, description) and hover in the window; every canonical item has an icon shape |
| `test_quest_forfeit_ui.gd` | The Quest Log's Forfeit (owner ruling #10): the button only on an in-progress quest (not on available or completed ones); real clicks through `Viewport.push_input`: Forfeit asks (modal, the message names the quest and Sera), Cancel changes nothing, the question's Forfeit forfeits through `Game.quests` (one `quest_forfeited`, the mirror taken back), the log updates and Sera offers 1001 again; real keys: Delete asks, Cancel has the focus, Left/Right move it, Enter presses it, Space and key repeat do not, Y forfeits, N and Esc cancel, the window stack's Esc reaches the question first; quiet under another modal; closing the log cancels; without a quest service nothing changes and the HUD says so |
| `test_ui_minimap_projection.gd` | No world: `project()` equals a real orthographic `Camera3D`'s `unproject_position` up to one scale and offset (20 points); further and higher points sit higher; `for_map` prefers the live basis; `fit` keeps the aspect and the margin; `clamp_to_rect` keeps the direction |
| `test_ui_minimap_world.gd` | With the world (SKIP without), one island build for the file (a test process survives about ten builds; the suite makes nine): `IslandWorld.ground_faces` on all 25 maps (non-empty, in the footprint, in the chunk's height range, cached); `MinimapModel` on all 25 maps against the canonical records: name and street, upward ground by tier, portal markers = the type-2 portals with their canonical destination names, NPC dots = the canonical NPCs, shop badges exactly on the doors to Pan, Sid and Lucy, role icons, interior floors, `player_spawns[0]` inside the bounds; the destination names inside the picture, never over another name or a portal glyph, and every exit named on each map with up to five exits; the hidden portal, its lane and arrival gates never shown; trail stubs only where the map's own canonical portals lead (no stub back up the one-way 30 → 40 on 000000040); every sidecar camera is the rig's default view; the footprint fallback |
| `test_ui_minimap.gd` | No world (stand-in maps from the canonical records): the scene installs after the HUD; the title and the debug id following the overlay; M and the fold button, quiet under a modal, folded across a map change; the fold saved in a private preferences file and read back by the next minimap (a restart), none kept without one; the status bar's `Map [M]` button names the key and folds and unfolds the map; Sam "!" → "..." after accepting 1006 and Mai "?" after the kills, through a real `QuestService`; the arrow follows the player, clamps off the map, the trail tag; portals, shop badges, role icons, hover text, labels inside the picture; every canonical NPC's name tag through the real `NpcPresenter` (coin, boat, "Transport"); the tag's "Transport" line follows the role in any call order; the places tried for a destination name clear the glyph and slide inside the picture |
| `test_ui_minimap_feedback.gd` | The level-up SP line (and none without SP); the map name stays on the minimap after the banner fades, also folded |
| `test_ui_drag_attack.gd` | UI drags against the real `PlayerCombat` (a `MonsterTestRig` world with a keyboard player) and the real windows scene, through `Input.parse_input_event`: a potion dragged out of the inventory over the world (a real GUI drag: `_get_drag_data` runs) never swings, pressed, held or released there, the attack action stays pressed, the drop changes nothing, and a later world click attacks; J held through that drag keeps repeating at the lockout rate (during and after it); a window dragged by its title across the world and clamped at the edge never swings, and J held next to it repeats |

All UI tests use a private `events.gd` bus and `MisoUiEnv.isolated(...)`. They never read or change autoload state
(`test_ui_drag_attack` sends real input events, as `test_player_combat_mouse` does, and releases them afterwards).
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
    res://scripts/ui/common/sandbox/ui_sandbox.tscn -- --shots <abs dir>    # hud, windows_a, windows_b, trail .png
```

The sandbox assigns `Game.character` directly and never calls `Game.new_game`, so it writes no save. In it, I/E/C/Q
open windows, 1-8 use quickslots, Esc closes the newest window, F1 levels up, F2 shows a banner, F3 toggles the trail
line (000000040 to 000000041, from a private `map_session.gd` instance; the `MapSession` autoload is untouched), F4
adds a notice and F5 toggles a death (the HUD's own handlers only). `trail.png` shows the trail line over the HUD of a
death (HP 0).

`ui_game_check.tscn` runs the real `main.tscn` with a quick-start game and checks the HUD on the real path
(`SubsystemInstaller` and `setup(ctx)` over the island), printing `UI_GAME_CHECK ok|FAIL: ...` and exiting 1 on a
failure. It takes `game_hud.png`; places the player mid-trail (the first walkable trail of the start map) so the
world's `RegionMonitor` reports it, checks `MapSession.trail_destination`, the line's text, that it holds past the
arrival banner's time, and that it clears back on the map (`game_trail.png`); kills the character through
`Game.change_hp` and checks the HP gauge at 0 under the death notice while the character holds its respawn HP, also
after a `stats_changed` / `hp_changed` refresh (`game_death.png`), then OK and the character's HP after the respawn;
then takes `game_windows.png` (all four windows at their default places) and quits. Starting a game writes a save, so
the scene refuses to run unless the copy's `project.godot` sets `application/config/use_custom_user_dir=true` and a
`custom_user_dir_name`. Set that in the ISOLATE copy only. Last run (2026-10-04): 14 checks ok on 000000001 (trail
to 000000010, "-> Mushroom Town").

**The minimap in the real game.** `ISOLATE=<name> bash scripts/playtest.sh ui_minimap [--windowed]` (scenario
`game/tools/playtest/scenarios/ui_minimap.gd`, PLAYTEST_HARNESS.md) starts a new game through the screens and checks,
with real keys, that the minimap is installed and unfolded with the canonical title and the player's arrow on the
picture; M folds it to the title strip (the name stays) and back; a mouse click on the status bar's `Map [M]` button
does the same, and each fold is written to `ui_prefs.cfg` in the run's save directory; F3 adds the map id and takes it away; M is quiet
while Heena's conversation is open; the arrow is tagged with the destination on a trail. It then warps (console,
setup only) through all 25 maps and checks on each: the title, the collision ground drawn, the picture on screen
with its ground meshes, every exit named on the picture (maps with up to five exits), portal markers equal to
the visible canonical portals, NPC dots equal to the canonical NPCs, the arrow on the picture, the name tags' shop and
transport icons, and island-wide the shop badges on exactly the three shop doors. Last, the Phase 12 feedback through
real play: Snails killed in Snail Hunting Ground I up to level 2 (8 kills with seed 1), then the flourish, the level,
AP and SP lines in the log, the hits announced (`monster_hit`, the damage numbers' source) and every pickup announced
with the HUD's own line; no engine error from the minimap. Last run on the minimap package (2026-10-05, review): 231
checks passed headless and windowed; the windowed run writes one screenshot per map. The scenario now expects the
HUD's "You have 1 SP to spend (press K)." (wave 3; it had expected the old "SP to distribute" and failed 1 of 231
on the integrated build), and it passes in the final Iteration Three evidence run (headless, seed 1, on the pinned
1600x900 screen: 230 checks, 0 failed, 1 warning: nothing had dropped near the player, so the pickup-announcement check
was not reached). Since issue #15 it ends by folding the minimap with `Map [M]` and quitting the game (Quit Game);
phase 1, a new process on the same saves, presses Continue and checks the minimap is still folded with the map's name
on its strip, then unfolds it with M (headless, seed 1, 2026-10-06: 242 checks, 0 failed, no warning).

**Review (iteration 2).** An adversarial review drove the real `main.tscn` (quick start) with real input events
(`Input.parse_input_event`: keys, mouse moves, clicks, double-clicks, right-clicks and drags) through 63 checks: the
installer and `setup(ctx)`, HUD values, I/E/C/Q and Esc (newest window first, then pause, nothing while paused),
quickslot keys, hover tooltips, equip by double-click, drag to a quickslot, the "+" buttons, a click on a back window,
title drags, the close button, right-click clear, quest progress, save and load (bindings, HUD, windows), death
(modal: quickslots and hotkeys quiet), banner and flourish fades, and no swing from any of it. It found and fixed:
overlapping default window positions, swings while dragging an item or a window (then worked around here by
releasing the attack action at a drag start; `PlayerCombat` has since taken over, see "Decisions"), a back window not
raised by a click on its slots or buttons, title dragging that read the OS cursor instead of the event, and the roots
staying disconnected after a reparent.

## Known gaps and requests

- **Tomato Field is not on any minimap.** The hidden portal 000001020 in00 (MeowDB type 1) and its hedge lane stay
  off the minimap, as on a classic minimap, and the world shows no swirl or prompt there either. A player has to find
  the lane. The owner decided on 2026-10-06 never to show it.
- **Windows cover the minimap.** The Stats and Quest windows open over its top-left corner; drag them away or close
  them, or fold the minimap with M or the status bar's `Map [M]` button (the fold is saved across restarts).
- **The Skills window covers a corner of the Equipment window** when both are open at their first places on
  1600 x 900 (226 x 228 px, below its title strip; see "Skills (K)"): no place on that screen is clear of all four
  other windows. Either can be dragged.
- **NPC speech bubbles hide while any modal is open** (a shop, a chat, the pause menu: `NpcPresenter.is_modal_open`,
  the interaction system's GameContext), so a bubble never shows over or under an open window (the acceptance review
  saw Lucy's cut off behind her shop). Name tags and quest markers stay.
- **The minimap shows no monsters and no Wooden Boxes,** as classic minimaps do not.
- **Phase 12 follow-ups outside the HUD and minimap** (found by the `ui_minimap` real-play check and the review):
  all closed at the Iteration Three integration. The status bar's Skill button carries an SP badge
  (`status_bar.gd set_sp`) and the stats window an SP row; the Tutorial Jr. Sentinel has a proxy and no label says
  "placeholder"; the Quest Log shows chain progress and the NPCs' maps; X (sit) and K (skills) have their handlers.

- **The trail line follows `RegionMonitor`'s sampling** (10 Hz, MapSession emits only changes). At a trail mouth the
  line appears or clears up to a tenth of a second after the step. A player who stands on the seam between a map
  footprint and a trail zone could see it flicker; stepping back on mid-fade fades in from the current opacity, so it
  never pops. Not seen in the real-game check.
- **The HP gauge stays at 0 through the respawn's fade-in**: `player_respawned` fires when the respawn transition
  completes (the player grounded in town), so the gauge shows the respawn HP a moment after the town appears.
- **Only the HUD's gauge reads 0 while dead.** A Character Stats window left open at the death (non-modal windows
  stay open) shows the character's HP on its next refresh, which is the respawn HP once the respawn's refresh arrives.
  The notice covers the middle of the screen, and the window is rarely open then.
- **Chairs on quickslots.** Since the integration the inventory's `Set key` follows `MisoQuickslots.can_bind`, which
  accepts chairs, as dragging a chair from the Set-up tab onto the bar always did; a bound chair key sits or stands
  through `ItemService.use_item`.
- **Skill slots poll.** The bar redraws its skill slots every 0.1 s while any is bound (every frame during a
  cooldown) instead of listening to MP and cooldown events.
- **Not built.** Dropping or discarding items, item sorting and a split-stack dialog.
- **Sandbox location.** The sandbox scenes live under `scripts/ui/common/sandbox/`, because this system owns no path
  under `scenes/sandbox/`.
