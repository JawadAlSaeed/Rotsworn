extends GutTest
## Charged Dooms (card #195, DESIGN.md 2.3): an announced big move the enemy gathers for a few
## turns, that the party breaks by dealing enough damage. Hand-made fights with exact numbers from
## Tuning.new() (base enemy HP 1500, stagger 1 turn, +50% damage taken), plus the shipped data.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")
const Bot := preload("res://tests/helpers/combat_bot.gd")

const FOE_ID: int = Fx.ENEMY_ID
const ENCOUNTER_DIR := "res://data/encounters"


## A Doom: a party-wide string, `charge` enemy turns, broken by `break_pct` of the enemy's max HP.
func _doom(charge: int = 3, break_pct: int = 10, weight: int = 100, start_cooldown: int = 0) -> EnemyAttackData:
	var d := Fx.attack("doom", [Fx.hit(900), Fx.hit(1500, Fx.GROUND), Fx.hit(2300)], Fx.PARTY, weight)
	d.charge_turns = charge
	d.break_damage_percent = break_pct
	d.cooldown_turns = 3
	d.start_cooldown_turns = start_cooldown
	return d


func _light() -> EnemyAttackData:
	return Fx.attack("light", [Fx.hit(900)], Fx.SINGLE, 1)


## A fight where the heroes get several turns before the enemy's first.
func _engine(attacks: Array, options: Dictionary = {}) -> CombatEngine:
	var opts := {"enemy_speed": 40, "seed": 3}
	opts.merge(options, true)
	var engine := CombatEngine.new(Fx.setup(attacks, opts))
	engine.start()
	return engine


func _foe(engine: CombatEngine) -> Combatant:
	return engine.get_combatant(FOE_ID)


