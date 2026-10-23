class_name CombatView
extends Node3D
## The 3D stage, HD-2D (DESIGN.md 7.3): the place's look (StageLook: lit ground, backdrop, sun,
## fog, bloom, colour grading, vignette) with its arena decoration, the combat camera with depth of
## field and cinematic shots, the fighters (party on the left facing right, enemies on the right)
## and short-lived effects (sparks, slashes, ground-wave crests and their floor band, projectiles,
## rock spikes). All art comes from data paths via AssetLoader.

## Effect animation shape: a slash grows to this scale, a spark shrinks to this one.
const SLASH_GROWTH: float = 1.3
const SPARK_END_SCALE: float = 0.4
## Effects drawn for one frame at fight start so the first parry has no compile hitch.
const WARM_UP_ALPHA: float = 0.02
## A missing projectile sheet shows placeholder cells this big.
const PROJECTILE_FALLBACK_PX: int = 20
## The wave's floor band sits just above the ground (and the floor warnings below it).
const BAND_HEIGHT: float = 0.04
## Across the band: transparent edges, a bright middle line.
const BAND_EDGE_ALPHA: float = 0.0
const BAND_MID_ALPHA: float = 1.0

var camera: CombatCamera

var _visuals: CombatVisuals
var _fighters: Dictionary = {}
var _spark_texture: Texture2D
var _slash_texture: Texture2D
var _wave_texture: Texture2D
var _wave_crests: Array[Sprite3D] = []
var _wave_band: MeshInstance3D
var _wave_band_material: StandardMaterial3D
var _rock_texture: Texture2D
## Pooled sprites, shown and placed every frame by the attack runner.
var _projectiles: Array[Sprite3D] = []
var _rocks: Array[Sprite3D] = []
## Projectile textures by path (loaded once per fight).
var _projectile_textures: Dictionary = {}
var _rng := RandomNumberGenerator.new()
## Shifts the room to its phase-two look when a boss or guard rages (DESIGN.md 7.3).
var _mood: ArenaMood
var _look: StageLook


## Builds the stage in `look` (null: the fight list's look from the visuals). Call once before
## adding fighters. `air` is the zone's drifting particles (DESIGN.md 8.12), played thinner in
## the fight; empty: the look's own arena_air.
func build(visuals: CombatVisuals, look: StageLook = null, air: Array[ZoneAmbientData] = []) -> void:
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
	_rock_texture = AssetLoader.texture(visuals.rock_path, Vector2i(16 * maxi(1, visuals.rock_hframes), 24))

	_look = look
	var world_env := StageBuilder.environment(look)
	var sun := StageBuilder.sun(look)
	var vignette := StageBuilder.vignette(look)
	add_child(world_env)
	add_child(sun)
	add_child(StageBuilder.ground(look))
	add_child(StageBuilder.backdrop(look))
	StageBuilder.add_contents(self, look.arena_blocks, look.arena_props, look.arena_lights, [], look)
	_add_air(look, air)
	add_child(vignette)
	var lamps: Array[FlickerLight] = []
	for node: Node in find_children("*", "FlickerLight", false, false):
		lamps.append(node as FlickerLight)
	_mood = ArenaMood.new()
	_mood.name = "ArenaMood"
	add_child(_mood)
	_mood.setup(look, world_env.environment, sun,
			(vignette.get_child(0) as ColorRect).material as ShaderMaterial, lamps)

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
	_build_wave_band()


## The zone's air in the arena: thinned copies of its particles, in a fixed box behind and around
## the fighters (the combat camera glides, so the box does not follow it).
func _add_air(look: StageLook, air: Array[ZoneAmbientData]) -> void:
	var list := air if not air.is_empty() else look.arena_air
	if list.is_empty() or _visuals.fight_air_percent <= 0:
		return
	for data: ZoneAmbientData in PhaseShift.fight_air(list, _visuals.fight_air_percent, _visuals.fight_air_depth_percent):
		var particles := StageBuilder.ambient(data)
		particles.position = _visuals.fight_air_offset + Vector3(0.0, data.height, 0.0)
		add_child(particles)


