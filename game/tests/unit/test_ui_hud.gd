extends TestCase
## The HUD (res://scenes/ui/hud.tscn, MisoHud): values follow Events, the message log, the map banner, the level-up
## flourish, and quickslots (bind, use through ItemService, decrement, persistence in CharacterState.quickslots).
## Every test runs on a private events.gd bus and an injected character: no autoload state is read or changed.

var bus: Node
var nodes: Array = []
var counts: Dictionary = {}


func before_each() -> void:
	bus = load("res://scripts/autoload/events.gd").new()
	counts = {}
	for sig in ["item_used", "inventory_changed", "hp_changed", "notice"]:
		var n := _arg_count(sig)
		bus.connect(sig, _count.bind(sig).unbind(n) if n > 0 else _count.bind(sig))


func after_each() -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.free()
	nodes.clear()
	bus.free()


func _arg_count(sig: String) -> int:
	for s in bus.get_signal_list():
		if String(s["name"]) == sig:
			return (s["args"] as Array).size()
	return 0


func _count(sig: String) -> void:
	counts[sig] = int(counts.get(sig, 0)) + 1


func _character() -> CharacterState:
	var cr := CharacterFactory.create(CharacterFactory.default_params(db()), db())
	assert_true(cr.ok, "factory character")
	return cr.character


func _hud(c: CharacterState, ctx: GameContext = null) -> MisoHud:
	var h: MisoHud = load("res://scenes/ui/hud.tscn").instantiate()
	h.configure(MisoUiEnv.isolated(c, db(), bus, ctx))
	_parent().add_child(h)
	nodes.append(h)
	return h


func _has_line(h: MisoHud, text: String) -> bool:
	return text in h.log_panel.texts()


func test_scene_root_implements_setup() -> void:
	var h: Node = load("res://scenes/ui/hud.tscn").instantiate()
	assert_true(h is MisoHud, "hud.tscn root is MisoHud")
	assert_true(h.has_method("setup"), "setup(ctx)")
	h.free()


func test_initial_values_come_from_the_character() -> void:
	var c := _character()
	c.mesos = 1234567
	var h := _hud(c)
	var max_hp := StatCalculator.max_hp(c, db())
	var max_mp := StatCalculator.max_mp(c, db())
	assert_eq(h.status.level_label.text, str(c.level), "level")
	assert_eq(h.status.name_label.text, c.name, "name")
	assert_eq(h.status.job_label.text, String(db().formula(c.job).get("name")), "job display name from canonical data")
	assert_eq(h.status.hp_gauge.value_label.text, "%d / %d" % [c.hp, max_hp], "HP")
	assert_eq(h.status.mp_gauge.value_label.text, "%d / %d" % [c.mp, max_mp], "MP")
	assert_eq(h.status.mesos_label.text, "1,234,567", "mesos with separators")
	var need := Progression.exp_to_next(c.level, db())
	assert_true(h.status.exp_gauge.value_label.text.begins_with("0 / %d" % need), "EXP: " + h.status.exp_gauge.value_label.text)
	assert_true("[0.00%]" in h.status.exp_gauge.value_label.text, "EXP percent")
	assert_eq(h.status.quickslots.slots.size(), MisoQuickslots.keys().size(), "one quickslot per quickslot_N action")
	assert_eq(MisoQuickslots.keys().size(), 8, "the Controls contract registers quickslot_1..8")


func test_values_follow_events() -> void:
	var c := _character()
	var h := _hud(c)
	bus.emit_signal("hp_changed", 30, 50)
	assert_eq(h.status.hp_gauge.value_label.text, "30 / 50", "hp_changed payload")
	assert_near(h.status.hp_gauge.ratio(), 0.6, 1e-6, "HP fill")
	bus.emit_signal("mp_changed", 2, 5)
	assert_eq(h.status.mp_gauge.value_label.text, "2 / 5", "mp_changed payload")

	c.mesos = 120
	bus.emit_signal("mesos_changed", 120, 20)
	assert_eq(h.status.mesos_label.text, "120", "mesos")
	assert_true(_has_line(h, "You have gained mesos (+20)"), "meso gain line")
	var lines_before := h.log_panel.history.size()
	bus.emit_signal("mesos_changed", 120, 0)
	assert_eq(h.log_panel.history.size(), lines_before, "a refresh (delta 0) logs nothing")

	var need := Progression.exp_to_next(c.level, db())
	c.exp = 7
	bus.emit_signal("exp_gained", 7, "monster:2")
	assert_true(h.status.exp_gauge.value_label.text.begins_with("7 / %d" % need), "EXP follows exp_gained")
	assert_true("[%.2f%%]" % (700.0 / need) in h.status.exp_gauge.value_label.text, "EXP percent")
	assert_true(_has_line(h, "You have gained experience (+7)"), "EXP line")

	var potion := String(db().item("270").get("name"))
	bus.emit_signal("item_gained", "270", 3)
	assert_true(_has_line(h, "You have gained an item (%s x3)" % potion), "item line: %s" % str(h.log_panel.texts()))
	bus.emit_signal("item_gained", "270", 1)
	assert_true(_has_line(h, "You have gained an item (%s)" % potion), "single item line")
	bus.emit_signal("inventory_full", "270")
	assert_true(_has_line(h, "Your inventory is full."), "inventory full warning")
	bus.emit_signal("notice", "Hello Maple Island")
	assert_true(_has_line(h, "Hello Maple Island"), "notice line")

	# Equipment changes re-read derived maxima from the character.
	c.hp = 11
	bus.emit_signal("equipment_changed", "weapon")
	assert_eq(h.status.hp_gauge.value_label.text, "11 / %d" % StatCalculator.max_hp(c, db()), "stats re-read")


