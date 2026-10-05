class_name IslandWorld
extends Node3D
## The playable island (scenes/world/world.tscn; MAP_ARCHITECTURE.md option C, "AllResident" residency; milestone M2:
## trails are walked through gates on edge-mode links, press Up warps on every link).
##
## Building it (build() async with load_progress for a loading screen, or build_now() synchronously):
##   1. data      WorldSidecars + MapDefinitions.build(Data.db, sidecars)
##   2. sky/sun   index.json environment -> WorldEnvironment + DirectionalLight3D
##   3. chunks    every visual glb (optional: load_visuals) and every collision glb; collision bodies are moved to
##                the WorldLayers table (map/interior/trail Ground -> walkable, Walls/hulls -> blocking, other world
##                chunks -> scenery)
##   4. trails    TrailLoader: each trail link's ribbon (the export's World_Trails meshes until its sidecar carries a
##                centreline), then RegionIndex with map footprints and trail zones
##   5. ground    MapDefinitions.ground_all(PhysicsGroundQuery): arrivals, player spawns, NPCs, spawn slots, gate heights;
##                finish_trails(): kill_y and camera bounds include the trails
##   6. nodes     containment (rings with a gap at every gate, plugs closing the gaps of warp-mode links, trail side
##                walls), a sea kill plane, one WorldPortal per canonical portal, one WorldNpc per MeowDB NPC, the
##                MapInstanceView, FallRecovery, PortalInteractor, GateMonitor, RegionMonitor and the ScreenFader
##   7. session   attaches itself to the MapSession autoload (attach_to_session)
## Wave 2 composes this scene into the main game scene, adds the player and calls set_player(player); the camera
## rig registers with MapSession.attach_camera(). The world never decides current_map: MapSession does.
## The shell hands it the GameContext with set_context(ctx) (or a modal_provider Callable): while a modal owns the
## keyboard, the world never turns the player's input back on and PortalInteractor ignores the portal keys.
## Link modes can change at runtime (PortalGraph.set_link_mode, the debug console): the world re-applies the plugs,
## the camera bounds and the active gates (link_mode_changed).

signal load_progress(fraction: float, stage: String)
signal world_ready()
## Lighting preset / BGM change for the entered map (wave 2 audio and lighting listen). config is
## MapDefinition.environment_configuration; blend_s is 0 under a fade.
signal environment_changed(config: Dictionary, blend_s: float)
## A non-player body reached the sea kill plane (monsters: the monster system decides what to do).
signal body_fell(body: Node3D)

const PORTAL_SCENE := preload("res://scenes/world/portal.tscn")

@export var assets_dir: String = WorldSidecars.DEFAULT_DIR
## Load the visual glbs (off for headless checks: collision, portals and NPCs are enough).
@export var load_visuals: bool = true
## Load the island in _ready() (asynchronously, emitting load_progress).
@export var build_on_ready: bool = true
## Register with the MapSession autoload once built.
@export var attach_to_session: bool = true

var content: ContentDB = null
var sidecars: WorldSidecars = null
var defs: MapDefinitions = null
var tuning: WorldTuning = null
var library: ProxyLibrary = null
var ground_query: PhysicsGroundQuery = null
var region_index: RegionIndex = null
var player: Node3D = null
## The MapSession this world talks to (the autoload unless set before build).
var session: Node = null
## () -> bool: true while a modal UI (dialogue, shop, console, death notice, pause menu) owns the keyboard. Wins
## over set_context(). Whoever answers true must turn the player's input back on when its last modal closes
## (GameContext.pop_modal does).
var modal_provider: Callable = Callable()
var is_built: bool = false
var build_errors: PackedStringArray = []
var build_warnings: PackedStringArray = []
## "<map>.<portal>" -> WorldPortal
var portal_nodes: Dictionary = {}
## MeowDB npc id -> WorldNpc
var npc_nodes: Dictionary = {}
var rings: Array[StaticBody3D] = []
## Gate key ("<link>><map>") -> the plug body closing that ring gap (enabled while the link is warp).
var plugs: Dictionary = {}
## One body of side walls per trail.
var trail_walls: Array[StaticBody3D] = []
## Gate key -> {map_id, half_width, link_id}: the ring gaps.
var ring_gaps: Dictionary = {}
var stats: Dictionary = {}

