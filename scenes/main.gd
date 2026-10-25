extends Node
## Entry point (run/main_scene). Shows the main menu (DESIGN.md 7.5): a new run (DESIGN.md 8),
## practice (the fight list), settings, quit. New Run and Practice open the players screen
## first (co-op, DESIGN.md 9.1); its roster goes to every fight. In a run the map screen leads to
## the stops: Fight stops, Elite stops (an elite group or the place's guard), events, rests, shops,
## treasure and the act's boss (DESIGN.md 8.22); RunState carries HP and gold from stop to stop.
## A Fight stop's fight opens with the First Strike ring on the place's name card (card #320): a
## GOOD or PERFECT press there starts it with First Strike.
## Online (DESIGN.md 9.2) the host's machine runs the run exactly as offline and tells the others
## what to show: every screen ("screen" messages with the run's state) and the fights' event
## batches. The others (clients) only show what arrives, never decide anything about
## the run: on run screens they watch while the host chooses. Their own heroes' fight choices and
## presses go to the host. Messages a client gets while a transition plays wait for it to end.
## R / "fight again" frees a practice fight and starts the same one again; Cancel on a practice
## fight's end screen goes back to the practice list. The options (and the F1 statistics they
## hold) survive restarts.
##
## User arguments (after "--"): --autoplay[=perfect|miss|mash], --quit-on-end, --seed=N,
## --encounter=ID (start that fight directly; autoplay without it or --run starts
## DEFAULT_ENCOUNTER_ID), --first-strike (with --encounter; a run's Fight stops get theirs from the
## ring, DESIGN.md 8.22),
## --run (start a new run at once; the seed also picks the map), --players=N (co-op with N pretend
## pads, for the bot), --host=N (host online and start a run once N players are in), --join=ADDRESS
## (join that host), --continue (pick up the saved run), --save-path=PATH (keep that save elsewhere;
## the bot saves only with it), --oath=N (play the run at oath N; also unlocks it on the players
## screen).

## Where a run fight's end screen leads (_after_run_fight): the run's end, the map, the party screen
## holding a Fight stop's drop that did not fit, or the spoils.
enum AfterFight { END, MAP, PARTY, SPOILS }

const DEFAULT_ENCOUNTER_ID := "husk_fight"
const TUNING_PATH := "res://data/tuning/tuning.tres"
const VISUALS_PATH := "res://data/presentation/combat_visuals.tres"
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
## Autoplay, a friend's bot (card #314): a choice the host could not take yet (a find in hand still
## settling, say) is asked again this often, this many times, while the screen stays up.
const AUTOPLAY_ASK_AGAIN_S: float = 2.0
const AUTOPLAY_ASK_TRIES: int = 10
## Autoplay on the map: a rest is picked when someone is at or under this percent of max HP, or the
## party averages under AUTOPLAY_REST_AVERAGE_PERCENT. An elite stop is only taken while the party is
## healthy (RunAutoplay.is_ready). These are the bot's habits, not game rules.
const AUTOPLAY_REST_BELOW_PERCENT: int = 60
const AUTOPLAY_REST_AVERAGE_PERCENT: int = 75
const QUIT_AUDIO_RELEASE_S: float = 0.3
## Online client: the "host is choosing" line over watched run screens.
const WATCH_TEXT_SIZE: int = 26
const WATCH_MARGIN_PX: float = 24.0
## The "P2 away" chip (card #205): above the pause menu, under the screen fades; its countdown
## is redrawn this often (host).
const AWAY_LAYER: int = 55
const AWAY_REFRESH_S: float = 0.25
## --drop-in-fight (dev): how often the bot looks for a fight, and how far into it it drops.
const AUTOPLAY_DROP_POLL_S: float = 0.5
const AUTOPLAY_DROP_INTO_FIGHT_S: float = 6.0
## The autoplay bots' First Strike luck (DESIGN.md 8.22) repeats with --seed: the seed times this
## plus the stop's number.
const FIRST_STRIKE_BOT_SALT: int = 1000003
## Online friend dropping in (card #304): the Join screen's line while the host catches them up.
const JOINING_STATUS := "Joining the game ..."
## Online Save & Quit (card #313): the friends' main menu notice (with the save picture), and the
## host's.
const HOST_SAVED_NOTICE := "Host saved the run"
const RUN_SAVED_ONLINE_NOTICE := "Run saved: Host to continue"
## Online: the host's screens that are a fight going on (kept as _net_fight, so a friend who gets in
## mid-fight is shown it), and the run screens a friend watches (_watched_screen_builder builds them).
const NET_FIGHT_SCREENS: Array[String] = ["final_fight", "stop_fight"]
const WATCHED_SCREENS: Array[String] = ["map", "rest", "shop", "loot", "party", "run_end", "event", "treasure",
		"start_relics"]
## Online: the screens whose choices go in turns (card #314, DESIGN.md 9.2): each new one belongs to
## the next seated player, and its message carries the turn ({"key", "peer", "player"}).
const CHOICE_SCREENS: Array[String] = ["map", "rest", "shop", "loot", "event", "treasure"]
## The whose-turn chip: the person sign's size.
const TURN_ICON_PX: float = 30.0
## Online friend (card #314): what becomes of a find the host handed us to place (_gift_step): open
## the backpack with it now, keep it until a screen that can take it is up, or let it go.
enum GiftStep { HOLD, WAIT, DROP }
## Host (card #314): what becomes of a find owed to a friend when the turn changes (_owed_step).
enum OwedStep { KEEP, HAND, TAKE_BACK }

var _encounters: Array[EncounterData] = []
var _encounter: EncounterData
var _tuning: Tuning
var _visuals: CombatVisuals
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
var _transition: ScreenTransition
## The run in progress (null outside a run).
var _run: RunState
## The oath the next run is played at (DESIGN.md 8.15): the players screen's pick, or --oath=N.
var _oath: int = 0
var _busy: bool = false
## Who plays and which heroes each player has (DESIGN.md 9.1).
var _players: PlayerRoster
## The device of the last button press (it becomes P1 on the players screen).
var _last_device: int = PlayerRoster.KEYBOARD
## Local co-op: the card shown while a player's pad is gone, and whether the fight should pause
## for it as soon as the current move ends.
var _pad_overlay: PadLostOverlay
var _pad_pause_wanted: bool = false
## Local co-op mid-run (cards #304, #311): a roster change waiting for the fight's next quiet
## moment (the bot's; the Players overlay is already paused), why it happens, and whether the pause
## that fight reaches was asked for it.
var _pending_roster: PlayerRoster = null
var _pending_why: String = ""
var _roster_pause_wanted: bool = false
## A pause menu (or focus loss) asked the fight to pause (so a roster pause landing at the same
## moment still opens the menu; presses meanwhile do not count as play).
var _menu_pause_wanted: bool = false
## The device that last pressed while the game itself was played (not a menu over it, not a pause
## or Back press): P1's real device when a friend joins a solo run.
var _play_device: int = PlayerRoster.ANY
## Online: the seed of the next fight (the host picks it), client messages waiting for the current
## transition, combat batches that arrived before their fight was built (kept per fight), the last
## screen the host sent (rebuilt when the run changes), and the run state the host sent last.
var _net_seed: int = -1
var _net_queue: Array[Dictionary] = []
var _combat_inbox := FightInbox.new()
var _net_screen: Dictionary = {}
var _sent_run: Dictionary = {}
## Online: whose turn it is, a chip over the run's choice screens (card #314).
var _watch_layer: CanvasLayer
var _watch_label: Label
var _watch_icon: UiGlyph
## Host, online (card #314): whose turn it is to choose (the referee).
var _turns := ChoiceTurns.new()
## Online: the turn now, as the host sent it ({"key", "peer", "player"}; {} offline or before one).
var _turn: Dictionary = {}
## Host: friends' choices that came during a transition, applied once it is over (in order).
var _choice_queue: Array[Dictionary] = []
## Host: the last choice screen sent (the map, a stop, the spoils), with its turn:
## a friend's choice made while the host has its party screen open over it goes back there first.
var _net_choice: Dictionary = {}
## Host: each find handed to a friend gets the next number (_gift_no), so a placing meant for an
## earlier one is never applied to it; _gift_peer is the machine it is with now (0: none).
var _gift_no: int = 0
var _gift_peer: int = 0
## Online friend: a find the host handed us that waits for a screen that can take it (the party
## screen, the shop's Sell backpack or a transition was up when it came); {} when none. _gift_held is
## the number of the find in hand now (in _gift_overlay, the backpack opened with it), _gift_done the
## newest one placed or left (a copy sent again is let go).
var _pending_gift: Dictionary = {}
var _gift_held: int = 0
var _gift_done: int = 0
var _gift_overlay: PartyScreen
## Online friend's bot: the shop shelves it already bought from on this shop turn ({"key", "shelves"},
## _bot_first_buy).
var _bot_shelves: Dictionary = {}
## The tutorial while it runs (DESIGN.md 7.8), else null.
var _tutorial: TutorialRunner
## What the Fight stop's enemy drops (null: nothing; DESIGN.md 8.22).
var _drop: ItemData
## Where the run fight takes place (the act's boss lair, the stop's place).
var _fight_look: StageLook
## The place's air of the run fight being built; empty for a boss.
var _fight_air: Array[ZoneAmbientData] = []
## Shown on the main menu next time (why an online game ended).
var _notice: String = ""
## Bumped when an online game ends, so a transition that was under way stops after its fade.
var _flow_gen: int = 0
## Client: the host's seed of the fight in the tree (0: none); its batches go straight to it,
## every other batch waits in _combat_inbox for its own fight (cards #205, #304).
var _combat_fight: int = 0
## Client: the run's end arrived (the host may go now).
var _client_done: bool = false
## Client: we got in mid-run (dropped in, or back with a token) and our heroes are not ours yet; the
## catch-up point we last told the host about ("f<seed>" or "p<screens>"), and how many screens
## we have shown (so each place screen is told once).
var _seat_wait: bool = false
var _seat_sent_key: String = ""
var _screens_seen: int = 0
## Online friend: their own Relic collection when the host's run started (card #281). The run plays
## with the host's bag; what it finds is banked on top of this.
var _own_start: RelicCollection = null
## The run seed _own_start was taken for: a seat taken back mid-run (the host sends run_start again)
## keeps it, so the run's finds are measured from the same start.
var _own_start_seed: int = -1
## Online friend who joined mid-run (card #304): the run's Relics (id -> 1) when they joined; only
## what comes after is theirs to keep. Empty: there from the start. `_join_pending`: the baseline is
## taken from the first run state that arrives.
var _join_relics: Dictionary = {}
var _join_pending: bool = false
## Host: the last place screen sent (map, shop ...) and the fight going on (stop_fight or
## final_fight message; empty between fights), so a player who joins again is shown where we are.
var _net_place: Dictionary = {}
var _net_fight: Dictionary = {}
## Client: the next fight is one we joined again in the middle of (it waits for the host's resume).
var _combat_resync: bool = false
## "P2 away" while a player's connection is gone (card #205).
var _away_layer: CanvasLayer
var _away_label: Label
var _away_refresh_s: float = 0.0
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
## The weather of the run fight being built (null: clear, or not a run fight).
var _fight_weather: WeatherData = null
## The place the run fight going on is fought in (its name; "" for the act's boss): the Rot
## Journal's "met at" (DESIGN.md 8.22).
var _fight_place: String = ""
## The "saved by another build" notice was shown once this session (the file stays, so it must not
## nag on every visit to the main menu).
var _mismatch_told: bool = false
## The picture before _notice on the main menu (a PauseMenu.RowGlyph kind, "" : none), shown with it once.
var _notice_glyph: StringName = &""
## Host: the run going on was continued from the online slot (card #313): every friend who gets into it
## counts as late (what they banked from it before is theirs already, so it is never banked twice).
var _continued_run: bool = false
## Host: Save & Quit online was pressed (card #313): until the main menu nothing writes or deletes the
## online slot (online the fight or screen under the pause may still end while the menu fades in).
var _put_away: bool = false
## The host's players screen's word on the online slot ("" : none): kept from another version, or
## broken and deleted (card #313).
var _online_save_note: String = ""
## The First Strike ring on the Fight stop's name card now (DESIGN.md 8.22, card #320; null: none),
## and the opening the next run fight starts with: a Fight stop's ring's, NORMAL for every other
## fight (the fight it goes into uses it up).
var _first_strike_ring: FirstStrikeRing = null
var _run_opening: CombatSetup.Opening = CombatSetup.Opening.NORMAL
## Online friend: the host's First Strike result ({fight: its seed, opening, word}; {}: none yet).
var _net_opening: Dictionary = {}
## The starting Relics step (DESIGN.md 8.24, card #328): true while it goes on, and the host's wait
## for its friends' picks (a newer step or its end stops an older wait).
var _start_open: bool = false
var _start_wait_gen: int = 0
## Host, online: the heroes each friend picks for in this step (peer -> hero slots), fixed when it
## began: a friend who drops in later gets no starting Relic.
var _start_pickers: Dictionary = {}
## Online friend: the host's "Start relics:" line is still to be logged for this game (a game this
## machine joined at its start; the host logs it even when it skips the step, which never comes here).
var _start_log_due: bool = false


func _ready() -> void:
	HudStyle.load_fonts()
	_tuning = load(_tuning_path()) as Tuning
	_visuals = load(VISUALS_PATH) as CombatVisuals
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
	if _encounters.is_empty() or _tuning == null:
		push_error("Main: could not load the encounters in %s or %s" % [FightSelect.ENCOUNTER_DIR, TUNING_PATH])
		return
	if _run_data == null:
		push_error("Main: could not load the run %s" % RUN_PATH)
	if _visuals == null:
		push_warning("Main: could not load %s, using built-in presentation defaults" % VISUALS_PATH)
		_visuals = CombatVisuals.new()
	if _map_look == null:
		push_warning("Main: could not load %s, using built-in map defaults" % MAP_VISUALS_PATH)
		_map_look = MapVisuals.new()
	_transition = ScreenTransition.new()
	_transition.name = "Transition"
	add_child(_transition)
	_transition.setup(_visuals)
	var tips := load(TIPS_PATH) as TipSet
	if tips == null:
		push_warning("Main: could not load %s, no loading tips" % TIPS_PATH)
	else:
		_transition.setup_tips(tips, _branding.logo_path)
	_build_watch_layer()
	_build_away_chip()
	Net.message_received.connect(_on_net_message)
	Net.peer_joined.connect(_on_net_peer_joined)
	Net.peer_left.connect(_on_net_peer_left)
	Net.peer_away.connect(_on_net_peer_away)
	Net.peer_rejoined.connect(_on_net_peer_rejoined)
	Net.peer_dropped_in.connect(_on_net_peer_dropped_in)
	Net.host_lost.connect(_on_net_host_lost)
	Net.refused.connect(_on_net_refused)
	Net.drop_in_check = _drop_in_refusal
	_options = CombatOptions.from_args(DevArgs.user_args(), _tuning)
	# A friend's seat in a host's saved run (card #313): a bot keeps one only with --seat-path.
	Net.seat_file = _options.seat_path if not _options.seat_path.is_empty() \
			else ("" if _options.is_autoplay() else SeatFile.PATH)
	if _options.shots_every_s > 0.0:
		var shooter := ScreenShooter.new()
		shooter.name = "Shots"
		add_child(shooter)
		shooter.setup(_options.shots_every_s, _options.screen if not _options.screen.is_empty() else "game")
	if _options.perf_every_s > 0.0:
		var perf := PerfLog.new()
		perf.name = "PerfLog"
		add_child(perf)
		perf.setup(_options.perf_every_s)
	# --players=N: pretend pads 0 to N-1 (only the bot presses them). With --pad-join-after P1 is pad 0
	# too, so the pad that joins later is the next one.
	var p1_pad := _options.players > 1 or _options.pad_join_after_s > 0
	_players = PlayerRoster.solo(_hero_names().size(), 0 if p1_pad else PlayerRoster.KEYBOARD)
	for pad: int in range(1, _options.players):
		_players.join(pad)
	if _options.is_autoplay():
		print("Autoplay: %s%s players: %d" % [_options.autoplay_mode, " (quit on end)" if _options.quit_on_end else "",
				_players.player_count()])
		if _options.pad_join_after_s > 0:
			_autoplay_pad_roster_later(true)
		if _options.pad_leave_after_s > 0:
			_autoplay_pad_roster_later(false)
	if _options.host_players > 0:
		_host_online()
		if _options.end_after_s > 0:
			_autoplay_end_later()
		return
	if not _options.join_address.is_empty():
		_show_join()
		if _options.join_after_s > 0:
			_autoplay_join_later(_options.join_address)
		else:
			_on_join_requested(_options.join_address)
		if _options.leave_after_s > 0:
			_autoplay_leave_later()
		if _options.drop_after_s > 0:
			_autoplay_drop_later()
		if _options.crash_after_s > 0:
			_autoplay_crash_later()
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
	var wanted := _options.encounter_id
	if wanted.is_empty() and _options.is_autoplay():
		wanted = DEFAULT_ENCOUNTER_ID
	if wanted.is_empty():
		_show_intro()
		return
	for i: int in _encounters.size():
		if _encounters[i].id == wanted:
			_select_index = 1 + i  # after the tutorial card
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
		"controller":
			_show_controller_notice(_show_title, true)
		"calibration_offer":
			_show_main_menu()
			_offer_calibration(false)
		"credits":
			_show_credits()
		"glossary":
			_show_glossary()
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
		"skills_tree":
			_show_real_tree(2)
		"party_relics":
			_show_sample_party_relics()
		"relics":
			_show_relics(_sample_collection())
		"start_relics":
			_show_sample_start_relics()
		"tutorial":
			_start_tutorial()
		"first_strike":
			_show_sample_first_strike()
		"map":
			_show_sample_map(2)
		"map_start":
			_show_sample_map(0)
		"map_act2":
			_show_sample_map(1, 1)
		"map_act3":
			_show_sample_map(1, 2)
		"shop", "campfire", "event", "treasure":
			_show_sample_stop(screen_name)
		"pact":
			# The starting pact of a run that is not the first (card #285), for pictures.
			_run = RunState.begin(_run_data, _tuning, 3, 0, _sample_collection())
			_show_event("", true)
		"run_end":
			# A lost run's end with each hero's defence and a co-op tag (cards #283, #284), for pictures.
			_run = RunState.begin(_run_data, _tuning, 3, 0, _sample_collection())
			_run.add_defence([[14, 3, 2, 5], [6, 9, 1, 3], [4, 2, 6, 8]])
			_run.add_relic(_run_data.gear[20])
			_run.result = RunState.DEFEAT
			_show_run_end()
		"players_in_run":
			# The Players overlay over the pause menu, a keyboard P1 and a pad P2 (cards #304, #311).
			_show_sample_map(2)
			_players = PlayerRoster.solo(_hero_names().size(), PlayerRoster.KEYBOARD)
			_players.join_midrun(0)
			_open_pause()
			_on_pause_players()
		"pause_players":
			# The pause menu with its Players row (card #304).
			_show_sample_map(2)
			_open_pause()
		"calibration":
			_show_settings()
			(_screen as SettingsScreen).open_calibration()
		"controls":
			_show_settings()
			(_screen as SettingsScreen).open_section(SettingsScreen.Section.CONTROLS)
		"controls_vibration":
			# The Controller page with its Vibration row chosen (card #299).
			_show_settings()
			var settings := _screen as SettingsScreen
			settings.open_page(SettingsScreen.ControlsPage.CONTROLLER)
			settings.select_row("vibration")
		_:
			if screen_name.begins_with("glossary_"):
				_show_glossary(screen_name.trim_prefix("glossary_"))
			else:
				_show_main_menu()


## --screen=map: a new run two stops in; map_start: before the first stop; map_act2 and map_act3: one
## stop into the second or third act (pictures of the map).
func _show_sample_map(stops: int, act: int = 0) -> void:
	_run = RunState.begin(_run_data, _tuning, 3)
	for i: int in act:
		_run.next_act()
	for i: int in stops:
		_run.go(_run.choices()[0])
	_show_map()


## --screen=first_strike: a Fight stop's name card with its First Strike ring (DESIGN.md 8.22, card
## #320), at a new run's first stop, for pictures. The ring starts over after each result and can be
## pressed; the card stays until the game is closed.
func _show_sample_first_strike() -> void:
	_run = RunState.begin(_run_data, _tuning, 3)
	_run.go(_run.choices()[0])
	var zone := _run.zone_now()
	_busy = true
	await _transition.fade_out()
	await _transition.show_tip(zone.display_name if zone != null else "",
			_new_first_strike_ring(FirstStrikeRing.Mode.LOOP))


## --screen=shop|campfire|event|treasure: a run standing at such a stop, with gold and a few items
## (pictures of the phase 15 stop screens, DESIGN.md 8.7 to 8.11).
func _show_sample_stop(kind: String) -> void:
	_run = RunState.begin(_run_data, _tuning, 3)
	_run.gold = 180
	var items := _run.items_by_id()
	_run.add_item(items["salve"])
	_run.add_item(items["feast"])
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


## --screen=party: a new run with some Relics given, the pack full and a curse on the party, the party
## screen open with a Holy Water in hand (for pictures of the pack).
func _show_sample_backpack() -> void:
	_run = RunState.begin(_run_data, _tuning, 3)
	var items := _run.items_by_id()
	_run.give_relic(_run_data.gear[0], 0)
	_run.give_relic(_run_data.gear[1], 0)
	_run.place_item(items["salve"], 0)
	_run.place_item(items["feast"], 1)
	_run.place_item(items["bomb"], 2)
	_run.place_item(items["smelling_salts"], 3)
	_run.add_curse(items["rotting_heart"])
	for id: String in ["silver_ring", "rot_gem"]:
		_run.add_item(items[id])
	_run.give_relic(_run_data.gear[3], 1)
	# Alder has levelled and has points to spend (the cards show "+N points", DESIGN.md 8.2).
	_run.add_xp(0, 200)
	_show_party("No room", true, {"item": items["holy_water"]})


## --screen=attributes: a run where Alder and Brin have levelled (Brin's points half spent), the
## attributes screen open over the party screen (for pictures of it). --screen=heroes: the same
## run on the party screen itself.
func _show_sample_attributes(open: bool = true) -> void:
	_run = RunState.begin(_run_data, _tuning, 3)
	_run.add_xp(0, 400)
	_run.add_xp(1, 200)
	_run.set_attributes(1, [1, 2, 1, 0, 1])
	_run.give_relic(_run_data.gear[3], 1)
	_show_party("", true)
	if open:
		(_screen as PartyScreen).open_attributes()


## A pretend Relic book for pictures (--screen=relics, start_relics): a few Relics found.
func _sample_collection() -> RelicCollection:
	var c := RelicCollection.new()
	for i: int in mini(14, _run_data.gear.size()):
		c.found[_run_data.gear[i].id] = true
	return c


## --screen=start_relics: the starting Relics step (card #328) of a run on the sample book, Alder's
## Relic taken and Brin choosing (for pictures; nothing is saved).
func _show_sample_start_relics() -> void:
	var book := _sample_collection()
	_run = RunState.begin(_run_data, _tuning, 3, 0, book)
	_players = PlayerRoster.solo(_hero_names().size(), PlayerRoster.KEYBOARD)
	var choices := _run.start_choices(book)
	if not choices.is_empty():
		_run.take_start_relic(0, choices[choices.size() - 1])
	_show_start_relics(book)


## --screen=party_relics: a run past act 1 where each hero has two Relics, Alder has levelled, and
## the party screen is open on its Relics tab (for pictures).
func _show_sample_party_relics() -> void:
	_run = RunState.begin(_run_data, _tuning, 3)
	_run.act = 1
	for slot: int in _run.party_size():
		for g: int in 2:
			_run.give_relic(_run_data.gear[slot * 3 + g], slot)
	_run.add_xp(0, 400)
	_show_party("", true)
	(_screen as PartyScreen).open_relics(0)


## --screen=skills: the skills screen on a run where each hero has a sample tree made of their
## own skills, arranged as in the skill tree proposal (docs/proposals/skill_trees.html), with
## Alder at level 4 (for pictures; the shipped heroes have no tree yet).
## Dev picture: hero `hero`'s real skill tree (phase 19 gave some branches a fourth skill), with
## points to spend.
func _show_real_tree(hero: int) -> void:
	_run = RunState.begin(_run_data, _tuning, 3)
	_run.add_xp(hero, 1200)
	_show_party("", true)
	(_screen as PartyScreen).open_skills()
	((_screen as PartyScreen).tab_node(PartyScreen.Tab.SKILLS) as SkillsTab).set_hero(hero)


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


