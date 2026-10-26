extends GutTest
## The Leech Queen (DESIGN.md 8.23, card #323): her drinking bites (EnemyAttackData.drain_percent, a
## rule of the core), her data and her Leechlings. Where she sits in the run is in test_run_stops.gd
## and test_run_balance.gd.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")

const NONE: int = Defense.Outcome.NONE
const DODGE: int = Defense.Outcome.DODGE
const PARRY: int = Defense.Outcome.PARRY
const FOE: int = Fx.ENEMY_ID
const QUEEN_PATH := "res://data/enemies/leech_queen.tres"
const LEECHLING_PATH := "res://data/enemies/leechling.tres"
const FIGHT_PATH := "res://data/encounters/leech_queen_fight.tres"
const LORD_PATH := "res://data/enemies/husk_lord.tres"
const KING_PATH := "res://data/enemies/hollow_king.tres"


## A drinking bite of `hits` plain hits, 600 ms apart.
func _bite(pct: int, hits: int = 1) -> EnemyAttackData:
	var list: Array = []
	for i: int in hits:
		list.append(Fx.hit(900 + 600 * i))
	var attack := Fx.attack("bite", list)
	attack.drain_percent = pct
	return attack


## The foe acts first with `attack`, already down to half its HP (`full`: untouched).
func _fight(attack: EnemyAttackData, full: bool = false, passives: Dictionary = {}, options: Dictionary = {}) -> CombatEngine:
	var setup := Fx.setup([attack], options)
	for i: int in 3:
		setup.party_passives.append(passives.duplicate())
	var engine := CombatEngine.new(setup)
	engine.start()
	if not full:
		var foe := engine.get_combatant(FOE)
		foe.hp = maxi(1, foe.max_hp / 2)
	return engine


func _hero(engine: CombatEngine) -> Combatant:
	return engine.get_combatant(int((engine.sequence.targets as Array)[0]))


func _drinks(events: Array[Dictionary]) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for e: Dictionary in Fx.of_type(events, "healed"):
		if String(e.get("cause", "")) == CombatEngine.CAUSE_DRAIN:
			list.append(e)
	return list


# --- the drinking bite (the core rule) -----------------------------------------------------------

func test_an_undefended_drinking_hit_heals_the_attacker_a_share_of_what_it_took() -> void:
	var engine := _fight(_bite(50))
	var foe := engine.get_combatant(FOE)
	var hero := _hero(engine)
	var foe_before := foe.hp
	var hero_before := hero.hp
	var events := engine.submit(Fx.resolve_now(engine, [[0, NONE]]))
	var lost := hero_before - hero.hp
	assert_gt(lost, 0, "the bite landed")
	var drinks := _drinks(events)
	assert_eq(drinks.size(), 1, "one drink for one hit")
	var expected := mini(foe.max_hp - foe_before, CombatMath.percent_min1(lost, 50))
	assert_gt(expected, 0)
	assert_eq(int(drinks[0].amount), expected, "half of what the hero lost")
	assert_eq(int(drinks[0].source), FOE, "she heals herself")
	assert_eq(int(drinks[0].target), FOE)
	assert_eq(int(drinks[0].hp), foe.hp)
	assert_eq(foe.hp, foe_before + expected)
	assert_lt(Fx.index_of(events, "prompt_resolved"), Fx.index_of(events, "healed"), "the drink follows the bite")


func test_the_prompts_of_a_drinking_move_carry_its_percent_and_others_carry_none() -> void:
	var declared := Fx.declared_attack(_bite(40, 2))
	assert_false(declared.is_empty())
	for p: Dictionary in declared.prompts:
		assert_eq(int(p.get("drain", 0)), 40, "every defend prompt says how much it drinks")
	var plain := Fx.declared_attack(Fx.attack("swipe", [Fx.hit(900)]))
	for p: Dictionary in plain.prompts:
		assert_false(p.has("drain"), "an ordinary move's prompts have no drain")
	assert_true(_bite(1).drains())
	assert_false(Fx.attack("swipe", [Fx.hit(900)]).drains())


func test_a_defended_hit_drinks_nothing() -> void:
	for outcome: int in [DODGE, PARRY]:
		var engine := _fight(_bite(80))
		var events := engine.submit(Fx.resolve_now(engine, [[0, outcome]]))
		assert_true(_drinks(events).is_empty(), "outcome %d: nothing taken, nothing drunk" % outcome)


func test_at_full_hp_she_drinks_nothing() -> void:
	var engine := _fight(_bite(80), true)
	var foe := engine.get_combatant(FOE)
	var events := engine.submit(Fx.resolve_now(engine, [[0, NONE]]))
	assert_true(Fx.of_type(events, "healed").is_empty(), "no heal event at full HP")
	assert_eq(foe.hp, foe.max_hp)


