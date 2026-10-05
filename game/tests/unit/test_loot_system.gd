extends TestCase
## LootSystem end to end on a private Events bus and a real MapInstanceState: Events.loot_dropped puts DropRoller
## output on the ground (records in the map instance, nodes in the scene), the pickup key takes the nearest drop in the
## canonical pickup box into the inventory or the wallet with a notice, a full inventory leaves the drop, drops expire
## (blinking first), and the records survive leaving and re-entering a map (snapshot -> from_snapshot).

class FakePlayer:
	extends Node3D
	var input_source := BotInput.new()
	var input_on := true
	var climbing := false

	func is_input_enabled() -> bool:
		return input_on

	func is_climbing() -> bool:
		return climbing

	func is_dead() -> bool:
		return false

	func set_input_enabled(on: bool) -> void:
		input_on = on


var bus: Node
var character: CharacterState
var state: MapInstanceState
var now: float = 100.0
var loot: LootSystem
var notices: Array = []
var events: Array = []


func before_each() -> void:
	bus = load("res://scripts/autoload/events.gd").new()
	character = CharacterState.new()
	now = 100.0
	notices = []
	events = []
	state = _fresh_state("000000040")
	bus.connect("notice", func(t: String) -> void: notices.append(t))
	bus.connect("item_gained", func(i: String, q: int) -> void: events.append(["item_gained", i, q]))
	bus.connect("mesos_changed", func(m: int, d: int) -> void: events.append(["mesos_changed", m, d]))
	bus.connect("inventory_full", func(i: String) -> void: events.append(["inventory_full", i]))
	loot = _make_loot()


func after_each() -> void:
	if is_instance_valid(loot):
		loot.free()
	bus.free()


func _fresh_state(map_id: String) -> MapInstanceState:
	var r := RandomNumberGenerator.new()
	r.seed = 3
	var none: Array[float] = []
	return MapInstanceState.fresh_for(map_id, none, SpawnModel.from_db(db()), r, now)


func _make_loot() -> LootSystem:
	var l := LootSystem.new()
	l.db = db()
	l.bus = bus
	l.use_session = false
	l.read_input = false
	l.character_provider = func() -> CharacterState: return character
	l.clock_provider = func() -> float: return now
	l.state_provider = func() -> MapInstanceState: return state
	l.ground_axis_provider = func() -> Vector3: return Vector3(1, 0, 0)
	l.setup(null)
	return l


func _drop(drops: Array, at: Vector3 = Vector3(5, 1, 2)) -> Array:
	bus.emit_signal("loot_dropped", drops, at, "000000040")
	loot.tick(1.0)  # past the toss: the drops have landed
	return state.drops


## The node tests can add children to (the runner scene; root is busy while the runner's _ready runs).
func _parent() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.current_scene if tree.current_scene != null else tree.root


func _spacing() -> float:
	return WorldScale.h(DropRates.scatter_spacing_px(db()))


# --- spawning ------------------------------------------------------------------------------------------------------

func test_loot_dropped_puts_records_in_the_map_instance_and_nodes_in_the_scene() -> void:
	bus.emit_signal("loot_dropped", [{"kind": "mesos", "amount": 7}, {"kind": "item", "item_id": "348", "qty": 1},
		{"kind": "item", "item_id": "270", "qty": 2}], Vector3(5, 1, 2), "000000040")
	assert_eq(state.drops.size(), 3, "three records in MapInstanceState.drops")
	assert_eq(loot.nodes().size(), 3, "three GroundDrop nodes")
	var life := DropRates.ground_lifetime_s(db())
	var uids := {}
	for r: Dictionary in state.drops:
		assert_false(String(r.get("uid", "")).is_empty(), "uid")
		uids[r["uid"]] = true
		assert_near(float(r["expires_at"]), now + life, 1e-6, "expires_at = now + ground_lifetime_s")
		assert_eq(r["owner"], "player")
		assert_true(r.get("pos_local") is Array, "pos_local stored as plain data")
	assert_eq(uids.size(), 3, "unique uids")
	# Scatter: 0, +s, -s along the ground axis, at the kill height (no ground in the test world).
	var xs: Array = []
	for r: Dictionary in state.drops:
		xs.append(snappedf(LootPickupRules.local_pos(r).x, 0.001))
	xs.sort()
	var s := _spacing()
	assert_eq(xs, [snappedf(5.0 - s, 0.001), 5.0, snappedf(5.0 + s, 0.001)], "scatter spacing %.2f m" % s)
	for n: GroundDrop in loot.nodes().values():
		assert_false(n.is_landed(), "tossed out of the monster first")
	loot.tick(1.0)
	for n: GroundDrop in loot.nodes().values():
		assert_true(n.is_landed())


