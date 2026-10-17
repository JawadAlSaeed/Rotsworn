class_name CameraTrauma
extends RefCounted
## The camera shake model (DESIGN.md 7.3, card #179): "trauma" from 0 to 1 that every impact adds
## to (clamped), that drains at a fixed rate per second, and whose shown amplitude is trauma
## SQUARED times a maximum, so a graze barely moves the view, a string of parries builds up, and a
## big moment is clearly bigger. The motion is a sum of sines of real time at a fixed frequency,
## never a fresh random number per frame, so it looks the same at 30 or 480 fps (keep the base
## frequency times the top layer under half of the lowest frame rate). Pure: the caller
## passes the elapsed seconds and the clock in.

## Sine speeds (cycles per base frequency) of the three layers on each axis; incommensurate, so
## the motion never visibly repeats.
const LAYERS: Array[float] = [1.0, 2.2, 3.7]
## How much each layer counts (they add up to 1).
const WEIGHTS: Array[float] = [0.5, 0.33, 0.17]
## A different phase for each axis (x, y, roll), in radians.
const AXIS_PHASE: Array[float] = [0.0, 2.1, 4.3]

var _trauma: float = 0.0
var _hz: float = 6.0
var _decay_per_s: float = 1.5
var _max_offset: float = 0.3
var _max_roll_deg: float = 1.5


func configure(hz: float, decay_per_s: float, max_offset: float, max_roll_deg: float) -> void:
	_hz = maxf(0.1, hz)
	_decay_per_s = maxf(0.0, decay_per_s)
	_max_offset = maxf(0.0, max_offset)
	_max_roll_deg = maxf(0.0, max_roll_deg)


## Adds trauma (a hit adds on top of what is left), never above 1.
func add(amount: float) -> void:
	_trauma = clampf(_trauma + maxf(0.0, amount), 0.0, 1.0)


## Drains trauma by `delta` seconds of real time.
func step(delta: float) -> void:
	_trauma = maxf(0.0, _trauma - _decay_per_s * maxf(0.0, delta))


func trauma() -> float:
	return _trauma


## The shown strength, 0 to 1: trauma squared.
func amount() -> float:
	return _trauma * _trauma


## The camera offset (x, y; z is always 0) at `time_s` seconds, scaled by `scale` (the player's
## shake setting, 0 to 1).
func offset(time_s: float, scale: float = 1.0) -> Vector3:
	var a := amount() * _max_offset * scale
	if a <= 0.0:
		return Vector3.ZERO
	return Vector3(a * _wave(time_s, 0), a * _wave(time_s, 1), 0.0)


## The roll in radians at `time_s` seconds, scaled the same way.
func roll(time_s: float, scale: float = 1.0) -> float:
	var a := amount() * deg_to_rad(_max_roll_deg) * scale
	if a <= 0.0:
		return 0.0
	return a * _wave(time_s, 2)


## A smooth value from -1 to 1 for one axis: three sines at fixed multiples of the base frequency.
func _wave(time_s: float, axis: int) -> float:
	var sum := 0.0
	for i: int in LAYERS.size():
		sum += WEIGHTS[i] * sin(TAU * _hz * LAYERS[i] * time_s + AXIS_PHASE[axis] * (i + 1))
	return sum
