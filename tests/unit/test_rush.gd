extends GutTest
## Fight Rush rules (DESIGN.md 8.21, card #305): the RunState seams, the fight counter and depth,
## the schedule of elites and bosses, the tiers, seeds, boss growth, XP, the reward cards, extra
## picks, Relic slots, the dict round trip and its refusals, the dev head start and the records.
## Builds a small RushData in code from the shipped run, zones and encounters (the shipped
## data/rush file is checked in test_rush_data.gd). Nothing here touches user://settings.cfg.

const RUN_PATH := "res://data/runs/rotten_road.tres"
const TUNING_PATH := "res://data/tuning/tuning.tres"
const ENCOUNTER_PATH := "res://data/encounters/%s.tres"
const ZONE_PATH := "res://data/zones/%s.tres"
const GEAR_PATH := "res://data/gear/%s.tres"
const MAIN_PATH := "res://scenes/main.gd"
const NORMAL := RushState.Kind.NORMAL
const ELITE := RushState.Kind.ELITE
const BOSS := RushState.Kind.BOSS

var _data: RunData
var _tuning: Tuning
var _rush: RushData
var _settings_before: ConfigFile


func before_all() -> void:
	_data = load(RUN_PATH) as RunData
	_tuning = load(TUNING_PATH) as Tuning
	_rush = _build_rush(false)


func before_each() -> void:
	# Each test may change numbers: a fresh copy, so nothing leaks into the next test.
	_tuning = (load(TUNING_PATH) as Tuning).duplicate() as Tuning


func _rush_state(seed_value: int = 7) -> RushState:
	return RushState.begin_rush(_rush, _tuning, seed_value)


func _enc(id: String) -> EncounterData:
	return load(ENCOUNTER_PATH % id) as EncounterData


func _gear(id: String) -> GearData:
	return _data.gear.filter(func(g: GearData) -> bool: return g != null and g.id == id)[0] as GearData


## The tiers and boss cycle of spec 2.2, built from the shipped data. `all_items`: every item the run
## knows, unfiltered (to check that the cards filter them too).
func _build_rush(all_items: bool) -> RushData:
	var hollow := load(ZONE_PATH % "rotten_hollow") as ZoneData
	var bog := load(ZONE_PATH % "sunken_bog") as ZoneData
	var ruins := load(ZONE_PATH % "ashen_ruins") as ZoneData
	var first := _data.acts[0]
	var second := _data.acts[1]
	var r := RushData.new()
	r.run = _data
	r.tiers.assign([
		_tier(1, [hollow], [hollow.roamer_pool], [first.elites], false),
		_tier(11, [bog], [bog.roamer_pool, first.ambushes], [first.elites], false),
		_tier(21, [ruins], [ruins.roamer_pool, second.ambushes], [second.elites], true),
		_tier(31, [hollow, bog, ruins], [hollow.roamer_pool, bog.roamer_pool, first.ambushes, ruins.roamer_pool,
				second.ambushes], [first.elites, second.elites], true),
	])
	r.bosses.assign([
		_boss("guard_gorged_one", hollow, null, 1),
		_boss("guard_mire_mother", bog, null, 3),
		_boss("guard_ash_warden", ruins, null, 9),
		_boss("husk_lord_fight", hollow, first.final_look, 6),
		_boss("hollow_king", null, second.final_look, 13),
	])
	for list: Array[ItemData] in [_data.shop_items, _data.found_items]:
		for item: ItemData in list:
			if item != null and not r.items.has(item) and (all_items or RushData.offerable(item)):
				r.items.append(item)
	return r


func _tier(from: int, zones: Array, pools: Array, elite_pools: Array, deep: bool) -> RushTier:
	var t := RushTier.new()
	t.from_fight = from
	t.zones.assign(zones)
	t.fights.assign(_union(pools))
	t.elites.assign(_union(elite_pools))
	t.deep = deep
	return t


func _union(pools: Array) -> Array[EncounterData]:
	var out: Array[EncounterData] = []
	for pool: Array in pools:
		for e: EncounterData in pool:
			if e != null and not out.has(e) and not e.boss and not e.mini_boss and not e.enemies.is_empty():
				out.append(e)
	return out


func _boss(id: String, zone: ZoneData, look: StageLook, home: int) -> RushBoss:
	var b := RushBoss.new()
	b.encounter = _enc(id)
	b.zone = zone
	b.look = look
	b.home_depth = home
	return b


## A fight worth `xp` XP to every standing hero.
func _xp_fight(xp: int) -> EncounterData:
	var enemy := EnemyData.new()
	enemy.xp = xp
	var e := EncounterData.new()
	e.id = "test_xp_%d" % xp
	e.enemies.assign([enemy])
	return e


func _full_hp(r: RushState) -> Array[int]:
	var out: Array[int] = []
	for slot: int in r.party_size():
		out.append(r.max_hp(slot))
	return out


## Wins fight `n` (set directly) with everyone standing: the cards of that fight are on show.
func _win(r: RushState, n: int, e: EncounterData = null) -> Dictionary:
	r.fight = n
	r.picks_left = 0
	var fought := e if e != null else _enc("husk_fight")
	return r.finish_fight(RunState.VICTORY, _full_hp(r), fought, {})


