class_name MisoTheme
extends RefCounted
## MisoStory's UI look, built in code: a MapleStory-inspired (not copied) visual language of soft blue-grey
## translucent panels with light borders and rounded corners, orange/gold highlights, and outlined text for HUD
## numbers. Every UI system (HUD, windows, dialogue, shop, menus, debug) uses it so the game reads as one thing.
##
##   var root := Control.new()
##   root.theme = MisoTheme.get_theme()                 # cached; one Theme for the whole UI
##   title.theme_type_variation = &"MisoTitle"          # gold window title
##   ok_button.theme_type_variation = &"MisoAccentButton"
##   MisoTheme.style_gauge(hp_bar, MisoTheme.HP)        # red HUD gauge
##   var lbl := MisoTheme.make_label("1,234", 16, MisoTheme.TEXT, 4)   # outlined HUD number
##
## Font: Nunito (SIL OFL 1.1, res://assets/fonts/nunito/), a rounded sans; weights come from the variable font's
## wght axis. When the font cannot be loaded (e.g. before an import pass) Godot's default font is used silently.
##
## Type variations registered on the theme (set Control.theme_type_variation):
##   Labels:  MisoTitle (gold, bold), MisoHeading (bold), MisoDim (secondary text), MisoGold, MisoHudNumber
##            (bold, dark outline), MisoBad (red, unmet requirements), MisoGood (green, bonuses), MisoSmall
##   Panels:  MisoWindow (window body), MisoInset (recessed content area), MisoSlot (an item slot), MisoHud (HUD
##            bar), MisoTitleBar (window title strip), MisoTooltip (tooltip card), MisoBanner (map name banner)
##   Buttons: MisoAccentButton (orange call to action), MisoCloseButton (small round "x"), MisoTabButton (a toggle
##            tab), MisoFlatButton (borderless, list rows)

# --- palette --------------------------------------------------------------------------------------------------

## Window body: soft blue-grey, slightly translucent.
const PANEL := Color(0.43, 0.53, 0.67, 0.93)
## Window border: light, cool.
const PANEL_BORDER := Color(0.88, 0.93, 1.0, 0.95)
## Recessed content (lists, slot grids).
const INSET := Color(0.13, 0.17, 0.25, 0.88)
const INSET_BORDER := Color(0.25, 0.32, 0.44, 1.0)
## Title strip.
const TITLE_BAR := Color(0.24, 0.35, 0.53, 1.0)
const TITLE_BAR_LIGHT := Color(0.47, 0.60, 0.80, 1.0)
## HUD bar.
const HUD_BG := Color(0.11, 0.15, 0.22, 0.86)
## Orange / gold highlights.
const ACCENT := Color(1.0, 0.62, 0.16)
const ACCENT_LIGHT := Color(1.0, 0.78, 0.38)
const ACCENT_DARK := Color(0.78, 0.40, 0.05)
const GOLD := Color(1.0, 0.85, 0.36)
## Text.
const TEXT := Color(0.97, 0.98, 1.0)
const TEXT_DIM := Color(0.72, 0.79, 0.89)
const TEXT_DARK := Color(0.10, 0.12, 0.18)
const OUTLINE := Color(0.04, 0.06, 0.11, 0.95)
const BAD := Color(1.0, 0.40, 0.38)
const GOOD := Color(0.55, 0.92, 0.50)
## Gauges.
const HP := Color(0.92, 0.25, 0.22)
const MP := Color(0.24, 0.53, 0.96)
const EXP := Color(0.98, 0.83, 0.20)
const GAUGE_BG := Color(0.05, 0.07, 0.11, 0.92)
## Item slots.
const SLOT := Color(0.17, 0.22, 0.32, 0.95)
const SLOT_BORDER := Color(0.47, 0.57, 0.72, 1.0)
const SLOT_HOVER := Color(0.27, 0.35, 0.50, 1.0)
const SLOT_SELECTED := Color(1.0, 0.70, 0.25, 1.0)
## Message log line colours (classic chat-log feel).
const LOG_ITEM := Color(0.98, 0.98, 1.0)
const LOG_MESOS := Color(1.0, 0.86, 0.40)
const LOG_EXP := Color(1.0, 0.93, 0.45)
const LOG_QUEST := Color(0.55, 0.85, 1.0)
const LOG_WARN := Color(1.0, 0.50, 0.45)
const LOG_INFO := Color(0.80, 0.86, 0.95)

