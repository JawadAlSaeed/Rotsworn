class_name ConfirmPrompt
extends CanvasLayer
## A yes/no question over everything (for example "Quit this run?"). "No" is selected first, and
## Cancel always means no.

signal answered(yes: bool)

const TEXT_SIZE: int = 44
const DETAIL_SIZE: int = 28
const DIM := Color(0.0, 0.0, 0.0, 0.75)

var _menu: ListMenu


func setup(question: String, detail: String, yes_text: String, no_text: String) -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	column.add_child(ListMenu.centred_title(question, TEXT_SIZE))
	column.add_child(ListMenu.divider())
	column.add_child(ListMenu.centred_label(detail, DETAIL_SIZE, HudStyle.TEXT_DIM))
	_menu = ListMenu.new()
	column.add_child(_menu)
	var items: Array[Dictionary] = [{"text": no_text}, {"text": yes_text}]
	_menu.set_items(items)


func _unhandled_input(event: InputEvent) -> void:
	match _menu.handle(event):
		&"confirm":
			Sfx.play("menu_confirm")
			answered.emit(_menu.index == 1)
		&"cancel":
			Sfx.play("menu_cancel")
			answered.emit(false)
