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
##   --zone=ID                       start in this zone (data/zones) instead of the list
##   --first-strike                  start --encounter with a FIRST STRIKE (DESIGN.md 2.12)
##   --run                           start a new run at once (DESIGN.md 8)
##   --save-path=PATH                (dev tool) keep the run save at PATH (a user:// path); the bot
##                                   never touches the player's real save, so it saves only with this
##   --journal-path=PATH             (dev tool) keep the Rot Journal at PATH (a user:// path); with it
##                                   every fight counts (bots and practice too), without it only a
##                                   person's run fights are written, to the real journal
##   --continue                      continue the run save at once (with --save-path for the bot)
##   --players=N                     co-op with N players (1 to 3), one pretend pad each, heroes
##                                   split evenly (DESIGN.md 9.1; for the autoplay bot)
##   --host=N                        host online; start a run once N players (2 or 3) are in
##   --join=ADDRESS                  join the online game at ADDRESS (DESIGN.md 9.2)
##   --leave-after=S                 (with --join) leave the game after S seconds and quit
##   --shots=S                       save a picture of the window every S seconds (dev tool)
##   --screen=NAME                   open a screen at once: menu, settings, players, practice,
##                                   title, credits, journal, party, heroes, attributes, skills, calibration,
##                                   tutorial, map, map_start, map_act2, shop, campfire,
##                                   event, treasure
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

## "" when a human plays, else AUTOPLAY_PERFECT, AUTOPLAY_MISS or AUTOPLAY_MASH.
var autoplay_mode: String = ""
var quit_on_end: bool = false
## -1 when no --seed was given.
var seed_override: int = -1
## "" when no --encounter was given.
var encounter_id: String = ""
## "" when no --zone was given.
var zone_id: String = ""
var first_strike: bool = false
var run: bool = false
## --continue: pick up the saved run at once.
var continue_run: bool = false
## --save-path=PATH ("" : the real save, and no saving for the bot).
var save_path: String = ""
## --journal-path=PATH ("" : the real journal, and no recording for bots or practice fights).
var journal_path: String = ""
## --oath=N: the oath a bot run (--run) or an autoplay host plays at (-1: none given, the lobby's pick).
var oath: int = -1
## Players from --players (1 = solo).
var players: int = 1
## --host=N (0: not hosting) and --join=ADDRESS ("" : not joining).
var host_players: int = 0
var join_address: String = ""
## --leave-after=S (0: stay).
var leave_after_s: int = 0
## --bot-skill=N for --autoplay=average (0 to 100).
var bot_skill: int = DEFAULT_BOT_SKILL
## --shots=S (0: no pictures) and --screen=NAME ("" : the normal start).
var shots_every_s: float = 0.0
var screen: String = ""
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
		elif arg.begins_with("--zone="):
			options.zone_id = arg.substr("--zone=".length())
		elif arg == "--first-strike":
			options.first_strike = true
		elif arg == "--run":
			options.run = true
		elif arg == "--continue":
			options.continue_run = true
		elif arg.begins_with("--save-path="):
			options.save_path = arg.substr("--save-path=".length())
		elif arg.begins_with("--journal-path="):
			options.journal_path = arg.substr("--journal-path=".length())
		elif arg.begins_with("--oath="):
			var level := arg.substr("--oath=".length())
			if level.is_valid_int() and level.to_int() >= 0:
				options.oath = level.to_int()
			else:
				push_warning("CombatOptions: --oath needs a whole number from 0, got '%s'" % level)
		elif arg.begins_with("--host="):
			var wanted := arg.substr("--host=".length())
			options.host_players = clampi(wanted.to_int(), 1, PlayerRoster.MAX_PLAYERS) if wanted.is_valid_int() else 2
		elif arg.begins_with("--leave-after="):
			options.leave_after_s = maxi(0, arg.substr("--leave-after=".length()).to_int())
		elif arg.begins_with("--bot-skill="):
			options.bot_skill = clampi(arg.substr("--bot-skill=".length()).to_int(), 0, 100)
		elif arg.begins_with("--shots="):
			options.shots_every_s = maxf(0.0, arg.substr("--shots=".length()).to_float())
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
