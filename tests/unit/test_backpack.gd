extends GutTest
## The pack (DESIGN.md 8.1, 8.19, card #282): Alder's pack with pockets, one item each whatever
## its shape; the first free pocket; items go and come back the same as plain data, and an old grid
## save turns into pockets; the run's ops (move, drop, use, gear swaps) work and refuse what no
## longer fits; treasure turns into gold; finds and drops are seeded; the shipped items, icons and
## glinting spots are sound; the party screen settles what is in hand. Uses the shipped run with Tuning.new() for the rules (every Relic slot open: the slots
## have their own tests in test_relics.gd).

const Fx := preload("res://tests/helpers/combat_fixtures.gd")
const RUN_PATH := "res://data/runs/rotten_road.tres"

var _tuning := Fx.all_slots()
var _data: RunData


func before_all() -> void:
	_data = load(RUN_PATH) as RunData


func _shape(cells: Array[Vector2i]) -> ItemData:
	var item := ItemData.new()
	item.id = "test_%d" % cells.size()
	item.shape = cells
	return item


func _run(seed_value: int = 7) -> RunState:
	return RunState.begin(_data, _tuning, seed_value)


func _by_id(items: Array) -> Dictionary:
	var d := {}
	for item: ItemData in items:
		d[item.id] = item
	return d


# --- the pockets ------------------------------------------------------------------------------

func test_every_item_takes_one_pocket_whatever_its_shape() -> void:
	var pack := Backpack.new(6)
	var loaf := _shape([Vector2i(0, 0), Vector2i(1, 0)])
	var ell := _shape([Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)])
	assert_eq(pack.cell_count(), 6, "six pockets")
	var a := pack.add(loaf, 0)
	var b := pack.add(ell, 1)
	assert_gte(a, 0)
	assert_gte(b, 0)
	assert_eq(pack.free_cells(), 4, "one pocket each")
	assert_eq(pack.uid_at(Vector2i(1, 0)), b)
	assert_eq(pack.uid_at(Vector2i(2, 0)), -1)
	assert_eq(pack.add(loaf, 1), -1, "one item per pocket")
	assert_false(pack.fits(loaf, 6), "no seventh pocket")
	assert_false(pack.fits(loaf, 2, 1), "pockets are one row")
	assert_true(pack.move(a, 5))
	assert_true(pack.move(a, 5), "it may stay in its own pocket")
	assert_false(pack.move(a, 1), "a taken pocket")
	assert_eq(pack.remove(a), loaf)
	assert_eq(pack.free_cells(), 5)


func test_find_spot_is_the_first_free_pocket() -> void:
	var pack := Backpack.new(2)
	var one := _shape([Vector2i(0, 0), Vector2i(0, 1)])
	assert_eq(pack.find_spot(one), {"x": 0, "y": 0, "turn": 0})
	assert_gte(pack.add_anywhere(one), 0)
	assert_eq(pack.find_spot(one), {"x": 1, "y": 0, "turn": 0})
	assert_gte(pack.add_anywhere(one), 0)
	assert_eq(pack.add_anywhere(one), -1, "full")


func test_backpack_round_trips_as_plain_data() -> void:
	var a := _shape([Vector2i(0, 0)])
	var b := _shape([Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)])
	b.id = "ell"
	var pack := Backpack.new(6)
	pack.add(a, 5)
	pack.add(b, 0, 0, 0, 2)
	var data := pack.to_array()
	var copy := Backpack.from_array(data, _by_id([a, b]))
	assert_not_null(copy)
	assert_eq(copy.to_array(), data)
	assert_eq(RunState.level_of(copy.entries[1]), 2)
	assert_null(Backpack.from_array(data, _by_id([a])), "unknown item")
	var bad := data.duplicate(true)
	(bad[3] as Array).append([9, "test_1", 5, 0, 0])
	assert_null(Backpack.from_array(bad, _by_id([a, b])), "two items in one pocket")
	assert_null(Backpack.from_array("junk", {}), "malformed")


