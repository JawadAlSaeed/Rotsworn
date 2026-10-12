extends Node
## Entry point (run/main_scene). Shows the main menu (DESIGN.md 7.5): a new run (DESIGN.md 8),
## practice (the zone and fight list), settings, quit. New Run and Practice open the players screen
## first (co-op, DESIGN.md 9.1); its roster goes to every fight and zone. In a run the map screen
## leads to the stops: zones, rests, shops and the final fight; RunState carries HP and gold from stop to stop.
## A zone (DESIGN.md 7.4) hands a fight over with encounter_started: the screen swirls into the
## fight, the zone waits outside the tree, and after the fight the screen fades back to the zone.
## R / "fight again" frees a practice fight and starts the same one again; Cancel on a practice
## fight's end screen goes back to the practice list. The options (and the F1 statistics they
## hold) survive restarts.
##
## User arguments (after "--"): --autoplay[=perfect|miss|mash], --quit-on-end, --seed=N,
## --encounter=ID (start that fight directly; autoplay without it, --zone or --run starts
## DEFAULT_ENCOUNTER_ID), --zone=ID (start in that zone), --first-strike (with --encounter),
## --run (start a new run at once; the seed also picks the map), --players=N (co-op with N pretend
## pads, for the bot).

const DEFAULT_ENCOUNTER_ID := "husk_fight"
const TUNING_PATH := "res://data/tuning/tuning.tres"
const VISUALS_PATH := "res://data/presentation/combat_visuals.tres"
const EXPLORE_VISUALS_PATH := "res://data/presentation/explore_visuals.tres"
const RUN_PATH := "res://data/runs/rotten_road.tres"
const COMBAT_SCENE := preload("res://scenes/combat.tscn")
## Autoplay: wait this long on an end screen or a run screen before going on (seconds).
const AUTOPLAY_RETURN_S: float = 1.0
## Autoplay: give up when no fight has started for this long in a zone (seconds).
const AUTOPLAY_ZONE_STUCK_S: float = 60.0
## Autoplay on the map: a rest is picked when someone is at or under this percent of max HP.
const AUTOPLAY_REST_BELOW_PERCENT: int = 60
const QUIT_AUDIO_RELEASE_S: float = 0.3

var _encounters: Array[EncounterData] = []
var _zones: Array[ZoneData] = []
var _encounter: EncounterData
var _tuning: Tuning
var _visuals: CombatVisuals
var _explore: ExploreVisuals
var _run_data: RunData
var _options: CombatOptions
var _combat: CombatController
var _select_index: int = 0
var _menu_item: StringName = MainMenu.NEW_RUN
## The menu-like screen shown now (main menu, settings, practice list, map, rest, shop, run end).
var _screen: Node
var _prompt: ConfirmPrompt
var _pause: PauseMenu
var _zone: ZoneController
var _run_bar: RunPartyBar
var _transition: ScreenTransition
## The run in progress (null outside a run).
var _run: RunState
## The fight that started in the zone: {index, opening}, or empty.
var _zone_fight: Dictionary = {}
var _busy: bool = false
var _zone_idle_s: float = 0.0
## Who plays and which heroes each player has (DESIGN.md 9.1).
var _players: PlayerRoster
## The device of the last button press (it becomes P1 on the players screen).
var _last_device: int = PlayerRoster.KEYBOARD


