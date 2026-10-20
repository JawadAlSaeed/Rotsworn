extends GutTest
## Long zones (DESIGN.md 8.5): ZoneAssembler lays sections end to end the same way for the same
## seed and differently for others; ZonePath finds ways round walls; every shipped zone, on many
## visits, lets the party reach every seal with the gate shut, and every spot, chest, shrine,
## wanderer, champion and prize, and the guard, once it opens; the gate really blocks the guard.
## The exit (card #241) stands past the guard and can be reached from it; a cleared run zone with
## an exit stays open. RunState pays for and gives the shrines' and wanderers' deals.

const SEEDS: int = 12

var _tuning := Tuning.new()
var _explore := load("res://data/presentation/explore_visuals.tres") as ExploreVisuals
var _run_data := load("res://data/runs/rotten_road.tres") as RunData


func _zones() -> Array[ZoneData]:
	var list: Array[ZoneData] = []
	for zone: ZoneData in FightSelect.load_zones():
		if ZoneAssembler.is_sectioned(zone):
			list.append(zone)
	return list


func _section(width: float) -> ZoneSectionData:
	var sec := ZoneSectionData.new()
	sec.width = width
	return sec


# --- the assembler ----------------------------------------------------------------------------

func test_every_shipped_zone_is_long_and_built_from_sections() -> void:
	var zones := _zones()
	assert_eq(zones.size(), 3, "the three zones are long zones now")
	for zone: ZoneData in zones:
		assert_gte(zone.middle_sections.size(), zone.middle_count, "%s has enough middles to pick from" % zone.id)
		var built := ZoneAssembler.assemble(zone, 1)
		var length := built.bounds_max.x - built.bounds_min.x
		assert_gt(length, 100.0, "%s is about four times longer than the old zones (30)" % zone.id)
		assert_eq(built.seal_spots.size(), zone.middle_count, "%s: a seal per middle section" % zone.id)
		assert_not_null(built.gate, "%s has a gate" % zone.id)
		var guards := 0
		for e: ZoneEnemyData in built.enemies:
			assert_not_null(e.encounter, "%s: every enemy has a fight" % zone.id)
			if e.guard:
				guards += 1
				assert_gt(e.position.x, built.gate.position.x, "%s: the guard stands past the gate" % zone.id)
		assert_eq(guards, 1, "%s: one guard" % zone.id)
		assert_true(built.has_exit, "%s has an exit" % zone.id)
		for e: ZoneEnemyData in built.enemies:
			if e.guard:
				assert_gt(built.exit_spot.x, e.position.x, "%s: the exit is past the guard" % zone.id)
		assert_lt(built.exit_spot.x, built.bounds_max.x, "%s: the exit is inside the zone" % zone.id)
		assert_gt(built.exit_spot.x, built.bounds_max.x - 5.0, "%s: the exit is at the far end" % zone.id)
		assert_lt(built.player_start.x, built.gate.position.x, "%s: the party starts before the gate" % zone.id)
		assert_eq(built.offers.size(), built.offer_spots.size(), "%s: every shrine has a spot" % zone.id)


func test_same_seed_same_zone_other_seeds_other_zones() -> void:
	for zone: ZoneData in _zones():
		var a := ZoneAssembler.assemble(zone, 5)
		var b := ZoneAssembler.assemble(zone, 5)
		assert_eq(_shape(a), _shape(b), "%s: the same seed builds the same zone" % zone.id)
		var shapes := {}
		for seed_value: int in range(1, SEEDS + 1):
			shapes[_shape(ZoneAssembler.assemble(zone, seed_value))] = true
		assert_gt(shapes.size(), SEEDS / 2, "%s: visits differ" % zone.id)


## Everything a visit decides, as text.
func _shape(zone: ZoneData) -> String:
	var parts: Array[String] = [str(zone.bounds_max), str(zone.seal_spots), str(zone.offer_spots)]
	for e: ZoneEnemyData in zone.enemies:
		parts.append("%s@%s" % [e.encounter.id, e.position])
	for offer: ZoneOfferData in zone.offers:
		parts.append(offer.id)
	return ";".join(parts)


