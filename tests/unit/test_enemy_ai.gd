extends GutTest
## Smarter enemies (DESIGN.md 2.3, card #189): anti-repeat, cooldowns, situational weights and the
## target rules. Hand-made fights from the fixtures; the numbers come from Tuning.new().

const Fx := preload("res://tests/helpers/combat_fixtures.gd")
const Bot := preload("res://tests/helpers/combat_bot.gd")

const HERO_A: int = 0
const HERO_B: int = 1
const HERO_C: int = 2
const FOE_ID: int = Fx.ENEMY_ID


func _atk(id: String, weight: int = 1) -> EnemyAttackData:
	return Fx.attack(id, [Fx.hit(900)], Fx.SINGLE, weight)


## A started fight where the enemy has `attacks`, with the rule set on its data.
func _engine(attacks: Array, rule: int = EnemyData.TargetRule.RANDOM, bias: int = 0, options: Dictionary = {}) -> CombatEngine:
	var setup := Fx.setup(attacks, options)
	setup.enemies[0].target_rule = rule as EnemyData.TargetRule
	setup.enemies[0].target_bias_percent = bias
	var engine := CombatEngine.new(setup)
	engine.start()
	return engine


func _foe(engine: CombatEngine) -> Combatant:
	return engine.get_combatant(FOE_ID)


func _set_hp(engine: CombatEngine, hero: int, hp: int) -> void:
	var c := engine.get_combatant(hero)
	c.hp = clampi(hp, 0, c.max_hp)


func _sum(values: Array[int]) -> int:
	var total := 0
	for v: int in values:
		total += v
	return total


func _hits(engine: CombatEngine, draws: int) -> Array[int]:
	var counts: Array[int] = [0, 0, 0]
	var attack: EnemyAttackData = engine.get_attack(_foe(engine).attack_ids[0])
	for _i: int in draws:
		var targets := engine._pick_targets(_foe(engine), attack)
		assert_eq(targets.size(), 1)
		counts[targets[0]] += 1
	return counts


## The ids of the attacks the enemy used, in order, over a whole fight the party cannot hurt it in.
func _used_in_fight(attacks: Array, seed_value: int) -> Array[String]:
	var engine := CombatEngine.new(Fx.setup(attacks, {"seed": seed_value, "hp_percents": [1000, 1000, 1000],
			"enemy_hp_percent": 3000, "enemy_power_percent": 10}))
	var run: Dictionary = Bot.new(Bot.Defence.MISS).play(engine)
	var used: Array[String] = []
	for e: Dictionary in Fx.of_type(run.events as Array, "timed_sequence_declared"):
		if String(e.kind) == "enemy_attack":
			used.append(String(e.action))
	return used


func _longest_run(used: Array[String], id: String) -> int:
	var longest := 0
	var run := 0
	for u: String in used:
		run = run + 1 if u == id else 0
		longest = maxi(longest, run)
	return longest


# --- anti-repeat and cooldown -----------------------------------------------------------------

func test_defaults_keep_most_attack_files_unchanged() -> void:
	var a := EnemyAttackData.new()
	assert_eq(a.max_in_a_row, 2)
	assert_eq(a.cooldown_turns, 0)
	assert_eq(a.finisher_weight_percent, 100)
	assert_eq(a.low_hp_weight_percent, 100)


func test_an_attack_is_never_used_more_than_max_in_a_row_times() -> void:
	for seed_value: int in [1, 2, 3, 4]:
		var used := _used_in_fight([_atk("heavy", 100), _atk("light", 1)], seed_value)
		assert_gt(used.size(), 8, "the fight gave enough enemy turns")
		assert_lte(_longest_run(used, "heavy"), 2, "heavy at most twice running (seed %d)" % seed_value)
		assert_true(used.has("light"), "the other move comes in")


func test_max_in_a_row_one_alternates() -> void:
	var heavy := _atk("heavy", 100)
	heavy.max_in_a_row = 1
	var used := _used_in_fight([heavy, _atk("light", 1)], 5)
	assert_gt(used.size(), 8)
	assert_eq(_longest_run(used, "heavy"), 1)


