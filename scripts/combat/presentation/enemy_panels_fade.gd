class_name EnemyPanelsFade
extends RefCounted
## How see-through the enemy panels (top right, their HP bars) are (DESIGN.md 7.1, card #268):
## they step back while an enemy attack plays so they do not cover its hits, and a parry or a
## counter brings them back to full at once, so what it does shows on the bar straight away.
## Pure: the HUD passes the CombatVisuals numbers and the elapsed seconds in. Each machine fades
## its own HUD from its own playback; nothing here goes over the network.

var _attack_alpha: float = 0.3
var _fade_ms: int = 200
var _hold_ms: int = 600
var _alpha: float = 1.0
var _attacking: bool = false
## Seconds left of a parry's hold at full.
var _hold_left_s: float = 0.0
## A parried last hit: full until the attack is over (the counter comes next).
var _held_to_end: bool = false


func configure(attack_alpha: float, fade_ms: int, parry_hold_ms: int) -> void:
	_attack_alpha = clampf(attack_alpha, 0.0, 1.0)
	_fade_ms = maxi(0, fade_ms)
	_hold_ms = maxi(0, parry_hold_ms)


## An enemy attack starts (true) or is over (false). A new attack drops any hold left from the
## last one.
func set_attacking(on: bool) -> void:
	if on and not _attacking:
		_hold_left_s = 0.0
		_held_to_end = false
	_attacking = on


## A parry or a counter: full at once, held for the parry hold (to the end of the attack when
## `to_end`).
func show_now(to_end: bool = false) -> void:
	_alpha = 1.0
	_hold_left_s = float(_hold_ms) / 1000.0
	if to_end:
		_held_to_end = true


## The see-through the panels are heading for.
func target() -> float:
	if not _attacking or _held_to_end or _hold_left_s > 0.0:
		return 1.0
	return _attack_alpha


## Runs `delta` seconds of real time (the hold, then the fade toward target()); returns the
## see-through to show.
func step(delta: float) -> float:
	var seconds := maxf(0.0, delta)
	_hold_left_s = maxf(0.0, _hold_left_s - seconds)
	var wanted := target()
	if _fade_ms == 0:
		_alpha = wanted
	else:
		_alpha = move_toward(_alpha, wanted, seconds * 1000.0 / float(_fade_ms))
	return _alpha


func alpha() -> float:
	return _alpha
