class_name MenuBackdrop
extends Control
## The background of every screen outside a fight (card #37): a dark gradient, a sickly glow
## rising from the bottom, slow motes of rot drifting up, and a vignette. Fills its parent.

const TOP := Color(0.03, 0.03, 0.05)
const BOTTOM := Color(0.08, 0.07, 0.08)
const GLOW := Color(0.36, 0.44, 0.14, 0.22)
const VIGNETTE := Color(0.0, 0.0, 0.0, 0.7)
const MOTE := Color(0.78, 0.86, 0.42)
const MOTE_ALPHA: float = 0.55
const MOTES: int = 70
const MOTE_LIFE_S: float = 11.0
const MOTE_SPEED_MIN: float = 25.0
const MOTE_SPEED_MAX: float = 70.0
const MOTE_SIZE_MIN: float = 2.0
const MOTE_SIZE_MAX: float = 5.0
## Sideways sway of the motes (pixels per second squared, both ways).
const MOTE_SWAY: float = 6.0
const GRADIENT_PX: int = 256

var _motes: CPUParticles2D


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_layer(_linear(TOP, BOTTOM)))
	add_child(_layer(_radial(GLOW, Vector2(0.5, 1.15), Vector2(0.5, 0.35))))
	_motes = CPUParticles2D.new()
	_motes.amount = MOTES
	_motes.lifetime = MOTE_LIFE_S
	_motes.preprocess = MOTE_LIFE_S
	_motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_motes.direction = Vector2.UP
	_motes.spread = 12.0
	_motes.gravity = Vector2.ZERO
	_motes.initial_velocity_min = MOTE_SPEED_MIN
	_motes.initial_velocity_max = MOTE_SPEED_MAX
	_motes.linear_accel_min = -MOTE_SWAY
	_motes.linear_accel_max = MOTE_SWAY
	_motes.tangential_accel_min = -MOTE_SWAY
	_motes.tangential_accel_max = MOTE_SWAY
	_motes.scale_amount_min = MOTE_SIZE_MIN
	_motes.scale_amount_max = MOTE_SIZE_MAX
	var ramp := Gradient.new()
	ramp.set_color(0, Color(MOTE, 0.0))
	ramp.set_color(1, Color(MOTE, 0.0))
	ramp.add_point(0.25, Color(MOTE, MOTE_ALPHA))
	ramp.add_point(0.7, Color(MOTE, MOTE_ALPHA * 0.6))
	_motes.color_ramp = ramp
	add_child(_motes)
	add_child(_layer(_radial(Color(VIGNETTE, 0.0), Vector2(0.5, 0.5), Vector2(0.5, 1.25), VIGNETTE)))
	resized.connect(_place_motes)


func _ready() -> void:
	_place_motes()


func _place_motes() -> void:
	_motes.position = Vector2(size.x * 0.5, size.y * 0.8)
	_motes.emission_rect_extents = Vector2(size.x * 0.5, size.y * 0.3)


static func _layer(texture: Texture2D) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	return rect


static func _linear(from: Color, to: Color) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, from)
	gradient.set_color(1, to)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 4
	texture.height = GRADIENT_PX
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(0.0, 1.0)
	return texture


## A radial gradient from `inner` at `centre` to `outer` (default: `inner` see-through) at `edge`.
static func _radial(inner: Color, centre: Vector2, edge: Vector2, outer: Color = Color(0, 0, 0, 0)) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, inner)
	gradient.set_color(1, outer if outer.a > 0.0 else Color(inner, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = GRADIENT_PX
	texture.height = GRADIENT_PX
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = centre
	texture.fill_to = edge
	return texture
