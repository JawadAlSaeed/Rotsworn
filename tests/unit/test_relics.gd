extends GutTest
## Relics and Echoes (DESIGN.md 8.17, phase 17): the shipped Relics' data and drops, the collection
## kept forever and its file, Relic levels, slots that open during a run, the stat lines, mastery
## and Echoes learned per run, Echo points, the oaths that bite into them, saving and online ops,
## the run's base enemy power, and the bot. Never touches the player's real files.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")

const RUN_PATH := "res://data/runs/rotten_road.tres"
const TEST_FILE := "user://test_progress.json"

var _data: RunData
var _tuning: Tuning


func before_all() -> void:
	_data = load(RUN_PATH) as RunData
	_tuning = load("res://data/tuning/tuning.tres") as Tuning


func after_each() -> void:
	RelicFile.delete(TEST_FILE)


func _run(seed_value: int = 7, collection: RelicCollection = null, oath: int = 0) -> RunState:
	return RunState.begin(_data, _tuning.duplicate(true) as Tuning, seed_value, oath, collection)


func _relic(id: String) -> GearData:
	for item: GearData in _data.gear:
		if item.id == id:
			return item
	fail_test("the shipped run has the Relic %s" % id)
	return GearData.new()


func _husk() -> EncounterData:
	return load("res://data/encounters/husk_fight.tres") as EncounterData


func _guard() -> EncounterData:
	return load("res://data/encounters/guard_gorged_one.tres") as EncounterData


## Wins `encounter` with the party's HP as it is.
func _win(run: RunState, encounter: EncounterData) -> Dictionary:
	return run.finish_fight(RunState.VICTORY, run.hp.duplicate(), encounter)


# --- the shipped data -----------------------------------------------------------------------------

func test_every_relic_has_a_stat_line_an_echo_cost_and_a_monster_that_drops_it() -> void:
	var dropped := {}
	for file: String in DirAccess.get_files_at("res://data/enemies"):
		if not file.ends_with(".tres"):
			continue
		var enemy := load("res://data/enemies".path_join(file)) as EnemyData
		for item: GearData in enemy.relic_drops:
			assert_not_null(item, "%s drops a real Relic" % enemy.id)
			if item != null:
				assert_true(_data.gear.has(item), "%s's %s is one of the run's Relics" % [enemy.id, item.id])
				dropped[item.id] = true
	assert_eq(_data.gear.size(), 31, "the 25 gear pieces and 6 from the old charms' ideas")
	for id: String in ["heartleaf", "wake_root", "ember_stone", "rain_pouch", "black_ichor", "gravebloom"]:
		assert_true(_relic(id).description.length() > 0, "%s: a Relic made from a charm idea" % id)
	assert_true(_relic("black_ichor").rot_touched and _relic("gravebloom").rot_touched, "the rotten ones keep their price")
	for item: GearData in _data.gear:
		assert_gt(item.stat_points, 0, "%s has a stat line" % item.id)
		assert_between(item.echo_cost, 1, 3, "%s's Echo costs 1 to 3 points" % item.id)
		assert_true(dropped.has(item.id), "some monster drops %s" % item.id)
	assert_eq(_relic("echo_charm").display_name, "Rebound Charm", "no Relic is called Echo anything")


func test_rarer_relics_cost_more_echo_points() -> void:
	for item: GearData in _data.gear:
		assert_eq(item.echo_cost, int(item.rarity) + 1, "%s: common 1, rare 2, legendary 3" % item.id)


func test_the_stat_line_grows_one_point_per_level() -> void:
	var crown := _relic("rotten_crown")
	assert_eq(crown.stat_points_at(1), crown.stat_points)
	assert_eq(crown.stat_points_at(3), crown.stat_points + 2 * crown.stat_points_per_level)
	assert_eq(crown.stat_text(1), "Might +%d" % crown.stat_points)
	var plain := GearData.new()
	assert_eq(plain.stat_points_at(4), 0, "no stat line")
	assert_eq(plain.stat_text(4), "")


# --- the collection and its file ------------------------------------------------------------------

