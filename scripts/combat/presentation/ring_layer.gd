class_name RingLayer
extends Control
## Draws the timing rings (DESIGN.md 3.7 and 2.10): circles that shrink onto a target and close
## exactly at the perfect moment. Skill press rings also show their timing zones osu-style: a faint
## target circle, a GOOD band and a gold PERFECT band; pressing while the shrinking ring is inside
## a band gives that result. A skill with several presses numbers its rings (PressNotes). The
## runners set them every frame in HUD canvas pixels.

const LABEL_SIZE: int = 30
const LABEL_OUTLINE: int = 8
const LABEL_GAP: float = 10.0
const SEGMENTS: int = 64
const NUMBER_SIZE: int = 34
const NUMBER_OUTLINE: int = 8

## Each ring: {pos: Vector2, radius: float, color: Color, label: String}, optionally
## target_radius: float and target_color: Color (a faint filled circle the ring closes onto),
## bands: [{radius: float (middle), width: float, color: Color}] drawn under the ring, and
## number: String drawn in the middle.
var _rings: Array[Dictionary] = []
var _width: float = 6.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func set_rings(rings: Array[Dictionary], width: float) -> void:
	if rings.is_empty() and _rings.is_empty():
		return
	_rings = rings
	_width = width
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for ring: Dictionary in _rings:
		var pos: Vector2 = ring.pos
		var radius := float(ring.radius)
		var color: Color = ring.color
		if ring.has("target_radius"):
			draw_circle(pos, float(ring.target_radius), ring.get("target_color", Color(1, 1, 1, 0.12)) as Color)
		# With zones the label stays put above the outer band; otherwise it rides on the ring.
		var bands: Array = ring.get("bands", [])
		var label_radius := radius if bands.is_empty() else 0.0
		for band: Dictionary in bands:
			var band_r := float(band.radius)
			var band_w := maxf(1.0, float(band.width))
			draw_arc(pos, band_r, 0.0, TAU, SEGMENTS, band.color as Color, band_w, true)
			label_radius = maxf(label_radius, band_r + band_w * 0.5)
		draw_arc(pos, radius + _width * 0.5, 0.0, TAU, SEGMENTS, HudStyle.OUTLINE_COLOR, _width * 0.5, true)
		draw_arc(pos, radius, 0.0, TAU, SEGMENTS, color, _width, true)
		var number := String(ring.get("number", ""))
		if not number.is_empty():
			var number_size := font.get_string_size(number, HORIZONTAL_ALIGNMENT_LEFT, -1, NUMBER_SIZE)
			var number_at := pos + Vector2(-number_size.x * 0.5, NUMBER_SIZE * 0.35)
			draw_string_outline(font, number_at, number, HORIZONTAL_ALIGNMENT_LEFT, -1, NUMBER_SIZE, NUMBER_OUTLINE, HudStyle.OUTLINE_COLOR)
			draw_string(font, number_at, number, HORIZONTAL_ALIGNMENT_LEFT, -1, NUMBER_SIZE, HudStyle.TEXT)
		var text := String(ring.get("label", ""))
		if text.is_empty():
			continue
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE)
		var at := pos + Vector2(-text_size.x * 0.5, -label_radius - LABEL_GAP)
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, LABEL_OUTLINE, HudStyle.OUTLINE_COLOR)
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, color)
