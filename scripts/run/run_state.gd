class_name RunState
extends RefCounted
## One run in progress (DESIGN.md 8): the map, where the party is on it, the party's HP (carried
## from fight to fight), max HP boosts, gold, each hero's level, XP and attribute points (DESIGN.md
## 8.2), the Relics the run has and each hero wears, the Echoes learned and worn (8.17, 8.19), and the
## shared backpack (DESIGN.md 8.1). The run's rules live here as plain integer maths so they
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
## Seeds the Relics a won fight's enemies drop (DESIGN.md 8.17).
const RELIC_SALT: int = 275604541
## Seeds which starting pacts a run offers (card #285).
const PACT_SALT: int = 295075153
## Phase 26 (DESIGN.md 8.22): a Fight stop's fight, and the weather of every run fight but the boss's.
const FIGHT_SALT: int = 405000041
const FIGHT_WEATHER_SALT: int = 426000017
## The map rules a new run is made with (see map_rules).
const MAP_RULES: int = 3
## The mastery an Echo needed before phase 21 (#280): an older save's mastery is scaled from it.
const LEGACY_MASTERY_NEEDED: int = 4
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
## Per party slot, tuning.run_gear_slots entries: GearData (a Relic) or null. Slots past
## open_relic_slots() are locked and always empty.
var gear: Array[Array] = []
## The run's Relics (DESIGN.md 8.17, 8.19): id -> level in this run (1 to tuning.relic_max_level;
## levels last one run, #280). The Relic bag's at the start (card #265, at level 1), and what the run
## finds; Main banks them into the collection (RelicFile.bank) when the run saves and when it ends.
## The whole team shares them: any hero can wear any of them.
var relics: Dictionary = {}
## Every Relic found before this run (id -> 1), bag or not: the end screen's "what you keep" line,
## and a find of one left at home joins the run at level 1 marked "home" rather than "new".
var relics_at_start: Dictionary = {}
## The Echo pips each found Relic had when the run started (id -> pips, from the collection; the
## host's online). Its pips now are these plus `mastery`.
var pips_at_start: Dictionary = {}
## Guards (mini-bosses) beaten this run: the first one opens a Relic slot.
var guards_beaten: int = 0
## Relic id -> Echo pips earned this run (on top of pips_at_start; their sum counts up to
## tuning.mastery_needed, when its Echo is learned for good). Kept whole (up to mastery_needed) even
## past what the host still needs, so an online friend banks them on top of their own (#281).
## Starts empty every run.
var mastery: Dictionary = {}
## Per party slot: the Echoes (Relic ids) the hero wears.
var echoes: Array[Array] = []
## The team gauge carried from the last fight into the next one (card #146).
var team_gauge: int = 0
## The shared backpack (items only: gear is always worn).
var backpack: Backpack
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
## The map rules the run was made with: 3 since phase 26 (a row of Guard stops, DESIGN.md 8.22), 2
## since phase 21 (rows that move, the crowned elite, card #286), 1 before; a run keeps the rules it
## was made with, so it continues on the map it had.
var map_rules: int = MAP_RULES
## "" while the run goes on, then VICTORY or DEFEAT.
var result: String = ""


## A new run of `run_data` with this seed at oath `p_oath` (0: none; kept inside the ladder): a
## fresh map, the starting gold and HP (the oaths can lower both), level 1. `collection`: the Relics
## found in earlier runs (none: a first run), and what each hero brings; they go on as slots open.
static func begin(run_data: RunData, p_tuning: Tuning, p_seed: int, p_oath: int = 0,
		collection: RelicCollection = null) -> RunState:
	var run := RunState.new()
	run._start(run_data, p_tuning, p_seed, p_oath, collection)
	return run


## Sets up a new game of `run_data` on this object (begin's body; a Fight Rush starts the same way,
## DESIGN.md 8.21). The map comes from _make_map, which a mode without a map overrides.
func _start(run_data: RunData, p_tuning: Tuning, p_seed: int, p_oath: int, collection: RelicCollection) -> void:
	data = run_data
	tuning = p_tuning
	run_seed = p_seed
	oath = OathData.clamp_oath(run_data.oaths, p_oath)
	map = _make_map(0)
	gold = maxi(0, p_tuning.run_start_gold + oath_total(&"start_gold_add"))
	backpack = Backpack.new(p_tuning.backpack_pockets)
	for c: CharacterData in run_data.party:
		bonus_points.append(0)
		max_hp_percent.append(100)
		tonics_used.append(0)
		levels.append(1)
		xps.append(0)
		attributes.append(Attributes.empty())
		var known: Array = []
		if c.skill_tree != null:
			for skill: AbilityData in c.skill_tree.starters():
				known.append(skill.id)
		unlocked.append(known.duplicate())
		loadout.append(known.slice(0, p_tuning.skill_slots))
		var slots: Array = []
		slots.resize(p_tuning.run_gear_slots)
		gear.append(slots)
		echoes.append([])
		defence.append([0, 0, 0, 0])
	if collection != null:
		_take_collection(collection)
	pact_pending = not relics_at_start.is_empty() and not run_data.pacts.is_empty() \
			and p_tuning.run_pact_choices > 0
	var start_hp := OathData.start_hp_for(run_data.oaths, oath)
	for slot: int in run_data.party.size():
		hp.append(maxi(1, CombatMath.percent(max_hp(slot), start_hp)))


## Which game this is: "run" (a Fight Rush says "rush", DESIGN.md 8.21). In to_dict, so a dict of
## one mode is never applied to the other.
func mode() -> String:
	return "run"


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
		"mode": mode(), "seed": run_seed, "at": at, "path": Array(path), "gold": gold, "hp": Array(hp),
		"max_hp_percent": Array(max_hp_percent), "tonics_used": Array(tonics_used), "levels": Array(levels), "xps": Array(xps),
		"attributes": attributes.duplicate(true), "team_gauge": team_gauge, "gear": worn,
		"unlocked": unlocked.duplicate(true), "loadout": loadout.duplicate(true),
		"backpack": backpack.to_array(),
		"fights_won": fights_won, "gold_earned": gold_earned, "result": result,
		"act": act, "visited": visited, "bonus_points": Array(bonus_points), "events_seen": Array(events_seen),
		"restocks": restocks, "oath": oath, "shop_sold": Array(shop_sold), "stop_done": stop_done, "stop_text": stop_text,
		"ambush_streak": ambush_streak, "ambush_id": ambush_id, "ambush_spoils": ambush_spoils,
		"relics": relics.duplicate(), "relics_start": relics_at_start.duplicate(),
		"pips_start": pips_at_start.duplicate(), "guards_beaten": guards_beaten,
		"defence": defence.duplicate(true), "flawless": flawless, "pact_pending": pact_pending, "sharpened": sharpened,
		"stop_rotten": stop_rotten, "map_rules": map_rules,
		"mastery": mastery.duplicate(), "echoes": echoes.duplicate(true),
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
	# A dict without a mode is a run's (saves from before the Fight Rush).
	if typeof(d.get("mode", "run")) != TYPE_STRING or String(d.get("mode", "run")) != mode():
		return false
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
	var new_pack := Backpack.from_array(d.backpack, items_by_id(), tuning.backpack_pockets)
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
	var relic_state := _relic_state_of(d, new_gear, by_id)
	if relic_state.is_empty():
		return false
	# Optional (saves from before card #283 lack them): the run's defence and a flawless spoils.
	var new_defence := _defence_of(d.get("defence"))
	if (d.has("defence") and new_defence.is_empty()) or (d.has("flawless") and typeof(d.flawless) != TYPE_BOOL):
		return false
	if (d.has("pact_pending") and typeof(d.pact_pending) != TYPE_BOOL) or (d.has("sharpened") and typeof(d.sharpened) != TYPE_BOOL) \
			or (d.has("stop_rotten") and typeof(d.stop_rotten) != TYPE_BOOL):
		return false
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
	relics = relic_state.relics
	relics_at_start = relic_state.start
	pips_at_start = relic_state.pips
	guards_beaten = int(relic_state.guards)
	mastery = relic_state.mastery
	echoes.assign(relic_state.echoes)
	if not new_defence.is_empty():
		defence = new_defence
	flawless = bool(d.get("flawless", false))
	pact_pending = bool(d.get("pact_pending", false))
	sharpened = bool(d.get("sharpened", false))
	stop_rotten = bool(d.get("stop_rotten", false))
	_lock_closed_slots()
	backpack = new_pack
	# A save from before phase 21 may hold Relics above the new top level: HP fits the new max.
	_clamp_hp()
	fights_won = int(d.fights_won)
	gold_earned = int(d.gold_earned)
	result = String(d.result)
	return true


