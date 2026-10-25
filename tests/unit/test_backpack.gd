extends GutTest
## The pack (DESIGN.md 8.1, 8.19, cards #282, #332): Alder's pack with four pockets, one consumable
## each whatever its shape; the first free pocket; items go and come back the same as plain data,
## and older pack shapes are refused; the run's ops (move, drop, use, gear swaps) work and refuse what
## no longer fits; no combining, no levels and no Bigger Pack; treasure turns into gold; curses sit on
## the party, not in a pocket, and only a shop's Cleanse lifts them; drops are seeded; the shipped
## items and icons are sound, and no list hands out the retired Key, Tonic or Bigger Pack; the party
## screen settles what is in hand (a free pocket, a swap or left behind). Uses the shipped run with
## Tuning.new() for the rules (every Relic slot open: the slots have their own tests in
## test_relics.gd).

const Fx := preload("res://tests/helpers/combat_fixtures.gd")
const RUN_PATH := "res://data/runs/rotten_road.tres"

var _tuning := Fx.run_tuning()
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
	var pack := Backpack.new(4)
	var loaf := _shape([Vector2i(0, 0), Vector2i(1, 0)])
	var ell := _shape([Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)])
	assert_eq(pack.cell_count(), 4, "four pockets")
	var a := pack.add(loaf, 0)
	var b := pack.add(ell, 1)
	assert_gte(a, 0)
	assert_gte(b, 0)
	assert_eq(pack.free_cells(), 2, "one pocket each")
	assert_eq(pack.uid_at(Vector2i(1, 0)), b)
	assert_eq(pack.uid_at(Vector2i(2, 0)), -1)
	assert_eq(pack.add(loaf, 1), -1, "one item per pocket")
	assert_false(pack.fits(loaf, 4), "no fifth pocket")
	assert_false(pack.fits(loaf, 2, 1), "pockets are one row")
	assert_true(pack.move(a, 3))
	assert_true(pack.move(a, 3), "it may stay in its own pocket")
	assert_false(pack.move(a, 1), "a taken pocket")
	assert_eq(pack.remove(a), loaf)
	assert_eq(pack.free_cells(), 3)


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
	var pack := Backpack.new(4)
	pack.add(a, 3)
	pack.add(b, 0)
	var data := pack.to_array()
	assert_eq(data, [4, 1, 3, [[1, "test_1", 3, 0, 0], [2, "ell", 0, 0, 0]]], "pockets, uid, id and pocket: no level")
	var copy := Backpack.from_array(data, _by_id([a, b]))
	assert_not_null(copy)
	assert_eq(copy.to_array(), data)
	assert_null(Backpack.from_array(data, _by_id([a])), "unknown item")
	var bad := data.duplicate(true)
	(bad[3] as Array).append([9, "test_1", 3, 0, 0])
	assert_null(Backpack.from_array(bad, _by_id([a, b])), "two items in one pocket")
	assert_null(Backpack.from_array("junk", {}), "malformed")


func test_older_pack_shapes_and_things_used_elsewhere_are_refused() -> void:
	# RunSave.FORMAT_VERSION 7 refuses such saves already (test_run_fights.gd); the pack checks too.
	var salve := _shape([Vector2i(0, 0)])
	salve.id = "salve"
	var by_id := _by_id([salve])
	assert_null(Backpack.from_array([4, 5, 9, [[1, "salve", 2, 3, 0]]], by_id), "the grid of before phase 21")
	assert_null(Backpack.from_array([4, 1, 9, [[1, "salve", 2, 0, 0, 1]]], by_id), "a level (before card #332)")
	var run := _run()
	var all := run.items_by_id()
	for id: String in ["rotting_heart", "silver_ring"]:
		assert_null(Backpack.from_array([4, 1, 2, [[1, id, 0, 0, 0]]], all), "%s never sits in a pocket" % id)
	assert_not_null(Backpack.from_array([4, 1, 2, [[1, "salve", 0, 0, 0]]], all))


# --- the run ----------------------------------------------------------------------------------

func test_a_run_starts_with_an_empty_backpack_of_four_pockets() -> void:
	var run := _run()
	assert_eq(_tuning.backpack_pockets, 4)
	var shipped := load("res://data/tuning/tuning.tres") as Tuning
	assert_eq(shipped.backpack_pockets, 4, "the shipped pack has four pockets")
	assert_eq(run.backpack.width, _tuning.backpack_pockets)
	assert_eq(run.backpack.rows, 1)
	assert_eq(run.backpack.entries.size(), 0)
	assert_true(run.curses.is_empty(), "and no curse")


