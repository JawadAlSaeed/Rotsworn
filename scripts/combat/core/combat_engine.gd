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
##   use_item         {turn, actor, uid, targets}                phase AWAITING_ACTION
##   resolve_prompts  {seq, results:[{prompt, outcome, offset_us}]}  phase AWAITING_TIMING
##                    partial is fine; per character, prompts must resolve in order
##   practice         {invulnerable_party?, immortal_enemies?, force_attack?}  if setup allows
##
## Events (Dictionary with "type"):
##   combat_started          {seed, fighters:[Combatant.to_dict()], practice_allowed, opening,
##                           items:[item_info()]} (backpack items usable in this fight)
##                           opening: "normal" | "first_strike" (DESIGN.md 2.12)
##   intent                  {enemy, attack, name, mode, targets:[id], kinds:[hit kind], times:[ms],
##                           feints:[bool] (which hits are feints, card #129)}
##                           what this enemy will do on its next turn (DESIGN.md 2.8). Sent at
##                           fight start, after its turn, and whenever its targets change.
##                           times: each hit's impact, ms after the attack starts (with
##                           attack_tempo_percent, like the declared hits' at_ms).
##   turn_started            {turn, actor, team, time}
##   turn_order              {order:[id]}      current actor first, then upcoming turns
##   ability_used            {turn, actor, ability, targets:[id]}
##   item_used               {turn, actor, uid, item, name, targets:[id]} (DESIGN.md 8.1)
##   damage                  {source, target, amount, hp, max_hp, cause, crit (a critical hit)}
##                           cause: "ability" | "follow_up" | "counter" | "team_counter" | "bleed"
##   healed                  {source, target, amount, hp, max_hp}
##   revived                 {source, target, hp, max_hp}
##   downed                  {target}
##   ap_changed              {character, delta, ap, reason}  reason: "spend" | "ability" | "given"
##                           | "gear"
##   status_changed          {target, status, active, turns, source}   see Status
##   turn_shifted            {target, delta}   a fighter's next turn moved (delta in timeline
##                           ticks: negative = sooner); a turn_order event follows
##   team_gauge              {value, delta, max}
##   timed_sequence_declared {seq, kind, source, action, name, mode, targets:[id],
##                            alert_cue, allow_timing_ring, hits:[hit], prompts:[prompt]}
##       hit    = {index, at_ms, kind, approach_ms, feint, damage_percent, impact_sfx}
##                kind is the hit's kind in this fight (a forced kind in a hard fight, card #187);
##                at_ms and approach_ms are scaled by the enemy's tempo (card #188).
##       prompt = {idx, hit, character, at_ms, kind, windows:{Outcome:[early_us, late_us]},
##                 perfect:[Outcome], damage, press_damage, perfect_damage, role, requires:[idx],
##                 crit (a party press that crits if it lands)}
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
##   counter                 {seq, actors:[id], target, team, hits, mixed}  followed by a damage
##                           event. hits: perfectly defended hits it answers; mixed: parries and jumps
##   enemy_phase             {enemy, phase, text}   a boss dropped under its phase two HP: new
##                           attacks, speed and attack tempo (an intent and turn_order follow)
##   turn_ended              {turn, actor}
##   practice_changed        {invulnerable_party, immortal_enemies, force_attack}
##                           also emitted (before timed_sequence_declared) when a forced
##                           attack is used and force_attack clears
##   escaped                 {character}     that hero ran from the fight (Run, DESIGN.md 2.13)
##   combat_ended            {result}        "victory" | "defeat" | "escaped" (every hero still
##                                           standing ran, DESIGN.md 2.13)
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
	## The tutorial's gate (DESIGN.md 7.8): an enemy's turn has started and its attack waits for
	## the practice command open_gate.
	AWAITING_GATE,
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
## Who a fight item is used on (item_info().target).
const ITEM_ALLY := "ally"
const ITEM_PARTY := "party"
const ITEM_ENEMIES := "enemies"
const ITEM_DOWNED := "downed"

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
## "victory", "defeat" or "escaped" once the fight is over.
var result: String = ""
## Practice options (only changeable when the setup allows practice).
var practice: Dictionary = {"invulnerable_party": false, "immortal_enemies": false, "force_attack": ""}
## The tutorial's staging (DESIGN.md 7.8), set by practice commands, local only: enemy turns pass
## (hold_enemies), hero turns pass (hold_party), enemy attacks slowed (tempo_percent, 0 = tuning's).
## gate: an enemy's attack waits at its turn start until open_gate (one try at a time).
## attack: every enemy that has it always picks this attack (the lesson's), "" = normal picks.
## hero: only this hero acts (the other heroes' turns pass), -1 = every hero.
var stage: Dictionary = {"hold_enemies": false, "hold_party": false, "tempo_percent": 0, "gate": false,
		"attack": "", "hero": -1}
