extends GutTest
## Phase 15 run stops and acts (DESIGN.md 8.6 to 8.11): the map's new stops and their rules, two
## acts with their own maps and bosses, elite fights, events, treasure, the shop's services, the
## campfire's choices, and that a client can follow the host across an act. Uses the shipped run.

const RUN_PATH := "res://data/runs/rotten_road.tres"
const SEEDS: int = 30

var _data: RunData
var _tuning: Tuning


func before_all() -> void:
	_data = load(RUN_PATH) as RunData
	_tuning = load("res://data/tuning/tuning.tres") as Tuning


func _run(seed_value: int = 7) -> RunState:
	return RunState.begin(_data, _tuning, seed_value)


# --- the map ----------------------------------------------------------------------------------

func test_new_stops_follow_their_rules() -> void:
	var seen := {}
	for s: int in range(1, SEEDS):
		var map := RunMap.generate(CombatRng.new(s), _tuning, 3)
		# The treasure row is all treasure, within run_treasure_row_spread of run_treasure_row (card #286).
		var treasure_rows: Array[int] = []
		for r: int in map.row_count():
			var all_treasure := true
			for id: int in map.rows[r]:
				all_treasure = all_treasure and int(map.stop(id).type) == RunMap.StopType.TREASURE
			if all_treasure:
				treasure_rows.append(r)
		assert_eq(treasure_rows.size(), 1, "seed %d: one treasure row" % s)
		if treasure_rows.size() == 1:
			assert_lte(absi(treasure_rows[0] - _tuning.run_treasure_row), _tuning.run_treasure_row_spread)
		# No Guard stops: since map rules 4 a place's guard waits at an Elite stop (DESIGN.md 8.22).
		assert_eq(map.count_type(RunMap.StopType.GUARD), 0, "seed %d: no Guard stops" % s)
		for st: Dictionary in map.stops:
			var type := int(st.type)
			seen[type] = true
			if type == RunMap.StopType.ELITE:
				assert_gte(int(st.row), _tuning.run_elite_min_row, "seed %d: no elite too early" % s)
				for p: int in st.prev:
					assert_ne(int(map.stop(p).type), RunMap.StopType.ELITE, "seed %d: never two elites in a row" % s)
		if is_failing():
			return
	for type: int in [RunMap.StopType.ELITE, RunMap.StopType.EVENT, RunMap.StopType.TREASURE, RunMap.StopType.SHOP,
			RunMap.StopType.REST, RunMap.StopType.FIGHT, RunMap.StopType.FINAL]:
		assert_true(seen.has(type), "%s stops turn up" % RunMap.TYPE_NAMES[type])


func test_planning_sees_every_stop_a_choice_leads_to() -> void:
	var run := _run()
	var first := run.choices()[0]
	var ahead := MapScreen.reachable_from(run.map, first)
	assert_true(ahead.has(first))
	assert_true(ahead.has(run.map.final_id()), "every road leads to the boss")
	for id: int in ahead:
		for n: int in run.map.stop(id).next:
			assert_true(ahead.has(n))


# --- acts -------------------------------------------------------------------------------------

func test_the_run_has_three_acts_with_their_own_places_and_bosses() -> void:
	var run := _run()
	assert_eq(run.acts().size(), 3, "three acts (card #323, DESIGN.md 8.23)")
	# One place per act, in the story's order: forests to husks, rivers to bog, cities to ash.
	var places := ["rotten_hollow", "sunken_bog", "ashen_ruins"]
	var bosses := ["husk_lord_fight", "leech_queen_fight", "hollow_king"]
	var seen_bosses := {}
	for i: int in run.acts().size():
		var act := run.act_data(i)
		assert_eq(act.zones.size(), 1, "%s is one place" % act.id)
		assert_eq(act.zones[0].id, places[i], "%s is in its place" % act.id)
		assert_eq(act.final_encounter.id, bosses[i], "%s's boss" % act.id)
		assert_true(act.final_encounter.boss, "%s ends on a boss" % act.id)
		assert_false(seen_bosses.has(act.final_encounter.id), "each act has its own boss")
		seen_bosses[act.final_encounter.id] = true
		assert_eq(act.deep, i == 2, "only the last act holds the variants")
		assert_not_null(act.final_look, "%s has its boss's lair" % act.id)
	assert_eq(run.act_data(2).final_encounter, _data.final_encounter, "the Hollow King ends the run")
	assert_eq(run.act_data(1).final_look.resource_path, "res://data/looks/leech_lair.tres", "the Queen's own lair")
	for act: ActData in run.acts():
		assert_false(act.zones.is_empty(), "%s has places" % act.id)
		assert_false(act.elites.is_empty(), "%s has elite fights" % act.id)
		assert_false(act.events.is_empty(), "%s has events" % act.id)
		assert_false(act.final_map_icon_path.is_empty())


