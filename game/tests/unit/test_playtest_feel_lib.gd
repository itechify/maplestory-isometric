extends TestCase
## The play-feel review's measuring library (game/tools/playtest/scenarios/test_feel_common.gd), its pure parts:
## segment counters merge (sums, maxima, minima, capped location lists, per-kind dictionaries), the one-line texts
## never fail on an empty segment, frame sheets compose frames of any format and skip missing ones, and
## test_feel_routes reads RouteBot's report fields.

const Lib := preload("res://tools/playtest/scenarios/test_feel_common.gd")
const Routes := preload("res://tools/playtest/scenarios/test_feel_routes.gd")


func test_merge_sums_counts_and_keeps_extremes() -> void:
	var a: Dictionary = Lib.Sampler.new_seg("a")
	var b: Dictionary = Lib.Sampler.new_seg("b")
	a["ticks"] = 10
	b["ticks"] = 5
	a["snags"] = 1
	b["snags"] = 2
	a["drop_max_m"] = 0.5
	b["drop_max_m"] = 1.25
	a["cam_min_margin_px"] = 120.0
	b["cam_min_margin_px"] = 80.0
	a["cam_max_off"] = Vector2(0.1, 0.4)
	b["cam_max_off"] = Vector2(0.3, 0.2)
	a["speed_sum"] = 1.5
	b["speed_sum"] = 2.0
	a["climb_ends"] = {"top": 2}
	b["climb_ends"] = {"top": 1, "bottom": 1}
	for k in Lib.WHERE_MAX + 3:
		(a["snag_where"] as Array).append("a%d" % k)
	var m: Dictionary = Lib.Sampler.merge("both", [a, b])
	assert_eq(m["label"], "both")
	assert_eq(int(m["ticks"]), 15, "counts add")
	assert_eq(int(m["snags"]), 3)
	assert_near(float(m["drop_max_m"]), 1.25, 1e-6, "maxima take the max")
	assert_near(float(m["cam_min_margin_px"]), 80.0, 1e-6, "the margin takes the min")
	assert_eq(m["cam_max_off"], Vector2(0.3, 0.4), "per-axis max")
	assert_near(float(m["speed_sum"]), 3.5, 1e-6, "float sums")
	assert_eq(m["climb_ends"], {"top": 3, "bottom": 1}, "per-kind counts add")
	assert_eq((m["snag_where"] as Array).size(), Lib.WHERE_MAX, "location lists are capped")


func test_texts_handle_an_empty_segment() -> void:
	var s: Dictionary = Lib.Sampler.new_seg("empty")
	assert_true(Lib.Sampler.move_text(s).begins_with("empty: 0 ticks"), Lib.Sampler.move_text(s))
	assert_true(Lib.Sampler.camera_text(s).contains("0 camera ticks"), Lib.Sampler.camera_text(s))


func test_sheet_composes_frames_and_skips_missing_ones() -> void:
	var red := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	red.fill(Color.RED)
	var blue := Image.create(20, 20, false, Image.FORMAT_RGB8)
	blue.fill(Color.BLUE)
	var sheet: Image = Lib.Util.sheet([red, null, blue], 2, Vector2i(40, 30))
	assert_eq(sheet.get_size(), Vector2i(80, 30), "two frames (the null one skipped) in one row of two cells")
	assert_true(sheet.get_pixel(20, 15).r > 0.9, "the first cell is the red frame")
	assert_true(sheet.get_pixel(60, 15).b > 0.9, "the second cell is the blue frame")


func test_route_report_fields() -> void:
	var rep := "route=route 000000042/Main result=DONE progress=140.2/141.0m time=50.1s jumps=3 climbs=4 falls=0"
	assert_eq(Routes._field(rep, "jumps"), 3)
	assert_eq(Routes._field(rep, "climbs"), 4)
	assert_eq(Routes._field(rep, "missing"), -1)
