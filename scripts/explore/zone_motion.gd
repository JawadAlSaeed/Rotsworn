class_name ZoneMotion
extends RefCounted
## Walking on a zone's ground (DESIGN.md 7.4): pure 2D maths on the ground plane, Vector2(x, z).
## Things that block walking are obstacles: circles {centre, radius} for props and boxes
## {centre, half, angle} for blocks (angle = the block's turn around the vertical axis, radians).
## A walker is a circle that is pushed out of every obstacle and kept inside the zone's bounds.
## Unit-tested.

## Push-out passes per move: enough for a walker wedged between two obstacles.
const PASSES: int = 3
## Long steps are split so a fast walker never jumps through a thin wall.
const MAX_STEP: float = 0.25


## The obstacles of a zone: solid props (circles) and solid blocks (boxes).
static func obstacles(zone: ZoneData) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for prop: ZonePropData in zone.props:
		if prop != null and prop.solid_radius > 0.0:
			list.append({"centre": Vector2(prop.position.x, prop.position.z), "radius": prop.solid_radius})
	for block: ZoneBlockData in zone.blocks:
		if block != null and block.solid:
			list.append({"centre": Vector2(block.position.x, block.position.z),
					"half": Vector2(block.size.x, block.size.z) * 0.5, "angle": deg_to_rad(block.rotation_y_degrees)})
	return list


## Where a walker of `radius` at `from` ends up after trying to move by `step`.
static func move(from: Vector2, step: Vector2, radius: float, obstacles_list: Array[Dictionary],
		bounds_min: Vector2, bounds_max: Vector2) -> Vector2:
	var parts := maxi(1, ceili(step.length() / MAX_STEP))
	var pos := from
	for _i: int in parts:
		pos += step / float(parts)
		for _pass: int in PASSES:
			for o: Dictionary in obstacles_list:
				pos = push_out(pos, radius, o)
		pos = clamp_to_bounds(pos, radius, bounds_min, bounds_max)
	return pos


## `pos` moved just out of obstacle `o` if a walker of `radius` there overlaps it.
static func push_out(pos: Vector2, radius: float, o: Dictionary) -> Vector2:
	var centre: Vector2 = o.centre
	if o.has("radius"):
		var away := pos - centre
		var need := radius + float(o.radius)
		var dist := away.length()
		if dist >= need:
			return pos
		if dist < 0.0001:
			away = Vector2.RIGHT
			dist = 1.0
		return centre + away / dist * need
	var angle := float(o.angle)
	var half: Vector2 = o.half
	var local := (pos - centre).rotated(angle)
	var nearest := Vector2(clampf(local.x, -half.x, half.x), clampf(local.y, -half.y, half.y))
	var gap := local - nearest
	if gap.length() >= radius:
		return pos
	if gap.length() > 0.0001:
		local = nearest + gap.normalized() * radius
	else:
		# The centre is inside the box: leave by the nearest side.
		var to_x := half.x - absf(local.x)
		var to_y := half.y - absf(local.y)
		if to_x < to_y:
			local.x = signf(local.x if local.x != 0.0 else 1.0) * (half.x + radius)
		else:
			local.y = signf(local.y if local.y != 0.0 else 1.0) * (half.y + radius)
	return centre + local.rotated(-angle)


static func clamp_to_bounds(pos: Vector2, radius: float, bounds_min: Vector2, bounds_max: Vector2) -> Vector2:
	return Vector2(clampf(pos.x, bounds_min.x + radius, bounds_max.x - radius),
			clampf(pos.y, bounds_min.y + radius, bounds_max.y - radius))


## True if `target` is within `reach` of `from` and inside the arc of `arc_degrees` around
## `facing` (a direction; zero means any direction).
static func in_reach(from: Vector2, facing: Vector2, target: Vector2, reach: float, arc_degrees: float) -> bool:
	var to := target - from
	if to.length() > reach:
		return false
	if facing.length() < 0.0001 or to.length() < 0.0001:
		return true
	return absf(rad_to_deg(facing.angle_to(to))) <= arc_degrees * 0.5