func test_an_old_grid_save_turns_into_pockets() -> void:
	var salve := _shape([Vector2i(0, 0)])
	salve.id = "salve"
	var feast := _shape([Vector2i(0, 0), Vector2i(1, 0)])
	feast.id = "feast"
	var key := _shape([Vector2i(0, 0), Vector2i(1, 0)])
	key.id = "key"
	var by_id := _by_id([salve, feast, key])
	# Phase 11 to 20: a 4 x 5 grid; items anywhere, turned.
	var old := [4, 5, 9, [[1, "salve", 2, 3, 0, 1], [2, "feast", 0, 0, 0, 0], [3, "key", 1, 4, 1]]]
	var pack := Backpack.from_array(old, by_id, 6)
	assert_not_null(pack, "an old save still loads")
	assert_eq(pack.width, 6)
	assert_eq(pack.rows, 1)
	assert_eq(pack.uid_at(Vector2i(0, 0)), 2, "top row first")
	assert_eq(pack.uid_at(Vector2i(1, 0)), 1)
	assert_eq(pack.uid_at(Vector2i(2, 0)), 3)
	assert_eq(RunState.level_of(pack.entry(1)), 1, "a combined item stays combined")
	assert_eq(pack.next_uid, 9)
	var bigger := Backpack.from_array([4, 7, 2, []], by_id, 6)
	assert_eq(bigger.width, 8, "each Bigger Pack row became a pocket")
	var crowded: Array = []
	for i: int in 9:
		crowded.append([i + 1, "salve", i % 4, i / 4, 0, 0])
	var full := Backpack.from_array([4, 5, 10, crowded], by_id, 6)
	assert_eq(full.width, 9, "nothing is lost: a crowded old pack gets a pocket for each item")
	assert_eq(full.free_cells(), 0)


# --- the run ----------------------------------------------------------------------------------

func test_a_run_starts_with_an_empty_backpack_of_the_tuned_size() -> void:
	var run := _run()
	assert_eq(_tuning.backpack_pockets, 6)
	assert_eq(run.backpack.width, _tuning.backpack_pockets)
	assert_eq(run.backpack.rows, 1)
	assert_eq(run.backpack.entries.size(), 0)


func test_ops_change_the_backpack_and_refuse_what_no_longer_fits() -> void:
	var run := _run()
	var salve := run.items_by_id()["salve"] as ItemData
	var feast := run.items_by_id()["feast"] as ItemData
	var a := run.place_item(salve, 0)
	var b := run.place_item(feast, 2)
	assert_true(run.apply_op({"op": "move", "uid": a, "x": 5, "y": 0, "turn": 0}))
	assert_eq(run.backpack.uid_at(Vector2i(5, 0)), a)
	assert_false(run.apply_op({"op": "move", "uid": a, "x": 2, "y": 0, "turn": 0}), "onto the feast")
	assert_false(run.apply_op({"op": "move", "uid": a, "x": "far"}), "malformed")
	run.hp[0] = 1
	assert_true(run.apply_op({"op": "use", "uid": a, "slot": 0}))
	assert_gt(run.hp[0], 1)
	assert_false(run.apply_op({"op": "use", "uid": a, "slot": 0}), "used up: a second ask is too late")
	assert_true(run.apply_op({"op": "drop", "uid": b}))
	assert_eq(run.backpack.entries.size(), 0)
	run.wear(0, 0, run.data.gear[0])
	assert_true(run.apply_op({"op": "swap_gear", "from": [0, 0], "to": [1, 2]}))
	assert_eq(run.gear[1][2], run.data.gear[0])
	assert_false(run.apply_op({"op": "swap_gear", "from": [0, 0], "to": [1, 2]}), "nothing left to move")
	assert_false(run.apply_op({"op": "swap_gear", "from": [0], "to": [1, 2]}), "malformed")
	assert_false(run.apply_op({"op": "nonsense"}))


func test_the_backpack_goes_over_the_network() -> void:
	var run := _run()
	run.place_item(run.data.shop_items[1], 1)
	var copy := RunState.from_dict(run.data, _tuning, run.to_dict())
	assert_not_null(copy)
	assert_eq(copy.backpack.to_array(), run.backpack.to_array())


func test_finds_and_drops_are_seeded() -> void:
	var run := _run(11)
	assert_eq(run.spot_item(3, 1), _run(11).spot_item(3, 1), "same seed, same find")
	assert_true(run.data.found_items.has(run.spot_item(3, 1)))
	var picks := {}
	for stop: int in 40:
		picks[run.spot_item(stop, 0)] = true
	assert_gt(picks.size(), 1, "spots hold different things")
	run.tuning = Tuning.new()
	run.tuning.item_drop_percent = 0
	for roamer: int in 10:
		assert_null(run.drop_for(2, roamer), "0%: never")
	run.tuning.item_drop_percent = 100
	for roamer: int in 10:
		assert_not_null(run.drop_for(2, roamer), "100%: always")
	assert_eq(run.drop_for(2, 3), run.drop_for(2, 3))


