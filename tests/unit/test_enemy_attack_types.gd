extends GutTest
## Phase 12 attack types (DESIGN 3.9 to 3.11): each-in-turn targeting in the engine (one target per
## hit, in party order from a random hero, never more targets than hits, a team counter when every
## target was perfect), ranged hits in the choreography (no lunge: a throw at the launch moment,
## then waiting while it flies), the throw clips' fallbacks, the data rules for projectiles,
## ground looks and each-in-turn attacks, and the intent text that names the order.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")
const ATTACK_DIR := "res://data/enemy_attacks"
const PROJECTILE_DIR := "res://data/projectiles"
const EACH: int = EnemyAttackData.TargetMode.EACH
const PARRY: int = Defense.Outcome.PARRY
const DODGE: int = Defense.Outcome.DODGE
## A projectile must fly at least this long to be read (attack ms at tempo 100%).
const MIN_FLIGHT_MS: int = 300
const EPS: float = 0.001

var _visuals := CombatVisuals.new()


func _bite(hit_count: int) -> EnemyAttackData:
	var hits: Array = []
	for i: int in hit_count:
		hits.append(Fx.hit(900 + i * 400, Fx.NORMAL, 40))
	return Fx.attack("bite", hits, EACH)


# --- each hero in turn --------------------------------------------------------------------------

func test_each_in_turn_gives_every_hit_one_target_in_party_order() -> void:
	for rng_seed: int in range(1, 9):
		var engine := CombatEngine.new(Fx.setup([_bite(3)], {"seed": rng_seed}))
		var declared := Fx.first_of(engine.start(), "timed_sequence_declared")
		var targets: Array = declared.targets
		assert_eq(targets.size(), 3, "three standing heroes, three bites")
		var sorted := targets.duplicate()
		sorted.sort()
		assert_eq(sorted, [0, 1, 2], "every hero once")
		# Party order from the first one on (wrapping round).
		for i: int in range(1, 3):
			assert_eq(int(targets[i]), (int(targets[0]) + i) % 3, "seed %d: in party order" % rng_seed)
		var prompts: Array = declared.prompts
		assert_eq(prompts.size(), 3, "one prompt per hit")
		for p: Dictionary in prompts:
			assert_eq(int(p.character), int(targets[int(p.hit)]), "hit %d strikes its own target" % int(p.hit))


func test_each_in_turn_bites_no_more_heroes_than_it_has_hits() -> void:
	var engine := CombatEngine.new(Fx.setup([_bite(2)]))
	var declared := Fx.first_of(engine.start(), "timed_sequence_declared")
	assert_eq((declared.targets as Array).size(), 2)
	assert_eq((declared.prompts as Array).size(), 2)


func test_each_in_turn_wraps_round_when_it_has_more_hits_than_heroes() -> void:
	var engine := CombatEngine.new(Fx.setup([_bite(5)]))
	var declared := Fx.first_of(engine.start(), "timed_sequence_declared")
	var targets: Array = declared.targets
	var prompts: Array = declared.prompts
	assert_eq(prompts.size(), 5)
	for p: Dictionary in prompts:
		assert_eq(int(p.character), int(targets[int(p.hit) % targets.size()]))


func test_each_in_turn_all_perfect_gives_a_team_counter() -> void:
	var engine := Fx.started([_bite(3)])
	var events := engine.submit(Fx.resolve_now(engine, [[0, PARRY], [1, PARRY], [2, PARRY]]))
	var counters := Fx.of_type(events, "counter")
	assert_eq(counters.size(), 1)
	assert_true(bool(counters[0].team), "every hero parried their own bite: one team counter")


func test_each_in_turn_partly_perfect_gives_solo_counters() -> void:
	var engine := Fx.started([_bite(3)])
	var parrier := int((engine.sequence.prompts as Array)[1].character)
	var events := engine.submit(Fx.resolve_now(engine, [[0, DODGE], [1, PARRY], [2, DODGE]]))
	var counters := Fx.of_type(events, "counter")
	assert_eq(counters.size(), 1, "only the hero who parried counters")
	assert_false(bool(counters[0].team))
	assert_eq(counters[0].actors, [parrier])


func test_each_in_turn_stays_deterministic() -> void:
	var a := CombatEngine.new(Fx.setup([_bite(3)], {"seed": 4})).start()
	var b := CombatEngine.new(Fx.setup([_bite(3)], {"seed": 4})).start()
	assert_eq(a, b)


func test_intent_text_names_the_order() -> void:
	var engine := Fx.started([_bite(3)])
	var mirror := CombatMirror.new()
	for ev: Dictionary in CombatEngine.new(Fx.setup([_bite(3)])).start():
		mirror.apply(ev)
	var targets: Array = engine.sequence.targets
	var names := PackedStringArray()
	for id: Variant in targets:
		names.append(String(mirror.fighter(int(id)).get("display_name", "?")).to_upper())
	assert_eq(CombatHud.target_text(mirror, EACH, targets), " > ".join(names))
	assert_eq(CombatHud.target_text(mirror, EnemyAttackData.TargetMode.PARTY, targets), "WHOLE PARTY")
	assert_eq(CombatHud.target_text(mirror, EnemyAttackData.TargetMode.SINGLE, [targets[0]]), names[0])


# --- ranged hits --------------------------------------------------------------------------------

## A hit dictionary as the runner holds it.
func _hit(at_ms: float, approach_ms: float, ranged: bool, kind: int = AttackHitData.Kind.NORMAL) -> Dictionary:
	return {"at_ms": at_ms, "kind": kind, "approach_ms": approach_ms, "feint": false, "close_ms": 120.0,
			"ranged": ranged, "anim": ""}