func test_only_consumables_go_in_the_pack() -> void:
	var run := _run()
	for item: ItemData in run.items_by_id().values():
		assert_eq(item.goes_in_pack(), item.kind == ItemData.Kind.CONSUMABLE, item.id)
		if not item.goes_in_pack():
			assert_eq(run.place_item(item, 0), -1, "%s never sits in a pocket" % item.id)
	assert_eq(run.backpack.entries.size(), 0)


func test_ops_change_the_backpack_and_refuse_what_no_longer_fits() -> void:
	var run := _run()
	var salve := run.items_by_id()["salve"] as ItemData
	var feast := run.items_by_id()["feast"] as ItemData
	var a := run.place_item(salve, 0)
	var b := run.place_item(feast, 2)
	assert_true(run.apply_op({"op": "move", "uid": a, "x": 3, "y": 0, "turn": 0}))
	assert_eq(run.backpack.uid_at(Vector2i(3, 0)), a)
	assert_false(run.apply_op({"op": "move", "uid": a, "x": 2, "y": 0, "turn": 0}), "onto the feast")
	assert_false(run.apply_op({"op": "move", "uid": a, "x": 4, "y": 0, "turn": 0}), "no fifth pocket")
	assert_false(run.apply_op({"op": "move", "uid": a, "x": "far"}), "malformed")
	run.hp[0] = 1
	assert_true(run.apply_op({"op": "use", "uid": a, "slot": 0}))
	assert_gt(run.hp[0], 1)
	assert_false(run.apply_op({"op": "use", "uid": a, "slot": 0}), "used up: a second ask is too late")
	assert_true(run.apply_op({"op": "drop", "uid": b}))
	assert_eq(run.backpack.entries.size(), 0)
	var relic := run.data.gear[0]
	assert_false(run.apply_op({"op": "give", "slot": 1, "relic": relic.id}), "not the run's: nothing waits")
	run.add_relic(relic)
	assert_true(run.apply_op({"op": "give", "slot": 1, "relic": relic.id}), "a waiting Relic goes to a hero")
	assert_eq(run.relics_of(1), [relic] as Array[GearData])
	assert_false(run.apply_op({"op": "give", "slot": 0, "relic": relic.id}), "given for good: never moved")
	assert_false(run.apply_op({"op": "give", "slot": "1", "relic": relic.id}), "malformed")
	for gone: String in ["swap_gear", "wear", "take_off", "echo"]:
		assert_false(run.apply_op({"op": gone, "slot": 0, "gear_slot": 0, "relic": relic.id}), gone + " is gone")
	assert_false(run.apply_op({"op": "nonsense"}))


func test_two_of_the_same_never_combine() -> void:
	# Card #332: no combining and no item levels. The op is gone, so a friend's old ask is refused.
	var run := _run()
	var salve := _item_of(run, "salve")
	var a := run.place_item(salve, 0)
	var b := run.place_item(salve, 1)
	assert_false(run.apply_op({"op": "combine", "uid": a, "into": b}), "the combine op is gone")
	assert_true(run.backpack.has_uid(a) and run.backpack.has_uid(b), "both salves stay as they are")
	assert_false(run.has_method("combine"))
	assert_false(run.has_method("upgrade_item"))
	assert_false(salve.has_method("combinable"))
	run.hp[0] = 1
	run.use_item(b, 0)
	assert_eq(run.hp[0], 1 + CombatMath.percent(run.max_hp(0), salve.amount_percent), "a salve heals its own amount")


func test_the_backpack_goes_over_the_network() -> void:
	var run := _run()
	run.place_item(run.data.shop_items[1], 1)
	var copy := RunState.from_dict(run.data, _tuning, run.to_dict())
	assert_not_null(copy)
	assert_eq(copy.backpack.to_array(), run.backpack.to_array())


