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
## A run fight is over and the player wants to go on with the run (DESIGN.md 8).
signal continue_requested(result: String)
## Every event as it is played (and the prompt events the runner applies at once).
signal event_played(event: Dictionary)
## The action menu opened for this party member.
signal menu_opened(actor_id: int)
signal combat_finished(result: String)
## A pause asked for with request_pause() can start now: nothing is being timed. Main stops this
## node (process disabled) and shows the pause menu; resume_after_pause() goes on.
signal pause_reached
## Online host: client `peer` caught up with this fight (it said so) and the fight is between moves:
## Main hands its heroes back now, never in the middle of an attack (cards #205, #304).
signal seat_ready(peer: int)
## Online client: this fight now shows what the host has: it played everything the host sent since
## its first batch (or the host's resume after joining mid-fight), so no sequence the host already
## played with someone else judging is still waiting here; Main tells the host it may hand our heroes
## over.
signal caught_up

enum NetMode { LOCAL, HOST, CLIENT }

## Stand-in ability ids for backpack items start with this (the uid follows).
const ITEM_PREFIX := "item:"
const TUTORIAL_LOCKED := "Not in this lesson."
const QUIT_DELAY_S: float = 1.0
## After stopping all sounds, quitting waits this long (real time) so the audio server lets go of
## the playbacks; two frames are not enough and Godot reports "resources still in use at exit".
const QUIT_AUDIO_RELEASE_S: float = 0.3
const PRACTICE_ATTACK_KEYS: Array[Key] = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]
const PRACTICE_KEYS_PER_LINE: int = 3
## Autoplay: a fight where nothing was played for this long is stuck (its state is printed once).
const AUTOPLAY_STUCK_MS: int = 60000
## Strike clips of a dash strike or counter, by the striker's place among the attackers.
const STRIKE_CLIPS: Array[String] = ["strike", "strike_alt"]
## Damage causes that stagger the target whatever the amount (DESIGN.md 5.5).
const STAGGER_CAUSES: Array[String] = ["counter", "team_counter"]
## The word over an enemy a drinking hit healed (card #323).
const DRAIN_TEXT := "DRAIN"

var mirror := CombatMirror.new()
var engine: CombatEngine
var view: CombatView
var hud: CombatHud
var runner: TimedSequenceRunner
var skill_runner: SkillSequenceRunner
## A tutorial fight (DESIGN.md 7.8): no practice panel, the training ring always on.
var tutorial_mode: bool = false
## The tutorial's one allowed menu choice (an ability id; "" = any): the rest is locked.
var tutorial_guide: String = ""
## Enemy speed in percent of their data (set before the fight is added; the tutorial slows it).
var enemy_speed_percent: int = 100
var defense_input: DefenseInput
var autoplay: Autoplay

## The song for the boss once it rages (set by Main from MusicSet; empty: no change).
var rage_music_path: String = ""
var rage_music_volume_db: float = 0.0
## Songs for the end screen (cards #109, #126; empty: the fight song goes on), started
## end_music_delay_ms after the jingle.
var victory_music_path: String = ""
var defeat_music_path: String = ""
var end_music_delay_ms: int = 0
## Set once the game is quitting (--quit-on-end): no end song may start after the sounds stop.
var _quitting: bool = false

var _encounter: EncounterData
var _tuning: Tuning
var _visuals: CombatVisuals
var _options: CombatOptions
## The hero the turn spotlight is on (-1: none).
var _spot_actor: int = -1
## --attacks: the next listed attack to force, and whether the last sequence was an enemy attack.
var _forced_next: int = 0
var _forced_seq_was_attack: bool = false
## The place the fight happens in (null: the fight list's look) and how it starts.
var _look: StageLook
## The place's drifting particles, played thinner in its fights (DESIGN.md 8.12); empty: the look's own.
var _air: Array[ZoneAmbientData] = []
var _opening: CombatSetup.Opening = CombatSetup.Opening.NORMAL
## The run this fight belongs to (null outside a run): it provides the party, its HP and the gold.
var _run: RunState
var _drop: ItemData
## Fight item stand-in abilities by uid (see _item_ability()).
var _item_abilities: Dictionary = {}
## Who plays (DESIGN.md 9.1): in co-op a device drives only its own heroes' menus and presses.
var _players: PlayerRoster = PlayerRoster.solo(3)
## Party member id -> co-op player.
var _owners: Dictionary = {}
var _net_mode: int = NetMode.LOCAL
## Online: the fight seed the host picked (-1: pick one here).
var _fight_seed: int = -1
## Host: the referee for clients' prompts.
var _arbiter: DefenseArbiter
## Host: clients who got in mid-fight and wait for the next quiet moment to get the fight, and
## clients that caught up with it and wait for the next quiet moment to get their heroes.
var _resume_peers: Array[int] = []
var _seat_peers: Array[int] = []
## Client (got in mid-fight): batches are skipped until the host's "resume" batch arrives.
var _resume_pending: bool = false
## Client: the host's batches for this fight started coming (the first one, or the resume after
## getting in mid-fight), and this fight has played all of them since (see caught_up).
var _host_batches: bool = false
var _caught_up: bool = false
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
## Fighter id -> its data id, from combat_started (host: known before the fighters are built).
var _data_ids: Dictionary = {}
## The freeze (ms) of the large-tier kill just shown by _show_downed (card #179), or of a BROKEN
## Doom (card #195): whatever plays it waits it out once, so the body holds before the next shot.
## 0: none.
var _kill_freeze_ms: int = 0
## Enemy id -> true while its Doom glow or stagger glow is lit (so it is switched off once).
var _doom_lit: Dictionary = {}
## Ability id -> AbilityData.
var _abilities: Dictionary = {}
## Enemy attack id -> EnemyAttackData (for its training ring speed).
var _attacks: Dictionary = {}


## Call before adding the node to the tree. `look` null uses the fight list's look.
func configure(encounter: EncounterData, tuning: Tuning, visuals: CombatVisuals, options: CombatOptions,
		look: StageLook = null, opening: CombatSetup.Opening = CombatSetup.Opening.NORMAL,
		air: Array[ZoneAmbientData] = []) -> void:
	_air = air
	_encounter = encounter
	_tuning = tuning
	_visuals = visuals
	_options = options
	_look = look
	_opening = opening


## Makes this a run fight (DESIGN.md 8): the run's party with its carried-over HP, gold on the end
## screen, and no "fight again". Call after configure(), before adding the node to the tree.
func configure_run(run: RunState) -> void:
	_run = run


## What the beaten enemy drops (DESIGN.md 8.1; null: nothing). The end screen names it after a
## victory; Main puts it in the backpack.
func configure_drop(item: ItemData) -> void:
	_drop = item


## The players and their heroes. Call before adding the node to the tree (default: solo).
func configure_players(players: PlayerRoster) -> void:
	_players = players
	_journal_local_slots()


## Online play (DESIGN.md 9.2): HOST runs the engine and talks to the clients, CLIENT plays what
## the host sends. `fight_seed` is the host's seed (both sides build the same setup from it).
func configure_online(mode: NetMode, fight_seed: int) -> void:
	_net_mode = mode
	_fight_seed = fight_seed


## The roster changed mid-fight (online: someone came, went or got their seat back; local: the
## Players overlay). Heroes' menus and presses go to their new owners from now on; a gone peer's open
## prompts are resolved by the arbiter at once. The turn's open menu stays where it was when its
## hero keeps the same player on the same machine (keeps_menu).
func update_players(players: PlayerRoster, gone_peer: int = -1) -> void:
	var actor := mirror.active_actor if mirror.party_ids.has(mirror.active_actor) else -1
	# The owner as this fight last knew it: the host changes its roster in place before calling.
	var before := int(_owners.get(actor, -1)) if actor >= 0 else -1
	var was_local := before >= 0 and _players.is_local(before)
	_players = players
	_journal_local_slots()
	# A new map, not the old one changed in place: a runner in the middle of a sequence still holds
	# the old one until it hands back.
	var owners: Dictionary = {}
	for id: int in mirror.party_ids:
		owners[id] = _players.owner_of(_owner_slot(id))
	_owners = owners
	runner.set_players(_players, _owners)
	skill_runner.set_players(_players, _owners)
	PadRumble.set_party(_players, _owners)
	if autoplay != null:
		autoplay.set_players(_players, _owners)
	hud.set_player_tags(_owners if _players.is_coop() else {})
	if _arbiter != null and gone_peer > 0:
		_arbiter.drop_peer(gone_peer)
	var after := _players.owner_of(_owner_slot(actor)) if actor >= 0 else -1
	var now_local := after >= 0 and _players.is_local(after)
	if keeps_menu(before, after, was_local, now_local, gone_peer):
		return
	_menu_turn = -1
	if not _playing and _queue.is_empty() and not _waiting_runner:
		_maybe_open_menu()