## The party hits the foe directly for `amount` (bypassing turns), returning the events.
func _hit(engine: CombatEngine, amount: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	engine._deal_damage(engine.get_combatant(0), _foe(engine), amount, "ability", events)
	return events


func _types(events: Array) -> Array[String]:
	return Fx.types(events)


# --- data -------------------------------------------------------------------------------------

func test_a_normal_attack_is_not_a_doom() -> void:
	var a := EnemyAttackData.new()
	assert_eq(a.charge_turns, 0)
	assert_eq(a.break_damage_percent, 0)
	assert_false(a.is_doom())
	assert_true(_doom().is_doom())


func test_tuning_defaults_for_the_stagger() -> void:
	var t := Tuning.new()
	assert_eq(t.stagger_turns, 1)
	assert_eq(t.stagger_damage_taken_percent, 50)
	var shipped := Fx.shipped_tuning()
	assert_gt(shipped.stagger_turns, 0)
	assert_gt(shipped.stagger_damage_taken_percent, 0)


func test_setup_rejects_a_doom_that_is_not_a_proper_doom() -> void:
	var single := _doom()
	single.target_mode = EnemyAttackData.TargetMode.SINGLE
	assert_false(Fx.setup([single]).validate().is_empty(), "a Doom is party-wide")
	var no_break := _doom(3, 0)
	assert_false(Fx.setup([no_break]).validate().is_empty(), "a Doom needs a break threshold")
	var no_cooldown := _doom()
	no_cooldown.cooldown_turns = 0
	assert_false(Fx.setup([no_cooldown]).validate().is_empty(), "a Doom needs a cooldown")
	assert_true(Fx.setup([_doom(), _light()]).validate().is_empty())


# --- announcing --------------------------------------------------------------------------------

func test_the_announced_doom_has_a_countdown_and_a_break_threshold() -> void:
	var engine := CombatEngine.new(Fx.setup([_doom(3, 10), _light()], {"enemy_speed": 40, "seed": 3}))
	var events := engine.start()
	var intent := Fx.first_of(events, "intent")
	assert_eq(String(intent.attack), "doom")
	assert_eq(int(intent.charge_left), 3)
	assert_eq(int(intent.charge_total), 3)
	assert_eq(int(intent.charge_damage), 0)
	assert_eq(int(intent.break_hp), CombatMath.percent_min1(_foe(engine).max_hp, 10))
	assert_eq(_foe(engine).charge_left, 3)
	assert_eq(_foe(engine).charge_attack, "doom")


func test_a_normal_intent_has_no_charge_keys() -> void:
	var engine := CombatEngine.new(Fx.setup([_light()], {"enemy_speed": 40}))
	var intent := Fx.first_of(engine.start(), "intent")
	assert_false(intent.has("charge_left"))
	assert_eq(_foe(engine).charge_left, 0)


func test_a_doom_never_opens_the_fight() -> void:
	# The doom is almost sure to be picked, but start_cooldown_turns keeps it from the first intent.
	for seed_value: int in [1, 2, 3, 4, 5, 6]:
		var engine := CombatEngine.new(Fx.setup([_doom(2, 10, 1000, 1), _light()], {"enemy_speed": 40, "seed": seed_value}))
		var intent := Fx.first_of(engine.start(), "intent")
		assert_eq(String(intent.attack), "light", "seed %d" % seed_value)
		assert_eq(_foe(engine).charge_left, 0)


func test_a_doom_comes_up_after_the_start_cooldown() -> void:
	var engine := CombatEngine.new(Fx.setup([_doom(2, 10, 1000, 1), _light()], {"enemy_speed": 200, "seed": 2,
			"enemy_hp_percent": 20000}))
	var run: Dictionary = Bot.new(Bot.Defence.PERFECT).play_steps(engine, 40)
	var intents := Fx.of_type(run.events as Array, "intent")
	assert_eq(String(intents[0].attack), "light")
	var announced := intents.filter(func(e: Dictionary) -> bool: return String(e.attack) == "doom")
	assert_false(announced.is_empty(), "the doom is announced later")


# --- gathering and unleashing ------------------------------------------------------------------

func test_the_enemy_gathers_then_unleashes_when_not_broken() -> void:
	# 20000% HP: the heroes can never reach the break.
	var engine := CombatEngine.new(Fx.setup([_doom(3, 10), _light()], {"enemy_speed": 200, "seed": 3,
			"enemy_hp_percent": 20000}))
	var run: Dictionary = Bot.new(Bot.Defence.PERFECT).play_steps(engine, 60)
	var events: Array = run.events
	var flow: Array[String] = []
	for e: Dictionary in events:
		match String(e.type):
			"doom_charging", "doom_unleashed", "doom_broken":
				flow.append(String(e.type) + (":%d" % int(e.left) if e.has("left") else ""))
			"intent":
				if String(e.attack) == "doom":
					flow.append("intent:%d" % int(e.charge_left))
			"timed_sequence_declared":
				if String(e.kind) == "enemy_attack":
					flow.append("attack:" + String(e.action))
	# Announced for 3 turns: two gathering turns, then the unleash and the string itself.
	assert_eq(flow.slice(0, 5), ["intent:3", "doom_charging:2", "doom_charging:1", "doom_unleashed", "attack:doom"])
	assert_false(flow.has("doom_broken"))


func test_the_doom_string_hits_the_whole_party() -> void:
	var engine := CombatEngine.new(Fx.setup([_doom(2, 10), _light()], {"enemy_speed": 200, "seed": 3,
			"enemy_hp_percent": 20000}))
	var run: Dictionary = Bot.new(Bot.Defence.PERFECT).play_steps(engine, 40)
	var declared := Fx.of_type(run.events as Array, "timed_sequence_declared").filter(
			func(e: Dictionary) -> bool: return String(e.action) == "doom")
	assert_false(declared.is_empty())
	assert_eq((declared[0].targets as Array).size(), 3)
	assert_eq((declared[0].hits as Array).size(), 3)
	assert_eq((declared[0].prompts as Array).size(), 9, "three hits on three heroes")


func test_a_doom_is_followed_by_its_cooldown() -> void:
	var light := _light()
	light.max_in_a_row = 0
	var engine := CombatEngine.new(Fx.setup([_doom(2, 10), light], {"enemy_speed": 200, "seed": 3,
			"enemy_hp_percent": 20000}))
	var run: Dictionary = Bot.new(Bot.Defence.PERFECT).play_steps(engine, 200)
	var used: Array[String] = []
	for e: Dictionary in Fx.of_type(run.events as Array, "timed_sequence_declared"):
		if String(e.kind) == "enemy_attack":
			used.append(String(e.action))
	for i: int in used.size():
		if used[i] == "doom":
			for j: int in range(i + 1, mini(used.size(), i + 4)):
				assert_ne(used[j], "doom", "no doom within the 3 turns after a doom (turn %d)" % i)


func test_delaying_a_gathering_enemy_does_not_reset_the_countdown() -> void:
	var engine := _engine([_doom(3, 10), _light()])
	assert_eq(_foe(engine).charge_left, 3)
	var events: Array[Dictionary] = []
	engine._shift_turn(_foe(engine), 5000, events)
	assert_eq(_foe(engine).charge_left, 3, "the countdown counts the enemy's turns, not time")
	assert_eq(_foe(engine).charge_attack, "doom")
	assert_eq(_foe(engine).charge_damage, 0)
	assert_eq(String((engine.intents[FOE_ID] as Dictionary).attack), "doom")


func test_damage_before_the_first_gather_counts_toward_the_break() -> void:
	var engine := _engine([_doom(3, 10), _light()])
	var break_hp := CombatMath.percent_min1(_foe(engine).max_hp, 10)
	var events := _hit(engine, break_hp - 1)
	assert_eq(_types(events), ["damage", "doom_progress"])
	assert_eq(int(events[1].damage), break_hp - 1)
	assert_eq(_foe(engine).charge_damage, break_hp - 1)


# --- breaking ----------------------------------------------------------------------------------

func test_enough_damage_breaks_the_doom_and_staggers_the_enemy() -> void:
	var engine := _engine([_doom(3, 10), _light()])
	var foe := _foe(engine)
	var break_hp := CombatMath.percent_min1(foe.max_hp, 10)
	_hit(engine, 60)
	var events := _hit(engine, break_hp - 60)
	var types := _types(events)
	assert_eq(types.slice(0, 3), ["damage", "doom_broken", "stagger_changed"])
	var broken := Fx.first_of(events, "doom_broken")
	assert_eq(String(broken.attack), "doom")
	assert_eq(int(broken.damage), break_hp)
	assert_eq(int(broken.break_hp), break_hp)
	assert_eq(int(broken.stagger_turns), 1)
	assert_eq(foe.charge_left, 0)
	assert_eq(foe.charge_attack, "")
	assert_eq(foe.charge_damage, 0)
	assert_eq(foe.staggered_turns, 1)
	var stagger := Fx.first_of(events, "stagger_changed")
	assert_eq(int(stagger.turns), 1)
	assert_false(bool(stagger.lost_turn))
	assert_true(foe.attack_cooldowns.has("doom"), "a broken doom is on cooldown")
	# It announces a fresh move, and it is not the doom.
	var intent := Fx.first_of(events, "intent")
	assert_eq(String(intent.attack), "light")
	assert_false(intent.has("charge_left"))


func test_one_point_short_does_not_break() -> void:
	var engine := _engine([_doom(3, 10), _light()])
	var break_hp := CombatMath.percent_min1(_foe(engine).max_hp, 10)
	_hit(engine, break_hp - 1)
	assert_eq(_foe(engine).charge_left, 3)
	assert_eq(_foe(engine).staggered_turns, 0)
	var events := _hit(engine, 1)
	assert_true(_types(events).has("doom_broken"))


func test_a_staggered_enemy_takes_extra_damage() -> void:
	var engine := _engine([_doom(3, 10), _light()])
	_hit(engine, CombatMath.percent_min1(_foe(engine).max_hp, 10))
	assert_eq(_foe(engine).staggered_turns, 1)
	var events := _hit(engine, 100)
	var damage := Fx.first_of(events, "damage")
	assert_eq(int(damage.amount), 150, "100 + 50 percent")
	assert_true(bool(damage.get("staggered", false)))
	assert_eq(_foe(engine).hp, _foe(engine).max_hp - CombatMath.percent_min1(_foe(engine).max_hp, 10) - 150)


func test_normal_damage_has_no_stagger_flag() -> void:
	var engine := _engine([_doom(3, 50), _light()])
	var damage := Fx.first_of(_hit(engine, 40), "damage")
	assert_eq(int(damage.amount), 40)
	assert_false(damage.has("staggered"))


func test_the_stagger_costs_the_next_turn_and_then_ends() -> void:
	var engine := _engine([_doom(4, 5), _light()], {"enemy_speed": 60, "enemy_hp_percent": 400})
	var bot := Bot.new(Bot.Defence.PERFECT)
	var events := _hit(engine, CombatMath.percent_min1(_foe(engine).max_hp, 5))
	assert_true(_types(events).has("doom_broken"))
	var intent_after_break: Dictionary = (engine.intents[FOE_ID] as Dictionary).duplicate(true)
	var later: Array[Dictionary] = []
	for _i: int in 30:
		later.append_array(engine.submit(bot.next_command(engine)))
		if Fx.first_of(later, "stagger_changed").has("lost_turn"):
			break
	var lost := Fx.first_of(later, "stagger_changed")
	assert_true(bool(lost.lost_turn), "the enemy lost a turn")
	assert_eq(int(lost.turns), 0, "and the stagger is over")
	assert_eq(_foe(engine).staggered_turns, 0)
	# The turn it lost has no attack, and no new intent: what it announced stands.
	var turn_events := later.slice(0, later.find(lost) + 1)
	for e: Dictionary in turn_events:
		if String(e.type) == "timed_sequence_declared":
			assert_ne(int(e.source), FOE_ID, "no attack on the lost turn")
	assert_eq(engine.intents.get(FOE_ID, {}), intent_after_break)


func test_stagger_turns_in_tuning_sets_how_many_turns_are_lost() -> void:
	var tuning := Fx.no_crit_tuning()
	tuning.stagger_turns = 2
	var engine := _engine([_doom(3, 10), _light()], {"tuning": tuning})
	var events := _hit(engine, CombatMath.percent_min1(_foe(engine).max_hp, 10))
	assert_eq(int(Fx.first_of(events, "doom_broken").stagger_turns), 2)
	assert_eq(_foe(engine).staggered_turns, 2)


func test_a_break_ends_the_charge_so_a_later_turn_is_a_normal_one() -> void:
	var engine := CombatEngine.new(Fx.setup([_doom(4, 5), _light()], {"enemy_speed": 100, "seed": 3,
			"enemy_hp_percent": 400}))
	var run: Dictionary = Bot.new(Bot.Defence.PERFECT).play_steps(engine, 12)
	var types := _types(run.events as Array)
	assert_true(types.has("doom_broken"))
	assert_false(types.has("doom_unleashed"), "a broken doom is never unleashed")
	for e: Dictionary in Fx.of_type(run.events as Array, "timed_sequence_declared"):
		if String(e.kind) == "enemy_attack":
			assert_ne(String(e.action), "doom")


func test_a_downed_enemy_drops_its_charge() -> void:
	var engine := _engine([_doom(3, 50), _light()])
	engine._deal_damage(engine.get_combatant(0), _foe(engine), _foe(engine).max_hp, "ability", [])
	assert_eq(_foe(engine).charge_left, 0)
	assert_eq(_foe(engine).staggered_turns, 0)


func test_a_bleed_tick_can_break_the_doom_too() -> void:
	var engine := _engine([_doom(3, 1), _light()])
	var break_hp := CombatMath.percent_min1(_foe(engine).max_hp, 1)
	var events: Array[Dictionary] = []
	engine._deal_damage(engine.get_combatant(0), _foe(engine), break_hp, "bleed", events)
	assert_true(_types(events).has("doom_broken"))


func test_phase_two_during_a_charge_keeps_the_charge() -> void:
	var doom := _doom(3, 90)
	var light := _light()
	var setup := Fx.setup([doom, light], {"enemy_speed": 40, "seed": 3})
	setup.enemies[0].phase_two_hp_percent = 50
	setup.enemies[0].phase_two_attacks.assign([doom, light])
	var engine := CombatEngine.new(setup)
	engine.start()
	var events := _hit(engine, _foe(engine).max_hp * 6 / 10)
	assert_true(_types(events).has("enemy_phase"))
	assert_eq(_foe(engine).charge_left, 3, "the gathering goes on in phase two")
	assert_eq(String((engine.intents[FOE_ID] as Dictionary).attack), "doom")


func test_a_taunt_or_a_fallen_hero_does_not_cancel_the_charge() -> void:
	var engine := _engine([_doom(3, 50), _light()])
	engine._deal_damage(_foe(engine), engine.get_combatant(0), 100000, "ability", [])
	assert_eq(_foe(engine).charge_left, 3)
	var intent: Dictionary = engine.intents[FOE_ID]
	assert_eq((intent.targets as Array).size(), 2, "the doom now aims at the heroes left")


# --- state, snapshots and determinism -----------------------------------------------------------

func test_the_charge_is_part_of_the_snapshot() -> void:
	var engine := _engine([_doom(3, 10), _light()])
	_hit(engine, 30)
	var snap := engine.snapshot()
	var foe: Dictionary = (snap.combatants as Array)[FOE_ID]
	assert_eq(String(foe.charge_attack), "doom")
	assert_eq(int(foe.charge_left), 3)
	assert_eq(int(foe.charge_damage), 30)
	assert_eq(int(foe.staggered_turns), 0)
	var back := Combatant.from_dict(foe)
	assert_eq(back.charge_attack, "doom")
	assert_eq(back.charge_left, 3)
	assert_eq(back.charge_damage, 30)


func test_snapshot_round_trips_a_stagger() -> void:
	var engine := _engine([_doom(3, 10), _light()])
	_hit(engine, CombatMath.percent_min1(_foe(engine).max_hp, 10))
	var back := Combatant.from_dict(_foe(engine).to_dict())
	assert_eq(back.staggered_turns, 1)
	assert_eq(back.charge_left, 0)


func test_restoring_mid_charge_plays_on_identically() -> void:
	for seed_value: int in [3, 7, 11]:
		var options := {"enemy_speed": 70, "seed": seed_value, "enemy_hp_percent": 300}
		var original := CombatEngine.new(Fx.setup([_doom(3, 12), _light()], options))
		var bot := Bot.new(Bot.Defence.PERFECT)
		original.start()
		# Play until the foe is mid-charge with some damage taken, then fork.
		var guard := 0
		while guard < 200 and not (_foe(original).charge_left > 0 and _foe(original).charge_damage > 0
				and original.phase == CombatEngine.Phase.AWAITING_ACTION):
			original.submit(bot.next_command(original))
			guard += 1
		assert_lt(guard, 200, "reached a mid-charge state (seed %d)" % seed_value)
		var copy := CombatEngine.restore(Fx.setup([_doom(3, 12), _light()], options), original.snapshot())
		assert_eq(copy.snapshot(), original.snapshot())
		var bot_a := Bot.new(Bot.Defence.PERFECT)
		var bot_b := Bot.new(Bot.Defence.PERFECT)
		var events_a: Array[Dictionary] = []
		var events_b: Array[Dictionary] = []
		for _i: int in 60:
			if original.phase == CombatEngine.Phase.ENDED:
				break
			events_a.append_array(original.submit(bot_a.next_command(original)))
			events_b.append_array(copy.submit(bot_b.next_command(copy)))
		assert_eq(events_b, events_a, "same events after a restore (seed %d)" % seed_value)
		assert_eq(copy.snapshot(), original.snapshot())


func test_same_seed_same_commands_same_events_with_dooms() -> void:
	for seed_value: int in [1, 5, 9]:
		var options := {"enemy_speed": 100, "seed": seed_value, "enemy_hp_percent": 250}
		var a: Dictionary = Bot.new(Bot.Defence.MIXED).play(CombatEngine.new(Fx.setup([_doom(3, 12), _light()], options)))
		var b: Dictionary = Bot.new(Bot.Defence.MIXED).play(CombatEngine.new(Fx.setup([_doom(3, 12), _light()], options)))
		assert_eq(b.events, a.events, "seed %d" % seed_value)
		assert_true(_types(a.events as Array).has("doom_charging") or _types(a.events as Array).has("doom_broken"))


func test_doom_events_use_only_plain_values() -> void:
	var options := {"enemy_speed": 100, "seed": 4, "enemy_hp_percent": 250}
	var run: Dictionary = Bot.new(Bot.Defence.PERFECT).play(CombatEngine.new(Fx.setup([_doom(3, 12), _light()], options)))
	var seen := 0
	for e: Dictionary in run.events:
		if String(e.type).begins_with("doom_") or String(e.type) == "stagger_changed":
			seen += 1
			assert_eq(Fx.find_illegal_value(e), "", String(e.type))
	assert_gt(seen, 0)


func test_the_mirror_follows_the_charge_and_matches_the_engine() -> void:
	var seen: Dictionary = {}
	for seed_value: int in [1, 2, 3, 4]:
		for defence: int in [Bot.Defence.PERFECT, Bot.Defence.MISS, Bot.Defence.MIXED]:
			var options := {"enemy_speed": 90, "seed": seed_value, "enemy_hp_percent": 250}
			var engine := CombatEngine.new(Fx.setup([_doom(3, 12), _light()], options))
			var mirror := CombatMirror.new()
			var bot := Bot.new(defence as Bot.Defence)
			for e: Dictionary in engine.start():
				mirror.apply(e)
			for _i: int in Bot.MAX_STEPS:
				if engine.phase == CombatEngine.Phase.ENDED:
					break
				for e: Dictionary in engine.submit(bot.next_command(engine)):
					if String(e.type) != "command_rejected":
						seen[String(e.type)] = true
						mirror.apply(e)
				if engine.phase == CombatEngine.Phase.AWAITING_ACTION:
					assert_eq(mirror.projection(), CombatMirror.project_snapshot(engine.snapshot()),
							"seed %d defence %d turn %d" % [seed_value, defence, engine.turn_number])
			assert_eq(mirror.projection(), CombatMirror.project_snapshot(engine.snapshot()))
	for type: String in ["doom_charging", "doom_unleashed", "doom_broken", "doom_progress", "stagger_changed"]:
		assert_true(seen.has(type), "the corpus covered " + type)


func _mirrored() -> Array:
	var engine := CombatEngine.new(Fx.setup([_doom(3, 10), _light()], {"enemy_speed": 40, "seed": 3}))
	var mirror := CombatMirror.new()
	for e: Dictionary in engine.start():
		mirror.apply(e)
	return [engine, mirror]


func test_mirror_helpers_report_charging_and_staggered() -> void:
	var first := _mirrored()
	var engine: CombatEngine = first[0]
	var mirror: CombatMirror = first[1]
	assert_true(mirror.is_charging(FOE_ID))
	assert_eq(int(mirror.fighter(FOE_ID).charge_left), 3)
	assert_eq(int(mirror.fighter(FOE_ID).break_hp), CombatMath.percent_min1(_foe(engine).max_hp, 10))
	for e: Dictionary in _hit(engine, _foe(engine).max_hp):
		mirror.apply(e)
	assert_false(mirror.is_charging(FOE_ID))
	var second := _mirrored()
	var other: CombatEngine = second[0]
	var m2: CombatMirror = second[1]
	for e: Dictionary in _hit(other, CombatMath.percent_min1(_foe(other).max_hp, 10)):
		m2.apply(e)
	assert_true(m2.is_staggered(FOE_ID))
	assert_false(m2.is_charging(FOE_ID))


# --- bots ---------------------------------------------------------------------------------------

func test_the_bot_focuses_the_gathering_enemy() -> void:
	var setup := Fx.setup([_doom(3, 10), _light()], {"enemy_speed": 40, "seed": 3})
	setup.enemies.append(Fx.enemy("calm", [_light()], 40))
	var engine := CombatEngine.new(setup)
	engine.start()
	# The first enemy (id 3) gathers, the second (id 4) does not: both stand, the bot aims at id 3.
	var enemy_a := engine.get_combatant(3)
	var enemy_b := engine.get_combatant(4)
	enemy_a.charge_left = 0
	enemy_b.charge_left = 2
	var bot := Bot.new()
	var command := bot.next_command(engine)
	assert_eq(int((command.targets as Array)[0]), 4, "aims at the one gathering")
	enemy_b.charge_left = 0
	command = bot.next_command(engine)
	assert_eq(int((command.targets as Array)[0]), 3, "else the first")


# --- the shipped guards and bosses ---------------------------------------------------------------

## Every attack of an enemy, both phases, each once.
func _all_attacks(enemy: EnemyData) -> Array[EnemyAttackData]:
	var list: Array[EnemyAttackData] = []
	for a: EnemyAttackData in enemy.attacks + enemy.phase_two_attacks:
		if not list.has(a):
			list.append(a)
	return list


func _dooms_of(enemy: EnemyData) -> Array[EnemyAttackData]:
	var list: Array[EnemyAttackData] = []
	for a: EnemyAttackData in _all_attacks(enemy):
		if a.is_doom():
			list.append(a)
	return list


## The big enemies of the shipped guard and boss fights (the one with the most HP in each).
func _bosses() -> Array[EnemyData]:
	var list: Array[EnemyData] = []
	for file: String in DirAccess.get_files_at(ENCOUNTER_DIR):
		if not file.ends_with(".tres"):
			continue
		var encounter := load(ENCOUNTER_DIR + "/" + file) as EncounterData
		if encounter == null or not (encounter.boss or encounter.mini_boss):
			continue
		var best: EnemyData = null
		for e: EnemyData in encounter.enemies:
			if best == null or e.hp_percent > best.hp_percent:
				best = e
		if best != null and not list.has(best):
			list.append(best)
	return list


func test_each_guard_and_boss_has_exactly_one_doom() -> void:
	var bosses := _bosses()
	assert_gte(bosses.size(), 5, "three zone guards and two act bosses")
	var names: Array[String] = []
	for boss: EnemyData in bosses:
		names.append(boss.id)
		assert_eq(_dooms_of(boss).size(), 1, "%s has exactly one Doom" % boss.id)
		# The Doom is on its list in both phases.
		var doom := _dooms_of(boss)[0]
		assert_true(boss.attacks.has(doom), "%s: the Doom is a phase one move" % boss.id)
		assert_true(boss.phase_two_attacks.has(doom), "%s: and a phase two move" % boss.id)
	for id: String in ["husk_lord", "hollow_king", "gorged_one", "mire_mother", "ash_warden"]:
		assert_true(names.has(id), id + " is a guard or boss fight")


func test_every_shipped_doom_is_well_formed() -> void:
	for boss: EnemyData in _bosses():
		for doom: EnemyAttackData in _dooms_of(boss):
			assert_eq(doom.target_mode, EnemyAttackData.TargetMode.PARTY, boss.id)
			assert_gte(doom.charge_turns, 2, boss.id)
			assert_gt(doom.break_damage_percent, 0, boss.id)
			assert_gte(doom.cooldown_turns, 1, boss.id)
			assert_gte(doom.start_cooldown_turns, 1, boss.id + ": never opens the fight")
			assert_gte(doom.hits.size(), 5, boss.id + ": a big string")
			var forced := 0
			for h: AttackHitData in doom.hits:
				if AttackHitData.is_forced(h.forced_kind):
					forced += 1
			assert_gte(forced, 1, boss.id + ": some rend or sweep in a hard fight")


func test_no_normal_enemy_has_a_doom() -> void:
	var bosses := _bosses()
	for file: String in DirAccess.get_files_at("res://data/enemies"):
		if not file.ends_with(".tres"):
			continue
		var enemy := load("res://data/enemies/" + file) as EnemyData
		if enemy != null and not bosses.has(enemy):
			assert_eq(_dooms_of(enemy).size(), 0, enemy.id)


func test_shipped_boss_fights_still_validate() -> void:
	var tuning := Fx.shipped_tuning()
	for file: String in DirAccess.get_files_at(ENCOUNTER_DIR):
		if not file.ends_with(".tres"):
			continue
		var encounter := load(ENCOUNTER_DIR + "/" + file) as EncounterData
		if encounter != null and (encounter.boss or encounter.mini_boss):
			var setup := CombatSetup.from_encounter(encounter, tuning, 1)
			assert_eq(setup.validate(), PackedStringArray(), file)


# --- events and the turn-order tags ---------------------------------------------------------------

const DOOM_EVENT_KEYS: Dictionary = {
	"doom_charging": ["enemy", "attack", "name", "left", "total", "damage", "break_hp"],
	"doom_progress": ["enemy", "attack", "damage", "break_hp"],
	"doom_broken": ["enemy", "attack", "name", "damage", "break_hp", "stagger_turns"],
	"doom_unleashed": ["enemy", "attack", "name"],
	"stagger_changed": ["enemy", "turns", "lost_turn"],
}


func _sorted(keys: Array) -> Array:
	var list := keys.duplicate()
	list.sort()
	return list


func test_doom_events_carry_exactly_their_documented_fields() -> void:
	var seen: Dictionary = {}
	var runs: Array[Dictionary] = []
	for seed_value: int in [1, 2, 3, 4]:
		var options := {"enemy_speed": 90, "seed": seed_value, "enemy_hp_percent": 250}
		runs.append(Bot.new(Bot.Defence.MIXED).play(CombatEngine.new(Fx.setup([_doom(3, 12), _light()], options))))
	# A foe too big to break gathers and unleashes.
	var big := {"enemy_speed": 200, "seed": 3, "enemy_hp_percent": 20000}
	runs.append(Bot.new(Bot.Defence.PERFECT).play_steps(CombatEngine.new(Fx.setup([_doom(3, 12), _light()], big)), 40))
	for run: Dictionary in runs:
		for e: Dictionary in run.events:
			var type := String(e.type)
			if DOOM_EVENT_KEYS.has(type):
				seen[type] = true
				var keys: Array = e.keys()
				keys.erase("type")
				assert_eq(_sorted(keys), _sorted(DOOM_EVENT_KEYS[type]), type)
			elif type == "intent" and e.has("charge_total"):
				seen["intent"] = true
				for key: String in ["charge_left", "charge_total", "charge_damage", "break_hp"]:
					assert_true(e.has(key), "intent." + key)
	for type: String in DOOM_EVENT_KEYS:
		assert_true(seen.has(type), "the corpus produced " + type)


func test_the_gathering_enemy_does_not_re_roll_its_intent() -> void:
	var engine := CombatEngine.new(Fx.setup([_doom(4, 12), _light()], {"enemy_speed": 200, "seed": 3,
			"enemy_hp_percent": 20000}))
	var run: Dictionary = Bot.new(Bot.Defence.PERFECT).play_steps(engine, 12)
	var events: Array = run.events
	# From the announcement to the unleash there is no other intent for the foe (no re-roll).
	var announced := Fx.index_of(events, "intent")
	var unleashed := Fx.index_of(events, "doom_unleashed")
	assert_gt(unleashed, announced)
	for i: int in range(announced + 1, unleashed):
		if String((events[i] as Dictionary).type) == "intent":
			assert_ne(int((events[i] as Dictionary).enemy), FOE_ID, "no new intent while it gathers")


func _tag_mirror(charge_left: int, staggered: int, active: int) -> CombatMirror:
	var mirror := CombatMirror.new()
	mirror.party_ids = [0, 1, 2]
	mirror.enemy_ids = [3]
	mirror.active_actor = active
	for id: int in [0, 1, 2, 3]:
		mirror.fighters[id] = {"id": id, "alive": true, "charge_left": charge_left if id == 3 else 0,
				"staggered": staggered if id == 3 else 0}
	return mirror


func test_the_timeline_counts_down_to_the_doom() -> void:
	var mirror := _tag_mirror(3, 0, 0)
	var order: Array[int] = [0, 3, 1, 3, 2, 3]
	assert_eq(TimelineRow.doom_tag(order, 0, mirror), "", "a hero's turn")
	assert_eq(TimelineRow.doom_tag(order, 1, mirror), "3")
	assert_eq(TimelineRow.doom_tag(order, 3, mirror), "2")
	assert_eq(TimelineRow.doom_tag(order, 5, mirror), "DOOM")
	assert_eq(TimelineRow.doom_tag(order, 4, mirror), "")


func test_the_turn_in_progress_is_not_tagged() -> void:
	# The foe is acting (it just spent its turn gathering, 2 left): its next turn counts as the first.
	var mirror := _tag_mirror(2, 0, 3)
	var order: Array[int] = [3, 0, 3, 1, 3]
	assert_eq(TimelineRow.doom_tag(order, 0, mirror), "")
	assert_eq(TimelineRow.doom_tag(order, 2, mirror), "2")
	assert_eq(TimelineRow.doom_tag(order, 4, mirror), "DOOM")


func test_a_staggered_enemys_next_turn_is_tagged() -> void:
	var mirror := _tag_mirror(0, 1, 0)
	var order: Array[int] = [0, 3, 1, 3]
	assert_eq(TimelineRow.doom_tag(order, 1, mirror), "STAGGER")
	assert_eq(TimelineRow.doom_tag(order, 3, mirror), "", "only the turn it loses")
	var calm := _tag_mirror(0, 0, 0)
	assert_eq(TimelineRow.doom_tag(order, 1, calm), "")
