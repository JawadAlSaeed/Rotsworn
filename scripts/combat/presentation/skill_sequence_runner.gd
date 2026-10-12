class_name SkillSequenceRunner
extends Node
## Plays one party skill on this machine (DESIGN.md 2.10 and 4.5): the user's press prompts, then
## the allies' follow-up prompts. Each press is PERFECT, GOOD, or a MISS when the window passes;
## the ring shows the GOOD and PERFECT zones osu-style (RingLayer).
##
## On a "skill" timed_sequence_declared the controller calls start(). The AttackClock starts at
## once (the press times in the data leave room for the ring). A ring closes on the presser at each
## prompt's moment; presses of the skill button are judged at once by a DefenseJudge (the same
## pure judge as defence, with PRESS windows), and released results go to the engine as
## resolve_prompts. Feedback comes from the judge at press time; the engine's events for a result
## (damage, statuses, healing...) are applied at that prompt's contact moment, so numbers appear
## with the strike. Everything from sequence_resolved on is handed back (finished) when the local
## animation is over.

## Everything from sequence_resolved on, to be played by the controller.
signal finished(tail: Array[Dictionary])
## Every judged press (a DefenseJudge.press() report), for statistics and the autoplay bot.
signal press_judged(action: int, report: Dictionary)

## A good (not perfect) press sounds quieter than a perfect one.
const GOOD_PRESS_VOLUME_DB: float = -6.0
## The press ring keeps shrinking past the target after the perfect moment, down to this radius.
const RING_MIN_RADIUS_PX: float = 4.0

var _submit: Callable
var _apply_now: Callable
var _mirror: CombatMirror
var _view: CombatView
var _hud: CombatHud
var _tuning: Tuning
var _visuals: CombatVisuals
var _options: CombatOptions
var _input: DefenseInput

var _active: bool = false
var _event: Dictionary = {}
var _seq: int = -1
var _actor: int = -1
var _prompts: Array = []
var _hits: Array = []
var _targets: Array[int] = []
var _hits_enemies: bool = false
var _ability: AbilityData
var _clock := AttackClock.new()
var _judge: DefenseJudge
var _latency_ms: int = 0
## Prompts sent to the engine, and prompts the engine voided (known before the mirror is).
var _sent: Dictionary = {}
var _voided: Dictionary = {}
## Contact effects and event batches waiting for their attack time: [{at_us, call}], in order.
var _scheduled: Array[Dictionary] = []
var _tail: Array[Dictionary] = []
var _tail_received: bool = false
## Follow-up allies who have stepped forward (id -> true).
var _ready_allies: Dictionary = {}


func setup(submit: Callable, apply_now: Callable, mirror: CombatMirror, view: CombatView, hud: CombatHud,
		tuning: Tuning, visuals: CombatVisuals, options: CombatOptions, input: DefenseInput) -> void:
	_submit = submit
	_apply_now = apply_now
	_mirror = mirror
	_view = view
	_hud = hud
	_tuning = tuning
	_visuals = visuals
	_options = options
	_input = input
	_input.pressed.connect(_on_pressed)


## Starts playing a skill timed_sequence_declared event (already applied to the mirror).
## `ability` is the skill's data (for its sound and target kind).
func start(event: Dictionary, ability: AbilityData) -> void:
	_event = event
	_ability = ability
	_seq = int(event.seq)
	_actor = int(event.source)
	_prompts = event.prompts
	_hits = event.hits
	_targets.assign(event.targets)
	_hits_enemies = ability != null and ability.targets_enemies()
	_latency_ms = PlayerSettings.latency_compensation_ms(_tuning)
	_judge = DefenseJudge.new(_tuning.whiff_lockout_ms, _latency_ms, _tuning.press_reach_back_max_ms,
			_tuning.late_press_report_ms)
	_judge.set_prompts(_prompts)
	_clock = AttackClock.new()
	_clock.start(Time.get_ticks_usec())
	_sent.clear()
	_voided.clear()
	_scheduled.clear()
	_tail.clear()
	_tail_received = false
	_ready_allies.clear()
	_active = true
	_input.arm_press()
	var actor_name := String(_mirror.fighter(_actor).get("display_name", "?")).to_upper()
	_hud.show_banner("%s: %s" % [actor_name, String(event.get("name", "?"))], HudStyle.GOLD)
	for id: int in _strikers():
		var v := _view.fighter(id)
		if v == null:
			continue
		v.set_pose(FighterView.CharPose.READY)
		if _hits_enemies and not _targets.is_empty():
			v.move_body(_approach_offset(id), float(_tuning.action_dash_ms) / 1000.0, Tween.TRANS_QUAD, Tween.EASE_OUT)