var chunks_root: Node3D = null
var collision_root: Node3D = null
var containment_root: Node3D = null
var portals_root: Node3D = null
var npcs_root: Node3D = null
var instance_view: MapInstanceView = null
var fall_recovery: FallRecovery = null
var interactor: PortalInteractor = null
var gate_monitor: GateMonitor = null
var region_monitor: RegionMonitor = null
var fader: ScreenFader = null
var kill_plane: Area3D = null
var sun: DirectionalLight3D = null
var environment_node: WorldEnvironment = null

var _building: bool = false
var _player_mode: ProcessMode = PROCESS_MODE_INHERIT
## The GameContext given to set_context() (duck-typed: is_modal_active()).
var _context: Object = null
## map id -> PackedVector3Array: ground_faces() cache.
var _ground_faces: Dictionary = {}


func _ready() -> void:
	_make_children()
	if build_on_ready:
		build()


func _exit_tree() -> void:
	if session != null and session.has_method("detach_world"):
		session.call("detach_world", self)
	if library != null:
		library.free_templates()


# --- building -----------------------------------------------------------------------------------------------

## Builds asynchronously, emitting load_progress(fraction, stage) every frame; emits world_ready at the end.
func build() -> void:
	if is_built or _building:
		return
	_building = true
	_make_children()
	_stage_data(null)
	load_progress.emit(0.05, "data")
	_stage_environment()
	var plan := _chunk_plan()
	for item in plan:
		ResourceLoader.load_threaded_request(String(item.path), "", true)
	var loaded := {}
	while loaded.size() < plan.size():
		var progress := 0.0
		for item in plan:
			var path := String(item.path)
			if loaded.has(path):
				progress += 1.0
				continue
			var p: Array = []
			var st := ResourceLoader.load_threaded_get_status(path, p)
			if st == ResourceLoader.THREAD_LOAD_LOADED:
				loaded[path] = ResourceLoader.load_threaded_get(path)
				progress += 1.0
			elif st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				build_errors.append("cannot load %s" % path)
				loaded[path] = null
				progress += 1.0
			else:
				progress += float(p[0]) if not p.is_empty() else 0.0
		load_progress.emit(0.05 + 0.75 * progress / maxf(plan.size(), 1.0), "loading chunks")
		if loaded.size() < plan.size():
			await get_tree().process_frame
	var i := 0
	for item in plan:
		_place_chunk(item, loaded.get(String(item.path), null))
		i += 1
		if i % 8 == 0:
			load_progress.emit(0.8 + 0.1 * i / maxf(plan.size(), 1.0), "placing chunks")
			await get_tree().process_frame
	load_progress.emit(0.9, "trails")
	_stage_trails()
	load_progress.emit(0.92, "grounding")
	_stage_ground()
	load_progress.emit(0.97, "portals and npcs")
	_stage_nodes()
	_finish()
	load_progress.emit(1.0, "ready")


## Builds synchronously (tests, tools). `db` defaults to the Data autoload's ContentDB.
func build_now(db: ContentDB = null) -> Error:
	if is_built:
		return OK
	_building = true
	_make_children()
	_stage_data(db)
	_stage_environment()
	for item in _chunk_plan():
		var res: Resource = load(String(item.path)) if ResourceLoader.exists(String(item.path)) else null
		if res == null:
			build_errors.append("cannot load %s" % String(item.path))
		_place_chunk(item, res)
	_stage_trails()
	_stage_ground()
	_stage_nodes()
	_finish()
	return OK if build_errors.is_empty() else FAILED


func _make_children() -> void:
	if chunks_root != null:
		return
	chunks_root = _child_node3d("Chunks")
	collision_root = _child_node3d("Collision")
	containment_root = _child_node3d("Containment")
	portals_root = _child_node3d("Portals")
	npcs_root = _child_node3d("Npcs")
	instance_view = MapInstanceView.new()
	instance_view.name = "Monsters"
	add_child(instance_view)
	fall_recovery = FallRecovery.new()
	fall_recovery.name = "FallRecovery"
	fall_recovery.world = self
	add_child(fall_recovery)
	interactor = PortalInteractor.new()
	interactor.name = "PortalInteractor"
	interactor.world = self
	add_child(interactor)
	gate_monitor = GateMonitor.new()
	gate_monitor.name = "GateMonitor"
	gate_monitor.world = self
	add_child(gate_monitor)
	region_monitor = RegionMonitor.new()
	region_monitor.name = "RegionMonitor"
	region_monitor.world = self
	add_child(region_monitor)
	fader = ScreenFader.new()
	fader.name = "Fader"
	add_child(fader)


