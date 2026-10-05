extends Node
## Autoload "MapSession": owns current_map and the only way to change it, transition() (MAP_ARCHITECTURE.md §4.3).
##
## Fixed contract (§4.3; other systems call these):
##   var current_map: String, var state: State, var respawn_reference: String, var last_arrival: ArrivalRef,
##   var last_transition: TransitionRecord, func transition(req: TransitionRequest) -> Error,
##   func request_portal(portal: PortalDef) -> Error, func debug_warp(map_id, portal_id := "") -> Error,
##   func can_save() -> bool
## Also: enter_dead()/respawn() (§4.8), enter_from_location()/start_new_game()/load_character() (§4.9),
## capture_location()/save_world() (the save block), attach_world()/attach_camera(), debug_info(), reload_map(),
## reset() (back to BOOT; detach_world() calls it), and the death commit: death_commit / commit_death() /
## death_committed / respawn_location() (classic applies a death's loss at the moment of death; see death_commit).
## Milestone M2: GateMonitor commits walked trails with transition(via "gate") (no fade, no placement), and the
## world's RegionMonitor reports the trail under the player through set_trail() -> trail_changed (the HUD line).
##
## current_map is never inferred from position; it changes only inside transition(). A transition resolves its
## arrival before any fade (a failure never leaves the screen black), fades out (ScreenFader), swaps the instance in
## one frame, emits Events.map_left -> Events.map_entered -> Events.portal_used (portal kinds only), fades in, and
## waits in ARRIVING until the player stands on the floor. Without a world (pure tests) every transition completes
## synchronously. See docs/runtime/WORLD_RUNTIME.md.

enum State { BOOT, IDLE, WARP_OUT, SWAP, WARP_IN, ARRIVING, DEAD }

const VIA_GATE := "gate"
const VIA_PRESS_UP := "press_up"
const VIA_DOOR := "door"
const VIA_RESPAWN := "respawn"
const VIA_LOAD := "load"
const VIA_DEBUG := "debug"
## Vias that use a portal (they need a link direction and emit Events.portal_used).
const PORTAL_VIAS := [VIA_GATE, VIA_PRESS_UP, VIA_DOOR]
## Spec size of the transition log ring buffer (§4.5 step 13); structural, not gameplay tuning.
const TRANSITION_LOG_SIZE := 64
## Physics priority of this autoload: after the player body (0) and PortalInteractor (100), so the ARRIVING check
## reads is_on_floor() as the player left it THIS frame. Autoloads otherwise run first in the physics frame and would
## read the floor state from before the warp (the controller defers its settle while frozen). Structural ordering.
const PHYSICS_PRIORITY := 200

signal state_changed(new_state: State, old_state: State)
signal transition_started(request: TransitionRequest)
## Emitted when a transition is fully done (state back to IDLE, the player grounded).
signal transition_finished(record: TransitionRecord)
signal transition_rejected(reason: String)
## The death's loss was committed (death_commit ran once for this death, the character's location is the respawn
## point): `report` is what the hook returned (DeathRules.apply returns its report), null without a character.
## Emitted once per death, when DEAD is entered; listen to this rather than ordering against Events.player_died.
signal death_committed(map_id: String, report: Variant)
## reset() ran: the session is back in BOOT with nothing current (quit to title).
signal session_reset()
## The player stepped onto a trail of current_map (dest_map_id: the map at its other end, for the HUD line
## "-> <map name>", MAP_ARCHITECTURE section 4.11) or left it (""). Also "" on every map change.
signal trail_changed(dest_map_id: String)

# --- contract ---------------------------------------------------------------------------------------------------
var current_map: String = ""
var state: State = State.BOOT
## Canonical returnMap of current_map.
var respawn_reference: String = ""
## {map_id, portal_id} or {map_id, spawn_index} of the last arrival.
var last_arrival: ArrivalRef = null
## {from, to, via, portal_id, arrival, t_game} of the last committed change.
var last_transition: TransitionRecord = null