## A won Fight stop's drop (DESIGN.md 8.22): seeded per stop, from the run's found items.
func test_drops_are_seeded() -> void:
	var run := _run(11)
	run.tuning = Tuning.new()
	run.tuning.item_drop_percent = 0
	for stop: int in run.map.stops.size():
		assert_null(run.drop_for(stop), "0%: never")
	run.tuning.item_drop_percent = 100
	var picks := {}
	for stop: int in run.map.stops.size():
		var drop := run.drop_for(stop)
		assert_not_null(drop, "100%: always")
		assert_true(run.data.found_items.has(drop), "a drop is one of the found items")
		assert_false(drop.is_curse(), "a drop is never a curse")
		assert_eq(run.drop_for(stop), drop, "the same stop, the same drop")
		picks[drop] = true
	assert_gt(picks.size(), 1, "stops drop different things")
	var again := _run(11)
	again.tuning = run.tuning
	assert_eq(again.drop_for(3), run.drop_for(3), "same seed, same drop")


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
		assert_true(item.kind in [ItemData.Kind.CONSUMABLE, ItemData.Kind.CURSE, ItemData.Kind.TREASURE],
				"%s is a consumable, a curse or treasure" % item.id)
		assert_false(item.effect in [ItemData.Effect.MAX_HP_ONE, ItemData.Effect.ADD_ROW], "%s: no retired effect" % item.id)
	for item: ItemData in _data.found_items:
		# Curses come only from events, pacts and the rotten chest.
		if item.is_curse():
			assert_eq(item.find_weight, 0, "%s is never found" % item.id)
		else:
			assert_gt(item.find_weight, 0, "%s can be found" % item.id)


func test_the_tonic_and_the_bigger_pack_are_gone() -> void:
	# Card #332: the Tonic (max HP for the run) and the Bigger Pack (one more pocket) went for good.
	# Their kinds and effects keep their numbers so the item files after them keep theirs.
	for id: String in ["tonic", "bigger_pack"]:
		assert_false(ResourceLoader.exists("res://data/items/%s.tres" % id), "no %s file" % id)
		assert_false(_run().items_by_id().has(id), "no item answers to %s" % id)
		assert_false(FileAccess.file_exists("res://assets/sprites/items/%s.png" % id), "no %s picture" % id)
	assert_eq(ItemData.Kind.UPGRADE, 4, "the retired kind keeps its number")
	assert_eq(ItemData.Effect.MAX_HP_ONE, 3)
	assert_eq(ItemData.Effect.ADD_ROW, 6)
	assert_eq(ItemData.Effect.CLEANSE_ONE, 7)
	for prop: String in ["tonic_max_per_hero", "backpack_max_pockets", "combine_bonus_percent", "shop_upgrade_price"]:
		assert_false(prop in _tuning, "tuning has no %s" % prop)


func test_no_event_or_pact_hands_out_a_retired_item() -> void:
	var run := _run()
	var deals: Array[ZoneOfferData] = []
	for act: ActData in run.acts():
		for event: EventData in act.events:
			for c: EventChoiceData in event.choices:
				deals.append_array([c.deal, c.risk_deal])
	for pact: EventChoiceData in _data.pacts:
		if pact != null:
			deals.append(pact.deal)
	for deal: ZoneOfferData in deals:
		if deal == null:
			continue
		if deal.item != null:
			assert_true(deal.item.kind != ItemData.Kind.UPGRADE and deal.item.effect != ItemData.Effect.MAX_HP_ONE,
					"%s is not a retired item" % deal.item.id)
		if deal.cost_rotten != null:
			assert_true(deal.cost_rotten.is_curse(), "%s: a curse price is a curse" % deal.cost_rotten.id)
			assert_true(run.items_by_id().has(deal.cost_rotten.id), "%s: the run knows the curse" % deal.cost_rotten.id)


# --- the party screen -------------------------------------------------------------------------

func test_a_relic_just_given_opens_the_relics_tab_on_its_hero() -> void:
	var run := _run()
	run.give_relic(run.data.gear[0], 2)
	var screen := PartyScreen.new()
	add_child_autofree(screen)
	screen.setup(run, "New", {"icon": run.data.gear[0]})
	assert_false(screen.holding_new(), "a Relic is never held: it was given before the screen opened")
	assert_eq(screen.current_tab(), PartyScreen.Tab.RELICS)
	assert_eq(screen.tab_node(PartyScreen.Tab.RELICS).hero, 2, "on the hero who got it")


