extends Node
## Entry point (run/main_scene). Shows the main menu (DESIGN.md 7.5): a new run (DESIGN.md 8),
## practice (the zone and fight list), settings, quit. New Run and Practice open the players screen
## first (co-op, DESIGN.md 9.1); its roster goes to every fight and zone. In a run the map screen
## leads to the stops: zones, rests, shops and the final fight; RunState carries HP and gold from stop to stop.
## A zone (DESIGN.md 7.4) hands a fight over with encounter_started: the screen swirls into the
## fight, the zone waits outside the tree, and after the fight the screen fades back to the zone.
## Online (DESIGN.md 9.2) the host's machine runs the run exactly as offline and tells the others
## what to show: every screen ("screen" messages with the run's state), the zone positions, the
## fights' event batches. The others (clients) only show what arrives, never decide anything about
## the run: on run screens they watch while the host chooses. Their own heroes' fight choices and
## presses go to the host. Messages a client gets while a transition plays wait for it to end.
## R / "fight again" frees a practice fight and starts the same one again; Cancel on a practice
## fight's end screen goes back to the practice list. The options (and the F1 statistics they
## hold) survive restarts.
##
## User arguments (after "--"): --autoplay[=perfect|miss|mash], --quit-on-end, --seed=N,
## --encounter=ID (start that fight directly; autoplay without it, --zone or --run starts
## DEFAULT_ENCOUNTER_ID), --zone=ID (start in that zone), --first-strike (with --encounter),
## --run (start a new run at once; the seed also picks the map), --players=N (co-op with N pretend
## pads, for the bot), --host=N (host online and start a run once N players are in), --join=ADDRESS
## (join that host).

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
## Online client: the "host is choosing" line over watched run screens.
const WATCH_TEXT_SIZE: int = 26
const WATCH_MARGIN_PX: float = 24.0

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
## Online: the seed of the next fight (the host picks it), client messages waiting for the current
## transition, combat batches that arrived before their fight was built, the last screen the host
## sent (rebuilt when the run changes), and the run state the host sent last.
var _net_seed: int = -1
var _net_queue: Array[Dictionary] = []
var _combat_inbox: Array[Dictionary] = []
var _net_screen: Dictionary = {}
var _sent_run: Dictionary = {}
var _zone_send_s: float = 0.0
## Online client: "the host is choosing" over the run screens.
var _watch_layer: CanvasLayer
## Shown on the main menu next time (why an online game ended).
var _notice: String = ""
## Bumped when an online game ends, so a transition that was under way stops after its fade.
var _flow_gen: int = 0
## Client: combat batches go straight to the fight (else they wait in _combat_inbox); the message
## pump holds while a zone plays a fight's opening; the run's end arrived (the host may go now).
var _combat_accepts: bool = false
var _net_hold: bool = false
var _client_done: bool = false


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
	_build_watch_layer()
	Net.message_received.connect(_on_net_message)
	Net.peer_joined.connect(_on_net_peer_joined)
	Net.peer_left.connect(_on_net_peer_left)
	Net.host_lost.connect(_on_net_host_lost)
	Net.refused.connect(_on_net_refused)
	_options = CombatOptions.from_args(OS.get_cmdline_user_args(), _tuning)
	# --players=N: pretend pads 0 to N-1 (only the bot presses them).
	_players = PlayerRoster.solo(_hero_names().size(), 0 if _options.players > 1 else PlayerRoster.KEYBOARD)
	for pad: int in range(1, _options.players):
		_players.join(pad)
	if _options.is_autoplay():
		print("Autoplay: %s%s players: %d" % [_options.autoplay_mode, " (quit on end)" if _options.quit_on_end else "",
				_players.player_count()])
	if _options.host_players > 0:
		_host_online()
		return
	if not _options.join_address.is_empty():
		_show_join()
		_on_join_requested(_options.join_address)
		if _options.leave_after_s > 0:
			_autoplay_leave_later()
		return
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
	if Net.is_host():
		_net_host_tick(delta)
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
	_watch_layer.visible = Net.is_client() and _is_run_screen(screen)


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
	var gen := _flow_gen
	await _transition.fade_out()
	if gen != _flow_gen:
		_transition.fade_in()
		_end_busy()
		return
	build.call()
	await get_tree().process_frame
	await _transition.fade_in()
	_end_busy()


