class_name ZonePath
extends RefCounted
## Finding a way through a zone (DESIGN.md 8.5): the ground is cut into a grid of CELL squares; a
## cell is free when a walker of the given radius can stand on its centre (no obstacle overlap,
## inside the bounds). find() runs A* over free cells (8 ways, no cutting corners). Used by the zone
## bot and by tests that check every spot of a zone can be reached. Pure. Unit-tested.

const CELL: float = 0.5
const DIAGONAL: float = 1.41421356

var _min: Vector2 = Vector2.ZERO
var _cols: int = 0
var _rows: int = 0
## 1 = blocked, per cell (row by row).
var _blocked := PackedByteArray()


## The grid of a zone's ground for a walker of `radius`, with these obstacles (ZoneMotion's).
static func build(obstacles: Array[Dictionary], bounds_min: Vector2, bounds_max: Vector2, radius: float) -> ZonePath:
	var path := ZonePath.new()
	path._min = bounds_min
	path._cols = maxi(1, ceili((bounds_max.x - bounds_min.x) / CELL))
	path._rows = maxi(1, ceili((bounds_max.y - bounds_min.y) / CELL))
	path._blocked.resize(path._cols * path._rows)
	path._blocked.fill(0)
	for row: int in path._rows:
		for col: int in path._cols:
			var c := path.centre(Vector2i(col, row))
			if c.x < bounds_min.x + radius or c.x > bounds_max.x - radius or c.y < bounds_min.y + radius \
					or c.y > bounds_max.y - radius:
				path._blocked[row * path._cols + col] = 1
	for o: Dictionary in obstacles:
		path._stamp(o, radius)
	return path


## The centre of a cell on the ground.
func centre(cell: Vector2i) -> Vector2:
	return _min + (Vector2(cell) + Vector2(0.5, 0.5)) * CELL


func cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(clampi(floori((pos.x - _min.x) / CELL), 0, _cols - 1),
			clampi(floori((pos.y - _min.y) / CELL), 0, _rows - 1))


func is_free(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _cols and cell.y < _rows and _blocked[cell.y * _cols + cell.x] == 0


## A way from `from` to within `near` of `to`: the cell centres to walk through (the last one
## within `near` of `to`), or empty if there is none. Starting on a blocked cell (pressed against
## a wall) starts from the nearest free cell.
func find(from: Vector2, to: Vector2, near: float) -> PackedVector2Array:
	var start := _nearest_free(cell_of(from))
	if start.x < 0:
		return PackedVector2Array()
	var count := _cols * _rows
	var cost := PackedFloat32Array()
	cost.resize(count)
	cost.fill(INF)
	var came := PackedInt32Array()
	came.resize(count)
	came.fill(-1)
	var closed := PackedByteArray()
	closed.resize(count)
	closed.fill(0)
	var heap: Array[Vector2] = []  # (priority, index)
	var first := start.y * _cols + start.x
	cost[first] = 0.0
	_push(heap, Vector2(_guess(start, to), float(first)))
	var goal := -1
	while not heap.is_empty():
		var index := int(_pop(heap).y)
		if closed[index] == 1:
			continue
		closed[index] = 1
		@warning_ignore("integer_division")
		var cell := Vector2i(index % _cols, index / _cols)
		if centre(cell).distance_to(to) <= near:
			goal = index
			break
		for dy: int in [-1, 0, 1]:
			for dx: int in [-1, 0, 1]:
				if dx == 0 and dy == 0:
					continue
				var next := cell + Vector2i(dx, dy)
				if not is_free(next):
					continue
				if dx != 0 and dy != 0 and (not is_free(cell + Vector2i(dx, 0)) or not is_free(cell + Vector2i(0, dy))):
					continue
				var n := next.y * _cols + next.x
				var step := DIAGONAL if dx != 0 and dy != 0 else 1.0
				var c := cost[index] + step
				if c < cost[n]:
					cost[n] = c
					came[n] = index
					_push(heap, Vector2(c + _guess(next, to), float(n)))
	var out := PackedVector2Array()
	if goal < 0:
		return out
	var at := goal
	while at >= 0:
		@warning_ignore("integer_division")
		out.append(centre(Vector2i(at % _cols, at / _cols)))
		at = came[at]
	out.reverse()
	return out


## True if a walker can get from `from` to within `near` of `to`.
func reachable(from: Vector2, to: Vector2, near: float) -> bool:
	return not find(from, to, near).is_empty()


## Marks the cells a walker of `radius` cannot stand on because of obstacle `o`.
func _stamp(o: Dictionary, radius: float) -> void:
	var c: Vector2 = o.centre
	var reach: float
	if o.has("radius"):
		reach = float(o.radius) + radius
	else:
		reach = (o.half as Vector2).length() + radius
	var lo := cell_of(c - Vector2(reach, reach))
	var hi := cell_of(c + Vector2(reach, reach))
	for row: int in range(lo.y, hi.y + 1):
		for col: int in range(lo.x, hi.x + 1):
			if _overlaps(centre(Vector2i(col, row)), radius, o):
				_blocked[row * _cols + col] = 1


static func _overlaps(pos: Vector2, radius: float, o: Dictionary) -> bool:
	var c: Vector2 = o.centre
	if o.has("radius"):
		return pos.distance_to(c) < float(o.radius) + radius
	var half: Vector2 = o.half
	var local := (pos - c).rotated(float(o.angle))
	var nearest := Vector2(clampf(local.x, -half.x, half.x), clampf(local.y, -half.y, half.y))
	return local.distance_to(nearest) < radius


func _nearest_free(cell: Vector2i) -> Vector2i:
	if is_free(cell):
		return cell
	for ring: int in range(1, 8):
		for dy: int in range(-ring, ring + 1):
			for dx: int in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) == ring and is_free(cell + Vector2i(dx, dy)):
					return cell + Vector2i(dx, dy)
	return Vector2i(-1, -1)


func _guess(cell: Vector2i, to: Vector2) -> float:
	return centre(cell).distance_to(to) / CELL


# A binary min-heap of Vector2(priority, index).
static func _push(heap: Array[Vector2], item: Vector2) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		@warning_ignore("integer_division")
		var parent := (i - 1) / 2
		if heap[parent].x <= heap[i].x:
			break
		var swap := heap[parent]
		heap[parent] = heap[i]
		heap[i] = swap
		i = parent


static func _pop(heap: Array[Vector2]) -> Vector2:
	var top := heap[0]
	var last: Vector2 = heap.pop_back()
	if heap.is_empty():
		return top
	heap[0] = last
	var i := 0
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var smallest := i
		if l < heap.size() and heap[l].x < heap[smallest].x:
			smallest = l
		if r < heap.size() and heap[r].x < heap[smallest].x:
			smallest = r
		if smallest == i:
			break
		var swap := heap[smallest]
		heap[smallest] = heap[i]
		heap[i] = swap
		i = smallest
	return top