func test_loot_for_another_map_is_ignored() -> void:
	bus.emit_signal("loot_dropped", [{"kind": "mesos", "amount": 3}], Vector3.ZERO, "000000010")
	assert_eq(state.drops.size(), 0)
	assert_eq(loot.nodes().size(), 0)


func test_pos_local_uses_the_map_frame() -> void:
	var def := MapDefinition.new()
	def.map_id = "000000040"
	def.frame = Transform3D(Basis.IDENTITY, Vector3(100, 0, -20))
	loot.def_provider = func() -> MapDefinition: return def
	_drop([{"kind": "mesos", "amount": 3}], Vector3(103, 2, -18))
	assert_eq(LootPickupRules.local_pos(state.drops[0]), Vector3(3, 2, 2), "map-local")
	assert_eq((loot.nodes().values()[0] as GroundDrop).landing, Vector3(103, 2, -18), "world position of the node")


# --- pickup --------------------------------------------------------------------------------------------------------

func test_pickup_item_goes_into_the_inventory_with_a_notice() -> void:
	_drop([{"kind": "item", "item_id": "348", "qty": 1}])
	var feet := Vector3(5, 1, 2)
	var t := loot.pickup_target(feet)
	assert_eq(t.get("label"), "Snail Shell", "the prompt label")
	var r := loot.try_pickup(feet)
	assert_true(bool(r["ok"]), str(r))
	assert_eq(character.inventory.count("348"), 1)
	assert_eq(state.drops.size(), 0, "record removed from the map instance")
	assert_eq(loot.nodes().size(), 0, "node removed")
	assert_eq(notices, ["You have gained an item (Snail Shell)"])
	assert_has(events, ["item_gained", "348", 1])


func test_pickup_stack_notice_shows_the_quantity() -> void:
	_drop([{"kind": "item", "item_id": "270", "qty": 3}])
	loot.try_pickup(Vector3(5, 1, 2))
	assert_eq(character.inventory.count("270"), 3)
	assert_eq(notices, ["You have gained an item (Red Potion x3)"])


func test_pickup_mesos() -> void:
	_drop([{"kind": "mesos", "amount": 7}])
	var r := loot.try_pickup(Vector3(5, 1, 2))
	assert_true(bool(r["ok"]))
	assert_eq(character.mesos, 7)
	assert_eq(notices, ["You have gained mesos (+7)"])
	assert_has(events, ["mesos_changed", 7, 7])


func test_inventory_full_leaves_the_drop_and_says_so() -> void:
	for k in 4000:
		if character.inventory.add("350", 100, db()) < 100:
			break
	assert_eq(character.inventory.room_for("348", db()), 0, "Etc tab full")
	_drop([{"kind": "item", "item_id": "348", "qty": 1}])
	var r := loot.try_pickup(Vector3(5, 1, 2))
	assert_false(bool(r["ok"]))
	assert_eq(r["code"], ItemCodes.INVENTORY_FULL)
	assert_eq(state.drops.size(), 1, "the drop stays on the ground")
	assert_eq(loot.nodes().size(), 1)
	assert_eq(character.inventory.count("348"), 0)
	assert_eq(notices, ["Your inventory is full."], "the ItemCodes sentence, the same line the HUD logs on inventory_full")
	assert_has(events, ["inventory_full", "348"])
	# Making room lets the same drop be taken.
	character.inventory.remove_at("etc", 0)
	assert_true(bool(loot.try_pickup(Vector3(5, 1, 2))["ok"]))


