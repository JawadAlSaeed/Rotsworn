class_name CombatController
extends Node
## Runs one fight (DESIGN.md 4). Owns the CombatEngine, keeps an event queue and plays the events
## one by one through the view and HUD, applying each to the CombatMirror at the moment it is
## played (so bars change with the animation). Enemy attacks are handed to the
## TimedSequenceRunner, party skills to the SkillSequenceRunner. Everything shown is read from the
## mirror and static data, never from the engine; the only way presentation changes the fight is
## submit() here.
## No SceneTree.paused and no Engine.time_scale anywhere: waits use Timers, hit-stop is the
## AttackClock.
##
## Online (DESIGN.md 9.2): the HOST runs the only engine. Every batch of events it makes is sent
## to the clients ("flow" batches go to the event queue, "timing" batches to the runner playing
## that sequence). A client's player commands (its heroes' menu choices, its prompt results) come
## to the host, which checks them (only its own heroes; prompt results through the
## DefenseArbiter) before submitting. A CLIENT has no engine: it plays the batches the host sends
## and sends its commands to the host. A batch for a sequence this machine has not started yet
## waits until it does.

signal restart_requested
## Back to the fight list (end screen, Cancel).
signal select_requested
## A fight that started in a zone or a run is over and the player wants to go on (back to the
## zone, or on with the run; DESIGN.md 7.4, 8).
signal continue_requested(result: String)
## Every event as it is played (and the prompt events the runner applies at once).
signal event_played(event: Dictionary)
## The action menu opened for this party member.
signal menu_opened(actor_id: int)
signal combat_finished(result: String)
## A pause asked for with request_pause() can start now: nothing is being timed. Main stops this
## node (process disabled) and shows the pause menu; resume_after_pause() goes on.
signal pause_reached

enum NetMode { LOCAL, HOST, CLIENT }

const QUIT_DELAY_S: float = 1.0
## After stopping all sounds, quitting waits this long (real time) so the audio server lets go of
## the playbacks; two frames are not enough and Godot reports "resources still in use at exit".
const QUIT_AUDIO_RELEASE_S: float = 0.3
const PRACTICE_ATTACK_KEYS: Array[Key] = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5]
const PRACTICE_KEYS_PER_LINE: int = 3
## Autoplay: a fight where nothing was played for this long is stuck (its state is printed once).
const AUTOPLAY_STUCK_MS: int = 60000
## Strike clips of a dash strike or counter, by the striker's place among the attackers.
const STRIKE_CLIPS: Array[String] = ["strike", "strike_alt"]
## Damage causes that stagger the target whatever the amount (DESIGN.md 5.5).
const STAGGER_CAUSES: Array[String] = ["counter", "team_counter"]

var mirror := CombatMirror.new()
var engine: CombatEngine
var view: CombatView
var hud: CombatHud
var runner: TimedSequenceRunner
var skill_runner: SkillSequenceRunner
var defense_input: DefenseInput
var autoplay: Autoplay

## The song for the boss once it rages (set by Main from MusicSet; empty: no change).
var rage_music_path: String = ""
var rage_music_volume_db: float = 0.0

var _encounter: EncounterData
var _tuning: Tuning
var _visuals: CombatVisuals
var _options: CombatOptions
## The place the fight happens in (null: the fight list's look), how it starts, and whether it
## started in a zone (the end screen then goes back to the zone).
var _look: StageLook
var _opening: CombatSetup.Opening = CombatSetup.Opening.NORMAL
var _from_zone: bool = false
## The run this fight belongs to (null outside a run): it provides the party, its HP and the gold.
var _run: RunState
## Who plays (DESIGN.md 9.1): in co-op a device drives only its own heroes' menus and presses.
var _players: PlayerRoster = PlayerRoster.solo(3)
## Party member id -> co-op player.
var _owners: Dictionary = {}
var _net_mode: int = NetMode.LOCAL
## Online: the fight seed the host picked (-1: pick one here).
var _fight_seed: int = -1
## Host: the referee for clients' prompts.
var _arbiter: DefenseArbiter
## Online: timing batches for a sequence this machine has not started yet: [{seq, events}].
var _timing_inbox: Array[Dictionary] = []
## Client: the turn a party member waits for a choice in (-1: none), and the turn a choice was
## sent for (the menu stays shut until the host's answer arrives).
var _awaiting_turn: int = -1
var _sent_turn: int = -1
## Autoplay: when an event was last played (stuck check).
var _progress_ms: int = 0
var _stuck_reported: bool = false
var _setup: CombatSetup
var _result: String = ""
var _queue: Array[Dictionary] = []
var _playing: bool = false
var _waiting_runner: bool = false
var _ended: bool = false
var _ended_at_us: int = 0
var _menu_turn: int = -1
## Pause (DESIGN.md 6): asked for, and reached (the event queue holds still).
var _pause_pending: bool = false
var _paused: bool = false
## This fight's numbers for the end screen: successful presses per Defense.Outcome (one press
## answering three characters counts once), enemy hits as distinct "seq:hit" keys, counters.
var _defended: Dictionary = {}
var _enemy_hits: Dictionary = {}
var _counters: int = 0
## Combatant id -> CharacterData or EnemyData.
var _data_by_id: Dictionary = {}
## Ability id -> AbilityData.
var _abilities: Dictionary = {}
## Enemy attack id -> EnemyAttackData (for its training ring speed).
var _attacks: Dictionary = {}


## Call before adding the node to the tree. `look` null uses the fight list's look.
func configure(encounter: EncounterData, tuning: Tuning, visuals: CombatVisuals, options: CombatOptions,
		look: StageLook = null, opening: CombatSetup.Opening = CombatSetup.Opening.NORMAL,
		from_zone: bool = false) -> void:
	_encounter = encounter
	_tuning = tuning
	_visuals = visuals
	_options = options
	_look = look
	_opening = opening
	_from_zone = from_zone


## Makes this a run fight (DESIGN.md 8): the run's party with its carried-over HP, gold on the end
## screen, and no "fight again". Call after configure(), before adding the node to the tree.
func configure_run(run: RunState) -> void:
	_run = run


## The players and their heroes. Call before adding the node to the tree (default: solo).
func configure_players(players: PlayerRoster) -> void:
	_players = players


## Online play (DESIGN.md 9.2): HOST runs the engine and talks to the clients, CLIENT plays what
## the host sends. `fight_seed` is the host's seed (both sides build the same setup from it).
func configure_online(mode: NetMode, fight_seed: int) -> void:
	_net_mode = mode
	_fight_seed = fight_seed


## Online host: someone left or the roster changed mid-fight. Their heroes' menus and presses go
## to the new owner from now on; their open prompts are resolved by the arbiter at once.
func update_players(players: PlayerRoster, gone_peer: int = -1) -> void:
	_players = players
	_owners.clear()
	for id: int in mirror.party_ids:
		_owners[id] = _players.owner_of(_owner_slot(id))
	runner.set_players(_players, _owners)
	skill_runner.set_players(_players, _owners)
	if autoplay != null:
		autoplay.set_players(_players, _owners)
	hud.set_player_tags(_owners if _players.is_coop() else {})
	if _arbiter != null and gone_peer > 0:
		_arbiter.drop_peer(gone_peer)
	_menu_turn = -1
	if not _playing and _queue.is_empty() and not _waiting_runner:
		_maybe_open_menu()


## Online: a batch of events from the host ({kind, seq, events}).
func receive_batch(payload: Dictionary) -> void:
	if _net_mode != NetMode.CLIENT or not payload.get("events") is Array:
		return
	var events: Array[Dictionary] = []
	for ev: Variant in payload.events:
		if ev is Dictionary:
			events.append(ev as Dictionary)
	if String(payload.get("kind", "")) == "timing":
		_route_timing(int(payload.get("seq", -1)), events)
	else:
		_enqueue(events)


