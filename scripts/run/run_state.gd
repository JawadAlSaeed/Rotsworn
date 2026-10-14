class_name RunState
extends RefCounted
## One run in progress (DESIGN.md 8): the map, where the party is on it, the party's HP (carried
## from fight to fight), max HP boosts, gold, the party level and XP, the gear each hero wears and
## the shared backpack (DESIGN.md 8.1). The run's rules live here as plain integer maths so they
## are unit-tested; screens only call these functions and show the result.

const VICTORY := "victory"
## A fight left with Run (DESIGN.md 2.13).
const ESCAPED := "escaped"
const DEFEAT := "defeat"
## Salts for the seeded picks of each stop (loot and shop gear differ at the same stop).
const LOOT_SALT: int = 7919
const SHOP_SALT: int = 104729
## Salts for what a zone's glinting spots hold and what its roaming enemies drop.
const SPOT_SALT: int = 15485863
const DROP_SALT: int = 32452843
const CHEST_SALT: int = 49979687
## Every piece of gear starts from this weight before rarity scales it.
const GEAR_WEIGHT: int = 100

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
## The shared backpack (items only: gear is always worn).
var backpack: Backpack
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
	run.backpack = Backpack.new(p_tuning.backpack_width, p_tuning.backpack_rows)
	for c: CharacterData in run_data.party:
		run.max_hp_percent.append(100)
		var slots: Array = []
		slots.resize(p_tuning.run_gear_slots)
		run.gear.append(slots)
	for slot: int in run_data.party.size():
		run.hp.append(run.max_hp(slot))
	return run


## Everything that changes during the run as plain data (gear and items by id), for online play:
## the host sends it and the other machines show it (DESIGN.md 9.2). The map is rebuilt from the
## seed.
func to_dict() -> Dictionary:
	var worn: Array = []
	for slots: Array in gear:
		var ids: Array = []
		for item: Variant in slots:
			ids.append((item as GearData).id if item != null else "")
		worn.append(ids)
	return {
		"seed": run_seed, "at": at, "path": Array(path), "gold": gold, "hp": Array(hp),
		"max_hp_percent": Array(max_hp_percent), "level": level, "xp": xp, "gear": worn,
		"backpack": backpack.to_array(),
		"fights_won": fights_won, "gold_earned": gold_earned, "result": result,
	}


## A run of `run_data` set to to_dict() data. Null if the data does not fit (malformed, or a
## different run: unknown gear or items, wrong party size).
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
	for key: String in ["path", "hp", "max_hp_percent", "gear", "backpack"]:
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
	var new_pack := Backpack.from_array(d.backpack, items_by_id())
	if new_pack == null:
		return false
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
	backpack = new_pack
	fights_won = int(d.fights_won)
	gold_earned = int(d.gold_earned)
	result = String(d.result)
	return true


func party_size() -> int:
	return data.party.size()


# --- stats ------------------------------------------------------------------------------------

## Max HP percent with tonics, levels, gear and charms.
func total_max_hp_percent(slot: int) -> int:
	return max_hp_percent[slot] + (level - 1) * tuning.run_level_hp_percent + bonus(slot, GearData.Effect.MAX_HP)


func max_hp(slot: int) -> int:
	return CombatSetup.scaled_max_hp(tuning, data.party[slot], total_max_hp_percent(slot))


## Power percent with levels, gear and charms (100 = the character's normal power).
func power_percent(slot: int) -> int:
	return 100 + (level - 1) * tuning.run_level_power_percent + bonus(slot, GearData.Effect.POWER)


func power(slot: int) -> int:
	return CombatMath.percent_min1(CombatMath.percent_min1(tuning.base_party_damage, data.party[slot].power_percent),
			power_percent(slot))


func speed(slot: int) -> int:
	return maxi(1, data.party[slot].speed + bonus(slot, GearData.Effect.SPEED))


## What slot `slot`'s gear and the backpack's charms (which help every hero) add up to for one
## effect.
func bonus(slot: int, effect: GearData.Effect) -> int:
	return gear_amount(slot, effect) + int(charm_totals().get(effect, 0))


## What slot `slot`'s worn gear adds up to for one effect.
func gear_amount(slot: int, effect: GearData.Effect) -> int:
	var total := 0
	for item: Variant in gear[slot]:
		if item != null and (item as GearData).effect == effect:
			total += (item as GearData).amount
	return total


