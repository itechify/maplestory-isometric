class_name PlaytestWalker
extends RefCounted
## Walks the real player along planned paths with real input (docs/runtime/PLAYTEST_HARNESS.md "Walking").
##
## Planning is the traversal bot's (MAP_ARCHITECTURE.md section 4.13): TraversalNav over the current map's exported
## routes (Dijkstra; both ends attached by a straight stretch), TraversalPaths.resample and with_clearance (stretches
## blocked by a prop are replanned on a grid around it, on the real collision). Steering is RouteBot's pure pursuit
## (jumps at rises, ladders on climb segments, stall and timeout detection) writing into a scratch BotInput; every
## tick the walker turns that intent into real input through PlaytestInput:
##   world_dir    move_* action strengths (InputEventAction) that KeyboardInput maps back onto exactly that direction
##   jump         the jump key (Space) down for the tick RouteBot taps it
##   climb +1/-1  Up / Down arrows held (portal_enter / climb_down: the classic ladder keys)
##   grab taps    Up / Down taps at a ladder's foot or top
## The player keeps its KeyboardInput, so a modal window, a warp or knockback stops the walk exactly as it stops a
## player; the walk then reports the stall.
##
## The loop runs on process frames (input is sent outside physics; see PlaytestInput) and decides once per physics
## tick that ran since the last frame (exactly one under --fixed-fps 60).

const PATH_STEP_M := 0.5
const DEFAULT_CLEARANCE_M := 2.0
## How far below / above a target point the walker looks for ground to stand on (m).
const GROUND_PROBE_UP_M := 1.0
const GROUND_PROBE_DOWN_M := 4.0
## Frames of a straight nudge into a portal trigger after a walk stopped short of it.
const NUDGE_FRAMES := 60
const TAP_ACTIONS: Array[StringName] = [&"jump", &"portal_enter", &"climb_down"]

var driver: Node = null
var _navs: Dictionary = {}
var _keys_down: Dictionary = {}


func _init(p_driver: Node) -> void:
	driver = p_driver


func _input() -> PlaytestInput:
	return driver.get("input") as PlaytestInput


func _world() -> IslandWorld:
	return driver.call("world") as IslandWorld


func _session() -> Node:
	return driver.call("session") as Node


func _player() -> PlayerController:
	return driver.call("player") as PlayerController


func _tree() -> SceneTree:
	return driver.get_tree()


## The route graph of `map_id` (cached; rebuilt when the world is a new one).
func nav(map_id: String) -> TraversalNav:
	var w := _world()
	var key := "%s#%d" % [map_id, w.get_instance_id() if w != null else 0]
	if not _navs.has(key):
		_navs[key] = TraversalNav.build(w.defs.get_def(map_id))
	return _navs[key]


## A point the feet can stand on at (x, z) near height `p.y`: the first floor (PlaytestGridNav's: walkable ground or a
## flat prop top) from GROUND_PROBE_UP_M above down to GROUND_PROBE_DOWN_M below; `p` itself when there is none.
func grounded(p: Vector3) -> Vector3:
	var w := _world()
	if w == null or w.ground_query == null or w.ground_query.space == null:
		return p
	var ray := PhysicsRayQueryParameters3D.create(p + Vector3.UP * GROUND_PROBE_UP_M, p - Vector3.UP * GROUND_PROBE_DOWN_M,
		PlaytestGridNav.FLOOR_MASK, w.ground_query.exclude)
	var hit := w.ground_query.space.intersect_ray(ray)
	return Vector3(p.x, (hit["position"] as Vector3).y, p.z) if not hit.is_empty() else p


## True when the body fits standing at `feet` (the planning capsule clear of blocking and containment collision).
func standable(feet: Vector3) -> bool:
	var w := _world()
	return w != null and w.ground_query != null and w.ground_query.is_clear(feet + Vector3.UP * TraversalPaths.LIFT_M,
		TraversalPaths.PLAN_RADIUS_M, TraversalPaths.HEIGHT_M)