## Online host: a command from client `peer`. Only its own heroes' choices and prompt results are
## taken; anything else is dropped.
func receive_command(peer: int, command: Dictionary) -> void:
	if _net_mode != NetMode.HOST or engine == null or _ended:
		return
	var player := _players.player_of_peer(peer)
	match String(command.get("type", "")):
		CombatCommands.USE_ABILITY:
			var actor := int(command.get("actor", -1))
			if engine.phase != CombatEngine.Phase.AWAITING_ACTION or actor != engine.active_actor \
					or player < 0 or _players.owner_of(_owner_slot(actor)) != player:
				return
			var targets: Array[int] = []
			if command.get("targets") is Array:
				for t: Variant in command.targets:
					targets.append(int(t))
			_enqueue(_submit(CombatCommands.use_ability(int(command.get("turn", -1)), actor,
					String(command.get("ability", "")), targets)))
		CombatCommands.RESOLVE_PROMPTS:
			if engine.phase != CombatEngine.Phase.AWAITING_TIMING or not command.get("results") is Array:
				return
			var seq := int(command.get("seq", -1))
			_submit_remote_results(seq, _arbiter.accept(peer, seq, command.results as Array))


## Online host: a client started playing sequence `seq`.
func receive_ack(peer: int, seq: int) -> void:
	if _arbiter != null:
		_arbiter.ack(peer, seq, Time.get_ticks_usec())


## Each party member's HP right now, by slot (the run carries it to the next fight).
func party_hp() -> Array[int]:
	var list: Array[int] = []
	list.resize(mirror.party_ids.size())
	for id: int in mirror.party_ids:
		var f := mirror.fighter(id)
		var slot := int(f.slot)
		if slot >= 0 and slot < list.size():
			list[slot] = int(f.hp)
	return list


func _ready() -> void:
	_progress_ms = Time.get_ticks_msec()
	defense_input = DefenseInput.new()
	defense_input.name = "DefenseInput"
	add_child(defense_input)

	view = CombatView.new()
	view.name = "View"
	add_child(view)
	view.build(_visuals, _look)
	view.camera.cinematic = _options.cinematic_camera

	hud = CombatHud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.setup(view, _visuals, _tuning)
	hud.action_menu.chosen.connect(_on_ability_chosen)
	hud.action_menu.run_hold_ms = _tuning.run_hold_ms
	hud.action_menu.target_changed.connect(_on_target_changed)
	hud.calibration.setup(_visuals, _tuning, defense_input)

	runner = TimedSequenceRunner.new()
	runner.name = "SequenceRunner"
	add_child(runner)
	runner.setup(_submit, _apply_now, mirror, view, hud, _tuning, _visuals, _options, defense_input)
	runner.finished.connect(_on_runner_finished)
	runner.press_judged.connect(_on_press_judged)
	runner.sequence_started.connect(_on_sequence_started)

	skill_runner = SkillSequenceRunner.new()
	skill_runner.name = "SkillRunner"
	add_child(skill_runner)
	skill_runner.setup(_submit, _apply_now, mirror, view, hud, _tuning, _visuals, _options, defense_input)
	skill_runner.finished.connect(_on_runner_finished)
	skill_runner.press_judged.connect(_on_press_judged)
	skill_runner.sequence_started.connect(_on_sequence_started)

	if _options.is_autoplay():
		autoplay = Autoplay.new()
		autoplay.name = "Autoplay"
		autoplay.setup(_options.autoplay_mode, mirror, runner, skill_runner, defense_input, hud.action_menu, _tuning)
		autoplay.bot_skill = _options.bot_skill
		add_child(autoplay)
		runner.press_judged.connect(autoplay.on_press_judged)
		skill_runner.press_judged.connect(autoplay.on_press_judged)
		event_played.connect(autoplay.on_event)
		menu_opened.connect(autoplay.on_menu_opened)
		combat_finished.connect(autoplay.on_combat_finished)

	var setup := _run.fight_setup(_encounter, _pick_seed(), _opening) if _run != null 			else CombatSetup.from_encounter(_encounter, _tuning, _pick_seed(), _opening)
	_setup = setup
	setup.allow_practice = _tuning.practice_tools_enabled or _options.is_autoplay()
	# A run is the real game: no training ring there (practice fights may still use it, F1 > R).
	runner.training_ring_allowed = _run == null
	print("Combat seed: %d  encounter: %s  opening: %s" % [setup.rng_seed, _encounter.id,
			CombatEngine.OPENING_NAMES[setup.opening]])
	for data: CharacterData in setup.party:
		for ability: AbilityData in data.all_abilities():
			_abilities[ability.id] = ability
	if setup.team_ultimate != null:
		_abilities[setup.team_ultimate.id] = setup.team_ultimate
	if setup.can_run and setup.run_ability != null:
		_abilities[setup.run_ability.id] = setup.run_ability
	for enemy: EnemyData in setup.enemies:
		for attack: EnemyAttackData in enemy.attacks:
			_attacks[attack.id] = attack
	_warm_up_assets(setup)
	if _net_mode == NetMode.CLIENT:
		# No engine here: the host's batches arrive through receive_batch().
		return
	engine = CombatEngine.new(setup)
	if _net_mode == NetMode.HOST:
		# A client's clock pauses for hit-stops and its lag compensation shifts its presses: both
		# push its deadlines back.
		var hitstop := maxi(maxi(_tuning.hitstop_parry_final_ms, _tuning.hitstop_hurt_ms),
				maxi(_tuning.hitstop_jump_ms, _tuning.hitstop_press_ms))
		_arbiter = DefenseArbiter.new(_tuning.net_ack_timeout_ms, _tuning.net_deadline_grace_ms,
				hitstop + _tuning.calibration_max_ms)
	_enqueue(_submit_start())


func _process(_delta: float) -> void:
	if _options.is_autoplay() and not _ended and not _paused and not _stuck_reported 			and _progress_ms > 0 and Time.get_ticks_msec() - _progress_ms > AUTOPLAY_STUCK_MS:
		_stuck_reported = true
		_report_stuck()
	if _arbiter != null and not _ended:
		var due := _arbiter.overdue(Time.get_ticks_usec())
		if not due.is_empty():
			_submit_remote_results(_arbiter.seq(), due)
	hud.overlay.update_text(_options.stats, _tuning, _options, runner.longest_frame_ms(), _ended)


func _unhandled_input(event: InputEvent) -> void:
	if hud.calibration.is_running():
		hud.calibration.handle_input(event)
		get_viewport().set_input_as_handled()
		return
	var key := _pressed_key(event)
	if _ended:
		if event.is_action_pressed("debug_overlay", false, true):
			hud.overlay.toggle()
			get_viewport().set_input_as_handled()
			return
		# A defence press still in flight when the fight ends must not skip the end screen.
		if Time.get_ticks_usec() - _ended_at_us < _visuals.end_input_guard_ms * 1000:
			return
		if _net_mode == NetMode.CLIENT:
			# The host goes on for everyone.
			return
		if _from_zone or _run != null:
			if key == KEY_R and _run == null:
				get_viewport().set_input_as_handled()
				restart_requested.emit()
			elif event.is_action_pressed("menu_confirm", false, true) or event.is_action_pressed("menu_cancel", false, true):
				get_viewport().set_input_as_handled()
				continue_requested.emit(_result)
			return
		if event.is_action_pressed("menu_confirm", false, true) or key == KEY_R:
			get_viewport().set_input_as_handled()
			restart_requested.emit()
		elif event.is_action_pressed("menu_cancel", false, true):
			get_viewport().set_input_as_handled()
			select_requested.emit()
		return
	if _tuning.practice_tools_enabled and _net_mode == NetMode.LOCAL and _handle_practice(event, key):
		get_viewport().set_input_as_handled()
		return
	# In co-op only the acting hero's player drives the menu.
	if not _players.may_control(PlayerRoster.device_of(event), _owner_slot(mirror.active_actor)):
		return
	if hud.action_menu.handle_input(event):
		get_viewport().set_input_as_handled()


