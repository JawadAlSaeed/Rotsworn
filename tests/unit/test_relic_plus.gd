extends GutTest
## Phase 27 (DESIGN.md 8.25): the 63 Relics as data, Relic+ (the "+" numbers, the rider, the run's
## upgraded set, saved and sent online, the campfire's upgrade op), the shared Relic limits in the
## fight (the tough floor, the 75% cut cap, the Relic AP cap per attack), First Light's charges,
## the spoils' rarity rules per act and the Relic book hiding cut Relics.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")
const RUN_PATH := "res://data/runs/rotten_road.tres"
const MAIN_PATH := "res://scenes/main.gd"
const DODGE: int = Defense.Outcome.DODGE
const FOE: int = Fx.ENEMY_ID
const CUT: Array[String] = ["iron_charm", "lucky_coin", "victors_wreath", "wardstone"]
const PRICES: Dictionary = {0: 60, 1: 100, 2: 150}

var _data: RunData
var _tuning: Tuning


func before_all() -> void:
	_data = load(RUN_PATH) as RunData
	_tuning = load("res://data/tuning/tuning.tres") as Tuning


func _run(seed_value: int = 7) -> RunState:
	return RunState.begin(_data, Fx.run_tuning(_tuning), seed_value)


func _relic(id: String) -> GearData:
	for item: GearData in _data.gear:
		if item.id == id:
			return item
	fail_test("the shipped run has the Relic %s" % id)
	return GearData.new()


func _engine(attacks: Array, passives: Dictionary = {}) -> CombatEngine:
	var setup := Fx.setup(attacks)
	for i: int in 3:
		setup.party_passives.append(passives.duplicate())
	var engine := CombatEngine.new(setup)
	engine.start()
	return engine


## A bare Relic with every Relic+ field set: effect 10 -> 15, a price of 20 -> 10, a rider.
func _test_relic() -> GearData:
	var item := GearData.new()
	item.id = "test_relic"
	item.effect = GearData.Effect.POWER
	item.amount = 10
	item.amount_plus = 15
	item.drawback = GearData.Effect.TOUGH
	item.drawback_amount = 20
	item.drawback_amount_plus = 10
	item.plus_rider = GearData.Effect.COUNTER
	item.plus_rider_amount = 5
	return item


# --- the data -----------------------------------------------------------------------------------

func test_the_63_relics_follow_the_table() -> void:
	assert_eq(_data.gear.size(), 63)
	var per_category := [0, 0, 0]
	var rot := 0
	var priced := 0
	var ids := {}
	for item: GearData in _data.gear:
		assert_false(ids.has(item.id), "%s once" % item.id)
		ids[item.id] = true
		assert_false(CUT.has(item.id), "%s was cut" % item.id)
		assert_false(item.display_name.is_empty(), item.id)
		assert_false(item.description.is_empty(), "%s says what it does" % item.id)
		assert_true(item.has_plus(), "%s has a Relic+" % item.id)
		assert_false(item.plus_text.is_empty(), "%s says what its + does" % item.id)
		assert_eq(item.icon_path, "res://assets/sprites/relics/%s.png" % item.id)
		assert_eq(item.price, int(PRICES[int(item.rarity)]), "%s is priced by rarity" % item.id)
		assert_false(item.effect_line().is_empty(), item.id)
		assert_false(item.effect_line(true).is_empty(), item.id)
		per_category[item.category()] += 1
		if item.rot_touched:
			rot += 1
			if item.has_drawback() or item.contribution(GearData.Effect.ROT) > 0:
				priced += 1
	assert_eq(per_category, [25, 16, 22], "offensive, defensive, support (DESIGN.md 8.25)")
	assert_eq(rot, 12, "12 rot-touched")
	assert_gte(priced, rot - 2, "a rot-touched Relic has a price; a couple only a condition (Hollow Mantle)")


func test_every_relic_effect_is_known_to_the_fight_or_the_run() -> void:
	var run_only: Array[int] = [GearData.Effect.ELITE_POWER, GearData.Effect.CAMPFIRE_HEAL,
			GearData.Effect.ACT_START_AP, GearData.Effect.POWER, GearData.Effect.MAX_HP]
	for item: GearData in _data.gear:
		for effect: int in [item.effect, item.plus_rider if item.has_rider() else item.effect]:
			if run_only.has(effect):
				continue
			var key := String(GearData.PASSIVE_KEYS.get(effect, ""))
			assert_false(key.is_empty(), "%s: effect %d has a passive key" % [item.id, effect])
			assert_true(Passive.ALL.has(key), "%s: %s is a Passive" % [item.id, key])


# --- Relic+ on the piece ---------------------------------------------------------------------------

