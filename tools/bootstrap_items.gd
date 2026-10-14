extends SceneTree
## Creates the phase 11 backpack data (DESIGN.md 8.1): the items (Salve, Feast, Tonic, which used
## to be used the moment they were bought; Bomb, Smelling Salts, Key; treasure), the run's shop and
## found lists, the charms (step 3: stones, bones, herbs, rotten ones) and the Bigger Pack, and the
## glinting spots and chests in the run's zones. Only writes item files that do not exist yet, and only gives a zone
## spots or chests if it has none, so edits made in the editor are never overwritten. Every spot and
## chest is checked against the zone's walls and props (one the leader cannot reach is an error).
## Run headless:
##   godot --headless --path . -s tools/bootstrap_items.gd
## Add "-- --force" after the script to overwrite the item files (careful: loses edits).

const RUN_PATH := "res://data/runs/rotten_road.tres"
const ICONS := "res://assets/sprites/items/"
## Spots stand at least this far from walls and props (the leader's own radius and a little).
const SPOT_CLEARANCE: float = 0.6
const E := ItemData.Effect
const K := ItemData.Kind
const R := ItemData.Rarity
const F := ItemData.Family
const G := GearData.Effect

## Glinting spots per zone (x, z on the ground): off the straight way to the guard, so finding
## them means exploring a little.
const SPOTS := {
	"rotten_hollow": [Vector2(-14.0, 3.0), Vector2(14.5, -9.5), Vector2(-14.5, -19.5)],
	"sunken_bog": [Vector2(-12.0, 1.0), Vector2(12.5, -9.5), Vector2(-11.5, -19.0)],
	"ashen_ruins": [Vector2(-13.0, 2.5), Vector2(14.0, -6.5), Vector2(-12.5, -15.5)],
}

## One chest per zone, in a far corner.
const CHESTS := {
	"rotten_hollow": [Vector2(13.5, -17.0)],
	"sunken_bog": [Vector2(-12.5, -12.5)],
	"ashen_ruins": [Vector2(13.0, -19.0)],
}

var _force := false
var _errors := 0


func _init() -> void:
	_force = OS.get_cmdline_user_args().has("--force")
	DirAccess.make_dir_recursive_absolute("res://data/items")
	var one: Array[Vector2i] = [Vector2i(0, 0)]
	var wide: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	var tall: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1)]
	var salve := _item("salve", "Salve", "Heals one character by half of their max HP.", 25, E.HEAL_ONE, 50, one, 10,
			K.CONSUMABLE, R.COMMON, true, true)
	var feast := _item("feast", "Feast", "Heals everyone by 30% of their max HP.", 40, E.HEAL_ALL, 30, wide, 4,
			K.CONSUMABLE, R.COMMON, true, true)
	var tonic := _item("tonic", "Tonic", "One character gets +15% max HP for the rest of the run.", 45, E.MAX_HP_ONE, 15,
			tall, 2, K.CONSUMABLE, R.COMMON, true, false)
	var bomb := _item("bomb", "Bomb", "In a fight: hits every enemy hard.", 30, E.DAMAGE_ALL, 120, one, 6,
			K.CONSUMABLE, R.COMMON, false, true)
	var salts := _item("smelling_salts", "Smelling Salts", "In a fight: wakes a downed hero with 40% of their HP.", 60,
			E.REVIVE_ONE, 40, one, 4, K.CONSUMABLE, R.RARE, false, true)
	var key := _item("key", "Key", "Opens one locked chest. It takes room while you carry it.", 30, E.NONE, 0, wide, 8,
			K.KEY, R.COMMON, false, false)
	var ring := _item("silver_ring", "Silver Ring", "Treasure. Sell it at a shop.", 40, E.NONE, 0, one, 6,
			K.TREASURE, R.COMMON, false, false)
	var gem := _item("rot_gem", "Rot Gem", "Treasure. Sell it at a shop.", 120, E.NONE, 0, one, 4,
			K.TREASURE, R.RARE, false, false)
	var idol := _item("golden_idol", "Golden Idol", "Treasure. Sell it at a shop.", 300, E.NONE, 0, tall, 3,
			K.TREASURE, R.LEGENDARY, false, false)

	var run := load(RUN_PATH) as RunData
	# New typed arrays: a run saved before phase 11 holds a list typed for the old shop items.
	var square: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
	var pole: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)]
	var bend: Array[Vector2i] = [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)]
	var charms: Array[ItemData] = [
		_charm("ember_stone", "Ember Stone", "Power +5% for every hero.", 50, F.STONE, G.POWER, 5, one, R.COMMON),
		_charm("iron_stone", "Iron Stone", "Enemy hits deal 5% less to every hero.", 50, F.STONE, G.TOUGH, 5, one, R.COMMON),
		_booster("lodestone", "Lodestone", "Stone charms touching it work 50% better.", 90, F.STONE, 50, square),
		_charm("knucklebone", "Lucky Knucklebone", "Gold from fights +10%.", 45, F.BONE, G.GOLD, 10, one, R.COMMON),
		_charm("wolf_tooth", "Wolf Tooth", "Speed +5 for every hero.", 50, F.BONE, G.SPEED, 5, one, R.COMMON),
		_booster("bone_totem", "Bone Totem", "Bone charms touching it work 50% better.", 90, F.BONE, 50, pole),
		_charm("heartleaf", "Heartleaf", "Max HP +5% for every hero.", 50, F.HERB, G.MAX_HP, 5, one, R.COMMON),
		_charm("wake_root", "Wake Root", "Every hero starts each fight with +1 AP.", 80, F.HERB, G.START_AP, 1, bend, R.RARE),
		_booster("rain_pouch", "Rain Pouch", "Herb charms touching it work 50% better.", 80, F.HERB, 50, one),
	]
	var heart := _charm("rotting_heart", "Rotting Heart", "Power +25% for every hero. Rotten: every hero loses 3% HP each turn.",
			0, F.NONE, G.POWER, 25, one, R.RARE, 3)
	var moss := _charm("grave_moss", "Grave Moss", "Every hero starts each fight with +2 AP. Rotten: every hero loses 2% HP each turn.",
			0, F.HERB, G.START_AP, 2, wide, R.RARE, 2)
	var pack := _item("bigger_pack", "Bigger Pack", "The backpack gets one more row, at once.", 100, E.ADD_ROW, 0, one, 1,
			K.UPGRADE, R.RARE, false, false)
	var shop: Array[ItemData] = [salve, feast, tonic, bomb, salts, key, pack]
	var found: Array[ItemData] = [salve, feast, tonic, bomb, salts, key, ring, gem, idol, heart, moss, pack]
	found.append_array(charms)
	run.shop_items = shop
	run.found_items = found
	_check(ResourceSaver.save(run, RUN_PATH), RUN_PATH)
	for zone: ZoneData in run.zones:
		_add_spots(zone)
	print("bootstrap_items: done, %d errors" % _errors)
	quit(1 if _errors > 0 else 0)


