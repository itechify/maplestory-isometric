extends TestCase
## The character windows (res://scenes/ui/windows.tscn, MisoWindowsRoot): Inventory (tabs, slots, use / equip /
## move / quickslot through the services), Equipment (doll, unequip, full inventory, bonuses), Character Stats (AP
## through Game.allocate_ap, derived numbers), Quest Log (Sam's Suggestion progress), the GameContext window stack,
## hotkeys, modal suppression, and the item tooltip. Private events.gd bus, injected character, no autoload state.

var bus: Node
var nodes: Array = []
var game: GameState = null
var seen: Dictionary = {}


## Contract C6.
func parity_keys() -> Dictionary:
	return {
		"test_stats_window_applies_ap_and_refreshes_derived_numbers": ["mechanic:ap-allocation"],
		"test_quest_log_shows_sams_suggestion_progress_after_kills": ["ui:quest-log"],
		"test_quest_log_marks_quests_whose_start_npc_is_here_nearby": ["ui:quest-log"],
	}


func before_each() -> void:
	bus = load("res://scripts/autoload/events.gd").new()
	seen = {}
	for s in bus.get_signal_list():
		var sig := String(s["name"])
		var n := (s["args"] as Array).size()
		var cb := _seen.bind(sig)
		bus.connect(sig, cb.unbind(n) if n > 0 else cb)


func after_each() -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.free()
	nodes.clear()
	if game != null:
		game.free()
		game = null
	bus.free()


func _seen(sig: String) -> void:
	seen[sig] = int(seen.get(sig, 0)) + 1


func _character() -> CharacterState:
	var cr := CharacterFactory.create(CharacterFactory.default_params(db()), db())
	assert_true(cr.ok, "factory character")
	return cr.character


func _parent() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.current_scene if tree.current_scene != null else tree.root


## The windows scene configured on `c` (a GameState stand-in carries allocate_ap; not in the tree).
func _windows(c: CharacterState, ctx: GameContext = null) -> MisoWindowsRoot:
	game = GameState.new()
	game.db = db()
	game.event_bus = bus
	game.log_warnings = false
	game.character = c
	var root: MisoWindowsRoot = load("res://scenes/ui/windows.tscn").instantiate()
	root.configure(MisoUiEnv.isolated(c, db(), bus, ctx, game))
	_parent().add_child(root)
	nodes.append(root)
	return root


## An equipment item the character cannot wear yet (a level requirement above theirs), read from canonical data.
func _too_high_item(c: CharacterState) -> String:
	for id in db().ids("items"):
		var d := ItemDef.of(id, db())
		if d.is_equipment() and d.req_level > c.level and d.req_jobs.is_empty():
			return id
	return ""


func test_scene_root_implements_setup() -> void:
	var w: Node = load("res://scenes/ui/windows.tscn").instantiate()
	assert_true(w is MisoWindowsRoot, "windows.tscn root is MisoWindowsRoot")
	assert_true(w.has_method("setup"), "setup(ctx)")
	for n in ["inventory", "equipment", "stats", "quests"]:
		assert_true((w as MisoWindowsRoot).window_by_name(n) != null, n)
		assert_false((w as MisoWindowsRoot).window_by_name(n).visible, "%s starts closed" % n)
	w.free()


# --- inventory ------------------------------------------------------------------------------------------------

func test_inventory_tabs_and_slots() -> void:
	var c := _character()
	var items := ItemService.new(c, db(), bus)
	items.gain("270", 5)
	items.gain("348", 2)
	items.gain("1157", 1)
	c.mesos = 4321
	var root := _windows(c)
	root.open_window("inventory")
	var inv := root.inventory
	assert_true(inv.visible, "opened")
	assert_eq(inv.tab_buttons.size(), Inventory.TABS.size(), "one tab per Inventory.TABS")
	assert_eq(inv.current_tab, "equip", "starts on Equip")
	assert_eq(inv.slots.size(), c.inventory.capacity("equip"), "slot count from the live inventory")
	assert_eq(inv.visible_item_ids()[0], "1157", "equip tab holds the bottom")
	assert_eq(inv.mesos_label.text, "4,321", "mesos shown")
	inv.select_tab("use")
	assert_eq(inv.visible_item_ids()[0], "270", "use tab")
	assert_eq(inv.slots[0].count_label.text, "5", "stack count")
	inv.select_tab("etc")
	assert_eq(inv.visible_item_ids()[0], "348", "etc tab")
	assert_eq(inv.slots[0].count_label.text, "2", "etc count")
	assert_eq(inv.slots[1].item_id, "", "empty slot")
	inv.select_tab("setup")
	assert_eq(inv.visible_item_ids().count(""), c.inventory.capacity("setup"), "empty tab")
	# Live updates: a pickup while the window is open.
	inv.select_tab("use")
	items.gain("270", 2)
	assert_eq(inv.slots[0].count_label.text, "7", "inventory_changed refreshes the open window")


