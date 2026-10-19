class_name UiGlyph
extends Control
## A small drawn icon for menus (the Y screen's tabs, stats, chips; DESIGN.md 8.18), so screens can
## show a picture instead of a word. Every glyph is drawn in code from simple shapes, filled in one
## colour, and fits a square of `px`. draw_glyph() draws one on any CanvasItem (RelicIcon, grids).
## Kinds: heart (HP, Vitality), sword (Might, Power, offensive), bolt (Speed), chevrons (Agility),
## shield (Defense, defensive), star (Luck, crit), leaf (support), coin (gold), bag (backpack),
## pouch (the Relic bag), lock, plus, skull (curses, downed), person (a hero), branch (skills),
## gem (a Relic), up (points to spend), echo (an Echo).

const KINDS: Array[StringName] = [&"heart", &"sword", &"bolt", &"chevrons", &"shield", &"star", &"leaf",
	&"coin", &"bag", &"pouch", &"lock", &"plus", &"skull", &"person", &"branch", &"gem", &"up", &"echo"]

var kind: StringName = &"star"
var color: Color = HudStyle.TEXT


## `px`: the glyph's square side.
func setup(p_kind: StringName, px: float, p_color: Color = HudStyle.TEXT) -> UiGlyph:
	kind = p_kind
	color = p_color
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()
	return self


## The glyph of an attribute (Attributes.Kind: Vitality, Might, Agility, Defense, Luck), the same
## on every page.
static func attribute_glyph(attribute: int) -> StringName:
	return [&"heart", &"sword", &"chevrons", &"shield", &"star"][clampi(attribute, 0, 4)]


## A new glyph Control.
static func make(p_kind: StringName, px: float, p_color: Color = HudStyle.TEXT) -> UiGlyph:
	return UiGlyph.new().setup(p_kind, px, p_color)


func _draw() -> void:
	var side := minf(size.x, size.y)
	draw_glyph(self, kind, size * 0.5, side, color)


