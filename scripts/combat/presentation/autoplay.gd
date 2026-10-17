class_name Autoplay
extends Node
## Test bot for `-- --autoplay[=perfect|miss|mash]` (DESIGN.md 10). It plays through the same
## paths as a person: menu choices go through the ActionMenu, defence and skill presses are
## injected into DefenseInput and judged like real ones.
## - perfect: the correct press for every hit (Defense.best_outcome: parry for a normal hit or a
##   rend, dodge for a sweep, jump for ground, the skill button for skill and follow-up presses)
##   at window centre;
## - miss: never presses;
## - mash: random presses about every MASH_INTERVAL_MS;
## - average: like a person of `bot_skill` percent (balance checks): each defence is landed with
##   that chance (a parry or a dodge, a jump for a ground hit), otherwise it is not pressed; each
##   skill press is landed with that chance, half of those perfect and half good. A rend or a sweep
##   (card #187) is read first: it is misread (the other of parry and dodge, on time) with
##   (100 - skill) * MISREAD_SHARE_PERCENT / 100 percent chance, so a better player misreads less.
## In co-op (--players=N) each player presses for their own heroes with their own device, so the
## per-player judging is played through too; mash presses as a random player. Online it presses
## only for this machine's player.
## Menu choices: the team ultimate when ready, Revive when someone is down, otherwise the usable
## class skills in turn, otherwise the basic attack; ally skills go to the most hurt ally.
## At the end it prints exactly one "AUTOPLAY_RESULT victory|defeat" line and one
## "AUTOPLAY_STATS ..." line.

## Pause before picking an action, so the menu is visible for a moment.
## Uses a healing item when a standing hero is at or under this percent of max HP.
const ITEM_HEAL_BELOW_PERCENT: int = 40
const CHOOSE_DELAY_MS: int = 250
const MASH_INTERVAL_MS: int = 70
const MASH_JITTER_MS: int = 20
const MASH_ACTIONS: Array[int] = [Defense.Outcome.PARRY, Defense.Outcome.DODGE, Defense.Outcome.JUMP,
		Defense.Outcome.PRESS]
## Average bot: share of its missing skill that shows up as misreading a rend or a sweep (a decent
## reader at skill 70 reads 85% of them right; the timing roll comes after).
const MISREAD_SHARE_PERCENT: int = 50

var _mode: String = CombatOptions.AUTOPLAY_PERFECT
var _mirror: CombatMirror
var _runner: TimedSequenceRunner
var _skill_runner: SkillSequenceRunner
var _input: DefenseInput
var _menu: ActionMenu
var _tuning: Tuning
var _rng := RandomNumberGenerator.new()
var _seq: int = -1
## Average bot: its decision per "plan:seq:hit:player".
var _plans: Dictionary = {}
## "hit:player" keys already pressed (or with nothing to press) in this sequence.
var _pressed: Dictionary = {}
var _roster: PlayerRoster = PlayerRoster.solo(0)
## Party member id -> player.
var _owners: Dictionary = {}
var _next_mash_us: int = 0
var _last_frame_us: int = 0
var _frame_us: int = 0
var _reported: bool = false
var _menu_picks: int = 0
## Percent of presses the average bot lands (CombatOptions.bot_skill).
var bot_skill: int = CombatOptions.DEFAULT_BOT_SKILL
## Average bot: when the fight started (real time, ms) for the stats line.
var _started_ms: int = 0
var _stats: Dictionary = {
	"parries": 0, "dodges": 0, "jumps": 0, "presses": 0, "perfect_presses": 0, "whiffs": 0,
	"hits_taken": 0, "counters": 0, "team_counters": 0, "skills": 0, "ultimates": 0,
	"dooms": 0, "broken": 0, "unleashed": 0,
}
## Enemies whose announced Doom has not been broken or unleashed yet (card #195).
var _dooms_open: Dictionary = {}


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


## Makes the average bot's luck repeatable (--seed): the same seed lands the same presses, so a
## balance check can be run again on another version.
func set_seed(value: int) -> void:
	_rng.seed = value


## Who plays which hero (see CombatController).
func set_players(roster: PlayerRoster, owners: Dictionary) -> void:
	_roster = roster
	_owners = owners


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	_frame_us = now - _last_frame_us if _last_frame_us > 0 else 0
	_last_frame_us = now
	if not _runner.is_defending() and not _skill_runner.is_defending():
		return
	if _started_ms == 0:
		_started_ms = Time.get_ticks_msec()
	match _mode:
		CombatOptions.AUTOPLAY_PERFECT, CombatOptions.AUTOPLAY_ESCAPE, CombatOptions.AUTOPLAY_AVERAGE:
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
	if choice != null and choice.escape:
		# Run like a player: hold Back until the ring around it fills (DESIGN.md 2.13).
		_menu.hold_run()
		_menu_picks += 1
		return
	if choice == null or not _menu.choose(choice.id, _pick_target(choice)):
		print("AUTOPLAY_ERROR could not choose an ability for fighter %d" % actor_id)
		return
	_menu_picks += 1
	if choice.id.begins_with(CombatController.ITEM_PREFIX):
		print("AUTOPLAY_ITEM %s" % choice.display_name)
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
		"intent":
			if event.has("charge_total") and not _dooms_open.has(int(event.enemy)):
				_dooms_open[int(event.enemy)] = true
				_stats.dooms += 1
		"doom_broken":
			_dooms_open.erase(int(event.enemy))
			_stats.broken += 1
		"doom_unleashed":
			_dooms_open.erase(int(event.enemy))
			_stats.unleashed += 1


