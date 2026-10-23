extends GutTest
## Phase 22 "menus: clean and easy to move through" (DESIGN.md 7.5, 9.1, 9.2): a picture and a word
## where a sentence was. The pause menu's rows, the yes/no prompts and notices in Main, the Join
## screen's hint bar, the lost-pad card, the Controller notice skipped for a pad, the lag
## calibration without milliseconds, the settings' short lines and trimmed footers, the stats
## overlay out of the walking and menu clash groups, and the players screen's footer. Nothing here
## reads or writes the real user://settings.cfg.

const MAIN_PATH := "res://scenes/main.gd"
const BRANDING_PATH := "res://data/branding/branding.tres"
const TUNING_PATH := "res://data/tuning/tuning.tres"
const VISUALS_PATH := "res://data/presentation/combat_visuals.tres"
const RUN_PATH := "res://data/runs/rotten_road.tres"
const MAX_DETAIL_WORDS: int = 4

var _settings_before: ConfigFile
var _shared_before: ControlBindings
var _pad_before: bool
var _both_before: bool
var _project: ControlBindings


func before_each() -> void:
	_project = ControlBindings.from_input_map()
	_settings_before = PlayerSettings._config
	PlayerSettings._config = ConfigFile.new()
	PlayerSettings.set_persistence(false)
	_shared_before = ControlBindings.shared
	ControlBindings.shared = null
	_pad_before = ButtonPrompts._pad
	_both_before = ButtonPrompts._both
	ButtonPrompts._pad = false
	ButtonPrompts._both = false


func after_each() -> void:
	PlayerSettings._config = _settings_before
	PlayerSettings.set_persistence(true)
	ControlBindings.shared = _shared_before
	ButtonPrompts._pad = _pad_before
	ButtonPrompts._both = _both_before
	_project.apply_to_input_map(true)
	HudStyle.set_text_size_index(0)


static func _action(name: StringName) -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = name
	ev.pressed = true
	return ev


## A key press of `name` (the first key the Input Map gives it): a local screen tells devices apart.
static func _key(name: StringName) -> InputEventKey:
	for ev: InputEvent in InputMap.action_get_events(name):
		if ev is InputEventKey:
			var key := ev.duplicate() as InputEventKey
			key.pressed = true
			return key
	return null


## The texts of the Labels under `node` that are shown.
static func _shown_texts(node: Node) -> Array[String]:
	var out: Array[String] = []
	for label: Node in node.find_children("*", "Label", true, false):
		if (label as Label).is_visible_in_tree():
			out.append((label as Label).text)
	return out


static func _words(text: String) -> int:
	return text.strip_edges().split(" ", false).size()


## Every Label under `node` (its text), deep.
static func _texts(node: Node) -> Array[String]:
	var out: Array[String] = []
	for label: Node in node.find_children("*", "Label", true, false):
		out.append((label as Label).text)
	return out


# --- the pause menu -----------------------------------------------------------------------------

func test_pause_rows_have_a_picture_and_no_sentence() -> void:
	var pause := PauseMenu.new()
	add_child_autofree(pause)
	pause.setup("Abandon run", "The run and its save are lost. Back to the main menu.", "", "",
			"Save & Quit", "Keep the run and go to the main menu.")
	for text: String in _texts(pause):
		assert_false(text.contains("."), "no sentence on the pause menu: %s" % text)
	var kinds: Array[StringName] = []
	for i: int in 5:
		kinds.append(pause.glyph_kind(i))
	assert_eq(kinds, [&"play", &"gear", &"book", &"save", &"door"] as Array[StringName],
			"Continue, Settings, Glossary, Save & Quit, Abandon run")


func test_pause_glyph_of_the_chosen_row_is_gold() -> void:
	var pause := PauseMenu.new()
	add_child_autofree(pause)
	pause.setup("Leave")
	assert_eq(pause._glyphs[0].color, HudStyle.GOLD, "Continue is chosen first")
	pause._unhandled_input(_action(&"menu_down"))
	assert_eq(pause._glyphs[1].color, HudStyle.GOLD, "the picture follows the cursor")
	assert_eq(pause._glyphs[0].color, HudStyle.TEXT_DIM)
	for glyph: Node in pause._glyphs:
		assert_true(glyph.is_inside_tree(), "each picture sits in its row")


func test_tutorial_pause_has_a_skip_picture() -> void:
	var pause := PauseMenu.new()
	add_child_autofree(pause)
	pause.setup("Leave tutorial", "Back to the main menu.", "Skip this lesson", "Go on to the next one.")
	assert_eq(pause.glyph_kind(1), &"skip")
	assert_eq(pause.glyph_kind(4), &"door")


func test_pause_players_row_has_a_picture() -> void:
	var pause := PauseMenu.new()
	pause.players_row = true
	add_child_autofree(pause)
	pause.setup("Abandon run", "", "", "", "Save & Quit")
	var kinds: Array[StringName] = []
	for i: int in 6:
		kinds.append(pause.glyph_kind(i))
	assert_eq(kinds, [&"play", &"players", &"gear", &"book", &"save", &"door"] as Array[StringName],
			"Players comes second, after Continue (DESIGN.md 9.3)")
	assert_true(_shown_texts(pause).has("Players"))
	watch_signals(pause)
	pause._unhandled_input(_action(&"menu_down"))
	pause._unhandled_input(_action(&"menu_confirm"))
	assert_signal_emitted(pause, "players_requested")
	assert_signal_not_emitted(pause, "resumed")


