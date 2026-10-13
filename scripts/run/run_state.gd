class_name RunState
extends RefCounted
## One run in progress (DESIGN.md 8): the map, where the party is on it, the party's HP (carried
## from fight to fight), max HP boosts, gold, the party level and XP, and the gear (worn and in the
## bag). The run's rules live here as plain integer maths so they are unit-tested; screens only
## call these functions and show the result.

const VICTORY := "victory"
## A fight left with Run (DESIGN.md 2.13).
const ESCAPED := "escaped"
const DEFEAT := "defeat"
## Salts for the seeded picks of each stop (loot and shop gear differ at the same stop).
const LOOT_SALT: int = 7919
const SHOP_SALT: int = 104729

var data: RunData
var tuning: Tuning
var run_seed: int = 1
var map: RunMap
## The stop the party is at (-1: before the first stop).
var at: int = -1
## Stops visited, in order.
var path: Array[int] = []
var gold: int = 0
## Per party slot: current HP, and max HP bought with tonics (percent of the character's normal
## max HP; levels and gear add to it in total_max_hp_percent).
var hp: Array[int] = []
var max_hp_percent: Array[int] = []
## The whole party shares one level; xp counts toward the next one.
var level: int = 1
var xp: int = 0
## Per party slot, tuning.run_gear_slots entries: GearData or null.
var gear: Array[Array] = []
## Gear the party owns but nobody wears.
var bag: Array[GearData] = []
var fights_won: int = 0
var gold_earned: int = 0
## "" while the run goes on, then VICTORY or DEFEAT.
var result: String = ""


## A new run of `run_data` with this seed: a fresh map, full HP, the starting gold, level 1.
static func begin(run_data: RunData, p_tuning: Tuning, p_seed: int) -> RunState:
	var run := RunState.new()
	run.data = run_data
	run.tuning = p_tuning
	run.run_seed = p_seed
	run.map = RunMap.generate(CombatRng.new(p_seed), p_tuning, run_data.zones.size())
	run.gold = p_tuning.run_start_gold
	for c: CharacterData in run_data.party:
		run.max_hp_percent.append(100)
		var slots: Array = []
		slots.resize(p_tuning.run_gear_slots)
		run.gear.append(slots)
	for slot: int in run_data.party.size():
		run.hp.append(run.max_hp(slot))
	return run


## Everything that changes during the run as plain data (gear by id), for online play: the host
## sends it and the other machines show it (DESIGN.md 9.2). The map is rebuilt from the seed.
func to_dict() -> Dictionary:
	var worn: Array = []
	for slots: Array in gear:
		var ids: Array = []
		for item: Variant in slots:
			ids.append((item as GearData).id if item != null else "")
		worn.append(ids)
	var bag_ids: Array = []
	for item: GearData in bag:
		bag_ids.append(item.id)
	return {
		"seed": run_seed, "at": at, "path": Array(path), "gold": gold, "hp": Array(hp),
		"max_hp_percent": Array(max_hp_percent), "level": level, "xp": xp, "gear": worn, "bag": bag_ids,
		"fights_won": fights_won, "gold_earned": gold_earned, "result": result,
	}


## A run of `run_data` set to to_dict() data. Null if the data does not fit (malformed, or a
## different run: unknown gear, wrong party size).
static func from_dict(run_data: RunData, p_tuning: Tuning, d: Dictionary) -> RunState:
	if typeof(d.get("seed")) != TYPE_INT:
		return null
	var run := RunState.begin(run_data, p_tuning, int(d.seed))
	return run if run.apply_dict(d) else null


## Sets this run (same seed) to to_dict() data. False (and nothing changed) if it does not fit.
func apply_dict(d: Dictionary) -> bool:
	for key: String in ["seed", "at", "gold", "level", "xp", "fights_won", "gold_earned"]:
		if typeof(d.get(key)) != TYPE_INT:
			return false
	if int(d.seed) != run_seed or typeof(d.get("result")) != TYPE_STRING:
		return false
	for key: String in ["path", "hp", "max_hp_percent", "gear", "bag"]:
		if not d.get(key) is Array:
			return false
	var size := party_size()
	if (d.hp as Array).size() != size or (d.max_hp_percent as Array).size() != size or (d.gear as Array).size() != size:
		return false
	var by_id: Dictionary = {}
	for item: GearData in data.gear:
		if item != null:
			by_id[item.id] = item
	var new_gear: Array[Array] = []
	for ids: Variant in d.gear:
		if not ids is Array or (ids as Array).size() != tuning.run_gear_slots:
			return false
		var slots: Array = []
		for id: Variant in ids:
			if typeof(id) != TYPE_STRING or (String(id) != "" and not by_id.has(String(id))):
				return false
			slots.append(by_id[String(id)] if String(id) != "" else null)
		new_gear.append(slots)
	var new_bag: Array[GearData] = []
	for id: Variant in d.bag:
		if typeof(id) != TYPE_STRING or not by_id.has(String(id)):
			return false
		new_bag.append(by_id[String(id)])
	for key: String in ["path", "hp", "max_hp_percent"]:
		for v: Variant in d[key]:
			if typeof(v) != TYPE_INT:
				return false
	if int(d.at) != -1 and map.stop(int(d.at)).is_empty():
		return false
	at = int(d.at)
	path.assign(d.path)
	gold = int(d.gold)
	hp.assign(d.hp)
	max_hp_percent.assign(d.max_hp_percent)
	level = int(d.level)
	xp = int(d.xp)
	gear = new_gear
	bag = new_bag
	fights_won = int(d.fights_won)
	gold_earned = int(d.gold_earned)
	result = String(d.result)
	return true