## A path in the current map from the player to `to`: {"path", "how", "props" (grid cells on prop tops)}. In order:
##   routes        the map's exported routes (TraversalNav: ladders, ropes, the validated walkways)
##   grid          PlaytestGridNav on the real collision (off the route network: terraces, field edges)
##   routes+grid   the routes to the route point nearest the goal, then the grid
##   grid+routes   the grid to the route point nearest the player, then the routes
##   straight      a straight line (the walk then reports where it stalled)
## `planner`: "auto" (the order above), "grid_first" (walk_to's re-plan after a stall on the routes), "grid" or
## "routes" (that planner only, else straight).
func plan(to: Vector3, planner: String = "auto") -> Dictionary:
	var p := _player()
	var from := p.global_position
	var n := nav(String(_session().get("current_map")))
	var w := _world()
	var straight := {"path": PackedVector3Array([from, to]), "how": "straight"}
	var grid_first := planner in ["grid_first", "grid"]
	if grid_first:
		var g0 := PlaytestGridNav.search(w, p.model, from, to)
		if not (g0["path"] as PackedVector3Array).is_empty():
			return {"path": g0["path"], "how": "grid", "props": int(g0["props"])}
		if planner == "grid":
			return straight
	var path := n.path(from, to)
	if not path.is_empty():
		return {"path": path, "how": "routes" if path.size() > 2 else "straight"}
	if planner == "routes":
		return straight
	var g := PlaytestGridNav.search(w, p.model, from, to) if not grid_first else {"path": PackedVector3Array()}
	if not (g["path"] as PackedVector3Array).is_empty():
		return {"path": g["path"], "how": "grid", "props": int(g["props"])}
	var near_goal := _nearest_route_point(n, to)
	if near_goal != Vector3.INF:
		var a := n.path(from, near_goal)
		var gb := PlaytestGridNav.search(w, p.model, near_goal, to) if not a.is_empty() else {"path": PackedVector3Array()}
		var b: PackedVector3Array = gb["path"]
		if not b.is_empty():
			a.append_array(b.slice(1))
			return {"path": a, "how": "routes+grid", "props": int(gb["props"])}
	var near_start := _nearest_route_point(n, from)
	if near_start != Vector3.INF:
		var gc := PlaytestGridNav.search(w, p.model, from, near_start)
		var c: PackedVector3Array = gc["path"]
		var e := n.path(near_start, to) if not c.is_empty() else PackedVector3Array()
		if not e.is_empty():
			c.append_array(e.slice(1))
			return {"path": c, "how": "grid+routes", "props": int(gc["props"])}
	return {"path": PackedVector3Array([from, to]), "how": "straight"}


## The route point closest to `p` (horizontal distance, height counted twice), or Vector3.INF without routes.
func _nearest_route_point(n: TraversalNav, p: Vector3) -> Vector3:
	var best := Vector3.INF
	var best_d := INF
	for q in n.points:
		var d := Vector2(q.x - p.x, q.z - p.z).length() + absf(q.y - p.y) * 2.0
		if d < best_d:
			best_d = d
			best = q
	return best


## Walks to `to` (world point) in the current map: plan, follow, and on a stall or timeout plan again once from where
## the player stands (the grid first when the routes stalled). opts: "retries" (1), "max_s", "stop_when" (Callable ->
## bool: end early, ok), "clearance_m", "within_m" (done once this close horizontally; default: RouteBot's own end
## rule), "planner" ("auto", "grid", "routes": see plan()). Returns follow()'s result plus "how" (see plan()), "props"
## (path cells on a prop's top rather than walkable ground) and "attempts".
func walk_to(to: Vector3, label: String, opts: Dictionary = {}) -> Dictionary:
	var retries := int(opts.get("retries", 1))
	var r := {}
	var attempts := 0
	var how := ""
	var props := 0
	var issues := PackedStringArray()
	var within := float(opts.get("within_m", -1.0))
	var p := _player()
	var stop: Callable = opts.get("stop_when", Callable())
	var o := opts.duplicate()
	if within > 0.0:
		o["stop_when"] = func() -> bool:
			var d := Vector2(to.x - p.global_position.x, to.z - p.global_position.z).length()
			return d <= within or (stop.is_valid() and bool(stop.call()))
	while attempts <= retries:
		attempts += 1
		# A re-plan after a stall on the routes (or a straight line) tries the grid first: the same plan would stall
		# at the same place.
		var planner := String(opts.get("planner", "auto"))
		if planner == "auto" and attempts > 1 and how in ["routes", "straight"]:
			planner = "grid_first"
		var pl := plan(to, planner)
		how = String(pl["how"])
		props = int(pl.get("props", 0))
		var oo := o.duplicate()
		if how == "grid" and not oo.has("clearance_m"):
			oo["clearance_m"] = 0.0  # the grid already kept the body clear
		r = await follow(pl["path"], "%s (try %d, %s)" % [label, attempts, how], oo)
		if bool(r["ok"]) or String(r["result"]) in ["ABORTED", "STOPPED"]:
			break
		issues.append_array(r["issues"])
	if not bool(r.get("ok", false)) and attempts > 1:
		r["issues"] = issues
	r["how"] = how
	r["props"] = props
	r["attempts"] = attempts
	return r


