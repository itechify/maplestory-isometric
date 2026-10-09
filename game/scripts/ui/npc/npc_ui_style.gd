class_name NpcUiStyle
extends RefCounted
## The look of the world-UI pieces (interaction prompt, NPC name tags and quest markers, the dialogue window, the shop
## window), built in code (no Nexon art).
##
## The window chrome follows the HUD's MisoTheme (res://scripts/ui/theme/miso_theme.gd) whenever that script exists:
## its window panel and title strip, its buttons (orange accent / blue secondary), its Nunito font and palette, so the
## dialogue and shop read as part of the same UI as the HUD and the inventory. MisoTheme is loaded by path, never by
## class name, so this file compiles (and falls back to an equivalent local style) without it.
##
## What stays local on purpose: the parchment "paper" body the dialogue text and the shop lists sit on (MapleStory's NPC
## chat is dark text on a light page, and canonical text carries red/blue/green emphasis that reads best on light),
## the name tags and the quest markers.

const MISO_THEME_PATH := "res://scripts/ui/theme/miso_theme.gd"
const MISO_COIN_ICON_PATH := "res://scripts/ui/common/coin_icon.gd"

# Paper (local) palette.
const BODY := Color("#fdf8ea")
const BODY_ALT := Color("#f3ecd6")
const BODY_EDGE := Color("#c9b98f")
const INK := Color("#2b2620")
const INK_SOFT := Color("#6b6255")
const SELECT := Color("#ffe8a6")
const SELECT_EDGE := Color("#d9a440")
const RED := Color("#d0252b")
const GREEN := Color("#2e8b3a")
# World overlay (local) palette.
const TAG_BG := Color(0.07, 0.09, 0.13, 0.78)
const NPC_NAME := Color("#ffe98a")
# Local chrome fallback (used only without MisoTheme).
const _FRAME := Color("#22314a")
const _FRAME_LIGHT := Color("#4d6d9a")
const _TITLE := Color("#33507c")
const _GOLD := Color("#f7b733")
const _GOLD_DARK := Color("#c3801b")
const _GOLD_LIGHT := Color("#ffd264")
const _SLATE := Color("#dfe6ef")
const _SLATE_DARK := Color("#8ea2bd")

static var _miso: Script = null
static var _miso_checked := false
static var _bold: Font = null
static var _regular: Font = null


# --- MisoTheme bridge ----------------------------------------------------------------------------------------------

## The MisoTheme script when it exists and compiles, else null.
static func miso() -> Script:
	if not _miso_checked:
		_miso_checked = true
		if ResourceLoader.exists(MISO_THEME_PATH):
			var s: Variant = load(MISO_THEME_PATH)
			if s is Script and (s as Script).can_instantiate():
				_miso = s
	return _miso


## MisoTheme.get_theme() when available, else null.
static func base_theme() -> Theme:
	var m := miso()
	if m == null:
		return null
	var t: Variant = m.call("get_theme")
	return t if t is Theme else null


## Applies the base theme (if any) to a root control.
static func apply_base(root: Control) -> void:
	var t := base_theme()
	if t != null:
		root.theme = t


## A MisoTheme colour constant by name, or `fallback`.
static func miso_color(const_name: String, fallback: Color) -> Color:
	var m := miso()
	if m == null:
		return fallback
	var v: Variant = m.get_script_constant_map().get(const_name)
	return v if v is Color else fallback


## Chrome colours (text on the window frame): "title" (gold), "text" (light), "dim" (secondary).
static func chrome(kind: String) -> Color:
	match kind:
		"title":
			return miso_color("GOLD", Color("#ffe7a3"))
		"dim":
			return miso_color("TEXT_DIM", Color("#b9c8de"))
		"accent":
			return miso_color("ACCENT", _GOLD)
	return miso_color("TEXT", Color.WHITE)


# --- fonts ---------------------------------------------------------------------------------------------------------

static func bold_font() -> Font:
	if _bold == null:
		var m := miso()
		var f: Variant = m.call("bold_font") if m != null else null
		if f is Font:
			_bold = f
		else:
			var fv := FontVariation.new()
			fv.base_font = ThemeDB.fallback_font
			fv.variation_embolden = 0.75
			_bold = fv
	return _bold


static func regular_font() -> Font:
	if _regular == null:
		var m := miso()
		var f: Variant = m.call("font") if m != null else null
		_regular = f if f is Font else ThemeDB.fallback_font
	return _regular


# --- style boxes ---------------------------------------------------------------------------------------------------

