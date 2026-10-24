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
##   over the first half of the whiff, then held. The runner uses it for a missed parry; a missed
##   jump or dodge plays the real move (missed(), card #309).
## - HURT: `hurt`, or `stagger` for a heavy hit, over the flinch.
## An empty clip name means "show the entry's legacy frame", exactly as before phase 10.
##
## It also builds the runner's anim entries (defence(), missed()) and the body's lift and slide
## shares on attack time (lift(), slide()), so the runner and the tests share one copy.

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


## The anim entry of a defence pressed at attack time `t_us` against a hit at `impact_us` whose
## window for that button closes `late_us` after it (DESIGN.md 3.6). The pose holds from the press
## until at least impact + late edge: parry and dodge for at least their minimum length, a jump for
## about jump_airtime_ms with the apex at impact when the press leaves time for it, else the
## fastest rise. `contact_us` is the contact moment (sound, popup, hit-stop): the impact, or the
## press if later; for a jump also not before the body is JUMP_CLEAR_HEIGHT up, so the freeze
## never shows a successful jump standing in the wave. `lift_share` and `slide_share` (kept as
## `lift` and `slide`) are where the body already is when the pose starts, as shares of the jump
## height and the dodge slide (see lift() and slide()), so a pose that takes over from a moving one
## carries on from there instead of snapping back to the spot first (card #309). {} for any other
## action.
static func defence(action: int, t_us: int, impact_us: int, late_us: int, visuals: CombatVisuals,
		lift_share: float = 0.0, slide_share: float = 0.0) -> Dictionary:
	var hold_until := impact_us + late_us
	var contact := maxi(t_us, impact_us)
	var entry: Dictionary = {}
	match action:
		Defense.Outcome.PARRY:
			entry = {"kind": TimedSequenceRunner.Anim.PARRY, "frame": FighterView.CharPose.PARRY, "from_us": t_us,
					"until_us": maxi(hold_until, t_us + visuals.parry_pose_min_ms * 1000)}
		Defense.Outcome.DODGE:
			entry = {"kind": TimedSequenceRunner.Anim.DODGE, "frame": FighterView.CharPose.DODGE, "from_us": t_us,
					"until_us": maxi(hold_until, t_us + visuals.dodge_pose_min_ms * 1000)}
		Defense.Outcome.JUMP:
			# Apex at impact when the press leaves time for it (up to half the airtime), else the
			# fastest rise; the whole jump lasts about jump_airtime_ms.
			var fast := visuals.jump_rise_fast_ms * 1000
			var rise := clampi(impact_us - t_us, fast, maxi(fast, visuals.jump_airtime_ms * 500))
			var apex := t_us + rise
			var fall := maxi(visuals.jump_airtime_ms * 1000 - rise, fast)
			var base := clampf(lift_share, 0.0, 1.0)
			entry = {"kind": TimedSequenceRunner.Anim.JUMP, "frame": FighterView.CharPose.JUMP, "from_us": t_us,
					"until_us": apex + fall, "apex_us": apex, "land_us": apex + fall}
			# The rise y = base + (1 - base)(1 - (1 - u)^2) reaches JUMP_CLEAR_HEIGHT at
			# u = 1 - sqrt(1 - need), need being the share of the climb still to go.
			var need := clampf((TimedSequenceRunner.JUMP_CLEAR_HEIGHT - base) / maxf(0.0001, 1.0 - base), 0.0, 1.0)
			contact = maxi(contact, t_us + roundi(float(rise) * (1.0 - sqrt(1.0 - need))))
		_:
			return {}
	# The parry clip turns into its hit frames at this moment (pick()).
	entry["contact_us"] = contact
	entry["lift"] = clampf(lift_share, 0.0, 1.0)
	entry["slide"] = clampf(slide_share, 0.0, 1.0)
	return entry


