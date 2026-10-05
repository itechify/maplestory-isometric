extends PlaytestScenario
## smoke: the harness end to end on the shell, the world and an NPC.
## New game through the title and creation screens -> walk route "Main" of 000000001 (its spawn to the portal) ->
## walk the trail to 000000010 across the far gate (M2 edge mode) -> talk to Roger (prompt, F, the conversation,
## Esc) -> save through the pause menu -> quit to title -> Continue -> the same map, place and character.
## tests/unit/test_playtest_smoke.gd runs it headless and asserts a clean report.

const START_MAP := "000000001"
const TOWN := "000000010"
const ROGER := "3"


func description() -> String:
	return "new game, route Main in %s, the trail to %s, Roger, save, quit to title, continue" % [START_MAP, TOWN]


func max_seconds() -> float:
	return 300.0


func run(d: PlaytestDriver) -> void:
	var ng: Dictionary = await d.new_game("Smoke", "female", "541", {"str": 5, "dex": 4})
	d.check("new game through the title and creation screens", bool(ng["ok"]) and ng["via"] == "screen",
		"via %s: %s" % [ng["via"], ng["why"]])
	if not bool(ng["ok"]):
		return
	var s := d.state()
	d.check("the game starts in %s" % START_MAP, s.get("map") == START_MAP, str(s.get("map")))
	var c := d.character()
	d.check("the character is the one created", c.name == "Smoke" and c.gender == "female"
		and c.equipment.weapon_id() == "541" and c.get_base_stat("str") == 9 and c.get_base_stat("dex") == 8,
		"%s %s weapon %s stats %s" % [c.name, c.gender, c.equipment.weapon_id(), c.base_stats])

	var route: Dictionary = await d.walk_route(START_MAP, "Main")
	d.check("walked route Main of %s" % START_MAP, bool(route["ok"]), "; ".join(route["issues"]))

	var trail: Dictionary = await d.walk_trail(START_MAP, TOWN)
	d.check("walked the trail into %s across the gate" % TOWN, bool(trail["ok"]) and trail["how"] == "walk"
		and trail["via"] == "gate", "%s via %s (%s)" % [trail["map"], trail["via"], "; ".join(trail["issues"])])
	if d.current_map() != TOWN:
		return

	var talk: Dictionary = await d.talk_to(ROGER)
	# Known world issue (2026-10-04): Roger stands on a terrace about 3-4 m above every ground around it, with no
	# stairs or climbable, so no player can walk up to him. Surfaced as a WARN; the console puts the player in front
	# of him (a setup step, counted apart) so the rest of the flow is still played.
	if not d.soft_check("Roger can be reached on foot", bool(talk["open"])):
		await d.console("goto npc %s" % ROGER)
		talk = await d.talk_to(ROGER)
	d.check("Roger's conversation opens with the interact key", bool(talk["open"]), str(talk))
	d.check("Roger says something", String(talk.get("text", "")).strip_edges() != "", String(talk.get("text", "")))
	await d.screenshot("roger")
	d.check("Esc ends the conversation", await d.close_dialogue())
	d.check("no modal left after the conversation", not bool(d.state().get("modal", true)))

	var before := d.state()
	var saved: Dictionary = await d.save_game()
	d.check("saved through the pause menu", bool(saved["ok"]) and saved["via"] == "screen",
		"%s %s (%s)" % [saved["slot"], saved["status"], saved["via"]])
	var quit: Dictionary = await d.quit_to_title()
	d.check("quit to title through the pause menu", bool(quit["ok"]) and quit["via"] == "screen", str(quit))
	var cont: Dictionary = await d.continue_game()
	d.check("continued from the title", bool(cont["ok"]) and cont["via"] == "screen", str(cont))
	var after := d.state()
	d.check("continued in the same map", after.get("map") == before.get("map"),
		"%s, saved in %s" % [after.get("map"), before.get("map")])
	var moved := (after.get("position", Vector3.INF) as Vector3).distance_to(before.get("position", Vector3.ZERO))
	d.check("continued where the game was saved", moved < 1.0, "%.2f m from the saved position" % moved)
	d.check("the same character after the reload", after.get("name") == before.get("name")
		and after.get("level") == before.get("level") and after.get("exp") == before.get("exp")
		and after.get("mesos") == before.get("mesos") and str(after.get("inventory")) == str(before.get("inventory"))
		and str(after.get("equipment")) == str(before.get("equipment")), "%s / %s" % [after.get("inventory"), before.get("inventory")])
	await d.screenshot("continued")