## The passives slot `slot` brings into fights (Passive keys -> amount): their gear's, the
## charms', and the rot of rotten items.
func passives(slot: int) -> Dictionary:
	var found := {}
	for item: Variant in gear[slot]:
		if item == null:
			continue
		var key := (item as GearData).passive_key()
		if not key.is_empty():
			found[key] = int(found.get(key, 0)) + (item as GearData).amount
	var charms := charm_totals()
	for effect: int in charms:
		var key := String(GearData.PASSIVE_KEYS.get(effect, ""))
		if not key.is_empty():
			found[key] = int(found.get(key, 0)) + int(charms[effect])
	var rot := rot_percent()
	if rot > 0:
		found[Passive.ROT] = rot
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


## True when the current stop is deep enough for variant monsters (tuning run_deep_row).
func is_deep() -> bool:
	return int(current().get("row", 0)) >= tuning.run_deep_row


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


## Gold this run gets for an encounter, with the party's gold gear and gold charms.
func gold_for(encounter: EncounterData) -> int:
	var extra := int(charm_totals().get(GearData.Effect.GOLD, 0))
	for slot: int in party_size():
		extra += gear_amount(slot, GearData.Effect.GOLD)
	return CombatMath.percent(encounter_gold(encounter), 100 + extra)


## The fight setup for an encounter in this run: the run's party, team ultimate, HP, max HP,
## power, speed, gear passives and the backpack's fight items.
func fight_setup(encounter: EncounterData, p_seed: int, opening: CombatSetup.Opening) -> CombatSetup:
	var setup := CombatSetup.from_encounter(encounter, tuning, p_seed, opening)
	setup.party = data.party.duplicate()
	setup.team_ultimate = data.team_ultimate
	setup.party_start_hp = hp.duplicate()
	for slot: int in party_size():
		setup.party_max_hp_percent.append(total_max_hp_percent(slot))
		setup.party_power_percent.append(power_percent(slot))
		setup.party_speed_bonus.append(bonus(slot, GearData.Effect.SPEED))
		setup.party_passives.append(passives(slot))
	for e: Dictionary in backpack.entries:
		if (e.item as ItemData).usable_in_fight():
			setup.items.append({"uid": int(e.uid), "item": e.item, "amount": entry_amount(e), "name": entry_name(e)})
	return setup


## Takes the items used in a fight out of the backpack (uids that are already gone are skipped).
func spend_items(uids: Array[int]) -> void:
	for uid: int in uids:
		backpack.remove(uid)


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


# --- the backpack (DESIGN.md 8.1) ---------------------------------------------------------------

## Every item this run knows (shop and finds), by id.
func items_by_id() -> Dictionary:
	var by_id := {}
	for list: Array[ItemData] in [data.shop_items, data.found_items]:
		for item: ItemData in list:
			if item != null:
				by_id[item.id] = item
	return by_id


## Gold for selling something with this price.
func sell_price(price: int) -> int:
	return CombatMath.percent(price, tuning.item_sell_percent)


## True if the party has the gold for `item`.
func can_afford(item: ItemData) -> bool:
	return item != null and gold >= item.price


## Pays for `item` (the caller puts it in the backpack). False if the gold is short.
func pay_for(item: ItemData) -> bool:
	if not can_afford(item):
		return false
	gold -= item.price
	return true


## Puts `item` wherever it fits first. Returns its uid, or -1 if there is no room. An upgrade (a
## bigger backpack) is used at once instead and returns 0.
func add_item(item: ItemData) -> int:
	if item != null and item.kind == ItemData.Kind.UPGRADE:
		take_upgrade(item)
		return 0
	return backpack.add_anywhere(item)


## True if `item` would do something if the party got it now (an upgrade with room left to grow).
func wants(item: ItemData) -> bool:
	if item == null:
		return false
	if item.kind == ItemData.Kind.UPGRADE:
		return item.effect == ItemData.Effect.ADD_ROW and backpack.rows < tuning.backpack_max_rows
	return true


