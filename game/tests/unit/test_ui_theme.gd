extends TestCase
## MisoTheme: the shared UI theme builds, caches, registers its type variations and loads the vendored OFL font.


func test_theme_is_cached_and_complete() -> void:
	var t := MisoTheme.get_theme()
	assert_true(t != null, "theme built")
	assert_true(MisoTheme.get_theme() == t, "theme cached")
	for v in ["MisoWindow", "MisoInset", "MisoSlot", "MisoHud", "MisoTooltip", "MisoTitleBar", "MisoBanner"]:
		assert_eq(String(t.get_type_variation_base(v)), "PanelContainer", v)
		assert_true(t.has_stylebox("panel", v), "%s has a panel style" % v)
	for v in ["MisoTitle", "MisoHeading", "MisoDim", "MisoGold", "MisoHudNumber", "MisoBad", "MisoGood", "MisoSmall"]:
		assert_eq(String(t.get_type_variation_base(v)), "Label", v)
	for v in ["MisoAccentButton", "MisoCloseButton", "MisoTabButton", "MisoFlatButton"]:
		assert_eq(String(t.get_type_variation_base(v)), "Button", v)
	assert_true(t.has_stylebox("fill", "ProgressBar"), "gauge fill")
	assert_true(t.has_stylebox("panel", "TooltipPanel"), "tooltip panel")


func test_font_loads_and_weights_differ() -> void:
	var regular := MisoTheme.font(MisoTheme.WEIGHT_REGULAR)
	var bold := MisoTheme.bold_font()
	assert_true(regular is FontVariation, "font variation")
	assert_true(MisoTheme.font(MisoTheme.WEIGHT_REGULAR) == regular, "fonts cached per weight")
	assert_true(regular != bold, "bold is its own font")
	var base: Font = (regular as FontVariation).base_font
	assert_true(base != null, "base font")
	assert_true(base != ThemeDB.fallback_font, "the vendored Nunito font loaded (not the engine fallback)")
	assert_true(FileAccess.file_exists("res://assets/fonts/nunito/OFL.txt"), "OFL license vendored beside the font")


func test_helpers() -> void:
	assert_eq(MisoTheme.thousands(0), "0")
	assert_eq(MisoTheme.thousands(999), "999")
	assert_eq(MisoTheme.thousands(1000), "1,000")
	assert_eq(MisoTheme.thousands(1234567), "1,234,567")
	assert_eq(MisoTheme.thousands(-45000), "-45,000")
	var l := MisoTheme.make_label("12", 14, MisoTheme.GOLD, 4)
	assert_eq(l.text, "12")
	assert_eq(l.get_theme_constant("outline_size"), 4, "outline applied")
	l.free()
	var bar := ProgressBar.new()
	MisoTheme.style_gauge(bar, MisoTheme.HP)
	assert_eq((bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color, MisoTheme.HP, "gauge fill colour")
	assert_false(bar.show_percentage, "gauge text is drawn by the caller")
	bar.free()
	var tick := MisoTheme.check_texture(true)
	assert_true(tick != null and tick.get_width() == 16, "check texture")
	assert_true(MisoTheme.check_texture(true) == tick, "check texture cached")
	for kind in ["window", "inset", "slot", "slot_hover", "slot_selected", "hud", "tooltip", "banner", "notice"]:
		assert_true(MisoTheme.panel_style(kind) is StyleBoxFlat, kind)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		assert_true(MisoTheme.button_style(state) != null, state)
		assert_true(MisoTheme.button_style(state, true) != null, "accent " + state)
