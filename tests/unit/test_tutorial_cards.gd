extends GutTest
## Card #293: every tutorial lesson card shows a picture beside one or two short lines with button
## chips (phase 22, DESIGN.md 7.13: never a wall of text). Only the words and pictures changed:
## the lessons, their goals and their staging are the same.

const TUTORIAL_PATH := "res://data/tutorial/tutorial.tres"
## The most words (button chips count as words) on a card's line, its tip, the reminder and the
## retry card.
const MAX_TEXT_WORDS: int = 12
const MAX_TIP_WORDS: int = 9
## A card's line is at most two rows and its tip one, even at the largest text size.
const MAX_ROWS: int = 2
const MAX_TIP_ROWS: int = 1

## What each step teaches and how it is staged, as before card #293: title, lesson, goal, hold,
## hero, ability, forced attack, tempo, full AP, fill gauge, mark hero, mark status.
const LESSONS: Array = [
	["Attack", 1, "good_press", "enemies", "brin", "brin_attack", "", 0, false, false, "", ""],
	["Skills", 2, "skill_used", "enemies", "alder", "taunt", "", 0, true, false, "", ""],
	["Follow-ups", 2, "skill_follow_up", "enemies", "alder", "shield_bash", "", 0, true, false, "", ""],
	["Parry", 3, "parry", "party", "", "", "husk_swipe", 170, false, false, "", ""],
	["Dodge", 3, "dodge", "party", "", "", "husk_swipe", 170, false, false, "", ""],
	["Jump", 3, "jump", "party", "", "", "husk_ground_slam", 170, false, false, "", ""],
	["Counter", 4, "counter", "party", "", "", "husk_flurry", 150, false, false, "", ""],
	["Team Ultimate", 5, "ultimate", "enemies", "alder", "team_ultimate", "", 0, false, true, "", ""],
	["Marks", 6, "mark_defended", "party", "", "", "husk_rot_combo", 170, false, false, "", ""],
	["Lift a mark", 6, "cleanse", "enemies", "cass", "mend", "", 0, true, false, "alder", "rotting"],
	["First Strike", 7, "read", "", "", "", "", 0, false, false, "", ""],
	["Relics", 8, "read", "", "", "", "", 0, false, false, "", ""],
	["Echoes", 8, "read", "", "", "", "", 0, false, false, "", ""],
]

var _size_index: int = 0


func before_each() -> void:
	_size_index = HudStyle.text_size_index()


func after_each() -> void:
	HudStyle.set_text_size_index(_size_index)


func _data() -> TutorialData:
	return load(TUTORIAL_PATH) as TutorialData


func _words(text: String) -> int:
	return text.split(" ", false).size()


## The action names of every {action} in `text`.
func _actions(text: String) -> Array[String]:
	var found: Array[String] = []
	var at := text.find("{")
	while at >= 0:
		var close := text.find("}", at)
		if close < 0:
			break
		found.append(text.substr(at + 1, close - at - 1))
		at = text.find("{", close)
	return found


func _chips(box: Node) -> int:
	var count := 0
	for row: Node in box.get_children():
		for piece: Node in row.get_children():
			if piece is HintBar:
				count += 1
	return count


func _overlay() -> TutorialOverlay:
	var overlay := TutorialOverlay.new()
	add_child_autofree(overlay)
	return overlay


func _show(overlay: TutorialOverlay, step: TutorialStepData) -> void:
	overlay.show_card("Lesson %d of 8" % step.lesson, step.title, step.text, step.tip, "Go", false, step.icon_path)


# --- the lessons are unchanged ---------------------------------------------------------------

func test_the_lessons_their_goals_and_staging_are_unchanged() -> void:
	var data := _data()
	assert_eq(data.steps.size(), LESSONS.size(), "the same steps")
	assert_eq(data.lesson_count(), 8)
	for i: int in mini(data.steps.size(), LESSONS.size()):
		var step: TutorialStepData = data.steps[i]
		var was: Array = LESSONS[i]
		var now: Array = [step.title, step.lesson, step.goal, step.hold, step.hero, step.ability,
				step.forced_attack, step.tempo_percent, step.full_ap, step.fill_gauge, step.mark_hero,
				step.mark_status]
		assert_eq(now, was, "step %d (%s) teaches and stages the same" % [i, step.title])


# --- every card has a picture -----------------------------------------------------------------

func test_every_step_has_a_picture_that_exists() -> void:
	var seen: Array[String] = []
	for step: TutorialStepData in _data().steps:
		assert_false(step.icon_path.is_empty(), "%s has a picture" % step.title)
		assert_true(step.icon_path.begins_with("res://assets/"), "%s: the picture is game art" % step.title)
		assert_true(AssetLoader.has_art(step.icon_path), "%s: %s exists" % [step.title, step.icon_path])
		var texture := AssetLoader.texture(step.icon_path)
		assert_ne(texture, AssetLoader.fallback_texture(Vector2i(32, 32)), "%s: the picture loads" % step.title)
		if texture != null:
			assert_eq(int(TutorialOverlay.PICTURE_PX) % texture.get_width(), 0,
					"%s: drawn at a whole multiple, so the pixels stay crisp" % step.title)
		assert_false(seen.has(step.icon_path), "%s: its own picture" % step.title)
		seen.append(step.icon_path)


