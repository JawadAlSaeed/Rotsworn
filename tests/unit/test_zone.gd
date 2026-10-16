extends GutTest
## Exploration (DESIGN 7.4): walking is blocked by props, blocks (turned too) and the bounds; the
## field strike's reach and arc; roaming enemies wander near home, give fair warning before they
## chase, give up and go home; the shipped zones are valid. Uses Tuning.new() for the rules.

const ZONE_DIR := "res://data/zones"
const EPS: float = 0.001

var _tuning := Tuning.new()


func _circle(x: float, z: float, r: float) -> Dictionary:
	return {"centre": Vector2(x, z), "radius": r}


func _box(x: float, z: float, hx: float, hz: float, degrees: float = 0.0) -> Dictionary:
	return {"centre": Vector2(x, z), "half": Vector2(hx, hz), "angle": deg_to_rad(degrees)}


# --- walking ----------------------------------------------------------------------------------

func test_open_ground_moves_freely() -> void:
	var end := ZoneMotion.move(Vector2.ZERO, Vector2(1.0, 0.5), 0.3, [], Vector2(-10, -10), Vector2(10, 10))
	assert_almost_eq(end, Vector2(1.0, 0.5), Vector2(EPS, EPS))


func test_a_prop_blocks_and_you_slide_around_it() -> void:
	var obstacles: Array[Dictionary] = [_circle(2.0, 0.0, 0.5)]
	var end := ZoneMotion.move(Vector2.ZERO, Vector2(4.0, 0.0), 0.3, obstacles, Vector2(-10, -10), Vector2(10, 10))
	assert_lte(end.x, 2.0 - 0.8 + EPS, "stopped in front of the prop")
	var slid := ZoneMotion.move(Vector2(0.0, 0.2), Vector2(4.0, 0.0), 0.3, obstacles, Vector2(-10, -10), Vector2(10, 10))
	assert_gte(slid.distance_to(Vector2(2.0, 0.0)), 0.8 - EPS, "never inside the prop")


func test_a_wall_cannot_be_walked_through_even_in_one_long_step() -> void:
	var obstacles: Array[Dictionary] = [_box(2.0, 0.0, 0.2, 3.0)]
	var end := ZoneMotion.move(Vector2.ZERO, Vector2(6.0, 0.0), 0.3, obstacles, Vector2(-10, -10), Vector2(10, 10))
	assert_lte(end.x, 1.8 - 0.3 + EPS, "the thin wall stops a long step")


func test_a_turned_block_blocks_along_its_turned_length() -> void:
	# 4 long in x, turned 90 degrees: it now runs along z.
	var obstacles: Array[Dictionary] = [_box(0.0, 0.0, 2.0, 0.25, 90.0)]
	var inside_turned := ZoneMotion.push_out(Vector2(0.0, 1.5), 0.3, obstacles[0])
	assert_gte(absf(inside_turned.x), 0.25 + 0.3 - EPS, "pushed out sideways from the turned block")
	var beside_unturned_spot := ZoneMotion.push_out(Vector2(1.5, 0.0), 0.3, obstacles[0])
	assert_almost_eq(beside_unturned_spot, Vector2(1.5, 0.0), Vector2(EPS, EPS), "free where the unturned block would be")


func test_bounds_are_invisible_walls() -> void:
	var end := ZoneMotion.move(Vector2.ZERO, Vector2(50.0, -50.0), 0.3, [], Vector2(-5, -5), Vector2(5, 5))
	assert_almost_eq(end, Vector2(4.7, -4.7), Vector2(EPS, EPS))


func test_strike_reach_and_arc() -> void:
	var facing := Vector2(0.0, -1.0)
	assert_true(ZoneMotion.in_reach(Vector2.ZERO, facing, Vector2(0.0, -1.5), 1.8, 140.0), "straight ahead")
	assert_true(ZoneMotion.in_reach(Vector2.ZERO, facing, Vector2(1.0, -1.0), 1.8, 140.0), "45 degrees off")
	assert_false(ZoneMotion.in_reach(Vector2.ZERO, facing, Vector2(0.0, 1.5), 1.8, 140.0), "behind")
	assert_false(ZoneMotion.in_reach(Vector2.ZERO, facing, Vector2(0.0, -2.5), 1.8, 140.0), "too far")


# --- roaming enemies --------------------------------------------------------------------------

## Runs a brain at a fixed leader spot, moving its walker, for `ms`. Returns {pos, states}.
func _run(brain: RoamerBrain, start: Vector2, leader: Vector2, ms: float, can_notice: bool = true) -> Dictionary:
	var pos := start
	var states: Array[int] = []
	var step_ms := 16.0
	var t := 0.0
	while t < ms:
		var v := brain.step(step_ms, pos, leader, _tuning, can_notice)
		pos += v * step_ms / 1000.0
		states.append(brain.state)
		t += step_ms
	return {"pos": pos, "states": states}


func test_wanders_near_home_when_nobody_is_near() -> void:
	var brain := RoamerBrain.new(Vector2.ZERO, 2.5, 7)
	var far := Vector2(100.0, 100.0)
	var pos := Vector2.ZERO
	var max_dist := 0.0
	var wandered := false
	for i: int in 1500:
		pos += brain.step(16.0, pos, far, _tuning, true) * 0.016
		max_dist = maxf(max_dist, pos.length())
		wandered = wandered or brain.state == RoamerBrain.State.WANDER
	assert_true(wandered, "it walks about")
	assert_lte(max_dist, 2.5 + 0.5, "it stays near home")


