class_name TimedSequenceRunner
extends Node
## Plays one enemy attack on this machine (DESIGN.md 3 and 4.5).
##
## On timed_sequence_declared the controller calls start(). After attack_lead_in_ms (banner up)
## the AttackClock starts. Presses arrive from DefenseInput and are judged at once by this
## machine's judges (JudgeSet), converted to
## attack time. Every frame, after input: scheduled contact effects fire, judge.advance() expires
## missed prompts (the hit lands), and released results go to the engine as resolve_prompts. In
## co-op each player has their own judge for their own heroes (JudgeSet, DESIGN.md 9.1): a press
## counts only for the heroes of the player whose device made it. The
## prompt events that come back are applied to the mirror at once; everything from
## sequence_resolved on is handed back (finished) only when the local animation is over.
##
## Feedback comes from the judge at press time, never from engine events: decide early, show at
## contact (attack time max(press, impact)). Enemy motion, the ground wave, the training ring and
## the reading aids (banner hit row, hit markers, floor warning; DESIGN.md 3.8) are pure functions
## of attack time, so hit-stop (AttackClock.pause_for) freezes them exactly.
##
## Online (DESIGN.md 9.2) this machine judges only its own player's prompts. The engine's answers
## (to any player's results) arrive through take_events(): another player's defence is shown when
## its result arrives (a defence pose at once, a hit when the prompt would have closed). Every
## batch of events goes through one queue applied in arrival order, never out of engine order.
##
## Animation frames (DESIGN.md 5.5) are driven by attack time too: the attacker's clips per beat
## (EnemyAnim) and each hero's defence, whiff, flinch and stagger clips (PartyAnim), so hit-stop
## freezes them with the motion. Without clips every fighter shows exactly its pre-phase-10 pose.
## start() drops leftover short reactions (a weapon draw, a hurt) so they never hide those frames.
##
## Phase 12 (DESIGN.md 3.9 to 3.11): a ranged hit's projectile flies from the enemy to each of its
## targets and arrives at impact, then bounces off a parry, flies past a dodge or bursts on a hit;
## a rock ground hit bursts rows of rocks along a lane to each target, the last row under them at
## impact; a wave's front lies on the floor as a glowing band; an each-in-turn attack lunges at
## each hit's own target. All of it is a pure function of attack time, like the rest.
##
## Phase 23 (DESIGN.md 3.12): an attacker that runs up runs from home to a step short of its first
## target during the last run_up_ms of a longer lead-in (real time, before anything is judged),
## then plays the attack from there (EnemyChoreography `near`).

## Everything from sequence_resolved on, to be played by the controller.
signal finished(tail: Array[Dictionary])
## Every judged press (a DefenseJudge.press() report), for statistics and the autoplay bot.
signal press_judged(action: int, report: Dictionary)
## start() ran for sequence `seq` (online: the client tells the host, DESIGN.md 9.2).
signal sequence_started(seq: int)

enum Anim {
	NONE,
	PARRY,
	DODGE,
	JUMP,
	WHIFF,
	HURT,
}

## Share of a dodge pose spent sliding out and coming back.
const DODGE_OUT_SHARE: float = 0.25
const DODGE_BACK_SHARE: float = 0.3
## A jumping body counts as clear of a ground wave at this share of the jump height.
const JUMP_CLEAR_HEIGHT: float = 0.6
## A wave front reaching beyond the outer party slots needs at least two crests.
const MIN_WAVE_CRESTS: int = 2
## The floor warning starts at this share of its strength when the slam starts.
const WARNING_START_SHARE: float = 0.3
## A projectile's trail copies: the first is this opaque and each one this much smaller than the
## one before.
const TRAIL_ALPHA: float = 0.45
const TRAIL_SHRINK: float = 0.15
## The last row of rocks fans out across the lane this many times rock_scatter.
const FINAL_ROW_SPREAD: float = 4.0

## The training ring is a practice aid: the controller turns it off for run fights.
var training_ring_allowed: bool = true
## The training ring shows whatever the player's setting (the tutorial's defend lessons).
var force_ring: bool = false
## The press timing in ms after PARRY, LATE... ("LATE +343") is a practice aid: the controller
## turns it off outside practice fights (card #276).
var timing_numbers_allowed: bool = true
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
var _animating: bool = false
var _event: Dictionary = {}
var _seq: int = -1
var _source: int = -1
var _hits: Array = []
var _prompts: Array = []
var _targets: Array[int] = []
var _clock := AttackClock.new()
var _judges: JudgeSet
var _roster: PlayerRoster = PlayerRoster.solo(0)
## Party member id -> player index (empty: everyone is player 0).
var _owners: Dictionary = {}
## A roster change that came during a sequence: it applies when the sequence hands back, so presses
## and freezes keep the player indexes the judges were made with (cards #205, #304).
var _held_roster: PlayerRoster = null
var _held_owners: Dictionary = {}
var _latency_ms: int = 0
var _lead_in_end_us: int = 0
## This attack opens with a run to the target (DESIGN.md 3.12): it starts at _run_from_us (real
## time) and ends where the clock starts, `_near` of the way from home to the first contact point.
var _run_up: bool = false
var _run_from_us: int = 0
var _near: float = 0.0
var _cues: Array[Dictionary] = []
var _next_cue: int = 0
## Contact effects waiting for their attack time: [{at_us, call: Callable}], in order.
var _scheduled: Array[Dictionary] = []
## Party member id -> {kind: Anim, frame, from_us, until_us, contact_us, apex_us, land_us, heavy}
## (attack time).
var _anims: Dictionary = {}
## The attacker's idle loop on attack time: one cycle (ms) and its phase, chosen so it continues
## the real-time loop the view played before the clock started.
var _idle_period_ms: float = 1.0
var _idle_phase_ms: float = 0.0
## Every press (any result) as {t, player} (attack time), for the MISS label.
var _press_times: Array[Dictionary] = []
## "hit:player" keys of the hits a player whiffed against (never MISS for that player: they did
## press).
var _whiffed_hits: Dictionary = {}
## Who owns each hit-stop freeze on the shared clock (card #180): an owner's own taps inside it are
## ignored; every other press is still judged, as if the freeze had not happened. The hurt freeze
## on the last hit has no owner.
var _freezes := FreezeLedger.new()
var _contact: Vector3 = Vector3.ZERO
var _tail: Array[Dictionary] = []
var _tail_received: bool = false
var _tail_t_us: int = 0
## Event batches waiting to be applied, in engine order: [{at_us, events}] (at_us never decreases).
var _inbox: Array[Dictionary] = []
var _inbox_at_us: int = 0
var _end_reason: String = ""
var _has_counter: bool = false
## Parries in a row in this attack: the parry ring climbs with each one (card #93).
var _parry_streak: int = 0
var _counter_ready_us: int = 0
var _wave_hit: int = -1
## How long before each hit the training ring appears (the attack's own ring speed).
var _ring_lead_us: int = 1
var _wave_dist: float = -1.0
## Per hit: the party members it strikes (from the prompts) and where its lunge connects.
var _hit_targets: Array = []
var _hit_contacts: Array[Vector3] = []
## Hit index -> the ProjectileData it throws (ranged hits only).
var _projectile_of: Dictionary = {}
## "hit:id" -> launch point of that projectile, fixed when it first shows.
var _projectile_starts: Dictionary = {}
## "hit:id" -> {kind: Defense.Outcome or -1 (it hit), at_us}: what happened when it arrived.
var _projectile_ends: Dictionary = {}
## Rock hit index -> where its lanes start (the enemy's feet at the slam).
var _rock_starts: Dictionary = {}
var _projectiles_drawn: int = 0
var _rocks_drawn: int = 0
## Real time start() ran (bystanders step aside from then).
var _started_us: int = 0
## Attack time of the first enemy motion (target arrows hide then).
var _first_motion_us: int = 0
var _last_frame_us: int = 0
var _longest_frame_us: int = 0
var _last_attack_longest_us: int = 0


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


## Who plays which hero (co-op). `owners` maps a party member id to its player. During a sequence
## the change waits until it hands back (the judges were made with the old player indexes).
func set_players(roster: PlayerRoster, owners: Dictionary) -> void:
	if _active:
		_held_roster = roster
		_held_owners = owners
		return
	_roster = roster
	_owners = owners


## Applies a roster change that waited for the sequence to end, if there is one.
func _take_held_players() -> void:
	if _held_roster == null:
		return
	_roster = _held_roster
	_owners = _held_owners
	_held_roster = null
	_held_owners = {}


