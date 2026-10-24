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


func test_the_tutorial_has_six_fight_lessons_then_first_strike_then_relics() -> void:
	# Phase 19 (card #264) added the marks lesson (6); phase 22 (card #291) the First Strike card (7)
	# before Relics and Echoes (8).
	var data := load(TUTORIAL_PATH) as TutorialData
	assert_not_null(data)
	assert_not_null(data.encounter)
	assert_eq(data.lesson_count(), 8)
	var cards: Array[String] = []
	for step: TutorialStepData in data.steps:
		if step.goal == TutorialGoals.READ:
			# First Strike (7), then the Relics and Echoes lesson (8, DESIGN.md 8.17): cards only, at the end.
			assert_eq(step.lesson, 7 if step.title == "First Strike" else 8, "%s comes after the fight lessons" % step.title)
			assert_false(step.text.is_empty(), step.title)
			cards.append(step.title)
			continue
		assert_true(cards.is_empty(), "%s: the fight lessons come first" % step.title)
		assert_true(TutorialGoals.FIGHT_GOALS.has(step.goal), "%s: known goal" % step.title)
		assert_false(step.text.is_empty(), step.title)
		assert_false(step.reminder.is_empty(), "%s has a reminder line" % step.title)
		assert_false(step.retry.is_empty(), "%s says what to fix" % step.title)
		assert_true(step.hold in ["enemies", "party"], "%s stages who acts" % step.title)
	assert_eq(cards, ["First Strike", "Relics", "Echoes"] as Array[String],
			"the cards explain First Strike, then Relics, then Echoes")


## Card #291: the zone no longer spelled out First Strike, so the tutorial did, in one short
## sentence. Phase 26 took the zones and their strike button away (DESIGN.md 8.22 G8); the card
## stays until #320 rewrites it, and it names no button that is gone.
func test_a_first_strike_card_stays_and_names_no_lost_button() -> void:
	var data := load(TUTORIAL_PATH) as TutorialData
	var card: TutorialStepData = null
	for step: TutorialStepData in data.steps:
		if step.title == "First Strike":
			card = step
	assert_not_null(card, "a First Strike card")
	if card == null:
		return
	assert_eq(card.goal, TutorialGoals.READ, "a card to read, no fight action")
	assert_false("{field_strike}" in card.text, "the strike button went with the zones")
	assert_false(InputMap.has_action(&"field_strike"), "no strike action is left")
	assert_lte(card.text.split(".", false).size(), 1, "one short sentence")
	assert_lte(card.text.length(), 120, "short")
	var overlay := TutorialOverlay.new()
	add_child_autofree(overlay)
	overlay.show_card("Lesson 7 of 8", card.title, card.text, card.tip, "Go", false, card.icon_path)
	var chips := 0
	for row: Node in overlay._lines.get_children():
		for piece: Node in row.get_children():
			if piece is HintBar:
				chips += 1
	assert_eq(chips, 0, "the card draws no button")
	# Card #293: the foe skull, the picture of an enemy to strike.
	assert_eq(card.icon_path, "res://assets/sprites/ui/goal_foe.png")
	assert_true(overlay._plate.visible, "the card shows its picture")


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


## The tutorial is the real game for the practice keys (card #248): 1 to 9, I, O and R would break
## its lessons (it keeps the enemy up and the party standing itself), as in a run fight.
func test_practice_keys_are_off_in_the_tutorial() -> void:
	var fight := CombatController.new()
	assert_false(fight._is_real_fight(), "a practice fight has the practice keys")
	fight.set_tutorial(true)
	assert_true(fight._is_real_fight(), "the tutorial has none")
	fight.free()


# --- the marks lesson (card #264) ----------------------------------------------------------

func test_defending_the_dotted_hit_finishes_the_marks_step() -> void:
	var sequence := {"seq": 4, "hits": [{"index": 0}, {"index": 1, "mark": "rotting"}],
			"prompts": [{"role": "defend"}, {"role": "defend"}]}
	var plain := {"type": "prompt_resolved", "seq": 4, "prompt": 0, "hit": 0, "outcome": Defense.Outcome.PARRY}
	var dotted := {"type": "prompt_resolved", "seq": 4, "prompt": 1, "hit": 1, "outcome": Defense.Outcome.PARRY}
	var missed := {"type": "prompt_resolved", "seq": 4, "prompt": 1, "hit": 1, "outcome": Defense.Outcome.NONE}
	assert_false(TutorialGoals.reached(TutorialGoals.MARK_DEFENDED, plain, sequence), "a plain hit")
	assert_true(TutorialGoals.reached(TutorialGoals.MARK_DEFENDED, dotted, sequence), "the dotted hit")
	assert_false(TutorialGoals.reached(TutorialGoals.MARK_DEFENDED, missed, sequence), "taken")


func test_only_a_skill_lifting_a_mark_finishes_the_cleanse_step() -> void:
	var lifted := {"type": "status_changed", "target": 0, "status": "rotting", "active": false}
	assert_true(TutorialGoals.reached(TutorialGoals.CLEANSE, lifted, {"kind": CombatEngine.SEQUENCE_SKILL}))
	assert_false(TutorialGoals.reached(TutorialGoals.CLEANSE, lifted, {}), "it just wore off")
	var other := {"type": "status_changed", "target": 0, "status": "guarded", "active": false}
	assert_false(TutorialGoals.reached(TutorialGoals.CLEANSE, other, {"kind": CombatEngine.SEQUENCE_SKILL}), "not a mark")


func test_the_marks_lesson_puts_a_mark_on_its_hero() -> void:
	var data := load(TUTORIAL_PATH) as TutorialData
	var step: TutorialStepData = null
	for s: TutorialStepData in data.steps:
		if s.goal == TutorialGoals.CLEANSE:
			step = s
	assert_not_null(step, "a cleanse step")
	assert_true(Status.is_debuff(step.mark_status), "it marks with a hero debuff")
	var setup := CombatSetup.from_encounter(data.encounter, Tuning.new(), 3)
	setup.allow_practice = true
	var engine := CombatEngine.new(setup)
	engine.start()
	var hero := -1
	for c: Combatant in engine.combatants:
		if c.is_party() and c.data_id == step.mark_hero:
			hero = c.id
	engine.submit(CombatCommands.practice({"mark_hero": hero, "mark_status": step.mark_status}))
	assert_true(engine.get_combatant(hero).has_status(step.mark_status))