func party_size() -> int:
	return data.party.size()


# --- stats ------------------------------------------------------------------------------------

## Max HP percent with tonics, levels and gear.
func total_max_hp_percent(slot: int) -> int:
	return max_hp_percent[slot] + (level - 1) * tuning.run_level_hp_percent + gear_amount(slot, GearData.Effect.MAX_HP)


func max_hp(slot: int) -> int:
	return CombatSetup.scaled_max_hp(tuning, data.party[slot], total_max_hp_percent(slot))


## Power percent with levels and gear (100 = the character's normal power).
func power_percent(slot: int) -> int:
	return 100 + (level - 1) * tuning.run_level_power_percent + gear_amount(slot, GearData.Effect.POWER)


func power(slot: int) -> int:
	return CombatMath.percent_min1(CombatMath.percent_min1(tuning.base_party_damage, data.party[slot].power_percent),
			power_percent(slot))


func speed(slot: int) -> int:
	return maxi(1, data.party[slot].speed + gear_amount(slot, GearData.Effect.SPEED))


## What slot `slot`'s worn gear adds up to for one effect.
func gear_amount(slot: int, effect: GearData.Effect) -> int:
	var total := 0
	for item: Variant in gear[slot]:
		if item != null and (item as GearData).effect == effect:
			total += (item as GearData).amount
	return total


## The passives slot `slot` brings into fights (Passive keys -> amount).
func passives(slot: int) -> Dictionary:
	var found := {}
	for item: Variant in gear[slot]:
		if item == null:
			continue
		var key := (item as GearData).passive_key()
		if not key.is_empty():
			found[key] = int(found.get(key, 0)) + (item as GearData).amount
	return found


func is_over() -> bool:
	return not result.is_empty()


# --- the map ----------------------------------------------------------------------------------

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


# --- fights -----------------------------------------------------------------------------------

## Gold for beating an encounter: the sum of its enemies' gold.
static func encounter_gold(encounter: EncounterData) -> int:
	var total := 0
	for e: EnemyData in encounter.enemies:
		if e != null:
			total += e.gold
	return total


static func encounter_xp(encounter: EncounterData) -> int:
	var total := 0
	for e: EnemyData in encounter.enemies:
		if e != null:
			total += e.xp
	return total


## Gold this run gets for an encounter, with the party's gold gear.
func gold_for(encounter: EncounterData) -> int:
	var bonus := 0
	for slot: int in party_size():
		bonus += gear_amount(slot, GearData.Effect.GOLD)
	return CombatMath.percent(encounter_gold(encounter), 100 + bonus)


## The fight setup for an encounter in this run: the run's party, team ultimate, HP, max HP,
## power, speed and gear passives.
func fight_setup(encounter: EncounterData, p_seed: int, opening: CombatSetup.Opening) -> CombatSetup:
	var setup := CombatSetup.from_encounter(encounter, tuning, p_seed, opening)
	setup.party = data.party.duplicate()
	setup.team_ultimate = data.team_ultimate
	setup.party_start_hp = hp.duplicate()
	for slot: int in party_size():
		setup.party_max_hp_percent.append(total_max_hp_percent(slot))
		setup.party_power_percent.append(power_percent(slot))
		setup.party_speed_bonus.append(gear_amount(slot, GearData.Effect.SPEED))
		setup.party_passives.append(passives(slot))
	return setup


