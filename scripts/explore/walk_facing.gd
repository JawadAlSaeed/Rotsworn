class_name WalkFacing
extends RefCounted
## Which way a zone walker faces and where its walk cycle is (DESIGN.md 5.5, card #59). Pure and
## static: the zone feeds it ground directions (x right, y = world z, toward the camera) and the
## distance actually walked, so the feet follow the ground and stop against a wall.

## The four views. Screen up is world -z, so walking "up" shows the back.
enum Facing {
	SIDE_R,
	SIDE_L,
	FRONT,
	BACK,
}

## Clip name suffix of each view for the walk and stand clips ("walk_" + suffix).
const SUFFIXES: Array[String] = ["side", "side", "front", "back"]


## The view for a ground direction `dir`: its dominant axis. When the two axes are within `margin`
## of each other (a stick or keys pushed diagonally), the walker keeps `current` if it is one of
## the two views the diagonal is between, so the view never flickers; otherwise it turns sideways.
## A zero direction keeps `current`.
static func pick(dir: Vector2, current: Facing, margin: float) -> Facing:
	if dir.length() <= 0.0001:
		return current
	var d := dir.normalized()
	var side := Facing.SIDE_R if d.x >= 0.0 else Facing.SIDE_L
	var updown := Facing.FRONT if d.y >= 0.0 else Facing.BACK
	if absf(absf(d.x) - absf(d.y)) <= margin:
		return current if current == side or current == updown else side
	return side if absf(d.x) > absf(d.y) else updown


## True for the two side views (the only ones that mirror the art).
static func is_side(facing: Facing) -> bool:
	return facing == Facing.SIDE_R or facing == Facing.SIDE_L


## The walk phase after walking `moved` world units: one whole step every `stride`. A stride of 0
## (or less) leaves the phase alone, for the caller's old time-based steps.
static func advance(phase: float, moved: float, stride: float) -> float:
	if stride <= 0.0 or moved <= 0.0:
		return phase
	return phase + moved / stride


## The cell of an n-cell walk cycle at `phase`: one cycle is two steps (both feet), so a foot
## comes down on cell 0 and on cell n/2, each time the phase crosses a whole number.
static func cycle_index(n: int, phase: float) -> int:
	return ClipMath.stretch(n, fposmod(phase * 0.5, 1.0))