## True between start() and the hand-back.
func is_active() -> bool:
	return _active


## True while presses are being judged.
func is_defending() -> bool:
	return _active and _clock.is_started()


## Current skill time in microseconds.
func attack_time_us() -> int:
	return _clock.attack_time_us(Time.get_ticks_usec()) if _clock.is_started() else 0


func is_clock_paused() -> bool:
	return _clock.is_started() and _clock.is_paused(Time.get_ticks_usec())


## The lag compensation the current judge uses.
func latency_us() -> int:
	return _latency_ms * 1000


## True if this prompt can still be answered (not sent, not voided, and for a follow-up, a
## press it needs was good or is still pending).
func is_prompt_open(idx: int) -> bool:
	if not _active or idx < 0 or idx >= _prompts.size():
		return false
	return not _sent.has(idx) and not _voided.has(idx)


func _process(_delta: float) -> void:
	if not _active:
		return
	var t := attack_time_us()
	_fire_scheduled(t)
	_expire(t)
	_release(t)
	_update_rings(t)
	_update_allies(t)
	_update_lock(t)
	_check_finish(t)


# --- presses ----------------------------------------------------------------------------------

func _on_pressed(action: int, stamp_us: int, previous_pump_us: int, _device: int) -> void:
	if not _active or action != Defense.Outcome.PRESS:
		return
	if _clock.is_paused(stamp_us):
		return
	var t := _clock.attack_time_us(stamp_us)
	var earliest := -1
	if previous_pump_us > 0 and previous_pump_us < stamp_us:
		var e := _clock.attack_time_us(previous_pump_us)
		if e >= 0:
			earliest = e
	var report := _judge.press(action, t, earliest)
	var answered: Array[int] = []
	for idx: int in report.prompts:
		if is_prompt_open(idx):
			answered.append(idx)
	if int(report.result) == DefenseJudge.Result.SUCCESS and answered.is_empty():
		report.result = DefenseJudge.Result.DONE
	_expire(t)
	# Not recorded in the F1 defence statistics: those are for defence timing only.
	press_judged.emit(action, report)
	match int(report.result):
		DefenseJudge.Result.SUCCESS:
			var impact_us := int((_hits[int(report.hit)] as Dictionary).at_ms) * 1000
			var perfect := int(report.outcome) == Defense.Outcome.PRESS_PERFECT
			_schedule(maxi(t, impact_us), _on_good_press.bind(answered, int(report.offset_us), perfect))
		DefenseJudge.Result.WHIFF:
			_on_whiff(report)
		DefenseJudge.Result.LOCKED:
			Sfx.play("locked", _visuals.locked_click_volume_db)
	_release(t)


## A good or perfect press reaches its contact moment.
func _on_good_press(idxs: Array[int], offset_us: int, perfect: bool) -> void:
	Sfx.play("skill_press", 0.0 if perfect else GOOD_PRESS_VOLUME_DB)
	if perfect:
		_clock.pause_for(Time.get_ticks_usec(), _tuning.hitstop_press_ms * 1000)
	var text := "PERFECT" if perfect else "GOOD"
	if _options.timing_readout:
		text += " " + HudStyle.signed_ms(roundi(float(offset_us) / 1000.0))
	var who: Array[int] = []
	for idx: int in idxs:
		who.append(int((_prompts[idx] as Dictionary).character))
	_hud.popup(text, _focus_head(who), HudStyle.GOLD if perfect else HudStyle.TEXT)
	_strike(idxs, true)


