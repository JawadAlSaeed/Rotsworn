class_name PlayerSettings
extends Node
## Per-machine player settings, saved in user://settings.cfg. Registered as the autoload
## "UserSettings"; the functions are static (class PlayerSettings) so code can call them as
## PlayerSettings.x() without the autoload's global name (which `--check-only` does not know)
## and they also work when no autoload exists (unit tests). UserSettings.x() works too.
## Holds what belongs to this machine and player rather than to the game's balance: the measured
## lag compensation, one per kind of input (keyboard, pad; F2 calibration or the settings screen, card #204), the training ring toggle (F1 then R),
## the volumes (overall, music, effects, voices), the display and graphics options, screen shake and
## flashes (settings screen, cards #112 and #185), the text size (card #203), the highest oath
## unlocked (DESIGN.md 8.15), the Fight Rush records (8.21), the last host address joined online, the rebound keys and buttons
## (card #190, ControlBindings). Anything not saved here falls back to the value in data/tuning/tuning.tres (or the defaults below).

const PATH := "user://settings.cfg"
## The game was called "Rotten Lands" before (card #48), and Godot keeps user:// in a folder named
## after the game: a settings file left there is read once, so calibration and volumes survive.
const OLD_NAME_DIR := "Rotten Lands"
const SECTION_TIMING := "timing"
const SECTION_CUES := "cues"
## The lag compensation saved before the two input kinds existed (card #204): still read, for both
## kinds, until the player calibrates that kind itself.
const KEY_LATENCY := "latency_compensation_ms"
## Lag compensation per kind of input (card #204): a keyboard and a wireless pad lag differently.
const INPUT_KEYBOARD := "keyboard"
const INPUT_PAD := "pad"
const INPUT_KINDS: Array[String] = [INPUT_KEYBOARD, INPUT_PAD]
const KEY_LATENCY_KEYBOARD := "latency_keyboard_ms"
const KEY_LATENCY_PAD := "latency_pad_ms"
const KEY_RING := "show_timing_ring"
const SECTION_AUDIO := "audio"
const KEY_VOLUME := "volume_percent"
## Volume channels (card #104): settings key and audio bus. "master" is the overall volume; the
## Audio autoload creates the other buses and plays songs, effects and voices on them.
const CHANNELS := {
	"master": {"key": KEY_VOLUME, "bus": "Master"},
	"music": {"key": "music_percent", "bus": "Music"},
	"effects": {"key": "effects_percent", "bus": "Effects"},
	"voice": {"key": "voice_percent", "bus": "Voice"},
}
const SECTION_DISPLAY := "display"
const KEY_FULLSCREEN := "fullscreen"
const KEY_WINDOW_SIZE := "window_size"
const KEY_VSYNC := "vsync"
const KEY_FPS_LIMIT := "fps_limit"
## Window sizes when not fullscreen (index 0: the maximised window, as before card #112).
const WINDOW_SIZES: Array[Vector2i] = [Vector2i.ZERO, Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080),
		Vector2i(2560, 1440)]
