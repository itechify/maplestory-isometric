extends TestCase
## MisoMinimap (res://scenes/ui/minimap.tscn) on a private bus, a private map_session.gd and MisoUiEnv.isolated, over
## small stand-in maps built from the canonical records (their portals, NPCs and names; the geometry is made up): no
## autoload state is read or changed, and no world export is needed (test_ui_minimap_world covers the real maps).
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
func _minimap(map_id: String, c: CharacterState = null, ctx: GameContext = null, game: Object = null) -> Dictionary:
	var mm: MisoMinimap = load("res://scenes/ui/minimap.tscn").instantiate()
	var ms := _session(map_id)
	var env := MisoUiEnv.isolated(c if c != null else _character(), db(), bus, ctx, game)
	env.map_session = ms
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
