extends SceneTree
## Creates the starting data files in data/. Only writes files that do not exist yet, so edits
## made in the editor are never overwritten (the sound library only gains the cues it lacks).
## Run headless:
##   godot --headless --path . -s tools/bootstrap_data.gd
## Add "-- --force" after the script to overwrite everything (careful: loses edits).

const NORMAL := AttackHitData.Kind.NORMAL
const GROUND := AttackHitData.Kind.GROUND
const SINGLE := EnemyAttackData.TargetMode.SINGLE
const PARTY := EnemyAttackData.TargetMode.PARTY

## Every sound cue the game uses. Missing ones are added to the library with these settings.
const CUE_NAMES: Array[String] = ["parry", "parry_final", "dodge", "jump", "whiff", "locked", "hurt",
	"strike", "heavy_strike", "counter", "team_counter", "alert", "lunge", "slam", "downed", "ap_gain",
	"turn_start", "menu_move", "menu_confirm", "menu_cancel", "victory", "defeat", "metronome",
	"skill_press", "follow_up", "heal", "buff", "debuff", "revive", "gauge_full", "ultimate"]
const JITTER_CUES: Array[String] = ["hurt", "strike", "dodge", "whiff", "lunge", "follow_up"]

var _force := false
var _written := 0
var _skipped := 0


func _init() -> void:
	_force = OS.get_cmdline_user_args().has("--force")
	for dir: String in ["res://data/tuning", "res://data/abilities", "res://data/characters",
			"res://data/enemies", "res://data/enemy_attacks", "res://data/encounters", "res://data/audio"]:
		DirAccess.make_dir_recursive_absolute(dir)

	_save_tuning("res://data/tuning/tuning.tres")

	var basic := _skill("basic_attack", "Attack", "A quick strike. Gains 1 AP. Perfect press: +25%.",
			AbilityData.Target.SINGLE_ENEMY, 0, [750], {"damage_percent": 100, "press_damage_percent": 25, "ap_gain": 1,
			"consumes_exposed": false})
	var alder_kit := _alder_kit()
	var brin_kit := _brin_kit()
	var cass_kit := _cass_kit()
	var ultimate := _skill("team_ultimate", "Team Ultimate",
			"Everyone strikes together twice (press on each ring). Revives every downed ally at 25% HP. Needs a full team gauge.",
			AbilityData.Target.SINGLE_ENEMY, 0, [900, 1400], {"damage_percent": 200, "press_damage_percent": 50,
			"team_ultimate": true, "impact_sfx": "ultimate"})

	var alder := _character("alder", "Alder", Color("5b7fbf"), 120, 90, 90, basic, alder_kit)
	var brin := _character("brin", "Brin", Color("c2453d"), 100, 120, 110, basic, brin_kit)
	var cass := _character("cass", "Cass", Color("d8b84a"), 100, 100, 100, basic, cass_kit)
	var party: Array = [alder, brin, cass]

	var husk := _husk()
	var bloat := _bloat()
	var gnat := _gnat_swarm()
	var shade := _shade()

	_encounter("husk_fight", "Rotten Husk", party, [husk], ultimate)
	_encounter("bloat_fight", "Bloat", party, [bloat], ultimate)
	_encounter("gnat_pair", "Two Gnat Swarms", party, [gnat, gnat], ultimate)
	_encounter("shade_fight", "Shade", party, [shade], ultimate)
	_encounter("bloat_and_gnat", "Bloat and Gnat Swarm", party, [bloat, gnat], ultimate)

	_save_sound_library("res://data/audio/sfx_library.tres")

	print("bootstrap_data: wrote %d, kept %d existing" % [_written, _skipped])
	quit()


# --- class kits (DESIGN.md 2.10) --------------------------------------------------------------

