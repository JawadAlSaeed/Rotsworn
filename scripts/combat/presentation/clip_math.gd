class_name ClipMath
extends RefCounted
## Pure frame-index maths for sprite clips (DESIGN.md 5.5): which of a clip's n cells shows at a
## progress, some time into a one-shot, or at some time of a loop, and each fighter's loop phase.
## No clock of its own: callers pass real time, attack time or skill time.

## Golden-ratio step between the loop phases of fighter ids, so no two fighters breathe in step.
const GOLDEN: float = 0.618034


## The cell index (0..n-1) at progress `u`: the n cells share the progress evenly. u <= 0 gives
## the first cell, u >= 1 the last. 0 for an empty or one-cell clip.
static func stretch(n: int, u: float) -> int:
	if n <= 1:
		return 0
	return clampi(floori(u * float(n)), 0, n - 1)


## A one-shot of n cells spread evenly over `length_ms`, `t_ms` after it started. It holds the
## last cell once the length is over (and shows the first before it starts).
static func once(n: int, t_ms: float, length_ms: float) -> int:
	if n <= 1:
		return 0
	if length_ms <= 0.0:
		return 0 if t_ms < 0.0 else n - 1
	# t * n / length rather than (t / length) * n: exact on the cell boundaries.
	return clampi(floori(t_ms * float(n) / length_ms), 0, n - 1)


## A loop of n cells, one cycle every `period_ms`, at time `t_ms` shifted by `phase_ms`.
static func loop(n: int, t_ms: float, period_ms: float, phase_ms: float = 0.0) -> int:
	if n <= 1 or period_ms <= 0.0:
		return 0
	return clampi(floori(fposmod(t_ms + phase_ms, period_ms) * float(n) / period_ms), 0, n - 1)


## The loop phase (0..period_ms) of fighter `id`: heroes 0-2, enemies after them (ids under 0
## were the zones' walkers until phase 26). The same id always gets the same phase.
static func phase_for(id: int, period_ms: float) -> float:
	return fposmod(float(id) * GOLDEN, 1.0) * period_ms
