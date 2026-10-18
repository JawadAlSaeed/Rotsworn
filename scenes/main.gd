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
## (join that host), --continue (pick up the saved run), --save-path=PATH (keep that save elsewhere;
## the bot saves only with it), --oath=N (play the run at oath N; also unlocks it on the players
## screen).

const DEFAULT_ENCOUNTER_ID := "husk_fight"
const TUNING_PATH := "res://data/tuning/tuning.tres"
const VISUALS_PATH := "res://data/presentation/combat_visuals.tres"
const EXPLORE_VISUALS_PATH := "res://data/presentation/explore_visuals.tres"
const MAP_VISUALS_PATH := "res://data/presentation/map_visuals.tres"
const RUN_PATH := "res://data/runs/rotten_road.tres"
const MUSIC_PATH := "res://data/audio/music.tres"
const BOOT_PATH := "res://data/presentation/boot.tres"
const BRANDING_PATH := "res://data/branding/branding.tres"
const CREDITS_PATH := "res://data/branding/credits.tres"
const TIPS_PATH := "res://data/branding/tips.tres"
const TUTORIAL_PATH := "res://data/tutorial/tutorial.tres"
const COMBAT_SCENE := preload("res://scenes/combat.tscn")
## Autoplay: wait this long on an end screen or a run screen before going on (seconds).
const AUTOPLAY_RETURN_S: float = 1.0
## Autoplay: give up when no fight has started for this long in a zone (seconds).
const AUTOPLAY_ZONE_STUCK_S: float = 180.0
## Autoplay on the map: a rest is picked when someone is at or under this percent of max HP, or the
## party averages under AUTOPLAY_REST_AVERAGE_PERCENT. An elite stop is only taken while the party is
## healthy, like a champion in a zone (ZoneAutoplay). These are the bot's habits, not game rules.
const AUTOPLAY_REST_BELOW_PERCENT: int = 60
const AUTOPLAY_REST_AVERAGE_PERCENT: int = 75
const QUIT_AUDIO_RELEASE_S: float = 0.3
## Online client: the "host is choosing" line over watched run screens.
const WATCH_TEXT_SIZE: int = 26
const WATCH_MARGIN_PX: float = 24.0
## The backpack over a zone draws above the zone's HUD and run bar.
const ZONE_BACKPACK_LAYER: int = 20

var _encounters: Array[EncounterData] = []
var _zones: Array[ZoneData] = []
var _encounter: EncounterData
var _tuning: Tuning
var _visuals: CombatVisuals
var _explore: ExploreVisuals
var _map_look: MapVisuals
var _run_data: RunData
var _music: MusicSet
## The last fight's recap for the RUN OVER screen (card #191): FightRecap.to_dict() and the
## encounter's name. Online, every machine keeps its own copy of the same events.
var _last_recap: Dictionary = {}
var _last_recap_name: String = ""
var _branding: BrandingData
var _options: CombatOptions
var _combat: CombatController
var _select_index: int = 0
var _menu_item: StringName = MainMenu.NEW_RUN
## The menu-like screen shown now (main menu, settings, practice list, map, rest, shop, run end).
var _screen: Node
var _prompt: ConfirmPrompt
var _pause: PauseMenu
var _zone: ZoneController
## The display name of the zone being played (the journal's "met at").
var _zone_name: String = ""
var _run_bar: RunPartyBar
var _transition: ScreenTransition
## The run in progress (null outside a run).
var _run: RunState
## The oath the next run is played at (DESIGN.md 8.15): the players screen's pick, or --oath=N.
var _oath: int = 0
## The fight that started in the zone: {index, opening}, or empty.
var _zone_fight: Dictionary = {}
var _busy: bool = false
var _zone_idle_s: float = 0.0
## Who plays and which heroes each player has (DESIGN.md 9.1).
var _players: PlayerRoster
## The device of the last button press (it becomes P1 on the players screen).
var _last_device: int = PlayerRoster.KEYBOARD
## Local co-op: the card shown while a player's pad is gone, and whether the fight should pause
## for it as soon as the current move ends.
var _pad_overlay: PadLostOverlay
var _pad_pause_wanted: bool = false
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
## The backpack open over a zone (DESIGN.md 8.1), and the glinting spot whose find waits on it.
var _overlay: PartyScreen
## The tutorial while it runs (DESIGN.md 7.8), else null.
var _tutorial: TutorialRunner
var _spot_pending: int = -1
## What the zone fight's enemy drops (null: nothing).
var _drop: ItemData
## Where a run fight away from a zone takes place (the act's boss lair, an elite's zone).
var _fight_look: StageLook
## The zone air of the run fight being built (an elite's zone); empty for a boss.
var _fight_air: Array[ZoneAmbientData] = []
## Shown on the main menu next time (why an online game ended).
var _notice: String = ""
## Bumped when an online game ends, so a transition that was under way stops after its fade.
var _flow_gen: int = 0
## Client: combat batches go straight to the fight (else they wait in _combat_inbox); the message
## pump holds while a zone plays a fight's opening; the run's end arrived (the host may go now).
var _combat_accepts: bool = false
var _net_hold: bool = false
var _client_done: bool = false
## The main menu has had a choice made on it (until then a saved run is the cursor's first stop).
var _menu_used: bool = false
## The run as it was when the stop in progress was entered (the save holds it; Save & Quit inside a
## stop writes it again), and whether it is a stop's (else the map's).
var _checkpoint: Dictionary = {}
var _checkpoint_in_stop: bool = false
## DataHash.of_content(), worked out once (hashing data/ takes a moment).
var _content_fingerprint: String = ""
## The run whose last fight was decided (its save is gone and must not come back), and the oath
## its win opened (shown by the run end screen; the unlock is granted when the fight is decided).
var _decided_run: RunState = null
var _decided_unlock: int = 0
## The "saved by another build" notice was shown once this session (the file stays, so it must not
## nag on every visit to the main menu).
var _mismatch_told: bool = false


func _ready() -> void:
	HudStyle.load_fonts()
	_tuning = load(_tuning_path()) as Tuning
	_visuals = load(VISUALS_PATH) as CombatVisuals
	_explore = load(EXPLORE_VISUALS_PATH) as ExploreVisuals
	_map_look = load(MAP_VISUALS_PATH) as MapVisuals
	_run_data = load(RUN_PATH) as RunData
	_music = load(MUSIC_PATH) as MusicSet
	if _music == null:
		push_warning("Main: could not load %s, no music" % MUSIC_PATH)
		_music = MusicSet.new()
	_branding = load(BRANDING_PATH) as BrandingData
	if _branding == null:
		push_warning("Main: could not load %s, using built-in branding defaults" % BRANDING_PATH)
		_branding = BrandingData.new()
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
	if _map_look == null:
		push_warning("Main: could not load %s, using built-in map defaults" % MAP_VISUALS_PATH)
		_map_look = MapVisuals.new()
	_transition = ScreenTransition.new()
	_transition.name = "Transition"
	add_child(_transition)
	_transition.setup(_explore)
	var tips := load(TIPS_PATH) as TipSet
	if tips == null:
		push_warning("Main: could not load %s, no loading tips" % TIPS_PATH)
	else:
		_transition.setup_tips(tips, _branding.logo_path)
	_build_watch_layer()
	Net.message_received.connect(_on_net_message)
	Net.peer_joined.connect(_on_net_peer_joined)
	Net.peer_left.connect(_on_net_peer_left)
	Net.host_lost.connect(_on_net_host_lost)
	Net.refused.connect(_on_net_refused)
	_options = CombatOptions.from_args(DevArgs.user_args(), _tuning)
	if _options.shots_every_s > 0.0:
		var shooter := ScreenShooter.new()
		shooter.name = "Shots"
		add_child(shooter)
		shooter.setup(_options.shots_every_s, _options.screen if not _options.screen.is_empty() else "game")
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
	if _options.continue_run:
		_continue_run()
		return
	if not _options.screen.is_empty():
		_open_dev_screen(_options.screen)
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
		_show_intro()
		return
	for i: int in _encounters.size():
		if _encounters[i].id == wanted:
			_select_index = 1 + _zones.size() + i  # after the tutorial card and the zones
			_encounter = _encounters[i]
	if _encounter == null:
		push_error("Main: no encounter with id '%s'" % wanted)
		_autoplay_fail("unknown encounter %s" % wanted)
		return
	_start_combat()


## The tuning file: --tuning=PATH (dev tool, for balance checks with another set of numbers;
## a user:// or res:// path), else data/tuning/tuning.tres.
static func _tuning_path() -> String:
	for arg: String in DevArgs.user_args():
		if arg.begins_with("--tuning="):
			return arg.substr("--tuning=".length())
	return TUNING_PATH


## --screen=NAME (dev tool, for pictures of a screen).
func _open_dev_screen(screen_name: String) -> void:
	match screen_name:
		"settings":
			_show_settings()
		"players":
			_show_lobby(_show_select)
		"oaths":
			_show_lobby(_fade_to.bind(_new_run), true)
		"practice":
			_show_select()
		"title":
			_show_title()
		"credits":
			_show_credits()
		"journal":
			_show_journal()
		"party":
			_show_sample_backpack()
		"attributes":
			_show_sample_attributes()
		"heroes":
			_show_sample_attributes(false)
		"skills":
			_show_sample_skills()
		"tutorial":
			_start_tutorial()
		"map":
			_show_sample_map(2)
		"map_start":
			_show_sample_map(0)
		"map_act2":
			_show_sample_map(1, 1)
		"shop", "campfire", "event", "treasure":
			_show_sample_stop(screen_name)
		"calibration":
			_show_settings()
			(_screen as SettingsScreen).open_calibration()
		"controls":
			_show_settings()
			(_screen as SettingsScreen).open_section(SettingsScreen.Section.CONTROLS)
		_:
			_show_main_menu()


## --screen=map: a new run two stops in; map_start: before the first stop; map_act2: one stop into
## the second act (pictures of the map).
func _show_sample_map(stops: int, act: int = 0) -> void:
	_run = RunState.begin(_run_data, _tuning, 3)
	for i: int in act:
		_run.next_act()
	for i: int in stops:
		_run.go(_run.choices()[0])
	_show_map()


