class_name HintBar
extends HBoxContainer
## A row of button hints: a button chip and what it does, for each entry [action, text] (action:
## an Input Map action or a HudStyle.NAV_TOKENS token). The chips follow ButtonPrompts (keyboard
## keys or pad buttons) and redraw when that changes (card #45).

const ENTRY_GAP: int = 28
const CHIP_GAP: int = 8
const OR_TEXT := "/"

var _entries: Array = []
var _font_size: int = 24
var _color: Color = HudStyle.TEXT_DIM


func _init(entries: Array = [], font_size: int = 24, color: Color = HudStyle.TEXT_DIM) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", ENTRY_GAP)
	_font_size = font_size
	_color = color
	set_entries(entries)


func _ready() -> void:
	ButtonPrompts.listen(_rebuild)


## Replaces the hints ([[action, text], ...]).
func set_entries(entries: Array) -> void:
	_entries = entries.duplicate()
	_rebuild()


func _rebuild() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	for entry: Array in _entries:
		add_child(HintBar.entry_row(StringName(entry[0]), String(entry[1]), _font_size, _color))


## Hints stacked one per line, chips on the left ([[action, text], ...]), then plain `notes`
## lines; for the corner of the fight and zone screens.
static func stack(entries: Array, font_size: int, notes: Array = [], color: Color = HudStyle.TEXT) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	for entry: Array in entries:
		var bar := HintBar.new([entry], font_size, color)
		bar.alignment = BoxContainer.ALIGNMENT_BEGIN
		box.add_child(bar)
	for note: String in notes:
		box.add_child(HudStyle.make_label(note, font_size, HudStyle.TEXT_DIM.lightened(0.2)))
	return box


## One hint: the action's button chip(s) and the text after them.
static func entry_row(action: StringName, text: String, font_size: int, color: Color = HudStyle.TEXT_DIM) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", CHIP_GAP)
	var parts := HudStyle.binding_parts(action)
	var chips := 0
	for pad: bool in [false, true]:
		var shown := ButtonPrompts.shows_pad() if pad else ButtonPrompts.shows_keys()
		var button := parts[1] if pad else parts[0]
		if not shown or button.is_empty():
			continue
		if chips > 0:
			row.add_child(HudStyle.make_label(OR_TEXT, font_size, color))
		var chip := HudStyle.button_chip(button, pad, font_size)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(chip)
		chips += 1
	if chips == 0:
		# The kind shown has no binding for this action: fall back to the text.
		row.add_child(HudStyle.button_chip(HudStyle.binding_text(action), false, font_size))
	if not text.is_empty():
		var label := HudStyle.make_label(text, font_size, color)
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(label)
	return row
