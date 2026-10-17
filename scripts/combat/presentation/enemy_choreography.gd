class_name EnemyChoreography
extends RefCounted
## The enemy's attack animation as a pure function of attack time (DESIGN.md 3.3 and 3.7).
## Because it only depends on the AttackClock, hit-stop freezes it exactly and what you see always
## matches what is judged: every normal lunge lasts approach_ms and reaches the contact point
## exactly at impact; a ground hit launches its wave approach_ms before impact.
##
## `hits` are the hit dictionaries of a timed_sequence_declared event (at_ms, kind, approach_ms,
## feint), optionally with `close_ms`: how long after impact the hit can still be defended on this
## machine (window late edge + lag compensation; see with_close_times). On an attack's last hit
## the contact pose is held until contact_after_close_ms past then, so a missed hit's flinch and
## hurt freeze show the enemy in contact; between hits the hold is capped by the next motion.
## `approach` in the result is 0 at the enemy's home and 1 at the contact point.
##
## Phase 10 (DESIGN.md 5.5) adds which beat of the attack a moment belongs to, so animation clips
## can be laid over the same spans without changing them: `beat`, `beat_ms` (attack ms since the
## beat began), `beat_len_ms` (its whole length; -1 for an open beat) and `beat_u` (progress 0..1;
## for a lunge and a feint's false start the lunge progress, so both show the same frames).
##
## Phase 12 (DESIGN.md 3.9): a ranged hit (its dictionary has `ranged` true, set by the runner from
## AttackHitData.projectile) never lunges. The enemy winds up, throws at the launch moment
## (impact - approach_ms, beat SHOOT, pose CONTACT) and waits where it is while the projectile
## flies (beat FLIGHT); the projectile arrives at impact.

## Frames of an enemy sheet (DESIGN.md 5.3).
enum Pose {
	IDLE,
	WINDUP,
	LUNGE,
	CONTACT,
	HURT,
	SLAM,
}

## Beats of an attack, in the order a hit plays them (DESIGN.md 5.5).
enum Beat {
	## Before the attack clock starts.
	BEFORE,
	## Wind-up before a hit's motion (pose WINDUP).
	WINDUP,
	## A ground hit's slam (pose SLAM).
	SLAM,
	## After the last ground hit's slam, until its wave reaches the party (pose IDLE).
	GROUND_WAIT,
	## A feint's false lunge (pose LUNGE).
	FEINT_START,
	## A feint's pause before the real lunge (pose WINDUP).
	FEINT_HOLD,
	## The lunge into the target, ending at impact (pose LUNGE).
	LUNGE,
	## Held in contact from impact (pose CONTACT).
	CONTACT,
	## Recoiling between the hits of a string (pose IDLE).
	RECOIL,
	## Walking home after the last hit (pose IDLE).
	RETURN,
	## Home again after the attack (pose IDLE).
	AFTER,
	## A ranged hit's throw (pose CONTACT).
	SHOOT,
	## After the last ranged hit's throw, until it arrives (pose IDLE).
	FLIGHT,
}

const CUE_LUNGE := "lunge"
const CUE_FEINT := "feint"
const CUE_SLAM := "slam"
const CUE_SHOOT := "shoot"


