extends GutTest
## The oath ladder (DESIGN.md 8.15, card #173): modifier sums, the rules each oath changes inside a
## run, the unlock rule and the run state's round trip. Uses the shipped run and tuning. Nothing
## here reads or writes the real settings file.

const RUN_PATH := "res://data/runs/rotten_road.tres"
const TUNING_PATH := "res://data/tuning/tuning.tres"

var _data: RunData
var _tuning: Tuning


func before_all() -> void:
	_data = load(RUN_PATH) as RunData
	_tuning = load(TUNING_PATH) as Tuning


func _run(oath: int, seed_value: int = 7) -> RunState:
	return RunState.begin(_data, _tuning, seed_value, oath)


## A run on a made-up ladder (`ladder` oaths, a copy of tuning with `start_gold`).
func _run_with(ladder: Array[OathData], oath: int, start_gold: int = 0) -> RunState:
	var data := _data.duplicate() as RunData
	data.oaths = ladder
	var tuning := _tuning.duplicate() as Tuning
	tuning.run_start_gold = start_gold
	return RunState.begin(data, tuning, 7, oath)


func _oath(fields: Dictionary) -> OathData:
	var oath := OathData.new()
	for key: String in fields:
		oath.set(key, fields[key])
	return oath


## A stop of the first act's map in map row `row`.
func _stop_in_row(run: RunState, row: int) -> int:
	for stop: Dictionary in run.map.stops:
		if int(stop.row) == row:
			return int(stop.id)
	return -1


# --- the data and the sums ------------------------------------------------------------------------

func test_the_shipped_ladder_has_twelve_oaths_in_order() -> void:
	assert_eq(_data.oaths.size(), 12)
	var ids := {}
	for oath: OathData in _data.oaths:
		assert_not_null(oath)
		assert_false(oath.title.is_empty())
		assert_false(oath.description.is_empty())
		assert_false(ids.has(oath.id), "%s is unique" % oath.id)
		ids[oath.id] = true
	assert_eq(_data.oaths[0].title, "Oath of Thorns")
	assert_eq(_data.oaths[9].title, "Oath of Rot")
	# The top of the ladder bites into the heroes (DESIGN.md 8.15, 8.24: no Relic slots or Echoes now).
	assert_eq(_data.oaths[10].start_relics_add, -1, "Oath 11, the Empty Hand: one starting Relic fewer per hero")
	assert_eq(_data.oaths[11].attr_points_per_level_add, -1, "Oath 12, Forgetting: one attribute point fewer per level")


func test_the_empty_hand_takes_the_starting_relics_and_forgetting_a_point_per_level() -> void:
	var c := RelicCollection.new()
	c.merge(["coffin_lid", "whetstone", "war_drum"])
	var ten := RunState.begin(_data, _tuning, 7, 10, c)
	assert_eq(ten.start_relic_count(), 1, "Oath 10: each hero takes one from the book (#328)")
	assert_true(ten.start_pending())
	var eleven := RunState.begin(_data, _tuning, 7, 11, c)
	assert_eq(eleven.start_relic_count(), 0, "Oath 11: one fewer for each hero, none at all")
	assert_false(eleven.start_pending(), "so the pick step is skipped")
	assert_true(eleven.relics.is_empty())
	var plain := _run(11)
	var forgetting := _run(12)
	for run: RunState in [plain, forgetting]:
		run.add_xp(0, run.tuning.run_xp_first_level)
	assert_eq(plain.levels[0], 2)
	assert_eq(forgetting.levels[0], 2)
	assert_eq(plain.earned_points(0), _tuning.attr_start_points + _tuning.attr_points_per_level)
	assert_eq(forgetting.earned_points(0), _tuning.attr_start_points + _tuning.attr_points_per_level - 1,
			"a point fewer per level up")
	var ladder: Array[OathData] = [_oath({"attr_points_per_level_add": -99})]
	var none := _run_with(ladder, 1)
	none.add_xp(0, none.tuning.run_xp_first_level)
	assert_eq(none.earned_points(0), _tuning.attr_start_points, "never fewer than none")


