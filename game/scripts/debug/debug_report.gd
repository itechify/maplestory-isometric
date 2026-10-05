class_name DebugReport
extends RefCounted
## The text the debug tools print: the overlay, "where", "portals", "maps", "char", "inv". Reads the collaborators
## through a DebugTools node and never changes anything. Every number comes from the live objects (MapSession,
## the instance state, SpawnModel, the camera rig, the character); none is a constant here.


## The overlay lines (F3): FPS and frame time; map id, name, street; session state and the last transition; the
## player's world and map-local position and region; grounded/climbing/HP/invulnerable; live monsters vs capacity
## and the next spawn tick; the camera ortho size; the draw layers that are on.
static func overlay_lines(dbg: DebugTools) -> PackedStringArray:
	var out: PackedStringArray = []
	var fps := Engine.get_frames_per_second()
	var phys_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var proc_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	out.append("FPS %d  frame %.1f ms  (process %.1f, physics %.1f)%s" % [fps, dbg.frame_ms, proc_ms, phys_ms,
		"  time x%.2f" % Engine.time_scale if not is_equal_approx(Engine.time_scale, 1.0) else ""])
	var s := dbg.get_session()
	var map := dbg.current_map()
	var defs := dbg.get_defs()
	var def := defs.get_def(map) if map != "" else null
	if def == null:
		out.append("MAP  (none)")
	else:
		out.append("MAP  %s  %s  [%s]" % [def.map_id, def.map_name, def.street_name])
		out.append("     v8 %d  %s  %s%s" % [def.gms_v8_id, def.slug, def.kind if def.kind != "" else "-",
			"  town" if def.is_town() else ""])
	if s != null:
		var st := String(s.call("state_name")) if s.has_method("state_name") else "?"
		out.append("SESSION %s  respawn %s" % [st, String(s.get("respawn_reference"))])
		var rec: Variant = s.get("last_transition")
		out.append("     last %s" % (transition_text(rec as TransitionRecord) if rec is TransitionRecord else "(none)"))
	out.append_array(position_lines(dbg))
	out.append(player_line(dbg))
	out.append(monster_line(dbg))
	var cam := dbg.get_camera()
	if cam != null:
		var size: Variant = cam.get("ortho_size")
		out.append("CAMERA ortho %s%s" % ["%.2f m" % float(size) if size != null else "?",
			"  bounds set" if cam.has_method("bounds_rect") and (cam.call("bounds_rect") as Rect2).size != Vector2.ZERO else ""])
	else:
		out.append("CAMERA (none)")
	var on: PackedStringArray = []
	for l in DebugTools.LAYERS:
		if dbg.is_layer_on(l):
			on.append(l)
	if dbg.god_mode:
		on.append("GOD")
	if not on.is_empty():
		out.append("DEBUG " + " ".join(on))
	return out


## "WORLD (x, y, z)  LOCAL (x, y, z)  REGION map:<id>" (or the reason there is no position).
static func position_lines(dbg: DebugTools) -> PackedStringArray:
	var out: PackedStringArray = []
	var p := dbg.get_player()
	var map := dbg.current_map()
	var def := dbg.get_defs().get_def(map) if map != "" else null
	if p == null:
		out.append("POS  (no player)")
		return out
	var pos := p.global_position
	var local := def.to_local(pos) if def != null else Vector3.ZERO
	var region := "?"
	var w := dbg.get_world()
	var ri: Variant = w.get("region_index") if w != null else null
	if ri is RegionIndex:
		var r := (ri as RegionIndex).region_of(pos, map)
		region = "%s:%s" % [String(r.get("kind", "")), String(r.get("id", ""))]
	out.append("POS  world %s  local %s" % [vec(pos), vec(local)])
	out.append("     region %s%s" % [region, "" if region == "map:" + map else "  (outside %s)" % map])
	return out