## A roster change leaves the turn's open menu alone (where its player was: Skills, target step,
## the hold ring) when the acting hero keeps the same player on the same machine and nobody left.
## Every drop-in sends at least two rosters to everyone, and a local overlay applies one. Pure.
static func keeps_menu(before: int, after: int, was_local: bool, now_local: bool, gone_peer: int) -> bool:
	return gone_peer <= 0 and before >= 0 and before == after and was_local == now_local


## Online client that joined again mid-fight (card #205): this machine missed the fight so far.
## Everything before the host's "resume" batch (the fight as it stands) is skipped.
func expect_resume() -> void:
	_resume_pending = true


## The host's seed for this fight (online), -1 offline.
func fight_seed() -> int:
	return _fight_seed


## Online host: client `peer` got in mid-fight (joined again, or dropped in); it gets the fight at
## the next moment nothing is being timed (a hero's turn, or the end), never in the middle of an
## attack. Its heroes come later (queue_seat).
func queue_resume(peer: int) -> void:
	if _net_mode != NetMode.HOST or _resume_peers.has(peer):
		return
	_resume_peers.append(peer)
	_try_resume.call_deferred()


## Online host: client `peer` caught up with this fight; its heroes come back at the next moment
## nothing is being timed (seat_ready).
func queue_seat(peer: int) -> void:
	if _net_mode != NetMode.HOST or _seat_peers.has(peer):
		return
	_seat_peers.append(peer)
	_try_resume.call_deferred()


## Online client: true once this fight shows the host's fight (see caught_up).
func has_caught_up() -> bool:
	return _caught_up


## Online host: client `peer` went away again before it got the fight or its seat.
func cancel_resume(peer: int) -> void:
	_resume_peers.erase(peer)
	_seat_peers.erase(peer)


## Host, at a quiet moment (a hero's turn, or the end): the fight as it stands goes to the clients
## waiting for it, and the ones that caught up get their heroes (seat_ready).
func _try_resume() -> void:
	if _net_mode != NetMode.HOST or engine == null or (_resume_peers.is_empty() and _seat_peers.is_empty()):
		return
	var events := engine.resume_events()
	if events.is_empty():
		return
	var peers := _resume_peers.duplicate()
	var seats := _seat_peers.duplicate()
	_resume_peers.clear()
	_seat_peers.clear()
	for peer: int in peers:
		Net.send_to(peer, "combat", {"kind": "resume", "seq": -1, "events": events, "fight": _fight_seed})
		print("Fight resumed for peer %d at turn %d" % [peer, engine.turn_number])
	for peer: int in seats:
		seat_ready.emit(peer)


## Online: a batch of events from the host ({kind, seq, events, fight}).
func receive_batch(payload: Dictionary) -> void:
	if _net_mode != NetMode.CLIENT or not payload.get("events") is Array:
		return
	var events: Array[Dictionary] = []
	for ev: Variant in payload.events:
		if ev is Dictionary:
			events.append(ev as Dictionary)
	var kind := String(payload.get("kind", ""))
	if _resume_pending or kind == "resume":
		# Got in mid-fight: what came before the fight as it stands is already in it.
		if kind == "resume" and _resume_pending:
			_resume_pending = false
			_timing_inbox.clear()
			_host_batches = true
			_enqueue(events)
			_note_caught_up()
		return
	_host_batches = true
	if kind == "timing":
		_route_timing(int(payload.get("seq", -1)), events)
	else:
		_enqueue(events)
	_note_caught_up()


## Client: tells Main once (caught_up), the first time this fight has played everything the host
## sent since its first batch (skipped ones do not count): nothing queued, nothing playing.
func _note_caught_up() -> void:
	if _caught_up or not drained(_host_batches, _queue.is_empty(), _playing or _waiting_runner or _runner_active()):
		return
	_caught_up = true
	caught_up.emit()


## True when a client fight has caught up with the host: the host's batches started (`started`),
## and none is waiting (`queue_empty`) or playing (`busy`: an event, or an attack or skill still
## running). Pure.
static func drained(started: bool, queue_empty: bool, busy: bool) -> bool:
	return started and queue_empty and not busy


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
		CombatCommands.USE_ITEM:
			var actor := int(command.get("actor", -1))
			if engine.phase != CombatEngine.Phase.AWAITING_ACTION or actor != engine.active_actor \
					or player < 0 or _players.owner_of(_owner_slot(actor)) != player:
				return
			var targets: Array[int] = []
			if command.get("targets") is Array:
				for t: Variant in command.targets:
					targets.append(int(t))
			_enqueue(_submit(CombatCommands.use_item(int(command.get("turn", -1)), actor, int(command.get("uid", -1)),
					targets)))
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
## The team gauge as the fight shows it (a run carries it into the next fight, card #146).
func team_gauge() -> int:
	return mirror.team_gauge


func party_hp() -> Array[int]:
	var list: Array[int] = []
	list.resize(mirror.party_ids.size())
	for id: int in mirror.party_ids:
		var f := mirror.fighter(id)
		var slot := int(f.slot)
		if slot >= 0 and slot < list.size():
			list[slot] = int(f.hp)
	return list


func _exit_tree() -> void:
	# Out of the fight a buzz goes to the pad in use again (card #299).
	PadRumble.clear_party()
	# The streak's swell and the attack dip belong to this fight: a restart keeps the same song,
	# which Audio.play_music leaves playing as it is (lift and dip included). The killing blow's
	# hush is left to the next song (play_music clears it), so a hushed song fades out silent.
	Sfx.lift_music(0.0, 0)
	Sfx.duck_music(0.0, 0)


func _ready() -> void:
	_progress_ms = Time.get_ticks_msec()
	defense_input = DefenseInput.new()
	defense_input.name = "DefenseInput"
	add_child(defense_input)

	view = CombatView.new()
	view.name = "View"
	add_child(view)
	view.build(_visuals, _look, _air)
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
		if _options.seed_override >= 0:
			autoplay.set_seed(_options.seed_override)
		add_child(autoplay)
		runner.press_judged.connect(autoplay.on_press_judged)
		skill_runner.press_judged.connect(autoplay.on_press_judged)
		event_played.connect(autoplay.on_event)
		menu_opened.connect(autoplay.on_menu_opened)
		combat_finished.connect(autoplay.on_combat_finished)

	var setup := _run.fight_setup(_encounter, _pick_seed(), _opening) if _run != null 			else CombatSetup.from_encounter(_encounter, _tuning, _pick_seed(), _opening)
	_setup = setup
	setup.allow_practice = _tuning.practice_tools_enabled or _options.is_autoplay()
	setup.enemy_speed_percent = enemy_speed_percent
	# A run is the real game: no training ring there (practice fights may still use it, F1 > R).
	runner.training_ring_allowed = _run == null
	_allow_timing_numbers()
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
		# Phase-two-only attacks too: their projectiles, rock waves and animations live in this data.
		for attack: EnemyAttackData in enemy.all_attacks():
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
	_update_doom_look()


func _unhandled_input(event: InputEvent) -> void:
	if hud.calibration.is_running():
		hud.calibration.handle_input(event)
		get_viewport().set_input_as_handled()
		return
	var key := _pressed_key(event)
	if _ended:
		if event.is_action_pressed("debug_overlay", false, true) and is_practice_fight():
			hud.overlay.toggle()
			get_viewport().set_input_as_handled()
			return
		# A defence press still in flight when the fight ends must not skip the end screen.
		if Time.get_ticks_usec() - _ended_at_us < _visuals.end_input_guard_ms * 1000:
			return
		if _net_mode == NetMode.CLIENT:
			# The host goes on for everyone.
			return
		if _run != null:
			if event.is_action_pressed("menu_confirm", false, true) or event.is_action_pressed("menu_cancel", false, true):
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
	_force_listed_attack(events)
	return events


