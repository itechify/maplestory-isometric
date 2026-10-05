extends PlaytestScenario
## counter: talk_to() follows the game's talk rule, not a feet-to-feet distance. Pan (16) stands behind his counter in
## the Southperry Armor Store (000000061), about 1.9 m from the nearest floor a body fits on. His talk zone (a sphere
## of interaction_radius_m centred half of it above his feet) still overlaps the body of a player pressed against the
## counter, so a walking player can talk to him: the walk ends at the counter and the lean closes the rest. A console
## warp is the setup (getting to the store on foot is the traversal scenarios' job).
## tests/unit/test_playtest_smoke.gd runs it headless.

const STORE := "000000061"
const PAN := "16"


func description() -> String:
	return "talk to Pan across his counter in %s on foot (the walk, then leaning in)" % STORE


func max_seconds() -> float:
	return 120.0


func run(d: PlaytestDriver) -> void:
	var ng: Dictionary = await d.new_game("Customer", "male")
	if not d.check("new game", bool(ng["ok"]), String(ng["why"])):
		return
	await d.console("warp " + STORE)
	if not d.check("in the armor store", d.current_map() == STORE, d.current_map()):
		return
	var npc := d.world().npc_nodes.get(PAN) as Node3D
	var p := d.player()
	d.check("the arrival is outside Pan's talk zone", d.talk_gap(npc, p.global_position) > 0.0,
		"%.2f m outside" % d.talk_gap(npc, p.global_position))
	var v: Dictionary = await d.talk_to(PAN)
	d.check("Pan's conversation opens on foot", bool(v["open"]), String(v.get("why", "")))
	d.check("the player stands outside the feet-to-feet radius", p.global_position.distance_to(npc.global_position)
		> d.world().tuning.num("npc", "interaction_radius_m"), "%.2f m feet to feet" % p.global_position.distance_to(npc.global_position))
	# talk_gap() models the engine's sphere-capsule overlap; 1 cm covers the physics engine's contact tolerance.
	d.check("talk_gap() agrees: the body is inside the talk zone", d.talk_gap(npc, p.global_position) <= 0.01,
		"%.3f m" % d.talk_gap(npc, p.global_position))
	await d.screenshot("pan")
	d.check("Esc ends the conversation", await d.close_dialogue())
