extends TestCase
## The character windows (res://scenes/ui/windows.tscn, MisoWindowsRoot): Inventory (tabs, slots, use / equip /
## move / quickslot through the services), Equipment (doll, unequip, full inventory, bonuses), Character Stats (AP
## through Game.allocate_ap, derived numbers), Quest Log (Sam's Suggestion progress), the GameContext window stack,
## hotkeys, modal suppression, and the item tooltip. Private events.gd bus, injected character, no autoload state.

var bus: Node
var nodes: Array = []
var game: GameState = null
var seen: Dictionary = {}


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
	assert_true("Return to %s" % String(db().npc(qs.engine.definition("1006").end_npc_id).get("name")) in texts,
		"turn-in row")
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
	Input.action_press(&"attack")
	_push_button(vp, grab, true)
	assert_false(Input.is_action_pressed(&"attack"), "a title press is not an attack (the drag may leave the window)")
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


func test_a_ui_drag_releases_the_mouse_attack() -> void:
	# The left button is an attack binding and PlayerCombat polls Input: a drag that starts on a slot must not keep
	# the attack held while it crosses the world (MisoUiEnv.release_attack_action, UI.md "Known gaps").
	assert_true(InputMap.has_action("attack"), "Controls registers attack")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(-50, -50)
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	assert_true(Input.is_action_pressed(&"attack"), "the mouse press holds the attack action")
	MisoUiEnv.release_attack_action()
	assert_false(Input.is_action_pressed(&"attack"), "released when a UI drag starts")
	var up := press.duplicate() as InputEventMouseButton
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	assert_false(Input.is_action_pressed(&"attack"), "still released after the button goes up")


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


func test_every_canonical_item_has_a_procedural_icon() -> void:
	for id in db().ids("items"):
		var d := ItemDef.of(id, db())
		var shape := MisoItemIcon.shape_for(d)
		assert_ne(shape, "unknown", "item %s (%s) has a shape" % [id, d.name])
	assert_eq(MisoItemIcon.shape_for(ItemDef.of("270", db())), "potion", "Red Potion")
	assert_eq(MisoItemIcon.color_for(ItemDef.of("270", db())), MisoItemIcon.COLOR_WORDS.filter(
		func(p: Array) -> bool: return p[0] == "red")[0][1], "red tint from the name")
	assert_eq(MisoItemIcon.color_for(null, "x"), MisoItemIcon.color_for(null, "x"), "stable fallback hue")
