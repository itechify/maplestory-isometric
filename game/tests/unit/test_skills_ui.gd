extends TestCase
## The skill UI: the Skills window on K (the canonical Beginner skills, level / max, SP, "+" through SkillBook with
## Events.skill_leveled, "Set key" and drag to a quickslot), the SP row of the stat window, the typed quickslots of
## contract C3 ({"kind": "item" | "skill", "id"}; bare legacy ids still read as items; chairs bind and ask the sitting
## system through ItemService.use_item and Chairs.use, contract C5), the HUD bar's skill slots (icon, MP greying,
## cooldown sweep) casting through the player's PlayerSkills, and the five default window positions.

const SNAILS := "0001000"
const RECOVERY := "0001001"
const NIMBLE := "0001002"

var bus: Node
var nodes: Array = []
var game: GameState = null
var seen: Dictionary = {}
var rig: MonsterTestRig = null


func parity_keys() -> Dictionary:
	return {
		"test_skills_window_opens_on_k_and_lists_the_canonical_skills": ["ui:skill-window", "skill:0001000",
			"skill:0001001", "skill:0001002"],
		"test_plus_spends_sp_and_announces_it": ["ui:skill-window", "mechanic:sp-allocation", "ui:sp-notification"],
		"test_set_key_and_drag_bind_a_learned_skill": ["ui:skill-window", "persistence:quickslots"],
		"test_a_skill_quickslot_casts_and_shows_mp_and_cooldown": ["ui:skill-window", "skill:0001002"],
		"test_quickslot_values_are_typed_and_read_legacy_ids": ["persistence:quickslots"],
		"test_a_chair_binds_and_asks_the_sitting_system": ["chair:522"],
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
	# Input's action state is global: a held key must never leak into the next test.
	for k in MisoQuickslots.keys():
		Input.action_release(MisoQuickslots.action_for(k))
	for n in nodes:
		if is_instance_valid(n):
			n.free()
	nodes.clear()
	if game != null:
		game.free()
		game = null
	if rig != null:
		rig.free_all()
		rig = null
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


func _hud(c: CharacterState, ctx: GameContext = null) -> MisoHud:
	var h: MisoHud = load("res://scenes/ui/hud.tscn").instantiate()
	h.configure(MisoUiEnv.isolated(c, db(), bus, ctx))
	_parent().add_child(h)
	nodes.append(h)
	return h


func _has_line(h: MisoHud, text: String) -> bool:
	return text in h.log_panel.texts()


func _press(root: Node, action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	root._unhandled_input(ev)


# --- the Skills window ---------------------------------------------------------------------------------------------

func test_skills_window_opens_on_k_and_lists_the_canonical_skills() -> void:
	var c := _character()
	var root := _windows(c)
	_press(root, "toggle_skills")
	assert_true(root.is_open("skills"), "K opens the Skills window")
	var w: MisoSkillsWindow = root.window_by_name("skills")
	var ids: Array = []
	for def in SkillDef.catalog(c.job, db()):
		ids.append(def.id)
	assert_eq(w.rows.keys(), ids, "one row per canonical Beginner skill, in record order")
	for sid in ids:
		assert_eq(w.level_text(sid), "Lv. 0 / %d" % SkillDef.of(sid, db()).max_level, "%s: level / max" % sid)
		assert_false((w.plus_buttons[sid] as Button).visible, "%s: no '+' at 0 SP" % sid)
		assert_eq(((w.rows[sid]["name"]) as Label).text, SkillDef.of(sid, db()).name, "canonical name")
	assert_eq(w.sp_label.text, "0", "SP left")
	_press(root, "toggle_skills")
	assert_false(root.is_open("skills"), "K closes it")


func test_plus_spends_sp_and_announces_it() -> void:
	var c := _character()
	c.sp = 2
	var root := _windows(c)
	root.open_window("skills")
	var w: MisoSkillsWindow = root.skills
	for sid in w.rows:
		assert_true((w.plus_buttons[sid] as Button).visible, "%s: '+' while SP is left" % sid)
	(w.plus_buttons[NIMBLE] as Button).pressed.emit()
	assert_eq(SkillBook.level_of(c, NIMBLE), 1, "the '+' learned a level")
	assert_eq(c.sp, 1, "one SP spent")
	assert_eq(w.level_text(NIMBLE), "Lv. 1 / 3", "the row follows")
	assert_eq(w.sp_label.text, "1", "the SP box follows")
	assert_eq(int(seen.get("skill_leveled", 0)), 1, "Events.skill_leveled")
	assert_true(int(seen.get("stats_changed", 0)) >= 1, "Events.stats_changed (HUD badge, stat window)")
	assert_true(w.add_point(NIMBLE), "a second level")
	assert_eq(c.sp, 0, "no SP left")
	for sid in w.rows:
		assert_false((w.plus_buttons[sid] as Button).visible, "%s: '+' hidden at 0 SP" % sid)
	assert_false(w.add_point(SNAILS), "refused without SP")
	assert_eq(c.skills, {NIMBLE: 2}, "nothing else learned")
	c.sp = 5
	w.add_point(NIMBLE)
	w.refresh()
	assert_false((w.plus_buttons[NIMBLE] as Button).visible, "no '+' at the max level")
	assert_false(w.add_point(NIMBLE), "no 4th level")
	# The stat window shows the SP too.
	root.open_window("stats")
	assert_eq(root.stats.sp_label.text, str(c.sp), "Skill Points row in the stat window")


func test_set_key_and_drag_bind_a_learned_skill() -> void:
	var c := _character()
	c.sp = 1
	var root := _windows(c)
	root.open_window("skills")
	var w := root.skills
	w.select_skill(NIMBLE)
	assert_true(w.key_button.disabled, "an unlearned skill cannot be set to a key")
	assert_false(w.assign_quickslot("2"), "refused")
	var icon: MisoSkillsWindow.SkillIconCell = w.rows[NIMBLE]["icon"]
	assert_eq(icon._get_drag_data(Vector2.ZERO), null, "an unlearned skill does not drag")
	w.add_point(NIMBLE)
	assert_false(w.key_button.disabled, "learned: Set key")
	(w.key_buttons["2"] as Button).pressed.emit()
	assert_eq(c.quickslots.get("2"), {"kind": "skill", "id": NIMBLE}, "a typed skill binding (C3)")
	# Drag the icon onto a HUD quickslot.
	var h := _hud(c)
	var drag: Variant = icon._get_drag_data(Vector2.ZERO)
	assert_eq(drag, {"kind": MisoQuickslots.SKILL_DRAG_KIND, "source": "skills", "skill_id": NIMBLE}, "drag data")
	var slot: MisoItemSlot = h.status.quickslots.slots["5"]
	assert_true(slot.drop_filter.call(slot, drag), "a learned skill may drop on a quickslot")
	slot.drop_handler.call(slot, drag)
	assert_eq(MisoQuickslots.skill_for(c, "5"), NIMBLE, "dropped binding")
	assert_eq(h.status.quickslots.skill_on("5"), NIMBLE, "the HUD shows the skill")
	assert_eq(h.status.quickslots.count_text("5"), "", "no item count on a skill slot")
	# Move it between keys, then clear it.
	assert_true(MisoQuickslots.move(h.env, "5", "7"), "move")
	assert_eq(MisoQuickslots.skill_for(c, "7"), NIMBLE, "moved")
	assert_true(MisoQuickslots.unbind(h.env, "7"), "unbind")
	h.refresh_all()
	assert_eq(h.status.quickslots.skill_on("7"), "", "cleared")


func test_a_skill_quickslot_casts_and_shows_mp_and_cooldown() -> void:
	rig = MonsterTestRig.create(db(), 3)
	rig.floor(30.0)
	var p := rig.spawn_player(Vector3.ZERO, Vector3.RIGHT)
	var c := rig.character()
	c.skills = {NIMBLE: 1, SNAILS: 1}
	rig.run(5)
	var ctx := GameContext.new()
	ctx.player = p
	var h := _hud(c, ctx)
	assert_true(MisoQuickslots.bind_skill(h.env, "1", NIMBLE), "bind Nimble Feet")
	assert_true(MisoQuickslots.bind_skill(h.env, "2", SNAILS), "bind Three Snails")
	assert_false(MisoQuickslots.bind_skill(h.env, "3", RECOVERY), "an unlearned skill cannot be bound")
	h.refresh_all()
	var cell: MisoQuickslotBar.QuickslotCell = h.status.quickslots.slots["2"]
	assert_true(cell.skill_icon.dim, "Three Snails greyed: no Snail Shell")
	c.mp = 0
	h.refresh_all()
	var nf: MisoQuickslotBar.QuickslotCell = h.status.quickslots.slots["1"]
	assert_true(nf.skill_icon.dim, "greyed without the MP")
	assert_false(h.use_quickslot("1").get("ok", true), "refused")
	assert_true(_has_line(h, "Not enough MP for Nimble Feet."), "the refusal is announced")
	c.mp = StatCalculator.max_mp(c, db())
	h.refresh_all()
	assert_false(nf.skill_icon.dim, "usable")
	# The key path: quickslot_1 casts through the player's PlayerSkills.
	_press(h, "quickslot_1")
	assert_true(EffectBook.has(c, PlayerSkills.effect_id(NIMBLE)), "Nimble Feet is active")
	assert_true(EffectBook.cooldown_left(c, NIMBLE) > 0.0, "cooling down")
	h.status.quickslots.refresh_skills()
	assert_true(nf.skill_icon.cooldown > 0.99, "the sweep starts full")
	assert_eq(nf.skill_icon.cooldown_text, str(ceili(EffectBook.cooldown_left(c, NIMBLE))), "seconds left")
	var again := h.use_quickslot("1")
	assert_eq(String(again.get("code")), SkillBook.COOLDOWN, "not again while cooling down")
	assert_true(_has_line(h, "Nimble Feet is not ready yet (%d s)." % ceili(EffectBook.cooldown_left(c, NIMBLE))),
		"the cooldown is announced")
	EffectBook.tick(c, 90.0)
	h.status.quickslots.refresh_skills()
	assert_near(nf.skill_icon.cooldown, 0.5, 0.01, "half the cooldown left")


func test_quickslot_values_are_typed_and_read_legacy_ids() -> void:
	var c := _character()
	ItemService.new(c, db(), null).gain("270", 2)
	c.quickslots = {"1": "270", "2": 270.0, "3": {"kind": "skill", "id": NIMBLE}, "4": {"kind": "pet", "id": "x"}}
	assert_eq(MisoQuickslots.binding(c, "1"), {"kind": "item", "id": "270"}, "a bare id reads as an item")
	assert_eq(MisoQuickslots.item_for(c, "2"), "270", "a JSON number id too")
	assert_eq(MisoQuickslots.skill_for(c, "3"), NIMBLE, "a skill binding")
	assert_eq(MisoQuickslots.item_for(c, "3"), "", "a skill key holds no item")
	assert_eq(MisoQuickslots.binding(c, "4"), {}, "an unknown kind is empty")
	var h := _hud(c)
	assert_eq(h.status.quickslots.count_text("1"), "2", "the legacy binding shows its count")
	assert_true(MisoQuickslots.move(h.env, "1", "3"), "move an item onto the skill's key: swap")
	assert_eq(c.quickslots["3"], {"kind": "item", "id": "270"}, "rewritten typed")
	assert_eq(c.quickslots["1"], {"kind": "skill", "id": NIMBLE}, "the skill moved back")
	# A save's copy never shares a binding with the live state.
	var saved := c.to_dict()
	MisoQuickslots.move(h.env, "1", "3")
	assert_eq(saved["quickslots"]["3"], {"kind": "item", "id": "270"}, "the earlier copy is unchanged")
	# Through a real save file.
	c.quickslots = {"1": {"kind": "item", "id": "270"}, "2": {"kind": "skill", "id": NIMBLE}}
	var doc := SaveDocument.build(c, SaveDocument.world_from_character(c), "2026-10-05T00:00:00Z", db())
	var res := SaveDocument.decode(JSON.parse_string(JSON.stringify(doc)), SaveMigrations.new(), db())
	assert_true(res.ok(), "decodes")
	assert_eq(res.character.quickslots, c.quickslots, "typed bindings survive the save")


func test_a_chair_binds_and_asks_the_sitting_system() -> void:
	var c := _character()
	var chair := ""
	for id in db().ids("items"):
		if MisoQuickslots.is_chair(ItemDef.of(id, db())):
			chair = id
			break
	assert_eq(chair, "522", "The Green Relaxer is the chair (Setup with setup data)")
	assert_true(MisoQuickslots.can_bind(chair, db()), "a chair may be bound")
	assert_false(MisoQuickslots.can_bind("348", db()), "an Etc item may not")
	var h := _hud(c)
	assert_true(MisoQuickslots.bind(h.env, "6", chair), "bound")
	var empty := h.use_quickslot("6")
	assert_false(empty.get("ok", true), "no chair in the bag: refused")
	assert_eq(String(empty.get("code", "")), ItemCodes.NOT_ENOUGH_ITEMS, "refused by Chairs.use: none owned")
	ItemService.new(c, db(), null).gain(chair, 1)
	# This HUD rig has no live player, so the sitting system (Chairs.use through ItemService.use_item) answers that it
	# cannot seat anyone: the key reached the chair rules, not the consumable rules. test_chairs_use seats a live player.
	var res := h.use_quickslot("6")
	assert_eq(String(res.get("code", "")), ItemCodes.CANNOT_SIT, "routed to Chairs.use (C5): %s" % res)


# --- held skill keys (#20) -------------------------------------------------------------------------------------------

## A rig player with Three Snails Lv1 on key 1 (and `shells` Snail Shells) and a HUD casting through it.
func _held_rig(shells: int) -> MisoHud:
	rig = MonsterTestRig.create(db(), 3)
	rig.floor(30.0)
	var p := rig.spawn_player(Vector3.ZERO, Vector3.RIGHT)
	var c := rig.character()
	c.skills = {SNAILS: 1, NIMBLE: 1}
	c.base_max_mp = 500
	c.mp = 500
	ItemService.new(c, db(), null).gain("348", shells)
	rig.run(5)
	var ctx := GameContext.new()
	ctx.player = p
	var h := _hud(c, ctx)
	assert_true(MisoQuickslots.bind_skill(h.env, "1", SNAILS), "Three Snails on key 1")
	return h


## The key goes down (the Input state a held key leaves) and its press event reaches the HUD.
func _key_down(h: MisoHud, action: String) -> void:
	Input.action_press(action)
	_press(h, action)


## `ticks` physics ticks of the rig with the HUD's held-key poll after each; the tick of every cast is appended to
## `cast_ticks` (PlayerSkills.casts going up).
func _hold_for(h: MisoHud, ticks: int, cast_ticks: Array) -> void:
	var ps: PlayerSkills = rig.w.player.get_node(^"PlayerSkills")
	for i in ticks:
		rig.tick()
		var before := ps.casts
		h.poll_held_skills()
		if ps.casts > before:
			cast_ticks.append(i)


## Holding a skill key over N lockouts gives N casts, one as each lockout ends (no buffer beyond the hold); releasing
## the key stops them.
func test_a_held_skill_key_casts_again_each_time_the_lockout_ends() -> void:
	var h := _held_rig(20)
	var ps: PlayerSkills = rig.w.player.get_node(^"PlayerSkills")
	_key_down(h, "quickslot_1")
	assert_eq(ps.casts, 1, "the press casts")
	assert_eq(h.held_skill_keys(), {"1": SNAILS}, "and starts a hold")
	var lock := ps.last_lockout_s
	assert_true(lock > 0.5, "Three Snails locks out (%.3f s)" % lock)
	var lockouts := 4
	var cast_ticks: Array = []
	_hold_for(h, int(ceil(lockouts * lock / MonsterTestRig.TICK)) + 1, cast_ticks)
	assert_eq(ps.casts, 1 + lockouts, "%d lockouts held: %d more casts (ticks %s)" % [lockouts, lockouts, cast_ticks])
	for k in range(1, cast_ticks.size()):
		assert_near((cast_ticks[k] - cast_ticks[k - 1]) * MonsterTestRig.TICK, lock, MonsterTestRig.TICK * 1.01,
			"each cast follows the last by one lockout")
	Input.action_release("quickslot_1")
	var after: Array = []
	_hold_for(h, int(ceil(3.0 * lock / MonsterTestRig.TICK)), after)
	assert_eq(after, [], "released: no more casts")
	assert_eq(h.held_skill_keys(), {}, "the hold ended")


## A refusal (here: no MP) shows its notice once while the key stays held, though every tick tries again; a new press
## is a new hold and says it again. A held key waits out a cooldown silently and casts when it ends.
func test_a_held_skill_key_announces_a_refusal_once_per_hold() -> void:
	var h := _held_rig(5)
	var c := rig.character()
	var ps: PlayerSkills = rig.w.player.get_node(^"PlayerSkills")
	c.mp = 0
	var line := "Not enough MP for %s." % SkillDef.of(SNAILS, db()).name
	_key_down(h, "quickslot_1")
	_hold_for(h, 120, [])
	assert_eq(ps.casts, 0, "nothing cast without MP")
	assert_eq(h.log_panel.texts().count(line), 1, "the refusal is announced once in 2 s of holding")
	assert_eq(int(seen.get("notice", 0)), 1, "one notice on the bus")
	Input.action_release("quickslot_1")
	_hold_for(h, 2, [])
	_key_down(h, "quickslot_1")
	assert_eq(int(seen.get("notice", 0)), 2, "a new press, a new hold: announced again")
	Input.action_release("quickslot_1")
	_hold_for(h, 2, [])
	# Nimble Feet (no lockout, a 3 min cooldown): the press casts, the hold waits out the cooldown without a word.
	c.mp = 500
	assert_true(MisoQuickslots.bind_skill(h.env, "2", NIMBLE), "Nimble Feet on key 2")
	var notices := int(seen.get("notice", 0))
	_key_down(h, "quickslot_2")
	assert_eq(ps.casts, 1, "the press casts Nimble Feet")
	_hold_for(h, 60, [])
	assert_eq(ps.casts, 1, "the cooldown holds the next cast")
	assert_eq(int(seen.get("notice", 0)), notices, "and the hold announces nothing while it waits")
	EffectBook.tick(c, SkillDef.of(NIMBLE, db()).cooldown_s(1) + 1.0)
	_hold_for(h, 1, [])
	assert_eq(ps.casts, 2, "the cooldown over, the held key casts again")
	Input.action_release("quickslot_2")


## Consumable quickslots behave as before: one press, one use, however long the key is held.
func test_a_held_consumable_key_uses_its_item_once() -> void:
	var h := _held_rig(0)
	var c := rig.character()
	ItemService.new(c, db(), null).gain("270", 5)
	assert_true(MisoQuickslots.bind(h.env, "4", "270"), "Red Potion on key 4")
	c.hp = 1
	_key_down(h, "quickslot_4")
	assert_eq(c.inventory.count("270"), 4, "the press drinks one")
	assert_eq(h.held_skill_keys(), {}, "an item key starts no hold")
	c.hp = 1
	_hold_for(h, 120, [])
	assert_eq(c.inventory.count("270"), 4, "holding it drinks no more")
	Input.action_release("quickslot_4")


# --- layout ---------------------------------------------------------------------------------------------------------

func test_the_five_default_window_positions_do_not_overlap() -> void:
	var c := _character()
	ItemService.new(c, db(), null).gain("270", 3)
	c.skills = {NIMBLE: 1}
	var root := _windows(c)
	var area := root.get_viewport_rect().size
	for n in ["skills", "quests", "inventory", "stats", "equipment"]:
		root.open_window(n)
	root.skills.select_skill(NIMBLE)
	var rects := {}
	for n in ["stats", "quests", "skills", "equipment", "inventory"]:
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
