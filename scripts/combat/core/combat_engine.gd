class_name CombatEngine
extends RefCounted
## Deterministic combat state machine. The only way to change a fight is submit(command), which
## returns the events that happened. Same setup + same seed + same commands = same events.
##
## Rules for this file and everything in scripts/combat/core/:
## no Nodes, no Input, no Time, no randi()/randf(), no floats in rules. Randomness comes from
## `rng` only. Events and commands hold only ints, bools, Strings and arrays/dictionaries of
## those, built fresh (never shared with internal state).
##
## Timed sequences: anything resolved in real time is a "timed sequence" made of prompts. A prompt
## is one (moment, character) pair with the actions it accepts and their windows. Kinds:
##   "enemy_attack"  one "defend" prompt per hit per target;
##   "skill"         one "press" prompt per hit per striker (the user, or every standing party
##                   member for the team ultimate), then one "follow_up" prompt per other standing
##                   ally. A follow-up "requires" the press prompts: it is voided unless at least
##                   one of them was good. Everything is declared up front, so no network round
##                   trip is needed mid-sequence.
## Prompts name characters, never players; deciding which player answers which prompt is the
## controller's job.
##
## Commands (build them with CombatCommands):
##   use_ability      {turn, actor, ability, targets}            phase AWAITING_ACTION
##   resolve_prompts  {seq, results:[{prompt, outcome, offset_us}]}  phase AWAITING_TIMING
##                    partial is fine; per character, prompts must resolve in order
##   practice         {invulnerable_party?, immortal_enemies?, force_attack?}  if setup allows
##
## Events (Dictionary with "type"):
##   combat_started          {seed, fighters:[Combatant.to_dict()], practice_allowed, opening}
##                           opening: "normal" | "first_strike" (DESIGN.md 2.12)
##   intent                  {enemy, attack, name, mode, targets:[id], kinds:[hit kind], times:[ms]}
##                           what this enemy will do on its next turn (DESIGN.md 2.8). Sent at
##                           fight start, after its turn, and whenever its targets change.
##                           times: each hit's impact, ms after the attack starts (with
##                           attack_tempo_percent, like the declared hits' at_ms).
##   turn_started            {turn, actor, team, time}
##   turn_order              {order:[id]}      current actor first, then upcoming turns
##   ability_used            {turn, actor, ability, targets:[id]}
##   damage                  {source, target, amount, hp, max_hp, cause}
##                           cause: "ability" | "follow_up" | "counter" | "team_counter"
##   healed                  {source, target, amount, hp, max_hp}
##   revived                 {source, target, hp, max_hp}
##   downed                  {target}
##   ap_changed              {character, delta, ap, reason}  reason: "spend" | "ability" | "given"
##   status_changed          {target, status, active, turns, source}   see Status
##   turn_shifted            {target, delta}   a fighter's next turn moved (delta in timeline
##                           ticks: negative = sooner); a turn_order event follows
##   team_gauge              {value, delta, max}
##   timed_sequence_declared {seq, kind, source, action, name, mode, targets:[id],
##                            alert_cue, allow_timing_ring, hits:[hit], prompts:[prompt]}
##       hit    = {index, at_ms, kind, approach_ms, feint, damage_percent, impact_sfx}
##       prompt = {idx, hit, character, at_ms, kind, windows:{Outcome:[early_us, late_us]},
##                 perfect:[Outcome], damage, press_damage, perfect_damage, role, requires:[idx]}
##       role: "defend" | "press" | "follow_up". damage is pre-rolled: for "defend" what the hit
##       deals if not avoided; for "press" and "follow_up" what it deals to each target on a miss
##       (damage), a good press (press_damage, outcome PRESS) and a perfect press (perfect_damage,
##       outcome PRESS_PERFECT). Enemy at_ms includes attack_tempo_percent.
##       mode: EnemyAttackData.TargetMode for enemy attacks, AbilityData.Target for skills.
##   prompt_resolved         {seq, prompt, hit, character, outcome, perfect, offset_us,
##                            damage, hp, max_hp, ap, ap_delta, downed}
##                           defend: damage is what the hit dealt (0 if avoided); hp/ap are the
##                           character's, after. press/follow_up: damage is what each target
##                           takes (damage events follow).
##   prompts_voided          {seq, prompts:[idx], reason}
##                           reason: "downed" | "attacker_down" | "targets_down" | "no_good_press"
##   sequence_resolved       {seq, reason}   boundary: every prompt is done. Counters follow.
##                           reason: "completed" | "targets_down" | "attacker_down"
##   counter                 {seq, actors:[id], target, team}  followed by a damage event
##   turn_ended              {turn, actor}
##   practice_changed        {invulnerable_party, immortal_enemies, force_attack}
##                           also emitted (before timed_sequence_declared) when a forced
##                           attack is used and force_attack clears
##   combat_ended            {result}        "victory" | "defeat"
##   command_rejected        {reason, command}   private to the sender; never broadcast/replayed

## combat_started "opening" names, by CombatSetup.Opening.
const OPENING_NAMES: Array[String] = ["normal", "first_strike"]

enum Phase {
	NOT_STARTED,
	## A party member (active_actor) must choose an action.
	AWAITING_ACTION,
	## The current timed sequence (`sequence`) has prompts waiting for results.
	AWAITING_TIMING,
	ENDED,
}

enum PromptState {
	PENDING,
	RESOLVED,
	## Cancelled (its character went down, its target is gone, or its requirement failed).
	## Counts as not perfect.
	VOID,
}

const SEQUENCE_ENEMY_ATTACK := "enemy_attack"
const SEQUENCE_SKILL := "skill"
const ROLE_DEFEND := "defend"
const ROLE_PRESS := "press"
const ROLE_FOLLOW_UP := "follow_up"
const MAX_AUTO_TURNS: int = 1000

var phase: Phase = Phase.NOT_STARTED
var tuning: Tuning
var rng: CombatRng
var combatants: Array[Combatant] = []
## Id of the combatant whose turn it is, or -1.
var active_actor: int = -1
## Timeline position of the current turn (used for revives and speed changes).
var time_now: int = 0
## Increases by one every turn; use_ability must quote it.
var turn_number: int = 0
## Last timed sequence number handed out.
var sequence_counter: int = 0
## The timed sequence being resolved (empty when none). Keys: seq, kind, source, action, mode,
## targets, hits, prompts, states (Array of PromptState), outcomes (Array of Defense.Outcome),
## and for skills: landed (bool), exposed_target (id or -1).
var sequence: Dictionary = {}
## Shared team gauge (0 .. tuning team_gauge_max).
var team_gauge: int = 0
## Enemy id -> {attack: String, targets: Array[int]}: what it does on its next turn.
var intents: Dictionary = {}
## "victory" or "defeat" once the fight is over.
var result: String = ""
## Practice options (only changeable when the setup allows practice).
var practice: Dictionary = {"invulnerable_party": false, "immortal_enemies": false, "force_attack": ""}

var _setup: CombatSetup
var _abilities: Dictionary = {}
var _attacks: Dictionary = {}


func _init(setup: CombatSetup) -> void:
	_setup = setup
	tuning = setup.tuning
	rng = CombatRng.new(setup.rng_seed)


