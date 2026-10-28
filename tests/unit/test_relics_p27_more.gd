extends GutTest
## Phase 27's other Relics (DESIGN.md 8.25, stage 4): damage, turns, the fight's start, heals, falls,
## kills and the run. Each Relic is tested as shipped (its file's numbers) and as Relic+. The last
## tests check that every one of the 63 Relics has a "+" and an effect something reads.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")

const RUN_PATH := "res://data/runs/rotten_road.tres"
const GEAR_DIR := "res://data/gear/"
const ENGINE_PATH := "res://scripts/combat/core/combat_engine.gd"
const RUN_STATE_PATH := "res://scripts/run/run_state.gd"
const NONE: int = Defense.Outcome.NONE
const DODGE: int = Defense.Outcome.DODGE
const PRESS: int = Defense.Outcome.PRESS
const FOE: int = Fx.ENEMY_ID
const PLUS: Array[bool] = [false, true]

var _data: RunData
var _tuning: Tuning


func before_all() -> void:
	_data = load(RUN_PATH) as RunData
	_tuning = load("res://data/tuning/tuning.tres") as Tuning


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


## A fixture fight. `passives`: one Dictionary for every hero, or an Array of three (one per hero).
## options as Fx.setup, plus kits (Fx.kit_setup), team_ultimate, items, opening, hits (the foe's
## attack, default one normal hit) and mode. Default: the foe is tough and slow, so a hero acts first.
func _engine(passives: Variant, options: Dictionary = {}) -> CombatEngine:
	var opts := options.duplicate()
	if not opts.has("enemy_hp_percent"):
		opts["enemy_hp_percent"] = 1000
	if not opts.has("enemy_speed"):
		opts["enemy_speed"] = 10
	var hits: Array = opts.get("hits", [Fx.hit(900)])
	var setup := Fx.kit_setup(opts.get("kits", []) as Array,
			[Fx.attack("strike", hits, int(opts.get("mode", Fx.SINGLE)))], opts)
	for i: int in 3:
		var mine: Dictionary = (passives as Array)[i] if passives is Array else passives
		setup.party_passives.append(mine.duplicate())
	if opts.has("items"):
		setup.items.assign(opts.items as Array)
	if opts.has("opening"):
		setup.opening = int(opts.opening) as CombatSetup.Opening
	var engine := CombatEngine.new(setup)
	engine.start()
	return engine


## Only hero 0 has the Relic.
func _first_only(id: String, plus: bool) -> Array:
	return [_passives(id, plus), {}, {}]


func _run() -> RunState:
	return RunState.begin(_data, Fx.run_tuning(_tuning), 7)


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


func _healed(events: Array, target: int) -> int:
	var total := 0
	for e: Dictionary in _of(events, "healed", "target", target):
		total += int(e.amount)
	return total


func _gained(events: Array, character: int, reason: String) -> int:
	var total := 0
	for e: Dictionary in _of(events, "ap_changed", "character", character):
		if String(e.reason) == reason:
			total += int(e.delta)
	return total


## Damage `source` deals `target` for `amount` before the Relics that read the target (events kept).
func _hit(engine: CombatEngine, source: Combatant, target: Combatant, amount: int, crit: bool = false) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	engine._deal_damage(source, target, amount, "ability", events, crit)
	return events


func _hurt(hero: Combatant, percent: int) -> void:
	hero.hp = maxi(1, CombatMath.percent(hero.max_hp, percent))


# --- damage ------------------------------------------------------------------------------------

func test_bitter_root_hurts_bleeding_foes_more() -> void:
	for plus: bool in PLUS:
		var engine := _engine(_passives("bitter_root", plus))
		var hero := engine.get_combatant(0)
		var foe := engine.get_combatant(FOE)
		assert_eq(int(Fx.first_of(_hit(engine, hero, foe, 100), "damage").amount), 100, "not Bleeding: as is")
		foe.statuses[Status.BLEEDING] = {"turns": 2, "source": hero.id}
		assert_eq(int(Fx.first_of(_hit(engine, hero, foe, 100), "damage").amount), 150 if plus else 130)
		var plain := _engine({})
		plain.get_combatant(FOE).statuses[Status.BLEEDING] = {"turns": 2, "source": 0}
		assert_eq(int(Fx.first_of(_hit(plain, plain.get_combatant(0), plain.get_combatant(FOE), 100), "damage").amount), 100)