func test_sections_are_laid_end_to_end() -> void:
	var zone := ZoneData.new()
	zone.bounds_min = Vector2(-1.0, -10.0)
	zone.bounds_max = Vector2(1.0, 10.0)
	zone.start_section = _section(10.0)
	zone.start_section.player_start = Vector3(2.0, 0.0, 1.0)
	var middle := _section(20.0)
	middle.item_spots.append(Vector3(5.0, 0.0, -3.0))
	middle.seal_spots.append(Vector3(6.0, 0.0, -4.0))
	zone.middle_sections.assign([middle])
	zone.middle_count = 1
	zone.end_section = _section(15.0)
	var gate := ZoneBlockData.new()
	gate.position = Vector3(3.0, 0.0, 0.0)
	zone.end_section.gate = gate
	zone.end_section.has_exit = true
	zone.end_section.exit_spot = Vector3(13.0, 0.0, 0.5)
	var built := ZoneAssembler.assemble(zone, 3)
	assert_eq(built.bounds_min, Vector2(0.0, -10.0), "starts at x 0, keeps the depth")
	assert_eq(built.bounds_max, Vector2(45.0, 10.0), "as long as its sections")
	assert_eq(built.player_start, Vector3(2.0, 0.0, 1.0))
	assert_eq(built.item_spots, [Vector3(15.0, 0.0, -3.0)] as Array[Vector3], "a middle's spots move by the start's width")
	assert_eq(built.seal_spots, [Vector3(16.0, 0.0, -4.0)] as Array[Vector3])
	assert_eq(built.gate.position, Vector3(33.0, 0.0, 0.0), "the end's gate moves by both widths before it")
	assert_eq(gate.position, Vector3(3.0, 0.0, 0.0), "the section's own data is never changed")
	assert_true(built.has_exit)
	assert_eq(built.exit_spot, Vector3(43.0, 0.0, 0.5), "the end's exit moves like its gate")


func test_a_zone_without_an_exit_section_has_none() -> void:
	var zone := ZoneData.new()
	zone.start_section = _section(10.0)
	zone.end_section = _section(10.0)
	assert_false(ZoneAssembler.assemble(zone, 2).has_exit)


func test_a_zone_without_sections_is_used_as_it_is() -> void:
	var zone := ZoneData.new()
	assert_same(ZoneAssembler.assemble(zone, 4), zone)


func test_roaming_spots_without_a_fight_take_one_from_the_pool() -> void:
	var zone := ZoneData.new()
	zone.start_section = _section(10.0)
	zone.end_section = _section(10.0)
	var spot := ZoneEnemyData.new()
	spot.position = Vector3(4.0, 0.0, 0.0)
	zone.start_section.enemies.append(spot)
	var fight := EncounterData.new()
	fight.id = "pool_fight"
	zone.roamer_pool.append(fight)
	var built := ZoneAssembler.assemble(zone, 9)
	assert_eq(built.enemies.size(), 1)
	assert_eq(built.enemies[0].encounter, fight)
	assert_null(spot.encounter, "the section keeps its empty spot")


func test_a_spot_with_no_chance_is_never_filled() -> void:
	var zone := ZoneData.new()
	zone.start_section = _section(10.0)
	zone.end_section = _section(10.0)
	var spot := ZoneEnemyData.new()
	spot.encounter = EncounterData.new()
	spot.chance_percent = 0
	zone.start_section.enemies.append(spot)
	for seed_value: int in range(1, 20):
		assert_eq(ZoneAssembler.assemble(zone, seed_value).enemies.size(), 0)


# --- paths ------------------------------------------------------------------------------------

func test_a_path_goes_round_a_wall() -> void:
	var wall: Array[Dictionary] = [{"centre": Vector2(5.0, 0.0), "half": Vector2(0.5, 4.0), "angle": 0.0}]
	var grid := ZonePath.build(wall, Vector2(0.0, -6.0), Vector2(10.0, 6.0), 0.35)
	var path := grid.find(Vector2(1.0, 0.0), Vector2(9.0, 0.0), 0.5)
	assert_false(path.is_empty(), "there is a way round")
	var went_round := false
	for p: Vector2 in path:
		assert_false(ZonePath._overlaps(p, 0.35, wall[0]), "never through the wall")
		went_round = went_round or absf(p.y) > 4.0
	assert_true(went_round, "it goes past an end of the wall")


