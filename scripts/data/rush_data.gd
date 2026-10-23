class_name RushData
extends Resource
## The Fight Rush (DESIGN.md 8.21): fight after fight with a reward pick after each win, until the
## party falls. Its tiers say where the fights come from as the count climbs, its bosses come round
## every tuning rush_boss_every fights, and its items fill the item card. Written by
## tools/bootstrap_rush.gd.

@export var id: String = "fight_rush"
@export var display_name: String = "Fight Rush"
## The run whose party, team ultimate and Relics (gear) this Rush shares. Relic ids must match the
## collection, so this is the main run (rotten_road).
@export var run: RunData
## Ascending from_fight, the first from 1.
@export var tiers: Array[RushTier] = []
## The boss cycle, one per tuning rush_boss_every fights, then round again.
@export var bosses: Array[RushBoss] = []
## Items the item card can offer: CONSUMABLE or UPGRADE only, never rotten (no keys, treasure or
## curses: a Rush has no chests and no gold).
@export var items: Array[ItemData] = []


## What is wrong with this data, one line per problem (empty: fine).
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if run == null:
		problems.append("no run")
	if tiers.is_empty():
		problems.append("no tiers")
	var last_from := 0
	# Fights are looked up by id (RushState.encounter_id): an id must always be the same fight. Tiers
	# may share fights (the last tier is all of them).
	var ids := {}
	for i: int in tiers.size():
		var tier := tiers[i]
		if tier == null:
			problems.append("tier %d is empty" % i)
			continue
		if i == 0 and tier.from_fight != 1:
			problems.append("the first tier starts at fight %d, not 1" % tier.from_fight)
		if tier.from_fight <= last_from:
			problems.append("tier %d starts at fight %d, not after %d" % [i, tier.from_fight, last_from])
		last_from = tier.from_fight
		if tier.zones.is_empty() or tier.zones.has(null):
			problems.append("tier %d needs zones" % i)
		if tier.fights.size() < 2:
			problems.append("tier %d needs at least 2 fights" % i)
		if tier.elites.is_empty():
			problems.append("tier %d needs an elite" % i)
		var in_tier := {}
		for list: Array[EncounterData] in [tier.fights, tier.elites]:
			for e: EncounterData in list:
				if e == null or e.id.is_empty():
					problems.append("tier %d has an empty fight" % i)
				elif in_tier.has(e.id):
					problems.append("fight %s is listed twice in tier %d" % [e.id, i])
				elif ids.has(e.id) and ids[e.id] != e:
					problems.append("two fights share the id %s" % e.id)
				elif e.boss or e.mini_boss or e.enemies.is_empty():
					problems.append("fight %s in tier %d is a boss, a guard or empty" % [e.id, i])
				else:
					in_tier[e.id] = true
					ids[e.id] = e
	var tier_ids := ids.duplicate()
	if bosses.is_empty():
		problems.append("no bosses")
	for i: int in bosses.size():
		var boss := bosses[i]
		if boss == null or boss.encounter == null or boss.encounter.id.is_empty():
			problems.append("boss %d has no fight" % i)
			continue
		if boss.zone == null and boss.look == null:
			problems.append("boss %d has no zone or look" % i)
		if tier_ids.has(boss.encounter.id):
			problems.append("boss fight %s is also a tier fight" % boss.encounter.id)
		elif ids.has(boss.encounter.id) and ids[boss.encounter.id] != boss.encounter:
			problems.append("two fights share the id %s" % boss.encounter.id)
		ids[boss.encounter.id] = boss.encounter
	for item: ItemData in items:
		if item == null:
			problems.append("an empty item")
		elif not offerable(item):
			problems.append("item %s cannot be offered (only usable, unrotten items)" % item.id)
	return problems


## True if the item card may offer `item`: a consumable or an upgrade, not rotten.
static func offerable(item: ItemData) -> bool:
	return item != null and not item.rotten \
			and (item.kind == ItemData.Kind.CONSUMABLE or item.kind == ItemData.Kind.UPGRADE)