func test_inventory_uses_and_equips_through_the_services() -> void:
	var c := _character()
	var items := ItemService.new(c, db(), bus)
	items.gain("270", 3)
	items.gain("541", 1)
	c.hp = 5
	var root := _windows(c)
	root.open_window("inventory")
	var inv := root.inventory
	inv.select_tab("use")
	inv.select_slot(0)
	assert_eq(inv.action_button.text, "Use", "consumable action")
	assert_false(inv.key_button.disabled, "a consumable can go to a quickslot")
	var res := inv.activate_slot(0)
	assert_true(res.get("ok", false), "used: %s" % str(res))
	assert_eq(c.inventory.count("270"), 2, "decremented")
	assert_true(c.hp > 5, "HP restored")
	assert_eq(int(seen.get("item_used", 0)), 1, "item_used through ItemService")
	assert_eq(inv.slots[0].count_label.text, "2", "count refreshed")

	inv.select_tab("equip")
	var old_weapon := c.equipment.weapon_id()
	var idx := inv.visible_item_ids().find("541")
	inv.select_slot(idx)
	assert_eq(inv.action_button.text, "Equip", "equipment action")
	assert_true(inv.key_button.disabled, "equipment cannot go to a quickslot")
	res = inv.activate_slot(idx)
	assert_true(res.get("ok", false), "equipped: %s" % str(res))
	assert_eq(c.equipment.weapon_id(), "541", "weapon slot")
	assert_true(old_weapon in inv.visible_item_ids(), "the previous weapon went back to the bag")
	assert_true(int(seen.get("equipment_changed", 0)) >= 1, "equipment_changed through ItemService")

	# A requirement failure is reported, not applied.
	var high := _too_high_item(c)
	assert_ne(high, "", "canonical data has a higher-level piece")
	items.gain(high, 1)
	idx = inv.visible_item_ids().find(high)
	var notices := int(seen.get("notice", 0))
	res = inv.activate_slot(idx)
	assert_false(res.get("ok", true), "refused")
	assert_eq(String(res.get("code")), ItemCodes.LEVEL_TOO_LOW, "level requirement")
	assert_true("level" in inv.status_label.text, "reason shown: " + inv.status_label.text)
	assert_eq(int(seen.get("notice", 0)), notices + 1, "Events.notice for the HUD log")
	assert_true(high in inv.visible_item_ids(), "still in the bag")

	# Etc items cannot be used.
	items.gain("348", 1)
	inv.select_tab("etc")
	res = inv.activate_slot(0)
	assert_eq(String(res.get("code")), ItemCodes.NOT_USABLE, "etc not usable")


func test_inventory_quickslot_assignment_and_drag_move() -> void:
	var c := _character()
	var items := ItemService.new(c, db(), bus)
	items.gain("270", 4)
	items.gain("348", 1)
	var root := _windows(c)
	root.open_window("inventory")
	var inv := root.inventory
	inv.select_tab("use")
	inv.select_slot(0)
	assert_true(inv.assign_quickslot("3"), "assign through the key picker")
	assert_eq(MisoQuickslots.item_for(c, "3"), "270", "stored in CharacterState.quickslots")
	inv.select_tab("etc")
	inv.select_slot(0)
	assert_false(inv.assign_quickslot("4"), "Etc items cannot be bound")
	assert_false(c.quickslots.has("4"), "nothing stored")

	inv.select_tab("use")
	var target: MisoItemSlot = inv.slots[5]
	var drag: Variant = inv.slots[0].drag_source.call(inv.slots[0])
	assert_true(target.drop_filter.call(target, drag), "same-tab move allowed")
	target.drop_handler.call(target, drag)
	assert_eq(inv.visible_item_ids()[5], "270", "moved to slot 5")
	assert_eq(inv.visible_item_ids()[0], "", "slot 0 now empty")
	assert_eq(c.inventory.get_slot("use", 5).get("item_id"), "270", "moved in the model (ItemService.move)")


# --- equipment ------------------------------------------------------------------------------------------------