func test_max_in_a_row_zero_means_no_limit() -> void:
	var heavy := _atk("heavy", 100)
	heavy.max_in_a_row = 0
	var used := _used_in_fight([heavy, _atk("light", 1)], 5)
	assert_gt(_longest_run(used, "heavy"), 2, "with no limit the heavy move streaks")


func test_a_single_move_enemy_keeps_using_it() -> void:
	var used := _used_in_fight([_atk("only")], 3)
	assert_gt(used.size(), 4)
	for id: String in used:
		assert_eq(id, "only")


func test_cooldown_blocks_the_move_for_that_many_enemy_turns() -> void:
	var big := _atk("big", 100)
	big.max_in_a_row = 0
	big.cooldown_turns = 2
	for seed_value: int in [1, 2, 3]:
		var used := _used_in_fight([big, _atk("light", 1)], seed_value)
		assert_gt(used.size(), 8)
		for i: int in used.size():
			if used[i] == "big":
				for j: int in range(i + 1, mini(used.size(), i + 3)):
					assert_ne(used[j], "big", "no big within 2 turns of big (seed %d, turn %d)" % [seed_value, i])
		assert_true(used.has("big"))


func test_cooldown_counts_down_at_the_start_of_each_turn() -> void:
	var c := Combatant.new()
	c.note_attack("big", 2, -1)
	assert_eq(int(c.attack_cooldowns.big), 2)
	c.tick_cooldowns()
	assert_eq(int(c.attack_cooldowns.big), 1)
	c.tick_cooldowns()
	assert_false(c.attack_cooldowns.has("big"))


func test_history_is_capped_and_counts_the_latest_run() -> void:
	var c := Combatant.new()
	for i: int in 12:
		c.note_attack("a" if i < 10 else "b", 0, -1)
	assert_eq(c.recent_attacks.size(), Combatant.RECENT_MAX)
	assert_eq(c.repeat_run("b"), 2)
	assert_eq(c.repeat_run("a"), 0)


func test_everything_blocked_falls_back_rather_than_skipping_the_turn() -> void:
	var a := _atk("a")
	var b := _atk("b")
	var engine := _engine([a, b])
	var foe := _foe(engine)
	foe.attack_cooldowns = {"a": 2, "b": 2}
	var intent := engine._choose_intent(foe)
	assert_false(intent.is_empty())


# --- situational weights ----------------------------------------------------------------------

func test_finisher_weight_applies_only_when_a_hero_is_low() -> void:
	var finisher := _atk("finisher", 10)
	finisher.finisher_below_percent = 30
	finisher.finisher_weight_percent = 500
	var engine := _engine([finisher, _atk("plain", 10)])
	var foe := _foe(engine)
	var hero := engine.get_combatant(HERO_B)
	assert_eq(engine._attack_weight(foe, finisher), 10, "everyone healthy")
	hero.hp = hero.max_hp * 30 / 100
	assert_eq(engine._attack_weight(foe, finisher), 50, "a hero at 30%")
	hero.hp = hero.max_hp * 31 / 100
	assert_eq(engine._attack_weight(foe, finisher), 10, "31% is out of range")
	hero.hp = 0
	assert_eq(engine._attack_weight(foe, finisher), 10, "a downed hero does not count")


func test_low_hp_weight_applies_when_the_enemy_is_hurt() -> void:
	var rage := _atk("rage", 10)
	rage.low_hp_below_percent = 50
	rage.low_hp_weight_percent = 300
	var engine := _engine([rage, _atk("plain", 10)])
	var foe := _foe(engine)
	assert_eq(engine._attack_weight(foe, rage), 10)
	foe.hp = foe.max_hp / 2
	assert_eq(engine._attack_weight(foe, rage), 30)
	foe.hp = foe.max_hp / 2 + 1
	assert_eq(engine._attack_weight(foe, rage), 10)