## The studio intro when the game starts, then the "Controller recommended" notice, then the title
## screen (no music until then).
func _show_intro() -> void:
	var boot := load(BOOT_PATH) as BootData
	if boot == null:
		push_warning("Main: could not load %s, no intro" % BOOT_PATH)
		_show_controller_notice(_show_title)
		return
	var intro := IntroScreen.new()
	intro.name = "Intro"
	intro.setup(boot)
	intro.done.connect(func() -> void:
		intro.queue_free()
		_show_controller_notice(_show_title))
	add_child(intro)


## The "Controller recommended" notice (card #167), then `next`. Left out when BrandingData says so
## (no hold time, or a pad is already plugged in and the data asks to skip it) and never in autoplay
## (the bot never reaches the intro). `force`: the --screen=controller picture shows it whatever
## the data says.
func _show_controller_notice(next: Callable, force: bool = false) -> void:
	if _options.is_autoplay() or not (force or ControllerNotice.is_due(_branding, not _connected_pads().is_empty())):
		next.call()
		return
	var notice := ControllerNotice.new()
	notice.name = "ControllerNotice"
	notice.setup(_branding)
	notice.done.connect(func() -> void:
		notice.queue_free()
		next.call())
	add_child(notice)


## The title screen (card #82): any button fades to the main menu.
func _show_title() -> void:
	var title := TitleScreen.new()
	title.name = "Title"
	title.setup(_branding)
	title.done.connect(_fade_to.bind(_show_main_menu))
	_show_screen(title)


func _process(delta: float) -> void:
	if Net.is_host():
		_net_host_tick()
		if not _busy and not _choice_queue.is_empty():
			var waiting: Dictionary = _choice_queue.pop_front()
			_on_friend_choice(int(waiting.peer), waiting.payload as Dictionary)
		_away_refresh_s += delta
		if _away_layer.visible and _away_refresh_s >= AWAY_REFRESH_S:
			_away_refresh_s = 0.0
			_update_away_chip()
	elif Net.is_client() and not _pending_gift.is_empty():
		_offer_pending_gift()
	if not _options.is_autoplay():
		_watch_pads()
		MouseCursor.set_menus_allowed(_mouse_wanted())


## True on every menu (the main menu, run screens, pause, settings) and false while a fight is
## being played: that is a keyboard and pad game, so the mouse pointer stays hidden there (card #202).
func _mouse_wanted() -> bool:
	if _pause != null or _prompt != null:
		return true
	for child: Node in get_children():
		if child is SettingsScreen:
			return true
	return not (_combat != null and _combat.is_inside_tree())


# --- screens ----------------------------------------------------------------------------------

## Frees whatever is shown (fight, screen, prompt) and shows `screen`, if any.
func _show_screen(screen: Node) -> void:
	_close_pad_overlay()
	_free_combat()
	_free_screen()
	if screen != null:
		_screen = screen
		add_child(screen)
		Sfx.play_weather("")
		var song := _music.run_path if _is_run_screen(screen) and not _music.run_path.is_empty() else _music.menu_path
		if screen is CreditsScreen and not _music.credits_path.is_empty():
			song = _music.credits_path
		if screen is RunEndScreen and _run != null:
			var end := _music.victory_path if _run.result == RunState.VICTORY else _music.defeat_path
			if not end.is_empty():
				song = end
		Sfx.play_music(song, _music.volume_db)
	# Online, whose turn it is (card #314): over the choice screens only. Anyone can change the
	# backpack (DESIGN.md 8.1), so the party screen has no turn.
	_update_watch_chip()


func _free_screen() -> void:
	_free_pause()
	if _screen != null:
		_screen.queue_free()
		_screen = null


## Fades to black, runs `build` (which shows the next thing), and fades back in. With a
## `tip_title` a loading card (that title and a tip, card #86) shows over the black and `build` runs
## at its end, so a fight starts when it is seen. `swirl`: into a fight, the screen swirls into the
## black (with its sound) instead of fading. How long the card stays (DESIGN.md 7.7):
## - with `ring`, a Fight stop's First Strike ring (8.22) on the card: until the ring is done (its
##   press and result; a friend's waits for the host's), on every machine, the bot's too, and the
##   tips' hold_ms does not apply;
## - otherwise the tips' hold_ms, on the host or a local game only: online clients and the bot do
##   not hold it (the host already held it before sending the screen).
func _fade_to(build: Callable, tip_title: String = "", swirl: bool = false, ring: FirstStrikeRing = null) -> void:
	if _busy:
		_drop_first_strike_ring(ring)
		return
	_busy = true
	var gen := _flow_gen
	if swirl:
		Sfx.play("encounter_swirl")
		await _transition.swirl_out()
	else:
		await _transition.fade_out()
	if gen != _flow_gen:
		_drop_first_strike_ring(ring)
		_transition.fade_in()
		_end_busy()
		return
	if not tip_title.is_empty() or ring != null:
		await _transition.show_tip(tip_title, ring)
		if ring != null:
			while gen == _flow_gen and is_instance_valid(ring) and ring.is_inside_tree() and not ring.is_finished():
				await get_tree().process_frame
		else:
			var tips := load(TIPS_PATH) as TipSet
			if tips != null and tips.hold_ms > 0 and not Net.is_client() and not _options.is_autoplay():
				await get_tree().create_timer(float(tips.hold_ms) / 1000.0).timeout
		if gen != _flow_gen:
			_first_strike_ring = null
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


## The main menu.
func _show_main_menu() -> void:
	_end_tutorial()
	_run = null
	_fight_weather = null
	_checkpoint = {}
	_checkpoint_in_stop = false
	_continued_run = false
	ButtonPrompts.set_both(false)
	if Net.is_online():
		_leave_online()
	# An online Save & Quit is done: the slot is the player's to use again (card #313).
	_put_away = false
	var saved := _valid_save()
	var menu := MainMenu.new()
	menu.name = "MainMenu"
	# A saved run is where the cursor rests until the player picks something else.
	var start := MainMenu.CONTINUE if not saved.is_empty() and not _menu_used else _menu_item
	# Practice (any fight on its own) is a test tool: only debug builds list it (card #208).
	menu.setup(_branding, start, _notice, not saved.is_empty(), OS.is_debug_build(), _notice_glyph)
	_notice = ""
	_notice_glyph = &""
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
		MainMenu.GLOSSARY:
			_show_glossary.call_deferred()
		MainMenu.JOURNAL:
			_show_journal.call_deferred()
		MainMenu.RELICS:
			_show_relics.call_deferred()
		MainMenu.SETTINGS:
			_show_settings.call_deferred()
		MainMenu.CREDITS:
			_show_credits.call_deferred()
		MainMenu.QUIT:
			_quit_game()


## Main menu, New Run: the tutorial offer (once), then the lag calibration offer (once),
## then the players screen, then the run. Only one offer per press: a player who says yes to the
## tutorial is asked about the calibration on their next New Run (DESIGN.md 3.2, 7.8).
func _start_new_run() -> void:
	if not PlayerSettings.tutorial_offered() and not _options.is_autoplay():
		_offer_tutorial()
	else:
		_new_run_players()


## After the offers: the players screen of a new run (or the calibration offer first, if it is due).
func _new_run_players() -> void:
	if _calibration_offer_wanted():
		_offer_calibration()
	else:
		_new_run_players_after_offer()


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
	_reset_play_device()
	# Practice has no Oath row: the pick for the next run stays as it was.
	if _screen is LobbyScreen and not (_screen as LobbyScreen).oaths.is_empty():
		_oath = oath
	_refresh_prompt_mix()
	var names := PackedStringArray()
	for device: int in _players.devices:
		names.append(PlayerRoster.device_name(device))
	print("Players: %d (%s)" % [_players.player_count(), ", ".join(names)])
	next.call()


## Again at the run end (card #284): the players screen once more with the same seats and oath.
## Online the host keeps the friends connected and sends them to their players screen to wait for
## its Start; a friend who presses it first waits there.
func _play_again() -> void:
	_run = null
	_checkpoint = {}
	_checkpoint_in_stop = false
	_continued_run = false
	_forget_own_start()
	if Net.is_client():
		_client_done = false
		# A friend who dropped into the last run is there from this one's start (card #304).
		Net.joined_mid_run = false
		_seat_wait = false
		_seat_sent_key = ""
		_combat_inbox.clear()
		_show_client_lobby()
		return
	if Net.is_online():
		_set_drop_in(false)
		# A friend still away mid-run is let go: Again starts over with the ones here.
		for peer: int in Net.seats.away_peers():
			Net.seats.remove(peer)
			_players.drop_peer(peer)
		# Only players still catching up can be marked away now: they play their seats from the start.
		for player: int in _players.away.duplicate():
			_players.set_back(_players.peers[player])
		_update_away_chip()
		Net.closed = false
		_show_host_lobby()
		Net.broadcast("again", _lobby_message(_players, _oath))
		return
	# Whoever pressed Again, the players screen opens as player 1's, so nobody's seat is dropped.
	if _players.player_count() > 1 and _players.devices.has(_last_device):
		_last_device = _players.device_of_player(0)
	_new_run_players_after_offer()


## A friend's start collection is for one run only (card #281), and so is a late joiner's baseline
## (card #304).
func _forget_own_start() -> void:
	_own_start = null
	_own_start_seed = -1
	_join_relics = {}
	_join_pending = false


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
	settings.setup(_tuning, _visuals, true)
	settings.closed.connect(_show_main_menu.call_deferred)
	settings.progress_reset.connect(_reset_progress)
	_show_screen(settings)


## Settings > Reset progress (DESIGN.md 8.17): the Relic book (8.24), the unlocked oaths and a saved
## run go; settings, controls and the Journal stay. A dev screen (--screen=settings) never wipes
## anything.
func _reset_progress() -> void:
	if not _options.screen.is_empty():
		return
	if _relics_io_ok():
		RelicFile.delete(_relics_path())
	PlayerSettings.reset_oath_unlocks()
	if _save_slot_ok():
		RunSave.delete(_run_save_path())
	# The online slot too (card #313): it is offline here, so the path above was the local one.
	if _online_slot_ok():
		RunSave.delete(_online_save_path())
	_mismatch_told = false
	print("Progress reset")


## The Glossary (card #207), from Extras: the book of the game's terms. Back returns to Extras.
## `topic` (a topic id) opens it on that topic (the --screen=glossary_<topic> dev picture).
func _show_glossary(topic: String = "") -> void:
	var screen := GlossaryScreen.new()
	screen.name = "Glossary"
	screen.setup(GlossaryScreen.load_glossary(), topic)
	screen.closed.connect(_show_main_menu.call_deferred)
	_show_screen(screen)


## The Rot Journal (card #200): what the player has met, read from the journal file when it opens.
func _show_journal() -> void:
	var screen := JournalScreen.new()
	screen.name = "Journal"
	screen.setup(JournalFile.load_journal(_journal_path()).journal as RotJournal, JournalScreen.load_enemies())
	screen.closed.connect(_show_main_menu.call_deferred)
	_show_screen(screen)


## The Relic book (DESIGN.md 8.17, 8.24, card #328): every Relic this machine found, read from its
## file; it only shows. `sample`: a dev screen's pretend book.
func _show_relics(sample: RelicCollection = null) -> void:
	var collection := sample if sample != null else RelicFile.load_or_empty(_relics_path())
	var screen := RelicsScreen.new()
	screen.name = "Relics"
	screen.setup(collection, _run_data.gear)
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
	var where := _journal_place(_encounter.display_name if _encounter != null else "",
			_fight_place if _run != null else "")
	if not JournalFile.record(fight, where, _journal_path()):
		push_warning("Main: the Rot Journal could not be written")


## Where the Rot Journal says a fight was met, pure: the place of a run's Fight, Guard, elite or
## ambush fight (`run_place`, DESIGN.md 8.22; none for a boss in its lair or a practice fight), else
## the fight's own name.
static func _journal_place(fight_name: String, run_place: String) -> String:
	return run_place if not run_place.is_empty() else fight_name


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
	select.setup(_encounters, _select_index, load(TUTORIAL_PATH) as TutorialData)
	select.chosen.connect(_on_fight_chosen)
	select.tutorial_chosen.connect(func() -> void:
		_select_index = 0
		_fade_to.call_deferred(_start_tutorial))
	select.back.connect(_show_main_menu.call_deferred)
	_show_screen(select)


func _on_fight_chosen(encounter: EncounterData) -> void:
	_select_index = (_screen as FightSelect).selected_index()
	_encounter = encounter
	_start_combat.call_deferred()


# --- fights -----------------------------------------------------------------------------------

## Builds a fight: a practice fight or a run fight (a Fight, Guard, elite, ambush or boss fight,
## DESIGN.md 8.22).
func _start_combat() -> void:
	_free_combat()
	_free_screen()
	# The whose-turn chip belongs to the run's choice screens, never over a fight (it draws above the
	# fight's HUD); the next choice screen shows it again.
	if _watch_layer != null:
		_watch_layer.visible = false
	_combat = COMBAT_SCENE.instantiate() as CombatController
	var continue_to := Callable()
	if _run != null:
		# A Fight stop's First Strike ring gave its opening (DESIGN.md 8.22); every other run fight opens
		# normally.
		_combat.configure(_encounter, _tuning, _visuals, _options, _fight_look, _run_opening, _fight_air)
		_run_opening = CombatSetup.Opening.NORMAL
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
		_combat.configure_drop(_drop)
	_combat.configure_players(_players)
	if Net.is_host():
		_combat.configure_online(CombatController.NetMode.HOST, _net_seed)
		_combat.seat_ready.connect(_return_seat)
	elif Net.is_client():
		_combat.configure_online(CombatController.NetMode.CLIENT, _net_seed)
		_combat_fight = _net_seed
		_combat.caught_up.connect(_send_seated_ready)
		if _combat_resync:
			# We got in mid-fight: the host sends the fight as it stands.
			_combat.expect_resume()
			_combat_resync = false
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
	if _run != null and _fight_weather != null:
		# A run fight's weather loop, quieter than its own volume (DESIGN.md 8.20, 8.22).
		Sfx.play_weather(_fight_weather.ambience_path,
				_fight_weather.ambience_volume_db + _fight_weather.fight_volume_offset_db)
	else:
		Sfx.play_weather("")
	# A guard (at a run's Elite stop, DESIGN.md 8.22) gets the boss song and its rage, as a boss does.
	var boss := _encounter != null and (_encounter.boss or _encounter.mini_boss)
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
		for batch: Dictionary in _combat_inbox.take(_net_seed):
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
	_set_drop_in(false)
	_bank_relics()
	_clear_run_save()


func _on_restart_requested() -> void:
	_start_combat.call_deferred()


func _free_combat() -> void:
	if _combat != null:
		if _combat.is_inside_tree():
			remove_child(_combat)
		_combat.queue_free()
		_combat = null
	_combat_fight = 0
	# A pause asked for that never came goes with the fight; a roster change waiting for it applies
	# now (a change is never lost).
	_menu_pause_wanted = false
	if _roster_pause_wanted:
		_roster_pause_wanted = false
		var roster := _pending_roster
		_pending_roster = null
		if roster != null and not _same_players(_players, roster):
			_apply_local_roster(roster, _pending_why)
		_pending_why = ""


# --- weather ----------------------------------------------------------------------------------

## The weather of a run fight: `rolled`, or the --weather=ID weather when that is given (dev tool;
## DESIGN.md 8.22: every run fight but the boss's).
func _weather_or_forced(rolled: WeatherData) -> WeatherData:
	return rolled if _options.weather_id.is_empty() else _forced_weather()


## The --weather=ID weather (null: "clear", or an id with no file, which fails a bot run).
func _forced_weather() -> WeatherData:
	if _options.weather_id.is_empty() or _options.weather_id == "clear":
		return null
	var path := "res://data/weather/%s.tres" % _options.weather_id
	var data := load(path) as WeatherData if ResourceLoader.exists(path) else null
	if data == null:
		# A typo must not quietly test clear weather.
		push_error("Main: no weather '%s' (data/weather/); the weather is clear" % _options.weather_id)
		_autoplay_fail("unknown weather %s" % _options.weather_id)
	return data


# --- the tutorial (DESIGN.md 7.8, card #131) --------------------------------------------------

## A question over the main menu hides the menu while it is open: the menu's gold letters showed
## through the prompt's dark backdrop (card #204, seen in a picture run).
func _hide_menu_behind(prompt: ConfirmPrompt) -> void:
	if not _screen is MainMenu:
		return
	var menu := _screen as MainMenu
	menu.visible = false
	prompt.tree_exited.connect(func() -> void:
		if is_instance_valid(menu):
			menu.visible = true)


## The first New Run asks once whether to play the tutorial first.
func _offer_tutorial() -> void:
	PlayerSettings.set_tutorial_offered(true)
	_prompt = ConfirmPrompt.new()
	_hide_menu_behind(_prompt)
	_prompt.name = "TutorialPrompt"
	_prompt.setup("Play the tutorial first?", "", "Tutorial", "Start the run")
	_prompt.answered.connect(func(yes: bool) -> void:
		_prompt.queue_free()
		_prompt = null
		if yes:
			_fade_to(_start_tutorial)
		else:
			_new_run_players())
	add_child(_prompt)


## True if a New Run should ask about the lag calibration now: once (PlayerSettings), not for a
## player who calibrated already, and never for the bot or an online game (an online client does not
## come through the main menu's New Run at all).
func _calibration_offer_wanted() -> bool:
	return not _options.is_autoplay() and not Net.is_online() and PlayerSettings.calibration_offer_due(
			PlayerSettings.calibration_offered(), PlayerSettings.is_calibrated())


## Asks once whether to measure the player's lag now (DESIGN.md 3.2). Yes runs the calibration
## screen, then goes on to the players screen; No goes straight on. `remember` false: a dev picture
## (--screen=calibration_offer) that must not use up the real once-only offer.
func _offer_calibration(remember: bool = true) -> void:
	if remember:
		PlayerSettings.set_calibration_offered(true)
	_prompt = ConfirmPrompt.new()
	_hide_menu_behind(_prompt)
	_prompt.name = "CalibrationPrompt"
	_prompt.setup("Calibrate your timing?", "About %d seconds" % _calibration_seconds(), "Calibrate now", "Not now")
	_prompt.answered.connect(func(yes: bool) -> void:
		_prompt.queue_free()
		_prompt = null
		if not remember:
			_show_main_menu()
		elif yes:
			_show_calibration_screen.call_deferred(_new_run_players_after_offer)
		else:
			_new_run_players_after_offer())
	add_child(_prompt)


## How long the lag calibration takes, in whole seconds (rounded up): the lead-in and every beat.
func _calibration_seconds() -> int:
	var ms := _visuals.calibration_lead_ms + _visuals.calibration_beats * _visuals.calibration_interval_ms
	@warning_ignore("integer_division")
	return (ms + 999) / 1000


## The players screen once the calibration offer is over (it is never asked twice, so this cannot
## loop back into the offer).
func _new_run_players_after_offer() -> void:
	_show_lobby(_fade_to.bind(_new_run), true)


## The lag calibration on its own screen, then `next`.
func _show_calibration_screen(next: Callable) -> void:
	var screen := CalibrationScreen.new()
	screen.name = "CalibrationScreen"
	screen.setup(_visuals, _tuning)
	screen.closed.connect(next, CONNECT_DEFERRED)
	_show_screen(screen)


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


## A fight paused: for a local roster change (cards #304, #311), the lost-pad card, the tutorial's
## card, or the pause menu.
func _on_combat_pause_reached() -> void:
	if _roster_pause_wanted:
		_roster_pause_wanted = false
		var roster := _pending_roster
		_pending_roster = null
		if roster != null and not _same_players(_players, roster):
			_apply_local_roster(roster, _pending_why)
		_pending_why = ""
		var someone_else := _pad_pause_wanted or _menu_pause_wanted or (_tutorial != null and _tutorial.pause_wanted())
		if not someone_else:
			# Deferred: this can come from inside the fight's event loop, which only plays the rest of
			# its queue once it has unwound (a resume from here would leave it stuck).
			_resume_quiet_pause.call_deferred()
			return
	# A menu asked for elsewhere is answered below or dropped (the lost-pad card, the tutorial).
	_menu_pause_wanted = false
	if _pad_pause_wanted:
		_pad_pause_wanted = false
		if _pause == null and _prompt == null:
			if not _lost_pad_players().is_empty():
				_show_pad_overlay()
			elif _combat != null:
				# The pad came back before the pause landed: no menu, the fight just goes on (deferred,
				# as for a roster change above).
				_resume_quiet_pause.call_deferred()
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

## Where the run is saved: online (the host) the online slot (card #313), else --save-path=PATH (dev
## tool) or the player's local slot. Two slots, so an online run never overwrites a local one.
func _run_save_path() -> String:
	if Net.is_online():
		return _online_save_path()
	return _options.save_path if not _options.save_path.is_empty() else RunSave.PATH


## The online slot (card #313): --online-save-path=PATH (dev tool) or the host's own.
func _online_save_path() -> String:
	return _options.online_save_path if not _options.online_save_path.is_empty() else RunSave.ONLINE_PATH


## True if this session may touch the save at all: a local run's slot, or online the host's online
## slot (card #313; a friend never saves), never the tutorial, never while an online Save & Quit goes
## home (_put_away), and the bot only with --save-path (online --online-save-path): it must never
## touch the player's save.
func _save_io_ok() -> bool:
	if _tutorial != null or _put_away:
		return false
	if Net.is_online():
		return Net.is_host() and (not _options.is_autoplay() or not _options.online_save_path.is_empty())
	return not _options.is_autoplay() or not _options.save_path.is_empty()


## True if this session may touch the online slot (card #313), hosting or not (Reset progress clears
## it from the main menu): the host's rules, never a dev screen.
func _online_slot_ok() -> bool:
	return _options.screen.is_empty() and _tutorial == null and not _put_away \
			and (not _options.is_autoplay() or not _options.online_save_path.is_empty())


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
## an opened chest): the checkpoint is written again, still inside the stop (card #197), and the
## run's Relics are banked with it.
func _save_stop_progress() -> void:
	if _run != null and _checkpoint_in_stop:
		_save_run(true)
	_bank_relics()


# --- Relics (DESIGN.md 8.17) ------------------------------------------------------------------

## The Relic collection's file: --relics-path=PATH (dev tool), else the player's.
func _relics_path() -> String:
	return _options.relics_path if not _options.relics_path.is_empty() else RelicFile.PATH


## True if this session reads and writes the player's Relic collection: not an online client (the
## host's Relics are everyone's; a client banks its own share, _client_relics_ok), not the tutorial,
## never a dev screen's sample run, and a bot only with --relics-path (it must never touch the
## player's file).
func _relics_io_ok() -> bool:
	return not Net.is_client() and _own_relics_ok()


## True if an online friend banks what the host's run finds into their own collection (card #281):
## the same rules as the host, on a client.
func _client_relics_ok() -> bool:
	return Net.is_client() and _own_relics_ok()


func _own_relics_ok() -> bool:
	return _tutorial == null and _options.screen.is_empty() \
			and (not _options.is_autoplay() or not _options.relics_path.is_empty())


## The Relic book a new run starts from (host or local): the player's, or a bot's pretend one
## (--relics=all gives every Relic found; a bot otherwise has none, like a first run).
func _run_collection() -> RelicCollection:
	var collection := RelicCollection.new()
	if _options.relics_mode == "all":
		collection = RelicCollection.all_of(_run_data.gear)
	elif _relics_io_ok() and _options.relics_mode != "none":
		collection = RelicFile.load_or_empty(_relics_path())
	return collection


## This machine's Relic book for the starting Relics (DESIGN.md 8.24, card #328): the host's or a
## local game's as _run_collection; an online friend's own, read when the host's run_start came
## (_own_start; --relics=all every Relic, a bot without --relics-path none).
func _own_book() -> RelicCollection:
	if not Net.is_client():
		return _run_collection()
	if _options.relics_mode == "all":
		return RelicCollection.all_of(_run_data.gear)
	if _options.relics_mode == "none" or _own_start == null:
		return RelicCollection.new()
	return _own_start


