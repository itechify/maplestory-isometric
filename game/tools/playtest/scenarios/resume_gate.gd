extends PlaytestScenario
## resume_gate: G1, the clean-character playthrough's open game observation, in the real game. A player who walks a
## trail across its far gate stands inside the trigger of the portal it arrived through until it walks on; a save made
## there kept that point as its resume point, and the Continue refused it ("saved resume point ... failed validation;
## using the entry") and fell back to the arrival 0.7 m away. For both gates the playthrough saw (The Field East of
## Amherst -> Amherst east00, A Split Road -> Southperry west00): a setup warp to the trail's start map (console), the
## trail walked with real input across the gate, a short walk back into the entry portal's own trigger, Save in the
## pause menu, Quit Game. The next process reads the save from disk (the entry is that portal, the resume point lies in
## its trigger) and presses Continue: the load used the resume point (MapSession's load step "resume", no fallback),
## the player stands where the save says, still inside the trigger, the portal is disarmed as after an arrival, and
## walking out of its trigger re-arms it.

const LEGS := [
	{"from": "000001020", "to": "000001010"},  # The Field East of Amherst -> Amherst (east00)
	{"from": "000000050", "to": "000000060"},  # A Split Road -> Southperry (west00)
]
## How close the Continue must put the player to the saved resume point (horizontal, m).
const RESUME_TOLERANCE_M := 0.05


func description() -> String:
	return "G1: a save just past a trail gate (inside the entry portal's trigger) resumes there after a Continue"


func max_seconds() -> float:
	return 300.0


func run(d: PlaytestDriver) -> void:
	if d.phase > 0:
		if not await _verify(d, LEGS[d.phase - 1]):
			return
	if d.phase == 0:
		var ng: Dictionary = await d.new_game("Gatekeeper", "female", "585", {"str": 9})
		if not d.check("new game through the screens", bool(ng["ok"]) and ng["via"] == "screen", str(ng)):
			return
		await _setup(d)
	if d.phase < LEGS.size():
		await _leg(d, LEGS[d.phase])


func _setup(d: PlaytestDriver) -> void:
	await d.console("god on")


## Warp to the trail's start (setup), walk it across the far gate, step back into the entry portal's trigger, save
## through the pause menu and Quit Game.
func _leg(d: PlaytestDriver, leg: Dictionary) -> void:
	var from := String(leg["from"])
	var to := String(leg["to"])
	await d.console("warp " + from)
	await d.wait_idle(20.0)
	var w: Dictionary = await d.walk_trail(from, to)
	if not d.check("[%s] walked the trail %s -> %s across the gate" % [to, from, to], bool(w["ok"]) and d.current_map() == to,
			"%s via %s, map %s, %s" % [w["how"], w["via"], d.current_map(), "; ".join(w["issues"])]):
		return
	var entry := _entry_portal(d, from, to)
	var arrival: ArrivalRef = d.session().get("last_arrival")
	d.check("[%s] the gate's arrival is %s" % [to, entry.key()], arrival != null and arrival.is_portal()
		and arrival.portal_id == entry.portal_id, str(arrival))
	if not _inside(d, entry):
		var spot := _point_in_trigger(d, entry)
		if spot != Vector3.INF:
			await d.walk_to(spot, {"max_s": 10.0, "within_m": 0.1})
	await d.wait(1.0)
	d.check("[%s] standing inside %s's trigger, just past the gate" % [to, entry.key()], _inside(d, entry),
		"local %s" % str(d.state().get("local")))
	var sv: Dictionary = await d.save_game()
	d.check("[%s] saved through the pause menu" % to, bool(sv["ok"]) and sv["via"] == "screen", str(sv))
	d.carry["slot"] = String(sv.get("slot", ""))
	d.carry["position"] = d.player().global_position
	await d.reload_process()


