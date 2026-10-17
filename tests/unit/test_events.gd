extends GutTest
## "?" events with real trade-offs (card #193, DESIGN.md 8.7): the new costs (permanent max HP, a
## backpack item, a curse, an ambush fight), the ambush chance of a "?" stop, depth scaling, the
## event screen's greyed choices, the shipped events and the bot's habits. Uses the shipped run.

const RUN_PATH := "res://data/runs/rotten_road.tres"
const EVENTS_DIR := "res://data/events"

var _data: RunData
var _tuning: Tuning


func before_all() -> void:
	_data = load(RUN_PATH) as RunData
	_tuning = load("res://data/tuning/tuning.tres") as Tuning


func _run(seed_value: int = 7, tuning: Tuning = null) -> RunState:
	return RunState.begin(_data, tuning if tuning != null else _tuning, seed_value)


func _offer(props: Dictionary) -> ZoneOfferData:
	var offer := ZoneOfferData.new()
	for key: String in props:
		offer.set(key, props[key])
	return offer


func _item(run: RunState, id: String) -> ItemData:
	return run.items_by_id()[id] as ItemData


func _event(id: String) -> EventData:
	return load("%s/%s.tres" % [EVENTS_DIR, id]) as EventData


func _screen(run: RunState, event: EventData, remote: bool = false) -> EventScreen:
	var screen := EventScreen.new()
	screen.remote = remote
	add_child_autofree(screen)
	screen.setup(run, event)
	return screen


## An event stop with the stop before it (so the party can be put there and move on).
func _event_stop(run: RunState) -> Dictionary:
	for stop: Dictionary in run.map.stops:
		if int(stop.type) == RunMap.StopType.EVENT and not (stop.prev as Array).is_empty():
			return stop
	return {}


# --- max HP for good ------------------------------------------------------------------------------

func test_max_hp_cost_takes_a_share_of_everyones_max_hp() -> void:
	var run := _run()
	var before: Array[int] = []
	for slot: int in run.party_size():
		before.append(run.max_hp(slot))
	var offer := _offer({"cost_max_hp_percent": 10})
	assert_true(run.can_take_offer(offer))
	var got := run.take_offer(offer, 1, 0)
	assert_true(bool(got.ok))
	assert_string_contains(String(got.text), "max HP")
	for slot: int in run.party_size():
		assert_eq(run.max_hp_percent[slot], 90, "hero %d lost 10 points of their normal max HP" % slot)
		assert_lt(run.max_hp(slot), before[slot])
		assert_lte(run.hp[slot], run.max_hp(slot), "HP never stays above the new max")


func test_the_share_is_of_the_heroes_current_max_hp() -> void:
	var run := _run()
	run.levels[0] = 5
	var total := run.total_max_hp_percent(0)
	assert_gt(total, 100)
	run.take_offer(_offer({"cost_max_hp_percent": 10}), 1, 0)
	assert_eq(run.max_hp_percent[0], 100 - CombatMath.percent(total, 10), "a levelled hero loses more points")


func test_max_hp_never_goes_under_the_floor() -> void:
	var run := _run()
	var floor_percent := _tuning.event_max_hp_floor_percent
	run.max_hp_percent[0] = floor_percent + 2
	assert_eq(run.lose_max_hp(0, 10), 2, "only what is left above the floor")
	assert_eq(run.max_hp_percent[0], floor_percent)
	assert_false(run.hero_can_lose_max_hp(0))
	assert_eq(run.lose_max_hp(0, 10), 0)
	assert_eq(run.max_hp_percent[0], floor_percent)


func test_a_max_hp_choice_is_greyed_when_everyone_is_at_the_floor() -> void:
	var run := _run()
	var offer := _offer({"cost_max_hp_percent": 5})
	for slot: int in run.party_size():
		run.max_hp_percent[slot] = _tuning.event_max_hp_floor_percent
	assert_false(run.can_take_offer(offer))
	var before := run.to_dict()
	assert_false(bool(run.take_offer(offer, 1, 0).ok))
	assert_eq(run.to_dict(), before, "nothing changed")
	run.max_hp_percent[2] = 100
	assert_true(run.can_take_offer(offer), "one hero with something to give is enough")


