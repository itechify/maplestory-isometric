extends TestCase
## MisoMinimap (res://scenes/ui/minimap.tscn) on a private bus, a private map_session.gd and MisoUiEnv.isolated, over
## small stand-in maps built from the canonical records (their portals, NPCs and names; the geometry is made up): no
## autoload state is read or changed, and no world export is needed (test_ui_minimap_world covers the real maps). The
## fold's restart test writes one private preferences file under user://_tests/ and removes it.
## Checks: the title strip names the canonical street and map and stays when M folds the map away; the map id shows
## exactly while the debug overlay is on; M toggles and stays quiet under a modal; NPC dots follow the quest engine
## (Sam "!" -> "..." after accepting 1006, Mai "?" once the Snails are killed); the player's arrow follows the player,
## is clamped to the edge off the map and tagged with the trail's destination; map_entered rebuilds; portal markers,
## shop badges, role icons and hover text.

const XFORM := [0.70711, 0, 0.70711, 0.45452, 0.76604, -0.45452, -0.54168, 0.64279, 0.54168, 0, 0, 0]
const SAM_MAP := "000000040"
const MAI_MAP := "000000050"
const SOUTHPERRY := "000000060"


## A world stand-in: MapDefinitions and their ground.
class FakeWorld extends RefCounted:
	var defs: MapDefinitions = null
	var is_built := true

	func ground_faces(map_id: String) -> PackedVector3Array:
		var def := defs.get_def(map_id)
		if def == null:
			return PackedVector3Array()
		# The footprint at the base and a raised terrace (two upward triangles each), plus a downward underside.
		var out := PackedVector3Array()
		for q: Array in [[0.0, 0.0, 40.0, 30.0, 0.0], [5.0, 5.0, 15.0, 12.0, 3.0]]:
			var x0: float = q[0]
			var z0: float = q[1]
			var x1: float = q[2]
			var z1: float = q[3]
			var y: float = def.base_y + float(q[4])
			out.append_array(PackedVector3Array([Vector3(x0, y, z0), Vector3(x0, y, z1), Vector3(x1, y, z0)]))
			out.append_array(PackedVector3Array([Vector3(x1, y, z0), Vector3(x0, y, z1), Vector3(x1, y, z1)]))
		out.append_array(PackedVector3Array([Vector3(0, def.base_y - 8.0, 0), Vector3(40, def.base_y - 8.0, 0), Vector3(0, def.base_y - 8.0, 30)]))
		return out


## The Debug autoload's overlay switch.
class FakeDebug extends RefCounted:
	signal overlay_toggled(on: bool)
	var overlay_enabled := false

	func set_overlay(on: bool) -> void:
		overlay_enabled = on
		overlay_toggled.emit(on)


## A player body with the controller's facing.
class FakePlayer extends Node3D:
	var facing := Vector3(1, 0, 0)


## The Game autoload's character_replaced signal (a load or a new character swaps the live character).
class FakeGame extends RefCounted:
	signal character_replaced(reason: String)


var bus: Node = null
var nodes: Array[Node] = []


