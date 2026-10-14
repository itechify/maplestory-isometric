extends TestCase
## Item icons are the pack's rendered icons over the procedural base (#69): an item the pack has an icon for draws it,
## framed to fit the slot; an item without one, or any item with no pack, draws the procedural shape as before. Runs
## on the stand-in pack in tests/data/item_icon_pack; the real pack's 94 items are checked when it is installed.

const FIXTURE := "res://tests/data/item_icon_pack"
const RED_POTION := "270"
const SWORD := "541"


func after_each() -> void:
	ItemIconArt.use(null)


func _use_fixture() -> void:
	ItemIconArt.use(ItemIconArt.new(ArtPack.load_from(FIXTURE)))


func _icon(item_id: String) -> MisoItemIcon:
	var icon := MisoItemIcon.new()
	icon.set_item(item_id, db())
	return icon


func test_an_item_with_a_pack_icon_draws_it() -> void:
	_use_fixture()
	var icon := _icon(RED_POTION)
	assert_true(icon.icon_texture != null, "the Red Potion draws the pack's icon")
	assert_eq(icon.shape, "potion", "the procedural shape stays underneath")
	icon.free()


func test_an_item_without_a_pack_icon_draws_the_procedural_icon() -> void:
	_use_fixture()
	var icon := _icon(SWORD)
	assert_true(icon.icon_texture == null, "the stand-in maps the Sword to an icon file that is not there")
	assert_eq(icon.shape, "sword", "so the procedural sword draws")
	icon.set_item("348", db())
	assert_true(icon.icon_texture == null, "the stand-in has no Snail Shell at all")
	assert_eq(icon.shape, "shell")
	icon.free()


func test_without_the_pack_every_item_draws_the_procedural_icon() -> void:
	ItemIconArt.use(ItemIconArt.new(ArtPack.load_from("res://tests/data/no_such_pack")))
	var icon := _icon(RED_POTION)
	assert_true(icon.icon_texture == null, "no pack, no art")
	assert_eq(icon.shape, "potion")
	assert_eq(icon.color, MisoItemIcon.COLOR_WORDS.filter(func(p: Array) -> bool: return p[0] == "red")[0][1])
	icon.free()


func test_an_unknown_item_draws_the_grey_token_even_with_the_pack() -> void:
	_use_fixture()
	var icon := _icon("9999999")
	assert_true(icon.icon_texture == null)
	assert_eq(icon.shape, "unknown")
	assert_eq(icon.color, MisoItemIcon.UNKNOWN_COLOR)
	icon.free()


func test_the_drag_preview_carries_the_pack_icon() -> void:
	_use_fixture()
	var slot := MisoItemSlot.new()
	slot.set_stack(RED_POTION, 3, db())
	var holder := slot.drag_preview()
	var preview: MisoItemIcon = holder.get_child(0)
	assert_eq(preview.icon_texture, slot.icon.icon_texture, "the dragged potion is the pack's potion")
	assert_true(preview.icon_texture != null)
	assert_eq(preview.shape, "potion", "with the procedural shape underneath")
	holder.free()
	slot.free()


func test_the_tooltip_and_the_shop_show_the_pack_icon() -> void:
	_use_fixture()
	var tip := MisoItemTooltip.new()
	tip.show_item(RED_POTION, CharacterState.new(), db())
	var icons := tip.find_children("*", "MisoItemIcon", true, false)
	assert_eq(icons.size(), 1, "the tooltip header has one icon")
	if icons.size() == 1:
		assert_true((icons[0] as MisoItemIcon).icon_texture != null, "the tooltip shows the pack's potion")
	tip.free()
	var shop_icon := NpcUiStyle.item_icon(RED_POTION, db(), null, 30.0)
	assert_true(shop_icon is MisoItemIcon and (shop_icon as MisoItemIcon).icon_texture != null, "a shop row shows it")
	NpcUiStyle.set_icon_item(shop_icon, SWORD, db(), null)
	assert_true((shop_icon as MisoItemIcon).icon_texture == null, "the shop detail, switched to the Sword, draws its shape")
	shop_icon.free()


