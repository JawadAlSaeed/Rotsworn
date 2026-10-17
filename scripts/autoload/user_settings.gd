class_name PlayerSettings
extends Node
## Per-machine player settings, saved in user://settings.cfg. Registered as the autoload
## "UserSettings"; the functions are static (class PlayerSettings) so code can call them as
## PlayerSettings.x() without the autoload's global name (which `--check-only` does not know)
## and they also work when no autoload exists (unit tests). UserSettings.x() works too.
## Holds what belongs to this machine and player rather than to the game's balance: the measured
## lag compensation (F2 calibration or the settings screen), the training ring toggle (F1 then R),
## the volumes (overall, music, effects, voices), the display and graphics options, screen shake
## (settings screen, card #112), the highest oath unlocked (DESIGN.md 8.13), the last host address joined online. Anything not
## saved here falls back to the value in data/tuning/tuning.tres (or the defaults below).

const PATH := "user://settings.cfg"
## The game was called "Rotten Lands" before (card #48), and Godot keeps user:// in a folder named
## after the game: a settings file left there is read once, so calibration and volumes survive.
const OLD_NAME_DIR := "Rotten Lands"
const SECTION_TIMING := "timing"
const SECTION_CUES := "cues"
const KEY_LATENCY := "latency_compensation_ms"
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
## The highest oath this machine has unlocked (DESIGN.md 8.13); 0 until a run is won.
const KEY_OATH_UNLOCKED := "oath_unlocked"
const KEY_TUTORIAL_OFFERED := "tutorial_offered"
const SHAKE_STEP_PERCENT: int = 25
const SECTION_ONLINE := "online"
const KEY_JOIN_ADDRESS := "join_address"
const DEFAULT_JOIN_ADDRESS := "127.0.0.1"
const DEFAULT_VOLUME_PERCENT: int = 100
const VOLUME_STEP_PERCENT: int = 10

static var _config: ConfigFile


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_settings()
	apply_volume()
	apply_fullscreen()
	apply_frame_options()


## Lag compensation in ms: the calibrated value if there is one (kept within tuning's
## calibration_min_ms .. calibration_max_ms, even if the file was edited), else the tuning default.
static func latency_compensation_ms(tuning: Tuning) -> int:
	if is_calibrated():
		return clamp_latency(int(_settings().get_value(SECTION_TIMING, KEY_LATENCY, 0)), tuning)
	return tuning.input_latency_compensation_ms if tuning != null else 0


## Saves a calibrated lag compensation (overrides the tuning default from now on), clamped.
static func set_latency_compensation_ms(value: int, tuning: Tuning) -> void:
	_settings().set_value(SECTION_TIMING, KEY_LATENCY, clamp_latency(value, tuning))
	_save()


## `value` limited to the calibration bounds in tuning.
static func clamp_latency(value: int, tuning: Tuning) -> int:
	if tuning == null:
		return value
	return clampi(value, tuning.calibration_min_ms, tuning.calibration_max_ms)


## True once the player has saved a calibration on this machine.
static func is_calibrated() -> bool:
	return _settings().has_section_key(SECTION_TIMING, KEY_LATENCY)


## Whether the training ring is shown: the saved choice, else the tuning default.
static func show_timing_ring(tuning: Tuning) -> bool:
	if _settings().has_section_key(SECTION_CUES, KEY_RING):
		return bool(_settings().get_value(SECTION_CUES, KEY_RING, false))
	return tuning.show_timing_ring if tuning != null else false


static func set_show_timing_ring(value: bool) -> void:
	_settings().set_value(SECTION_CUES, KEY_RING, value)
	_save()


## Forgets the calibrated lag compensation: the tuning default is used again.
static func reset_latency_compensation() -> void:
	if is_calibrated():
		_settings().erase_section_key(SECTION_TIMING, KEY_LATENCY)
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


## The highest oath (difficulty step, DESIGN.md 8.13) unlocked on this machine. 0: only the plain run.
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


## True once the tutorial was offered on the first New Run (DESIGN.md 7.8): it is asked once.
static func tutorial_offered() -> bool:
	return bool(_settings().get_value(SECTION_GAME, KEY_TUTORIAL_OFFERED, false))


static func set_tutorial_offered(value: bool) -> void:
	_settings().set_value(SECTION_GAME, KEY_TUTORIAL_OFFERED, value)
	_save()


## How strong camera shakes are, in percent (0: no shaking).
static func screen_shake_percent() -> int:
	return clampi(int(_settings().get_value(SECTION_GAME, KEY_SHAKE, 100)), 0, 100)


static func set_screen_shake_percent(value: int) -> void:
	_settings().set_value(SECTION_GAME, KEY_SHAKE, clampi(value, 0, 100))
	_save()


## The host address typed last on the Join Online screen.
static func join_address() -> String:
	return String(_settings().get_value(SECTION_ONLINE, KEY_JOIN_ADDRESS, DEFAULT_JOIN_ADDRESS))


static func set_join_address(value: String) -> void:
	_settings().set_value(SECTION_ONLINE, KEY_JOIN_ADDRESS, value.strip_edges())
	_save()


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
	var err := _settings().save(PATH)
	if err != OK:
		push_warning("UserSettings: could not save %s (error %d)" % [PATH, err])
