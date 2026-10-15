extends GutTest
## Phase 2 rules (DESIGN 2.8, 2.10): skill presses, follow-ups and the team gauge, the team
## ultimate, Exposed, Guard, Taunt, Slow, Riposte, Payback, timeline shifts, healing, AP gifts,
## revive, and enemy intent. Exact numbers come from Tuning.new() and hand-made fixture fights.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")

const NONE: int = Defense.Outcome.NONE
const PARRY: int = Defense.Outcome.PARRY
const PRESS: int = Defense.Outcome.PRESS
const PERFECT: int = Defense.Outcome.PRESS_PERFECT
const FOE: int = Fx.ENEMY_ID
const ENEMY: int = AbilityData.Target.SINGLE_ENEMY
const ALLY: int = AbilityData.Target.ALLY
const OTHER: int = AbilityData.Target.OTHER_ALLY
const SELF: int = AbilityData.Target.SELF
const DOWNED: int = AbilityData.Target.DOWNED_ALLY
## Fixture party power with Tuning.new(): 40 x 90%, 40 x 120%, 40 x 100%.
const POWERS: Array[int] = [36, 48, 40]
## Party-first fights: turn costs c0 111, c1 90, c2 100; an enemy at speed 10 waits 1000.
const SLOW_ENEMY: int = 10


func _swipe() -> EnemyAttackData:
	return Fx.attack("swipe", [Fx.hit(900)])


func _party_hit(pct: int = 100) -> EnemyAttackData:
	return Fx.attack("wide", [Fx.hit(900, Fx.NORMAL, pct)], Fx.PARTY)


func _party_flurry() -> EnemyAttackData:
	return Fx.attack("wide_flurry", [Fx.hit(900), Fx.hit(1200), Fx.hit(1500)], Fx.PARTY)


func _cut(fields: Dictionary = {}) -> AbilityData:
	var f := {"damage_percent": 100, "follow_ups": true}
	f.merge(fields, true)
	return Fx.skill("cut", ENEMY, 0, [800], f)


func _use(engine: CombatEngine, ability_id: String, target: int = FOE) -> Array[Dictionary]:
	return engine.submit(Fx.use(engine, ability_id, target))


func _resolve(engine: CombatEngine, pairs: Array) -> Array[Dictionary]:
	return engine.submit(Fx.resolve_now(engine, pairs))


## Downs c0 with a party-wide 400% hit while c1 and c2 parry (enemy acts first). c1 acts next.
func _with_c0_down(kits: Array, options: Dictionary = {}) -> CombatEngine:
	var engine := Fx.kit_started(kits, [_party_hit(400)], options)
	_resolve(engine, [[0, NONE], [1, PARRY], [2, PARRY]])
	assert_false(engine.get_combatant(0).is_alive(), "c0 is down")
	assert_eq(engine.active_actor, 1, "c1 acts next")
	return engine


# --- presses ----------------------------------------------------------------------------------

func test_skill_declares_one_press_prompt_per_hit() -> void:
	var rend := Fx.skill("rend", ENEMY, 0, [800, 1100], {"damage_percent": 200, "press_damage_percent": 50})
	var engine := Fx.kit_started([[], [rend], []], [_swipe()], {"enemy_speed": SLOW_ENEMY})
	var events := _use(engine, "rend")
	var declared := Fx.first_of(events, "timed_sequence_declared")
	assert_eq(declared.kind, "skill")
	assert_eq(declared.source, 1)
	assert_eq(declared.targets, [FOE])
	assert_eq(engine.phase, CombatEngine.Phase.AWAITING_TIMING)
	var prompts: Array = declared.prompts
	assert_eq(prompts.size(), 2, "no follow-ups unless the skill has them")
	for i: int in 2:
		var p: Dictionary = prompts[i]
		assert_eq(p.role, "press")
		assert_eq(p.character, 1)
		assert_eq(p.at_ms, [800, 1100][i])
		assert_eq(p.kind, AttackHitData.Kind.PRESS)
		assert_true((p.windows as Dictionary).has(PRESS), "a good window")
		assert_true((p.windows as Dictionary).has(PERFECT), "a perfect window")
		var good: Array = p.windows[PRESS]
		var perfect: Array = p.windows[PERFECT]
		assert_true(int(good[0]) < int(perfect[0]) and int(perfect[1]) < int(good[1]), "perfect sits inside good")
		assert_eq(p.perfect, [PERFECT])
		assert_eq(p.press_damage, 96, "good: 48 x 200%")
		assert_eq(p.perfect_damage, 120, "perfect: 48 x 250%")
		assert_eq(p.damage, 48, "miss: half of good")