func test_the_finisher_is_picked_more_often_when_a_hero_is_low() -> void:
	var finisher := _atk("finisher", 1)
	finisher.finisher_below_percent = 40
	finisher.finisher_weight_percent = 1000
	finisher.max_in_a_row = 0
	var engine := _engine([finisher, _atk("plain", 10)])
	var foe := _foe(engine)
	var before := 0
	var after := 0
	for _i: int in 400:
		before += 1 if engine._choose_intent(foe).attack == "finisher" else 0
	_set_hp(engine, HERO_C, 1)
	for _i: int in 400:
		after += 1 if engine._choose_intent(foe).attack == "finisher" else 0
	assert_lt(before, 80, "rare while everyone is healthy (about 9%)")
	assert_gt(after, 160, "common once a hero is low (about 50%)")


# --- target rules -----------------------------------------------------------------------------

func test_random_rule_is_even() -> void:
	var engine := _engine([_atk("a")])
	var counts := _hits(engine, 600)
	for n: int in counts:
		assert_between(n, 140, 260)


func test_wounded_weights_grow_with_missing_hp() -> void:
	var engine := _engine([_atk("a")], EnemyData.TargetRule.WOUNDED, 300)
	var foe := _foe(engine)
	var living := engine.living_party_ids()
	assert_eq(engine._target_weights(foe, living), [100, 100, 100] as Array[int])
	var b := engine.get_combatant(HERO_B)
	b.hp = b.max_hp / 2
	var c := engine.get_combatant(HERO_C)
	c.hp = 1
	var weights := engine._target_weights(foe, living)
	assert_eq(weights[0], 100)
	assert_eq(weights[1], 250, "half the HP gone = 100 + 50 x 3")
	assert_gt(weights[2], 380, "nearly dead = nearly 100 + 100 x 3")


func test_wounded_hunts_the_weak_hero_but_not_always() -> void:
	var engine := _engine([_atk("a")], EnemyData.TargetRule.WOUNDED, 300)
	_set_hp(engine, HERO_C, 1)
	var counts := _hits(engine, 900)
	assert_gt(counts[HERO_C], counts[HERO_A] * 2, "the near-dead hero is hit about 4 times as often")
	assert_gt(counts[HERO_A], 50, "the healthy ones still get hit")
	assert_gt(counts[HERO_B], 50)


func test_lowest_hp_picks_the_weakest_with_the_bias() -> void:
	var engine := _engine([_atk("a")], EnemyData.TargetRule.LOWEST_HP, 200)
	var foe := _foe(engine)
	_set_hp(engine, HERO_B, 5)
	assert_eq(engine._target_weights(foe, engine.living_party_ids()), [100, 300, 100] as Array[int])
	var counts := _hits(engine, 900)
	assert_gt(counts[HERO_B], 400, "about 60 percent")
	assert_lt(counts[HERO_B], 700)
	assert_gt(counts[HERO_A], 100)


func test_lowest_hp_with_a_tie_adds_the_bias_once() -> void:
	var engine := _engine([_atk("a")], EnemyData.TargetRule.LOWEST_HP, 200)
	assert_eq(_sum(engine._target_weights(_foe(engine), engine.living_party_ids())), 500)


func test_downed_heroes_are_never_picked() -> void:
	for rule: int in [EnemyData.TargetRule.RANDOM, EnemyData.TargetRule.WOUNDED, EnemyData.TargetRule.LOWEST_HP,
			EnemyData.TargetRule.MARKED, EnemyData.TargetRule.AVOID_LAST]:
		var engine := _engine([_atk("a")], rule, 500)
		_set_hp(engine, HERO_A, 0)
		var counts := _hits(engine, 200)
		assert_eq(counts[HERO_A], 0, "rule %d" % rule)
		assert_eq(counts[HERO_B] + counts[HERO_C], 200)


func test_escaped_heroes_are_never_picked() -> void:
	var engine := _engine([_atk("a")], EnemyData.TargetRule.WOUNDED, 500)
	engine.get_combatant(HERO_C).escaped = true
	assert_eq(_hits(engine, 200)[HERO_C], 0)


