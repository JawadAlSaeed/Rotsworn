class_name ZoneAutoplay
extends Node
## Test bot for a zone (`-- --autoplay --zone=ID`, DESIGN.md 10): walks the leader to the nearest
## roaming enemy. In "perfect" mode it stops in reach, turns to it and strikes (FIRST STRIKE); in
## "miss" and "mash" modes it walks into it (a normal start). The fights themselves are played by
## the combat Autoplay. Walls are handled by sliding sideways for a moment when stuck. In a run it
## heads for the guard at the exit (DESIGN.md 8) and fights others only if they catch it.

## Strike when this share of the strike reach away or closer.
const STRIKE_SHARE: float = 0.7
## Stuck: moved less than this (world units) in STUCK_CHECK_S while walking.
const STUCK_DISTANCE: float = 0.15
const STUCK_CHECK_S: float = 0.5
## Then slide sideways for this long.
const SLIDE_S: float = 0.7

var _zone: ZoneController
var _tuning: Tuning
var _strike_first: bool = true
var _guard_only: bool = false
var _check_t: float = 0.0
var _check_pos: Vector2 = Vector2.ZERO
var _slide_t: float = 0.0
var _slide_sign: float = 1.0


func setup(zone: ZoneController, tuning: Tuning, mode: String, guard_only: bool = false) -> void:
	_zone = zone
	_tuning = tuning
	_guard_only = guard_only
	_strike_first = mode == CombatOptions.AUTOPLAY_PERFECT
	zone.use_bot = true


func _process(delta: float) -> void:
	if _zone == null or not _zone.is_inside_tree() or _zone.is_frozen():
		return
	var me := _zone.leader_ground()
	var spots := _zone.roamer_spots()
	var guard := _zone.guard_index()
	if _guard_only and spots.has(guard):
		spots = {guard: spots[guard]}
	if spots.is_empty():
		_zone.bot_move = Vector2.ZERO
		return
	var target := Vector2.ZERO
	var best := INF
	for i: int in spots:
		var d := me.distance_to(spots[i] as Vector2)
		if d < best:
			best = d
			target = spots[i]
	var to := target - me
	if _strike_first and best <= _tuning.explore_strike_reach * STRIKE_SHARE:
		_zone.bot_move = Vector2.ZERO
		_zone.face(to)
		_zone.strike()
		return
	var move := to.normalized()
	_check_t += delta
	if _check_t >= STUCK_CHECK_S:
		if me.distance_to(_check_pos) < STUCK_DISTANCE and _slide_t <= 0.0:
			_slide_t = SLIDE_S
			_slide_sign = -_slide_sign
		_check_t = 0.0
		_check_pos = me
	if _slide_t > 0.0:
		_slide_t -= delta
		move = (move + Vector2(-move.y, move.x) * 1.6 * _slide_sign).normalized()
	_zone.bot_move = move