func _item(id: String, title: String, desc: String, price: int, effect: ItemData.Effect, pct: int,
		shape: Array[Vector2i], weight: int, kind: ItemData.Kind, rarity: ItemData.Rarity, on_map: bool,
		in_fight: bool) -> ItemData:
	var path := "res://data/items/%s.tres" % id
	if FileAccess.file_exists(path) and not _force:
		return load(path) as ItemData
	var item := ItemData.new()
	item.id = id
	item.display_name = title
	item.description = desc
	item.kind = kind
	item.rarity = rarity
	item.use_on_map = on_map
	item.use_in_fight = in_fight
	item.price = price
	item.effect = effect
	item.amount_percent = pct
	item.shape = shape
	item.find_weight = weight
	item.icon_path = ICONS + id + ".png"
	_check(ResourceSaver.save(item, path), path)
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as ItemData


## A charm (DESIGN.md 8.1): gives every hero `amount` of `effect` while in the backpack. With
## `rot` > 0 it is rotten.
func _charm(id: String, title: String, desc: String, price: int, family: ItemData.Family, effect: GearData.Effect,
		amount: int, shape: Array[Vector2i], rarity: ItemData.Rarity, rot: int = 0) -> ItemData:
	var path := "res://data/items/%s.tres" % id
	if FileAccess.file_exists(path) and not _force:
		return load(path) as ItemData
	var item := ItemData.new()
	item.id = id
	item.display_name = title
	item.description = desc
	item.kind = K.CHARM
	item.rarity = rarity
	item.price = price
	item.shape = shape
	item.family = family
	item.charm_effect = effect
	item.charm_amount = amount
	item.rotten = rot > 0
	item.rot_percent = rot
	item.find_weight = 2 if rot > 0 else (4 if rarity == R.COMMON else 3)
	item.use_on_map = false
	item.icon_path = ICONS + id + ".png"
	_check(ResourceSaver.save(item, path), path)
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as ItemData


## A booster charm: no bonus of its own; charms of `family` touching it work `percent` better.
func _booster(id: String, title: String, desc: String, price: int, family: ItemData.Family, percent: int,
		shape: Array[Vector2i]) -> ItemData:
	var path := "res://data/items/%s.tres" % id
	if FileAccess.file_exists(path) and not _force:
		return load(path) as ItemData
	var item := _charm(id, title, desc, price, family, G.POWER, 0, shape, R.RARE)
	item.boost_family = family
	item.boost_percent = percent
	_check(ResourceSaver.save(item, path), path)
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as ItemData


func _add_spots(zone: ZoneData) -> void:
	if zone == null:
		return
	var changed := false
	if zone.item_spots.is_empty() and SPOTS.has(zone.id):
		for spot: Vector2 in SPOTS[zone.id]:
			if _free(zone, spot):
				zone.item_spots.append(Vector3(spot.x, 0.0, spot.y))
				changed = true
	if zone.chests.is_empty() and CHESTS.has(zone.id):
		for spot: Vector2 in CHESTS[zone.id]:
			if _free(zone, spot):
				zone.chests.append(Vector3(spot.x, 0.0, spot.y))
				changed = true
	if changed:
		_check(ResourceSaver.save(zone, zone.resource_path), zone.resource_path)


## True if the leader can stand at `spot` (an error is reported if not).
func _free(zone: ZoneData, spot: Vector2) -> bool:
	var free := ZoneMotion.move(spot, Vector2.ZERO, SPOT_CLEARANCE, ZoneMotion.obstacles(zone), zone.bounds_min,
			zone.bounds_max)
	if free.distance_to(spot) > 0.01:
		push_error("bootstrap_items: spot %s in %s is blocked (pushed to %s)" % [spot, zone.id, free])
		_errors += 1
		return false
	return true


func _check(err: int, path: String) -> void:
	if err != OK:
		push_error("bootstrap_items: could not save %s (%d)" % [path, err])
		_errors += 1
