class_name MisoItemTooltip
extends PanelContainer
## The item inspect card shown when hovering an inventory slot, an equipped piece or a quickslot: icon, name,
## category, requirements (red when the character does not meet them), weapon facts, stat lines, consumable
## effects, description and sell price. Every value is read from the canonical item (ItemDef) and the live
## character; nothing is invented.
##
##   tip.show_item("541", Game.character, Data.db, {"hint": "Double-click to equip"})
##
## describe() is the pure part (rows of {text, tone}); tests read it directly.

## Display labels of stat-line keys (Equipment.BONUS_KEYS + ItemDef.EXTRA_STAT_KEYS). Presentation only.
const STAT_LABELS := {
	"str": "STR", "dex": "DEX", "int": "INT", "luk": "LUK", "max_hp": "MaxHP", "max_mp": "MaxMP",
	"watk": "Weapon Attack", "matk": "Magic Attack", "wdef": "Weapon Def.", "mdef": "Magic Def.",
	"acc": "Accuracy", "avoid": "Avoidability", "speed": "Speed", "jump": "Jump",
	"crit_rate_pct": "Critical Rate", "knockback_pct": "Knockback Rate",
}
## Order the stat lines are listed in.
const STAT_ORDER: PackedStringArray = ["str", "dex", "int", "luk", "max_hp", "max_mp", "watk", "matk", "wdef",
	"mdef", "acc", "avoid", "speed", "jump", "crit_rate_pct", "knockback_pct"]
## Inventory tab display names.
const TAB_NAMES := {"equip": "Equip", "use": "Use", "setup": "Set-up", "etc": "Etc", "cash": "Cash"}
## Tooltip width in px.
const WIDTH := 290.0
## place_beside: px between the anchor and the card, and how far the card's top sits above the anchor's.
const ANCHOR_GAP := 8.0
const ANCHOR_RISE := 6.0

## The rows currently shown ([{text, tone}]); tones: title, sub, text, good, bad, desc, price, hint, sep.
var rows: Array = []
var _box: VBoxContainer
var _icon: MisoItemIcon


func _init() -> void:
	theme_type_variation = &"MisoTooltip"
	mouse_filter = MOUSE_FILTER_IGNORE
	z_index = 50
	custom_minimum_size = Vector2(WIDTH, 0)
	visible = false
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 2)
	_box.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_box)


## Fills the card for an item. opts: qty (int), data (per-instance data), equipped (bool), hint (String).
func show_item(item_id: String, character: CharacterState, db: ContentDB, opts: Dictionary = {}) -> void:
	rows = describe(item_id, character, db, opts)
	for ch in _box.get_children():
		_box.remove_child(ch)
		ch.queue_free()
	_icon = null
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	header.mouse_filter = MOUSE_FILTER_IGNORE
	var icon_frame := PanelContainer.new()
	icon_frame.theme_type_variation = &"MisoSlot"
	icon_frame.mouse_filter = MOUSE_FILTER_IGNORE
	_icon = MisoItemIcon.new()
	_icon.custom_minimum_size = Vector2(44, 44)
	_icon.set_item(item_id, db)
	icon_frame.add_child(_icon)
	header.add_child(icon_frame)
	var head_text := VBoxContainer.new()
	head_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_text.alignment = BoxContainer.ALIGNMENT_CENTER
	head_text.mouse_filter = MOUSE_FILTER_IGNORE
	header.add_child(head_text)
	_box.add_child(header)
	var in_header := 0
	for r: Dictionary in rows:
		var tone := String(r["tone"])
		if in_header < 2 and (tone == "title" or tone == "sub"):
			head_text.add_child(_row_control(r))
			in_header += 1
			continue
		_box.add_child(_row_control(r))
	visible = true
	reset_size()


