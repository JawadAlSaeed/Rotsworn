class_name ZoneController
extends Node
## One explorable zone (DESIGN.md 7.4): builds the place from its ZoneData in the HD-2D look
## (StageBuilder), lets the leader walk around (ZoneMotion), runs the roaming enemies (RoamerBrain),
## and starts a fight when the leader strikes an enemy first (FIRST STRIKE) or an enemy touches
## the leader (normal start). Main takes it out of the tree during the fight and calls resume()
## when the party comes back. Walking is presentation, not combat: real time, floats, no engine.
## In a run (DESIGN.md 8) the zone is cleared by beating its guard at the exit; the other roaming
## enemies are optional. Outside a run (practice) every enemy must be beaten.
## A long zone (DESIGN.md 8.5, laid out by ZoneAssembler before it gets here) also has rot seals
## that open the gate to the guard, shrines and wanderers (deals Main asks about), and champions
## that guard prize chests.
## In co-op only player 1 walks and strikes (DESIGN.md 9.1); the others watch.
## Online (DESIGN.md 9.2) the host's zone is the real one: it sends net_snapshot() several times a
## second. On the other machines the zone is `remote`: nothing moves by itself and no fight starts
## here; the walkers glide to the host's positions (apply_snapshot) and a fight starts when the
## host says so (begin_remote).

## A fight is starting: roaming enemy `index` (its encounter), with this opening.
signal encounter_started(index: int, opening: CombatSetup.Opening)
## The zone is cleared: the guard is beaten (run), or every roaming enemy (practice).
signal cleared
## In a run, the leader asked to pick up glinting spot `spot` (DESIGN.md 8.1). Main decides what it
## holds and calls take_spot() once the party has it.
signal pickup_requested(spot: int)
## In a run, the leader tried to open chest `chest`. Main checks for a key and calls open_chest().
signal chest_requested(chest: int)
## In a run, the leader walked up to shrine or wanderer `offer` (DESIGN.md 8.5). Main asks the
## question and calls use_offer() if the deal is taken.
signal offer_requested(offer: int)
## In a run, the leader opened the prize chest of a beaten champion (DESIGN.md 8.5). Main gives
## its prize (open_prize() has already run).
signal prize_requested(prize: int)

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
## A walk that covers less than this share of its full step (pushing into a wall) shows the
## leader standing, so the feet never tread on the spot.
const BLOCKED_SHARE: float = 0.1
## A walking direction must lean this far left or right (ground axis share) to turn the side art.
const SIDE_TURN: float = 0.1
## The floor reaches this far past the zone's bounds on every side (world units).
const FLOOR_MARGIN: float = 30.0
## Rot seals bob up and down this high, once per this long.
const SEAL_BOB: float = 0.08
const SEAL_BOB_MS: float = 2200.0

## Online, the pause menu opens over a zone that goes on: the leader stands still meanwhile.
var input_held: bool = false
## Autoplay (ZoneAutoplay) drives these instead of the input when `use_bot` is set.
var use_bot: bool = false
var bot_move: Vector2 = Vector2.ZERO

var _zone: ZoneData
var _tuning: Tuning
var _visuals: CombatVisuals
var _explore: ExploreVisuals
## The place's look (props built later, like shrines and chests, take their contact shadow from it).
var _look: StageLook
var _world: Node3D
var _camera: Camera3D
var _hud: ZoneHud
var _leader: FighterView
var _leader_pos: Vector2 = Vector2.ZERO
var _facing: Vector2 = Vector2(0.0, -1.0)
## The leader's view (WalkFacing, DESIGN.md 5.5): starts walking away from the camera.
var _view: WalkFacing.Facing = WalkFacing.Facing.BACK
## The last side the leader turned to: the side art (strike, hurt, pickup, a missing view) uses it.
var _side_left: bool = false
## Walk cycle: one whole number per step (WalkFacing); a foot comes down on each.
var _walk_phase: float = 0.0
## The leader is really walking this frame (not standing, striking or pushing into a wall).
var _stepping: bool = false
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
## Deep in a run: roaming enemies hold their encounters' deep versions (variants, DESIGN.md 2.16).
var _deep: bool = false
var _cleared: bool = false
var _players: PlayerRoster = PlayerRoster.solo(3)
## Online, not the host: positions come from the host.
var _remote: bool = false
## Remote: the host's latest positions; the strike counter tells a new strike from an old one.
var _net: Dictionary = {}
var _strikes: int = 0
## Glinting spots (run mode): {pos: Vector2, view: Sprite3D, taken: bool}.
var _spots: Array[Dictionary] = []
## Locked chests (run mode): {pos: Vector2, view: Sprite3D or a 3D piece, opened: bool}.
var _chests: Array[Dictionary] = []
## Held still while a screen is open over the zone (the backpack): nothing moves, no input.
var _paused: bool = false
## Rot seals (DESIGN.md 8.5): {pos: Vector2, view: Sprite3D or a 3D piece, light: OmniLight3D, taken: bool}.
var _seals: Array[Dictionary] = []
## Seals the gate wants (0: no gate, or open from the start).
var _seals_needed: int = 0
## The gate to the guard: its block node and its obstacle (both null / empty once it is open).
var _gate_view: MeshInstance3D
var _gate_obstacle: Dictionary = {}
## Shrines and wanderers: {pos: Vector2, data: ZoneOfferData, view: Sprite3D or a 3D piece, used: bool}.
var _offers: Array[Dictionary] = []
## Champions' prize chests: {pos: Vector2, view: Sprite3D or a 3D piece, roamer: int, opened: bool}.
var _prizes: Array[Dictionary] = []
## Drifting particles (DESIGN.md 8.12): {node: GPUParticles3D, height: float}; they follow the
## camera's spot.
var _ambient: Array[Dictionary] = []
## Crows, frogs and rats: {data, view: Sprite3D, pos: Vector3, state: 0 idle / 1 away / 2 gone,
## t: seconds in the state, next: seconds to the next idle frame, dir: float (-1 / 1), frame}.
var _critters: Array[Dictionary] = []
var _critter_rng := RandomNumberGenerator.new()