## A transition is over: messages that waited for it go on (online client).
func _end_busy() -> void:
	_busy = false
	_pump_net.call_deferred()


func _show_main_menu() -> void:
	_run = null
	if Net.is_online():
		_leave_online()
	var menu := MainMenu.new()
	menu.name = "MainMenu"
	menu.setup(_menu_item, _notice)
	_notice = ""
	menu.chosen.connect(_on_menu_chosen)
	_show_screen(menu)


func _on_menu_chosen(item: StringName) -> void:
	_menu_item = item
	match item:
		MainMenu.NEW_RUN:
			_show_lobby.call_deferred(_fade_to.bind(_new_run))
		MainMenu.HOST_ONLINE:
			_host_online.call_deferred()
		MainMenu.JOIN_ONLINE:
			_show_join.call_deferred()
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
	if Net.is_host():
		_combat.configure_online(CombatController.NetMode.HOST, _net_seed)
	elif Net.is_client():
		_combat.configure_online(CombatController.NetMode.CLIENT, _net_seed)
		# Only the host goes on after a fight; the next screen comes from it.
		continue_to = Callable()
	if continue_to.is_valid():
		_combat.continue_requested.connect(continue_to)
		if _options.is_autoplay():
			_combat.combat_finished.connect(_autoplay_continue.bind(continue_to))
	_combat.pause_reached.connect(_open_pause)
	_combat.restart_requested.connect(_on_restart_requested)
	_combat.select_requested.connect(_show_select.call_deferred)
	add_child(_combat)
	if Net.is_client():
		_combat_accepts = true
		var waiting := _combat_inbox.duplicate()
		_combat_inbox.clear()
		for batch: Dictionary in waiting:
			_combat.receive_batch(batch)


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
	if Net.is_client():
		_zone.configure_remote()
	_send_screen({"name": "zone", "zone": zone.id})
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
	if _options.is_autoplay() and not Net.is_client():
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
	_net_hold = false
	if _busy:
		return
	_busy = true
	_zone_fight = {"index": index, "opening": opening}
	_encounter = _zone.encounter_of(index)
	if Net.is_host():
		_net_seed = randi_range(1, 2147483646)
		Net.broadcast("screen", {"name": "zone_fight", "index": index, "opening": int(opening), "seed": _net_seed})
	var gen := _flow_gen
	await _transition.swirl_out()
	if gen != _flow_gen or _zone == null:
		_transition.fade_in()
		_end_busy()
		return
	remove_child(_zone)
	_start_combat()
	await get_tree().process_frame
	await _transition.fade_in()
	_end_busy()


## The zone fight's end screen was left: carry the run's HP and gold, then fade back to the zone
## (or to the run's end after a defeat).
func _on_zone_return_requested(result: String) -> void:
	if _busy or _zone == null:
		return
	_busy = true
	if _run != null and not Net.is_client():
		_run.finish_fight(result, _combat.party_hp(), _encounter)
		_send_screen({"name": "zone_back", "result": result})
		if _run.is_over():
			# The run's end screen follows (online, the host sends it).
			await _transition.fade_out()
			_show_run_end()
			await get_tree().process_frame
			await _transition.fade_in()
			_end_busy()
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
	_end_busy()
	if _run == null and result != "victory" and _options.is_autoplay():
		print("AUTOPLAY_RESULT zone_defeat fights=%d first_strikes=%d" % [_zone.fights_started(), _zone.first_strikes()])
		_autoplay_quit()
	elif _run != null and _zone.is_cleared() and not Net.is_client():
		# Let ZONE CLEAR read, then the guard's loot (online, the host sends it).
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
	if Net.is_host():
		Net.broadcast("run_start", {"seed": run_seed, "roster": _players.to_dict()})
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
	_send_screen({"name": "map"})
	if _options.is_autoplay() and not Net.is_client():
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
	if Net.is_host():
		_net_seed = randi_range(1, 2147483646)
		_send_screen({"name": "final_fight", "seed": _net_seed})
	await _transition.swirl_out()
	_start_combat()
	await get_tree().process_frame
	await _transition.fade_in()
	_end_busy()


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
	_send_screen({"name": "rest"})
	if _options.is_autoplay() and not Net.is_client():
		_autoplay_rest.call_deferred(rest)