## Follows `path` (world points; the first is replaced by the player's position). opts: "clearance_m" (2.0; 0 skips
## the replanning around props), "allow_map_change" (false: a map change aborts), "max_s" (0: RouteBot's own budget),
## "stop_when" (Callable -> bool), "stall_s". Returns {"ok", "result" (DONE, STALLED, FELL, TIMEOUT, ABORTED,
## STOPPED), "time_s" (game), "distance_m", "issues", "report", "end", "recoveries", "violations", "gate_errors",
## "maps" (current_map after each change)}.
func follow(path: PackedVector3Array, label: String, opts: Dictionary = {}) -> Dictionary:
	var w := _world()
	var session := _session()
	var p := _player()
	var input := _input()
	var issues := PackedStringArray()
	var pts := PackedVector3Array([p.global_position])
	for k in range(1, path.size()):
		pts.append(path[k])
	if path.size() == 1:
		pts.append(path[0])
	pts = TraversalPaths.resample(pts, PATH_STEP_M)
	var clearance := float(opts.get("clearance_m", DEFAULT_CLEARANCE_M))
	if clearance > 0.0:
		var cl := TraversalPaths.with_clearance(w, pts, clearance)
		pts = cl["path"]
		if int(cl["blocked"]) > 0:
			issues.append("%d stretch(es) blocked by props could not be replanned" % int(cl["blocked"]))
	var rb := RouteBot.create(pts, p.climbables, p.model, label)
	if opts.has("stall_s"):
		rb.stall_time_s = float(opts["stall_s"])
	var bot := BotInput.new()
	var fell := func(_at: Vector3) -> void: rb.notify_fall()
	p.fell_out_of_world.connect(fell)
	var allow_change := bool(opts.get("allow_map_change", false))
	var max_s := float(opts.get("max_s", 0.0))
	var stop: Callable = opts.get("stop_when", Callable())
	var tps := float(Engine.physics_ticks_per_second)
	var map0 := String(session.get("current_map"))
	var maps := PackedStringArray()
	var f0 := Engine.get_physics_frames()
	var last_f := f0
	var rec0 := w.fall_recovery.recoveries
	var vio0 := w.region_monitor.violations
	var gerr0 := w.gate_monitor.errors.size()
	var dist := 0.0
	var last_pos := p.global_position
	var result := ""
	while true:
		await _tree().process_frame
		if not is_instance_valid(p) or not p.is_inside_tree():
			result = "ABORTED"
			issues.append("the player left the tree")
			break
		var now_f := Engine.get_physics_frames()
		var ticks := now_f - last_f
		if ticks <= 0:
			continue
		last_f = now_f
		dist += p.global_position.distance_to(last_pos)
		last_pos = p.global_position
		var cur := String(session.get("current_map"))
		if cur != (map0 if maps.is_empty() else maps[maps.size() - 1]):
			maps.append(cur)
			if not allow_change:
				result = "ABORTED"
				issues.append("the map changed during an in-map walk: %s -> %s" % [map0, cur])
				break
		if p.is_dead() or String(session.call("state_name")) == "DEAD":
			result = "ABORTED"
			issues.append("the player died")
			break
		if stop.is_valid() and bool(stop.call()):
			result = "STOPPED"
			break
		if max_s > 0.0 and (now_f - f0) / tps > max_s:
			result = "TIMEOUT"
			issues.append("no arrival within %.1f s (%s)" % [max_s, rb.report()])
			break
		if not bool(session.call("is_idle")):
			# A warp (or a gate's swap) is running: hold still, as a player would, and do not count it as a stall.
			_release(input)
			continue
		var res := rb.tick(p, bot, ticks / tps)
		if res != RouteBot.Result.RUNNING:
			result = String(RouteBot.Result.keys()[res])
			if res != RouteBot.Result.DONE:
				var why := ""
				var block := String(w.player_input_block())
				if block != "":
					why = " (player input blocked: %s)" % block
				elif p.in_hitstun:
					why = " (in knockback hit-stun)"
				issues.append(rb.report() + why)
			break
		bot.begin_tick()
		_apply(bot, p, input)
		input.reassert()
	_release(input)
	if p.fell_out_of_world.is_connected(fell):
		p.fell_out_of_world.disconnect(fell)
	await _tree().process_frame
	var rec := w.fall_recovery.recoveries - rec0 if is_instance_valid(w) else 0
	var vio := w.region_monitor.violations - vio0 if is_instance_valid(w) else 0
	var gerr := w.gate_monitor.errors.size() - gerr0 if is_instance_valid(w) else 0
	if rec > 0:
		issues.append("%d fall recoveries" % rec)
	if vio > 0:
		issues.append("%d region invariant violations" % vio)
	if gerr > 0:
		issues.append("gate errors: %s" % "; ".join(w.gate_monitor.errors.slice(gerr0)))
	var ok := result in ["DONE", "STOPPED"] and rec == 0 and vio == 0 and gerr == 0
	return {"ok": ok, "result": result, "time_s": snappedf((Engine.get_physics_frames() - f0) / tps, 0.001),
		"distance_m": snappedf(dist, 0.01), "issues": issues, "report": rb.report(), "end": p.global_position,
		"recoveries": rec, "violations": vio, "gate_errors": gerr, "maps": maps}