## The rows describing an item for a character ([{text, tone}]). Pure: no scene tree.
static func describe(item_id: String, character: CharacterState, db: ContentDB, opts: Dictionary = {}) -> Array:
	var out: Array = []
	var def: ItemDef = ItemDef.of(item_id, db) if db != null else null
	if def == null:
		# An id the item data does not define: kept from an older save (docs/runtime/SAVES.md, unknown items).
		var qty := int(opts.get("qty", 1))
		out.append({"text": "Unknown item %s" % item_id + (" (x%d)" % qty if qty > 1 else ""), "tone": "title"})
		out.append({"text": "Not in this version's item data", "tone": "sub"})
		if bool(opts.get("equipped", false)):
			out.append({"text": "Equipped", "tone": "gold"})
		out.append({"text": "", "tone": "sep"})
		out.append({"text": "Kept from your save. It cannot be used, equipped or sold.", "tone": "desc"})
		return out
	var qty := int(opts.get("qty", 1))
	out.append({"text": def.name + (" (x%d)" % qty if qty > 1 else ""), "tone": "title"})
	var cat: String = TAB_NAMES.get(def.tab, def.type)
	if def.subtype != "":
		cat += "  ·  " + def.subtype
	out.append({"text": cat, "tone": "sub"})
	var flags: PackedStringArray = []
	if bool(opts.get("equipped", false)):
		flags.append("Equipped")
	if def.quest_item:
		flags.append("Quest item")
	if def.untradeable():
		flags.append("Untradeable")
	if not flags.is_empty():
		out.append({"text": "  ·  ".join(flags), "tone": "gold"})

	if def.is_equipment():
		var reqs := requirement_rows(def, character, db)
		if not reqs.is_empty():
			out.append({"text": "", "tone": "sep"})
			out.append_array(reqs)
		out.append({"text": "", "tone": "sep"})
		if def.is_weapon():
			if def.attack_speed_name != "":
				out.append({"text": "Attack Speed: %s (%d)" % [def.attack_speed_name, def.attack_speed], "tone": "text"})
		var stats: Dictionary = def.stat_lines()
		var data: Variant = opts.get("data", {})
		if data is Dictionary and (data as Dictionary).get("stats") is Dictionary:
			var b := ItemDef.bonuses_from_stats(data["stats"])
			stats = {}
			for k in b:
				if int(b[k]) != 0:
					stats[k] = b[k]
		for k in STAT_ORDER:
			if stats.has(k) and int(stats[k]) != 0:
				var v := int(stats[k])
				var suffix := "%" if k.ends_with("_pct") else ""
				out.append({"text": "%s: %s%d%s" % [STAT_LABELS.get(k, k), "+" if v > 0 else "", v, suffix],
					"tone": "good"})
		if def.upgrade_slots > 0:
			out.append({"text": "Number of upgrades available: %d" % def.upgrade_slots, "tone": "text"})
	else:
		var fx := effect_rows(def)
		if not fx.is_empty():
			out.append({"text": "", "tone": "sep"})
			out.append_array(fx)

	if def.description.strip_edges() != "":
		out.append({"text": "", "tone": "sep"})
		out.append({"text": def.description.strip_edges(), "tone": "desc"})
	out.append({"text": "", "tone": "sep"})
	out.append({"text": price_text(def), "tone": "price"})
	var hint := String(opts.get("hint", ""))
	if hint != "":
		out.append({"text": hint, "tone": "hint"})
	return out


## Requirement rows of a piece of equipment, each "bad" when the character does not meet it.
static func requirement_rows(def: ItemDef, character: CharacterState, db: ContentDB) -> Array:
	var out: Array = []
	if def.req_level > 0:
		var ok := character == null or character.level >= def.req_level
		out.append({"text": "REQ LEV: %d" % def.req_level, "tone": "text" if ok else "bad", "met": ok})
	for stat in ItemDef.REQ_STAT_KEYS:
		var need := int(def.req_stats.get(stat, 0))
		if need <= 0:
			continue
		var ok := character == null or StatCalculator.total_stat(character, stat, db) >= need
		out.append({"text": "REQ %s: %d" % [String(stat).to_upper(), need], "tone": "text" if ok else "bad", "met": ok})
	if def.req_fame > 0:
		var ok := character == null or character.fame >= def.req_fame
		out.append({"text": "REQ POP: %d" % def.req_fame, "tone": "text" if ok else "bad", "met": ok})
	if not def.req_jobs.is_empty():
		var ok := true
		if character != null:
			ok = false
			var tags := ItemsConfig.job_item_tags(character.job, db)
			for j in def.req_jobs:
				if j in tags:
					ok = true
		out.append({"text": "REQ JOB: %s" % " / ".join(def.req_jobs), "tone": "text" if ok else "bad", "met": ok})
	if def.gender != "":
		var g := Equipment.character_gender(character) if character != null else ""
		var ok := g == "" or g == def.gender
		out.append({"text": "For %s characters" % ("male" if def.gender == "male" else "female"),
			"tone": "text" if ok else "bad", "met": ok})
	return out


