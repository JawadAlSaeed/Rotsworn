class_name SkillSequenceRunner
extends Node
## Plays one party skill on this machine (DESIGN.md 2.10 and 4.5): the user's press prompts, then
## the allies' follow-up prompts. Each press is PERFECT, GOOD, or a MISS when the window passes;
## the ring shows the GOOD and PERFECT zones osu-style (RingLayer). Each press moment is its own
## ring at its own spot (PressNotes): a skill with several presses shows a numbered row of rings,
## closing left to right at the skill's own ring speed (ring_lead_percent).
##
## On a "skill" timed_sequence_declared the controller calls start(). The AttackClock starts at
## once (the press times in the data leave room for the ring). A ring closes on the presser at each
## prompt's moment; presses of the skill button are judged at once by a DefenseJudge (the same
## pure judge as defence, with PRESS windows), and released results go to the engine as
## resolve_prompts. In co-op each player presses for their own heroes (JudgeSet, DESIGN.md 9.1):
## the skill user's owner for the skill, each ally's owner for its follow-up, everyone for the team
## ultimate. Feedback comes from the judge at press time; the engine's events for a result
## (damage, statuses, healing...) are applied at that prompt's contact moment, so numbers appear
## with the strike. Everything from sequence_resolved on is handed back (finished) when the local
## animation is over.
##
## Online (DESIGN.md 9.2) this machine judges only its own player's prompts; the engine's answers
## to everyone's results arrive through take_events(), where other players' presses get their
## feedback. Event batches are applied in arrival order (never out of engine order).

## Everything from sequence_resolved on, to be played by the controller.
signal finished(tail: Array[Dictionary])
## Every judged press (a DefenseJudge.press() report), for statistics and the autoplay bot.
signal press_judged(action: int, report: Dictionary)
## start() ran for sequence `seq` (online: the client tells the host, DESIGN.md 9.2).
signal sequence_started(seq: int)

## A good (not perfect) press sounds quieter than a perfect one.
const GOOD_PRESS_VOLUME_DB: float = -6.0
## The press ring keeps shrinking past the target after the perfect moment, down to this radius.
const RING_MIN_RADIUS_PX: float = 4.0
## Follow-up allies step this share of the way to their strike point when their ring appears.
const FOLLOW_UP_STEP_SHARE: float = 0.5
## The clips a follow-up ally winds up and strikes with (they fall back to the backhand).
const FOLLOW_UP_WINDUPS: PackedStringArray = ["follow_up_windup"]
const FOLLOW_UP_STRIKES: PackedStringArray = ["follow_up"]
## A follow-up ally hops in and out of their spot with this clip.
const LEAP_CLIP: String = "leap"
## A bolt's trail copies: the first one this bright, each next one fainter.
const BOLT_TRAIL_ALPHA: float = 0.45

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
## A spell (AbilityData.projectile, card #81): the caster stays where they stand and a bolt flies
## to the target for each of their presses.
var _ranged: bool = false
## Card #166: press prompt idx -> skill time (us) its bolt left the staff (the press, or the end
## of the press window when none came), and -> skill time it lands (the strike belongs to that).
var _bolt_release: Dictionary = {}
var _bolt_landing: Dictionary = {}
var _clock := AttackClock.new()
## Who owns each perfect press's freeze on the shared clock (card #180, see FreezeLedger).
var _freezes := FreezeLedger.new()
var _judges: JudgeSet
var _roster: PlayerRoster = PlayerRoster.solo(0)
## Party member id -> player index (empty: everyone is player 0).
var _owners: Dictionary = {}
var _latency_ms: int = 0
## Prompts sent to the engine, and prompts the engine voided (known before the mirror is).
var _sent: Dictionary = {}
var _voided: Dictionary = {}
## Contact effects and event batches waiting for their attack time: [{at_us, call}], in order.
var _scheduled: Array[Dictionary] = []
var _tail: Array[Dictionary] = []
var _tail_received: bool = false
## Event batches waiting to be applied, in engine order: [{at_us, events}] (at_us never decreases).
var _inbox: Array[Dictionary] = []
var _inbox_at_us: int = 0
## Follow-up allies who have stepped forward (id -> true).
var _ready_allies: Dictionary = {}
## Contact moment (skill time, us) of each prompt that struck (prompt idx -> us), and prompts that
## will never strike (a missed or voided follow-up), for the wind-up and strike frames.
var _contacts: Dictionary = {}
var _no_strike: Dictionary = {}
## Each animated hero's prompts in press order (id -> Array[int] of prompt idx).
var _anim_prompts: Dictionary = {}
## A Run attempt (escape ability) saw its hero escape (else it failed).
var _escaped_seen: bool = false
## The skill's press moments (PressNotes.notes), the middle of their row (where the strikers
## stand, chest height), how long before each press its ring appears, and the ring colour.
var _notes: Array[Dictionary] = []
var _note_anchor: Vector3 = Vector3.ZERO
var _press_lead_us: int = 1
var _ring_color: Color = HudStyle.TEXT


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