func test_level_up_flourish_and_ap_badge() -> void:
	var c := _character()
	var h := _hud(c)
	assert_eq(h.status.ap_available, 0, "no AP shown at 0 AP")
	var r := Progression.gain_exp(c, Progression.exp_to_next(c.level, db()), db())
	assert_eq(int(r["levels_gained"]), 1, "levelled")
	bus.emit_signal("leveled_up", c.level)
	assert_true(h.flourish.is_playing(), "flourish plays")
	assert_eq(h.flourish.sub.text, "Level %d" % c.level, "flourish level")
	assert_eq(h.status.level_label.text, str(c.level), "level label")
	assert_true(_has_line(h, "Congratulations! You have reached level %d." % c.level), "level line")
	assert_eq(h.status.ap_available, c.ap, "AP shown while unspent")
	var stat_button: Button = h.status.menu_buttons["stats"]
	assert_eq(String(stat_button.theme_type_variation), "MisoAccentButton", "Stat button highlighted")
	assert_true(("+%d" % c.ap) in stat_button.text, "AP on the Stat button: " + stat_button.text)
	h.flourish.advance(MisoLevelUpFlourish.DURATION_S + 0.1)
	assert_false(h.flourish.is_playing(), "flourish ends")


func test_map_banner_shows_street_and_name() -> void:
	var c := _character()
	var h := _hud(c)
	var map_id := "000000040"
	bus.emit_signal("map_entered", map_id, "")
	assert_true(h.banner.is_showing(), "banner shows")
	assert_eq(h.banner.name_label.text, String(db().map(map_id).get("name")), "canonical map name")
	assert_eq(h.banner.street_label.text, String(db().map(map_id).get("street_name")), "canonical street name")
	h.banner.advance(MisoMapBanner.FADE_IN_S * 0.5)
	assert_between(h.banner.modulate.a, 0.01, 0.99, "fading in")
	h.banner.advance(MisoMapBanner.FADE_IN_S + MisoMapBanner.HOLD_S + MisoMapBanner.FADE_OUT_S)
	assert_false(h.banner.is_showing(), "banner faded out")


func test_notice_log_fades_and_caps() -> void:
	var c := _character()
	var h := _hud(c)
	for i in MisoNoticeLog.MAX_VISIBLE + 3:
		bus.emit_signal("notice", "line %d" % i)
	assert_eq(h.log_panel.visible_count(), MisoNoticeLog.MAX_VISIBLE, "visible lines capped")
	assert_eq(h.log_panel.history.size(), MisoNoticeLog.MAX_VISIBLE + 3, "history keeps every line")
	bus.emit_signal("notice", "line 0")
	bus.emit_signal("notice", "line 0")
	assert_eq(h.log_panel.texts().count("line 0"), 2, "an identical line right away is not repeated")
	h.log_panel.advance(MisoNoticeLog.LIFETIME_S + MisoNoticeLog.FADE_S + 0.1)
	assert_eq(h.log_panel.visible_count(), 0, "lines fade away")


func test_quickslot_bind_use_decrement_and_persist() -> void:
	var c := _character()
	var items := ItemService.new(c, db(), bus)
	assert_eq(items.gain("270", 5), 5, "5 potions")
	c.hp = 10
	var h := _hud(c)
	assert_true(MisoQuickslots.bind(h.env, "1", "270"), "bind a consumable")
	assert_eq(String(c.quickslots.get("1")), "270", "binding stored in CharacterState.quickslots")
	assert_eq(h.status.quickslots.count_text("1"), "5", "count shown")

	var res := h.use_quickslot("1")
	assert_true(res.get("ok", false), "used: %s" % str(res))
	assert_eq(c.inventory.count("270"), 4, "one potion consumed")
	assert_eq(h.status.quickslots.count_text("1"), "4", "count decremented")
	assert_true(c.hp > 10, "HP restored")
	assert_eq(int(counts.get("item_used", 0)), 1, "item_used announced through ItemService")
	assert_eq(h.status.hp_gauge.value_label.text, "%d / %d" % [c.hp, StatCalculator.max_hp(c, db())], "HP gauge followed")

	# The key path: the quickslot_1 action.
	var ev := InputEventAction.new()
	ev.action = "quickslot_1"
	ev.pressed = true
	h._unhandled_input(ev)
	assert_eq(c.inventory.count("270"), 3, "the key uses the slot")

	# Persistence: the binding survives a JSON save round trip of the character.
	var restored := CharacterState.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	assert_eq(MisoQuickslots.item_for(restored, "1"), "270", "binding persisted")
	h.configure(MisoUiEnv.isolated(restored, db(), bus))
	assert_eq(h.status.quickslots.count_text("1"), "3", "restored HUD shows the binding and count")

	# Running out keeps the binding (greyed 0) and says so.
	c = restored
	ItemService.new(c, db(), null).lose("270", 3)
	h.refresh_all()
	assert_eq(h.status.quickslots.count_text("1"), "0", "empty stack shows 0")
	assert_true((h.status.quickslots.slots["1"] as MisoItemSlot).icon.dim, "greyed out")
	var empty := h.use_quickslot("1")
	assert_false(empty.get("ok", true), "nothing to use")
	assert_true(_has_line(h, "You have no %s left." % String(db().item("270").get("name"))), "out-of-stock notice")