func test_relic_plus_changes_the_amounts_and_adds_the_rider() -> void:
	var item := _test_relic()
	assert_true(item.has_plus())
	assert_eq(item.contribution(GearData.Effect.POWER), 10)
	assert_eq(item.contribution(GearData.Effect.POWER, true), 15)
	assert_eq(item.contribution(GearData.Effect.TOUGH), -20)
	assert_eq(item.contribution(GearData.Effect.TOUGH, true), -10, "the price drops")
	assert_eq(item.contribution(GearData.Effect.COUNTER), 0, "no rider before the +")
	assert_eq(item.contribution(GearData.Effect.COUNTER, true), 5)
	assert_eq(item.effect_line(true).split("  |  ").size(), 3, "effect, rider, price")
	var bare := GearData.new()
	bare.amount = 7
	assert_false(bare.has_plus())
	assert_eq(bare.amount_of(true), 7, "0 means unchanged")


# --- Relic+ in the run ---------------------------------------------------------------------------

func test_only_a_given_relic_not_yet_plus_can_be_upgraded() -> void:
	var run := _run()
	var root := _relic("wake_root")
	assert_false(run.can_upgrade(root), "the run does not have it")
	assert_false(run.upgrade_relic("wake_root"))
	assert_false(run.upgrade_relic("no_such_relic"))
	assert_false(run.give_relic(root, 0).is_empty())
	assert_eq(run.upgradable(), [root] as Array[GearData])
	assert_eq(run.upgradable([1, 2] as Array[int]), [] as Array[GearData], "only the chooser's heroes")
	var key := String(GearData.PASSIVE_KEYS[root.plus_rider])
	assert_false(run.passives(0).has(key))
	assert_true(run.upgrade_relic("wake_root"))
	assert_true(run.is_plus(root))
	assert_eq(int(run.passives(0)[key]), root.plus_rider_amount, "the rider works once upgraded")
	assert_false(run.can_upgrade(root))
	assert_false(run.upgrade_relic("wake_root"), "once per Relic")


func test_the_run_reads_the_plus_amounts() -> void:
	var tried := 0
	for item: GearData in _data.gear:
		var key := item.passive_key()
		if item.amount_plus <= 0 or key.is_empty() or (item.has_drawback() and item.drawback == item.effect):
			continue
		var run := _run()
		run.give_relic(item, 1)
		assert_eq(int(run.passives(1)[key]), item.amount, item.id)
		run.upgrade_relic(item.id)
		assert_eq(int(run.passives(1)[key]), item.amount_plus, item.id + "+")
		tried += 1
	assert_gt(tried, 10)


func test_the_upgraded_set_is_saved_sent_and_checked() -> void:
	var run := _run()
	run.give_relic(_relic("wake_root"), 2)
	run.upgrade_relic("wake_root")
	var d := run.to_dict()
	assert_eq(d.relics_plus, {"wake_root": 1})
	assert_eq(Fx.find_illegal_value(d), "", "plain values only")
	var copy := RunState.from_dict(_data, Fx.run_tuning(_tuning), d)
	assert_not_null(copy)
	assert_true(copy.is_plus(copy.relic_by_id("wake_root")))
	assert_eq(copy.to_dict(), d)
	var bad := d.duplicate(true)
	bad.relics_plus = {"coffin_lid": 1}
	assert_false(run.apply_dict(bad), "a Relic the run does not have")
	bad.relics_plus = {"wake_root": "yes"}
	assert_false(run.apply_dict(bad), "not a number")
	bad.relics_plus = ["wake_root"]
	assert_false(run.apply_dict(bad), "not a dictionary")
	assert_true(run.is_plus(_relic("wake_root")), "a refused state changes nothing")


func test_taking_a_starting_relic_back_drops_its_plus() -> void:
	var book := RelicCollection.new()
	book.merge(["wake_root"])
	var run := RunState.begin(_data, Fx.run_tuning(_tuning), 7, 0, book)
	assert_false(run.take_start_relic(0, _relic("wake_root")).is_empty())
	run.relics_plus["wake_root"] = 1
	run.undo_start_relic(0, "wake_root")
	assert_false(run.relics_plus.has("wake_root"))


func test_the_campfire_upgrades_a_relic_once() -> void:
	var run := _run()
	run.give_relic(_relic("wake_root"), 0)
	var rest := RestScreen.new()
	add_child_autofree(rest)
	rest.setup(run)
	assert_false(rest.upgrade_now("coffin_lid"), "not the run's")
	assert_true(rest.upgrade_now("wake_root"))
	assert_true(run.is_plus(_relic("wake_root")))
	assert_true(rest.has_acted(), "it is the fire's one choice")
	run.give_relic(_relic("fox_step"), 1)
	assert_false(rest.upgrade_now("fox_step"), "once a fire")


func test_a_friends_upgrade_goes_through_the_host_check() -> void:
	var main_script := load(MAIN_PATH) as GDScript
	var run := _run()
	run.give_relic(_relic("wake_root"), 0)
	var rest := RestScreen.new()
	add_child_autofree(rest)
	rest.setup(run)
	assert_eq(String(main_script.call("_make_rest_choice", rest, "upgrade", {})), "", "no Relic named")
	assert_eq(String(main_script.call("_make_rest_choice", rest, "upgrade", {"relic": 3})), "", "not a name")
	assert_eq(String(main_script.call("_make_rest_choice", rest, "upgrade", {"relic": "fox_step"})), "", "not had")
	assert_eq(String(main_script.call("_make_rest_choice", rest, "upgrade", {"relic": "wake_root"})), "upgrade wake_root")
	assert_true(run.is_plus(_relic("wake_root")))
	assert_eq(String(main_script.call("_make_rest_choice", rest, "rest", {})), "", "once a fire")