func _ready() -> void:
	_tuning = load(TUNING_PATH) as Tuning
	_visuals = load(VISUALS_PATH) as CombatVisuals
	_explore = load(EXPLORE_VISUALS_PATH) as ExploreVisuals
	_run_data = load(RUN_PATH) as RunData
	_encounters = FightSelect.load_encounters()
	_zones = FightSelect.load_zones()
	if _encounters.is_empty() or _tuning == null:
		push_error("Main: could not load the encounters in %s or %s" % [FightSelect.ENCOUNTER_DIR, TUNING_PATH])
		return
	if _run_data == null:
		push_error("Main: could not load the run %s" % RUN_PATH)
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
	# --players=N: pretend pads 0 to N-1 (only the bot presses them).
	_players = PlayerRoster.solo(_hero_names().size(), 0 if _options.players > 1 else PlayerRoster.KEYBOARD)
	for pad: int in range(1, _options.players):
		_players.join(pad)
	if _options.is_autoplay():
		print("Autoplay: %s%s players: %d" % [_options.autoplay_mode, " (quit on end)" if _options.quit_on_end else "",
				_players.player_count()])
	if _options.run:
		_new_run()
		return
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
		_show_main_menu()
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
	# Autoplay guard: a zone that never reaches a fight is stuck.
	if not _options.is_autoplay() or _zone == null or not _zone.is_inside_tree() or _zone.is_frozen():
		_zone_idle_s = 0.0
		return
	_zone_idle_s += delta
	if _zone_idle_s > AUTOPLAY_ZONE_STUCK_S:
		_zone_idle_s = 0.0
		_autoplay_fail("zone_stuck")


# --- screens ----------------------------------------------------------------------------------

## Frees whatever is shown (fight, zone, screen, prompt) and shows `screen`, if any.
func _show_screen(screen: Node) -> void:
	_free_combat()
	_free_zone()
	_free_screen()
	if screen != null:
		_screen = screen
		add_child(screen)


func _free_screen() -> void:
	_free_pause()
	if _screen != null:
		_screen.queue_free()
		_screen = null


## Fades to black, runs `build` (which shows the next thing), and fades back in.
func _fade_to(build: Callable) -> void:
	if _busy:
		return
	_busy = true
	await _transition.fade_out()
	build.call()
	await get_tree().process_frame
	await _transition.fade_in()
	_busy = false


func _show_main_menu() -> void:
	_run = null
	var menu := MainMenu.new()
	menu.name = "MainMenu"
	menu.setup(_menu_item)
	menu.chosen.connect(_on_menu_chosen)
	_show_screen(menu)


func _on_menu_chosen(item: StringName) -> void:
	_menu_item = item
	match item:
		MainMenu.NEW_RUN:
			_show_lobby.call_deferred(_fade_to.bind(_new_run))
		MainMenu.PRACTICE:
			_show_lobby.call_deferred(_show_select.call_deferred)
		MainMenu.SETTINGS:
			_show_settings.call_deferred()
		MainMenu.QUIT:
			_quit_game()


## The players screen; Start keeps its roster and calls `next`.
func _show_lobby(next: Callable) -> void:
	var lobby := LobbyScreen.new()
	lobby.name = "Lobby"
	lobby.setup(_hero_names(), _players, _last_device)
	lobby.started.connect(_on_lobby_started.bind(next))
	lobby.back.connect(_show_main_menu.call_deferred)
	_show_screen(lobby)


func _on_lobby_started(players: PlayerRoster, next: Callable) -> void:
	_players = players
	var names := PackedStringArray()
	for device: int in _players.devices:
		names.append(PlayerRoster.device_name(device))
	print("Players: %d (%s)" % [_players.player_count(), ", ".join(names)])
	next.call()


## The run's heroes in slot order (a roster covers these slots).
func _hero_names() -> Array[String]:
	var names: Array[String] = []
	if _run_data != null:
		for data: CharacterData in _run_data.party:
			names.append(data.display_name)
	return names


func _show_settings() -> void:
	var settings := SettingsScreen.new()
	settings.name = "Settings"
	settings.setup(_tuning, _visuals)
	settings.closed.connect(_show_main_menu.call_deferred)
	_show_screen(settings)


func _show_select() -> void:
	_run = null
	var select := FightSelect.new()
	select.name = "FightSelect"
	select.setup(_zones, _encounters, _select_index)
	select.chosen.connect(_on_fight_chosen)
	select.zone_chosen.connect(_on_zone_chosen)
	select.back.connect(_show_main_menu.call_deferred)
	_show_screen(select)


func _on_fight_chosen(encounter: EncounterData) -> void:
	_select_index = (_screen as FightSelect).selected_index()
	_encounter = encounter
	_zone_fight = {}
	_start_combat.call_deferred()


func _on_zone_chosen(zone: ZoneData) -> void:
	_select_index = (_screen as FightSelect).selected_index()
	_start_zone.call_deferred(zone)


