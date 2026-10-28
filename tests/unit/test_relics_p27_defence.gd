extends GutTest
## Phase 27's defence-side Relics in the fight engine (DESIGN.md 8.25): the ones that answer a
## parry, a dodge, a jump, a counter or a hit taken, and the ones that change the timing windows.
## Each Relic is tested as shipped (its file's numbers) and as Relic+. The other Relics' engine side
## is in their own stage's tests.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")

const RUN_PATH := "res://data/runs/rotten_road.tres"
const NONE: int = Defense.Outcome.NONE
const DODGE: int = Defense.Outcome.DODGE
const PARRY: int = Defense.Outcome.PARRY
const JUMP: int = Defense.Outcome.JUMP
const FOE: int = Fx.ENEMY_ID

var _data: RunData


func before_all() -> void:
	_data = load(RUN_PATH) as RunData


func _relic(id: String) -> GearData:
	for item: GearData in _data.gear:
		if item.id == id:
			return item
	fail_test("the shipped run has the Relic %s" % id)
	return GearData.new()


## The fight passives the shipped Relic `id` gives its hero (as Relic+ when `plus`), as RunState
## builds them: every effect's contribution, drawbacks as losses.
func _passives(id: String, plus: bool = false) -> Dictionary:
	var item := _relic(id)
	var out := {}
	for effect: Variant in GearData.PASSIVE_KEYS:
		var amount := item.contribution(int(effect) as GearData.Effect, plus)
		if amount != 0:
			var key := String(GearData.PASSIVE_KEYS[effect])
			out[key] = int(out.get(key, 0)) + amount
	return out


## A fixture fight where every hero has `passives`, against one tough foe whose only attack is
## `hits` (single target unless options.mode). It acts first, so the attack is declared at once.
## options as Fx.setup, plus kits (Fx.kit_setup), mode and start_hp (Array[int]).
func _engine(passives: Dictionary, hits: Array, options: Dictionary = {}) -> CombatEngine:
	var opts := options.duplicate()
	if not opts.has("enemy_hp_percent"):
		opts["enemy_hp_percent"] = 1000
	var setup := Fx.kit_setup(opts.get("kits", []) as Array,
			[Fx.attack("strike", hits, int(opts.get("mode", Fx.SINGLE)))], opts)
	for i: int in 3:
		setup.party_passives.append(passives.duplicate())
	if opts.has("start_hp"):
		setup.party_start_hp.assign(opts.start_hp as Array)
	var engine := CombatEngine.new(setup)
	engine.start()
	return engine


## The hero the declared single-target attack aims at.
func _target(engine: CombatEngine) -> Combatant:
	return engine.get_combatant(int((engine.sequence.prompts[0] as Dictionary).character))


## Resolves the current attack's prompts in order with `outcomes` (one per prompt).
func _answer(engine: CombatEngine, outcomes: Array) -> Array[Dictionary]:
	var pairs: Array = []
	for i: int in outcomes.size():
		pairs.append([i, int(outcomes[i])])
	return engine.submit(Fx.resolve_now(engine, pairs))


## Plays enemy attacks until a hero's turn waits: every hit dodged (no counter, so no counter Relic
## fires; the tests' attacks have normal hits only).
func _to_party_turn(engine: CombatEngine) -> void:
	for _i: int in 30:
		if engine.phase == CombatEngine.Phase.AWAITING_ACTION:
			return
		var pairs: Array = []
		for idx: int in engine.pending_prompts():
			pairs.append([idx, DODGE])
		engine.submit(Fx.resolve_now(engine, pairs))
	fail_test("a hero's turn came")


func _of(events: Array, type: String, key: String, value: int) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for e: Dictionary in Fx.of_type(events, type):
		if int(e.get(key, -1)) == value:
			list.append(e)
	return list


func _status_on(events: Array, target: int, status: String) -> Dictionary:
	for e: Dictionary in _of(events, "status_changed", "target", target):
		if String(e.status) == status and bool(e.active):
			return e
	return {}


func _raw_hit(engine: CombatEngine, pct: int = 100) -> int:
	return CombatMath.percent_min1(engine.get_combatant(FOE).power, pct)


# --- parry, dodge and jump --------------------------------------------------------------------

