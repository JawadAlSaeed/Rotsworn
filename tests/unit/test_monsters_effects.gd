extends GutTest
## Phase 19 "Monsters and effects" (DESIGN.md 2.7, 2.17, cards #245, #252 to #264): the five new
## hero marks (Burn, Shock, Slow, Daze, Hush), the ward and the cleanses (Purify, Antidote, Holy
## Water, Relics against marks), monsters that heal or shield each other, the Pus Tick's burst,
## the area skills, the fights of three and the new monsters' data.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")

const NONE: int = Defense.Outcome.NONE
const PARRY: int = Defense.Outcome.PARRY
const PRESS: int = Defense.Outcome.PRESS
const PERFECT: int = Defense.Outcome.PRESS_PERFECT
const FOE: int = Fx.ENEMY_ID
const SLOW_ENEMY: int = 10
const NEW_MONSTERS: Array[String] = ["rot_rat", "ember_slinger", "barrow_brute", "marsh_lantern", "rot_priest",
		"pus_tick"]


func _calm() -> CombatEngine:
	return Fx.started([Fx.attack("bite", [Fx.hit(900)])], {"enemy_speed": SLOW_ENEMY})


func _mark(engine: CombatEngine, id: int, status: String, turns: int = 2) -> void:
	var events: Array[Dictionary] = []
	engine._add_status(engine.get_combatant(id), status, turns, FOE, events)


## The enemy strikes first with one hit that leaves `status`.
func _marking_fight(status: String, options: Dictionary = {}) -> CombatEngine:
	var h := Fx.hit(900)
	h.on_hit_status = status
	var setup := Fx.setup([Fx.attack("bite", [h])], options)
	if options.has("allow_marks"):
		setup.allow_marks = bool(options.allow_marks)
	var engine := CombatEngine.new(setup)
	engine.start()
	return engine


# --- the new marks ------------------------------------------------------------------------------

func test_the_new_marks_are_hero_debuffs_with_words_colours_and_icons() -> void:
	for id: String in [Status.BURNING, Status.SHOCKED, Status.SLOWED, Status.DAZED, Status.HUSHED]:
		assert_true(Status.is_debuff(id), id)
		assert_true(Status.counts_turns(id), id + " counts down")
		assert_true(HudStyle.STATUS_NAMES.has(id), id + " has a word")
		assert_true(HudStyle.STATUS_COLORS.has(id), id + " has a colour")
		assert_not_null(HudStyle.mark_icon(id), id + " has an icon")
	assert_eq(Status.DEBUFFS.size(), 8)


func test_burning_takes_a_big_share_each_turn_but_never_the_last_hp() -> void:
	var engine := _calm()
	var hero := engine.get_combatant(0)
	_mark(engine, 0, Status.BURNING)
	var events: Array[Dictionary] = []
	engine._start_of_turn(hero, events)
	var expected := CombatMath.percent_min1(hero.max_hp, Tuning.new().burning_percent)
	assert_eq(hero.hp, hero.max_hp - expected)
	assert_eq(String(Fx.first_of(events, "damage").cause), "burning")
	assert_gt(Tuning.new().burning_percent, Tuning.new().rotting_percent, "fire burns hotter than rot")
	hero.hp = 2
	engine._start_of_turn(hero, events)
	engine._start_of_turn(hero, events)
	assert_eq(hero.hp, 1, "fire alone leaves 1 HP")


func test_a_shocked_hero_gets_smaller_defence_windows() -> void:
	var engine := _calm()
	var hero := engine.get_combatant(0)
	var normal := Defense.build_windows(AttackHitData.Kind.NORMAL, Tuning.new())
	assert_eq(engine._windows_for(hero, normal), normal, "no shock, no change")
	_mark(engine, 0, Status.SHOCKED)
	var small := engine._windows_for(hero, normal)
	var pct := Tuning.new().shocked_window_percent
	for outcome: Variant in normal:
		var a: Array = normal[outcome]
		var b: Array = small[outcome]
		assert_eq(int(b[0]), CombatMath.percent(int(a[0]), pct), "early edge shrinks")
		assert_eq(int(b[1]), CombatMath.percent(int(a[1]), pct), "late edge shrinks")
	# The engine uses them on the shocked hero's defend prompts.
	var shocked := _marking_fight("")
	var target := int((shocked.sequence.prompts as Array)[0].character)
	assert_eq((shocked.sequence.prompts as Array)[0].windows, normal, "a calm hero's prompt")
	assert_true(target >= 0)