# --- collaborators (injectable; null = the autoloads) -----------------------------------------------------------
## All 25 maps and the portal graph. Built lazily from Data.db (+ the export) or taken from the attached world.
var defs: MapDefinitions = null
## The IslandWorld (duck-typed: fader, player, place_player, activate_map, release_instance, ...).
var world: Node = null
## The camera rig (duck-typed: set_bounds(bounds: PackedVector2Array, ortho_size: float, blend_s: float), snap()).
var camera: Object = null
var character: CharacterState = null
var content: ContentDB = null
## () -> float game time; null = Game.clock.
var clock_provider: Callable = Callable()
## Seeds instance RNGs; null = Game.rng.
var rng: RandomNumberGenerator = null
## Requests an autosave after each commit (Saves.request_autosave(), when the save system provides it).
var autosave_enabled: bool = true
## DeathRules hook applied ON RESPAWN (the original §4.8 step 2): Callable(character: CharacterState) -> Variant,
## called by respawn() before the respawn warp, unless this death was already committed by death_commit. Install
## death_commit instead (or one of the two, never both for the same rules).
var death_rules: Callable = Callable()
## Death commit hook, applied AT THE MOMENT OF DEATH (classic MapleStory takes the EXP when the character dies):
## Callable(character: CharacterState) -> Variant (DeathRules.apply fits). When it is set, entering DEAD (by
## enter_dead(), by Events.player_died, or when a warp the player died in completes) does, in this order:
##   1. state DEAD, player input off;
##   2. death_commit.call(Game.character), exactly once for this death (the EXP penalty, the HP/MP the player will
##      respawn with: whatever the hook applies to the live character);
##   3. the character's location becomes respawn_location(): the canonical returnMap's
##      player_spawns[death.json respawn_player_spawn_index], without a resume point;
##   4. death_committed(map_id, report), then Saves.request_autosave() (when autosave_enabled);
##   5. enter_dead() only: Events.player_died(map_id) (the other two paths announced the death already).
## While DEAD after a commit, can_save() is true and save_world() / capture_location() return that respawn location,
## so any save (the pause menu, the autosave, Game's save when the window closes) stores the post-death character in
## town: quitting while dead cannot dodge the loss, and a reload starts at the return map. respawn() then skips
## death_rules. Without death_commit nothing changes: the loss waits for respawn() and saving while DEAD is refused.
var death_commit: Callable = Callable()
## The last commit: {"map_id" (died in), "location" (the respawn location written), "report"} ({} before any).
var last_death_commit: Dictionary = {}

var transition_log: Array[TransitionRecord] = []
## The trail under the player (RegionMonitor, ten times a second): its link id and the map at its other end, or ""
## off trails. Read trail_destination for the HUD; trail_changed announces changes.
var trail_link_id: String = ""
var trail_destination: String = ""
var cache: MapStateCache = MapStateCache.new()
## The live instance of current_map (pure state; the world's MapInstanceView shows it).
var instance_state: MapInstanceState = null
var last_error: String = ""

var _arriving_frames: int = 0
var _replaced: bool = false
## The committed record of the transition in flight (set at the swap, cleared when IDLE is reached).
var _pending: TransitionRecord = null
var _location_timer: float = 0.0
## Bumped when a warp starts or is aborted; a fading coroutine whose number is stale stops after its await.
var _transition_seq: int = 0
## The state a transition started from (BOOT, IDLE or DEAD); restored when a warp is dropped before its swap.
var _start_state: State = State.BOOT
## Game replaced the character while a transition was in flight: its {location, respawn_reference}, loaded once the
## session is IDLE again ({} when nothing is queued).
var _load_after_transition: Dictionary = {}
## Events.player_died arrived while a transition was in flight: DEAD is entered when it completes.
var _death_pending: bool = false
## This death's loss was committed (death_commit ran); cleared whenever DEAD is left.
var _death_committed: bool = false


func _ready() -> void:
	process_physics_priority = PHYSICS_PRIORITY
	var ev := _autoload("Events")
	if ev != null and ev.has_signal("player_died"):
		ev.connect("player_died", _on_player_died)
	var game := _autoload("Game")
	if game != null and game.has_signal("character_replaced"):
		game.connect("character_replaced", _on_character_replaced)
	_register_debug_commands()


# --- setup ------------------------------------------------------------------------------------------------------

## The map definitions in use (built on first use from Data.db and, when present, the Blender export).
func get_defs() -> MapDefinitions:
	if defs == null:
		var side: WorldSidecars = WorldSidecars.load_dir() if WorldSidecars.exists() else null
		defs = MapDefinitions.build(_content(), side)
	return defs


## Called by IslandWorld once it is built: the world's grounded definitions become the session's.
func attach_world(w: Node) -> void:
	world = w
	if w != null and w.get("defs") is MapDefinitions:
		defs = w.get("defs")


## Called by IslandWorld when it leaves the tree (the game shell's quit to title frees the whole session). A warp
## in flight cannot finish its fades or its grounding wait without the world, so it is settled first: a committed
## swap completes (state IDLE, events already sent), an uncommitted one is dropped. Then reset(): the session is
## back in BOOT, so the next GameSession.start enters through start_new_game() / load_character() exactly like the
## first one, and nothing of the previous session (cached instances, drops, map_left of the old map) leaks into it.
func detach_world(w: Node) -> void:
	if world != w:
		return
	world = null
	if state in [State.WARP_OUT, State.SWAP, State.WARP_IN, State.ARRIVING]:
		_transition_seq += 1
		if _pending != null:
			push_warning("[MapSession] world detached during a transition to %s; completing it without the world" % _pending.to_map)
			_complete(_pending)
		else:
			push_warning("[MapSession] world detached before the swap; transition dropped")
			_set_state(_start_state)
	reset()


