extends TestCase
## The player-attack feel values live in data/misostory/combat.json section "player_attack" (root_on_ground,
## input_buffer_s, basic_attack_targets, lunge_m, lunge_s), each with a reason and verified: false. PlayerCombat reads
## them; a missing or malformed value is an error and leaves that feature off, never a number hidden in code.

const KEYS := ["root_on_ground", "input_buffer_s", "basic_attack_targets", "lunge_m", "lunge_s"]


func _section() -> Dictionary:
	return db().miso_table("combat")["player_attack"]


## A ContentDB whose combat.json player_attack is replaced by `section` (null = no section).
func _db_with(section: Variant) -> ContentDB:
	var c := ContentDB.new()
	c.canonical = db().canonical
	c.miso = db().miso.duplicate()
	var singles: Dictionary = (db().miso[""] as Dictionary).duplicate()
	var combat: Dictionary = (singles["combat"] as Dictionary).duplicate()
	if section == null:
		combat.erase("player_attack")
	else:
		combat["player_attack"] = section
	singles["combat"] = combat
	c.miso[""] = singles
	c.loaded = true
	return c


func test_the_section_holds_every_value_with_a_reason_and_unverified() -> void:
	var s := _section()
	for k in KEYS:
		assert_true(s.has(k), "player_attack.%s" % k)
		var reason := String(s.get(k + "_reason", s.get(String(k).get_slice("_", 0) + "_reason", "")))
		assert_true(reason.length() > 40, "player_attack.%s has its own reason" % k)
	assert_true(String(s.get("reason", "")).length() > 40, "a section reason")
	assert_eq(s.get("verified"), false, "verified: false")


func test_player_combat_reads_the_section() -> void:
	var rig := MonsterTestRig.create(db(), 3)
	rig.floor(10.0)
	rig.spawn_player(Vector3.ZERO, Vector3.RIGHT)
	var pc := rig.system.player_combat
	var s := _section()
	assert_eq(pc.errors.size(), 0, "no load errors: %s" % "; ".join(pc.errors))
	assert_eq(pc.root_on_ground, bool(s["root_on_ground"]), "root_on_ground")
	assert_near(pc.input_buffer_s, float(s["input_buffer_s"]), 1e-9, "input_buffer_s")
	assert_eq(pc.basic_attack_targets, int(s["basic_attack_targets"]), "basic_attack_targets")
	assert_near(pc.lunge_m, float(s["lunge_m"]), 1e-9, "lunge_m")
	assert_near(pc.lunge_s, float(s["lunge_s"]), 1e-9, "lunge_s")
	rig.free_all()


func test_other_values_in_the_data_change_the_attack() -> void:
	var s := _section().duplicate()
	s["root_on_ground"] = false
	s["input_buffer_s"] = 0.3
	s["basic_attack_targets"] = 3
	var pc := PlayerCombat.new()
	assert_eq(pc.load_feel(_db_with(s)).size(), 0, "a valid edited section loads")
	assert_false(pc.root_on_ground, "root off")
	assert_near(pc.input_buffer_s, 0.3, 1e-9, "buffer from data")
	assert_eq(pc.basic_attack_targets, 3, "targets from data")
	pc.free()
	# With the root off a ground attack no longer plants the player.
	var rig := MonsterTestRig.create(db(), 3)
	rig.floor(20.0)
	var p := rig.spawn_player(Vector3.ZERO, Vector3.RIGHT)
	var live := rig.system.player_combat
	live.load_feel(_db_with(s))
	rig.w.bot.world_dir = Vector3.RIGHT
	rig.run(20)
	rig.w.bot.press(&"attack")
	rig.tick()
	var x0 := p.global_position.x
	rig.run(10)
	assert_true(p.global_position.x > x0 + 0.1, "walks during the attack when root_on_ground is false")
	rig.free_all()


## An attack tap whose key is already up again at the tick (pressed and released between two ticks): just pressed,
## never held. KeyboardInput reads a sub-tick J tap this way, and MouseAttackGate a sub-tick click on the world.
class SubTickTap extends InputSource:
	var tap := false

	func just_pressed(action: StringName) -> bool:
		return action == &"attack" and tap

	func is_held(_action: StringName) -> bool:
		return false


func test_with_no_input_buffer_a_press_still_attacks_at_once() -> void:
	# input_buffer_s 0 (also what a missing or malformed value leaves) means "nothing is remembered during the
	# lockout", not "a press that is not also held never attacks".
	var s := _section().duplicate()
	s["input_buffer_s"] = 0.0
	var rig := MonsterTestRig.create(db(), 3)
	rig.floor(20.0)
	var p := rig.spawn_player(Vector3.ZERO, Vector3.RIGHT)
	var pc := rig.system.player_combat
	assert_eq(pc.load_feel(_db_with(s)).size(), 0, "a zero buffer is valid data")
	var src := SubTickTap.new()
	p.set_input_source(src)
	rig.tick()
	var before := pc.attacks
	src.tap = true
	rig.tick()
	src.tap = false
	assert_eq(pc.attacks, before + 1, "a tap shorter than a tick attacks without a buffer")
	rig.run(5)
	src.tap = true
	rig.tick()
	src.tap = false
	rig.run(int(ceil(pc.last_lockout_s / MonsterTestRig.TICK)) + 2)
	assert_eq(pc.attacks, before + 1, "without a buffer a press during the lockout is not kept")
	# The same tap with the shipped buffer: kept when it comes within input_buffer_s of the lockout's end.
	pc.load_feel(db())
	assert_true(pc.input_buffer_s > 0.0, "the shipped buffer")
	src.tap = true
	rig.tick()
	src.tap = false
	var first := pc.attacks
	var early := int(floor(pc.input_buffer_s / MonsterTestRig.TICK)) - 1
	rig.run(int(ceil(pc.last_lockout_s / MonsterTestRig.TICK)) - early)
	src.tap = true
	rig.tick()
	src.tap = false
	rig.run(early + 2)
	assert_eq(pc.attacks, first + 1, "a tap inside the buffer fires when the lockout ends")
	rig.free_all()


func test_a_missing_or_malformed_section_is_an_error_and_turns_the_features_off() -> void:
	var pc := PlayerCombat.new()
	var errs := pc.load_feel(_db_with(null))
	assert_eq(errs.size(), 1, "one error for the missing section")
	assert_true(errs.size() == 1 and errs[0].contains("player_attack") and errs[0].contains("missing"), "names the section")
	assert_false(pc.root_on_ground, "no root")
	assert_eq(pc.input_buffer_s, 0.0, "no buffer")
	assert_eq(pc.basic_attack_targets, 1, "one target")
	assert_eq(pc.lunge_m, 0.0, "no lunge")
	var bad := {"root_on_ground": "yes", "input_buffer_s": -1, "basic_attack_targets": 1.5, "lunge_m": 0.1,
		"reason": "test", "verified": false}
	errs = pc.load_feel(_db_with(bad))
	var text := "; ".join(errs)
	for k in ["root_on_ground", "input_buffer_s", "basic_attack_targets", "lunge_s"]:
		assert_true(text.contains(k), "%s reported: %s" % [k, text])
	assert_false(text.contains("lunge_m"), "a valid value is not reported")
	assert_near(pc.lunge_m, 0.1, 1e-9, "a valid value still loads")
	assert_eq(pc.input_buffer_s, 0.0, "an invalid value stays off")
	pc.free()
