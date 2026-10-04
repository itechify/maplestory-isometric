class_name ScreenKit
extends RefCounted
## Small builders shared by the shell's screens (title, creation, loading, pause menu, death notice), all built in
## code. The look comes from MisoTheme (res://scripts/ui/theme/miso_theme.gd, the HUD system's theme) when that
## script exists; otherwise Godot's default theme plus a few local style boxes, so the screens never depend on it.
## MisoTheme is loaded by path, not by class name, so the shell still compiles without it.

const MISO_THEME_PATH := "res://scripts/ui/theme/miso_theme.gd"

## Fallback colours (used only without MisoTheme; MisoTheme's palette otherwise).
const FALLBACK_PANEL := Color(0.235, 0.302, 0.408, 0.95)
const FALLBACK_BORDER := Color(0.78, 0.86, 0.97, 0.95)
const FALLBACK_INSET := Color(0.13, 0.17, 0.25, 0.85)
const ACCENT := Color(1.0, 0.62, 0.16)
const GOLD := Color(1.0, 0.85, 0.36)
const TEXT := Color(0.97, 0.98, 1.0)
const TEXT_DIM := Color(0.72, 0.79, 0.89)
const BAD := Color(1.0, 0.45, 0.42)
const GOOD := Color(0.55, 0.92, 0.50)
const OUTLINE := Color(0.04, 0.06, 0.11, 0.95)

static var _theme_checked := false
static var _theme: Theme = null
static var _miso: GDScript = null


## MisoTheme.get_theme() when the HUD system's theme exists, else null (Godot's default theme).
static func theme() -> Theme:
	if not _theme_checked:
		_theme_checked = true
		if ResourceLoader.exists(MISO_THEME_PATH):
			_miso = load(MISO_THEME_PATH) as GDScript
			if _miso != null and _miso.can_instantiate():
				var t: Variant = _miso.call("get_theme")
				_theme = t if t is Theme else null
	return _theme


## True when the screens use MisoTheme.
static func has_miso_theme() -> bool:
	return theme() != null


## Applies the theme to a screen root.
static func apply(root: Control) -> void:
	root.theme = theme()


## A full-rect Control (the root of a screen).
static func full_rect(node: Control) -> Control:
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return node


## A window panel ("MisoWindow" with MisoTheme; a rounded blue-grey box otherwise).
static func window_panel(variation: String = "MisoWindow") -> PanelContainer:
	var p := PanelContainer.new()
	if has_miso_theme():
		p.theme_type_variation = variation
	else:
		p.add_theme_stylebox_override("panel", box(FALLBACK_PANEL if variation != "MisoInset" else FALLBACK_INSET,
			FALLBACK_BORDER, 2, 10, 14))
	return p


## A recessed inner panel.
static func inset_panel() -> PanelContainer:
	return window_panel("MisoInset")


static func box(bg: Color, border: Color = Color.TRANSPARENT, border_px: int = 0, radius: int = 8,
		margin: int = 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_px)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	return s


static func label(text: String, size: int = 0, color: Color = Color(0, 0, 0, 0), variation: String = "") -> Label:
	var l := Label.new()
	l.text = text
	if variation != "" and has_miso_theme():
		l.theme_type_variation = variation
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	if color.a > 0.0:
		l.add_theme_color_override("font_color", color)
	return l


## A label with a dark outline (for text over the 3D world or a busy backdrop).
static func outlined(text: String, size: int, color: Color = TEXT, outline_px: int = 6) -> Label:
	var l := label(text, size, color)
	l.add_theme_color_override("font_outline_color", OUTLINE)
	l.add_theme_constant_override("outline_size", outline_px)
	return l


## A gold window title.
static func title(text: String, size: int = 20) -> Label:
	var l := label(text, size, Color(0, 0, 0, 0) if has_miso_theme() else GOLD, "MisoTitle")
	return l


static func button(text: String, accent: bool = false, min_width: int = 0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	if accent and has_miso_theme():
		b.theme_type_variation = "MisoAccentButton"
	if min_width > 0:
		b.custom_minimum_size.x = min_width
	b.custom_minimum_size.y = maxf(b.custom_minimum_size.y, 34)
	return b


static func vbox(separation: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	return v


static func hbox(separation: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", separation)
	return h


## Wraps `child` in a MarginContainer with `px` on every side.
static func margin(child: Control, px: int) -> MarginContainer:
	var m := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(side, px)
	m.add_child(child)
	return m


## A full-rect CenterContainer holding `child`.
static func centered(child: Control) -> CenterContainer:
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(child)
	return c


## A full-rect translucent colour (dims what is behind a menu and blocks mouse clicks through it).
static func dim(color: Color = Color(0, 0, 0, 0.45)) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	return r


## A thin horizontal separator.
static func separator() -> HSeparator:
	return HSeparator.new()


## A progress bar styled as a gauge (MisoTheme.style_gauge with the EXP colour when available).
static func gauge(fill: Color = GOLD) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 18)
	if has_miso_theme() and _miso != null:
		_miso.call("style_gauge", bar, fill)
	else:
		bar.add_theme_stylebox_override("background", box(Color(0.05, 0.07, 0.11, 0.92), Color.TRANSPARENT, 0, 5, 0))
		bar.add_theme_stylebox_override("fill", box(fill, Color.TRANSPARENT, 0, 5, 0))
	return bar


## "1,234,567".
static func thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out