## --screen=shop|campfire|event|treasure: a run standing at such a stop, with gold and a few items
## (pictures of the phase 15 stop screens, DESIGN.md 8.7 to 8.11).
func _show_sample_stop(kind: String) -> void:
	_run = RunState.begin(_run_data, _tuning, 3)
	_run.gold = 180
	var items := _run.items_by_id()
	_run.add_item(items["salve"])
	_run.add_item(items["ember_stone"])
	_run.add_item(items["rotting_heart"])
	_run.hp[1] = CombatMath.percent(_run.max_hp(1), 50)
	var want := {"shop": RunMap.StopType.SHOP, "campfire": RunMap.StopType.REST, "event": RunMap.StopType.EVENT,
			"treasure": RunMap.StopType.TREASURE}[kind] as int
	for s: Dictionary in _run.map.stops:
		if int(s.type) == want:
			_run.at = int(s.id)
			_run.path.append(int(s.id))
			break
	if want == RunMap.StopType.EVENT:
		_run.events_seen.append(_run.event_of(_run.at).id)
	match kind:
		"shop":
			_show_shop()
		"campfire":
			_show_rest()
		"event":
			_show_event()
		"treasure":
			_show_treasure()


## --screen=party: a new run with some gear worn and a few items packed, the party screen open
## with a Golden Idol in hand (for pictures of the backpack).
func _show_sample_backpack() -> void:
	_run = RunState.begin(_run_data, _tuning, 3)
	var items := _run.items_by_id()
	_run.wear(0, 0, _run_data.gear[0])
	_run.wear(0, 1, _run_data.gear[1])
	_run.place_item(items["heartleaf"], 0, 0, 0)
	_run.place_item(items["ember_stone"], 1, 0, 0)
	_run.place_item(items["lodestone"], 2, 0, 0)
	_run.place_item(items["iron_stone"], 2, 2, 0)
	_run.place_item(items["salve"], 0, 1, 0, 1)
	_run.place_item(items["rotting_heart"], 0, 4, 0)
	_run.place_item(items["key"], 2, 4, 0)
	_run.place_item(items["bomb"], 3, 2, 0)
	_run.wear(1, 0, _run_data.gear[3])
	# Alder has levelled and has points to spend (the cards show "+N points", DESIGN.md 8.2).
	_run.add_xp(0, 200)
	_show_party("Found a Golden Idol. Where does it go?", true, {"item": items["golden_idol"]})


## --screen=attributes: a run where Alder and Brin have levelled (Brin's points half spent), the
## attributes screen open over the party screen (for pictures of it). --screen=heroes: the same
## run on the party screen itself.
func _show_sample_attributes(open: bool = true) -> void:
	_run = RunState.begin(_run_data, _tuning, 3)
	_run.add_xp(0, 400)
	_run.add_xp(1, 200)
	_run.set_attributes(1, [1, 2, 1, 0, 1])
	_run.wear(1, 0, _run_data.gear[3])
	_show_party("", true)
	if open:
		(_screen as PartyScreen).open_attributes()


## --screen=skills: the skills screen on a run where each hero has a sample tree made of their
## own skills, arranged as in the skill tree proposal (docs/proposals/skill_trees.html), with
## Alder at level 4 (for pictures; the shipped heroes have no tree yet).
func _show_sample_skills() -> void:
	var data := _run_data.duplicate() as RunData
	var party: Array[CharacterData] = []
	var layout := {
		"alder": [["Bulwark", ["guard"]], ["Bash", ["shield_bash"]], ["Retort", ["taunt", "riposte_stance", "payback"]]],
		"brin": [["Flurry", ["quick_cuts", "all_in"]], ["Cripple", ["hamstring", "rend"]], ["Shadow", ["feint_step"]]],
		"cass": [["Mending", ["mend"]], ["Light", ["reveal", "revive"]], ["Grace", ["pass_the_torch", "hasten"]]],
	}
	for c: CharacterData in _run_data.party:
		var hero := c.duplicate() as CharacterData
		var tree := SkillTreeData.new()
		for pair: Array in layout.get(c.id, []):
			var branch := SkillBranchData.new()
			branch.display_name = String(pair[0])
			for id: String in pair[1]:
				var ability := load("res://data/abilities/%s.tres" % id) as AbilityData
				if ability != null:
					branch.skills.append(ability)
			tree.branches.append(branch)
		hero.skill_tree = tree
		party.append(hero)
	data.party = party
	_run = RunState.begin(data, _tuning, 3)
	_run.add_xp(0, 400)
	_run.unlock(0, "riposte_stance")
	_show_party("", true)
	(_screen as PartyScreen).open_skills()


## The studio intro when the game starts, then the title screen (no music until then).
func _show_intro() -> void:
	var boot := load(BOOT_PATH) as BootData
	if boot == null:
		push_warning("Main: could not load %s, no intro" % BOOT_PATH)
		_show_title()
		return
	var intro := IntroScreen.new()
	intro.name = "Intro"
	intro.setup(boot)
	intro.done.connect(func() -> void:
		intro.queue_free()
		_show_title())
	add_child(intro)


## The title screen (card #82): any button fades to the main menu.
func _show_title() -> void:
	var title := TitleScreen.new()
	title.name = "Title"
	title.setup(_branding)
	title.done.connect(_fade_to.bind(_show_main_menu))
	_show_screen(title)


## A zone parked outside the tree during a fight is not freed with the tree: free it here.
func _exit_tree() -> void:
	if _zone != null and not _zone.is_inside_tree():
		_zone.free()
		_zone = null


func _process(delta: float) -> void:
	if Net.is_host():
		_net_host_tick(delta)
	if not _options.is_autoplay():
		_watch_pads()
		MouseCursor.set_menus_allowed(_mouse_wanted())
	# Autoplay guard: a zone that never reaches a fight is stuck.
	if not _options.is_autoplay() or _zone == null or not _zone.is_inside_tree() or _zone.is_frozen():
		_zone_idle_s = 0.0
		return
	_zone_idle_s += delta
	if _zone_idle_s > AUTOPLAY_ZONE_STUCK_S:
		_zone_idle_s = 0.0
		_autoplay_fail("zone_stuck")


## True on every menu (the main menu, run screens, pause, settings, the backpack over a zone) and
## false while a fight or a zone is being played: those are keyboard and pad games, so the mouse
## pointer stays hidden there (card #202).
func _mouse_wanted() -> bool:
	if _pause != null or _prompt != null or _overlay != null:
		return true
	for child: Node in get_children():
		if child is SettingsScreen:
			return true
	var playing := (_combat != null and _combat.is_inside_tree()) or (_zone != null and _zone.is_inside_tree())
	return not playing


# --- screens ----------------------------------------------------------------------------------

## Frees whatever is shown (fight, zone, screen, prompt) and shows `screen`, if any.
func _show_screen(screen: Node) -> void:
	_close_overlay()
	_close_pad_overlay()
	_free_combat()
	_free_zone()
	_free_screen()
	if screen != null:
		_screen = screen
		add_child(screen)
		Sfx.play_ambience("")
		var song := _music.run_path if _is_run_screen(screen) and not _music.run_path.is_empty() else _music.menu_path
		if screen is CreditsScreen and not _music.credits_path.is_empty():
			song = _music.credits_path
		if screen is RunEndScreen and _run != null:
			var end := _music.victory_path if _run.result == RunState.VICTORY else _music.defeat_path
			if not end.is_empty():
				song = end
		Sfx.play_music(song, _music.volume_db)
	# Anyone can change the backpack (DESIGN.md 8.1), so the party screen is not just watched.
	_watch_layer.visible = Net.is_client() and _is_run_screen(screen) and not screen is PartyScreen


func _free_screen() -> void:
	_free_pause()
	if _screen != null:
		_screen.queue_free()
		_screen = null


## Fades to black, runs `build` (which shows the next thing), and fades back in. With a
## `tip_title` a loading card (that title and a tip, card #86) shows over the black for at least
## the tips' hold_ms, and `build` runs at its end, so a zone starts when it is seen. Online clients
## and the bot do not hold the card (the host already held it before sending the screen).
func _fade_to(build: Callable, tip_title: String = "") -> void:
	if _busy:
		return
	_busy = true
	var gen := _flow_gen
	await _transition.fade_out()
	if gen != _flow_gen:
		_transition.fade_in()
		_end_busy()
		return
	if not tip_title.is_empty():
		await _transition.show_tip(tip_title)
		var tips := load(TIPS_PATH) as TipSet
		if tips != null and tips.hold_ms > 0 and not Net.is_client() and not _options.is_autoplay():
			await get_tree().create_timer(float(tips.hold_ms) / 1000.0).timeout
		if gen != _flow_gen:
			await _transition.hide_tip()
			_transition.fade_in()
			_end_busy()
			return
	build.call()
	await get_tree().process_frame
	await _transition.hide_tip()
	await _transition.fade_in()
	_end_busy()


## A transition is over: messages that waited for it go on (online client).
func _end_busy() -> void:
	_busy = false
	_pump_net.call_deferred()


func _show_main_menu() -> void:
	_end_tutorial()
	_run = null
	_checkpoint = {}
	_checkpoint_in_stop = false
	ButtonPrompts.set_both(false)
	if Net.is_online():
		_leave_online()
	var saved := _valid_save()
	var menu := MainMenu.new()
	menu.name = "MainMenu"
	# A saved run is where the cursor rests until the player picks something else.
	var start := MainMenu.CONTINUE if not saved.is_empty() and not _menu_used else _menu_item
	# Practice (any fight or zone on its own) is a test tool: only debug builds list it (card #208).
	menu.setup(_branding, start, _notice, not saved.is_empty(), OS.is_debug_build())
	_notice = ""
	menu.chosen.connect(_on_menu_chosen)
	_show_screen(menu)


func _on_menu_chosen(item: StringName) -> void:
	_menu_item = item
	_menu_used = true
	match item:
		MainMenu.CONTINUE:
			_continue_with_players.call_deferred()
		MainMenu.NEW_RUN:
			if _save_in_the_way():
				_ask_overwrite_save.call_deferred()
			else:
				_start_new_run.call_deferred()
		MainMenu.HOST_ONLINE:
			_host_online.call_deferred()
		MainMenu.JOIN_ONLINE:
			_show_join.call_deferred()
		MainMenu.TUTORIAL:
			_fade_to.call_deferred(_start_tutorial)
		MainMenu.PRACTICE:
			_show_lobby.call_deferred(_show_select.call_deferred)
		MainMenu.JOURNAL:
			_show_journal.call_deferred()
		MainMenu.SETTINGS:
			_show_settings.call_deferred()
		MainMenu.CREDITS:
			_show_credits.call_deferred()
		MainMenu.QUIT:
			_quit_game()


## New Run from the main menu: the tutorial offer (once), then the players screen, then the run.
func _start_new_run() -> void:
	if not PlayerSettings.tutorial_offered() and not _options.is_autoplay():
		_offer_tutorial()
	else:
		_show_lobby(_fade_to.bind(_new_run), true)