func _submit_start() -> Array[Dictionary]:
	var events := _keep_valid(engine.start())
	if _net_mode == NetMode.HOST:
		_host_sent(events, "flow", -1)
	_force_listed_attack(events)
	return events


## --attacks (a dev tool for pictures): once the fight starts and after each enemy attack, the
## next listed attack is forced through the practice tools (practice fights only).
func _force_listed_attack(events: Array[Dictionary]) -> void:
	if _options.forced_attacks.is_empty() or _net_mode != NetMode.LOCAL or _run != null:
		return
	for ev: Dictionary in events:
		var type := String(ev.get("type", ""))
		var after_attack := type == "sequence_resolved" and _forced_seq_was_attack
		if type == "timed_sequence_declared":
			_forced_seq_was_attack = String(ev.kind) == CombatEngine.SEQUENCE_ENEMY_ATTACK
		if (type == "combat_started" or after_attack) and engine.phase != CombatEngine.Phase.ENDED:
			var id := _options.forced_attacks[_forced_next % _options.forced_attacks.size()]
			_forced_next += 1
			events.append_array(_keep_valid(engine.submit(CombatCommands.practice({"force_attack": id}))))
			return


## Host: sends a batch to the clients and keeps the arbiter up to date.
func _host_sent(events: Array[Dictionary], kind: String, seq: int) -> void:
	if events.is_empty():
		return
	# Tagged with the fight, so a client still building an earlier one keeps it for this one.
	Net.broadcast("combat", {"kind": kind, "seq": seq, "events": events, "fight": _fight_seed})
	if not _resume_peers.is_empty() or not _seat_peers.is_empty():
		_try_resume.call_deferred()
	for ev: Dictionary in events:
		match String(ev.get("type", "")):
			"combat_started":
				# The first attack can come in this same batch, before the fighters are built.
				for f: Dictionary in ev.fighters:
					_data_ids[int(f.id)] = String(f.get("data_id", ""))
					if int(f.team) == Combatant.Team.PARTY:
						_owners[int(f.id)] = _players.owner_of(int(f.slot))
			"timed_sequence_declared":
				var owners: Dictionary = {}
				for p: Dictionary in ev.prompts:
					var player := int(_owners.get(int(p.character), 0))
					if not _players.is_local(player) and player < _players.peers.size():
						owners[int(p.idx)] = _players.peers[player]
				var lead := 0
				if String(ev.kind) == CombatEngine.SEQUENCE_ENEMY_ATTACK:
					# The same lead-in the runner plays, run-up included (DESIGN.md 3.12).
					lead = EnemyChoreography.lead_in_ms(_tuning, EnemyChoreography.runs_up(
							_attacks.get(String(ev.action)) as EnemyAttackData, _enemy_data_of(int(ev.source)),
							ev.hits as Array, _tuning))
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
		if _net_mode == NetMode.CLIENT:
			_note_caught_up()
		if _pause_pending:
			_enter_pause()


## Makes this a tutorial fight (call after it is in the tree).
func set_tutorial(on: bool) -> void:
	tutorial_mode = on
	if runner != null:
		runner.force_ring = on
	_allow_timing_numbers()


## The press timing numbers ("PARRY -34", "LATE +343") show only in practice fights (card #276).
func _allow_timing_numbers() -> void:
	if runner != null:
		runner.timing_numbers_allowed = is_practice_fight()
	if skill_runner != null:
		skill_runner.timing_numbers_allowed = is_practice_fight()


## The tutorial allows only this menu choice (an ability id; "" = any). An open menu is redrawn.
func set_tutorial_guide(ability_id: String) -> void:
	tutorial_guide = ability_id
	hud.action_menu.guide = ability_id
	if hud.action_menu.is_open():
		hud.action_menu.close()
		_menu_turn = -1
		_maybe_open_menu()


## Sends a practice command (DESIGN.md 3.4; the tutorial drives its fight with these). Practice
## fights only: ignored in a run, online, or once the fight is over.
func practice_command(fields: Dictionary) -> void:
	if engine == null or _run != null or _net_mode != NetMode.LOCAL or engine.phase == CombatEngine.Phase.ENDED:
		return
	_enqueue(_submit(CombatCommands.practice(fields)))


## Asks to pause. Returns false if this fight cannot pause now (over, or calibrating). During an
## enemy attack or a skill the pause starts when it is done ("PAUSING AFTER THIS MOVE").

## `quiet`: no "PAUSING AFTER THIS MOVE" banner (the tutorial pauses between its steps).
func request_pause(quiet: bool = false) -> bool:
	if _ended or _paused or hud.calibration.is_running():
		return false
	_pause_pending = true
	if not _playing and not _waiting_runner:
		_enter_pause()
	elif not quiet:
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
	# A Doom picked inside a skill's batch (the boss entering phase two on a hero's hit) is announced
	# here too, without the awaited beat (the skill goes on).
	var announced := String(ev.get("type", "")) == "intent" and _announces_doom(ev)
	mirror.apply(ev)
	match String(ev.get("type", "")):
		"intent":
			if announced:
				_show_doom_banner(ev, int(ev.charge_left))
		"downed":
			_show_downed(int(ev.target))
			# A kill by a skill's press: its animation clock holds for the freeze (a hit-stop), so
			# the strike stays on its impact frame; nothing here waits for it.
			skill_runner.hold(_take_kill_freeze())
		"prompt_resolved":
			if String(mirror.sequence.get("kind", "")) == CombatEngine.SEQUENCE_ENEMY_ATTACK:
				_enemy_hits["%d:%d" % [int(ev.seq), int(ev.hit)]] = true
		"damage":
			_show_damage(ev)
		"doom_broken":
			# Broken by a skill's press: the skill's clock holds for the freeze, like a big kill.
			_show_feedback(ev)
			skill_runner.hold(_take_kill_freeze())
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
			if bool(ev.get("resume", false)):
				# Got in mid-fight (#205, #304): no intro, and a boss already raging rages here too.
				_resume_mood(ev)
			elif String(ev.get("opening", "")) == "first_strike":
				Sfx.play("gauge_full")
				hud.show_center_banner("FIRST STRIKE!", HudStyle.GOLD, _visuals.first_strike_banner_ms)
			elif _encounter.boss or _encounter.mini_boss:
				Sfx.play("alert")
				hud.show_center_banner(_encounter.display_name.to_upper(), HudStyle.LATE, _visuals.first_strike_banner_ms)
				# The camera starts pulled back and pushes in with a little trauma (card #179).
				view.camera.add_trauma(_visuals.intro_shake)
				view.camera.punch(-_visuals.intro_push, _visuals.intro_push_ms)
			else:
				Sfx.play("fight_start")
		"turn_started":
			mirror.apply(ev)
			if int(ev.team) == Combatant.Team.PARTY:
				Sfx.play("turn_start")
				_awaiting_turn = int(ev.turn)
		"ability_used":
			mirror.apply(ev)
			_spotlight(-1)
			_awaiting_turn = -1
			_refresh()
			var used := _abilities.get(String(ev.ability)) as AbilityData
			# Skills with presses are animated by the SkillSequenceRunner.
			if used == null or used.press_times_ms.is_empty():
				await _play_party_action(ev)
		"item_used":
			mirror.apply(ev)
			_spotlight(-1)
			_awaiting_turn = -1
			_refresh()
			await _play_item_used(ev)
		"counter":
			mirror.apply(ev)
			await _play_counter(ev)
		"damage":
			mirror.apply(ev)
			_show_damage(ev)
		"downed":
			mirror.apply(ev)
			_show_downed(int(ev.target))
			# The large-tier kill holds for its freeze before the next event (the end shot).
			await _wait_ms(_take_kill_freeze())
		"ap_changed", "healed", "revived", "status_changed", "turn_shifted", "team_gauge", "enemy_phase", "escaped", \
				"defence_streak":
			mirror.apply(ev)
			_show_feedback(ev)
		"intent":
			# A Doom just announced (card #195) gets its banner; every other intent is silent.
			var announced := _announces_doom(ev)
			mirror.apply(ev)
			if announced:
				_show_doom_banner(ev, int(ev.charge_left))
				await _wait_ms(_visuals.doom_gather_beat_ms)
		"doom_charging", "doom_progress", "doom_unleashed", "stagger_changed":
			mirror.apply(ev)
			_show_feedback(ev)
			if type == "doom_charging":
				await _wait_ms(_visuals.doom_gather_beat_ms)
			elif type == "doom_unleashed":
				await _wait_ms(_visuals.doom_unleash_beat_ms)
		"doom_broken":
			mirror.apply(ev)
			_show_feedback(ev)
			await _wait_ms(_take_kill_freeze())
		"turn_lost":
			# A Dazed hero's turn passes (card #252).
			mirror.apply(ev)
			var dazed := view.fighter(int(ev.actor))
			if dazed != null:
				Sfx.play("status_expired")
				dazed.play("hurt", _visuals.hurt_pose_ms, FighterView.PRIO_BIG)
				hud.popup("DAZED", dazed.head_position(), HudStyle.STATUS_COLORS.get(String(ev.status), HudStyle.TEXT) as Color)
			await _wait_ms(_visuals.turn_lost_beat_ms)
		"enemy_support":
			# A monster heals or shields a fellow monster (card #259): its name in the banner, a cast.
			mirror.apply(ev)
			await _play_enemy_support(ev)
		"self_destructed":
			mirror.apply(ev)
			var spent := view.fighter(int(ev.enemy))
			if spent != null:
				spent.flash(_visuals.flash_ms * 3, HudStyle.LATE, 0.9)
				view.camera.add_trauma(_visuals.phase_shake)
		"timed_sequence_declared":
			mirror.apply(ev)
			hud.action_menu.close()
			get_viewport().gui_release_focus()
			_menu_turn = -1
			_waiting_runner = true
			_set_active_pose(-1)
			_spotlight(-1)
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
			# A turn the tutorial passed may still have its menu open.
			hud.action_menu.close()
			_spotlight(-1)
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


