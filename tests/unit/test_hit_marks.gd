extends GutTest
## Enemy hits that leave a mark (DESIGN.md 2.7, card #194): the Rotting, Blighted and Weakened hero
## debuffs and the AP drain. Applied only by a hit that lands undefended on a hero who survives it,
## cleansed by healing skills and items, shown honestly in the intent.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")

const NONE: int = Defense.Outcome.NONE
const DODGE: int = Defense.Outcome.DODGE
const PARRY: int = Defense.Outcome.PARRY
const JUMP: int = Defense.Outcome.JUMP
const PRESS: int = Defense.Outcome.PRESS
const PERFECT: int = Defense.Outcome.PRESS_PERFECT
const FOE: int = Fx.ENEMY_ID
const SLOW_ENEMY: int = 10


## A hit that marks. `status` "" = none.
func _hit(status: String, turns: int = 2, drain: int = 0, hard_only: bool = false, kind: int = Fx.NORMAL) -> AttackHitData:
	var h := Fx.hit(900, kind)
	h.on_hit_status = status
	h.on_hit_status_turns = turns
	h.on_hit_ap_drain = drain
	h.on_hit_hard_only = hard_only
	return h


## The enemy acts first and its single attack is declared. Returns the engine.
func _marked_fight(hit: AttackHitData, options: Dictionary = {}) -> CombatEngine:
	var setup := Fx.setup([Fx.attack("bite", [hit])], options)
	setup.forced_hits = bool(options.get("hard", false))
	var engine := CombatEngine.new(setup)
	engine.start()
	return engine


func _defend(engine: CombatEngine, outcome: int) -> Array[Dictionary]:
	return engine.submit(Fx.resolve_now(engine, [[0, outcome]]))


func _hero(engine: CombatEngine) -> Combatant:
	return engine.get_combatant(int((engine.sequence.targets as Array)[0]))


func _status_events(events: Array[Dictionary], status: String) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for e: Dictionary in Fx.of_type(events, "status_changed"):
		if String(e.status) == status:
			list.append(e)
	return list


# --- when a mark lands ------------------------------------------------------------------------

func test_an_undefended_hit_leaves_the_debuff() -> void:
	for status: String in Status.DEBUFFS:
		var engine := _marked_fight(_hit(status, 3))
		var hero := _hero(engine)
		var events := _defend(engine, NONE)
		var marks := _status_events(events, status)
		assert_eq(marks.size(), 1, "%s: one status event" % status)
		assert_true(hero.has_status(status), "%s: the hero carries it" % status)
		assert_eq(int((hero.statuses[status] as Dictionary).turns), 3)
		assert_eq(int((hero.statuses[status] as Dictionary).source), FOE, "the enemy is the source")
		assert_true(bool(marks[0].active))
		assert_eq(int(marks[0].target), hero.id)


func test_the_mark_comes_after_the_hit_resolves() -> void:
	var engine := _marked_fight(_hit(Status.ROTTING))
	var events := _defend(engine, NONE)
	assert_lt(Fx.index_of(events, "prompt_resolved"), Fx.index_of(events, "status_changed"))


func test_a_successful_defence_prevents_the_mark() -> void:
	for outcome: int in [DODGE, PARRY]:
		var engine := _marked_fight(_hit(Status.ROTTING, 2, 1))
		var hero := _hero(engine)
		var ap := hero.ap
		var events := _defend(engine, outcome)
		assert_true(_status_events(events, Status.ROTTING).is_empty(), "outcome %d: no status event" % outcome)
		assert_false(hero.has_status(Status.ROTTING))
		assert_eq(hero.ap, ap + Defense.ap_reward(outcome, Tuning.new()), "only the defence reward, nothing drained")
		for e: Dictionary in Fx.of_type(events, "ap_changed"):
			assert_ne(String(e.reason), "drain")


