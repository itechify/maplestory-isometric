class_name NpcNameTag
extends PanelContainer
## A MapleStory-style NPC name tag: a dark rounded plate under the NPC's feet with the name in NPC yellow and, for
## shopkeepers, the canonical function title ("Grocer") on a second line. Screen-space Control placed by
## NpcPresenter, so it stays crisp at every camera size.
## An NPC with a role icon (set_role, MapIcons.npc_role of its canonical record) shows it before the name: the gold
## coin for a shopkeeper (Pan, Sid, Lucy) and the boat for a Transport NPC (Shanks), whose second line is then the
## canonical role "Transport" when it has no function title. The same icons mark them on the minimap.

const ICON_SIZE := Vector2(15, 15)

var name_label: Label = null
var title_label: Label = null
## MapIcons.ROLE_SHOP, MapIcons.ROLE_TRANSPORT or "".
var role: String = ""
var role_icon: Control = null
## The function title given to set_texts ("" for none).
var _title: String = ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", NpcUiStyle.box(NpcUiStyle.TAG_BG, Color(1, 1, 1, 0.12), 1, 4, 6, 1))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	role_icon = _RoleIcon.new(self)
	role_icon.visible = false
	row.add_child(role_icon)
	name_label = NpcUiStyle.label("", NpcUiStyle.NPC_NAME, 14, true)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(name_label)
	title_label = NpcUiStyle.label("", Color("#d8e2f0"), 11)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.visible = false
	col.add_child(title_label)


func set_texts(npc_name: String, title: String = "") -> void:
	name_label.text = npc_name
	_title = title
	_sync_title()


## Shows the role icon (MapIcons.ROLE_SHOP / ROLE_TRANSPORT; "" hides it). A Transport NPC without a function title gets
## the canonical role name on the second line (and loses it again with the role). Either call may come first.
func set_role(p_role: String) -> void:
	role = p_role
	role_icon.visible = role != ""
	role_icon.queue_redraw()
	_sync_title()


## The second line: the function title given to set_texts, else "Transport" for a Transport NPC, else none.
func _sync_title() -> void:
	var t := _title
	if t.is_empty() and role == MapIcons.ROLE_TRANSPORT:
		t = MapIcons.TRANSPORT_ROLE
	title_label.text = t
	title_label.visible = not t.is_empty()
	reset_size()


## Centres the tag horizontally under a screen point (the NPC's feet).
func place_below(screen_pos: Vector2) -> void:
	var sz := get_combined_minimum_size()
	size = sz
	position = (screen_pos + Vector2(-sz.x * 0.5, 4.0)).round()


## The role icon before the name.
class _RoleIcon extends Control:
	var tag: NpcNameTag = null

	func _init(p_tag: NpcNameTag) -> void:
		tag = p_tag
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = NpcNameTag.ICON_SIZE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _draw() -> void:
		MapIcons.draw_role(self, tag.role, size * 0.5, minf(size.x, size.y) * 0.5 - 1.0)
