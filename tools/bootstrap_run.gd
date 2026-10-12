extends SceneTree
## Creates the phase 4 run data (DESIGN.md 8): shop items, the new encounters, two more zones
## (Sunken Bog, Ashen Ruins) with their looks, and the run itself. Only writes files that do not
## exist yet, so edits made in the editor are never overwritten. Run headless:
##   godot --headless --path . -s tools/bootstrap_run.gd
## Add "-- --force" after the script to overwrite them (careful: loses edits).
## Then run tools/gen_placeholders.gd to draw any new ground tiles.

const ENV := "res://assets/sprites/env/"
const SHROOM_GLOW := Color(0.35, 1.0, 0.85)
const LAMP_LIGHT := Color(1.0, 0.68, 0.38)
const BOG_LIGHT := Color(0.55, 1.0, 0.6)

var _force := false
var _written := 0
var _skipped := 0


func _init() -> void:
	_force = OS.get_cmdline_user_args().has("--force")
	for dir: String in ["res://data/shop", "res://data/runs", "res://data/zones", "res://data/looks"]:
		DirAccess.make_dir_recursive_absolute(dir)

	var salve := _shop_item("salve", "Salve", "Heals one character by half of their max HP.", 25,
			ShopItemData.Effect.HEAL_ONE, 50)
	var feast := _shop_item("feast", "Feast", "Heals everyone by 30% of their max HP.", 40,
			ShopItemData.Effect.HEAL_ALL, 30)
	var tonic := _shop_item("tonic", "Tonic", "One character gets +15% max HP for the rest of the run.", 45,
			ShopItemData.Effect.MAX_HP_ONE, 15)

	var party: Array = [load("res://data/characters/alder.tres"), load("res://data/characters/brin.tres"),
			load("res://data/characters/cass.tres")]
	var ultimate := load("res://data/abilities/team_ultimate.tres") as AbilityData
	var husk := load("res://data/enemies/rotten_husk.tres") as EnemyData
	var bloat := load("res://data/enemies/bloat.tres") as EnemyData
	var gnat := load("res://data/enemies/gnat_swarm.tres") as EnemyData
	var shade := load("res://data/enemies/shade.tres") as EnemyData
	var husk_and_gnat := _encounter("husk_and_gnat", "Rotten Husk and Gnat Swarm", party, [husk, gnat], ultimate)
	var shade_and_gnat := _encounter("shade_and_gnat", "Shade and Gnat Swarm", party, [shade, gnat], ultimate)
	var final_stand := _encounter("final_stand", "The Last Gate", party, [shade, bloat], ultimate)

	var hollow_look := load("res://data/looks/rotten_hollow.tres") as StageLook
	var bog_look := _bog_look(hollow_look)
	var ash_look := _ash_look(hollow_look)
	var brin := party[1] as CharacterData
	var bog := _sunken_bog(bog_look, brin, husk_and_gnat)
	var ash := _ashen_ruins(ash_look, brin, shade_and_gnat)

	var run := RunData.new()
	run.id = "rotten_road"
	run.display_name = "The Rotten Road"
	run.party.assign(party)
	run.team_ultimate = ultimate
	run.zones.assign([load("res://data/zones/rotten_hollow.tres"), bog, ash])
	run.final_encounter = final_stand
	run.final_look = ash_look
	run.shop_items.assign([salve, feast, tonic])
	_save(run, "res://data/runs/rotten_road.tres")
	print("bootstrap_run: wrote %d, kept %d existing" % [_written, _skipped])
	quit()


func _save(res: Resource, path: String) -> Resource:
	if FileAccess.file_exists(path) and not _force:
		_skipped += 1
		return load(path)
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_error("bootstrap_run: could not save %s (%d)" % [path, err])
		return res
	_written += 1
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)


func _shop_item(id: String, title: String, desc: String, price: int, effect: ShopItemData.Effect,
		pct: int) -> ShopItemData:
	var item := ShopItemData.new()
	item.id = id
	item.display_name = title
	item.description = desc
	item.price = price
	item.effect = effect
	item.amount_percent = pct
	return _save(item, "res://data/shop/%s.tres" % id) as ShopItemData


