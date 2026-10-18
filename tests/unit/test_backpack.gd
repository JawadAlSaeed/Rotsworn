extends GutTest
## The backpack (DESIGN.md 8.1): shapes turn and stay in the grid; items never overlap; the first
## free place is found with any turn; items move, go and come back the same as plain data; the
## run's ops (move, drop, use, gear swaps) work and refuse what no longer fits; finds and drops are
## seeded; the shipped items, icons and glinting spots are sound; the party screen settles what is
## in hand. Uses the shipped run with Tuning.new() for the rules (every Relic slot open: the slots
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


# --- the grid ---------------------------------------------------------------------------------

func test_shapes_turn_clockwise_and_start_at_the_corner() -> void:
	var l: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)]
	var once := Backpack.turned(l, 1)
	once.sort()
	assert_eq(once, [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 0)] as Array[Vector2i])
	var tall: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1)]
	assert_eq(Backpack.extent(Backpack.turned(tall, 1)), Vector2i(2, 1), "a tall item lies down")
	var back := Backpack.turned(l, 4)
	back.sort()
	assert_eq(back, l, "four turns are no turn")


func test_items_stay_in_the_grid_and_never_overlap() -> void:
	var pack := Backpack.new(4, 5)
	var tall := _shape([Vector2i(0, 0), Vector2i(0, 1)])
	assert_false(pack.fits(tall, 0, 4, 0), "sticks out of the bottom")
	assert_false(pack.fits(tall, 3, 0, 1), "lying down, it sticks out of the side")
	var uid := pack.add(tall, 0, 0, 0)
	assert_gte(uid, 0)
	assert_eq(pack.add(tall, 0, 1, 0), -1, "overlaps")
	assert_eq(pack.uid_at(Vector2i(0, 1)), uid)
	assert_eq(pack.uid_at(Vector2i(1, 1)), -1)
	assert_eq(pack.free_cells(), 18)
	assert_true(pack.move(uid, 0, 3, 0))
	assert_true(pack.move(uid, 0, 2, 0), "it may move onto its own cells")
	assert_eq(pack.remove(uid), tall)
	assert_eq(pack.free_cells(), 20)


func test_find_spot_turns_items_to_fit() -> void:
	var pack := Backpack.new(2, 1)
	var tall := _shape([Vector2i(0, 0), Vector2i(0, 1)])
	assert_eq(pack.find_spot(tall), {"x": 0, "y": 0, "turn": 1}, "only fits lying down")
	assert_gte(pack.add_anywhere(tall), 0)
	assert_eq(pack.add_anywhere(_shape([Vector2i(0, 0)])), -1, "full")


func test_backpack_round_trips_as_plain_data() -> void:
	var a := _shape([Vector2i(0, 0)])
	var b := _shape([Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)])
	b.id = "ell"
	var pack := Backpack.new(4, 5)
	pack.add(a, 3, 4, 0)
	pack.add(b, 0, 0, 2)
	var data := pack.to_array()
	var copy := Backpack.from_array(data, _by_id([a, b]))
	assert_not_null(copy)
	assert_eq(copy.to_array(), data)
	assert_null(Backpack.from_array(data, _by_id([a])), "unknown item")
	var bad := data.duplicate(true)
	(bad[3] as Array).append([9, "test_1", 0, 0, 0])
	assert_null(Backpack.from_array(bad, _by_id([a, b])), "overlapping items")
	assert_null(Backpack.from_array("junk", {}), "malformed")


# --- the run ----------------------------------------------------------------------------------

func test_a_run_starts_with_an_empty_backpack_of_the_tuned_size() -> void:
	var run := _run()
	assert_eq(run.backpack.width, _tuning.backpack_width)
	assert_eq(run.backpack.rows, _tuning.backpack_rows)
	assert_eq(run.backpack.entries.size(), 0)


func test_ops_change_the_backpack_and_refuse_what_no_longer_fits() -> void:
	var run := _run()
	var salve := run.items_by_id()["salve"] as ItemData
	var feast := run.items_by_id()["feast"] as ItemData
	var a := run.place_item(salve, 0, 0, 0)
	var b := run.place_item(feast, 2, 2, 0)
	assert_true(run.apply_op({"op": "move", "uid": a, "x": 3, "y": 4, "turn": 0}))
	assert_eq(run.backpack.uid_at(Vector2i(3, 4)), a)
	assert_false(run.apply_op({"op": "move", "uid": a, "x": 3, "y": 2, "turn": 0}), "onto the feast")
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
	run.place_item(run.data.shop_items[1], 1, 1, 3)
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
	var gem := run.items_by_id()["rot_gem"] as ItemData
	var uid := run.add_item(gem)
	run.gold = 0
	assert_true(run.apply_op({"op": "sell", "uid": uid}))
	assert_eq(run.gold, CombatMath.percent(gem.price, _tuning.item_sell_percent))
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