func _kinds(r: RushState) -> Array:
	return r.offer.map(func(c: Dictionary) -> String: return String(c.kind))


# --- 1, 2: the RunState seams ----------------------------------------------------------------

func test_run_begin_is_unchanged_and_says_run() -> void:
	var run := RunState.begin(_data, _tuning, 7)
	var act := run.act_data(0)
	var map := RunMap.generate(CombatRng.new(7), _tuning, act.zones.size(), not act.elites.is_empty(),
			not act.events.is_empty(), true)
	assert_eq(run.map.stops, map.stops, "the same map for seed 7")
	assert_eq(run.gold, _tuning.run_start_gold)
	for slot: int in run.party_size():
		assert_eq(run.levels[slot], 1)
		assert_eq(run.hp[slot], run.max_hp(slot), "full HP at oath 0")
	assert_eq(run.mode(), "run")
	assert_eq(run.to_dict().mode, "run")
	assert_true(run.shows_gold() and run.teaches_echoes())
	var old := run.to_dict()
	old.erase("mode")
	var copy := RunState.from_dict(_data, _tuning, old)
	assert_not_null(copy, "a dict with no mode (an older save) still loads")
	if copy != null:
		assert_eq(copy.to_dict(), run.to_dict())


func test_each_mode_refuses_the_others_dict() -> void:
	var run := RunState.begin(_data, _tuning, 7)
	var rush := _rush_state(7)
	var run_before := run.to_dict()
	var rush_before := rush.to_dict()
	assert_eq(rush_before.mode, "rush")
	assert_false(rush.apply_dict(run_before), "a Rush refuses a run's dict")
	assert_false(run.apply_dict(rush_before), "a run refuses a Rush's dict")
	var forged := rush_before.duplicate(true)
	forged.mode = "run"
	assert_false(rush.apply_dict(forged), "a Rush dict that says run is refused")
	assert_eq(run.to_dict(), run_before, "nothing changed")
	assert_eq(rush.to_dict(), rush_before, "nothing changed")
	assert_null(RushState.from_rush_dict(_rush, _tuning, run_before))


# --- 3 to 8: fights, depth, schedule, tiers, seeds -------------------------------------------

func test_counter_and_depth() -> void:
	var r := _rush_state()
	assert_eq(r.fight, 0)
	assert_eq(r.reached(), 0)
	assert_null(r.encounter_now())
	assert_true(r.map.stops.is_empty() and r.current().is_empty() and r.at == -1, "no map")
	assert_false(r.pact_pending, "no pact (no crossroads at the start)")
	r.next_fight()
	assert_eq(r.fight, 1)
	assert_eq(r.reached(), 1)
	assert_not_null(r.encounter_now())
	assert_eq(r._depth(), 0, "fight 1 is as deep as a run's first row")
	assert_eq(r.enemy_hp_percent(), 100)
	r.fight = 11
	assert_eq(r._depth(), 10)
	assert_eq(r.enemy_hp_percent(), 100 + 10 * _tuning.run_enemy_hp_row_percent)
	assert_eq(r.enemy_power_percent(), 100 + 10 * _tuning.run_enemy_power_row_percent)
	_tuning.rush_enemy_hp_step_add = 2
	assert_eq(r.enemy_hp_percent(), 170, "fight 11 at 5 + 2 per step")
	_tuning.rush_depth_per_fight_percent = 50
	assert_eq(r._depth(), 5, "half a row per fight")
	_tuning.rush_depth_per_fight_percent = 100
	var e := _enc("husk_fight")
	r.fight = 29
	assert_gt(r.enemy_tempo_percent(e), _tuning.attack_tempo_floor_percent)
	r.fight = 31
	assert_eq(r.enemy_tempo_percent(e), _tuning.attack_tempo_floor_percent, "the speed floor at fight 31")
	r.fight = 61
	assert_eq(r.enemy_tempo_percent(e), _tuning.attack_tempo_floor_percent, "and never faster")


func test_schedule_and_boss_cycle() -> void:
	var r := _rush_state()
	var want := {0: NORMAL, 5: ELITE, 10: BOSS, 15: ELITE, 20: BOSS}
	for n: int in range(0, 21):
		assert_eq(r.kind_of(n), want.get(n, NORMAL), "fight %d" % n)
	var cycle: Array[String] = []
	for n: int in range(10, 61, 10):
		cycle.append(r.boss_entry(n).encounter.id)
	assert_eq(cycle, ["guard_gorged_one", "guard_mire_mother", "guard_ash_warden", "husk_lord_fight", "hollow_king",
			"guard_gorged_one"] as Array[String])
	assert_null(r.boss_entry(5), "no boss on an elite fight")


func test_tiers_and_deep_versions() -> void:
	var r := _rush_state()
	var from := {1: 1, 10: 1, 11: 11, 21: 21, 31: 31, 99: 31}
	for n: int in from:
		assert_eq(r.tier_of(n).from_fight, from[n], "fight %d" % n)
	r.fight = 20
	assert_false(r.is_deep())
	r.fight = 21
	assert_true(r.is_deep(), "deep from fight 21")
	r.encounter_id = "slinger_trio"
	assert_eq(r.encounter_now().id, "deep_slinger_trio", "a deep tier fights the deep version")
	r.fight = 50
	r.encounter_id = "hollow_king"
	assert_eq(r.encounter_now().id, "hollow_king", "the base one when there is no deep version")
	r.fight = 5
	r.encounter_id = "elite_hyena_pack"
	assert_eq(r.encounter_now().id, "elite_hyena_pack", "fight 5 is not deep")
	r.fight = 30
	r.encounter_id = "guard_ash_warden"
	assert_eq(r.encounter_now().id, "deep_guard_ash_warden", "a guard in a deep tier is its deep version")