func test_a_closed_room_cannot_be_reached() -> void:
	var walls: Array[Dictionary] = [{"centre": Vector2(5.0, 0.0), "half": Vector2(0.5, 10.0), "angle": 0.0}]
	var grid := ZonePath.build(walls, Vector2(0.0, -6.0), Vector2(10.0, 6.0), 0.35)
	assert_false(grid.reachable(Vector2(1.0, 0.0), Vector2(9.0, 0.0), 0.5))


# --- every visit of every zone can be played through -------------------------------------------

func test_every_visit_can_be_played_through() -> void:
	var pickup := _tuning.explore_pickup_radius * ZoneAutoplay.PICKUP_SHARE
	var radius := ZoneController.LEADER_RADIUS
	for layout: ZoneData in _zones():
		for seed_value: int in range(1, SEEDS + 1):
			var zone := ZoneAssembler.assemble(layout, seed_value)
			var label := "%s seed %d" % [zone.id, seed_value]
			var open := ZoneMotion.obstacles(zone)
			var exit := Vector2(zone.exit_spot.x, zone.exit_spot.z)
			open.append({"centre": exit, "radius": _explore.exit_solid_radius})
			for i: int in zone.offers.size():
				var spot := zone.offer_spots[i]
				open.append({"centre": Vector2(spot.x, spot.z), "radius": zone.offers[i].solid_radius})
			var shut := open.duplicate()
			var g := zone.gate
			shut.append({"centre": Vector2(g.position.x, g.position.z), "half": Vector2(g.size.x, g.size.z) * 0.5,
					"angle": deg_to_rad(g.rotation_y_degrees)})
			var start := Vector2(zone.player_start.x, zone.player_start.z)
			var before := ZonePath.build(shut, zone.bounds_min, zone.bounds_max, radius)
			var after := ZonePath.build(open, zone.bounds_min, zone.bounds_max, radius)
			assert_true(before.is_free(before.cell_of(start)), label + ": the start is free")
			for seal: Vector3 in zone.seal_spots:
				assert_true(before.reachable(start, Vector2(seal.x, seal.z), pickup), label + ": seal %s with the gate shut" % seal)
			for list: Array[Vector3] in [zone.item_spots, zone.chests]:
				for spot: Vector3 in list:
					assert_true(after.reachable(start, Vector2(spot.x, spot.z), pickup), label + ": %s" % spot)
			var talk := _tuning.explore_pickup_radius * ZoneAutoplay.OFFER_SHARE
			for spot: Vector3 in zone.offer_spots:
				assert_true(after.reachable(start, Vector2(spot.x, spot.z), talk), label + ": shrine %s" % spot)
			for e: ZoneEnemyData in zone.enemies:
				var home := Vector2(e.position.x, e.position.z)
				assert_true(after.reachable(start, home, _tuning.explore_touch_radius), label + ": %s" % e.encounter.id)
				if e.champion:
					assert_true(after.reachable(home, Vector2(e.prize_spot.x, e.prize_spot.z), pickup), label + ": prize")
				if e.guard:
					assert_false(before.reachable(start, home, _tuning.explore_strike_reach), label + ": the gate shuts the guard off")
					assert_true(after.reachable(home, exit, _tuning.zone_exit_reach * ZoneAutoplay.PICKUP_SHARE),
							label + ": from the guard to the exit")
					assert_false(before.reachable(start, exit, _tuning.zone_exit_reach), label + ": the gate shuts the exit off")
				assert_gt(home.distance_to(start), _tuning.explore_notice_radius, label + ": nobody waits at the start")


func test_every_zone_fight_exists() -> void:
	for zone: ZoneData in _zones():
		for encounter: EncounterData in ZoneAssembler.encounters(zone):
			assert_gt(encounter.enemies.size(), 0, "%s: %s has enemies" % [zone.id, encounter.id])
		assert_false(zone.roamer_pool.is_empty(), "%s has fights for its roaming spots" % zone.id)
		assert_false(zone.shrines.is_empty(), "%s has shrines" % zone.id)
		assert_false(zone.wanderers.is_empty(), "%s has wanderers" % zone.id)


