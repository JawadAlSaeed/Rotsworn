extends GutTest
## Phase 13 step 2 skills (DESIGN.md 8.4): party-wide skills, Twin Fangs, Bleeding, Renew,
## Marked, Empowered and Unbreakable. The shipped skills at 0 AP without follow-ups, in fixture
## fights where the party acts first.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")

const PRESS: int = Defense.Outcome.PRESS
const PERFECT: int = Defense.Outcome.PRESS_PERFECT
const FOE: int = Fx.ENEMY_ID
const SLOW_ENEMY: int = 10
const SKILLS: Array[String] = ["shield_wall", "sanctuary", "inspire", "twin_fangs", "shadowstep", "unbreakable",
	"death_mark", "earthshaker"]


func _skill(id: String) -> AbilityData:
	var ability := (load("res://data/abilities/%s.tres" % id) as AbilityData).duplicate() as AbilityData
	ability.ap_cost = 0
	ability.follow_ups = false
	return ability


func _engine(options: Dictionary = {}) -> CombatEngine:
	var kit: Array = []
	for id: String in SKILLS:
		kit.append(_skill(id))
	kit.append(Fx.skill("cut", AbilityData.Target.SINGLE_ENEMY, 0, [800], {"damage_percent": 100}))
	var o := {"enemy_speed": SLOW_ENEMY}
	o.merge(options, true)
	var setup := Fx.kit_setup([kit, kit, kit], [Fx.attack("swipe", [Fx.hit(900)])], o)
	if options.has("start_hp"):
		setup.party_start_hp.assign(options.start_hp)
	var engine := CombatEngine.new(setup)
	engine.start()
	return engine


func _use(engine: CombatEngine, id: String, pairs: Array) -> Array[Dictionary]:
	engine.submit(Fx.use(engine, id, FOE))
	return engine.submit(Fx.resolve_now(engine, pairs))


func test_shield_wall_guards_the_whole_party() -> void:
	var engine := _engine()
	var events := _use(engine, "shield_wall", [[0, PRESS]])
	var guarded: Array[int] = []
	for e: Dictionary in Fx.of_type(events, "status_changed"):
		if String(e.status) == Status.GUARDED and bool(e.active):
			guarded.append(int(e.target))
	# Each guard lasts until that hero's own next turn (the next hero's starts at once).
	for id: int in engine.party_ids():
		assert_true(guarded.has(id), "hero %d guarded" % id)


func test_sanctuary_heals_everyone() -> void:
	var engine := _engine({"start_hp": [10, 10, 10]})
	_use(engine, "sanctuary", [[0, PRESS]])
	for id: int in engine.party_ids():
		var c := engine.get_combatant(id)
		assert_eq(c.hp, 10 + CombatMath.percent_min1(c.max_hp, 30), "hero %d healed 30%%" % id)


func test_inspire_gives_everyone_ap_and_fills_the_gauge() -> void:
	var engine := _engine()
	var before: Array[int] = []
	for id: int in engine.party_ids():
		before.append(engine.get_combatant(id).ap)
	_use(engine, "inspire", [[0, PRESS]])
	for i: int in engine.party_ids().size():
		assert_eq(engine.get_combatant(engine.party_ids()[i]).ap, mini(before[i] + 1, Tuning.new().max_ap))
	assert_eq(engine.team_gauge, 25)


func test_twin_fangs_exposes_only_on_a_perfect_pair() -> void:
	var engine := _engine()
	_use(engine, "twin_fangs", [[0, PERFECT], [1, PRESS]])
	assert_false(engine.get_combatant(FOE).has_status(Status.EXPOSED), "one good press is not enough")
	engine = _engine()
	_use(engine, "twin_fangs", [[0, PERFECT], [1, PERFECT]])
	assert_true(engine.get_combatant(FOE).has_status(Status.EXPOSED))


func test_bleeding_hurts_at_the_start_of_the_enemys_turn() -> void:
	var engine := _engine()
	var brin := engine.get_combatant(engine.party_ids()[1])
	var foe := engine.get_combatant(FOE)
	var events: Array[Dictionary] = []
	engine._add_status(foe, Status.BLEEDING, 3, brin.id, events)
	events.clear()
	var hp := foe.hp
	engine._start_of_turn(foe, events)
	var bleed := Fx.first_of(events, "damage")
	assert_eq(String(bleed.cause), "bleed")
	assert_eq(int(bleed.amount), CombatMath.percent_min1(brin.power, Tuning.new().bleed_power_percent))
	assert_eq(foe.hp, hp - int(bleed.amount))


