extends SceneTree
## Writes the long zones (DESIGN.md 8.5, 8.12): the shrines and wanderers (data/offers/), the
## sections of each zone (data/zones/sections/) and the zones themselves (data/zones/), which keep
## their id, name, look, leader, map picture, sounds and fights but are built from sections.
## Every zone has its own places (user, 2026-10-17: "the ruins should have ruins, roads; the swamp
## should have a swamp, jungle; make the zones feel alive"):
## - Ashen Ruins, a dead city: a cobbled road through it all, a gate, an old road between broken
##   walls, a plaza with a dry fountain and statues, a colonnade, a walled graveyard with a crypt
##   (the champion), a collapsed hall; braziers, banners, ash falling, embers, crows and rats.
## - Sunken Bog, swamp and jungle: water everywhere with boardwalks across, a stilt village, a
##   mangrove tangle, a lily pond (the champion on a spit of land), a glowing mushroom grove;
##   reeds, lily pads, lanterns, fireflies, mist and spores, frogs and crows.
## - Rotten Hollow, a rotting forest: a dirt trail under dense trees, a forest trail with a side
##   clearing, a woodcutter's camp with a campfire, a ruined chapel yard (the champion), a thorn
##   thicket, a giant fallen tree; ferns, bushes, falling leaves, fireflies, crows and rats.
## Solid decoration keeps clear of every spot that matters and of water; tests check that every
## spot can be reached on many visits (tests/unit/test_long_zones.gd).
## Run: Godot --headless --path . -s tools/bootstrap_zones.gd   (after tools/bootstrap_phase15.gd)

const ENV := "res://assets/sprites/env/"
const FX := "res://assets/sprites/fx/"
const SHROOM_GLOW := Color(0.35, 1.0, 0.85)
const LAMP_LIGHT := Color(1.0, 0.68, 0.38)
const BOG_LIGHT := Color(0.55, 1.0, 0.6)
const FIRE_LIGHT := Color(1.0, 0.55, 0.25)
## The depth of every long zone (z), the same frame every section is drawn in.
const Z_BACK: float = -20.0
const Z_FRONT: float = 10.0
## Scattered solid decoration keeps this far from every spot that matters.
const KEEP_OUT: float = 2.0

var _written: int = 0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/offers"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/zones/sections"))
	var offers := _offers()
	_zone("ashen_ruins", offers, "res://data/encounters/guard_ash_warden.tres", ENV + "ruin_wall.png",
			[_start_ruins(), _ruins_road(), _ruins_plaza(), _ruins_colonnade(), _ruins_graveyard(), _ruins_hall(),
			_end_ruins()], _ruins_air())
	_zone("sunken_bog", offers, "res://data/encounters/guard_mire_mother.tres", "",
			[_start_bog(), _bog_boardwalk(), _bog_village(), _bog_mangroves(), _bog_pond(), _bog_grove(), _end_bog()],
			_bog_air())
	_zone("rotten_hollow", offers, "res://data/encounters/guard_gorged_one.tres", "",
			[_start_hollow(), _hollow_trail(), _hollow_camp(), _hollow_chapel(), _hollow_thicket(), _hollow_fallen(),
			_end_hollow()], _hollow_air())
	var hollow_look := load("res://data/looks/rotten_hollow.tres") as StageLook
	hollow_look.floor_tile_path = ENV + "hollow_floor.png"
	hollow_look.floor_variant_paths = [ENV + "hollow_floor_b.png", ENV + "hollow_floor_c.png"]
	_save(hollow_look, hollow_look.resource_path)
	print("bootstrap_zones: wrote %d files" % _written)
	quit()


# --- shrines and wanderers --------------------------------------------------------------------

func _offers() -> Dictionary:
	var key := load("res://data/items/key.tres") as ItemData
	var list := {}
	list.spring = _offer("healing_spring", "Healing Spring", ZoneOfferData.Kind.SHRINE, "shrine_spring",
			"Drink from the Healing Spring?", "Free. Everyone heals 30% of their HP.", "Drink", SHROOM_GLOW)
	list.spring.heal_percent = 30
	list.altar = _offer("blood_altar", "Blood Altar", ZoneOfferData.Kind.SHRINE, "shrine_altar",
			"Bleed on the Blood Altar?", "Everyone loses 20% of their max HP (never below 1).\nThe altar gives something rare.",
			"Bleed", Color(1.0, 0.3, 0.25))
	list.altar.cost_hp_percent = 20
	list.altar.find_rarity = ItemData.Rarity.RARE
	list.idol = _offer("war_idol", "War Idol", ZoneOfferData.Kind.SHRINE, "shrine_idol",
			"Pray to the War Idol?", "Free. The team gauge fills by 50.", "Pray", Color(1.0, 0.7, 0.3))
	list.idol.team_gauge = 50
	list.plenty = _offer("shrine_of_plenty", "Shrine of Plenty", ZoneOfferData.Kind.SHRINE, "shrine_plenty",
			"Leave 40 gold at the Shrine of Plenty?", "Every hero gets 40 XP.", "Leave the gold", Color(1.0, 0.85, 0.4))
	list.plenty.cost_gold = 40
	list.plenty.xp = 40
	list.peddler = _offer("key_peddler", "Key Peddler", ZoneOfferData.Kind.WANDERER, "wanderer_peddler",
			"\"A key for 30 gold?\"", "The Key Peddler sells one key. Keys open locked chests.", "Buy the key",
			LAMP_LIGHT)
	list.peddler.cost_gold = 30
	list.peddler.item = key
	list.robber = _offer("grave_robber", "Grave Robber", ZoneOfferData.Kind.WANDERER, "wanderer_robber",
			"\"Something rare, 45 gold. No questions.\"", "The Grave Robber sells one rare or better find.",
			"Pay 45 gold", Color(0.75, 0.6, 1.0))
	list.robber.cost_gold = 45
	list.robber.find_rarity = ItemData.Rarity.RARE
	list.pilgrim = _offer("old_pilgrim", "Old Pilgrim", ZoneOfferData.Kind.WANDERER, "wanderer_pilgrim",
			"\"Rest by my fire a while?\"", "Free. Everyone heals 15% and gets 20 XP.", "Rest", LAMP_LIGHT)
	list.pilgrim.heal_percent = 15
	list.pilgrim.xp = 20
	for name: String in list:
		var offer := list[name] as ZoneOfferData
		list[name] = _save(offer, "res://data/offers/%s.tres" % offer.id)
	return list


func _offer(id: String, title: String, kind: ZoneOfferData.Kind, sprite: String, question: String, detail: String,
		yes: String, color: Color) -> ZoneOfferData:
	var offer := ZoneOfferData.new()
	offer.id = id
	offer.display_name = title
	offer.kind = kind
	offer.sprite_path = ENV + sprite + ".png"
	offer.pixel_size = 0.05 if kind == ZoneOfferData.Kind.SHRINE else 0.045
	offer.question = question
	offer.detail = detail
	offer.yes_text = yes
	offer.no_text = "Not now"
	offer.glow = 1.2 if kind == ZoneOfferData.Kind.SHRINE else 0.0
	offer.glow_color = color
	offer.solid_radius = 0.5 if kind == ZoneOfferData.Kind.SHRINE else 0.35
	return offer


# --- a zone -----------------------------------------------------------------------------------

## `sections`: start, five middles, end (each already built, saved here). `edge`: the texture of the
## walls along the back and the ends ("" for none: a tree line stands there instead).
func _zone(id: String, offers: Dictionary, guard_path: String, edge: String, sections: Array,
		ambient: Array[ZoneAmbientData]) -> void:
	var path := "res://data/zones/%s.tres" % id
	var zone := load(path) as ZoneData
	var pool: Array[EncounterData] = []
	pool.assign(zone.roamer_pool)
	var guard := load(guard_path) as EncounterData
	for sec: ZoneSectionData in sections:
		for e: ZoneEnemyData in sec.enemies:
			if e.guard:
				e.encounter = guard
	zone.blocks.clear()
	zone.props.clear()
	zone.lights.clear()
	zone.grounds.clear()
	zone.critters.clear()
	zone.enemies.clear()
	zone.item_spots.clear()
	zone.chests.clear()
	zone.seal_spots.clear()
	zone.gate = null
	zone.offers.clear()
	zone.offer_spots.clear()
	zone.ambient.assign(ambient)
	zone.bounds_min = Vector2(0.0, Z_BACK)
	zone.bounds_max = Vector2(1.0, Z_FRONT)
	zone.player_start = Vector3.ZERO
	zone.roamer_pool.assign(pool)
	zone.shrines.assign([offers.spring, offers.altar, offers.idol, offers.plenty])
	zone.wanderers.assign([offers.peddler, offers.robber, offers.pilgrim])
	zone.wanderer_percent = 60
	zone.middle_count = 3
	zone.edge_texture_path = edge
	zone.edge_height = 4.5
	var saved: Array[ZoneSectionData] = []
	for sec: ZoneSectionData in sections:
		sec.id = "%s_%s" % [id, sec.id]
		saved.append(_save(sec, "res://data/zones/sections/%s.tres" % sec.id) as ZoneSectionData)
	zone.start_section = saved[0]
	zone.middle_sections.assign(saved.slice(1, 6))
	zone.end_section = saved[6]
	_save(zone, path)
	for old: String in DirAccess.get_files_at("res://data/zones/sections"):
		if old.begins_with(id + "_") and old.ends_with(".tres"):
			var keep := false
			for sec: ZoneSectionData in saved:
				keep = keep or old == sec.id + ".tres"
			if not keep:
				DirAccess.remove_absolute(ProjectSettings.globalize_path("res://data/zones/sections/" + old))


func _new(kind: String, width: float, seed_value: int) -> ZoneSectionData:
	var sec := ZoneSectionData.new()
	sec.id = kind
	sec.width = width
	_rng.seed = seed_value
	return sec


# ================================================================================================
# Ashen Ruins: a dead city under falling ash
# ================================================================================================

const RUIN_ROAD := ENV + "road_cobble.png"
const RUIN_PAVING := ENV + "paving.png"
const RUIN_ASH := ENV + "ash_ground.png"
const ROAD_TINT := Color(0.86, 0.84, 0.86)


