extends TestCase
## Trail ribbons (MAP_ARCHITECTURE.md sections 4.3, 4.6): TrailGeometry derives a trail's side edges and rows from its
## exported triangles until the export carries the centreline. Pure part: a hand-built trail mesh like Iteration
## One's (rows of a top strip, steep flanks, end caps, an L-shaped bend whose inner edge folds) gives the right
## width, caps, sides and centreline. With the export (INCLUDE_WORLD=1): all 20 trails are derived (their grid-cut
## T-junction spikes and bend folds cleaned), each one width (5.2, 3.8 or 3.4 m; the plank bridge 3 m), its caps on
## the footprint edge 1 m inside its gates (the one-way ledge exactly on 000000040's gate plane).

const HALF := 1.9


## Rows along an L: 6 m east from (0, 0), then 6 m north; each row a left/right top vertex at y = 0 and a flank
## foot 1.5 m out and 1.8 m down. Returns the triangle soup (top quads split in two, flanks, end caps).
func l_trail() -> PackedVector3Array:
	var centre: Array[Vector3] = []
	for k in 13:
		centre.append(Vector3(k * 0.5, 0, 0))
	for k in range(1, 13):
		centre.append(Vector3(6, 0, -k * 0.5))
	var rows: Array = []
	for i in centre.size():
		var a := centre[maxi(i - 1, 0)]
		var b := centre[mini(i + 1, centre.size() - 1)]
		var t := (b - a).normalized()
		var n := Vector3(-t.z, 0, t.x)  # left of the direction of travel
		rows.append([centre[i] + n * HALF, centre[i] - n * HALF, centre[i] + n * (HALF + 1.5) + Vector3.DOWN * 1.8,
			centre[i] - n * (HALF + 1.5) + Vector3.DOWN * 1.8])
	var tris := PackedVector3Array()
	for i in rows.size() - 1:
		var l0: Vector3 = rows[i][0]
		var r0: Vector3 = rows[i][1]
		var l1: Vector3 = rows[i + 1][0]
		var r1: Vector3 = rows[i + 1][1]
		tris.append_array([l0, l1, r1, l0, r1, r0])
		var fl0: Vector3 = rows[i][2]
		var fl1: Vector3 = rows[i + 1][2]
		var fr0: Vector3 = rows[i][3]
		var fr1: Vector3 = rows[i + 1][3]
		tris.append_array([fl0, fl1, l1, fl0, l1, l0, r0, r1, fr1, r0, fr1, fr0])
	var first: Array = rows[0]
	var last: Array = rows[rows.size() - 1]
	tris.append_array([first[2], first[0], first[1], first[2], first[1], first[3]])
	tris.append_array([last[2], last[0], last[1], last[2], last[1], last[3]])
	return tris


func test_ribbon_of_a_bent_trail() -> void:
	if true:
		var r := TrailGeometry.ribbon(l_trail(), {"point": Vector3(-1, 0, 0), "normal": Vector3(-1, 0, 0)},
			{"point": Vector3(6, 0, -7), "normal": Vector3(0, 0, -1)}, 45.0)
		var label := "L-shaped trail"
		assert_true(bool(r.ok), "%s: derived (%s)" % [label, String(r.error)])
		if not bool(r.ok):
			return
		var c: PackedVector3Array = r.centre
		var h: PackedFloat32Array = r.half
		assert_near(h[0], HALF, 0.02, "%s: half-width" % label)
		assert_true(c[0].distance_to(Vector3(0, 0, 0)) < 0.05, "%s: starts at the start cap's middle (%s)" % [label, c[0]])
		assert_true(c[c.size() - 1].distance_to(Vector3(6, 0, -6)) < 0.05, "%s: ends at the end cap's middle (%s)" % [label, c[c.size() - 1]])
		var caps: Array = r.caps
		assert_true((caps[0] as Vector3).distance_to(Vector3(0, 0, 0)) < 0.05 and (caps[1] as Vector3).distance_to(Vector3(6, 0, -6)) < 0.05,
			"%s: caps %s" % [label, str(caps)])
		# The centre keeps half the width from both sides everywhere (around the bend's outer corner a little more),
		# and stays on the top.
		var sa: PackedVector3Array = r.side_a
		var sb: PackedVector3Array = r.side_b
		var straight := 0
		for p in c:
			var da := _dist(p, sa)
			var db_ := _dist(p, sb)
			# Around the 90 deg corner (rows 0.5 m apart, the inner edge folded) the centre may drift 0.3 m.
			assert_true(da > HALF - 0.3 and db_ > HALF - 0.3, "%s: centre %s too near a side (%.2f, %.2f)" % [label, p, da, db_])
			assert_true(da < HALF + 1.0 and db_ < HALF + 1.0, "%s: centre %s off the middle (%.2f, %.2f)" % [label, p, da, db_])
			if absf(da - HALF) < 0.05 and absf(db_ - HALF) < 0.05:
				straight += 1
			assert_true(absf(p.y) < 0.01, "%s: on the top" % label)
		assert_true(straight >= c.size() - 12, "%s: exactly in the middle away from the bend (%d of %d rows)" % [label, straight, c.size()])
		assert_true(sa[0].distance_to(sb[0]) > 3.7 and sa[0].distance_to(sb[0]) < 3.9, "%s: the sides start at the start cap's corners" % label)