func _child_node3d(n: String) -> Node3D:
	var c := Node3D.new()
	c.name = n
	add_child(c)
	return c


func _stage_data(db: ContentDB) -> void:
	content = db if db != null else _autoload_db()
	sidecars = WorldSidecars.load_dir(assets_dir)
	build_errors.append_array(sidecars.load_errors)
	defs = MapDefinitions.build(content, sidecars)
	tuning = defs.tuning
	build_errors.append_array(defs.errors)
	build_warnings.append_array(defs.warnings)
	region_index = RegionIndex.from_defs(defs)


## {path, chunk, which: "visual"|"collision", kind, trails: bool} for every glb to load.
func _chunk_plan() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for chunk in sidecars.geometry_chunks():
		var sc := sidecars.chunk(chunk)
		var meta := {"chunk": chunk, "kind": String(sc.get("kind", "")), "trails": sc.has("trails")}
		var col := sidecars.file_path(chunk, "collision")
		if col != "" and not FileAccess.file_exists(col):
			build_warnings.append("%s lists %s, which does not exist; skipped" % [chunk, col])
			col = ""
		if col != "":
			var m := meta.duplicate()
			m["path"] = col
			m["which"] = "collision"
			out.append(m)
		var vis := sidecars.file_path(chunk, "visual")
		if vis != "" and not FileAccess.file_exists(vis):
			build_warnings.append("%s lists %s, which does not exist; skipped" % [chunk, vis])
			vis = ""
		if load_visuals and vis != "":
			var m2 := meta.duplicate()
			m2["path"] = vis
			m2["which"] = "visual"
			out.append(m2)
	return out


func _place_chunk(item: Dictionary, res: Resource) -> void:
	if not (res is PackedScene):
		return
	var root := (res as PackedScene).instantiate()
	if String(item.which) == "visual":
		root.name = String(item.chunk)
		chunks_root.add_child(root)
		stats["visual_chunks"] = int(stats.get("visual_chunks", 0)) + 1
		return
	root.name = String(item.chunk) + "_collision"
	var gameplay := String(item.kind) in ["map", "interior"] or bool(item.trails)
	var double_sided := gameplay and double_sided_trimesh(String(defs.id_of_slug.get(String(item.chunk), "")))
	var bodies := 0
	for body in root.find_children("*", "StaticBody3D", true, false):
		var sb := body as StaticBody3D
		var ground := String(sb.name).begins_with("Ground")
		if gameplay:
			sb.collision_layer = WorldLayers.WALKABLE if ground else WorldLayers.BLOCKING
		else:
			sb.collision_layer = WorldLayers.SCENERY
		sb.collision_mask = 0
		sb.set_meta("chunk", String(item.chunk))
		bodies += 1
		if double_sided:
			for cs in sb.find_children("*", "CollisionShape3D", true, false):
				var trimesh := (cs as CollisionShape3D).shape as ConcavePolygonShape3D
				if trimesh != null:
					# A copy: the imported scene's cached shape stays as exported for any other build in the process.
					trimesh = trimesh.duplicate() as ConcavePolygonShape3D
					trimesh.backface_collision = true
					(cs as CollisionShape3D).shape = trimesh
					stats["double_sided_trimeshes"] = int(stats.get("double_sided_trimeshes", 0)) + 1
	collision_root.add_child(root)
	stats["collision_bodies"] = int(stats.get("collision_bodies", 0)) + bodies


## maps/<id>.json `collision.double_sided_trimesh` (with its reason): the map chunk's trimesh collision (Ground and
## Walls) collides from both sides. The export's trimesh faces point outward, so where the player walks inside an
## enclosure (Southperry's ship: its bulwarks, the forecastle's deck and bulkhead) it would pass through them from
## within (WORLD_RUNTIME.md "Region extensions").
func double_sided_trimesh(map_id: String) -> bool:
	if map_id == "" or tuning == null:
		return false
	var c: Variant = tuning.map_override(map_id).get("collision", {})
	return c is Dictionary and bool((c as Dictionary).get("double_sided_trimesh", false)) \
		and String((c as Dictionary).get("reason", "")) != ""


