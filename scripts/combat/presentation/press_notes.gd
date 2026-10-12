class_name PressNotes
extends RefCounted
## Where and how big a skill's press rings are (DESIGN.md 2.10). Each press moment is one "note":
## its own ring at its own spot. A skill with several presses lays its notes out in a row, left to
## right in press order and numbered, so a string of presses never stacks rings on top of each
## other (osu-style). One press answers every striker's prompt at that moment (the team ultimate),
## so a note groups those prompts. Pure functions, unit-tested.


## The press moments of a skill's prompts, in order: [{hit: int, at_ms: int, prompts: [idx]}].
## Only "press" prompts count (follow-ups get their own ring at their ally).
static func notes(prompts: Array) -> Array[Dictionary]:
	var by_hit: Dictionary = {}
	var order: Array[int] = []
	for idx: int in prompts.size():
		var p: Dictionary = prompts[idx]
		if String(p.role) != CombatEngine.ROLE_PRESS:
			continue
		var hit := int(p.hit)
		if not by_hit.has(hit):
			by_hit[hit] = {"hit": hit, "at_ms": int(p.at_ms), "prompts": []}
			order.append(hit)
		(by_hit[hit].prompts as Array).append(idx)
	order.sort_custom(func(a: int, b: int) -> bool: return int(by_hit[a].at_ms) < int(by_hit[b].at_ms))
	var list: Array[Dictionary] = []
	for hit: int in order:
		list.append(by_hit[hit])
	return list


## Offset (screen pixels) of note `k` of `count` from the middle of the row.
static func offset(k: int, count: int, spacing_px: float) -> Vector2:
	return Vector2((float(k) - float(count - 1) * 0.5) * spacing_px, 0.0)


## Size of the rings in a row of `count` notes, as a share of a single press ring.
static func scale(count: int, note_scale: float) -> float:
	return 1.0 if count <= 1 else note_scale


## Radius of a ring `rel_us` from its perfect moment: start_px when it appears `lead_us` before,
## end_px (the target circle) at the perfect moment, still shrinking after, never below min_px.
static func radius(rel_us: int, lead_us: int, start_px: float, end_px: float, min_px: float) -> float:
	var span := start_px - end_px
	return maxf(min_px, end_px - span * float(rel_us) / float(maxi(1, lead_us)))
