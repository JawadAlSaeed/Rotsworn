extends SceneTree
## Creates the phase 11 backpack data (DESIGN.md 8.1): the items (Salve, Feast, Tonic, which used
## to be used the moment they were bought; Bomb, Smelling Salts; treasure), the run's shop and
## found lists, the curses (Rotting Heart, Grave Moss: events' prices) and the Bigger Pack. Phase 17
## took the charms out (DESIGN.md 8.17; the best charm ideas became Relics: tools/bootstrap_relics.gd)
## and phase 21 deleted their faded files (card #282). Phase 26 removed the walkable zones with their
## glinting spots, chests and the Key that opened them (DESIGN.md 8.22, G3). Only adds items missing
## from the run's lists (later phases added their own). Only writes item files that do not exist
## yet, so edits made in the editor are never overwritten.
## Run headless:
##   godot --headless --path . -s tools/bootstrap_items.gd
## Add "-- --force" after the script to overwrite the item files (careful: loses edits).

const RUN_PATH := "res://data/runs/rotten_road.tres"
const ICONS := "res://assets/sprites/items/"
const E := ItemData.Effect
const K := ItemData.Kind
const R := ItemData.Rarity

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
	var ring := _item("silver_ring", "Silver Ring", "Treasure. Sell it at a shop.", 40, E.NONE, 0, one, 6,
			K.TREASURE, R.COMMON, false, false)
	var gem := _item("rot_gem", "Rot Gem", "Treasure. Sell it at a shop.", 120, E.NONE, 0, one, 4,
			K.TREASURE, R.RARE, false, false)
	var idol := _item("golden_idol", "Golden Idol", "Treasure. Sell it at a shop.", 300, E.NONE, 0, tall, 3,
			K.TREASURE, R.LEGENDARY, false, false)

	var run := load(RUN_PATH) as RunData
	# New typed arrays: a run saved before phase 11 holds a list typed for the old shop items.
	var heart := _curse("rotting_heart", "Rotting Heart", 3, one)
	var moss := _curse("grave_moss", "Grave Moss", 2, wide)
	var pack := _item("bigger_pack", "Bigger Pack", "The backpack gets one more row, at once.", 100, E.ADD_ROW, 0, one, 1,
			K.UPGRADE, R.RARE, false, false)
	var shop: Array[ItemData] = [salve, feast, tonic, bomb, salts, pack]
	var found: Array[ItemData] = [salve, feast, tonic, bomb, salts, ring, gem, idol, heart, moss, pack]
	for item: ItemData in shop:
		if not run.shop_items.has(item):
			run.shop_items.append(item)
	for item: ItemData in found:
		if not run.found_items.has(item):
			run.found_items.append(item)
	_check(ResourceSaver.save(run, RUN_PATH), RUN_PATH)
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


func _check(err: int, path: String) -> void:
	if err != OK:
		push_error("bootstrap_items: could not save %s (%d)" % [path, err])
		_errors += 1