func _stage_environment() -> void:
	var env := sidecars.environment()
	var sun_data: Dictionary = env.get("sun", {}) if env.get("sun", null) is Dictionary else {}
	if sun == null:
		sun = DirectionalLight3D.new()
		sun.name = "Sun"
		add_child(sun)
	sun.transform = WorldSidecars.xform(sun_data.get("xform", null))
	sun.light_color = Color(String(sun_data.get("color_srgb", "#FFFFFF")))
	sun.light_energy = float(sun_data.get("blender_strength_w_m2", 1.0)) * tuning.num("environment", "sun_energy_per_w_m2")
	sun.shadow_enabled = true
	if environment_node == null:
		environment_node = WorldEnvironment.new()
		environment_node.name = "Environment"
		add_child(environment_node)
	var e := Environment.new()
	var sky_cols: Array = env.get("sky_gradient_srgb", [])
	var mat := ProceduralSkyMaterial.new()
	if sky_cols.size() >= 2:
		mat.sky_horizon_color = Color(String(sky_cols[0]))
		mat.sky_top_color = Color(String(sky_cols[1]))
		mat.ground_horizon_color = Color(String(sky_cols[0]))
		mat.ground_bottom_color = Color(String(sky_cols[1]))
	var sky := Sky.new()
	sky.sky_material = mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	var bgs: Array = env.get("world_backgrounds", [])
	if not bgs.is_empty() and bgs[0] is Dictionary:
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(String(bgs[0].get("color_srgb", "#FFFFFF")))
		e.ambient_light_energy = float(bgs[0].get("strength", 1.0))
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment_node.environment = e


## Trail ribbons (TrailLoader; the live World_Trails visual chunk when visuals were loaded).
func _stage_trails() -> void:
	var visual_root: Node = null
	for chunk in sidecars.chunks:
		if (sidecars.chunks[chunk] as Dictionary).get("trails", null) is Array:
			visual_root = chunks_root.get_node_or_null(NodePath(String(chunk)))
	build_errors.append_array(TrailLoader.attach(defs, sidecars, visual_root))


func _stage_ground() -> void:
	ground_query = PhysicsGroundQuery.new(get_world_3d().direct_space_state)
	ground_query.coplanar_tolerance = tuning.num("grounding", "coplanar_tolerance_m")
	if player is CollisionObject3D:
		ground_query.exclude = [(player as CollisionObject3D).get_rid()]
	build_warnings.append_array(defs.ground_all(ground_query))
	build_errors.append_array(defs.finish_trails())
	region_index = RegionIndex.from_defs(defs)


func _stage_nodes() -> void:
	var built := ContainmentBuilder.build(defs, containment_root)
	rings = built.rings
	plugs = built.plugs
	trail_walls = built.walls
	ring_gaps = built.gaps
	if not defs.graph.link_mode_changed.is_connected(_on_link_mode_changed):
		defs.graph.link_mode_changed.connect(_on_link_mode_changed)
	_make_kill_plane()
	library = ProxyLibrary.load_from(assets_dir.path_join("_library.glb"), assets_dir.path_join("_library.json"))
	for p in defs.canonical_portals():
		if not p.has_anchor:
			continue
		var node: WorldPortal = PORTAL_SCENE.instantiate()
		portals_root.add_child(node)
		node.setup(p, library)
		node.watched = player  # set_player() may have run before the build finished
		portal_nodes[p.key()] = node
	build_errors.append_array(tuning.talk_zone_errors())
	var placed := {}
	for id in defs.ids():
		for pl in defs.get_def(id).npc_definitions:
			placed[pl.npc_id] = true
	var profiles := tuning.talk_zone_profiles()
	for pname: String in profiles:
		for nid: Variant in (profiles[pname] as Dictionary).get("npcs", []):
			if not placed.has(str(nid)):
				build_errors.append("presentation.json npc.talk_zones.%s lists npc %s, which no map places" % [pname, str(nid)])
	for id in defs.ids():
		for pl in defs.get_def(id).npc_definitions:
			var n := WorldNpc.new()
			npcs_root.add_child(n)
			var zone := tuning.talk_zone(pl.npc_id)
			n.setup(pl, library, float(zone.radius_m), float(zone.centre_height_m), String(zone.profile))
			npc_nodes[pl.npc_id] = n
	instance_view.library = library
	instance_view.tuning = tuning


