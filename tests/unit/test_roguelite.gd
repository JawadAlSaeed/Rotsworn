extends GutTest
## Phase 21, the roguelite pass (DESIGN.md 8.19): defence counts and Flawless spoils (#283). Uses the
## shipped run and tuning. Never touches the player's files.

const RUN_PATH := "res://data/runs/rotten_road.tres"

var _data: RunData
var _tuning: Tuning


func before_all() -> void:
	_data = load(RUN_PATH) as RunData
	_tuning = load("res://data/tuning/tuning.tres") as Tuning


func _run(seed_value: int = 7) -> RunState:
	return RunState.begin(_data, _tuning.duplicate(true) as Tuning, seed_value)


func _husk() -> EncounterData:
	return load("res://data/encounters/husk_fight.tres") as EncounterData


func _guard() -> EncounterData:
	return load("res://data/encounters/guard_gorged_one.tres") as EncounterData


func _recap(heroes: Array, taken: int) -> Dictionary:
	return {"heroes": heroes, "hits_taken": taken}


# --- defence counts, and pays (#283) --------------------------------------------------------------

func test_each_fights_defence_adds_up_per_hero() -> void:
	var run := _run()
	assert_eq(run.defence, [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]] as Array[Array])
	run.finish_fight(RunState.VICTORY, run.hp.duplicate(), _husk(), _recap([[3, 1, 0, 2], [0, 4, 1, 0], [1, 0, 0, 5]], 7))
	run.finish_fight(RunState.ESCAPED, run.hp.duplicate(), _husk(), _recap([[1, 0, 0, 0], [0, 0, 0, 0], [0, 0, 2, 1]], 1))
	assert_eq(run.defence, [[4, 1, 0, 2], [0, 4, 1, 0], [1, 0, 2, 6]] as Array[Array], "won or not, it counts")
	assert_eq(run.best_defender(), 1, "Brin and Alder both saved 5; Brin took fewer hits")
	run.add_defence("junk")
	run.add_defence([[1, 1]])
	assert_eq(run.defence[0], [4, 1, 0, 2], "junk is ignored")


func test_nobody_is_best_without_a_single_defence() -> void:
	assert_eq(_run().best_defender(), -1)


func test_a_flawless_guard_or_elite_gives_one_more_spoils_choice() -> void:
	var run := _run()
	run.go(run.choices()[0])
	var plain := run.loot_choice_count()
	assert_false(RunState.is_flawless(_husk(), _recap([], 0)), "an ordinary fight is never Flawless")
	assert_false(RunState.is_flawless(_guard(), {}), "no recap, no Flawless")
	assert_true(RunState.is_flawless(_guard(), _recap([], 0)))
	run.finish_fight(RunState.VICTORY, run.hp.duplicate(), _guard(), _recap([[1, 0, 0, 1], [0, 0, 0, 0], [0, 0, 0, 0]], 1))
	assert_false(run.flawless, "one hit taken")
	run.finish_fight(RunState.VICTORY, run.hp.duplicate(), _guard(), _recap([[2, 1, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]], 0))
	assert_true(run.flawless)
	assert_eq(run.loot_choice_count(), plain + 1)
	assert_eq(run.loot_choices(run.at).size(), plain + 1, "the spoils offer one more Relic")
	var copy := RunState.from_dict(_data, run.tuning, run.to_dict())
	assert_true(copy.flawless, "saved and sent online")
	assert_eq(copy.defence, run.defence)
	run.finish_fight(RunState.VICTORY, run.hp.duplicate(), _husk(), _recap([[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]], 0))
	assert_false(run.flawless, "only the fight right before the spoils counts")
	run.flawless = true
	run.go(run.choices()[0])
	assert_false(run.flawless, "the next stop starts plain")


func test_an_older_save_without_defence_still_loads() -> void:
	var run := _run()
	var old := run.to_dict()
	old.erase("defence")
	old.erase("flawless")
	var copy := RunState.from_dict(_data, run.tuning, old)
	assert_not_null(copy)
	assert_eq(copy.defence, run.defence)
	var bad := run.to_dict()
	bad["defence"] = [[1, 2, 3]]
	assert_null(RunState.from_dict(_data, run.tuning, bad), "a broken defence list is refused")