## The players screen; Start keeps its roster and calls `next`. `with_oaths`: a run's screen, with
## the Oath row (DESIGN.md 8.15).
func _show_lobby(next: Callable, with_oaths: bool = false) -> void:
	var lobby := LobbyScreen.new()
	lobby.name = "Lobby"
	lobby.hero_portraits = _hero_portraits()
	if with_oaths:
		_give_oaths(lobby)
	if not _options.is_autoplay():
		# A pad that was unplugged since the last run must not come back as a ghost player.
		_players.drop_missing(_connected_pads())
	lobby.setup(_hero_names(), _players, _last_device)
	lobby.started.connect(_on_lobby_started.bind(next))
	lobby.back.connect(_show_main_menu.call_deferred)
	_show_screen(lobby)


## The players screen of a run gets the oath ladder, the highest oath this machine unlocked (--oath=N
## unlocks up to N for tests and pictures) and the last pick to start on.
func _give_oaths(lobby: LobbyScreen) -> void:
	if _run_data == null:
		return
	lobby.oaths = _run_data.oaths
	lobby.oath_unlocked = maxi(PlayerSettings.highest_oath_unlocked(), _options.oath)
	lobby.start_oath = _options.oath if _options.oath >= 0 else _oath


func _on_lobby_started(players: PlayerRoster, oath: int, next: Callable) -> void:
	_players = players
	if not _options.is_autoplay():
		_players.drop_missing(_connected_pads())
	# Practice has no Oath row: the pick for the next run stays as it was.
	if _screen is LobbyScreen and not (_screen as LobbyScreen).oaths.is_empty():
		_oath = oath
	# Keyboard and pad players together: hints show both kinds of buttons (card #45).
	ButtonPrompts.set_both(not Net.is_online() and _players.devices.has(PlayerRoster.KEYBOARD)
			and _players.devices.any(func(device: int) -> bool: return device >= 0))
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


## The heroes' big portraits (for the players screen), in party order.
func _hero_portraits() -> Array[String]:
	var paths: Array[String] = []
	if _run_data != null:
		for data: CharacterData in _run_data.party:
			paths.append(data.big_portrait_path)
	return paths


func _show_settings() -> void:
	var settings := SettingsScreen.new()
	settings.name = "Settings"
	settings.setup(_tuning, _visuals)
	settings.closed.connect(_show_main_menu.call_deferred)
	_show_screen(settings)


## The Rot Journal (card #200): what the player has met, read from the journal file when it opens.
func _show_journal() -> void:
	var screen := JournalScreen.new()
	screen.name = "Journal"
	screen.setup(JournalFile.load_journal(_journal_path()).journal as RotJournal, JournalScreen.load_enemies())
	screen.closed.connect(_show_main_menu.call_deferred)
	_show_screen(screen)


## Where the journal lives: --journal-path=PATH (dev tool), else the real file.
func _journal_path() -> String:
	return _options.journal_path if not _options.journal_path.is_empty() else JournalFile.PATH


## Writes the fight that just ended into the journal, if it counts (RotJournal.counts_fight), from
## what the presentation saw (the controller's mirror), never from the engine.
func _record_journal(fight: Dictionary) -> void:
	if not RotJournal.counts_fight(_run != null, _options.is_autoplay(), _tutorial != null,
			not _options.journal_path.is_empty()):
		return
	var where := _zone_name if not _zone_fight.is_empty() else (_encounter.display_name if _encounter != null else "")
	if not JournalFile.record(fight, where, _journal_path()):
		push_warning("Main: the Rot Journal could not be written")


## The credits (card #87), to their own song; Back returns to the main menu.
func _show_credits() -> void:
	var credits := load(CREDITS_PATH) as CreditsData
	if credits == null:
		push_warning("Main: could not load %s, no credits" % CREDITS_PATH)
		credits = CreditsData.new()
	var screen := CreditsScreen.new()
	screen.name = "Credits"
	screen.setup(credits, _branding)
	screen.closed.connect(_show_main_menu.call_deferred)
	_show_screen(screen)


func _show_select() -> void:
	_run = null
	var select := FightSelect.new()
	select.name = "FightSelect"
	select.setup(_zones, _encounters, _select_index, load(TUTORIAL_PATH) as TutorialData)
	select.chosen.connect(_on_fight_chosen)
	select.tutorial_chosen.connect(func() -> void:
		_select_index = 0
		_fade_to.call_deferred(_start_tutorial))
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
	_fade_to.call_deferred(_start_zone.bind(zone), zone.display_name)


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
				_zone_fight.opening as CombatSetup.Opening, true, _zone.ambient_air())
		continue_to = _on_zone_return_requested
	elif _run != null:
		_combat.configure(_encounter, _tuning, _visuals, _options, _fight_look,
				CombatSetup.Opening.NORMAL, false, _fight_air)
		continue_to = _on_run_fight_over
	else:
		# The tutorial starts with the heroes' turns (first strike) against a slower enemy.
		var first := _options.first_strike or _tutorial != null
		var opening := CombatSetup.Opening.FIRST_STRIKE if first else CombatSetup.Opening.NORMAL
		_combat.configure(_encounter, _tuning, _visuals, _options, null, opening)
		if _tutorial != null:
			_combat.enemy_speed_percent = (load(TUTORIAL_PATH) as TutorialData).enemy_speed_percent
	if _run != null:
		_combat.configure_run(_run)
		_combat.configure_drop(_drop if not _zone_fight.is_empty() else null)
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
	_combat.combat_finished.connect(_on_combat_finished)
	_combat.pause_reached.connect(_on_combat_pause_reached)
	_combat.restart_requested.connect(_on_restart_requested)
	_combat.select_requested.connect(_show_select.call_deferred)
	add_child(_combat)
	Sfx.play_ambience("")
	var boss := _encounter != null and _encounter.boss
	var elite := _encounter != null and _encounter.elite
	var song := _music.fight_path
	if boss and not _music.boss_path.is_empty():
		song = _music.boss_path
	elif elite and not _music.elite_path.is_empty():
		song = _music.elite_path
	Sfx.play_music(song, _music.volume_db)
	_combat.rage_music_volume_db = _music.volume_db
	_combat.victory_music_path = _music.victory_path
	_combat.defeat_music_path = _music.defeat_path
	_combat.end_music_delay_ms = _music.end_song_delay_ms
	if boss:
		_combat.rage_music_path = _music.boss_rage_path
	if Net.is_client():
		_combat_accepts = true
		var waiting := _combat_inbox.duplicate()
		_combat_inbox.clear()
		for batch: Dictionary in waiting:
			_combat.receive_batch(batch)


## Keeps the fight's recap (who hit hardest, the last blow) in case it was the run's last fight, and
## closes the run the moment its last fight is decided (card #197).
func _on_combat_finished(result: String) -> void:
	if _combat != null:
		_last_recap = _combat.recap()
		_record_journal(_combat.journal_fight())
		_last_recap_name = _encounter.display_name if _encounter != null else ""
	_close_decided_run(result)


## A defeat, or the last act's boss beaten, ends the run for certain: the save goes now (closing the
## game on the end screen must not leave a save that replays the decided fight), and a win opens its
## oath at once. The end screen shows what was opened. Clients leave it to their end screen.
func _close_decided_run(result: String) -> void:
	if _run == null or Net.is_client() or _decided_run == _run or not _run.decides_run(result):
		return
	_decided_run = _run
	_decided_unlock = _grant_win_unlock() if result == RunState.VICTORY else 0
	_clear_run_save()


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
	_zone_name = zone.display_name
	# A long zone is laid out anew each visit (DESIGN.md 8.5); in a run the same on every machine.
	var layout_seed := randi_range(1, 2147483646)
	if _run != null:
		layout_seed = _run.zone_seed(_run.at)
	elif _options.seed_override >= 0:
		layout_seed = _options.seed_override + 1
	_zone.configure(ZoneAssembler.assemble(zone, layout_seed), _tuning, _visuals, _explore, _run != null,
			_run != null and _run.is_deep())
	_zone.configure_players(_players)
	if Net.is_client():
		_zone.configure_remote()
	_send_screen({"name": "zone", "zone": zone.id})
	_zone.encounter_started.connect(_on_encounter_started)
	_zone.cleared.connect(_on_zone_cleared)
	_zone.pickup_requested.connect(_on_spot_pickup)
	_zone.chest_requested.connect(_on_chest)
	_zone.offer_requested.connect(_on_offer)
	_zone.prize_requested.connect(_on_prize)
	add_child(_zone)
	Sfx.play_music(_zone_song(), _music.volume_db)
	_play_zone_ambience()
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
		bot.setup(_zone, _tuning, _options.autoplay_mode, _run != null, _autoplay_health, _autoplay_use_items)


func _free_zone() -> void:
	_close_overlay()
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
	_close_overlay()
	_zone_fight = {"index": index, "opening": opening}
	_encounter = _zone.encounter_of(index)
	# The guard gives loot instead; others may drop something (the same on every machine: seeded).
	_drop = _run.drop_for(_run.at, index) if _run != null and index != _zone.guard_index() else null
	if Net.is_host():
		_net_seed = randi_range(1, 2147483646)
		Net.broadcast("screen", {"name": "zone_fight", "index": index, "opening": int(opening), "seed": _net_seed})
	var gen := _flow_gen
	Sfx.play("encounter_swirl")
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
	var gen := _flow_gen
	var found: ItemData = null
	if _run != null and not Net.is_client():
		_run.spend_items(_combat.used_items())
		_run.finish_fight(result, _combat.party_hp(), _encounter)
		_run.carry_team_gauge(_combat.team_gauge())
		_autoplay_spend_points()
		if result == RunState.VICTORY and _drop != null and _run.add_item(_drop) < 0:
			found = _drop
		_drop = null
		_send_screen({"name": "zone_back", "result": result})
		if _run.is_over():
			_clear_run_save()
			# The run's end screen follows (online, the host sends it).
			await _transition.fade_out()
			if gen != _flow_gen:
				_transition.fade_in()
				_end_busy()
				return
			_show_run_end()
			await get_tree().process_frame
			await _transition.fade_in()
			_end_busy()
			return
	await _transition.fade_out()
	if gen != _flow_gen or _zone == null:
		_transition.fade_in()
		_end_busy()
		return
	_free_combat()
	_zone_fight = {}
	add_child(_zone)
	# The song and the ambience pick up where the fight cut them off (card #192).
	Sfx.play_music(_zone_song(), _music.volume_db, true)
	_play_zone_ambience(true)
	_zone.resume(result)
	if _run_bar != null:
		_run_bar.refresh(_run)
	await get_tree().process_frame
	await _transition.fade_in()
	_end_busy()
	if found != null and _zone != null and not _zone.is_cleared():
		_open_zone_backpack("The enemy dropped a %s, but the backpack is full." % found.display_name, {"item": found})
	if _run == null and result == "escaped" and _options.autoplay_mode == CombatOptions.AUTOPLAY_ESCAPE:
		print("AUTOPLAY_RESULT zone_escaped fights=%d" % _zone.fights_started())
		_autoplay_quit()
	elif _run == null and result == "defeat" and _options.is_autoplay():
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