## {pose: Pose, approach: float, glow: float (0..1 wind-up glow), hit: int, beat: Beat,
## beat_ms: float, beat_len_ms: float, beat_u: float} at attack time `t_ms`.
## `hit` is the hit this pose belongs to (its wind-up, motion, contact, recoil or the walk home
## after the last hit), -1 before the clock starts. The beat keys only describe the spans the
## pose already follows; they never change pose, approach or glow.
static func sample(hits: Array, t_ms: float, v: CombatVisuals) -> Dictionary:
	if hits.is_empty() or t_ms < 0.0:
		return _open(_pose(Pose.IDLE, 0.0, 0.0), Beat.BEFORE, 0.0)
	var rest := 0.0
	var hold_from := 0.0
	for i: int in hits.size():
		var hit: Dictionary = hits[i]
		var impact := float(hit.at_ms)
		var approach_ms := maxf(1.0, float(hit.approach_ms))
		var start := motion_start(hits, i, v)
		var lunge_start := maxf(impact - approach_ms, hold_from)
		var is_last := i == hits.size() - 1
		if t_ms < start:
			return _beat(_pose(Pose.WINDUP, rest, _ramp(t_ms, hold_from, start), i), Beat.WINDUP, t_ms,
					hold_from, start)

		if int(hit.kind) == AttackHitData.Kind.GROUND:
			var slam_end := start + float(v.slam_hold_ms)
			if not is_last:
				slam_end = minf(slam_end, motion_start(hits, i + 1, v))
			if t_ms < slam_end:
				return _beat(_pose(Pose.SLAM, rest, 1.0 - _ramp(t_ms, start, slam_end), i), Beat.SLAM, t_ms,
						start, slam_end)
			if is_last:
				var back_from := maxf(slam_end, impact)
				if t_ms < back_from:
					return _beat(_pose(Pose.IDLE, rest, 0.0, i), Beat.GROUND_WAIT, t_ms, slam_end, back_from)
				var home_at := back_from + float(v.return_ms)
				var walked := _pose(Pose.IDLE, lerpf(rest, 0.0, _smooth(_ramp(t_ms, back_from, home_at))), 0.0, i)
				if t_ms < home_at:
					return _beat(walked, Beat.RETURN, t_ms, back_from, home_at)
				return _open(walked, Beat.AFTER, t_ms - home_at)
			hold_from = slam_end
			continue

		if is_ranged(hit):
			var shoot_end := start + float(v.shoot_hold_ms)
			if not is_last:
				shoot_end = minf(shoot_end, motion_start(hits, i + 1, v))
			if t_ms < shoot_end:
				return _beat(_pose(Pose.CONTACT, rest, 1.0 - _ramp(t_ms, start, shoot_end), i), Beat.SHOOT, t_ms,
						start, shoot_end)
			if is_last:
				var landed_at := maxf(shoot_end, impact)
				if t_ms < landed_at:
					return _beat(_pose(Pose.IDLE, rest, 0.0, i), Beat.FLIGHT, t_ms, shoot_end, landed_at)
				var home_at := landed_at + (float(v.return_ms) if rest > 0.0 else 0.0)
				var walked := _pose(Pose.IDLE, lerpf(rest, 0.0, _smooth(_ramp(t_ms, landed_at, home_at))), 0.0, i)
				if t_ms < home_at:
					return _beat(walked, Beat.RETURN, t_ms, landed_at, home_at)
				return _open(walked, Beat.AFTER, t_ms - home_at)
			hold_from = shoot_end
			continue

		var from := rest
		# A false start that runs past the lunge start (squeezed by the previous hit) delays it.
		var lunge_from := lunge_start
		if bool(hit.feint):
			var portion := float(v.feint_portion_percent) / 100.0
			var feint_end := start + approach_ms * portion
			if t_ms < feint_end:
				var u := (t_ms - start) / approach_ms
				return _beat(_pose(Pose.LUNGE, rest + (1.0 - rest) * u * u, 1.0 - u, i), Beat.FEINT_START, t_ms,
						start, feint_end, u)
			from = rest + (1.0 - rest) * portion * portion
			if t_ms < lunge_start:
				return _beat(_pose(Pose.WINDUP, from, _ramp(t_ms, feint_end, lunge_start), i), Beat.FEINT_HOLD, t_ms,
						feint_end, lunge_start)
			lunge_from = maxf(lunge_start, feint_end)
		if t_ms < impact:
			var u := clampf((t_ms - lunge_start) / maxf(1.0, impact - lunge_start), 0.0, 1.0)
			return _beat(_pose(Pose.LUNGE, from + (1.0 - from) * u * u, 1.0 - u, i), Beat.LUNGE, t_ms, lunge_from,
					impact, u)

		var close := float(hit.get("close_ms", 0.0))
		if is_last:
			# Past the close time: the hit lands on the first frame after it, then its hurt freeze.
			var hold_end := impact + maxf(float(v.contact_hold_ms), close + float(v.contact_after_close_ms))
			if t_ms < hold_end:
				return _beat(_pose(Pose.CONTACT, 1.0, 0.0, i), Beat.CONTACT, t_ms, impact, hold_end)
			var home_at := hold_end + float(v.return_ms)
			var back := _smooth(_ramp(t_ms, hold_end, home_at))
			if t_ms < home_at:
				return _beat(_pose(Pose.IDLE, 1.0 - back, 0.0, i), Beat.RETURN, t_ms, hold_end, home_at)
			return _open(_pose(Pose.IDLE, 1.0 - back, 0.0, i), Beat.AFTER, t_ms - home_at)

		var available := maxf(0.0, motion_start(hits, i + 1, v) - impact)
		var hold := minf(maxf(float(v.contact_hold_ms), close), maxf(0.0, available - float(v.recoil_min_ms)))
		var recoil := minf(float(v.recoil_ms), available - hold)
		var recoiled := 1.0 - float(v.recoil_percent) / 100.0
		if t_ms < impact + hold:
			return _beat(_pose(Pose.CONTACT, 1.0, 0.0, i), Beat.CONTACT, t_ms, impact, impact + hold)
		if t_ms < impact + hold + recoil:
			var r := _ramp(t_ms, impact + hold, impact + hold + recoil)
			return _beat(_pose(Pose.IDLE, lerpf(1.0, recoiled, 1.0 - (1.0 - r) * (1.0 - r)), 0.0, i), Beat.RECOIL,
					t_ms, impact + hold, impact + hold + recoil)
		rest = recoiled
		hold_from = impact + hold + recoil
	return _open(_pose(Pose.IDLE, 0.0, 0.0), Beat.AFTER, 0.0)