## Builds the fighters and runs until the first decision is needed.
func start() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if phase != Phase.NOT_STARTED:
		events.append(_reject("already_started", {}))
		return events
	var problems := _setup.validate()
	if not problems.is_empty():
		events.append(_reject("invalid_setup: " + ", ".join(problems), {}))
		return events
	_build_lookups()
	_build_combatants()
	var fighters: Array[Dictionary] = []
	for c: Combatant in combatants:
		fighters.append(c.to_dict())
	events.append({
		"type": "combat_started",
		"seed": _setup.rng_seed,
		"fighters": fighters,
		"practice_allowed": _setup.allow_practice,
		"opening": OPENING_NAMES[_setup.opening],
	})
	for enemy_id: int in enemy_ids():
		_pick_intent(get_combatant(enemy_id), events)
	_advance_turn(events)
	return events


## Applies one command. Invalid commands change nothing and return one command_rejected event.
func submit(command: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	match String(command.get("type", "")):
		CombatCommands.USE_ABILITY:
			_cmd_use_ability(command, events)
		CombatCommands.RESOLVE_PROMPTS:
			_cmd_resolve_prompts(command, events)
		CombatCommands.PRACTICE:
			_cmd_practice(command, events)
		_:
			events.append(_reject("unknown_command", command))
	return events


## Rebuilds an engine from snapshot() output (reconnects, late join, desync debugging).
static func restore(setup: CombatSetup, snap: Dictionary) -> CombatEngine:
	var engine := CombatEngine.new(setup)
	engine._build_lookups()
	for d: Dictionary in snap.combatants:
		engine.combatants.append(Combatant.from_dict(d))
	engine.phase = int(snap.phase) as Phase
	engine.active_actor = int(snap.active_actor)
	engine.time_now = int(snap.time_now)
	engine.turn_number = int(snap.turn_number)
	engine.sequence_counter = int(snap.sequence_counter)
	engine.sequence = (snap.sequence as Dictionary).duplicate(true)
	engine.team_gauge = int(snap.team_gauge)
	engine.intents = (snap.intents as Dictionary).duplicate(true)
	engine.result = String(snap.result)
	engine.practice = (snap.practice as Dictionary).duplicate(true)
	engine.rng.state = int(snap.rng_state)
	return engine


# --- queries ----------------------------------------------------------------------------------

func get_combatant(id: int) -> Combatant:
	if id < 0 or id >= combatants.size():
		return null
	return combatants[id]


func party_ids() -> Array[int]:
	return _ids_of_team(Combatant.Team.PARTY, false)


func enemy_ids() -> Array[int]:
	return _ids_of_team(Combatant.Team.ENEMY, false)


func living_party_ids() -> Array[int]:
	return _ids_of_team(Combatant.Team.PARTY, true)


func living_enemy_ids() -> Array[int]:
	return _ids_of_team(Combatant.Team.ENEMY, true)


func downed_party_ids() -> Array[int]:
	var ids: Array[int] = []
	for id: int in party_ids():
		if not get_combatant(id).is_alive():
			ids.append(id)
	return ids


func get_ability(ability_id: String) -> AbilityData:
	return _abilities.get(ability_id) as AbilityData


func get_attack(attack_id: String) -> EnemyAttackData:
	return _attacks.get(attack_id) as EnemyAttackData


## True if the actor has enough AP for this ability (ignores whose turn it is).
func can_afford(actor_id: int, ability_id: String) -> bool:
	var actor := get_combatant(actor_id)
	var ability := get_ability(ability_id)
	return actor != null and ability != null and actor.ap >= ability.ap_cost


## True if the actor could use this ability now: affordable, gauge full for the team ultimate,
## and at least one valid target.
func can_use(actor_id: int, ability_id: String) -> bool:
	var ability := get_ability(ability_id)
	if ability == null or not can_afford(actor_id, ability_id):
		return false
	if ability.team_ultimate and team_gauge < tuning.team_gauge_max:
		return false
	return not valid_targets(actor_id, ability_id).is_empty()


## Ids this actor may pick as the target of this ability. For abilities without a target step
## (all enemies, self) the list holds what they would affect.
func valid_targets(actor_id: int, ability_id: String) -> Array[int]:
	var ability := get_ability(ability_id)
	var list: Array[int] = []
	if ability == null:
		return list
	match ability.target:
		AbilityData.Target.SINGLE_ENEMY, AbilityData.Target.ALL_ENEMIES:
			list = living_enemy_ids()
		AbilityData.Target.SELF:
			list.append(actor_id)
		AbilityData.Target.ALLY:
			list = living_party_ids()
		AbilityData.Target.OTHER_ALLY:
			for id: int in living_party_ids():
				if id != actor_id:
					list.append(id)
		AbilityData.Target.DOWNED_ALLY:
			list = downed_party_ids()
	return list


## Indices of prompts still waiting for a result.
func pending_prompts() -> Array[int]:
	var list: Array[int] = []
	if sequence.is_empty():
		return list
	var states: Array = sequence.states
	for i: int in states.size():
		if int(states[i]) == PromptState.PENDING:
			list.append(i)
	return list


## Current actor first, then the next turns.
func preview_turn_order(count: int) -> Array[int]:
	var order: Array[int] = []
	var current := get_combatant(active_actor)
	if current != null and current.is_alive():
		order.append(active_actor)
	order.append_array(Timeline.preview(combatants, maxi(0, count - order.size()), tuning.timeline_base))
	return order


## Full state as plain data (deep copy), for determinism checks, restore and network sync.
func snapshot() -> Dictionary:
	var fighters: Array[Dictionary] = []
	for c: Combatant in combatants:
		fighters.append(c.to_dict())
	return {
		"phase": phase,
		"combatants": fighters,
		"active_actor": active_actor,
		"time_now": time_now,
		"turn_number": turn_number,
		"sequence_counter": sequence_counter,
		"sequence": sequence.duplicate(true),
		"team_gauge": team_gauge,
		"intents": intents.duplicate(true),
		"result": result,
		"practice": practice.duplicate(true),
		"rng_state": rng.state,
	}


# --- building ---------------------------------------------------------------------------------

func _build_lookups() -> void:
	_abilities.clear()
	_attacks.clear()
	for data: CharacterData in _setup.party:
		for ability: AbilityData in data.all_abilities():
			_abilities[ability.id] = ability
	if _setup.team_ultimate != null:
		_abilities[_setup.team_ultimate.id] = _setup.team_ultimate
	for data: EnemyData in _setup.enemies:
		for attack: EnemyAttackData in data.attacks:
			_attacks[attack.id] = attack


func _build_combatants() -> void:
	combatants.clear()
	var slot := 0
	for data: CharacterData in _setup.party:
		var c := Combatant.new()
		c.id = combatants.size()
		c.team = Combatant.Team.PARTY
		c.slot = slot
		c.data_id = data.id
		c.display_name = data.display_name
		c.max_hp = _setup.party_max_hp(slot, data)
		c.hp = _setup.party_hp_at_start(slot, c.max_hp)
		c.ap = clampi(tuning.start_ap, 0, tuning.max_ap)
		c.power = CombatMath.percent_min1(tuning.base_party_damage, data.power_percent)
		c.speed = maxi(1, data.speed)
		c.base_speed = c.speed
		for ability: AbilityData in data.all_abilities():
			c.ability_ids.append(ability.id)
		if _setup.team_ultimate != null:
			c.ability_ids.append(_setup.team_ultimate.id)
		c.next_turn_at = Timeline.turn_cost(c.speed, tuning.timeline_base)
		combatants.append(c)
		slot += 1
	slot = 0
	# Two enemies with the same name get letters (Gnat Swarm A, Gnat Swarm B) so targets read.
	var name_count: Dictionary = {}
	for data: EnemyData in _setup.enemies:
		name_count[data.display_name] = int(name_count.get(data.display_name, 0)) + 1
	var name_seen: Dictionary = {}
	for data: EnemyData in _setup.enemies:
		var c := Combatant.new()
		c.id = combatants.size()
		c.team = Combatant.Team.ENEMY
		c.slot = slot
		c.data_id = data.id
		c.display_name = data.display_name
		if int(name_count[data.display_name]) > 1:
			var letter := int(name_seen.get(data.display_name, 0))
			name_seen[data.display_name] = letter + 1
			c.display_name += " " + String.chr(65 + letter)
		c.max_hp = CombatMath.percent_min1(tuning.base_enemy_hp, data.hp_percent)
		c.hp = c.max_hp
		c.power = CombatMath.percent_min1(tuning.base_enemy_hit_damage, data.power_percent)
		c.speed = maxi(1, data.speed)
		c.base_speed = c.speed
		for attack: EnemyAttackData in data.attacks:
			c.attack_ids.append(attack.id)
		c.next_turn_at = Timeline.turn_cost(c.speed, tuning.timeline_base)
		combatants.append(c)
		slot += 1
	if _setup.opening == CombatSetup.Opening.FIRST_STRIKE:
		_apply_first_strike()


## First strike (DESIGN.md 2.12): no enemy's first turn comes before the last party member's
## first turn. On a tie the party member goes first (lower id), so the whole party acts before any
## enemy; everyone keeps their speed from then on.
func _apply_first_strike() -> void:
	var last_party := 0
	for c: Combatant in combatants:
		if c.is_party():
			last_party = maxi(last_party, c.next_turn_at)
	for c: Combatant in combatants:
		if not c.is_party():
			c.next_turn_at = maxi(c.next_turn_at, last_party)


# --- turn flow --------------------------------------------------------------------------------

## Moves the timeline forward until a decision is needed or the fight ends.
func _advance_turn(events: Array[Dictionary]) -> void:
	for _guard: int in MAX_AUTO_TURNS:
		if _check_end(events):
			return
		var actor := Timeline.next_actor(combatants)
		time_now = actor.next_turn_at
		actor.next_turn_at += Timeline.turn_cost(actor.speed, tuning.timeline_base)
		turn_number += 1
		active_actor = actor.id
		events.append({"type": "turn_started", "turn": turn_number, "actor": actor.id, "team": actor.team, "time": time_now})
		_start_of_turn(actor, events)
		events.append({"type": "turn_order", "order": preview_turn_order(tuning.turn_order_preview)})
		if actor.is_party():
			phase = Phase.AWAITING_ACTION
			return
		if _begin_enemy_attack(actor, events):
			return
		# The enemy had nothing it could do; its turn passes.
		_end_of_turn(actor, events)
		events.append({"type": "turn_ended", "turn": turn_number, "actor": actor.id})
	push_warning("CombatEngine: turn guard reached; nobody can act")


## Statuses that last until the holder's next turn end now.
func _start_of_turn(actor: Combatant, events: Array[Dictionary]) -> void:
	for id: String in Status.ALL:
		if Status.ends_at_own_turn(id) and actor.has_status(id):
			_remove_status(actor, id, events)


## Turn-counted statuses tick down; the defence count for Payback starts again (after the turn's
## action used it); an enemy picks what it does next.
func _end_of_turn(actor: Combatant, events: Array[Dictionary]) -> void:
	actor.perfect_defenses = 0
	for id: String in Status.ALL:
		if not Status.counts_turns(id) or not actor.has_status(id):
			continue
		var entry: Dictionary = actor.statuses[id]
		var left := int(entry.turns) - 1
		if left <= 0:
			_remove_status(actor, id, events)
		else:
			entry.turns = left
			events.append(_status_event(actor, id, true))
	if not actor.is_party() and actor.is_alive():
		_pick_intent(actor, events)


## Declares the enemy's intended attack as a timed sequence. Returns false if it has none.
func _begin_enemy_attack(actor: Combatant, events: Array[Dictionary]) -> bool:
	var intent: Dictionary = intents.get(actor.id, {})
	var forced := String(practice.force_attack)
	if not forced.is_empty() and actor.attack_ids.has(forced):
		practice.force_attack = ""
		# Announce the clear, or mirrors (HUD practice status) would keep showing the forced attack.
		events.append(_practice_changed_event())
		if String(intent.get("attack", "")) != forced:
			intent = {"attack": forced, "targets": _pick_targets(actor, get_attack(forced))}
	if intent.is_empty():
		intent = _choose_intent(actor)
	var attack := get_attack(String(intent.get("attack", "")))
	intents.erase(actor.id)
	if attack == null:
		return false
	var targets: Array[int] = []
	targets.assign(intent.targets)
	if not _targets_still_valid(actor, attack, targets):
		targets = _pick_targets(actor, attack)
	if targets.is_empty():
		return false
	if attack.target_mode == EnemyAttackData.TargetMode.SINGLE and actor.has_status(Status.TAUNTED):
		_remove_status(actor, Status.TAUNTED, events)

	var hits: Array[Dictionary] = []
	var prompts: Array[Dictionary] = []
	for hit_index: int in attack.hits.size():
		var hit: AttackHitData = attack.hits[hit_index]
		var at_ms := CombatMath.percent(hit.impact_ms, tuning.attack_tempo_percent)
		hits.append({
			"index": hit_index,
			"at_ms": at_ms,
			"kind": hit.kind,
			"approach_ms": CombatMath.percent(hit.approach_ms, tuning.attack_tempo_percent),
			"feint": hit.feint,
			"damage_percent": hit.damage_percent,
			"impact_sfx": hit.impact_sfx,
		})
		for target_id: int in targets:
			prompts.append(_prompt(prompts.size(), hit_index, target_id, at_ms, hit.kind,
					Defense.build_windows(hit.kind, tuning), _enemy_hit_damage(actor, get_combatant(target_id), hit.damage_percent),
					0, 0, ROLE_DEFEND, []))
	_declare(SEQUENCE_ENEMY_ATTACK, actor.id, attack.id, attack.display_name, attack.target_mode, targets,
			attack.alert_cue, attack.allow_timing_ring, hits, prompts, events)
	return true


## Emits combat_ended and returns true if one side is wiped out.
func _check_end(events: Array[Dictionary]) -> bool:
	if phase == Phase.ENDED:
		return true
	var outcome := ""
	if living_enemy_ids().is_empty():
		outcome = "victory"
	elif living_party_ids().is_empty():
		outcome = "defeat"
	if outcome.is_empty():
		return false
	result = outcome
	phase = Phase.ENDED
	active_actor = -1
	sequence = {}
	events.append({"type": "combat_ended", "result": outcome})
	return true


# --- enemy intent -----------------------------------------------------------------------------

## Picks the enemy's next attack and targets (weighted, seeded) and announces it.
func _pick_intent(enemy: Combatant, events: Array[Dictionary]) -> void:
	var intent := _choose_intent(enemy)
	if intent.is_empty():
		intents.erase(enemy.id)
		return
	intents[enemy.id] = intent
	events.append(_intent_event(enemy.id))


func _choose_intent(enemy: Combatant) -> Dictionary:
	var choices: Array[EnemyAttackData] = []
	var weights: Array[int] = []
	for attack_id: String in enemy.attack_ids:
		var candidate := get_attack(attack_id)
		if candidate != null and not candidate.hits.is_empty() and candidate.weight > 0:
			choices.append(candidate)
			weights.append(candidate.weight)
	var pick := rng.pick_weighted(weights)
	if pick < 0:
		return {}
	return {"attack": choices[pick].id, "targets": _pick_targets(enemy, choices[pick])}


## Whole party for party-wide attacks; otherwise the taunter if one is standing, else a random
## standing party member.
func _pick_targets(enemy: Combatant, attack: EnemyAttackData) -> Array[int]:
	var living := living_party_ids()
	var targets: Array[int] = []
	if living.is_empty() or attack == null:
		return targets
	if attack.target_mode == EnemyAttackData.TargetMode.PARTY:
		return living
	var taunter := _taunter_of(enemy)
	if taunter >= 0:
		targets.append(taunter)
	else:
		targets.append(living[rng.range_int(0, living.size() - 1)])
	return targets


func _taunter_of(enemy: Combatant) -> int:
	if not enemy.has_status(Status.TAUNTED):
		return -1
	var source := get_combatant(int((enemy.statuses[Status.TAUNTED] as Dictionary).source))
	return source.id if source != null and source.is_alive() else -1


func _targets_still_valid(enemy: Combatant, attack: EnemyAttackData, targets: Array[int]) -> bool:
	if attack.target_mode == EnemyAttackData.TargetMode.PARTY:
		return targets == living_party_ids()
	if targets.size() != 1 or not get_combatant(targets[0]).is_alive():
		return false
	var taunter := _taunter_of(enemy)
	return taunter < 0 or targets[0] == taunter


## Re-targets every intent that no longer fits (a target went down or came back, a taunt).
func _refresh_intents(events: Array[Dictionary]) -> void:
	for enemy_id: int in living_enemy_ids():
		if not intents.has(enemy_id):
			continue
		var enemy := get_combatant(enemy_id)
		var intent: Dictionary = intents[enemy_id]
		var attack := get_attack(String(intent.attack))
		var targets: Array[int] = []
		targets.assign(intent.targets)
		if attack == null or _targets_still_valid(enemy, attack, targets):
			continue
		intent.targets = _pick_targets(enemy, attack)
		events.append(_intent_event(enemy_id))


func _intent_event(enemy_id: int) -> Dictionary:
	var intent: Dictionary = intents[enemy_id]
	var attack := get_attack(String(intent.attack))
	var kinds: Array[int] = []
	var times: Array[int] = []
	for hit: AttackHitData in attack.hits:
		kinds.append(hit.kind)
		times.append(CombatMath.percent(hit.impact_ms, tuning.attack_tempo_percent))
	var targets: Array[int] = []
	targets.assign(intent.targets)
	return {
		"type": "intent",
		"enemy": enemy_id,
		"attack": attack.id,
		"name": attack.display_name,
		"mode": attack.target_mode,
		"targets": targets,
		"kinds": kinds,
		"times": times,
	}


# --- commands ---------------------------------------------------------------------------------

func _cmd_use_ability(command: Dictionary, events: Array[Dictionary]) -> void:
	if phase != Phase.AWAITING_ACTION:
		events.append(_reject("not_awaiting_action", command))
		return
	if int(command.get("turn", -1)) != turn_number:
		events.append(_reject("wrong_turn", command))
		return
	var actor_id := int(command.get("actor", -1))
	if actor_id != active_actor:
		events.append(_reject("not_this_actors_turn", command))
		return
	var actor := get_combatant(actor_id)
	var ability_id := String(command.get("ability", ""))
	if not actor.ability_ids.has(ability_id):
		events.append(_reject("unknown_ability", command))
		return
	var ability := get_ability(ability_id)
	if ability.team_ultimate and team_gauge < tuning.team_gauge_max:
		events.append(_reject("gauge_not_full", command))
		return
	if actor.ap < ability.ap_cost:
		events.append(_reject("not_enough_ap", command))
		return
	var targets: Array[int] = []
	var allowed := valid_targets(actor.id, ability.id)
	match ability.target:
		AbilityData.Target.ALL_ENEMIES, AbilityData.Target.SELF:
			targets = allowed
		_:
			var requested: Variant = command.get("targets", [])
			if typeof(requested) != TYPE_ARRAY or (requested as Array).size() != 1:
				events.append(_reject("needs_one_target", command))
				return
			var target_id := int((requested as Array)[0])
			if not allowed.has(target_id):
				events.append(_reject("invalid_target", command))
				return
			targets.append(target_id)

	if ability.ap_cost > 0:
		_change_ap(actor, -ability.ap_cost, "spend", events)
	if ability.team_ultimate:
		_change_gauge(-team_gauge, events)
	events.append({"type": "ability_used", "turn": turn_number, "actor": actor.id, "ability": ability.id, "targets": targets.duplicate()})
	if not ability.press_times_ms.is_empty():
		_begin_skill(actor, ability, targets, events)
		return
	# No timed press: one hit with the base effect, at once.
	var exposed := _exposed_target(ability, targets)
	if _deals_damage(ability):
		for target_id: int in targets:
			var target := get_combatant(target_id)
			if target.is_alive():
				var pct := _skill_percent(actor, ability, false)
				_deal_damage(actor, target, _skill_damage(actor.power, pct, _exposed_bonus(ability, target_id == exposed)), "ability", events)
	_apply_effects(actor, ability, targets, false, exposed, events)
	_end_of_turn(actor, events)
	events.append({"type": "turn_ended", "turn": turn_number, "actor": actor.id})
	_advance_turn(events)


func _cmd_resolve_prompts(command: Dictionary, events: Array[Dictionary]) -> void:
	if phase != Phase.AWAITING_TIMING:
		events.append(_reject("not_awaiting_timing", command))
		return
	if int(command.get("seq", -1)) != int(sequence.seq):
		events.append(_reject("stale_sequence", command))
		return
	var raw: Variant = command.get("results", [])
	if typeof(raw) != TYPE_ARRAY or (raw as Array).is_empty():
		events.append(_reject("no_results", command))
		return
	var prompts: Array = sequence.prompts
	var states: Array = sequence.states

	# Validate everything before changing anything.
	var items: Array[Dictionary] = []
	var included: Dictionary = {}
	for entry: Variant in raw:
		if typeof(entry) != TYPE_DICTIONARY:
			events.append(_reject("bad_result", command))
			return
		var idx := int((entry as Dictionary).get("prompt", -1))
		if idx < 0 or idx >= prompts.size():
			events.append(_reject("unknown_prompt", command))
			return
		if included.has(idx):
			events.append(_reject("duplicate_prompt", command))
			return
		if int(states[idx]) != PromptState.PENDING:
			events.append(_reject("stale_prompt", command))
			return
		included[idx] = true
		items.append({
			"idx": idx,
			"outcome": int((entry as Dictionary).get("outcome", Defense.Outcome.NONE)),
			"offset_us": int((entry as Dictionary).get("offset_us", 0)),
		})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.idx) < int(b.idx))
	for item: Dictionary in items:
		var character := int((prompts[item.idx] as Dictionary).character)
		for j: int in int(item.idx):
			if int((prompts[j] as Dictionary).character) == character \
					and int(states[j]) == PromptState.PENDING and not included.has(j):
				events.append(_reject("out_of_order", command))
				return

	for item: Dictionary in items:
		if int(states[item.idx]) != PromptState.PENDING:
			continue # voided earlier in this batch
		_apply_prompt(item, events)
		_void_dead_prompts(events)
		_maybe_land_skill(events)
	_finish_sequence_if_done(events)


