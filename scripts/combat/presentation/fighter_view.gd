class_name FighterView
extends Node3D
## One fighter on the stage: a billboard sprite, a shadow blob, a floor warning (ground hits), and
## the flash / glow / crouch / greyed-out looks. The node itself stays at the fighter's home spot;
## `body_offset` moves the body (dashes, lunges, dodges, jumps, hops) and the shadow follows on
## the floor.
##
## Frames (DESIGN.md 5.3 and 5.5). Without SpriteClips (or when the texture does not match them)
## the sheet is one row and a pose is a frame index, exactly as before phase 10. With clips the
## sheet is a grid: row 0 still holds the poses in the same order, and named clips play on a
## ClipPlayer: a base (a key cell, a cell the caller drives from attack or skill time, or a
## real-time loop) and one timed override with a priority. Every request shows its frame at once.
## Clip names fall back through ClipNames to the caller's legacy pose.

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

## Override priorities (ClipPlayer): short reactions < big reactions < death and victory.
const PRIO_REACT: int = ClipPlayer.PRIO_REACT
const PRIO_BIG: int = ClipPlayer.PRIO_BIG
const PRIO_FINAL: int = ClipPlayer.PRIO_FINAL

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

## Where the turn spotlight puts the body, on top of body_offset (card #154): the acting hero a
## step forward, the others a step away. Animate it only through set_stage().
var stage_offset: Vector3 = Vector3.ZERO:
	set = _set_stage_offset

var _sprite: Sprite3D
var _shadow: Sprite3D
var _warning: MeshInstance3D
var _warning_material: StandardMaterial3D
var _material: ShaderMaterial
var _visuals: CombatVisuals
## The sheet's grid and clips; null for a legacy one-row sheet.
var _clips: SpriteClips
var _player := ClipPlayer.new()
var _hframes: int = 1
var _vframes: int = 1
var _cell_count: int = 1
var _idle_percent: int = 100
## Zone facing ("", "_front" or "_back"): clips with this suffix are tried first.
var _facing_suffix: String = ""
var _frame_height_px: float = 48.0
## Opaque part of the first frame, in pixels measured up from the feet (bottom of the frame).
var _visible_top_px: float = 48.0
var _visible_bottom_px: float = 0.0
var _pixel_size: float = 0.045
var _head_factor: float = 1.0
var _flash_until_us: int = 0
var _flash_length_us: int = 1
var _flash_strength: float = 1.0
## The one tween allowed to move the body (see move_body).
var _move_tween: Tween
var _stage_tween: Tween
var _tint: Color = Color.WHITE
var _dissolve_tween: Tween
## Sheets already warned about (their size does not match their clips).
static var _warned_layout: Dictionary = {}


## Builds the sprite and shadow. `hframes` and `frame_size` describe the legacy one-row sheet
## (`frame_size` only fakes a missing file). With `clips` whose grid matches the texture, the sheet
## is that grid. `idle_percent` scales an enemy's idle loop (EnemyData.idle_cycle_percent).
func setup(id: int, party: bool, sheet_path: String, hframes: int, frame_size: Vector2i,
		pixel_size: float, flip: bool, visuals: CombatVisuals, clips: SpriteClips = null,
		idle_percent: int = 100) -> void:
	fighter_id = id
	is_party = party
	_visuals = visuals
	_idle_percent = maxi(1, idle_percent)
	_hframes = maxi(1, hframes)
	_vframes = 1
	_pixel_size = pixel_size
	_head_factor = visuals.head_height_factor
	var fallback_size := Vector2i(frame_size.x * _hframes, frame_size.y) if clips == null else clips.sheet_size()
	var texture := AssetLoader.texture(sheet_path, fallback_size)
	_clips = _matching_clips(clips, texture, sheet_path)
	_frame_height_px = float(texture.get_height())
	var body_width_px := float(texture.get_width()) / float(_hframes)
	if _clips != null:
		_hframes = _clips.hframes
		_vframes = _clips.vframes
		_frame_height_px = float(_clips.frame_size.y)
		body_width_px = float(_clips.body_width_px)
	_cell_count = _hframes * _vframes
	_measure_visible(texture)

	_sprite = Sprite3D.new()
	_sprite.name = "Body"
	_sprite.texture = texture
	_sprite.hframes = _hframes
	_sprite.vframes = _vframes
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
	# The dissolve's top-first bias works per cell of a grid sheet.
	_material.set_shader_parameter("sheet_rows", float(_vframes))
	_sprite.material_override = _material
	add_child(_sprite)

	_shadow = Sprite3D.new()
	_shadow.name = "Shadow"
	_shadow.texture = AssetLoader.texture(visuals.shadow_path, Vector2i(32, 12))
	var frame_width := body_width_px * pixel_size
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
	_sprite.frame = cell_at(float(now) / 1000.0)
	var flash := 0.0
	if now < _flash_until_us:
		flash = _flash_strength * float(_flash_until_us - now) / float(_flash_length_us)
	_material.set_shader_parameter("flash_amount", clampf(flash, 0.0, 1.0))