## Starts playing a timed_sequence_declared event (already applied to the mirror). `attack` is the
## attack's data (for its training ring speed and its hits' animation prefixes; null = the tuning
## default and plain clips). `enemy_data` is the attacker's data (its idle breathing speed; null =
## 100%).
func start(event: Dictionary, attack: EnemyAttackData = null, enemy_data: EnemyData = null) -> void:
	_take_held_players()
	_event = event
	_seq = int(event.seq)
	_source = int(event.source)
	_prompts = event.prompts
	_targets.assign(event.targets)
	_latency_ms = PlayerSettings.base_latency_compensation_ms(_tuning)
	# Each hit carries its close time on this machine, so the enemy holds contact until then.
	_hits = EnemyChoreography.with_close_times(event.hits, _prompts, _latency_ms)
	_add_hit_anims(attack)
	_hit_targets.clear()
	for i: int in _hits.size():
		_hit_targets.append([] as Array[int])
	for prompt: Dictionary in _prompts:
		var list: Array[int] = _hit_targets[int(prompt.hit)]
		if not list.has(int(prompt.character)):
			list.append(int(prompt.character))
	_projectile_starts.clear()
	_projectile_ends.clear()
	_rock_starts.clear()
	_view.set_projectiles([])
	_view.set_rocks([])
	_projectiles_drawn = 0
	_rocks_drawn = 0
	_judges = JudgeSet.new(_tuning.whiff_lockout_ms, _latency_ms, _tuning.press_reach_back_max_ms,
			_tuning.late_press_report_ms)
	# Online, other machines judge their own players' prompts.
	var only: Array[int] = []
	if _roster.is_online():
		only = _roster.local_players()
	_judges.set_prompts(_prompts, _owners, only)
	_clock = AttackClock.new()
	_inbox.clear()
	_inbox_at_us = 0
	_started_us = Time.get_ticks_usec()
	_run_up = EnemyChoreography.runs_up(attack, enemy_data, _hits)
	_run_from_us = _started_us + _tuning.attack_lead_in_ms * 1000
	_lead_in_end_us = _started_us + EnemyChoreography.lead_in_ms(_tuning, _run_up) * 1000
	_set_idle_loop(enemy_data)
	_cues = EnemyChoreography.cues(_hits, _visuals)
	_ring_lead_us = maxi(1, (attack.ring_lead_ms(_tuning) if attack != null else _tuning.ring_lead_ms) * 1000)
	_first_motion_us = roundi(float(_cues[0].at_ms) * 1000.0) if not _cues.is_empty() else 0
	_next_cue = 0
	_scheduled.clear()
	_schedule_windups()
	_anims.clear()
	_press_times.clear()
	_whiffed_hits.clear()
	_freezes.clear()
	_tail.clear()
	_tail_received = false
	_has_counter = false
	_parry_streak = 0
	_counter_ready_us = 0
	_end_reason = ""
	_wave_hit = -1
	_wave_dist = -1.0
	_longest_frame_us = 0
	_last_frame_us = Time.get_ticks_usec()
	_contact = _view.contact_point(_targets)
	# Each hero in turn: every hit lunges at its own target.
	_hit_contacts.clear()
	for i: int in _hits.size():
		var own: Array[int] = _hit_targets[i]
		_hit_contacts.append(_view.contact_point(own) if _each_in_turn() and not own.is_empty() else _contact)
	_near = _near_share()
	_view.camera.shot_attack(_view.home_of(_source), _contact)
	# The runner moves the party every frame from here on: stop any leftover tweened movement, and
	# any leftover short reaction (a weapon draw, a hurt) that would hide a defence frame. Bigger
	# ones (a fall, a get-up) keep playing.
	for id: int in _mirror.party_ids:
		var view := _view.fighter(id)
		if view != null:
			view.move_body(view.body_offset, 0.0)
			view.clear_timed_pose(FighterView.PRIO_BIG)
	_active = true
	_animating = true
	_input.arm_all()
	_hud.show_banner(String(_event.get("name", "?")), HudStyle.LATE, _banner_text())
	_hud.set_defending(true)
	var kinds: Array = []
	var times: Array = []
	var feints: Array = []
	var marks: Array = []
	# A thrown hit shows its own icon on the banner too (card #278).
	var ranged: Array = []
	for hit: Dictionary in _hits:
		kinds.append(int(hit.kind))
		times.append(int(hit.at_ms))
		feints.append(bool(hit.get("feint", false)))
		marks.append(String(hit.get("mark", "")))
		ranged.append(EnemyChoreography.is_ranged(hit))
	_hud.set_banner_hits(kinds, times, feints, marks, ranged)
	_hud.set_targeted(_targets)
	var enemy := _view.fighter(_source)
	if enemy != null:
		# Nothing timed (a hurt, a stagger, a rage) may hide the attack's own frames.
		enemy.clear_timed_pose(FighterView.PRIO_FINAL)
		enemy.body_offset = Vector3.ZERO
		enemy.set_pose(EnemyChoreography.Pose.IDLE)
		enemy.set_squash(0.0)
	sequence_started.emit(_seq)


## The sequence being played (-1 before the first).
func current_seq() -> int:
	return _seq


## Events of this sequence that did not come back from this machine's own submit (online: every
## batch the host sends; on the host, the batches its clients' results and the arbiter caused).
## Other players' results are shown here: a defence when it arrives, a hit when the prompt would
## have closed (the batch waits until then, so HP never drops before the swing lands).
func take_events(events: Array[Dictionary]) -> void:
	if not _active:
		return
	var t := attack_time_us()
	var apply_at := t
	for ev: Dictionary in events:
		if String(ev.get("type", "")) != "prompt_resolved" or int(ev.get("seq", -1)) != _seq:
			continue
		var idx := int(ev.prompt)
		if _judges.player_of_prompt(idx) >= 0 or not _is_pending(idx):
			continue
		var prompt: Dictionary = _prompts[idx]
		var outcome := int(ev.outcome)
		var impact_us := int(prompt.at_ms) * 1000
		if outcome == Defense.Outcome.NONE:
			var close_us := impact_us
			for action: Variant in (prompt.windows as Dictionary):
				close_us = maxi(close_us, impact_us + int((prompt.windows[action] as Array)[1]))
			apply_at = maxi(apply_at, close_us)
			_schedule(maxi(t, close_us), _land_remote_hit.bind(idx))
		else:
			var id := int(prompt.character)
			var late_us := int((prompt.windows[outcome] as Array)[1]) if (prompt.windows as Dictionary).has(outcome) else 0
			var contact := _start_defence_anim(id, outcome, t, impact_us, late_us)
			var chars: Array[int] = [id]
			_schedule(contact, _on_contact.bind(outcome, int(prompt.hit), chars, int(ev.get("offset_us", 0))))
	_push_batch(events, apply_at)

func is_active() -> bool:
	return _active


## True while presses are being judged (the attack clock is running).
func is_defending() -> bool:
	return _active and _clock.is_started()


## Current attack time in microseconds (0 before the clock starts).
func attack_time_us() -> int:
	if not _clock.is_started():
		return 0
	return _clock.attack_time_us(Time.get_ticks_usec())


func is_clock_paused() -> bool:
	return _clock.is_started() and _clock.is_paused(Time.get_ticks_usec())


## The base lag compensation the current judges use (the smaller of the keyboard's and the pad's,
## DESIGN.md 3.2). Window edges drawn for the player use it too.
func latency_us() -> int:
	return _latency_ms * 1000


## How much more the device that made a press lags than the base (card #204).
func _extra_latency_ms(device: int) -> int:
	return PlayerSettings.latency_compensation_ms(_tuning, PlayerSettings.input_kind_of_device(device)) - _latency_ms


## Longest frame (ms) during the current attack, or the last one if none is running.
func longest_frame_ms() -> float:
	return float(_longest_frame_us if _active else _last_attack_longest_us) / 1000.0


func _process(_delta: float) -> void:
	if not _animating:
		return
	var now := Time.get_ticks_usec()
	if _active:
		_longest_frame_us = maxi(_longest_frame_us, now - _last_frame_us)
		_last_frame_us = now
	if not _clock.is_started():
		if now < _lead_in_end_us:
			_update_party(0)
			_update_target_arrows(0)
			_update_run_in(now)
			return
		_clock.start(_lead_in_end_us)
		# The camera glided to the attack shot during the lead-in: hold it still from here.
		_view.camera.settle()
		if bool(_event.get("alert_cue", false)):
			Sfx.play("alert")
	var t := _clock.attack_time_us(now)
	if _active:
		_fire_scheduled(t)
		_expire(t)
		_release(t)
		_drain(t)
		_fire_cues(t)
	_update_enemy(t)
	_update_projectiles(t)
	_update_rocks(t)
	if _active:
		_update_party(t)
		_update_wave(t)
		_update_rings(t)
		_update_reading(t)
		_update_ranged_aims(t)
		_update_lock(t)
		_update_target_arrows(t)
		# Read the time again: a contact effect above may have just started a hit-stop.
		_check_finish(Time.get_ticks_usec(), t)
	elif _enemy_settled(t) and _projectiles_drawn == 0 and _rocks_drawn == 0:
		_animating = false