func _alder_kit() -> Array:
	return [
		_skill("taunt", "Taunt", "The enemy's next attack on one character must hit Alder. Perfect press: +1 AP.",
				AbilityData.Target.SINGLE_ENEMY, 1, [800], {"damage_percent": 0, "status": Status.TAUNTED, "press_ap_gain": 1,
				"impact_sfx": "debuff"}),
		_skill("guard", "Guard", "One ally takes half damage until their next turn. Perfect press: Alder is guarded too.",
				AbilityData.Target.OTHER_ALLY, 1, [800], {"damage_percent": 0, "status": Status.GUARDED,
				"press_status_on_self": true, "impact_sfx": "buff"}),
		_skill("shield_bash", "Shield Bash", "180% hit. The enemy's next turn comes later. Perfect press: much later.",
				AbilityData.Target.SINGLE_ENEMY, 2, [800], {"damage_percent": 180, "turn_delay_percent": 30,
				"press_turn_delay_percent": 30, "follow_ups": true, "impact_sfx": "heavy_strike"}),
		_skill("riposte_stance", "Riposte Stance", "Until Alder's next turn, his counters hit twice as hard. Perfect press: +1 AP.",
				AbilityData.Target.SELF, 2, [800], {"damage_percent": 0, "status": Status.RIPOSTE, "press_ap_gain": 1,
				"impact_sfx": "buff"}),
		_skill("payback", "Payback", "150% hit, +50% for each perfect parry or jump since Alder's last turn. Perfect press: +50%.",
				AbilityData.Target.SINGLE_ENEMY, 3, [800], {"damage_percent": 150, "per_perfect_defense_percent": 50,
				"press_damage_percent": 50, "follow_ups": true, "impact_sfx": "heavy_strike"}),
	]


func _brin_kit() -> Array:
	return [
		_skill("feint_step", "Feint Step", "80% hit. +1 AP. Perfect press: +2 AP instead.",
				AbilityData.Target.SINGLE_ENEMY, 0, [800], {"damage_percent": 80, "ap_gain": 1, "press_ap_gain": 1,
				"consumes_exposed": false}),
		_skill("quick_cuts", "Quick Cuts", "3 hits of 50%, one press each. Each perfect press: +25% on that hit.",
				AbilityData.Target.SINGLE_ENEMY, 1, [800, 1100, 1400], {"damage_percent": 50, "press_damage_percent": 25,
				"follow_ups": true}),
		_skill("hamstring", "Hamstring", "150% hit. The enemy is slower for 2 of its turns. Perfect press: 3 turns.",
				AbilityData.Target.SINGLE_ENEMY, 2, [800], {"damage_percent": 150, "status": Status.SLOWED, "status_turns": 2,
				"press_status_turns": 1, "follow_ups": true}),
		_skill("rend", "Rend", "300% hit. Removes Exposed for +150%. Perfect press: +30%.",
				AbilityData.Target.SINGLE_ENEMY, 3, [800], {"damage_percent": 300, "press_damage_percent": 30,
				"exposed_bonus_percent": 150, "follow_ups": true, "impact_sfx": "heavy_strike"}),
		_skill("all_in", "All In", "5 hits of 120%, one press each. Each perfect press: +30% on that hit.",
				AbilityData.Target.SINGLE_ENEMY, 5, [800, 1050, 1300, 1550, 1800], {"damage_percent": 120,
				"press_damage_percent": 30, "follow_ups": true}),
	]


func _cass_kit() -> Array:
	return [
		_skill("mend", "Mend", "Heals one ally for 30% of their max HP. Perfect press: 45%.",
				AbilityData.Target.ALLY, 1, [800], {"damage_percent": 0, "heal_percent": 30, "press_heal_percent": 15,
				"impact_sfx": "heal"}),
		_skill("reveal", "Reveal", "60% hit. The enemy becomes Exposed (the next skill on it removes it for +50%). Perfect press: +1 AP.",
				AbilityData.Target.SINGLE_ENEMY, 1, [800], {"damage_percent": 60, "status": Status.EXPOSED, "press_ap_gain": 1,
				"consumes_exposed": false, "follow_ups": true, "impact_sfx": "debuff"}),
		_skill("pass_the_torch", "Pass the Torch", "Gives one ally 2 AP. Perfect press: 3 AP.",
				AbilityData.Target.OTHER_ALLY, 2, [800], {"damage_percent": 0, "give_ap": 2, "press_give_ap": 1,
				"impact_sfx": "buff"}),
		_skill("hasten", "Hasten", "One ally's next turn comes sooner. Perfect press: even sooner.",
				AbilityData.Target.OTHER_ALLY, 2, [800], {"damage_percent": 0, "turn_hasten_percent": 50,
				"press_turn_hasten_percent": 25, "impact_sfx": "buff"}),
		_skill("revive", "Revive", "Brings a downed ally back at 25% HP. Perfect press: 50% HP.",
				AbilityData.Target.DOWNED_ALLY, 3, [800], {"damage_percent": 0, "revive_percent": 25, "press_revive_percent": 25,
				"impact_sfx": "revive"}),
	]