func test_resampling_and_deck_rows() -> void:
	var pts := PackedVector3Array([Vector3.ZERO, Vector3(3, 0, 0)])
	var r := TrailGeometry.resample_step(pts, 0.5)
	assert_eq(r.size(), 7, "every 0.5 m")
	assert_near(r[3].x, 1.5, 1e-4, "evenly spaced")
	# Two planks across the x axis (3 m long, 0.47 wide), each a top and an underside face.
	var tris := PackedVector3Array()
	for x in [0.0, 0.42]:
		for y in [0.0, -0.12]:
			var a := Vector3(x - 0.235, y, -1.5)
			var b := Vector3(x + 0.235, y, -1.5)
			var c := Vector3(x + 0.235, y, 1.5)
			var d := Vector3(x - 0.235, y, 1.5)
			tris.append_array([a, b, c, a, c, d])
	var rows := TrailGeometry.deck_rows(tris, 45.0)
	assert_eq(rows.size(), 2, "one row per plank (top and underside merged)")
	for row in rows:
		assert_near(float(row.half), 1.5, 0.01, "half the plank's length")
		assert_true(absf((row.axis as Vector3).z) > 0.99, "the plank's long axis is the row's lateral")
		assert_near((row.centre as Vector3).y, 0.0, 1e-4, "the top's height")


## With the export: every trail derived from its mesh, one width each, caps 1 m inside the gates.
func test_every_exported_trail() -> void:
	if not WorldSidecars.exists():
		print("SKIP test_every_exported_trail: game/assets/world not present (run with INCLUDE_WORLD=1)")
		return
	var side := WorldSidecars.load_dir()
	var d := MapDefinitions.build(db(), side)
	var warnings := TrailLoader.attach(d, side)
	assert_eq(warnings.size(), 0, "loader warnings: %s" % "; ".join(warnings))
	var widths := {}
	for t in d.trail_list():
		assert_true(t.has_geometry(), "%s derived" % t.link_id)
		assert_eq(t.hidden, t.link_id == "T_000001020_in00__000001021_out00", "%s hidden: only the type-1 hedge lane" % t.link_id)
		if not t.has_geometry():
			continue
		var w := roundi(t.half_widths[0] * 20.0)  # decimetres
		widths[w] = int(widths.get(w, 0)) + 1
		assert_true(w in [34, 38, 52], "%s width %.2f m" % [t.link_id, t.half_widths[0] * 2.0])
		var bridge_rows := 0
		for h in t.half_widths:
			if absf(h - t.half_widths[0]) > 0.02:
				bridge_rows += 1
		if t.link_id == "T_000001000_in05__000001006_out00":
			assert_true(bridge_rows > 10, "the plank bridge appended (%d rows)" % bridge_rows)
		else:
			assert_eq(bridge_rows, 0, "%s has one width" % t.link_id)
		for i in 2:
			var g := t.gates[i]
			var cap := t.centre[0] if i == 0 else t.centre[t.centre.size() - 1]
			if t.link_id == "T_000001000_in05__000001006_out00" and i == 1:
				continue  # the bridge's last plank, not a cap
			var depth := 0.0 if (t.one_way and i == 1) else d.tuning.num("containment", "ring_offset_m")
			assert_near(g.signed_distance(cap), depth, 0.05, "%s cap at %s %.2f m inside its gate" % [t.link_id, g.map_id, g.signed_distance(cap)])
			assert_true(absf(g.lateral_offset(cap)) < 0.05, "%s cap centred on its gate" % t.link_id)
	assert_eq(widths, {52: 11, 38: 8, 34: 1}, "trail widths in dm (main road 5.2 m, branches 3.8 m, the hidden lane 3.4 m)")


static func _dist(p: Vector3, line: PackedVector3Array) -> float:
	var best := INF
	for i in line.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z), Vector2(line[i].x, line[i].z), Vector2(line[i + 1].x, line[i + 1].z))
		best = minf(best, q.distance_to(Vector2(p.x, p.z)))
	return best
