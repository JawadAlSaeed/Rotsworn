class_name RelicIcon
extends Control
## A Relic's icon (DESIGN.md 8.17, card #271), drawn in code: like Expedition 33's Pictos, but the
## frame's shape says the category, so it reads without colour and at 26 px. Offensive Relics sit
## in a spearhead (pointed top, notched base) with a blade inside, defensive ones in a heater shield
## (flat top, rounded down to a point) with a shield boss, support ones in a round seal (a second
## ring inside) with a leaf. The frame is edged in the Relic's rarity colour (violet, and a rot
## drip, for a rot-touched one) and the sign inside has its category's colour, never a hero's; the
## Relic's own picture (GearData.icon_path) takes the sign's place when it has one. An unknown
## Relic is a dim neutral diamond with a "?".
## For the Y screen (DESIGN.md 8.18): level pips along the bottom (set_level), an empty slot
## (setup_slot: a dashed diamond with a plus, a locked one with a lock), a hero tag in a corner
## (set_tag: who has it) and the cursor's gold glow (chosen).
## Drawn grids paint the same icon on their own canvas with draw_relic, draw_slot and draw_tag.

## What a Relic slot shows (setup_slot). NONE: not a slot, a Relic (or its "?").
enum SlotState { NONE = -1, EMPTY, LOCKED }

## The frame_points() category of the neutral frame (unknown Relics and slots): a rounded diamond.
const NEUTRAL: int = -1

## Sign colours by category (ember offensive, steel defensive, moss support). Never a hero's colour
## (blue, red, gold), so a sign is not read as "this hero's".
const CATEGORY_COLORS: Array[Color] = [Color(1.0, 0.47, 0.16), Color(0.58, 0.7, 0.84), Color(0.48, 0.78, 0.38)]
const UNKNOWN_COLOR := Color(0.45, 0.45, 0.5)
## An open slot's dashed edge and plus; a locked slot's edge and its lock.
const SLOT_COLOR := Color(0.55, 0.55, 0.58)
const LOCKED_COLOR := Color(0.33, 0.32, 0.36)
const LOCKED_SIGN := Color(0.46, 0.45, 0.5)
const FILL := Color(0.03, 0.025, 0.04, 0.95)
## How much of its category colour tints a known Relic's dark fill.
const FILL_TINT: float = 0.08
const GLOW_COLOR := HudStyle.GOLD
const PIP_COLOR := HudStyle.GOLD
const PIP_EMPTY := Color(0.36, 0.34, 0.31)
const OUTLINE := Color(0.0, 0.0, 0.0, 0.85)
## A tag letter on a light hero colour.
const TAG_DARK := Color(0.05, 0.04, 0.06)

## The edge's width as a share of the icon's side, kept inside these pixel bounds.
const EDGE_SHARE: float = 0.055
const EDGE_MIN: float = 1.75
const EDGE_MAX: float = 4.0
## The inner line sits this share of the frame's radius in, and at least INNER_EDGES edge widths.
## Frames under INNER_MIN_RADIUS skip it (but the seal, whose second ring is part of its shape).
const INNER_GAP_SHARE: float = 0.22
const INNER_EDGES: float = 1.7
const INNER_MIN_RADIUS: float = 13.0
## The sign inside each frame by category: its centre (in frame radii from the frame's centre) and
## its size (in frame radii), so it sits in the frame's roomy middle.
const SIGN_OFFSETS: Array[Vector2] = [Vector2(0.0, -0.16), Vector2(0.0, -0.12), Vector2(0.0, 0.0)]
const SIGN_SIZES: Array[float] = [0.86, 0.9, 1.15]
## Level pips: their size as a share of the side (pixel bounds); the gap between them, and above
## the row, as a share of a pip.
const PIP_SHARE: float = 0.1
const PIP_MIN: float = 3.0
const PIP_MAX: float = 10.0
const PIP_GAP: float = 0.55
## The hero tag's radius as a share of the side, in pixel bounds.
const TAG_SHARE: float = 0.18
const TAG_MIN: float = 6.0
const TAG_MAX: float = 18.0
## The rot drip hangs from the frame's point furthest this way (low left, clear of the tag).
const DRIP_DIR := Vector2(-0.6, 0.8)