func _on_whiff(report: Dictionary) -> void:
	Sfx.play("whiff")
	var text := "EARLY" if int(report.reason) == DefenseJudge.Reason.EARLY else "LATE"
	var color := HudStyle.EARLY if text == "EARLY" else HudStyle.LATE
	if _options.timing_readout and int(report.hit) >= 0:
		text += " " + HudStyle.signed_ms(roundi(float(report.offset_us) / 1000.0))
	var who: Array[int] = []
	var hit := int(report.hit)
	for p: Dictionary in _prompts:
		if int(p.hit) == hit:
			who.append(int(p.character))
	_hud.popup(text, _focus_head(who if not who.is_empty() else [_actor]), color)


## Prompts whose window closed unanswered: the hit lands without the bonus (a follow-up does
## nothing).
func _expire(t: int) -> void:
	var expired := _judge.advance(t)
	var strikes: Array[int] = []
	for idx: int in expired:
		if not is_prompt_open(idx):
			continue
		var prompt: Dictionary = _prompts[idx]
		var v := _view.fighter(int(prompt.character))
		if v != null:
			_hud.popup("MISS", v.head_position(), HudStyle.MISS)
		if String(prompt.role) != CombatEngine.ROLE_FOLLOW_UP:
			strikes.append(idx)
	if not strikes.is_empty():
		_strike(strikes, false)


## Sends the judge's released results to the engine. Its events are applied at the contact
## moment of the last prompt in the batch (now for misses, at impact for early presses).
func _release(t: int) -> void:
	if _judge == null:
		return
	var ready := _judge.pop_ready()
	if ready.is_empty():
		return
	var results: Array[Dictionary] = []
	var show_at := t
	for r: Dictionary in ready:
		var idx := int(r.prompt)
		if not is_prompt_open(idx):
			continue
		_sent[idx] = true
		results.append(CombatCommands.prompt_result(idx, int(r.outcome), int(r.offset_us)))
		show_at = maxi(show_at, int((_prompts[idx] as Dictionary).at_ms) * 1000 if bool(r.pressed) else t)
	if results.is_empty():
		return
	var events: Array[Dictionary] = _submit.call(CombatCommands.resolve_prompts(_seq, results))
	for ev: Dictionary in events:
		if String(ev.get("type", "")) == "prompts_voided":
			for idx: int in ev.get("prompts", []):
				_voided[int(idx)] = true
			_judge.void_prompts(ev.get("prompts", []) as Array)
	_schedule(show_at, _apply_batch.bind(events))


func _apply_batch(events: Array[Dictionary]) -> void:
	var in_tail := _tail_received
	for ev: Dictionary in events:
		var type := String(ev.get("type", ""))
		if type == "sequence_resolved":
			in_tail = true
			_tail_received = true
		# Practice toggles are not part of any animation: apply them at once even in the tail.
		if in_tail and type != "practice_changed":
			_tail.append(ev)
		else:
			_apply_now.call(ev)


# --- animation --------------------------------------------------------------------------------