## Back to BOOT, as before the first map: no current_map, respawn_reference, last_arrival or last_transition, an
## empty transition log, no live instance and an empty instance cache (drops and dead slots of the last session are
## gone), nothing pending (load, death, commit) and a warp in flight abandoned (its coroutine stops at its next
## await). Collaborators stay: defs, world, camera, character, content, clock, rng, autosave_enabled, death_rules and
## death_commit (their owners attach and detach them). A world still attached hands its monsters back first.
## Emits state_changed (when not already BOOT) and session_reset. Saves are not touched: save first.
func reset() -> void:
	_transition_seq += 1
	if world != null:
		world.call("release_instance")
	current_map = ""
	respawn_reference = ""
	last_arrival = null
	last_transition = null
	transition_log.clear()
	cache.clear()
	instance_state = null
	last_error = ""
	last_death_commit = {}
	_pending = null
	_arriving_frames = 0
	_replaced = false
	_location_timer = 0.0
	_start_state = State.BOOT
	_load_after_transition = {}
	_death_pending = false
	_death_committed = false
	set_trail("", "")
	_set_state(State.BOOT)
	session_reset.emit()


## Registers the camera rig (duck-typed set_bounds(bounds, ortho_size, blend_s) and snap()).
func attach_camera(cam: Object) -> void:
	camera = cam
	if cam != null and current_map != "":
		_apply_camera(get_defs().get_def(current_map), false)


## Re-applies the current map's camera bounds without a blend (the world calls it when a link mode change alters
## them: a trail in edge mode widens them).
func refresh_camera() -> void:
	if current_map != "":
		_apply_camera(get_defs().get_def(current_map), false)


## The trail under the player changed (RegionMonitor): `link_id` and the map at its other end (`dest_map_id`), or
## both "" off trails. Emits trail_changed(dest_map_id) when the destination changes.
func set_trail(link_id: String, dest_map_id: String) -> void:
	trail_link_id = link_id
	if dest_map_id == trail_destination:
		return
	trail_destination = dest_map_id
	trail_changed.emit(dest_map_id)


func is_idle() -> bool:
	return state == State.IDLE


func state_name() -> String:
	return State.keys()[state]


# --- transitions ------------------------------------------------------------------------------------------------

## The only way current_map changes (§4.5). Returns OK when the transition was accepted (it may still be fading);
## await transition_finished for completion. Rejections return an error, log, and change nothing.
func transition(req: TransitionRequest) -> Error:
	var why := _guard(req)
	if why != "":
		return _reject(why, ERR_UNAVAILABLE)
	var res := ArrivalResolver.resolve(req, get_defs())
	if not bool(res.ok):
		return _reject(String(res.error), ERR_CANT_RESOLVE)
	_transition_seq += 1
	_start_state = state
	transition_started.emit(req)
	if req.via == VIA_GATE:
		_set_state(State.SWAP)
		var rec := _swap(req, res)
		_complete(rec)
		return OK
	if _can_animate():
		_run_warp(req, res)
	else:
		_run_warp_now(req, res)
	return OK


## Press Up / interact on a portal of the current map (§4.4).
func request_portal(portal: PortalDef) -> Error:
	if portal == null:
		return _reject("no portal", ERR_INVALID_PARAMETER)
	if not portal.accepts_press():
		return _reject("%s cannot be entered by pressing Up (%s)" % [portal.key(), portal.interaction_type], ERR_UNAVAILABLE)
	var via := VIA_DOOR if portal.portal_type == PortalDef.TYPE_DOOR else VIA_PRESS_UP
	return transition(TransitionRequest.make(portal.destination_map_id, get_defs().arrival_for(portal), via, portal))


## Teleport to a map's player_spawns[0], or to a portal's arrival when portal_id is given (§4.14).
func debug_warp(map_id: String, portal_id: String = "") -> Error:
	var d := get_defs()
	if not d.has_map(map_id):
		return _reject("debug_warp: unknown map %s" % map_id, ERR_DOES_NOT_EXIST)
	if portal_id != "" and d.portal(map_id, portal_id) == null:
		return _reject("debug_warp: unknown portal %s.%s" % [map_id, portal_id], ERR_DOES_NOT_EXIST)
	var arrival := ArrivalRef.at_portal(map_id, portal_id) if portal_id != "" else ArrivalRef.at_spawn(map_id, 0)
	return transition(TransitionRequest.make(map_id, arrival, VIA_DEBUG))


## Saving is allowed in IDLE with the player alive and a valid SafeGround point (§4.9), and in DEAD once the death
## is committed (death_commit): the save then stores the respawn location with the post-death character.
func can_save() -> bool:
	if state == State.DEAD:
		return _death_committed and current_map != ""
	if state != State.IDLE or current_map == "":
		return false
	if world != null and bool(world.call("has_player")):
		return bool((world.call("safe_point") as Dictionary).get("ok", false))
	return true


# --- death and respawn (§4.8) -----------------------------------------------------------------------------------