func test_pause_note_is_one_gold_line() -> void:
	var plain := PauseMenu.new()
	add_child_autofree(plain)
	plain.setup("End the game")
	var line := LobbyScreen.address_line(["192.168.1.20"] as Array[String], 7777)
	assert_eq(line, "Address  192.168.1.20     Port  7777")
	assert_eq(LobbyScreen.address_line([] as Array[String], 7777), "Address  no network     Port  7777")
	var noted := PauseMenu.new()
	noted.note = line
	add_child_autofree(noted)
	noted.setup("End the game")
	assert_true(_shown_texts(noted).has(line), "the address is shown under PAUSED")
	assert_false(_shown_texts(plain).has(line))
	assert_eq(_texts(noted).size(), _texts(plain).size() + 1, "one extra line, nothing else")
	for label: Node in noted.find_children("*", "Label", true, false):
		if (label as Label).text == line:
			assert_eq((label as Label).label_settings.font_color, HudStyle.GOLD, "in gold")


# --- Main's prompts and notices --------------------------------------------------------------

func test_main_still_compiles() -> void:
	var script := load(MAIN_PATH) as GDScript
	assert_not_null(script)
	assert_true(script.can_instantiate(), "main.gd parses")


func test_mains_prompts_drop_their_long_sentences() -> void:
	var source := FileAccess.get_file_as_string(MAIN_PATH)
	for gone: String in ["Five short lessons", "Takes about 15 seconds", "Press Enter (A on a pad)",
			"so it cannot be continued here", "Everyone goes back to the main menu", "You go back to the main menu",
			"Is another game already hosting on this PC"]:
		assert_false(source.contains(gone), "gone from main.gd: %s" % gone)
	assert_true(source.contains("\"About %d seconds\" % _calibration_seconds()"), "the calibration's length comes from data")


func test_every_main_menu_notice_is_one_short_line() -> void:
	var source := FileAccess.get_file_as_string(MAIN_PATH)
	var notices := RegEx.create_from_string("_notice = (?:\"\" if \\w+ else )?\"([^\"]*)\"")
	var found := 0
	for hit: RegExMatch in notices.search_all(source):
		var text := hit.get_string(1)
		found += 1
		assert_lte(_words(text), 6, "short: %s" % text)
		assert_false(text.contains(". "), "one line, no second sentence: %s" % text)
	assert_gte(found, 4, "the saved-run, save, host and online notices")


func test_the_calibration_offer_counts_its_seconds_from_the_data() -> void:
	var visuals := load(VISUALS_PATH) as CombatVisuals
	var ms := visuals.calibration_lead_ms + visuals.calibration_beats * visuals.calibration_interval_ms
	assert_gt(ms, 0)
	assert_lt(ms, 60000, "well under a minute")


# --- the Join screen --------------------------------------------------------------------------

func test_join_footer_says_connect_or_rejoin_and_back() -> void:
	assert_eq(JoinScreen.footer_entries(false, false, true), [[&"menu_confirm", "Connect"], [&"pause", "Back"]],
			"keyboard: Escape (the Pause key) goes back, Backspace types")
	assert_eq(JoinScreen.footer_entries(false, true, false), [[&"menu_confirm", "Connect"], [&"menu_cancel", "Back"]],
			"a pad: its usual Back button")
	assert_eq(JoinScreen.footer_entries(true, true, true)[0], [&"menu_confirm", "Rejoin"], "after a lost connection")


func test_join_screen_has_no_key_names_or_networking_sentence() -> void:
	var join := JoinScreen.new()
	add_child_autofree(join)
	join.setup("192.168.1.20")
	for text: String in _texts(join):
		assert_false(text.contains("Tailscale"), text)
		assert_false(text.contains("Enter"), "keys are chips in the footer, not words: %s" % text)
		assert_false(text.contains("Esc"), text)
	assert_not_null(join._footer, "a hint bar along the bottom")
	var rejoin := JoinScreen.new()
	add_child_autofree(rejoin)
	rejoin.setup("192.168.1.20", true)
	assert_eq(String(rejoin._footer._entries[0][1]), "Rejoin")


func test_join_screen_back_from_escape_pause_and_the_pad() -> void:
	var join := JoinScreen.new()
	add_child_autofree(join)
	join.setup("")
	watch_signals(join)
	var pad_back := InputEventJoypadButton.new()
	pad_back.button_index = JOY_BUTTON_B
	pad_back.pressed = true
	join._input(pad_back)
	assert_signal_emit_count(join, "back", 1, "the pad's Back")
	var start := InputEventJoypadButton.new()
	start.button_index = JOY_BUTTON_START
	start.pressed = true
	join._input(start)
	assert_signal_emit_count(join, "back", 2, "the pad's Menu (Pause) too")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	join._input(escape)
	assert_signal_emit_count(join, "back", 3, "Escape")
	var backspace := InputEventKey.new()
	backspace.physical_keycode = KEY_BACKSPACE
	backspace.keycode = KEY_BACKSPACE
	backspace.pressed = true
	join._input(backspace)
	assert_signal_emit_count(join, "back", 3, "Backspace edits the address")


