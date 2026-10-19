class_name GroundStack
extends RefCounted
## Which height step each ground piece of a place lies on (card #269). Flat pieces at the same
## height fight over which one draws (they flicker through each other as the camera moves), so
## no two pieces that overlap may share a step. Pieces are taken in order of layer, then list
## order; each lies one step above the highest earlier piece it overlaps. So a higher layer
## always draws over a lower one it touches, and of two overlapping pieces on one layer the later
## one wins, every time. Pieces that do not touch may share a step, which keeps the stack low.
## Pure: no nodes. Unit-tested.


## The step of each piece (same order as `grounds`; a null piece gets 0).
static func levels(grounds: Array[ZoneGroundData]) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(grounds.size())
	var order: Array[int] = []
	for i: int in grounds.size():
		if grounds[i] != null:
			order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		return grounds[a].layer < grounds[b].layer or (grounds[a].layer == grounds[b].layer and a < b))
	var boxes: Array[Rect2] = []
	boxes.resize(grounds.size())
	for i: int in order:
		boxes[i] = footprint(grounds[i])
	for n: int in order.size():
		var i := order[n]
		var level := 0
		for m: int in n:
			var j := order[m]
			if boxes[i].intersects(boxes[j], true):
				level = maxi(level, out[j] + 1)
		out[i] = level
	return out


## The highest step any piece of `grounds` lies on (-1 for none).
static func top_level(grounds: Array[ZoneGroundData]) -> int:
	var top := -1
	for level: int in levels(grounds):
		top = maxi(top, level)
	return top


## How far over the floor a piece on `level` lies, with the look's numbers.
static func lift(look: StageLook, level: int) -> float:
	return look.ground_lift + look.ground_step * float(level)


## The box on the floor (x, z) a piece can cover, turned with it (a little more than the piece:
## a safe guess, it only costs a step).
static func footprint(data: ZoneGroundData) -> Rect2:
	var half := data.size * 0.5
	var angle := deg_to_rad(data.rotation_y_degrees)
	var reach := Vector2(absf(half.x * cos(angle)) + absf(half.y * sin(angle)),
			absf(half.x * sin(angle)) + absf(half.y * cos(angle)))
	return Rect2(Vector2(data.position.x, data.position.z) - reach, reach * 2.0)
