extends GutTest
## The shipped Fight Rush data (DESIGN.md 8.21, card #305): data/rush/fight_rush.tres, written by
## tools/bootstrap_rush.gd. It loads and validates, its tiers and boss cycle are the ones the design
## names, its fights are what the zones and acts hold now (else the tool needs running again), and a
## Rush walked over it always has a fight and a look.

const RUSH_PATH := "res://data/rush/fight_rush.tres"
const RUN_PATH := "res://data/runs/rotten_road.tres"
const TUNING_PATH := "res://data/tuning/tuning.tres"
const FIRST_ACT_PATH := "res://data/runs/acts/rotten_road.tres"
const SECOND_ACT_PATH := "res://data/runs/acts/ashen_deep.tres"
const ZONE_PATH := "res://data/zones/%s.tres"
const RERUN := " (run tools/bootstrap_rush.gd again)"
## The boss cycle in order: encounter id and home depth (the map row a run meets it at).
const BOSS_CYCLE: Array[Array] = [
	["guard_gorged_one", 1],
	["guard_mire_mother", 3],
	["guard_ash_warden", 9],
	["husk_lord_fight", 6],
	["hollow_king", 13],
]
## How many fights a Rush walk covers: every tier and every boss of the cycle, then the cycle again.
const WALK_FIGHTS: int = 70

var _rush: RushData
var _run: RunData
var _tuning: Tuning


func before_all() -> void:
	_rush = load(RUSH_PATH) as RushData
	_run = load(RUN_PATH) as RunData
	_tuning = load(TUNING_PATH) as Tuning


func test_the_file_loads_and_validates() -> void:
	assert_not_null(_rush, "%s loads as RushData" % RUSH_PATH)
	if _rush == null:
		return
	var problems := _rush.validate()
	assert_eq(problems.size(), 0, "the shipped Fight Rush has no problems: %s" % "; ".join(problems))
	assert_eq(_rush.id, "fight_rush")
	assert_eq(_rush.display_name, "Fight Rush")


func test_it_shares_the_main_run() -> void:
	if _rush == null:
		return
	# The Relic bag's ids come from the main run's gear (RelicCollection), so it must be that run.
	assert_not_null(_rush.run, "the Rush names its run")
	assert_eq(_rush.run, _run, "the Rush shares %s" % RUN_PATH)
	assert_eq(_rush.run.resource_path, RUN_PATH)


func test_tiers_follow_the_design() -> void:
	if _rush == null:
		return
	var expected: Array[Array] = [[1, ["rotten_hollow"], false], [11, ["sunken_bog"], false],
			[21, ["ashen_ruins"], true], [31, ["rotten_hollow", "sunken_bog", "ashen_ruins"], true]]
	assert_eq(_rush.tiers.size(), expected.size(), "four tiers")
	for i: int in mini(_rush.tiers.size(), expected.size()):
		var tier := _rush.tiers[i]
		assert_eq(tier.from_fight, int(expected[i][0]), "tier %d starts at its fight" % i)
		var zone_ids: Array = []
		for zone: ZoneData in tier.zones:
			zone_ids.append(zone.id)
		assert_eq(zone_ids, expected[i][1], "tier %d zones" % i)
		# Monster variants start with the Ruins (fight 21), so the first two tiers teach the plain ones.
		assert_eq(tier.deep, bool(expected[i][2]), "tier %d deep" % i)


func test_every_tier_fight_is_a_plain_fight() -> void:
	if _rush == null:
		return
	for i: int in _rush.tiers.size():
		var tier := _rush.tiers[i]
		assert_gte(tier.fights.size(), 2, "tier %d has a choice of fights" % i)
		assert_gte(tier.elites.size(), 1, "tier %d has an elite" % i)
		for elite_pool: bool in [false, true]:
			for e: EncounterData in (tier.elites if elite_pool else tier.fights):
				assert_not_null(e, "tier %d has no empty fight" % i)
				if e == null:
					continue
				assert_false(e.enemies.is_empty(), "%s has enemies" % e.id)
				assert_false(e.boss, "%s is not a boss" % e.id)
				assert_false(e.mini_boss, "%s is not a guard" % e.id)
				assert_false(e.resource_path.is_empty(), "%s is its own file (not a copy)" % e.id)
				# The elite mark gives an elite its HP, power and tempo (RunState.fight_setup).
				assert_eq(e.elite, elite_pool, "%s is marked elite only in the elite pool" % e.id)