# --- fights -----------------------------------------------------------------------------------

## Builds a fight: a practice fight, a zone's fight (the zone waits outside the tree), or the
## run's final fight.
func _start_combat() -> void:
	_free_combat()
	_free_screen()
	_combat = COMBAT_SCENE.instantiate() as CombatController
	var continue_to := Callable()
	if not _zone_fight.is_empty():
		_combat.configure(_encounter, _tuning, _visuals, _options, _zone.look(),
				_zone_fight.opening as CombatSetup.Opening, true)
		continue_to = _on_zone_return_requested
	elif _run != null:
		_combat.configure(_encounter, _tuning, _visuals, _options, _run_data.final_look)
		continue_to = _on_run_fight_over
	else:
		var opening := CombatSetup.Opening.FIRST_STRIKE if _options.first_strike else CombatSetup.Opening.NORMAL
		_combat.configure(_encounter, _tuning, _visuals, _options, null, opening)
	if _run != null:
		_combat.configure_run(_run)
	_combat.configure_players(_players)
	if continue_to.is_valid():
		_combat.continue_requested.connect(continue_to)
		if _options.is_autoplay():
			_combat.combat_finished.connect(_autoplay_continue.bind(continue_to))
	_combat.pause_reached.connect(_open_pause)
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
	_show_screen(null)
	_zone_fight = {}
	_zone = ZoneController.new()
	_zone.name = "Zone"
	_zone.configure(zone, _tuning, _visuals, _explore, _run != null)
	_zone.configure_players(_players)
	_zone.encounter_started.connect(_on_encounter_started)
	_zone.cleared.connect(_on_zone_cleared)
	add_child(_zone)
	if _run != null:
		var layer := CanvasLayer.new()
		layer.name = "RunBar"
		layer.layer = 11
		_zone.add_child(layer)
		_run_bar = RunPartyBar.new()
		_run_bar.position = Vector2(24.0, 24.0)
		layer.add_child(_run_bar)
		_run_bar.setup(_run)
	if _options.is_autoplay():
		var bot := ZoneAutoplay.new()
		bot.name = "ZoneAutoplay"
		_zone.add_child(bot)
		bot.setup(_zone, _tuning, _options.autoplay_mode, _run != null)


func _free_zone() -> void:
	if _zone != null:
		if _zone.is_inside_tree():
			remove_child(_zone)
		_zone.queue_free()
		_zone = null
		_run_bar = null


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


## The zone fight's end screen was left: carry the run's HP and gold, then fade back to the zone
## (or to the run's end after a defeat).
func _on_zone_return_requested(result: String) -> void:
	if _busy or _zone == null:
		return
	_busy = true
	if _run != null:
		_run.finish_fight(result, _combat.party_hp(), _encounter)
		if _run.is_over():
			await _transition.fade_out()
			_show_run_end()
			await get_tree().process_frame
			await _transition.fade_in()
			_busy = false
			return
	await _transition.fade_out()
	_free_combat()
	_zone_fight = {}
	add_child(_zone)
	_zone.resume(result)
	if _run_bar != null:
		_run_bar.refresh(_run)
	await get_tree().process_frame
	await _transition.fade_in()
	_busy = false
	if _run == null and result != "victory" and _options.is_autoplay():
		print("AUTOPLAY_RESULT zone_defeat fights=%d first_strikes=%d" % [_zone.fights_started(), _zone.first_strikes()])
		_autoplay_quit()
	elif _run != null and _zone.is_cleared():
		# Let ZONE CLEAR read, then the guard's loot.
		await get_tree().create_timer(float(_explore.zone_title_ms) / 1000.0).timeout
		_fade_to(_show_loot)


func _on_zone_cleared() -> void:
	if _run != null or not _options.is_autoplay():
		return
	print("AUTOPLAY_RESULT zone_clear fights=%d first_strikes=%d" % [_zone.fights_started(), _zone.first_strikes()])
	_autoplay_quit()


# --- the run ----------------------------------------------------------------------------------

