extends SceneTree
## Phase 17 (DESIGN.md 8.17): turns the run's 25 gear pieces into Relics, adds six Relics made from
## the best charm ideas (the backpack's charms are gone: their effects are Relics' job now), and
## turns the old charm files into faded treasure (kept so older saves load) and the rotten ones into
## curses. Gives each Relic its stat line (attribute points at level 1, one more per level) and its
## Echo cost, renames the Echo Charm (its name would clash with Echoes), and lists the Relics every
## monster can drop. Every Relic is dropped by at least one monster; the rare ones by the deep
## monsters, guards and bosses. Edits existing files in place (only these fields) and writes the new
## Relics. First numbers: tune them in the files after play.
## Run: Godot --headless --path . -s tools/bootstrap_relics.gd

const GEAR_DIR := "res://data/gear/"
const ENEMY_DIR := "res://data/enemies/"
const ITEM_DIR := "res://data/items/"
const RUN_PATH := "res://data/runs/rotten_road.tres"
const E := GearData.Effect

## The Relics made from charm ideas, each with an effect no Relic had yet (or a rot-touched price):
## id -> [name, description, rarity, effect, amount, price, rot-touched, drawback, drawback amount].
const NEW_RELICS := {
	"heartleaf": ["Heartleaf", "Healing the wearer receives is 25% stronger.", 0, E.HEAL_TAKEN, 25, 60, false, E.MAX_HP, 0],
	"wake_root": ["Wake Root", "Each parry gives the wearer 1 more AP.", 1, E.PARRY_AP, 1, 90, false, E.MAX_HP, 0],
	"ember_stone": ["Ember Stone", "Critical hit chance +10%.", 0, E.CRIT, 10, 60, false, E.MAX_HP, 0],
	"rain_pouch": ["Rain Pouch", "The campfire's Rest heals the wearer 50% more.", 0, E.REST_HEAL, 50, 50, false, E.MAX_HP, 0],
	"black_ichor": ["Black Ichor", "Power +25%, but the wearer loses 3% of max HP at the start of each of their turns.",
			1, E.POWER, 25, 110, true, E.ROT, 3],
	"gravebloom": ["Gravebloom", "Start every fight with +2 AP, but lose 2% of max HP at the start of each of your turns.",
			1, E.START_AP, 2, 120, true, E.ROT, 2],
}

## The old charms (phase 11), faded to treasure since phase 17: item id -> name.
const FADED := {
	"ember_stone": "Ember Stone", "iron_stone": "Iron Stone", "lodestone": "Lodestone",
	"knucklebone": "Lucky Knucklebone", "wolf_tooth": "Wolf Tooth", "bone_totem": "Bone Totem",
	"heartleaf": "Heartleaf", "wake_root": "Wake Root", "rain_pouch": "Rain Pouch",
}
## The rotten charms, now curses: item id -> HP lost each turn, in percent.
const CURSES := {"rotting_heart": 3, "grave_moss": 2}