func test_equipment_doll_unequip_and_full_inventory() -> void:
	var c := _character()
	var root := _windows(c)
	root.open_window("equipment")
	var eq := root.equipment
	var weapon := c.equipment.weapon_id()
	assert_ne(weapon, "", "the factory character wears a weapon")
	for slot_name in ItemsConfig.equipment_slots(db()):
		assert_true(eq.slot_controls.has(slot_name), "doll has a %s slot" % slot_name)
	assert_eq((eq.slot_controls["weapon"] as MisoItemSlot).item_id, weapon, "weapon shown")
	var watk := int(ItemDef.of(weapon, db()).bonuses["watk"])
	assert_eq(int(eq.bonus_lines().get("watk", 0)), watk, "equipment W.ATK contribution")

	# Fill the Equip tab, then try to take the weapon off: refused, nothing changes.
	var items := ItemService.new(c, db(), null)
	items.gain("1157", c.inventory.free_slots("equip"))
	assert_eq(c.inventory.free_slots("equip"), 0, "equip tab full")
	var notices := int(seen.get("notice", 0))
	var res := eq.unequip_slot("weapon")
	assert_false(res.get("ok", true), "refused")
	assert_eq(String(res.get("code")), ItemCodes.INVENTORY_FULL, "inventory full")
	assert_eq(c.equipment.weapon_id(), weapon, "still equipped")
	assert_true("full" in eq.status_label.text, "message: " + eq.status_label.text)
	assert_eq(int(seen.get("notice", 0)), notices + 1, "notice for the HUD")

	items.lose("1157", 1)
	res = eq.unequip_slot("weapon")
	assert_true(res.get("ok", false), "unequipped")
	assert_eq(c.equipment.weapon_id(), "", "weapon slot empty")
	assert_eq(c.inventory.count(weapon), 1, "back in the bag")
	assert_eq((eq.slot_controls["weapon"] as MisoItemSlot).item_id, "", "doll updated")
	assert_eq(int(eq.bonus_lines().get("watk", 0)), 0, "contribution gone")

	# Drag from the inventory onto the doll equips.
	var idx := int(c.inventory.find(weapon).get("index", -1))
	var drag := {"kind": MisoQuickslots.DRAG_KIND, "source": "inventory", "tab": "equip", "index": idx, "item_id": weapon}
	var ws: MisoItemSlot = eq.slot_controls["weapon"]
	assert_true(ws.drop_filter.call(ws, drag), "a weapon may drop on the weapon slot")
	assert_false((eq.slot_controls["hat"] as MisoItemSlot).drop_filter.call(eq.slot_controls["hat"], drag), "not on the hat slot")
	ws.drop_handler.call(ws, drag)
	assert_eq(c.equipment.weapon_id(), weapon, "re-equipped by drop")


# --- stats ----------------------------------------------------------------------------------------------------

func test_stats_window_applies_ap_and_refreshes_derived_numbers() -> void:
	var c := _character()
	var root := _windows(c)
	root.open_window("stats")
	var st := root.stats
	assert_false((st.plus_buttons["str"] as Button).visible, "no + without AP")
	Progression.gain_exp(c, Progression.exp_to_next(c.level, db()), db())
	assert_true(c.ap > 0, "a level-up grants AP")
	bus.emit_signal("leveled_up", c.level)
	assert_true((st.plus_buttons["str"] as Button).visible, "+ shown once AP is available")
	assert_eq(st.ap_label.text, str(c.ap), "AP shown")

	var snap := StatCalculator.snapshot(c, db())
	assert_eq(st.value_text("str"), str(int(snap["str"])), "STR total")
	assert_eq(st.value_text("damage"), "%d ~ %d" % [int(snap["damage_min"]), int(snap["damage_max"])], "damage range")
	assert_eq(st.value_text("acc"), str(int(snap["acc"])), "ACC")
	assert_eq(st.value_text("avoid"), str(int(snap["avoid"])), "AVOID")
	assert_eq(st.value_text("wdef"), str(int(snap["wdef"])), "W.DEF")
	assert_eq(st.value_text("mdef"), str(int(snap["mdef"])), "M.DEF")
	assert_eq(st.value_text("magic"), str(int(snap["matk"])), "Magic")
	assert_eq(st.value_text("speed"), "%d%%" % int(snap["speed"]), "Speed")
	assert_eq(st.value_text("jump"), "%d%%" % int(snap["jump"]), "Jump")
	assert_eq(st.value_text("level"), str(c.level), "level")
	assert_eq(st.value_text("job"), String(db().formula(c.job).get("name")), "job")

	var ap := c.ap
	var base_str := c.get_base_stat("str")
	var stats_before := int(seen.get("stats_changed", 0))
	assert_true(st.add_point("str"), "spent")
	assert_eq(c.get_base_stat("str"), base_str + 1, "STR +1")
	assert_eq(c.ap, ap - 1, "AP -1")
	assert_true(int(seen.get("stats_changed", 0)) > stats_before, "Game.allocate_ap announced it")
	var after := StatCalculator.snapshot(c, db())
	assert_eq(st.value_text("str"), str(int(after["str"])), "STR refreshed")
	assert_eq(st.value_text("damage"), "%d ~ %d" % [int(after["damage_min"]), int(after["damage_max"])], "damage refreshed")
	assert_ne(int(after["damage_max"]), int(snap["damage_max"]), "STR moved the damage range")

	# Spend the rest through the buttons; + disappears at 0 AP.
	while c.ap > 0:
		(st.plus_buttons["dex"] as Button).pressed.emit()
	assert_false((st.plus_buttons["dex"] as Button).visible, "+ hidden at 0 AP")
	assert_eq(st.ap_label.text, "0", "AP 0")
	assert_false(st.add_point("luk"), "no AP left: refused")