func test_black_ichor_raises_power_and_the_plus_eases_its_price() -> void:
	var run := _run()
	var base := run.power_percent(0)
	run.give_relic(_relic("black_ichor"), 0)
	assert_eq(run.power_percent(0), CombatMath.percent(base, 135))
	assert_eq(run.defense_percent(0), -35, "hits on the holder +35%")
	run.upgrade_relic("black_ichor")
	assert_eq(run.power_percent(0), CombatMath.percent(base, 135))
	assert_eq(run.defense_percent(0), -15, "Black Ichor+: only +15%")
	for plus: bool in PLUS:
		var engine := _engine(_passives("black_ichor", plus))
		var foe := engine.get_combatant(FOE)
		var raw := CombatMath.percent_min1(foe.power, 100)
		assert_eq(engine._hit_amount(foe, engine.get_combatant(0), 100), CombatMath.percent_min1(raw, 115 if plus else 135))


func test_bloodletters_fang_adds_crit_chance_and_rots() -> void:
	for plus: bool in PLUS:
		var engine := _engine(_passives("bloodletters_fang", plus))
		var hero := engine.get_combatant(0)
		assert_eq(engine.crit_chance(hero), engine.tuning.crit_base_percent + (45 if plus else 30))
		var events: Array[Dictionary] = []
		engine._start_of_turn(hero, events)
		var rot := _of(events, "damage", "target", 0)
		assert_eq(rot.size(), 1)
		assert_eq(String(rot[0].cause), "rot")
		assert_eq(int(rot[0].amount), CombatMath.percent_min1(hero.max_hp, 2), "the price stays 2%")


func test_breakers_maul_multiplies_the_stagger_bonus() -> void:
	for plus: bool in PLUS:
		var engine := _engine(_passives("breakers_maul", plus))
		var foe := engine.get_combatant(FOE)
		foe.staggered_turns = 1
		var stagger := 100 + engine.tuning.stagger_damage_taken_percent
		assert_eq(int(Fx.first_of(_hit(engine, engine.get_combatant(0), foe, 100), "damage").amount),
				CombatMath.percent(stagger, 170 if plus else 140))


func test_butchers_edge_multiplies_crit_damage() -> void:
	for plus: bool in PLUS:
		var engine := _engine(_passives("butchers_edge", plus))
		var crit := CombatMath.percent(engine.tuning.crit_damage_percent, 200 if plus else 160)
		assert_eq(engine._crit_damage(engine.get_combatant(0), 100), crit)


func test_hounds_tooth_makes_follow_ups_hit_harder() -> void:
	var strike := Fx.skill("strike", AbilityData.Target.SINGLE_ENEMY, 0, [300],
			{"damage_percent": 100, "follow_ups": true})
	for plus: bool in PLUS:
		var engine := _engine(_passives("hounds_tooth", plus), {"kits": [[strike], [strike], [strike]]})
		var declared := Fx.first_of(engine.submit(Fx.use(engine, "strike")), "timed_sequence_declared")
		var follow_ups: Array = (declared.prompts as Array).filter(
				func(p: Dictionary) -> bool: return String(p.role) == CombatEngine.ROLE_FOLLOW_UP)
		assert_eq(follow_ups.size(), 2)
		for p: Dictionary in follow_ups:
			var ally := engine.get_combatant(int(p.character))
			var pct := CombatMath.percent(engine.tuning.follow_up_percent, 180 if plus else 150)
			assert_eq(int(p.press_damage), CombatMath.percent_min1(engine._power_of(ally), pct))


func test_knotted_lash_ramps_each_hit_of_a_skill() -> void:
	var flurry := Fx.skill("flurry", AbilityData.Target.SINGLE_ENEMY, 0, [200, 400, 600], {"damage_percent": 100})
	for plus: bool in PLUS:
		var engine := _engine(_passives("knotted_lash", plus), {"kits": [[flurry], [flurry], [flurry]]})
		var hero := engine.get_combatant(engine.active_actor)
		var prompts: Array = Fx.first_of(engine.submit(Fx.use(engine, "flurry")), "timed_sequence_declared").prompts
		var ramp := 20 if plus else 10
		for i: int in 3:
			assert_eq(int(prompts[i].press_damage), CombatMath.percent_min1(engine._power_of(hero), 100 + ramp * i),
					"hit %d" % i)