func test_a_chosen_hero_alone_pays() -> void:
	var run := _run()
	var offer := _offer({"cost_max_hp_percent": 10, "cost_max_hp_target": ZoneOfferData.HpTarget.CHOSEN})
	assert_eq(offer.pick_kind(), ZoneOfferData.Pick.HERO)
	assert_false(bool(run.take_offer(offer, 1, 0).ok), "asks for a hero first")
	assert_false(bool(run.take_offer(offer, 1, 0, 100, 9).ok), "no such hero")
	assert_true(bool(run.take_offer(offer, 1, 0, 100, 1).ok))
	assert_eq(run.max_hp_percent[1], 90)
	assert_eq(run.max_hp_percent[0], 100)
	assert_eq(run.max_hp_percent[2], 100)
	run.max_hp_percent[2] = _tuning.event_max_hp_floor_percent
	assert_false(run.pick_fits(offer, 2), "a hero at the floor cannot be picked")


func test_a_random_hero_pays_the_same_way_on_every_machine() -> void:
	var offer := _offer({"cost_max_hp_percent": 10, "cost_max_hp_target": ZoneOfferData.HpTarget.RANDOM})
	var seen := {}
	for s: int in range(1, 25):
		var a := _run(s)
		var b := _run(s)
		a.take_offer(offer, 3, 0)
		b.take_offer(offer, 3, 0)
		assert_eq(a.max_hp_percent, b.max_hp_percent, "seed %d: the same hero on both" % s)
		var paid := 0
		for slot: int in a.party_size():
			if a.max_hp_percent[slot] < 100:
				paid += 1
				seen[slot] = true
		assert_eq(paid, 1, "exactly one hero pays")
	assert_gt(seen.size(), 1, "it is not always the same hero")


func test_a_choice_that_needs_a_pick_is_refused_without_one() -> void:
	var run := _run()
	var choice := EventChoiceData.new()
	choice.deal = _offer({"cost_max_hp_percent": 10, "cost_max_hp_target": ZoneOfferData.HpTarget.CHOSEN, "xp": 50})
	assert_true(run.can_choose(choice))
	assert_false(bool(run.choose_event(choice, 3, 0).ok))
	assert_eq(run.xps[0], 0)
	assert_true(bool(run.choose_event(choice, 3, 0, 0).ok))
	assert_eq(run.max_hp_percent[0], 90)


# --- a backpack item ----------------------------------------------------------------------------------

func test_losing_an_item_is_greyed_when_the_pack_is_empty() -> void:
	var run := _run()
	var offer := _offer({"cost_item": ZoneOfferData.ItemCost.RANDOM, "gold": 50})
	assert_false(run.can_take_offer(offer))
	assert_false(bool(run.take_offer(offer, 1, 0).ok))
	assert_eq(run.gold, 0, "no reward without paying")
	run.add_item(_item(run, "salve"))
	assert_true(run.can_take_offer(offer))


func test_rotten_items_are_never_lost_to_an_event() -> void:
	var run := _run()
	run.add_item(_item(run, "rotting_heart"))
	var offer := _offer({"cost_item": ZoneOfferData.ItemCost.RANDOM})
	assert_true(run.losable_uids().is_empty())
	assert_false(run.can_take_offer(offer), "only rot in the pack: nothing to lose")
	var salve := run.add_item(_item(run, "salve"))
	assert_eq(run.losable_uids(), [salve] as Array[int])
	run.take_offer(offer, 1, 0)
	assert_eq(run.rotten_uids().size(), 1, "the rot stayed")
	assert_false(run.backpack.has_uid(salve))


func test_a_random_item_is_lost_the_same_way_on_every_machine() -> void:
	var offer := _offer({"cost_item": ZoneOfferData.ItemCost.RANDOM})
	var kinds := {}
	for s: int in range(1, 25):
		var a := _run(s)
		var b := _run(s)
		for run: RunState in [a, b]:
			for id: String in ["salve", "key", "ember_stone", "heartleaf"]:
				run.add_item(_item(run, id))
			run.take_offer(offer, 2, 1)
		assert_eq(a.backpack.entries.size(), 3)
		assert_eq(a.backpack.to_array(), b.backpack.to_array(), "seed %d: the same item went" % s)
		for e: Dictionary in a.backpack.entries:
			kinds[(e.item as ItemData).id] = true
	assert_gt(kinds.size(), 3, "different seeds lose different items")