func test_ash_veil_dodges_counter_normal_hits_parries_give_no_ap_and_plus_pays_dodges() -> void:
	var engine := _engine(_passives("ash_veil"), [Fx.hit(900)])
	assert_true((engine.sequence.prompts[0].perfect as Array).has(DODGE), "a dodge of a normal hit counts")
	var events := _answer(engine, [DODGE])
	assert_eq(Fx.of_type(events, "counter").size(), 1, "the dodge counters")
	assert_eq(int(Fx.first_of(events, "prompt_resolved").ap_delta), 0, "a dodge gives no AP without the +")
	assert_eq(engine.defence_streak, 0, "the dodge only counts toward the counter, not the streak")
	var parry := _engine(_passives("ash_veil"), [Fx.hit(900)])
	assert_eq(int(Fx.first_of(_answer(parry, [PARRY]), "prompt_resolved").ap_delta), 0, "parries give no AP")
	var sweep := _engine(_passives("ash_veil"), [Fx.hit(900, AttackHitData.Kind.SWEEP)])
	assert_false((sweep.sequence.prompts[0].perfect as Array).has(DODGE), "sweeps stay uncounterable (#187)")
	assert_eq(Fx.of_type(_answer(sweep, [DODGE]), "counter").size(), 0)
	var plus := _engine(_passives("ash_veil", true), [Fx.hit(900)])
	assert_eq(int(Fx.first_of(_answer(plus, [DODGE]), "prompt_resolved").ap_delta), 1, "Ash Veil+: dodges +1 AP")


func test_bramble_coat_hurts_the_attacker_on_a_parry() -> void:
	for plus: bool in [false, true]:
		var engine := _engine(_passives("bramble_coat", plus), [Fx.hit(900)])
		var damage := int(engine.sequence.prompts[0].damage)
		var events := _answer(engine, [PARRY])
		var thorns := _of(events, "damage", "target", FOE).filter(
				func(e: Dictionary) -> bool: return String(e.cause) == "thorns")
		assert_eq(thorns.size(), 1)
		assert_eq(int(thorns[0].amount), CombatMath.percent_min1(damage, 50 if plus else 30))
		var dodged := _engine(_passives("bramble_coat", plus), [Fx.hit(900)])
		assert_eq(Fx.of_type(_answer(dodged, [DODGE]), "damage").size(), 0, "a dodge sends nothing back")


func test_shriving_bell_lifts_marks_on_a_parry() -> void:
	for plus: bool in [false, true]:
		var engine := _engine(_passives("cleansing_bell", plus), [Fx.hit(900)])
		var hero := _target(engine)
		hero.statuses[Status.WEAKENED] = {"turns": 3, "source": FOE}
		hero.statuses[Status.BLIGHTED] = {"turns": 3, "source": FOE}
		hero.statuses[Status.ROTTING] = {"turns": 3, "source": FOE}
		_answer(engine, [PARRY])
		var left := 0
		for id: String in [Status.WEAKENED, Status.BLIGHTED, Status.ROTTING]:
			left += 1 if hero.has_status(id) else 0
		assert_eq(left, 1 if plus else 2, "Shriving Bell%s lifts %d" % ["+" if plus else "", 2 if plus else 1])


func test_fox_step_pays_dodges_within_the_relic_ap_cap() -> void:
	var engine := _engine(_passives("fox_step"), [Fx.hit(900)])
	assert_eq(int(Fx.first_of(_answer(engine, [DODGE]), "prompt_resolved").ap_delta), 1)
	var plus := _engine(_passives("fox_step", true), [Fx.hit(600), Fx.hit(900), Fx.hit(1200)])
	var deltas: Array = Fx.of_type(_answer(plus, [DODGE, DODGE, DODGE]), "prompt_resolved").map(
			func(e: Dictionary) -> int: return int(e.ap_delta))
	assert_eq(deltas, [2, 1, 0], "Fox Step+ gives 2 a dodge, at most relic_ap_per_attack_max (3) an attack")


func test_crow_feather_pays_jumps() -> void:
	for plus: bool in [false, true]:
		var engine := _engine(_passives("crow_feather", plus), [Fx.hit(900, Fx.GROUND)])
		var resolved := Fx.first_of(_answer(engine, [JUMP]), "prompt_resolved")
		assert_eq(int(resolved.ap_delta), engine.tuning.ap_per_jump + (2 if plus else 1))


func test_leaping_heart_heals_on_a_jump() -> void:
	for plus: bool in [false, true]:
		var engine := _engine(_passives("leaping_heart", plus), [Fx.hit(900, Fx.GROUND)], {"start_hp": [10, 10, 10]})
		var hero := _target(engine)
		var healed := _of(_answer(engine, [JUMP]), "healed", "target", hero.id)
		assert_eq(healed.size(), 1)
		assert_eq(int(healed[0].amount), CombatMath.percent_min1(hero.max_hp, 8 if plus else 5))


