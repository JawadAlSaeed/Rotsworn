class_name RunState
extends RefCounted
## One run in progress (DESIGN.md 8): the map, where the party is on it, the party's HP (carried
## from fight to fight), max HP boosts, gold, each hero's level, XP and attribute points (DESIGN.md
## 8.2), the gear each hero wears and the shared backpack (DESIGN.md 8.1). The run's rules live here as plain integer maths so they
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
## Long zones (DESIGN.md 8.5): the layout of a zone visit, a deal's find, a champion's prize chest.
const ZONE_SALT: int = 67867967
const OFFER_SALT: int = 86028121
const PRIZE_SALT: int = 104395301
## Phase 15 stops and acts (DESIGN.md 8.6 to 8.11).
const ACT_SALT: int = 122949829
const ELITE_SALT: int = 141650939
const EVENT_SALT: int = 160481183
const TREASURE_SALT: int = 179424673
const RESTOCK_SALT: int = 198491317
## Every piece of gear starts from this weight before rarity scales it.
const GEAR_WEIGHT: int = 100

var data: RunData
var tuning: Tuning
var run_seed: int = 1
## The oath this run is played at (0: none; DESIGN.md 8.15). Oaths 1 to this number are in force.
var oath: int = 0
## The current act's map (a new one each act, DESIGN.md 8.9).
var map: RunMap
## The act the party is in (0 = the first).
var act: int = 0
## Stops visited in the whole run (every act).
var visited: int = 0
## Attribute points each hero got at campfires (Train), on top of their levels' (DESIGN.md 8.11).
var bonus_points: Array[int] = []
## Events met this run (their ids): an event never comes twice (DESIGN.md 8.7).
var events_seen: Array[String] = []
## How many times the shop at the current stop was restocked (DESIGN.md 8.10).
var restocks: int = 0
## The stop the party is at (-1: before the first stop).
var at: int = -1
## Stops visited, in order.
var path: Array[int] = []
var gold: int = 0
## Per party slot: current HP, and max HP bought with tonics (percent of the character's normal
## max HP; levels and gear add to it in total_max_hp_percent).
var hp: Array[int] = []
var max_hp_percent: Array[int] = []
## Per party slot: Tonics (permanent max HP) the hero has drunk; tuning.tonic_max_per_hero is the
## most (card #175: gold must not turn into endless max HP).
var tonics_used: Array[int] = []
## Per party slot: the hero's level, and the XP counting toward their next one.
var levels: Array[int] = []
var xps: Array[int] = []
## Per party slot: points spent on each attribute (Attributes.COUNT ints).
var attributes: Array[Array] = []
## Per party slot, for heroes with a skill tree (DESIGN.md 8.4): the skills they know (ability
## ids, starters included) and the ones they bring into fights.
var unlocked: Array[Array] = []
var loadout: Array[Array] = []
## Per party slot, tuning.run_gear_slots entries: GearData or null.
var gear: Array[Array] = []
## The team gauge carried from the last fight into the next one (card #146).
var team_gauge: int = 0
## The shared backpack (items only: gear is always worn).
var backpack: Backpack
var fights_won: int = 0
var gold_earned: int = 0
## "" while the run goes on, then VICTORY or DEFEAT.
var result: String = ""


## A new run of `run_data` with this seed at oath `p_oath` (0: none; kept inside the ladder): a
## fresh map, the starting gold and HP (the oaths can lower both), level 1.
static func begin(run_data: RunData, p_tuning: Tuning, p_seed: int, p_oath: int = 0) -> RunState:
	var run := RunState.new()
	run.data = run_data
	run.tuning = p_tuning
	run.run_seed = p_seed
	run.oath = OathData.clamp_oath(run_data.oaths, p_oath)
	run.map = run._make_map(0)
	run.gold = maxi(0, p_tuning.run_start_gold + run.oath_total(&"start_gold_add"))
	run.backpack = Backpack.new(p_tuning.backpack_width, p_tuning.backpack_rows)
	for c: CharacterData in run_data.party:
		run.bonus_points.append(0)
		run.max_hp_percent.append(100)
		run.tonics_used.append(0)
		run.levels.append(1)
		run.xps.append(0)
		run.attributes.append(Attributes.empty())
		var known: Array = []
		if c.skill_tree != null:
			for skill: AbilityData in c.skill_tree.starters():
				known.append(skill.id)
		run.unlocked.append(known.duplicate())
		run.loadout.append(known.slice(0, p_tuning.skill_slots))
		var slots: Array = []
		slots.resize(p_tuning.run_gear_slots)
		run.gear.append(slots)
	var start_hp := OathData.start_hp_for(run_data.oaths, run.oath)
	for slot: int in run_data.party.size():
		run.hp.append(maxi(1, CombatMath.percent(run.max_hp(slot), start_hp)))
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
		"max_hp_percent": Array(max_hp_percent), "tonics_used": Array(tonics_used), "levels": Array(levels), "xps": Array(xps),
		"attributes": attributes.duplicate(true), "team_gauge": team_gauge, "gear": worn,
		"unlocked": unlocked.duplicate(true), "loadout": loadout.duplicate(true),
		"backpack": backpack.to_array(),
		"fights_won": fights_won, "gold_earned": gold_earned, "result": result,
		"act": act, "visited": visited, "bonus_points": Array(bonus_points), "events_seen": Array(events_seen),
		"restocks": restocks, "oath": oath,
	}


## A run of `run_data` set to to_dict() data. Null if the data does not fit (malformed, or a
## different run: unknown gear or items, wrong party size).
static func from_dict(run_data: RunData, p_tuning: Tuning, d: Dictionary) -> RunState:
	if typeof(d.get("seed")) != TYPE_INT:
		return null
	var run := RunState.begin(run_data, p_tuning, int(d.seed), int(d.get("oath", 0)) if typeof(d.get("oath")) == TYPE_INT else 0)
	return run if run.apply_dict(d) else null


