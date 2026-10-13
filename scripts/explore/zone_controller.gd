class_name ZoneController
extends Node
## One explorable zone (DESIGN.md 7.4): builds the place from its ZoneData in the HD-2D look
## (StageBuilder), lets the leader walk around (ZoneMotion), runs the roaming enemies (RoamerBrain),
## and starts a fight when the leader strikes an enemy first (FIRST STRIKE) or an enemy touches
## the leader (normal start). Main takes it out of the tree during the fight and calls resume()
## when the party comes back. Walking is presentation, not combat: real time, floats, no engine.
## In a run (DESIGN.md 8) the zone is cleared by beating its guard at the exit; the other roaming
## enemies are optional. Outside a run (practice) every enemy must be beaten.
## In co-op only player 1 walks and strikes (DESIGN.md 9.1); the others watch.
## Online (DESIGN.md 9.2) the host's zone is the real one: it sends net_snapshot() several times a
## second. On the other machines the zone is `remote`: nothing moves by itself and no fight starts
## here; the walkers glide to the host's positions (apply_snapshot) and a fight starts when the
## host says so (begin_remote).

## A fight is starting: roaming enemy `index` (its encounter), with this opening.
signal encounter_started(index: int, opening: CombatSetup.Opening)
## The zone is cleared: the guard is beaten (run), or every roaming enemy (practice).
signal cleared

## Walker sizes on the ground (world units).
const LEADER_RADIUS: float = 0.35
const ROAMER_RADIUS: float = 0.45
## The strike's slash is drawn at this height (world units).
const SLASH_HEIGHT: float = 1.0
## A stick or key push smaller than this is ignored.
const MOVE_DEADZONE: float = 0.15
## Pauses before a fight starts, so the hit (or the touch) reads (seconds).
const FIRST_STRIKE_PAUSE_S: float = 0.35
const TOUCH_PAUSE_S: float = 0.15
## Name tags show over roaming enemies this many notice radii away or closer.
const TAG_RANGE_SHARE: float = 1.6

## Online, the pause menu opens over a zone that goes on: the leader stands still meanwhile.
var input_held: bool = false
## Autoplay (ZoneAutoplay) drives these instead of the input when `use_bot` is set.
var use_bot: bool = false
var bot_move: Vector2 = Vector2.ZERO

var _zone: ZoneData
var _tuning: Tuning
var _visuals: CombatVisuals
var _explore: ExploreVisuals
var _world: Node3D
var _camera: Camera3D
var _hud: ZoneHud
var _leader: FighterView
var _leader_pos: Vector2 = Vector2.ZERO
var _facing: Vector2 = Vector2(0.0, -1.0)
var _walk_phase: float = 0.0
## One per roaming enemy: {data, view, brain, pos: Vector2, defeated: bool, phase: float}.
var _roamers: Array[Dictionary] = []
var _obstacles: Array[Dictionary] = []
var _frozen: bool = false
var _time_ms: float = 0.0
var _strike_until_ms: float = 0.0
var _grace_until_ms: float = 0.0
var _fight_index: int = -1
var _cam_pos: Vector3 = Vector3.ZERO
var _slash_texture: Texture2D
var _fights: int = 0
var _first_strikes: int = 0
var _run_mode: bool = false
var _cleared: bool = false
var _players: PlayerRoster = PlayerRoster.solo(3)
## Online, not the host: positions come from the host.
var _remote: bool = false
## Remote: the host's latest positions; the strike counter tells a new strike from an old one.
var _net: Dictionary = {}
var _strikes: int = 0


func configure(zone: ZoneData, tuning: Tuning, visuals: CombatVisuals, explore: ExploreVisuals,
		run_mode: bool = false) -> void:
	_zone = zone
	_tuning = tuning
	_visuals = visuals
	_explore = explore
	_run_mode = run_mode


## The players (default: solo). In co-op only player 1's device walks and strikes.
func configure_players(players: PlayerRoster) -> void:
	_players = players


## Online, not the host: this zone only shows what the host's zone sends.
func configure_remote() -> void:
	_remote = true