## HP reached 0: DEAD, input off, the death commit (when death_commit is set), Events.player_died(current_map). The
## death UI then calls respawn(). During a warp the death is announced at once and DEAD (with its commit) is entered
## when the warp completes (same as a death that arrives through Events.player_died).
func enter_dead() -> Error:
	if state in [State.WARP_OUT, State.SWAP, State.WARP_IN, State.ARRIVING]:
		_death_pending = true
		var evt := _autoload("Events")
		if evt != null:
			evt.emit_signal("player_died", current_map)
		return OK
	if state != State.IDLE:
		return _reject("enter_dead: not idle (%s)" % state_name(), ERR_BUSY)
	_enter_dead_state()
	var ev := _autoload("Events")
	if ev != null:
		ev.emit_signal("player_died", current_map)
	return OK


## Respawn at returnMap player_spawns[respawn spawn index] (via respawn). Applies the death_rules hook first, unless
## death_commit already took this death's loss.
func respawn() -> Error:
	if state != State.DEAD:
		return _reject("respawn: not dead (%s)" % state_name(), ERR_UNAVAILABLE)
	if death_rules.is_valid() and not _death_committed:
		death_rules.call(_character())
	var def := get_defs().get_def(current_map)
	var to := def.respawn_location.map_id if def != null else current_map
	var idx := def.respawn_location.spawn_index if def != null else 0
	return transition(TransitionRequest.make(to, ArrivalRef.at_spawn(to, idx), VIA_RESPAWN))


## Applies the death_commit hook to the live character now, once per death (MapSession calls it itself when it
## enters DEAD; call it only if the hook was installed after the death). Then the character's location becomes
## respawn_location(), death_committed is emitted and an autosave is requested. Errors: ERR_UNAVAILABLE (not DEAD),
## ERR_ALREADY_EXISTS (this death is committed), ERR_UNCONFIGURED (no death_commit hook).
func commit_death() -> Error:
	if state != State.DEAD:
		return ERR_UNAVAILABLE
	if _death_committed:
		return ERR_ALREADY_EXISTS
	if not death_commit.is_valid():
		return ERR_UNCONFIGURED
	var c := _character()
	var report: Variant = death_commit.call(c) if c != null else null
	_death_committed = true
	var loc := capture_location()
	last_death_commit = {"map_id": current_map, "location": loc.duplicate(true), "report": report}
	death_committed.emit(current_map, report)
	_request_autosave()
	return OK


## True while DEAD with this death's loss committed (saving is allowed and stores the respawn location).
func is_death_committed() -> bool:
	return state == State.DEAD and _death_committed


## The save location a respawn from `map_id` (default current_map) arrives at: {"map_id": the canonical returnMap,
## "entry": {"map_id", "spawn_index": death.json respawn_player_spawn_index}}, without a resume point (a load lands
## on that player spawn). {} for an unknown map. respawn() travels to the same point.
func respawn_location(map_id: String = "") -> Dictionary:
	var def := get_defs().get_def(map_id if map_id != "" else current_map)
	if def == null or def.respawn_location == null:
		return {}
	var to := def.respawn_location.map_id
	return {"map_id": to, "entry": ArrivalRef.at_spawn(to, def.respawn_location.spawn_index).to_dict()}


## The respawn_reference a save at `map_id` carries: that map's canonical returnMap ("" for an unknown map).
func respawn_reference_of(map_id: String) -> String:
	var def := get_defs().get_def(map_id)
	return def.respawn_location.map_id if def != null and def.respawn_location != null else ""


## DEAD, input off, and the death commit when the hook is installed (every path into DEAD goes through here).
func _enter_dead_state() -> void:
	_set_state(State.DEAD)
	_player_input(false)
	if death_commit.is_valid() and not _death_committed:
		commit_death()


func _on_player_died(_map_id: String) -> void:
	# Someone else (the player/combat system) announced the death: enter DEAD without re-emitting.
	if state == State.IDLE:
		_enter_dead_state()
	elif state in [State.WARP_OUT, State.SWAP, State.WARP_IN, State.ARRIVING]:
		# Died while a warp was in flight (a hit landed during the fade): enter DEAD once it completes, or the
		# controller would be dead while the session sits in IDLE and refuses respawn().
		_death_pending = true


# --- loading (§4.9) ---------------------------------------------------------------------------------------------