func test_a_ground_hit_is_stopped_only_by_a_jump() -> void:
	var engine := _marked_fight(_hit(Status.BLIGHTED, 2, 0, false, Fx.GROUND))
	var hero := _hero(engine)
	_defend(engine, JUMP)
	assert_false(hero.has_status(Status.BLIGHTED), "a jump prevents it")
	engine = _marked_fight(_hit(Status.BLIGHTED, 2, 0, false, Fx.GROUND))
	hero = _hero(engine)
	_defend(engine, DODGE)
	assert_true(hero.has_status(Status.BLIGHTED), "a dodge is the wrong button for a ground hit")


func test_a_wrong_button_on_a_forced_hit_does_not_prevent_it() -> void:
	var engine := _marked_fight(_hit(Status.WEAKENED, 2, 0, false, AttackHitData.Kind.REND))
	var hero := _hero(engine)
	var events := _defend(engine, DODGE)
	assert_eq(int(Fx.first_of(events, "prompt_resolved").outcome), NONE, "a dodge does not answer a rend")
	assert_true(hero.has_status(Status.WEAKENED))


func test_a_hero_downed_by_the_hit_gets_no_mark() -> void:
	var engine := _marked_fight(_hit(Status.ROTTING, 2, 1), {"hp_percents": [1, 1, 1]})
	var hero := _hero(engine)
	var events := _defend(engine, NONE)
	assert_false(hero.is_alive())
	assert_true(_status_events(events, Status.ROTTING).is_empty(), "no mark on a downed hero")
	assert_false(hero.has_status(Status.ROTTING))
	for e: Dictionary in Fx.of_type(events, "ap_changed"):
		assert_ne(String(e.reason), "drain", "a downed hero loses no AP")


func test_a_second_mark_refreshes_the_turns_and_never_stacks() -> void:
	var engine := _marked_fight(_hit(Status.ROTTING, 3))
	var hero := _hero(engine)
	var events: Array[Dictionary] = []
	engine._add_status(hero, Status.ROTTING, 1, FOE, events)
	_defend(engine, NONE)
	assert_eq(int((hero.statuses[Status.ROTTING] as Dictionary).turns), 3, "the longer of the two")
	assert_eq(hero.statuses.size(), 1)
	engine._add_status(hero, Status.ROTTING, 2, FOE, events)
	assert_eq(int((hero.statuses[Status.ROTTING] as Dictionary).turns), 3, "a shorter mark does not shorten it")


func test_an_ap_drain_takes_ap_from_an_undefended_hit() -> void:
	var engine := _marked_fight(_hit("", 2, 2))
	var hero := _hero(engine)
	hero.ap = 4
	var events := _defend(engine, NONE)
	assert_eq(hero.ap, 2)
	var drains := Fx.of_type(events, "ap_changed").filter(func(e: Dictionary) -> bool: return String(e.reason) == "drain")
	assert_eq(drains.size(), 1)
	assert_eq(int(drains[0].delta), -2)
	assert_eq(int(drains[0].ap), 2)


func test_an_ap_drain_never_goes_below_zero() -> void:
	var engine := _marked_fight(_hit("", 2, 3))
	var hero := _hero(engine)
	hero.ap = 1
	_defend(engine, NONE)
	assert_eq(hero.ap, 0)


func test_a_defended_ap_drain_hit_takes_nothing() -> void:
	var engine := _marked_fight(_hit("", 2, 2))
	var hero := _hero(engine)
	hero.ap = 4
	_defend(engine, PARRY)
	assert_eq(hero.ap, 5, "only the parry reward")


# --- hard fights only -------------------------------------------------------------------------

func test_a_hard_only_mark_waits_for_a_hard_fight() -> void:
	var engine := _marked_fight(_hit(Status.ROTTING, 2, 0, true))
	var hero := _hero(engine)
	_defend(engine, NONE)
	assert_false(hero.has_status(Status.ROTTING), "an ordinary fight: just damage")
	engine = _marked_fight(_hit(Status.ROTTING, 2, 0, true), {"hard": true})
	hero = _hero(engine)
	_defend(engine, NONE)
	assert_true(hero.has_status(Status.ROTTING), "a hard fight")


