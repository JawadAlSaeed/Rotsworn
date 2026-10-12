class_name ListMenu
extends VBoxContainer
## A vertical list of choices for the menus outside a fight (main menu, settings, shop, rest).
## Driven only by the menu_* input actions, like the fight list: the screen that owns it passes
## each input event to handle(), which moves the cursor itself and reports the rest.

const CURSOR := "> "
const ITEM_SIZE: int = 40
const DETAIL_SIZE: int = 26

## Every item: {text: String, enabled: bool, detail: String}.
var items: Array[Dictionary] = []
var index: int = 0
var item_size: int = ITEM_SIZE
## Centre the items (main menu) or line them up on the left (shop, settings).
var centred: bool = true
var _labels: Array[Label] = []
var _detail: Label
## Process frame of the last stick move (a held stick sends many motion events).
var _stick_frame: int = -1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 12)


## Replaces the items (keeps the cursor where it was if it still fits).
func set_items(new_items: Array[Dictionary], detail_label: Label = null) -> void:
	items = new_items
	if detail_label != null:
		_detail = detail_label
	for label: Label in _labels:
		label.queue_free()
	_labels.clear()
	for i: int in items.size():
		var label := HudStyle.make_label("", item_size)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centred else HORIZONTAL_ALIGNMENT_LEFT
		add_child(label)
		_labels.append(label)
	index = clampi(index, 0, maxi(0, items.size() - 1))
	redraw()


func set_item(i: int, text: String, enabled: bool = true, detail: String = "") -> void:
	if i < 0 or i >= items.size():
		return
	items[i] = {"text": text, "enabled": enabled, "detail": detail}
	redraw()


func is_enabled(i: int) -> bool:
	return i >= 0 and i < items.size() and bool(items[i].get("enabled", true))


## Handles one input event. Moves the cursor on up/down and returns &"" then; returns &"confirm",
## &"cancel", &"left" or &"right" for the owner to act on, or &"" if the event was not for menus.
## Marks every menu event as handled.
func handle(event: InputEvent) -> StringName:
	var answer := &""
	if _pressed(event, &"menu_up"):
		_move(-1)
	elif _pressed(event, &"menu_down"):
		_move(1)
	elif _pressed(event, &"menu_confirm"):
		answer = &"confirm"
	elif _pressed(event, &"menu_cancel"):
		answer = &"cancel"
	elif _pressed(event, &"menu_left"):
		answer = &"left"
	elif _pressed(event, &"menu_right"):
		answer = &"right"
	else:
		return &""
	if is_inside_tree():
		get_viewport().set_input_as_handled()
	return answer


func redraw() -> void:
	for i: int in _labels.size():
		var selected := i == index
		var enabled := is_enabled(i)
		_labels[i].text = (CURSOR if selected else "  ") + String(items[i].get("text", ""))
		var color := HudStyle.GOLD if selected else HudStyle.TEXT
		if not enabled:
			color = HudStyle.TEXT_DIM
		_labels[i].label_settings.font_color = color
	if _detail != null:
		_detail.text = String(items[index].get("detail", "")) if index < items.size() else ""


func _move(step: int) -> void:
	if items.is_empty():
		return
	index = wrapi(index + step, 0, items.size())
	Sfx.play("menu_move")
	redraw()


func _pressed(event: InputEvent, action: StringName) -> bool:
	if not event.is_action_pressed(action, false, true):
		return false
	if event is InputEventJoypadMotion:
		var frame := Engine.get_process_frames()
		if not Input.is_action_just_pressed(action) or frame == _stick_frame:
			return false
		_stick_frame = frame
	return true


## A full-screen dark background and a centred column with a title, for a menu screen.
## Returns the column; the background and column are added to `parent`.
static func screen_column(parent: Node, title: String, title_size: int = 64) -> VBoxContainer:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.04, 0.06)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(bg)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 18)
	parent.add_child(column)
	if not title.is_empty():
		var label := HudStyle.make_label(title, title_size, HudStyle.GOLD)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(label)
	return column


## A centred label for a screen column.
static func centred_label(text: String, size: int, color: Color = HudStyle.TEXT) -> Label:
	var label := HudStyle.make_label(text, size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label