## Regression: holding Z next to a drop the full inventory refuses retried it every hold_repeat_s, and each try
## logged two different lines (the HUD's inventory_full line and this system's notice): ~10 log lines a second.
func test_holding_the_pickup_key_with_a_full_inventory_announces_once_and_still_takes_mesos() -> void:
	for k in 4000:
		if character.inventory.add("350", 100, db()) < 100:
			break
	var p := FakePlayer.new()
	_parent().add_child(p)
	loot.player = p
	loot.read_input = true
	_drop([{"kind": "item", "item_id": "348", "qty": 1}, {"kind": "mesos", "amount": 6}], Vector3(5, 1, 2))
	# Nearer the Snail Shell (lands at the kill point) than the meso bag (+s), both in the box.
	p.position = Vector3(5 + _spacing() * 0.3, 1, 2)
	var bot := p.input_source as BotInput
	bot.hold(&"pickup")
	var ticks := int(ceil(LootVisuals.new(db()).num("pickup", "hold_repeat_s") * 60.0)) * 6 + 2
	for i in ticks:
		bot.begin_tick()
		loot._physics_process(1.0 / 60.0)
	assert_eq(notices.count("Your inventory is full."), 1, "one refusal per press: %s" % str(notices))
	assert_eq(_count(events, "inventory_full"), 1, "the refused drop is not retried while Z is held")
	assert_eq(character.mesos, 6, "the hold still takes the meso bag next to it")
	assert_eq(state.drops.size(), 1, "the refused drop stays")
	# A fresh press tries (and explains) it again.
	bot.release(&"pickup")
	bot.begin_tick()
	loot._physics_process(1.0 / 60.0)
	bot.press(&"pickup")
	bot.begin_tick()
	loot._physics_process(1.0 / 60.0)
	assert_eq(notices.count("Your inventory is full."), 2, "a new press explains again")
	p.free()


## The pickup notices are word for word the HUD's own item_gained / mesos_changed lines, so the HUD log (which drops a
## line repeating the previous one) shows a pickup once; large meso amounts use the HUD's thousands separators.
func test_pickup_notices_match_the_hud_lines() -> void:
	_drop([{"kind": "mesos", "amount": 1500}])
	loot.try_pickup(Vector3(5, 1, 2))
	assert_eq(notices, [MisoUiText.mesos_gained_line(1500)])
	assert_eq(notices[0], "You have gained mesos (+1,500)")
	notices.clear()
	_drop([{"kind": "item", "item_id": "270", "qty": 3}])
	loot.try_pickup(Vector3(5, 1, 2))
	assert_eq(notices, [MisoUiText.item_gained_line("Red Potion", 3)])
	_drop([{"kind": "mesos", "amount": 2500}])
	assert_eq(String(loot.pickup_target(Vector3(5, 1, 2)).get("label")), "2,500 mesos")


func _count(list: Array, sname: String) -> int:
	var n := 0
	for e: Array in list:
		if e[0] == sname:
			n += 1
	return n


