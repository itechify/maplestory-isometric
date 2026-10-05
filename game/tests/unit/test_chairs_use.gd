extends TestCase
## Chairs (contract C5): a chair is a Setup item with canonical setup data (The Green Relaxer, 522); using it through
## ItemService.use_item (the Set-up tab's double-click or Sit button, a quickslot) sits the player down, or stands it
## up when it already sits on it, and never consumes it. Refusals: not a chair, not owned, a level requirement, dead,
## and a player that cannot sit now. A fixture character's ItemService never moves the live player.

const RELAXER := "522"
const SKY_BLUE := "525"

var w: PlayerTestWorld = null
var bus: Node = null
var nodes: Array = []
var seen: Array = []
var _saved_character: CharacterState = null


func parity_keys() -> Dictionary:
	var chair := ["chair:522"]
	return {
		"test_chairs_are_setup_items_with_setup_data": chair + ["item:522"],
		"test_bonus_comes_from_the_canonical_setup_data": chair + ["mechanic:chair-hp-bonus"],
		"test_use_sits_and_stands_without_consuming_the_chair": chair + ["mechanic:sitting"],
		"test_inventory_window_sits_on_the_chair_from_the_setup_tab": chair + ["mechanic:sitting"],
		"test_quickslot_bound_chair_sits_the_live_player": chair,
	}


func before_each() -> void:
	w = PlayerTestWorld.create(db())
	w.add_box(Vector3(0, -0.5, 0), Vector3(100, 1, 100))
	bus = load("res://scripts/autoload/events.gd").new()
	seen = []
	for s in bus.get_signal_list():
		var sig := String(s["name"])
		var n := (s["args"] as Array).size()
		var cb := func() -> void: seen.append(sig)
		bus.connect(sig, cb.unbind(n) if n > 0 else cb)


func after_each() -> void:
	if _saved_character != null:
		Game.character = _saved_character
		_saved_character = null
	for n in nodes:
		if is_instance_valid(n):
			n.free()
	nodes.clear()
	w.free_all()
	bus.free()


func _player() -> PlayerController:
	var p := w.spawn_player(Vector3.ZERO)
	w.run(2)
	return p


func _owner(chairs: Array = [RELAXER]) -> CharacterState:
	var c := CharacterState.new()
	for id: String in chairs:
		c.inventory.add(id, 1, db())
	return c


func test_chairs_are_setup_items_with_setup_data() -> void:
	var chairs: PackedStringArray = []
	for id in db().ids("items"):
		var d := ItemDef.of(id, db())
		if Chairs.is_chair(d):
			chairs.append(id)
			assert_eq(d.tab, "setup", "%s is in the Set-up tab" % id)
			assert_true(d.setup_hp_bonus > 0, "%s has a setup bonus" % id)
	assert_true(RELAXER in chairs, "The Green Relaxer is a chair")
	assert_true(SKY_BLUE in chairs, "the Sky-blue Wooden Chair is a chair")
	for id in ["270", "541", "348", "269"]:
		assert_false(ItemDef.of(id, db()).is_chair(), "%s is not a chair" % id)
	assert_false(ItemDef.of(RELAXER, db()).is_consumable(), "a chair is not a consumable")


func test_bonus_comes_from_the_canonical_setup_data() -> void:
	var rec: Dictionary = db().item(RELAXER)["setup"]
	assert_eq(Chairs.bonus(RELAXER, db()), {"hp": int(rec["hp_recovery_bonus"]), "interval_s": float(rec["interval_s"])})
	assert_eq(Chairs.bonus("270", db()), {}, "not a chair")
	assert_eq(Chairs.bonus("", db()), {})