func test_a_find_with_no_room_is_left_behind() -> void:
	var run := _run()
	var salve := run.items_by_id()["salve"] as ItemData
	while run.add_item(salve) >= 0:
		pass
	assert_eq(run.backpack.entries.size(), 4, "four salves fill the pack")
	var screen := PartyScreen.new()
	add_child_autofree(screen)
	screen.setup(run, "", {"item": salve})
	watch_signals(screen)
	screen.auto_settle()
	assert_signal_emitted_with_parameters(screen, "left_behind", [salve])
	assert_eq(run.backpack.free_cells(), 0)


# --- step 2: rarity, selling --------------------------------------------------------------------

func test_deeper_rows_turn_up_rarer_things() -> void:
	var run := _run()
	assert_eq(run.rarity_weight(100, ItemData.Rarity.COMMON, 6), 100)
	assert_gt(run.rarity_weight(100, ItemData.Rarity.RARE, 6), run.rarity_weight(100, ItemData.Rarity.RARE, 0))
	assert_gt(run.rarity_weight(100, ItemData.Rarity.LEGENDARY, 6), run.rarity_weight(100, ItemData.Rarity.LEGENDARY, 0))


func test_selling_pays_and_removes() -> void:
	var run := _run()
	var bomb := run.items_by_id()["bomb"] as ItemData
	var uid := run.add_item(bomb)
	run.gold = 0
	assert_true(run.apply_op({"op": "sell", "uid": uid}))
	assert_eq(run.gold, CombatMath.percent(bomb.price, _tuning.item_sell_percent))
	assert_false(run.backpack.has_uid(uid))
	assert_false(run.apply_op({"op": "sell", "uid": uid}), "already sold")


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


# --- curses on the party (card #332) ------------------------------------------------------------

func test_a_curse_sits_on_the_party_not_in_a_pocket() -> void:
	var run := _run()
	var heart := _item_of(run, "rotting_heart")
	var moss := _item_of(run, "grave_moss")
	assert_true(heart.is_curse() and heart.rotten)
	var power_before := run.power_percent(0)
	assert_eq(run.add_item(heart), 0, "taken, not packed")
	assert_eq(run.find_text(heart), "Cursed: Rotting Heart")
	assert_true(run.add_curse(moss))
	assert_eq(run.curses, ["rotting_heart", "grave_moss"] as Array[String], "in the order taken")
	assert_eq(run.curse_items(), [heart, moss] as Array[ItemData])
	assert_eq(run.backpack.entries.size(), 0, "a curse takes no pocket")
	assert_eq(run.backpack.free_cells(), 4)
	assert_eq(run.rot_percent(), heart.rot_percent + moss.rot_percent, "the same rot per curse")
	assert_eq(run.power_percent(0), power_before, "a curse only hurts")
	assert_true(run.add_curse(heart), "the same curse twice is two curses")
	assert_eq(run.rot_percent(), 2 * heart.rot_percent + moss.rot_percent)
	assert_false(run.add_curse(_item_of(run, "salve")), "not a curse")
	assert_eq(run.curses.size(), 3)


func test_a_full_pack_still_takes_a_curse() -> void:
	var run := _run()
	while run.add_item(_item_of(run, "bomb")) >= 0:
		pass
	assert_eq(run.add_item(_item_of(run, "grave_moss")), 0, "no room needed")
	assert_eq(run.curses, ["grave_moss"] as Array[String])


func test_curses_drain_in_fights() -> void:
	var run := _run()
	var curse := _item_of(run, "rotting_heart")
	run.add_curse(curse)
	assert_eq(run.rot_percent(), 3)
	var setup := run.fight_setup(load("res://data/encounters/husk_fight.tres") as EncounterData, 3,
			CombatSetup.Opening.FIRST_STRIKE)
	assert_eq(int(setup.party_passives[0].get(Passive.ROT, 0)), 3)
	var engine := CombatEngine.new(setup)
	var events := engine.start()
	var rot := events.filter(func(ev: Dictionary) -> bool: return String(ev.type) == "damage" and String(ev.cause) == "rot")
	assert_gt(rot.size(), 0, "the first hero to act loses HP to the rot")


func test_rot_never_downs_a_hero() -> void:
	var run := _run()
	run.add_curse(_item_of(run, "rotting_heart"))
	for slot: int in run.party_size():
		run.hp[slot] = 1
	var engine := CombatEngine.new(run.fight_setup(load("res://data/encounters/husk_fight.tres") as EncounterData, 3,
			CombatSetup.Opening.FIRST_STRIKE))
	engine.start()
	for id: int in engine.party_ids():
		assert_eq(engine.get_combatant(id).hp, 1)


