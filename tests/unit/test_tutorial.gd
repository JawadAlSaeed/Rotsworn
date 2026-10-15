extends GutTest
## The tutorial (card #131, DESIGN.md 7.8): its data, and which events finish each step.

const TUTORIAL_PATH := "res://data/tutorial/tutorial.tres"
const PRESS: int = Defense.Outcome.PRESS
const PERFECT: int = Defense.Outcome.PRESS_PERFECT


func _sequence(roles: Array) -> Dictionary:
	var prompts: Array = []
	for role: String in roles:
		prompts.append({"role": role})
	return {"seq": 4, "prompts": prompts}


func _resolved(prompt: int, outcome: int, seq: int = 4) -> Dictionary:
	return {"type": "prompt_resolved", "seq": seq, "prompt": prompt, "outcome": outcome}


func test_the_tutorial_has_five_fight_lessons() -> void:
	var data := load(TUTORIAL_PATH) as TutorialData
	assert_not_null(data)
	assert_not_null(data.encounter)
	assert_eq(data.lesson_count(), 5)
	for step: TutorialStepData in data.steps:
		assert_true(TutorialGoals.FIGHT_GOALS.has(step.goal), "%s: known goal" % step.title)
		assert_false(step.text.is_empty(), step.title)
		assert_false(step.reminder.is_empty(), "%s has a reminder line" % step.title)
		assert_false(step.retry.is_empty(), "%s says what to fix" % step.title)
		assert_true(step.hold in ["enemies", "party"], "%s stages who acts" % step.title)


func test_the_skills_lesson_comes_before_follow_ups_and_has_none() -> void:
	var data := load(TUTORIAL_PATH) as TutorialData
	for step: TutorialStepData in data.steps:
		if step.goal == TutorialGoals.SKILL_USED:
			var skill := load("res://data/abilities/%s.tres" % step.ability) as AbilityData
			assert_false(skill.follow_ups, "follow-ups are the next lesson")
		if step.goal == TutorialGoals.SKILL_FOLLOW_UP:
			var skill := load("res://data/abilities/%s.tres" % step.ability) as AbilityData
			assert_true(skill.follow_ups, "this lesson's skill brings follow-ups")


func test_forced_attacks_exist_on_the_tutorial_enemy() -> void:
	var data := load(TUTORIAL_PATH) as TutorialData
	var ids: Array[String] = []
	for enemy: EnemyData in data.encounter.enemies:
		for attack: EnemyAttackData in enemy.attacks:
			ids.append(attack.id)
	for step: TutorialStepData in data.steps:
		if not step.forced_attack.is_empty():
			assert_true(ids.has(step.forced_attack), "%s forces a real attack" % step.title)


func test_a_good_press_finishes_the_attack_lesson() -> void:
	var seq := _sequence([CombatEngine.ROLE_PRESS])
	assert_true(TutorialGoals.reached(TutorialGoals.GOOD_PRESS, _resolved(0, PRESS), seq))
	assert_true(TutorialGoals.reached(TutorialGoals.GOOD_PRESS, _resolved(0, PERFECT), seq))
	assert_false(TutorialGoals.reached(TutorialGoals.GOOD_PRESS, _resolved(0, Defense.Outcome.NONE), seq), "a miss")
	assert_false(TutorialGoals.reached(TutorialGoals.GOOD_PRESS, _resolved(0, PRESS, 9), seq), "another sequence")


func test_only_a_good_follow_up_finishes_the_skill_lesson() -> void:
	var seq := _sequence([CombatEngine.ROLE_PRESS, CombatEngine.ROLE_FOLLOW_UP])
	assert_false(TutorialGoals.reached(TutorialGoals.SKILL_FOLLOW_UP, _resolved(0, PRESS), seq), "the skill's own press")
	assert_true(TutorialGoals.reached(TutorialGoals.SKILL_FOLLOW_UP, _resolved(1, PRESS), seq))


func test_defence_counter_and_ultimate_goals() -> void:
	var seq := _sequence([CombatEngine.ROLE_DEFEND])
	assert_true(TutorialGoals.reached(TutorialGoals.PARRY, _resolved(0, Defense.Outcome.PARRY), seq))
	assert_false(TutorialGoals.reached(TutorialGoals.PARRY, _resolved(0, Defense.Outcome.DODGE), seq))
	assert_true(TutorialGoals.reached(TutorialGoals.DODGE, _resolved(0, Defense.Outcome.DODGE), seq))
	assert_true(TutorialGoals.reached(TutorialGoals.JUMP, _resolved(0, Defense.Outcome.JUMP), seq))
	assert_true(TutorialGoals.reached(TutorialGoals.COUNTER, {"type": "counter"}, {}))
	assert_true(TutorialGoals.reached(TutorialGoals.ULTIMATE, {"type": "ability_used", "ability": "team_ultimate"}, {}))
	assert_false(TutorialGoals.reached(TutorialGoals.ULTIMATE, {"type": "ability_used", "ability": "rend"}, {}))