func _push_batch(events: Array[Dictionary], at_us: int) -> void:
	if events.is_empty():
		return
	_inbox_at_us = maxi(_inbox_at_us, at_us)
	_inbox.append({"at_us": _inbox_at_us, "events": events})
	_drain(attack_time_us())


## Applies the queued batches that are due, oldest first.
func _drain(t: int) -> void:
	while not _inbox.is_empty() and int(_inbox[0].at_us) <= t:
		_apply_batch((_inbox.pop_front() as Dictionary).events as Array[Dictionary], t)


## Another player's prompt landed as a hit (their machine said NONE).
func _land_remote_hit(idx: int) -> void:
	var sounded: Dictionary = {}
	_land_hit(idx, attack_time_us(), Time.get_ticks_usec(), sounded)


# --- presses ----------------------------------------------------------------------------------

func _on_pressed(action: int, stamp_us: int, previous_pump_us: int, device: int) -> void:
	if not _active or not _clock.is_started():
		return
	# Only players whose heroes this attack targets defend (another player's press does nothing).
	var player := _roster.player_of_device(device)
	if not _judges.players().has(player):
		return
	# Every target went down: what is left of the attack is only animation.
	if _tail_received and _end_reason != "completed":
		return
	var t := _clock.attack_time_us(stamp_us)
	var earliest := -1
	if _clock.is_paused(stamp_us):
		# A press by the owner of a success freeze is a double tap: ignored, no judgement, no
		# lockout (DESIGN.md 3.3). Anyone else's press, and any press during the hurt freeze on a
		# last hit (every prompt is resolved by then, so it can only be a LATE report), is judged
		# at the time it would have had without the freeze.
		var shift := _freezes.press_shift_us(stamp_us, player)
		if shift == FreezeLedger.IGNORE:
			return
		t += shift
	elif previous_pump_us > 0 and previous_pump_us < stamp_us:
		var e := _clock.attack_time_us(previous_pump_us)
		if e >= 0:
			earliest = e
	var report := _judges.press(player, action, t, earliest, _extra_latency_ms(device))
	if int(report.result) == DefenseJudge.Result.SUCCESS and not _any_pending(report.prompts):
		report.result = DefenseJudge.Result.DONE
	_press_times.append({"t": t, "player": player})
	# Hits this press expired (after a long frame) land now, while still pending, so they get
	# their hit feedback before the results go to the engine.
	_expire(t)
	_options.stats.record(action, report)
	press_judged.emit(action, report)
	match int(report.result):
		DefenseJudge.Result.SUCCESS:
			_on_success(action, report, t)
		DefenseJudge.Result.WHIFF:
			_on_whiff(action, report, t, player)
		DefenseJudge.Result.LOCKED:
			Sfx.play("locked", _visuals.locked_click_volume_db)
	_release(t)


func _on_success(action: int, report: Dictionary, t: int) -> void:
	var hit_index := int(report.hit)
	var hit: Dictionary = _hits[hit_index]
	var impact_us := int(hit.at_ms) * 1000
	var characters: Array[int] = []
	var contact_us := maxi(t, impact_us)
	for idx: int in report.prompts:
		if not _is_pending(idx):
			continue
		var prompt: Dictionary = _prompts[idx]
		var id := int(prompt.character)
		characters.append(id)
		var late_us := int((prompt.windows[action] as Array)[1])
		contact_us = maxi(contact_us, _start_defence_anim(id, action, t, impact_us, late_us))
	if characters.is_empty():
		return
	_schedule(contact_us, _on_contact.bind(action, hit_index, characters, int(report.offset_us)))


func _on_whiff(action: int, report: Dictionary, t: int, player: int) -> void:
	var reason := int(report.reason)
	Sfx.play("wrong_button" if reason == DefenseJudge.Reason.WRONG_ACTION else "whiff")
	_parry_streak = 0
	var text := "LATE"
	var color := HudStyle.LATE
	match reason:
		DefenseJudge.Reason.EARLY:
			text = "EARLY"
			color = HudStyle.EARLY
		DefenseJudge.Reason.WRONG_ACTION:
			color = HudStyle.WRONG
			text = HudStyle.wrong_action_text(_kind_of(int(report.hit)))
	if reason != DefenseJudge.Reason.WRONG_ACTION and int(report.hit) >= 0:
		text = with_timing(text, int(report.offset_us))
	if int(report.hit) >= 0:
		_whiffed_hits["%d:%d" % [int(report.hit), player]] = true
	var defenders := _living_targets_of(player)
	for id: int in defenders:
		var current: Dictionary = _anims.get(id, {})
		# Keep a flinch (the hit is what happened) and a successful defence still playing (a
		# double tap must not drop a jumper to the ground); flash, sound and readout still show.
		if not current.is_empty() and int(current.kind) != Anim.WHIFF and t < int(current.until_us):
			_view.fighter(id).flash(_visuals.flash_ms, color, _visuals.whiff_flash_strength)
			continue
		_anims[id] = {"kind": Anim.WHIFF, "frame": _pose_for_action(action), "from_us": t,
				"until_us": t + _visuals.whiff_pose_ms * 1000}
		_view.fighter(id).flash(_visuals.flash_ms, color, _visuals.whiff_flash_strength)
	_hud.popup(text, _focus_head(defenders), color)


## Contact moment of a successful defence: sound, flash, sparks, hit-stop, popup.
func _on_contact(action: int, hit_index: int, characters: Array[int], offset_us: int) -> void:
	var now := Time.get_ticks_usec()
	var final := hit_index == _hits.size() - 1
	var text := ""
	var color := HudStyle.PARRY
	match action:
		Defense.Outcome.PARRY:
			text = "PARRY"
			Sfx.play("parry_final" if final else "parry")
			PadRumble.heroes("parry_final" if final else "parry", characters)
			var step := mini(_parry_streak, _visuals.parry_ring_max_steps)
			Sfx.play("parry_ring", 0.0, pow(2.0, step * _visuals.parry_ring_step_semitones / 12.0))
			_parry_streak += 1
			_freeze(now, _tuning.hitstop_parry_final_ms if final else _tuning.hitstop_parry_ms, characters)
			_view.camera.add_trauma(_visuals.shake_parry_final if final else _visuals.shake_parry)
			_view.camera.punch(_visuals.punch_parry_final if final else _visuals.punch_parry, _visuals.punch_ms)
			var enemy := _view.fighter(_source)
			if enemy != null:
				enemy.flash(_visuals.flash_ms, Color.WHITE, _visuals.parry_enemy_flash_strength)
			# The enemy panels come back at once (card #268); a parried last hit keeps them up for
			# the counter.
			_hud.show_enemy_panels(final)
		Defense.Outcome.DODGE:
			text = "DODGE"
			color = HudStyle.DODGE
			Sfx.play("dodge")
			PadRumble.heroes("dodge", characters)
			_view.camera.add_trauma(_visuals.shake_dodge)
		Defense.Outcome.JUMP:
			text = "JUMP"
			color = HudStyle.JUMP
			Sfx.play("jump")
			PadRumble.heroes("jump", characters)
			_freeze(now, _tuning.hitstop_jump_ms, characters)
	text = with_timing(text, offset_us)
	var shown: Array[int] = []
	var enemy_view := _view.fighter(_source)
	for id: int in characters:
		var key := _projectile_key(hit_index, id)
		if _projectile_of.has(hit_index) and not _projectile_ends.has(key):
			_projectile_ends[key] = {"kind": action, "at_us": attack_time_us()}
		if not _mirror.is_alive(id):
			continue
		shown.append(id)
		var view := _view.fighter(id)
		if action == Defense.Outcome.PARRY:
			view.flash(_visuals.flash_ms)
			var at := view.centre_position()
			if enemy_view != null:
				at = at.lerp(enemy_view.centre_position(), _visuals.spark_toward_enemy)
			_view.spawn_sparks(at, _visuals.sparks_per_parry)
		elif action == Defense.Outcome.JUMP:
			view.flash(_visuals.flash_ms, HudStyle.JUMP, _visuals.jump_flash_strength)
		elif action == Defense.Outcome.DODGE:
			view.flash(_visuals.flash_ms, HudStyle.DODGE, _visuals.dodge_flash_strength)
	# One readout per press, even when it answered several characters at once.
	if not shown.is_empty():
		_hud.popup(text, _focus_head(shown), color)


## `text` with the press timing after it ("LATE +343"): only in a practice fight with the readout
## on (F1 > T). In the real game the word alone (card #276).
func with_timing(text: String, offset_us: int) -> String:
	if not timing_numbers_allowed or _options == null or not _options.timing_readout:
		return text
	return text + " " + HudStyle.signed_ms(roundi(float(offset_us) / 1000.0))


## Freezes the shared attack clock for `ms` from `now`, owned by the players behind `characters`
## (none: nobody's, the hurt freeze).
func _freeze(now: int, ms: int, characters: Array[int]) -> void:
	var players: Array[int] = []
	for id: int in characters:
		var player := int(_owners.get(id, 0))
		if not players.has(player):
			players.append(player)
	_clock.pause_for(now, ms * 1000)
	_freezes.add(now, ms * 1000, players)