func configure(zone: ZoneData, tuning: Tuning, visuals: CombatVisuals, explore: ExploreVisuals,
		run_mode: bool = false, deep: bool = false) -> void:
	_zone = zone
	_tuning = tuning
	_visuals = visuals
	_explore = explore
	_run_mode = run_mode
	_deep = deep


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
	var taken: Array = []
	for spot: Dictionary in _spots:
		taken.append(bool(spot.taken))
	var opened: Array = []
	for chest: Dictionary in _chests:
		opened.append(bool(chest.opened))
	return {"l": [_leader_pos.x, _leader_pos.y], "f": [_facing.x, _facing.y],
			"w": _stepping, "s": _strikes, "r": roamers, "p": taken, "c": opened,
			"g": _flags(_seals, "taken"), "o": _flags(_offers, "used"), "z": _flags(_prizes, "opened")}


static func _flags(list: Array[Dictionary], key: String) -> Array:
	var out: Array = []
	for entry: Dictionary in list:
		out.append(bool(entry[key]))
	return out


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
	return _roamers[index].encounter as EncounterData


func look() -> StageLook:
	return _zone.look


## The particles drifting through this zone (also played, thinner, in its fights).
func ambient_air() -> Array[ZoneAmbientData]:
	return _zone.ambient


## This zone's background loop and its volume (empty path: none).
func ambience() -> Array:
	return [_zone.ambience_path, _zone.ambience_volume_db] if _zone != null else ["", 0.0]


## This zone's song (empty: none of its own).
func music_path() -> String:
	return _zone.music_path if _zone != null else ""


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


## Holds the zone still (a screen is open over it) or lets it go on.
func set_paused(paused: bool) -> void:
	_paused = paused


func is_paused() -> bool:
	return _paused


## Rot seals not taken yet: index -> ground spot (autoplay).
func seal_positions() -> Dictionary:
	var found := {}
	for i: int in _seals.size():
		if not bool(_seals[i].taken):
			found[i] = _seals[i].pos
	return found


func seals_held() -> int:
	var count := 0
	for seal: Dictionary in _seals:
		if bool(seal.taken):
			count += 1
	return count


func seals_needed() -> int:
	return _seals_needed


func is_gate_open() -> bool:
	return _gate_obstacle.is_empty()


## What blocks walking right now (the gate while it is shut), for ZonePath (autoplay).
func obstacles() -> Array[Dictionary]:
	return _obstacles


func bounds() -> Array[Vector2]:
	return [_zone.bounds_min, _zone.bounds_max]


## Shrines and wanderers not used yet: index -> ground spot (autoplay).
func offer_positions() -> Dictionary:
	var found := {}
	for i: int in _offers.size():
		if not bool(_offers[i].used):
			found[i] = _offers[i].pos
	return found


func offer_data(offer: int) -> ZoneOfferData:
	return _offers[offer].data as ZoneOfferData if offer >= 0 and offer < _offers.size() else null


## Prize chests whose champion is beaten and that are still shut: index -> ground spot (autoplay).
func prize_positions() -> Dictionary:
	var found := {}
	for i: int in _prizes.size():
		if not bool(_prizes[i].opened) and bool(_roamers[int(_prizes[i].roamer)].defeated):
			found[i] = _prizes[i].pos
	return found


## The roaming enemy whose prize chest `prize` is.
func prize_roamer(prize: int) -> int:
	return int(_prizes[prize].roamer)


## Champions (DESIGN.md 8.5) by roamer index.
func is_champion(index: int) -> bool:
	return index >= 0 and index < _roamers.size() and (_roamers[index].data as ZoneEnemyData).champion


## Glinting spots not picked up yet: index -> ground spot (autoplay).
func spot_positions() -> Dictionary:
	var found := {}
	for i: int in _spots.size():
		if not bool(_spots[i].taken):
			found[i] = _spots[i].pos
	return found


## Chests not opened yet: index -> ground spot (autoplay).
func chest_positions() -> Dictionary:
	var found := {}
	for i: int in _chests.size():
		if not bool(_chests[i].opened):
			found[i] = _chests[i].pos
	return found


## The closed chest within reach of the leader (-1: none).
func chest_in_reach() -> int:
	var best := -1
	var best_dist := _tuning.explore_pickup_radius
	for i: int in _chests.size():
		var d := (_chests[i].pos as Vector2).distance_to(_leader_pos)
		if not bool(_chests[i].opened) and d <= best_dist:
			best = i
			best_dist = d
	return best


## The chest opens (Main found a key): its lid swings up and the leader reaches in.
func open_chest(chest: int) -> void:
	if chest < 0 or chest >= _chests.size() or bool(_chests[chest].opened):
		return
	_chests[chest].opened = true
	_show_chest_open(chest)
	play_pickup(0)


func _show_chest_open(chest: int) -> void:
	_show_open(_chests[chest])