## The anim entry of a defence press that defended nothing, pressed at attack time `t_us`: early,
## late, the wrong button, locked out, with nothing left to defend, or still in the lead-in (card
## #309). The move plays anyway, aimed at no hit, so the player sees the press registered: a jump
## rises for half of jump_airtime_ms and comes back down, a dodge slides out and back over
## dodge_pose_min_ms, a parry raises the guard over half of whiff_pose_ms and holds it (never its
## hit frames). Marked `missed`. {} for any other action.
static func missed(action: int, t_us: int, visuals: CombatVisuals) -> Dictionary:
	var entry: Dictionary = {}
	match action:
		Defense.Outcome.PARRY:
			entry = {"kind": TimedSequenceRunner.Anim.WHIFF, "frame": FighterView.CharPose.PARRY, "from_us": t_us,
					"until_us": t_us + visuals.whiff_pose_ms * 1000}
		Defense.Outcome.DODGE:
			entry = defence(action, t_us, t_us, 0, visuals)
		Defense.Outcome.JUMP:
			entry = defence(action, t_us, t_us + visuals.jump_airtime_ms * 500, 0, visuals)
		_:
			return {}
	entry["missed"] = true
	return entry


## True while the anim entry `anim` still plays at attack time `t_us`.
static func is_playing(anim: Dictionary, t_us: int) -> bool:
	return not anim.is_empty() and t_us < int(anim.get("until_us", 0))


## How high the hero is at attack time `t_us`, as a share of the jump height (0 on the floor). A
## jump rises from where it took off (`lift`) to its apex and falls to the landing; any other pose
## that took over in the air (a flinch, a dodge, a parry) falls from that height (`lift`) over its
## length, so nothing snaps to the floor (card #309). 0 once `anim` is over.
static func lift(anim: Dictionary, t_us: int) -> float:
	if not is_playing(anim, t_us):
		return 0.0
	var from := float(anim.get("from_us", 0))
	var until := float(anim.get("until_us", 0))
	var t := float(t_us)
	var start := clampf(float(anim.get("lift", 0.0)), 0.0, 1.0)
	if int(anim.get("kind", TimedSequenceRunner.Anim.NONE)) == TimedSequenceRunner.Anim.JUMP:
		var apex := float(anim.get("apex_us", until))
		var land := float(anim.get("land_us", until))
		if t < apex:
			var u := clampf((t - from) / maxf(1.0, apex - from), 0.0, 1.0)
			return start + (1.0 - start) * (1.0 - (1.0 - u) * (1.0 - u))
		var down := clampf((t - apex) / maxf(1.0, land - apex), 0.0, 1.0)
		return 1.0 - down * down
	var s := clampf((t - from) / maxf(1.0, until - from), 0.0, 1.0)
	return start * (1.0 - s * s)


## How far out the hero has slid at attack time `t_us`, as a share of dodge_slide_distance. A
## dodge eases out from where it started (`slide`) over its first `out_share` and comes back over
## its last `back_share`; any other pose that took over mid-slide (a flinch, a jump, a parry) eases
## back from there (`slide`) over its length (card #309). 0 once `anim` is over.
static func slide(anim: Dictionary, t_us: int, out_share: float, back_share: float) -> float:
	if not is_playing(anim, t_us):
		return 0.0
	var from := float(anim.get("from_us", 0))
	var until := float(anim.get("until_us", 0))
	var s := (float(t_us) - from) / maxf(1.0, until - from)
	var start := clampf(float(anim.get("slide", 0.0)), 0.0, 1.0)
	if int(anim.get("kind", TimedSequenceRunner.Anim.NONE)) == TimedSequenceRunner.Anim.DODGE:
		var k := 1.0
		if s < out_share:
			k = start + (1.0 - start) * (1.0 - pow(1.0 - s / out_share, 2.0))
		elif s > 1.0 - back_share:
			k = 1.0 - (s - (1.0 - back_share)) / back_share
		return clampf(k, 0.0, 1.0)
	var back := 1.0 - clampf(s, 0.0, 1.0)
	return start * back * back


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