func _ruins_air() -> Array[ZoneAmbientData]:
	return [
		_air("ash", FX + "ash_flake.png", Color(0.82, 0.8, 0.78), 0.0, 80, 7.0, 0.07, Vector3(14, 3, 4.5), 3.0,
				Vector3(0.18, -0.32, 0.04), 25.0, 0.2),
		_air("embers", FX + "mote.png", Color(1.0, 0.55, 0.2), 2.6, 22, 5.0, 0.06, Vector3(13, 1.2, 8), 0.8,
				Vector3(0.05, 0.35, 0.0), 40.0, 0.5),
	]


## A brazier with its fire light.
func _brazier(sec: ZoneSectionData, at: Vector2) -> void:
	_p(sec, "brazier", at, 0.05, 0.4, 0.0, false, 1.0, FIRE_LIGHT)
	sec.lights.append(_light(Vector3(at.x, 1.6, at.y + 0.3), FIRE_LIGHT, 2.8, 7.5, 18))


## A broken wall: a low ruin block from `a` to `b` (on the ground) and its rubble.
func _ruin_wall(sec: ZoneSectionData, a: Vector2, b: Vector2, height: float = 1.6, thick: float = 0.8) -> void:
	var mid := (a + b) * 0.5
	var length := a.distance_to(b)
	var turn := -rad_to_deg((b - a).angle())
	sec.blocks.append(_block(Vector3(mid.x, 0.0, mid.y), Vector3(length, height, thick), "ruin_wall", turn))


func _start_ruins() -> ZoneSectionData:
	var sec := _new("start", 18.0, 1101)
	sec.player_start = Vector3(2.5, 0.0, 1.0)
	_path(sec, [Vector2(-1, 0.4), Vector2(9, -0.2), Vector2(19, 0.2)], 4.2, RUIN_ROAD, 1, ROAD_TINT)
	# The old city gate: two posts either side of the road, banners on them.
	sec.blocks.append(_block(Vector3(6.5, 0, -3.9), Vector3(1.6, 3.6, 1.6), "ruin_wall"))
	sec.blocks.append(_block(Vector3(6.5, 0, 3.9), Vector3(1.6, 3.0, 1.6), "ruin_wall"))
	_ruin_wall(sec, Vector2(6.5, -5.0), Vector2(6.5, -12.0), 2.4, 1.0)
	_ruin_wall(sec, Vector2(6.5, 5.0), Vector2(6.5, 8.0), 1.2, 1.0)
	_p(sec, "banner_torn", Vector2(7.6, -4.8), 0.05, 0.0, 0.05)
	_p(sec, "banner_torn", Vector2(7.6, 4.9), 0.05, 0.0, 0.05, true)
	_brazier(sec, Vector2(11.5, -3.4))
	_brazier(sec, Vector2(11.5, 3.6))
	_p(sec, "statue_headless", Vector2(12.0, -14.0), 0.05, 1.0)
	_ground(sec, Vector2(10, -9), Vector2(8, 5), RUIN_ASH, true, 0)
	_ground(sec, Vector2(14, 7), Vector2(7, 3), RUIN_ASH, true, 0)
	_p(sec, "rubble", Vector2(3.5, -8.5), 0.05, 0.8)
	_p(sec, "rubble", Vector2(15.5, 6.5), 0.05, 0.8)
	_p(sec, "dead_tree", Vector2(2.0, -17.0), 0.05, 0.4)
	_p(sec, "bones", Vector2(9.0, 6.0), 0.045, 0.0)
	sec.item_spots.append(Vector3(3.0, 0, -13.0))
	_critter(sec, ZoneCritterData.Kind.CROW, Vector2(14.5, -9.0))
	_critter(sec, ZoneCritterData.Kind.RAT, Vector2(4.0, 6.5))
	_ruins_back(sec)
	return sec


## Behind every ruins section: arches and broken walls against the back wall; dead grass between
## the stones.
func _ruins_back(sec: ZoneSectionData) -> void:
	_scatter(sec, [["grass", 0.045, 0.0, 0.05]], int(sec.width / 3.0))
	var x := 3.0 + _rng.randf() * 4.0
	while x < sec.width - 2.0:
		var kind := _rng.randi_range(0, 2)
		if kind == 0:
			_p(sec, "arch_broken", Vector2(x, -19.6), 0.05, 0.0)
		elif kind == 1:
			_p(sec, "wall_low", Vector2(x, -19.4), 0.05, 0.0)
		else:
			_p(sec, "pillar", Vector2(x, -19.5), 0.05, 0.0)
		x += 5.0 + _rng.randf() * 4.0


## The old road: a straight stretch between broken walls, an alley behind them to a burnt house.
func _ruins_road() -> ZoneSectionData:
	var sec := _new("road", 32.0, 1201)
	_path(sec, [Vector2(-1, 0.2), Vector2(10, -0.4), Vector2(22, 0.5), Vector2(33, 0.0)], 4.4, RUIN_ROAD, 1, ROAD_TINT)
	_ruin_wall(sec, Vector2(3, -4.6), Vector2(12, -4.6), 1.5)
	_ruin_wall(sec, Vector2(16, -4.6), Vector2(27, -4.6), 1.3)
	_ruin_wall(sec, Vector2(6, 4.8), Vector2(14, 4.8), 1.1)
	_ruin_wall(sec, Vector2(19, 4.8), Vector2(29, 4.8), 1.2)
	# The burnt house at the back right, its door toward the alley.
	_ruin_wall(sec, Vector2(18, -9), Vector2(18, -16.5), 2.6, 0.9)
	_ruin_wall(sec, Vector2(18, -16.5), Vector2(29.5, -16.5), 2.8, 0.9)
	_ruin_wall(sec, Vector2(29.5, -16.5), Vector2(29.5, -9), 2.2, 0.9)
	_ruin_wall(sec, Vector2(18, -9), Vector2(21.5, -9), 2.0, 0.9)
	_ruin_wall(sec, Vector2(25.5, -9), Vector2(29.5, -9), 1.6, 0.9)
	_ground(sec, Vector2(23.7, -12.7), Vector2(10, 6.6), RUIN_PAVING, false, 0, 0.2)
	sec.seal_spots.assign([Vector3(23.5, 0, -13.0), Vector3(8.0, 0, -14.5)])
	sec.item_spots.append(Vector3(28.5, 0, 7.5))
	sec.shrine_spots.append(Vector3(9.0, 0, 7.0))
	sec.enemies.append(_roamer(Vector2(10, 0.5), 2.5, 85))
	sec.enemies.append(_roamer(Vector2(24, -12.5), 1.6, 70))
	sec.enemies.append(_roamer(Vector2(25, 6.5), 2.0, 45))
	_brazier(sec, Vector2(14.0, -3.0))
	_brazier(sec, Vector2(16.5, 3.4))
	_p(sec, "banner_torn", Vector2(12.5, -5.6), 0.05, 0.0, 0.05)
	_p(sec, "column_fallen", Vector2(7.0, -10.5), 0.05, 1.2)
	_p(sec, "rubble", Vector2(21.0, -6.5), 0.05, 0.7)
	_p(sec, "rubble", Vector2(3.0, 7.5), 0.05, 0.7)
	_p(sec, "bones", Vector2(26.5, -6.2), 0.045, 0.0)
	_p(sec, "statue_headless", Vector2(3.0, -15.5), 0.05, 1.0)
	_ground(sec, Vector2(8, -14), Vector2(9, 6), RUIN_ASH, true, 0)
	_ground(sec, Vector2(16, 7.5), Vector2(10, 3.6), RUIN_ASH, true, 0)
	_critter(sec, ZoneCritterData.Kind.CROW, Vector2(13.0, -6.2))
	_critter(sec, ZoneCritterData.Kind.RAT, Vector2(21.0, 7.0))
	_critter(sec, ZoneCritterData.Kind.CROW, Vector2(27.0, -18.5))
	_ruins_back(sec)
	return sec


## The plaza: paved square, a dry fountain in the middle, statues, braziers; the road crosses it.
func _ruins_plaza() -> ZoneSectionData:
	var sec := _new("plaza", 34.0, 1301)
	_ground(sec, Vector2(17, -4.5), Vector2(25, 15), RUIN_PAVING, false, 0, 0.3)
	_path(sec, [Vector2(-1, 0.0), Vector2(6, 0.0)], 4.4, RUIN_ROAD, 1, ROAD_TINT)
	_path(sec, [Vector2(28, 0.0), Vector2(35, 0.0)], 4.4, RUIN_ROAD, 1, ROAD_TINT)
	_p(sec, "fountain", Vector2(17.0, -4.5), 0.05, 2.2)
	for at: Vector2 in [Vector2(8.5, -10.5), Vector2(25.5, -10.5)]:
		_p(sec, "statue_headless", at, 0.05, 1.0, 0.0, at.x > 17.0)
	_brazier(sec, Vector2(10.5, 2.6))
	_brazier(sec, Vector2(23.5, 2.6))
	_brazier(sec, Vector2(13.0, -10.5))
	_brazier(sec, Vector2(21.0, -10.5))
	_p(sec, "arch_broken", Vector2(17.0, -17.5), 0.05, 1.0)
	_p(sec, "banner_torn", Vector2(6.0, -6.0), 0.05, 0.0, 0.05)
	_p(sec, "banner_torn", Vector2(28.0, -6.0), 0.05, 0.0, 0.05, true)
	_p(sec, "column_fallen", Vector2(30.0, 7.0), 0.05, 1.2)
	_p(sec, "rubble", Vector2(4.0, 6.5), 0.05, 0.7)
	sec.seal_spots.assign([Vector3(17.0, 0, -14.5), Vector3(31.5, 0, -14.0)])
	sec.wanderer_spots.append(Vector3(6.0, 0, -12.0))
	sec.shrine_spots.append(Vector3(28.5, 0, -12.0))
	sec.chests.append(Vector3(3.0, 0, -17.5))
	sec.item_spots.append(Vector3(17.0, 0, 7.5))
	sec.enemies.append(_roamer(Vector2(12.0, -14.0), 2.0, 80))
	sec.enemies.append(_roamer(Vector2(24.0, 5.0), 2.5, 70))
	sec.enemies.append(_roamer(Vector2(8.0, 1.0), 2.0, 45))
	_ground(sec, Vector2(30, -16), Vector2(7, 6), RUIN_ASH, true, 1)
	_critter(sec, ZoneCritterData.Kind.CROW, Vector2(18.5, -2.2))
	_critter(sec, ZoneCritterData.Kind.CROW, Vector2(9.0, -12.5))
	_critter(sec, ZoneCritterData.Kind.RAT, Vector2(29.0, 5.5))
	_ruins_back(sec)
	return sec