## Sets this run (same seed) to to_dict() data. False (and nothing changed) if it does not fit.
func apply_dict(d: Dictionary) -> bool:
	for key: String in ["seed", "at", "gold", "team_gauge", "fights_won", "gold_earned", "act", "visited", "restocks",
			"oath"]:
		if typeof(d.get(key)) != TYPE_INT:
			return false
	if int(d.oath) < 0 or int(d.oath) > data.oaths.size():
		return false
	if int(d.seed) != run_seed or typeof(d.get("result")) != TYPE_STRING:
		return false
	for key: String in ["path", "hp", "max_hp_percent", "tonics_used", "levels", "xps", "attributes", "gear", "backpack",
			"unlocked", "loadout", "bonus_points", "events_seen"]:
		if not d.get(key) is Array:
			return false
	var size := party_size()
	for key: String in ["hp", "max_hp_percent", "tonics_used", "levels", "xps", "attributes", "gear", "unlocked",
			"loadout", "bonus_points"]:
		if (d[key] as Array).size() != size:
			return false
	for key: String in ["unlocked", "loadout"]:
		for slot: int in size:
			if not _skill_ids_fit(slot, d[key][slot]):
				return false
	for values: Variant in d.attributes:
		if not Attributes.is_valid(values):
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
	for key: String in ["path", "hp", "max_hp_percent", "tonics_used", "levels", "xps", "bonus_points"]:
		for v: Variant in d[key]:
			if typeof(v) != TYPE_INT:
				return false
	for v: Variant in d.events_seen:
		if typeof(v) != TYPE_STRING:
			return false
	if int(d.act) < 0 or int(d.act) >= acts().size():
		return false
	var act_map := map if int(d.act) == act else _make_map(int(d.act))
	if int(d.at) != -1 and act_map.stop(int(d.at)).is_empty():
		return false
	oath = int(d.oath)
	act = int(d.act)
	map = act_map
	visited = int(d.visited)
	restocks = int(d.restocks)
	bonus_points.assign(d.bonus_points)
	events_seen.assign(d.events_seen)
	at = int(d.at)
	path.assign(d.path)
	gold = int(d.gold)
	hp.assign(d.hp)
	max_hp_percent.assign(d.max_hp_percent)
	tonics_used.assign(d.tonics_used)
	team_gauge = int(d.team_gauge)
	levels.assign(d.levels)
	xps.assign(d.xps)
	var new_attributes: Array[Array] = []
	for values: Variant in d.attributes:
		var kept: Array[int] = []
		kept.assign(values)
		new_attributes.append(kept)
	attributes = new_attributes
	unlocked.assign((d.unlocked as Array).duplicate(true))
	loadout.assign((d.loadout as Array).duplicate(true))
	gear = new_gear
	backpack = new_pack
	fights_won = int(d.fights_won)
	gold_earned = int(d.gold_earned)
	result = String(d.result)
	return true


func party_size() -> int:
	return data.party.size()


# --- stats ------------------------------------------------------------------------------------

## Max HP percent with tonics, level, Vitality, gear and charms.
func total_max_hp_percent(slot: int) -> int:
	return max_hp_percent[slot] + (levels[slot] - 1) * tuning.run_level_hp_percent \
			+ attribute(slot, Attributes.Kind.VITALITY) * tuning.attr_vitality_hp_percent + bonus(slot, GearData.Effect.MAX_HP)


func max_hp(slot: int) -> int:
	return CombatSetup.scaled_max_hp(tuning, data.party[slot], total_max_hp_percent(slot))


## Power percent with level, Might, gear and charms (100 = the character's normal power).
func power_percent(slot: int) -> int:
	return 100 + (levels[slot] - 1) * tuning.run_level_power_percent \
			+ attribute(slot, Attributes.Kind.MIGHT) * tuning.attr_might_power_percent + bonus(slot, GearData.Effect.POWER)


func power(slot: int) -> int:
	return CombatMath.percent_min1(CombatMath.percent_min1(tuning.base_party_damage, data.party[slot].power_percent),
			power_percent(slot))


func speed(slot: int) -> int:
	return maxi(1, data.party[slot].speed + speed_bonus(slot))


## Speed added to the hero's own: Agility, gear and charms.
func speed_bonus(slot: int) -> int:
	return attribute(slot, Attributes.Kind.AGILITY) * tuning.attr_agility_speed + bonus(slot, GearData.Effect.SPEED)


## How much less enemy hits deal to this hero, in percent: Defense, gear and charms (capped as the
## fight caps it).
func defense_percent(slot: int) -> int:
	return mini(int(passives(slot).get(Passive.TOUGH, 0)), tuning.tough_max_percent)


## This hero's chance of a critical hit, in percent (the base, Luck).
func crit_percent(slot: int) -> int:
	return mini(100, tuning.crit_base_percent + int(passives(slot).get(Passive.CRIT, 0)))


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
	var defense := attribute(slot, Attributes.Kind.DEFENSE) * tuning.attr_defense_percent
	if defense > 0:
		found[Passive.TOUGH] = int(found.get(Passive.TOUGH, 0)) + defense
	var luck := attribute(slot, Attributes.Kind.LUCK) * tuning.attr_luck_crit_percent
	if luck > 0:
		found[Passive.CRIT] = luck
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
	# The event is picked before the party is there (event_of then picks a fresh one).
	var event := event_of(id) if int(map.stop(id).type) == RunMap.StopType.EVENT else null
	at = id
	path.append(id)
	visited += 1
	restocks = 0
	if event != null:
		events_seen.append(event.id)
	return true


# --- acts (DESIGN.md 8.9) -----------------------------------------------------------------------

var _acts: Array[ActData] = []