func test_pickup_box_is_the_canonical_box_through_world_scale() -> void:
	var box := DropRates.pickup_box_m(db())
	var px := DropRates.pickup_box_px(db())
	assert_near(float(box["left"]), WorldScale.actor(float(px["left"])), 1e-6)
	var r := maxf(float(box["left"]), float(box["right"]))
	var feet := Vector3(0, 0, 0)
	assert_true(LootPickupRules.in_pickup_box(feet, Vector3(r * 0.99, 0, 0), box), "inside the radius")
	assert_true(LootPickupRules.in_pickup_box(feet, Vector3(0, 0, r * 0.99), box), "the depth axis uses the same radius")
	assert_false(LootPickupRules.in_pickup_box(feet, Vector3(r * 1.01, 0, 0), box), "outside")
	assert_true(LootPickupRules.in_pickup_box(feet, Vector3(0, float(box["above"]) * 0.99, 0), box), "above")
	assert_false(LootPickupRules.in_pickup_box(feet, Vector3(0, float(box["above"]) * 1.01, 0), box))
	assert_true(LootPickupRules.in_pickup_box(feet, Vector3(0, -float(box["below"]) * 0.99, 0), box), "below")
	assert_false(LootPickupRules.in_pickup_box(feet, Vector3(0, -float(box["below"]) * 1.01, 0), box))
	# Through the system: a drop just outside the box is not taken.
	_drop([{"kind": "mesos", "amount": 2}], Vector3(0, 0, 0))
	assert_eq(loot.try_pickup(Vector3(r * 1.05, 0, 0))["code"], "nothing")
	assert_true(bool(loot.try_pickup(Vector3(r * 0.9, 0, 0))["ok"]))


func test_the_nearest_drop_in_the_box_is_taken_first() -> void:
	_drop([{"kind": "item", "item_id": "348", "qty": 1}, {"kind": "mesos", "amount": 4}], Vector3(0, 0, 0))
	# Record 0 lands at 0, record 1 at +s. Standing just right of +s/2 the meso bag is nearer.
	var s := _spacing()
	var feet := Vector3(s * 0.6, 0, 0)
	assert_eq(String(loot.pickup_target(feet).get("label")), "4 mesos")
	loot.try_pickup(feet)
	assert_eq(character.mesos, 4)
	assert_eq(String(loot.pickup_target(Vector3(0, 0, 0)).get("label")), "Snail Shell")


func test_owner_window_applies() -> void:
	_drop([{"kind": "mesos", "amount": 4}])
	loot.owner_name = "someone_else"
	assert_true(loot.pickup_target(Vector3(5, 1, 2)).is_empty(), "the killer's for owner_exclusive_s")
	now += DropRates.owner_exclusive_s(db()) + 0.1
	assert_false(loot.pickup_target(Vector3(5, 1, 2)).is_empty(), "free for all afterwards")


func test_pickup_key_through_the_players_input_source() -> void:
	var p := FakePlayer.new()
	_parent().add_child(p)
	p.position = Vector3(5, 1, 2)
	loot.player = p
	loot.read_input = true
	_drop([{"kind": "mesos", "amount": 9}])
	(p.input_source as BotInput).press(&"pickup")
	(p.input_source as BotInput).begin_tick()
	loot._physics_process(1.0 / 60.0)
	assert_eq(character.mesos, 9, "Z picked it up")
	_drop([{"kind": "mesos", "amount": 1}])
	p.input_on = false
	(p.input_source as BotInput).press(&"pickup")
	(p.input_source as BotInput).begin_tick()
	loot._physics_process(1.0 / 60.0)
	assert_eq(character.mesos, 9, "no pickup while the player's input is off (a modal is open)")
	p.input_on = true
	p.climbing = true
	(p.input_source as BotInput).begin_tick()  # the key goes up
	loot._physics_process(1.0 / 60.0)
	(p.input_source as BotInput).press(&"pickup")
	(p.input_source as BotInput).begin_tick()
	loot._physics_process(1.0 / 60.0)
	assert_eq(character.mesos, 9, "no pickup on a ladder, where the prompt is silent")
	p.climbing = false
	(p.input_source as BotInput).begin_tick()  # the key goes up
	loot._physics_process(1.0 / 60.0)
	(p.input_source as BotInput).press(&"pickup")
	(p.input_source as BotInput).begin_tick()
	loot._physics_process(1.0 / 60.0)
	assert_eq(character.mesos, 10, "off the ladder Z takes it")
	p.free()