## Corner radii and sizes.
const RADIUS_WINDOW := 10
const RADIUS_INSET := 6
const RADIUS_BUTTON := 7
const FONT_SIZE := 15
const FONT_SIZE_SMALL := 13
const FONT_SIZE_TITLE := 16

const FONT_PATH := "res://assets/fonts/nunito/Nunito-Variable.ttf"
## Weights on the variable font's wght axis.
const WEIGHT_REGULAR := 600
const WEIGHT_BOLD := 800
const WEIGHT_BLACK := 900

static var _theme: Theme = null
static var _base_font: Font = null
static var _base_font_tried := false
static var _fonts: Dictionary = {}
static var _check_textures: Dictionary = {}


# --- the theme ------------------------------------------------------------------------------------------------

## The shared MisoStory Theme (built once, then cached). Assign it to a UI root Control.
static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build_theme()
	return _theme


## Drops the cached theme and fonts (tests, live tweaking).
static func reset_cache() -> void:
	_theme = null
	_fonts = {}
	_base_font = null
	_base_font_tried = false
	_check_textures = {}


# --- fonts ----------------------------------------------------------------------------------------------------

## The UI font at a wght-axis weight (WEIGHT_REGULAR, WEIGHT_BOLD, WEIGHT_BLACK). Falls back to the engine default
## font (with emboldening for heavy weights) when Nunito is not available.
static func font(weight: int = WEIGHT_REGULAR) -> Font:
	if _fonts.has(weight):
		return _fonts[weight]
	var fv := FontVariation.new()
	var base := _load_base_font()
	if base != null:
		fv.base_font = base
		var ts := TextServerManager.get_primary_interface()
		if ts != null:
			fv.variation_opentype = {ts.name_to_tag("wght"): weight}
	else:
		fv.base_font = ThemeDB.fallback_font
		fv.variation_embolden = clampf(float(weight - WEIGHT_REGULAR) / 400.0, 0.0, 0.8)
	_fonts[weight] = fv
	return fv


static func bold_font() -> Font:
	return font(WEIGHT_BOLD)


static func black_font() -> Font:
	return font(WEIGHT_BLACK)


static func _load_base_font() -> Font:
	if _base_font_tried:
		return _base_font
	_base_font_tried = true
	if ResourceLoader.exists(FONT_PATH):
		var res: Resource = ResourceLoader.load(FONT_PATH)
		if res is Font:
			_base_font = res
	if _base_font == null and FileAccess.file_exists(FONT_PATH):
		var ff := FontFile.new()
		if ff.load_dynamic_font(FONT_PATH) == OK:
			_base_font = ff
	return _base_font


# --- style boxes ----------------------------------------------------------------------------------------------

