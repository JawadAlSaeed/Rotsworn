class_name CombatSetup
extends RefCounted
## Everything CombatEngine needs to build a fight.

## How the fight starts (DESIGN.md 2.12).
enum Opening {
	## Everyone's first turn comes from their speed.
	NORMAL,
	## The party struck a roaming enemy first: every party member acts before any enemy.
	FIRST_STRIKE,
}

## The Run action every hero has (DESIGN.md 2.13).
const RUN_ABILITY_PATH := "res://data/abilities/run.tres"

var party: Array[CharacterData] = []
var enemies: Array[EnemyData] = []
## Offered to every party member when the team gauge is full (null = no team ultimate).
var team_ultimate: AbilityData
## Run (DESIGN.md 2.13): every hero gets it when can_run is true (not against bosses, guards or elites).
var run_ability: AbilityData
var can_run: bool = false
var tuning: Tuning
var rng_seed: int = 1
## Accept practice commands (force an attack, invulnerability). Off for real runs.
var allow_practice: bool = false
var opening: Opening = Opening.NORMAL
## A run's carried-over state, per party slot (DESIGN.md 8). Empty = the defaults.
## Max HP in percent of the character's normal max HP (100 = unchanged).
var party_max_hp_percent: Array[int] = []
## HP at the start of the fight (-1 or missing = full; kept within 1 .. max HP).
var party_start_hp: Array[int] = []
## Power in percent of the character's normal power (levels, gear; 100 = unchanged).
var party_power_percent: Array[int] = []
## Speed added to the character's own (gear).
var party_speed_bonus: Array[int] = []
## Gear passives per slot (Passive keys -> amount).
var party_passives: Array[Dictionary] = []
## The skills each slot brings (a run with skill trees, card #136): ability ids. Missing or
## empty for a slot: every skill the character has.
var party_skills: Array[Array] = []
## The team gauge at the start of the fight (a run carries it over, card #146; 0 = empty).
var start_team_gauge: int = 0
## Every enemy's HP and power in percent of their data (a run's depth, DESIGN.md 8.3; 100 =
## unchanged).
var enemy_hp_percent: int = 100
var enemy_power_percent: int = 100
## Every enemy's speed in percent of their data (the tutorial's slower enemy, DESIGN.md 7.8).
var enemy_speed_percent: int = 100
## How fast enemy attacks play, in percent of their authored timing (card #188; lower = faster,
## 0 = tuning attack_tempo_percent). A run sets it from depth, elites, guards and bosses; it never
## goes under tempo_floor().
var attack_tempo_percent: int = 0
## Hits take their forced kinds (REND, SWEEP; card #187): elite, guard and boss fights.
var forced_hits: bool = false
## Backpack items the party can use in this fight (DESIGN.md 8.1): {uid: int, item: ItemData,
## amount: int (its effect percent, stronger once combined), name: String}.
## Each can be used once; the run takes the used ones out of the backpack afterwards.
var items: Array[Dictionary] = []


static func from_encounter(encounter: EncounterData, p_tuning: Tuning, p_seed: int,
		p_opening: Opening = Opening.NORMAL) -> CombatSetup:
	var setup := CombatSetup.new()
	setup.opening = p_opening
	setup.party = encounter.party.duplicate()
	setup.enemies = encounter.enemies.duplicate()
	setup.team_ultimate = encounter.team_ultimate
	setup.run_ability = load(RUN_ABILITY_PATH) as AbilityData
	# Bosses, guards and elites are commitments (DESIGN.md 2.13): a rule here, so a new one in data
	# can never be left runnable by a forgotten can_run flag.
	setup.can_run = encounter.can_run and not encounter.boss and not encounter.mini_boss 			and not encounter.elite and setup.run_ability != null
	setup.tuning = p_tuning
	setup.rng_seed = p_seed
	# Hard fights read the forced-choice hits (card #187): a data rule, like can_run above.
	setup.forced_hits = encounter.elite or encounter.boss or encounter.mini_boss
	return setup


## The fastest enemy attacks may play, in percent of their authored timing (card #188): tuning
## attack_tempo_floor_percent, or the global tempo if that is set faster on purpose.
static func tempo_floor(p_tuning: Tuning) -> int:
	return mini(p_tuning.attack_tempo_floor_percent, p_tuning.attack_tempo_percent)


## Max HP of party member `slot` (`data`) in this fight: the character's own max HP, scaled by
## the run's percent for that slot. RunState uses the same rule, so both always agree.
func party_max_hp(slot: int, data: CharacterData) -> int:
	var pct := party_max_hp_percent[slot] if slot < party_max_hp_percent.size() else 100
	return scaled_max_hp(tuning, data, pct)


## Power of party member `slot` in this fight: the character's own power, scaled by the run.
func party_power(slot: int, data: CharacterData) -> int:
	var pct := party_power_percent[slot] if slot < party_power_percent.size() else 100
	return CombatMath.percent_min1(CombatMath.percent_min1(tuning.base_party_damage, data.power_percent), pct)