func test_the_collection_keeps_the_higher_level_so_banking_twice_adds_nothing() -> void:
	var c := RelicCollection.new()
	assert_true(c.merge({"iron_charm": 2, "whetstone": 1}))
	assert_false(c.merge({"iron_charm": 2, "whetstone": 1}), "the same run banked again changes nothing")
	assert_false(c.merge({"iron_charm": 1}), "a lower level never takes one away")
	assert_true(c.merge({"iron_charm": 3}))
	assert_eq(c.level_of("iron_charm"), 3)
	assert_eq(c.level_of("war_drum"), 0)
	assert_eq(c.count(), 2)


func test_picks_are_found_relics_each_brought_by_one_hero() -> void:
	var c := RelicCollection.new()
	c.merge({"iron_charm": 1, "whetstone": 1, "war_drum": 1, "keen_eye": 1})
	c.set_picks("alder", ["iron_charm", "nope", "iron_charm", "whetstone", "war_drum", "keen_eye"] as Array[String], 3)
	assert_eq(c.picks_for("alder"), ["iron_charm", "whetstone", "war_drum"] as Array[String], "found ones, once, at most 3")
	c.set_picks("brin", ["whetstone"] as Array[String], 3)
	assert_eq(c.picks_for("brin"), ["whetstone"] as Array[String])
	assert_eq(c.picks_for("alder"), ["iron_charm", "war_drum"] as Array[String], "moved from Alder to Brin")
	assert_eq(c.picked_by("whetstone"), "brin")
	assert_eq(c.picked_by("keen_eye"), "")


func test_a_collection_survives_its_dictionary_and_skips_junk() -> void:
	var c := RelicCollection.new()
	c.merge({"iron_charm": 2})
	c.set_picks("cass", ["iron_charm"] as Array[String], 3)
	var copy := RelicCollection.from_dict(c.to_dict())
	assert_eq(copy.to_dict(), c.to_dict())
	var junk := RelicCollection.from_dict({"levels": {"a": -1, 3: 2, "b": "x", "c": 2.0}, "picks": {"cass": ["a", "c", 5]}})
	assert_eq(junk.levels, {"c": 2}, "only sound entries are kept")
	assert_eq(junk.picks_for("cass"), ["c"] as Array[String])
	assert_eq(RelicCollection.from_dict({}).count(), 0)