func test_gravediggers_spade_boosts_every_third_damaging_action() -> void:
	for plus: bool in PLUS:
		var engine := _engine(_first_only("gravediggers_spade", plus))
		var hero := engine.get_combatant(0)
		var dealt: Array[int] = []
		for _i: int in 60:
			if dealt.size() >= 4:
				break
			if engine.phase == CombatEngine.Phase.AWAITING_TIMING:
				var pairs: Array = []
				for idx: int in engine.pending_prompts():
					pairs.append([idx, DODGE])
				engine.submit(Fx.resolve_now(engine, pairs))
				continue
			var mine := engine.active_actor == hero.id
			var events := engine.submit(Fx.use(engine, "basic_attack"))
			if mine:
				dealt.append(int(_of(events, "damage", "source", hero.id)[0].amount))
		assert_eq(dealt.size(), 4)
		assert_eq(dealt[1], dealt[0])
		assert_eq(dealt[2], CombatMath.percent_min1(dealt[0], 250 if plus else 200), "the third")
		assert_eq(dealt[3], dealt[0], "then the count starts again")
		assert_eq(hero.skills_used, 4)
	var spade := _engine(_passives("gravediggers_spade"))
	var striker := spade.get_combatant(0)
	striker.skills_used = 3
	assert_eq(spade._skill_boost(striker, striker, 0), 200)
	assert_eq(spade._skill_boost(striker, spade.get_combatant(1), 0), 100, "not another hero's skill")


func test_last_ember_raises_power_under_30_percent_hp() -> void:
	for plus: bool in PLUS:
		var engine := _engine(_passives("last_ember", plus))
		var hero := engine.get_combatant(0)
		var power := engine._power_of(hero)
		_hurt(hero, 25)
		assert_eq(engine._power_of(hero), CombatMath.percent_min1(power, 180 if plus else 150))


func test_lone_lantern_raises_the_last_heros_power() -> void:
	for plus: bool in PLUS:
		var engine := _engine(_passives("lone_lantern", plus))
		var hero := engine.get_combatant(0)
		var power := engine._power_of(hero)
		engine.get_combatant(1).hp = 0
		assert_eq(engine._power_of(hero), power, "two still stand")
		engine.get_combatant(2).hp = 0
		assert_eq(engine._power_of(hero), CombatMath.percent_min1(power, 200 if plus else 160))


func test_rot_hunter_multiplies_the_exposed_bonus() -> void:
	for plus: bool in PLUS:
		var engine := _engine(_passives("rot_hunter", plus))
		var basic := engine.get_ability("basic_attack")
		var bonus := engine.tuning.exposed_bonus_percent
		assert_eq(engine._exposed_bonus(engine.get_combatant(0), basic, true),
				CombatMath.percent(100 + bonus, 180 if plus else 150) - 100)


func test_ember_stone_crits_make_the_foe_bleed() -> void:
	for plus: bool in PLUS:
		var engine := _engine(_passives("ember_stone", plus))
		var hero := engine.get_combatant(0)
		var foe := engine.get_combatant(FOE)
		assert_true(_status_on(_hit(engine, hero, foe, 10), FOE, Status.BLEEDING).is_empty(), "no crit, no Bleed")
		var bleed := _status_on(_hit(engine, hero, foe, 10, true), FOE, Status.BLEEDING)
		assert_eq(int(bleed.turns), 4 if plus else 2)
		assert_eq(int(bleed.source), hero.id)


# --- AP and costs -------------------------------------------------------------------------------

func test_chain_of_silence_fills_more_gauge_and_starts_one_ap_down() -> void:
	for plus: bool in PLUS:
		var engine := _engine(_passives("chain_of_silence", plus))
		var hero := engine.get_combatant(0)
		assert_eq(engine._gauge_gain(hero, 10), 18 if plus else 15)
		assert_eq(hero.ap, clampi(engine.tuning.start_ap - 1, 0, engine.tuning.max_ap))


func test_oathbreakers_band_starts_at_full_ap_and_hits_hurt_more() -> void:
	for plus: bool in PLUS:
		var engine := _engine(_first_only("oathbreakers_band", plus))
		assert_eq(engine.get_combatant(0).ap, engine.tuning.max_ap)
		assert_eq(engine.get_combatant(1).ap, engine.tuning.start_ap, "only the holder")
		var foe := engine.get_combatant(FOE)
		assert_eq(engine._hit_amount(foe, engine.get_combatant(0), 100),
				CombatMath.percent_min1(foe.power, 115 if plus else 130))