## True when a resume's combat_started (`ev`) has an enemy past its phase change (a boss or guard
## that already raged before this machine got in, #205, #304). Pure.
static func raging_on_resume(ev: Dictionary) -> bool:
	if not bool(ev.get("resume", false)):
		return false
	for d: Variant in ev.get("fighters", []):
		var fighter: Dictionary = d if d is Dictionary else {}
		if int(fighter.get("team", -1)) == Combatant.Team.ENEMY and int(fighter.get("phase", 1)) >= 2:
			return true
	return false


## A resume into a fight whose boss already raged: the arena's phase-two look at once and the rage
## song, with none of the live phase change's flash, shake or banner.
func _resume_mood(ev: Dictionary) -> void:
	if not raging_on_resume(ev):
		return
	view.shift_to_phase_two(true)
	if not rage_music_path.is_empty():
		Sfx.play_music(rage_music_path, rage_music_volume_db)


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
		_spotlight(actor)
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
	# Only what this hero brought into the fight (a run with skill trees, card #136).
	var known: Array = mirror.fighter(actor).get("ability_ids", [])
	var abilities: Array[AbilityData] = []
	for ability: AbilityData in data.all_abilities():
		if known.is_empty() or known.has(ability.id):
			abilities.append(ability)
	if _setup.team_ultimate != null:
		abilities.append(_setup.team_ultimate)
	if _setup.can_run and _setup.run_ability != null:
		abilities.append(_setup.run_ability)
	var entries: Array[Dictionary] = []
	for ability: AbilityData in abilities:
		entries.append(_menu_entry(actor, ability))
	# Backpack items (DESIGN.md 8.1): stand-in abilities named "item:<uid>" so the menu's lists,
	# costs and target step work the same.
	var uids: Array = mirror.items.keys()
	uids.sort()
	for uid: int in uids:
		var entry := _menu_entry(actor, _item_ability(mirror.items[uid] as Dictionary))
		entry["item"] = true
		# The list's short line and chips come from the item itself (card #292).
		for e: Dictionary in _setup.items:
			if int(e.uid) == uid:
				entry["item_data"] = e.item
				entry["amount"] = int(e.get("amount", (e.item as ItemData).amount_percent))
		entries.append(entry)
	if not tutorial_guide.is_empty():
		for entry: Dictionary in entries:
			if (entry.ability as AbilityData).id != tutorial_guide:
				entry.usable = false
				entry.reason = TUTORIAL_LOCKED
	hud.action_menu.actor_ap = int(mirror.fighter(actor).ap)
	hud.action_menu.actor_id = actor
	_spotlight(actor)
	hud.action_menu.max_ap = _tuning.max_ap
	hud.action_menu.open(data.color, entries, names)
	view.camera.shot_turn(view.home_of(actor))
	_set_active_pose(actor)
	menu_opened.emit(actor)
	if not _options.menu_keys.is_empty():
		_press_menu_keys.call_deferred()


## --menu-keys (dev tool, pictures of the menu): presses those actions on the menu; "|" starts the
## next turn's list.
func _press_menu_keys() -> void:
	var keys := PackedStringArray()
	while not _options.menu_keys.is_empty():
		var action := _options.menu_keys[0]
		_options.menu_keys.remove_at(0)
		if action == "|":
			break
		keys.append(action)
	for action: String in keys:
		await get_tree().create_timer(0.35).timeout
		var press := InputEventAction.new()
		press.action = StringName(action)
		press.pressed = true
		hud.action_menu.handle_input(press)


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
		AbilityData.Target.ALL_ALLIES:
			targets = mirror.living_party_ids()
			pick = false
	# Why it is locked, as a code the menu draws (a lock, a red cost, the Hush icon; phase 22). The
	# rules behind it (how to gain AP, what Hush does) are taught in the tutorial and the Glossary.
	var reason := ""
	if ability.team_ultimate and mirror.team_gauge < _tuning.team_gauge_max:
		reason = ActionMenu.LOCK_GAUGE
	elif _hushed_out(actor, ability):
		reason = ActionMenu.LOCK_HUSHED
	elif ap < ability.ap_cost:
		reason = ActionMenu.LOCK_AP
	elif targets.is_empty():
		reason = ActionMenu.LOCK_TARGET
	return {"ability": ability, "usable": reason.is_empty(), "reason": reason, "targets": targets, "pick_target": pick}


## True if a Hushed hero cannot use this skill (card #252; the engine's CombatEngine.is_hushed_out
## from the mirror): every skill is out, the basic attack, items, Run and the team ultimate stay.
func _hushed_out(actor: int, ability: AbilityData) -> bool:
	var f := mirror.fighter(actor)
	if not (f.get("statuses", {}) as Dictionary).has(Status.HUSHED):
		return false
	if ability.escape or ability.team_ultimate or ability.id.begins_with(ITEM_PREFIX):
		return false
	var slot := int(f.get("slot", -1))
	if _setup == null or slot < 0 or slot >= _setup.party.size() or _setup.party[slot].basic_attack == null:
		return true
	return ability.id != _setup.party[slot].basic_attack.id


## The stand-in ability for a fight item (cached per uid).
func _item_ability(info: Dictionary) -> AbilityData:
	var uid := int(info.uid)
	if _item_abilities.has(uid):
		return _item_abilities[uid]
	var ability := AbilityData.new()
	ability.id = ITEM_PREFIX + str(uid)
	ability.display_name = String(info.name)
	ability.description = String(info.description)
	ability.ap_cost = int(info.ap_cost)
	# Lets the bot see a cleansing item (Antidote, Holy Water, card #254).
	ability.cleanse_count = int(info.get("cleanse", 0))
	match String(info.target):
		CombatEngine.ITEM_ALLY:
			ability.target = AbilityData.Target.ALLY
		CombatEngine.ITEM_DOWNED:
			ability.target = AbilityData.Target.DOWNED_ALLY
		CombatEngine.ITEM_ENEMIES:
			ability.target = AbilityData.Target.ALL_ENEMIES
		_:
			ability.target = AbilityData.Target.SELF
	_item_abilities[uid] = ability
	return ability