func party_speed(slot: int, data: CharacterData) -> int:
	return maxi(1, data.speed + (party_speed_bonus[slot] if slot < party_speed_bonus.size() else 0))


## The abilities party member `slot` (`data`) can use: the basic attack, then the skills it
## brings (party_skills), or every skill.
func party_abilities(slot: int, data: CharacterData) -> Array[AbilityData]:
	var all := data.all_abilities()
	if slot >= party_skills.size() or party_skills[slot].is_empty():
		return all
	var list: Array[AbilityData] = []
	for ability: AbilityData in all:
		if ability == data.basic_attack or party_skills[slot].has(ability.id):
			list.append(ability)
	return list


func party_passives_of(slot: int) -> Dictionary:
	return party_passives[slot].duplicate() if slot < party_passives.size() else {}


## A character's max HP with its run percent applied (100 = the character's normal max HP).
static func scaled_max_hp(p_tuning: Tuning, data: CharacterData, percent: int) -> int:
	return CombatMath.percent_min1(CombatMath.percent_min1(p_tuning.base_character_hp, data.hp_percent), percent)


## HP party member `slot` starts the fight with (`max_hp` = its max HP).
func party_hp_at_start(slot: int, max_hp: int) -> int:
	var start := party_start_hp[slot] if slot < party_start_hp.size() else -1
	return max_hp if start < 0 else clampi(start, 1, max_hp)


## Human-readable problems. Empty means the setup is usable.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if tuning == null:
		problems.append("no tuning resource")
	if party.is_empty() or party.size() > 3:
		problems.append("party must have 1 to 3 characters (has %d)" % party.size())
	if enemies.is_empty():
		problems.append("no enemies")
	for pct: int in party_max_hp_percent + party_power_percent:
		if pct < 1:
			problems.append("party max HP and power percents must be at least 1 (is %d)" % pct)
	if tuning != null and (start_team_gauge < 0 or start_team_gauge > tuning.team_gauge_max):
		problems.append("start team gauge must be 0 .. team_gauge_max (is %d)" % start_team_gauge)
	if enemy_hp_percent < 1 or enemy_power_percent < 1 or enemy_speed_percent < 1:
		problems.append("enemy HP and power percents must be at least 1")
	if attack_tempo_percent < 0:
		problems.append("attack tempo percent must be 0 (tuning's) or more")
	for passives: Dictionary in party_passives:
		for key: Variant in passives:
			if not Passive.ALL.has(String(key)):
				problems.append("unknown passive '%s'" % String(key))
	for c: CharacterData in party:
		if c == null:
			problems.append("empty party slot")
		elif c.basic_attack == null:
			problems.append("character %s has no basic attack" % c.id)
		else:
			for ability: AbilityData in c.all_abilities():
				problems.append_array(_ability_problems(ability))
	if run_ability != null:
		problems.append_array(_ability_problems(run_ability))
		if not run_ability.escape:
			problems.append("run ability %s is not marked escape" % run_ability.id)
	if team_ultimate != null:
		problems.append_array(_ability_problems(team_ultimate))
		if not team_ultimate.team_ultimate:
			problems.append("team ultimate %s is not marked team_ultimate" % team_ultimate.id)
	var uids := {}
	for entry: Dictionary in items:
		var item: Variant = entry.get("item")
		if not item is ItemData or not (item as ItemData).usable_in_fight():
			problems.append("fight item %s cannot be used in fights" % str(entry.get("uid")))
		elif uids.has(int(entry.get("uid", -1))):
			problems.append("fight item uid %d twice" % int(entry.uid))
		uids[int(entry.get("uid", -1))] = true
	for e: EnemyData in enemies:
		if e == null:
			problems.append("empty enemy slot")
			continue
		for a: EnemyAttackData in e.attacks:
			if a == null:
				problems.append("enemy %s has an empty attack slot" % e.id)
				continue
			if a.hits.is_empty():
				problems.append("attack %s has no hits" % a.id)
			var last := -1
			for h: AttackHitData in a.hits:
				if h == null:
					problems.append("attack %s has an empty hit slot" % a.id)
				elif h.kind == AttackHitData.Kind.PRESS:
					problems.append("attack %s: PRESS is for party skills only" % a.id)
				elif h.forced_kind != AttackHitData.Kind.NORMAL and (h.kind != AttackHitData.Kind.NORMAL
						or not AttackHitData.is_forced(h.forced_kind)):
					problems.append("attack %s: a forced kind is REND or SWEEP, on a normal hit" % a.id)
				elif h.impact_ms <= last:
					problems.append("attack %s: hit times must increase" % a.id)
				else:
					last = h.impact_ms
	return problems


func _ability_problems(ability: AbilityData) -> PackedStringArray:
	var problems := PackedStringArray()
	var last := -1
	for at_ms: int in ability.press_times_ms:
		if at_ms <= last:
			problems.append("ability %s: press times must increase" % ability.id)
			break
		last = at_ms
	for id: String in [ability.status, ability.self_status, ability.press_self_status]:
		if not id.is_empty() and not Status.is_known(id):
			problems.append("ability %s: unknown status '%s'" % [ability.id, id])
	return problems