## The clip clock: real time in milliseconds (Time.get_ticks_usec, like flash()).
static func now_ms() -> float:
	return float(Time.get_ticks_usec()) / 1000.0


## The sheet cell shown at `time_ms` (now_ms() clock), clamped to the sheet.
func cell_at(time_ms: float) -> int:
	return clampi(_player.cell_at(time_ms), 0, _cell_count - 1)


## The base pose, shown when no timed pose plays. With clips, idle, ready and down (heroes) and
## idle (enemies) loop their clip in real time when it has more than one cell, each fighter out of
## step with the others; every other pose shows its row-0 key cell, as before.
func set_pose(pose: int) -> void:
	var cells := _loop_cells(pose)
	if cells.size() > 1:
		var period := _loop_period_ms(pose)
		_player.set_base_loop(cells, period, ClipMath.phase_for(fighter_id, period))
	else:
		_player.set_base_cell(pose)
	_show()


## Shows `pose` for `ms` milliseconds (real time), then goes back to the base pose. With clips the
## pose's clip plays spread over `ms`; without one, the pose's single frame, as before.
func play_pose(pose: int, ms: int) -> void:
	var cells := _cells(ClipNames.pose_name(pose, is_party))
	if cells.is_empty():
		cells = PackedInt32Array([pose])
	_player.play(cells, now_ms(), float(ms), PRIO_REACT)
	_show()


## Drops the timed pose if its priority is below `below` (default: any), back to the base pose.
func clear_timed_pose(below: int = PRIO_FINAL + 1) -> void:
	_player.cancel_below(below)
	_show()


## Base: cell `index` of `clip` (a caller driving it from attack or skill time calls this every
## frame). A missing clip shows set_pose(fallback_pose) instead (nothing when it is -1).
func show_clip(clip: String, index: int, fallback_pose: int) -> void:
	var cells := _cells(clip)
	if cells.is_empty():
		if fallback_pose >= 0:
			set_pose(fallback_pose)
		return
	_player.set_base_cell(cells[clampi(index, 0, cells.size() - 1)])
	_show()


## Base: `clip` at progress `u` (0..1, its cells shared evenly); otherwise like show_clip.
func show_clip_u(clip: String, u: float, fallback_pose: int) -> void:
	show_clip(clip, ClipMath.stretch(clip_count(clip), u), fallback_pose)


## Base: loops `clip` in real time, one cycle every `period_ms`, out of step with other fighters.
## With `delay_ms` it starts from its first cell that much later and the current base shows until
## then (call it once, not every frame). A missing clip shows set_pose(fallback_pose) (nothing
## when it is -1).
func set_loop(clip: String, period_ms: int, fallback_pose: int, delay_ms: int = 0) -> void:
	var cells := _cells(clip)
	if cells.is_empty():
		if fallback_pose >= 0:
			set_pose(fallback_pose)
		return
	var period := float(maxi(1, period_ms))
	if delay_ms > 0:
		_player.set_base_loop(cells, period, 0.0, now_ms() + float(delay_ms))
	else:
		_player.set_base_loop(cells, period, ClipMath.phase_for(fighter_id, period))
	_show()