## The run's acts. A run without acts is one act made of its own zones and final fight.
func acts() -> Array[ActData]:
	if _acts.is_empty():
		if not data.acts.is_empty():
			_acts.assign(data.acts)
		else:
			var only := ActData.new()
			only.id = data.id
			only.display_name = data.display_name
			only.zones = data.zones
			only.final_encounter = data.final_encounter
			only.final_look = data.final_look
			only.final_map_icon_path = data.final_map_icon_path
			_acts.append(only)
	return _acts


## The current act (or act `index`).
func act_data(index: int = -1) -> ActData:
	var list := acts()
	return list[clampi(act if index < 0 else index, 0, list.size() - 1)]


func is_last_act() -> bool:
	return act >= acts().size() - 1


## The fight at the top of this act's map.
func final_encounter() -> EncounterData:
	return act_data().final_encounter


func final_look() -> StageLook:
	return act_data().final_look


## The current stop is this act's boss, beaten, and more acts follow (Main moves on with next_act).
func act_cleared() -> bool:
	return not is_over() and not is_last_act() and int(current().get("type", -1)) == RunMap.StopType.FINAL


## On to the next act: its own map from the start, and everyone heals act_heal_percent().
func next_act() -> bool:
	if is_last_act():
		return false
	act += 1
	map = _make_map(act)
	at = -1
	path.clear()
	for slot: int in hp.size():
		heal(slot, CombatMath.percent(max_hp(slot), act_heal_percent()))
	return true


## Act `index`'s map. The first act's comes from the run's seed alone (as before acts existed).
func _make_map(index: int) -> RunMap:
	var rng := CombatRng.new(run_seed if index == 0 else absi(run_seed * 31 + index * ACT_SALT) % 2147483647 + 1)
	var act_info := act_data(index)
	return RunMap.generate(rng, tuning, act_info.zones.size(), not act_info.elites.is_empty(),
			not act_info.events.is_empty())


# --- elite, event and treasure stops (DESIGN.md 8.6 to 8.8) -------------------------------------

## The elite fight at stop `stop_id` (seeded; deep acts and rows bring the deep version).
func elite_of(stop_id: int) -> EncounterData:
	var pool := act_data().elites
	if pool.is_empty():
		return null
	var rng := CombatRng.new(_salted(stop_id * ELITE_SALT + act * 31))
	var encounter := pool[rng.range_int(0, pool.size() - 1)]
	var row := int(map.stop(stop_id).get("row", 0))
	if (act_data().deep or row >= tuning.run_deep_row) and encounter.deep != null:
		return encounter.deep
	return encounter


## The event at stop `stop_id`: seeded, never one already met this run (unless every one was).
## Once the party is at the stop, it is the event go() recorded there.
func event_of(stop_id: int) -> EventData:
	var pool := act_data().events
	if pool.is_empty():
		return null
	if stop_id == at and int(current().get("type", -1)) == RunMap.StopType.EVENT and not events_seen.is_empty():
		for event: EventData in pool:
			if event != null and event.id == events_seen.back():
				return event
	var fresh: Array[EventData] = []
	for event: EventData in pool:
		if event != null and not events_seen.has(event.id):
			fresh.append(event)
	if fresh.is_empty():
		fresh.assign(pool)
	var rng := CombatRng.new(_salted(stop_id * EVENT_SALT + act * 37))
	return fresh[rng.range_int(0, fresh.size() - 1)]


## True if the party can take event choice `choice` (it can pay the price).
func can_choose(choice: EventChoiceData) -> bool:
	return choice != null and (choice.deal == null or can_take_offer(choice.deal))


## Takes event choice `index` at stop `stop_id`: its deal, and with its risk_percent (seeded) its
## risk deal too. Items come back for the caller to put in the backpack. Returns {ok: bool,
## text: String, items: Array[ItemData], risk: bool}.
func choose_event(choice: EventChoiceData, stop_id: int, index: int) -> Dictionary:
	var items: Array[ItemData] = []
	if not can_choose(choice):
		return {"ok": false, "text": "Not enough gold.", "items": items, "risk": false}
	var lines: Array[String] = []
	if not choice.done_text.is_empty():
		lines.append(choice.done_text)
	if choice.deal != null:
		var got := take_offer(choice.deal, stop_id, 1000 + index)
		if got.item != null:
			items.append(got.item)
		if String(got.text) != "Nothing happened.":
			lines.append(String(got.text))
	var risk := false
	var rng := CombatRng.new(_salted(stop_id * EVENT_SALT + index * 23 + act))
	if choice.risk_percent > 0 and choice.risk_deal != null and rng.range_int(0, 99) < choice.risk_percent:
		risk = true
		if not choice.risk_text.is_empty():
			lines.append(choice.risk_text)
		# A risk is never refused for lack of gold: it takes what there is.
		var hurt := choice.risk_deal.duplicate() as ZoneOfferData
		hurt.cost_gold = mini(hurt.cost_gold, gold)
		var got := take_offer(hurt, stop_id, 1050 + index)
		if got.item != null:
			items.append(got.item)
		if String(got.text) != "Nothing happened.":
			lines.append(String(got.text))
	return {"ok": true, "text": "\n".join(lines), "items": items, "risk": risk}


## What the chest of treasure stop `stop_id` holds: a prize like a locked chest's, picked as if the
## stop were a few rows deeper (rarer things).
func treasure_contents(stop_id: int) -> Resource:
	return _rare_prize(CombatRng.new(_salted(stop_id * TREASURE_SALT + act * 41)), _row_of(stop_id) + 4)


## Opening the treasure also gives tuning.run_treasure_gold. Returns it.
func take_treasure_gold() -> int:
	gold += tuning.run_treasure_gold
	gold_earned += tuning.run_treasure_gold
	return tuning.run_treasure_gold