## The backpack items used in this fight (uids): the run takes them out of the backpack.
func used_items() -> Array[int]:
	return mirror.used_items.duplicate()


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
	_spotlight(-1)
	if ability_id.begins_with(ITEM_PREFIX):
		var uid := int(ability_id.substr(ITEM_PREFIX.length()))
		_enqueue(_submit(CombatCommands.use_item(mirror.turn, mirror.active_actor, uid, targets)))
		return
	_enqueue(_submit(CombatCommands.use_ability(mirror.turn, mirror.active_actor, ability_id, targets)))


func _on_target_changed(target_id: int) -> void:
	hud.set_target(target_id)


func _on_combat_ended(result: String) -> void:
	_result = result
	_ended = true
	_ended_at_us = Time.get_ticks_usec()
	hud.action_menu.close()
	_set_active_pose(-1)
	_spotlight(-1)
	match result:
		"victory":
			Sfx.play("victory")
			_play_victory()
			if _run != null:
				_play_reward_sounds()
			_play_end_song(victory_music_path)
		"escaped":
			Sfx.play("dodge")
			# No end song: the fight song comes back after the jingle's beat if it was hushed.
			_play_end_song("")
		_:
			Sfx.play("defeat")
			_play_end_song(defeat_music_path)
	view.camera.shot_end(view.arena_centre())
	var hints := _end_hints()
	# The real game shows icons (phase 22); the lines of numbers stay for practice.
	var summary := _summary_text() if is_practice_fight() else ""
	hud.show_end(result, summary, hints, "The host goes on for everyone." if _net_mode == NetMode.CLIENT else "",
			_end_rewards())
	if _options.is_autoplay():
		_check_mirror()
		if _net_mode != NetMode.LOCAL:
			print("AUTOPLAY_MIRROR %s %d" % [result, var_to_str(mirror.projection()).hash()])
	combat_finished.emit(result)
	# A run fight hands the end back to Main, which decides when the run is over.
	if _options.quit_on_end and _run == null:
		get_tree().create_timer(QUIT_DELAY_S).timeout.connect(_quit)


## Gold, then level up when a hero levels (DESIGN.md 8.2): after the victory sound, one at a time,
## with LEVEL UP! over each hero who grew.
func _play_reward_sounds() -> void:
	var risen := _levelling_heroes()
	await _wait_ms(_visuals.reward_sound_delay_ms)
	Sfx.play("gold_gain")
	if risen.is_empty():
		return
	await _wait_ms(_visuals.level_up_sound_gap_ms)
	Sfx.play("level_up")
	for id: int in risen:
		var v := view.fighter(id)
		if v != null:
			hud.popup("LEVEL UP!", v.head_position(), HudStyle.GOLD, _visuals.level_up_popup_size)


## The fighter ids of the heroes this victory levels up (the run adds the XP later).
func _levelling_heroes() -> Array[int]:
	var ids: Array[int] = []
	var xp := _run.fight_xp(_encounter, party_hp())
	for id: int in mirror.party_ids:
		var slot := int(mirror.fighter(id).slot)
		if slot >= 0 and slot < xp.size() and _run.levels_from(slot, xp[slot]) > 0:
			ids.append(id)
	return ids


## The end screen's song, after the jingle (nothing if this place has none).
func _play_end_song(path: String) -> void:
	await _wait_ms(end_music_delay_ms)
	if not _ended or not is_inside_tree() or _quitting:
		return
	if path.is_empty():
		# No end song (MusicSet: the fight song goes on): back from the killing blow's silence.
		Sfx.hush_music(false, _visuals.kill_silence_fade_ms)
		return
	Sfx.play_music(path, rage_music_volume_db)


func _quit() -> void:
	_quitting = true
	Sfx.stop_all()
	await get_tree().create_timer(QUIT_AUDIO_RELEASE_S, true, false, true).timeout
	get_tree().quit(0)


func _on_press_judged(action: int, report: Dictionary) -> void:
	if int(report.get("result", DefenseJudge.Result.DONE)) == DefenseJudge.Result.SUCCESS:
		# Skill presses count by result (good or perfect), defence presses by button.
		var key := int(report.get("outcome", action)) if action == Defense.Outcome.PRESS else action
		_defended[key] = int(_defended.get(key, 0)) + 1


## What the end screen's buttons do ([[action, text], ...] for the HUD's hint bar). R (fight
## again) is a keyboard extra and is not listed. F1 Stats only in a practice fight (phase 22).
func _end_hints() -> Array:
	var hints: Array = [[&"menu_confirm", "Fight again"], [&"menu_cancel", "Choose a fight"]]
	if _net_mode == NetMode.CLIENT:
		hints = []
	elif _run != null and _result == "defeat":
		hints = [[&"menu_confirm", "See how the run went"]]
	elif _run != null:
		hints = [[&"menu_confirm", "On with the run"]]
	if is_practice_fight():
		hints.append([&"debug_overlay", "Stats"])
	return hints


## A won run fight's end screen as icons (phase 22, cards #273 and #274), instead of the lines of
## _summary_text: {chips: [{icon, text, color}] (gold, the find, flawless, the streak), heroes: [{portrait,
## text, level (new level, 0: none), down}]}. Empty outside a won run fight.
func _end_rewards() -> Dictionary:
	if _run == null or _result != "victory":
		return {}
	var chips: Array[Dictionary] = [{"icon": AssetLoader.texture(_visuals.gold_icon_path, Vector2i(12, 12)),
			"text": "+%d" % _run.gold_for(_encounter), "color": HudStyle.GOLD}]
	if _drop != null:
		chips.append({"icon": AssetLoader.texture(_drop.icon_path, Vector2i(16, 16)), "text": _drop.display_name,
				"color": HudStyle.TEXT})
	# A flawless win earns one more spoils choice (card #283).
	if RunState.is_flawless(_encounter, recap()):
		chips.append({"icon": null, "text": "FLAWLESS  +1 spoils", "color": HudStyle.GOLD})
	# The fight's best defence streak, once it was long enough to show (card #300).
	if mirror.best_defence_streak >= _visuals.streak_show_from:
		chips.append({"icon": AssetLoader.texture(_visuals.streak_chip_icon_path, Vector2i(16, 16)),
				"text": "Streak %d" % mirror.best_defence_streak, "color": HudStyle.GOLD})
	var heroes: Array[Dictionary] = []
	var xp := _run.fight_xp(_encounter, party_hp())
	var hp := party_hp()
	for id: int in mirror.party_ids:
		var slot := int(mirror.fighter(id).slot)
		if slot < 0 or slot >= _run.party_size():
			continue
		var up := _run.levels_from(slot, xp[slot])
		heroes.append({"portrait": hud.portrait(id), "text": "+%d XP" % xp[slot],
				"level": _run.levels[slot] + up if up > 0 else 0, "down": slot < hp.size() and hp[slot] <= 0})
	return {"chips": chips, "heroes": heroes}


## The fight so far as plain numbers (FightRecap.to_dict), read from the mirror (rule 7).
func recap() -> Dictionary:
	return mirror.recap.to_dict()


## What the fight adds to the Rot Journal (JournalTally.to_dict), read from the mirror (rule 7).
func journal_fight() -> Dictionary:
	return mirror.journal.to_dict()


## Online, this machine's Journal counts only its own players' defence (card #283).
func _journal_local_slots() -> void:
	var slots: Array[int] = []
	if _players != null and _players.is_online():
		for slot: int in _players.hero_count():
			if _players.is_local(_players.owner_of(slot)):
				slots.append(slot)
	mirror.journal.local_slots = slots