## Host: where everything is now, to send to the other machines.
func net_snapshot() -> Dictionary:
	var roamers: Array = []
	for r: Dictionary in _roamers:
		var pos: Vector2 = r.pos
		roamers.append([pos.x, pos.y, int((r.brain as RoamerBrain).state), bool(r.defeated)])
	return {"l": [_leader_pos.x, _leader_pos.y], "f": [_facing.x, _facing.y],
			"w": _walk_phase > 0.0, "s": _strikes, "r": roamers}


## Remote: the host's latest positions (see net_snapshot()). Malformed data is ignored.
func apply_snapshot(d: Dictionary) -> void:
	if not d.get("l") is Array or not d.get("f") is Array or not d.get("r") is Array:
		return
	if (d.l as Array).size() != 2 or (d.f as Array).size() != 2 or (d.r as Array).size() != _roamers.size():
		return
	_net = d


## Remote: the host's leader touched or struck roaming enemy `index`: the same start as there.
func begin_remote(index: int, opening: CombatSetup.Opening) -> void:
	if index >= 0 and index < _roamers.size() and not _frozen:
		_begin(index, opening)


func _ready() -> void:
	_build()


func _enter_tree() -> void:
	# Back from a fight: this camera shows the world again.
	if _camera != null:
		_camera.make_current.call_deferred()


## The roaming enemy a fight is about (its index in the zone data).
func fight_index() -> int:
	return _fight_index


func encounter_of(index: int) -> EncounterData:
	return (_roamers[index].data as ZoneEnemyData).encounter


func look() -> StageLook:
	return _zone.look


func fights_started() -> int:
	return _fights


func first_strikes() -> int:
	return _first_strikes


## Roaming enemies not beaten yet.
func enemies_left() -> int:
	var count := 0
	for r: Dictionary in _roamers:
		if not bool(r.defeated):
			count += 1
	return count


## The leader's spot and facing on the ground (x, z), and the living roamers' spots (autoplay).
func leader_ground() -> Vector2:
	return _leader_pos


func roamer_spots() -> Dictionary:
	var spots := {}
	for i: int in _roamers.size():
		if not bool(_roamers[i].defeated):
			spots[i] = _roamers[i].pos
	return spots


## The roaming enemy that guards the exit (-1 if the zone has none: then every enemy counts).
func guard_index() -> int:
	for i: int in _roamers.size():
		if (_roamers[i].data as ZoneEnemyData).guard:
			return i
	return -1


func is_cleared() -> bool:
	return _cleared


func is_frozen() -> bool:
	return _frozen


## Turns the leader toward a ground direction (autoplay aims before striking).
func face(direction: Vector2) -> void:
	if direction.length() > 0.0001:
		_facing = direction.normalized()
		_update_flip()


## Back from fight `fight_index()` with its result: a beaten enemy is gone; one the party ran
## from goes home; after a defeat the leader starts over at the zone's start and every enemy
## goes home. Nothing can start a fight
## for explore_return_grace_ms.
func resume(result: String) -> void:
	if _fight_index >= 0 and _fight_index < _roamers.size():
		var r: Dictionary = _roamers[_fight_index]
		if result == "victory":
			r.defeated = true
			(r.view as FighterView).visible = false
			_hud.set_notice(_fight_index, false)
			_hud.set_tag(_fight_index, "", false)
		elif result == "escaped":
			# Ran away (DESIGN.md 2.13): the enemy goes home; the leader stays where it is.
			(r.brain as RoamerBrain).reset()
			r.pos = (r.brain as RoamerBrain).home
			_hud.set_notice(_fight_index, false)
		else:
			_leader_pos = Vector2(_zone.player_start.x, _zone.player_start.z)
			for other: Dictionary in _roamers:
				(other.brain as RoamerBrain).reset()
				other.pos = (other.brain as RoamerBrain).home
	_fight_index = -1
	_frozen = false
	# The swing that started the fight is over: zone time stood still during the fight, so it
	# would otherwise still be "swinging" and start a fight during the fade back in.
	_strike_until_ms = _time_ms
	_grace_until_ms = _time_ms + float(_tuning.explore_return_grace_ms)
	_update_goal()
	_place_walkers(0.0)
	_snap_camera()
	if not _cleared and _goal_met():
		_cleared = true
		# A run moves on to the map now: nothing may start another fight on the way out.
		_frozen = _run_mode
		_hud.banner("ZONE CLEAR", HudStyle.GOLD, _explore.zone_title_ms)
		cleared.emit()


