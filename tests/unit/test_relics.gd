extends GutTest
## Relics and Echoes (DESIGN.md 8.17, 8.19): the shipped Relics' data and drops, the collection kept
## forever and its file (found Relics, Echo pips, the bag that grows with Echoes learned), Relic levels
## that last one run, slots that open during a run, the stat lines, Echo pips filled across runs and
## Echoes learned for good, Echo points, one hero per Echo, the oaths that bite into them, saving and
## online ops, the run's base enemy power, and the bot. Never touches the player's real files.

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


## A collection that found `ids`, with `pips` (id -> pips) and `bag` in it (as many as fit in 10).
func _collection(ids: Array, pips: Dictionary = {}, bag: Array = []) -> RelicCollection:
	var c := RelicCollection.new()
	c.merge(ids, pips)
	for id: Variant in bag:
		c.toggle_bag(String(id), 10)
	return c


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
	assert_eq(_data.gear.size(), 50, "the 25 gear pieces, 6 from the old charms' ideas, 3 against marks (card #263), 16 more (card #242)")
	for id: String in ["heartleaf", "wake_root", "ember_stone", "rain_pouch", "black_ichor", "gravebloom"]:
		assert_true(_relic(id).description.length() > 0, "%s: a Relic made from a charm idea" % id)
	assert_true(_relic("black_ichor").rot_touched and _relic("gravebloom").rot_touched, "the rotten ones keep their price")
	for item: GearData in _data.gear:
		assert_gt(item.stat_points, 0, "%s has a stat line" % item.id)
		assert_between(item.echo_cost, 1, 4, "%s's Echo costs 1 to 4 points" % item.id)
		assert_true(dropped.has(item.id), "some monster drops %s" % item.id)
	assert_eq(_relic("echo_charm").display_name, "Rebound Charm", "no Relic is called Echo anything")


func test_echo_costs_go_by_strength() -> void:
	# Phase 21 (#280): a learned Echo can be worn in any run, so strong effects cost more points.
	for id: String in ["fox_step", "wake_root"]:
		assert_eq(_relic(id).echo_cost, 3, "%s: AP on every dodge or parry" % id)
	assert_eq(_relic("oathbreakers_band").echo_cost, 4, "+2 AP at the start of every fight")
	for id: String in ["iron_charm", "whetstone", "thick_hide", "quick_boots", "war_drum"]:
		assert_eq(_relic(id).echo_cost, 2, "%s: a big all-round effect" % id)
	for id: String in ["lucky_coin", "rain_pouch", "mossbed", "first_light", "bitter_root"]:
		assert_eq(_relic(id).echo_cost, 1, "%s: a small or narrow effect" % id)


func test_the_stat_line_grows_one_point_per_level() -> void:
	var crown := _relic("rotten_crown")
	assert_eq(crown.stat_points_at(1), crown.stat_points)
	assert_eq(crown.stat_points_at(3), crown.stat_points + 2 * crown.stat_points_per_level)
	assert_eq(crown.stat_text(1), "Might +%d" % crown.stat_points)
	var plain := GearData.new()
	assert_eq(plain.stat_points_at(4), 0, "no stat line")
	assert_eq(plain.stat_text(4), "")


func test_relic_levels_last_one_run_and_pips_teach_an_echo() -> void:
	assert_eq(_tuning.relic_max_level, 3, "levels last one run, up to 3 (#280)")
	assert_eq(_tuning.mastery_needed, 12, "12 pips, about one act, learn an Echo for good")
	assert_eq([_tuning.relic_bag_start, _tuning.relic_bag_echoes_per_slot, _tuning.relic_bag_max], [3, 5, 6],
			"the bag starts at 3 and grows by 1 every 5 Echoes learned, up to 6 (#266)")


# --- the collection and its file ------------------------------------------------------------------

func test_the_collection_keeps_finds_and_the_higher_pips_so_banking_twice_adds_nothing() -> void:
	var c := RelicCollection.new()
	assert_true(c.merge(["iron_charm", "whetstone"], {"iron_charm": 5}))
	assert_false(c.merge(["iron_charm", "whetstone"], {"iron_charm": 5}), "the same run banked again changes nothing")
	assert_false(c.merge([], {"iron_charm": 3}), "fewer pips never take any away")
	assert_true(c.merge([], {"iron_charm": 7}))
	assert_eq(c.pips_of("iron_charm"), 7)
	assert_false(c.is_learned("iron_charm", 12))
	assert_false(c.merge([], {"war_drum": 5}), "pips of a Relic never found are ignored")
	assert_eq(c.pips_of("war_drum"), 0)
	assert_true(c.merge([], {"iron_charm": 99}, _tuning))
	assert_eq(c.pips_of("iron_charm"), _tuning.mastery_needed, "never past the pips needed")
	assert_true(c.is_learned("iron_charm", _tuning.mastery_needed))
	assert_eq(c.learned_count(_tuning.mastery_needed), 1)
	assert_eq(c.count(), 2)


