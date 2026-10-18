class_name AttributeRadar
extends Control
## A hero's five attributes as a radar (a pentagon), like Expedition 33's character page: the
## grid, the hero's shape filled in their colour, and each attribute's name and points at its tip.

const GRID := Color(0.72, 0.6, 0.38, 0.35)
const RINGS: int = 3
const LABEL_SIZE: int = 18
## The radius share left for the names around the pentagon.
const LABEL_ROOM: float = 0.3

var _values: Array[int] = []
var _top: int = 1
var _color: Color = HudStyle.GOLD


## `values`: points per attribute (Attributes.Kind order); `top`: the value that reaches the tip.
func setup(values: Array[int], top: int, color: Color, px: float) -> void:
	_values = values
	_top = maxi(1, top)
	_color = color
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 * (1.0 - LABEL_ROOM)
	var count := Attributes.COUNT
	for ring: int in range(1, RINGS + 1):
		var points := _shape(c, r * float(ring) / float(RINGS), [])
		points.append(points[0])
		draw_polyline(points, GRID, 1.0, true)
	for i: int in count:
		draw_line(c, c + _dir(i) * r, GRID, 1.0, true)
	var shape := _shape(c, r, _values)
	draw_colored_polygon(shape, Color(_color, 0.35))
	shape.append(shape[0])
	draw_polyline(shape, _color, 2.0, true)
	var font := HudStyle.body_font()
	for i: int in count:
		var text := "%s %d" % [Attributes.NAMES[i], _values[i] if i < _values.size() else 0]
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x
		var at := c + _dir(i) * (r + LABEL_SIZE * 0.9)
		draw_string_outline(font, at - Vector2(width * 0.5, -LABEL_SIZE * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				LABEL_SIZE, 4, HudStyle.OUTLINE_COLOR)
		draw_string(font, at - Vector2(width * 0.5, -LABEL_SIZE * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE,
				HudStyle.TEXT)


## The pentagon's corners at radius `r` (`values` scale each one; empty: the full grid).
func _shape(c: Vector2, r: float, values: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i: int in Attributes.COUNT:
		var share := 1.0
		if not values.is_empty():
			share = clampf(float(values[i] if i < values.size() else 0) / float(_top), 0.06, 1.0)
		points.append(c + _dir(i) * r * share)
	return points


## Attribute `i`'s direction: the first straight up, the rest round clockwise.
static func _dir(i: int) -> Vector2:
	var angle := -PI * 0.5 + float(i) * TAU / float(Attributes.COUNT)
	return Vector2(cos(angle), sin(angle))
