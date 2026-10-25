extends GutTest
## Relics (DESIGN.md 8.17, 8.24): the shipped Relics' data, the Relic book kept forever and its file
## (the Relics found; no bag since #328), a run's Relics given to its heroes (no slots, no levels, no
## copies), the stat lines, the end screen's line, a late joiner, saving and the online op, the party
## screen's Relics tab, and the run's base enemy power. The starting Relics and the book's page are in
## test_start_relics.gd. Never touches the player's real files.

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
	return RunState.begin(_data, Fx.run_tuning(_tuning), seed_value, oath, collection)


func _relic(id: String) -> GearData:
	for item: GearData in _data.gear:
		if item.id == id:
			return item
	fail_test("the shipped run has the Relic %s" % id)
	return GearData.new()


## A Relic book that found `ids`.
func _collection(ids: Array) -> RelicCollection:
	var c := RelicCollection.new()
	c.merge(ids)
	return c


func _husk() -> EncounterData:
	return load("res://data/encounters/husk_fight.tres") as EncounterData


func _guard() -> EncounterData:
	return load("res://data/encounters/guard_gorged_one.tres") as EncounterData


## Wins `encounter` with the party's HP as it is.
func _win(run: RunState, encounter: EncounterData) -> Dictionary:
	return run.finish_fight(RunState.VICTORY, run.hp.duplicate(), encounter)


func _ids(items: Array) -> Array:
	return items.map(func(item: GearData) -> String: return item.id)


# --- the shipped data -----------------------------------------------------------------------------

func test_every_relic_has_a_stat_line_and_a_monster_kept_as_its_dropper() -> void:
	# Fights drop no Relics since DESIGN.md 8.24, but the monsters' drop lists stay in the data.
	var dropped := {}
	for file: String in DirAccess.get_files_at("res://data/enemies"):
		if not file.ends_with(".tres"):
			continue
		var enemy := load("res://data/enemies".path_join(file)) as EnemyData
		for item: GearData in enemy.relic_drops:
			assert_not_null(item, "%s's drop list holds a real Relic" % enemy.id)
			if item != null:
				assert_true(_data.gear.has(item), "%s's %s is one of the run's Relics" % [enemy.id, item.id])
				dropped[item.id] = true
	assert_eq(_data.gear.size(), 50, "the 25 gear pieces, 6 from the old charms' ideas, 3 against marks (card #263), 16 more (card #242)")
	for id: String in ["heartleaf", "wake_root", "ember_stone", "rain_pouch", "black_ichor", "gravebloom"]:
		assert_true(_relic(id).description.length() > 0, "%s: a Relic made from a charm idea" % id)
	assert_true(_relic("black_ichor").rot_touched and _relic("gravebloom").rot_touched, "the rotten ones keep their price")
	for item: GearData in _data.gear:
		assert_gt(item.stat_points, 0, "%s has a stat line" % item.id)
		assert_null(item.get("echo_cost"), "%s has no Echo cost (no Echoes, 8.24)" % item.id)
		assert_true(dropped.has(item.id), "some monster's list holds %s" % item.id)
	assert_eq(_relic("echo_charm").display_name, "Rebound Charm", "no Relic is called Echo anything")


func test_the_stat_line_is_one_line_with_no_levels() -> void:
	var crown := _relic("rotten_crown")
	assert_eq(crown.stat_text(), "Might +%d" % crown.stat_points)
	assert_null(crown.get("stat_points_per_level"), "no Relic levels")
	assert_eq(GearData.new().stat_text(), "", "no stat line")


func test_the_tuning_has_no_slots_levels_copies_or_echoes() -> void:
	for gone: String in ["run_gear_slots", "relic_slots_start", "relic_bag_echoes_per_slot", "relic_bag_max", "relic_bag_start",
			"relic_max_level", "relic_spare_gold", "relic_drop_percent", "relic_copy_weight_percent",
			"mastery_needed", "mastery_fight", "mastery_elite", "mastery_guard", "mastery_boss",
			"echo_start_points", "echo_points_per_level"]:
		assert_null(_tuning.get(gone), "%s went with DESIGN.md 8.24" % gone)
	assert_eq(_tuning.start_relics_per_hero, 1, "one starting Relic per hero from the book (#328)")


# --- the collection and its file ------------------------------------------------------------------