## Who plays which hero (co-op). `owners` maps a party member id to its player.
func set_players(roster: PlayerRoster, owners: Dictionary) -> void:
	_roster = roster
	_owners = owners


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
	_ranged = ability != null and ability.projectile != null
	_bolt_release.clear()
	_bolt_landing.clear()
	_latency_ms = PlayerSettings.base_latency_compensation_ms(_tuning)
	_judges = JudgeSet.new(_tuning.whiff_lockout_ms, _latency_ms, _tuning.press_reach_back_max_ms,
			_tuning.late_press_report_ms)
	# Online, other machines judge their own players' prompts.
	var only: Array[int] = []
	if _roster.is_online():
		only = _roster.local_players()
	_press_lead_us = maxi(1, (ability.ring_lead_ms(_tuning) if ability != null else _tuning.ring_lead_ms) * 1000)
	# The judge spends a ring on an early press only once that ring is on screen (one press per
	# ring, DESIGN.md 2.10): tell it how early each prompt's ring shows.
	var judged: Array = []
	for prompt: Dictionary in _prompts:
		var copy := prompt.duplicate()
		var follow_up := String(prompt.role) == CombatEngine.ROLE_FOLLOW_UP
		copy["ring_lead_us"] = maxi(1, _tuning.ring_lead_ms * 1000) if follow_up else _press_lead_us
		judged.append(copy)
	_judges.set_prompts(judged, _owners, only)
	_inbox.clear()
	_inbox_at_us = 0
	_clock = AttackClock.new()
	_clock.start(Time.get_ticks_usec())
	_freezes.clear()
	_sent.clear()
	_voided.clear()
	_scheduled.clear()
	_tail.clear()
	_tail_received = false
	_ready_allies.clear()
	_contacts.clear()
	_no_strike.clear()
	_anim_prompts = _prompts_by_hero()
	_escaped_seen = false
	_notes = PressNotes.notes(_prompts)
	_ring_color = ability.ring_color if ability != null else HudStyle.TEXT
	_note_anchor = _strikers_stand_point()
	var aim := _first_target()
	if aim < 0 and not _targets.is_empty():
		aim = _targets[0]
	var stand := Vector3(_note_anchor.x, 0.0, _note_anchor.z)
	# With follow-ups the whole sequence is framed at once (strikers, target, every ally who will
	# press), so the camera never moves while a ring is up and nobody is off screen (card #49).
	if not _follow_up_allies().is_empty():
		_frame_skill()
	else:
		_view.camera.shot_strike(stand, _view.home_of(aim) if aim >= 0 else stand, ability != null and ability.team_ultimate)
	_active = true
	_input.arm_press()
	var actor_name := String(_mirror.fighter(_actor).get("display_name", "?")).to_upper()
	_hud.show_banner(String(event.get("name", "?")), HudStyle.GOLD, actor_name)
	if ability != null and ability.team_ultimate:
		Sfx.play("ultimate_start")
	_hud.set_skill_pressing(true)
	# A leftover draw or hurt must never hide the driven skill frames (cancel rule, DESIGN.md 5.5).
	for id: int in _follow_up_allies():
		var ally := _view.fighter(id)
		if ally != null:
			ally.clear_timed_pose(FighterView.PRIO_BIG)
	for id: int in _strikers():
		var v := _view.fighter(id)
		if v == null:
			continue
		v.clear_timed_pose(FighterView.PRIO_BIG)
		v.set_pose(FighterView.CharPose.READY)
		if _hits_enemies and not _targets.is_empty() and not _ranged:
			v.move_body(_approach_offset(id), float(_tuning.action_dash_ms) / 1000.0, Tween.TRANS_QUAD, Tween.EASE_OUT)
	sequence_started.emit(_seq)


## The sequence being played (-1 before the first).
func current_seq() -> int:
	return _seq


## Events of this sequence that did not come back from this machine's own submit (see
## TimedSequenceRunner.take_events). Another player's good press strikes at its moment, a missed
## one shows MISS.
func take_events(events: Array[Dictionary]) -> void:
	if not _active:
		return
	var t := attack_time_us()
	var show_at := t
	for ev: Dictionary in events:
		var type := String(ev.get("type", ""))
		if type == "prompts_voided":
			_void(ev.get("prompts", []) as Array)
		if type != "prompt_resolved" or int(ev.get("seq", -1)) != _seq:
			continue
		var idx := int(ev.prompt)
		var outcome := int(ev.outcome)
		var at_us := int((_prompts[idx] as Dictionary).at_ms) * 1000
		if _judges.player_of_prompt(idx) >= 0:
			# This machine's own press: its feedback already played; numbers show at its moment.
			if outcome != Defense.Outcome.NONE:
				show_at = maxi(show_at, int(_bolt_landing.get(idx, at_us)) if _is_cast(idx) else at_us)
			continue
		if not is_prompt_open(idx):
			continue
		_sent[idx] = true
		var list: Array[int] = [idx]
		if outcome == Defense.Outcome.NONE:
			if _is_cast(idx):
				# The bolt of a press that never came leaves now (its window closed on the other machine).
				_expire_remote(idx, t)
				show_at = maxi(show_at, int(_bolt_landing.get(idx, t)))
			else:
				_schedule(t, _expire_remote.bind(idx, t))
		else:
			var contact_us := maxi(t, at_us)
			_on_good_result(list, int(ev.get("offset_us", 0)), outcome == Defense.Outcome.PRESS_PERFECT, t, contact_us)
			show_at = maxi(show_at, int(_bolt_landing.get(idx, at_us)) if _is_cast(idx) else at_us)
	_push_batch(events, show_at)