## The room shifts toward its phase-two look (a boss or guard rages). Does nothing if the look has
## none or it already shifted. Takes longer under the Reduced and Off Flashes settings. `instant`: at
## once and without the burst (a friend who got in after the boss raged, #205, #304).
func shift_to_phase_two(instant: bool = false) -> void:
	if _mood == null or not PhaseShift.has_shift(_look) or _mood.shifted():
		return
	_mood.begin(0 if instant else PhaseShift.duration_ms(_visuals.phase_look_ms, _visuals.phase_look_calm_percent,
			PlayerSettings.flash_mode()))
	if _look.phase_burst != null and not instant:
		var burst := StageBuilder.burst(_look.phase_burst)
		burst.position = _visuals.fight_air_offset + Vector3(0.0, _look.phase_burst.height, 0.0)
		add_child(burst)


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
		view.runs_up = c.runs_up
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
		if not alive and not v.is_party and v.is_dying():
			# A beaten enemy still plays its death and crumbles: snapping it gone would cut that short.
			continue
		v.set_grey(0.0 if alive else 1.0)
		if v.is_party:
			v.set_pose(FighterView.CharPose.IDLE if alive else FighterView.CharPose.DOWN)
			v.set_dissolve(0.0)
		else:
			# An enemy gathering a Doom (card #195) keeps its wind-up crouch.
			var rest := EnemyChoreography.Pose.WINDUP if mirror.is_charging(id) else EnemyChoreography.Pose.IDLE
			v.set_pose(rest if alive else EnemyChoreography.Pose.HURT)
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
	_wave_band.visible = false


## Lays the wave's floor band from `a` to `b` (the front's ends, on the floor) at this strength
## (0 hides it), in `color`.
func set_wave_band(a: Vector3, b: Vector3, strength: float, color: Color) -> void:
	var along := b - a
	along.y = 0.0
	_wave_band.visible = strength > 0.0 and along.length() > 0.001
	if not _wave_band.visible:
		return
	var mid := (a + b) * 0.5
	_wave_band.position = Vector3(mid.x, BAND_HEIGHT, mid.z)
	_wave_band.basis = Basis(Vector3.UP, atan2(-along.z, along.x))
	(_wave_band.mesh as PlaneMesh).size = Vector2(along.length(), _visuals.wave_band_depth)
	_wave_band_material.albedo_color = Color(color.r, color.g, color.b, clampf(strength, 0.0, 1.0))


## Shows one sprite per entry: {path, hframes, frame, pixel_size, pos, alpha, scale}. Entries past
## the list hide; an empty list hides every projectile.
func set_projectiles(list: Array[Dictionary]) -> void:
	while _projectiles.size() < list.size():
		var sprite := _effect_sprite(null, BaseMaterial3D.BILLBOARD_ENABLED)
		sprite.name = "Projectile%d" % _projectiles.size()
		add_child(sprite)
		_projectiles.append(sprite)
	for i: int in _projectiles.size():
		var sprite := _projectiles[i]
		sprite.visible = i < list.size()
		if not sprite.visible:
			continue
		var p: Dictionary = list[i]
		var path := String(p.path)
		if not _projectile_textures.has(path):
			_projectile_textures[path] = AssetLoader.texture(path, Vector2i(PROJECTILE_FALLBACK_PX * maxi(1, int(p.hframes)), PROJECTILE_FALLBACK_PX))
		sprite.texture = _projectile_textures[path]
		sprite.hframes = maxi(1, int(p.hframes))
		sprite.frame = clampi(int(p.frame), 0, sprite.hframes - 1)
		sprite.pixel_size = float(p.pixel_size)
		sprite.position = p.pos
		sprite.scale = Vector3.ONE * float(p.get("scale", 1.0))
		sprite.modulate = Color(1.0, 1.0, 1.0, clampf(float(p.alpha), 0.0, 1.0))


## Shows one rock spike per entry: {pos (feet on the floor), height (0..1 of its full height),
## frame, scale}. An empty list hides every rock.
func set_rocks(list: Array[Dictionary]) -> void:
	var frames := maxi(1, _visuals.rock_hframes)
	while _rocks.size() < list.size():
		var rock := Sprite3D.new()
		rock.name = "Rock%d" % _rocks.size()
		rock.texture = _rock_texture
		rock.hframes = frames
		rock.pixel_size = _visuals.fx_pixel_size * _visuals.rock_scale
		rock.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		rock.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		rock.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		rock.shaded = false
		rock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Feet on the node: scaling y grows the rock out of the floor.
		rock.offset = Vector2(0.0, float(_rock_texture.get_height()) * 0.5)
		add_child(rock)
		_rocks.append(rock)
	for i: int in _rocks.size():
		var rock := _rocks[i]
		var r: Dictionary = list[i] if i < list.size() else {}
		var height := float(r.get("height", 0.0))
		rock.visible = height > 0.0
		if not rock.visible:
			continue
		var size := float(r.get("scale", 1.0))
		rock.position = r.pos
		rock.frame = posmod(int(r.get("frame", 0)), frames)
		rock.scale = Vector3(size, size * height, size)