func test_rotten_crown_cuts_skill_costs_and_rots() -> void:
	var heavy := Fx.ability("heavy_strike", 2, 0, 220)
	for plus: bool in PLUS:
		var engine := _engine(_passives("rotten_crown", plus), {"kits": [[heavy], [heavy], [heavy]]})
		var hero := engine.get_combatant(engine.active_actor)
		assert_eq(CombatEngine.skill_cost(heavy, hero.passives), 1)
		assert_eq(CombatEngine.skill_cost(engine.get_ability("basic_attack"), hero.passives), 0, "never below 0")
		hero.ap = 1
		assert_true(engine.can_afford(hero.id, "heavy_strike"))
		assert_true(engine.can_use(hero.id, "heavy_strike"))
		var events := engine.submit(Fx.use(engine, "heavy_strike"))
		assert_eq(Fx.of_type(events, "command_rejected").size(), 0)
		assert_eq(_gained(events, hero.id, "spend"), -1, "pays the cut cost")
		var rot: Array[Dictionary] = []
		var other := engine.get_combatant(0 if hero.id != 0 else 1)
		engine._start_of_turn(other, rot)
		assert_eq(int(_of(rot, "damage", "target", other.id)[0].amount), CombatMath.percent_min1(other.max_hp, 1 if plus else 3))
	var plain := _engine({}, {"kits": [[heavy], [heavy], [heavy]]})
	var actor := plain.get_combatant(plain.active_actor)
	actor.ap = 1
	assert_false(plain.can_afford(actor.id, "heavy_strike"), "without it, 2 AP")
	assert_eq(String(Fx.first_of(plain.submit(Fx.use(plain, "heavy_strike")), "command_rejected").reason), "not_enough_ap")


func test_whetstone_basic_attack_gives_more_ap() -> void:
	var heavy := Fx.ability("heavy_strike", 0, 1, 100)
	for plus: bool in PLUS:
		var engine := _engine(_passives("whetstone", plus), {"kits": [[heavy], [heavy], [heavy]]})
		var hero := engine.active_actor
		assert_eq(_gained(engine.submit(Fx.use(engine, "basic_attack")), hero, "ability"), 3 if plus else 2)
		var next := engine.active_actor
		assert_eq(_gained(engine.submit(Fx.use(engine, "heavy_strike")), next, "ability"), 1, "only the basic attack")


func test_kindling_bundle_passes_spare_ap_to_the_next_hero() -> void:
	for plus: bool in PLUS:
		var engine := _engine(_passives("kindling_bundle", plus))
		var hero := engine.get_combatant(engine.active_actor)
		var next: Combatant = null
		for id: int in engine.living_party_ids():
			var c := engine.get_combatant(id)
			if c != hero and (next == null or Timeline.comes_before(c, next)):
				next = c
		var events := engine.submit(Fx.use(engine, "basic_attack"))
		assert_eq(_gained(events, next.id, "given"), 2 if plus else 1)
		var none: Array[Dictionary] = []
		hero.ap = 0
		engine._pass_spare_ap(hero, none)
		assert_eq(none.size(), 0, "no AP left, nothing to pass")


func test_hollow_drum_team_ultimate_gives_the_party_ap() -> void:
	var ult := Fx.skill("ult", AbilityData.Target.ALL_ENEMIES, 0, [], {"damage_percent": 100, "team_ultimate": true})
	for plus: bool in PLUS:
		var engine := _engine(_first_only("hollow_drum", plus), {"team_ultimate": ult})
		engine.team_gauge = engine.tuning.team_gauge_max
		var events := engine.submit(Fx.use(engine, "ult"))
		assert_eq(Fx.of_type(events, "command_rejected").size(), 0)
		for id: int in 3:
			assert_eq(_gained(events, id, "gear"), 3 if plus else 2, "hero %d" % id)
	var plain := _engine({}, {"team_ultimate": ult})
	plain.team_gauge = plain.tuning.team_gauge_max
	assert_eq(_gained(plain.submit(Fx.use(plain, "ult")), 0, "gear"), 0)


func test_reapers_coin_pays_for_a_kill_and_a_stagger() -> void:
	var doom := Fx.attack("doom", [Fx.hit(900)])
	doom.charge_turns = 2
	doom.break_damage_percent = 1
	for plus: bool in PLUS:
		var engine := _engine(_passives("reapers_coin", plus), {"hits": [Fx.hit(900)]})
		var hero := engine.get_combatant(0)
		var foe := engine.get_combatant(FOE)
		engine._attacks[doom.id] = doom
		foe.charge_attack = doom.id
		foe.charge_left = 1
		var broke := _hit(engine, hero, foe, engine._break_hp(foe, doom) + 1)
		assert_eq(Fx.of_type(broke, "doom_broken").size(), 1)
		assert_eq(_gained(broke, hero.id, "gear"), 3 if plus else 2, "a Stagger pays")
		foe.hp = 1
		assert_eq(_gained(_hit(engine, hero, foe, 50), hero.id, "gear"), 3 if plus else 2, "a kill pays")