func test_the_bag_holds_found_relics_once_up_to_its_size() -> void:
	var c := _collection(["iron_charm", "whetstone", "war_drum", "keen_eye"])
	assert_true(c.toggle_bag("iron_charm", 3))
	assert_false(c.toggle_bag("nope", 3), "not found: cannot go in")
	assert_true(c.toggle_bag("whetstone", 3))
	assert_true(c.toggle_bag("war_drum", 3))
	assert_false(c.toggle_bag("keen_eye", 3), "the bag is full")
	assert_eq(c.bag_ids(), ["iron_charm", "whetstone", "war_drum"] as Array[String])
	assert_true(c.toggle_bag("whetstone", 3), "Confirm again takes it out")
	assert_false(c.in_bag("whetstone"))
	assert_true(c.toggle_bag("keen_eye", 3), "room again")
	assert_eq(c.bag_ids(), ["iron_charm", "war_drum", "keen_eye"] as Array[String])


func test_new_relics_join_the_bag_while_it_has_room() -> void:
	var c := RelicCollection.new()
	c.merge(["iron_charm", "whetstone"], {}, _tuning)
	assert_eq(c.bag_ids(), ["iron_charm", "whetstone"] as Array[String], "first finds go in (user pick)")
	c.toggle_bag("whetstone", 3)
	c.merge(["whetstone", "war_drum", "keen_eye"], {}, _tuning)
	assert_eq(c.bag_ids(), ["iron_charm", "war_drum", "keen_eye"] as Array[String],
			"a Relic taken out stays out; new ones fill the room")
	c.merge(["rot_hunter"], {}, _tuning)
	assert_false(c.in_bag("rot_hunter"), "a full bag takes no more")
	c.merge(["lucky_coin"], {})
	assert_false(c.in_bag("lucky_coin"), "no tuning: never")


func test_the_bag_grows_with_the_echoes_learned() -> void:
	var c := RelicCollection.new()
	var ids: Array = []
	for item: GearData in _data.gear:
		ids.append(item.id)
	c.merge(ids, {})
	assert_eq(c.bag_size(_tuning), 3, "3 to start")
	var needed := _tuning.mastery_needed
	for count: int in [4, 5, 9, 10, 15, 30]:
		var pips := {}
		for i: int in count:
			pips[ids[i]] = needed
		c.merge([], pips)
		assert_eq(c.bag_size(_tuning), mini(6, 3 + count / 5), "%d Echoes learned" % count)
	for id: String in ids.slice(0, 6):
		assert_true(c.toggle_bag(id, c.bag_size(_tuning)))
	assert_false(c.trim_bag(6), "a bag that fits is left alone")
	assert_true(c.trim_bag(3), "a bag from before the bag shrank keeps its first Relics")
	assert_eq(c.bag_ids(), [ids[0], ids[1], ids[2]] as Array[String])


func test_a_bot_fills_its_bag_best_first() -> void:
	var c := RelicCollection.all_of(_data.gear, _tuning.mastery_needed)
	assert_eq(c.learned_count(_tuning.mastery_needed), _data.gear.size(), "--relics=all learns every Echo")
	c.fill_bag(_data.gear, 4, GearBot.score)
	var ids := c.bag_ids()
	assert_eq(ids.size(), 4)
	for id: String in ids:
		assert_gte(GearBot.score(_relic(id)), 0, id + " is a Relic the bot would wear")
	var best := 0
	for item: GearData in _data.gear:
		best = maxi(best, GearBot.score(item))
	assert_eq(GearBot.score(_relic(ids[0])), best, "the best first")


func test_a_collection_survives_its_dictionary_and_skips_junk() -> void:
	var c := _collection(["iron_charm", "whetstone"], {"iron_charm": 4}, ["iron_charm"])
	var copy := RelicCollection.from_dict(c.to_dict())
	assert_eq(copy.to_dict(), c.to_dict())
	var junk := RelicCollection.from_dict({"found": ["a", 3, "c"], "pips": {"a": -1, "c": 2.0, "x": 5, 4: 1},
			"bag": ["a", "c", 5, "c"]})
	assert_eq(junk.found_ids(), ["a", "c"] as Array[String], "only sound entries are kept")
	assert_eq(junk.pips, {"c": 2})
	assert_eq(junk.bag_ids(), ["a", "c"] as Array[String])
	assert_eq(RelicCollection.from_dict({}).count(), 0)