func _encounter(id: String, title: String, party: Array, enemies: Array, ultimate: AbilityData) -> EncounterData:
	var encounter := EncounterData.new()
	encounter.id = id
	encounter.display_name = title
	encounter.party.assign(party)
	encounter.enemies.assign(enemies)
	encounter.team_ultimate = ultimate
	return _save(encounter, "res://data/encounters/%s.tres" % id) as EncounterData


# --- looks ------------------------------------------------------------------------------------

func _bog_look(base: StageLook) -> StageLook:
	var look := base.duplicate(true) as StageLook
	look.floor_tile_path = ENV + "bog_tile.png"
	look.background_color = Color(0.04, 0.07, 0.06)
	look.ambient_color = Color(0.3, 0.42, 0.36)
	look.light_color = Color(0.85, 1.0, 0.8)
	look.light_energy = 0.9
	look.fog_color = Color(0.14, 0.24, 0.18)
	look.fog_density = 0.03
	look.fog_height_density = 0.2
	look.fog_height = 0.6
	look.saturation = 1.05
	look.vignette_color = Color(0.0, 0.02, 0.01)
	for light: ZoneLightData in look.arena_lights:
		light.color = BOG_LIGHT
	return _save(look, "res://data/looks/sunken_bog.tres") as StageLook


func _ash_look(base: StageLook) -> StageLook:
	var look := base.duplicate(true) as StageLook
	look.floor_tile_path = ENV + "ash_tile.png"
	look.background_color = Color(0.06, 0.06, 0.09)
	look.ambient_color = Color(0.38, 0.42, 0.58)
	look.light_color = Color(0.75, 0.85, 1.0)
	look.light_energy = 1.0
	look.fog_color = Color(0.2, 0.21, 0.28)
	look.fog_density = 0.02
	look.saturation = 0.85
	look.contrast = 1.15
	return _save(look, "res://data/looks/ashen_ruins.tres") as StageLook


# --- zones ------------------------------------------------------------------------------------

## A wet hollow: winding ground between rotten trees and glowing fungus. Guard: husk and gnats.
func _sunken_bog(look: StageLook, leader: CharacterData, guard: EncounterData) -> ZoneData:
	var zone := _zone("sunken_bog", "Sunken Bog", look, leader, Vector2(-14.0, -21.0), Vector2(14.0, 10.0))
	zone.blocks.assign([
		_block(Vector3(0, 0, -23.5), Vector3(34, 5, 3), "cliff"),
		_block(Vector3(-16.5, 0, -5.5), Vector3(3, 4, 36), "cliff"),
		_block(Vector3(16.5, 0, -5.5), Vector3(3, 4, 36), "cliff"),
		_block(Vector3(-6, 0, -1), Vector3(6, 1.4, 0.8), "ruin_wall"),
		_block(Vector3(7, 0, -11), Vector3(5, 1.6, 0.8), "ruin_wall", 90.0),
		_block(Vector3(-10, 0, -15), Vector3(4, 2.5, 4), "cliff"),
		_block(Vector3(10, 0, 3), Vector3(3, 2, 3), "cliff"),
	])
	var props: Array[ZonePropData] = [
		_prop("rotten_tree", Vector3(-11, 0, 5), 0.06, 0.6),
		_prop("rotten_tree", Vector3(12, 0, -3), 0.06, 0.6, true),
		_prop("rotten_tree", Vector3(-12, 0, -9), 0.06, 0.6),
		_prop("rotten_tree", Vector3(11, 0, -17), 0.06, 0.6, true),
		_prop("rotten_tree", Vector3(-6, 0, -20), 0.06, 0.6),
		_prop("dead_tree", Vector3(4, 0, 1), 0.06, 0.4),
		_prop("dead_tree", Vector3(-3, 0, -9), 0.06, 0.4, true),
		_prop("dead_tree", Vector3(5, 0, -15), 0.06, 0.4),
		_prop("rock", Vector3(-3, 0, 4.5), 0.05, 0.7),
		_prop("rock", Vector3(9.5, 0, -6.5), 0.05, 0.7, true),
		_prop("rock", Vector3(-8, 0, -11.5), 0.05, 0.7),
		_prop("pillar", Vector3(-2.5, 0, -20.5), 0.055, 0.45),
		_prop("pillar", Vector3(3.5, 0, -20.5), 0.055, 0.45, true),
	]
	for spot: Vector3 in [Vector3(-7, 0, 3), Vector3(3, 0, -4.5), Vector3(-1, 0, -13), Vector3(8, 0, -19),
			Vector3(-12.5, 0, -2), Vector3(12, 0, 7)]:
		props.append(_glow_prop("glow_shroom", spot, 0.05, 1.5, SHROOM_GLOW))
	props.append_array(_grass(hash("sunken_bog"), 22, zone.bounds_min, zone.bounds_max))
	zone.props.assign(props)
	zone.lights.assign([
		_light(Vector3(-2, 1.5, 6), BOG_LIGHT, 2.0, 7.0, 0),
		_light(Vector3(4, 1.5, -6), BOG_LIGHT, 2.0, 7.0, 0),
		_light(Vector3(-6, 1.5, -14), BOG_LIGHT, 2.0, 7.0, 0),
		_light(Vector3(-2.5, 1.9, -20), LAMP_LIGHT, 2.4, 7.0, 12),
		_light(Vector3(3.5, 1.9, -20), LAMP_LIGHT, 2.4, 7.0, 12),
	])
	zone.enemies.assign([
		_roamer("res://data/encounters/gnat_pair.tres", Vector3(-7, 0, -5), 2.5),
		_roamer("res://data/encounters/husk_fight.tres", Vector3(6, 0, -3), 2.5),
		_roamer("res://data/encounters/bloat_fight.tres", Vector3(-4, 0, -16), 2.0),
		_guard(guard, Vector3(0.5, 0, -18)),
	])
	return _save(zone, "res://data/zones/sunken_bog.tres") as ZoneData