# --- the tutorial (DESIGN.md 7.8, card #131) --------------------------------------------------

## The first New Run asks once whether to play the tutorial first.
func _offer_tutorial() -> void:
	PlayerSettings.set_tutorial_offered(true)
	_prompt = ConfirmPrompt.new()
	_prompt.name = "TutorialPrompt"
	_prompt.setup("Play the tutorial first?", "Five short lessons: attacking, skills, defending and the team "
			+ "ultimate. It is always in the main menu too.", "Play the tutorial", "Start the run")
	_prompt.answered.connect(func(yes: bool) -> void:
		_prompt.queue_free()
		_prompt = null
		if yes:
			_fade_to(_start_tutorial)
		else:
			_show_lobby(_fade_to.bind(_new_run), true))
	add_child(_prompt)


## Starts the tutorial: its practice fight, one player, the lessons over it.
func _start_tutorial() -> void:
	var data := load(TUTORIAL_PATH) as TutorialData
	if data == null or data.encounter == null:
		push_error("Main: no tutorial data")
		_show_main_menu()
		return
	_end_tutorial()
	_run = null
	_players = PlayerRoster.solo(data.encounter.party.size(), _last_device)
	_tutorial = TutorialRunner.new()
	_tutorial.name = "Tutorial"
	add_child(_tutorial)
	_tutorial.setup(data)
	if _options.is_autoplay():
		_tutorial.auto_confirm_s = 1.2
	_tutorial.leave_requested.connect(_fade_to.bind(_show_main_menu))
	_encounter = data.encounter
	_zone_fight = {}
	_start_combat()
	_tutorial.attach_fight(_combat)
	var from := 0
	for arg: String in DevArgs.user_args():
		if arg.begins_with("--tutorial-step="):
			from = arg.substr("--tutorial-step=".length()).to_int()
	_tutorial.start(from)


func _end_tutorial() -> void:
	if _tutorial != null:
		_tutorial.queue_free()
		_tutorial = null


## A fight paused: for the tutorial's card, or the pause menu.
func _on_combat_pause_reached() -> void:
	if _pad_pause_wanted:
		_pad_pause_wanted = false
		if _pause == null and _prompt == null:
			if not _lost_pad_players().is_empty():
				_show_pad_overlay()
			elif _combat != null:
				# The pad came back before the pause landed: no menu, the fight just goes on.
				_combat.resume_after_pause()
			return
	if _tutorial != null and _tutorial.pause_wanted():
		_tutorial.on_paused()
	else:
		_open_pause()


func _on_tutorial_skip() -> void:
	_on_pause_resumed()
	if _tutorial != null:
		_tutorial.skip()


# --- save and quit (DESIGN.md 8.14) -----------------------------------------------------------

## Where the run is saved: --save-path=PATH (dev tool) or the player's one slot.
func _run_save_path() -> String:
	return _options.save_path if not _options.save_path.is_empty() else RunSave.PATH


## True if this session may touch the save at all: local play only (online runs are never saved),
## not the tutorial, and the bot only with --save-path (it must never touch the player's save).
func _save_io_ok() -> bool:
	return not Net.is_online() and _tutorial == null and (not _options.is_autoplay() or not _options.save_path.is_empty())


## True if this session works on the player's one save slot (a dev screen's sample run does not).
func _save_slot_ok() -> bool:
	return _options.screen.is_empty() and _save_io_ok()


## True if the run in progress is saved as it goes (not a dev sample run, not one already decided).
func _save_allowed() -> bool:
	return _run != null and _decided_run != _run and _save_slot_ok()


## Saves the run now. `in_stop` is true right after a stop was chosen: continuing re-enters that
## stop from its start, never the map (no dodging a hard stop by quitting); what the party already
## did there is in the state (RunState.stop_done, shop_sold), so Continue picks up after it. False if
## nothing was saved (not allowed, or the write failed).
func _save_run(in_stop: bool) -> bool:
	if not _save_allowed():
		return false
	_checkpoint = _run.to_dict()
	_checkpoint_in_stop = in_stop
	return _write_checkpoint()


## A stop's screen just settled something that cannot be taken back (an event choice, a purchase,
## an opened chest): the checkpoint is written again, still inside the stop (card #197).
func _save_stop_progress() -> void:
	if _run != null and _checkpoint_in_stop:
		_save_run(true)


## The fingerprint a save is checked against: data and version only, so a code-only update keeps a
## saved run (card #208; the online handshake still checks the code, Net.fingerprint).
func _save_fingerprint() -> String:
	if _content_fingerprint.is_empty():
		_content_fingerprint = DataHash.of_content()
	return _content_fingerprint


func _write_checkpoint() -> bool:
	if _checkpoint.is_empty():
		return false
	var saved := RunSave.save(_checkpoint, _save_fingerprint(), _checkpoint_in_stop, _players.player_count(), _run_save_path())
	if not saved:
		push_warning("Main: could not write the run save to %s" % _run_save_path())
	return saved


## The run ended or was abandoned: its save goes. Only on the real save slot: a dev screen's sample
## run (--screen=map and so on) has no save of its own and must never delete the player's.
func _clear_run_save() -> void:
	_checkpoint = {}
	_checkpoint_in_stop = false
	if _save_slot_ok():
		RunSave.delete(_run_save_path())


## The saved run that Continue would pick up: {state (a RunState), in_stop, players}, or {} if
## there is none. A file that is damaged, or that RunState refuses, is deleted and the menu says so
## once. A save made by another build (other version or content, the editor and an exported game
## fingerprint differently) is intact: it stays on disk, Continue is hidden and the menu says why;
## only starting a new run over it removes it (card #197).
func _valid_save() -> Dictionary:
	if not _save_io_ok() or _run_data == null or _tuning == null or not RunSave.exists(_run_save_path()):
		return {}
	# No content check (card #208): the game changes almost every day, and every change hid the
	# player's run. RunState.from_dict still refuses a run that does not fit (unknown gear, items or
	# skills, a wrong party, a stop that is not on the map); the fingerprint stays in the file only to
	# tell which build wrote it.
	var loaded := RunSave.load_save("", _run_save_path())
	var reason := ""
	match String(loaded.status):
		RunSave.LOADED:
			var state := RunState.from_dict(_run_data, _tuning, loaded.run as Dictionary)
			if state != null and not state.is_over():
				loaded["state"] = state
				return loaded
			reason = "it does not fit this version of the game"
		RunSave.MISSING:
			return {}
		_:
			reason = String(loaded.get("reason", "the file is damaged"))
			if bool(loaded.get("keep", false)):
				if not _mismatch_told and _notice.is_empty():
					_mismatch_told = true
					_notice = "The saved run was made by another build of the game (%s), so it cannot be continued here. " \
							% reason + "It is kept: open that build to carry on, or start a new run to replace it."
				return {}
	RunSave.delete(_run_save_path())
	if _notice.is_empty():
		_notice = "The saved run could not be continued (%s). It was deleted." % reason
	return {}


## A new run would overwrite a save: a usable one, or one kept from another build.
func _save_in_the_way() -> bool:
	return not _valid_save().is_empty() or (_save_io_ok() and RunSave.exists(_run_save_path()))


func _ask_overwrite_save() -> void:
	_prompt = ConfirmPrompt.new()
	_prompt.name = "OverwritePrompt"
	_prompt.setup("Start a new run?", "Your saved run will be lost.", "Start a new run", "Keep the saved run")
	_prompt.answered.connect(func(yes: bool) -> void:
		_prompt.queue_free()
		_prompt = null
		if yes:
			_start_new_run())
	add_child(_prompt)


## Main menu, Continue: a co-op save goes through the players screen first (pads may have changed).
func _continue_with_players() -> void:
	var saved := _valid_save()
	if saved.is_empty():
		_show_main_menu()
	elif int(saved.players) > 1:
		_show_lobby(_continue_run)
	else:
		_continue_run()


## Picks the saved run up: back in the stop it was saved in (from its start), or on the map.
func _continue_run() -> void:
	var saved := _valid_save()
	if saved.is_empty():
		_show_main_menu()
		return
	_run = saved.state as RunState
	_checkpoint = saved.run as Dictionary
	_checkpoint_in_stop = bool(saved.in_stop)
	print("Run continued: seed %d  act %d  stop %d%s" % [_run.run_seed, _run.act + 1, _run.visited,
			" (in progress)" if _checkpoint_in_stop else ""])
	Sfx.play("run_begin")
	if _checkpoint_in_stop and not _run.current().is_empty():
		_enter_stop()
	else:
		_fade_to(_show_map)


## Pause menu, Save & Quit: the run stays in its slot and the game goes back to the main menu.
## Inside a stop the save already holds the state from when the stop was entered, and that is
## what is kept; on the map the state is saved as it is now.
func _on_pause_save_quit() -> void:
	var saved := false
	if _checkpoint_in_stop:
		saved = _write_checkpoint()
	else:
		saved = _save_run(false)
	_notice = "" if saved else "The run could not be saved."
	_menu_item = MainMenu.CONTINUE
	_menu_used = true
	_free_pause()
	_fade_to(_show_main_menu)


# --- the run ----------------------------------------------------------------------------------

func _new_run() -> void:
	if _run_data == null:
		push_error("Main: no run data, cannot start a run")
		_autoplay_fail("no run data")
		_show_main_menu()
		return
	# A save in the way (asked about already) goes now: also one kept from another build.
	if _save_slot_ok():
		RunSave.delete(_run_save_path())
	var run_seed := _options.seed_override if _options.seed_override >= 0 else randi_range(1, 2147483646)
	if _options.oath >= 0:
		_oath = _options.oath
	_run = RunState.begin(_run_data, _tuning, run_seed, _oath)
	_oath = _run.oath
	if Net.is_host():
		Net.broadcast("run_start", {"seed": run_seed, "roster": _players.to_dict(), "oath": _run.oath})
	print("Run seed: %d  oath: %d  stops: %d  acts: %d" % [run_seed, _run.oath, _run.map.row_count(), _run.acts().size()])
	Sfx.play("run_begin")
	_show_map()