func _push_batch(events: Array[Dictionary], at_us: int) -> void:
	if events.is_empty():
		return
	_inbox_at_us = maxi(_inbox_at_us, at_us)
	_inbox.append({"at_us": _inbox_at_us, "events": events})


## Applies the queued batches that are due, oldest first.
func _drain(t: int) -> void:
	while not _inbox.is_empty() and int(_inbox[0].at_us) <= t:
		_apply_batch((_inbox.pop_front() as Dictionary).events as Array[Dictionary])


## Another player missed a press: MISS, and the strike without the bonus (a follow-up ally hops
## home instead).
func _expire_remote(idx: int, contact_us: int) -> void:
	var prompt: Dictionary = _prompts[idx]
	var v := _view.fighter(int(prompt.character))
	if v != null:
		_hud.popup("MISS", v.head_position(), HudStyle.MISS)
	if String(prompt.role) != CombatEngine.ROLE_FOLLOW_UP:
		var list: Array[int] = [idx]
		_miss_strike(list, contact_us)
	else:
		_follow_up_off(idx)


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


## Holds the skill's animation clock for `ms` (a hit-stop on a killing blow, card #179). Nobody
## owns this freeze, so every player's presses are still judged as if it had not happened.
func hold(ms: int) -> void:
	if not _active or ms <= 0 or not _clock.is_started():
		return
	var now := Time.get_ticks_usec()
	_clock.pause_for(now, ms * 1000)
	_freezes.add(now, ms * 1000, [] as Array[int])


## The base lag compensation the current judges use (the smaller of the keyboard's and the pad's,
## DESIGN.md 3.2). Window edges drawn for the player use it too.
func latency_us() -> int:
	return _latency_ms * 1000


## How much more the device that made a press lags than the base (card #204).
func _extra_latency_ms(device: int) -> int:
	return PlayerSettings.latency_compensation_ms(_tuning, PlayerSettings.input_kind_of_device(device)) - _latency_ms


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
	_drain(t)
	_update_rings(t)
	_update_allies(t)
	_update_poses(t)
	_update_bolts(t)
	_update_lock(t)
	_check_finish(t)


# --- presses ----------------------------------------------------------------------------------

func _on_pressed(action: int, stamp_us: int, previous_pump_us: int, device: int) -> void:
	if not _active or action != Defense.Outcome.PRESS:
		return
	var player := _roster.player_of_device(device)
	if not _judges.players().has(player):
		return
	var t := _clock.attack_time_us(stamp_us)
	var earliest := -1
	if _clock.is_paused(stamp_us):
		# The owner's own tap inside their perfect-press freeze is a double tap: ignored. Another
		# player's press is judged as if the freeze had not happened (card #180).
		var shift := _freezes.press_shift_us(stamp_us, player)
		if shift == FreezeLedger.IGNORE:
			return
		t += shift
	elif previous_pump_us > 0 and previous_pump_us < stamp_us:
		var e := _clock.attack_time_us(previous_pump_us)
		if e >= 0:
			earliest = e
	var report := _judges.press(player, action, t, earliest, _extra_latency_ms(device))
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
			_on_good_result(answered, int(report.offset_us), perfect, t, maxi(t, impact_us))
		DefenseJudge.Result.WHIFF:
			_on_whiff(report, player)
		DefenseJudge.Result.LOCKED:
			Sfx.play("locked", _visuals.locked_click_volume_db)
	_release(t)


## A good or perfect press was judged at skill time `now_us`; its strike belongs at `contact_us`
## (the press, or the ring's moment if the press was early). A spell's bolt (card #166) instead
## leaves the staff now and the strike waits for it to land.
func _on_good_result(idxs: Array[int], offset_us: int, perfect: bool, now_us: int, contact_us: int) -> void:
	var casts: Array[int] = []
	var others: Array[int] = []
	for idx: int in idxs:
		if _is_cast(idx):
			casts.append(idx)
		else:
			others.append(idx)
	if not casts.is_empty():
		_press_feedback(casts, offset_us, perfect)
		_launch(casts, now_us, true, perfect)
	if not others.is_empty():
		_schedule(contact_us, _on_good_press.bind(others, offset_us, perfect, contact_us))


## A good or perfect press reaches its contact moment (`contact_us`, skill time).
func _on_good_press(idxs: Array[int], offset_us: int, perfect: bool, contact_us: int) -> void:
	_press_feedback(idxs, offset_us, perfect)
	if perfect:
		_press_freeze(idxs)
	_strike(idxs, true, contact_us, perfect)


## The press sound and the PERFECT / GOOD readout over the pressing hero.
func _press_feedback(idxs: Array[int], offset_us: int, perfect: bool) -> void:
	Sfx.play("skill_press", 0.0 if perfect else GOOD_PRESS_VOLUME_DB)
	var text := "PERFECT" if perfect else "GOOD"
	if _options.timing_readout:
		text += " " + HudStyle.signed_ms(roundi(float(offset_us) / 1000.0))
	var who: Array[int] = []
	for idx: int in idxs:
		who.append(int((_prompts[idx] as Dictionary).character))
	_hud.popup(text, _focus_head(who), HudStyle.GOLD if perfect else HudStyle.TEXT)