func test_a_shocked_hero_gets_smaller_skill_press_windows() -> void:
	var cut := Fx.skill("cut", AbilityData.Target.SINGLE_ENEMY, 0, [800])
	var engine := Fx.kit_started([[cut], [cut], [cut]], [Fx.attack("bite", [Fx.hit(900)])], {"enemy_speed": SLOW_ENEMY})
	_mark(engine, engine.active_actor, Status.SHOCKED)
	engine.submit(Fx.use(engine, "cut"))
	var windows: Dictionary = (engine.sequence.prompts as Array)[0].windows
	var normal := Defense.build_windows(AttackHitData.Kind.PRESS, Tuning.new())
	var a: Array = normal[PRESS]
	var b: Array = windows[PRESS]
	assert_lt(int(b[1]) - int(b[0]), int(a[1]) - int(a[0]))


func test_a_dazed_hero_loses_the_next_turn_then_acts_again() -> void:
	var engine := _calm()
	var order := engine.preview_turn_order(3)
	var next := order[1]
	assert_true(engine.get_combatant(next).is_party(), "a hero is next")
	_mark(engine, next, Status.DAZED, 1)
	var events := engine.submit(Fx.use(engine, "basic_attack"))
	var lost := Fx.first_of(events, "turn_lost")
	assert_eq(int(lost.get("actor", -1)), next, "the dazed hero's turn passed")
	assert_false(engine.get_combatant(next).has_status(Status.DAZED), "the daze ends with that turn")
	assert_ne(engine.active_actor, next)


func test_a_hushed_hero_can_only_attack() -> void:
	var cut := Fx.skill("cut", AbilityData.Target.SINGLE_ENEMY, 0, [800])
	var engine := Fx.kit_started([[cut], [cut], [cut]], [Fx.attack("bite", [Fx.hit(900)])], {"enemy_speed": SLOW_ENEMY})
	var actor := engine.active_actor
	_mark(engine, actor, Status.HUSHED)
	assert_false(engine.can_use(actor, "cut"), "no skills")
	assert_true(engine.can_use(actor, "basic_attack"), "the basic attack stays")
	var rejected := engine.submit(Fx.use(engine, "cut"))
	assert_eq(String(Fx.first_of(rejected, "command_rejected").reason), "hushed")
	assert_eq(Fx.of_type(engine.submit(Fx.use(engine, "basic_attack")), "ability_used").size(), 1)


func test_a_slowed_hero_waits_longer_and_a_cleanse_gives_the_speed_back() -> void:
	var engine := _calm()
	var hero := engine.get_combatant(1)
	var speed := hero.speed
	_mark(engine, 1, Status.SLOWED)
	assert_lt(hero.speed, speed, "the mud slows them")
	var events: Array[Dictionary] = []
	engine._cleanse(hero, Status.CLEANSE_ALL, events)
	assert_eq(hero.speed, speed)


func test_an_undefended_hit_leaves_each_new_mark_and_a_defended_one_none() -> void:
	for status: String in [Status.BURNING, Status.SHOCKED, Status.SLOWED, Status.DAZED, Status.HUSHED]:
		var engine := _marking_fight(status)
		var target := int((engine.sequence.prompts as Array)[0].character)
		engine.submit(Fx.resolve_now(engine, [[0, NONE]]))
		assert_true(engine.get_combatant(target).has_status(status), status + " lands")
		engine = _marking_fight(status)
		target = int((engine.sequence.prompts as Array)[0].character)
		engine.submit(Fx.resolve_now(engine, [[0, PARRY]]))
		assert_false(engine.get_combatant(target).has_status(status), status + ": a parry prevents it")


func test_the_first_zone_holds_ordinary_marks_back() -> void:
	var engine := _marking_fight(Status.BURNING, {"allow_marks": false})
	var target := int((engine.sequence.prompts as Array)[0].character)
	assert_false((engine.sequence.hits as Array)[0].has("mark"), "the hit shows no dot")
	engine.submit(Fx.resolve_now(engine, [[0, NONE]]))
	assert_false(engine.get_combatant(target).has_status(Status.BURNING))


# --- ward and cleanses --------------------------------------------------------------------------

func test_a_warded_hero_takes_no_mark() -> void:
	var engine := _marking_fight(Status.BURNING)
	var target := int((engine.sequence.prompts as Array)[0].character)
	_mark(engine, target, Status.WARDED, 2)
	engine.submit(Fx.resolve_now(engine, [[0, NONE]]))
	assert_false(engine.get_combatant(target).has_status(Status.BURNING))


