class_name CombatOptions
extends RefCounted
## How the combat scene was launched (command line) plus the session state that survives a
## restart (R): the F1 overlay toggles and the defence statistics.
##
## User args (after "--" on the Godot command line):
##   --autoplay[=perfect|miss|mash|escape|average]  bot plays the fight (perfect is the default;
##                                   escape presses perfectly and runs on its first turn; average
##                                   lands --bot-skill percent of its presses)
##   --bot-skill=N                   (with --autoplay=average) percent of presses it lands (60)
##   --quit-on-end                   quit one second after the fight ends
##   --seed=N                        fixed fight seed (else tuning fixed_seed, else random)
##   --encounter=ID                  start this encounter (data/encounters) instead of the list
##   --weather=ID                    every run fight but the boss's and every Rush fight has this
##                                   weather (data/weather: rain, storm, fog, wind, dusk) or none
##                                   ("clear"), for tests and pictures
##   --first-strike                  start --encounter with a FIRST STRIKE (DESIGN.md 2.12; a run's
##                                   Fight stops open with the First Strike ring instead, 8.22)
##   --run                           start a new run at once (DESIGN.md 8)
##   --rush                          start a Fight Rush at once (DESIGN.md 8.21); with --host=N host
##                                   one online (card #312)
##   --rush-start=N                 (dev tool) the Rush starts at fight N, the fights before it
##                                   replayed as perfect wins (at least 1; implies --rush)
##   --rush-fights=N                 (dev tool) the Rush ends after N fights (0: no cap; implies --rush)
##   --save-path=PATH                (dev tool) keep the run save at PATH (a user:// path); the bot
##                                   never touches the player's real save, so it saves only with this
##   --journal-path=PATH             (dev tool) keep the Rot Journal at PATH (a user:// path); with it
##                                   every fight counts (bots and practice too), without it only a
##                                   person's run fights are written, to the real journal
##   --continue                      continue the run save at once (with --save-path for the bot)
##   --players=N                     co-op with N players (1 to 3), one pretend pad each, heroes
##                                   split evenly (DESIGN.md 9.1; for the autoplay bot)
##   --pad-join-after=S              (with --autoplay) a pretend pad joins the local run S seconds
##                                   after launch, at the next quiet moment (DESIGN.md 9.3)
##   --pad-leave-after=S             (with --autoplay) the last local player leaves after S seconds
##   --roster-in-fight               those two wait for the next fight and come a few seconds into it
##   --host=N                        host online; start a run (a Fight Rush with --rush) once N
##                                   players (1 to 3) are in; 1 starts at once, friends drop in later
##                                   (DESIGN.md 9.3)
##   --seat-in-fight                 (online host) seat a friend who drops in only a few seconds
##                                   into the next fight
##   --join=ADDRESS                  join the online game at ADDRESS (DESIGN.md 9.2)
##   --join-after=S                  (with --join) connect S seconds after launch, into a run going
##   --leave-after=S                 (with --join) leave the game after S seconds and quit
##   --crash-after=S                 (with --join) quit S seconds after launch without a goodbye,
##                                   like a crash
##   --shots=S                       save a picture of the window every S seconds (dev tool)
##   --perf-log=S                    print frames a second and draw calls every S seconds (dev tool)
##   --screen=NAME                   open a screen at once: menu, settings, players, practice,
##                                   title, controller, calibration_offer, credits, glossary (glossary_<topic> opens that
##                                   topic: glossary_reading), journal, party, heroes, attributes, skills, calibration,
##                                   tutorial, map, map_start, map_act2, map_act3, first_strike (a Fight
##                                   stop's name card with its First Strike ring, starting over),
##                                   shop, campfire,
##                                   event, treasure, controls_vibration (the Controller page on
##                                   its Vibration row), players_in_run (the Players overlay
##                                   over the pause menu, two players), pause_players (the pause menu
##                                   with its Players row)
##   --menu-keys=ACTION,ACTION,...   (dev tool, for pictures of the fight menu) the first time the
##                                   action menu opens, press these input actions on it (for
##                                   example fight_skills,menu_down), then leave it waiting; "|"
##                                   moves on to the next turn's menu
##   --attacks=ID,ID,...             (practice fights) the enemy uses these attacks in this order,
##                                   round and round (dev tool, for pictures of one move)