## Takes the run into the Relic book: when the run saves on the map, when a stop settles something,
## and when the run ends (won, lost or abandoned). The Relics found (never the starting ones, which
## came from a book, card #328): banking twice, or after Continue replays a stop, never adds any
## (DESIGN.md 8.19).
## An online friend banks too, into their own file (card #281): the Relics the run found on top of
## their own collection. A friend who joined mid-run banks only what came after they joined (card
## #304), and nothing before that baseline is known.
func _bank_relics() -> void:
	if _run == null:
		return
	if Net.is_client():
		if _own_start == null or _join_pending or not _client_relics_ok():
			return
		var found := _run.relic_ids_since(_join_relics)
		if RelicFile.bank(found, _relics_path()):
			print("Relics banked (own): %d" % found.size())
		return
	if not _relics_io_ok():
		return
	var ids := _run.relic_ids_since({})
	if RelicFile.bank(ids, _relics_path()):
		print("Relics banked: %d" % ids.size())


## The player number (1, 2, 3) who plays each hero, for the run end's defence rows; empty when one
## player plays them all (card #283).
func _hero_players() -> Array[int]:
	var out: Array[int] = []
	if _players == null or _players.player_count() <= 1:
		return out
	for slot: int in _run.party_size():
		out.append(_players.owner_of(slot) + 1)
	return out


## The fingerprint a save is checked against: data and version only, so a code-only update keeps a
## saved run (card #208; the online handshake still checks the code, Net.fingerprint).
func _save_fingerprint() -> String:
	if _content_fingerprint.is_empty():
		_content_fingerprint = DataHash.of_content()
	return _content_fingerprint


func _write_checkpoint() -> bool:
	if _checkpoint.is_empty():
		return false
	# The host's online save keeps its seats too (card #313): who held which hero, and their tokens.
	var seats := SavedSeats.capture(_players, Net.seats) if Net.is_host() else {}
	var saved := RunSave.save(_checkpoint, _save_fingerprint(), _checkpoint_in_stop, _players.player_count(),
			_run_save_path(), seats)
	if not saved:
		push_warning("Main: could not write the run save to %s" % _run_save_path())
	return saved


## The run ended or was abandoned: its save goes (online the host's online slot, card #313). Only on
## the real save slot: a dev screen's sample run (--screen=map and so on) has no save of its own and
## must never delete the player's.
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
	# The local slot only: online the host's players screen reads its own (_valid_online_save).
	if Net.is_online() or not _save_io_ok() or _run_data == null or _tuning == null or not RunSave.exists(_run_save_path()):
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
					print("Saved run kept, from another build: %s" % reason)
					_notice = "Saved run: another version (kept)"
				return {}
	RunSave.delete(_run_save_path())
	print("Saved run deleted: %s" % reason)
	if _notice.is_empty():
		_notice = "Saved run was broken (deleted)"
	return {}


## A new run would overwrite a save: a usable one, or one kept from another build.
func _save_in_the_way() -> bool:
	return not _valid_save().is_empty() or (_save_io_ok() and RunSave.exists(_run_save_path()))


## The saved online run the host's players screen offers to continue (card #313): {state (a RunState),
## in_stop, players, online (its seats)}, or {} if there is none. As for the local slot (_valid_save):
## a damaged file, or one RunState or its seats do not fit, is deleted; one written by another version
## of the game (config/version, or another save format) is kept and not offered. Either way
## _online_save_note says so on the players screen.
func _valid_online_save() -> Dictionary:
	_online_save_note = ""
	if not _online_slot_ok() or _run_data == null or _tuning == null or not RunSave.exists(_online_save_path()):
		return {}
	var loaded := RunSave.load_save("", _online_save_path(), RunSave.game_version(), true)
	var reason := ""
	match String(loaded.status):
		RunSave.LOADED:
			var state := RunState.from_dict(_run_data, _tuning, loaded.run as Dictionary)
			if state != null and not state.is_over() \
					and SavedSeats.restore(loaded.online as Dictionary, state.party_size()) != null:
				loaded["state"] = state
				return loaded
			reason = "it does not fit this version of the game"
		RunSave.MISSING:
			return {}
		_:
			reason = String(loaded.get("reason", "the file is damaged"))
			if bool(loaded.get("keep", false)):
				_online_save_note = "Saved run: another version (kept)"
				return {}
	RunSave.delete(_online_save_path())
	print("Saved online run deleted: %s" % reason)
	_online_save_note = "Saved run was broken (deleted)"
	return {}


## Online host: a new run would overwrite the online slot (a usable save, or one kept from another
## version).
func _online_save_in_the_way() -> bool:
	return not _valid_online_save().is_empty() or (_online_slot_ok() and RunSave.exists(_online_save_path()))


## The Continue button's line for a saved run (card #313): where it is, in a few words.
static func _continue_line_of(state: RunState) -> String:
	return "Act %d, Stop %d" % [state.act + 1, state.visited]


func _ask_overwrite_save() -> void:
	_prompt = ConfirmPrompt.new()
	_hide_menu_behind(_prompt)
	_prompt.name = "OverwritePrompt"
	_prompt.setup("Start a new run?", "The saved run is lost.", "New run", "Keep saved run")
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
	_reset_turns()
	_checkpoint = saved.run as Dictionary
	_checkpoint_in_stop = bool(saved.in_stop)
	_reset_play_device()
	print("Run continued: seed %d  act %d  stop %d%s" % [_run.run_seed, _run.act + 1, _run.visited,
			" (in progress)" if _checkpoint_in_stop else ""])
	Sfx.play("run_begin")
	_resume_where_saved()


## A continued run (local, or the host's online one, card #313) goes back where it was saved: into the
## stop it was saved in, from its start (a fight at the HP the party had on entering it), the starting
## Relics (card #328), the starting pact, or the map.
func _resume_where_saved() -> void:
	if _checkpoint_in_stop and not _run.current().is_empty():
		_enter_stop()
	elif _run.start_pending() and _run.at < 0:
		_fade_to(_begin_start_relics)
	elif _run.pact_pending and _run.at < 0:
		_fade_to(_show_event.bind("", true))
	else:
		_fade_to(_show_map)


## Pause menu, Save & Quit: the run stays in its slot and the game goes back to the main menu.
## Inside a stop the save already holds the state from when the stop was entered, and that is
## what is kept; on the map the state is saved as it is now. Online (the host, card #313) the friends
## go home too, keeping their seats (_save_quit_online).
func _on_pause_save_quit() -> void:
	if not _save_allowed():
		# Online the fight under the pause goes on: it may have decided the run since the pause opened
		# (its save is gone already). Nothing is saved: the pause closes on the run's own end.
		Sfx.play("locked")
		_on_pause_resumed()
		return
	if _gift_in_hand(_screen):
		# A find is still being placed (online maybe by a friend, card #314): the stop's last save holds
		# the choice without it. Save & Quit waits until it is in the backpack.
		Sfx.play("locked")
		return
	if Net.is_host():
		_save_quit_online()
		return
	var saved := false
	if _checkpoint_in_stop:
		saved = _write_checkpoint()
	else:
		saved = _save_run(false)
	_notice = "" if saved else "Could not save the run"
	_menu_item = MainMenu.CONTINUE
	_menu_used = true
	_free_pause()
	_fade_to(_show_main_menu)


## The "saved" message (card #313): the run as the save holds it (`checkpoint`: inside a stop, as the
## party entered it), which the friends bank from. Not the newest state: what the stop found since is
## found again when the Continue replays it, and banked then. Pure.
static func _saved_message(checkpoint: Dictionary) -> Dictionary:
	return {"run": checkpoint.duplicate(true)}


## True while `screen` is a stop's screen still handing out a find (its backpack open with it in hand,
## more to come, or online one handed to a friend to place): what it gives is not in the run yet.
static func _gift_in_hand(screen: Node) -> bool:
	return is_instance_valid(screen) and screen is StopScreen and (screen as StopScreen).is_settling()


## Host, Save & Quit online (card #313): the run goes into the online slot with its seats (the same
## checkpoint rules as a local run's), the friends are told ("saved", with the state the save holds:
## they bank from it, go to the main menu and keep their seat's token), and the host goes to the main
## menu. If the save could not be written the game simply ends for everyone ("menu"). From here on
## until the main menu nothing writes or deletes the slot (_put_away): online the fight or screen
## under the pause is held, but a message or a timer may still end it.
func _save_quit_online() -> void:
	var saved := _write_checkpoint() if _checkpoint_in_stop else _save_run(false)
	if saved:
		Net.broadcast("saved", _saved_message(_checkpoint))
	else:
		Net.broadcast("menu")
	_put_away = true
	_set_drop_in(false)
	_free_pause()
	_hold_behind_overlay(true)
	_choice_queue.clear()
	print("Run saved online: act %d  stop %d%s  seats %d" % [_run.act + 1, _run.visited,
			" (in progress)" if _checkpoint_in_stop else "", _players.player_count()])
	if _options.is_autoplay():
		print("AUTOPLAY_SAVED host ok=%d act=%d stop=%d in_stop=%d players=%d owners=%s" % [int(saved), _run.act + 1,
				_run.visited, int(_checkpoint_in_stop), _players.player_count(), _players.owners_text()])
	_notice = RUN_SAVED_ONLINE_NOTICE if saved else "Could not save the run"
	_notice_glyph = &"save" if saved else &""
	_menu_item = MainMenu.HOST_ONLINE
	_menu_used = true
	# A transition under way stops after its fade (it would build the next screen of the run).
	_flow_gen += 1
	while _busy:
		await get_tree().process_frame
	_fade_to(_show_main_menu)
	if _options.is_autoplay():
		print("AUTOPLAY_RESULT run_saved" if saved else "AUTOPLAY_RESULT host_ended")
		_autoplay_quit()


## Autoplay (--save-quit-at=N): the bot presses Save & Quit on arriving at stop N, once (online the
## host, card #313; a local bot needs --save-path). True if it did.
func _autoplay_save_quit_now() -> bool:
	if not _options.is_autoplay() or _options.save_quit_at <= 0 or _run == null or _run.visited != _options.save_quit_at \
			or Net.is_client() or not _save_allowed():
		return false
	print("AUTOPLAY_SAVE_QUIT at stop %d" % _run.visited)
	_on_pause_save_quit()
	if not Net.is_online():
		print("AUTOPLAY_SAVED local act=%d stop=%d in_stop=%d" % [_run.act + 1, _run.visited, int(_checkpoint_in_stop)])
		print("AUTOPLAY_RESULT run_saved")
		_autoplay_quit()
	return true


# --- the run ----------------------------------------------------------------------------------

func _new_run() -> void:
	if _run_data == null:
		push_error("Main: no run data, cannot start a run")
		_autoplay_fail("no run data")
		_show_main_menu()
		return
	# A save in the way (asked about already) goes now: also one kept from another build (online the
	# host's online slot, card #313).
	if _save_slot_ok():
		RunSave.delete(_run_save_path())
	_reset_play_device()
	_fight_weather = null
	_continued_run = false
	var run_seed := _options.seed_override if _options.seed_override >= 0 else randi_range(1, 2147483646)
	if _options.oath >= 0:
		_oath = _options.oath
	_run = RunState.begin(_run_data, _tuning, run_seed, _oath, _run_collection())
	_oath = _run.oath
	_reset_turns()
	if Net.is_host():
		Net.broadcast("run_start", _run_start_message(_run, _players, false))
	print("Run seed: %d  oath: %d  stops: %d  acts: %d" % [run_seed, _run.oath, _run.map.row_count(), _run.acts().size()])
	# Friends may drop in from now on (the first screen goes out in this same frame, card #304).
	_set_drop_in(true)
	Sfx.play("run_begin")
	_begin_start_relics()


## The run's start after the starting Relics (card #328): the starting pact when it is due (card
## #285; it may give a Relic), else the map.
func _after_start_relics() -> void:
	if _run == null:
		return
	if _run.pact_pending:
		_show_event("", true)
		return
	_after_pact()


## The run's start after the pact (or with none): the map.
func _after_pact() -> void:
	_show_map()


# --- the starting Relics (DESIGN.md 8.24, card #328) ------------------------------------------

## The starting Relics: each hero may take start_relic_count() Relics from a Relic book before the
## run goes on (_after_start_relics: the pact or the map). Heroes nobody can pick for now are skipped
## at once (an empty book: a first run or a bot without --relics=all; the Empty Hand gives none at
## all); with nobody left to pick, the run goes on straight away. Online the host shows the step to
## everyone: each friend seated now picks for their own heroes from their own book, and the host
## waits for them up to tuning.start_relic_wait_ms; a friend who drops in later gets none.
func _begin_start_relics() -> void:
	_start_open = true
	_start_wait_gen += 1
	_start_pickers = {}
	var picking := _start_heroes()
	if _run.start_choices(_own_book()).is_empty():
		_run.skip_start_relics(picking)
	if Net.is_host():
		for player: int in range(1, _players.player_count()):
			var theirs := _players.heroes_of(player)
			if not theirs.is_empty() and player < _players.peers.size():
				_start_pickers[_players.peers[player]] = theirs
				picking.append_array(theirs)
	var nobody: Array[int] = []
	for slot: int in _run.party_size():
		if not picking.has(slot):
			nobody.append(slot)
	_run.skip_start_relics(nobody)
	if not _run.start_pending():
		_end_start_relics(false)
		return
	_show_start_relics()
	if Net.is_host() and not _start_pickers.is_empty():
		_wait_start_friends(_start_wait_gen)


## The hero slots this machine picks starting Relics for: every hero in a local game, online this
## machine's player's heroes (the host's also the heroes of anyone away).
func _start_heroes() -> Array[int]:
	if not Net.is_online():
		return RelicGift.every_hero(_run)
	var mine := _players.local_players()
	var none: Array[int] = []
	return _players.heroes_of(mine[0]) if not mine.is_empty() else none


## The starting Relics screen (host, local, and an online friend shown the host's step): this
## machine's heroes still to choose pick from `book` (default: this machine's, _own_book). A friend
## who dropped in mid-run picks nothing (DESIGN.md 8.24); a friend with an empty book skips at once.
func _show_start_relics(book: RelicCollection = null) -> void:
	if _run == null:
		return
	if book == null:
		book = _own_book()
	var screen := StartRelicsScreen.new()
	screen.name = "StartRelics"
	screen.remote = Net.is_client()
	screen.players = _players
	screen.check_pads = not Net.is_online() and _players != null and _players.player_count() > 1
	var mine: Array[int] = []
	if not (Net.is_client() and Net.joined_mid_run):
		mine = _run.start_open_of(_start_heroes())
	screen.setup_pick(_run, book, mine)
	screen.picked.connect(_on_start_picked)
	screen.finished.connect(_check_start_done)
	_show_screen(screen)
	_send_screen({"name": "start_relics"})
	if Net.is_client() and _run.start_choices(book).is_empty():
		while screen.skip():
			pass
	elif _options.is_autoplay():
		screen.autopick = true
		screen.bot_pick.call_deferred()


## A hero took a starting Relic (null: skipped) on this machine's screen: logged here; an online
## friend's goes to the host, which checks it (_on_friend_start_relic).
func _on_start_picked(slot: int, item: GearData) -> void:
	var hero := _run.data.party[slot].id if _run != null and slot >= 0 and slot < _run.party_size() else "?"
	if Net.is_client():
		print("Start relic asked: %s to %s" % [item.id if item != null else "skip", hero])
		Net.send_to_host("start_relic", {"slot": slot, "relic": item.id if item != null else ""})
		return
	print("Start relic: %s to %s" % [item.id if item != null else "skip", hero])


## Host or local: once every hero has their starting Relics (or went without), the run goes on.
func _check_start_done() -> void:
	if Net.is_client() or _run == null or not _start_open or not _screen is StartRelicsScreen:
		return
	if not _run.start_pending():
		_end_start_relics(true)


## The starting Relics step is over (on the host or a local game): what each hero took is logged,
## and the run goes on (`fade`: from the step's screen, once any transition under way is done).
func _end_start_relics(fade: bool) -> void:
	var was_open := _start_open
	_start_open = false
	_start_wait_gen += 1
	_start_pickers = {}
	_run.end_start_picks()
	_log_start_relics()
	if not was_open:
		return
	if not fade:
		_after_start_relics()
		return
	var run := _run
	while _busy:
		await get_tree().process_frame
	if _run == run and _screen is StartRelicsScreen:
		_fade_to(_after_start_relics)


## Logs each hero's Relics as the step left them: "Start relics: alder=iron_charm brin=- cass=..."
## (the bot's AUTOPLAY_START_RELICS line, the same on every machine of an online game).
func _log_start_relics() -> void:
	var parts := PackedStringArray()
	for slot: int in _run.party_size():
		var ids := PackedStringArray()
		for item: GearData in _run.relics_of(slot):
			if _run.start_relics.has(item.id):
				ids.append(item.id)
		parts.append("%s=%s" % [_run.data.party[slot].id, ",".join(ids) if not ids.is_empty() else "-"])
	print("Start relics: %s" % " ".join(parts))
	if _options.is_autoplay():
		print("AUTOPLAY_START_RELICS %s" % " ".join(parts))


## Host, online: the friends' heroes still choosing after start_relic_wait_ms go without, and the run
## goes on once the host's own are done. `gen`: the step this wait is for.
func _wait_start_friends(gen: int) -> void:
	await get_tree().create_timer(maxf(0.0, float(_tuning.start_relic_wait_ms) / 1000.0)).timeout
	if gen != _start_wait_gen or _run == null or not _screen is StartRelicsScreen:
		return
	var late: Array[int] = []
	for peer: Variant in _start_pickers:
		late.append_array(_start_pickers[peer] as Array)
	_start_pickers = {}
	print("Start relics: the wait ran out (%d skipped)" % _run.skip_start_relics(late))
	(_screen as StartRelicsScreen).refresh()
	_check_start_done()


## Host: a friend's starting Relic for hero `slot` ("relic": an id, "" skipped). Taken when it is
## theirs to pick (a hero they held when the step began, still choosing) and the Relic is free; else
## refused, and their screen opens that hero again.
func _on_friend_start_relic(from_peer: int, p: Dictionary) -> void:
	var slot := int(p.get("slot", -1)) if typeof(p.get("slot")) == TYPE_INT else -1
	var id := String(p.relic) if typeof(p.get("relic")) == TYPE_STRING else ""
	var ok := _start_pick_allowed(_start_pickers, from_peer, slot, _run) and _screen is StartRelicsScreen
	if ok:
		if id.is_empty():
			ok = _run.skip_start_relic(slot)
		else:
			ok = not _run.take_start_relic(slot, _run.relic_by_id(id)).is_empty()
	var who := HudStyle.player_tag(maxi(0, _players.player_of_peer(from_peer))) if _players != null else "P?"
	var what := id if not id.is_empty() else "skip"
	print("Start relic %s: %s %s hero=%d" % ["taken" if ok else "refused", who, what, slot])
	if _options.is_autoplay():
		print("AUTOPLAY_START_RELIC %s %s hero=%d ok=%d" % [who, what, slot, int(ok)])
	if not ok:
		Net.send_to(from_peer, "start_refused", {"slot": slot, "relic": id})
		return
	(_screen as StartRelicsScreen).refresh()
	_check_start_done()


## Host: true when hero `slot` is one friend `peer` picks for in this step (`pickers`, fixed when it
## began) and still choosing in `run`. Pure.
static func _start_pick_allowed(pickers: Dictionary, peer: int, slot: int, run: RunState) -> bool:
	return run != null and pickers.get(peer) is Array and (pickers[peer] as Array).has(slot) and run.start_open(slot)


## Host: a friend who left (or dropped for good) during the step: their heroes still choosing go
## without.
func _forget_start_picker(peer: int) -> void:
	if not _start_pickers.has(peer) or _run == null:
		return
	var theirs: Array[int] = []
	theirs.assign(_start_pickers[peer] as Array)
	_start_pickers.erase(peer)
	_run.skip_start_relics(theirs)
	if _screen is StartRelicsScreen:
		(_screen as StartRelicsScreen).refresh()
	_check_start_done()


## `unroll` false shows the map already open (back from the party screen, or redrawn online).
func _show_map(unroll: bool = true) -> void:
	if _run == null:
		return
	# Back from an act's boss and its spoils: on to the next act's map (DESIGN.md 8.9).
	if not Net.is_client() and _run.act_cleared():
		_run.next_act()
		Sfx.play("run_cleared")
		print("Run act %d: %s" % [_run.act + 1, _run.act_data().display_name])
	_begin_choice("map")
	var map := MapScreen.new()
	map.name = "Map"
	_wire_turn(map)
	map.setup(_run, _map_look, unroll)
	map.stop_chosen.connect(_on_stop_chosen)
	map.quit_requested.connect(_open_pause)
	map.party_requested.connect(_show_party.bind("", true))
	_show_screen(map)
	_send_screen({"name": "map"})
	_save_run(false)
	_bank_relics()
	_autoplay_choice(map)


func _on_stop_chosen(id: int) -> void:
	if _busy or not _run.go(id):
		return
	_save_run(true)
	if _autoplay_save_quit_now():
		return
	_enter_stop()


## Starts the stop the party is at: the stop just chosen on the map, or the one a saved run was in.
func _enter_stop() -> void:
	var stop := _run.current()
	print("Run stop %d: %s %s" % [_run.visited, RunMap.TYPE_NAMES[int(stop.type)], MapScreen.stop_name(_run, stop)])
	if _run.in_ambush():
		print("Run ambush: %s (chance was %d%%)" % [_run.ambush_id, _run.unknown_fight_percent()])
	match int(stop.type):
		RunMap.StopType.FIGHT, RunMap.StopType.GUARD:
			# The map swirls away, the place's name card with a tip shows (card #86), then its fight
			# (DESIGN.md 8.22; Guard stops are map rules 3's only, new maps put the guard at an Elite
			# stop). A Fight stop's card carries the First Strike ring (card #320); its fight
			# is announced first, so the friends watch the ring while the host presses it (never while
			# a transition is under way: _fade_to would not build that fight).
			var zone := _run.zone_of(stop)
			var ring: FirstStrikeRing = null
			if _rings_first_strike(int(stop.type)) and not _busy:
				_announce_stop_fight(true)
				ring = _new_first_strike_ring(FirstStrikeRing.Mode.PRESS)
			_fade_to(_start_stop_fight, zone.display_name if zone != null else "", true, ring)
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


## A Fight or Guard stop's fight (DESIGN.md 8.22), built under the place's name card: the fight the
## run state names for the stop (the same on every machine, the friend builds it from the host's
## state), in the place's look and air under its rolled weather, with a Fight stop's drop, and a
## Fight stop's opening from its First Strike ring (card #320). The way in is _fade_to's swirl (the
## map swirls into black, as into every other run fight), then the card.
func _start_stop_fight() -> void:
	var ringed := _run != null and _rings_first_strike(int(_run.current().get("type", -1)))
	var opening := _stop_opening(ringed)
	_first_strike_ring = null
	if _run == null:
		return
	_encounter = _run.encounter_now()
	if _encounter == null:
		# Only bad data gets here (a place with no monsters or no guard): the stop is passed.
		push_error("Main: %s stop %d has no fight in act %d" % [RunMap.TYPE_NAMES[int(_run.current().get("type", 0))],
				_run.at, _run.act])
		_autoplay_fail("stop has no fight")
		if not Net.is_client():
			_show_map()
		return
	_set_run_fight_place(false)
	_drop = _run.fight_drop()
	print("Run fight: %s at %s weather %s%s" % [_encounter.id, _fight_place,
			_fight_weather.id if _fight_weather != null else "clear", " (drop %s)" % _drop.id if _drop != null else ""])
	if _options.is_autoplay():
		print("AUTOPLAY_WEATHER %s %s" % [_run.zone_now().id if _run.zone_now() != null else "none",
				_fight_weather.id if _fight_weather != null else "clear"])
		if ringed:
			print("AUTOPLAY_OPENING %s stop=%d" % [CombatEngine.OPENING_NAMES[opening], _run.visited])
	if not ringed:
		# A Guard stop's fight is announced once the host's card is done (a Fight stop's at its swirl).
		_announce_stop_fight(false)
	_run_opening = opening
	_start_combat()


## True for the stops whose fight opens with the First Strike ring (DESIGN.md 8.22, card #320):
## Fight stops only. Guard, elite, "?" ambush and boss fights open normally. Pure.
static func _rings_first_strike(stop_type: int) -> bool:
	return stop_type == RunMap.StopType.FIGHT