func test_perfect_good_and_missed_presses_deal_their_damage() -> void:
	var rend := Fx.skill("rend", ENEMY, 0, [800, 1100, 1400], {"damage_percent": 200, "press_damage_percent": 50})
	var engine := Fx.kit_started([[], [rend], []], [_swipe()], {"enemy_speed": SLOW_ENEMY})
	_use(engine, "rend")
	var events := _resolve(engine, [[0, PERFECT]])
	assert_eq(Fx.first_of(events, "prompt_resolved").perfect, true)
	assert_eq(Fx.first_of(events, "damage"), {"type": "damage", "source": 1, "target": FOE, "amount": 120,
			"hp": 1380, "max_hp": 1500, "cause": "ability", "crit": false})
	events = _resolve(engine, [[1, PRESS]])
	assert_eq(Fx.first_of(events, "prompt_resolved").perfect, false)
	assert_eq(Fx.first_of(events, "damage").amount, 96, "good: normal damage")
	events = _resolve(engine, [[2, NONE]])
	assert_eq(Fx.first_of(events, "damage").amount, 48, "miss: skill_miss_damage_percent of normal")
	assert_eq(Fx.first_of(events, "sequence_resolved").reason, "completed")
	assert_eq(engine.active_actor, 2, "the turn moved on")
	assert_eq(engine.phase, CombatEngine.Phase.AWAITING_ACTION)


func test_a_parry_result_on_a_press_prompt_is_a_miss() -> void:
	var engine := Fx.kit_started([[], [_cut()], []], [_swipe()], {"enemy_speed": SLOW_ENEMY})
	_use(engine, "cut")
	var events := _resolve(engine, [[0, PARRY]])
	assert_eq(Fx.first_of(events, "prompt_resolved").outcome, NONE)


# --- follow-ups and the team gauge -------------------------------------------------------------

func test_follow_ups_are_declared_for_each_other_ally() -> void:
	var tuning := Tuning.new()
	var engine := Fx.kit_started([[], [_cut()], []], [_swipe()], {"enemy_speed": SLOW_ENEMY, "tuning": tuning})
	var prompts: Array = Fx.first_of(_use(engine, "cut"), "timed_sequence_declared").prompts
	assert_eq(prompts.size(), 3)
	var first: Dictionary = prompts[1]
	var second: Dictionary = prompts[2]
	assert_eq([first.character, second.character], [0, 2], "the other allies, in slot order")
	assert_eq(first.role, "follow_up")
	assert_eq(first.requires, [0])
	assert_eq(first.at_ms, 800 + tuning.follow_up_delay_ms)
	assert_eq(second.at_ms, 800 + tuning.follow_up_delay_ms + tuning.follow_up_gap_ms)
	assert_eq(first.damage, 0, "a missed follow-up does nothing")
	assert_eq(first.press_damage, CombatMath.percent(36, tuning.follow_up_percent))
	assert_eq(first.perfect_damage, CombatMath.percent(36, tuning.follow_up_perfect_percent))
	assert_ne(first.hit, second.hit, "each follow-up is its own hit")


func test_good_follow_up_strikes_and_fills_the_gauge() -> void:
	var engine := Fx.kit_started([[], [_cut()], []], [_swipe()], {"enemy_speed": SLOW_ENEMY})
	_use(engine, "cut")
	_resolve(engine, [[0, PRESS]])
	var events := _resolve(engine, [[1, PRESS]])
	assert_eq(Fx.first_of(events, "damage"), {"type": "damage", "source": 0, "target": FOE, "amount": 11,
			"hp": 1500 - 48 - 11, "max_hp": 1500, "cause": "follow_up", "crit": false})
	assert_eq(Fx.first_of(events, "team_gauge"), {"type": "team_gauge", "value": 10, "delta": 10, "max": 100})
	events = _resolve(engine, [[2, NONE]])
	assert_eq(Fx.of_type(events, "damage").size(), 0)
	assert_eq(Fx.of_type(events, "team_gauge").size(), 0)
	assert_eq(engine.team_gauge, 10)