func test_marked_rule_prefers_heroes_under_exposed_or_marked() -> void:
	var engine := _engine([_atk("a")], EnemyData.TargetRule.MARKED, 300)
	var foe := _foe(engine)
	assert_eq(engine._target_weights(foe, engine.living_party_ids()), [100, 100, 100] as Array[int], "nobody marked: plain random")
	engine.get_combatant(HERO_A).statuses[Status.EXPOSED] = {"turns": 1, "source": FOE_ID}
	engine.get_combatant(HERO_C).statuses[Status.MARKED] = {"turns": 2, "source": FOE_ID}
	assert_eq(engine._target_weights(foe, engine.living_party_ids()), [400, 100, 400] as Array[int])


func test_avoid_last_spreads_the_hits() -> void:
	var engine := _engine([_atk("a")], EnemyData.TargetRule.AVOID_LAST, 200)
	var foe := _foe(engine)
	foe.last_target = -1
	assert_eq(engine._target_weights(foe, engine.living_party_ids()), [300, 300, 300] as Array[int], "no last target yet")
	foe.last_target = HERO_B
	assert_eq(engine._target_weights(foe, engine.living_party_ids()), [300, 100, 300] as Array[int])


func test_a_lone_hero_is_the_only_target() -> void:
	var engine := _engine([_atk("a")], EnemyData.TargetRule.WOUNDED, 300)
	_set_hp(engine, HERO_A, 0)
	_set_hp(engine, HERO_B, 0)
	var counts := _hits(engine, 20)
	assert_eq(counts[HERO_C], 20)


func test_taunt_still_wins_over_every_rule() -> void:
	for rule: int in [EnemyData.TargetRule.WOUNDED, EnemyData.TargetRule.LOWEST_HP, EnemyData.TargetRule.AVOID_LAST]:
		var engine := _engine([_atk("a")], rule, 1000)
		_set_hp(engine, HERO_C, 1)
		_foe(engine).statuses[Status.TAUNTED] = {"turns": 1, "source": HERO_A}
		var counts := _hits(engine, 100)
		assert_eq(counts[HERO_A], 100, "rule %d" % rule)


func test_party_wide_attacks_ignore_the_rule() -> void:
	var sweep := Fx.attack("sweep", [Fx.hit(900)], Fx.PARTY)
	var engine := _engine([sweep], EnemyData.TargetRule.LOWEST_HP, 1000)
	_set_hp(engine, HERO_B, 1)
	assert_eq(engine._pick_targets(_foe(engine), sweep), [HERO_A, HERO_B, HERO_C] as Array[int])


func test_the_enemy_remembers_the_hero_it_hit() -> void:
	var engine := _engine([_atk("a")], EnemyData.TargetRule.AVOID_LAST, 300, {"hp_percents": [1000, 1000, 1000],
			"enemy_hp_percent": 3000, "enemy_power_percent": 10})
	var run: Dictionary = Bot.new(Bot.Defence.MISS).play(engine)
	var hit_order: Array[int] = []
	for e: Dictionary in Fx.of_type(run.events as Array, "timed_sequence_declared"):
		if String(e.kind) == "enemy_attack":
			hit_order.append(int((e.targets as Array)[0]))
	assert_gt(hit_order.size(), 8)
	var repeats := 0
	for i: int in range(1, hit_order.size()):
		repeats += 1 if hit_order[i] == hit_order[i - 1] else 0
	assert_lt(repeats * 4, hit_order.size() * 1, "well under the 1 in 3 of plain random")


# --- determinism, snapshots and the practice odds ---------------------------------------------

func _ruled_attacks() -> Array:
	var heavy := _atk("heavy", 5)
	heavy.cooldown_turns = 1
	var finisher := _atk("finisher", 1)
	finisher.finisher_below_percent = 50
	finisher.finisher_weight_percent = 800
	return [heavy, _atk("light", 3), finisher]


func test_same_seed_same_events_with_target_rules() -> void:
	for rule: int in [EnemyData.TargetRule.WOUNDED, EnemyData.TargetRule.LOWEST_HP, EnemyData.TargetRule.AVOID_LAST]:
		var a := Bot.new(Bot.Defence.MIXED).play(_engine(_ruled_attacks(), rule, 250, {"seed": 11}))
		var b := Bot.new(Bot.Defence.MIXED).play(_engine(_ruled_attacks(), rule, 250, {"seed": 11}))
		assert_true(a.events == b.events, "rule %d" % rule)
		assert_gt((a.events as Array).size(), 20)