## The cursor is on it: a gold glow and a gold ring around the frame, and a thicker edge.
var chosen: bool = false:
	set(value):
		if chosen != value:
			chosen = value
			queue_redraw()

var _item: GearData
var _known: bool = true
var _texture: Texture2D
var _slot: int = SlotState.NONE
var _level: int = 0
var _max_level: int = 0
var _tag: String = ""
var _tag_color: Color = HudStyle.TEXT


## `px`: the icon's width and height. `known` false: a "?" for a Relic not found yet. `level` > 0
## shows that many gold pips along the bottom, out of `max_level` (0 shows only the filled ones;
## runs pass 0: Relics have no levels since DESIGN.md 8.24).
func setup(item: GearData, px: float, known: bool = true, level: int = 0, max_level: int = 0) -> void:
	_item = item
	_known = known and item != null
	_slot = SlotState.NONE
	_level = level
	_max_level = max_level
	_texture = _texture_for(item) if _known else null
	_size_to(px)


## A Relic slot on a hero row instead of a Relic: EMPTY (open, a dashed frame with a plus) or
## LOCKED (not open yet, a dim frame with a lock). A slot has no category: a neutral frame.
func setup_slot(state: int, px: float) -> void:
	_item = null
	_known = false
	_slot = state if state == SlotState.EMPTY or state == SlotState.LOCKED else SlotState.EMPTY
	_level = 0
	_max_level = 0
	_texture = null
	_size_to(px)


## The level pips: `level` filled out of `max_level` (0: only the filled ones). Level 0 hides them.
func set_level(level: int, max_level: int = 0) -> void:
	_level = level
	_max_level = max_level
	queue_redraw()


## A small round badge in the top right corner with the first letter of `letter` (a hero's
## initial or name) on `color` (the hero's colour): who wears it, in the shared bag. "" removes it.
func set_tag(letter: String, color: Color = HudStyle.TEXT) -> void:
	_tag = letter.strip_edges().substr(0, 1).to_upper()
	_tag_color = color
	queue_redraw()


## The filled level pips drawn now (0 for a slot or an unknown Relic).
func pip_count() -> int:
	return pip_layout(_level, _max_level).x if _shows_relic() else 0


## All level pips drawn now, filled and empty.
func pip_slots() -> int:
	return pip_layout(_level, _max_level).y if _shows_relic() else 0


## SlotState.EMPTY or LOCKED for a slot, NONE for a Relic.
func slot_state() -> int:
	return _slot


## The tag's letter, "" for none.
func tag() -> String:
	return _tag


## The frame drawn: the Relic's category, or NEUTRAL (unknown Relic, slot).
func shape() -> int:
	return _item.category() if _shows_relic() else NEUTRAL


## A new icon for `item` (see setup).
static func make(item: GearData, px: float, known: bool = true, level: int = 0, max_level: int = 0) -> RelicIcon:
	var icon := RelicIcon.new()
	icon.setup(item, px, known, level, max_level)
	return icon


## A new slot icon (see setup_slot).
static func make_slot(state: int, px: float) -> RelicIcon:
	var icon := RelicIcon.new()
	icon.setup_slot(state, px)
	return icon


## Filled and total pips (x, y) for a Relic at `level` of `max_level` (0: `level` filled, no
## empty ones). Level 0 or less: none.
static func pip_layout(level: int, max_level: int) -> Vector2i:
	if level <= 0:
		return Vector2i.ZERO
	if max_level <= 0:
		return Vector2i(level, level)
	return Vector2i(mini(level, max_level), max_level)