func test_the_collection_keeps_finds_so_banking_twice_adds_nothing() -> void:
	var c := RelicCollection.new()
	assert_true(c.merge(["iron_charm", "whetstone"]))
	assert_false(c.merge(["iron_charm", "whetstone"]), "the same run banked again changes nothing")
	assert_false(c.merge([]))
	assert_false(c.merge([3, null]), "junk ids are skipped")
	assert_true(c.merge(["war_drum"]))
	assert_eq(c.found_ids(), ["iron_charm", "whetstone", "war_drum"] as Array[String], "in the order found")
	assert_eq(c.count(), 3)


func test_a_collection_survives_its_dictionary_and_skips_junk() -> void:
	var c := _collection(["iron_charm", "whetstone"])
	var copy := RelicCollection.from_dict(c.to_dict())
	assert_eq(copy.to_dict(), c.to_dict())
	assert_eq(c.to_dict().keys(), ["found"], "no Echo pips and no bag kept any more (#328)")
	var junk := RelicCollection.from_dict({"found": ["a", 3, "c"], "pips": {"a": 4, "c": 12},
			"bag": ["a", "c", 5, "c", "x"]})
	assert_eq(junk.found_ids(), ["a", "c"] as Array[String], "only sound entries are kept")
	assert_false(junk.to_dict().has("pips"), "an old file's pips are dropped")
	assert_false(junk.to_dict().has("bag"), "and so is its bag")
	assert_eq(RelicCollection.from_dict({}).count(), 0)


func test_a_collection_from_before_phase_21_keeps_every_relic_it_held() -> void:
	var old := RelicCollection.from_dict({"levels": {"a": 1, "b": 5, "c": 3, "d": -1, "e": "x"}, "bag": ["c", "d"]})
	assert_eq(old.found_ids(), ["a", "b", "c"] as Array[String], "every Relic it held is found")
	# A file from before the bag (each hero's picks): its Relics are found, the picks dropped.
	var older := RelicCollection.from_dict({"levels": {"a": 1, "b": 1, "c": 1},
			"picks": {"alder": ["b", "x"], "brin": ["a"]}})
	assert_eq(older.found_ids(), ["a", "b", "c"] as Array[String])
	assert_eq(older.to_dict().keys(), ["found"])