# --- shop services and the campfire (DESIGN.md 8.10, 8.11) -------------------------------------

## True if item `uid` can go up a level (it can be combined and is not legendary yet).
func can_upgrade(uid: int) -> bool:
	var e := backpack.entry(uid)
	return not e.is_empty() and (e.item as ItemData).combinable() and entry_rarity(e) < ItemData.Rarity.LEGENDARY


## Item `uid` goes up a level, for `price` gold (0 at the campfire). False if it cannot.
func upgrade_item(uid: int, price: int = 0) -> bool:
	if not can_upgrade(uid) or gold < price:
		return false
	gold -= price
	backpack.entry(uid).level = level_of(backpack.entry(uid)) + 1
	return true


## Rotten items in the backpack (uids), for the shop to take away.
func rotten_uids() -> Array[int]:
	var found: Array[int] = []
	for e: Dictionary in backpack.entries:
		if (e.item as ItemData).rotten:
			found.append(int(e.uid))
	return found


## The shop takes rotten item `uid` away for cleanse_price() gold.
func cleanse(uid: int) -> bool:
	if not rotten_uids().has(uid) or gold < cleanse_price():
		return false
	gold -= cleanse_price()
	backpack.remove(uid)
	_clamp_hp()
	return true


## What the next restock costs: tuning.shop_restock_price, plus tuning.shop_restock_step for every
## restock already bought in this shop visit.
func restock_price() -> int:
	return shop_price(tuning.shop_restock_price + restocks * tuning.shop_restock_step)


## New wares on the shelves for restock_price() gold (shop_stock, shop_gear and shop_charms
## change).
func restock() -> bool:
	var price := restock_price()
	if gold < price:
		return false
	gold -= price
	restocks += 1
	return true


## Campfire Train: every hero gets tuning.rest_train_points attribute points.
func train() -> void:
	for slot: int in bonus_points.size():
		bonus_points[slot] += tuning.rest_train_points


## True when the current stop is deep enough for variant monsters (tuning run_deep_row).
func is_deep() -> bool:
	return act_data().deep or int(current().get("row", 0)) >= tuning.run_deep_row


## The zone of a zone stop (null for other stops).
func zone_of(stop: Dictionary) -> ZoneData:
	var index := int(stop.get("zone", -1))
	var zones := act_data().zones
	return zones[index] if index >= 0 and index < zones.size() else null


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


## Gold this run gets for an encounter, with the party's gold gear and gold charms, then the
## oaths' cut (Want, DESIGN.md 8.15; never below 0).
func gold_for(encounter: EncounterData) -> int:
	var extra := int(charm_totals().get(GearData.Effect.GOLD, 0))
	for slot: int in party_size():
		extra += gear_amount(slot, GearData.Effect.GOLD)
	var won := CombatMath.percent(encounter_gold(encounter), 100 + extra)
	if encounter.elite:
		won = CombatMath.percent(won, tuning.elite_gold_percent)
	return CombatMath.percent(won, maxi(0, 100 + oath_total(&"gold_percent_add")))


## The fight setup for an encounter in this run: the run's party, team ultimate, HP, max HP,
## power, speed, gear passives, the backpack's fight items and the enemies grown with depth.
func fight_setup(encounter: EncounterData, p_seed: int, opening: CombatSetup.Opening) -> CombatSetup:
	var setup := CombatSetup.from_encounter(encounter, tuning, p_seed, opening)
	setup.party = data.party.duplicate()
	setup.team_ultimate = data.team_ultimate
	setup.party_start_hp = hp.duplicate()
	for slot: int in party_size():
		setup.party_max_hp_percent.append(total_max_hp_percent(slot))
		setup.party_power_percent.append(power_percent(slot))
		setup.party_speed_bonus.append(speed_bonus(slot))
		setup.party_passives.append(passives(slot))
		setup.party_skills.append(loadout[slot].duplicate() if has_tree(slot) else [])
	for e: Dictionary in backpack.entries:
		if (e.item as ItemData).usable_in_fight():
			setup.items.append({"uid": int(e.uid), "item": e.item, "amount": entry_amount(e), "name": entry_name(e)})
	setup.start_team_gauge = clampi(team_gauge, 0, tuning.team_gauge_max)
	if not encounter.boss or tuning.run_enemy_scale_bosses:
		setup.enemy_hp_percent = enemy_hp_percent()
		setup.enemy_power_percent = enemy_power_percent()
	if encounter.elite:
		setup.enemy_hp_percent = CombatMath.percent(setup.enemy_hp_percent,
				maxi(1, tuning.elite_hp_percent + oath_total(&"elite_hp_percent_add")))
		setup.enemy_power_percent = CombatMath.percent(setup.enemy_power_percent,
				maxi(1, tuning.elite_power_percent + oath_total(&"elite_power_percent_add")))
	# Oaths (DESIGN.md 8.15): guards count as bosses; every enemy's power goes up on top.
	if encounter.boss or encounter.mini_boss:
		setup.enemy_hp_percent = CombatMath.percent(setup.enemy_hp_percent, 100 + oath_total(&"boss_hp_percent_add"))
		setup.enemy_power_percent = CombatMath.percent(setup.enemy_power_percent,
				100 + oath_total(&"boss_power_percent_add"))
	setup.enemy_power_percent = CombatMath.percent(setup.enemy_power_percent,
			100 + oath_total(&"enemy_power_percent_add"))
	return setup


## Enemy HP at the current stop's depth, in percent of their data (DESIGN.md 8.3).
func enemy_hp_percent() -> int:
	return 100 + _depth() * maxi(0, tuning.run_enemy_hp_row_percent + oath_total(&"enemy_hp_row_add"))


## Enemy power at the current stop's depth, in percent of their data.
func enemy_power_percent() -> int:
	return 100 + _depth() * maxi(0, tuning.run_enemy_power_row_percent + oath_total(&"enemy_power_row_add"))


