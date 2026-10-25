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
##   practice         {invulnerable_party?, immortal_enemies?, force_attack?, mark_hero?, mark_status?}
##                    if setup allows
##   set_opening      {opening: "normal" | "first_strike", word}  phase AWAITING_OPENING (a Fight
##                    stop's First Strike ring, pressed in the fight after its intro, card #335)
##
## Events (Dictionary with "type"):
##   combat_started          {seed, fighters:[Combatant.to_dict()], practice_allowed, opening,
##                           items:[item_info()]} (backpack items usable in this fight)
##                           opening: "normal" | "first_strike" (DESIGN.md 2.12) | "ring" (the
##                           first turn waits for set_opening, card #335)
##   opening                 {opening, word} the First Strike ring's result (set_opening): First
##                           Strike applied or not; the first turn follows in the same batch
##   intent                  {enemy, attack, name, mode, targets:[id], kinds:[hit kind], times:[ms],
##                           feints:[bool] (which hits are feints, card #129), marks? (card #194),
##                           ranged?:[bool] (which hits are thrown, only when one is, card #278),
##                           support? (EnemyAttackData.Support of a heal or shield move, card #259),
##                           odds? {attacks:[[id, weight]], targets:[[hero, weight]]} (practice only)}
##                           what this enemy will do on its next turn (DESIGN.md 2.8). Sent at
##                           fight start, after its turn, and whenever its targets change.
##                           times: each hit's impact, ms after the attack starts (with
##                           attack_tempo_percent, like the declared hits' at_ms).
##                           A Charged Doom (card #195) adds charge_left (enemy turns until it
##                           unleashes), charge_total, charge_damage (taken since it was announced)
##                           and break_hp (the damage that breaks it).
##   turn_started            {turn, actor, team, time}
##   turn_order              {order:[id]}      current actor first, then upcoming turns
##   ability_used            {turn, actor, ability, targets:[id]}
##   item_used               {turn, actor, uid, item, name, targets:[id]} (DESIGN.md 8.1)
##   damage                  {source, target, amount, hp, max_hp, cause, crit (a critical hit)}
##                           cause: "ability" | "follow_up" | "counter" | "team_counter" | "bleed"
##                           | "item" | "rot" (gear) | "rotting" (the Rotting debuff) | "thorns" (gear)
##                           | "burning" (the Burning debuff, card #252)
##   healed                  {source, target, amount, hp, max_hp, cause? ("drain": a drinking hit healed
##                           its attacker, EnemyAttackData.drain_percent, card #323; only then)}
##   revived                 {source, target, hp, max_hp}
##   downed                  {target}
##   ap_changed              {character, delta, ap, reason}  reason: "spend" | "ability" | "given"
##                           | "gear" | "drain" (an enemy hit that drains AP, card #194)
##   status_changed          {target, status, active, turns, source}   see Status
##   turn_shifted            {target, delta}   a fighter's next turn moved (delta in timeline
##                           ticks: negative = sooner); a turn_order event follows
##   team_gauge              {value, delta, max}
##   defence_streak          {value, best, milestone, lost}   the party's perfect defences in a row
##                           (card #300): value after this defence (0: a hit ended it), best this
##                           fight, milestone (every tuning defence_streak_step: the gauge fills, a
##                           team_gauge event follows), lost (the streak a hit just ended, else 0)
##   timed_sequence_declared {seq, kind, source, action, name, mode, targets:[id],
##                            alert_cue, allow_timing_ring, hits:[hit], prompts:[prompt]}
##       hit    = {index, at_ms, kind, approach_ms, feint, damage_percent, impact_sfx,
##                 mark (only on a hit that marks, card #194: a hero debuff id or Status.MARK_AP_DRAIN)}
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
##   doom_charging           {enemy, attack, name, left, total, damage, break_hp}   the enemy spent its
##                           turn gathering a Doom (card #195); left > 0 turns remain
##   doom_progress           {enemy, attack, damage, break_hp}   the party took more HP off a gathering
##                           enemy, short of the break
##   doom_broken             {enemy, attack, name, damage, break_hp, stagger_turns}   the party dealt
##                           break_hp while the Doom was announced: it is cancelled and the enemy
##                           staggered (a stagger_changed and a new intent follow)
##   doom_unleashed          {enemy, attack, name}   the countdown ran out; the Doom strikes (its
##                           timed_sequence_declared follows)
##   stagger_changed         {enemy, turns, lost_turn}   the enemy is staggered for turns more of its
##                           turns (it takes extra damage; damage events carry staggered: true);
##                           lost_turn: it just lost one; turns 0: the stagger is over
##   enemy_phase             {enemy, phase, text}   a boss dropped under its phase two HP: new
##                           attacks, speed and attack tempo (an intent and turn_order follow)
##   turn_ended              {turn, actor}
##   practice_changed        {invulnerable_party, immortal_enemies, force_attack}
##                           also emitted (before timed_sequence_declared) when a forced
##                           attack is used and force_attack clears
##   turn_lost               {actor, status}   a Dazed hero's turn passes (card #252)
##   enemy_support           {enemy, attack, name, target, support}   a monster healed or shielded a fellow
##                           monster instead of striking (card #259; healed / status_changed follow)
##   self_destructed         {enemy, attack}   the attacker spent itself (a Pus Tick's Burst, card #260);
##                           a downed event follows
##   escaped                 {character}     that hero ran from the fight (Run, DESIGN.md 2.13)
##   combat_ended            {result}        "victory" | "defeat" | "escaped" (every hero still
##                                           standing ran, DESIGN.md 2.13)
##   command_rejected        {reason, command}   private to the sender; never broadcast/replayed

