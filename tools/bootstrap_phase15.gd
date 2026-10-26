extends SceneTree
## Writes the phase 15 run content (DESIGN.md 8.6 to 8.9): the places' mini-boss guards (DESIGN.md
## 8.6), the first act's boss, the elite fights and the three acts of the run (their "?" events and
## ambushes: tools/bootstrap_events.gd, run it after this one; the second act and its boss, the Leech
## Queen, came with card #323, DESIGN.md 8.23, hand-made, so this writes only the act's file). The mini-bosses and the boss are
## recoloured kin of the monsters (tools/art_kit/assets/enemy_variants.py draws their sheets) with a
## phase two. Rewrites every file it owns. Each place's `guard` (data/zones, met at some of a run's
## Elite stops, DESIGN.md 8.22) points at a guard written here; the place files are never written.
## Run: Godot --headless --path . -s tools/bootstrap_phase15.gd

const EN := "res://data/enemies/"
const ENC := "res://data/encounters/"
const ATK := "res://data/enemy_attacks/"

var _written: int = 0


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/runs/acts"))
	var party: Array = (load(ENC + "husk_fight.tres") as EncounterData).party
	var ultimate := (load(ENC + "husk_fight.tres") as EncounterData).team_ultimate

	# --- mini-boss guards: a named kin of the place's monster, with a phase two ----------------
	var gorged := _boss_kin("gorged_one", "The Gorged One", "bloat", "blight_bloat", Color(0.7, 0.25, 0.35),
			280, 150, 85, 60, 130, "THE GORGED ONE SPLITS ITS SKIN!")
	var mother := _boss_kin("mire_mother", "Mire Mother", "mire_toad", "elder_toad", Color(0.3, 0.55, 0.45),
			270, 145, 105, 60, 130, "THE MIRE MOTHER CALLS THE MUD!")
	var warden := _boss_kin("ash_warden", "Ash Warden", "shade", "hollow_shade", Color(0.85, 0.45, 0.2),
			250, 150, 115, 60, 130, "THE ASH WARDEN BURNS!")
	var gnats := load(EN + "gnat_swarm.tres") as EnemyData
	var blood := load(EN + "blood_gnats.tres") as EnemyData
	var fly := load(EN + "carrion_fly.tres") as EnemyData
	var plague := load(EN + "plague_fly.tres") as EnemyData
	_guard("guard_gorged_one", "The Gorged One", [gorged, gnats], [gorged, blood], party, ultimate)
	_guard("guard_mire_mother", "Mire Mother", [mother, fly], [mother, plague], party, ultimate)
	_guard("guard_ash_warden", "Ash Warden", [warden, gnats], [warden, blood], party, ultimate)

	# --- the first act's boss --------------------------------------------------------------------
	var lord := _boss_kin("husk_lord", "The Husk Lord", "rotten_husk", "ashen_husk", Color(0.75, 0.6, 0.25),
			420, 140, 120, 120, 260, "THE HUSK LORD TEARS FREE OF ITS BARK!")
	lord.phase_two_speed = 165
	_save(lord, EN + "husk_lord.tres")
	var boss := _encounter("husk_lord_fight", "The Husk Lord", [lord, load(EN + "rotten_husk.tres")], party, ultimate)
	boss.boss = true
	boss.can_run = false
	_save(boss, ENC + "husk_lord_fight.tres")

	# --- elite fights (DESIGN.md 8.6) -------------------------------------------------------------
	var husk := load(EN + "rotten_husk.tres") as EnemyData
	var ashen := load(EN + "ashen_husk.tres") as EnemyData
	var hyena := load(EN + "rot_hyena.tres") as EnemyData
	var bone := load(EN + "bone_hyena.tres") as EnemyData
	var toad := load(EN + "mire_toad.tres") as EnemyData
	var elder := load(EN + "elder_toad.tres") as EnemyData
	var shade := load(EN + "shade.tres") as EnemyData
	var hollow := load(EN + "hollow_shade.tres") as EnemyData
	_elite("elite_twin_husks", "Twin Husks", [husk, husk], [ashen, ashen], party, ultimate)
	_elite("elite_hyena_pack", "The Laughing Pack", [hyena, hyena, fly], [bone, bone, plague], party, ultimate)
	_elite("elite_toad_court", "Toad Court", [toad, toad], [elder, elder], party, ultimate)
	_elite("elite_shade_coven", "Shade Coven", [shade, shade, gnats], [hollow, hollow, blood], party, ultimate)

	# --- the acts -------------------------------------------------------------------------
	var run := load("res://data/runs/rotten_road.tres") as RunData
	var zones := {}
	for zone: ZoneData in run.zones:
		zones[zone.id] = zone
	var act1 := ActData.new()
	act1.id = "rotten_road"
	act1.display_name = "The Rotten Road"
	# One place per act since card #323 (DESIGN.md 8.23): forests to husks, rivers to bog, cities to ash.
	act1.zones.assign([zones.rotten_hollow])
	act1.final_encounter = load(ENC + "husk_lord_fight.tres") as EncounterData
	act1.final_look = load("res://data/looks/rotten_hollow.tres") as StageLook
	act1.final_map_icon_path = "res://assets/sprites/ui/map_lair_husk_lord.png"
	act1.elites.assign([_enc("elite_twin_husks"), _enc("elite_shade_coven")])
	# The "?" events and the ambush pools of every act come from tools/bootstrap_events.gd (run it after
	# this one; it fills them in the act files written here).
	var act2 := ActData.new()
	act2.id = "drowned_mire"
	act2.display_name = "The Drowned Mire"
	act2.zones.assign([zones.sunken_bog])
	act2.final_encounter = load(ENC + "leech_queen_fight.tres") as EncounterData
	act2.final_look = load("res://data/looks/leech_lair.tres") as StageLook
	act2.final_map_icon_path = "res://assets/sprites/ui/map_lair_leech_queen.png"
	act2.elites.assign([_enc("elite_toad_court"), _enc("elite_twin_husks")])
	var act3 := ActData.new()
	act3.id = "ashen_deep"
	act3.display_name = "The Ashen Deep"
	act3.zones.assign([zones.ashen_ruins])
	act3.final_encounter = run.final_encounter
	act3.final_look = run.final_look
	act3.final_map_icon_path = run.final_map_icon_path
	act3.elites.assign([_enc("elite_hyena_pack"), _enc("elite_shade_coven")])
	act3.deep = true
	run.acts.assign([_save(act1, "res://data/runs/acts/rotten_road.tres"),
			_save(act2, "res://data/runs/acts/drowned_mire.tres"), _save(act3, "res://data/runs/acts/ashen_deep.tres")])
	_save(run, "res://data/runs/rotten_road.tres")
	print("bootstrap_phase15: wrote %d files" % _written)
	quit()