# --- shipped data -----------------------------------------------------------------------------

func test_shipped_items_are_sound() -> void:
	var all := _run().items_by_id()
	assert_gte(all.size(), 3)
	for item: ItemData in all.values():
		assert_false(item.shape.is_empty(), "%s has a shape" % item.id)
		var seen := {}
		for c: Vector2i in item.shape:
			assert_false(seen.has(c), "%s: no cell twice" % item.id)
			seen[c] = true
			assert_true(c.x >= 0 and c.y >= 0, "%s: cells from the top-left" % item.id)
		assert_true(FileAccess.file_exists(item.icon_path), "%s has its icon" % item.id)
		if not item.rotten:
			assert_gt(item.price, 0, "%s has a price" % item.id)
	for item: ItemData in _data.found_items:
		# Curses come only from events, and the faded charms (phase 17) only from older saves.
		var never_found := item.is_curse() or (item.kind == ItemData.Kind.TREASURE and item.display_name.begins_with("Faded "))
		if never_found:
			assert_eq(item.find_weight, 0, "%s is never found" % item.id)
		else:
			assert_gt(item.find_weight, 0, "%s can be found" % item.id)


func test_zone_spots_stand_where_the_leader_can_reach() -> void:
	for layout: ZoneData in _data.zones:
		# A long zone is laid out anew each visit (DESIGN.md 8.5): check a few visits.
		for seed_value: int in [1, 2, 3]:
			_check_spots(ZoneAssembler.assemble(layout, seed_value))


func _check_spots(zone: ZoneData) -> void:
	assert_gte(zone.item_spots.size(), 2, "%s has glinting spots" % zone.id)
	var obstacles := ZoneMotion.obstacles(zone)
	for spot: Vector3 in zone.item_spots:
		var at := Vector2(spot.x, spot.z)
		var free := ZoneMotion.move(at, Vector2.ZERO, ZoneController.LEADER_RADIUS, obstacles, zone.bounds_min,
				zone.bounds_max)
		assert_almost_eq(free.distance_to(at), 0.0, 0.01, "%s spot %s is free" % [zone.id, at])


# --- the party screen -------------------------------------------------------------------------

func test_a_new_relic_in_hand_is_worn_by_someone_with_room() -> void:
	var run := _run()
	var screen := PartyScreen.new()
	add_child_autofree(screen)
	screen.setup(run, "", {"gear": run.data.gear[0]})
	assert_true(screen.holding_new())
	screen.auto_settle()
	assert_false(screen.holding_new())
	assert_true(run.is_worn(run.data.gear[0]), "worn by someone with room")


func test_a_find_with_no_room_is_left_behind() -> void:
	var run := _run()
	var salve := run.items_by_id()["salve"] as ItemData
	while run.add_item(salve) >= 0:
		pass
	var screen := PartyScreen.new()
	add_child_autofree(screen)
	screen.setup(run, "", {"item": salve})
	watch_signals(screen)
	screen.auto_settle()
	assert_signal_emitted_with_parameters(screen, "left_behind", [salve])
	assert_eq(run.backpack.free_cells(), 0)


# --- step 2: rarity, keys, chests, selling ----------------------------------------------------

func test_deeper_rows_turn_up_rarer_things() -> void:
	var run := _run()
	assert_eq(run.rarity_weight(100, ItemData.Rarity.COMMON, 6), 100)
	assert_gt(run.rarity_weight(100, ItemData.Rarity.RARE, 6), run.rarity_weight(100, ItemData.Rarity.RARE, 0))
	assert_gt(run.rarity_weight(100, ItemData.Rarity.LEGENDARY, 6), run.rarity_weight(100, ItemData.Rarity.LEGENDARY, 0))


func test_keys_open_chests_once_and_chests_hold_rare_things() -> void:
	var run := _run()
	assert_false(run.has_key())
	assert_false(run.use_key(), "no key, no chest")
	run.add_item(run.items_by_id()["key"])
	assert_true(run.has_key())
	assert_true(run.use_key())
	assert_false(run.has_key(), "the key is used up")
	for stop: int in 30:
		var prize := run.chest_contents(stop)
		assert_not_null(prize)
		assert_gte(int(prize.get("rarity")), ItemData.Rarity.RARE, "chests hold rare or better")
		assert_eq(run.chest_contents(stop), prize, "seeded")