func test_a_chosen_item_is_the_one_lost() -> void:
	var run := _run()
	var salve := run.add_item(_item(run, "salve"))
	var key := run.add_item(_item(run, "key"))
	var offer := _offer({"cost_item": ZoneOfferData.ItemCost.CHOSEN})
	assert_eq(offer.pick_kind(), ZoneOfferData.Pick.ITEM)
	assert_false(bool(run.take_offer(offer, 1, 0).ok), "asks for an item first")
	assert_false(bool(run.take_offer(offer, 1, 0, 100, 999).ok), "no such item")
	assert_true(bool(run.take_offer(offer, 1, 0, 100, key).ok))
	assert_true(run.backpack.has_uid(salve))
	assert_false(run.backpack.has_uid(key))


# --- a curse -------------------------------------------------------------------------------------------

func test_a_curse_goes_into_the_pack_and_the_shop_cleanses_it() -> void:
	var run := _run()
	var offer := _offer({"cost_rotten": _item(run, "grave_moss"), "gold": 50})
	var got := run.take_offer(offer, 1, 0)
	assert_true(bool(got.ok))
	assert_eq(run.gold, 50)
	assert_eq(run.rotten_uids().size(), 1, "the rotten item is in the backpack")
	assert_gt(run.rot_percent(), 0, "and it rots the party in fights")
	assert_string_contains(String(got.text), "Grave Moss")
	run.gold = _tuning.shop_cleanse_price
	assert_true(run.cleanse(run.rotten_uids()[0]))
	assert_true(run.rotten_uids().is_empty())


func test_a_curse_is_greyed_when_it_has_no_room() -> void:
	var run := _run()
	var salve := _item(run, "salve")
	while run.add_item(salve) >= 0:
		pass
	var moss := _item(run, "grave_moss")
	var offer := _offer({"cost_rotten": moss, "gold": 50})
	assert_false(run.can_take_offer(offer))
	assert_false(bool(run.take_offer(offer, 1, 0).ok))
	assert_eq(run.gold, 0)
	# A risk is never refused: the curse that finds no room rots away instead.
	var forced := run.take_offer(offer, 1, 0, 100, -1, true)
	assert_true(bool(forced.ok))
	assert_string_contains(String(forced.text), "no room")
	assert_true(run.rotten_uids().is_empty())


# --- an ambush -----------------------------------------------------------------------------------------

func test_an_ambush_cost_sets_up_the_fight() -> void:
	var run := _run()
	var pack := load("res://data/encounters/hyena_pack.tres") as EncounterData
	var offer := _offer({"ambush": pack, "ambush_spoils": true, "gold": 40})
	assert_false(run.in_ambush())
	var got := run.take_offer(offer, 1, 0)
	assert_true(bool(got.ok))
	assert_true(run.in_ambush())
	assert_eq(run.ambush_id, "hyena_pack")
	assert_true(run.ambush_spoils)
	assert_eq(run.ambush_encounter(), pack, "act 1's early rows fight the plain version")
	assert_eq(run.ambush_streak, 0, "any ambush starts the count over")
	run.act = 1
	assert_eq(run.ambush_encounter(), pack.deep, "a deep act fights the deep version")
	run.act = 0
	run.finish_fight(RunState.VICTORY, run.hp.duplicate(), pack)
	assert_false(run.in_ambush(), "the fight ends the ambush")
	assert_false(run.ambush_spoils)


func test_an_ambush_cannot_be_run_from_but_a_zone_fight_can() -> void:
	var run := _run()
	var pack := load("res://data/encounters/hyena_pack.tres") as EncounterData
	assert_true(run.fight_setup(pack, 1, CombatSetup.Opening.NORMAL).can_run, "a plain fight can be run from")
	run.take_offer(_offer({"ambush": pack}), 1, 0)
	assert_false(run.fight_setup(pack, 1, CombatSetup.Opening.NORMAL).can_run, "an ambush is sprung on the party")
	var open := _tuning.duplicate() as Tuning
	open.ambush_can_run = true
	var other := _run(7, open)
	other.take_offer(_offer({"ambush": pack}), 1, 0)
	assert_true(other.fight_setup(pack, 1, CombatSetup.Opening.NORMAL).can_run, "the tuning can allow it")


