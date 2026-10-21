class_name TutorialOverlay
extends CanvasLayer
## What the tutorial shows (DESIGN.md 7.8). The card: centred over a dimmed screen while the game
## waits, "Lesson N of M: title" (or "Well done!" / "Try again"), the lesson's picture on a plate
## beside a short line with button pictures in it (card #293), a dimmer tip, and "Enter: go". The
## reminder: one line at the bottom centre, above the hero bars, while the player tries (never over
## the enemy, its intent sign or the attack banner).

const CARD_WIDTH: float = 1100.0
const HEAD_SIZE: int = 40
const TEXT_SIZE: int = 32
const TIP_SIZE: int = 26
const REMINDER_SIZE: int = 28
## The reminder's bottom edge, above the hero bars (pixels from the bottom of the screen).
const REMINDER_BOTTOM: float = 180.0
const DIM := Color(0.0, 0.0, 0.0, 0.62)
## The card's inner padding (each side).
const CARD_PAD: float = 28.0
const WORD_GAP: float = 9.0
## The lesson picture's side: a whole multiple of the 12 and 24 pixel icons (10x and 5x), so the
## pixel art stays crisp.
const PICTURE_PX: float = 120.0
## The picture plate's padding and the gap between the plate and the words.
const PLATE_PAD: int = 10
const PICTURE_GAP: float = 28.0
const PLATE_BG := Color(0.1, 0.09, 0.13, 1.0)

var _dim: ColorRect
var _card: PanelContainer
var _head: Label
var _sub: Label
## The card's text: rows of words and button pictures, wrapped by measuring each piece (a flow
## container sizes itself as if every word were on its own line and left the card screen-tall).
var _lines: VBoxContainer
## The dimmer tip under it, wrapped the same way (a tip may show a button picture too).
var _tip: VBoxContainer
## The lesson's picture on its plate, left of the words (hidden on a card without one).
var _plate: PanelContainer
var _picture: TextureRect
var _go: HintBar
var _reminder: PanelContainer
## The reminder is one line (a row, not a wrapping flow: it has no width of its own to wrap in).
var _reminder_row: HBoxContainer


func _init() -> void:
	layer = 45
	_dim = ColorRect.new()
	_dim.color = DIM
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)
	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.custom_minimum_size.x = CARD_WIDTH
	_card.add_theme_stylebox_override("panel", HudStyle.panel(Color(0.05, 0.05, 0.07, 0.97), HudStyle.GOLD, 3, int(CARD_PAD)))
	add_child(_card)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 16)
	_card.add_child(box)
	_sub = HudStyle.make_label("", TIP_SIZE, HudStyle.TEXT_DIM)
	box.add_child(_sub)
	_head = HudStyle.make_title("", HEAD_SIZE, HudStyle.GOLD)
	box.add_child(_head)
	box.add_child(ListMenu.divider(CARD_WIDTH - 60.0))
	var body := HBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", int(PICTURE_GAP))
	box.add_child(body)
	_plate = PanelContainer.new()
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_plate.add_theme_stylebox_override("panel", HudStyle.panel(PLATE_BG, HudStyle.PANEL_BORDER, 2, PLATE_PAD))
	body.add_child(_plate)
	_picture = HudStyle.icon(null, PICTURE_PX)
	_plate.add_child(_picture)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	column.add_theme_constant_override("separation", 12)
	body.add_child(column)
	_lines = VBoxContainer.new()
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines.add_theme_constant_override("separation", 6)
	column.add_child(_lines)
	_tip = VBoxContainer.new()
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.add_theme_constant_override("separation", 4)
	column.add_child(_tip)
	_go = HintBar.new([[&"menu_confirm", "Go"]], TEXT_SIZE, HudStyle.GOLD)
	_go.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(_go)
	_reminder = PanelContainer.new()
	_reminder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reminder.add_theme_stylebox_override("panel", HudStyle.panel(Color(0.04, 0.04, 0.06, 0.85), HudStyle.PANEL_BORDER, 2, 12))
	add_child(_reminder)
	_reminder_row = HBoxContainer.new()
	_reminder_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reminder_row.add_theme_constant_override("separation", 9)
	_reminder.add_child(_reminder_row)
	hide_all()


## The card over a dimmed, waiting game. `sub`: the small line above the heading ("Lesson 2 of
## 6"); `heading` in gold, or green when `good`; `text` with {action} button pictures; `icon_path`:
## the lesson's picture beside the words (empty: none, the words take the whole card).
func show_card(sub: String, heading: String, text: String, tip: String, go_text: String = "Go",
		good: bool = false, icon_path: String = "") -> void:
	_sub.text = sub
	_sub.visible = not sub.is_empty()
	_head.text = heading
	_head.label_settings.font_color = HudStyle.HEAL if good else HudStyle.GOLD
	_plate.visible = not icon_path.is_empty()
	# A missing file shows the placeholder and warns (AssetLoader), never a crash.
	_picture.texture = AssetLoader.texture(icon_path) if _plate.visible else null
	var width := text_width(_plate.visible)
	_fill(_lines, text, TEXT_SIZE, width)
	_fill(_tip, tip, TIP_SIZE, width, HudStyle.TEXT_DIM)
	_tip.visible = not tip.is_empty()
	_go.set_entries([[&"menu_confirm", go_text]])
	_dim.visible = true
	_card.visible = true
	_reminder.visible = false
	_place_card.call_deferred()