# --- the lost pad -----------------------------------------------------------------------------

func test_lost_pad_card_is_a_crossed_pad_a_tag_and_two_hints() -> void:
	var overlay := PadLostOverlay.new()
	var roster := PlayerRoster.solo(3, PlayerRoster.KEYBOARD)
	roster.join(0)
	overlay.setup(roster)
	add_child_autofree(overlay)
	overlay.show_player(1)
	assert_eq(overlay._tag.text, "P2")
	assert_eq(overlay._tag.label_settings.font_color, HudStyle.player_color(1))
	assert_not_null(overlay._pad, "the crossed-out pad")
	var texts := _texts(overlay)
	assert_true(texts.has("Take over"))
	assert_true(texts.has("Give heroes"))
	for text: String in texts:
		assert_lte(_words(text), 2, "words, not sentences: %s" % text)
	var bars := overlay.find_children("*", "HintBar", true, false)
	assert_eq(bars.size(), 1, "the Pause chip follows keys / pad")


func test_lost_pad_pause_gives_the_heroes_away() -> void:
	var overlay := PadLostOverlay.new()
	overlay.setup(PlayerRoster.solo(3, PlayerRoster.KEYBOARD))
	add_child_autofree(overlay)
	watch_signals(overlay)
	overlay._input(_action(&"pause"))
	assert_signal_emitted(overlay, "dropped")


# --- the Controller notice --------------------------------------------------------------------

func test_shipped_controller_notice_skips_a_player_with_a_pad() -> void:
	var branding := load(BRANDING_PATH) as BrandingData
	assert_true(branding.controller_skip_with_pad)
	assert_true(ControllerNotice.is_due(branding, false), "shown to a keyboard player")
	assert_false(ControllerNotice.is_due(branding, true), "not to one who has a pad plugged in")


# --- the lag calibration ----------------------------------------------------------------------

func test_meter_reaches_the_save_line_exactly_when_it_can_save() -> void:
	var line := CalibrationPanel.METER_SAVE_LINE
	assert_eq(CalibrationPanel.meter_percent(0, 4, 0, 60), 0, "empty before any press")
	assert_lt(CalibrationPanel.meter_percent(3, 4, 0, 60), line, "too few presses stay under the line")
	assert_gt(CalibrationPanel.meter_percent(2, 4, 0, 60), CalibrationPanel.meter_percent(1, 4, 0, 60), "fills a step a press")
	assert_eq(CalibrationPanel.meter_percent(4, 4, 0, 60), 100, "dead steady: full")
	assert_eq(CalibrationPanel.meter_percent(4, 4, 60, 60), line, "at the spread limit: on the line")
	assert_lt(CalibrationPanel.meter_percent(4, 4, 61, 60), line, "a millisecond over: under it")
	assert_eq(CalibrationPanel.meter_percent(8, 4, 500, 60), 0, "never below empty")
	assert_eq(CalibrationPanel.meter_percent(4, 4, -5, 60), 100, "never above full")


func _calibration() -> CalibrationPanel:
	var input := DefenseInput.new()
	add_child_autofree(input)
	var panel := CalibrationPanel.new()
	add_child_autofree(panel)
	panel.setup(load(VISUALS_PATH) as CombatVisuals, load(TUNING_PATH) as Tuning, input)
	panel.open()
	return panel


func _hint_texts(bar: HintBar) -> Array[String]:
	var out: Array[String] = []
	for entry: Array in bar._entries:
		out.append(String(entry[1]))
	return out


func test_calibration_shows_pips_device_and_meter_not_milliseconds() -> void:
	var panel := _calibration()
	var visuals := load(VISUALS_PATH) as CombatVisuals
	assert_eq(panel._pips.count, visuals.calibration_beats, "a pip for every beat")
	assert_eq(panel._pips.filled(), 0)
	assert_true((panel._devices[PlayerSettings.INPUT_KEYBOARD] as Control).visible, "both pictures before a press")
	assert_true((panel._devices[PlayerSettings.INPUT_PAD] as Control).visible)
	assert_false(panel._numbers.visible, "no milliseconds for players")
	for text: String in _texts(panel):
		assert_false(text.contains("ms"), "no milliseconds: %s" % text)
	assert_false(panel._uneven.visible)
	assert_eq(_hint_texts(panel._hints), ["Cancel"] as Array[String])
	panel._close()