func on_combat_finished(result: String) -> void:
	if _reported:
		return
	_reported = true
	print("AUTOPLAY_RESULT %s" % result)
	print(("AUTOPLAY_STATS parries=%d dodges=%d jumps=%d presses=%d perfect=%d whiffs=%d hits_taken=%d"
			+ " counters=%d team_counters=%d skills=%d ultimates=%d gauge=%d") % [_stats.parries, _stats.dodges,
			_stats.jumps, _stats.presses, _stats.perfect_presses, _stats.whiffs, _stats.hits_taken, _stats.counters,
			_stats.team_counters, _stats.skills, _stats.ultimates, _mirror.team_gauge])
	if int(_stats.dooms) > 0:
		print("AUTOPLAY_DOOMS announced=%d broken=%d unleashed=%d" % [_stats.dooms, _stats.broken, _stats.unleashed])
	# Balance numbers: turns, real seconds, and the party's HP left (percent of max, standing).
	var hp := 0
	var max_hp := 0
	for id: int in _mirror.party_ids:
		var f := _mirror.fighter(id)
		max_hp += int(f.max_hp)
		hp += int(f.hp) if bool(f.alive) else 0
	@warning_ignore("integer_division")
	print("AUTOPLAY_BALANCE turns=%d seconds=%d party_hp_percent=%d" % [_mirror.turn,
			(Time.get_ticks_msec() - _started_ms) / 1000, hp * 100 / maxi(1, max_hp)])


func _pick_ability() -> AbilityData:
	var usable: Array[AbilityData] = []
	var basic: AbilityData = null
	var item := _pick_item()
	if item != null:
		return item
	for ability: AbilityData in _menu.abilities():
		if ability.escape and _mode == CombatOptions.AUTOPLAY_ESCAPE and _menu.is_usable(ability.id):
			return ability
		if not _menu.is_usable(ability.id) or ability.escape or ability.id.begins_with(CombatController.ITEM_PREFIX):
			continue
		if ability.team_ultimate or ability.revive_percent > 0:
			return ability
		if ability.cleanse_count > 0 and _any_marked():
			# The healer lifts a mark (rot, blight, weakness) before it costs the party more.
			return ability
		if ability.ap_cost == 0 and basic == null:
			basic = ability
		else:
			usable.append(ability)
	if not usable.is_empty():
		return usable[_menu_picks % usable.size()]
	return basic


## A backpack item worth using now (DESIGN.md 8.1), or null: a revive when someone is down, a heal
## when someone is at or under ITEM_HEAL_BELOW_PERCENT, a bomb against two or more enemies.
func _pick_item() -> AbilityData:
	var hurt := false
	for id: int in _mirror.living_party_ids():
		var f := _mirror.fighter(id)
		hurt = hurt or int(f.hp) * 100 <= int(f.max_hp) * ITEM_HEAL_BELOW_PERCENT
	for ability: AbilityData in _menu.abilities():
		if not ability.id.begins_with(CombatController.ITEM_PREFIX) or not _menu.is_usable(ability.id):
			continue
		match ability.target:
			AbilityData.Target.DOWNED_ALLY:
				return ability
			AbilityData.Target.ALLY, AbilityData.Target.SELF:
				if hurt:
					return ability
			AbilityData.Target.ALL_ENEMIES:
				if _mirror.living_enemy_ids().size() >= 2:
					return ability
	return null


## True if a standing hero carries a hero debuff (card #194).
func _any_marked() -> bool:
	for id: int in _mirror.living_party_ids():
		if _is_marked(id):
			return true
	return false


func _is_marked(id: int) -> bool:
	var statuses: Dictionary = _mirror.fighter(id).get("statuses", {})
	for debuff: String in Status.DEBUFFS:
		if statuses.has(debuff):
			return true
	return false


