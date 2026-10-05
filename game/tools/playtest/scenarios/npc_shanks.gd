extends PlaytestScenario
## npc_shanks: Shanks' departure boundary in the real game (Iteration Three's end of Maple Island; adopted from the
## quests package's scratch check). A new game is warped to Southperry (setup), and the talk, the pages, the Yes and
## the End of Maple Island screen are played with real keys: below level 7 Shanks refuses with the canonical level;
## at level 7 without the fare he refuses with the canonical fare; with 300 mesos he gives the guide's sentence, lists
## the unfinished Maple Island quests (a warning, not a block) and offers the voyage. Yes opens the End of Maple
## Island screen: Victoria Island is not built, nobody sails, the fare is not taken, the character stays in
## Southperry and the departure flag is set. Space (jump) does not dismiss the screen; Enter on "Stay on Maple Island"
## and Esc do. The flag survives Save, Quit to Title and Continue. Setup (warp, level, mesos) is console, each command
## a logged step in a _setup function; route, level and fare come from canonical data (npcs/15.json transport).
## The clean-character playthrough (scenarios/playthrough.gd) reaches the same screen without any console use.

const SHANKS := "15"
const SOUTHPERRY := "000000060"
const SCREEN_PATH := "Screens/DepartureScreen"

var d: PlaytestDriver = null
var k: PlaytestKit = null


func description() -> String:
	return "Shanks: refused below level 7 and without the fare, the guide and the unfinished list, Yes -> End of Maple Island, Space ignored, Enter and Esc close, the flag survives a reload"


func max_seconds() -> float:
	return 400.0


func run(p_d: PlaytestDriver) -> void:
	d = p_d
	k = PlaytestKit.new(d)
	var ng: Dictionary = await d.new_game("Sailor", "male", "", {})
	if not d.check("new game through the title and creation screens", bool(ng["ok"]) and ng["via"] == "screen", str(ng)):
		return
	k.connect_bus()
	var s := screen()
	d.check("the End of Maple Island screen is installed and hidden", s != null and not bool(s.call("is_open")),
		str(s), ["npc:" + SHANKS])
	var route := _route()
	d.check("Shanks' canonical route: level %d, fare %d mesos, to %s" % [int(route.get("min_level", -1)),
		int(route.get("fare_mesos", -1)), route.get("to_map_name", "?")], int(route.get("min_level", 0)) > 0
		and int(route.get("fare_mesos", 0)) > 0, str(route), ["npc:" + SHANKS])
	await _setup_warp()
	if not d.check("in Southperry", d.current_map() == SOUTHPERRY, d.current_map(), ["map:" + SOUTHPERRY]):
		return

	# --- level 1: refused for the level -------------------------------------------------------------------------
	var pages := await _talk_pages()
	d.check("Shanks can be talked to on foot", bool(pages["open"]), String(pages["why"]), ["npc:" + SHANKS])
	d.check("his greeting is his canonical voyage line", _any(pages["texts"], _greeting()), str(pages["texts"]),
		["npc:" + SHANKS])
	d.check("level %d is refused with the canonical level %d" % [d.character().level, int(route["min_level"])],
		_any(pages["texts"], "at least level %d" % int(route["min_level"])) and pages["offer"] == "", str(pages["texts"]),
		["npc:" + SHANKS])
	d.check("the chat ended without an offer", not d.dialogue_open() and not bool(s.call("is_open")))

	# --- the level, no fare: refused for the fare ---------------------------------------------------------------
	await _setup_level(int(route["min_level"]))
	pages = await _talk_pages()
	d.check("at level %d with %d mesos the fare (%d) is refused" % [d.character().level, d.character().mesos,
		int(route["fare_mesos"])], _any(pages["texts"], "The fare to") and _any(pages["texts"], "%d mesos" % int(route["fare_mesos"]))
		and pages["offer"] == "", str(pages["texts"]), ["npc:" + SHANKS, "mechanic:insufficient-mesos-warning"])

	# --- the fare: the guide, the unfinished quests, the offer ---------------------------------------------------
	await _setup_mesos(int(route["fare_mesos"]))
	pages = await _talk_pages({"stop_at_offer": true})
	d.check("the guide's sentence", _any(pages["texts"], "Hand in every Maple Island quest before you board."),
		str(pages["texts"]), ["npc:" + SHANKS])
	d.check("the unfinished Maple Island quests are listed (a warning, not a block)",
		_any(pages["texts"], "You still have unfinished Maple Island quests:") and _any(pages["texts"], "Rain's Maple Quiz"),
		str(pages["texts"]), ["npc:" + SHANKS])
	d.check("the offer: 'Sail to %s? The fare is %d mesos.'" % [route["to_map_name"], int(route["fare_mesos"])],
		String(pages["offer"]).contains("The fare is %d mesos." % int(route["fare_mesos"])), String(pages["offer"]),
		["npc:" + SHANKS])
	await k.shot("shanks_offer")
	var mesos_before := d.character().mesos
	await d.choose("yes")
	await d.frames(5)
	d.check("Yes opens the End of Maple Island screen", bool(s.call("is_open")), "", ["npc:" + SHANKS])
	if not bool(s.call("is_open")):
		return
	var texts: PackedStringArray = s.call("texts")
	d.note("screen: %s" % " | ".join(texts))
	d.check("it says Victoria Island is not built and the fare was not taken",
		texts[1].contains("Victoria Island is not part of MisoStory yet") and texts[1].contains("not taken"), texts[1],
		["npc:" + SHANKS])
	d.check("the departure flag is set", d.character().flags.has("maple_island_departure_ready_at"), str(d.character().flags),
		["npc:" + SHANKS])
	d.check("no mesos charged", d.character().mesos == mesos_before, "%d -> %d" % [mesos_before, d.character().mesos],
		["npc:" + SHANKS])
	d.check("still in Southperry", d.current_map() == SOUTHPERRY, d.current_map(), ["npc:" + SHANKS])
	d.check("modal while it shows", bool(d.state().get("modal", false)))
	await k.shot("departure_screen")
	await d.wait(0.5)
	await d.tap_key(KEY_SPACE)
	await d.frames(3)
	d.check("Space (jump) does not dismiss it", bool(s.call("is_open")))
	await d.tap_key(KEY_ENTER)
	await d.frames(3)
	d.check("Enter on 'Stay on Maple Island' closes it", not bool(s.call("is_open")))
	d.check("no modal left", not bool(d.state().get("modal", true)))

	# --- again, closed with Esc ----------------------------------------------------------------------------------
	pages = await _talk_pages({"stop_at_offer": true})
	if String(pages["offer"]) != "":
		await d.choose("yes")
		await d.frames(5)
	d.check("the screen opens again on a second Yes", bool(s.call("is_open")), str(pages["texts"]), ["npc:" + SHANKS])
	await d.tap_key(KEY_ESCAPE)
	await d.frames(3)
	d.check("Esc closes it", not bool(s.call("is_open")) and not bool(d.state().get("modal", true)))

	# --- the flag survives a save and Continue -------------------------------------------------------------------
	var saved: Dictionary = await d.save_game()
	d.check("saved through the pause menu", bool(saved["ok"]) and saved["via"] == "screen", str(saved), ["mechanic:save-load"])
	await d.quit_to_title()
	var cont: Dictionary = await d.continue_game()
	d.check("Continue", bool(cont["ok"]), str(cont))
	d.check("the departure flag survives Quit to Title and Continue", d.character().flags.has("maple_island_departure_ready_at"),
		str(d.character().flags), ["npc:" + SHANKS, "mechanic:save-load"])