func test_an_ambush_risk_springs_with_the_choice_seed() -> void:
	var run := _run()
	var choice := EventChoiceData.new()
	choice.deal = _offer({"gold": 10})
	choice.risk_percent = 100
	choice.risk_deal = _offer({"ambush": load("res://data/encounters/toad_and_fly.tres")})
	choice.risk_text = "Something rises."
	var got := run.choose_event(choice, 2, 0)
	assert_true(bool(got.ok))
	assert_true(bool(got.risk))
	assert_true(bool(got.ambush))
	assert_true(run.in_ambush())
	assert_string_contains(String(got.text), "ambush")


func test_ambush_state_round_trips_and_is_validated() -> void:
	var run := _run()
	run.ambush_streak = 2
	run.ambush_id = "hyena_pack"
	run.ambush_spoils = true
	var back := RunState.from_dict(_data, _tuning, run.to_dict())
	assert_not_null(back, "the state fits")
	assert_eq(back.ambush_streak, 2)
	assert_eq(back.ambush_id, "hyena_pack")
	assert_true(back.ambush_spoils)
	assert_eq(back.to_dict(), run.to_dict())
	# What Save & Quit keeps goes through JSON, where every number is a float.
	var json := JSON.new()
	assert_eq(json.parse(JSON.stringify(run.to_dict())), OK)
	var saved := RunSave._whole_numbers(json.data) as Dictionary
	var loaded := RunState.from_dict(_data, _tuning, saved)
	assert_not_null(loaded, "a saved run keeps the ambush")
	assert_eq(loaded.ambush_streak, 2)
	assert_eq(loaded.ambush_id, "hyena_pack")
	for bad: Dictionary in [{"ambush_id": "nobody_knows_me"}, {"ambush_streak": -1}, {"ambush_streak": 1.5},
			{"ambush_spoils": 1}, {"ambush_id": 5}]:
		var broken := run.to_dict()
		broken.merge(bad, true)
		assert_null(RunState.from_dict(_data, _tuning, broken), "refused: %s" % str(bad))
	var missing := run.to_dict()
	missing.erase("ambush_streak")
	assert_null(RunState.from_dict(_data, _tuning, missing), "a dict without the counter is refused")


func test_the_next_act_ends_a_pending_ambush() -> void:
	var run := _run()
	run.ambush_id = "hyena_pack"
	assert_true(run.next_act())
	assert_false(run.in_ambush())


# --- the "?" stop turning into a fight ---------------------------------------------------------------------

func test_the_chance_rises_with_every_event_passed_and_resets_after_a_fight() -> void:
	var t := _tuning.duplicate() as Tuning
	t.unknown_fight_percent_base = 0
	t.unknown_fight_percent_step = 40
	var run := _run(5, t)
	assert_eq(run.unknown_fight_percent(), 0)
	var fought := -1
	for i: int in 6:
		assert_eq(run.unknown_fight_percent(), mini(100, 40 * i), "the chance before the %dth \"?\"" % (i + 1))
		if run._roll_ambush(10 + i):
			fought = i
			break
		assert_eq(run.ambush_streak, i + 1, "an event passed raises the count")
	assert_gte(fought, 0, "it comes by the fourth, whatever the luck")
	assert_lte(fought, 3)
	assert_eq(run.ambush_streak, 0, "the count starts over")
	assert_eq(run.unknown_fight_percent(), 0, "back to the base")
	assert_true(run.in_ambush())


func test_the_chance_is_the_base_plus_a_step_per_event_and_capped() -> void:
	var run := _run()
	assert_eq(run.unknown_fight_percent(), _tuning.unknown_fight_percent_base)
	run.ambush_streak = 2
	assert_eq(run.unknown_fight_percent(), _tuning.unknown_fight_percent_base + 2 * _tuning.unknown_fight_percent_step)
	run.ambush_streak = 99
	assert_eq(run.unknown_fight_percent(), 100)