func test_only_a_cleanse_lifts_a_curse_and_it_costs_the_same() -> void:
	# Deliberate (DESIGN.md 8.1): a curse cannot be thrown away or sold for free; the shop's Cleanse
	# at its old price is the only way off.
	var run := _run()
	run.add_curse(_item_of(run, "rotting_heart"))
	run.add_curse(_item_of(run, "grave_moss"))
	assert_eq(run.cleanse_price(), run.shop_price(_tuning.shop_cleanse_price))
	for op: String in ["drop", "sell", "use"]:
		assert_false(run.apply_op({"op": op, "uid": 0, "slot": 0}), "%s cannot reach a curse" % op)
	run.gold = run.cleanse_price() - 1
	assert_false(run.cleanse(0), "short of gold")
	assert_eq(run.curses.size(), 2)
	run.gold = run.cleanse_price() * 2
	assert_false(run.cleanse(2), "no such curse")
	assert_false(run.cleanse(-1))
	assert_true(run.cleanse(1), "the Grave Moss")
	assert_eq(run.curses, ["rotting_heart"] as Array[String])
	assert_eq(run.gold, run.cleanse_price())
	assert_true(run.cleanse(0))
	assert_true(run.curses.is_empty())
	assert_eq(run.gold, 0)
	assert_eq(run.rot_percent(), 0, "no curse, no rot")


func test_curses_go_over_the_network_and_odd_ones_are_refused() -> void:
	var run := _run()
	run.add_curse(_item_of(run, "grave_moss"))
	run.add_curse(_item_of(run, "rotting_heart"))
	var d := run.to_dict()
	assert_eq(d.curses, ["grave_moss", "rotting_heart"])
	var copy := RunState.from_dict(run.data, _tuning, d)
	assert_not_null(copy)
	assert_eq(copy.curses, run.curses)
	assert_eq(copy.rot_percent(), run.rot_percent())
	for bad: Variant in [["no_such_curse"], ["salve"], [3], "rotting_heart"]:
		var odd := d.duplicate(true)
		odd.curses = bad
		assert_null(RunState.from_dict(run.data, _tuning, odd), "refused: %s" % str(bad))
	var none := d.duplicate(true)
	none.erase("curses")
	assert_null(RunState.from_dict(run.data, _tuning, none), "a run without the curses list (before card #332)")
	var cleared := d.duplicate(true)
	cleared.curses = []
	assert_true(copy.apply_dict(cleared))
	assert_true(copy.curses.is_empty(), "a lifted curse goes on every copy")


func test_shops_and_finds_never_offer_curses() -> void:
	var run := _run()
	for stop: int in 30:
		for item: ItemData in run.shop_stock(stop):
			assert_false(item.is_curse(), "no curse on the shelves")
			assert_true(item.goes_in_pack(), "%s: the shelves hold only things for the pack" % item.id)
	for item: ItemData in run.data.found_items:
		if item.is_curse():
			assert_eq(item.find_weight, 0, "%s: curses come only from events" % item.id)


func test_no_run_list_hands_out_a_key() -> void:
	# Phase 26 (DESIGN.md 8.22, G3): the Key left the shop, the finds and the drops (it went with the
	# chests). Finds, drops and treasure all draw from found_items, so the lists are the whole story.
	var run := _run()
	for list: Array[ItemData] in [_data.shop_items, _data.found_items]:
		for item: ItemData in list:
			assert_ne(item.kind, ItemData.Kind.KEY, "%s is no key" % item.id)
	for stop: int in 30:
		for item: ItemData in run.shop_stock(stop):
			assert_ne(item.kind, ItemData.Kind.KEY, "no key on the shelves")
	for act: ActData in run.acts():
		for event: EventData in act.events:
			for c: EventChoiceData in event.choices:
				for deal: ZoneOfferData in [c.deal, c.risk_deal]:
					if deal != null and deal.item != null:
						assert_ne(deal.item.kind, ItemData.Kind.KEY, "%s gives no key" % event.id)
	for pact: EventChoiceData in _data.pacts:
		if pact != null and pact.deal != null and pact.deal.item != null:
			assert_ne(pact.deal.item.kind, ItemData.Kind.KEY, "a pact gives no key")


