class_name AttackFx
extends Node3D
## Short-lived combat effects (scenes/fx/attack_fx.tscn). Presentation only: procedural meshes (no sprites), sized
## from the canonical hit box of the attack that played, so what the player sees is the reach that hits.
##   swing(feet, facing, box_px)   a crescent slash through the box (sword, axe, club swings)
##   stab(feet, facing, box_px)    a thrust spike from the box's near edge to its far edge (stabs, dagger thrusts)
##   punch(feet, facing, box_px)   a small burst at the far end of the box (bare hands)
##   spark(pos)                    a hit flash on a monster
## box_px is CombatReach.attack_box_px(weapon, presentation, true, level): facing +x, y down, px. Meters through
## WorldScale.actor, as for the hit test (MeleeQuery).

## Presentation constants: lifetimes (s), colours and shapes.
const SWING_LIFE_S := 0.28
const STAB_LIFE_S := 0.22
const PUNCH_LIFE_S := 0.2
const SPARK_LIFE_S := 0.22
const SLASH_COLOR := Color(1.0, 0.97, 0.85, 0.9)
const STAB_COLOR := Color(0.85, 0.95, 1.0, 0.9)
const PUNCH_COLOR := Color(1.0, 0.9, 0.55, 0.9)
const SPARK_COLOR := Color(1.0, 0.95, 0.7, 0.95)
## The slash plane is tilted this far from vertical about the facing axis, so it reads from the isometric camera in
## every facing (a vertical arc is edge-on when the player faces toward or away from the camera).
const SLASH_TILT_DEG := 55.0
const ARC_FROM_DEG := 85.0
const ARC_TO_DEG := -45.0
const ARC_SEGMENTS := 18

var _live: Array[Dictionary] = []


func swing(feet: Vector3, facing: Vector3, box_px: Rect2) -> Node3D:
	var g := _geometry(box_px)
	var mesh := arc_mesh(g.near, g.far, deg_to_rad(ARC_FROM_DEG), deg_to_rad(ARC_TO_DEG), ARC_SEGMENTS, SLASH_COLOR)
	var n := _spawn(mesh, feet, facing, g.center_h, SWING_LIFE_S, &"swing")
	n.rotate_object_local(Vector3.BACK, deg_to_rad(SLASH_TILT_DEG))
	return n


func stab(feet: Vector3, facing: Vector3, box_px: Rect2) -> Node3D:
	var g := _geometry(box_px)
	var mesh := spike_mesh(g.near, g.far, maxf(0.06, (g.top_h - g.bottom_h) * 0.5), STAB_COLOR)
	return _spawn(mesh, feet, facing, g.center_h, STAB_LIFE_S, &"stab")


func punch(feet: Vector3, facing: Vector3, box_px: Rect2) -> Node3D:
	var g := _geometry(box_px)
	var mi := make_burst(maxf(0.18, (g.far - g.near) * 0.35), PUNCH_COLOR, 8, false)
	var f := _flat(facing)
	add_child(mi)
	mi.global_position = feet + f * g.far + Vector3.UP * g.center_h
	_live.append({"node": mi, "t": 0.0, "life": PUNCH_LIFE_S, "kind": &"punch"})
	return mi


func spark(pos: Vector3, radius: float = 0.35) -> Node3D:
	var mi := make_burst(radius, SPARK_COLOR, 10, true)
	add_child(mi)
	mi.global_position = pos
	_live.append({"node": mi, "t": 0.0, "life": SPARK_LIFE_S, "kind": &"spark"})
	return mi


func live_count() -> int:
	return _live.size()


func _process(delta: float) -> void:
	advance(delta)


## Advances every effect (called by _process; tests call it directly).
func advance(delta: float) -> void:
	var keep: Array[Dictionary] = []
	for e in _live:
		var n: Node3D = e.node
		if not is_instance_valid(n):
			continue
		e.t = float(e.t) + delta
		var k := clampf(float(e.t) / float(e.life), 0.0, 1.0)
		if k >= 1.0:
			n.queue_free()
			continue
		var gi := n as GeometryInstance3D
		match e.kind:
			&"swing":
				n.scale = Vector3.ONE * lerpf(0.82, 1.06, sqrt(k))
				gi.transparency = k * k * k
			&"stab":
				n.scale = Vector3(1.0, 1.0, lerpf(0.45, 1.0, sqrt(clampf(k * 2.0, 0.0, 1.0))))
				gi.transparency = k * k
			_:
				n.scale = Vector3.ONE * lerpf(0.5, 1.2, sqrt(k))
				gi.transparency = k
		keep.append(e)
	_live = keep