## Relic id -> [attribute (Attributes.Kind), stat points at level 1, Echo cost].
const RELICS := {
	"iron_charm": [Attributes.Kind.VITALITY, 2, 1],
	"lucky_coin": [Attributes.Kind.LUCK, 2, 1],
	"menders_charm": [Attributes.Kind.VITALITY, 2, 1],
	"quick_boots": [Attributes.Kind.AGILITY, 2, 1],
	"thick_hide": [Attributes.Kind.DEFENSE, 2, 1],
	"whetstone": [Attributes.Kind.MIGHT, 2, 1],
	"echo_charm": [Attributes.Kind.AGILITY, 3, 2],
	"keen_eye": [Attributes.Kind.LUCK, 3, 2],
	"leaping_heart": [Attributes.Kind.VITALITY, 3, 2],
	"riposte_ring": [Attributes.Kind.DEFENSE, 3, 2],
	"rot_hunter": [Attributes.Kind.MIGHT, 3, 2],
	"war_drum": [Attributes.Kind.MIGHT, 3, 2],
	"ash_veil": [Attributes.Kind.AGILITY, 3, 2],
	"bloodletters_fang": [Attributes.Kind.LUCK, 3, 2],
	"chain_of_silence": [Attributes.Kind.DEFENSE, 3, 2],
	"gravebound_ring": [Attributes.Kind.MIGHT, 3, 2],
	"hollow_mantle": [Attributes.Kind.DEFENSE, 3, 2],
	"hunger_charm": [Attributes.Kind.VITALITY, 3, 2],
	"last_ember": [Attributes.Kind.MIGHT, 3, 2],
	"pale_tithe": [Attributes.Kind.LUCK, 3, 2],
	"plague_bell": [Attributes.Kind.LUCK, 3, 2],
	"thorned_gauntlet": [Attributes.Kind.DEFENSE, 3, 2],
	"second_wind": [Attributes.Kind.VITALITY, 4, 3],
	"oathbreakers_band": [Attributes.Kind.AGILITY, 4, 3],
	"rotten_crown": [Attributes.Kind.MIGHT, 4, 3],
	"heartleaf": [Attributes.Kind.VITALITY, 2, 1],
	"wake_root": [Attributes.Kind.AGILITY, 3, 2],
	"ember_stone": [Attributes.Kind.LUCK, 2, 1],
	"rain_pouch": [Attributes.Kind.VITALITY, 2, 1],
	"black_ichor": [Attributes.Kind.MIGHT, 3, 2],
	"gravebloom": [Attributes.Kind.AGILITY, 3, 2],
	# Phase 19: the Relics against marks (card #263), written by hand in data/gear/.
	"wardstone": [Attributes.Kind.VITALITY, 2, 1],
	"bitter_root": [Attributes.Kind.VITALITY, 2, 1],
	"cleansing_bell": [Attributes.Kind.DEFENSE, 3, 2],
}

## Gear ids whose player-facing name changes.
const RENAMES := {"echo_charm": "Rebound Charm"}

## Enemy id -> the Relic ids it can drop.
const DROPS := {
	"rotten_husk": ["iron_charm", "thick_hide", "whetstone"],
	"gnat_swarm": ["quick_boots", "lucky_coin", "ember_stone"],
	"bloat": ["menders_charm", "iron_charm", "hunger_charm", "rain_pouch"],
	"shade": ["keen_eye", "rot_hunter", "wake_root"],
	"carrion_fly": ["lucky_coin", "leaping_heart", "heartleaf"],
	"rot_hyena": ["quick_boots", "riposte_ring", "bloodletters_fang", "wake_root"],
	"mire_toad": ["leaping_heart", "menders_charm", "thick_hide", "heartleaf"],
	"ashen_husk": ["war_drum", "thick_hide", "thorned_gauntlet", "ember_stone"],
	"blight_bloat": ["hunger_charm", "plague_bell", "pale_tithe", "black_ichor"],
	"blood_gnats": ["bloodletters_fang", "ash_veil"],
	"bone_hyena": ["riposte_ring", "gravebound_ring"],
	"elder_toad": ["chain_of_silence", "hollow_mantle", "rain_pouch"],
	"plague_fly": ["plague_bell", "echo_charm", "gravebloom"],
	"hollow_shade": ["last_ember", "keen_eye", "echo_charm"],
	"gorged_one": ["hunger_charm", "war_drum", "second_wind", "black_ichor"],
	"mire_mother": ["hollow_mantle", "chain_of_silence", "second_wind", "gravebloom"],
	"ash_warden": ["ash_veil", "last_ember", "pale_tithe"],
	"husk_lord": ["war_drum", "oathbreakers_band", "gravebound_ring"],
	"hollow_king": ["rotten_crown", "oathbreakers_band", "second_wind"],
	# Phase 19: the new monsters and their deep twins.
	"rot_rat": ["lucky_coin", "quick_boots", "bitter_root"],
	"grave_rat": ["bloodletters_fang", "bitter_root"],
	"ember_slinger": ["ember_stone", "keen_eye", "wardstone"],
	"cinder_slinger": ["last_ember", "ash_veil", "wardstone"],
	"barrow_brute": ["thick_hide", "thorned_gauntlet", "cleansing_bell"],
	"tomb_brute": ["hollow_mantle", "chain_of_silence", "cleansing_bell"],
	"marsh_lantern": ["keen_eye", "echo_charm", "wardstone"],
	"storm_lantern": ["plague_bell", "cleansing_bell"],
	"rot_priest": ["menders_charm", "heartleaf", "bitter_root"],
	"hollow_priest": ["pale_tithe", "cleansing_bell"],
	"pus_tick": ["hunger_charm", "wardstone"],
	"bile_tick": ["plague_bell", "black_ichor"],
}