func test_an_enemy_with_forced_hits_marks_in_any_fight() -> void:
	var setup := Fx.setup([Fx.attack("bite", [_hit(Status.BLIGHTED, 2, 0, true)])])
	setup.enemies[0].forced_hits = true
	var engine := CombatEngine.new(setup)
	engine.start()
	var hero := _hero(engine)
	_defend(engine, NONE)
	assert_true(hero.has_status(Status.BLIGHTED))


# --- honest intent ----------------------------------------------------------------------------

func test_the_declared_hit_and_the_intent_say_which_hits_mark() -> void:
	var plain := _hit("")
	var marking := _hit(Status.WEAKENED)
	marking.impact_ms = 1300
	var engine := CombatEngine.new(Fx.setup([Fx.attack("string", [plain, marking])]))
	var events := engine.start()
	var intent := Fx.first_of(events, "intent")
	assert_eq(intent.marks, ["", Status.WEAKENED], "the intent names the marking hit")
	var declared := Fx.first_of(events, "timed_sequence_declared")
	assert_false((declared.hits[0] as Dictionary).has("mark"))
	assert_eq((declared.hits[1] as Dictionary).mark, Status.WEAKENED)
	assert_false((declared.prompts[0] as Dictionary).has("mark_status"), "a plain hit carries nothing")
	assert_eq((declared.prompts[1] as Dictionary).mark_status, Status.WEAKENED)
	assert_eq((declared.prompts[1] as Dictionary).mark_turns, 2)


func test_ap_drain_shows_as_its_own_mark() -> void:
	var events := CombatEngine.new(Fx.setup([Fx.attack("drain", [_hit("", 2, 1)])])).start()
	assert_eq((Fx.first_of(events, "timed_sequence_declared").hits[0] as Dictionary).mark, Status.MARK_AP_DRAIN)
	assert_eq(Fx.first_of(events, "intent").marks, [Status.MARK_AP_DRAIN])


func test_a_fight_without_marks_keeps_its_events_unchanged() -> void:
	var events := CombatEngine.new(Fx.setup([Fx.attack("plain", [Fx.hit(900)])])).start()
	assert_false(Fx.first_of(events, "intent").has("marks"))
	var declared := Fx.first_of(events, "timed_sequence_declared")
	assert_false((declared.hits[0] as Dictionary).has("mark"))
	assert_false((declared.prompts[0] as Dictionary).has("mark_status"))


func test_a_hard_only_mark_is_not_announced_in_an_ordinary_fight() -> void:
	var setup := Fx.setup([Fx.attack("bite", [_hit(Status.ROTTING, 2, 0, true)])])
	var events := CombatEngine.new(setup).start()
	assert_false(Fx.first_of(events, "intent").has("marks"), "no mark, no announcement")
	setup.forced_hits = true
	events = CombatEngine.new(setup).start()
	assert_eq(Fx.first_of(events, "intent").marks, [Status.ROTTING])


# --- what each debuff does --------------------------------------------------------------------

func _calm() -> CombatEngine:
	var engine := Fx.started([Fx.attack("bite", [Fx.hit(900)])], {"enemy_speed": SLOW_ENEMY})
	return engine


func test_rotting_costs_a_percent_of_max_hp_at_the_start_of_each_turn() -> void:
	var engine := _calm()
	var hero := engine.get_combatant(0)
	var events: Array[Dictionary] = []
	engine._add_status(hero, Status.ROTTING, 2, FOE, events)
	events.clear()
	engine._start_of_turn(hero, events)
	var expected := CombatMath.percent_min1(hero.max_hp, Tuning.new().rotting_percent)
	assert_eq(hero.hp, hero.max_hp - expected)
	var hit := Fx.first_of(events, "damage")
	assert_eq(int(hit.amount), expected)
	assert_eq(String(hit.cause), "rotting")


