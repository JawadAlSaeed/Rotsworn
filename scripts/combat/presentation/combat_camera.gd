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
var _trauma := CameraTrauma.new()
var _last_us: int = 0
var _punch_amount: float = 0.0
var _punch_until_us: int = 0
var _punch_length_us: int = 1
## A fight's intro sweep (card #335): from, to, and its real-time span.
var _sweep_from: Dictionary = {}
var _sweep_to: Dictionary = {}
var _sweep_start_us: int = 0
var _sweep_length_us: int = 0


func setup(visuals: CombatVisuals) -> void:
	_visuals = visuals
	_goal = CameraShots.base(visuals)
	_pos = _goal.pos
	_target = _goal.target
	_fov = float(_goal.fov)
	_trauma.configure(visuals.shake_hz, visuals.shake_decay_per_s, visuals.shake_max_offset,
			visuals.shake_max_roll_deg)
	_last_us = Time.get_ticks_usec()
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


## A fight's intro (card #335): the camera is at `from` at once and slides to `to` over `ms`, eased
## in and out, then stays there until the next shot. Off (not cinematic): the base shot, still.
func sweep(from: Dictionary, to: Dictionary, ms: int) -> void:
	if not cinematic:
		reset_shot()
		return
	_go(from)
	settle()
	_sweep_from = from
	_sweep_to = to
	_sweep_start_us = Time.get_ticks_usec()
	_sweep_length_us = maxi(1, ms * 1000)


## True while an intro sweep slides.
func is_sweeping() -> bool:
	return not _sweep_to.is_empty()


## Jumps straight to the current goal (used when an enemy attack's clock starts).
func settle() -> void:
	var goal := _orbited_goal()
	_pos = goal.pos
	_target = goal.target
	_fov = float(goal.fov)


func _go(goal: Dictionary, orbit_speed: float = 0.0) -> void:
	# Any other shot ends a sweep.
	_sweep_to = {}
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
	if not _sweep_to.is_empty():
		var p := clampf(float(Time.get_ticks_usec() - _sweep_start_us) / float(_sweep_length_us), 0.0, 1.0)
		_goal = CameraShots.blend(_sweep_from, _sweep_to, smoothstep(0.0, 1.0, p))
		if p >= 1.0:
			_sweep_to = {}
	var goal := _orbited_goal()
	var k := 1.0 - exp(-delta * 1000.0 / float(maxi(1, _visuals.shot_glide_ms)))
	_pos = _pos.lerp(goal.pos, k)
	_target = _target.lerp(goal.target, k)
	_fov = lerpf(_fov, float(goal.fov), k)
	var now := Time.get_ticks_usec()
	# Trauma drains on real time and the wave reads the clock, so the shake looks the same at any
	# frame rate and still runs through a hit-stop freeze.
	_trauma.step(float(now - _last_us) / 1000000.0)
	_last_us = now
	var shake_scale := float(PlayerSettings.screen_shake_percent()) / 100.0
	var time_s := float(now) / 1000000.0
	var offset := _trauma.offset(time_s, shake_scale)
	if now < _punch_until_us:
		var p := float(_punch_until_us - now) / float(_punch_length_us)
		offset += (_target - _pos).normalized() * _punch_amount * p * p
	_apply(offset, _trauma.roll(time_s, shake_scale))


func _apply(offset: Vector3, roll: float = 0.0) -> void:
	fov = _fov
	var pos := _pos + offset
	if pos.is_equal_approx(_target):
		return
	var basis := Basis.looking_at(_target - _pos, Vector3.UP)
	if roll != 0.0:
		basis = basis * Basis(Vector3.BACK, roll)
	transform = Transform3D(basis, pos)


## Adds trauma (0 to 1, clamped) to the shake: impacts add up, so a string of parries builds and a
## big moment is clearly bigger than a graze (CameraTrauma, card #179). The player's screen shake
## setting scales the result (0: none, card #112).
func add_trauma(amount: float) -> void:
	_trauma.add(amount)


## Older call shape: `strength` is a trauma amount now; the length is set by the shared decay rate
## (shake_decay_per_s), so `ms` is only kept so existing callers keep working.
func shake(strength: float, _ms: int = 0) -> void:
	add_trauma(strength)


## Moves toward the target by `amount` world units and eases back over `ms` milliseconds.
func punch(amount: float, ms: int) -> void:
	_punch_amount = amount
	_punch_length_us = maxi(1, ms * 1000)
	_punch_until_us = Time.get_ticks_usec() + _punch_length_us