## Map rows walked so far: the rows of the acts before this one, then this act's row.
func _depth() -> int:
	return act * (tuning.run_map_rows + 1) + maxi(0, int(current().get("row", 0)))


## Takes the items used in a fight out of the backpack (uids that are already gone are skipped).
func spend_items(uids: Array[int]) -> void:
	for uid: int in uids:
		backpack.remove(uid)
	_clamp_hp()


## A fight ended with these party HPs (per slot). A victory pays gold and XP (each hero their own,
## less for the downed) and gets the downed back up at tuning.run_downed_revive_hp; a defeat ends
## the run. Returns {gold, xp: per slot, levels: per slot (levels gained)}.
func finish_fight(fight_result: String, party_hp: Array[int], encounter: EncounterData) -> Dictionary:
	var none := {"gold": 0, "xp": _zeros(), "levels": _zeros()}
	if fight_result == ESCAPED:
		# Ran away (DESIGN.md 2.13): the HP carries on (a downed hero stands up at the floor),
		# no gold, no XP, the run goes on.
		for slot: int in hp.size():
			var left := party_hp[slot] if slot < party_hp.size() else hp[slot]
			hp[slot] = clampi(maxi(left, tuning.run_downed_revive_hp), 1, max_hp(slot))
		return none
	if fight_result != VICTORY:
		for slot: int in hp.size():
			hp[slot] = 0
		result = DEFEAT
		return none
	var gained := fight_xp(encounter, party_hp)
	for slot: int in hp.size():
		var after := party_hp[slot] if slot < party_hp.size() else hp[slot]
		hp[slot] = clampi(maxi(after, tuning.run_downed_revive_hp), 1, max_hp(slot))
	fights_won += 1
	var won := gold_for(encounter)
	gold += won
	gold_earned += won
	var up := _zeros()
	for slot: int in party_size():
		up[slot] = add_xp(slot, gained[slot])
	if int(current().get("type", -1)) == RunMap.StopType.FINAL and is_last_act():
		result = VICTORY
	return {"gold": won, "xp": gained, "levels": up}


## A fight ended with the team gauge at `value`: the next fight starts with
## team_gauge_carry_percent() of it (card #146).
func carry_team_gauge(value: int) -> void:
	team_gauge = CombatMath.percent(clampi(value, 0, tuning.team_gauge_max), team_gauge_carry_percent())


## The XP each hero gets for winning `encounter` with these HPs left: the encounter's XP for those
## standing, tuning.run_xp_downed_percent of it for the downed.
func fight_xp(encounter: EncounterData, party_hp: Array[int]) -> Array[int]:
	var full := encounter_xp(encounter)
	var shares: Array[int] = []
	for slot: int in party_size():
		var standing := slot >= party_hp.size() or party_hp[slot] > 0
		shares.append(full if standing else CombatMath.percent(full, tuning.run_xp_downed_percent))
	return shares


func _zeros() -> Array[int]:
	var zeros: Array[int] = []
	zeros.resize(party_size())
	zeros.fill(0)
	return zeros


# --- levels and attributes (DESIGN.md 8.2) ------------------------------------------------------

## XP hero `slot` needs from their level to the next.
func xp_to_next(slot: int) -> int:
	return tuning.run_xp_first_level + (levels[slot] - 1) * tuning.run_xp_level_step


func is_max_level(slot: int) -> bool:
	return levels[slot] >= tuning.run_max_level


## Levels `amount` more XP would give hero `slot` from here (for the end screen, before it is
## added).
func levels_from(slot: int, amount: int) -> int:
	var lv := levels[slot]
	var left := xps[slot] + amount
	while lv < tuning.run_max_level:
		var need := tuning.run_xp_first_level + (lv - 1) * tuning.run_xp_level_step
		if left < need:
			break
		left -= need
		lv += 1
	return lv - levels[slot]


## Adds XP to hero `slot`; each level up raises max HP and power, heals what max HP grew and gives
## attribute points. Returns levels gained.
func add_xp(slot: int, amount: int) -> int:
	var gained := 0
	xps[slot] += maxi(0, amount)
	while levels[slot] < tuning.run_max_level and xps[slot] >= xp_to_next(slot):
		xps[slot] -= xp_to_next(slot)
		var before := max_hp(slot)
		levels[slot] += 1
		gained += 1
		hp[slot] = mini(max_hp(slot), hp[slot] + max_hp(slot) - before)
	if is_max_level(slot):
		xps[slot] = 0
	return gained


## The highest level in the party (for summaries).
func top_level() -> int:
	var top := 1
	for lv: int in levels:
		top = maxi(top, lv)
	return top


## Points spent on one attribute.
func attribute(slot: int, kind: int) -> int:
	return int(attributes[slot][kind]) if slot < attributes.size() else 0


## Every attribute point hero `slot` has earned so far.
func earned_points(slot: int) -> int:
	return tuning.attr_start_points + (levels[slot] - 1) * tuning.attr_points_per_level + bonus_points[slot]


## Points hero `slot` has not spent yet.
func free_points(slot: int) -> int:
	return earned_points(slot) - Attributes.total(attributes[slot])


## True if any hero has points to spend.
func has_free_points() -> bool:
	for slot: int in party_size():
		if free_points(slot) > 0:
			return true
	return false