func test_next_act_brings_a_new_map_heals_and_goes_deeper() -> void:
	var run := _run()
	var first_map := var_to_str(run.map.stops)
	run.hp[0] = 1
	var hp_before := run.enemy_hp_percent()
	assert_true(run.next_act())
	assert_eq(run.act, 1)
	assert_ne(var_to_str(run.map.stops), first_map, "a new map")
	assert_eq(run.hp[0], 1 + CombatMath.percent(run.max_hp(0), _tuning.run_act_heal_percent))
	assert_false(run.is_deep(), "the second act (the Drowned Mire) starts plain")
	run.go(run.choices()[0])
	assert_gt(run.enemy_hp_percent(), hp_before, "enemies keep growing in the next act")
	var second_hp := run.enemy_hp_percent()
	assert_false(run.is_last_act())
	assert_true(run.next_act())
	assert_eq(run.act, 2)
	assert_true(run.is_deep(), "the third act holds the variants")
	assert_true(run.is_last_act())
	run.go(run.choices()[0])
	assert_gt(run.enemy_hp_percent(), second_hp, "and again in the third")
	assert_false(run.next_act(), "no act after the last")


func test_a_client_follows_the_host_into_the_next_act() -> void:
	var host := _run(11)
	host.go(host.choices()[0])
	host.next_act()
	host.go(host.choices()[0])
	var client := RunState.from_dict(_data, _tuning, host.to_dict())
	assert_not_null(client)
	assert_eq(client.act, 1)
	assert_eq(var_to_str(client.map.stops), var_to_str(host.map.stops), "the same act map on both")
	assert_eq(client.to_dict(), host.to_dict())


# --- elites, events, treasure ---------------------------------------------------------------------

func test_elites_are_tougher_and_pay_more() -> void:
	var run := _run()
	var elite := run.act_data().elites[0]
	assert_true(elite.elite)
	var plain := EncounterData.new()
	plain.enemies = elite.enemies
	var a := run.fight_setup(plain, 1, CombatSetup.Opening.NORMAL)
	var b := run.fight_setup(elite, 1, CombatSetup.Opening.NORMAL)
	assert_eq(b.enemy_hp_percent, CombatMath.percent(a.enemy_hp_percent, _tuning.elite_hp_percent))
	assert_eq(b.enemy_power_percent, CombatMath.percent(a.enemy_power_percent, _tuning.elite_power_percent))
	assert_gt(run.gold_for(elite), run.gold_for(plain))


func test_guards_are_mini_bosses_with_a_phase_two() -> void:
	# Some Elite stops in a place fight its guard (DESIGN.md 8.22).
	for zone: ZoneData in _data.zones:
		var guard := zone.guard
		assert_not_null(guard, "%s has a guard" % zone.id)
		if guard == null:
			continue
		assert_true(guard.mini_boss and not guard.can_run, "%s: its guard is a mini-boss, no running" % zone.id)
		assert_gt(guard.enemies[0].phase_two_hp_percent, 0, "%s: the guard has a phase two" % zone.id)
		assert_not_null(guard.deep, "%s: its guard has a deep version" % zone.id)
		if guard.deep != null:
			assert_true(guard.deep.mini_boss and not guard.deep.can_run, "%s: so is its deep version" % zone.id)


## Act 1 lets tuning.run_spoils_open_cards of them be any rarity (DESIGN.md 8.25); later acts none.
func test_spoils_are_rare_while_the_run_has_rare_gear() -> void:
	var run := _run()
	run.go(run.choices()[0])
	for act: int in [0, 1]:
		run.act = act
		var low := 0
		for gear: GearData in run.loot_choices(run.at):
			if int(gear.rarity) < _tuning.run_spoils_min_rarity:
				low += 1
		assert_lte(low, run.spoils_open_cards(run.is_crowned()), "act %d" % (act + 1))


func test_an_event_never_comes_twice() -> void:
	var run := _run(3)
	var met := {}
	var pool := run.act_data().events.size()
	for i: int in pool:
		var at := run.map.stops.size() - 2 - i
		var event := run.event_of(at)
		assert_false(met.has(event.id), "event %s met twice" % event.id)
		met[event.id] = true
		run.events_seen.append(event.id)
	assert_eq(met.size(), pool)


func test_an_event_choice_pays_gives_and_risks_the_same_way_every_time() -> void:
	var event := load("res://data/events/gamblers_bones.tres") as EventData
	var roll := event.choices[0]
	var a := _run(5)
	a.gold = 200
	var b := _run(5)
	b.gold = 200
	var ra := a.choose_event(roll, 4, 0)
	var rb := b.choose_event(roll, 4, 0)
	assert_true(bool(ra.ok))
	assert_eq(a.gold, b.gold, "seeded: the same luck on every machine")
	assert_eq(bool(ra.risk), bool(rb.risk))
	var scale := a.event_scale(4)
	var won := 200 - CombatMath.percent(roll.deal.cost_gold, scale) + CombatMath.percent(roll.deal.gold, scale)
	var lost := won - CombatMath.percent(roll.risk_deal.cost_gold, scale)
	assert_eq(a.gold, lost if bool(ra.risk) else won, "won the stake or lost it again (%d)" % a.gold)
	var poor := _run(5)
	poor.gold = 5
	assert_false(poor.can_choose(roll))
	assert_false(bool(poor.choose_event(roll, 4, 0).ok))
	assert_eq(poor.gold, 5)


