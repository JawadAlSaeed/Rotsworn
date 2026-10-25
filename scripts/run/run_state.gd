class_name RunState
extends RefCounted
## One run in progress (DESIGN.md 8): the map, where the party is on it, the party's HP (carried
## from fight to fight), max HP boosts, gold, each hero's level, XP and attribute points (DESIGN.md
## 8.2), the Relics given to each hero (8.17, 8.24), the shared backpack (DESIGN.md 8.1) and the
## curses on the party (card #332). The run's rules live here as plain integer maths so they
## are unit-tested; screens only call these functions and show the result.

const VICTORY := "victory"
## A fight left with Run (DESIGN.md 2.13).
const ESCAPED := "escaped"
const DEFEAT := "defeat"
## Salts for the seeded picks of each stop (loot and shop gear differ at the same stop).
const LOOT_SALT: int = 7919
const SHOP_SALT: int = 104729
## Salts for what a Fight stop's fight drops (DESIGN.md 8.22) and a deal's find or Relic (an
## event's, a pact's). Their values were the walkable zones' (8.5), so a seed gives the same drops.
const DROP_SALT: int = 32452843
const OFFER_SALT: int = 86028121
## Phase 15 stops and acts (DESIGN.md 8.6 to 8.11).
const ACT_SALT: int = 122949829
const ELITE_SALT: int = 141650939
const EVENT_SALT: int = 160481183
const TREASURE_SALT: int = 179424673
const RESTOCK_SALT: int = 198491317
## Phase 16 "?" stops: the ambush roll of a stop, and the random picks of an event's costs.
const AMBUSH_SALT: int = 217645177
const COST_SALT: int = 236887691
## Every piece of gear starts from this weight before rarity scales it.
const GEAR_WEIGHT: int = 100
## Seeds the spoils' guaranteed rot-touched pick apart from the normal picks.
const ROT_GEAR_SALT: int = 253645133
## Seeds which starting pacts a run offers (card #285).
const PACT_SALT: int = 295075153
## Phase 26 (DESIGN.md 8.22): a Fight stop's fight, and the weather of every run fight but the boss's.
const FIGHT_SALT: int = 405000041
const FIGHT_WEATHER_SALT: int = 426000017
## Phase 26 (DESIGN.md 8.22, map rules 4): whether an Elite stop holds its place's guard.
const ELITE_GUARD_SALT: int = 447000011
## The map rules a new run is made with (see map_rules).
const MAP_RULES: int = 4
## Which gear a pick draws from (see _pick_gear).
enum GearPool { ANY, NORMAL, ROT_TOUCHED }

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
## Shop items (by shelf index) bought at the current stop; a restock empties it. Saved, so a continued
## run does not put a bought item back on the shelf (card #197).
var shop_sold: Array[int] = []
## The current stop already had its irreversible action (an event choice taken, a chest opened) and
## `stop_text` is what the screen then shows. Saved, so Continue resumes after it, never replays its
## random results (card #197).
var stop_done: bool = false
var stop_text: String = ""
## "?" stops passed since the last ambush fight: each one raises the chance that the next "?" stop
## is an ambush (tuning unknown_fight_percent_*, DESIGN.md 8.7). Any ambush starts it over.
var ambush_streak: int = 0
## The encounter ("" none) the party must fight at the current stop: a "?" stop that turned into an
## ambush, or an event choice that ended in one. Cleared when that fight ends.
var ambush_id: String = ""
## The ambush ends in spoils (one piece of gear), like an elite's.
var ambush_spoils: bool = false
## The stop the party is at (-1: before the first stop).
var at: int = -1
## Stops visited, in order.
var path: Array[int] = []
var gold: int = 0
## Per party slot: current HP, and the max HP kept for good (percent of the character's normal
## max HP: events and pacts lower it; levels and gear add to it in total_max_hp_percent).
var hp: Array[int] = []
var max_hp_percent: Array[int] = []
## Per party slot: the hero's level, and the XP counting toward their next one.
var levels: Array[int] = []
var xps: Array[int] = []
## Per party slot: points spent on each attribute (Attributes.COUNT ints).
var attributes: Array[Array] = []
## Per party slot, for heroes with a skill tree (DESIGN.md 8.4): the skills they know (ability
## ids, starters included) and the ones they bring into fights.
var unlocked: Array[Array] = []
var loadout: Array[Array] = []
## Per party slot: the Relics (GearData) given to that hero, in the order given (DESIGN.md 8.24):
## any number, no slots, kept until the run ends.
var gear: Array[Array] = []
## The run's Relics (DESIGN.md 8.17, 8.24): id -> 1 for every Relic in the run, given to a hero (a
## Relic still waiting for one comes only from tests and old saves). No levels and no copies: a Relic
## the run has never turns up again in it. Main banks them into the Relic book (RelicFile.bank)
## when the run saves and when it ends.
var relics: Dictionary = {}
## Every Relic in the Relic book before this run (id -> 1; online the host's): the end screen's
## "what you keep" line, and only a find the book lacks is tagged "New" (LootScreen.new_tag).
var relics_at_start: Dictionary = {}
## Per party slot: the starting Relics that hero may still take from a Relic book (DESIGN.md 8.24,
## card #328), start_relic_count() each at the start; 0 once taken or skipped. Main shows the pick
## step while any is above 0 (start_pending), before the pact and the first stop.
var start_left: Array[int] = []
## The run's starting Relics (id -> 1): taken from a Relic book, not found in this run, so nobody
## banks them (online each player's come from their own book) and the end screen never calls them new.
var start_relics: Dictionary = {}
## The Relics on offer at this stop (ids, in the order shown): the rotten chest's pick (pick 1 of
## them and give it to a hero, DESIGN.md 8.24; empty once one is taken) or the shop's shelves (kept
## as they were first shown, so a Relic bought there keeps its place). Saved and sent, so Continue and
## every machine show the same. Empty at every new stop.
var stop_relics: Array[String] = []
## The team gauge carried from the last fight into the next one (card #146).
var team_gauge: int = 0
## The shared backpack (consumables only, card #332: gear is always worn, treasure turns into gold
## and curses sit on the party).
var backpack: Backpack
## The curses on the party (card #332): the ids of curse items (ItemData.Kind.CURSE), one per curse
## taken, in the order taken (two of the same hurt twice). They are not in the pack: each hurts every
## hero its rot_percent at the start of their turns in fights until a shop's Cleanse takes it away.
var curses: Array[String] = []
var fights_won: int = 0
var gold_earned: int = 0
## Per party slot: [parried, dodged, jumped, hits taken] over the whole run (card #283), from each
## fight's FightRecap.
var defence: Array[Array] = []
## The last fight was a guard or an elite won without a hit taken (card #283): its spoils offer one
## more choice.
var flawless: bool = false
## The starting pact (card #285) is still to be offered: before the first stop of a run that is not
## the player's first.
var pact_pending: bool = false
## Sharpened at the campfire before the boss (card #287): every hero starts the boss fight with
## tuning.sharpen_ap more AP.
var sharpened: bool = false
## The treasure stop's rotten chest was the one opened (card #287): the screen shows it open.
var stop_rotten: bool = false
## The map rules the run was made with: 4 since the guards joined the Elite stops (no Guard stops,
## an Elite stop may hold its place's guard, DESIGN.md 8.22), 3 in early phase 26 (a row of Guard
## stops), 2 since phase 21 (rows that move, the crowned elite, card #286), 1 before; a run keeps the
## rules it was made with, so it continues on the map it had.
var map_rules: int = MAP_RULES
## "" while the run goes on, then VICTORY or DEFEAT.
var result: String = ""


## A new run of `run_data` with this seed at oath `p_oath` (0: none; kept inside the ladder): a
## fresh map, the starting gold and HP (the oaths can lower both), level 1. `collection`: the Relic
## book from earlier runs (none: a first run); every hero may take start_relic_count() Relics from a
## book in the pick step (start_left).
static func begin(run_data: RunData, p_tuning: Tuning, p_seed: int, p_oath: int = 0,
		collection: RelicCollection = null) -> RunState:
	var run := RunState.new()
	run.data = run_data
	run.tuning = p_tuning
	run.run_seed = p_seed
	run.oath = OathData.clamp_oath(run_data.oaths, p_oath)
	run.map = run._make_map(0)
	run.gold = maxi(0, p_tuning.run_start_gold + run.oath_total(&"start_gold_add"))
	run.backpack = Backpack.new(p_tuning.backpack_pockets)
	for c: CharacterData in run_data.party:
		run.bonus_points.append(0)
		run.max_hp_percent.append(100)
		run.levels.append(1)
		run.xps.append(0)
		run.attributes.append(Attributes.empty())
		var known: Array = []
		if c.skill_tree != null:
			for skill: AbilityData in c.skill_tree.starters():
				known.append(skill.id)
		run.unlocked.append(known.duplicate())
		run.loadout.append(known.slice(0, p_tuning.skill_slots))
		run.gear.append([])
		run.defence.append([0, 0, 0, 0])
		run.start_left.append(run.start_relic_count())
	if collection != null:
		run._take_collection(collection)
	run.pact_pending = not run.relics_at_start.is_empty() and not run_data.pacts.is_empty() \
			and p_tuning.run_pact_choices > 0
	var start_hp := OathData.start_hp_for(run_data.oaths, run.oath)
	for slot: int in run_data.party.size():
		run.hp.append(maxi(1, CombatMath.percent(run.max_hp(slot), start_hp)))
	return run