func test_rot_never_takes_the_last_hp() -> void:
	var engine := _calm()
	var hero := engine.get_combatant(0)
	var events: Array[Dictionary] = []
	engine._add_status(hero, Status.ROTTING, 5, FOE, events)
	hero.hp = 3
	for _i: int in 4:
		engine._start_of_turn(hero, events)
	assert_eq(hero.hp, 1, "rot alone leaves 1 HP")
	assert_true(hero.is_alive())
	events.clear()
	engine._start_of_turn(hero, events)
	assert_true(Fx.of_type(events, "damage").is_empty(), "nothing to take at 1 HP")


func test_debuff_turns_count_down_and_end() -> void:
	for status: String in Status.DEBUFFS:
		var engine := _calm()
		var hero := engine.get_combatant(0)
		var events: Array[Dictionary] = []
		engine._add_status(hero, status, 2, FOE, events)
		events.clear()
		engine._end_of_turn(hero, events)
		assert_eq(int((hero.statuses[status] as Dictionary).turns), 1, "%s: one turn used" % status)
		assert_eq(int(_status_events(events, status)[0].turns), 1)
		events.clear()
		engine._end_of_turn(hero, events)
		assert_false(hero.has_status(status), "%s: gone after its turns" % status)
		assert_false(bool(_status_events(events, status)[0].active))


func test_the_hud_shows_the_turns_left() -> void:
	assert_true(Status.shows_count(Status.ROTTING))
	assert_true(Status.shows_count(Status.BLIGHTED))
	assert_true(Status.shows_count(Status.WEAKENED))
	var words := HudStyle.debuff_words({Status.ROTTING: {"turns": 2, "source": 3}, Status.GUARDED: {"turns": 0, "source": 0}})
	assert_eq(words.size(), 1)
	assert_eq(words[0], [Status.ROTTING, "ROT 2"])


func test_blighted_cuts_the_healing_received() -> void:
	var engine := _calm()
	var hero := engine.get_combatant(0)
	var healer := engine.get_combatant(2)
	hero.hp = 10
	var events: Array[Dictionary] = []
	engine._heal(healer, hero, 40, events)
	assert_eq(hero.hp, 50)
	hero.hp = 10
	engine._add_status(hero, Status.BLIGHTED, 2, FOE, events)
	events.clear()
	engine._heal(healer, hero, 40, events)
	assert_eq(hero.hp, 10 + CombatMath.percent_min1(40, 100 - Tuning.new().blighted_heal_cut_percent))
	assert_eq(int(Fx.first_of(events, "healed").amount), 20)


func test_a_blighted_hero_still_gets_a_heal_of_at_least_one() -> void:
	var engine := _calm()
	var hero := engine.get_combatant(0)
	hero.hp = 5
	var events: Array[Dictionary] = []
	engine._add_status(hero, Status.BLIGHTED, 2, FOE, events)
	engine._heal(engine.get_combatant(2), hero, 1, events)
	assert_eq(hero.hp, 6)


func test_weakened_cuts_power() -> void:
	var engine := _calm()
	var hero := engine.get_combatant(1)
	var full := hero.power
	assert_eq(engine._power_of(hero), full)
	var events: Array[Dictionary] = []
	engine._add_status(hero, Status.WEAKENED, 2, FOE, events)
	assert_eq(engine._power_of(hero), CombatMath.percent_min1(full, 100 - Tuning.new().weakened_power_cut_percent))
	assert_lt(engine._power_of(hero), full)
	assert_eq(hero.power, full, "the stored power is untouched")


func test_weakened_cuts_a_skills_damage() -> void:
	var fresh := _damage_of_cut(false)
	var weak := _damage_of_cut(true)
	assert_gt(fresh, 0)
	assert_eq(weak, _damage_of_cut_expected(fresh, true), "the declared press damage is cut")
	assert_lt(weak, fresh)