func test_the_roll_is_seeded_so_every_machine_agrees() -> void:
	for s: int in range(1, 20):
		var a := _run(s)
		var b := _run(s)
		for stop: int in [4, 9, 12, 5, 7, 11]:
			assert_eq(a._roll_ambush(stop), b._roll_ambush(stop), "seed %d stop %d" % [s, stop])
		assert_eq(a.to_dict(), b.to_dict())
	var differ := false
	for s: int in range(1, 40):
		var a := _run(s)
		var b := _run(s + 100)
		a._roll_ambush(4)
		b._roll_ambush(4)
		differ = differ or a.ambush_id != b.ambush_id or a.ambush_streak != b.ambush_streak
	assert_true(differ, "other seeds roll other luck")


func test_the_first_event_is_an_ambush_about_as_often_as_the_tuning_says() -> void:
	var hits := 0
	var runs := 400
	for s: int in range(1, runs + 1):
		if _run(s)._roll_ambush(6):
			hits += 1
	var expected := CombatMath.percent(runs, _tuning.unknown_fight_percent_base)
	assert_between(hits, CombatMath.percent(expected, 50), expected * 2, "%d of %d first \"?\" stops" % [hits, runs])


func test_walking_onto_an_event_stop_gives_an_event_or_an_ambush_never_both() -> void:
	var ambushes := 0
	var events := 0
	for s: int in range(1, 80):
		var run := _run(s)
		var stop := _event_stop(run)
		if stop.is_empty():
			continue
		run.at = int((stop.prev as Array)[0])
		var seen_before := run.events_seen.size()
		assert_true(run.go(int(stop.id)))
		if run.in_ambush():
			ambushes += 1
			assert_eq(run.events_seen.size(), seen_before, "an ambush uses up no event")
			assert_not_null(run.ambush_encounter())
			assert_eq(run.ambush_streak, 0)
		else:
			events += 1
			assert_eq(run.events_seen.size(), seen_before + 1)
			assert_eq(run.ambush_streak, 1, "an event passed")
	assert_gt(ambushes, 0, "some \"?\" stops are ambushes")
	assert_gt(events, ambushes, "most are events")


func test_leaving_for_another_stop_clears_a_pending_ambush() -> void:
	var run := _run()
	run.ambush_id = "hyena_pack"
	run.ambush_spoils = true
	assert_true(run.go(run.choices()[0]))
	assert_false(run.in_ambush())
	assert_false(run.ambush_spoils)


# --- depth ----------------------------------------------------------------------------------------------------

func test_event_gold_and_xp_grow_with_depth() -> void:
	var run := _run()
	var shallow := -1
	var deep := -1
	for stop: Dictionary in run.map.stops:
		if int(stop.row) == 1 and shallow < 0:
			shallow = int(stop.id)
		if int(stop.row) == 5 and deep < 0:
			deep = int(stop.id)
	assert_gte(run.event_scale(shallow), 100)
	assert_gt(run.event_scale(deep), run.event_scale(shallow), "a deeper row pays and charges more")
	var act_one := run.event_scale(deep)
	run.act = 1
	assert_gt(run.event_scale(deep), act_one, "the next act more again")
	run.act = 0
	var offer := _offer({"gold": 100, "xp": 50, "cost_gold": 20})
	run.gold = 100
	run.take_offer(offer, deep, 0, run.event_scale(deep))
	assert_eq(run.gold, 100 - CombatMath.percent(20, run.event_scale(deep)) + CombatMath.percent(100, run.event_scale(deep)))
	assert_false(run.can_take_offer(_offer({"cost_gold": 100}), 300), "the scaled price is what counts")


func test_choice_summaries_show_the_numbers_that_will_be_paid() -> void:
	var run := _run()
	var stop := _event_stop(run)
	var scale := run.event_scale(int(stop.id))
	var choice := _event("gamblers_bones").choices[0]
	var text := run.choice_summary(choice, int(stop.id))
	assert_string_contains(text, "Price: %d gold" % CombatMath.percent(choice.deal.cost_gold, scale))
	assert_string_contains(text, "+%d gold" % CombatMath.percent(choice.deal.gold, scale))
	assert_string_contains(text, "%d%% risk" % choice.risk_percent)
	var door := run.choice_summary(_event("sealed_door").choices[0], int(stop.id))
	assert_string_contains(door, "ambush")
	var mask := run.choice_summary(_event("whispering_mask").choices[0], int(stop.id))
	assert_string_contains(mask, "max HP")
	assert_string_contains(mask, "you pick")


