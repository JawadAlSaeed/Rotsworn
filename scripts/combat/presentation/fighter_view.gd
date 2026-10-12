class_name FighterView
extends Node3D
## One fighter on the stage: a billboard sprite whose frame is the pose, a shadow blob, a floor
## warning (ground hits), and the flash / glow / crouch / greyed-out looks. The node itself stays at the fighter's home spot;
## `body_offset` moves the body (dashes, lunges, dodges, jumps) and the shadow follows on the floor.
## Poses are frame indices of the one-row sheet (DESIGN.md 5.3).

## Frames of a character sheet.
enum CharPose {
	IDLE,
	READY,
	PARRY,
	DODGE,
	JUMP,
	HURT,
	STRIKE,
	DOWN,
}

const SHADER := preload("res://scripts/combat/presentation/fighter_sprite.gdshader")
const SHADOW_HEIGHT := 0.02
## The shadow shrinks to this scale when the body is this high (world units) or higher.
const SHADOW_MIN_SCALE := 0.55
const SHADOW_FADE_HEIGHT := 1.6
## The floor warning sits just above the shadow.
const WARNING_HEIGHT := 0.03
## Floor warning gradient: opacity at the centre, at WARNING_RIM_AT of the radius, and at the rim.
const WARNING_CENTRE_ALPHA := 0.35
const WARNING_RIM_AT := 0.75
const WARNING_RIM_ALPHA := 1.0

## Combatant id this view shows.
var fighter_id: int = -1
var is_party: bool = true
## Body position relative to home (the node's position). Animate it only through move_body().
var body_offset: Vector3 = Vector3.ZERO:
	set = set_body_offset

var _sprite: Sprite3D
var _shadow: Sprite3D
var _warning: MeshInstance3D
var _warning_material: StandardMaterial3D
var _material: ShaderMaterial
var _hframes: int = 1
var _frame_height_px: float = 48.0
## Opaque part of the first frame, in pixels measured up from the feet (bottom of the frame).
var _visible_top_px: float = 48.0
var _visible_bottom_px: float = 0.0
var _pixel_size: float = 0.045
var _head_factor: float = 1.0
var _base_pose: int = 0
var _override_pose: int = -1
var _override_until_us: int = 0
var _flash_until_us: int = 0
var _flash_length_us: int = 1
var _flash_strength: float = 1.0
## The one tween allowed to move the body (see move_body).
var _move_tween: Tween


## Builds the sprite and shadow. `fallback_size` is the sheet size to fake if the art is missing.
func setup(id: int, party: bool, sheet_path: String, hframes: int, frame_size: Vector2i,
		pixel_size: float, flip: bool, visuals: CombatVisuals) -> void:
	fighter_id = id
	is_party = party
	_hframes = maxi(1, hframes)
	_pixel_size = pixel_size
	_head_factor = visuals.head_height_factor
	var texture := AssetLoader.texture(sheet_path, Vector2i(frame_size.x * _hframes, frame_size.y))
	_frame_height_px = float(texture.get_height())
	_measure_visible(texture)

	_sprite = Sprite3D.new()
	_sprite.name = "Body"
	_sprite.texture = texture
	_sprite.hframes = _hframes
	_sprite.pixel_size = pixel_size
	_sprite.centered = true
	_sprite.offset = Vector2(0.0, _frame_height_px * 0.5)
	_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_sprite.flip_h = flip
	_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("sprite_texture", texture)
	_material.set_shader_parameter("glow_color", visuals.windup_glow_color)
	_material.set_shader_parameter("glow_strength", visuals.windup_glow_strength)
	_sprite.material_override = _material
	add_child(_sprite)

	_shadow = Sprite3D.new()
	_shadow.name = "Shadow"
	_shadow.texture = AssetLoader.texture(visuals.shadow_path, Vector2i(32, 12))
	var frame_width := float(texture.get_width()) / float(_hframes) * pixel_size
	_shadow.pixel_size = frame_width * visuals.shadow_width_factor / float(maxi(1, _shadow.texture.get_width()))
	_shadow.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_shadow.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow.position = Vector3(0.0, SHADOW_HEIGHT, 0.0)
	add_child(_shadow)
	_build_floor_warning(visuals.floor_warning_size)
	set_pose(0)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var pose := _base_pose
	if _override_pose >= 0:
		if now < _override_until_us:
			pose = _override_pose
		else:
			_override_pose = -1
	_sprite.frame = clampi(pose, 0, _hframes - 1)
	var flash := 0.0
	if now < _flash_until_us:
		flash = _flash_strength * float(_flash_until_us - now) / float(_flash_length_us)
	_material.set_shader_parameter("flash_amount", clampf(flash, 0.0, 1.0))


## The pose shown when no timed pose is playing.
func set_pose(frame: int) -> void:
	_base_pose = frame
	if _sprite != null and _override_pose < 0:
		_sprite.frame = clampi(frame, 0, _hframes - 1)


## Shows `frame` for `ms` milliseconds (real time), then goes back to the base pose.
func play_pose(frame: int, ms: int) -> void:
	_override_pose = frame
	_override_until_us = Time.get_ticks_usec() + ms * 1000
	_sprite.frame = clampi(frame, 0, _hframes - 1)