## Pushes straight at `target` (a portal anchor) until `inside` says the player is in, for at most NUDGE_FRAMES
## ticks. Returns whether it got there.
func nudge_until(target: Vector3, inside: Callable) -> bool:
	var p := _player()
	var input := _input()
	var start := Engine.get_physics_frames()
	while not bool(inside.call()) and Engine.get_physics_frames() - start < NUDGE_FRAMES:
		var d := Vector3(target.x - p.global_position.x, 0.0, target.z - p.global_position.z)
		input.set_move_world(d.normalized() if d.length() > 0.05 else Vector3.ZERO, p.view_right, p.view_forward)
		await _tree().process_frame
	input.release_movement()
	await _tree().physics_frame
	await _tree().process_frame
	return bool(inside.call())


## RouteBot's intent for this tick as real input: movement strengths, the jump / Up / Down keys.
func _apply(bot: BotInput, p: PlayerController, input: PlaytestInput) -> void:
	input.set_move_world(bot.world_dir, p.view_right, p.view_forward)
	var want := {}
	for a in TAP_ACTIONS:
		want[a] = bot.is_held(a)
	if bot.climb > 0.0:
		want[&"portal_enter"] = true
	elif bot.climb < 0.0:
		want[&"climb_down"] = true
	for a: StringName in want:
		var k := PlaytestInput.key_for_action(a)
		if k == KEY_NONE:
			input.set_action_strength(a, 1.0 if bool(want[a]) else 0.0)
			continue
		if bool(want[a]) and not _keys_down.has(a):
			input.key_down(k)
			_keys_down[a] = k
		elif not bool(want[a]) and _keys_down.has(a):
			input.key_up(_keys_down[a])
			_keys_down.erase(a)


func _release(input: PlaytestInput) -> void:
	input.release_movement()
	for a: StringName in _keys_down.keys():
		input.key_up(_keys_down[a])
	_keys_down.clear()
	for a in TAP_ACTIONS:
		input.set_action_strength(a, 0.0)