func _make_kill_plane() -> void:
	var sea := sidecars.sea_level_y()
	if is_nan(sea):
		return
	var box := AABB()
	var first := true
	for chunk in sidecars.geometry_chunks():
		var b: Dictionary = sidecars.chunk(chunk).get("bounds", {}) if sidecars.chunk(chunk).get("bounds", null) is Dictionary else {}
		if b.is_empty():
			continue
		var a := AABB(WorldSidecars.vec3(b.get("position", null)), WorldSidecars.vec3(b.get("size", null)))
		box = a if first else box.merge(a)
		first = false
	var depth := tuning.num("fall_recovery", "sea_kill_depth_m")
	kill_plane = Area3D.new()
	kill_plane.name = "SeaKillPlane"
	kill_plane.collision_layer = WorldLayers.KILL
	kill_plane.collision_mask = WorldLayers.PLAYER | WorldLayers.MONSTERS
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(box.size.x, depth, box.size.z)
	cs.shape = shape
	kill_plane.add_child(cs)
	add_child(kill_plane)
	kill_plane.global_position = Vector3(box.get_center().x, sea + depth * 0.5, box.get_center().z)
	kill_plane.body_entered.connect(_on_kill_plane)


func _on_kill_plane(body: Node3D) -> void:
	if body == player:
		fall_recovery.recover("reached the sea")
	else:
		body_fell.emit(body)


func _finish() -> void:
	is_built = true
	_building = false
	stats["portals"] = portal_nodes.size()
	stats["npcs"] = npc_nodes.size()
	stats["rings"] = rings.size()
	stats["trails"] = defs.trail_list().filter(func(t: TrailDef) -> bool: return t.has_geometry()).size()
	stats["plugs"] = plugs.size()
	for e in build_errors:
		push_error("[IslandWorld] " + e)
	if player != null:
		register_climbables(player)
	if attach_to_session:
		if session == null:
			session = get_node_or_null("/root/MapSession")
		if session != null and session.has_method("attach_world"):
			session.call("attach_world", self)
	world_ready.emit()


# --- the player -----------------------------------------------------------------------------------------------

## Registers the player body (duck-typed: teleport(xform), is_on_floor(), global_position, velocity; optional
## set_input_enabled(bool), input_source, safe_ground, safe_ground_filter, in_hitstun, add_climbables_from_sidecar).
## A player that can climb and has no climbables yet gets every map's ladders, ropes and vines from the sidecars
## (climbables[]), so ladders work in the game and for the traversal bot.
## A physics body is put on the world's layer table: collision_layer = WorldLayers.PLAYER (portal triggers, NPC talk
## areas and the sea kill plane watch that layer) and WorldLayers.PLAYER_MASK added to its collision_mask (walkable,
## blocking, containment, scenery), so walls, rings and scenery stop it whatever layers its scene was authored with.
func set_player(p: Node3D) -> void:
	player = p
	if p is CollisionObject3D:
		var body := p as CollisionObject3D
		body.collision_layer = WorldLayers.PLAYER
		body.collision_mask |= WorldLayers.PLAYER_MASK
	fall_recovery.attach_player(p)
	for k in portal_nodes:
		(portal_nodes[k] as WorldPortal).watched = p
	if ground_query != null and p is CollisionObject3D:
		ground_query.exclude = [(p as CollisionObject3D).get_rid()]
	register_climbables(p)
	if gate_monitor != null:
		gate_monitor.reset()
	if region_monitor != null:
		region_monitor.reset()


## Gives `p` every map sidecar's climbables (ladders, ropes, vines) when it can climb and has none yet. Returns how
## many it has.
func register_climbables(p: Node) -> int:
	if p == null or sidecars == null or defs == null or not p.has_method("add_climbables_from_sidecar") or not ("climbables" in p):
		return 0
	if not (p.get("climbables") as Array).is_empty():
		return (p.get("climbables") as Array).size()
	for id in defs.ids():
		var def := defs.get_def(id)
		if def.sidecar.get("climbables", null) is Array:
			p.call("add_climbables_from_sidecar", def.sidecar.climbables)
	return (p.get("climbables") as Array).size()


