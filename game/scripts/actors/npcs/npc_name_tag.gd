class_name NpcNameTag
extends PanelContainer
## A MapleStory-style NPC name tag: a dark rounded plate under the NPC's feet with the name in NPC yellow and, for
## shopkeepers, the canonical function title ("Grocer") on a second line. Screen-space Control placed by
## NpcPresenter, so it stays crisp at every camera size.

var name_label: Label = null
var title_label: Label = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", NpcUiStyle.box(NpcUiStyle.TAG_BG, Color(1, 1, 1, 0.12), 1, 4, 6, 1))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	name_label = NpcUiStyle.label("", NpcUiStyle.NPC_NAME, 14, true)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(name_label)
	title_label = NpcUiStyle.label("", Color("#d8e2f0"), 11)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.visible = false
	col.add_child(title_label)


func set_texts(npc_name: String, title: String = "") -> void:
	name_label.text = npc_name
	title_label.text = title
	title_label.visible = not title.is_empty()
	reset_size()


## Centres the tag horizontally under a screen point (the NPC's feet).
func place_below(screen_pos: Vector2) -> void:
	var sz := get_combined_minimum_size()
	size = sz
	position = (screen_pos + Vector2(-sz.x * 0.5, 4.0)).round()