## Host: picks the stop fight's seed and tells the friends (DESIGN.md 8.22). A Fight stop's fight is
## announced at its swirl (`ring`: the friends watch its First Strike ring and wait for the host's
## result, card #320); a Guard stop's once the host's card is done, as the friends hold no card.
func _announce_stop_fight(ring: bool) -> void:
	if not Net.is_host():
		return
	_net_seed = randi_range(1, 2147483646)
	_send_screen({"name": "stop_fight", "seed": _net_seed, "ring": ring})


## A First Strike ring for the Fight stop being entered (DESIGN.md 8.22, card #320): pressed here
## (PRESS: a local game, or the host), watched (WATCH: an online friend) or the picture's (LOOP). The
## bots' luck on it repeats with --seed, a new roll at each stop.
func _new_first_strike_ring(mode: FirstStrikeRing.Mode) -> FirstStrikeRing:
	var ring := FirstStrikeRing.new()
	ring.name = "FirstStrike"
	var bot_seed := -1
	if _options.seed_override >= 0:
		bot_seed = absi(_options.seed_override * FIRST_STRIKE_BOT_SALT + (_run.visited if _run != null else 0))
	ring.setup(_tuning, _visuals, _options, _players, mode, bot_seed)
	if mode == FirstStrikeRing.Mode.PRESS:
		ring.decided.connect(_on_first_strike_decided)
	_first_strike_ring = ring
	return ring


## A ring that never reached its card (the transition could not run) goes.
func _drop_first_strike_ring(ring: FirstStrikeRing) -> void:
	if ring == null:
		return
	if _first_strike_ring == ring:
		_first_strike_ring = null
	if is_instance_valid(ring) and not ring.is_inside_tree():
		ring.free()


## The First Strike ring here is decided (DESIGN.md 8.22). Online the host tells the friends at once
## (their cards wait for it) and keeps it with the fight's message for anyone who gets in later.
func _on_first_strike_decided(opening: CombatSetup.Opening, word: String) -> void:
	var opening_name := CombatEngine.OPENING_NAMES[opening]
	print("First Strike press: %s (%s)" % [opening_name, word])
	if not Net.is_host():
		return
	if int(_net_fight.get("seed", 0)) == _net_seed:
		_net_fight["opening"] = opening_name
		_net_fight["word"] = word
	Net.broadcast("opening", {"fight": _net_seed, "opening": opening_name, "word": word})


## The opening of the Fight stop's fight being built (`ringed`; a Guard stop's is NORMAL): its First
## Strike ring's here (a local game's or the host's press), the host's on a friend's machine.
func _stop_opening(ringed: bool) -> CombatSetup.Opening:
	if not ringed:
		return CombatSetup.Opening.NORMAL
	if Net.is_client():
		return _opening_of(_net_opening, _net_seed)
	if _first_strike_ring != null and is_instance_valid(_first_strike_ring):
		return _first_strike_ring.opening()
	return CombatSetup.Opening.NORMAL


## The opening a host's First Strike result (`result`: {fight, opening, ...}) gives fight `fight`:
## FIRST_STRIKE only when it is that fight's and says so. Pure.
static func _opening_of(result: Dictionary, fight: int) -> CombatSetup.Opening:
	if fight == 0 or int(result.get("fight", 0)) != fight:
		return CombatSetup.Opening.NORMAL
	var first := String(result.get("opening", "")) == CombatEngine.OPENING_NAMES[CombatSetup.Opening.FIRST_STRIKE]
	return CombatSetup.Opening.FIRST_STRIKE if first else CombatSetup.Opening.NORMAL


## Online friend: the host's First Strike result for fight `fight` (its "opening" message, or the
## fight's own message for a friend who gets in once it is decided). A ring watched for that fight
## shows it at once.
func _take_net_opening(p: Dictionary, fight: int) -> void:
	if not p.has("opening"):
		return
	_net_opening = {"fight": fight, "opening": String(p.opening), "word": String(p.get("word", ""))}
	if _first_strike_ring != null and is_instance_valid(_first_strike_ring) and fight == _net_seed:
		_first_strike_ring.show_host_result(String(p.opening), String(p.get("word", "")))


## The run fight at the current stop is fought in its place (DESIGN.md 8.22): the look and air of
## the stop's place under its rolled weather (with --weather on top), or the act's boss lair with no
## weather (`boss`). Sets _fight_look, _fight_air, _fight_weather and _fight_place.
func _set_run_fight_place(boss: bool) -> void:
	var zone := _run.zone_now()
	_fight_place = zone.display_name if zone != null and not boss else ""
	_fight_weather = null if boss else _weather_or_forced(_run.weather_now())
	var look := _run.final_look() if boss else _run.look_now()
	var air: Array[ZoneAmbientData] = []
	if not boss:
		air = _run.air_now()
	_fight_look = _fight_weather.apply_to(look) if _fight_weather != null else look
	_fight_air = _fight_weather.air_with(air) if _fight_weather != null else air


## A run fight that is a stop of its own: the act's boss, an Elite stop's fight (`elite`: one of the
## act's elite groups or its place's guard, as the run state names it, DESIGN.md 8.22) in one of the
## act's places, or an ambush (a "?" stop that turned into a fight, or an event choice that ended in
## one; DESIGN.md 8.7). Elites and ambushes roll a weather like a Fight stop (8.22); the boss has none.
func _start_final_fight(elite: bool = false) -> void:
	_busy = true
	_encounter = _run.final_encounter()
	_drop = null
	var boss := not _run.in_ambush() and not elite
	if _run.in_ambush():
		_encounter = _run.ambush_encounter()
		print("Run ambush fight: %s" % [_encounter.id if _encounter != null else "none"])
		if _encounter == null:
			push_error("Ambush %s has no encounter" % _run.ambush_id)
			_run.end_ambush()
			_end_busy()
			_fade_to(_show_map)
			return
	elif elite:
		_encounter = _run.encounter_now()
		if _encounter == null:
			# The map rolls Elite stops only for an act with elite groups or a guard in every place
			# (RunState._make_map); if one slips through, leave it empty instead of crashing.
			push_error("Elite stop %d has no elite fight in act %d" % [_run.at, _run.act])
			_end_busy()
			_fade_to(_show_map)
			return
		if _options.is_autoplay():
			print("AUTOPLAY_ELITE stop=%d kind=%s enc=%s" % [_run.visited,
					"guard" if _run.elite_holds_guard(_run.at) else "group", _encounter.id])
	_set_run_fight_place(boss)
	if not boss:
		print("Run fight weather: %s" % [_fight_weather.id if _fight_weather != null else "clear"])
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


## A run fight's end screen was left. A defeat (or the last boss) ends the run. A Fight stop's win
## puts its drop in the backpack (one that does not fit opens the party screen holding it), then the
## map; a guard, an elite or an act's boss gives spoils, then the map (the next act's, after a boss).
## Running away passes the stop (DESIGN.md 2.13, 8.22).
func _on_run_fight_over(result: String) -> void:
	if _busy or _run == null:
		return
	_run.spend_items(_combat.used_items())
	var ambushed := _run.in_ambush()
	var ambush_spoils := _run.ambush_spoils
	var type := int(_run.current().get("type", -1))
	_run.finish_fight(result, _combat.party_hp(), _encounter, _combat.recap())
	_run.carry_team_gauge(_combat.team_gauge())
	_autoplay_spend_points()
	var found: ItemData = null
	if _takes_fight_drop(result, type, ambushed, _drop != null):
		print("Run drop: %s" % _drop.id)
		if _run.add_item(_drop) < 0:
			found = _drop
	_drop = null
	match _after_run_fight(result, type, ambushed, ambush_spoils, _run.is_over(), found != null):
		AfterFight.END:
			_clear_run_save()
			_fade_to(_show_run_end)
		AfterFight.PARTY:
			_fade_to(_show_party.bind(_pack_full_note(found), false, {"item": found}))
		AfterFight.SPOILS:
			var guard := _encounter != null and _encounter.mini_boss
			_fade_to(_show_loot.bind([] as Array[GearData], _spoils_line(type, ambushed, guard)))
		_:
			_fade_to(_show_map)


## True when a run fight's item drop (`has_drop`) goes in the pack: only a won Fight stop's fight,
## never an ambush's, an escape or a loss (DESIGN.md 8.22). Pure.
static func _takes_fight_drop(result: String, stop_type: int, ambushed: bool, has_drop: bool) -> bool:
	return has_drop and result == RunState.VICTORY and not ambushed and stop_type == RunMap.StopType.FIGHT


## Where a run fight's end screen leads (DESIGN.md 2.13, 8.22), pure: the run's end once it is
## `over`; after a win the party screen when a Fight stop's drop did not fit (`drop_left`), the spoils
## after a guard, an elite or a boss (after an ambush only when its event's data says so,
## `ambush_spoils`; an ambush pays gold and XP like any fight), else the map. An escape passes the
## stop: the map.
static func _after_run_fight(result: String, stop_type: int, ambushed: bool, ambush_spoils: bool, over: bool,
		drop_left: bool) -> AfterFight:
	if over:
		return AfterFight.END
	if result != RunState.VICTORY:
		return AfterFight.MAP
	if ambushed:
		return AfterFight.SPOILS if ambush_spoils else AfterFight.MAP
	if stop_type == RunMap.StopType.FIGHT:
		return AfterFight.PARTY if drop_left else AfterFight.MAP
	return AfterFight.SPOILS


## The line over a run fight's spoils: the boss's, a guard's (`guard`: the fight was a guard's, at an
## Elite stop since DESIGN.md 8.22, or a map rules 3 Guard stop), else an elite's (an ambush with
## spoils reads as an elite's, as before). Pure.
static func _spoils_line(stop_type: int, ambushed: bool, guard: bool = false) -> String:
	if not ambushed and stop_type == RunMap.StopType.FINAL:
		return "The boss fell. Take one."
	if not ambushed and (stop_type == RunMap.StopType.GUARD or guard):
		return "The guard fell. Take one."
	return "The elite fell. Take one."


## The party screen's line when a Fight stop's drop did not fit the pack (it opens holding it). Pure.
static func _pack_full_note(item: ItemData) -> String:
	return "The enemy dropped a %s, but the pack is full." % item.display_name


func _show_rest(result: String = "") -> void:
	_begin_choice("rest")
	var rest := RestScreen.new()
	rest.name = "Rest"
	rest.remote = Net.is_client()
	_wire_turn(rest)
	rest.setup(_run, RestScreen.FIRE_PATH, result)
	rest.done.connect(_fade_to.bind(_show_map))
	rest.acted.connect(func(text: String) -> void: _send_screen({"name": "rest", "result": text}))
	_show_screen(rest)
	_send_screen({"name": "rest", "result": result})
	_autoplay_choice(rest)


func _show_shop(gear: Array[GearData] = []) -> void:
	_begin_choice("shop")
	var shop := ShopScreen.new()
	shop.name = "Shop"
	shop.remote = Net.is_client()
	if not Net.is_client():
		gear = _run.shop_gear(_run.at)
	_wire_turn(shop)
	shop.setup(_run, gear)
	shop.done.connect(_fade_to.bind(_show_map))
	shop.restocked.connect(func() -> void: _send_shop_wares(_run.shop_gear(_run.at)))
	shop.acted.connect(_save_stop_progress)
	_show_screen(shop)
	_send_shop_wares(gear)
	_autoplay_choice(shop)


func _send_shop_wares(gear: Array[GearData]) -> void:
	_send_screen({"name": "shop", "gear": _gear_ids(gear)})


## A "?" stop (DESIGN.md 8.7). `result`: online clients show what the host chose.
## `pact`: the starting pact before the first stop (card #285) instead of a "?" stop's event.
func _show_event(result: String = "", pact: bool = false) -> void:
	_begin_choice("pact" if pact else "event")
	var screen := EventScreen.new()
	screen.name = "Event"
	screen.remote = Net.is_client()
	_wire_turn(screen)
	var event := _run.pact_event() if pact else (null if _run.in_ambush() and result.is_empty() else _run.event_of(_run.at))
	screen.setup(_run, event, result)
	if pact:
		screen.done.connect(_on_pact_done)
		screen.chosen.connect(func(_index: int, text: String) -> void:
			_run.pact_pending = false
			_send_screen({"name": "event", "pact": true, "result": text if not text.is_empty() else "You walk on."})
			_save_run(false))
		screen.gifts_settled.connect(_save_run.bind(false))
	else:
		screen.done.connect(_on_event_done)
		screen.chosen.connect(func(index: int, text: String) -> void:
			_send_screen({"name": "event", "result": text if not text.is_empty() else "You walk on."})
			# The risk is rolled: lock the result in (a Leave, index -1, took nothing).
			if index >= 0:
				_save_stop_progress())
		screen.gifts_settled.connect(_save_stop_progress)
	_show_screen(screen)
	_send_screen({"name": "event", "pact": pact, "result": result})
	_autoplay_choice(screen)


## The starting pact was taken or passed by (card #285): on to the run's start.
func _on_pact_done() -> void:
	if _busy or Net.is_client():
		return
	_run.pact_pending = false
	_run.stop_done = false
	_run.stop_text = ""
	_fade_to(_after_pact)


## An event (or an ambush page) was left: into the fight if it sprang an ambush, else the map.
func _on_event_done() -> void:
	if _busy:
		return
	if _run.in_ambush():
		_start_final_fight()
	else:
		_fade_to(_show_map)


## The treasure stop was left: into the fight if the rotten chest sprang one (card #287), else the map.
func _on_treasure_done() -> void:
	if _busy:
		return
	if _run.in_ambush():
		_start_final_fight()
	else:
		_fade_to(_show_map)


## A treasure stop (DESIGN.md 8.8). `opened`: online clients show the chest as the host left it.
func _show_treasure(opened: bool = false, text: String = "") -> void:
	_begin_choice("treasure")
	var screen := TreasureScreen.new()
	screen.name = "Treasure"
	screen.remote = Net.is_client()
	_wire_turn(screen)
	screen.setup(_run, opened, text if not text.is_empty() else _run.stop_text)
	screen.done.connect(_on_treasure_done)
	screen.opened.connect(func() -> void: _send_screen({"name": "treasure", "opened": true}))
	screen.gifts_settled.connect(_save_stop_progress)
	_show_screen(screen)
	_send_screen({"name": "treasure", "opened": opened})
	_autoplay_choice(screen)


## Spoils after an elite or an act's boss (DESIGN.md 8, 8.6, 8.24): pick one Relic and the hero who
## gets it, then the party screen with it.
func _show_loot(gear: Array[GearData] = [], text: String = "") -> void:
	_begin_choice("loot")
	var loot := LootScreen.new()
	loot.name = "Loot"
	if not Net.is_client():
		gear = _run.loot_choices(_run.at)
	_wire_turn(loot)
	loot.setup(gear, text, _run)
	loot.chosen.connect(_on_loot_chosen)
	_show_screen(loot)
	Sfx.play("loot_reveal")
	_send_screen({"name": "loot", "gear": _gear_ids(gear), "text": text})
	_autoplay_choice(loot)


## A spoil was picked: it goes to hero `hero` (DESIGN.md 8.24), then the party screen opens on that
## hero's Relics. Nothing picked (or nothing it could take): on to the map.
func _on_loot_chosen(item: GearData, hero: int) -> void:
	var found := _run.give_relic(item, hero) if item != null else {}
	if found.is_empty():
		_fade_to(_show_map)
		return
	print("Run relic: %s to %s" % [item.id, _run.data.party[hero].id])
	# The party screen shows it as a toast next to the Relic's icon (card #270): no sentence.
	_show_party.call_deferred(RunState.relic_find_short(found), false, {"icon": item})


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
	if from_map and not _my_turn():
		# The host's own look at the party (card #314): a friend whose turn it is keeps choosing.
		if _options.is_autoplay():
			_autoplay_party.call_deferred(party)
		return
	_send_screen({"name": "party", "note": note})
	if _options.is_autoplay() and not Net.is_client():
		_autoplay_party.call_deferred(party)


## A win at oath N opens oath N+1 on this machine (never lowering what is open). Returns the oath
## that was newly opened (0: none), worked out from the value before the unlock, for the end screen.
## Bot runs only show it. An online friend who joined late unlocks too (owner, 2026-10-23).
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
	_set_drop_in(false)
	_bank_relics()
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
	# Phase 22: the killer's row (a defeat) and what an online friend keeps, as icons (the Kept row,
	# RunEndScreen.own_kept: no words line).
	end.setup(_run, _visuals.end_input_guard_ms, unlocked_now, recap_lines, "", _hero_players(),
			_last_recap if _run.result != RunState.VICTORY else {}, _own_start if Net.is_client() else null,
			{"relics": _join_relics} if Net.is_client() else {})
	end.done.connect(_fade_to.bind(_show_main_menu))
	end.again.connect(_fade_to.bind(_play_again))
	_show_screen(end)
	_send_screen({"name": "run_end"})
	_client_done = Net.is_client()
	if _options.is_autoplay():
		for line: String in recap_lines:
			print("AUTOPLAY_RECAP ", line)
		# Who plays at the end (cards #304, #311): the same on every machine of an online game.
		print("AUTOPLAY_PLAYERS n=%d owners=%s" % [_players.player_count(), _players.owners_text()])
		print("AUTOPLAY_RESULT run_%s act=%d stops=%d fights=%d level=%d items=%d gold=%d seed=%d oath=%d relics=%d relics_held=%d" % [
				_run.result, _run.act + 1, _run.visited, _run.fights_won, _run.top_level(), _run.backpack.entries.size(),
				_run.gold_earned, _run.run_seed, _run.oath, _run.relics.size(), _held_count(_run)])
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


## Every frame in local co-op: when a player's pad is gone during a fight, hold the game under a
## card until they are back (their heroes would wait forever otherwise). A pad that returns under
## the same id carries on by itself.
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
		_refresh_prompt_mix()
		_refresh_roster_users()
		_watch_pads()


## Give heroes on the lost-pad card: that player leaves, their heroes go to P1 (P2 when P1's pad was
## lost) and nobody else's change (DESIGN.md 9.3, #311).
func _on_pad_dropped() -> void:
	var lost := _lost_pad_players()
	if not lost.is_empty() and _players.leave_midrun(lost[0]):
		Sfx.play("menu_cancel")
		_reset_play_device()
		_refresh_roster_users()
		_refresh_prompt_mix()
		_resave_players()
		_watch_pads()


## The fight reads the roster in place; tell it it changed.
func _refresh_roster_users() -> void:
	if _combat != null:
		_combat.update_players(_players)


## The window lost focus (alt-tab, the Steam overlay, a notification): a fight or the map pauses,
## alone or in local co-op. Never online, where the others play on.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_on_close_requested()
		return
	if what != NOTIFICATION_APPLICATION_FOCUS_OUT and what != NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		return
	if Net.is_online() or _options == null or _options.is_autoplay():
		return
	# Deferred (card #208): focus can go while Main is adding a child (building a fight), and a pause
	# menu added then fails, leaving the game held still behind a menu that never appeared.
	_pause_game.call_deferred()


# --- pause ------------------------------------------------------------------------------------

## Pause (Esc / Menu, DESIGN.md 7.5) over a fight or the run map. Main reads it before the
## fight's own input, so Esc never reaches the action menu as "back".
func _input(event: InputEvent) -> void:
	var pause := event.is_action_pressed(&"pause", false, true)
	if (event is InputEventKey or event is InputEventJoypadButton) and event.is_pressed():
		_last_device = PlayerRoster.device_of(event)
	_note_play_device(event, pause)
	# Online on a run screen whose choice is another player's (card #314; with Take turns off, every
	# choice is the host's): only pause (to leave) works here. The backpack is everyone's: the party
	# screen takes input, and Tab / Y on the map opens it.
	# The starting Relics (card #328): every machine picks for its own heroes, whoever's turn it is.
	var own := _screen is PartyScreen or _screen is RunEndScreen or _screen is StartRelicsScreen \
			or (_screen is MapScreen and event.is_action(&"party_menu"))
	var watching := Net.is_online() and not _my_turn()
	if watching and _is_run_screen(_screen) and _pause == null and _prompt == null and not pause and not own:
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
	if Net.is_online() and (_combat != null or _is_run_screen(_screen)):
		# Online nothing stops for a pause menu: it opens over the game, which goes on.
		get_viewport().set_input_as_handled()
		_open_pause()
		return
	if _pause_game():
		get_viewport().set_input_as_handled()


## Remembers P1's real device while solo (#304): a button press, or a stick push (the move actions,
## DESIGN.md 8.22 G8), made while the game itself is being played. The press that opens the pause menu (Pause, or Back on the
## map) never counts: it may be a friend's pad. Nor does any press in co-op (_reset_play_device
## takes the roster's P1 whenever the roster changes).
func _note_play_device(event: InputEvent, pause: bool) -> void:
	var pressed := (event is InputEventKey or event is InputEventJoypadButton) and event.is_pressed() and not event.is_echo()
	var walked := event is InputEventJoypadMotion and (event.is_action_pressed(&"move_left")
			or event.is_action_pressed(&"move_right") or event.is_action_pressed(&"move_up")
			or event.is_action_pressed(&"move_down"))
	if not pressed and not walked:
		return
	var in_play := (_pause == null and _prompt == null and _pad_overlay == null
			and not _menu_pause_wanted and not _busy and _game_in_play())
	_play_device = PlayerRoster.play_device_after(_play_device, PlayerRoster.device_of(event),
			pause or event.is_action(&"menu_cancel"), in_play, _players != null and _players.is_coop())


## A new roster (a run started, someone joined or left, the lost-pad card): P1's real device is the
## roster's P1 again until a solo press says otherwise. Without this, a press a friend made before
## the game went back to solo could make their pad P1 on the next Players overlay.
func _reset_play_device() -> void:
	_play_device = _players.device_of_player(0) if _players != null else PlayerRoster.ANY


## True while the game itself is on screen: a fight or a run screen.
func _game_in_play() -> bool:
	if _combat != null and _combat.is_inside_tree():
		return true
	return _is_run_screen(_screen)


## Pauses the fight (after the current move), the run map or the starting Relics (where Esc would
## otherwise be Back, skipping a hero). True if it started one.
func _pause_game() -> bool:
	if _pause != null or _prompt != null or _busy or _pad_overlay != null:
		return false
	if _combat != null and _combat.is_inside_tree():
		# A fight pauses between moves; it calls back with pause_reached. The flag goes up first: an
		# idle fight pauses inside request_pause.
		_menu_pause_wanted = true
		if _combat.request_pause():
			return true
		_menu_pause_wanted = false
		return false
	if _screen is MapScreen or _screen is StartRelicsScreen:
		_open_pause()
		return true
	return false


func _open_pause() -> void:
	if _pause != null:
		return
	if not Net.is_online():
		_hold_behind_overlay(true)
	_pause = PauseMenu.new()
	_pause.name = "Pause"
	# Local friends join, leave and swap heroes here (cards #304, #311); online the host seats them,
	# and the address a friend types to drop in is shown.
	_pause.players_row = not Net.is_online() and _tutorial == null
	if Net.is_online():
		_pause.note = _online_address_line()
	if _tutorial != null:
		_pause.setup("Leave tutorial", "Back to the main menu.", "Skip this lesson", "Go on to the next one.")
		_pause.extra_requested.connect(_on_tutorial_skip)
	elif Net.is_host() and _save_allowed():
		# The host keeps the online run for later (card #313), with the same rules as a local run's; a
		# friend's pause never offers it.
		var again := "The stop starts over when you continue." if _checkpoint_in_stop else "You continue from this map."
		_pause.setup("End the game", "The run and its save are lost, for everyone.", "", "",
				"Save & Quit", "Everyone goes to the main menu; Host continues it. %s" % again)
		_pause.save_quit_requested.connect(_on_pause_save_quit)
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
	_pause.glossary_requested.connect(_on_pause_glossary)
	_pause.players_requested.connect(_on_pause_players)
	_pause.leave_requested.connect(_on_pause_leave)
	add_child(_pause)


func _on_pause_resumed() -> void:
	_free_pause()
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


## The Glossary over the pause menu (card #207). It only reads, so it needs nothing held: the game
## is already held (or, online, goes on) exactly as under the pause menu.
func _on_pause_glossary() -> void:
	_pause.visible = false
	_pause.process_mode = Node.PROCESS_MODE_DISABLED
	var book := GlossaryScreen.new()
	book.name = "PauseGlossary"
	book.layer = _pause.layer + 1
	book.setup(GlossaryScreen.load_glossary())
	book.closed.connect(_on_pause_glossary_closed.bind(book))
	add_child(book)