## Override: plays `clip` over the base for `ms` (real time), its cells spread evenly, at priority
## `prio` (PRIO_REACT, PRIO_BIG or PRIO_FINAL), starting after `delay_ms`. `hold` keeps its last
## cell until cleared; `cycle_ms` above 0 loops it for the whole length instead. A missing clip
## plays the single cell `fallback_pose` (nothing when it is -1). False when refused (a higher
## priority one is pending or playing) or when there was nothing to play.
func play(clip: String, ms: int, prio: int, fallback_pose: int = -1, delay_ms: int = 0,
		hold: bool = false, cycle_ms: int = 0) -> bool:
	var cells := _cells(clip)
	if cells.is_empty():
		if fallback_pose < 0:
			return false
		cells = PackedInt32Array([fallback_pose])
	var played := _player.play(cells, now_ms(), float(ms), prio, float(delay_ms), hold, float(cycle_ms))
	_show()
	return played


## Cells `clip` plays after the fallbacks (0: nothing fits, or a sheet without clips).
func clip_count(clip: String) -> int:
	return _cells(clip).size()


func has_clip(clip: String) -> bool:
	return clip_count(clip) > 0


## True while a timed pose of at least `min_prio` is pending or playing.
func is_busy(min_prio: int = PRIO_REACT) -> bool:
	return _player.busy(now_ms(), min_prio)


## True while it crumbles away or plays its death (or victory): a final look nothing should snap.
func is_dying() -> bool:
	return is_dissolving() or is_busy(PRIO_FINAL)


## Zone facing: clips named with this suffix ("_front", "_back"; "" for side views) are tried first.
func set_facing_suffix(suffix: String) -> void:
	_facing_suffix = suffix


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


## Hops the body to `to` over `seconds` along an arc `height` high (world units), replacing any
## movement still in progress, like move_body. 0 seconds snaps.
func hop_body(to: Vector3, seconds: float, height: float) -> void:
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	_move_tween = null
	if seconds <= 0.0:
		body_offset = to
		return
	_move_tween = create_tween()
	_move_tween.tween_method(_hop_step.bind(body_offset, to, height), 0.0, 1.0, seconds)


## Where a hop from `from` to `to`, `height` high, is at progress `u` (0..1).
static func hop_point(from: Vector3, to: Vector3, u: float, height: float) -> Vector3:
	return from.lerp(to, u) + Vector3(0.0, sin(PI * u) * height, 0.0)


func set_body_offset(value: Vector3) -> void:
	body_offset = value
	_place_body()


func _set_stage_offset(value: Vector3) -> void:
	stage_offset = value
	_place_body()


func _place_body() -> void:
	if _sprite == null:
		return
	var at := body_offset + stage_offset
	_sprite.position = at
	_shadow.position = Vector3(at.x, SHADOW_HEIGHT, at.z)
	_warning.position = Vector3(at.x, WARNING_HEIGHT, at.z)
	var lift := clampf(body_offset.y / SHADOW_FADE_HEIGHT, 0.0, 1.0)
	_shadow.scale = Vector3.ONE * lerpf(1.0, SHADOW_MIN_SCALE, lift)