func _show_shop(gear: Array[GearData] = []) -> void:
	var shop := ShopScreen.new()
	shop.name = "Shop"
	if not Net.is_client():
		gear = _run.shop_gear(_run.at)
	shop.setup(_run, gear)
	shop.done.connect(_fade_to.bind(_show_map))
	_show_screen(shop)
	_send_screen({"name": "shop", "gear": _gear_ids(gear)})
	if _options.is_autoplay() and not Net.is_client():
		_autoplay_shop.call_deferred(shop)


## The guard's loot (DESIGN.md 8): pick one, then the party screen to put it on.
func _show_loot(gear: Array[GearData] = []) -> void:
	var loot := LootScreen.new()
	loot.name = "Loot"
	if not Net.is_client():
		gear = _run.loot_choices(_run.at)
	loot.setup(gear)
	loot.chosen.connect(_on_loot_chosen)
	_show_screen(loot)
	_send_screen({"name": "loot", "gear": _gear_ids(gear)})
	if _options.is_autoplay() and not Net.is_client():
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
	_send_screen({"name": "party", "note": note})
	if _options.is_autoplay() and not Net.is_client():
		_autoplay_party.call_deferred(party)


func _show_run_end() -> void:
	var end := RunEndScreen.new()
	end.name = "RunEnd"
	end.setup(_run, _visuals.end_input_guard_ms)
	end.done.connect(_fade_to.bind(_show_main_menu))
	_show_screen(end)
	_send_screen({"name": "run_end"})
	_client_done = Net.is_client()
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
	var pause := event.is_action_pressed(&"pause", false, true)
	# Online client on a run screen: the host chooses; only pause (to leave) works here.
	if Net.is_client() and _is_run_screen(_screen) and _pause == null and _prompt == null and not pause:
		if not event is InputEventMouseMotion:
			get_viewport().set_input_as_handled()
		return
	if _pause != null or _prompt != null or _busy or not pause:
		return
	if Net.is_online() and (_combat != null or _zone != null or _is_run_screen(_screen)):
		# Online nothing stops for a pause menu: it opens over the game, which goes on.
		get_viewport().set_input_as_handled()
		_open_pause()
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
	if not Net.is_online():
		_hold_behind_overlay(true)
	elif _zone != null:
		_zone.input_held = true
	_pause = PauseMenu.new()
	_pause.name = "Pause"
	if Net.is_host():
		_pause.setup("End the game", "The run ends for everyone.")
	elif Net.is_client():
		_pause.setup("Leave the game", "You leave; the others play on.")
	elif _run != null:
		_pause.setup("Abandon run", "The run is lost. Back to the main menu.")
	else:
		_pause.setup("Leave", "Back to the practice list.")
	_pause.resumed.connect(_on_pause_resumed)
	_pause.settings_requested.connect(_on_pause_settings)
	_pause.leave_requested.connect(_on_pause_leave)
	add_child(_pause)


func _on_pause_resumed() -> void:
	_free_pause()
	if _zone != null:
		_zone.input_held = false
	if Net.is_online():
		return
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
	if Net.is_online():
		_pause.process_mode = Node.PROCESS_MODE_DISABLED
		_prompt = ConfirmPrompt.new()
		_prompt.name = "LeavePrompt"
		if Net.is_host():
			_prompt.setup("End the game for everyone?", "The run is lost. Everyone goes back to the main menu.",
					"End the game", "Keep playing")
		else:
			_prompt.setup("Leave the game?", "You go back to the main menu. Your heroes go to the host.",
					"Leave", "Keep playing")
		_prompt.answered.connect(_on_abandon_answered)
		add_child(_prompt)
		return
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


