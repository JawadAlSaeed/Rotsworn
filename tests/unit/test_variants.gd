extends GutTest
## Monster variants (DESIGN 2.16): every fight a zone of the shipped run holds has a deep version
## made of variant monsters; a variant is tougher than its base, adds a move of its own and plays
## its base's clips on a sheet of the same size; a run is deep from map row run_deep_row on; every
## enemy's voice is a cue of the sfx library.

const RUN_PATH := "res://data/runs/rotten_road.tres"
## Variant id -> its base monster.
const BASES: Dictionary = {
	"ashen_husk": "rotten_husk",
	"blight_bloat": "bloat",
	"blood_gnats": "gnat_swarm",
	"hollow_shade": "shade",
	"bone_hyena": "rot_hyena",
	"plague_fly": "carrion_fly",
	"elder_toad": "mire_toad",
	# Phase 19 (cards #255 to #260).
	"grave_rat": "rot_rat",
	"cinder_slinger": "ember_slinger",
	"tomb_brute": "barrow_brute",
	"storm_lantern": "marsh_lantern",
	"hollow_priest": "rot_priest",
	"bile_tick": "pus_tick",
}

var _data: RunData


func before_all() -> void:
	_data = load(RUN_PATH) as RunData


func _enemy(id: String) -> EnemyData:
	return load("res://data/enemies/%s.tres" % id) as EnemyData


func test_every_place_fight_has_a_deep_version_of_variants() -> void:
	var checked := 0
	for zone: ZoneData in _data.zones:
		var fights: Array[EncounterData] = zone.roamer_pool.duplicate()
		if zone.guard != null:
			fights.append(zone.guard)
		for encounter: EncounterData in fights:
			var label := "%s: %s" % [zone.id, encounter.id]
			assert_not_null(encounter.deep, label + " has a deep version")
			if encounter.deep == null:
				continue
			assert_null(encounter.deep.deep, label + ": a deep fight goes no deeper")
			assert_eq(encounter.deep.enemies.size(), encounter.enemies.size(), label + ": as many monsters")
			for i: int in encounter.enemies.size():
				var base := encounter.enemies[i]
				var variant := encounter.deep.enemies[i]
				# A guard's mini-boss (DESIGN.md 8.6) stays itself; only its helpers turn into variants.
				if encounter.mini_boss and variant == base:
					continue
				assert_eq(String(BASES.get(variant.id, "")), base.id, label + ": %s is the variant of %s" % [variant.id, base.id])
			checked += 1
	assert_gt(checked, 8, "the zones' fights")


func test_variants_are_tougher_kin_of_their_base() -> void:
	for variant_id: String in BASES:
		var variant := _enemy(variant_id)
		var base := _enemy(String(BASES[variant_id]))
		assert_not_null(variant, variant_id)
		if variant == null or base == null:
			continue
		assert_gt(variant.hp_percent, base.hp_percent, variant_id + ": more HP")
		assert_gt(variant.power_percent, base.power_percent, variant_id + ": hits harder")
		assert_gt(variant.attacks.size(), base.attacks.size(), variant_id + ": a move of its own")
		for attack: EnemyAttackData in base.attacks:
			assert_true(variant.attacks.has(attack), variant_id + " keeps " + attack.id)
		assert_eq(variant.sprite_clips, base.sprite_clips, variant_id + ": plays its base's clips")
		var sheet := load(variant.sprite_path) as Texture2D
		var base_sheet := load(base.sprite_path) as Texture2D
		assert_not_null(sheet, variant_id + ": its sheet exists")
		if sheet != null and base_sheet != null:
			assert_eq(sheet.get_size(), base_sheet.get_size(), variant_id + ": same layout as its base")
		assert_true(ResourceLoader.exists(variant.portrait_path), variant_id + ": its portrait exists")


func test_a_run_is_deep_from_the_deep_row_on() -> void:
	var tuning := Tuning.new()
	var run := RunState.begin(_data, tuning, 3)
	assert_false(run.is_deep(), "not deep before the first stop")
	while not run.is_over() and not run.choices().is_empty():
		run.go(run.choices()[0])
		var row := int(run.current().get("row", 0))
		assert_eq(run.is_deep(), row >= tuning.run_deep_row, "row %d" % row)
		if row >= tuning.run_deep_row:
			break
	assert_true(run.is_deep(), "a long enough run goes deep")


func test_every_enemy_voice_exists() -> void:
	var library := load("res://data/audio/sfx_library.tres") as SfxLibrary
	for file: String in DirAccess.get_files_at("res://data/enemies"):
		if not file.ends_with(".tres"):
			continue
		var enemy := load("res://data/enemies/" + file) as EnemyData
		if not enemy.voice_sfx.is_empty():
			assert_not_null(library.find(enemy.voice_sfx), "%s's voice '%s' is in the sfx library" % [enemy.id, enemy.voice_sfx])