func test_selling_pays_and_removes() -> void:
	var run := _run()
	var bomb := run.items_by_id()["bomb"] as ItemData
	var uid := run.add_item(bomb)
	run.gold = 0
	assert_true(run.apply_op({"op": "sell", "uid": uid}))
	assert_eq(run.gold, CombatMath.percent(bomb.price, _tuning.item_sell_percent))
	assert_false(run.backpack.has_uid(uid))
	assert_false(run.apply_op({"op": "sell", "uid": uid}), "already sold")


func test_zones_have_reachable_chests() -> void:
	for layout: ZoneData in _data.zones:
		var most := 0
		for seed_value: int in range(1, 9):
			var zone := ZoneAssembler.assemble(layout, seed_value)
			most = maxi(most, zone.chests.size())
			for chest: Vector3 in zone.chests:
				var at := Vector2(chest.x, chest.z)
				var free := ZoneMotion.move(at, Vector2.ZERO, ZoneController.LEADER_RADIUS, ZoneMotion.obstacles(zone),
						zone.bounds_min, zone.bounds_max)
				assert_almost_eq(free.distance_to(at), 0.0, 0.01, "%s chest is free" % zone.id)
		assert_gt(most, 0, "%s has a locked chest on some visits" % layout.id)


# --- step 3: curses, rot, combining, a bigger backpack (charms are gone since phase 17) ----------

func _item_of(run: RunState, id: String) -> ItemData:
	return run.items_by_id()[id] as ItemData


func test_treasure_turns_into_gold_at_once_and_takes_no_pocket() -> void:
	var run := _run()
	run.gold = 0
	var ring := _item_of(run, "silver_ring")
	assert_eq(ring.kind, ItemData.Kind.TREASURE)
	assert_eq(run.add_item(ring), 0, "taken, not packed")
	assert_eq(run.gold, CombatMath.percent(ring.price, _tuning.item_sell_percent), "what selling it paid")
	assert_eq(run.backpack.entries.size(), 0)
	assert_eq(run.find_text(ring), "Silver Ring: +%d gold" % run.treasure_gold(ring))
	assert_eq(run.find_text(_item_of(run, "salve")), "Found: Salve")


func test_the_old_charms_are_gone() -> void:
	# Phase 17 faded them to treasure; phase 21 (card #282) deleted them.
	for id: String in ["ember_stone", "iron_stone", "lodestone", "knucklebone", "wolf_tooth", "bone_totem", "heartleaf",
			"wake_root", "rain_pouch"]:
		assert_false(ResourceLoader.exists("res://data/items/%s.tres" % id), "%s is gone" % id)
		assert_false(_run().items_by_id().has(id))


func test_curses_drain_in_fights_and_never_sell() -> void:
	var run := _run()
	var curse := _item_of(run, "rotting_heart")
	assert_true(curse.is_curse() and curse.rotten)
	var power_before := run.power_percent(0)
	var heart := run.place_item(curse, 0, 0, 0)
	assert_eq(run.rot_percent(), 3)
	assert_eq(run.power_percent(0), power_before, "a curse only hurts")
	var setup := run.fight_setup(load("res://data/encounters/husk_fight.tres") as EncounterData, 3,
			CombatSetup.Opening.FIRST_STRIKE)
	assert_eq(int(setup.party_passives[0].get(Passive.ROT, 0)), 3)
	var engine := CombatEngine.new(setup)
	var events := engine.start()
	var rot := events.filter(func(ev: Dictionary) -> bool: return String(ev.type) == "damage" and String(ev.cause) == "rot")
	assert_gt(rot.size(), 0, "the first hero to act loses HP to the rot")
	assert_eq(run.sell_item(heart), -1, "nobody buys rot")


func test_rot_never_downs_a_hero() -> void:
	var run := _run()
	run.place_item(_item_of(run, "rotting_heart"), 0, 0, 0)
	for slot: int in run.party_size():
		run.hp[slot] = 1
	var engine := CombatEngine.new(run.fight_setup(load("res://data/encounters/husk_fight.tres") as EncounterData, 3,
			CombatSetup.Opening.FIRST_STRIKE))
	engine.start()
	for id: int in engine.party_ids():
		assert_eq(engine.get_combatant(id).hp, 1)


