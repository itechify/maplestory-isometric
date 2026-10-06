class_name DebugCommands
extends RefCounted
## The built-in debug console commands (brief Phase 20), registered on a DebugTools node by install().
##
## Every command goes through the systems' own APIs, never around them: MapSession (debug_warp, reload_map,
## respawn, report_monster_killed), PortalGraph.set_link_mode, Game (gain_exp, allocate_ap, rng), ItemService
## (gain, gain_mesos, spend_mesos, clear_inventory), Progression, DropRoller.simulate, the QuestService, and the
## world's MapInstanceView.monster_factory for debug spawns. Commands another system already registers are reused:
## save / load / saves / delete_save / reset_save (Game), map_* (MapSession), quests / quest_* (QuestService);
## "reset" is an alias of reset_save and "quest accept|complete|reset" call quest_accept|complete|reset.
##
## Debug spawns ("spawn") are non-canonical: they never occupy a spawn slot, carry the metadata debug_spawn = true
## and spawn_slot = -1, and are removed when the map is left or reloaded.

const QUEST_FALLBACK_NOTE := "(debug fallback quest service: not attached to Events, so play does not progress quests)"
## Sanity bounds for console input (engineering limits, not gameplay values).
const MAX_SPAWN := 50
const MAX_TIME_SCALE := 16.0
const MIN_TIME_SCALE := 0.01
const DEFAULT_SIM_KILLS := 1000
## Ring the debug spawns stand on around the player (m) and the extra radius per ring of 8.
const SPAWN_RING_M := 1.5
const SPAWN_RING_STEP_M := 0.75

var dbg: DebugTools
## Monsters made by "spawn" (never in a slot).
var debug_spawns: Array[Node3D] = []
## The unattached QuestService the console uses when no system registered quest commands (null otherwise).
var fallback_quests: QuestService = null


func _init(debug: DebugTools) -> void:
	dbg = debug


## Registers every built-in command, its Tab completion and the aliases.
func install() -> void:
	var d := dbg
	d.register_command("help", "help [command]: every command with its help, or one command in detail", _cmd_help)
	d.register_command("clear", "clear: clear the console output", _cmd_clear)
	# Maps and portals.
	d.register_command("warp", "warp <map> [portal]: teleport to a map (MeowDB id, v8 id or name) at player_spawns[0], or at a portal's arrival", _cmd_warp)
	d.register_command("portals", "portals [map]: the portals of a map (default: current) with destination, link mode and type", _cmd_portals)
	d.register_command("where", "where: current map, session state, last transition, position and region", _cmd_where)
	d.register_command("maps", "maps: the 25 maps with ids, v8 ids, names and counts", _cmd_maps)
	d.register_command("reload", "reload: fresh monsters for the current map (MapSession.reload_map); removes debug spawns", _cmd_reload)
	d.register_command("linkmode", "linkmode [warp|edge] [link|all]: show or switch portal link modes (edge = walk the trail through its gates; doors are always warp)", _cmd_linkmode)
	d.register_command("respawn", "respawn: respawn a dead character at its return map", _cmd_respawn)
	d.register_command("goto", "goto <x> <z> | goto slot <n> | goto npc <id|name> | goto portal <id>: move the player inside the current map", _cmd_goto)
	# Overlay and draw layers.
	d.register_command("overlay", "overlay [on|off]: the F3 overlay (FPS, map, session, position, player, monsters, camera)", _cmd_overlay.bind("overlay"))
	d.register_command("showmap", "showmap [on|off]: toggle the overlay and print the current map", _cmd_overlay.bind("showmap"))
	d.register_command("coords", "coords [on|off]: toggle the overlay and print the position (world, map-local, region)", _cmd_overlay.bind("coords"))
	d.register_command("collision", "collision [on|off]: wireframe of the current map's collision (walkable green, blocking orange, scenery blue)", _cmd_layer.bind("collision"))
	d.register_command("spawns", "spawns [on|off]: spawn areas and slots (alive green, dead red), live and debug monsters", _cmd_layer.bind("spawns"))
	d.register_command("portaldata", "portaldata [on|off]: portal triggers, arrivals and labels (name -> destination, link mode, type)", _cmd_layer.bind("portals"))
	d.register_command("npcs", "npcs [on|off]: NPC anchors with talk range and labels", _cmd_layer.bind("npcs"))
	d.register_command("bounds", "bounds [on|off]: camera bounds and the live camera view", _cmd_layer.bind("camera"))
	d.register_command("mobregion", "mobregion [on|off]: the mob region (layout footprint inset)", _cmd_layer.bind("mobregion"))
	d.register_command("rings", "rings [on|off]: the current map's containment ring", _cmd_layer.bind("rings"))
	d.register_command("safeground", "safeground [on|off]: the SafeGround point and the fall-recovery height", _cmd_layer.bind("safeground"))
	d.register_command("draw", "draw [layer|all] [on|off]: list or toggle debug draw layers (%s)" % ", ".join(DebugTools.LAYERS), _cmd_draw)
	# Monsters.
	d.register_command("spawn", "spawn <monster> [n]: n debug monsters around the player (non-canonical, never in a slot)", _cmd_spawn)
	d.register_command("kill", "kill [nearest|all]: kill live monsters (their own death path when they have one)", _cmd_kill)
	d.register_command("drops", "drops <monster|owner id> [kills] [seed]: simulate kills with DropRoller (canonical records: MeowDB membership and Henesys.gg rarity; chances from the owner's table drop_rates.json, mesos from meso_rules.json; the character's quests gate quest drops); lists unresolved members", _cmd_drops)
	d.register_command("monsters", "monsters [name]: search monster ids", _cmd_search.bind("monsters"))
	# Character.
	d.register_command("exp", "exp <n>: gain n EXP through Game.gain_exp (level-ups, AP, SP, HP/MP as in play)", _cmd_exp)
	d.register_command("level", "level <n>: set the level through Progression (up: the exact EXP per level; down: the gains taken back)", _cmd_level)
	d.register_command("ap", "ap <str|dex|int|luk> [n]: spend unspent AP (Game.allocate_ap)", _cmd_ap)
	d.register_command("heal", "heal: restore HP and MP to their maxima", _cmd_heal)
	d.register_command("god", "god [on|off]: player invulnerable and HP locked at max", _cmd_god)
	d.register_command("char", "char: level, EXP, HP/MP, stats, AP/SP, mesos", _cmd_char)
	# Items.
	d.register_command("mesos", "mesos <n>: add (or with a negative n spend) mesos", _cmd_mesos)
	d.register_command("give", "give <item id|name> [qty]: put items in the inventory (ItemService.gain)", _cmd_give)
	d.register_command("clearinv", "clearinv [equip|use|setup|etc|cash]: empty the inventory (one tab or all)", _cmd_clearinv)
	d.register_command("inv", "inv: list the inventory, equipment and mesos", _cmd_inv)
	d.register_command("items", "items [name]: search item ids", _cmd_search.bind("items"))
	# Quests (a dispatcher over the QuestService's own commands).
	d.register_composite("quest", "quest accept|complete|forfeit|reset <id> | quest <id>: quest actions and status (complete <id> force satisfies objectives first)", _cmd_quest)
	# Engine.
	d.register_command("timescale", "timescale [x]: show or set Engine.time_scale (0.01 - 16)", _cmd_timescale)
	d.register_command("seed", "seed [n]: show or reseed the gameplay RNG (Game.rng)", _cmd_seed)
	d.register_command("screenshot", "screenshot [path]: save the next frame without the console (default user://screenshots/)", _cmd_screenshot)
	_install_quest_commands()
	d.register_alias("reset", "reset_save")
	d.register_alias("tp", "warp")
	d.register_alias("mobs", "monsters")
	d.set_completion("warp", ["map", "portal"])
	d.set_completion("map_warp", ["map", "portal"])
	d.set_completion("portals", ["map"])
	d.set_completion("linkmode", ["link_mode", "link"])
	d.set_completion("map_link_mode", ["link", "link_mode"])
	for c in ["overlay", "showmap", "coords", "collision", "spawns", "portaldata", "npcs", "bounds", "mobregion",
			"rings", "safeground", "god"]:
		d.set_completion(c, ["on_off"])
	d.set_completion("draw", ["layer", "on_off"])
	d.set_completion("spawn", ["monster"])
	d.set_completion("drops", ["monster"])
	d.set_completion("kill", ["kill"])
	d.set_completion("give", ["item"])
	d.set_completion("clearinv", ["tab"])
	d.set_completion("ap", ["stat"])
	d.set_completion("quest", ["quest_sub", "quest"])
	for c in ["quest_accept", "quest_complete", "quest_reset"]:
		d.set_completion(c, ["quest"])
	d.set_completion("help", ["command"])
	d.set_completion("goto", [["slot", "npc", "portal"]])
	# Debug spawns leave with their map: Events.map_left, and the session's own transition_started (a private session
	# in tests emits on the Events autoload, not on an injected bus).
	var cb := Callable(self, "_on_map_left")
	var bus := d.get_bus()
	if bus != null and bus.has_signal("map_left") and not bus.is_connected("map_left", cb):
		bus.connect("map_left", cb)
	var s := d.get_session()
	if s != null and s.has_signal("transition_started"):
		var cb2 := Callable(self, "_on_transition_started")
		if not s.is_connected("transition_started", cb2):
			s.connect("transition_started", cb2)