## The perfect press's hit-stop on the shared clock, owned by the presser (card #180).
func _press_freeze(idxs: Array[int]) -> void:
	var owners: Array[int] = []
	for idx: int in idxs:
		var player := int(_owners.get(int((_prompts[idx] as Dictionary).character), 0))
		if not owners.has(player):
			owners.append(player)
	var now := Time.get_ticks_usec()
	_clock.pause_for(now, _tuning.hitstop_press_ms * 1000)
	_freezes.add(now, _tuning.hitstop_press_ms * 1000, owners)


# --- spell bolts (card #166) ------------------------------------------------------------------

## True for a press prompt of a spell: its bolt leaves the staff at the press (SpellShot).
func _is_cast(idx: int) -> bool:
	return _ranged and idx >= 0 and idx < _prompts.size() \
			and String((_prompts[idx] as Dictionary).role) == CombatEngine.ROLE_PRESS


func _flight_us() -> int:
	return maxi(1, (_ability.projectile_flight_ms if _ability != null else 0) * 1000)


## These press prompts' bolts leave the staff now (`now_us`: the press, or the moment the judge
## found the window closed; never later than the window's end). The caster's strike frames start
## with the release; the strike (damage numbers, sparks, the perfect press's hit-stop) belongs to
## the landing. A press that never came is a miss whose bolt still goes, so the skill never stalls.
func _launch(idxs: Array[int], now_us: int, good: bool, perfect: bool) -> void:
	var landing := 0
	var fresh: Array[int] = []
	for idx: int in idxs:
		if _bolt_release.has(idx):
			continue
		var release := SpellShot.release_us(now_us, SpellShot.window_end_us(_prompts[idx] as Dictionary, latency_us()))
		_bolt_release[idx] = release
		_bolt_landing[idx] = SpellShot.landing_us(release, _flight_us())
		_contacts[idx] = release
		landing = maxi(landing, int(_bolt_landing[idx]))
		fresh.append(idx)
	if fresh.is_empty():
		return
	if _ability != null and _ability.projectile != null and not _ability.projectile.launch_sfx.is_empty():
		Sfx.play(_ability.projectile.launch_sfx)
	_schedule(landing, _on_bolt_lands.bind(fresh, good, perfect, landing))


## The bolt reached the target: the hit-stop of a perfect press, then the strike.
func _on_bolt_lands(idxs: Array[int], good: bool, perfect: bool, landing_us: int) -> void:
	if good and perfect:
		_press_freeze(idxs)
	_strike(idxs, good, landing_us, perfect)


## A press that came in time did not happen: the hit lands as a miss. A spell's bolt leaves now.
func _miss_strike(idxs: Array[int], now_us: int) -> void:
	var casts: Array[int] = []
	var others: Array[int] = []
	for idx: int in idxs:
		if _is_cast(idx):
			casts.append(idx)
		else:
			others.append(idx)
	if not casts.is_empty():
		_launch(casts, now_us, false, false)
	if not others.is_empty():
		_strike(others, false, now_us)


func _on_whiff(report: Dictionary, player: int) -> void:
	Sfx.play("whiff")
	var text := "EARLY" if int(report.reason) == DefenseJudge.Reason.EARLY else "LATE"
	var color := HudStyle.EARLY if text == "EARLY" else HudStyle.LATE
	if _options.timing_readout and int(report.hit) >= 0:
		text += " " + HudStyle.signed_ms(roundi(float(report.offset_us) / 1000.0))
	var who: Array[int] = []
	var hit := int(report.hit)
	for p: Dictionary in _prompts:
		if int(p.hit) == hit and _judges.player_of_prompt(int(p.idx)) == player:
			who.append(int(p.character))
	if who.is_empty():
		who = _heroes_of(player)
	_hud.popup(text, _focus_head(who if not who.is_empty() else [_actor]), color)


## Prompts whose window closed unanswered: the hit lands without the bonus (a follow-up does
## nothing).
func _expire(t: int) -> void:
	var expired := _judges.advance(t)
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
		else:
			_follow_up_off(idx)
	if not expired.is_empty():
		Sfx.play("skill_miss")
	if not strikes.is_empty():
		_miss_strike(strikes, t)


## Sends the judge's released results to the engine. Its events are applied at the contact
## moment of the last prompt in the batch (now for misses, at impact for early presses).
func _release(t: int) -> void:
	if _judges == null:
		return
	var ready := _judges.pop_ready()
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
		if _is_cast(idx):
			# A spell's numbers appear when its bolt lands (card #166).
			show_at = maxi(show_at, int(_bolt_landing.get(idx, t)))
		else:
			show_at = maxi(show_at, int((_prompts[idx] as Dictionary).at_ms) * 1000 if bool(r.pressed) else t)
	if results.is_empty():
		return
	var events: Array[Dictionary] = _submit.call(CombatCommands.resolve_prompts(_seq, results))
	for ev: Dictionary in events:
		if String(ev.get("type", "")) == "prompts_voided":
			_void(ev.get("prompts", []) as Array)
	_push_batch(events, show_at)