## The colonnade: a covered walk of pillars at the back behind a low wall, rubble in front.
func _ruins_colonnade() -> ZoneSectionData:
	var sec := _new("colonnade", 32.0, 1401)
	_path(sec, [Vector2(-1, 1.0), Vector2(16, 0.4), Vector2(33, 1.0)], 4.4, RUIN_ROAD, 1, ROAD_TINT)
	_ground(sec, Vector2(16, -11), Vector2(25, 8.5), RUIN_PAVING, false, 0, 0.25)
	var x := 5.5
	while x <= 27.0:
		_p(sec, "pillar", Vector2(x, -7.2), 0.05, 0.45)
		_p(sec, "pillar", Vector2(x, -14.8), 0.05, 0.45, 0.0, true)
		x += 4.3
	_ruin_wall(sec, Vector2(3, -4.8), Vector2(12, -4.8), 1.2)
	_ruin_wall(sec, Vector2(20, -4.8), Vector2(29, -4.8), 1.0)
	_p(sec, "column_fallen", Vector2(14.0, 6.5), 0.05, 1.2)
	for at: Vector2 in [Vector2(5.0, 6.0), Vector2(23.0, 7.5), Vector2(28.5, 6.0)]:
		_p(sec, "rubble", at, 0.05, 0.7)
	_brazier(sec, Vector2(16.0, -3.4))
	sec.seal_spots.assign([Vector3(27.5, 0, -11.0), Vector3(4.0, 0, -11.0)])
	sec.item_spots.append(Vector3(18.0, 0, 7.8))
	sec.shrine_spots.append(Vector3(9.0, 0, 7.0))
	sec.wanderer_spots.append(Vector3(30.0, 0, -18.0))
	sec.enemies.append(_roamer(Vector2(16.0, -11.0), 3.0, 85))
	sec.enemies.append(_roamer(Vector2(8.0, 2.0), 2.0, 70))
	sec.enemies.append(_roamer(Vector2(25.0, 1.5), 2.0, 50))
	_ground(sec, Vector2(20, 7), Vector2(12, 4), RUIN_ASH, true, 0)
	_critter(sec, ZoneCritterData.Kind.CROW, Vector2(12.0, -5.8))
	_critter(sec, ZoneCritterData.Kind.RAT, Vector2(20.0, -11.0))
	_ruins_back(sec)
	return sec


## The graveyard: rows of headstones round a walled crypt yard where a champion keeps its prize.
func _ruins_graveyard() -> ZoneSectionData:
	var sec := _new("graveyard", 32.0, 1501)
	_path(sec, [Vector2(-1, 0.4), Vector2(16, 1.2), Vector2(33, 0.4)], 4.0, RUIN_ROAD, 1, ROAD_TINT)
	_ruin_wall(sec, Vector2(9, -9), Vector2(9, -20), 2.4, 0.9)
	_ruin_wall(sec, Vector2(23, -9), Vector2(23, -20), 2.4, 0.9)
	_ruin_wall(sec, Vector2(9, -9), Vector2(13.6, -9), 2.4, 0.9)
	_ruin_wall(sec, Vector2(18.4, -9), Vector2(23, -9), 2.4, 0.9)
	_ground(sec, Vector2(16, -14.5), Vector2(13, 10.5), RUIN_PAVING, false, 0, 0.2)
	var champion := _roamer(Vector2(16.0, -13.5), 0.0, 100)
	champion.encounter = load("res://data/encounters/elite_shade_coven.tres") as EncounterData
	champion.champion = true
	champion.prize_spot = Vector3(16.0, 0, -18.0)
	sec.enemies.append(champion)
	_brazier(sec, Vector2(12.5, -7.6))
	_brazier(sec, Vector2(19.5, -7.6))
	for row: int in 3:
		for col: int in 4:
			var at := Vector2(2.0 + col * 1.9, -6.5 - row * 3.6 + (col % 2) * 0.4)
			_p(sec, "gravestone", at, 0.05, 0.0, 0.0, col % 2 == 0)
			_p(sec, "gravestone", Vector2(32.0 - at.x, at.y + 0.3), 0.05, 0.0, 0.0, col % 2 == 1)
	_p(sec, "dead_tree", Vector2(5.0, 6.5), 0.05, 0.4)
	_p(sec, "dead_tree", Vector2(27.5, -18.0), 0.05, 0.4, 0.0, true)
	_p(sec, "bones", Vector2(13.0, -15.5), 0.045, 0.0)
	_p(sec, "bones", Vector2(24.0, 6.0), 0.045, 0.0)
	sec.seal_spots.assign([Vector3(4.0, 0, -17.0), Vector3(28.0, 0, -15.0)])
	sec.item_spots.append(Vector3(9.0, 0, 7.5))
	sec.wanderer_spots.append(Vector3(29.0, 0, 6.5))
	sec.enemies.append(_roamer(Vector2(9.0, 1.5), 2.5, 80))
	sec.enemies.append(_roamer(Vector2(24.0, 1.0), 2.5, 60))
	_ground(sec, Vector2(5, -11), Vector2(7, 11), RUIN_ASH, true, 0)
	_ground(sec, Vector2(27, -11), Vector2(7, 11), RUIN_ASH, true, 0)
	_critter(sec, ZoneCritterData.Kind.CROW, Vector2(6.0, -9.0))
	_critter(sec, ZoneCritterData.Kind.CROW, Vector2(27.0, -13.0))
	_critter(sec, ZoneCritterData.Kind.RAT, Vector2(12.0, 6.8))
	_ruins_back(sec)
	return sec


## A collapsed hall: two rooms behind a long wall with doorways, braziers still burning inside.
func _ruins_hall() -> ZoneSectionData:
	var sec := _new("hall", 34.0, 1601)
	_path(sec, [Vector2(-1, 1.2), Vector2(17, 1.8), Vector2(35, 1.2)], 4.2, RUIN_ROAD, 1, ROAD_TINT)
	_ruin_wall(sec, Vector2(4, -6), Vector2(9, -6), 2.6, 0.9)
	_ruin_wall(sec, Vector2(13, -6), Vector2(21, -6), 2.4, 0.9)
	_ruin_wall(sec, Vector2(25, -6), Vector2(30, -6), 2.2, 0.9)
	_ruin_wall(sec, Vector2(4, -6), Vector2(4, -20), 2.6, 0.9)
	_ruin_wall(sec, Vector2(30, -6), Vector2(30, -20), 2.6, 0.9)
	_ruin_wall(sec, Vector2(17, -10.5), Vector2(17, -20), 2.6, 0.9)
	_ground(sec, Vector2(17, -13), Vector2(25, 13.5), RUIN_PAVING, false, 0, 0.2)
	_brazier(sec, Vector2(7.0, -8.5))
	_brazier(sec, Vector2(27.0, -8.5))
	_p(sec, "rubble", Vector2(11.0, -17.0), 0.05, 0.7)
	_p(sec, "column_fallen", Vector2(23.5, -16.5), 0.05, 1.2)
	_p(sec, "statue_headless", Vector2(17.0, -8.5), 0.05, 1.0)
	_p(sec, "banner_torn", Vector2(14.0, -6.9), 0.05, 0.0, 0.05)
	_p(sec, "banner_torn", Vector2(20.0, -6.9), 0.05, 0.0, 0.05, true)
	sec.seal_spots.assign([Vector3(8.0, 0, -15.5), Vector3(27.0, 0, -16.5)])
	sec.chests.append(Vector3(12.5, 0, -18.5))
	sec.item_spots.append(Vector3(31.5, 0, 7.0))
	sec.shrine_spots.append(Vector3(17.0, 0, 7.0))
	sec.enemies.append(_roamer(Vector2(9.5, -12.5), 2.0, 80))
	sec.enemies.append(_roamer(Vector2(24.0, -12.0), 2.0, 70))
	sec.enemies.append(_roamer(Vector2(17.0, 3.0), 2.5, 50))
	for at: Vector2 in [Vector2(3.0, 7.0), Vector2(25.0, 7.5)]:
		_p(sec, "rubble", at, 0.05, 0.7)
	_ground(sec, Vector2(9, 7), Vector2(12, 4), RUIN_ASH, true, 0)
	_critter(sec, ZoneCritterData.Kind.RAT, Vector2(21.0, -15.0))
	_critter(sec, ZoneCritterData.Kind.CROW, Vector2(31.5, -4.0))
	_ruins_back(sec)
	return sec


func _end_ruins() -> ZoneSectionData:
	var sec := _new("end", 26.0, 1701)
	_path(sec, [Vector2(-1, 0.0), Vector2(8, 0.0)], 4.2, RUIN_ROAD, 1, ROAD_TINT)
	_ground(sec, Vector2(17, -1.5), Vector2(17, 15), RUIN_PAVING, false, 0, 0.3)
	_gate(sec)
	_guard(sec, Vector2(17.0, -1.0))
	for at: Vector2 in [Vector2(11.0, -9.0), Vector2(23.0, -9.0)]:
		_p(sec, "statue_headless", at, 0.05, 1.0, 0.0, at.x > 17.0)
	_brazier(sec, Vector2(11.0, 4.5))
	_brazier(sec, Vector2(23.0, 4.5))
	_p(sec, "arch_broken", Vector2(17.0, -15.0), 0.05, 1.0)
	_p(sec, "banner_torn", Vector2(13.5, -9.5), 0.05, 0.0, 0.05)
	_p(sec, "banner_torn", Vector2(20.5, -9.5), 0.05, 0.0, 0.05, true)
	sec.lights.append(_light(Vector3(17.0, 2.2, -1.0), FIRE_LIGHT, 2.6, 8.0, 10))
	_critter(sec, ZoneCritterData.Kind.CROW, Vector2(22.0, -14.0))
	_ruins_back(sec)
	return sec