## Makes quest_accept / quest_complete / quest_reset / quests available now: the live QuestService's own commands
## (Game.quests registers them again, deferred, which changes nothing), or an unattached fallback service when the
## game has none.
func _install_quest_commands() -> void:
	if dbg.has_command("quest_accept"):
		return
	var g := dbg.get_game()
	var live: Variant = g.get("quests") if g != null else null
	if live is QuestService:
		(live as QuestService).register_debug_commands(dbg)
		return
	fallback_quests = QuestService.create(dbg.get_bus(), dbg.get_db(), dbg.get_character(), dbg.get_rng(),
		func() -> float: return dbg.get_clock())
	fallback_quests.character_provider = func() -> CharacterState: return dbg.get_character()
	fallback_quests.register_debug_commands(dbg)


# --- help -----------------------------------------------------------------------------------------------------

func _cmd_help(args: PackedStringArray) -> String:
	if not args.is_empty():
		var key := args[0].to_lower()
		if dbg.resolve_name(key) != key:
			var target := dbg.resolve_name(key)
			return "%s: alias of %s\n%s" % [key, target, _help_line(target) if dbg.has_command(target) else "(%s is not registered yet)" % target]
		if not dbg.has_command(key):
			return "unknown command: %s" % key
		var text := _help_line(key)
		if dbg.shadowed_help(key) != "":
			text += "\n  falls back to: " + dbg.shadowed_help(key)
		return text
	var names := dbg.command_names()
	var lines: PackedStringArray = ["%d commands (help <command> for one; Tab completes; ';' separates commands; quote names with spaces):" % names.size()]
	for n in names:
		lines.append("  " + _help_line(n))
	var aliases: PackedStringArray = []
	for a in dbg.alias_names():
		aliases.append("%s -> %s" % [a, dbg.resolve_name(a)])
	if not aliases.is_empty():
		lines.append("aliases: " + ", ".join(aliases))
	return "\n".join(lines)


func _help_line(cmd: String) -> String:
	var h := dbg.command_help(cmd)
	if h == "":
		return cmd
	return h if h.begins_with(cmd) else "%s: %s" % [cmd, h]


func _cmd_clear(_args: PackedStringArray) -> String:
	dbg.clear_requested.emit()
	return ""


# --- maps -----------------------------------------------------------------------------------------------------

func _cmd_warp(args: PackedStringArray) -> String:
	if args.is_empty():
		return "usage: warp <map> [portal]   map: MeowDB id (000000040), v8 id (40000) or a name (snail hunting ground 1)"
	var s := dbg.get_session()
	if s == null or not s.has_method("debug_warp"):
		return "warp: no MapSession"
	var defs := dbg.get_defs()
	var t := resolve_map_and_portal(args, defs)
	if not bool(t.ok):
		return "warp: " + String(t.error)
	var map := String(t.map)
	var portal := String(t.portal)
	var err := int(s.call("debug_warp", map, portal))
	if err != OK:
		return "warp failed: %s" % String(s.get("last_error"))
	var def := defs.get_def(map)
	var at := "%s's arrival" % portal if portal != "" else "player_spawns[0]"
	if dbg.current_map() == map and bool(s.call("is_idle")):
		return "warped to %s %s at %s" % [map, def.map_name, at]
	if s.has_signal("transition_finished"):
		# The fades take a few frames: report the arrival (with its grounding frames) when it completes.
		s.connect("transition_finished", func(rec: TransitionRecord) -> void:
			dbg.message.emit("arrived: %s" % DebugReport.transition_text(rec)), CONNECT_ONE_SHOT)
	return "warping to %s %s at %s (session %s)" % [map, def.map_name, at, String(s.call("state_name"))]