## Enters the world at a saved location through the fallback chain: resume -> entry -> player_spawns[0] -> the
## fallback map (presentation.json session.fallback_map_id). `saved_respawn` is the save's respawn_reference;
## canonical returnMap wins on a mismatch (logged).
func enter_from_location(location: Dictionary, saved_respawn: String = "") -> Error:
	var d := get_defs()
	var fallback := d.tuning.text("session", "fallback_map_id")
	var res := ArrivalResolver.resolve_load(location, d, _resume_validator(), fallback)
	for e in res.errors:
		if String(res.step) == ArrivalResolver.STEP_FALLBACK_MAP:
			push_error("[MapSession] " + e)
		else:
			push_warning("[MapSession] " + e)
	if not bool(res.ok):
		return _reject("load: no arrival in %s" % String(res.map_id), ERR_CANT_RESOLVE)
	var expected := d.get_def(String(res.map_id)).respawn_location.map_id
	if saved_respawn != "" and saved_respawn != expected:
		push_warning("[MapSession] saved respawn_reference %s differs from canonical returnMap %s of %s; using canonical" % [
			saved_respawn, expected, String(res.map_id)])
	var req := TransitionRequest.make_xform(String(res.map_id), res.xform, res.arrival, VIA_LOAD)
	req.load_step = String(res.step)
	return transition(req)


## New game: data/misostory/new_character.json start_location (falls back to session.fallback_map_id sp 0).
func start_new_game() -> Error:
	var nc: Variant = _content().miso_table("new_character")
	var start: Dictionary = (nc as Dictionary).get("start_location", {}) if nc is Dictionary else {}
	var m := String(start.get("map_id", get_defs().tuning.text("session", "fallback_map_id")))
	var i := int(start.get("spawn_index", 0))
	return enter_from_location({"map_id": m, "entry": {"map_id": m, "spawn_index": i}})


## Enters the world where a (loaded) character's location says.
func load_character(c: CharacterState) -> Error:
	return enter_from_location(c.location, c.respawn_reference)


## Game.character_replaced (new game, load, reset during play): the live character changed, so the session enters
## the world where the NEW character's location says (via load), before the location refresh can overwrite that
## location with the old map's. A transition in flight finishes first and the load follows it. In BOOT nothing
## happens: the main scene starts the session itself (start_new_game() / load_character()).
func _on_character_replaced(_reason: String = "") -> void:
	if state == State.BOOT:
		return
	var c := _character()
	if c == null:
		return
	if state in [State.IDLE, State.DEAD]:
		_load_after_transition = {}
		load_character(c)
	else:
		# Copied now: the in-flight swap writes its own location into the (new) character before the load runs.
		_load_after_transition = {"location": c.location.duplicate(true), "respawn_reference": c.respawn_reference}


# --- the location model (§4.9) ----------------------------------------------------------------------------------

## The save location {map_id, entry, resume?}. resume comes from SafeGround (never the live position) in map-local
## coordinates. Also written into the character (location, respawn_reference). While DEAD with the death committed
## it is respawn_location() instead (the town the player will wake up in, no resume point).
func capture_location() -> Dictionary:
	if current_map == "":
		return {}
	if state == State.DEAD and _death_committed:
		var town := respawn_location(current_map)
		var ch := _character()
		if ch != null and not town.is_empty():
			ch.location = town.duplicate(true)
			ch.respawn_reference = respawn_reference_of(String(town.map_id))
		return town
	var entry := last_arrival if last_arrival != null else ArrivalRef.at_spawn(current_map, 0)
	var loc := {"map_id": current_map, "entry": entry.to_dict()}
	var def := get_defs().get_def(current_map)
	if world != null and def != null:
		var sp: Dictionary = world.call("safe_point")
		var pos: Vector3 = sp.get("position", Vector3.ZERO)
		var region: RegionIndex = world.get("region_index")
		var r: Dictionary = region.region_of(pos, current_map) if region != null else {}
		var in_map := String(r.get("kind", "")) == RegionIndex.KIND_MAP and String(r.get("id", "")) == current_map
		# On a trail (section 4.9): no resume point, and the entry becomes current_map's portal at that trail.
		if bool(sp.get("ok", false)) and String(r.get("kind", "")) == RegionIndex.KIND_TRAIL:
			var t := get_defs().trail(String(r.get("id", "")))
			var key := t.portal_key_of(current_map) if t != null else ""
			var p: PortalDef = get_defs().graph.portals.get(key, null)
			if p != null and p.is_canonical():
				loc["entry"] = ArrivalRef.at_portal(current_map, p.portal_id).to_dict()
		if bool(sp.get("ok", false)) and in_map:
			var local := def.to_local(pos)
			# Facing is stored in the map frame too, so a layout move or yaw change keeps the save valid (§4.9).
			var f: Vector3 = def.frame.basis.inverse() * (sp.get("facing", Vector3.BACK) as Vector3)
			loc["resume"] = {"local_pos": [local.x, local.y, local.z], "facing_deg": rad_to_deg(atan2(f.x, f.z)),
				"map_content_hash": def.content_hash}
	var c := _character()
	if c != null:
		c.location = loc.duplicate(true)
		c.respawn_reference = respawn_reference
	return loc


## The "world" block for SaveService (it calls this when present). While DEAD with the death committed: the respawn
## location and that map's own respawn reference.
func save_world() -> Dictionary:
	var loc := capture_location()
	var ref := respawn_reference
	if state == State.DEAD and _death_committed and not loc.is_empty():
		ref = respawn_reference_of(String(loc.map_id))
	return {"location": loc, "respawn_reference": ref}