func test_still_water_heals_on_a_parry() -> void:
	for plus: bool in [false, true]:
		var engine := _engine(_passives("still_water", plus), [Fx.hit(900)], {"start_hp": [10, 10, 10]})
		var hero := _target(engine)
		var healed := _of(_answer(engine, [PARRY]), "healed", "target", hero.id)
		assert_eq(int(healed[0].amount), CombatMath.percent_min1(hero.max_hp, 7 if plus else 4))


func test_wake_root_pays_parries_and_plus_pays_counters() -> void:
	var engine := _engine(_passives("wake_root"), [Fx.hit(900)])
	var events := _answer(engine, [PARRY])
	assert_eq(int(Fx.first_of(events, "prompt_resolved").ap_delta), engine.tuning.ap_per_parry + 1)
	var hero := int(Fx.first_of(events, "prompt_resolved").character)
	assert_eq(_of(events, "ap_changed", "character", hero).size(), 0, "no counter AP without the +")
	var plus := _engine(_passives("wake_root", true), [Fx.hit(900)])
	var plus_hero := _target(plus).id
	var gear := _of(_answer(plus, [PARRY]), "ap_changed", "character", plus_hero)
	assert_eq(gear.size(), 1, "Wake Root+: the counter gives AP")
	assert_eq(int(gear[0].delta), 1)


func test_plague_lancet_bleeds_the_attacker_on_a_parry_and_plus_on_a_dodge() -> void:
	var engine := _engine(_passives("plague_bell"), [Fx.hit(900)])
	var hero := _target(engine)
	var bleed := _status_on(_answer(engine, [PARRY]), FOE, Status.BLEEDING)
	assert_eq(int(bleed.get("turns", 0)), 2)
	assert_eq(int(bleed.get("source", -1)), hero.id, "the hero's power drives the bleed")
	var dodged := _engine(_passives("plague_bell"), [Fx.hit(900)])
	assert_true(_status_on(_answer(dodged, [DODGE]), FOE, Status.BLEEDING).is_empty())
	var plus := _engine(_passives("plague_bell", true), [Fx.hit(900)])
	assert_false(_status_on(_answer(plus, [DODGE]), FOE, Status.BLEEDING).is_empty(), "Plague Lancet+: dodges too")


## Counts the foe's bleed ticks in `events`, then plays on until its Bleed is gone: hero turns pass
## (the tutorial's hold, set before the attack was answered) and the foe's hits land (a defence could
## give a new Bleed).
func _bleed_ticks(engine: CombatEngine, events: Array[Dictionary]) -> int:
	var ticks := 0
	for _i: int in 40:
		for e: Dictionary in _of(events, "damage", "target", FOE):
			if String(e.cause) == "bleed":
				ticks += 1
		if not engine.get_combatant(FOE).has_status(Status.BLEEDING):
			return ticks
		if engine.phase != CombatEngine.Phase.AWAITING_TIMING:
			break
		var pairs: Array = []
		for idx: int in engine.pending_prompts():
			pairs.append([idx, NONE])
		events = engine.submit(Fx.resolve_now(engine, pairs))
	fail_test("the Bleed ran out")
	return ticks


## A Bleed given during the foe's own turn (a parry, a dodge or a counter) ticks as many times as
## its turns say: that turn's end does not count it down.
func test_a_bleed_given_in_the_foes_turn_ticks_every_turn() -> void:
	for plus: bool in [false, true]:
		var engine := _engine(_passives("plague_bell", plus), [Fx.hit(900)])
		engine.stage.hold_party = true
		var outcome := DODGE if plus else PARRY
		var events := _answer(engine, [outcome])
		var turns := int(_status_on(events, FOE, Status.BLEEDING).turns)
		assert_eq(turns, 2)
		assert_eq(_bleed_ticks(engine, events), turns, "Plague Lancet: two ticks")
	var tag := _engine(_passives("grave_tag", true), [Fx.hit(900)])
	tag.stage.hold_party = true
	var tagged := _answer(tag, [PARRY])
	assert_eq(int(_status_on(tagged, FOE, Status.BLEEDING).turns), 3, "Grave Tag+ on a counter")
	assert_eq(_bleed_ticks(tag, tagged), 3)
	for plus: bool in [false, true]:
		var passives := _passives("ember_stone", plus)
		passives.merge(_passives("headsmans_hood"))
		var ember := _engine(passives, [Fx.hit(900)])
		ember.stage.hold_party = true
		var crit := _answer(ember, [PARRY])
		var turns := int(_status_on(crit, FOE, Status.BLEEDING).turns)
		assert_eq(turns, 4 if plus else 2, "Ember Stone on a counter crit")
		assert_eq(_bleed_ticks(ember, crit), turns)
	var c := Combatant.new()
	c.fresh_bleed = true
	assert_true(Combatant.from_dict(c.to_dict()).fresh_bleed, "kept in to_dict")