## Frame rate limits (0: the project's own limit).
const FPS_LIMITS: Array[int] = [0, 30, 60, 120, 144, 240]
## Graphics options (card #112): each turns one part of a place's look on or off. A look that
## does not use it stays without it either way.
const SECTION_GRAPHICS := "graphics"
const GRAPHICS := {
	"fog": "Fog",
	"bloom": "Bloom",
	"shadows": "Shadows",
	"ambient_occlusion": "Soft shadows",
	"depth_of_field": "Depth of field",
}
const SECTION_GAME := "game"
const KEY_SHAKE := "screen_shake_percent"
const KEY_FLASH := "flash_mode"
const KEY_TEXT_SIZE := "text_size"
## The Text size setting (card #203): names of the steps. The percents live in
## data/presentation/ui_fonts.tres (UiFonts.text_size_percents), one per name.
const TEXT_SIZE_NAMES: Array[String] = ["Normal", "Large", "Larger"]
## The Flashes setting (card #185): how strong screen flashes and white hit flashes are. The
## numbers for Reduced and Off live in data/presentation/combat_visuals.tres.
const FLASH_FULL: int = 0
const FLASH_REDUCED: int = 1
const FLASH_OFF: int = 2
const FLASH_NAMES: Array[String] = ["Full", "Reduced", "Off"]
## The highest oath this machine has unlocked (DESIGN.md 8.15); 0 until a run is won.
const KEY_OATH_UNLOCKED := "oath_unlocked"
const KEY_TUTORIAL_OFFERED := "tutorial_offered"
const KEY_CALIBRATION_OFFERED := "calibration_offered"
const SHAKE_STEP_PERCENT: int = 25
## Controller vibration (card #299): how strong the buzz is, in steps of RUMBLE_STEP_PERCENT; 0 is off.
const KEY_RUMBLE := "rumble_percent"
const RUMBLE_STEP_PERCENT: int = 25
## The Fight Rush records (DESIGN.md 8.21): one key per party size, "best_1" to "best_3".
const SECTION_RUSH := "rush"
const KEY_RUSH_BEST := "best_%d"
const SECTION_ONLINE := "online"
const KEY_JOIN_ADDRESS := "join_address"
## Online run choices pass from player to player (card #314, DESIGN.md 9.2): on by default; off, the
## host makes every choice (the old way). Only the host's own setting counts.
const KEY_TAKE_TURNS := "take_turns"
const DEFAULT_JOIN_ADDRESS := "127.0.0.1"
## Rebound keys and buttons (card #190): one entry per changed action, see ControlBindings.
const SECTION_CONTROLS := "controls"
const DEFAULT_VOLUME_PERCENT: int = 100
const VOLUME_STEP_PERCENT: int = 10

static var _config: ConfigFile
## False in unit tests: settings change in memory only and user://settings.cfg is never written.
static var _persist: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_settings()
	apply_volume()
	apply_fullscreen()
	apply_frame_options()
	# Before any screen reads the Input Map: the rebound keys and buttons (card #190), and before any
	# text is built: the text size (card #203).
	# A test run (godot -s) keeps the project's own keys and text size, whatever this machine has saved.
	if not OS.get_cmdline_args().has("-s") and not OS.get_cmdline_args().has("--script"):
		ControlBindings.install(control_overrides())
		apply_text_size()


## Which kind of input a device code is (PlayerRoster: a pad's Godot id is 0 and up; KEYBOARD, ANY
## and the autoplay bot's injected presses count as the keyboard).
static func input_kind_of_device(device: int) -> String:
	return INPUT_PAD if device >= 0 else INPUT_KEYBOARD


## Lag compensation in ms for one kind of input (keyboard by default): the calibrated value if
## there is one (kept within tuning's calibration_min_ms .. calibration_max_ms, even if the file was
## edited), else the value saved before the kinds existed, else the tuning default.
static func latency_compensation_ms(tuning: Tuning, kind: String = INPUT_KEYBOARD) -> int:
	var key := _latency_key(kind)
	var cfg := _settings()
	if cfg.has_section_key(SECTION_TIMING, key):
		return clamp_latency(int(cfg.get_value(SECTION_TIMING, key, 0)), tuning)
	if cfg.has_section_key(SECTION_TIMING, KEY_LATENCY):
		return clamp_latency(int(cfg.get_value(SECTION_TIMING, KEY_LATENCY, 0)), tuning)
	return tuning.input_latency_compensation_ms if tuning != null else 0


## The smallest lag compensation over both kinds of input. The sequence judges work from this base
## and each press adds its own device's extra (DESIGN.md 3.2), so an attack never closes a window
## before a laggier device can still press into it.
static func base_latency_compensation_ms(tuning: Tuning) -> int:
	return mini(latency_compensation_ms(tuning, INPUT_KEYBOARD), latency_compensation_ms(tuning, INPUT_PAD))