## A run zone is done when its guard is beaten; otherwise when every enemy is.
func _goal_met() -> bool:
	var guard := guard_index()
	if _run_mode and guard >= 0:
		return bool(_roamers[guard].defeated)
	return enemies_left() == 0


func _update_goal() -> void:
	var guard := guard_index()
	if _run_mode and guard >= 0:
		var others := enemies_left() - (0 if bool(_roamers[guard].defeated) else 1)
		_hud.set_guard_goal(bool(_roamers[guard].defeated), others)
	else:
		_hud.set_enemies_left(enemies_left())


# --- building ---------------------------------------------------------------------------------

func _build() -> void:
	var look := _zone.look if _zone.look != null else StageLook.new()
	_world = Node3D.new()
	_world.name = "World"
	add_child(_world)
	_world.add_child(StageBuilder.environment(look))
	_world.add_child(StageBuilder.sun(look))
	var centre := (_zone.bounds_min + _zone.bounds_max) * 0.5
	_world.add_child(StageBuilder.ground(look, Vector3(centre.x, 0.0, centre.y)))
	StageBuilder.add_contents(_world, _zone.blocks, _zone.props, _zone.lights)
	add_child(StageBuilder.vignette(look))
	_obstacles = ZoneMotion.obstacles(_zone)
	_slash_texture = AssetLoader.texture(_visuals.slash_path, Vector2i(32, 32))

	_leader_pos = Vector2(_zone.player_start.x, _zone.player_start.z)
	var c := _zone.leader
	_leader = FighterView.new()
	_leader.name = "Leader"
	_world.add_child(_leader)
	if c != null:
		_leader.setup(-1, true, c.sprite_path, c.sprite_hframes, Vector2i(32, 48), c.sprite_pixel_size,
				not _visuals.party_art_faces_right, _visuals)
	else:
		push_warning("ZoneController: zone %s has no leader" % _zone.id)
		_leader.setup(-1, true, "", 8, Vector2i(32, 48), 0.045, false, _visuals)

	for i: int in _zone.enemies.size():
		var data := _zone.enemies[i]
		if data == null or data.encounter == null or data.encounter.enemies.is_empty():
			push_warning("ZoneController: roaming enemy %d of %s has no encounter" % [i, _zone.id])
			continue
		var enemy := data.encounter.enemies[0]
		var view := FighterView.new()
		view.name = "Roamer%d" % i
		_world.add_child(view)
		view.setup(-2 - i, false, enemy.sprite_path, enemy.sprite_hframes, Vector2i(64, 64),
				enemy.sprite_pixel_size, not _visuals.enemy_art_faces_left, _visuals)
		var home := Vector2(data.position.x, data.position.z)
		var brain := RoamerBrain.new(home, data.wander_radius, hash(_zone.id) + i)
		_roamers.append({"data": data, "view": view, "brain": brain, "pos": home, "defeated": false,
				"phase": float(i) * 0.37})

	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.fov = _explore.camera_fov
	_camera.attributes = StageBuilder.camera_attributes(_explore.dof_far_enabled, _explore.dof_far_distance,
			_explore.dof_far_transition, _explore.dof_near_enabled, _explore.dof_near_distance,
			_explore.dof_near_transition, _explore.dof_amount)
	_world.add_child(_camera)
	_camera.current = true

	_hud = ZoneHud.new()
	_hud.name = "ZoneHud"
	add_child(_hud)
	_hud.setup(_explore, _zone.display_name)
	_update_goal()
	_place_walkers(0.0)
	_snap_camera()