func test_pilgrims_staff_gives_start_ap_per_act_and_one_more_as_plus() -> void:
	var run := _run()
	run.give_relic(_relic("war_drum"), 0)
	assert_eq(int(run.passives(0)[Passive.START_AP]), 1)
	run.act = 2
	assert_eq(int(run.passives(0)[Passive.START_AP]), 3, "1 per act")
	assert_true(run.upgrade_relic("war_drum"))
	assert_eq(int(run.passives(0)[Passive.START_AP]), 4, "Pilgrim's Staff+: +1 AP more")
	run.act = 0
	assert_eq(int(run.passives(0)[Passive.START_AP]), 2)


# --- the fight's start and turns ---------------------------------------------------------------

func test_first_light_starts_empowered_for_one_or_two_skills() -> void:
	for plus: bool in PLUS:
		var engine := _engine(_passives("first_light", plus))
		assert_eq(int(engine.get_combatant(0).statuses[Status.EMPOWERED].turns), 2 if plus else 1)


func test_mossbed_starts_with_regen() -> void:
	for plus: bool in PLUS:
		var engine := _engine(_passives("mossbed", plus))
		assert_eq(int(engine.get_combatant(0).statuses[Status.REGEN].turns), 3 if plus else 2)


func test_coffin_lid_starts_guarded_and_the_plus_keeps_it_a_turn_longer() -> void:
	for plus: bool in PLUS:
		var engine := _engine(_first_only("coffin_lid", plus))
		var hero := engine.get_combatant(0)
		assert_true(hero.has_status(Status.GUARDED))
		assert_false(engine.get_combatant(1).has_status(Status.GUARDED), "only the holder")
		var events: Array[Dictionary] = []
		engine._start_of_turn(hero, events)
		assert_true(hero.has_status(Status.GUARDED), "no foe has had a turn yet: it waits")
		engine._start_of_turn(engine.get_combatant(FOE), events)
		engine._start_of_turn(hero, events)
		assert_eq(hero.has_status(Status.GUARDED), plus, "Coffin Lid+: still Guarded on the next turn")
		engine._start_of_turn(hero, events)
		assert_false(hero.has_status(Status.GUARDED))


## A First Strike gives every hero a turn before the foes: the fight-start Guard still meets the
## first enemy attack and cuts its hit on the holder.
func test_coffin_lid_guard_meets_the_first_enemy_attack_after_a_first_strike() -> void:
	for plus: bool in PLUS:
		var engine := _engine(_first_only("coffin_lid", plus), {"opening": CombatSetup.Opening.FIRST_STRIKE,
				"enemy_speed": 80, "mode": Fx.PARTY, "practice": true})
		# Every hero's turn passes (the tutorial's hold), so the foe's first attack comes next.
		engine.submit(CombatCommands.practice({"hold_party": true, "pass_turn": true}))
		var hero := engine.get_combatant(0)
		assert_eq(engine.active_actor, FOE, "every hero's first turn passed, the foe attacks")
		assert_true(hero.has_status(Status.GUARDED), "still Guarded")
		var raw := CombatMath.percent_min1(engine.get_combatant(FOE).power, 100)
		var damage := {}
		for p: Dictionary in engine.sequence.prompts:
			damage[int(p.character)] = int(p.damage)
		assert_eq(int(damage[0]), CombatMath.percent_min1(raw, engine.tuning.guard_damage_percent), "the hit is cut")
		assert_eq(int(damage[1]), raw, "only the holder")
		var pairs: Array = []
		for idx: int in engine.pending_prompts():
			pairs.append([idx, NONE])
		engine.submit(Fx.resolve_now(engine, pairs))
		assert_eq(hero.has_status(Status.GUARDED), plus, "Coffin Lid+ lasts one more of the holder's turns")


func test_sour_milk_takes_the_first_turn_and_cuts_heals() -> void:
	for plus: bool in PLUS:
		# The foe is fast and the slowest hero (0) has it.
		var engine := _engine(_first_only("sour_milk", plus), {"enemy_speed": 400})
		assert_eq(engine.active_actor, 0)
		assert_eq(engine.phase, CombatEngine.Phase.AWAITING_ACTION)
		var hero := engine.get_combatant(0)
		_hurt(hero, 10)
		var events: Array[Dictionary] = []
		engine._heal(hero, hero, 50, events)
		assert_eq(_healed(events, 0), 45 if plus else 35)
	assert_ne(_engine({}, {"enemy_speed": 400}).active_actor, 0, "without it the fast foe goes first")