func test_quickslot_refuses_non_consumables() -> void:
	var c := _character()
	ItemService.new(c, db(), null).gain("348", 2)
	var h := _hud(c)
	assert_false(MisoQuickslots.bind(h.env, "2", "348"), "an Etc item cannot be bound")
	assert_false(MisoQuickslots.bind(h.env, "2", c.equipment.weapon_id()), "equipment cannot be bound")
	assert_false(c.quickslots.has("2"), "nothing stored")
	assert_eq(String(h.use_quickslot("2").get("code")), ItemCodes.SLOT_EMPTY, "unbound key")
	# Drag from the inventory onto a quickslot binds; right-click (unbind) clears.
	ItemService.new(c, db(), null).gain("270", 1)
	var slot: MisoItemSlot = h.status.quickslots.slots["4"]
	var drag := {"kind": MisoQuickslots.DRAG_KIND, "source": "inventory", "tab": "use", "index": 0, "item_id": "270"}
	assert_true(slot.drop_filter.call(slot, drag), "a consumable may drop on a quickslot")
	assert_false(slot.drop_filter.call(slot, {"kind": MisoQuickslots.DRAG_KIND, "source": "inventory", "item_id": "348"}),
		"an Etc item may not")
	slot.drop_handler.call(slot, drag)
	assert_eq(MisoQuickslots.item_for(c, "4"), "270", "dropped binding")
	assert_true(MisoQuickslots.move(h.env, "4", "8"), "move a binding")
	assert_eq(MisoQuickslots.item_for(c, "8"), "270", "moved")
	assert_false(c.quickslots.has("4"), "old key cleared")
	assert_true(MisoQuickslots.unbind(h.env, "8"), "unbind")
	assert_true(c.quickslots.is_empty(), "cleared")


func test_quest_progress_lines() -> void:
	var c := _character()
	var qs := QuestService.create(bus, db(), c, RandomNumberGenerator.new())
	qs.attach()
	var h := _hud(c)
	var r := qs.accept("1006")
	assert_true(r.get("ok", false), "accepted Sam's Suggestion: %s" % str(r))
	var quest_name := String(db().quest("1006").get("name"))
	assert_true(_has_line(h, "Quest started: %s" % quest_name), "start line")
	var kill: Dictionary = {}
	for o: Dictionary in qs.engine.definition("1006").objectives:
		if o["kind"] == "monster_kills":
			kill = o
	bus.emit_signal("monster_killed", String(kill["id"]), "000000040")
	assert_true(_has_line(h, "%s: %s 1/%d" % [quest_name, String(kill["name"]), int(kill["count"])]),
		"progress line: %s" % str(h.log_panel.texts()))
	qs.detach()


func test_reparenting_keeps_the_hud_listening() -> void:
	var c := _character()
	var h := _hud(c)
	var p := h.get_parent()
	p.remove_child(h)
	c.mesos = 77
	p.add_child(h)
	assert_eq(h.status.mesos_label.text, "77", "re-entering the tree redraws what changed meanwhile")
	bus.emit_signal("hp_changed", 9, 50)
	assert_eq(h.status.hp_gauge.value_label.text, "9 / 50", "listening again after re-entering the tree")


func test_without_character_or_content_nothing_breaks() -> void:
	var h := MisoHud.new()
	h.configure(MisoUiEnv.isolated(null, null, bus))
	_parent().add_child(h)
	nodes.append(h)
	bus.emit_signal("hp_changed", 1, 2)
	assert_eq(h.status.hp_gauge.value_label.text, "1 / 2", "payload still shown")
	bus.emit_signal("leveled_up", 2)
	bus.emit_signal("map_entered", "000000040", "")
	assert_false(h.use_quickslot("1").get("ok", true), "no character: nothing used")
	assert_eq(h.status.level_label.text, "0", "no character: blank identity")


func _parent() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.current_scene if tree.current_scene != null else tree.root
