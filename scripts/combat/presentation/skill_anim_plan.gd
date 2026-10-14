class_name SkillAnimPlan
extends RefCounted
## Which clip a hero shows during a skill, and how far into it (DESIGN.md 5.5, card #58). Pure and
## static: the runner calls pick() every frame on skill time, so the perfect-press hit-stop
## freezes the frames with the rings.
##
## A hero's presses k = 0..n-1 have their moments at_k. Press k winds up from
##   start_k = max(at_k - windup, contact_{k-1} (or at_{k-1} while unknown) + gap, 0)
## to at_k (held on its last cell when the press comes late), and strikes from its contact moment
## (max(press, at_k) for a good press, the window's close for a miss) over
##   min(strike, start_{k+1} - contact_k),
## so the next wind-up never starts on top of a strike. A press winds up only once the press before
## it has struck, so its frames never jump back. Otherwise the hero holds the combat stance.

enum Phase { READY, WINDUP, STRIKE }

## A contact not known yet.
const NO_CONTACT: int = -1


## The clip and progress at skill time `t_us`: {"phase": Phase, "press": k (-1 when READY),
## "clip": the clip name ("" = the combat stance), "u": progress 0..1 through it}.
## `at_us[k]` is press k's moment and `contact_us[k]` its contact (NO_CONTACT while unknown; a
## contact later than `t_us` counts as unknown, so the answer never looks ahead). Press k plays
## `windups[k % size]` and `strikes[k % size]` (an empty list keeps the stance). All times in
## microseconds of skill time.
static func pick(at_us: Array[int], contact_us: Array[int], windups: PackedStringArray,
		strikes: PackedStringArray, windup_us: int, strike_us: int, gap_us: int, t_us: int) -> Dictionary:
	var n := at_us.size()
	for k: int in range(n - 1, -1, -1):
		var contact := _contact(contact_us, k, t_us)
		if contact >= 0:
			var length := strike_us
			if k + 1 < n:
				length = mini(length, start_us(at_us, contact_us, k + 1, windup_us, gap_us, t_us) - contact)
			# The contact cell always shows at its moment, however short the strike is cut.
			length = maxi(1, length)
			if t_us < contact + length:
				return _result(Phase.STRIKE, k, strikes, float(t_us - contact) / float(length))
			return stance()
		if k > 0 and _contact(contact_us, k - 1, t_us) < 0:
			continue # the press before is still waiting for its contact
		var start := start_us(at_us, contact_us, k, windup_us, gap_us, t_us)
		if t_us < start:
			continue
		var span := at_us[k] - start
		var u := 1.0 if span <= 0 else clampf(float(t_us - start) / float(span), 0.0, 1.0)
		return _result(Phase.WINDUP, k, windups, u)
	return stance()


## When press k's wind-up starts (skill time, microseconds): `windup_us` before its moment, but no
## sooner than `gap_us` after the press before it struck (its moment while that is unknown).
static func start_us(at_us: Array[int], contact_us: Array[int], k: int, windup_us: int, gap_us: int,
		t_us: int) -> int:
	var start := at_us[k] - maxi(0, windup_us)
	if k > 0:
		var before := _contact(contact_us, k - 1, t_us)
		if before < 0:
			before = at_us[k - 1]
		start = maxi(start, before + gap_us)
	return maxi(start, 0)


## The combat stance (no clip).
static func stance() -> Dictionary:
	return {"phase": Phase.READY, "press": -1, "clip": "", "u": 0.0}


## Press k's clip from `names` (k % size), or the stance when the list is empty.
static func clip_for(names: PackedStringArray, k: int) -> String:
	return names[k % names.size()] if not names.is_empty() else ""


static func _result(phase: Phase, k: int, names: PackedStringArray, u: float) -> Dictionary:
	var clip := clip_for(names, k)
	if clip.is_empty():
		return stance()
	return {"phase": phase, "press": k, "clip": clip, "u": clampf(u, 0.0, 1.0)}


static func _contact(contact_us: Array[int], k: int, t_us: int) -> int:
	if k >= contact_us.size():
		return NO_CONTACT
	var c := contact_us[k]
	return c if c >= 0 and c <= t_us else NO_CONTACT