func _damage_of_cut(weakened: bool) -> int:
	var kit: Array = [Fx.skill("cut", AbilityData.Target.SINGLE_ENEMY, 0, [800], {"damage_percent": 200})]
	var engine := Fx.kit_started([kit, kit, kit], [Fx.attack("swipe", [Fx.hit(900)])], {"enemy_speed": SLOW_ENEMY})
	var actor := engine.get_combatant(engine.active_actor)
	if weakened:
		engine._add_status(actor, Status.WEAKENED, 2, FOE, [] as Array[Dictionary])
	engine.submit(Fx.use(engine, "cut", FOE))
	return int((engine.sequence.prompts[0] as Dictionary).press_damage)


func _damage_of_cut_expected(_fresh: int, _weak: bool) -> int:
	var kit: Array = [Fx.skill("cut", AbilityData.Target.SINGLE_ENEMY, 0, [800], {"damage_percent": 200})]
	var engine := Fx.kit_started([kit, kit, kit], [Fx.attack("swipe", [Fx.hit(900)])], {"enemy_speed": SLOW_ENEMY})
	var actor := engine.get_combatant(engine.active_actor)
	return CombatMath.percent_min1(CombatMath.percent_min1(actor.power, 100 - Tuning.new().weakened_power_cut_percent), 200)


func test_a_downed_hero_loses_every_debuff() -> void:
	var engine := _calm()
	var hero := engine.get_combatant(0)
	var events: Array[Dictionary] = []
	for status: String in Status.DEBUFFS:
		engine._add_status(hero, status, 3, FOE, events)
	engine._deal_damage(engine.get_combatant(FOE), hero, hero.hp, "ability", events)
	assert_true(hero.statuses.is_empty())


# --- cleansing --------------------------------------------------------------------------------

func _healer_fight(skill_id: String, hurt: Array = [10, 10, 10]) -> CombatEngine:
	var ability := (load("res://data/abilities/%s.tres" % skill_id) as AbilityData).duplicate() as AbilityData
	ability.ap_cost = 0
	var kit: Array = [ability]
	var setup := Fx.kit_setup([kit, kit, kit], [Fx.attack("swipe", [Fx.hit(900)])], {"enemy_speed": SLOW_ENEMY})
	setup.party_start_hp.assign(hurt)
	var engine := CombatEngine.new(setup)
	engine.start()
	return engine


func _mark_all(engine: CombatEngine, id: int) -> void:
	var events: Array[Dictionary] = []
	for status: String in Status.DEBUFFS:
		engine._add_status(engine.get_combatant(id), status, 3, FOE, events)


func _mend(engine: CombatEngine, target: int, outcome: int) -> Array[Dictionary]:
	var targets: Array[int] = [target]
	engine.submit(CombatCommands.use_ability(engine.turn_number, engine.active_actor, "mend", targets))
	return engine.submit(Fx.resolve_now(engine, [[0, outcome]]))


func test_mend_lifts_one_mark_in_order_and_a_perfect_press_lifts_all() -> void:
	var engine := _healer_fight("mend")
	var target := engine.party_ids()[0]
	_mark_all(engine, target)
	var events := _mend(engine, target, PRESS)
	var hero := engine.get_combatant(target)
	assert_false(hero.has_status(Status.ROTTING), "rotting goes first")
	assert_true(hero.has_status(Status.BLIGHTED))
	assert_true(hero.has_status(Status.WEAKENED))
	assert_eq(_status_events(events, Status.ROTTING).size(), 1)
	engine = _healer_fight("mend")
	target = engine.party_ids()[0]
	_mark_all(engine, target)
	_mend(engine, target, PERFECT)
	assert_true(engine.get_combatant(target).statuses.is_empty(), "a perfect press lifts all three")