func test_hunters_horn_exposes_and_slows_foes_after_a_first_strike() -> void:
	for plus: bool in PLUS:
		var engine := _engine(_first_only("hunters_horn", plus), {"opening": CombatSetup.Opening.FIRST_STRIKE})
		var foe := engine.get_combatant(FOE)
		assert_eq(int(foe.statuses[Status.EXPOSED].turns), 2)
		assert_eq(foe.has_status(Status.SLOWED), plus, "Hunter's Horn+ also Slows")
		var ring := _engine(_first_only("hunters_horn", plus), {"opening": CombatSetup.Opening.RING})
		assert_false(ring.get_combatant(FOE).has_status(Status.EXPOSED), "not before the ring")
		var events := ring.submit(CombatCommands.set_opening("first_strike"))
		assert_false(_status_on(events, FOE, Status.EXPOSED).is_empty(), "the ring won")
		assert_eq(_status_on(events, FOE, Status.SLOWED).is_empty(), not plus)
	var normal := _engine(_first_only("hunters_horn", true))
	assert_false(normal.get_combatant(FOE).has_status(Status.EXPOSED), "no First Strike, nothing")
	var lost := _engine(_first_only("hunters_horn", true), {"opening": CombatSetup.Opening.RING})
	assert_true(_status_on(lost.submit(CombatCommands.set_opening("normal")), FOE, Status.EXPOSED).is_empty())


# --- heals and falls ----------------------------------------------------------------------------

func test_heartleaf_strengthens_heals_on_the_holder() -> void:
	for plus: bool in PLUS:
		var engine := _engine(_passives("heartleaf", plus))
		var hero := engine.get_combatant(0)
		_hurt(hero, 10)
		var events: Array[Dictionary] = []
		engine._heal(hero, hero, 20, events)
		assert_eq(_healed(events, 0), 30 if plus else 26)


func test_crown_of_thorns_cuts_hits_and_heals() -> void:
	for plus: bool in PLUS:
		var engine := _engine(_passives("crown_of_thorns", plus))
		var hero := engine.get_combatant(0)
		var foe := engine.get_combatant(FOE)
		assert_eq(engine._hit_amount(foe, hero, 100), CombatMath.percent_min1(foe.power, 60))
		_hurt(hero, 10)
		var events: Array[Dictionary] = []
		engine._heal(hero, hero, 100, events)
		assert_eq(_healed(events, 0), 75 if plus else 50)


func test_marrow_charm_shares_a_heal_with_the_lowest_ally() -> void:
	for plus: bool in PLUS:
		var engine := _engine(_first_only("marrow_charm", plus))
		var holder := engine.get_combatant(0)
		_hurt(holder, 10)
		_hurt(engine.get_combatant(1), 50)
		_hurt(engine.get_combatant(2), 20)
		var events: Array[Dictionary] = []
		engine._heal(holder, holder, 20, events)
		assert_eq(_healed(events, 0), 20)
		assert_eq(_healed(events, 2), 20 if plus else 10, "the lowest ally gets half (the +: all)")
		assert_eq(_healed(events, 1), 0)
		var back: Array[Dictionary] = []
		engine._heal(holder, engine.get_combatant(2), 10, back)
		assert_eq(_healed(back, 0), 0, "only heals on the holder are shared")


func test_hunger_charm_heals_holders_when_any_foe_falls_and_rots() -> void:
	for plus: bool in PLUS:
		var engine := _engine(_first_only("hunger_charm", plus))
		var holder := engine.get_combatant(0)
		_hurt(holder, 50)
		var foe := engine.get_combatant(FOE)
		foe.hp = 1
		var events := _hit(engine, engine.get_combatant(1), foe, 10)
		assert_eq(_healed(events, 0), CombatMath.percent_min1(holder.max_hp, 10 if plus else 6), "whoever downs it")
		var rot: Array[Dictionary] = []
		engine._start_of_turn(holder, rot)
		assert_eq(int(_of(rot, "damage", "target", 0)[0].amount), CombatMath.percent_min1(holder.max_hp, 2))


func test_gravebloom_heals_and_the_plus_gives_ap_when_an_ally_falls() -> void:
	for plus: bool in PLUS:
		var engine := _engine(_first_only("gravebloom", plus))
		var holder := engine.get_combatant(0)
		_hurt(holder, 30)
		var fallen := engine.get_combatant(1)
		fallen.hp = 0
		var events: Array[Dictionary] = []
		engine._on_downed(fallen, events)
		assert_eq(_healed(events, 0), CombatMath.percent_min1(holder.max_hp, 20))
		assert_eq(_gained(events, 0, "gear"), 2 if plus else 0)
		var ran := engine.get_combatant(2)
		ran.escaped = true
		var none: Array[Dictionary] = []
		engine._on_downed(ran, none)
		assert_eq(_healed(none, 0), 0, "a hero who ran did not fall")