func test_a_drink_never_lifts_her_above_her_max_hp() -> void:
	var engine := _fight(_bite(100), true)
	var foe := engine.get_combatant(FOE)
	foe.hp = foe.max_hp - 1
	var events := engine.submit(Fx.resolve_now(engine, [[0, NONE]]))
	var drinks := _drinks(events)
	assert_eq(drinks.size(), 1)
	assert_eq(int(drinks[0].amount), 1, "only the one HP she was missing")
	assert_eq(foe.hp, foe.max_hp)


func test_a_tiny_share_still_drinks_one() -> void:
	var engine := _fight(_bite(1))
	var events := engine.submit(Fx.resolve_now(engine, [[0, NONE]]))
	var drinks := _drinks(events)
	assert_eq(drinks.size(), 1)
	assert_eq(int(drinks[0].amount), 1, "at least 1, like every percent of a hit")


func test_each_hit_of_a_string_drinks_on_its_own() -> void:
	var engine := _fight(_bite(50, 3))
	var events := engine.submit(Fx.resolve_now(engine, [[0, NONE], [1, DODGE], [2, NONE]]))
	assert_eq(_drinks(events).size(), 2, "two hits landed, two drinks")


func test_a_hit_that_downs_a_hero_drinks_what_the_hero_had_left() -> void:
	var engine := _fight(_bite(100), false, {}, {"hp_percents": [1, 1, 1]})
	var hero := _hero(engine)
	var had := hero.hp
	var damage := int((engine.sequence.prompts as Array)[0].damage)
	assert_gt(damage, had, "the bite is bigger than the hero's HP")
	var events := engine.submit(Fx.resolve_now(engine, [[0, NONE]]))
	assert_false(hero.is_alive())
	var drinks := _drinks(events)
	assert_eq(drinks.size(), 1)
	assert_eq(int(drinks[0].amount), had, "she drinks the HP taken, not the hit's size")


func test_an_attacker_killed_by_thorns_drinks_nothing() -> void:
	var engine := _fight(_bite(100), false, {Passive.THORNS: 100})
	engine.get_combatant(FOE).hp = 1
	var events := engine.submit(Fx.resolve_now(engine, [[0, NONE]]))
	assert_false(engine.get_combatant(FOE).is_alive(), "the thorns killed her")
	assert_true(_drinks(events).is_empty(), "the dead drink nothing")


func test_a_blighted_attacker_drinks_less() -> void:
	var clean := _fight(_bite(100))
	var clean_drinks := _drinks(clean.submit(Fx.resolve_now(clean, [[0, NONE]])))
	var cut := _fight(_bite(100))
	var events: Array[Dictionary] = []
	cut._add_status(cut.get_combatant(FOE), Status.BLIGHTED, 3, -1, events)
	var cut_drinks := _drinks(cut.submit(Fx.resolve_now(cut, [[0, NONE]])))
	assert_eq(clean_drinks.size(), 1)
	assert_eq(cut_drinks.size(), 1)
	assert_lt(int(cut_drinks[0].amount), int(clean_drinks[0].amount), "Blighted cuts every heal, hers too")


func test_an_ordinary_heal_says_no_cause() -> void:
	var heal := Fx.attack("help", [])
	heal.target_mode = EnemyAttackData.TargetMode.ALLY
	heal.support = EnemyAttackData.Support.HEAL
	heal.support_percent = 20
	heal.support_below_percent = 100
	var healer := Fx.enemy("healer", [heal], 500)
	var brute := Fx.enemy("brute", [Fx.attack("swipe", [Fx.hit(900)])], 10)
	var engine := CombatEngine.new(Fx.kit_setup([[], [], []], [], {"enemies": [healer, brute]}))
	var events := engine.start()
	var heals := Fx.of_type(events, "healed")
	for e: Dictionary in heals:
		assert_false(e.has("cause"), "only a drink names its cause")


func test_the_mirror_follows_a_drink() -> void:
	var engine := CombatEngine.new(Fx.setup([_bite(50)]))
	var mirror := CombatMirror.new()
	for e: Dictionary in engine.start():
		mirror.apply(e)
	var foe := engine.get_combatant(FOE)
	foe.hp = foe.max_hp / 2
	var events := engine.submit(Fx.resolve_now(engine, [[0, NONE]]))
	assert_eq(_drinks(events).size(), 1)
	for e: Dictionary in events:
		mirror.apply(e)
	assert_gt(foe.hp, foe.max_hp / 2, "she drank")
	assert_eq(int(mirror.fighter(FOE).hp), foe.hp, "the screen shows her new HP")


