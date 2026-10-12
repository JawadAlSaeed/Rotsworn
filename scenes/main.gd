extends Node
## Entry point (run/main_scene). Reads the user arguments and the tuning, shows the start menu
## (zones to explore, then test fights) and runs what was chosen. A zone (DESIGN.md 7.4) hands a
## fight over with encounter_started: the screen swirls into the fight, the zone waits outside the
## tree, and after the fight the screen fades back to the zone. R / "fight again" frees the fight
## and starts the same one again; Cancel on a test fight's end screen goes back to the menu. The
## options (and the F1 statistics they hold) survive restarts.
##
## User arguments (after "--"): --autoplay[=perfect|miss|mash], --quit-on-end, --seed=N,
## --encounter=ID (start that fight directly; autoplay without it or --zone starts
## DEFAULT_ENCOUNTER_ID), --zone=ID (start in that zone), --first-strike (with --encounter).

const DEFAULT_ENCOUNTER_ID := "husk_fight"
const TUNING_PATH := "res://data/tuning/tuning.tres"
const VISUALS_PATH := "res://data/presentation/combat_visuals.tres"
const EXPLORE_VISUALS_PATH := "res://data/presentation/explore_visuals.tres"
const COMBAT_SCENE := preload("res://scenes/combat.tscn")
## Autoplay: wait this long on a zone fight's end screen before going back (seconds).
const AUTOPLAY_RETURN_S: float = 1.0
## Autoplay: give up when no fight has started for this long in a zone (seconds).
const AUTOPLAY_ZONE_STUCK_S: float = 60.0
const QUIT_AUDIO_RELEASE_S: float = 0.3

var _encounters: Array[EncounterData] = []
var _zones: Array[ZoneData] = []
var _encounter: EncounterData
var _tuning: Tuning
var _visuals: CombatVisuals
var _explore: ExploreVisuals
var _options: CombatOptions
var _combat: CombatController
var _select: FightSelect
var _select_index: int = 0
var _zone: ZoneController
var _transition: ScreenTransition
## The fight that started in the zone: {index, opening}, or empty.
var _zone_fight: Dictionary = {}
var _busy: bool = false
var _zone_idle_s: float = 0.0


func _ready() -> void:
	_tuning = load(TUNING_PATH) as Tuning
	_visuals = load(VISUALS_PATH) as CombatVisuals
	_explore = load(EXPLORE_VISUALS_PATH) as ExploreVisuals
	_encounters = FightSelect.load_encounters()
	_zones = FightSelect.load_zones()
	if _encounters.is_empty() or _tuning == null:
		push_error("Main: could not load the encounters in %s or %s" % [FightSelect.ENCOUNTER_DIR, TUNING_PATH])
		return
	if _visuals == null:
		push_warning("Main: could not load %s, using built-in presentation defaults" % VISUALS_PATH)
		_visuals = CombatVisuals.new()
	if _explore == null:
		push_warning("Main: could not load %s, using built-in exploration defaults" % EXPLORE_VISUALS_PATH)
		_explore = ExploreVisuals.new()
	_transition = ScreenTransition.new()
	_transition.name = "Transition"
	add_child(_transition)
	_transition.setup(_explore)
	_options = CombatOptions.from_args(OS.get_cmdline_user_args(), _tuning)
	if _options.is_autoplay():
		print("Autoplay: %s%s" % [_options.autoplay_mode, " (quit on end)" if _options.quit_on_end else ""])
	if not _options.zone_id.is_empty():
		for zone: ZoneData in _zones:
			if zone.id == _options.zone_id:
				_start_zone(zone)
				return
		push_error("Main: no zone with id '%s'" % _options.zone_id)
		_autoplay_fail("unknown zone %s" % _options.zone_id)
		return
	var wanted := _options.encounter_id
	if wanted.is_empty() and _options.is_autoplay():
		wanted = DEFAULT_ENCOUNTER_ID
	if wanted.is_empty():
		_show_select()
		return
	for i: int in _encounters.size():
		if _encounters[i].id == wanted:
			_select_index = _zones.size() + i
			_encounter = _encounters[i]
	if _encounter == null:
		push_error("Main: no encounter with id '%s'" % wanted)
		_autoplay_fail("unknown encounter %s" % wanted)
		return
	_start_combat()


## A zone parked outside the tree during a fight is not freed with the tree: free it here.
func _exit_tree() -> void:
	if _zone != null and not _zone.is_inside_tree():
		_zone.free()
		_zone = null


func _process(delta: float) -> void:
	# Autoplay guard: a zone run that never reaches a fight is stuck.
	if not _options.is_autoplay() or _zone == null or not _zone.is_inside_tree() or _zone.is_frozen():
		_zone_idle_s = 0.0
		return
	_zone_idle_s += delta
	if _zone_idle_s > AUTOPLAY_ZONE_STUCK_S:
		_zone_idle_s = 0.0
		_autoplay_fail("zone_stuck")


