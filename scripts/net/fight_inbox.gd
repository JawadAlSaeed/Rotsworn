class_name FightInbox
extends RefCounted
## Online client: combat batches that arrived before their fight was built here, kept per fight (the
## host tags every batch with its fight's seed, cards #205, #304). A newcomer's catch-up can take
## seconds; meanwhile the host may finish that fight and start the next, so batches must never be
## thrown away just because a later fight was announced. Pure.
##
## The host plays one fight at a time and sends everything on one ordered channel, so fights first
## show up here in the order the host played them: when a fight is taken, the fights that showed up
## before it are over (this machine passed them), and their batches go too.

## fight seed -> its batches in arrival order (Array[Dictionary]).
var _batches: Dictionary = {}
## The fights waiting here, in the order their first batch arrived.
var _order: Array[int] = []
## The fights taken (built) or passed on this machine (seed -> true): their late batches are dropped.
var _played: Dictionary = {}


## Keeps `batch` (its "fight" seed) unless that fight was already played on this machine. A batch
## with no seed (0) is dropped too: no fight here could ever take it (seeds start at 1).
func add(batch: Dictionary) -> void:
	var fight := _seed_of(batch)
	if fight == 0 or _played.has(fight):
		return
	if not _batches.has(fight):
		var list: Array[Dictionary] = []
		_batches[fight] = list
		_order.append(fight)
	(_batches[fight] as Array[Dictionary]).append(batch)


## Removes and returns fight `fight`'s batches in arrival order; that fight counts as played (its
## late batches are dropped), and batches of fights played earlier are dropped too.
func take(fight: int) -> Array[Dictionary]:
	var taken: Array[Dictionary] = []
	var at := _order.find(fight)
	if at >= 0:
		for earlier: int in _order.slice(0, at):
			_forget(earlier)
		taken = _batches[fight] as Array[Dictionary]
		_forget(fight)
	_played[fight] = true
	return taken


## How many batches are waiting.
func size() -> int:
	var count := 0
	for fight: int in _order:
		count += (_batches[fight] as Array[Dictionary]).size()
	return count


## Forgets everything (a new online game or run).
func clear() -> void:
	_batches.clear()
	_order.clear()
	_played.clear()


func _forget(fight: int) -> void:
	_batches.erase(fight)
	_order.erase(fight)
	_played[fight] = true


static func _seed_of(batch: Dictionary) -> int:
	var value: Variant = batch.get("fight", 0)
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return int(value)
	return 0