const AUTOPLAY_PERFECT := "perfect"
const AUTOPLAY_MISS := "miss"
const AUTOPLAY_MASH := "mash"
## Presses perfectly and tries to Run on its first turn (checks the escape ending, DESIGN.md 2.13).
const AUTOPLAY_ESCAPE := "escape"
## Plays like an average player for balance checks (DESIGN.md 10): lands bot_skill percent of
## its defences and skill presses (some perfect, some good) and lets the rest go.
const AUTOPLAY_AVERAGE := "average"
const DEFAULT_BOT_SKILL: int = 60
## --rejoin without a number: join again this many seconds after losing the host (longer than the
## heartbeat, so the host has marked the seat away and plays on meanwhile).
const DEFAULT_REJOIN_S: int = 10

## "" when a human plays, else AUTOPLAY_PERFECT, AUTOPLAY_MISS or AUTOPLAY_MASH.
var autoplay_mode: String = ""
var quit_on_end: bool = false
## -1 when no --seed was given.
var seed_override: int = -1
## "" when no --encounter was given.
var encounter_id: String = ""
## --weather=ID: every run fight but the boss's and every Rush fight has this
## weather ("clear": none); "" : the seed picks (card #303, DESIGN.md 8.22).
var weather_id: String = ""
var first_strike: bool = false
var run: bool = false
## --rush: start a Fight Rush at once; --rush-start=N: its first fight (above 1 replays the ones
## before, RushState.head_start); --rush-fights=N: it stops after N fights (0: never). The last two
## imply --rush and keep the Rush out of the records (DESIGN.md 8.21).
var rush: bool = false
var rush_start: int = 1
var rush_fights: int = 0
## --continue: pick up the saved run at once.
var continue_run: bool = false
## --save-path=PATH ("" : the real save, and no saving for the bot).
var save_path: String = ""
## Online saves (card #313): --online-save-path=PATH keeps the host's online slot there ("" : the real
## one, and no online saving for the bot); --continue-online makes an autoplay host continue that
## saved run once its players are in (--host=N); --save-quit-at=N makes the bot Save & Quit on
## arriving at stop N (0: never); --seat-path=PATH is a friend's seat file ("" : the real one for a
## person, none for the bot).
var online_save_path: String = ""
var continue_online: bool = false
var save_quit_at: int = 0
var seat_path: String = ""
## --journal-path=PATH ("" : the real journal, and no recording for bots or practice fights).
var journal_path: String = ""
## --relics-path=PATH ("" : the real Relic collection, which bots never read or write).
var relics_path: String = ""
## --relics=none|all: the pretend collection a bot run starts with (DESIGN.md 8.17; "" : none for
## bots, the real one for a person). "all" has every Relic at its top level, for balance runs.
var relics_mode: String = ""
## --oath=N: the oath a bot run (--run) or an autoplay host plays at (-1: none given, the lobby's pick).
var oath: int = -1
## Players from --players (1 = solo).
var players: int = 1
## --host=N (0: not hosting) and --join=ADDRESS ("" : not joining).
var host_players: int = 0
var join_address: String = ""
## --join-after=S (with --join): wait S seconds after launch before connecting (a friend dropping in
## mid-run, card #304; 0: at once).
var join_after_s: int = 0
## --leave-after=S (0: stay).
var leave_after_s: int = 0
## --end-after=S (0: never): an online host ends the game for everyone S seconds after starting,
## as End the game in the pause menu does.
var end_after_s: int = 0
## --drop-after=S (0: never): an online client drops off the network without a word after S
## seconds, like a pulled cable (card #205). --rejoin[=S]: after losing the host it joins again
## S seconds later (0: it does not). --drop-in-fight: the drop waits for the next fight after
## those S seconds and comes a few seconds into it (to test rejoining mid-fight).
var drop_after_s: int = 0
var rejoin_after_s: int = 0
var drop_in_fight: bool = false
## --pad-join-after=S (0: never): a pretend pad joins the local run S seconds after launch, at the next
## quiet moment, through the same roster change as the Players overlay (card #304).
var pad_join_after_s: int = 0
## --pad-leave-after=S (0: never): the last local player leaves S seconds after launch (card #311).
var pad_leave_after_s: int = 0
## --roster-in-fight: those local changes wait for the next fight and come a few seconds into it.
var roster_in_fight: bool = false
## --seat-in-fight (online host): a friend who drops in is seated only once a fight has been on for a
## few seconds (tests seating mid-fight; they wait on "Joining the game ..." meanwhile).
var seat_in_fight: bool = false
## --crash-after=S (online client): the game quits S seconds after launch without a goodbye, like a
## crash (its seat goes away on the host; a new client can take it after net_takeover_after_ms, card #304).
var crash_after_s: int = 0
## --bot-skill=N for --autoplay=average (0 to 100).
var bot_skill: int = DEFAULT_BOT_SKILL
## --shots=S (0: no pictures) and --screen=NAME ("" : the normal start).
var shots_every_s: float = 0.0
var screen: String = ""
## --perf-log=S (0: none): print frames a second and draw calls every S seconds (card #237).
var perf_every_s: float = 0.0
## --menu-keys=ACTION,... (dev tool; empty: none).
var menu_keys: PackedStringArray = PackedStringArray()
## --attacks=ID,ID,... (empty: the enemy picks as always).
var forced_attacks: PackedStringArray = PackedStringArray()
## Session toggles (F1 overlay; not saved): telegraph flash (G), timing readout (T), the
## enemy's motion sounds (L: lunge whoosh and slam), hit markers (H), the wind-up crouch (C) and
## the cinematic camera (V).
var telegraph_flash: bool = true
var timing_readout: bool = true
var motion_sounds: bool = true
var hit_markers: bool = true
var windup_crouch: bool = true
## Cinematic combat camera (V).
var cinematic_camera: bool = true
## Defence statistics for the F1 overlay, kept across restarts.
var stats := DefenseStats.new()