## Broken halls under a cold moon: colonnades and walls make corridors. Guard: shade and gnats.
func _ashen_ruins(look: StageLook, leader: CharacterData, guard: EncounterData) -> ZoneData:
	var zone := _zone("ashen_ruins", "Ashen Ruins", look, leader, Vector2(-15.0, -21.0), Vector2(15.0, 10.0))
	zone.blocks.assign([
		_block(Vector3(0, 0, -23.5), Vector3(36, 4, 2), "ruin_wall"),
		_block(Vector3(-17, 0, -5.5), Vector3(2, 3.5, 36), "ruin_wall"),
		_block(Vector3(17, 0, -5.5), Vector3(2, 3.5, 36), "ruin_wall"),
		_block(Vector3(-8, 0, 0), Vector3(8, 1.8, 0.8), "ruin_wall"),
		_block(Vector3(8, 0, -8), Vector3(8, 1.8, 0.8), "ruin_wall"),
		_block(Vector3(-6, 0, -14), Vector3(6, 1.6, 0.8), "ruin_wall", 90.0),
		_block(Vector3(10, 0, -17), Vector3(4, 2, 3), "cliff"),
	])
	var props: Array[ZonePropData] = []
	for spot: Vector3 in [Vector3(-3, 0, 4), Vector3(3, 0, 4), Vector3(-3, 0, -4), Vector3(3, 0, -4.5),
			Vector3(-2, 0, -11), Vector3(2, 0, -11), Vector3(-2.5, 0, -20.5), Vector3(2.5, 0, -20.5)]:
		props.append(_prop("pillar", spot, 0.055, 0.45, spot.x > 0.0))
	props.append_array([
		_prop("dead_tree", Vector3(-12, 0, 6), 0.06, 0.4),
		_prop("dead_tree", Vector3(12, 0, 7), 0.06, 0.4, true),
		_prop("dead_tree", Vector3(-13, 0, -18), 0.06, 0.4),
		_prop("dead_tree", Vector3(13, 0, -3), 0.06, 0.4, true),
		_prop("rock", Vector3(6.5, 0, 4), 0.05, 0.7),
		_prop("rock", Vector3(-6, 0, -9), 0.05, 0.7, true),
		_prop("rock", Vector3(12.5, 0, -12), 0.05, 0.7),
		_glow_prop("glow_shroom", Vector3(-10, 0, -12), 0.05, 1.5, SHROOM_GLOW),
		_glow_prop("glow_shroom", Vector3(10.5, 0, -10), 0.05, 1.5, SHROOM_GLOW),
	])
	props.append_array(_grass(hash("ashen_ruins"), 14, zone.bounds_min, zone.bounds_max))
	zone.props.assign(props)
	zone.lights.assign([
		_light(Vector3(-3, 1.9, 4.5), LAMP_LIGHT, 2.4, 7.0, 12),
		_light(Vector3(3, 1.9, -5), LAMP_LIGHT, 2.4, 7.0, 12),
		_light(Vector3(-2, 1.9, -11.5), LAMP_LIGHT, 2.4, 7.0, 12),
		_light(Vector3(0, 1.9, -20), LAMP_LIGHT, 2.8, 8.0, 12),
		_light(Vector3(10, 1.2, -10), SHROOM_GLOW, 1.2, 5.0, 0),
	])
	zone.enemies.assign([
		_roamer("res://data/encounters/shade_fight.tres", Vector3(7, 0, -2), 2.5),
		_roamer("res://data/encounters/husk_fight.tres", Vector3(-9, 0, -6), 2.5),
		_roamer("res://data/encounters/gnat_pair.tres", Vector3(9, 0, -13), 2.0),
		_guard(guard, Vector3(0, 0, -18)),
	])
	return _save(zone, "res://data/zones/ashen_ruins.tres") as ZoneData