## Map and optional portal from warp arguments: "<map> [portal]", or a multi-word map name with or without a
## trailing portal id. {"ok", "map", "portal", "error"}.
static func resolve_map_and_portal(args: PackedStringArray, defs: MapDefinitions) -> Dictionary:
	var first := DebugResolve.map_id(args[0], defs)
	var portal_error := ""
	if bool(first.ok):
		if args.size() == 1:
			return {"ok": true, "map": first.id, "portal": "", "error": ""}
		if args.size() == 2:
			var p := DebugResolve.portal_id(args[1], defs.get_def(String(first.id)))
			if bool(p.ok):
				return {"ok": true, "map": first.id, "portal": p.id, "error": ""}
			portal_error = String(p.error)
	var whole := DebugResolve.map_id(" ".join(args), defs)
	if bool(whole.ok):
		return {"ok": true, "map": whole.id, "portal": "", "error": ""}
	if args.size() >= 2:
		var head := DebugResolve.map_id(" ".join(args.slice(0, args.size() - 1)), defs)
		if bool(head.ok):
			var p2 := DebugResolve.portal_id(args[args.size() - 1], defs.get_def(String(head.id)))
			if bool(p2.ok):
				return {"ok": true, "map": head.id, "portal": p2.id, "error": ""}
			return {"ok": false, "map": "", "portal": "", "error": String(p2.error)}
	if portal_error != "":
		return {"ok": false, "map": "", "portal": "", "error": portal_error}
	return {"ok": false, "map": "", "portal": "", "error": String(whole.error if args.size() > 1 else first.error)}


func _cmd_portals(args: PackedStringArray) -> String:
	var map := dbg.current_map()
	if not args.is_empty():
		var r := DebugResolve.map_id(" ".join(args), dbg.get_defs())
		if not bool(r.ok):
			return "portals: " + String(r.error)
		map = String(r.id)
	if map == "":
		return "portals: no current map (give one: portals <map>)"
	return DebugReport.portals_text(dbg, map)


func _cmd_where(_args: PackedStringArray) -> String:
	return DebugReport.where_text(dbg)


func _cmd_maps(_args: PackedStringArray) -> String:
	return DebugReport.maps_text(dbg)


func _cmd_reload(_args: PackedStringArray) -> String:
	var s := dbg.get_session()
	if s == null or not s.has_method("reload_map"):
		return "reload: no MapSession"
	var map := dbg.current_map()
	var removed := clear_debug_spawns()
	if int(s.call("reload_map")) != OK:
		return "reload: needs an idle session with a current map (session %s, map '%s')" % [String(s.call("state_name")), map]
	var inst: MapInstanceState = s.get("instance_state")
	return "reloaded %s %s: fresh instance, %d/%d slots alive (capacity %d)%s" % [map, dbg.get_defs().get_def(map).map_name,
		inst.alive_count(), inst.slots.size(), inst.capacity, ", %d debug spawns removed" % removed if removed > 0 else ""]


func _cmd_linkmode(args: PackedStringArray) -> String:
	var graph := dbg.get_defs().graph
	if args.is_empty():
		var counts := {}
		for id in graph.links:
			var m := String(graph.links[id].mode)
			counts[m] = int(counts.get(m, 0)) + 1
		var forced := dbg.get_defs().tuning.forced_link_mode()
		return "%d links: %s%s" % [graph.links.size(), JSON.stringify(counts), (" (forced %s by portal_adaptations.json)" % forced) if forced != "" else ""]
	var mode := args[0].to_lower()
	var link := args[1] if args.size() > 1 else "all"
	var err := graph.set_link_mode(link, mode)
	match err:
		OK:
			return "link mode %s for %s" % [mode, "all %d links" % graph.links.size() if link == "all" else link]
		ERR_UNAVAILABLE:
			return "linkmode %s: %s is a door link; doors are always warp" % [mode, link]
		ERR_DOES_NOT_EXIST:
			return "linkmode: unknown link %s (Tab lists the link ids)" % link
		_:
			return "linkmode: mode must be warp or edge, not '%s'" % mode


func _cmd_respawn(_args: PackedStringArray) -> String:
	var s := dbg.get_session()
	if s == null or not s.has_method("respawn"):
		return "respawn: no MapSession"
	var err := int(s.call("respawn"))
	if err != OK:
		return "respawn: %s" % String(s.get("last_error"))
	return "respawning in %s" % dbg.current_map()