## Everything that changes during the run as plain data (gear and items by id), for online play:
## the host sends it and the other machines show it (DESIGN.md 9.2). The map is rebuilt from the
## seed.
func to_dict() -> Dictionary:
	var given: Array = []
	for list: Array in gear:
		var ids: Array = []
		for item: Variant in list:
			ids.append((item as GearData).id)
		given.append(ids)
	return {
		"seed": run_seed, "at": at, "path": Array(path), "gold": gold, "hp": Array(hp),
		"max_hp_percent": Array(max_hp_percent), "levels": Array(levels), "xps": Array(xps),
		"attributes": attributes.duplicate(true), "team_gauge": team_gauge, "gear": given,
		"unlocked": unlocked.duplicate(true), "loadout": loadout.duplicate(true),
		"backpack": backpack.to_array(), "curses": Array(curses),
		"fights_won": fights_won, "gold_earned": gold_earned, "result": result,
		"act": act, "visited": visited, "bonus_points": Array(bonus_points), "events_seen": Array(events_seen),
		"restocks": restocks, "oath": oath, "shop_sold": Array(shop_sold), "stop_done": stop_done, "stop_text": stop_text,
		"ambush_streak": ambush_streak, "ambush_id": ambush_id, "ambush_spoils": ambush_spoils,
		"relics": relics.duplicate(), "relics_start": relics_at_start.duplicate(),
		"defence": defence.duplicate(true), "flawless": flawless, "pact_pending": pact_pending, "sharpened": sharpened,
		"stop_rotten": stop_rotten, "stop_relics": Array(stop_relics), "map_rules": map_rules,
		"start_left": Array(start_left), "start_relics": start_relics.duplicate(),
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
			"oath", "ambush_streak"]:
		if typeof(d.get(key)) != TYPE_INT:
			return false
	if int(d.ambush_streak) < 0 or typeof(d.get("ambush_id")) != TYPE_STRING or typeof(d.get("ambush_spoils")) != TYPE_BOOL:
		return false
	if int(d.oath) < 0 or int(d.oath) > data.oaths.size():
		return false
	if int(d.seed) != run_seed or typeof(d.get("result")) != TYPE_STRING:
		return false
	for key: String in ["path", "hp", "max_hp_percent", "levels", "xps", "attributes", "gear", "backpack",
			"unlocked", "loadout", "bonus_points", "events_seen", "curses"]:
		if not d.get(key) is Array:
			return false
	var size := party_size()
	for key: String in ["hp", "max_hp_percent", "levels", "xps", "attributes", "gear", "unlocked",
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
	# Each hero's Relics: known ids, each Relic given to one hero only.
	var new_gear: Array[Array] = []
	var given := {}
	for ids: Variant in d.gear:
		if not ids is Array:
			return false
		var list: Array = []
		for id: Variant in ids:
			if typeof(id) != TYPE_STRING or not by_id.has(String(id)) or given.has(String(id)):
				return false
			given[String(id)] = true
			list.append(by_id[String(id)])
		new_gear.append(list)
	var known_items := items_by_id()
	var new_pack := Backpack.from_array(d.backpack, known_items)
	if new_pack == null:
		return false
	# The curses: ids of curse items this run knows.
	var new_curses: Array[String] = []
	for v: Variant in d.curses:
		if typeof(v) != TYPE_STRING or not known_items.has(String(v)) or not (known_items[String(v)] as ItemData).is_curse():
			return false
		new_curses.append(String(v))
	for key: String in ["path", "hp", "max_hp_percent", "levels", "xps", "bonus_points"]:
		for v: Variant in d[key]:
			if typeof(v) != TYPE_INT:
				return false
	for v: Variant in d.events_seen:
		if typeof(v) != TYPE_STRING:
			return false
	if int(d.act) < 0 or int(d.act) >= acts().size():
		return false
	if String(d.ambush_id) != "" and _find_ambush(String(d.ambush_id)) == null:
		return false
	# Optional (older saves lack them): what the current stop already did.
	var sold: Array[int] = []
	if d.has("shop_sold"):
		if not d.shop_sold is Array:
			return false
		for v: Variant in d.shop_sold:
			if typeof(v) != TYPE_INT or int(v) < 0:
				return false
			sold.append(int(v))
	if (d.has("stop_done") and typeof(d.stop_done) != TYPE_BOOL) or (d.has("stop_text") and typeof(d.stop_text) != TYPE_STRING):
		return false
	# A run saved before phase 21 keeps its map rules (card #286): its map does not change under it.
	var rules := int(d.map_rules) if typeof(d.get("map_rules")) == TYPE_INT else 1
	if rules < 1 or rules > MAP_RULES:
		return false
	var act_map := map if int(d.act) == act and rules == map_rules else _make_map(int(d.act), rules)
	if int(d.at) != -1 and act_map.stop(int(d.at)).is_empty():
		return false
	var relic_state := _relic_state_of(d, given, by_id)
	if relic_state.is_empty():
		return false
	# Optional (saves from before card #283 lack them): the run's defence and a flawless spoils.
	var new_defence := _defence_of(d.get("defence"))
	if (d.has("defence") and new_defence.is_empty()) or (d.has("flawless") and typeof(d.flawless) != TYPE_BOOL):
		return false
	if (d.has("pact_pending") and typeof(d.pact_pending) != TYPE_BOOL) or (d.has("sharpened") and typeof(d.sharpened) != TYPE_BOOL) \
			or (d.has("stop_rotten") and typeof(d.stop_rotten) != TYPE_BOOL):
		return false
	# Optional (saves from before card #328 lack it: no starting pick waits).
	var new_start_left: Array[int] = []
	if d.has("start_left"):
		if not d.start_left is Array or (d.start_left as Array).size() != size:
			return false
		for v: Variant in d.start_left:
			if typeof(v) != TYPE_INT or int(v) < 0:
				return false
			new_start_left.append(int(v))
	else:
		for slot: int in size:
			new_start_left.append(0)
	var new_start_relics := {}
	if d.has("start_relics"):
		if not d.start_relics is Dictionary:
			return false
		for id: Variant in d.start_relics:
			if typeof(id) != TYPE_STRING or not (relic_state.relics as Dictionary).has(String(id)):
				return false
			new_start_relics[String(id)] = 1
	oath = int(d.oath)
	act = int(d.act)
	map_rules = rules
	map = act_map
	visited = int(d.visited)
	restocks = int(d.restocks)
	shop_sold = sold
	stop_done = bool(d.get("stop_done", false))
	stop_text = String(d.get("stop_text", ""))
	ambush_streak = int(d.ambush_streak)
	ambush_id = String(d.ambush_id)
	ambush_spoils = bool(d.ambush_spoils)
	bonus_points.assign(d.bonus_points)
	events_seen.assign(d.events_seen)
	at = int(d.at)
	path.assign(d.path)
	gold = int(d.gold)
	hp.assign(d.hp)
	max_hp_percent.assign(d.max_hp_percent)
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
	relics = relic_state.relics
	relics_at_start = relic_state.start
	stop_relics.assign(relic_state.offered)
	if not new_defence.is_empty():
		defence = new_defence
	flawless = bool(d.get("flawless", false))
	pact_pending = bool(d.get("pact_pending", false))
	sharpened = bool(d.get("sharpened", false))
	stop_rotten = bool(d.get("stop_rotten", false))
	start_left = new_start_left
	start_relics = new_start_relics
	backpack = new_pack
	curses = new_curses
	_clamp_hp()
	fights_won = int(d.fights_won)
	gold_earned = int(d.gold_earned)
	result = String(d.result)
	return true


## The Relic state in to_dict() data, checked: {relics, start, offered}, or {} if it does not fit:
## the run's Relics (id -> 1, every one a hero has among them, `given`), the Relics found before the
## run, and the stop's Relics on offer (known ones, each once). Saves from before the Relic rework
## (DESIGN.md 8.24) never get here: RunSave's format changed with it.
func _relic_state_of(d: Dictionary, given: Dictionary, by_id: Dictionary) -> Dictionary:
	var state := {"relics": {}, "start": {}, "offered": []}
	if not d.get("relics") is Dictionary or not d.get("relics_start") is Dictionary:
		return {}
	for id: Variant in d.relics:
		if typeof(id) != TYPE_STRING or not by_id.has(String(id)) or typeof(d.relics[id]) != TYPE_INT:
			return {}
		state.relics[String(id)] = 1
	for id: Variant in given:
		if not state.relics.has(String(id)):
			return {}
	for id: Variant in d.relics_start:
		if typeof(id) != TYPE_STRING or not by_id.has(String(id)) or typeof(d.relics_start[id]) != TYPE_INT:
			return {}
		state.start[String(id)] = 1
	var offered: Variant = d.get("stop_relics", [])
	if not offered is Array:
		return {}
	for id: Variant in offered:
		if typeof(id) != TYPE_STRING or not by_id.has(String(id)) or (state.offered as Array).has(String(id)):
			return {}
		(state.offered as Array).append(String(id))
	return state


func party_size() -> int:
	return data.party.size()


## The run's defence in to_dict() data, checked: one [parried, dodged, jumped, taken] per hero, or
## [] if it is missing or does not fit.
func _defence_of(value: Variant) -> Array[Array]:
	var out: Array[Array] = []
	if not value is Array or (value as Array).size() != party_size():
		return out
	for row: Variant in value:
		if not row is Array or (row as Array).size() != 4:
			out.clear()
			return out
		for n: Variant in row:
			if typeof(n) != TYPE_INT or int(n) < 0:
				out.clear()
				return out
		out.append((row as Array).duplicate())
	return out


## Adds a fight's defence (FightRecap.to_dict()'s "heroes": per party slot [parried, dodged,
## jumped, taken]) to the run's.
func add_defence(heroes: Variant) -> void:
	if not heroes is Array:
		return
	for slot: int in mini((heroes as Array).size(), defence.size()):
		var row: Variant = heroes[slot]
		if row is Array and (row as Array).size() == 4:
			for i: int in 4:
				defence[slot][i] = int(defence[slot][i]) + maxi(0, int(row[i]))


## A guard or an elite won without a hit taken (`recap`: FightRecap.to_dict()), card #283.
static func is_flawless(encounter: EncounterData, recap: Dictionary) -> bool:
	return encounter != null and (encounter.mini_boss or encounter.elite) and not recap.is_empty() \
			and int(recap.get("hits_taken", 1)) == 0


## The hero who defended best this run: the most hits parried, dodged or jumped, then the fewest
## taken (-1: nobody defended anything).
func best_defender() -> int:
	var best := -1
	for slot: int in defence.size():
		var row: Array = defence[slot]
		var saved := int(row[0]) + int(row[1]) + int(row[2])
		if saved <= 0:
			continue
		if best < 0:
			best = slot
			continue
		var top: Array = defence[best]
		var top_saved := int(top[0]) + int(top[1]) + int(top[2])
		if saved > top_saved or (saved == top_saved and int(row[3]) < int(top[3])):
			best = slot
	return best


# --- stats ------------------------------------------------------------------------------------

## Max HP percent kept for good (max_hp_percent), level, Vitality (spent and from Relics) and Relics.
func total_max_hp_percent(slot: int) -> int:
	return max_hp_percent[slot] + (levels[slot] - 1) * tuning.run_level_hp_percent \
			+ attribute_total(slot, Attributes.Kind.VITALITY) * tuning.attr_vitality_hp_percent + gear_amount(slot, GearData.Effect.MAX_HP)


func max_hp(slot: int) -> int:
	return CombatSetup.scaled_max_hp(tuning, data.party[slot], total_max_hp_percent(slot))


## Power percent with level, Might and Relics (100 = the character's normal power).
func power_percent(slot: int) -> int:
	return 100 + (levels[slot] - 1) * tuning.run_level_power_percent \
			+ attribute_total(slot, Attributes.Kind.MIGHT) * tuning.attr_might_power_percent + gear_amount(slot, GearData.Effect.POWER)


func power(slot: int) -> int:
	return CombatMath.percent_min1(CombatMath.percent_min1(tuning.base_party_damage, data.party[slot].power_percent),
			power_percent(slot))


func speed(slot: int) -> int:
	return maxi(1, data.party[slot].speed + speed_bonus(slot))


## Speed added to the hero's own: Agility and Relics.
func speed_bonus(slot: int) -> int:
	return attribute_total(slot, Attributes.Kind.AGILITY) * tuning.attr_agility_speed + gear_amount(slot, GearData.Effect.SPEED)


## How much less enemy hits deal to this hero, in percent: Defense and Relics (capped as the
## fight caps it).
func defense_percent(slot: int) -> int:
	return mini(int(passives(slot).get(Passive.TOUGH, 0)), tuning.tough_max_percent)


## This hero's chance of a critical hit, in percent (the base, Luck).
func crit_percent(slot: int) -> int:
	return mini(100, tuning.crit_base_percent + int(passives(slot).get(Passive.CRIT, 0)))


## What hero `slot`'s Relics add up to for one effect: the effects add, rot-touched
## drawbacks take away (GearData.contribution), so the total can be below 0.
func gear_amount(slot: int, effect: GearData.Effect) -> int:
	var total := 0
	for item: GearData in effect_sources(slot):
		total += item.contribution(effect)
	return total


## The Relics whose effect hero `slot` has: every one given to them (DESIGN.md 8.24).
func effect_sources(slot: int) -> Array[GearData]:
	var found: Array[GearData] = []
	if slot >= 0 and slot < gear.size():
		for item: Variant in gear[slot]:
			if item != null:
				found.append(item as GearData)
	return found


## The passives slot `slot` brings into fights (Passive keys -> amount): their Relics',
## and the rot of the party's curses (card #332).
func passives(slot: int) -> Dictionary:
	var found := {}
	for item: GearData in effect_sources(slot):
		# Effects and rot-touched drawbacks together (a drawback on the same key takes away).
		for effect: int in GearData.PASSIVE_KEYS:
			var delta := item.contribution(effect as GearData.Effect)
			if delta != 0:
				var key := String(GearData.PASSIVE_KEYS[effect])
				found[key] = int(found.get(key, 0)) + delta
	var rot := rot_percent()
	if rot > 0:
		found[Passive.ROT] = int(found.get(Passive.ROT, 0)) + rot
	var defense := attribute_total(slot, Attributes.Kind.DEFENSE) * tuning.attr_defense_percent
	if defense > 0:
		found[Passive.TOUGH] = int(found.get(Passive.TOUGH, 0)) + defense
	var luck := attribute_total(slot, Attributes.Kind.LUCK) * tuning.attr_luck_crit_percent
	if luck > 0:
		found[Passive.CRIT] = int(found.get(Passive.CRIT, 0)) + luck
	for key: String in found.keys():
		if int(found[key]) == 0:
			found.erase(key)
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
	# The event is picked before the party is there (event_of then picks a fresh one). A "?" stop
	# may turn into an ambush instead (DESIGN.md 8.7); that one is no event, so none is used up.
	ambush_id = ""
	ambush_spoils = false
	flawless = false
	var event: EventData = null
	if int(map.stop(id).type) == RunMap.StopType.EVENT and not _roll_ambush(id):
		event = event_of(id)
	at = id
	path.append(id)
	visited += 1
	restocks = 0
	_start_stop()
	if event != null:
		events_seen.append(event.id)
	return true


## A stop begins: nothing was done at it yet.
func _start_stop() -> void:
	shop_sold.clear()
	stop_done = false
	stop_rotten = false
	stop_text = ""
	stop_relics.clear()


# --- acts (DESIGN.md 8.9) -----------------------------------------------------------------------

var _acts: Array[ActData] = []


## The run's acts. A run without acts is one act made of its own places and final fight.
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
	end_ambush()
	_start_stop()
	at = -1
	path.clear()
	for slot: int in hp.size():
		heal(slot, CombatMath.percent(max_hp(slot), act_heal_percent()))
	return true


## Act `index`'s map. The first act's comes from the run's seed alone (as before acts existed).
## The map of act `index` by `rules` (map_rules when -1): 2 and up move rows, 3 has a row of Guard
## stops, 4 has none (its Elite stops may hold the place's guard, DESIGN.md 8.22, so an act with no
## elite groups still gets Elite stops when every one of its places has a guard).
func _make_map(index: int, rules: int = -1) -> RunMap:
	var rng := CombatRng.new(run_seed if index == 0 else absi(run_seed * 31 + index * ACT_SALT) % 2147483647 + 1)
	var act_info := act_data(index)
	var made_by := map_rules if rules < 0 else rules
	var has_elites := not act_info.elites.is_empty() or (made_by >= 4 and _act_all_guarded(act_info))
	return RunMap.generate(rng, tuning, act_info.zones.size(), has_elites,
			not act_info.events.is_empty(), made_by >= 2, made_by == 3)


## True if the act has places and every one has a guard. The map gives an Elite stop any of the act's
## places, so an act with no elite groups needs a guard in each or some Elite stop would hold nothing.
static func _act_all_guarded(act_info: ActData) -> bool:
	if act_info.zones.is_empty():
		return false
	for zone: ZoneData in act_info.zones:
		if zone == null or zone.guard == null:
			return false
	return true


# --- elite, event and treasure stops (DESIGN.md 8.6 to 8.8) -------------------------------------

## The fight at Elite stop `stop_id`: its place's guard when the stop holds it (elite_holds_guard),
## else one of the act's elite groups (elite_of). Null when neither is there.
func elite_stop_fight(stop_id: int) -> EncounterData:
	return guard_of(stop_id) if elite_holds_guard(stop_id) else elite_of(stop_id)


## True if Elite stop `stop_id` holds its place's guard rather than one of the act's elite groups
## (map rules 4, DESIGN.md 8.22): a roll of its own (ELITE_GUARD_SALT, by the run's seed and the
## stop, the same on every machine) under tuning.run_elite_guard_percent, never when the nearest
## Elite stop on a road leading to it holds the guard, so no road meets the guard at two Elite stops
## in a row. The act's crowned elite rolls too (a crowned guard keeps the crown's legendary spoils).
## An act with no elite groups always holds its guard there; a place with no guard never does.
## False for every other stop and older map rules.
func elite_holds_guard(stop_id: int) -> bool:
	var stop := map.stop(stop_id)
	if map_rules < 4 or int(stop.get("type", -1)) != RunMap.StopType.ELITE:
		return false
	var zone := zone_of(stop)
	if zone == null or zone.guard == null:
		return false
	if act_data().elites.is_empty():
		return true
	if _guard_elite_before(stop_id):
		return false
	var rng := CombatRng.new(_salted((stop_id + 1) * ELITE_GUARD_SALT))
	return rng.range_int(0, 99) < tuning.run_elite_guard_percent


## True if the nearest Elite stop on any road leading to stop `stop_id` holds the guard (the stops
## between that are not Elite stops are passed through).
func _guard_elite_before(stop_id: int) -> bool:
	var seen := {}
	var todo: Array[int] = []
	todo.assign(map.stop(stop_id).get("prev", []))
	while not todo.is_empty():
		var p: int = todo.pop_back()
		if seen.has(p):
			continue
		seen[p] = true
		if int(map.stop(p).get("type", -1)) == RunMap.StopType.ELITE:
			if elite_holds_guard(p):
				return true
		else:
			todo.append_array(map.stop(p).get("prev", []))
	return false


## The elite group at stop `stop_id` (seeded; deep acts and rows bring the deep version). An Elite
## stop that holds its place's guard fights that instead (elite_stop_fight).
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


# --- "?" stops: ambushes and the costs of event choices (DESIGN.md 8.7) -------------------------

## The chance, in percent, that the next "?" stop is an ambush fight: unknown_fight_percent_base plus
## unknown_fight_percent_step for every "?" stop passed without one.
func unknown_fight_percent() -> int:
	return clampi(tuning.unknown_fight_percent_base + ambush_streak * tuning.unknown_fight_percent_step, 0, 100)


## Rolls whether "?" stop `stop_id` is an ambush (seeded by the stop, so it is the same on every
## machine). If so the ambush is set and the count starts over; if not the count grows. An act
## with no ambushes never rolls.
func _roll_ambush(stop_id: int) -> bool:
	var pool := act_data().ambushes
	if pool.is_empty():
		return false
	var rng := CombatRng.new(_salted(stop_id * AMBUSH_SALT))
	var roll := rng.range_int(0, 99)
	var encounter := pool[rng.range_int(0, pool.size() - 1)]
	if encounter == null or roll >= unknown_fight_percent():
		ambush_streak += 1
		return false
	_set_ambush(encounter, false)
	return true


func _set_ambush(encounter: EncounterData, spoils: bool) -> void:
	ambush_id = encounter.id
	ambush_spoils = spoils
	ambush_streak = 0


## True while the party must fight an ambush at this stop.
func in_ambush() -> bool:
	return not ambush_id.is_empty()


## The ambush fight: its encounter, in its deep version in a deep act or row (null: none).
func ambush_encounter() -> EncounterData:
	var base := _find_ambush(ambush_id)
	if base == null:
		return null
	return base.deep if is_deep() and base.deep != null else base


## The ambush is over (fought, or the act ended).
func end_ambush() -> void:
	ambush_id = ""
	ambush_spoils = false


## The look of an ambush fight: one of the act's places' (picked by the stop).
func ambush_look() -> StageLook:
	var zone := _ambush_zone()
	return zone.look if zone != null and zone.look != null else final_look()


## The place an ambush at the current stop is fought in: one of the act's (picked by the stop).
func _ambush_zone() -> ZoneData:
	var zones := act_data().zones
	return zones[absi(at) % zones.size()] if not zones.is_empty() else null


## An ambush encounter by id: the act pools' and every event choice's.
func _find_ambush(id: String) -> EncounterData:
	if id.is_empty():
		return null
	for act_info: ActData in acts():
		for encounter: EncounterData in act_info.ambushes:
			if encounter != null and encounter.id == id:
				return encounter
		for event: EventData in act_info.events:
			if event == null:
				continue
			for choice: EventChoiceData in event.choices:
				for deal: ZoneOfferData in [choice.deal, choice.risk_deal]:
					if deal != null and deal.ambush != null and deal.ambush.id == id:
						return deal.ambush
	return null


## The percent an event at stop `stop_id` pays and charges its gold and XP at: 100, plus
## tuning.event_reward_row_percent for every map row of depth.
func event_scale(stop_id: int) -> int:
	return 100 + _row_of(stop_id) * tuning.event_reward_row_percent if stop_id >= 0 else 100


## True if the party can take event choice `choice` at stop `stop_id` (default: the current one),
## which means it can pay the price.
func can_choose(choice: EventChoiceData, stop_id: int = -2) -> bool:
	if choice == null:
		return false
	var scale := event_scale(at if stop_id == -2 else stop_id)
	return choice.deal == null or can_take_offer(choice.deal, scale)


## Takes event choice `index` at stop `stop_id`: its deal, and with its risk_percent (seeded) its
## risk deal too. `pick` answers a deal that asks for a hero (slot) or an item (uid): see
## ZoneOfferData.pick_kind. Items come back for the caller to put in the backpack. Returns
## {ok: bool, text: String, items: Array[ItemData], risk: bool, ambush: bool}.
func choose_event(choice: EventChoiceData, stop_id: int, index: int, pick: int = -1, hero: int = -1) -> Dictionary:
	var items: Array[ItemData] = []
	var scale := event_scale(stop_id)
	if not can_choose(choice, stop_id) or (choice.deal != null and not pick_fits(choice.deal, pick)):
		return {"ok": false, "text": "You cannot pay that.", "items": items, "risk": false, "ambush": false}
	var lines: Array[String] = []
	if not choice.done_text.is_empty():
		lines.append(choice.done_text)
	if choice.deal != null:
		var got := take_offer(choice.deal, stop_id, 1000 + index, scale, pick, false, hero)
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
		# A risk is never refused: it takes what there is, from a hero or an item picked by the seed.
		var got := take_offer(choice.risk_deal, stop_id, 1050 + index, scale, -1, true, hero)
		if got.item != null:
			items.append(got.item)
		if String(got.text) != "Nothing happened.":
			lines.append(String(got.text))
	# The result is final from here on (card #197): a saved run resumes after it, not before it.
	stop_done = true
	stop_text = "\n".join(lines) if not lines.is_empty() else "You walk on."
	return {"ok": true, "text": "\n".join(lines), "items": items, "risk": risk, "ambush": in_ambush()}


## True if `pick` answers what `offer` asks the player to pick (and is true of any deal that asks
## for nothing).
func pick_fits(offer: ZoneOfferData, pick: int) -> bool:
	match offer.pick_kind():
		ZoneOfferData.Pick.HERO:
			return pick >= 0 and pick < party_size() and hero_can_lose_max_hp(pick)
		ZoneOfferData.Pick.ITEM:
			return losable_uids().has(pick)
	return true


## Backpack items an event may take: every one (the pack holds only consumables since card #332;
## curses sit on the party and cannot be handed over).
func losable_uids() -> Array[int]:
	var found: Array[int] = []
	if backpack == null:
		return found
	for e: Dictionary in backpack.entries:
		found.append(int(e.uid))
	return found


## True if hero `slot` can lose max HP to an event without going under the floor
## (tuning.event_max_hp_floor_percent of their normal max HP).
func hero_can_lose_max_hp(slot: int) -> bool:
	return slot >= 0 and slot < max_hp_percent.size() and max_hp_percent[slot] > tuning.event_max_hp_floor_percent


## Hero `slot` loses `percent` of their max HP for good, as far as the floor allows. Returns the
## points of normal max HP taken off (0 if they were at the floor).
func lose_max_hp(slot: int, percent: int) -> int:
	var points := mini(maxi(1, CombatMath.percent(total_max_hp_percent(slot), percent)),
			max_hp_percent[slot] - tuning.event_max_hp_floor_percent)
	if points <= 0:
		return 0
	max_hp_percent[slot] -= points
	_clamp_hp()
	return points


## What the shown choice costs and gives, for the event screen: "Price: ...   Reward: ...   n% risk:
## ..." with the depth scaling applied, so the numbers on screen are the numbers paid.
func choice_summary(choice: EventChoiceData, stop_id: int = -2) -> String:
	if choice == null or choice.deal == null:
		return ""
	var scale := event_scale(at if stop_id == -2 else stop_id)
	var parts: Array[String] = []
	var lines := offer_lines(choice.deal, scale)
	if not (lines.price as Array).is_empty():
		parts.append("Price: " + ", ".join(lines.price as Array))
	if not (lines.gift as Array).is_empty():
		parts.append("Reward: " + ", ".join(lines.gift as Array))
	if choice.risk_percent > 0 and choice.risk_deal != null:
		var risk := offer_lines(choice.risk_deal, scale)
		var all: Array = (risk.price as Array) + (risk.gift as Array)
		parts.append("%d%% risk: %s" % [choice.risk_percent, ", ".join(all)])
	return "   ".join(parts)


## A deal in words: {price: Array[String], gift: Array[String]}, gold and XP at `scale` percent.
func offer_lines(offer: ZoneOfferData, scale: int = 100) -> Dictionary:
	var price: Array[String] = []
	var gift: Array[String] = []
	if offer.cost_gold > 0:
		price.append("%d gold" % CombatMath.percent(offer.cost_gold, scale))
	if offer.cost_hp_percent > 0:
		price.append("everyone loses %d%% HP" % offer.cost_hp_percent)
	if offer.cost_max_hp_percent > 0:
		var who := ["everyone", "a hero you pick", "a random hero"][int(offer.cost_max_hp_target)] as String
		price.append("%s loses %d%% max HP for good" % [who, offer.cost_max_hp_percent])
	match offer.cost_item:
		ZoneOfferData.ItemCost.RANDOM:
			price.append("a random pack item")
		ZoneOfferData.ItemCost.CHOSEN:
			price.append("a pack item you pick")
	if offer.cost_rotten != null:
		price.append("curse: %s (rotten)" % offer.cost_rotten.display_name)
	if offer.ambush != null:
		price.append("ambush: %s%s" % [offer.ambush.display_name, ", with spoils" if offer.ambush_spoils else ""])
	if offer.heal_percent > 0:
		gift.append("everyone heals %d%%" % offer.heal_percent)
	if offer.gold > 0:
		gift.append("+%d gold" % CombatMath.percent(offer.gold, scale))
	if offer.xp > 0:
		gift.append("+%d XP each" % CombatMath.percent(offer.xp, scale))
	if offer.team_gauge > 0:
		gift.append("team gauge +%d" % offer.team_gauge)
	if offer.item != null:
		gift.append(offer.item.display_name)
	elif offer.find_rarity >= 0:
		gift.append(["an item", "a rare item", "a legendary item"][clampi(offer.find_rarity, 0, 2)] as String)
	if offer.relic_rarity >= 0:
		gift.append(["a Relic", "a rare Relic", "a legendary Relic"][clampi(offer.relic_rarity, 0, 2)] as String)
	return {"price": price, "gift": gift}


## A deal as icon chips for the choice cards (card #288), the same numbers
## as offer_lines: [{kind: String, text: String, cost: bool}], the price first. Kinds (StopVisuals
## draws each): gold, hp, max_hp, item, curse, fight (the price); heal, gold, xp, gauge, item, find,
## relic (the gift).
func offer_chips(offer: ZoneOfferData, scale: int = 100) -> Array[Dictionary]:
	var chips: Array[Dictionary] = []
	if offer == null:
		return chips
	if offer.cost_gold > 0:
		chips.append({"kind": "gold", "text": "-%d gold" % CombatMath.percent(offer.cost_gold, scale), "cost": true})
	if offer.cost_hp_percent > 0:
		chips.append({"kind": "hp", "text": "-%d%% HP" % offer.cost_hp_percent, "cost": true})
	if offer.cost_max_hp_percent > 0:
		# Who pays, as offer_lines says it: everyone ("all"), a hero you pick ("1") or a random
		# hero ("1?"). Everyone paying costs about three times more, so the chips must differ.
		var who := ["all", "1", "1?"][clampi(int(offer.cost_max_hp_target), 0, 2)] as String
		chips.append({"kind": "max_hp", "text": "-%d%% max HP %s" % [offer.cost_max_hp_percent, who], "cost": true})
	if offer.cost_item != ZoneOfferData.ItemCost.NONE:
		chips.append({"kind": "item", "text": "-1 item?" if offer.cost_item == ZoneOfferData.ItemCost.RANDOM else "-1 item",
				"cost": true})
	if offer.cost_rotten != null:
		chips.append({"kind": "curse", "text": "Curse", "cost": true})
	if offer.ambush != null:
		chips.append({"kind": "fight", "text": "Fight", "cost": true})
	if offer.heal_percent > 0:
		chips.append({"kind": "heal", "text": "+%d%% HP" % offer.heal_percent, "cost": false})
	if offer.gold > 0:
		chips.append({"kind": "gold", "text": "+%d gold" % CombatMath.percent(offer.gold, scale), "cost": false})
	if offer.xp > 0:
		chips.append({"kind": "xp", "text": "+%d XP" % CombatMath.percent(offer.xp, scale), "cost": false})
	if offer.team_gauge > 0:
		chips.append({"kind": "gauge", "text": "+%d gauge" % offer.team_gauge, "cost": false})
	if offer.item != null:
		chips.append({"kind": "item", "text": offer.item.display_name, "cost": false})
	elif offer.find_rarity >= 0:
		chips.append({"kind": "find", "text": ["Item", "Rare item", "Legendary item"][clampi(offer.find_rarity, 0, 2)] as String,
				"cost": false})
	if offer.relic_rarity >= 0:
		chips.append({"kind": "relic", "text": ["Relic", "Rare Relic", "Legendary Relic"][clampi(offer.relic_rarity, 0, 2)] as String,
				"cost": false})
	if offer.ambush != null and offer.ambush_spoils:
		chips.append({"kind": "relic", "text": "Spoils", "cost": false})
	return chips


## An event choice as icon chips at stop `stop_id` (default: the current one), the numbers that
## will be paid: its deal's (offer_chips), then with a risk a die with its chance and the risk
## deal's chips, those marked {risk: true}. The die starts a new line.
func choice_chips(choice: EventChoiceData, stop_id: int = -2) -> Array[Dictionary]:
	var chips: Array[Dictionary] = []
	if choice == null:
		return chips
	var scale := event_scale(at if stop_id == -2 else stop_id)
	chips.append_array(offer_chips(choice.deal, scale))
	if choice.risk_percent > 0 and choice.risk_deal != null:
		chips.append({"kind": "risk", "text": "Risk %d%%" % choice.risk_percent, "cost": true, "risk": true, "newline": true})
		for chip: Dictionary in offer_chips(choice.risk_deal, scale):
			chip["risk"] = true
			chips.append(chip)
	return chips


## The starting pact (card #285): an event with tuning.run_pact_choices of RunData.pacts, picked by
## the run's seed (the same on every machine), shown before the first stop. Null if there are none.
func pact_event() -> EventData:
	if data.pacts.is_empty():
		return null
	var left: Array[EventChoiceData] = []
	for pact: EventChoiceData in data.pacts:
		if pact != null:
			left.append(pact)
	var rng := CombatRng.new(absi(run_seed * 31 + PACT_SALT) % 2147483647 + 1)
	var event := EventData.new()
	event.id = "pact"
	event.title = data.pact_title
	event.text = data.pact_text
	event.picture_path = data.pact_picture_path
	while event.choices.size() < tuning.run_pact_choices and not left.is_empty():
		event.choices.append(left.pop_at(rng.range_int(0, left.size() - 1)))
	return event


## The treasure stop's two chests (card #287): the plain one holds tuning.run_treasure_gold and a
## rare or better item; the rotten one a pick of relic_choice_count() rare or better Relics the run
## does not have, at most rot_gear_spoils_count of them rot-touched like the spoils' (DESIGN.md
## 8.24: they wait in stop_relics until one is taken and given), but
## tuning.rotten_chest_curse_percent of the time a curse comes with it (on the party) and
## rotten_chest_fight_percent of the time (on top) an ambush from the act's pool. Applies the gold,
## the curse and the ambush; the plain chest's item comes back for the screen to hand out. Seeded per
## stop, so a continued run gets the same. Returns {prize: ItemData or null, relics: the Relics on
## offer, gold: int, curse: ItemData or null, ambush: bool, text: String}.
func open_treasure(stop_id: int, rotten: bool) -> Dictionary:
	var row := _row_of(stop_id) + 4
	var rng := CombatRng.new(_salted(stop_id * TREASURE_SALT + act * 41 + (7 if rotten else 0)))
	var got := {"prize": null, "relics": [] as Array[GearData], "gold": 0, "curse": null, "ambush": false, "text": ""}
	var parts: Array[String] = []
	if not rotten:
		var item := _pick_found(rng, row, ItemData.Rarity.RARE)
		got.prize = item if item != null else _pick_found(rng, row)
		got.gold = take_treasure_gold()
		parts.append("+%d gold" % int(got.gold))
	else:
		# Built like the spoils (8.16, 8.24): at most rot_gear_spoils_count rot-touched, never only
		# those, as one must be taken and given for good before the chest can be left.
		var offered := _loot_picks(stop_id * TREASURE_SALT + act * 41 + 13, row, relic_choice_count(), [],
				ItemData.Rarity.RARE)
		got.relics = offered
		stop_relics.clear()
		for item: GearData in offered:
			stop_relics.append(item.id)
		var roll := rng.range_int(0, 99)
		var curses: Array[ItemData] = []
		for item: ItemData in data.found_items:
			if item != null and item.is_curse():
				curses.append(item)
		if roll < tuning.rotten_chest_curse_percent and not curses.is_empty():
			var curse := curses[rng.range_int(0, curses.size() - 1)]
			if add_curse(curse):
				got.curse = curse
				parts.append("Cursed: %s" % curse.display_name)
		elif roll < tuning.rotten_chest_curse_percent + tuning.rotten_chest_fight_percent \
				and not act_data().ambushes.is_empty() and not in_ambush():
			var foe := act_data().ambushes[rng.range_int(0, act_data().ambushes.size() - 1)]
			if foe != null:
				_set_ambush(foe, false)
				got.ambush = true
				parts.append("Something was waiting inside!")
	if got.prize is ItemData:
		parts.push_front("Inside: %s" % (got.prize as ItemData).display_name)
	got.text = ". ".join(parts) + "." if not parts.is_empty() else ""
	stop_done = true
	stop_rotten = rotten
	stop_text = String(got.text)
	return got


## True at the campfire before the boss (card #287): the act's campfire row, the top all-campfire
## row under the boss. Its choices are Rest, Keep Watch and Sharpen.
func is_watch_fire() -> bool:
	var here := current()
	if int(here.get("type", -1)) != RunMap.StopType.REST:
		return false
	for r: int in range(map.row_count() - 2, 0, -1):
		var all_rest := true
		for id: int in map.rows[r]:
			all_rest = all_rest and int(map.stop(id).type) == RunMap.StopType.REST
		if all_rest:
			return int(here.get("row", -1)) == r
	return false


## Keep Watch at the campfire before the boss: the team gauge is full (card #287).
func keep_watch() -> void:
	team_gauge = tuning.team_gauge_max


## Opening the treasure also gives tuning.run_treasure_gold. Returns it.
func take_treasure_gold() -> int:
	gold += tuning.run_treasure_gold
	gold_earned += tuning.run_treasure_gold
	return tuning.run_treasure_gold


# --- shop services and the campfire (DESIGN.md 8.10, 8.11) -------------------------------------

## The shop's Cleanse (card #332): curse `index` (its place in curses) is taken off the party for
## cleanse_price() gold. False (and nothing changes) if there is no such curse or the gold is short.
func cleanse(index: int) -> bool:
	if index < 0 or index >= curses.size() or gold < cleanse_price():
		return false
	gold -= cleanse_price()
	curses.remove_at(index)
	return true


## What the next restock costs: tuning.shop_restock_price, plus tuning.shop_restock_step for every
## restock already bought in this shop visit.
func restock_price() -> int:
	return shop_price(tuning.shop_restock_price + restocks * tuning.shop_restock_step)


## New wares on the shelves for restock_price() gold (shop_stock and shop_gear change).
func restock() -> bool:
	var price := restock_price()
	if gold < price:
		return false
	gold -= price
	restocks += 1
	shop_sold.clear()
	stop_relics.clear()
	return true


## Shelf `index` of this stop's shop was bought (kept for a continued run).
func mark_sold(index: int) -> void:
	if index >= 0 and not shop_sold.has(index):
		shop_sold.append(index)


## Shelf `index` is back on sale (the purchase was undone).
func unmark_sold(index: int) -> void:
	shop_sold.erase(index)


## Campfire Train: every hero gets tuning.rest_train_points attribute points.
func train() -> void:
	for slot: int in bonus_points.size():
		bonus_points[slot] += tuning.rest_train_points


## True when the current stop is deep enough for variant monsters (tuning run_deep_row).
func is_deep() -> bool:
	return act_data().deep or int(current().get("row", 0)) >= tuning.run_deep_row


## The place of a Fight, Guard or elite stop (one of the act's places, ActData.zones; null for other
## stops).
func zone_of(stop: Dictionary) -> ZoneData:
	var index := int(stop.get("zone", -1))
	var zones := act_data().zones
	return zones[index] if index >= 0 and index < zones.size() else null


# --- Fight and Guard stops, and where every run fight is fought (DESIGN.md 8.22) ---------------

## The fight at Fight stop `stop_id`: one of its place's monsters (ZoneData.roamer_pool, seeded by
## the stop), never the fight of the last Fight stop on the road to it while the pool has another;
## in its deep version in a deep act or row. Null for another stop or a place with no monsters.
func fight_of(stop_id: int) -> EncounterData:
	return _deep_version(_fight_base(stop_id), stop_id)


## The guard at stop `stop_id`, an Elite stop that holds it (elite_holds_guard) or a Guard stop of
## map rules 3: its place's (ZoneData.guard), in its deep version in a deep act or row. Null for
## another stop or a place with no guard.
func guard_of(stop_id: int) -> EncounterData:
	var stop := map.stop(stop_id)
	if int(stop.get("type", -1)) != RunMap.StopType.GUARD and not elite_holds_guard(stop_id):
		return null
	var zone := zone_of(stop)
	return _deep_version(zone.guard if zone != null else null, stop_id)


## The fight at the current stop: an ambush sprung there, else the Fight, Elite (an elite group or
## its place's guard) or Guard stop's, or the act's boss (null: a stop with no fight).
func encounter_now() -> EncounterData:
	if in_ambush():
		return ambush_encounter()
	match int(current().get("type", -1)):
		RunMap.StopType.FIGHT:
			return fight_of(at)
		RunMap.StopType.GUARD:
			return guard_of(at)
		RunMap.StopType.ELITE:
			return elite_stop_fight(at)
		RunMap.StopType.FINAL:
			return final_encounter()
	return null


## The place the current stop's fight is fought in: an ambush's (one of the act's, by the stop), or
## the Fight, Guard or elite stop's. Null for the act's boss (fought in its lair) and the stops with
## no fight.
func zone_now() -> ZoneData:
	if in_ambush():
		return _ambush_zone()
	match int(current().get("type", -1)):
		RunMap.StopType.FIGHT, RunMap.StopType.GUARD, RunMap.StopType.ELITE:
			return zone_of(current())
	return null


## The look of the current stop's fight before its weather: its place's, else the act's boss lair.
func look_now() -> StageLook:
	var zone := zone_now()
	return zone.look if zone != null and zone.look != null else final_look()


## The air (drifting motes and the like) of the current stop's fight: its place's (none in the lair).
func air_now() -> Array[ZoneAmbientData]:
	var air: Array[ZoneAmbientData] = []
	var zone := zone_now()
	if zone != null:
		air.assign(zone.ambient)
	return air


## The weather of the current stop's fight: rolled from its place's weathers on a stream of its own,
## seeded by the stop (the same on every machine). Null: clear weather, or the act's boss.
func weather_now() -> WeatherData:
	var zone := zone_now()
	if zone == null:
		return null
	return WeatherData.pick(zone.weathers, zone.weather_weights, zone.clear_weight, _salted((at + 1) * FIGHT_WEATHER_SALT))


## What the current Fight stop's fight drops when won: its seeded tuning.item_drop_percent roll
## (drop_for, the roll a zone's first roaming enemy had). Null at every other stop and in an ambush.
func fight_drop() -> ItemData:
	if in_ambush() or int(current().get("type", -1)) != RunMap.StopType.FIGHT:
		return null
	return drop_for(at)


## The fight Fight stop `stop_id` picks, before its deep version (see fight_of).
func _fight_base(stop_id: int) -> EncounterData:
	var stop := map.stop(stop_id)
	var zone := zone_of(stop) if int(stop.get("type", -1)) == RunMap.StopType.FIGHT else null
	if zone == null:
		return null
	var pool: Array[EncounterData] = []
	for encounter: EncounterData in zone.roamer_pool:
		if encounter != null and not encounter.enemies.is_empty():
			pool.append(encounter)
	var last := _last_fight_before(stop_id)
	if last != null:
		var others: Array[EncounterData] = []
		for encounter: EncounterData in pool:
			if encounter.id != last.id:
				others.append(encounter)
		if not others.is_empty():
			pool = others
	if pool.is_empty():
		return null
	var rng := CombatRng.new(_salted((stop_id + 1) * FIGHT_SALT))
	return pool[rng.range_int(0, pool.size() - 1)]


## The fight (before its deep version) of the last Fight stop on the road to stop `stop_id`: the
## stops walked before it (the whole path while it is not on it yet). Null: none.
func _last_fight_before(stop_id: int) -> EncounterData:
	var end := path.find(stop_id)
	if end < 0:
		end = path.size()
	for i: int in range(end - 1, -1, -1):
		if int(map.stop(path[i]).get("type", -1)) == RunMap.StopType.FIGHT:
			return _fight_base(path[i])
	return null


## `encounter`'s deep version (variant monsters, DESIGN.md 2.16) when stop `stop_id` is in a deep act
## or row and that version has enemies, else `encounter` itself (null stays null).
func _deep_version(encounter: EncounterData, stop_id: int) -> EncounterData:
	if encounter == null:
		return null
	var row := int(map.stop(stop_id).get("row", 0))
	if (act_data().deep or row >= tuning.run_deep_row) and encounter.deep != null \
			and not encounter.deep.enemies.is_empty():
		return encounter.deep
	return encounter


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


## Gold this run gets for an encounter, with the party's gold Relics, then the
## oaths' cut (Want, DESIGN.md 8.15; never below 0).
func gold_for(encounter: EncounterData) -> int:
	var extra := 0
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
		var mine := passives(slot)
		if sharpened and encounter.boss and tuning.sharpen_ap > 0:
			mine[Passive.START_AP] = int(mine.get(Passive.START_AP, 0)) + tuning.sharpen_ap
		setup.party_passives.append(mine)
		setup.party_skills.append(loadout[slot].duplicate() if has_tree(slot) else [])
	for e: Dictionary in backpack.entries:
		if (e.item as ItemData).usable_in_fight():
			var item := e.item as ItemData
			setup.items.append({"uid": int(e.uid), "item": item, "amount": item.amount_percent, "name": item.display_name})
	setup.start_team_gauge = clampi(team_gauge, 0, tuning.team_gauge_max)
	if in_ambush():
		# An ambush is sprung on the party: no running unless the tuning allows it.
		setup.can_run = setup.can_run and tuning.ambush_can_run
	# The marks wait for the second map row (card #253): the first teaches the hits alone.
	setup.allow_marks = _depth() > 0
	if not encounter.boss or tuning.run_enemy_scale_bosses:
		setup.enemy_hp_percent = CombatMath.percent(enemy_hp_percent(), encounter.enemy_hp_percent)
		setup.enemy_power_percent = enemy_power_percent()
	if encounter.elite:
		setup.enemy_hp_percent = CombatMath.percent(setup.enemy_hp_percent,
				maxi(1, tuning.elite_hp_percent + oath_total(&"elite_hp_percent_add")))
		setup.enemy_power_percent = CombatMath.percent(setup.enemy_power_percent,
				maxi(1, tuning.elite_power_percent + oath_total(&"elite_power_percent_add")))
		if is_crowned():
			# The act's crowned elite (card #286): harder still.
			setup.enemy_hp_percent = CombatMath.percent(setup.enemy_hp_percent, tuning.crown_elite_hp_percent)
			setup.enemy_power_percent = CombatMath.percent(setup.enemy_power_percent, tuning.crown_elite_power_percent)
	# Oaths (DESIGN.md 8.15): guards count as bosses; every enemy's power goes up on top.
	if encounter.boss or encounter.mini_boss:
		setup.enemy_hp_percent = CombatMath.percent(setup.enemy_hp_percent, 100 + oath_total(&"boss_hp_percent_add"))
		setup.enemy_power_percent = CombatMath.percent(setup.enemy_power_percent,
				100 + oath_total(&"boss_power_percent_add"))
	setup.enemy_power_percent = CombatMath.percent(setup.enemy_power_percent,
			100 + oath_total(&"enemy_power_percent_add"))
	# Phase 17: the run's base enemy power (Relics stay between runs, DESIGN.md 8.17).
	setup.enemy_power_percent = CombatMath.percent(setup.enemy_power_percent, maxi(1, tuning.enemy_power_base_percent))
	setup.attack_tempo_percent = enemy_tempo_percent(encounter)
	return setup


## How fast this fight's enemy attacks play at the current stop, in percent of their authored
## timing (card #188; lower = faster): tuning attack_tempo_percent less run_enemy_tempo_row_percent
## per row of depth, then the elite, guard or boss percent, never under the floor.
func enemy_tempo_percent(encounter: EncounterData) -> int:
	var tempo := tuning.attack_tempo_percent - _depth() * maxi(0, tuning.run_enemy_tempo_row_percent)
	if encounter.boss:
		tempo = CombatMath.percent(tempo, tuning.boss_tempo_percent)
	elif encounter.mini_boss:
		tempo = CombatMath.percent(tempo, tuning.guard_tempo_percent)
	elif encounter.elite:
		tempo = CombatMath.percent(tempo, tuning.elite_tempo_percent)
	return maxi(tempo, CombatSetup.tempo_floor(tuning))


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
## the run. Fights drop no Relics (DESIGN.md 8.24: they come from Elite stops, bosses, chests and
## shops). Returns {gold, xp: per slot, levels: per slot (levels gained)}.
func finish_fight(fight_result: String, party_hp: Array[int], encounter: EncounterData,
		recap: Dictionary = {}) -> Dictionary:
	var none := {"gold": 0, "xp": _zeros(), "levels": _zeros()}
	end_ambush()
	add_defence(recap.get("heroes", []))
	if encounter != null and encounter.boss:
		sharpened = false
	flawless = fight_result == VICTORY and RunState.is_flawless(encounter, recap)
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
	_wound_winners()
	var won := gold_for(encounter)
	gold += won
	gold_earned += won
	var up := _zeros()
	for slot: int in party_size():
		up[slot] = add_xp(slot, gained[slot])
	if int(current().get("type", -1)) == RunMap.StopType.FINAL and is_last_act():
		result = VICTORY
	return {"gold": won, "xp": gained, "levels": up}


## Gear that wounds its wearer (Oathbreaker's Band, DESIGN.md 8.16): after each fight won they lose
## max HP for good (the floor of lose_max_hp applies). Win-heal Relics (Victor's Wreath, card #242)
## then heal theirs a share of max HP.
func _wound_winners() -> void:
	for slot: int in hp.size():
		var wound := gear_amount(slot, GearData.Effect.WIN_WOUND)
		if wound > 0:
			lose_max_hp(slot, wound)
		var mend := gear_amount(slot, GearData.Effect.WIN_HEAL)
		if mend > 0:
			heal(slot, CombatMath.percent_min1(max_hp(slot), mend))


## True if a fight that ended with `fight_result` ends the run (finish_fight sets the result): any
## defeat, or the last act's boss beaten. An escape never does. Main uses it to close the save the
## moment the fight is decided, before the end screen.
func decides_run(fight_result: String) -> bool:
	if is_over() or fight_result == ESCAPED:
		return false
	if fight_result != VICTORY:
		return true
	return int(current().get("type", -1)) == RunMap.StopType.FINAL and is_last_act()


## A fight ended with the team gauge at `value`: the next fight starts with
## team_gauge_carry_percent() of it (card #146).
func carry_team_gauge(value: int) -> void:
	team_gauge = CombatMath.percent(clampi(value, 0, tuning.team_gauge_max), team_gauge_carry_percent())


## The XP each hero gets for winning `encounter` with these HPs left: the encounter's XP for those
## standing, tuning.run_xp_downed_percent of it for the downed.
func fight_xp(encounter: EncounterData, party_hp: Array[int]) -> Array[int]:
	var full := xp_full(encounter)
	var shares: Array[int] = []
	for slot: int in party_size():
		var standing := slot >= party_hp.size() or party_hp[slot] > 0
		shares.append(full if standing else CombatMath.percent(full, tuning.run_xp_downed_percent))
	return shares


## The XP a standing hero gets for winning `encounter`: its enemies' XP at tuning.run_xp_percent.
func xp_full(encounter: EncounterData) -> int:
	return CombatMath.percent(encounter_xp(encounter), tuning.run_xp_percent)


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


## Points in one attribute with the stat lines of the Relics the hero has (DESIGN.md 8.17).
func attribute_total(slot: int, kind: int) -> int:
	return attribute(slot, kind) + relic_stat(slot, kind)


## The attribute points the Relics hero `slot` has give to one attribute (their level 1 stat line:
## a run has no Relic levels, DESIGN.md 8.24).
func relic_stat(slot: int, kind: int) -> int:
	var total := 0
	if slot >= 0 and slot < gear.size():
		for item: Variant in gear[slot]:
			if item != null and (item as GearData).stat == kind:
				total += (item as GearData).stat_points
	return total


## Every attribute point hero `slot` has earned so far (fewer per level with the oaths, DESIGN.md 8.15).
func earned_points(slot: int) -> int:
	var per_level := maxi(0, tuning.attr_points_per_level + oath_total(&"attr_points_per_level_add"))
	return tuning.attr_start_points + (levels[slot] - 1) * per_level + bonus_points[slot]


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
		healed.append(heal(slot, CombatMath.percent(max_hp(slot), rest_heal_percent_of(slot))))
	return healed


## The percent of max HP a campfire Rest heals hero `slot`: the same for everyone, less (or none)
## for a wearer of gear with a Rest drawback (Hunger Charm, DESIGN.md 8.16).
func rest_heal_percent_of(slot: int) -> int:
	return CombatMath.percent(rest_heal_percent(), clampi(100 + gear_amount(slot, GearData.Effect.REST_HEAL), 0, 1000))


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


## Heals one character (never above max HP). Returns how much was healed. `scaled`: gear that
## changes the healing a hero receives (DESIGN.md 8.16) applies (false: new max HP filled, not a heal).
func heal(slot: int, amount: int, scaled: bool = true) -> int:
	var before := hp[slot]
	if scaled:
		amount = CombatMath.percent(maxi(amount, 0), maxi(0, 100 + gear_amount(slot, GearData.Effect.HEAL_TAKEN)))
	hp[slot] = clampi(before + maxi(amount, 0), 1, max_hp(slot))
	return hp[slot] - before


# --- the backpack (DESIGN.md 8.1) ---------------------------------------------------------------

## Every item this run knows (the shop's and the finds'), by id.
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


## Puts `item` in the first free pocket. Returns its uid, or -1 if the pack is full. Only
## consumables go in the pack (card #332): treasure turns into gold at once (its treasure_gold, card
## #282) and a curse goes on the party (add_curse); both return 0. Anything else returns -1.
func add_item(item: ItemData) -> int:
	if item == null:
		return -1
	if item.kind == ItemData.Kind.TREASURE:
		var won := treasure_gold(item)
		gold += won
		gold_earned += won
		return 0
	if item.is_curse():
		return 0 if add_curse(item) else -1
	if not item.goes_in_pack():
		return -1
	return backpack.add_anywhere(item)


## The gold a treasure turns into the moment it is found: what selling it paid (card #282).
func treasure_gold(item: ItemData) -> int:
	return sell_price(item.price) if item != null else 0


## A find in a few words for a stop or a fight's drop: "Found: Salve", "Silver Ring: +20 gold",
## "Cursed: Grave Moss". Call it after add_item.
func find_text(item: ItemData) -> String:
	if item == null:
		return ""
	if item.kind == ItemData.Kind.TREASURE:
		return "%s: +%d gold" % [item.display_name, treasure_gold(item)]
	if item.is_curse():
		return "Cursed: %s" % item.display_name
	return "Found: %s" % item.display_name


## The items a shop stop has on its shelves: up to tuning.run_shop_items of the run's
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


## Puts consumable `item` in pocket x (`y` and `turn` are from the old grid: 0). Returns its uid, or
## -1 if that pocket is taken or the item does not go in the pack.
func place_item(item: ItemData, x: int, y: int = 0, turn: int = 0) -> int:
	if item == null or not item.goes_in_pack():
		return -1
	return backpack.add(item, x, y, turn)


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
	return not item.needs_target() or (slot >= 0 and slot < hp.size())


## Why backpack item `uid` cannot be used on hero `slot` right now ("" when it can), for screens
## to show next to a greyed hero.
func use_blocked_reason(uid: int, slot: int) -> String:
	if can_use_item(uid, slot):
		return ""
	return "It cannot be used on them."


## Uses backpack item `uid` on the map (on character `slot` if it needs one); it is used up.
func use_item(uid: int, slot: int) -> bool:
	if not can_use_item(uid, slot):
		return false
	apply_item(backpack.remove(uid), slot)
	return true


## What an item does when used outside a fight, at its own amount (no levels since card #332).
func apply_item(item: ItemData, slot: int) -> void:
	match item.effect:
		ItemData.Effect.HEAL_ONE:
			heal(slot, CombatMath.percent(max_hp(slot), item.amount_percent))
		ItemData.Effect.HEAL_ALL:
			for s: int in hp.size():
				heal(s, CombatMath.percent(max_hp(s), item.amount_percent))


# --- curses (DESIGN.md 8.1, card #332) ---------------------------------------------------------

## Puts curse `item` on the party (card #332: never in the pack). False if it is not a curse this
## run knows (an unknown id could not be saved or sent).
func add_curse(item: ItemData) -> bool:
	if item == null or not item.is_curse() or not items_by_id().has(item.id):
		if item != null:
			push_warning("RunState: %s is not a curse of this run's items" % item.id)
		return false
	curses.append(item.id)
	return true


## The curses on the party as items, in the order taken.
func curse_items() -> Array[ItemData]:
	var by_id := items_by_id()
	var found: Array[ItemData] = []
	for id: String in curses:
		if by_id.has(id):
			found.append(by_id[id] as ItemData)
	return found


## The HP percent every hero loses each turn in a fight from the party's curses.
func rot_percent() -> int:
	var total := 0
	for item: ItemData in curse_items():
		total += item.rot_percent
	return total


## A backpack or gear change as plain data, from any player (online, clients send these to the
## host, which applies them in the order they arrive: DESIGN.md 8.1). Ops:
## {op: "move", uid, x, y, turn}, {op: "drop", uid}, {op: "use", uid, slot}, {op: "sell", uid},
## {op: "give", slot, relic: id} (a Relic the run has that waits for a hero, DESIGN.md 8.24),
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
		"attributes":
			return ints.call(["slot"]) and set_attributes(int(op.slot), op.get("values"))
		"unlock":
			return ints.call(["slot"]) and typeof(op.get("ability")) == TYPE_STRING \
					and int(op.slot) >= 0 and int(op.slot) < party_size() and unlock(int(op.slot), String(op.ability))
		"loadout":
			return ints.call(["slot"]) and int(op.slot) >= 0 and int(op.slot) < party_size() \
					and set_loadout(int(op.slot), op.get("abilities"))
		"give":
			return ints.call(["slot"]) and typeof(op.get("relic")) == TYPE_STRING \
					and give_waiting(relic_by_id(String(op.relic)), int(op.slot))
	return false


## Sells backpack item `uid` (it is gone). Returns the gold, or -1 if there is no such item or it
## is rotten (nobody buys rot).
func sell_item(uid: int) -> int:
	var e := backpack.entry(uid)
	if e.is_empty() or (e.item as ItemData).rotten:
		return -1
	var gained := sell_price((e.item as ItemData).price)
	backpack.remove(uid)
	gold += gained
	_clamp_hp()
	return gained


## True if the party can pay for an event choice's or a pact's deal. HP prices can always be paid (a
## hero never drops below 1 HP for one); an event's deal (`scale` is its gold and XP percent, see
## event_scale) also needs a hero who can still lose max HP and something in the backpack to lose (a
## curse needs no room: it sits on the party, card #332). A deal that asks for a pick is checked
## again when it is taken.
func can_take_offer(offer: ZoneOfferData, scale: int = 100) -> bool:
	if offer == null or gold < CombatMath.percent(offer.cost_gold, scale):
		return false
	if offer.cost_max_hp_percent > 0:
		var anyone := false
		for slot: int in party_size():
			anyone = anyone or hero_can_lose_max_hp(slot)
		if not anyone:
			return false
	return offer.cost_item == ZoneOfferData.ItemCost.NONE or not losable_uids().is_empty()


## Takes deal `index` of the event at stop `stop_id` (DESIGN.md 8.7): pays its price and
## gives its gifts, all but the item, which comes back for the caller to put in the backpack. Returns
## {ok: bool, text: String (what happened, one line), item: ItemData or null}. Nothing changes if
## the deal cannot be paid. `scale`: percent for the deal's gold and XP; `pick`: the hero or item the
## player picked (see ZoneOfferData.pick_kind); `forced` (a risk): never refused, it takes what
## there is; `hero`: who gets the deal's Relic (DESIGN.md 8.24; not a hero: the one with the fewest
## Relics).
func take_offer(offer: ZoneOfferData, stop_id: int, index: int, scale: int = 100, pick: int = -1,
		forced: bool = false, hero: int = -1) -> Dictionary:
	if not forced and (not can_take_offer(offer, scale) or not pick_fits(offer, pick)):
		var short := offer != null and gold < CombatMath.percent(offer.cost_gold, scale)
		return {"ok": false, "text": "Not enough gold." if short else "You cannot pay that.", "item": null}
	var parts: Array[String] = []
	var rng := CombatRng.new(_salted(stop_id * COST_SALT + index * 29))
	gold -= mini(CombatMath.percent(offer.cost_gold, scale), gold)
	if offer.cost_hp_percent > 0:
		for slot: int in hp.size():
			if hp[slot] > 0:
				hp[slot] = maxi(1, hp[slot] - CombatMath.percent(max_hp(slot), offer.cost_hp_percent))
		parts.append("Everyone lost %d%% HP" % offer.cost_hp_percent)
	if offer.cost_max_hp_percent > 0:
		parts.append(_take_max_hp(offer, pick, rng))
	if offer.cost_item != ZoneOfferData.ItemCost.NONE:
		parts.append(_take_item(offer, pick, rng))
	if offer.cost_rotten != null and add_curse(offer.cost_rotten):
		parts.append("Cursed: %s" % offer.cost_rotten.display_name)
	if offer.ambush != null and not in_ambush():
		_set_ambush(offer.ambush, offer.ambush_spoils)
		parts.append("An ambush!")
	if offer.heal_percent > 0:
		for slot: int in hp.size():
			heal(slot, CombatMath.percent(max_hp(slot), offer.heal_percent))
		parts.append("Everyone healed %d%%" % offer.heal_percent)
	if offer.gold > 0:
		var won := CombatMath.percent(offer.gold, scale)
		gold += won
		gold_earned += won
		parts.append("+%d gold" % won)
	if offer.xp > 0:
		var xp_each := CombatMath.percent(offer.xp, scale)
		for slot: int in xps.size():
			add_xp(slot, xp_each)
		parts.append("+%d XP each" % xp_each)
	if offer.team_gauge > 0:
		team_gauge = mini(tuning.team_gauge_max, team_gauge + offer.team_gauge)
		parts.append("Team gauge +%d" % offer.team_gauge)
	if offer.relic_rarity >= 0:
		var relic_rng_salt := stop_id * OFFER_SALT + index * 19 + 7
		var gifts := _pick_gear(relic_rng_salt, 1, _row_of(stop_id), offer.relic_rarity, GearPool.NORMAL)
		if not gifts.is_empty():
			var to := hero if hero >= 0 and hero < party_size() else fewest_relics_hero()
			parts.append(relic_given_text(give_relic(gifts[0], to), to))
	var item: ItemData = offer.item
	if item == null and offer.find_rarity >= 0:
		var find_rng := CombatRng.new(_salted(stop_id * OFFER_SALT + index * 19))
		item = _pick_found(find_rng, _row_of(stop_id), offer.find_rarity)
		if item == null:
			item = _pick_found(find_rng, _row_of(stop_id))
	if item != null:
		parts.append("Got: %s" % item.display_name)
	return {"ok": true, "text": ". ".join(parts) if not parts.is_empty() else "Nothing happened.", "item": item}


## The max HP part of a deal: who loses it (everyone, the picked hero, or one by the seed; a
## risk's chosen hero is also by the seed) and what it says.
func _take_max_hp(offer: ZoneOfferData, pick: int, rng: CombatRng) -> String:
	var lost: Array[String] = []
	var slots: Array[int] = []
	match offer.cost_max_hp_target:
		ZoneOfferData.HpTarget.EVERYONE:
			for slot: int in party_size():
				slots.append(slot)
		ZoneOfferData.HpTarget.CHOSEN:
			slots.append(pick if pick >= 0 and pick < party_size() else _random_slot(rng))
		_:
			slots.append(_random_slot(rng))
	for slot: int in slots:
		if lose_max_hp(slot, offer.cost_max_hp_percent) > 0:
			lost.append(data.party[slot].display_name)
	if lost.is_empty():
		return "Nothing more could be taken from your strength"
	if slots.size() > 1 and lost.size() == slots.size():
		return "Everyone lost %d%% max HP for good" % offer.cost_max_hp_percent
	return "%s lost %d%% max HP for good" % [" and ".join(lost), offer.cost_max_hp_percent]


## A hero for a random cost: one who can still lose max HP, else any.
func _random_slot(rng: CombatRng) -> int:
	var able: Array[int] = []
	for slot: int in party_size():
		if hero_can_lose_max_hp(slot):
			able.append(slot)
	if able.is_empty():
		return rng.range_int(0, party_size() - 1)
	return able[rng.range_int(0, able.size() - 1)]


## The item part of a deal: the picked item, or one by the seed, leaves the backpack.
func _take_item(offer: ZoneOfferData, pick: int, rng: CombatRng) -> String:
	var able := losable_uids()
	if able.is_empty():
		return "There was nothing in the pack to lose"
	var uid: int = pick if offer.cost_item == ZoneOfferData.ItemCost.CHOSEN and able.has(pick) \
			else able[rng.range_int(0, able.size() - 1)]
	var label := (backpack.entry(uid).item as ItemData).display_name
	backpack.remove(uid)
	_clamp_hp()
	return "Lost: %s" % label


## What the fight at Fight stop `stop_id` drops when won (DESIGN.md 8.22): a seeded
## tuning.item_drop_percent chance of a found item, else null.
func drop_for(stop_id: int) -> ItemData:
	var rng := CombatRng.new(_salted(stop_id * DROP_SALT))
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


# --- Relics (DESIGN.md 8.17, 8.24; "gear" in the code) -----------------------------------------

var _relic_index: Dictionary = {}


## The run's Relic with this id (null: none).
func relic_by_id(id: String) -> GearData:
	if _relic_index.is_empty():
		for item: GearData in data.gear:
			if item != null:
				_relic_index[item.id] = item
	return _relic_index.get(id) as GearData


## True if the run has this Relic (given to a hero, or still waiting for one).
func owns(item: GearData) -> bool:
	return item != null and relics.has(item.id)


## True if the Relic is in the Relic book from before this run and has not turned up in this run
## yet: a find of it is not tagged "New" (LootScreen.new_tag).
func is_home(item: GearData) -> bool:
	return item != null and relics_at_start.has(item.id) and not owns(item)


## True if a hero has this Relic.
func is_given(item: GearData) -> bool:
	return holder_of(item) >= 0


## The hero who has this Relic (-1: nobody).
func holder_of(item: GearData) -> int:
	if item == null:
		return -1
	for slot: int in gear.size():
		if (gear[slot] as Array).has(item):
			return slot
	return -1


## True if this Relic could still turn up in this run: the run does not have it. A run has no copies
## and no Relic levels (DESIGN.md 8.24), so a Relic the party has never shows up again.
func can_gain(item: GearData) -> bool:
	return item != null and not owns(item)


## Every Relic the run has, in the run's order.
func owned_relics() -> Array[GearData]:
	var found: Array[GearData] = []
	for item: GearData in data.gear:
		if item != null and owns(item):
			found.append(item)
	return found


## The Relics hero `slot` has, in the order given.
func relics_of(slot: int) -> Array[GearData]:
	var found: Array[GearData] = []
	if slot >= 0 and slot < gear.size():
		for item: Variant in gear[slot]:
			found.append(item as GearData)
	return found


## The run's Relics no hero has yet, in the run's order (none in play since the Relic bag went, card
## #328: only tests and an old save have them). The party screen gives them out.
func waiting_relics() -> Array[GearData]:
	var found: Array[GearData] = []
	for item: GearData in owned_relics():
		if not is_given(item):
			found.append(item)
	return found


## The hero with the fewest Relics (the first on a tie).
func fewest_relics_hero() -> int:
	var best := 0
	for slot: int in party_size():
		if (gear[slot] as Array).size() < (gear[best] as Array).size():
			best = slot
	return best


## What finding `item` now is, before it joins the run: {item, new (never found before), home (found
## before, left at home)}. Changes nothing.
func relic_find(item: GearData) -> Dictionary:
	var home := is_home(item)
	return {"item": item, "new": item != null and not owns(item) and not home, "home": home}


## Gives Relic `item` to hero `slot` (DESIGN.md 8.24): a find joins the run with it. A hero keeps
## every Relic given to them, with no limit and no slots, until the run ends; a Relic is never
## given twice. HP never rises from it (no free heal) and is cut to a lower max. Returns the find
## (relic_find, read before it joined), or {} if it cannot be given (not this run's Relic, a hero
## has it already, no such hero).
func give_relic(item: GearData, slot: int) -> Dictionary:
	if item == null or relic_by_id(item.id) != item or slot < 0 or slot >= party_size() or is_given(item):
		return {}
	var info := relic_find(item)
	relics[item.id] = 1
	(gear[slot] as Array).append(item)
	_clamp_hp()
	return info


## Gives a Relic the run has that waits for a hero to hero `slot`. False if it is not waiting or
## there is no such hero.
func give_waiting(item: GearData, slot: int) -> bool:
	return owns(item) and not give_relic(item, slot).is_empty()


## A Relic joins the run with no hero yet (tests). Returns relic_find's info, or {} if the run has it
## already.
func add_relic(item: GearData) -> Dictionary:
	if item == null or relic_by_id(item.id) != item or owns(item):
		return {}
	var info := relic_find(item)
	relics[item.id] = 1
	return info


## What the run keeps forever, won or lost, for its end screen: the Relics found for the first time
## ("Nothing new to keep." if none).
func relic_gain_line() -> String:
	return relic_gain_line_since(relics_at_start)


## The same line measured from another collection (an online friend's own: `found_before` id -> any,
## card #281). A late joiner's run end shows RunEndScreen.own_kept instead.
func relic_gain_line_since(found_before: Dictionary) -> String:
	var found := PackedStringArray()
	for item: GearData in found_relics():
		if not found_before.has(item.id):
			found.append(item.display_name)
	if found.is_empty():
		return "Nothing new to keep."
	return "New Relics: " + ", ".join(found)


## A find from relic_find() in a word, for the toast next to the Relic's icon: "New" (not in the
## Relic book yet), "Found" (the book has it, as relic_find_text's line says), or "" (one the run had
## waiting).
static func relic_find_short(info: Dictionary) -> String:
	if bool(info.get("new", false)):
		return "New"
	if bool(info.get("home", false)):
		return "Found"
	return ""


## One line for a find from relic_find(): "New Relic: Iron Charm", "Found: Iron Charm" (one left at
## home or waiting), "" for none.
static func relic_find_text(info: Dictionary) -> String:
	var item := info.get("item") as GearData
	if item == null:
		return ""
	if bool(info.get("new", false)):
		return "New Relic: %s" % item.display_name
	return "Found: %s" % item.display_name


## relic_find_text with who got it: "New Relic: Iron Charm (Alder)".
func relic_given_text(info: Dictionary, slot: int) -> String:
	var line := RunState.relic_find_text(info)
	if line.is_empty() or slot < 0 or slot >= party_size():
		return line
	return "%s (%s)" % [line, data.party[slot].display_name]


## Takes in the Relic book at the start of a run: what it holds is remembered for the end screen and
## the "New" tags. Nothing joins the run here: each hero takes a starting Relic from the book in the
## pick step (take_start_relic, card #328).
func _take_collection(collection: RelicCollection) -> void:
	for item: GearData in data.gear:
		if item != null and collection.owns(item.id):
			relics_at_start[item.id] = 1


# --- starting Relics (DESIGN.md 8.24, card #328) ------------------------------------------------

## How many Relics each hero takes from a Relic book at the start: tuning.start_relics_per_hero, fewer
## with the oaths (start_relics_add, the Empty Hand), never below 0.
func start_relic_count() -> int:
	return maxi(0, tuning.start_relics_per_hero + oath_total(&"start_relics_add"))


## True while a hero may still take a starting Relic (the pick step is not over).
func start_pending() -> bool:
	for left: int in start_left:
		if left > 0:
			return true
	return false


## True while hero `slot` may still take a starting Relic.
func start_open(slot: int) -> bool:
	return slot >= 0 and slot < start_left.size() and start_left[slot] > 0


## The heroes of `slots` who may still take a starting Relic, in the same order.
func start_open_of(slots: Array[int]) -> Array[int]:
	var open: Array[int] = []
	for slot: int in slots:
		if start_open(slot):
			open.append(slot)
	return open


## The Relics of `book` a hero could take as a starting Relic now: found in the book, known to this
## run and not in it yet (one taken for another hero is gone), in the run's order.
func start_choices(book: RelicCollection) -> Array[GearData]:
	var list: Array[GearData] = []
	if book == null:
		return list
	for item: GearData in book.found_of(data.gear):
		if can_gain(item):
			list.append(item)
	return list


## Hero `slot` takes `item` as a starting Relic (from a Relic book: online the host cannot see a
## friend's book, so it checks only the rest). Returns the find (relic_find), or {} if refused: no
## starting Relic left for that hero, not this run's Relic, or the run has it (taken for another hero).
func take_start_relic(slot: int, item: GearData) -> Dictionary:
	if not start_open(slot) or not can_gain(item):
		return {}
	# Before the run, unlike a find (no free heal), a higher max HP comes filled: the HP each hero is
	# missing stays the same, so a drawback still cuts it.
	var missing: Array[int] = []
	for s: int in party_size():
		missing.append(max_hp(s) - hp[s])
	var got := give_relic(item, slot)
	if not got.is_empty():
		start_left[slot] -= 1
		start_relics[item.id] = 1
		for s: int in party_size():
			hp[s] = clampi(max_hp(s) - missing[s], 1, max_hp(s))
	return got


## Hero `slot` takes no (more) starting Relics. False if they had none left to take.
func skip_start_relic(slot: int) -> bool:
	if not start_open(slot):
		return false
	start_left[slot] = 0
	return true


## Every hero of `slots` takes no (more) starting Relics (an empty book, the online wait ran out).
## Returns how many were still open.
func skip_start_relics(slots: Array[int]) -> int:
	var skipped := 0
	for slot: int in slots:
		if skip_start_relic(slot):
			skipped += 1
	return skipped


## Every hero takes no (more) starting Relics: the pick step is over.
func end_start_picks() -> void:
	for slot: int in start_left.size():
		start_left[slot] = 0


## The bot (and tests): every Relic still waiting goes to the hero it helps most (GearBot.best_hero),
## the best first by GearBot's score; a price GearBot refuses stays waiting. Returns how many were
## given.
func auto_give() -> int:
	var left := waiting_relics()
	left.sort_custom(func(a: GearData, b: GearData) -> bool: return GearBot.score(a) > GearBot.score(b))
	var given := 0
	for item: GearData in left:
		if GearBot.score(item) >= 0 and not give_relic(item, GearBot.best_hero(self, item)).is_empty():
			given += 1
	return given


## The run's found Relic ids (found_relics) that were not in `relics_before` (id -> 1 when a friend
## joined late, card #304; empty: every one), in the run's Relic order: what a machine banks.
func relic_ids_since(relics_before: Dictionary) -> Array:
	var ids: Array = []
	for item: GearData in found_relics():
		if not relics_before.has(item.id):
			ids.append(item.id)
	return ids


## The Relics this run found (DESIGN.md 8.24): every Relic it has but the starting ones, which came
## from a Relic book (online maybe another player's). Only these are banked and shown as new.
func found_relics() -> Array[GearData]:
	var list: Array[GearData] = []
	for item: GearData in owned_relics():
		if not start_relics.has(item.id):
			list.append(item)
	return list


## The Relics on offer at this stop (stop_relics), in the order shown.
func stop_relic_choices() -> Array[GearData]:
	var found: Array[GearData] = []
	for id: String in stop_relics:
		var item := relic_by_id(id)
		if item != null:
			found.append(item)
	return found


## Takes Relic `index` of the stop's offer and gives it to hero `slot`; the others go, and the stop's
## line (stop_text) gets who got it. Returns the find (relic_find), or {} if it cannot be taken.
func take_stop_relic(index: int, slot: int) -> Dictionary:
	var offered := stop_relic_choices()
	if index < 0 or index >= offered.size():
		return {}
	var got := give_relic(offered[index], slot)
	if not got.is_empty():
		stop_relics.clear()
		stop_text = (stop_text + "\n" + relic_given_text(got, slot)).strip_edges()
	return got


# --- spoils, shops and chests -------------------------------------------------------------------

## How many Relics the spoils offer: relic_choice_count(), one more after a flawless win (card #283).
func loot_choice_count() -> int:
	return relic_choice_count() + (1 if flawless else 0)


## How many Relics a pick shows (spoils and the rotten chest, DESIGN.md 8.24): tuning.run_loot_choices,
## fewer with the oaths (never fewer than one).
func relic_choice_count() -> int:
	return maxi(1, tuning.run_loot_choices + oath_total(&"loot_choices_add"))


## True if stop `stop_id` (the current one by default) is the act's crowned elite (card #286).
func is_crowned(stop_id: int = -2) -> bool:
	var s := map.stop(at if stop_id == -2 else stop_id)
	return int(s.get("type", -1)) == RunMap.StopType.ELITE and bool(s.get("crown", false))


## The Relics a stop's spoils offer: up to loot_choice_count() Relics the run lacks (seeded). The crowned elite's spoils always hold a legendary one, listed first (card
## #286), while the run has one left to gain.
func loot_choices(stop_id: int) -> Array[GearData]:
	var salt := stop_id * LOOT_SALT + act * 43
	var row := _row_of(stop_id)
	var count := loot_choice_count()
	if is_crowned(stop_id) and not in_ambush():
		var crown := _pick_gear(salt + 3, 1, row, ItemData.Rarity.LEGENDARY, GearPool.NORMAL)
		if not crown.is_empty() and int(crown[0].rarity) == ItemData.Rarity.LEGENDARY:
			var rest := _loot_picks(salt, row, count - 1, crown)
			crown.append_array(rest)
			return crown
	return _loot_picks(salt, row, count)


## Up to `count` spoils picks, none of `skip` (see loot_choices). `floor_rarity`: the lowest rarity
## offered while the pool has enough (the rotten chest's rare or better), -1 for the spoils' own
## tuning.run_spoils_min_rarity (and any rarity once the pool runs short).
func _loot_picks(salt: int, row: int, count: int, skip: Array[GearData] = [],
		floor_rarity: int = -1) -> Array[GearData]:
	# Rot-touched gear (DESIGN.md 8.16): spoils offer some among their choices (listed last), but
	# never as the only choice.
	var least := floor_rarity if floor_rarity >= 0 else tuning.run_spoils_min_rarity
	var rot_count := mini(tuning.rot_gear_spoils_count, count - 1)
	var rot: Array[GearData] = []
	if rot_count > 0:
		rot = _pick_gear(salt + ROT_GEAR_SALT, rot_count, row, least, GearPool.ROT_TOUCHED, skip)
	var picked := _pick_gear(salt, count - rot.size(), row, least, GearPool.NORMAL, skip)
	picked.append_array(rot)
	if picked.size() < count:
		var taken := picked.duplicate()
		taken.append_array(skip)
		picked.append_array(_pick_gear(salt + 1, count - picked.size(), row, maxi(floor_rarity, 0), GearPool.ANY, taken))
	return picked


## The Relics a shop stop sells: up to tuning.run_shop_gear the run does not have (seeded). At the
## shop the party stands at, the shelves are kept in stop_relics once shown (until a restock), so a
## Relic bought there stays on its shelf, sold.
func shop_gear(stop_id: int) -> Array[GearData]:
	var here := stop_id == at and int(current().get("type", -1)) == RunMap.StopType.SHOP
	if here and not stop_relics.is_empty():
		return stop_relic_choices()
	var picked := _pick_gear(stop_id * SHOP_SALT + restocks * RESTOCK_SALT + act * 47, tuning.run_shop_gear,
			_row_of(stop_id), 0, GearPool.ANY, [], true)
	if here:
		stop_relics.clear()
		for item: GearData in picked:
			stop_relics.append(item.id)
	return picked


## Up to `count` Relics the run does not have (can_gain), picked by weight at
## map row `row` (seeded, see _relic_weight), of at least `min_rarity` while the pool still has
## enough such pieces. `pool`: all gear, only the ordinary pieces or only the rot-touched ones;
## `skip`: pieces already picked; `rare_rot`: rot-touched pieces weigh less (shop shelves).
func _pick_gear(salt: int, count: int, row: int, min_rarity: int = 0, pool: GearPool = GearPool.ANY,
		skip: Array[GearData] = [], rare_rot: bool = false) -> Array[GearData]:
	var all: Array[GearData] = []
	for item: GearData in data.gear:
		if item == null or not can_gain(item) or skip.has(item):
			continue
		if (pool == GearPool.NORMAL and item.rot_touched) or (pool == GearPool.ROT_TOUCHED and not item.rot_touched):
			continue
		all.append(item)
	var left: Array[GearData] = []
	for item: GearData in all:
		if item.rarity >= min_rarity:
			left.append(item)
	if left.size() < count:
		for item: GearData in all:
			if not left.has(item):
				left.append(item)
	var rng := CombatRng.new(_salted(salt))
	var picked: Array[GearData] = []
	while picked.size() < count and not left.is_empty():
		var weights: Array = []
		for g: GearData in left:
			weights.append(_relic_weight(g, row, rare_rot))
		var index := _weighted_index(rng, weights)
		if index < 0:
			break
		picked.append(left.pop_at(index))
	return picked


## A Relic's weight in a pick: by rarity at row `row`; a rot-touched piece on the shelves
## (`rare_rot`) tuning.rot_gear_weight_percent.
func _relic_weight(item: GearData, row: int, rare_rot: bool = false) -> int:
	var weight := rarity_weight(GEAR_WEIGHT, item.rarity, row)
	if rare_rot and item.rot_touched:
		weight = CombatMath.percent(weight, tuning.rot_gear_weight_percent)
	return weight


func can_buy_gear(item: GearData) -> bool:
	return item != null and can_gain(item) and gold >= gear_price(item)


## Pays for a shop Relic and gives it to hero `slot` (DESIGN.md 8.24). Returns the find
## (relic_find), or {} if it cannot be bought.
func buy_gear(item: GearData, slot: int) -> Dictionary:
	if not can_buy_gear(item) or slot < 0 or slot >= party_size():
		return {}
	gold -= gear_price(item)
	return give_relic(item, slot)


func _clamp_hp() -> void:
	for slot: int in hp.size():
		hp[slot] = clampi(hp[slot], 1, max_hp(slot))