func test_follow_ups_are_voided_when_every_press_missed() -> void:
	var engine := Fx.kit_started([[], [_cut()], []], [_swipe()], {"enemy_speed": SLOW_ENEMY})
	_use(engine, "cut")
	var events := _resolve(engine, [[0, NONE]])
	assert_eq(Fx.first_of(events, "prompts_voided"), {"type": "prompts_voided", "seq": 1, "prompts": [1, 2],
			"reason": "no_good_press"})
	assert_eq(Fx.first_of(events, "sequence_resolved").reason, "completed")
	assert_eq(engine.active_actor, 2)


func test_a_follow_up_sent_as_good_without_a_good_press_counts_as_a_miss() -> void:
	var multi := Fx.skill("multi", ENEMY, 0, [800, 1100], {"damage_percent": 50, "follow_ups": true})
	var engine := Fx.kit_started([[], [multi], []], [_swipe()], {"enemy_speed": SLOW_ENEMY})
	_use(engine, "multi")
	# Both presses must be in before a follow-up can be judged; one good press is enough.
	var events := _resolve(engine, [[0, NONE], [1, PRESS], [2, PRESS]])
	assert_eq(Fx.of_type(events, "team_gauge").size(), 1)
	engine = Fx.kit_started([[], [multi], []], [_swipe()], {"enemy_speed": SLOW_ENEMY})
	_use(engine, "multi")
	events = _resolve(engine, [[0, NONE], [1, NONE]])
	assert_eq(Fx.first_of(events, "prompts_voided").reason, "no_good_press")


func test_killing_the_target_voids_the_rest_of_the_skill() -> void:
	var tuning := Tuning.new()
	tuning.base_enemy_hp = 50
	var multi := Fx.skill("multi", ENEMY, 0, [800, 1100], {"damage_percent": 120, "follow_ups": true})
	var engine := Fx.kit_started([[], [multi], []], [_swipe()], {"enemy_speed": SLOW_ENEMY, "tuning": tuning})
	_use(engine, "multi")
	var events := _resolve(engine, [[0, PRESS]])
	assert_eq(Fx.first_of(events, "prompts_voided").reason, "targets_down")
	assert_eq(Fx.first_of(events, "sequence_resolved").reason, "targets_down")
	assert_eq(Fx.first_of(events, "combat_ended").result, "victory")


# --- team ultimate ----------------------------------------------------------------------------

func test_team_ultimate_needs_a_full_gauge() -> void:
	var ult := Fx.skill("ult", ENEMY, 0, [900], {"damage_percent": 200, "team_ultimate": true})
	var engine := Fx.kit_started([[], [], []], [_swipe()], {"enemy_speed": SLOW_ENEMY, "team_ultimate": ult})
	assert_true(engine.get_combatant(1).ability_ids.has("ult"), "every party member is offered it")
	assert_false(engine.can_use(1, "ult"))
	var before := engine.snapshot()
	var events := _use(engine, "ult")
	assert_eq(events.size(), 1)
	assert_eq(events[0].reason, "gauge_not_full")
	assert_eq(engine.snapshot(), before)


func test_team_ultimate_strikes_with_everyone_empties_the_gauge_and_revives() -> void:
	var ult := Fx.skill("ult", ENEMY, 0, [900], {"damage_percent": 200, "press_damage_percent": 50, "team_ultimate": true})
	var engine := _with_c0_down([[], [], []], {"team_ultimate": ult})
	var snap := engine.snapshot()
	snap.team_gauge = 100
	engine = CombatEngine.restore(Fx.kit_setup([[], [], []], [_party_hit(400)], {"team_ultimate": ult}), snap)
	assert_true(engine.can_use(1, "ult"))
	var events := _use(engine, "ult")
	assert_eq(Fx.first_of(events, "team_gauge"), {"type": "team_gauge", "value": 0, "delta": -100, "max": 100})
	var prompts: Array = Fx.first_of(events, "timed_sequence_declared").prompts
	assert_eq(prompts.size(), 2, "one press per standing party member")
	assert_eq([prompts[0].character, prompts[1].character], [1, 2])
	events = _resolve(engine, [[0, PERFECT], [1, NONE]])
	var damage := Fx.of_type(events, "damage")
	assert_eq(damage.size(), 2)
	assert_eq([damage[0].source, damage[0].amount], [1, 120], "perfect: 48 x 250%")
	assert_eq([damage[1].source, damage[1].amount], [2, 40], "miss: half of 40 x 200%")
	var revived := Fx.first_of(events, "revived")
	assert_eq(revived, {"type": "revived", "source": 1, "target": 0, "hp": 25, "max_hp": 100})
	assert_true(engine.get_combatant(0).is_alive())