## A fight ended with these party HPs (per slot). A victory pays gold and XP and gets the downed
## back up at tuning.run_downed_revive_hp; a defeat ends the run.
## Returns {gold, xp, levels} (levels gained).
func finish_fight(fight_result: String, party_hp: Array[int], encounter: EncounterData) -> Dictionary:
	if fight_result == ESCAPED:
		# Ran away (DESIGN.md 2.13): the HP carries on (a downed hero stands up at the floor),
		# no gold, no XP, the run goes on.
		for slot: int in hp.size():
			var left := party_hp[slot] if slot < party_hp.size() else hp[slot]
			hp[slot] = clampi(maxi(left, tuning.run_downed_revive_hp), 1, max_hp(slot))
		return {"gold": 0, "xp": 0, "levels": 0}
	if fight_result != VICTORY:
		for slot: int in hp.size():
			hp[slot] = 0
		result = DEFEAT
		return {"gold": 0, "xp": 0, "levels": 0}
	for slot: int in hp.size():
		var after := party_hp[slot] if slot < party_hp.size() else hp[slot]
		hp[slot] = clampi(maxi(after, tuning.run_downed_revive_hp), 1, max_hp(slot))
	fights_won += 1
	var won := gold_for(encounter)
	gold += won
	gold_earned += won
	var gained := encounter_xp(encounter)
	var levels := add_xp(gained)
	if int(current().get("type", -1)) == RunMap.StopType.FINAL:
		result = VICTORY
	return {"gold": won, "xp": gained, "levels": levels}


# --- levels -----------------------------------------------------------------------------------

## XP needed from this level to the next.
func xp_to_next() -> int:
	return tuning.run_xp_first_level + (level - 1) * tuning.run_xp_level_step


## Levels `amount` more XP would give from here (for the end screen, before it is added).
func levels_from(amount: int) -> int:
	var lv := level
	var left := xp + amount
	while lv < tuning.run_max_level:
		var need := tuning.run_xp_first_level + (lv - 1) * tuning.run_xp_level_step
		if left < need:
			break
		left -= need
		lv += 1
	return lv - level


## Adds XP; each level up raises max HP and power and heals what max HP grew. Returns levels gained.
func add_xp(amount: int) -> int:
	var gained := 0
	xp += maxi(0, amount)
	while level < tuning.run_max_level and xp >= xp_to_next():
		xp -= xp_to_next()
		var before: Array[int] = []
		for slot: int in party_size():
			before.append(max_hp(slot))
		level += 1
		gained += 1
		for slot: int in party_size():
			hp[slot] = mini(max_hp(slot), hp[slot] + max_hp(slot) - before[slot])
	if level >= tuning.run_max_level:
		xp = 0
	return gained


# --- rest and care ----------------------------------------------------------------------------

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


# --- gear -------------------------------------------------------------------------------------

## True if the party has this item (worn or in the bag).
func owns(item: GearData) -> bool:
	if bag.has(item):
		return true
	for slots: Array in gear:
		if slots.has(item):
			return true
	return false


## The loot a stop offers: up to tuning.run_loot_choices items the party does not own (seeded).
func loot_choices(stop_id: int) -> Array[GearData]:
	return _pick_gear(stop_id * LOOT_SALT, tuning.run_loot_choices)


## The gear a shop stop sells: up to tuning.run_shop_gear items the party does not own (seeded).
func shop_gear(stop_id: int) -> Array[GearData]:
	return _pick_gear(stop_id * SHOP_SALT, tuning.run_shop_gear)


func _pick_gear(salt: int, count: int) -> Array[GearData]:
	var left: Array[GearData] = []
	for item: GearData in data.gear:
		if item != null and not owns(item):
			left.append(item)
	var rng := CombatRng.new(absi(run_seed * 31 + salt) % 2147483647 + 1)
	var picked: Array[GearData] = []
	while picked.size() < count and not left.is_empty():
		picked.append(left.pop_at(rng.range_int(0, left.size() - 1)))
	return picked


## Takes loot into the bag. False if it is already owned.
func take(item: GearData) -> bool:
	if item == null or owns(item):
		return false
	bag.append(item)
	return true


func can_buy_gear(item: GearData) -> bool:
	return item != null and not owns(item) and gold >= item.price


func buy_gear(item: GearData) -> bool:
	if not can_buy_gear(item):
		return false
	gold -= item.price
	bag.append(item)
	return true


## Puts bag item `item` on character `slot` in gear slot `gear_slot`; what was there goes back
## to the bag. HP never rises from putting gear on (no free heal), and is cut to a lower max.
func equip(slot: int, gear_slot: int, item: GearData) -> bool:
	if not bag.has(item) or gear_slot < 0 or gear_slot >= gear[slot].size():
		return false
	var old: Variant = gear[slot][gear_slot]
	bag.erase(item)
	if old != null:
		bag.append(old as GearData)
	gear[slot][gear_slot] = item
	_clamp_hp()
	return true


## Takes off what character `slot` wears in `gear_slot` (back to the bag).
func unequip(slot: int, gear_slot: int) -> bool:
	var old: Variant = gear[slot][gear_slot]
	if old == null:
		return false
	gear[slot][gear_slot] = null
	bag.append(old as GearData)
	_clamp_hp()
	return true


## The first empty gear slot of character `slot`, or -1.
func free_gear_slot(slot: int) -> int:
	return gear[slot].find(null)


func _clamp_hp() -> void:
	for slot: int in hp.size():
		hp[slot] = clampi(hp[slot], 1, max_hp(slot))