## `unroll` false shows the map already open (back from the party screen, or redrawn online).
func _show_map(unroll: bool = true) -> void:
	if _run == null:
		return
	# Back from an act's boss and its spoils: on to the next act's map (DESIGN.md 8.9).
	if not Net.is_client() and _run.act_cleared():
		_run.next_act()
		Sfx.play("run_cleared")
		print("Run act %d: %s" % [_run.act + 1, _run.act_data().display_name])
	var map := MapScreen.new()
	map.name = "Map"
	map.setup(_run, _map_look, unroll)
	map.stop_chosen.connect(_on_stop_chosen)
	map.quit_requested.connect(_open_pause)
	map.party_requested.connect(_show_party.bind("", true))
	_show_screen(map)
	_send_screen({"name": "map"})
	_save_run(false)
	if _options.is_autoplay() and not Net.is_client():
		_autoplay_map.call_deferred(map)


func _on_stop_chosen(id: int) -> void:
	if _busy or not _run.go(id):
		return
	_save_run(true)
	_enter_stop()


## Starts the stop the party is at: the stop just chosen on the map, or the one a saved run was in.
func _enter_stop() -> void:
	var stop := _run.current()
	print("Run stop %d: %s %s" % [_run.visited, RunMap.TYPE_NAMES[int(stop.type)], MapScreen.stop_name(_run, stop)])
	if _run.in_ambush():
		print("Run ambush: %s (chance was %d%%)" % [_run.ambush_id, _run.unknown_fight_percent()])
	match int(stop.type):
		RunMap.StopType.ZONE:
			var zone := _run.zone_of(stop)
			_fade_to(_start_zone.bind(zone), zone.display_name if zone != null else "")
		RunMap.StopType.REST:
			_fade_to(_show_rest)
		RunMap.StopType.SHOP:
			_fade_to(_show_shop)
		RunMap.StopType.FINAL:
			_start_final_fight()
		RunMap.StopType.ELITE:
			_start_final_fight(true)
		RunMap.StopType.EVENT:
			# A continued run whose choice was already made shows its result, never the choices again.
			_fade_to(_show_event.bind(_run.stop_text if _run.stop_done else ""))
		RunMap.StopType.TREASURE:
			_fade_to(_show_treasure.bind(_run.stop_done, _run.stop_text if _run.stop_done else ""))


## A run fight that is a stop of its own: the act's boss, an elite fight (`elite`) in the look of
## one of the act's zones, or an ambush (a "?" stop that turned into a fight, or an event choice
## that ended in one; DESIGN.md 8.7).
func _start_final_fight(elite: bool = false) -> void:
	_busy = true
	_encounter = _run.final_encounter()
	_fight_look = _run.final_look()
	_fight_air = []
	if _run.in_ambush():
		_encounter = _run.ambush_encounter()
		_fight_look = _run.ambush_look()
		print("Run ambush fight: %s" % [_encounter.id if _encounter != null else "none"])
		if _encounter == null:
			push_error("Ambush %s has no encounter" % _run.ambush_id)
			_run.end_ambush()
			_end_busy()
			_fade_to(_show_map)
			return
	elif elite:
		_encounter = _run.elite_of(_run.at)
		if _encounter == null:
			# The map never rolls an elite stop for an act without elites; if one slips through,
			# leave it as an empty stop instead of crashing the fight.
			push_error("Elite stop %d has no elite fight in act %d" % [_run.at, _run.act])
			_end_busy()
			_fade_to(_show_map)
			return
		var zone := _run.zone_of(_run.current())
		_fight_look = zone.look if zone != null else _run.final_look()
		if zone != null:
			_fight_air = zone.ambient
	_zone_fight = {}
	if Net.is_host():
		_net_seed = randi_range(1, 2147483646)
		_send_screen({"name": "final_fight", "seed": _net_seed})
	var gen := _flow_gen
	Sfx.play("encounter_swirl")
	await _transition.swirl_out()
	if gen != _flow_gen or _run == null:
		_transition.fade_in()
		_end_busy()
		return
	_start_combat()
	await get_tree().process_frame
	await _transition.fade_in()
	_end_busy()


## A boss or elite fight's end screen was left. A defeat (or the last boss) ends the run; an
## elite or an act's boss gives spoils, then the map (the next act's, after a boss).
func _on_run_fight_over(result: String) -> void:
	if _busy or _run == null:
		return
	_run.spend_items(_combat.used_items())
	var ambushed := _run.in_ambush()
	var ambush_spoils := _run.ambush_spoils
	_run.finish_fight(result, _combat.party_hp(), _encounter)
	_run.carry_team_gauge(_combat.team_gauge())
	_autoplay_spend_points()
	if _run.is_over():
		_clear_run_save()
		_fade_to(_show_run_end)
	elif result == RunState.VICTORY and ambushed and not ambush_spoils:
		# An ambush pays gold and XP like any fight; spoils only when the event's data says so.
		_fade_to(_show_map)
	elif result == RunState.VICTORY:
		var boss := int(_run.current().type) == RunMap.StopType.FINAL
		_fade_to(_show_loot.bind([] as Array[GearData], "The boss fell. Take one." if boss else "The elite fell. Take one."))
	else:
		_fade_to(_show_map)


func _show_rest(result: String = "") -> void:
	var rest := RestScreen.new()
	rest.name = "Rest"
	rest.remote = Net.is_client()
	rest.setup(_run, RestScreen.FIRE_PATH, result)
	rest.done.connect(_fade_to.bind(_show_map))
	rest.acted.connect(func(text: String) -> void: _send_screen({"name": "rest", "result": text}))
	_show_screen(rest)
	_send_screen({"name": "rest", "result": result})
	if _options.is_autoplay() and not Net.is_client():
		_autoplay_rest.call_deferred(rest)


func _show_shop(gear: Array[GearData] = [], charms: Array[ItemData] = []) -> void:
	var shop := ShopScreen.new()
	shop.name = "Shop"
	if not Net.is_client():
		gear = _run.shop_gear(_run.at)
		charms = _run.shop_charms(_run.at)
	shop.setup(_run, gear, charms)
	shop.done.connect(_fade_to.bind(_show_map))
	shop.restocked.connect(func() -> void: _send_shop_wares(_run.shop_gear(_run.at), _run.shop_charms(_run.at)))
	shop.acted.connect(_save_stop_progress)
	_show_screen(shop)
	_send_shop_wares(gear, charms)
	if _options.is_autoplay() and not Net.is_client():
		_autoplay_shop.call_deferred(shop)


func _send_shop_wares(gear: Array[GearData], charms: Array[ItemData]) -> void:
	var charm_ids: Array = []
	for item: ItemData in charms:
		charm_ids.append(item.id)
	_send_screen({"name": "shop", "gear": _gear_ids(gear), "charms": charm_ids})


## A "?" stop (DESIGN.md 8.7). `result`: online clients show what the host chose.
func _show_event(result: String = "") -> void:
	var screen := EventScreen.new()
	screen.name = "Event"
	screen.remote = Net.is_client()
	screen.setup(_run, null if _run.in_ambush() and result.is_empty() else _run.event_of(_run.at), result)
	screen.done.connect(_on_event_done)
	screen.chosen.connect(func(index: int, text: String) -> void:
		_send_screen({"name": "event", "result": text if not text.is_empty() else "You walk on."})
		# The risk is rolled: lock the result in (a Leave, index -1, took nothing).
		if index >= 0:
			_save_stop_progress())
	screen.gifts_settled.connect(_save_stop_progress)
	_show_screen(screen)
	_send_screen({"name": "event", "result": result})
	if _options.is_autoplay() and not Net.is_client():
		_autoplay_event.call_deferred(screen)


## An event (or an ambush page) was left: into the fight if it sprang an ambush, else the map.
func _on_event_done() -> void:
	if _busy:
		return
	if _run.in_ambush():
		_start_final_fight()
	else:
		_fade_to(_show_map)


## A treasure stop (DESIGN.md 8.8). `opened`: online clients show the chest as the host left it.
func _show_treasure(opened: bool = false, text: String = "") -> void:
	var screen := TreasureScreen.new()
	screen.name = "Treasure"
	screen.remote = Net.is_client()
	screen.setup(_run, _explore, opened, text)
	screen.done.connect(_fade_to.bind(_show_map))
	screen.opened.connect(func() -> void: _send_screen({"name": "treasure", "opened": true}))
	screen.gifts_settled.connect(_save_stop_progress)
	_show_screen(screen)
	_send_screen({"name": "treasure", "opened": opened})
	if _options.is_autoplay() and not Net.is_client():
		_autoplay_treasure.call_deferred(screen)


## Spoils after a guard, an elite or an act's boss (DESIGN.md 8, 8.6): pick one, then the party
## screen to put it on.
func _show_loot(gear: Array[GearData] = [], text: String = "") -> void:
	var loot := LootScreen.new()
	loot.name = "Loot"
	if not Net.is_client():
		gear = _run.loot_choices(_run.at)
	loot.setup(gear, text)
	loot.chosen.connect(_on_loot_chosen)
	_show_screen(loot)
	Sfx.play("loot_reveal")
	_send_screen({"name": "loot", "gear": _gear_ids(gear), "text": text})
	if _options.is_autoplay() and not Net.is_client():
		_autoplay_loot.call_deferred(loot)


func _on_loot_chosen(item: GearData) -> void:
	if item != null and not _run.owns(item):
		_show_party.call_deferred("Found: %s. Who wears it?" % item.display_name, false, {"gear": item})
	else:
		_fade_to(_show_map)


## The party screen: gear, stats and the backpack. From the map it closes back to the map at once;
## after loot it fades on to the map. Online clients change things through the host.
func _show_party(note: String, from_map: bool, held: Dictionary = {}) -> void:
	var party := PartyScreen.new()
	party.name = "Party"
	party.remote = Net.is_client()
	party.setup(_run, note, held)
	party.op_requested.connect(_send_bag_op)
	if from_map:
		party.done.connect(_show_map.bind(false).call_deferred)
	else:
		party.done.connect(_fade_to.bind(_show_map))
	_show_screen(party)
	if Net.is_client():
		_watch_layer.visible = false
		return
	_send_screen({"name": "party", "note": note})
	if _options.is_autoplay() and not Net.is_client():
		_autoplay_party.call_deferred(party)


