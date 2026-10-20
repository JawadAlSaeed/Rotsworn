class_name PauseMenu
extends CanvasLayer
## The pause menu (DESIGN.md 7.5): over a fight, a zone or the run map. Continue, Settings, Glossary (7.12), Save &
## Quit (a local run, DESIGN.md 8.14) and Abandon run (in a run) or Leave (practice). Pause (Esc /
## Menu) or Back also continues. Main stops whatever is under it while it is open.
## Phase 22: each row is a small drawn picture and its word, with no sentence under it (what a row
## does is plain from the word; a leave that loses the run still asks first).

signal resumed
signal settings_requested
## The Glossary row: Main opens the book over this menu and comes back to it.
signal glossary_requested
signal leave_requested
## Save & Quit: keep the run in its slot and go to the main menu.
signal save_quit_requested
## The extra item (the tutorial's "Skip this lesson").
signal extra_requested

const TITLE_SIZE: int = 72
const DIM := Color(0.0, 0.0, 0.0, 0.7)
## The picture before each row's word (pixels on the 1920x1080 canvas, before the text size).
const GLYPH_PX: int = 34

enum Item { CONTINUE, SETTINGS, LEAVE, EXTRA, SAVE_QUIT, GLOSSARY }
## The picture of each kind of row (RowGlyph kinds).
const ITEM_GLYPHS := {
	Item.CONTINUE: &"play", Item.SETTINGS: &"gear", Item.GLOSSARY: &"book", Item.SAVE_QUIT: &"save",
	Item.LEAVE: &"door", Item.EXTRA: &"skip",
}

var _menu: ListMenu
## What each row is (Item), in order.
var _rows: Array[int] = []
## Each row's picture, in row order.
var _glyphs: Array[RowGlyph] = []


## `leave_text`: "Abandon run" or "Leave". `extra_text`: one more row after Continue (empty: none).
## `save_text` (empty: none) is the Save & Quit row, just before the leave row. The `*_detail`
## arguments are kept for the callers but no longer shown (phase 22: no sentence under the rows).
func setup(leave_text: String, _leave_detail: String = "", extra_text: String = "", _extra_detail: String = "",
		save_text: String = "", _save_detail: String = "") -> void:
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
	var items: Array[Dictionary] = [{"text": "Continue"}]
	_rows = [Item.CONTINUE]
	if not extra_text.is_empty():
		items.append({"text": extra_text})
		_rows.append(Item.EXTRA)
	items.append({"text": "Settings"})
	_rows.append(Item.SETTINGS)
	items.append({"text": "Glossary"})
	_rows.append(Item.GLOSSARY)
	if not save_text.is_empty():
		items.append({"text": save_text})
		_rows.append(Item.SAVE_QUIT)
	items.append({"text": leave_text})
	_rows.append(Item.LEAVE)
	_menu.set_items(items)
	_add_glyphs()
	ListMenu.screen_footer(self, [[&"@updown", "Choose"], [&"menu_confirm", "Select"], [&"pause", "Continue"]])


## The kind of picture on row `i` (for tests).
func glyph_kind(i: int) -> StringName:
	return _glyphs[i].kind if i >= 0 and i < _glyphs.size() else &""


## Puts a picture before each row's word, and an empty box of the same width after it so the word
## stays centred (in ListMenu's own row line, ListMenu.row_box).
func _add_glyphs() -> void:
	_glyphs.clear()
	var px := float(HudStyle.scaled(GLYPH_PX))
	for i: int in _rows.size():
		var glyph := RowGlyph.new()
		glyph.kind = ITEM_GLYPHS[_rows[i]]
		glyph.custom_minimum_size = Vector2(px, px)
		glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_glyphs.append(glyph)
		var line := _menu.row_box(i)
		if line == null:
			continue
		line.add_child(glyph)
		line.move_child(glyph, 0)
		var balance := Control.new()
		balance.mouse_filter = Control.MOUSE_FILTER_IGNORE
		balance.custom_minimum_size = Vector2(px, px)
		line.add_child(balance)
	_paint_glyphs()