# --- debug ------------------------------------------------------------------------------------------------------

## Overlay data: current map, region, state, last transition, instance counts.
func debug_info() -> Dictionary:
	var d := get_defs()
	var def := d.get_def(current_map)
	var info := {
		"current_map": current_map,
		"map_name": def.map_name if def != null else "",
		"state": state_name(),
		"respawn_reference": respawn_reference,
		"last_arrival": last_arrival.to_dict() if last_arrival != null else {},
		"last_transition": last_transition.to_dict() if last_transition != null else {},
		"link_mode": d.tuning.forced_link_mode() if d.tuning.forced_link_mode() != "" else JSON.stringify(d.graph.mode_counts()),
		"trail": trail_destination,
		"capacity": instance_state.capacity if instance_state != null else 0,
		"alive_slots": instance_state.alive_count() if instance_state != null else 0,
		"cached_maps": cache.keys(),
		"death_committed": is_death_committed(),
		"region": {},
	}
	if world != null:
		var w: Dictionary = world.call("debug_info")
		info["region"] = w.get("region", {})
		info["live_monsters"] = w.get("live_monsters", 0)
		info["position"] = w.get("position", Vector3.ZERO)
	return info


## Reload map (§4.14): release the instance, fresh state, realize again. The player stays where it is.
func reload_map() -> Error:
	if state != State.IDLE or current_map == "":
		return ERR_UNAVAILABLE
	var def := get_defs().get_def(current_map)
	if world != null:
		world.call("release_instance")
	instance_state = MapInstanceState.fresh(def, get_defs().spawn_model, _new_rng(), _now())
	if world != null:
		var pos: Vector3 = (world.get("player") as Node3D).global_position if world.get("player") != null else def.player_spawn(0).origin
		world.call("activate_map", def, instance_state, last_arrival, Transform3D(Basis.IDENTITY, pos))
	return OK


## Reports a killed monster node (it carries spawn_slot metadata from MapInstanceView).
func report_monster_killed(node: Node) -> bool:
	if world == null:
		return false
	var view: Node = world.get("instance_view")
	return view != null and bool(view.call("notify_node_killed", node))


# --- the transition machinery -----------------------------------------------------------------------------------

func _guard(req: TransitionRequest) -> String:
	if req == null:
		return "no request"
	var d := get_defs()
	match req.via:
		VIA_RESPAWN:
			if state != State.DEAD:
				return "respawn needs DEAD, state is %s" % state_name()
		VIA_LOAD:
			if not (state in [State.BOOT, State.IDLE, State.DEAD]):
				return "busy (%s)" % state_name()
		VIA_DEBUG:
			if not (state in [State.BOOT, State.IDLE]):
				return "busy (%s)" % state_name()
		VIA_GATE, VIA_PRESS_UP, VIA_DOOR:
			if state != State.IDLE:
				return "busy (%s)" % state_name()
		_:
			return "unknown via '%s'" % req.via
	if not d.has_map(req.to_map):
		return "unknown map %s" % req.to_map
	if req.via in PORTAL_VIAS:
		if current_map == "":
			return "no current map"
		if req.source_portal == null or req.source_portal.source_map_id != current_map:
			return "portal is not in %s" % current_map
		if not d.graph.has_direction(current_map, req.to_map):
			return "no link %s -> %s" % [current_map, req.to_map]
		# The portal decides where it leads (MeowDB toMapId + PortalGraph resolution); a request cannot redirect it.
		if req.source_portal.destination_map_id != req.to_map:
			return "%s leads to %s, not %s" % [req.source_portal.key(), req.source_portal.destination_map_id, req.to_map]
		if not req.has_xform and not d.arrival_for(req.source_portal).equals(req.arrival):
			return "%s arrives at %s, not %s" % [req.source_portal.key(), d.arrival_for(req.source_portal), req.arrival]
	return ""


func _can_animate() -> bool:
	return world != null and world.get("fader") != null and (world.get("fader") as Node).is_inside_tree() \
		and bool(world.call("has_player"))


func _run_warp(req: TransitionRequest, res: Dictionary) -> void:
	var seq := _transition_seq
	var tuning := get_defs().tuning
	var fader: ScreenFader = world.get("fader")
	_player_input(false)
	world.call("freeze_player", true)
	if state == State.BOOT:
		fader.set_black(true)
	else:
		_set_state(State.WARP_OUT)
		await fader.fade_out(tuning.num("transition", "fade_out_s"))
		if seq != _transition_seq:
			return  # aborted while fading out (detach_world)
	_set_state(State.SWAP)
	var rec := _swap(req, res)
	_pending = rec
	_set_state(State.WARP_IN)
	if world != null and is_instance_valid(fader) and fader.is_inside_tree():
		await fader.fade_in(tuning.num("transition", "fade_in_s"))
	if seq != _transition_seq:
		return  # aborted while fading in (detach_world completed the record)
	_begin_arriving(rec)