# ================================================================================================
# Sunken Bog: swamp and jungle, water everywhere
# ================================================================================================

const BOG_MUD := ENV + "mud.png"
const BOG_MOSS := ENV + "moss.png"
const BOG_PLANKS := ENV + "planks.png"
const WATER_TINT := Color(0.75, 0.95, 0.85)
const WATER_DEEP := Color(0.03, 0.08, 0.07)


func _bog_air() -> Array[ZoneAmbientData]:
	return [
		_air("fireflies", FX + "mote.png", Color(0.75, 1.0, 0.45), 3.0, 40, 7.0, 0.08, Vector3(14, 1.2, 9), 1.3,
				Vector3(0.05, 0.02, 0.0), 180.0, 1.2),
		_air("mist", FX + "mist.png", Color(0.78, 0.92, 0.82, 0.22), 0.0, 18, 12.0, 1.8, Vector3(16, 0.15, 4.0),
				0.35, Vector3(0.25, 0.0, 0.05), 20.0, 0.0, true),
		_air("spores", FX + "spore.png", Color(0.7, 1.0, 0.6), 1.2, 26, 8.0, 0.05, Vector3(14, 1.5, 9), 1.0,
				Vector3(0.0, 0.22, 0.0), 35.0, 0.6),
	]


## A pool of deep water with lily pads on it and reeds round its edge.
func _pool(sec: ZoneSectionData, centre: Vector2, size: Vector2, lilies: bool = true, reeds: int = 4) -> void:
	_ground(sec, centre, size, ENV + "water.png", true, 0, 0.5, true, WATER_TINT, WATER_DEEP)
	if lilies:
		_lily(sec, centre + Vector2(size.x * 0.12, -size.y * 0.1), size * 0.55)
	for i: int in reeds:
		var a := _rng.randf() * TAU
		var at := centre + Vector2(cos(a) * size.x * 0.5, sin(a) * size.y * 0.5)
		_p(sec, "reeds", at, 0.045, 0.0, 0.06, _rng.randf() < 0.5)


## Lily pads floating on water (the same pixel size as the floor, so the pads match the heroes).
func _lily(sec: ZoneSectionData, at: Vector2, size: Vector2) -> void:
	_ground(sec, at, size, ENV + "lily_pads.png", true, 1, 0.6)
	sec.grounds.back().texture_world_size = 1.6


## Deep water as a rectangle (channels, lagoons): solid, rippling.
func _lagoon(sec: ZoneSectionData, centre: Vector2, size: Vector2) -> void:
	_ground(sec, centre, size, ENV + "water.png", false, 0, 0.6, true, WATER_TINT, WATER_DEEP)


func _bog_lantern(sec: ZoneSectionData, at: Vector2) -> void:
	_p(sec, "swamp_lantern", at, 0.05, 0.3, 0.0, at.x > sec.width * 0.5, 1.0, LAMP_LIGHT)
	sec.lights.append(_light(Vector3(at.x + 0.3, 1.4, at.y + 0.3), LAMP_LIGHT, 2.2, 6.5, 12))


## The bog's back edge: a wall of swamp trees beyond the bounds, ferns at their feet.
func _bog_back(sec: ZoneSectionData) -> void:
	var x := -0.5 + _rng.randf() * 2.0
	while x < sec.width:
		var kind := _rng.randi_range(0, 2)
		var name: String = ["mangrove", "moss_tree", "rotten_tree"][kind]
		_p(sec, name, Vector2(x, -21.5 - _rng.randf() * 2.5), 0.05, 0.0, 0.02, _rng.randf() < 0.5)
		x += 3.0 + _rng.randf() * 2.5
	x = 1.0
	while x < sec.width:
		_p(sec, "fern", Vector2(x, -19.6 - _rng.randf() * 0.4), 0.045, 0.0, 0.06, _rng.randf() < 0.5)
		x += 2.2 + _rng.randf() * 2.0


## Low growth across the front edge (blurred by the camera), framing the view.
func _front_edge(sec: ZoneSectionData, names: Array) -> void:
	var x := _rng.randf() * 3.0
	while x < sec.width:
		var name: String = names[_rng.randi_range(0, names.size() - 1)]
		_p(sec, name, Vector2(x, 10.6 + _rng.randf() * 1.4), 0.045 if name != "bush" else 0.05, 0.0, 0.05,
				_rng.randf() < 0.5)
		x += 2.5 + _rng.randf() * 3.0


func _start_bog() -> ZoneSectionData:
	var sec := _new("start", 18.0, 2101)
	sec.player_start = Vector3(2.5, 0.0, 1.0)
	_path(sec, [Vector2(-1, 0.3), Vector2(9, -0.4), Vector2(19, 0.2)], 3.6, BOG_MUD, 1)
	_pool(sec, Vector2(12.5, 7.0), Vector2(9, 4.5))
	_pool(sec, Vector2(7.0, -12.0), Vector2(8, 5))
	_bog_lantern(sec, Vector2(8.0, -3.2))
	_p(sec, "moss_tree", Vector2(3.0, -16.0), 0.05, 0.6, 0.02)
	_p(sec, "mangrove", Vector2(14.5, -14.5), 0.05, 0.8, 0.02, true)
	_p(sec, "giant_mushroom", Vector2(16.0, -6.5), 0.05, 0.8, 0.0, false, 1.0, SHROOM_GLOW)
	_ground(sec, Vector2(3, 6), Vector2(5, 3.5), BOG_MOSS, true, 0)
	sec.item_spots.append(Vector3(13.0, 0, -9.5))
	_critter(sec, ZoneCritterData.Kind.FROG, Vector2(10.0, 4.4))
	_critter(sec, ZoneCritterData.Kind.FROG, Vector2(5.0, -9.2))
	_scatter(sec, [["fern", 0.045, 0.0, 0.06], ["reeds", 0.045, 0.0, 0.06], ["grass", 0.045, 0.0, 0.05]], 14)
	_bog_back(sec)
	_front_edge(sec, ["reeds", "fern"])
	_end_trees(sec, -2.0, ["mangrove", "moss_tree"])
	return sec


## The boardwalk: wide water front and back; planks carry the way across, and a side walk runs
## out to a muddy island at the back where the seal waits.
func _bog_boardwalk() -> ZoneSectionData:
	var sec := _new("boardwalk", 32.0, 2201)
	_lagoon(sec, Vector2(9.0, -10.5), Vector2(9.0, 12.5))
	_lagoon(sec, Vector2(23.0, -10.5), Vector2(9.0, 12.5))
	_lagoon(sec, Vector2(16.0, 6.8), Vector2(18.0, 5.0))
	_lily(sec, Vector2(9.5, -9.0), Vector2(5, 6))
	_lily(sec, Vector2(23.0, 6.6), Vector2(6, 3))
	_path(sec, [Vector2(-1, 0.0), Vector2(33, 0.0)], 4.2, BOG_MUD, 1)
	_path(sec, [Vector2(4, -0.3), Vector2(28, 0.3)], 3.4, BOG_PLANKS, 2)
	_path(sec, [Vector2(16, -2.0), Vector2(16, -8.5)], 2.6, BOG_PLANKS, 2)
	_ground(sec, Vector2(16.0, -13.0), Vector2(7.5, 8.0), BOG_MUD, true, 1)
	_ground(sec, Vector2(16.0, -13.0), Vector2(5.0, 5.0), BOG_MOSS, true, 2)
	_p(sec, "mangrove", Vector2(7.5, -12.0), 0.05, 0.0, 0.02)
	_p(sec, "mangrove", Vector2(25.0, -9.0), 0.05, 0.0, 0.02, true)
	_p(sec, "moss_tree", Vector2(11.0, -16.0), 0.05, 0.0, 0.02)
	for at: Vector2 in [Vector2(6.0, -2.4), Vector2(14.0, 2.4), Vector2(22.0, -2.4)]:
		_bog_lantern(sec, at)
	for i: int in 10:
		var at := Vector2(5.0 + i * 2.4 + _rng.randf(), -4.6 if i % 2 == 0 else 4.5)
		_p(sec, "reeds", at, 0.045, 0.0, 0.06, i % 3 == 0)
	sec.seal_spots.assign([Vector3(16.0, 0, -14.0), Vector3(29.5, 0, -16.0)])
	sec.item_spots.append(Vector3(2.5, 0, -14.0))
	sec.shrine_spots.append(Vector3(29.0, 0, 6.5))
	sec.enemies.append(_roamer(Vector2(10.0, 0.0), 2.0, 85))
	sec.enemies.append(_roamer(Vector2(22.0, 0.0), 2.0, 70))
	sec.enemies.append(_roamer(Vector2(16.0, -12.5), 1.5, 55))
	_critter(sec, ZoneCritterData.Kind.FROG, Vector2(13.0, -4.6))
	_critter(sec, ZoneCritterData.Kind.FROG, Vector2(19.5, 4.6))
	_critter(sec, ZoneCritterData.Kind.CROW, Vector2(17.5, -15.0))
	_bog_back(sec)
	_front_edge(sec, ["reeds"])
	return sec