# --- revive, heal, AP -------------------------------------------------------------------------

func test_revive_brings_a_downed_ally_back_and_retargets_party_intents() -> void:
	var revive := Fx.skill("revive", DOWNED, 0, [800], {"damage_percent": 0, "revive_percent": 25, "press_revive_percent": 25})
	var engine := _with_c0_down([[], [revive], []])
	assert_eq(engine.intents[FOE].targets, [1, 2], "the next party-wide attack aims at who is standing")
	assert_eq(engine.valid_targets(1, "revive"), [0])
	var before := engine.snapshot()
	var bad := _use(engine, "revive", 2)
	assert_eq(bad[0].reason, "invalid_target", "only a downed ally")
	assert_eq(engine.snapshot(), before)
	_use(engine, "revive", 0)
	var events := _resolve(engine, [[0, PERFECT]])
	assert_eq(Fx.first_of(events, "revived"), {"type": "revived", "source": 1, "target": 0, "hp": 50, "max_hp": 100})
	var c0 := engine.get_combatant(0)
	assert_true(c0.is_alive())
	var intent := Fx.first_of(events, "intent")
	assert_eq(intent.targets, [0, 1, 2], "the revived ally is a target again")
	assert_true(Fx.index_of(events, "turn_order") > Fx.index_of(events, "revived"), "the timeline is re-sent")
	# DESIGN 2.1: the revived ally's next turn is one turn cost after the revive.
	assert_eq(c0.next_turn_at, 90 + 111)


func test_mend_heals_up_to_max_hp() -> void:
	var mend := Fx.skill("mend", ALLY, 0, [800], {"damage_percent": 0, "heal_percent": 10, "press_heal_percent": 50})
	var engine := Fx.kit_started([[], [mend], []], [_party_hit()])
	_resolve(engine, [[0, NONE], [1, NONE], [2, NONE]])
	assert_eq(engine.get_combatant(0).hp, 72)
	_use(engine, "mend", 0)
	var events := _resolve(engine, [[0, NONE]])
	assert_eq(Fx.first_of(events, "healed"), {"type": "healed", "source": 1, "target": 0, "amount": 10, "hp": 82, "max_hp": 100})


func test_pass_the_torch_gives_ap_to_another_ally() -> void:
	var torch := Fx.skill("torch", OTHER, 0, [800], {"damage_percent": 0, "give_ap": 2, "press_give_ap": 1})
	var engine := Fx.kit_started([[], [torch], []], [_swipe()], {"enemy_speed": SLOW_ENEMY})
	assert_eq(engine.valid_targets(1, "torch"), [0, 2], "not the user")
	_use(engine, "torch", 2)
	var events := _resolve(engine, [[0, PERFECT]])
	assert_eq(Fx.first_of(events, "ap_changed"), {"type": "ap_changed", "character": 2, "delta": 3, "ap": 4, "reason": "given"})


func test_effect_bonus_needs_every_press_perfect() -> void:
	var step := Fx.skill("step", ENEMY, 0, [800, 1000], {"damage_percent": 50, "ap_gain": 1, "press_ap_gain": 1})
	var engine := Fx.kit_started([[], [step], []], [_swipe()], {"enemy_speed": SLOW_ENEMY})
	_use(engine, "step")
	var events := _resolve(engine, [[0, PERFECT], [1, PRESS]])
	assert_eq(Fx.first_of(events, "ap_changed").delta, 1, "one only good: base gain only")
	_use(engine, "basic_attack")
	_use(engine, "basic_attack")
	_use(engine, "step")
	events = _resolve(engine, [[0, PERFECT], [1, PERFECT]])
	assert_eq(Fx.first_of(events, "ap_changed").delta, 2, "all perfect: base + press gain")


