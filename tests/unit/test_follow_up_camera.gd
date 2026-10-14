extends GutTest
## Card #49: a skill with follow-ups is framed so the striker, every ally pressing and the target stay in
## the follow-up safe area (clear of the banner and party panels). For every striker and enemy
## slot of the default stage layout, the allies' feet and heads and the enemy's are projected by a
## real Camera3D (in a 1920x1080 SubViewport) and must land inside the safe area.

const SCREEN := Vector2i(1920, 1080)
## Pixels of slack for float rounding between the pure maths and the camera.
const SLACK_PX: float = 2.0
## Character art: 48 px tall frames at the default pixel size; enemy: the tallest shipped one
## (frame height from its sheet, one-row or grid, times its pixel size).
const CHARACTER_HEIGHT: float = 48.0 * 0.045 * 1.05
const ENEMY_DIR := "res://data/enemies"

var _visuals: CombatVisuals
var _viewport: SubViewport
var _camera: Camera3D


func before_each() -> void:
	_visuals = load("res://data/presentation/combat_visuals.tres") as CombatVisuals
	_viewport = SubViewport.new()
	_viewport.size = SCREEN
	add_child_autofree(_viewport)
	_camera = Camera3D.new()
	_viewport.add_child(_camera)


func _enemy_height() -> float:
	var tallest := 0.0
	for file: String in DirAccess.get_files_at(ENEMY_DIR):
		if file.ends_with(".tres"):
			var e := load(ENEMY_DIR.path_join(file)) as EnemyData
			# Each enemy's frame height comes from its sheet (bigger monsters get bigger frames); a
			# grid sheet (sprite clips) has many rows, so read one cell, as FighterView shows it.
			var fallback := Vector2i(64 * e.sprite_hframes, 64) if e.sprite_clips == null else e.sprite_clips.sheet_size()
			var texture := AssetLoader.texture(e.sprite_path, fallback)
			var frame_px := float(SpriteClips.frame_px(e.sprite_clips, texture, e.sprite_hframes).y)
			tallest = maxf(tallest, frame_px * e.sprite_pixel_size * 1.05)
	return tallest


## Feet and head of the striker (where it waits), every follow-up ally (stepped forward like the
## runner) and the enemy in `enemy_slot`.
func _points(striker: int, enemy_slot: int) -> Array[Vector3]:
	var enemy := _visuals.enemy_positions[enemy_slot]
	var strike_point := enemy - Vector3(_visuals.strike_gap, 0.0, 0.0)
	var points: Array[Vector3] = []
	for slot: int in _visuals.party_positions.size():
		var home := _visuals.party_positions[slot]
		var step := (strike_point - home) * _visuals.skill_approach_share
		# The striker waits part of the way in; follow-up allies step half as far.
		var feet := home + (step if slot == striker else step * SkillSequenceRunner.FOLLOW_UP_STEP_SHARE)
		points.append(feet)
		points.append(feet + Vector3(0.0, CHARACTER_HEIGHT, 0.0))
	points.append(enemy)
	points.append(enemy + Vector3(0.0, _enemy_height(), 0.0))
	return points


func test_every_follow_up_stays_in_the_safe_area() -> void:
	var safe := _visuals.follow_up_safe_area
	var rect := Rect2(Vector2(safe.position) * Vector2(SCREEN), Vector2(safe.size) * Vector2(SCREEN)).grow(SLACK_PX)
	var aspect := float(SCREEN.x) / float(SCREEN.y)
	var cases := 0
	for striker: int in _visuals.party_positions.size():
		for enemy_slot: int in _visuals.enemy_positions.size():
			var points := _points(striker, enemy_slot)
			var shot := CameraShots.frame(_visuals, points, aspect, safe)
			_camera.fov = float(shot.fov)
			_camera.transform = Transform3D(Basis.looking_at((shot.target as Vector3) - (shot.pos as Vector3), Vector3.UP), shot.pos as Vector3)
			for p: Vector3 in points:
				assert_false(_camera.is_position_behind(p), "striker %d enemy %d: %s in front of the camera" % [striker, enemy_slot, p])
				var at := _camera.unproject_position(p)
				assert_true(rect.has_point(at), "striker %d enemy %d: %s shows at %s, outside %s" % [striker, enemy_slot, p, at, rect])
			cases += 1
	assert_eq(cases, 9, "three strikers by three enemy slots")


func test_framing_keeps_the_base_angle_and_pulls_back_only_as_needed() -> void:
	var aspect := float(SCREEN.x) / float(SCREEN.y)
	var points := _points(0, 0)
	var shot := CameraShots.frame(_visuals, points, aspect, _visuals.follow_up_safe_area)
	var base := CameraShots.base(_visuals)
	assert_almost_eq(((shot.target as Vector3) - (shot.pos as Vector3)).normalized(),
			((base.target as Vector3) - (base.pos as Vector3)).normalized(), Vector3(0.001, 0.001, 0.001), "same 3/4 angle")
	var distance := (shot.pos as Vector3).distance_to(shot.target as Vector3)
	var closer := CameraShots.shot((shot.target as Vector3) + ((shot.pos as Vector3) - (shot.target as Vector3)) * 0.9,
			shot.target as Vector3, float(shot.fov))
	assert_false(CameraShots.fits(closer, points, aspect, _visuals.follow_up_safe_area), "any closer and someone would leave the safe area")
	assert_lt(distance, CameraShots.FRAME_MAX_DISTANCE, "it found a fit")
