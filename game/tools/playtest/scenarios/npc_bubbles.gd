extends PlaytestScenario
## npc_bubbles: NPC speech bubbles in the real game (adopted from the quests package's scratch check). After a setup
## warp to Amherst (one logged console step) the run is strict. For 30 s of game time it watches every NPC presenter's
## bubble: at least one shows, and every text shown is one of that NPC's canonical idle lines (canonical
## npcs/<id>.json idle_chatter; the timing is the MisoStory adaptation misostory/npcs/_speech_bubbles.json). Then Rain
## is talked to on foot, and no bubble shows over her while her chat is open.

const AMHERST := "000001010"
const RAIN := "19"
const WATCH_S := 30.0

var d: PlaytestDriver = null
var k: PlaytestKit = null


func description() -> String:
	return "speech bubbles over the Amherst NPCs show canonical idle lines, and none while talking"


func max_seconds() -> float:
	return 240.0


func run(p_d: PlaytestDriver) -> void:
	d = p_d
	k = PlaytestKit.new(d)
	var ng: Dictionary = await d.new_game("Listener", "female", "", {})
	if not d.check("new game through the title and creation screens", bool(ng["ok"]) and ng["via"] == "screen", str(ng)):
		return
	await _setup_warp()
	if not d.check("in Amherst", d.current_map() == AMHERST, d.current_map(), ["map:" + AMHERST]):
		return
	d.begin_strict("after the setup warp")
	k.connect_bus()
	var seen := {}
	var by_npc := {}
	var shot := false
	var t0 := d.game_s()
	while d.game_s() - t0 < WATCH_S:
		await d.wait(0.1)
		for b: Dictionary in _bubbles():
			var key := "%s: %s" % [b["npc"], b["text"]]
			if not seen.has(key):
				seen[key] = _canonical(String(b["npc"]), String(b["text"]))
				by_npc[String(b["npc"])] = true
			if not shot:
				shot = true
				await k.shot("bubble")
	d.note("bubbles seen in %.0f s: %s" % [WATCH_S, str(seen)])
	var keys := []
	for npc: String in by_npc:
		keys.append("npc:" + npc)
	d.check("at least one bubble showed in %.0f s" % WATCH_S, not seen.is_empty(), str(seen), keys)
	var all_ok := true
	for key: String in seen:
		all_ok = all_ok and bool(seen[key])
	d.check("every bubble is one of its NPC's canonical idle lines", all_ok and not seen.is_empty(), str(seen), keys)
	var v: Dictionary = await k.talk(RAIN)
	if not d.check("Rain can be talked to on foot", bool(v.get("open", false)), String(v.get("why", "")), ["npc:" + RAIN]):
		return
	var shown := false
	for i in 100:
		await d.wait(0.1)
		for b: Dictionary in _bubbles():
			shown = shown or String(b["npc"]) == RAIN
	d.check("Rain shows no bubble while her chat is open", not shown, "", ["npc:" + RAIN])
	await d.close_dialogue()


## The visible bubbles: [{"npc", "text"}] from every NPC presenter of the map.
func _bubbles() -> Array:
	var out: Array = []
	var inter := d.interaction()
	var pres: Dictionary = inter.get("presenters") if inter != null else {}
	for nid: Variant in pres:
		var p: Variant = pres[nid]
		if not (p is NpcPresenter) or not is_instance_valid(p):
			continue
		var b: NpcSpeechBubble = (p as NpcPresenter).bubble
		if b != null and is_instance_valid(b) and b.visible:
			out.append({"npc": String(nid), "text": b.text})
	return out


## True when `text` is one of the NPC's canonical idle lines.
func _canonical(npc: String, text: String) -> bool:
	for l: Variant in d.db().npc(npc).get("idle_chatter", []):
		if l is Dictionary and String((l as Dictionary).get("text", "")) == text:
			return true
	return false


func _setup_warp() -> void:
	await d.console("warp " + AMHERST)
	await d.wait_idle()