func test_quick_boots_brings_the_next_turn_sooner_once_per_attack() -> void:
	for plus: bool in [false, true]:
		var engine := _engine(_passives("quick_boots", plus), [Fx.hit(600), Fx.hit(900)])
		var hero := _target(engine)
		var wait := hero.next_turn_at - engine.time_now
		var events := _answer(engine, [DODGE, DODGE])
		var shifted := _of(events, "turn_shifted", "target", hero.id)
		assert_eq(shifted.size(), 1, "once per enemy attack")
		var cost := Timeline.turn_cost(hero.speed, engine.tuning.timeline_base)
		assert_eq(int(shifted[0].delta), -mini(CombatMath.percent(cost, 50 if plus else 25), wait))
		var parried := _engine(_passives("quick_boots", plus), [Fx.hit(900)])
		assert_eq(Fx.of_type(_answer(parried, [PARRY]), "turn_shifted").size(), 0, "only a dodge")


func test_moth_wing_readies_a_crit_after_a_whole_attack_dodged_and_plus_jumped() -> void:
	var engine := _engine(_passives("moth_wing"), [Fx.hit(600), Fx.hit(900)])
	var hero := _target(engine)
	_answer(engine, [DODGE, DODGE])
	assert_true(hero.crit_ready, "every hit dodged")
	var partly := _engine(_passives("moth_wing"), [Fx.hit(600), Fx.hit(900)])
	var partly_hero := _target(partly)
	_answer(partly, [DODGE, PARRY])
	assert_false(partly_hero.crit_ready, "a parry in the string: not a whole attack dodged")
	var jumped := _engine(_passives("moth_wing"), [Fx.hit(600, Fx.GROUND), Fx.hit(900, Fx.GROUND)])
	var jumper := _target(jumped)
	_answer(jumped, [JUMP, JUMP])
	assert_false(jumper.crit_ready, "jumps only with the +")
	var plus := _engine(_passives("moth_wing", true), [Fx.hit(600, Fx.GROUND), Fx.hit(900)])
	var plus_hero := _target(plus)
	_answer(plus, [JUMP, DODGE])
	assert_true(plus_hero.crit_ready, "Moth Wing+: jumped and dodged")


func test_moth_wings_ready_crit_makes_the_next_skill_crit_once() -> void:
	var strike := Fx.skill("strike", AbilityData.Target.SINGLE_ENEMY, 0, [300], {"damage_percent": 100})
	var engine := _engine(_passives("moth_wing"), [Fx.hit(900)], {"kits": [[strike], [strike], [strike]]})
	_to_party_turn(engine)
	var hero := engine.get_combatant(engine.active_actor)
	hero.crit_ready = true
	var restored := CombatEngine.restore(engine._setup, engine.snapshot())
	assert_true(restored.get_combatant(hero.id).crit_ready, "the ready crit is in the snapshot")
	var declared := Fx.first_of(engine.submit(Fx.use(engine, "strike")), "timed_sequence_declared")
	assert_true(bool((declared.prompts[0] as Dictionary).crit), "crits with the crit chance at 0")
	assert_false(hero.crit_ready, "used up")


func test_sextons_hourglass_widens_defend_windows_within_the_bound() -> void:
	var plain := _engine({}, [Fx.hit(900)])
	var normal := Defense.build_windows(Fx.NORMAL, plain.tuning)
	var press := Defense.build_windows(AttackHitData.Kind.PRESS, plain.tuning)
	for plus: bool in [false, true]:
		var engine := _engine(_passives("sextons_hourglass", plus), [Fx.hit(900)])
		var wider := 35 if plus else 20
		var parry: Array = engine.sequence.prompts[0].windows[PARRY]
		assert_eq(parry, [CombatMath.percent(int(normal[PARRY][0]), 100 + wider),
				CombatMath.percent(int(normal[PARRY][1]), 100 + wider)], "the declared parry window is wider")
		var dodge: Array = engine.sequence.prompts[0].windows[DODGE]
		assert_eq(int(dodge[1]), CombatMath.percent(int(normal[DODGE][1]), 100 + wider))
		assert_eq_deep(engine._windows_for(_target(engine), press), press)
	var hero := _target(plain)
	hero.passives[Passive.DEFEND_WINDOW] = 500
	var capped: Array = plain._windows_for(hero, normal)[PARRY]
	assert_eq(int(capped[1]), CombatMath.percent(int(normal[PARRY][1]), 100 + plain.tuning.relic_defend_window_max_percent))


