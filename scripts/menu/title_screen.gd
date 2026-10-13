class_name TitleScreen
extends CanvasLayer
## The title screen (DESIGN.md 7.7, card #82), after the studio intro: the logo fades in over the
## menu background with drifting fog and a soft green glow that breathes behind it, then
## "Press any button" pulses under it. Any key, button or click (after skip_guard_ms) sends `done`
## once. The logo is an AnimatedLogo: its ribbon sways and its letters' edges flicker like
## static. Numbers live in data/branding/branding.tres.

signal done

const FOG_SHADER := preload("res://scripts/menu/fog.gdshader")
## The glow behind the logo, as a share of the logo's size.
const GLOW_SCALE := Vector2(1.15, 1.6)
## The prompt sits this far under the logo's centre, as a share of the screen height.
const PROMPT_DROP_SHARE: float = 0.4

var _branding: BrandingData
var _logo: AnimatedLogo
var _glow: TextureRect
var _prompt: Label
var _started_ms: int = 0
var _finished: bool = false


func setup(branding: BrandingData) -> void:
	_branding = branding
	add_child(MenuBackdrop.new())
	var fog := ColorRect.new()
	fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fog.set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = FOG_SHADER
	mat.set_shader_parameter("fog_color", branding.fog_color)
	mat.set_shader_parameter("speed", branding.fog_speed)
	fog.material = mat
	fog.resized.connect(func() -> void:
		mat.set_shader_parameter("aspect", fog.size.x / maxf(1.0, fog.size.y)))
	add_child(fog)
	_glow = TextureRect.new()
	_glow.texture = _radial(branding.glow_color)
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glow.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_glow)
	_logo = AnimatedLogo.new()
	_logo.setup(branding)
	add_child(_logo)
	_prompt = HudStyle.make_title(branding.prompt_text, branding.prompt_size, HudStyle.TEXT)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.label_settings.shadow_color = Color(0.0, 0.0, 0.0, 0.7)
	_prompt.label_settings.shadow_offset = Vector2(0.0, 3.0)
	_prompt.modulate.a = 0.0
	add_child(_prompt)


func _ready() -> void:
	_started_ms = Time.get_ticks_msec()
	_layout()
	get_viewport().size_changed.connect(_layout)
	_logo.modulate.a = 0.0
	_glow.modulate.a = 0.0
	var grow := 1.0 - float(_branding.logo_grow_percent) / 100.0
	_logo.scale = Vector2(grow, grow)
	var seconds := float(_branding.logo_fade_in_ms) / 1000.0
	var tween := create_tween().set_parallel()
	tween.tween_property(_logo, "modulate:a", 1.0, seconds).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_logo, "scale", Vector2.ONE, seconds).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


func _process(_delta: float) -> void:
	var elapsed_ms := Time.get_ticks_msec() - _started_ms
	var in_share := clampf(float(elapsed_ms) / maxf(1.0, float(_branding.logo_fade_in_ms)), 0.0, 1.0)
	# The glow breathes between glow_low_percent and full.
	var breath := 0.5 - 0.5 * cos(TAU * float(elapsed_ms) / float(_branding.glow_pulse_ms))
	var low := float(_branding.glow_low_percent) / 100.0
	_glow.modulate.a = in_share * lerpf(low, 1.0, breath)
	# The prompt appears once the logo is in, then fades in and out.
	var since_in := elapsed_ms - _branding.logo_fade_in_ms
	if since_in > 0:
		var blink := 0.5 + 0.5 * cos(TAU * float(since_in) / float(_branding.prompt_blink_ms) + PI)
		_prompt.modulate.a = lerpf(0.25, 1.0, blink) * clampf(float(since_in) / 400.0, 0.0, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if _finished or Time.get_ticks_msec() - _started_ms < _branding.skip_guard_ms:
		return
	var pressed := (event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton) \
			and event.is_pressed() and not event.is_echo()
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	_finished = true
	Sfx.play("menu_confirm")
	done.emit()


## The logo centred a little above the middle, the glow behind it, the prompt under it.
func _layout() -> void:
	var screen := get_viewport().get_visible_rect().size
	var width := screen.x * float(_branding.title_logo_width_percent) / 100.0
	var height := width * _logo.logo_size.y / maxf(1.0, _logo.logo_size.x)
	var centre := Vector2(screen.x * 0.5, screen.y * 0.44)
	_logo.size = Vector2(width, height)
	_logo.position = centre - _logo.size * 0.5
	_logo.pivot_offset = _logo.size * 0.5
	_glow.size = Vector2(width, height) * GLOW_SCALE
	_glow.position = centre - _glow.size * 0.5
	_prompt.size = Vector2(screen.x, float(_branding.prompt_size) * 1.6)
	_prompt.position = Vector2(0.0, centre.y + screen.y * PROMPT_DROP_SHARE - _prompt.size.y * 0.5)


static func _radial(color: Color) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, color)
	gradient.set_color(1, Color(color, 0.0))
	gradient.add_point(0.45, Color(color, color.a * 0.45))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 256
	texture.height = 256
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	return texture