static func player_line(dbg: DebugTools) -> String:
	var p := dbg.get_player()
	var c := dbg.get_character()
	var parts: PackedStringArray = []
	if p != null:
		var grounded: Variant = p.call("is_grounded") if p.has_method("is_grounded") else (p.call("is_on_floor") if p.has_method("is_on_floor") else null)
		parts.append("grounded %s" % _yn(grounded))
		parts.append("climbing %s" % _yn(p.call("is_climbing") if p.has_method("is_climbing") else null))
		parts.append("invuln %s" % (("%.1fs" % float(p.call("invulnerable_time_left"))) if p.has_method("invulnerable_time_left") and bool(p.call("is_invulnerable")) else "no"))
		if p.has_method("is_dead") and bool(p.call("is_dead")):
			parts.append("DEAD")
	if c != null:
		var db := dbg.get_db()
		parts.append("HP %d/%d  MP %d/%d  Lv %d" % [c.hp, StatCalculator.max_hp(c, db), c.mp, StatCalculator.max_mp(c, db), c.level])
	return "PLAYER " + ("  ".join(parts) if not parts.is_empty() else "(none)")


## Live monster nodes vs capacity, alive slots, the next global spawn tick and debug spawns.
static func monster_line(dbg: DebugTools) -> String:
	var s := dbg.get_session()
	var st: Variant = s.get("instance_state") if s != null else null
	if not (st is MapInstanceState):
		return "MOBS (no map instance)"
	var inst := st as MapInstanceState
	var live := -1
	var w := dbg.get_world()
	var view: Variant = w.get("instance_view") if w != null else null
	if view is MapInstanceView:
		live = (view as MapInstanceView).live_count()
	var model := inst.model
	var now := dbg.get_clock()
	var tick := ""
	if model != null and model.tick_s > 0.0:
		var next := model.boundary_time(model.boundary_index_at_or_before(now) + 1)
		tick = "  next tick in %.1fs (every %.2fs)" % [next - now, model.tick_s]
	var dbg_spawns := dbg.builtins.debug_spawn_count() if dbg.builtins != null else 0
	return "MOBS live %s (capacity %d)  slots alive %d/%d%s%s" % [str(live) if live >= 0 else "-", inst.capacity, inst.alive_count(),
		inst.slots.size(), tick, "  debug spawns %d" % dbg_spawns if dbg_spawns > 0 else ""]


## "where": the map, the session, the position and the last arrival.
static func where_text(dbg: DebugTools) -> String:
	var map := dbg.current_map()
	if map == "":
		var s := dbg.get_session()
		return "no current map (session %s)" % (String(s.call("state_name")) if s != null and s.has_method("state_name") else "missing")
	var def := dbg.get_defs().get_def(map)
	var lines: PackedStringArray = ["%s %s (%s), v8 %d, %s" % [map, def.map_name, def.street_name, def.gms_v8_id, def.slug]]
	var s := dbg.get_session()
	lines.append("session %s, respawn map %s" % [String(s.call("state_name")), String(s.get("respawn_reference"))])
	var arr: Variant = s.get("last_arrival")
	if arr is ArrivalRef:
		lines.append("arrived at %s" % str(arr))
	var rec: Variant = s.get("last_transition")
	if rec is TransitionRecord:
		lines.append("last transition %s" % transition_text(rec))
	lines.append_array(position_lines(dbg))
	return "\n".join(lines)


static func transition_text(rec: TransitionRecord) -> String:
	if rec == null:
		return "(none)"
	var via := rec.via + (" " + rec.portal_id if rec.portal_id != "" else "")
	var extra := ""
	if rec.frames_to_ground >= 0:
		extra = ", grounded in %d frames" % rec.frames_to_ground
	if rec.replaced:
		extra += ", RE-PLACED"
	if rec.load_step != "":
		extra += ", load step " + rec.load_step
	return "%s -> %s via %s at t=%.1fs%s" % [rec.from_map if rec.from_map != "" else "(start)", rec.to_map, via, rec.t_game, extra]


## "portals [map]": every portal with its destination, link and type.
static func portals_text(dbg: DebugTools, map_id: String) -> String:
	var defs := dbg.get_defs()
	var def := defs.get_def(map_id)
	if def == null:
		return "unknown map %s" % map_id
	var lines: PackedStringArray = ["%s %s: %d portals" % [def.map_id, def.map_name, def.portals.size()]]
	for p in def.portals:
		lines.append("  " + portal_label(p, defs))
	return "\n".join(lines)