func test_a_restored_snapshot_carries_the_ai_memory() -> void:
	var setup := Fx.setup(_ruled_attacks(), {"seed": 4, "hp_percents": [1000, 1000, 1000]})
	setup.enemies[0].target_rule = EnemyData.TargetRule.WOUNDED
	setup.enemies[0].target_bias_percent = 250
	var engine := CombatEngine.new(setup)
	engine.start()
	var bot := Bot.new(Bot.Defence.MIXED)
	for _i: int in 40:
		if engine.phase == CombatEngine.Phase.ENDED:
			break
		engine.submit(bot.next_command(engine))
	var foe := _foe(engine)
	assert_gt(foe.recent_attacks.size(), 0, "the enemy has acted")
	var snap := engine.snapshot()
	var copy := CombatEngine.restore(setup, snap)
	assert_eq(copy.snapshot(), snap)
	assert_eq(_foe(copy).recent_attacks, foe.recent_attacks)
	assert_eq(_foe(copy).attack_cooldowns, foe.attack_cooldowns)
	assert_eq(_foe(copy).last_target, foe.last_target)
	var copy_bot := Bot.new(Bot.Defence.MIXED)
	for _i: int in 60:
		if engine.phase == CombatEngine.Phase.ENDED:
			break
		var out_a := engine.submit(bot.next_command(engine))
		var out_b := copy.submit(copy_bot.next_command(copy))
		assert_true(out_a == out_b, "the restored fight plays on identically")
	assert_eq(engine.snapshot(), copy.snapshot())


func test_combatant_round_trips_the_ai_memory() -> void:
	var c := Combatant.new()
	c.note_attack("x", 3, 2)
	c.note_attack("y", 0, 1)
	var d := Combatant.from_dict(c.to_dict())
	assert_eq(d.recent_attacks, c.recent_attacks)
	assert_eq(d.attack_cooldowns, c.attack_cooldowns)
	assert_eq(d.last_target, 1)


func test_practice_intents_show_the_odds_and_normal_fights_do_not() -> void:
	var practice := _engine([_atk("a", 4), _atk("b", 1)], EnemyData.TargetRule.WOUNDED, 200, {"practice": true, "enemy_speed": 10})
	var normal := _engine([_atk("a", 4), _atk("b", 1)], EnemyData.TargetRule.WOUNDED, 200, {"enemy_speed": 10})
	var event := practice._intent_event(FOE_ID)
	assert_true(event.has("odds"))
	assert_eq((event.odds.attacks as Array).size(), 2)
	assert_eq((event.odds.targets as Array).size(), 3)
	assert_false(normal._intent_event(FOE_ID).has("odds"))


func test_practice_does_not_change_what_happens() -> void:
	var a := Bot.new(Bot.Defence.MIXED).play(_engine(_ruled_attacks(), EnemyData.TargetRule.WOUNDED, 250, {"seed": 9, "practice": true}))
	var b := Bot.new(Bot.Defence.MIXED).play(_engine(_ruled_attacks(), EnemyData.TargetRule.WOUNDED, 250, {"seed": 9}))
	var chosen_a: Array[String] = []
	for e: Dictionary in Fx.of_type(a.events as Array, "intent"):
		chosen_a.append("%s:%s" % [e.attack, str(e.targets)])
	var chosen_b: Array[String] = []
	for e: Dictionary in Fx.of_type(b.events as Array, "intent"):
		chosen_b.append("%s:%s" % [e.attack, str(e.targets)])
	assert_eq(chosen_a, chosen_b)


func test_shipped_enemies_have_a_bias_with_every_rule() -> void:
	var dir := DirAccess.open("res://data/enemies")
	var count := 0
	for file: String in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var data := load("res://data/enemies/" + file) as EnemyData
		count += 1
		if data.target_rule != EnemyData.TargetRule.RANDOM:
			assert_gt(data.target_bias_percent, 0, "%s has a rule but no bias" % data.id)
	assert_gt(count, 15)
