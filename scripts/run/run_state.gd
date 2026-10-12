class_name RunState
extends RefCounted
## One run in progress (DESIGN.md 8): the map, where the party is on it, the party's HP (carried
## from fight to fight), max HP boosts and gold. The run's rules live here as plain integer maths
## so they are unit-tested; screens only call these functions and show the result.

const VICTORY := "victory"
const DEFEAT := "defeat"

var data: RunData
var tuning: Tuning
var run_seed: int = 1
var map: RunMap
## The stop the party is at (-1: before the first stop).
var at: int = -1
## Stops visited, in order.
var path: Array[int] = []
var gold: int = 0
## Per party slot: current HP, and max HP in percent of the character's normal max HP.
var hp: Array[int] = []
var max_hp_percent: Array[int] = []
var fights_won: int = 0
var gold_earned: int = 0
## "" while the run goes on, then VICTORY or DEFEAT.
var result: String = ""


## A new run of `run_data` with this seed: a fresh map, full HP, the starting gold.
static func begin(run_data: RunData, p_tuning: Tuning, p_seed: int) -> RunState:
	var run := RunState.new()
	run.data = run_data
	run.tuning = p_tuning
	run.run_seed = p_seed
	run.map = RunMap.generate(CombatRng.new(p_seed), p_tuning, run_data.zones.size())
	run.gold = p_tuning.run_start_gold
	for c: CharacterData in run_data.party:
		run.max_hp_percent.append(100)
		run.hp.append(CombatSetup.scaled_max_hp(p_tuning, c, 100))
	return run


func party_size() -> int:
	return data.party.size()


func max_hp(slot: int) -> int:
	return CombatSetup.scaled_max_hp(tuning, data.party[slot], max_hp_percent[slot])


func is_over() -> bool:
	return not result.is_empty()


## The stop the party is at ({} before the first one).
func current() -> Dictionary:
	return map.stop(at)


func choices() -> Array[int]:
	return map.choices(at)


## Moves to stop `id`. False (and nothing changes) if it is not one of the choices.
func go(id: int) -> bool:
	if is_over() or not choices().has(id):
		return false
	at = id
	path.append(id)
	return true


## The zone of a zone stop (null for other stops).
func zone_of(stop: Dictionary) -> ZoneData:
	var index := int(stop.get("zone", -1))
	return data.zones[index] if index >= 0 and index < data.zones.size() else null


## Gold for beating an encounter: the sum of its enemies' gold.
static func encounter_gold(encounter: EncounterData) -> int:
	var total := 0
	for e: EnemyData in encounter.enemies:
		if e != null:
			total += e.gold
	return total


## The fight setup for an encounter in this run: the run's party, team ultimate, HP and max HP.
func fight_setup(encounter: EncounterData, p_seed: int, opening: CombatSetup.Opening) -> CombatSetup:
	var setup := CombatSetup.from_encounter(encounter, tuning, p_seed, opening)
	setup.party = data.party.duplicate()
	setup.team_ultimate = data.team_ultimate
	setup.party_max_hp_percent = max_hp_percent.duplicate()
	setup.party_start_hp = hp.duplicate()
	return setup


## A fight ended with these party HPs (per slot). A victory pays the encounter's gold and gets
## the downed back up at tuning.run_downed_revive_hp; a defeat ends the run. Returns the gold won.
func finish_fight(fight_result: String, party_hp: Array[int], encounter: EncounterData) -> int:
	if fight_result != VICTORY:
		for slot: int in hp.size():
			hp[slot] = 0
		result = DEFEAT
		return 0
	for slot: int in hp.size():
		var after := party_hp[slot] if slot < party_hp.size() else hp[slot]
		hp[slot] = clampi(maxi(after, tuning.run_downed_revive_hp), 1, max_hp(slot))
	fights_won += 1
	var won := encounter_gold(encounter)
	gold += won
	gold_earned += won
	if int(current().get("type", -1)) == RunMap.StopType.FINAL:
		result = VICTORY
	return won


## Rest: everyone heals tuning.run_rest_heal_percent of their max HP. Returns HP healed per slot.
func rest() -> Array[int]:
	var healed: Array[int] = []
	for slot: int in hp.size():
		healed.append(heal(slot, CombatMath.percent(max_hp(slot), tuning.run_rest_heal_percent)))
	return healed


## Heals one character (never above max HP). Returns how much was healed.
func heal(slot: int, amount: int) -> int:
	var before := hp[slot]
	hp[slot] = clampi(before + maxi(amount, 0), 1, max_hp(slot))
	return hp[slot] - before


## True if `item` can be bought now for `slot` (ignored for items that need no target).
func can_buy(item: ShopItemData, slot: int) -> bool:
	if item == null or gold < item.price:
		return false
	return not item.needs_target() or (slot >= 0 and slot < hp.size())


## Buys `item` for `slot`. False (and nothing changes) if it cannot be bought.
func buy(item: ShopItemData, slot: int) -> bool:
	if not can_buy(item, slot):
		return false
	gold -= item.price
	match item.effect:
		ShopItemData.Effect.HEAL_ONE:
			heal(slot, CombatMath.percent(max_hp(slot), item.amount_percent))
		ShopItemData.Effect.HEAL_ALL:
			for s: int in hp.size():
				heal(s, CombatMath.percent(max_hp(s), item.amount_percent))
		ShopItemData.Effect.MAX_HP_ONE:
			var before := max_hp(slot)
			max_hp_percent[slot] += item.amount_percent
			heal(slot, max_hp(slot) - before)
	return true