## combat_started "opening" names, by CombatSetup.Opening.
const OPENING_NAMES: Array[String] = ["normal", "first_strike", "ring"]

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
	## A Fight stop's fight before its first turn (CombatSetup.Opening.RING, card #335): the First
	## Strike ring's result comes as set_opening.
	AWAITING_OPENING,
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
## A healed event's cause when a drinking hit healed its attacker (card #323).
const CAUSE_DRAIN := "drain"

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
## The party's perfect parries and jumps in a row across the fight (card #300), and the best run.
var defence_streak: int = 0
var best_defence_streak: int = 0
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
## The enemy that just lost a turn to a stagger: its announced intent stays (set and used within
## one submit, so it is not part of snapshots).
var _keep_intent: int = -1
## Backpack items not used yet (uids, DESIGN.md 8.1).
var items_left: Array[int] = []

var _setup: CombatSetup
var _abilities: Dictionary = {}
var _attacks: Dictionary = {}
## uid -> ItemData for the fight's items, their amounts (the setup's, normally the item's own) and names.
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
	for id: int in party_ids():
		var hero := get_combatant(id)
		var ward := Passive.amount(hero, Passive.WARD_START)
		if ward > 0:
			# Relics against marks (card #263): the fight opens with the hero Warded.
			_add_status(hero, Status.WARDED, ward, hero.id, events)
		if Passive.amount(hero, Passive.START_EMPOWERED) > 0:
			# Phase 20 Relics (card #242): the first damaging skill of the fight hits harder.
			_add_status(hero, Status.EMPOWERED, 1, hero.id, events)
		var regen := Passive.amount(hero, Passive.START_REGEN)
		if regen > 0:
			_add_status(hero, Status.REGEN, regen, hero.id, events)
	for enemy_id: int in enemy_ids():
		_pick_intent(get_combatant(enemy_id), events)
	if _setup.opening == CombatSetup.Opening.RING:
		# The First Strike ring is pressed in the fight, after its intro (card #335): the first turn
		# waits for its result.
		phase = Phase.AWAITING_OPENING
		return events
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
		CombatCommands.SET_OPENING:
			_cmd_set_opening(command, events)
		_:
			events.append(_reject("unknown_command", command))
	return events


## The First Strike ring's result (card #335): First Strike or a normal start, then the first turn.
## Only while the fight waits for it (AWAITING_OPENING), and only those two openings.
func _cmd_set_opening(command: Dictionary, events: Array[Dictionary]) -> void:
	if phase != Phase.AWAITING_OPENING:
		events.append(_reject("not_awaiting_opening", command))
		return
	var opening := OPENING_NAMES.find(String(command.get("opening", "")))
	if opening != CombatSetup.Opening.NORMAL and opening != CombatSetup.Opening.FIRST_STRIKE:
		events.append(_reject("bad_opening", command))
		return
	if opening == CombatSetup.Opening.FIRST_STRIKE:
		_apply_first_strike()
	var word: Variant = command.get("word", "")
	events.append({"type": "opening", "opening": OPENING_NAMES[opening],
			"word": String(word) if word is String else ""})
	_advance_turn(events)


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
	engine.defence_streak = int(snap.get("defence_streak", 0))
	engine.best_defence_streak = int(snap.get("best_defence_streak", 0))
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
	if is_hushed_out(actor_id, ability_id):
		return false
	return not valid_targets(actor_id, ability_id).is_empty()


## True if a Hushed hero may not use this ability now (card #252): every skill is out; the basic
## attack, Run and the team ultimate stay.
func is_hushed_out(actor_id: int, ability_id: String) -> bool:
	var actor := get_combatant(actor_id)
	var ability := get_ability(ability_id)
	if actor == null or ability == null or not actor.is_party() or not actor.has_status(Status.HUSHED):
		return false
	if ability.escape or ability.team_ultimate:
		return false
	var data: CharacterData = _setup.party[actor.slot] if actor.slot < _setup.party.size() else null
	return data == null or data.basic_attack == null or ability.id != data.basic_attack.id


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


## A fight item as plain data: {uid, id, name, description, ap_cost, target, cleanse} (target: ITEM_ALLY,
## ITEM_PARTY, ITEM_ENEMIES or ITEM_DOWNED). Empty if the uid is not one of the fight's items.
func item_info(uid: int) -> Dictionary:
	var item := _items.get(uid) as ItemData
	if item == null:
		return {}
	return {"uid": uid, "id": item.id, "name": String(_item_names.get(uid, item.display_name)), "description": item.description,
			"ap_cost": item.ap_cost, "target": item_target(item), "cleanse": item.cleanse_count}


## Who an item is used on.
static func item_target(item: ItemData) -> String:
	match item.effect:
		ItemData.Effect.HEAL_ONE, ItemData.Effect.CLEANSE_ONE:
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


## The fight as it stands, as the events a machine that missed it plays to catch up (an online
## player who rejoined mid-fight, DESIGN.md 9.2, card #205): combat_started with every fighter as
## they are now (and "resume": true), the practice options, the team gauge, every enemy's intent,
## the turn order, and the turn that waits for a choice (or the end). Only between sequences
## (AWAITING_ACTION or ENDED; empty otherwise, never mid-attack). Changes nothing, so the engine's
## own events and their order are the same with or without a rejoin.
func resume_events() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if phase != Phase.AWAITING_ACTION and phase != Phase.ENDED:
		return events
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
		"opening": OPENING_NAMES[CombatSetup.Opening.NORMAL],
		"items": item_list,
		"resume": true,
	})
	var p := practice.duplicate(true)
	p["type"] = "practice_changed"
	events.append(p)
	events.append({"type": "team_gauge", "value": team_gauge, "delta": 0, "max": tuning.team_gauge_max})
	events.append({"type": "defence_streak", "value": defence_streak, "best": best_defence_streak,
			"milestone": false, "lost": 0})
	for enemy_id: int in living_enemy_ids():
		if intents.has(enemy_id) and get_attack(String((intents[enemy_id] as Dictionary).attack)) != null:
			events.append(_intent_event(enemy_id))
	if phase == Phase.ENDED:
		events.append({"type": "combat_ended", "result": result})
		return events
	events.append({"type": "turn_order", "order": preview_turn_order(tuning.turn_order_preview)})
	var actor := get_combatant(active_actor)
	if actor != null:
		events.append({"type": "turn_started", "turn": turn_number, "actor": actor.id, "team": actor.team,
				"time": time_now})
	return events


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
		"defence_streak": defence_streak,
		"best_defence_streak": best_defence_streak,
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
			if attack.start_cooldown_turns > 0:
				# A Doom never opens the fight (card #195).
				c.attack_cooldowns[attack.id] = attack.start_cooldown_turns
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
		if actor.is_alive() and not held and actor.has_status(Status.DAZED):
			# Dazed (card #252): this turn passes; its end takes the daze away.
			events.append({"type": "turn_lost", "actor": actor.id, "status": Status.DAZED})
			held = true
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