func session_node() -> Node:
	return session


func place_player(xform: Transform3D) -> void:
	if player == null:
		return
	if player.has_method("teleport"):
		player.call("teleport", xform)
	else:
		player.global_transform = xform
		if "velocity" in player:
			player.set("velocity", Vector3.ZERO)
	fall_recovery.reset_to(xform)
	# A teleport is never a gate crossing, and the old ground point says nothing about the new place.
	if gate_monitor != null:
		gate_monitor.reset()
	if region_monitor != null:
		region_monitor.reset()


## Freezes (process disabled, velocity zeroed) or unfreezes the player's physics.
func freeze_player(on: bool) -> void:
	if player == null:
		return
	if on:
		if player.process_mode != PROCESS_MODE_DISABLED:
			_player_mode = player.process_mode
		player.process_mode = PROCESS_MODE_DISABLED
		if "velocity" in player:
			player.set("velocity", Vector3.ZERO)
	else:
		player.process_mode = _player_mode


## Turns the player's input on or off (MapSession: off for a warp or a death, on when the arrival is grounded).
## Turning it ON is refused while a modal is open (is_modal_active()): the modal owns the keyboard, and the context
## turns input back on when its last modal closes. Turning it off always goes through.
func set_player_input(on: bool) -> void:
	if player == null:
		return
	if on and is_modal_active():
		return
	if player.has_method("set_input_enabled"):
		player.call("set_input_enabled", on)
	elif "input_enabled" in player:
		player.set("input_enabled", on)


## The game's GameContext (duck-typed: is_modal_active()); null forgets it. GameSession calls this once the context
## exists, so warps never hand the keyboard back under a modal and portal keys typed into a modal are ignored.
func set_context(ctx: Object) -> void:
	_context = ctx


## True while a modal owns the keyboard: modal_provider when set, else the context from set_context(), else the
## context of the nearest ancestor that exposes one as a `ctx` property (GameSession composes the world as its child
## and owns the GameContext; a fallback until the shell calls set_context). False when none is known.
func is_modal_active() -> bool:
	if modal_provider.is_valid():
		return bool(modal_provider.call())
	var ctx := _context if _context != null and is_instance_valid(_context) else _ancestor_context()
	return ctx != null and ctx.has_method("is_modal_active") and bool(ctx.call("is_modal_active"))


## Why the player's keys must not act on the world right now ("" when they may): "no player", "dead" (the
## controller's is_dead()), "input off" (is_input_enabled() false, or the input_enabled property), "modal".
## PortalInteractor checks it before every press; prompts can use it too.
func player_input_block() -> String:
	if player == null or not is_instance_valid(player):
		return "no player"
	if player.has_method("is_dead") and bool(player.call("is_dead")):
		return "dead"
	if player.has_method("is_input_enabled"):
		if not bool(player.call("is_input_enabled")):
			return "input off"
	elif "input_enabled" in player and not bool(player.get("input_enabled")):
		return "input off"
	if is_modal_active():
		return "modal"
	return ""


func _ancestor_context() -> Object:
	var n := get_parent()
	while n != null:
		if "ctx" in n:
			var c: Variant = n.get("ctx")
			if c is Object and is_instance_valid(c) and (c as Object).has_method("is_modal_active"):
				return c
		n = n.get_parent()
	return null


func player_on_floor() -> bool:
	if player == null:
		return true
	return bool(player.call("is_on_floor")) if player.has_method("is_on_floor") else true


func has_player() -> bool:
	return player != null and is_instance_valid(player)


## {"ok", "position", "facing"} of the SafeGround record in use.
func safe_point() -> Dictionary:
	var sg := fall_recovery.safe_ground()
	return {"ok": sg.valid, "position": sg.position, "facing": sg.facing}


# --- map activation (called by MapSession inside the swap frame) ---------------------------------------------

## Hands back the live instance's monsters.
func release_instance() -> void:
	instance_view.release()