## The chosen row's picture in gold, the others dim (like the words).
func _paint_glyphs() -> void:
	for i: int in _glyphs.size():
		var colour := HudStyle.GOLD if i == _menu.index else HudStyle.TEXT_DIM
		if _glyphs[i].color != colour:
			_glyphs[i].color = colour
			_glyphs[i].queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause", false, true):
		get_viewport().set_input_as_handled()
		Sfx.play("menu_cancel")
		resumed.emit()
		return
	var answer := _menu.handle(event)
	_paint_glyphs()
	match answer:
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
				Item.GLOSSARY:
					glossary_requested.emit()
				Item.LEAVE:
					leave_requested.emit()
				Item.EXTRA:
					extra_requested.emit()
				Item.SAVE_QUIT:
					save_quit_requested.emit()


## A pause row's small picture, drawn from simple shapes in one colour: play (Continue), gear
## (Settings), book (Glossary), save (Save & Quit), door (Abandon / Leave) and skip (the tutorial's
## skip).
class RowGlyph:
	extends Control

	const HOLE := Color(0.03, 0.025, 0.04, 0.95)

	var kind: StringName = &"play"
	var color: Color = HudStyle.TEXT_DIM

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var h := minf(size.x, size.y) * 0.5
		match kind:
			&"play":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-h * 0.55, -h * 0.8), c + Vector2(h * 0.8, 0.0),
						c + Vector2(-h * 0.55, h * 0.8)]), color)
			&"skip":
				for dx: float in [-0.75, 0.05]:
					draw_colored_polygon(PackedVector2Array([c + Vector2(h * dx, -h * 0.7), c + Vector2(h * (dx + 0.7), 0.0),
							c + Vector2(h * dx, h * 0.7)]), color)
			&"gear":
				for i: int in 8:
					var a := TAU * float(i) / 8.0
					var along := Vector2(cos(a), sin(a))
					var across := Vector2(-along.y, along.x) * h * 0.17
					draw_colored_polygon(PackedVector2Array([c + along * h * 0.5 - across, c + along * h * 0.95 - across,
							c + along * h * 0.95 + across, c + along * h * 0.5 + across]), color)
				draw_circle(c, h * 0.68, color)
				draw_circle(c, h * 0.26, HOLE)
			&"book":
				for side: float in [-1.0, 1.0]:
					draw_colored_polygon(PackedVector2Array([c + Vector2(side * h * 0.08, -h * 0.55),
							c + Vector2(side * h * 0.92, -h * 0.75), c + Vector2(side * h * 0.92, h * 0.6),
							c + Vector2(side * h * 0.08, h * 0.8)]), color)
			&"save":
				# An arrow going down into a tray.
				draw_rect(Rect2(c + Vector2(-h * 0.16, -h * 0.9), Vector2(h * 0.32, h * 0.75)), color)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-h * 0.5, -h * 0.2), c + Vector2(h * 0.5, -h * 0.2),
						c + Vector2(0.0, h * 0.35)]), color)
				var w := h * 0.18
				draw_rect(Rect2(c + Vector2(-h * 0.9, h * 0.62), Vector2(h * 1.8, w)), color)
				draw_rect(Rect2(c + Vector2(-h * 0.9, h * 0.2), Vector2(w, h * 0.5)), color)
				draw_rect(Rect2(c + Vector2(h * 0.9 - w, h * 0.2), Vector2(w, h * 0.5)), color)
			&"door":
				draw_rect(Rect2(c + Vector2(-h * 0.55, -h * 0.92), Vector2(h * 1.1, h * 1.84)), color)
				draw_rect(Rect2(c + Vector2(-h * 0.38, -h * 0.74), Vector2(h * 0.76, h * 1.66)), HOLE)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-h * 0.38, -h * 0.74), c + Vector2(h * 0.2, -h * 0.56),
						c + Vector2(h * 0.2, h * 0.92), c + Vector2(-h * 0.38, h * 0.92)]), color)
				draw_circle(c + Vector2(h * 0.06, h * 0.12), h * 0.08, HOLE)
			_:
				draw_circle(c, h * 0.5, color)
