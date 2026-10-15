class_name TutorialOverlay
extends CanvasLayer
## What the tutorial shows (DESIGN.md 7.8). The card: centred over a dimmed screen while the game
## waits, "Lesson N of M: title" (or "Well done!" / "Try again"), the explanation with button
## pictures in the line, a dimmer tip, and "Enter: go". The reminder: one line at the bottom
## centre, above the hero bars, while the player tries (never over the enemy, its intent sign or
## the attack banner).

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

var _dim: ColorRect
var _card: PanelContainer
var _head: Label
var _sub: Label
## The card's text: rows of words and button pictures, wrapped by measuring each piece (a flow
## container sizes itself as if every word were on its own line and left the card screen-tall).
var _lines: VBoxContainer
var _tip: Label
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
	_lines = VBoxContainer.new()
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines.add_theme_constant_override("separation", 6)
	box.add_child(_lines)
	_tip = HudStyle.make_label("", TIP_SIZE, HudStyle.TEXT_DIM)
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.custom_minimum_size.x = CARD_WIDTH - 60.0
	box.add_child(_tip)
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
## 6"); `heading` in gold, or green when `good`; `text` with {action} button pictures.
func show_card(sub: String, heading: String, text: String, tip: String, go_text: String = "Go",
		good: bool = false) -> void:
	_sub.text = sub
	_sub.visible = not sub.is_empty()
	_head.text = heading
	_head.label_settings.font_color = HudStyle.HEAL if good else HudStyle.GOLD
	_fill(_lines, text, TEXT_SIZE, CARD_WIDTH - 2.0 * CARD_PAD)
	_tip.text = tip
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


## The words of `text` as labels and each {action} as its button picture. With a `width`, they
## wrap into rows of `box` (a VBoxContainer); with 0, they all go in `box` (one row).
func _fill(box: Container, text: String, size: int, width: float) -> void:
	for child: Node in box.get_children():
		box.remove_child(child)
		child.queue_free()
	var row: Container = box
	var used := 0.0
	for word: String in text.split(" ", false):
		var pieces := _pieces(word, size)
		var piece_width := 0.0
		for piece: Control in pieces:
			piece_width += piece.get_combined_minimum_size().x
		if width > 0.0 and (row == box or used + piece_width > width):
			row = HBoxContainer.new()
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_theme_constant_override("separation", int(WORD_GAP))
			box.add_child(row)
			used = 0.0
		for piece: Control in pieces:
			row.add_child(piece)
		used += piece_width + WORD_GAP


## One word as controls: plain text, or a {action} button picture with any text stuck to it
## ("{fight_attack}." keeps its full stop).
func _pieces(word: String, size: int) -> Array[Control]:
	var list: Array[Control] = []
	var at := word.find("{")
	var close := word.find("}")
	if at < 0 or close < at:
		list.append(HudStyle.make_label(word, size))
		return list
	if at > 0:
		list.append(HudStyle.make_label(word.substr(0, at), size))
	var chip := HintBar.new([[StringName(word.substr(at + 1, close - at - 1)), ""]], size, HudStyle.TEXT)
	chip.alignment = BoxContainer.ALIGNMENT_BEGIN
	list.append(chip)
	if close + 1 < word.length():
		list.append(HudStyle.make_label(word.substr(close + 1), size))
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