func test_keen_eye_grows_the_perfect_press_window_partway_toward_the_good_one() -> void:
	var plain := _engine({}, [Fx.hit(900)])
	var press := Defense.build_windows(AttackHitData.Kind.PRESS, plain.tuning)
	var good: Array = press[Defense.Outcome.PRESS]
	var best: Array = press[Defense.Outcome.PRESS_PERFECT]
	for plus: bool in [false, true]:
		var engine := _engine(_passives("keen_eye", plus), [Fx.hit(900)])
		var keen := 70 if plus else 40
		var windows := engine._windows_for(_target(engine), press)
		assert_eq(windows[Defense.Outcome.PRESS], good, "the good window stays")
		assert_eq(windows[Defense.Outcome.PRESS_PERFECT], [int(best[0]) + CombatMath.percent(int(good[0]) - int(best[0]), keen),
				int(best[1]) + CombatMath.percent(int(good[1]) - int(best[1]), keen)])
		assert_eq_deep(engine.sequence.prompts[0].windows as Dictionary, Defense.build_windows(Fx.NORMAL, engine.tuning))
	var hero := _target(plain)
	hero.passives[Passive.PERFECT_WINDOW] = 100
	var capped: Array = plain._windows_for(hero, press)[Defense.Outcome.PRESS_PERFECT]
	assert_true(int(capped[1]) < int(good[1]), "never as wide as the good window (Pale Tithe keeps its price)")


# --- hits taken -------------------------------------------------------------------------------

func test_thick_hide_cuts_the_first_hit_of_each_attack() -> void:
	for plus: bool in [false, true]:
		var engine := _engine(_passives("thick_hide", plus), [Fx.hit(600), Fx.hit(900)])
		var raw := _raw_hit(engine)
		assert_eq(int(engine.sequence.prompts[0].damage), CombatMath.percent_min1(raw, 40 if plus else 60))
		assert_eq(int(engine.sequence.prompts[1].damage), raw, "only the first hit")


func test_hollow_mantle_pays_one_ap_to_cut_a_hit() -> void:
	for plus: bool in [false, true]:
		var engine := _engine(_passives("hollow_mantle", plus), [Fx.hit(600), Fx.hit(900)])
		var hero := _target(engine)
		var raw := _raw_hit(engine)
		assert_eq(hero.ap, 1)
		var cut := CombatMath.percent_min1(raw, 40 if plus else 50)
		assert_eq(int(engine.sequence.prompts[0].guard_damage), cut)
		var resolved := Fx.of_type(_answer(engine, [NONE, NONE]), "prompt_resolved")
		assert_eq(int(resolved[0].damage), cut)
		assert_eq(int(resolved[0].ap_delta), -1, "1 AP paid")
		assert_eq(int(resolved[1].damage), raw, "no AP left: the full hit")
	var capped := _engine(_passives("hollow_mantle", true), [Fx.hit(900)])
	var hero := _target(capped)
	hero.statuses[Status.GUARDED] = {"turns": 1, "source": hero.id}
	var raw := _raw_hit(capped)
	assert_eq(capped._hit_amount(capped.get_combatant(FOE), hero, 100, 60),
			CombatMath.percent_min1(raw, 100 - capped.tuning.relic_damage_cut_max_percent),
			"Guarded and the mantle never cut more than 75% together")


func test_widows_thimble_makes_the_first_hits_of_a_fight_do_nothing() -> void:
	for plus: bool in [false, true]:
		var engine := _engine(_passives("widows_thimble", plus), [Fx.hit(500), Fx.hit(800), Fx.hit(1100)])
		var hero := _target(engine)
		var hp := hero.hp
		assert_eq(int(engine.sequence.prompts[0].null_left), 2 if plus else 1, "a hint for the hit's popup")
		var resolved := Fx.of_type(_answer(engine, [NONE, NONE, NONE]), "prompt_resolved")
		var nulled := 2 if plus else 1
		for i: int in 3:
			assert_eq(bool(resolved[i].get("nulled", false)), i < nulled, "hit %d" % i)
			assert_eq(int(resolved[i].damage) == 0, i < nulled)
		assert_eq(hp - hero.hp, int(resolved[nulled].damage) * (3 - nulled))
		assert_eq(hero.null_hits_used, nulled)
		assert_true(hero.was_hit, "the hits after it land")
	var once := _engine(_passives("widows_thimble"), [Fx.hit(900)])
	var hero := _target(once)
	_answer(once, [NONE])
	assert_false(hero.was_hit, "a hit that does nothing is not a hit (Brimming Cup stays full)")
	var restored := CombatEngine.restore(once._setup, once.snapshot())
	assert_eq(restored.get_combatant(hero.id).null_hits_used, 1, "used up for the fight, also after a restore")