## The turn spotlight (card #154): glides to `offset` (see stage_offset) and `tint` over `seconds`.
func set_stage(offset: Vector3, tint: Color, seconds: float) -> void:
	if _stage_tween != null and _stage_tween.is_valid():
		_stage_tween.kill()
	if seconds <= 0.0:
		stage_offset = offset
		set_tint(tint)
		return
	_stage_tween = create_tween().set_parallel(true)
	_stage_tween.tween_property(self, "stage_offset", offset, seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_stage_tween.tween_method(set_tint, _tint, tint, seconds)


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


## A beaten enemy crumbles away over `ms` (its shadow fades with it), its edge glowing in
## `edge_color`, starting after `delay_ms`. ms 0 makes it gone at once (after the delay);
## set_dissolve(0) brings it back. is_dissolving() is true from the call on, delay included.
func dissolve(ms: int, edge_color: Color, delay_ms: int = 0) -> void:
	_material.set_shader_parameter("dissolve_edge_color", edge_color)
	if _dissolve_tween != null and _dissolve_tween.is_valid():
		_dissolve_tween.kill()
	if ms <= 0 and delay_ms <= 0:
		set_dissolve(1.0)
		return
	_dissolve_tween = create_tween()
	if delay_ms > 0:
		_dissolve_tween.tween_interval(float(delay_ms) / 1000.0)
	if ms <= 0:
		_dissolve_tween.tween_callback(_apply_dissolve.bind(1.0))
	else:
		_dissolve_tween.tween_method(_apply_dissolve, 0.0, 1.0, float(ms) / 1000.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


## True while a dissolve() is still playing (or waiting for its delay).
func is_dissolving() -> bool:
	return _dissolve_tween != null and _dissolve_tween.is_valid() and _dissolve_tween.is_running()


## How much of the body has crumbled away (0 whole, 1 gone).
func set_dissolve(amount: float) -> void:
	if amount <= 0.0 and _dissolve_tween != null and _dissolve_tween.is_valid():
		_dissolve_tween.kill()
	_apply_dissolve(amount)


## Greyed-out look for a downed fighter (0..1).
func set_grey(amount: float) -> void:
	_material.set_shader_parameter("grey_amount", clampf(amount, 0.0, 1.0))


## Mirrors the art (a walker turning to face the other way).
func set_flip(flip: bool) -> void:
	_sprite.flip_h = flip


func set_tint(color: Color) -> void:
	_tint = color
	_material.set_shader_parameter("tint", color)


## Height of the sprite in world units.
func sprite_height() -> float:
	return _frame_height_px * _pixel_size


## Where the body is now (feet), in world space.
func body_position() -> Vector3:
	return global_position + body_offset + stage_offset


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


## The dissolve look, without touching the tween (the dissolve tween itself drives this).
func _apply_dissolve(amount: float) -> void:
	_material.set_shader_parameter("dissolve", clampf(amount, 0.0, 1.0))
	_shadow.modulate = Color(1.0, 1.0, 1.0, 1.0 - clampf(amount, 0.0, 1.0))


func _hop_step(u: float, from: Vector3, to: Vector3, height: float) -> void:
	body_offset = hop_point(from, to, u, height)


## Writes the frame for now at once, so a request never waits for the next _process.
func _show() -> void:
	if _sprite != null:
		_sprite.frame = cell_at(now_ms())


## `clips` if `texture` is exactly their grid; otherwise null (the legacy one-row sheet), with one
## warning per sheet when there were clips.
func _matching_clips(clips: SpriteClips, texture: Texture2D, sheet_path: String) -> SpriteClips:
	if clips == null or clips.matches(texture):
		return clips
	if not _warned_layout.has(sheet_path):
		_warned_layout[sheet_path] = true
		push_warning("FighterView: '%s' is %dx%d but its clips expect %s; showing it as one row of %d frames"
				% [sheet_path, texture.get_width(), texture.get_height(), clips.sheet_size(), _hframes])
	return null


## The cells `clip` plays on this sheet after the fallbacks (empty without clips).
func _cells(clip: String) -> PackedInt32Array:
	return ClipNames.cells(_clips, clip, _facing_suffix)


## The clip of a looping pose (idle, ready, down); empty for any other pose or without clips.
func _loop_cells(pose: int) -> PackedInt32Array:
	if _clips == null:
		return PackedInt32Array()
	var clip := ClipNames.pose_name(pose, is_party)
	if not ClipNames.LOOPS.has(clip):
		return PackedInt32Array()
	return _cells(clip)


## One cycle of a looping pose, in ms.
func _loop_period_ms(pose: int) -> float:
	if not is_party:
		return float(maxi(1, CombatMath.percent(_visuals.enemy_idle_cycle_ms, _idle_percent)))
	match pose:
		CharPose.READY:
			return float(_visuals.ready_cycle_ms)
		CharPose.DOWN:
			return float(_visuals.down_cycle_ms)
	return float(_visuals.idle_cycle_ms)


## Finds the opaque rows of frame 0 (cell 0 of a grid), so popups sit on the art and not on empty
## frame space. Falls back to the whole frame if the image cannot be read.
@warning_ignore("integer_division")
func _measure_visible(texture: Texture2D) -> void:
	_visible_top_px = _frame_height_px
	_visible_bottom_px = 0.0
	var image := texture.get_image()
	if image == null or image.is_empty():
		return
	if image.is_compressed() and image.decompress() != OK:
		return
	var frame_w := image.get_width() / _hframes
	var frame_h := image.get_height()
	if _clips != null:
		frame_w = _clips.frame_size.x
		frame_h = _clips.frame_size.y
	var used := image.get_region(Rect2i(0, 0, frame_w, frame_h)).get_used_rect()
	if used.size.y <= 0:
		return
	_visible_top_px = _frame_height_px - float(used.position.y)
	_visible_bottom_px = _frame_height_px - float(used.end.y)
