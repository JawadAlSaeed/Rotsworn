class_name Autoplay
extends Node
## Test bot for `-- --autoplay[=perfect|miss|mash]` (DESIGN.md 10). It plays through the same
## paths as a person: menu choices go through the ActionMenu, defence and skill presses are
## injected into DefenseInput and judged like real ones.
## - perfect: the correct press for every hit (parry for normal, jump for ground, the skill
##   button for skill and follow-up presses) at window centre;
## - miss: never presses;
## - mash: random presses about every MASH_INTERVAL_MS.
## Menu choices: the team ultimate when ready, Revive when someone is down, otherwise the usable
## class skills in turn, otherwise the basic attack; ally skills go to the most hurt ally.
## At the end it prints exactly one "AUTOPLAY_RESULT victory|defeat" line and one
## "AUTOPLAY_STATS ..." line.

## Pause before picking an action, so the menu is visible for a moment.
const CHOOSE_DELAY_MS: int = 250
const MASH_INTERVAL_MS: int = 70
const MASH_JITTER_MS: int = 20
const MASH_ACTIONS: Array[int] = [Defense.Outcome.PARRY, Defense.Outcome.DODGE, Defense.Outcome.JUMP,
		Defense.Outcome.PRESS]

var _mode: String = CombatOptions.AUTOPLAY_PERFECT
var _mirror: CombatMirror
var _runner: TimedSequenceRunner
var _skill_runner: SkillSequenceRunner
var _input: DefenseInput
var _menu: ActionMenu
var _tuning: Tuning
var _rng := RandomNumberGenerator.new()
var _seq: int = -1
var _pressed: Dictionary = {}
var _next_mash_us: int = 0
var _last_frame_us: int = 0
var _frame_us: int = 0
var _reported: bool = false
var _menu_picks: int = 0
var _stats: Dictionary = {
	"parries": 0, "dodges": 0, "jumps": 0, "presses": 0, "perfect_presses": 0, "whiffs": 0,
	"hits_taken": 0, "counters": 0, "team_counters": 0, "skills": 0, "ultimates": 0,
}


func setup(mode: String, mirror: CombatMirror, runner: TimedSequenceRunner, skill_runner: SkillSequenceRunner,
		input: DefenseInput, menu: ActionMenu, tuning: Tuning) -> void:
	_mode = mode
	_mirror = mirror
	_runner = runner
	_skill_runner = skill_runner
	_input = input
	_menu = menu
	_tuning = tuning
	_rng.randomize()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	_frame_us = now - _last_frame_us if _last_frame_us > 0 else 0
	_last_frame_us = now
	if not _runner.is_defending() and not _skill_runner.is_defending():
		return
	match _mode:
		CombatOptions.AUTOPLAY_PERFECT:
			_press_perfectly()
		CombatOptions.AUTOPLAY_MASH:
			_mash()


## The controller opened the menu for this party member: pick an ability and a target.
func on_menu_opened(actor_id: int) -> void:
	var turn := _mirror.turn
	# A Timer child: if the fight is freed the wait never resumes on a freed bot.
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = float(CHOOSE_DELAY_MS) / 1000.0
	add_child(timer)
	timer.start()
	await timer.timeout
	timer.queue_free()
	if not _menu.is_open() or _mirror.turn != turn or _mirror.active_actor != actor_id:
		return
	var choice := _pick_ability()
	if choice == null or not _menu.choose(choice.id, _pick_target(choice)):
		print("AUTOPLAY_ERROR could not choose an ability for fighter %d" % actor_id)
		return
	_menu_picks += 1
	if choice.team_ultimate:
		_stats.ultimates += 1
	elif choice.ap_cost > 0:
		_stats.skills += 1


func on_press_judged(action: int, report: Dictionary) -> void:
	match int(report.get("result", DefenseJudge.Result.DONE)):
		DefenseJudge.Result.SUCCESS:
			match action:
				Defense.Outcome.PARRY:
					_stats.parries += 1
				Defense.Outcome.DODGE:
					_stats.dodges += 1
				Defense.Outcome.JUMP:
					_stats.jumps += 1
				Defense.Outcome.PRESS:
					_stats.presses += 1
					if int(report.get("outcome", -1)) == Defense.Outcome.PRESS_PERFECT:
						_stats.perfect_presses += 1
		DefenseJudge.Result.WHIFF:
			_stats.whiffs += 1