## STR / DEX / INT / LUK each keep their value on their own row, with or without AP. A GridContainer skips hidden
## children, so hiding the "+" at 0 AP used to reflow the 3-column grid into "STR 9 DEX" / "8 INT 4" / "LUK 4".
func test_stats_rows_keep_each_value_beside_its_name_at_any_ap() -> void:
	var c := _character()
	var root := _windows(c)
	root.open_window("stats")
	var st := root.stats
	assert_eq(c.ap, 0, "a new Beginner has every creation AP placed")
	var rows_0 := _stat_rows(st, "AP 0")
	Progression.gain_exp(c, Progression.exp_to_next(c.level, db()), db())
	bus.emit_signal("leveled_up", c.level)
	assert_true(c.ap > 0, "a level-up grants AP")
	var rows_ap := _stat_rows(st, "AP %d" % c.ap)
	for stat in CharacterState.STAT_KEYS:
		assert_eq(rows_ap[stat], rows_0[stat], "%s keeps its row when the '+' appears" % stat)
	while c.ap > 0:
		assert_true(st.add_point("dex"), "spent")
	var rows_spent := _stat_rows(st, "AP spent")
	for stat in CharacterState.STAT_KEYS:
		assert_eq(rows_spent[stat], rows_0[stat], "%s keeps its row when the '+' goes" % stat)


## Lays the window out (containers sort deferred) and checks each stat's value against its name label: same row (the
## playtest's 2 px tolerance), value to the right, rows in STAT_KEYS order. Returns stat -> the row's global y.
func _stat_rows(st: MisoStatsWindow, tag: String) -> Dictionary:
	st.reset_size()
	st.propagate_notification(Container.NOTIFICATION_SORT_CHILDREN)
	var out := {}
	var last_y := -INF
	for stat in CharacterState.STAT_KEYS:
		var v := st.values[stat] as Label
		var name_l := v.get_parent().get_child(v.get_index() - 1) as Label
		assert_true(name_l != null, "%s %s: the cell before the value is the name label" % [tag, stat])
		if name_l == null:
			continue
		assert_eq(name_l.text, String(MisoUiText.STAT_NAMES.get(stat, stat.to_upper())), "%s %s: name label" % [tag, stat])
		var vr := v.get_global_rect()
		var nr := name_l.get_global_rect()
		assert_true(absf(vr.position.y - nr.position.y) <= 2.0, "%s %s: value '%s' at y %.0f on its name's row (y %.0f)"
			% [tag, stat, v.text, vr.position.y, nr.position.y])
		assert_true(vr.position.x > nr.position.x, "%s %s: value right of its name" % [tag, stat])
		assert_true(nr.position.y > last_y, "%s %s: below the previous stat's row" % [tag, stat])
		last_y = nr.position.y
		out[stat] = nr.position.y
	return out


# --- quests ---------------------------------------------------------------------------------------------------