func test_drinking_is_deterministic() -> void:
	var runs: Array = []
	for _i: int in 2:
		var engine := _fight(_bite(60, 3), false, {}, {"seed": 9})
		var events := engine.submit(Fx.resolve_now(engine, [[0, NONE], [1, NONE], [2, PARRY]]))
		runs.append(var_to_str(events))
	assert_eq(runs[0], runs[1], "same seed, same presses, same drinks")


# --- her data -----------------------------------------------------------------------------------

func test_the_queen_has_two_phases_her_hunger_and_a_doom() -> void:
	var queen := load(QUEEN_PATH) as EnemyData
	assert_eq(queen.id, "leech_queen")
	assert_eq(queen.display_name, "The Leech Queen")
	assert_eq(queen.phase_two_text, "THE LEECH QUEEN HUNGERS!")
	assert_gt(queen.phase_two_hp_percent, 0, "she has a phase two")
	assert_gt(queen.phase_two_speed, queen.speed, "she hungers faster")
	var first := {}
	for attack: EnemyAttackData in queen.attacks:
		first[attack.id] = attack
	var new_moves := 0
	for attack: EnemyAttackData in queen.phase_two_attacks:
		if not first.has(attack.id):
			new_moves += 1
	assert_gt(new_moves, 0, "phase two brings new moves")
	for list: Array[EnemyAttackData] in [queen.attacks, queen.phase_two_attacks]:
		var dooms := list.filter(func(a: EnemyAttackData) -> bool: return a.is_doom())
		assert_eq(dooms.size(), 1, "one Doom in each phase")
		assert_gt(list.filter(func(a: EnemyAttackData) -> bool: return a.drains()).size(), 0, "she drinks in each phase")
	assert_false(queen.relic_drops.is_empty(), "she drops Relics like the other bosses")
	assert_true(FileAccess.file_exists(queen.sprite_path), "her picture")
	assert_true(FileAccess.file_exists(queen.portrait_path), "her portrait")
	assert_not_null(queen.sprite_clips, "her animation layout")


func test_her_moves_cover_every_kind_of_defence() -> void:
	var queen := load(QUEEN_PATH) as EnemyData
	var kinds := {}
	var marks := {}
	var thrown := false
	var tail := false
	for attack: EnemyAttackData in queen.all_attacks():
		for hit: AttackHitData in attack.hits:
			kinds[hit.kind] = true
			if not hit.on_hit_status.is_empty():
				marks[hit.on_hit_status] = true
			if hit.projectile != null:
				thrown = true
			if hit.anim == "tail":
				tail = true
	assert_true(kinds.has(AttackHitData.Kind.NORMAL), "bites to dodge or parry")
	assert_true(kinds.has(AttackHitData.Kind.GROUND), "Black Water to jump")
	assert_true(kinds.has(AttackHitData.Kind.SWEEP), "the tail sweep to dodge")
	assert_true(marks.has(Status.BLIGHTED), "her spit blights")
	assert_true(thrown, "her spit is thrown")
	assert_true(tail, "the tail moves play the tail clip")


func test_the_leechlings_are_small_quick_and_bite() -> void:
	var leechling := load(LEECHLING_PATH) as EnemyData
	var queen := load(QUEEN_PATH) as EnemyData
	assert_lt(leechling.hp_percent, queen.hp_percent / 5, "small")
	assert_gt(leechling.speed, queen.speed, "quick")
	assert_eq(leechling.phase_two_hp_percent, 0, "no phase two")
	assert_false(leechling.attacks.is_empty())
	assert_true(FileAccess.file_exists(leechling.sprite_path))
	assert_not_null(leechling.sprite_clips)


func test_her_fight_is_a_boss_fight_with_two_leechlings() -> void:
	var fight := load(FIGHT_PATH) as EncounterData
	assert_true(fight.boss)
	assert_false(fight.can_run, "no running from a boss")
	assert_eq(fight.display_name, "The Leech Queen")
	var ids: Array[String] = []
	for enemy: EnemyData in fight.enemies:
		ids.append(enemy.id)
	assert_eq(ids, ["leech_queen", "leechling", "leechling"] as Array[String])


func test_her_hp_and_power_sit_between_the_lord_and_the_king() -> void:
	var lord := load(LORD_PATH) as EnemyData
	var queen := load(QUEEN_PATH) as EnemyData
	var king := load(KING_PATH) as EnemyData
	assert_between(queen.hp_percent, lord.hp_percent + 1, king.hp_percent - 1)
	assert_between(queen.power_percent, lord.power_percent, king.power_percent)
	# The King ends the run, so he pays nothing; she pays more than the Lord.
	assert_gte(queen.gold, lord.gold)
	assert_gte(queen.xp, lord.xp)