## Moves the player inside the current map (the map does not change): to a world x/z, a spawn slot, an NPC or a
## portal's arrival point, grounded and placed through IslandWorld.place_player (which also resets fall recovery).
func _cmd_goto(args: PackedStringArray) -> String:
	var usage := "usage: goto <x> <z> | goto slot <n> | goto npc <id|name> | goto portal <id>"
	if args.is_empty():
		return usage
	var w := dbg.get_world()
	var p := dbg.get_player()
	if w == null or p == null or not w.has_method("place_player"):
		return "goto: needs the world and a player"
	var map := dbg.current_map()
	var def := dbg.get_defs().get_def(map) if map != "" else null
	if def == null:
		return "goto: no current map"
	var target := Vector3.ZERO
	var what := ""
	match args[0].to_lower():
		"slot":
			if args.size() < 2 or not args[1].is_valid_int() or int(args[1]) < 0 or int(args[1]) >= def.monster_spawn_definitions.size():
				return "goto slot: %s has slots 0..%d" % [map, def.monster_spawn_definitions.size() - 1]
			target = def.monster_spawn_definitions[int(args[1])].transform.origin
			what = "slot %s" % args[1]
		"npc":
			var key := " ".join(args.slice(1)).to_lower()
			for n in def.npc_definitions:
				if n.npc_id == key or n.npc_name.to_lower().contains(key):
					target = n.transform.origin
					what = "npc %s %s" % [n.npc_id, n.npc_name]
					break
			if what == "":
				return "goto npc: no NPC '%s' in %s" % [key, map]
		"portal":
			var r := DebugResolve.portal_id(args[1] if args.size() > 1 else "", def)
			if not bool(r.ok):
				return "goto portal: " + String(r.error)
			target = def.portal(String(r.id)).spawn_transform.origin
			what = "portal %s arrival" % r.id
		_:
			if args.size() < 2 or not args[0].is_valid_float() or not args[1].is_valid_float():
				return usage
			target = Vector3(float(args[0]), p.global_position.y, float(args[1]))
			what = "x %s z %s" % [args[0], args[1]]
	if not def.footprint_contains(target):
		return "goto: %s is outside %s (use warp for other maps)" % [DebugReport.vec(target), map]
	# Slots, NPCs and arrivals are already on the ground; a typed x/z is probed through the map's whole height.
	var g := _ground(w, Vector3(target.x, def.y_max + 1.0, target.z), 0.0, def.y_max - def.y_min + 2.0) \
		if what.begins_with("x ") else _ground(w, target + Vector3.UP * 0.5)
	if not bool(g.ok):
		return "goto: no walkable ground at %s" % DebugReport.vec(target)
	w.call("place_player", Transform3D(p.global_transform.basis.orthonormalized(), g.pos))
	return "moved to %s at %s" % [what, DebugReport.vec(g.pos)]


# --- overlay and layers ---------------------------------------------------------------------------------------

func _cmd_overlay(args: PackedStringArray, which: String) -> String:
	var t := parse_toggle(args, dbg.overlay_enabled)
	if not bool(t.ok):
		return "usage: %s [on|off]" % which
	dbg.set_overlay(bool(t.on))
	var head := "overlay %s" % ("on" if bool(t.on) else "off")
	match which:
		"showmap":
			var map := dbg.current_map()
			var def := dbg.get_defs().get_def(map) if map != "" else null
			return "%s\n%s" % [head, "%s %s (%s)" % [map, def.map_name, def.street_name] if def != null else "no current map"]
		"coords":
			return "%s\n%s" % [head, "\n".join(DebugReport.position_lines(dbg))]
	return "%s\n%s" % [head, dbg.overlay_text()]


func _cmd_layer(args: PackedStringArray, layer: String) -> String:
	var t := parse_toggle(args, dbg.is_layer_on(layer))
	if not bool(t.ok):
		return "usage: [on|off] (layer %s)" % layer
	dbg.set_layer(layer, bool(t.on))
	return "%s layer %s%s" % [layer, "on" if bool(t.on) else "off", _layer_note(layer, bool(t.on))]


func _cmd_draw(args: PackedStringArray) -> String:
	if args.is_empty():
		var rows: PackedStringArray = []
		for l in DebugTools.LAYERS:
			rows.append("%s %s" % [l, "on" if dbg.is_layer_on(l) else "off"])
		return "layers: " + ", ".join(rows)
	var name := args[0].to_lower()
	var targets: PackedStringArray = DebugTools.LAYERS if name == "all" else PackedStringArray([name])
	if name != "all" and not (name in DebugTools.LAYERS):
		return "draw: unknown layer %s (layers: %s, all)" % [name, ", ".join(DebugTools.LAYERS)]
	var current := dbg.is_layer_on(targets[0])
	var t := parse_toggle(args.slice(1), current)
	if not bool(t.ok):
		return "usage: draw [layer|all] [on|off]"
	var out: PackedStringArray = []
	for l in targets:
		dbg.set_layer(l, bool(t.on))
		out.append("%s %s%s" % [l, "on" if bool(t.on) else "off", _layer_note(l, bool(t.on))])
	return "\n".join(out)


func _layer_note(layer: String, on: bool) -> String:
	if not on:
		return ""
	var d := dbg.ensure_draw()
	if d == null:
		return " (no world loaded: drawn once one is attached)"
	d.rebuild_now()
	var st := d.layer_stats(layer)
	return " (%d lines, %d labels in %s)" % [int(st.segments), int(st.labels), dbg.current_map()]


## "on"/"off"/"toggle" (or nothing = toggle). {"ok", "on"}.
static func parse_toggle(args: PackedStringArray, current: bool) -> Dictionary:
	if args.is_empty():
		return {"ok": true, "on": not current}
	match args[0].to_lower():
		"on", "1", "true", "yes":
			return {"ok": true, "on": true}
		"off", "0", "false", "no":
			return {"ok": true, "on": false}
		"toggle":
			return {"ok": true, "on": not current}
	return {"ok": false, "on": current}


# --- monsters -------------------------------------------------------------------------------------------------