static func box(bg: Color, border: Color = Color.TRANSPARENT, border_w: int = 0, radius: int = 6,
		pad_h: float = 10.0, pad_v: float = 8.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad_h
	s.content_margin_right = pad_h
	s.content_margin_top = pad_v
	s.content_margin_bottom = pad_v
	s.anti_aliasing = true
	return s


## The outer window frame (MisoTheme's window panel, padded a little more for these larger windows).
static func window_frame() -> StyleBoxFlat:
	var m := miso()
	var v: Variant = m.call("panel_style", "window") if m != null else null
	if v is StyleBoxFlat:
		var s := (v as StyleBoxFlat).duplicate() as StyleBoxFlat
		s.set_content_margin_all(12)
		# Opaque: the chat and the shop are modal and sit over the HUD's map banner and log, which showed through
		# MisoTheme's slightly translucent window body (the arrival banner over Lucy's shop header).
		s.bg_color.a = 1.0
		return s
	var f := box(_FRAME, _FRAME_LIGHT, 2, 10, 12, 12)
	f.shadow_color = Color(0, 0, 0, 0.35)
	f.shadow_size = 8
	f.shadow_offset = Vector2(0, 3)
	return f


## A title strip (MisoTheme's).
static func title_bar() -> StyleBoxFlat:
	var m := miso()
	var v: Variant = m.call("title_bar_style") if m != null else null
	if v is StyleBoxFlat:
		return v
	return box(_TITLE, _FRAME_LIGHT, 1, 6, 10, 4)


## A dark recessed plate (MisoTheme's inset): name plates, the meso display.
static func inset() -> StyleBoxFlat:
	var m := miso()
	var v: Variant = m.call("panel_style", "inset") if m != null else null
	if v is StyleBoxFlat:
		return v
	return box(Color("#1b2638"), Color("#5f7fae"), 1, 4, 8, 3)


## The paper page (local): dialogue text, shop lists and details.
static func body_panel() -> StyleBoxFlat:
	return box(BODY, BODY_EDGE, 1, 6, 14, 12)


## Styles a Button: "primary" (MisoTheme accent, orange) or "secondary" (MisoTheme blue). Buttons never take keyboard
## focus: the windows read keys themselves, so Enter cannot press a focused button a second time.
static func style_button(b: Button, kind: String = "primary") -> void:
	var accent := kind == "primary"
	var m := miso()
	if m != null:
		for state in ["normal", "hover", "pressed", "disabled"]:
			var sb: Variant = m.call("button_style", state, accent)
			if sb is StyleBox:
				b.add_theme_stylebox_override(state, sb)
		var ink := chrome("text")
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(c, ink)
		b.add_theme_color_override("font_disabled_color", chrome("dim"))
	else:
		var bg := _GOLD if accent else _SLATE
		var border := _GOLD_DARK if accent else _SLATE_DARK
		var hover := _GOLD_LIGHT if accent else Color("#eef2f8")
		var ink := Color("#3a2208") if accent else Color("#23324a")
		b.add_theme_stylebox_override("normal", box(bg, border, 2, 6, 14, 5))
		b.add_theme_stylebox_override("hover", box(hover, border, 2, 6, 14, 5))
		b.add_theme_stylebox_override("pressed", box(bg.darkened(0.12), border, 2, 6, 14, 5))
		b.add_theme_stylebox_override("disabled", box(bg.lerp(Color("#bbbbbb"), 0.6), border.lerp(Color("#999999"), 0.6), 2, 6, 14, 5))
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(c, ink)
		b.add_theme_color_override("font_disabled_color", ink.lerp(Color("#888888"), 0.6))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_override("font", bold_font())
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


## A label in the given colour/size, optionally bold, in the UI font.
static func label(text: String, color: Color = INK, font_size: int = 16, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_font_override("font", bold_font() if bold else regular_font())
	return l


## Applies the UI fonts to a RichTextLabel (normal + bold) at a size, ink colour on paper.
static func style_rich(r: RichTextLabel, font_size: int, ink: Color = INK) -> void:
	r.add_theme_color_override("default_color", ink)
	r.add_theme_font_override("normal_font", regular_font())
	r.add_theme_font_override("bold_font", bold_font())
	r.add_theme_font_size_override("normal_font_size", font_size)
	r.add_theme_font_size_override("bold_font_size", font_size)


# --- icons ---------------------------------------------------------------------------------------------------------

## An item icon `side` px square: the inventory's MisoItemIcon, so the item's pack art when an icon pack has it
## (MisoIconResolver), else its procedural icon. Pack art is drawn at whole multiples of its 32 px cell: a 32 px box
## shows it at 1x, a 64 px box at 2x.
static func item_icon(item_id: String, db: ContentDB, side: float = 32.0) -> MisoItemIcon:
	var icon := MisoItemIcon.new()
	icon.custom_minimum_size = Vector2(side, side)
	icon.set_item(item_id, db)
	return icon


## Updates an icon made by item_icon() to show another item.
static func set_icon_item(icon: MisoItemIcon, item_id: String, db: ContentDB) -> void:
	if icon != null:
		icon.set_item(item_id, db)


## A meso coin icon: the HUD's MisoCoinIcon when it exists, else a LootItemIcon coin.
static func coin_icon(side: float = 20.0) -> Control:
	if ResourceLoader.exists(MISO_COIN_ICON_PATH):
		var s: Variant = load(MISO_COIN_ICON_PATH)
		if s is Script and (s as Script).can_instantiate():
			var icon: Variant = (s as Script).new(side)
			if icon is Control:
				return icon
	return LootItemIcon.new({"shape": "meso", "body": Color("#f4c430"), "coins": 1}, side)


## A deterministic badge colour for an id (portraits, fallback icons).
static func id_color(id: String) -> Color:
	var h := float(absi(hash(id)) % 360) / 360.0
	return Color.from_hsv(h, 0.45, 0.82)