func test_quest_log_shows_sams_suggestion_progress_after_kills() -> void:
	var c := _character()
	var qs := QuestService.create(bus, db(), c, RandomNumberGenerator.new())
	qs.attach()
	var root := _windows(c)
	game.quests = qs
	root.open_window("quests")
	var ql := root.quests
	assert_eq(ql.entries.size(), 0, "nothing in progress yet")
	ql.select_tab(MisoQuestWindow.TAB_AVAILABLE)
	var available: PackedStringArray = []
	for e: Dictionary in ql.entries:
		available.append(String(e["quest_id"]))
	assert_true("1006" in available, "Sam's Suggestion is available to a new Beginner")

	assert_true(qs.accept("1006").get("ok", false), "accepted")
	ql.select_tab(MisoQuestWindow.TAB_IN_PROGRESS)
	assert_eq(ql.selected_quest, "1006", "selected")
	var kill: Dictionary = {}
	for o: Dictionary in qs.engine.definition("1006").objectives:
		if o["kind"] == "monster_kills":
			kill = o
	var need := int(kill["count"])
	for i in 7:
		bus.emit_signal("monster_killed", String(kill["id"]), "000000040")
	var rows := ql.objective_rows()
	var kill_text := "%s 7/%d" % [String(kill["name"]), need]
	var found := false
	for r: Dictionary in rows:
		if r["text"] == kill_text:
			found = true
			assert_false(r["done"], "not done at 7")
	assert_true(found, "objective row '%s' in %s" % [kill_text, str(rows)])
	var texts := ql.detail_texts()
	assert_true(String(db().quest("1006").get("name")) in texts, "quest name")
	assert_true("Talk to %s" % String(db().npc(qs.engine.definition("1006").end_npc_id).get("name")) in texts,
		"turn-in row (Mai not met yet, so not 'Return to')")
	var d := qs.engine.definition("1006")
	assert_true("EXP  +%d" % d.reward_exp in texts, "canonical EXP reward")
	for it: Dictionary in d.reward_items:
		var nm := String(db().item(String(it["item_id"])).get("name"))
		var line := "%s%s" % [nm, " x%d" % int(it["count"]) if int(it["count"]) > 1 else ""]
		assert_true(line in texts, "item reward '%s'" % line)

	for i in need:
		bus.emit_signal("monster_killed", String(kill["id"]), "000000040")
	for r: Dictionary in ql.objective_rows():
		if String(r["text"]).begins_with(String(kill["name"])):
			assert_eq(r["text"], "%s %d/%d" % [String(kill["name"]), need, need], "capped at the requirement")
			assert_true(r["done"], "ticked")
	qs.detach()


## Available quests whose start NPC stands on the current map come first, marked "[nearby]". Canonical NPCs give their
## map in locations[].map_id (no top-level map_id): Sam (9), who starts Sam's Suggestion (1006), is in 000000040.
func test_quest_log_marks_quests_whose_start_npc_is_here_nearby() -> void:
	var c := _character()
	var qs := QuestService.create(bus, db(), c, RandomNumberGenerator.new())
	var root := _windows(c)
	game.quests = qs
	assert_eq(qs.engine.definition("1006").start_npc_id, "9", "Sam starts Sam's Suggestion (canonical)")
	var sam_maps: PackedStringArray = []
	for loc: Dictionary in db().npc("9").get("locations", []):
		sam_maps.append(String(loc.get("map_id", "")))
	assert_true("000000040" in sam_maps, "Sam stands in Snail Hunting Ground I: %s" % sam_maps)
	c.location["map_id"] = "000000040"
	root.open_window("quests")
	var ql := root.quests
	ql.select_tab(MisoQuestWindow.TAB_AVAILABLE)
	assert_true(ql.entries.size() > 1, "several quests are available to a new Beginner")
	assert_eq(String(ql.entries[0]["quest_id"]), "1006", "Sam's quest is listed first in his map")
	assert_true(bool(ql.entries[0]["nearby"]), "and marked nearby")
	assert_true(_quest_button_text(ql, "1006").ends_with("[nearby]"), "list: '%s'" % _quest_button_text(ql, "1006"))
	assert_true("Available nearby" in " ".join(ql.detail_texts()), "detail status: %s" % ql.detail_texts())
	for e: Dictionary in ql.entries:
		var here := false
		for loc: Dictionary in db().npc(String(e.get("start_npc_id", ""))).get("locations", []):
			here = here or String(loc.get("map_id", "")) == "000000040"
		assert_eq(bool(e["nearby"]), here, "quest %s nearby only when its start NPC is here" % e["quest_id"])
	# Elsewhere Sam's quest is an ordinary available quest.
	c.location["map_id"] = "000000041"
	ql.refresh()
	var sam_entry: Dictionary = {}
	for e: Dictionary in ql.entries:
		if String(e["quest_id"]) == "1006":
			sam_entry = e
	assert_false(sam_entry.is_empty(), "still available")
	assert_false(bool(sam_entry.get("nearby", true)), "not nearby in 000000041")
	assert_false(_quest_button_text(ql, "1006").contains("[nearby]"), "no tag: '%s'" % _quest_button_text(ql, "1006"))
	ql.select_quest("1006")
	assert_false("Available nearby" in " ".join(ql.detail_texts()), "detail status: %s" % ql.detail_texts())


func _quest_button_text(ql: MisoQuestWindow, quest_id: String) -> String:
	for b in ql.list_box.get_children():
		if b is Button and String(b.get_meta("quest_id", "")) == quest_id:
			return (b as Button).text
	return ""


# --- the window stack -----------------------------------------------------------------------------------------

