extends SceneTree
## Creates the phase 4 run data (DESIGN.md 8): gear, the new encounters, the looks of two more
## places (Sunken Bog, Ashen Ruins), the boss (The Hollow King) with its attacks and look, and the
## run itself. Only writes files that do not exist yet, so edits made in the editor are never
## overwritten; an existing run only gains gear and the boss if it has none.
## Run headless:
##   godot --headless --path . -s tools/bootstrap_run.gd
## Add "-- --force" after the script to overwrite them (careful: loses edits).
## Then run tools/gen_placeholders.gd to draw any new ground tiles, and tools/bootstrap_items.gd for
## the backpack items the shops sell (phase 11). The places (data/zones) are read, never written:
## phase 4 wrote small walkable zones here, which phase 26 removed (DESIGN.md 8.22); a place is now
## a fight's look, air, weathers, monsters and guard, edited in its file.

const ENV := "res://assets/sprites/env/"
const BOG_LIGHT := Color(0.55, 1.0, 0.6)
const THRONE_LIGHT := Color(1.0, 0.45, 0.35)
const NORMAL := AttackHitData.Kind.NORMAL
const GROUND := AttackHitData.Kind.GROUND
const SINGLE := EnemyAttackData.TargetMode.SINGLE
const PARTY := EnemyAttackData.TargetMode.PARTY
const G := GearData.Effect

var _force := false
var _written := 0
var _skipped := 0


func _init() -> void:
	_force = OS.get_cmdline_user_args().has("--force")
	for dir: String in ["res://data/runs", "res://data/looks", "res://data/gear"]:
		DirAccess.make_dir_recursive_absolute(dir)

	var party: Array = [load("res://data/characters/alder.tres"), load("res://data/characters/brin.tres"),
			load("res://data/characters/cass.tres")]
	var ultimate := load("res://data/abilities/team_ultimate.tres") as AbilityData
	var husk := load("res://data/enemies/rotten_husk.tres") as EnemyData
	var bloat := load("res://data/enemies/bloat.tres") as EnemyData
	var gnat := load("res://data/enemies/gnat_swarm.tres") as EnemyData
	var shade := load("res://data/enemies/shade.tres") as EnemyData
	_encounter("husk_and_gnat", "Rotten Husk and Gnat Swarm", party, [husk, gnat], ultimate)
	_encounter("shade_and_gnat", "Shade and Gnat Swarm", party, [shade, gnat], ultimate)
	var final_stand := _encounter("final_stand", "The Last Gate", party, [shade, bloat], ultimate)

	var hollow_look := load("res://data/looks/rotten_hollow.tres") as StageLook
	_bog_look(hollow_look)
	var ash_look := _ash_look(hollow_look)

	var gear := _gear_list()
	var king := _hollow_king()
	var king_fight := _encounter("hollow_king", "The Hollow King", party, [king, load("res://data/enemies/hollow_shade.tres")], ultimate)
	if not king_fight.boss:
		king_fight.boss = true
		ResourceSaver.save(king_fight, king_fight.resource_path)
	var throne_look := _throne_look(ash_look)

	var run_path := "res://data/runs/rotten_road.tres"
	var run := RunData.new()
	run.id = "rotten_road"
	run.display_name = "The Rotten Road"
	run.party.assign(party)
	run.team_ultimate = ultimate
	run.zones.assign([load("res://data/zones/rotten_hollow.tres"), load("res://data/zones/sunken_bog.tres"),
			load("res://data/zones/ashen_ruins.tres")])
	run.final_encounter = king_fight
	run.final_look = throne_look
	run.gear.assign(gear)
	run = _save(run, run_path) as RunData
	# A run saved before Part B: give it the gear and the boss.
	if run.gear.is_empty() or run.final_encounter == final_stand:
		run.gear.assign(gear)
		run.final_encounter = king_fight
		run.final_look = throne_look
		ResourceSaver.save(run, run_path)
		_written += 1
	print("bootstrap_run: wrote %d, kept %d existing" % [_written, _skipped])
	quit()


# --- gear (Part B) ----------------------------------------------------------------------------

func _gear_list() -> Array[GearData]:
	var list: Array[GearData] = [
		_gear("whetstone", "Whetstone", "Power +15%: every hit, skill and counter.", 70, G.POWER, 15),
		_gear("quick_boots", "Quick Boots", "Speed +15: turns come sooner.", 60, G.SPEED, 15),
		_gear("war_drum", "War Drum", "Start every fight with +1 AP.", 70, G.START_AP, 1),
		_gear("riposte_ring", "Riposte Ring", "Counters hit 50% harder.", 70, G.COUNTER, 50),
		_gear("echo_charm", "Echo Charm", "+1 AP after each counter.", 60, G.AP_ON_COUNTER, 1),
		_gear("leaping_heart", "Leaping Heart", "Each perfect jump heals 5% of max HP.", 60, G.HEAL_ON_JUMP, 5),
		_gear("second_wind", "Second Wind", "Once per fight: fall during an enemy attack, get back up when it ends with 30% HP.",
				80, G.SECOND_WIND, 30),
		_gear("keen_eye", "Keen Eye", "Perfect skill presses deal +25%.", 60, G.PERFECT_PRESS, 25),
		_gear("rot_hunter", "Rot Hunter", "Hits on Exposed enemies deal +50% more.", 60, G.EXPOSED, 50),
		_gear("thick_hide", "Thick Hide", "Enemy hits deal 15% less.", 70, G.TOUGH, 15),
		_gear("menders_charm", "Mender's Charm", "Heals you give are 30% stronger.", 50, G.HEAL, 30),
	]
	return list