# --- every frame ------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _frozen:
		return
	var dt_ms := delta * 1000.0
	_time_ms += dt_ms
	if _remote:
		_follow_host(delta)
		_place_walkers(delta)
		_follow_camera(delta)
		_update_marks()
		return
	var move := bot_move if use_bot else _leader_input()
	var striking := _time_ms < _strike_until_ms
	var walking := not striking and move.length() > MOVE_DEADZONE
	if walking:
		var step := move.limit_length(1.0) * _tuning.explore_walk_speed * delta
		_leader_pos = ZoneMotion.move(_leader_pos, step, LEADER_RADIUS, _obstacles, _zone.bounds_min, _zone.bounds_max)
		_facing = move.normalized()
		_update_flip()
		_walk_phase += delta * _explore.walk_bob_hz
	else:
		_walk_phase = 0.0
	if not striking:
		_leader.set_pose(FighterView.CharPose.READY if walking and fposmod(_walk_phase, 1.0) < 0.5 else FighterView.CharPose.IDLE)

	var calm := _time_ms < _grace_until_ms
	for i: int in _roamers.size():
		var r: Dictionary = _roamers[i]
		if bool(r.defeated):
			continue
		var brain := r.brain as RoamerBrain
		var velocity := brain.step(dt_ms, r.pos, _leader_pos, _tuning, not calm)
		if velocity.length() > 0.0:
			r.pos = ZoneMotion.move(r.pos, velocity * delta, ROAMER_RADIUS, _obstacles, _zone.bounds_min, _zone.bounds_max)
			r.phase = float(r.phase) + delta * _explore.roam_bob_hz
			if absf(velocity.x) > 0.05:
				(r.view as FighterView).set_flip((velocity.x > 0.0) == _visuals.enemy_art_faces_left)
		var pose := EnemyChoreography.Pose.IDLE
		match brain.state:
			RoamerBrain.State.NOTICE:
				pose = EnemyChoreography.Pose.WINDUP
			RoamerBrain.State.CHASE:
				pose = EnemyChoreography.Pose.LUNGE
		(r.view as FighterView).set_pose(pose)
		# An enemy that walks into a swing still in progress is struck first.
		if striking and not calm and ZoneMotion.in_reach(_leader_pos, _facing, r.pos, _tuning.explore_strike_reach,
				_tuning.explore_strike_arc_degrees):
			_begin(i, CombatSetup.Opening.FIRST_STRIKE)
			return
		if not calm and (r.pos as Vector2).distance_to(_leader_pos) <= _tuning.explore_touch_radius:
			_begin(i, CombatSetup.Opening.NORMAL)
			return
	_place_walkers(delta)
	_follow_camera(delta)
	_update_marks()


func _unhandled_input(event: InputEvent) -> void:
	if _frozen or _remote or input_held or not is_inside_tree():
		return
	# Pause (Esc / Menu) is Main's: it stops this node and opens the pause menu.
	if event.is_action_pressed(&"field_strike", false, true):
		get_viewport().set_input_as_handled()
		if _players.player_of_device(PlayerRoster.device_of(event)) == 0:
			strike()


## The walk input: any device in solo and online (the host is player 1), only player 1's device in
## local co-op.
func _leader_input() -> Vector2:
	if input_held:
		return Vector2.ZERO
	if not _players.is_coop() or _players.is_online():
		return Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	return DeviceInput.vector(&"move_left", &"move_right", &"move_up", &"move_down", _players.device_of_player(0))


## The leader's field strike: a slash in front; a roaming enemy inside it starts a FIRST STRIKE.
func strike() -> void:
	if _frozen or _remote or _time_ms < _strike_until_ms:
		return
	_strike_until_ms = _time_ms + float(_tuning.explore_strike_ms)
	_strikes += 1
	_show_strike()
	var best := -1
	var best_dist := INF
	for i: int in _roamers.size():
		var r: Dictionary = _roamers[i]
		if bool(r.defeated):
			continue
		var pos: Vector2 = r.pos
		if ZoneMotion.in_reach(_leader_pos, _facing, pos, _tuning.explore_strike_reach, _tuning.explore_strike_arc_degrees):
			var d := pos.distance_to(_leader_pos)
			if d < best_dist:
				best = i
				best_dist = d
	if best >= 0:
		_begin(best, CombatSetup.Opening.FIRST_STRIKE)