# --- online (DESIGN.md 9.2) -------------------------------------------------------------------

## Host Online: listen, and show the players screen with the address friends type in.
func _host_online() -> void:
	var err := Net.host()
	if err != OK:
		_notice = "Could not host (error %d). Is another game already hosting on this PC?" % err
		_autoplay_fail("host_failed")
		_show_main_menu()
		return
	_players = PlayerRoster.online(_hero_names().size(), NetSession.HOST_PEER, NetSession.HOST_PEER)
	var lobby := LobbyScreen.new()
	lobby.name = "Lobby"
	lobby.setup_online(_hero_names(), _players, true, NetSession.local_addresses(), _tuning.net_port)
	lobby.roster_changed.connect(_on_online_roster_changed)
	lobby.started.connect(_on_online_started)
	lobby.back.connect(_show_main_menu.call_deferred)
	_show_screen(lobby)
	print("Hosting on port %d: %s" % [_tuning.net_port, ", ".join(NetSession.local_addresses())])


func _on_online_roster_changed(players: PlayerRoster) -> void:
	_players = players
	Net.broadcast("lobby", {"roster": players.to_dict()})
	if _options.host_players > 0 and players.player_count() >= _options.host_players:
		_autoplay_start_online()


## The host pressed Start: nobody else can join now; the run begins (the clients follow).
func _on_online_started(players: PlayerRoster) -> void:
	if _busy or not _screen is LobbyScreen:
		return
	_players = players
	Net.closed = true
	print("Players: %d online" % players.player_count())
	_fade_to(_new_run)


func _show_join() -> void:
	var join := JoinScreen.new()
	join.name = "Join"
	join.setup(PlayerSettings.join_address())
	join.connect_requested.connect(_on_join_requested)
	join.back.connect(_show_main_menu.call_deferred)
	_show_screen(join)


func _on_join_requested(address: String) -> void:
	if not _options.is_autoplay():
		PlayerSettings.set_join_address(address)
	var err := Net.join(address)
	if err != OK and _screen is JoinScreen:
		(_screen as JoinScreen).show_problem("Could not start connecting (error %d)." % err)


func _on_net_peer_joined(peer: int) -> void:
	if Net.is_host():
		if not _screen is LobbyScreen or not (_screen as LobbyScreen).add_peer(peer):
			Net.kick(peer)
		return
	# Welcomed by the host: wait on the players screen for its roster and its Start.
	_players = PlayerRoster.online(_hero_names().size(), NetSession.HOST_PEER, peer)
	var lobby := LobbyScreen.new()
	lobby.name = "Lobby"
	lobby.setup_online(_hero_names(), _players, false, [] as Array[String], _tuning.net_port)
	lobby.back.connect(_show_main_menu.call_deferred)
	_show_screen(lobby)


## Host: a client left. Before the run it just leaves the list; during the run its heroes go to
## the host (and the others are told).
func _on_net_peer_left(peer: int) -> void:
	if _run == null and _screen is LobbyScreen:
		(_screen as LobbyScreen).remove_peer(peer)
		return
	if _players.drop_peer(peer):
		print("Player left: peer %d" % peer)
		Net.broadcast("roster", {"roster": _players.to_dict()})
		if _combat != null:
			_combat.update_players(_players, peer)
		if _zone != null:
			_zone.configure_players(_players)


func _on_net_host_lost() -> void:
	if not _client_done:
		_autoplay_fail("host_lost")
	_end_online("The run is over." if _client_done else "The host left the game.")


func _on_net_refused(reason: String) -> void:
	_autoplay_fail("refused " + reason)
	if _screen is JoinScreen:
		(_screen as JoinScreen).show_problem(reason)
	else:
		_end_online(reason)