# --- per-frame steps --------------------------------------------------------------------------

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


## Prompts whose windows all closed: the hit lands now (damage, flinch, sound, hit-stop).
func _expire(t: int) -> void:
	var expired := _judges.advance(t)
	if expired.is_empty():
		return
	var now := Time.get_ticks_usec()
	var sounded: Dictionary = {}
	for idx: int in expired:
		if _is_pending(idx):
			_land_hit(idx, t, now, sounded)


## A hit lands on prompt `idx`'s character: sound (once per hit in `sounded`), hit-stop on the
## last hit, shake, flinch, MISS (unless the player pressed) and the damage number.
func _land_hit(idx: int, t: int, now: int, sounded: Dictionary) -> void:
	var prompt: Dictionary = _prompts[idx]
	var id := int(prompt.character)
	if not _mirror.is_alive(id):
		return
	var hit_index := int(prompt.hit)
	# A heavy hit (at least big_hit_percent of max HP, like the big damage number) staggers the
	# hero: a longer pose and a bigger knockback (card #62), and it shakes the camera harder than
	# a graze (card #179). Presentation only.
	var max_hp := maxi(1, int(_mirror.fighter(id).get("max_hp", 1)))
	var heavy := int(prompt.damage) * 100 >= max_hp * _visuals.big_hit_percent
	if not sounded.has(hit_index):
		sounded[hit_index] = true
		_parry_streak = 0
		# A Guarded hero takes less damage: a dull block instead of the full hit sound.
		var guarded := _mirror.has_status(id, "guarded")
		var impact := String((_hits[hit_index] as Dictionary).get("impact_sfx", "hurt"))
		var thrown: ProjectileData = _projectile_of.get(hit_index)
		if thrown != null and not thrown.hit_sfx.is_empty():
			impact = thrown.hit_sfx
		Sfx.play("guard_block" if guarded else impact)
		# Only the last hit freezes: in a string the next lunge has often started by now.
		if hit_index == _hits.size() - 1 and _tuning.hitstop_hurt_ms > 0:
			_freeze(now, _tuning.hitstop_hurt_ms, [])
		_view.camera.add_trauma(_visuals.shake_hurt_heavy if heavy else _visuals.shake_hurt)
		if heavy:
			_view.camera.punch(_visuals.punch_hurt_heavy, _visuals.punch_ms)
	var view := _view.fighter(id)
	view.flash(_visuals.flash_ms, HudStyle.DAMAGE_TAKEN, _visuals.hurt_flash_strength)
	# Only the pad of the player whose hero took it (card #299).
	PadRumble.hero("hurt_heavy" if heavy else "hurt", id)
	# A projectile bursts on the hero it hit.
	var key := _projectile_key(hit_index, id)
	if _projectile_of.has(hit_index) and not _projectile_ends.has(key):
		_projectile_ends[key] = {"kind": -1, "at_us": t}
		var projectile: ProjectileData = _projectile_of[hit_index]
		_view.spawn_sparks(_standing_centre(id), _visuals.projectile_burst_sparks, 1.0, projectile.color)
	var pose_ms := _visuals.stagger_pose_ms if heavy else _visuals.hurt_pose_ms
	_anims[id] = {"kind": Anim.HURT, "frame": FighterView.CharPose.HURT, "from_us": t,
			"until_us": t + pose_ms * 1000, "heavy": heavy}
	# MISS first: popups in a column stack oldest on top, so the damage number (newest) stays
	# at the head and MISS sits just above it.
	var player := _judges.player_of_prompt(idx)
	if not _whiffed_hits.has("%d:%d" % [hit_index, player]) and not _pressed_near(prompt, player):
		var rise := view.visible_height() * _visuals.miss_label_rise_factor
		_hud.popup("MISS", view.head_position() + Vector3(0.0, rise, 0.0), HudStyle.MISS)
	_hud.damage_number(int(prompt.damage), view.head_position(), HudStyle.DAMAGE_TAKEN)


## Sends the judge's released results to the engine and applies what comes back.
func _release(t: int) -> void:
	if _judges == null:
		return
	var ready := _judges.pop_ready()
	if ready.is_empty():
		return
	var results: Array[Dictionary] = []
	for r: Dictionary in ready:
		var idx := int(r.prompt)
		# Prompts the engine voided (their character went down) are no longer accepted.
		if _is_pending(idx):
			results.append(CombatCommands.prompt_result(idx, int(r.outcome), int(r.offset_us)))
	if results.is_empty():
		return
	_push_batch(_submit.call(CombatCommands.resolve_prompts(_seq, results)), t)


## Applies one batch of engine events: prompt events now, everything from sequence_resolved on
## kept as the tail for the controller.
func _apply_batch(events: Array[Dictionary], t: int) -> void:
	var in_tail := _tail_received
	for ev: Dictionary in events:
		var type := String(ev.get("type", ""))
		if type == "sequence_resolved":
			in_tail = true
			_tail_received = true
			_tail_t_us = t
			_end_reason = String(ev.get("reason", ""))
		if type == "prompts_voided":
			_judges.void_prompts(ev.get("prompts", []) as Array)
		# Practice toggles are not part of any animation: apply them at once even in the tail,
		# so a newer toggle can never be overwritten by this older snapshot later.
		if in_tail and type != "practice_changed":
			_tail.append(ev)
			if type == "counter":
				_has_counter = true
		else:
			_apply_now.call(ev)


## The wind-up sound swells into each hit and peaks on it (card #94): it starts its own length
## before the impact. Skipped when it would overlap the previous hit or start before the attack.
func _schedule_windups() -> void:
	if not _options.motion_sounds:
		return
	var length_us := Sfx.cue_length_ms("windup") * 1000
	if length_us <= 0:
		return
	var free_from_us := 0
	for hit: Dictionary in _hits:
		var impact_us := int(hit.at_ms) * 1000
		if impact_us - length_us >= free_from_us:
			_schedule(impact_us - length_us, Sfx.play.bind("windup", 0.0, 1.0))
		free_from_us = impact_us


## The kind of hit `hit_index` in this attack (NORMAL when there is none).
func _kind_of(hit_index: int) -> int:
	if hit_index < 0 or hit_index >= _hits.size():
		return AttackHitData.Kind.NORMAL
	return int((_hits[hit_index] as Dictionary).kind)


func _fire_cues(t: int) -> void:
	var t_ms := float(t) / 1000.0
	while _next_cue < _cues.size() and t_ms >= float(_cues[_next_cue].at_ms):
		var cue: Dictionary = _cues[_next_cue]
		_next_cue += 1
		var enemy := _view.fighter(_source)
		if _options.telegraph_flash and enemy != null:
			# The flash is in the hit's colour: it says which defence the hit needs (a slam purple,
			# a rend bone, a sweep green, a normal hit red-orange).
			var color := _visuals.kind_color(_kind_of(int(cue.get("hit", -1))), _visuals.telegraph_flash_color)
			if String(cue.type) == EnemyChoreography.CUE_SLAM:
				color = _visuals.ground_hit_color
			enemy.flash(_visuals.telegraph_flash_ms, color, _visuals.telegraph_flash_strength)
		match String(cue.type):
			EnemyChoreography.CUE_SLAM:
				if _options.motion_sounds:
					Sfx.play("slam")
				if _ground_look(int(cue.hit)) == AttackHitData.GroundLook.ROCKS:
					_rock_starts[int(cue.hit)] = enemy.body_position() if enemy != null else _contact
					if _options.motion_sounds:
						Sfx.play("rock_rumble")
				else:
					_wave_hit = int(cue.hit)
					_wave_dist = -1.0
			EnemyChoreography.CUE_SHOOT:
				var projectile: ProjectileData = _projectile_of.get(int(cue.hit))
				if _options.motion_sounds and projectile != null and not projectile.launch_sfx.is_empty():
					Sfx.play(projectile.launch_sfx)
			_:
				if _options.motion_sounds:
					Sfx.play("lunge")


func _update_enemy(t: int) -> void:
	var enemy := _view.fighter(_source)
	if enemy == null:
		return
	var t_ms := float(t) / 1000.0
	var s := EnemyChoreography.sample(_hits, t_ms, _visuals, _near)
	# The beat's clip cell on attack time (cards #60, #63, #69); a missing clip shows the pose.
	# A beaten enemy keeps the look its downing gave it while it still walks home.
	if _mirror.is_alive(_source) and int(s.get("beat", -1)) == EnemyChoreography.Beat.AFTER:
		# After the last beat, hand over to the real-time idle loop (no one-cell pop).
		enemy.set_pose(EnemyChoreography.Pose.IDLE)
	elif _mirror.is_alive(_source):
		var frame := EnemyAnim.pick(s, _hits, enemy.clip_count, _visuals, t_ms, _idle_period_ms,
				_idle_phase_ms)
		enemy.show_clip(String(frame.clip), int(frame.index), int(s.pose))
	enemy.set_glow(float(s.glow))
	# The wind-up glows in the hit's colour: purple before a slam, bone before a rend, green before
	# a sweep, the wind-up colour before a normal lunge.
	enemy.set_glow_color(_visuals.kind_color(_kind_of(int(s.hit)), _visuals.windup_glow_color))
	var crouch := 0.0
	if _options.windup_crouch and int(s.pose) == EnemyChoreography.Pose.WINDUP:
		crouch = float(s.glow) * float(_visuals.windup_squash_percent) / 100.0
	enemy.set_squash(crouch)
	enemy.body_offset = _enemy_travel(s, enemy.position) * float(s.approach)