func test_martyrs_ash_gives_allies_ap_when_the_holder_falls() -> void:
	for plus: bool in PLUS:
		var engine := _engine(_first_only("martyrs_ash", plus))
		var holder := engine.get_combatant(0)
		holder.hp = 0
		var events: Array[Dictionary] = []
		engine._on_downed(holder, events)
		for id: int in [1, 2]:
			assert_eq(_gained(events, id, "gear"), 3 if plus else 2)
		var other := _engine(_first_only("martyrs_ash", plus))
		other.get_combatant(1).hp = 0
		var none: Array[Dictionary] = []
		other._on_downed(other.get_combatant(1), none)
		assert_eq(_gained(none, 2, "gear"), 0, "only when the holder falls")


func test_second_wind_rises_once_at_its_percent() -> void:
	for plus: bool in PLUS:
		var engine := _engine(_passives("second_wind", plus))
		var hero := engine.get_combatant(0)
		hero.hp = 0
		var events: Array[Dictionary] = []
		engine._second_winds(events)
		assert_eq(hero.hp, CombatMath.percent_min1(hero.max_hp, 60 if plus else 30))
		hero.hp = 0
		engine._second_winds(events)
		assert_eq(hero.hp, 0, "once a fight")


func test_tallow_candle_regen_once_under_half_hp() -> void:
	for plus: bool in PLUS:
		var engine := _engine(_passives("tallow_candle", plus), {"enemy_speed": 200})
		var target := engine.get_combatant(int((engine.sequence.prompts[0] as Dictionary).character))
		var damage := int(engine.sequence.prompts[0].damage)
		target.hp = mini(target.max_hp, CombatMath.percent(target.max_hp, 50) + CombatMath.percent(damage, 50))
		var events := engine.submit(Fx.resolve_now(engine, [[0, NONE]]))
		assert_eq(int(_status_on(events, target.id, Status.REGEN).turns), 5 if plus else 3)
		assert_true(target.low_regen_used)
		target.statuses.erase(Status.REGEN)
		var again := _hit(engine, engine.get_combatant(FOE), target, 1)
		assert_true(_status_on(again, target.id, Status.REGEN).is_empty(), "once a fight")
	var hp_side := _engine(_passives("tallow_candle"))
	var hero := hp_side.get_combatant(0)
	_hurt(hero, 55)
	var bleed := _hit(hp_side, hp_side.get_combatant(FOE), hero, CombatMath.percent(hero.max_hp, 10))
	assert_false(_status_on(bleed, 0, Status.REGEN).is_empty(), "any damage that takes the hero under half")


func test_menders_charm_makes_items_work_better() -> void:
	var tonic := ItemData.new()
	tonic.id = "tonic"
	tonic.display_name = "Tonic"
	tonic.effect = ItemData.Effect.HEAL_ONE
	tonic.amount_percent = 20
	tonic.ap_cost = 0
	tonic.kind = ItemData.Kind.CONSUMABLE
	tonic.use_in_fight = true
	for plus: bool in PLUS:
		var items: Array = [{"uid": 1, "item": tonic, "amount": 20, "name": "Tonic"}]
		var engine := _engine(_passives("menders_charm", plus), {"items": items})
		var hero := engine.get_combatant(engine.active_actor)
		_hurt(hero, 10)
		var targets: Array[int] = [hero.id]
		var events := engine.submit(CombatCommands.use_item(engine.turn_number, hero.id, 1, targets))
		assert_eq(_healed(events, hero.id), CombatMath.percent_min1(hero.max_hp, 40 if plus else 30))


# --- the run -----------------------------------------------------------------------------------

func test_rain_pouch_heals_its_holder_at_any_campfire_pick() -> void:
	for plus: bool in PLUS:
		var run := _run()
		run.give_relic(_relic("rain_pouch"), 1)
		if plus:
			assert_true(run.upgrade_relic("rain_pouch"))
		for slot: int in 3:
			run.hp[slot] = 1
		var healed := run.campfire_heal()
		assert_eq(healed[1], CombatMath.percent(run.max_hp(1), 40 if plus else 25))
		assert_eq(healed[0], 0, "only the holder")
		assert_eq(run.hp[0], 1)
	var none := _run()
	assert_eq(none.campfire_heal(), [0, 0, 0] as Array[int])


# --- state and determinism -----------------------------------------------------------------------

func test_new_per_fight_state_survives_to_dict() -> void:
	var c := Combatant.new()
	c.skills_used = 5
	c.low_regen_used = true
	var back := Combatant.from_dict(c.to_dict())
	assert_eq([back.skills_used, back.low_regen_used], [5, true])
	var old := {}
	for key: String in c.to_dict():
		if key != "skills_used" and key != "low_regen_used":
			old[key] = c.to_dict()[key]
	var loaded := Combatant.from_dict(old)
	assert_eq([loaded.skills_used, loaded.low_regen_used], [0, false], "older dictionaries load as 0 and false")


