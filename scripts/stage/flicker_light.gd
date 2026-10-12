class_name FlickerLight
extends OmniLight3D
## A point light that can flicker like a flame (ZoneLightData). Presentation only, real time.

## Two out-of-step waves make the flicker look uneven.
const SECOND_WAVE_RATIO: float = 2.37
const SECOND_WAVE_SHARE: float = 0.4

var _base_energy: float = 1.0
var _flicker: float = 0.0
var _hz: float = 6.0
var _phase: float = 0.0


func setup(energy: float, flicker_percent: int, hz: float) -> void:
	_base_energy = energy
	_flicker = float(clampi(flicker_percent, 0, 100)) / 100.0
	_hz = hz
	_phase = randf() * TAU
	light_energy = energy
	set_process(_flicker > 0.0)


func _process(_delta: float) -> void:
	var t := float(Time.get_ticks_msec()) / 1000.0 * TAU * _hz + _phase
	var wave := (sin(t) + sin(t * SECOND_WAVE_RATIO) * SECOND_WAVE_SHARE) / (1.0 + SECOND_WAVE_SHARE)
	light_energy = _base_energy * (1.0 - _flicker * (0.5 + 0.5 * wave))
