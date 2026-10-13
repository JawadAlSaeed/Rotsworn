class_name ButtonChip
extends Control
## One button picture for the hints (card #45), drawn with shapes rather than art files, all in
## one light colour on a dark see-through fill, outline style (user pick 2026-10-13):
## - pad face buttons A, B, X, Y: a ring with its letter;
## - Menu and View: a ring with the Xbox symbol (three lines, two windows);
## - the D-pad: an outlined cross with arrows on the arms the hint means (up and down...);
## - sticks (L-stick, LS, R-stick, RS): a ring with an inner ring and its letter;
## - other pad buttons (LB, RB...): an outlined pill with the name;
## - keyboard keys: an outlined rounded key with the key's name.
## Text is centred on its ink (the drawn pixels of the letters), not on the font's line box, so a
## letter sits in the middle of its button at every size.

enum Shape { KEY, FACE, PILL, MENU, VIEW, DPAD, STICK }

## Chip shape, as shares of the chip's height (the hint's font size times
## HudStyle.CHIP_HEIGHT_SHARE).
const PILL_SIDE_SHARE: float = 0.3
const KEY_SIDE_SHARE: float = 0.3
## The pad's face buttons (a ring with a letter).
const FACE_BUTTONS: Array[String] = ["A", "B", "X", "Y"]
## Outline width, as a share of the chip's height (at least OUTLINE_MIN_PX).
const OUTLINE_SHARE: float = 0.065
const OUTLINE_MIN_PX: float = 1.5
## Every chip's outline, letters and symbols, and its fill.
const LINE := Color(0.9, 0.9, 0.9)
const FILL := Color(0.06, 0.06, 0.08, 0.7)
const KEY_CORNER_SHARE: float = 0.22
const MENU_LINE_WIDTH_SHARE: float = 0.46
const MENU_LINE_THICK_SHARE: float = 0.075
const MENU_LINE_GAP_SHARE: float = 0.15
const VIEW_RECT_SHARE: float = 0.3
const VIEW_RECT_OFFSET_SHARE: float = 0.08
const VIEW_LINE_SHARE: float = 0.06
const DPAD_SCALE: float = 1.2
const DPAD_ARM_SHARE: float = 0.36
const DPAD_ARROW_SHARE: float = 0.16
const STICK_INNER_SHARE: float = 0.36
const STICK_TEXT_SHARE: float = 0.62
## A capital letter: text is centred up and down on its height.
const CAP_SAMPLE := "H"
## Arrows on the D-pad arms the hint does not mean: faint, so the lit ones stand out.
const DPAD_ARROW_DIM := Color(0.9, 0.9, 0.9, 0.25)

var text: String = ""
var shape: Shape = Shape.KEY
## D-pad arms with an arrow (Vector2i.UP, DOWN, LEFT, RIGHT).
var directions: Array[Vector2i] = []
var _font_size: int = 24
var _text_size: int = 19
var _height: float = 30.0
var _bg: Color = FILL
var _fg: Color = LINE
var _line: TextLine
var _font: Font


## `button` is a key or pad button name (HudStyle.binding_parts); `pad` says which kind.
func _init(button: String, pad: bool, font_size: int) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	text = button
	_font_size = font_size
	_height = roundf(float(font_size) * HudStyle.CHIP_HEIGHT_SHARE)
	_text_size = maxi(1, roundi(float(font_size) * HudStyle.CHIP_TEXT_SHARE))
	shape = ButtonChip.shape_of(button, pad)
	if shape == Shape.DPAD:
		# The cross has thin arms: a little bigger than the other buttons so its arrows read.
		_height = roundf(_height * DPAD_SCALE)
	if shape == Shape.DPAD:
		directions = ButtonChip.dpad_directions(button)
	if shape == Shape.STICK:
		text = "R" if button.begins_with("R") else "L"
		_text_size = maxi(1, roundi(_height * STICK_TEXT_SHARE * HudStyle.CHIP_TEXT_SHARE))
	_font = HudStyle.body_font()
	_line = TextLine.new()
	if shape in [Shape.KEY, Shape.FACE, Shape.PILL, Shape.STICK]:
		_line.add_string(text, _font, _text_size)
	custom_minimum_size = Vector2(_width(), _height)


