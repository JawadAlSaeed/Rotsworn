class_name CombatView
extends Node3D
## The 3D stage, HD-2D (DESIGN.md 7.3): the place's look (StageLook: lit ground, backdrop, sun,
## fog, bloom, colour grading, vignette) with its arena decoration, the combat camera with depth of
## field and cinematic shots, the fighters (party on the left facing right, enemies on the right)
## and short-lived effects (sparks, slashes, ground-wave crests). All art comes from data paths via
## AssetLoader.

## Effect animation shape: a slash grows to this scale, a spark shrinks to this one.
const SLASH_GROWTH: float = 1.3
const SPARK_END_SCALE: float = 0.4
## Effects drawn for one frame at fight start so the first parry has no compile hitch.
const WARM_UP_ALPHA: float = 0.02

var camera: CombatCamera

var _visuals: CombatVisuals
var _fighters: Dictionary = {}
var _spark_texture: Texture2D
var _slash_texture: Texture2D
var _wave_texture: Texture2D
var _wave_crests: Array[Sprite3D] = []
var _rng := RandomNumberGenerator.new()


## Builds the stage in `look` (null: the fight list's look from the visuals). Call once before
## adding fighters.
func build(visuals: CombatVisuals, look: StageLook = null) -> void:
	_visuals = visuals
	if look == null:
		look = visuals.stage_look
	if look == null:
		push_warning("CombatView: no stage look, using the StageLook defaults")
		look = StageLook.new()
	_rng.randomize()
	_spark_texture = AssetLoader.texture(visuals.spark_path, Vector2i(16, 16))
	_slash_texture = AssetLoader.texture(visuals.slash_path, Vector2i(32, 32))
	_wave_texture = AssetLoader.texture(visuals.shockwave_path, Vector2i(64, 16))

	add_child(StageBuilder.environment(look))
	add_child(StageBuilder.sun(look))
	add_child(StageBuilder.ground(look))
	add_child(StageBuilder.backdrop(look))
	StageBuilder.add_contents(self, look.arena_blocks, look.arena_props, look.arena_lights)
	add_child(StageBuilder.vignette(look))

	camera = CombatCamera.new()
	camera.name = "Camera"
	camera.setup(visuals)
	camera.attributes = StageBuilder.camera_attributes(visuals.dof_far_enabled, visuals.dof_far_distance,
			visuals.dof_far_transition, visuals.dof_near_enabled, visuals.dof_near_distance,
			visuals.dof_near_transition, visuals.dof_amount)
	add_child(camera)
	camera.current = true

	for i: int in visuals.wave_crest_count:
		var crest := _effect_sprite(_wave_texture, BaseMaterial3D.BILLBOARD_FIXED_Y)
		crest.name = "WaveCrest%d" % i
		crest.offset = Vector2(0.0, float(_wave_texture.get_height()) * 0.5)
		crest.visible = false
		add_child(crest)
		_wave_crests.append(crest)


## Adds the view for one fighter (from a combat_started fighter entry and its data resource).
func add_fighter(id: int, is_party: bool, slot: int, data: Resource) -> FighterView:
	var view := FighterView.new()
	view.name = "Fighter%d" % id
	view.position = _home_for(is_party, slot)
	add_child(view)
	if is_party:
		var c := data as CharacterData
		view.setup(id, true, c.sprite_path, c.sprite_hframes, Vector2i(32, 48), c.sprite_pixel_size,
				not _visuals.party_art_faces_right, _visuals, c.sprite_clips)
	else:
		var e := data as EnemyData
		view.setup(id, false, e.sprite_path, e.sprite_hframes, Vector2i(64, 64), e.sprite_pixel_size,
				not _visuals.enemy_art_faces_left, _visuals, e.sprite_clips, e.idle_cycle_percent)
	_fighters[id] = view
	return view


func fighter(id: int) -> FighterView:
	return _fighters.get(id) as FighterView


## Home spot (feet) of a fighter.
func home_of(id: int) -> Vector3:
	var v := fighter(id)
	return v.position if v != null else Vector3.ZERO


## Where an enemy lunge connects with these party targets (their centre, in front of them).
func contact_point(target_ids: Array[int]) -> Vector3:
	if target_ids.is_empty():
		return Vector3.ZERO
	var sum := Vector3.ZERO
	for id: int in target_ids:
		sum += home_of(id)
	return sum / float(target_ids.size()) + Vector3(_visuals.contact_gap, 0.0, 0.0)


## The middle of every fighter's home spot (feet).
func arena_centre() -> Vector3:
	if _fighters.is_empty():
		return Vector3.ZERO
	var sum := Vector3.ZERO
	for id: int in _fighters:
		sum += home_of(id)
	return sum / float(_fighters.size())


## Where a party member stands to strike this enemy.
func strike_point(enemy_id: int) -> Vector3:
	return home_of(enemy_id) - Vector3(_visuals.strike_gap, 0.0, 0.0)


## Where `id` stands relative to a strike point shared by all of `actors` (a team counter, the
## team ultimate): it keeps team_strike_spread of its offset from the middle of their homes, so
## every striker stays visible instead of overlapping.
func team_spread_offset(id: int, actors: Array[int]) -> Vector3:
	var centre := Vector3.ZERO
	for actor: int in actors:
		centre += home_of(actor)
	centre /= float(maxi(1, actors.size()))
	return spread_offset(home_of(id), centre, _visuals.team_strike_spread)


## The team spread formula: `share` of a home's offset from the formation's middle.
static func spread_offset(home: Vector3, formation_centre: Vector3, share: float) -> Vector3:
	return (home - formation_centre) * share


