class_name ConfirmPrompt
extends CanvasLayer
## A yes/no question over everything (for example "Quit this run?"). "No" is selected first, and
## Cancel always means no. The two answers sit side by side (phase 22: two or three choices never
## stack), No on the left. Optional icon chips under the question (card #288: a shrine's price and
## gift, ListMenu.chip) can stand in for the line of detail.

signal answered(yes: bool)

const TEXT_SIZE: int = 44
const DETAIL_SIZE: int = 28
const DIM := Color(0.0, 0.0, 0.0, 0.75)
## How wide the chips under the question may run before they wrap.
const CHIPS_WIDTH: float = 900.0

var _menu: ListMenu
var _chips: VBoxContainer


## `chips`: [{icon: Texture2D or glyph, text, color}] (ListMenu.chip) shown under the question; an
## empty `detail` shows no line.
func setup(question: String, detail: String, yes_text: String, no_text: String, chips: Array = []) -> void:
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
	if not chips.is_empty():
		_chips = ListMenu.chip_lines(chips, CHIPS_WIDTH)
		_chips.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(_chips)
	if not detail.is_empty() or chips.is_empty():
		column.add_child(ListMenu.centred_label(detail, DETAIL_SIZE, HudStyle.TEXT_DIM))
	_menu = ListMenu.new()
	_menu.horizontal = true
	column.add_child(_menu)
	var items: Array[Dictionary] = [{"text": no_text}, {"text": yes_text}]
	_menu.set_items(items)


## How many chips show under the question (tests).
func chip_count() -> int:
	if _chips == null:
		return 0
	var count := 0
	for line: Node in _chips.get_children():
		count += line.get_child_count()
	return count


func _unhandled_input(event: InputEvent) -> void:
	match _menu.handle(event):
		&"confirm":
			Sfx.play("menu_confirm")
			answered.emit(_menu.index == 1)
		&"cancel":
			Sfx.play("menu_cancel")
			answered.emit(false)
