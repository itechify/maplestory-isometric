class_name MisoItemIcon
extends Control
## A procedurally drawn item icon: a small sticker-like shape chosen from the item's canonical type, subtype and
## equip slot (a potion bottle, an apple, a sword, a skullcap, a shell ...) tinted by the colour its name states
## ("Red Potion", "Blue Headband", "Amethyst Ore"), or a stable hue derived from the id. No MapleStory art is used.
##
##   var icon := MisoItemIcon.new()
##   icon.set_item("270", Data.db)      # Red Potion: a red bottle
##
## The shape and colour rules are presentation only (no gameplay value); shape_for() and color_for() are static so
## other UI (shop, dialogue item refs, loot labels) can reuse them.

## Item to draw ("" = nothing).
var item_id: String = ""
## Greyed out (a quickslot whose stack ran out).
var dim: bool = false:
	set(v):
		dim = v
		queue_redraw()

var shape: String = ""
var color: Color = Color.WHITE

## Name keyword -> tint, checked in order (longer, more specific words first).
const COLOR_WORDS: Array = [
	["sky-blue", Color(0.55, 0.80, 1.0)], ["aquamarine", Color(0.40, 0.90, 0.88)], ["amethyst", Color(0.66, 0.42, 0.92)],
	["garnet", Color(0.75, 0.10, 0.20)], ["opal", Color(0.96, 0.84, 0.92)], ["diamond", Color(0.88, 0.97, 1.0)],
	["mithril", Color(0.62, 0.74, 0.92)], ["bronze", Color(0.80, 0.50, 0.22)], ["silver", Color(0.84, 0.86, 0.90)],
	["iron", Color(0.58, 0.60, 0.64)], ["gold", Color(1.0, 0.80, 0.25)], ["jean", Color(0.30, 0.45, 0.78)],
	["indigo", Color(0.30, 0.28, 0.72)], ["orange", Color(1.0, 0.58, 0.12)], ["yellow", Color(1.0, 0.88, 0.25)],
	["green", Color(0.36, 0.78, 0.32)], ["blue", Color(0.25, 0.52, 0.95)], ["red", Color(0.90, 0.20, 0.18)],
	["white", Color(0.96, 0.96, 0.94)], ["black", Color(0.20, 0.20, 0.24)], ["grey", Color(0.60, 0.62, 0.66)],
	["brown", Color(0.58, 0.36, 0.20)], ["leather", Color(0.62, 0.40, 0.22)], ["wooden", Color(0.72, 0.50, 0.28)],
	["apple", Color(0.90, 0.18, 0.16)], ["egg", Color(1.0, 0.96, 0.84)], ["meat", Color(0.72, 0.32, 0.22)],
	["lemon", Color(1.0, 0.92, 0.30)], ["spore", Color(0.84, 0.72, 0.52)], ["snail", Color(0.80, 0.56, 0.30)],
	["shellpiece", Color(0.70, 0.74, 0.80)], ["mirror", Color(0.75, 0.88, 1.0)], ["letter", Color(0.98, 0.94, 0.82)],
	["screw", Color(0.62, 0.50, 0.40)], ["board", Color(0.66, 0.48, 0.30)], ["card", Color(0.98, 0.84, 0.40)],
	["relaxer", Color(0.40, 0.80, 0.40)], ["undershirt", Color(0.96, 0.96, 0.94)], ["gomushin", Color(0.96, 0.96, 0.94)],
]

const OUTLINE_COLOR := Color(0.06, 0.07, 0.10, 0.95)
## The neutral token of an item the item data does not define, so it reads as inert.
const UNKNOWN_COLOR := Color(0.62, 0.62, 0.66)
const METAL := Color(0.82, 0.86, 0.92)
const WOOD := Color(0.62, 0.42, 0.22)


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(32, 32)


## Shows an item (or nothing for ""). `db` resolves the canonical record; an id it does not define (an unknown item
## kept from an older save, docs/runtime/SAVES.md) draws a grey "?" token.
func set_item(p_item_id: String, db: ContentDB) -> void:
	item_id = p_item_id
	var def: ItemDef = ItemDef.of(item_id, db) if item_id != "" and db != null else null
	shape = shape_for(def) if item_id != "" else ""
	color = color_for(def, item_id) if def != null else UNKNOWN_COLOR
	queue_redraw()