## The End of Maple Island screen (MainShell/Screens/DepartureScreen), or null.
func screen() -> Node:
	var c := d.ctx()
	var main: Node = c.main if c != null else null
	return main.get_node_or_null(SCREEN_PATH) if main != null else null


## Shanks' canonical route (npcs/15.json transport.routes[0]).
func _route() -> Dictionary:
	var t: Variant = d.db().npc(SHANKS).get("transport")
	var routes: Array = (t as Dictionary).get("routes", []) if t is Dictionary else []
	return routes[0] if not routes.is_empty() and routes[0] is Dictionary else {}


## His greeting: his own canonical idle_chatter line 1 (misostory/dialogue/15.json patch_nodes).
func _greeting() -> String:
	var lines: Array = d.db().npc(SHANKS).get("idle_chatter", [])
	return String((lines[1] as Dictionary).get("text", "")) if lines.size() > 1 else "I'll take you anywhere you want to go."


## Talks to Shanks and pages the conversation with Enter until it ends, or (opts "stop_at_offer") until the Yes/No
## offer, which is left open. Returns {"open", "why", "texts", "offer" (the Yes/No text, "" when none)}. Await it.
func _talk_pages(opts: Dictionary = {}) -> Dictionary:
	var v: Dictionary = await k.talk(SHANKS)
	var out := {"open": bool(v.get("open", false)), "why": String(v.get("why", "")), "texts": PackedStringArray(), "offer": ""}
	var texts := PackedStringArray()
	var guard := 0
	var r := d.read_dialogue()
	while bool(r["open"]) and guard < 12:
		guard += 1
		texts.append(String(r["text"]))
		out["texts"] = texts
		if String(r["type"]) == "yes_no":
			out["offer"] = String(r["text"])
			if bool(opts.get("stop_at_offer", false)):
				return out
			r = await d.choose("no")
			continue
		if "next" in r["buttons"] or "ok" in r["buttons"]:
			r = await d.next()
		else:
			break
	if d.dialogue_open():
		await d.close_dialogue()
	return out


static func _any(texts: Variant, needle: String) -> bool:
	return PlaytestKit.any_contains(texts, needle)


# --- setup (console, each a logged step) --------------------------------------------------------------------------

func _setup_warp() -> void:
	await d.console("warp " + SOUTHPERRY)
	await d.wait_idle()


func _setup_level(level: int) -> void:
	await d.console("level %d" % level)


func _setup_mesos(n: int) -> void:
	await d.console("mesos %d" % n)