func test_stage_four_relics_stay_deterministic_and_restore() -> void:
	var passives := {}
	for id: String in ["bitter_root", "ember_stone", "knotted_lash", "gravediggers_spade", "kindling_bundle",
			"whetstone", "lone_lantern", "tallow_candle", "marrow_charm", "hounds_tooth", "coffin_lid", "mossbed"]:
		var mine := _passives(id, true)
		for key: String in mine:
			passives[key] = int(passives.get(key, 0)) + int(mine[key])
	var flurry := Fx.skill("flurry", AbilityData.Target.SINGLE_ENEMY, 0, [200, 400], {"damage_percent": 100,
			"follow_ups": true})
	var runs: Array = []
	var snaps: Array = []
	for _r: int in 2:
		var engine := _engine(passives, {"seed": 5, "enemy_speed": 120, "kits": [[flurry], [flurry], [flurry]],
				"tuning": Tuning.new()})
		var trail: Array = []
		for i: int in 14:
			if engine.phase == CombatEngine.Phase.AWAITING_TIMING:
				var pairs: Array = []
				for idx: int in engine.pending_prompts():
					pairs.append([idx, [PRESS, NONE, DODGE][(idx + i) % 3]])
				trail.append_array(engine.submit(Fx.resolve_now(engine, pairs)))
			elif engine.phase == CombatEngine.Phase.AWAITING_ACTION:
				trail.append_array(engine.submit(Fx.use(engine, "flurry" if i % 2 == 0 else "basic_attack")))
		runs.append(trail)
		snaps.append(engine.snapshot())
	assert_eq(runs[0], runs[1], "same seed, same commands, same events")
	var setup := Fx.kit_setup([[flurry], [flurry], [flurry]], [Fx.attack("strike", [Fx.hit(900)])],
			{"seed": 5, "enemy_speed": 120, "enemy_hp_percent": 1000, "tuning": Tuning.new()})
	for i: int in 3:
		setup.party_passives.append(passives.duplicate())
	assert_eq(CombatEngine.restore(setup, snaps[0]).snapshot(), snaps[0], "restore keeps the Relic state")


# --- every Relic: a "+" and an effect that something reads ---------------------------------------

## Every Relic in data/gear/ (not just the run's list): it has a "+", the "+" changes what it does,
## and each of its effects (the effect, the "+" rider, the price) is read by the fight engine (its
## Passive key) or by the run (its GearData.Effect).
func test_every_relic_file_has_a_plus_and_a_wired_effect() -> void:
	var engine_source := (load(ENGINE_PATH) as GDScript).source_code
	var run_source := (load(RUN_STATE_PATH) as GDScript).source_code
	var files := DirAccess.get_files_at(GEAR_DIR)
	var count := 0
	for file: String in files:
		if not file.ends_with(".tres"):
			continue
		var item := load(GEAR_DIR + file) as GearData
		assert_not_null(item, file)
		if item == null:
			continue
		count += 1
		assert_true(item.has_plus(), "%s has a Relic+" % item.id)
		assert_ne(item.effect_line(true), item.effect_line(false), "%s: the + changes its line" % item.id)
		var changed := false
		var effects: Array[int] = [item.effect]
		if item.has_rider():
			effects.append(item.plus_rider)
		if item.has_drawback():
			effects.append(item.drawback)
		for effect: int in effects:
			changed = changed or item.contribution(effect as GearData.Effect) \
					!= item.contribution(effect as GearData.Effect, true)
			var key := String(GearData.PASSIVE_KEYS.get(effect, ""))
			var effect_name := String(GearData.Effect.find_key(effect))
			if key.is_empty():
				assert_true(run_source.contains("GearData.Effect.%s" % effect_name),
						"%s: the run reads %s" % [item.id, effect_name])
			else:
				assert_true(Passive.ALL.has(key), "%s: %s is a Passive" % [item.id, key])
				assert_true(engine_source.contains("Passive.%s" % key.to_upper()),
						"%s: the fight reads %s" % [item.id, key])
		assert_true(changed, "%s: the + changes a number" % item.id)
	assert_eq(count, 63, "the 63 Relics")
	assert_eq(_data.gear.size(), count, "the run offers every Relic file")


## The Passive keys every Relic can give are named like their constants (the check above relies on it).
func test_passive_keys_match_their_constant_names() -> void:
	var consts := (load("res://scripts/combat/core/passive.gd") as GDScript).get_script_constant_map()
	for key: String in Passive.ALL:
		assert_eq(String(consts.get(key.to_upper(), "")), key)