func test_modifiers_add_up_over_oaths_one_to_n() -> void:
	assert_eq(OathData.total(_data.oaths, 0, &"elite_hp_percent_add"), 0, "no oath: no change")
	assert_eq(OathData.total(_data.oaths, 1, &"elite_hp_percent_add"), 20)
	assert_eq(OathData.total(_data.oaths, 10, &"elite_hp_percent_add"), 20)
	assert_eq(OathData.total(_data.oaths, 2, &"shop_price_percent_add"), 15)
	assert_eq(OathData.total(_data.oaths, 1, &"shop_price_percent_add"), 0, "Want is oath 2")
	assert_eq(OathData.total(_data.oaths, 3, &"rest_heal_percent_add"), -15)
	assert_eq(OathData.total(_data.oaths, 99, &"enemy_power_percent_add"), 10, "past the ladder: the whole ladder")
	assert_eq(OathData.total(_data.oaths, -4, &"enemy_power_percent_add"), 0)
	var ladder: Array[OathData] = [_oath({"loot_choices_add": -1}), _oath({"loot_choices_add": -2})]
	assert_eq(OathData.total(ladder, 2, &"loot_choices_add"), -3, "oaths stack")


func test_start_hp_takes_the_lowest_oath() -> void:
	assert_eq(OathData.start_hp_for(_data.oaths, 5), 100)
	assert_eq(OathData.start_hp_for(_data.oaths, 6), 75)
	assert_eq(OathData.start_hp_for(_data.oaths, 10), 75)
	var ladder: Array[OathData] = [_oath({"start_hp_percent": 80}), _oath({"start_hp_percent": 90})]
	assert_eq(OathData.start_hp_for(ladder, 2), 80, "the lowest counts, not the last")


func test_rule_lines_list_the_newest_first() -> void:
	assert_eq(OathData.rule_lines(_data.oaths, 0).size(), 0)
	var lines := OathData.rule_lines(_data.oaths, 3)
	assert_eq(lines.size(), 3)
	assert_true(lines[0].begins_with("3  Oath of Embers"))
	assert_true(lines[2].begins_with("1  Oath of Thorns"))


# --- inside a run ---------------------------------------------------------------------------------

func test_a_run_keeps_its_oath_inside_the_ladder() -> void:
	assert_eq(_run(0).oath, 0)
	assert_eq(_run(4).oath, 4)
	assert_eq(_run(99).oath, 12, "capped at the ladder")
	assert_eq(_run(-3).oath, 0)


func test_fight_setup_at_oath_zero_is_the_plain_game() -> void:
	var plain := _run(0)
	var elite := plain.act_data().elites[0]
	var setup := plain.fight_setup(elite, 1, CombatSetup.Opening.NORMAL)
	assert_eq(setup.enemy_hp_percent, CombatMath.percent(plain.enemy_hp_percent(), _tuning.elite_hp_percent))
	# Phase 17: the run's base enemy power (tuning enemy_power_base_percent) comes last.
	assert_eq(setup.enemy_power_percent, CombatMath.percent(CombatMath.percent(plain.enemy_power_percent(),
			_tuning.elite_power_percent), _tuning.enemy_power_base_percent))


func test_oath_ten_makes_every_kind_of_fight_harder() -> void:
	var plain := _run(0)
	var hard := _run(10)
	var normal := load("res://data/encounters/fly_fight.tres") as EncounterData
	var elite := plain.act_data().elites[0]
	var guard := load("res://data/encounters/guard_gorged_one.tres") as EncounterData
	var boss := plain.final_encounter()
	assert_true(guard.mini_boss and boss.boss and elite.elite)
	# A plain enemy: only Rot's +10% power.
	var base := _tuning.enemy_power_base_percent
	var a := plain.fight_setup(normal, 1, CombatSetup.Opening.NORMAL)
	var b := hard.fight_setup(normal, 1, CombatSetup.Opening.NORMAL)
	assert_eq(b.enemy_hp_percent, a.enemy_hp_percent, "HP is untouched")
	assert_eq(b.enemy_power_percent, CombatMath.percent(CombatMath.percent(plain.enemy_power_percent(), 110), base))
	# An elite: Thorns (+20 HP, +10 power points on the elite numbers) and Rot.
	a = plain.fight_setup(elite, 1, CombatSetup.Opening.NORMAL)
	b = hard.fight_setup(elite, 1, CombatSetup.Opening.NORMAL)
	assert_eq(b.enemy_hp_percent, CombatMath.percent(plain.enemy_hp_percent(), _tuning.elite_hp_percent + 20))
	assert_eq(b.enemy_power_percent, CombatMath.percent(CombatMath.percent(
			CombatMath.percent(plain.enemy_power_percent(), _tuning.elite_power_percent + 10), 110), base))
	assert_gt(b.enemy_hp_percent, a.enemy_hp_percent)
	# A guard counts as a boss: Crowns (+15% HP, +10% power) and Rot.
	a = plain.fight_setup(guard, 1, CombatSetup.Opening.NORMAL)
	b = hard.fight_setup(guard, 1, CombatSetup.Opening.NORMAL)
	assert_eq(b.enemy_hp_percent, CombatMath.percent(a.enemy_hp_percent, 115))
	assert_eq(b.enemy_power_percent, CombatMath.percent(CombatMath.percent(CombatMath.percent(
			plain.enemy_power_percent(), 110), 110), base))
	# An act boss too.
	a = plain.fight_setup(boss, 1, CombatSetup.Opening.NORMAL)
	b = hard.fight_setup(boss, 1, CombatSetup.Opening.NORMAL)
	assert_eq(b.enemy_hp_percent, CombatMath.percent(a.enemy_hp_percent, 115))
	assert_gt(b.enemy_power_percent, a.enemy_power_percent)