func test_the_file_saves_loads_banks_and_deletes() -> void:
	assert_eq(String(RelicFile.load_collection(TEST_FILE).status), RelicFile.MISSING)
	assert_true(RelicFile.bank({"iron_charm": 1}, TEST_FILE), "a first find is written")
	assert_false(RelicFile.bank({"iron_charm": 1}, TEST_FILE), "nothing new: nothing written")
	assert_true(RelicFile.bank({"iron_charm": 2, "whetstone": 1}, TEST_FILE))
	var loaded := RelicFile.load_collection(TEST_FILE)
	assert_eq(String(loaded.status), RelicFile.LOADED)
	assert_eq((loaded.collection as RelicCollection).levels, {"iron_charm": 2, "whetstone": 1})
	# A damaged main file falls back to the backup (the file before the last write).
	var file := FileAccess.open(TEST_FILE, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	assert_eq((RelicFile.load_or_empty(TEST_FILE)).levels, {"iron_charm": 1}, "the backup is the previous good file")
	RelicFile.delete(TEST_FILE)
	assert_false(RelicFile.exists(TEST_FILE))
	assert_eq(RelicFile.load_or_empty(TEST_FILE).count(), 0)


func test_a_file_of_another_version_is_kept_and_never_written_over() -> void:
	var file := FileAccess.open(TEST_FILE, FileAccess.WRITE)
	file.store_string(JSON.stringify({"format": RelicCollection.FORMAT_VERSION + 1, "relics": {}}))
	file.close()
	var loaded := RelicFile.load_collection(TEST_FILE)
	assert_eq(String(loaded.status), RelicFile.REJECTED)
	assert_true(bool(loaded.keep))
	assert_false(RelicFile.bank({"iron_charm": 1}, TEST_FILE))


# --- a run with a collection ----------------------------------------------------------------------

func test_a_run_takes_the_collection_and_puts_the_first_pick_on() -> void:
	var c := RelicCollection.new()
	c.merge({"iron_charm": 3, "whetstone": 1, "war_drum": 2, "not_a_relic": 1})
	c.set_picks("alder", ["whetstone", "iron_charm", "war_drum"] as Array[String], 3)
	var run := _run(7, c)
	assert_eq(run.relics, {"iron_charm": 3, "whetstone": 1, "war_drum": 2}, "only Relics this run knows")
	assert_eq(run.open_relic_slots(), 1, "one slot at the start")
	assert_eq(run.gear[0][0], _relic("whetstone"), "the first pick goes on")
	assert_null(run.gear[0][1], "the other slots are still shut")
	assert_eq(run.hp[0], run.max_hp(0), "the run starts at full HP with the Relic's stat line counted")
	assert_true(run.mastery.is_empty(), "no Echo carries over")
	assert_eq(run.learned_echoes().size(), 0)


func test_slots_open_after_the_first_guard_and_act_one_and_fill_from_the_picks() -> void:
	var c := RelicCollection.new()
	c.merge({"iron_charm": 1, "whetstone": 1, "war_drum": 1})
	c.set_picks("brin", ["iron_charm", "whetstone", "war_drum"] as Array[String], 3)
	var run := _run(7, c)
	assert_eq(run.gear[1][0], _relic("iron_charm"))
	assert_eq(run.wear(1, 1, _relic("whetstone")), -1, "a shut slot takes nothing")
	assert_eq(run.slot_lock_text(1), "Opens after the first guard.")
	assert_eq(run.slot_lock_text(2), "Opens after act 1's boss.")
	assert_eq(run.free_gear_slot(1), -1)
	_win(run, _husk())
	assert_eq(run.open_relic_slots(), 1, "an ordinary fight opens nothing")
	_win(run, _guard())
	assert_eq(run.open_relic_slots(), 2, "the first guard opens the second slot")
	assert_eq(run.gear[1][1], _relic("whetstone"), "and the next pick goes on")
	_win(run, _guard())
	assert_eq(run.open_relic_slots(), 2, "only the first guard counts")
	run.next_act()
	assert_eq(run.open_relic_slots(), 3, "act 1's boss opens the third")
	assert_eq(run.gear[1][2], _relic("war_drum"))
	assert_eq(run.slot_lock_text(2), "")


func test_the_empty_hand_oath_shuts_a_slot_but_never_the_last_one() -> void:
	var run := _run(7, null, 11)
	assert_eq(run.oath_total(&"relic_slots_add"), -1)
	assert_eq(run.open_relic_slots(), 1, "never under one")
	assert_eq(run.slot_lock_text(1), "Opens after act 1's boss.", "the first guard opens nothing under this oath")
	assert_eq(run.slot_lock_text(2), "Shut by your oath.")
	run.guards_beaten = 1
	assert_eq(run.open_relic_slots(), 1)
	run.act = 1
	assert_eq(run.open_relic_slots(), 2)
	assert_eq(run.slot_lock_text(2), "Shut by your oath.")


func test_a_find_is_new_then_levels_up_then_turns_into_gold() -> void:
	var run := _run()
	var coin := _relic("lucky_coin")
	var first := run.add_relic(coin)
	assert_true(bool(first.new))
	assert_eq(run.relic_level(coin), 1)
	assert_eq(RunState.relic_find_text(first), "New Relic: Lucky Coin")
	var second := run.add_relic(coin)
	assert_false(bool(second.new))
	assert_eq(int(second.level), 2)
	assert_eq(RunState.relic_find_text(second), "Lucky Coin is now level 2")
	run.relics[coin.id] = run.tuning.relic_max_level
	var gold := run.gold
	var spare := run.add_relic(coin)
	assert_eq(run.gold, gold + run.tuning.relic_spare_gold, "a copy past the top level is gold")
	assert_eq(int(spare.gold), run.tuning.relic_spare_gold)
	assert_false(run.can_gain(coin))


func test_a_relic_stat_line_adds_attribute_points_that_grow_with_its_level() -> void:
	var run := _run()
	var drum := _relic("war_drum")
	var power_before := run.power_percent(0)
	assert_eq(run.wear(0, 0, drum), 0)
	assert_eq(run.relic_stat(0, Attributes.Kind.MIGHT), drum.stat_points)
	assert_eq(run.attribute(0, Attributes.Kind.MIGHT), 0, "spent points are not touched")
	assert_eq(run.power_percent(0), power_before + drum.stat_points * run.tuning.attr_might_power_percent)
	run.add_relic(drum)
	assert_eq(run.relic_stat(0, Attributes.Kind.MIGHT), drum.stat_points_at(2), "a copy raises the stat line")
	assert_true(run.passives(0).has(Passive.START_AP), "and the effect is there as before")


func test_the_end_screen_line_names_new_relics_and_level_ups() -> void:
	var c := RelicCollection.new()
	c.merge({"whetstone": 1})
	var run := _run(7, c)
	assert_eq(run.relic_gain_line(), "No new Relics this run.")
	run.add_relic(_relic("whetstone"))
	run.add_relic(_relic("iron_charm"))
	assert_eq(run.relic_gain_line(), "Relics kept forever.  New: Iron Charm   Up a level: Whetstone (Lv 2)")
	var copy := RunState.from_dict(_data, run.tuning, run.to_dict())
	assert_eq(copy.relic_gain_line(), run.relic_gain_line(), "the start survives a save")


func test_a_relic_off_or_unworn_stays_the_runs() -> void:
	var run := _run()
	var charm := _relic("iron_charm")
	run.wear(0, 0, charm)
	assert_true(run.take_off(0, 0))
	assert_true(run.owns(charm))
	assert_eq(run.unworn_relics(), [charm] as Array[GearData])
	assert_eq(run.wear(0, 0, _relic("whetstone"), true), -1, "an op may only wear a Relic the run has")


# --- mastery and Echoes ---------------------------------------------------------------------------

func test_wins_teach_a_worn_relic_its_echo_bigger_fights_faster() -> void:
	var run := _run()
	var drum := _relic("war_drum")
	run.wear(0, 0, drum)
	assert_eq(run.mastery_gain(_husk()), run.tuning.mastery_fight)
	assert_eq(run.mastery_gain(_guard()), run.tuning.mastery_guard)
	assert_eq(run.mastery_gain(run.final_encounter()), run.tuning.mastery_boss)
	assert_eq(run.mastery_gain(run.act_data().elites[0]), run.tuning.mastery_elite)
	for i: int in run.tuning.mastery_needed - 1:
		_win(run, _husk())
	assert_false(run.echo_learned(drum))
	assert_eq(run.fights_to_learn(drum), 1)
	assert_eq(run.echoes_from_win(_husk()), [drum] as Array[GearData], "the end screen knows the next win teaches it")
	var got := _win(run, _husk())
	assert_eq(got.echoes, [drum] as Array[GearData])
	assert_true(run.echo_learned(drum))
	assert_eq(run.learned_echoes(), [drum] as Array[GearData])
	var guarded := _run()
	guarded.wear(0, 0, drum)
	_win(guarded, _guard())
	_win(guarded, _husk())
	assert_true(guarded.echo_learned(drum), "a guard counts for three fights")


func test_only_worn_relics_learn_and_a_lost_fight_teaches_nothing() -> void:
	var run := _run()
	var drum := _relic("war_drum")
	run.add_relic(drum)
	_win(run, run.final_encounter())
	assert_eq(run.mastery_of(drum), 0, "a Relic nobody wears learns nothing")
	run.wear(0, 0, drum)
	run.finish_fight(RunState.ESCAPED, run.hp.duplicate(), _guard())
	assert_eq(run.mastery_of(drum), 0, "running away teaches nothing")


func test_echoes_cost_points_from_levels_and_reach_the_fight() -> void:
	var run := _run()
	var drum := _relic("war_drum")
	run.wear(1, 0, drum)
	run.mastery[drum.id] = run.tuning.mastery_needed
	assert_eq(run.echo_points(0), run.tuning.echo_start_points)
	assert_ne(run.echo_blocked_reason(0, drum), "", "no points at level 1")
	assert_false(run.set_echo(0, drum, true))
	run.add_xp(0, 200)
	assert_gte(run.echo_points(0), drum.echo_cost)
	assert_eq(run.echo_blocked_reason(0, drum), "")
	assert_true(run.set_echo(0, drum, true))
	assert_true(run.wears_echo(0, drum))
	assert_eq(run.echo_points_used(0), drum.echo_cost)
	assert_eq(int(run.passives(0).get(Passive.START_AP, 0)), drum.amount, "Alder gets the War Drum's effect")
	assert_eq(run.relic_stat(0, Attributes.Kind.MIGHT), 0, "but not its stat line")
	assert_true(run.set_echo(0, drum, false))
	assert_false(run.passives(0).has(Passive.START_AP))


func test_an_echo_and_its_relic_on_one_hero_count_once() -> void:
	var run := _run()
	var drum := _relic("war_drum")
	run.add_xp(0, 400)
	run.mastery[drum.id] = run.tuning.mastery_needed
	run.add_relic(drum)
	assert_true(run.set_echo(0, drum, true))
	assert_eq(run.wear(0, 0, drum), 0)
	assert_false(run.wears_echo(0, drum), "putting the Relic on takes its Echo off")
	assert_eq(int(run.passives(0).get(Passive.START_AP, 0)), drum.amount)
	assert_ne(run.echo_blocked_reason(0, drum), "", "a hero wearing the Relic needs no Echo of it")
	assert_ne(run.echo_blocked_reason(0, _relic("iron_charm")), "", "an Echo not learned cannot be worn")


func test_forgetting_halves_echo_points() -> void:
	var plain := _run()
	var oath := _run(7, null, 12)
	for run: RunState in [plain, oath]:
		run.add_xp(0, 400)
	assert_gt(plain.echo_points(0), 0)
	assert_eq(oath.echo_points(0), CombatMath.percent(plain.echo_points(0), 50))


func test_the_bot_wears_the_echoes_it_can_cheapest_first() -> void:
	var run := _run()
	run.add_xp(0, 400)
	for id: String in ["iron_charm", "war_drum", "rotten_crown"]:
		run.add_relic(_relic(id))
		run.mastery[id] = run.tuning.mastery_needed
	run.auto_echoes(0)
	assert_true(run.wears_echo(0, _relic("iron_charm")), "the cheap one first")
	assert_false(run.wears_echo(0, _relic("rotten_crown")), "a price the bot will not pay")
	assert_lte(run.echo_points_used(0), run.echo_points(0))


# --- drops ----------------------------------------------------------------------------------------

func test_drops_are_seeded_and_what_the_end_screen_says_is_what_the_run_gets() -> void:
	var tuning := Fx.all_slots(_tuning)
	tuning.relic_drop_percent = 100
	var run := RunState.begin(_data, tuning, 7)
	run.go(run.choices()[0])
	var husk := _husk()
	assert_eq(run.relic_drops(husk), run.relic_drops(husk), "the same stop and fight drop the same")
	assert_eq(run.relic_drops(husk).size(), husk.enemies.size(), "every enemy drops at 100%")
	var lines := run.win_relic_lines(husk)
	var got := _win(run, husk)
	var texts: Array[String] = []
	for info: Dictionary in got.relics:
		texts.append(RunState.relic_find_text(info))
	assert_eq(texts, lines.slice(0, texts.size()), "the end screen read the same finds")
	for info: Dictionary in got.relics:
		assert_true(run.owns(info.item as GearData))
	tuning.relic_drop_percent = 0
	assert_true(run.relic_drops(husk).is_empty())


func test_the_first_guard_says_a_slot_opens() -> void:
	var run := _run()
	assert_has(run.win_relic_lines(_guard()), "A Relic slot opens")
	assert_eq(run.guards_beaten, 0, "the preview changes nothing")
	_win(run, _guard())
	assert_does_not_have(run.win_relic_lines(_guard()), "A Relic slot opens")


# --- saving and online ----------------------------------------------------------------------------

func test_the_relic_state_survives_a_save_and_the_network() -> void:
	var c := RelicCollection.new()
	c.merge({"war_drum": 2, "iron_charm": 1})
	c.set_picks("alder", ["war_drum", "iron_charm"] as Array[String], 3)
	var run := _run(7, c)
	_win(run, _guard())
	run.mastery["war_drum"] = run.tuning.mastery_needed
	run.add_xp(1, 400)
	run.set_echo(1, _relic("war_drum"), true)
	var data := run.to_dict()
	assert_eq(Fx.find_illegal_value(data), "", "only plain values go over the network")
	var copy := RunState.from_dict(_data, run.tuning, data)
	assert_not_null(copy)
	assert_eq(copy.to_dict(), data)
	assert_eq(copy.relics, run.relics)
	assert_eq(copy.gear[0][1], _relic("iron_charm"))
	assert_true(copy.wears_echo(1, _relic("war_drum")))
	assert_eq(copy.passives(1), run.passives(1))


func test_a_save_from_before_relics_keeps_what_it_wears() -> void:
	var run := _run()
	run.wear(0, 0, _relic("whetstone"))
	var old := run.to_dict()
	for key: String in ["relics", "relic_picks", "guards_beaten", "mastery", "echoes"]:
		old.erase(key)
	var copy := RunState.from_dict(_data, run.tuning, old)
	assert_not_null(copy, "an older save still loads (card #208)")
	assert_eq(copy.relics, {"whetstone": 1}, "what it wore joins the run at level 1")
	assert_eq(copy.gear[0][0], _relic("whetstone"))
	assert_eq(copy.open_relic_slots(), 2, "a party that wore gear had beaten a guard")


func test_bad_relic_state_is_refused() -> void:
	var run := _run()
	run.wear(0, 0, _relic("whetstone"))
	var good := run.to_dict()
	var cases := [
		["relics", {"whetstone": 0}], ["relics", {"nope": 1}], ["relics", {"whetstone": 99}], ["relics", {}],
		["mastery", {"nope": 2}], ["mastery", {"whetstone": -1}], ["guards_beaten", -1], ["guards_beaten", "1"],
		["echoes", [["nope"], [], []]], ["echoes", [[], []]], ["relic_picks", "x"],
	]
	for pair: Array in cases:
		var d := good.duplicate(true)
		d[String(pair[0])] = pair[1]
		assert_null(RunState.from_dict(_data, run.tuning, d), "%s = %s" % [pair[0], str(pair[1])])


func test_relic_and_echo_ops_for_online_play() -> void:
	var run := _run()
	var drum := _relic("war_drum")
	assert_false(run.apply_op({"op": "wear", "slot": 0, "gear_slot": 0, "relic": "war_drum"}), "not the run's yet")
	run.add_relic(drum)
	assert_true(run.apply_op({"op": "wear", "slot": 0, "gear_slot": 0, "relic": "war_drum"}))
	assert_eq(run.gear[0][0], drum)
	assert_false(run.apply_op({"op": "wear", "slot": 1, "gear_slot": 1, "relic": "iron_charm"}), "a shut slot")
	assert_true(run.apply_op({"op": "take_off", "slot": 0, "gear_slot": 0}))
	assert_false(run.apply_op({"op": "take_off", "slot": 0, "gear_slot": 0}), "nothing left")
	run.mastery[drum.id] = run.tuning.mastery_needed
	run.add_xp(2, 400)
	assert_true(run.apply_op({"op": "echo", "slot": 2, "relic": "war_drum", "on": true}))
	assert_true(run.wears_echo(2, drum))
	assert_false(run.apply_op({"op": "echo", "slot": 2, "relic": "war_drum", "on": "yes"}), "malformed")
	assert_true(run.apply_op({"op": "echo", "slot": 2, "relic": "war_drum", "on": false}))


# --- the screens ----------------------------------------------------------------------------------

func test_the_relics_page_fills_a_heros_slots_from_the_collection() -> void:
	var c := RelicCollection.new()
	c.merge({"iron_charm": 2, "whetstone": 1, "war_drum": 1, "keen_eye": 1})
	var screen := RelicsScreen.new()
	add_child_autofree(screen)
	screen.setup(c, _data.gear, _data.party, _tuning, [] as Array[EnemyData])
	var changes: Array = []
	screen.picks_changed.connect(func(changed: RelicCollection) -> void: changes.append(changed))
	var alder := _data.party[0].id
	for slot: int in 3:
		screen.choose_slot(slot)
		assert_true(screen.open_grid())
		assert_true(screen.put(_relic(["iron_charm", "whetstone", "war_drum"][slot])))
	assert_eq(c.picks_for(alder), ["iron_charm", "whetstone", "war_drum"] as Array[String])
	assert_eq(changes.size(), 3, "each change is saved")
	screen.choose_slot(1)
	assert_true(screen.put(_relic("keen_eye")), "a full slot takes the new Relic")
	assert_eq(c.picks_for(alder), ["iron_charm", "keen_eye", "war_drum"] as Array[String])
	screen.choose_slot(0)
	assert_true(screen.take_off())
	assert_eq(c.picks_for(alder), ["keen_eye", "war_drum"] as Array[String], "left home")
	assert_false(screen.put(_relic("rotten_crown")), "not found yet: cannot be brought")
	assert_eq(screen.slot_item(0, 0), _relic("keen_eye"))


func test_the_echoes_screen_puts_an_echo_on_and_off() -> void:
	var run := _run()
	var drum := _relic("war_drum")
	run.wear(1, 0, drum)
	run.mastery[drum.id] = run.tuning.mastery_needed
	run.add_xp(0, 400)
	var screen := EchoesScreen.new()
	add_child_autofree(screen)
	screen.setup(run, 0)
	assert_eq(screen.chosen(), drum, "the learned Echo is listed")
	screen.toggle()
	assert_true(run.wears_echo(0, drum))
	screen.toggle()
	assert_false(run.wears_echo(0, drum))


func test_the_party_screen_opens_the_relics_page_for_a_slot() -> void:
	var run := _run()
	run.add_relic(_relic("iron_charm"))
	run.add_relic(_relic("whetstone"))
	var screen := PartyScreen.new()
	add_child_autofree(screen)
	screen.setup(run)
	screen._confirm_gear()
	assert_not_null(screen._relics, "Confirm on an open slot opens the Relics page")
	assert_true(screen._relics.put(_relic("whetstone")))
	assert_eq(run.gear[0][0], _relic("whetstone"))
	assert_true(screen._relics.put(_relic("iron_charm")), "the same slot takes another")
	assert_eq(run.gear[0][0], _relic("iron_charm"))
	assert_false(run.is_worn(_relic("whetstone")), "the old one goes back to the run's Relics")
	screen._relics.choose_slot(1)
	assert_false(screen._relics.open_grid(), "a locked slot opens nothing")
	screen._relics.close()
	assert_null(screen._relics)
	screen._slot = 1
	screen._confirm_gear()
	assert_null(screen._relics, "a locked slot on the party screen opens nothing either")


# --- harder runs ----------------------------------------------------------------------------------

func test_run_fights_get_the_base_enemy_power_and_practice_keeps_the_data() -> void:
	var run := _run()
	var husk := _husk()
	var setup := run.fight_setup(husk, 1, CombatSetup.Opening.NORMAL)
	assert_eq(_tuning.enemy_power_base_percent, 105, "phase 17: a little harder")
	assert_eq(setup.enemy_power_percent, CombatMath.percent(run.enemy_power_percent(), _tuning.enemy_power_base_percent))
	var practice := CombatSetup.from_encounter(husk, _tuning, 1, CombatSetup.Opening.NORMAL)
	assert_lt(practice.enemy_power_percent, setup.enemy_power_percent, "practice fights are as in the data")