# --- the shared limits in the fight --------------------------------------------------------------

func test_hits_on_a_hero_never_hurt_more_than_the_tough_floor() -> void:
	var engine := _engine([Fx.attack("one", [Fx.hit(900)])], {Passive.TOUGH: -200})
	var foe := engine.get_combatant(FOE)
	var hero := engine.get_combatant(0)
	var t := engine.tuning
	assert_eq(engine._enemy_hit_damage(foe, hero, 100),
			CombatMath.percent_min1(foe.power, t.relic_hit_taken_max_percent), "x1.6 at most")


func test_relics_and_guard_never_cut_a_hit_by_more_than_the_cap() -> void:
	var engine := _engine([Fx.attack("one", [Fx.hit(900)])], {Passive.TOUGH: 60})
	var foe := engine.get_combatant(FOE)
	var hero := engine.get_combatant(0)
	var t := engine.tuning
	var no_events: Array[Dictionary] = []
	engine._add_status(hero, Status.GUARDED, 1, hero.id, no_events)
	# Guarded (x0.5) and 60% tough (x0.4) would leave 20%; the cap keeps 25%.
	assert_eq(engine._enemy_hit_damage(foe, hero, 100),
			CombatMath.percent_min1(foe.power, 100 - t.relic_damage_cut_max_percent))


func test_relic_ap_from_one_attack_is_capped() -> void:
	var three := Fx.attack("three", [Fx.hit(500), Fx.hit(900), Fx.hit(1300)])
	var gained: Array[int] = []
	for amount: int in [0, 1, 2]:
		var engine := _engine([three], {Passive.DODGE_AP: amount} if amount > 0 else {})
		var target := int((engine.sequence.targets as Array)[0])
		var before := engine.get_combatant(target).ap
		engine.submit(Fx.resolve_now(engine, [[0, DODGE], [1, DODGE], [2, DODGE]]))
		gained.append(engine.get_combatant(target).ap - before)
	var base := 3 * Defense.ap_reward(DODGE, Tuning.new())
	assert_eq(gained, [base, base + 3, base + 3] as Array[int],
			"three dodges: +1 each, but +2 each stops at relic_ap_per_attack_max")


func test_first_light_plus_empowers_two_skills() -> void:
	var engine := _engine([Fx.attack("one", [Fx.hit(900)])], {Passive.START_EMPOWERED: 2})
	for id: int in 3:
		var hero := engine.get_combatant(id)
		assert_true(hero.has_status(Status.EMPOWERED))
		assert_eq(int((hero.statuses[Status.EMPOWERED] as Dictionary).turns), 2, "two skills")


# --- spoils --------------------------------------------------------------------------------------

func test_act_one_spoils_may_hold_one_common_card_and_later_acts_none() -> void:
	var commons := 0
	for s: int in range(1, 25):
		var run := _run(s)
		for stop: Dictionary in run.map.stops:
			if int(stop.type) != RunMap.StopType.ELITE or bool(stop.get("crown", false)):
				continue
			var id := int(stop.id)
			var low := run.loot_choices(id).filter(func(g: GearData) -> bool: return g.rarity < ItemData.Rarity.RARE)
			assert_lte(low.size(), _tuning.run_spoils_open_cards, "seed %d: one open card at most" % s)
			commons += low.size()
			run.act = _tuning.run_spoils_open_acts
			var later := run.loot_choices(id).filter(func(g: GearData) -> bool: return g.rarity < ItemData.Rarity.RARE)
			assert_eq(later.size(), 0, "seed %d: no common card after act 1" % s)
			run.act = 0
	assert_gt(commons, 0, "act 1 spoils do offer common Relics sometimes")
	var run := _run()
	assert_eq(run.spoils_open_cards(true), 0, "never at the crowned elite")
	assert_eq(run.spoils_open_cards(false), _tuning.run_spoils_open_cards)


# --- the Relic book ------------------------------------------------------------------------------

func test_the_relic_book_hides_and_does_not_count_cut_relics() -> void:
	var book := RelicCollection.new()
	book.merge(["iron_charm", "coffin_lid", "wardstone"])
	assert_eq(book.count(), 3, "the file keeps every id")
	assert_eq(book.found_count_of(_data.gear), 1, "only Relics the game has count")
	assert_eq(book.found_of(_data.gear), [_relic("coffin_lid")] as Array[GearData])
	var run := RunState.begin(_data, Fx.run_tuning(_tuning), 7, 0, book)
	assert_null(run.relic_by_id("iron_charm"), "a cut Relic is nowhere in a run")