## A chest (or a champion's prize chest) shows itself open: the open sprite, or the open 3D
## piece in place of the closed one. The two pieces share the box's front (only the lid differs,
## thrown back), so their front faces line up and the box does not jump.
func _show_open(entry: Dictionary) -> void:
	var sprite := entry.view as Sprite3D
	if sprite != null:
		var tex := AssetLoader.texture(_explore.chest_open_path, Vector2i(28, 24))
		sprite.texture = tex
		(sprite.material_override as ShaderMaterial).set_shader_parameter("sprite_texture", tex)
		return
	var old := entry.view as MeshInstance3D
	if old == null or _explore.chest_open_piece == null:
		return
	var view := StageBuilder.piece_view(_explore.chest_open_piece)
	view.transform = old.transform
	view.position += old.basis * Vector3(0.0, 0.0, old.mesh.get_aabb().end.z - view.mesh.get_aabb().end.z)
	old.add_sibling(view)
	old.queue_free()
	entry["view"] = view


## The glinting spot within pickup reach of the leader (-1: none).
func spot_in_reach() -> int:
	var best := -1
	var best_dist := _tuning.explore_pickup_radius
	for i: int in _spots.size():
		var d := (_spots[i].pos as Vector2).distance_to(_leader_pos)
		if not bool(_spots[i].taken) and d <= best_dist:
			best = i
			best_dist = d
	return best


## The rot seal within reach of the leader (-1: none).
func seal_in_reach() -> int:
	return _nearest_in_reach(_seals, "taken")


## The shrine or wanderer within reach (-1: none; only in a run, where deals can be paid).
func offer_in_reach() -> int:
	return _nearest_in_reach(_offers, "used") if _run_mode else -1


## The prize chest within reach whose champion is beaten (-1: none).
func prize_in_reach() -> int:
	var best := -1
	var best_dist := _tuning.explore_pickup_radius
	for i: int in _prizes.size():
		var d := (_prizes[i].pos as Vector2).distance_to(_leader_pos)
		if not bool(_prizes[i].opened) and bool(_roamers[int(_prizes[i].roamer)].defeated) and d <= best_dist:
			best = i
			best_dist = d
	return best


func _nearest_in_reach(list: Array[Dictionary], done_key: String) -> int:
	var best := -1
	var best_dist := _tuning.explore_pickup_radius
	for i: int in list.size():
		var d := (list[i].pos as Vector2).distance_to(_leader_pos)
		if not bool(list[i][done_key]) and d <= best_dist:
			best = i
			best_dist = d
	return best


## What Confirm does here now: "" for nothing, else the hint's text.
func _use_hint() -> String:
	if _remote:
		return ""
	if spot_in_reach() >= 0:
		return "Pick up"
	if chest_in_reach() >= 0:
		return "Open chest"
	if prize_in_reach() >= 0 and _run_mode:
		return "Open chest"
	if seal_in_reach() >= 0:
		return "Take the seal"
	var offer := offer_in_reach()
	if offer >= 0:
		var data := _offers[offer].data as ZoneOfferData
		return ("Pray at " if data.kind == ZoneOfferData.Kind.SHRINE else "Talk to ") + data.display_name
	return ""


## The leader uses what is in reach: picks up a spot, opens a chest (Main answers with take_spot()
## or open_chest()), takes a seal, opens a beaten champion's prize chest, or walks up to a shrine
## or wanderer (Main asks and answers with use_offer()).
func pickup() -> void:
	if _frozen or _paused or _remote:
		return
	var spot := spot_in_reach()
	if spot >= 0:
		pickup_requested.emit(spot)
		return
	var chest := chest_in_reach()
	if chest >= 0:
		chest_requested.emit(chest)
		return
	var prize := prize_in_reach()
	if prize >= 0 and _run_mode:
		open_prize(prize)
		prize_requested.emit(prize)
		return
	var seal := seal_in_reach()
	if seal >= 0:
		take_seal(seal)
		return
	var offer := offer_in_reach()
	if offer >= 0:
		offer_requested.emit(offer)


## The party takes rot seal `seal`: it is gone; with enough seals the gate opens.
func take_seal(seal: int) -> void:
	if seal < 0 or seal >= _seals.size() or bool(_seals[seal].taken):
		return
	_seals[seal].taken = true
	_hide_seal(seal)
	play_pickup(0)
	Sfx.play("item_found")
	var held := seals_held()
	if _seals_needed > 0 and held >= _seals_needed and not is_gate_open():
		_open_gate()
	elif _seals_needed > held:
		_hud.banner("Rot seal %d / %d" % [held, _seals_needed], HudStyle.GOLD, _explore.zone_title_ms)
	_update_goal()


func _hide_seal(seal: int) -> void:
	(_seals[seal].view as Node3D).visible = false
	(_seals[seal].light as OmniLight3D).visible = false


## The gate sinks into the ground and stops blocking the way.
func _open_gate() -> void:
	if is_gate_open():
		return
	_obstacles.erase(_gate_obstacle)
	_gate_obstacle = {}
	_hud.banner("THE GATE OPENS", HudStyle.GOLD, _explore.zone_title_ms)
	Sfx.play("zone_clear")
	if _gate_view != null:
		var sink := _gate_view.create_tween()
		sink.tween_property(_gate_view, "position:y", _gate_view.position.y - _zone.gate.size.y - 0.1,
				float(_explore.gate_open_ms) / 1000.0).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		sink.tween_callback(_gate_view.hide)


