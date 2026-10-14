class_name ZoneAutoplay
extends Node
## Test bot for a zone (`-- --autoplay --zone=ID`, DESIGN.md 10): walks the leader to the nearest
## roaming enemy. In "perfect" mode it stops in reach, turns to it and strikes (FIRST STRIKE); in
## "miss" and "mash" modes it walks into it (a normal start). The fights themselves are played by
## the combat Autoplay. Walls are handled by sliding sideways for a moment when stuck. In a run it
## first picks up the zone's glinting spots and tries its chest (DESIGN.md 8.1), then heads for the guard at the exit
## (DESIGN.md 8) and fights others only if they catch it.

## Strike when this share of the strike reach away or closer.
const STRIKE_SHARE: float = 0.7
## Stuck: moved less than this (world units) in STUCK_CHECK_S while walking.
const STUCK_DISTANCE: float = 0.15
const STUCK_CHECK_S: float = 0.5
## Then slide sideways for this long (times how often in a row it got stuck).
const SLIDE_S: float = 0.7
## After this many slides one way without getting free, it tries the other way.
const MAX_SLIDES_ONE_WAY: int = 4
## Free again: moved at least this far (world units) in one check while walking.
const FREE_DISTANCE: float = 1.0
## A glinting spot not reached in this long is given up (seconds).
const SPOT_GIVE_UP_S: float = 25.0
## Picks up from this share of the pickup reach.
const PICKUP_SHARE: float = 0.6
## Chests share the list of places to visit with spots, from this key on.
const CHEST_KEY: int = 1000

var _zone: ZoneController
var _tuning: Tuning
var _strike_first: bool = true
var _guard_only: bool = false
var _check_t: float = 0.0
var _check_pos: Vector2 = Vector2.ZERO
var _slide_t: float = 0.0
var _slide_sign: float = 1.0
var _stuck_count: int = 0
## The spot it walks to now (-1: none), how long it has tried, and the spots it gave up on.
var _spot: int = -1
var _spot_t: float = 0.0
var _skipped: Array[int] = []


func setup(zone: ZoneController, tuning: Tuning, mode: String, guard_only: bool = false) -> void:
	_zone = zone
	_tuning = tuning
	_guard_only = guard_only
	_strike_first = mode == CombatOptions.AUTOPLAY_PERFECT
	zone.use_bot = true


func _process(delta: float) -> void:
	if _zone == null or not _zone.is_inside_tree() or _zone.is_frozen() or _zone.is_paused():
		return
	var me := _zone.leader_ground()
	var spots := _zone.roamer_spots()
	var guard := _zone.guard_index()
	if _guard_only and spots.has(guard):
		spots = {guard: spots[guard]}
	if _guard_only and _walk_to_find(me, delta):
		return
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
	_steer(me, to, delta)


## Walks to the nearest glinting spot or closed chest not tried or given up on and uses it (a
## chest is tried once: without a key it stays locked). False when none are left.
func _walk_to_find(me: Vector2, delta: float) -> bool:
	var finds := {}
	var spots := _zone.spot_positions()
	for i: int in spots:
		finds[i] = spots[i]
	var chests := _zone.chest_positions()
	for i: int in chests:
		finds[CHEST_KEY + i] = chests[i]
	for key: int in _skipped:
		finds.erase(key)
	if finds.is_empty():
		return false
	if not finds.has(_spot):
		_spot = -1
		var best := INF
		for key: int in finds:
			var d := me.distance_to(finds[key] as Vector2)
			if d < best:
				best = d
				_spot = key
		_spot_t = 0.0
	_spot_t += delta
	if _spot_t > SPOT_GIVE_UP_S:
		_skipped.append(_spot)
		return true
	var to := (finds[_spot] as Vector2) - me
	if to.length() <= _tuning.explore_pickup_radius * PICKUP_SHARE:
		_zone.bot_move = Vector2.ZERO
		_zone.pickup()
		if _spot >= CHEST_KEY:
			_skipped.append(_spot)
		return true
	_steer(me, to, delta)
	return true


## Walks toward `to` (sliding along walls when stuck).
func _steer(me: Vector2, to: Vector2, delta: float) -> void:
	var move := to.normalized()
	_check_t += delta
	if _check_t >= STUCK_CHECK_S:
		var moved := me.distance_to(_check_pos)
		if moved < STUCK_DISTANCE and _slide_t <= 0.0:
			# Keep sliding the same way, longer each time, to get round a long wall; only a
			# dead end (stuck again and again) turns it the other way.
			_stuck_count += 1
			if _stuck_count > MAX_SLIDES_ONE_WAY:
				_stuck_count = 1
				_slide_sign = -_slide_sign
			_slide_t = SLIDE_S * float(_stuck_count)
		elif moved > FREE_DISTANCE and _slide_t <= 0.0:
			_stuck_count = 0
		_check_t = 0.0
		_check_pos = me
	if _slide_t > 0.0:
		_slide_t -= delta
		move = (move + Vector2(-move.y, move.x) * 1.6 * _slide_sign).normalized()
	_zone.bot_move = move