func _on_pause_glossary_closed(book: GlossaryScreen) -> void:
	book.queue_free()
	if _pause != null:
		_pause.visible = true
		_pause.process_mode = Node.PROCESS_MODE_INHERIT


## The Players row (DESIGN.md 9.3): the players screen in its in-run mode over the pause menu. The
## game under it is held at a quiet moment already (the pause), so the roster it returns is applied
## at once when it closes.
func _on_pause_players() -> void:
	_pause.visible = false
	_pause.process_mode = Node.PROCESS_MODE_DISABLED
	# P1's real device while solo; ANY, or a pad that is no longer plugged in, falls back to the
	# roster's, then to the device that pressed last, then the keyboard: never a dead pad (so the
	# device P1 holds is never left out, where its Enter would join them as P2 by mistake).
	var p1 := PlayerRoster.overlay_p1_device(_play_device, _players.device_of_player(0), _last_device,
			_connected_pads())
	var lobby := LobbyScreen.new()
	lobby.name = "PausePlayers"
	lobby.layer = _pause.layer + 1
	lobby.hero_portraits = _hero_portraits()
	lobby.setup_in_run(_hero_names(), _players, p1)
	lobby.started.connect(_on_pause_players_play.bind(lobby))
	lobby.back.connect(_on_pause_players_back.bind(lobby))
	add_child(lobby)


## Play: apply and go back to the game.
func _on_pause_players_play(players: PlayerRoster, _oath_pick: int, lobby: LobbyScreen) -> void:
	lobby.queue_free()
	_change_local_roster(players, "menu")
	_on_pause_resumed()


## Back (P1) or Pause: apply and go back to the pause menu.
func _on_pause_players_back(lobby: LobbyScreen) -> void:
	var roster := lobby.roster()
	lobby.queue_free()
	_change_local_roster(roster, "menu")
	if _pause != null:
		_pause.visible = true
		_pause.process_mode = Node.PROCESS_MODE_INHERIT


## Local co-op: the roster changes mid-run (someone joined, left or traded, cards #304, #311).
## Only at a quiet moment: at once outside a fight, while it is paused or over; in a fight that is
## playing, after the current move (request_pause, quiet), like pausing. Nothing happens when
## nothing changed (both solo counts as no change). Online: never (the host seats friends itself).
func _change_local_roster(roster: PlayerRoster, why: String) -> void:
	# A change already waiting for the quiet moment is what this one is measured against.
	var base := _pending_roster if _pending_roster != null else _players
	if roster == null or Net.is_online() or not roster.validate().is_empty() or _same_players(base, roster):
		return
	var live := _combat != null and _combat.is_inside_tree() and not _combat.is_paused()
	if not live:
		# Nothing waits any more (a waiting one would otherwise land later over this one).
		_pending_roster = null
		_pending_why = ""
		_apply_local_roster(roster, why)
		return
	_pending_roster = roster
	_pending_why = why
	if _roster_pause_wanted:
		return
	# The flag goes up first: an idle fight pauses (and emits pause_reached) inside request_pause.
	_roster_pause_wanted = true
	if not _combat.request_pause(true):
		# The fight is over (or calibrating): nothing is moving, so the change can come now.
		_roster_pause_wanted = false
		_pending_roster = null
		_pending_why = ""
		_apply_local_roster(roster, why)


## Applies a local roster now and tells everything that reads it.
func _apply_local_roster(roster: PlayerRoster, why: String) -> void:
	var before := _players
	_players = roster
	_reset_play_device()
	_refresh_roster_users()
	_refresh_prompt_mix()
	_resave_players()
	if _screen is StartRelicsScreen:
		# The starting Relics (card #328): the player tags and whose pad picks follow the new roster.
		var picks := _screen as StartRelicsScreen
		picks.players = roster
		picks.check_pads = roster.player_count() > 1
		picks.refresh()
	var names := PackedStringArray()
	for device: int in roster.devices:
		names.append(PlayerRoster.device_name(device))
	print("Players now: %d (%s) heroes %s [%s]" % [roster.player_count(), ", ".join(names), roster.owners_text(), why])
	if _options == null or not _options.is_autoplay():
		return
	var count := roster.player_count()
	var old := before.player_count() if before != null else count
	if count > old:
		print("AUTOPLAY_ROSTER join p=%d device=%d at=%s owners=%s" % [count, roster.device_of_player(count - 1),
				_place_word(), roster.owners_text()])
	elif count < old:
		print("AUTOPLAY_ROSTER leave p=%d at=%s owners=%s" % [old, _place_word(), roster.owners_text()])
	else:
		print("AUTOPLAY_ROSTER trade at=%s owners=%s" % [_place_word(), roster.owners_text()])


## True when `next` changes nothing that matters against `now`: the same roster, or solo both
## times (a solo device swap changes nothing in solo, where every device controls everything).
static func _same_players(now: PlayerRoster, next: PlayerRoster) -> bool:
	return next.same_as(now) or (not next.is_coop() and not now.is_coop())


## The fight goes on after a pause nobody stays in (a roster change, or a lost pad that came back
## before the pause landed), unless a menu, card or another pause came over it meanwhile. A pad lost
## again meanwhile gets its card instead. Always deferred by the callers: pause_reached can come from
## inside the fight's event loop, which only plays the rest of its queue once it has unwound.
func _resume_quiet_pause() -> void:
	if _combat == null or not _combat.is_paused() or _pause != null or _prompt != null or _pad_overlay != null \
			or _roster_pause_wanted or _pad_pause_wanted or _menu_pause_wanted \
			or (_tutorial != null and _tutorial.pause_wanted()):
		return
	# (The bot's pretend pads are never plugged in: it has no lost-pad card, as in _process.)
	if not _options.is_autoplay() and not _lost_pad_players().is_empty():
		_show_pad_overlay()
		return
	_combat.resume_after_pause()


## Keyboard and pad players together: hints show both kinds of buttons (card #45).
func _refresh_prompt_mix() -> void:
	ButtonPrompts.set_both(not Net.is_online() and _players.devices.has(PlayerRoster.KEYBOARD)
			and _players.devices.any(func(device: int) -> bool: return device >= 0))


## The save keeps how many players share the pads, and online who holds which seat with its token
## (card #313); a roster change rewrites the last checkpoint with the new players, nothing else
## (DESIGN.md 8.14): a local join or leave, the online Continue seating the friends, a drop-in.
func _resave_players() -> void:
	if _save_allowed() and not _checkpoint.is_empty():
		_write_checkpoint()


## "fight", "map" or the screen's name in lower case (logs, AUTOPLAY lines).
func _place_word() -> String:
	if _combat != null and _combat.is_inside_tree():
		return "fight"
	if _screen is MapScreen:
		return "map"
	return String(_screen.name).to_lower() if _screen != null else "none"


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
			_prompt.setup("End the game for everyone?", "The run is lost.", "End the game", "Keep playing")
		else:
			_prompt.setup("Leave the game?", "Your heroes go to the host.", "Leave", "Keep playing")
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
	_prompt.setup("Abandon this run?", "The run is lost.", "Abandon run", "Keep playing")
	_prompt.answered.connect(_on_abandon_answered)
	add_child(_prompt)


func _on_abandon_answered(yes: bool) -> void:
	_prompt.queue_free()
	_prompt = null
	if yes:
		_abandon_run()
	elif _pause != null:
		_pause.process_mode = Node.PROCESS_MODE_INHERIT


## Abandon run, End the game (host) or Leave the game (client), once the player said yes.
func _abandon_run() -> void:
	_free_pause()
	_set_drop_in(false)
	_tell_clients_game_ended()
	if _run != null:
		# An abandoned run keeps what it found, like a lost one (DESIGN.md 8.17).
		_bank_relics()
		_clear_run_save()
	_fade_to(_show_main_menu)


## Host mid-run: tells the friends the game is over before the line goes down (End the game, or
## closing the window), so they go to the main menu with "The host ended the game." instead of
## taking the lost connection for a dropped host and waiting to take their seat back (DESIGN.md
## 9.2). The message goes out with the next frames; the line closes after the fade (or the wait
## before quitting), never in the same moment, as the other end handles a disconnect before the
## messages that came with it.
func _tell_clients_game_ended() -> void:
	if Net.is_host() and _run != null and not _run.is_over():
		Net.broadcast("menu")


## The window's close button. Only a host holds quitting back (auto_accept_quit is off while
## hosting): it says goodbye first and quits a moment later, so the goodbye arrives. A run the host
## saves as it goes keeps its save, as a local run does (card #313): the friends hear "saved" and keep
## their seats for the host's Continue.
func _on_close_requested() -> void:
	if get_tree().auto_accept_quit:
		return
	if Net.is_host() and _save_allowed() and _write_checkpoint():
		Net.broadcast("saved", _saved_message(_checkpoint))
		_put_away = true
	else:
		_tell_clients_game_ended()
	await get_tree().create_timer(NetSession.BYE_LINGER_S, true, false, true).timeout
	get_tree().quit()


## Stops (or restarts) the fight or screen under an overlay: no movement, timers or input.
func _hold_behind_overlay(held: bool) -> void:
	var mode := Node.PROCESS_MODE_DISABLED if held else Node.PROCESS_MODE_INHERIT
	for node: Node in [_combat, _screen]:
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
		if (child is SettingsScreen or child is GlossaryScreen or child is LobbyScreen) and child != _screen:
			child.queue_free()


# --- online (DESIGN.md 9.2) -------------------------------------------------------------------

## Host Online: listen, and show the players screen with the address friends type in.
func _host_online() -> void:
	var err := Net.host()
	if err != OK:
		print("Could not host: error %d" % err)
		_notice = "Could not host (another game hosting?)"
		_autoplay_fail("host_failed")
		_show_main_menu()
		return
	# Closing the window waits for the goodbye to the friends (_on_close_requested).
	get_tree().auto_accept_quit = false
	_players = PlayerRoster.online(_hero_names().size(), NetSession.HOST_PEER, NetSession.HOST_PEER)
	_show_host_lobby()
	print("Hosting on port %d: %s" % [_tuning.net_port, ", ".join(NetSession.local_addresses())])
	# --host=1: the bot starts alone; friends drop in later (card #304).
	if _options.host_players > 0 and _players.player_count() >= _options.host_players:
		_autoplay_start_online()


## The host's players screen with the roster as it is (a new game, or Again after a run, card #284).
func _show_host_lobby() -> void:
	var lobby := LobbyScreen.new()
	lobby.name = "Lobby"
	lobby.hero_portraits = _hero_portraits()
	_give_oaths(lobby)
	# A saved online run (card #313): Continue beside Start, or why there is none.
	var saved := _valid_online_save()
	if not saved.is_empty():
		lobby.continue_line = _continue_line_of(saved.state as RunState)
	lobby.saved_note = _online_save_note
	lobby.setup_online(_hero_names(), _players, true, NetSession.local_addresses(), _tuning.net_port)
	lobby.roster_changed.connect(_on_online_roster_changed)
	lobby.oath_changed.connect(_on_online_oath_changed)
	lobby.started.connect(_on_online_started)
	lobby.continued.connect(_on_online_continued)
	lobby.back.connect(_show_main_menu.call_deferred)
	_show_screen(lobby)


func _on_online_roster_changed(players: PlayerRoster) -> void:
	_players = players
	Net.broadcast("lobby", _lobby_message(players, _lobby_oath()))
	if _options.host_players > 0 and players.player_count() >= _options.host_players:
		_autoplay_start_online()


## The address a friend types to drop in, for the online pause menu (card #304): the host's own
## addresses, or the one this friend joined.
func _online_address_line() -> String:
	if Net.is_host():
		return LobbyScreen.address_line(NetSession.local_addresses(), _tuning.net_port)
	var joined: Array[String] = [Net.joined_address()]
	return LobbyScreen.address_line(joined, _tuning.net_port)


## The oath picked on the players screen now (0 without one).
func _lobby_oath() -> int:
	return (_screen as LobbyScreen).oath() if _screen is LobbyScreen else 0


## Online host: the oath pick changed; the clients show it.
func _on_online_oath_changed(oath: int) -> void:
	_oath = oath
	Net.broadcast("lobby", _lobby_message(_players, oath))


## The host pressed Start: the players screen closes (friends drop in from now on); the run begins
## (the clients follow). A new run over a saved online run asks first, as the main menu's New Run
## does over a local one (card #313; `asked`: the host said yes; a bot never asks).
func _on_online_started(players: PlayerRoster, oath: int, asked: bool = false) -> void:
	if _busy or not _screen is LobbyScreen or _prompt != null:
		return
	if not asked and not _options.is_autoplay() and _online_save_in_the_way():
		_ask_overwrite_online_save(oath)
		return
	_players = players
	_oath = oath
	Net.closed = true
	print("Players: %d online" % players.player_count())
	_fade_to(_new_run)


## Online host, Start over a saved online run (card #313): "Start a new run?" first; yes starts it (the
## save goes when it begins), no stays on the players screen with Continue.
func _ask_overwrite_online_save(oath: int) -> void:
	_prompt = ConfirmPrompt.new()
	_prompt.name = "OverwritePrompt"
	_prompt.setup("Start a new run?", "The saved online run is lost.", "New run", "Keep saved run")
	_prompt.answered.connect(func(yes: bool) -> void:
		_prompt.queue_free()
		_prompt = null
		if yes and _screen is LobbyScreen:
			# The friends on the screen now (one may have come or gone while it asked).
			_on_online_started((_screen as LobbyScreen).roster(), oath, true))
	add_child(_prompt)


## The host pressed Continue on its players screen (card #313): the saved online run goes on at once,
## as a run friends drop into does (`--host=1`). The saved seats come back away (the host plays those
## heroes); the friends on the players screen sit down now (SavedSeats.seat_lobby: a token takes its
## own seat, anyone else the next saved seat nobody took, then a free one; with neither they are
## turned away), the other saved seats wait for their tokens (Net.hold_seat), and free seats fill by
## drop-in. It goes back into the stop it was saved in (a fight at the HP the party had on entering
## it), or the map. Everyone in it counts as late (_continued_run).
func _on_online_continued(lobby_roster: PlayerRoster) -> void:
	if _busy or not _screen is LobbyScreen or _prompt != null:
		return
	var saved := _valid_online_save()
	if saved.is_empty():
		# Gone or no longer usable since the screen was built: the screen says why now.
		_show_host_lobby()
		return
	var state := saved.state as RunState
	var seats := saved.online as Dictionary
	var roster := SavedSeats.restore(seats, state.party_size())
	var lobby: Array[int] = []
	var shown := {}
	for player: int in range(1, lobby_roster.peers.size()):
		lobby.append(lobby_roster.peers[player])
		shown[lobby_roster.peers[player]] = Net.shown_token(lobby_roster.peers[player])
	if roster == null:
		# _valid_online_save checked the seats; this only keeps a surprise from stopping the run.
		roster = PlayerRoster.online(_hero_names().size(), NetSession.HOST_PEER, NetSession.HOST_PEER)
	var placed := SavedSeats.seat_lobby(roster, SavedSeats.tokens_of(seats), lobby, shown)
	for peer: Variant in placed.refused as Array:
		Net.refuse(int(peer), JoinGate.REASON_FULL)
	var waiting := placed.waiting as Dictionary
	for old: int in waiting:
		if not Net.hold_seat(old, String(waiting[old])):
			roster.drop_peer(old)
	Net.closed = true
	_players = roster
	_run = state
	_oath = state.oath
	_fight_weather = null
	_checkpoint = saved.run as Dictionary
	_checkpoint_in_stop = bool(saved.in_stop)
	# The friends sat down under the tokens of this session: the slot gets them now, so it agrees with
	# their seat files even if this machine crashes before the next autosave (a stop's whole fight).
	_resave_players()
	_continued_run = true
	_reset_turns()
	_reset_play_device()
	_refresh_prompt_mix()
	var start := _run_start_message(_run, _players, true)
	start["continued"] = true
	Net.broadcast("run_start", start)
	print("Run continued online: seed %d  act %d  stop %d%s  players %d (%s)" % [_run.run_seed, _run.act + 1,
			_run.visited, " (in progress)" if _checkpoint_in_stop else "", _players.player_count(), _players.owners_text()])
	if _options.is_autoplay():
		print("AUTOPLAY_CONTINUED host act=%d stop=%d in_stop=%d seated=%d waiting=%d refused=%d players=%d" % [
				_run.act + 1, _run.visited, int(_checkpoint_in_stop), (placed.seated as Dictionary).size(), waiting.size(),
				(placed.refused as Array).size(), _players.player_count()])
	# Friends may drop in from now on, and the saved seats' owners come back with their tokens.
	_set_drop_in(true)
	_update_away_chip()
	Sfx.play("run_begin")
	_resume_where_saved()


## The "lobby" and "again" messages: the host's roster and its oath pick.
static func _lobby_message(roster: PlayerRoster, oath: int) -> Dictionary:
	return {"roster": roster.to_dict(), "oath": oath}


## The "run_start" message: the run's seed, the roster and the oath, `late`: a drop-in's catch-up
## (card #304), whose friend keeps only what comes after. The host's next screen brings the whole
## state.
static func _run_start_message(run: RunState, roster: PlayerRoster, late: bool) -> Dictionary:
	return {"seed": run.run_seed, "roster": roster.to_dict(), "oath": run.oath, "late": late}


## Client, at a run_start: whether this friend's Relics count only from the first run state (late,
## card #304). The host said so (`said_late`: a drop-in, a continued run), or the welcome gave a seat
## back (`rejoined`) for this catch-up (`catching_up`) into a game this machine has no start of
## (`same_game` false): the token came from the seat file after a crash or a restart (card #313), and
## the Relic file may hold this run's pips already. A start on time, a rejoin within the same game
## here (its start is kept), or a later game after that rejoin (no catch-up any more) is not late. Pure.
static func _late_baseline(said_late: bool, rejoined: bool, catching_up: bool, same_game: bool) -> bool:
	return said_late or (rejoined and catching_up and not same_game)


## Client: the run a "run_start" begins here, from the host's seed at `oath`. Null when this machine
## lacks its data. The host's next screen brings the whole state.
static func _client_game(run_data: RunData, tuning: Tuning, game_seed: int, oath: int) -> RunState:
	return RunState.begin(run_data, tuning, game_seed, oath) if run_data != null else null


## `address` "" : the remembered one. `problem`: shown at once (why we are here again). `rejoin`:
## the connection was lost mid-run (the Confirm hint says Rejoin).
func _show_join(address: String = "", problem: String = "", rejoin: bool = false) -> void:
	var join := JoinScreen.new()
	join.name = "Join"
	join.setup(address if not address.is_empty() else PlayerSettings.join_address(), rejoin)
	join.connect_requested.connect(_on_join_requested)
	join.back.connect(_show_main_menu.call_deferred)
	_show_screen(join)
	if not problem.is_empty():
		join.show_problem(problem)


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
	if Net.rejoined:
		# Our seat is back: the host sends the run and where it is now; our heroes come once this
		# machine has caught up (_send_seated_ready).
		Sfx.play("net_connected")
		print("Rejoined as peer %d" % peer)
		_players = PlayerRoster.online(_hero_names().size(), NetSession.HOST_PEER, peer)
		_seat_wait = true
		_seat_sent_key = ""
		if _screen is JoinScreen:
			(_screen as JoinScreen).show_status("Back in, catching up ...")
		return
	if Net.joined_mid_run:
		# Dropped into a run already going (card #304): the same catch-up, then a hero of our own.
		Sfx.play("net_connected")
		print("Joined mid-run as peer %d" % peer)
		if _options.is_autoplay():
			print("AUTOPLAY_DROPIN joined peer=%d" % peer)
		_players = PlayerRoster.online(_hero_names().size(), NetSession.HOST_PEER, peer)
		_seat_wait = true
		_seat_sent_key = ""
		if _screen is JoinScreen:
			(_screen as JoinScreen).show_status(JOINING_STATUS)
		return
	# Welcomed by the host: wait on the players screen for its roster and its Start.
	Sfx.play("net_connected")
	_players = PlayerRoster.online(_hero_names().size(), NetSession.HOST_PEER, peer)
	_show_client_lobby()


## An online friend's players screen: the host's roster, waiting for its Start (a new game, or Again
## after a run, card #284).
func _show_client_lobby() -> void:
	var lobby := LobbyScreen.new()
	lobby.name = "Lobby"
	lobby.hero_portraits = _hero_portraits()
	if _run_data != null:
		lobby.oaths = _run_data.oaths
	lobby.setup_online(_hero_names(), _players, false, [] as Array[String], _tuning.net_port)
	lobby.back.connect(_show_main_menu.call_deferred)
	_show_screen(lobby)


## Host: a client left (or its seat's grace time ran out). Before the run it just leaves the list;
## during the run its heroes go to the host for good (and the others are told).
func _on_net_peer_left(peer: int) -> void:
	if _run == null and _screen is LobbyScreen:
		(_screen as LobbyScreen).remove_peer(peer)
		return
	_forget_start_picker(peer)
	if _players.drop_peer(peer):
		print("Player left: peer %d" % peer)
		Sfx.play("player_leave")
		Net.broadcast("roster", {"roster": _players.to_dict()})
		if _combat != null:
			_combat.cancel_resume(peer)
			_combat.update_players(_players, peer)
		_pass_turn()
	_update_away_chip()


## Host: a client's connection went mid-run (card #205). Its seat is kept for the grace time; the
## host plays its heroes meanwhile (their open defence prompts count as not defended), and everyone
## sees "P2 away".
@warning_ignore("integer_division")
func _on_net_peer_away(peer: int) -> void:
	var player := _players.player_of_peer(peer)
	if player < 0:
		# Welcomed but never seated (the --seat-in-fight wait): nothing to keep.
		Net.seats.remove(peer)
		return
	if player > 0 and _players.is_joining(player):
		# Gone before their seat was theirs: no seat is kept; they can drop in again.
		Net.seats.remove(peer)
		_on_net_peer_left(peer)
		return
	if player > 0 and _players.is_away(player):
		# Gone again while catching up (card #205): the seat stays away; the hand-over waits for
		# their next return.
		if _combat != null:
			_combat.cancel_resume(peer)
		_update_away_chip()
		return
	if not _players.set_away(peer):
		return
	print("Player away: P%d (peer %d), seat kept %d s" % [_players.player_of_peer(peer) + 1, peer,
			_tuning.net_rejoin_grace_ms / 1000])
	Sfx.play("player_leave")
	Net.broadcast("roster", {"roster": _players.to_dict()})
	if _combat != null:
		_combat.cancel_resume(peer)
		_combat.update_players(_players, peer)
	_pass_turn()
	_update_away_chip()


## Host: the player who had `old_peer` joined again as `new_peer` with their seat's token. They get
## the run and the screen we are on (in a fight, the fight as it stands at the next hero's turn);
## their heroes come back once their machine has caught up, at a quiet moment (so no attack is
## half theirs).
func _on_net_peer_rejoined(old_peer: int, new_peer: int) -> void:
	var player := _players.rebind_peer(old_peer, new_peer)
	if player < 0 or _run == null:
		Net.kick(new_peer)
		return
	print("Player back: P%d (peer %d, was %d)" % [player + 1, new_peer, old_peer])
	Sfx.play("net_connected")
	# Back during the starting Relics (card #328): their heroes still choosing went without.
	_forget_start_picker(old_peer)
	if not _players.is_away(player):
		# Their old connection had not been noticed as lost yet: it is gone now.
		_players.set_away(new_peer)
		if _combat != null:
			_combat.update_players(_players, old_peer)
	# Net let the old connection go without an away or left signal (card #314): a turn it had passes
	# on now, before the catch-up, so the screen they get carries it.
	_pass_turn()
	if _continued_run:
		# Back in a continued online run (card #313) they count as late: what they banked from it in the
		# session it was saved in is theirs already (a rejoin within this session keeps its own baseline).
		_catch_up(new_peer, true)
	else:
		_catch_up(new_peer, false)
	_update_away_chip()


## Host: sends a player who got in mid-run (back with a token, card #205, or dropping in, #304) the
## run and where it is now (_catch_up_messages), and in a fight its resume at the next quiet moment.
## Their heroes come later, when their machine says it caught up (_on_seated_ready).
func _catch_up(peer: int, late: bool) -> void:
	var mid_fight := not _net_fight.is_empty() and _combat != null
	for message: Dictionary in _catch_up_messages(_run, _players, late, _net_place, _net_fight, mid_fight):
		Net.send_to(peer, String(message.kind), message.payload as Dictionary)
	if mid_fight:
		_combat.queue_resume(peer)