## Activates `def`: portals and NPC interaction for this map only, the arrival portal disarmed, monsters realized.
func activate_map(def: MapDefinition, state: MapInstanceState, arrival: ArrivalRef, xform: Transform3D) -> void:
	var disarm := bool(tuning.portal_section("anti_ping_pong").get("disarm_arrival_portal_until_exit", true))
	for k in portal_nodes:
		var wp: WorldPortal = portal_nodes[k]
		var on := wp.def.source_map_id == def.map_id
		wp.set_interaction_enabled(on)
		wp.armed = true
		if on and disarm and arrival != null and arrival.is_portal() and arrival.portal_id == wp.def.portal_id:
			wp.disarm()
	for id in npc_nodes:
		var n: WorldNpc = npc_nodes[id]
		n.set_interaction_enabled(n.map_id() == def.map_id)
	instance_view.realize(state, def, xform.origin)


func apply_environment(def: MapDefinition, blend_s: float) -> void:
	environment_changed.emit(def.environment_configuration, blend_s)


## A link changed mode (PortalGraph.link_mode_changed: the debug console, a test): the plugs follow it, camera bounds
## are recomputed (the current map's are re-applied through MapSession.refresh_camera) and GateMonitor re-reads its
## gates.
func _on_link_mode_changed(link_id: String, _mode: String) -> void:
	ContainmentBuilder.set_plugs(defs, plugs)
	defs.refresh_camera_bounds()
	if gate_monitor != null:
		gate_monitor.refresh()
	if session != null and session.has_method("refresh_camera"):
		var t := defs.trail(link_id)
		if t == null or t.touches(current_map_id()):
			session.call("refresh_camera")


## Load-chain validation of a saved resume point (MAP_ARCHITECTURE section 4.9 step 1): in the map's region, on
## walkable ground, capsule-clear and outside every portal trigger, except the trigger of `entry`, the portal the save
## says the player arrived through (ArrivalResolver passes it). An accepted resume arrives through that same entry, so
## activate_map disarms that portal exactly as on a real arrival: standing in its trigger after a Continue is the state
## the arrival itself left (G1: every edge arrival spawns inside its own portal's trigger, 0.7 m from the gate, and the
## save made right after a trail arrival used to be refused for it, falling back to that arrival with a warning).
func validate_resume(map_id: String, pos: Vector3, entry: ArrivalRef = null) -> bool:
	var def := defs.get_def(map_id)
	if def == null or ground_query == null:
		return false
	if String(region_index.region_of(pos, map_id).get("id", "")) != map_id:
		return false
	var g := ground_query.ground_at(pos, tuning.num("grounding", "probe_up_m"), tuning.num("grounding", "probe_down_m"))
	if not bool(g.ok):
		return false
	var feet := Vector3(pos.x, float(g.y), pos.z)
	if not ground_query.is_clear(feet + Vector3.UP * tuning.num("grounding", "capsule_lift_m"),
			tuning.num("grounding", "capsule_radius_m"), tuning.num("grounding", "capsule_height_m")):
		return false
	var entered := entry.portal_id if entry != null and entry.is_portal() and entry.map_id == map_id else ""
	for p in def.portals:
		if p.has_anchor and p.portal_type != PortalDef.TYPE_ARRIVAL and p.portal_id != entered \
				and p.trigger_contains(feet + Vector3.UP * 0.1):
			return false
	return true


# --- queries for wave 2 (interaction prompts, debug overlays) ------------------------------------------------

func current_map_id() -> String:
	return String(session.get("current_map")) if session != null else ""


## Portals of a map (WorldPortal nodes).
func portals_of(map_id: String) -> Array[WorldPortal]:
	var out: Array[WorldPortal] = []
	for k in portal_nodes:
		var wp: WorldPortal = portal_nodes[k]
		if wp.def.source_map_id == map_id:
			out.append(wp)
	return out


func portal_node(map_id: String, portal_id: String) -> WorldPortal:
	return portal_nodes.get("%s.%s" % [map_id, portal_id], null)


## NPC nodes of a map.
func npcs_of(map_id: String) -> Array[WorldNpc]:
	var out: Array[WorldNpc] = []
	for id in npc_nodes:
		var n: WorldNpc = npc_nodes[id]
		if n.map_id() == map_id:
			out.append(n)
	return out