func test_first_owned_reads_the_setup_tab_in_slot_order() -> void:
	var c := CharacterState.new()
	assert_eq(Chairs.first_owned(c, db()), "", "no chair")
	c.inventory.add("270", 2, db())
	assert_eq(Chairs.first_owned(c, db()), "", "a potion is no chair")
	c.inventory.add(SKY_BLUE, 1, db())
	c.inventory.add(RELAXER, 1, db())
	assert_eq(Chairs.first_owned(c, db()), SKY_BLUE, "the first slot of the Set-up tab")
	c.inventory.move("setup", 0, 1, db())
	assert_eq(Chairs.first_owned(c, db()), RELAXER, "after a move, the new first slot")


func test_use_refusals_change_nothing() -> void:
	var p := _player()
	var c := _owner()
	assert_eq(Chairs.use(c, "nope", db(), p).code, ItemCodes.UNKNOWN_ITEM)
	c.inventory.add("270", 1, db())
	assert_eq(Chairs.use(c, "270", db(), p).code, ItemCodes.NOT_USABLE, "a potion is not a chair")
	assert_eq(Chairs.use(CharacterState.new(), RELAXER, db(), p).code, ItemCodes.NOT_ENOUGH_ITEMS, "not owned")
	var low := _owner([SKY_BLUE])
	var res := Chairs.use(low, SKY_BLUE, db(), p)
	assert_eq(res.code, ItemCodes.LEVEL_TOO_LOW, "the Sky-blue Wooden Chair needs level %d" % int(res.get("required", 0)))
	assert_eq(int(res.required), ItemDef.of(SKY_BLUE, db()).req_level, "the canonical level requirement")
	# A chair refused for its level is worded as sitting, never as equipping (the HUD log, the inventory window).
	assert_true(bool(res.get("chair", false)), "the refusal is marked as a chair's")
	assert_eq(MisoUiText.result_message(res, db()),
		"You need to be level %d to sit on that chair." % ItemDef.of(SKY_BLUE, db()).req_level)
	assert_eq(MisoUiText.result_message(res, null),
		"You need to be level %d to sit on that chair." % ItemDef.of(SKY_BLUE, db()).req_level, "without a db too")
	assert_eq(ItemCodes.message(res), "Your level is too low to sit on that chair.")
	var through_items := ItemService.new(low, db(), bus)
	through_items.seat = p
	var via := through_items.use_item(SKY_BLUE)
	assert_eq(via.code, ItemCodes.LEVEL_TOO_LOW, "the Set-up tab path refuses the same way")
	assert_false(MisoUiText.result_message(via, db()).contains("equip"), MisoUiText.result_message(via, db()))
	# Equipment keeps its own wording.
	var equip := ItemCodes.result(ItemCodes.LEVEL_TOO_LOW, {"item_id": "1040002", "required": 10})
	assert_eq(MisoUiText.result_message(equip, db()), "You need to be level 10 to equip that.")
	assert_eq(ItemCodes.message(equip), "Your level is too low to equip that.")
	assert_eq(Chairs.use(c, RELAXER, db(), p, func() -> bool: return true).code, ItemCodes.DEAD)
	w.bot.world_dir = Vector3.RIGHT
	w.run(5)
	res = Chairs.use(c, RELAXER, db(), p)
	assert_eq(res.code, ItemCodes.CANNOT_SIT, "walking")
	assert_eq(res.reason, "walking")
	assert_eq(ItemCodes.message(res), "You cannot sit down right now.")
	assert_false(p.is_seated())
	assert_eq(c.inventory.count(RELAXER), 1, "still owned")


func test_use_sits_and_stands_without_consuming_the_chair() -> void:
	var p := _player()
	var c := _owner()
	var items := ItemService.new(c, db(), bus)
	items.seat = p
	var res := items.use_item(RELAXER)
	assert_true(res.ok, str(res))
	assert_eq(res.action, "sit")
	assert_true(p.is_seated(), "seated")
	assert_eq(p.seated_chair_id(), RELAXER)
	assert_eq(c.inventory.count(RELAXER), 1, "the chair is not consumed")
	assert_eq(seen, [], "nothing left the bag: no item_used, item_lost or inventory_changed")
	res = items.use_item(RELAXER)
	assert_true(res.ok, str(res))
	assert_eq(res.action, "stand", "using it again stands up")
	assert_false(p.is_seated())


