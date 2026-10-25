extends GutTest
## Phase 22 "Fewer words, more icons" (DESIGN.md 11): practice-only helpers stay out of the real
## game (cards #275, #276) and the strip leaves out what a mode lacks. (The zone's goal chips went
## with the zones in phase 26, DESIGN.md 8.22.)

const TUNING_PATH := "res://data/tuning/tuning.tres"
const VISUALS_PATH := "res://data/presentation/combat_visuals.tres"
const RUN_PATH := "res://data/runs/rotten_road.tres"


func _practice() -> CombatController:
	var fight := CombatController.new()
	fight.runner = TimedSequenceRunner.new()
	fight.skill_runner = SkillSequenceRunner.new()
	return fight


func _free(fight: CombatController) -> void:
	fight.runner.free()
	fight.skill_runner.free()
	fight.free()


# --- press and defence numbers only in practice (card #276) -------------------------------------

func test_only_a_local_fight_outside_a_run_and_the_tutorial_is_practice() -> void:
	var fight := CombatController.new()
	assert_true(fight.is_practice_fight(), "the Practice menu's fights and the dev switches")
	fight.set_tutorial(true)
	assert_false(fight.is_practice_fight(), "the tutorial is the real game")
	fight.free()
	fight = CombatController.new()
	fight.configure_run(RunState.new())
	assert_false(fight.is_practice_fight(), "a run fight")
	fight.free()
	fight = CombatController.new()
	fight.configure_online(CombatController.NetMode.CLIENT, 7)
	assert_false(fight.is_practice_fight(), "an online fight")
	fight.free()


func test_the_press_timing_numbers_show_only_in_practice() -> void:
	var fight := _practice()
	fight._allow_timing_numbers()
	assert_true(fight.runner.timing_numbers_allowed, "defence numbers in practice")
	assert_true(fight.skill_runner.timing_numbers_allowed, "skill press numbers in practice")
	fight.set_tutorial(true)
	assert_false(fight.runner.timing_numbers_allowed, "no defence numbers in the tutorial")
	assert_false(fight.skill_runner.timing_numbers_allowed, "no skill press numbers in the tutorial")
	_free(fight)
	fight = _practice()
	fight.configure_run(RunState.new())
	fight._allow_timing_numbers()
	assert_false(fight.runner.timing_numbers_allowed, "no defence numbers in a run")
	assert_false(fight.skill_runner.timing_numbers_allowed, "no skill press numbers in a run")
	_free(fight)


func test_a_runner_keeps_the_word_and_drops_the_number_outside_practice() -> void:
	for runner: Variant in [TimedSequenceRunner.new(), SkillSequenceRunner.new()]:
		runner._options = CombatOptions.new()
		assert_eq(runner.with_timing("PARRY", -34000), "PARRY -34", "practice: the word and the ms")
		assert_eq(runner.with_timing("LATE", 343000), "LATE +343")
		runner._options.timing_readout = false
		assert_eq(runner.with_timing("PARRY", -34000), "PARRY", "F1 > T off: the word alone")
		runner._options.timing_readout = true
		runner.timing_numbers_allowed = false
		assert_eq(runner.with_timing("PERFECT", -34000), "PERFECT", "real game: the word alone")
		assert_eq(runner.with_timing("LATE", 343000), "LATE")
		(runner as Node).free()


# --- no yellow practice text under the enemy panels (card #275), F1 only in practice ------------

func test_the_fight_screen_has_no_practice_text_under_the_enemy_panels() -> void:
	var hud := CombatHud.new()
	add_child_autofree(hud)
	hud.setup(null, load(VISUALS_PATH) as CombatVisuals, load(TUNING_PATH) as Tuning)
	assert_null(hud.find_child("PracticeStatus", true, false), "no practice status label")
	var column := hud.find_child("RightColumn", true, false) as Control
	assert_not_null(column)
	assert_eq(column.get_child_count(), 1, "only the enemy panels in the top right column")


func test_the_practice_keys_live_in_the_f1_panel() -> void:
	var overlay := DebugOverlay.new()
	add_child_autofree(overlay)
	overlay.visible = true
	overlay.practice_text = "PRACTICE   next attack: random"
	overlay.update_text(DefenseStats.new(), load(TUNING_PATH) as Tuning, CombatOptions.new(), 0.0)
	var body := overlay._body.text
	assert_string_contains(body, "PRACTICE   next attack: random")
	overlay.practice_text = ""
	overlay.update_text(DefenseStats.new(), load(TUNING_PATH) as Tuning, CombatOptions.new(), 0.0)
	assert_false(overlay._body.text.contains("PRACTICE"), "outside practice: none")