## A win at oath N opens oath N+1 on this machine (never lowering what is open). Returns the oath
## that was newly opened (0: none), worked out from the value before the unlock, for the end screen.
## Bot runs only show it.
func _grant_win_unlock() -> int:
	var ladder := _run.data.oaths.size()
	var before := PlayerSettings.highest_oath_unlocked()
	var after := PlayerSettings.oath_after_win(before, _run.oath, ladder)
	if after <= before:
		return 0
	if not _options.is_autoplay():
		PlayerSettings.unlock_after_win(_run.oath, ladder)
	return after


func _show_run_end() -> void:
	_clear_run_save()
	var end := RunEndScreen.new()
	end.name = "RunEnd"
	# A win at oath N opens oath N+1 on this machine (online players too). The host and local play
	# opened it when the fight was decided; the end screen only shows what that did.
	var unlocked_now := 0
	if _run.result == RunState.VICTORY:
		unlocked_now = _decided_unlock if _decided_run == _run else _grant_win_unlock()
	var recap_lines: Array[String] = []
	if _run.result != RunState.VICTORY:
		var where := "Stop %d, act %d%s" % [_run.visited, _run.act + 1, ", " + OathData.label(_run.oath) if _run.oath > 0 else ""]
		recap_lines = FightRecap.lines(_last_recap, _last_recap_name, where)
	end.setup(_run, _visuals.end_input_guard_ms, unlocked_now, recap_lines)
	end.done.connect(_fade_to.bind(_show_main_menu))
	_show_screen(end)
	_send_screen({"name": "run_end"})
	_client_done = Net.is_client()
	if _options.is_autoplay():
		for line: String in recap_lines:
			print("AUTOPLAY_RECAP ", line)
		print("AUTOPLAY_RESULT run_%s act=%d stops=%d fights=%d level=%d gear=%d items=%d gold=%d seed=%d oath=%d" % [
				_run.result, _run.act + 1, _run.visited, _run.fights_won, _run.top_level(), _worn_count(), _run.backpack.entries.size(),
				_run.gold_earned, _run.run_seed, _run.oath])
		_autoplay_quit()


# --- pad drop and window focus (DESIGN.md 9.1) ------------------------------------------------

## The Godot ids of the pads that are plugged in.
static func _connected_pads() -> Array[int]:
	var pads: Array[int] = []
	pads.assign(Input.get_connected_joypads())
	return pads


## Local co-op players whose pad is gone (never online; the roster ignores keyboards).
func _lost_pad_players() -> Array[int]:
	if Net.is_online() or _players == null or not _players.is_coop():
		return [] as Array[int]
	return _players.missing_players(_connected_pads())


## Every frame in local co-op: when a player's pad is gone during a fight or a zone, hold the game
## under a card until they are back (their heroes would wait forever otherwise, and P1 could not
## walk). A pad that returns under the same id carries on by itself.
func _watch_pads() -> void:
	var lost := _lost_pad_players()
	if _pad_overlay != null:
		if lost.is_empty():
			_resume_after_pad_card()
		else:
			_pad_overlay.show_player(lost[0])
		return
	if lost.is_empty() or _busy or _pause != null or _prompt != null or _tutorial != null:
		return
	if _combat != null and _combat.is_inside_tree():
		# The flag goes up first: an idle fight pauses (and emits pause_reached) inside request_pause.
		var was_wanted := _pad_pause_wanted
		_pad_pause_wanted = true
		if not _combat.request_pause(true):
			_pad_pause_wanted = was_wanted
	elif _zone != null and _zone.is_inside_tree() and not _zone.is_frozen():
		_show_pad_overlay()


func _show_pad_overlay() -> void:
	var lost := _lost_pad_players()
	if _pad_overlay != null or lost.is_empty():
		return
	_hold_behind_overlay(true)
	_pad_overlay = PadLostOverlay.new()
	_pad_overlay.name = "PadLost"
	_pad_overlay.setup(_players)
	_pad_overlay.show_player(lost[0])
	_pad_overlay.claimed.connect(_on_pad_claimed)
	_pad_overlay.dropped.connect(_on_pad_dropped)
	add_child(_pad_overlay)


func _close_pad_overlay() -> void:
	_pad_pause_wanted = false
	if _pad_overlay != null:
		_pad_overlay.queue_free()
		_pad_overlay = null


func _resume_after_pad_card() -> void:
	_close_pad_overlay()
	_hold_behind_overlay(false)
	if _combat != null and _combat.is_paused():
		_combat.resume_after_pause()


func _on_pad_claimed(device: int) -> void:
	var lost := _lost_pad_players()
	if not lost.is_empty() and _players.replace_device(lost[0], device):
		Sfx.play("menu_confirm")
		ButtonPrompts.set_both(_players.devices.has(PlayerRoster.KEYBOARD)
				and _players.devices.any(func(d: int) -> bool: return d >= 0))
		_refresh_roster_users()
		_watch_pads()


func _on_pad_dropped() -> void:
	var lost := _lost_pad_players()
	if not lost.is_empty() and _players.leave(lost[0]):
		Sfx.play("menu_cancel")
		_refresh_roster_users()
		_watch_pads()


## The fight and the zone read the roster in place; tell them it changed.
func _refresh_roster_users() -> void:
	if _combat != null:
		_combat.update_players(_players)
	if _zone != null:
		_zone.configure_players(_players)


## The window lost focus (alt-tab, the Steam overlay, a notification): a fight or zone pauses,
## alone or in local co-op. Never online, where the others play on.
func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_FOCUS_OUT and what != NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		return
	if Net.is_online() or _options == null or _options.is_autoplay():
		return
	# Deferred (card #208): focus can go while Main is adding a child (entering a zone), and a pause
	# menu added then fails, leaving the game held still behind a menu that never appeared.
	_pause_game.call_deferred()


# --- pause ------------------------------------------------------------------------------------

## Pause (Esc / Menu, DESIGN.md 7.5) over a fight, a zone or the run map. Main reads it before the
## fight's own input, so Esc never reaches the action menu as "back".
func _input(event: InputEvent) -> void:
	if (event is InputEventKey or event is InputEventJoypadButton) and event.is_pressed():
		_last_device = PlayerRoster.device_of(event)
	var pause := event.is_action_pressed(&"pause", false, true)
	# The backpack over a zone (anyone, any time: DESIGN.md 8.1).
	if _overlay == null and _pause == null and _prompt == null and not _busy and _run != null and _zone != null 			and _zone.is_inside_tree() and not _zone.is_frozen() and event.is_action_pressed(&"party_menu", false, true):
		get_viewport().set_input_as_handled()
		Sfx.play("menu_confirm")
		_open_zone_backpack("", {})
		return
	# Online client on a run screen: the host chooses; only pause (to leave) works here. The
	# backpack is everyone's: the party screen takes input, and Tab / Y on the map opens it.
	var own := _screen is PartyScreen or (_screen is MapScreen and event.is_action(&"party_menu"))
	if Net.is_client() and _is_run_screen(_screen) and _pause == null and _prompt == null and not pause and not own:
		if not event is InputEventMouseMotion:
			get_viewport().set_input_as_handled()
		return
	# Online the fight goes on under the pause menu: the fight-only buttons (X / Y / RT) must not
	# reach the action menu underneath (the pause menu only eats the menu buttons).
	if (_pause != null or _prompt != null) and _combat != null and (event.is_action(&"fight_skills")
			or event.is_action(&"fight_items") or event.is_action(&"fight_ultimate")):
		get_viewport().set_input_as_handled()
		return
	if _pause != null or _prompt != null or _busy or not pause:
		return
	if Net.is_online() and (_combat != null or _zone != null or _is_run_screen(_screen)):
		# Online nothing stops for a pause menu: it opens over the game, which goes on.
		get_viewport().set_input_as_handled()
		_open_pause()
		return
	if _pause_game():
		get_viewport().set_input_as_handled()


## Pauses the fight (after the current move), the zone or the run map. True if it started one.
func _pause_game() -> bool:
	if _pause != null or _prompt != null or _busy or _pad_overlay != null:
		return false
	if _combat != null and _combat.is_inside_tree():
		# A fight pauses between moves; it calls back with pause_reached.
		return _combat.request_pause()
	if _zone != null and _zone.is_inside_tree() and not _zone.is_frozen():
		_open_pause()
		return true
	if _screen is MapScreen:
		_open_pause()
		return true
	return false


func _open_pause() -> void:
	if _pause != null:
		return
	if not Net.is_online():
		_hold_behind_overlay(true)
	elif _zone != null:
		_zone.input_held = true
	_pause = PauseMenu.new()
	_pause.name = "Pause"
	if _tutorial != null:
		_pause.setup("Leave tutorial", "Back to the main menu.", "Skip this lesson", "Go on to the next one.")
		_pause.extra_requested.connect(_on_tutorial_skip)
	elif Net.is_host():
		_pause.setup("End the game", "The run ends for everyone.")
	elif Net.is_client():
		_pause.setup("Leave the game", "You leave; the others play on.")
	elif _run != null and _save_allowed():
		var where := "The stop starts over when you continue (what you already did there stays done)." if _checkpoint_in_stop else "You continue from this map."
		_pause.setup("Abandon run", "The run and its save are lost. Back to the main menu.", "", "",
				"Save & Quit", "Keep the run and go to the main menu. %s" % where)
		_pause.save_quit_requested.connect(_on_pause_save_quit)
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
	if _tutorial != null:
		_free_pause()
		_fade_to.call_deferred(_show_main_menu)
		return
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
		if _run != null:
			_clear_run_save()
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
	lobby.hero_portraits = _hero_portraits()
	_give_oaths(lobby)
	lobby.setup_online(_hero_names(), _players, true, NetSession.local_addresses(), _tuning.net_port)
	lobby.roster_changed.connect(_on_online_roster_changed)
	lobby.oath_changed.connect(_on_online_oath_changed)
	lobby.started.connect(_on_online_started)
	lobby.back.connect(_show_main_menu.call_deferred)
	_show_screen(lobby)
	print("Hosting on port %d: %s" % [_tuning.net_port, ", ".join(NetSession.local_addresses())])


func _on_online_roster_changed(players: PlayerRoster) -> void:
	_players = players
	Net.broadcast("lobby", {"roster": players.to_dict(), "oath": _lobby_oath()})
	if _options.host_players > 0 and players.player_count() >= _options.host_players:
		_autoplay_start_online()


## The oath picked on the players screen now (0 without one).
func _lobby_oath() -> int:
	return (_screen as LobbyScreen).oath() if _screen is LobbyScreen else 0


