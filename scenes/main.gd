extends Node
## Entry point (run/main_scene). Reads the user arguments and the tuning, shows the fight list
## (phase 2 test menu) and starts the chosen fight. R / "fight again" frees the fight and starts
## the same one again; Cancel on the end screen goes back to the list. The options (and the F1
## statistics they hold) survive restarts.
##
## User arguments (after "--"): --autoplay[=perfect|miss|mash], --quit-on-end, --seed=N,
## --encounter=ID (start that fight directly; autoplay without it starts DEFAULT_ENCOUNTER_ID).

const DEFAULT_ENCOUNTER_ID := "husk_fight"
const TUNING_PATH := "res://data/tuning/tuning.tres"
const VISUALS_PATH := "res://data/presentation/combat_visuals.tres"
const COMBAT_SCENE := preload("res://scenes/combat.tscn")

var _encounters: Array[EncounterData] = []
var _encounter: EncounterData
var _tuning: Tuning
var _visuals: CombatVisuals
var _options: CombatOptions
var _combat: CombatController
var _select: FightSelect
var _select_index: int = 0


func _ready() -> void:
	_tuning = load(TUNING_PATH) as Tuning
	_visuals = load(VISUALS_PATH) as CombatVisuals
	_encounters = FightSelect.load_encounters()
	if _encounters.is_empty() or _tuning == null:
		push_error("Main: could not load the encounters in %s or %s" % [FightSelect.ENCOUNTER_DIR, TUNING_PATH])
		return
	if _visuals == null:
		push_warning("Main: could not load %s, using built-in presentation defaults" % VISUALS_PATH)
		_visuals = CombatVisuals.new()
	_options = CombatOptions.from_args(OS.get_cmdline_user_args(), _tuning)
	if _options.is_autoplay():
		print("Autoplay: %s%s" % [_options.autoplay_mode, " (quit on end)" if _options.quit_on_end else ""])
	var wanted := _options.encounter_id
	if wanted.is_empty() and _options.is_autoplay():
		wanted = DEFAULT_ENCOUNTER_ID
	if wanted.is_empty():
		_show_select()
		return
	for i: int in _encounters.size():
		if _encounters[i].id == wanted:
			_select_index = i
			_encounter = _encounters[i]
	if _encounter == null:
		push_error("Main: no encounter with id '%s'" % wanted)
		if _options.is_autoplay():
			print("AUTOPLAY_ERROR unknown encounter %s" % wanted)
			get_tree().quit(1)
		return
	_start_combat()


func _show_select() -> void:
	if _combat != null:
		remove_child(_combat)
		_combat.queue_free()
		_combat = null
	_select = FightSelect.new()
	_select.name = "FightSelect"
	_select.setup(_encounters, _select_index)
	_select.chosen.connect(_on_fight_chosen)
	add_child(_select)


func _on_fight_chosen(encounter: EncounterData) -> void:
	_select_index = _select.selected_index()
	_encounter = encounter
	_select.queue_free()
	_select = null
	_start_combat.call_deferred()


func _start_combat() -> void:
	if _combat != null:
		remove_child(_combat)
		_combat.queue_free()
	_combat = COMBAT_SCENE.instantiate() as CombatController
	_combat.configure(_encounter, _tuning, _visuals, _options)
	_combat.restart_requested.connect(_on_restart_requested)
	_combat.select_requested.connect(_show_select.call_deferred)
	add_child(_combat)


func _on_restart_requested() -> void:
	_start_combat.call_deferred()