## The charms a shop stop sells: up to tuning.run_shop_charms of the run's found charms, never
## rotten, picked by rarity at the stop's row (seeded).
func shop_charms(stop_id: int) -> Array[ItemData]:
	var left: Array[ItemData] = []
	for item: ItemData in data.found_items:
		if item != null and item.is_charm() and not item.rotten and not left.has(item):
			left.append(item)
	var rng := CombatRng.new(_salted(stop_id * SHOP_SALT + 17))
	var picked: Array[ItemData] = []
	var row := _row_of(stop_id)
	while picked.size() < tuning.run_shop_charms and not left.is_empty():
		var weights: Array = []
		for item: ItemData in left:
			weights.append(rarity_weight(item.find_weight, item.rarity, row))
		var index := _weighted_index(rng, weights)
		if index < 0:
			break
		picked.append(left.pop_at(index))
	return picked


## Puts `item` (at `level`) at (x, y) turned `turn` times. Returns its uid, or -1 if it does not
## fit there.
func place_item(item: ItemData, x: int, y: int, turn: int, level: int = 0) -> int:
	return backpack.add(item, x, y, turn, level)


func move_item(uid: int, x: int, y: int, turn: int) -> bool:
	return backpack.move(uid, x, y, turn)


## Throws item `uid` away (it is gone).
func drop_item(uid: int) -> bool:
	return backpack.remove(uid) != null


## True if backpack item `uid` can be used on the map now (on character `slot` if it needs one).
func can_use_item(uid: int, slot: int) -> bool:
	var e := backpack.entry(uid)
	if e.is_empty():
		return false
	var item := e.item as ItemData
	if not item.usable_on_map():
		return false
	return not item.needs_target() or (slot >= 0 and slot < hp.size())


## Uses backpack item `uid` on the map (on character `slot` if it needs one); it is used up.
func use_item(uid: int, slot: int) -> bool:
	if not can_use_item(uid, slot):
		return false
	var amount := entry_amount(backpack.entry(uid))
	apply_item(backpack.remove(uid), slot, amount)
	return true


## What an item does when used outside a fight (`amount`: its effect percent, -1 for the item's own).
func apply_item(item: ItemData, slot: int, amount: int = -1) -> void:
	var pct := item.amount_percent if amount < 0 else amount
	match item.effect:
		ItemData.Effect.HEAL_ONE:
			heal(slot, CombatMath.percent(max_hp(slot), pct))
		ItemData.Effect.HEAL_ALL:
			for s: int in hp.size():
				heal(s, CombatMath.percent(max_hp(s), pct))
		ItemData.Effect.MAX_HP_ONE:
			var before := max_hp(slot)
			max_hp_percent[slot] += pct
			heal(slot, max_hp(slot) - before)


# --- levels, charms, rot and combining (DESIGN.md 8.1) -----------------------------------------

## A placed item's level (0, higher once combined).
static func level_of(e: Dictionary) -> int:
	return int(e.get("level", 0))


## A placed item's effect percent: its own, stronger by tuning.combine_bonus_percent per level.
func entry_amount(e: Dictionary) -> int:
	return CombatMath.percent((e.item as ItemData).amount_percent, 100 + level_of(e) * tuning.combine_bonus_percent)


## A placed item's name: "Salve", "Salve+", "Salve++".
static func entry_name(e: Dictionary) -> String:
	return (e.item as ItemData).display_name + "+".repeat(level_of(e))


## A placed item's rarity: its own, one step up per level (never past legendary).
static func entry_rarity(e: Dictionary) -> int:
	return mini(int((e.item as ItemData).rarity) + level_of(e), ItemData.Rarity.LEGENDARY)


## A placed item's price: its own, higher by tuning.combine_bonus_percent per level.
func entry_price(e: Dictionary) -> int:
	return CombatMath.percent((e.item as ItemData).price, 100 + level_of(e) * tuning.combine_bonus_percent)


## How much stronger touching charms make charm `uid` (percent points; 0 if nothing boosts it).
func charm_boost(uid: int) -> int:
	var e := backpack.entry(uid)
	if e.is_empty() or not (e.item as ItemData).is_charm():
		return 0
	var family := (e.item as ItemData).family
	var boost := 0
	if family == ItemData.Family.NONE:
		return 0
	for other: int in backpack.touching(uid):
		var booster := backpack.entry(other).item as ItemData
		if booster.is_charm() and booster.boost_family == family:
			boost += CombatMath.percent(booster.boost_percent, 100 + level_of(backpack.entry(other)) * tuning.combine_bonus_percent)
	return boost


