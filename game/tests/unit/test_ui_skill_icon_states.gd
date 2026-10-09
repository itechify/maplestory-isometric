extends TestCase
## Skill icons draw the icon packs' state pictures (#51, docs/runtime/UI.md "Icon packs"): iconDisabled wherever
## MisoSkillIcon.dim greys a skill, iconMouseOver while the pointer is over a skill in the Skills window or a
## quickslot, and for a state whose variant no pack has, the plain icon (under the procedural dim while greyed). The
## cooldown sweep draws over the art and counts down as before. The fake pack is written by the test to a private
## user:// folder (solid-colour PNGs made with Image.create, loaded through the raw-PNG path) and removed after each
## test; the shared resolver is swapped for the test's own and restored. No network and no Nexon art.

const NIMBLE := "0001002"       # all three variants in the fake pack
const RECOVERY := "0001001"     # the plain icon only
const SNAILS := "0001000"       # in no pack: the procedural badge
const ONLY_DISABLED := "9999999"  # an iconDisabled without its plain icon
const PLAIN := Color(0, 1, 0)
const DISABLED := Color(0, 0, 1)
const MOUSE_OVER := Color(1, 1, 0)

var bus: Node
## The private folder the fake pack lives in (removed after each test).
var root := ""
var nodes: Array = []
var game: GameState = null


func before_each() -> void:
	bus = load("res://scripts/autoload/events.gd").new()
	root = "user://_tests".path_join("skill_icon_states_%d_%d" % [Time.get_ticks_usec(), randi()])
	var pack := _pack("fake", [[NIMBLE, "icon", PLAIN], [NIMBLE, "iconDisabled", DISABLED],
		[NIMBLE, "iconMouseOver", MOUSE_OVER], [RECOVERY, "icon", PLAIN], [ONLY_DISABLED, "iconDisabled", DISABLED]])
	MisoIconResolver.set_shared(MisoIconResolver.new(PackedStringArray([pack])))


func after_each() -> void:
	MisoIconResolver.set_shared(null)
	nodes.reverse()
	for n in nodes:
		if is_instance_valid(n):
			n.free()
	nodes.clear()
	if game != null:
		game.free()
		game = null
	bus.free()
	_remove_tree(root)


## A fake pack in format 1 under root: entries are [skill_id, variant, colour], each a 32 x 32 PNG of that colour.
func _pack(pack_name: String, entries: Array) -> String:
	var dir := root.path_join(pack_name)
	var skills := {}
	for e: Array in entries:
		var folder := dir.path_join("skills/%s" % e[0])
		DirAccess.make_dir_recursive_absolute(folder)
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		img.fill(e[2])
		assert_eq(img.save_png(folder.path_join("%s.png" % e[1])), OK, "PNG written")
		if not skills.has(e[0]):
			skills[e[0]] = {}
		skills[e[0]][e[1]] = {"size": [32, 32], "sha256": "", "url": "", "fetched": "2026-10-09"}
	var f := FileAccess.open(dir.path_join("pack.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"format": 1, "name": pack_name, "source": {"service": "test"}, "items": {},
		"skills": skills, "missing": []}, "  "))
	f.close()
	return dir


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for d in dir.get_directories():
		_remove_tree(path.path_join(d))
	for f in dir.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)


## The colour of the pack picture an icon draws now, or null when it draws the procedural badge.
func _drawn(icon: MisoSkillIcon) -> Variant:
	var art := icon.shown_art()
	return art.texture.get_image().get_pixel(0, 0) if art != null else null


func _character() -> CharacterState:
	var cr := CharacterFactory.create(CharacterFactory.default_params(db()), db())
	assert_true(cr.ok, "factory character")
	return cr.character


func _parent() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.current_scene if tree.current_scene != null else tree.root


func _windows(c: CharacterState) -> MisoWindowsRoot:
	game = GameState.new()
	game.db = db()
	game.event_bus = bus
	game.log_warnings = false
	game.character = c
	var windows: MisoWindowsRoot = load("res://scenes/ui/windows.tscn").instantiate()
	windows.configure(MisoUiEnv.isolated(c, db(), bus, null, game))
	_parent().add_child(windows)
	nodes.append(windows)
	return windows


func _hud(c: CharacterState) -> MisoHud:
	var h: MisoHud = load("res://scenes/ui/hud.tscn").instantiate()
	h.configure(MisoUiEnv.isolated(c, db(), bus, null))
	_parent().add_child(h)
	nodes.append(h)
	return h