## The icon shape for an item ("potion", "apple", "sword", "cap", "shirt", ... "unknown").
static func shape_for(def: ItemDef) -> String:
	if def == null:
		return "unknown"
	var n := def.name.to_lower()
	match def.type:
		"Equip":
			match def.equip_slot:
				"weapon":
					var w := (def.weapon_type if def.weapon_type != "" else def.subtype).to_lower()
					if "dagger" in w:
						return "dagger"
					if "axe" in w:
						return "axe"
					if "blunt" in w or "mace" in w:
						return "club"
					if "spear" in w or "polearm" in w:
						return "spear"
					if "wand" in w or "staff" in w:
						return "wand"
					if "bow" in w:
						return "bow"
					if "claw" in w:
						return "claw"
					return "sword"
				"hat":
					return "headband" if "headband" in n else "cap"
				"top":
					return "shirt"
				"bottom":
					if "skirt" in n:
						return "skirt"
					if "shorts" in n:
						return "shorts"
					return "pants"
				"overall":
					return "overall"
				"shoes":
					return "boot"
				"gloves":
					return "glove"
				"earrings":
					return "earring"
				"cape":
					return "cape"
				"shield":
					return "shield"
			return "gear"
		"Use":
			match def.subtype:
				"Potion":
					return "potion"
				"Food":
					for k in ["apple", "egg", "meat", "lemon"]:
						if k in n:
							return k
					if "orange" in n:
						return "fruit"
					return "apple"
				"Pet Food":
					return "bag"
				"Arrow":
					return "arrow"
				"Scroll":
					return "scroll"
			return "potion"
		"Setup":
			return "chair"
		"Etc":
			match def.subtype:
				"Monster Drop":
					if "shellpiece" in n:
						return "shard"
					if "shell" in n:
						return "shell"
					if "spore" in n:
						return "spore"
					if "cap" in n or "mushroom" in n:
						return "mushroom"
					return "shard"
				"Gem":
					return "gem"
				"Ore & Mineral":
					return "ore"
				"Quest Item":
					for k in ["letter", "mirror", "screw", "board", "card"]:
						if k in n:
							return k
					return "parcel"
			return "parcel"
		"Cash":
			return "star"
	return "unknown"


## The tint for an item: the first colour word in its name, else a stable hue from its id.
static func color_for(def: ItemDef, fallback_id: String = "") -> Color:
	var n := def.name.to_lower() if def != null else ""
	for pair: Array in COLOR_WORDS:
		if String(pair[0]) in n:
			return pair[1]
	var key := def.id if def != null else fallback_id
	var h := float(absi(key.hash()) % 360) / 360.0
	return Color.from_hsv(h, 0.55, 0.92)


func _draw() -> void:
	if shape == "":
		return
	var side := minf(size.x, size.y)
	var s := side / 32.0
	draw_set_transform(Vector2((size.x - side) * 0.5, (size.y - side) * 0.5), 0.0, Vector2(s, s))
	var c := color
	if dim:
		c = c.darkened(0.45)
		c.a = 0.55
	_draw_shape(shape, c)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# --- shapes (drawn on a 32 x 32 grid) --------------------------------------------------------------------------