# --- statuses ---------------------------------------------------------------------------------

func test_exposed_is_consumed_by_the_next_skill_that_consumes_it() -> void:
	var reveal := Fx.skill("reveal", ENEMY, 0, [800], {"damage_percent": 60, "status": Status.EXPOSED, "consumes_exposed": false})
	var jab := Fx.skill("jab", ENEMY, 0, [800], {"damage_percent": 50, "consumes_exposed": false})
	var rend := Fx.skill("rend", ENEMY, 0, [800], {"damage_percent": 220, "exposed_bonus_percent": 150})
	var engine := Fx.kit_started([[jab], [rend], [reveal]], [_swipe()], {"enemy_speed": SLOW_ENEMY})
	_use(engine, "basic_attack")
	_use(engine, "reveal")
	var events := _resolve(engine, [[0, NONE]])
	assert_eq(Fx.first_of(events, "status_changed"), {"type": "status_changed", "target": FOE, "status": "exposed",
			"active": true, "turns": 0, "source": 2})
	_use(engine, "jab")
	events = _resolve(engine, [[0, PRESS]])
	assert_eq(Fx.of_type(events, "status_changed").size(), 0, "a skill that does not consume it leaves it")
	assert_eq(Fx.first_of(events, "damage").amount, 18, "and gets no bonus")
	events = _use(engine, "rend")
	assert_eq((Fx.first_of(events, "timed_sequence_declared").prompts[0] as Dictionary).press_damage, 265, "106 x 250%")
	events = _resolve(engine, [[0, PRESS]])
	assert_eq(Fx.first_of(events, "damage").amount, 265)
	var removed := Fx.first_of(events, "status_changed")
	assert_eq([removed.status, removed.active], ["exposed", false])
	assert_false(engine.get_combatant(FOE).has_status(Status.EXPOSED))


func test_guard_halves_enemy_damage_until_the_holders_turn() -> void:
	var guard := Fx.skill("guard", OTHER, 0, [800], {"damage_percent": 0, "status": Status.GUARDED, "press_status_on_self": true})
	var engine := Fx.kit_started([[], [guard], []], [_party_hit()], {"enemy_speed": 100})
	_use(engine, "guard", 0)
	var events := _resolve(engine, [[0, PERFECT]])
	var guarded: Array = []
	for e: Dictionary in Fx.of_type(events, "status_changed"):
		guarded.append(e.target)
	assert_eq(guarded, [0, 1], "the target, and the user after a good press")
	events = _use(engine, "basic_attack")
	var prompts: Array = Fx.first_of(events, "timed_sequence_declared").prompts
	assert_eq([prompts[0].damage, prompts[1].damage, prompts[2].damage], [14, 14, 28])
	events = _resolve(engine, [[0, NONE], [1, NONE], [2, NONE]])
	assert_eq(engine.active_actor, 0)
	var ended := Fx.first_of(events, "status_changed")
	assert_eq([ended.target, ended.status, ended.active], [0, "guarded", false], "ends when c0's turn starts")
	assert_true(engine.get_combatant(1).has_status(Status.GUARDED), "c1's lasts until c1's turn")


func test_taunt_redirects_the_next_single_target_attack() -> void:
	var taunt := Fx.skill("taunt", ENEMY, 0, [800], {"damage_percent": 0, "status": Status.TAUNTED})
	for seed_value: int in 6:
		# Turn order: c1 90, c2 100, enemy 100 (c2 first on the tie).
		var engine := Fx.kit_started([[], [taunt], []], [_swipe()], {"enemy_speed": 100, "seed": seed_value})
		var before: Array = engine.intents[FOE].targets
		_use(engine, "taunt")
		var events := _resolve(engine, [[0, PRESS]])
		assert_true(engine.get_combatant(FOE).has_status(Status.TAUNTED))
		assert_eq(engine.intents[FOE].targets, [1], "the intent now aims at the taunter")
		assert_eq(Fx.of_type(events, "intent").size(), 0 if before == [1] else 1, "re-announced only if it changed")
		events = _use(engine, "basic_attack")
		assert_eq(Fx.first_of(events, "timed_sequence_declared").targets, [1])
		var used := Fx.first_of(events, "status_changed")
		assert_eq([used.status, used.active], ["taunted", false], "used up by the attack")


