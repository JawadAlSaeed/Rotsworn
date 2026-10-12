class_name PlayerSettings
extends Node
## Per-machine player settings, saved in user://settings.cfg. Registered as the autoload
## "UserSettings"; the functions are static (class PlayerSettings) so code can call them as
## PlayerSettings.x() without the autoload's global name (which `--check-only` does not know)
## and they also work when no autoload exists (unit tests). UserSettings.x() works too.
## Holds what belongs to this machine and player rather than to the game's balance: the measured
## lag compensation (F2 calibration or the settings screen), the training ring toggle (F1 then R),
## the volume and fullscreen (settings screen), the last host address joined online. Anything not
## saved here falls back to the value in data/tuning/tuning.tres (or the defaults below).

const PATH := "user://settings.cfg"
const SECTION_TIMING := "timing"
const SECTION_CUES := "cues"
const KEY_LATENCY := "latency_compensation_ms"
const KEY_RING := "show_timing_ring"
const SECTION_AUDIO := "audio"
const KEY_VOLUME := "volume_percent"
const SECTION_DISPLAY := "display"
const KEY_FULLSCREEN := "fullscreen"
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


## Master volume in percent (0 = silent).
static func volume_percent() -> int:
	return clampi(int(_settings().get_value(SECTION_AUDIO, KEY_VOLUME, DEFAULT_VOLUME_PERCENT)), 0, 100)


static func set_volume_percent(value: int) -> void:
	_settings().set_value(SECTION_AUDIO, KEY_VOLUME, clampi(value, 0, 100))
	_save()
	apply_volume()


static func apply_volume() -> void:
	var pct := volume_percent()
	AudioServer.set_bus_mute(0, pct == 0)
	AudioServer.set_bus_volume_db(0, linear_to_db(float(maxi(pct, 1)) / 100.0))


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
	elif not fullscreen() and mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)


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
		if err != OK and err != ERR_FILE_NOT_FOUND:
			push_warning("UserSettings: could not read %s (error %d); using defaults" % [PATH, err])
	return _config


static func _save() -> void:
	var err := _settings().save(PATH)
	if err != OK:
		push_warning("UserSettings: could not save %s (error %d)" % [PATH, err])