## Saves a calibrated lag compensation for one kind of input (overrides the tuning default from now
## on), clamped.
static func set_latency_compensation_ms(value: int, tuning: Tuning, kind: String = INPUT_KEYBOARD) -> void:
	_settings().set_value(SECTION_TIMING, _latency_key(kind), clamp_latency(value, tuning))
	_save()


## `value` limited to the calibration bounds in tuning.
static func clamp_latency(value: int, tuning: Tuning) -> int:
	if tuning == null:
		return value
	return clampi(value, tuning.calibration_min_ms, tuning.calibration_max_ms)


## True once the player has saved a calibration on this machine: for this kind of input, or for
## either of them when `kind` is empty.
static func is_calibrated(kind: String = "") -> bool:
	var cfg := _settings()
	if cfg.has_section_key(SECTION_TIMING, KEY_LATENCY):
		return true
	if not kind.is_empty():
		return cfg.has_section_key(SECTION_TIMING, _latency_key(kind))
	return cfg.has_section_key(SECTION_TIMING, KEY_LATENCY_KEYBOARD) \
			or cfg.has_section_key(SECTION_TIMING, KEY_LATENCY_PAD)


static func _latency_key(kind: String) -> String:
	return KEY_LATENCY_PAD if kind == INPUT_PAD else KEY_LATENCY_KEYBOARD


## Whether the training ring is shown: the saved choice, else the tuning default.
static func show_timing_ring(tuning: Tuning) -> bool:
	if _settings().has_section_key(SECTION_CUES, KEY_RING):
		return bool(_settings().get_value(SECTION_CUES, KEY_RING, false))
	return tuning.show_timing_ring if tuning != null else false


static func set_show_timing_ring(value: bool) -> void:
	_settings().set_value(SECTION_CUES, KEY_RING, value)
	_save()


## Forgets every calibrated lag compensation: the tuning default is used again.
static func reset_latency_compensation() -> void:
	if is_calibrated():
		for key: String in [KEY_LATENCY, KEY_LATENCY_KEYBOARD, KEY_LATENCY_PAD]:
			if _settings().has_section_key(SECTION_TIMING, key):
				_settings().erase_section_key(SECTION_TIMING, key)
		_save()


## Overall volume in percent (0 = silent).
static func volume_percent() -> int:
	return channel_percent("master")


static func set_volume_percent(value: int) -> void:
	set_channel_percent("master", value)


## One channel's volume in percent ("master", "music", "effects", "voice"; 0 = silent).
static func channel_percent(channel: String) -> int:
	if not CHANNELS.has(channel):
		return DEFAULT_VOLUME_PERCENT
	var key := String(CHANNELS[channel].key)
	return clampi(int(_settings().get_value(SECTION_AUDIO, key, DEFAULT_VOLUME_PERCENT)), 0, 100)


static func set_channel_percent(channel: String, value: int) -> void:
	if not CHANNELS.has(channel):
		return
	_settings().set_value(SECTION_AUDIO, String(CHANNELS[channel].key), clampi(value, 0, 100))
	_save()
	apply_volume()


## Volume in dB for a percent (linear loudness scale); 0 % is muted instead.
static func percent_to_db(percent: int) -> float:
	return linear_to_db(float(clampi(percent, 1, 100)) / 100.0)


## Sets every channel's bus (a bus that does not exist yet is skipped; Audio applies again).
static func apply_volume() -> void:
	for channel: String in CHANNELS:
		var bus := AudioServer.get_bus_index(String(CHANNELS[channel].bus))
		if bus < 0:
			continue
		var pct := channel_percent(channel)
		AudioServer.set_bus_mute(bus, pct == 0)
		AudioServer.set_bus_volume_db(bus, percent_to_db(pct))


static func fullscreen() -> bool:
	return bool(_settings().get_value(SECTION_DISPLAY, KEY_FULLSCREEN, false))