## The stilt village: huts on stilts over the mud, planks between them, lanterns, puddles.
func _bog_village() -> ZoneSectionData:
	var sec := _new("village", 34.0, 2301)
	_ground(sec, Vector2(17, -6), Vector2(32, 20), BOG_MUD, false, 0, 0.8)
	_path(sec, [Vector2(-1, 0.4), Vector2(35, 0.4)], 3.4, BOG_PLANKS, 2)
	_p(sec, "stilt_hut", Vector2(8.0, -12.5), 0.05, 2.0)
	_p(sec, "stilt_hut", Vector2(20.0, -15.0), 0.05, 2.0, 0.0, true)
	_p(sec, "stilt_hut", Vector2(29.5, -9.0), 0.05, 1.8)
	_path(sec, [Vector2(8.0, -1.5), Vector2(8.0, -9.0)], 2.0, BOG_PLANKS, 2)
	_path(sec, [Vector2(29.5, -1.5), Vector2(29.5, -6.0)], 2.0, BOG_PLANKS, 2)
	_ground(sec, Vector2(14.0, -8.0), Vector2(3.5, 2.2), ENV + "water.png", true, 1, 0.3, false, WATER_TINT, WATER_DEEP)
	_ground(sec, Vector2(23.0, 6.0), Vector2(5.0, 2.6), ENV + "water.png", true, 1, 0.3, false, WATER_TINT, WATER_DEEP)
	_pool(sec, Vector2(3.0, 6.5), Vector2(5.0, 3.6), true, 3)
	for at: Vector2 in [Vector2(5.0, -2.4), Vector2(16.5, 2.4), Vector2(25.0, -2.4), Vector2(12.0, -14.5)]:
		_bog_lantern(sec, at)
	_p(sec, "log", Vector2(14.0, 6.5), 0.05, 0.8)
	_p(sec, "giant_mushroom", Vector2(32.0, -16.0), 0.05, 0.8, 0.0, true, 1.0, SHROOM_GLOW)
	sec.wanderer_spots.append(Vector3(14.0, 0, -4.5))
	sec.shrine_spots.append(Vector3(25.0, 0, 6.5))
	sec.chests.append(Vector3(4.0, 0, -17.0))
	sec.seal_spots.assign([Vector3(20.0, 0, -19.0), Vector3(31.5, 0, -14.0)])
	sec.item_spots.append(Vector3(17.0, 0, 7.5))
	sec.enemies.append(_roamer(Vector2(12.0, 1.0), 2.5, 85))
	sec.enemies.append(_roamer(Vector2(25.0, -5.0), 2.0, 70))
	sec.enemies.append(_roamer(Vector2(20.0, 6.0), 1.5, 45))
	_critter(sec, ZoneCritterData.Kind.CROW, Vector2(9.5, -9.5))
	_critter(sec, ZoneCritterData.Kind.FROG, Vector2(22.0, 4.2))
	_critter(sec, ZoneCritterData.Kind.FROG, Vector2(14.5, -6.3))
	_scatter(sec, [["fern", 0.045, 0.0, 0.06], ["reeds", 0.045, 0.0, 0.06]], 12)
	_bog_back(sec)
	_front_edge(sec, ["reeds", "fern"])
	return sec


## The mangrove tangle: channels of water between stilt-rooted trees; the way winds back to a
## hidden clearing.
func _bog_mangroves() -> ZoneSectionData:
	var sec := _new("mangroves", 32.0, 2401)
	_path(sec, [Vector2(-1, 0.6), Vector2(11, -0.8), Vector2(21, 0.8), Vector2(33, 0.0)], 3.4, BOG_MUD, 1)
	_pool(sec, Vector2(7.0, -9.0), Vector2(8.0, 6.0))
	_pool(sec, Vector2(24.0, -11.0), Vector2(9.0, 7.0))
	_pool(sec, Vector2(14.0, 6.6), Vector2(10.0, 4.4))
	_pool(sec, Vector2(28.0, 6.4), Vector2(6.0, 3.6), false, 2)
	_ground(sec, Vector2(16.0, -16.0), Vector2(8.0, 6.0), BOG_MOSS, true, 1)
	for at: Vector2 in [Vector2(5.5, -14.5), Vector2(11.5, -5.5), Vector2(19.5, -6.0), Vector2(12.0, -16.5),
			Vector2(20.5, -17.5), Vector2(29.5, -15.5), Vector2(3.0, -5.0)]:
		_p(sec, "mangrove", at, 0.05, 0.9, 0.02, at.x > 16.0)
	_p(sec, "moss_tree", Vector2(28.0, -4.5), 0.05, 0.6, 0.02, true)
	_p(sec, "giant_mushroom", Vector2(16.0, -11.5), 0.05, 0.8, 0.0, false, 1.0, SHROOM_GLOW)
	sec.lights.append(_light(Vector3(16.0, 1.5, -11.0), SHROOM_GLOW, 1.8, 6.0, 0))
	_bog_lantern(sec, Vector2(9.0, 2.4))
	sec.seal_spots.assign([Vector3(16.0, 0, -16.5), Vector3(3.0, 0, -17.5)])
	sec.item_spots.append(Vector3(30.0, 0, 2.5))
	sec.shrine_spots.append(Vector3(4.0, 0, 6.5))
	sec.enemies.append(_roamer(Vector2(16.0, -15.0), 2.0, 85))
	sec.enemies.append(_roamer(Vector2(9.0, 0.0), 2.0, 70))
	sec.enemies.append(_roamer(Vector2(24.0, 1.0), 2.0, 55))
	_critter(sec, ZoneCritterData.Kind.FROG, Vector2(4.0, -6.3))
	_critter(sec, ZoneCritterData.Kind.FROG, Vector2(20.0, -8.0))
	_critter(sec, ZoneCritterData.Kind.CROW, Vector2(22.5, -6.5))
	_scatter(sec, [["fern", 0.045, 0.0, 0.06]], 10)
	_bog_back(sec)
	_front_edge(sec, ["reeds", "fern"])
	return sec


## The lily pond: two ponds hold a spit of land between them where a champion guards its chest.
func _bog_pond() -> ZoneSectionData:
	var sec := _new("pond", 32.0, 2501)
	_path(sec, [Vector2(-1, 0.4), Vector2(16, 1.0), Vector2(33, 0.4)], 3.6, BOG_MUD, 1)
	_pool(sec, Vector2(8.0, -11.0), Vector2(9.5, 14.0), true, 6)
	_pool(sec, Vector2(24.0, -11.0), Vector2(9.5, 14.0), true, 6)
	_ground(sec, Vector2(16.0, -13.0), Vector2(6.0, 14.0), BOG_MOSS, false, 1, 0.5)
	_path(sec, [Vector2(16.0, -1.5), Vector2(16.0, -6.5)], 2.6, BOG_PLANKS, 2)
	var champion := _roamer(Vector2(16.0, -12.0), 0.0, 100)
	champion.encounter = load("res://data/encounters/elite_toad_court.tres") as EncounterData
	champion.champion = true
	champion.prize_spot = Vector3(16.0, 0, -17.5)
	sec.enemies.append(champion)
	_bog_lantern(sec, Vector2(14.5, -6.0))
	_bog_lantern(sec, Vector2(17.5, -6.0))
	_p(sec, "moss_tree", Vector2(2.5, -6.0), 0.05, 0.6, 0.02)
	_p(sec, "mangrove", Vector2(29.5, -5.5), 0.05, 0.8, 0.02, true)
	sec.seal_spots.assign([Vector3(2.5, 0, -17.0), Vector3(29.5, 0, -17.0)])
	sec.item_spots.append(Vector3(16.0, 0, 7.5))
	sec.wanderer_spots.append(Vector3(28.5, 0, 6.0))
	sec.enemies.append(_roamer(Vector2(8.0, 1.5), 2.0, 80))
	sec.enemies.append(_roamer(Vector2(24.0, 1.5), 2.0, 60))
	_ground(sec, Vector2(8, 7), Vector2(9, 3.5), BOG_MOSS, true, 0)
	_critter(sec, ZoneCritterData.Kind.FROG, Vector2(12.5, -6.0))
	_critter(sec, ZoneCritterData.Kind.FROG, Vector2(19.8, -15.0))
	_critter(sec, ZoneCritterData.Kind.FROG, Vector2(4.0, -4.2))
	_scatter(sec, [["fern", 0.045, 0.0, 0.06]], 8)
	_bog_back(sec)
	_front_edge(sec, ["reeds", "fern"])
	return sec


## The mushroom grove: giant glowing mushrooms in rings on moss, puddles, spores in the air.
func _bog_grove() -> ZoneSectionData:
	var sec := _new("grove", 30.0, 2601)
	_path(sec, [Vector2(-1, 0.0), Vector2(15, -0.8), Vector2(31, 0.0)], 3.4, BOG_MUD, 1)
	_ground(sec, Vector2(15.0, -12.0), Vector2(22.0, 13.0), BOG_MOSS, true, 0, 0.8)
	for i: int in 7:
		var a := float(i) / 7.0 * TAU + 0.45
		if absf(a - PI * 0.5) < 0.5:
			continue
		var at := Vector2(15.0 + cos(a) * 5.5, -13.0 + sin(a) * 4.0)
		_p(sec, "giant_mushroom", at, 0.05, 0.8, 0.0, cos(a) > 0.0, 1.0, SHROOM_GLOW)
	sec.lights.append(_light(Vector3(15.0, 1.8, -13.0), SHROOM_GLOW, 2.2, 7.5, 0))
	for at: Vector2 in [Vector2(4.0, -7.0), Vector2(26.0, -7.5), Vector2(25.0, 6.5)]:
		_p(sec, "giant_mushroom", at, 0.05, 0.8, 0.0, at.x > 15.0, 1.0, SHROOM_GLOW)
		sec.lights.append(_light(Vector3(at.x, 1.5, at.y + 0.5), SHROOM_GLOW, 1.4, 5.0, 0))
	_ground(sec, Vector2(8.0, 6.0), Vector2(4.0, 2.4), ENV + "water.png", true, 1, 0.3, false, WATER_TINT, WATER_DEEP)
	_p(sec, "log", Vector2(20.0, -18.5), 0.05, 0.8)
	sec.seal_spots.assign([Vector3(15.0, 0, -14.0), Vector3(27.0, 0, -16.5)])
	sec.item_spots.append(Vector3(4.0, 0, -12.0))
	sec.item_spots.append(Vector3(21.0, 0, 7.0))
	sec.shrine_spots.append(Vector3(11.0, 0, 6.5))
	sec.enemies.append(_roamer(Vector2(15.0, -9.0), 3.0, 85))
	sec.enemies.append(_roamer(Vector2(7.0, 1.0), 2.0, 70))
	sec.enemies.append(_roamer(Vector2(24.0, 0.5), 2.0, 50))
	_critter(sec, ZoneCritterData.Kind.FROG, Vector2(6.0, 4.4))
	_critter(sec, ZoneCritterData.Kind.CROW, Vector2(21.0, -17.8))
	_scatter(sec, [["glow_shroom", 0.05, 0.0, 0.0], ["fern", 0.045, 0.0, 0.06]], 14)
	_bog_back(sec)
	_front_edge(sec, ["fern"])
	return sec