func test_seeds_repeat_and_never_twice_in_a_row() -> void:
	var a := _rush_state(7)
	var b := _rush_state(7)
	var other := _rush_state(8)
	var differs := false
	var prev := ""
	for n: int in range(1, 41):
		a.next_fight()
		b.next_fight()
		other.next_fight()
		assert_eq(a.fight, n)
		assert_eq(a.encounter_id, b.encounter_id, "fight %d: same encounter" % n)
		assert_eq(a.zone_now(), b.zone_now(), "fight %d: same zone" % n)
		assert_eq(a.weather_now(), b.weather_now(), "fight %d: same weather" % n)
		assert_ne(a.encounter_id, prev, "fight %d: not the one just fought" % n)
		assert_not_null(a.encounter_now(), "fight %d has a fight" % n)
		assert_not_null(a.look_now(), "fight %d has a look" % n)
		if a.kind_of(n) != BOSS:
			assert_true(a.tier_of(n).zones.has(a.zone_now()), "fight %d: a zone of its tier" % n)
		differs = differs or a.encounter_id != other.encounter_id
		prev = a.encounter_id
	assert_true(differs, "another seed fights other fights")
	a.fight = 50
	assert_null(a.zone_now(), "the Hollow King's throne has no zone")
	assert_null(a.weather_now(), "and so no weather")
	assert_true(a.air_now().is_empty())
	assert_eq(a.look_now(), _data.acts[1].final_look)


func test_bosses_grow_from_their_home_depth() -> void:
	var r := _rush_state()
	r.fight = 40
	var lord := _enc("husk_lord_fight")
	var numbers := r.fight_numbers(lord)
	assert_eq(int(numbers.depth), 39 - 6, "the Husk Lord grows by the depth past where a run meets it")
	assert_eq(int(numbers.hp), CombatMath.percent(100 + 33 * _tuning.run_enemy_hp_row_percent, lord.enemy_hp_percent))
	r.fight = 10
	var gorged := _enc("guard_gorged_one")
	numbers = r.fight_numbers(gorged)
	assert_eq(int(numbers.depth), 9 - 1, "a guard fought as a boss too")
	assert_eq(int(numbers.hp), CombatMath.percent(100 + 8 * _tuning.run_enemy_hp_row_percent, gorged.enemy_hp_percent))
	_tuning.rush_scale_bosses = false
	assert_eq(int(r.fight_numbers(gorged).hp), CombatMath.percent(100, gorged.enemy_hp_percent), "no growth when off")
	r.fight = 40
	assert_eq(int(r.fight_numbers(lord).hp), CombatMath.percent(100, lord.enemy_hp_percent))


func test_fight_setup_has_no_running_and_the_flat_multipliers() -> void:
	var r := _rush_state()
	r.fight = 3
	var e := _enc("husk_fight")
	assert_true(e.can_run, "a fight a run could run from")
	var setup := r.fight_setup(e, 1, CombatSetup.Opening.NORMAL)
	assert_false(setup.can_run, "no running away in a Rush")
	assert_true(setup.allow_marks, "marks from the second step on")
	var hp := setup.enemy_hp_percent
	_tuning.rush_enemy_hp_percent = 200
	assert_eq(r.fight_setup(e, 1, CombatSetup.Opening.NORMAL).enemy_hp_percent, hp * 2)
	r.fight = 1
	assert_false(r.fight_setup(e, 1, CombatSetup.Opening.NORMAL).allow_marks, "fight 1 has no marks")


# --- 9 to 13: XP, the end of a fight, the cards, extra picks -----------------------------------

func test_xp_gold_drops_and_echoes() -> void:
	var r := _rush_state()
	r.fight = 50
	var king := _enc("hollow_king")
	assert_lt(RunState.encounter_xp(king), _tuning.rush_boss_min_xp, "the King's own data pays little")
	assert_eq(r.xp_full(king), _tuning.rush_boss_min_xp)
	_tuning.rush_xp_percent = 200
	assert_eq(r.xp_full(king), _tuning.rush_boss_min_xp * 2, "every Rush XP gain takes rush_xp_percent")
	_tuning.rush_xp_percent = 100
	r.fight = 3
	assert_eq(r.xp_full(_enc("husk_fight")), RunState.encounter_xp(_enc("husk_fight")), "a normal fight pays its own")
	r.fight = 50
	var hp := _full_hp(r)
	hp[1] = 0
	var xp := r.fight_xp(king, hp)
	assert_eq(xp[0], _tuning.rush_boss_min_xp)
	assert_eq(xp[1], CombatMath.percent(_tuning.rush_boss_min_xp, _tuning.run_xp_downed_percent), "the downed share")
	r.fight = 3
	var e := _enc("husk_fight")
	assert_eq(r.gold_for(e), 0)
	assert_true(r.relic_drops(e).is_empty())
	assert_false(r.shows_gold())
	assert_false(r.teaches_echoes())
	var charm := _gear("iron_charm")
	assert_eq(r.wear(0, 0, charm), 0)
	var pips := r.mastery_of(charm)
	var totals := r.pips_totals()
	_win(r, 3, e)
	assert_eq(r.mastery_of(charm), pips, "no Echo pips")
	assert_eq(r.pips_totals(), totals)
	assert_eq(r.gold, 0)
	assert_false(r.echo_learned(charm))
	assert_eq(r.echo_blocked_reason(1, charm), "Runs only")


