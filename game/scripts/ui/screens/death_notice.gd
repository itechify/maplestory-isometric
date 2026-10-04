class_name DeathNotice
extends Control
## The classic death prompt: "You have died. Return to the nearest town?" with one OK button. Modal (the
## DeathController pushes it on the GameContext); Esc does not close it. OK emits `confirmed` once.

signal confirmed

const TEXT := "You have died. Return to the nearest town?"

var ok_button: Button = null
var message: Label = null
var detail: Label = null
var _sent := false


func _init() -> void:
	name = "DeathNotice"
	ScreenKit.full_rect(self)
	ScreenKit.apply(self)
	add_child(ScreenKit.dim(Color(0.15, 0.0, 0.0, 0.28)))
	var panel := ScreenKit.window_panel()
	panel.custom_minimum_size = Vector2(440, 0)
	var v := ScreenKit.vbox(14)
	panel.add_child(ScreenKit.margin(v, 8))
	message = ScreenKit.label(TEXT, 18, Color(0, 0, 0, 0), "MisoHeading")
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size = Vector2(400, 0)
	v.add_child(message)
	detail = ScreenKit.label("", 13, ScreenKit.TEXT_DIM, "MisoDim")
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.visible = false
	v.add_child(detail)
	var row := ScreenKit.hbox()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	ok_button = ScreenKit.button("OK", true, 130)
	ok_button.name = "OK"
	ok_button.pressed.connect(confirm)
	row.add_child(ok_button)
	v.add_child(row)
	# Below the screen centre, where the camera keeps the player, so the fallen character stays visible.
	var c := ScreenKit.centered(panel)
	c.offset_top = 260
	add_child(c)


## Shows the notice (`where`: a line under the question, e.g. the town the player returns to).
func open(where: String = "") -> void:
	_sent = false
	ok_button.disabled = false
	detail.text = where
	detail.visible = where != ""
	show()
	ok_button.grab_focus()


## OK: emits `confirmed` once per open().
func confirm() -> void:
	if _sent:
		return
	_sent = true
	ok_button.disabled = true
	confirmed.emit()
