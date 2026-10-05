class_name PlayerTestWorld
extends RefCounted
## A throwaway physics world for player tests and the sandbox feel lab: primitive collision (boxes, ramps,
## steps), one PlayerController driven by a BotInput, and a synchronous tick loop.
##
## Works synchronously (inside a test method): nodes are added under the running scene and queried through the
## physics space immediately, and the controller advances with step(1/60) instead of waiting for frames.
##
##   var w := PlayerTestWorld.create(db())
##   w.add_box(Vector3(0, -0.5, 0), Vector3(40, 1, 40))      # floor, top at y = 0
##   var p := w.spawn_player(Vector3(0, 0, 0))
##   w.bot.world_dir = Vector3.RIGHT
##   w.run(60)
##   w.free_all()                                             # always, or the bodies leak into later tests

const TICK := 1.0 / 60.0

var host: Node3D = null
var player: PlayerController = null
var bot: BotInput = BotInput.new()
var db: ContentDB = null


## A new empty world hosted under the running scene (the test runner during tests).
static func create(content: ContentDB, parent: Node = null) -> PlayerTestWorld:
	var w := PlayerTestWorld.new()
	w.db = content
	w.host = Node3D.new()
	w.host.name = "PlayerTestWorld"
	var p := parent if parent != null else _default_parent()
	p.add_child(w.host)
	return w


static func _default_parent() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree.current_scene != null:
		return tree.current_scene
	return tree.root.get_child(tree.root.get_child_count() - 1)


## A static box (center, full size), optionally rotated (degrees, Euler XYZ).
func add_box(center: Vector3, size: Vector3, rotation_deg: Vector3 = Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	# Set the transform before entering the tree: a transform change of a body already in the tree reaches the
	# physics server only at the frame's transform flush, which never happens inside a synchronous test.
	body.position = center
	body.rotation_degrees = rotation_deg
	host.add_child(body)
	return body


## A ramp rising along +X from (x0, base_y) with the given slope angle and horizontal run; width along Z.
## Its top surface passes through (x0, base_y) and (x0 + run, base_y + run * tan(angle)).
func add_ramp(x0: float, base_y: float, z_center: float, angle_deg: float, run: float, width: float) -> StaticBody3D:
	var a := deg_to_rad(angle_deg)
	var length := run / cos(a)
	var thickness := 0.5
	var mid_top := Vector3(x0 + run * 0.5, base_y + run * 0.5 * tan(a), z_center)
	var normal := Vector3(-sin(a), cos(a), 0.0)
	var center := mid_top - normal * thickness * 0.5
	return add_box(center, Vector3(length, thickness, width), Vector3(0.0, 0.0, angle_deg))


## A trimesh (ConcavePolygonShape3D) floor quad at height y, like the exported Ground-colonly meshes.
func add_trimesh_floor(center: Vector3, half_extent: float, cells: int = 8) -> StaticBody3D:
	var faces := PackedVector3Array()
	var step := half_extent * 2.0 / cells
	for i in cells:
		for j in cells:
			var x0 := center.x - half_extent + i * step
			var z0 := center.z - half_extent + j * step
			var a := Vector3(x0, center.y, z0)
			var b := Vector3(x0 + step, center.y, z0)
			var c := Vector3(x0 + step, center.y, z0 + step)
			var d := Vector3(x0, center.y, z0 + step)
			faces.append_array([a, b, c, a, c, d])  # clockwise seen from above: front faces point up
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	host.add_child(body)
	return body


## Adds a node (e.g. an instantiated collision glb) to the world. Set its transform before calling this.
func add_node(n: Node) -> Node:
	host.add_child(n)
	return n


## Spawns the player (feet at `feet`), driven by this world's BotInput, using the shipped movement data.
func spawn_player(feet: Vector3, facing: Vector3 = Vector3.ZERO) -> PlayerController:
	var p := PlayerController.new()
	p.name = "Player"
	p.use_autoloads = false
	p.model = MovementModel.from_db(db)
	p.set_input_source(bot)
	host.add_child(p)
	var xf := Transform3D(Basis.IDENTITY, feet)
	if facing.length_squared() > 0.0001:
		var f := Vector3(facing.x, 0.0, facing.z).normalized()
		xf.basis = Basis(Vector3.UP.cross(f).normalized(), Vector3.UP, f)
	p.teleport(xf)
	player = p
	return p


## Advances the player `ticks` physics ticks. `before_tick` (optional) is called with the tick index first.
func run(ticks: int, before_tick: Callable = Callable()) -> void:
	for i in ticks:
		if before_tick.is_valid():
			before_tick.call(i)
		player.step(TICK)


## Runs until `done` returns true or `max_ticks` pass; returns the ticks used (or -1 on timeout).
func run_until(done: Callable, max_ticks: int, before_tick: Callable = Callable()) -> int:
	for i in max_ticks:
		if before_tick.is_valid():
			before_tick.call(i)
		player.step(TICK)
		if done.call():
			return i + 1
	return -1


## Frees every node of this world immediately.
func free_all() -> void:
	if host != null and is_instance_valid(host):
		host.get_parent().remove_child(host)
		host.free()
	host = null
	player = null