## The Relic state in to_dict() data, checked: {relics, start, pips, guards, mastery, echoes}, or {}
## if it does not fit. A save from before phase 17 has none of it: it gets the Relics it wears, at
## level 1, no mastery and no Echoes. A save from before the bag (card #265) may still hold
## "relic_picks": it is ignored. A save from before phase 21 (#280) has no "pips_start": its levels
## are cut to the new top level and its mastery (out of the old 4) is scaled to the new pips.
func _relic_state_of(d: Dictionary, worn: Array[Array], by_id: Dictionary) -> Dictionary:
	var size := party_size()
	var state := {"relics": {}, "start": {}, "pips": {}, "guards": 0, "mastery": {}, "echoes": []}
	for slot: int in size:
		(state.echoes as Array).append([])
	if not d.has("relics"):
		for slots: Array in worn:
			for item: Variant in slots:
				if item != null:
					state.relics[(item as GearData).id] = 1
		# Gear came from a guard's spoils then: count one guard, so its slot stays open.
		state.guards = 1 if not (state.relics as Dictionary).is_empty() else 0
		state.start = (state.relics as Dictionary).duplicate()
		return state
	if not d.relics is Dictionary or not d.get("mastery") is Dictionary 			or not d.get("echoes") is Array or typeof(d.get("guards_beaten")) != TYPE_INT or int(d.guards_beaten) < 0:
		return {}
	for id: Variant in d.relics:
		var level: Variant = d.relics[id]
		if typeof(id) != TYPE_STRING or not by_id.has(String(id)) or typeof(level) != TYPE_INT or int(level) < 1:
			return {}
		state.relics[String(id)] = mini(int(level), tuning.relic_max_level)
	for slots: Array in worn:
		for item: Variant in slots:
			if item != null and not state.relics.has((item as GearData).id):
				return {}
	# Optional (saves from the first phase 17 builds lack it): the Relics the run started with.
	var start: Variant = d.get("relics_start", d.relics)
	if not start is Dictionary:
		return {}
	for id: Variant in start:
		if typeof(id) != TYPE_STRING or not by_id.has(String(id)) or typeof(start[id]) != TYPE_INT or int(start[id]) < 1:
			return {}
		state.start[String(id)] = 1
	var legacy := not d.has("pips_start")
	if not legacy:
		if not d.pips_start is Dictionary:
			return {}
		for id: Variant in d.pips_start:
			var value: Variant = d.pips_start[id]
			if typeof(id) != TYPE_STRING or not by_id.has(String(id)) or typeof(value) != TYPE_INT or int(value) < 0:
				return {}
			state.pips[String(id)] = mini(int(value), tuning.mastery_needed)
	for id: Variant in d.mastery:
		if typeof(id) != TYPE_STRING or not by_id.has(String(id)) or typeof(d.mastery[id]) != TYPE_INT or int(d.mastery[id]) < 0:
			return {}
		var earned := int(d.mastery[id])
		if legacy:
			earned = earned * tuning.mastery_needed / LEGACY_MASTERY_NEEDED
		state.mastery[String(id)] = clampi(earned, 0, tuning.mastery_needed)
	var lists: Array = d.echoes
	if lists.size() != size:
		return {}
	var kept: Array = []
	for ids: Variant in lists:
		if not ids is Array:
			return {}
		for id: Variant in ids:
			if typeof(id) != TYPE_STRING or not by_id.has(String(id)):
				return {}
		kept.append((ids as Array).duplicate())
	state.echoes = kept
	state.guards = int(d.guards_beaten)
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

## Max HP percent with tonics, level, Vitality (spent and from Relics), Relics and Echoes.
func total_max_hp_percent(slot: int) -> int:
	return max_hp_percent[slot] + (levels[slot] - 1) * tuning.run_level_hp_percent \
			+ attribute_total(slot, Attributes.Kind.VITALITY) * tuning.attr_vitality_hp_percent + gear_amount(slot, GearData.Effect.MAX_HP)


func max_hp(slot: int) -> int:
	return CombatSetup.scaled_max_hp(tuning, data.party[slot], total_max_hp_percent(slot))


## Power percent with level, Might, Relics and Echoes (100 = the character's normal power).
func power_percent(slot: int) -> int:
	return 100 + (levels[slot] - 1) * tuning.run_level_power_percent \
			+ attribute_total(slot, Attributes.Kind.MIGHT) * tuning.attr_might_power_percent + gear_amount(slot, GearData.Effect.POWER)


func power(slot: int) -> int:
	return CombatMath.percent_min1(CombatMath.percent_min1(tuning.base_party_damage, data.party[slot].power_percent),
			power_percent(slot))


func speed(slot: int) -> int:
	return maxi(1, data.party[slot].speed + speed_bonus(slot))


## Speed added to the hero's own: Agility, Relics and Echoes.
func speed_bonus(slot: int) -> int:
	return attribute_total(slot, Attributes.Kind.AGILITY) * tuning.attr_agility_speed + gear_amount(slot, GearData.Effect.SPEED)


## How much less enemy hits deal to this hero, in percent: Defense, Relics and Echoes (capped as the
## fight caps it).
func defense_percent(slot: int) -> int:
	return mini(int(passives(slot).get(Passive.TOUGH, 0)), tuning.tough_max_percent)


## This hero's chance of a critical hit, in percent (the base, Luck).
func crit_percent(slot: int) -> int:
	return mini(100, tuning.crit_base_percent + int(passives(slot).get(Passive.CRIT, 0)))