func _cmd_practice(command: Dictionary, events: Array[Dictionary]) -> void:
	if not _setup.allow_practice:
		events.append(_reject("practice_disabled", command))
		return
	if phase == Phase.NOT_STARTED or phase == Phase.ENDED:
		events.append(_reject("not_in_combat", command))
		return
	if command.has("force_attack"):
		var attack_id := String(command.force_attack)
		if not attack_id.is_empty() and not _attacks.has(attack_id):
			events.append(_reject("unknown_attack", command))
			return
	if command.has("invulnerable_party"):
		practice.invulnerable_party = bool(command.invulnerable_party)
	if command.has("immortal_enemies"):
		practice.immortal_enemies = bool(command.immortal_enemies)
	if command.has("force_attack"):
		practice.force_attack = String(command.force_attack)
	events.append(_practice_changed_event())
	if command.has("force_attack"):
		_show_forced_intent(events)


## The next enemy (in turn order) that has the forced attack shows it as its intent right away.
func _show_forced_intent(events: Array[Dictionary]) -> void:
	var forced := String(practice.force_attack)
	if forced.is_empty():
		return
	var order := Timeline.preview(combatants, combatants.size() * 2, tuning.timeline_base)
	for id: int in order:
		var c := get_combatant(id)
		if c.is_party() or not c.attack_ids.has(forced):
			continue
		var current: Dictionary = intents.get(id, {})
		if String(current.get("attack", "")) != forced:
			intents[id] = {"attack": forced, "targets": _pick_targets(c, get_attack(forced))}
			events.append(_intent_event(id))
		return