# --- the states ----------------------------------------------------------------------------------------------------

func test_each_state_draws_its_variant_or_falls_back_to_the_plain_icon_and_the_procedural_dim() -> void:
	# [skill, dim, hover, the picture drawn (null: the badge), greyed by the procedural dim, why]
	var cases: Array = [
		[NIMBLE, false, false, PLAIN, false, "the plain icon"],
		[NIMBLE, true, false, DISABLED, false, "greyed: iconDisabled, not the procedural dim"],
		[NIMBLE, false, true, MOUSE_OVER, false, "under the pointer: iconMouseOver"],
		[NIMBLE, true, true, DISABLED, false, "greyed under the pointer: still iconDisabled"],
		[RECOVERY, false, false, PLAIN, false, "the plain icon"],
		[RECOVERY, true, false, PLAIN, true, "no iconDisabled: the plain icon under the procedural dim"],
		[RECOVERY, false, true, PLAIN, false, "no iconMouseOver: the plain icon, not greyed"],
		[RECOVERY, true, true, PLAIN, true, "greyed under the pointer: the procedural dim"],
		[SNAILS, false, false, null, false, "no pack: the badge"],
		[SNAILS, true, false, null, true, "no pack: the badge, greyed as before"],
		[SNAILS, false, true, null, false, "no pack: the badge, unchanged under the pointer"],
		[ONLY_DISABLED, false, false, null, false, "no plain icon: the badge"],
		[ONLY_DISABLED, true, false, DISABLED, false, "but greyed, the pack's iconDisabled"],
	]
	for row: Array in cases:
		var icon: MisoSkillIcon = MisoSkillIcon.new()
		nodes.append(icon)
		icon.skill_id = row[0]
		icon.size = Vector2(36, 36)
		icon.dim = row[1]
		icon.hover = row[2]
		var what := "%s dim=%s hover=%s: %s" % (row.slice(0, 3) + [row[5]])
		assert_eq(_drawn(icon), row[3], what)
		assert_eq(icon.procedural_dim(), row[4], what + " (procedural dim)")
		assert_eq(icon.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST if row[3] != null
			else CanvasItem.TEXTURE_FILTER_PARENT_NODE, what + " (nearest filtering only under pack art)")
		assert_eq(icon.art_rect(), Rect2(2, 2, 32, 32) if row[3] != null else Rect2(),
			what + " (the variant fills the cell at 1x)")
	var nf: MisoSkillIcon = MisoSkillIcon.new()
	nodes.append(nf)
	nf.skill_id = NIMBLE
	nf.dim = true
	nf.hover = true
	nf.dim = false
	assert_eq(_drawn(nf), MOUSE_OVER, "ungreyed under the pointer: iconMouseOver")
	nf.hover = false
	assert_eq(_drawn(nf), PLAIN, "the pointer gone: the plain icon")
	nf.skill_id = SNAILS
	assert_eq([nf.art, nf.disabled_art, nf.hover_art], [null, null, null], "another skill resolves again")


# --- the Skills window and the quickslots ---------------------------------------------------------------------------

func test_the_skills_window_greys_unlearned_skills_and_lights_the_one_under_the_pointer() -> void:
	var c := _character()
	c.sp = 1
	var windows := _windows(c)
	windows.open_window("skills")
	var w := windows.skills
	var nimble: MisoSkillsWindow.SkillIconCell = w.rows[NIMBLE]["icon"]
	var recovery: MisoSkillsWindow.SkillIconCell = w.rows[RECOVERY]["icon"]
	var snails: MisoSkillsWindow.SkillIconCell = w.rows[SNAILS]["icon"]
	assert_eq(_drawn(nimble.icon), DISABLED, "unlearned Nimble Feet: its iconDisabled")
	assert_eq([_drawn(recovery.icon), recovery.icon.procedural_dim()], [PLAIN, true],
		"unlearned Recovery: its icon under the procedural dim")
	assert_eq([_drawn(snails.icon), snails.icon.procedural_dim()], [null, true], "unlearned Three Snails: the dim badge")
	nimble.mouse_entered.emit()
	assert_eq(_drawn(nimble.icon), DISABLED, "under the pointer, still greyed")
	nimble.mouse_exited.emit()
	assert_true(w.add_point(NIMBLE), "learn Nimble Feet")
	assert_eq(_drawn(nimble.icon), PLAIN, "learned: its icon")
	nimble.mouse_entered.emit()
	assert_eq(_drawn(nimble.icon), MOUSE_OVER, "the pointer over its cell: iconMouseOver")
	w.refresh()
	assert_eq(_drawn(nimble.icon), MOUSE_OVER, "a refresh keeps it")
	nimble.mouse_exited.emit()
	assert_eq(_drawn(nimble.icon), PLAIN, "the pointer gone: its icon")
	recovery.mouse_entered.emit()
	assert_eq([_drawn(recovery.icon), recovery.icon.procedural_dim()], [PLAIN, true],
		"Recovery has no iconMouseOver and stays greyed")