# --- the exit (card #241) ---------------------------------------------------------------------

func test_a_cleared_run_zone_with_an_exit_stays_open() -> void:
	assert_true(ZoneController.keeps_open(true, true), "a run zone with an exit: leave when you want")
	assert_false(ZoneController.keeps_open(true, false), "no exit: on to the map at once")
	assert_false(ZoneController.keeps_open(false, true), "practice ends when every enemy is beaten")


## The goal is icon chips, not sentences (phase 22).
func test_the_goal_names_the_way_out_once_the_guard_falls() -> void:
	var before := ZoneController.goal_chips(1, 2, false, true, true, false, 5, true)
	assert_eq(before, [{"icon": ZoneController.GOAL_SEAL, "text": "Seals 1/2"},
			{"icon": ZoneController.GOAL_GUARD, "text": "GUARD"}, {"icon": ZoneController.GOAL_FOE, "text": "4 left"}]
			as Array[Dictionary])
	var after := ZoneController.goal_chips(2, 2, true, true, true, true, 3, true)
	assert_eq(after, [{"icon": ZoneController.GOAL_EXIT, "text": "EXIT"},
			{"icon": ZoneController.GOAL_FOE, "text": "3 left"}] as Array[Dictionary])
	var no_exit := ZoneController.goal_chips(2, 2, true, true, true, true, 3, false)
	assert_eq(no_exit[0], {"icon": ZoneController.GOAL_EXIT, "text": "OPEN"})
	var all_beaten := ZoneController.goal_chips(2, 2, true, true, true, true, 0, true)
	assert_eq(all_beaten.size(), 1, "no enemy chip once they are all beaten")
	var practice := ZoneController.goal_chips(0, 0, true, false, true, false, 0, true)
	assert_eq(practice, [{"icon": ZoneController.GOAL_FOE, "text": "0 left"}] as Array[Dictionary])


# --- shrines and wanderers --------------------------------------------------------------------

func _run() -> RunState:
	return RunState.begin(_run_data, _tuning, 42)


func test_a_deal_takes_its_price_and_gives_its_gifts() -> void:
	var run := _run()
	run.gold = 100
	var offer := ZoneOfferData.new()
	offer.cost_gold = 40
	offer.xp = 10
	offer.team_gauge = 30
	var result := run.take_offer(offer, 0, 0)
	assert_true(bool(result.ok))
	assert_eq(run.gold, 60, "paid")
	assert_eq(run.xps[0], 10, "every hero got the XP")
	assert_eq(run.team_gauge, 30)
	assert_null(result.item)


func test_a_deal_too_dear_changes_nothing() -> void:
	var run := _run()
	run.gold = 10
	var offer := ZoneOfferData.new()
	offer.cost_gold = 40
	offer.xp = 10
	assert_false(run.can_take_offer(offer))
	var result := run.take_offer(offer, 0, 0)
	assert_false(bool(result.ok))
	assert_eq(run.gold, 10)
	assert_eq(run.xps[0], 0)


func test_blood_costs_never_kill_and_heals_never_overfill() -> void:
	var run := _run()
	run.hp[0] = 2
	var full := run.max_hp(1)
	var blood := ZoneOfferData.new()
	blood.cost_hp_percent = 50
	run.take_offer(blood, 0, 0)
	assert_eq(run.hp[0], 1, "never below 1 HP")
	assert_eq(run.hp[1], full - CombatMath.percent(full, 50))
	var spring := ZoneOfferData.new()
	spring.heal_percent = 100
	run.take_offer(spring, 0, 1)
	assert_eq(run.hp[1], full, "healed up to max, not over")


func test_a_find_from_a_deal_is_seeded_and_rare() -> void:
	var offer := ZoneOfferData.new()
	offer.find_rarity = ItemData.Rarity.RARE
	var a := _run().take_offer(offer, 1, 2).item as ItemData
	var b := _run().take_offer(offer, 1, 2).item as ItemData
	assert_not_null(a)
	assert_eq(a, b, "the same run, stop and deal give the same find")
	assert_gte(a.rarity, ItemData.Rarity.RARE)


