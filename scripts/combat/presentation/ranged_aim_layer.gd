class_name RangedAimLayer
extends Control
## Draws the ranged-hit indicators (DESIGN.md 3.9, card #165): a dashed path from the flying
## projectile to the hero it is thrown at, and four corner brackets on that hero that close in and
## meet exactly at the hit's impact. The colour is the hit's kind colour (DESIGN.md 3.8). The
## runner sets them every frame in HUD canvas pixels, from RangedAim's pure timing.

const LABEL_SIZE: int = 24
const LABEL_OUTLINE: int = 7
const LABEL_GAP: float = 8.0
## Corner arms are this share of the bracket's half size, never shorter than ARM_MIN_PX.
const ARM_SHARE: float = 0.5
const ARM_MIN_PX: float = 8.0
## The dark edge drawn under every line, this much wider.
const EDGE_EXTRA_PX: float = 3.0
## A locked bracket is filled with the colour at this alpha (plus the lock pulse).
const LOCK_FILL_ALPHA: float = 0.14

## Each aim: {center: Vector2 (the hero), half: float (bracket half size, px), color: Color,
## alpha: float, path: PackedVector2Array (screen points from the projectile to the hero),
## path_strength: float (the path's share of alpha),
## locked: bool, pulse: float (0..1 extra brightness), label: String, line_px: float,
## dash_px: float, gap_px: float}.
var _aims: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func set_aims(aims: Array[Dictionary]) -> void:
	if aims.is_empty() and _aims.is_empty():
		return
	_aims = aims
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for aim: Dictionary in _aims:
		var alpha := float(aim.alpha)
		if alpha <= 0.0:
			continue
		var color: Color = aim.color
		var line := float(aim.line_px)
		_draw_path(aim.path as PackedVector2Array, color, alpha * float(aim.get("path_strength", 1.0)), line,
				float(aim.dash_px), float(aim.gap_px))
		var centre: Vector2 = aim.center
		var half := float(aim.half)
		var pulse := float(aim.get("pulse", 0.0))
		var shown := Color(color.r, color.g, color.b, alpha)
		if bool(aim.locked):
			var fill := Color(color.r, color.g, color.b, alpha * (LOCK_FILL_ALPHA + pulse * 0.4))
			draw_rect(Rect2(centre - Vector2(half, half), Vector2(half, half) * 2.0), fill)
		if pulse > 0.0:
			shown = shown.lerp(Color(1, 1, 1, alpha), pulse * 0.6)
		_draw_corners(centre, half, shown, line)
		var text := String(aim.get("label", ""))
		if text.is_empty():
			continue
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE)
		var at := centre + Vector2(-text_size.x * 0.5, half + LABEL_GAP + text_size.y * 0.75)
		var text_color := Color(color.r, color.g, color.b, alpha)
		var outline := HudStyle.OUTLINE_COLOR
		outline.a *= alpha
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, LABEL_OUTLINE, outline)
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, text_color)


## Four L-shaped corners of the square of half size `half` around `centre`.
func _draw_corners(centre: Vector2, half: float, color: Color, line: float) -> void:
	var arm := maxf(ARM_MIN_PX, half * ARM_SHARE)
	var edge := HudStyle.OUTLINE_COLOR
	edge.a *= color.a
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var corner := centre + Vector2(sx * half, sy * half)
			var along_x := corner - Vector2(sx * arm, 0.0)
			var along_y := corner - Vector2(0.0, sy * arm)
			draw_polyline(PackedVector2Array([along_x, corner, along_y]), edge, line + EDGE_EXTRA_PX, true)
			draw_polyline(PackedVector2Array([along_x, corner, along_y]), color, line, true)


## A dashed line along `points` (dash then gap, carried round the corners).
func _draw_path(points: PackedVector2Array, color: Color, alpha: float, line: float, dash: float, gap: float) -> void:
	if points.size() < 2 or dash <= 0.0:
		return
	var edge := HudStyle.OUTLINE_COLOR
	edge.a *= alpha
	var shown := Color(color.r, color.g, color.b, alpha)
	var drawing := true
	var left := dash
	for i: int in points.size() - 1:
		var from := points[i]
		var to := points[i + 1]
		var length := from.distance_to(to)
		if length <= 0.001:
			continue
		var dir := (to - from) / length
		var at := 0.0
		while at < length:
			var step := minf(left, length - at)
			if drawing:
				draw_line(from + dir * at, from + dir * (at + step), edge, line + EDGE_EXTRA_PX)
				draw_line(from + dir * at, from + dir * (at + step), shown, line)
			at += step
			left -= step
			if left <= 0.0:
				drawing = not drawing
				left = dash if drawing else gap