func parity_keys() -> Dictionary:
	return {
		"test_the_title_strip_names_the_map_and_shows_the_id_in_debug_mode": ["ui:map-name-display", "ui:minimap-map-id-debug"],
		"test_m_folds_the_map_to_the_title_and_is_quiet_under_a_modal": ["ui:key-bindings", "ui:map-name-display"],
		"test_a_load_or_a_new_character_re_reads_the_map": ["ui:map-name-display"],
		"test_npc_dots_follow_the_quests": ["ui:quest-indicators", "quest:1006"],
		"test_portals_npcs_shops_and_hover_text": ["ui:shop-indication", "ui:portal-cue", "npc:16", "npc:15"],
		"test_name_tags_mark_shopkeepers_and_transport": ["ui:shop-indication", "npc:15", "npc:16", "npc:20", "npc:21"],
		"test_name_tag_role_line_follows_the_role": ["ui:shop-indication"],
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


## A stand-in map from the canonical record: a 40 x 30 m footprint at x/z 0..40/0..30, its canonical type-2 portals
## along the east edge (plus its hidden ones, which must not show), its canonical NPCs along z = 15.
func _def(map_id: String) -> MapDefinition:
	var rec := db().map(map_id)
	var def := MapDefinition.new()
	def.map_id = map_id
	def.map_name = String(rec["name"])
	def.base_y = 2.0
	def.footprint_layout = PackedVector2Array([Vector2(0, 0), Vector2(40, 0), Vector2(40, 30), Vector2(0, 30)])
	def.footprint = PackedVector2Array([Vector2(-1, -1), Vector2(41, -1), Vector2(41, 31), Vector2(-1, 31)])
	def.sidecar = {"cameras": {"gameplay": {"xform": XFORM}}}
	var k := 0
	for p: Dictionary in rec.get("portals", []):
		var pd := PortalDef.new()
		pd.portal_id = String(p["name"])
		pd.source_map_id = map_id
		pd.destination_map_id = String(p["to_map_id"])
		pd.canonical_type = int(p["type"])
		pd.hidden = int(p["type"]) == 1
		pd.has_anchor = true
		pd.portal_type = PortalDef.TYPE_DOOR if pd.portal_id.begins_with("in") else PortalDef.TYPE_EDGE
		pd.anchor_ground = Vector3(40, def.base_y, 4.0 + 8.0 * k)
		pd.inward = Vector3(-1, 0, 0)
		def.portals.append(pd)
		k += 1
	var arrival := PortalDef.new()
	arrival.portal_id = "arrival:T_x"
	arrival.source_map_id = map_id
	arrival.portal_type = PortalDef.TYPE_ARRIVAL
	arrival.has_anchor = true
	arrival.anchor_ground = Vector3(0, def.base_y, 15)
	def.portals.append(arrival)
	k = 0
	for n: Dictionary in rec.get("npcs", []):
		var pl := NpcPlacement.new()
		pl.npc_id = str(n["id"])
		pl.npc_name = String(n.get("name", ""))
		pl.map_id = map_id
		pl.transform = Transform3D(Basis.IDENTITY, Vector3(8.0 + 6.0 * k, def.base_y, 15))
		def.npc_definitions.append(pl)
		k += 1
	return def


func _world() -> FakeWorld:
	var w := FakeWorld.new()
	w.defs = MapDefinitions.new()
	for id in [SAM_MAP, MAI_MAP, SOUTHPERRY]:
		w.defs.maps[id] = _def(id)
	return w


func _session(map_id: String) -> Node:
	var ms: Node = load("res://scripts/autoload/map_session.gd").new()
	ms.current_map = map_id
	nodes.append(ms)
	return ms


## The minimap scene on `map_id`, configured like the shell does, with the stand-ins.
## `prefs`: the UI preferences file (MisoUiPrefs); "" keeps nothing.
func _minimap(map_id: String, c: CharacterState = null, ctx: GameContext = null, game: Object = null,
		prefs: String = "") -> Dictionary:
	var mm: MisoMinimap = load("res://scenes/ui/minimap.tscn").instantiate()
	var ms := _session(map_id)
	var env := MisoUiEnv.isolated(c if c != null else _character(), db(), bus, ctx, game)
	env.map_session = ms
	env.prefs_path = prefs
	var dbg := FakeDebug.new()
	var p := FakePlayer.new()
	_parent().add_child(p)
	nodes.append(p)
	mm.world = _world()
	mm.player = p
	mm.debug = dbg
	mm.configure(env)
	_parent().add_child(mm)
	nodes.append(mm)
	return {"minimap": mm, "session": ms, "env": env, "debug": dbg, "player": p}


func _name(map_id: String) -> String:
	return String(db().map(map_id)["name"])


func _street(map_id: String) -> String:
	return String(db().map(map_id)["street_name"])


func test_the_scene_is_installed_after_the_hud() -> void:
	assert_true(ResourceLoader.exists("res://scenes/ui/minimap.tscn"), "the scene exists")
	var names: PackedStringArray = []
	for e: Dictionary in SubsystemInstaller.DEFAULT_SUBSYSTEMS:
		names.append(String(e["name"]))
	var i := names.find("Minimap")
	assert_true(i > names.find("HUD") and i < names.find("Windows"), "after the HUD, below the windows: %s" % names)
	var mm: Node = load("res://scenes/ui/minimap.tscn").instantiate()
	assert_true(mm is MisoMinimap and mm.has_method("setup"), "root MisoMinimap with setup(ctx)")
	mm.free()


func test_the_title_strip_names_the_map_and_shows_the_id_in_debug_mode() -> void:
	var r := _minimap(SAM_MAP)
	var mm: MisoMinimap = r["minimap"]
	assert_eq(mm.map_id, SAM_MAP, "the session's map")
	assert_eq(mm.name_label.text, _name(SAM_MAP), "canonical name")
	assert_eq(mm.street_label.text, _street(SAM_MAP), "canonical street")
	assert_eq(mm.title_text(), "%s · %s" % [_street(SAM_MAP), _name(SAM_MAP)], "the title")
	assert_false(mm.id_label.visible, "no map id in normal play")
	(r["debug"] as FakeDebug).set_overlay(true)
	assert_true(mm.id_label.visible and mm.id_label.text == SAM_MAP, "the canonical id while the debug overlay is on")
	assert_true(mm.title_text().ends_with("[%s]" % SAM_MAP), mm.title_text())
	(r["debug"] as FakeDebug).set_overlay(false)
	assert_false(mm.id_label.visible, "and gone again with the overlay")
	bus.emit_signal("map_entered", MAI_MAP, SAM_MAP)
	assert_eq(mm.name_label.text, _name(MAI_MAP), "map_entered: the new map's name")
	assert_eq(mm.view.model.map_id, MAI_MAP, "map_entered rebuilds the picture")
	bus.emit_signal("map_entered", "999999999", MAI_MAP)
	assert_eq(mm.name_label.text, "999999999", "an unknown map shows its id")
	assert_eq(mm.view.model, null, "and no picture")


## A load (Events.game_loaded) or a swapped character (Game.character_replaced) re-reads the current map without a
## map_entered; leaving the tree lets go of the game's signal.
func test_a_load_or_a_new_character_re_reads_the_map() -> void:
	var game := FakeGame.new()
	var r := _minimap(SAM_MAP, null, null, game)
	var mm: MisoMinimap = r["minimap"]
	var ms: Node = r["session"]
	assert_eq(mm.map_id, SAM_MAP, "the session's map")
	ms.current_map = MAI_MAP
	game.character_replaced.emit("load")
	assert_eq(mm.map_id, MAI_MAP, "character_replaced: the current map again")
	assert_eq(mm.name_label.text, _name(MAI_MAP), "with its canonical name")
	assert_true(mm.view.model != null and mm.view.model.map_id == MAI_MAP, "and its picture")
	assert_true(bus.has_signal("game_loaded"), "the bus has game_loaded")
	ms.current_map = SOUTHPERRY
	bus.emit_signal("game_loaded", "slot_1")
	assert_eq(mm.map_id, SOUTHPERRY, "game_loaded: the loaded map")
	assert_eq(mm.name_label.text, _name(SOUTHPERRY), "with its canonical name")
	_parent().remove_child(mm)
	assert_true(game.get_signal_connection_list("character_replaced").is_empty(), "out of the tree: disconnected from Game")
	_parent().add_child(mm)
	assert_false(game.get_signal_connection_list("character_replaced").is_empty(), "back in the tree: connected again")


func test_m_folds_the_map_to_the_title_and_is_quiet_under_a_modal() -> void:
	var ctx := GameContext.new()
	var r := _minimap(SAM_MAP, null, ctx)
	var mm: MisoMinimap = r["minimap"]
	assert_true(mm.is_expanded() and mm.view.visible, "shown on a new game")
	var press := InputEventAction.new()
	press.action = MisoMinimap.ACTION
	press.pressed = true
	mm._unhandled_input(press)
	assert_false(mm.is_expanded() or mm.view.visible, "M folds the map away")
	assert_true(mm.name_label.is_visible_in_tree() and mm.name_label.text == _name(SAM_MAP),
		"the map name stays on screen (the persistent map name)")
	mm._unhandled_input(press)
	assert_true(mm.is_expanded() and mm.view.visible, "M brings it back")
	ctx.push_modal(self)
	mm._unhandled_input(press)
	assert_true(mm.is_expanded(), "nothing under a modal")
	ctx.pop_modal(self)
	mm.fold_button.pressed.emit()
	assert_false(mm.is_expanded(), "the fold button does the same")
	bus.emit_signal("map_entered", MAI_MAP, SAM_MAP)
	assert_false(mm.is_expanded(), "folded survives a map change")
	assert_eq(mm.name_label.text, _name(MAI_MAP), "with the new name")
	var other := InputEventAction.new()
	other.action = "toggle_inventory"
	other.pressed = true
	mm._unhandled_input(other)
	assert_false(mm.is_expanded(), "other keys leave it alone")


## Issue #15: the fold is a UI preference kept beside the save slots (MisoUiPrefs), so folding the minimap, quitting
## and starting again shows it folded. Here a private file in user:// stands for the save directory's, and a second
## minimap on it for the next start. With no file it opens unfolded; an env with no preferences keeps nothing.
func test_the_fold_survives_a_restart() -> void:
	var dir := "user://_tests/ui_minimap_prefs_%d_%d" % [Time.get_ticks_usec(), randi()]
	var prefs := dir.path_join(MisoUiPrefs.FILE_NAME)
	var first: MisoMinimap = _minimap(SAM_MAP, null, null, null, prefs)["minimap"]
	assert_true(first.is_expanded(), "no saved preference: unfolded")
	var press := InputEventAction.new()
	press.action = MisoMinimap.ACTION
	press.pressed = true
	first._unhandled_input(press)
	assert_false(first.is_expanded(), "M folds it")
	assert_true(FileAccess.file_exists(prefs), "the fold is written to %s" % prefs)
	assert_eq(MisoUiPrefs.read(prefs, MisoUiPrefs.MINIMAP, MisoUiPrefs.MINIMAP_EXPANDED, true), false, "as folded")
	first.free()  # quit
	var second: MisoMinimap = _minimap(MAI_MAP, null, null, null, prefs)["minimap"]
	assert_false(second.is_expanded() or second.view.visible, "the next start shows it folded")
	assert_true(second.name_label.is_visible_in_tree() and second.name_label.text == _name(MAI_MAP),
		"with the map's name on the title strip")
	second.fold_button.pressed.emit()
	assert_true(second.is_expanded(), "unfolded again")
	second.free()
	var third: MisoMinimap = _minimap(SAM_MAP, null, null, null, prefs)["minimap"]
	assert_true(third.is_expanded() and third.view.visible, "and the start after that shows it unfolded")
	third.set_expanded(false)
	var none: MisoMinimap = _minimap(SAM_MAP)["minimap"]
	assert_true(none.is_expanded(), "an env with no preferences file reads none")
	none.set_expanded(false)
	assert_eq(MisoUiEnv.isolated(null, db(), bus).ui_prefs_path(), "", "an isolated env names no file")
	DirAccess.remove_absolute(prefs)
	DirAccess.remove_absolute(dir)


## Issue #15: the status bar's "Map [M]" button shows the minimap's key and folds the map like M does.
func test_the_status_bar_map_button_folds_the_minimap() -> void:
	var c := _character()
	var hud: MisoHud = load("res://scenes/ui/hud.tscn").instantiate()
	hud.configure(MisoUiEnv.isolated(c, db(), bus))
	_parent().add_child(hud)
	nodes.append(hud)
	var mm: MisoMinimap = _minimap(SAM_MAP, c)["minimap"]
	var b := hud.status.map_button
	var key := MisoUiEnv.key_label(MisoMinimap.ACTION)
	assert_eq(key, "M", "the minimap's key is M (Controls)")
	assert_eq(b.text, "Map [M]", "the button names the key")
	assert_eq(hud.status.menu_buttons.get("map"), b, "in the status bar's button grid")
	assert_true(mm.is_expanded(), "unfolded")
	b.pressed.emit()
	assert_false(mm.is_expanded() or mm.view.visible, "the button folds the map to the title strip")
	b.pressed.emit()
	assert_true(mm.is_expanded() and mm.view.visible, "and unfolds it")


func test_npc_dots_follow_the_quests() -> void:
	var c := _character()
	var qs := QuestService.create(bus, db(), c, RandomNumberGenerator.new())
	qs.attach()
	var r := _minimap(SAM_MAP, c)
	var mm: MisoMinimap = r["minimap"]
	(r["env"] as MisoUiEnv).quest_engine_override = qs.engine
	mm.refresh_markers()
	var sam := qs.engine.definition("1006").start_npc_id
	var mai := qs.engine.definition("1006").end_npc_id
	assert_true(sam in mm.snapshot()["npcs"], "Sam's dot on %s" % SAM_MAP)
	assert_eq(mm.snapshot()["markers"].get(sam, ""), "available", "Sam: a quest available ('!')")
	assert_eq(mm.snapshot()["markers"].get(sam, ""), qs.engine.npc_marker(sam), "the same rule as the badge over his head")
	assert_true(qs.accept("1006").get("ok", false), "accepted Sam's Suggestion")
	assert_eq(mm.snapshot()["markers"].get(sam, ""), "in_progress", "quest_started: Sam's dot turns to '...'")
	bus.emit_signal("map_entered", MAI_MAP, SAM_MAP)
	assert_true(mai in mm.snapshot()["npcs"], "Mai's dot on %s" % MAI_MAP)
	assert_eq(mm.snapshot()["markers"].get(mai, ""), "in_progress", "Mai: the quest is under way")
	var kill: Dictionary = {}
	for o: Dictionary in qs.engine.definition("1006").objectives:
		if o["kind"] == "monster_kills":
			kill = o
	for i in int(kill["count"]):
		bus.emit_signal("monster_killed", String(kill["id"]), SAM_MAP)
	assert_eq(mm.snapshot()["markers"].get(mai, ""), "completable", "after the kills: Mai's dot shows '?'")
	assert_true(mm.view.describe_at(mm.view.to_px(mm.view.model.npc(mai)["pos"])).contains("ready to turn in"),
		"hovering Mai says so")
	qs.detach()


func test_player_arrow_follows_the_player_and_the_trail() -> void:
	var r := _minimap(SAM_MAP)
	var mm: MisoMinimap = r["minimap"]
	var p: FakePlayer = r["player"]
	p.global_position = Vector3(20, 2, 15)
	mm.refresh_player()
	var s := mm.snapshot()
	assert_true(s["player_in_view"] and not s["player_clamped"], "the player on the map: arrow inside the picture")
	var at: Vector2 = mm.view.player_marker()["pos"]
	p.global_position = Vector3(30, 2, 15)
	mm.advance(MisoMinimap.MARKER_REFRESH_S)
	var moved: Vector2 = mm.view.player_marker()["pos"]
	assert_true(moved.x > at.x, "moving camera-right moves the arrow right (%s -> %s)" % [at, moved])
	p.global_position = Vector3(400, 2, 15)
	mm.refresh_player()
	s = mm.snapshot()
	assert_true(s["player_clamped"] and not s["player_in_view"], "far off the map: clamped to the edge")
	assert_true(Rect2(Vector2.ZERO, mm.view.size).has_point(mm.view.player_marker()["pos"]), "still inside the picture")
	(r["session"] as Node).call("set_trail", "T_000000040_east00__000000041_west00", "000000041")
	assert_eq(mm.snapshot()["trail_tag"], _name("000000041"), "trail_changed: tagged with the destination's canonical name")
	var tag := mm.view.trail_tag_layout()
	assert_true(not tag.is_empty() and tag["text"] == "-> %s" % _name("000000041"), "the tag is laid out: %s" % tag)
	assert_true(not tag.is_empty() and Rect2(Vector2.ZERO, mm.view.size).encloses(tag["rect"]), "inside the picture: %s" % tag)
	(r["session"] as Node).call("set_trail", "", "")
	assert_true(mm.view.trail_tag_layout().is_empty(), "no tag laid out off the trail")
	assert_eq(mm.snapshot()["trail_tag"], "", "off the trail: no tag")
	mm.player = null
	mm.refresh_player()
	assert_true(mm.view.player_marker().is_empty(), "no player, no arrow")


func test_portals_npcs_shops_and_hover_text() -> void:
	var r := _minimap(SOUTHPERRY)
	var mm: MisoMinimap = r["minimap"]
	var s := mm.snapshot()
	var want := PackedStringArray()
	var hidden := 0
	for p: Dictionary in db().map(SOUTHPERRY).get("portals", []):
		if int(p["type"]) == 2:
			want.append(String(p["name"]))
		else:
			hidden += 1
	assert_eq(s["portals"], want, "the visible canonical portals, no arrival gate")
	assert_eq(s["ground_source"], MinimapModel.SOURCE_COLLISION, "the world's ground faces")
	assert_eq(s["ground"], 4, "the four upward triangles; the underside is left out")
	assert_eq(MisoMinimapView.build_meshes(mm.view.model).size(), 2, "one ground mesh per tier (the base and the terrace)")
	for p: Dictionary in mm.view.model.portals:
		var shops := MinimapModel.shopkeepers_on(db(), String(p["dest_map_id"]))
		assert_eq(String(p["id"]) in s["shop_doors"], not shops.is_empty(), "%s: shop badge iff a shopkeeper inside" % p["id"])
		var tip := mm.view.describe_at(mm.view.to_px(p["pos"]))
		assert_true(tip.begins_with("Portal to %s" % _name(String(p["dest_map_id"]))), tip)
		if not shops.is_empty():
			assert_true(tip.contains("Shop: %s" % shops[0]), tip)
	assert_false((s["shop_doors"] as PackedStringArray).is_empty(), "Southperry's door to Pan's store has the badge")
	var npcs := PackedStringArray()
	for n: Dictionary in db().map(SOUTHPERRY).get("npcs", []):
		npcs.append(str(n["id"]))
	assert_eq(s["npcs"], npcs, "the canonical NPCs")
	for nid: String in s["roles"]:
		assert_eq(s["roles"][nid], MapIcons.npc_role(db().npc(nid)), "NPC %s role icon from the canonical record" % nid)
	assert_true((s["roles"] as Dictionary).values().has(MapIcons.ROLE_TRANSPORT), "Shanks (Transport) has the boat")
	var shanks := ""
	for nid: String in s["roles"]:
		if s["roles"][nid] == MapIcons.ROLE_TRANSPORT:
			shanks = nid
	var tip := mm.view.describe_at(mm.view.to_px(mm.view.model.npc(shanks)["pos"]))
	assert_eq(tip, "%s, %s" % [String(db().npc(shanks)["name"]), MapIcons.TRANSPORT_ROLE], "hovering Shanks")
	assert_eq(mm.view.describe_at(Vector2(-100, -100)), "", "nothing under the pointer: no tooltip")
	for l: Dictionary in mm.view.label_layout():
		assert_true(Rect2(Vector2.ZERO, mm.view.size).encloses(l["rect"]), "label %s inside the picture" % l["id"])
	assert_eq(mm.snapshot()["labels"].size(), want.size(), "two exits: both names fit")


## Shop indication on the NPCs themselves: every canonical NPC's name tag, through the real NpcPresenter, carries the
## coin when the record has a shop (Pan, Sid, Lucy, with their function title), the boat for the Transport role
## (Shanks, with "Transport" under his name) and nothing for anyone else.
func test_name_tags_mark_shopkeepers_and_transport() -> void:
	var overlay := Control.new()
	_parent().add_child(overlay)
	nodes.append(overlay)
	var shops := 0
	var transports := 0
	for nid in db().ids("npcs"):
		var rec := db().npc(nid)
		var n := Node3D.new()
		n.set_meta("npc_id", nid)
		overlay.add_child(n)
		var p := NpcPresenter.attach(n, overlay, db())
		var want := MapIcons.npc_role(rec)
		assert_eq(p.tag.role, want, "NPC %s (%s) role icon" % [nid, rec.get("name")])
		assert_eq(p.tag.role_icon.visible, want != "", "NPC %s icon shown iff it has a role icon" % nid)
		assert_eq(p.tag.name_label.text, String(rec["name"]), "NPC %s name" % nid)
		if want == MapIcons.ROLE_SHOP:
			shops += 1
			assert_true(rec.get("shop") is Dictionary, "NPC %s: a shop behind the coin" % nid)
			assert_eq(p.tag.title_label.text, String(rec["function_title"]), "NPC %s: the canonical function title" % nid)
		elif want == MapIcons.ROLE_TRANSPORT:
			transports += 1
			assert_true((rec.get("roles", []) as Array).has(MapIcons.TRANSPORT_ROLE), "NPC %s: the canonical role" % nid)
			assert_true(p.tag.title_label.visible and p.tag.title_label.text == MapIcons.TRANSPORT_ROLE,
				"NPC %s: 'Transport' under the name" % nid)
		else:
			assert_false(rec.get("shop") is Dictionary, "NPC %s: no shop, no coin" % nid)
	assert_true(shops >= 3 and transports >= 1, "Maple Island's shopkeepers (%d) and Shanks (%d)" % [shops, transports])


## The places tried for a destination name: none of the nine sides or corners touches the portal's own glyph box (the
## first corners did, so a name could never go there), the slid copies end inside the picture, and near every edge and
## corner of the picture some place fits.
func test_label_candidates_clear_the_glyph_and_slide_inside() -> void:
	var area := Rect2(Vector2(2, 2), Vector2(226, 166))
	var half := Vector2.ONE * (MisoMinimapView.PORTAL_R + 1.0)
	var sz := Vector2(120.4, 16.0)
	for at: Vector2 in [Vector2(115, 85), Vector2(222, 12), Vector2(8, 160), Vector2(10, 12), Vector2(222, 160)]:
		for dir: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2(0.7, 0.7).normalized()]:
			var cs := MisoMinimapView.label_candidates(at, dir, sz, area)
			assert_true(cs.size() >= 9, "%s: the nine sides and corners" % at)
			for i in 9:
				assert_false(Rect2(cs[i], sz).intersects(Rect2(at - half, half * 2.0)),
					"%s %s: candidate %d %s clears the glyph" % [at, dir, i, cs[i]])
			for i in range(9, cs.size()):
				assert_true(area.encloses(Rect2(cs[i].round(), sz)), "%s: slid candidate %s inside %s" % [at, cs[i], area])
			var fits := cs.filter(func(c: Vector2) -> bool:
				var r := Rect2(c.round(), sz)
				return area.encloses(r) and not r.intersects(Rect2(at - half, half * 2.0)))
			assert_false(fits.is_empty(), "%s %s: some place inside the picture beside the glyph" % [at, dir])


## The tag's second line in any call order: the function title wins, "Transport" fills in only for a Transport NPC
## without one, and goes again with the role.
func test_name_tag_role_line_follows_the_role() -> void:
	var tag := NpcNameTag.new()
	nodes.append(tag)
	tag.set_role(MapIcons.ROLE_TRANSPORT)
	tag.set_texts("Shanks")
	assert_true(tag.title_label.visible and tag.title_label.text == MapIcons.TRANSPORT_ROLE, "role first, then the texts")
	tag.set_role("")
	assert_false(tag.title_label.visible or tag.role_icon.visible, "no role: no 'Transport' line, no icon")
	assert_eq(tag.title_label.text, "", "the role's line is gone")
	tag.set_texts("Pan", "Armor Seller")
	tag.set_role(MapIcons.ROLE_SHOP)
	assert_eq(tag.title_label.text, "Armor Seller", "a shopkeeper keeps the function title")
	tag.set_role(MapIcons.ROLE_TRANSPORT)
	assert_eq(tag.title_label.text, "Armor Seller", "a function title is never replaced by the role")
	tag.set_texts("Shanks", "")
	assert_eq(tag.title_label.text, MapIcons.TRANSPORT_ROLE, "texts without a title: the role's line again")