func test_taunt_waits_through_party_wide_attacks() -> void:
	var taunt := Fx.skill("taunt", ENEMY, 0, [800], {"damage_percent": 0, "status": Status.TAUNTED})
	var engine := Fx.kit_started([[], [taunt], []], [_party_hit()], {"enemy_speed": 100})
	_use(engine, "taunt")
	_resolve(engine, [[0, NONE]])
	var events := _use(engine, "basic_attack")
	assert_eq(Fx.first_of(events, "timed_sequence_declared").targets, [0, 1, 2])
	assert_true(engine.get_combatant(FOE).has_status(Status.TAUNTED), "kept for a single-target attack")


func test_slow_rescales_the_wait_and_wears_off_after_its_turns() -> void:
	var hamstring := Fx.skill("hamstring", ENEMY, 5, [800], {"damage_percent": 100, "status": Status.SLOWED, "status_turns": 2})
	var tuning := Tuning.new()
	tuning.start_ap = 5
	# Costs all of c1's AP, so the bot below cannot use it again within two enemy turns.
	var engine := Fx.kit_started([[], [hamstring], []], [_swipe()], {"enemy_speed": 100, "tuning": tuning})
	var foe := engine.get_combatant(FOE)
	_use(engine, "hamstring")
	var events := _resolve(engine, [[0, NONE]])
	assert_eq(foe.speed, 75)
	# DESIGN 2.1: next = now + (next - now) x old / new = 90 + 10 x 100 / 75.
	assert_eq(foe.next_turn_at, 90 + 13)
	assert_true(Fx.index_of(events, "turn_order") > Fx.index_of(events, "status_changed"))
	var bot := preload("res://tests/helpers/combat_bot.gd").new()
	var enemy_turns := 0
	for i: int in 60:
		if not foe.has_status(Status.SLOWED) or engine.phase == CombatEngine.Phase.ENDED:
			break
		events = engine.submit(bot.next_command(engine))
		for e: Dictionary in Fx.of_type(events, "turn_ended"):
			if int(e.actor) == FOE:
				enemy_turns += 1
	assert_eq(enemy_turns, 2, "slowed for exactly 2 of its turns")
	assert_eq(foe.speed, 100, "speed restored")


func test_shield_bash_pushes_the_enemy_turn_and_hasten_pulls_an_ally_turn() -> void:
	var bash := Fx.skill("bash", ENEMY, 0, [800], {"damage_percent": 100, "turn_delay_percent": 30, "press_turn_delay_percent": 30})
	var hasten := Fx.skill("hasten", OTHER, 0, [800], {"damage_percent": 0, "turn_hasten_percent": 50, "press_turn_hasten_percent": 25})
	var engine := Fx.kit_started([[], [bash], [hasten]], [_swipe()], {"enemy_speed": 100})
	_use(engine, "bash")
	var events := _resolve(engine, [[0, PERFECT]])
	assert_eq(Fx.first_of(events, "turn_shifted"), {"type": "turn_shifted", "target": FOE, "delta": 60})
	assert_eq(engine.get_combatant(FOE).next_turn_at, 160)
	assert_eq(engine.active_actor, 2)
	_use(engine, "hasten", 0)
	events = _resolve(engine, [[0, NONE]])
	# c0 waits 111 - 100 = 11; half of it (rounded) comes off.
	assert_eq(Fx.first_of(events, "turn_shifted"), {"type": "turn_shifted", "target": 0, "delta": -6})
	assert_eq(engine.active_actor, 0, "c0 now acts before the enemy")
	assert_eq(engine.time_now, 105)


func test_riposte_doubles_the_holders_counter_share() -> void:
	var riposte := Fx.skill("riposte", SELF, 0, [800], {"damage_percent": 0, "status": Status.RIPOSTE})
	var engine := Fx.kit_started([[], [riposte], []], [_party_hit()], {"enemy_speed": 100})
	_use(engine, "riposte")
	_resolve(engine, [[0, NONE]])
	_use(engine, "basic_attack")
	var events := _resolve(engine, [[0, PARRY], [1, PARRY], [2, PARRY]])
	var counter := Fx.first_of(events, "damage")
	assert_eq(counter.cause, "team_counter")
	# 36 x 120% + 48 x 240% + 40 x 120% = 43 + 115 + 48
	assert_eq(counter.amount, 206)