## The messages that catch a player up, in order, each {kind, payload}: run_start (`late`: a drop-in,
## whose Relics count from now), the place screen last sent (`place`: a map, a stop) and the fight
## that followed it (`fight`; `mid_fight`: it is built here, so a resume follows). Each screen carries
## the whole state. Pure.
static func _catch_up_messages(run: RunState, roster: PlayerRoster, late: bool, place: Dictionary,
		fight: Dictionary, mid_fight: bool) -> Array[Dictionary]:
	var messages: Array[Dictionary] = [{"kind": "run_start", "payload": _run_start_message(run, roster, late)}]
	var state := run.to_dict()
	if not place.is_empty():
		var screen := place.duplicate()
		screen["run"] = state
		messages.append({"kind": "screen", "payload": screen})
	# A fight that is over is still sent: its end screen shows there until the host's next screen.
	if not fight.is_empty():
		var screen := fight.duplicate()
		screen["run"] = state
		screen["rejoin"] = mid_fight
		messages.append({"kind": "screen", "payload": screen})
	return messages


## Host, before Net welcomes a newcomer into the run (card #304): "" to let them in, else why not.
func _drop_in_refusal(old_peer: int) -> String:
	if _run == null or _decided_run == _run or _run.is_over():
		return JoinGate.REASON_CLOSED
	if old_peer > 0 and _players.player_of_peer(old_peer) > 0:
		return ""
	return "" if _players.can_join_midrun() else JoinGate.REASON_FULL


## Host: opens or shuts drop-in seats (card #304).
func _set_drop_in(open: bool) -> void:
	if Net.is_host():
		Net.drop_in_open = open


## Host: a friend got in during the run (DESIGN.md 9.3, card #304): a new seat (`old_peer` 0) or
## the seat of the player away longest (a friend whose game crashed and kept no token comes back this
## way; with one in their seat file they rejoin by it, card #313).
func _on_net_peer_dropped_in(peer: int, old_peer: int) -> void:
	# Net asked _drop_in_refusal before the welcome, so this is only a fallback.
	if _run == null or _decided_run == _run or _run.is_over():
		Net.refuse(peer, JoinGate.REASON_CLOSED)
		if old_peer > 0 and _players.player_of_peer(old_peer) > 0:
			# Net gave that seat away already: its old player goes for good.
			_on_net_peer_left(old_peer)
		return
	if _options.is_autoplay() and _options.seat_in_fight:
		_autoplay_seat_in_fight(peer, old_peer)
		return
	_seat_newcomer(peer, old_peer)


## Host: seats the newcomer: the roster (joining: the host keeps playing the hero), everyone told,
## then the catch-up.
func _seat_newcomer(peer: int, old_peer: int) -> void:
	var player := -1
	if old_peer > 0:
		player = _players.rebind_peer(old_peer, peer)
		if player > 0:
			if _combat != null:
				_combat.cancel_resume(old_peer)
		elif _players.player_of_peer(old_peer) > 0:
			# Net gave that seat away already: its old player goes for good.
			_on_net_peer_left(old_peer)
	if player < 0:
		player = _players.join_peer_midrun(peer)
	if player < 0 or not _players.set_joining(peer):
		Net.refuse(peer, JoinGate.REASON_FULL)
		_update_away_chip()
		return
	var mid_fight := not _net_fight.is_empty() and _combat != null
	var place := String(_net_place.get("name", "?"))
	print("Player dropped in: P%d (peer %d%s) at %s%s" % [player + 1, peer,
			", seat of peer %d" % old_peer if old_peer > 0 else "", place, " (fight)" if mid_fight else ""])
	if _options.is_autoplay():
		print("AUTOPLAY_DROPIN P%d peer=%d took=%d place=%s fight=%d" % [player + 1, peer, old_peer, place, int(mid_fight)])
	Sfx.play("player_join")
	Net.broadcast("roster", {"roster": _players.to_dict()})
	if _combat != null:
		_combat.update_players(_players)
	# A seat taken over is the newcomer's now (card #314): a turn the old peer still had passes on.
	_pass_turn()
	# The seat's token is the newcomer's now (an old one stops working): the slot keeps it at once.
	_resave_players()
	_catch_up(peer, true)
	_update_away_chip()


## Host: a client that got in mid-run caught up (`client_fight`: the fight it shows, 0: a place
## screen): its heroes come back now, at the fight's next quiet moment, or not yet (JoinGate.ready_action).
func _on_seated_ready(peer: int, client_fight: int) -> void:
	var player := _players.player_of_peer(peer)
	if player <= 0 or not _players.is_away(player):
		return
	# A fight counts from the moment it was announced (its swirl, nothing built yet): a "caught up on
	# the place screen" that lands then is ignored, and the client says so again once it shows the fight.
	var built := _combat.fight_seed() if _combat != null and _combat.is_inside_tree() else 0
	var host_fight := JoinGate.host_fight(int(_net_fight.get("seed", 0)), built)
	match JoinGate.ready_action(client_fight, host_fight):
		JoinGate.Ready.SEAT_NOW:
			_return_seat(peer)
		JoinGate.Ready.AT_QUIET:
			if _combat != null and _combat.fight_seed() == client_fight:
				_combat.queue_seat(peer)


## Host: peer `peer` plays its own heroes again (everyone is told).
func _return_seat(peer: int) -> void:
	if not _players.set_back(peer):
		return
	print("Player plays again: P%d (peer %d)" % [_players.player_of_peer(peer) + 1, peer])
	if _options.is_autoplay():
		print("AUTOPLAY_SEATED P%d peer=%d" % [_players.player_of_peer(peer) + 1, peer])
	Net.broadcast("roster", {"roster": _players.to_dict()})
	if _combat != null:
		_combat.update_players(_players)
	_update_away_chip()


func _on_net_host_lost() -> void:
	# Still joining (card #304): the host keeps no seat for us, so there is none to take back. The
	# newest roster the host sent: a hand-over may still wait in the queue behind a transition. The
	# roster's own peer, not Net.my_peer(): the connection is already down here.
	var newest := _newest_roster(_net_queue, _players)
	var mine: Array[int] = newest.local_players() if newest != null else [] as Array[int]
	if not mine.is_empty() and newest.is_joining(mine[0]):
		Net.forget_seat()
	if not _client_done and _run != null and Net.has_seat() \
			and (not _options.is_autoplay() or _options.rejoin_after_s > 0):
		_lost_host()
		return
	if not _client_done:
		_autoplay_fail("host_lost")
		Sfx.play("net_error")
	_end_online(_host_gone_notice(_client_done))


## Online friend: the main menu's notice when the host's line goes down. After the end screen
## (`done`) the run is simply over; before it the host left.
static func _host_gone_notice(done: bool) -> String:
	return "The run is over." if done else "The host left the game."


## Client: the newest roster the host sent: the last one still waiting in `queue` (the host's
## messages held behind a transition; roster, run_start and again carry one), else `current`.
static func _newest_roster(queue: Array[Dictionary], current: PlayerRoster) -> PlayerRoster:
	var local_peer := current.local_peer if current != null else 0
	for i: int in range(queue.size() - 1, -1, -1):
		if not String(queue[i].get("kind", "")) in ["roster", "run_start", "again"]:
			continue
		var payload: Variant = queue[i].get("payload")
		if payload is Dictionary and (payload as Dictionary).get("roster") is Dictionary:
			var roster := PlayerRoster.from_dict((payload as Dictionary).roster as Dictionary, local_peer)
			if roster != null:
				return roster
	return current


## Client: the connection to the host went mid-run (card #205). The host keeps our seat for a while:
## the Join screen opens with its address, ready to take the seat back.
@warning_ignore("integer_division")
func _lost_host() -> void:
	var address := Net.seat_address()
	print("Lost the host; seat kept at %s" % address)
	Sfx.play("net_error")
	_leave_online()
	_free_pause()
	_busy = false
	_combat_resync = false
	_run = null
	var grace_s := _tuning.net_rejoin_grace_ms / 1000
	var kept := "%d min" % (grace_s / 60) if grace_s >= 120 else "%d s" % grace_s
	_show_join.call_deferred(address, "Connection lost\nSeat kept %s" % kept, true)
	if _options.rejoin_after_s > 0:
		_autoplay_rejoin_later(address)


func _on_net_refused(reason: String) -> void:
	_autoplay_fail("refused " + reason)
	Sfx.play("net_error")
	if _screen is JoinScreen:
		(_screen as JoinScreen).show_problem(reason)
	else:
		_end_online(reason)


## Online friend in a run: keeps our seat's token on this machine (SeatFile, card #313), so the file
## always holds the token the host's autosaves keep, even when the host crashes or we are away when
## it saves. True if it is kept.
func _keep_seat() -> bool:
	if _run == null or not Net.is_client():
		return false
	return SeatFile.save(Net.seat_address(), Net.seat_token(), Net.seat_file)


## This machine's online game is over: back to the main menu with a note (`glyph`: a picture before
## it, a PauseMenu.RowGlyph kind, card #313).
func _end_online(notice: String, glyph: StringName = &"") -> void:
	_forget_own_start()
	Net.forget_seat()
	_leave_online()
	_notice = notice
	_notice_glyph = glyph
	_free_pause()
	_busy = false
	_show_main_menu.call_deferred()


## Closes the connection and forgets everything that was waiting.
func _leave_online() -> void:
	_flow_gen += 1
	_net_queue.clear()
	_combat_inbox.clear()
	_combat_fight = 0
	_seat_wait = false
	_seat_sent_key = ""
	_screens_seen = 0
	_net_screen = {}
	_sent_run = {}
	_net_place = {}
	_net_fight = {}
	_net_opening = {}
	Net.leave()
	get_tree().auto_accept_quit = true
	_players = PlayerRoster.solo(_hero_names().size())
	_update_away_chip()


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
				if payload.get("op") is Dictionary:
					var op := payload.op as Dictionary
					if String(op.get("op", "")) == BagTab.HAND_OUT:
						_on_hand_out(from_peer, op)
					else:
						_apply_bag_op(op)
			"choice":
				_on_friend_choice(from_peer, payload)
			"start_relic":
				_on_friend_start_relic(from_peer, payload)
			"seated_ready":
				_on_seated_ready(from_peer, int(payload.get("fight", 0)))
		return
	match kind:
		"combat":
			# Batches of the fight shown here go to it; any other fight's wait for that fight.
			if _combat != null and _combat_fight != 0 and int(payload.get("fight", 0)) == _combat_fight:
				_combat.receive_batch(payload)
			else:
				_combat_inbox.add(payload)
		"lobby":
			var roster := PlayerRoster.from_dict(payload.get("roster", {}) as Dictionary, Net.my_peer())
			if roster != null and _screen is LobbyScreen:
				_players = roster
				(_screen as LobbyScreen).set_roster(roster)
				(_screen as LobbyScreen).set_oath(int(payload.get("oath", 0)))
		"opening":
			# The host's First Strike result (DESIGN.md 8.22): at once, not after the transition under
			# way, because this machine's name card is waiting for it.
			_take_net_opening(payload, int(payload.get("fight", 0)))
		"menu":
			# The host ended the game. At once, not after the transition under way: the host's line
			# goes down a moment later, and that must not count as a lost host (no seat to take back).
			_client_done = true
			_end_online("The host ended the game.")
			if _options.is_autoplay():
				print("AUTOPLAY_RESULT host_ended")
				_autoplay_quit()
		"saved":
			# The host saved the run to go on later (card #313). At once too, as "menu": the line goes
			# down a moment later. What the save holds is banked first, as on Leave: the state it carries
			# (inside a stop, as the party entered it), never a newer one. On the Continue we count as
			# late from that state, so what the stop finds is banked when it is played again, once. Our
			# seat's token is kept on this machine (SeatFile), so joining the host again takes the same
			# seat back when it continues.
			_client_done = true
			if payload.get("run") is Dictionary:
				_apply_run(payload)
			_bank_relics()
			var kept := SeatFile.save(Net.seat_address(), Net.seat_token(), Net.seat_file)
			print("The host saved the run%s" % (" (seat kept)" if kept else ""))
			_end_online(HOST_SAVED_NOTICE, &"save")
			if _options.is_autoplay():
				print("AUTOPLAY_SAVED friend seat_kept=%d notice=\"%s\"" % [int(kept), HOST_SAVED_NOTICE])
				print("AUTOPLAY_RESULT host_saved")
				_autoplay_quit()
		_:
			_net_queue.append({"kind": kind, "payload": payload})
			_pump_net()


## Client: handles the host's messages in order, each after the transition the last one started.
func _pump_net() -> void:
	while not _busy and not _net_queue.is_empty() and Net.is_client():
		var m: Dictionary = _net_queue.pop_front()
		_client_message(String(m.kind), m.payload as Dictionary)
	_send_seated_ready()


## Client still catching up (card #304, and #205 rejoins): once this machine shows what the host
## has (a place screen built, or a fight that applied its first batch or the host's resume), tells
## the host so; it hands our heroes over then (now, or at the fight's next quiet moment). Each
## catch-up point is told once; a point the host ignores (we were behind) is followed by the next.
func _send_seated_ready() -> void:
	if not Net.is_client() or not _seat_wait or _run == null or _screens_seen <= 0 or _busy \
			or not _net_queue.is_empty():
		return
	var fight := 0
	if _combat != null and _combat.is_inside_tree():
		if not _combat.has_caught_up():
			return
		fight = _combat_fight
	var key := ("f%d" % fight) if fight != 0 else ("p%d" % _screens_seen)
	if key == _seat_sent_key:
		return
	_seat_sent_key = key
	Net.send_to_host("seated_ready", {"fight": fight})


func _client_message(kind: String, p: Dictionary) -> void:
	match kind:
		"again":
			# The host pressed Again after a run (card #284): wait on the players screen for its Start.
			var again_roster := PlayerRoster.from_dict(p.get("roster", {}) as Dictionary, Net.my_peer())
			if again_roster != null:
				_players = again_roster
			_forget_own_start()
			# A friend who dropped into the last run is there from the next one's start (card #304).
			Net.joined_mid_run = false
			_seat_wait = false
			_seat_sent_key = ""
			_combat_inbox.clear()
			if not _screen is LobbyScreen:
				_run = null
				_client_done = false
				var oath := int(p.get("oath", 0))
				_fade_to(func() -> void:
					_show_client_lobby()
					(_screen as LobbyScreen).set_oath(oath))
			elif again_roster != null:
				(_screen as LobbyScreen).set_roster(again_roster)
				(_screen as LobbyScreen).set_oath(int(p.get("oath", 0)))
		"run_start":
			# A new game (an earlier one in this session may have ended). The host's next screen brings
			# its whole state.
			_client_done = false
			_turn = {}
			_forget_gifts()
			var roster := PlayerRoster.from_dict(p.get("roster", {}) as Dictionary, Net.my_peer())
			if roster != null:
				_players = roster
			var start_seed := int(p.get("seed", 1))
			var game := _client_game(_run_data, _tuning, start_seed, int(p.get("oath", 0)))
			if game == null:
				push_error("Main: the host started a run this machine has no data for")
				_autoplay_fail("run_state_mismatch")
				_end_online("Could not start the game")
				return
			_run = game
			# A run with us in it (a start, a Continue, a drop-in or a rejoin): our token is the one the
			# host's autosaves keep from now on (card #313).
			_keep_seat()
			# The same game again: our seat taken back mid-game (card #205).
			var same_game := _own_start_seed == start_seed
			# A drop-in's catch-up says late (card #304), and so does a continued run's (#313); a token
			# rejoin into a game this machine has no start of (it crashed or was closed, the token came
			# from the seat file) is late too: our Relic file may hold what this run banked already.
			var late := _late_baseline(bool(p.get("late", false)), Net.rejoined, _seat_wait, same_game)
			# The host logs its starting Relics once per game, at its start (card #328): only a friend
			# there from the start logs them too, never one dropping in or back into a continued run.
			_start_log_due = not late and not same_game
			if _own_start == null or not same_game:
				_own_start = RelicFile.load_or_empty(_relics_path()) if _client_relics_ok() else null
				_own_start_seed = start_seed
				# Late (above): the baseline is the first run state. Not Net.joined_mid_run: it would
				# still be up in the run after Again.
				_join_relics = {}
				_join_pending = late
			Sfx.play("run_begin")
			if bool(p.get("continued", false)):
				# The host's saved online run goes on (card #313).
				print("Run continued online: seed %d" % start_seed)
				if _options.is_autoplay():
					var own := _players.local_players()
					print("AUTOPLAY_CONTINUED friend seed=%d seat=%d" % [start_seed, own[0] + 1 if not own.is_empty() else 0])
		"roster":
			var roster := PlayerRoster.from_dict(p.get("roster", {}) as Dictionary, Net.my_peer())
			if roster != null:
				_players = roster
				if _combat != null:
					_combat.update_players(_players)
				_update_away_chip()
				var mine := _players.local_players()
				if _seat_wait and not mine.is_empty() and not _players.is_away(mine[0]):
					# The host handed our heroes over: they answer to this machine from now on.
					_seat_wait = false
					print("Playing now: P%d heroes %s" % [mine[0] + 1, str(_players.heroes_of(mine[0]))])
					if _options.is_autoplay():
						print("AUTOPLAY_SEATED P%d heroes=%d" % [mine[0] + 1, _players.heroes_of(mine[0]).size()])
		"run":
			_apply_run(p)
			_rebuild_watched_screen()
		"screen":
			_apply_run(p)
			_client_screen(p)
		"turn":
			# The turn passed on (its owner dropped or left, card #314): the screen stays, lit or greyed.
			_turn = p.duplicate()
			if not _net_screen.is_empty() and CHOICE_SCREENS.has(String(_net_screen.get("name", ""))):
				_net_screen["turn"] = _turn
			_apply_turn_to_screen()
		"gift":
			_apply_run(p)
			_client_gift(p)
		"start_refused":
			# The host refused a starting Relic (taken first, card #328): that hero chooses again.
			if _screen is StartRelicsScreen:
				var refused_id := String(p.relic) if typeof(p.get("relic")) == TYPE_STRING else ""
				(_screen as StartRelicsScreen).refused(int(p.get("slot", -1)), refused_id)


## Client: shows the screen the host is on.
func _client_screen(p: Dictionary) -> void:
	var name := String(p.get("name", ""))
	if _run == null and name != "menu":
		return
	_screens_seen += 1
	if p.get("turn") is Dictionary:
		_turn = (p.turn as Dictionary).duplicate()
	if _logs_start_relics(_screen is StartRelicsScreen, _start_log_due, name):
		_start_log_due = false
		_log_start_relics()
	if WATCHED_SCREENS.has(name):
		if not _busy and _waits_under_party(name, _net_screen, _screen is PartyScreen):
			# Our own party screen is open over that place (card #314): the map drawn again waits under
			# it; closing it shows that place as it is now.
			_net_screen = p
			_refresh_party_views()
			return
		_net_screen = p
		_fade_to(_watched_screen_builder(p))
		return
	match name:
		"final_fight":
			_net_seed = int(p.get("seed", 1))
			# Read here, not when it arrived: a fight announced later must not change this one.
			_combat_resync = bool(p.get("rejoin", false))
			_start_final_fight(int(_run.current().get("type", -1)) == RunMap.StopType.ELITE)
		"stop_fight":
			# A Fight or Guard stop's fight (DESIGN.md 8.22): built from the host's run state that came
			# with it (fight, place, weather and drop), never rolled here. Its batches wait in the inbox
			# until it is built, as a final fight's do.
			_net_seed = int(p.get("seed", 1))
			_combat_resync = bool(p.get("rejoin", false))
			# A Fight stop's First Strike ring (card #320): watched while the host presses it, the card
			# waiting for its result. A friend who gets in once it is decided (or mid-fight) goes on.
			_take_net_opening(p, _net_seed)
			var ring: FirstStrikeRing = null
			if _watches_first_strike(p, _net_opening):
				ring = _new_first_strike_ring(FirstStrikeRing.Mode.WATCH)
			var zone := _run.zone_now()
			_fade_to(_start_stop_fight, zone.display_name if zone != null else "", true, ring)


## Online friend: true when the host's stop_fight message `p` brings a First Strike ring to watch
## (DESIGN.md 8.22): a Fight stop's, unless its result (`known`, the host's last one) is in already or
## the fight is going on (a friend who got in mid-fight goes straight to it). Pure.
static func _watches_first_strike(p: Dictionary, known: Dictionary) -> bool:
	var fight := int(p.get("seed", 0))
	return bool(p.get("ring", false)) and not bool(p.get("rejoin", false)) and not p.has("opening") \
			and int(known.get("fight", 0)) != fight


## Client: true when host screen `name` comes after the host's starting Relics step (card #328), so
## this machine logs what each hero took, as the host did: from the step's screen (`on_step`), or
## first thing in a game it was in from the start (`due`) when the host skipped the step (an empty
## book, the Empty Hand). Never for the step itself, nor the main menu (a game ended there). Pure.
static func _logs_start_relics(on_step: bool, due: bool, name: String) -> bool:
	return (on_step or due) and name != "start_relics" and name != "menu"


## Client: the function that builds a watched run screen from the host's message.
func _watched_screen_builder(p: Dictionary) -> Callable:
	match String(p.get("name", "")):
		"rest":
			return _show_rest.bind(String(p.get("result", "")))
		"event":
			return _show_event.bind(String(p.get("result", "")), bool(p.get("pact", false)))
		"treasure":
			return _show_treasure.bind(bool(p.get("opened", false)))
		"shop":
			return _show_shop.bind(_gear_from_ids(p.get("gear", []) as Array))
		"loot":
			return _show_loot.bind(_gear_from_ids(p.get("gear", []) as Array), String(p.get("text", "")))
		"party":
			return _show_party.bind(String(p.get("note", "")), true)
		"run_end":
			return _show_run_end
		"start_relics":
			return _show_start_relics.bind(null)
	return _show_map


## Client: the run changed on the host (a purchase, gear): show the watched screen again. A party
## screen (this player may be busy in it) only redraws.
func _rebuild_watched_screen() -> void:
	if _screen is StartRelicsScreen and is_instance_valid(_screen):
		# The starting Relics redraw in place: a pick of ours on its way to the host stays (card #328).
		(_screen as StartRelicsScreen).refresh()
		return
	if _refresh_party_views():
		return
	if _keeps_hero_pick(_screen):
		# Our Relic waits for its hero ("Who gets it?", card #326): a new screen would drop the hero
		# cards. The host's answer to the pick (a new screen) redraws it.
		return
	# A find handed to us is in hand over the screen (card #314): the backpack redraws, the screen
	# stays (a new one would drop it).
	var over := _overlay_of(_screen)
	if over != null:
		over.refresh()
		return
	if _busy or _net_screen.is_empty() or not _is_run_screen(_screen) or _screen is RunEndScreen:
		return
	if _screen is MapScreen:
		# The cursor stays on the stop it was on (the turn's owner may be choosing, card #314).
		var keep := (_screen as MapScreen).selection()
		_show_map(false)
		if _screen is MapScreen:
			(_screen as MapScreen).set_selection(keep)
		return
	if _screen is ShopScreen:
		var shelf := (_screen as ShopScreen).selection()
		_watched_screen_builder(_net_screen).call()
		if _screen is ShopScreen:
			(_screen as ShopScreen).set_selection(shelf)
		return
	_watched_screen_builder(_net_screen).call()


## True while choice screen `screen` shows its "Who gets it?" hero cards for a Relic picked there
## (spoils, the rotten chest, a shop's Relic, an event's Relic): a redraw from the host's newer state
## must not throw the hero step away. Pure.
static func _keeps_hero_pick(screen: Node) -> bool:
	if screen is LootScreen:
		return (screen as LootScreen).is_giving()
	if screen is TreasureScreen:
		return (screen as TreasureScreen).is_giving()
	if screen is EventScreen:
		return (screen as EventScreen).is_giving()
	if screen is ShopScreen:
		return (screen as ShopScreen).is_giving()
	return false


## Host: a friend changed the shared party or backpack (DESIGN.md 8.1): first come, first served. The
## host's open party screen redraws, as the friends' copies do with each new state. True if the
## change was made.
func _apply_bag_op(op: Dictionary) -> bool:
	if _run == null or not _run.apply_op(op):
		return false
	_refresh_party_views()
	return true