func test_thorned_gauntlet_pays_the_first_hit_of_an_attack_and_plus_heals() -> void:
	for plus: bool in [false, true]:
		var engine := _engine(_passives("thorned_gauntlet", plus), [Fx.hit(600), Fx.hit(900)])
		var hero := _target(engine)
		var events := _answer(engine, [NONE, NONE])
		var deltas: Array = Fx.of_type(events, "prompt_resolved").map(func(e: Dictionary) -> int: return int(e.ap_delta))
		assert_eq(deltas, [1, 0], "+1 AP once per attack")
		var healed := _of(events, "healed", "target", hero.id)
		assert_eq(healed.size(), 1 if plus else 0, "Thorned Gauntlet+ heals once per attack")
		if plus:
			assert_eq(int(healed[0].amount), CombatMath.percent_min1(hero.max_hp, 3))


func test_brimming_cup_powers_up_until_the_first_hit() -> void:
	for plus: bool in [false, true]:
		var engine := _engine(_passives("brimming_cup", plus), [Fx.hit(600), Fx.hit(900)])
		var hero := _target(engine)
		assert_eq(engine._power_of(hero), CombatMath.percent_min1(hero.power, 150 if plus else 130))
		_answer(engine, [PARRY, NONE])
		assert_true(hero.was_hit)
		assert_eq(engine._power_of(hero), hero.power, "gone once a hit lands")
		var restored := CombatEngine.restore(engine._setup, engine.snapshot())
		assert_true(restored.get_combatant(hero.id).was_hit, "in the snapshot")


func test_gravebound_ring_multiplies_counters_and_makes_hits_hurt_more() -> void:
	for plus: bool in [false, true]:
		var engine := _engine(_passives("gravebound_ring", plus), [Fx.hit(900)])
		var hero := _target(engine)
		assert_eq(int(engine.sequence.prompts[0].damage), CombatMath.percent_min1(_raw_hit(engine), 120),
				"hits on you +20% (the + keeps the price)")
		assert_eq(engine._counter_percent(hero, 100, Vector2i(1, 0)), 250 if plus else 200)


# --- counters ---------------------------------------------------------------------------------

func test_bone_whistle_exposes_the_foe_and_plus_hits_harder() -> void:
	var engine := _engine(_passives("bone_whistle"), [Fx.hit(900)])
	var hero := _target(engine)
	var events := _answer(engine, [PARRY])
	assert_false(_status_on(events, FOE, Status.EXPOSED).is_empty(), "the counter Exposes the foe")
	assert_eq(int(_status_on(events, FOE, Status.EXPOSED).source), hero.id)
	assert_eq(engine._counter_percent(hero, 100, Vector2i(1, 0)), 100)
	var plus := _engine(_passives("bone_whistle", true), [Fx.hit(900)])
	assert_eq(plus._counter_percent(_target(plus), 100, Vector2i(1, 0)), 130, "Bone Whistle+: counters +30%")
	var dodged := _engine(_passives("bone_whistle"), [Fx.hit(900)])
	assert_true(_status_on(_answer(dodged, [DODGE]), FOE, Status.EXPOSED).is_empty(), "no counter, no Expose")


func test_leech_hook_heals_on_a_counter() -> void:
	for plus: bool in [false, true]:
		var engine := _engine(_passives("echo_charm", plus), [Fx.hit(900)], {"start_hp": [10, 10, 10]})
		var hero := _target(engine)
		var events := _answer(engine, [PARRY])
		var after := Fx.index_of(events, "counter")
		var healed := _of(events.slice(after), "healed", "target", hero.id)
		assert_eq(healed.size(), 1)
		assert_eq(int(healed[0].amount), CombatMath.percent_min1(hero.max_hp, 8 if plus else 5))


func test_riposte_ring_fills_the_team_gauge_on_a_counter() -> void:
	for plus: bool in [false, true]:
		var engine := _engine(_passives("riposte_ring", plus), [Fx.hit(900)])
		_answer(engine, [PARRY])
		assert_eq(engine.team_gauge, 20 if plus else 10)