## This machine's online game is over: back to the main menu with a note.
func _end_online(notice: String) -> void:
	_leave_online()
	_notice = notice
	_free_pause()
	_busy = false
	_show_main_menu.call_deferred()


## Closes the connection and forgets everything that was waiting.
func _leave_online() -> void:
	_flow_gen += 1
	_net_queue.clear()
	_combat_inbox.clear()
	_combat_accepts = false
	_net_hold = false
	_net_screen = {}
	_sent_run = {}
	Net.leave()
	_players = PlayerRoster.solo(_hero_names().size())


func _on_net_message(from_peer: int, kind: String, payload: Dictionary) -> void:
	if Net.is_host():
		match kind:
			"cmd":
				if _combat != null and _combat.is_inside_tree() and payload.get("command") is Dictionary:
					_combat.receive_command(from_peer, payload.command as Dictionary)
			"ack":
				if _combat != null:
					_combat.receive_ack(from_peer, int(payload.get("seq", -1)))
		return
	match kind:
		"combat":
			if _combat_accepts and _combat != null:
				_combat.receive_batch(payload)
			else:
				_combat_inbox.append(payload)
		"zone":
			if _zone != null and _zone.is_inside_tree():
				_zone.apply_snapshot(payload)
		"lobby":
			var roster := PlayerRoster.from_dict(payload.get("roster", {}) as Dictionary, Net.my_peer())
			if roster != null and _screen is LobbyScreen:
				_players = roster
				(_screen as LobbyScreen).set_roster(roster)
		_:
			if kind == "screen" and String(payload.get("name", "")) in ["zone_fight", "final_fight"]:
				# Batches from here on belong to the next fight.
				_combat_accepts = false
				_combat_inbox.clear()
			_net_queue.append({"kind": kind, "payload": payload})
			_pump_net()


## Client: handles the host's messages in order, each after the transition the last one started.
func _pump_net() -> void:
	while not _busy and not _net_hold and not _net_queue.is_empty() and Net.is_client():
		var m: Dictionary = _net_queue.pop_front()
		_client_message(String(m.kind), m.payload as Dictionary)


func _client_message(kind: String, p: Dictionary) -> void:
	match kind:
		"run_start":
			var roster := PlayerRoster.from_dict(p.get("roster", {}) as Dictionary, Net.my_peer())
			if roster != null:
				_players = roster
			_run = RunState.begin(_run_data, _tuning, int(p.get("seed", 1)))
		"roster":
			var roster := PlayerRoster.from_dict(p.get("roster", {}) as Dictionary, Net.my_peer())
			if roster != null:
				_players = roster
				if _combat != null:
					_combat.update_players(_players)
		"run":
			_apply_run(p)
			_rebuild_watched_screen()
		"menu":
			_client_done = true
			_end_online("The host ended the game.")
		"screen":
			_apply_run(p)
			_client_screen(p)


## Client: shows the screen the host is on.
func _client_screen(p: Dictionary) -> void:
	var name := String(p.get("name", ""))
	if _run == null and name != "menu":
		return
	match name:
		"map", "rest", "shop", "loot", "party", "run_end":
			_net_screen = p
			_fade_to(_watched_screen_builder(p))
		"zone":
			var zone := _zone_by_id(String(p.get("zone", "")))
			if zone != null:
				_fade_to(_start_zone.bind(zone))
		"zone_fight":
			_net_seed = int(p.get("seed", 1))
			if _zone != null and _zone.is_inside_tree():
				# The pump waits until the fight starts (the zone plays its short opening first).
				_net_hold = true
				_zone.begin_remote(int(p.get("index", -1)), int(p.get("opening", 0)) as CombatSetup.Opening)
		"final_fight":
			_net_seed = int(p.get("seed", 1))
			_start_final_fight()
		"zone_back":
			# After a lost run the host sends the run's end next instead.
			if not _run.is_over():
				_on_zone_return_requested(String(p.get("result", "")))