## Shrine or wanderer `offer` has given its gift: a shrine dims, a wanderer fades away.
func use_offer(offer: int) -> void:
	if offer < 0 or offer >= _offers.size() or bool(_offers[offer].used):
		return
	_offers[offer].used = true
	_show_offer_used(offer, true)


func _show_offer_used(offer: int, animate: bool) -> void:
	var data := _offers[offer].data as ZoneOfferData
	var view := _offers[offer].view as Node3D
	if data.kind == ZoneOfferData.Kind.WANDERER:
		var obstacle: Dictionary = _offers[offer].get("obstacle", {})
		_obstacles.erase(obstacle)
		if animate:
			var fade := view.create_tween()
			fade.tween_property(view, "modulate:a", 0.0, float(_explore.offer_fade_ms) / 1000.0)
			fade.tween_callback(view.hide)
		else:
			view.hide()
	else:
		StageBuilder.dim_glow(view, data.glow, _explore.offer_used_glow_share)
	var light: OmniLight3D = _offers[offer].get("light")
	if light != null:
		light.visible = false


## The prize chest of a beaten champion opens (its lid swings up).
func open_prize(prize: int) -> void:
	if prize < 0 or prize >= _prizes.size() or bool(_prizes[prize].opened):
		return
	_prizes[prize].opened = true
	_show_prize_open(prize)
	play_pickup(0)


func _show_prize_open(prize: int) -> void:
	_show_open(_prizes[prize])


## A short gold line over the zone (for example what was just found).
func announce(text: String) -> void:
	_hud.banner(text, HudStyle.GOLD, _explore.zone_title_ms)


## The party has what spot `spot` held: it is gone, and the leader bends down for it.
func take_spot(spot: int) -> void:
	if spot < 0 or spot >= _spots.size() or bool(_spots[spot].taken):
		return
	_spots[spot].taken = true
	(_spots[spot].view as Sprite3D).visible = false
	play_pickup(0)


## Turns the leader toward a ground direction (autoplay aims before striking).
func face(direction: Vector2) -> void:
	_turn(direction)


## The leader bends down for the guard's loot (#71) once the zone is cleared, in the moment before
## the fade to the loot screen. Turns to its last side first: the pickup is side art.
func play_pickup(delay_ms: int = -1) -> void:
	if not WalkFacing.is_side(_view):
		_view = WalkFacing.Facing.SIDE_L if _side_left else WalkFacing.Facing.SIDE_R
	_pose_leader()
	_leader.play("pickup", _explore.pickup_ms, FighterView.PRIO_BIG, -1,
			_explore.pickup_delay_ms if delay_ms < 0 else delay_ms)


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
	# Back on its feet, standing: the walk the fight interrupted is over.
	_walk_phase = 0.0
	_stepping = false
	_pose_leader()
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
		Sfx.play("zone_clear")
		if result == "victory":
			play_pickup()
		cleared.emit()


## A run zone is done when its guard is beaten; otherwise when every enemy is.
func _goal_met() -> bool:
	var guard := guard_index()
	if _run_mode and guard >= 0:
		return bool(_roamers[guard].defeated)
	return enemies_left() == 0


func _update_goal() -> void:
	var lines: Array[String] = []
	if not is_gate_open():
		lines.append("Rot seals: %d / %d  (they open the gate)" % [seals_held(), _seals_needed])
	var guard := guard_index()
	if _run_mode and guard >= 0:
		var beaten := bool(_roamers[guard].defeated)
		lines.append("The way out is open" if beaten else "Beat the GUARD at the exit")
		lines.append("Optional enemies: %d" % (enemies_left() - (0 if beaten else 1)))
	else:
		lines.append("Enemies left: %d" % enemies_left() if enemies_left() > 0 else "All enemies beaten")
	_hud.set_goal("\n".join(lines))


# --- building ---------------------------------------------------------------------------------

