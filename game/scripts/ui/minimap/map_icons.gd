class_name MapIcons
extends RefCounted
## Small procedural map icons shared by the minimap and the NPC name tags (no art, no Nexon sprite): the shop coin,
## the transport boat, the portal swirl and door, the player arrow and the quest-marker dot; and which role icon an
## NPC gets from its canonical record. All static; each draw call paints on the CanvasItem it is given.

## An NPC's role icon: a shopkeeper (a canonical `shop`, or the MeowDB role "Shopkeeper") gets the coin, a
## "Transport" NPC (Shanks) the boat, anyone else nothing.
const ROLE_SHOP := "shop"
const ROLE_TRANSPORT := "transport"
## The MeowDB role names behind them (npcs/<id>.json roles[]).
const SHOPKEEPER_ROLE := "Shopkeeper"
const TRANSPORT_ROLE := "Transport"

const COIN_RIM := Color(0.78, 0.50, 0.08)
const COIN_EDGE := Color(0.35, 0.20, 0.02, 0.9)
const BOAT_HULL := Color(0.55, 0.33, 0.16)
const BOAT_SAIL := Color(0.97, 0.96, 0.90)
const ICON_EDGE := Color(0.06, 0.08, 0.12, 0.9)
const PORTAL := Color(0.45, 0.82, 1.0)
const PORTAL_CORE := Color(0.85, 0.96, 1.0)
const DOOR := Color(0.93, 0.70, 0.36)
const DOOR_DARK := Color(0.42, 0.25, 0.10)


## ROLE_SHOP, ROLE_TRANSPORT or "" for a canonical NPC record (npcs/<id>.json).
static func npc_role(rec: Dictionary) -> String:
	if rec.get("shop") is Dictionary:
		return ROLE_SHOP
	var roles: Array = rec.get("roles") if rec.get("roles") is Array else []
	if roles.has(SHOPKEEPER_ROLE):
		return ROLE_SHOP
	if roles.has(TRANSPORT_ROLE):
		return ROLE_TRANSPORT
	return ""


## The role icon for `role` centred at `c` with radius `r` (nothing for "").
static func draw_role(ci: CanvasItem, role: String, c: Vector2, r: float) -> void:
	match role:
		ROLE_SHOP:
			draw_coin(ci, c, r)
		ROLE_TRANSPORT:
			draw_boat(ci, c, r)


## A gold coin (the MisoCoinIcon look, at any size).
static func draw_coin(ci: CanvasItem, c: Vector2, r: float) -> void:
	ci.draw_circle(c, r, COIN_RIM)
	ci.draw_circle(c + Vector2(-0.4, -0.4), r * 0.8, MisoTheme.GOLD)
	ci.draw_arc(c, r * 0.5, 0.0, TAU, 16, COIN_RIM, maxf(1.0, r * 0.14), true)
	ci.draw_arc(c, r, 0.0, TAU, 20, COIN_EDGE, 1.0, true)


## A small sailing boat: hull, mast and sail.
static func draw_boat(ci: CanvasItem, c: Vector2, r: float) -> void:
	var hull := PackedVector2Array([c + Vector2(-r, r * 0.15), c + Vector2(r, r * 0.15), c + Vector2(r * 0.6, r * 0.8),
		c + Vector2(-r * 0.6, r * 0.8)])
	var sail := PackedVector2Array([c + Vector2(-r * 0.05, -r * 0.95), c + Vector2(r * 0.75, r * 0.05),
		c + Vector2(-r * 0.05, r * 0.05)])
	ci.draw_colored_polygon(sail, BOAT_SAIL)
	ci.draw_polyline(_closed(sail), ICON_EDGE, 1.0, true)
	ci.draw_line(c + Vector2(-r * 0.1, -r * 0.95), c + Vector2(-r * 0.1, r * 0.2), ICON_EDGE, maxf(1.0, r * 0.14), true)
	ci.draw_colored_polygon(hull, BOAT_HULL)
	ci.draw_polyline(_closed(hull), ICON_EDGE, 1.0, true)


## A portal swirl: a glowing ring with a bright core.
static func draw_swirl(ci: CanvasItem, c: Vector2, r: float) -> void:
	ci.draw_circle(c, r + 1.5, Color(PORTAL, 0.35))
	ci.draw_circle(c, r, ICON_EDGE)
	ci.draw_circle(c, r - 1.2, PORTAL)
	ci.draw_arc(c, r * 0.55, 0.3, 0.3 + TAU * 0.75, 12, PORTAL_CORE, maxf(1.0, r * 0.25), true)


## A door: an arched rectangle.
static func draw_door(ci: CanvasItem, c: Vector2, r: float) -> void:
	var w := r * 0.8
	var rect := Rect2(c + Vector2(-w, -r * 0.4), Vector2(w * 2.0, r * 1.4))
	ci.draw_rect(rect.grow(1.0), ICON_EDGE)
	ci.draw_circle(c + Vector2(0, -r * 0.4), w + 1.0, ICON_EDGE)
	ci.draw_rect(rect, DOOR)
	ci.draw_circle(c + Vector2(0, -r * 0.4), w, DOOR)
	ci.draw_circle(c + Vector2(w * 0.45, r * 0.35), maxf(0.8, r * 0.14), DOOR_DARK)


## A chevron at `c` pointing along `dir` (a unit minimap direction).
static func draw_chevron(ci: CanvasItem, c: Vector2, dir: Vector2, r: float, color: Color) -> void:
	if dir == Vector2.ZERO:
		return
	var side := dir.orthogonal()
	var tip := c + dir * r
	ci.draw_polyline(PackedVector2Array([c - dir * r * 0.2 + side * r * 0.8, tip, c - dir * r * 0.2 - side * r * 0.8]),
		color, maxf(1.5, r * 0.35), true)


## The player arrow: a filled triangle pointing along `dir` (up when zero), outlined.
static func draw_arrow(ci: CanvasItem, c: Vector2, dir: Vector2, r: float, fill: Color) -> void:
	var d := dir if dir != Vector2.ZERO else Vector2.UP
	var side := d.orthogonal()
	var pts := PackedVector2Array([c + d * r * 1.15, c - d * r * 0.75 + side * r * 0.85, c - d * r * 0.35,
		c - d * r * 0.75 - side * r * 0.85])
	ci.draw_colored_polygon(pts, fill)
	ci.draw_polyline(_closed(pts), ICON_EDGE, 1.5, true)


## A quest-marker dot in QuestMarker's colours and glyph ("available" "!", "in_progress" "...", "completable" "?"),
## so a dot on the minimap reads like the badge over the NPC's head.
static func draw_marker_dot(ci: CanvasItem, state: String, c: Vector2, r: float, font: Font) -> void:
	if not QuestMarker.STYLES.has(state):
		return
	var st: Dictionary = QuestMarker.STYLES[state]
	ci.draw_circle(c, r + 1.0, st["edge"])
	ci.draw_circle(c, r, st["fill"])
	if font == null:
		return
	var glyph: String = st["glyph"]
	var fs := int(roundf(r * (1.7 if glyph.length() == 1 else 1.15)))
	var w := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string(font, Vector2(c.x - w * 0.5, c.y + font.get_ascent(fs) * 0.38), glyph, HORIZONTAL_ALIGNMENT_LEFT,
		-1, fs, st["ink"])


static func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	if not pts.is_empty():
		out.append(pts[0])
	return out