# --- the event screen --------------------------------------------------------------------------------------------

func test_a_choice_the_party_cannot_pay_is_greyed_and_leave_is_always_there() -> void:
	var run := _run()
	var screen := _screen(run, _event("gamblers_bones"))
	var rows := screen.rows()
	assert_eq(rows.size(), 3, "two choices and Leave")
	assert_false(bool(rows[0].enabled), "the stake costs gold and there is none")
	assert_true(bool(rows[1].enabled), "the purse costs nothing now")
	assert_eq(String(rows[2].text), "Leave")
	assert_true(bool(rows[2].enabled))
	assert_false(screen.can_choose(0))
	assert_false(screen.choose(0))
	run.gold = 500
	var rich := _screen(run, _event("gamblers_bones"))
	assert_true(bool(rich.rows()[0].enabled))


func test_an_item_price_is_greyed_with_an_empty_pack() -> void:
	var run := _run()
	var event := _event("merchant_wreck")
	var screen := _screen(run, event)
	assert_true(bool(screen.rows()[0].enabled), "searching costs nothing up front")
	assert_false(bool(screen.rows()[1].enabled), "the strongbox costs a pack item")
	run.add_item(_item(run, "salve"))
	assert_true(bool(_screen(run, event).rows()[1].enabled))


func test_a_remote_screen_only_shows() -> void:
	var run := _run()
	run.gold = 500
	var screen := _screen(run, _event("gamblers_bones"), true)
	for row: Dictionary in screen.rows():
		assert_false(bool(row.enabled), "clients choose nothing")


func test_the_screen_takes_a_picked_hero() -> void:
	var run := _run()
	var screen := _screen(run, _event("whispering_mask"))
	assert_eq(screen.pick_kind(0), ZoneOfferData.Pick.HERO)
	assert_false(screen.choose(0), "no hero picked")
	for slot: int in run.party_size():
		assert_eq(run.max_hp_percent[slot], 100)
	assert_true(screen.choose(0, 2))
	assert_lt(run.max_hp_percent[2], 100)
	assert_eq(run.max_hp_percent[0], 100)


func test_a_choice_that_springs_an_ambush_leads_to_the_fight() -> void:
	var run := _run()
	var screen := _screen(run, _event("sealed_door"))
	assert_true(screen.choose(0))
	assert_true(run.in_ambush())
	assert_eq(String(screen.rows()[0].text), "Fight", "Continue becomes Fight")


func test_an_ambush_stop_shows_its_own_page() -> void:
	var run := _run()
	run.ambush_id = "hyena_pack"
	var screen := _screen(run, null)
	assert_eq(screen.choice_count(), 0)
	assert_eq(screen.rows().size(), 1)
	assert_eq(String(screen.rows()[0].text), "Fight")
	assert_false(screen.can_choose(0))


# --- the shipped events ----------------------------------------------------------------------------------------------

func _has_scarce_price(deal: ZoneOfferData) -> bool:
	return deal != null and (deal.cost_gold > 0 or deal.cost_max_hp_percent > 0
			or deal.cost_item != ZoneOfferData.ItemCost.NONE or deal.cost_rotten != null or deal.ambush != null)