## What slot `slot`'s worn Relics and Echoes add up to for one effect: the effects add, rot-touched
## drawbacks take away (GearData.contribution), so the total can be below 0.
func gear_amount(slot: int, effect: GearData.Effect) -> int:
	var total := 0
	for item: GearData in effect_sources(slot):
		total += item.contribution(effect)
	return total


## The Relics whose effect hero `slot` has: the ones they wear, then their Echoes (an Echo of a
## Relic they also wear counts once).
func effect_sources(slot: int) -> Array[GearData]:
	var found: Array[GearData] = []
	for item: Variant in gear[slot]:
		if item != null:
			found.append(item as GearData)
	if slot < echoes.size():
		for id: Variant in echoes[slot]:
			var item := relic_by_id(String(id))
			if item != null and not found.has(item):
				found.append(item)
	return found


## The passives slot `slot` brings into fights (Passive keys -> amount): their Relics' and Echoes',
## and the rot of the curses carried.
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
## The map of act `index` by `rules` (map_rules when -1): 2 and up move rows, 3 and up have a row of
## Guard stops.
func _make_map(index: int, rules: int = -1) -> RunMap:
	var rng := CombatRng.new(run_seed if index == 0 else absi(run_seed * 31 + index * ACT_SALT) % 2147483647 + 1)
	var act_info := act_data(index)
	var made_by := map_rules if rules < 0 else rules
	return RunMap.generate(rng, tuning, act_info.zones.size(), not act_info.elites.is_empty(),
			not act_info.events.is_empty(), made_by >= 2, made_by >= 3)


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
func choose_event(choice: EventChoiceData, stop_id: int, index: int, pick: int = -1) -> Dictionary:
	var items: Array[ItemData] = []
	var scale := event_scale(stop_id)
	if not can_choose(choice, stop_id) or (choice.deal != null and not pick_fits(choice.deal, pick)):
		return {"ok": false, "text": "You cannot pay that.", "items": items, "risk": false, "ambush": false}
	var lines: Array[String] = []
	if not choice.done_text.is_empty():
		lines.append(choice.done_text)
	if choice.deal != null:
		var got := take_offer(choice.deal, stop_id, 1000 + index, scale, pick)
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
		var got := take_offer(choice.risk_deal, stop_id, 1050 + index, scale, -1, true)
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


## Backpack items an event may take: everything but rotten items (nobody misses those).
func losable_uids() -> Array[int]:
	var found: Array[int] = []
	if backpack == null:
		return found
	for e: Dictionary in backpack.entries:
		if not (e.item as ItemData).rotten:
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
## rare or better item; the rotten one a rare or better Relic (one a copy still helps), but
## tuning.rotten_chest_curse_percent of the time a curse comes with it and
## rotten_chest_fight_percent of the time (on top) an ambush from the act's pool. Applies the gold,
## the curse and the ambush; the prize comes back for the screen to hand out. Seeded per stop, so a
## continued run gets the same. Returns {prize: Resource or null, gold: int, curse: ItemData or null,
## ambush: bool, text: String}.
func open_treasure(stop_id: int, rotten: bool) -> Dictionary:
	var row := _row_of(stop_id) + 4
	var rng := CombatRng.new(_salted(stop_id * TREASURE_SALT + act * 41 + (7 if rotten else 0)))
	var got := {"prize": null, "gold": 0, "curse": null, "ambush": false, "text": ""}
	var parts: Array[String] = []
	if not rotten:
		var item := _pick_found(rng, row, ItemData.Rarity.RARE)
		got.prize = item if item != null else _pick_found(rng, row)
		got.gold = take_treasure_gold()
		parts.append("+%d gold" % int(got.gold))
	else:
		var relics := _pick_gear(stop_id * TREASURE_SALT + act * 41 + 13, 1, row, ItemData.Rarity.RARE, GearPool.ANY)
		got.prize = relics[0] if not relics.is_empty() else null
		var roll := rng.range_int(0, 99)
		var curses: Array[ItemData] = []
		for item: ItemData in data.found_items:
			if item != null and item.is_curse():
				curses.append(item)
		if roll < tuning.rotten_chest_curse_percent and not curses.is_empty():
			var curse := curses[rng.range_int(0, curses.size() - 1)]
			if add_item(curse) >= 0:
				got.curse = curse
				parts.append("The %s settles in your pack" % curse.display_name)
		elif roll < tuning.rotten_chest_curse_percent + tuning.rotten_chest_fight_percent \
				and not act_data().ambushes.is_empty() and not in_ambush():
			var foe := act_data().ambushes[rng.range_int(0, act_data().ambushes.size() - 1)]
			if foe != null:
				_set_ambush(foe, false)
				got.ambush = true
				parts.append("Something was waiting inside!")
	if got.prize is GearData:
		parts.push_front("Inside: %s" % (got.prize as GearData).display_name)
	elif got.prize is ItemData:
		parts.push_front("Inside: %s" % (got.prize as ItemData).display_name)
	got.text = ". ".join(parts) + "."
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


## New wares on the shelves for restock_price() gold (shop_stock and shop_gear change).
func restock() -> bool:
	var price := restock_price()
	if gold < price:
		return false
	gold -= price
	restocks += 1
	shop_sold.clear()
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


## The guard at Guard stop `stop_id`: its place's (ZoneData.guard), in its deep version in a deep
## act or row. Null for another stop or a place with no guard.
func guard_of(stop_id: int) -> EncounterData:
	var stop := map.stop(stop_id)
	if int(stop.get("type", -1)) != RunMap.StopType.GUARD:
		return null
	var zone := zone_of(stop)
	return _deep_version(zone.guard if zone != null else null, stop_id)


## The fight at the current stop: an ambush sprung there, else the Fight, Guard or elite stop's, or
## the act's boss (null: a stop with no fight).
func encounter_now() -> EncounterData:
	if in_ambush():
		return ambush_encounter()
	match int(current().get("type", -1)):
		RunMap.StopType.FIGHT:
			return fight_of(at)
		RunMap.StopType.GUARD:
			return guard_of(at)
		RunMap.StopType.ELITE:
			return elite_of(at)
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


## Gold this run gets for an encounter, with the party's gold Relics and Echoes, then the
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
			setup.items.append({"uid": int(e.uid), "item": e.item, "amount": entry_amount(e), "name": entry_name(e)})
	setup.start_team_gauge = clampi(team_gauge, 0, tuning.team_gauge_max)
	if in_ambush():
		# An ambush is sprung on the party: no running unless the tuning allows it.
		setup.can_run = setup.can_run and tuning.ambush_can_run
	# The marks wait for the second map row (card #253): the first teaches the hits alone.
	setup.allow_marks = _depth() > 0
	if _scales(encounter):
		setup.enemy_hp_percent = CombatMath.percent(enemy_hp_percent(encounter), encounter.enemy_hp_percent)
		setup.enemy_power_percent = enemy_power_percent(encounter)
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
	var tempo := tuning.attack_tempo_percent - _fight_depth(encounter) * maxi(0, tuning.run_enemy_tempo_row_percent)
	if encounter.boss:
		tempo = CombatMath.percent(tempo, tuning.boss_tempo_percent)
	elif encounter.mini_boss:
		tempo = CombatMath.percent(tempo, tuning.guard_tempo_percent)
	elif encounter.elite:
		tempo = CombatMath.percent(tempo, tuning.elite_tempo_percent)
	return maxi(tempo, CombatSetup.tempo_floor(tuning))