func test_the_file_saves_loads_banks_and_deletes() -> void:
	assert_eq(String(RelicFile.load_collection(TEST_FILE).status), RelicFile.MISSING)
	assert_true(RelicFile.bank(["iron_charm"], TEST_FILE), "a first find is written")
	assert_false(RelicFile.bank(["iron_charm"], TEST_FILE), "nothing new: nothing written")
	assert_true(RelicFile.bank(["iron_charm", "whetstone"], TEST_FILE))
	var loaded := RelicFile.load_collection(TEST_FILE)
	assert_eq(String(loaded.status), RelicFile.LOADED)
	var got := loaded.collection as RelicCollection
	assert_eq(got.found_ids(), ["iron_charm", "whetstone"] as Array[String])
	# A damaged main file falls back to the backup (the file before the last write).
	var file := FileAccess.open(TEST_FILE, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	assert_eq(RelicFile.load_or_empty(TEST_FILE).found_ids(), ["iron_charm"] as Array[String],
			"the backup is the previous good file")
	RelicFile.delete(TEST_FILE)
	assert_false(RelicFile.exists(TEST_FILE))
	assert_eq(RelicFile.load_or_empty(TEST_FILE).count(), 0)


func test_files_of_format_one_and_two_load_and_are_written_back_as_three() -> void:
	var file := FileAccess.open(TEST_FILE, FileAccess.WRITE)
	file.store_string(JSON.stringify({"format": 1, "relics": {"levels": {"iron_charm": 5, "whetstone": 2},
			"bag": ["whetstone"]}}))
	file.close()
	var loaded := RelicFile.load_collection(TEST_FILE)
	assert_eq(String(loaded.status), RelicFile.LOADED, "a phase 17 to 20 file is not lost")
	var c := loaded.collection as RelicCollection
	assert_eq(c.found_ids(), ["iron_charm", "whetstone"] as Array[String])
	assert_true(RelicFile.bank(["war_drum"], TEST_FILE))
	var body: Variant = JSON.parse_string(FileAccess.get_file_as_string(TEST_FILE))
	assert_eq(int((body as Dictionary).format), RelicCollection.FORMAT_VERSION, "written back in the new format")
	assert_eq(RelicCollection.FORMAT_VERSION, 3, "the Relic book (#328)")
	assert_eq(((body as Dictionary).relics as Dictionary).keys(), ["found"], "no levels, pips or bag")
	assert_eq(RelicFile.load_or_empty(TEST_FILE).count(), 3, "nothing lost on the way")
	# A phase 21 to 26 file (format 2 with Echo pips and a bag) still loads: every Relic in it is found.
	file = FileAccess.open(TEST_FILE, FileAccess.WRITE)
	file.store_string(JSON.stringify({"format": 2, "relics": {"found": ["war_drum", "keen_eye"],
			"pips": {"war_drum": 12}, "bag": ["keen_eye"]}}))
	file.close()
	var pipped := RelicFile.load_or_empty(TEST_FILE)
	assert_eq(pipped.found_ids(), ["war_drum", "keen_eye"] as Array[String])
	assert_eq(pipped.to_dict().keys(), ["found"])


func test_a_file_of_another_version_is_kept_and_never_written_over() -> void:
	var file := FileAccess.open(TEST_FILE, FileAccess.WRITE)
	file.store_string(JSON.stringify({"format": RelicCollection.FORMAT_VERSION + 1, "relics": {}}))
	file.close()
	var loaded := RelicFile.load_collection(TEST_FILE)
	assert_eq(String(loaded.status), RelicFile.REJECTED)
	assert_true(bool(loaded.keep))
	assert_false(RelicFile.bank(["iron_charm"], TEST_FILE))


# --- a run's Relics -------------------------------------------------------------------------------

func test_a_run_takes_nothing_from_the_book_by_itself() -> void:
	var c := _collection(["iron_charm", "whetstone", "war_drum", "keen_eye", "not_a_relic"])
	var run := _run(7, c)
	assert_true(run.relics.is_empty(), "the starting pick gives Relics (#328), nothing comes by itself")
	assert_eq(run.relics_at_start, {"iron_charm": 1, "whetstone": 1, "war_drum": 1, "keen_eye": 1},
			"everything found this run knows is remembered")
	for slot: int in run.party_size():
		assert_true(run.relics_of(slot).is_empty())
	assert_true(run.waiting_relics().is_empty(), "no bag: nothing waits for a hero")
	assert_false(run.apply_op({"op": "give", "slot": 2, "relic": "war_drum"}), "a Relic in the book is not the run's")
	assert_eq(run.start_left, [1, 1, 1] as Array[int], "each hero may take one from the book")
	assert_eq(run.hp[0], run.max_hp(0))


func test_a_relic_left_at_home_joins_the_run_as_a_home_find() -> void:
	var c := _collection(["iron_charm", "whetstone"])
	var run := _run(7, c)
	var charm := _relic("iron_charm")
	assert_true(run.is_home(charm))
	var info := run.give_relic(charm, 0)
	assert_false(bool(info.new), "not new: it was found before")
	assert_true(bool(info.home))
	assert_false(info.has("level"), "no Relic levels")
	assert_eq(RunState.relic_find_short(info), "Home")
	assert_eq(RunState.relic_find_text(info), "Found: Iron Charm")
	assert_false(run.is_home(charm))
	assert_eq(run.holder_of(charm), 0)
	assert_eq(run.give_relic(charm, 1), {}, "no copies: a Relic the party has never comes again")
	assert_false(run.relic_gain_line().contains("New Relics"))


func test_a_find_is_new_once_and_never_turns_up_again() -> void:
	var run := _run()
	var coin := _relic("lucky_coin")
	assert_true(run.can_gain(coin))
	var first := run.give_relic(coin, 1)
	assert_true(bool(first.new))
	assert_eq(RunState.relic_find_text(first), "New Relic: Lucky Coin")
	assert_eq(RunState.relic_find_short(first), "New")
	assert_false(run.can_gain(coin), "the party has it: it never turns up again")
	var gold := run.gold
	assert_eq(run.give_relic(coin, 1), {})
	assert_eq(run.add_relic(coin), {}, "no copy, so no spare gold either")
	assert_eq(run.gold, gold)
	assert_eq(run.relics, {"lucky_coin": 1})


func test_a_hero_keeps_every_relic_given_with_no_slots() -> void:
	var run := _run()
	var given: Array[GearData] = []
	for item: GearData in _data.gear.slice(0, 7):
		assert_false(run.give_relic(item, 0).is_empty(), item.id)
		given.append(item)
	assert_eq(run.relics_of(0), given, "seven Relics on one hero, in the order given")
	for item: GearData in given:
		assert_eq(run.holder_of(item), 0)
		assert_true(run.give_relic(item, 1).is_empty(), "%s: never on two heroes" % item.id)
	assert_eq(run.give_relic(_data.gear[8], 3), {}, "no such hero")
	assert_eq(run.give_relic(GearData.new(), 0), {}, "not one of the run's Relics")
	assert_eq(run.fewest_relics_hero(), 1, "the first of the heroes with none")


func test_the_bot_gives_every_waiting_relic_to_the_hero_it_helps_most() -> void:
	var run := _run()
	for id: String in ["iron_charm", "whetstone", "war_drum"]:
		run.add_relic(_relic(id))
	assert_eq(run.waiting_relics().size(), 3)
	assert_eq(run.auto_give(), 3, "every waiting Relic goes to a hero")
	assert_eq(run.auto_give(), 0, "nothing left to give")
	assert_true(run.waiting_relics().is_empty())
	var total := 0
	for slot: int in run.party_size():
		total += run.relics_of(slot).size()
	assert_eq(total, 3)
	# A Relic no hero suits more than another goes to the one with the fewest.
	var even := _run()
	var coin := _relic("lucky_coin")
	var fits: Array[int] = []
	for hero: CharacterData in _data.party:
		fits.append(GearBot.fit_of(hero, coin))
	assert_eq(fits.min(), fits.max(), "the Lucky Coin suits no hero more than another")
	even.give_relic(_relic("iron_charm"), 0)
	assert_eq(GearBot.best_hero(even, coin), 1, "a tie: the first with the fewest Relics")
	assert_eq(GearBot.best_hero(even, coin, [0] as Array[int]), 0, "only an allowed hero")


func test_spoils_offer_only_relics_the_run_lacks_and_may_run_dry() -> void:
	var run := _run(7, RelicCollection.all_of(_data.gear))
	run.go(run.choices()[0])
	assert_eq(run.loot_choices(run.at).size(), run.loot_choice_count(),
			"finding every Relic before takes nothing from a run's spoils")
	var left: Array[GearData] = [_relic("war_drum"), _relic("keen_eye")]
	for item: GearData in _data.gear:
		if not left.has(item):
			run.add_relic(item)
	var offered := run.loot_choices(run.at)
	assert_lte(offered.size(), 2, "only what the party lacks")
	for item: GearData in offered:
		assert_true(left.has(item), item.id)
	for item: GearData in left:
		run.add_relic(item)
	assert_true(run.loot_choices(run.at).is_empty(), "a party with every Relic gets none (honestly dry)")


func test_a_relic_stat_line_adds_attribute_points() -> void:
	var run := _run()
	var drum := _relic("war_drum")
	var power_before := run.power_percent(0)
	assert_false(run.give_relic(drum, 0).is_empty())
	assert_eq(run.relic_stat(0, Attributes.Kind.MIGHT), drum.stat_points)
	assert_eq(run.attribute(0, Attributes.Kind.MIGHT), 0, "spent points are not touched")
	assert_eq(run.power_percent(0), power_before + drum.stat_points * run.tuning.attr_might_power_percent)
	assert_true(run.passives(0).has(Passive.START_AP), "and the effect is there")
	assert_eq(run.relic_stat(1, Attributes.Kind.MIGHT), 0, "only the hero who has it")


func test_wins_give_no_relics() -> void:
	var run := _run()
	run.give_relic(_relic("war_drum"), 0)
	for encounter: EncounterData in [_husk(), _guard(), run.final_encounter()]:
		var got := _win(run, encounter)
		assert_false(got.has("relics"), "%s: no drops (8.24)" % encounter.id)
	assert_eq(run.relics, {"war_drum": 1})


func test_the_end_screen_line_names_new_relics() -> void:
	var c := _collection(["whetstone", "war_drum"])
	var run := _run(7, c)
	assert_eq(run.relic_gain_line(), "Nothing new to keep.")
	run.give_relic(_relic("whetstone"), 0)
	run.give_relic(_relic("iron_charm"), 1)
	assert_eq(run.relic_gain_line(), "New Relics: Iron Charm", "a Relic found before is not news")
	var copy := RunState.from_dict(_data, run.tuning, run.to_dict())
	assert_eq(copy.relic_gain_line(), run.relic_gain_line(), "the start survives a save")


func test_an_online_friend_banks_what_is_new_to_them() -> void:
	# Card #281: the run plays with the host's collection; a friend keeps what is new to them.
	var run := _run(7, _collection(["war_drum"]))
	run.give_relic(_relic("war_drum"), 0)
	var friend := _collection(["iron_charm"])
	assert_eq(run.relic_gain_line_since(friend.found), "New Relics: War Drum",
			"the friend's end screen: new to them, though the host had it")
	assert_true(friend.merge(run.relic_ids_since({})))
	assert_true(friend.owns("war_drum"))
	assert_true(friend.owns("iron_charm"), "what the friend had stays")


func test_a_late_joiner_keeps_only_what_came_after() -> void:
	# Card #304: a friend who dropped in mid-run banks only the Relics found after they joined.
	var run := _run()
	run.give_relic(_relic("war_drum"), 0)
	var relics_before := run.relics.duplicate()
	run.give_relic(_relic("iron_charm"), 1)
	assert_eq(run.relic_ids_since(relics_before), ["iron_charm"], "only the Relic found after the join")
	var every := run.relic_ids_since({})
	every.sort()
	var keys := run.relics.keys()
	keys.sort()
	assert_eq(every, keys, "empty: every Relic the run has")
	var friend := _collection(["ash_veil"])
	var since := {"relics": relics_before}
	var shown: Array = []
	for entry: Dictionary in RunEndScreen.own_kept(run, friend, since):
		shown.append((entry.item as GearData).id)
	assert_eq(shown, ["iron_charm"], "the late find is theirs, the earlier one is not (the Kept row)")
	assert_true(friend.merge(run.relic_ids_since(relics_before)))
	assert_true(friend.owns("iron_charm"))
	assert_false(friend.owns("war_drum"), "nothing found before they joined is banked")
	assert_true(friend.owns("ash_veil"), "what the friend had stays")


# --- saving and online ----------------------------------------------------------------------------

func test_the_relic_state_survives_a_save_and_the_network() -> void:
	var run := _run(7, _collection(["war_drum", "iron_charm", "whetstone"]))
	run.add_relic(_relic("whetstone"))
	run.give_relic(_relic("war_drum"), 0)
	run.give_relic(_relic("iron_charm"), 0)
	run.give_relic(_relic("keen_eye"), 2)
	var data := run.to_dict()
	assert_eq(Fx.find_illegal_value(data), "", "only plain values go over the network")
	assert_eq(data.gear, [["war_drum", "iron_charm"], [], ["keen_eye"]], "each hero's Relics as ids")
	for gone: String in ["mastery", "echoes", "pips_start", "guards_beaten"]:
		assert_false(data.has(gone), gone)
	var copy := RunState.from_dict(_data, run.tuning, data)
	assert_not_null(copy)
	if copy == null:
		return
	assert_eq(copy.to_dict(), data)
	assert_eq(copy.relics, run.relics)
	assert_eq(copy.relics_of(0), [_relic("war_drum"), _relic("iron_charm")] as Array[GearData])
	assert_eq(copy.waiting_relics(), [_relic("whetstone")] as Array[GearData], "one waiting (an old save's) still waits")
	assert_eq(copy.passives(0), run.passives(0))
	assert_eq(copy.passives(2), run.passives(2))


func test_bad_relic_state_is_refused() -> void:
	var run := _run()
	run.give_relic(_relic("whetstone"), 0)
	var good := run.to_dict()
	assert_not_null(RunState.from_dict(_data, run.tuning, good))
	var cases := [
		["relics", {"whetstone": 1, "nope": 1}], ["relics", {"whetstone": "1"}], ["relics", {}], ["relics", []],
		["relics_start", {"nope": 1}], ["relics_start", []],
		["gear", [["nope"], [], []]], ["gear", [["whetstone"], ["whetstone"], []]], ["gear", [["whetstone"], []]],
		["gear", [["whetstone", 3], [], []]], ["gear", [null, [], []]],
		["stop_relics", ["nope"]], ["stop_relics", ["iron_charm", "iron_charm"]], ["stop_relics", "iron_charm"],
	]
	for pair: Array in cases:
		var d := good.duplicate(true)
		d[String(pair[0])] = pair[1]
		assert_null(RunState.from_dict(_data, run.tuning, d), "%s = %s" % [pair[0], str(pair[1])])


func test_the_give_op_for_online_play() -> void:
	var run := _run()
	var drum := _relic("war_drum")
	assert_false(run.apply_op({"op": "give", "slot": 0, "relic": "war_drum"}), "not the run's yet")
	run.add_relic(drum)
	assert_false(run.apply_op({"op": "give", "slot": "0", "relic": "war_drum"}), "malformed")
	assert_false(run.apply_op({"op": "give", "slot": 7, "relic": "war_drum"}), "no such hero")
	assert_false(run.apply_op({"op": "give", "slot": 0, "relic": 4}), "malformed")
	assert_true(run.apply_op({"op": "give", "slot": 1, "relic": "war_drum"}))
	assert_eq(run.holder_of(drum), 1)
	assert_false(run.apply_op({"op": "give", "slot": 0, "relic": "war_drum"}), "given already: someone got there first")
	for old: Dictionary in [{"op": "wear", "slot": 0, "gear_slot": 0, "relic": "war_drum"},
			{"op": "take_off", "slot": 1, "gear_slot": 0}, {"op": "echo", "slot": 2, "relic": "war_drum", "on": true}]:
		assert_false(run.apply_op(old), "%s: gone with 8.24" % old.op)
	assert_eq(run.holder_of(drum), 1, "a Relic stays with its hero")


# --- the screens ----------------------------------------------------------------------------------

func test_the_relics_tab_gives_a_waiting_relic_to_the_hero() -> void:
	var run := _run()
	run.add_relic(_relic("iron_charm"))
	run.add_relic(_relic("whetstone"))
	var screen := PartyScreen.new()
	add_child_autofree(screen)
	screen.setup(run)
	screen.open_relics(1, true)
	assert_eq(screen.current_tab(), PartyScreen.Tab.RELICS)
	var tab := screen.tab_node(PartyScreen.Tab.RELICS) as RelicsTab
	assert_eq(tab.badge(), 2, "two wait for a hero")
	assert_true(tab.put(_relic("whetstone")))
	assert_eq(run.holder_of(_relic("whetstone")), 1)
	assert_false(tab.put(_relic("whetstone")), "given already")
	assert_false(tab.put(_relic("rotten_crown")), "not the run's")
	tab.focus_hero(2, true)
	assert_true(tab.put(_relic("iron_charm")))
	assert_eq(run.relics_of(2), [_relic("iron_charm")] as Array[GearData])
	assert_eq(tab.badge(), 0)
	tab.focus_hero(0)
	assert_false(tab.open_bag(), "nothing left to give")
	assert_eq(String(tab.info().title), "Nothing to give")


# --- harder runs ----------------------------------------------------------------------------------

func test_run_fights_get_the_base_enemy_power_and_practice_keeps_the_data() -> void:
	# Phase 17 made run fights 5% harder; the three-act run's balance pass (#321, DESIGN.md 8.23) set
	# the run back to its data, and the Fight Rush keeps its 105% in rush_enemy_power_percent.
	assert_eq(_tuning.enemy_power_base_percent, 100, "#321: run fights as in the data")
	assert_eq(CombatMath.percent(_tuning.enemy_power_base_percent, _tuning.rush_enemy_power_percent), 105,
			"the Rush keeps its 105%")
	var run := _run()
	run.tuning.enemy_power_base_percent = 105
	var husk := _husk()
	var setup := run.fight_setup(husk, 1, CombatSetup.Opening.NORMAL)
	assert_eq(setup.enemy_power_percent, CombatMath.percent(run.enemy_power_percent(), 105))
	var practice := CombatSetup.from_encounter(husk, _tuning, 1, CombatSetup.Opening.NORMAL)
	assert_lt(practice.enemy_power_percent, setup.enemy_power_percent, "practice fights are as in the data")