func _end_bog() -> ZoneSectionData:
	var sec := _new("end", 26.0, 2701)
	_path(sec, [Vector2(-1, 0.0), Vector2(27, 0.0)], 3.6, BOG_MUD, 1)
	_gate(sec)
	_guard(sec, Vector2(17.0, -1.0))
	_ground(sec, Vector2(17.0, -2.0), Vector2(14.0, 9.0), BOG_MOSS, true, 1, 0.6)
	_pool(sec, Vector2(17.0, -13.5), Vector2(15.0, 7.0), true, 6)
	_pool(sec, Vector2(17.0, 8.2), Vector2(13.0, 3.0), true, 3)
	_bog_lantern(sec, Vector2(11.0, -5.5))
	_bog_lantern(sec, Vector2(23.0, -5.5))
	_p(sec, "moss_tree", Vector2(8.5, -15.0), 0.05, 0.6, 0.02)
	_p(sec, "mangrove", Vector2(25.0, -15.5), 0.05, 0.8, 0.02, true)
	sec.lights.append(_light(Vector3(17.0, 2.0, -1.0), BOG_LIGHT, 2.6, 8.0, 10))
	_critter(sec, ZoneCritterData.Kind.FROG, Vector2(12.0, -9.5))
	_bog_back(sec)
	_front_edge(sec, ["reeds"])
	_end_trees(sec, sec.width + 2.0, ["mangrove", "moss_tree"])
	return sec


# ================================================================================================
# Rotten Hollow: a rotting forest
# ================================================================================================

const TRAIL := ENV + "dirt_trail.png"
## The trail a shade lighter than the dark forest floor, so it reads as the way.
const TRAIL_TINT := Color(1.25, 1.18, 1.05)
const LEAVES := ENV + "leaf_litter.png"
const HOLLOW_MOSS := ENV + "moss.png"


func _hollow_air() -> Array[ZoneAmbientData]:
	return [
		_air("leaves", FX + "leaf.png", Color(1, 1, 1), 0.0, 40, 9.0, 0.14, Vector3(14, 3, 4.5), 4.5,
				Vector3(0.3, -0.45, 0.05), 35.0, 0.7, false, true),
		_air("fireflies", FX + "mote.png", Color(1.0, 0.85, 0.45), 2.6, 22, 7.0, 0.07, Vector3(14, 1.2, 9), 1.3,
				Vector3(0.05, 0.03, 0.0), 180.0, 1.0),
	]


func _lamp(sec: ZoneSectionData, at: Vector2) -> void:
	_p(sec, "lamp", at, 0.05, 0.3)
	sec.lights.append(_light(Vector3(at.x, 1.9, at.y + 0.3), LAMP_LIGHT, 2.4, 7.0, 12))


## Thick forest: big trees in a band, the solid ones away from `keep` spots.
func _forest(sec: ZoneSectionData, area: Rect2, count: int) -> void:
	_scatter(sec, [["rotten_tree", 0.05, 0.6, 0.02], ["dead_tree", 0.05, 0.4, 0.0], ["pine_dead", 0.05, 0.4, 0.0],
			["bush", 0.05, 0.5, 0.03]], count, area)


## Low growth (bushes, stumps) in `area`: for the front, where trees would hide the party.
func _undergrowth(sec: ZoneSectionData, area: Rect2, count: int) -> void:
	_scatter(sec, [["bush", 0.05, 0.5, 0.03], ["stump", 0.05, 0.5, 0.0]], count, area)


## A wall of trees just past one end of a zone (x), front to back.
func _end_trees(sec: ZoneSectionData, x: float, names: Array) -> void:
	var z := Z_BACK
	while z < Z_FRONT + 2.0:
		var name: String = names[_rng.randi_range(0, names.size() - 1)]
		_p(sec, name, Vector2(x + _rng.randf_range(-1.0, 1.0), z), 0.05, 0.0, 0.02, _rng.randf() < 0.5)
		z += 2.4 + _rng.randf() * 1.6


## The hollow's back edge: a wall of trees beyond the bounds, bushes at their feet.
func _hollow_back(sec: ZoneSectionData) -> void:
	var x := -0.5 + _rng.randf() * 2.0
	while x < sec.width:
		var name: String = ["rotten_tree", "pine_dead", "dead_tree", "rotten_tree"][_rng.randi_range(0, 3)]
		_p(sec, name, Vector2(x, -21.0 - _rng.randf() * 3.0), 0.05, 0.0, 0.02, _rng.randf() < 0.5)
		x += 2.6 + _rng.randf() * 2.2
	x = 0.5
	while x < sec.width:
		_p(sec, "bush" if _rng.randf() < 0.5 else "fern", Vector2(x, -19.7 - _rng.randf() * 0.5),
				0.05, 0.0, 0.04, _rng.randf() < 0.5)
		x += 2.0 + _rng.randf() * 2.0


func _start_hollow() -> ZoneSectionData:
	var sec := _new("start", 18.0, 3101)
	sec.player_start = Vector3(2.5, 0.0, 1.0)
	_path(sec, [Vector2(-1, 0.3), Vector2(9, -0.5), Vector2(19, 0.2)], 3.4, TRAIL, 1, TRAIL_TINT)
	_p(sec, "signpost", Vector2(7.0, -2.6), 0.05, 0.3)
	_p(sec, "fence", Vector2(10.0, 4.4), 0.05, 0.0)
	_p(sec, "fence", Vector2(14.0, 4.6), 0.05, 0.0, 0.0, true)
	_lamp(sec, Vector2(12.0, -3.2))
	_p(sec, "stump", Vector2(4.0, 5.5), 0.05, 0.5)
	sec.item_spots.append(Vector3(14.0, 0, -12.0))
	_forest(sec, Rect2(0, -19, 18, 13), 8)
	_ground(sec, Vector2(9, -12), Vector2(10, 7), HOLLOW_MOSS, true, 0)
	_critter(sec, ZoneCritterData.Kind.CROW, Vector2(7.6, -3.4))
	_critter(sec, ZoneCritterData.Kind.RAT, Vector2(15.0, 6.5))
	_scatter(sec, [["fern", 0.045, 0.0, 0.06], ["grass", 0.045, 0.0, 0.05]], 14)
	_hollow_back(sec)
	_front_edge(sec, ["fern", "bush"])
	_end_trees(sec, -2.0, ["rotten_tree", "pine_dead", "dead_tree"])
	return sec


## The forest trail: a winding trail under dense trees; a side trail climbs to a clearing behind
## a band of thorns, where the seal waits in a ring of stumps.
func _hollow_trail() -> ZoneSectionData:
	var sec := _new("trail", 32.0, 3201)
	_path(sec, [Vector2(-1, 0.0), Vector2(8, -1.4), Vector2(16, 1.0), Vector2(24, -0.6), Vector2(33, 0.0)], 3.4,
			TRAIL, 1, TRAIL_TINT)
	_path(sec, [Vector2(14, -0.5), Vector2(17, -6.0), Vector2(20, -12.5)], 2.6, TRAIL, 1, TRAIL_TINT)
	_ground(sec, Vector2(21.0, -14.0), Vector2(9.0, 7.0), HOLLOW_MOSS, true, 0)
	for at: Vector2 in [Vector2(18.0, -15.5), Vector2(24.0, -15.5), Vector2(21.0, -17.5)]:
		_p(sec, "stump", at, 0.05, 0.5)
	for x: float in [4.0, 7.5, 11.0, 24.5, 28.0]:
		_p(sec, "thorns", Vector2(x, -8.5 - fmod(x, 2.0)), 0.05, 0.8)
	_lamp(sec, Vector2(10.0, -3.6))
	_lamp(sec, Vector2(26.0, 2.6))
	sec.seal_spots.assign([Vector3(21.0, 0, -14.0), Vector3(4.0, 0, -15.5)])
	sec.item_spots.append(Vector3(10.0, 0, 7.0))
	sec.shrine_spots.append(Vector3(28.0, 0, -5.0))
	sec.enemies.append(_roamer(Vector2(8.0, 0.0), 2.5, 85))
	sec.enemies.append(_roamer(Vector2(21.0, -12.0), 1.6, 65))
	sec.enemies.append(_roamer(Vector2(27.0, 4.0), 2.0, 50))
	_forest(sec, Rect2(0, -19, 32, 9), 12)
	_undergrowth(sec, Rect2(0, 4.2, 32, 5.4), 6)
	_critter(sec, ZoneCritterData.Kind.CROW, Vector2(18.5, -16.5))
	_critter(sec, ZoneCritterData.Kind.RAT, Vector2(3.0, 4.5))
	_scatter(sec, [["fern", 0.045, 0.0, 0.06], ["grass", 0.045, 0.0, 0.05], ["glow_shroom", 0.05, 0.0, 0.0]], 18)
	_hollow_back(sec)
	_front_edge(sec, ["fern", "bush"])
	return sec