static func from_args(args: PackedStringArray, tuning: Tuning) -> CombatOptions:
	var options := CombatOptions.new()
	if tuning != null:
		options.telegraph_flash = tuning.show_telegraph_flash
		options.timing_readout = tuning.show_timing_feedback
		options.motion_sounds = tuning.play_motion_sounds
		options.hit_markers = tuning.show_hit_markers
		options.windup_crouch = tuning.show_windup_crouch
		options.cinematic_camera = tuning.cinematic_camera
	for arg: String in args:
		if arg == "--autoplay":
			options.autoplay_mode = AUTOPLAY_PERFECT
		elif arg.begins_with("--autoplay="):
			var mode := arg.substr("--autoplay=".length()).to_lower()
			if mode in [AUTOPLAY_PERFECT, AUTOPLAY_MISS, AUTOPLAY_MASH, AUTOPLAY_ESCAPE, AUTOPLAY_AVERAGE]:
				options.autoplay_mode = mode
			else:
				push_warning("CombatOptions: unknown autoplay mode '%s', using perfect" % mode)
				options.autoplay_mode = AUTOPLAY_PERFECT
		elif arg == "--quit-on-end":
			options.quit_on_end = true
		elif arg.begins_with("--encounter="):
			options.encounter_id = arg.substr("--encounter=".length())
		elif arg.begins_with("--weather="):
			options.weather_id = arg.substr("--weather=".length())
		elif arg == "--first-strike":
			options.first_strike = true
		elif arg == "--run":
			options.run = true
		elif arg == "--rush":
			options.rush = true
		elif arg.begins_with("--rush-start="):
			options.rush = true
			options.rush_start = maxi(1, arg.substr("--rush-start=".length()).to_int())
		elif arg.begins_with("--rush-fights="):
			options.rush = true
			options.rush_fights = maxi(0, arg.substr("--rush-fights=".length()).to_int())
		elif arg == "--continue":
			options.continue_run = true
		elif arg.begins_with("--save-path="):
			options.save_path = arg.substr("--save-path=".length())
		elif arg.begins_with("--online-save-path="):
			options.online_save_path = arg.substr("--online-save-path=".length())
		elif arg == "--continue-online":
			options.continue_online = true
		elif arg.begins_with("--save-quit-at="):
			options.save_quit_at = maxi(0, arg.substr("--save-quit-at=".length()).to_int())
		elif arg.begins_with("--seat-path="):
			options.seat_path = arg.substr("--seat-path=".length())
		elif arg.begins_with("--journal-path="):
			options.journal_path = arg.substr("--journal-path=".length())
		elif arg.begins_with("--relics-path="):
			options.relics_path = arg.substr("--relics-path=".length())
		elif arg.begins_with("--relics="):
			var mode := arg.substr("--relics=".length()).to_lower()
			if mode in ["none", "all"]:
				options.relics_mode = mode
			else:
				push_warning("CombatOptions: --relics needs none or all, got '%s'" % mode)
		elif arg.begins_with("--oath="):
			var level := arg.substr("--oath=".length())
			if level.is_valid_int() and level.to_int() >= 0:
				options.oath = level.to_int()
			else:
				push_warning("CombatOptions: --oath needs a whole number from 0, got '%s'" % level)
		elif arg.begins_with("--host="):
			var wanted := arg.substr("--host=".length())
			options.host_players = clampi(wanted.to_int(), 1, PlayerRoster.MAX_PLAYERS) if wanted.is_valid_int() else 2
		elif arg.begins_with("--join-after="):
			options.join_after_s = maxi(0, arg.substr("--join-after=".length()).to_int())
		elif arg.begins_with("--leave-after="):
			options.leave_after_s = maxi(0, arg.substr("--leave-after=".length()).to_int())
		elif arg.begins_with("--end-after="):
			options.end_after_s = maxi(0, arg.substr("--end-after=".length()).to_int())
		elif arg.begins_with("--drop-after="):
			options.drop_after_s = maxi(0, arg.substr("--drop-after=".length()).to_int())
		elif arg == "--drop-in-fight":
			options.drop_in_fight = true
		elif arg.begins_with("--pad-join-after="):
			options.pad_join_after_s = maxi(0, arg.substr("--pad-join-after=".length()).to_int())
		elif arg.begins_with("--pad-leave-after="):
			options.pad_leave_after_s = maxi(0, arg.substr("--pad-leave-after=".length()).to_int())
		elif arg == "--roster-in-fight":
			options.roster_in_fight = true
		elif arg == "--seat-in-fight":
			options.seat_in_fight = true
		elif arg.begins_with("--crash-after="):
			options.crash_after_s = maxi(0, arg.substr("--crash-after=".length()).to_int())
		elif arg == "--rejoin":
			options.rejoin_after_s = DEFAULT_REJOIN_S
		elif arg.begins_with("--rejoin="):
			options.rejoin_after_s = maxi(1, arg.substr("--rejoin=".length()).to_int())
		elif arg.begins_with("--bot-skill="):
			options.bot_skill = clampi(arg.substr("--bot-skill=".length()).to_int(), 0, 100)
		elif arg.begins_with("--shots="):
			options.shots_every_s = maxf(0.0, arg.substr("--shots=".length()).to_float())
		elif arg.begins_with("--perf-log="):
			options.perf_every_s = maxf(0.0, arg.substr("--perf-log=".length()).to_float())
		elif arg.begins_with("--screen="):
			options.screen = arg.substr("--screen=".length())
		elif arg.begins_with("--menu-keys="):
			options.menu_keys = arg.substr("--menu-keys=".length()).replace("|", ",|,").split(",", false)
		elif arg.begins_with("--attacks="):
			options.forced_attacks = arg.substr("--attacks=".length()).split(",", false)
		elif arg.begins_with("--join="):
			options.join_address = arg.substr("--join=".length())
		elif arg.begins_with("--players="):
			var count := arg.substr("--players=".length())
			if count.is_valid_int() and count.to_int() >= 1 and count.to_int() <= PlayerRoster.MAX_PLAYERS:
				options.players = count.to_int()
			else:
				push_warning("CombatOptions: --players needs 1 to %d, got '%s'" % [PlayerRoster.MAX_PLAYERS, count])
		elif arg.begins_with("--seed="):
			var text := arg.substr("--seed=".length())
			if text.is_valid_int():
				options.seed_override = absi(text.to_int())
			else:
				push_warning("CombatOptions: --seed needs a whole number, got '%s'" % text)
	return options


func is_autoplay() -> bool:
	return not autoplay_mode.is_empty()