func test_purify_lifts_every_mark_and_wards() -> void:
	var purify := (load("res://data/abilities/purify.tres") as AbilityData).duplicate() as AbilityData
	purify.ap_cost = 0
	var engine := Fx.kit_started([[purify], [purify], [purify]], [Fx.attack("bite", [Fx.hit(900)])],
			{"enemy_speed": SLOW_ENEMY})
	var target := engine.party_ids()[0] if engine.active_actor != engine.party_ids()[0] else engine.party_ids()[1]
	for status: String in Status.DEBUFFS:
		_mark(engine, target, status, 3)
	var targets: Array[int] = [target]
	engine.submit(CombatCommands.use_ability(engine.turn_number, engine.active_actor, "purify", targets))
	engine.submit(Fx.resolve_now(engine, [[0, PRESS]]))
	var hero := engine.get_combatant(target)
	for status: String in Status.DEBUFFS:
		assert_false(hero.has_status(status), status + " lifted")
	assert_true(hero.has_status(Status.WARDED), "and warded")


func test_the_antidote_and_holy_water_lift_marks() -> void:
	var antidote := load("res://data/items/antidote.tres") as ItemData
	var holy := load("res://data/items/holy_water.tres") as ItemData
	assert_true(antidote.usable_in_fight() and holy.usable_in_fight())
	var setup := Fx.setup([Fx.attack("bite", [Fx.hit(900)])], {"enemy_speed": SLOW_ENEMY})
	setup.items.append({"uid": 1, "item": antidote})
	setup.items.append({"uid": 2, "item": holy})
	var engine := CombatEngine.new(setup)
	engine.start()
	for id: int in engine.party_ids():
		_mark(engine, id, Status.BURNING, 3)
		_mark(engine, id, Status.SHOCKED, 3)
	var first := engine.party_ids()[0]
	engine.submit(CombatCommands.use_item(engine.turn_number, engine.active_actor, 1, [first] as Array[int]))
	assert_false(engine.get_combatant(first).has_status(Status.BURNING), "the antidote lifts all of one hero's")
	assert_false(engine.get_combatant(first).has_status(Status.SHOCKED))
	for _i: int in 10:
		if engine.phase == CombatEngine.Phase.AWAITING_ACTION:
			break
		engine.submit(Fx.resolve_now(engine, [[0, PARRY]]))
	engine.submit(CombatCommands.use_item(engine.turn_number, engine.active_actor, 2, [] as Array[int]))
	for id: int in engine.party_ids():
		assert_true(engine.get_combatant(id).statuses.is_empty(), "holy water lifts everyone's (%d)" % id)


func test_relics_against_marks() -> void:
	# Shorter marks.
	var engine := _marking_fight(Status.BURNING)
	var target := int((engine.sequence.prompts as Array)[0].character)
	engine.get_combatant(target).passives[Passive.MARK_SHORTEN] = 1
	engine.submit(Fx.resolve_now(engine, [[0, NONE]]))
	assert_eq(int((engine.get_combatant(target).statuses[Status.BURNING] as Dictionary).turns), 1, "2 turns less 1")
	# A parry shakes a mark off.
	engine = _marking_fight(Status.BURNING)
	target = int((engine.sequence.prompts as Array)[0].character)
	_mark(engine, target, Status.ROTTING, 3)
	engine.get_combatant(target).passives[Passive.PARRY_CLEANSE] = 1
	engine.submit(Fx.resolve_now(engine, [[0, PARRY]]))
	assert_false(engine.get_combatant(target).has_status(Status.ROTTING))
	# Warded from the start.
	var setup := Fx.setup([Fx.attack("bite", [Fx.hit(900)])])
	setup.party_passives.assign([{Passive.WARD_START: 2}, {}, {}])
	engine = CombatEngine.new(setup)
	engine.start()
	assert_true(engine.get_combatant(0).has_status(Status.WARDED))
	for id: String in ["wardstone", "bitter_root", "cleansing_bell"]:
		var relic := load("res://data/gear/%s.tres" % id) as GearData
		assert_not_null(relic, id)
		assert_true(GearData.PASSIVE_KEYS.has(relic.effect), id + " runs in the fight")
		assert_false(GearData.effect_text(relic.effect, relic.amount).is_empty(), id + " says what it does")


# --- monsters helping monsters, the burst ---------------------------------------------------------