## The woodcutter's camp: a clearing with a campfire, stumps and logs, a broken cart and a well.
func _hollow_camp() -> ZoneSectionData:
	var sec := _new("camp", 32.0, 3301)
	_path(sec, [Vector2(-1, 0.6), Vector2(33, 0.0)], 3.4, TRAIL, 1, TRAIL_TINT)
	_ground(sec, Vector2(16.0, -7.5), Vector2(20.0, 13.0), TRAIL, true, 0, 0.9)
	_p(sec, "campfire", Vector2(16.0, -7.5), 0.05, 0.6, 0.0, false, 1.4, FIRE_LIGHT)
	sec.lights.append(_light(Vector3(16.0, 1.0, -7.0), FIRE_LIGHT, 3.0, 8.0, 25))
	for at: Vector2 in [Vector2(13.0, -9.0), Vector2(19.0, -9.5), Vector2(16.0, -4.6)]:
		_p(sec, "stump", at, 0.05, 0.5)
	_p(sec, "log", Vector2(12.0, -12.5), 0.05, 0.8)
	_p(sec, "log", Vector2(21.0, -5.0), 0.05, 0.8, 0.0, true)
	_p(sec, "cart", Vector2(8.0, -13.5), 0.05, 1.2)
	_p(sec, "well", Vector2(25.0, -12.5), 0.05, 1.0)
	_p(sec, "fence", Vector2(27.5, -6.5), 0.05, 0.0)
	_p(sec, "fence", Vector2(5.0, -6.0), 0.05, 0.0, 0.0, true)
	_lamp(sec, Vector2(11.0, 2.8))
	sec.wanderer_spots.append(Vector3(14.0, 0, -6.0))
	sec.shrine_spots.append(Vector3(27.0, 0, 6.0))
	sec.chests.append(Vector3(4.5, 0, -17.0))
	sec.seal_spots.assign([Vector3(16.0, 0, -17.0), Vector3(29.5, 0, -16.0)])
	sec.item_spots.append(Vector3(22.0, 0, 7.5))
	sec.enemies.append(_roamer(Vector2(8.0, 1.0), 2.5, 85))
	sec.enemies.append(_roamer(Vector2(24.0, 1.0), 2.5, 70))
	sec.enemies.append(_roamer(Vector2(21.0, -16.0), 1.6, 55))
	_undergrowth(sec, Rect2(0, 4.2, 32, 5.4), 6)
	_forest(sec, Rect2(0, -19, 5, 12), 2)
	_forest(sec, Rect2(27, -19, 5, 9), 2)
	_critter(sec, ZoneCritterData.Kind.CROW, Vector2(9.5, -11.0))
	_critter(sec, ZoneCritterData.Kind.RAT, Vector2(24.0, -9.5))
	_scatter(sec, [["fern", 0.045, 0.0, 0.06], ["grass", 0.045, 0.0, 0.05]], 14)
	_hollow_back(sec)
	_front_edge(sec, ["fern", "bush"])
	return sec


## The chapel yard: the broken walls of a forest chapel, grave crosses all round; a champion
## keeps its chest inside.
func _hollow_chapel() -> ZoneSectionData:
	var sec := _new("chapel", 32.0, 3401)
	_path(sec, [Vector2(-1, 0.4), Vector2(16, 1.4), Vector2(33, 0.4)], 3.4, TRAIL, 1, TRAIL_TINT)
	sec.blocks.append(_block(Vector3(9.0, 0, -14.5), Vector3(0.9, 2.6, 11.0), "ruin_wall"))
	sec.blocks.append(_block(Vector3(23.0, 0, -14.5), Vector3(0.9, 2.2, 11.0), "ruin_wall"))
	sec.blocks.append(_block(Vector3(11.3, 0, -9.0), Vector3(4.6, 2.4, 0.9), "ruin_wall"))
	sec.blocks.append(_block(Vector3(20.7, 0, -9.0), Vector3(4.6, 1.8, 0.9), "ruin_wall"))
	_ground(sec, Vector2(16.0, -14.5), Vector2(13.0, 10.5), ENV + "paving.png", false, 0, 0.3)
	var champion := _roamer(Vector2(16.0, -13.5), 0.0, 100)
	champion.encounter = load("res://data/encounters/elite_twin_husks.tres") as EncounterData
	champion.champion = true
	champion.prize_spot = Vector3(16.0, 0, -18.0)
	sec.enemies.append(champion)
	_lamp(sec, Vector2(13.0, -7.6))
	_lamp(sec, Vector2(19.0, -7.6))
	for i: int in 8:
		var at := Vector2(2.0 + (i % 4) * 1.8, -6.0 - floorf(i / 4.0) * 4.5)
		_p(sec, "grave_cross", at, 0.05, 0.0, 0.0, i % 2 == 0)
		_p(sec, "grave_cross", Vector2(32.0 - at.x, at.y - 0.5), 0.05, 0.0, 0.0, i % 2 == 1)
	_p(sec, "grave_cross", Vector2(13.0, -16.0), 0.05, 0.0)
	_p(sec, "rotten_tree", Vector2(6.0, 6.5), 0.05, 0.6)
	_p(sec, "rotten_tree", Vector2(27.0, -18.0), 0.05, 0.6, 0.02, true)
	sec.seal_spots.assign([Vector3(4.0, 0, -16.0), Vector3(28.0, 0, -15.5)])
	sec.item_spots.append(Vector3(27.0, 0, 7.0))
	sec.wanderer_spots.append(Vector3(5.0, 0, -2.5))
	sec.enemies.append(_roamer(Vector2(9.0, 1.5), 2.5, 80))
	sec.enemies.append(_roamer(Vector2(23.0, 1.0), 2.5, 60))
	_critter(sec, ZoneCritterData.Kind.CROW, Vector2(4.0, -6.8))
	_critter(sec, ZoneCritterData.Kind.CROW, Vector2(28.5, -11.0))
	_scatter(sec, [["fern", 0.045, 0.0, 0.06], ["grass", 0.045, 0.0, 0.05]], 14)
	_hollow_back(sec)
	_front_edge(sec, ["fern", "bush"])
	return sec


## The thorn thicket: briars choke the back half; one way winds through to the seal.
func _hollow_thicket() -> ZoneSectionData:
	var sec := _new("thicket", 32.0, 3501)
	_path(sec, [Vector2(-1, 0.0), Vector2(16, -1.0), Vector2(33, 0.0)], 3.4, TRAIL, 1, TRAIL_TINT)
	_path(sec, [Vector2(10, -1.5), Vector2(12, -8.0), Vector2(16, -12.5), Vector2(16, -16.0)], 2.4, TRAIL, 1, TRAIL_TINT)
	var thorns: Array[Vector2] = [Vector2(4, -6), Vector2(6, -9), Vector2(8, -13), Vector2(5, -16), Vector2(9, -18),
			Vector2(14.5, -6.5), Vector2(19, -8.5), Vector2(20, -12.5), Vector2(19.5, -16.5), Vector2(12.5, -18.5),
			Vector2(23, -6), Vector2(26, -9.5), Vector2(24, -14.5), Vector2(28.5, -5.5)]
	for at: Vector2 in thorns:
		_p(sec, "thorns", at, 0.05, 0.9, 0.0, int(at.x) % 2 == 0)
	_ground(sec, Vector2(16, -16), Vector2(6, 5), HOLLOW_MOSS, true, 0)
	_lamp(sec, Vector2(6.0, 2.8))
	sec.seal_spots.assign([Vector3(16.0, 0, -16.0), Vector3(29.0, 0, -12.0)])
	sec.item_spots.append(Vector3(4.0, 0, -12.5))
	sec.shrine_spots.append(Vector3(16.0, 0, 6.5))
	sec.chests.append(Vector3(29.5, 0, -18.5))
	sec.enemies.append(_roamer(Vector2(15.0, -11.0), 2.0, 85))
	sec.enemies.append(_roamer(Vector2(8.0, 0.5), 2.0, 70))
	sec.enemies.append(_roamer(Vector2(25.0, 1.0), 2.0, 55))
	_undergrowth(sec, Rect2(0, 4.2, 32, 5.4), 6)
	_critter(sec, ZoneCritterData.Kind.RAT, Vector2(22.0, -11.0))
	_critter(sec, ZoneCritterData.Kind.CROW, Vector2(3.0, -12.0))
	_scatter(sec, [["fern", 0.045, 0.0, 0.06], ["grass", 0.045, 0.0, 0.05]], 12)
	_hollow_back(sec)
	_front_edge(sec, ["fern", "bush"])
	return sec


## The fallen giant: a great dead tree lies across the forest; the way goes round its broken top.
func _hollow_fallen() -> ZoneSectionData:
	var sec := _new("fallen", 32.0, 3601)
	_path(sec, [Vector2(-1, 0.6), Vector2(33, 0.0)], 3.4, TRAIL, 1, TRAIL_TINT)
	var x := 3.0
	while x < 26.0:
		if x < 14.5 or x > 17.5:
			_p(sec, "log", Vector2(x, -7.0 - (x - 3.0) * 0.12), 0.05, 1.0, 0.0, x > 16.0)
		x += 2.2
	_p(sec, "rotten_tree", Vector2(28.0, -8.5), 0.05, 0.6, 0.02, true)
	for at: Vector2 in [Vector2(6.0, -8.6), Vector2(11.0, -9.2), Vector2(20.0, -10.0), Vector2(24.0, -10.4)]:
		_p(sec, "glow_shroom", at, 0.05, 0.0, 0.0, false, 1.5, SHROOM_GLOW)
	sec.lights.append(_light(Vector3(10.0, 1.2, -8.5), SHROOM_GLOW, 1.4, 5.5, 0))
	sec.lights.append(_light(Vector3(22.0, 1.2, -9.5), SHROOM_GLOW, 1.4, 5.5, 0))
	_ground(sec, Vector2(16.0, -14.5), Vector2(22.0, 9.0), HOLLOW_MOSS, true, 0, 0.7)
	_lamp(sec, Vector2(16.0, 2.8))
	sec.seal_spots.assign([Vector3(16.0, 0, -15.0), Vector3(5.5, 0, -16.0)])
	sec.item_spots.append(Vector3(10.0, 0, -15.0))
	sec.item_spots.append(Vector3(27.0, 0, 7.0))
	sec.wanderer_spots.append(Vector3(26.0, 0, -15.0))
	sec.enemies.append(_roamer(Vector2(16.0, -13.0), 2.5, 85))
	sec.enemies.append(_roamer(Vector2(8.0, 1.0), 2.0, 70))
	sec.enemies.append(_roamer(Vector2(25.0, 0.5), 2.0, 50))
	_undergrowth(sec, Rect2(0, 4.2, 32, 5.4), 6)
	_critter(sec, ZoneCritterData.Kind.CROW, Vector2(9.0, -7.9))
	_critter(sec, ZoneCritterData.Kind.RAT, Vector2(20.0, -6.0))
	_scatter(sec, [["fern", 0.045, 0.0, 0.06], ["grass", 0.045, 0.0, 0.05]], 14)
	_hollow_back(sec)
	_front_edge(sec, ["fern", "bush"])
	return sec