func _practice_changed_event() -> Dictionary:
	return {
		"type": "practice_changed",
		"invulnerable_party": practice.invulnerable_party,
		"immortal_enemies": practice.immortal_enemies,
		"force_attack": practice.force_attack,
	}


# --- skills -----------------------------------------------------------------------------------

## Declares a skill as a timed sequence: press prompts for the striker(s), then follow-ups.
func _begin_skill(actor: Combatant, ability: AbilityData, targets: Array[int], events: Array[Dictionary]) -> void:
	var strikers: Array[int] = []
	if ability.team_ultimate:
		strikers = living_party_ids()
	else:
		strikers.append(actor.id)
	var exposed := _exposed_target(ability, targets)
	var damaging := _deals_damage(ability) and ability.targets_enemies()
	var hits: Array[Dictionary] = []
	var prompts: Array[Dictionary] = []
	var press_idxs: Array[int] = []
	for hit_index: int in ability.press_times_ms.size():
		var at_ms := ability.press_times_ms[hit_index]
		hits.append(_skill_hit(hit_index, at_ms, ability.damage_percent, ability.impact_sfx))
		for striker_id: int in strikers:
			var striker := get_combatant(striker_id)
			var miss := 0
			var good := 0
			var perfect := 0
			if damaging:
				var bonus := _exposed_bonus(ability, exposed >= 0)
				good = _skill_damage(striker.power, _skill_percent(striker, ability, false), bonus)
				perfect = _skill_damage(striker.power, _skill_percent(striker, ability, true), bonus)
				miss = CombatMath.percent(good, tuning.skill_miss_damage_percent)
			press_idxs.append(prompts.size())
			prompts.append(_prompt(prompts.size(), hit_index, striker_id, at_ms, AttackHitData.Kind.PRESS,
					Defense.build_windows(AttackHitData.Kind.PRESS, tuning), miss, good, perfect, ROLE_PRESS, []))
	if ability.follow_ups and damaging and not ability.team_ultimate:
		var last_ms := ability.press_times_ms[ability.press_times_ms.size() - 1]
		var order := 0
		for ally_id: int in living_party_ids():
			if ally_id == actor.id:
				continue
			var at_ms := last_ms + tuning.follow_up_delay_ms + order * tuning.follow_up_gap_ms
			var hit_index := hits.size()
			var ally := get_combatant(ally_id)
			hits.append(_skill_hit(hit_index, at_ms, tuning.follow_up_percent, "strike"))
			prompts.append(_prompt(prompts.size(), hit_index, ally_id, at_ms, AttackHitData.Kind.PRESS,
					Defense.build_follow_up_windows(tuning), 0, _roll_damage(ally.power, tuning.follow_up_percent),
					_roll_damage(ally.power, tuning.follow_up_perfect_percent), ROLE_FOLLOW_UP, press_idxs))
			order += 1
	_declare(SEQUENCE_SKILL, actor.id, ability.id, ability.display_name, ability.target, targets,
			false, true, hits, prompts, events)
	sequence["landed"] = false
	sequence["exposed_target"] = exposed