func test_windows_register_and_close_through_the_ctx_stack() -> void:
	var c := _character()
	var ctx := GameContext.new()
	var changes: Array = []
	ctx.window_changed.connect(func(w: Control, open: bool) -> void: changes.append([w.name, open]))
	var root := _windows(c, ctx)
	assert_false(ctx.has_open_windows(), "nothing open")
	root.open_window("inventory")
	root.open_window("stats")
	assert_true(ctx.has_open_windows(), "registered")
	assert_true(ctx.close_top_window(), "Esc closes one")
	assert_false(root.is_open("stats"), "the newest (stats) closed first")
	assert_true(root.is_open("inventory"), "inventory still open")
	root.open_window("quests")
	root.open_window("inventory")
	assert_true(ctx.close_top_window(), "Esc again")
	assert_false(root.is_open("inventory"), "re-focused inventory is now the newest")
	assert_true(root.is_open("quests"), "quests still open")
	root.quests.close_button.pressed.emit()
	assert_false(root.is_open("quests"), "close button")
	assert_false(ctx.has_open_windows(), "close button unregistered it")
	assert_false(ctx.close_top_window(), "nothing left to close")
	assert_true(changes.size() >= 4, "window_changed reported: %s" % str(changes))


func test_hotkeys_toggle_and_respect_modals() -> void:
	var c := _character()
	var ctx := GameContext.new()
	var root := _windows(c, ctx)
	for action: String in MisoWindowsRoot.ACTIONS:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = true
		root._unhandled_input(ev)
		assert_true(root.is_open(MisoWindowsRoot.ACTIONS[action]), "%s opens" % action)
		root._unhandled_input(ev)
		assert_false(root.is_open(MisoWindowsRoot.ACTIONS[action]), "%s closes" % action)
	var owner := RefCounted.new()
	ctx.push_modal(owner)
	var ev2 := InputEventAction.new()
	ev2.action = "toggle_inventory"
	ev2.pressed = true
	root._unhandled_input(ev2)
	assert_false(root.is_open("inventory"), "hotkeys are quiet while a modal owns the keyboard")
	ctx.pop_modal(owner)
	root._unhandled_input(ev2)
	assert_true(root.is_open("inventory"), "back after the modal closes")
	# The HUD's buttons reach the windows through the group.
	var hud := MisoHud.new()
	hud.configure(MisoUiEnv.isolated(c, db(), bus, ctx))
	_parent().add_child(hud)
	nodes.append(hud)
	(hud.status.menu_buttons["quests"] as Button).pressed.emit()
	assert_true(root.is_open("quests"), "HUD Quest button opens the quest log")


func test_default_window_positions_do_not_overlap() -> void:
	var c := _character()
	ItemService.new(c, db(), null).gain("270", 3)
	var root := _windows(c)
	var area := root.get_viewport_rect().size
	assert_true(area.x >= 1600.0 and area.y >= 900.0, "the base viewport (1600 x 900 or more): %s" % area)
	# Opened in an order other than the row order: placement must not depend on it.
	for n in ["quests", "inventory", "stats", "equipment"]:
		root.open_window(n)
	var rects := {}
	for n in ["stats", "quests", "equipment", "inventory"]:
		var w := root.window_by_name(n)
		var r := Rect2(w.position, w.size.max(w.get_combined_minimum_size()))
		rects[n] = r
		assert_true(r.position.x >= 0.0 and r.end.x <= area.x, "%s inside the viewport horizontally: %s" % [n, r])
		assert_true(r.position.y >= 0.0 and r.end.y <= area.y, "%s inside the viewport vertically: %s" % [n, r])
	var names: Array = rects.keys()
	for i in names.size():
		for j in range(i + 1, names.size()):
			var a: Rect2 = rects[names[i]]
			var b: Rect2 = rects[names[j]]
			assert_false(a.intersects(b), "%s %s and %s %s overlap" % [names[i], a, names[j], b])
	assert_true((rects["inventory"] as Rect2).position.x > (rects["equipment"] as Rect2).position.x,
		"inventory on the right edge, equipment beside it")


func test_clicking_inside_a_back_window_makes_it_the_newest() -> void:
	var c := _character()
	ItemService.new(c, db(), null).gain("270", 3)
	var ctx := GameContext.new()
	var root := _windows(c, ctx)
	root.open_window("inventory")
	root.open_window("stats")
	root.inventory.select_tab("use")
	# Lay the windows out now (containers sort deferred) so the click lands on a real slot, which stops the event
	# before the window's own _gui_input would see it.
	for w: MisoWindow in [root.inventory, root.stats]:
		w.reset_size()
		w.propagate_notification(Container.NOTIFICATION_SORT_CHILDREN)
	var slot: MisoItemSlot = root.inventory.slots[0]
	var at := slot.get_global_rect().get_center()
	assert_true(Rect2(root.inventory.position, root.inventory.size).has_point(at), "the slot lies inside the inventory")
	assert_false(Rect2(root.stats.position, root.stats.size).has_point(at), "the click point is not under the stats window")
	assert_true(root.inventory.is_frontmost_at(at), "the inventory is the window under the point")
	assert_false(root.stats.is_frontmost_at(at), "the stats window is not")
	var vp := root.get_viewport()
	var m := InputEventMouseMotion.new()
	m.position = at
	m.global_position = at
	vp.push_input(m, true)
	for pressed: bool in [true, false]:
		var b := InputEventMouseButton.new()
		b.position = at
		b.global_position = at
		b.button_index = MOUSE_BUTTON_LEFT
		b.pressed = pressed
		vp.push_input(b, true)
	assert_eq(root.inventory.selected_index, 0, "the press reached the slot (it selected it)")
	assert_true(ctx.close_top_window(), "Esc closes one window")
	assert_false(root.is_open("inventory"), "the clicked (back) inventory became the newest window")
	assert_true(root.is_open("stats"), "stats stays open")