## Screen position (HUD canvas pixels) of a world point.
func screen_position(world: Vector3) -> Vector2:
	if camera == null:
		return Vector2.ZERO
	return camera.unproject_position(world)


## Sets every fighter's down/greyed look from the mirror (outside enemy attacks).
func sync_alive(mirror: CombatMirror) -> void:
	for id: int in _fighters:
		var v := fighter(id)
		var alive := mirror.is_alive(id)
		if v.is_party and bool(mirror.fighter(id).get("escaped", false)):
			# A hero who ran is gone from the stage (DESIGN.md 2.13); let a running escape finish.
			if not v.is_dissolving():
				v.set_dissolve(1.0)
			continue
		v.set_grey(0.0 if alive else 1.0)
		if v.is_party:
			v.set_pose(FighterView.CharPose.IDLE if alive else FighterView.CharPose.DOWN)
			v.set_dissolve(0.0)
		else:
			v.set_pose(EnemyChoreography.Pose.IDLE if alive else EnemyChoreography.Pose.HURT)
			# A beaten enemy has crumbled away (card #38).
			v.set_dissolve(0.0 if alive else 1.0)


## A burst of sparks flying out from `at`, tinted `color`.
func spawn_sparks(at: Vector3, count: int, alpha: float = 1.0, color: Color = Color.WHITE) -> void:
	for i: int in count:
		var spark := _effect_sprite(_spark_texture, BaseMaterial3D.BILLBOARD_ENABLED)
		spark.position = at
		spark.modulate = Color(color.r, color.g, color.b, alpha)
		add_child(spark)
		var angle := _rng.randf_range(0.0, TAU)
		var dist := _visuals.spark_spread * _rng.randf_range(0.5, 1.0)
		var dir := Vector3(cos(angle), sin(angle) * 0.8 + 0.2, _rng.randf_range(-0.3, 0.3)).normalized()
		var seconds := float(_visuals.spark_ms) / 1000.0
		var tween := spark.create_tween().set_parallel(true)
		tween.tween_property(spark, "position", at + dir * dist, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(spark, "modulate:a", 0.0, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(spark, "scale", Vector3.ONE * SPARK_END_SCALE, seconds)
		tween.chain().tween_callback(spark.queue_free)


## A slash arc at `at`, mirrored for strikes going left, appearing after `delay_ms`. Returns its
## tween (set_speed_scale(0) on it freezes the slash for a hit-stop).
func spawn_slash(at: Vector3, facing_right: bool = true, alpha: float = 1.0, delay_ms: int = 0) -> Tween:
	var slash := _effect_sprite(_slash_texture, BaseMaterial3D.BILLBOARD_ENABLED)
	slash.position = at
	slash.flip_h = not facing_right
	slash.scale = Vector3.ONE * _visuals.slash_scale
	slash.modulate = Color(1.0, 1.0, 1.0, alpha)
	slash.visible = delay_ms <= 0
	add_child(slash)
	var seconds := float(_visuals.slash_ms) / 1000.0
	var tween := slash.create_tween()
	if delay_ms > 0:
		tween.tween_interval(float(delay_ms) / 1000.0)
		tween.tween_callback(slash.show)
	tween.tween_property(slash, "scale", Vector3.ONE * _visuals.slash_scale * SLASH_GROWTH, seconds)
	tween.parallel().tween_property(slash, "modulate:a", 0.0, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(slash.queue_free)
	return tween


## Places the ground-wave crests (one per point) at this opacity.
func set_wave(points: Array[Vector3], alpha: float) -> void:
	for i: int in _wave_crests.size():
		var crest := _wave_crests[i]
		if i < points.size():
			crest.visible = true
			crest.position = points[i]
			crest.modulate = Color(1.0, 1.0, 1.0, clampf(alpha, 0.0, 1.0))
		else:
			crest.visible = false


func hide_wave() -> void:
	for crest: Sprite3D in _wave_crests:
		crest.visible = false


## Draws every effect once, nearly invisible, so their materials are compiled before the first
## parry. Call at fight start; the effects remove themselves.
func warm_up() -> void:
	var spot := _visuals.camera_target + Vector3(0.0, 0.0, -2.0)
	spawn_sparks(spot, 1, WARM_UP_ALPHA)
	spawn_slash(spot, true, WARM_UP_ALPHA)
	var points: Array[Vector3] = [spot]
	set_wave(points, WARM_UP_ALPHA)
	for id: int in _fighters:
		fighter(id).flash(1, Color.WHITE, WARM_UP_ALPHA)
		fighter(id).set_floor_warning(WARM_UP_ALPHA, Color.WHITE)


## Ends the warm-up started by warm_up().
func finish_warm_up() -> void:
	hide_wave()
	for id: int in _fighters:
		fighter(id).set_floor_warning(0.0, Color.WHITE)


func _home_for(is_party: bool, slot: int) -> Vector3:
	var list: Array[Vector3] = _visuals.party_positions if is_party else _visuals.enemy_positions
	if list.is_empty():
		return Vector3(-3.0 if is_party else 3.0, 0.0, 0.0)
	if slot < list.size():
		return list[slot]
	# More fighters than authored spots: continue the line of the last two.
	var last := list[list.size() - 1]
	var step := Vector3(0.0, 0.0, 1.3) if list.size() < 2 else last - list[list.size() - 2]
	return last + step * float(slot - list.size() + 1)


func _effect_sprite(texture: Texture2D, billboard: BaseMaterial3D.BillboardMode) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = texture
	s.pixel_size = _visuals.fx_pixel_size
	s.billboard = billboard
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.no_depth_test = true
	s.render_priority = 1
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return s