## Online host: the oath pick changed; the clients show it.
func _on_online_oath_changed(oath: int) -> void:
	_oath = oath
	Net.broadcast("lobby", {"roster": _players.to_dict(), "oath": oath})


## The host pressed Start: nobody else can join now; the run begins (the clients follow).
func _on_online_started(players: PlayerRoster, oath: int) -> void:
	if _busy or not _screen is LobbyScreen:
		return
	_players = players
	_oath = oath
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
	Sfx.play("net_connected")
	_players = PlayerRoster.online(_hero_names().size(), NetSession.HOST_PEER, peer)
	var lobby := LobbyScreen.new()
	lobby.name = "Lobby"
	lobby.hero_portraits = _hero_portraits()
	if _run_data != null:
		lobby.oaths = _run_data.oaths
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
		Sfx.play("player_leave")
		Net.broadcast("roster", {"roster": _players.to_dict()})
		if _combat != null:
			_combat.update_players(_players, peer)
		if _zone != null:
			_zone.configure_players(_players)


func _on_net_host_lost() -> void:
	if not _client_done:
		_autoplay_fail("host_lost")
		Sfx.play("net_error")
	_end_online("The run is over." if _client_done else "The host left the game.")


func _on_net_refused(reason: String) -> void:
	_autoplay_fail("refused " + reason)
	Sfx.play("net_error")
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
			"bag":
				# A player changed the shared backpack (DESIGN.md 8.1): first come, first served.
				if _run != null and payload.get("op") is Dictionary and _run.apply_op(payload.op as Dictionary):
					_refresh_party_views()
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
				(_screen as LobbyScreen).set_oath(int(payload.get("oath", 0)))
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
			_run = RunState.begin(_run_data, _tuning, int(p.get("seed", 1)), int(p.get("oath", 0)))
			Sfx.play("run_begin")
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
		"map", "rest", "shop", "loot", "party", "run_end", "event", "treasure":
			_net_screen = p
			_fade_to(_watched_screen_builder(p))
		"zone":
			var zone := _zone_by_id(String(p.get("zone", "")))
			if zone != null:
				_fade_to(_start_zone.bind(zone), zone.display_name)
		"zone_fight":
			_net_seed = int(p.get("seed", 1))
			if _zone != null and _zone.is_inside_tree():
				# The pump waits until the fight starts (the zone plays its short opening first).
				_net_hold = true
				_zone.begin_remote(int(p.get("index", -1)), int(p.get("opening", 0)) as CombatSetup.Opening)
		"final_fight":
			_net_seed = int(p.get("seed", 1))
			_start_final_fight(int(_run.current().get("type", -1)) == RunMap.StopType.ELITE)
		"zone_back":
			# After a lost run the host sends the run's end next instead.
			if not _run.is_over():
				_on_zone_return_requested(String(p.get("result", "")))


## Client: the function that builds a watched run screen from the host's message.
func _watched_screen_builder(p: Dictionary) -> Callable:
	match String(p.get("name", "")):
		"rest":
			return _show_rest.bind(String(p.get("result", "")))
		"event":
			return _show_event.bind(String(p.get("result", "")))
		"treasure":
			return _show_treasure.bind(bool(p.get("opened", false)))
		"shop":
			var charms: Array[ItemData] = []
			if _run != null:
				var by_id := _run.items_by_id()
				for id: Variant in p.get("charms", []):
					if by_id.has(str(id)):
						charms.append(by_id[str(id)])
			return _show_shop.bind(_gear_from_ids(p.get("gear", []) as Array), charms)
		"loot":
			return _show_loot.bind(_gear_from_ids(p.get("gear", []) as Array), String(p.get("text", "")))
		"party":
			return _show_party.bind(String(p.get("note", "")), true)
		"run_end":
			return _show_run_end
	return _show_map


## Client: the run changed on the host (a purchase, gear): show the watched screen again. A party
## screen (this player may be busy in it) and the backpack over a zone only redraw.
func _rebuild_watched_screen() -> void:
	if _refresh_party_views():
		return
	if _busy or _net_screen.is_empty() or not _is_run_screen(_screen) or _screen is RunEndScreen:
		return
	if _screen is MapScreen:
		_show_map(false)
		return
	_watched_screen_builder(_net_screen).call()


## Redraws the open party screen or backpack after the run changed. True if one is open.
func _refresh_party_views() -> bool:
	var shown := false
	for view: Variant in [_screen, _overlay]:
		if view is PartyScreen and is_instance_valid(view):
			(view as PartyScreen).refresh()
			shown = true
	return shown


## Online client: asks the host to make a backpack change.
func _send_bag_op(op: Dictionary) -> void:
	if Net.is_client():
		Net.send_to_host("bag", {"op": op})


# --- the backpack over a zone (DESIGN.md 8.1) -------------------------------------------------

## Opens the backpack over the zone, holding the zone still (online clients: only their own input
## stops; the host's zone goes on). `held`: something new in hand ({item: ItemData}).
func _open_zone_backpack(note: String, held: Dictionary) -> void:
	if _overlay != null or _zone == null or _run == null:
		return
	_overlay = PartyScreen.new()
	_overlay.name = "Backpack"
	_overlay.layer = ZONE_BACKPACK_LAYER
	_overlay.remote = Net.is_client()
	_overlay.close_when_settled = not held.is_empty()
	add_child(_overlay)
	_overlay.setup(_run, note, held)
	_overlay.op_requested.connect(_send_bag_op)
	_overlay.left_behind.connect(_on_find_left)
	_overlay.done.connect(_close_overlay)
	if Net.is_client():
		_zone.input_held = true
	else:
		_zone.set_paused(true)
	if _options.is_autoplay() and not Net.is_client():
		_autoplay_backpack.call_deferred(_overlay)


func _close_overlay() -> void:
	if _overlay == null:
		return
	_overlay.queue_free()
	_overlay = null
	if _spot_pending >= 0 and _zone != null:
		_zone.take_spot(_spot_pending)
	_spot_pending = -1
	if _zone != null:
		_zone.input_held = false
		_zone.set_paused(false)
	if _run_bar != null and _run != null:
		# Attribute points and gear may have changed levels' marks and max HP.
		_run_bar.refresh(_run)


## A find that did not fit was left behind: a glinting spot keeps it.
func _on_find_left(item: ItemData) -> void:
	if _spot_pending >= 0 and _run.spot_item(_run.at, _spot_pending) == item:
		_spot_pending = -1


## The leader tries a chest: a key from the backpack opens it; its prize goes into the backpack (an
## item) or straight onto a hero (gear), with the backpack opening when it has to.
func _on_chest(chest: int) -> void:
	if _run == null or _zone == null or _overlay != null:
		return
	if not _run.use_key():
		Sfx.play("locked")
		_zone.announce("Locked. You need a key.")
		return
	_zone.open_chest(chest)
	Sfx.play("chest_open")
	var prize := _run.chest_contents(_run.at, chest)
	print("Run chest: %s" % (String(prize.get("id")) if prize != null else "empty"))
	_give_prize(prize, "The chest")


## The leader opened a beaten champion's prize chest (DESIGN.md 8.5): its prize goes into the
## backpack or onto a hero, like a locked chest's.
func _on_prize(prize: int) -> void:
	if _run == null or _zone == null:
		return
	Sfx.play("chest_open")
	var found := _run.prize_contents(_run.at, _zone.prize_roamer(prize))
	print("Run prize chest: %s" % (String(found.get("id")) if found != null else "empty"))
	_give_prize(found, "The champion's chest")


## Gives a chest's prize: gear onto a hero (the backpack opens to pick who), an item into the
## backpack (it opens with the item in hand when full). `from` names the chest in the line shown.
func _give_prize(prize: Resource, from: String) -> void:
	if prize is GearData:
		_open_zone_backpack("%s held the %s. Who wears it?" % [from, (prize as GearData).display_name], {"gear": prize})
	elif prize is ItemData:
		var item := prize as ItemData
		if item.kind == ItemData.Kind.UPGRADE:
			_run.add_item(item)
			_zone.announce("%s held a %s. The backpack has %d rows." % [from, item.display_name, _run.backpack.rows])
		elif _run.add_item(item) >= 0:
			_zone.announce("%s held: %s" % [from, item.display_name])
		else:
			_open_zone_backpack("%s held a %s, but the backpack is full." % [from, item.display_name], {"item": item})
	else:
		_zone.announce("%s is empty." % from)


## The leader walked up to a shrine or a wanderer (DESIGN.md 8.5): its question, yes or no. The
## zone holds still meanwhile. The bot takes every deal it can pay for.
func _on_offer(offer: int) -> void:
	if _run == null or _zone == null or _overlay != null or _prompt != null:
		return
	var data := _zone.offer_data(offer)
	if data == null:
		return
	if _options.is_autoplay():
		_take_offer(offer, _run.can_take_offer(data))
		return
	_zone.set_paused(true)
	_prompt = ConfirmPrompt.new()
	_prompt.name = "OfferPrompt"
	var detail := data.detail
	if not _run.can_take_offer(data):
		detail += "
You have %d gold." % _run.gold
	_prompt.setup(data.question, detail, data.yes_text, data.no_text)
	_prompt.answered.connect(func(yes: bool) -> void:
		_prompt.queue_free()
		_prompt = null
		if _zone != null:
			_zone.set_paused(false)
			_take_offer(offer, yes))
	add_child(_prompt)


func _take_offer(offer: int, yes: bool) -> void:
	if not yes or _zone == null:
		return
	var data := _zone.offer_data(offer)
	var result := _run.take_offer(data, _run.at, offer)
	if not bool(result.ok):
		Sfx.play("locked")
		_zone.announce(String(result.text))
		return
	_zone.use_offer(offer)
	Sfx.play("item_found")
	print("Run offer: %s" % data.id)
	if _run_bar != null:
		_run_bar.refresh(_run)
	var item := result.item as ItemData
	if item == null:
		_zone.announce(String(result.text))
	elif item.kind == ItemData.Kind.UPGRADE or _run.add_item(item) >= 0:
		if item.kind == ItemData.Kind.UPGRADE:
			_run.add_item(item)
		_zone.announce(String(result.text))
	else:
		_open_zone_backpack("%s, but the backpack is full." % String(result.text), {"item": item})