## Effect rows of a Use / Setup item ("Recovers 50 HP").
static func effect_rows(def: ItemDef) -> Array:
	var out: Array = []
	if def.hp_flat > 0:
		out.append({"text": "Recovers %d HP" % def.hp_flat, "tone": "good"})
	if def.mp_flat > 0:
		out.append({"text": "Recovers %d MP" % def.mp_flat, "tone": "good"})
	if def.hp_pct > 0.0:
		out.append({"text": "Recovers %s%% of Max HP" % _num(def.hp_pct), "tone": "good"})
	if def.mp_pct > 0.0:
		out.append({"text": "Recovers %s%% of Max MP" % _num(def.mp_pct), "tone": "good"})
	for b: Variant in def.buffs:
		if b is Dictionary:
			out.append({"text": "Effect: %s" % _buff_text(b), "tone": "good"})
	if def.pet_fullness > 0:
		out.append({"text": "Pet fullness +%d" % def.pet_fullness, "tone": "good"})
	if def.setup_hp_bonus > 0:
		out.append({"text": "While sitting: +%d HP every %s s" % [def.setup_hp_bonus, _num(def.setup_interval_s)],
			"tone": "good"})
	return out


## "Sells for 25 mesos each" / "Shops will not buy this".
static func price_text(def: ItemDef) -> String:
	if def.sell_price < 0:
		return "Shops will not buy this"
	var each := " each" if def.sell_basis == "per_unit" and def.is_stackable() else ""
	return "Sells for %s mesos%s" % [MisoTheme.thousands(def.sell_price), each]


static func _buff_text(b: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k in b:
		parts.append("%s %s" % [String(k).replace("_", " "), str(b[k])])
	return ", ".join(parts)


static func _num(v: float) -> String:
	return str(int(v)) if v == floorf(v) else str(v)


func _row_control(r: Dictionary) -> Control:
	var tone := String(r["tone"])
	if tone == "sep":
		var sep := HSeparator.new()
		sep.mouse_filter = MOUSE_FILTER_IGNORE
		return sep
	var l := Label.new()
	l.text = String(r["text"])
	l.mouse_filter = MOUSE_FILTER_IGNORE
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(WIDTH - 80 if tone in ["title", "sub"] else WIDTH - 24, 0)
	match tone:
		"title":
			l.theme_type_variation = &"MisoTitle"
		"sub":
			l.theme_type_variation = &"MisoDim"
		"good":
			l.theme_type_variation = &"MisoGood"
		"bad":
			l.theme_type_variation = &"MisoBad"
		"gold":
			l.theme_type_variation = &"MisoGold"
			l.add_theme_font_size_override("font_size", MisoTheme.FONT_SIZE_SMALL)
		"desc":
			l.theme_type_variation = &"MisoDim"
		"price":
			l.theme_type_variation = &"MisoGold"
			l.add_theme_font_size_override("font_size", MisoTheme.FONT_SIZE_SMALL)
		"hint":
			l.theme_type_variation = &"MisoDim"
			l.add_theme_color_override("font_color", MisoTheme.ACCENT_LIGHT)
		_:
			l.theme_type_variation = &"MisoSmall"
	return l


## Places the card beside `anchor` (a slot's global rect) without covering it, kept inside `bounds`: to its right
## when the card fits there, else to its left, else above it (below near the top edge). On a side the card's top is
## level with the anchor's (ANCHOR_RISE above it) and only slides up or down to stay on screen, so it never moves
## back over the anchor.
func place_beside(anchor: Rect2, bounds: Rect2) -> void:
	reset_size()
	var sz := get_combined_minimum_size()
	var pos := Vector2(anchor.end.x + ANCHOR_GAP, anchor.position.y - ANCHOR_RISE)
	var side := true
	if pos.x + sz.x > bounds.end.x:
		pos.x = anchor.position.x - ANCHOR_GAP - sz.x
		if pos.x < bounds.position.x:
			side = false
	if not side:
		pos.x = anchor.get_center().x - sz.x * 0.5
		pos.y = anchor.position.y - ANCHOR_GAP - sz.y
		if pos.y < bounds.position.y:
			pos.y = anchor.end.y + ANCHOR_GAP
	pos.x = clampf(pos.x, bounds.position.x, maxf(bounds.position.x, bounds.end.x - sz.x))
	pos.y = clampf(pos.y, bounds.position.y, maxf(bounds.position.y, bounds.end.y - sz.y))
	global_position = pos


## Places the card next to a screen point, kept inside `bounds` (flips left/up near the edges).
func place_near(point: Vector2, bounds: Rect2) -> void:
	reset_size()
	var sz := get_combined_minimum_size()
	var pos := point + Vector2(18, 14)
	if pos.x + sz.x > bounds.end.x:
		pos.x = point.x - sz.x - 12
	if pos.y + sz.y > bounds.end.y:
		pos.y = bounds.end.y - sz.y - 4
	pos.x = clampf(pos.x, bounds.position.x, maxf(bounds.position.x, bounds.end.x - sz.x))
	pos.y = clampf(pos.y, bounds.position.y, maxf(bounds.position.y, bounds.end.y - sz.y))
	global_position = pos