func test_f1_stats_shows_on_the_end_screen_only_in_practice() -> void:
	var fight := CombatController.new()
	assert_true(_has_stats(fight._end_hints()), "practice: F1 Stats")
	fight.set_tutorial(true)
	assert_false(_has_stats(fight._end_hints()), "tutorial: none")
	assert_eq(fight._end_hints().size(), 2, "the tutorial keeps Fight again and Choose a fight")
	fight.free()
	fight = CombatController.new()
	fight.configure_run(RunState.new())
	assert_false(_has_stats(fight._end_hints()), "run: none")
	fight.free()


func _has_stats(hints: Array) -> bool:
	for hint: Array in hints:
		if hint[0] == &"debug_overlay":
			return true
	return false


# --- the status strip ----------------------------------------------------------------------------

## The strip always opens with the run's gold, then the party's curses (only while there are any,
## card #332), then one panel per hero (the gold-less strip of the cut second mode is gone, card #331).
func test_the_strip_shows_the_gold_then_the_heroes() -> void:
	var run := RunState.begin(load(RUN_PATH) as RunData, load(TUNING_PATH) as Tuning, 42)
	var bar := RunPartyBar.new()
	add_child_autofree(bar)
	bar.setup(run)
	assert_eq(bar.get_child_count(), run.party_size() + 2, "the gold panel, the curses' panel and a panel per hero")
	var gold := bar.get_child(0).find_children("*", "Label", true, false)
	assert_eq((gold[0] as Label).text, RunPartyBar.GOLD_TEXT % run.gold, "the gold comes first")
	assert_false((bar.get_child(1) as Control).visible, "no curse: no curses' panel")


## Card #332: each curse on the party shows on the strip as its picture and name, in the rot green;
## more of the same curse share one chip ("x2"); a Cleanse takes the chip away.
func test_the_strip_shows_the_partys_curses() -> void:
	var run := RunState.begin(load(RUN_PATH) as RunData, load(TUNING_PATH) as Tuning, 42)
	var heart := run.items_by_id()["rotting_heart"] as ItemData
	var moss := run.items_by_id()["grave_moss"] as ItemData
	var bar := RunPartyBar.new()
	add_child_autofree(bar)
	bar.setup(run)
	run.add_curse(heart)
	run.add_curse(moss)
	run.add_curse(heart)
	assert_eq(RunPartyBar.curse_chips(run), [[heart.icon_path, "Rotting Heart x2", BackpackGrid.ROTTEN_COLOR],
			[moss.icon_path, "Grave Moss", BackpackGrid.ROTTEN_COLOR]])
	bar.refresh(run)
	var panel := bar.get_child(1) as Control
	assert_true(panel.visible, "the curses show")
	var words: Array[String] = []
	for label: Node in panel.find_children("*", "Label", true, false):
		words.append((label as Label).text)
	assert_eq(words, ["Rotting Heart x2", "Grave Moss"] as Array[String], "a few words each")
	assert_eq(panel.find_children("*", "TextureRect", true, false).size(), 2, "each with its picture")
	run.gold = run.cleanse_price() * 3
	while not run.curses.is_empty():
		run.cleanse(0)
	bar.refresh(run)
	assert_false(panel.visible, "all lifted: the panel goes")


# --- two or three choices side by side -----------------------------------------------------------

func _press(menu: ListMenu, action: StringName) -> StringName:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return menu.handle(event)


func test_a_horizontal_list_lays_its_cards_side_by_side_and_moves_with_left_and_right() -> void:
	var menu := ListMenu.new()
	add_child_autofree(menu)
	menu.horizontal = true
	var items: Array[Dictionary] = [{"text": "No"}, {"text": "Yes"}, {"text": "Maybe"}]
	menu.set_items(items)
	var strip: Node = null
	for child: Node in menu.get_children():
		if child is HBoxContainer:
			strip = child
	assert_not_null(strip, "the cards sit in one row")
	assert_eq(strip.get_child_count(), 3)
	assert_eq(menu.index, 0)
	assert_eq(_press(menu, &"menu_right"), &"", "right moves the cursor")
	assert_eq(menu.index, 1)
	_press(menu, &"menu_left")
	assert_eq(menu.index, 0)
	assert_eq(_press(menu, &"menu_confirm"), &"confirm")