func test_a_win_revives_counts_heals_and_offers_cards() -> void:
	var r := _rush_state()
	r.fight = 3
	var hp := _full_hp(r)
	hp[0] = 0
	r.finish_fight(RunState.VICTORY, hp, _enc("husk_fight"), {})
	assert_eq(r.hp[0], _tuning.run_downed_revive_hp, "a downed hero gets up")
	assert_eq(r.fights_won, 1)
	assert_eq(_kinds(r), ["heal", "point", "item"], "a normal fight's cards")
	assert_true(r.card_enabled(0), "Heal while someone is hurt")
	assert_eq(r.picks_left, 1)
	var out := _win(r, 5, _enc("elite_hyena_pack"))
	assert_eq(int(out.picks), 1)
	assert_eq(r.elites_beaten, 1)
	assert_eq(_kinds(r), ["heal", "point", "relic"], "an elite's cards")
	r.hp[0] = r.max_hp(0)
	assert_false(r.card_enabled(0), "Heal is greyed at full HP")
	assert_true(r.card_enabled(1))
	hp = _full_hp(r)
	hp[2] = 0
	r.hp[1] = 1
	r.fight = 10
	r.picks_left = 0
	r.finish_fight(RunState.VICTORY, hp, _enc("guard_gorged_one"), {})
	assert_eq(r.bosses_beaten, 1)
	for slot: int in r.party_size():
		assert_eq(r.hp[slot], r.max_hp(slot), "the boss heal fills everyone")
	assert_eq(_kinds(r), ["point", "relic", "relic"], "a boss's cards")
	assert_ne(r.offer[1].id, r.offer[2].id, "two different Relics")
	assert_eq(r.fights_won, 3)


func test_a_loss_ends_the_rush() -> void:
	var r := _rush_state()
	r.next_fight()
	assert_true(r.decides_run(RunState.DEFEAT))
	assert_false(r.decides_run(RunState.VICTORY), "a win never ends it")
	r.fight = 10
	assert_false(r.decides_run(RunState.VICTORY), "not even a boss")
	var hp := _full_hp(r)
	hp.fill(0)
	r.finish_fight(RunState.DEFEAT, hp, _enc("guard_gorged_one"), {})
	assert_eq(r.result, RunState.DEFEAT)
	assert_true(r.is_over())
	assert_false(r.decides_run(RunState.DEFEAT), "an ended Rush is decided already")
	var quit := _rush_state()
	quit.give_up()
	assert_eq(quit.result, RushState.GAVE_UP)
	quit.cap()
	assert_eq(quit.result, RushState.GAVE_UP, "the first end stays")


func test_taking_cards() -> void:
	var r := _rush_state()
	_win(r, 3)
	assert_eq(_kinds(r)[0], "heal")
	r.hp[0] = 1
	r.hp[1] = r.max_hp(1) - 5
	var before := r.hp.duplicate()
	var got := r.take_card(0)
	assert_eq(got.kind, "heal")
	assert_eq(r.hp[0], mini(r.max_hp(0), 1 + CombatMath.percent(r.max_hp(0), _tuning.rush_heal_card_percent)))
	assert_eq(r.hp[1], r.max_hp(1), "never past max HP")
	assert_eq((got.healed as Array)[1], 5)
	assert_eq(r.hp[2], before[2])
	assert_eq(r.picks_left, 0)
	assert_eq(r.pick_no, 1)
	assert_true(r.offer.is_empty(), "the cards go")
	assert_eq(r.take_card(0), {}, "no pick left")
	# Rest Relics change the Heal card as they change the campfire's Rest.
	var hunger := _gear("hunger_charm")
	var pouch := _gear("rain_pouch")
	assert_eq(r.wear(0, 0, hunger), 0)
	assert_eq(r.wear(1, 0, pouch), 0)
	assert_eq(r.card_heal_percent_of(0), 0, "Hunger Charm: nothing")
	assert_eq(r.card_heal_percent_of(1), 60, "Rain Pouch: 40% grows to 60%")
	assert_eq(r.card_heal_percent_of(2), _tuning.rush_heal_card_percent)
	_win(r, 4)
	r.hp[0] = 1
	r.hp[1] = r.max_hp(1)
	r.hp[2] = r.max_hp(2)
	assert_eq(r.heal_card_gain(0), 0)
	assert_false(r.card_enabled(0), "only a Hunger Charm wearer is hurt: Heal is greyed")
	# Train.
	var points := r.bonus_points.duplicate()
	got = r.take_card(1)
	assert_eq(got.kind, "point")
	for slot: int in r.party_size():
		assert_eq(r.bonus_points[slot], points[slot] + _tuning.rush_point_card_points)
	# An item and a Relic come back to be handed out; nothing is added yet.
	_win(r, 6)
	var item_card := r.offer[2]
	assert_eq(item_card.kind, "item")
	var pack := r.backpack.to_array()
	got = r.take_card(2)
	assert_true(got.give is ItemData)
	assert_eq((got.give as ItemData).id, item_card.id)
	assert_eq(r.backpack.to_array(), pack, "the item is not in the pack yet")
	_win(r, 15, _enc("elite_hyena_pack"))
	var relic := r.relic_by_id(String(r.offer[2].id))
	var level := r.relic_level(relic)
	got = r.take_card(2)
	assert_eq(got.give, relic)
	assert_eq(r.relic_level(relic), level, "the Relic is not added yet")
	assert_eq(r.pick_no, 4)