func test_holding_the_pickup_key_repeats() -> void:
	var p := FakePlayer.new()
	_parent().add_child(p)
	p.position = Vector3(5, 1, 2)
	loot.player = p
	loot.read_input = true
	_drop([{"kind": "mesos", "amount": 1}, {"kind": "mesos", "amount": 2}], Vector3(5, 1, 2))
	var bot := p.input_source as BotInput
	bot.hold(&"pickup")
	var repeat := LootVisuals.new(db()).num("pickup", "hold_repeat_s")
	var ticks := int(ceil(repeat * 60.0)) + 2
	# The scatter puts the second bag s away; stand between them so both are in the box.
	p.position = Vector3(5 + _spacing() * 0.5, 1, 2)
	for i in ticks:
		bot.begin_tick()
		loot._physics_process(1.0 / 60.0)
	assert_eq(character.mesos, 3, "a press, then one more after hold_repeat_s")
	p.free()


# --- expiry --------------------------------------------------------------------------------------------------------

func test_drops_blink_then_expire() -> void:
	_drop([{"kind": "item", "item_id": "348", "qty": 1}])
	var expired: Array = []
	loot.drop_expired.connect(func(uid: String) -> void: expired.append(uid))
	var life := DropRates.ground_lifetime_s(db())
	var window := LootVisuals.new(db()).motion("blink_before_expiry_s")
	var n: GroundDrop = loot.nodes().values()[0]
	now += life - window - 1.0
	loot.tick(0.016)
	assert_true(n.model.visible, "steady until the blink window")
	now = 100.0 + life - window * 0.5
	var off := 0
	for i in 32:
		now += 0.05
		loot.tick(0.05)
		if n.is_blinking_off():
			off += 1
	assert_true(off > 4, "blinks in the last %.0f s" % window)
	now = 100.0 + life + 0.01
	loot.tick(0.016)
	assert_eq(state.drops.size(), 0, "record expired")
	assert_eq(loot.nodes().size(), 0, "node gone")
	assert_eq(expired.size(), 1)


func test_records_the_map_instance_expires_on_its_own_tick_lose_their_node() -> void:
	_drop([{"kind": "mesos", "amount": 4}])
	state.tick(now + DropRates.ground_lifetime_s(db()) + 1.0)  # MapInstanceView ticks the state independently
	assert_eq(state.drops.size(), 0)
	loot.tick(0.016)
	assert_eq(loot.nodes().size(), 0, "nodes follow the records")


# --- persistence (MAP_ARCHITECTURE 4.7.7) ------------------------------------------------------------------------

func test_leaving_and_returning_keeps_drops_with_their_remaining_lifetime() -> void:
	_drop([{"kind": "item", "item_id": "348", "qty": 1}, {"kind": "mesos", "amount": 6}], Vector3(5, 1, 2))
	var before: Array = state.drops.duplicate(true)
	# Leave: MapSession emits map_left, then snapshots the instance into MapStateCache.
	bus.emit_signal("map_left", "000000040")
	assert_eq(loot.nodes().size(), 0, "nodes go with the map")
	var snap := state.snapshot(now + 10.0)
	state = _fresh_state("000000010")
	loot.tick(0.016)
	assert_eq(loot.nodes().size(), 0, "nothing on the other map")
	# Return 40 s later: the cache restores (fast-forwards) the instance.
	now += 40.0
	state = MapInstanceState.from_snapshot(snap, SpawnModel.from_db(db()), now)
	bus.emit_signal("map_entered", "000000040", "000000010")
	assert_eq(state.drops.size(), 2, "records survive the snapshot")
	assert_eq(loot.nodes().size(), 2, "nodes rebuilt")
	for i in 2:
		assert_eq(state.drops[i]["uid"], before[i]["uid"])
		assert_eq(state.drops[i]["expires_at"], before[i]["expires_at"], "same expiry: lifetime keeps counting")
		assert_near(LootPickupRules.time_left(state.drops[i], now), DropRates.ground_lifetime_s(db()) - 40.0, 1e-6)
	for n: GroundDrop in loot.nodes().values():
		assert_true(n.is_landed(), "restored drops rest at once (no toss)")
	assert_true(bool(loot.try_pickup(Vector3(5, 1, 2))["ok"]), "and can be picked up")