func _build() -> void:
	var look := _zone.look if _zone.look != null else StageLook.new()
	_world = Node3D.new()
	_world.name = "World"
	add_child(_world)
	_world.add_child(StageBuilder.environment(look))
	_world.add_child(StageBuilder.sun(look))
	var centre := (_zone.bounds_min + _zone.bounds_max) * 0.5
	var cover := _zone.bounds_max - _zone.bounds_min + Vector2(FLOOR_MARGIN, FLOOR_MARGIN) * 2.0
	_world.add_child(StageBuilder.ground(look, Vector3(centre.x, 0.0, centre.y), cover))
	StageBuilder.add_contents(_world, _zone.blocks, _zone.props, _zone.lights, _zone.grounds, look)
	_look = look
	for data: ZoneAmbientData in _zone.ambient:
		if data != null:
			var particles := StageBuilder.ambient(data)
			_world.add_child(particles)
			_ambient.append({"node": particles, "height": data.height})
	for i: int in _zone.critters.size():
		_add_critter(_zone.critters[i], i)
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
				not _visuals.party_art_faces_right, _visuals, c.sprite_clips)
	else:
		push_warning("ZoneController: zone %s has no leader" % _zone.id)
		_leader.setup(-1, true, "", 8, Vector2i(32, 48), 0.045, false, _visuals)

	for i: int in _zone.enemies.size():
		var data := _zone.enemies[i]
		if data == null or data.encounter == null or data.encounter.enemies.is_empty():
			push_warning("ZoneController: roaming enemy %d of %s has no encounter" % [i, _zone.id])
			continue
		var encounter := data.encounter
		if _deep and encounter.deep != null and not encounter.deep.enemies.is_empty():
			encounter = encounter.deep
		var enemy := encounter.enemies[0]
		var view := FighterView.new()
		view.name = "Roamer%d" % i
		_world.add_child(view)
		view.setup(-2 - i, false, enemy.sprite_path, enemy.sprite_hframes, Vector2i(64, 64),
				enemy.sprite_pixel_size, not _visuals.enemy_art_faces_left, _visuals, enemy.sprite_clips,
				enemy.idle_cycle_percent)
		var home := Vector2(data.position.x, data.position.z)
		var brain := RoamerBrain.new(home, data.wander_radius, hash(_zone.id) + i)
		_roamers.append({"data": data, "encounter": encounter, "view": view, "brain": brain, "pos": home,
				"defeated": false, "phase": float(i) * 0.37})

	if _run_mode:
		for pos: Vector3 in _zone.item_spots:
			var glint := ZonePropData.new()
			glint.contact_shadow = false
			glint.sprite_path = _explore.glint_path
			glint.pixel_size = _explore.glint_pixel_size
			glint.position = pos + Vector3(0.0, _explore.glint_height, 0.0)
			glint.glow = _explore.glint_glow
			glint.glow_color = _explore.glint_color
			var view := StageBuilder.prop(glint)
			_world.add_child(view)
			_spots.append({"pos": Vector2(pos.x, pos.z), "view": view, "taken": false})
		for pos: Vector3 in _zone.chests:
			var chest := ZonePropData.new()
			chest.sprite_path = _explore.chest_closed_path
			chest.pixel_size = _explore.chest_pixel_size
			chest.piece = _explore.chest_piece
			chest.position = pos
			var view := StageBuilder.prop_view(chest, _look)
			_world.add_child(view)
			_chests.append({"pos": Vector2(pos.x, pos.z), "view": view, "opened": false})
		for i: int in _roamers.size():
			var data := _roamers[i].data as ZoneEnemyData
			if not data.champion:
				continue
			var chest := ZonePropData.new()
			chest.sprite_path = _explore.chest_closed_path
			chest.pixel_size = _explore.chest_pixel_size
			chest.piece = _explore.chest_piece
			chest.position = data.prize_spot
			var view := StageBuilder.prop_view(chest, _look)
			_world.add_child(view)
			_prizes.append({"pos": Vector2(data.prize_spot.x, data.prize_spot.z), "view": view, "roamer": i,
					"opened": false})
		for i: int in _zone.offers.size():
			if _zone.offers[i] != null and i < _zone.offer_spots.size():
				_add_offer(_zone.offers[i], _zone.offer_spots[i])
	_build_seals_and_gate()

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
	_hud.setup(_explore, _zone.display_name, _run_mode)
	Sfx.play("zone_enter")
	_update_goal()
	_place_walkers(0.0)
	_snap_camera()


## Rot seals (glowing stones with a small light) and the gate, solid until enough seals are held.
func _build_seals_and_gate() -> void:
	for pos: Vector3 in _zone.seal_spots:
		var stone := ZonePropData.new()
		stone.sprite_path = _explore.seal_path
		stone.pixel_size = _explore.seal_pixel_size
		stone.position = pos
		stone.glow = _explore.seal_glow
		stone.glow_color = _explore.seal_color
		stone.piece = _explore.seal_piece
		var view := StageBuilder.prop_view(stone, _look)
		_world.add_child(view)
		var lamp := ZoneLightData.new()
		lamp.position = pos + Vector3(0.0, 1.0, 0.4)
		lamp.color = _explore.seal_color
		lamp.energy = _explore.seal_light_energy
		lamp.reach = _explore.seal_light_reach
		lamp.flicker_percent = 15
		lamp.flicker_hz = 2.0
		var light := StageBuilder.light(lamp)
		_world.add_child(light)
		_seals.append({"pos": Vector2(pos.x, pos.z), "view": view, "light": light, "taken": false})
	if _zone.gate == null:
		return
	_seals_needed = mini(_tuning.zone_seals_needed, _seals.size())
	if _seals_needed <= 0:
		return
	_gate_view = StageBuilder.block(_zone.gate)
	_gate_view.name = "Gate"
	_world.add_child(_gate_view)
	var g := _zone.gate
	_gate_obstacle = {"centre": Vector2(g.position.x, g.position.z), "half": Vector2(g.size.x, g.size.z) * 0.5,
			"angle": deg_to_rad(g.rotation_y_degrees)}
	_obstacles.append(_gate_obstacle)


## A shrine or a wanderer standing at `pos`, with a small light in its glow colour.
func _add_offer(data: ZoneOfferData, pos: Vector3) -> void:
	var prop := ZonePropData.new()
	prop.sprite_path = data.sprite_path
	prop.pixel_size = data.pixel_size
	prop.position = pos
	prop.glow = data.glow
	prop.glow_color = data.glow_color
	prop.piece = data.piece
	var view := StageBuilder.prop_view(prop, _look)
	_world.add_child(view)
	var entry := {"pos": Vector2(pos.x, pos.z), "data": data, "view": view, "used": false}
	if data.glow > 0.0:
		var lamp := ZoneLightData.new()
		lamp.position = pos + Vector3(0.0, 1.2, 0.5)
		lamp.color = data.glow_color
		lamp.energy = _explore.offer_light_energy
		lamp.reach = _explore.offer_light_reach
		var light := StageBuilder.light(lamp)
		_world.add_child(light)
		entry["light"] = light
	if data.solid_radius > 0.0:
		var obstacle := {"centre": Vector2(pos.x, pos.z), "radius": data.solid_radius}
		_obstacles.append(obstacle)
		entry["obstacle"] = obstacle
	_offers.append(entry)