func test_each_oath_changes_only_its_own_rule() -> void:
	var normal := load("res://data/encounters/fly_fight.tres") as EncounterData
	var plain := _run(0).fight_setup(normal, 1, CombatSetup.Opening.NORMAL)
	# Oaths 1 to 9 never change a plain enemy's power; oath 10 does.
	var at_nine := _run(9).fight_setup(normal, 1, CombatSetup.Opening.NORMAL)
	assert_eq(at_nine.enemy_power_percent, plain.enemy_power_percent)
	assert_gt(_run(10).fight_setup(normal, 1, CombatSetup.Opening.NORMAL).enemy_power_percent, plain.enemy_power_percent)


func test_enemies_grow_faster_per_row_from_oath_four() -> void:
	var row := 3
	for oath: int in [0, 3, 4]:
		var run := _run(oath)
		run.at = _stop_in_row(run, row)
		assert_gte(run.at, 0)
		var extra_hp := 2 if oath >= 4 else 0
		var extra_power := 1 if oath >= 4 else 0
		assert_eq(run.enemy_hp_percent(), 100 + row * (_tuning.run_enemy_hp_row_percent + extra_hp), "oath %d" % oath)
		assert_eq(run.enemy_power_percent(), 100 + row * (_tuning.run_enemy_power_row_percent + extra_power))


func test_rest_heals_less_from_oath_three() -> void:
	for oath: int in [0, 2, 3]:
		var run := _run(oath)
		for slot: int in run.party_size():
			run.hp[slot] = 1
		var expected_percent := _tuning.run_rest_heal_percent - (15 if oath >= 3 else 0)
		assert_eq(run.rest_heal_percent(), expected_percent)
		var healed := run.rest()
		for slot: int in run.party_size():
			assert_eq(healed[slot], CombatMath.percent(run.max_hp(slot), expected_percent), "oath %d" % oath)


func test_the_heal_between_acts_is_smaller_from_oath_nine() -> void:
	for oath: int in [0, 9]:
		var run := _run(oath)
		for slot: int in run.party_size():
			run.hp[slot] = 1
		var expected_percent := _tuning.run_act_heal_percent - (25 if oath >= 9 else 0)
		assert_eq(run.act_heal_percent(), expected_percent)
		assert_true(run.next_act())
		for slot: int in run.party_size():
			assert_eq(run.hp[slot], 1 + CombatMath.percent(run.max_hp(slot), expected_percent), "oath %d" % oath)


func test_start_gold_oath_can_take_gold_but_never_below_nothing() -> void:
	var ladder: Array[OathData] = [_oath({"start_gold_add": -30})]
	assert_eq(_run_with(ladder, 0, 50).gold, 50, "no oath: the normal gold")
	assert_eq(_run_with(ladder, 1, 50).gold, 20)
	assert_eq(_run_with(ladder, 1, 10).gold, 0, "never negative")
	assert_eq(_run(_data.oaths.size()).gold, _tuning.run_start_gold, "no shipped oath touches the starting purse (no start_gold_add)")


func test_want_cuts_the_gold_fights_pay() -> void:
	var husk := load("res://data/encounters/husk_fight.tres") as EncounterData
	var base := RunState.encounter_gold(husk)
	assert_gt(base, 0)
	assert_eq(_run(0).gold_for(husk), base, "no oath: full pay")
	assert_eq(_run(1).gold_for(husk), base, "Thorns leaves the pay alone")
	assert_eq(_run(2).gold_for(husk), CombatMath.percent(base, 75), "Want: 25% less")
	assert_lt(_run(2).gold_for(husk), base)
	assert_eq(OathData.total(_data.oaths, 2, &"gold_percent_add"), -25)