## A category's sign colour (GearData.Category); the unknown grey for anything else.
static func category_color(category: int) -> Color:
	if category < 0 or category >= CATEGORY_COLORS.size():
		return UNKNOWN_COLOR
	return CATEGORY_COLORS[category]


## The frame for `category` (GearData.Category; NEUTRAL or anything else: the rounded diamond),
## centred on `centre`, inside a square reaching `radius` from it. Clockwise, no repeated points,
## so draw_colored_polygon can always fill it.
static func frame_points(category: int, centre: Vector2, radius: float) -> PackedVector2Array:
	var unit: PackedVector2Array
	match category:
		GearData.Category.OFFENSIVE:
			unit = _spearhead()
		GearData.Category.DEFENSIVE:
			unit = _heater()
		GearData.Category.SUPPORT:
			unit = _seal()
		_:
			unit = _rounded_diamond()
	var points := PackedVector2Array()
	points.resize(unit.size())
	for i: int in unit.size():
		points[i] = centre + unit[i] * radius
	return points


## Paints `item`'s icon into `rect` on `canvas` (call it from that canvas's _draw), like the
## Control does: for drawn grids. `on_cursor`: the chosen glow.
static func draw_relic(canvas: CanvasItem, rect: Rect2, item: GearData, known: bool = true, level: int = 0,
		max_level: int = 0, on_cursor: bool = false) -> void:
	var seen := known and item != null
	_paint(canvas, rect, item, seen, SlotState.NONE, level, max_level, on_cursor, _texture_for(item) if seen else null)


## Paints a Relic slot (SlotState.EMPTY or LOCKED) into `rect` on `canvas`.
static func draw_slot(canvas: CanvasItem, rect: Rect2, state: int, on_cursor: bool = false) -> void:
	_paint(canvas, rect, null, false, state, 0, 0, on_cursor, null)


## Paints the hero tag (the first letter of `letter` on `color`) in `rect`'s top right corner.
static func draw_tag(canvas: CanvasItem, rect: Rect2, letter: String, color: Color) -> void:
	var text := letter.strip_edges().substr(0, 1).to_upper()
	if text.is_empty():
		return
	var side := minf(rect.size.x, rect.size.y)
	var r := clampf(side * TAG_SHARE, TAG_MIN, TAG_MAX)
	var ring := maxf(1.0, r * 0.18)
	var square := _square(rect)
	var centre := Vector2(square.end.x - r - ring, square.position.y + r + ring)
	canvas.draw_circle(centre, r + ring, OUTLINE)
	canvas.draw_circle(centre, r, color)
	_draw_text(canvas, text, centre, maxi(6, roundi(r * 1.35)), TAG_DARK if color.get_luminance() > 0.5 else HudStyle.TEXT)


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	_paint(self, rect, _item, _known, _slot, _level, _max_level, chosen, _texture)
	if not _tag.is_empty():
		draw_tag(self, rect, _tag, _tag_color)


func _size_to(px: float) -> void:
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _shows_relic() -> bool:
	return _slot == SlotState.NONE and _known and _item != null


