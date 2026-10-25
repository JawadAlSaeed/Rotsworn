class_name Backpack
extends RefCounted
## The party's shared pack (DESIGN.md 8.1, 8.19, cards #282, #332): Alder's pack with `width`
## pockets in a row, one consumable per pocket whatever its shape (no shapes, no turning since phase
## 21; no levels, no combining and no growing since card #332). Pure and unit-tested; the Bag tab only
## calls these functions and draws the result.
## Every item has a uid that stays the same while it is in the pack, so online players can name it
## in a request even after other items moved. Cells are kept as Vector2i(pocket, 0) so the ops and
## saves of the old grid keep their shape.

## Pockets (tuning.backpack_pockets; the old grid's width). `rows` is always 1.
var width: int = 4
var rows: int = 1
## Every item: {uid: int, item: ItemData, x: int (its pocket), y: 0, turn: 0}.
var entries: Array[Dictionary] = []
var next_uid: int = 1


func _init(p_pockets: int = 4) -> void:
	width = maxi(1, p_pockets)
	rows = 1


## The pocket `item` would sit in with its pocket at x: one pocket, whatever its shape.
static func cells_at(_item: ItemData, x: int, y: int, _turn: int = 0) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [Vector2i(x, y)]
	return cells


func cell_count() -> int:
	return width


## The uid of the item in pocket `cell` (-1: empty or no such pocket).
func uid_at(cell: Vector2i) -> int:
	for e: Dictionary in entries:
		if int(e.x) == cell.x and cell.y == 0:
			return int(e.uid)
	return -1


## True if `item` fits in pocket x (y must be 0): a pocket of the pack that holds nothing (the
## item `ignore_uid` does not count, so an item can stay in its own pocket).
func fits(item: ItemData, x: int, y: int = 0, _turn: int = 0, ignore_uid: int = -1) -> bool:
	if item == null or x < 0 or x >= width or y != 0:
		return false
	var at := uid_at(Vector2i(x, 0))
	return at < 0 or at == ignore_uid


## The first free pocket for `item`: {x, y: 0, turn: 0}, or {} if the pack is full.
func find_spot(item: ItemData) -> Dictionary:
	if item == null:
		return {}
	for x: int in width:
		if fits(item, x):
			return {"x": x, "y": 0, "turn": 0}
	return {}


## Puts `item` in pocket x. Returns its uid, or -1 if that pocket is taken or not there.
func add(item: ItemData, x: int, y: int = 0, _turn: int = 0) -> int:
	if not fits(item, x, y):
		return -1
	var uid := next_uid
	next_uid += 1
	entries.append({"uid": uid, "item": item, "x": x, "y": 0, "turn": 0})
	return uid


## Puts `item` in the first free pocket. Returns its uid, or -1 if the pack is full.
func add_anywhere(item: ItemData) -> int:
	var spot := find_spot(item)
	if spot.is_empty():
		return -1
	return add(item, int(spot.x))


## Moves item `uid` to pocket x. False (and nothing moves) if that pocket is taken.
func move(uid: int, x: int, y: int = 0, _turn: int = 0) -> bool:
	var e := entry(uid)
	if e.is_empty() or not fits(e.item as ItemData, x, y, 0, uid):
		return false
	e.x = x
	return true


## Takes item `uid` out. Returns the item (null if there is no such uid).
func remove(uid: int) -> ItemData:
	for i: int in entries.size():
		if int(entries[i].uid) == uid:
			var item := entries[i].item as ItemData
			entries.remove_at(i)
			return item
	return null


## The entry of item `uid` ({} if there is none). Changing it changes the pack.
func entry(uid: int) -> Dictionary:
	for e: Dictionary in entries:
		if int(e.uid) == uid:
			return e
	return {}


func has_uid(uid: int) -> bool:
	return not entry(uid).is_empty()


## How many pockets are free.
func free_cells() -> int:
	return maxi(0, width - entries.size())


## Plain data for online play and saving: [pockets, 1, next_uid, [[uid, id, x, 0, 0], ...]].
func to_array() -> Array:
	var list: Array = []
	for e: Dictionary in entries:
		list.append([int(e.uid), (e.item as ItemData).id, int(e.x), 0, 0])
	return [width, 1, next_uid, list]


## A pack from to_array() data; `by_id` maps item ids to ItemData. Null if the data is malformed
## (an older shape too: the grid of before phase 21 or the levels of before card #332; such saves are
## refused by RunSave's format), names an unknown item or one that does not go in the pack, or puts
## two items in one pocket.
static func from_array(d: Variant, by_id: Dictionary) -> Backpack:
	if not d is Array or (d as Array).size() != 4:
		return null
	var a := d as Array
	for i: int in 3:
		if typeof(a[i]) != TYPE_INT or int(a[i]) < 1:
			return null
	if int(a[1]) != 1 or not a[3] is Array:
		return null
	var pack := Backpack.new(int(a[0]))
	for row: Variant in a[3]:
		if not row is Array or (row as Array).size() != 5:
			return null
		var r := row as Array
		if typeof(r[1]) != TYPE_STRING or not by_id.has(String(r[1])):
			return null
		for i: int in [0, 2, 3, 4]:
			if typeof(r[i]) != TYPE_INT:
				return null
		var item := by_id[String(r[1])] as ItemData
		if not item.goes_in_pack() or pack.has_uid(int(r[0])) or not pack.fits(item, int(r[2]), int(r[3])):
			return null
		pack.entries.append({"uid": int(r[0]), "item": item, "x": int(r[2]), "y": 0, "turn": 0})
	pack.next_uid = int(a[2])
	for e: Dictionary in pack.entries:
		pack.next_uid = maxi(pack.next_uid, int(e.uid) + 1)
	return pack