func test_the_key_is_gone_but_its_kind_keeps_its_number() -> void:
	# Phase 26 (DESIGN.md 8.22, G3): the Key's file went with the chests; every save from before
	# (RunSave formats 1 and 2: the first phase 26 builds could still give a Key) is kept but refused
	# by RunSave.FORMAT_VERSION 3, so no pack that loads can hold one (test_run_fights.gd). The kind
	# keeps its slot so the item files after it keep their numbers.
	assert_false(ResourceLoader.exists("res://data/items/key.tres"), "no Key file")
	assert_false(_run().items_by_id().has("key"), "no item answers to the Key's id")
	assert_eq(ItemData.Kind.KEY, 2, "the retired kind keeps its number")
	assert_eq(ItemData.Kind.TREASURE, 3)


func test_the_pack_art_exists() -> void:
	var visuals := load("res://data/presentation/combat_visuals.tres") as CombatVisuals
	assert_true(ResourceLoader.exists(visuals.backpack_art_path), "Alder's open pack")
	for gone: String in ["backpack_6", "backpack_7", "upgrade", "choice_upgrade"]:
		assert_false(FileAccess.file_exists("res://assets/sprites/ui/%s.png" % gone), "%s went with card #332" % gone)


func test_four_pockets_sit_two_to_a_row() -> void:
	var run := _run()
	var grid := BackpackGrid.new()
	add_child_autofree(grid)
	var visuals := load("res://data/presentation/combat_visuals.tres") as CombatVisuals
	grid.setup(run.backpack, visuals)
	assert_eq(grid.columns(), 2, "two to a row")
	var r0 := grid.pocket_rect(0)
	var r1 := grid.pocket_rect(1)
	var r2 := grid.pocket_rect(2)
	assert_eq(r1.position.y, r0.position.y, "the first two side by side")
	assert_gt(r2.position.y, r0.position.y, "the next two below")
	assert_eq(r2.position.x, r0.position.x)
	assert_false(r0.intersects(r1) or r0.intersects(r2), "pockets never overlap")
	assert_gt(r0.size.x, 0.0)


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


func test_a_find_handed_out_goes_in_a_pocket_a_swap_or_is_left() -> void:
	# The host's side of a friend's choice (BagTab.place_new, card #314): checked against the pack.
	var run := _run()
	var salve := _item_of(run, "salve")
	var bomb := _item_of(run, "bomb")
	assert_eq(BagTab.place_new(run, salve, {"to": "pocket", "pocket": 2}), BagTab.PLACED)
	assert_eq(run.backpack.uid_at(Vector2i(2, 0)) >= 0, true)
	assert_eq(BagTab.place_new(run, salve, {"to": "pocket", "pocket": 2}), "", "a taken pocket")
	assert_eq(BagTab.place_new(run, salve, {"to": "pocket", "pocket": 4}), "", "no fifth pocket")
	while run.add_item(bomb) >= 0:
		pass
	var old := run.backpack.uid_at(Vector2i(0, 0))
	assert_eq(BagTab.place_new(run, salve, {"to": "fit"}), BagTab.LEFT, "full: left behind")
	assert_eq(BagTab.place_new(run, salve, {"to": "swap", "uid": old, "pocket": 1}), "", "not that pocket's item")
	assert_eq(BagTab.place_new(run, salve, {"to": "swap", "uid": old, "pocket": 0}), BagTab.PLACED)
	assert_false(run.backpack.has_uid(old), "the old one is thrown away")
	assert_eq((run.backpack.entry(run.backpack.uid_at(Vector2i(0, 0))).item as ItemData), salve)
	assert_eq(BagTab.place_new(run, salve, {"to": "leave"}), BagTab.LEFT)
	assert_eq(BagTab.place_new(run, salve, {"to": "combine", "uid": old}), "", "no combining")
	var empty := _run()
	assert_eq(BagTab.place_new(empty, _item_of(empty, "silver_ring"), {"to": "pocket", "pocket": 0}), "",
			"treasure never sits in a pocket")
	assert_eq(BagTab.place_new(empty, _item_of(empty, "rotting_heart"), {"to": "pocket", "pocket": 0}), "",
			"nor does a curse")
	assert_eq(empty.backpack.entries.size(), 0)


func _press(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event