## The Three Snails shell is coloured by MisoItemIcon.color_for of the level's shell item (PlayerSkills._play_shell).
## The pack's icons must not change it: these are the colours before the pack.
func test_the_three_snails_shell_keeps_its_colour() -> void:
	_use_fixture()
	ItemIconArt.use(null)
	var shells := {"348": Color(0.80, 0.56, 0.30), "349": Color(0.25, 0.52, 0.95), "351": Color(0.90, 0.20, 0.18)}
	for id: String in shells:
		assert_eq(MisoItemIcon.color_for(ItemDef.of(id, db())), shells[id], "shell %s" % id)
		var icon := _icon(id)
		assert_eq(icon.color, shells[id], "shell %s's icon colour, pack or not" % id)
		icon.free()


func test_the_icon_samples_mipmaps_so_small_slots_stay_smooth() -> void:
	var icon := MisoItemIcon.new()
	assert_eq(icon.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS)
	icon.free()


# --- framing -----------------------------------------------------------------------------------------------------

func test_an_icon_is_framed_square_centred_and_never_cropped() -> void:
	_use_fixture()
	var tex := ItemIconArt.shared().texture_for(RED_POTION, db())
	assert_true(tex != null, "the Red Potion has an icon")
	if tex == null:
		return
	var img := tex.get_image()
	assert_eq(img.get_width(), ItemIconArt.SIDE, "one square size for every icon")
	assert_eq(img.get_height(), ItemIconArt.SIDE)
	var used := img.get_used_rect()
	var inner := ItemIconArt.SIDE - 2 * ItemIconArt.MARGIN
	# The stand-in draws a 12 x 40 bar in the top-left quarter of a 64 px canvas: the bar, not the canvas, fills the
	# frame, keeping its 3:10 shape, centred with the same margin on its long sides.
	assert_between(used.size.y, inner - 2, inner + 2, "the tall side fills the frame: %s" % used)
	assert_between(used.size.x, roundi(inner * 0.3) - 2, roundi(inner * 0.3) + 2, "the 3:10 shape is kept: %s" % used)
	assert_between(used.position.y, ItemIconArt.MARGIN - 2, ItemIconArt.MARGIN + 1, "the margin above: %s" % used)
	var left := used.position.x
	var right := ItemIconArt.SIDE - used.end.x
	assert_between(left - right, -2, 2, "centred across: %s" % used)
	assert_true(img.has_mipmaps(), "mipmapped, so small slots stay smooth")


# --- the real pack (SKIP without it) -------------------------------------------------------------------------------

func _skip_without_pack(test: String) -> bool:
	if ArtPack.load_installed().present():
		return false
	print("SKIP %s: no art pack installed (bash scripts/art_pack.sh fetch)" % test)
	return true


func test_every_obtainable_item_draws_a_pack_icon() -> void:
	if _skip_without_pack("test_every_obtainable_item_draws_a_pack_icon"):
		return
	var ids := db().ids("items")
	assert_eq(ids.size(), 94, "the 94 obtainable items")
	var icon := MisoItemIcon.new()
	var inner := ItemIconArt.SIDE - 2 * ItemIconArt.MARGIN
	for id in ids:
		icon.set_item(id, db())
		assert_true(icon.icon_texture != null, "item %s (%s) draws the pack's icon" % [id, ItemDef.of(id, db()).name])
		assert_ne(icon.shape, "unknown", "item %s keeps its procedural shape underneath" % id)
		if icon.icon_texture != null:
			var used := icon.icon_texture.get_image().get_used_rect()
			assert_between(maxi(used.size.x, used.size.y), inner - 2, inner + 2, "item %s fills the frame: %s" % [id, used])
			assert_true(Rect2i(0, 0, ItemIconArt.SIDE, ItemIconArt.SIDE).encloses(used), "item %s is not cropped" % id)
	icon.free()