## How far from home (share of the way to the first contact point) an attacker that runs up stops:
## swing_step short of the contact point (0 when it does not run up).
func _near_share() -> float:
	var enemy := _view.fighter(_source)
	if not _run_up or enemy == null or _hit_contacts.is_empty():
		return 0.0
	var reach := _hit_contacts[0] - enemy.position
	reach.y = 0.0
	if reach.length() <= 0.0:
		return 0.0
	return clampf(1.0 - _visuals.swing_step / reach.length(), 0.0, 1.0)


## Before the clock: the run up to the first target over run_up_ms at the end of the lead-in, in
## real time (nothing is judged yet), easing in and out, playing the chase loop.
func _update_run_in(now: int) -> void:
	var enemy := _view.fighter(_source)
	if not _run_up or enemy == null or not _mirror.is_alive(_source) or now < _run_from_us:
		return
	var ms := float(now - _run_from_us) / 1000.0
	var u := clampf(ms / float(maxi(1, _tuning.run_up_ms)), 0.0, 1.0)
	var s := {"hit": 0, "beat": EnemyChoreography.Beat.BEFORE}
	enemy.body_offset = _enemy_travel(s, enemy.position) * _near * u * u * (3.0 - 2.0 * u)
	var frame := EnemyAnim.run(enemy.clip_count, ms, _visuals)
	enemy.show_clip(String(frame.clip), int(frame.index), EnemyChoreography.Pose.IDLE)


func _enemy_settled(t: int) -> bool:
	var s := EnemyChoreography.sample(_hits, float(t) / 1000.0, _visuals, _near)
	if float(s.approach) > 0.0 or int(s.pose) != EnemyChoreography.Pose.IDLE:
		return false
	if t < _last_impact_us():
		return false
	var enemy := _view.fighter(_source)
	if enemy != null:
		enemy.body_offset = Vector3.ZERO
		enemy.set_glow(0.0)
		enemy.set_squash(0.0)
		# Back to the real-time idle loop (the attack-time one would stop here).
		if _mirror.is_alive(_source):
			enemy.set_pose(EnemyChoreography.Pose.IDLE)
	return true


func _update_party(t: int) -> void:
	# During a single-target attack the others step back and dim, so the lunge lane and the
	# target read clearly (they ease aside at the speed party members return to their spots).
	var single := int(_event.get("mode", 0)) != EnemyAttackData.TargetMode.PARTY
	var step := clampf(float(Time.get_ticks_usec() - _started_us) / float(maxi(1, _tuning.action_return_ms * 1000)), 0.0, 1.0)
	for id: int in _mirror.party_ids:
		var view := _view.fighter(id)
		if view == null:
			continue
		var anim: Dictionary = _anims.get(id, {})
		var playing := not anim.is_empty() and t < int(anim.until_us)
		if not _mirror.is_alive(id):
			view.set_pose(FighterView.CharPose.DOWN)
			view.set_grey(1.0)
			# The killing hit's knockback plays out (the fall plays over the down pose, card #66).
			var knocked := playing and int(anim.kind) == Anim.HURT
			view.body_offset = _anim_offset(id, anim, t) if knocked else Vector3.ZERO
			continue
		var pose := FighterView.CharPose.READY if _targets.has(id) else FighterView.CharPose.IDLE
		var offset := Vector3.ZERO
		var bystander := single and not _targets.has(id)
		if bystander:
			offset = _away_from_contact(id) * _visuals.bystander_step_back * (1.0 - (1.0 - step) * (1.0 - step))
		view.set_tint(Color.WHITE.lerp(_visuals.bystander_tint, step) if bystander else Color.WHITE)
		if playing:
			offset += _anim_offset(id, anim, t)
			# Defence, whiff, flinch or stagger frames on attack time (cards #61, #62); a missing
			# clip shows the anim's single pose.
			var frame := PartyAnim.pick(anim, t, view.clip_count, DODGE_OUT_SHARE, DODGE_BACK_SHARE)
			view.show_clip(String(frame.clip), int(frame.index), int(anim.frame))
		else:
			# Idle or combat stance: their real-time breathing loops (card #69).
			view.set_pose(pose)
		view.body_offset = offset


## Flat direction from the contact point to this party member's home.
func _away_from_contact(id: int) -> Vector3:
	var away := _view.home_of(id) - _contact
	away.y = 0.0
	return away.normalized() if away.length() > 0.0 else Vector3.LEFT


func _anim_offset(id: int, anim: Dictionary, t: int) -> Vector3:
	var from := float(anim.from_us)
	var until := float(anim.until_us)
	var away := _away_from_contact(id)
	match int(anim.kind):
		Anim.DODGE:
			var length := maxf(1.0, until - from)
			var s := (float(t) - from) / length
			var k := 1.0
			if s < DODGE_OUT_SHARE:
				k = 1.0 - pow(1.0 - s / DODGE_OUT_SHARE, 2.0)
			elif s > 1.0 - DODGE_BACK_SHARE:
				k = 1.0 - (s - (1.0 - DODGE_BACK_SHARE)) / DODGE_BACK_SHARE
			return away * _visuals.dodge_slide_distance * clampf(k, 0.0, 1.0)
		Anim.JUMP:
			var apex := float(anim.apex_us)
			var land := float(anim.land_us)
			var y := 0.0
			if float(t) < apex:
				var u := clampf((float(t) - from) / maxf(1.0, apex - from), 0.0, 1.0)
				y = 1.0 - (1.0 - u) * (1.0 - u)
			else:
				var u := clampf((float(t) - apex) / maxf(1.0, land - apex), 0.0, 1.0)
				y = 1.0 - u * u
			return Vector3(0.0, _visuals.jump_height * y, 0.0)
		Anim.HURT:
			var s := clampf((float(t) - from) / maxf(1.0, until - from), 0.0, 1.0)
			var knockback := _visuals.stagger_knockback if bool(anim.get("heavy", false)) else _visuals.hurt_knockback
			return away * knockback * (1.0 - s) * (1.0 - s)
	return Vector3.ZERO


## Places the ground-wave crests: a front parallel to the party line that reaches it at impact.
func _update_wave(t: int) -> void:
	if _wave_hit < 0:
		return
	var hit: Dictionary = _hits[_wave_hit]
	var approach := maxf(1.0, float(hit.approach_ms))
	var u := (float(t) / 1000.0 - (float(hit.at_ms) - approach)) / approach
	# Fully visible until the hit can no longer be jumped (a missed jump's damage lands on it),
	# then it fades out while travelling on past the party.
	var close_u := 1.0 + float(hit.get("close_ms", 0.0)) / approach
	var gone_u := close_u + float(_visuals.wave_fade_ms) / approach
	if u > gone_u:
		_wave_hit = -1
		_view.hide_wave()
		return
	var line := _party_line()
	var a: Vector3 = line[0]
	var b: Vector3 = line[1]
	var along := b - a
	along.y = 0.0
	along = along.normalized() if along.length() > 0.0 else Vector3.BACK
	var normal := Vector3(along.z, 0.0, -along.x)
	var enemy := _view.fighter(_source)
	var enemy_pos := enemy.body_position() if enemy != null else _contact
	if normal.dot(enemy_pos - a) < 0.0:
		normal = -normal
	if _wave_dist < 0.0:
		_wave_dist = maxf(normal.dot(enemy_pos - a), _visuals.wave_min_travel)
	var front := normal * _wave_dist * (1.0 - u)
	var margin := along * _visuals.wave_line_margin
	var count := maxi(MIN_WAVE_CRESTS, _visuals.wave_crest_count)
	var points: Array[Vector3] = []
	for i: int in count:
		var p := (a - margin).lerp(b + margin, float(i) / float(count - 1)) + front
		p.y = 0.0
		points.append(p)
	var alpha := 1.0 if u <= close_u else 1.0 - (u - close_u) / maxf(0.001, gone_u - close_u)
	alpha = clampf(minf(alpha, u * 4.0 + 0.2), 0.0, 1.0)
	_view.set_wave(points, alpha)
	_view.set_wave_band(points[0], points[points.size() - 1], alpha * _visuals.wave_band_strength,
			_visuals.ground_hit_color)