func _support(kind: int, below: int = 100) -> EnemyAttackData:
	var a := Fx.attack("help", [])
	a.target_mode = EnemyAttackData.TargetMode.ALLY
	a.support = kind as EnemyAttackData.Support
	a.support_percent = 25
	a.support_below_percent = below
	a.support_turns = 2
	return a


func test_a_healer_heals_the_most_wounded_fellow_and_waits_when_nobody_is_hurt() -> void:
	var healer := Fx.enemy("healer", [_support(EnemyAttackData.Support.HEAL, 75), Fx.attack("poke", [Fx.hit(900)])], 10)
	var brute := Fx.enemy("brute", [Fx.attack("bite", [Fx.hit(900)])], 10)
	var setup := Fx.kit_setup([[], [], []], [], {"enemies": [healer, brute]})
	assert_eq(setup.validate(), PackedStringArray(), "a support move with no hits is valid")
	var engine := CombatEngine.new(setup)
	engine.start()
	var heal_id := "help"
	assert_ne(String((engine.intents[3] as Dictionary).attack), heal_id, "nobody hurt: no heal")
	var b := engine.get_combatant(4)
	b.hp = b.max_hp / 2
	var intent := engine._choose_intent(engine.get_combatant(3))
	# The heal is one of two moves now; whenever it is picked it aims at the brute.
	var heal := engine.get_attack(heal_id)
	assert_eq(engine._pick_targets(engine.get_combatant(3), heal), [4] as Array[int])
	var events: Array[Dictionary] = []
	engine._use_support(engine.get_combatant(3), heal, b, events)
	assert_eq(String(Fx.first_of(events, "enemy_support").type), "enemy_support")
	assert_eq(b.hp, b.max_hp / 2 + CombatMath.percent_min1(b.max_hp, 25))
	assert_true(intent.has("attack"))


func test_a_shield_cuts_the_damage_a_monster_takes() -> void:
	var engine := _calm()
	var foe := engine.get_combatant(FOE)
	var events: Array[Dictionary] = []
	engine._add_status(foe, Status.SHIELDED, 2, FOE, events)
	var hp := foe.hp
	engine._deal_damage(engine.get_combatant(0), foe, 100, "ability", events)
	assert_eq(hp - foe.hp, CombatMath.percent_min1(100, 100 - Tuning.new().shielded_damage_cut_percent))


func test_a_support_move_on_its_turn_heals_and_the_turn_passes() -> void:
	var healer := Fx.enemy("healer", [_support(EnemyAttackData.Support.HEAL)], 500)
	var brute := Fx.enemy("brute", [Fx.attack("bite", [Fx.hit(900)])], 10)
	var engine := CombatEngine.new(Fx.kit_setup([[], [], []], [], {"enemies": [healer, brute]}))
	var events := engine.start()
	var support := Fx.first_of(events, "enemy_support")
	assert_false(support.is_empty(), "the healer used its move")
	assert_true(Fx.of_type(events, "timed_sequence_declared").is_empty(), "no hits to defend")


func test_the_burst_spends_the_attacker() -> void:
	var burst := Fx.attack("burst", [Fx.hit(900, Fx.GROUND)], Fx.PARTY)
	burst.self_destruct = true
	var engine := Fx.started([burst])
	assert_eq(String(engine.sequence.action), "burst")
	var pairs: Array = []
	for i: int in (engine.sequence.prompts as Array).size():
		pairs.append([i, NONE])
	var events := engine.submit(Fx.resolve_now(engine, pairs))
	assert_false(Fx.first_of(events, "self_destructed").is_empty())
	assert_false(engine.get_combatant(FOE).is_alive())
	assert_eq(engine.result, "victory", "its last monster spent itself")


func test_the_shipped_pus_tick_announces_its_burst_like_a_doom() -> void:
	var tick := load("res://data/enemies/pus_tick.tres") as EnemyData
	var burst := load("res://data/enemy_attacks/tick_burst.tres") as EnemyAttackData
	assert_true(tick.attacks.has(burst))
	assert_true(burst.is_doom() and burst.self_destruct)
	assert_eq(burst.hits[0].kind, AttackHitData.Kind.GROUND, "jump the burst")


# --- skills, fights and data ----------------------------------------------------------------------