## The armed, enabled, pressable portal the player is inside (nearest anchor first), or null.
func portal_under_player() -> WorldPortal:
	if player == null:
		return null
	var best: WorldPortal = null
	var best_d := INF
	for wp in portals_of(current_map_id()):
		if not (wp.interaction_enabled and wp.armed and wp.def.accepts_press()):
			continue
		if not wp.contains(player):
			continue
		var d := player.global_position.distance_to(wp.def.anchor_ground)
		if d < best_d:
			best_d = d
			best = wp
	return best


## The nearest thing the interact key would act on at `pos`: a portal the player is inside (armed, pressable) or a
## current-map NPC whose own talk zone (WorldNpc.in_range, WorldTuning.talk_zone) holds the player. With no player,
## `pos` within the NPC's talk_radius_m of its feet. {"kind": "portal"|"npc", "node", "id", "distance"} or {} when
## nothing. The NPC/dialogue system should act on interact only when kind == "npc"; PortalInteractor acts on "portal".
func nearest_interactable(pos: Vector3) -> Dictionary:
	var best := {}
	var best_d := INF
	var under := portal_under_player()
	if under != null:
		best_d = pos.distance_to(under.def.anchor_ground)
		best = {"kind": "portal", "node": under, "id": under.def.key(), "distance": best_d}
	for n in npcs_of(current_map_id()):
		if player != null and not n.in_range(player):
			continue
		var d := pos.distance_to(n.global_position)
		if player == null and d > n.talk_radius_m:
			continue
		if d < best_d:
			best_d = d
			best = {"kind": "npc", "node": n, "id": n.npc_id(), "distance": d}
	return best


## The walkable ground of a map as triangles (three points each) in the island's coordinates (those of
## MapDefinition): the faces of its collision chunk's Ground* bodies (meta "chunk" == the map's slug), each shape's
## faces moved by its CollisionShape3D's transform (ConcavePolygonShape3D.get_faces() is shape-local). Cached per map
## id; empty for an unknown map, a world not built yet, or a chunk without ground trimeshes. Raw: nothing is
## filtered (the minimap, MinimapModel, keeps what it draws).
func ground_faces(map_id: String) -> PackedVector3Array:
	if _ground_faces.has(map_id):
		return _ground_faces[map_id]
	var out := PackedVector3Array()
	var def := defs.get_def(map_id) if defs != null else null
	if def == null or def.slug == "" or collision_root == null or not is_built:
		return out
	for body in collision_root.find_children("Ground*", "StaticBody3D", true, false):
		if String(body.get_meta("chunk", "")) != def.slug:
			continue
		for cs in body.find_children("*", "CollisionShape3D", true, false):
			var shape := (cs as CollisionShape3D).shape as ConcavePolygonShape3D
			if shape == null:
				continue
			out.append_array(_relative_xform(cs as Node3D) * shape.get_faces())
	_ground_faces[map_id] = out
	return out


## `n`'s transform in this world's space (its global transform when the world sits at the origin).
func _relative_xform(n: Node3D) -> Transform3D:
	if n.is_inside_tree() and is_inside_tree():
		return global_transform.affine_inverse() * n.global_transform
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != self:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


## Overlay data: build state, counts, the player's region.
func debug_info() -> Dictionary:
	var info := stats.duplicate()
	info["built"] = is_built
	info["errors"] = build_errors.size()
	info["warnings"] = build_warnings.size()
	info["live_monsters"] = instance_view.live_count() if instance_view != null else 0
	info["fall_recoveries"] = fall_recovery.recoveries if fall_recovery != null else 0
	info["gate_commits"] = gate_monitor.commits if gate_monitor != null else 0
	info["armed_gates"] = gate_monitor.armed_maps() if gate_monitor != null else PackedStringArray()
	info["region_violations"] = region_monitor.violations if region_monitor != null else 0
	info["link_modes"] = defs.graph.mode_counts() if defs != null else {}
	if player != null and region_index != null:
		info["region"] = region_index.region_of(player.global_position, current_map_id())
		info["position"] = player.global_position
	return info


static func _autoload_db() -> ContentDB:
	var tree := Engine.get_main_loop() as SceneTree
	var data: Node = tree.root.get_node_or_null("Data") if tree != null else null
	if data != null and data.get("db") is ContentDB:
		return data.get("db")
	return ContentDB.new().load_all()