## What charm `uid` gives every hero now: its amount (stronger per level) boosted by touching
## charms.
func charm_value(uid: int) -> int:
	var e := backpack.entry(uid)
	if e.is_empty() or not (e.item as ItemData).is_charm():
		return 0
	var own := CombatMath.percent((e.item as ItemData).charm_amount, 100 + level_of(e) * tuning.combine_bonus_percent)
	return CombatMath.percent(own, 100 + charm_boost(uid))


## Every charm in the backpack, added up: GearData.Effect -> amount (for every hero).
func charm_totals() -> Dictionary:
	var totals := {}
	if backpack == null:
		return totals
	for e: Dictionary in backpack.entries:
		var item := e.item as ItemData
		if item.is_charm() and item.charm_amount > 0:
			totals[item.charm_effect] = int(totals.get(item.charm_effect, 0)) + charm_value(int(e.uid))
	return totals


## The HP percent every hero loses each turn in a fight from the rotten items carried.
func rot_percent() -> int:
	var total := 0
	if backpack == null:
		return total
	for e: Dictionary in backpack.entries:
		if (e.item as ItemData).rotten:
			total += (e.item as ItemData).rot_percent
	return total


## True if item `uid` can be combined into item `into`: two of the same item at the same level,
## a kind that combines, and not past legendary.
func can_combine(uid: int, into: int) -> bool:
	if uid == into:
		return false
	var a := backpack.entry(uid)
	var b := backpack.entry(into)
	if a.is_empty() or b.is_empty():
		return false
	return _combines(a.item as ItemData, level_of(a), b)


func _combines(item: ItemData, item_level: int, target: Dictionary) -> bool:
	return item == target.item and item.combinable() and item_level == level_of(target) \
			and entry_rarity(target) < ItemData.Rarity.LEGENDARY


## Combines item `uid` into item `into`: `into` goes up a level, `uid` is gone.
func combine(uid: int, into: int) -> bool:
	if not can_combine(uid, into):
		return false
	backpack.remove(uid)
	backpack.entry(into).level = level_of(backpack.entry(into)) + 1
	return true


## Combines a new item (not in the backpack yet, level 0) into item `into`.
func combine_new(item: ItemData, into: int) -> bool:
	var target := backpack.entry(into)
	if target.is_empty() or not _combines(item, 0, target):
		return false
	target.level = level_of(target) + 1
	return true


## Applies an upgrade the moment the party gets it (a bigger backpack). False if it does nothing
## (not an upgrade, or the backpack is already as big as it gets).
func take_upgrade(item: ItemData) -> bool:
	if item == null or item.kind != ItemData.Kind.UPGRADE:
		return false
	if item.effect == ItemData.Effect.ADD_ROW and backpack.rows < tuning.backpack_max_rows:
		backpack.rows += 1
		return true
	return false


## A backpack or gear change as plain data, from any player (online, clients send these to the
## host, which applies them in the order they arrive: DESIGN.md 8.1). Ops:
## {op: "move", uid, x, y, turn}, {op: "drop", uid}, {op: "use", uid, slot}, {op: "sell", uid},
## {op: "combine", uid, into},
## {op: "swap_gear", from: [slot, gear_slot], to: [slot, gear_slot]}.
## False (and nothing changes) if it is malformed or no longer possible (someone else got there
## first).
func apply_op(op: Dictionary) -> bool:
	if is_over():
		return false
	var ints := func(keys: Array) -> bool:
		for key: String in keys:
			if typeof(op.get(key)) != TYPE_INT:
				return false
		return true
	match String(op.get("op", "")):
		"move":
			return ints.call(["uid", "x", "y", "turn"]) and move_item(int(op.uid), int(op.x), int(op.y), int(op.turn))
		"drop":
			return ints.call(["uid"]) and drop_item(int(op.uid))
		"use":
			return ints.call(["uid", "slot"]) and use_item(int(op.uid), int(op.slot))
		"sell":
			return ints.call(["uid"]) and sell_item(int(op.uid)) >= 0
		"combine":
			return ints.call(["uid", "into"]) and combine(int(op.uid), int(op.into))
		"swap_gear":
			var from: Variant = op.get("from")
			var to: Variant = op.get("to")
			if not from is Array or not to is Array or (from as Array).size() != 2 or (to as Array).size() != 2:
				return false
			for v: Variant in (from as Array) + (to as Array):
				if typeof(v) != TYPE_INT:
					return false
			return swap_gear(int(from[0]), int(from[1]), int(to[0]), int(to[1]))
	return false


