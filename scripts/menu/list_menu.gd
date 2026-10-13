class_name ListMenu
extends VBoxContainer
## A vertical list of choices for the menus outside a fight (main menu, settings, shop, rest).
## Driven only by the menu_* input actions, like the fight list: the screen that owns it passes
## each input event to handle(), which moves the cursor itself and reports the rest.
## Each item is a row: its text, and an optional value on the right (a price, a setting); the
## chosen row is lit with a gold bar (card #37).

const ITEM_SIZE: int = 40
const DETAIL_SIZE: int = 26
## Width of the rows in a centred menu, and in a left-aligned one (pixels).
const CENTRED_ROW_WIDTH: float = 560.0
const LEFT_ROW_WIDTH: float = 720.0
const ROW_PAD_X: int = 22
const ROW_PAD_Y: int = 4
const ACCENT_PX: int = 5
const SELECTED_BG := Color(1.0, 0.78, 0.3, 0.16)
## The chosen row lights up for a moment when the cursor lands on it.
const SELECTED_FLASH := Color(1.5, 1.4, 1.2)
const SELECTED_FLASH_S: float = 0.16
const TITLE_DIVIDER_WIDTH: float = 620.0
const TITLE_DIVIDER_PX: float = 3.0
const FOOTER_SIZE: int = 26
const FOOTER_STRIP := Color(0.0, 0.0, 0.0, 0.45)
const FOOTER_STRIP_PX: float = 76.0

## Every item: {text: String, enabled: bool, detail: String, value: String}.
var items: Array[Dictionary] = []
var index: int = 0
var item_size: int = ITEM_SIZE
## Centre the items (main menu) or line them up on the left (shop, settings).
var centred: bool = true
## Row width in pixels (0: CENTRED_ROW_WIDTH or LEFT_ROW_WIDTH).
var row_width: float = 0.0
var _rows: Array[PanelContainer] = []
var _labels: Array[Label] = []
var _values: Array[Label] = []
var _detail: Label
var _shown_index: int = -1
## Process frame of the last stick move (a held stick sends many motion events).
var _stick_frame: int = -1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_theme_constant_override("separation", 6)


## Replaces the items (keeps the cursor where it was if it still fits).
func set_items(new_items: Array[Dictionary], detail_label: Label = null) -> void:
	items = new_items
	if detail_label != null:
		_detail = detail_label
	for row: PanelContainer in _rows:
		row.queue_free()
	_rows.clear()
	_labels.clear()
	_values.clear()
	custom_minimum_size.x = row_width if row_width > 0.0 else (CENTRED_ROW_WIDTH if centred else LEFT_ROW_WIDTH)
	for i: int in items.size():
		var row := PanelContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_stylebox_override("panel", row_style(false))
		var line := HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_theme_constant_override("separation", 24)
		row.add_child(line)
		var label := HudStyle.make_label("", item_size)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centred else HORIZONTAL_ALIGNMENT_LEFT
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(label)
		var value := HudStyle.make_label("", item_size)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(value)
		add_child(row)
		_rows.append(row)
		_labels.append(label)
		_values.append(value)
	index = clampi(index, 0, maxi(0, items.size() - 1))
	_shown_index = -1
	redraw()


func set_item(i: int, text: String, enabled: bool = true, detail: String = "", value: String = "") -> void:
	if i < 0 or i >= items.size():
		return
	items[i] = {"text": text, "enabled": enabled, "detail": detail, "value": value}
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
		_labels[i].text = String(items[i].get("text", ""))
		var value := String(items[i].get("value", ""))
		_values[i].text = value
		_values[i].visible = not value.is_empty()
		var color := HudStyle.GOLD if selected else HudStyle.TEXT
		if not enabled:
			color = HudStyle.TEXT_DIM.lightened(0.15) if selected else HudStyle.TEXT_DIM
		_labels[i].label_settings.font_color = color
		_values[i].label_settings.font_color = color
		_rows[i].add_theme_stylebox_override("panel", row_style(selected))
	if index != _shown_index and index < _rows.size():
		_shown_index = index
		var row := _rows[index]
		row.modulate = SELECTED_FLASH
		row.create_tween().tween_property(row, "modulate", Color.WHITE, SELECTED_FLASH_S)
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


## The chosen row: a soft gold bar with a bright edge on the left. Other rows keep the same
## margins with no bar, so the text never jumps. `pad_x`: the side padding.
static func row_style(selected: bool, pad_x: int = ROW_PAD_X) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = SELECTED_BG if selected else Color(0, 0, 0, 0)
	box.border_color = HudStyle.GOLD if selected else Color(0, 0, 0, 0)
	box.border_width_left = ACCENT_PX
	box.set_corner_radius_all(4)
	box.content_margin_left = pad_x + ACCENT_PX
	box.content_margin_right = pad_x
	box.content_margin_top = ROW_PAD_Y
	box.content_margin_bottom = ROW_PAD_Y
	return box


## The menu background (MenuBackdrop) and a centred column with a title and a thin gold line
## under it, for a menu screen. Returns the column; the background and column are added to
## `parent`. The title is the column's first child.
static func screen_column(parent: Node, title: String, title_size: int = 64) -> VBoxContainer:
	parent.add_child(MenuBackdrop.new())
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_bottom = -FOOTER_STRIP_PX
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 18)
	parent.add_child(column)
	if not title.is_empty():
		var label := HudStyle.make_title(title, title_size, HudStyle.GOLD)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.label_settings.shadow_color = Color(0.0, 0.0, 0.0, 0.6)
		label.label_settings.shadow_offset = Vector2(0.0, maxf(3.0, float(title_size) * 0.06))
		column.add_child(label)
		column.add_child(divider())
	return column


## A thin gold line that fades out at both ends.
static func divider(width: float = TITLE_DIVIDER_WIDTH) -> TextureRect:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(HudStyle.GOLD, 0.0))
	gradient.set_color(1, Color(HudStyle.GOLD, 0.0))
	gradient.add_point(0.5, Color(HudStyle.GOLD, 0.85))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 256
	texture.height = 1
	var line := TextureRect.new()
	line.texture = texture
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	line.stretch_mode = TextureRect.STRETCH_SCALE
	line.custom_minimum_size = Vector2(width, TITLE_DIVIDER_PX)
	line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return line


## Button hints along the bottom of a screen, on a dark strip ([[action, text], ...], see
## HintBar). Returns the bar (set_entries() changes it later).
static func screen_footer(parent: Node, entries: Array) -> HintBar:
	var strip := ColorRect.new()
	strip.color = FOOTER_STRIP
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	strip.offset_top = -FOOTER_STRIP_PX
	parent.add_child(strip)
	var bar := HintBar.new(entries, FOOTER_SIZE)
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -FOOTER_STRIP_PX
	strip.add_sibling(bar)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	return bar


## A centred title-font label for a screen column (titles outside screen_column).
static func centred_title(text: String, size: int, color: Color = HudStyle.GOLD) -> Label:
	var label := HudStyle.make_title(text, size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


## A centred label for a screen column.
static func centred_label(text: String, size: int, color: Color = HudStyle.TEXT) -> Label:
	var label := HudStyle.make_label(text, size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label