func _skill_hit(index: int, at_ms: int, damage_percent: int, sfx: String) -> Dictionary:
	return {
		"index": index,
		"at_ms": at_ms,
		"kind": AttackHitData.Kind.PRESS,
		"approach_ms": 0,
		"feint": false,
		"damage_percent": damage_percent,
		"impact_sfx": sfx,
	}


## Once every press prompt of the skill is resolved or void, its effects apply (once).
func _maybe_land_skill(events: Array[Dictionary]) -> void:
	if sequence.is_empty() or String(sequence.kind) != SEQUENCE_SKILL or bool(sequence.landed):
		return
	var all_perfect := true
	var any_press := false
	var prompts: Array = sequence.prompts
	for i: int in prompts.size():
		if String((prompts[i] as Dictionary).role) != ROLE_PRESS:
			continue
		match int(sequence.states[i]):
			PromptState.PENDING:
				return
			PromptState.RESOLVED:
				var outcome := int(sequence.outcomes[i])
				any_press = any_press or Defense.is_press(outcome)
				all_perfect = all_perfect and outcome == Defense.Outcome.PRESS_PERFECT
	sequence.landed = true
	var actor := get_combatant(int(sequence.source))
	var ability := get_ability(String(sequence.action))
	var targets: Array[int] = []
	targets.assign(sequence.targets)
	_apply_effects(actor, ability, targets, all_perfect and any_press, int(sequence.exposed_target), events)