func test_notices_then_waits_before_chasing() -> void:
	var brain := RoamerBrain.new(Vector2.ZERO, 2.5, 7)
	var leader := Vector2(_tuning.explore_notice_radius - 0.5, 0.0)
	var first := brain.step(16.0, Vector2.ZERO, leader, _tuning, true)
	assert_eq(brain.state, RoamerBrain.State.NOTICE, "notices the leader in range")
	assert_eq(first, Vector2.ZERO, "and stops (the ! warning)")
	var r := _run(brain, Vector2.ZERO, leader, float(_tuning.explore_notice_ms) - 40.0)
	assert_eq(r.pos, Vector2.ZERO, "does not move during the warning")
	r = _run(brain, Vector2.ZERO, leader, 100.0)
	assert_eq(brain.state, RoamerBrain.State.CHASE, "then chases")
	assert_gt((r.pos as Vector2).x, 0.0, "toward the leader")


func test_does_not_notice_while_calm() -> void:
	var brain := RoamerBrain.new(Vector2.ZERO, 2.5, 7)
	var r := _run(brain, Vector2.ZERO, Vector2(1.0, 0.0), 2000.0, false)
	assert_false((r.states as Array).has(RoamerBrain.State.NOTICE), "just back from a fight: no chase")


func test_gives_up_and_goes_home() -> void:
	var brain := RoamerBrain.new(Vector2.ZERO, 2.5, 7)
	brain.state = RoamerBrain.State.CHASE
	var far := Vector2(_tuning.explore_give_up_radius + 5.0, 0.0)
	var r := _run(brain, Vector2(3.0, 0.0), far, 4000.0)
	assert_true((r.states as Array).has(RoamerBrain.State.RETURN), "gives up past the give-up range")
	assert_lte((r.pos as Vector2).length(), 2.5 + 0.5, "back near home")


func test_chasing_is_slower_than_walking() -> void:
	assert_lt(_tuning.explore_chase_speed, _tuning.explore_walk_speed, "the leader can always get away or turn and strike")


# --- shipped zones ----------------------------------------------------------------------------

func _zones() -> Array[ZoneData]:
	var list: Array[ZoneData] = []
	for file: String in DirAccess.get_files_at(ZONE_DIR):
		if file.ends_with(".tres"):
			list.append(load(ZONE_DIR.path_join(file)) as ZoneData)
	return list


func test_shipped_zones_are_valid() -> void:
	var zones := _zones()
	assert_gt(zones.size(), 0, "phase 3 ships a zone")
	for layout: ZoneData in zones:
		# Long zones are laid out per visit (DESIGN.md 8.5): check one.
		var zone := ZoneAssembler.assemble(layout, 7)
		assert_false(zone.id.is_empty(), "every zone has an id")
		assert_not_null(zone.look, "%s has a look" % zone.id)
		assert_not_null(zone.leader, "%s has a leader" % zone.id)
		assert_gt(zone.enemies.size(), 0, "%s has roaming enemies" % zone.id)
		var obstacles := ZoneMotion.obstacles(zone)
		var start := Vector2(zone.player_start.x, zone.player_start.z)
		assert_eq(ZoneMotion.move(start, Vector2.ZERO, ZoneController.LEADER_RADIUS, obstacles, zone.bounds_min,
				zone.bounds_max), start, "%s: the start spot is free" % zone.id)
		for e: ZoneEnemyData in zone.enemies:
			assert_not_null(e.encounter, "%s: every roaming enemy has a fight" % zone.id)
			if e.encounter == null:
				continue
			assert_gt(e.encounter.enemies.size(), 0, "%s: %s has enemies" % [zone.id, e.encounter.id])
			var home := Vector2(e.position.x, e.position.z)
			assert_eq(ZoneMotion.move(home, Vector2.ZERO, ZoneController.ROAMER_RADIUS, obstacles, zone.bounds_min,
					zone.bounds_max), home, "%s: %s starts on free ground" % [zone.id, e.encounter.id])
			assert_gt(home.distance_to(start), _tuning.explore_notice_radius,
					"%s: %s does not start next to the leader" % [zone.id, e.encounter.id])


# --- camera shots (DESIGN 7.3) ----------------------------------------------------------------

func test_camera_shots_frame_their_subjects() -> void:
	var v := CombatVisuals.new()
	var base := CameraShots.base(v)
	assert_eq(base.pos, v.camera_position)
	var actor := Vector3(-3.0, 0.0, 1.0)
	var turn := CameraShots.turn(v, actor)
	assert_lt((turn.target as Vector3).distance_to(Vector3(actor.x, v.camera_target.y, actor.z)),
			(base.target as Vector3).distance_to(Vector3(actor.x, v.camera_target.y, actor.z)), "a turn drifts toward the actor")
	assert_almost_eq(((turn.target as Vector3) - (turn.pos as Vector3)).normalized(),
			((base.target as Vector3) - (base.pos as Vector3)).normalized(), Vector3(EPS, EPS, EPS), "and keeps the 3/4 angle")
	var strike := CameraShots.strike(v, Vector3(-2.0, 0.0, 0.0), Vector3(2.0, 0.0, 0.0), false)
	assert_almost_eq(strike.target as Vector3, Vector3(0.0, CameraShots.CHEST_HEIGHT, 0.0), Vector3(EPS, EPS, EPS),
			"a strike looks at the middle of striker and target")
	var orbit := CameraShots.orbit(strike, 90.0)
	assert_almost_eq((orbit.pos as Vector3).distance_to(strike.target as Vector3),
			(strike.pos as Vector3).distance_to(strike.target as Vector3), EPS, "an orbit keeps its distance")