## The strike's pose, sound and slash (also on the other machines online).
func _show_strike() -> void:
	_leader.play_pose(FighterView.CharPose.STRIKE, _tuning.explore_strike_ms)
	Sfx.play("strike")
	var front := _leader_pos + _facing * _explore.strike_slash_distance
	_spawn_slash(Vector3(front.x, SLASH_HEIGHT, front.y))


## Remote: glide toward the host's positions, copy its facing, walking, strikes and enemy states.
func _follow_host(delta: float) -> void:
	if _net.is_empty():
		return
	var k := 1.0 - exp(-delta * 1000.0 / float(maxi(1, _explore.net_follow_ms)))
	_leader_pos = _leader_pos.lerp(Vector2(float(_net.l[0]), float(_net.l[1])), k)
	var facing := Vector2(float(_net.f[0]), float(_net.f[1]))
	if facing.length() > 0.0001:
		_facing = facing.normalized()
		_update_flip()
	var striking := _time_ms < _strike_until_ms
	if int(_net.get("s", 0)) != _strikes:
		_strikes = int(_net.get("s", 0))
		_strike_until_ms = _time_ms + float(_tuning.explore_strike_ms)
		_show_strike()
		striking = true
	if bool(_net.get("w", false)) and not striking:
		_walk_phase += delta * _explore.walk_bob_hz
		_leader.set_pose(FighterView.CharPose.READY if fposmod(_walk_phase, 1.0) < 0.5 else FighterView.CharPose.IDLE)
	elif not striking:
		_walk_phase = 0.0
		_leader.set_pose(FighterView.CharPose.IDLE)
	for i: int in _roamers.size():
		var r: Dictionary = _roamers[i]
		var entry: Variant = (_net.r as Array)[i]
		if not entry is Array or (entry as Array).size() != 4:
			continue
		var gone := bool(entry[3])
		if gone and not bool(r.defeated):
			r.defeated = true
			(r.view as FighterView).visible = false
			_hud.set_notice(i, false)
			_hud.set_tag(i, "", false)
			_update_goal()
		if gone:
			continue
		var target := Vector2(float(entry[0]), float(entry[1]))
		var old: Vector2 = r.pos
		r.pos = old.lerp(target, k)
		var brain := r.brain as RoamerBrain
		brain.state = clampi(int(entry[2]), 0, RoamerBrain.State.size() - 1) as RoamerBrain.State
		if absf(target.x - old.x) > 0.001:
			(r.view as FighterView).set_flip((target.x > old.x) == _visuals.enemy_art_faces_left)
		var moving := brain.state in [RoamerBrain.State.WANDER, RoamerBrain.State.CHASE, RoamerBrain.State.RETURN]
		if moving:
			r.phase = float(r.phase) + delta * _explore.roam_bob_hz
		var pose := EnemyChoreography.Pose.IDLE
		match brain.state:
			RoamerBrain.State.NOTICE:
				pose = EnemyChoreography.Pose.WINDUP
			RoamerBrain.State.CHASE:
				pose = EnemyChoreography.Pose.LUNGE
		(r.view as FighterView).set_pose(pose)


func _begin(index: int, opening: CombatSetup.Opening) -> void:
	_frozen = true
	_fight_index = index
	_fights += 1
	var view := _roamers[index].view as FighterView
	if opening == CombatSetup.Opening.FIRST_STRIKE:
		_first_strikes += 1
		view.flash(_visuals.flash_ms * 2)
		view.play_pose(EnemyChoreography.Pose.HURT, int(FIRST_STRIKE_PAUSE_S * 1000.0))
		_hud.banner("FIRST STRIKE!", HudStyle.GOLD, int(FIRST_STRIKE_PAUSE_S * 1000.0) + _explore.transition_out_ms)
		Sfx.play("counter")
		await get_tree().create_timer(FIRST_STRIKE_PAUSE_S).timeout
	else:
		view.flash(_visuals.telegraph_flash_ms * 2, _visuals.telegraph_flash_color, 0.8)
		_leader.play_pose(FighterView.CharPose.HURT, int(TOUCH_PAUSE_S * 1000.0) + _explore.transition_out_ms)
		Sfx.play("alert")
		await get_tree().create_timer(TOUCH_PAUSE_S).timeout
	_hud.set_notice(index, false)
	encounter_started.emit(index, opening)