## Enemy HP at the current stop's depth, in percent of their data (DESIGN.md 8.3). `encounter`: the
## fight it is for (null: any; a run grows every fight by the same depth).
func enemy_hp_percent(encounter: EncounterData = null) -> int:
	return 100 + _fight_depth(encounter) * maxi(0, tuning.run_enemy_hp_row_percent + oath_total(&"enemy_hp_row_add"))


## Enemy power at the current stop's depth, in percent of their data.
func enemy_power_percent(encounter: EncounterData = null) -> int:
	return 100 + _fight_depth(encounter) * maxi(0, tuning.run_enemy_power_row_percent + oath_total(&"enemy_power_row_add"))


## Map rows walked so far: the rows of the acts before this one, then this act's row.
func _depth() -> int:
	return act * (tuning.run_map_rows + 1) + maxi(0, int(current().get("row", 0)))


## The depth `_encounter` grows by (a run: _depth() for every fight; a Fight Rush counts a boss only
## from where a run meets it, DESIGN.md 8.21).
func _fight_depth(_encounter: EncounterData) -> int:
	return _depth()


## True if `encounter` grows with depth at all (a run's bosses only with run_enemy_scale_bosses).
func _scales(encounter: EncounterData) -> bool:
	return not encounter.boss or tuning.run_enemy_scale_bosses


## True if this game shows gold (the strip, the party screen, sell prices, the win's gold chip and
## sound). A Fight Rush has none (DESIGN.md 8.21).
func shows_gold() -> bool:
	return true


## True if worn Relics earn Echo pips here (the pips bars and the Echoes learning row show).
func teaches_echoes() -> bool:
	return true


## Takes the items used in a fight out of the backpack (uids that are already gone are skipped).
func spend_items(uids: Array[int]) -> void:
	for uid: int in uids:
		backpack.remove(uid)
	_clamp_hp()


## A fight ended with these party HPs (per slot). A victory pays gold and XP (each hero their own,
## less for the downed), drops Relics, gives the worn Relics their mastery, counts a guard (a Relic
## slot opens) and gets the downed back up at tuning.run_downed_revive_hp; a defeat ends the run.
## Returns {gold, xp: per slot, levels: per slot (levels gained), relics: the finds (add_relic
## infos), echoes: the Relics whose Echo was learned}.
func finish_fight(fight_result: String, party_hp: Array[int], encounter: EncounterData,
		recap: Dictionary = {}) -> Dictionary:
	var none := {"gold": 0, "xp": _zeros(), "levels": _zeros(), "relics": [], "echoes": []}
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
	# Seeded by the fights won before this one, like the end screen's preview.
	var drops := relic_drops(encounter)
	var learned := _master_worn(encounter)
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
	var finds: Array = []
	for item: GearData in drops:
		finds.append(add_relic(item))
	if encounter != null and encounter.mini_boss:
		guards_beaten += 1
	if int(current().get("type", -1)) == RunMap.StopType.FINAL and is_last_act():
		result = VICTORY
	return {"gold": won, "xp": gained, "levels": up, "relics": finds, "echoes": learned}


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


## The XP a standing hero gets for winning `encounter` here (its enemies' XP in a run).
func xp_full(encounter: EncounterData) -> int:
	return encounter_xp(encounter)


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


## Points in one attribute with the stat lines of the Relics the hero wears (DESIGN.md 8.17).
func attribute_total(slot: int, kind: int) -> int:
	return attribute(slot, kind) + relic_stat(slot, kind)


## The attribute points the Relics hero `slot` wears give to one attribute.
func relic_stat(slot: int, kind: int) -> int:
	var total := 0
	if slot < gear.size():
		for item: Variant in gear[slot]:
			if item != null and (item as GearData).stat == kind:
				total += (item as GearData).stat_points_at(relic_level(item as GearData))
	return total


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


func upgrade_price() -> int:
	return shop_price(tuning.shop_upgrade_price)


## Heals one character (never above max HP). Returns how much was healed. `scaled`: gear that
## changes the healing a hero receives (DESIGN.md 8.16) applies; a Tonic's new HP is not a heal.
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


## Puts `item` in the first free pocket. Returns its uid, or -1 if the pack is full. An upgrade (a
## bigger pack) is used at once instead and returns 0; treasure turns into gold at once (its
## treasure_gold) and returns 0 too (card #282: it takes no pocket).
func add_item(item: ItemData) -> int:
	if item != null and item.kind == ItemData.Kind.UPGRADE:
		take_upgrade(item)
		return 0
	if item != null and item.kind == ItemData.Kind.TREASURE:
		var won := treasure_gold(item)
		gold += won
		gold_earned += won
		return 0
	return backpack.add_anywhere(item)


## The gold a treasure turns into the moment it is found: what selling it paid (card #282).
func treasure_gold(item: ItemData) -> int:
	return sell_price(item.price) if item != null else 0


## A find in a few words for a stop or a fight's drop: "Found: Salve", "Silver Ring: +20 gold", "Bigger
## Pack: 7 pockets". Call it after add_item.
func find_text(item: ItemData) -> String:
	if item == null:
		return ""
	if item.kind == ItemData.Kind.TREASURE:
		return "%s: +%d gold" % [item.display_name, treasure_gold(item)]
	if item.kind == ItemData.Kind.UPGRADE:
		return "%s: %d pockets" % [item.display_name, backpack.width]
	return "Found: %s" % item.display_name


## True if `item` would do something if the party got it now (an upgrade with room left to grow).
func wants(item: ItemData) -> bool:
	if item == null:
		return false
	if item.kind == ItemData.Kind.UPGRADE:
		return item.effect == ItemData.Effect.ADD_ROW and backpack.width < tuning.backpack_max_pockets
	if item.effect == ItemData.Effect.MAX_HP_ONE:
		for slot: int in party_size():
			if tonics_left(slot) > 0:
				return true
		return false
	return true


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


## Puts `item` (at `level`) in pocket x (`y` and `turn` are from the old grid: 0). Returns its uid,
## or -1 if that pocket is taken.
func place_item(item: ItemData, x: int, y: int = 0, turn: int = 0, level: int = 0) -> int:
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
			max_hp_percent[slot] += item.amount_percent
			tonics_used[slot] += 1
			heal(slot, max_hp(slot) - before, false)


# --- levels, rot and combining (DESIGN.md 8.1) --------------------------------------------------

## A placed item's level (0, higher once combined).
static func level_of(e: Dictionary) -> int:
	return int(e.get("level", 0))


## A placed item's effect percent: its own, stronger by tuning.combine_bonus_percent per level.
func entry_amount(e: Dictionary) -> int:
	# A Tonic's max HP never grows with levels (card #198): that would get round tonic_max_per_hero.
	if (e.item as ItemData).effect == ItemData.Effect.MAX_HP_ONE:
		return (e.item as ItemData).amount_percent
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


