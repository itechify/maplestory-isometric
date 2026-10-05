extends TestCase
## The HUD (res://scenes/ui/hud.tscn, MisoHud): values follow Events, the message log, the map banner and the trail
## line, the level-up flourish, the HP gauge while dead, and quickslots (bind, use through ItemService, decrement,
## persistence in CharacterState.quickslots).
## Every test runs on a private events.gd bus and an injected character (and, for the trail line, a private
## map_session.gd instance): no autoload state is read or changed.

## Stands in for the Game autoload: character_replaced and is_character_dead() (MisoUiEnv reads only those here).
class FakeGame extends Node:
	signal character_replaced(reason: String)
	var dead: bool = false

	func is_character_dead() -> bool:
		return dead


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
	# The SP of the level-up (canonical: 1 per level-up at levels 2-10) on the Skill button and in the log.
	assert_eq(c.sp, int(db().formula("beginner")["sp"]["sp_per_level"]), "one SP at level 2")
	assert_eq(h.status.sp_available, c.sp, "SP shown while unspent")
	var skill_button: Button = h.status.menu_buttons["skills"]
	assert_eq(String(skill_button.theme_type_variation), "MisoAccentButton", "Skill button highlighted")
	assert_true(("+%d" % c.sp) in skill_button.text, "SP on the Skill button: " + skill_button.text)
	assert_true(_has_line(h, "You have %d SP to spend (press K)." % c.sp), "SP line")
	c.sp = 0
	bus.emit_signal("stats_changed")
	assert_eq(h.status.sp_available, 0, "spent: no badge")
	assert_eq(String(skill_button.theme_type_variation), "", "Skill button plain again")
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
	assert_false(h.banner.trail_label.visible, "no trail line on an arrival")


## A private MapSession (the real script, not in the tree) standing on `map_id`.
func _session(map_id: String) -> Node:
	var ms: Node = load("res://scripts/autoload/map_session.gd").new()
	ms.current_map = map_id
	nodes.append(ms)
	return ms


func _hud_on(c: CharacterState, ms: Node) -> MisoHud:
	var h: MisoHud = load("res://scenes/ui/hud.tscn").instantiate()
	var e := MisoUiEnv.isolated(c, db(), bus)
	e.map_session = ms
	h.configure(e)
	_parent().add_child(h)
	nodes.append(h)
	return h


func _map_name(map_id: String) -> String:
	return String(db().map(map_id).get("name"))


func test_trail_line_shows_the_destination_while_on_a_trail() -> void:
	var here := "000000040"
	var there := "000000041"
	var link := "T_000000040_east00__000000041_west00"
	var ms := _session(here)
	var h := _hud_on(_character(), ms)
	assert_false(h.banner.is_showing(), "off trails: no banner")
	ms.set_trail(link, there)
	assert_true(h.banner.is_trail_showing(), "on the trail: the line shows")
	assert_eq(h.banner.trail_label.text, "-> " + _map_name(there), "the destination's canonical name")
	assert_true(h.banner.trail_label.visible, "the line is visible")
	assert_eq(h.banner.name_label.text, _map_name(here), "under the current map's canonical name")
	assert_eq(h.banner.street_label.text, String(db().map(here).get("street_name")), "and its street")
	h.banner.advance(MisoMapBanner.FADE_IN_S + MisoMapBanner.HOLD_S + MisoMapBanner.FADE_OUT_S + 30.0)
	assert_true(h.banner.is_trail_showing(), "held for as long as the player is on the trail")
	assert_near(h.banner.modulate.a, 1.0, 1e-6, "fully visible")
	# RegionMonitor reports the same trail ten times a second; MapSession emits only changes, and a refresh re-syncs
	# without restarting the fade.
	bus.emit_signal("stats_changed")
	assert_near(h.banner.modulate.a, 1.0, 1e-6, "a refresh does not restart the banner")

	ms.set_trail("", "")
	assert_false(h.banner.trail_label.visible, "off the trail: the line goes")
	assert_eq(h.banner.trail_map_id, "", "cleared")
	h.banner.advance(MisoMapBanner.FADE_OUT_S * 0.5)
	assert_between(h.banner.modulate.a, 0.01, 0.99, "the banner fades out")
	# Back on the trail mid-fade: the line returns and the banner fades back in from where it was.
	var a := h.banner.modulate.a
	ms.set_trail(link, there)
	assert_true(h.banner.is_trail_showing(), "back on the trail")
	h.banner.advance(0.01)
	assert_true(h.banner.modulate.a > a, "fading back in, not restarting from 0")
	ms.set_trail("", "")
	h.banner.advance(MisoMapBanner.FADE_IN_S + MisoMapBanner.HOLD_S + MisoMapBanner.FADE_OUT_S)
	assert_false(h.banner.is_showing(), "gone once faded")