## Redraws the open party screen after the run changed. True if one is open.
func _refresh_party_views() -> bool:
	if _screen is PartyScreen and is_instance_valid(_screen):
		(_screen as PartyScreen).refresh()
		return true
	return false


## Online client: asks the host to make a backpack change.
func _send_bag_op(op: Dictionary) -> void:
	if not Net.is_client():
		return
	if String(op.get("op", "")) == BagTab.HAND_OUT:
		# Where the find the host handed us goes (card #314), under its number: the host places only the
		# find it handed out last, and a copy of this one sent again is let go here.
		op = _numbered_placing(op, _gift_held)
		_gift_done = maxi(_gift_done, _gift_held)
	Net.send_to_host("bag", {"op": op})


## A HAND_OUT op for the find numbered `number` the host handed us. Pure.
static func _numbered_placing(op: Dictionary, number: int) -> Dictionary:
	var numbered := op.duplicate()
	numbered["gift"] = number
	return numbered


func _apply_run(p: Dictionary) -> void:
	if _run == null or not p.get("run") is Dictionary:
		return
	if not _run.apply_dict(p.run as Dictionary):
		push_error("Main: the host's run state does not fit this run")
		_autoplay_fail("run_state_mismatch")
		return
	if _join_pending:
		# The first run state after a late run_start: what the run had found when we joined (#304).
		_join_relics = _run.relics.duplicate()
		_join_pending = false
		print("Joined late: %d Relics already found" % _join_relics.size())


## Host: tells the clients which screen to show now, with the run's state.
func _send_screen(p: Dictionary) -> void:
	if not Net.is_host():
		return
	p = p.duplicate()
	var screen_name := String(p.get("name", ""))
	if CHOICE_SCREENS.has(screen_name) and not _turn.is_empty():
		p["turn"] = _turn.duplicate()
		_net_choice = p.duplicate()
	var message := p.duplicate()
	if _run != null:
		_sent_run = _run.to_dict()
		message["run"] = _sent_run
	Net.broadcast("screen", message)
	# Kept for a player who joins again (without the run: theirs is sent fresh): a fight going on apart
	# from the place it started from.
	if NET_FIGHT_SCREENS.has(screen_name):
		_net_fight = p.duplicate()
	else:
		_net_place = p.duplicate()
		_net_fight = {}


## Host, every frame: run changes (purchases, gear, levels) go out.
func _net_host_tick() -> void:
	if _run != null and not _sent_run.is_empty():
		var now := _run.to_dict()
		if now != _sent_run:
			_sent_run = now
			Net.broadcast("run", {"run": now})


# --- taking turns (card #314, DESIGN.md 9.2) ----------------------------------------------------

## A new run: nobody has had a turn yet (the first choice is P1's).
func _reset_turns() -> void:
	_turns.reset()
	_turn = {}
	_choice_queue.clear()
	_net_choice = {}
	_gift_peer = 0


## Host, online: choice screen `screen_name` is about to be built. A new one belongs to the next
## seated player; the same screen shown again keeps its owner. With Take turns off (Settings, Game)
## the host makes every choice.
func _begin_choice(screen_name: String) -> void:
	if not Net.is_host() or _run == null or _players == null:
		return
	_turns.enabled = PlayerSettings.take_turns()
	var key := _choice_key_of(screen_name, _run)
	if key.is_empty():
		return
	var was := _turns.key
	_turns.turn_for(key, _players)
	_turn = _turns.to_dict()
	if key != was:
		print("Turn: %s %s" % [HudStyle.player_tag(_turns.player), key])


## The turn key of choice screen `screen_name` with `run` as it is now. The same screen shown again
## (a redraw, a result, a restock) has the same key. "" for a screen with no choice. Pure.
static func _choice_key_of(screen_name: String, run: RunState) -> String:
	if run == null:
		return ""
	var stop := "%d:%d" % [run.act, run.visited]
	match screen_name:
		"map":
			return "map:" + stop
		"rest", "shop", "event", "treasure":
			return "stop:" + stop
		"pact":
			return "pact"
		"loot":
			return "loot:" + stop
	return ""


## Online: true when this machine makes the choice on the screen up now. Always offline.
func _my_turn() -> bool:
	if not Net.is_online():
		return true
	if _turn.is_empty():
		return Net.is_host()
	return int(_turn.get("peer", ChoiceTurns.HOST_PEER)) == Net.my_peer()


## Online friend whose turn it is: where its screen's choices go (to the host). Else none.
func _asker() -> Callable:
	return _ask_host if Net.is_client() and _my_turn() else Callable()


## Online friend whose turn it is: asks the host to make `choice` on the screen up now.
func _ask_host(choice: Dictionary) -> void:
	var key := String(_turn.get("key", ""))
	print("Choice asked: %s %s key=%s" % [HudStyle.player_tag(int(_turn.get("player", 0))), _choice_word(choice), key])
	Net.send_to_host("choice", {"key": key, "choice": choice})


## A choice in a few words for the log ("stop id=5", "buy index=2").
static func _choice_word(choice: Dictionary) -> String:
	var parts := PackedStringArray([String(choice.get("do", "?"))])
	for field: String in ["id", "index", "uid", "pick", "rotten", "hero"]:
		if choice.has(field):
			parts.append("%s=%s" % [field, str(choice[field])])
	return " ".join(parts)


## Before a choice screen is set up (host and friends): greyed on another player's turn, asking the
## host on a friend's own turn; on the host, a find with no room on a friend's turn goes to them. A
## screen that gives Relics learns who may get them (_give_heroes, also offline).
func _wire_turn(screen: Node) -> void:
	if screen != null and "give_heroes" in screen:
		screen.set("give_heroes", _give_heroes)
	if not Net.is_online() or screen == null:
		return
	var watching := not _my_turn()
	var asker := _asker()
	if screen is StopScreen:
		var stop := screen as StopScreen
		stop.watching = watching
		stop.asks = asker
		if Net.is_host():
			stop.hand_off = _hand_gift if watching else Callable()
		elif not stop.op_requested.is_connected(_send_bag_op):
			stop.op_requested.connect(_send_bag_op)
	elif screen is ShopScreen:
		var shop := screen as ShopScreen
		shop.watching = watching
		shop.asks = asker
		if Net.is_host():
			shop.hand_off = _hand_gift if watching else Callable()
		elif not shop.op_requested.is_connected(_send_bag_op):
			shop.op_requested.connect(_send_bag_op)
	elif screen is LootScreen:
		(screen as LootScreen).set_turn(watching, asker)
	elif screen is MapScreen:
		(screen as MapScreen).asks = asker


## The heroes who may get a Relic picked on this machine with `device` (DESIGN.md 8.24; the screens'
## give_heroes): online with Take turns on, the heroes of the player whose turn it is (the host checks
## a friend's pick against these); local co-op, the heroes of the player whose pad picked. Empty (every
## hero, RelicGift.allowed) solo, with Take turns off, or when the pad is not known.
func _give_heroes(device: int) -> Array[int]:
	var none: Array[int] = []
	if _run == null or _players == null:
		return none
	if Net.is_online():
		if _turn.is_empty() or (Net.is_host() and not _turns.enabled):
			return none
		return _players.heroes_of(int(_turn.get("player", 0)))
	if _players.player_count() > 1 and device != PlayerRoster.ANY:
		var player := _players.player_of_device(device)
		if player >= 0:
			return _players.heroes_of(player)
	return none


## The turn changed with the screen still up (a drop passed it on): the screen redraws for it, and so does the chip; on the host a find in a friend's hands follows the turn
## (to the new owner, or back into this machine's backpack).
func _apply_turn_to_screen() -> void:
	_update_watch_chip()
	var screen := _screen
	if not Net.is_online() or not is_instance_valid(screen) or not _is_choice_screen(screen):
		return
	var watching := not _my_turn()
	var asker := _asker()
	if screen is StopScreen:
		var stop := screen as StopScreen
		if Net.is_host():
			stop.hand_off = _hand_gift if watching else Callable()
		stop.set_turn(watching, asker)
	elif screen is ShopScreen:
		var shop := screen as ShopScreen
		if Net.is_host():
			shop.hand_off = _hand_gift if watching else Callable()
		shop.set_turn(watching, asker)
	elif screen is LootScreen:
		(screen as LootScreen).set_turn(watching, asker)
	elif screen is MapScreen:
		(screen as MapScreen).asks = asker
	if Net.is_host() and _owes(screen):
		match _owed_step(_gift_peer, int(_turn.get("peer", ChoiceTurns.HOST_PEER))):
			OwedStep.HAND:
				_hand_gift(screen)
			OwedStep.TAKE_BACK:
				_gift_peer = 0
				screen.call("take_back_owed")
	_autoplay_choice(screen)


func _is_choice_screen(node: Node) -> bool:
	return node is MapScreen or node is ShopScreen or node is RestScreen or node is LootScreen \
			or node is EventScreen or node is TreasureScreen


## Host: the turn's owner dropped or left (card #314): the turn passes on to the next seated player,
## and everyone's screen and chip follow. Also follows their seat moving up when someone left. Only
## while the turn's screen is still up: a turn already used (its choice made, the party in a fight or
## on the spoils' party screen) stays with who used it, so the next screen counts on from them.
func _pass_turn() -> void:
	if not Net.is_host() or _turn.is_empty() or not _turn_on_screen(_net_place, _net_fight, _run, _turns.key):
		return
	_turns.pass_if_gone(_players)
	var now := _turns.to_dict()
	if now == _turn:
		return
	_turn = now
	print("Turn passes: %s %s" % [HudStyle.player_tag(_turns.player), _turns.key])
	_send_turn()


## Host: true while the choice screen of the turn `key` is still the place everyone is on (`place`:
## the place screen last sent, `fight`: a fight sent after it, `run` as it is now). False once its
## choice is made: a fight began, the party screen after spoils is up, or the map step was taken (the
## map's key moved on). Pure.
static func _turn_on_screen(place: Dictionary, fight: Dictionary, run: RunState, key: String) -> bool:
	var screen_name := String(place.get("name", ""))
	if key.is_empty() or not fight.is_empty() or not CHOICE_SCREENS.has(screen_name):
		return false
	if screen_name == "event" and bool(place.get("pact", false)):
		screen_name = "pact"
	return _choice_key_of(screen_name, run) == key


## Host: everyone gets the turn as it is now (it changed with the screen still up). A friend who gets
## in later is caught up with it too.
func _send_turn() -> void:
	Net.broadcast("turn", _turn)
	for kept: Dictionary in [_net_place, _net_choice]:
		if CHOICE_SCREENS.has(String(kept.get("name", ""))):
			kept["turn"] = _turn.duplicate()
	_apply_turn_to_screen()


## Host: a friend asks to make a choice on their turn (card #314). It is made only when it is their
## turn on the screen up now and the screen can take it, exactly as if pressed here; what came of it
## goes out as usual (a new screen, a new state). Anything else is dropped (their screen still shows
## what is true). During a transition it waits for its end.
func _on_friend_choice(from_peer: int, payload: Dictionary) -> void:
	var key := String(payload.get("key", ""))
	var choice: Variant = payload.get("choice")
	var who := HudStyle.player_tag(maxi(0, _players.player_of_peer(from_peer))) if _players != null else "P?"
	if not choice is Dictionary or _run == null or not _turns.allows(from_peer, key):
		print("Choice refused: %s key=%s (turn %s)" % [who, key, _turns.key])
		return
	if _busy:
		_choice_queue.append({"peer": from_peer, "payload": payload})
		return
	_back_to_choice_screen()
	if from_peer == _gift_peer and _owes(_screen):
		# Their find with no room is still waiting to be placed (their copy may not have it in hand):
		# it goes to them again, and that comes first.
		print("Choice refused: %s %s key=%s (a find to place first)" % [who, _choice_word(choice as Dictionary), key])
		_send_gift(_screen)
		return
	var done := _make_choice(_screen, choice as Dictionary)
	if done.is_empty():
		print("Choice refused: %s %s key=%s" % [who, _choice_word(choice as Dictionary), key])
		return
	print("Choice: %s %s key=%s" % [who, done, key])
	if _options != null and _options.is_autoplay():
		print("AUTOPLAY_CHOICE %s %s key=%s" % [who, done, key])
		_autoplay_spend_points()


## Host: a friend chose while the host had its own party screen open over the map (a look at the
## party, never a find in hand): the map goes back first.
func _back_to_choice_screen() -> void:
	if not _screen is PartyScreen or (_screen as PartyScreen).close_when_settled:
		return
	var place := String(_net_place.get("name", ""))
	if place == "map" and place == String(_net_choice.get("name", "")):
		_show_map(false)


## Makes a friend's choice `choice` ({"do": ...}) on `screen` if it can take it now: a stop on the
## map, Rest or Train at a campfire, a purchase or a service, an event's choice, a chest or a spoil.
## Returns what was done in a few words, "" if it was refused.
static func _make_choice(screen: Node, choice: Dictionary) -> String:
	var what := String(choice.get("do", ""))
	var index := int(choice.get("index", -1))
	# The hero who gets a picked Relic (DESIGN.md 8.24); the screen checks it is one of the turn's
	# player's heroes.
	var hero := int(choice.get("hero", -1))
	if screen is MapScreen:
		var id := int(choice.get("id", -1))
		if what != "stop" or not (screen as MapScreen).choices().has(id):
			return ""
		(screen as MapScreen).choose(id)
		return "stop %d" % id
	if screen is ShopScreen:
		var shop := screen as ShopScreen
		if shop.is_settling():
			return ""
		match what:
			"buy":
				return "buy %d" % index if shop.can_buy(index) and shop.buy(index, hero) else ""
			"restock":
				return what if shop.restock() else ""
			"cleanse":
				# The curse and the count the friend saw (card #332): a second press made before the
				# first came back names a list that is gone, and is refused.
				var id := String(choice.get("id", ""))
				var seen := int(choice.get("seen", -1))
				return "cleanse %d" % index if not id.is_empty() and shop.cleanse(index, id, seen) else ""
			"leave":
				shop.leave()
				return what
		return ""
	if screen is LootScreen:
		var loot := screen as LootScreen
		if what != "take" or loot.is_taken() or index < 0 or index >= maxi(1, loot.choices().size()):
			return ""
		return "take %d" % index if loot.take(index, hero) else ""
	if not screen is StopScreen or (screen as StopScreen).is_settling():
		return ""
	if what == "leave":
		# As the screens' own leave(): Back to the map, Continue, or Fight after an ambush, only once
		# the screen shows that way on (an undecided event's way out is walk_on).
		if not _can_leave(screen):
			return ""
		screen.call("leave")
		return what
	if screen is RestScreen:
		return _make_rest_choice(screen as RestScreen, what)
	if screen is EventScreen:
		var event := screen as EventScreen
		if what == "choose":
			return "choose %d" % index if event.choose(index, int(choice.get("pick", -1)), hero) else ""
		if what == "walk_on":
			return what if event.walk_on() else ""
		return ""
	if screen is TreasureScreen:
		var chest := screen as TreasureScreen
		if what == "relic":
			return "relic %d" % index if chest.take_relic(index, hero) else ""
		if what != "open" or chest.is_open():
			return ""
		var rotten := bool(choice.get("rotten", false))
		chest.open_chest(rotten)
		return "open rotten" if rotten else "open plain"
	return ""


## True when stop screen `screen` shows its way on (Back to the map, Continue, or Fight): a campfire
## once used, a chest once opened (and its Relic pick taken), an event once decided or on its ambush
## page. Pure.
static func _can_leave(screen: Node) -> bool:
	if screen is RestScreen:
		return (screen as RestScreen).has_acted()
	if screen is TreasureScreen:
		var chest := screen as TreasureScreen
		return chest.is_open() and not chest.relic_waiting()
	if screen is EventScreen:
		var event := screen as EventScreen
		return event.is_decided() or event.is_ambush_page() or event.event() == null
	return false


## A friend's campfire choice: Rest, then Train at a normal fire, Keep watch or Sharpen at the fire
## before the boss. Once only. "" if refused.
static func _make_rest_choice(rest: RestScreen, what: String) -> String:
	if rest.has_acted():
		return ""
	var watch := rest.run.is_watch_fire()
	if what == "rest":
		rest.rest_now()
	elif what == "train" and not watch:
		rest.train_now()
	elif what == "watch" and watch:
		rest.watch_now()
	elif what == "sharpen" and watch:
		rest.sharpen_now()
	else:
		return ""
	return what


## Host, a friend's turn (card #314): their find with no room (a gift or a purchase) goes to them to
## place: their backpack opens with it in hand, and what they do there comes back as a HAND_OUT op.
## Back on this machine's turn, it opens here instead.
func _hand_gift(screen: Node) -> void:
	if not _owes(screen) or _run == null:
		return
	var peer := int(_turn.get("peer", ChoiceTurns.HOST_PEER))
	if peer == ChoiceTurns.HOST_PEER:
		_gift_peer = 0
		screen.call("take_back_owed")
		return
	# A new hand-out: a placing sent for an earlier one no longer counts.
	_gift_no += 1
	_gift_peer = peer
	_send_gift(screen)


## Host: sends the friend holding it (_gift_peer) the find owed on `screen`, under its number. Sent
## again, it is the same find: their copy never holds it twice.
func _send_gift(screen: Node) -> void:
	if not _owes(screen) or _run == null or _gift_peer <= 0:
		return
	var owed: Dictionary = screen.call("owed")
	var item := owed.get("item") as ItemData
	print("Gift handed: %s %s (%d)" % [HudStyle.player_tag(maxi(0, _players.player_of_peer(_gift_peer))), item.id, _gift_no])
	Net.send_to(_gift_peer, "gift", {"key": String(_turn.get("key", "")), "gift": _gift_no,
			"note": String(owed.get("note", "")), "item": item.id, "refund": screen is ShopScreen, "run": _run.to_dict()})


## Host: true when `screen` owes a friend a find to place (handed to them, not placed yet).
static func _owes(screen: Node) -> bool:
	if not is_instance_valid(screen) or not screen.has_method("owed"):
		return false
	return (screen.call("owed") as Dictionary).get("item") is ItemData


## Host: what becomes of a find owed to a friend (`with_peer`, the machine it was handed to) when the
## turn changes to `turn_peer`'s machine: back into the host's own backpack on the host's turn, handed
## to the new owner, or kept where it is (the same machine still owns the turn: their seat moved up).
## Pure.
static func _owed_step(with_peer: int, turn_peer: int) -> int:
	if turn_peer == ChoiceTurns.HOST_PEER:
		return OwedStep.TAKE_BACK
	return OwedStep.KEEP if with_peer == turn_peer else OwedStep.HAND


## Host: the friend whose turn it is put the find we handed them somewhere (card #314): it goes where
## they chose. A placing for an earlier hand-out (the find went to them again, or to someone else
## since) is let go. If it no longer fits (the backpack changed meanwhile), it is handed to them again.
func _on_hand_out(from_peer: int, op: Dictionary) -> void:
	var screen := _screen
	if not _owes(screen) or not screen.has_method("settle_owed"):
		return
	if not _placing_counts(from_peer, op, _gift_peer, _gift_no, _turns.peer):
		print("Gift placing let go: peer %d (%d) for %d" % [from_peer, int(op.get("gift", 0)), _gift_no])
		return
	if screen.call("settle_owed", op):
		_gift_peer = 0
		print("Choice: %s placed %s" % [HudStyle.player_tag(maxi(0, _players.player_of_peer(from_peer))),
				String(op.get("to", ""))])
	else:
		_hand_gift(screen)


## Host: true when HAND_OUT op `op` from machine `from_peer` places the find handed out now: number
## `gift_no`, with `gift_peer`, whose turn it still is (`turn_peer`). Pure.
static func _placing_counts(from_peer: int, op: Dictionary, gift_peer: int, gift_no: int, turn_peer: int) -> bool:
	return gift_peer > 0 and from_peer == gift_peer and from_peer == turn_peer and int(op.get("gift", 0)) == gift_no


## Online friend (card #314): the host handed us a find to place (our turn, no room for it): the
## backpack opens over the screen with it in hand, now or once a screen that can take it is up (it
## waits under our own party screen, the shop's Sell backpack or a transition).
func _client_gift(p: Dictionary) -> void:
	if _run == null or not _run.items_by_id().get(String(p.get("item", ""))) is ItemData:
		return
	_pending_gift = p.duplicate()
	_offer_pending_gift()


## Online friend: opens the find the host handed us (_pending_gift) once the screen up can take it,
## or lets it go when it is no longer ours to place (GiftStep).
func _offer_pending_gift() -> void:
	if _pending_gift.is_empty() or _run == null:
		return
	var holding := is_instance_valid(_gift_overlay) and _overlay_of(_screen) == _gift_overlay
	match _gift_step(_pending_gift, String(_turn.get("key", "")), _my_turn(), _gift_held, holding, _gift_done,
			_screen, _busy):
		GiftStep.DROP:
			_pending_gift = {}
		GiftStep.HOLD:
			var p := _pending_gift
			_pending_gift = {}
			var item := _run.items_by_id().get(String(p.get("item", ""))) as ItemData
			if item == null:
				return
			var held := {"item": item, "refund": bool(p.get("refund", false))}
			var note := String(p.get("note", ""))
			if _screen is StopScreen:
				(_screen as StopScreen).hold_gift(note, held)
			else:
				(_screen as ShopScreen).hold_gift(note, held)
			_gift_held = int(p.get("gift", 0))
			_gift_overlay = _overlay_of(_screen)
			print("Gift in hand: %s (%d)" % [item.id, _gift_held])
			if _options.is_autoplay():
				_autoplay_settle_over.call_deferred(_screen)


## Online friend: what becomes of find `gift` the host handed us ({"key", "gift", "item", ...}) with
## the turn now (`turn_key`, `my_turn`) and the screen up (`screen`, `busy`: a transition): DROP it
## when it is no longer ours to place (the turn moved on, or it was placed already: number at or
## under `done`), or when that very find is in hand already (number `held`, `holding`: its backpack is
## open); HOLD it now on a stop screen or the shop with no backpack open; else WAIT. Pure.
static func _gift_step(gift: Dictionary, turn_key: String, my_turn: bool, held: int, holding: bool, done: int,
		screen: Node, busy: bool) -> int:
	var number := int(gift.get("gift", 0))
	if number <= done or not my_turn or String(gift.get("key", "")) != turn_key:
		return GiftStep.DROP
	if holding and number == held:
		return GiftStep.DROP
	if busy or not is_instance_valid(screen) or not (screen is StopScreen or screen is ShopScreen):
		return GiftStep.WAIT
	return GiftStep.WAIT if _overlay_of(screen) != null else GiftStep.HOLD


## Online friend: a new game (or the same one caught up again): no find from the host waits, and the
## bot has bought from no shelf.
func _forget_gifts() -> void:
	_pending_gift = {}
	_gift_held = 0
	_gift_done = 0
	_gift_overlay = null
	_bot_shelves = {}


## Online friend: true when the host's screen message `name` is the place our own party screen was
## opened over (`last`: the host's screen message before it; `on_party`: a party screen is up), so it
## waits under the party screen instead of replacing it: the map drawn again (card #314). A party
## screen the host sent ("party") follows the host as before. Pure.
static func _waits_under_party(name: String, last: Dictionary, on_party: bool) -> bool:
	return on_party and name == "map" and String(last.get("name", "")) == name


## The backpack open over a stop screen or the shop (null: none).
static func _overlay_of(screen: Node) -> PartyScreen:
	if screen is StopScreen:
		return (screen as StopScreen).overlay()
	if screen is ShopScreen:
		return (screen as ShopScreen).overlay()
	return null


## The whose-turn chip: online with two or more players, over a choice screen: a person's sign and
## the tag of the player whose turn it is, in their colour.
func _update_watch_chip() -> void:
	if _watch_layer == null:
		return
	var shown := Net.is_online() and _players != null and _players.player_count() > 1 and not _turn.is_empty() \
			and is_instance_valid(_screen) and _is_choice_screen(_screen)
	_watch_layer.visible = shown
	if not shown:
		return
	var player := int(_turn.get("player", 0))
	var color := HudStyle.player_color(player)
	_watch_label.text = HudStyle.player_tag(player)
	_watch_label.label_settings.font_color = color
	_watch_icon.color = color
	_watch_icon.queue_redraw()