## The leader picks up glinting spot `spot`: into the backpack, or the backpack opens with it in hand.
func _on_spot_pickup(spot: int) -> void:
	if _run == null or _zone == null or _overlay != null:
		return
	var item := _run.spot_item(_run.at, spot)
	if item == null:
		_zone.take_spot(spot)
		return
	if item.kind == ItemData.Kind.UPGRADE:
		_run.add_item(item)
		_zone.take_spot(spot)
		_zone.announce("Found: %s. The backpack has %d rows." % [item.display_name, _run.backpack.rows])
		Sfx.play("item_found")
		return
	if _run.add_item(item) >= 0:
		_zone.take_spot(spot)
		_zone.announce("Found: %s" % item.display_name)
		Sfx.play("item_found")
		print("Run find: %s" % item.id)
		return
	_spot_pending = spot
	Sfx.play("item_found")
	_open_zone_backpack("Found a %s, but the backpack is full." % item.display_name, {"item": item})


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


## The current zone's background loop; anything else (fights, screens) is silent underneath.
## `resume`: back from a fight, the loop goes on where it was left.
func _play_zone_ambience(resume: bool = false) -> void:
	var amb := _zone.ambience() if _zone != null else ["", 0.0]
	Sfx.play_ambience(String(amb[0]), float(amb[1]), resume)


## The current zone's own song, else the shared zone song.
func _zone_song() -> String:
	var own := _zone.music_path() if _zone != null else ""
	return own if not own.is_empty() else _music.zone_path


func _is_run_screen(node: Node) -> bool:
	return node is MapScreen or node is ShopScreen or node is RestScreen or node is LootScreen \
			or node is PartyScreen or node is RunEndScreen or node is EventScreen or node is TreasureScreen


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
		_on_online_started((_screen as LobbyScreen).roster(), (_screen as LobbyScreen).oath())


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
	_autoplay_use_items()
	var pick := -1
	var cheapest := 1 << 30
	for item: ItemData in _run_data.shop_items:
		cheapest = mini(cheapest, item.price)
	var hurt := _autoplay_hurt()
	# Treasure first, a shop with gold, a campfire when hurt, then zones, events, and elites when
	# healthy (each kind gets played).
	for wanted: int in [RunMap.StopType.TREASURE, RunMap.StopType.SHOP if _run.gold >= cheapest else -1,
			RunMap.StopType.REST if hurt else -1, RunMap.StopType.ELITE if _autoplay_elite_ready() else -1,
			RunMap.StopType.EVENT, RunMap.StopType.ZONE]:
		for id: int in map.choices():
			if pick < 0 and int(_run.map.stop(id).type) == wanted:
				pick = id
	if pick < 0 and not map.choices().is_empty():
		pick = map.choices()[0]
	if pick < 0:
		_autoplay_fail("map_no_choice")
		return
	map.choose(pick)


## True if the party is fit for an elite fight (the same habit as a zone champion).
func _autoplay_elite_ready() -> bool:
	return ZoneAutoplay.is_ready(_autoplay_health())


## Autoplay at a campfire: rests when someone is hurt, else upgrades an item or trains.
func _autoplay_rest(rest: RestScreen) -> void:
	await get_tree().create_timer(AUTOPLAY_RETURN_S).timeout
	if not is_instance_valid(rest):
		return
	if _autoplay_hurt():
		rest.rest_now()
	elif not rest.upgradable().is_empty():
		rest.upgrade_now(rest.upgradable()[0])
	else:
		rest.train_now()
		_autoplay_spend_points()
	await get_tree().create_timer(AUTOPLAY_RETURN_S).timeout
	if is_instance_valid(rest):
		rest.leave()


## Autoplay in a shop: buys what it can afford; bought gear goes on whoever has room.
func _autoplay_shop(shop: ShopScreen) -> void:
	await get_tree().create_timer(AUTOPLAY_RETURN_S).timeout
	if not is_instance_valid(shop):
		return
	for i: int in shop.count():
		if shop.can_buy(i) and shop.buy(i) and shop.overlay() != null:
			_autoplay_settle(shop.overlay())
			if shop.overlay() != null:
				shop.overlay().close()
	print("Run shop: gold left %d, items %d" % [_run.gold, _run.backpack.entries.size()])
	await get_tree().create_timer(AUTOPLAY_RETURN_S).timeout
	if is_instance_valid(shop):
		shop.leave()


## True if a hero is at or under AUTOPLAY_REST_BELOW_PERCENT of their max HP, or the party as a
## whole is under AUTOPLAY_REST_AVERAGE_PERCENT.
func _autoplay_hurt() -> bool:
	for slot: int in _run.party_size():
		if _run.hp[slot] * 100 <= _run.max_hp(slot) * AUTOPLAY_REST_BELOW_PERCENT:
			return true
	return _autoplay_health().y < AUTOPLAY_REST_AVERAGE_PERCENT


## The party's state: x the weakest hero's HP percent of max, y the party's average HP percent, z the
## lowest hero level (ZoneAutoplay reads it).
@warning_ignore("integer_division")
func _autoplay_health() -> Vector3i:
	if _run == null:
		return Vector3i(100, 100, 99)
	var lowest := 100
	var lowest_level := 99
	var hp_sum := 0
	var max_sum := 0
	for slot: int in _run.party_size():
		lowest = mini(lowest, _run.hp[slot] * 100 / maxi(1, _run.max_hp(slot)))
		lowest_level = mini(lowest_level, _run.levels[slot])
		hp_sum += _run.hp[slot]
		max_sum += _run.max_hp(slot)
	return Vector3i(lowest, hp_sum * 100 / maxi(1, max_sum), lowest_level)


## Autoplay at an event: a careful player's pick (EventAutoplay), or Leave; an ambush page just
## fights.
func _autoplay_event(screen: EventScreen) -> void:
	await get_tree().create_timer(AUTOPLAY_RETURN_S).timeout
	if not is_instance_valid(screen):
		return
	if screen.choice_count() > 0 and not _run.stop_done:
		var event := _run.event_of(_run.at)
		var decision := EventAutoplay.decide(_run, event, _autoplay_health())
		print("AUTOPLAY_EVENT %s -> %s" % [event.id, "choice %d" % int(decision.index) if int(decision.index) >= 0 else "leave"])
		if int(decision.index) >= 0:
			screen.choose(int(decision.index), int(decision.pick))
	await _autoplay_stop_gifts(screen)
	if is_instance_valid(screen):
		screen.leave()


## Autoplay at a treasure stop: opens the chest, settles the prize, goes on.
func _autoplay_treasure(screen: TreasureScreen) -> void:
	await get_tree().create_timer(AUTOPLAY_RETURN_S).timeout
	if not is_instance_valid(screen):
		return
	screen.open_chest()
	await _autoplay_stop_gifts(screen)
	if is_instance_valid(screen):
		screen.leave()


## Settles every backpack a stop screen opens for its gifts.
func _autoplay_stop_gifts(screen: StopScreen) -> void:
	while is_instance_valid(screen) and screen.is_settling():
		await get_tree().create_timer(AUTOPLAY_RETURN_S).timeout
		if is_instance_valid(screen) and screen.overlay() != null:
			_autoplay_settle(screen.overlay())
			if is_instance_valid(screen) and screen.overlay() != null:
				screen.overlay().close()
	await get_tree().create_timer(AUTOPLAY_RETURN_S).timeout


## Autoplay after a guard: takes the rarest piece, a rot-touched one when its price is bearable
## (GearBot, DESIGN.md 8.16).
func _autoplay_loot(loot: LootScreen) -> void:
	await get_tree().create_timer(AUTOPLAY_RETURN_S).timeout
	if is_instance_valid(loot):
		var index := GearBot.pick(loot.choices())
		if index < loot.choices().size():
			print("Run loot: took %s" % loot.choices()[index].id)
		loot.take(index)


## Autoplay: every hero spends their new attribute points evenly (DESIGN.md 8.2) and learns the
## skills it can (8.4).
func _autoplay_spend_points() -> void:
	if not _options.is_autoplay() or Net.is_client() or _run == null:
		return
	for slot: int in _run.party_size():
		if _run.has_tree(slot) and _run.free_skill_points(slot) > 0:
			_run.auto_skills(slot)
			print("Run skills: %s %s" % [_run.data.party[slot].id, str(_run.loadout[slot])])
		if _run.free_points(slot) > 0:
			_run.auto_spend(slot)
			print("Run points: %s level %d attributes %s" % [_run.data.party[slot].id, _run.levels[slot],
					str(_run.attributes[slot])])


## Autoplay on the party screen: new gear in hand goes on whoever has the most free slots.
func _autoplay_party(party: PartyScreen) -> void:
	await get_tree().create_timer(AUTOPLAY_RETURN_S).timeout
	if not is_instance_valid(party) or _run == null:
		return
	_autoplay_settle(party)
	if is_instance_valid(party) and party.is_inside_tree():
		party.close()


## Autoplay: the backpack opened over a zone with a find that did not fit.
func _autoplay_backpack(party: PartyScreen) -> void:
	await get_tree().create_timer(AUTOPLAY_RETURN_S).timeout
	if is_instance_valid(party) and party == _overlay:
		_autoplay_settle(party)
		if party == _overlay:
			party.close()


func _autoplay_settle(party: PartyScreen) -> void:
	var worn := _worn_count()
	var items := _run.backpack.entries.size()
	party.auto_settle()
	print("Run settle: worn %d -> %d, items %d -> %d, gold %d" % [worn, _worn_count(), items,
			_run.backpack.entries.size(), _run.gold])


## Autoplay on the map: uses healing items on whoever is hurt (like a player tidying up), and
## tonics at once.
func _autoplay_use_items() -> void:
	for e: Dictionary in _run.backpack.entries.duplicate():
		var item := e.item as ItemData
		if not item.usable_on_map() or item.effect == ItemData.Effect.MAX_HP_ONE:
			continue
		var low := 0
		for slot: int in _run.party_size():
			if _run.hp[slot] * _run.max_hp(low) < _run.hp[low] * _run.max_hp(slot):
				low = slot
		if _run.hp[low] * 100 <= _run.max_hp(low) * AUTOPLAY_REST_BELOW_PERCENT and _run.use_item(int(e.uid), low):
			print("Run use: %s on %s" % [item.id, _run.data.party[low].id])
	for e: Dictionary in _run.backpack.entries.duplicate():
		if (e.item as ItemData).effect != ItemData.Effect.MAX_HP_ONE:
			continue
		# A hero can only drink so many (tuning.tonic_max_per_hero): the one with the most left.
		var drinker := 0
		for slot: int in _run.party_size():
			if _run.tonics_left(slot) > _run.tonics_left(drinker):
				drinker = slot
		if _run.use_item(int(e.uid), drinker):
			print("Run use: %s" % (e.item as ItemData).id)


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