func test_using_another_chair_moves_over() -> void:
	var p := _player()
	var c := _owner([RELAXER, SKY_BLUE])
	c.level = ItemDef.of(SKY_BLUE, db()).req_level
	assert_true(Chairs.use(c, RELAXER, db(), p).ok)
	var res := Chairs.use(c, SKY_BLUE, db(), p)
	assert_true(res.ok, str(res))
	assert_eq(res.action, "sit")
	assert_eq(p.seated_chair_id(), SKY_BLUE, "now on the other chair")


func test_fixture_item_service_never_moves_the_live_player() -> void:
	var p := _player()
	p.add_to_group(Chairs.SEAT_GROUP)
	var res := ItemService.new(_owner(), db(), bus).use_item(RELAXER)
	assert_eq(res.code, ItemCodes.CANNOT_SIT, "not Game.character: no seat")
	assert_eq(res.reason, "no_player")
	assert_false(p.is_seated())


func test_quickslot_bound_chair_sits_the_live_player() -> void:
	var p := _player()
	p.add_to_group(Chairs.SEAT_GROUP)
	var c := _owner()
	_saved_character = Game.character
	Game.character = c  # the live character: Chairs.seat_for finds the player in SEAT_GROUP (the HUD's path)
	c.quickslots["1"] = RELAXER  # what a quickslot binding stores (binding chairs is the skills package's can_bind)
	var env := MisoUiEnv.isolated(c, db(), bus)
	var res := MisoQuickslots.use(env, "1")
	assert_true(res.ok, str(res))
	assert_true(p.is_seated(), "the bound chair sits the player down through ItemService.use_item")
	res = MisoQuickslots.use(env, "1")
	assert_false(p.is_seated(), "and stands it up again")


func test_inventory_window_sits_on_the_chair_from_the_setup_tab() -> void:
	var p := _player()
	var c := _owner()
	var ctx := GameContext.new()
	ctx.player = p
	var root: MisoWindowsRoot = load("res://scenes/ui/windows.tscn").instantiate()
	root.configure(MisoUiEnv.isolated(c, db(), bus, ctx))
	w.host.add_child(root)
	root.open_window("inventory")
	var inv := root.inventory
	inv.select_tab("setup")
	assert_eq(inv.visible_item_ids()[0], RELAXER, "the chair is in the Set-up tab")
	inv.select_slot(0)
	assert_false(inv.action_button.disabled, "a chair can be used")
	assert_eq(inv.action_button.text, "Sit")
	assert_eq(inv.key_button.disabled, not MisoQuickslots.can_bind(RELAXER, db()),
		"Set key follows MisoQuickslots.can_bind")
	inv.slots[0].activated.emit(inv.slots[0])  # the slot's double-click
	assert_true(p.is_seated(), "double-click sits")
	assert_true("sit" in inv.status_label.text.to_lower(), inv.status_label.text)
	assert_eq(inv.action_button.text, "Stand", "the button now stands up")
	var res := inv.activate_slot(0)
	assert_true(res.ok, str(res))
	assert_false(p.is_seated(), "Stand")
	assert_eq(inv.action_button.text, "Sit")
	assert_eq(c.inventory.count(RELAXER), 1, "still in the bag")
	# Refused while walking: reported in the window and as a notice.
	w.bot.world_dir = Vector3.RIGHT
	w.run(5)
	res = inv.activate_slot(0)
	assert_eq(String(res.code), ItemCodes.CANNOT_SIT)
	assert_true(seen.has("notice"), "Events.notice for the HUD log")
	assert_eq(inv.status_label.text, "You cannot sit down right now.")
