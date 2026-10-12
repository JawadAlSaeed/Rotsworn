class_name PauseMenu
extends CanvasLayer
## The pause menu (DESIGN.md 7.5): over a fight, a zone or the run map. Continue, Settings, and
## Abandon run (in a run) or Leave (practice). Pause (Esc / Menu) or Back also continues.
## Main stops whatever is under it while it is open.

signal resumed
signal settings_requested
signal leave_requested

const TITLE_SIZE: int = 72
const DETAIL_SIZE: int = 26
const DIM := Color(0.0, 0.0, 0.0, 0.7)

enum Item { CONTINUE, SETTINGS, LEAVE }

var _menu: ListMenu


## `leave_text`: "Abandon run" or "Leave"; `leave_detail` says where it goes.
func setup(leave_text: String, leave_detail: String) -> void:
	layer = 50
	var bg := ColorRect.new()
	bg.color = DIM
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 18)
	add_child(column)
	column.add_child(ListMenu.centred_label("PAUSED", TITLE_SIZE, HudStyle.GOLD))
	_menu = ListMenu.new()
	column.add_child(_menu)
	var detail := ListMenu.centred_label("", DETAIL_SIZE, HudStyle.TEXT_DIM)
	column.add_child(detail)
	var items: Array[Dictionary] = [
		{"text": "Continue", "detail": "%s or %s also continues." % [HudStyle.binding_text(&"pause"),
				HudStyle.binding_text(&"menu_cancel")]},
		{"text": "Settings", "detail": "Volume, fullscreen, training ring, lag calibration."},
		{"text": leave_text, "detail": leave_detail},
	]
	_menu.set_items(items, detail)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause", false, true):
		get_viewport().set_input_as_handled()
		Sfx.play("menu_cancel")
		resumed.emit()
		return
	match _menu.handle(event):
		&"cancel":
			Sfx.play("menu_cancel")
			resumed.emit()
		&"confirm":
			Sfx.play("menu_confirm")
			match _menu.index:
				Item.CONTINUE:
					resumed.emit()
				Item.SETTINGS:
					settings_requested.emit()
				Item.LEAVE:
					leave_requested.emit()