func test_a_vertical_list_still_reports_left_and_right() -> void:
	var menu := ListMenu.new()
	add_child_autofree(menu)
	var items: Array[Dictionary] = [{"text": "Music"}, {"text": "Sound"}]
	menu.set_items(items)
	assert_eq(_press(menu, &"menu_right"), &"right", "settings use left and right to change a value")
	assert_eq(menu.index, 0)


func test_a_yes_no_question_shows_its_answers_side_by_side() -> void:
	var prompt := ConfirmPrompt.new()
	add_child_autofree(prompt)
	prompt.setup("Abandon this run?", "The run is lost.", "Abandon run", "Keep playing")
	assert_true(prompt._menu.horizontal)
	assert_eq(prompt._menu.index, 0, "No is chosen first")


# --- an enemy's HP bar never grows (card #279) ---------------------------------------------------

func test_long_words_many_hits_and_badges_never_widen_an_enemy_panel() -> void:
	var hud := CombatHud.new()
	add_child_autofree(hud)
	hud.setup(null, load(VISUALS_PATH) as CombatVisuals, load(TUNING_PATH) as Tuning)
	var plain: Dictionary = hud._make_enemy_panel(1, "Husk")
	var stuffed: Dictionary = hud._make_enemy_panel(2, "A Very Long Enemy Name Indeed")
	var sign: Dictionary = hud._intent_signs[2]
	(sign.panel as Control).visible = true
	(sign.label as Label).text = "Seven Sorrows Of The Rotten Road  >  WHOLE PARTY  [ROT/BLIGHT]"
	(sign.row as HitRowView).set_hits([0, 0, 0, 0, 0, 0, 0], [0, 500, 1000, 1500, 2000, 2500, 3000], hud._hit_icons)
	(sign.doom as Control).visible = true
	(sign.doom_label as Label).text = "DOOM IN 2    BREAK 1200 / 8400    AND SOME MORE WORDS"
	var statuses := {}
	for id: String in ["exposed", "guarded", "slowed", "bleeding", "marked", "empowered", "burning", "shocked"]:
		statuses[id] = {"turns": 3}
	hud._show_badges(stuffed, statuses, 1)
	var plain_width := (plain.panel as Control).get_combined_minimum_size().x
	var stuffed_width := (stuffed.panel as Control).get_combined_minimum_size().x
	assert_almost_eq(stuffed_width, plain_width, 0.5, "the stuffed panel is as wide as a plain one")
	assert_almost_eq((stuffed.bar as Control).get_combined_minimum_size().x, CombatHud.ENEMY_BAR_WIDTH, 0.5)


# --- the fight's end: icons, not lines (cards #273, #274) ---------------------------------------

func test_a_won_run_fight_ends_with_icon_rows_and_no_lines_of_text() -> void:
	var hud := CombatHud.new()
	add_child_autofree(hud)
	hud.setup(null, load(VISUALS_PATH) as CombatVisuals, load(TUNING_PATH) as Tuning)
	var rewards := {"chips": [{"icon": null, "text": "+25", "color": HudStyle.GOLD}],
			"heroes": [{"portrait": null, "text": "+30 XP", "level": 2, "down": false},
					{"portrait": null, "text": "+6 XP", "level": 0, "down": true}]}
	hud.show_end("victory", "", [], "", rewards)
	assert_eq(hud.end_reward_rows(), 2, "a row of rewards, a row of heroes")
	assert_false(hud._end_summary.visible, "no summary lines in the real game")
	hud.show_end("defeat", "", [], "")
	assert_eq(hud.end_reward_rows(), 0, "a defeat shows no rewards")
	hud.show_end("victory", "5 enemy hits   parried 3", [], "")
	assert_true(hud._end_summary.visible, "practice keeps its numbers")


func test_the_gold_icon_exists() -> void:
	var visuals := load(VISUALS_PATH) as CombatVisuals
	assert_true(ResourceLoader.exists(visuals.gold_icon_path), visuals.gold_icon_path)


func test_the_defend_buttons_stack_in_the_corner_clear_of_the_gauge() -> void:
	var hud := CombatHud.new()
	add_child_autofree(hud)
	hud.setup(null, load(VISUALS_PATH) as CombatVisuals, load(TUNING_PATH) as Tuning)
	var plates: Node = null
	for child: Node in hud._controls.get_children():
		if child is BoxContainer:
			plates = child
	assert_true(plates is VBoxContainer, "parry, dodge and jump one under the other")
	assert_eq(plates.get_child_count(), 3)