## Everything a skill does besides its hits. `good`: every press was perfect (the press_* bonus
## of the effects). `exposed`: the target
## whose Exposed this skill consumes (-1 if none).
func _apply_effects(actor: Combatant, ability: AbilityData, targets: Array[int], good: bool, exposed: int,
		events: Array[Dictionary]) -> void:
	var timeline_changed := false
	if exposed >= 0 and get_combatant(exposed).has_status(Status.EXPOSED):
		_remove_status(get_combatant(exposed), Status.EXPOSED, events)
	var first := get_combatant(targets[0]) if not targets.is_empty() else null
	var gain := ability.ap_gain + (ability.press_ap_gain if good else 0)
	if gain > 0:
		_change_ap(actor, gain, "ability", events)
	var give := ability.give_ap + (ability.press_give_ap if good else 0)
	if give > 0 and first != null and first.is_party() and first.is_alive():
		_change_ap(first, give, "given", events)
	var heal := ability.heal_percent + (ability.press_heal_percent if good else 0)
	if heal > 0 and first != null and first.is_party() and first.is_alive():
		_heal(actor, first, CombatMath.percent_min1(first.max_hp, heal), events)
	var revive := ability.revive_percent + (ability.press_revive_percent if good else 0)
	if revive > 0 and first != null and first.is_party() and not first.is_alive():
		_revive(actor, first, revive, events)
		timeline_changed = true
	var delay := ability.turn_delay_percent + (ability.press_turn_delay_percent if good else 0)
	if delay > 0 and first != null and first.is_alive():
		_shift_turn(first, CombatMath.percent(Timeline.turn_cost(first.speed, tuning.timeline_base), delay), events)
		timeline_changed = true
	var hasten := ability.turn_hasten_percent + (ability.press_turn_hasten_percent if good else 0)
	if hasten > 0 and first != null and first.is_alive():
		var waiting := maxi(0, first.next_turn_at - time_now)
		_shift_turn(first, -CombatMath.percent(waiting, mini(100, hasten)), events)
		timeline_changed = true
	if Status.is_known(ability.status):
		var turns := ability.status_turns + (ability.press_status_turns if good else 0)
		for target_id: int in targets:
			var target := get_combatant(target_id)
			if target.is_alive():
				timeline_changed = _add_status(target, ability.status, turns, actor.id, events) or timeline_changed
		if good and ability.press_status_on_self and not targets.has(actor.id):
			timeline_changed = _add_status(actor, ability.status, turns, actor.id, events) or timeline_changed
	if ability.team_ultimate:
		for id: int in downed_party_ids():
			_revive(actor, get_combatant(id), tuning.team_ultimate_revive_percent, events)
			timeline_changed = true
	if timeline_changed:
		events.append({"type": "turn_order", "order": preview_turn_order(tuning.turn_order_preview)})


func _deals_damage(ability: AbilityData) -> bool:
	return ability.damage_percent > 0 or ability.press_damage_percent > 0 or ability.per_perfect_defense_percent > 0


## The single enemy target whose Exposed this ability will consume, or -1.
func _exposed_target(ability: AbilityData, targets: Array[int]) -> int:
	if ability.target != AbilityData.Target.SINGLE_ENEMY or not ability.consumes_exposed or not _deals_damage(ability):
		return -1
	if targets.size() != 1 or not get_combatant(targets[0]).has_status(Status.EXPOSED):
		return -1
	return targets[0]


func _exposed_bonus(ability: AbilityData, exposed: bool) -> int:
	if not exposed:
		return 0
	return ability.exposed_bonus_percent if ability.exposed_bonus_percent > 0 else tuning.exposed_bonus_percent


## Move percent of one hit: base, plus Payback's per-defence bonus, plus the press bonus.
func _skill_percent(striker: Combatant, ability: AbilityData, good: bool) -> int:
	var pct := ability.damage_percent + ability.per_perfect_defense_percent * striker.perfect_defenses
	if good:
		pct += ability.press_damage_percent
	return pct


## Power x move percent, then the Exposed multiplier (a status, DESIGN.md 2.7), then variance.
func _skill_damage(power: int, pct: int, exposed_bonus: int) -> int:
	var amount := CombatMath.percent_min1(power, pct)
	if exposed_bonus > 0:
		amount = CombatMath.percent_min1(amount, 100 + exposed_bonus)
	return _apply_variance(amount)


# --- timed sequence resolution ----------------------------------------------------------------

func _declare(kind: String, source: int, action: String, display_name: String, mode: int, targets: Array[int],
		alert_cue: bool, allow_ring: bool, hits: Array[Dictionary], prompts: Array[Dictionary], events: Array[Dictionary]) -> void:
	var states: Array[int] = []
	var outcomes: Array[int] = []
	for i: int in prompts.size():
		states.append(PromptState.PENDING)
		outcomes.append(Defense.Outcome.NONE)
	sequence_counter += 1
	sequence = {
		"seq": sequence_counter,
		"kind": kind,
		"source": source,
		"action": action,
		"mode": mode,
		"targets": targets.duplicate(),
		"hits": hits.duplicate(true),
		"prompts": prompts.duplicate(true),
		"states": states,
		"outcomes": outcomes,
	}
	phase = Phase.AWAITING_TIMING
	events.append({
		"type": "timed_sequence_declared",
		"seq": sequence_counter,
		"kind": kind,
		"source": source,
		"action": action,
		"name": display_name,
		"mode": mode,
		"targets": targets.duplicate(),
		"alert_cue": alert_cue,
		"allow_timing_ring": allow_ring,
		"hits": hits.duplicate(true),
		"prompts": prompts.duplicate(true),
	})


func _prompt(idx: int, hit: int, character: int, at_ms: int, kind: int, windows: Dictionary, damage: int,
		press_damage: int, perfect_damage: int, role: String, requires: Array[int]) -> Dictionary:
	return {
		"idx": idx,
		"hit": hit,
		"character": character,
		"at_ms": at_ms,
		"kind": kind,
		"windows": windows,
		"perfect": Defense.perfect_outcomes(kind),
		"damage": damage,
		"press_damage": press_damage,
		"perfect_damage": perfect_damage,
		"role": role,
		"requires": requires.duplicate(),
	}


func _apply_prompt(item: Dictionary, events: Array[Dictionary]) -> void:
	var prompt: Dictionary = sequence.prompts[int(item.idx)]
	match String(prompt.role):
		ROLE_PRESS, ROLE_FOLLOW_UP:
			_apply_press_prompt(item, events)
		_:
			_apply_defend_prompt(item, events)


func _apply_defend_prompt(item: Dictionary, events: Array[Dictionary]) -> void:
	var idx: int = item.idx
	var prompt: Dictionary = sequence.prompts[idx]
	var target := get_combatant(int(prompt.character))
	var outcome := Defense.sanitize(int(item.outcome), prompt.windows)
	sequence.states[idx] = PromptState.RESOLVED
	sequence.outcomes[idx] = outcome
	var damage := 0
	var ap_delta := 0
	var perfect := (prompt.perfect as Array).has(outcome)
	if outcome != Defense.Outcome.NONE:
		ap_delta = _change_ap_silent(target, Defense.ap_reward(outcome, tuning))
		if perfect:
			target.perfect_defenses += 1
	else:
		damage = int(prompt.damage)
		_lose_hp(target, damage)
	var downed := not target.is_alive()
	events.append({
		"type": "prompt_resolved",
		"seq": sequence.seq,
		"prompt": idx,
		"hit": prompt.hit,
		"character": target.id,
		"outcome": outcome,
		"perfect": perfect,
		"offset_us": int(item.offset_us),
		"damage": damage,
		"hp": target.hp,
		"max_hp": target.max_hp,
		"ap": target.ap,
		"ap_delta": ap_delta,
		"downed": downed,
	})
	if downed:
		events.append({"type": "downed", "target": target.id})
		_on_downed(target, events)


