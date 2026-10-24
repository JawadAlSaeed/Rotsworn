class_name ZoneAutoplay
extends Node
## Test bot for a zone (`-- --autoplay --zone=ID`, DESIGN.md 10): walks the leader along a path
## found by ZonePath (A* over the zone's ground, DESIGN.md 8.5). It first takes the rot seals that
## open the gate. In a run it then picks up the glinting spots, tries each chest once, takes every
## shrine's and wanderer's deal (Main says yes when the party can pay), fights the champions and
## opens their prize chests, and at last heads for the guard at the exit (DESIGN.md 8); other
## enemies are fought only if they catch it. With the guard beaten it walks to the zone's exit and
## leaves (card #241; Main does not ask the bot). It plays like a careful player (card #178): it
## goes for a champion, or hunts a roamer for XP, only while the party is healthy, and uses its
## healing items before it walks into the guard. In practice it fights every roaming enemy. In
## "perfect" mode it stops in reach, turns to an enemy and strikes (FIRST STRIKE); in "miss" and
## "mash" modes it walks into it (a normal start). The fights are played by the combat Autoplay.

## Strike when this share of the strike reach away or closer.
const STRIKE_SHARE: float = 0.7
## Uses things from this share of the pickup reach; shrines and wanderers (solid, so the leader
## stops further away) from OFFER_SHARE.
const PICKUP_SHARE: float = 0.6
const OFFER_SHARE: float = 0.9
## The path is found again this often (enemies move) and when the target changes.
const REPATH_S: float = 1.0
## A waypoint this close counts as reached.
const WAYPOINT_REACHED: float = 0.35
## A target not reached in this long is given up (seconds).
const GIVE_UP_S: float = 40.0
## The path keeps this much room from walls on top of the leader's radius.
const PATH_MARGIN: float = 0.1
## Stuck: moved less than this (world units) in STUCK_CHECK_S while walking: nudge sideways a moment.
const STUCK_DISTANCE: float = 0.15
const STUCK_CHECK_S: float = 0.5
const NUDGE_S: float = 0.4
## Optional roamers (not the guard, not champions) within OPTIONAL_HUNT_RANGE are fought for their
## XP and gold, with the same health rule as a champion (RunAutoplay.is_ready).
const OPTIONAL_HUNT_RANGE: float = 6.0
## Keys of the things it walks to, by kind (index added).
const SPOT_KEY: int = 0
const CHEST_KEY: int = 1000
const SEAL_KEY: int = 2000
const OFFER_KEY: int = 3000
const PRIZE_KEY: int = 4000
const ENEMY_KEY: int = 5000
const EXIT_KEY: int = 6000

var _zone: ZoneController
var _tuning: Tuning
var _strike_first: bool = true
var _run_mode: bool = false
var _grid: ZonePath
var _grid_gate_open: bool = false
var _target: int = -1
var _target_t: float = 0.0
var _path := PackedVector2Array()
var _repath_t: float = 0.0
var _skipped: Array[int] = []
var _check_t: float = 0.0
var _check_pos: Vector2 = Vector2.ZERO
var _nudge_t: float = 0.0
var _nudge_sign: float = 1.0
## Run mode: () -> Vector3i(lowest hero HP percent, party average HP percent, lowest hero level),
## set by Main.
var _party_health: Callable
## Run mode: called once when only the guard is left (Main uses healing items).
var _before_guard: Callable
var _prepared: bool = false


## `run_mode`: a run zone (finds, deals, champions, then the guard); else every enemy is fought.
func setup(zone: ZoneController, tuning: Tuning, mode: String, run_mode: bool = false,
		party_health: Callable = Callable(), before_guard: Callable = Callable()) -> void:
	_zone = zone
	_tuning = tuning
	_run_mode = run_mode
	_party_health = party_health
	_before_guard = before_guard
	_strike_first = mode == CombatOptions.AUTOPLAY_PERFECT
	zone.use_bot = true


func _process(delta: float) -> void:
	if _zone == null or not _zone.is_inside_tree() or _zone.is_frozen() or _zone.is_paused():
		return
	if _grid == null or _grid_gate_open != _zone.is_gate_open():
		var b := _zone.bounds()
		_grid = ZonePath.build(_zone.obstacles(), b[0], b[1], ZoneController.LEADER_RADIUS + PATH_MARGIN)
		_grid_gate_open = _zone.is_gate_open()
		_path = PackedVector2Array()
	var me := _zone.leader_ground()
	var goals := _goals()
	for key: int in _skipped:
		goals.erase(key)
	if goals.is_empty():
		_zone.bot_move = Vector2.ZERO
		return
	if not goals.has(_target):
		_target = _nearest(me, goals)
		_target_t = 0.0
		_path = PackedVector2Array()
		_repath_t = 0.0
	_target_t += delta
	if _target_t > GIVE_UP_S:
		print("ZoneAutoplay: gave up on %d" % _target)
		_skipped.append(_target)
		_target = -1
		return
	var at: Vector2 = goals[_target]
	if _target >= ENEMY_KEY and _target < EXIT_KEY:
		if _strike_first and me.distance_to(at) <= _tuning.explore_strike_reach * STRIKE_SHARE:
			_zone.bot_move = Vector2.ZERO
			_zone.face(at - me)
			_zone.strike()
			return
	elif me.distance_to(at) <= _use_reach():
		_zone.bot_move = Vector2.ZERO
		_zone.pickup()
		if _target == EXIT_KEY:
			# Leaving freezes the zone; until Main takes it, keep pressing.
			return
		# Try each thing once: a chest without a key stays shut, a deal the party cannot pay stays,
		# a find that does not fit a full backpack is left behind.
		_skipped.append(_target)
		return
	_walk_to(me, at, delta)