## The enemy waiting at the gate (-1: none).
var _gated: int = -1
## Backpack items not used yet (uids, DESIGN.md 8.1).
var items_left: Array[int] = []

var _setup: CombatSetup
var _abilities: Dictionary = {}
var _attacks: Dictionary = {}
## uid -> ItemData for the fight's items, their amounts (combined items are stronger) and names.
var _items: Dictionary = {}
var _item_amounts: Dictionary = {}
var _item_names: Dictionary = {}


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
	items_left.clear()
	for entry: Dictionary in _setup.items:
		items_left.append(int(entry.uid))
	var fighters: Array[Dictionary] = []
	for c: Combatant in combatants:
		fighters.append(c.to_dict())
	var item_list: Array = []
	for uid: int in items_left:
		item_list.append(item_info(uid))
	events.append({
		"type": "combat_started",
		"seed": _setup.rng_seed,
		"fighters": fighters,
		"practice_allowed": _setup.allow_practice,
		"opening": OPENING_NAMES[_setup.opening],
		"items": item_list,
	})
	if _setup.start_team_gauge > 0:
		# Carried over from the run's last fight (card #146).
		_change_gauge(_setup.start_team_gauge, events)
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
		CombatCommands.USE_ITEM:
			_cmd_use_item(command, events)
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
	engine.items_left.assign(snap.get("items_left", []))
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
		var c := get_combatant(id)
		if not c.is_alive() and not c.escaped:
			ids.append(id)
	return ids


## Party members who ran from the fight (DESIGN.md 2.13).
func escaped_party_ids() -> Array[int]:
	var ids: Array[int] = []
	for id: int in party_ids():
		if get_combatant(id).escaped:
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
		AbilityData.Target.ALL_ALLIES:
			list = living_party_ids()
	return list


## A fight item as plain data: {uid, id, name, description, ap_cost, target} (target: ITEM_ALLY,
## ITEM_PARTY, ITEM_ENEMIES or ITEM_DOWNED). Empty if the uid is not one of the fight's items.
func item_info(uid: int) -> Dictionary:
	var item := _items.get(uid) as ItemData
	if item == null:
		return {}
	return {"uid": uid, "id": item.id, "name": String(_item_names.get(uid, item.display_name)), "description": item.description,
			"ap_cost": item.ap_cost, "target": item_target(item)}


## Who an item is used on.
static func item_target(item: ItemData) -> String:
	match item.effect:
		ItemData.Effect.HEAL_ONE:
			return ITEM_ALLY
		ItemData.Effect.REVIVE_ONE:
			return ITEM_DOWNED
		ItemData.Effect.DAMAGE_ALL:
			return ITEM_ENEMIES
	return ITEM_PARTY


## The ids an item would pick from (ally, downed) or affect (party, enemies).
func item_targets(uid: int) -> Array[int]:
	var item := _items.get(uid) as ItemData
	var list: Array[int] = []
	if item == null:
		return list
	match item_target(item):
		ITEM_ALLY, ITEM_PARTY:
			list = living_party_ids()
		ITEM_DOWNED:
			list = downed_party_ids()
		ITEM_ENEMIES:
			list = living_enemy_ids()
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
		"items_left": items_left.duplicate(),
		"rng_state": rng.state,
	}


# --- building ---------------------------------------------------------------------------------

func _build_lookups() -> void:
	_abilities.clear()
	_attacks.clear()
	for data: CharacterData in _setup.party:
		for ability: AbilityData in data.all_abilities():
			_abilities[ability.id] = ability
	_items.clear()
	_item_amounts.clear()
	_item_names.clear()
	for entry: Dictionary in _setup.items:
		var item := entry.item as ItemData
		_items[int(entry.uid)] = item
		_item_amounts[int(entry.uid)] = int(entry.get("amount", item.amount_percent))
		_item_names[int(entry.uid)] = String(entry.get("name", item.display_name))
	if _setup.team_ultimate != null:
		_abilities[_setup.team_ultimate.id] = _setup.team_ultimate
	if _setup.can_run and _setup.run_ability != null:
		_abilities[_setup.run_ability.id] = _setup.run_ability
	for data: EnemyData in _setup.enemies:
		for attack: EnemyAttackData in data.attacks + data.phase_two_attacks:
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
		c.passives = _setup.party_passives_of(slot)
		c.ap = clampi(tuning.start_ap + Passive.amount(c, Passive.START_AP), 0, tuning.max_ap)
		c.power = _setup.party_power(slot, data)
		c.speed = _setup.party_speed(slot, data)
		c.base_speed = c.speed
		for ability: AbilityData in _setup.party_abilities(slot, data):
			c.ability_ids.append(ability.id)
		if _setup.team_ultimate != null:
			c.ability_ids.append(_setup.team_ultimate.id)
		if _setup.can_run and _setup.run_ability != null:
			c.ability_ids.append(_setup.run_ability.id)
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
		c.max_hp = CombatMath.percent_min1(CombatMath.percent_min1(tuning.base_enemy_hp, data.hp_percent),
				_setup.enemy_hp_percent)
		c.hp = c.max_hp
		c.power = CombatMath.percent_min1(CombatMath.percent_min1(tuning.base_enemy_hit_damage, data.power_percent),
				_setup.enemy_power_percent)
		c.speed = maxi(1, CombatMath.percent(data.speed, _setup.enemy_speed_percent))
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
		var held := bool(stage.hold_enemies)
		if actor.is_party():
			held = bool(stage.hold_party) or (int(stage.hero) >= 0 and actor.id != int(stage.hero))
		if not actor.is_alive() or held:
			# Bled out at the start of its turn, or held by the tutorial: the turn passes.
			_end_of_turn(actor, events)
			events.append({"type": "turn_ended", "turn": turn_number, "actor": actor.id})
			continue
		if actor.is_party():
			phase = Phase.AWAITING_ACTION
			return
		if bool(stage.gate):
			_gated = actor.id
			phase = Phase.AWAITING_GATE
			return
		if _begin_enemy_attack(actor, events):
			return
		# The enemy had nothing it could do; its turn passes.
		_end_of_turn(actor, events)
		events.append({"type": "turn_ended", "turn": turn_number, "actor": actor.id})
	push_warning("CombatEngine: turn guard reached; nobody can act")


