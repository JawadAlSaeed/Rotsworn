class_name Backpack
extends RefCounted
## The party's shared backpack (DESIGN.md 8.1): a grid `width` cells wide and `rows` tall. Each
## item covers the cells of its shape, turned in 90 degree steps, and no two items overlap. Pure
## and unit-tested; the backpack screen only calls these functions and draws the result.
## Every placed item has a uid that stays the same while it is moved, so online players can name
## it in a request even after other items moved.

var width: int = 4
var rows: int = 5
## Every placed item: {uid: int, item: ItemData, x: int, y: int, turn: int (0 to 3), level: int
## (0, or higher once combined: DESIGN.md 8.1)}.
var entries: Array[Dictionary] = []
var next_uid: int = 1


func _init(p_width: int = 4, p_rows: int = 5) -> void:
	width = p_width
	rows = p_rows


## `cells` turned clockwise `turn` times (on screen, y down), moved so the top-left is (0, 0).
static func turned(cells: Array[Vector2i], turn: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c: Vector2i in cells:
		var p := c
		for i: int in posmod(turn, 4):
			p = Vector2i(-p.y, p.x)
		out.append(p)
	if out.is_empty():
		return out
	var low := out[0]
	for p: Vector2i in out:
		low = Vector2i(mini(low.x, p.x), mini(low.y, p.y))
	for i: int in out.size():
		out[i] -= low
	return out


## Width and height of a set of cells (from (0, 0)).
static func extent(cells: Array[Vector2i]) -> Vector2i:
	var size := Vector2i.ZERO
	for c: Vector2i in cells:
		size = Vector2i(maxi(size.x, c.x + 1), maxi(size.y, c.y + 1))
	return size


## The grid cells `item` would cover with its top-left at (x, y), turned `turn` times.
static func cells_at(item: ItemData, x: int, y: int, turn: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c: Vector2i in turned(item.shape, turn):
		out.append(c + Vector2i(x, y))
	return out


func cell_count() -> int:
	return width * rows


## The uid of the item covering `cell` (-1: empty or off the grid).
func uid_at(cell: Vector2i) -> int:
	for e: Dictionary in entries:
		if cells_at(e.item as ItemData, int(e.x), int(e.y), int(e.turn)).has(cell):
			return int(e.uid)
	return -1


## True if `item` fits with its top-left at (x, y), turned `turn` times: inside the grid and over
## no other item (the item `ignore_uid` does not count, so an item can move onto its own cells).
func fits(item: ItemData, x: int, y: int, turn: int, ignore_uid: int = -1) -> bool:
	if item == null or item.shape.is_empty():
		return false
	var taken := {}
	for e: Dictionary in entries:
		if int(e.uid) == ignore_uid:
			continue
		for c: Vector2i in cells_at(e.item as ItemData, int(e.x), int(e.y), int(e.turn)):
			taken[c] = true
	for c: Vector2i in cells_at(item, x, y, turn):
		if c.x < 0 or c.y < 0 or c.x >= width or c.y >= rows or taken.has(c):
			return false
	return true


## The first place `item` fits, row by row from the top-left, trying each turn: {x, y, turn},
## or {} if it fits nowhere.
func find_spot(item: ItemData) -> Dictionary:
	if item == null:
		return {}
	var tried: Array = []
	for turn: int in 4:
		var shape := turned(item.shape, turn)
		shape.sort()
		if tried.has(shape):
			continue
		tried.append(shape)
		for y: int in rows:
			for x: int in width:
				if fits(item, x, y, turn):
					return {"x": x, "y": y, "turn": turn}
	return {}


## Places `item` at (x, y) turned `turn` times. Returns its uid, or -1 if it does not fit.
func add(item: ItemData, x: int, y: int, turn: int, level: int = 0) -> int:
	if not fits(item, x, y, turn):
		return -1
	var uid := next_uid
	next_uid += 1
	entries.append({"uid": uid, "item": item, "x": x, "y": y, "turn": posmod(turn, 4), "level": maxi(0, level)})
	return uid


## Places `item` wherever it fits first (find_spot). Returns its uid, or -1 if there is no room.
func add_anywhere(item: ItemData, level: int = 0) -> int:
	var spot := find_spot(item)
	if spot.is_empty():
		return -1
	return add(item, int(spot.x), int(spot.y), int(spot.turn), level)


## The uids of the items whose cells touch item `uid`'s cells side by side (not corner to corner).
func touching(uid: int) -> Array[int]:
	var e := entry(uid)
	var found: Array[int] = []
	if e.is_empty():
		return found
	var mine := cells_at(e.item as ItemData, int(e.x), int(e.y), int(e.turn))
	for other: Dictionary in entries:
		if int(other.uid) == uid:
			continue
		for c: Vector2i in cells_at(other.item as ItemData, int(other.x), int(other.y), int(other.turn)):
			if mine.has(c + Vector2i.UP) or mine.has(c + Vector2i.DOWN) or mine.has(c + Vector2i.LEFT) \
					or mine.has(c + Vector2i.RIGHT):
				found.append(int(other.uid))
				break
	return found


## Moves item `uid` to (x, y) turned `turn` times. False (and nothing moves) if it does not fit.
func move(uid: int, x: int, y: int, turn: int) -> bool:
	var e := entry(uid)
	if e.is_empty() or not fits(e.item as ItemData, x, y, turn, uid):
		return false
	e.x = x
	e.y = y
	e.turn = posmod(turn, 4)
	return true


## Takes item `uid` out. Returns the item (null if there is no such uid).
func remove(uid: int) -> ItemData:
	for i: int in entries.size():
		if int(entries[i].uid) == uid:
			var item := entries[i].item as ItemData
			entries.remove_at(i)
			return item
	return null


## The entry of item `uid` ({} if there is none). Changing it changes the backpack.
func entry(uid: int) -> Dictionary:
	for e: Dictionary in entries:
		if int(e.uid) == uid:
			return e
	return {}


func has_uid(uid: int) -> bool:
	return not entry(uid).is_empty()


## How many of the grid's cells are free.
func free_cells() -> int:
	var used := 0
	for e: Dictionary in entries:
		used += (e.item as ItemData).shape.size()
	return cell_count() - used


## Plain data for online play and saving: [width, rows, next_uid,
## [[uid, id, x, y, turn, level], ...]].
func to_array() -> Array:
	var list: Array = []
	for e: Dictionary in entries:
		list.append([int(e.uid), (e.item as ItemData).id, int(e.x), int(e.y), int(e.turn), int(e.get("level", 0))])
	return [width, rows, next_uid, list]


## A backpack from to_array() data; `by_id` maps item ids to ItemData. Null if the data is
## malformed, names an unknown item, or has items that overlap or stick out.
static func from_array(d: Variant, by_id: Dictionary) -> Backpack:
	if not d is Array or (d as Array).size() != 4:
		return null
	var a := d as Array
	for i: int in 3:
		if typeof(a[i]) != TYPE_INT or int(a[i]) < 1:
			return null
	if not a[3] is Array:
		return null
	var pack := Backpack.new(int(a[0]), int(a[1]))
	for row: Variant in a[3]:
		if not row is Array or (row as Array).size() < 5 or (row as Array).size() > 6:
			return null
		var r := (row as Array).duplicate()
		if r.size() == 5:
			r.append(0)
		if typeof(r[1]) != TYPE_STRING or not by_id.has(String(r[1])):
			return null
		for i: int in [0, 2, 3, 4, 5]:
			if typeof(r[i]) != TYPE_INT:
				return null
		var item := by_id[String(r[1])] as ItemData
		if pack.has_uid(int(r[0])) or not pack.fits(item, int(r[2]), int(r[3]), int(r[4])):
			return null
		pack.entries.append({"uid": int(r[0]), "item": item, "x": int(r[2]), "y": int(r[3]), "turn": posmod(int(r[4]), 4),
				"level": maxi(0, int(r[5]))})
	pack.next_uid = int(a[2])
	for e: Dictionary in pack.entries:
		pack.next_uid = maxi(pack.next_uid, int(e.uid) + 1)
	return pack