## The HP percent every hero loses each turn in a fight from the curses (rotten items) carried.
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


## Applies an upgrade the moment the party gets it (a Bigger Pack: one more pocket). False if it
## does nothing (not an upgrade, or the pack is already as big as it gets).
func take_upgrade(item: ItemData) -> bool:
	if item == null or item.kind != ItemData.Kind.UPGRADE:
		return false
	if item.effect == ItemData.Effect.ADD_ROW and backpack.width < tuning.backpack_max_pockets:
		backpack.width += 1
		return true
	return false


## A backpack or gear change as plain data, from any player (online, clients send these to the
## host, which applies them in the order they arrive: DESIGN.md 8.1). Ops:
## {op: "move", uid, x, y, turn}, {op: "drop", uid}, {op: "use", uid, slot}, {op: "sell", uid},
## {op: "combine", uid, into},
## {op: "swap_gear", from: [slot, gear_slot], to: [slot, gear_slot]},
## {op: "wear", slot, gear_slot, relic: id} (a Relic the run has), {op: "take_off", slot, gear_slot},
## {op: "echo", slot, relic: id, on: bool},
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
		"wear":
			return ints.call(["slot", "gear_slot"]) and typeof(op.get("relic")) == TYPE_STRING 					and wear(int(op.slot), int(op.gear_slot), relic_by_id(String(op.relic)), true) == 0
		"take_off":
			return ints.call(["slot", "gear_slot"]) and take_off(int(op.slot), int(op.gear_slot))
		"echo":
			return ints.call(["slot"]) and typeof(op.get("relic")) == TYPE_STRING and typeof(op.get("on")) == TYPE_BOOL 					and set_echo(int(op.slot), relic_by_id(String(op.relic)), bool(op.on))
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


## True if the party can pay for an event choice's or a pact's deal. HP prices can always be paid (a
## hero never drops below 1 HP for one); an event's deal (`scale` is its gold and XP percent, see
## event_scale) also needs a hero who can still lose max HP, something in the backpack to lose, and
## room for a curse. A deal that asks for a pick is checked again when it is taken.
func can_take_offer(offer: ZoneOfferData, scale: int = 100) -> bool:
	if offer == null or gold < CombatMath.percent(offer.cost_gold, scale):
		return false
	if offer.cost_max_hp_percent > 0:
		var anyone := false
		for slot: int in party_size():
			anyone = anyone or hero_can_lose_max_hp(slot)
		if not anyone:
			return false
	if offer.cost_item != ZoneOfferData.ItemCost.NONE and losable_uids().is_empty():
		return false
	return offer.cost_rotten == null or not backpack.find_spot(offer.cost_rotten).is_empty()


## Takes deal `index` of the event at stop `stop_id` (DESIGN.md 8.7): pays its price and
## gives its gifts, all but the item, which comes back for the caller to put in the backpack. Returns
## {ok: bool, text: String (what happened, one line), item: ItemData or null}. Nothing changes if
## the deal cannot be paid. `scale`: percent for the deal's gold and XP; `pick`: the hero or item the
## player picked (see ZoneOfferData.pick_kind); `forced` (a risk): never refused, it takes what
## there is.
func take_offer(offer: ZoneOfferData, stop_id: int, index: int, scale: int = 100, pick: int = -1,
		forced: bool = false) -> Dictionary:
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
	if offer.cost_rotten != null:
		if add_item(offer.cost_rotten) >= 0:
			parts.append("The %s settles in your pack" % offer.cost_rotten.display_name)
		else:
			parts.append("The %s finds no room and rots away" % offer.cost_rotten.display_name)
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
			parts.append(relic_find_text(add_relic(gifts[0])))
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
	var label := entry_name(backpack.entry(uid))
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


# --- Relics (DESIGN.md 8.17; "gear" in the code) ----------------------------------------------

var _relic_index: Dictionary = {}


## The run's Relic with this id (null: none).
func relic_by_id(id: String) -> GearData:
	if _relic_index.is_empty():
		for item: GearData in data.gear:
			if item != null:
				_relic_index[item.id] = item
	return _relic_index.get(id) as GearData


## True if the run has this Relic (found in an earlier run or in this one).
func owns(item: GearData) -> bool:
	return item != null and relics.has(item.id)


## The Relic's level in this run (0: not in the run).
func relic_level(item: GearData) -> int:
	return int(relics.get(item.id, 0)) if item != null else 0


## True if the Relic was found before this run but left at home (not in the bag, card #265) and has
## not turned up in this run yet: a find of it joins the run at level 1, marked "home".
func is_home(item: GearData) -> bool:
	return item != null and relics_at_start.has(item.id) and relic_level(item) <= 0


## True if someone in the party wears this Relic.
func is_worn(item: GearData) -> bool:
	return wearer_of(item) >= 0


## The hero wearing this Relic (-1: nobody).
func wearer_of(item: GearData) -> int:
	for slot: int in gear.size():
		if (gear[slot] as Array).has(item):
			return slot
	return -1


## The Relic slot the Relic is worn in (-1: not worn).
func wear_slot_of(item: GearData) -> int:
	var slot := wearer_of(item)
	return (gear[slot] as Array).find(item) if slot >= 0 else -1


## True if another copy of the Relic still does something in this run: it is not in the run yet, or
## below the top level. Levels last one run (#280), so spoils never run dry.
func can_gain(item: GearData) -> bool:
	return item != null and relic_level(item) < tuning.relic_max_level


## Every Relic the run has, in the run's order.
func owned_relics() -> Array[GearData]:
	var found: Array[GearData] = []
	for item: GearData in data.gear:
		if item != null and owns(item):
			found.append(item)
	return found


## A Relic found (a drop, spoils, a shop, a chest): one not in the run joins it at level 1 ("new" if
## it was never found, "home" if it was left at home), a copy raises the run's level, a copy past the
## top level turns into tuning.relic_spare_gold. Levels last one run (#280). Returns {item, new, home,
## level, gold} (gold: what a spare copy paid).
func add_relic(item: GearData) -> Dictionary:
	var info := {"item": item, "new": false, "home": false, "level": 0, "gold": 0}
	if item == null:
		return info
	var level := relic_level(item)
	if level <= 0:
		info.home = is_home(item)
		info.new = not info.home
		relics[item.id] = 1
	elif level < tuning.relic_max_level:
		relics[item.id] = level + 1
		_clamp_hp()
	else:
		gold += tuning.relic_spare_gold
		gold_earned += tuning.relic_spare_gold
		info.gold = tuning.relic_spare_gold
	info.level = relic_level(item)
	return info


## What the run keeps forever, won or lost, for its end screen: the Relics found for the first time
## and the Echoes learned for good ("Nothing new to keep." if neither).
func relic_gain_line() -> String:
	return relic_gain_line_since(relics_at_start, pips_at_start)