## Statuses that last until the holder's next turn end now; a hero carrying rotten items loses
## some HP (never below 1).
func _start_of_turn(actor: Combatant, events: Array[Dictionary]) -> void:
	for id: String in Status.ALL:
		if Status.ends_at_own_turn(id) and actor.has_status(id):
			_remove_status(actor, id, events)
	var rot := Passive.amount(actor, Passive.ROT)
	if rot > 0 and actor.is_alive():
		var amount := mini(CombatMath.percent_min1(actor.max_hp, rot), actor.hp - 1)
		if amount > 0:
			_deal_damage(actor, actor, amount, "rot", events)
	if actor.has_status(Status.BLEEDING) and actor.is_alive():
		var source := get_combatant(int((actor.statuses[Status.BLEEDING] as Dictionary).source))
		var power := source.power if source != null else 1
		_deal_damage(source if source != null else actor, actor, CombatMath.percent_min1(power, tuning.bleed_power_percent),
				"bleed", events)
	if actor.has_status(Status.REGEN) and actor.is_alive():
		var healer := get_combatant(int((actor.statuses[Status.REGEN] as Dictionary).source))
		_heal(healer if healer != null else actor, actor, CombatMath.percent_min1(actor.max_hp, tuning.regen_percent), events)


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
	var tempo := _tempo_percent(actor)
	var hard := _forced_hits(actor)
	for hit_index: int in attack.hits.size():
		var hit: AttackHitData = attack.hits[hit_index]
		var at_ms := CombatMath.percent(hit.impact_ms, tempo)
		var kind := hit.kind_in(hard)
		hits.append({
			"index": hit_index,
			"at_ms": at_ms,
			"kind": kind,
			"approach_ms": CombatMath.percent(hit.approach_ms, tempo),
			"feint": hit.feint_in(hard),
			"damage_percent": hit.damage_percent,
			"impact_sfx": hit.impact_sfx,
		})
		# Each hero in turn: hit i strikes only its own target (DESIGN.md 3.11).
		var hit_targets: Array[int] = targets
		if attack.target_mode == EnemyAttackData.TargetMode.EACH:
			hit_targets = [targets[hit_index % targets.size()]]
		for target_id: int in hit_targets:
			prompts.append(_prompt(prompts.size(), hit_index, target_id, at_ms, kind,
					Defense.build_windows(kind, tuning), _enemy_hit_damage(actor, get_combatant(target_id), hit.damage_percent),
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
		# Nobody is left standing in the fight: if anyone got away, the party escaped.
		outcome = "escaped" if not escaped_party_ids().is_empty() else "defeat"
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
	var staged := String(stage.attack)
	if not staged.is_empty() and enemy.attack_ids.has(staged):
		return {"attack": staged, "targets": _pick_targets(enemy, get_attack(staged))}
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


## Whole party for party-wide attacks; standing heroes in party order from a random one on for
## each-in-turn attacks (one per hit at most); otherwise the taunter if one is standing, else a random standing
## party member.
func _pick_targets(enemy: Combatant, attack: EnemyAttackData) -> Array[int]:
	var living := living_party_ids()
	var targets: Array[int] = []
	if living.is_empty() or attack == null:
		return targets
	if attack.target_mode == EnemyAttackData.TargetMode.PARTY:
		return living
	if attack.target_mode == EnemyAttackData.TargetMode.EACH:
		# A string shorter than the party bites only as many heroes as it has hits.
		var first := rng.range_int(0, living.size() - 1)
		for i: int in mini(living.size(), maxi(1, attack.hits.size())):
			targets.append(living[(first + i) % living.size()])
		return targets
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
	if attack.target_mode == EnemyAttackData.TargetMode.EACH:
		var living := living_party_ids()
		if targets.size() != mini(living.size(), maxi(1, attack.hits.size())):
			return false
		for id: int in targets:
			if not living.has(id):
				return false
		return true
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
	var feints: Array[bool] = []
	var enemy := get_combatant(enemy_id)
	var tempo := _tempo_percent(enemy)
	var hard := _forced_hits(enemy)
	for hit: AttackHitData in attack.hits:
		kinds.append(hit.kind_in(hard))
		times.append(CombatMath.percent(hit.impact_ms, tempo))
		feints.append(hit.feint_in(hard))
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
		"feints": feints,
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
		AbilityData.Target.ALL_ENEMIES, AbilityData.Target.SELF, AbilityData.Target.ALL_ALLIES:
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
				var crit := _roll_crit(actor)
				var bonus := _exposed_bonus(actor, ability, target_id == exposed) + _marked_bonus(ability, targets) \
						+ _empowered_bonus(actor, ability)
				var amount := _skill_damage(actor.power, pct, bonus)
				_deal_damage(actor, target, _crit_damage(amount) if crit else amount, "ability", events, crit)
	_apply_effects(actor, ability, targets, false, exposed, events)
	_end_of_turn(actor, events)
	events.append({"type": "turn_ended", "turn": turn_number, "actor": actor.id})
	_advance_turn(events)


## A backpack item used as the hero's action (DESIGN.md 8.1): it costs its AP, works at once (no
## timed press), is gone for the rest of the fight, and the turn ends.
func _cmd_use_item(command: Dictionary, events: Array[Dictionary]) -> void:
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
	var uid := int(command.get("uid", -1))
	if not items_left.has(uid):
		events.append(_reject("unknown_item", command))
		return
	var actor := get_combatant(actor_id)
	var item := _items[uid] as ItemData
	if actor.ap < item.ap_cost:
		events.append(_reject("not_enough_ap", command))
		return
	var allowed := item_targets(uid)
	var targets: Array[int] = []
	if item_target(item) in [ITEM_ALLY, ITEM_DOWNED]:
		var requested: Variant = command.get("targets", [])
		if typeof(requested) != TYPE_ARRAY or (requested as Array).size() != 1:
			events.append(_reject("needs_one_target", command))
			return
		var target_id := int((requested as Array)[0])
		if not allowed.has(target_id):
			events.append(_reject("invalid_target", command))
			return
		targets.append(target_id)
	else:
		targets = allowed
		if targets.is_empty():
			events.append(_reject("invalid_target", command))
			return
	if item.ap_cost > 0:
		_change_ap(actor, -item.ap_cost, "spend", events)
	items_left.erase(uid)
	events.append({"type": "item_used", "turn": turn_number, "actor": actor.id, "uid": uid, "item": item.id,
			"name": String(_item_names.get(uid, item.display_name)), "targets": targets.duplicate()})
	var pct := int(_item_amounts.get(uid, item.amount_percent))
	for target_id: int in targets:
		var target := get_combatant(target_id)
		match item.effect:
			ItemData.Effect.HEAL_ONE, ItemData.Effect.HEAL_ALL:
				if target.is_alive():
					_heal(actor, target, CombatMath.percent_min1(target.max_hp, pct), events)
			ItemData.Effect.REVIVE_ONE:
				_revive(actor, target, pct, events)
			ItemData.Effect.DAMAGE_ALL:
				if target.is_alive():
					_deal_damage(actor, target, _roll_damage(tuning.base_party_damage, pct), "item", events)
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
	for key: String in ["force_attack", "stage_attack"]:
		var attack_id := String(command.get(key, ""))
		if not attack_id.is_empty() and not _attacks.has(attack_id):
			events.append(_reject("unknown_attack", command))
			return
	if command.has("invulnerable_party"):
		practice.invulnerable_party = bool(command.invulnerable_party)
	if command.has("immortal_enemies"):
		practice.immortal_enemies = bool(command.immortal_enemies)
	if command.has("force_attack"):
		practice.force_attack = String(command.force_attack)
	for key: String in ["hold_enemies", "hold_party"]:
		if command.has(key):
			stage[key] = bool(command[key])
	if command.has("tempo_percent"):
		stage.tempo_percent = maxi(0, int(command.tempo_percent))
	if command.has("gate"):
		stage.gate = bool(command.gate)
	if command.has("hero"):
		stage.hero = int(command.hero)
	if bool(command.get("full_ap", false)):
		for id: int in living_party_ids():
			var hero := get_combatant(id)
			_change_ap(hero, tuning.max_ap - hero.ap, "given", events)
	if bool(command.get("fill_gauge", false)):
		# The tutorial's Team Ultimate lesson (DESIGN.md 7.8).
		_change_gauge(tuning.team_gauge_max, events)
	events.append(_practice_changed_event())
	if command.has("force_attack"):
		_show_forced_intent(events)
	if command.has("stage_attack"):
		stage.attack = String(command.stage_attack)
		_show_staged_intents(events)
	if bool(command.get("open_gate", false)) and phase == Phase.AWAITING_GATE:
		_open_gate(events)
	elif bool(command.get("pass_turn", false)):
		_pass_turn(events)


## The gated enemy attacks now (its forced attack and tempo as they are now).
func _open_gate(events: Array[Dictionary]) -> void:
	var actor := get_combatant(_gated)
	_gated = -1
	if actor != null and actor.is_alive() and _begin_enemy_attack(actor, events):
		return
	if actor != null:
		_end_of_turn(actor, events)
		events.append({"type": "turn_ended", "turn": turn_number, "actor": actor.id})
	_advance_turn(events)


## The tutorial moves on: the hero choosing an action, or the enemy at the gate, lets the turn go.
func _pass_turn(events: Array[Dictionary]) -> void:
	if phase != Phase.AWAITING_ACTION and phase != Phase.AWAITING_GATE:
		return
	var actor := get_combatant(active_actor)
	_gated = -1
	_end_of_turn(actor, events)
	events.append({"type": "turn_ended", "turn": turn_number, "actor": actor.id})
	_advance_turn(events)


## `enemy`'s attack tempo in percent of its authored timing (lower = faster, card #188): the
## tutorial's slowed attacks as they are; else the fight's tempo (CombatSetup.attack_tempo_percent,
## 0 = tuning's) times the enemy's own (phase two), floored by CombatSetup.tempo_floor.
func _tempo_percent(enemy: Combatant) -> int:
	if int(stage.tempo_percent) > 0:
		return int(stage.tempo_percent)
	var base := _setup.attack_tempo_percent if _setup.attack_tempo_percent > 0 else tuning.attack_tempo_percent
	var own := enemy.tempo_percent if enemy != null and enemy.tempo_percent > 0 else 100
	return maxi(CombatMath.percent(base, own), CombatSetup.tempo_floor(tuning))


## True if `enemy`'s hits take their forced kinds (card #187): a hard fight (elite, guard, boss) or
## an enemy that always uses them (the deep variants).
func _forced_hits(enemy: Combatant) -> bool:
	if _setup.forced_hits:
		return true
	if enemy == null or enemy.is_party() or enemy.slot >= _setup.enemies.size():
		return false
	return _setup.enemies[enemy.slot].forced_hits


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


## Every enemy that has the staged attack shows it as its intent right away.
func _show_staged_intents(events: Array[Dictionary]) -> void:
	var staged := String(stage.attack)
	if staged.is_empty():
		return
	for id: int in living_enemy_ids():
		var c := get_combatant(id)
		if c.attack_ids.has(staged) and String((intents.get(id, {}) as Dictionary).get("attack", "")) != staged:
			intents[id] = {"attack": staged, "targets": _pick_targets(c, get_attack(staged))}
			events.append(_intent_event(id))


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
			var crit := false
			if damaging:
				var bonus := _exposed_bonus(striker, ability, exposed >= 0) + _marked_bonus(ability, targets) \
						+ _empowered_bonus(striker, ability)
				good = _skill_damage(striker.power, _skill_percent(striker, ability, false), bonus)
				perfect = _skill_damage(striker.power, _skill_percent(striker, ability, true), bonus)
				miss = CombatMath.percent(good, tuning.skill_miss_damage_percent)
				# Rolled now with the damage, so it is in the declared event (DESIGN.md 8.2); a missed
				# press never crits.
				crit = _roll_crit(striker)
				if crit:
					good = _crit_damage(good)
					perfect = _crit_damage(perfect)
			press_idxs.append(prompts.size())
			var press := _prompt(prompts.size(), hit_index, striker_id, at_ms, AttackHitData.Kind.PRESS,
					Defense.build_windows(AttackHitData.Kind.PRESS, tuning, ability.perfect_window_percent),
					miss, good, perfect, ROLE_PRESS, [])
			press["crit"] = crit
			prompts.append(press)
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
			var good := _roll_damage(ally.power, tuning.follow_up_percent)
			var perfect := _roll_damage(ally.power, tuning.follow_up_perfect_percent)
			var crit := _roll_crit(ally)
			var follow := _prompt(prompts.size(), hit_index, ally_id, at_ms, AttackHitData.Kind.PRESS,
					Defense.build_follow_up_windows(tuning), 0, _crit_damage(good) if crit else good,
					_crit_damage(perfect) if crit else perfect, ROLE_FOLLOW_UP, press_idxs)
			follow["crit"] = crit
			prompts.append(follow)
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
	if ability.escape:
		# Run: only a perfect press gets this hero out of the fight.
		if all_perfect and any_press:
			actor.escaped = true
			events.append({"type": "escaped", "character": actor.id})
			_on_downed(actor, events)
		return
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
	_use_damage_statuses(actor, ability, targets, events)
	var first := get_combatant(targets[0]) if not targets.is_empty() else null
	var gain := ability.ap_gain + (ability.press_ap_gain if good else 0)
	if gain > 0:
		_change_ap(actor, gain, "ability", events)
	# Ally effects reach every party target (one for most skills, the whole party for ALL_ALLIES).
	var give := ability.give_ap + (ability.press_give_ap if good else 0)
	var heal := ability.heal_percent + (ability.press_heal_percent if good else 0)
	var hasten := ability.turn_hasten_percent + (ability.press_turn_hasten_percent if good else 0)
	var delay := ability.turn_delay_percent + (ability.press_turn_delay_percent if good else 0)
	for target_id: int in targets:
		var target := get_combatant(target_id)
		if not target.is_alive():
			continue
		if target.is_party():
			if give > 0:
				_change_ap(target, give, "given", events)
			if heal > 0:
				_heal(actor, target, CombatMath.percent_min1(target.max_hp, heal), events)
			if hasten > 0:
				var waiting := maxi(0, target.next_turn_at - time_now)
				_shift_turn(target, -CombatMath.percent(waiting, mini(100, hasten)), events)
				timeline_changed = true
		elif delay > 0:
			_shift_turn(target, CombatMath.percent(Timeline.turn_cost(target.speed, tuning.timeline_base), delay), events)
			timeline_changed = true
	var revive := ability.revive_percent + (ability.press_revive_percent if good else 0)
	if revive > 0 and first != null and first.is_party() and not first.is_alive():
		_revive(actor, first, revive, events)
		timeline_changed = true
	if ability.gauge_gain > 0:
		_change_gauge(ability.gauge_gain, events)
	if Status.is_known(ability.status) and (good or not ability.status_needs_perfect):
		var turns := ability.status_turns + (ability.press_status_turns if good else 0)
		for target_id: int in targets:
			var target := get_combatant(target_id)
			if target.is_alive():
				timeline_changed = _add_status(target, ability.status, turns, actor.id, events) or timeline_changed
		if good and ability.press_status_on_self and not targets.has(actor.id):
			timeline_changed = _add_status(actor, ability.status, turns, actor.id, events) or timeline_changed
	if actor.is_alive():
		if Status.is_known(ability.self_status):
			timeline_changed = _add_status(actor, ability.self_status, ability.self_status_turns, actor.id, events) \
					or timeline_changed
		if good and Status.is_known(ability.press_self_status):
			timeline_changed = _add_status(actor, ability.press_self_status, ability.self_status_turns, actor.id, events) \
					or timeline_changed
	if ability.team_ultimate:
		for id: int in downed_party_ids():
			_revive(actor, get_combatant(id), tuning.team_ultimate_revive_percent, events)
			timeline_changed = true
	if timeline_changed:
		events.append({"type": "turn_order", "order": preview_turn_order(tuning.turn_order_preview)})


## A damaging skill on enemies uses up the striker's Empowered and one use of each target's Marked.
func _use_damage_statuses(actor: Combatant, ability: AbilityData, targets: Array[int], events: Array[Dictionary]) -> void:
	if not _deals_damage(ability) or not ability.targets_enemies():
		return
	if actor.has_status(Status.EMPOWERED):
		_remove_status(actor, Status.EMPOWERED, events)
	for target_id: int in targets:
		var target := get_combatant(target_id)
		if not target.has_status(Status.MARKED):
			continue
		var entry: Dictionary = target.statuses[Status.MARKED]
		var left := int(entry.turns) - 1
		if left <= 0:
			_remove_status(target, Status.MARKED, events)
		else:
			entry.turns = left
			events.append(_status_event(target, Status.MARKED, true))


## Extra percent for a skill on one Marked enemy (Death Mark).
func _marked_bonus(ability: AbilityData, targets: Array[int]) -> int:
	if not _deals_damage(ability) or ability.target != AbilityData.Target.SINGLE_ENEMY or targets.size() != 1:
		return 0
	return tuning.marked_bonus_percent if get_combatant(targets[0]).has_status(Status.MARKED) else 0


## Extra percent for an Empowered striker's damaging skill (Shadowstep).
func _empowered_bonus(striker: Combatant, ability: AbilityData) -> int:
	if not _deals_damage(ability) or not ability.targets_enemies() or not striker.has_status(Status.EMPOWERED):
		return 0
	return tuning.empowered_bonus_percent


func _deals_damage(ability: AbilityData) -> bool:
	return ability.damage_percent > 0 or ability.press_damage_percent > 0 or ability.per_perfect_defense_percent > 0


## The single enemy target whose Exposed this ability will consume, or -1.
func _exposed_target(ability: AbilityData, targets: Array[int]) -> int:
	if ability.target != AbilityData.Target.SINGLE_ENEMY or not ability.consumes_exposed or not _deals_damage(ability):
		return -1
	if targets.size() != 1 or not get_combatant(targets[0]).has_status(Status.EXPOSED):
		return -1
	return targets[0]


func _exposed_bonus(striker: Combatant, ability: AbilityData, exposed: bool) -> int:
	if not exposed:
		return 0
	var bonus := ability.exposed_bonus_percent if ability.exposed_bonus_percent > 0 else tuning.exposed_bonus_percent
	return bonus + Passive.amount(striker, Passive.EXPOSED)


## Move percent of one hit: base, plus Payback's per-defence bonus, plus the press bonus.
func _skill_percent(striker: Combatant, ability: AbilityData, good: bool) -> int:
	var pct := ability.damage_percent + ability.per_perfect_defense_percent * striker.perfect_defenses
	if good:
		pct += ability.press_damage_percent + Passive.amount(striker, Passive.PERFECT_PRESS)
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
		# A party press or follow-up that will be a critical hit if it lands (rolled at declare time).
		"crit": false,
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
	var resolved := {
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
	}
	events.append(resolved)
	if downed:
		events.append({"type": "downed", "target": target.id})
		_on_downed(target, events)
	elif perfect and outcome == Defense.Outcome.JUMP and Passive.amount(target, Passive.HEAL_ON_JUMP) > 0:
		_heal(target, target, CombatMath.percent_min1(target.max_hp, Passive.amount(target, Passive.HEAL_ON_JUMP)), events)


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
		var crit := good and bool(prompt.get("crit", false))
		var targets: Array = sequence.targets
		# A follow-up strikes the skill's first target only.
		var struck: Array = [targets[0]] if follow_up and not targets.is_empty() else targets
		for target_id: int in struck:
			var target := get_combatant(target_id)
			if not target.is_party() and target.is_alive():
				_deal_damage(striker, target, amount, "follow_up" if follow_up else "ability", events, crit)
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
		_second_winds(events)
	sequence = {}
	_end_of_turn(source, events)
	events.append({"type": "turn_ended", "turn": turn_number, "actor": source.id})
	_advance_turn(events)


## Counter for every target who perfectly defended all of their prompts. If the attack was
## party-wide (or each hero in turn) and every target did, they strike together as one team counter.
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
		int(sequence.mode) != EnemyAttackData.TargetMode.SINGLE
		and targets.size() >= 2
		and counterers.size() == targets.size()
	)
	if team:
		var string := _string_of(-1)
		var total := 0
		var any_crit := false
		for actor_id: int in counterers:
			var actor := get_combatant(actor_id)
			var share := CombatMath.percent(actor.power, _counter_percent(actor, tuning.team_counter_percent, string))
			# Each hero's share can crit on its own.
			if _roll_crit(actor):
				share = CombatMath.percent(share, tuning.crit_damage_percent)
				any_crit = true
			total += share
		events.append({"type": "counter", "seq": sequence.seq, "actors": counterers.duplicate(), "target": attacker.id,
				"team": true, "hits": string.x, "mixed": string.y == 1})
		_deal_damage(get_combatant(counterers[0]), attacker, _apply_variance(maxi(1, total)), "team_counter", events,
				any_crit)
		for actor_id: int in counterers:
			_gear_ap_on_counter(get_combatant(actor_id), events)
		return
	for actor_id: int in counterers:
		if not attacker.is_alive():
			break
		var actor := get_combatant(actor_id)
		var string := _string_of(actor_id)
		events.append({"type": "counter", "seq": sequence.seq, "actors": [actor_id], "target": attacker.id, "team": false,
				"hits": string.x, "mixed": string.y == 1})
		var amount := _roll_damage(actor.power, _counter_percent(actor, tuning.counter_percent, string))
		var crit := _roll_crit(actor)
		_deal_damage(actor, attacker, _crit_damage(amount) if crit else amount, "counter", events, crit)
		_gear_ap_on_counter(actor, events)


## The counter percent (card #52): the base, plus counter_per_extra_hit_percent for each hit after
## the first, plus counter_mixed_bonus_percent for a string of parries and jumps, plus gear; then
## Riposte Stance multiplies it. string = Vector2i(hits, mixed 0/1) from _string_of.
func _counter_percent(actor: Combatant, base_percent: int, string: Vector2i) -> int:
	var pct := base_percent + tuning.counter_per_extra_hit_percent * maxi(0, string.x - 1)
	if string.y == 1:
		pct += tuning.counter_mixed_bonus_percent
	pct += Passive.amount(actor, Passive.COUNTER)
	if actor.has_status(Status.RIPOSTE):
		return CombatMath.percent(pct, tuning.riposte_counter_percent)
	return pct


## The string a counter answers: Vector2i(hits, 1 if it had both normal and ground hits else 0).
## For one character (character_id) its own prompts; -1 = the whole attack (team counter).
func _string_of(character_id: int) -> Vector2i:
	var hits := 0
	var normal := false
	var ground := false
	for prompt: Dictionary in sequence.prompts:
		if character_id >= 0 and int(prompt.character) != character_id:
			continue
		hits += 1
		# A rend is parried like a normal hit (a sweep never reaches a counter: it has no perfect answer).
		normal = normal or int(prompt.kind) == AttackHitData.Kind.NORMAL or int(prompt.kind) == AttackHitData.Kind.REND
		ground = ground or int(prompt.kind) == AttackHitData.Kind.GROUND
	if character_id < 0:
		hits = (sequence.hits as Array).size()
	return Vector2i(hits, 1 if normal and ground else 0)


func _gear_ap_on_counter(actor: Combatant, events: Array[Dictionary]) -> void:
	var gain := Passive.amount(actor, Passive.AP_ON_COUNTER)
	if gain > 0 and actor.is_alive():
		_change_ap(actor, gain, "gear", events)


## Second Wind gear: once per fight, a character downed during this enemy attack gets back up.
func _second_winds(events: Array[Dictionary]) -> void:
	for c: Combatant in combatants:
		var pct := Passive.amount(c, Passive.SECOND_WIND)
		if c.is_party() and not c.is_alive() and not c.escaped and pct > 0 and not c.second_wind_used:
			c.second_wind_used = true
			_revive(c, c, pct, events)


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
	amount = CombatMath.percent(amount, 100 + Passive.amount(source, Passive.HEAL))
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


## A party member's chance of a critical hit (DESIGN.md 8.2): the base plus Luck. Enemies never crit.
func crit_chance(c: Combatant) -> int:
	if not c.is_party():
		return 0
	return clampi(tuning.crit_base_percent + Passive.amount(c, Passive.CRIT), 0, 100)


## Rolls whether this hit of `striker` is a critical hit (no roll at 0%, so fights without crits
## keep their old random sequence).
func _roll_crit(striker: Combatant) -> bool:
	var chance := crit_chance(striker)
	if chance <= 0:
		return false
	return rng.range_int(0, 99) < chance


func _crit_damage(amount: int) -> int:
	return CombatMath.percent_min1(amount, tuning.crit_damage_percent)


## An enemy hit on a party member: power x hit percent, then Guard, then variance.
func _enemy_hit_damage(enemy: Combatant, target: Combatant, pct: int) -> int:
	var amount := CombatMath.percent_min1(enemy.power, pct)
	if target.has_status(Status.GUARDED):
		amount = CombatMath.percent_min1(amount, tuning.guard_damage_percent)
	var tough := mini(Passive.amount(target, Passive.TOUGH), tuning.tough_max_percent)
	if tough > 0:
		amount = CombatMath.percent_min1(amount, maxi(0, 100 - tough))
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


## `crit`: a critical hit (the amount already has the crit bonus; the event says so for the popup).
func _deal_damage(source: Combatant, target: Combatant, amount: int, cause: String, events: Array[Dictionary],
		crit: bool = false) -> void:
	_lose_hp(target, amount)
	events.append({
		"type": "damage",
		"source": source.id,
		"target": target.id,
		"amount": amount,
		"hp": target.hp,
		"max_hp": target.max_hp,
		"cause": cause,
		"crit": crit,
	})
	if not target.is_alive():
		events.append({"type": "downed", "target": target.id})
		_on_downed(target, events)
	elif not target.is_party():
		_maybe_enter_phase_two(target, events)


## A boss under its phase two HP changes attacks, speed and attack tempo, and picks a new intent.
func _maybe_enter_phase_two(enemy: Combatant, events: Array[Dictionary]) -> void:
	if enemy.phase != 1 or enemy.slot >= _setup.enemies.size():
		return
	var data := _setup.enemies[enemy.slot]
	if data.phase_two_hp_percent <= 0 or data.phase_two_attacks.is_empty():
		return
	if enemy.hp * 100 > enemy.max_hp * data.phase_two_hp_percent:
		return
	enemy.phase = 2
	enemy.attack_ids.clear()
	for attack: EnemyAttackData in data.phase_two_attacks:
		enemy.attack_ids.append(attack.id)
	if data.phase_two_tempo_percent > 0:
		# Its strings speed up (card #188), on top of the fight's tempo.
		enemy.tempo_percent = data.phase_two_tempo_percent
	if data.phase_two_speed > 0:
		enemy.base_speed = data.phase_two_speed
		# A slowed boss stays slowed: the slow is a share of its (new) normal speed.
		_set_speed(enemy, CombatMath.percent_min1(data.phase_two_speed, tuning.slow_speed_percent)
				if enemy.has_status(Status.SLOWED) else data.phase_two_speed)
	events.append({"type": "enemy_phase", "enemy": enemy.id, "phase": 2, "text": data.phase_two_text})
	_pick_intent(enemy, events)
	events.append({"type": "turn_order", "order": preview_turn_order(tuning.turn_order_preview)})


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