func test_every_event_file_loads_and_makes_every_choice_cost_something() -> void:
	var count := 0
	var run := _run()
	for file: String in DirAccess.get_files_at(EVENTS_DIR):
		if not file.ends_with(".tres"):
			continue
		var event := load(EVENTS_DIR.path_join(file)) as EventData
		assert_not_null(event, file)
		count += 1
		assert_eq(event.id, file.get_basename(), "%s: id matches the file" % file)
		assert_false(event.title.is_empty())
		assert_false(event.text.is_empty())
		assert_false(event.picture_path.is_empty())
		assert_between(event.choices.size(), 1, 2, "%s: one or two choices" % event.id)
		var screen := _screen(run, event)
		var rows := screen.rows()
		assert_eq(rows.size(), event.choices.size() + 1, "%s: the choices and Leave" % event.id)
		assert_eq(String(rows[rows.size() - 1].text), "Leave", "%s: Leave is always there" % event.id)
		for c: EventChoiceData in event.choices:
			var where := "%s / %s" % [event.id, c.text]
			assert_false(c.text.is_empty(), where)
			assert_false(c.done_text.is_empty(), "%s: tells what happened" % where)
			assert_not_null(c.deal, "%s: does something" % where)
			if c.risk_percent > 0:
				assert_not_null(c.risk_deal, "%s: has a risk" % where)
				assert_false(c.risk_text.is_empty(), "%s: says what the risk did" % where)
			assert_true(_has_scarce_price(c.deal) or (c.risk_percent >= 25 and _has_scarce_price(c.risk_deal)),
					"%s: costs gold, max HP, an item, a curse or a fight (no free lunch)" % where)
			# Healing must not be free: a heal comes with a price that is not just HP.
			if c.deal.heal_percent > 0:
				assert_true(_has_scarce_price(c.deal), "%s: a heal is paid for" % where)
			for deal: ZoneOfferData in [c.deal, c.risk_deal]:
				if deal == null:
					continue
				assert_false(deal.cost_item == ZoneOfferData.ItemCost.CHOSEN and deal.cost_max_hp_percent > 0
						and deal.cost_max_hp_target == ZoneOfferData.HpTarget.CHOSEN, "%s: one pick at most" % where)
				assert_false(deal.cost_item != ZoneOfferData.ItemCost.NONE and deal.cost_rotten != null,
						"%s: an item and a curse together could not be checked up front" % where)
				if deal.cost_rotten != null:
					assert_true(deal.cost_rotten.rotten, "%s: a curse is a rotten item" % where)
				if deal.ambush != null:
					assert_false(deal.ambush.boss or deal.ambush.mini_boss, "%s: no boss ambush" % where)
					assert_not_null(deal.ambush.deep, "%s: the ambush has a deep version for act 2" % where)
					assert_false(deal.ambush.enemies.is_empty())
			if c.risk_deal != null:
				assert_eq(c.risk_deal.pick_kind(), ZoneOfferData.Pick.NONE, "%s: a risk asks nobody" % where)
	assert_gte(count, 16, "the eight old events and eight new ones")


func test_the_acts_have_their_own_event_lists_and_ambushes() -> void:
	var run := _run()
	var first := run.act_data(0)
	var second := run.act_data(1)
	var in_first := {}
	var shared := 0
	for event: EventData in first.events:
		assert_false(in_first.has(event.id), "%s listed twice" % event.id)
		in_first[event.id] = true
	var in_second := {}
	for event: EventData in second.events:
		assert_false(in_second.has(event.id), "%s listed twice" % event.id)
		in_second[event.id] = true
		if in_first.has(event.id):
			shared += 1
	assert_gte(first.events.size(), 8)
	assert_gte(second.events.size(), 8)
	assert_gt(shared, 0, "some events are shared")
	assert_lt(shared, second.events.size(), "act 2 has events of its own")
	var used := {}
	for id: String in in_first:
		used[id] = true
	for id: String in in_second:
		used[id] = true
	for file: String in DirAccess.get_files_at(EVENTS_DIR):
		if file.ends_with(".tres"):
			assert_true(used.has(file.get_basename()), "%s is in an act's list" % file)
	for act: ActData in run.acts():
		assert_gte(act.ambushes.size(), 3, "%s has ambush fights" % act.id)
		for encounter: EncounterData in act.ambushes:
			assert_false(encounter.boss or encounter.mini_boss or encounter.elite, "%s: an ordinary fight" % encounter.id)
			assert_not_null(encounter.deep, "%s has a deep version" % encounter.id)
		assert_false(act.ambush_text.is_empty())
	# Every encounter an act's events can spring must resolve from a saved id.
	for act: ActData in run.acts():
		for event: EventData in act.events:
			for c: EventChoiceData in event.choices:
				for deal: ZoneOfferData in [c.deal, c.risk_deal]:
					if deal != null and deal.ambush != null:
						assert_not_null(run._find_ambush(deal.ambush.id), "%s can be found by id" % deal.ambush.id)