## Which picture a button name gets.
static func shape_of(button: String, pad: bool) -> Shape:
	if not pad:
		return Shape.KEY
	if button in FACE_BUTTONS:
		return Shape.FACE
	if button == "Menu":
		return Shape.MENU
	if button == "View":
		return Shape.VIEW
	if button.begins_with("D-pad"):
		return Shape.DPAD
	if button in ["LS", "RS", "L-stick", "R-stick"]:
		return Shape.STICK
	return Shape.PILL


## The D-pad arms a name points at: "D-pad up", "D-pad ↑↓", "D-pad ←→"... (all four if none).
static func dpad_directions(button: String) -> Array[Vector2i]:
	var dirs: Array[Vector2i] = []
	var lower := button.to_lower()
	if lower.contains("up") or button.contains("↑"):
		dirs.append(Vector2i.UP)
	if lower.contains("down") or button.contains("↓"):
		dirs.append(Vector2i.DOWN)
	if lower.contains("left") or button.contains("←"):
		dirs.append(Vector2i.LEFT)
	if lower.contains("right") or button.contains("→"):
		dirs.append(Vector2i.RIGHT)
	if dirs.is_empty():
		dirs.assign([Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT])
	return dirs


## The text's colour (for tools that check the picture).
func text_color() -> Color:
	return _fg


func _width() -> float:
	match shape:
		Shape.KEY:
			return maxf(_height, _line.get_size().x + 2.0 * _height * KEY_SIDE_SHARE)
		Shape.PILL:
			return maxf(_height, _line.get_size().x + 2.0 * _height * PILL_SIDE_SHARE)
	return _height


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var h := _height
	var centre := Vector2(rect.size.x * 0.5, rect.size.y * 0.5)
	var line := maxf(OUTLINE_MIN_PX, h * OUTLINE_SHARE)
	match shape:
		Shape.KEY, Shape.PILL:
			var box := StyleBoxFlat.new()
			box.bg_color = _bg
			box.border_color = _fg
			box.set_border_width_all(roundi(line))
			box.set_corner_radius_all(roundi(h * (0.5 if shape == Shape.PILL else KEY_CORNER_SHARE)))
			box.anti_aliasing = true
			draw_style_box(box, Rect2(0.0, (rect.size.y - h) * 0.5, rect.size.x, h))
			_draw_text_centred(centre)
		Shape.FACE:
			_draw_round(centre, h * 0.5, line)
			_draw_text_centred(centre)
		Shape.MENU:
			_draw_round(centre, h * 0.5, line)
			var half := h * MENU_LINE_WIDTH_SHARE * 0.5
			var thick := maxf(1.5, h * MENU_LINE_THICK_SHARE)
			for i: int in [-1, 0, 1]:
				var y := centre.y + float(i) * h * MENU_LINE_GAP_SHARE
				draw_line(Vector2(centre.x - half, y), Vector2(centre.x + half, y), _fg, thick, true)
		Shape.VIEW:
			_draw_round(centre, h * 0.5, line)
			var side := h * VIEW_RECT_SHARE
			var shift := h * VIEW_RECT_OFFSET_SHARE
			var thin := maxf(1.2, h * VIEW_LINE_SHARE)
			var back := Rect2(centre - Vector2(side, side) * 0.5 - Vector2(shift, shift), Vector2(side, side))
			var front := Rect2(centre - Vector2(side, side) * 0.5 + Vector2(shift, shift), Vector2(side, side))
			draw_rect(back, _fg, false, thin, true)
			# The front window hides the back one's corner (filled with the button's own colour).
			draw_rect(front, Color(_bg, 1.0), true)
			draw_rect(front, _fg, false, thin, true)
		Shape.DPAD:
			_draw_dpad(centre, h, line)
		Shape.STICK:
			_draw_round(centre, h * 0.5, line)
			draw_arc(centre, h * STICK_INNER_SHARE, 0.0, TAU, 32, Color(_fg, 0.5), maxf(1.2, line * 0.7), true)
			_draw_text_centred(centre)