func test_renew_heals_at_the_start_of_the_heros_turn() -> void:
	var engine := _engine({"start_hp": [10, 10, 10]})
	var hero := engine.get_combatant(engine.party_ids()[0])
	var events: Array[Dictionary] = []
	engine._add_status(hero, Status.REGEN, 3, engine.party_ids()[2], events)
	events.clear()
	engine._start_of_turn(hero, events)
	assert_eq(hero.hp, 10 + CombatMath.percent_min1(hero.max_hp, Tuning.new().regen_percent))


func test_marked_adds_damage_and_wears_off_with_use() -> void:
	var plain := _engine()
	plain.submit(Fx.use(plain, "cut", FOE))
	var normal := int((plain.sequence.prompts as Array)[0].press_damage)
	var engine := _engine()
	var events: Array[Dictionary] = []
	var foe := engine.get_combatant(FOE)
	engine._add_status(foe, Status.MARKED, 2, engine.active_actor, events)
	engine.submit(Fx.use(engine, "cut", FOE))
	assert_eq(int((engine.sequence.prompts as Array)[0].press_damage),
			CombatMath.percent_min1(normal, 100 + Tuning.new().marked_bonus_percent))
	engine.submit(Fx.resolve_now(engine, [[0, PRESS]]))
	assert_eq(int((foe.statuses[Status.MARKED] as Dictionary).turns), 1, "one use spent")


func test_shadowstep_empowers_the_next_damaging_skill_once() -> void:
	var engine := _engine()
	var actor := engine.active_actor
	_use(engine, "shadowstep", [[0, PRESS]])
	var hero := engine.get_combatant(actor)
	assert_true(hero.has_status(Status.EMPOWERED))
	assert_eq(engine._empowered_bonus(hero, _skill("twin_fangs")), Tuning.new().empowered_bonus_percent)
	assert_eq(engine._empowered_bonus(hero, _skill("shield_wall")), 0, "only damaging skills")
	var events: Array[Dictionary] = []
	engine._use_damage_statuses(hero, _skill("twin_fangs"), [FOE], events)
	assert_false(hero.has_status(Status.EMPOWERED), "used up")


func test_unbreakable_taunts_every_enemy_and_guards_alder() -> void:
	var engine := _engine()
	var actor := engine.active_actor
	_use(engine, "unbreakable", [[0, PRESS]])
	assert_true(engine.get_combatant(FOE).has_status(Status.TAUNTED))
	assert_true(engine.get_combatant(actor).has_status(Status.GUARDED))
	assert_false(engine.get_combatant(actor).has_status(Status.RIPOSTE), "riposte needs a perfect press")
	engine = _engine()
	actor = engine.active_actor
	_use(engine, "unbreakable", [[0, PERFECT]])
	assert_true(engine.get_combatant(actor).has_status(Status.RIPOSTE))


func test_earthshaker_pushes_every_enemy_back() -> void:
	var engine := _engine()
	var before := engine.get_combatant(FOE).next_turn_at
	_use(engine, "earthshaker", [[0, PRESS]])
	assert_gt(engine.get_combatant(FOE).next_turn_at, before)


func test_every_hero_has_three_branches_of_three_or_four() -> void:
	# Phase 19 (cards #254, #261) gave Brin's Flurry and Cass's Mending and Light a fourth skill.
	for hero: String in ["alder", "brin", "cass"]:
		var c := load("res://data/characters/%s.tres" % hero) as CharacterData
		assert_not_null(c.skill_tree, hero)
		assert_eq(c.skill_tree.branches.size(), 3, hero)
		for branch: SkillBranchData in c.skill_tree.branches:
			assert_between(branch.skills.size(), 3, 4, "%s %s" % [hero, branch.display_name])
			for skill: AbilityData in branch.skills:
				assert_not_null(skill, hero)


func test_cass_casts_every_skill_from_afar_but_walks_up_to_attack() -> void:
	var cass := load("res://data/characters/cass.tres") as CharacterData
	assert_null(cass.basic_attack.projectile, "her normal attack is melee")
	for skill: AbilityData in cass.skill_tree.all_skills():
		if skill.targets_enemies():
			assert_not_null(skill.projectile, "%s is a spell" % skill.id)