func _cmd_spawn(args: PackedStringArray) -> String:
	if args.is_empty():
		return "usage: spawn <monster id|name> [n]"
	var n := 1
	var words := args
	if args.size() >= 2 and args[args.size() - 1].is_valid_int():
		n = int(args[args.size() - 1])
		words = args.slice(0, args.size() - 1)
	var r := DebugResolve.monster_id(" ".join(words), dbg.get_db())
	if not bool(r.ok):
		return "spawn: " + String(r.error)
	if n < 1 or n > MAX_SPAWN:
		return "spawn: n must be 1..%d" % MAX_SPAWN
	var w := dbg.get_world()
	var view: Variant = w.get("instance_view") if w != null else null
	if not (view is MapInstanceView):
		return "spawn: needs the world (no IslandWorld is attached); debug spawns are nodes and never touch the slot state"
	var map := dbg.current_map()
	var def := dbg.get_defs().get_def(map) if map != "" else null
	if def == null:
		return "spawn: no current map"
	var mv := view as MapInstanceView
	var factory: Callable = mv.monster_factory if mv.monster_factory.is_valid() else Callable(mv, "default_factory")
	var p := dbg.get_player()
	var center := p.global_position if p != null else def.player_spawn(0).origin
	var made := 0
	var start := debug_spawn_count()
	for i in n:
		var k := start + i
		var ring := floori(k / 8.0)
		var angle := TAU * float(k % 8) / 8.0 + 0.3 * ring
		var pos := center + Vector3(cos(angle), 0.0, sin(angle)) * (SPAWN_RING_M + SPAWN_RING_STEP_M * ring)
		var grounded := _ground(w, pos)
		pos = grounded.pos
		var slot := SpawnSlot.new()
		slot.index = -1
		slot.mob_id = String(r.id)
		slot.region = "debug"
		slot.placement = "debug"
		slot.grounded = bool(grounded.ok)
		slot.transform = Transform3D(MapDefinitions.facing_basis(center - pos), pos)
		var node: Variant = factory.call(String(r.id), slot)
		if not (node is Node3D):
			continue
		var m := node as Node3D
		m.set_meta("debug_spawn", true)
		m.set_meta("non_canonical", true)
		m.set_meta("spawn_slot", -1)
		m.set_meta("mob_id", String(r.id))
		m.set_meta("map_id", map)
		if m.has_meta("default_proxy"):
			m.remove_meta("default_proxy")  # the view's proxy pool never adopts a debug spawn
		if m.get_parent() == null:
			mv.add_child(m)
		m.global_transform = slot.transform
		if m.has_signal("died"):
			var argc := 0
			for sig in m.get_signal_list():
				if String(sig.name) == "died":
					argc = (sig.args as Array).size()
			m.connect("died", _on_debug_spawn_died.bind(m).unbind(argc))
		debug_spawns.append(m)
		made += 1
	var inst: Variant = dbg.get_session().get("instance_state") if dbg.get_session() != null else null
	var slots_note := ""
	if inst is MapInstanceState:
		slots_note = "; slots unchanged %d/%d alive" % [(inst as MapInstanceState).alive_count(), (inst as MapInstanceState).capacity]
	return "spawned %d x %s (%s) in %s near %s (debug, non-canonical, no slot%s)" % [made, _name("monsters", String(r.id)),
		r.id, map, DebugReport.vec(center), slots_note]


func _cmd_kill(args: PackedStringArray) -> String:
	var mode := args[0].to_lower() if not args.is_empty() else "nearest"
	if not (mode in ["nearest", "all"]):
		return "usage: kill [nearest|all]"
	var map := dbg.current_map()
	if map == "":
		return "kill: no current map"
	var w := dbg.get_world()
	var view: Variant = w.get("instance_view") if w != null else null
	if view is MapInstanceView:
		return _kill_nodes(view as MapInstanceView, mode, map)
	return _kill_slots(mode, map)


## World mode: live monster nodes (slot monsters and debug spawns).
func _kill_nodes(view: MapInstanceView, mode: String, map: String) -> String:
	var targets: Array[Node3D] = []
	for i in view.nodes:
		var n: Variant = view.nodes[i]
		if n is Node3D and is_instance_valid(n):
			targets.append(n)
	for n in debug_spawns:
		if is_instance_valid(n):
			targets.append(n)
	if targets.is_empty():
		return "kill: no live monsters in %s (%d queued to spawn)" % [map, view.pending_count()]
	if mode == "nearest":
		var p := dbg.get_player()
		var from := p.global_position if p != null else dbg.get_defs().get_def(map).player_spawn(0).origin
		targets.sort_custom(func(a: Node3D, b: Node3D) -> bool:
			return a.global_position.distance_squared_to(from) < b.global_position.distance_squared_to(from))
		targets.resize(1)
	var own := 0
	var fallback := 0
	var names: PackedStringArray = []
	for n in targets:
		names.append(_name("monsters", String(n.get_meta("mob_id", "?"))))
		if kill_node(n, view):
			own += 1
		else:
			fallback += 1
	var how: PackedStringArray = []
	if own > 0:
		how.append("%d through the monster's own death" % own)
	if fallback > 0:
		how.append("%d by freeing the slot + monster_killed (no EXP/drops: the node has no death method)" % fallback)
	return "killed %d in %s: %s (%s)" % [targets.size(), map, ", ".join(_summarize(names)), "; ".join(how)]


## Kills one monster node: its own zero-argument death method (debug_kill, kill or die) when it has one, else the
## slot is reported to MapSession / the view (debug spawns are freed) and Events.monster_killed is emitted.
## Returns true when the monster's own death path ran.
func kill_node(n: Node3D, view: MapInstanceView) -> bool:
	var method := zero_arg_method(n, ["debug_kill", "kill", "die"])
	var is_debug := n.has_meta("debug_spawn")
	if method != "":
		if is_debug:
			debug_spawns.erase(n)
		n.call(method)
		return true
	var mob := String(n.get_meta("mob_id", ""))
	var map := String(n.get_meta("map_id", dbg.current_map()))
	if is_debug:
		debug_spawns.erase(n)
		_release_debug(n, view)
	else:
		var s := dbg.get_session()
		var reported := s != null and s.has_method("report_monster_killed") and bool(s.call("report_monster_killed", n))
		if not reported:
			view.notify_node_killed(n)
	dbg.emit_event(&"monster_killed", [mob, map])
	return false


## No world (pure MapSession): kill alive slots in the instance state.
func _kill_slots(mode: String, map: String) -> String:
	var s := dbg.get_session()
	var st: Variant = s.get("instance_state") if s != null else null
	if not (st is MapInstanceState):
		return "kill: no map instance"
	var inst := st as MapInstanceState
	var alive := inst.alive_indices()
	if alive.is_empty():
		return "kill: no live monsters in %s" % map
	var chosen: PackedInt32Array = alive if mode == "all" else PackedInt32Array([alive[0]])
	var def := dbg.get_defs().get_def(map)
	var names: PackedStringArray = []
	var now := dbg.get_clock()
	for i in chosen:
		inst.kill(i, now)
		var mob := def.monster_spawn_definitions[i].mob_id
		names.append(_name("monsters", mob))
		dbg.emit_event(&"monster_killed", [mob, map])
	return "killed %d slot(s) in %s: %s (no world: slot state only, monster_killed emitted, no EXP/drops)" % [chosen.size(),
		map, ", ".join(_summarize(names))]


