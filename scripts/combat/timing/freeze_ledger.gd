class_name FreezeLedger
extends RefCounted
## Who owns each hit-stop freeze on a shared AttackClock (card #180). The clock is shared by every
## local player, so one player's parry freezes it for all. The owner's own double tap inside the
## freeze is ignored (DESIGN.md 3.3), but another player's press is NOT dropped: it is judged at
## the time it would have had without the freeze (the same trick as the hurt freeze). Pure: the
## caller passes every real timestamp in (microseconds, Time.get_ticks_usec()).

## Returned by press_shift_us() for a press that must be ignored (the freeze owner's own tap).
const IGNORE: int = -1

var _from := PackedInt64Array()
var _to := PackedInt64Array()
var _owners: Array = []


func clear() -> void:
	_from.clear()
	_to.clear()
	_owners.clear()


## Records a freeze from `from_us` for `duration_us`, owned by these players. A freeze nobody owns
## (the hurt freeze after the last hit) is passed with no owners: it ignores no one.
func add(from_us: int, duration_us: int, owners: Array[int]) -> void:
	if duration_us <= 0:
		return
	_from.append(from_us)
	_to.append(from_us + duration_us)
	_owners.append(owners.duplicate())


## What to do with a press by `player` stamped `stamp_us`: IGNORE it (inside a freeze that player
## owns), or the extra attack time (microseconds, 0 outside any freeze) to add to the clock's
## attack time for that stamp, so the press is judged as if no freeze had happened.
func press_shift_us(stamp_us: int, player: int) -> int:
	var start := -1
	for i: int in _from.size():
		if stamp_us >= _from[i] and stamp_us < _to[i]:
			if (_owners[i] as Array).has(player):
				return IGNORE
			start = _from[i] if start < 0 else mini(start, _from[i])
	if start < 0:
		return 0
	# The clock merges freezes that touch, so the frozen attack time is the one at the start of
	# the whole chain.
	var changed := true
	while changed:
		changed = false
		for j: int in _from.size():
			if _from[j] < start and _to[j] >= start:
				start = _from[j]
				changed = true
	return stamp_us - start