## Sells backpack item `uid` (it is gone). Returns the gold, or -1 if there is no such item or it
## is rotten (nobody buys rot).
func sell_item(uid: int) -> int:
	var e := backpack.entry(uid)
	if e.is_empty() or (e.item as ItemData).rotten:
		return -1
	var gained := sell_price(entry_price(e))
	backpack.remove(uid)
	gold += gained
	return gained


## True if a key is in the backpack.
func has_key() -> bool:
	return _key_uid() >= 0


## Uses up one key (the first one in the backpack). False if there is none.
func use_key() -> bool:
	var uid := _key_uid()
	return uid >= 0 and backpack.remove(uid) != null


func _key_uid() -> int:
	for e: Dictionary in backpack.entries:
		if (e.item as ItemData).kind == ItemData.Kind.KEY:
			return int(e.uid)
	return -1


## What the chest of the zone at stop `stop_id` holds (seeded): tuning.chest_gear_percent of the
## time a piece of rare or better gear the party does not wear, else a rare or better item (any
## item if the run has none that rare). GearData or ItemData; null if nothing at all is left.
func chest_contents(stop_id: int) -> Resource:
	var rng := CombatRng.new(_salted(stop_id * CHEST_SALT))
	var row := _row_of(stop_id)
	if rng.range_int(0, 99) < tuning.chest_gear_percent:
		var gear_left: Array[GearData] = []
		var weights: Array = []
		for item: GearData in data.gear:
			if item != null and not owns(item) and item.rarity >= ItemData.Rarity.RARE:
				gear_left.append(item)
				weights.append(rarity_weight(GEAR_WEIGHT, item.rarity, row))
		var index := _weighted_index(rng, weights)
		if index >= 0:
			return gear_left[index]
	var found := _pick_found(rng, row, ItemData.Rarity.RARE)
	return found if found != null else _pick_found(rng, row)


## What glinting spot `spot` of the zone at stop `stop_id` holds (seeded; null if nothing can be
## found in this run).
func spot_item(stop_id: int, spot: int) -> ItemData:
	return _pick_found(CombatRng.new(_salted(stop_id * SPOT_SALT + spot * 7)), _row_of(stop_id))


## What roaming enemy `roamer` of the zone at stop `stop_id` drops when beaten: a seeded
## tuning.item_drop_percent chance of a found item, else null.
func drop_for(stop_id: int, roamer: int) -> ItemData:
	var rng := CombatRng.new(_salted(stop_id * DROP_SALT + roamer * 13))
	if rng.range_int(0, 99) >= tuning.item_drop_percent:
		return null
	return _pick_found(rng, _row_of(stop_id))


## A weight scaled by rarity at map row `row`: common as is, rare and legendary by their tuned
## shares, which grow each row (deeper stops turn up rarer things).
func rarity_weight(weight: int, rarity: int, row: int) -> int:
	match rarity:
		ItemData.Rarity.RARE:
			return CombatMath.percent(weight, tuning.item_rare_percent + row * tuning.item_rare_row_percent)
		ItemData.Rarity.LEGENDARY:
			return CombatMath.percent(weight, tuning.item_legendary_percent + row * tuning.item_legendary_row_percent)
	return weight


func _row_of(stop_id: int) -> int:
	return int(map.stop(stop_id).get("row", 0))


## One of the run's found items at least `min_rarity` rare, by find weight and rarity.
func _pick_found(rng: CombatRng, row: int, min_rarity: int = ItemData.Rarity.COMMON) -> ItemData:
	var pool: Array[ItemData] = []
	var weights: Array = []
	for item: ItemData in data.found_items:
		if item != null and item.rarity >= min_rarity:
			pool.append(item)
			weights.append(rarity_weight(item.find_weight, item.rarity, row))
	var index := _weighted_index(rng, weights)
	return pool[index] if index >= 0 else null