func _new_run() -> void:
	if _run_data == null:
		push_error("Main: no run data, cannot start a run")
		_autoplay_fail("no run data")
		_show_main_menu()
		return
	var run_seed := _options.seed_override if _options.seed_override >= 0 else randi_range(1, 2147483646)
	_run = RunState.begin(_run_data, _tuning, run_seed)
	print("Run seed: %d  stops: %d" % [run_seed, _run.map.row_count()])
	_show_map()


func _show_map() -> void:
	if _run == null:
		return
	var map := MapScreen.new()
	map.name = "Map"
	map.setup(_run)
	map.stop_chosen.connect(_on_stop_chosen)
	map.quit_requested.connect(_open_pause)
	map.party_requested.connect(_show_party.bind("", true))
	_show_screen(map)
	if _options.is_autoplay():
		_autoplay_map.call_deferred(map)


func _on_stop_chosen(id: int) -> void:
	if _busy or not _run.go(id):
		return
	var stop := _run.current()
	print("Run stop %d: %s %s" % [_run.path.size(), RunMap.TYPE_NAMES[int(stop.type)], MapScreen.stop_name(_run, stop)])
	match int(stop.type):
		RunMap.StopType.ZONE:
			_fade_to(_start_zone.bind(_run.zone_of(stop)))
		RunMap.StopType.REST:
			_fade_to(_show_rest)
		RunMap.StopType.SHOP:
			_fade_to(_show_shop)
		RunMap.StopType.FINAL:
			_start_final_fight()


func _start_final_fight() -> void:
	_busy = true
	_encounter = _run_data.final_encounter
	_zone_fight = {}
	await _transition.swirl_out()
	_start_combat()
	await get_tree().process_frame
	await _transition.fade_in()
	_busy = false


## The final fight's end screen was left: the run is over either way.
func _on_run_fight_over(result: String) -> void:
	if _busy or _run == null:
		return
	_run.finish_fight(result, _combat.party_hp(), _encounter)
	_fade_to(_show_run_end)


func _show_rest() -> void:
	var rest := RestScreen.new()
	rest.name = "Rest"
	rest.setup(_run)
	rest.done.connect(_fade_to.bind(_show_map))
	_show_screen(rest)
	if _options.is_autoplay():
		_autoplay_rest.call_deferred(rest)


func _show_shop() -> void:
	var shop := ShopScreen.new()
	shop.name = "Shop"
	shop.setup(_run, _run.shop_gear(_run.at))
	shop.done.connect(_fade_to.bind(_show_map))
	_show_screen(shop)
	if _options.is_autoplay():
		_autoplay_shop.call_deferred(shop)


## The guard's loot (DESIGN.md 8): pick one, then the party screen to put it on.
func _show_loot() -> void:
	var loot := LootScreen.new()
	loot.name = "Loot"
	loot.setup(_run.loot_choices(_run.at))
	loot.chosen.connect(_on_loot_chosen)
	_show_screen(loot)
	if _options.is_autoplay():
		_autoplay_loot.call_deferred(loot)


func _on_loot_chosen(item: GearData) -> void:
	if item != null and _run.take(item):
		_show_party.call_deferred("Found: %s. Put it on someone (or keep it in the bag)." % item.display_name, false)
	else:
		_fade_to(_show_map)


## The party screen: gear and stats. From the map it closes back to the map at once; after loot
## it fades on to the map.
func _show_party(note: String, from_map: bool) -> void:
	var party := PartyScreen.new()
	party.name = "Party"
	party.setup(_run, note)
	if from_map:
		party.done.connect(_show_map.call_deferred)
	else:
		party.done.connect(_fade_to.bind(_show_map))
	_show_screen(party)
	if _options.is_autoplay():
		_autoplay_party.call_deferred(party)


func _show_run_end() -> void:
	var end := RunEndScreen.new()
	end.name = "RunEnd"
	end.setup(_run, _visuals.end_input_guard_ms)
	end.done.connect(_fade_to.bind(_show_main_menu))
	_show_screen(end)
	if _options.is_autoplay():
		print("AUTOPLAY_RESULT run_%s stops=%d fights=%d level=%d gear=%d gold=%d seed=%d" % [_run.result, _run.path.size(),
				_run.fights_won, _run.level, _run.bag.size() + _worn_count(), _run.gold_earned, _run.run_seed])
		_autoplay_quit()


