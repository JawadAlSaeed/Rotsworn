extends GutTest
## The party screen's Skills tab (SkillsTab, DESIGN.md 8.4 and 8.18): the old Skills page's rules
## (learning with skill points, bringing and leaving behind, heroes without a tree skipped) on the
## new tab.

const Fx := preload("res://tests/helpers/combat_fixtures.gd")
const RUN_PATH := "res://data/runs/rotten_road.tres"
const AP: int = 2


## The shipped run with the heroes in `tree_slots` given a small tree: two branches, [a, a2, a3]
## and [b, b2]; the others have none.
func _run(tree_slots: Array = [0], tuning: Tuning = null) -> RunState:
	var data := (load(RUN_PATH) as RunData).duplicate() as RunData
	var party: Array[CharacterData] = []
	party.assign(data.party)
	for slot: int in party.size():
		var hero := (party[slot] as CharacterData).duplicate() as CharacterData
		hero.skill_tree = _tree() if tree_slots.has(slot) else null
		if tree_slots.has(slot):
			hero.skills.clear()
		party[slot] = hero
	data.party = party
	return RunState.begin(data, tuning if tuning != null else Tuning.new(), 7)


## Confirm plays sounds through the Audio autoload: stop them, so none is still playing at exit.
func after_all() -> void:
	Sfx.stop_all()


func _tree() -> SkillTreeData:
	var tree := SkillTreeData.new()
	for names: Array in [["a", "a2", "a3"], ["b", "b2"]]:
		var branch := SkillBranchData.new()
		branch.display_name = String(names[0]).to_upper()
		for n: String in names:
			var skill := Fx.ability("tree_" + n, AP, 0, 100)
			skill.description = "What %s does." % n
			branch.skills.append(skill)
		tree.branches.append(branch)
	return tree


func _level_to(run: RunState, slot: int, level: int) -> void:
	while run.levels[slot] < level:
		run.add_xp(slot, run.xp_to_next(slot) - run.xps[slot])


func _tab(run: RunState, remote: bool = false) -> SkillsTab:
	var tab := SkillsTab.new()
	tab.setup(run, remote)
	add_child_autofree(tab)
	return tab


func _action(action: StringName) -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	return ev


func test_learning_spends_a_point_and_unlocks_the_skill() -> void:
	var run := _run()
	_level_to(run, 0, 2)
	var tab := _tab(run)
	watch_signals(tab)
	tab.move_cursor(Vector2i(0, 1))
	assert_eq(tab.selected().id, "tree_a2")
	var points := run.free_skill_points(0)
	assert_eq(tab.info().chips[1][1], "Learn: %d" % run.skill_cost(0, "tree_a2"))
	assert_true(tab.confirm())
	assert_true(run.unlocked[0].has("tree_a2"))
	assert_eq(run.free_skill_points(0), points - run.skill_cost(0, "tree_a2"))
	assert_true(run.loadout[0].has("tree_a2"), "brought at once while a socket is free")
	assert_signal_emitted(tab, "toast")


func test_bringing_and_leaving_behind_change_the_loadout() -> void:
	var run := _run()
	var tab := _tab(run)
	assert_eq(tab.selected().id, "tree_a")
	assert_eq(tab.hints()[1][1], "Leave")
	assert_true(tab.confirm(), "a brought skill is left behind")
	assert_eq(run.loadout[0], ["tree_b"])
	assert_eq(tab.hints()[1][1], "Bring")
	assert_true(tab.confirm(), "and brought again, at the end")
	assert_eq(run.loadout[0], ["tree_b", "tree_a"])


func test_a_full_loadout_refuses_on_the_info_line() -> void:
	var tuning := Tuning.new()
	tuning.skill_slots = 2
	var run := _run([0], tuning)
	_level_to(run, 0, 2)
	run.unlock(0, "tree_a2")
	assert_eq(run.loadout[0], ["tree_a", "tree_b"], "learned, but no socket free")
	var tab := _tab(run)
	tab.move_cursor(Vector2i.DOWN)
	assert_eq(tab.selected().id, "tree_a2")
	assert_false(tab.confirm())
	assert_eq(run.loadout[0], ["tree_a", "tree_b"])
	assert_string_contains(String(tab.info().line), "leave one behind")
	tab.move_cursor(Vector2i.UP)
	assert_eq(tab.info().line, "What a does.", "moving on shows the description again")


func test_a_locked_skill_says_why() -> void:
	var run := _run()
	_level_to(run, 0, 3)
	var tab := _tab(run)
	tab.move_cursor(Vector2i(0, 2))
	assert_eq(tab.selected().id, "tree_a3")
	assert_false(tab.confirm(), "a2 is not known yet")
	assert_false(run.unlocked[0].has("tree_a3"))
	assert_string_contains(String(tab.info().line), "tree_a2")
	assert_eq(tab.info().chips[1][1], "Locked")