func _apply_batch(events: Array[Dictionary]) -> void:
	var in_tail := _tail_received
	for ev: Dictionary in events:
		var type := String(ev.get("type", ""))
		if type == "escaped":
			_escaped_seen = true
		if type == "sequence_resolved":
			if _ability != null and _ability.escape and not _escaped_seen:
				Sfx.play("escape_fail")
			in_tail = true
			_tail_received = true
		# Practice toggles are not part of any animation: apply them at once even in the tail.
		if in_tail and type != "practice_changed":
			_tail.append(ev)
		else:
			_apply_now.call(ev)


# --- animation --------------------------------------------------------------------------------

## The strike of these prompts' characters at `contact_us` (skill time): a lunge and a slash on the
## target for a damaging skill (or a follow-up), a flash on the ally target for a support skill.
## The strike frames come from _update_poses, on skill time, so the hit-stop holds them. The impact
## grows with the moment (card #179): a graze or good press is small, a perfect press medium, a
## hit of the Team Ultimate large (more shake, punch-in and sparks).
func _strike(idxs: Array[int], good: bool, contact_us: int, perfect: bool = false) -> void:
	var lunge_s := float(_visuals.skill_lunge_ms) / 1000.0
	var target := _first_target()
	var team := _ability != null and _ability.team_ultimate
	var shake := _visuals.shake_strike
	var punch := 0.0
	var spark_percent := 100
	if good and team:
		shake = _visuals.shake_ultimate_hit
		punch = _visuals.punch_ultimate_hit
		spark_percent = _visuals.spark_tier_large_percent
	elif good and perfect:
		shake = _visuals.shake_strike_perfect
		punch = _visuals.punch_strike_perfect
		spark_percent = _visuals.spark_tier_medium_percent
	for i: int in idxs.size():
		# A spell's strike frames started when its bolt left the staff (_launch).
		if not _is_cast(idxs[i]):
			_contacts[idxs[i]] = contact_us
		var prompt: Dictionary = _prompts[idxs[i]]
		var id := int(prompt.character)
		var v := _view.fighter(id)
		if v == null or not _mirror.is_alive(id):
			continue
		var follow_up := String(prompt.role) == CombatEngine.ROLE_FOLLOW_UP
		# A spell's own presses land as its bolt arrives: the caster stays put (follow-ups still run in).
		var cast := _ranged and not follow_up
		if _hits_enemies and target >= 0:
			var enemy := _view.fighter(target)
			if not cast:
				var strike_at := _view.strike_point(target)
				if team:
					# Card #65: each hero keeps part of the formation, so nobody hides behind another.
					strike_at += _view.team_spread_offset(id, _strikers())
				v.move_body(strike_at - v.position, lunge_s, Tween.TRANS_QUAD, Tween.EASE_IN)
			if enemy != null:
				if not cast:
					_view.spawn_slash(enemy.centre_position(), i % 2 == 0, 1.0 if good else 0.6, i * _visuals.team_slash_gap_ms)
				_view.spawn_sparks(enemy.centre_position(), CombatMath.percent(_visuals.sparks_per_strike, spark_percent),
						1.0 if good else 0.6, _ability.projectile.color if cast else _visuals.strike_spark_color)
			_view.camera.add_trauma(shake)
			if punch > 0.0:
				_view.camera.punch(punch, _visuals.punch_ms)
			if team and i == 0:
				_hud.screen_flash(HudStyle.GOLD, _visuals.screen_flash_ultimate)
			if _ability == null or not _ability.escape:
				Sfx.play("follow_up" if follow_up else (_ability.impact_sfx if _ability != null else "strike"))
			if follow_up:
				# Hop home only after the follow-up strike clip has played (plus a perfect press's
				# freeze), so its last cells are not cut off by the leap.
				var strike_s := float(_visuals.skill_strike_pose_ms + _tuning.hitstop_press_ms) / 1000.0
				get_tree().create_timer(maxf(lunge_s * 2.0, strike_s)).timeout.connect(_hop_home.bind(id))
			elif not cast:
				get_tree().create_timer(lunge_s * 2.0).timeout.connect(_step_back.bind(id, _approach_offset(id)))
		elif _ability == null or not _ability.escape:
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


## A follow-up ally hops back home (after their strike, or when their prompt is gone).
func _hop_home(id: int) -> void:
	if not _active:
		return
	var v := _view.fighter(id)
	if v == null or not _mirror.is_alive(id):
		return
	v.hop_body(Vector3.ZERO, float(_visuals.follow_up_hop_ms) / 1000.0, _visuals.follow_up_hop_height)
	v.play(LEAP_CLIP, _visuals.follow_up_hop_ms, FighterView.PRIO_REACT)


## The engine voided these prompts: no ring, no judging, and an ally who already hopped in for one
## hops home again.
func _void(idxs: Array) -> void:
	for idx: int in idxs:
		_voided[int(idx)] = true
		_follow_up_off(int(idx))
	_judges.void_prompts(idxs)


## Follow-up prompt `idx` will never strike (missed or voided): its ally stops winding up and, if
## they had hopped in, hops home.
func _follow_up_off(idx: int) -> void:
	if idx < 0 or idx >= _prompts.size() or _no_strike.has(idx):
		return
	var prompt: Dictionary = _prompts[idx]
	if String(prompt.role) != CombatEngine.ROLE_FOLLOW_UP:
		return
	_no_strike[idx] = true
	if _ready_allies.has(int(prompt.character)):
		_hop_home(int(prompt.character))


