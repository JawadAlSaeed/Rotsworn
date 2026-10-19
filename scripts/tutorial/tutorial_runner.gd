class_name TutorialRunner
extends Node
## Runs the tutorial (DESIGN.md 7.8, card #131). Every step is staged: the game waits while a
## card explains it (Enter to go), the player tries with only a one-line reminder on screen, then
## the game waits again for a card saying how it went: "Well done!" moves on, "Try again" repeats
## the same try. In the fight only what the step needs happens (practice staging commands): in the
## attack, skill and ultimate steps only the lesson's hero acts and their menu allows only the
## lesson's choice; in the defend steps the heroes' turns pass and the enemy waits at a gate until
## the card is closed, then makes the step's one attack, slowed. A "read" step (the Relics and
## Echoes lesson, DESIGN.md 8.17) is only its card: the fight stays paused and closing it moves on.
## Main routes the fight's `pause_reached` here while `pause_wanted()`.

## The end card was closed: back to the main menu.
signal leave_requested

const PRAISE := "Well done!"
const RETRY := "Try again"

var _data: TutorialData
var _step: int = -1
var _overlay: TutorialOverlay
var _fight: CombatController
## The fight has started (practice commands are accepted).
var _fight_ready: bool = false
## Ability ids that are not skills (basic attacks, the ultimate, Run).
var _not_skills: Array[String] = []
## The card to show once the fight has paused: "step", "good", "retry" or "" (none wanted).
var _pending: String = ""
## The card on screen now ("" while the player tries).
var _card: String = ""
## The current try: a sequence of the step's kind was declared; the goal was seen.
var _trying: bool = false
var _reached: bool = false
var _done: bool = false
## A hero step's card waits until the lesson hero's turn menu is open (the card talks about it).
var _wait_menu: bool = false
## The bot (autoplay) closes each card after this many seconds (0: a person presses Enter).
var auto_confirm_s: float = 0.0
## Counts cards, so a bot timer only closes the card it was started for.
var _card_serial: int = 0


func setup(data: TutorialData) -> void:
	_data = data
	_overlay = TutorialOverlay.new()
	_overlay.name = "TutorialOverlay"
	add_child(_overlay)
	for c: CharacterData in data.encounter.party:
		if c != null and c.basic_attack != null:
			_not_skills.append(c.basic_attack.id)
	_not_skills.append("run")


## Starts at step `from` (0: the first; --tutorial-step=N for pictures of a later one).
func start(from: int = 0) -> void:
	_go_to(clampi(from, 0, maxi(0, _data.steps.size() - 1)))


func current() -> TutorialStepData:
	return _data.steps[_step] if _step >= 0 and _step < _data.steps.size() else null


func attach_fight(fight: CombatController) -> void:
	_fight = fight
	_fight_ready = false
	fight.set_tutorial(true)
	fight.event_played.connect(_on_fight_event)
	fight.menu_opened.connect(_on_menu_opened)


## True while the tutorial waits for the fight to pause (Main sends pause_reached here).
func pause_wanted() -> bool:
	return not _pending.is_empty()


## The fight has paused for the tutorial: its card shows.
func on_paused() -> void:
	var kind := _pending
	_pending = ""
	match kind:
		"step":
			_show_step_card()
		"good":
			_show_good_card()
		"retry":
			_show_retry_card()


## Skips the current step (from the pause menu).
func skip() -> void:
	if not _done:
		_card = ""
		_go_to(_step + 1)


func _input(event: InputEvent) -> void:
	if _card.is_empty():
		return
	# The card holds the game: no key, button or click reaches anything behind it.
	if not (event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion
			or event is InputEventMouseButton):
		return
	if event.is_action_pressed(&"pause", false, true):
		return
	get_viewport().set_input_as_handled()
	if event.is_action_pressed(&"menu_confirm", false, true):
		Sfx.play("menu_confirm")
		_close_card()


func _close_card() -> void:
	var kind := _card
	_card = ""
	match kind:
		"done":
			leave_requested.emit()
		"good":
			_go_to(_step + 1)
		"step" when current() != null and current().goal == TutorialGoals.READ:
			_go_to(_step + 1)
		_:
			# "step" or "retry": the player tries now.
			_overlay.show_reminder(current().reminder)
			_begin_try()


## Lets the player try: the fight goes on (a defend step's attack is let through the gate).
func _begin_try() -> void:
	_trying = false
	_reached = false
	if current().hold == "party":
		_fight.practice_command({"open_gate": true})
	_fight.resume_after_pause()