## The same line measured from another collection (an online friend's own: `found_before` id -> any,
## `pips_before` id -> pips, card #281). A late joiner's run end shows RunEndScreen.own_kept instead.
func relic_gain_line_since(found_before: Dictionary, pips_before: Dictionary) -> String:
	var found := PackedStringArray()
	for item: GearData in owned_relics():
		if not found_before.has(item.id):
			found.append(item.display_name)
	var totals := pips_totals_from(pips_before)
	var learned := PackedStringArray()
	for item: GearData in data.gear:
		if item != null and int(pips_before.get(item.id, 0)) < tuning.mastery_needed \
				and int(totals.get(item.id, 0)) >= tuning.mastery_needed:
			learned.append(item.display_name)
	if found.is_empty() and learned.is_empty():
		return "Nothing new to keep."
	var parts := PackedStringArray()
	if not found.is_empty():
		parts.append("New Relics: " + ", ".join(found))
	if not learned.is_empty():
		parts.append("Echoes learned: " + ", ".join(learned))
	return "   ".join(parts)


## A find from add_relic() in a word or two, for a toast next to the Relic's icon: "New", "Home"
## (one left at home), "Lv 2", "+30" (a spare copy's gold).
static func relic_find_short(info: Dictionary) -> String:
	if bool(info.get("new", false)):
		return "New"
	if bool(info.get("home", false)):
		return "Home"
	if int(info.get("gold", 0)) > 0:
		return "+%d" % int(info.gold)
	return "Lv %d" % int(info.get("level", 0))


## One line for a find from add_relic(): "New Relic: Iron Charm", "Found: Iron Charm" (one left at
## home), "Iron Charm is now level 2", "Iron Charm is at its top level: +30 gold".
static func relic_find_text(info: Dictionary) -> String:
	var item := info.get("item") as GearData
	if item == null:
		return ""
	if bool(info.new):
		return "New Relic: %s" % item.display_name
	if bool(info.get("home", false)):
		return "Found: %s" % item.display_name
	if int(info.gold) > 0:
		return "%s is at its top level: +%d gold" % [item.display_name, int(info.gold)]
	return "%s is now level %d" % [item.display_name, int(info.level)]


## How many Relic slots each hero has open now: tuning.relic_slots_start, one more after the first
## guard, one more after act 1's boss, with the oaths (never under one, never past run_gear_slots).
func open_relic_slots() -> int:
	var open := tuning.relic_slots_start + (1 if guards_beaten > 0 else 0) + (1 if act > 0 else 0)
	return clampi(open + oath_total(&"relic_slots_add"), 1, tuning.run_gear_slots)


## True if Relic slot `gear_slot` is open.
func slot_open(gear_slot: int) -> bool:
	return gear_slot >= 0 and gear_slot < open_relic_slots()


## Why Relic slot `gear_slot` is still shut, in a few words ("" if it is open): the first thing still
## to come (the first guard, then act 1's boss) after which it would be open, oaths counted.
func slot_lock_text(gear_slot: int) -> String:
	if slot_open(gear_slot):
		return ""
	var real_guards := guards_beaten
	var real_act := act
	var text := ""
	if guards_beaten <= 0:
		guards_beaten = 1
		if slot_open(gear_slot):
			text = "Opens after the first guard."
	if text.is_empty() and act <= 0:
		act = 1
		if slot_open(gear_slot):
			text = "Opens after act 1's boss."
	guards_beaten = real_guards
	act = real_act
	if text.is_empty():
		text = "Shut by your oath." if oath_total(&"relic_slots_add") < 0 else "Shut."
	return text


## Puts Relic `item` on hero `slot` in Relic slot `gear_slot` (open slots only). What was worn there
## goes back to the run's Relics (nothing is sold). A Relic the run does not have yet joins it (a find
## worn at once) unless `only_owned`. A Relic worn by someone else must be moved with swap_gear. An
## Echo of it the hero wears comes off (the effect counts once). HP never rises from putting a Relic
## on (no free heal), and is cut to a lower max. Returns 0, or -1 if it cannot be worn there.
func wear(slot: int, gear_slot: int, item: GearData, only_owned: bool = false) -> int:
	if item == null or is_worn(item) or slot < 0 or slot >= gear.size() or not slot_open(gear_slot) \
			or gear_slot >= gear[slot].size() or (only_owned and not owns(item)) or relic_by_id(item.id) != item:
		return -1
	if not owns(item):
		add_relic(item)
	gear[slot][gear_slot] = item
	(echoes[slot] as Array).erase(item.id)
	_clamp_hp()
	return 0


## Takes the Relic off hero `slot`'s Relic slot `gear_slot` (it stays the run's). False if empty.
func take_off(slot: int, gear_slot: int) -> bool:
	if slot < 0 or slot >= gear.size() or gear_slot < 0 or gear_slot >= gear[slot].size() or gear[slot][gear_slot] == null:
		return false
	gear[slot][gear_slot] = null
	_clamp_hp()
	return true


## Swaps what two Relic slots hold (between heroes or on one hero). The first slot must hold
## something; both must be open. HP never rises from it and is cut to a lower max.
func swap_gear(from_slot: int, from_gear: int, to_slot: int, to_gear: int) -> bool:
	for pair: Array in [[from_slot, from_gear], [to_slot, to_gear]]:
		if pair[0] < 0 or pair[0] >= gear.size() or not slot_open(pair[1]) or pair[1] >= gear[pair[0]].size():
			return false
	var moving: Variant = gear[from_slot][from_gear]
	if moving == null or (from_slot == to_slot and from_gear == to_gear):
		return false
	gear[from_slot][from_gear] = gear[to_slot][to_gear]
	gear[to_slot][to_gear] = moving
	for pair: Array in [[from_slot, from_gear], [to_slot, to_gear]]:
		var now: Variant = gear[pair[0]][pair[1]]
		if now != null:
			(echoes[pair[0]] as Array).erase((now as GearData).id)
	_clamp_hp()
	return true


## The first open, empty Relic slot of hero `slot`, or -1.
func free_gear_slot(slot: int) -> int:
	for g: int in open_relic_slots():
		if g < gear[slot].size() and gear[slot][g] == null:
			return g
	return -1


## The run's Relics nobody wears.
func unworn_relics() -> Array[GearData]:
	var found: Array[GearData] = []
	for item: GearData in owned_relics():
		if not is_worn(item):
			found.append(item)
	return found


## Takes in the collection at the start of a run (cards #265, #266, #280): the Relics in its bag
## join the run at level 1 (only ones this run knows, at most the bag's size); nobody wears them yet,
## the player puts them on from the party screen. What was found and each Relic's Echo pips are
## remembered (the learned Echoes can be worn all run, any Relic or none).
func _take_collection(collection: RelicCollection) -> void:
	for item: GearData in data.gear:
		if item != null and collection.owns(item.id):
			relics_at_start[item.id] = 1
			var filled := mini(collection.pips_of(item.id), tuning.mastery_needed)
			if filled > 0:
				pips_at_start[item.id] = filled
	var size := collection.bag_size(tuning)
	for id: String in collection.bag_ids():
		var item := relic_by_id(id)
		if item != null and relics.size() < size:
			relics[id] = 1