## The strike of these prompts' characters: a lunge and a slash on the target for a damaging
## skill (or a follow-up), a flash on the ally target for a support skill.
func _strike(idxs: Array[int], good: bool) -> void:
	var lunge_s := float(_visuals.skill_lunge_ms) / 1000.0
	var target := _first_target()
	for i: int in idxs.size():
		var prompt: Dictionary = _prompts[idxs[i]]
		var id := int(prompt.character)
		var v := _view.fighter(id)
		if v == null or not _mirror.is_alive(id):
			continue
		var follow_up := String(prompt.role) == CombatEngine.ROLE_FOLLOW_UP
		v.play_pose(FighterView.CharPose.STRIKE, _visuals.skill_lunge_ms * 3)
		if _hits_enemies and target >= 0:
			var enemy := _view.fighter(target)
			v.move_body(_view.strike_point(target) - v.position, lunge_s, Tween.TRANS_QUAD, Tween.EASE_IN)
			if enemy != null:
				_view.spawn_slash(enemy.centre_position(), i % 2 == 0, 1.0 if good else 0.6, i * _visuals.team_slash_gap_ms)
			_view.camera.shake(_visuals.shake_strike, _visuals.shake_strike_ms)
			Sfx.play("follow_up" if follow_up else (_ability.impact_sfx if _ability != null else "strike"))
			var back := Vector3.ZERO if follow_up else _approach_offset(id)
			get_tree().create_timer(lunge_s * 2.0).timeout.connect(_step_back.bind(id, back))
		else:
			Sfx.play(_ability.impact_sfx if _ability != null else "buff")
			for target_id: int in _targets:
				var tv := _view.fighter(target_id)
				if tv != null:
					tv.flash(_visuals.flash_ms * 2, HudStyle.GOLD if good else Color.WHITE, 0.8)


func _step_back(id: int, to: Vector3) -> void:
	if not _active:
		return
	var v := _view.fighter(id)
	if v != null:
		v.move_body(to, float(_visuals.skill_lunge_ms) / 1000.0 * 2.0, Tween.TRANS_QUAD, Tween.EASE_OUT)


## Follow-up allies step forward when their ring appears (and stay home if it was voided).
func _update_allies(t: int) -> void:
	var lead := _tuning.ring_lead_ms * 1000
	for idx: int in _prompts.size():
		var prompt: Dictionary = _prompts[idx]
		if String(prompt.role) != CombatEngine.ROLE_FOLLOW_UP:
			continue
		var id := int(prompt.character)
		if _ready_allies.has(id) or _voided.has(idx) or t < int(prompt.at_ms) * 1000 - lead:
			continue
		_ready_allies[id] = true
		var v := _view.fighter(id)
		if v != null and _mirror.is_alive(id):
			v.set_pose(FighterView.CharPose.READY)
			v.move_body(_approach_offset(id) * 0.5, float(_tuning.action_dash_ms) / 1000.0, Tween.TRANS_QUAD, Tween.EASE_OUT)


## osu-style press rings: a faint target circle, the GOOD band and the gold PERFECT band (the
## press windows drawn at the ring's shrink speed), and the ring itself, which reaches the target
## circle at the perfect moment and turns gold while it is inside the PERFECT band.
func _update_rings(t: int) -> void:
	var rings: Array[Dictionary] = []
	var lead := maxi(1, _tuning.ring_lead_ms * 1000)
	for idx: int in _prompts.size():
		var prompt: Dictionary = _prompts[idx]
		var at := int(prompt.at_ms) * 1000
		var windows: Dictionary = prompt.windows
		var good: Array = windows.get(Defense.Outcome.PRESS, [0, 0])
		var perfect: Array = windows.get(Defense.Outcome.PRESS_PERFECT, good)
		var rel := t - at
		if rel < -lead or rel > int(good[1]) + latency_us() or not is_prompt_open(idx):
			continue
		var v := _view.fighter(int(prompt.character))
		if v == null:
			continue
		var follow_up := String(prompt.role) == CombatEngine.ROLE_FOLLOW_UP
		var color := HudStyle.JUMP if follow_up else HudStyle.TEXT
		if rel >= int(perfect[0]) and rel <= int(perfect[1]):
			color = HudStyle.GOLD
		rings.append({
			"pos": _view.screen_position(v.centre_position()),
			"radius": _ring_radius(rel, lead),
			"color": color,
			"label": "FOLLOW-UP" if follow_up else "PRESS",
			"target_radius": _visuals.press_ring_end_radius_px,
			"target_color": _visuals.press_target_color,
			"bands": [_band(good, lead, _visuals.press_good_band_color),
					_band(perfect, lead, _visuals.press_perfect_band_color)],
		})
	_hud.set_rings(rings)