## A crow, frog or rat (DESIGN.md 8.12): a 4-frame sprite (idle, idle, move, move) lit like a prop.
func _add_critter(data: ZoneCritterData, index: int) -> void:
	if data == null:
		return
	var prop := ZonePropData.new()
	prop.sprite_path = data.sprite_path
	prop.pixel_size = data.pixel_size
	prop.position = data.position
	prop.flip = data.flip
	prop.contact_shadow = false
	var view := StageBuilder.prop(prop)
	view.hframes = 4
	view.frame = 0
	_world.add_child(view)
	_critter_rng.seed = hash(_zone.id) + index * 7
	_critters.append({"data": data, "view": view, "pos": data.position, "state": 0, "t": 0.0,
			"next": _critter_rng.randf_range(0.3, 1.5), "dir": -1.0 if data.flip else 1.0, "frame": 0})


## The drifting particles follow the camera's spot; critters idle, then get away from the leader.
func _update_life(delta: float) -> void:
	var spot := Vector3(_leader_pos.x, 0.0, _leader_pos.y)
	for a: Dictionary in _ambient:
		(a.node as GPUParticles3D).global_position = spot + Vector3(0.0, float(a.height), 0.0)
	for c: Dictionary in _critters:
		_update_critter(c, delta)


func _update_critter(c: Dictionary, delta: float) -> void:
	var view := c.view as Sprite3D
	var data := c.data as ZoneCritterData
	c.t = float(c.t) + delta
	match int(c.state):
		0:
			c.next = float(c.next) - delta
			if float(c.next) <= 0.0:
				c.frame = 1 - int(c.frame)
				view.frame = int(c.frame)
				c.next = _critter_rng.randf_range(0.4, 1.6)
			var pos: Vector3 = c.pos
			if Vector2(pos.x, pos.z).distance_to(_leader_pos) <= _explore.critter_flee_radius:
				c.state = 1
				c.t = 0.0
				c.dir = 1.0 if pos.x >= _leader_pos.x else -1.0
				# The art faces right.
				view.flip_h = c.dir < 0.0
		1:
			var t := float(c.t)
			var step: Vector3
			match data.kind:
				ZoneCritterData.Kind.CROW:
					step = Vector3(c.dir * _explore.crow_speed, _explore.crow_climb, -_explore.crow_speed * 0.4) * delta
				ZoneCritterData.Kind.FROG:
					step = Vector3(c.dir * _explore.frog_speed * delta, 0.0, 0.0)
				_:
					step = Vector3(c.dir * _explore.rat_speed * delta, 0.0, 0.0)
			c.pos = (c.pos as Vector3) + step
			var pos: Vector3 = c.pos
			var hop := 0.0
			if data.kind == ZoneCritterData.Kind.FROG:
				hop = absf(sin(t * PI / maxf(0.05, _explore.frog_hop_s))) * _explore.frog_hop_height
			view.position = pos + Vector3(0.0, hop, 0.0)
			view.frame = 2 + (int(t / _explore.critter_frame_s) % 2)
			if t >= _explore.critter_away_s:
				c.state = 2
				view.visible = false


# --- every frame ------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _frozen or _paused:
		return
	var dt_ms := delta * 1000.0
	_time_ms += dt_ms
	_pulse_spots()
	if _remote:
		_follow_host(delta)
		_place_walkers(delta)
		_follow_camera(delta)
		_update_marks()
		_update_life(delta)
		return
	var move := bot_move if use_bot else _leader_input()
	var striking := _time_ms < _strike_until_ms
	# The loot pickup (a big timed pose) holds the leader still until it is done.
	var walking := not striking and not _leader.is_busy(FighterView.PRIO_BIG) and move.length() > MOVE_DEADZONE
	_stepping = false
	if walking:
		var step := move.limit_length(1.0) * _tuning.explore_walk_speed * delta
		var before := _leader_pos
		_leader_pos = ZoneMotion.move(_leader_pos, step, LEADER_RADIUS, _obstacles, _zone.bounds_min, _zone.bounds_max)
		_turn(move)
		var moved := before.distance_to(_leader_pos)
		_stepping = moved > step.length() * BLOCKED_SHARE
		if _stepping:
			_advance_walk(moved, delta)
	else:
		_walk_phase = 0.0
	if not striking:
		_pose_leader()

	var calm := _time_ms < _grace_until_ms
	for i: int in _roamers.size():
		var r: Dictionary = _roamers[i]
		if bool(r.defeated):
			continue
		var brain := r.brain as RoamerBrain
		# A champion never chases: it stands by its prize until someone walks into it.
		var velocity := brain.step(dt_ms, r.pos, _leader_pos, _tuning, not calm and not (r.data as ZoneEnemyData).champion)
		_sound_roamer(r)
		if velocity.length() > 0.0:
			var before: Vector2 = r.pos
			r.pos = ZoneMotion.move(r.pos, velocity * delta, ROAMER_RADIUS, _obstacles, _zone.bounds_min, _zone.bounds_max)
			_advance_roamer(r, before.distance_to(r.pos), delta)
			if absf(velocity.x) > 0.05:
				(r.view as FighterView).set_flip((velocity.x > 0.0) == _visuals.enemy_art_faces_left)
		_pose_roamer(r)
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
	_update_life(delta)