## Follow-up allies hop to their spot when their ring appears (and stay home if it was voided).
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
			Sfx.play("follow_up_ready")
			# Card #64: a hop in to the same half-step spot as before (so the framing is unchanged).
			v.hop_body(_follow_up_offset(id), float(_visuals.follow_up_hop_ms) / 1000.0, _visuals.follow_up_hop_height)
			v.play(LEAP_CLIP, _visuals.follow_up_hop_ms, FighterView.PRIO_REACT)


## Card #58: every striker and every ally who hopped in shows their wind-up and strike frames on
## skill time (SkillAnimPlan), so the perfect-press hit-stop holds the contact frame.
func _update_poses(t: int) -> void:
	var windup_us := _visuals.skill_windup_ms * 1000
	var strike_us := _visuals.skill_strike_pose_ms * 1000
	var gap_us := _visuals.skill_strike_min_ms * 1000
	for id: int in _anim_prompts:
		var v := _view.fighter(id)
		if v == null or not _mirror.is_alive(id) or bool(_mirror.fighter(id).get("escaped", false)):
			continue
		var at: Array[int] = []
		var contacts: Array[int] = []
		var follow_up := false
		for idx: int in _anim_prompts[id]:
			var prompt: Dictionary = _prompts[idx]
			follow_up = String(prompt.role) == CombatEngine.ROLE_FOLLOW_UP
			if _voided.has(idx) or _no_strike.has(idx):
				continue
			at.append(int(prompt.at_ms) * 1000)
			contacts.append(int(_contacts.get(idx, SkillAnimPlan.NO_CONTACT)))
		if follow_up and not _ready_allies.has(id):
			continue
		var pick: Dictionary
		if follow_up:
			pick = SkillAnimPlan.pick(at, contacts, FOLLOW_UP_WINDUPS, FOLLOW_UP_STRIKES, windup_us,
					strike_us, gap_us, t)
		elif _ability != null:
			pick = SkillAnimPlan.pick(at, contacts, _ability.windup_clips, _ability.strike_clips,
					windup_us * _ability.windup_percent / 100, strike_us, gap_us, t)
		else:
			pick = SkillAnimPlan.stance()
		var clip := String(pick.clip)
		if clip.is_empty():
			v.set_pose(FighterView.CharPose.READY)
		else:
			# Without the clip: the stance while winding up, the old strike key while striking.
			var striking := int(pick.phase) == SkillAnimPlan.Phase.STRIKE
			v.show_clip_u(clip, float(pick.u),
					FighterView.CharPose.STRIKE if striking else FighterView.CharPose.READY)


## Every ally with a follow-up prompt (in prompt order).
func _follow_up_allies() -> Array[int]:
	var ids: Array[int] = []
	for prompt: Dictionary in _prompts:
		if String(prompt.role) == CombatEngine.ROLE_FOLLOW_UP and not ids.has(int(prompt.character)):
			ids.append(int(prompt.character))
	return ids


## Frames the strikers where they wait, the target, and every follow-up ally where they will step
## (feet and heads) inside the follow-up safe area.
func _frame_skill() -> void:
	var points: Array[Vector3] = []
	var target := _first_target()
	for id: int in _strikers():
		_add_body_points(points, id, _approach_offset(id))
	for id: int in _follow_up_allies():
		_add_body_points(points, id, _follow_up_offset(id))
	if target >= 0:
		_add_body_points(points, target, Vector3.ZERO)
	if not points.is_empty():
		_view.camera.shot_frame(points)


func _add_body_points(points: Array[Vector3], id: int, offset: Vector3) -> void:
	var v := _view.fighter(id)
	if v == null:
		return
	var feet := v.global_position + offset
	points.append(feet)
	points.append(feet + Vector3(0.0, v.head_position().y - v.body_position().y, 0.0))


## osu-style press rings: a faint target circle, the GOOD band and the gold PERFECT band (the
## press windows drawn at the ring's shrink speed), and the ring itself, which reaches the target
## circle at the perfect moment and turns gold while it is inside the PERFECT band. The skill's
## presses are notes in a row where the strikers stand; follow-ups ring on their ally.
func _update_rings(t: int) -> void:
	var rings: Array[Dictionary] = []
	_add_press_notes(rings, t)
	_add_follow_up_rings(rings, t)
	_hud.set_rings(rings)


## One ring per press moment, numbered when there are several, the next press drawn on top.
func _add_press_notes(rings: Array[Dictionary], t: int) -> void:
	var count := _notes.size()
	var size := PressNotes.scale(count, _visuals.press_note_scale)
	var centre := _view.screen_position(_note_anchor)
	var shown: Array[Dictionary] = []
	for k: int in count:
		var note: Dictionary = _notes[k]
		var idx := _first_open(note.prompts as Array)
		if idx < 0:
			continue
		var windows: Dictionary = (_prompts[idx] as Dictionary).windows
		var rel := t - int(note.at_ms) * 1000
		var good: Array = windows.get(Defense.Outcome.PRESS, [0, 0])
		if rel < -_press_lead_us or rel > int(good[1]) + latency_us():
			continue
		var perfect: Array = windows.get(Defense.Outcome.PRESS_PERFECT, good)
		var pos := centre + PressNotes.offset(k, count, _visuals.press_note_spacing_px)
		var ring := _ring(pos, rel, _press_lead_us, size, good, perfect, _ring_color)
		ring["label"] = "PRESS" if shown.is_empty() else ""
		if count > 1:
			ring["number"] = str(k + 1)
		shown.append(ring)
	shown.reverse()
	rings.append_array(shown)