## Moments where something starts, in attack time: [{at_ms, type, hit}], type is CUE_LUNGE,
## CUE_FEINT, CUE_SLAM or CUE_SHOOT. Used for the telegraph flash, the lunge, slam and throw
## sounds and the wave.
static func cues(hits: Array, v: CombatVisuals) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for i: int in hits.size():
		var hit: Dictionary = hits[i]
		var lunge_start := float(hit.at_ms) - float(hit.approach_ms)
		if i > 0:
			lunge_start = maxf(lunge_start, float((hits[i - 1] as Dictionary).at_ms))
		lunge_start = maxf(lunge_start, 0.0)
		if int(hit.kind) == AttackHitData.Kind.GROUND:
			list.append({"at_ms": lunge_start, "type": CUE_SLAM, "hit": i})
			continue
		if is_ranged(hit):
			list.append({"at_ms": lunge_start, "type": CUE_SHOOT, "hit": i})
			continue
		if bool(hit.feint):
			list.append({"at_ms": motion_start(hits, i, v), "type": CUE_FEINT, "hit": i})
		list.append({"at_ms": lunge_start, "type": CUE_LUNGE, "hit": i})
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.at_ms) < float(b.at_ms))
	return list


## A copy of `hits` with `close_ms` set on each hit: the largest late window edge among that hit's
## prompts plus `latency_ms`, in milliseconds after impact.
static func with_close_times(hits: Array, prompts: Array, latency_ms: int) -> Array:
	var late_us: Dictionary = {}
	for p: Dictionary in prompts:
		for action: int in (p.windows as Dictionary):
			var edge := int((p.windows[action] as Array)[1])
			var h := int(p.hit)
			late_us[h] = maxi(int(late_us.get(h, edge)), edge)
	var list: Array = []
	for i: int in hits.size():
		var hit: Dictionary = (hits[i] as Dictionary).duplicate()
		hit["close_ms"] = float(int(late_us.get(i, 0))) / 1000.0 + float(latency_ms)
		list.append(hit)
	return list


## Copies each hit's presentation-only data from the attack's file into `hits` (engine-declared
## hit dictionaries, matched by their `index`): the animation prefix (`anim`), whether it throws a
## projectile (`ranged`) and its ground look (`ground_look`). The engine never sends these.
static func add_hit_data(hits: Array, attack: EnemyAttackData) -> void:
	if attack == null:
		return
	for hit: Dictionary in hits:
		var index := int(hit.get("index", -1))
		if index >= 0 and index < attack.hits.size() and attack.hits[index] != null:
			var data: AttackHitData = attack.hits[index]
			hit["anim"] = data.anim
			hit["ranged"] = data.projectile != null
			hit["ground_look"] = data.ground_look


## When the visible motion for hit `i` starts (feint false start, lunge, slam or throw), in attack ms.
static func motion_start(hits: Array, i: int, v: CombatVisuals) -> float:
	var hit: Dictionary = hits[i]
	var start := float(hit.at_ms) - float(hit.approach_ms)
	if AttackHitData.is_strike(int(hit.kind)) and bool(hit.feint) and not is_ranged(hit):
		start -= float(v.feint_lead_ms)
	if i > 0:
		start = maxf(start, float((hits[i - 1] as Dictionary).at_ms))
	return maxf(start, 0.0)


## True for a strike (normal, rend or sweep) that throws a projectile instead of lunging.
static func is_ranged(hit: Dictionary) -> bool:
	return bool(hit.get("ranged", false)) and AttackHitData.is_strike(int(hit.kind))


static func _ramp(t: float, from: float, to: float) -> float:
	if to <= from:
		return 1.0
	return clampf((t - from) / (to - from), 0.0, 1.0)


static func _smooth(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


static func _pose(pose: Pose, approach: float, glow: float, hit: int = -1) -> Dictionary:
	return {"pose": pose, "approach": clampf(approach, 0.0, 1.0), "glow": clampf(glow, 0.0, 1.0), "hit": hit}


## `s` with the beat keys of a beat spanning [from, to) in attack ms, at `t`. `u` is the beat's
## progress; below 0 it is the share of the span already played.
static func _beat(s: Dictionary, beat: Beat, t: float, from: float, to: float, u: float = -1.0) -> Dictionary:
	s["beat"] = beat
	s["beat_ms"] = maxf(0.0, t - from)
	s["beat_len_ms"] = maxf(0.0, to - from)
	s["beat_u"] = clampf(u if u >= 0.0 else _ramp(t, from, to), 0.0, 1.0)
	return s


## `s` with the keys of an open beat (no end), `elapsed` attack ms into it.
static func _open(s: Dictionary, beat: Beat, elapsed: float) -> Dictionary:
	s["beat"] = beat
	s["beat_ms"] = maxf(0.0, elapsed)
	s["beat_len_ms"] = -1.0
	s["beat_u"] = 0.0
	return s