func _end_hollow() -> ZoneSectionData:
	var sec := _new("end", 26.0, 3701)
	_path(sec, [Vector2(-1, 0.0), Vector2(27, 0.0)], 3.4, TRAIL, 1, TRAIL_TINT)
	_ground(sec, Vector2(17.0, -2.0), Vector2(16.0, 12.0), HOLLOW_MOSS, true, 0, 0.6)
	_gate(sec)
	_guard(sec, Vector2(17.0, -1.0))
	for at: Vector2 in [Vector2(10.0, -10.0), Vector2(24.0, -11.0), Vector2(11.0, 6.5), Vector2(23.5, 6.0)]:
		_p(sec, "rotten_tree", at, 0.05, 0.6, 0.02, at.x > 17.0)
	_lamp(sec, Vector2(12.0, -4.0))
	_lamp(sec, Vector2(22.0, -4.0))
	for at: Vector2 in [Vector2(14.0, -12.0), Vector2(20.0, -12.5)]:
		_p(sec, "grave_cross", at, 0.05, 0.0)
	sec.lights.append(_light(Vector3(17.0, 2.0, -1.0), LAMP_LIGHT, 2.6, 8.0, 10))
	_critter(sec, ZoneCritterData.Kind.CROW, Vector2(14.5, -12.8))
	_scatter(sec, [["fern", 0.045, 0.0, 0.06]], 8)
	_hollow_back(sec)
	_front_edge(sec, ["fern", "bush"])
	_end_trees(sec, sec.width + 2.0, ["rotten_tree", "pine_dead", "dead_tree"])
	return sec


# --- shared pieces ----------------------------------------------------------------------------

## The gate of rotten roots across the whole depth at x 4 (DESIGN.md 8.5).
func _gate(sec: ZoneSectionData) -> void:
	var gate := _block(Vector3(4.0, 0.0, (Z_BACK + Z_FRONT) * 0.5), Vector3(1.2, 2.6, Z_FRONT - Z_BACK), "rot_gate")
	gate.texture_world_size = 2.4
	sec.gate = gate


func _guard(sec: ZoneSectionData, at: Vector2) -> void:
	var guard := ZoneEnemyData.new()
	guard.position = Vector3(at.x, 0.0, at.y)
	guard.wander_radius = 1.0
	guard.guard = true
	sec.enemies.append(guard)


## A road or trail through points (x, z): one ground piece per stretch, overlapping at the joints.
func _path(sec: ZoneSectionData, points: Array, width: float, texture: String, layer: int,
		tint: Color = Color(1, 1, 1)) -> void:
	for i: int in points.size() - 1:
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var g := ZoneGroundData.new()
		g.position = Vector3((a.x + b.x) * 0.5, 0.0, (a.y + b.y) * 0.5)
		g.size = Vector2(a.distance_to(b) + width * 0.6, width)
		g.rotation_y_degrees = -rad_to_deg((b - a).angle())
		g.texture_path = texture
		g.edge_noise = 0.45
		g.layer = layer
		g.tint = tint
		sec.grounds.append(g)


const FRINGE := {"planks.png": 0, "paving.png": 2, "road_cobble.png": 2}
const FLAT_PROPS := ["fern", "grass", "reeds"]


func _ground(sec: ZoneSectionData, at: Vector2, size: Vector2, texture: String, round: bool = false, layer: int = 0,
		edge: float = 0.5, solid: bool = false, tint: Color = Color(1, 1, 1), deep: Color = Color(0.04, 0.1, 0.09)) -> void:
	var g := ZoneGroundData.new()
	g.kind = ZoneGroundData.Kind.WATER if texture.ends_with("water.png") else ZoneGroundData.Kind.PATCH
	g.position = Vector3(at.x, 0.0, at.y)
	g.size = size
	g.round = round
	g.texture_path = texture
	g.edge_noise = edge
	g.layer = layer
	g.tint = tint
	g.deep_color = deep
	g.solid = solid
	# Hard-edged ground (boards, slabs) keeps its edge; earth, moss and leaves fade into the floor.
	g.fringe_pixels = FRINGE.get(texture.get_file(), g.fringe_pixels)
	sec.grounds.append(g)


## A prop at (x, z). `glow` above 0 makes it shine in `glow_color`.
func _p(sec: ZoneSectionData, sprite: String, at: Vector2, pixel: float, solid: float, sway: float = 0.0,
		flip: bool = false, glow: float = 0.0, glow_color: Color = Color(1, 1, 1)) -> void:
	var prop := ZonePropData.new()
	prop.sprite_path = ENV + sprite + ".png"
	prop.position = Vector3(snappedf(at.x, 0.01), 0.0, snappedf(at.y, 0.01))
	prop.pixel_size = pixel
	# Ground cover gets no contact shadow (a blob under every fern would dirty the floor).
	prop.contact_shadow = not FLAT_PROPS.has(sprite)
	prop.solid_radius = solid
	prop.flip = flip
	prop.sway = sway
	prop.glow = glow
	prop.glow_color = glow_color
	sec.props.append(prop)


func _critter(sec: ZoneSectionData, kind: ZoneCritterData.Kind, at: Vector2) -> void:
	var c := ZoneCritterData.new()
	c.kind = kind
	c.position = Vector3(at.x, 0.0, at.y)
	c.sprite_path = ENV + "critter_%s.png" % ["crow", "frog", "rat"][kind]
	c.pixel_size = 0.045
	c.flip = _rng.randf() < 0.5
	sec.critters.append(c)


func _air(id: String, texture: String, color: Color, glow: float, amount: int, lifetime: float, size: float,
		area: Vector3, height: float, velocity: Vector3, spread: float, wobble: float, soft: bool = false,
		spin: bool = false) -> ZoneAmbientData:
	var a := ZoneAmbientData.new()
	a.id = id
	a.texture_path = texture
	a.color = color
	a.glow = glow
	a.amount = amount
	a.lifetime = lifetime
	a.size = size
	a.area = area
	a.height = height
	a.velocity = velocity
	a.spread = spread
	a.wobble = wobble
	a.soft = soft
	a.spin = spin
	return a


## `count` props picked from `kinds` ([sprite, pixel, solid, sway] each) at random spots in `area`
## (default: the whole section) that keep clear of the spots that matter, the blocks, deep water,
## other solid props and (for solid props) the walkways.
func _scatter(sec: ZoneSectionData, kinds: Array, count: int, area: Rect2 = Rect2()) -> void:
	if area.size == Vector2.ZERO:
		area = Rect2(0.5, Z_BACK + 0.5, sec.width - 1.0, Z_FRONT - Z_BACK - 1.0)
	var keep := _keep_spots(sec)
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 40:
		tries += 1
		var kind: Array = kinds[_rng.randi_range(0, kinds.size() - 1)]
		var at := Vector2(_rng.randf_range(area.position.x, area.end.x), _rng.randf_range(area.position.y, area.end.y))
		var solid := float(kind[2])
		if not _clear(sec, keep, at, solid):
			continue
		_p(sec, String(kind[0]), at, float(kind[1]), solid, float(kind[3]), _rng.randf() < 0.5)
		if solid > 0.0:
			keep.append(Vector3(at.x, 0.0, at.y))
		placed += 1


func _keep_spots(sec: ZoneSectionData) -> Array[Vector3]:
	var keep: Array[Vector3] = []
	keep.append_array(sec.item_spots)
	keep.append_array(sec.chests)
	keep.append_array(sec.seal_spots)
	keep.append_array(sec.shrine_spots)
	keep.append_array(sec.wanderer_spots)
	keep.append(sec.player_start)
	for e: ZoneEnemyData in sec.enemies:
		keep.append(e.position)
		if e.champion:
			keep.append(e.prize_spot)
	for p: ZonePropData in sec.props:
		if p.solid_radius > 0.0:
			keep.append(p.position)
	return keep


## True if a prop of solid `radius` (0: walk-through) can stand at `at`.
func _clear(sec: ZoneSectionData, keep: Array[Vector3], at: Vector2, radius: float) -> bool:
	var reach := KEEP_OUT + radius if radius > 0.0 else 0.9
	for k: Vector3 in keep:
		if Vector2(k.x, k.z).distance_to(at) < reach:
			return false
	for b: ZoneBlockData in sec.blocks:
		var o := {"centre": Vector2(b.position.x, b.position.z), "half": Vector2(b.size.x, b.size.z) * 0.5,
				"angle": deg_to_rad(b.rotation_y_degrees)}
		if ZonePath._overlaps(at, radius + 0.8, o):
			return false
	for g: ZoneGroundData in sec.grounds:
		if not g.solid and not (radius > 0.0 and g.layer >= 1 and g.texture_path != ENV + "lily_pads.png"):
			continue
		if g.solid:
			for o: Dictionary in ZoneMotion.ground_obstacles(g):
				if ZonePath._overlaps(at, radius + 0.5, o):
					return false
		elif _on_ground(g, at, radius + 0.6):
			# Solid props keep off roads, trails and boardwalks.
			return false
	if radius > 0.0 and absf(at.y) < 3.6:
		return false
	return true


## True if `at` is within `margin` of ground piece `g` (its rectangle or ellipse).
func _on_ground(g: ZoneGroundData, at: Vector2, margin: float) -> bool:
	var local := (at - Vector2(g.position.x, g.position.z)).rotated(deg_to_rad(g.rotation_y_degrees))
	var half := g.size * 0.5 + Vector2(margin, margin)
	if g.round:
		return (local.x / half.x) * (local.x / half.x) + (local.y / half.y) * (local.y / half.y) <= 1.0
	return absf(local.x) <= half.x and absf(local.y) <= half.y


# --- small builders ---------------------------------------------------------------------------

func _roamer(at: Vector2, wander: float, chance: int) -> ZoneEnemyData:
	var roamer := ZoneEnemyData.new()
	roamer.position = Vector3(at.x, 0.0, at.y)
	roamer.wander_radius = wander
	roamer.chance_percent = chance
	return roamer


func _block(pos: Vector3, size: Vector3, texture: String, turn: float = 0.0) -> ZoneBlockData:
	var block := ZoneBlockData.new()
	block.position = pos
	block.size = size
	block.texture_path = ENV + texture + ".png"
	block.rotation_y_degrees = turn
	return block


func _light(pos: Vector3, color: Color, energy: float, reach: float, flicker: int) -> ZoneLightData:
	var light := ZoneLightData.new()
	light.position = pos
	light.color = color
	light.energy = energy
	light.reach = reach
	light.flicker_percent = flicker
	return light


func _save(res: Resource, path: String) -> Resource:
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_error("bootstrap_zones: could not save %s (%d)" % [path, err])
		return res
	_written += 1
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