## Client: the function that builds a watched run screen from the host's message.
func _watched_screen_builder(p: Dictionary) -> Callable:
	match String(p.get("name", "")):
		"rest":
			return _show_rest
		"shop":
			return _show_shop.bind(_gear_from_ids(p.get("gear", []) as Array))
		"loot":
			return _show_loot.bind(_gear_from_ids(p.get("gear", []) as Array))
		"party":
			return _show_party.bind(String(p.get("note", "")), true)
		"run_end":
			return _show_run_end
	return _show_map


## Client: the run changed on the host (a purchase, gear): show the watched screen again.
func _rebuild_watched_screen() -> void:
	if _busy or _net_screen.is_empty() or not _is_run_screen(_screen) or _screen is RunEndScreen:
		return
	_watched_screen_builder(_net_screen).call()


func _apply_run(p: Dictionary) -> void:
	if _run == null or not p.get("run") is Dictionary:
		return
	if not _run.apply_dict(p.run as Dictionary):
		push_error("Main: the host's run state does not fit this run")
		_autoplay_fail("run_state_mismatch")


## Host: tells the clients which screen to show now, with the run's state.
func _send_screen(p: Dictionary) -> void:
	if not Net.is_host():
		return
	var message := p.duplicate()
	if _run != null:
		_sent_run = _run.to_dict()
		message["run"] = _sent_run
	Net.broadcast("screen", message)


## Host, every frame: run changes (purchases, gear, levels) and zone positions go out.
func _net_host_tick(delta: float) -> void:
	if _run != null and not _sent_run.is_empty():
		var now := _run.to_dict()
		if now != _sent_run:
			_sent_run = now
			Net.broadcast("run", {"run": now})
	if _zone != null and _zone.is_inside_tree() and not _zone.is_frozen():
		_zone_send_s += delta
		if _zone_send_s * float(_tuning.net_zone_send_hz) >= 1.0:
			_zone_send_s = 0.0
			Net.broadcast_fast("zone", _zone.net_snapshot())


func _is_run_screen(node: Node) -> bool:
	return node is MapScreen or node is ShopScreen or node is RestScreen or node is LootScreen \
			or node is PartyScreen or node is RunEndScreen


func _gear_ids(gear: Array[GearData]) -> Array:
	var ids: Array = []
	for item: GearData in gear:
		ids.append(item.id)
	return ids


func _gear_from_ids(ids: Array) -> Array[GearData]:
	var list: Array[GearData] = []
	if _run_data == null:
		return list
	for id: Variant in ids:
		for item: GearData in _run_data.gear:
			if item != null and item.id == str(id):
				list.append(item)
	return list


func _zone_by_id(id: String) -> ZoneData:
	if _run_data != null:
		for zone: ZoneData in _run_data.zones:
			if zone != null and zone.id == id:
				return zone
	return null


## "The host is choosing" over the run screens a client watches.
func _build_watch_layer() -> void:
	_watch_layer = CanvasLayer.new()
	_watch_layer.name = "Watching"
	_watch_layer.layer = 12
	_watch_layer.visible = false
	add_child(_watch_layer)
	# Top-left: the run screens keep their titles centred and their party bars in the middle.
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", HudStyle.panel())
	box.position = Vector2(WATCH_MARGIN_PX, WATCH_MARGIN_PX)
	_watch_layer.add_child(box)
	box.add_child(HudStyle.make_label("The host is choosing (P1)", WATCH_TEXT_SIZE, HudStyle.player_color(0)))


## Autoplay client (--leave-after=S): leaves the game mid-run, as a player quitting would.
func _autoplay_leave_later() -> void:
	await get_tree().create_timer(float(_options.leave_after_s)).timeout
	print("AUTOPLAY_LEFT after %d s" % _options.leave_after_s)
	_client_done = true
	Net.leave()
	_quit_game()


## Autoplay host (--host=N): everyone is in, start.
func _autoplay_start_online() -> void:
	await get_tree().create_timer(AUTOPLAY_RETURN_S).timeout
	if _screen is LobbyScreen:
		_on_online_started((_screen as LobbyScreen).roster())


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