func test_spare_xp_makes_extra_picks() -> void:
	var r := _rush_state()
	_tuning.rush_spare_pick_xp = 300
	for slot: int in r.party_size():
		r.levels[slot] = _tuning.run_max_level
		r.xps[slot] = 0
	var hundred := _xp_fight(100)
	_win(r, 1, hundred)
	assert_eq(r.spare_xp, 100)
	assert_eq(r.picks_left, 1)
	_win(r, 2, hundred)
	assert_eq(r.picks_left, 1)
	_win(r, 3, hundred)
	assert_eq(r.picks_left, 2, "the third 100 XP makes an extra pick")
	assert_eq(r.spare_xp, 0)
	var mixed := _rush_state()
	mixed.levels[0] = _tuning.run_max_level
	mixed.levels[1] = 5
	mixed.levels[2] = 5
	_win(mixed, 1, hundred)
	assert_eq(mixed.spare_xp, 100, "one hero at the top level is enough")
	var close := _rush_state()
	close.levels[0] = _tuning.run_max_level - 1
	close.xps[0] = close.xp_to_next(0) - 50
	assert_eq(close.xp_to_cap(0), 50)
	_win(close, 1, hundred)
	assert_eq(close.spare_xp, 50, "only what passes the top level")
	assert_eq(close.levels[0], _tuning.run_max_level)
	# Extra picks always show the normal cards, even after a boss.
	var boss := _rush_state()
	for slot: int in boss.party_size():
		boss.levels[slot] = _tuning.run_max_level
	boss.spare_xp = 250
	_win(boss, 10, hundred)
	assert_eq(boss.picks_left, 2)
	assert_eq(_kinds(boss), ["point", "relic", "relic"])
	boss.take_card(0)
	boss.next_offer()
	assert_eq(_kinds(boss), ["heal", "point", "item"], "the extra pick")


# --- 14 to 17: Relic slots, the round trip, refusals, the head start ----------------------------

func test_relic_slots_open_with_the_first_elite_and_boss() -> void:
	var r := _rush_state()
	assert_eq(r.open_relic_slots(), 1)
	assert_eq(r.slot_lock_text(0), "")
	assert_eq(r.slot_lock_text(1), "First elite")
	assert_eq(r.slot_lock_text(2), "First boss")
	r.fight = 5
	assert_eq(r.win_relic_lines(null), [RushState.SLOT_OPENS_LINE] as Array[String], "the elite would open one")
	_win(r, 5, _enc("elite_hyena_pack"))
	assert_eq(r.open_relic_slots(), 2)
	assert_eq(r.slot_lock_text(1), "")
	assert_eq(r.slot_lock_text(2), "First boss")
	r.fight = 15
	assert_true(r.win_relic_lines(null).is_empty(), "a second elite opens nothing")
	assert_eq(r.elites_beaten, 1, "the preview changes nothing")
	_win(r, 10, _enc("guard_gorged_one"))
	assert_eq(r.open_relic_slots(), 3)
	assert_eq(r.slot_lock_text(2), "")


func test_round_trip_mid_pick() -> void:
	var r := _rush_state()
	r.next_fight()
	_win(r, 5, _enc("elite_hyena_pack"))
	r.encounter_id = "elite_hyena_pack"
	var charm := _gear("iron_charm")
	assert_eq(r.wear(0, 1, charm), 0, "slot 2 is open after the elite")
	r.note_players(2)
	r.spare_xp = 40
	assert_false(r.offer.is_empty())
	var d := r.to_dict()
	var copy := RushState.from_rush_dict(_rush, _tuning, d)
	assert_not_null(copy)
	if copy == null:
		return
	assert_eq(copy.to_dict(), d, "the other machine sees the same Rush")
	assert_eq(copy.gear[0][1], charm, "the slot-2 Relic is still worn")
	assert_eq(copy.offer, r.offer)
	assert_eq(copy.most_players, 2)
	var sent: Variant = bytes_to_var(var_to_bytes(d))
	var over_net := RushState.from_rush_dict(_rush, _tuning, sent as Dictionary)
	assert_not_null(over_net, "the RPC path keeps it whole")
	if over_net != null:
		assert_eq(over_net.to_dict(), d)