func test_the_cursor_wraps_across_branches_and_stops_down_a_branch() -> void:
	var run := _run()
	var tab := _tab(run)
	tab.move_cursor(Vector2i.LEFT)
	assert_eq(tab.selected().id, "tree_b", "wraps to the last branch")
	tab.move_cursor(Vector2i(0, 5))
	assert_eq(tab.selected().id, "tree_b2", "stops at the bottom")
	tab.move_cursor(Vector2i.RIGHT)
	assert_eq(tab.selected().id, "tree_a2", "same depth in the next branch")


func test_heroes_without_a_tree_are_skipped() -> void:
	var run := _run([0, 2])
	var tab := _tab(run)
	tab.set_hero(1)
	assert_eq(tab.hero, 2, "to the next hero with a tree")
	assert_true(tab.handle_input(_action(&"party_skills")))
	assert_eq(tab.hero, 0, "RT wraps round, past hero 1")
	assert_true(tab.handle_input(_action(&"party_attributes")))
	assert_eq(tab.hero, 2, "LT goes back past hero 1")


func test_nobody_with_a_tree() -> void:
	var run := _run([])
	var tab := _tab(run)
	assert_null(tab.selected())
	assert_false(tab.confirm())
	assert_eq(tab.info().title, "No skill tree")
	assert_eq(tab.badge(), 0)


func test_badge_sums_free_points_of_heroes_with_a_tree() -> void:
	var run := _run([0, 2])
	_level_to(run, 0, 3)
	_level_to(run, 1, 3)
	_level_to(run, 2, 2)
	var tab := _tab(run)
	assert_eq(tab.badge(), run.free_skill_points(0) + run.free_skill_points(2))
	assert_gt(run.free_skill_points(0), 0)


func test_hints_never_more_than_four() -> void:
	for slots: Array in [[0], [0, 2]]:
		var run := _run(slots)
		_level_to(run, 0, 2)
		var tab := _tab(run)
		for b: int in 2:
			for t: int in 3:
				tab.move_cursor(Vector2i(0, -9))
				tab.move_cursor(Vector2i(0, t))
				assert_lte(tab.hints().size(), 4)
			tab.move_cursor(Vector2i.RIGHT)
		var actions: Array = []
		for entry: Array in tab.hints():
			actions.append(entry[0])
		assert_eq(actions.has(&"party_skills"), slots.size() > 1, "hero switch only with two trees")


func test_info_names_the_selected_skill() -> void:
	var run := _run()
	var tab := _tab(run)
	var shown := tab.info()
	assert_eq(shown.title, tab.selected().display_name)
	assert_eq(shown.chips[0][1], "%d AP" % AP)
	assert_eq(shown.chips[1][1], "Brought")
	assert_eq(shown.line, "What a does.")


func test_a_long_description_is_cut_to_one_line() -> void:
	var long := "word ".repeat(60) + "\nsecond line"
	var line := SkillsTab.one_line(long, 40)
	assert_lte(line.length(), 40)
	assert_false(line.contains("\n"))
	assert_eq(SkillsTab.one_line("short\nmore"), "short")


func test_online_client_asks_the_host_with_the_old_ops() -> void:
	var run := _run()
	_level_to(run, 0, 2)
	var tab := _tab(run, true)
	watch_signals(tab)
	assert_true(tab.confirm())
	assert_eq(get_signal_parameters(tab, "op_requested"), [{"op": "loadout", "slot": 0, "abilities": ["tree_b"]}])
	assert_eq(run.loadout[0], ["tree_a", "tree_b"], "nothing changes until the host answers")
	tab.move_cursor(Vector2i.DOWN)
	assert_true(tab.confirm())
	assert_eq(get_signal_parameters(tab, "op_requested"), [{"op": "unlock", "slot": 0, "ability": "tree_a2"}])
	assert_false(run.unlocked[0].has("tree_a2"))


func test_the_mouse_picks_a_tile_and_a_click_confirms() -> void:
	var run := _run()
	var tab := _tab(run)
	var tile := tab._cells[1][0] as Control
	var point := tile.get_global_transform_with_canvas() * (tile.size * 0.5)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	assert_true(tab.handle_input(motion))
	assert_eq(tab.selected().id, "tree_b")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = point
	assert_true(tab.handle_input(click))
	assert_eq(run.loadout[0], ["tree_a"], "the click left tree_b behind")
	var socket := tab._sockets[0] as Control
	motion.position = socket.get_global_transform_with_canvas() * (socket.size * 0.5)
	assert_true(tab.handle_input(motion))
	assert_eq(tab.selected().id, "tree_a", "pointing at a socket picks its skill")
