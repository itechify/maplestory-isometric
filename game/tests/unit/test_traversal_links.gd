extends TestCase
## L2 per link and L3 tour (MAP_ARCHITECTURE.md section 4.13), each in its own headless child process of
## res://tools/traversal_bot.tscn at --fixed-fps 60 with the game's PlayerController (the test runner cannot await
## physics frames):
##   links       every trail walked in each allowed direction in edge mode (the exact map_left -> map_entered ->
##               portal_used sequence through the gate), every link pressed in warp mode, walk/press-Up equivalence,
##               and 40 -> 30 blocked by the ledge for 10 s of jump spam
##   tour edge   the Test A tour from a new game at 000000001, trails walked
##   tour warp   the same tour with every link press-Up (the force_link_mode fallback)
## Each must pass with zero fall recoveries, stalls and region invariant violations. Needs the Blender export
## (INCLUDE_WORLD=1); prints one SKIP line without it.

const TOOL_SCENE := "res://tools/traversal_bot.tscn"
## Watchdogs (frames at --fixed-fps 60): the link runs take ~25k frames, the edge tour ~52k, the warp tour ~38k.
const LINK_FRAMES := 90000
const TOUR_FRAMES := 150000


func test_l2_every_link_both_ways() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_l2_every_link_both_ways: game/assets/world not present (run with INCLUDE_WORLD=1)")
		return
	var r := _run(PackedStringArray(["--only", "trails"]), LINK_FRAMES, "links")
	if r.is_empty():
		return
	var summary := String(r.summary)
	assert_true(summary.contains("links runs="), "summary: %s" % summary)
	var runs := _int_after(summary, "links runs=")
	assert_true(runs >= 80, "link runs %d (20 trails both ways x walk and press, doors, the ledge)" % runs)
	assert_eq(_int_after(summary, "failed="), 0, "link failures (see the TRAVERSAL LINK lines)")
	assert_true(String(r.out).contains("TRAVERSAL LEDGE 000000040>000000030 blocked (ok)"), "40 -> 30 is blocked by the ledge")


func test_l3_test_a_tour_walking_the_trails() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_l3_test_a_tour_walking_the_trails: game/assets/world not present (run with INCLUDE_WORLD=1)")
		return
	_tour("edge")


func test_l3_test_a_tour_in_warp_mode() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_l3_test_a_tour_in_warp_mode: game/assets/world not present (run with INCLUDE_WORLD=1)")
		return
	_tour("warp")


func _tour(mode: String) -> void:
	var r := _run(PackedStringArray(["--only", "tour", "--tour", mode]), TOUR_FRAMES, "tour " + mode)
	if r.is_empty():
		return
	var summary := String(r.summary)
	assert_true(summary.contains("tour %s ok=true" % mode), "tour %s: %s" % [mode, summary])
	assert_eq(_int_after(summary, "legs="), 38, "38 legs (25 maps)")
	for key in ["recoveries=", "stalls=", "violations=", "teleports="]:
		assert_eq(_int_after(summary, key), 0, "tour %s %s" % [mode, key])


## Runs the tool with `args`; returns {"out", "summary", "code"} or {} after failing the test.
func _run(args: PackedStringArray, frames: int, label: String) -> Dictionary:
	var out: Array = []
	var report := ProjectSettings.globalize_path("user://traversal_test_%s.json" % label.replace(" ", "_"))
	var all := PackedStringArray(["--headless", "--fixed-fps", "60", "--quit-after", str(frames), "--path",
		ProjectSettings.globalize_path("res://"), TOOL_SCENE, "--"])
	all.append_array(args)
	all.append_array(PackedStringArray(["--out", report]))
	var t0 := Time.get_ticks_msec()
	var code := OS.execute(OS.get_executable_path(), all, out, true)
	var text := "\n".join(PackedStringArray(out))
	var summary := ""
	for line in text.split("\n"):
		var l := line.strip_edges()
		if l.begins_with("TRAVERSAL_SUMMARY"):
			summary = l
			print("  [%s] %s (%d ms)" % [label, l, Time.get_ticks_msec() - t0])
		elif l.begins_with("TRAVERSAL ") and l.contains("FAIL"):
			fail("[%s] %s" % [label, l])
		elif l.begins_with("SCRIPT ERROR") or l.contains("Parse Error"):
			fail("[%s] child process: %s" % [label, l])
	if summary == "":
		fail("[%s] the traversal tool did not finish (exit %d); output tail: %s" % [label, code, text.right(1500)])
		return {}
	assert_eq(code, 0, "[%s] tool exit code" % label)
	return {"out": text, "summary": summary, "code": code}


static func _int_after(s: String, key: String) -> int:
	var i := s.find(key)
	if i < 0:
		return -1
	var j := i + key.length()
	var digits := ""
	while j < s.length() and s[j] >= "0" and s[j] <= "9":
		digits += s[j]
		j += 1
	return int(digits) if digits != "" else -1
