class_name EnemyAnim
extends RefCounted
## Which clip cell an attacking enemy shows (DESIGN.md 5.5, cards #60, #63 and #69), picked from an
## EnemyChoreography.sample() beat. Pure and static: everything comes from the sample and attack
## time, so a hit-stop freezes the frames exactly like the motion, and contact[0] first shows at the
## impact moment the defence is judged against.
##
## Per beat: the wind-up coils (`windup`, or `windup_ground` before a ground hit) over the first
## enemy_windup_coil_ms of the wind-up, then shivers (`windup_hold`, a loop); a lunge and a feint's
## false start show `lunge` by lunge progress (so a feint looks like a lunge for its first part);
## `contact`, `slam` and `slam_recover` spread over their beat; `recoil` and `return` follow their
## progress; before and after the attack (and in any idle beat whose clip is missing) the enemy
## breathes its `idle` loop on attack time. Each hit tries its AttackHitData.anim prefix first
## (`<anim>_lunge` before `lunge`) and odd hits of a string their alternate limb (`lunge_b`); the
## view's ClipNames fallbacks resolve what the sheet lacks. An empty clip name means "show the
## sample's legacy pose", exactly as before phase 10.

const IDLE := "idle"
const WINDUP := "windup"
const WINDUP_GROUND := "windup_ground"
const WINDUP_HOLD := "windup_hold"
const LUNGE := "lunge"
const CONTACT := "contact"
const RECOIL := "recoil"
const RETURN := "return"
const SLAM := "slam"
const SLAM_RECOVER := "slam_recover"
## A hit's alternate limb (husk and king alternate claws): odd hits of a string try `<clip>_b`.
const ALT_SUFFIX := "_b"


## {clip: String, index: int} for sample `s` at attack time `t_ms`. `hits` are the attack's hit
## dictionaries (`kind`, and an optional `anim` prefix). `count` is a Callable(String) -> int
## giving how many cells a clip name plays after the fallbacks, 0 when none fits
## (FighterView.clip_count, or counter() in tests). The idle loop runs one cycle every
## `idle_period_ms`, shifted by `idle_phase_ms`. clip "" = the legacy pose `s.pose`.
static func pick(s: Dictionary, hits: Array, count: Callable, v: CombatVisuals, t_ms: float,
		idle_period_ms: float, idle_phase_ms: float) -> Dictionary:
	var hit_index := int(s.get("hit", -1))
	var hit: Dictionary = hits[hit_index] if hit_index >= 0 and hit_index < hits.size() else {}
	var prefix := String(hit.get("anim", ""))
	var alt := hit_index % 2 == 1
	var beat_ms := float(s.get("beat_ms", 0.0))
	var beat_len := float(s.get("beat_len_ms", -1.0))
	var beat_u := float(s.get("beat_u", 0.0))
	var idle := _idle(count, t_ms, idle_period_ms, idle_phase_ms)
	match int(s.get("beat", EnemyChoreography.Beat.AFTER)):
		EnemyChoreography.Beat.WINDUP:
			var ground := int(hit.get("kind", AttackHitData.Kind.NORMAL)) == AttackHitData.Kind.GROUND
			return _windup(name_for(WINDUP_GROUND if ground else WINDUP, prefix, alt),
					name_for(WINDUP_HOLD, prefix, alt), count, beat_ms, beat_len, v)
		EnemyChoreography.Beat.FEINT_HOLD:
			return _loop(name_for(WINDUP_HOLD, prefix, alt), count, beat_ms, float(v.enemy_windup_shiver_ms), {})
		EnemyChoreography.Beat.FEINT_START:
			# A feint stops short: it never shows the last ("arriving") lunge cell.
			var lunge := name_for(LUNGE, prefix, alt)
			var n := int(count.call(lunge))
			if n > 1:
				return {"clip": lunge, "index": mini(ClipMath.stretch(n, beat_u), n - 2)}
			return _at(lunge, count, beat_u, {})
		EnemyChoreography.Beat.LUNGE:
			return _at(name_for(LUNGE, prefix, alt), count, beat_u, {})
		EnemyChoreography.Beat.CONTACT:
			return _spread(name_for(CONTACT, prefix, alt), count, beat_ms, beat_len, {})
		EnemyChoreography.Beat.SLAM:
			return _spread(name_for(SLAM, prefix, alt), count, beat_ms, beat_len, {})
		EnemyChoreography.Beat.GROUND_WAIT:
			return _spread(name_for(SLAM_RECOVER, prefix, alt), count, beat_ms, beat_len, idle)
		EnemyChoreography.Beat.RECOIL:
			return _at(name_for(RECOIL, prefix, alt), count, beat_u, idle)
		EnemyChoreography.Beat.RETURN:
			# Ground-only attacks never leave home: no walking back in place.
			if float(s.get("approach", 0.0)) <= 0.0:
				return idle
			return _at(name_for(RETURN, prefix, alt), count, beat_u, idle)
	return idle