## A skill press or follow-up press: its hit lands on every standing target.
func _apply_press_prompt(item: Dictionary, events: Array[Dictionary]) -> void:
	var idx: int = item.idx
	var prompt: Dictionary = sequence.prompts[idx]
	var striker := get_combatant(int(prompt.character))
	var outcome := Defense.sanitize(int(item.outcome), prompt.windows)
	var follow_up := String(prompt.role) == ROLE_FOLLOW_UP
	if follow_up and not _requirement_met(prompt):
		outcome = Defense.Outcome.NONE
	sequence.states[idx] = PromptState.RESOLVED
	sequence.outcomes[idx] = outcome
	var good := Defense.is_press(outcome)
	var perfect := outcome == Defense.Outcome.PRESS_PERFECT
	var amount := int(prompt.damage)
	if perfect:
		amount = int(prompt.perfect_damage)
	elif good:
		amount = int(prompt.press_damage)
	events.append({
		"type": "prompt_resolved",
		"seq": sequence.seq,
		"prompt": idx,
		"hit": prompt.hit,
		"character": striker.id,
		"outcome": outcome,
		"perfect": perfect,
		"offset_us": int(item.offset_us),
		"damage": amount,
		"hp": striker.hp,
		"max_hp": striker.max_hp,
		"ap": striker.ap,
		"ap_delta": 0,
		"downed": false,
	})
	if amount > 0:
		var targets: Array = sequence.targets
		# A follow-up strikes the skill's first target only.
		var struck: Array = [targets[0]] if follow_up and not targets.is_empty() else targets
		for target_id: int in struck:
			var target := get_combatant(target_id)
			if not target.is_party() and target.is_alive():
				_deal_damage(striker, target, amount, "follow_up" if follow_up else "ability", events)
	if follow_up and good:
		_change_gauge(tuning.team_gauge_per_follow_up, events)


## A follow-up counts only if at least one of the prompts it requires was a good or perfect press.
func _requirement_met(prompt: Dictionary) -> bool:
	var required: Array = prompt.requires
	if required.is_empty():
		return true
	for idx: int in required:
		if int(sequence.states[idx]) == PromptState.RESOLVED and Defense.is_press(int(sequence.outcomes[idx])):
			return true
	return false


## True once every prompt this one requires is resolved or void and none was good.
func _requirement_failed(prompt: Dictionary) -> bool:
	var required: Array = prompt.requires
	if required.is_empty():
		return false
	for idx: int in required:
		if int(sequence.states[idx]) == PromptState.PENDING:
			return false
	return not _requirement_met(prompt)


## Cancels pending prompts that can no longer matter: their character is down, the attacker is
## down, a skill's targets are all gone, or a follow-up's presses all missed.
func _void_dead_prompts(events: Array[Dictionary]) -> void:
	if sequence.is_empty():
		return
	var voided: Array[int] = []
	var reason := ""
	var prompts: Array = sequence.prompts
	if String(sequence.kind) == SEQUENCE_SKILL:
		var targets_gone := _skill_targets_gone()
		for i: int in prompts.size():
			if int(sequence.states[i]) != PromptState.PENDING:
				continue
			if targets_gone:
				reason = "targets_down"
			elif _requirement_failed(prompts[i]):
				reason = "no_good_press"
			else:
				continue
			sequence.states[i] = PromptState.VOID
			voided.append(i)
	else:
		var attacker_down := not get_combatant(int(sequence.source)).is_alive()
		reason = "attacker_down" if attacker_down else "downed"
		for i: int in prompts.size():
			if int(sequence.states[i]) != PromptState.PENDING:
				continue
			var character := get_combatant(int((prompts[i] as Dictionary).character))
			if attacker_down or not character.is_alive():
				sequence.states[i] = PromptState.VOID
				voided.append(i)
	if not voided.is_empty():
		events.append({"type": "prompts_voided", "seq": sequence.seq, "prompts": voided, "reason": reason})


## True if the skill hits enemies and none of its targets is standing.
func _skill_targets_gone() -> bool:
	if int(sequence.mode) != AbilityData.Target.SINGLE_ENEMY and int(sequence.mode) != AbilityData.Target.ALL_ENEMIES:
		return false
	for target_id: int in sequence.targets:
		if get_combatant(target_id).is_alive():
			return false
	return true


func _finish_sequence_if_done(events: Array[Dictionary]) -> void:
	if not pending_prompts().is_empty():
		return
	var source := get_combatant(int(sequence.source))
	var reason := "completed"
	if String(sequence.kind) == SEQUENCE_SKILL:
		if _skill_targets_gone():
			reason = "targets_down"
		events.append({"type": "sequence_resolved", "seq": sequence.seq, "reason": reason})
	else:
		var any_standing := false
		for target_id: int in sequence.targets:
			if get_combatant(target_id).is_alive():
				any_standing = true
				break
		if not source.is_alive():
			reason = "attacker_down"
		elif not any_standing:
			reason = "targets_down"
		events.append({"type": "sequence_resolved", "seq": sequence.seq, "reason": reason})
		if reason == "completed":
			_resolve_counters(source, events)
	sequence = {}
	_end_of_turn(source, events)
	events.append({"type": "turn_ended", "turn": turn_number, "actor": source.id})
	_advance_turn(events)


## Counter for every target who perfectly defended all of their prompts. If the attack was
## party-wide and every target did, they strike together as one team counter instead.
func _resolve_counters(attacker: Combatant, events: Array[Dictionary]) -> void:
	if not attacker.is_alive():
		return
	var targets: Array = sequence.targets
	var counterers: Array[int] = []
	for target_id: int in targets:
		if get_combatant(target_id).is_alive() and _all_perfect(target_id):
			counterers.append(target_id)
	if counterers.is_empty():
		return
	var team := (
		int(sequence.mode) == EnemyAttackData.TargetMode.PARTY
		and targets.size() >= 2
		and counterers.size() == targets.size()
	)
	if team:
		var total := 0
		for actor_id: int in counterers:
			var actor := get_combatant(actor_id)
			total += CombatMath.percent(actor.power, _counter_percent(actor, tuning.team_counter_percent))
		events.append({"type": "counter", "seq": sequence.seq, "actors": counterers.duplicate(), "target": attacker.id, "team": true})
		_deal_damage(get_combatant(counterers[0]), attacker, _apply_variance(maxi(1, total)), "team_counter", events)
		return
	for actor_id: int in counterers:
		if not attacker.is_alive():
			break
		var actor := get_combatant(actor_id)
		events.append({"type": "counter", "seq": sequence.seq, "actors": [actor_id], "target": attacker.id, "team": false})
		_deal_damage(actor, attacker, _roll_damage(actor.power, _counter_percent(actor, tuning.counter_percent)), "counter", events)


## Riposte Stance multiplies the counter percent.
func _counter_percent(actor: Combatant, base_percent: int) -> int:
	if actor.has_status(Status.RIPOSTE):
		return CombatMath.percent(base_percent, tuning.riposte_counter_percent)
	return base_percent