func test_drops_past_their_lifetime_are_gone_after_a_long_absence() -> void:
	_drop([{"kind": "mesos", "amount": 6}])
	var snap := state.snapshot(now)
	now += DropRates.ground_lifetime_s(db()) + 5.0
	state = MapInstanceState.from_snapshot(snap, SpawnModel.from_db(db()), now)
	loot.tick(0.016)
	assert_eq(state.drops.size(), 0)
	assert_eq(loot.nodes().size(), 0)


func test_a_new_state_object_rebuilds_nodes_even_without_signals() -> void:
	_drop([{"kind": "mesos", "amount": 6}])
	var snap := state.snapshot(now)
	state = MapInstanceState.from_snapshot(snap, SpawnModel.from_db(db()), now)
	loot.tick(0.016)
	assert_eq(loot.nodes().size(), 1)
	assert_eq(String(loot.nodes().keys()[0]), String(state.drops[0]["uid"]))


func test_rolled_kills_are_picked_up_exactly() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var expected_mesos := 0
	var expected_items := {}
	var spawned := 0
	for k in 20:
		var drops := DropRoller.roll("2", db(), rng)
		spawned += drops.size()
		for d: Dictionary in drops:
			if d["kind"] == "mesos":
				expected_mesos += int(d["amount"])
			else:
				expected_items[d["item_id"]] = int(expected_items.get(d["item_id"], 0)) + int(d["qty"])
		_drop(drops, Vector3(0, 0, 0))
		var guard := 0
		while not state.drops.is_empty() and guard < 50:
			var p := LootPickupRules.local_pos(state.drops[0])
			loot.try_pickup(p)
			guard += 1
	assert_eq(character.mesos, expected_mesos, "every meso bag")
	for id: String in expected_items:
		assert_eq(character.inventory.count(id), expected_items[id], "item %s" % id)
	assert_true(spawned > 5, "20 Snail kills drop something")
	assert_eq(notices.size(), spawned, "one notice per pickup")


## The console's "loot <owner> [kills]" rolls with the character's quests as the C2 context: the Wooden Box's Old
## Wooden Board (441) and Rusty Screw (442), gated to Pio's quest 1012, never drop without it and drop on every roll
## (Chance value 1) while 1012 is in progress.
func test_the_loot_command_follows_the_characters_quests() -> void:
	var out := loot._cmd_loot(PackedStringArray(["0000001", "40"]))
	assert_true(out.ends_with("drops on the ground"), out)
	var before := _item_counts(state.drops)
	assert_false(before.has("441") or before.has("442"), "no gated drop without 1012: %s" % str(before))
	character.quests.start("1012", 0.0)
	state.drops.clear()
	loot._cmd_loot(PackedStringArray(["0000001", "40"]))
	var during := _item_counts(state.drops)
	assert_eq(int(during.get("441", 0)), 40, "Old Wooden Board on every roll while 1012 is in progress")
	assert_eq(int(during.get("442", 0)), 40, "Rusty Screw on every roll while 1012 is in progress")
	assert_eq(loot._cmd_loot(PackedStringArray()), "usage: loot <owner_id> [kills]")


func _item_counts(records: Array) -> Dictionary:
	var out := {}
	for rec: Dictionary in records:
		if String(rec.get("kind", "")) == "item":
			var id := String(rec.get("item_id", ""))
			out[id] = int(out.get(id, 0)) + int(rec.get("amount", 1))
	return out