func _cmd_drops(args: PackedStringArray) -> String:
	if args.is_empty():
		return "usage: drops <monster id|name|owner id> [kills] [seed]"
	var words := args
	var nums: Array[int] = []
	while words.size() > 1 and words[words.size() - 1].is_valid_int() and nums.size() < 2:
		nums.push_front(int(words[words.size() - 1]))
		words = words.slice(0, words.size() - 1)
	var db := dbg.get_db()
	var owner := " ".join(words)
	if not db.has("drops", owner):  # a breakable's owner id ("0000001") is used as is; anything else names a monster
		var r := DebugResolve.monster_id(owner, db)
		if not bool(r.ok):
			return "drops: " + String(r.error)
		owner = String(r.id)
	var kills := nums[0] if nums.size() > 0 else DEFAULT_SIM_KILLS
	if kills < 1 or kills > 1000000:
		return "drops: kills must be 1..1000000"
	var rng := RandomNumberGenerator.new()
	rng.seed = nums[1] if nums.size() > 1 else 1
	var ctx := DropRoller.context_for(dbg.get_character())
	var quests := DropRates.quests_in_progress(ctx)
	var sim := DropRoller.simulate(owner, kills, db, rng, ctx)
	var table := db.drop_table(owner)
	var lines: PackedStringArray = ["%s (%s), %d kills, seed %d, quests in progress [%s] (canonical record drops/%s.json):" % [
		String(table.get("owner", {}).get("name", owner)), owner, kills, rng.seed, ", ".join(quests), owner]]
	var meso := DropRates.meso_rule(owner, db)
	if float(meso.chance) > 0.0:
		lines.append("  mesos %d total in %d bags (%.2f%%; configured %.2f%% of %d-%d, %s)" % [int(sim.mesos),
			int(sim.meso_drops), 100.0 * float(sim.meso_drops) / float(kills), 100.0 * float(meso.chance), int(meso.min),
			int(meso.max), meso.source])
	else:
		lines.append("  mesos: none (%s)" % meso.excluded)
	for e in DropRates.effective_entries(owner, db):
		var label := "%s %s" % [e.item_id if e.item_id != "" else "-", e.name]
		if e.excluded != "":
			lines.append("  %s: never rolls (%s)" % [label, e.excluded])
			continue
		var gate := " gated to quest %s%s" % [e.quest_gate, "" if quests.has(e.quest_gate) else " (not in progress)"] if e.quest_gate != "" else ""
		var n := int((sim.item_drops as Dictionary).get(e.item_id, 0))
		lines.append("  %s x%d (%d kills, %.4f%%; configured %.4f%%, %s)%s" % [label, int((sim.items as Dictionary).get(e.item_id, 0)),
			n, 100.0 * float(n) / float(kills), 100.0 * float(e.chance), e.source, gate])
	return "\n".join(lines)


func _cmd_search(args: PackedStringArray, domain: String) -> String:
	var rows := DebugResolve.search(domain, " ".join(args), dbg.get_db())
	return "\n".join(rows) if not rows.is_empty() else "no %s match '%s'" % [domain, " ".join(args)]


## Debug spawns still alive.
func debug_spawn_count() -> int:
	var n := 0
	for m in debug_spawns:
		if is_instance_valid(m):
			n += 1
	return n


## Removes every debug spawn. Returns how many there were.
func clear_debug_spawns() -> int:
	var w := dbg.get_world()
	var view: Variant = w.get("instance_view") if w != null else null
	var n := 0
	for m in debug_spawns:
		if is_instance_valid(m):
			_release_debug(m, view as MapInstanceView if view is MapInstanceView else null)
			n += 1
	debug_spawns.clear()
	return n


func _release_debug(n: Node3D, view: MapInstanceView) -> void:
	if view != null and view.monster_releaser.is_valid():
		view.monster_releaser.call(n)
	else:
		n.queue_free()


func _on_debug_spawn_died(n: Node3D) -> void:
	debug_spawns.erase(n)


func _on_map_left(_map_id: String) -> void:
	clear_debug_spawns()


func _on_transition_started(_request: Variant) -> void:
	clear_debug_spawns()


# --- character ------------------------------------------------------------------------------------------------

func _cmd_exp(args: PackedStringArray) -> String:
	if args.is_empty() or not args[0].is_valid_int():
		return "usage: exp <n>"
	var n := int(args[0])
	if n <= 0:
		return "exp: give a positive amount (EXP is only ever added; 'level <n>' goes down)"
	var g := dbg.get_game()
	var c := dbg.get_character()
	if g == null or c == null or not g.has_method("gain_exp"):
		return "exp: no Game character"
	var before := c.level
	var r: Dictionary = g.call("gain_exp", n, "debug")
	var db := dbg.get_db()
	var lv := ""
	if c.level > before:
		lv = ", level %d -> %d (+%d AP, +%d SP)" % [before, c.level, int(r.get("ap_gained", 0)), int(r.get("sp_gained", 0))]
	return "EXP +%d: Lv %d, %d/%d EXP%s" % [int(r.get("exp_added", 0)), c.level, c.exp, Progression.exp_to_next(c.level, db), lv]