func test_the_pictures_are_the_games_own_icons_where_they_fit() -> void:
	var by_title := {}
	for step: TutorialStepData in _data().steps:
		by_title[step.title] = step.icon_path
	# The defence lessons show the hit kinds' own icons, the marks lesson the Rot mark, First Strike
	# the foe skull: the same pictures the player meets in the fight and on the map.
	assert_eq(by_title.get("Parry"), "res://assets/sprites/ui/hit_normal.png")
	assert_eq(by_title.get("Jump"), "res://assets/sprites/ui/hit_ground.png")
	assert_eq(by_title.get("Skills"), "res://assets/sprites/ui/ap_pip.png")
	assert_eq(by_title.get("Marks"), HudStyle.MARK_ICON_PATH % "rotting")
	assert_eq(by_title.get("First Strike"), "res://assets/sprites/ui/goal_foe.png")


# --- the words are short ----------------------------------------------------------------------

func test_every_card_line_is_short() -> void:
	for step: TutorialStepData in _data().steps:
		assert_false(step.text.is_empty(), step.title)
		assert_lte(_words(step.text), MAX_TEXT_WORDS, "%s: a short line, not a wall of text" % step.title)
		assert_false(step.text.contains("\n"), "%s: no hand-made line breaks" % step.title)
		assert_lte(_words(step.tip), MAX_TIP_WORDS, "%s: the tip is one short line" % step.title)
		assert_lte(step.tip.split(".", false).size(), 1, "%s: the tip is one sentence" % step.title)
		if step.goal != TutorialGoals.READ:
			assert_lte(_words(step.reminder), MAX_TEXT_WORDS, "%s: a short reminder" % step.title)
			assert_lte(_words(step.retry), MAX_TEXT_WORDS, "%s: a short retry card" % step.title)
	assert_lte(_words(_data().done_text), MAX_TEXT_WORDS, "the end card is short too")


func test_every_button_chip_is_a_real_action() -> void:
	for step: TutorialStepData in _data().steps:
		for text: String in [step.text, step.tip, step.reminder, step.retry]:
			for action: String in _actions(text):
				assert_true(InputMap.has_action(StringName(action)), "%s: {%s} is a real action" % [step.title, action])


func test_fight_lessons_show_the_buttons_they_ask_for() -> void:
	for step: TutorialStepData in _data().steps:
		if step.goal == TutorialGoals.READ:
			continue
		assert_gt(_actions(step.text).size(), 0, "%s: the line shows its button" % step.title)


# --- the card on screen -----------------------------------------------------------------------

func test_a_card_shows_its_picture_beside_the_words() -> void:
	var overlay := _overlay()
	var step: TutorialStepData = _data().steps[0]
	_show(overlay, step)
	assert_true(overlay._plate.visible, "the picture plate shows")
	assert_not_null(overlay._picture.texture, "with the lesson's picture")
	assert_eq(overlay._picture.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "crisp pixel art")
	assert_eq(overlay._picture.custom_minimum_size, Vector2(TutorialOverlay.PICTURE_PX, TutorialOverlay.PICTURE_PX))
	assert_eq(_chips(overlay._lines), _actions(step.text).size(), "every {action} is a button chip")
	assert_true(overlay._tip.visible, "the tip under it")
	# A card without a picture (the end card) gives the words the whole card.
	overlay.show_card("", "Tutorial complete", _data().done_text, "", "Main menu", true)
	assert_false(overlay._plate.visible, "no plate without a picture")
	assert_null(overlay._picture.texture)
	assert_false(overlay._tip.visible, "no tip, no tip line")
	assert_gt(TutorialOverlay.text_width(false), TutorialOverlay.text_width(true), "the words get the plate's room")


func test_a_tip_can_show_a_button_chip() -> void:
	var overlay := _overlay()
	for step: TutorialStepData in _data().steps:
		if _actions(step.tip).is_empty():
			continue
		_show(overlay, step)
		assert_eq(_chips(overlay._tip), _actions(step.tip).size(), "%s: the tip draws its button" % step.title)
		for row: Node in overlay._tip.get_children():
			for piece: Node in row.get_children():
				if piece is Label:
					assert_eq((piece as Label).label_settings.font_color, HudStyle.TEXT_DIM, "the tip stays dim")


func test_every_card_fits_at_the_normal_and_the_largest_text_size() -> void:
	var overlay := _overlay()
	var largest := HudStyle.fonts().text_size_percents.size() - 1
	for index: int in [0, largest]:
		HudStyle.set_text_size_index(index)
		for step: TutorialStepData in _data().steps:
			_show(overlay, step)
			var label := "%s at text size %d" % [step.title, index]
			assert_lte(overlay._lines.get_child_count(), MAX_ROWS, "%s: one or two rows" % label)
			assert_lte(overlay._tip.get_child_count(), MAX_TIP_ROWS, "%s: a one-row tip" % label)
			for box: VBoxContainer in [overlay._lines, overlay._tip]:
				for row: Node in box.get_children():
					assert_lte((row as Control).get_combined_minimum_size().x, TutorialOverlay.text_width(true) + 1.0,
							"%s: every row fits beside the picture" % label)
			if overlay._lines.get_child_count() == 2:
				var a := (overlay._lines.get_child(0) as Control).get_combined_minimum_size().x
				var b := (overlay._lines.get_child(1) as Control).get_combined_minimum_size().x
				assert_gte(minf(a, b), maxf(a, b) * 0.5, "%s: two even rows, no lone word below" % label)
			var card := overlay._card.get_combined_minimum_size()
			assert_lte(card.x, TutorialOverlay.CARD_WIDTH + 1.0, "%s: the card keeps its width" % label)
			assert_lte(card.y, 640.0, "%s: the card fits the screen with room to spare" % label)