# --- pause ------------------------------------------------------------------------------------

## Pause (Esc / Menu, DESIGN.md 7.5) over a fight, a zone or the run map. Main reads it before the
## fight's own input, so Esc never reaches the action menu as "back".
func _input(event: InputEvent) -> void:
	if (event is InputEventKey or event is InputEventJoypadButton) and event.is_pressed():
		_last_device = PlayerRoster.device_of(event)
	if _pause != null or _prompt != null or _busy or not event.is_action_pressed(&"pause", false, true):
		return
	if _combat != null and _combat.is_inside_tree():
		# A fight pauses between moves; it calls back with pause_reached.
		if _combat.request_pause():
			get_viewport().set_input_as_handled()
	elif _zone != null and _zone.is_inside_tree() and not _zone.is_frozen():
		get_viewport().set_input_as_handled()
		_open_pause()
	elif _screen is MapScreen:
		get_viewport().set_input_as_handled()
		_open_pause()


func _open_pause() -> void:
	if _pause != null:
		return
	_hold_behind_overlay(true)
	_pause = PauseMenu.new()
	_pause.name = "Pause"
	if _run != null:
		_pause.setup("Abandon run", "The run is lost. Back to the main menu.")
	else:
		_pause.setup("Leave", "Back to the practice list.")
	_pause.resumed.connect(_on_pause_resumed)
	_pause.settings_requested.connect(_on_pause_settings)
	_pause.leave_requested.connect(_on_pause_leave)
	add_child(_pause)


func _on_pause_resumed() -> void:
	_free_pause()
	_hold_behind_overlay(false)
	if _combat != null and _combat.is_paused():
		_combat.resume_after_pause()


func _on_pause_settings() -> void:
	_pause.visible = false
	_pause.process_mode = Node.PROCESS_MODE_DISABLED
	var settings := SettingsScreen.new()
	settings.name = "PauseSettings"
	settings.layer = _pause.layer + 1
	settings.setup(_tuning, _visuals)
	settings.closed.connect(_on_pause_settings_closed.bind(settings))
	add_child(settings)


func _on_pause_settings_closed(settings: SettingsScreen) -> void:
	settings.queue_free()
	if _pause != null:
		_pause.visible = true
		_pause.process_mode = Node.PROCESS_MODE_INHERIT


## Abandon the run (asks first) or, in practice, leave for the practice list.
func _on_pause_leave() -> void:
	if _run == null:
		_free_pause()
		_show_select.call_deferred()
		return
	_pause.process_mode = Node.PROCESS_MODE_DISABLED
	_prompt = ConfirmPrompt.new()
	_prompt.name = "AbandonPrompt"
	_prompt.setup("Abandon this run?", "The run is lost. You go back to the main menu.", "Abandon run", "Keep playing")
	_prompt.answered.connect(_on_abandon_answered)
	add_child(_prompt)


func _on_abandon_answered(yes: bool) -> void:
	_prompt.queue_free()
	_prompt = null
	if yes:
		_free_pause()
		_fade_to(_show_main_menu)
	elif _pause != null:
		_pause.process_mode = Node.PROCESS_MODE_INHERIT


## Stops (or restarts) the fight, zone or screen under an overlay: no movement, timers or input.
func _hold_behind_overlay(held: bool) -> void:
	var mode := Node.PROCESS_MODE_DISABLED if held else Node.PROCESS_MODE_INHERIT
	for node: Node in [_combat, _zone, _screen]:
		if node != null:
			node.process_mode = mode


func _free_pause() -> void:
	if _prompt != null:
		_prompt.queue_free()
		_prompt = null
	if _pause != null:
		_pause.queue_free()
		_pause = null
	for child: Node in get_children():
		if child is SettingsScreen and child != _screen:
			child.queue_free()


# --- autoplay ---------------------------------------------------------------------------------

## Autoplay: waits on the end screen, then goes on the way the player would.
func _autoplay_continue(result: String, continue_to: Callable) -> void:
	await get_tree().create_timer(AUTOPLAY_RETURN_S).timeout
	continue_to.call(result)