func test_two_of_the_same_combine_into_a_stronger_one() -> void:
	var run := _run()
	var salve := _item_of(run, "salve")
	var a := run.place_item(salve, 0)
	var b := run.place_item(salve, 1)
	var tonic := run.place_item(_item_of(run, "tonic"), 3)
	assert_false(run.can_combine(a, tonic), "different items")
	assert_true(run.apply_op({"op": "combine", "uid": a, "into": b}))
	assert_false(run.backpack.has_uid(a))
	var e := run.backpack.entry(b)
	assert_eq(RunState.level_of(e), 1)
	assert_eq(RunState.entry_name(e), "Salve+")
	assert_eq(RunState.entry_rarity(e), ItemData.Rarity.RARE)
	assert_eq(run.entry_amount(e), CombatMath.percent(salve.amount_percent, 100 + _tuning.combine_bonus_percent))
	var c := run.place_item(salve, 0)
	assert_false(run.can_combine(c, b), "only the same level")
	run.hp[0] = 1
	run.use_item(b, 0)
	assert_eq(run.hp[0], 1 + CombatMath.percent(run.max_hp(0), run.entry_amount(e)), "a combined salve heals more")


func test_combining_stops_at_legendary_and_keys_never_combine() -> void:
	var run := _run()
	var gem := _item_of(run, "rot_gem")
	assert_false(gem.combinable(), "treasure does not combine")
	var key := _item_of(run, "key")
	var a := run.place_item(key, 0)
	var b := run.place_item(key, 1)
	assert_false(run.can_combine(a, b))
	var salts := _item_of(run, "smelling_salts")
	var s1 := run.place_item(salts, 2, 0, 0, 1)
	var s2 := run.place_item(salts, 3, 0, 0, 1)
	assert_false(run.can_combine(s1, s2), "rare + 1 level is legendary already")


func test_levels_go_over_the_network() -> void:
	var run := _run()
	run.place_item(_item_of(run, "salve"), 2, 0, 0, 2)
	var copy := RunState.from_dict(run.data, _tuning, run.to_dict())
	assert_eq(RunState.level_of(copy.backpack.entries[0]), 2)


func test_a_bigger_pack_adds_a_pocket_up_to_the_max() -> void:
	var run := _run()
	var pack := _item_of(run, "bigger_pack")
	assert_true(run.wants(pack))
	assert_gte(run.add_item(pack), 0, "used at once")
	assert_eq(run.backpack.width, _tuning.backpack_pockets + 1)
	assert_eq(run.backpack.entries.size(), 0, "it is not kept")
	assert_eq(run.find_text(pack), "Bigger Pack: %d pockets" % (_tuning.backpack_pockets + 1))
	while run.backpack.width < _tuning.backpack_max_pockets:
		run.add_item(pack)
	assert_false(run.wants(pack), "no use any more")
	assert_false(run.take_upgrade(pack))
	assert_eq(run.backpack.width, _tuning.backpack_max_pockets)


func test_shops_and_finds_never_offer_curses_or_faded_charms() -> void:
	var run := _run()
	for stop: int in 30:
		for item: ItemData in run.shop_stock(stop):
			assert_false(item.is_curse(), "no curse on the shelves")
			assert_ne(item.find_weight == 0 and item.kind == ItemData.Kind.TREASURE, true, "no faded charm on the shelves")
	for item: ItemData in run.data.found_items:
		if item.is_curse():
			assert_eq(item.find_weight, 0, "%s: curses come only from events" % item.id)


func test_the_pack_art_exists() -> void:
	var visuals := load("res://data/presentation/combat_visuals.tres") as CombatVisuals
	assert_true(ResourceLoader.exists(visuals.backpack_art_path), "Alder's open pack")


func test_the_bag_tab_puts_a_new_find_in_a_free_pocket_or_swaps_it() -> void:
	var run := _run()
	var salve := _item_of(run, "salve")
	var bomb := _item_of(run, "bomb")
	for i: int in run.backpack.width:
		run.add_item(bomb)
	var screen := PartyScreen.new()
	add_child_autofree(screen)
	screen.setup(run, "", {"item": salve})
	var tab := screen.tab_node(PartyScreen.Tab.BAG) as BagTab
	assert_true(tab.holding_new())
	assert_eq(tab.info().chips.size() >= 2, true)
	assert_true(String(tab.info().chips[1][1]).begins_with("Swap"), "a full pack offers a swap")
	tab.handle_input(_press(&"menu_confirm"))
	assert_true(tab.busy(), "asked first")
	assert_true(tab.holding_new())


func _press(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event