func test_steady_presses_turn_the_meter_green_and_offer_save() -> void:
	var panel := _calibration()
	var visuals := load(VISUALS_PATH) as CombatVisuals
	panel._kind = PlayerSettings.INPUT_PAD
	panel._next_beat = visuals.calibration_min_presses
	for i: int in visuals.calibration_min_presses:
		panel._offsets_us.append(40000)
		panel._hit_beats[i] = true
	panel._update_text()
	assert_eq(panel._meter.color, CalibrationPanel.STEADY, "green: it can be saved")
	assert_eq(panel._meter.percent, 100)
	assert_false(panel._uneven.visible)
	assert_false((panel._devices[PlayerSettings.INPUT_KEYBOARD] as Control).visible, "only the pad is being measured")
	assert_true((panel._devices[PlayerSettings.INPUT_PAD] as Control).visible)
	assert_eq(_hint_texts(panel._hints), ["Save", "Cancel"] as Array[String])
	assert_eq(panel._pips.filled(), visuals.calibration_min_presses, "the pips of the beats gone by are filled")
	panel._close()


func test_uneven_presses_show_the_chip_and_cannot_save() -> void:
	var panel := _calibration()
	var visuals := load(VISUALS_PATH) as CombatVisuals
	panel._kind = PlayerSettings.INPUT_KEYBOARD
	var spread_us := visuals.calibration_max_spread_ms * 1000 * 3
	for i: int in visuals.calibration_min_presses:
		panel._offsets_us.append(-spread_us if i % 2 == 0 else spread_us)
	panel._update_text()
	assert_true(panel._uneven.visible, "the Too uneven chip")
	assert_eq(panel._meter.color, HudStyle.LATE)
	assert_lt(panel._meter.percent, CalibrationPanel.METER_SAVE_LINE)
	assert_eq(_hint_texts(panel._hints), ["Cancel"] as Array[String])
	panel._close()


func test_calibration_numbers_only_on_request() -> void:
	var panel := _calibration()
	panel.show_numbers = true
	panel._offsets_us.append(20000)
	panel._kind = PlayerSettings.INPUT_KEYBOARD
	panel._update_text()
	assert_true(panel._numbers.visible, "a practice look keeps the milliseconds")
	assert_true(panel._numbers.text.contains("ms"))
	panel._close()


# --- settings ---------------------------------------------------------------------------------

func _settings_screen(allow_reset: bool = false) -> SettingsScreen:
	var screen := SettingsScreen.new()
	add_child_autofree(screen)
	screen.setup(load(TUNING_PATH) as Tuning, load(VISUALS_PATH) as CombatVisuals, allow_reset)
	return screen


func test_every_settings_line_is_four_words_or_none() -> void:
	for allow: bool in [false, true]:
		var screen := _settings_screen(allow)
		for section: int in SettingsScreen.Section.size():
			if section == SettingsScreen.Section.CONTROLS:
				continue
			screen.open_section(section as SettingsScreen.Section)
			for item: Dictionary in screen._menu.items:
				var detail := String(item.get("detail", ""))
				assert_lte(_words(detail), SettingsScreen.DETAIL_MAX_WORDS, "%s: %s" % [item.get("text", ""), detail])
				assert_false(detail.contains(" ms"), "no milliseconds: %s" % detail)


func test_every_control_line_is_short_and_has_no_counter() -> void:
	for action: StringName in ControlBindings.ACTIONS:
		assert_lte(_words(String(ControlBindings.DETAILS[action])), MAX_DETAIL_WORDS, String(action))
	var screen := _settings_screen()
	screen.open_section(SettingsScreen.Section.CONTROLS)
	for item: Dictionary in screen._menu.items:
		assert_false(String(item.get("detail", "")).contains(" of "), "no (3 of 28) counter: %s" % item.get("detail", ""))


func test_controls_footer_keeps_only_the_essentials() -> void:
	assert_lte(SettingsScreen.CONTROLS_HINTS.size(), 4)
	var actions: Array[StringName] = []
	for hint: Array in SettingsScreen.CONTROLS_HINTS:
		actions.append(hint[0])
	assert_false(actions.has(&"party_attributes"), "LT sits by the page tabs already")
	assert_false(actions.has(&"party_skills"), "RT too")
	assert_true(actions.has(&"menu_confirm") and actions.has(&"menu_cancel"))
	assert_true(actions.has(&"item_turn_left") and actions.has(&"item_turn_right"), "LB / RB: Section")


func test_training_ring_row_only_in_a_debug_build() -> void:
	assert_false(SettingsScreen.section_rows(SettingsScreen.Section.GAME, false).has("timing_ring"),
			"Practice is hidden in a release build, so is its ring")
	assert_true(SettingsScreen.section_rows(SettingsScreen.Section.GAME, true).has("timing_ring"))
	assert_eq(SettingsScreen.section_rows(SettingsScreen.Section.GAME, false)[0], "text_size")
	var screen := _settings_screen()
	assert_eq(screen._rows_of(SettingsScreen.Section.GAME).has("timing_ring"), OS.is_debug_build())


func test_lag_row_says_which_inputs_are_measured() -> void:
	assert_eq(SettingsScreen.calibrated_text(false, false), "Default")
	assert_eq(SettingsScreen.calibrated_text(true, false), "Keys")
	assert_eq(SettingsScreen.calibrated_text(false, true), "Pad")
	assert_eq(SettingsScreen.calibrated_text(true, true), "Keys, Pad")