func on_event(event: Dictionary) -> void:
	match String(event.get("type", "")):
		"prompt_resolved":
			var defending := String(_mirror.sequence.get("kind", "")) == CombatEngine.SEQUENCE_ENEMY_ATTACK
			if defending and int(event.outcome) == Defense.Outcome.NONE:
				_stats.hits_taken += 1
		"counter":
			if bool(event.team):
				_stats.team_counters += 1
			else:
				_stats.counters += 1


func on_combat_finished(result: String) -> void:
	if _reported:
		return
	_reported = true
	print("AUTOPLAY_RESULT %s" % result)
	print(("AUTOPLAY_STATS parries=%d dodges=%d jumps=%d presses=%d perfect=%d whiffs=%d hits_taken=%d"
			+ " counters=%d team_counters=%d skills=%d ultimates=%d gauge=%d") % [_stats.parries, _stats.dodges,
			_stats.jumps, _stats.presses, _stats.perfect_presses, _stats.whiffs, _stats.hits_taken, _stats.counters,
			_stats.team_counters, _stats.skills, _stats.ultimates, _mirror.team_gauge])


func _pick_ability() -> AbilityData:
	var usable: Array[AbilityData] = []
	var basic: AbilityData = null
	for ability: AbilityData in _menu.abilities():
		if not _menu.is_usable(ability.id):
			continue
		if ability.team_ultimate or ability.revive_percent > 0:
			return ability
		if ability.ap_cost == 0 and basic == null:
			basic = ability
		else:
			usable.append(ability)
	if not usable.is_empty():
		return usable[_menu_picks % usable.size()]
	return basic


## The most hurt ally for ally skills, else the first target offered.
func _pick_target(ability: AbilityData) -> int:
	var targets := _menu.targets_of(ability.id)
	if targets.is_empty():
		return -1
	if ability.target != AbilityData.Target.ALLY and ability.target != AbilityData.Target.OTHER_ALLY:
		return targets[0]
	var best := targets[0]
	for id: int in targets:
		var f := _mirror.fighter(id)
		var b := _mirror.fighter(best)
		if int(f.hp) * int(b.max_hp) < int(b.hp) * int(f.max_hp):
			best = id
	return best


## Presses the perfect action for the next open prompt when the sequence time reaches its window
## centre (plus the lag compensation the judge will subtract).
func _press_perfectly() -> void:
	var sequence := _mirror.sequence
	var skill := _skill_runner.is_defending()
	var runner_paused := _skill_runner.is_clock_paused() if skill else _runner.is_clock_paused()
	if sequence.is_empty() or runner_paused:
		return
	if int(sequence.seq) != _seq:
		_seq = int(sequence.seq)
		_pressed.clear()
	var t := _skill_runner.attack_time_us() if skill else _runner.attack_time_us()
	var latency := _skill_runner.latency_us() if skill else _runner.latency_us()
	for hit: Dictionary in sequence.hits:
		var hit_index := int(hit.index)
		if _pressed.has(hit_index):
			continue
		var prompt := _open_prompt(sequence, hit_index, skill)
		if prompt.is_empty():
			_pressed[hit_index] = true
			continue
		var action := int((prompt.perfect as Array)[0])
		var edges: Array = prompt.windows[action]
		@warning_ignore("integer_division")
		var centre := int(prompt.at_ms) * 1000 + (int(edges[0]) + int(edges[1])) / 2
		# Half a frame early: the press lands on average at the centre even when frames are slow.
		@warning_ignore("integer_division")
		var lead_us := _frame_us / 2
		if t + lead_us >= centre + latency:
			_pressed[hit_index] = true
			# A perfect skill press is still the skill button.
			_input.inject_press(Defense.Outcome.PRESS if action == Defense.Outcome.PRESS_PERFECT else action)
		return


func _mash() -> void:
	var now := Time.get_ticks_usec()
	if now < _next_mash_us:
		return
	_next_mash_us = now + (MASH_INTERVAL_MS + _rng.randi_range(-MASH_JITTER_MS, MASH_JITTER_MS)) * 1000
	_input.inject_press(MASH_ACTIONS[_rng.randi_range(0, MASH_ACTIONS.size() - 1)])


## The first prompt of a hit that can still be answered, or {}.
func _open_prompt(sequence: Dictionary, hit_index: int, skill: bool) -> Dictionary:
	var prompts: Array = sequence.prompts
	var states: Array = sequence.states
	for i: int in prompts.size():
		var prompt: Dictionary = prompts[i]
		if int(prompt.hit) != hit_index:
			continue
		if skill:
			if _skill_runner.is_prompt_open(i):
				return prompt
		elif int(states[i]) == CombatEngine.PromptState.PENDING and _mirror.is_alive(int(prompt.character)):
			return prompt
	return {}
