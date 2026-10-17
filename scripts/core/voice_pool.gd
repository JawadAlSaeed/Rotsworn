class_name VoicePool
extends RefCounted
## Picks which sound player a new cue uses (pure, tested). A free player first; only when all are
## busy, steal the one with the least time left (it is closest to finishing anyway).


## The index of the player to use. `busy[i]` is whether player i is sounding, `remaining_s[i]` how
## many seconds it still has. -1 if there are no players.
static func pick(busy: Array[bool], remaining_s: Array[float]) -> int:
	var best := -1
	for i: int in busy.size():
		if not busy[i]:
			return i
	for i: int in busy.size():
		if best < 0 or remaining_s[i] < remaining_s[best]:
			best = i
	return best


## True if a cue started `elapsed_ms` ago must not start again yet (`last_ms` < 0: never played).
static func in_cooldown(last_ms: int, now_ms: int, cooldown_ms: int) -> bool:
	return last_ms >= 0 and now_ms - last_ms < cooldown_ms
