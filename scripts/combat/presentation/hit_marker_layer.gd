class_name HitMarkerLayer
extends Control
## Draws the hit markers (DESIGN.md 3.8): while a hit's motion plays, its icon on a dark disc
## with a border in the hit's colour, beside each target on the side the hit comes from, and
## "JUMP" under a ground hit's icon. The runner sets them every frame in HUD canvas pixels.

const LABEL_SIZE: int = 26
const LABEL_OUTLINE: int = 7
const LABEL_GAP: float = 4.0
const SEGMENTS: int = 48
## Disc radius and border width, as shares of the icon size.
const DISC_SHARE: float = 0.68
const BORDER_SHARE: float = 0.09
const DISC_COLOR := Color(0.04, 0.03, 0.05, 0.85)

## Each marker: {pos: Vector2 (centre), size: float (icon px, pop scale included),
## texture: Texture2D, color: Color (border and label), label: String}.
var _markers: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_preset(Control.PRESET_FULL_RECT)


func set_markers(markers: Array[Dictionary]) -> void:
	if markers.is_empty() and _markers.is_empty():
		return
	_markers = markers
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for marker: Dictionary in _markers:
		var pos: Vector2 = marker.pos
		var px := float(marker.size)
		var color: Color = marker.color
		var radius := px * DISC_SHARE
		draw_circle(pos, radius, DISC_COLOR)
		draw_arc(pos, radius, 0.0, TAU, SEGMENTS, color, maxf(2.0, px * BORDER_SHARE), true)
		var texture := marker.get("texture") as Texture2D
		if texture != null:
			draw_texture_rect(texture, Rect2(pos - Vector2(px, px) * 0.5, Vector2(px, px)), false)
		var text := String(marker.get("label", ""))
		if text.is_empty():
			continue
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE)
		var at := pos + Vector2(-text_size.x * 0.5, radius + LABEL_GAP + text_size.y * 0.75)
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, LABEL_OUTLINE, HudStyle.OUTLINE_COLOR)
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, color)