func test_gold_cut_never_goes_below_nothing() -> void:
	var husk := load("res://data/encounters/husk_fight.tres") as EncounterData
	var ladder: Array[OathData] = [_oath({"gold_percent_add": -150})]
	assert_eq(_run_with(ladder, 1).gold_for(husk), 0)
	var two: Array[OathData] = [_oath({"gold_percent_add": -10}), _oath({"gold_percent_add": -15})]
	assert_eq(_run_with(two, 2).gold_for(husk), CombatMath.percent(RunState.encounter_gold(husk), 75), "oaths stack")


func test_the_party_starts_hurt_from_oath_six() -> void:
	var full := _run(5)
	var hurt := _run(6)
	for slot: int in full.party_size():
		assert_eq(full.hp[slot], full.max_hp(slot))
		assert_eq(hurt.hp[slot], CombatMath.percent(hurt.max_hp(slot), 75))
	var ladder: Array[OathData] = [_oath({"start_hp_percent": 1})]
	for hp: int in _run_with(ladder, 1).hp:
		assert_gte(hp, 1, "never dead on arrival")


func test_spoils_offer_one_choice_fewer_from_oath_seven_and_never_none() -> void:
	assert_eq(_run(6).loot_choice_count(), _tuning.run_loot_choices)
	assert_eq(_run(7).loot_choice_count(), _tuning.run_loot_choices - 1)
	var run := _run(7)
	assert_lte(run.loot_choices(_stop_in_row(run, 2)).size(), _tuning.run_loot_choices - 1)
	var ladder: Array[OathData] = [_oath({"loot_choices_add": -20})]
	var harsh := _run_with(ladder, 1)
	assert_eq(harsh.loot_choice_count(), 1, "floor of one")
	assert_eq(harsh.loot_choices(_stop_in_row(harsh, 2)).size(), 1)


func test_shops_charge_more_from_oath_two_but_pay_the_same_for_selling() -> void:
	var item := _data.shop_items[0]
	var plain := _run(0)
	var want := _run(2)
	assert_eq(plain.item_price(item), item.price)
	assert_eq(want.item_price(item), CombatMath.percent(item.price, 115))
	assert_eq(want.sell_price(item.price), plain.sell_price(item.price), "selling is unchanged")
	want.gold = item.price
	assert_false(want.can_afford(item), "the old price no longer buys it")
	want.gold = want.item_price(item)
	assert_true(want.pay_for(item))
	assert_eq(want.gold, 0)
	var gear := _data.gear[0]
	assert_eq(want.gear_price(gear), CombatMath.percent(gear.price, 115))
	want.gold = want.gear_price(gear) - 1
	assert_false(want.can_buy_gear(gear))
	want.gold = want.gear_price(gear)
	assert_false(want.buy_gear(gear, 0).is_empty(), "a bought Relic goes to a hero")
	assert_eq(want.relics_of(0), [gear] as Array[GearData])
	assert_eq(want.gold, 0)
	# The services cost more too.
	want.gold = _tuning.shop_restock_price
	assert_false(want.restock(), "the plain price is not enough")
	want.gold = want.restock_price()
	assert_true(want.restock())
	assert_eq(want.cleanse_price(), CombatMath.percent(_tuning.shop_cleanse_price, 115))


func test_only_half_the_team_gauge_carries_from_oath_eight() -> void:
	var plain := _run(0)
	plain.carry_team_gauge(80)
	assert_eq(plain.team_gauge, CombatMath.percent(80, _tuning.run_team_gauge_carry_percent))
	var silent := _run(8)
	silent.carry_team_gauge(80)
	assert_eq(silent.team_gauge, CombatMath.percent(80, _tuning.run_team_gauge_carry_percent - 50))
	assert_lt(silent.team_gauge, plain.team_gauge)


# --- saving the state -----------------------------------------------------------------------------

func test_the_oath_survives_the_online_round_trip() -> void:
	var host := _run(6)
	host.gold = 33
	var copy := RunState.from_dict(_data, _tuning, host.to_dict())
	assert_not_null(copy)
	assert_eq(copy.oath, 6)
	assert_eq(copy.gold, 33)
	assert_eq(copy.hp, host.hp)
	assert_eq(copy.to_dict(), host.to_dict())


func test_a_bad_oath_is_refused() -> void:
	var good := _run(3).to_dict()
	for bad: Variant in [-1, 13, "3", 2.5, null]:
		var d := good.duplicate(true)
		d["oath"] = bad
		assert_null(RunState.from_dict(_data, _tuning, d), "oath %s" % str(bad))
	var missing := good.duplicate(true)
	missing.erase("oath")
	assert_null(RunState.from_dict(_data, _tuning, missing), "the oath key is required")
	var client := _run(0)
	assert_true(client.apply_dict(good))
	assert_eq(client.oath, 3, "a client takes the host's oath")


