class_name PartyAnim
extends RefCounted
## Which clip cell a hero shows while defending or getting hit in an enemy attack (DESIGN.md 5.5,
## cards #61 and #62), picked from the runner's anim entry. Pure and static, driven by attack
## time (microseconds), so a hit-stop freezes the frames with the motion. The spans are the ones
## TimedSequenceRunner already computes; this never moves them.
##
## - PARRY: `parry` from the press to the contact moment, then `parry_hit` until the pose ends.
## - DODGE: `dodge`: its first cell while sliding out, its last while coming back, the middle cells
##   in between (the runner's slide shares).
## - JUMP: `jump_up` to the apex, `jump_down` to the landing.
## - WHIFF: the pressed defence's way in (`parry`, `jump_up`, or `dodge` without its last cell)
##   over the first half of the whiff, then held.
## - HURT: `hurt`, or `stagger` for a heavy hit, over the flinch.
## An empty clip name means "show the entry's legacy frame", exactly as before phase 10.

const PARRY := "parry"
const PARRY_HIT := "parry_hit"
const DODGE := "dodge"
const JUMP_UP := "jump_up"
const JUMP_DOWN := "jump_down"
const HURT := "hurt"
const STAGGER := "stagger"


## {clip: String, index: int} for the runner's anim entry `anim` ({kind: TimedSequenceRunner.Anim,
## frame, from_us, until_us, and contact_us for a defence, apex_us and land_us for a jump, heavy
## for a hit}) at attack time `t_us`. `count` is a Callable(String) -> int giving how many cells a
## clip name plays after the fallbacks (FighterView.clip_count, or EnemyAnim.counter in tests).
## `dodge_out_share` and `dodge_back_share` are the shares of a dodge spent sliding out and back.
static func pick(anim: Dictionary, t_us: int, count: Callable, dodge_out_share: float,
		dodge_back_share: float) -> Dictionary:
	var from := float(anim.get("from_us", 0))
	var until := float(anim.get("until_us", 0))
	var t := float(t_us)
	match int(anim.get("kind", TimedSequenceRunner.Anim.NONE)):
		TimedSequenceRunner.Anim.PARRY:
			var contact := clampf(float(anim.get("contact_us", from)), from, maxf(from, until))
			if t < contact:
				return _spread(PARRY, count, t - from, contact - from)
			return _spread(PARRY_HIT, count, t - contact, until - contact)
		TimedSequenceRunner.Anim.DODGE:
			var n := int(count.call(DODGE))
			if n <= 0:
				return _legacy()
			var u := (t - from) / maxf(1.0, until - from)
			return {"clip": DODGE, "index": dodge_index(n, u, dodge_out_share, dodge_back_share)}
		TimedSequenceRunner.Anim.JUMP:
			var apex := float(anim.get("apex_us", until))
			var land := float(anim.get("land_us", until))
			if t < apex:
				return _spread(JUMP_UP, count, t - from, apex - from)
			return _spread(JUMP_DOWN, count, t - apex, land - apex)
		TimedSequenceRunner.Anim.WHIFF:
			return _whiff(int(anim.get("frame", FighterView.CharPose.READY)), count, t - from, (until - from) * 0.5)
		TimedSequenceRunner.Anim.HURT:
			var clip := STAGGER if bool(anim.get("heavy", false)) else HURT
			return _spread(clip, count, t - from, until - from)
	return _legacy()


## The cell of an n-cell dodge at progress `u`: the first cell while sliding out (u below
## `out_share`), the last while coming back (from 1 - `back_share`), the middle cells in between.
static func dodge_index(n: int, u: float, out_share: float, back_share: float) -> int:
	if n <= 1:
		return 0
	if u >= 1.0 - back_share:
		return n - 1
	if u < out_share or n == 2:
		return 0
	var middle := (u - out_share) / maxf(0.0001, 1.0 - back_share - out_share)
	return 1 + ClipMath.stretch(n - 2, middle)


## The pressed defence's way in (`frame` is its legacy pose), over `in_us`, then held.
static func _whiff(frame: int, count: Callable, elapsed_us: float, in_us: float) -> Dictionary:
	var clip := ""
	var cells := 0
	match frame:
		FighterView.CharPose.PARRY:
			clip = PARRY
			cells = int(count.call(PARRY))
		FighterView.CharPose.JUMP:
			clip = JUMP_UP
			cells = int(count.call(JUMP_UP))
		FighterView.CharPose.DODGE:
			# Into the dodge and held there: never the step back out.
			clip = DODGE
			cells = int(count.call(DODGE))
			cells = maxi(1, cells - 1) if cells > 0 else 0
	if cells <= 0:
		return _legacy()
	return {"clip": clip, "index": ClipMath.once(cells, elapsed_us, maxf(0.0, in_us))}


## `clip` spread evenly over `length_us`, `elapsed_us` into it; the legacy frame without the clip.
static func _spread(clip: String, count: Callable, elapsed_us: float, length_us: float) -> Dictionary:
	var n := int(count.call(clip))
	if n <= 0:
		return _legacy()
	return {"clip": clip, "index": ClipMath.once(n, elapsed_us, maxf(0.0, length_us))}


## Nothing fits: the caller shows the entry's legacy frame.
static func _legacy() -> Dictionary:
	return {"clip": "", "index": 0}