func test_a_collection_from_before_phase_21_turns_its_levels_into_pips() -> void:
	var old := RelicCollection.from_dict({"levels": {"a": 1, "b": 5, "c": 3, "d": -1, "e": "x"}, "bag": ["c", "d"]})
	assert_eq(old.found_ids(), ["a", "b", "c"] as Array[String], "every Relic it held is found")
	assert_eq(old.pips, {"b": 12, "c": 6}, "3 pips per level above 1: the old top level is learned")
	assert_true(old.is_learned("b", _tuning.mastery_needed))
	assert_eq(old.bag_ids(), ["c"] as Array[String])
	# A file from before the bag: each hero's picks go into it, heroes in order.
	var older := RelicCollection.from_dict({"levels": {"a": 1, "b": 1, "c": 1},
			"picks": {"alder": ["b", "x"], "brin": ["a"]}})
	assert_eq(older.bag_ids(), ["b", "a"] as Array[String])


func test_the_file_saves_loads_banks_and_deletes() -> void:
	assert_eq(String(RelicFile.load_collection(TEST_FILE).status), RelicFile.MISSING)
	assert_true(RelicFile.bank(["iron_charm"], {}, TEST_FILE), "a first find is written")
	assert_false(RelicFile.bank(["iron_charm"], {}, TEST_FILE), "nothing new: nothing written")
	assert_true(RelicFile.bank(["iron_charm", "whetstone"], {"iron_charm": 4}, TEST_FILE))
	var loaded := RelicFile.load_collection(TEST_FILE)
	assert_eq(String(loaded.status), RelicFile.LOADED)
	var got := loaded.collection as RelicCollection
	assert_eq(got.found_ids(), ["iron_charm", "whetstone"] as Array[String])
	assert_eq(got.pips, {"iron_charm": 4})
	# A damaged main file falls back to the backup (the file before the last write).
	var file := FileAccess.open(TEST_FILE, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	assert_eq(RelicFile.load_or_empty(TEST_FILE).found_ids(), ["iron_charm"] as Array[String],
			"the backup is the previous good file")
	RelicFile.delete(TEST_FILE)
	assert_false(RelicFile.exists(TEST_FILE))
	assert_eq(RelicFile.load_or_empty(TEST_FILE).count(), 0)


func test_a_file_of_format_one_loads_and_is_written_back_as_the_new_one() -> void:
	var file := FileAccess.open(TEST_FILE, FileAccess.WRITE)
	file.store_string(JSON.stringify({"format": 1, "relics": {"levels": {"iron_charm": 5, "whetstone": 2},
			"bag": ["whetstone"]}}))
	file.close()
	var loaded := RelicFile.load_collection(TEST_FILE)
	assert_eq(String(loaded.status), RelicFile.LOADED, "a phase 17 to 20 file is not lost")
	var c := loaded.collection as RelicCollection
	assert_true(c.is_learned("iron_charm", _tuning.mastery_needed), "level 5 became a learned Echo")
	assert_eq(c.pips_of("whetstone"), 3)
	assert_eq(c.bag_ids(), ["whetstone"] as Array[String])
	assert_true(RelicFile.bank(["war_drum"], {}, TEST_FILE))
	var body: Variant = JSON.parse_string(FileAccess.get_file_as_string(TEST_FILE))
	assert_eq(int((body as Dictionary).format), RelicCollection.FORMAT_VERSION, "written back in the new format")
	assert_eq(RelicFile.load_or_empty(TEST_FILE).pips_of("iron_charm"), 12, "nothing lost on the way")


func test_a_file_of_another_version_is_kept_and_never_written_over() -> void:
	var file := FileAccess.open(TEST_FILE, FileAccess.WRITE)
	file.store_string(JSON.stringify({"format": RelicCollection.FORMAT_VERSION + 1, "relics": {}}))
	file.close()
	var loaded := RelicFile.load_collection(TEST_FILE)
	assert_eq(String(loaded.status), RelicFile.REJECTED)
	assert_true(bool(loaded.keep))
	assert_false(RelicFile.bank(["iron_charm"], {}, TEST_FILE))


# --- a run with a collection ----------------------------------------------------------------------

func test_a_run_takes_only_the_bag_at_level_one_and_wears_nothing_yet() -> void:
	var c := _collection(["iron_charm", "whetstone", "war_drum", "keen_eye", "not_a_relic"], {"iron_charm": 6},
			["whetstone", "iron_charm", "not_a_relic"])
	var run := _run(7, c)
	assert_eq(run.relics, {"whetstone": 1, "iron_charm": 1}, "the bag's Relics this run knows, at level 1")
	assert_eq(run.relics_at_start, {"iron_charm": 1, "whetstone": 1, "war_drum": 1, "keen_eye": 1},
			"everything found is remembered")
	assert_eq(run.pips_at_start, {"iron_charm": 6}, "and the pips")
	assert_eq(run.mastery_of(_relic("iron_charm")), 6)
	assert_eq(run.open_relic_slots(), 1, "one slot at the start")
	for slot: int in run.party_size():
		assert_null(run.gear[slot][0], "nothing goes on by itself (card #265)")
	assert_eq(run.wear(2, 0, _relic("war_drum"), true), -1, "a Relic left at home cannot be worn")
	assert_eq(run.wear(2, 0, _relic("whetstone"), true), 0, "any hero wears any Relic from the bag")
	assert_eq(run.hp[0], run.max_hp(0))
	assert_true(run.mastery.is_empty(), "no pips earned yet this run")
	assert_eq(run.learned_echoes().size(), 0)


func test_the_bag_brings_only_as_many_as_it_holds() -> void:
	var ids: Array = []
	for i: int in 8:
		ids.append(_data.gear[i].id)
	var c := _collection(ids, {}, ids)
	assert_eq(c.bag_ids().size(), 8, "an old bag of 10")
	var run := _run(7, c)
	assert_eq(run.relics.size(), 3, "a run takes what the bag holds now (#266)")


func test_a_relic_left_at_home_joins_the_run_at_level_one() -> void:
	var c := _collection(["iron_charm", "whetstone"], {"iron_charm": 6}, ["whetstone"])
	var run := _run(7, c)
	var charm := _relic("iron_charm")
	assert_true(run.is_home(charm))
	var info := run.add_relic(charm)
	assert_false(bool(info.new), "not new: it was found before")
	assert_true(bool(info.home))
	assert_eq(int(info.level), 1, "it joins at level 1, its home pips are untouched")
	assert_eq(RunState.relic_find_short(info), "Home")
	assert_eq(RunState.relic_find_text(info), "Found: Iron Charm")
	assert_eq(run.relic_level(charm), 1)
	assert_false(run.is_home(charm))
	assert_eq(run.mastery_of(charm), 6)
	assert_eq(int(run.add_relic(charm).level), 2, "a copy now raises it this run")
	assert_false(run.relic_gain_line().contains("New Relics"))


func test_the_bot_fills_open_slots() -> void:
	var c := RelicCollection.new()
	c.merge(["iron_charm", "whetstone", "war_drum"], {}, _tuning)
	var run := _run(7, c)
	assert_eq(run.auto_wear(), 3, "one open slot per hero")
	assert_eq(run.auto_wear(), 0, "nothing left to fill")
	run.add_relic(_relic("keen_eye"))
	assert_eq(run.unworn_relics().size(), 1)


## The second slot opens after the first Elite stop won (DESIGN.md 8.22); a guard won anywhere still
## counts (a map rules 3 Guard stop, the Rush), so these wins over the Gorged One open it too.
func test_slots_open_after_the_first_elite_stop_and_act_one() -> void:
	var c := RelicCollection.new()
	c.merge(["iron_charm", "whetstone", "war_drum"], {}, _tuning)
	var run := _run(7, c)
	assert_eq(run.wear(1, 0, _relic("iron_charm")), 0)
	assert_eq(run.gear[1][0], _relic("iron_charm"))
	assert_eq(run.wear(1, 1, _relic("whetstone")), -1, "a shut slot takes nothing")
	assert_eq(run.slot_lock_text(1), "Opens after the first Elite stop.")
	assert_eq(run.slot_lock_text(2), "Opens after act 1's boss.")
	assert_eq(run.free_gear_slot(1), -1)
	_win(run, _husk())
	assert_eq(run.open_relic_slots(), 1, "an ordinary fight opens nothing")
	assert_true(run.win_relic_lines(_guard()).has("A Relic slot opens: Y to put a Relic on"), "the end screen says so")
	_win(run, _guard())
	assert_eq(run.open_relic_slots(), 2, "the first guard opens the second slot")
	assert_null(run.gear[1][1], "it stays empty until the player fills it")
	assert_eq(run.wear(1, 1, _relic("whetstone")), 0)
	assert_false(run.win_relic_lines(_guard()).has("A Relic slot opens: Y to put a Relic on"), "only the first guard")
	_win(run, _guard())
	assert_eq(run.open_relic_slots(), 2, "only the first guard counts")
	run.next_act()
	assert_eq(run.open_relic_slots(), 3, "act 1's boss opens the third")
	assert_null(run.gear[1][2])
	assert_eq(run.slot_lock_text(2), "")


func test_the_empty_hand_oath_shuts_a_slot_but_never_the_last_one() -> void:
	var run := _run(7, null, 11)
	assert_eq(run.oath_total(&"relic_slots_add"), -1)
	assert_eq(run.open_relic_slots(), 1, "never under one")
	assert_eq(run.slot_lock_text(1), "Opens after act 1's boss.", "the first Elite stop opens nothing under this oath")
	assert_eq(run.slot_lock_text(2), "Shut by your oath.")
	run.elite_stops_won = 1
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
	assert_true(run.can_gain(coin))
	run.add_relic(coin)
	assert_eq(run.relic_level(coin), 3, "the top level")
	var gold := run.gold
	var spare := run.add_relic(coin)
	assert_eq(run.gold, gold + run.tuning.relic_spare_gold, "a copy past the top level is gold")
	assert_eq(int(spare.gold), run.tuning.relic_spare_gold)
	assert_false(run.can_gain(coin))


func test_spoils_never_run_dry_for_a_full_collection() -> void:
	var run := _run(7, RelicCollection.all_of(_data.gear, _tuning.mastery_needed))
	run.go(run.choices()[0])
	assert_eq(run.loot_choices(run.at).size(), run.loot_choice_count(),
			"every Relic found before is still worth a pick: levels last one run")


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


func test_the_end_screen_line_names_new_relics_and_echoes_learned() -> void:
	var c := _collection(["whetstone", "war_drum"], {"war_drum": _tuning.mastery_needed})
	var run := _run(7, c)
	assert_eq(run.relic_gain_line(), "Nothing new to keep.", "an Echo learned before this run is not news")
	run.add_relic(_relic("whetstone"))
	run.add_relic(_relic("iron_charm"))
	assert_eq(run.relic_gain_line(), "New Relics: Iron Charm", "a Relic found before is not news either")
	run.mastery["iron_charm"] = run.tuning.mastery_needed
	assert_eq(run.relic_gain_line(), "New Relics: Iron Charm   Echoes learned: Iron Charm")
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


# --- Echo pips and Echoes -------------------------------------------------------------------------

func test_wins_fill_a_worn_relics_pips_bigger_fights_faster() -> void:
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
	assert_true(run.win_relic_lines(_husk()).has("Echo learned for good: War Drum"))
	var got := _win(run, _husk())
	assert_eq(got.echoes, [drum] as Array[GearData])
	assert_true(run.echo_learned(drum))
	assert_eq(run.learned_echoes(), [drum] as Array[GearData])
	_win(run, _guard())
	assert_eq(run.mastery_of(drum), run.tuning.mastery_needed, "never past the pips needed")
	var guarded := _run()
	guarded.wear(0, 0, drum)
	_win(guarded, _guard())
	for i: int in guarded.tuning.mastery_needed - guarded.tuning.mastery_guard:
		_win(guarded, _husk())
	assert_true(guarded.echo_learned(drum), "a guard counts for three fights")


func test_pips_carry_from_run_to_run_and_a_learned_echo_needs_no_relic() -> void:
	var needed := _tuning.mastery_needed
	var c := RelicCollection.new()
	var first := _run(7, c)
	var drum := _relic("war_drum")
	first.add_relic(drum)
	first.wear(0, 0, drum)
	for i: int in 5:
		_win(first, _husk())
	assert_eq(first.pips_totals(), {"war_drum": 5})
	assert_true(c.merge(first.relics.keys(), first.pips_totals(), _tuning), "Main banks the run")
	assert_false(c.merge(first.relics.keys(), first.pips_totals(), _tuning), "banking twice adds nothing")
	assert_true(c.in_bag("war_drum"), "a first find joins the bag")
	c.bag.clear()
	var second := _run(8, c)
	assert_eq(second.mastery_of(drum), 5, "the pips are still there, even with the War Drum at home")
	assert_false(second.owns(drum))
	second.add_relic(drum)
	second.wear(1, 0, drum)
	for i: int in needed - 5:
		_win(second, _husk())
	assert_true(second.echo_learned(drum))
	assert_eq(second.echoes_learned_this_run(), [drum] as Array[GearData])
	c.merge(second.relics.keys(), second.pips_totals(), _tuning)
	assert_true(c.is_learned("war_drum", needed))
	c.bag.clear()
	var third := _run(9, c)
	assert_false(third.owns(drum), "the War Drum stays at home")
	assert_eq(third.learned_echoes(), [drum] as Array[GearData], "its Echo is learned for good")
	assert_true(third.echoes_learned_this_run().is_empty())
	assert_ne(third.echo_blocked_reason(0, drum), "", "but every run starts with 0 Echo points")
	third.add_xp(0, 400)
	assert_true(third.set_echo(0, drum, true), "a learned Echo goes on without its Relic (option A)")
	assert_eq(int(third.passives(0).get(Passive.START_AP, 0)), drum.amount)


func test_an_online_friend_banks_this_runs_pips_on_top_of_their_own() -> void:
	# Card #281: the run plays with the host's collection; a friend keeps what it finds and fills.
	var run := _run(7, _collection(["war_drum"], {"war_drum": _tuning.mastery_needed}))
	var drum := _relic("war_drum")
	run.add_relic(drum)
	run.wear(0, 0, drum)
	for i: int in 4:
		_win(run, _husk())
	assert_eq(run.mastery_of(drum), _tuning.mastery_needed, "the host had learned it already")
	assert_eq(run.mastery[drum.id], 4, "this run's pips are kept whole all the same")
	assert_eq(run.pips_totals_from({"war_drum": 5}), {"war_drum": 9}, "a friend gets them on top of their own")
	assert_eq(run.pips_totals_from({}), {"war_drum": 4})
	var friend := _collection(["iron_charm"], {"iron_charm": 3})
	assert_eq(run.relic_gain_line_since(friend.found, friend.pips), "New Relics: War Drum",
			"the friend's end screen: new to them, though the host had it")
	assert_eq(run.relic_gain_line_since({"war_drum": true}, {"war_drum": 8}), "Echoes learned: War Drum")
	assert_true(friend.merge(run.relics.keys(), run.pips_totals_from(friend.pips), _tuning))
	assert_eq(friend.pips_of("war_drum"), 4)
	assert_eq(friend.pips_of("iron_charm"), 3, "what the friend had stays")


func test_a_late_joiner_keeps_only_what_came_after() -> void:
	# Card #304: a friend who dropped in mid-run banks only the Relics and pips found after they joined.
	var run := _run()
	run.tuning.relic_drop_percent = 0
	var drum := _relic("war_drum")
	run.add_relic(drum)
	run.wear(0, 0, drum)
	for i: int in 2:
		_win(run, _husk())
	var relics_before := run.relics.duplicate()
	var mastery_before := run.mastery.duplicate()
	run.add_relic(_relic("iron_charm"))
	for i: int in 2:
		_win(run, _husk())
	assert_eq(run.relic_ids_since(relics_before), ["iron_charm"], "only the Relic found after the join")
	var every := run.relic_ids_since({})
	every.sort()
	var keys := run.relics.keys()
	keys.sort()
	assert_eq(every, keys, "empty: every Relic the run has")
	assert_eq(int(run.pips_totals_since({}, mastery_before)["war_drum"]), 2, "only the later pips")
	assert_eq(int(run.pips_totals_since({"war_drum": 5}, mastery_before)["war_drum"]), 7, "on top of their own")
	for start: Dictionary in [{}, {"war_drum": 5}, {"iron_charm": 3}]:
		assert_eq(run.pips_totals_since(start, {}), run.pips_totals_from(start), "empty: the whole run's")
	var friend := _collection(["ash_veil"], {"ash_veil": 3})
	var since := {"relics": relics_before, "mastery": mastery_before}
	var shown: Array = []
	for entry: Dictionary in RunEndScreen.own_kept(run, friend, since):
		shown.append((entry.item as GearData).id)
	assert_eq(shown, ["iron_charm"], "the late find is theirs, the earlier one is not (the Kept row)")
	var near := _collection(["war_drum", "iron_charm"], {"war_drum": _tuning.mastery_needed - 3})
	var echoes := func(kept: Array[Dictionary]) -> Array:
		var ids: Array = []
		for entry: Dictionary in kept:
			if bool(entry.echo):
				ids.append((entry.item as GearData).id)
		return ids
	assert_eq(echoes.call(RunEndScreen.own_kept(run, near)), ["war_drum"], "there from the start, 4 pips fill it")
	assert_eq(echoes.call(RunEndScreen.own_kept(run, near, since)), [], "joined late, the 2 pips since do not")
	assert_true(friend.merge(run.relic_ids_since(relics_before), run.pips_totals_since(friend.pips, mastery_before), _tuning))
	assert_true(friend.owns("iron_charm"))
	assert_false(friend.owns("war_drum"), "nothing found before they joined is banked")
	assert_eq(friend.pips_of("war_drum"), 0)
	assert_eq(friend.pips_of("ash_veil"), 3, "what the friend had stays")


func test_one_hero_per_echo() -> void:
	var run := _run()
	var drum := _relic("war_drum")
	run.mastery[drum.id] = run.tuning.mastery_needed
	for slot: int in run.party_size():
		run.add_xp(slot, 400)
	assert_true(run.set_echo(0, drum, true))
	assert_eq(run.echo_wearer(drum), 0)
	assert_eq(run.echo_blocked_reason(1, drum), "Alder wears this Echo.")
	assert_false(run.set_echo(1, drum, true), "an Echo cannot sit on the whole party")
	assert_true(run.set_echo(0, drum, false))
	assert_true(run.set_echo(1, drum, true), "free again once it comes off")
	run.add_relic(drum)
	assert_eq(run.wear(2, 0, drum), 0, "another hero may still wear the Relic itself")
	assert_true(run.wears_echo(1, drum))


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
	for id: String in ["ember_stone", "war_drum", "rotten_crown"]:
		run.mastery[id] = run.tuning.mastery_needed
	run.auto_echoes(0)
	assert_true(run.wears_echo(0, _relic("ember_stone")), "the cheap one first")
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
	assert_has(run.win_relic_lines(_guard()), "A Relic slot opens: Y to put a Relic on")
	assert_eq(run.elite_stops_won, 0, "the preview changes nothing")
	_win(run, _guard())
	assert_does_not_have(run.win_relic_lines(_guard()), "A Relic slot opens: Y to put a Relic on")


# --- saving and online ----------------------------------------------------------------------------

func test_the_relic_state_survives_a_save_and_the_network() -> void:
	var c := RelicCollection.new()
	c.merge(["war_drum", "iron_charm"], {"war_drum": 4}, _tuning)
	var run := _run(7, c)
	run.wear(0, 0, _relic("war_drum"))
	_win(run, _guard())
	run.wear(0, 1, _relic("iron_charm"))
	run.mastery["war_drum"] = run.tuning.mastery_needed - 4
	run.add_xp(1, 400)
	run.set_echo(1, _relic("war_drum"), true)
	var data := run.to_dict()
	assert_eq(Fx.find_illegal_value(data), "", "only plain values go over the network")
	var copy := RunState.from_dict(_data, run.tuning, data)
	assert_not_null(copy)
	assert_eq(copy.to_dict(), data)
	assert_eq(copy.relics, run.relics)
	assert_eq(copy.pips_at_start, {"war_drum": 4}, "the host's pips go to every machine")
	assert_eq(copy.gear[0][1], _relic("iron_charm"))
	assert_true(copy.wears_echo(1, _relic("war_drum")))
	assert_eq(copy.passives(1), run.passives(1))


func test_a_save_from_before_relics_keeps_what_it_wears() -> void:
	var run := _run()
	run.wear(0, 0, _relic("whetstone"))
	var old := run.to_dict()
	for key: String in ["relics", "relic_picks", "guards_beaten", "mastery", "echoes", "pips_start"]:
		old.erase(key)
	var copy := RunState.from_dict(_data, run.tuning, old)
	assert_not_null(copy, "an older save still loads (card #208)")
	assert_eq(copy.relics, {"whetstone": 1}, "what it wore joins the run at level 1")
	assert_eq(copy.gear[0][0], _relic("whetstone"))
	assert_eq(copy.open_relic_slots(), 2, "a party that wore gear had beaten a guard")


func test_a_save_from_before_phase_21_keeps_its_echoes() -> void:
	var run := _run()
	run.add_relic(_relic("whetstone"))
	run.wear(0, 0, _relic("whetstone"))
	var old := run.to_dict()
	old.erase("pips_start")
	old["relics"] = {"whetstone": 5}
	old["relics_start"] = {"whetstone": 4}
	old["mastery"] = {"whetstone": 4, "war_drum": 2}
	var copy := RunState.from_dict(_data, run.tuning, old)
	assert_not_null(copy, "a run saved before phase 21 still loads")
	assert_eq(copy.relics, {"whetstone": 3}, "its level is cut to the new top level")
	assert_eq(copy.relics_at_start, {"whetstone": 1})
	assert_true(copy.echo_learned(_relic("whetstone")), "an Echo it had learned stays learned (4 of the old 4)")
	assert_eq(copy.mastery_of(_relic("war_drum")), 6, "half way stays half way")


func test_bad_relic_state_is_refused() -> void:
	var run := _run()
	run.wear(0, 0, _relic("whetstone"))
	var good := run.to_dict()
	var cases := [
		["relics", {"whetstone": 0}], ["relics", {"nope": 1}], ["relics", {}],
		["mastery", {"nope": 2}], ["mastery", {"whetstone": -1}], ["guards_beaten", -1], ["guards_beaten", "1"],
		["echoes", [["nope"], [], []]], ["echoes", [[], []]],
		["pips_start", {"nope": 1}], ["pips_start", {"whetstone": -1}], ["pips_start", []],
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

func test_the_relics_page_fills_the_bag_from_the_collection() -> void:
	var c := _collection(["iron_charm", "whetstone", "war_drum", "keen_eye"], {"iron_charm": 5})
	var screen := RelicsScreen.new()
	add_child_autofree(screen)
	screen.setup(c, _data.gear, _data.party, _tuning, [] as Array[EnemyData])
	var changes: Array = []
	screen.bag_changed.connect(func(changed: RelicCollection) -> void: changes.append(changed))
	for id: String in ["iron_charm", "whetstone", "war_drum"]:
		assert_true(screen.put(_relic(id)))
	assert_eq(c.bag_ids(), ["iron_charm", "whetstone", "war_drum"] as Array[String])
	assert_eq(changes.size(), 3, "each change is saved")
	assert_false(screen.put(_relic("keen_eye")), "the bag of 3 is full")
	assert_true(screen.put(_relic("whetstone")), "Confirm on a bagged Relic takes it out")
	assert_true(screen.put(_relic("keen_eye")))
	assert_eq(c.bag_ids(), ["iron_charm", "war_drum", "keen_eye"] as Array[String])
	assert_false(screen.put(_relic("rotten_crown")), "not found yet: cannot be brought")


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


func test_the_relics_tab_puts_a_relic_from_the_bag_on_a_slot() -> void:
	var run := _run()
	run.add_relic(_relic("iron_charm"))
	run.add_relic(_relic("whetstone"))
	var screen := PartyScreen.new()
	add_child_autofree(screen)
	screen.setup(run)
	screen.open_relics(0, 0)
	assert_eq(screen.current_tab(), PartyScreen.Tab.RELICS)
	var tab := screen.tab_node(PartyScreen.Tab.RELICS) as RelicsTab
	assert_true(tab.put(_relic("whetstone")))
	assert_eq(run.gear[0][0], _relic("whetstone"))
	tab.focus_slot(0, 0, true)
	assert_true(tab.put(_relic("iron_charm")), "the same slot takes another")
	assert_eq(run.gear[0][0], _relic("iron_charm"))
	assert_false(run.is_worn(_relic("whetstone")), "the old one goes back to the bag")
	tab.focus_slot(1, 0, true)
	assert_true(tab.put(_relic("iron_charm")), "one another hero wears swaps over")
	assert_eq(run.gear[1][0], _relic("iron_charm"))
	assert_null(run.gear[0][0])
	tab.focus_slot(0, 1)
	assert_false(tab.open_bag(), "a locked slot opens nothing")
	assert_eq(String(tab.info().title), "Locked")


# --- harder runs ----------------------------------------------------------------------------------

func test_run_fights_get_the_base_enemy_power_and_practice_keeps_the_data() -> void:
	var run := _run()
	var husk := _husk()
	var setup := run.fight_setup(husk, 1, CombatSetup.Opening.NORMAL)
	assert_eq(_tuning.enemy_power_base_percent, 105, "phase 17: a little harder")
	assert_eq(setup.enemy_power_percent, CombatMath.percent(run.enemy_power_percent(), _tuning.enemy_power_base_percent))
	var practice := CombatSetup.from_encounter(husk, _tuning, 1, CombatSetup.Opening.NORMAL)
	assert_lt(practice.enemy_power_percent, setup.enemy_power_percent, "practice fights are as in the data")
