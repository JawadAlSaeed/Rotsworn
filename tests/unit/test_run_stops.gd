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
		for st: Dictionary in map.stops:
			var type := int(st.type)
			seen[type] = true
			if int(st.row) == _tuning.run_treasure_row:
				assert_eq(type, RunMap.StopType.TREASURE, "seed %d: the treasure row is all treasure" % s)
			if type == RunMap.StopType.ELITE:
				assert_gte(int(st.row), _tuning.run_elite_min_row, "seed %d: no elite too early" % s)
				for p: int in st.prev:
					assert_ne(int(map.stop(p).type), RunMap.StopType.ELITE, "seed %d: never two elites in a row" % s)
		if is_failing():
			return
	for type: int in [RunMap.StopType.ELITE, RunMap.StopType.EVENT, RunMap.StopType.TREASURE, RunMap.StopType.SHOP,
			RunMap.StopType.REST, RunMap.StopType.ZONE, RunMap.StopType.FINAL]:
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

func test_the_run_has_two_acts_with_their_own_bosses() -> void:
	var run := _run()
	assert_eq(run.acts().size(), 2)
	assert_ne(run.act_data(0).final_encounter, run.act_data(1).final_encounter, "each act has its own boss")
	assert_true(run.act_data(0).final_encounter.boss)
	assert_true(run.act_data(1).deep, "the second act holds the variants")
	for act: ActData in run.acts():
		assert_false(act.zones.is_empty(), "%s has zones" % act.id)
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
	assert_true(run.is_deep())
	run.go(run.choices()[0])
	assert_gt(run.enemy_hp_percent(), hp_before, "enemies keep growing in the next act")
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


func test_guards_are_mini_bosses_and_champions_elites() -> void:
	for zone: ZoneData in _data.zones:
		var built := ZoneAssembler.assemble(zone, 3)
		for e: ZoneEnemyData in built.enemies:
			if e.guard:
				assert_true(e.encounter.mini_boss, "%s: the guard is a mini-boss" % zone.id)
				assert_false(e.encounter.can_run, "%s: no running from the guard" % zone.id)
				assert_gt(e.encounter.enemies[0].phase_two_hp_percent, 0, "%s: the guard has a phase two" % zone.id)
			if e.champion:
				assert_true(e.encounter.elite, "%s: a champion is an elite fight" % zone.id)


func test_spoils_are_rare_while_the_run_has_rare_gear() -> void:
	var run := _run()
	run.go(run.choices()[0])
	for gear: GearData in run.loot_choices(run.at):
		assert_gte(int(gear.rarity), _tuning.run_spoils_min_rarity)


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
	a.gold = 100
	var b := _run(5)
	b.gold = 100
	var ra := a.choose_event(roll, 4, 0)
	var rb := b.choose_event(roll, 4, 0)
	assert_true(bool(ra.ok))
	assert_eq(a.gold, b.gold, "seeded: the same luck on every machine")
	assert_eq(bool(ra.risk), bool(rb.risk))
	assert_true(a.gold == 140 or a.gold == 80, "won 60 or lost it again (%d)" % a.gold)
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


func test_treasure_is_rare_and_pays_gold() -> void:
	var run := _run()
	var found := 0
	for id: int in run.map.stops.size():
		var prize := run.treasure_contents(id)
		assert_not_null(prize)
		if prize is ItemData:
			assert_gte(int((prize as ItemData).rarity), ItemData.Rarity.RARE)
		found += 1
	var gold := run.gold
	assert_eq(run.take_treasure_gold(), _tuning.run_treasure_gold)
	assert_eq(run.gold, gold + _tuning.run_treasure_gold)


# --- shop services and the campfire ---------------------------------------------------------------

func _with(run: RunState, id: String) -> int:
	var item := run.items_by_id()[id] as ItemData
	return run.add_item(item)


func test_shop_services() -> void:
	var run := _run()
	run.gold = 500
	var rotten := ""
	for item: ItemData in _data.found_items:
		if item.rotten:
			rotten = item.id
	if not rotten.is_empty():
		var uid := _with(run, rotten)
		assert_true(run.rotten_uids().has(uid))
		assert_true(run.cleanse(uid))
		assert_false(run.backpack.has_uid(uid))
	var salve := _with(run, "salve")
	assert_true(run.can_upgrade(salve))
	var gold := run.gold
	assert_true(run.upgrade_item(salve, _tuning.shop_upgrade_price))
	assert_eq(RunState.level_of(run.backpack.entry(salve)), 1)
	assert_eq(run.gold, gold - _tuning.shop_upgrade_price)
	run.go(run.choices()[0])
	var before := str(run.shop_stock(run.at)) + str(run.shop_gear(run.at)) + str(run.shop_charms(run.at))
	assert_true(run.restock())
	var after := str(run.shop_stock(run.at)) + str(run.shop_gear(run.at)) + str(run.shop_charms(run.at))
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