# --- engine access ----------------------------------------------------------------------------

## Submits a command and returns its events. A rejection must never happen: it is reported and
## dropped (never played).
func submit(command: Dictionary) -> Array[Dictionary]:
	return _submit(command)


func _submit(command: Dictionary) -> Array[Dictionary]:
	if _net_mode == NetMode.CLIENT:
		Net.send_to_host("cmd", {"command": command})
		return []
	var events := _keep_valid(engine.submit(command))
	if _net_mode == NetMode.HOST:
		var timing := String(command.get("type", "")) == CombatCommands.RESOLVE_PROMPTS
		_host_sent(events, "timing" if timing else "flow", int(command.get("seq", -1)))
	return events


func _submit_start() -> Array[Dictionary]:
	var events := _keep_valid(engine.start())
	if _net_mode == NetMode.HOST:
		_host_sent(events, "flow", -1)
	return events


## Host: sends a batch to the clients and keeps the arbiter up to date.
func _host_sent(events: Array[Dictionary], kind: String, seq: int) -> void:
	if events.is_empty():
		return
	Net.broadcast("combat", {"kind": kind, "seq": seq, "events": events})
	for ev: Dictionary in events:
		match String(ev.get("type", "")):
			"combat_started":
				# The first attack can come in this same batch, before the fighters are built.
				for f: Dictionary in ev.fighters:
					if int(f.team) == Combatant.Team.PARTY:
						_owners[int(f.id)] = _players.owner_of(int(f.slot))
			"timed_sequence_declared":
				var owners: Dictionary = {}
				for p: Dictionary in ev.prompts:
					var player := int(_owners.get(int(p.character), 0))
					if not _players.is_local(player) and player < _players.peers.size():
						owners[int(p.idx)] = _players.peers[player]
				var lead := _tuning.attack_lead_in_ms if String(ev.kind) == CombatEngine.SEQUENCE_ENEMY_ATTACK else 0
				_arbiter.declare(int(ev.seq), ev.prompts as Array, owners, lead, Time.get_ticks_usec())
			"prompt_resolved":
				_arbiter.mark_resolved([int(ev.prompt)])
			"prompts_voided":
				_arbiter.mark_resolved(ev.prompts as Array)
			"sequence_resolved":
				_arbiter.clear()


## Host: submits results that did not come from this machine's runner (a client's, or the
## arbiter's NONE). Only prompts still pending are sent, and a character's earlier prompts that
## are still open go as NONE with them (they are overdue), so the engine never refuses the batch.
func _submit_remote_results(seq: int, results: Array[Dictionary]) -> void:
	if engine == null or engine.sequence.is_empty() or int(engine.sequence.seq) != seq or results.is_empty():
		return
	var prompts: Array = engine.sequence.prompts
	var states: Array = engine.sequence.states
	var chosen: Dictionary = {}
	for r: Dictionary in results:
		var idx := int(r.get("prompt", -1))
		if idx >= 0 and idx < states.size() and int(states[idx]) == CombatEngine.PromptState.PENDING:
			chosen[idx] = CombatCommands.prompt_result(idx, int(r.get("outcome", Defense.Outcome.NONE)),
					int(r.get("offset_us", 0)))
	for idx: int in chosen.keys():
		var character := int((prompts[idx] as Dictionary).character)
		for j: int in idx:
			if int((prompts[j] as Dictionary).character) == character \
					and int(states[j]) == CombatEngine.PromptState.PENDING and not chosen.has(j):
				chosen[j] = CombatCommands.prompt_result(j, Defense.Outcome.NONE, 0)
	if chosen.is_empty():
		return
	var idxs: Array = chosen.keys()
	idxs.sort()
	var list: Array[Dictionary] = []
	for idx: int in idxs:
		list.append(chosen[idx])
	_route_timing(seq, _submit(CombatCommands.resolve_prompts(seq, list)))


## A timing batch goes to the runner playing its sequence, or waits until that sequence starts.
func _route_timing(seq: int, events: Array[Dictionary]) -> void:
	if events.is_empty():
		return
	if runner.is_active() and runner.current_seq() == seq:
		runner.take_events(events)
	elif skill_runner.is_active() and skill_runner.current_seq() == seq:
		skill_runner.take_events(events)
	else:
		_timing_inbox.append({"seq": seq, "events": events})


## A runner started sequence `seq`: hand it what already arrived; a client tells the host.
func _on_sequence_started(seq: int) -> void:
	if _net_mode == NetMode.CLIENT:
		Net.send_to_host("ack", {"seq": seq})
	var waiting := _timing_inbox.duplicate()
	_timing_inbox.clear()
	for batch: Dictionary in waiting:
		if int(batch.seq) == seq:
			_route_timing(seq, batch.events as Array[Dictionary])
		elif int(batch.seq) > seq:
			_timing_inbox.append(batch)


func _keep_valid(events: Array[Dictionary]) -> Array[Dictionary]:
	var kept: Array[Dictionary] = []
	for ev: Dictionary in events:
		if String(ev.get("type", "")) == "command_rejected":
			var details := "reason=%s command=%s" % [String(ev.get("reason", "?")), var_to_str(ev.get("command", {})).replace("\n", " ")]
			push_error("CombatController: command rejected: " + details)
			if _options.is_autoplay():
				print("AUTOPLAY_ERROR command_rejected " + details)
			continue
		kept.append(ev)
	return kept


# --- event playback ---------------------------------------------------------------------------

func _enqueue(events: Array[Dictionary]) -> void:
	for ev: Dictionary in events:
		# Practice toggles are not part of any animation; show them at once.
		if String(ev.get("type", "")) == "practice_changed":
			_apply_now(ev)
		else:
			_queue.append(ev)
	_pump()


func _pump() -> void:
	if _playing or _waiting_runner or _paused:
		return
	_playing = true
	while not _queue.is_empty():
		# A pause waits for a boundary between events, never inside an attack or a skill: their
		# timing runs on the real clock and cannot stop.
		if _pause_pending:
			_enter_pause()
			break
		var ev: Dictionary = _queue.pop_front()
		await _play(ev)
		if _waiting_runner:
			break
	_playing = false
	if _queue.is_empty() and not _waiting_runner and not _paused:
		_maybe_open_menu()
		if _pause_pending:
			_enter_pause()


## Asks to pause. Returns false if this fight cannot pause now (over, or calibrating). During an
## enemy attack or a skill the pause starts when it is done ("PAUSING AFTER THIS MOVE").
func request_pause() -> bool:
	if _ended or _paused or hud.calibration.is_running():
		return false
	_pause_pending = true
	if not _playing and not _waiting_runner:
		_enter_pause()
	else:
		hud.show_center_banner("PAUSING AFTER THIS MOVE", HudStyle.TEXT, _visuals.first_strike_banner_ms)
	return true


func is_paused() -> bool:
	return _paused


## Goes on after the pause menu closes (Main has re-enabled this node).
func resume_after_pause() -> void:
	_paused = false
	_pump()


func _enter_pause() -> void:
	_pause_pending = false
	_paused = true
	pause_reached.emit()