func test_trail_line_clears_on_a_gate_commit_and_follows_the_map_session() -> void:
	var ms := _session("000000040")
	ms.set_trail("T_000000040_east00__000000041_west00", "000000041")
	var h := _hud_on(_character(), ms)
	assert_true(h.banner.is_trail_showing(), "a HUD set up on a trail shows the line at once")
	assert_eq(h.banner.trail_label.text, "-> " + _map_name("000000041"), "from MapSession.trail_destination")
	# A gate commit, in MapSession's order: the trail line cleared, then map_entered for the new map.
	ms.set_trail("", "")
	ms.current_map = "000000041"
	bus.emit_signal("map_entered", "000000041", "000000040")
	assert_true(h.banner.is_showing(), "the arrival banner")
	assert_eq(h.banner.name_label.text, _map_name("000000041"), "names the new map")
	assert_false(h.banner.trail_label.visible, "with no trail line")
	# Turning back onto the trail just walked: it now leads back to the map left.
	ms.set_trail("T_000000040_east00__000000041_west00", "000000040")
	assert_eq(h.banner.name_label.text, _map_name("000000041"), "the current map")
	assert_eq(h.banner.trail_label.text, "-> " + _map_name("000000040"), "the way back")
	# An unknown destination shows its id; leaving and re-entering the tree keeps listening.
	var p := h.get_parent()
	p.remove_child(h)
	ms.set_trail("T_x", "999999999")
	p.add_child(h)
	assert_eq(h.banner.trail_label.text, "-> 999999999", "re-entering the tree re-syncs; unknown ids show the id")
	ms.set_trail("T_000000040_east00__000000041_west00", "000000040")
	assert_eq(h.banner.trail_label.text, "-> " + _map_name("000000040"), "still listening after re-entering")
	ms.reset()
	assert_false(h.banner.trail_label.visible, "a session reset clears it")


## The trail line can hold the banner for minutes, so it must follow a screen resize: with stretch aspect "expand" a
## window wider than 16:9 widens the HUD, and a banner centred for the old width sits off to one side.
func test_a_held_banner_stays_centred_when_the_screen_resizes() -> void:
	var ms := _session("000000040")
	var h := _hud_on(_character(), ms)
	# The HUD's size stands in for the viewport's (top-left anchors, so setting it is not overridden by the layout).
	h.set_anchors_preset(Control.PRESET_TOP_LEFT)
	h.size = Vector2(1600, 900)
	ms.set_trail("T_000000040_east00__000000041_west00", "000000041")
	h.banner.advance(MisoMapBanner.FADE_IN_S + MisoMapBanner.HOLD_S + 30.0)
	assert_true(h.banner.is_trail_showing(), "held on the trail")
	for w: float in [2400.0, 1280.0, 1600.0]:
		h.size = Vector2(w, 900)
		var centre := h.banner.position.x + h.banner.get_combined_minimum_size().x * 0.5
		assert_near(centre, w * 0.5, 1.0, "centred on a %d px wide HUD" % int(w))
	# Off the trail and faded out, then a resize: nothing to centre, and the next banner is centred for the new width.
	ms.set_trail("", "")
	h.banner.advance(MisoMapBanner.FADE_IN_S + MisoMapBanner.HOLD_S + MisoMapBanner.FADE_OUT_S)
	assert_false(h.banner.is_showing(), "faded out")
	h.size = Vector2(2000, 900)
	bus.emit_signal("map_entered", "000000041", "000000040")
	assert_near(h.banner.position.x + h.banner.get_combined_minimum_size().x * 0.5, 1000.0, 1.0, "the next banner too")


func test_hp_gauge_reads_zero_from_death_to_respawn() -> void:
	var c := _character()
	var h := _hud(c)
	var max_hp := StatCalculator.max_hp(c, db())
	# The killing blow, then the death commit: the character already holds its respawn HP while the notice is up.
	c.hp = 0
	bus.emit_signal("hp_changed", 0, max_hp)
	var respawn_hp := mini(max_hp, 50)
	c.hp = respawn_hp
	bus.emit_signal("player_died", "000000040")
	assert_true(h.dead, "dead")
	assert_eq(h.status.hp_gauge.current, 0, "HP 0 at the death")
	assert_eq(h.status.hp_gauge.value_label.text, "0 / %d" % max_hp, "0 / max")
	for sig: Array in [["stats_changed"], ["hp_changed", respawn_hp, max_hp], ["equipment_changed", ""],
			["leveled_up", c.level], ["game_loaded", "slot1"]]:
		bus.callv(&"emit_signal", [StringName(sig[0])] + sig.slice(1))
		assert_eq(h.status.hp_gauge.current, 0, "still 0 after %s (the respawn HP stays hidden)" % sig[0])
	bus.emit_signal("player_respawned", "000000001")
	assert_false(h.dead, "alive again")
	assert_eq(h.status.hp_gauge.value_label.text, "%d / %d" % [respawn_hp, max_hp], "the respawn HP at the respawn")
	bus.emit_signal("hp_changed", respawn_hp - 5, max_hp)
	assert_eq(h.status.hp_gauge.current, respawn_hp - 5, "HP follows hp_changed again")

	# A death another system announces (HP never reached 0) also reads 0.
	c.hp = 30
	h.refresh_all()
	assert_eq(h.status.hp_gauge.current, 30, "alive: the character's HP")
	bus.emit_signal("player_died", "000000001")
	assert_eq(h.status.hp_gauge.current, 0, "an announced death reads 0")
	bus.emit_signal("player_respawned", "000000001")
	assert_eq(h.status.hp_gauge.current, 30, "and the HP again after the respawn")