# --- enemies (DESIGN.md 2.9 and 2.11) ---------------------------------------------------------

func _husk() -> EnemyData:
	var attacks := [
		_attack("husk_swipe", "Swipe", SINGLE, 3, true, [_hit(900, NORMAL, 100, 200)]),
		_attack("husk_flurry", "Flurry", SINGLE, 3, true, [
			_hit(900, NORMAL, 45, 180), _hit(1200, NORMAL, 45, 180), _hit(1500, NORMAL, 45, 180)]),
		_attack("husk_lingering_claw", "Lingering Claw", SINGLE, 2, false, [_hit(1600, NORMAL, 130, 200, true)]),
		_attack("husk_ground_slam", "Ground Slam", PARTY, 1, true, [_hit(1100, GROUND, 80, 450)]),
		_attack("husk_rot_combo", "Rot Combo", PARTY, 1, true, [
			_hit(900, NORMAL, 35, 180), _hit(1200, NORMAL, 35, 180), _hit(1700, GROUND, 35, 400),
			_hit(2300, NORMAL, 35, 200)]),
	]
	return _enemy("rotten_husk", "Rotten Husk", Color("7aa344"), 0.05, 100, 100, 200, attacks)


func _bloat() -> EnemyData:
	var attacks := [
		_attack("bloat_belly_slam", "Belly Slam", SINGLE, 3, true, [_hit(1600, NORMAL, 130, 400)]),
		_attack("bloat_rot_wave", "Rot Wave", PARTY, 2, true, [_hit(1200, GROUND, 80, 500)]),
		_attack("bloat_double_wave", "Double Wave", PARTY, 2, true, [
			_hit(1100, GROUND, 55, 450), _hit(1800, GROUND, 55, 450)]),
		_attack("bloat_crush", "Crush", SINGLE, 1, true, [_hit(1400, NORMAL, 70, 300), _hit(2000, GROUND, 70, 400)]),
	]
	return _enemy("bloat", "Bloat", Color("8a6f9e"), 0.065, 180, 140, 80, attacks)


func _gnat_swarm() -> EnemyData:
	var attacks := [
		_attack("gnat_sting_string", "Sting String", SINGLE, 3, true, [
			_hit(800, NORMAL, 30, 160), _hit(1080, NORMAL, 30, 160), _hit(1360, NORMAL, 30, 160),
			_hit(1640, NORMAL, 30, 160), _hit(1920, NORMAL, 30, 160)]),
		_attack("gnat_buzz", "Buzz", SINGLE, 2, true, [
			_hit(800, NORMAL, 25, 150), _hit(1050, NORMAL, 25, 150), _hit(1300, NORMAL, 25, 150),
			_hit(1550, NORMAL, 25, 150), _hit(1800, NORMAL, 25, 150), _hit(2050, NORMAL, 25, 150)]),
		_attack("gnat_swarm_sweep", "Swarm Sweep", PARTY, 1, true, [
			_hit(900, NORMAL, 40, 180), _hit(1200, NORMAL, 40, 180), _hit(1500, NORMAL, 40, 180)]),
	]
	return _enemy("gnat_swarm", "Gnat Swarm", Color("c9b458"), 0.04, 50, 50, 160, attacks)


func _shade() -> EnemyData:
	var attacks := [
		_attack("shade_delayed_rake", "Delayed Rake", SINGLE, 3, false, [_hit(1700, NORMAL, 120, 200, true)]),
		_attack("shade_cross_step", "Cross Step", SINGLE, 2, true, [
			_hit(900, NORMAL, 45, 200), _hit(1450, GROUND, 45, 400), _hit(2000, NORMAL, 45, 200)]),
		_attack("shade_stutter", "Stutter", SINGLE, 2, false, [
			_hit(800, NORMAL, 40, 180), _hit(1600, NORMAL, 40, 200, true), _hit(1900, NORMAL, 40, 180)]),
		_attack("shade_nightfall", "Nightfall", PARTY, 1, false, [
			_hit(1000, GROUND, 60, 450), _hit(1600, NORMAL, 60, 200, true)]),
	]
	return _enemy("shade", "Shade", Color("4b4f7a"), 0.05, 90, 100, 130, attacks)


# --- builders ---------------------------------------------------------------------------------

## Saves the resource unless the file exists (then loads and returns the existing one, so other
## files reference it).
func _save(res: Resource, path: String) -> Resource:
	if FileAccess.file_exists(path) and not _force:
		_skipped += 1
		return load(path)
	var err := ResourceSaver.save(res, path)
	if err != OK:
		push_error("bootstrap_data: could not save %s (%d)" % [path, err])
		return res
	_written += 1
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)