## Applies an event to the mirror right now (runner prompt events, practice changes) with its
## feedback (numbers, popups).
func _apply_now(ev: Dictionary) -> void:
	_progress_ms = Time.get_ticks_msec()
	mirror.apply(ev)
	match String(ev.get("type", "")):
		"downed":
			_show_downed(int(ev.target))
		"prompt_resolved":
			if String(mirror.sequence.get("kind", "")) == CombatEngine.SEQUENCE_ENEMY_ATTACK:
				_enemy_hits["%d:%d" % [int(ev.seq), int(ev.hit)]] = true
		"damage":
			_show_damage(ev)
		_:
			_show_feedback(ev)
	_refresh()
	event_played.emit(ev)


func _play(ev: Dictionary) -> void:
	_progress_ms = Time.get_ticks_msec()
	var type := String(ev.get("type", ""))
	match type:
		"combat_started":
			mirror.apply(ev)
			await _build_fighters()
			_play_draw()
			if String(ev.get("opening", "")) == "first_strike":
				Sfx.play("gauge_full")
				hud.show_center_banner("FIRST STRIKE!", HudStyle.GOLD, _visuals.first_strike_banner_ms)
			elif _encounter.boss:
				Sfx.play("alert")
				hud.show_center_banner(_encounter.display_name.to_upper(), HudStyle.LATE, _visuals.first_strike_banner_ms)
			else:
				Sfx.play("fight_start")
		"turn_started":
			mirror.apply(ev)
			if int(ev.team) == Combatant.Team.PARTY:
				Sfx.play("turn_start")
				_awaiting_turn = int(ev.turn)
		"ability_used":
			mirror.apply(ev)
			_awaiting_turn = -1
			_refresh()
			var used := _abilities.get(String(ev.ability)) as AbilityData
			# Skills with presses are animated by the SkillSequenceRunner.
			if used == null or used.press_times_ms.is_empty():
				await _play_party_action(ev)
		"counter":
			mirror.apply(ev)
			await _play_counter(ev)
		"damage":
			mirror.apply(ev)
			_show_damage(ev)
		"downed":
			mirror.apply(ev)
			_show_downed(int(ev.target))
		"ap_changed", "healed", "revived", "status_changed", "turn_shifted", "team_gauge", "enemy_phase", "escaped":
			mirror.apply(ev)
			_show_feedback(ev)
		"timed_sequence_declared":
			mirror.apply(ev)
			hud.action_menu.close()
			get_viewport().gui_release_focus()
			_menu_turn = -1
			_waiting_runner = true
			_set_active_pose(-1)
			if String(ev.kind) == CombatEngine.SEQUENCE_SKILL:
				_shout(int(ev.source), _abilities.get(String(ev.action)) as AbilityData)
				skill_runner.start(ev, _abilities.get(String(ev.action)) as AbilityData)
			else:
				Sfx.duck_music(_visuals.music_duck_db, _visuals.music_duck_ms)
				var voice := _voice_of(int(ev.source))
				if not voice.is_empty():
					Sfx.play(voice)
				runner.start(ev, _attacks.get(String(ev.action)) as EnemyAttackData,
						_data_by_id.get(int(ev.source)) as EnemyData)
		"turn_ended":
			mirror.apply(ev)
			view.camera.reset_shot()
			_refresh()
			event_played.emit(ev)
			await _wait_ms(_tuning.turn_gap_ms)
			return
		"combat_ended":
			mirror.apply(ev)
			_on_combat_ended(String(ev.result))
		_:
			mirror.apply(ev)
	_refresh()
	event_played.emit(ev)


func _on_runner_finished(tail: Array[Dictionary]) -> void:
	_waiting_runner = false
	Sfx.duck_music(0.0, _visuals.music_duck_ms)
	view.sync_alive(mirror)
	# Online, later batches may already wait in the queue: the tail comes first (engine order).
	var later := _queue.duplicate()
	_queue = tail.duplicate()
	_queue.append_array(later)
	_pump()


## True when the fight waits for a party member's choice (a client reads it from the events).
func _awaiting_choice() -> bool:
	if engine != null:
		return engine.phase == CombatEngine.Phase.AWAITING_ACTION
	return _awaiting_turn == mirror.turn and _sent_turn != mirror.turn


func _maybe_open_menu() -> void:
	if _ended or _runner_active() or not _awaiting_choice():
		return
	var actor := mirror.active_actor
	if actor < 0 or not mirror.party_ids.has(actor):
		return
	if hud.action_menu.is_open() and _menu_turn == mirror.turn:
		return
	var owner := _players.owner_of(_owner_slot(actor))
	if not _players.is_local(owner):
		# Another machine's hero: its player chooses there (say so once per turn).
		if _menu_turn == mirror.turn:
			return
		_menu_turn = mirror.turn
		hud.action_menu.close()
		view.camera.shot_turn(view.home_of(actor))
		_set_active_pose(actor)
		hud.show_center_banner("%s is choosing" % HudStyle.player_tag(owner), HudStyle.player_color(owner),
				_visuals.first_strike_banner_ms)
		return
	_menu_turn = mirror.turn
	var data := _data_by_id.get(actor) as CharacterData
	if data == null:
		push_error("CombatController: no character data for fighter %d" % actor)
		return
	var names: Dictionary = {}
	for id: int in mirror.fighters:
		names[id] = String(mirror.fighter(id).display_name)
	var abilities := data.all_abilities()
	if _setup.team_ultimate != null:
		abilities.append(_setup.team_ultimate)
	if _setup.can_run and _setup.run_ability != null:
		abilities.append(_setup.run_ability)
	var entries: Array[Dictionary] = []
	for ability: AbilityData in abilities:
		entries.append(_menu_entry(actor, ability))
	var player := _players.owner_of(_owner_slot(actor)) if _players.is_coop() else -1
	hud.action_menu.open(String(mirror.fighter(actor).display_name), data.color, entries, names, player)
	view.camera.shot_turn(view.home_of(actor))
	_set_active_pose(actor)
	menu_opened.emit(actor)


## One action menu line, worked out from the mirror (the same rules the engine checks).
func _menu_entry(actor: int, ability: AbilityData) -> Dictionary:
	var ap := int(mirror.fighter(actor).ap)
	var targets: Array[int] = []
	var pick := true
	match ability.target:
		AbilityData.Target.SINGLE_ENEMY:
			targets = mirror.living_enemy_ids()
		AbilityData.Target.ALL_ENEMIES:
			targets = mirror.living_enemy_ids()
			pick = false
		AbilityData.Target.SELF:
			targets.append(actor)
			pick = false
		AbilityData.Target.ALLY:
			targets = mirror.living_party_ids()
		AbilityData.Target.OTHER_ALLY:
			for id: int in mirror.living_party_ids():
				if id != actor:
					targets.append(id)
		AbilityData.Target.DOWNED_ALLY:
			targets = mirror.downed_party_ids()
	var reason := ""
	if ability.team_ultimate and mirror.team_gauge < _tuning.team_gauge_max:
		reason = "Needs a full team gauge. Good follow-up presses fill it."
	elif ap < ability.ap_cost:
		reason = "Needs %d AP (you have %d). Parry hits to gain AP." % [ability.ap_cost, ap]
	elif targets.is_empty():
		reason = "Nobody is down." if ability.target == AbilityData.Target.DOWNED_ALLY else "No target."
	return {"ability": ability, "usable": reason.is_empty(), "reason": reason, "targets": targets, "pick_target": pick}


func _runner_active() -> bool:
	return runner.is_active() or skill_runner.is_active()