func test_controls_rows_show_each_binding_as_its_button_picture() -> void:
	var screen := _settings_screen()
	screen.open_page(SettingsScreen.ControlsPage.KEYBOARD)
	var rows := screen._rows_of(SettingsScreen.Section.CONTROLS)
	var model := ControlBindings.current()
	for i: int in rows.size():
		var row := String(rows[i])
		if not row.begins_with("ctl:"):
			assert_null(screen.binding_chip(i), "%s: no button picture" % row)
			continue
		var chip := screen.binding_chip(i)
		assert_not_null(chip, "%s: a key cap" % row)
		assert_eq(chip.shape, ButtonChip.Shape.KEY)
		assert_eq(String(chip.get_meta(&"button")), HudStyle.input_name(model.primary(StringName(row.substr(4)), ControlBindings.KEY)))
		assert_eq(String(screen._menu.items[i].get("value", "")), "", "%s: no text value beside it" % row)
	screen.open_page(SettingsScreen.ControlsPage.CONTROLLER)
	rows = screen._rows_of(SettingsScreen.Section.CONTROLS)
	var shapes := {}
	for i: int in rows.size():
		var chip := screen.binding_chip(i)
		if chip != null:
			shapes[String(rows[i])] = chip.shape
			assert_eq(chip._bg, ButtonChip.FILL, "the same dark fill as the key caps")
	assert_eq(shapes["ctl:defend_parry"], ButtonChip.Shape.PILL, "RB: a pill")
	assert_eq(shapes["ctl:fight_ultimate"], ButtonChip.Shape.PILL, "RT: a pill")
	assert_eq(shapes["ctl:menu_up"], ButtonChip.Shape.DPAD, "the D-pad cross")
	var faces := 0
	for row: String in shapes:
		if shapes[row] == ButtonChip.Shape.FACE:
			faces += 1
	assert_gt(faces, 0, "A / B / X / Y rings")


func test_the_chip_follows_a_rebinding_and_waiting_shows_words() -> void:
	var screen := _settings_screen()
	screen.open_section(SettingsScreen.Section.CONTROLS)
	var parry := screen._rows_of(SettingsScreen.Section.CONTROLS).find("ctl:defend_parry")
	screen._menu.index = parry
	screen._controls_answer(&"defend_parry", &"confirm")
	assert_null(screen.binding_chip(parry), "while waiting the row says what to press")
	assert_true(String(screen._menu.items[parry].get("value", "")).begins_with("press a key"))
	var key := InputEventKey.new()
	key.physical_keycode = KEY_K
	key.pressed = true
	screen._input(key)
	assert_eq(screen.shown_value(parry), "K", "the new key's cap")


func test_the_settings_title_and_section_names_stay_put() -> void:
	var screen := _settings_screen()
	var title := screen._page.get_child(0) as Control
	var tabs := screen._tabs[0].get_parent() as Control
	var tops: Array[Vector2] = []
	for section: int in SettingsScreen.Section.size():
		screen.open_section(section as SettingsScreen.Section)
		await get_tree().process_frame
		await get_tree().process_frame
		tops.append(Vector2(title.get_global_rect().position.y, tabs.get_global_rect().position.y))
	for i: int in range(1, tops.size()):
		assert_almost_eq(tops[i].x, tops[0].x, 0.5, "the title does not move on section %d" % i)
		assert_almost_eq(tops[i].y, tops[0].y, 0.5, "the section names do not move on section %d" % i)
	assert_lt(tops[0].x, 120.0, "pinned near the top")


func test_every_section_fits_under_the_pinned_title() -> void:
	for size: int in PlayerSettings.TEXT_SIZE_NAMES.size():
		HudStyle.set_text_size_index(size)
		var screen := _settings_screen()
		for section: int in SettingsScreen.Section.size():
			screen.open_section(section as SettingsScreen.Section)
			await get_tree().process_frame
			var height := screen._page.get_combined_minimum_size().y + SettingsScreen.HEADER_TOP_PX
			assert_lte(height, 1080.0 - ListMenu.FOOTER_STRIP_PX, "text %d, section %d fits (%d)" % [size, section, int(height)])
		screen.visible = false
	HudStyle.set_text_size_index(0)


# --- the stats overlay's clash groups ---------------------------------------------------------

func test_stats_overlay_is_only_in_the_fight_groups() -> void:
	for group: Array in ControlBindings.GROUPS:
		var walking := group.has(&"move_up")
		var menus := group.has(&"party_attributes")
		var fight := group.has(&"defend_parry") or group.has(&"skill_press") or group.has(&"fight_attack")
		if walking or menus:
			assert_false(group.has(&"debug_overlay"), "no stats overlay in the walking and menu groups")
		elif fight:
			assert_true(group.has(&"debug_overlay"), "still in the fight groups")