func _unhandled_input(event: InputEvent) -> void:
	if _frozen or _paused or _remote or input_held or not is_inside_tree():
		return
	# Pause (Esc / Menu) is Main's: it stops this node and opens the pause menu.
	if event.is_action_pressed(&"field_strike", false, true):
		get_viewport().set_input_as_handled()
		if _players.player_of_device(PlayerRoster.device_of(event)) == 0:
			strike()
	elif event.is_action_pressed(&"field_pickup", false, true) and not _use_hint().is_empty():
		get_viewport().set_input_as_handled()
		if _players.player_of_device(PlayerRoster.device_of(event)) == 0:
			pickup()


## Glinting spots breathe in size; the pick-up hint shows when one is in reach.
func _pulse_spots() -> void:
	var t := fposmod(_time_ms / float(maxi(1, _explore.glint_pulse_ms)), 1.0)
	var size := 1.0 + _explore.glint_pulse_share * 0.5 * (1.0 + sin(t * TAU))
	for spot: Dictionary in _spots:
		(spot.view as Sprite3D).scale = Vector3.ONE * size
	var bob := sin(_time_ms / SEAL_BOB_MS * TAU) * SEAL_BOB
	for seal: Dictionary in _seals:
		(seal.view as Node3D).position.y = bob
	_hud.set_pickup_hint(_use_hint())


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


## The strike's pose, sound and slash (also on the other machines online). The strike is side art,
## swung toward the last side the leader turned to.
func _show_strike() -> void:
	_show_side_art()
	_leader.play_pose(FighterView.CharPose.STRIKE, _tuning.explore_strike_ms)
	Sfx.play("strike")
	var front := _leader_pos + _facing * _explore.strike_slash_distance
	_spawn_slash(Vector3(front.x, SLASH_HEIGHT, front.y))


## Remote: glide toward the host's positions, copy its facing, walking, strikes and enemy states.
func _follow_host(delta: float) -> void:
	if _net.is_empty():
		return
	var taken: Variant = _net.get("p", [])
	if taken is Array and (taken as Array).size() == _spots.size():
		for i: int in _spots.size():
			if bool(taken[i]) and not bool(_spots[i].taken):
				_spots[i].taken = true
				(_spots[i].view as Sprite3D).visible = false
	var opened: Variant = _net.get("c", [])
	if opened is Array and (opened as Array).size() == _chests.size():
		for i: int in _chests.size():
			if bool(opened[i]) and not bool(_chests[i].opened):
				_chests[i].opened = true
				_show_chest_open(i)
	var seals: Variant = _net.get("g", [])
	if seals is Array and (seals as Array).size() == _seals.size():
		for i: int in _seals.size():
			if bool(seals[i]) and not bool(_seals[i].taken):
				take_seal(i)
	var used: Variant = _net.get("o", [])
	if used is Array and (used as Array).size() == _offers.size():
		for i: int in _offers.size():
			if bool(used[i]):
				use_offer(i)
	var prizes: Variant = _net.get("z", [])
	if prizes is Array and (prizes as Array).size() == _prizes.size():
		for i: int in _prizes.size():
			if bool(prizes[i]) and not bool(_prizes[i].opened):
				_prizes[i].opened = true
				_show_prize_open(i)
	var k := 1.0 - exp(-delta * 1000.0 / float(maxi(1, _explore.net_follow_ms)))
	var leader_before := _leader_pos
	_leader_pos = _leader_pos.lerp(Vector2(float(_net.l[0]), float(_net.l[1])), k)
	_turn(Vector2(float(_net.f[0]), float(_net.f[1])))
	var striking := _time_ms < _strike_until_ms
	if int(_net.get("s", 0)) != _strikes:
		_strikes = int(_net.get("s", 0))
		_strike_until_ms = _time_ms + float(_tuning.explore_strike_ms)
		_show_strike()
		striking = true
	# The walk cycle follows this machine's own smoothed positions, so the feet match the glide.
	_stepping = bool(_net.get("w", false)) and not striking
	if _stepping:
		_advance_walk(leader_before.distance_to(_leader_pos), delta)
	else:
		_walk_phase = 0.0
	if not striking:
		_pose_leader()
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
		_sound_roamer(r)
		if absf(target.x - old.x) > 0.001:
			(r.view as FighterView).set_flip((target.x > old.x) == _visuals.enemy_art_faces_left)
		if _is_moving(brain):
			_advance_roamer(r, old.distance_to(r.pos), delta)
		_pose_roamer(r)


## The leader walked `moved` world units this frame: the walk cycle moves on one step per
## walk_stride (or by time with stride 0), and each time a foot comes down (every whole phase,
## the walk clip's contact cells) a step sounds.
func _advance_walk(moved: float, delta: float) -> void:
	var before := floori(_walk_phase)
	if _explore.walk_stride > 0.0:
		_walk_phase = WalkFacing.advance(_walk_phase, moved, _explore.walk_stride)
	else:
		_walk_phase += delta * _explore.walk_bob_hz
	if floori(_walk_phase) > before:
		Sfx.play(_zone.footstep_sfx)


## A roaming enemy walked `moved` world units: its walk cycle (and bob) moves on one step per
## roam_stride (or by time with stride 0).
func _advance_roamer(r: Dictionary, moved: float, delta: float) -> void:
	if _explore.roam_stride > 0.0:
		r.phase = WalkFacing.advance(float(r.phase), moved, _explore.roam_stride)
	else:
		r.phase = float(r.phase) + delta * _explore.roam_bob_hz