## Draws glyph `kind` on `canvas`, centred on `c`, fitting a square of side `s`.
static func draw_glyph(canvas: CanvasItem, glyph: StringName, c: Vector2, s: float, col: Color) -> void:
	var h := s * 0.5
	var w := maxf(1.5, s * 0.11)
	match glyph:
		&"heart":
			var pts := PackedVector2Array()
			for i: int in 32:
				var t := TAU * float(i) / 32.0
				# The heart curve, scaled into the square.
				var x := 16.0 * pow(sin(t), 3.0)
				var y := -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))
				pts.append(c + Vector2(x, y + 1.5) * (h / 17.5))
			canvas.draw_colored_polygon(pts, col)
		&"sword":
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -h), c + Vector2(h * 0.2, -h * 0.72),
					c + Vector2(h * 0.2, h * 0.3), c + Vector2(-h * 0.2, h * 0.3), c + Vector2(-h * 0.2, -h * 0.72)]), col)
			canvas.draw_rect(Rect2(c + Vector2(-h * 0.62, h * 0.3), Vector2(h * 1.24, h * 0.2)), col)
			canvas.draw_rect(Rect2(c + Vector2(-h * 0.12, h * 0.5), Vector2(h * 0.24, h * 0.36)), col)
			canvas.draw_circle(c + Vector2(0, h * 0.92), h * 0.13, col)
		&"bolt":
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(h * 0.2, -h), c + Vector2(-h * 0.62, h * 0.12),
					c + Vector2(-h * 0.04, h * 0.12), c + Vector2(-h * 0.24, h), c + Vector2(h * 0.62, -h * 0.16),
					c + Vector2(h * 0.04, -h * 0.16)]), col)
		&"chevrons":
			for dy: float in [-0.45, 0.25]:
				canvas.draw_polyline(PackedVector2Array([c + Vector2(-h * 0.7, h * (dy + 0.4)), c + Vector2(0, h * dy),
						c + Vector2(h * 0.7, h * (dy + 0.4))]), col, w * 1.3, true)
		&"shield":
			canvas.draw_colored_polygon(_shield(c, h), col)
		&"star":
			var star := PackedVector2Array()
			for i: int in 10:
				var a := -PI * 0.5 + float(i) * PI / 5.0
				star.append(c + Vector2(cos(a), sin(a)) * (h if i % 2 == 0 else h * 0.42))
			canvas.draw_colored_polygon(star, col)
		&"leaf":
			var leaf := PackedVector2Array()
			for i: int in 17:
				var t := PI * float(i) / 16.0
				leaf.append(c + Vector2(-h * 0.8 + h * 1.6 * float(i) / 16.0, -sin(t) * h * 0.55).rotated(-0.6))
			for i: int in range(15, 0, -1):
				var t := PI * float(i) / 16.0
				leaf.append(c + Vector2(-h * 0.8 + h * 1.6 * float(i) / 16.0, sin(t) * h * 0.4).rotated(-0.6))
			canvas.draw_colored_polygon(leaf, col)
		&"coin":
			canvas.draw_circle(c, h * 0.9, col)
			canvas.draw_arc(c, h * 0.55, 0.0, TAU, 24, Color(0, 0, 0, 0.45), w, true)
		&"bag":
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-h * 0.8, -h * 0.25), c + Vector2(h * 0.8, -h * 0.25),
					c + Vector2(h * 0.66, h * 0.9), c + Vector2(-h * 0.66, h * 0.9)]), col)
			canvas.draw_arc(c + Vector2(0, -h * 0.3), h * 0.42, PI, TAU, 16, col, w * 1.3, true)
		&"pouch":
			canvas.draw_circle(c + Vector2(0, h * 0.25), h * 0.68, col)
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-h * 0.3, -h * 0.5), c + Vector2(h * 0.3, -h * 0.5),
					c + Vector2(h * 0.18, -h * 0.25), c + Vector2(-h * 0.18, -h * 0.25)]), col)
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-h * 0.55, -h * 0.95), c + Vector2(h * 0.55, -h * 0.95),
					c + Vector2(h * 0.25, -h * 0.5), c + Vector2(-h * 0.25, -h * 0.5)]), col)
		&"lock":
			canvas.draw_rect(Rect2(c + Vector2(-h * 0.7, -h * 0.1), Vector2(h * 1.4, h * 1.0)), col)
			canvas.draw_arc(c + Vector2(0, -h * 0.15), h * 0.45, PI, TAU, 16, col, w * 1.4, true)
			canvas.draw_line(c + Vector2(-h * 0.45, -h * 0.15), c + Vector2(-h * 0.45, -h * 0.05), col, w * 1.4)
			canvas.draw_line(c + Vector2(h * 0.45, -h * 0.15), c + Vector2(h * 0.45, -h * 0.05), col, w * 1.4)
		&"plus":
			canvas.draw_rect(Rect2(c + Vector2(-h * 0.16, -h * 0.75), Vector2(h * 0.32, h * 1.5)), col)
			canvas.draw_rect(Rect2(c + Vector2(-h * 0.75, -h * 0.16), Vector2(h * 1.5, h * 0.32)), col)
		&"skull":
			canvas.draw_circle(c + Vector2(0, -h * 0.15), h * 0.72, col)
			canvas.draw_rect(Rect2(c + Vector2(-h * 0.42, h * 0.3), Vector2(h * 0.84, h * 0.55)), col)
			var hole := Color(0.03, 0.025, 0.04, 0.95)
			canvas.draw_circle(c + Vector2(-h * 0.3, -h * 0.15), h * 0.2, hole)
			canvas.draw_circle(c + Vector2(h * 0.3, -h * 0.15), h * 0.2, hole)
		&"person":
			canvas.draw_circle(c + Vector2(0, -h * 0.42), h * 0.4, col)
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(-h * 0.85, h * 0.95), c + Vector2(-h * 0.6, h * 0.2),
					c + Vector2(0, h * 0.02), c + Vector2(h * 0.6, h * 0.2), c + Vector2(h * 0.85, h * 0.95)]), col)
		&"branch":
			var top := c + Vector2(0, -h * 0.62)
			var left := c + Vector2(-h * 0.62, h * 0.62)
			var right := c + Vector2(h * 0.62, h * 0.62)
			canvas.draw_line(top, c, col, w)
			canvas.draw_line(c, left, col, w)
			canvas.draw_line(c, right, col, w)
			for p: Vector2 in [top, left, right]:
				canvas.draw_circle(p, h * 0.3, col)
		&"gem":
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -h * 0.9), c + Vector2(h * 0.75, 0),
					c + Vector2(0, h * 0.9), c + Vector2(-h * 0.75, 0)]), col)
		&"up":
			canvas.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -h * 0.9), c + Vector2(h * 0.8, 0),
					c + Vector2(h * 0.3, 0), c + Vector2(h * 0.3, h * 0.9), c + Vector2(-h * 0.3, h * 0.9),
					c + Vector2(-h * 0.3, 0), c + Vector2(-h * 0.8, 0)]), col)
		&"echo":
			canvas.draw_circle(c, h * 0.3, col)
			canvas.draw_arc(c, h * 0.62, 0.0, TAU, 24, col, w, true)
			canvas.draw_arc(c, h * 0.92, -0.9, 0.9, 10, col, w, true)
			canvas.draw_arc(c, h * 0.92, PI - 0.9, PI + 0.9, 10, col, w, true)
		_:
			canvas.draw_circle(c, h * 0.5, col)


## A heater shield, top flat and rounded down to a point (also the defensive Relic frame).
static func _shield(c: Vector2, h: float) -> PackedVector2Array:
	var pts := PackedVector2Array([c + Vector2(-h * 0.8, -h * 0.85), c + Vector2(h * 0.8, -h * 0.85)])
	for i: int in range(1, 9):
		var t := float(i) / 8.0
		pts.append(c + Vector2(h * 0.8 * (1.0 - t * t), -h * 0.85 + t * h * 1.85))
	for i: int in range(7, 0, -1):
		var t := float(i) / 8.0
		pts.append(c + Vector2(-h * 0.8 * (1.0 - t * t), -h * 0.85 + t * h * 1.85))
	return pts