static func set_fullscreen(value: bool) -> void:
	_settings().set_value(SECTION_DISPLAY, KEY_FULLSCREEN, value)
	_save()
	apply_fullscreen()


## Fullscreen, or the normal maximised window. Nothing to do without a window (headless).
static func apply_fullscreen() -> void:
	if DisplayServer.get_name() == "headless":
		return
	# A quiet picture run (card #168) keeps the window where the launcher put it: fullscreen or
	# maximised would activate it and steal the keyboard from whatever the owner is playing.
	if QuietWindow.active():
		return
	var mode := DisplayServer.window_get_mode()
	if fullscreen() and mode != DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not fullscreen():
		var wanted := window_size()
		if wanted == Vector2i.ZERO:
			if mode != DisplayServer.WINDOW_MODE_MAXIMIZED:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
			return
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(wanted)
		var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
		DisplayServer.window_set_position(screen.position + (screen.size - wanted) / 2)


## The window size when not fullscreen (Vector2i.ZERO: maximised).
static func window_size() -> Vector2i:
	return WINDOW_SIZES[window_size_index()]


static func window_size_index() -> int:
	return clampi(int(_settings().get_value(SECTION_DISPLAY, KEY_WINDOW_SIZE, 0)), 0, WINDOW_SIZES.size() - 1)


static func set_window_size_index(value: int) -> void:
	_settings().set_value(SECTION_DISPLAY, KEY_WINDOW_SIZE, posmod(value, WINDOW_SIZES.size()))
	_save()
	apply_fullscreen()


static func vsync() -> bool:
	return bool(_settings().get_value(SECTION_DISPLAY, KEY_VSYNC, true))


static func set_vsync(value: bool) -> void:
	_settings().set_value(SECTION_DISPLAY, KEY_VSYNC, value)
	_save()
	apply_frame_options()


## The frame rate limit (0: the project's own).
static func fps_limit() -> int:
	return FPS_LIMITS[fps_limit_index()]


static func fps_limit_index() -> int:
	return clampi(int(_settings().get_value(SECTION_DISPLAY, KEY_FPS_LIMIT, 0)), 0, FPS_LIMITS.size() - 1)


static func set_fps_limit_index(value: int) -> void:
	_settings().set_value(SECTION_DISPLAY, KEY_FPS_LIMIT, posmod(value, FPS_LIMITS.size()))
	_save()
	apply_frame_options()


## VSync (on: the project's own mode) and the frame rate limit.
static func apply_frame_options() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var project_vsync := int(ProjectSettings.get_setting("display/window/vsync/vsync_mode", DisplayServer.VSYNC_ENABLED))
	DisplayServer.window_set_vsync_mode(project_vsync if vsync() else DisplayServer.VSYNC_DISABLED)
	var limit := fps_limit()
	Engine.max_fps = limit if limit > 0 else int(ProjectSettings.get_setting("application/run/max_fps", 0))


## One graphics option (a GRAPHICS key); every option is on unless turned off.
static func graphics(key: String) -> bool:
	return bool(_settings().get_value(SECTION_GRAPHICS, key, true))


static func set_graphics(key: String, value: bool) -> void:
	if not GRAPHICS.has(key):
		return
	_settings().set_value(SECTION_GRAPHICS, key, value)
	_save()


## The highest oath (difficulty step, DESIGN.md 8.15) unlocked on this machine. 0: only the plain run.
static func highest_oath_unlocked() -> int:
	return maxi(0, int(_settings().get_value(SECTION_GAME, KEY_OATH_UNLOCKED, 0)))


## What the highest unlocked oath becomes after winning a run at `won_oath` on a ladder of
## `ladder_size` oaths: one more than the oath won, never lower than `unlocked`, never past the
## ladder. Pure, so it is tested without a settings file.
static func oath_after_win(unlocked: int, won_oath: int, ladder_size: int) -> int:
	return clampi(maxi(unlocked, won_oath + 1), 0, maxi(0, ladder_size))