func test_window_drags_by_its_title_and_stays_on_screen() -> void:
	var c := _character()
	var root := _windows(c)
	root.open_window("stats")
	var w := root.stats
	w.reset_size()
	w.propagate_notification(Container.NOTIFICATION_SORT_CHILDREN)
	var start := w.position
	var grab := w.title_label.get_global_rect().get_center()
	var vp := root.get_viewport()
	Input.action_press(&"attack")  # an attack key held while the window is dragged
	_push_button(vp, grab, true)
	assert_true(Input.is_action_pressed(&"attack"), "a title press leaves the attack action alone (PlayerCombat ignores "
		+ "GUI presses; test_ui_drag_attack covers the swings)")
	_push_motion(vp, grab + Vector2(200, 100))
	assert_eq(w.position, start + Vector2(200, 100), "the window follows the pointer")
	_push_motion(vp, grab + Vector2(5000, 5000))
	var area := root.get_viewport_rect().size
	assert_eq(w.position.x, area.x - w.size.x, "clamped to the right edge")
	assert_eq(w.position.y, area.y - 40.0, "the title strip stays on screen")
	_push_button(vp, grab + Vector2(5000, 5000), false)
	_push_motion(vp, grab)
	assert_eq(w.position.y, area.y - 40.0, "released: no longer dragging")
	Input.action_release(&"attack")