## The most hurt ally for ally skills (a marked one first for a cleansing skill); against enemies the
## one gathering a Doom (card #195: the party breaks it), else the first target offered.
func _pick_target(ability: AbilityData) -> int:
	var targets := _menu.targets_of(ability.id)
	if targets.is_empty():
		return -1
	if ability.target != AbilityData.Target.ALLY and ability.target != AbilityData.Target.OTHER_ALLY:
		for id: int in targets:
			if _mirror.is_charging(id):
				return id
		return targets[0]
	if ability.cleanse_count > 0:
		var marked: Array[int] = []
		for id: int in targets:
			if _is_marked(id):
				marked.append(id)
		if not marked.is_empty():
			targets = marked
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
	for player: int in _roster.local_players():
		for hit: Dictionary in sequence.hits:
			var hit_index := int(hit.index)
			var key := "%d:%d" % [hit_index, player]
			if _pressed.has(key):
				continue
			var prompt := _open_prompt(sequence, hit_index, skill, player)
			if prompt.is_empty():
				_pressed[key] = true
				continue
			var action := Defense.best_outcome(int(prompt.kind))
			var edges: Array = prompt.windows[action]
			@warning_ignore("integer_division")
			var centre := int(prompt.at_ms) * 1000 + (int(edges[0]) + int(edges[1])) / 2
			if _mode == CombatOptions.AUTOPLAY_AVERAGE:
				var plan := _average_plan(key, prompt, skill)
				if plan.is_empty():
					_pressed[key] = true
					continue
				action = int(plan.action)
				centre = int(plan.at_us)
			# Half a frame early: the press lands on average at the centre even when frames are slow.
			@warning_ignore("integer_division")
			var lead_us := _frame_us / 2
			if t + lead_us >= centre + latency:
				_pressed[key] = true
				# A perfect skill press is still the skill button.
				_input.inject_press(Defense.Outcome.PRESS if action == Defense.Outcome.PRESS_PERFECT else action,
						_roster.device_of_player(player))
			break


func _mash() -> void:
	var now := Time.get_ticks_usec()
	if now < _next_mash_us:
		return
	_next_mash_us = now + (MASH_INTERVAL_MS + _rng.randi_range(-MASH_JITTER_MS, MASH_JITTER_MS)) * 1000
	var players := _roster.local_players()
	if players.is_empty():
		return
	var player := players[_rng.randi_range(0, players.size() - 1)]
	_input.inject_press(MASH_ACTIONS[_rng.randi_range(0, MASH_ACTIONS.size() - 1)], _roster.device_of_player(player))


## The average bot's choice for one prompt, decided once per hit and player: {} (let it go) or
## {action, at_us}: a parry or a dodge for a normal hit, a jump for a ground hit, a perfect or a
## good skill press.
func _average_plan(key: String, prompt: Dictionary, skill: bool) -> Dictionary:
	var plan_key := "plan:%d:%s" % [_seq, key]
	if _plans.has(plan_key):
		return _plans[plan_key]
	var plan: Dictionary = {}
	var kind := int(prompt.kind)
	@warning_ignore("integer_division")
	var misread_percent := (100 - bot_skill) * MISREAD_SHARE_PERCENT / 100
	if not skill and AttackHitData.is_forced(kind) and _rng.randi_range(1, 100) <= misread_percent:
		# Misread: the other button, pressed on time (a whiff, the hit lands).
		var wrong := Defense.Outcome.DODGE if kind == AttackHitData.Kind.REND else Defense.Outcome.PARRY
		var right: Array = prompt.windows[Defense.best_outcome(kind)]
		@warning_ignore("integer_division")
		plan = {"action": wrong, "at_us": int(prompt.at_ms) * 1000 + (int(right[0]) + int(right[1])) / 2}
		_plans[plan_key] = plan
		return plan
	if _rng.randi_range(1, 100) <= bot_skill:
		var at := int(prompt.at_ms) * 1000
		var windows: Dictionary = prompt.windows
		var action := Defense.best_outcome(kind)
		if skill:
			var perfect: Array = windows.get(Defense.Outcome.PRESS_PERFECT, windows[Defense.Outcome.PRESS])
			var good: Array = windows[Defense.Outcome.PRESS]
			var edges := perfect
			if _rng.randi_range(0, 1) == 1:
				# A good press: early, between the good and the perfect edges.
				edges = [int(good[0]), int(perfect[0])]
			@warning_ignore("integer_division")
			plan = {"action": action, "at_us": at + (int(edges[0]) + int(edges[1])) / 2}
		else:
			if windows.has(Defense.Outcome.DODGE) and windows.has(Defense.Outcome.PARRY) and _rng.randi_range(0, 1) == 1:
				action = Defense.Outcome.DODGE
			var edges: Array = windows[action]
			@warning_ignore("integer_division")
			plan = {"action": action, "at_us": at + (int(edges[0]) + int(edges[1])) / 2}
	_plans[plan_key] = plan
	return plan


## The first prompt of a hit that player `player` can still answer, or {}.
func _open_prompt(sequence: Dictionary, hit_index: int, skill: bool, player: int) -> Dictionary:
	var prompts: Array = sequence.prompts
	var states: Array = sequence.states
	for i: int in prompts.size():
		var prompt: Dictionary = prompts[i]
		if int(prompt.hit) != hit_index or int(_owners.get(int(prompt.character), 0)) != player:
			continue
		if skill:
			if _skill_runner.is_prompt_open(i):
				return prompt
		elif int(states[i]) == CombatEngine.PromptState.PENDING and _mirror.is_alive(int(prompt.character)):
			return prompt
	return {}