## Everything worth walking to now, key -> ground spot. Seals come first while the gate is shut.
func _goals() -> Dictionary:
	var goals := {}
	if _zone.is_exit_open():
		# The guard is beaten and everything worth having was taken before it: out.
		goals[EXIT_KEY] = _zone.exit_ground()
		return goals
	if not _zone.is_gate_open():
		_add(goals, SEAL_KEY, _zone.seal_positions())
		if not goals.is_empty():
			return goals
	var enemies := _zone.roamer_spots()
	if not _run_mode:
		_add(goals, ENEMY_KEY, enemies)
		return goals
	_add(goals, SPOT_KEY, _zone.spot_positions())
	_add(goals, CHEST_KEY, _zone.chest_positions())
	_add(goals, OFFER_KEY, _zone.offer_positions())
	_add(goals, PRIZE_KEY, _zone.prize_positions())
	var guard := _zone.guard_index()
	var healthy := _is_healthy()
	if healthy:
		var me := _zone.leader_ground()
		for i: int in enemies:
			if _zone.is_champion(i):
				goals[ENEMY_KEY + i] = enemies[i]
			elif i != guard and me.distance_to(enemies[i] as Vector2) <= OPTIONAL_HUNT_RANGE:
				goals[ENEMY_KEY + i] = enemies[i]
	for key: int in _skipped:
		goals.erase(key)
	if goals.is_empty():
		if not _prepared and _before_guard.is_valid():
			_prepared = true
			_before_guard.call()
		if enemies.has(guard):
			goals[ENEMY_KEY + guard] = enemies[guard]
		else:
			_add(goals, ENEMY_KEY, enemies)
	return goals


## True if the party is fit for an optional fight (always, without a health reader): a careful
## player's habit, RunAutoplay.is_ready.
func _is_healthy() -> bool:
	if not _party_health.is_valid():
		return true
	var health: Vector3i = _party_health.call()
	return RunAutoplay.is_ready(health)


## How close it walks to use the target (not an enemy).
func _use_reach() -> float:
	if _target == EXIT_KEY:
		return _tuning.zone_exit_reach * PICKUP_SHARE
	var share := OFFER_SHARE if _target >= OFFER_KEY and _target < PRIZE_KEY else PICKUP_SHARE
	return _tuning.explore_pickup_radius * share


static func _add(goals: Dictionary, base: int, spots: Dictionary) -> void:
	for i: int in spots:
		goals[base + i] = spots[i]


func _nearest(me: Vector2, goals: Dictionary) -> int:
	var best := -1
	var best_d := INF
	for key: int in goals:
		var d := me.distance_to(goals[key] as Vector2)
		if d < best_d:
			best_d = d
			best = key
	return best


## Follows a path to `at` (found again every REPATH_S), nudging sideways when stuck on a corner.
func _walk_to(me: Vector2, at: Vector2, delta: float) -> void:
	_repath_t -= delta
	if _path.is_empty() or _repath_t <= 0.0:
		_repath_t = REPATH_S
		var near := _use_reach()
		if _target >= ENEMY_KEY and _target < EXIT_KEY:
			near = _tuning.explore_strike_reach * STRIKE_SHARE if _strike_first else _tuning.explore_touch_radius
		_path = _grid.find(me, at, near)
	while _path.size() > 1 and me.distance_to(_path[0]) <= WAYPOINT_REACHED:
		_path.remove_at(0)
	var aim := at if _path.is_empty() else _path[0]
	var move := (aim - me).normalized()
	_check_t += delta
	if _check_t >= STUCK_CHECK_S:
		if me.distance_to(_check_pos) < STUCK_DISTANCE and _nudge_t <= 0.0:
			_nudge_t = NUDGE_S
			_nudge_sign = -_nudge_sign
			_repath_t = 0.0
		_check_t = 0.0
		_check_pos = me
	if _nudge_t > 0.0:
		_nudge_t -= delta
		move = (move + Vector2(-move.y, move.x) * _nudge_sign).normalized()
	_zone.bot_move = move