func _update_rings(t: int) -> void:
	var ring_on := training_ring_allowed and bool(_event.get("allow_timing_ring", true))
	if not ring_on or not (force_ring or PlayerSettings.show_timing_ring(_tuning)):
		_hud.set_rings([])
		return
	var rings: Array[Dictionary] = []
	var lead := _ring_lead_us
	for prompt: Dictionary in _prompts:
		var at := int(prompt.at_ms) * 1000
		if t < at - lead or t > at:
			continue
		var id := int(prompt.character)
		if not _mirror.is_alive(id):
			continue
		var u := float(t - (at - lead)) / float(lead)
		rings.append({
			"pos": _view.screen_position(_view.fighter(id).centre_position()),
			"radius": lerpf(_visuals.ring_start_radius_px, _visuals.ring_end_radius_px, u),
			"color": _visuals.kind_color(int(prompt.kind), HudStyle.RING_NORMAL),
			"label": HudStyle.kind_label(int(prompt.kind)),
		})
	_hud.set_rings(rings)


## The banner row's hit states, and while a hit's motion plays its marker beside each living
## target (on the side the enemy stands) and, for a ground hit, the floor warning under them.
func _update_reading(t: int) -> void:
	var t_ms := float(t) / 1000.0
	var states := HitRhythm.states(_hits, t_ms, _visuals)
	# Once the first hit lands, the rest of the string is from memory (tuning
	# hide_intent_after_first_hit): no hit row, no markers; the enemy's motion and the floor
	# warning still show each hit.
	var hidden := _tuning.hide_intent_after_first_hit and not _hits.is_empty() and t_ms >= float(_hits[0].at_ms)
	_hud.set_banner_hit_states(states)
	_hud.show_banner_hits(not hidden)
	var markers: Array[Dictionary] = []
	var warning := 0.0
	var active := HitRhythm.active_hit(states)
	var warned: Array[int] = _hit_targets[active] if active >= 0 else ([] as Array[int])
	# The floor warning under a ground hit always shows (the enemy's own tell); the hit markers
	# only with their toggle (off by default since phase 6).
	if active >= 0:
		var hit: Dictionary = _hits[active]
		var kind := int(hit.kind)
		var ground := kind == AttackHitData.Kind.GROUND
		var start := EnemyChoreography.motion_start(_hits, active, _visuals)
		var pop := clampf((t_ms - start) / maxf(1.0, float(_visuals.hit_marker_pop_ms)), 0.0, 1.0)
		var px := _visuals.hit_marker_px * lerpf(_visuals.hit_marker_pop_scale, 1.0, 1.0 - (1.0 - pop) * (1.0 - pop))
		if ground:
			var progress := clampf((t_ms - start) / maxf(1.0, float(hit.at_ms) - start), 0.0, 1.0)
			warning = _visuals.floor_warning_strength * lerpf(WARNING_START_SHARE, 1.0, progress)
		var enemy := _view.fighter(_source)
		for id: int in ([] as Array[int]) if hidden or not _options.hit_markers else _living_of(warned):
			var view := _view.fighter(id)
			# The standing middle of the body: a jump does not carry the marker up.
			var centre := _view.screen_position(view.centre_position() - Vector3(0.0, view.body_offset.y, 0.0))
			var side := 1.0
			if enemy != null and _view.screen_position(enemy.global_position).x < centre.x:
				side = -1.0
			markers.append({
				"pos": centre + Vector2(_visuals.hit_marker_offset_px.x * side, _visuals.hit_marker_offset_px.y),
				"size": px,
				"texture": _hud.hit_icon(kind, EnemyChoreography.is_ranged(hit)),
				"color": _visuals.kind_color(kind, _visuals.normal_hit_color),
				"label": HudStyle.kind_label(kind),
			})
	_hud.set_hit_markers(markers)
	# The moment a ground hit arrives, the warning under its targets flashes bright (card #114).
	var flash := 0.0
	var flashed: Array[int] = []
	for i: int in _hits.size():
		var hit: Dictionary = _hits[i]
		var since := t_ms - float(hit.at_ms)
		if int(hit.kind) == AttackHitData.Kind.GROUND and since >= 0.0 and since < float(_visuals.floor_flash_ms):
			flash = 1.0 - since / maxf(1.0, float(_visuals.floor_flash_ms))
			flashed = _hit_targets[i]
	for id: int in _mirror.party_ids:
		var view := _view.fighter(id)
		if view != null:
			var shown := 0.0
			if _mirror.is_alive(id):
				shown = maxf(warning if warned.has(id) else 0.0, flash if flashed.has(id) else 0.0)
			view.set_floor_warning(shown, _visuals.ground_hit_color)


## The ranged-hit indicators (DESIGN.md 3.9, card #165): for each hero a projectile flies at, four
## brackets that close in and meet exactly at the hit's declared impact (the time the defence is
## judged on) and a dashed path from the projectile to the hero, in the hit's kind colour. Pure
## functions of attack time (RangedAim), so hit-stop freezes them with the projectile.
func _update_ranged_aims(t: int) -> void:
	if _projectile_of.is_empty() or not _tuning.show_ranged_aim:
		_hud.set_ranged_aims([])
		return
	var t_ms := float(t) / 1000.0
	var aims: Array[Dictionary] = []
	var enemy := _view.fighter(_source)
	var pulse_scale := _visuals.screen_flash_scale(PlayerSettings.flash_mode())
	for hit_index: int in _projectile_of:
		var data: ProjectileData = _projectile_of[hit_index]
		var hit: Dictionary = _hits[hit_index]
		var kind := int(hit.kind)
		var launch := EnemyChoreography.motion_start(_hits, hit_index, _visuals)
		var impact := float(hit.at_ms)
		for id: int in _living_of(_hit_targets[hit_index]):
			var key := _projectile_key(hit_index, id)
			# A defended or landed hit ends the indicator at its decision, never before the impact.
			var end := impact + float(hit.get("close_ms", 0.0))
			if _projectile_ends.has(key):
				end = maxf(impact, float((_projectile_ends[key] as Dictionary).at_us) / 1000.0)
			var s := RangedAim.state(t_ms, launch, impact, end, float(_visuals.ranged_aim_lead_ms),
					float(_visuals.ranged_aim_fade_ms))
			if not bool(s.shown):
				continue
			var to := _standing_centre(id)
			var from: Vector3 = _projectile_starts.get(key, _launch_point(enemy, data, id))
			var points := PackedVector2Array()
			var steps := maxi(1, _visuals.ranged_aim_path_points)
			for k: int in steps + 1:
				var u := lerpf(float(s.progress), 1.0, float(k) / float(steps))
				points.append(_view.screen_position(_arc(from, to, u, data.arc_height)))
			var pulse := RangedAim.lock_pulse(t_ms, impact, float(_visuals.ranged_aim_pulse_ms)) * pulse_scale
			aims.append({
				"center": _view.screen_position(to),
				"half": RangedAim.radius_px(float(s.progress), _visuals.ranged_aim_start_px, _visuals.ranged_aim_end_px),
				"color": _visuals.kind_color(kind, _visuals.normal_hit_color),
				"alpha": float(s.alpha),
				"path": points,
				"path_strength": _visuals.ranged_aim_path_strength,
				"locked": bool(s.locked),
				"pulse": pulse,
				"label": HudStyle.kind_label(kind) if _visuals.ranged_aim_label else "",
				"line_px": _visuals.ranged_aim_line_px,
				"dash_px": _visuals.ranged_aim_dash_px,
				"gap_px": _visuals.ranged_aim_gap_px,
			})
	_hud.set_ranged_aims(aims)


## A lock icon at the feet of each locked-out player's heroes.
func _update_lock(t: int) -> void:
	var spots: Array[Vector3] = []
	for player: int in _judges.players():
		var defenders := _living_targets_of(player)
		if _judges.is_locked_out(player, t) and not defenders.is_empty():
			spots.append(_focus_feet(defenders))
	_hud.set_locks(spots)


## Hands the tail back once the local animation is over (DESIGN.md 4.5).
func _check_finish(now: int, t: int) -> void:
	# Wait for every contact effect of this attack (a jump's contact comes after impact).
	if not _tail_received or _clock.is_paused(now) or not _scheduled.is_empty():
		return
	if _has_counter:
		# The counter follows the final hit-stop after counter_delay_ms.
		if t < _last_impact_us():
			return
		if _counter_ready_us == 0:
			_counter_ready_us = maxi(now, _clock.last_pause_end_us()) + _tuning.counter_delay_ms * 1000
		if now >= _counter_ready_us:
			_hand_back()
		return
	var end_at := _last_impact_us() if _end_reason == "completed" else _tail_t_us
	if t >= end_at + _tuning.attack_recover_ms * 1000:
		_hand_back()