func clear_timed_pose() -> void:
	_override_pose = -1


## Moves the body to `to` (relative to home) over `seconds`, replacing any movement still in
## progress, so two movements never fight over the body. 0 seconds snaps (and just stops any
## movement when `to` is the current offset).
func move_body(to: Vector3, seconds: float, trans: Tween.TransitionType = Tween.TRANS_LINEAR,
		ease: Tween.EaseType = Tween.EASE_IN_OUT) -> void:
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	_move_tween = null
	if seconds <= 0.0:
		body_offset = to
		return
	_move_tween = create_tween()
	_move_tween.tween_property(self, "body_offset", to, seconds).set_trans(trans).set_ease(ease)


func set_body_offset(value: Vector3) -> void:
	body_offset = value
	if _sprite == null:
		return
	_sprite.position = value
	_shadow.position = Vector3(value.x, SHADOW_HEIGHT, value.z)
	_warning.position = Vector3(value.x, WARNING_HEIGHT, value.z)
	var lift := clampf(value.y / SHADOW_FADE_HEIGHT, 0.0, 1.0)
	_shadow.scale = Vector3.ONE * lerpf(1.0, SHADOW_MIN_SCALE, lift)


## White (or coloured) flash that fades over `ms` milliseconds of real time.
func flash(ms: int, color: Color = Color.WHITE, strength: float = 1.0) -> void:
	_flash_length_us = maxi(1, ms * 1000)
	_flash_until_us = Time.get_ticks_usec() + _flash_length_us
	_flash_strength = strength
	_material.set_shader_parameter("flash_color", color)
	_material.set_shader_parameter("flash_amount", clampf(strength, 0.0, 1.0))


## Wind-up glow strength (0..1).
func set_glow(amount: float) -> void:
	_material.set_shader_parameter("glow_amount", clampf(amount, 0.0, 1.0))


func set_glow_color(color: Color) -> void:
	_material.set_shader_parameter("glow_color", color)


## Wind-up crouch: the body gets `amount` (0..1) shorter and as much wider, around its feet.
func set_squash(amount: float) -> void:
	var a := clampf(amount, 0.0, 0.9)
	_sprite.scale = Vector3(1.0 + a, 1.0 - a, 1.0)


## A glowing disc on the floor under the body (a ground hit is coming): `strength` 0 hides it.
func set_floor_warning(strength: float, color: Color) -> void:
	_warning.visible = strength > 0.0
	if _warning.visible:
		_warning_material.albedo_color = Color(color.r, color.g, color.b, clampf(strength, 0.0, 1.0))


## Greyed-out look for a downed fighter (0..1).
func set_grey(amount: float) -> void:
	_material.set_shader_parameter("grey_amount", clampf(amount, 0.0, 1.0))


func set_tint(color: Color) -> void:
	_material.set_shader_parameter("tint", color)


## Height of the sprite in world units.
func sprite_height() -> float:
	return _frame_height_px * _pixel_size


## Where the body is now (feet), in world space.
func body_position() -> Vector3:
	return global_position + body_offset


## Height of the visible art (opaque pixels of the first frame) in world units.
func visible_height() -> float:
	return _visible_top_px * _pixel_size


## Above the head, for popups and icons.
func head_position() -> Vector3:
	return body_position() + Vector3(0.0, visible_height() * _head_factor, 0.0)


## Middle of the visible body, for sparks, slashes and rings.
func centre_position() -> Vector3:
	return body_position() + Vector3(0.0, (_visible_top_px + _visible_bottom_px) * 0.5 * _pixel_size, 0.0)


func _build_floor_warning(diameter: float) -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, WARNING_RIM_AT, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, WARNING_CENTRE_ALPHA), Color(1, 1, 1, WARNING_RIM_ALPHA), Color(1, 1, 1, 0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	_warning_material = StandardMaterial3D.new()
	_warning_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_warning_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_warning_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_warning_material.albedo_texture = texture
	var plane := PlaneMesh.new()
	plane.size = Vector2(diameter, diameter)
	_warning = MeshInstance3D.new()
	_warning.name = "FloorWarning"
	_warning.mesh = plane
	_warning.material_override = _warning_material
	_warning.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_warning.position = Vector3(0.0, WARNING_HEIGHT, 0.0)
	_warning.visible = false
	add_child(_warning)


## Finds the opaque rows of frame 0, so popups sit on the art and not on empty frame space.
## Falls back to the whole frame if the image cannot be read.
func _measure_visible(texture: Texture2D) -> void:
	_visible_top_px = _frame_height_px
	_visible_bottom_px = 0.0
	var image := texture.get_image()
	if image == null or image.is_empty():
		return
	if image.is_compressed() and image.decompress() != OK:
		return
	var frame_w := image.get_width() / _hframes
	var used := image.get_region(Rect2i(0, 0, frame_w, image.get_height())).get_used_rect()
	if used.size.y <= 0:
		return
	_visible_top_px = _frame_height_px - float(used.position.y)
	_visible_bottom_px = _frame_height_px - float(used.end.y)