func test_a_replaced_character_ends_the_dead_reading_unless_the_game_is_still_dead() -> void:
	var c := _character()
	var game := FakeGame.new()
	nodes.append(game)
	var h: MisoHud = load("res://scenes/ui/hud.tscn").instantiate()
	h.configure(MisoUiEnv.isolated(c, db(), bus, null, game))
	_parent().add_child(h)
	nodes.append(h)
	c.hp = 40
	bus.emit_signal("player_died", "000000040")
	# The game still says dead after the replacement (a load MapSession refused, so it stays in DEAD): still 0.
	game.dead = true
	game.character_replaced.emit("load")
	assert_eq(h.status.hp_gauge.current, 0, "the game still says dead: 0")
	# The real load out of DEAD: MapSession hears character_replaced first and is already in the load's warp, so
	# Game.is_character_dead() is false when the HUD re-reads it (seen in the real game: state WARP_OUT).
	game.dead = false
	game.character_replaced.emit("load")
	assert_false(h.dead, "a replaced character the game says is alive is not the one that died")
	assert_eq(h.status.hp_gauge.current, 40, "its HP shows from the start of the load")
	# Set up while the game says dead (a HUD installed under the death notice).
	game.dead = true
	h.configure(MisoUiEnv.isolated(c, db(), bus, null, game))
	assert_eq(h.status.hp_gauge.current, 0, "configured while dead: 0")


func test_exp_refreshes_log_no_gain() -> void:
	var c := _character()
	var h := _hud(c)
	var need := Progression.exp_to_next(c.level, db())
	c.exp = 9
	bus.emit_signal("exp_gained", 9, "monster:2")
	assert_true(_has_line(h, "You have gained experience (+9)"), "a gain is logged")
	var lines := h.log_panel.history.size()
	# The death penalty: the bar drops, and nothing is logged.
	c.exp = 4
	bus.emit_signal("exp_gained", -5, "death")
	assert_true(h.status.exp_gauge.value_label.text.begins_with("4 / %d" % need), "the EXP bar drops: " + h.status.exp_gauge.value_label.text)
	assert_eq(h.status.exp_gauge.current, 4, "gauge value")
	c.exp = 6
	bus.emit_signal("exp_gained", 0, "")
	assert_eq(h.status.exp_gauge.current, 6, "amount 0 is a refresh")
	assert_eq(h.log_panel.history.size(), lines, "no line for amounts <= 0")
	for t: String in h.log_panel.texts():
		assert_false(t.contains("(+-") or t.contains("(+0)"), "no '+' line for a loss or a refresh: " + t)


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