## Everything but the tag, in a square centred in `rect`: glow, fill, inner line, sign, edge, gold
## ring, rot drip, pips.
static func _paint(canvas: CanvasItem, rect: Rect2, item: GearData, known: bool, slot: int, level: int,
		max_level: int, on_cursor: bool, texture: Texture2D) -> void:
	var side := minf(rect.size.x, rect.size.y)
	if side < 4.0:
		return
	var square := _square(rect)
	var edge := clampf(side * EDGE_SHARE, EDGE_MIN, EDGE_MAX)
	var relic := slot == SlotState.NONE and known and item != null
	var pips := pip_layout(level, max_level) if relic else Vector2i.ZERO
	var pip := _pip_size(side, pips.y)
	var strip := pip * (1.0 + PIP_GAP) if pips.y > 0 else 0.0
	if (side - strip) * 0.5 - edge < 3.0:
		# Too small for pips and a frame: the frame wins.
		pips = Vector2i.ZERO
		strip = 0.0
	var radius := (side - strip) * 0.5 - edge
	if radius < 1.0:
		return
	var c := square.position + Vector2(side * 0.5, (side - strip) * 0.5)
	var category := item.category() if relic else NEUTRAL
	var points := frame_points(category, c, radius)
	var edge_color := _edge_color(item, relic, slot)
	if on_cursor:
		for ring: PackedVector2Array in Geometry2D.offset_polygon(points, edge * 2.0, Geometry2D.JOIN_ROUND):
			canvas.draw_polyline(_closed(ring), Color(GLOW_COLOR, 0.3), edge * 2.0, true)
	var fill := FILL
	if relic:
		fill = FILL.lerp(Color(category_color(category), FILL.a), FILL_TINT)
	elif slot == SlotState.EMPTY:
		fill = Color(FILL, 0.55)
	elif slot == SlotState.LOCKED:
		fill = Color(FILL, 0.8)
	canvas.draw_colored_polygon(points, fill)
	var seal := category == GearData.Category.SUPPORT
	if slot == SlotState.NONE and (seal or radius >= INNER_MIN_RADIUS):
		var gap := maxf(edge * INNER_EDGES, radius * INNER_GAP_SHARE)
		for inner: PackedVector2Array in Geometry2D.offset_polygon(points, -gap, Geometry2D.JOIN_ROUND):
			if inner.size() >= 3:
				canvas.draw_polyline(_closed(inner), Color(edge_color, 0.7 if seal else 0.45), maxf(1.0, edge * 0.45), true)
	match slot:
		SlotState.EMPTY:
			UiGlyph.draw_glyph(canvas, &"plus", c, radius * 0.62, SLOT_COLOR)
		SlotState.LOCKED:
			UiGlyph.draw_glyph(canvas, &"lock", c + Vector2(0.0, radius * 0.04), radius * 0.72, LOCKED_SIGN)
		_:
			if not relic:
				_draw_text(canvas, "?", c, maxi(6, int(radius * 1.1)), UNKNOWN_COLOR)
			elif texture != null:
				var spot := c + SIGN_OFFSETS[category] * radius
				var pic := radius * 1.05
				canvas.draw_texture_rect(texture, Rect2(spot - Vector2(pic, pic) * 0.5, Vector2(pic, pic)), false)
			else:
				_draw_sign(canvas, category, c, radius, category_color(category))
	if slot == SlotState.EMPTY:
		_dashed_loop(canvas, points, SLOT_COLOR, maxf(1.5, edge * 0.8), maxf(2.0, edge * 2.0), maxf(1.5, edge * 1.4))
	else:
		canvas.draw_polyline(_closed(points), edge_color, edge * (1.25 if on_cursor else 1.0), true)
	if on_cursor:
		for ring: PackedVector2Array in Geometry2D.offset_polygon(points, edge * 1.15, Geometry2D.JOIN_ROUND):
			canvas.draw_polyline(_closed(ring), GLOW_COLOR, maxf(1.5, edge * 0.8), true)
	if relic and item.rot_touched:
		_draw_drip(canvas, points, c, radius)
	if pips.y > 0:
		_draw_pips(canvas, square, c.x, pip, pips)


## The largest square centred in `rect`.
static func _square(rect: Rect2) -> Rect2:
	var side := minf(rect.size.x, rect.size.y)
	return Rect2(rect.position + (rect.size - Vector2(side, side)) * 0.5, Vector2(side, side))


static func _edge_color(item: GearData, relic: bool, slot: int) -> Color:
	if slot == SlotState.EMPTY:
		return SLOT_COLOR
	if slot == SlotState.LOCKED:
		return LOCKED_COLOR
	if not relic:
		return UNKNOWN_COLOR
	if item.rot_touched:
		return GearData.ROT_TOUCHED_COLOR
	return BackpackGrid.rarity_color(BackpackGrid.gear_step(item))