func test_a_ranged_hit_throws_at_launch_and_never_lunges() -> void:
	var hits := [_hit(1200.0, 500.0, true)]
	var t := -10.0
	while t < 2500.0:
		var s := EnemyChoreography.sample(hits, t, _visuals)
		assert_almost_eq(float(s.approach), 0.0, EPS, "at %.0f ms the enemy stays home" % t)
		t += 5.0
	var cues := EnemyChoreography.cues(hits, _visuals)
	assert_eq(cues.size(), 1)
	assert_eq(String(cues[0].type), EnemyChoreography.CUE_SHOOT)
	assert_almost_eq(float(cues[0].at_ms), 700.0, EPS, "it leaves approach_ms before impact")
	var throw := EnemyChoreography.sample(hits, 700.0, _visuals)
	assert_eq(int(throw.beat), EnemyChoreography.Beat.SHOOT)
	assert_eq(int(throw.pose), EnemyChoreography.Pose.CONTACT)
	var flying := EnemyChoreography.sample(hits, 700.0 + float(_visuals.shoot_hold_ms) + 1.0, _visuals)
	assert_eq(int(flying.beat), EnemyChoreography.Beat.FLIGHT)
	assert_eq(int(EnemyChoreography.sample(hits, 1300.0, _visuals).beat), EnemyChoreography.Beat.AFTER,
			"home and idle once it has landed")


func test_a_ranged_hit_after_a_lunge_throws_from_where_the_enemy_recoiled() -> void:
	var hits := [_hit(900.0, 200.0, false), _hit(1600.0, 450.0, true)]
	var recoiled := 1.0 - float(_visuals.recoil_percent) / 100.0
	var throw := EnemyChoreography.sample(hits, 1150.0, _visuals)
	assert_eq(int(throw.beat), EnemyChoreography.Beat.SHOOT)
	assert_almost_eq(float(throw.approach), recoiled, EPS, "it throws from its recoil spot")
	var home := EnemyChoreography.sample(hits, 1600.0 + float(_visuals.return_ms) + 5.0, _visuals)
	assert_almost_eq(float(home.approach), 0.0, EPS, "then walks home")


func test_throw_clips_fall_back_to_the_lunge_set() -> void:
	assert_eq(ClipNames.next("shoot"), "contact")
	assert_eq(ClipNames.next("windup_shoot"), "windup")
	var clips := SpriteClips.new()
	clips.frame_size = Vector2i(8, 8)
	clips.hframes = 8
	clips.vframes = 1
	clips.clips = {"windup": PackedInt32Array([1]), "contact": PackedInt32Array([3])}
	assert_eq(ClipNames.resolve(clips, "spit_shoot"), "contact")
	assert_eq(ClipNames.resolve(clips, "windup_shoot"), "windup")


# --- data rules ---------------------------------------------------------------------------------

func _shipped_attacks() -> Array[EnemyAttackData]:
	var list: Array[EnemyAttackData] = []
	for file: String in DirAccess.get_files_at(ATTACK_DIR):
		if file.ends_with(".tres"):
			list.append(load(ATTACK_DIR.path_join(file)) as EnemyAttackData)
	return list


func test_shipped_projectiles_are_complete() -> void:
	var library := load("res://data/audio/sfx_library.tres") as SfxLibrary
	var count := 0
	for file: String in DirAccess.get_files_at(PROJECTILE_DIR):
		if not file.ends_with(".tres"):
			continue
		var p := load(PROJECTILE_DIR.path_join(file)) as ProjectileData
		assert_not_null(p, file)
		assert_eq(p.id + ".tres", file, "the id matches the file name")
		assert_true(ResourceLoader.exists(p.texture_path), p.id + ": its sprite exists")
		assert_gt(p.hframes, 0, p.id)
		for cue: String in [p.launch_sfx, p.hit_sfx]:
			if not cue.is_empty():
				assert_not_null(library.find(cue), "%s plays cue '%s', which the sfx library defines" % [p.id, cue])
		count += 1
	assert_gt(count, 2, "phase 12 ships projectiles")


func test_ranged_rocks_and_each_in_turn_follow_the_rules() -> void:
	var tuning := Tuning.new()
	var ranged := 0
	var rocks := 0
	var each := 0
	for attack: EnemyAttackData in _shipped_attacks():
		var declared := Fx.first_of(CombatEngine.new(Fx.setup([attack])).start(), "timed_sequence_declared")
		var hits := EnemyChoreography.with_close_times(declared.hits as Array, declared.prompts as Array, 0)
		EnemyChoreography.add_hit_data(hits, attack)
		if attack.target_mode == EACH:
			each += 1
		for i: int in attack.hits.size():
			var hit := attack.hits[i]
			var label := "%s hit %d" % [attack.id, i]
			if attack.target_mode == EACH:
				assert_eq(hit.kind, AttackHitData.Kind.NORMAL, label + ": each-in-turn attacks have normal hits only")
			if hit.ground_look != AttackHitData.GroundLook.WAVE:
				rocks += 1
				assert_eq(hit.kind, AttackHitData.Kind.GROUND, label + ": a ground look on a ground hit")
			if hit.projectile == null:
				continue
			ranged += 1
			assert_eq(hit.kind, AttackHitData.Kind.NORMAL, label + ": only normal hits are thrown")
			assert_false(hit.feint, label + ": a throw is never a feint")
			var flight := float(hits[i].at_ms) - EnemyChoreography.motion_start(hits, i, _visuals)
			assert_gte(flight, float(CombatMath.percent(MIN_FLIGHT_MS, tuning.attack_tempo_percent)),
					label + ": flies long enough to read")
	assert_gt(ranged, 0, "shipped ranged hits")
	assert_gt(rocks, 0, "shipped rock hits")
	assert_gt(each, 0, "shipped each-in-turn attacks")