func _spawn(mesh: Mesh, feet: Vector3, facing: Vector3, height: float, life: float, kind: StringName) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = fx_material(false, false)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var f := _flat(facing)
	mi.global_transform = Transform3D(Basis.looking_at(-f, Vector3.UP), feet + Vector3.UP * height)
	_live.append({"node": mi, "t": 0.0, "life": life, "kind": kind})
	return mi


## Box geometry in meters: near/far reach along the facing, heights above the feet.
static func _geometry(box_px: Rect2) -> Dictionary:
	var near := WorldScale.actor(maxf(0.0, box_px.position.x))
	var far := WorldScale.actor(maxf(box_px.end.x, box_px.position.x + 1.0))
	var top_h := WorldScale.actor(-box_px.position.y)
	var bottom_h := WorldScale.actor(-box_px.end.y)
	return {"near": near, "far": far, "top_h": top_h, "bottom_h": bottom_h, "center_h": (top_h + bottom_h) * 0.5}


static func _flat(v: Vector3) -> Vector3:
	var f := Vector3(v.x, 0.0, v.z)
	return f.normalized() if f.length_squared() > 1e-8 else Vector3.BACK


## Unshaded additive vertex-colour material for effects. Billboarded bursts keep their scale.
static func fx_material(billboard: bool, no_depth: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = no_depth
	if no_depth:
		m.render_priority = 8
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
	return m


## A crescent (ring segment) in the local Y-Z plane, +Z forward, from angle `a0` to `a1` (radians from +Z toward
## +Y), between radii `r_in` and `r_out`. Alpha rises toward the leading (a1) end.
static func arc_mesh(r_in: float, r_out: float, a0: float, a1: float, segments: int, color: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner := maxf(r_in, r_out * 0.45)
	for i in segments:
		var s0 := float(i) / segments
		var s1 := float(i + 1) / segments
		var b0 := lerpf(a0, a1, s0)
		var b1 := lerpf(a0, a1, s1)
		var c0 := Color(color.r, color.g, color.b, color.a * sin(PI * s0) * (0.35 + 0.65 * s0))
		var c1 := Color(color.r, color.g, color.b, color.a * sin(PI * s1) * (0.35 + 0.65 * s1))
		var o0 := Vector3(0.0, sin(b0), cos(b0))
		var o1 := Vector3(0.0, sin(b1), cos(b1))
		var ci0 := Color(c0, c0.a * 0.15)
		var ci1 := Color(c1, c1.a * 0.15)
		st.set_color(ci0); st.add_vertex(o0 * inner)
		st.set_color(c0); st.add_vertex(o0 * r_out)
		st.set_color(c1); st.add_vertex(o1 * r_out)
		st.set_color(ci0); st.add_vertex(o0 * inner)
		st.set_color(c1); st.add_vertex(o1 * r_out)
		st.set_color(ci1); st.add_vertex(o1 * inner)
	return st.commit()


## A flat thrust spike along +Z from `near` to `far` (a long diamond), lying in the ground plane.
static func spike_mesh(near: float, far: float, half_width: float, color: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mid := lerpf(near, far, 0.3)
	var tail := Color(color, 0.0)
	var pts := [Vector3(0, 0, near), Vector3(half_width, 0, mid), Vector3(0, 0, far + 0.08), Vector3(-half_width, 0, mid)]
	var cols := [tail, color, color, color]
	for tri in [[0, 1, 2], [0, 2, 3]]:
		for idx in tri:
			st.set_color(cols[idx])
			st.add_vertex(pts[idx])
	return st.commit()


## A billboarded starburst of `points` spikes and radius `radius`: an additive glow, or alpha-blended when it must
## read on bright ground (the critical-hit star).
static func make_burst(radius: float, color: Color, points: int, no_depth: bool, additive: bool = true) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Color(color, color.a)
	var rim := Color(color, 0.0)
	var n := points * 2
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var r0 := radius if i % 2 == 0 else radius * 0.42
		var r1 := radius if (i + 1) % 2 == 0 else radius * 0.42
		st.set_color(center); st.add_vertex(Vector3.ZERO)
		st.set_color(rim); st.add_vertex(Vector3(cos(a0) * r0, sin(a0) * r0, 0.0))
		st.set_color(rim); st.add_vertex(Vector3(cos(a1) * r1, sin(a1) * r1, 0.0))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := fx_material(true, no_depth)
	if not additive:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