func test_the_cleanse_frees_the_heal_from_blight() -> void:
	var engine := _healer_fight("mend")
	var target := engine.party_ids()[0]
	var hero := engine.get_combatant(target)
	var events: Array[Dictionary] = []
	engine._add_status(hero, Status.BLIGHTED, 3, FOE, events)
	_mend(engine, target, PRESS)
	assert_false(hero.has_status(Status.BLIGHTED))
	assert_eq(hero.hp, 10 + CombatMath.percent_min1(hero.max_hp, 30), "the heal was not cut: blight left first")


func test_a_skill_that_does_not_heal_does_not_cleanse() -> void:
	var engine := _healer_fight("inspire")
	var target := engine.party_ids()[0]
	_mark_all(engine, target)
	engine.submit(Fx.use(engine, "inspire", target))
	engine.submit(Fx.resolve_now(engine, [[0, PERFECT]]))
	assert_eq(engine.get_combatant(target).statuses.size(), 3)


func test_sanctuary_lifts_a_mark_from_everyone() -> void:
	var engine := _healer_fight("sanctuary")
	for id: int in engine.party_ids():
		_mark_all(engine, id)
	engine.submit(Fx.use(engine, "sanctuary", FOE))
	engine.submit(Fx.resolve_now(engine, [[0, PRESS]]))
	for id: int in engine.party_ids():
		assert_eq(engine.get_combatant(id).statuses.size(), 2, "one mark gone for hero %d" % id)


func test_a_healing_item_lifts_a_mark() -> void:
	var item := (load("res://data/items/salve.tres") as ItemData).duplicate() as ItemData
	assert_eq(item.cleanse_count, 1, "the salve is the cleansing item")
	var setup := Fx.setup([Fx.attack("swipe", [Fx.hit(900)])], {"enemy_speed": SLOW_ENEMY})
	setup.items.append({"uid": 1, "item": item})
	var engine := CombatEngine.new(setup)
	engine.start()
	var target := engine.party_ids()[0]
	_mark_all(engine, target)
	engine.submit(CombatCommands.use_item(engine.turn_number, engine.active_actor, 1, [target] as Array[int]))
	assert_eq(engine.get_combatant(target).statuses.size(), 2, "one mark lifted by the salve")


func test_shipped_healing_skills_cleanse_and_others_do_not() -> void:
	for id: String in ["mend", "sanctuary"]:
		var a := load("res://data/abilities/%s.tres" % id) as AbilityData
		assert_eq(a.cleanse_count, 1, id)
		assert_eq(a.cleanse_count + a.press_cleanse_count, 3, "%s: a perfect press clears all three" % id)
	assert_eq((load("res://data/abilities/renew.tres") as AbilityData).cleanse_count, 0)


# --- state, determinism and data --------------------------------------------------------------

func test_marks_survive_a_snapshot_round_trip() -> void:
	var engine := _marked_fight(_hit(Status.ROTTING, 3, 1))
	var hero := _hero(engine)
	hero.ap = 3
	var before_hit := engine.snapshot()
	var restored := CombatEngine.restore(engine._setup, before_hit)
	assert_eq(restored.snapshot(), before_hit, "the declared mark data is in the snapshot")
	_defend(engine, NONE)
	var after := engine.snapshot()
	var twin := CombatEngine.restore(engine._setup, after)
	assert_eq(twin.snapshot(), after)
	assert_true(twin.get_combatant(hero.id).has_status(Status.ROTTING))
	assert_eq(int((twin.get_combatant(hero.id).statuses[Status.ROTTING] as Dictionary).turns), 3)
	# The restored fight carries on exactly like the original.
	assert_eq(_step(engine), _step(twin))
	assert_eq(engine.snapshot(), twin.snapshot())


## The next command of a simple fight: resolve an open attack undefended, else the hero attacks.
func _step(engine: CombatEngine) -> Array[Dictionary]:
	if engine.phase == CombatEngine.Phase.AWAITING_TIMING:
		var pairs: Array = []
		for i: int in (engine.sequence.prompts as Array).size():
			pairs.append([i, NONE])
		return engine.submit(Fx.resolve_now(engine, pairs))
	return engine.submit(Fx.use(engine, "basic_attack"))