## One portal: "east00 -> 000000040.west00 (Snail Hunting Ground I) [edge, link warp T_..., type 2]".
static func portal_label(p: PortalDef, defs: MapDefinitions) -> String:
	var dest := "%s.%s" % [p.destination_map_id, p.destination_portal_id] if p.destination_portal_id != "" \
		else "%s sp%d" % [p.destination_map_id, maxi(p.destination_spawn_index, 0)]
	if p.portal_type == PortalDef.TYPE_ARRIVAL:
		dest = "(arrival gate, walk-only)"
	var dname := ""
	var ddef := defs.get_def(p.destination_map_id)
	if ddef != null and p.portal_type != PortalDef.TYPE_ARRIVAL:
		dname = " (%s)" % ddef.map_name
	var flags: PackedStringArray = [p.portal_type, "link %s" % p.link_mode]
	if p.canonical_type >= 0:
		flags.append("type %d" % p.canonical_type)
	if p.hidden:
		flags.append("hidden")
	if p.interaction_type != PortalDef.INTERACT_PRESS_UP:
		flags.append(p.interaction_type)
	if not p.has_anchor:
		flags.append("no anchor")
	return "%s -> %s%s [%s]" % [p.portal_id, dest, dname, ", ".join(flags)]


static func maps_text(dbg: DebugTools) -> String:
	var defs := dbg.get_defs()
	var lines: PackedStringArray = []
	for id in defs.ids():
		var d := defs.get_def(id)
		lines.append("%s  v8 %-7d %-32s %-12s %d portals, %d spawns, %d npcs" % [id, d.gms_v8_id, d.map_name,
			d.kind if d.kind != "" else "-", d.canonical_portals().size(), d.spawn_point_count(), d.npc_definitions.size()])
	return "\n".join(lines)


static func character_text(dbg: DebugTools) -> String:
	var c := dbg.get_character()
	if c == null:
		return "no character"
	var db := dbg.get_db()
	var need := Progression.exp_to_next(c.level, db)
	return "\n".join(PackedStringArray([
		"%s, %s Lv %d, EXP %d/%d" % [c.name if c.name != "" else "(unnamed)", c.job, c.level, c.exp, need],
		"HP %d/%d  MP %d/%d (base max %d/%d)" % [c.hp, StatCalculator.max_hp(c, db), c.mp, StatCalculator.max_mp(c, db), c.base_max_hp, c.base_max_mp],
		"STR %d  DEX %d  INT %d  LUK %d  AP %d  SP %d  fame %d" % [c.get_base_stat("str"), c.get_base_stat("dex"),
			c.get_base_stat("int"), c.get_base_stat("luk"), c.ap, c.sp, c.fame],
		"mesos %d  location %s" % [c.mesos, JSON.stringify(c.location.get("map_id", ""))],
	]))


static func inventory_text(dbg: DebugTools) -> String:
	var c := dbg.get_character()
	if c == null:
		return "no character"
	var db := dbg.get_db()
	var lines: PackedStringArray = []
	for tab in Inventory.TABS:
		var rows: PackedStringArray = []
		var slots: Array = c.inventory.slots(tab)
		for i in slots.size():
			var s: Dictionary = slots[i]
			if s.is_empty() or String(s.get("item_id", "")) == "":
				continue
			rows.append("%d:%s %s x%d" % [i, s.item_id, String(db.item(String(s.item_id)).get("name", "?")), int(s.get("qty", 0))])
		lines.append("%s (%d/%d): %s" % [tab, rows.size(), c.inventory.capacity(tab), ", ".join(rows) if not rows.is_empty() else "-"])
	var eq: PackedStringArray = []
	var worn := c.equipment.equipped()
	for slot in worn:
		var id := String(worn[slot])
		eq.append("%s=%s %s" % [slot, id, String(db.item(id).get("name", "?"))])
	lines.append("equipped: %s" % (", ".join(eq) if not eq.is_empty() else "-"))
	lines.append("mesos: %d" % c.mesos)
	return "\n".join(lines)


static func vec(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]


static func _yn(v: Variant) -> String:
	if v == null:
		return "?"
	return "yes" if bool(v) else "no"
