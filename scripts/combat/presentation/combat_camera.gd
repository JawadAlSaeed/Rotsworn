class_name CombatCamera
extends Camera3D
## The combat camera (DESIGN.md 7.3): it glides to the shot for each moment of the fight
## (CameraShots: a party turn, a strike or skill, the ultimate, an enemy attack, a counter, the
## end), with screen shake and punch-in on top. With `cinematic` off it stays on the 3/4 base
## shot. Runs on real (presentation) time, not attack time, so a hit-stop freeze still shakes.
## An enemy attack's shot is settled before its first motion (settle()), so the view holds still
## while you defend.

## Turn cinematic shots on or off (F1 > V); off returns to the base shot.
var cinematic: bool = true:
	set = set_cinematic

var _visuals: CombatVisuals
var _goal: Dictionary = {}
var _orbit_speed: float = 0.0
var _orbit_degrees: float = 0.0
var _pos: Vector3 = Vector3.ZERO
var _target: Vector3 = Vector3.ZERO
var _fov: float = 40.0
var _shake_strength: float = 0.0
var _shake_until_us: int = 0
var _shake_length_us: int = 1
var _punch_amount: float = 0.0
var _punch_until_us: int = 0
var _punch_length_us: int = 1
var _rng := RandomNumberGenerator.new()


func setup(visuals: CombatVisuals) -> void:
	_visuals = visuals
	_goal = CameraShots.base(visuals)
	_pos = _goal.pos
	_target = _goal.target
	_fov = float(_goal.fov)
	_rng.randomize()
	_apply(Vector3.ZERO)


func set_cinematic(value: bool) -> void:
	cinematic = value
	if not value and _visuals != null:
		reset_shot()


## Back to the 3/4 base shot.
func reset_shot() -> void:
	_go(CameraShots.base(_visuals))


## A party member's turn (their feet).
func shot_turn(actor: Vector3) -> void:
	_go(CameraShots.turn(_visuals, actor))


## A strike or skill from `from` to `to` (feet); the ultimate circles slowly.
func shot_strike(from: Vector3, to: Vector3, ultimate: bool = false) -> void:
	_go(CameraShots.strike(_visuals, from, to, ultimate), _visuals.ultimate_orbit_degrees_per_s if ultimate else 0.0)


## An enemy attack from `enemy` onto the contact point (feet).
func shot_attack(enemy: Vector3, contact: Vector3) -> void:
	_go(CameraShots.attack(_visuals, enemy, contact))


## Pulls back to fit every point (follow-up allies and their target) in the follow-up safe area.
func shot_frame(points: Array[Vector3]) -> void:
	var size := get_viewport().get_visible_rect().size
	_go(CameraShots.frame(_visuals, points, size.x / maxf(1.0, size.y), _visuals.follow_up_safe_area))


func shot_counter(enemy: Vector3) -> void:
	_go(CameraShots.counter(_visuals, enemy))


## Victory or defeat: a slow circle around the middle of the arena.
func shot_end(centre: Vector3) -> void:
	_go(CameraShots.ending(_visuals, centre), _visuals.end_orbit_degrees_per_s)


## Jumps straight to the current goal (used when an enemy attack's clock starts).
func settle() -> void:
	var goal := _orbited_goal()
	_pos = goal.pos
	_target = goal.target
	_fov = float(goal.fov)


func _go(goal: Dictionary, orbit_speed: float = 0.0) -> void:
	if not cinematic and _visuals != null:
		goal = CameraShots.base(_visuals)
		orbit_speed = 0.0
	_goal = goal
	_orbit_speed = orbit_speed
	_orbit_degrees = 0.0


func _orbited_goal() -> Dictionary:
	if _orbit_degrees == 0.0:
		return _goal
	return CameraShots.orbit(_goal, _orbit_degrees)


func _process(delta: float) -> void:
	if _visuals == null:
		return
	_orbit_degrees += _orbit_speed * delta
	var goal := _orbited_goal()
	var k := 1.0 - exp(-delta * 1000.0 / float(maxi(1, _visuals.shot_glide_ms)))
	_pos = _pos.lerp(goal.pos, k)
	_target = _target.lerp(goal.target, k)
	_fov = lerpf(_fov, float(goal.fov), k)
	var now := Time.get_ticks_usec()
	var offset := Vector3.ZERO
	if now < _shake_until_us:
		var s := _shake_strength * float(_shake_until_us - now) / float(_shake_length_us)
		offset += Vector3(_rng.randf_range(-s, s), _rng.randf_range(-s, s), 0.0)
	if now < _punch_until_us:
		var p := float(_punch_until_us - now) / float(_punch_length_us)
		offset += (_target - _pos).normalized() * _punch_amount * p * p
	_apply(offset)


func _apply(offset: Vector3) -> void:
	fov = _fov
	var pos := _pos + offset
	if pos.is_equal_approx(_target):
		return
	transform = Transform3D(Basis.looking_at(_target - _pos, Vector3.UP), pos)


## Shakes by up to `strength` world units, fading over `ms` milliseconds. Stronger shakes win.
func shake(strength: float, ms: int) -> void:
	var now := Time.get_ticks_usec()
	var current := 0.0
	if now < _shake_until_us:
		current = _shake_strength * float(_shake_until_us - now) / float(_shake_length_us)
	if strength < current:
		return
	_shake_strength = strength
	_shake_length_us = maxi(1, ms * 1000)
	_shake_until_us = now + _shake_length_us


## Moves toward the target by `amount` world units and eases back over `ms` milliseconds.
func punch(amount: float, ms: int) -> void:
	_punch_amount = amount
	_punch_length_us = maxi(1, ms * 1000)
	_punch_until_us = Time.get_ticks_usec() + _punch_length_us