func _play(seed_value: int) -> Array:
	var hit_a := _hit(Status.ROTTING, 2, 1)
	var hit_b := _hit(Status.WEAKENED, 2)
	hit_b.impact_ms = 1300
	var setup := Fx.setup([Fx.attack("bite", [hit_a, hit_b])], {"seed": seed_value, "enemy_speed": 60})
	setup.tuning.damage_variance_percent = 10
	var engine := CombatEngine.new(setup)
	var events: Array = engine.start()
	var guard := 0
	while engine.result.is_empty() and guard < 60:
		guard += 1
		events.append_array(_step(engine))
	events.append(engine.snapshot())
	return events


func test_same_seed_same_commands_same_events() -> void:
	assert_eq(_play(11), _play(11))
	assert_ne(_play(11), [], "the fight produced events")


func test_shipped_marking_hits_are_few_hard_only_and_honest() -> void:
	var marking := 0
	for path: String in DirAccess.get_files_at("res://data/enemy_attacks"):
		if not path.ends_with(".tres"):
			continue
		var attack := load("res://data/enemy_attacks/" + path) as EnemyAttackData
		var in_string := 0
		for h: AttackHitData in attack.hits:
			if h.on_hit_status.is_empty() and h.on_hit_ap_drain == 0:
				continue
			in_string += 1
			assert_true(h.on_hit_hard_only, "%s: marks only in hard fights" % attack.id)
			assert_true(h.on_hit_status.is_empty() or Status.is_debuff(h.on_hit_status), "%s: a hero debuff" % attack.id)
			assert_true(h.on_hit_status.is_empty() or h.on_hit_ap_drain == 0, "%s: one mark per hit" % attack.id)
		assert_lte(in_string, 1, "%s: at most one marking hit per string" % attack.id)
		marking += in_string
	assert_gt(marking, 0, "some attacks mark")
	assert_lte(marking, 10, "marks stay sparing")


func test_the_tutorial_and_ordinary_fights_never_mark() -> void:
	var tuning := Tuning.new()
	for path: String in DirAccess.get_files_at("res://data/encounters"):
		if not path.ends_with(".tres"):
			continue
		var encounter := load("res://data/encounters/" + path) as EncounterData
		var setup := CombatSetup.from_encounter(encounter.duplicate(true) as EncounterData, tuning, 1)
		var hard := setup.forced_hits
		for e: EnemyData in setup.enemies:
			if hard or e.forced_hits:
				continue
			for a: EnemyAttackData in e.attacks:
				for h: AttackHitData in a.hits:
					assert_false(h.marks_in(false), "%s / %s: no mark outside a hard fight" % [path, a.id])


func test_setup_rejects_a_mark_that_is_not_a_hero_debuff() -> void:
	var setup := Fx.setup([Fx.attack("bite", [_hit(Status.EXPOSED)])])
	var problems := setup.validate()
	assert_gt(problems.size(), 0)
	assert_true(" ".join(problems).contains("not a hero debuff"))


func test_the_shipped_rot_combo_rots_every_hero_it_lands_on_in_a_hard_fight_only() -> void:
	var combo := load("res://data/enemy_attacks/husk_rot_combo.tres") as EnemyAttackData
	for hard: bool in [false, true]:
		var setup := Fx.setup([combo])
		setup.forced_hits = hard
		var engine := CombatEngine.new(setup)
		engine.start()
		assert_eq(String(engine.sequence.kind), "enemy_attack")
		var pairs: Array = []
		for i: int in (engine.sequence.prompts as Array).size():
			pairs.append([i, NONE])
		engine.submit(Fx.resolve_now(engine, pairs))
		for id: int in engine.party_ids():
			assert_eq(engine.get_combatant(id).has_status(Status.ROTTING), hard, "hard=%s hero %d" % [hard, id])