func _on_ability_chosen(ability_id: String, target_id: int) -> void:
	if _ended or not _awaiting_choice():
		return
	var targets: Array[int] = []
	if target_id >= 0:
		targets.append(target_id)
	_menu_turn = -1
	_sent_turn = mirror.turn
	_enqueue(_submit(CombatCommands.use_ability(mirror.turn, mirror.active_actor, ability_id, targets)))


func _on_target_changed(target_id: int) -> void:
	var v := view.fighter(target_id)
	if v == null:
		hud.set_target_marker(Vector3.ZERO, false)
	else:
		hud.set_target_marker(v.head_position(), true)


func _on_combat_ended(result: String) -> void:
	_result = result
	_ended = true
	_ended_at_us = Time.get_ticks_usec()
	hud.action_menu.close()
	_set_active_pose(-1)
	match result:
		"victory":
			Sfx.play("victory")
			_play_victory()
			if _run != null:
				_play_reward_sounds()
		"escaped":
			Sfx.play("dodge")
		_:
			Sfx.play("defeat")
	view.camera.shot_end(view.arena_centre())
	var hints := _end_hints()
	hud.show_end(result, _summary_text(), hints, "The host goes on for everyone." if _net_mode == NetMode.CLIENT else "")
	if _options.is_autoplay():
		_check_mirror()
		if _net_mode != NetMode.LOCAL:
			print("AUTOPLAY_MIRROR %s %d" % [result, var_to_str(mirror.projection()).hash()])
	combat_finished.emit(result)
	# A zone fight hands the end back to the zone (Main); the zone decides when the run is over.
	if _options.quit_on_end and not _from_zone and _run == null:
		get_tree().create_timer(QUIT_DELAY_S).timeout.connect(_quit)


## Gold, then level up when the party levels: after the victory sound, one at a time.
func _play_reward_sounds() -> void:
	var levels := _run.levels_from(RunState.encounter_xp(_encounter))
	await _wait_ms(_visuals.reward_sound_delay_ms)
	Sfx.play("gold_gain")
	if levels > 0:
		await _wait_ms(_visuals.level_up_sound_gap_ms)
		Sfx.play("level_up")


func _quit() -> void:
	Sfx.stop_all()
	await get_tree().create_timer(QUIT_AUDIO_RELEASE_S, true, false, true).timeout
	get_tree().quit(0)


func _on_press_judged(action: int, report: Dictionary) -> void:
	if int(report.get("result", DefenseJudge.Result.DONE)) == DefenseJudge.Result.SUCCESS:
		# Skill presses count by result (good or perfect), defence presses by button.
		var key := int(report.get("outcome", action)) if action == Defense.Outcome.PRESS else action
		_defended[key] = int(_defended.get(key, 0)) + 1


## What the end screen's buttons do ([[action, text], ...] for the HUD's hint bar). R (fight
## again) is a keyboard extra and is not listed.
func _end_hints() -> Array:
	var stats := [&"debug_overlay", "Stats"]
	if _net_mode == NetMode.CLIENT:
		return [stats]
	if _run != null:
		if _result == "defeat":
			return [[&"menu_confirm", "See how the run went"], stats]
		return [[&"menu_confirm", "Back to the zone" if _from_zone else "On with the run"], stats]
	if _from_zone:
		return [[&"menu_confirm", "Back to the zone"], stats]
	return [[&"menu_confirm", "Fight again"], [&"menu_cancel", "Choose a fight"], stats]


func _summary_text() -> String:
	var text := "%d enemy hits   parried %d, dodged %d, jumped %d   counters %d\nskill presses: perfect %d, good %d" % [
			_enemy_hits.size(), int(_defended.get(Defense.Outcome.PARRY, 0)),
			int(_defended.get(Defense.Outcome.DODGE, 0)), int(_defended.get(Defense.Outcome.JUMP, 0)), _counters,
			int(_defended.get(Defense.Outcome.PRESS_PERFECT, 0)), int(_defended.get(Defense.Outcome.PRESS, 0))]
	if _run != null and _result == "victory":
		var xp := RunState.encounter_xp(_encounter)
		text += "\n+%d gold   +%d XP" % [_run.gold_for(_encounter), xp]
		var levels := _run.levels_from(xp)
		if levels > 0:
			text += "   LEVEL UP!  Level %d" % (_run.level + levels)
	return text


## Autoplay: what the fight waits for, when nothing has happened for a long time.
func _report_stuck() -> void:
	var states: Array = mirror.sequence.get("states", [])
	var info := "mode=%d phase=%s actor=%s turn=%d mirror_actor=%d awaiting=%d sent=%d menu_turn=%d menu_open=%s" % [
			_net_mode, str(engine.phase) if engine != null else "-", str(engine.active_actor) if engine != null else "-",
			mirror.turn, mirror.active_actor, _awaiting_turn, _sent_turn, _menu_turn, hud.action_menu.is_open()]
	info += " queue=%d playing=%s waiting_runner=%s runner=%s/%d skill=%s/%d inbox=%d seq=%s states=%s owners=%s" % [
			_queue.size(), _playing, _waiting_runner, runner.is_active(), runner.current_seq(), skill_runner.is_active(),
			skill_runner.current_seq(), _timing_inbox.size(), str(mirror.sequence.get("seq", -1)), str(states), str(_owners)]
	if _arbiter != null:
		info += " arbiter_seq=%d arbiter_open=%s" % [_arbiter.seq(), _arbiter.has_open()]
	print("AUTOPLAY_ERROR combat_stuck " + info)


## Autoplay guard: the mirror, built from events in playback order, must end equal to the engine.
func _check_mirror() -> void:
	if engine == null:
		return
	var shown := mirror.projection()
	var truth := CombatMirror.project_snapshot(engine.snapshot())
	if shown != truth:
		print("AUTOPLAY_ERROR mirror_mismatch mirror=%s engine=%s" % [var_to_str(shown).replace("\n", " "),
				var_to_str(truth).replace("\n", " ")])


# --- animations -------------------------------------------------------------------------------

func _build_fighters() -> void:
	for id: int in mirror.fighters:
		var f := mirror.fighter(id)
		var is_party := int(f.team) == Combatant.Team.PARTY
		var data := _find_data(String(f.data_id), is_party)
		if data == null:
			push_error("CombatController: no data resource for '%s'" % String(f.data_id))
			continue
		_data_by_id[id] = data
		view.add_fighter(id, is_party, int(f.slot), data)
	hud.build_fighters(mirror, _data_by_id)
	_owners.clear()
	for id: int in mirror.party_ids:
		_owners[id] = _players.owner_of(_owner_slot(id))
	runner.set_players(_players, _owners)
	skill_runner.set_players(_players, _owners)
	if autoplay != null:
		autoplay.set_players(_players, _owners)
	if _players.is_coop():
		hud.set_player_tags(_owners)
	view.sync_alive(mirror)
	_refresh()
	# Warm-up: draw every effect once so the first parry has no shader-compile hitch.
	view.warm_up()
	hud.warm_up()
	await get_tree().process_frame
	await get_tree().process_frame
	view.finish_warm_up()
	hud.finish_warm_up()


## The party slot of a fighter (-1 for an enemy or nobody).
func _owner_slot(id: int) -> int:
	if not mirror.party_ids.has(id):
		return -1
	return int(mirror.fighter(id).slot)


## Dash, strike, damage, hold, return (DESIGN.md 2.2, about 0.55 s).
func _play_party_action(ev: Dictionary) -> void:
	var actor := int(ev.actor)
	var ability := _abilities.get(String(ev.ability)) as AbilityData
	var targets: Array = ev.targets
	var target := int(targets[0]) if not targets.is_empty() else -1
	if target < 0 and not mirror.enemy_ids.is_empty():
		target = mirror.enemy_ids[0]
	var actors: Array[int] = [actor]
	var sfx := ability.impact_sfx if ability != null else "strike"
	await _strike(actors, target, sfx, _take_following(), false)
	_set_active_pose(-1)


