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

var party: Array[CharacterData] = []
var enemies: Array[EnemyData] = []
## Offered to every party member when the team gauge is full (null = no team ultimate).
var team_ultimate: AbilityData
var tuning: Tuning
var rng_seed: int = 1
## Accept practice commands (force an attack, invulnerability). Off for real runs.
var allow_practice: bool = false
var opening: Opening = Opening.NORMAL


static func from_encounter(encounter: EncounterData, p_tuning: Tuning, p_seed: int,
		p_opening: Opening = Opening.NORMAL) -> CombatSetup:
	var setup := CombatSetup.new()
	setup.opening = p_opening
	setup.party = encounter.party.duplicate()
	setup.enemies = encounter.enemies.duplicate()
	setup.team_ultimate = encounter.team_ultimate
	setup.tuning = p_tuning
	setup.rng_seed = p_seed
	return setup


## Human-readable problems. Empty means the setup is usable.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if tuning == null:
		problems.append("no tuning resource")
	if party.is_empty() or party.size() > 3:
		problems.append("party must have 1 to 3 characters (has %d)" % party.size())
	if enemies.is_empty():
		problems.append("no enemies")
	for c: CharacterData in party:
		if c == null:
			problems.append("empty party slot")
		elif c.basic_attack == null:
			problems.append("character %s has no basic attack" % c.id)
		else:
			for ability: AbilityData in c.all_abilities():
				problems.append_array(_ability_problems(ability))
	if team_ultimate != null:
		problems.append_array(_ability_problems(team_ultimate))
		if not team_ultimate.team_ultimate:
			problems.append("team ultimate %s is not marked team_ultimate" % team_ultimate.id)
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
	if not ability.status.is_empty() and not Status.is_known(ability.status):
		problems.append("ability %s: unknown status '%s'" % [ability.id, ability.status])
	return problems
