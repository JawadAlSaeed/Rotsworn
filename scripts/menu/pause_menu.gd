class_name PauseMenu
extends CanvasLayer
## The pause menu (DESIGN.md 7.5): over a fight, a zone or the run map. Continue, Settings, and
## Abandon run (in a run) or Leave (practice). Pause (Esc / Menu) or Back also continues.
## Main stops whatever is under it while it is open.

signal resumed
signal settings_requested
signal leave_requested
## The extra item (the tutorial's "Skip this lesson").
signal extra_requested

const TITLE_SIZE: int = 72
const DETAIL_SIZE: int = 26
const DIM := Color(0.0, 0.0, 0.0, 0.7)

enum Item { CONTINUE, SETTINGS, LEAVE, EXTRA }

var _menu: ListMenu
## What each row is (Item), in order.
var _rows: Array[int] = []


## `leave_text`: "Abandon run" or "Leave"; `leave_detail` says where it goes. `extra_text`: one
## more row after Continue (empty: none).
func setup(leave_text: String, leave_detail: String, extra_text: String = "", extra_detail: String = "") -> void:
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
	column.add_child(ListMenu.centred_title("PAUSED", TITLE_SIZE))
	column.add_child(ListMenu.divider())
	_menu = ListMenu.new()
	column.add_child(_menu)
	var detail := ListMenu.centred_label("", DETAIL_SIZE, HudStyle.TEXT_DIM)
	column.add_child(detail)
	var items: Array[Dictionary] = [{"text": "Continue", "detail": ""}]
	_rows = [Item.CONTINUE]
	if not extra_text.is_empty():
		items.append({"text": extra_text, "detail": extra_detail})
		_rows.append(Item.EXTRA)
	items.append({"text": "Settings", "detail": "Graphics, sound, controls and lag calibration."})
	items.append({"text": leave_text, "detail": leave_detail})
	_rows.append_array([Item.SETTINGS, Item.LEAVE])
	_menu.set_items(items, detail)
	ListMenu.screen_footer(self, [[&"@updown", "Choose"], [&"menu_confirm", "Select"], [&"pause", "Continue"]])


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
			match _rows[_menu.index]:
				Item.CONTINUE:
					resumed.emit()
				Item.SETTINGS:
					settings_requested.emit()
				Item.LEAVE:
					leave_requested.emit()
				Item.EXTRA:
					extra_requested.emit()