func _zone(id: String, title: String, look: StageLook, leader: CharacterData, lo: Vector2, hi: Vector2) -> ZoneData:
	var zone := ZoneData.new()
	zone.id = id
	zone.display_name = title
	zone.look = look
	zone.leader = leader
	zone.bounds_min = lo
	zone.bounds_max = hi
	zone.player_start = Vector3(0, 0, 8)
	return zone


func _block(pos: Vector3, size: Vector3, texture: String, turn: float = 0.0) -> ZoneBlockData:
	var block := ZoneBlockData.new()
	block.position = pos
	block.size = size
	block.texture_path = ENV + texture + ".png"
	block.rotation_y_degrees = turn
	return block


func _prop(sprite: String, pos: Vector3, pixel: float, solid: float, flip: bool = false) -> ZonePropData:
	var prop := ZonePropData.new()
	prop.sprite_path = ENV + sprite + ".png"
	prop.position = pos
	prop.pixel_size = pixel
	prop.solid_radius = solid
	prop.flip = flip
	return prop


func _glow_prop(sprite: String, pos: Vector3, pixel: float, glow: float, color: Color) -> ZonePropData:
	var prop := _prop(sprite, pos, pixel, 0.0)
	prop.glow = glow
	prop.glow_color = color
	return prop


## Grass tufts at random spots (seeded, so the same every time), walk-through.
func _grass(seed_value: int, count: int, lo: Vector2, hi: Vector2) -> Array[ZonePropData]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var list: Array[ZonePropData] = []
	for i: int in count:
		var spot := Vector3(snappedf(rng.randf_range(lo.x, hi.x), 0.01), 0, snappedf(rng.randf_range(lo.y, hi.y), 0.01))
		list.append(_prop("grass", spot, 0.045, 0.0, rng.randf() < 0.5))
	return list


func _light(pos: Vector3, color: Color, energy: float, reach: float, flicker: int) -> ZoneLightData:
	var light := ZoneLightData.new()
	light.position = pos
	light.color = color
	light.energy = energy
	light.reach = reach
	light.flicker_percent = flicker
	return light


func _roamer(encounter_path: String, pos: Vector3, wander: float) -> ZoneEnemyData:
	var roamer := ZoneEnemyData.new()
	roamer.encounter = load(encounter_path) as EncounterData
	roamer.position = pos
	roamer.wander_radius = wander
	return roamer


## The guard stands at the exit and barely wanders.
func _guard(encounter: EncounterData, pos: Vector3) -> ZoneEnemyData:
	var guard := _roamer(encounter.resource_path, pos, 1.0)
	guard.guard = true
	return guard