## Each open follow-up prompt rings on its ally, at the normal ring speed.
func _add_follow_up_rings(rings: Array[Dictionary], t: int) -> void:
	var lead := maxi(1, _tuning.ring_lead_ms * 1000)
	for idx: int in _prompts.size():
		var prompt: Dictionary = _prompts[idx]
		if String(prompt.role) != CombatEngine.ROLE_FOLLOW_UP or not is_prompt_open(idx):
			continue
		var windows: Dictionary = prompt.windows
		var good: Array = windows.get(Defense.Outcome.PRESS, [0, 0])
		var rel := t - int(prompt.at_ms) * 1000
		if rel < -lead or rel > int(good[1]) + latency_us():
			continue
		var v := _view.fighter(int(prompt.character))
		if v == null:
			continue
		var perfect: Array = windows.get(Defense.Outcome.PRESS_PERFECT, good)
		# Anchored at the ally's spot, not their body, so the hop in never moves the ring.
		var chest := v.centre_position() - v.body_position()
		var spot := v.global_position + _follow_up_offset(int(prompt.character)) + chest
		var ring := _ring(_view.screen_position(spot), rel, lead, 1.0, good, perfect, HudStyle.JUMP)
		ring["label"] = "FOLLOW-UP"
		rings.append(ring)


## A press ring `rel_us` from its perfect moment, `size` times the press ring's size, gold while
## inside the PERFECT window.
func _ring(pos: Vector2, rel_us: int, lead_us: int, size: float, good: Array, perfect: Array, color: Color) -> Dictionary:
	if rel_us >= int(perfect[0]) and rel_us <= int(perfect[1]):
		color = HudStyle.GOLD
	return {
		"pos": pos,
		"radius": _ring_radius(rel_us, lead_us, size),
		"color": color,
		"target_radius": _visuals.press_ring_end_radius_px * size,
		"target_color": _visuals.press_target_color,
		"bands": [_band(good, lead_us, size, _visuals.press_good_band_color),
				_band(perfect, lead_us, size, _visuals.press_perfect_band_color)],
	}


func _ring_radius(rel_us: int, lead_us: int, size: float) -> float:
	return PressNotes.radius(rel_us, lead_us, _visuals.press_ring_start_radius_px * size,
			_visuals.press_ring_end_radius_px * size, RING_MIN_RADIUS_PX)


## The ring of radii the shrinking ring passes through during a window [early_us, late_us].
func _band(edges: Array, lead_us: int, size: float, color: Color) -> Dictionary:
	var outer := _ring_radius(int(edges[0]), lead_us, size)
	var inner := _ring_radius(int(edges[1]), lead_us, size)
	return {"radius": (outer + inner) * 0.5, "width": outer - inner, "color": color}


## The first of these prompts that can still be answered, or -1.
func _first_open(idxs: Array) -> int:
	for idx: int in idxs:
		if is_prompt_open(idx):
			return idx
	return -1


## A lock icon at the first pressing hero of each locked-out player.
func _update_lock(t: int) -> void:
	var spots: Array[Vector3] = []
	for player: int in _judges.players():
		var heroes := _heroes_of(player)
		if _judges.is_locked_out(player, t) and not heroes.is_empty():
			spots.append(_view.home_of(heroes[0]))
	_hud.set_locks(spots)


## The heroes of `player` with a prompt in this skill, in prompt order.
func _heroes_of(player: int) -> Array[int]:
	var list: Array[int] = []
	for p: Dictionary in _prompts:
		var id := int(p.character)
		if _judges.player_of_prompt(int(p.idx)) == player and not list.has(id):
			list.append(id)
	return list


## Hands the tail back once every prompt is done and the last strike has played out.
func _check_finish(t: int) -> void:
	if not _tail_received or not _scheduled.is_empty() or _clock.is_paused(Time.get_ticks_usec()):
		return
	var last_us := 0
	for idx: int in _prompts.size():
		if not _voided.has(idx):
			last_us = maxi(last_us, int((_prompts[idx] as Dictionary).at_ms) * 1000)
			# A spell's strike comes when its bolt lands, which can be after the press moment.
			last_us = maxi(last_us, int(_bolt_landing.get(idx, 0)))
	if t < last_us + _tuning.skill_recover_ms * 1000:
		return
	_hand_back()


