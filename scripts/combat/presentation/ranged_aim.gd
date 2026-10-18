class_name RangedAim
extends RefCounted
## The pure timing of the ranged-hit indicator (DESIGN.md 3.9, card #165): a bracket on the hero a
## thrown projectile flies at that tightens onto them and closes exactly at the hit's declared
## impact (the same time the defence is judged on), plus a dashed path from the projectile to the
## hero. Everything is a function of attack time in milliseconds, so hit-stop freezes it.


## 0 at the launch, 1 at impact (clamped): how far the projectile has flown, and how far the bracket
## has closed.
static func progress(t_ms: float, launch_ms: float, impact_ms: float) -> float:
	var flight := impact_ms - launch_ms
	if flight <= 0.0:
		return 1.0 if t_ms >= impact_ms else 0.0
	return clampf((t_ms - launch_ms) / flight, 0.0, 1.0)


## When the indicator first shows: `lead_ms` before the launch (the wind-up), never before 0.
static func show_from_ms(launch_ms: float, lead_ms: float) -> float:
	return maxf(0.0, launch_ms - maxf(0.0, lead_ms))


## The indicator at attack time `t_ms`: {shown: bool, alpha: 0..1, progress: 0..1, locked: bool}.
## It fades in over `fade_ms` from show_from_ms(), stays until `end_ms` (the hit was decided, or
## its window closed) and fades out over `fade_ms`. `locked` is true from the impact on: the
## bracket is closed and the hit is being decided.
static func state(t_ms: float, launch_ms: float, impact_ms: float, end_ms: float, lead_ms: float,
		fade_ms: float) -> Dictionary:
	var from := show_from_ms(launch_ms, lead_ms)
	var fade := maxf(1.0, fade_ms)
	var alpha := 0.0
	if t_ms >= from:
		alpha = clampf((t_ms - from) / fade, 0.0, 1.0)
		if t_ms > end_ms:
			alpha = minf(alpha, clampf(1.0 - (t_ms - end_ms) / fade, 0.0, 1.0))
	return {
		"shown": alpha > 0.0,
		"alpha": alpha,
		"progress": progress(t_ms, launch_ms, impact_ms),
		"locked": t_ms >= impact_ms,
	}


## The bracket's half size in pixels at progress `u`: wide at the launch, `end_px` at impact.
static func radius_px(u: float, start_px: float, end_px: float) -> float:
	return lerpf(start_px, end_px, clampf(u, 0.0, 1.0))


## Extra brightness (0..1) right after the bracket locks, fading over `pulse_ms`; 0 before the
## impact and after the pulse. The caller scales it by the Flashes setting.
static func lock_pulse(t_ms: float, impact_ms: float, pulse_ms: float) -> float:
	var since := t_ms - impact_ms
	if since < 0.0 or pulse_ms <= 0.0 or since >= pulse_ms:
		return 0.0
	return 1.0 - since / pulse_ms