## Sets hero `slot`'s attribute points (spending, undoing and resetting are all this). False (and
## nothing changes) if it is malformed, spends more than they earned, or takes back so much max HP
## that the hero is too wounded to stand it (card #175). The HP they are missing stays exactly the
## same, so no change ever heals: a change that would push them under 1 HP is refused instead of
## clamped, because a clamp forgets missing HP and a respend would then hand it back.
func set_attributes(slot: int, values: Variant) -> bool:
	if slot < 0 or slot >= party_size() or not Attributes.is_valid(values):
		return false
	if Attributes.total(values) > earned_points(slot):
		return false
	if attributes_wound_blocked(slot, values):
		return false
	var missing := max_hp(slot) - hp[slot]
	var kept: Array[int] = []
	kept.assign(values)
	attributes[slot] = kept
	hp[slot] = clampi(max_hp(slot) - missing, 1, max_hp(slot))
	return true


## True if hero `slot` is too wounded to change their attribute points to `values`: with the
## same HP missing, the lower max HP would leave them under 1 HP.
func attributes_wound_blocked(slot: int, values: Variant) -> bool:
	if slot < 0 or slot >= party_size() or not Attributes.is_valid(values):
		return false
	var kept: Array[int] = []
	kept.assign(values)
	var old: Array[int] = []
	old.assign(attributes[slot])
	var missing := max_hp(slot) - hp[slot]
	attributes[slot] = kept
	var new_max := max_hp(slot)
	attributes[slot] = old
	return new_max - missing < 1


# --- skill trees (DESIGN.md 8.4, card #136) ----------------------------------------------------

## True if hero `slot` has a skill tree (without one they always have every skill).
func has_tree(slot: int) -> bool:
	return slot >= 0 and slot < party_size() and data.party[slot].skill_tree != null


func tree(slot: int) -> SkillTreeData:
	return data.party[slot].skill_tree if has_tree(slot) else null


## Every skill point hero `slot` has earned so far.
func earned_skill_points(slot: int) -> int:
	return (levels[slot] - 1) * tuning.skill_points_per_level


## What unlocking `ability_id` costs (its place in its branch; -1 if it is not in the tree).
func skill_cost(slot: int, ability_id: String) -> int:
	if not has_tree(slot):
		return -1
	var at := tree(slot).place_of(ability_id)
	if at.y < 0:
		return -1
	var costs := tuning.skill_tier_costs
	return costs[mini(at.y, costs.size() - 1)] if not costs.is_empty() else 0


func spent_skill_points(slot: int) -> int:
	var total := 0
	for id: Variant in unlocked[slot]:
		total += maxi(0, skill_cost(slot, String(id)))
	return total


func free_skill_points(slot: int) -> int:
	return earned_skill_points(slot) - spent_skill_points(slot)


## True if hero `slot` can learn `ability_id` now: in their tree, not known yet, the skill above it
## known, and enough free points.
func can_unlock(slot: int, ability_id: String) -> bool:
	var cost := skill_cost(slot, ability_id)
	if cost < 0 or unlocked[slot].has(ability_id) or cost > free_skill_points(slot):
		return false
	var parent := tree(slot).parent_of(ability_id)
	return parent == null or unlocked[slot].has(parent.id)


## Learns a skill; it is brought into fights at once if there is a free slot.
func unlock(slot: int, ability_id: String) -> bool:
	if not can_unlock(slot, ability_id):
		return false
	unlocked[slot].append(ability_id)
	if loadout[slot].size() < tuning.skill_slots:
		loadout[slot].append(ability_id)
	return true


## Sets the skills hero `slot` brings: known skills, each once, at most tuning.skill_slots.
func set_loadout(slot: int, ids: Variant) -> bool:
	if not has_tree(slot) or not ids is Array or (ids as Array).size() > tuning.skill_slots:
		return false
	var seen := {}
	for id: Variant in ids:
		if typeof(id) != TYPE_STRING or not unlocked[slot].has(String(id)) or seen.has(String(id)):
			return false
		seen[String(id)] = true
	loadout[slot] = (ids as Array).duplicate()
	return true


## The bot's way: learns whatever it can, cheapest first (the first branch on a tie), and brings
## new skills while there is room.
func auto_skills(slot: int) -> void:
	if not has_tree(slot):
		return
	while true:
		var best := ""
		var best_cost := 1 << 30
		for skill: AbilityData in tree(slot).all_skills():
			if can_unlock(slot, skill.id) and skill_cost(slot, skill.id) < best_cost:
				best = skill.id
				best_cost = skill_cost(slot, skill.id)
		if best.is_empty():
			return
		unlock(slot, best)


## True if `ids` is a list of skills in hero `slot`'s tree (any list is fine without a tree only
## if it is empty).
func _skill_ids_fit(slot: int, ids: Variant) -> bool:
	if not ids is Array:
		return false
	for id: Variant in ids:
		if typeof(id) != TYPE_STRING or not has_tree(slot) or tree(slot).place_of(String(id)).x < 0:
			return false
	return true


## The bot's way to spend: each free point goes to the attribute with the fewest points (the
## first on a tie), so a hero grows evenly.
func auto_spend(slot: int) -> void:
	var values: Array[int] = []
	values.assign(attributes[slot])
	for i: int in free_points(slot):
		var low := 0
		for kind: int in Attributes.COUNT:
			if values[kind] < values[low]:
				low = kind
		values[low] += 1
	set_attributes(slot, values)


# --- rest and care ----------------------------------------------------------------------------

## Rest: everyone heals rest_heal_percent() of their max HP. Returns HP healed per slot.
func rest() -> Array[int]:
	var healed: Array[int] = []
	for slot: int in hp.size():
		healed.append(heal(slot, CombatMath.percent(max_hp(slot), rest_heal_percent())))
	return healed


# --- oaths (DESIGN.md 8.15) ---------------------------------------------------------------------

## The oath modifier `field` (an OathData property) summed over oaths 1 to this run's.
func oath_total(field: StringName) -> int:
	return OathData.total(data.oaths, oath, field)


## Percent of max HP a campfire Rest heals, with the oaths.
func rest_heal_percent() -> int:
	return clampi(tuning.run_rest_heal_percent + oath_total(&"rest_heal_percent_add"), 0, 100)