func test_a_quickslot_greys_an_unusable_skill_and_lights_under_the_pointer() -> void:
	var c := _character()
	c.skills = {NIMBLE: 1, SNAILS: 1}
	c.mp = StatCalculator.max_mp(c, db())
	var h := _hud(c)
	assert_true(MisoQuickslots.bind_skill(h.env, "1", NIMBLE), "bind Nimble Feet")
	assert_true(MisoQuickslots.bind_skill(h.env, "2", SNAILS), "bind Three Snails")
	h.refresh_all()
	var nf: MisoQuickslotBar.QuickslotCell = h.status.quickslots.slots["1"]
	var snails: MisoQuickslotBar.QuickslotCell = h.status.quickslots.slots["2"]
	assert_eq(_drawn(nf.skill_icon), PLAIN, "usable: its icon")
	assert_eq([_drawn(snails.skill_icon), snails.skill_icon.procedural_dim()], [null, true],
		"no Snail Shell and no pack: the dim badge, as before")
	c.mp = 0
	h.refresh_all()
	assert_eq(_drawn(nf.skill_icon), DISABLED, "without the MP: its iconDisabled")
	assert_false(nf.skill_icon.procedural_dim(), "not the procedural dim")
	nf.mouse_entered.emit()
	assert_eq(_drawn(nf.skill_icon), DISABLED, "under the pointer, still greyed")
	c.mp = StatCalculator.max_mp(c, db())
	h.status.quickslots.refresh_skills()
	assert_eq(_drawn(nf.skill_icon), MOUSE_OVER, "usable again under the pointer: iconMouseOver")
	nf.mouse_exited.emit()
	assert_eq(_drawn(nf.skill_icon), PLAIN, "the pointer gone: its icon")
	snails.mouse_entered.emit()
	assert_eq(_drawn(snails.skill_icon), null, "no pack: the badge under the pointer too")


func test_the_cooldown_sweep_counts_down_over_the_art() -> void:
	var c := _character()
	c.skills = {NIMBLE: 1}
	c.mp = StatCalculator.max_mp(c, db())
	var h := _hud(c)
	assert_true(MisoQuickslots.bind_skill(h.env, "1", NIMBLE), "bind Nimble Feet")
	h.refresh_all()
	var nf: MisoQuickslotBar.QuickslotCell = h.status.quickslots.slots["1"]
	var total := SkillDef.of(NIMBLE, db()).cooldown_s(1)
	assert_true(total > 0.0, "Nimble Feet has a cooldown")
	EffectBook.start_cooldown(c, NIMBLE, total)
	h.status.quickslots.refresh_skills()
	assert_eq(_drawn(nf.skill_icon), PLAIN, "cooling down over its icon")
	assert_true(nf.skill_icon.cooldown > 0.99, "the sweep starts full")
	assert_eq(nf.skill_icon.cooldown_text, str(ceili(total)), "seconds left")
	EffectBook.tick(c, total * 0.5)
	h.status.quickslots.refresh_skills()
	assert_near(nf.skill_icon.cooldown, 0.5, 0.01, "half the cooldown left")
	assert_eq(nf.skill_icon.cooldown_text, str(ceili(EffectBook.cooldown_left(c, NIMBLE))), "the seconds count down")
	c.mp = 0
	nf.mouse_entered.emit()
	h.status.quickslots.refresh_skills()
	assert_eq(_drawn(nf.skill_icon), DISABLED, "greyed while cooling down: the sweep over its iconDisabled")
	assert_near(nf.skill_icon.cooldown, 0.5, 0.01, "the same sweep")
	EffectBook.tick(c, total)
	h.status.quickslots.refresh_skills()
	assert_eq([nf.skill_icon.cooldown, nf.skill_icon.cooldown_text], [0.0, ""], "ready: no sweep")