# --- the unlock rule and the command line ---------------------------------------------------------

func test_winning_unlocks_the_next_oath_and_never_lowers() -> void:
	assert_eq(PlayerSettings.oath_after_win(0, 0, 10), 1, "a plain win opens Oath 1")
	assert_eq(PlayerSettings.oath_after_win(1, 1, 10), 2)
	assert_eq(PlayerSettings.oath_after_win(5, 2, 10), 5, "an easier win never lowers it")
	assert_eq(PlayerSettings.oath_after_win(3, 3, 10), 4)
	assert_eq(PlayerSettings.oath_after_win(10, 10, 10), 10, "capped at the ladder")
	assert_eq(PlayerSettings.oath_after_win(9, 9, 10), 10)
	assert_eq(PlayerSettings.oath_after_win(0, 0, 0), 0, "no ladder: nothing to unlock")


func test_the_unlock_reads_zero_without_a_saved_value() -> void:
	var kept: ConfigFile = PlayerSettings._config
	PlayerSettings._config = ConfigFile.new()
	assert_eq(PlayerSettings.highest_oath_unlocked(), 0)
	PlayerSettings._config.set_value(PlayerSettings.SECTION_GAME, PlayerSettings.KEY_OATH_UNLOCKED, -4)
	assert_eq(PlayerSettings.highest_oath_unlocked(), 0, "never negative, even if the file was edited")
	PlayerSettings._config.set_value(PlayerSettings.SECTION_GAME, PlayerSettings.KEY_OATH_UNLOCKED, 4)
	assert_eq(PlayerSettings.highest_oath_unlocked(), 4)
	PlayerSettings._config = kept


func test_oath_switch_is_read_from_the_command_line() -> void:
	assert_eq(CombatOptions.from_args(PackedStringArray(["--run"]), null).oath, -1, "none given")
	assert_eq(CombatOptions.from_args(PackedStringArray(["--run", "--oath=7"]), null).oath, 7)
	assert_eq(CombatOptions.from_args(PackedStringArray(["--oath=0"]), null).oath, 0)


# --- the players screen ---------------------------------------------------------------------------

func _names() -> Array[String]:
	var names: Array[String] = []
	for c: CharacterData in _data.party:
		names.append(c.display_name)
	return names


func _portraits() -> Array[String]:
	var paths: Array[String] = []
	for c: CharacterData in _data.party:
		paths.append(c.big_portrait_path)
	return paths


func test_the_players_screen_picks_up_to_the_unlocked_oath() -> void:
	var lobby := LobbyScreen.new()
	lobby.hero_portraits = _portraits()
	lobby.oaths = _data.oaths
	lobby.oath_unlocked = 3
	lobby.setup(_names(), null, PlayerRoster.KEYBOARD)
	add_child_autofree(lobby)
	assert_eq(lobby.oath(), 0)
	for i: int in 5:
		lobby._step_oath(1, false)
	assert_eq(lobby.oath(), 3, "stops at the highest unlocked oath")
	lobby._step_oath(1, true)
	assert_eq(lobby.oath(), 0, "Confirm on the top wraps back to none")
	lobby._step_oath(-1, false)
	assert_eq(lobby.oath(), 0, "never below none")
	assert_eq(lobby._start_row(), _names().size() + 1, "Start comes after the Oath row")


func test_a_players_screen_without_oaths_is_as_before() -> void:
	var lobby := LobbyScreen.new()
	lobby.hero_portraits = _portraits()
	lobby.setup(_names(), null, PlayerRoster.KEYBOARD)
	add_child_autofree(lobby)
	assert_eq(lobby._oath_row(), -1)
	assert_eq(lobby._start_row(), _names().size())
	assert_eq(lobby.oath(), 0)


func test_a_waiting_client_shows_the_hosts_oath_but_cannot_change_it() -> void:
	var lobby := LobbyScreen.new()
	lobby.hero_portraits = _portraits()
	lobby.oaths = _data.oaths
	lobby.oath_unlocked = 12
	var roster := PlayerRoster.online(_names().size(), NetSession.HOST_PEER, 2)
	lobby.setup_online(_names(), roster, false, [] as Array[String], 7777)
	add_child_autofree(lobby)
	lobby.set_oath(6)
	assert_eq(lobby.oath(), 6)
	lobby._step_oath(1, false)
	assert_eq(lobby.oath(), 6, "only the host picks")
	lobby.set_oath(99)
	assert_eq(lobby.oath(), 12, "kept inside the ladder")