func _go_to(index: int) -> void:
	_step = index
	if _step >= _data.steps.size():
		_done = true
		_card = "done"
		_overlay.show_card("", _data.done_title, _data.done_text, "", "Main menu", true)
		return
	if not _fight_ready:
		# The fight's first event stages the step.
		return
	if current().goal == TutorialGoals.READ:
		# Only a card to read: the fight stays as it is (paused after the last try's card).
		_show_step_card()
		return
	if _stage(current()):
		# The turn moves on to the lesson's hero first; the card shows with their menu.
		_overlay.hide_all()
		_wait_menu = true
		_fight.resume_after_pause()
		return
	_show_step_card()


## Sets the fight up for a step: who acts, the enemy's gate, tempo, AP and gauge. Returns true
## when a hero step must first wait for its hero's turn menu.
func _stage(step: TutorialStepData) -> bool:
	var defend := step.hold == "party"
	var hero := _hero_id(step.hero)
	var engine := _fight.engine
	var wait := hero >= 0 and (engine.phase != CombatEngine.Phase.AWAITING_ACTION or engine.active_actor != hero)
	if wait or defend:
		# That turn is passed: its menu goes now, not after the card.
		_fight.hud.action_menu.close()
	# The menu allows only the lesson's choice (redrawn at once if it is open).
	_fight.set_tutorial_guide(step.ability)
	_fight.practice_command({"hold_party": defend, "hold_enemies": step.hold == "enemies", "gate": defend,
			"hero": hero, "tempo_percent": step.tempo_percent, "stage_attack": step.forced_attack,
			"full_ap": step.full_ap, "fill_gauge": step.fill_gauge,
			"mark_hero": _hero_id(step.mark_hero), "mark_status": step.mark_status,
			# A hero choosing goes on to the enemy's gate (or to the lesson's hero); an enemy at the
			# gate lets the heroes act.
			"pass_turn": defend or engine.phase == CombatEngine.Phase.AWAITING_GATE
					or (wait and engine.phase == CombatEngine.Phase.AWAITING_ACTION)})
	return wait


## The fighter id of the lesson's hero (a character id), or -1 for none.
func _hero_id(character: String) -> int:
	if character.is_empty():
		return -1
	for c: Combatant in _fight.engine.combatants:
		if c.is_party() and c.data_id == character:
			return c.id
	return -1


func _show_step_card() -> void:
	var step := current()
	if step == null:
		return
	_card = "step"
	_auto_confirm()
	_overlay.show_card("Lesson %d of %d" % [step.lesson, _data.lesson_count()], step.title, step.text, step.tip)


func _show_good_card() -> void:
	var next := _data.steps[_step + 1] if _step + 1 < _data.steps.size() else null
	_card = "good"
	_auto_confirm()
	Sfx.play("level_up")
	_overlay.show_card(current().title, PRAISE, "Next: %s." % next.title if next != null else "That was the last one.",
			"", "Next", true)


func _show_retry_card() -> void:
	_card = "retry"
	_auto_confirm()
	_overlay.show_card(current().title, RETRY, current().retry, "", "Try again")


## The bot's way through a card: it closes by itself after auto_confirm_s.
func _auto_confirm() -> void:
	_card_serial += 1
	if auto_confirm_s <= 0.0:
		return
	var serial := _card_serial
	get_tree().create_timer(auto_confirm_s).timeout.connect(func() -> void:
		if serial == _card_serial and not _card.is_empty():
			_close_card())


func _on_fight_event(ev: Dictionary) -> void:
	var type := String(ev.get("type", ""))
	if not _fight_ready and type in ["combat_started", "turn_started"]:
		_fight_ready = true
		_fight.practice_command({"invulnerable_party": true, "immortal_enemies": true})
		if current() != null:
			_stage(current())
			if current().hold == "enemies":
				_wait_menu = true
			else:
				_ask_pause("step")
		return
	var step := current()
	if step == null or not _card.is_empty() or not _pending.is_empty() or _wait_menu:
		return
	var kind := CombatEngine.SEQUENCE_ENEMY_ATTACK if step.hold == "party" else CombatEngine.SEQUENCE_SKILL
	if type == "timed_sequence_declared" and String(ev.get("kind", "")) == kind:
		_trying = true
	if TutorialGoals.reached(step.goal, ev, _fight.mirror.sequence, "team_ultimate", _not_skills):
		_reached = true
	# A try ends with its turn (after any counter), then the game waits for the result card.
	if type == "turn_ended" and (_trying or _reached):
		_ask_pause("good" if _reached else "retry")


func _on_menu_opened(actor_id: int) -> void:
	var step := current()
	if not _wait_menu or step == null:
		return
	var hero := _hero_id(step.hero)
	if hero >= 0 and actor_id != hero:
		return
	_wait_menu = false
	_ask_pause("step")


func _ask_pause(kind: String) -> void:
	_pending = kind
	if not _fight.request_pause(true):
		# Already paused (or ending): show it at once.
		if _fight.is_paused():
			on_paused()