## Percent of max HP everyone heals between acts, with the oaths.
func act_heal_percent() -> int:
	return clampi(tuning.run_act_heal_percent + oath_total(&"act_heal_percent_add"), 0, 100)


## Percent of the team gauge that carries into the next fight, with the oaths.
func team_gauge_carry_percent() -> int:
	return clampi(tuning.run_team_gauge_carry_percent + oath_total(&"team_gauge_carry_percent_add"), 0, 100)


## What a shop charges for something whose normal price is `base`, with the oaths. Selling pays on
## the normal price (sell_price), so a dearer shop never pays more.
func shop_price(base: int) -> int:
	return CombatMath.percent(base, maxi(0, 100 + oath_total(&"shop_price_percent_add")))


## What a shop item costs.
func item_price(item: ItemData) -> int:
	return shop_price(item.price)


## What a piece of shop gear costs.
func gear_price(item: GearData) -> int:
	return shop_price(item.price)


func cleanse_price() -> int:
	return shop_price(tuning.shop_cleanse_price)


func upgrade_price() -> int:
	return shop_price(tuning.shop_upgrade_price)


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
	return item != null and gold >= item_price(item)


## Pays for `item` (the caller puts it in the backpack). False if the gold is short.
func pay_for(item: ItemData) -> bool:
	if not can_afford(item):
		return false
	gold -= item_price(item)
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
	if item.effect == ItemData.Effect.MAX_HP_ONE:
		for slot: int in party_size():
			if tonics_left(slot) > 0:
				return true
		return false
	return true


## The items (not charms) a shop stop has on its shelves: up to tuning.run_shop_items of the run's
## shop list, picked for the stop (seeded; a restock picks again), in the list's order.
func shop_stock(stop_id: int) -> Array[ItemData]:
	var left: Array[ItemData] = []
	for item: ItemData in data.shop_items:
		if item != null:
			left.append(item)
	var rng := CombatRng.new(_salted(stop_id * SHOP_SALT + 29 + restocks * RESTOCK_SALT))
	var picked: Array[ItemData] = []
	while picked.size() < tuning.run_shop_items and not left.is_empty():
		picked.append(left.pop_at(rng.range_int(0, left.size() - 1)))
	var ordered: Array[ItemData] = []
	for item: ItemData in data.shop_items:
		if picked.has(item):
			ordered.append(item)
	return ordered


## The charms a shop stop sells: up to tuning.run_shop_charms of the run's found charms, never
## rotten, picked by rarity at the stop's row (seeded).
func shop_charms(stop_id: int) -> Array[ItemData]:
	var left: Array[ItemData] = []
	for item: ItemData in data.found_items:
		if item != null and item.is_charm() and not item.rotten and not left.has(item):
			left.append(item)
	var rng := CombatRng.new(_salted(stop_id * SHOP_SALT + 17 + restocks * RESTOCK_SALT + act * 53))
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
	var moved := backpack.move(uid, x, y, turn)
	_clamp_hp()
	return moved


## Throws item `uid` away (it is gone).
func drop_item(uid: int) -> bool:
	var gone := backpack.remove(uid) != null
	_clamp_hp()
	return gone


## True if backpack item `uid` can be used on the map now (on character `slot` if it needs one).
func can_use_item(uid: int, slot: int) -> bool:
	var e := backpack.entry(uid)
	if e.is_empty():
		return false
	var item := e.item as ItemData
	if not item.usable_on_map():
		return false
	if item.needs_target() and (slot < 0 or slot >= hp.size()):
		return false
	return not (item.effect == ItemData.Effect.MAX_HP_ONE and tonics_left(slot) <= 0)


## Tonics hero `slot` can still drink this run (tuning.tonic_max_per_hero is the most).
func tonics_left(slot: int) -> int:
	if slot < 0 or slot >= tonics_used.size():
		return 0
	return maxi(0, tuning.tonic_max_per_hero - tonics_used[slot])


## Why backpack item `uid` cannot be used on hero `slot` right now ("" when it can), for screens
## to show next to a greyed hero.
func use_blocked_reason(uid: int, slot: int) -> String:
	if can_use_item(uid, slot):
		return ""
	var e := backpack.entry(uid)
	if not e.is_empty() and (e.item as ItemData).effect == ItemData.Effect.MAX_HP_ONE and slot >= 0 and slot < hp.size():
		return "%s has drunk all %d Tonics they can." % [data.party[slot].display_name, tuning.tonic_max_per_hero]
	return "It cannot be used on them."


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
			tonics_used[slot] += 1
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
	_clamp_hp()
	return true


## Combines a new item (not in the backpack yet, level 0) into item `into`.
func combine_new(item: ItemData, into: int) -> bool:
	var target := backpack.entry(into)
	if target.is_empty() or not _combines(item, 0, target):
		return false
	target.level = level_of(target) + 1
	_clamp_hp()
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
## {op: "swap_gear", from: [slot, gear_slot], to: [slot, gear_slot]},
## {op: "attributes", slot, values: [Attributes.COUNT ints]},
## {op: "unlock", slot, ability}, {op: "loadout", slot, abilities: [ids]}.
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
		"attributes":
			return ints.call(["slot"]) and set_attributes(int(op.slot), op.get("values"))
		"unlock":
			return ints.call(["slot"]) and typeof(op.get("ability")) == TYPE_STRING \
					and int(op.slot) >= 0 and int(op.slot) < party_size() and unlock(int(op.slot), String(op.ability))
		"loadout":
			return ints.call(["slot"]) and int(op.slot) >= 0 and int(op.slot) < party_size() \
					and set_loadout(int(op.slot), op.get("abilities"))
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
	_clamp_hp()
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