func _summary_text() -> String:
	var text := "%d enemy hits   parried %d, dodged %d, jumped %d   counters %d\nskill presses: perfect %d, good %d" % [
			_enemy_hits.size(), int(_defended.get(Defense.Outcome.PARRY, 0)),
			int(_defended.get(Defense.Outcome.DODGE, 0)), int(_defended.get(Defense.Outcome.JUMP, 0)), _counters,
			int(_defended.get(Defense.Outcome.PRESS_PERFECT, 0)), int(_defended.get(Defense.Outcome.PRESS, 0))]
	if _run != null and _result == "victory":
		text += "\n+%d gold" % _run.gold_for(_encounter)
		if _drop != null:
			text += "   Found: %s" % _drop.display_name
		if RunState.is_flawless(_encounter, recap()):
			text += "\nFlawless! One more spoils choice."
		var xp := _run.fight_xp(_encounter, party_hp())
		var parts := PackedStringArray()
		var risen := false
		for slot: int in _run.party_size():
			var part := "%s +%d XP" % [_run.data.party[slot].display_name, xp[slot]]
			var up := _run.levels_from(slot, xp[slot])
			if up > 0:
				part += " LEVEL UP! Lv %d" % (_run.levels[slot] + up)
				risen = true
			parts.append(part)
		text += "\n" + "    ".join(parts)
		if risen:
			text += "\nNew attribute points: spend them on the party screen."
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
	# Tall monsters stand at the back so they hide nobody (CombatView.enemy_spots).
	var heights: Array[float] = []
	for id: int in mirror.enemy_ids:
		var enemy := _find_data(String(mirror.fighter(id).data_id), false) as EnemyData
		heights.append(CombatView.enemy_height(enemy) if enemy != null else 0.0)
	var spots := CombatView.enemy_spots(heights, _visuals.enemy_positions)
	for id: int in mirror.fighters:
		var f := mirror.fighter(id)
		var is_party := int(f.team) == Combatant.Team.PARTY
		var data := _find_data(String(f.data_id), is_party)
		if data == null:
			push_error("CombatController: no data resource for '%s'" % String(f.data_id))
			continue
		_data_by_id[id] = data
		var slot := int(f.slot)
		if not is_party and slot < spots.size():
			slot = spots[slot]
		view.add_fighter(id, is_party, slot, data)
	hud.build_fighters(mirror, _data_by_id)
	_owners.clear()
	for id: int in mirror.party_ids:
		_owners[id] = _players.owner_of(_owner_slot(id))
	runner.set_players(_players, _owners)
	skill_runner.set_players(_players, _owners)
	PadRumble.set_party(_players, _owners)
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
	# The enemy panels are at full for the counter's damage, not still fading in (card #268).
	hud.show_enemy_panels()
	view.camera.shot_counter(view.home_of(int(ev.target)))
	var label := counter_label(team, int(ev.get("hits", 1)), bool(ev.get("mixed", false)))
	if team:
		hud.show_center_banner(label, HudStyle.GOLD, _visuals.team_banner_ms)
	else:
		var enemy := view.fighter(int(ev.target))
		if enemy != null:
			hud.popup(label, enemy.head_position(), HudStyle.GOLD)
	await _strike(actors, int(ev.target), "team_counter" if team else "counter", _take_following(), true, team)


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


func _strike(actors: Array[int], target: int, sfx: String, results: Array[Dictionary], is_counter: bool,
		team: bool = false) -> void:
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
		view.camera.add_trauma(_visuals.shake_team_counter if team else _visuals.shake_counter)
		view.camera.punch(_visuals.punch_team_counter if team else _visuals.punch_counter, _visuals.punch_ms)
		hud.screen_flash(HudStyle.PARRY, _visuals.screen_flash_counter)
	else:
		view.camera.add_trauma(_visuals.shake_strike)
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
	# Hit-stop: the slashes freeze on the impact frame, then play out. A counter has one, and so
	# does the blow that ends the fight or fells a boss (the longer of the two, once).
	var stop_ms := _tuning.hitstop_counter_ms if is_counter else 0
	stop_ms = maxi(stop_ms, _take_kill_freeze())
	if stop_ms > 0:
		for tween: Tween in slashes:
			tween.set_speed_scale(0.0)
		await _wait_ms(stop_ms)
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
	var crit := bool(ev.get("crit", false))
	var big := crit or int(ev.amount) * 100 >= max_hp * _visuals.big_hit_percent
	if crit:
		# CRITICAL! first, so the number pops under it (DESIGN.md 8.2).
		hud.popup("CRITICAL!", v.head_position(), HudStyle.GOLD, _visuals.crit_popup_size)
		Sfx.play("critical")
	hud.damage_number(int(ev.amount), v.head_position(), HudStyle.GOLD if crit else (HudStyle.DAMAGE_DEALT if to_enemy
			else HudStyle.DAMAGE_TAKEN), big)
	v.flash(_visuals.flash_ms)
	if to_enemy and crit:
		view.camera.add_trauma(_visuals.shake_crit)
		view.camera.punch(_visuals.punch_crit, _visuals.punch_ms)
	if mirror.is_alive(int(ev.target)):
		# A struck enemy recoils away from the heroes and settles back (card #179), more for a
		# heavy, critical or countered hit. Not during an enemy attack: the runner owns its body.
		if to_enemy and not runner.is_active():
			var heavy := big or String(ev.get("cause", "")) in STAGGER_CAUSES
			v.recoil(Vector3(_visuals.enemy_heavy_knockback if heavy else _visuals.enemy_hit_knockback, 0.0, 0.0),
					float(_visuals.recoil_out_ms) / 1000.0, float(_visuals.recoil_back_ms) / 1000.0)
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


## A support move on screen (card #259): the banner names it and the monster it helps, the helper
## winds up and casts, and the helped monster glows (the healed / status_changed events that follow
## show the numbers and the SHIELD word).
func _play_enemy_support(ev: Dictionary) -> void:
	var helper := view.fighter(int(ev.enemy))
	var helped := view.fighter(int(ev.target))
	var helped_name := String(mirror.fighter(int(ev.target)).get("display_name", ""))
	hud.show_banner(String(ev.get("name", "?")), HudStyle.HEAL, "> " + helped_name.to_upper())
	var voice := _voice_of(int(ev.enemy))
	if not voice.is_empty():
		Sfx.play(voice)
	if helper != null:
		helper.play("windup", _visuals.support_cast_ms, FighterView.PRIO_BIG)
	await _wait_ms(_visuals.support_cast_ms)
	Sfx.play("heal")
	if helper != null:
		helper.play("slam", _visuals.hurt_pose_ms, FighterView.PRIO_BIG)
	if helped != null:
		helped.flash(_visuals.flash_ms * 3, HudStyle.HEAL, 0.8)
	await _wait_ms(_visuals.support_cast_ms / 2)
	hud.hide_banner()


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
			if int(ev.delta) < 0 and String(ev.reason) == "drain" and v != null:
				# An enemy hit drained AP (card #194).
				Sfx.play("status_expired")
				hud.popup("%d AP" % int(ev.delta), head, HudStyle.STATUS_COLORS["ap_drain"] as Color)
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
			view.shift_to_phase_two()
			view.camera.add_trauma(_visuals.phase_shake)
			view.camera.punch(_visuals.phase_punch, _visuals.phase_punch_ms)
			PadRumble.everyone("boss_rage")
			var text := String(ev.get("text", ""))
			hud.show_center_banner(text if not text.is_empty() else "IT GROWS FURIOUS!", HudStyle.LATE,
					_visuals.first_strike_banner_ms)
		"doom_charging":
			_show_doom_banner(ev, int(ev.left))
		"doom_unleashed":
			_show_doom_unleashed(ev)
		"doom_broken":
			_show_doom_broken(ev)
		"stagger_changed":
			_show_stagger(ev)
		"healed":
			if v != null:
				if String(ev.get("cause", "")) == CombatEngine.CAUSE_DRAIN:
					# A drinking bite (card #323): the word over the number, so the heal reads as hers.
					Sfx.play("heal")
					hud.popup(DRAIN_TEXT, head, HudStyle.HEAL)
				hud.damage_number(int(ev.amount), head, HudStyle.HEAL)
				v.flash(_visuals.flash_ms * 2, HudStyle.HEAL, 0.7)
		"revived":
			if not _ended:
				# A Second Wind got the last hero back up after the killing blow's silence (card #308):
				# the fight goes on, and so does its song.
				Sfx.hush_music(false, _visuals.kill_silence_fade_ms)
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
		"defence_streak":
			_show_streak(ev)