func _run_warp_now(req: TransitionRequest, res: Dictionary) -> void:
	_player_input(false)
	if world != null:
		world.call("freeze_player", true)
	_set_state(State.WARP_OUT)
	_set_state(State.SWAP)
	var rec := _swap(req, res)
	_pending = rec
	_set_state(State.WARP_IN)
	_begin_arriving(rec)


func _begin_arriving(rec: TransitionRecord) -> void:
	_set_state(State.ARRIVING)
	_pending = rec
	_arriving_frames = 0
	_replaced = false
	if world == null or not bool(world.call("has_player")):
		_complete(rec)
		return
	world.call("freeze_player", false)


func _physics_process(delta: float) -> void:
	if state == State.ARRIVING and _pending != null:
		if world == null or not bool(world.call("has_player")):
			_complete(_pending)  # the world or the player went away while arriving
			return
		_arriving_frames += 1
		if bool(world.call("player_on_floor")):
			_pending.frames_to_ground = _arriving_frames
			var limit := get_defs().tuning.count("transition", "arrive_grounded_frames")
			if _arriving_frames > limit:
				push_warning("[MapSession] grounded %d frames after arriving in %s (budget %d)" % [_arriving_frames, current_map, limit])
			_complete(_pending)
		elif _arriving_frames >= get_defs().tuning.count("transition", "arrive_replace_frames"):
			var def := get_defs().get_def(current_map)
			if not _replaced:
				push_error("[MapSession] player not on the floor %d frames after arriving in %s at %s; re-placing at player_spawns[0]" % [
					_arriving_frames, current_map, _pending.arrival_xform.origin])
				_replaced = true
				_pending.replaced = true
				_arriving_frames = 0
				world.call("place_player", def.player_spawn(0))
			else:
				push_error("[MapSession] player still not on the floor in %s; giving control back" % current_map)
				_pending.frames_to_ground = -1
				_complete(_pending)
	elif state == State.IDLE and world != null and current_map != "":
		_location_timer += delta
		if _location_timer >= get_defs().tuning.num("session", "location_refresh_s"):
			_location_timer = 0.0
			capture_location()


func _swap(req: TransitionRequest, res: Dictionary) -> TransitionRecord:
	var d := get_defs()
	var old := current_map
	var def := d.get_def(req.to_map)
	var ev := _autoload("Events")
	var now := _now()
	if old != "" and ev != null:
		ev.emit_signal("map_left", old)
	# Release the old instance into the cache. A load (a save file, Continue, a new game) starts the world the way the
	# file describes it, and monsters, ground drops and Wooden Boxes are never saved (contract C3): nothing of the
	# instances before it survives. The old map is not parked and every parked map is forgotten, else a pause-menu
	# load into the same map took back the snapshot it had just parked (broken boxes still broken).
	var loading := req.via == VIA_LOAD
	if world != null:
		world.call("release_instance")
	if instance_state != null and old != "" and not loading:
		cache.put(old, instance_state.snapshot(now))
	if loading:
		cache.clear()
	instance_state = null
	current_map = req.to_map
	respawn_reference = def.respawn_location.map_id
	last_arrival = (res.arrival as ArrivalRef).duplicate_ref()
	# Activate the new instance: restored from the cache (fast-forwarded) or fresh.
	var snap := cache.take(current_map)
	if not snap.is_empty():
		instance_state = MapInstanceState.from_snapshot(snap, d.spawn_model, now)
	else:
		instance_state = MapInstanceState.fresh(def, d.spawn_model, _new_rng(), now)
	var xform: Transform3D = res.xform
	var warp := req.via != VIA_GATE
	set_trail("", "")
	if world != null:
		# A gate commit leaves the player where it walked: monsters realize nearest-first from there.
		var anchor := xform
		if not warp and bool(world.call("has_player")):
			anchor = Transform3D(xform.basis, (world.get("player") as Node3D).global_position)
		world.call("activate_map", def, instance_state, last_arrival, anchor)
		if warp:
			world.call("place_player", xform)
		world.call("apply_environment", def, 0.0 if warp else d.tuning.num("transition", "environment_blend_s"))
	_apply_camera(def, not warp)
	if ev != null:
		ev.emit_signal("map_entered", current_map, old)
		if req.via in PORTAL_VIAS:
			ev.emit_signal("portal_used", old, req.source_portal_id(), current_map)
	var rec := TransitionRecord.new()
	rec.from_map = old
	rec.to_map = current_map
	rec.via = req.via
	rec.portal_id = req.source_portal_id()
	rec.arrival = last_arrival.duplicate_ref()
	rec.t_game = now
	rec.arrival_xform = xform if warp else Transform3D.IDENTITY
	rec.load_step = req.load_step
	last_transition = rec
	transition_log.append(rec)
	while transition_log.size() > TRANSITION_LOG_SIZE:
		transition_log.remove_at(0)
	capture_location()
	return rec