func _update_flip() -> void:
	if absf(_facing.x) > 0.1:
		# Party art faces right: facing left mirrors it.
		_leader.set_flip((_facing.x < 0.0) == _visuals.party_art_faces_right)


## Puts every walker's node on its ground spot, with the walking bob.
func _place_walkers(_delta: float) -> void:
	_leader.position = Vector3(_leader_pos.x, 0.0, _leader_pos.y)
	var bob := absf(sin(_walk_phase * PI)) * _explore.walk_bob_height
	_leader.body_offset = Vector3(0.0, bob, 0.0)
	for r: Dictionary in _roamers:
		if bool(r.defeated):
			continue
		var pos: Vector2 = r.pos
		var view := r.view as FighterView
		view.position = Vector3(pos.x, 0.0, pos.y)
		var moving := (r.brain as RoamerBrain).state in [RoamerBrain.State.WANDER, RoamerBrain.State.CHASE, RoamerBrain.State.RETURN]
		view.body_offset = Vector3(0.0, absf(sin(float(r.phase) * PI)) * _explore.walk_bob_height if moving else 0.0, 0.0)


func _camera_goal() -> Vector3:
	return Vector3(_leader_pos.x, 0.0, _leader_pos.y) + _explore.camera_offset


func _follow_camera(delta: float) -> void:
	var k := 1.0 - exp(-delta * 1000.0 / float(maxi(1, _explore.camera_follow_ms)))
	_cam_pos = _cam_pos.lerp(_camera_goal(), k)
	_aim_camera()


func _snap_camera() -> void:
	_cam_pos = _camera_goal()
	_aim_camera()


func _aim_camera() -> void:
	var look_at_point := _cam_pos - _explore.camera_offset + _explore.look_offset
	_camera.transform = Transform3D(Basis.looking_at(look_at_point - _cam_pos, Vector3.UP), _cam_pos)


func _update_marks() -> void:
	for i: int in _roamers.size():
		var r: Dictionary = _roamers[i]
		if bool(r.defeated):
			continue
		var view := r.view as FighterView
		var head := view.head_position()
		var on_screen := not _camera.is_position_behind(head)
		var screen := _camera.unproject_position(head)
		var state := (r.brain as RoamerBrain).state
		var alert := state == RoamerBrain.State.NOTICE or state == RoamerBrain.State.CHASE
		_hud.set_notice(i, on_screen and alert, screen)
		var near := (r.pos as Vector2).distance_to(_leader_pos) <= _tuning.explore_notice_radius * TAG_RANGE_SHARE
		if _run_mode and (r.data as ZoneEnemyData).guard:
			# The guard is the way out: always named, in gold.
			_hud.set_tag(i, "GUARD: " + encounter_of(i).display_name, on_screen, screen, HudStyle.GOLD)
		else:
			_hud.set_tag(i, encounter_of(i).display_name, on_screen and near, screen)


func _spawn_slash(at: Vector3) -> void:
	var slash := Sprite3D.new()
	slash.texture = _slash_texture
	slash.pixel_size = _visuals.fx_pixel_size
	slash.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	slash.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	slash.no_depth_test = true
	slash.flip_h = _facing.x < 0.0
	slash.position = at
	slash.scale = Vector3.ONE * _visuals.slash_scale
	_world.add_child(slash)
	var seconds := float(_visuals.slash_ms) / 1000.0
	var tween := slash.create_tween()
	tween.tween_property(slash, "scale", Vector3.ONE * _visuals.slash_scale * CombatView.SLASH_GROWTH, seconds)
	tween.parallel().tween_property(slash, "modulate:a", 0.0, seconds)
	tween.tween_callback(slash.queue_free)