## Autoplay: plays choice screen `screen` when its choice is this machine's (online: its turn), once
## per screen and turn. A friend's bot asks the host, as a player would.
func _autoplay_choice(screen: Node) -> void:
	if not _options.is_autoplay() or not is_instance_valid(screen) or not _my_turn():
		return
	var key := String(_turn.get("key", ""))
	if screen.has_meta(&"autoplay_key") and String(screen.get_meta(&"autoplay_key")) == key:
		return
	screen.set_meta(&"autoplay_key", key)
	if screen is MapScreen:
		_autoplay_map.call_deferred(screen)
	elif screen is RestScreen:
		_autoplay_rest.call_deferred(screen)
	elif screen is ShopScreen:
		_autoplay_shop.call_deferred(screen)
	elif screen is EventScreen:
		_autoplay_event.call_deferred(screen)
	elif screen is TreasureScreen:
		_autoplay_treasure.call_deferred(screen)
	elif screen is LootScreen:
		_autoplay_loot.call_deferred(screen)


## Autoplay: the bot still plays `screen`: it is up, and the turn it started on is still this
## machine's. Untyped: a friend's screen is often freed under the bot (the host's answer redraws it).
func _autoplay_turn_ok(screen: Variant) -> bool:
	if not is_instance_valid(screen) or not _my_turn():
		return false
	var node := screen as Node
	if node == null or not node.is_inside_tree():
		return false
	return not node.has_meta(&"autoplay_key") or String(node.get_meta(&"autoplay_key")) == String(_turn.get("key", ""))


## Autoplay: does `act` on `screen`. A friend's bot asks the host, so it asks again every
## AUTOPLAY_ASK_AGAIN_S while the screen stays up and the turn is still ours (a choice the host could
## not take yet, say while a find in hand settles). The host's bot acts once.
func _autoplay_act(screen: Variant, act: Callable) -> void:
	for attempt: int in AUTOPLAY_ASK_TRIES:
		if not _autoplay_turn_ok(screen):
			return
		await _autoplay_settle_over(screen)
		if not _autoplay_turn_ok(screen):
			return
		var before := _run.to_dict() if _run != null else {}
		act.call()
		if not Net.is_client():
			return
		await get_tree().create_timer(AUTOPLAY_ASK_AGAIN_S).timeout
		if _run != null and _run.to_dict() != before:
			# The host made a change meanwhile: its next screen (and that screen's bot) follows.
			return


## Autoplay: settles the backpack open over `screen` with a find in hand, until none is.
func _autoplay_settle_over(screen: Variant) -> void:
	while is_instance_valid(screen) and _overlay_of(screen) != null:
		await get_tree().create_timer(AUTOPLAY_RETURN_S).timeout
		var over := _overlay_of(screen) if is_instance_valid(screen) else null
		if over != null:
			_autoplay_settle(over)
			if is_instance_valid(screen) and _overlay_of(screen) == over:
				over.close()


func _is_run_screen(node: Node) -> bool:
	return node is MapScreen or node is ShopScreen or node is RestScreen or node is LootScreen \
			or node is PartyScreen or node is RunEndScreen or node is EventScreen or node is TreasureScreen \
			or node is StartRelicsScreen


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


## Whose turn it is (card #314): a chip over the run's choice screens online, a person's sign and
## the player's tag (P2) in their colour. No sentence.
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
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_watch_layer.add_child(box)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	_watch_icon = UiGlyph.make(&"person", TURN_ICON_PX, HudStyle.player_color(0))
	_watch_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_watch_icon)
	_watch_label = HudStyle.make_label(HudStyle.player_tag(0), WATCH_TEXT_SIZE, HudStyle.player_color(0))
	row.add_child(_watch_label)


## Autoplay client (--drop-after=S, card #205): drops off the network without a word mid-run, like
## a pulled cable; the host notices through the heartbeat.
func _autoplay_drop_later() -> void:
	await get_tree().create_timer(float(_options.drop_after_s)).timeout
	if _options.drop_in_fight:
		while Net.is_client() and (_combat == null or not _combat.is_inside_tree()):
			await get_tree().create_timer(AUTOPLAY_DROP_POLL_S).timeout
		await get_tree().create_timer(AUTOPLAY_DROP_INTO_FIGHT_S).timeout
	if not Net.is_client():
		return
	print("AUTOPLAY_DROPPED after %d s%s" % [_options.drop_after_s, " (in a fight)" if _combat != null else ""])
	Net.drop_silently()


## Autoplay client (--crash-after=S, card #304): quits without a goodbye, like a crash; the host
## notices through the heartbeat and keeps the seat away.
func _autoplay_crash_later() -> void:
	await get_tree().create_timer(float(_options.crash_after_s)).timeout
	if not Net.is_client():
		return
	print("AUTOPLAY_CRASHED after %d s" % _options.crash_after_s)
	_client_done = true
	Net.drop_silently()
	get_tree().quit()


## Autoplay host (--seat-in-fight, card #304): seats a newcomer a few seconds into the next fight
## (they wait on "Joining the game ..." meanwhile; one who leaves first has no seat, _on_net_peer_away).
func _autoplay_seat_in_fight(peer: int, old_peer: int) -> void:
	while Net.is_host() and _run != null and not _run.is_over() and (_combat == null or not _combat.is_inside_tree()):
		await get_tree().create_timer(AUTOPLAY_DROP_POLL_S).timeout
	await get_tree().create_timer(AUTOPLAY_DROP_INTO_FIGHT_S).timeout
	if not Net.is_host() or not Net.clients().has(peer):
		return
	if _run != null and _decided_run != _run and not _run.is_over():
		_seat_newcomer(peer, old_peer)
	else:
		Net.refuse(peer, JoinGate.REASON_CLOSED)


## Autoplay, local (--pad-join-after / --pad-leave-after, cards #304, #311): S seconds after launch
## (with --roster-in-fight: a few seconds into the next fight) a pretend pad joins, or the last
## player leaves, through _change_local_roster (the next quiet moment).
func _autoplay_pad_roster_later(join: bool) -> void:
	var why := "join" if join else "leave"
	await get_tree().create_timer(float(_options.pad_join_after_s if join else _options.pad_leave_after_s)).timeout
	if _options.roster_in_fight:
		while _run != null and not _run.is_over() and (_combat == null or not _combat.is_inside_tree()):
			await get_tree().create_timer(AUTOPLAY_DROP_POLL_S).timeout
		await get_tree().create_timer(AUTOPLAY_DROP_INTO_FIGHT_S).timeout
	while _busy:
		await get_tree().process_frame
	if _run == null or _run.is_over():
		print("AUTOPLAY_ROSTER skipped")
		return
	var next := _players.copy()
	var changed := false
	if join:
		changed = next.join_midrun(PlayerRoster.free_pad(next)) >= 0
	else:
		changed = next.leave_midrun(next.player_count() - 1)
	if not changed:
		print("AUTOPLAY_ROSTER refused %s" % why)
		return
	_change_local_roster(next, why)


## Autoplay client (--join-after=S): connects S seconds after launch, into a run already going.
func _autoplay_join_later(address: String) -> void:
	await get_tree().create_timer(float(_options.join_after_s)).timeout
	print("AUTOPLAY_JOIN after %d s" % _options.join_after_s)
	_on_join_requested(address)


## Autoplay client (--rejoin=S): joins the host again S seconds after losing it.
func _autoplay_rejoin_later(address: String) -> void:
	await get_tree().create_timer(float(_options.rejoin_after_s)).timeout
	if _screen is JoinScreen and not Net.is_online():
		print("AUTOPLAY_REJOIN %s" % address)
		(_screen as JoinScreen).submit(address)


## "P2 away" (with the seat's time left on the host) while a player's connection is gone.
func _build_away_chip() -> void:
	_away_layer = CanvasLayer.new()
	_away_layer.name = "AwayChip"
	_away_layer.layer = AWAY_LAYER
	_away_layer.visible = false
	add_child(_away_layer)
	# Top-right: the watch note sits top-left, the run screens' titles in the middle.
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", HudStyle.panel())
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.offset_left = -WATCH_MARGIN_PX
	box.offset_right = -WATCH_MARGIN_PX
	box.offset_top = WATCH_MARGIN_PX
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_away_layer.add_child(box)
	_away_label = HudStyle.make_label("", WATCH_TEXT_SIZE, HudStyle.TEXT)
	box.add_child(_away_label)


@warning_ignore("integer_division")
func _update_away_chip() -> void:
	if _away_layer == null:
		return
	var lines: Array[String] = []
	if Net.is_online() and _players != null:
		for player: int in _players.away:
			if _players.is_joining(player):
				# Getting in (card #304): no seat time runs for them.
				lines.append("%s joining" % HudStyle.player_tag(player))
				continue
			var line := "%s away" % HudStyle.player_tag(player)
			if Net.is_host() and player < _players.peers.size():
				var left_s := ceili(float(Net.seat_time_left(_players.peers[player])) / 1000.0)
				line += ", seat kept %d:%02d" % [left_s / 60, left_s % 60]
			lines.append(line)
	_away_layer.visible = not lines.is_empty()
	if lines.is_empty():
		return
	_away_label.text = "\n".join(lines)
	_away_label.label_settings.font_color = HudStyle.player_color(_players.away[0])


## Autoplay client (--leave-after=S): leaves the game mid-run, as a player quitting would.
func _autoplay_leave_later() -> void:
	await get_tree().create_timer(float(_options.leave_after_s)).timeout
	print("AUTOPLAY_LEFT after %d s" % _options.leave_after_s)
	_client_done = true
	Net.leave()
	_quit_game()


## Autoplay host (--end-after=S): ends the game for everyone mid-run, as End the game would.
func _autoplay_end_later() -> void:
	await get_tree().create_timer(float(_options.end_after_s)).timeout
	while Net.is_host() and _busy:
		await get_tree().process_frame
	if not Net.is_host() or _run == null or _run.is_over():
		return
	print("AUTOPLAY_ENDED after %d s" % _options.end_after_s)
	_abandon_run()
	print("AUTOPLAY_RESULT host_ended")
	_autoplay_quit()


## Autoplay host (--host=N): everyone is in, start (--continue-online: the saved online run, card #313).
func _autoplay_start_online() -> void:
	await get_tree().create_timer(AUTOPLAY_RETURN_S).timeout
	if not _screen is LobbyScreen:
		return
	var lobby := _screen as LobbyScreen
	if not _options.continue_online:
		_on_online_started(lobby.roster(), lobby.oath())
	elif lobby.has_continue():
		_on_online_continued(lobby.roster())
	elif not _busy:
		_autoplay_fail("no_online_save")


# --- autoplay ---------------------------------------------------------------------------------

## Autoplay: waits on the end screen, then goes on the way the player would.
func _autoplay_continue(result: String, continue_to: Callable) -> void:
	await get_tree().create_timer(AUTOPLAY_RETURN_S).timeout
	continue_to.call(result)


## Autoplay on the map: a shop when there is gold to spend, a rest when someone is hurt, else a
## fight (so a run tries every kind of stop). Healing items go on whoever is low first, at every map
## visit, so also before every Elite stop.
func _autoplay_map(map: MapScreen) -> void:
	await get_tree().create_timer(AUTOPLAY_RETURN_S).timeout
	if not _autoplay_turn_ok(map) or _run == null:
		return
	if Net.is_client() and _choice_key_of("map", _run) != String(_turn.get("key", "")):
		# The party already left this map (the host's next screen is on its way): nothing to choose.
		return
	_autoplay_use_items()
	var pick := -1
	var cheapest := 1 << 30
	for item: ItemData in _run_data.shop_items:
		cheapest = mini(cheapest, item.price)
	var hurt := _autoplay_hurt()
	# Treasure first, a shop with gold, a campfire when hurt, Elite stops (an elite group or the
	# place's guard) when healthy, then events and fights (each kind gets played).
	for wanted: int in [RunMap.StopType.TREASURE, RunMap.StopType.SHOP if _run.gold >= cheapest else -1,
			RunMap.StopType.REST if hurt else -1, RunMap.StopType.ELITE if _autoplay_elite_ready() else -1,
			RunMap.StopType.EVENT, RunMap.StopType.FIGHT]:
		for id: int in map.choices():
			if pick < 0 and int(_run.map.stop(id).type) == wanted:
				pick = id
	if pick < 0 and not map.choices().is_empty():
		pick = map.choices()[0]
	if pick < 0:
		_autoplay_fail("map_no_choice")
		return
	_autoplay_act(map, map.choose.bind(pick))


## True if the party is fit for an elite fight (RunAutoplay's habit).
func _autoplay_elite_ready() -> bool:
	return RunAutoplay.is_ready(_autoplay_health())


## Autoplay at a campfire: rests when someone is hurt, else keeps watch before the boss or trains.
func _autoplay_rest(rest: RestScreen) -> void:
	await get_tree().create_timer(AUTOPLAY_RETURN_S).timeout
	if not _autoplay_turn_ok(rest):
		return
	if _autoplay_hurt():
		rest.rest_now()
	elif _run.is_watch_fire():
		rest.watch_now()
	else:
		rest.train_now()
		_autoplay_spend_points()
	await get_tree().create_timer(AUTOPLAY_RETURN_S).timeout
	if is_instance_valid(rest):
		_autoplay_act(rest, rest.leave)


## Autoplay in a shop: first lifts every curse it can pay for (Cleanse, card #332), then buys what it
## can afford; a bought Relic goes to the hero it helps most.
func _autoplay_shop(shop: ShopScreen) -> void:
	await get_tree().create_timer(AUTOPLAY_RETURN_S).timeout
	if not _autoplay_turn_ok(shop):
		return
	# At most one Cleanse per curse it came in with: online a friend's request waits for the host's
	# answer, so its copy may still show a curse it already asked to lift.
	var to_lift := _run.curses.size()
	var lifted := 0
	while _bot_cleanses(_run, lifted, to_lift):
		var curse := _run.curses[0]
		if not shop.cleanse(0):
			break
		lifted += 1
		print("Run cleanse: %s" % curse)
		if Net.is_client():
			# A friend's bot (card #314): the host's answer redraws the shop; the next curse waits for it.
			await get_tree().create_timer(AUTOPLAY_RETURN_S).timeout
			if not _autoplay_turn_ok(shop):
				return
	var shop_turn := "%s/%d" % [String(_turn.get("key", "")), _run.restocks]
	for i: int in shop.count():
		if not _autoplay_turn_ok(shop):
			return
		if not _bot_buys(shop, i):
			continue
		if Net.is_client() and not _bot_first_buy(_bot_shelves, shop_turn, i):
			continue
		var hero := -1
		if shop.is_relic(i):
			hero = RelicGift.bot_hero(_run, shop.relic_at(i), shop.relic_heroes())
		if not shop.buy(i, hero):
			continue
		if shop.is_relic(i):
			print("Run relic: %s to %s (shop)" % [shop.relic_at(i).id, _run.data.party[hero].id])
		if Net.is_client():
			# A friend's bot (card #314): the host's answer redraws the shop, whose bot goes on; a find
			# handed to us settles first.
			await get_tree().create_timer(AUTOPLAY_RETURN_S).timeout
			await _autoplay_settle_over(shop)
		elif shop.overlay() != null:
			_autoplay_settle(shop.overlay())
			if shop.overlay() != null:
				shop.overlay().close()
	if not _autoplay_turn_ok(shop):
		return
	print("Run shop: gold left %d, items %d" % [_run.gold, _run.backpack.entries.size()])
	await get_tree().create_timer(AUTOPLAY_RETURN_S).timeout
	if is_instance_valid(shop):
		_autoplay_act(shop, shop.leave)


## True if the bot lifts another curse in a shop (card #332): the party has one and the gold for the
## Cleanse, and it has lifted (or asked to lift) fewer than the `to_lift` curses it came in with.
## Pure.
static func _bot_cleanses(run: RunState, lifted: int, to_lift: int) -> bool:
	return run != null and lifted < to_lift and not run.curses.is_empty() and run.gold >= run.cleanse_price()


## True if the bot buys shelf `i` of `shop`: one it can buy, never a Relic GearBot refuses (a
## rot-touched one with a costly price: a given Relic never comes off). Pure.
static func _bot_buys(shop: ShopScreen, i: int) -> bool:
	if not shop.can_buy(i):
		return false
	return not shop.is_relic(i) or GearBot.score(shop.relic_at(i)) >= 0


## Online friend's bot: true the first time it buys shelf `shelf` on shop turn `key` (the turn's key
## and the restock count), noted in `tried` ({"key", "shelves"}; a new key starts it over). A
## purchase with no room that the bot leaves behind goes back on the shelf with its gold, and the
## host's answer redraws the shop, whose bot starts again: without this it would buy that shelf for
## ever. So it tries each shelf once, as the host's bot does. Pure apart from `tried`.
static func _bot_first_buy(tried: Dictionary, key: String, shelf: int) -> bool:
	if String(tried.get("key", "")) != key or not tried.get("shelves") is Array:
		tried.clear()
		tried["key"] = key
		tried["shelves"] = []
	var shelves := tried["shelves"] as Array
	if shelves.has(shelf):
		return false
	shelves.append(shelf)
	return true


## True if a hero is at or under AUTOPLAY_REST_BELOW_PERCENT of their max HP, or the party as a
## whole is under AUTOPLAY_REST_AVERAGE_PERCENT.
func _autoplay_hurt() -> bool:
	for slot: int in _run.party_size():
		if _run.hp[slot] * 100 <= _run.max_hp(slot) * AUTOPLAY_REST_BELOW_PERCENT:
			return true
	return _autoplay_health().y < AUTOPLAY_REST_AVERAGE_PERCENT


## The party's state: x the weakest hero's HP percent of max, y the party's average HP percent, z the
## lowest hero level (RunAutoplay reads it).
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
	if not _autoplay_turn_ok(screen):
		return
	if screen.choice_count() > 0 and not _run.stop_done and not screen.is_decided():
		var event := screen.event()
		var decision := EventAutoplay.decide(_run, event, _autoplay_health())
		print("AUTOPLAY_EVENT %s -> %s" % [event.id, "choice %d" % int(decision.index) if int(decision.index) >= 0 else "leave"])
		if Net.is_client():
			# A friend's bot (card #314) chooses, or walks on (also when nothing came of its choice), as
			# a player would; the host leaves only a decided event, and its result screen (with that
			# screen's bot) comes next.
			if int(decision.index) >= 0:
				await _autoplay_act(screen, screen.choose.bind(int(decision.index), int(decision.pick),
						_autoplay_event_hero(screen, int(decision.index))))
			if _autoplay_turn_ok(screen) and _run != null and not _run.stop_done:
				_autoplay_act(screen, screen.walk_on)
			return
		if int(decision.index) >= 0:
			screen.choose(int(decision.index), int(decision.pick), _autoplay_event_hero(screen, int(decision.index)))
	await _autoplay_stop_gifts(screen)
	if is_instance_valid(screen):
		_autoplay_act(screen, screen.leave)


## The bot's hero for event choice `index`'s Relic (its rarity is rolled when taken): the hero with
## the fewest Relics it may give to; -1 when the choice gives none.
func _autoplay_event_hero(screen: EventScreen, index: int) -> int:
	if not screen.gives_relic(index):
		return -1
	var best := -1
	for slot: int in screen.relic_heroes():
		if best < 0 or _run.relics_of(slot).size() < _run.relics_of(best).size():
			best = slot
	return best


## Autoplay at a treasure stop: opens the chest, picks the rotten chest's Relic (GearBot) for the
## hero it helps most, settles the prize, goes on.
func _autoplay_treasure(screen: TreasureScreen) -> void:
	await get_tree().create_timer(AUTOPLAY_RETURN_S).timeout
	if not _autoplay_turn_ok(screen):
		return
	# The rotten chest only while healthy (a curse or a fight may come with it).
	if not screen.is_open():
		screen.open_chest(not _autoplay_hurt())
	if screen.relic_waiting():
		await get_tree().create_timer(AUTOPLAY_RETURN_S).timeout
		if not _autoplay_turn_ok(screen):
			return
		var offered := screen.relic_choices()
		var index := GearBot.pick(offered)
		var item := offered[index]
		var hero := RelicGift.bot_hero(_run, item, RelicGift.allowed(_give_heroes, _run))
		print("Run relic: %s to %s (chest)" % [item.id, _run.data.party[hero].id])
		await _autoplay_act(screen, screen.take_relic.bind(index, hero))
		if Net.is_client():
			return
	await _autoplay_stop_gifts(screen)
	if is_instance_valid(screen):
		_autoplay_act(screen, screen.leave)


## Settles every backpack a stop screen opens for its gifts. Untyped: a friend's screen may be freed
## under the bot.
func _autoplay_stop_gifts(screen: Variant) -> void:
	while is_instance_valid(screen) and screen.is_settling():
		await get_tree().create_timer(AUTOPLAY_RETURN_S).timeout
		if is_instance_valid(screen) and screen.overlay() != null:
			_autoplay_settle(screen.overlay())
			if is_instance_valid(screen) and screen.overlay() != null:
				screen.overlay().close()
	await get_tree().create_timer(AUTOPLAY_RETURN_S).timeout


## Autoplay on the spoils: takes the rarest Relic, a rot-touched one when its price is bearable
## (GearBot, DESIGN.md 8.16), for the hero it helps most (8.24).
func _autoplay_loot(loot: LootScreen) -> void:
	await get_tree().create_timer(AUTOPLAY_RETURN_S).timeout
	if _autoplay_turn_ok(loot):
		var index := GearBot.pick(loot.choices())
		var hero := -1
		if index < loot.choices().size():
			var item := loot.choices()[index]
			hero = RelicGift.bot_hero(_run, item, RelicGift.allowed(_give_heroes, _run))
			print("Run loot: took %s for %s" % [item.id, _run.data.party[hero].id])
		_autoplay_act(loot, loot.take.bind(index, hero))


## Autoplay: every Relic still waiting goes to a hero (RunState.auto_give, DESIGN.md 8.24), and every
## hero spends their new attribute points evenly (8.2) and learns the skills it can (8.4).
func _autoplay_spend_points() -> void:
	if not _options.is_autoplay() or Net.is_client() or _run == null:
		return
	_run.auto_give()
	for slot: int in _run.party_size():
		if _run.has_tree(slot) and _run.free_skill_points(slot) > 0:
			_run.auto_skills(slot)
			print("Run skills: %s %s" % [_run.data.party[slot].id, str(_run.loadout[slot])])
		if _run.free_points(slot) > 0:
			_run.auto_spend(slot)
			print("Run points: %s level %d attributes %s" % [_run.data.party[slot].id, _run.levels[slot],
					str(_run.attributes[slot])])


## Autoplay on the party screen: a find in hand is placed, and Relics still waiting are given.
func _autoplay_party(party: PartyScreen) -> void:
	await get_tree().create_timer(AUTOPLAY_RETURN_S).timeout
	if not is_instance_valid(party) or _run == null:
		return
	_autoplay_settle(party)
	if is_instance_valid(party) and party.is_inside_tree():
		party.close()


func _autoplay_settle(party: PartyScreen) -> void:
	var held := _held_count(_run)
	var items := _run.backpack.entries.size()
	party.auto_settle()
	# A Relic waiting for a hero (only an old save has one) goes nowhere by itself: the bot gives it.
	# A friend's copy of the run never changes by itself (the host's does that).
	if not Net.is_client():
		_run.auto_give()
	print("Run settle: held %d -> %d, items %d -> %d, gold %d" % [held, _held_count(_run), items,
			_run.backpack.entries.size(), _run.gold])


## Autoplay on the map: uses healing items on whoever is hurt (like a player tidying up).
func _autoplay_use_items() -> void:
	if Net.is_client():
		# A friend's copy of the run never changes by itself (the host's bot tidies up).
		return
	for e: Dictionary in _run.backpack.entries.duplicate():
		var item := e.item as ItemData
		if not item.usable_on_map():
			continue
		var low := 0
		for slot: int in _run.party_size():
			if _run.hp[slot] * _run.max_hp(low) < _run.hp[low] * _run.max_hp(slot):
				low = slot
		if _run.hp[low] * 100 <= _run.max_hp(low) * AUTOPLAY_REST_BELOW_PERCENT and _run.use_item(int(e.uid), low):
			print("Run use: %s on %s" % [item.id, _run.data.party[low].id])


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


## The Relics given to heroes (autoplay result line, DESIGN.md 8.24).
static func _held_count(run: RunState) -> int:
	var held := 0
	for given: Array in run.gear:
		held += given.size()
	return held