## The clip name a hit asks for: `<prefix>_<clip>`, with `_b` on an alternate hit. The fallbacks
## (ClipNames) drop the `_b`, then the prefix, when the sheet lacks them.
static func name_for(clip: String, prefix: String, alt: bool) -> String:
	var clip_name := clip + ALT_SUFFIX if alt else clip
	return clip_name if prefix.is_empty() else prefix + "_" + clip_name


## A Callable(String) -> int counting the cells a clip name plays on `clips` after the fallbacks,
## the way FighterView.clip_count does (for tests and tools).
static func counter(clips: SpriteClips) -> Callable:
	return func(clip: String) -> int: return ClipNames.cells(clips, clip).size()


## The coil over the first enemy_windup_coil_ms of the wind-up (never longer than the wind-up),
## then the shiver loop; with no shiver the coil holds its last cell. Nothing fits: legacy pose.
static func _windup(coil_name: String, hold_name: String, count: Callable, beat_ms: float,
		beat_len: float, v: CombatVisuals) -> Dictionary:
	var coil_len := minf(maxf(0.0, beat_len), float(v.enemy_windup_coil_ms))
	var n := int(count.call(coil_name))
	if beat_ms < coil_len:
		return {"clip": coil_name, "index": ClipMath.once(n, beat_ms, coil_len)} if n > 0 else _legacy()
	var held := {"clip": coil_name, "index": n - 1} if n > 0 else _legacy()
	return _loop(hold_name, count, beat_ms - coil_len, float(v.enemy_windup_shiver_ms), held)


## `clip` spread evenly over a beat of `beat_len` ms, `beat_ms` into it; `missing` without the clip.
static func _spread(clip: String, count: Callable, beat_ms: float, beat_len: float,
		missing: Dictionary) -> Dictionary:
	var n := int(count.call(clip))
	if n <= 0:
		return missing if not missing.is_empty() else _legacy()
	return {"clip": clip, "index": ClipMath.once(n, beat_ms, maxf(0.0, beat_len))}


## `clip` at progress `u` (0..1); `missing` without the clip.
static func _at(clip: String, count: Callable, u: float, missing: Dictionary) -> Dictionary:
	var n := int(count.call(clip))
	if n <= 0:
		return missing if not missing.is_empty() else _legacy()
	return {"clip": clip, "index": ClipMath.stretch(n, u)}


## `clip` looped, one cycle every `period_ms`, `t_ms` into it; `missing` without the clip.
static func _loop(clip: String, count: Callable, t_ms: float, period_ms: float,
		missing: Dictionary) -> Dictionary:
	var n := int(count.call(clip))
	if n <= 0:
		return missing if not missing.is_empty() else _legacy()
	return {"clip": clip, "index": ClipMath.loop(n, t_ms, period_ms)}


## The idle loop on attack time (the legacy pose when the sheet has no idle clip).
static func _idle(count: Callable, t_ms: float, period_ms: float, phase_ms: float) -> Dictionary:
	var n := int(count.call(IDLE))
	if n <= 0:
		return _legacy()
	return {"clip": IDLE, "index": ClipMath.loop(n, t_ms, period_ms, phase_ms)}


## Nothing fits: the caller shows the sample's legacy pose.
static func _legacy() -> Dictionary:
	return {"clip": "", "index": 0}