## Writes the tuning file with every value spelled out (Godot normally leaves defaults out,
## which would make the file look empty).
func _save_tuning(path: String) -> void:
	if FileAccess.file_exists(path) and not _force:
		_skipped += 1
		return
	var t := Tuning.new()
	var lines := PackedStringArray()
	lines.append('[gd_resource type="Resource" script_class="Tuning" format=3]')
	lines.append("")
	lines.append('[ext_resource type="Script" path="res://scripts/data/tuning.gd" id="1_tuning"]')
	lines.append("")
	lines.append("[resource]")
	lines.append('script = ExtResource("1_tuning")')
	for p: Dictionary in t.get_property_list():
		if (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) and (p.usage & PROPERTY_USAGE_STORAGE):
			lines.append("%s = %s" % [p.name, var_to_str(t.get(p.name))])
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	_written += 1


## Adds the cues the library lacks (creates it if missing). Existing cues keep their settings.
func _save_sound_library(path: String) -> void:
	var library: SfxLibrary = null
	if FileAccess.file_exists(path) and not _force:
		library = load(path) as SfxLibrary
	if library == null:
		library = SfxLibrary.new()
	var known: Dictionary = {}
	for cue: SfxCue in library.cues:
		if cue != null:
			known[cue.name] = true
	var added := 0
	for cue_name: String in CUE_NAMES:
		if known.has(cue_name):
			continue
		var cue := SfxCue.new()
		cue.name = cue_name
		cue.path = "res://assets/audio/sfx/%s.wav" % cue_name
		cue.volume_db = 0.0
		cue.pitch_jitter = 0.04 if JITTER_CUES.has(cue_name) else 0.0
		library.cues.append(cue)
		added += 1
	if added == 0:
		_skipped += 1
		return
	var err := ResourceSaver.save(library, path)
	if err != OK:
		push_error("bootstrap_data: could not save %s (%d)" % [path, err])
		return
	_written += 1


## An ability saved to data/abilities/<id>.tres. `fields` sets any other AbilityData property.
func _skill(id: String, title: String, desc: String, target: AbilityData.Target, cost: int, presses: Array,
		fields: Dictionary) -> AbilityData:
	var a := AbilityData.new()
	a.id = id
	a.display_name = title
	a.description = desc
	a.target = target
	a.ap_cost = cost
	a.press_times_ms.assign(presses)
	a.impact_sfx = "strike"
	for key: String in fields:
		a.set(key, fields[key])
	return _save(a, "res://data/abilities/%s.tres" % id) as AbilityData


func _character(id: String, title: String, color: Color, hp_pct: int, power_pct: int, speed: int,
		basic: AbilityData, skills: Array) -> CharacterData:
	var c := CharacterData.new()
	c.id = id
	c.display_name = title
	c.color = color
	c.sprite_path = "res://assets/sprites/characters/%s.png" % id
	c.portrait_path = "res://assets/sprites/portraits/%s.png" % id
	c.sprite_pixel_size = 0.045
	c.hp_percent = hp_pct
	c.power_percent = power_pct
	c.speed = speed
	c.basic_attack = basic
	c.skills.assign(skills)
	return _save(c, "res://data/characters/%s.tres" % id) as CharacterData


func _enemy(id: String, title: String, color: Color, pixel_size: float, hp_pct: int, power_pct: int,
		speed: int, attacks: Array) -> EnemyData:
	var e := EnemyData.new()
	e.id = id
	e.display_name = title
	e.color = color
	e.sprite_path = "res://assets/sprites/enemies/%s.png" % id
	e.portrait_path = "res://assets/sprites/portraits/%s.png" % id
	e.sprite_pixel_size = pixel_size
	e.hp_percent = hp_pct
	e.power_percent = power_pct
	e.speed = speed
	e.attacks.assign(attacks)
	return _save(e, "res://data/enemies/%s.tres" % id) as EnemyData


func _encounter(id: String, title: String, party: Array, enemies: Array, ultimate: AbilityData) -> void:
	var encounter := EncounterData.new()
	encounter.id = id
	encounter.display_name = title
	encounter.party.assign(party)
	encounter.enemies.assign(enemies)
	encounter.team_ultimate = ultimate
	_save(encounter, "res://data/encounters/%s.tres" % id)


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