func _is_moving(brain: RoamerBrain) -> bool:
	return brain.state in [RoamerBrain.State.WANDER, RoamerBrain.State.CHASE, RoamerBrain.State.RETURN]


## Turns the leader toward ground direction `direction` (zero keeps the facing). The view comes
## from WalkFacing, so a diagonal keeps it; a clear lean left or right also turns the side art.
func _turn(direction: Vector2) -> void:
	if direction.length() <= 0.0001:
		return
	_facing = direction.normalized()
	_view = WalkFacing.pick(_facing, _view, _explore.walk_turn_margin)
	if absf(_facing.x) > SIDE_TURN:
		_side_left = _facing.x < 0.0


## The leader's frame for its view (card #59). Walking: the view's walk clip at the walk phase.
## Standing: the view's stand loop (the idle loop for a side view). A view with no art of its own
## shows the side art toward the last side; only the side art is ever mirrored. With no walk clip
## at all, the old READY / IDLE step flicker.
func _pose_leader() -> void:
	var clip := ("walk_" if _stepping else "stand_") + WalkFacing.SUFFIXES[_view]
	var own_view := not WalkFacing.is_side(_view) and _leader.has_clip(clip)
	if own_view:
		_leader.set_flip(false)
	else:
		clip = "walk_side" if _stepping else ""
		_show_side_art()
	if _stepping:
		var legacy := FighterView.CharPose.READY if fposmod(_walk_phase, 1.0) < 0.5 else FighterView.CharPose.IDLE
		_leader.show_clip(clip, WalkFacing.cycle_index(_leader.clip_count(clip), _walk_phase), legacy)
	elif clip.is_empty():
		_leader.set_pose(FighterView.CharPose.IDLE)
	else:
		_leader.set_loop(clip, _visuals.idle_cycle_ms, FighterView.CharPose.IDLE)


## Mirrors the leader's side art toward the last side it turned to (party art faces right).
func _show_side_art() -> void:
	_leader.set_flip(_side_left == _visuals.party_art_faces_right)


## A roaming enemy's frame (side views only). Wandering and going home: its walk clip; chasing: its
## chase clip, both at its walk phase. Noticing: the wind-up key; pausing: the idle loop. Without
## those clips, the old poses (idle, lunge).
func _pose_roamer(r: Dictionary) -> void:
	var view := r.view as FighterView
	var phase := float(r.phase)
	match (r.brain as RoamerBrain).state:
		RoamerBrain.State.WANDER, RoamerBrain.State.RETURN:
			view.show_clip("walk", WalkFacing.cycle_index(view.clip_count("walk"), phase),
					EnemyChoreography.Pose.IDLE)
		RoamerBrain.State.CHASE:
			view.show_clip("chase", WalkFacing.cycle_index(view.clip_count("chase"), phase),
					EnemyChoreography.Pose.LUNGE)
		RoamerBrain.State.NOTICE:
			view.set_pose(EnemyChoreography.Pose.WINDUP)
		_:
			view.set_pose(EnemyChoreography.Pose.IDLE)


## A roaming enemy's state changed: a sting when it spots the leader, a sigh when it gives up.
func _sound_roamer(r: Dictionary) -> void:
	var state := (r.brain as RoamerBrain).state
	var last := int(r.get("last_state", state))
	r.last_state = state
	if state == last:
		return
	if state == RoamerBrain.State.NOTICE:
		Sfx.play("enemy_notice")
	elif state == RoamerBrain.State.RETURN and last == RoamerBrain.State.CHASE:
		Sfx.play("enemy_give_up")


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
		_show_side_art()
		_leader.play_pose(FighterView.CharPose.HURT, int(TOUCH_PAUSE_S * 1000.0) + _explore.transition_out_ms)
		Sfx.play("alert")
		await get_tree().create_timer(TOUCH_PAUSE_S).timeout
	_hud.set_notice(index, false)
	encounter_started.emit(index, opening)


## Puts every walker's node on its ground spot, with the walking bob.
func _place_walkers(_delta: float) -> void:
	_leader.position = Vector3(_leader_pos.x, 0.0, _leader_pos.y)
	var bob := absf(sin(_walk_phase * PI)) * _explore.walk_bob_height if _stepping else 0.0
	_leader.body_offset = Vector3(0.0, bob, 0.0)
	for r: Dictionary in _roamers:
		if bool(r.defeated):
			continue
		var pos: Vector2 = r.pos
		var view := r.view as FighterView
		view.position = Vector3(pos.x, 0.0, pos.y)
		var moving := _is_moving(r.brain as RoamerBrain)
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
			# The guard is the way out: always marked, in gold.
			var tag := "GUARD: " + encounter_of(i).display_name if _explore.show_roamer_names else "GUARD"
			_hud.set_tag(i, tag, on_screen, screen, HudStyle.GOLD)
		elif (r.data as ZoneEnemyData).champion:
			# A champion (an elite fight, DESIGN.md 8.6) is a choice: marked from a little further away,
			# in its own colour.
			var close := (r.pos as Vector2).distance_to(_leader_pos) <= _tuning.explore_notice_radius * _explore.champion_tag_range
			_hud.set_tag(i, "ELITE", on_screen and close, screen, _explore.champion_color)
		else:
			_hud.set_tag(i, encounter_of(i).display_name, on_screen and near and _explore.show_roamer_names, screen)


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