func test_the_fill_gauge_practice_command() -> void:
	var setup := CombatSetup.from_encounter(load("res://data/encounters/husk_fight.tres") as EncounterData, Tuning.new(), 3)
	setup.allow_practice = true
	var engine := CombatEngine.new(setup)
	engine.start()
	engine.submit(CombatCommands.practice({"fill_gauge": true}))
	assert_eq(engine.team_gauge, Tuning.new().team_gauge_max)


func test_the_tutorial_enemy_is_slowed() -> void:
	var data := load(TUTORIAL_PATH) as TutorialData
	var setup := CombatSetup.from_encounter(data.encounter, Tuning.new(), 3, CombatSetup.Opening.FIRST_STRIKE)
	setup.enemy_speed_percent = data.enemy_speed_percent
	var engine := CombatEngine.new(setup)
	engine.start()
	var foe := engine.get_combatant(engine.enemy_ids()[0])
	assert_eq(foe.speed, CombatMath.percent(data.encounter.enemies[0].speed, data.enemy_speed_percent))
	assert_true(engine.get_combatant(engine.active_actor).is_party(), "the heroes go first")


func _tutorial_engine() -> CombatEngine:
	var data := load(TUTORIAL_PATH) as TutorialData
	var setup := CombatSetup.from_encounter(data.encounter, Tuning.new(), 3, CombatSetup.Opening.FIRST_STRIKE)
	setup.allow_practice = true
	var engine := CombatEngine.new(setup)
	engine.start()
	return engine


func test_the_gate_holds_the_enemy_until_opened() -> void:
	var engine := _tutorial_engine()
	assert_eq(engine.phase, CombatEngine.Phase.AWAITING_ACTION, "a hero is choosing")
	engine.submit(CombatCommands.practice({"hold_party": true, "gate": true, "pass_turn": true,
			"stage_attack": "husk_swipe", "tempo_percent": 170}))
	assert_eq(engine.phase, CombatEngine.Phase.AWAITING_GATE, "the heroes' turns passed, the enemy waits")
	assert_true(engine.sequence.is_empty() or String(engine.sequence.get("kind", "")) != CombatEngine.SEQUENCE_ENEMY_ATTACK
			or engine.phase == CombatEngine.Phase.AWAITING_GATE)
	var events := engine.submit(CombatCommands.practice({"open_gate": true}))
	var declared := {}
	for e: Dictionary in events:
		if String(e.type) == "timed_sequence_declared":
			declared = e
	assert_eq(String(declared.get("action", "")), "husk_swipe", "the step's attack")
	var swipe := load("res://data/enemy_attacks/husk_swipe.tres") as EnemyAttackData
	assert_eq(int((declared.hits as Array)[0].at_ms), CombatMath.percent(swipe.hits[0].impact_ms, 170), "slowed")


func test_hold_enemies_lets_only_the_heroes_act() -> void:
	var engine := _tutorial_engine()
	engine.submit(CombatCommands.practice({"hold_enemies": true}))
	for i: int in 6:
		assert_eq(engine.phase, CombatEngine.Phase.AWAITING_ACTION)
		assert_true(engine.get_combatant(engine.active_actor).is_party(), "always a hero")
		engine.submit(CombatCommands.practice({"pass_turn": true}))


func test_the_staged_attack_is_always_the_enemy_intent() -> void:
	var engine := _tutorial_engine()
	var husk := engine.living_enemy_ids()[0]
	engine.submit(CombatCommands.practice({"stage_attack": "husk_swipe"}))
	assert_eq(String(engine.intents[husk].attack), "husk_swipe", "shown at once")
	for i: int in 10:
		assert_eq(String(engine._choose_intent(engine.get_combatant(husk)).attack), "husk_swipe", "every pick")
	engine.submit(CombatCommands.practice({"stage_attack": "husk_ground_slam"}))
	assert_eq(String(engine.intents[husk].attack), "husk_ground_slam", "the next lesson's attack")


func test_every_hero_step_names_a_hero_and_one_of_their_abilities() -> void:
	var data := load(TUTORIAL_PATH) as TutorialData
	for step: TutorialStepData in data.steps:
		if step.hold != "enemies":
			continue
		var hero: CharacterData = null
		for c: CharacterData in data.encounter.party:
			if c.id == step.hero:
				hero = c
		assert_not_null(hero, "%s: the hero is in the party" % step.title)
		if hero == null:
			continue
		var ids: Array[String] = ["team_ultimate"]
		for a: AbilityData in hero.all_abilities():
			ids.append(a.id)
		assert_true(ids.has(step.ability), "%s: %s can use %s" % [step.title, step.hero, step.ability])


func test_only_the_lesson_hero_acts() -> void:
	var engine := _tutorial_engine()
	var brin := -1
	for c: Combatant in engine.combatants:
		if c.data_id == "brin":
			brin = c.id
	engine.submit(CombatCommands.practice({"hold_enemies": true, "hero": brin,
			"pass_turn": engine.active_actor != brin}))
	for i: int in 4:
		assert_eq(engine.phase, CombatEngine.Phase.AWAITING_ACTION)
		assert_eq(engine.active_actor, brin, "always Brin")
		engine.submit(CombatCommands.practice({"pass_turn": true}))
