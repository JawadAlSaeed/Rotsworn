extends SceneTree
## Creates the phase 11 backpack data (DESIGN.md 8.1): the items (Salve, Feast, Tonic, which used
## to be used the moment they were bought; Bomb, Smelling Salts, Key; treasure), the run's shop and
## found lists, the curses (Rotting Heart, Grave Moss: events' prices) and the Bigger Pack, and the
## glinting spots and chests in the run's zones. Phase 17 took the charms out (DESIGN.md 8.17): their
## files are written as faded treasure nobody finds any more, kept so older saves still load (the
## best charm ideas became Relics: tools/bootstrap_relics.gd). Only writes item files that do not exist yet, and only gives a zone
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
	var faded: Array[ItemData] = [
		_faded("ember_stone", "Ember Stone", 50, one), _faded("iron_stone", "Iron Stone", 50, one),
		_faded("lodestone", "Lodestone", 90, square), _faded("knucklebone", "Lucky Knucklebone", 45, one),
		_faded("wolf_tooth", "Wolf Tooth", 50, one), _faded("bone_totem", "Bone Totem", 90, pole),
		_faded("heartleaf", "Heartleaf", 50, one), _faded("wake_root", "Wake Root", 80, bend),
		_faded("rain_pouch", "Rain Pouch", 80, one),
	]
	var heart := _curse("rotting_heart", "Rotting Heart", 3, one)
	var moss := _curse("grave_moss", "Grave Moss", 2, wide)
	var pack := _item("bigger_pack", "Bigger Pack", "The backpack gets one more row, at once.", 100, E.ADD_ROW, 0, one, 1,
			K.UPGRADE, R.RARE, false, false)
	var shop: Array[ItemData] = [salve, feast, tonic, bomb, salts, key, pack]
	var found: Array[ItemData] = [salve, feast, tonic, bomb, salts, key, ring, gem, idol, heart, moss, pack]
	found.append_array(faded)
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


## A charm from before phase 17, now faded treasure (DESIGN.md 8.17): no effect, never found again
## (find weight 0), only worth gold; kept so older saves that carry one still load.
func _faded(id: String, title: String, price: int, shape: Array[Vector2i]) -> ItemData:
	var item := _item(id, "Faded " + title, "An old charm. Its power faded when the Relics woke. Worth gold at a shop.",
			price, E.NONE, 0, shape, 0, K.TREASURE, R.COMMON, false, false)
	return item


## A curse (DESIGN.md 8.1, 8.7): rotten, every hero loses `rot` percent HP each turn in fights while
## it is carried; events give it as a price and a shop's Cleanse throws it away. Never found.
func _curse(id: String, title: String, rot: int, shape: Array[Vector2i]) -> ItemData:
	var path := "res://data/items/%s.tres" % id
	if FileAccess.file_exists(path) and not _force:
		return load(path) as ItemData
	var item := _item(id, title, "A curse. Every hero loses %d%% HP each turn in fights while you carry it. " % rot
			+ "A shop's Cleanse throws it away.", 0, E.NONE, 0, shape, 0, K.CURSE, R.RARE, false, false)
	item.rotten = true
	item.rot_percent = rot
	_check(ResourceSaver.save(item, path), path)
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as ItemData


func _add_spots(zone: ZoneData) -> void:
	# Long zones (DESIGN.md 8.5) keep their spots in their sections (tools/bootstrap_zones.gd).
	if zone == null or ZoneAssembler.is_sectioned(zone):
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