func test_zone_seeds_differ_by_stop_and_match_on_every_machine() -> void:
	assert_eq(_run().zone_seed(3), _run().zone_seed(3))
	assert_ne(_run().zone_seed(3), _run().zone_seed(4))


func test_shipped_deals_make_sense() -> void:
	var seen := 0
	for file: String in DirAccess.get_files_at("res://data/offers"):
		if not file.ends_with(".tres"):
			continue
		var offer := load("res://data/offers".path_join(file)) as ZoneOfferData
		seen += 1
		assert_false(offer.question.is_empty(), "%s asks something" % offer.id)
		var gives := offer.heal_percent + offer.gold + offer.xp + offer.team_gauge + (1 if offer.item != null else 0) \
				+ (1 if offer.find_rarity >= 0 else 0)
		assert_gt(gives, 0, "%s gives something" % offer.id)
		assert_true(ResourceLoader.exists(offer.sprite_path), "%s has its sprite" % offer.id)
	assert_eq(seen, 7, "four shrines and three wanderers")


# --- living zones (DESIGN.md 8.12) --------------------------------------------------------------

func test_deep_water_blocks_walking_but_not_its_shore() -> void:
	var pool := ZoneGroundData.new()
	pool.kind = ZoneGroundData.Kind.WATER
	pool.solid = true
	pool.round = true
	pool.size = Vector2(8.0, 4.0)
	var obstacles := ZoneMotion.ground_obstacles(pool)
	assert_gt(obstacles.size(), 1, "an ellipse is filled with circles")
	var into := ZoneMotion.move(Vector2(-6.0, 0.0), Vector2(6.0, 0.0), 0.35, obstacles, Vector2(-20, -20), Vector2(20, 20))
	assert_lt(into.x, -2.0, "a walker cannot wade into deep water")
	var past := ZoneMotion.move(Vector2(-6.0, 3.0), Vector2(12.0, 0.0), 0.35, obstacles, Vector2(-20, -20), Vector2(20, 20))
	assert_almost_eq(past.x, 6.0, 0.01, "and walks past it on the bank")
	var rect := ZoneGroundData.new()
	rect.solid = true
	rect.size = Vector2(6.0, 2.0)
	rect.rotation_y_degrees = 90.0
	var box := ZoneMotion.ground_obstacles(rect)
	assert_eq(box.size(), 1)
	assert_true(ZonePath._overlaps(Vector2(0.0, 2.5), 0.1, box[0]), "turned with the piece")


func test_every_zone_is_alive() -> void:
	for layout: ZoneData in _zones():
		var zone := ZoneAssembler.assemble(layout, 3)
		assert_false(zone.ambient.is_empty(), "%s has something in the air" % zone.id)
		assert_gt(zone.critters.size(), 3, "%s has critters" % zone.id)
		assert_gt(zone.grounds.size(), 10, "%s has ground pieces" % zone.id)
		var swaying := 0
		for p: ZonePropData in zone.props:
			if p.sway > 0.0:
				swaying += 1
			var art := p.piece.model_path if p.piece != null else p.sprite_path
			assert_true(ResourceLoader.exists(art), "%s: %s exists" % [zone.id, art])
		assert_gt(swaying, 10, "%s: plants sway in the wind" % zone.id)
		for g: ZoneGroundData in zone.grounds:
			assert_true(ResourceLoader.exists(g.texture_path), "%s: %s exists" % [zone.id, g.texture_path])
		for c: ZoneCritterData in zone.critters:
			assert_true(ResourceLoader.exists(c.sprite_path))
		for a: ZoneAmbientData in zone.ambient:
			assert_true(ResourceLoader.exists(a.texture_path))
	var bog := ZoneAssembler.assemble(load("res://data/zones/sunken_bog.tres") as ZoneData, 3)
	var water := 0
	for g: ZoneGroundData in bog.grounds:
		if g.kind == ZoneGroundData.Kind.WATER and g.solid:
			water += 1
	assert_gt(water, 4, "the swamp has deep water")