func _play_counter(ev: Dictionary) -> void:
	var actors: Array[int] = []
	actors.assign(ev.actors)
	var team := bool(ev.team)
	_counters += 1
	view.camera.shot_counter(view.home_of(int(ev.target)))
	var label := counter_label(team, int(ev.get("hits", 1)), bool(ev.get("mixed", false)))
	if team:
		hud.show_center_banner(label, HudStyle.GOLD, _visuals.team_banner_ms)
	else:
		var enemy := view.fighter(int(ev.target))
		if enemy != null:
			hud.popup(label, enemy.head_position(), HudStyle.GOLD)
	await _strike(actors, int(ev.target), "team_counter" if team else "counter", _take_following(), true)


## "COUNTER!", "COUNTER x5!", "TEAM COUNTER x4 MIXED!": a longer or mixed string hits harder
## (card #52), so the text says why.
static func counter_label(team: bool, hits: int, mixed: bool) -> String:
	var text := "TEAM COUNTER" if team else "COUNTER"
	if hits > 1:
		text += " x%d" % hits
	if mixed:
		text += " MIXED"
	return text + "!"


## Pops the damage/downed events that belong to the strike now being played.
func _take_following() -> Array[Dictionary]:
	var taken: Array[Dictionary] = []
	while not _queue.is_empty() and String(_queue[0].get("type", "")) in ["damage", "downed"]:
		taken.append(_queue.pop_front())
	return taken


func _strike(actors: Array[int], target: int, sfx: String, results: Array[Dictionary], is_counter: bool) -> void:
	var enemy := view.fighter(target)
	var dash_s := float(_tuning.action_dash_ms) / 1000.0
	var return_s := float(_tuning.action_return_ms) / 1000.0
	var strike_at := view.strike_point(target)
	# Several attackers keep part of their formation so each one stays visible at the strike.
	for i: int in actors.size():
		var v := view.fighter(actors[i])
		if v == null:
			continue
		var spread := view.team_spread_offset(actors[i], actors)
		v.set_pose(FighterView.CharPose.READY)
		v.move_body(strike_at + spread - v.position, dash_s, Tween.TRANS_QUAD, Tween.EASE_IN)
	await _wait_ms(_tuning.action_dash_ms)

	for i: int in actors.size():
		var v := view.fighter(actors[i])
		if v != null:
			# The strike clip (alternating with the backhand in a team strike, like the slashes),
			# held on its last cell until the return (card #62); without a clip the strike key, as
			# before. The READY base stays underneath.
			v.play(STRIKE_CLIPS[i % STRIKE_CLIPS.size()], _visuals.skill_strike_pose_ms, FighterView.PRIO_REACT,
					FighterView.CharPose.STRIKE, 0, true)
	var slashes: Array[Tween] = []
	if enemy != null:
		# One slash per attacker, a little apart in time, alternating direction.
		for i: int in actors.size():
			slashes.append(view.spawn_slash(enemy.centre_position(), i % 2 == 0, 1.0, i * _visuals.team_slash_gap_ms))
	Sfx.play(sfx)
	if is_counter:
		view.camera.shake(_visuals.shake_counter, _visuals.shake_counter_ms)
		view.camera.punch(_visuals.punch_counter, _visuals.punch_ms)
		hud.screen_flash(HudStyle.PARRY, _visuals.screen_flash_counter)
	else:
		view.camera.shake(_visuals.shake_strike, _visuals.shake_strike_ms)
	if enemy != null:
		view.spawn_sparks(enemy.centre_position(), _visuals.sparks_per_counter if is_counter else _visuals.sparks_per_strike,
				1.0, _visuals.strike_spark_color)
	for ev: Dictionary in results:
		mirror.apply(ev)
		if String(ev.type) == "damage":
			_show_damage(ev)
		elif String(ev.type) == "downed":
			_show_downed(int(ev.target))
		event_played.emit(ev)
	_refresh()
	if is_counter and _tuning.hitstop_counter_ms > 0:
		# Counter hit-stop: the slashes freeze on the impact frame, then play out.
		for tween: Tween in slashes:
			tween.set_speed_scale(0.0)
		await _wait_ms(_tuning.hitstop_counter_ms)
		for tween: Tween in slashes:
			if tween.is_valid():
				tween.set_speed_scale(1.0)
	await _wait_ms(_tuning.action_hold_ms)

	for id: int in actors:
		var v := view.fighter(id)
		if v == null:
			continue
		# Ends the held strike; a fall or anything bigger keeps playing.
		v.clear_timed_pose(FighterView.PRIO_BIG)
		v.set_pose(FighterView.CharPose.IDLE if mirror.is_alive(id) else FighterView.CharPose.DOWN)
		v.move_body(Vector3.ZERO, return_s, Tween.TRANS_QUAD, Tween.EASE_OUT)
	await _wait_ms(_tuning.action_return_ms)


func _show_damage(ev: Dictionary) -> void:
	var v := view.fighter(int(ev.target))
	if v == null:
		return
	var to_enemy := not mirror.party_ids.has(int(ev.target))
	var max_hp := maxi(1, int(mirror.fighter(int(ev.target)).get("max_hp", 1)))
	var big := int(ev.amount) * 100 >= max_hp * _visuals.big_hit_percent
	hud.damage_number(int(ev.amount), v.head_position(), HudStyle.DAMAGE_DEALT if to_enemy else HudStyle.DAMAGE_TAKEN, big)
	v.flash(_visuals.flash_ms)
	if mirror.is_alive(int(ev.target)):
		# During an enemy attack the runner plays a hero's flinch or stagger on attack time (card
		# #62); a timed pose here would hide those frames.
		if to_enemy or not runner.is_active():
			var hurt_pose: int = EnemyChoreography.Pose.HURT if to_enemy else FighterView.CharPose.HURT
			if big or String(ev.get("cause", "")) in STAGGER_CAUSES:
				# A counter, a team counter or a heavy hit staggers; falls back to the hurt.
				v.play("stagger", _visuals.stagger_pose_ms, FighterView.PRIO_BIG, hurt_pose)
			else:
				v.play_pose(hurt_pose, _visuals.hurt_pose_ms)
		var voice := _voice_of(int(ev.target)) if to_enemy else ""
		if not voice.is_empty():
			Sfx.play(voice, _visuals.voice_hurt_volume_db, _visuals.voice_hurt_pitch)


## Heroes shout when one uses a skill (not the basic attack or Run), and all together on the Team
## Ultimate (card #102).
func _shout(actor: int, ability: AbilityData) -> void:
	if ability == null or ability.escape:
		return
	var shouters: Array[int] = [actor]
	if ability.team_ultimate:
		shouters.assign(mirror.party_ids.filter(func(id: int) -> bool: return mirror.is_alive(id)))
	for id: int in shouters:
		var data := _data_by_id.get(id) as CharacterData
		if data != null and data.basic_attack != ability and not data.shout_sfx.is_empty():
			Sfx.play(data.shout_sfx)


## An enemy's voice cue (empty for heroes and silent enemies).
func _voice_of(id: int) -> String:
	var data := _data_by_id.get(id) as EnemyData
	return data.voice_sfx if data != null else ""


