extends TestCase
## MapInstanceView without a scene tree (MAP_ARCHITECTURE.md section 4.7.4): slot monsters, the debug console's
## NO_SLOT spawns (SpawnSlot.synthetic, index -1) and debug_kill(node). Pure data underneath (MapInstanceState) and
## a stub factory, so it runs anywhere (no export needed).


## A monster with its own death, like the monster system's Monster: die() emits `died`.
class DyingMob extends Node3D:
	signal died(mob: Node3D)
	var hp: int = 10
	var deaths: int = 0

	func die() -> void:
		deaths += 1
		died.emit(self)


var view: MapInstanceView = null
var state: MapInstanceState = null
var def: MapDefinition = null
var t: float = 0.0
var released: Array[Node3D] = []
## Factory output: DyingMob when true, else a plain Node3D (a proxy without a death).
var with_death: bool = true


func before_each() -> void:
	var defs := MapDefinitions.build(db())
	def = defs.get_def("000000040")
	var r := RandomNumberGenerator.new()
	r.seed = 5
	t = 0.0
	state = MapInstanceState.fresh(def, defs.spawn_model, r, t)
	released.clear()
	with_death = true
	view = MapInstanceView.new()
	view.clock = func() -> float: return t
	view.monster_factory = func(_mob: String, slot: SpawnSlot) -> Node3D:
		var n: Node3D = DyingMob.new() if with_death else Node3D.new()
		n.transform = slot.transform
		return n
	view.monster_releaser = func(n: Node3D) -> void:
		released.append(n)
	view.realize(state, def, Vector3.ZERO)
	view._process(0.0)  # no tuning: the whole queue spawns at once


func after_each() -> void:
	for n in view.get_children():
		n.free()
	for n in released:
		if is_instance_valid(n):
			n.free()
	view.free()


## A debug spawn the way the console makes one: the factory with a synthetic slot, parented under the view.
func debug_spawn() -> Node3D:
	var slot := SpawnSlot.synthetic("2", Transform3D(Basis.IDENTITY, Vector3(1, 0, 1)))
	var n: Node3D = view.monster_factory.call("2", slot)
	n.set_meta("debug_spawn", true)
	n.set_meta("spawn_slot", slot.index)
	view.add_child(n)
	return n


func test_slots_spawn_and_debug_spawns_stay_outside_the_slot_state() -> void:
	assert_eq(view.live_count(), state.alive_count(), "every alive slot realized")
	var alive_before := state.alive_count()
	var dbg := debug_spawn()
	assert_eq(view.slot_of(dbg), SpawnSlot.NO_SLOT, "a debug spawn occupies no slot")
	assert_false(view.notify_killed(SpawnSlot.NO_SLOT), "notify_killed(-1) records nothing")
	assert_false(view.notify_node_killed(dbg), "notify_node_killed(debug spawn) records nothing")
	assert_eq(state.alive_count(), alive_before, "slot state untouched")
	(dbg as DyingMob).die()
	assert_eq(state.alive_count(), alive_before, "its own death is not connected to the view")
	t = 1000.0
	view._process(0.0)
	assert_false(view.nodes.values().has(dbg), "never adopted as a slot monster")
	assert_eq(view.live_count(), state.alive_count(), "only slot monsters are live")


func test_debug_kill_of_a_slot_monster_runs_its_death_and_records_the_slot() -> void:
	var i: int = state.alive_indices()[0]
	var n: Node3D = view.nodes[i]
	var out := view.debug_kill(n)
	assert_true(bool(out.own_death), "the monster's own die() ran")
	assert_eq(int(out.slot), i, "its slot")
	assert_true(bool(out.recorded), "the died signal recorded the kill")
	assert_eq((n as DyingMob).deaths, 1, "died once")
	assert_false(state.is_alive(i), "slot dead")
	assert_false(view.nodes.has(i), "node handed back")
	assert_true(released.has(n), "through the releaser")


func test_debug_kill_of_a_debug_spawn_never_touches_a_slot() -> void:
	var alive_before := state.alive_count()
	var dbg := debug_spawn()
	var out := view.debug_kill(dbg)
	assert_true(bool(out.own_death), "its own death ran (EXP and drops in the game)")
	assert_eq(int(out.slot), SpawnSlot.NO_SLOT, "no slot")
	assert_false(bool(out.recorded), "no kill recorded")
	assert_eq(state.alive_count(), alive_before, "slot state untouched")


func test_debug_kill_without_a_death_method() -> void:
	view.release()
	released.clear()
	with_death = false
	view.realize(state, def, Vector3.ZERO)
	view._process(0.0)
	var i: int = state.alive_indices()[0]
	var n: Node3D = view.nodes[i]
	var out := view.debug_kill(n)
	assert_false(bool(out.own_death), "no death method")
	assert_true(bool(out.recorded), "the slot kill is recorded directly")
	assert_false(state.is_alive(i), "slot dead")
	var alive_before := state.alive_count()
	var dbg := debug_spawn()
	var out2 := view.debug_kill(dbg)
	assert_false(bool(out2.recorded), "a debug spawn is only released")
	assert_true(released.has(dbg), "released through the releaser")
	assert_eq(state.alive_count(), alive_before, "slot state untouched")


func test_a_stale_node_cannot_kill_a_live_slot() -> void:
	var i: int = state.alive_indices()[0]
	var old: Node3D = view.nodes[i]
	view.release()
	view.realize(state, def, Vector3.ZERO)
	view._process(0.0)
	assert_true(state.is_alive(i), "the slot is alive again in the new realize")
	assert_false(view.notify_node_killed(old), "the released node no longer speaks for the slot")
	assert_true(state.is_alive(i), "still alive")