## A rounded flat style box. `border` 0 = no border.
static func flat(bg: Color, border_color: Color = Color.TRANSPARENT, border: int = 0, radius: int = RADIUS_INSET,
		margin: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border_color
	sb.set_border_width_all(border)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	sb.anti_aliasing = true
	sb.corner_detail = 6
	return sb


## Panel styles: "window" (window body), "inset" (recessed content), "slot" (an item slot), "slot_hover",
## "slot_selected", "hud" (HUD bar), "tooltip", "banner" (map name banner), "notice" (one log line backdrop).
static func panel_style(kind: String = "window") -> StyleBoxFlat:
	match kind:
		"window":
			var sb := flat(PANEL, PANEL_BORDER, 2, RADIUS_WINDOW, 8)
			sb.shadow_color = Color(0, 0, 0, 0.35)
			sb.shadow_size = 6
			sb.shadow_offset = Vector2(0, 3)
			return sb
		"inset":
			return flat(INSET, INSET_BORDER, 1, RADIUS_INSET, 6)
		"slot":
			return flat(SLOT, SLOT_BORDER, 1, 6, 2)
		"slot_hover":
			return flat(SLOT_HOVER, ACCENT_LIGHT, 2, 6, 2)
		"slot_selected":
			return flat(SLOT_HOVER, SLOT_SELECTED, 2, 6, 2)
		"hud":
			var hud := flat(HUD_BG, Color(0.60, 0.70, 0.86, 0.75), 2, 12, 8)
			hud.shadow_color = Color(0, 0, 0, 0.3)
			hud.shadow_size = 5
			return hud
		"tooltip":
			var tt := flat(Color(0.08, 0.11, 0.17, 0.96), ACCENT_LIGHT, 2, 8, 10)
			tt.shadow_color = Color(0, 0, 0, 0.45)
			tt.shadow_size = 6
			return tt
		"banner":
			var bn := flat(Color(0.08, 0.11, 0.18, 0.72), Color(1.0, 0.85, 0.45, 0.85), 2, 14, 12)
			bn.content_margin_left = 34
			bn.content_margin_right = 34
			return bn
		"notice":
			return flat(Color(0.04, 0.06, 0.10, 0.55), Color.TRANSPARENT, 0, 5, 3)
	return flat(PANEL, PANEL_BORDER, 2, RADIUS_WINDOW, 8)


## The window title strip: rounded top corners, square bottom, a light top edge for a bit of gloss.
static func title_bar_style() -> StyleBoxFlat:
	var sb := flat(TITLE_BAR, TITLE_BAR_LIGHT, 0, RADIUS_WINDOW - 2, 6)
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0
	sb.border_width_top = 2
	sb.border_width_bottom = 1
	sb.border_color = TITLE_BAR_LIGHT
	sb.content_margin_left = 10
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


## Button style for a state ("normal", "hover", "pressed", "disabled", "focus"). accent = the orange call-to-action.
static func button_style(state: String, accent: bool = false) -> StyleBox:
	if state == "focus":
		var f := flat(Color.TRANSPARENT, ACCENT_LIGHT, 1, RADIUS_BUTTON, 4)
		f.draw_center = false
		return f
	var base := ACCENT if accent else Color(0.33, 0.45, 0.63)
	var edge := ACCENT_LIGHT if accent else Color(0.70, 0.80, 0.94)
	var bg := base
	match state:
		"hover":
			bg = base.lightened(0.15)
		"pressed":
			bg = ACCENT_DARK if accent else ACCENT
			edge = ACCENT_LIGHT
		"disabled":
			bg = Color(0.30, 0.33, 0.40, 0.75)
			edge = Color(0.45, 0.48, 0.55, 0.75)
	var sb := flat(bg, edge, 1, RADIUS_BUTTON, 4)
	sb.border_width_top = 2
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	return sb


## {"background", "fill"} style boxes for a gauge in `fill_color` (HP, MP, EXP, or any).
static func gauge_styles(fill_color: Color, radius: int = 5) -> Dictionary:
	var bg := flat(GAUGE_BG, Color(0.55, 0.64, 0.78, 0.85), 1, radius, 0)
	var fill := flat(fill_color, fill_color.lightened(0.45), 0, radius, 0)
	fill.border_width_top = 2
	fill.border_color = fill_color.lightened(0.45)
	return {"background": bg, "fill": fill}


## Styles a ProgressBar as a MisoStory gauge (text drawn by the caller, usually an outlined Label on top).
static func style_gauge(bar: ProgressBar, fill_color: Color, radius: int = 5) -> void:
	var s := gauge_styles(fill_color, radius)
	bar.add_theme_stylebox_override("background", s["background"])
	bar.add_theme_stylebox_override("fill", s["fill"])
	bar.show_percentage = false


# --- label helpers --------------------------------------------------------------------------------------------

## A Label in the UI font. outline > 0 draws a dark outline (HUD numbers over the 3D world).
static func make_label(text: String, size: int = FONT_SIZE, color: Color = TEXT, outline: int = 0,
		weight: int = WEIGHT_REGULAR) -> Label:
	var l := Label.new()
	l.text = text
	style_label(l, size, color, outline, weight)
	return l


## Applies font, size, colour and outline to an existing Label.
static func style_label(l: Label, size: int = FONT_SIZE, color: Color = TEXT, outline: int = 0,
		weight: int = WEIGHT_REGULAR) -> void:
	l.add_theme_font_override("font", font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", OUTLINE)


## Formats an integer with thousands separators ("1,234,567"), as classic meso displays do.
static func thousands(n: int) -> String:
	var neg := n < 0
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if neg else "") + s + out


## A small procedurally drawn check box texture (quest objectives): ticked or empty.
static func check_texture(checked: bool, size: int = 16) -> Texture2D:
	var key := "%s_%d" % [checked, size]
	if _check_textures.has(key):
		return _check_textures[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var border := GOLD if checked else TEXT_DIM
	for x in size:
		for y in size:
			var edge := x <= 1 or y <= 1 or x >= size - 2 or y >= size - 2
			if edge:
				img.set_pixel(x, y, border)
			elif checked:
				img.set_pixel(x, y, Color(0.20, 0.30, 0.18, 0.9))
			else:
				img.set_pixel(x, y, Color(0.06, 0.08, 0.12, 0.8))
	if checked:
		# A tick: down-stroke then a longer up-stroke, two pixels thick.
		var pts: Array[Vector2i] = []
		var s := float(size)
		var a := Vector2(s * 0.22, s * 0.52)
		var b := Vector2(s * 0.42, s * 0.74)
		var c := Vector2(s * 0.80, s * 0.26)
		for i in 24:
			var t := float(i) / 23.0
			pts.append(Vector2i(a.lerp(b, t).round()))
			pts.append(Vector2i(b.lerp(c, t).round()))
		for p in pts:
			for d: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
				var q := p + d
				if q.x >= 0 and q.y >= 0 and q.x < size and q.y < size:
					img.set_pixelv(q, GOOD)
	var tex := ImageTexture.create_from_image(img)
	_check_textures[key] = tex
	return tex


# --- build ----------------------------------------------------------------------------------------------------

static func _build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font(WEIGHT_REGULAR)
	t.default_font_size = FONT_SIZE

	# Panels.
	t.set_stylebox("panel", "Panel", panel_style("window"))
	t.set_stylebox("panel", "PanelContainer", panel_style("window"))
	for v: Array in [["MisoWindow", "window"], ["MisoInset", "inset"], ["MisoSlot", "slot"], ["MisoHud", "hud"],
			["MisoTooltip", "tooltip"], ["MisoBanner", "banner"], ["MisoNotice", "notice"]]:
		t.set_type_variation(v[0], "PanelContainer")
		t.set_stylebox("panel", v[0], panel_style(v[1]))
	t.set_type_variation("MisoTitleBar", "PanelContainer")
	t.set_stylebox("panel", "MisoTitleBar", title_bar_style())

	# Labels.
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.35))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 1)
	t.set_color("font_outline_color", "Label", OUTLINE)
	_label_variation(t, "MisoTitle", GOLD, FONT_SIZE_TITLE, WEIGHT_BOLD, 3)
	_label_variation(t, "MisoHeading", TEXT, FONT_SIZE, WEIGHT_BOLD, 0)
	_label_variation(t, "MisoDim", TEXT_DIM, FONT_SIZE_SMALL, WEIGHT_REGULAR, 0)
	_label_variation(t, "MisoSmall", TEXT, FONT_SIZE_SMALL, WEIGHT_REGULAR, 0)
	_label_variation(t, "MisoGold", GOLD, FONT_SIZE, WEIGHT_BOLD, 0)
	_label_variation(t, "MisoBad", BAD, FONT_SIZE_SMALL, WEIGHT_BOLD, 0)
	_label_variation(t, "MisoGood", GOOD, FONT_SIZE_SMALL, WEIGHT_BOLD, 0)
	_label_variation(t, "MisoHudNumber", TEXT, FONT_SIZE_SMALL, WEIGHT_BLACK, 4)

	# Buttons.
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.set_stylebox(state, "Button", button_style(state))
	t.set_stylebox("hover_pressed", "Button", button_style("pressed"))
	t.set_font("font", "Button", font(WEIGHT_BOLD))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", TEXT_DARK)
	t.set_color("font_hover_pressed_color", "Button", TEXT_DARK)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(0.65, 0.68, 0.74))
	t.set_color("font_outline_color", "Button", OUTLINE)
	t.set_constant("outline_size", "Button", 0)

	t.set_type_variation("MisoAccentButton", "Button")
	for state in ["normal", "hover", "pressed", "disabled"]:
		t.set_stylebox(state, "MisoAccentButton", button_style(state, true))
	t.set_stylebox("hover_pressed", "MisoAccentButton", button_style("pressed", true))
	t.set_color("font_color", "MisoAccentButton", Color.WHITE)
	t.set_color("font_outline_color", "MisoAccentButton", Color(0.45, 0.20, 0.0, 0.9))
	t.set_constant("outline_size", "MisoAccentButton", 3)

	t.set_type_variation("MisoCloseButton", "Button")
	var close_n := flat(Color(0.22, 0.30, 0.44), Color(0.75, 0.84, 0.96), 1, 9, 0)
	var close_h := flat(Color(0.86, 0.33, 0.24), Color(1.0, 0.75, 0.6), 1, 9, 0)
	t.set_stylebox("normal", "MisoCloseButton", close_n)
	t.set_stylebox("hover", "MisoCloseButton", close_h)
	t.set_stylebox("pressed", "MisoCloseButton", close_h)
	t.set_stylebox("hover_pressed", "MisoCloseButton", close_h)
	t.set_color("font_pressed_color", "MisoCloseButton", Color.WHITE)
	t.set_color("font_hover_pressed_color", "MisoCloseButton", Color.WHITE)
	t.set_font_size("font_size", "MisoCloseButton", 13)

	t.set_type_variation("MisoTabButton", "Button")
	var tab_off := flat(Color(0.20, 0.27, 0.38, 0.95), Color(0.50, 0.60, 0.75), 1, 7, 3)
	tab_off.corner_radius_bottom_left = 0
	tab_off.corner_radius_bottom_right = 0
	var tab_hover := tab_off.duplicate() as StyleBoxFlat
	tab_hover.bg_color = Color(0.30, 0.40, 0.56)
	var tab_on := flat(ACCENT, ACCENT_LIGHT, 1, 7, 3)
	tab_on.corner_radius_bottom_left = 0
	tab_on.corner_radius_bottom_right = 0
	tab_on.border_width_top = 2
	t.set_stylebox("normal", "MisoTabButton", tab_off)
	t.set_stylebox("hover", "MisoTabButton", tab_hover)
	t.set_stylebox("pressed", "MisoTabButton", tab_on)
	t.set_stylebox("hover_pressed", "MisoTabButton", tab_on)
	t.set_color("font_pressed_color", "MisoTabButton", Color.WHITE)
	t.set_color("font_hover_pressed_color", "MisoTabButton", Color.WHITE)
	t.set_color("font_outline_color", "MisoTabButton", Color(0.40, 0.18, 0.0, 0.9))
	t.set_constant("outline_size", "MisoTabButton", 2)
	t.set_font_size("font_size", "MisoTabButton", FONT_SIZE_SMALL)

	t.set_type_variation("MisoFlatButton", "Button")
	var row_n := flat(Color(0, 0, 0, 0), Color.TRANSPARENT, 0, 5, 4)
	var row_h := flat(Color(0.35, 0.47, 0.66, 0.55), Color.TRANSPARENT, 0, 5, 4)
	var row_p := flat(Color(1.0, 0.62, 0.16, 0.35), ACCENT_LIGHT, 1, 5, 4)
	t.set_stylebox("normal", "MisoFlatButton", row_n)
	t.set_stylebox("hover", "MisoFlatButton", row_h)
	t.set_stylebox("pressed", "MisoFlatButton", row_p)
	t.set_stylebox("hover_pressed", "MisoFlatButton", row_p)
	t.set_font("font", "MisoFlatButton", font(WEIGHT_REGULAR))
	t.set_color("font_pressed_color", "MisoFlatButton", Color.WHITE)
	t.set_color("font_hover_pressed_color", "MisoFlatButton", Color.WHITE)
	t.set_constant("align_to_largest_stylebox", "MisoFlatButton", 0)

	# Tabs (TabBar / TabContainer) for systems that prefer the built-in controls.
	for tt in ["TabBar", "TabContainer"]:
		t.set_stylebox("tab_selected", tt, tab_on)
		t.set_stylebox("tab_unselected", tt, tab_off)
		t.set_stylebox("tab_hovered", tt, tab_hover)
		t.set_stylebox("tab_disabled", tt, tab_off)
		t.set_color("font_selected_color", tt, Color.WHITE)
		t.set_color("font_unselected_color", tt, TEXT_DIM)
		t.set_color("font_hovered_color", tt, Color.WHITE)
		t.set_font_size("font_size", tt, FONT_SIZE_SMALL)
	t.set_stylebox("panel", "TabContainer", panel_style("inset"))

	# Gauges.
	var g := gauge_styles(EXP)
	t.set_stylebox("background", "ProgressBar", g["background"])
	t.set_stylebox("fill", "ProgressBar", g["fill"])
	t.set_color("font_color", "ProgressBar", TEXT)
	t.set_color("font_outline_color", "ProgressBar", OUTLINE)
	t.set_constant("outline_size", "ProgressBar", 3)

	# Tooltips.
	t.set_stylebox("panel", "TooltipPanel", panel_style("tooltip"))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", FONT_SIZE_SMALL)

	# Text entry.
	var le := flat(Color(0.06, 0.09, 0.14, 0.92), INSET_BORDER, 1, 5, 6)
	var le_focus := flat(Color(0.06, 0.09, 0.14, 0.95), ACCENT_LIGHT, 1, 5, 6)
	for tt in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", tt, le)
		t.set_stylebox("focus", tt, le_focus)
		t.set_stylebox("read_only", tt, le)
		t.set_color("font_color", tt, TEXT)
		t.set_color("caret_color", tt, GOLD)
		t.set_color("selection_color", tt, Color(1.0, 0.62, 0.16, 0.4))
		t.set_color("font_placeholder_color", tt, Color(0.6, 0.66, 0.75, 0.8))

	# Rich text, lists, popups, separators, scroll bars.
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font("bold_font", "RichTextLabel", font(WEIGHT_BOLD))
	t.set_font("normal_font", "RichTextLabel", font(WEIGHT_REGULAR))
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	t.set_stylebox("panel", "ItemList", panel_style("inset"))
	t.set_stylebox("selected", "ItemList", row_p)
	t.set_stylebox("selected_focus", "ItemList", row_p)
	t.set_stylebox("hovered", "ItemList", row_h)
	t.set_color("font_color", "ItemList", TEXT)
	t.set_color("font_selected_color", "ItemList", Color.WHITE)
	t.set_stylebox("panel", "PopupMenu", panel_style("tooltip"))
	t.set_stylebox("hover", "PopupMenu", row_h)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_stylebox("panel", "PopupPanel", panel_style("tooltip"))
	var line := StyleBoxLine.new()
	line.color = Color(0.62, 0.72, 0.86, 0.45)
	line.thickness = 1
	t.set_stylebox("separator", "HSeparator", line)
	t.set_constant("separation", "HSeparator", 6)
	var vline := line.duplicate() as StyleBoxLine
	vline.vertical = true
	t.set_stylebox("separator", "VSeparator", vline)
	var sc_bg := flat(Color(0.05, 0.07, 0.11, 0.5), Color.TRANSPARENT, 0, 4, 0)
	var sc_grab := flat(Color(0.55, 0.66, 0.82, 0.85), Color.TRANSPARENT, 0, 4, 0)
	var sc_grab_hi := flat(ACCENT_LIGHT, Color.TRANSPARENT, 0, 4, 0)
	sc_bg.content_margin_left = 4
	sc_bg.content_margin_right = 4
	for sb_type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sb_type, sc_bg)
		t.set_stylebox("grabber", sb_type, sc_grab)
		t.set_stylebox("grabber_highlight", sb_type, sc_grab_hi)
		t.set_stylebox("grabber_pressed", sb_type, sc_grab_hi)
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())

	# Check boxes use the procedural ticks.
	t.set_icon("checked", "CheckBox", check_texture(true))
	t.set_icon("unchecked", "CheckBox", check_texture(false))
	t.set_stylebox("normal", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("hover", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("pressed", "CheckBox", StyleBoxEmpty.new())
	return t


static func _label_variation(t: Theme, name: String, color: Color, size: int, weight: int, outline: int) -> void:
	t.set_type_variation(name, "Label")
	t.set_color("font_color", name, color)
	t.set_font_size("font_size", name, size)
	t.set_font("font", name, font(weight))
	t.set_constant("outline_size", name, outline)
	t.set_color("font_outline_color", name, OUTLINE)
