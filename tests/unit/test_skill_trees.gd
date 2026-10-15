extends GutTest
## Skill trees (card #136, DESIGN.md 8.4): learning skills with points and choosing which to bring.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")
const RUN_PATH := "res://data/runs/rotten_road.tres"


## The shipped run with hero 0 given a small tree: two branches, [a, a2, a3] and [b, b2]; the
## others have none.
func _run() -> RunState:
	var data := (load(RUN_PATH) as RunData).duplicate() as RunData
	var hero := (data.party[0] as CharacterData).duplicate() as CharacterData
	var tree := SkillTreeData.new()
	for names: Array in [["a", "a2", "a3"], ["b", "b2"]]:
		var branch := SkillBranchData.new()
		branch.display_name = String(names[0]).to_upper()
		for n: String in names:
			branch.skills.append(Fx.ability("tree_" + n, 0, 0, 100))
		tree.branches.append(branch)
	hero.skill_tree = tree
	hero.skills.clear()
	var party: Array[CharacterData] = []
	party.assign(data.party)
	party[0] = hero
	# The others without a tree (the shipped heroes all have one).
	for slot: int in range(1, party.size()):
		var plain := party[slot].duplicate() as CharacterData
		plain.skill_tree = null
		party[slot] = plain
	data.party = party
	return RunState.begin(data, Tuning.new(), 7)


func _level_to(run: RunState, slot: int, level: int) -> void:
	while run.levels[slot] < level:
		run.add_xp(slot, run.xp_to_next(slot) - run.xps[slot])


func test_a_run_starts_with_the_top_of_each_branch() -> void:
	var run := _run()
	assert_true(run.has_tree(0))
	assert_false(run.has_tree(1), "the others have no tree")
	assert_eq(run.unlocked[0], ["tree_a", "tree_b"])
	assert_eq(run.loadout[0], ["tree_a", "tree_b"], "and brings them")
	assert_eq(run.free_skill_points(0), 0)


func test_learning_costs_points_and_needs_the_skill_above() -> void:
	var run := _run()
	var t := run.tuning
	assert_false(run.can_unlock(0, "tree_a2"), "no points at level 1")
	_level_to(run, 0, 2)
	assert_eq(run.free_skill_points(0), t.skill_points_per_level)
	assert_false(run.can_unlock(0, "tree_a3"), "needs a2 first")
	assert_true(run.unlock(0, "tree_a2"))
	assert_eq(run.free_skill_points(0), t.skill_points_per_level - t.skill_tier_costs[1])
	assert_true(run.loadout[0].has("tree_a2"), "brought at once while there is room")
	assert_false(run.unlock(0, "tree_a2"), "only once")
	assert_eq(run.skill_cost(0, "tree_a3"), t.skill_tier_costs[2])
	assert_eq(run.skill_cost(0, "nonsense"), -1)


func test_choosing_what_to_bring() -> void:
	var run := _run()
	assert_true(run.set_loadout(0, ["tree_b"]))
	assert_eq(run.loadout[0], ["tree_b"])
	assert_false(run.set_loadout(0, ["tree_a2"]), "not known yet")
	assert_false(run.set_loadout(0, ["tree_b", "tree_b"]), "each once")
	var too_many: Array = []
	for i: int in run.tuning.skill_slots + 1:
		too_many.append("tree_a")
	assert_false(run.set_loadout(0, too_many))
	assert_false(run.set_loadout(1, []), "a hero without a tree has nothing to choose")


func test_the_fight_gets_only_what_was_brought() -> void:
	var run := _run()
	run.set_loadout(0, ["tree_b"])
	var husk := load("res://data/encounters/husk_fight.tres") as EncounterData
	var setup := run.fight_setup(husk, 3, CombatSetup.Opening.NORMAL)
	var engine := CombatEngine.new(setup)
	engine.start()
	var hero := engine.get_combatant(engine.party_ids()[0])
	assert_true(hero.ability_ids.has("tree_b"))
	assert_false(hero.ability_ids.has("tree_a"), "left behind")
	assert_true(hero.ability_ids.has(run.data.party[0].basic_attack.id), "the basic attack always comes")
	var other := engine.get_combatant(engine.party_ids()[1])
	# No tree: every skill, as before.
	for ability: AbilityData in run.data.party[1].all_abilities():
		assert_true(other.ability_ids.has(ability.id))


func test_the_bot_learns_what_it_can() -> void:
	var run := _run()
	_level_to(run, 0, 6)
	run.auto_skills(0)
	assert_eq(run.unlocked[0].size(), 5, "5 points learn the whole small tree (1 + 2 + 1)")
	for skill: AbilityData in run.tree(0).all_skills():
		assert_false(run.can_unlock(0, skill.id), "nothing left to learn")


func test_skills_go_online_and_bad_ones_are_refused() -> void:
	var run := _run()
	_level_to(run, 0, 3)
	assert_true(run.apply_op({"op": "unlock", "slot": 0, "ability": "tree_b2"}))
	assert_true(run.apply_op({"op": "loadout", "slot": 0, "abilities": ["tree_b2"]}))
	assert_false(run.apply_op({"op": "unlock", "slot": 9, "ability": "tree_a2"}))
	assert_false(run.apply_op({"op": "loadout", "slot": 0, "abilities": "tree_b2"}))
	var copy := RunState.from_dict(run.data, run.tuning, run.to_dict())
	assert_not_null(copy)
	assert_eq(copy.unlocked[0], run.unlocked[0])
	assert_eq(copy.loadout[0], ["tree_b2"])
	var bad := run.to_dict()
	bad.unlocked = [["tree_zzz"], [], []]
	assert_null(RunState.from_dict(run.data, run.tuning, bad), "unknown skills are refused")