func _all_perfect(character_id: int) -> bool:
	var prompts: Array = sequence.prompts
	var found := false
	for i: int in prompts.size():
		var prompt: Dictionary = prompts[i]
		if int(prompt.character) != character_id:
			continue
		found = true
		if int(sequence.states[i]) != PromptState.RESOLVED:
			return false
		if not (prompt.perfect as Array).has(int(sequence.outcomes[i])):
			return false
	return found


# --- statuses, healing, revive, timeline ------------------------------------------------------

## Adds or refreshes a status. Returns true if the timeline changed (a speed change).
func _add_status(target: Combatant, id: String, turns: int, source: int, events: Array[Dictionary]) -> bool:
	var timeline_changed := false
	if target.has_status(id):
		var entry: Dictionary = target.statuses[id]
		entry.turns = maxi(int(entry.turns), turns)
		entry.source = source
	else:
		target.statuses[id] = {"turns": turns, "source": source}
		if id == Status.SLOWED:
			_set_speed(target, CombatMath.percent_min1(target.base_speed, tuning.slow_speed_percent))
			timeline_changed = true
	events.append(_status_event(target, id, true))
	if id == Status.TAUNTED:
		_refresh_intents(events)
	return timeline_changed


func _remove_status(target: Combatant, id: String, events: Array[Dictionary]) -> void:
	if not target.has_status(id):
		return
	var source := int((target.statuses[id] as Dictionary).source)
	target.statuses.erase(id)
	if id == Status.SLOWED:
		_set_speed(target, target.base_speed)
	events.append({"type": "status_changed", "target": target.id, "status": id, "active": false, "turns": 0, "source": source})


func _status_event(target: Combatant, id: String, active: bool) -> Dictionary:
	var entry: Dictionary = target.statuses.get(id, {})
	return {
		"type": "status_changed",
		"target": target.id,
		"status": id,
		"active": active,
		"turns": int(entry.get("turns", 0)),
		"source": int(entry.get("source", -1)),
	}


## Changes speed and rescales the wait for the next turn (DESIGN.md 2.1).
func _set_speed(c: Combatant, new_speed: int) -> void:
	new_speed = maxi(1, new_speed)
	if new_speed == c.speed:
		return
	if c.is_alive():
		@warning_ignore("integer_division")
		var waiting := maxi(0, c.next_turn_at - time_now) * c.speed / new_speed
		c.next_turn_at = time_now + waiting
	c.speed = new_speed


## Moves a fighter's next turn by `delta` ticks (never before the current turn).
func _shift_turn(c: Combatant, delta: int, events: Array[Dictionary]) -> void:
	var before := c.next_turn_at
	c.next_turn_at = maxi(time_now, c.next_turn_at + delta)
	events.append({"type": "turn_shifted", "target": c.id, "delta": c.next_turn_at - before})


func _heal(source: Combatant, target: Combatant, amount: int, events: Array[Dictionary]) -> void:
	var before := target.hp
	target.hp = mini(target.max_hp, target.hp + amount)
	events.append({"type": "healed", "source": source.id, "target": target.id, "amount": target.hp - before,
			"hp": target.hp, "max_hp": target.max_hp})


## Brings a downed party member back (DESIGN.md 2.1: next turn one turn cost from now).
func _revive(source: Combatant, target: Combatant, pct: int, events: Array[Dictionary]) -> void:
	if target.is_alive():
		return
	target.hp = CombatMath.percent_min1(target.max_hp, pct)
	target.perfect_defenses = 0
	target.next_turn_at = time_now + Timeline.turn_cost(target.speed, tuning.timeline_base)
	events.append({"type": "revived", "source": source.id, "target": target.id, "hp": target.hp, "max_hp": target.max_hp})
	_refresh_intents(events)


## A fighter went down: its statuses end, taunts it holds end, and intents re-target.
func _on_downed(target: Combatant, events: Array[Dictionary]) -> void:
	for id: String in Status.ALL:
		if target.has_status(id):
			_remove_status(target, id, events)
	if not target.is_party():
		intents.erase(target.id)
		return
	for enemy_id: int in living_enemy_ids():
		var enemy := get_combatant(enemy_id)
		if enemy.has_status(Status.TAUNTED) and int((enemy.statuses[Status.TAUNTED] as Dictionary).source) == target.id:
			_remove_status(enemy, Status.TAUNTED, events)
	_refresh_intents(events)


func _change_gauge(delta: int, events: Array[Dictionary]) -> void:
	var before := team_gauge
	team_gauge = clampi(team_gauge + delta, 0, tuning.team_gauge_max)
	if team_gauge != before:
		events.append({"type": "team_gauge", "value": team_gauge, "delta": team_gauge - before, "max": tuning.team_gauge_max})


# --- helpers ----------------------------------------------------------------------------------

func _roll_damage(power: int, pct: int) -> int:
	return _apply_variance(CombatMath.percent_min1(power, pct))


## An enemy hit on a party member: power x hit percent, then Guard, then variance.
func _enemy_hit_damage(enemy: Combatant, target: Combatant, pct: int) -> int:
	var amount := CombatMath.percent_min1(enemy.power, pct)
	if target.has_status(Status.GUARDED):
		amount = CombatMath.percent_min1(amount, tuning.guard_damage_percent)
	return _apply_variance(amount)


func _apply_variance(amount: int) -> int:
	if tuning.damage_variance_percent <= 0:
		return maxi(1, amount)
	var spread := rng.range_int(-tuning.damage_variance_percent, tuning.damage_variance_percent)
	return CombatMath.percent_min1(amount, 100 + spread)


## Lowers HP, respecting practice floors. Returns the HP actually lost.
func _lose_hp(target: Combatant, amount: int) -> int:
	var floor_hp := 0
	if target.is_party() and practice.invulnerable_party:
		floor_hp = 1
	elif not target.is_party() and practice.immortal_enemies:
		floor_hp = 1
	var before := target.hp
	target.hp = maxi(mini(floor_hp, before), before - amount)
	return before - target.hp


func _deal_damage(source: Combatant, target: Combatant, amount: int, cause: String, events: Array[Dictionary]) -> void:
	_lose_hp(target, amount)
	events.append({
		"type": "damage",
		"source": source.id,
		"target": target.id,
		"amount": amount,
		"hp": target.hp,
		"max_hp": target.max_hp,
		"cause": cause,
	})
	if not target.is_alive():
		events.append({"type": "downed", "target": target.id})
		_on_downed(target, events)


func _change_ap(target: Combatant, delta: int, reason: String, events: Array[Dictionary]) -> void:
	var applied := _change_ap_silent(target, delta)
	if applied != 0:
		events.append({"type": "ap_changed", "character": target.id, "delta": applied, "ap": target.ap, "reason": reason})


## Changes AP within [0, max_ap] and returns the change actually applied.
func _change_ap_silent(target: Combatant, delta: int) -> int:
	var before := target.ap
	target.ap = clampi(target.ap + delta, 0, tuning.max_ap)
	return target.ap - before


func _ids_of_team(team: Combatant.Team, living_only: bool) -> Array[int]:
	var ids: Array[int] = []
	for c: Combatant in combatants:
		if c.team == team and (not living_only or c.is_alive()):
			ids.append(c.id)
	return ids


func _reject(reason: String, command: Dictionary) -> Dictionary:
	return {"type": "command_rejected", "reason": reason, "command": command.duplicate(true)}