func test_items_touch_side_by_side_not_by_corners() -> void:
	var pack := Backpack.new(4, 5)
	var one := _shape([Vector2i(0, 0)])
	var a := pack.add(one, 1, 1, 0)
	var right := pack.add(one, 2, 1, 0)
	var corner := pack.add(one, 2, 2, 0)
	assert_eq(pack.touching(a), [right] as Array[int])
	assert_false(pack.touching(a).has(corner), "corners do not touch")


func test_old_charms_are_faded_treasure_that_does_nothing_and_is_never_found() -> void:
	var run := _run()
	var power_before := run.power_percent(0)
	var max_before := run.max_hp(0)
	var husk := load("res://data/encounters/husk_fight.tres") as EncounterData
	var gold_before := run.gold_for(husk)
	for id: String in ["ember_stone", "iron_stone", "lodestone", "knucklebone", "wolf_tooth", "bone_totem", "heartleaf",
			"wake_root", "rain_pouch"]:
		var item := _item_of(run, id)
		assert_eq(item.kind, ItemData.Kind.TREASURE, "%s is treasure now (DESIGN.md 8.17)" % id)
		assert_eq(item.find_weight, 0, "%s is never found again" % id)
		assert_gt(item.price, 0, "%s still sells" % id)
		run.add_item(item)
	assert_eq(run.power_percent(0), power_before, "no buff from the backpack any more")
	assert_eq(run.max_hp(0), max_before)
	assert_eq(run.gold_for(husk), gold_before)


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
	var a := run.place_item(salve, 0, 0, 0)
	var b := run.place_item(salve, 1, 0, 0)
	var tonic := run.place_item(_item_of(run, "tonic"), 3, 0, 0)
	assert_false(run.can_combine(a, tonic), "different items")
	assert_true(run.apply_op({"op": "combine", "uid": a, "into": b}))
	assert_false(run.backpack.has_uid(a))
	var e := run.backpack.entry(b)
	assert_eq(RunState.level_of(e), 1)
	assert_eq(RunState.entry_name(e), "Salve+")
	assert_eq(RunState.entry_rarity(e), ItemData.Rarity.RARE)
	assert_eq(run.entry_amount(e), CombatMath.percent(salve.amount_percent, 100 + _tuning.combine_bonus_percent))
	var c := run.place_item(salve, 0, 0, 0)
	assert_false(run.can_combine(c, b), "only the same level")
	run.hp[0] = 1
	run.use_item(b, 0)
	assert_eq(run.hp[0], 1 + CombatMath.percent(run.max_hp(0), run.entry_amount(e)), "a combined salve heals more")


func test_combining_stops_at_legendary_and_keys_never_combine() -> void:
	var run := _run()
	var gem := _item_of(run, "rot_gem")
	assert_false(gem.combinable(), "treasure does not combine")
	var key := _item_of(run, "key")
	var a := run.place_item(key, 0, 0, 0)
	var b := run.place_item(key, 0, 1, 0)
	assert_false(run.can_combine(a, b))
	var salts := _item_of(run, "smelling_salts")
	var s1 := run.place_item(salts, 0, 3, 0, 1)
	var s2 := run.place_item(salts, 1, 3, 0, 1)
	assert_false(run.can_combine(s1, s2), "rare + 1 level is legendary already")


func test_levels_go_over_the_network() -> void:
	var run := _run()
	run.place_item(_item_of(run, "salve"), 2, 2, 0, 2)
	var copy := RunState.from_dict(run.data, _tuning, run.to_dict())
	assert_eq(RunState.level_of(copy.backpack.entries[0]), 2)


func test_a_bigger_pack_adds_a_row_up_to_the_max() -> void:
	var run := _run()
	var pack := _item_of(run, "bigger_pack")
	assert_true(run.wants(pack))
	assert_gte(run.add_item(pack), 0, "used at once")
	assert_eq(run.backpack.rows, _tuning.backpack_rows + 1)
	assert_eq(run.backpack.entries.size(), 0, "it is not kept")
	while run.backpack.rows < _tuning.backpack_max_rows:
		run.add_item(pack)
	assert_false(run.wants(pack), "no use any more")
	assert_false(run.take_upgrade(pack))
	assert_eq(run.backpack.rows, _tuning.backpack_max_rows)


func test_shops_and_finds_never_offer_curses_or_faded_charms() -> void:
	var run := _run()
	for stop: int in 30:
		for item: ItemData in run.shop_stock(stop):
			assert_false(item.is_curse(), "no curse on the shelves")
			assert_ne(item.find_weight == 0 and item.kind == ItemData.Kind.TREASURE, true, "no faded charm on the shelves")
	for item: ItemData in run.data.found_items:
		if item.is_curse():
			assert_eq(item.find_weight, 0, "%s: curses come only from events" % item.id)


func test_every_backpack_art_size_exists() -> void:
	for rows: int in range(_tuning.backpack_rows, _tuning.backpack_max_rows + 1):
		assert_true(ResourceLoader.exists("res://assets/sprites/ui/backpack_%d.png" % rows), "%d rows" % rows)