## A mini-boss or boss: `base`'s look and moves recoloured (sheet `id`.png from enemy_variants.py),
## `variant`'s moves in phase two at half HP.
func _boss_kin(id: String, title: String, base_id: String, variant_id: String, color: Color, hp: int, power: int,
		speed: int, gold: int, xp: int, rage: String) -> EnemyData:
	var base := load(EN + base_id + ".tres") as EnemyData
	var variant := load(EN + variant_id + ".tres") as EnemyData
	var kin := base.duplicate() as EnemyData
	kin.id = id
	kin.display_name = title
	kin.color = color
	kin.sprite_path = "res://assets/sprites/enemies/%s.png" % id
	kin.portrait_path = "res://assets/sprites/portraits/%s.png" % id
	kin.hp_percent = hp
	kin.power_percent = power
	kin.speed = speed
	kin.gold = gold
	kin.xp = xp
	kin.attacks = base.attacks.duplicate()
	kin.phase_two_hp_percent = 50
	kin.phase_two_attacks = variant.attacks.duplicate()
	kin.phase_two_speed = speed + 40
	kin.phase_two_text = rage
	return _save(kin, EN + id + ".tres") as EnemyData


func _encounter(id: String, title: String, enemies: Array, party: Array, ultimate: AbilityData) -> EncounterData:
	var encounter := EncounterData.new()
	encounter.id = id
	encounter.display_name = title
	encounter.party.assign(party)
	encounter.enemies.assign(enemies)
	encounter.team_ultimate = ultimate
	return encounter


## A place's guard: a mini-boss fight (no running), with a deep version (variant helpers).
func _guard(id: String, title: String, enemies: Array, deep_enemies: Array, party: Array, ultimate: AbilityData) -> void:
	var deep := _encounter("deep_" + id, title, deep_enemies, party, ultimate)
	deep.mini_boss = true
	deep.can_run = false
	var guard := _encounter(id, title, enemies, party, ultimate)
	guard.mini_boss = true
	guard.can_run = false
	guard.deep = _save(deep, ENC + "deep_%s.tres" % id) as EncounterData
	_save(guard, ENC + id + ".tres")


func _elite(id: String, title: String, enemies: Array, deep_enemies: Array, party: Array, ultimate: AbilityData) -> void:
	var deep := _encounter("deep_" + id, title, deep_enemies, party, ultimate)
	deep.elite = true
	var elite := _encounter(id, title, enemies, party, ultimate)
	elite.elite = true
	elite.deep = _save(deep, ENC + "deep_%s.tres" % id) as EncounterData
	_save(elite, ENC + id + ".tres")


func _enc(id: String) -> EncounterData:
	return load(ENC + id + ".tres") as EncounterData


func _save(res: Resource, path: String) -> Resource:
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_error("bootstrap_phase15: could not save %s (%d)" % [path, err])
		return res
	_written += 1
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