## The bot (and tests): every open, empty Relic slot gets the best Relic the run has that nobody
## wears (GearBot's score, rarest first; prices it refuses are passed over), heroes in turn.
## Returns how many went on.
func auto_wear() -> int:
	var put := 0
	for g: int in open_relic_slots():
		for slot: int in party_size():
			if g >= gear[slot].size() or gear[slot][g] != null:
				continue
			var best: GearData = null
			for item: GearData in unworn_relics():
				if GearBot.score(item) >= 0 and (best == null or GearBot.score(item) > GearBot.score(best)):
					best = item
			if best != null and wear(slot, g, best, true) == 0:
				put += 1
	return put


## Relics in slots that are shut (a save from before phase 17) come off; they stay the run's.
func _lock_closed_slots() -> void:
	for slot: int in gear.size():
		for g: int in range(open_relic_slots(), gear[slot].size()):
			gear[slot][g] = null


# --- drops and Echo pips (DESIGN.md 8.17, 8.19) ------------------------------------------------

## The Relics a win over `encounter` here would drop (seeded by the stop and the fights won, so the
## end screen, the run and every machine agree): each enemy with drops gives one of them by
## tuning.relic_drop_percent.
func relic_drops(encounter: EncounterData) -> Array[GearData]:
	var found: Array[GearData] = []
	if encounter == null:
		return found
	var rng := CombatRng.new(_salted(at * RELIC_SALT + fights_won * 101 + visited * 7))
	for e: EnemyData in encounter.enemies:
		if e == null or e.relic_drops.is_empty():
			continue
		if rng.range_int(0, 99) >= tuning.relic_drop_percent:
			continue
		var item: GearData = e.relic_drops[rng.range_int(0, e.relic_drops.size() - 1)]
		var known := relic_by_id(item.id) if item != null else null
		if known != null:
			found.append(known)
	return found


## Echo pips a worn Relic gets for winning `encounter`.
func mastery_gain(encounter: EncounterData) -> int:
	if encounter == null:
		return 0
	if encounter.boss:
		return tuning.mastery_boss
	if encounter.mini_boss:
		return tuning.mastery_guard
	if encounter.elite:
		return tuning.mastery_elite
	return tuning.mastery_fight


## A Relic's Echo pips now: the ones it had at the start of the run plus this run's (never past
## tuning.mastery_needed).
func mastery_of(item: GearData) -> int:
	if item == null:
		return 0
	return mini(tuning.mastery_needed, int(pips_at_start.get(item.id, 0)) + int(mastery.get(item.id, 0)))


## True if the Relic's Echo is learned for good (before this run or during it).
func echo_learned(item: GearData) -> bool:
	return mastery_of(item) >= tuning.mastery_needed


## Every learned Echo, in the run's order: any hero can wear one for its Echo points, whether the run
## has its Relic or not (#280, option A).
func learned_echoes() -> Array[GearData]:
	var found: Array[GearData] = []
	for item: GearData in data.gear:
		if item != null and echo_learned(item):
			found.append(item)
	return found


## The Echoes learned for good during this run (the end screen's "what you keep").
func echoes_learned_this_run() -> Array[GearData]:
	var found: Array[GearData] = []
	for item: GearData in learned_echoes():
		if int(pips_at_start.get(item.id, 0)) < tuning.mastery_needed:
			found.append(item)
	return found


## Every Relic's pips now (id -> pips, the ones above 0): what Main banks into the collection.
func pips_totals() -> Dictionary:
	return pips_totals_from(pips_at_start)


## This run's pips on top of `start` (id -> pips: the host's, or an online friend's own collection,
## card #281), each never past tuning.mastery_needed; only the ones above 0.
func pips_totals_from(start: Dictionary) -> Dictionary:
	return pips_totals_since(start, {})


## This run's pips earned since `mastery_before` (the run's `mastery` when an online friend joined
## late, card #304; empty: the whole run) on top of `start`, each never past mastery_needed; only the
## ones above 0.
func pips_totals_since(start: Dictionary, mastery_before: Dictionary) -> Dictionary:
	var totals := {}
	for item: GearData in data.gear:
		if item == null:
			continue
		var gained := maxi(0, int(mastery.get(item.id, 0)) - int(mastery_before.get(item.id, 0)))
		var total := mini(tuning.mastery_needed, int(start.get(item.id, 0)) + gained)
		if total > 0:
			totals[item.id] = total
	return totals


## The run's Relic ids that were not in `relics_before` (id -> level when a friend joined late, card
## #304; empty: every one), in the run's Relic order: what a late joiner banks as found.
func relic_ids_since(relics_before: Dictionary) -> Array:
	var ids: Array = []
	for item: GearData in owned_relics():
		if not relics_before.has(item.id):
			ids.append(item.id)
	return ids


## The worn Relics whose Echo a win over `encounter` would teach (for the end screen).
func echoes_from_win(encounter: EncounterData) -> Array[GearData]:
	var found: Array[GearData] = []
	var gain := mastery_gain(encounter)
	for slots: Array in gear:
		for item: Variant in slots:
			if item != null and not echo_learned(item as GearData) \
					and mastery_of(item as GearData) + gain >= tuning.mastery_needed:
				found.append(item as GearData)
	return found


## The end screen's lines for a win over `encounter` here: the Relics it drops (read as add_relic
## would add them), the Echoes it teaches and a Relic slot it opens. Changes nothing.
func win_relic_lines(encounter: EncounterData) -> Array[String]:
	var lines: Array[String] = []
	var levels := relics.duplicate()
	for item: GearData in relic_drops(encounter):
		var level := int(levels.get(item.id, 0))
		var home := level <= 0 and relics_at_start.has(item.id)
		var info := {"item": item, "new": level <= 0 and not home, "home": home,
				"level": mini(level + 1, tuning.relic_max_level),
				"gold": tuning.relic_spare_gold if level >= tuning.relic_max_level else 0}
		levels[item.id] = info.level
		lines.append(relic_find_text(info))
	for item: GearData in echoes_from_win(encounter):
		lines.append("Echo learned for good: %s" % item.display_name)
	var before := open_relic_slots()
	var real_guards := guards_beaten
	var real_act := act
	if encounter != null and encounter.mini_boss:
		guards_beaten += 1
	elif int(current().get("type", -1)) == RunMap.StopType.FINAL and not is_last_act():
		# An act's boss: the next act opens (next_act), and with it act 1's slot.
		act += 1
	var after := open_relic_slots()
	guards_beaten = real_guards
	act = real_act
	if after > before:
		# Nothing goes on by itself (card #265): the player puts a Relic on from the party screen.
		lines.append("A Relic slot opens: Y to put a Relic on")
	return lines


## A won fight: every worn Relic gets its Echo pips. Returns the Echoes this taught for good.
func _master_worn(encounter: EncounterData) -> Array[GearData]:
	var learned := echoes_from_win(encounter)
	var gain := mastery_gain(encounter)
	for slots: Array in gear:
		for item: Variant in slots:
			if item != null:
				var id := (item as GearData).id
				mastery[id] = clampi(int(mastery.get(id, 0)) + gain, 0, tuning.mastery_needed)
	return learned


# --- Echoes (DESIGN.md 8.17) ------------------------------------------------------------------