func test_tier_fights_match_the_zones_and_acts() -> void:
	if _rush == null:
		return
	var hollow := load(ZONE_PATH % "rotten_hollow") as ZoneData
	var bog := load(ZONE_PATH % "sunken_bog") as ZoneData
	var ruins := load(ZONE_PATH % "ashen_ruins") as ZoneData
	var first := load(FIRST_ACT_PATH) as ActData
	var second := load(SECOND_ACT_PATH) as ActData
	var fights: Array = [
		[hollow.roamer_pool],
		[bog.roamer_pool, first.ambushes],
		[ruins.roamer_pool, second.ambushes],
		[hollow.roamer_pool, bog.roamer_pool, first.ambushes, ruins.roamer_pool, second.ambushes],
	]
	var elites: Array = [[first.elites], [first.elites], [second.elites], [first.elites, second.elites]]
	for i: int in mini(_rush.tiers.size(), fights.size()):
		assert_eq(_ids(_rush.tiers[i].fights), _ids(_union(fights[i])), "tier %d fights%s" % [i, RERUN])
		assert_eq(_ids(_rush.tiers[i].elites), _ids(_union(elites[i])), "tier %d elites%s" % [i, RERUN])


func test_boss_cycle_follows_the_design() -> void:
	if _rush == null:
		return
	assert_eq(_rush.bosses.size(), BOSS_CYCLE.size(), "five bosses")
	for i: int in mini(_rush.bosses.size(), BOSS_CYCLE.size()):
		var boss := _rush.bosses[i]
		assert_not_null(boss.encounter, "boss %d has a fight" % i)
		if boss.encounter == null:
			continue
		assert_eq(boss.encounter.id, String(BOSS_CYCLE[i][0]), "boss %d of the cycle" % i)
		assert_eq(boss.home_depth, int(BOSS_CYCLE[i][1]), "boss %d home depth" % i)
		assert_true(boss.encounter.boss or boss.encounter.mini_boss, "%s is a boss or a guard" % boss.encounter.id)
		var look := boss.look if boss.look != null else (boss.zone.look if boss.zone != null else null)
		assert_not_null(look, "%s has a look (its own or its zone's)" % boss.encounter.id)
	# The Hollow King's throne has no zone, so no weather.
	assert_null(_rush.bosses[BOSS_CYCLE.size() - 1].zone, "the Hollow King has no zone")


func test_each_tier_ends_on_its_own_guard() -> void:
	if _rush == null:
		return
	var r := RushState.begin_rush(_rush, _tuning, 7)
	for i: int in _rush.bosses.size():
		var boss := _rush.bosses[i]
		if boss.encounter == null or not boss.encounter.mini_boss:
			continue
		var n := (i + 1) * _tuning.rush_boss_every
		assert_eq(r.kind_of(n), RushState.Kind.BOSS, "fight %d is a boss fight" % n)
		assert_true(r.tier_of(n).zones.has(boss.zone), "%s (fight %d) is fought in its tier's zone" % [boss.encounter.id, n])