## Popups and sounds for the phase 2 events (DESIGN.md 2.10): healing, revive, AP, statuses,
## turn shifts, the team gauge filling up.
func _show_feedback(ev: Dictionary) -> void:
	var type := String(ev.get("type", ""))
	var target := int(ev.get("target", ev.get("character", -1)))
	var v := view.fighter(target)
	var head := v.head_position() if v != null else Vector3.ZERO
	match type:
		"escaped":
			# The hero runs off the stage and fades out (DESIGN.md 2.13).
			Sfx.play("dodge")
			hud.popup("ESCAPED", head, HudStyle.JUMP)
			if v != null:
				v.clear_timed_pose()
				v.set_pose(FighterView.CharPose.DODGE)
				# The run-off: the run loop (or the side walk) turned to face away. Without either,
				# the dodge pose facing the enemies, as before.
				if v.has_clip("run"):
					v.set_flip(_visuals.party_art_faces_right)
					v.play("run", _visuals.escape_run_ms, FighterView.PRIO_BIG, FighterView.CharPose.DODGE, 0,
							false, _visuals.escape_run_cycle_ms)
				v.move_body(Vector3(-_visuals.escape_run_distance, 0.0, 0.0), float(_visuals.escape_run_ms) / 1000.0,
						Tween.TRANS_QUAD, Tween.EASE_IN)
				v.dissolve(_visuals.escape_run_ms, HudStyle.JUMP)
		"ap_changed":
			if int(ev.delta) > 0:
				Sfx.play("ap_gain")
				if String(ev.reason) in ["given", "gear"] and v != null:
					hud.popup("+%d AP" % int(ev.delta), head, HudStyle.AP_TEXT)
		"enemy_phase":
			var boss := view.fighter(int(ev.enemy))
			Sfx.play("boss_rage")
			if not rage_music_path.is_empty():
				Sfx.play_music(rage_music_path, rage_music_volume_db)
			if boss != null:
				boss.flash(_visuals.flash_ms * 4, HudStyle.LATE, 0.9)
				# Its rage clip, when the sheet has one (card #68).
				boss.play("rage", _visuals.rage_pose_ms, FighterView.PRIO_BIG)
			hud.screen_flash(HudStyle.LATE, _visuals.screen_flash_phase)
			var text := String(ev.get("text", ""))
			hud.show_center_banner(text if not text.is_empty() else "IT GROWS FURIOUS!", HudStyle.LATE,
					_visuals.first_strike_banner_ms)
		"healed":
			if v != null:
				hud.damage_number(int(ev.amount), head, HudStyle.HEAL)
				v.flash(_visuals.flash_ms * 2, HudStyle.HEAL, 0.7)
		"revived":
			if v != null:
				Sfx.play("revive")
				v.set_grey(0.0)
				v.clear_timed_pose()
				v.set_pose(FighterView.CharPose.IDLE)
				# Gets back up from the floor (card #66), when the sheet has the clip.
				v.play("get_up", _visuals.revive_pose_ms, FighterView.PRIO_BIG)
				v.flash(_visuals.flash_ms * 3, HudStyle.GOLD, 0.9)
				hud.popup("REVIVED", head, HudStyle.HEAL)
		"status_changed":
			if bool(ev.active) and v != null and mirror.is_alive(target):
				var status := String(ev.status)
				hud.popup(String(HudStyle.STATUS_NAMES.get(status, status.to_upper())), head,
						HudStyle.STATUS_COLORS.get(status, HudStyle.TEXT) as Color)
			elif not bool(ev.active) and v != null and mirror.is_alive(target):
				# A hit uses up EXPOSED for bonus damage (the combo payoff); other statuses just wear off.
				Sfx.play("exposed_burst" if String(ev.status) == "exposed" else "status_expired")
		"turn_shifted":
			if v != null and int(ev.delta) != 0:
				Sfx.play("timeline_shift")
				hud.popup("DELAYED" if int(ev.delta) > 0 else "HASTE", head, HudStyle.JUMP)
		"team_gauge":
			# The gauge label itself turns gold and says READY (the banner slot may hold a skill name).
			if int(ev.delta) > 0 and int(ev.value) >= _tuning.team_gauge_max:
				Sfx.play("gauge_full")


func _show_downed(id: int) -> void:
	var v := view.fighter(id)
	if v == null:
		return
	Sfx.play("downed" if mirror.party_ids.has(id) else "enemy_crumble")
	v.clear_timed_pose()
	v.set_grey(1.0)
	v.set_glow(0.0)
	if mirror.party_ids.has(id):
		v.set_pose(FighterView.CharPose.DOWN)
		# Falls over onto the down pose (card #66); its first cell is the flinch.
		v.play("fall", _visuals.fall_ms, FighterView.PRIO_BIG)
		hud.screen_flash(HudStyle.DAMAGE_TAKEN, _visuals.screen_flash_downed)
	elif not v.has_clip("death"):
		# A beaten enemy crumbles into rot (card #38).
		v.set_pose(EnemyChoreography.Pose.HURT)
		v.flash(_visuals.flash_ms * 2, _visuals.death_edge_color, _visuals.death_flash_strength)
		v.dissolve(_visuals.death_dissolve_ms, _visuals.death_edge_color)
		view.spawn_sparks(v.centre_position(), _visuals.death_sparks, 1.0, _visuals.death_spark_color)
	else:
		_play_enemy_death(id, v)


## A beaten enemy with a death clip plays it and holds its last cell (card #68). A rotting one
## crumbles during the clip, its motes rising at once; a bursting one bursts into sparks when the
## clip ends and vanishes quickly. Nothing is awaited: the burst is a one-shot timer.
func _play_enemy_death(id: int, v: FighterView) -> void:
	var data := _data_by_id.get(id) as EnemyData
	var own := data != null and data.death_color.a > 0.0
	var edge := data.death_color if own else _visuals.death_edge_color
	v.set_pose(EnemyChoreography.Pose.HURT)
	v.flash(_visuals.flash_ms * 2, edge, _visuals.death_flash_strength)
	v.play("death", _visuals.death_pose_ms, FighterView.PRIO_FINAL, EnemyChoreography.Pose.HURT, 0, true)
	if data != null and data.death_style == EnemyData.DeathStyle.BURST:
		v.dissolve(_visuals.death_burst_dissolve_ms, edge, _visuals.death_pose_ms)
		var color := data.death_color if own else _visuals.death_burst_color
		get_tree().create_timer(float(_visuals.death_pose_ms) / 1000.0).timeout.connect(_burst.bind(id, color))
	else:
		v.dissolve(_visuals.death_dissolve_ms, edge, _visuals.death_dissolve_delay_ms)
		view.spawn_sparks(v.centre_position(), _visuals.death_sparks, 1.0,
				data.death_color if own else _visuals.death_spark_color)


## The spark burst of a bursting enemy's death (at its body, wherever the death left it).
func _burst(id: int, color: Color) -> void:
	var v := view.fighter(id)
	if v != null:
		view.spawn_sparks(v.centre_position(), _visuals.death_burst_sparks, 1.0, color)


## Ready pose for the party member whose turn it is (-1: nobody).
func _set_active_pose(actor: int) -> void:
	for id: int in mirror.party_ids:
		var v := view.fighter(id)
		if v == null or not mirror.is_alive(id):
			continue
		v.set_pose(FighterView.CharPose.READY if id == actor else FighterView.CharPose.IDLE)


## Fight start (card #70): each standing hero draws their weapon once the fade-in uncovers them,
## one after another by party slot. Not awaited; an attack or a skill that starts first cancels it.
func _play_draw() -> void:
	for id: int in _standing_heroes():
		var delay := _visuals.draw_delay_ms + _hero_slot(id) * _visuals.draw_stagger_ms
		view.fighter(id).play("draw", _visuals.draw_pose_ms, FighterView.PRIO_REACT, -1, delay)