## Echo points hero `slot` has: tuning.echo_start_points plus echo_points_per_level per level up,
## with the oaths (Forgetting halves them).
func echo_points(slot: int) -> int:
	var base := tuning.echo_start_points + (levels[slot] - 1) * tuning.echo_points_per_level
	return CombatMath.percent(maxi(0, base), maxi(0, 100 + oath_total(&"echo_points_percent_add")))


## Echo points hero `slot` has used on the Echoes they wear.
func echo_points_used(slot: int) -> int:
	var used := 0
	for id: Variant in echoes[slot]:
		var item := relic_by_id(String(id))
		if item != null:
			used += item.echo_cost
	return used


func free_echo_points(slot: int) -> int:
	return echo_points(slot) - echo_points_used(slot)


## True if hero `slot` wears the Echo of `item`.
func wears_echo(slot: int, item: GearData) -> bool:
	return item != null and slot >= 0 and slot < echoes.size() and (echoes[slot] as Array).has(item.id)


## The hero wearing the Echo of `item` (-1: nobody). One hero per Echo (#280).
func echo_wearer(item: GearData) -> int:
	for slot: int in echoes.size():
		if wears_echo(slot, item):
			return slot
	return -1


## Won fights still needed to learn the Echo of `item` (counting normal fights).
func fights_to_learn(item: GearData) -> int:
	var left := maxi(0, tuning.mastery_needed - mastery_of(item))
	return ceili(float(left) / float(maxi(1, tuning.mastery_fight)))


## Why hero `slot` cannot put on the Echo of `item` ("" if they can).
func echo_blocked_reason(slot: int, item: GearData) -> String:
	if item == null or slot < 0 or slot >= party_size():
		return "No such Echo."
	if not echo_learned(item):
		return "Wear the %s for %d more won fights to learn its Echo." % [item.display_name, fights_to_learn(item)]
	if wears_echo(slot, item):
		return ""
	if (gear[slot] as Array).has(item):
		return "%s already wears the %s itself." % [data.party[slot].display_name, item.display_name]
	# One hero per Echo (#280): it cannot sit on the whole party.
	var other := echo_wearer(item)
	if other >= 0 and other != slot:
		return "%s wears this Echo." % data.party[other].display_name
	if free_echo_points(slot) < item.echo_cost:
		return "Needs %d Echo points; %s has %d free." % [item.echo_cost, data.party[slot].display_name, free_echo_points(slot)]
	return ""


## Puts the Echo of `item` on hero `slot` (`on`) or takes it off. False (nothing changes) if it
## cannot be done. Taking an Echo off is always allowed; HP is cut to a lower max.
func set_echo(slot: int, item: GearData, on: bool) -> bool:
	if item == null or slot < 0 or slot >= party_size() or relic_by_id(item.id) != item:
		return false
	if not on:
		if not wears_echo(slot, item):
			return false
		(echoes[slot] as Array).erase(item.id)
		_clamp_hp()
		return true
	if wears_echo(slot, item) or not echo_blocked_reason(slot, item).is_empty():
		return false
	(echoes[slot] as Array).append(item.id)
	_clamp_hp()
	return true


## The bot (and tests): hero `slot` wears the learned Echoes it can, cheapest first, passing over
## the ones whose price GearBot refuses.
func auto_echoes(slot: int) -> void:
	var learned := learned_echoes()
	learned.sort_custom(func(a: GearData, b: GearData) -> bool: return a.echo_cost < b.echo_cost)
	for item: GearData in learned:
		if GearBot.score(item) >= 0 and not wears_echo(slot, item) and echo_blocked_reason(slot, item).is_empty():
			set_echo(slot, item, true)


# --- spoils, shops and chests -------------------------------------------------------------------

## How many Relics the spoils offer: tuning.run_loot_choices, fewer with the oaths (never fewer
## than one).
func loot_choice_count() -> int:
	return maxi(1, tuning.run_loot_choices + oath_total(&"loot_choices_add")) + (1 if flawless else 0)


## True if stop `stop_id` (the current one by default) is the act's crowned elite (card #286).
func is_crowned(stop_id: int = -2) -> bool:
	var s := map.stop(at if stop_id == -2 else stop_id)
	return int(s.get("type", -1)) == RunMap.StopType.ELITE and bool(s.get("crown", false))


## The Relics a stop's spoils offer: up to loot_choice_count() Relics the run lacks or can still
## level up (seeded). The crowned elite's spoils always hold a legendary one, listed first (card
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


## Up to `count` spoils picks, none of `skip` (see loot_choices).
func _loot_picks(salt: int, row: int, count: int, skip: Array[GearData] = []) -> Array[GearData]:
	# Rot-touched gear (DESIGN.md 8.16): spoils offer some among their choices (listed last), but
	# never as the only choice.
	var rot_count := mini(tuning.rot_gear_spoils_count, count - 1)
	var rot: Array[GearData] = []
	if rot_count > 0:
		rot = _pick_gear(salt + ROT_GEAR_SALT, rot_count, row, tuning.run_spoils_min_rarity, GearPool.ROT_TOUCHED, skip)
	var picked := _pick_gear(salt, count - rot.size(), row, tuning.run_spoils_min_rarity, GearPool.NORMAL, skip)
	picked.append_array(rot)
	if picked.size() < count:
		var taken := picked.duplicate()
		taken.append_array(skip)
		picked.append_array(_pick_gear(salt + 1, count - picked.size(), row, 0, GearPool.ANY, taken))
	return picked


## The Relics a shop stop sells: up to tuning.run_shop_gear (seeded).
func shop_gear(stop_id: int) -> Array[GearData]:
	return _pick_gear(stop_id * SHOP_SALT + restocks * RESTOCK_SALT + act * 47, tuning.run_shop_gear, _row_of(stop_id),
			0, GearPool.ANY, [], true)


## Up to `count` Relics a copy would still help (new, or below the top level), picked by weight at
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


## A Relic's weight in a pick: by rarity at row `row`; a copy weighs tuning.relic_copy_weight_percent
## of a new one; a rot-touched piece on the shelves (`rare_rot`) tuning.rot_gear_weight_percent.
func _relic_weight(item: GearData, row: int, rare_rot: bool = false) -> int:
	var weight := rarity_weight(GEAR_WEIGHT, item.rarity, row)
	if relic_level(item) > 0:
		weight = CombatMath.percent(weight, tuning.relic_copy_weight_percent)
	if rare_rot and item.rot_touched:
		weight = CombatMath.percent(weight, tuning.rot_gear_weight_percent)
	return weight


func can_buy_gear(item: GearData) -> bool:
	return item != null and can_gain(item) and gold >= gear_price(item)


## Pays for a shop Relic and adds it to the run (a copy raises its level). Returns the find
## (add_relic), or {} if it cannot be bought.
func buy_gear(item: GearData) -> Dictionary:
	if not can_buy_gear(item):
		return {}
	gold -= gear_price(item)
	return add_relic(item)


func _clamp_hp() -> void:
	for slot: int in hp.size():
		hp[slot] = clampi(hp[slot], 1, max_hp(slot))