func test_a_walking_or_menu_button_may_take_the_stats_overlays_button() -> void:
	var model := ControlBindings.from_input_map()
	var f1 := model.primary(&"debug_overlay", ControlBindings.KEY)
	var view := model.primary(&"debug_overlay", ControlBindings.PAD)
	assert_false(model.conflicts(&"field_pickup", f1).has(&"debug_overlay"), "walking: no swap offered")
	assert_false(model.conflicts(&"item_move", view).has(&"debug_overlay"), "menus: no swap offered")
	assert_true(model.conflicts(&"defend_dodge", f1).has(&"debug_overlay"), "a fight still keeps them apart")
	assert_true(bool(model.assign(&"field_pickup", f1).ok))
	assert_eq(model.conflict_pairs(), [], "and nothing clashes after it")


func test_the_real_game_never_blocks_a_fight_button_with_the_hidden_stats_overlay() -> void:
	var model := ControlBindings.from_input_map()
	var f1 := model.primary(&"debug_overlay", ControlBindings.KEY)
	var view := model.primary(&"debug_overlay", ControlBindings.PAD)
	assert_true(model.list_debug, "a model starts strict (debug build, tests)")
	assert_true(model.conflicts(&"menu_confirm", f1).has(&"debug_overlay"), "debug: the action menu keeps them apart")
	model.list_debug = false
	assert_false(model.conflicts(&"menu_confirm", f1).has(&"debug_overlay"), "real game: Confirm may take F1")
	assert_false(model.conflicts(&"defend_parry", view).has(&"debug_overlay"), "real game: Parry may take View")
	assert_false(model.conflicts(&"skill_press", f1).has(&"debug_overlay"), "real game: Skill press may take F1")
	assert_eq(model.conflicts(&"debug_overlay", f1), [] as Array[StringName], "the hidden action clashes with nothing")
	assert_true(bool(model.assign(&"menu_confirm", f1).ok), "no swap with a hidden action")
	assert_true(bool(model.assign(&"defend_parry", view).ok))
	assert_eq(model.conflict_pairs(), [])
	assert_true(model.conflicts(&"menu_cancel", f1).has(&"menu_confirm"), "live actions still clash")


func test_a_saved_file_from_the_real_game_loads_in_a_debug_build() -> void:
	var real := ControlBindings.from_input_map()
	real.list_debug = false
	var f1 := real.primary(&"debug_overlay", ControlBindings.KEY)
	assert_true(bool(real.assign(&"menu_confirm", f1).ok))
	var saved := real.overrides()
	for strict: bool in [true, false]:
		var loaded := ControlBindings.from_input_map()
		loaded.list_debug = strict
		loaded.load_overrides(saved)
		assert_true(ControlBindings.same(loaded.primary(&"menu_confirm", ControlBindings.KEY), f1),
				"list_debug %s: the change is kept, not thrown away" % strict)
		assert_eq(loaded.list_debug, strict, "loading leaves the flag as it was")


func test_a_saved_clash_between_live_actions_is_still_dropped() -> void:
	var model := ControlBindings.from_input_map()
	var confirm := model.primary(&"menu_confirm", ControlBindings.KEY)
	var saved := {"menu_cancel": {"key": [confirm]}}
	model.list_debug = false
	model.load_overrides(saved)
	assert_true(model.is_action_default(&"menu_cancel"), "Back on Confirm's key is refused")


# --- the players screen -----------------------------------------------------------------------

func _names(data: RunData) -> Array[String]:
	var names: Array[String] = []
	for c: CharacterData in data.party:
		names.append(c.display_name)
	return names


func _portraits(data: RunData) -> Array[String]:
	var paths: Array[String] = []
	for c: CharacterData in data.party:
		paths.append(c.big_portrait_path)
	return paths


func _lobby(with_oaths: bool, unlocked: int = 3) -> LobbyScreen:
	var data := load(RUN_PATH) as RunData
	var lobby := LobbyScreen.new()
	lobby.hero_portraits = _portraits(data)
	if with_oaths:
		lobby.oaths = data.oaths
		lobby.oath_unlocked = unlocked
	lobby.setup(_names(data), null, PlayerRoster.KEYBOARD)
	add_child_autofree(lobby)
	return lobby