## Statuses that last until the holder's next turn end now; a hero of a cursed party (passive rot)
## loses some HP (never below 1).
func _start_of_turn(actor: Combatant, events: Array[Dictionary]) -> void:
	for id: String in Status.ALL:
		if Status.ends_at_own_turn(id) and actor.has_status(id):
			_remove_status(actor, id, events)
	var rot := Passive.amount(actor, Passive.ROT)
	if rot > 0 and actor.is_alive():
		var amount := mini(CombatMath.percent_min1(actor.max_hp, rot), actor.hp - 1)
		if amount > 0:
			_deal_damage(actor, actor, amount, "rot", events)
	if actor.has_status(Status.ROTTING) and actor.is_alive():
		var rotted := mini(CombatMath.percent_min1(actor.max_hp, tuning.rotting_percent), actor.hp - 1)
		if rotted > 0:
			_deal_damage(actor, actor, rotted, "rotting", events)
	if actor.has_status(Status.BURNING) and actor.is_alive():
		var burned := mini(CombatMath.percent_min1(actor.max_hp, tuning.burning_percent), actor.hp - 1)
		if burned > 0:
			_deal_damage(actor, actor, burned, "burning", events)
	if actor.has_status(Status.BLEEDING) and actor.is_alive():
		var source := get_combatant(int((actor.statuses[Status.BLEEDING] as Dictionary).source))
		var power := _power_of(source) if source != null else 1
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
		if _keep_intent == actor.id:
			# It lost its turn to a stagger: what it announced still stands.
			_keep_intent = -1
		else:
			_pick_intent(actor, events)


## Declares the enemy's intended attack as a timed sequence. Returns false if it has none.
func _begin_enemy_attack(actor: Combatant, events: Array[Dictionary]) -> bool:
	if actor.staggered_turns > 0:
		_lose_staggered_turn(actor, events)
		return false
	actor.tick_cooldowns()
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
	if attack != null and attack.is_doom():
		# Charged Doom (card #195): every turn up to the last is spent gathering.
		_arm_charge(actor, attack)
		actor.charge_left -= 1
		if actor.charge_left > 0:
			events.append(_doom_event("doom_charging", actor, attack))
			return false
		actor.clear_charge()
		events.append({"type": "doom_unleashed", "enemy": actor.id, "attack": attack.id, "name": attack.display_name})
	elif actor.charge_left > 0:
		# Something else was forced over the Doom (practice): the charge is dropped.
		actor.clear_charge()
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
	actor.note_attack(attack.id, attack.cooldown_turns,
			targets[0] if attack.target_mode == EnemyAttackData.TargetMode.SINGLE else -1)
	if attack.is_support():
		_use_support(actor, attack, get_combatant(targets[0]), events)
		return false

	var hits: Array[Dictionary] = []
	var prompts: Array[Dictionary] = []
	var tempo := _tempo_percent(actor)
	var hard := _forced_hits(actor)
	var allowed := _setup.allow_marks
	for hit_index: int in attack.hits.size():
		var hit: AttackHitData = attack.hits[hit_index]
		var at_ms := CombatMath.percent(hit.impact_ms, tempo)
		var kind := hit.kind_in(hard)
		var declared := {
			"index": hit_index,
			"at_ms": at_ms,
			"kind": kind,
			"approach_ms": CombatMath.percent(hit.approach_ms, tempo),
			"feint": hit.feint_in(hard),
			"damage_percent": hit.damage_percent,
			"impact_sfx": hit.impact_sfx,
		}
		var marks := hit.marks_in(hard, allowed)
		if marks:
			declared["mark"] = hit.mark_id_in(hard, allowed)
		hits.append(declared)
		# Each hero in turn: hit i strikes only its own target (DESIGN.md 3.11).
		var hit_targets: Array[int] = targets
		if attack.target_mode == EnemyAttackData.TargetMode.EACH:
			hit_targets = [targets[hit_index % targets.size()]]
		for target_id: int in hit_targets:
			var defend := _prompt(prompts.size(), hit_index, target_id, at_ms, kind,
					_windows_for(get_combatant(target_id), Defense.build_windows(kind, tuning)),
					_enemy_hit_damage(actor, get_combatant(target_id), hit.damage_percent), 0, 0, ROLE_DEFEND, [])
			if marks:
				# Only a marking hit carries these, so every other fight's events stay as they were.
				defend["mark_status"] = hit.on_hit_status
				defend["mark_turns"] = hit.on_hit_status_turns
				defend["mark_ap"] = hit.on_hit_ap_drain
			if attack.drains():
				# A drinking bite (card #323); only its prompts carry it, like a mark.
				defend["drain"] = attack.drain_percent
			prompts.append(defend)
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
	if enemy.charge_left > 0:
		# Gathering a Doom: the announced intent stays until it unleashes or is broken.
		return
	var intent := _choose_intent(enemy)
	if intent.is_empty():
		intents.erase(enemy.id)
		return
	intents[enemy.id] = intent
	_arm_charge(enemy, get_attack(String(intent.attack)))
	events.append(_intent_event(enemy.id))