func test_payback_grows_with_perfect_defences_since_the_last_turn() -> void:
	var payback := Fx.skill("payback", ENEMY, 0, [800], {"damage_percent": 100, "per_perfect_defense_percent": 50})
	var engine := Fx.kit_started([[], [payback], []], [_party_flurry()])
	_resolve(engine, [[0, PARRY], [1, PARRY], [2, PARRY]])
	_resolve(engine, [[3, PARRY], [4, PARRY], [5, PARRY]])
	_resolve(engine, [[6, PARRY], [7, PARRY], [8, PARRY]])
	assert_eq(engine.active_actor, 1)
	var events := _use(engine, "payback")
	assert_eq((Fx.first_of(events, "timed_sequence_declared").prompts[0] as Dictionary).press_damage, 120, "48 x 250%")
	_resolve(engine, [[0, NONE]])
	assert_eq(engine.get_combatant(1).perfect_defenses, 0, "the count starts again after the turn")


# --- enemy intent -----------------------------------------------------------------------------

func test_every_enemy_announces_its_intent_at_the_start() -> void:
	var foes: Array = [Fx.enemy("foe", [_swipe()], 10), Fx.enemy("foe", [_party_hit()], 10)]
	var engine := CombatEngine.new(Fx.kit_setup([], [_swipe()], {"enemies": foes}))
	var events := engine.start()
	var intents := Fx.of_type(events, "intent")
	assert_eq(intents.size(), 2)
	assert_eq([intents[0].enemy, intents[1].enemy], [3, 4])
	assert_eq(intents[1].mode, Fx.PARTY)
	assert_eq(intents[1].targets, [0, 1, 2])
	assert_eq(intents[0].kinds, [Fx.NORMAL])
	assert_eq(intents[0].name, "Attack swipe")
	assert_eq(String(Fx.first_of(events, "combat_started").fighters[3].display_name), "foe A", "same names get letters")
	assert_eq(String(Fx.first_of(events, "combat_started").fighters[4].display_name), "foe B")


func test_the_enemy_does_what_its_intent_said() -> void:
	var bot_script := preload("res://tests/helpers/combat_bot.gd")
	var checked := 0
	for seed_value: int in 6:
		for defence: int in [bot_script.Defence.PERFECT, bot_script.Defence.MIXED]:
			var engine := CombatEngine.new(Fx.shipped_setup(seed_value))
			var bot = bot_script.new(defence)
			var last: Dictionary = {}
			var events: Array[Dictionary] = engine.start()
			for step: int in 3000:
				for e: Dictionary in events:
					if e.type == "intent":
						last[int(e.enemy)] = e
					elif e.type == "timed_sequence_declared" and e.kind == "enemy_attack":
						var said: Dictionary = last[int(e.source)]
						assert_eq([e.action, e.targets], [said.attack, said.targets], "seed %d: as announced" % seed_value)
						checked += 1
				if engine.phase == CombatEngine.Phase.ENDED:
					break
				events = engine.submit(bot.next_command(engine))
	assert_gt(checked, 50, "checked many attacks")


func test_an_intent_retargets_when_its_target_goes_down() -> void:
	var heavy := Fx.attack("heavy", [Fx.hit(900, Fx.NORMAL, 400)], Fx.PARTY)
	var foes: Array = [Fx.enemy("a", [heavy], 200), Fx.enemy("b", [_swipe()], 150)]
	var engine := CombatEngine.new(Fx.kit_setup([], [_swipe()], {"enemies": foes}))
	engine.start()
	var aimed := int((engine.intents[4].targets as Array)[0])
	var pairs: Array = []
	for i: int in 3:
		pairs.append([i, NONE if i == aimed else PARRY])
	var events := _resolve(engine, pairs)
	var retarget := {}
	for e: Dictionary in Fx.of_type(events, "intent"):
		if int(e.enemy) == 4:
			retarget = e
	assert_false(retarget.is_empty(), "enemy b re-announces")
	assert_ne(int((retarget.targets as Array)[0]), aimed)
	assert_true(engine.get_combatant(int((retarget.targets as Array)[0])).is_alive())