## A round button: the see-through fill and a ring.
func _draw_round(centre: Vector2, radius: float, line: float) -> void:
	draw_circle(centre, radius, _bg, true, -1.0, true)
	draw_arc(centre, radius - line * 0.5, 0.0, TAU, 48, _fg, line, true)


## An outlined D-pad cross with a small arrow on each arm in `directions` (the others faint).
func _draw_dpad(centre: Vector2, h: float, line: float) -> void:
	var a := h * DPAD_ARM_SHARE * 0.5
	var r := h * 0.5 - line * 0.5
	var cross := PackedVector2Array([
		Vector2(-a, -r), Vector2(a, -r), Vector2(a, -a), Vector2(r, -a), Vector2(r, a), Vector2(a, a),
		Vector2(a, r), Vector2(-a, r), Vector2(-a, a), Vector2(-r, a), Vector2(-r, -a), Vector2(-a, -a),
	])
	for i: int in cross.size():
		cross[i] += centre
	draw_colored_polygon(cross, _bg)
	var outline := cross.duplicate()
	outline.append(cross[0])
	draw_polyline(outline, _fg, line, true)
	var tip := h * DPAD_ARROW_SHARE
	for dir: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var d := Vector2(dir)
		var side := Vector2(-d.y, d.x)
		var point := centre + d * (r - line - tip * 0.45)
		var base := point - d * tip
		var arrow := PackedVector2Array([point, base + side * tip * 0.75, base - side * tip * 0.75])
		draw_colored_polygon(arrow, _fg if directions.has(dir) else DPAD_ARROW_DIM)


## Draws the text so the middle of its ink (not its line box) is at `centre` across, and the
## middle of a capital letter's height is at `centre` up and down, so tails (p, Q, J) hang below
## and every key of a size shares one baseline.
func _draw_text_centred(centre: Vector2) -> void:
	var ink := ButtonChip.ink_rect(_line)
	var ascent := _line.get_line_ascent()
	if ink.size == Vector2.ZERO:
		ink = Rect2(0.0, -ascent, _line.get_size().x, _line.get_size().y)
	var caps := TextLine.new()
	caps.add_string(CAP_SAMPLE, _font, _text_size)
	var cap := ButtonChip.ink_rect(caps)
	var middle_y := cap.get_center().y if cap.size != Vector2.ZERO else ink.get_center().y
	var origin := centre - Vector2(ink.get_center().x, middle_y)
	# TextLine.draw takes the top-left of the line box; the ink is relative to the baseline.
	_line.draw(get_canvas_item(), Vector2(roundf(origin.x), roundf(origin.y - ascent)), _fg)


## The rectangle the glyphs of `line` actually cover, relative to the start of its baseline.
## Uses each glyph's cached bitmap rectangle (its padding is the same on every side, so the
## middle is the ink's middle).
static func ink_rect(line: TextLine) -> Rect2:
	var ts := TextServerManager.get_primary_interface()
	var glyphs: Array[Dictionary] = ts.shaped_text_get_glyphs(line.get_rid())
	var x := 0.0
	var found := false
	var box := Rect2()
	for glyph: Dictionary in glyphs:
		var font_rid: RID = glyph.get("font_rid", RID())
		var index := int(glyph.get("index", 0))
		var advance := float(glyph.get("advance", 0.0))
		var offset: Vector2 = glyph.get("offset", Vector2.ZERO)
		if font_rid.is_valid():
			var font_size := Vector2i(int(glyph.get("font_size", 16)), 0)
			var size := ts.font_get_glyph_size(font_rid, font_size, index)
			if size.x > 0.0 and size.y > 0.0:
				var at := Vector2(x, 0.0) + offset + ts.font_get_glyph_offset(font_rid, font_size, index)
				var r := Rect2(at, size)
				box = r if not found else box.merge(r)
				found = true
		x += advance
	return box if found else Rect2()