func test_tampered_dicts_are_refused() -> void:
	var r := _rush_state()
	r.next_fight()
	_win(r, 3)
	r.encounter_id = "husk_fight"
	var good := r.to_dict()
	assert_true(r.apply_dict(good))
	var bad_item := good.duplicate(true)
	bad_item.rush.offer[2] = {"kind": "item", "id": "no_such_item"}
	var bad_kind := good.duplicate(true)
	bad_kind.rush.offer[0] = {"kind": "gold", "amount": 5}
	var bad_encounter := good.duplicate(true)
	bad_encounter.rush.encounter_id = "no_such_fight"
	var bad_start := good.duplicate(true)
	bad_start.rush.start = 10
	var no_block := good.duplicate(true)
	no_block.erase("rush")
	var copy := _rush_state()
	var before := copy.to_dict()
	for d: Dictionary in [bad_item, bad_kind, bad_encounter, bad_start, no_block]:
		assert_false(copy.apply_dict(d))
		assert_null(RushState.from_rush_dict(_rush, _tuning, d))
	assert_eq(copy.to_dict(), before, "a refusal changes nothing")
	# A refused run part puts the slot counts back. The Rush block is read first, so a dict whose
	# run part fails must not leave its elite and boss counts behind (they open Relic slots 2 and 3).
	var won := _rush_state()
	won.next_fight()
	_win(won, 5, _enc("elite_hyena_pack"))
	_win(won, 10, _enc("guard_gorged_one"))
	won.encounter_id = "guard_gorged_one"
	assert_true(won.elites_beaten > 0 and won.bosses_beaten > 0, "the forged dict carries both counts")
	var forged := won.to_dict()
	forged.gold = "lots"
	assert_false(copy.apply_dict(forged))
	assert_eq(copy.elites_beaten, 0, "the forged elite count is not kept")
	assert_eq(copy.bosses_beaten, 0, "the forged boss count is not kept")
	assert_eq(copy.open_relic_slots(), 1)
	assert_eq(copy.to_dict(), before)
	# And the other way: a refused dict with no wins never shuts a slot that was open, nor takes
	# the Relic worn in it.
	var worn := _rush_state()
	worn.next_fight()
	_win(worn, 5, _enc("elite_hyena_pack"))
	worn.encounter_id = "elite_hyena_pack"
	var charm := _gear("iron_charm")
	assert_eq(worn.wear(0, 1, charm), 0, "slot 2 is open after the elite")
	var worn_before := worn.to_dict()
	var no_wins := _rush_state().to_dict()
	no_wins.gold = "lots"
	assert_false(worn.apply_dict(no_wins))
	assert_eq(worn.elites_beaten, 1, "the elite count is put back")
	assert_eq(worn.bosses_beaten, 0)
	assert_true(worn.slot_open(1), "slot 2 stays open")
	assert_eq(worn.gear[0][1], charm, "the slot-2 Relic is still worn")
	assert_eq(worn.to_dict(), worn_before)


func test_head_start_replays_the_fights_before() -> void:
	var r := RushState.begin_rush(_rush, _tuning, 7, null, 21)
	assert_eq(r.fight, 20)
	assert_eq(r.start_fight, 21)
	assert_eq(r.fights_won, 20)
	assert_eq(r.elites_beaten, 2)
	assert_eq(r.bosses_beaten, 2)
	assert_eq(r.open_relic_slots(), 3)
	assert_eq(r.picks_left, 0)
	assert_false(r.owned_relics().is_empty(), "the elite and boss Relic cards were taken")
	for slot: int in r.party_size():
		assert_eq(r.hp[slot], r.max_hp(slot))
		assert_gte(r.bonus_points[slot], 16 * _tuning.rush_point_card_points, "a Train card per normal fight")
		assert_gt(r.levels[slot], 1)
	var d := r.to_dict()
	var copy := RushState.from_rush_dict(_rush, _tuning, d)
	assert_not_null(copy, "a head start round trips")
	var five := RushState.begin_rush(_rush, _tuning, 7, null, 5)
	assert_eq(five.fight, 4)
	five.next_fight()
	assert_eq(five.kind_of(five.fight), ELITE)
	assert_true(five.encounter_now().elite)


# --- 18 to 20: records, salts, cards never offered -----------------------------------------------

func test_records() -> void:
	assert_eq(RushRecords.bucket(0), 1)
	assert_eq(RushRecords.bucket(2), 2)
	assert_eq(RushRecords.bucket(5), 3)
	assert_eq(RushRecords.label(1), "Solo")
	assert_eq(RushRecords.label(2), "Duo")
	assert_eq(RushRecords.label(3), "Trio")
	var e := RushRecords.entry(16, "2026-10-24")
	assert_true(RushRecords.is_valid(e))
	assert_false(RushRecords.is_valid({"fight": 0, "date": "x"}))
	assert_false(RushRecords.is_valid({"fight": 3.0, "date": "x"}))
	assert_false(RushRecords.is_valid("16"))
	assert_true(RushRecords.better(e, {}))
	assert_true(RushRecords.better(e, RushRecords.entry(15, "2026-10-23")))
	assert_false(RushRecords.better(e, RushRecords.entry(16, "2026-10-23")), "only a higher fight")
	assert_false(RushRecords.better({"fight": "lots"}, {}))
	assert_eq(RushRecords.best_of([e, RushRecords.entry(9, "a"), {"fight": 99}, null]), 16, "a bad entry is ignored")
	assert_eq(RushRecords.best_of([]), 0)
	var clean := {"autoplay": false, "screen": "", "start_fight": 1, "rush_fights": 0, "relics_mode": "",
			"relics_path": "", "seed_override": -1, "fixed_seed": 0, "tuning_default": true, "late": false,
			"players": 1, "pad_join_after_s": 0, "pad_leave_after_s": 0}
	assert_true(RushRecords.allowed(clean))
	var dirty := {"autoplay": true, "screen": "rush_end", "start_fight": 5, "rush_fights": 3, "relics_mode": "all",
			"relics_path": "x.json", "seed_override": 7, "fixed_seed": 9, "tuning_default": false, "late": true,
			"players": 3, "pad_join_after_s": 50, "pad_leave_after_s": 50}
	for key: String in dirty:
		var f := clean.duplicate()
		f[key] = dirty[key]
		assert_false(RushRecords.allowed(f), "%s alone blocks the records" % key)
		var missing := clean.duplicate()
		missing.erase(key)
		assert_false(RushRecords.allowed(missing), "a missing %s counts as a switch in use" % key)


