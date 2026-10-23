extends SceneTree
## Writes the Fight Rush (DESIGN.md 8.21, card #305): data/rush/fight_rush.tres. Its four tiers come
## from the run's zones and acts (roamers, ambushes, elites), its boss cycle is the three guards, the
## Husk Lord and the Hollow King, and its item card offers the run's usable items. Rewrites the file
## (run it again after a zone's roamers, an act's elites or ambushes, or the run's items change).
## Saves nothing if the result does not pass RushData.validate().
## Run: Godot --headless --path . --import, then Godot --headless --path . -s tools/bootstrap_rush.gd

const RUN_PATH := "res://data/runs/rotten_road.tres"
const FIRST_ACT_PATH := "res://data/runs/acts/rotten_road.tres"
const SECOND_ACT_PATH := "res://data/runs/acts/ashen_deep.tres"
const ZONE_PATH := "res://data/zones/%s.tres"
const ENCOUNTER_PATH := "res://data/encounters/%s.tres"
const OUT_DIR := "res://data/rush"
const OUT_PATH := "res://data/rush/fight_rush.tres"


func _init() -> void:
	var run := load(RUN_PATH) as RunData
	var first := load(FIRST_ACT_PATH) as ActData
	var second := load(SECOND_ACT_PATH) as ActData
	var hollow := load(ZONE_PATH % "rotten_hollow") as ZoneData
	var bog := load(ZONE_PATH % "sunken_bog") as ZoneData
	var ruins := load(ZONE_PATH % "ashen_ruins") as ZoneData
	if run == null or first == null or second == null or hollow == null or bog == null or ruins == null:
		push_error("bootstrap_rush: could not load the run, its acts or its zones")
		quit(1)
		return
	var rush := RushData.new()
	rush.id = "fight_rush"
	rush.display_name = "Fight Rush"
	rush.run = run
	# Each tier teaches its own zone's monsters before the next; the last one mixes them all. Fights
	# 1 to 20 stay on the plain monsters, deep versions from the Ruins on.
	rush.tiers.assign([
		_tier(1, [hollow], [hollow.roamer_pool], [first.elites], false),
		_tier(11, [bog], [bog.roamer_pool, first.ambushes], [first.elites], false),
		_tier(21, [ruins], [ruins.roamer_pool, second.ambushes], [second.elites], true),
		_tier(31, [hollow, bog, ruins], [hollow.roamer_pool, bog.roamer_pool, first.ambushes,
				ruins.roamer_pool, second.ambushes], [first.elites, second.elites], true),
	])
	# Each tier ends on its zone's guard, then the two act bosses; the Hollow King closes the cycle.
	# home_depth is the map row a run meets each one at.
	rush.bosses.assign([
		_boss("guard_gorged_one", hollow, null, 1),
		_boss("guard_mire_mother", bog, null, 3),
		_boss("guard_ash_warden", ruins, null, 9),
		_boss("husk_lord_fight", hollow, first.final_look, 6),
		_boss("hollow_king", null, second.final_look, 13),
	])
	# No chests and no gold in a Rush: keys, treasure and curses never reach the item card.
	for list: Array[ItemData] in [run.shop_items, run.found_items]:
		for item: ItemData in list:
			if RushData.offerable(item) and not rush.items.has(item):
				rush.items.append(item)
	var problems := rush.validate()
	if not problems.is_empty():
		for problem: String in problems:
			push_error("bootstrap_rush: %s" % problem)
		push_error("bootstrap_rush: %s not written" % OUT_PATH)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var err := ResourceSaver.save(rush, OUT_PATH)
	if err != OK:
		push_error("bootstrap_rush: could not save %s (%d)" % [OUT_PATH, err])
		quit(1)
		return
	for i: int in rush.tiers.size():
		var tier := rush.tiers[i]
		print("bootstrap_rush: tier %d from fight %d: %d zones, %d fights, %d elites%s" % [i + 1,
				tier.from_fight, tier.zones.size(), tier.fights.size(), tier.elites.size(),
				", deep" if tier.deep else ""])
	print("bootstrap_rush: wrote %s (%d tiers, %d bosses, %d items)" % [OUT_PATH, rush.tiers.size(),
			rush.bosses.size(), rush.items.size()])
	quit()


## One tier: its zones, the fights of `pools` and the elites of `elite_pools`, each listed once
## (by resource), leaving out bosses, guards and empty fights.
func _tier(from_fight: int, zones: Array, pools: Array, elite_pools: Array, deep: bool) -> RushTier:
	var tier := RushTier.new()
	tier.from_fight = from_fight
	tier.zones.assign(zones)
	tier.fights.assign(_union(pools))
	tier.elites.assign(_union(elite_pools))
	tier.deep = deep
	return tier


## Every fight of `pools` once, in order, without bosses, guards or fights with no enemies.
func _union(pools: Array) -> Array[EncounterData]:
	var out: Array[EncounterData] = []
	var seen := {}
	for pool: Array in pools:
		for e: EncounterData in pool:
			if e == null or e.boss or e.mini_boss or e.enemies.is_empty():
				continue
			var key := e.resource_path if not e.resource_path.is_empty() else e.id
			if seen.has(key):
				continue
			seen[key] = true
			out.append(e)
	return out


## One boss of the cycle: the encounter `id`, where it is fought (`zone`, or `look` in its place) and
## the depth a run meets it at.
func _boss(id: String, zone: ZoneData, look: StageLook, home_depth: int) -> RushBoss:
	var boss := RushBoss.new()
	boss.encounter = load(ENCOUNTER_PATH % id) as EncounterData
	if boss.encounter == null:
		push_error("bootstrap_rush: no encounter %s" % id)
	boss.zone = zone
	boss.look = look
	boss.home_depth = home_depth
	return boss
