class_name RoamerBrain
extends RefCounted
## What a roaming enemy does (DESIGN.md 7.4), as a pure state machine on the ground plane: it
## pauses and wanders near its home; when the leader comes within notice range it stops and shows
## "!" for notice ms (fair warning), then chases until the leader is beyond give-up range, then
## walks home. Randomness comes from its own seeded generator. Unit-tested.

enum State {
	PAUSE,
	WANDER,
	NOTICE,
	CHASE,
	RETURN,
}

## Close enough to a wander spot or home (world units).
const ARRIVE: float = 0.25
## A wander walk gives up after this share longer than it should take (it may be blocked).
const WANDER_SLACK: float = 1.5
const WANDER_SLACK_MS: float = 600.0

var state: State = State.PAUSE
var home: Vector2 = Vector2.ZERO
var wander_radius: float = 2.5
var goal: Vector2 = Vector2.ZERO
## Milliseconds left in the current pause, notice or wander walk.
var timer_ms: float = 0.0

var _rng := RandomNumberGenerator.new()


func _init(p_home: Vector2, p_wander_radius: float, rng_seed: int) -> void:
	home = p_home
	goal = p_home
	wander_radius = p_wander_radius
	_rng.seed = rng_seed
	timer_ms = 0.0


## Back to a calm pause at home (after the party loses a fight).
func reset() -> void:
	state = State.PAUSE
	goal = home
	timer_ms = 0.0


## Advances `dt_ms` and returns the velocity to walk with (world units per second). `can_notice`
## is false while the leader may not be chased (just back from a fight).
func step(dt_ms: float, pos: Vector2, leader: Vector2, tuning: Tuning, can_notice: bool) -> Vector2:
	var to_leader := pos.distance_to(leader)
	if can_notice and state in [State.PAUSE, State.WANDER, State.RETURN] and to_leader <= tuning.explore_notice_radius:
		state = State.NOTICE
		timer_ms = float(tuning.explore_notice_ms)
	match state:
		State.NOTICE:
			timer_ms -= dt_ms
			if timer_ms <= 0.0:
				state = State.CHASE
			return Vector2.ZERO
		State.CHASE:
			if not can_notice or to_leader > tuning.explore_give_up_radius:
				state = State.RETURN
				return _toward(pos, home, tuning.explore_wander_speed)
			return _toward(pos, leader, tuning.explore_chase_speed)
		State.RETURN:
			if pos.distance_to(home) <= ARRIVE:
				_pause(tuning)
				return Vector2.ZERO
			return _toward(pos, home, tuning.explore_wander_speed)
		State.WANDER:
			timer_ms -= dt_ms
			if pos.distance_to(goal) <= ARRIVE or timer_ms <= 0.0:
				_pause(tuning)
				return Vector2.ZERO
			return _toward(pos, goal, tuning.explore_wander_speed)
	# PAUSE
	timer_ms -= dt_ms
	if timer_ms <= 0.0:
		var angle := _rng.randf() * TAU
		goal = home + Vector2.RIGHT.rotated(angle) * wander_radius * sqrt(_rng.randf())
		var walk_ms := pos.distance_to(goal) / maxf(0.01, tuning.explore_wander_speed) * 1000.0
		timer_ms = walk_ms * WANDER_SLACK + WANDER_SLACK_MS
		state = State.WANDER
	return Vector2.ZERO


func _pause(tuning: Tuning) -> void:
	state = State.PAUSE
	timer_ms = float(_rng.randi_range(tuning.explore_pause_min_ms, maxi(tuning.explore_pause_min_ms, tuning.explore_pause_max_ms)))


static func _toward(from: Vector2, to: Vector2, speed: float) -> Vector2:
	var d := to - from
	if d.length() < 0.0001:
		return Vector2.ZERO
	return d.normalized() * speed