func _choose_intent(enemy: Combatant) -> Dictionary:
	var staged := String(stage.attack)
	if not staged.is_empty() and enemy.attack_ids.has(staged):
		return {"attack": staged, "targets": _pick_targets(enemy, get_attack(staged))}
	var candidates: Array[EnemyAttackData] = []
	for attack_id: String in enemy.attack_ids:
		var candidate := get_attack(attack_id)
		if candidate == null or candidate.weight <= 0:
			continue
		if candidate.is_support():
			# A support move with nobody to help is never a choice, not even the fallback (card #259).
			if _support_target(enemy, candidate) >= 0:
				candidates.append(candidate)
		elif not candidate.hits.is_empty():
			candidates.append(candidate)
	# Skip moves that are on cooldown or have been used max_in_a_row times running, unless that
	# leaves nothing to pick from (an enemy with a single move keeps using it).
	var choices: Array[EnemyAttackData] = []
	for candidate: EnemyAttackData in candidates:
		if _attack_usable(enemy, candidate):
			choices.append(candidate)
	if choices.is_empty():
		choices = candidates
	var weights: Array[int] = []
	for candidate: EnemyAttackData in choices:
		weights.append(_attack_weight(enemy, candidate))
	var pick := rng.pick_weighted(weights)
	if pick < 0:
		return {}
	var intent := {"attack": choices[pick].id, "targets": _pick_targets(enemy, choices[pick])}
	if _setup.allow_practice:
		# Practice shows the odds behind the pick, so the weights can be tuned by eye. Not rules.
		var attack_odds: Array = []
		for i: int in choices.size():
			attack_odds.append([choices[i].id, weights[i]])
		var target_odds: Array = []
		if choices[pick].target_mode == EnemyAttackData.TargetMode.SINGLE:
			var living := living_party_ids()
			var target_weights := _target_weights(enemy, living)
			for i: int in living.size():
				target_odds.append([living[i], target_weights[i]])
		intent["odds"] = {"attacks": attack_odds, "targets": target_odds}
	return intent


## False while the move is on cooldown or the enemy has just used it max_in_a_row times running.
func _attack_usable(enemy: Combatant, attack: EnemyAttackData) -> bool:
	if int(enemy.attack_cooldowns.get(attack.id, 0)) > 0:
		return false
	return attack.max_in_a_row <= 0 or enemy.repeat_run(attack.id) < attack.max_in_a_row


## The move's base weight, scaled by the situation: a finisher when a hero is nearly down, a
## desperate move when the enemy itself is. Never below 1 so a pick always exists.
func _attack_weight(enemy: Combatant, attack: EnemyAttackData) -> int:
	var weight := attack.weight
	if attack.finisher_below_percent > 0 and attack.finisher_weight_percent != 100:
		for id: int in living_party_ids():
			var hero := get_combatant(id)
			if hero.hp * 100 <= hero.max_hp * attack.finisher_below_percent:
				weight = CombatMath.percent_min1(weight, attack.finisher_weight_percent)
				break
	if attack.low_hp_below_percent > 0 and attack.low_hp_weight_percent != 100 			and enemy.hp * 100 <= enemy.max_hp * attack.low_hp_below_percent:
		weight = CombatMath.percent_min1(weight, attack.low_hp_weight_percent)
	return weight


## Whole party for party-wide attacks; standing heroes in party order from a random one on for
## each-in-turn attacks (one per hit at most); otherwise the taunter if one is standing, else a
## standing hero chosen by the enemy's target rule (EnemyData.TargetRule, DESIGN.md 2.3).
func _pick_targets(enemy: Combatant, attack: EnemyAttackData) -> Array[int]:
	var living := living_party_ids()
	var targets: Array[int] = []
	if attack != null and attack.target_mode == EnemyAttackData.TargetMode.ALLY:
		var ally := _support_target(enemy, attack)
		if ally >= 0:
			targets.append(ally)
		return targets
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
		var data := _enemy_data(enemy)
		if data == null or data.target_rule == EnemyData.TargetRule.RANDOM or living.size() == 1:
			targets.append(living[rng.range_int(0, living.size() - 1)])
		else:
			targets.append(living[rng.pick_weighted(_target_weights(enemy, living))])
	return targets


## Chance (as integer weights) of each standing hero being hit by this enemy's single-target
## attack. Every hero keeps at least 100, so nobody is ever safe and nothing is a sure thing.
func _target_weights(enemy: Combatant, living: Array[int]) -> Array[int]:
	var weights: Array[int] = []
	var data := _enemy_data(enemy)
	var rule := data.target_rule if data != null else EnemyData.TargetRule.RANDOM
	var bias := data.target_bias_percent if data != null else 0
	var lowest_hp := 0
	for id: int in living:
		var hp := get_combatant(id).hp
		lowest_hp = hp if lowest_hp == 0 else mini(lowest_hp, hp)
	var lowest_taken := false
	for id: int in living:
		var hero := get_combatant(id)
		var weight := 100
		match rule:
			EnemyData.TargetRule.WOUNDED:
				weight += CombatMath.percent(_missing_hp_percent(hero), bias)
			EnemyData.TargetRule.LOWEST_HP:
				# One hero only, even on a tie: the first in party order.
				if hero.hp == lowest_hp and not lowest_taken:
					lowest_taken = true
					weight += bias
			EnemyData.TargetRule.MARKED:
				if hero.has_status(Status.EXPOSED) or hero.has_status(Status.MARKED):
					weight += bias
			EnemyData.TargetRule.AVOID_LAST:
				if id != enemy.last_target:
					weight += bias
		weights.append(weight)
	return weights