func _hand_back() -> void:
	_active = false
	_take_held_players()
	_last_attack_longest_us = _longest_frame_us
	_input.disarm()
	_hud.hide_banner()
	_hud.set_defending(false)
	_hud.set_rings([])
	_hud.set_hit_markers([])
	_hud.set_ranged_aims([])
	_hud.set_locks([])
	_hud.set_targeted([])
	_hud.set_target_arrows([])
	_view.hide_wave()
	_wave_hit = -1
	# Projectiles and rocks still flying or sinking keep playing (_process draws them until done).
	var return_s := float(_tuning.action_return_ms) / 1000.0
	for id: int in _mirror.party_ids:
		var view := _view.fighter(id)
		if view == null:
			continue
		view.set_tint(Color.WHITE)
		view.set_floor_warning(0.0, _visuals.ground_hit_color)
		if view.body_offset == Vector3.ZERO or not _mirror.is_alive(id):
			view.move_body(Vector3.ZERO, 0.0)
		else:
			# Bystanders walk back and jumpers come down; a counter dash replaces this movement.
			view.move_body(Vector3.ZERO, return_s, Tween.TRANS_QUAD, Tween.EASE_OUT)
	var tail: Array[Dictionary] = _tail.duplicate()
	_tail.clear()
	finished.emit(tail)


# --- helpers ----------------------------------------------------------------------------------

## Copies each hit's animation prefix (AttackHitData.anim), projectile and ground look into this
## machine's hit list. They are presentation only: never part of the engine's events.
func _add_hit_anims(attack: EnemyAttackData) -> void:
	_projectile_of.clear()
	if attack == null:
		return
	EnemyChoreography.add_hit_data(_hits, attack)
	for i: int in _hits.size():
		var index := int((_hits[i] as Dictionary).get("index", -1))
		if EnemyChoreography.is_ranged(_hits[i]) and index >= 0 and index < attack.hits.size():
			_projectile_of[i] = attack.hits[index].projectile


## The attacker's idle loop on attack time: the view's real-time loop (same cycle and phase)
## carried on from the clock start, so the switch is seamless and hit-stops freeze it.
func _set_idle_loop(enemy: EnemyData) -> void:
	var idle_percent := maxi(1, enemy.idle_cycle_percent if enemy != null else 100)
	_idle_period_ms = float(maxi(1, CombatMath.percent(_visuals.enemy_idle_cycle_ms, idle_percent)))
	_idle_phase_ms = ClipMath.phase_for(_source, _idle_period_ms) + float(_lead_in_end_us) / 1000.0


## Starts the defence pose and returns the attack time of its contact moment (sound, popup,
## hit-stop): the impact, or the press if later; for a jump also not before the body is clear
## of the wave, so the freeze never shows a successful jump standing in it.
func _start_defence_anim(id: int, action: int, t: int, impact_us: int, late_us: int) -> int:
	var hold_until := impact_us + late_us
	var contact := maxi(t, impact_us)
	match action:
		Defense.Outcome.PARRY:
			_anims[id] = {"kind": Anim.PARRY, "frame": FighterView.CharPose.PARRY, "from_us": t,
					"until_us": maxi(hold_until, t + _visuals.parry_pose_min_ms * 1000)}
		Defense.Outcome.DODGE:
			_anims[id] = {"kind": Anim.DODGE, "frame": FighterView.CharPose.DODGE, "from_us": t,
					"until_us": maxi(hold_until, t + _visuals.dodge_pose_min_ms * 1000)}
		Defense.Outcome.JUMP:
			# Apex at impact when the press leaves time for it (up to half the airtime), else the
			# fastest rise; the whole jump lasts about jump_airtime_ms.
			var fast := _visuals.jump_rise_fast_ms * 1000
			var rise := clampi(impact_us - t, fast, maxi(fast, _visuals.jump_airtime_ms * 500))
			var apex := t + rise
			var fall := maxi(_visuals.jump_airtime_ms * 1000 - rise, fast)
			_anims[id] = {"kind": Anim.JUMP, "frame": FighterView.CharPose.JUMP, "from_us": t,
					"until_us": apex + fall, "apex_us": apex, "land_us": apex + fall}
			# The rise y = 1 - (1 - u)^2 reaches JUMP_CLEAR_HEIGHT at u = 1 - sqrt(1 - JUMP_CLEAR_HEIGHT).
			contact = maxi(contact, t + roundi(float(rise) * (1.0 - sqrt(1.0 - JUMP_CLEAR_HEIGHT))))
	# The parry clip turns into its hit frames at this moment (PartyAnim).
	if _anims.has(id):
		(_anims[id] as Dictionary)["contact_us"] = contact
	return contact


## Arrows over the targets from the banner until the enemy starts moving.
func _update_target_arrows(t: int) -> void:
	var heads: Array[Vector3] = []
	if t < _first_motion_us:
		for id: int in _living_targets():
			heads.append(_view.fighter(id).head_position())
	_hud.set_target_arrows(heads)


func _pose_for_action(action: int) -> int:
	match action:
		Defense.Outcome.PARRY:
			return FighterView.CharPose.PARRY
		Defense.Outcome.DODGE:
			return FighterView.CharPose.DODGE
		Defense.Outcome.JUMP:
			return FighterView.CharPose.JUMP
	return FighterView.CharPose.READY


## True if `player` pressed between the earliest window edge of this prompt and now (press times
## compensated the way the judge compensates them).
func _pressed_near(prompt: Dictionary, player: int) -> bool:
	var earliest := 0
	for action: int in (prompt.windows as Dictionary):
		earliest = mini(earliest, int((prompt.windows[action] as Array)[0]))
	var from := int(prompt.at_ms) * 1000 + earliest
	for press: Dictionary in _press_times:
		if int(press.player) == player and int(press.t) - latency_us() >= from:
			return true
	return false


func _any_pending(idxs: Array) -> bool:
	for idx: int in idxs:
		if _is_pending(idx):
			return true
	return false


func _is_pending(idx: int) -> bool:
	if _mirror.sequence.is_empty() or int(_mirror.sequence.seq) != _seq:
		return false
	var states: Array = _mirror.sequence.states
	return idx >= 0 and idx < states.size() and int(states[idx]) == CombatEngine.PromptState.PENDING


## The living targets player `player` defends.
func _living_targets_of(player: int) -> Array[int]:
	var list: Array[int] = []
	for id: int in _living_targets():
		if int(_owners.get(id, 0)) == player:
			list.append(id)
	return list


func _living_targets() -> Array[int]:
	var list: Array[int] = []
	for id: int in _targets:
		if _mirror.is_alive(id):
			list.append(id)
	return list


## The middle of these fighters' feet (standing, ignoring jumps), for the lock icon.
func _focus_feet(ids: Array[int]) -> Vector3:
	var list := ids if not ids.is_empty() else _mirror.party_ids
	var sum := Vector3.ZERO
	var count := 0
	for id: int in list:
		var view := _view.fighter(id)
		if view != null:
			var feet := view.body_position()
			feet.y = 0.0
			sum += feet
			count += 1
	return sum / float(maxi(1, count))


## Above the middle of these fighters' standing heads (the party centre if the list is empty).
## Ignores a jump's lift, so a jump readout starts where a parry readout does.
func _focus_head(ids: Array[int]) -> Vector3:
	var list := ids if not ids.is_empty() else _mirror.party_ids
	var sum := Vector3.ZERO
	var count := 0
	for id: int in list:
		var view := _view.fighter(id)
		if view != null:
			sum += view.head_position() - Vector3(0.0, view.body_offset.y, 0.0)
			count += 1
	return sum / float(maxi(1, count))


## The first and last party slots' homes: the line ground waves travel toward.
func _party_line() -> Array[Vector3]:
	var ids := _mirror.party_ids
	var line: Array[Vector3] = [_contact, _contact]
	if ids.is_empty():
		return line
	line[0] = _view.home_of(ids[0])
	line[1] = _view.home_of(ids[ids.size() - 1])
	return line


func _last_impact_us() -> int:
	if _hits.is_empty():
		return 0
	return int((_hits[_hits.size() - 1] as Dictionary).at_ms) * 1000


## The banner's small line: who attacks whom ("GNAT SWARM  >  CASS > ALDER"). The marks a hit leaves
## show as icons on the banner's hits, not as words here (phase 22).
func _banner_text() -> String:
	var enemy_name := String(_mirror.fighter(_source).get("display_name", "?"))
	var target_text := CombatHud.target_text(_mirror, int(_event.get("mode", 0)), _targets)
	return "%s  >  %s" % [enemy_name.to_upper(), target_text]


func _each_in_turn() -> bool:
	return int(_event.get("mode", 0)) == EnemyAttackData.TargetMode.EACH


func _ground_look(hit_index: int) -> int:
	if hit_index < 0 or hit_index >= _hits.size():
		return AttackHitData.GroundLook.WAVE
	return int((_hits[hit_index] as Dictionary).get("ground_look", AttackHitData.GroundLook.WAVE))