static func _click(at: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = at
	ev.pressed = true
	return ev


func test_players_footer_is_choose_change_start_back() -> void:
	var texts: Array[String] = []
	for hint: Array in LobbyScreen.hints(false, true):
		texts.append(String(hint[1]))
	assert_eq(texts, ["Choose", "Change", "Start", "Back"] as Array[String])
	assert_eq(LobbyScreen.hints(true, true).size(), 4, "the host the same")
	assert_eq(LobbyScreen.hints(true, false), [[&"menu_cancel", "Leave"]], "a waiting client only leaves")


func test_join_inputs_are_the_free_pads_and_the_free_keyboard() -> void:
	var solo_keys: Array[int] = [PlayerRoster.KEYBOARD]
	var solo_pad: Array[int] = [0]
	assert_eq(LobbyScreen.join_inputs(solo_keys, [] as Array[int]), {"pad": false, "keys": false}, "nothing else to join with")
	assert_eq(LobbyScreen.join_inputs(solo_keys, [0] as Array[int]), {"pad": true, "keys": false}, "a free pad")
	assert_eq(LobbyScreen.join_inputs(solo_pad, [0] as Array[int]), {"pad": false, "keys": true}, "the keyboard is free")
	assert_eq(LobbyScreen.join_inputs(solo_pad, [0, 1] as Array[int]), {"pad": true, "keys": true}, "both")


func test_the_open_seat_shows_the_join_buttons_not_words() -> void:
	var data := load(RUN_PATH) as RunData
	var lobby := LobbyScreen.new()
	lobby.hero_portraits = _portraits(data)
	lobby.setup(_names(data), null, 0)
	add_child_autofree(lobby)
	var seat := lobby._slots[1]
	var chips := seat.find_children("*", "ButtonChip", true, false)
	assert_eq(chips.size(), 1, "the keyboard is free: its Confirm key")
	assert_eq((chips[0] as ButtonChip).text, HudStyle.binding_parts(&"menu_confirm")[0], "read from the bindings")
	assert_true(_texts(seat).has("join"))
	assert_eq(lobby._slots[2].find_children("*", "ButtonChip", true, false).size(), 0, "only the first open seat")
	for text: String in _texts(lobby):
		assert_false(text.contains("press"), "no press-to-join words: %s" % text)


func test_one_oath_picker_with_effect_chips_and_no_rules_panel() -> void:
	var lobby := _lobby(true)
	assert_not_null(lobby._picker, "the Oath picker under the cards")
	assert_eq(lobby._picker_title.text, "No oath  >")
	assert_true(_texts(lobby._picker).has(LobbyScreen.NO_CHANGE))
	lobby._step_oath(1, false)
	lobby._step_oath(1, false)
	assert_eq(lobby._picker_title.text, "<  Oath 2  >")
	var data := load(RUN_PATH) as RunData
	var expected := LobbyScreen.oath_chips(data.oaths, 2)
	assert_false(expected.is_empty())
	for chip: Dictionary in expected:
		assert_true(_texts(lobby._picker).has(String(chip.text)), "chip %s" % chip.text)
	var oath_lines := 0
	for text: String in _shown_texts(lobby):
		assert_false(text.contains("The road as it is"), "no second oath panel: %s" % text)
		assert_false(text.contains("Win a run at this oath"), text)
		if text.contains("Oath 2"):
			oath_lines += 1
	assert_eq(oath_lines, 1, "the oath shows in one place only")


func test_oath_chips_are_short_and_add_up() -> void:
	var data := load(RUN_PATH) as RunData
	assert_eq(LobbyScreen.oath_chips(data.oaths, 0), [], "no oath: nothing changes")
	var all := LobbyScreen.oath_chips(data.oaths, data.oaths.size())
	assert_gte(all.size(), LobbyScreen.oath_chips(data.oaths, 1).size())
	for chip: Dictionary in all:
		assert_lte(_words(String(chip.text)), MAX_DETAIL_WORDS, String(chip.text))
		assert_true(UiGlyph.KINDS.has(chip.glyph), "a drawn picture: %s" % chip.glyph)
	var ladder: Array[OathData] = []
	var crowns := OathData.new()
	crowns.boss_hp_percent_add = 15
	crowns.boss_power_percent_add = 10
	var want := OathData.new()
	want.gold_percent_add = -25
	ladder.append(crowns)
	ladder.append(want)
	var texts: Array[String] = []
	for chip: Dictionary in LobbyScreen.oath_chips(ladder, 2):
		texts.append(String(chip.text))
	assert_eq(texts, ["Boss HP +15%", "Boss hit +10%", "Fight gold -25%"] as Array[String], "numbers from the data")


func test_cards_are_centred_and_nothing_floats_beside_them() -> void:
	var lobby := _lobby(true)
	await get_tree().process_frame
	await get_tree().process_frame
	var first := lobby._card_boxes[0].get_global_rect()
	var last := lobby._card_boxes[lobby._card_boxes.size() - 1].get_global_rect()
	var width := float(ProjectSettings.get_setting("display/window/size/viewport_width", 1920))
	assert_almost_eq((first.position.x + last.end.x) * 0.5, width * 0.5, 2.0, "the cards are one group in the middle")
	var row := lobby._card_boxes[0].get_parent() as Control
	assert_eq(row.get_child_count(), lobby._card_boxes.size(), "nothing else on the cards' line")
	var buttons := lobby._start_button.get_parent() as Control
	assert_gt(buttons.get_global_rect().position.y, first.end.y, "the picker and Start sit under the cards")
	var picker := lobby._picker.get_global_rect()
	var start := lobby._start_button.get_global_rect()
	assert_almost_eq(picker.get_center().y, start.get_center().y, 2.0, "side by side")
	assert_almost_eq((picker.position.x + start.end.x) * 0.5, width * 0.5, 2.0, "centred too")


func test_the_players_screen_fits_at_every_text_size() -> void:
	for size: int in PlayerSettings.TEXT_SIZE_NAMES.size():
		HudStyle.set_text_size_index(size)
		var lobby := _lobby(true, 12)
		lobby._oath = 12
		lobby._refresh()
		await get_tree().process_frame
		var column := lobby._start_button.get_parent().get_parent() as Control
		assert_lte(column.get_combined_minimum_size().y, 1080.0 - ListMenu.FOOTER_STRIP_PX,
				"text %d fits (it is %d tall)" % [size, int(column.get_combined_minimum_size().y)])
		lobby.visible = false
	HudStyle.set_text_size_index(0)


func test_start_is_lit_first_and_confirm_starts_from_any_row() -> void:
	var lobby := _lobby(true)
	assert_true(lobby.is_lit(lobby._start_row()), "the cursor starts on Start")
	assert_eq(lobby._menu.items.size(), lobby._start_row() + 1, "no Back row: Back is a footer button")
	watch_signals(lobby)
	lobby._unhandled_input(_key(&"menu_up"))
	assert_true(lobby.is_lit(lobby._oath_row()))
	lobby._unhandled_input(_key(&"menu_right"))
	assert_eq(lobby.oath(), 1, "right on the picker")
	lobby._unhandled_input(_key(&"menu_up"))
	assert_true(lobby.is_lit(lobby._hero_names.size() - 1), "up again: the last hero's card")
	lobby._unhandled_input(_key(&"menu_confirm"))
	assert_signal_emitted(lobby, "started", "Confirm on a card starts too")
	var params: Variant = get_signal_parameters(lobby, "started")
	assert_eq(int(params[1]) if params != null else -1, 1, "at the picked oath")
	lobby._unhandled_input(_key(&"menu_cancel"))
	assert_signal_emitted(lobby, "back", "Back from the footer button")


func test_the_mouse_points_and_clicks() -> void:
	var lobby := _lobby(true)
	await get_tree().process_frame
	await get_tree().process_frame
	var picker := lobby._picker.get_global_rect()
	var motion := InputEventMouseMotion.new()
	motion.position = picker.get_center()
	lobby._unhandled_input(motion)
	assert_eq(lobby._menu.index, lobby._oath_row(), "pointing at the picker chooses it")
	lobby._unhandled_input(_click(picker.position + Vector2(picker.size.x * 0.9, picker.size.y * 0.5)))
	assert_eq(lobby.oath(), 1, "a click on its right half steps up")
	lobby._unhandled_input(_click(picker.position + Vector2(picker.size.x * 0.1, picker.size.y * 0.5)))
	assert_eq(lobby.oath(), 0, "the left half steps down")
	watch_signals(lobby)
	lobby._unhandled_input(_click(lobby._start_button.get_global_rect().get_center()))
	assert_signal_emitted(lobby, "started", "a click on Start starts")


func test_players_screen_has_no_row_sentences() -> void:
	var lobby := _lobby(true, 2)
	lobby._step_oath(1, false)
	for item: Dictionary in lobby._menu.items:
		assert_eq(String(item.get("detail", "")), "", "no line under %s" % item.get("text", ""))
	for text: String in _texts(lobby):
		assert_false(text.contains("Join with a second pad"), text)
		assert_false(text.ends_with("."), "no sentences: %s" % text)


func test_a_waiting_client_sees_no_start_and_can_only_leave() -> void:
	var data := load(RUN_PATH) as RunData
	var lobby := LobbyScreen.new()
	lobby.hero_portraits = _portraits(data)
	lobby.oaths = data.oaths
	var roster := PlayerRoster.online(_names(data).size(), NetSession.HOST_PEER, 2)
	lobby.setup_online(_names(data), roster, false, [] as Array[String], 7777)
	add_child_autofree(lobby)
	lobby.set_oath(3)
	assert_false(lobby._start_button.visible, "no dead Start button")
	assert_eq(lobby._picker_title.text, "Oath 3", "the host's pick, no arrows")
	for row: int in lobby._start_row() + 1:
		assert_false(lobby.is_lit(row), "nothing lit: nothing to pick")
	watch_signals(lobby)
	lobby._unhandled_input(_action(&"menu_confirm"))
	assert_signal_not_emitted(lobby, "started")
	lobby._unhandled_input(_action(&"menu_right"))
	assert_eq(lobby.oath(), 3, "only the host picks")
	lobby._unhandled_input(_action(&"menu_cancel"))
	assert_signal_emitted(lobby, "back", "Back leaves")


func test_the_host_still_hands_out_and_starts() -> void:
	var data := load(RUN_PATH) as RunData
	var lobby := LobbyScreen.new()
	lobby.hero_portraits = _portraits(data)
	var roster := PlayerRoster.online(_names(data).size(), NetSession.HOST_PEER, NetSession.HOST_PEER)
	lobby.setup_online(_names(data), roster, true, ["10.0.0.5"] as Array[String], 7777)
	add_child_autofree(lobby)
	assert_true(lobby._start_button.visible)
	assert_true(lobby.is_lit(lobby._start_row()))
	watch_signals(lobby)
	assert_true(lobby.add_peer(5))
	lobby._unhandled_input(_action(&"menu_up"))
	lobby._unhandled_input(_action(&"menu_right"))
	assert_signal_emit_count(lobby, "roster_changed", 2, "joined, then a hero handed over")
	lobby._unhandled_input(_action(&"menu_confirm"))
	assert_signal_emitted(lobby, "started")
