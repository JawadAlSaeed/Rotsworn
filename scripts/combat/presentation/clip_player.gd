class_name ClipPlayer
extends RefCounted
## Which sheet cell a fighter shows (DESIGN.md 5.5), as pure state without nodes: a base layer and
## one timed override on top. It holds resolved cell lists (never clip names), and every query
## takes the time in ms on the caller's clock (FighterView passes real time), so it is testable
## without a scene.
##
## Base: a static cell (set_base_cell; a caller that drives a clip from attack or skill time sets
## one every frame) or a loop indexed from absolute time (set_base_loop). Because a loop is indexed
## from the clock, setting the same loop every frame never restarts it. A loop may start later
## (start_ms); until then the previous base shows.
## Override: play() shows its cells over the base for a length, spread evenly (or cycling every
## cycle_ms), optionally after a delay or held on its last cell. There is one override at a time:
## a strictly higher priority one refuses the new one, an equal or lower one is replaced.

const PRIO_NONE: int = 0
## Hurt, legacy play_pose, weapon draw, counter strike, zone strike, follow-up leap.
const PRIO_REACT: int = 1
## Stagger, fall, get-up, escape run-off, pickup, boss rage.
const PRIO_BIG: int = 2
## Death and victory.
const PRIO_FINAL: int = 3


## One base layer: a static cell (one cell, or no period) or a loop.
class Layer:
	extends RefCounted

	var cells: PackedInt32Array = PackedInt32Array([0])
	var period_ms: float = 0.0
	var phase_ms: float = 0.0
	var start_ms: float = 0.0

	func set_cell(cell: int) -> void:
		if cells.size() != 1 or cells[0] != cell:
			cells = PackedInt32Array([cell])
		period_ms = 0.0
		phase_ms = 0.0
		start_ms = 0.0

	func set_loop(loop_cells: PackedInt32Array, period: float, phase: float, start: float) -> void:
		cells = loop_cells
		period_ms = period
		phase_ms = phase
		start_ms = start

	func cell_at(now_ms: float) -> int:
		if cells.size() <= 1 or period_ms <= 0.0:
			return cells[0]
		return cells[ClipMath.loop(cells.size(), now_ms - start_ms, period_ms, phase_ms)]


var _base := Layer.new()
## Shown instead of _base until _base.start_ms (a loop that starts later); null when none.
var _before: Layer = null

var _cells := PackedInt32Array()
var _prio: int = PRIO_NONE
var _start_ms: float = 0.0
var _length_ms: float = 0.0
var _hold: bool = false
var _cycle_ms: float = 0.0


## The base becomes this one cell (replacing any loop, a pending one included).
func set_base_cell(cell: int) -> void:
	_before = null
	_base.set_cell(cell)


## The base loops `cells`, one cycle every `period_ms`, shifted by `phase_ms`, indexed from the
## clock (start_ms 0) or from `start_ms` (a loop that begins later: its first cell shows at
## start_ms, the previous base until then). Call a delayed loop once, not every frame.
func set_base_loop(cells: PackedInt32Array, period_ms: float, phase_ms: float, start_ms: float = 0.0) -> void:
	if cells.is_empty():
		return
	if start_ms > 0.0:
		_before = _base
		_base = Layer.new()
	else:
		_before = null
	_base.set_loop(cells, period_ms, phase_ms, start_ms)


## Shows `cells` over the base for `length_ms` from `now_ms + delay_ms`: spread evenly over the
## length, or cycling every `cycle_ms` when it is above 0. `hold` keeps the last cell (or the
## cycle) after the length until cleared. Refused (false) while a strictly higher priority
## override is pending or playing; an equal or lower one is replaced.
func play(cells: PackedInt32Array, now_ms: float, length_ms: float, prio: int, delay_ms: float = 0.0,
		hold: bool = false, cycle_ms: float = 0.0) -> bool:
	if cells.is_empty():
		return false
	if _live(now_ms) and _prio > prio:
		return false
	_cells = cells
	_prio = maxi(prio, PRIO_REACT)
	_start_ms = now_ms + maxf(delay_ms, 0.0)
	_length_ms = maxf(length_ms, 0.0)
	_hold = hold
	_cycle_ms = cycle_ms
	return true


## Drops the override (pending or playing) if its priority is below `prio`.
func cancel_below(prio: int) -> void:
	if _prio != PRIO_NONE and _prio < prio:
		_drop_override()


## Drops the override; the base stays.
func clear() -> void:
	_drop_override()


## True while an override of at least `min_prio` is pending or playing.
func busy(now_ms: float, min_prio: int = PRIO_REACT) -> bool:
	return _live(now_ms) and _prio >= min_prio


## The cell to show at `now_ms`: the override while it plays, otherwise the base.
func cell_at(now_ms: float) -> int:
	if _live(now_ms) and now_ms >= _start_ms:
		var elapsed := now_ms - _start_ms
		if _cycle_ms > 0.0:
			return _cells[ClipMath.loop(_cells.size(), elapsed, _cycle_ms)]
		return _cells[ClipMath.once(_cells.size(), elapsed, _length_ms)]
	if _before != null and now_ms < _base.start_ms:
		return _before.cell_at(now_ms)
	return _base.cell_at(now_ms)


## An override exists and has not run out (pending ones count).
func _live(now_ms: float) -> bool:
	return _prio != PRIO_NONE and (_hold or now_ms < _start_ms + _length_ms)


func _drop_override() -> void:
	_prio = PRIO_NONE
	_cells = PackedInt32Array()
	_hold = false