## The defence streak (card #300): the chip over the gauge pops; a step reached (the gauge fills)
## plays its swell, buzzes every pad and lifts the music a little more; a hit that ends a long
## streak lets the music settle back.
func _show_streak(ev: Dictionary) -> void:
	var value := int(ev.value)
	var milestone := bool(ev.get("milestone", false))
	var lost := int(ev.get("lost", 0))
	hud.show_streak(value, milestone, lost)
	var step := maxi(1, _tuning.defence_streak_step)
	if milestone:
		Sfx.play(_visuals.streak_milestone_sfx)
		PadRumble.everyone("streak")
	# The song's lift follows the steps the streak has reached, so a rejoin's resume event (no
	# milestone) gets it back too; a hit that ends a streak of a step or more takes it off.
	@warning_ignore("integer_division")
	var steps_reached := value / step
	if steps_reached > 0 or lost >= step:
		Sfx.lift_music(minf(_visuals.streak_music_lift_max_db, _visuals.streak_music_lift_db * float(steps_reached)),
				_visuals.streak_music_fade_ms)


# --- charged dooms (card #195, DESIGN.md 2.3) -------------------------------------------------

## True if this intent event announces a Doom the mirror does not know yet (a retarget of a Doom
## already gathering does not count).
func _announces_doom(ev: Dictionary) -> bool:
	return ev.has("charge_total") and int(ev.charge_left) == int(ev.charge_total) \
			and not mirror.is_charging(int(ev.enemy))


## The Doom's banner: its name and the turns until it unleashes. Shown when it is announced and on
## every turn the enemy spends gathering it (a rumble, a flash in the doom colour, a sound).
func _show_doom_banner(ev: Dictionary, left: int) -> void:
	var title := String(ev.get("name", ev.get("attack", ""))).to_upper()
	var boss := view.fighter(int(ev.enemy))
	Sfx.play(_visuals.doom_gather_sfx)
	hud.show_center_banner("%s IN %d" % [title, left], _visuals.doom_text_color, _visuals.doom_gather_banner_ms)
	hud.screen_flash(_visuals.doom_glow_color, _visuals.doom_gather_flash)
	view.camera.add_trauma(_visuals.doom_gather_shake)
	if boss != null:
		boss.flash(_visuals.flash_ms * 3, _visuals.doom_glow_color, 0.8)
		boss.set_pose(EnemyChoreography.Pose.WINDUP)


## The countdown ran out: the Doom's name, a heavy rumble and punch-in, then its attack begins.
func _show_doom_unleashed(ev: Dictionary) -> void:
	var boss := view.fighter(int(ev.enemy))
	Sfx.play(_visuals.doom_unleash_sfx)
	hud.show_center_banner(String(ev.get("name", "")).to_upper() + "!", _visuals.doom_text_color,
			_visuals.doom_unleash_banner_ms)
	hud.screen_flash(_visuals.doom_glow_color, _visuals.doom_unleash_flash)
	view.camera.add_trauma(_visuals.doom_unleash_shake)
	view.camera.punch(_visuals.doom_unleash_punch, _visuals.punch_ms)
	PadRumble.everyone("doom")
	if boss != null:
		boss.flash(_visuals.flash_ms * 4, _visuals.doom_glow_color, 1.0)


## BROKEN!: the large tier (card #179). The freeze is kept in _kill_freeze_ms for whatever plays
## the event to wait out.
func _show_doom_broken(ev: Dictionary) -> void:
	var boss := view.fighter(int(ev.enemy))
	Sfx.play(_visuals.broken_sfx)
	hud.show_center_banner("BROKEN!", HudStyle.GOLD, _visuals.broken_banner_ms)
	hud.screen_flash(_visuals.broken_flash_color, _visuals.broken_flash)
	view.camera.add_trauma(_visuals.broken_shake)
	view.camera.punch(_visuals.broken_punch, _visuals.punch_ms)
	if boss != null:
		boss.set_squash(0.0)
		boss.flash(maxi(_visuals.broken_hitstop_ms, _visuals.flash_ms * 4), _visuals.broken_flash_color, 0.9)
		view.spawn_sparks(boss.centre_position(), _visuals.death_sparks, 1.0, _visuals.broken_flash_color)
	_kill_freeze_ms = maxi(_kill_freeze_ms, _visuals.broken_hitstop_ms)


## The stagger starts (the enemy falls into its stagger pose and holds it), costs a turn, or ends.
func _show_stagger(ev: Dictionary) -> void:
	var enemy := int(ev.enemy)
	var v := view.fighter(enemy)
	if v == null or not mirror.is_alive(enemy):
		return
	if bool(ev.lost_turn):
		hud.popup("TURN LOST", v.head_position(), _visuals.stagger_text_color)
		if int(ev.turns) <= 0:
			v.clear_timed_pose()
			v.set_pose(EnemyChoreography.Pose.IDLE)
		return
	Sfx.play(_visuals.stagger_sfx)
	hud.popup("STAGGERED", v.head_position(), _visuals.stagger_text_color)
	# Held until the stagger is over (a clip with a hold keeps its last cell).
	v.play("stagger", _visuals.stagger_pose_ms, FighterView.PRIO_BIG, EnemyChoreography.Pose.HURT, 0, true)


## Every frame: an enemy gathering a Doom pulses in the doom colour (quicker on its last turn) and
## crouches; a staggered one glows cold; when either ends the glow and crouch are switched off
## once. Everything else is left to the attack choreography.
func _update_doom_look() -> void:
	if view == null or mirror.enemy_ids.is_empty():
		return
	var now_ms := float(Time.get_ticks_msec())
	for id: int in mirror.enemy_ids:
		var v := view.fighter(id)
		if v == null:
			continue
		if mirror.is_charging(id):
			var cycle := float(_visuals.doom_pulse_ms)
			if int(mirror.fighter(id).charge_left) <= 1:
				cycle = cycle * float(_visuals.doom_pulse_last_percent) / 100.0
			var wave := 0.5 + 0.5 * sin(now_ms / maxf(1.0, cycle) * TAU)
			v.set_glow_color(_visuals.doom_glow_color)
			v.set_glow(lerpf(_visuals.doom_glow_min, _visuals.doom_glow_max, wave))
			v.set_squash(float(_visuals.doom_squash_percent) / 100.0)
			_doom_lit[id] = true
		elif mirror.is_staggered(id):
			v.set_glow_color(_visuals.stagger_glow_color)
			v.set_glow(_visuals.stagger_glow)
			v.set_squash(0.0)
			_doom_lit[id] = true
		elif bool(_doom_lit.get(id, false)):
			_doom_lit[id] = false
			v.set_glow(0.0)
			v.set_squash(0.0)


## A hero uses a backpack item: its name over the hero, a sound, a short beat before its effect
## (heals, a revive, the bomb's damage) plays from the events that follow.
func _play_item_used(ev: Dictionary) -> void:
	var actor := int(ev.actor)
	var v := view.fighter(actor)
	_set_active_pose(-1)
	Sfx.play("item_lift")
	hud.show_center_banner(String(ev.get("name", "")).to_upper(), HudStyle.GOLD, _visuals.item_use_ms)
	if v != null:
		v.flash(_visuals.flash_ms * 2, HudStyle.GOLD, 0.6)
		v.play_pose(FighterView.CharPose.READY, _visuals.item_use_ms)
	await get_tree().create_timer(float(_visuals.item_use_ms) / 1000.0).timeout


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
		view.camera.add_trauma(_visuals.downed_shake)
		PadRumble.hero("downed", id)
		if mirror.living_party_ids().is_empty():
			# The last hero down (card #308): the same silence and held frame as a killing blow.
			_killing_blow(HudStyle.DAMAGE_TAKEN, _visuals.screen_flash_downed)
		else:
			hud.screen_flash(HudStyle.DAMAGE_TAKEN, _visuals.screen_flash_downed)
		return
	# The large tier (card #179): the last enemy and a boss or guard fall with a held freeze,
	# shake, punch-in and flash. Whatever plays this kill waits out _kill_freeze_ms.
	var hold_ms := _big_kill(id)
	if not v.has_clip("death"):
		# A beaten enemy crumbles into rot (card #38).
		v.set_pose(EnemyChoreography.Pose.HURT)
		v.flash(_visuals.flash_ms * 2, _visuals.death_edge_color, _visuals.death_flash_strength)
		if hold_ms > 0:
			await _wait_ms(hold_ms)
			if not is_instance_valid(v):
				return
		v.dissolve(_visuals.death_dissolve_ms, _visuals.death_edge_color)
		view.spawn_sparks(v.centre_position(), _visuals.death_sparks, 1.0, _visuals.death_spark_color)
	else:
		if hold_ms > 0:
			# The body holds on its hurt pose, flashing, until the freeze ends; then the death clip.
			v.set_pose(EnemyChoreography.Pose.HURT)
			v.flash(hold_ms, Color.WHITE, 0.9)
			await _wait_ms(hold_ms)
			if not is_instance_valid(v):
				return
		_play_enemy_death(id, v)