## Every gain (and spend) is its own event and gets its own line, even when the text repeats at once (selling one
## Orange Potion twice in half a second). Only notices and warnings that repeat the previous line are dropped: a full
## inventory announced again while pickup is held, and a pickup notice that words the HUD's own gain line again.
func test_notice_log_logs_every_gain_and_drops_only_repeated_notices() -> void:
	var c := _character()
	var h := _hud(c)
	var gained := MisoUiText.mesos_gained_line(15)
	bus.emit_signal("mesos_changed", 115, 15)
	bus.emit_signal("mesos_changed", 130, 15)
	assert_eq(h.log_panel.texts().count(gained), 2, "two sales, two lines: %s" % h.log_panel.texts())
	bus.emit_signal("mesos_changed", 80, -50)
	bus.emit_signal("mesos_changed", 30, -50)
	assert_eq(h.log_panel.texts().count("You have spent 50 mesos."), 2, "two purchases, two lines")
	bus.emit_signal("exp_gained", 3, "monster:100100")
	bus.emit_signal("exp_gained", 3, "monster:100100")
	assert_eq(h.log_panel.texts().count(MisoUiText.exp_gained_line(3)), 2, "two kills, two lines")
	var potion_line := MisoUiText.item_gained_line(String(db().item("270").get("name")), 1)
	bus.emit_signal("item_gained", "270", 1)
	bus.emit_signal("item_gained", "270", 1)
	assert_eq(h.log_panel.texts().count(potion_line), 2, "two pickups, two lines")
	# A pickup's notice repeats the HUD's own line word for word (LootPickupRules.pickup_notice): shown once.
	bus.emit_signal("notice", potion_line)
	assert_eq(h.log_panel.texts().count(potion_line), 2, "the pickup notice collapses into the gain line")
	bus.emit_signal("mesos_changed", 145, 15)
	bus.emit_signal("notice", gained)
	assert_eq(h.log_panel.texts().count(gained), 3, "a meso pickup's notice collapses too")
	# Refusals: holding pickup at a full bag says it once.
	var n := h.log_panel.history.size()
	bus.emit_signal("inventory_full", "270")
	bus.emit_signal("notice", "Your inventory is full.")
	bus.emit_signal("inventory_full", "270")
	assert_eq(h.log_panel.history.size(), n + 1, "a full inventory is logged once: %s" % h.log_panel.texts())
	# After DEDUPE_S the same refusal is news again.
	h.log_panel.advance(MisoNoticeLog.DEDUPE_S + 0.1)
	bus.emit_signal("inventory_full", "270")
	assert_eq(h.log_panel.history.size(), n + 2, "logged again after %.1f s" % MisoNoticeLog.DEDUPE_S)


func test_quickslot_bind_use_decrement_and_persist() -> void:
	var c := _character()
	var items := ItemService.new(c, db(), bus)
	assert_eq(items.gain("270", 5), 5, "5 potions")
	c.hp = 10
	var h := _hud(c)
	assert_true(MisoQuickslots.bind(h.env, "1", "270"), "bind a consumable")
	assert_eq(c.quickslots.get("1"), {"kind": "item", "id": "270"}, "a typed binding in CharacterState.quickslots (C3)")
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
	# The turn-in: talking to the end NPC ticks the npc_talk objective (quest_progressed), then the quest completes.
	# The talk is the completion itself, so no "Quest updated" line comes before "Quest complete".
	for i in int(kill["count"]) - 1:
		bus.emit_signal("monster_killed", String(kill["id"]), "000000040")
	var d := qs.engine.definition("1006")
	var progressed := [0]
	bus.quest_progressed.connect(func(_q: String) -> void: progressed[0] += 1)
	var before := h.log_panel.history.size()
	bus.emit_signal("npc_talked", d.end_npc_id)
	assert_eq(progressed[0], 1, "talking to %s ticks the turn-in objective (quest_progressed)" % d.end_npc_id)
	assert_eq(h.log_panel.history.size(), before, "the turn-in talk adds no line: %s" % str(h.log_panel.texts()))
	assert_true(qs.complete("1006").get("ok", false), "turned in")
	assert_true(_has_line(h, "Quest complete: %s" % quest_name), "complete line: %s" % str(h.log_panel.texts()))
	for t: String in h.log_panel.texts():
		assert_false(t.begins_with("Quest updated:"), "no generic line at the turn-in: %s" % str(h.log_panel.texts()))
	qs.detach()


## The quest_progressed line names what moved: counts, a visited map, an NPC spoken to en route. A turn-in talk
## names nothing (the completion follows); nothing identifiable, no line.
func test_quest_progress_line_names_what_moved() -> void:
	var kill := {"key": "monster_kills:100100", "kind": "monster_kills", "name": "Snail", "current": 3, "required": 10}
	var talk := {"key": "npc_talk:11", "kind": "npc_talk", "id": "11", "name": "Mai", "purpose": "talk", "current": 1,
		"required": 1}
	var turn_in := {"key": "npc_talk:9", "kind": "npc_talk", "id": "9", "name": "Sam", "purpose": "turn_in", "current": 1,
		"required": 1}
	var was := {"monster_kills:100100": 2, "npc_talk:11": 0, "npc_talk:9": 0}
	assert_eq(MisoHud.quest_progress_line("Q", was, [kill]), "Q: Snail 3/10", "a count")
	assert_eq(MisoHud.quest_progress_line("Q", was, [kill, talk]), "Q: Snail 3/10, spoke to Mai", "a count and a talk")
	assert_eq(MisoHud.quest_progress_line("Q", was, [talk]), "Q: spoke to Mai", "an NPC spoken to en route")
	assert_eq(MisoHud.quest_progress_line("Q", was, [turn_in]), "", "a turn-in talk: no line")
	assert_eq(MisoHud.quest_progress_line("Q", was, [kill, turn_in]), "Q: Snail 3/10", "the turn-in adds nothing")
	var same := {"monster_kills:100100": 3, "npc_talk:11": 1}
	assert_eq(MisoHud.quest_progress_line("Q", same, [kill, talk]), "", "nothing moved: no line")


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