## What locked chest number `chest` of the zone at stop `stop_id` holds (seeded; the chest index
## keeps two chests in one visit apart): tuning.chest_gear_percent of the time a piece of rare or
## better gear the party does not wear, else a rare or better item (any item if the run has none
## that rare). GearData or ItemData; null if nothing at all is left.
func chest_contents(stop_id: int, chest: int = 0) -> Resource:
	return _rare_prize(CombatRng.new(_salted(stop_id * CHEST_SALT + chest * 31)), _row_of(stop_id))


## What the prize chest of champion `roamer` in the zone at stop `stop_id` holds (DESIGN.md 8.5):
## the same kind of prize as a locked chest, seeded apart from it.
func prize_contents(stop_id: int, roamer: int) -> Resource:
	return _rare_prize(CombatRng.new(_salted(stop_id * PRIZE_SALT + roamer * 17)), _row_of(stop_id))


func _rare_prize(rng: CombatRng, row: int) -> Resource:
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


## The seed of the zone visit at stop `stop_id` (DESIGN.md 8.5): which sections, enemies, seals,
## shrines and wanderer it has. The same on every machine.
func zone_seed(stop_id: int) -> int:
	return _salted(stop_id * ZONE_SALT)


## True if the party can pay for the shrine or wanderer's deal (HP prices can always be paid: a
## hero never drops below 1 HP for one).
func can_take_offer(offer: ZoneOfferData) -> bool:
	return offer != null and gold >= offer.cost_gold


## Takes deal `index` of the zone at stop `stop_id` (DESIGN.md 8.5): pays its price and gives its
## gifts, all but the item, which comes back for the caller to put in the backpack. Returns
## {ok: bool, text: String (what happened, one line), item: ItemData or null}. Nothing changes if
## the gold is short.
func take_offer(offer: ZoneOfferData, stop_id: int, index: int) -> Dictionary:
	if not can_take_offer(offer):
		return {"ok": false, "text": "Not enough gold.", "item": null}
	var parts: Array[String] = []
	gold -= offer.cost_gold
	if offer.cost_hp_percent > 0:
		for slot: int in hp.size():
			if hp[slot] > 0:
				hp[slot] = maxi(1, hp[slot] - CombatMath.percent(max_hp(slot), offer.cost_hp_percent))
		parts.append("Everyone lost %d%% HP" % offer.cost_hp_percent)
	if offer.heal_percent > 0:
		for slot: int in hp.size():
			heal(slot, CombatMath.percent(max_hp(slot), offer.heal_percent))
		parts.append("Everyone healed %d%%" % offer.heal_percent)
	if offer.gold > 0:
		gold += offer.gold
		gold_earned += offer.gold
		parts.append("+%d gold" % offer.gold)
	if offer.xp > 0:
		for slot: int in xps.size():
			add_xp(slot, offer.xp)
		parts.append("+%d XP each" % offer.xp)
	if offer.team_gauge > 0:
		team_gauge = mini(tuning.team_gauge_max, team_gauge + offer.team_gauge)
		parts.append("Team gauge +%d" % offer.team_gauge)
	var item: ItemData = offer.item
	if item == null and offer.find_rarity >= 0:
		var rng := CombatRng.new(_salted(stop_id * OFFER_SALT + index * 19))
		item = _pick_found(rng, _row_of(stop_id), offer.find_rarity)
		if item == null:
			item = _pick_found(rng, _row_of(stop_id))
	if item != null:
		parts.append("Got: %s" % item.display_name)
	return {"ok": true, "text": ". ".join(parts) if not parts.is_empty() else "Nothing happened.", "item": item}


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


## How deep stop `stop_id` is for rarity: later acts count the rows of the acts before them.
func _row_of(stop_id: int) -> int:
	return act * (tuning.run_map_rows + 1) + int(map.stop(stop_id).get("row", 0))


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
	# Each act's stops are numbered from 0 again: the act keeps their seeds apart.
	return absi(run_seed * 31 + salt + act * 1000003) % 2147483647 + 1


# --- gear -------------------------------------------------------------------------------------

## True if someone in the party wears this item.
func owns(item: GearData) -> bool:
	for slots: Array in gear:
		if slots.has(item):
			return true
	return false


## How many pieces of gear the spoils offer: tuning.run_loot_choices, fewer with the oaths (never
## fewer than one).
func loot_choice_count() -> int:
	return maxi(1, tuning.run_loot_choices + oath_total(&"loot_choices_add"))


## The loot a stop offers: up to loot_choice_count() items the party does not own (seeded).
func loot_choices(stop_id: int) -> Array[GearData]:
	return _pick_gear(stop_id * LOOT_SALT + act * 43, loot_choice_count(), _row_of(stop_id),
			tuning.run_spoils_min_rarity)


## The gear a shop stop sells: up to tuning.run_shop_gear items the party does not own (seeded).
func shop_gear(stop_id: int) -> Array[GearData]:
	return _pick_gear(stop_id * SHOP_SALT + restocks * RESTOCK_SALT + act * 47, tuning.run_shop_gear, _row_of(stop_id))


## Up to `count` pieces the party does not wear, picked by rarity at map row `row` (seeded), of at
## least `min_rarity` while the run still has enough such pieces.
func _pick_gear(salt: int, count: int, row: int, min_rarity: int = 0) -> Array[GearData]:
	var left: Array[GearData] = []
	for item: GearData in data.gear:
		if item != null and not owns(item) and item.rarity >= min_rarity:
			left.append(item)
	if left.size() < count:
		for item: GearData in data.gear:
			if item != null and not owns(item) and not left.has(item):
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
	return item != null and not owns(item) and gold >= gear_price(item)


## Pays for shop gear (the caller then has it in hand: wear it or sell it). False if it cannot
## be bought.
func buy_gear(item: GearData) -> bool:
	if not can_buy_gear(item):
		return false
	gold -= gear_price(item)
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