func test_grudge_stone_stacks_damage_with_each_counter_up_to_the_cap() -> void:
	for plus: bool in [false, true]:
		var engine := _engine(_passives("grudge_stone", plus), [Fx.hit(900)])
		var hero := _target(engine)
		_answer(engine, [PARRY])
		assert_eq(hero.grudge_stacks, 1)
		assert_eq(engine._power_of(hero), CombatMath.percent_min1(hero.power, 115 if plus else 110))
		var restored := CombatEngine.restore(engine._setup, engine.snapshot())
		assert_eq(restored.get_combatant(hero.id).grudge_stacks, 1, "in the snapshot")
	var capped := _engine(_passives("grudge_stone"), [Fx.hit(900)])
	var hero := _target(capped)
	hero.grudge_stacks = capped.tuning.grudge_stack_max
	_answer(capped, [PARRY])
	assert_eq(hero.grudge_stacks, capped.tuning.grudge_stack_max, "stops at grudge_stack_max")


func test_headsmans_hood_counters_always_crit_and_plus_crits_harder() -> void:
	for plus: bool in [false, true]:
		var engine := _engine(_passives("headsmans_hood", plus), [Fx.hit(900)])
		var hero := _target(engine)
		var events := _answer(engine, [PARRY])
		var counter := _of(events, "damage", "target", FOE).filter(
				func(e: Dictionary) -> bool: return String(e.cause) == "counter")
		assert_eq(counter.size(), 1)
		assert_true(bool(counter[0].crit), "a crit with the crit chance at 0")
		var amount := CombatMath.percent_min1(engine._power_of(hero), engine._counter_percent(hero, engine.tuning.counter_percent,
				Vector2i(1, 0)))
		var crit := engine._crit_damage(hero, amount)
		assert_eq(int(counter[0].amount), CombatMath.percent_min1(crit, 150) if plus else crit)


func test_bellringers_rope_puts_the_counterer_next_and_plus_empowers() -> void:
	for plus: bool in [false, true]:
		var engine := _engine(_passives("bellringers_rope", plus), [Fx.hit(900)])
		var hero := _target(engine)
		var events := _answer(engine, [PARRY])
		var after := Fx.index_of(events, "counter")
		assert_true(after >= 0)
		var next := Fx.first_of(events.slice(after), "turn_started")
		assert_eq(int(next.get("actor", -1)), hero.id, "the counterer's turn comes next")
		assert_eq(hero.has_status(Status.EMPOWERED), plus, "Bellringer's Rope+: Empowered too")


func test_counter_relics_also_work_in_a_team_counter() -> void:
	var passives := _passives("riposte_ring")
	passives.merge(_passives("echo_charm"))
	var engine := _engine(passives, [Fx.hit(900)], {"mode": Fx.PARTY, "start_hp": [10, 10, 10]})
	var outcomes: Array = []
	for _p: Variant in engine.sequence.prompts:
		outcomes.append(PARRY)
	var events := _answer(engine, outcomes)
	assert_true(bool(Fx.first_of(events, "counter").team), "a team counter")
	assert_eq(engine.team_gauge, 30, "each counterer's Riposte Ring")
	assert_eq(Fx.of_type(events.slice(Fx.index_of(events, "counter")), "healed").size(), 3, "each one's Leech Hook")


# --- first hits and run Relics ----------------------------------------------------------------

func test_grave_tag_exposes_the_foe_on_the_first_hit_and_plus_bleeds_it() -> void:
	for plus: bool in [false, true]:
		var engine := _engine(_passives("grave_tag", plus), [Fx.hit(900)])
		_to_party_turn(engine)
		var hero := engine.get_combatant(engine.active_actor)
		var events := engine.submit(Fx.use(engine, "basic_attack"))
		assert_false(_status_on(events, FOE, Status.EXPOSED).is_empty(), "the first hit Exposes")
		assert_eq(_status_on(events, FOE, Status.BLEEDING).is_empty(), not plus, "Grave Tag+ also Bleeds")
		if plus:
			assert_eq(int(_status_on(events, FOE, Status.BLEEDING).turns), 3)
		assert_true(hero.first_hit_done)
		var again: Array[Dictionary] = []
		engine._deal_damage(hero, engine.get_combatant(FOE), 1, "ability", again)
		assert_true(_status_on(again, FOE, Status.EXPOSED).is_empty(), "only the first hit of the fight")


