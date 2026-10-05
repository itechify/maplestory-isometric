extends TestCase
## World feedback the minimap package adds to the HUD (brief Phase 12), on a private bus with MisoUiEnv.isolated: a
## level-up announces the unspent SP next to the AP (SP was shown only by the debug `char` command), and the map's name
## stays on screen after the arrival banner fades (the minimap's title strip).

var bus: Node = null
var nodes: Array[Node] = []


func parity_keys() -> Dictionary:
	return {
		"test_a_level_up_announces_the_sp": ["ui:level-up-feedback", "ui:sp-notification"],
		"test_the_map_name_outlasts_the_banner": ["ui:map-name-display"],
	}


func before_each() -> void:
	bus = load("res://scripts/autoload/events.gd").new()


func after_each() -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.free()
	nodes.clear()
	bus.free()


func _parent() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.current_scene if tree.current_scene != null else tree.root


func _character() -> CharacterState:
	var cr := CharacterFactory.create(CharacterFactory.default_params(db()), db())
	assert_true(cr.ok, "factory character")
	return cr.character


func _hud(c: CharacterState) -> MisoHud:
	var h: MisoHud = load("res://scenes/ui/hud.tscn").instantiate()
	h.configure(MisoUiEnv.isolated(c, db(), bus))
	_parent().add_child(h)
	nodes.append(h)
	return h


func test_a_level_up_announces_the_sp() -> void:
	var c := _character()
	var h := _hud(c)
	var r := Progression.gain_exp(c, Progression.exp_to_next(c.level, db()), db())
	assert_eq(int(r["levels_gained"]), 1, "levelled")
	assert_true(c.sp > 0, "the canonical Beginner rule grants SP at level %d (%d)" % [c.level, c.sp])
	bus.emit_signal("leveled_up", c.level)
	var key := MisoUiEnv.key_label("toggle_skills")
	var line := "You have %d SP to distribute%s." % [c.sp, " (press %s)" % key if key != "" else ""]
	assert_true(line in h.log_panel.texts(), "'%s' in %s" % [line, h.log_panel.texts()])
	var lines := h.log_panel.texts()
	assert_true(lines.find(line) > lines.find("Congratulations! You have reached level %d." % c.level), "after the level line")
	c.sp = 0
	var n := h.log_panel.history.size()
	bus.emit_signal("leveled_up", c.level)
	for t in h.log_panel.texts().slice(n):
		assert_false(t.contains("SP to distribute"), "no SP line with no SP: %s" % t)


func test_the_map_name_outlasts_the_banner() -> void:
	var c := _character()
	var h := _hud(c)
	var mm: MisoMinimap = load("res://scenes/ui/minimap.tscn").instantiate()
	var ms: Node = load("res://scripts/autoload/map_session.gd").new()
	ms.current_map = "000000040"
	nodes.append(ms)
	var env := MisoUiEnv.isolated(c, db(), bus)
	env.map_session = ms
	mm.configure(env)
	_parent().add_child(mm)
	nodes.append(mm)
	ms.current_map = "000000050"
	bus.emit_signal("map_entered", "000000050", "000000040")
	assert_true(h.banner.is_showing(), "the arrival banner")
	h.banner.advance(MisoMapBanner.FADE_IN_S + MisoMapBanner.HOLD_S + MisoMapBanner.FADE_OUT_S + 0.1)
	assert_false(h.banner.is_showing(), "the banner has faded")
	assert_true(mm.name_label.is_visible_in_tree(), "the minimap's title is still on screen")
	assert_eq(mm.name_label.text, String(db().map("000000050")["name"]), "naming the canonical map")
	assert_eq(mm.street_label.text, String(db().map("000000050")["street_name"]), "and street")
	mm.set_expanded(false)
	assert_true(mm.name_label.is_visible_in_tree(), "also with the map folded away")