## The next process: the save on disk, then Continue and where it put the player.
func _verify(d: PlaytestDriver, leg: Dictionary) -> bool:
	var from := String(leg["from"])
	var to := String(leg["to"])
	var save := _read_save(d, String(d.carry.get("slot", "")))
	var loc: Dictionary = (save.get("world", {}) as Dictionary).get("location", {})
	var entry_d: Dictionary = loc.get("entry", {})
	var resume: Variant = loc.get("resume", null)
	var cg: Dictionary = await d.continue_game()
	if not d.check("[%s] Continue" % to, bool(cg["ok"]) and cg["via"] == "screen", str(cg)):
		return false
	var entry := _entry_portal(d, from, to)
	var def := d.world().defs.get_def(to)
	d.check("[%s] the save names %s as the entry and keeps a resume point" % [to, entry.key()],
		String(loc.get("map_id", "")) == to and String(entry_d.get("portal_id", "")) == entry.portal_id and resume is Dictionary,
		JSON.stringify(loc))
	if not (resume is Dictionary):
		return false
	var lp: Array = (resume as Dictionary).get("local_pos", [])
	var saved := def.to_world(Vector3(float(lp[0]), float(lp[1]), float(lp[2]))) if lp.size() == 3 else Vector3.INF
	d.check("[%s] the saved resume point lies inside %s's trigger (the G1 case)" % [to, entry.key()],
		entry.trigger_contains(saved + Vector3.UP * 0.1), "resume %s" % str(saved))
	var rec: Variant = d.session().get("last_transition")
	var step := String((rec as TransitionRecord).load_step) if rec is TransitionRecord else ""
	d.check("[%s] the load used the saved resume point, not the entry fallback" % to, step == ArrivalResolver.STEP_RESUME,
		"load step '%s'" % step, ["persistence:current-map", "mechanic:save-load"])
	var p := d.player().global_position
	var off := Vector2(p.x - saved.x, p.z - saved.z).length()
	d.check("[%s] the player stands at the saved point after the Continue" % to, d.current_map() == to and off <= RESUME_TOLERANCE_M,
		"%s, %.3f m from the resume point (%.2f m from where the game quit)" % [d.current_map(), off,
			p.distance_to(d.carry.get("position", Vector3.INF))], ["persistence:current-map"])
	var wp: WorldPortal = d.world().portal_node(to, entry.portal_id)
	d.check("[%s] inside %s's trigger, the portal disarmed as after an arrival" % [to, entry.key()],
		_inside(d, entry) and wp != null and not wp.armed, "inside %s, armed %s" % [_inside(d, entry), wp.armed if wp != null else "?"])
	# Walk on into the map: leaving the trigger re-arms the portal.
	await d.walk_to(entry.spawn_transform.origin + (entry.spawn_transform.origin - entry.anchor_ground).normalized() * 2.0,
		{"max_s": 10.0, "within_m": 0.5})
	await d.wait(0.2)
	d.check("[%s] out of the trigger the portal is armed again" % to, not _inside(d, entry) and wp != null and wp.armed,
		"inside %s, armed %s" % [_inside(d, entry), wp.armed if wp != null else "?"])
	return true


## The portal of `to` at the trail from `from` (the entry a walk across the far gate records).
func _entry_portal(d: PlaytestDriver, from: String, to: String) -> PortalDef:
	var defs := d.world().defs
	var src := TraversalTour.portal_between(defs, from, to)
	var t := defs.trail(src.link_id)
	return defs.graph.portals.get(t.portal_key_of(to), null) as PortalDef


func _inside(d: PlaytestDriver, p: PortalDef) -> bool:
	return p != null and p.trigger_contains(d.player().global_position + Vector3.UP * 0.1)


## The first walkable point inside `p`'s trigger on the line from its arrival to its anchor (Vector3.INF if none).
func _point_in_trigger(d: PlaytestDriver, p: PortalDef) -> Vector3:
	var a := p.spawn_transform.origin
	var b := p.anchor_ground
	var n := int(ceil(Vector2(b.x - a.x, b.z - a.z).length() / 0.05))
	for i in n + 1:
		var c := a.lerp(b, float(i) / maxf(1.0, float(n)))
		var g: Dictionary = d.world().ground_query.ground_at(c, 1.0, 3.0)
		if bool(g.get("ok", false)):
			var feet := Vector3(c.x, float(g["y"]), c.z)
			if p.trigger_contains(feet + Vector3.UP * 0.1):
				# 0.2 m deeper, so the walker's stop tolerance still leaves the feet inside.
				return feet + (b - a).normalized() * 0.2 * Vector3(1, 0, 1)
	return Vector3.INF


static func _read_save(d: PlaytestDriver, slot: String) -> Dictionary:
	var path := d.save_dir.path_join(slot + ".json")
	if slot == "" or not FileAccess.file_exists(path):
		return {}
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return v if v is Dictionary else {}