func test_kingsbane_nail_raises_power_in_elite_and_boss_fights() -> void:
	var run := RunState.begin(_data, Fx.run_tuning(load("res://data/tuning/tuning.tres") as Tuning), 7)
	var husk := load("res://data/encounters/husk_fight.tres") as EncounterData
	var elite := load("res://data/encounters/deep_elite_hyena_pack.tres") as EncounterData
	var base := run.fight_setup(elite, 1, CombatSetup.Opening.NORMAL).party_power_percent[0]
	var nail := _relic("kingsbane_nail")
	assert_false(run.give_relic(nail, 0).is_empty())
	assert_eq(run.fight_setup(husk, 1, CombatSetup.Opening.NORMAL).party_power_percent[0], base, "not in a plain fight")
	assert_eq(run.fight_setup(elite, 1, CombatSetup.Opening.NORMAL).party_power_percent[0], CombatMath.percent(base, 130))
	assert_true(run.upgrade_relic(nail.id))
	assert_eq(run.fight_setup(elite, 1, CombatSetup.Opening.NORMAL).party_power_percent[0], CombatMath.percent(base, 150))


# --- skill presses ------------------------------------------------------------------------------

func test_pale_tithe_multiplies_perfect_presses_and_cuts_the_others() -> void:
	var strike := Fx.skill("strike", AbilityData.Target.SINGLE_ENEMY, 0, [300],
			{"damage_percent": 100, "press_damage_percent": 50})
	for plus: bool in [false, true]:
		var engine := _engine(_passives("pale_tithe", plus), [Fx.hit(900)])
		var hero := _target(engine)
		assert_eq(engine._skill_percent(hero, strike, true), 225 if not plus else CombatMath.percent(150, 175))
		assert_eq(engine._other_press_percent(hero, 100), 70, "other presses -30% (the + keeps the price)")
	var kit := _engine(_passives("pale_tithe"), [Fx.hit(900)], {"kits": [[strike], [strike], [strike]]})
	_to_party_turn(kit)
	var striker := kit.get_combatant(kit.active_actor)
	var prompt: Dictionary = Fx.first_of(kit.submit(Fx.use(kit, "strike")), "timed_sequence_declared").prompts[0]
	assert_eq(int(prompt.press_damage), CombatMath.percent_min1(kit._power_of(striker), 70))
	assert_eq(int(prompt.perfect_damage), CombatMath.percent_min1(kit._power_of(striker), 225))


# --- state ------------------------------------------------------------------------------------

func test_per_fight_relic_state_survives_to_dict() -> void:
	var c := Combatant.new()
	c.was_hit = true
	c.grudge_stacks = 4
	c.crit_ready = true
	c.first_hit_done = true
	c.null_hits_used = 2
	var back := Combatant.from_dict(c.to_dict())
	assert_eq([back.was_hit, back.grudge_stacks, back.crit_ready, back.first_hit_done, back.null_hits_used],
			[true, 4, true, true, 2])
	var old := Combatant.from_dict(Combatant.new().to_dict())
	assert_eq([old.was_hit, old.grudge_stacks, old.crit_ready, old.first_hit_done, old.null_hits_used],
			[false, 0, false, false, 0])
	assert_eq(Fx.find_illegal_value(c.to_dict()), "", "plain data, fit for the network")


func test_defence_relics_stay_deterministic() -> void:
	var passives := {}
	for id: String in ["ash_veil", "thick_hide", "hollow_mantle", "quick_boots", "moth_wing", "plague_bell",
			"widows_thimble", "thorned_gauntlet", "grudge_stone", "bellringers_rope"]:
		var mine := _passives(id, true)
		for key: String in mine:
			passives[key] = int(passives.get(key, 0)) + int(mine[key])
	var runs: Array = []
	for _r: int in 2:
		var engine := _engine(passives, [Fx.hit(600), Fx.hit(900, Fx.GROUND)], {"seed": 5})
		var trail: Array = []
		for _i: int in 6:
			if engine.phase == CombatEngine.Phase.AWAITING_TIMING:
				var pairs: Array = []
				var answers := [DODGE, NONE, JUMP]
				for idx: int in engine.pending_prompts():
					pairs.append([idx, answers[idx % answers.size()]])
				trail.append_array(engine.submit(Fx.resolve_now(engine, pairs)))
			elif engine.phase == CombatEngine.Phase.AWAITING_ACTION:
				trail.append_array(engine.submit(Fx.use(engine, "basic_attack")))
		runs.append(trail)
	assert_eq(runs[0], runs[1], "same seed, same commands, same events")