static func _texture_for(item: GearData) -> Texture2D:
	if item == null or item.icon_path.is_empty() or not ResourceLoader.exists(item.icon_path):
		return null
	return load(item.icon_path) as Texture2D


## The category sign inside a frame of `radius` centred on `c`.
static func _draw_sign(canvas: CanvasItem, category: int, c: Vector2, radius: float, color: Color) -> void:
	var spot := c + SIGN_OFFSETS[category] * radius
	var s := SIGN_SIZES[category] * radius
	match category:
		GearData.Category.OFFENSIVE:
			UiGlyph.draw_glyph(canvas, &"sword", spot, s, color)
		GearData.Category.DEFENSIVE:
			# A shield boss: a ring and a domed middle with a glint.
			var h := s * 0.5
			canvas.draw_arc(spot, h * 0.8, 0.0, TAU, 28, color, maxf(1.2, h * 0.2), true)
			canvas.draw_circle(spot, h * 0.46, color)
			canvas.draw_circle(spot + Vector2(-h, -h) * 0.14, h * 0.14, Color(1.0, 1.0, 1.0, 0.45))
		_:
			UiGlyph.draw_glyph(canvas, &"leaf", spot, s, color)


## `text` centred on `centre` (the title font, as the "?" and the tag letter).
static func _draw_text(canvas: CanvasItem, text: String, centre: Vector2, font_size: int, color: Color) -> void:
	var font := HudStyle.title_font()
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := centre.y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	canvas.draw_string(font, Vector2(centre.x - width * 0.5, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			font_size, color)


## A rot drip oozing from the frame's lowest left point.
static func _draw_drip(canvas: CanvasItem, points: PackedVector2Array, c: Vector2, radius: float) -> void:
	var dir := DRIP_DIR.normalized()
	var anchor := points[0]
	for p: Vector2 in points:
		if (p - c).dot(dir) > (anchor - c).dot(dir):
			anchor = p
	var drop := maxf(1.2, radius * 0.09)
	var centre := anchor + Vector2(0.0, maxf(2.5, radius * 0.17))
	canvas.draw_colored_polygon(PackedVector2Array([anchor + Vector2(-drop * 0.6, -drop * 0.3),
			anchor + Vector2(drop * 0.6, -drop * 0.3), centre + Vector2(drop, 0.0), centre + Vector2(-drop, 0.0)]),
			GearData.ROT_TOUCHED_COLOR)
	canvas.draw_circle(centre, drop, GearData.ROT_TOUCHED_COLOR)


## A pip's diameter for `count` pips in an icon of `side`: shrinks when many would not fit.
static func _pip_size(side: float, count: int) -> float:
	var d := clampf(side * PIP_SHARE, PIP_MIN, PIP_MAX)
	if count > 0:
		d = minf(d, side * 0.92 / (float(count) + float(count - 1) * PIP_GAP))
	return d


## The pip row along the bottom of `square`: `pips.x` gold, the rest of `pips.y` dim.
static func _draw_pips(canvas: CanvasItem, square: Rect2, x: float, d: float, pips: Vector2i) -> void:
	var gap := d * PIP_GAP
	var row := float(pips.y) * d + float(pips.y - 1) * gap
	var y := square.end.y - d * 0.5
	var outline := maxf(0.75, d * 0.15)
	for i: int in pips.y:
		var p := Vector2(x - row * 0.5 + d * 0.5 + float(i) * (d + gap), y)
		canvas.draw_circle(p, d * 0.5 + outline, OUTLINE)
		canvas.draw_circle(p, d * 0.5, PIP_COLOR if i < pips.x else PIP_EMPTY)


## A dashed closed outline: dashes of `dash` with gaps of `gap` measured along the whole loop, so
## short corner segments do not break the rhythm.
static func _dashed_loop(canvas: CanvasItem, points: PackedVector2Array, color: Color, width: float, dash: float,
		gap: float) -> void:
	var loop := _closed(points)
	var on := true
	var left := dash
	var run := PackedVector2Array([loop[0]])
	for i: int in range(1, loop.size()):
		var a := loop[i - 1]
		var b := loop[i]
		var seg := a.distance_to(b)
		if seg <= 0.0:
			continue
		var pos := 0.0
		while pos + left < seg:
			pos += left
			var p := a.lerp(b, pos / seg)
			if on:
				run.append(p)
				if run.size() >= 2:
					canvas.draw_polyline(run, color, width, true)
			run = PackedVector2Array([p])
			on = not on
			left = dash if on else gap
		left = maxf(0.001, left - (seg - pos))
		if on:
			run.append(b)
	if on and run.size() >= 2:
		canvas.draw_polyline(run, color, width, true)


static func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var looped := points.duplicate()
	looped.append(points[0])
	return looped


## The offensive frame in unit size: a spearhead (or fang), its tip up, its sides bulging out and
## pinching in to two barbs, a V notch cut up into its base.
static func _spearhead() -> PackedVector2Array:
	var tip := Vector2(0.0, -1.0)
	var widest := Vector2(0.7, 0.22)
	var barb := Vector2(0.48, 0.9)
	var notch := Vector2(0.0, 0.6)
	var side := PackedVector2Array()
	for i: int in range(1, 8):
		side.append(_bezier(tip, Vector2(0.48, -0.36), widest, float(i) / 7.0))
	for i: int in range(1, 5):
		side.append(_bezier(widest, Vector2(0.7, 0.62), barb, float(i) / 4.0))
	var points := PackedVector2Array([tip])
	points.append_array(side)
	points.append(notch)
	for i: int in range(side.size() - 1, -1, -1):
		points.append(Vector2(-side[i].x, side[i].y))
	return points


## The defensive frame in unit size: a heater shield, its top flat, rounded down to a point (the
## shape of UiGlyph's shield, a little wider).
static func _heater() -> PackedVector2Array:
	var top := -0.86
	var half := 0.84
	var steps := 12
	var points := PackedVector2Array([Vector2(-half, top), Vector2(half, top)])
	for i: int in range(1, steps + 1):
		var t := float(i) / float(steps)
		points.append(Vector2(half * (1.0 - t * t), top + t * (1.0 - top)))
	for i: int in range(steps - 1, 0, -1):
		var t := float(i) / float(steps)
		points.append(Vector2(-half * (1.0 - t * t), top + t * (1.0 - top)))
	return points


## The support frame in unit size: a round seal (its second ring is drawn as the inner line).
static func _seal() -> PackedVector2Array:
	var points := PackedVector2Array()
	var steps := 40
	for i: int in steps:
		var a := -PI * 0.5 + TAU * float(i) / float(steps)
		points.append(Vector2(cos(a), sin(a)) * 0.92)
	return points


## The neutral frame in unit size: Expedition 33's diamond with softened corners.
static func _rounded_diamond() -> PackedVector2Array:
	var corners: Array[Vector2] = [Vector2(0.0, -1.0), Vector2(1.0, 0.0), Vector2(0.0, 1.0), Vector2(-1.0, 0.0)]
	var soften := 0.16
	var points := PackedVector2Array()
	for k: int in corners.size():
		var at := corners[k]
		var from := at.lerp(corners[(k + 3) % 4], soften)
		var to := at.lerp(corners[(k + 1) % 4], soften)
		for i: int in 4:
			points.append(_bezier(from, at, to, float(i) / 3.0))
	return points


static func _bezier(a: Vector2, control: Vector2, b: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return a * (u * u) + control * (2.0 * u * t) + b * (t * t)