func _cmd_level(args: PackedStringArray) -> String:
	if args.is_empty() or not args[0].is_valid_int():
		return "usage: level <n>"
	var g := dbg.get_game()
	var c := dbg.get_character()
	if g == null or c == null:
		return "level: no Game character"
	var db := dbg.get_db()
	var target := int(args[0])
	var cap := Progression.level_cap(db)
	if target < 1 or target > cap:
		return "level: must be 1..%d" % cap
	if target == c.level:
		return "level: already %d" % target
	var start := c.level
	if target > c.level:
		var ap := 0
		var sp := 0
		var hp0 := c.base_max_hp
		var mp0 := c.base_max_mp
		while c.level < target:
			var need := Progression.exp_to_next(c.level, db) - c.exp
			var r: Dictionary = g.call("gain_exp", maxi(need, 1), "debug:level")
			if int(r.get("levels_gained", 0)) <= 0:
				break
			ap += int(r.get("ap_gained", 0))
			sp += int(r.get("sp_gained", 0))
		return "level %d -> %d through Progression.gain_exp: +%d AP, +%d SP, base max HP/MP %d/%d (+%d/+%d), HP %d/%d; EXP %d/%d" % [
			start, c.level, ap, sp, c.base_max_hp, c.base_max_mp, c.base_max_hp - hp0, c.base_max_mp - mp0, c.hp,
			StatCalculator.max_hp(c, db), c.exp, Progression.exp_to_next(c.level, db)]
	var back := {"ap": 0, "sp": 0, "max_hp": 0, "max_mp": 0}
	for lv in range(c.level, target, -1):
		var gains := Progression.level_up_gains(c.job, lv, db)
		for k in back:
			back[k] = int(back[k]) + int(gains[k])
	if c.ap < int(back.ap) or c.sp < int(back.sp):
		return "level: cannot go down to %d: that takes back %d AP and %d SP, but only %d AP and %d SP are unspent (reset_save gives a clean character)" % [
			target, int(back.ap), int(back.sp), c.ap, c.sp]
	c.level = target
	c.ap -= int(back.ap)
	c.sp -= int(back.sp)
	c.base_max_hp -= int(back.max_hp)
	c.base_max_mp -= int(back.max_mp)
	c.exp = 0
	c.hp = mini(c.hp, StatCalculator.max_hp(c, db))
	c.mp = mini(c.mp, StatCalculator.max_mp(c, db))
	dbg.emit_event(&"stats_changed")
	dbg.emit_event(&"hp_changed", [c.hp, StatCalculator.max_hp(c, db)])
	dbg.emit_event(&"mp_changed", [c.mp, StatCalculator.max_mp(c, db)])
	return "level %d -> %d: took back %d AP, %d SP, base max HP/MP -%d/-%d (Progression.level_up_gains in reverse); EXP 0, HP %d/%d" % [
		start, target, int(back.ap), int(back.sp), int(back.max_hp), int(back.max_mp), c.hp, StatCalculator.max_hp(c, db)]


func _cmd_ap(args: PackedStringArray) -> String:
	if args.is_empty():
		return "usage: ap <str|dex|int|luk> [n]"
	var g := dbg.get_game()
	var c := dbg.get_character()
	if g == null or c == null or not g.has_method("allocate_ap"):
		return "ap: no Game character"
	var stat := args[0].to_lower()
	var n := int(args[1]) if args.size() > 1 and args[1].is_valid_int() else 1
	if not bool(g.call("allocate_ap", stat, n)):
		return "ap: refused (%d AP unspent; stats: %s)" % [c.ap, ", ".join(CharacterState.STAT_KEYS)]
	return "%s %d (+%d), %d AP left" % [stat.to_upper(), c.get_base_stat(stat), n, c.ap]


func _cmd_heal(_args: PackedStringArray) -> String:
	var c := dbg.get_character()
	if c == null:
		return "heal: no character"
	var s := dbg.get_session()
	if s != null and s.has_method("state_name") and String(s.call("state_name")) == "DEAD":
		return "heal: the character is dead; use respawn"
	var db := dbg.get_db()
	c.hp = StatCalculator.max_hp(c, db)
	c.mp = StatCalculator.max_mp(c, db)
	dbg.emit_event(&"hp_changed", [c.hp, c.hp])
	dbg.emit_event(&"mp_changed", [c.mp, c.mp])
	return "healed: HP %d/%d, MP %d/%d" % [c.hp, c.hp, c.mp, c.mp]


func _cmd_god(args: PackedStringArray) -> String:
	var t := parse_toggle(args, dbg.god_mode)
	if not bool(t.ok):
		return "usage: god [on|off]"
	dbg.set_god_mode(bool(t.on))
	if not bool(t.on):
		return "god mode off (the last invulnerability window runs out within 0.25 s)"
	return "god mode on: player invulnerable (renewed every physics tick, so it blinks) and HP locked at max%s" % (
		"" if dbg.get_player() != null else " (no player now: HP lock only)")


func _cmd_char(_args: PackedStringArray) -> String:
	return DebugReport.character_text(dbg)


# --- items ----------------------------------------------------------------------------------------------------

func _items() -> ItemService:
	var c := dbg.get_character()
	return ItemService.new(c, dbg.get_db(), dbg.get_bus()) if c != null else null


func _cmd_mesos(args: PackedStringArray) -> String:
	var items := _items()
	if items == null:
		return "mesos: no character"
	var c := items.character
	if args.is_empty():
		return "mesos: %d" % c.mesos
	if not args[0].is_valid_int():
		return "usage: mesos <n>"
	var n := int(args[0])
	if n > 0:
		var added := items.gain_mesos(n)
		return "mesos +%d -> %d%s" % [added, c.mesos, " (meso cap reached)" if added < n else ""]
	if n < 0:
		var r := items.spend_mesos(-n)
		if bool(r.get("ok", false)):
			return "mesos %d -> %d" % [n, c.mesos]
		return "mesos: cannot spend %d (have %d): %s" % [-n, c.mesos, String(r.get("code", ""))]
	return "mesos: %d" % c.mesos


func _cmd_give(args: PackedStringArray) -> String:
	if args.is_empty():
		return "usage: give <item id|name> [qty]"
	var items := _items()
	if items == null:
		return "give: no character"
	var qty := 1
	var words := args
	if args.size() >= 2 and args[args.size() - 1].is_valid_int():
		qty = int(args[args.size() - 1])
		words = args.slice(0, args.size() - 1)
	var db := dbg.get_db()
	var r := DebugResolve.item_id(" ".join(words), db)
	if not bool(r.ok):
		return "give: " + String(r.error)
	if qty < 1:
		return "give: qty must be at least 1"
	var id := String(r.id)
	var added := items.gain(id, qty)
	var tab := String(db.item(id).get("inventory_tab", "?"))
	if added == qty:
		return "gave %d x %s (%s): %d in the %s tab" % [qty, _name("items", id), id, items.character.inventory.count(id), tab]
	if added > 0:
		return "gave %d of %d x %s (%s): the %s tab is full" % [added, qty, _name("items", id), id, tab]
	return "give: no room for %s (%s) in the %s tab" % [_name("items", id), id, tab]


func _cmd_clearinv(args: PackedStringArray) -> String:
	var items := _items()
	if items == null:
		return "clearinv: no character"
	var tab := args[0].to_lower() if not args.is_empty() else ""
	if tab != "" and not (tab in Inventory.TABS):
		return "clearinv: unknown tab %s (tabs: %s)" % [tab, ", ".join(Inventory.TABS)]
	var removed := items.clear_inventory(tab)
	var total := 0
	for id in removed:
		total += int(removed[id])
	return "cleared %d items (%d kinds) from %s; equipment untouched" % [total, removed.size(), tab if tab != "" else "every tab"]