## The enemy's flat offset from home to where sample `s` is headed. Each hero in turn: a lunge
## swings over from the previous hit's target to its own, so the enemy never jumps sideways.
func _enemy_travel(s: Dictionary, home: Vector3) -> Vector3:
	var hit_index := clampi(int(s.get("hit", 0)), 0, maxi(0, _hit_contacts.size() - 1))
	var to := (_hit_contacts[hit_index] if not _hit_contacts.is_empty() else _contact) - home
	if _each_in_turn() and hit_index > 0:
		var share := -1.0
		match int(s.get("beat", -1)):
			EnemyChoreography.Beat.WINDUP, EnemyChoreography.Beat.FEINT_HOLD:
				share = 0.0
			EnemyChoreography.Beat.FEINT_START, EnemyChoreography.Beat.LUNGE:
				share = float(s.get("beat_u", 0.0))
		if share >= 0.0:
			to = (_hit_contacts[hit_index - 1] - home).lerp(to, share * share * (3.0 - 2.0 * share))
	to.y = 0.0
	return to


func _projectile_key(hit_index: int, id: int) -> String:
	return "%d:%d" % [hit_index, id]


## The middle of a hero's body where they stand (a dodge or a jump does not move it).
func _standing_centre(id: int) -> Vector3:
	var view := _view.fighter(id)
	if view == null:
		return _contact
	return view.centre_position() - view.body_offset


## Every projectile on screen at attack time `t`: in flight from launch to impact (with its trail),
## held on the hero until the hit is decided, then bounced back off a parry or flying on past a
## dodge, fading. A hit bursts (sparks in _land_hit) and is gone.
func _update_projectiles(t: int) -> void:
	if _projectile_of.is_empty():
		return
	var list: Array[Dictionary] = []
	var t_ms := float(t) / 1000.0
	var enemy := _view.fighter(_source)
	for hit_index: int in _projectile_of:
		var data: ProjectileData = _projectile_of[hit_index]
		var launch := EnemyChoreography.motion_start(_hits, hit_index, _visuals)
		if t_ms < launch:
			continue
		var impact := float((_hits[hit_index] as Dictionary).at_ms)
		var flight := maxf(1.0, impact - launch)
		var frame := int(floor((t_ms - launch) / maxf(1.0, float(data.loop_ms)) * float(data.hframes)))
		for id: int in (_hit_targets[hit_index] as Array[int]):
			var key := _projectile_key(hit_index, id)
			if not _projectile_starts.has(key):
				_projectile_starts[key] = _launch_point(enemy, data, id)
			var from: Vector3 = _projectile_starts[key]
			var to := _standing_centre(id)
			var u := (t_ms - launch) / flight
			if u <= 1.0:
				for k: int in range(data.trail_count, 0, -1):
					var tu := u - float(k * data.trail_gap_ms) / flight
					if tu > 0.0:
						list.append(_projectile_entry(data, frame, _arc(from, to, tu, data.arc_height),
								TRAIL_ALPHA / float(k), 1.0 - TRAIL_SHRINK * float(k)))
				list.append(_projectile_entry(data, frame, _arc(from, to, u, data.arc_height), 1.0, 1.0))
				continue
			var ending: Dictionary = _projectile_ends.get(key, {})
			if ending.is_empty():
				# Arrived, not decided yet (the late window is still open): it waits on the hero. A
				# hero already down (their prompt was voided) or a result that never came: it is gone.
				var close := float((_hits[hit_index] as Dictionary).get("close_ms", 0.0))
				if _mirror.is_alive(id) and t_ms <= impact + close + float(_visuals.projectile_pass_ms):
					list.append(_projectile_entry(data, frame, to, 1.0, 1.0))
				continue
			var kind := int(ending.kind)
			if kind < 0:
				continue
			var since := float(t - int(ending.at_us)) / 1000.0
			var back := from - to
			back.y = 0.0
			back = back.normalized() if back.length() > 0.0 else Vector3.RIGHT
			if kind == Defense.Outcome.PARRY:
				var v := since / maxf(1.0, float(_visuals.projectile_deflect_ms))
				if v < 1.0:
					var pos := to + back * _visuals.projectile_deflect_distance * v \
							+ Vector3.UP * _visuals.projectile_deflect_rise * sin(v * PI * 0.5)
					list.append(_projectile_entry(data, frame, pos, 1.0 - v, 1.0))
			else:
				var v := since / maxf(1.0, float(_visuals.projectile_pass_ms))
				if v < 1.0:
					list.append(_projectile_entry(data, frame, to - back * _visuals.projectile_pass_distance * v,
							1.0 - v, 1.0))
	_view.set_projectiles(list)
	_projectiles_drawn = list.size()


func _projectile_entry(data: ProjectileData, frame: int, pos: Vector3, alpha: float, size: float) -> Dictionary:
	return {"path": data.texture_path, "hframes": data.hframes, "frame": posmod(frame, maxi(1, data.hframes)),
			"pixel_size": data.pixel_size, "pos": pos, "alpha": alpha, "scale": size}


## Where a projectile leaves the enemy: its centre, moved toward the target and up.
func _launch_point(enemy: FighterView, data: ProjectileData, target: int) -> Vector3:
	if enemy == null:
		return _contact
	var centre := enemy.centre_position()
	var toward := _standing_centre(target) - centre
	toward.y = 0.0
	toward = toward.normalized() if toward.length() > 0.0 else Vector3.LEFT
	return centre + toward * data.launch_offset.x + Vector3.UP * data.launch_offset.y


## A point on a projectile's path at progress `u`: a straight line plus a lift that peaks halfway.
static func _arc(from: Vector3, to: Vector3, u: float, height: float) -> Vector3:
	return from.lerp(to, u) + Vector3.UP * height * 4.0 * u * (1.0 - u)


## Rock ground hits at attack time `t`: along a lane from the slam to each target, rows of rocks
## burst out one after another (the front moves at the hit's travel speed) and the last row bursts
## under the target exactly at impact; each rock rises, stands and sinks (DESIGN.md 3.10).
func _update_rocks(t: int) -> void:
	if _rock_starts.is_empty():
		return
	var t_ms := float(t) / 1000.0
	var list: Array[Dictionary] = []
	var spacing := maxf(0.05, _visuals.rock_row_spacing)
	for hit_index: int in _rock_starts:
		var hit: Dictionary = _hits[hit_index]
		var launch := EnemyChoreography.motion_start(_hits, hit_index, _visuals)
		var impact := float(hit.at_ms)
		var travel := maxf(1.0, impact - launch)
		var final_end := impact + float(hit.get("close_ms", 0.0))
		var start: Vector3 = _rock_starts[hit_index]
		start.y = 0.0
		for id: int in (_hit_targets[hit_index] as Array[int]):
			var feet := _view.home_of(id)
			feet.y = 0.0
			var lane := feet - start
			var length := lane.length()
			if length <= 0.001:
				continue
			var dir := lane / length
			var side := Vector3(dir.z, 0.0, -dir.x)
			var rows := int(floor(length / spacing))
			for row: int in range(rows, -1, -1):
				# Row 0 stands at the target; row n is n spacings back toward the enemy.
				var dist := length - float(row) * spacing
				if dist < spacing * 0.5:
					continue
				var erupt := launch + travel * dist / length
				var stand_until := final_end if row == 0 else erupt + float(_visuals.rock_rise_ms + _visuals.rock_hold_ms)
				var height := _rock_height(t_ms, erupt, stand_until)
				if height <= 0.0:
					continue
				var count := _visuals.rock_final_count if row == 0 else 1
				var size := _visuals.rock_final_scale if row == 0 else 1.0
				for k: int in count:
					var scatter := _visuals.rock_scatter * (1.0 if row % 2 == 0 else -1.0)
					if count > 1:
						# The last row fans out in front of the hero, across the lane.
						scatter = _visuals.rock_scatter * FINAL_ROW_SPREAD * (float(k) / float(count - 1) - 0.5)
					var pos := start + dir * (dist - (_visuals.rock_scatter if row == 0 else 0.0)) + side * scatter
					list.append({"pos": pos, "height": height, "frame": row * 3 + k + id, "scale": size})
	_view.set_rocks(list)
	_rocks_drawn = list.size()


## A rock's height share at attack ms `t`: rises from `erupt`, stands until `stand_until`, sinks.
func _rock_height(t: float, erupt: float, stand_until: float) -> float:
	if t < erupt:
		return 0.0
	var rise := maxf(1.0, float(_visuals.rock_rise_ms))
	if t < erupt + rise:
		var u := (t - erupt) / rise
		return 1.0 - (1.0 - u) * (1.0 - u)
	var hold_end := maxf(stand_until, erupt + rise)
	if t < hold_end:
		return 1.0
	var sink := maxf(1.0, float(_visuals.rock_sink_ms))
	return clampf(1.0 - (t - hold_end) / sink, 0.0, 1.0)


func _living_of(ids: Array[int]) -> Array[int]:
	var list: Array[int] = []
	for id: int in ids:
		if _mirror.is_alive(id):
			list.append(id)
	return list