func test_the_area_skills_hit_every_enemy() -> void:
	for id: String in ["fang_storm", "radiance", "earthshaker"]:
		var a := load("res://data/abilities/%s.tres" % id) as AbilityData
		assert_eq(a.target, AbilityData.Target.ALL_ENEMIES, id)
	var brin := load("res://data/characters/brin.tres") as CharacterData
	var cass := load("res://data/characters/cass.tres") as CharacterData
	assert_true(brin.skill_tree.all_skills().has(load("res://data/abilities/fang_storm.tres")))
	assert_true(cass.skill_tree.all_skills().has(load("res://data/abilities/radiance.tres")))
	assert_true(cass.skill_tree.all_skills().has(load("res://data/abilities/purify.tres")))


func test_a_fight_of_three_spreads_its_hp() -> void:
	var trio := load("res://data/encounters/priest_coven.tres") as EncounterData
	assert_eq(trio.enemies.size(), 3)
	assert_lt(trio.enemy_hp_percent, 100)
	var setup := CombatSetup.from_encounter(trio, Tuning.new(), 1)
	assert_eq(setup.enemy_hp_percent, trio.enemy_hp_percent)


func test_every_zone_and_guard_has_a_fight_of_three() -> void:
	var run := load("res://data/runs/rotten_road.tres") as RunData
	for zone: ZoneData in run.zones:
		var trios := 0
		var guard_trio := false
		for encounter: EncounterData in ZoneAssembler.encounters(zone):
			if encounter.enemies.size() == 3:
				trios += 1
				guard_trio = guard_trio or encounter.mini_boss
		assert_gt(trios, 1, zone.id + ": fights of three")
		assert_true(guard_trio, zone.id + ": the guard brings two helpers")


func test_the_new_monsters_each_have_one_marking_move_and_drops() -> void:
	for id: String in NEW_MONSTERS:
		var e := load("res://data/enemies/%s.tres" % id) as EnemyData
		assert_not_null(e, id)
		assert_false(e.relic_drops.is_empty(), id + " drops Relics")
		var marking := 0
		for a: EnemyAttackData in e.attacks:
			for h: AttackHitData in a.hits:
				if h.marks_in(false):
					marking += 1
		assert_eq(marking, 1, id + ": one mark hit")
		assert_true(ResourceLoader.exists(e.sprite_path), id + ": sheet")
		assert_true(ResourceLoader.exists(e.portrait_path), id + ": portrait")


func test_the_slinger_only_throws_and_the_brute_is_slow_and_heavy() -> void:
	var slinger := load("res://data/enemies/ember_slinger.tres") as EnemyData
	for a: EnemyAttackData in slinger.attacks:
		for h: AttackHitData in a.hits:
			assert_not_null(h.projectile, a.id + ": a throw")
	var brute := load("res://data/enemies/barrow_brute.tres") as EnemyData
	var rat := load("res://data/enemies/rot_rat.tres") as EnemyData
	assert_lt(brute.speed, 80, "slow")
	assert_gt(brute.power_percent, 150, "hits hard")
	assert_gt(rat.speed, 200, "small fry are quick")
	assert_lt(rat.hp_percent, 50, "and frail")


# --- the stage (user, phase 19) -----------------------------------------------------------------

func test_big_monsters_stand_farthest_from_the_camera() -> void:
	var spots: Array[Vector3] = [Vector3(2.6, 0.0, 0.0), Vector3(3.8, 0.0, 1.6), Vector3(3.8, 0.0, -1.6)]
	# A small rat, a huge brute, a middling husk: the brute goes to the back, the rat to the front.
	var heights: Array[float] = [2.0, 5.4, 3.2]
	assert_eq(CombatView.enemy_spots(heights, spots), [1, 2, 0] as Array[int])
	# Two monsters use the first two spots: the bigger one on the farther of them.
	var pair: Array[float] = [2.0, 5.0]
	assert_eq(CombatView.enemy_spots(pair, spots), [1, 0] as Array[int])
	var same: Array[float] = [3.0, 3.0, 3.0]
	assert_eq(CombatView.enemy_spots(same, spots), [0, 1, 2] as Array[int], "all one size: nobody moves")


func test_tall_monsters_measure_taller_than_small_ones() -> void:
	var tall := {}
	for id: String in ["barrow_brute", "rot_priest", "rotten_husk", "rot_rat"]:
		tall[id] = CombatView.enemy_height(load("res://data/enemies/%s.tres" % id) as EnemyData)
	assert_gt(float(tall.barrow_brute), float(tall.rot_priest), "the brute is the tallest")
	assert_gt(float(tall.rot_priest), float(tall.rotten_husk), "the upright priest over the hunched husk")
	assert_gt(float(tall.rotten_husk), float(tall.rot_rat))
