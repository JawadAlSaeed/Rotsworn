class_name ZoneAssembler
extends RefCounted
## Builds one visit of a long zone (DESIGN.md 8.5): the start section, middle_count of the middle
## sections (picked and shuffled by the seed), then the end section, laid end to end from x = 0 to
## the right. Each section's contents are moved by its place along x; the seed also decides which
## roaming spots are filled and with which fight, where each section's seal stands, which shrine
## stands at each shrine spot and whether (and where) a wanderer is met. Walls go along the back
## and at both ends. The same zone and seed always give the same result (online, every machine
## builds the same zone). Pure: no nodes. Unit-tested.

## Half the height (z) of the lane every section keeps free at both ends, so any two join.
const LANE: float = 3.0
## Thickness of the walls along the back and at the ends.
const WALL: float = 2.0


## True if the zone is built from sections (otherwise it is used as it is).
static func is_sectioned(zone: ZoneData) -> bool:
	return zone != null and zone.start_section != null and zone.end_section != null


## The zone for one visit. A zone without sections comes back unchanged.
static func assemble(zone: ZoneData, seed_value: int) -> ZoneData:
	if not is_sectioned(zone):
		return zone
	var rng := CombatRng.new(maxi(1, absi(seed_value)))
	var out := ZoneData.new()
	out.id = zone.id
	out.display_name = zone.display_name
	out.map_icon_path = zone.map_icon_path
	out.look = zone.look
	out.leader = zone.leader
	out.footstep_sfx = zone.footstep_sfx
	out.music_path = zone.music_path
	out.ambience_path = zone.ambience_path
	out.ambience_volume_db = zone.ambience_volume_db
	out.blocks.append_array(zone.blocks)
	out.props.append_array(zone.props)
	out.lights.append_array(zone.lights)
	out.enemies.append_array(zone.enemies)
	out.item_spots.append_array(zone.item_spots)
	out.chests.append_array(zone.chests)

	var sections: Array[ZoneSectionData] = [zone.start_section]
	sections.append_array(pick_middles(zone, rng))
	sections.append(zone.end_section)

	var shrine_bag: Array[ZoneOfferData] = []
	var wanderer_spots: Array[Vector3] = []
	var x := 0.0
	for section: ZoneSectionData in sections:
		var at := Vector3(x, 0.0, 0.0)
		for block: ZoneBlockData in section.blocks:
			out.blocks.append(_moved_block(block, at))
		for prop: ZonePropData in section.props:
			var p := prop.duplicate() as ZonePropData
			p.position += at
			out.props.append(p)
		for light: ZoneLightData in section.lights:
			var l := light.duplicate() as ZoneLightData
			l.position += at
			out.lights.append(l)
		for enemy: ZoneEnemyData in section.enemies:
			if enemy == null:
				continue
			# Always roll, so one spot's chance never shifts the picks of the spots after it.
			var roll := rng.range_int(0, 99)
			var pick := rng.range_int(0, maxi(0, zone.roamer_pool.size() - 1))
			if roll >= enemy.chance_percent and not enemy.guard:
				continue
			var e := enemy.duplicate() as ZoneEnemyData
			e.position += at
			e.prize_spot += at
			if e.encounter == null and not zone.roamer_pool.is_empty():
				e.encounter = zone.roamer_pool[pick]
			if e.encounter != null:
				out.enemies.append(e)
		for spot: Vector3 in section.item_spots:
			out.item_spots.append(spot + at)
		for spot: Vector3 in section.chests:
			out.chests.append(spot + at)
		if not section.seal_spots.is_empty():
			out.seal_spots.append(section.seal_spots[rng.range_int(0, section.seal_spots.size() - 1)] + at)
		for spot: Vector3 in section.shrine_spots:
			if zone.shrines.is_empty():
				break
			if shrine_bag.is_empty():
				shrine_bag.assign(zone.shrines)
			out.offers.append(shrine_bag.pop_at(rng.range_int(0, shrine_bag.size() - 1)))
			out.offer_spots.append(spot + at)
		for spot: Vector3 in section.wanderer_spots:
			wanderer_spots.append(spot + at)
		if section.gate != null:
			out.gate = _moved_block(section.gate, at)
		if section == zone.start_section:
			out.player_start = section.player_start + at
		x += section.width

	var meet := rng.range_int(0, 99)
	if meet < zone.wanderer_percent and not wanderer_spots.is_empty() and not zone.wanderers.is_empty():
		out.offers.append(zone.wanderers[rng.range_int(0, zone.wanderers.size() - 1)])
		out.offer_spots.append(wanderer_spots[rng.range_int(0, wanderer_spots.size() - 1)])

	out.bounds_min = Vector2(0.0, zone.bounds_min.y)
	out.bounds_max = Vector2(x, zone.bounds_max.y)
	_add_walls(out, zone)
	return out


## Every fight a zone can hold on any visit: its own enemies', its roamer pool and its sections'.
static func encounters(zone: ZoneData) -> Array[EncounterData]:
	var found: Array[EncounterData] = []
	var lists: Array = [zone.enemies]
	for section: ZoneSectionData in [zone.start_section, zone.end_section] + Array(zone.middle_sections):
		if section != null:
			lists.append(section.enemies)
	for list: Array in lists:
		for e: ZoneEnemyData in list:
			if e != null and e.encounter != null and not found.has(e.encounter):
				found.append(e.encounter)
	for encounter: EncounterData in zone.roamer_pool:
		if encounter != null and not found.has(encounter):
			found.append(encounter)
	return found


## The middle sections of one visit: middle_count of the pool, in a shuffled order.
static func pick_middles(zone: ZoneData, rng: CombatRng) -> Array[ZoneSectionData]:
	var bag: Array[ZoneSectionData] = []
	for section: ZoneSectionData in zone.middle_sections:
		if section != null:
			bag.append(section)
	var picked: Array[ZoneSectionData] = []
	while picked.size() < zone.middle_count and not bag.is_empty():
		picked.append(bag.pop_at(rng.range_int(0, bag.size() - 1)))
	return picked


static func _moved_block(block: ZoneBlockData, at: Vector3) -> ZoneBlockData:
	var b := block.duplicate() as ZoneBlockData
	b.position += at
	return b


## A wall along the back and one at each end (just outside the bounds), in the zone's edge texture.
static func _add_walls(out: ZoneData, zone: ZoneData) -> void:
	if zone.edge_texture_path.is_empty():
		return
	var lo := out.bounds_min
	var hi := out.bounds_max
	var depth := hi.y - lo.y
	var walls: Array[Array] = [
		[Vector3((lo.x + hi.x) * 0.5, 0.0, lo.y - WALL * 0.5), Vector3(hi.x - lo.x + WALL * 2.0, zone.edge_height, WALL)],
		[Vector3(lo.x - WALL * 0.5, 0.0, (lo.y + hi.y) * 0.5), Vector3(WALL, zone.edge_height, depth)],
		[Vector3(hi.x + WALL * 0.5, 0.0, (lo.y + hi.y) * 0.5), Vector3(WALL, zone.edge_height, depth)],
	]
	for wall: Array in walls:
		var block := ZoneBlockData.new()
		block.position = wall[0]
		block.size = wall[1]
		block.texture_path = zone.edge_texture_path
		out.blocks.append(block)