## Share of max HP a fighter is missing, 0 to 100 (rounded down).
@warning_ignore("integer_division")
func _missing_hp_percent(c: Combatant) -> int:
	return (c.max_hp - c.hp) * 100 / maxi(1, c.max_hp)


func _enemy_data(enemy: Combatant) -> EnemyData:
	if enemy.is_party() or enemy.slot >= _setup.enemies.size():
		return null
	return _setup.enemies[enemy.slot]


func _taunter_of(enemy: Combatant) -> int:
	if not enemy.has_status(Status.TAUNTED):
		return -1
	var source := get_combatant(int((enemy.statuses[Status.TAUNTED] as Dictionary).source))
	return source.id if source != null and source.is_alive() else -1


func _targets_still_valid(enemy: Combatant, attack: EnemyAttackData, targets: Array[int]) -> bool:
	if attack.target_mode == EnemyAttackData.TargetMode.ALLY:
		if targets.size() != 1:
			return false
		var ally := get_combatant(targets[0])
		return ally != null and ally.is_alive() and not ally.is_party()
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
	var marks: Array[String] = []
	var any_mark := false
	var ranged: Array[bool] = []
	var any_ranged := false
	var enemy := get_combatant(enemy_id)
	var tempo := _tempo_percent(enemy)
	var hard := _forced_hits(enemy)
	var allowed := _setup.allow_marks
	for hit: AttackHitData in attack.hits:
		kinds.append(hit.kind_in(hard))
		times.append(CombatMath.percent(hit.impact_ms, tempo))
		feints.append(hit.feint_in(hard))
		marks.append(hit.mark_id_in(hard, allowed))
		any_mark = any_mark or hit.marks_in(hard, allowed)
		var thrown := hit.ranged_in(hard)
		ranged.append(thrown)
		any_ranged = any_ranged or thrown
	var targets: Array[int] = []
	targets.assign(intent.targets)
	var event := {
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
	if any_mark:
		# Honest intent (card #194): which hits leave a mark, "" for a plain one. Only when one does.
		event["marks"] = marks
	if any_ranged:
		# Which hits are thrown (card #278), so the intent shows their own icon. Only when one is.
		event["ranged"] = ranged
	if attack.is_support():
		# A heal or a shield for a fellow monster (card #259): targets holds that monster.
		event["support"] = attack.support
	if attack.is_doom():
		var charging := enemy.charge_attack == attack.id
		event["charge_left"] = enemy.charge_left if charging else attack.charge_turns
		event["charge_total"] = attack.charge_turns
		event["charge_damage"] = enemy.charge_damage if charging else 0
		event["break_hp"] = _break_hp(enemy, attack)
	if intent.has("odds"):
		event["odds"] = (intent.odds as Dictionary).duplicate(true)
	return event


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
	if is_hushed_out(actor.id, ability.id):
		events.append(_reject("hushed", command))
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
				var amount := _skill_damage(_power_of(actor), pct, bonus)
				_deal_damage(actor, target, _crit_damage(actor, amount) if crit else amount, "ability", events, crit)
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
					_cleanse(target, item.cleanse_count, events)
					_heal(actor, target, CombatMath.percent_min1(target.max_hp, pct), events)
			ItemData.Effect.CLEANSE_ONE, ItemData.Effect.CLEANSE_ALL:
				# Antidote, Holy Water (card #254): the marks go first, then the small heal if any.
				if target.is_alive():
					_cleanse(target, item.cleanse_count, events)
					if pct > 0:
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
	var marked := get_combatant(int(command.get("mark_hero", -1)))
	if marked != null and marked.is_party() and marked.is_alive() and Status.is_debuff(String(command.get("mark_status", ""))):
		# The tutorial's marks lesson (card #264): a mark for the healer to lift.
		_add_status(marked, String(command.mark_status), 3, -1, events)
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
			_arm_charge(c, get_attack(forced))
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
			_arm_charge(c, get_attack(staged))
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
				good = _skill_damage(_power_of(striker), _skill_percent(striker, ability, false), bonus)
				perfect = _skill_damage(_power_of(striker), _skill_percent(striker, ability, true), bonus)
				miss = CombatMath.percent(good, tuning.skill_miss_damage_percent)
				# Rolled now with the damage, so it is in the declared event (DESIGN.md 8.2); a missed
				# press never crits.
				crit = _roll_crit(striker)
				if crit:
					good = _crit_damage(striker, good)
					perfect = _crit_damage(striker, perfect)
			press_idxs.append(prompts.size())
			var press := _prompt(prompts.size(), hit_index, striker_id, at_ms, AttackHitData.Kind.PRESS,
					_windows_for(striker, Defense.build_windows(AttackHitData.Kind.PRESS, tuning, ability.perfect_window_percent)),
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
			var good := _roll_damage(_power_of(ally), tuning.follow_up_percent)
			var perfect := _roll_damage(_power_of(ally), tuning.follow_up_perfect_percent)
			var crit := _roll_crit(ally)
			var follow := _prompt(prompts.size(), hit_index, ally_id, at_ms, AttackHitData.Kind.PRESS,
					_windows_for(ally, Defense.build_follow_up_windows(tuning)), 0, _crit_damage(ally, good) if crit else good,
					_crit_damage(ally, perfect) if crit else perfect, ROLE_FOLLOW_UP, press_idxs)
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
			# The cleanse comes first, so lifting Blighted frees this very heal (Purify cleanses alone).
			var cleanse := ability.cleanse_count + (ability.press_cleanse_count if good else 0)
			if cleanse > 0:
				var was_slowed := target.has_status(Status.SLOWED)
				_cleanse(target, cleanse, events)
				timeline_changed = timeline_changed or (was_slowed and not target.has_status(Status.SLOWED))
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
		_change_gauge(_gauge_gain(actor, ability.gauge_gain), events)
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
	var lost := 0
	var ap_delta := 0
	var perfect := (prompt.perfect as Array).has(outcome)
	if outcome != Defense.Outcome.NONE:
		ap_delta = _change_ap_silent(target, _defence_ap(target, outcome))
		if perfect:
			target.perfect_defenses += 1
	else:
		damage = int(prompt.damage)
		lost = _lose_hp(target, damage)
	var downed := not target.is_alive()
	var thorn_events: Array[Dictionary] = []
	if damage > 0:
		_reflect_thorns(target, damage, thorn_events)
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
	events.append_array(thorn_events)
	_drink(prompt, lost, events)
	_count_streak(outcome, perfect, events)
	if downed:
		events.append({"type": "downed", "target": target.id})
		_on_downed(target, events)
	elif perfect and outcome == Defense.Outcome.JUMP and Passive.amount(target, Passive.HEAL_ON_JUMP) > 0:
		_heal(target, target, CombatMath.percent_min1(target.max_hp, Passive.amount(target, Passive.HEAL_ON_JUMP)), events)
	if not downed and perfect and outcome == Defense.Outcome.PARRY and Passive.amount(target, Passive.PARRY_HEAL) > 0:
		_heal(target, target, CombatMath.percent_min1(target.max_hp, Passive.amount(target, Passive.PARRY_HEAL)), events)
	if not downed and outcome == Defense.Outcome.PARRY and Passive.amount(target, Passive.PARRY_CLEANSE) > 0:
		# Relics against marks (card #263): a parry shakes marks off.
		if _cleanse(target, Passive.amount(target, Passive.PARRY_CLEANSE), events) > 0:
			events.append({"type": "turn_order", "order": preview_turn_order(tuning.turn_order_preview)})
	if not downed and outcome == Defense.Outcome.NONE:
		_apply_hit_marks(target, prompt, events)


## The defence streak (card #300): a perfect parry or jump adds one, a dodge keeps it, a hit taken
## ends it. Every tuning defence_streak_step in a row fills the team gauge. Counted here, from the
## resolved outcomes, so every machine online counts the same streak and pays the same gauge.
func _count_streak(outcome: int, perfect: bool, events: Array[Dictionary]) -> void:
	if perfect:
		defence_streak += 1
		best_defence_streak = maxi(best_defence_streak, defence_streak)
		var milestone := defence_streak % maxi(1, tuning.defence_streak_step) == 0
		events.append({"type": "defence_streak", "value": defence_streak, "best": best_defence_streak,
				"milestone": milestone, "lost": 0})
		if milestone and tuning.defence_streak_gauge > 0:
			_change_gauge(tuning.defence_streak_gauge, events)
	elif outcome == Defense.Outcome.NONE and defence_streak > 0:
		var lost := defence_streak
		defence_streak = 0
		events.append({"type": "defence_streak", "value": 0, "best": best_defence_streak,
				"milestone": false, "lost": lost})


## AP a successful defence earns: the tuned reward plus rot-touched gear (DESIGN.md 8.16), never below 0.
func _defence_ap(target: Combatant, outcome: int) -> int:
	var reward := Defense.ap_reward(outcome, tuning)
	if outcome == Defense.Outcome.DODGE:
		reward += Passive.amount(target, Passive.DODGE_AP)
	elif outcome == Defense.Outcome.PARRY:
		reward += Passive.amount(target, Passive.PARRY_AP)
	return maxi(0, reward)


## Thorned gear: the enemy whose hit landed on `target` takes a share of the damage back.
func _reflect_thorns(target: Combatant, damage: int, events: Array[Dictionary]) -> void:
	var pct := Passive.amount(target, Passive.THORNS)
	if pct <= 0 or sequence.is_empty():
		return
	var attacker := get_combatant(int(sequence.source))
	if attacker == null or attacker.is_party() or not attacker.is_alive():
		return
	_deal_damage(target, attacker, CombatMath.percent_min1(damage, pct), "thorns", events)


## A drinking hit (EnemyAttackData.drain_percent, card #323): the attacker heals that percent of the
## HP the hit took from the hero (at least 1). Nothing when the hit was defended, when the attacker
## is down (thorns may have killed it a moment ago) or already at full HP.
func _drink(prompt: Dictionary, lost: int, events: Array[Dictionary]) -> void:
	var pct := int(prompt.get("drain", 0))
	if pct <= 0 or lost <= 0 or sequence.is_empty():
		return
	var attacker := get_combatant(int(sequence.source))
	if attacker == null or attacker.is_party() or not attacker.is_alive() or attacker.hp >= attacker.max_hp:
		return
	_heal(attacker, attacker, CombatMath.percent_min1(lost, pct), events, CAUSE_DRAIN)


## The mark a hit leaves on a hero who took it undefended and is still standing (card #194): a
## debuff (refreshing its turns if the hero already has it) and/or an AP drain. A hero downed by the
## hit, or one who defended it, gets nothing.
func _apply_hit_marks(target: Combatant, prompt: Dictionary, events: Array[Dictionary]) -> void:
	if target.has_status(Status.WARDED):
		# Purify's ward (card #254): no mark gets through while it lasts.
		return
	var id := String(prompt.get("mark_status", ""))
	if Status.is_debuff(id):
		# Relics against marks (card #263) shorten them, never under one turn.
		var turns := maxi(1, int(prompt.get("mark_turns", 1)) - Passive.amount(target, Passive.MARK_SHORTEN))
		if _add_status(target, id, turns, int(sequence.source), events):
			# A Slow moved the hero's next turn.
			events.append({"type": "turn_order", "order": preview_turn_order(tuning.turn_order_preview)})
	var drain := int(prompt.get("mark_ap", 0))
	if drain > 0:
		_change_ap(target, -drain, "drain", events)


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
		_change_gauge(_gauge_gain(striker, tuning.team_gauge_per_follow_up), events)


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
		var used := get_attack(String(sequence.action))
		if used != null and used.self_destruct and source.is_alive():
			# A Pus Tick's Burst (card #260) spends the tick.
			events.append({"type": "self_destructed", "enemy": source.id, "attack": used.id})
			source.hp = 0
			events.append({"type": "downed", "target": source.id})
			_on_downed(source, events)
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
			var share := CombatMath.percent(_power_of(actor), _counter_percent(actor, tuning.team_counter_percent, string))
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
		var amount := _roll_damage(_power_of(actor), _counter_percent(actor, tuning.counter_percent, string))
		var crit := _roll_crit(actor)
		_deal_damage(actor, attacker, _crit_damage(actor, amount) if crit else amount, "counter", events, crit)
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

## A prompt's windows for `c`: a Shocked hero's are shocked_window_percent of their size (card #252).
func _windows_for(c: Combatant, windows: Dictionary) -> Dictionary:
	if c == null or not c.has_status(Status.SHOCKED):
		return windows
	var shrunk: Dictionary = {}
	for outcome: Variant in windows:
		var edges: Array = windows[outcome]
		shrunk[outcome] = [mini(-1, CombatMath.percent(int(edges[0]), tuning.shocked_window_percent)),
				maxi(1, CombatMath.percent(int(edges[1]), tuning.shocked_window_percent))]
	return shrunk


## The fellow monster a support move would help (card #259), or -1 when nobody needs it: the most
## wounded standing monster at or under support_below_percent for a heal, the most wounded one with
## no shield for a shield (itself included). Ties go to the lower id.
func _support_target(enemy: Combatant, attack: EnemyAttackData) -> int:
	var best := -1
	var best_missing := -1
	for id: int in living_enemy_ids():
		var c := get_combatant(id)
		match attack.support:
			EnemyAttackData.Support.HEAL:
				if c.hp * 100 > c.max_hp * attack.support_below_percent:
					continue
			EnemyAttackData.Support.SHIELD:
				if c.has_status(Status.SHIELDED):
					continue
			_:
				continue
		var missing := _missing_hp_percent(c)
		if missing > best_missing:
			best = id
			best_missing = missing
	return best


## A monster helps a fellow monster instead of striking: a heal or a shield (card #259).
func _use_support(actor: Combatant, attack: EnemyAttackData, target: Combatant, events: Array[Dictionary]) -> void:
	if target == null or not target.is_alive():
		return
	events.append({"type": "enemy_support", "enemy": actor.id, "attack": attack.id, "name": attack.display_name,
			"target": target.id, "support": attack.support})
	match attack.support:
		EnemyAttackData.Support.HEAL:
			_heal(actor, target, CombatMath.percent_min1(target.max_hp, attack.support_percent), events)
		EnemyAttackData.Support.SHIELD:
			_add_status(target, Status.SHIELDED, maxi(1, attack.support_turns), actor.id, events)


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


## `cause`: "" for an ordinary heal; CAUSE_DRAIN for a drinking hit (only then the event says so).
func _heal(source: Combatant, target: Combatant, amount: int, events: Array[Dictionary], cause: String = "") -> void:
	amount = CombatMath.percent(amount, maxi(0, 100 + Passive.amount(source, Passive.HEAL)))
	amount = CombatMath.percent(amount, maxi(0, 100 + Passive.amount(target, Passive.HEAL_TAKEN)))
	if target.has_status(Status.BLIGHTED) and amount > 0:
		amount = CombatMath.percent_min1(amount, maxi(0, 100 - tuning.blighted_heal_cut_percent))
	var before := target.hp
	target.hp = mini(target.max_hp, target.hp + amount)
	var event := {"type": "healed", "source": source.id, "target": target.id, "amount": target.hp - before,
			"hp": target.hp, "max_hp": target.max_hp}
	if not cause.is_empty():
		event["cause"] = cause
	events.append(event)


## A fighter's power with Weakened applied (card #194).
func _power_of(c: Combatant) -> int:
	var power := c.power
	var ember := Passive.amount(c, Passive.LOW_HP_POWER)
	if ember > 0 and c.is_alive() and c.hp * 100 < c.max_hp * tuning.rot_low_hp_percent:
		power = CombatMath.percent_min1(power, 100 + ember)
	var brim := Passive.amount(c, Passive.FULL_HP_POWER)
	if brim > 0 and c.is_alive() and c.hp >= c.max_hp:
		power = CombatMath.percent_min1(power, 100 + brim)
	if c.has_status(Status.WEAKENED):
		return CombatMath.percent_min1(power, maxi(0, 100 - tuning.weakened_power_cut_percent))
	return power


## Removes up to `count` hero debuffs from `target`, in Status.DEBUFFS order. Returns how many went.
func _cleanse(target: Combatant, count: int, events: Array[Dictionary]) -> int:
	var removed := 0
	for id: String in Status.DEBUFFS:
		if removed >= count:
			break
		if target.has_status(id):
			_remove_status(target, id, events)
			removed += 1
	return removed


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
		target.clear_charge()
		target.staggered_turns = 0
		# A fellow monster's heal or shield aimed at it looks for someone else (card #259).
		_refresh_intents(events)
		return
	for enemy_id: int in living_enemy_ids():
		var enemy := get_combatant(enemy_id)
		if enemy.has_status(Status.TAUNTED) and int((enemy.statuses[Status.TAUNTED] as Dictionary).source) == target.id:
			_remove_status(enemy, Status.TAUNTED, events)
	_refresh_intents(events)


## Team gauge `amount` earned by `source`, bigger with gauge gear (DESIGN.md 8.16).
func _gauge_gain(source: Combatant, amount: int) -> int:
	return CombatMath.percent(amount, maxi(0, 100 + Passive.amount(source, Passive.GAUGE)))


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


## `striker`'s critical hit: the tuned crit damage, bigger with crit-damage Relics (card #242).
func _crit_damage(striker: Combatant, amount: int) -> int:
	return CombatMath.percent_min1(amount, maxi(100, tuning.crit_damage_percent + Passive.amount(striker, Passive.CRIT_DAMAGE)))


## An enemy hit on a party member: power x hit percent, then Guard, then variance.
func _enemy_hit_damage(enemy: Combatant, target: Combatant, pct: int) -> int:
	var amount := CombatMath.percent_min1(enemy.power, pct)
	if target.has_status(Status.GUARDED):
		amount = CombatMath.percent_min1(amount, tuning.guard_damage_percent)
	var tough := mini(Passive.amount(target, Passive.TOUGH), tuning.tough_max_percent)
	if tough != 0:
		# Below 0 (rot-touched gear's drawback) the hit lands harder.
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
	# A staggered enemy takes extra damage from every source (card #195).
	var staggered := not target.is_party() and target.staggered_turns > 0
	if staggered:
		var breaker := Passive.amount(source, Passive.STAGGER_DAMAGE) if source.is_party() else 0
		amount = CombatMath.percent_min1(amount, 100 + tuning.stagger_damage_taken_percent + maxi(0, breaker))
	if not target.is_party() and target.has_status(Status.SHIELDED):
		# A Rot Priest's ward (card #259).
		amount = CombatMath.percent_min1(amount, maxi(0, 100 - tuning.shielded_damage_cut_percent))
	var lost := _lose_hp(target, amount)
	var event := {
		"type": "damage",
		"source": source.id,
		"target": target.id,
		"amount": amount,
		"hp": target.hp,
		"max_hp": target.max_hp,
		"cause": cause,
		"crit": crit,
	}
	if staggered:
		event["staggered"] = true
	events.append(event)
	if not target.is_alive():
		events.append({"type": "downed", "target": target.id})
		_on_downed(target, events)
		_heal_on_kill(source, target, events)
	elif not target.is_party():
		_count_doom_damage(target, lost, events)
		_maybe_enter_phase_two(target, events)


## Kill-heal gear (DESIGN.md 8.16): a hero whose hit downed an enemy heals a share of their max HP,
## and kill-AP Relics (card #242) give them AP.
func _heal_on_kill(killer: Combatant, victim: Combatant, events: Array[Dictionary]) -> void:
	if victim.is_party() or not killer.is_party() or not killer.is_alive():
		return
	var pct := Passive.amount(killer, Passive.KILL_HEAL)
	if pct > 0:
		_heal(killer, killer, CombatMath.percent_min1(killer.max_hp, pct), events)
	var gain := Passive.amount(killer, Passive.KILL_AP)
	if gain > 0:
		_change_ap(killer, gain, "gear", events)


# --- charged dooms (card #195) ----------------------------------------------------------------

## The HP of damage that breaks `attack` for `enemy`.
func _break_hp(enemy: Combatant, attack: EnemyAttackData) -> int:
	return CombatMath.percent_min1(enemy.max_hp, attack.break_damage_percent)


## Starts the countdown when `attack` (a Doom) becomes the enemy's intent. The turn it was
## announced for is the first of the charge_turns it takes. No-op for other moves and when the
## enemy is already charging this one.
func _arm_charge(enemy: Combatant, attack: EnemyAttackData) -> void:
	if attack == null or not attack.is_doom() or enemy.charge_attack == attack.id:
		return
	enemy.charge_attack = attack.id
	enemy.charge_left = attack.charge_turns
	enemy.charge_damage = 0


func _doom_event(type: String, enemy: Combatant, attack: EnemyAttackData) -> Dictionary:
	return {
		"type": type,
		"enemy": enemy.id,
		"attack": attack.id,
		"name": attack.display_name,
		"left": enemy.charge_left,
		"total": attack.charge_turns,
		"damage": enemy.charge_damage,
		"break_hp": _break_hp(enemy, attack),
	}


## HP the party took off a gathering enemy counts toward the break; enough breaks the Doom.
func _count_doom_damage(enemy: Combatant, lost: int, events: Array[Dictionary]) -> void:
	if enemy.charge_left <= 0 or lost <= 0:
		return
	var attack := get_attack(enemy.charge_attack)
	if attack == null:
		return
	enemy.charge_damage += lost
	if enemy.charge_damage >= _break_hp(enemy, attack):
		_break_doom(enemy, attack, events)
	else:
		events.append({"type": "doom_progress", "enemy": enemy.id, "attack": attack.id, "damage": enemy.charge_damage,
				"break_hp": _break_hp(enemy, attack)})


## The Doom is cancelled and the enemy staggers: it loses its next turn(s) and takes extra damage
## until then. The cooldown starts as if it had been used, and the enemy announces a new move.
func _break_doom(enemy: Combatant, attack: EnemyAttackData, events: Array[Dictionary]) -> void:
	var broken := _doom_event("doom_broken", enemy, attack)
	broken.erase("left")
	broken.erase("total")
	broken["stagger_turns"] = tuning.stagger_turns
	enemy.clear_charge()
	enemy.note_attack(attack.id, attack.cooldown_turns, -1)
	enemy.staggered_turns = tuning.stagger_turns
	events.append(broken)
	events.append({"type": "stagger_changed", "enemy": enemy.id, "turns": enemy.staggered_turns, "lost_turn": false})
	_pick_intent(enemy, events)
	events.append({"type": "turn_order", "order": preview_turn_order(tuning.turn_order_preview)})


## A staggered enemy's turn passes without an attack; its announced intent stays.
func _lose_staggered_turn(enemy: Combatant, events: Array[Dictionary]) -> void:
	enemy.staggered_turns -= 1
	_keep_intent = enemy.id
	events.append({"type": "stagger_changed", "enemy": enemy.id, "turns": enemy.staggered_turns, "lost_turn": true})


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