func _hand_back() -> void:
	_active = false
	if _ranged:
		_view.set_projectiles([])
	_hud.set_skill_pressing(false)
	_input.disarm()
	_hud.hide_banner()
	_hud.set_rings([])
	_hud.set_locks([])
	var return_s := float(_tuning.action_return_ms) / 1000.0
	for id: int in _mirror.party_ids:
		var v := _view.fighter(id)
		if v == null or bool(_mirror.fighter(id).get("escaped", false)):
			# A hero who just ran keeps running off (DESIGN.md 2.13).
			continue
		v.set_pose(FighterView.CharPose.IDLE if _mirror.is_alive(id) else FighterView.CharPose.DOWN)
		v.move_body(Vector3.ZERO, return_s, Tween.TRANS_QUAD, Tween.EASE_OUT)
	var tail: Array[Dictionary] = _tail.duplicate()
	_tail.clear()
	finished.emit(tail)


## A spell's bolts at skill time `t` (card #166): each of the caster's presses sends one from the
## staff to the target. It leaves at the press (or, when none came, at the end of the press
## window) and flies projectile_flight_ms; the strike lands with it (SpellShot).
func _update_bolts(t: int) -> void:
	if not _ranged:
		return
	var data := _ability.projectile
	# A spell on every enemy (Radiance, card #261) sends one bolt to each; others to the first target.
	var aims: Array[FighterView] = []
	var aim_ids: Array[int] = []
	if _ability.target == AbilityData.Target.ALL_ENEMIES:
		for id: int in _targets:
			if _mirror.is_alive(id):
				aim_ids.append(id)
	else:
		aim_ids.append(_first_target())
	for id: int in aim_ids:
		var view := _view.fighter(id)
		if view != null:
			aims.append(view)
	var list: Array[Dictionary] = []
	var flight_us := _flight_us()
	for idx: int in _bolt_release:
		var prompt: Dictionary = _prompts[idx]
		if _voided.has(idx) or aims.is_empty():
			continue
		var caster := _view.fighter(int(prompt.character))
		if caster == null:
			continue
		var release := int(_bolt_release[idx])
		if not SpellShot.in_flight(t, release, flight_us):
			continue
		var u := SpellShot.progress(t, release, flight_us)
		var frame := int(floor(float(t) / 1000.0 / maxf(1.0, float(data.loop_ms)) * float(data.hframes)))
		for target: FighterView in aims:
			var from := caster.centre_position()
			var to := target.centre_position()
			var toward := to - from
			toward.y = 0.0
			from += (toward.normalized() if toward.length() > 0.0 else Vector3.RIGHT) * data.launch_offset.x \
					+ Vector3.UP * data.launch_offset.y
			for k: int in range(data.trail_count, 0, -1):
				var tu := u - float(k * data.trail_gap_ms * 1000) / float(flight_us)
				if tu > 0.0:
					list.append(_bolt_entry(data, frame, _arc(from, to, tu, data.arc_height), BOLT_TRAIL_ALPHA / float(k)))
			list.append(_bolt_entry(data, frame, _arc(from, to, u, data.arc_height), 1.0))
	_view.set_projectiles(list)


static func _bolt_entry(data: ProjectileData, frame: int, pos: Vector3, alpha: float) -> Dictionary:
	return {"path": data.texture_path, "hframes": data.hframes, "frame": posmod(frame, maxi(1, data.hframes)),
			"pixel_size": data.pixel_size, "pos": pos, "alpha": alpha, "scale": 1.0}


## A point on a bolt's path at progress `u`: a straight line plus a lift that peaks halfway.
static func _arc(from: Vector3, to: Vector3, u: float, height: float) -> Vector3:
	return from.lerp(to, u) + Vector3.UP * height * 4.0 * u * (1.0 - u)


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


## Chest height of the spot the strikers wait at between hits (their middle for several): the
## middle of the press note row. Fixed for the whole skill, so lunges never move the rings.
func _strikers_stand_point() -> Vector3:
	var sum := Vector3.ZERO
	var count := 0
	for id: int in _strikers():
		var v := _view.fighter(id)
		if v == null:
			continue
		var chest := v.centre_position() - v.body_position()
		sum += v.global_position + _approach_offset(id) + chest
		count += 1
	if count == 0:
		var actor := _view.fighter(_actor)
		return actor.centre_position() if actor != null else Vector3.ZERO
	return sum / float(count)


## Each hero with a prompt (strikers and follow-up allies) -> their prompt idxs in press order.
func _prompts_by_hero() -> Dictionary:
	var by_hero: Dictionary = {}
	for idx: int in _prompts.size():
		var id := int((_prompts[idx] as Dictionary).character)
		if not by_hero.has(id):
			var list: Array[int] = []
			by_hero[id] = list
		(by_hero[id] as Array[int]).append(idx)
	for id: int in by_hero:
		(by_hero[id] as Array[int]).sort_custom(_earlier_prompt)
	return by_hero


func _earlier_prompt(a: int, b: int) -> bool:
	return int((_prompts[a] as Dictionary).at_ms) < int((_prompts[b] as Dictionary).at_ms)


## Where a follow-up ally waits for their ring: part of the way to their own approach spot.
func _follow_up_offset(id: int) -> Vector3:
	return _approach_offset(id) * FOLLOW_UP_STEP_SHARE


## Where a striker waits between hits: part of the way to the strike point.
func _approach_offset(id: int) -> Vector3:
	var target := _first_target()
	var v := _view.fighter(id)
	# A spell is cast from where the caster stands (their rings sit on them too).
	if target < 0 or v == null or _ranged:
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