func _cmd_inv(_args: PackedStringArray) -> String:
	return DebugReport.inventory_text(dbg)


# --- quests ---------------------------------------------------------------------------------------------------

## The QuestService behind the quest commands: the owner of the registered quest_accept, else Game.quests, else
## the debug fallback.
func quest_service() -> QuestService:
	var owner := dbg.command_owner("quest_accept")
	if owner is QuestService:
		return owner
	var g := dbg.get_game()
	var live: Variant = g.get("quests") if g != null else null
	if live is QuestService:
		return live
	return fallback_quests


func _cmd_quest(args: PackedStringArray) -> String:
	if args.is_empty():
		return "usage: quest accept|complete|forfeit|reset <id> [force] | quest <id> | quest list"
	var sub := args[0].to_lower()
	var note := ("\n" + QUEST_FALLBACK_NOTE) if quest_service() != null and quest_service() == fallback_quests else ""
	match sub:
		"list":
			return dbg.call_command("quests", PackedStringArray()) + note
		"accept", "complete", "reset", "forfeit", "status":
			var rest := args.slice(1)
			var force := false
			if sub == "complete" and not rest.is_empty() and rest[rest.size() - 1].to_lower() == "force":
				force = true
				rest = rest.slice(0, rest.size() - 1)
			if rest.is_empty():
				return "usage: quest %s <id>%s" % [sub, " [force]" if sub == "complete" else ""]
			var r := DebugResolve.quest_id(" ".join(rest), dbg.get_db())
			if not bool(r.ok):
				return "quest: " + String(r.error)
			var id := String(r.id)
			var label := "%s %s" % [id, _name("quests", id)]
			if sub == "status":
				return _quest_status(PackedStringArray([id])) + note
			if sub == "forfeit":
				var svc := quest_service()
				if svc == null:
					return "quest forfeit: no quest service"
				var fr := svc.forfeit(id)
				return ("forfeited %s" % label if bool(fr.get("ok", false)) else "forfeit %s refused: %s" % [label, String(fr.get("reason", ""))]) + note
			var cmd := "quest_" + sub
			if not dbg.has_command(cmd):
				return "quest %s: no quest system registered %s" % [sub, cmd]
			var pass_args := PackedStringArray([id])
			if force:
				pass_args.append("force")
			return "%s %s: %s%s" % [sub, label, dbg.call_command(cmd, pass_args), note]
	return _quest_status(args) + note


## "quest <id>": the QuestService's own status command (the shadowed "quest"), with name resolution.
func _quest_status(args: PackedStringArray) -> String:
	var r := DebugResolve.quest_id(" ".join(args), dbg.get_db())
	if not bool(r.ok):
		return "quest: " + String(r.error)
	var h := dbg.shadowed_handler("quest")
	if not h.is_valid():
		return "quest: no quest system registered a status command"
	return str(h.call(PackedStringArray([String(r.id)])))


# --- engine ---------------------------------------------------------------------------------------------------

func _cmd_timescale(args: PackedStringArray) -> String:
	if args.is_empty():
		return "time scale %.2f" % Engine.time_scale
	if not args[0].is_valid_float():
		return "usage: timescale <x>"
	var x := float(args[0])
	if x < MIN_TIME_SCALE or x > MAX_TIME_SCALE:
		return "timescale: must be %.2f..%.0f" % [MIN_TIME_SCALE, MAX_TIME_SCALE]
	var before := Engine.time_scale
	Engine.time_scale = x
	return "time scale %.2f (was %.2f): physics, animation and Game.clock run at this rate" % [x, before]


func _cmd_seed(args: PackedStringArray) -> String:
	var rng := dbg.get_rng()
	if rng == null:
		return "seed: no gameplay RNG (Game)"
	if args.is_empty():
		return "gameplay RNG seed %d, state %d" % [rng.seed, rng.state]
	if not args[0].is_valid_int():
		return "usage: seed <n>"
	rng.seed = int(args[0])
	return "gameplay RNG (Game.rng) seeded with %d: rolls, drops and new map instances replay from here" % rng.seed


func _cmd_screenshot(args: PackedStringArray) -> String:
	var r := dbg.screenshot(args[0] if not args.is_empty() else "")
	if not bool(r.ok):
		return "screenshot: %s" % String(r.error)
	return "screenshot: capturing the next frame to %s" % String(r.path)


# --- helpers --------------------------------------------------------------------------------------------------

func _name(domain: String, id: String) -> String:
	return String(dbg.get_db().get_entity(domain, id).get("name", id))


## Grounds a point on walkable collision with the world's ground query. {"ok", "pos"}.
func _ground(w: Node, pos: Vector3, up_m: float = -1.0, down_m: float = -1.0) -> Dictionary:
	var q: Variant = w.get("ground_query") if w != null else null
	var tuning: Variant = w.get("tuning") if w != null else null
	if not (q is GroundQuery) or not (tuning is WorldTuning):
		return {"ok": false, "pos": pos}
	var t := tuning as WorldTuning
	var g := (q as GroundQuery).ground_at(pos, up_m if up_m >= 0.0 else t.num("grounding", "probe_up_m"),
		down_m if down_m >= 0.0 else t.num("grounding", "probe_down_m"))
	if bool(g.get("ok", false)):
		return {"ok": true, "pos": Vector3(pos.x, float(g.y), pos.z)}
	return {"ok": false, "pos": pos}


## The first of `names` the node has as a method callable without arguments ("" when none).
static func zero_arg_method(n: Object, names: Array) -> String:
	for m in names:
		if not n.has_method(m):
			continue
		for info in n.get_method_list():
			if String(info.name) == m and (info.args as Array).size() - (info.default_args as Array).size() <= 0:
				return m
	return ""


## "Snail x3, Blue Snail" from a list of names.
static func _summarize(names: PackedStringArray) -> PackedStringArray:
	var counts := {}
	var order: PackedStringArray = []
	for n in names:
		if not counts.has(n):
			order.append(n)
		counts[n] = int(counts.get(n, 0)) + 1
	var out: PackedStringArray = []
	for n in order:
		out.append(n if int(counts[n]) == 1 else "%s x%d" % [n, int(counts[n])])
	return out