func _init() -> void:
	_write_new_relics()
	_fade_charms()
	var by_id := {}
	for id: String in RELICS:
		var path := GEAR_DIR + id + ".tres"
		var item := load(path) as GearData
		if item == null:
			push_error("bootstrap_relics: no gear file %s" % path)
			continue
		var row: Array = RELICS[id]
		item.stat = int(row[0])
		item.stat_points = int(row[1])
		item.stat_points_per_level = 1
		item.echo_cost = int(row[2])
		if RENAMES.has(id):
			item.display_name = String(RENAMES[id])
		_save(item, path)
		by_id[id] = item
	for enemy_id: String in DROPS:
		var path := ENEMY_DIR + enemy_id + ".tres"
		var enemy := load(path) as EnemyData
		if enemy == null:
			push_error("bootstrap_relics: no enemy file %s" % path)
			continue
		var drops: Array[GearData] = []
		for id: String in DROPS[enemy_id]:
			if by_id.has(id):
				drops.append(by_id[id] as GearData)
		enemy.relic_drops = drops
		_save(enemy, path)
	print("bootstrap_relics: %d Relics, %d monsters" % [by_id.size(), DROPS.size()])
	quit()


## Writes the Relics made from charm ideas (only ones not written yet) and adds them to the run.
func _write_new_relics() -> void:
	var run := load(RUN_PATH) as RunData
	var gear: Array[GearData] = run.gear.duplicate()
	for id: String in NEW_RELICS:
		var path := GEAR_DIR + id + ".tres"
		if not FileAccess.file_exists(path):
			var row: Array = NEW_RELICS[id]
			var item := GearData.new()
			item.id = id
			item.display_name = String(row[0])
			item.description = String(row[1])
			item.set("rarity", int(row[2]))
			item.set("effect", int(row[3]))
			item.amount = int(row[4])
			item.price = int(row[5])
			item.rot_touched = bool(row[6])
			item.set("drawback", int(row[7]))
			item.drawback_amount = int(row[8])
			_save(item, path)
		var made := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as GearData
		var known := false
		for g: GearData in gear:
			known = known or (g != null and g.id == id)
		if made != null and not known:
			gear.append(made)
	run.gear = gear
	_save(run, RUN_PATH)


## The old charms become faded treasure nobody finds any more; the rotten ones become curses.
func _fade_charms() -> void:
	for id: String in FADED:
		var path := ITEM_DIR + id + ".tres"
		var item := load(path) as ItemData
		if item == null:
			continue
		item.kind = ItemData.Kind.TREASURE
		item.display_name = "Faded " + String(FADED[id])
		item.description = "An old charm. Its power faded when the Relics woke. Worth gold at a shop."
		item.rarity = ItemData.Rarity.COMMON
		item.find_weight = 0
		_save(item, path)
	for id: String in CURSES:
		var path := ITEM_DIR + id + ".tres"
		var item := load(path) as ItemData
		if item == null:
			continue
		item.kind = ItemData.Kind.CURSE
		item.rotten = true
		item.rot_percent = int(CURSES[id])
		item.price = 0
		item.find_weight = 0
		item.description = "A curse. Every hero loses %d%% HP each turn in fights while you carry it. " % int(CURSES[id]) \
				+ "A shop's Cleanse throws it away."
		_save(item, path)


func _save(resource: Resource, path: String) -> void:
	var err := ResourceSaver.save(resource, path)
	if err != OK:
		push_error("bootstrap_relics: could not save %s (%d)" % [path, err])