## The one-line reminder at the bottom while the player tries (empty: none).
func show_reminder(text: String) -> void:
	_dim.visible = false
	_card.visible = false
	_reminder.visible = not text.is_empty()
	if _reminder.visible:
		_fill(_reminder_row, text, REMINDER_SIZE, 0.0)
		_place_reminder.call_deferred()


func hide_all() -> void:
	_dim.visible = false
	_card.visible = false
	_reminder.visible = false


func is_card_open() -> bool:
	return _card.visible


## How wide the card's words may run: the card less its padding, and less the picture plate and
## its gap when the card has a picture.
static func text_width(with_picture: bool) -> float:
	var width := CARD_WIDTH - 2.0 * CARD_PAD
	if with_picture:
		width -= PICTURE_PX + 2.0 * float(PLATE_PAD) + PICTURE_GAP
	return width


## The words of `text` as labels and each {action} as its button picture, in `color`. With a
## `width`, they wrap into rows of `box` (a VBoxContainer), as even as the row count allows (no
## lone word on a second row); with 0, they all go in `box` (one row).
func _fill(box: Container, text: String, size: int, width: float, color: Color = HudStyle.TEXT) -> void:
	for child: Node in box.get_children():
		box.remove_child(child)
		child.queue_free()
	var words: Array = []
	var widths := PackedFloat32Array()
	for word: String in text.split(" ", false):
		var pieces := _pieces(word, size, color)
		# The row's gap also sits between the pieces of one word ("{fight_attack}," is a chip and a
		# comma).
		var piece_width := WORD_GAP * float(pieces.size() - 1)
		for piece: Control in pieces:
			piece_width += piece.get_combined_minimum_size().x
		words.append(pieces)
		widths.append(piece_width)
	if width <= 0.0:
		for pieces: Array in words:
			for piece: Control in pieces:
				box.add_child(piece)
		return
	var starts := _row_starts(widths, _even_width(widths, width))
	var row: Container = null
	for i: int in words.size():
		if starts.has(i):
			row = HBoxContainer.new()
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_theme_constant_override("separation", int(WORD_GAP))
			box.add_child(row)
		for piece: Control in words[i]:
			row.add_child(piece)


## The narrowest row width (up to `width`) that still needs no more rows than `width` does, so
## two rows come out about even.
static func _even_width(widths: PackedFloat32Array, width: float) -> float:
	var rows := _row_starts(widths, width).size()
	if rows <= 1:
		return width
	var total := WORD_GAP * float(widths.size() - 1)
	for w: float in widths:
		total += w
	var even := minf(width, total / float(rows))
	while even < width and _row_starts(widths, even).size() > rows:
		even = minf(width, even + WORD_GAP)
	return even


## Where each row starts (word indices) when words of these widths fill rows of `width` in turn.
static func _row_starts(widths: PackedFloat32Array, width: float) -> PackedInt32Array:
	var starts := PackedInt32Array()
	var used := 0.0
	for i: int in widths.size():
		if starts.is_empty() or used + widths[i] > width:
			starts.append(i)
			used = 0.0
		used += widths[i] + WORD_GAP
	return starts


## One word as controls: plain text, or a {action} button picture with any text stuck to it
## ("{fight_attack}." keeps its full stop).
func _pieces(word: String, size: int, color: Color = HudStyle.TEXT) -> Array[Control]:
	var list: Array[Control] = []
	var at := word.find("{")
	var close := word.find("}")
	if at < 0 or close < at:
		list.append(HudStyle.make_label(word, size, color))
		return list
	if at > 0:
		list.append(HudStyle.make_label(word.substr(0, at), size, color))
	var chip := HintBar.new([[StringName(word.substr(at + 1, close - at - 1)), ""]], size, color)
	chip.alignment = BoxContainer.ALIGNMENT_BEGIN
	list.append(chip)
	if close + 1 < word.length():
		list.append(HudStyle.make_label(word.substr(close + 1), size, color))
	return list


func _place_card() -> void:
	if not _card.is_inside_tree():
		return
	_card.reset_size()
	var screen := _card.get_viewport_rect().size
	var size := _card.get_combined_minimum_size()
	_card.position = (screen - Vector2(maxf(size.x, CARD_WIDTH), size.y)) * 0.5


func _place_reminder() -> void:
	if not _reminder.is_inside_tree():
		return
	_reminder.reset_size()
	var screen := _reminder.get_viewport_rect().size
	var size := _reminder.get_combined_minimum_size()
	_reminder.position = Vector2((screen.x - size.x) * 0.5, screen.y - REMINDER_BOTTOM - size.y)