func _show_select() -> void:
	_free_combat()
	_free_zone()
	_select = FightSelect.new()
	_select.name = "FightSelect"
	_select.setup(_zones, _encounters, _select_index)
	_select.chosen.connect(_on_fight_chosen)
	_select.zone_chosen.connect(_on_zone_chosen)
	add_child(_select)


func _on_fight_chosen(encounter: EncounterData) -> void:
	_select_index = _select.selected_index()
	_encounter = encounter
	_zone_fight = {}
	_select.queue_free()
	_select = null
	_start_combat.call_deferred()


func _on_zone_chosen(zone: ZoneData) -> void:
	_select_index = _select.selected_index()
	_select.queue_free()
	_select = null
	_start_zone.call_deferred(zone)


## Builds a fight: a test fight, or the zone's current fight (its look, opening and end screen).
func _start_combat() -> void:
	_free_combat()
	_combat = COMBAT_SCENE.instantiate() as CombatController
	if _zone_fight.is_empty():
		var opening := CombatSetup.Opening.FIRST_STRIKE if _options.first_strike else CombatSetup.Opening.NORMAL
		_combat.configure(_encounter, _tuning, _visuals, _options, null, opening)
	else:
		_combat.configure(_encounter, _tuning, _visuals, _options, _zone.look(),
				_zone_fight.opening as CombatSetup.Opening, true)
		_combat.zone_return_requested.connect(_on_zone_return_requested)
		if _options.is_autoplay():
			_combat.combat_finished.connect(_on_zone_fight_finished_autoplay)
	_combat.restart_requested.connect(_on_restart_requested)
	_combat.select_requested.connect(_show_select.call_deferred)
	add_child(_combat)


func _on_restart_requested() -> void:
	_start_combat.call_deferred()


func _free_combat() -> void:
	if _combat != null:
		if _combat.is_inside_tree():
			remove_child(_combat)
		_combat.queue_free()
		_combat = null


# --- zones ------------------------------------------------------------------------------------

func _start_zone(zone: ZoneData) -> void:
	_free_combat()
	_free_zone()
	_zone_fight = {}
	_zone = ZoneController.new()
	_zone.name = "Zone"
	_zone.configure(zone, _tuning, _visuals, _explore)
	_zone.encounter_started.connect(_on_encounter_started)
	_zone.leave_requested.connect(_show_select.call_deferred)
	_zone.cleared.connect(_on_zone_cleared)
	add_child(_zone)
	if _options.is_autoplay():
		var bot := ZoneAutoplay.new()
		bot.name = "ZoneAutoplay"
		_zone.add_child(bot)
		bot.setup(_zone, _tuning, _options.autoplay_mode)


func _free_zone() -> void:
	if _zone != null:
		if _zone.is_inside_tree():
			remove_child(_zone)
		_zone.queue_free()
		_zone = null


## The zone started a fight: swirl out, park the zone outside the tree, fade the fight in.
func _on_encounter_started(index: int, opening: CombatSetup.Opening) -> void:
	if _busy:
		return
	_busy = true
	_zone_fight = {"index": index, "opening": opening}
	_encounter = _zone.encounter_of(index)
	await _transition.swirl_out()
	remove_child(_zone)
	_start_combat()
	await get_tree().process_frame
	await _transition.fade_in()
	_busy = false


## The zone fight's end screen was left: fade out, free the fight, bring the zone back.
func _on_zone_return_requested(result: String) -> void:
	if _busy or _zone == null:
		return
	_busy = true
	await _transition.fade_out()
	_free_combat()
	_zone_fight = {}
	add_child(_zone)
	_zone.resume(result)
	await get_tree().process_frame
	await _transition.fade_in()
	_busy = false
	if result != "victory" and _options.is_autoplay():
		print("AUTOPLAY_RESULT zone_defeat fights=%d first_strikes=%d" % [_zone.fights_started(), _zone.first_strikes()])
		_autoplay_quit()


func _on_zone_fight_finished_autoplay(result: String) -> void:
	await get_tree().create_timer(AUTOPLAY_RETURN_S).timeout
	_on_zone_return_requested(result)


func _on_zone_cleared() -> void:
	if not _options.is_autoplay():
		return
	print("AUTOPLAY_RESULT zone_clear fights=%d first_strikes=%d" % [_zone.fights_started(), _zone.first_strikes()])
	_autoplay_quit()


# --- autoplay endings -------------------------------------------------------------------------

func _autoplay_fail(reason: String) -> void:
	if not _options.is_autoplay():
		return
	print("AUTOPLAY_ERROR " + reason)
	get_tree().quit(1)


func _autoplay_quit() -> void:
	if not _options.quit_on_end:
		return
	await get_tree().create_timer(AUTOPLAY_RETURN_S).timeout
	Sfx.stop_all()
	await get_tree().create_timer(QUIT_AUDIO_RELEASE_S, true, false, true).timeout
	get_tree().quit(0)