## A seeded pick by weight (-1 if every weight is 0).
static func _weighted_index(rng: CombatRng, weights: Array) -> int:
	var total := 0
	for w: Variant in weights:
		total += maxi(0, int(w))
	if total <= 0:
		return -1
	var roll := rng.range_int(0, total - 1)
	for i: int in weights.size():
		roll -= maxi(0, int(weights[i]))
		if roll < 0:
			return i
	return -1


func _salted(salt: int) -> int:
	return absi(run_seed * 31 + salt) % 2147483647 + 1


# --- gear -------------------------------------------------------------------------------------

## True if someone in the party wears this item.
func owns(item: GearData) -> bool:
	for slots: Array in gear:
		if slots.has(item):
			return true
	return false


## The loot a stop offers: up to tuning.run_loot_choices items the party does not own (seeded).
func loot_choices(stop_id: int) -> Array[GearData]:
	return _pick_gear(stop_id * LOOT_SALT, tuning.run_loot_choices, _row_of(stop_id))


## The gear a shop stop sells: up to tuning.run_shop_gear items the party does not own (seeded).
func shop_gear(stop_id: int) -> Array[GearData]:
	return _pick_gear(stop_id * SHOP_SALT, tuning.run_shop_gear, _row_of(stop_id))


## Up to `count` pieces the party does not wear, picked by rarity at map row `row` (seeded).
func _pick_gear(salt: int, count: int, row: int) -> Array[GearData]:
	var left: Array[GearData] = []
	for item: GearData in data.gear:
		if item != null and not owns(item):
			left.append(item)
	var rng := CombatRng.new(_salted(salt))
	var picked: Array[GearData] = []
	while picked.size() < count and not left.is_empty():
		var weights: Array = []
		for g: GearData in left:
			weights.append(rarity_weight(GEAR_WEIGHT, g.rarity, row))
		var index := _weighted_index(rng, weights)
		if index < 0:
			break
		picked.append(left.pop_at(index))
	return picked


func can_buy_gear(item: GearData) -> bool:
	return item != null and not owns(item) and gold >= item.price


## Pays for shop gear (the caller then has it in hand: wear it or sell it). False if it cannot
## be bought.
func buy_gear(item: GearData) -> bool:
	if not can_buy_gear(item):
		return false
	gold -= item.price
	return true


## Gold for selling a piece of gear.
func gear_sell_price(item: GearData) -> int:
	return sell_price(item.price) if item != null else 0


## Puts new gear `item` on character `slot` in gear slot `gear_slot` (gear never goes in the
## backpack). What was worn there is sold on the spot. HP never rises from putting gear on (no
## free heal), and is cut to a lower max. Returns the gold the old piece sold for, or -1 if the
## item cannot be worn there.
func wear(slot: int, gear_slot: int, item: GearData) -> int:
	if item == null or owns(item) or slot < 0 or slot >= gear.size() or gear_slot < 0 or gear_slot >= gear[slot].size():
		return -1
	var old: Variant = gear[slot][gear_slot]
	var sold := gear_sell_price(old as GearData) if old != null else 0
	gold += sold
	gear[slot][gear_slot] = item
	_clamp_hp()
	return sold


## New gear the party chose not to wear: sold on the spot. Returns the gold.
func sell_new_gear(item: GearData) -> int:
	var sold := gear_sell_price(item)
	gold += sold
	return sold


## Swaps what two gear slots hold (between heroes or on one hero). The first slot must hold
## something; the second may be empty. HP never rises from it and is cut to a lower max.
func swap_gear(from_slot: int, from_gear: int, to_slot: int, to_gear: int) -> bool:
	for pair: Array in [[from_slot, from_gear], [to_slot, to_gear]]:
		if pair[0] < 0 or pair[0] >= gear.size() or pair[1] < 0 or pair[1] >= gear[pair[0]].size():
			return false
	var moving: Variant = gear[from_slot][from_gear]
	if moving == null or (from_slot == to_slot and from_gear == to_gear):
		return false
	gear[from_slot][from_gear] = gear[to_slot][to_gear]
	gear[to_slot][to_gear] = moving
	_clamp_hp()
	return true


## The first empty gear slot of character `slot`, or -1.
func free_gear_slot(slot: int) -> int:
	return gear[slot].find(null)


func _clamp_hp() -> void:
	for slot: int in hp.size():
		hp[slot] = clampi(hp[slot], 1, max_hp(slot))