## Ring radius `rel_us` from the perfect moment: start radius ring_lead_ms before, the target
## circle at 0, still shrinking after.
func _ring_radius(rel_us: int, lead_us: int) -> float:
	var span := _visuals.press_ring_start_radius_px - _visuals.press_ring_end_radius_px
	return maxf(RING_MIN_RADIUS_PX, _visuals.press_ring_end_radius_px - span * float(rel_us) / float(lead_us))


## The ring of radii the shrinking ring passes through during a window [early_us, late_us].
func _band(edges: Array, lead_us: int, color: Color) -> Dictionary:
	var outer := _ring_radius(int(edges[0]), lead_us)
	var inner := _ring_radius(int(edges[1]), lead_us)
	return {"radius": (outer + inner) * 0.5, "width": outer - inner, "color": color}


func _update_lock(t: int) -> void:
	if _judge.is_locked_out(t):
		_hud.set_lock(true, _view.home_of(_actor))
	else:
		_hud.set_lock(false)


## Hands the tail back once every prompt is done and the last strike has played out.
func _check_finish(t: int) -> void:
	if not _tail_received or not _scheduled.is_empty() or _clock.is_paused(Time.get_ticks_usec()):
		return
	var last_us := 0
	for idx: int in _prompts.size():
		if not _voided.has(idx):
			last_us = maxi(last_us, int((_prompts[idx] as Dictionary).at_ms) * 1000)
	if t < last_us + _tuning.skill_recover_ms * 1000:
		return
	_hand_back()


func _hand_back() -> void:
	_active = false
	_input.disarm()
	_hud.hide_banner()
	_hud.set_rings([])
	_hud.set_lock(false)
	var return_s := float(_tuning.action_return_ms) / 1000.0
	for id: int in _mirror.party_ids:
		var v := _view.fighter(id)
		if v == null:
			continue
		v.set_pose(FighterView.CharPose.IDLE if _mirror.is_alive(id) else FighterView.CharPose.DOWN)
		v.move_body(Vector3.ZERO, return_s, Tween.TRANS_QUAD, Tween.EASE_OUT)
	var tail: Array[Dictionary] = _tail.duplicate()
	_tail.clear()
	finished.emit(tail)


# --- helpers ----------------------------------------------------------------------------------

func _schedule(at_us: int, call: Callable) -> void:
	var entry := {"at_us": at_us, "call": call}
	var i := _scheduled.size()
	while i > 0 and int(_scheduled[i - 1].at_us) > at_us:
		i -= 1
	_scheduled.insert(i, entry)


func _fire_scheduled(t: int) -> void:
	while not _scheduled.is_empty() and int(_scheduled[0].at_us) <= t:
		var entry: Dictionary = _scheduled.pop_front()
		(entry.call as Callable).call()


## The characters with press prompts (the user, or everyone for the team ultimate).
func _strikers() -> Array[int]:
	var list: Array[int] = []
	for p: Dictionary in _prompts:
		if String(p.role) == CombatEngine.ROLE_PRESS and not list.has(int(p.character)):
			list.append(int(p.character))
	return list


func _first_target() -> int:
	for id: int in _targets:
		if _mirror.is_alive(id) and not _mirror.party_ids.has(id):
			return id
	return -1


## Where a striker waits between hits: part of the way to the strike point.
func _approach_offset(id: int) -> Vector3:
	var target := _first_target()
	var v := _view.fighter(id)
	if target < 0 or v == null:
		return Vector3.ZERO
	return (_view.strike_point(target) - v.position) * _visuals.skill_approach_share


func _focus_head(ids: Array[int]) -> Vector3:
	var sum := Vector3.ZERO
	var count := 0
	for id: int in ids:
		var v := _view.fighter(id)
		if v != null:
			sum += v.head_position()
			count += 1
	return sum / float(maxi(1, count))