## Autoplay on the map: a shop when there is gold to spend, a rest when someone is hurt, else a
## zone (so a run tries every kind of stop).
func _autoplay_map(map: MapScreen) -> void:
	await get_tree().create_timer(AUTOPLAY_RETURN_S).timeout
	if not is_instance_valid(map) or not map.is_inside_tree() or _run == null:
		return
	var pick := -1
	var cheapest := 1 << 30
	for item: ShopItemData in _run_data.shop_items:
		cheapest = mini(cheapest, item.price)
	var hurt := false
	for slot: int in _run.party_size():
		hurt = hurt or _run.hp[slot] * 100 <= _run.max_hp(slot) * AUTOPLAY_REST_BELOW_PERCENT
	for wanted: int in [RunMap.StopType.SHOP if _run.gold >= cheapest else -1,
			RunMap.StopType.REST if hurt else -1, RunMap.StopType.ZONE]:
		for id: int in map.choices():
			if pick < 0 and int(_run.map.stop(id).type) == wanted:
				pick = id
	if pick < 0 and not map.choices().is_empty():
		pick = map.choices()[0]
	if pick < 0:
		_autoplay_fail("map_no_choice")
		return
	map.choose(pick)


func _autoplay_rest(rest: RestScreen) -> void:
	await get_tree().create_timer(AUTOPLAY_RETURN_S).timeout
	if not is_instance_valid(rest):
		return
	rest.rest_now()
	await get_tree().create_timer(AUTOPLAY_RETURN_S).timeout
	if is_instance_valid(rest):
		rest.leave()


## Autoplay in a shop: buys what it can afford, each for whoever has the least HP.
func _autoplay_shop(shop: ShopScreen) -> void:
	await get_tree().create_timer(AUTOPLAY_RETURN_S).timeout
	if not is_instance_valid(shop):
		return
	for i: int in shop.count():
		if shop.can_buy(i):
			var slot := 0
			for s: int in _run.party_size():
				if _run.hp[s] * _run.max_hp(slot) < _run.hp[slot] * _run.max_hp(s):
					slot = s
			shop.buy(i, slot)
	print("Run shop: gold left %d, bag %d" % [_run.gold, _run.bag.size()])
	await get_tree().create_timer(AUTOPLAY_RETURN_S).timeout
	if is_instance_valid(shop):
		shop.leave()


## Autoplay after a guard: takes the first item.
func _autoplay_loot(loot: LootScreen) -> void:
	await get_tree().create_timer(AUTOPLAY_RETURN_S).timeout
	if is_instance_valid(loot):
		loot.take(0)


## Autoplay on the party screen: puts every bag item on whoever has the most free slots.
func _autoplay_party(party: PartyScreen) -> void:
	await get_tree().create_timer(AUTOPLAY_RETURN_S).timeout
	if not is_instance_valid(party) or _run == null:
		return
	for item: GearData in _run.bag.duplicate():
		var best := -1
		var free := 0
		for slot: int in _run.party_size():
			var empty := _run.gear[slot].count(null)
			if empty > free:
				best = slot
				free = empty
		if best >= 0:
			_run.equip(best, _run.free_gear_slot(best), item)
			print("Run gear: %s on %s" % [item.id, _run.data.party[best].id])
	if is_instance_valid(party):
		party.done.emit()


func _autoplay_fail(reason: String) -> void:
	if not _options.is_autoplay():
		return
	print("AUTOPLAY_ERROR " + reason)
	get_tree().quit(1)


func _autoplay_quit() -> void:
	if not _options.quit_on_end:
		return
	await get_tree().create_timer(AUTOPLAY_RETURN_S).timeout
	_quit_game()


func _quit_game() -> void:
	Sfx.stop_all()
	await get_tree().create_timer(QUIT_AUDIO_RELEASE_S, true, false, true).timeout
	get_tree().quit(0)


## Gear the party wears (autoplay result line).
func _worn_count() -> int:
	var worn := 0
	for slots: Array in _run.gear:
		worn += slots.size() - slots.count(null)
	return worn