## Main hands RushRecords every switch that makes a dev or bot Rush (D9), the pretend pads too: a
## person who starts `--rush --players=3` with no friends keeps no Trio record.
func test_main_keeps_dev_rushes_out_of_the_records() -> void:
	var main_script := load(MAIN_PATH) as GDScript
	var flags := func(args: Array, tuning_default: bool) -> Dictionary:
		return main_script.call("_rush_records_flags", CombatOptions.from_args(PackedStringArray(args), _tuning), _tuning,
				tuning_default)
	var plain: Dictionary = flags.call(["--rush"], true)
	for key: String in RushRecords.CLEAN_FLAGS:
		assert_true(plain.has(key), "Main fills %s" % key)
	assert_true(RushRecords.allowed(plain), "a plain Rush keeps records")
	assert_true(RushRecords.allowed(flags.call(["--rush", "--players=1"], true)), "one player is no switch")
	for args: Array in [["--rush", "--players=3"], ["--rush", "--players=2"], ["--rush", "--pad-join-after=50"],
			["--rush", "--pad-leave-after=50"], ["--rush", "--autoplay"], ["--rush", "--screen=rush_end"],
			["--rush-start=5"], ["--rush-fights=3"], ["--rush", "--relics=all"], ["--rush", "--relics-path=x.json"],
			["--rush", "--seed=7"]]:
		assert_false(RushRecords.allowed(flags.call(args, true)), "%s keeps no record" % str(args))
	assert_false(RushRecords.allowed(flags.call(["--rush"], false)), "another tuning file keeps no record")
	_tuning.fixed_seed = 9
	assert_false(RushRecords.allowed(flags.call(["--rush"], true)), "a fixed seed in tuning keeps no record")


## No "Fight 0": before the first fight is entered the pause note and the Rush end leave the fight out.
func test_reached_text_waits_for_the_first_fight() -> void:
	var r := _rush_state()
	assert_eq(r.reached(), 0)
	assert_eq(r.reached_text(), "", "no fight entered yet")
	r.next_fight()
	assert_eq(r.reached_text(), "Fight 1")
	assert_eq(RushState.begin_rush(_rush, _tuning, 7, null, 5).reached_text(), "Fight 4", "a head start's fights count")
	var source := FileAccess.get_file_as_string(MAIN_PATH)
	var start := source.find("func _open_pause(")
	var body := source.substr(start, source.find("\nfunc ", start + 1) - start)
	assert_string_contains(body, "_pause.note = (_run as RushState).reached_text()")
	assert_false(body.contains("maxi(1"), "the pause note never says Fight 1 before it")


func test_records_in_settings() -> void:
	_settings_before = PlayerSettings._config
	PlayerSettings._config = ConfigFile.new()
	PlayerSettings.set_persistence(false)
	assert_eq(PlayerSettings.rush_best(1), {})
	assert_eq(PlayerSettings.rush_best_any(), 0)
	assert_true(PlayerSettings.set_rush_best(1, RushRecords.entry(9, "2026-10-23")))
	assert_false(PlayerSettings.set_rush_best(1, RushRecords.entry(7, "2026-10-24")), "a lower fight is not kept")
	assert_true(PlayerSettings.set_rush_best(1, RushRecords.entry(12, "2026-10-24")))
	assert_true(PlayerSettings.set_rush_best(2, RushRecords.entry(16, "2026-10-24")))
	assert_eq(PlayerSettings.rush_best(1), RushRecords.entry(12, "2026-10-24"))
	assert_eq(PlayerSettings.rush_best(2).fight, 16)
	assert_eq(PlayerSettings.rush_best(3), {})
	assert_eq(PlayerSettings.rush_best_any(), 16)
	PlayerSettings._config.set_value(PlayerSettings.SECTION_RUSH, "best_3", {"fight": "x"})
	assert_eq(PlayerSettings.rush_best(3), {}, "a damaged record reads as none")
	PlayerSettings.reset_rush_records()
	assert_eq(PlayerSettings.rush_best(1), {})
	assert_eq(PlayerSettings.rush_best_any(), 0)
	PlayerSettings.reset_rush_records()
	PlayerSettings._config = _settings_before
	PlayerSettings.set_persistence(true)