## Records a won run at `won_oath` (online players too). Returns the highest oath unlocked now.
static func unlock_after_win(won_oath: int, ladder_size: int) -> int:
	var now := oath_after_win(highest_oath_unlocked(), won_oath, ladder_size)
	if now != highest_oath_unlocked():
		_settings().set_value(SECTION_GAME, KEY_OATH_UNLOCKED, now)
		_save()
	return now


## Settings > Reset progress (DESIGN.md 8.17): back to no oath unlocked.
static func reset_oath_unlocks() -> void:
	_settings().set_value(SECTION_GAME, KEY_OATH_UNLOCKED, 0)
	_save()


## The Fight Rush record of a party of `players` (RushRecords.entry; {} when there is none or it is
## damaged), DESIGN.md 8.21.
static func rush_best(players: int) -> Dictionary:
	var e: Variant = _settings().get_value(SECTION_RUSH, _rush_key(players), {})
	return (e as Dictionary).duplicate() if RushRecords.is_valid(e) else {}


## Keeps `e` as the record of a party of `players` if it beats the one kept (RushRecords.better).
## True if it was written.
static func set_rush_best(players: int, e: Dictionary) -> bool:
	if not RushRecords.better(e, rush_best(players)):
		return false
	_settings().set_value(SECTION_RUSH, _rush_key(players), RushRecords.entry(int(e.fight), String(e.date)))
	_save()
	return true


## The best fight of every party size's record (0: none), for the main menu's Fight Rush card.
static func rush_best_any() -> int:
	var entries: Array = []
	for players: int in RushRecords.SIZES:
		entries.append(rush_best(players))
	return RushRecords.best_of(entries)


## Settings > Reset progress: every Fight Rush record goes.
static func reset_rush_records() -> void:
	if _settings().has_section(SECTION_RUSH):
		_settings().erase_section(SECTION_RUSH)
	_save()


static func _rush_key(players: int) -> String:
	return KEY_RUSH_BEST % RushRecords.bucket(players)


## True once the tutorial was offered on the first New Run (DESIGN.md 7.8): it is asked once.
static func tutorial_offered() -> bool:
	return bool(_settings().get_value(SECTION_GAME, KEY_TUTORIAL_OFFERED, false))


static func set_tutorial_offered(value: bool) -> void:
	_settings().set_value(SECTION_GAME, KEY_TUTORIAL_OFFERED, value)
	_save()


## True once the lag calibration was offered on a New Run (DESIGN.md 3.2, card #204): asked once.
static func calibration_offered() -> bool:
	return bool(_settings().get_value(SECTION_GAME, KEY_CALIBRATION_OFFERED, false))


static func set_calibration_offered(value: bool) -> void:
	_settings().set_value(SECTION_GAME, KEY_CALIBRATION_OFFERED, value)
	_save()


## Whether a New Run should offer the lag calibration now: only once, and never to a player who
## already calibrated (an older save, or Settings). Pure, so it is tested without any file.
static func calibration_offer_due(offered: bool, calibrated: bool) -> bool:
	return not offered and not calibrated


## How strong camera shakes are, in percent (0: no shaking).
static func screen_shake_percent() -> int:
	return clampi(int(_settings().get_value(SECTION_GAME, KEY_SHAKE, 100)), 0, 100)


static func set_screen_shake_percent(value: int) -> void:
	_settings().set_value(SECTION_GAME, KEY_SHAKE, clampi(value, 0, 100))
	_save()


## How strong the controller buzzes, in percent (0: no buzz).
static func rumble_percent() -> int:
	return clampi(int(_settings().get_value(SECTION_GAME, KEY_RUMBLE, 100)), 0, 100)


static func set_rumble_percent(value: int) -> void:
	_settings().set_value(SECTION_GAME, KEY_RUMBLE, clampi(value, 0, 100))
	_save()