## Draws every effect once, nearly invisible, so their materials are compiled before the first
## parry. Call at fight start; the effects remove themselves.
func warm_up() -> void:
	var spot := _visuals.camera_target + Vector3(0.0, 0.0, -2.0)
	spawn_sparks(spot, 1, WARM_UP_ALPHA)
	spawn_slash(spot, true, WARM_UP_ALPHA)
	var points: Array[Vector3] = [spot]
	set_wave(points, WARM_UP_ALPHA)
	set_wave_band(spot, spot + Vector3.RIGHT, WARM_UP_ALPHA, Color.WHITE)
	set_rocks([{"pos": spot, "height": WARM_UP_ALPHA}])
	for id: int in _fighters:
		fighter(id).flash(1, Color.WHITE, WARM_UP_ALPHA)
		fighter(id).set_floor_warning(WARM_UP_ALPHA, Color.WHITE)


## Ends the warm-up started by warm_up().
func finish_warm_up() -> void:
	hide_wave()
	set_rocks([])
	for id: int in _fighters:
		fighter(id).set_floor_warning(0.0, Color.WHITE)


func _build_wave_band() -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, BAND_EDGE_ALPHA), Color(1, 1, 1, BAND_MID_ALPHA),
			Color(1, 1, 1, BAND_EDGE_ALPHA)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.5, 0.0)
	texture.fill_to = Vector2(0.5, 1.0)
	_wave_band_material = StandardMaterial3D.new()
	_wave_band_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_wave_band_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_wave_band_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_wave_band_material.albedo_texture = texture
	_wave_band = MeshInstance3D.new()
	_wave_band.name = "WaveBand"
	_wave_band.mesh = PlaneMesh.new()
	_wave_band.material_override = _wave_band_material
	_wave_band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_wave_band.visible = false
	add_child(_wave_band)


## Which stage spot (an index into `positions`) each enemy stands on, by fight slot: the tallest
## monster on the spot farthest from the camera, the smallest on the nearest, so a big body never
## hides a smaller one or its attack (user, phase 19). `heights`: each enemy's enemy_height, by
## slot; all the same height keeps every monster on its own spot. Only the picture changes: ids, targets and
## the rules never look at it.
static func enemy_spots(heights: Array[float], positions: Array[Vector3]) -> Array[int]:
	var count := heights.size()
	var identity: Array[int] = []
	for i: int in count:
		identity.append(i)
	if heights.all(func(h: float) -> bool: return is_equal_approx(h, heights[0])):
		# All the same size: nobody hides anybody, every monster keeps its own spot.
		return identity
	var spots: Array[int] = []
	for i: int in mini(count, positions.size()):
		spots.append(i)
	# Farthest from the camera first (the camera looks from +z).
	spots.sort_custom(func(a: int, b: int) -> bool:
		return positions[a].z < positions[b].z or (positions[a].z == positions[b].z and a < b))
	var order: Array[int] = []
	for i: int in count:
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		return heights[a] > heights[b] or (heights[a] == heights[b] and a < b))
	var result: Array[int] = []
	result.resize(count)
	for k: int in count:
		# More enemies than spots: the extras keep their own slot (the line goes on, _home_for).
		result[order[k]] = spots[k] if k < spots.size() else order[k]
	return result


## How tall a monster's body stands, in world units: from its feet to the highest opaque pixel of
## its idle frame (the sheet's first cell), times its pixel size. A body only hides the monsters
## behind it up to its own height, so the tallest stand at the back. A sheet that cannot be read
## counts its whole cell.
static func enemy_height(e: EnemyData) -> float:
	var cell := e.sprite_clips.frame_size if e.sprite_clips != null else Vector2i(64, 64)
	var rows := cell.y
	var texture := load(e.sprite_path) as Texture2D if ResourceLoader.exists(e.sprite_path) else null
	var image := texture.get_image() if texture != null else null
	if image != null and image.get_width() >= cell.x and image.get_height() >= cell.y:
		if image.is_compressed():
			image.decompress()
		var used := image.get_region(Rect2i(Vector2i.ZERO, cell)).get_used_rect()
		if used.size.y > 0:
			rows = cell.y - used.position.y
	return float(rows) * e.sprite_pixel_size


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