func test_deep_links_resolve() -> void:
	if _rush == null:
		return
	var checked := 0
	for tier: RushTier in _rush.tiers:
		if not tier.deep:
			continue
		for list: Array[EncounterData] in [tier.fights, tier.elites]:
			for e: EncounterData in list:
				if e.deep == null:
					continue
				checked += 1
				assert_false(e.deep.enemies.is_empty(), "%s's deep version %s has enemies" % [e.id, e.deep.id])
				assert_ne(e.deep.id, e.id, "%s's deep version has its own id" % e.id)
				assert_false(e.deep.boss or e.deep.mini_boss, "%s's deep version is still a plain fight" % e.id)
				assert_eq(e.deep.elite, e.elite, "%s's deep version keeps its elite mark" % e.id)
	assert_gt(checked, 10, "the deep tiers have deep versions")
	for boss: RushBoss in _rush.bosses:
		if boss.encounter != null and boss.encounter.deep != null:
			assert_false(boss.encounter.deep.enemies.is_empty(), "%s's deep version has enemies" % boss.encounter.id)


func test_items_are_only_usable_ones() -> void:
	if _rush == null:
		return
	assert_false(_rush.items.is_empty(), "the item card has items")
	for item: ItemData in _rush.items:
		assert_not_null(item)
		if item == null:
			continue
		assert_false(item.kind in [ItemData.Kind.KEY, ItemData.Kind.TREASURE, ItemData.Kind.CURSE],
				"%s is no key, treasure or curse" % item.id)
		assert_false(item.rotten, "%s is not rotten" % item.id)
	# Every usable item the run sells or finds is offered, once.
	var expected: Array[ItemData] = []
	for list: Array[ItemData] in [_run.shop_items, _run.found_items]:
		for item: ItemData in list:
			if RushData.offerable(item) and not expected.has(item):
				expected.append(item)
	assert_eq(_item_ids(_rush.items), _item_ids(expected), "the run's usable items%s" % RERUN)


func test_a_rush_walk_always_has_a_fight_and_a_look() -> void:
	if _rush == null:
		return
	var r := RushState.begin_rush(_rush, _tuning, 11)
	for n: int in range(1, WALK_FIGHTS + 1):
		r.next_fight()
		assert_eq(r.fight, n, "next_fight moves on")
		var e := r.encounter_now()
		assert_not_null(e, "fight %d has an encounter" % n)
		if e == null:
			continue
		assert_false(e.enemies.is_empty(), "fight %d (%s) has enemies" % [n, e.id])
		assert_not_null(r.look_now(), "fight %d has a look" % n)
		var tier := r.tier_of(n)
		match r.kind_of(n):
			RushState.Kind.BOSS:
				assert_eq(r.encounter_id, r.boss_entry(n).encounter.id, "fight %d is its boss" % n)
			RushState.Kind.ELITE:
				assert_true(_ids(tier.elites).has(r.encounter_id), "fight %d is one of its tier's elites" % n)
			_:
				assert_true(_ids(tier.fights).has(r.encounter_id), "fight %d is one of its tier's fights" % n)
		if tier.deep and r.kind_of(n) != RushState.Kind.BOSS:
			var base := r._encounter_by_id(r.encounter_id)
			if base.deep != null:
				assert_eq(e, base.deep, "fight %d plays the deep version" % n)
	# Fight 50 is the Hollow King on his throne: no zone, so no weather.
	var king := RushState.begin_rush(_rush, _tuning, 11)
	king.fight = 5 * _tuning.rush_boss_every
	assert_null(king.zone_now(), "the Hollow King's throne has no zone")
	assert_null(king.weather_now(), "and so no weather")


func _union(pools: Array) -> Array[EncounterData]:
	var out: Array[EncounterData] = []
	for pool: Array in pools:
		for e: EncounterData in pool:
			if e != null and not out.has(e) and not e.boss and not e.mini_boss and not e.enemies.is_empty():
				out.append(e)
	return out


func _ids(list: Array[EncounterData]) -> Array[String]:
	var out: Array[String] = []
	for e: EncounterData in list:
		out.append(e.id if e != null else "")
	return out


func _item_ids(list: Array[ItemData]) -> Array[String]:
	var out: Array[String] = []
	for item: ItemData in list:
		out.append(item.id if item != null else "")
	return out
