class_name RelicIcon
extends Control
## A Relic's diamond, like Expedition 33's Picto and Lumina icons (DESIGN.md 8.17): a dark diamond
## edged in the Relic's rarity colour (violet for a rot-touched one), and inside it the Relic's own
## picture (GearData.icon_path) or, while it has none, a drawn sign for its category: a blade
## (offensive), a shield (defensive) or a star (support). An unknown Relic shows a dim "?".

## Sign colours by category (offensive, defensive, support), and an unknown Relic's.
const SIGN_COLORS: Array[Color] = [Color(1.0, 0.5, 0.35), Color(0.45, 0.75, 1.0), Color(0.45, 0.95, 0.55)]
const UNKNOWN_COLOR := Color(0.45, 0.45, 0.5)
const FILL := Color(0.03, 0.025, 0.04, 0.95)
const EDGE_PX: float = 2.5
## The inner diamond line sits this share of the way in.
const INNER_SHARE: float = 0.78

var _item: GearData
var _known: bool = true
var _texture: Texture2D


## `px`: the diamond's width and height. `known` false: a "?" for a Relic not found yet.
func setup(item: GearData, px: float, known: bool = true) -> void:
	_item = item
	_known = known and item != null
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_texture = null
	if _known and not item.icon_path.is_empty() and ResourceLoader.exists(item.icon_path):
		_texture = load(item.icon_path) as Texture2D
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - EDGE_PX
	var edge := _edge_color()
	draw_colored_polygon(_diamond(c, r), FILL)
	draw_polyline(_closed(_diamond(c, r)), edge, EDGE_PX, true)
	draw_polyline(_closed(_diamond(c, r * INNER_SHARE)), Color(edge, 0.45), 1.0, true)
	if not _known:
		var font := ThemeDB.fallback_font
		var font_size := int(r * 0.9)
		draw_string(font, c + Vector2(-r * 0.28, r * 0.32), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UNKNOWN_COLOR)
		return
	if _texture != null:
		var side := r * 1.05
		draw_texture_rect(_texture, Rect2(c - Vector2(side, side) * 0.5, Vector2(side, side)), false)
		return
	_draw_sign(c, r * 0.55, SIGN_COLORS[_item.category()])


func _edge_color() -> Color:
	if not _known:
		return UNKNOWN_COLOR
	if _item.rot_touched:
		return GearData.ROT_TOUCHED_COLOR
	return BackpackGrid.rarity_color(BackpackGrid.gear_step(_item))


## The category sign, about `s` from the centre `c` to its tips.
func _draw_sign(c: Vector2, s: float, color: Color) -> void:
	var w := maxf(1.5, s * 0.16)
	match _item.category():
		GearData.Category.OFFENSIVE:
			# A blade point up, with a crossguard and a grip.
			draw_line(c + Vector2(0.0, -s), c + Vector2(0.0, s * 0.55), color, w, true)
			draw_line(c + Vector2(-s * 0.5, s * 0.35), c + Vector2(s * 0.5, s * 0.35), color, w, true)
			draw_line(c + Vector2(0.0, s * 0.55), c + Vector2(0.0, s), color, w * 1.4, true)
		GearData.Category.DEFENSIVE:
			# A shield.
			var shield := PackedVector2Array([c + Vector2(-s * 0.75, -s * 0.8), c + Vector2(s * 0.75, -s * 0.8),
					c + Vector2(s * 0.7, s * 0.1), c + Vector2(0.0, s), c + Vector2(-s * 0.7, s * 0.1)])
			draw_polyline(_closed(shield), color, w, true)
			draw_line(c + Vector2(0.0, -s * 0.8), c + Vector2(0.0, s * 0.85), color, w * 0.7, true)
		_:
			# A four-point star.
			var star := PackedVector2Array()
			for i: int in 8:
				var angle := -PI * 0.5 + float(i) * PI / 4.0
				var reach := s if i % 2 == 0 else s * 0.32
				star.append(c + Vector2(cos(angle), sin(angle)) * reach)
			draw_polyline(_closed(star), color, w, true)


static func _diamond(c: Vector2, r: float) -> PackedVector2Array:
	return PackedVector2Array([c + Vector2(0.0, -r), c + Vector2(r, 0.0), c + Vector2(0.0, r), c + Vector2(-r, 0.0)])


static func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var looped := points.duplicate()
	looped.append(points[0])
	return looped
