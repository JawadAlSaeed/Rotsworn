class_name CameraShots
extends RefCounted
## Where the combat camera goes for each moment of a fight (DESIGN.md 7.3): pure functions that
## return a shot {pos: Vector3, target: Vector3, fov: float}. Positions are fighters' feet; shots
## look at chest height (CHEST_HEIGHT above the feet). Unit-tested.

## Shots look at this height above the subjects' feet (world units).
const CHEST_HEIGHT: float = 1.0
## frame(): the camera stays between these distances from the middle of the points, found to
## within (max - min) / 2^FRAME_STEPS.
const FRAME_MIN_DISTANCE: float = 3.0
const FRAME_MAX_DISTANCE: float = 40.0
const FRAME_STEPS: int = 16


static func shot(pos: Vector3, target: Vector3, fov: float) -> Dictionary:
	return {"pos": pos, "target": target, "fov": fov}


## The fixed 3/4 view of the whole arena.
static func base(v: CombatVisuals) -> Dictionary:
	return shot(v.camera_position, v.camera_target, v.camera_fov)


## The base view moved so its centre goes `share` of the way toward `focus` (feet) and the
## camera comes `push` world units closer. Keeps the 3/4 angle, so the fight still reads.
static func drift(v: CombatVisuals, focus: Vector3, share: float, push: float) -> Dictionary:
	var b := base(v)
	var b_target: Vector3 = b.target
	var b_pos: Vector3 = b.pos
	var aim := Vector3(focus.x, b_target.y, focus.z)
	var target := b_target.lerp(aim, clampf(share, 0.0, 1.0))
	var pos := b_pos + (target - b_target) + (b_target - b_pos).normalized() * push
	return shot(pos, target, v.camera_fov)


## A party member's turn: drift toward them.
static func turn(v: CombatVisuals, actor: Vector3) -> Dictionary:
	return drift(v, actor, v.turn_focus_share, v.turn_push)


## An enemy attack: drift toward the middle of the attacker and the spot it hits.
static func attack(v: CombatVisuals, enemy: Vector3, contact: Vector3) -> Dictionary:
	return drift(v, (enemy + contact) * 0.5, v.attack_focus_share, v.attack_push)


## A strike or skill: framed on the middle of the strikers and their target (an ultimate uses the
## low ultimate shot).
static func strike(v: CombatVisuals, from: Vector3, to: Vector3, ultimate: bool) -> Dictionary:
	var target := (from + to) * 0.5 + Vector3(0.0, CHEST_HEIGHT, 0.0)
	var offset := v.ultimate_shot_offset if ultimate else v.skill_shot_offset
	return shot(target + offset, target, v.ultimate_shot_fov if ultimate else v.skill_shot_fov)


## The 3/4 base angle, pulled back just far enough that every point fits inside `safe` (a share
## of the screen: x and y from the top left, 0..1) on a screen of `aspect` (width / height). Used
## for follow-ups, so every ally pressing and the enemy stay in view (card #49).
static func frame(v: CombatVisuals, points: Array[Vector3], aspect: float, safe: Rect2) -> Dictionary:
	if points.is_empty():
		return base(v)
	var lo := points[0]
	var hi := points[0]
	for p: Vector3 in points:
		lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
		hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
	var target := (lo + hi) * 0.5
	var b := base(v)
	var back := ((b.pos as Vector3) - (b.target as Vector3)).normalized()
	var fov := v.camera_fov
	var near := FRAME_MIN_DISTANCE
	var far := FRAME_MAX_DISTANCE
	if not fits(shot(target + back * far, target, fov), points, aspect, safe):
		return shot(target + back * far, target, fov)
	for _i: int in FRAME_STEPS:
		var mid := (near + far) * 0.5
		if fits(shot(target + back * mid, target, fov), points, aspect, safe):
			far = mid
		else:
			near = mid
	return shot(target + back * far, target, fov)


## True if every point of `points` shows inside `safe` (screen shares, top left origin) for shot
## `s` on a screen of `aspect`. Same projection as a Camera3D keeping its vertical field of view.
static func fits(s: Dictionary, points: Array[Vector3], aspect: float, safe: Rect2) -> bool:
	for p: Vector3 in points:
		var at := screen_share(s, p, aspect)
		if at.x < safe.position.x or at.x > safe.end.x or at.y < safe.position.y or at.y > safe.end.y:
			return false
	return true


## Where point `p` shows for shot `s`, as a share of the screen (0..1 from the top left); behind
## the camera gives (-1, -1).
static func screen_share(s: Dictionary, p: Vector3, aspect: float) -> Vector2:
	var pos: Vector3 = s.pos
	var basis := Basis.looking_at((s.target as Vector3) - pos, Vector3.UP)
	var rel := p - pos
	var depth := rel.dot(-basis.z)
	if depth <= 0.001:
		return Vector2(-1.0, -1.0)
	var t := tan(deg_to_rad(float(s.fov)) * 0.5)
	var ndc := Vector2(rel.dot(basis.x) / (depth * t * aspect), rel.dot(basis.y) / (depth * t))
	return Vector2(0.5 + ndc.x * 0.5, 0.5 - ndc.y * 0.5)


## A counter: a quick push toward the enemy.
static func counter(v: CombatVisuals, enemy: Vector3) -> Dictionary:
	return drift(v, enemy, 0.5, v.counter_push)


## Victory or defeat: the end shot around the middle of the arena.
static func ending(v: CombatVisuals, centre: Vector3) -> Dictionary:
	var target := centre + Vector3(0.0, CHEST_HEIGHT, 0.0)
	return shot(target + v.end_shot_offset, target, v.camera_fov)


## `s` turned around its own target by `degrees` (an orbit).
static func orbit(s: Dictionary, degrees: float) -> Dictionary:
	var target: Vector3 = s.target
	var pos: Vector3 = s.pos
	var turned := target + (pos - target).rotated(Vector3.UP, deg_to_rad(degrees))
	return shot(turned, target, float(s.fov))