func _draw_shape(kind: String, c: Color) -> void:
	var a := 0.55 if dim else 1.0
	var metal := Color(METAL, a)
	var wood := Color(WOOD, a)
	var hi := Color(1, 1, 1, 0.55 * a)
	match kind:
		"potion":
			_poly(_rect_pts(13, 6, 6, 7), Color(0.86, 0.92, 1.0, 0.9 * a))
			_poly(_rect_pts(12, 3, 8, 4), Color(0.62, 0.40, 0.22, a))
			_circle(Vector2(16, 20), 9.5, c)
			draw_circle(Vector2(12.5, 17), 2.6, hi)
		"apple":
			_circle(Vector2(16, 18), 10, c)
			draw_line(Vector2(16, 9), Vector2(17.5, 4), Color(0.45, 0.28, 0.12, a), 2.0)
			_poly(PackedVector2Array([Vector2(18, 7), Vector2(24, 4), Vector2(22, 9)]), Color(0.35, 0.75, 0.30, a))
			draw_circle(Vector2(12, 14), 2.4, hi)
		"fruit":
			_circle(Vector2(16, 18), 10, c)
			for p: Vector2 in [Vector2(12, 16), Vector2(19, 15), Vector2(15, 22), Vector2(20, 21)]:
				draw_circle(p, 0.9, c.darkened(0.25))
			_poly(PackedVector2Array([Vector2(16, 8), Vector2(22, 5), Vector2(20, 10)]), Color(0.35, 0.75, 0.30, a))
		"lemon":
			_poly(_ellipse_pts(Vector2(16, 17), 12, 8, 0.0, 18), c)
			draw_circle(Vector2(12, 14), 2.0, hi)
		"egg":
			_poly(_ellipse_pts(Vector2(16, 17), 8, 11, 0.0, 20), c)
			draw_circle(Vector2(13, 12), 2.2, hi)
		"meat":
			draw_line(Vector2(7, 25), Vector2(15, 17), Color(0.96, 0.94, 0.88, a), 4.0)
			draw_circle(Vector2(6, 24), 2.4, Color(0.96, 0.94, 0.88, a))
			draw_circle(Vector2(8, 27), 2.4, Color(0.96, 0.94, 0.88, a))
			_poly(_ellipse_pts(Vector2(19, 13), 10, 7, -0.75, 18), c)
			draw_circle(Vector2(18, 10), 2.0, hi)
		"bag":
			_poly(PackedVector2Array([Vector2(9, 12), Vector2(23, 12), Vector2(26, 27), Vector2(6, 27)]), c)
			_poly(PackedVector2Array([Vector2(11, 7), Vector2(21, 7), Vector2(19, 12), Vector2(13, 12)]), c.lightened(0.2))
			draw_line(Vector2(11, 12), Vector2(21, 12), Color(0.45, 0.28, 0.12, a), 2.0)
		"arrow":
			draw_line(Vector2(7, 25), Vector2(23, 9), wood, 2.0)
			_poly(PackedVector2Array([Vector2(26, 6), Vector2(19, 9), Vector2(23, 13)]), metal)
			_poly(PackedVector2Array([Vector2(7, 25), Vector2(5, 20), Vector2(10, 22)]), c)
			_poly(PackedVector2Array([Vector2(7, 25), Vector2(12, 27), Vector2(10, 22)]), c)
		"scroll":
			_poly(_rect_pts(8, 9, 16, 14), Color(0.98, 0.93, 0.78, a))
			_circle(Vector2(8, 16), 3.5, Color(0.90, 0.82, 0.64, a))
			_circle(Vector2(24, 16), 3.5, Color(0.90, 0.82, 0.64, a))
			_poly(_rect_pts(14, 9, 4, 14), c)
		"chair":
			_poly(_rect_pts(9, 5, 14, 12), c)
			_poly(_rect_pts(7, 16, 18, 4), c.darkened(0.15))
			draw_line(Vector2(9, 20), Vector2(9, 28), c.darkened(0.35), 2.0)
			draw_line(Vector2(23, 20), Vector2(23, 28), c.darkened(0.35), 2.0)
		"shell":
			_circle(Vector2(16, 17), 10.5, c)
			draw_arc(Vector2(16, 17), 7.0, 0.3, 5.6, 16, c.darkened(0.35), 1.6)
			draw_arc(Vector2(17, 17), 3.6, 1.0, 6.0, 12, c.darkened(0.35), 1.6)
			draw_circle(Vector2(12, 12), 2.0, hi)
		"shard":
			_poly(PackedVector2Array([Vector2(8, 24), Vector2(14, 6), Vector2(25, 13), Vector2(21, 26)]), c)
			draw_line(Vector2(14, 6), Vector2(16, 18), c.darkened(0.3), 1.2)
			draw_line(Vector2(16, 18), Vector2(21, 26), c.darkened(0.3), 1.2)
		"spore":
			_circle(Vector2(12, 19), 5.5, c)
			_circle(Vector2(20, 20), 5.0, c.darkened(0.08))
			_circle(Vector2(16, 12), 5.5, c.lightened(0.08))
		"mushroom":
			_poly(_rect_pts(12, 17, 8, 10), Color(0.98, 0.93, 0.80, a))
			var cap := _ellipse_pts(Vector2(16, 17), 12, 11, 0.0, 22)
			var top := PackedVector2Array()
			for p in cap:
				if p.y <= 17.01:
					top.append(p)
			_poly(top, c)
			draw_circle(Vector2(11, 12), 1.8, Color(1, 1, 1, 0.85 * a))
			draw_circle(Vector2(19, 10), 2.2, Color(1, 1, 1, 0.85 * a))
			draw_circle(Vector2(23, 14), 1.4, Color(1, 1, 1, 0.85 * a))
		"gem":
			var g := PackedVector2Array([Vector2(16, 4), Vector2(26, 12), Vector2(16, 28), Vector2(6, 12)])
			_poly(g, c)
			_poly(PackedVector2Array([Vector2(16, 4), Vector2(26, 12), Vector2(16, 12), Vector2(6, 12)]), c.lightened(0.3))
			draw_line(Vector2(16, 12), Vector2(16, 28), c.darkened(0.25), 1.0)
		"ore":
			_poly(PackedVector2Array([Vector2(5, 22), Vector2(8, 13), Vector2(15, 9), Vector2(24, 11), Vector2(28, 20),
				Vector2(22, 27), Vector2(10, 27)]), Color(0.52, 0.48, 0.44, a))
			_poly(PackedVector2Array([Vector2(12, 18), Vector2(15, 12), Vector2(18, 18)]), c)
			_poly(PackedVector2Array([Vector2(18, 21), Vector2(21, 14), Vector2(24, 21)]), c.lightened(0.2))
		"letter":
			_poly(_rect_pts(5, 9, 22, 15), c)
			draw_polyline(PackedVector2Array([Vector2(5, 9), Vector2(16, 18), Vector2(27, 9)]), Color(0.55, 0.45, 0.30, a), 1.4)
			draw_circle(Vector2(16, 18), 2.0, Color(0.85, 0.20, 0.18, a))
		"mirror":
			draw_line(Vector2(16, 20), Vector2(16, 29), wood, 3.0)
			_circle(Vector2(16, 13), 9, Color(0.86, 0.70, 0.34, a))
			_circle(Vector2(16, 13), 6.5, c)
			draw_circle(Vector2(14, 11), 1.8, hi)
		"screw":
			_poly(_rect_pts(13, 10, 6, 17), c)
			for y in [13, 17, 21, 25]:
				draw_line(Vector2(13, y), Vector2(19, y - 2), c.darkened(0.35), 1.2)
			_poly(_rect_pts(9, 6, 14, 4), c.lightened(0.1))
		"board":
			_poly(PackedVector2Array([Vector2(5, 13), Vector2(27, 8), Vector2(28, 17), Vector2(6, 22)]), c)
			draw_line(Vector2(6, 17), Vector2(27, 12), c.darkened(0.3), 1.0)
			draw_circle(Vector2(9, 15), 1.0, c.darkened(0.5))
			draw_circle(Vector2(24, 11), 1.0, c.darkened(0.5))
		"card":
			_poly(_rect_pts(8, 4, 16, 24), c)
			_poly(_star_pts(Vector2(16, 16), 6.0, 2.6), Color(1, 1, 1, 0.9 * a))
		"parcel":
			_poly(_rect_pts(7, 9, 18, 16), c)
			draw_line(Vector2(16, 9), Vector2(16, 25), c.darkened(0.35), 2.0)
		"star":
			_poly(_star_pts(Vector2(16, 16), 12.0, 5.0), c)
		"sword":
			_poly(PackedVector2Array([Vector2(12, 18), Vector2(24, 5), Vector2(27, 4), Vector2(26, 7), Vector2(14, 20)]), metal)
			draw_line(Vector2(13, 18), Vector2(24.5, 5.8), hi, 1.0)
			draw_line(Vector2(8, 15), Vector2(17, 24), c, 3.0)
			draw_line(Vector2(12, 21), Vector2(7, 26), wood, 3.0)
			_circle(Vector2(6, 27), 2.2, c)
		"dagger":
			_poly(PackedVector2Array([Vector2(13, 18), Vector2(22, 9), Vector2(25, 7), Vector2(23, 10), Vector2(15, 20)]), metal)
			draw_line(Vector2(10, 16), Vector2(17, 23), c, 3.0)
			draw_line(Vector2(13, 21), Vector2(8, 26), wood, 3.0)
		"axe":
			draw_line(Vector2(9, 28), Vector2(21, 6), wood, 3.0)
			_poly(PackedVector2Array([Vector2(18, 7), Vector2(27, 5), Vector2(29, 13), Vector2(22, 16), Vector2(16, 13)]), metal)
			draw_line(Vector2(27, 5), Vector2(29, 13), hi, 1.0)
		"club":
			_poly(PackedVector2Array([Vector2(7, 27), Vector2(10, 28), Vector2(24, 12), Vector2(20, 8)]), c)
			_circle(Vector2(22, 9), 5.5, c)
			draw_circle(Vector2(20, 7), 1.6, hi)
		"spear":
			draw_line(Vector2(5, 29), Vector2(22, 10), wood, 2.4)
			_poly(PackedVector2Array([Vector2(28, 3), Vector2(25, 12), Vector2(21, 11), Vector2(19, 8)]), metal)
		"wand":
			draw_line(Vector2(8, 27), Vector2(21, 11), wood, 2.6)
			_poly(_star_pts(Vector2(23, 8), 6.0, 2.6), c)
		"bow":
			draw_arc(Vector2(10, 16), 13.0, -1.25, 1.25, 16, wood, 3.0)
			draw_line(Vector2(14, 4), Vector2(14, 28), Color(0.95, 0.95, 0.95, a), 1.0)
			draw_circle(Vector2(23, 16), 1.6, c)
		"claw":
			for i in 3:
				draw_arc(Vector2(10 + i * 5, 20), 8.0, -1.9, -0.3, 8, metal, 2.0)
			_poly(_rect_pts(7, 20, 16, 7), c)
		"cap":
			var dome := _ellipse_pts(Vector2(16, 19), 11, 12, 0.0, 22)
			var top_half := PackedVector2Array()
			for p in dome:
				if p.y <= 19.01:
					top_half.append(p)
			_poly(top_half, c)
			_poly(_rect_pts(4, 18, 24, 5), c.darkened(0.18))
			draw_circle(Vector2(12, 12), 2.0, hi)
		"headband":
			_poly(PackedVector2Array([Vector2(4, 13), Vector2(28, 13), Vector2(28, 20), Vector2(4, 20)]), c)
			_poly(PackedVector2Array([Vector2(24, 18), Vector2(30, 27), Vector2(26, 28), Vector2(22, 20)]), c.darkened(0.15))
			draw_line(Vector2(4, 15), Vector2(28, 15), Color(1, 1, 1, 0.35 * a), 1.0)
		"shirt":
			_poly(PackedVector2Array([Vector2(4, 11), Vector2(11, 5), Vector2(21, 5), Vector2(28, 11), Vector2(24, 16),
				Vector2(22, 14), Vector2(22, 28), Vector2(10, 28), Vector2(10, 14), Vector2(8, 16)]), c)
			draw_arc(Vector2(16, 5), 3.5, 0.0, PI, 8, c.darkened(0.4), 1.4)
		"shorts":
			_poly(PackedVector2Array([Vector2(7, 8), Vector2(25, 8), Vector2(27, 22), Vector2(18, 22), Vector2(16, 15),
				Vector2(14, 22), Vector2(5, 22)]), c)
			draw_line(Vector2(7, 11), Vector2(25, 11), c.darkened(0.3), 1.2)
		"pants":
			_poly(PackedVector2Array([Vector2(8, 4), Vector2(24, 4), Vector2(26, 28), Vector2(19, 28), Vector2(16, 13),
				Vector2(13, 28), Vector2(6, 28)]), c)
			draw_line(Vector2(8, 7), Vector2(24, 7), c.darkened(0.3), 1.2)
		"skirt":
			_poly(PackedVector2Array([Vector2(10, 7), Vector2(22, 7), Vector2(28, 25), Vector2(4, 25)]), c)
			draw_line(Vector2(10, 10), Vector2(22, 10), c.darkened(0.3), 1.2)
			draw_line(Vector2(13, 12), Vector2(10, 25), c.darkened(0.15), 1.0)
			draw_line(Vector2(19, 12), Vector2(22, 25), c.darkened(0.15), 1.0)
		"overall":
			_poly(PackedVector2Array([Vector2(9, 4), Vector2(23, 4), Vector2(24, 28), Vector2(18, 28), Vector2(16, 18),
				Vector2(14, 28), Vector2(8, 28)]), c)
		"boot":
			_poly(PackedVector2Array([Vector2(9, 4), Vector2(18, 4), Vector2(18, 19), Vector2(27, 21), Vector2(28, 27),
				Vector2(8, 27)]), c)
			draw_line(Vector2(8, 24), Vector2(28, 24), c.darkened(0.35), 1.5)
		"glove":
			_poly(PackedVector2Array([Vector2(9, 28), Vector2(9, 12), Vector2(12, 6), Vector2(21, 6), Vector2(23, 12),
				Vector2(23, 28)]), c)
			_poly(PackedVector2Array([Vector2(23, 15), Vector2(28, 11), Vector2(29, 15), Vector2(23, 21)]), c.darkened(0.1))
			_poly(_rect_pts(8, 24, 16, 4), c.darkened(0.25))
		"earring":
			for x in [10.0, 22.0]:
				draw_arc(Vector2(x, 8), 3.0, PI, TAU, 8, Color(0.95, 0.80, 0.30, a), 1.5)
				draw_line(Vector2(x + 3, 8), Vector2(x, 15), Color(0.95, 0.80, 0.30, a), 1.2)
				_poly(PackedVector2Array([Vector2(x, 14), Vector2(x + 4, 19), Vector2(x, 25), Vector2(x - 4, 19)]), c)
		"cape":
			_poly(PackedVector2Array([Vector2(10, 5), Vector2(22, 5), Vector2(28, 28), Vector2(4, 28)]), c)
			draw_line(Vector2(10, 6), Vector2(22, 6), Color(0.95, 0.80, 0.30, a), 2.0)
		"shield":
			_poly(PackedVector2Array([Vector2(6, 6), Vector2(26, 6), Vector2(25, 18), Vector2(16, 28), Vector2(7, 18)]), c)
			_poly(PackedVector2Array([Vector2(16, 9), Vector2(22, 9), Vector2(21, 17), Vector2(16, 23)]), c.lightened(0.25))
		_:
			_poly(_rect_pts(6, 6, 20, 20), c)
			draw_string(MisoTheme.bold_font(), Vector2(11, 22), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
				Color(0.1, 0.1, 0.15, a))


## A filled polygon with a dark outline (the sticker look).
func _poly(pts: PackedVector2Array, fill: Color) -> void:
	if pts.size() < 3:
		return
	draw_colored_polygon(pts, fill)
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, Color(OUTLINE_COLOR, OUTLINE_COLOR.a * fill.a), 1.4, true)


func _circle(center: Vector2, r: float, fill: Color) -> void:
	draw_circle(center, r, fill)
	draw_arc(center, r, 0.0, TAU, 28, Color(OUTLINE_COLOR, OUTLINE_COLOR.a * fill.a), 1.4, true)


static func _rect_pts(x: float, y: float, w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)])


static func _ellipse_pts(center: Vector2, rx: float, ry: float, rot: float, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var t := TAU * float(i) / float(n)
		out.append(center + Vector2(cos(t) * rx, sin(t) * ry).rotated(rot))
	return out


static func _star_pts(center: Vector2, outer: float, inner: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 10:
		var r := outer if i % 2 == 0 else inner
		var t := -PI / 2.0 + PI * float(i) / 5.0
		out.append(center + Vector2(cos(t), sin(t)) * r)
	return out