func test_shipped_events_make_sense() -> void:
	var count := 0
	for file: String in DirAccess.get_files_at("res://data/events"):
		if not file.ends_with(".tres"):
			continue
		var event := load("res://data/events".path_join(file)) as EventData
		count += 1
		assert_false(event.title.is_empty())
		assert_false(event.text.is_empty())
		assert_false(event.choices.is_empty(), "%s has choices" % event.id)
		for c: EventChoiceData in event.choices:
			assert_not_null(c.deal, "%s: %s does something" % [event.id, c.text])
			if c.risk_percent > 0:
				assert_not_null(c.risk_deal, "%s: %s has a risk" % [event.id, c.text])
				assert_false(c.risk_text.is_empty())
	assert_gte(count, 8)


func test_the_plain_chest_is_rare_and_pays_gold() -> void:
	for id: int in _run().map.stops.size():
		var run := _run()
		var gold := run.gold
		var got := run.open_treasure(id, false)
		assert_true(got.prize is ItemData, "stop %d: the plain chest holds an item" % id)
		if got.prize is ItemData:
			assert_gte(int((got.prize as ItemData).rarity), ItemData.Rarity.RARE)
		assert_eq(run.gold, gold + _tuning.run_treasure_gold, "and pays its gold")


# --- shop services and the campfire ---------------------------------------------------------------

func test_shop_services() -> void:
	var run := _run()
	run.gold = 500
	var rotten: ItemData = null
	for item: ItemData in _data.found_items:
		if item.rotten:
			rotten = item
	assert_not_null(rotten, "the run has a curse")
	assert_eq(run.add_item(rotten), 0, "on the party")
	var gold := run.gold
	assert_true(run.cleanse(0, rotten.id, 1), "Cleanse lifts it")
	assert_true(run.curses.is_empty())
	assert_eq(run.gold, gold - run.cleanse_price())
	assert_false(run.cleanse(0, rotten.id, 1), "nothing left to lift")
	assert_false(run.has_method("upgrade_item"), "no Upgrade since card #332")
	run.go(run.choices()[0])
	var before := str(run.shop_stock(run.at)) + str(run.shop_gear(run.at))
	assert_true(run.restock())
	var after := str(run.shop_stock(run.at)) + str(run.shop_gear(run.at))
	assert_ne(after, before, "new wares after a restock")
	run.gold = 0
	assert_false(run.restock(), "no gold, no service")


func test_a_shop_stocks_a_few_items_not_the_whole_list() -> void:
	var run := _run()
	run.go(run.choices()[0])
	var stock := run.shop_stock(run.at)
	assert_eq(stock.size(), mini(_tuning.run_shop_items, _data.shop_items.size()))
	assert_eq(str(stock), str(run.shop_stock(run.at)), "the same stock while the party is there")
	var kinds := {}
	for id: int in run.map.stops.size():
		for item: ItemData in run.shop_stock(id):
			kinds[item.id] = true
	assert_gt(kinds.size(), _tuning.run_shop_items, "other shops stock other things")


func test_campfire_train_gives_points() -> void:
	var run := _run()
	var before := run.free_points(0)
	run.train()
	assert_eq(run.free_points(0), before + _tuning.rest_train_points)
	var client := RunState.from_dict(_data, _tuning, run.to_dict())
	assert_eq(client.free_points(0), run.free_points(0), "the points travel online")


func test_the_campfire_before_the_boss_offers_its_three_choices_as_cards() -> void:
	var run := _run()
	var fire := -1
	for r: int in range(run.map.row_count() - 2, 0, -1):
		var all_rest := true
		for id: int in run.map.rows[r]:
			all_rest = all_rest and int(run.map.stop(id).type) == RunMap.StopType.REST
		if all_rest:
			fire = int(run.map.rows[r][0])
			break
	assert_gte(fire, 0, "the act has a campfire row under the boss")
	run.at = fire
	assert_true(run.is_watch_fire())
	var rest := RestScreen.new()
	add_child_autofree(rest)
	rest.setup(run)
	var menu := rest.menu()
	assert_true(menu.horizontal, "side by side (card #288)")
	assert_eq(menu.items.map(func(row: Dictionary) -> String: return String(row.text)), ["Rest", "Keep watch", "Upgrade"],
			"Upgrade takes Sharpen's place (DESIGN.md 8.25)")
	for row: Dictionary in menu.items:
		assert_true(row.icon is Texture2D, "%s has a picture" % row.text)
	assert_eq(String((menu.items[2].chips as Array)[0].text), RestScreen.UPGRADE_CHIP)
	rest.watch_now()
	assert_eq(run.team_gauge, _tuning.team_gauge_max, "the bot's watch_now() still works")
	assert_false(menu.horizontal, "then one way on")