## Flashes: FLASH_FULL (default), FLASH_REDUCED or FLASH_OFF. Bad values read as Full.
static func flash_mode() -> int:
	var mode := int(_settings().get_value(SECTION_GAME, KEY_FLASH, FLASH_FULL))
	return mode if mode >= FLASH_FULL and mode <= FLASH_OFF else FLASH_FULL


## Sets the flash mode; the number wraps around (so Right on Off goes to Full).
static func set_flash_mode(value: int) -> void:
	_settings().set_value(SECTION_GAME, KEY_FLASH, posmod(value, FLASH_NAMES.size()))
	_save()


## The text size step: 0 Normal (default), 1 Large, 2 Larger. A bad saved value reads as Normal.
static func text_size_index() -> int:
	var index := int(_settings().get_value(SECTION_GAME, KEY_TEXT_SIZE, 0))
	return index if index >= 0 and index < TEXT_SIZE_NAMES.size() else 0


## Sets the text size; the number wraps around (Right on Larger goes to Normal). Text built from
## now on uses it (HudStyle.scaled).
static func set_text_size_index(value: int) -> void:
	_settings().set_value(SECTION_GAME, KEY_TEXT_SIZE, posmod(value, TEXT_SIZE_NAMES.size()))
	_save()
	apply_text_size()


## Gives the saved text size to HudStyle (start-up, and whenever it changes).
static func apply_text_size() -> void:
	HudStyle.set_text_size_index(text_size_index())


## The host address typed last on the Join Online screen.
static func join_address() -> String:
	return String(_settings().get_value(SECTION_ONLINE, KEY_JOIN_ADDRESS, DEFAULT_JOIN_ADDRESS))


static func set_join_address(value: String) -> void:
	_settings().set_value(SECTION_ONLINE, KEY_JOIN_ADDRESS, value.strip_edges())
	_save()


## Online, as host: friends take turns making the run's choices (card #314). On unless turned off.
static func take_turns() -> bool:
	return bool(_settings().get_value(SECTION_ONLINE, KEY_TAKE_TURNS, true))


static func set_take_turns(value: bool) -> void:
	_settings().set_value(SECTION_ONLINE, KEY_TAKE_TURNS, value)
	_save()


## The rebound keys and buttons: {action: {"key": [...], "pad": [...]}}, only the changed actions
## (see ControlBindings.overrides).
static func control_overrides() -> Dictionary:
	var out := {}
	var cfg := _settings()
	if cfg.has_section(SECTION_CONTROLS):
		for action: String in cfg.get_section_keys(SECTION_CONTROLS):
			out[action] = cfg.get_value(SECTION_CONTROLS, action, {})
	return out


## Saves the rebound keys and buttons (the whole list: actions left out go back to the default).
static func set_control_overrides(overrides: Dictionary) -> void:
	var cfg := _settings()
	if cfg.has_section(SECTION_CONTROLS):
		cfg.erase_section(SECTION_CONTROLS)
	for action: String in overrides:
		cfg.set_value(SECTION_CONTROLS, action, overrides[action])
	_save()


## Unit tests: stop writing user://settings.cfg (settings then only live in memory).
static func set_persistence(on: bool) -> void:
	_persist = on


static func _settings() -> ConfigFile:
	if _config == null:
		_config = ConfigFile.new()
		var err := _config.load(PATH)
		if err == ERR_FILE_NOT_FOUND:
			var old := OS.get_user_data_dir().get_base_dir().path_join(OLD_NAME_DIR).path_join("settings.cfg")
			if FileAccess.file_exists(old) and _config.load(old) == OK:
				_save()
				return _config
		if err != OK and err != ERR_FILE_NOT_FOUND:
			push_warning("UserSettings: could not read %s (error %d); using defaults" % [PATH, err])
	return _config


static func _save() -> void:
	if not _persist:
		return
	var err := _settings().save(PATH)
	if err != OK:
		push_warning("UserSettings: could not save %s (error %d)" % [PATH, err])