## Won (card #67): each standing hero plays the victory clip, one after another by party slot,
## then loops the victory hold. Not awaited; without the clips they keep breathing.
func _play_victory() -> void:
	for id: int in _standing_heroes():
		var v := view.fighter(id)
		var delay := _visuals.victory_pose_delay_ms + _hero_slot(id) * _visuals.victory_stagger_ms
		v.play("victory", _visuals.victory_pose_ms, FighterView.PRIO_FINAL, -1, delay)
		if v.has_clip("victory_hold"):
			v.set_loop("victory_hold", _visuals.victory_cycle_ms, FighterView.CharPose.IDLE,
					delay + _visuals.victory_pose_ms)


## Heroes on the stage, alive and not escaped, who have a view.
func _standing_heroes() -> Array[int]:
	var ids: Array[int] = []
	for id: int in mirror.party_ids:
		if view.fighter(id) != null and mirror.is_alive(id) and not bool(mirror.fighter(id).get("escaped", false)):
			ids.append(id)
	return ids


## A hero's party slot (0 to 2), for staggering their poses.
func _hero_slot(id: int) -> int:
	return maxi(0, _owner_slot(id))


func _refresh() -> void:
	hud.refresh(mirror, _practice_text())


# --- practice tools ---------------------------------------------------------------------------

func _handle_practice(event: InputEvent, key: Key) -> bool:
	if event.is_action_pressed("debug_overlay", false, true):
		hud.overlay.toggle()
		return true
	if key == KEY_NONE:
		return false
	if hud.overlay.visible:
		match key:
			KEY_R:
				# The training ring is a practice aid: a run fight is the real game.
				if _run == null:
					PlayerSettings.set_show_timing_ring(not PlayerSettings.show_timing_ring(_tuning))
				return true
			KEY_G:
				# G, not F: F is the keyboard Skills button (fight_skills).
				_options.telegraph_flash = not _options.telegraph_flash
				return true
			KEY_T:
				_options.timing_readout = not _options.timing_readout
				return true
			KEY_L:
				_options.motion_sounds = not _options.motion_sounds
				return true
			KEY_H:
				_options.hit_markers = not _options.hit_markers
				return true
			KEY_C:
				_options.windup_crouch = not _options.windup_crouch
				return true
			KEY_V:
				_options.cinematic_camera = not _options.cinematic_camera
				view.camera.cinematic = _options.cinematic_camera
				return true
	match key:
		KEY_F2:
			# Only while the game waits for a menu choice, never during an attack or a skill.
			if hud.action_menu.is_open() and not _runner_active():
				hud.action_menu.cancel_hold()
				hud.calibration.open()
			return true
		KEY_I:
			if engine.phase != CombatEngine.Phase.ENDED and _run == null:
				_enqueue(_submit(CombatCommands.practice({"invulnerable_party": not bool(mirror.practice.invulnerable_party)})))
			return true
		KEY_O:
			if engine.phase != CombatEngine.Phase.ENDED and _run == null:
				_enqueue(_submit(CombatCommands.practice({"immortal_enemies": not bool(mirror.practice.immortal_enemies)})))
			return true
		KEY_R:
			# A run fight cannot be started over: its HP and gold carry on.
			if _run == null:
				restart_requested.emit()
			return true
	var index := PRACTICE_ATTACK_KEYS.find(key)
	if index >= 0 and _run != null:
		# A run fight is the real game: no forcing attacks.
		return false
	if index >= 0:
		var attacks := _practice_attacks()
		# The engine is already over while the last strike or attack still plays: nothing to force.
		if index < attacks.size() and engine.phase != CombatEngine.Phase.ENDED:
			_enqueue(_submit(CombatCommands.practice({"force_attack": attacks[index].id})))
		return true
	return false


## The attacks of the first living enemy (what 1-5 force).
func _practice_attacks() -> Array[EnemyAttackData]:
	var list: Array[EnemyAttackData] = []
	for id: int in mirror.living_enemy_ids():
		var data := _data_by_id.get(id) as EnemyData
		if data != null:
			for attack: EnemyAttackData in data.attacks:
				if attack != null:
					list.append(attack)
			break
	return list


func _practice_text() -> String:
	# Online the practice keys are off (they would change everyone's fight), and a run fight is the
	# real game: no practice panel there (F1 and F2 still work).
	if not _tuning.practice_tools_enabled or _net_mode != NetMode.LOCAL or _run != null:
		return ""
	var forced := String(mirror.practice.get("force_attack", ""))
	var attacks := _practice_attacks()
	var lines := PackedStringArray()
	lines.append("PRACTICE   next attack: " + ("random" if forced.is_empty() else _attack_name(forced)))
	var keys := PackedStringArray()
	for i: int in mini(attacks.size(), PRACTICE_ATTACK_KEYS.size()):
		keys.append("%d %s" % [i + 1, attacks[i].display_name])
		if keys.size() == PRACTICE_KEYS_PER_LINE:
			lines.append("   ".join(keys))
			keys.clear()
	if not keys.is_empty():
		lines.append("   ".join(keys))
	lines.append("I party invulnerable: " + _on_off(bool(mirror.practice.get("invulnerable_party", false))))
	lines.append("O enemy immortal: " + _on_off(bool(mirror.practice.get("immortal_enemies", false))))
	lines.append("F1 stats   F2 calibrate" if _run != null else "R restart   F1 stats   F2 calibrate")
	return "\n".join(lines)


func _attack_name(attack_id: String) -> String:
	for attack: EnemyAttackData in _practice_attacks():
		if attack.id == attack_id:
			return attack.display_name
	return attack_id


static func _on_off(value: bool) -> String:
	return "ON" if value else "OFF"


# --- helpers ----------------------------------------------------------------------------------

## A real-time wait owned by this node: if the fight is freed (restart) the wait simply never
## resumes, so no coroutine wakes up on a freed controller.
func _wait_ms(ms: int) -> void:
	if ms <= 0:
		return
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = float(ms) / 1000.0
	add_child(timer)
	timer.start()
	await timer.timeout
	timer.queue_free()


func _pick_seed() -> int:
	if _fight_seed >= 0:
		return _fight_seed
	if _options.seed_override >= 0:
		return _options.seed_override
	if _tuning.fixed_seed != 0:
		return _tuning.fixed_seed
	return randi_range(1, 2147483646)


func _find_data(data_id: String, is_party: bool) -> Resource:
	if is_party:
		for c: CharacterData in _setup.party:
			if c != null and c.id == data_id:
				return c
	else:
		for e: EnemyData in _setup.enemies:
			if e != null and e.id == data_id:
				return e
	return null


## Loads every sound and texture now so nothing loads in the middle of an attack.
func _warm_up_assets(setup: CombatSetup) -> void:
	Sfx.preload_all()
	for c: CharacterData in setup.party:
		AssetLoader.texture(c.sprite_path, Vector2i(256, 48))
		AssetLoader.texture(c.portrait_path, Vector2i(48, 48))
	for e: EnemyData in setup.enemies:
		AssetLoader.texture(e.sprite_path, Vector2i(384, 64))
		AssetLoader.texture(e.portrait_path, Vector2i(48, 48))
	for path: String in [_visuals.spark_path, _visuals.shockwave_path, _visuals.shadow_path,
			_visuals.slash_path,
			_visuals.lock_icon_path, _visuals.ap_pip_path, _visuals.ap_pip_empty_path,
			_visuals.hit_icon_normal_path, _visuals.hit_icon_ground_path]:
		AssetLoader.texture(path)


static func _pressed_key(event: InputEvent) -> Key:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return KEY_NONE
	return key.physical_keycode