func test_the_run_end_shows_a_defence_row_per_hero_with_a_star_for_the_best() -> void:
	var run := _run()
	run.add_defence([[5, 0, 0, 1], [1, 0, 0, 0], [0, 0, 0, 0]])
	var rows := RunEndScreen._defence_rows(run, [1, 2, 2] as Array[int])
	add_child_autofree(rows)
	assert_eq(rows.get_child_count(), run.party_size())
	var alder := rows.get_child(0)
	assert_eq((alder.get_child(1) as Label).text, "P1", "co-op: whose hero")
	var star := alder.get_child(alder.get_child_count() - 1) as Control
	assert_eq(star.modulate.a, 1.0, "Alder defended best")
	var brin := rows.get_child(1)
	assert_eq((brin.get_child(brin.get_child_count() - 1) as Control).modulate.a, 0.0)


# --- one more run, together (#284) ----------------------------------------------------------------

func _action(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func test_the_run_end_offers_again_or_the_main_menu() -> void:
	var run := _run()
	var end := RunEndScreen.new()
	add_child_autofree(end)
	end.setup(run, 0)
	watch_signals(end)
	end._age = 1.0
	end._unhandled_input(_action(&"menu_confirm"))
	assert_signal_emitted(end, "again", "Confirm plays again with the same players")
	assert_signal_not_emitted(end, "done")
	end._unhandled_input(_action(&"menu_cancel"))
	assert_signal_emitted(end, "done", "Back goes to the main menu")


# --- a pact at the start (#285) -------------------------------------------------------------------

func _with_relics() -> RelicCollection:
	var c := RelicCollection.new()
	c.merge(["iron_charm"])
	return c


func _pact(run: RunState, id: String) -> EventChoiceData:
	for choice: EventChoiceData in run.data.pacts:
		if choice.deal.id == "pact_" + id:
			return choice
	fail_test("no pact %s" % id)
	return null


func test_a_first_ever_run_has_no_pact_and_later_runs_do() -> void:
	assert_false(_run().pact_pending, "nothing found yet: a first-ever run")
	var run := RunState.begin(_data, _tuning.duplicate(true) as Tuning, 7, 0, _with_relics())
	assert_true(run.pact_pending)
	var copy := RunState.from_dict(_data, run.tuning, run.to_dict())
	assert_true(copy.pact_pending, "saved and sent online")


func test_the_pact_offers_three_seeded_deals_each_with_a_price() -> void:
	assert_gte(_data.pacts.size(), 6)
	var run := RunState.begin(_data, _tuning.duplicate(true) as Tuning, 7, 0, _with_relics())
	var event := run.pact_event()
	assert_eq(event.choices.size(), _tuning.run_pact_choices)
	assert_eq(event.choices, run.pact_event().choices, "the same seed, the same pacts")
	assert_false(event.picture_path.is_empty())
	var seen := {}
	for s: int in range(1, 30):
		for choice: EventChoiceData in RunState.begin(_data, _tuning, s, 0, _with_relics()).pact_event().choices:
			seen[choice] = true
	assert_gt(seen.size(), _tuning.run_pact_choices, "runs differ")
	for choice: EventChoiceData in _data.pacts:
		var words := run.offer_lines(choice.deal, 100)
		assert_false((words.price as Array).is_empty(), "%s has a price" % choice.text)
		assert_false((words.gift as Array).is_empty(), "%s has a gift" % choice.text)


func test_feeding_the_hungry_relic_gives_a_rare_relic_and_a_curse() -> void:
	var run := RunState.begin(_data, _tuning.duplicate(true) as Tuning, 7, 0, _with_relics())
	var before := run.owned_relics().size()
	var got := run.choose_event(_pact(run, "hungry_relic"), run.at, 0)
	assert_true(bool(got.ok))
	assert_eq(run.owned_relics().size(), before + 1, "a Relic joins the run")
	var found: GearData = null
	for item: GearData in run.owned_relics():
		if item.id != "iron_charm":
			found = item
	assert_gte(int(found.rarity), ItemData.Rarity.RARE)
	assert_eq(run.holder_of(found), 0, "given to a hero: the one with the fewest Relics (DESIGN.md 8.24)")
	assert_true(String(got.text).contains(run.data.party[0].display_name), "the line says who got it")
	assert_eq(run.rot_percent(), 3, "and the Rotting Heart rots the party")
	var picked := RunState.begin(_data, _tuning.duplicate(true) as Tuning, 7, 0, _with_relics())
	picked.choose_event(_pact(picked, "hungry_relic"), picked.at, 0, -1, 2)
	assert_eq(picked.relics_of(2).size(), 1, "the hero the player picked gets it")


# --- a map with a dare (#286) ---------------------------------------------------------------------

func _crowned(map: RunMap) -> Array[int]:
	var ids: Array[int] = []
	for s: Dictionary in map.stops:
		if bool(s.get("crown", false)):
			ids.append(int(s.id))
	return ids


func test_every_act_map_has_one_crowned_elite_on_a_road() -> void:
	for s: int in range(1, 40):
		var run := _run(s)
		for act: int in run.acts().size():
			var map := run._make_map(act)
			var crowned := _crowned(map)
			if run.acts()[act].elites.is_empty():
				assert_eq(crowned.size(), 0, "no elites, no crown")
				continue
			assert_eq(crowned.size(), 1, "seed %d act %d: one crowned elite" % [s, act + 1])
			assert_eq(int(map.stop(crowned[0]).type), RunMap.StopType.ELITE)
			assert_gte(int(map.stop(crowned[0]).zone), 0, "it has a place to be fought in")
			assert_gt(map.count_type(RunMap.StopType.SHOP), 0, "still a shop")
			assert_gt(map.count_type(RunMap.StopType.TREASURE), 0, "still a treasure row")
			assert_eq(map.choices(-1).size(), (map.rows[0] as Array).size())


func test_the_campfire_and_treasure_rows_move_between_maps() -> void:
	var rest_rows := {}
	var treasure_rows := {}
	for s: int in range(1, 60):
		var map := _run(s).map
		for s2: Dictionary in map.stops:
			if int(s2.type) == RunMap.StopType.REST and int(s2.row) >= map.row_count() - 3:
				var full := true
				for id: int in map.rows[int(s2.row)]:
					full = full and int(map.stop(id).type) == RunMap.StopType.REST
				if full:
					rest_rows[int(s2.row)] = true
			if int(s2.type) == RunMap.StopType.TREASURE:
				treasure_rows[int(s2.row)] = true
	assert_gt(rest_rows.size(), 1, "the campfire row is not always the same")
	assert_gt(treasure_rows.size(), 1, "the treasure row moves")


func test_the_crowned_elite_is_harder_and_its_spoils_hold_a_legendary_relic() -> void:
	var run := _run(5)
	var crown := _crowned(run.map)
	assert_eq(crown.size(), 1)
	var elite := run.act_data().elites[0]
	run.at = crown[0]
	var crowned := run.fight_setup(elite, 1, CombatSetup.Opening.NORMAL)
	var plain_id := -1
	for s: Dictionary in run.map.stops:
		if int(s.type) == RunMap.StopType.ELITE and not bool(s.get("crown", false)):
			plain_id = int(s.id)
	if plain_id >= 0:
		run.at = plain_id
		var plain := run.fight_setup(elite, 1, CombatSetup.Opening.NORMAL)
		assert_gt(crowned.enemy_hp_percent, plain.enemy_hp_percent, "more HP")
		assert_gt(crowned.enemy_power_percent, plain.enemy_power_percent, "more power")
	run.at = crown[0]
	var loot := run.loot_choices(crown[0])
	assert_eq(int(loot[0].rarity), ItemData.Rarity.LEGENDARY, "a legendary Relic, listed first")
	assert_eq(loot.size(), run.loot_choice_count())
	var unique := {}
	for item: GearData in loot:
		unique[item] = true
	assert_eq(unique.size(), loot.size(), "no Relic twice")
	assert_true(run.is_crowned())


# --- no free stops (#287) -------------------------------------------------------------------------

func test_a_treasure_stop_has_a_plain_and_a_rotten_chest() -> void:
	var outcomes := {"curse": 0, "ambush": 0, "clean": 0}
	for s: int in range(1, 40):
		var plain := _run(s)
		plain.gold = 0
		var got := plain.open_treasure(3, false)
		assert_eq(int(got.gold), _tuning.run_treasure_gold, "the plain chest: gold")
		assert_true(got.prize is ItemData, "and an item")
		assert_true(plain.stop_done, "the result is final")
		var rotten := _run(s)
		var dark := rotten.open_treasure(3, true)
		assert_null(dark.prize, "the rotten chest: no item")
		var offered := dark.relics as Array[GearData]
		assert_eq(offered.size(), rotten.relic_choice_count(), "but a pick of Relics (DESIGN.md 8.24)")
		for item: GearData in offered:
			assert_gte(int(item.rarity), ItemData.Rarity.RARE)
			assert_false(rotten.owns(item), "only Relics the run does not have")
		assert_eq(rotten.stop_relic_choices(), offered, "they wait at the stop until one is taken")
		assert_eq(int(dark.gold), 0)
		assert_eq(dark, _run(s).open_treasure(3, true), "seeded")
		if dark.curse != null:
			outcomes.curse += 1
			assert_gt(rotten.rot_percent(), 0)
		elif bool(dark.ambush):
			outcomes.ambush += 1
			assert_true(rotten.in_ambush())
		else:
			outcomes.clean += 1
	for key: String in outcomes:
		assert_gt(int(outcomes[key]), 0, "the rotten chest sometimes gives: %s" % key)


func test_the_campfire_before_the_boss_offers_watch_and_sharpen() -> void:
	var run := _run(3)
	var watch := -1
	var other := -1
	for s: Dictionary in run.map.stops:
		if int(s.type) != RunMap.StopType.REST:
			continue
		run.at = int(s.id)
		if run.is_watch_fire():
			watch = int(s.id)
		else:
			other = int(s.id)
	assert_gte(watch, 0, "the campfire row is found")
	run.at = watch
	run.team_gauge = 0
	run.keep_watch()
	assert_eq(run.team_gauge, _tuning.team_gauge_max)
	run.sharpened = true
	var boss := run.final_encounter()
	var before := int(run.passives(0).get(Passive.START_AP, 0))
	var setup := run.fight_setup(boss, 1, CombatSetup.Opening.NORMAL)
	assert_eq(int(setup.party_passives[0].get(Passive.START_AP, 0)), before + _tuning.sharpen_ap, "+1 AP for the boss")
	var ordinary := run.fight_setup(_husk(), 1, CombatSetup.Opening.NORMAL)
	assert_eq(int(ordinary.party_passives[0].get(Passive.START_AP, 0)), before, "not for other fights")
	assert_true(RunState.from_dict(_data, run.tuning, run.to_dict()).sharpened, "saved")
	run.finish_fight(RunState.VICTORY, run.hp.duplicate(), boss)
	assert_false(run.sharpened, "used up by the boss fight")
	if other >= 0:
		run.at = other
		assert_false(run.is_watch_fire(), "other campfires keep Rest, Train and Upgrade")


# --- review fixes -----------------------------------------------------------------------------------

func test_a_run_saved_before_phase_21_keeps_its_map() -> void:
	var run := _run(9)
	var old := run.to_dict()
	old.erase("map_rules")
	var copy := RunState.from_dict(_data, run.tuning, old)
	assert_not_null(copy)
	assert_eq(copy.map_rules, 1, "the old rules")
	var plain := RunMap.generate(CombatRng.new(9), run.tuning, run.act_data().zones.size(),
			not run.act_data().elites.is_empty(), not run.act_data().events.is_empty(), false, false)
	for s: Dictionary in copy.map.stops:
		assert_eq(int(s.type), int(plain.stop(int(s.id)).type), "stop %d as it was" % int(s.id))
	assert_eq(RunState.from_dict(_data, run.tuning, copy.to_dict()).map_rules, 1, "and keeps them when saved again")
	assert_eq(RunState.from_dict(_data, run.tuning, run.to_dict()).map_rules, RunState.MAP_RULES)


func test_the_rotten_chest_stays_the_one_shown_open() -> void:
	var run := _run(4)
	run.open_treasure(3, true)
	assert_true(run.stop_rotten)
	assert_true(RunState.from_dict(_data, run.tuning, run.to_dict()).stop_rotten, "saved and sent online")
	run.go(run.choices()[0])
	assert_false(run.stop_rotten, "a new stop starts closed")