func test_ambush_encounters_are_picked_and_fought_in_the_deep_version_late() -> void:
	var run := _run()
	var pool := run.act_data(0).ambushes
	run.ambush_id = pool[0].id
	assert_eq(run.ambush_encounter(), pool[0])
	run.act = 1
	assert_eq(run.ambush_encounter(), pool[0].deep)


# --- the bot ------------------------------------------------------------------------------------------------------------

const FIT := Vector3i(100, 100, 5)
const HURT := Vector3i(30, 45, 5)


func test_the_bot_avoids_max_hp_costs_when_hurt() -> void:
	var run := _run()
	var mask := _event("whispering_mask")
	var wear := mask.choices[0]
	assert_gte(EventAutoplay.net_worth(run, wear, FIT), 0, "healthy, a fair price for 90 XP each")
	assert_eq(EventAutoplay.net_worth(run, wear, HURT), -1, "no permanent max HP while a hero is hurt")
	var tithe := _event("tithe_collector").choices[1]
	assert_eq(EventAutoplay.net_worth(run, tithe, HURT), -1)
	assert_gte(EventAutoplay.net_worth(run, tithe, FIT), 0, "healthy, a fair blood price is fine")


func test_the_bot_takes_a_curse_only_for_a_big_reward() -> void:
	var run := _run()
	var purse := _event("gamblers_bones").choices[1]
	assert_eq(EventAutoplay.net_worth(run, purse, FIT), -1, "60 gold is not worth a curse")
	var smash := _event("black_mirror").choices[1]
	assert_eq(EventAutoplay.net_worth(run, smash, FIT), -1, "90 gold is not worth a curse")
	var silver := _event("drowned_chapel").choices[1]
	assert_gte(EventAutoplay.net_worth(run, silver, FIT), 0, "120 gold is")
	assert_eq(EventAutoplay.decide(run, _event("drowned_chapel"), FIT).index, 1)


func test_the_bot_fights_an_ambush_choice_only_when_fit() -> void:
	var run := _run()
	var door := _event("sealed_door")
	assert_eq(EventAutoplay.net_worth(run, door.choices[0], HURT), -1)
	assert_gte(EventAutoplay.net_worth(run, door.choices[0], FIT), 0)
	assert_eq(EventAutoplay.decide(run, door, HURT).index, -1, "hurt, with an empty pack: leave")
	assert_eq(EventAutoplay.decide(run, door, FIT).index, 0, "fit: break the seal")
	var salve := run.add_item(_item(run, "salve"))
	var picked := EventAutoplay.decide(run, door, FIT)
	assert_eq(picked.index, 1, "with something to spare, the quiet way pays better")
	assert_eq(picked.pick, salve)
	assert_eq(EventAutoplay.decide(run, door, HURT).index, 1, "hurt: the quiet way is still open")


func test_the_bot_pays_max_hp_from_the_healthiest_hero_and_leaves_what_it_cannot_pay() -> void:
	var run := _run()
	run.hp[0] = 1
	var pick := EventAutoplay.pick_for(run, _event("whispering_mask").choices[0].deal)
	assert_ne(pick, 0, "never the wounded one")
	assert_true(run.pick_fits(_event("whispering_mask").choices[0].deal, pick))
	var poor := EventAutoplay.decide(run, _event("gamblers_bones"), FIT)
	assert_ne(poor.index, 0, "it cannot pay the stake")
	assert_eq(EventAutoplay.decide(run, null, FIT).index, -1)


func test_the_bot_hands_over_the_cheapest_item() -> void:
	var run := _run()
	var key := run.add_item(_item(run, "key"))
	var idol := run.add_item(_item(run, "golden_idol"))
	var pick := EventAutoplay.pick_for(run, _event("bone_collector").choices[0].deal)
	assert_true(run.losable_uids().has(pick))
	assert_eq(pick, key, "the key is worth less than the idol")
	assert_ne(pick, idol)
