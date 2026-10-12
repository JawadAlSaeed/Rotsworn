class_name HitRhythm
extends RefCounted
## How an enemy attack's hits are shown so the player can read them (DESIGN.md 3.8): where each
## hit icon sits in a rhythm row (spaced by time, so a string's beat and its pauses show) and the
## state of each hit at an attack time. Pure functions of the hits and attack time, so hit-stop
## freezes them exactly like the enemy motion.

enum State {
	## Its motion has not started yet.
	UPCOMING,
	## Its motion (a feint's false start included) has started and it has not landed yet.
	ACTIVE,
	## Its impact has passed.
	DONE,
}

## Squeezing a row that is too wide: halvings of the time scale tried (precision is plenty).
const FIT_STEPS: int = 24


## Centre x of each icon, in pixels from the row's left edge, for impact times `times_ms`.
## Centres are `px_per_ms` apart per millisecond between impacts and never closer than
## icon_px + min_gap_px. A row wider than max_width_px is squeezed (only the time spacing, never
## below the minimum) until it fits or every step is at the minimum.
static func layout(times_ms: Array, icon_px: float, px_per_ms: float, min_gap_px: float,
		max_width_px: float) -> PackedFloat32Array:
	var scale := maxf(0.0, px_per_ms)
	if _width_at(times_ms, icon_px, scale, min_gap_px) > max_width_px:
		var lo := 0.0
		var hi := scale
		for _step: int in FIT_STEPS:
			var mid := (lo + hi) * 0.5
			if _width_at(times_ms, icon_px, mid, min_gap_px) > max_width_px:
				hi = mid
			else:
				lo = mid
		scale = lo
	return _centres(times_ms, icon_px, scale, min_gap_px)


## Width of a row laid out by layout(): from the first icon's left edge to the last one's right.
static func row_width(centres: PackedFloat32Array, icon_px: float) -> float:
	if centres.is_empty():
		return 0.0
	return centres[centres.size() - 1] + icon_px * 0.5


## The State of each hit at attack time `t_ms`. `hits` are the declared hit dictionaries (at_ms,
## kind, approach_ms, feint). A hit is ACTIVE from its motion start (EnemyChoreography: a feint's
## false start, a lunge or a slam) until its impact, so at most one hit is active at a time and a
## feint lights its hit as early as the false start (it still fools you).
static func states(hits: Array, t_ms: float, v: CombatVisuals) -> Array[int]:
	var list: Array[int] = []
	for i: int in hits.size():
		var impact := float((hits[i] as Dictionary).at_ms)
		if t_ms >= impact:
			list.append(State.DONE)
		elif t_ms >= EnemyChoreography.motion_start(hits, i, v):
			list.append(State.ACTIVE)
		else:
			list.append(State.UPCOMING)
	return list


## Index of the ACTIVE hit in `states`, or -1.
static func active_hit(hit_states: Array[int]) -> int:
	return hit_states.find(State.ACTIVE)


static func _centres(times_ms: Array, icon_px: float, scale: float, min_gap_px: float) -> PackedFloat32Array:
	var centres := PackedFloat32Array()
	var x := icon_px * 0.5
	for i: int in times_ms.size():
		if i > 0:
			var gap := float(int(times_ms[i]) - int(times_ms[i - 1])) * scale
			x += maxf(icon_px + min_gap_px, gap)
		centres.append(x)
	return centres


static func _width_at(times_ms: Array, icon_px: float, scale: float, min_gap_px: float) -> float:
	return row_width(_centres(times_ms, icon_px, scale, min_gap_px), icon_px)