## The large-tier impact for enemy `id` falling, if it is one (the fight's last enemy, or the boss
## of a boss or guard fight): shake, punch-in and screen flash now, and the freeze in ms (also
## kept in _kill_freeze_ms for whatever plays the kill to wait out). 0: a normal kill.
func _big_kill(id: int) -> int:
	var boss := _is_boss(id)
	if not boss and not mirror.living_enemy_ids().is_empty():
		return 0
	var hold_ms := _visuals.boss_kill_hitstop_ms if boss else _visuals.kill_hitstop_ms
	view.camera.add_trauma(_visuals.boss_kill_shake if boss else _visuals.kill_shake)
	view.camera.punch(_visuals.boss_kill_punch if boss else _visuals.kill_punch, _visuals.punch_ms)
	var flash := _visuals.boss_kill_flash if boss else _visuals.kill_flash
	if mirror.living_enemy_ids().is_empty():
		# The blow that ends the fight (card #308): silence and a held frame, then the flash.
		_killing_blow(Color.WHITE, flash)
	else:
		hud.screen_flash(Color.WHITE, flash)
	_kill_freeze_ms = maxi(_kill_freeze_ms, hold_ms)
	return hold_ms


## The blow that ends the fight (card #308): the song cuts to silence until the end song, so only
## the hit and the crumble are heard, and the scene holds a dark impact frame before the flash.
func _killing_blow(flash_color: Color, flash_strength: float) -> void:
	if _visuals.kill_silence:
		Sfx.hush_music(true, _visuals.kill_silence_fade_ms)
	hud.impact_frame(_visuals.impact_frame_color, _visuals.impact_frame_ms, flash_color, flash_strength)


## True for the boss of a boss or guard fight: the enemy with the most HP (the first of equals).
func _is_boss(id: int) -> bool:
	if _encounter == null or not (_encounter.boss or _encounter.mini_boss):
		return false
	var best := -1
	var best_hp := -1
	for enemy_id: int in mirror.enemy_ids:
		var data := _data_by_id.get(enemy_id) as EnemyData
		var hp := data.hp_percent if data != null else 0
		if hp > best_hp:
			best_hp = hp
			best = enemy_id
	return best == id


## The pending kill freeze (ms), cleared: whoever plays the kill waits it once.
func _take_kill_freeze() -> int:
	var ms := _kill_freeze_ms
	_kill_freeze_ms = 0
	return ms


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
## The turn spotlight (card #154): the acting hero steps forward onto a gold ring, the other heroes
## step away from them and dim, so whose turn it is reads at once. -1 sends everyone home.
func _spotlight(actor: int) -> void:
	if actor == _spot_actor:
		return
	_spot_actor = actor
	var seconds := float(_visuals.turn_spot_ms) / 1000.0
	var centre := view.home_of(actor) if actor >= 0 else Vector3.ZERO
	for id: int in mirror.party_ids:
		var v := view.fighter(id)
		if v == null:
			continue
		if actor < 0:
			v.set_stage(Vector3.ZERO, Color.WHITE, seconds)
			v.set_floor_warning(0.0, _visuals.turn_ring_color)
		elif id == actor:
			v.set_stage(_visuals.turn_step, Color.WHITE, seconds)
			v.set_floor_warning(_visuals.turn_ring_alpha, _visuals.turn_ring_color)
		else:
			# Back (away from the camera) and out to their own side, so they clear the menu.
			var side := signf(view.home_of(id).x - centre.x)
			var away := Vector3(side * 0.45, 0.0, -0.9).normalized() * _visuals.turn_step_away
			v.set_stage(away, _visuals.bystander_tint, seconds)
			v.set_floor_warning(0.0, _visuals.turn_ring_color)


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
	# The F1 stats panel is a practice tool: the real game has none (phase 22).
	if event.is_action_pressed("debug_overlay", false, true) and is_practice_fight():
		hud.overlay.toggle()
		return true
	if key == KEY_NONE:
		return false
	if hud.overlay.visible:
		# G, T, L, H, C and V change what the player sees or hears of an attack: practice only. A
		# run fight is the real game (card #179, DESIGN.md 3.7); F1 and F2 still work there.
		if _is_real_fight() and key in [KEY_G, KEY_T, KEY_L, KEY_H, KEY_C, KEY_V]:
			return false
		match key:
			KEY_R:
				# The training ring is a practice aid: a run fight is the real game.
				if not _is_real_fight():
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
			if engine.phase != CombatEngine.Phase.ENDED and not _is_real_fight():
				_enqueue(_submit(CombatCommands.practice({"invulnerable_party": not bool(mirror.practice.invulnerable_party)})))
			return true
		KEY_O:
			if engine.phase != CombatEngine.Phase.ENDED and not _is_real_fight():
				_enqueue(_submit(CombatCommands.practice({"immortal_enemies": not bool(mirror.practice.immortal_enemies)})))
			return true
		KEY_R:
			# A run fight cannot be started over: its HP and gold carry on.
			if not _is_real_fight():
				restart_requested.emit()
			return true
	var index := PRACTICE_ATTACK_KEYS.find(key)
	if index >= 0 and _is_real_fight():
		# A run fight is the real game: no forcing attacks.
		return false
	if index >= 0:
		var attacks := _practice_attacks()
		# The engine is already over while the last strike or attack still plays: nothing to force.
		if index < attacks.size() and engine.phase != CombatEngine.Phase.ENDED:
			_enqueue(_submit(CombatCommands.practice({"force_attack": attacks[index].id})))
		return true
	return false


## A run fight or the tutorial: the real game, so the practice keys are off (F1 and F2 still
## work). The tutorial sets up its own fight (an unbeatable enemy, a party that cannot fall), and
## I, O, R or 1-9 would break its lessons (card #248).
func _is_real_fight() -> bool:
	return _run != null or tutorial_mode


## A practice fight: the main menu's Practice fights and the dev switch's (--encounter without
## --run), played on this machine. Not a run, the tutorial or an online game.
func is_practice_fight() -> bool:
	return not _is_real_fight() and _net_mode == NetMode.LOCAL


## The attacks of the first living enemy (what 1-9 force).
func _practice_attacks() -> Array[EnemyAttackData]:
	var list: Array[EnemyAttackData] = []
	for id: int in mirror.living_enemy_ids():
		var data := _data_by_id.get(id) as EnemyData
		if data != null:
			list.append_array(data.all_attacks())
			break
	return list


func _practice_text() -> String:
	# Online the practice keys are off (they would change everyone's fight), and a run fight is the
	# real game: no practice panel there (F1 and F2 still work).
	if not _tuning.practice_tools_enabled or _net_mode != NetMode.LOCAL or _is_real_fight():
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
	# Shown in the F1 panel (card #275), where R is the ring: R restarts once F1 is closed.
	lines.append("F1 closed: R restart   F2 calibrate")
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


## An enemy's data by fighter id, also before the fighters are built (the first attack can come
## in the same batch as combat_started).
func _enemy_data_of(id: int) -> EnemyData:
	if _data_by_id.has(id):
		return _data_by_id[id] as EnemyData
	var data_id := String(_data_ids.get(id, ""))
	return _find_data(data_id, false) as EnemyData if not data_id.is_empty() else null


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
			_visuals.hit_icon_normal_path, _visuals.hit_icon_ground_path, _visuals.hit_icon_ranged_path]:
		AssetLoader.texture(path)


static func _pressed_key(event: InputEvent) -> Key:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return KEY_NONE
	return key.physical_keycode