func _complete(rec: TransitionRecord) -> void:
	_pending = null
	# A gate commit never took the input (the player walked in); whoever else turned it off keeps it off.
	if rec.via != VIA_GATE:
		_player_input(true)
	_set_state(State.IDLE)
	# A respawn ends DEAD; so does a load started from DEAD (a death screen's "load"): the player is alive again.
	if rec.via == VIA_RESPAWN or (rec.via == VIA_LOAD and _start_state == State.DEAD):
		var ev := _autoload("Events")
		if ev != null:
			ev.emit_signal("player_respawned", current_map)
	capture_location()
	_request_autosave()
	transition_finished.emit(rec)
	if not _load_after_transition.is_empty():
		_death_pending = false  # the replaced character is not the one that died
		var queued := _load_after_transition
		_load_after_transition = {}
		enter_from_location(queued.location, String(queued.respawn_reference))
	elif _death_pending:
		_death_pending = false
		if rec.via != VIA_RESPAWN and state == State.IDLE:
			_enter_dead_state()


func _request_autosave() -> void:
	if not autosave_enabled:
		return
	var saves := _autoload("Saves")
	if saves != null and saves.has_method("request_autosave"):
		saves.call("request_autosave")


func _apply_camera(def: MapDefinition, gate: bool) -> void:
	if camera == null or def == null:
		return
	var blend := get_defs().tuning.num("transition", "gate_blend_s") if gate else 0.0
	if camera.has_method("set_bounds"):
		camera.call("set_bounds", def.camera_bounds, def.ortho_size, blend)
	if not gate and camera.has_method("snap"):
		camera.call("snap")


func _set_state(s: State) -> void:
	if s == state:
		return
	var old := state
	state = s
	if old == State.DEAD:
		_death_committed = false  # a respawn or a load ends this death; the next one commits again
	state_changed.emit(s, old)


func _reject(why: String, err: Error) -> Error:
	last_error = why
	push_warning("[MapSession] transition rejected: " + why)
	transition_rejected.emit(why)
	return err


func _player_input(on: bool) -> void:
	if world != null:
		world.call("set_player_input", on)


func _resume_validator() -> Callable:
	if world != null and world.has_method("validate_resume"):
		return Callable(world, "validate_resume")
	return Callable()


func _new_rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	if rng != null:
		r.seed = rng.randi()
	else:
		var game := _autoload("Game")
		var grng: Variant = game.get("rng") if game != null else null
		r.seed = (grng as RandomNumberGenerator).randi() if grng is RandomNumberGenerator else 0
	return r


func _now() -> float:
	if clock_provider.is_valid():
		return float(clock_provider.call())
	var game := _autoload("Game")
	return float(game.get("clock")) if game != null and game.get("clock") != null else 0.0


func _character() -> CharacterState:
	if character != null:
		return character
	var game := _autoload("Game")
	var c: Variant = game.get("character") if game != null else null
	return c if c is CharacterState else null


func _content() -> ContentDB:
	if content != null:
		return content
	var data := _autoload("Data")
	var db: Variant = data.get("db") if data != null else null
	if db is ContentDB:
		return db
	content = ContentDB.new().load_all()
	return content


static func _autoload(autoload_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(autoload_name) if tree != null else null


func _register_debug_commands() -> void:
	var dbg := _autoload("Debug")
	if dbg == null or not dbg.has_method("register_command"):
		return
	dbg.call("register_command", "map_warp", "map_warp <map_id> [portal]: warp to a map's player_spawns[0] or to a portal's arrival", _cmd_warp)
	dbg.call("register_command", "map_info", "map_info: current map, region, state, last transition", _cmd_info)
	dbg.call("register_command", "map_link_mode", "map_link_mode <link_id|all> <warp|edge>: switch link modes (doors are always warp)", _cmd_link_mode)
	dbg.call("register_command", "map_reload", "map_reload: fresh monsters for the current map", _cmd_reload)


func _cmd_warp(args: Array) -> String:
	if args.is_empty():
		return "usage: map_warp <map_id> [portal]"
	var err := debug_warp(String(args[0]), String(args[1]) if args.size() > 1 else "")
	return "ok" if err == OK else "failed: %s" % last_error


func _cmd_info(_args: Array) -> String:
	return JSON.stringify(debug_info(), "  ", false)


func _cmd_link_mode(args: Array) -> String:
	if args.size() < 2:
		return "usage: map_link_mode <link_id|all> <warp|edge>"
	var err := get_defs().graph.set_link_mode(String(args[0]), String(args[1]))
	if err == ERR_UNAVAILABLE:
		return "failed: %s is a door link; doors are always warp" % String(args[0])
	return "ok" if err == OK else "failed: %s" % error_string(err)


func _cmd_reload(_args: Array) -> String:
	return "ok" if reload_map() == OK else "failed"