func _push_motion(vp: Viewport, at: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = at
	m.global_position = at
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	vp.push_input(m, true)


func _push_button(vp: Viewport, at: Vector2, pressed: bool) -> void:
	var b := InputEventMouseButton.new()
	b.position = at
	b.global_position = at
	b.button_index = MOUSE_BUTTON_LEFT
	b.pressed = pressed
	b.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	vp.push_input(b, true)


func test_standalone_root_handles_escape_itself() -> void:
	var c := _character()
	var root := _windows(c)
	assert_true(root.env.owns_ctx, "private window stack")
	root.open_window("equipment")
	var esc := InputEventAction.new()
	esc.action = "menu"
	esc.pressed = true
	root._unhandled_input(esc)
	assert_false(root.is_open("equipment"), "Esc closes the newest window standalone")


# --- tooltip and icons ----------------------------------------------------------------------------------------

func test_tooltip_rows_and_unmet_requirements() -> void:
	var c := _character()
	var high := _too_high_item(c)
	var rows := MisoItemTooltip.describe(high, c, db())
	var def := ItemDef.of(high, db())
	assert_eq(String(rows[0]["text"]), def.name, "name first")
	var lev_row: Dictionary = {}
	for r: Dictionary in rows:
		if String(r["text"]) == "REQ LEV: %d" % def.req_level:
			lev_row = r
	assert_eq(String(lev_row.get("tone", "")), "bad", "an unmet level requirement is red")
	c.level = def.req_level
	for r: Dictionary in MisoItemTooltip.describe(high, c, db()):
		if String(r["text"]) == "REQ LEV: %d" % def.req_level:
			assert_eq(String(r["tone"]), "text", "met requirement is plain")
	var potion := ItemDef.of("270", db())
	var prows := MisoItemTooltip.describe("270", c, db(), {"qty": 5})
	var texts: PackedStringArray = []
	for r: Dictionary in prows:
		texts.append(String(r["text"]))
	assert_true("%s (x5)" % potion.name in texts, "name with quantity")
	assert_true("Recovers %d HP" % potion.hp_flat in texts, "canonical effect")
	assert_true(MisoItemTooltip.price_text(potion) in texts, "sell price")
	assert_true(potion.description.strip_edges() in texts, "description")
	# Shown in the window: hovering a slot fills the shared tooltip.
	ItemService.new(c, db(), null).gain("270", 2)
	var root := _windows(c)
	root.open_window("inventory")
	root.inventory.select_tab("use")
	root.inventory.slots[0].hover_changed.emit(root.inventory.slots[0], true)
	assert_true(root.tooltip.visible, "tooltip shown on hover")
	assert_eq(String(root.tooltip.rows[0]["text"]), "%s (x2)" % potion.name, "tooltip for the hovered stack")
	root.inventory.slots[0].hover_changed.emit(root.inventory.slots[0], false)
	assert_false(root.tooltip.visible, "hidden on exit")


## The card sits beside its anchor and never covers it: right of it when that fits, else left of it, else above or
## below; kept on screen. Before, a slot near the right edge got the card flipped back over itself.
func test_item_tooltip_sits_beside_its_anchor() -> void:
	var c := _character()
	var tip := MisoItemTooltip.new()
	tip.top_level = true
	tip.theme = MisoTheme.get_theme()
	_parent().add_child(tip)
	nodes.append(tip)
	tip.show_item("270", c, db(), {"qty": 2, "hint": "Double-click to use"})
	var bounds := Rect2(0, 0, 1600, 900)
	var cases := {
		"right edge": Rect2(1540, 300, 48, 48), "left edge": Rect2(12, 300, 48, 48), "bottom-right corner": Rect2(1540, 846, 48, 48),
		"top-right corner": Rect2(1540, 4, 48, 48), "middle": Rect2(780, 420, 48, 48),
	}
	for what: String in cases:
		var anchor: Rect2 = cases[what]
		tip.place_beside(anchor, bounds)
		var r := Rect2(tip.global_position, tip.size)
		assert_false(r.intersects(anchor), "%s: the card %s covers the anchor %s" % [what, r, anchor])
		assert_true(bounds.encloses(r), "%s: the card %s stays on screen" % [what, r])
	tip.place_beside(cases["left edge"], bounds)
	assert_true(tip.global_position.x >= cases["left edge"].end.x, "room on the right: the card goes right")
	tip.place_beside(cases["right edge"], bounds)
	assert_true(tip.global_position.x + tip.size.x <= cases["right edge"].position.x, "no room on the right: left")
	# Too narrow for either side: above (or below near the top), never over the anchor.
	var narrow := Rect2(0, 0, tip.size.x + 60.0, 900)
	for anchor: Rect2 in [Rect2(30, 700, 48, 48), Rect2(30, 10, 48, 48)]:
		tip.place_beside(anchor, narrow)
		var r := Rect2(tip.global_position, tip.size)
		assert_false(r.intersects(anchor), "narrow: the card %s covers the anchor %s" % [r, anchor])
		assert_true(narrow.encloses(r), "narrow: on screen %s" % r)

	# In the windows: the right-docked inventory and the Equipment doll beside it.
	ItemService.new(c, db(), null).gain("270", 2)
	var root := _windows(c)
	root.open_window("equipment")
	root.open_window("inventory")
	root.inventory.select_tab("use")
	for w: MisoWindow in [root.inventory, root.equipment]:
		w.reset_size()
		w.propagate_notification(Container.NOTIFICATION_SORT_CHILDREN)
	var view := root.get_viewport_rect()
	var hovered: Array = [root.inventory.slots[0]]
	for s: String in root.equipment.slot_controls:
		if not (root.equipment.slot_controls[s] as MisoItemSlot).is_empty():
			hovered.append(root.equipment.slot_controls[s])
	assert_true(hovered.size() > 1, "the Beginner wears something")
	for slot: MisoItemSlot in hovered:
		slot.hover_changed.emit(slot, true)
		assert_true(root.tooltip.visible, "shown for %s" % slot.item_id)
		var r := Rect2(root.tooltip.global_position, root.tooltip.size)
		var a := slot.get_global_rect()
		assert_false(r.intersects(a), "hovering %s at %s: the card %s covers the slot" % [slot.item_id, a, r])
		assert_true(view.encloses(r), "the card %s stays on screen %s" % [r, view])
		slot.hover_changed.emit(slot, false)


func test_every_canonical_item_has_a_procedural_icon() -> void:
	for id in db().ids("items"):
		var d := ItemDef.of(id, db())
		var shape := MisoItemIcon.shape_for(d)
		assert_ne(shape, "unknown", "item %s (%s) has a shape" % [id, d.name])
	assert_eq(MisoItemIcon.shape_for(ItemDef.of("270", db())), "potion", "Red Potion")
	assert_eq(MisoItemIcon.color_for(ItemDef.of("270", db())), MisoItemIcon.COLOR_WORDS.filter(
		func(p: Array) -> bool: return p[0] == "red")[0][1], "red tint from the name")
	assert_eq(MisoItemIcon.color_for(null, "x"), MisoItemIcon.color_for(null, "x"), "stable fallback hue")