func _gear(id: String, title: String, desc: String, price: int, effect: GearData.Effect, amount: int) -> GearData:
	var item := GearData.new()
	item.id = id
	item.display_name = title
	item.description = desc
	item.price = price
	item.effect = effect
	item.amount = amount
	return _save(item, "res://data/gear/%s.tres" % id) as GearData


# --- the boss (Part B) ------------------------------------------------------------------------

## The Hollow King: long strings that mix parries and jumps; at half HP it gets faster and
## brings out its six-hit Kingsfall and a feint.
func _hollow_king() -> EnemyData:
	var cleave := _attack("king_cleave", "Cleave", SINGLE, 3, true, [_hit(1000, NORMAL, 120, 220)])
	var sweep := _attack("king_crown_sweep", "Crown Sweep", PARTY, 2, true, [
		_hit(900, NORMAL, 40, 180), _hit(1200, NORMAL, 40, 180), _hit(1500, NORMAL, 40, 180)])
	var stomp := _attack("king_grave_stomp", "Grave Stomp", PARTY, 2, true, [
		_hit(1100, GROUND, 50, 450), _hit(1700, GROUND, 50, 450)])
	var cascade := _attack("king_rot_cascade", "Rot Cascade", SINGLE, 2, true, [
		_hit(900, NORMAL, 25, 180), _hit(1200, NORMAL, 25, 180), _hit(1700, GROUND, 25, 400),
		_hit(2200, NORMAL, 25, 200), _hit(2700, GROUND, 25, 400)])
	var kingsfall := _attack("king_kingsfall", "Kingsfall", PARTY, 2, true, [
		_hit(900, NORMAL, 25, 180), _hit(1150, NORMAL, 25, 160), _hit(1400, NORMAL, 25, 160),
		_hit(1900, GROUND, 25, 400), _hit(2400, NORMAL, 25, 200), _hit(2900, GROUND, 25, 400)])
	var false_crown := _attack("king_false_crown", "False Crown", SINGLE, 2, false, [
		_hit(800, NORMAL, 35, 180), _hit(1700, NORMAL, 40, 200, true), _hit(2000, NORMAL, 35, 180),
		_hit(2500, GROUND, 40, 400)])
	var wave := _attack("king_hollow_wave", "Hollow Wave", PARTY, 1, true, [_hit(1200, GROUND, 70, 500)])
	var path := "res://data/enemies/hollow_king.tres"
	if FileAccess.file_exists(path) and not _force:
		_skipped += 1
		return load(path) as EnemyData
	var e := EnemyData.new()
	e.id = "hollow_king"
	e.voice_sfx = "voice_king"
	e.display_name = "The Hollow King"
	e.color = Color("8e2f3a")
	e.sprite_path = "res://assets/sprites/enemies/hollow_king.png"
	e.portrait_path = "res://assets/sprites/portraits/hollow_king.png"
	e.sprite_pixel_size = 0.045
	e.hp_percent = 650
	e.power_percent = 165
	e.speed = 155
	e.gold = 0
	e.xp = 0
	e.attacks.assign([cleave, sweep, stomp, cascade])
	e.phase_two_hp_percent = 50
	e.phase_two_attacks.assign([cleave, cascade, kingsfall, false_crown, wave])
	e.phase_two_speed = 210
	e.phase_two_text = "THE HOLLOW KING RAGES!"
	e.runs_up = true
	return _save(e, path) as EnemyData


func _attack(id: String, title: String, mode: EnemyAttackData.TargetMode, weight: int, ring: bool,
		hits: Array) -> EnemyAttackData:
	var a := EnemyAttackData.new()
	a.id = id
	a.display_name = title
	a.target_mode = mode
	a.weight = weight
	a.alert_cue = true
	a.allow_timing_ring = ring
	a.hits.assign(hits)
	return _save(a, "res://data/enemy_attacks/%s.tres" % id) as EnemyAttackData


func _hit(impact_ms: int, kind: AttackHitData.Kind, pct: int, approach_ms: int, feint: bool = false) -> AttackHitData:
	var h := AttackHitData.new()
	h.impact_ms = impact_ms
	h.kind = kind
	h.damage_percent = pct
	h.approach_ms = approach_ms
	h.feint = feint
	h.impact_sfx = "hurt"
	return h


## The boss's hall: the Ashen Ruins under a red glow.
func _throne_look(base: StageLook) -> StageLook:
	var look := base.duplicate(true) as StageLook
	look.floor_tile_path = ENV + "throne_tile.png"
	look.floor_variant_paths = [ENV + "throne_tile_b.png", ENV + "throne_tile_c.png"]
	look.background_color = Color(0.07, 0.03, 0.04)
	look.ambient_color = Color(0.42, 0.3, 0.34)
	look.light_color = Color(1.0, 0.7, 0.6)
	look.light_energy = 0.9
	look.fog_color = Color(0.26, 0.12, 0.14)
	look.fog_density = 0.03
	look.saturation = 0.95
	look.vignette_strength = 0.6
	look.vignette_color = Color(0.05, 0.0, 0.0)
	for light: ZoneLightData in look.arena_lights:
		light.color = THRONE_LIGHT
	return _save(look, "res://data/looks/hollow_throne.tres") as StageLook


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
	look.floor_variant_paths = [ENV + "bog_tile_b.png", ENV + "bog_tile_c.png"]
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
	look.floor_variant_paths = [ENV + "ash_tile_b.png", ENV + "ash_tile_c.png"]
	look.background_color = Color(0.06, 0.06, 0.09)
	look.ambient_color = Color(0.38, 0.42, 0.58)
	look.light_color = Color(0.75, 0.85, 1.0)
	look.light_energy = 1.0
	look.fog_color = Color(0.2, 0.21, 0.28)
	look.fog_density = 0.02
	look.saturation = 0.85
	look.contrast = 1.15
	return _save(look, "res://data/looks/ashen_ruins.tres") as StageLook