func test_rush_salts_differ_from_every_run_salt() -> void:
	var run_consts: Dictionary = (load("res://scripts/run/run_state.gd") as Script).get_script_constant_map()
	var salts: Array[int] = [RushState.RUSH_FIGHT_SALT, RushState.RUSH_LOOK_SALT, RushState.RUSH_OFFER_SALT,
			RushState.RUSH_WEATHER_SALT]
	var run_salts: Array[int] = []
	for key: String in run_consts:
		if key.ends_with("_SALT"):
			run_salts.append(int(run_consts[key]))
	assert_gt(run_salts.size(), 15, "RunState's salts were found")
	for salt: int in salts:
		assert_false(run_salts.has(salt), "%d is not a RunState salt" % salt)
		assert_eq(salts.count(salt), 1)


func test_cards_never_offer_keys_treasure_curses_or_gold() -> void:
	var loose := _build_rush(true)
	var kinds := {}
	for item: ItemData in loose.items:
		kinds[item.kind] = true
	assert_true(kinds.has(ItemData.Kind.KEY) and kinds.has(ItemData.Kind.TREASURE), "the loose list has keys and treasure")
	var r := RushState.begin_rush(loose, _tuning, 3)
	var items := 0
	var relics := 0
	for k: int in 50:
		r.fight = k + 1
		r.first_pick_no = r.pick_no
		r.roll_offer()
		for card: Dictionary in r.offer:
			if card.kind == "item":
				items += 1
				var item := r._rush_item(String(card.id))
				assert_true(item.kind == ItemData.Kind.CONSUMABLE or item.kind == ItemData.Kind.UPGRADE, item.id)
				assert_false(item.rotten, item.id)
			elif card.kind == "relic":
				relics += 1
				var gear := r.relic_by_id(String(card.id))
				assert_ne(gear.effect, GearData.Effect.GOLD, gear.id)
				assert_false(gear.rot_touched, "no rot-touched Relic on a card")
		r.pick_no += 1
	assert_gt(items, 10)
	assert_gt(relics, 10)
	# Every Relic at its top level but the gold ones: a boss offers Train alone.
	for item: GearData in _data.gear:
		if item != null and item.effect != GearData.Effect.GOLD:
			r.relics[item.id] = _tuning.relic_max_level
	r.fight = 10
	r.first_pick_no = r.pick_no
	r.roll_offer()
	assert_eq(_kinds(r), ["point"])


func test_built_data_validates_and_bad_data_does_not() -> void:
	assert_eq(_rush.validate(), PackedStringArray())
	var bad := RushData.new()
	assert_gt(bad.validate().size(), 2, "no run, tiers or bosses")
	var loose := _build_rush(true)
	assert_false(loose.validate().is_empty(), "keys and treasure on the item list")
	var late := _build_rush(false)
	late.tiers[0].from_fight = 2
	assert_false(late.validate().is_empty(), "the first tier must start at fight 1")
	var guard := _build_rush(false)
	guard.tiers[1].fights.append(_enc("guard_mire_mother"))
	assert_false(guard.validate().is_empty(), "a guard is no tier fight")


## The Rush's dev and bot switches (DESIGN.md 8.21): --rush-start and --rush-fights imply --rush,
## and stay in range.
func test_rush_switches_parse() -> void:
	var plain := CombatOptions.from_args(PackedStringArray([]), null)
	assert_false(plain.rush, "no Rush by default")
	assert_eq(plain.rush_start, 1)
	assert_eq(plain.rush_fights, 0, "no cap by default")
	assert_true(CombatOptions.from_args(PackedStringArray(["--rush"]), null).rush)
	var start := CombatOptions.from_args(PackedStringArray(["--rush-start=0"]), null)
	assert_true(start.rush, "--rush-start implies --rush")
	assert_eq(start.rush_start, 1, "the first fight is at least 1")
	assert_eq(CombatOptions.from_args(PackedStringArray(["--rush-start=21"]), null).rush_start, 21)
	var capped := CombatOptions.from_args(PackedStringArray(["--rush-fights=5"]), null)
	assert_true(capped.rush, "--rush-fights implies --rush")
	assert_eq(capped.rush_fights, 5)
	assert_eq(capped.rush_start, 1)
	assert_eq(CombatOptions.from_args(PackedStringArray(["--rush-fights=-3"]), null).rush_fights, 0, "never below 0")


## Every Fight Rush dev screen (--screen=rush_*) is wired in Main's dev screen list.
func test_rush_dev_screens_are_wired() -> void:
	var source := FileAccess.get_file_as_string(MAIN_PATH)
	var start := source.find("func _open_dev_screen(")
	var body := source.substr(start, source.find("\nfunc ", start + 1) - start)
	for screen: String in ["rush_cards", "rush_players", "rush_reward", "rush_reward_elite", "rush_ready", "rush_end",
			"rush_pause"]:
		assert_string_contains(body, "\"%s\"" % screen)


func test_unspent_points_and_players() -> void:
	var r := _rush_state()
	assert_eq(r.unspent_points(), 0)
	r.bonus_points[0] += 2
	assert_eq(r.unspent_points(), 2)
	r.note_players(5)
	assert_eq(r.most_players, 3)
	r.note_players(1)
	assert_eq(r.most_players, 3, "the most seen stays")
