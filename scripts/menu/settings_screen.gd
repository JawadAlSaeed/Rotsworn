class_name SettingsScreen
extends CanvasLayer
## Settings (DESIGN.md 7.5, card #112) in four sections, changed with LB / RB (Z / C), or by clicking
## the section's name:
## Graphics (fullscreen, window size, vsync, frame limit, fog, bloom, shadows, soft shadows, depth
## of field), Sound (overall, music, effects, voices), Controls (every key and button can be
## rebound, card #190) and Game (text size, screen shake, flashes, the training ring, lag calibration,
## Reset progress). Everything is saved per machine at once (PlayerSettings, user://settings.cfg)
## and graphics changes show at once, even over a fight. Left/right change a value, confirm toggles
## or opens. Reset progress (DESIGN.md 8.17) asks twice and then emits progress_reset for Main to
## wipe the Relics, the unlocked oaths, the Fight Rush records (8.21) and a saved run; it is only
## offered from the main menu, never in a run.
## The mouse (card #202): pointing at a row chooses it, a click confirms it (on a row with a value
## that Left / Right change, the left half of the row steps down and the right half up), a right
## click or the back button goes back.
##
## Controls (card #277) has two pages, side by side under the section names: Keyboard and
## Controller, each a picture and its word. A page lists only its own device's buttons, one row per
## action with the button drawn as its picture (ButtonChip: a key cap, a pad's A/B/X/Y ring, an LB or
## RT pill, the D-pad cross, all on the same dark fill), then its own options (the Controller page:
## Vibration, card #299) and its own "Reset to defaults" (asks twice; it puts back only that device's
## buttons). The section opens on the page of the device in the player's hands
## (ButtonPrompts.pad_in_use). LT / RT (T / K) open the Keyboard / Controller page from any row,
## Left / Right do it from a button's row, and a click on a page's name opens it. Confirm waits for
## the new key or button (Escape or the pad's Menu button cancels, and so does waiting too long). A
## button an action in the same group already has asks to swap them; ControlBindings holds the rules.
## A change applies to every pad: there are no per-pad bindings. The F1 stats overlay is a
## practice-fight tool and is only listed in a debug build (phase 22), and so is the Game section's
## Training ring (it only shows in practice fights, and Practice is a debug-build menu).
## Phase 22: the line under a row is four words at most (or none), and the footers keep only the
## buttons that matter (the page keys LT / RT sit beside the Controls page tabs). The title, its gold
## line and the section names are pinned at the top; only the list under them changes.

signal closed
## The player confirmed Reset progress twice (Main wipes the files).
signal progress_reset

const TITLE_SIZE: int = 56
const TAB_SIZE: int = 34
const TAB_GAP: int = 48
const CONTROLS_SIZE: int = 26
const DETAIL_SIZE: int = 26
const ROW_WIDTH: float = 760.0
## Smaller rows than other menus: the graphics section has ten.
const ITEM_SIZE: int = 32
## The Controls list is a little wider (a long action name and its button) and scrolls: this many
## rows show, less one for the page tabs above it.
const CONTROLS_ROW_WIDTH: float = 900.0
const CONTROLS_WINDOW: int = 10
## The page's top edge: the title sits this far down, the same on every section.
const HEADER_TOP_PX: float = 40.0
## The size of a Controls row's button picture (a hint's font size; ButtonChip scales from it).
const BINDING_CHIP_SIZE: int = 26
## Reset progress's question: what is wiped, then what stays, on two lines.
const RESET_DETAIL := "Relics and their levels, unlocked oaths, Rush records and a saved run are wiped.\n" \
		+ "Settings, controls and the Journal stay."

enum Section { GRAPHICS, SOUND, CONTROLS, GAME }
const SECTION_NAMES: Array[String] = ["Graphics", "Sound", "Controls", "Game"]

## The Controls section's two pages (card #277), left to right: their names, pictures (UiGlyph) and
## the kind of input each lists (ControlBindings.KEY / PAD).
enum ControlsPage { KEYBOARD, CONTROLLER }
const PAGE_NAMES: Array[String] = ["Keyboard", "Controller"]
const PAGE_GLYPHS: Array[StringName] = [&"keyboard", &"pad"]
const PAGE_KINDS: Array[String] = [ControlBindings.KEY, ControlBindings.PAD]
## A page's own options, listed under its buttons and above its reset (row ids handled like the other
## sections' rows). The Controller page has Vibration (card #299).
const PAGE_OPTION_ROWS := {
	ControlsPage.KEYBOARD: [],
	ControlsPage.CONTROLLER: ["vibration"],
}
## The page tabs: word size, picture size, gap between the tabs and their inside padding.
const PAGE_TAB_SIZE: int = 28
const PAGE_GLYPH_PX: int = 34
const PAGE_TAB_GAP: int = 22
const PAGE_TAB_PAD: int = 8
const PAGE_TAB_WIDTH: float = 250.0
const PAGE_TAB_ON_BG := Color(0.16, 0.12, 0.05, 0.92)

## The rows of each section, by id (Back closes the screen from any section).
const SECTION_ROWS := {
	Section.GRAPHICS: ["fullscreen", "window_size", "vsync", "fps_limit", "fog", "bloom", "shadows",
		"ambient_occlusion", "depth_of_field", "back"],
	Section.SOUND: ["master", "music", "effects", "voice", "back"],
	Section.CONTROLS: [],  # built by controls_rows: the page's actions, its options, reset and back
	Section.GAME: ["text_size", "screen_shake", "flashes", "timing_ring", "take_turns", "calibrate", "reset_lag",
		"reset_progress", "back"],
}
## Rows whose value Left / Right change: a mouse click steps it by the side of the row it lands on.
const SIDED_ROWS: Array[String] = ["master", "music", "effects", "voice", "window_size", "fps_limit",
		"screen_shake", "flashes", "text_size", "vibration"]
## How many rows of a list fit on screen at the normal text size; bigger text shows fewer (the list
## scrolls with the cursor).
const ROWS_AT_NORMAL_SIZE: int = 10
## LB and RB share one word ("[LB] [RB] Section").
const SECTION_HINTS: Array = [[&"item_turn_left", ""], [&"item_turn_right", "Section"],
		[&"@updown", "Choose"], [&"@leftright", "Change"], [&"menu_confirm", "Select"], [&"menu_cancel", "Back"]]
## The Controls pages: Section, Change, Back. LT / RT are drawn by the page tabs themselves.
const CONTROLS_HINTS: Array = [[&"item_turn_left", ""], [&"item_turn_right", "Section"],
		[&"menu_confirm", "Change"], [&"menu_cancel", "Back"]]
## Rows only a debug build shows (the Training ring works in practice fights only).
const DEBUG_ROWS: Array[String] = ["timing_ring"]
## The line under a row: four words at most (phase 22).
const DETAIL_MAX_WORDS: int = 4
const GRAPHICS_DETAIL := {
	"fog": "Off is faster",
	"bloom": "Glow around lights",
	"shadows": "Sun shadows",
	"ambient_occlusion": "Shade where things meet",
	"depth_of_field": "Blur far things",
}
const VOLUME_DETAIL := {
	"master": ["Volume", "Everything"],
	"music": ["Music", "Songs only"],
	"effects": ["Effects", "Hits, steps, menus"],
	"voice": ["Voices", "Shouts and growls"],
}

var _tuning: Tuning
var _visuals: CombatVisuals
var _section: Section = Section.GRAPHICS
var _tabs: Array[Label] = []
var _menu: ListMenu
var _detail: Label
var _defense_input: DefenseInput
var _calibration: CalibrationPanel
var _page: Control
var _footer: HintBar
## What _build_page added to this screen (freed and rebuilt when the text size changes).
var _built: Array[Node] = []
var _bindings: ControlBindings
## The Controls page shown (its kind of input is the one the rows show and rebind).
var _device_page: ControlsPage = ControlsPage.KEYBOARD
## The page tabs above the Controls list (shown only on that section), and their words and pictures.
var _device_strip: HBoxContainer
var _device_tabs: Array[PanelContainer] = []
var _device_words: Array[Label] = []
var _device_glyphs: Array[UiGlyph] = []
## Waiting for the new input of this action and kind ("" kind: not waiting).
var _capture_action: StringName = &""
var _capture_kind: String = ""
var _capture_until_ms: int = 0
## A swap waiting for Confirm: {action, input, other}; empty when none.
var _swap: Dictionary = {}
## The message under the list (a refusal, a question) until the cursor moves.
var _note: String = ""
var _note_is_problem: bool = false
## When a second Confirm on "Reset to defaults" still counts (Time.get_ticks_msec).
var _reset_until_ms: int = 0
## Reset progress can be picked (the main menu's settings; not the pause menu's, mid-run).
var _allow_reset: bool = false
var _prompt: ConfirmPrompt


func setup(tuning: Tuning, visuals: CombatVisuals, allow_reset: bool = false) -> void:
	_tuning = tuning
	_visuals = visuals
	_allow_reset = allow_reset
	_build_page()
	_defense_input = DefenseInput.new()
	_defense_input.name = "DefenseInput"
	add_child(_defense_input)
	_calibration = CalibrationPanel.new()
	_calibration.name = "Calibration"
	add_child(_calibration)
	_calibration.setup(_visuals, _tuning, _defense_input)
	_calibration.closed.connect(_on_calibration_closed)


## The backdrop, title, section names, list, detail line and hints.
func _build_page() -> void:
	var before := get_child_count()
	_tabs.clear()
	var column := ListMenu.screen_column(self, "Settings", TITLE_SIZE)
	# The title, its line and the section names stay put at the top: only the list under them
	# changes from section to section (a centred column made them jump).
	column.alignment = BoxContainer.ALIGNMENT_BEGIN
	column.offset_top = HEADER_TOP_PX
	_page = column
	var tabs := HBoxContainer.new()
	tabs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", TAB_GAP)
	column.add_child(tabs)
	for name: String in SECTION_NAMES:
		var tab := HudStyle.make_title(name, TAB_SIZE, HudStyle.TEXT_DIM)
		tabs.add_child(tab)
		_tabs.append(tab)
	_build_device_strip(column)
	_menu = ListMenu.new()
	_menu.centred = false
	_menu.row_width = ROW_WIDTH
	_menu.item_size = ITEM_SIZE
	_menu.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_menu)
	_bindings = ControlBindings.current()
	# The real game hides the stats overlay, so its button never blocks or swaps there.
	_bindings.list_debug = OS.is_debug_build()
	_detail =ListMenu.centred_label("", DETAIL_SIZE, HudStyle.TEXT_DIM)
	column.add_child(_detail)
	_footer = ListMenu.screen_footer(self, [])
	_built.clear()
	for i: int in range(before, get_child_count()):
		_built.append(get_child(i))
	_show_section(Section.GRAPHICS)


## Builds the page again, so every label has the new text size (card #203), and comes back to the
## same section and row.
func _rebuild_page() -> void:
	var section := _section
	var page := _device_page
	var row := _menu.index
	for node: Node in _built:
		remove_child(node)
		node.queue_free()
	_build_page()
	_section = section
	_device_page = page
	_fill_section()
	_menu.index = clampi(row, 0, maxi(0, _menu.items.size() - 1))
	_refresh()


func _process(_delta: float) -> void:
	if _capture_kind != "" and Time.get_ticks_msec() >= _capture_until_ms:
		_end_capture("Nothing pressed: the old button stays.", false)


## While the Controls list waits for a new key or button every key and pad press comes here first
## (so Escape and the Menu button can cancel, and Pause or Confirm cannot act meanwhile).
func _input(event: InputEvent) -> void:
	if _capture_kind == "" or _calibration.is_running():
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		get_viewport().set_input_as_handled()
		if ControlBindings.input_from_event(key).get("code", 0) == KEY_ESCAPE:
			_end_capture("Cancelled: the old button stays.", false)
		elif _capture_kind == ControlBindings.KEY:
			_try_assign(ControlBindings.input_from_event(key))
		else:
			_wrong_device_note()
	elif event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		if not button.pressed:
			return
		get_viewport().set_input_as_handled()
		if button.button_index == JOY_BUTTON_START:
			_end_capture("Cancelled: the old button stays.", false)
		elif _capture_kind == ControlBindings.PAD:
			_try_assign(ControlBindings.input_from_event(button))
		else:
			_wrong_device_note()
	elif event is InputEventJoypadMotion and _capture_kind == ControlBindings.PAD:
		var motion := event as InputEventJoypadMotion
		if ControlBindings.TRIGGER_AXES.has(motion.axis) and motion.axis_value >= ControlBindings.TRIGGER_CAPTURE_VALUE:
			get_viewport().set_input_as_handled()
			_try_assign({"k": "axis", "code": int(motion.axis), "dir": 1})


func _unhandled_input(event: InputEvent) -> void:
	if _prompt != null:
		return
	if _calibration.is_running():
		_calibration.handle_input(event)
		get_viewport().set_input_as_handled()
		return
	if _capture_kind != "":
		# Waiting for a new key: nothing else may act (a stick must not move the cursor). A right
		# click or the mouse's back button cancels, like Escape.
		get_viewport().set_input_as_handled()
		if MenuMouse.is_back(event):
			_end_capture("Cancelled: the old button stays.", false)
		return
	if not _swap.is_empty():
		if event.is_action_pressed(&"menu_confirm", false, true) or MenuMouse.is_click(event):
			get_viewport().set_input_as_handled()
			_do_swap()
		elif event.is_action_pressed(&"menu_cancel", false, true) or event.is_action_pressed(&"pause", false, true) \
				or MenuMouse.is_back(event):
			get_viewport().set_input_as_handled()
			_swap = {}
			_set_note("Not swapped: nothing changed.", false)
			_refresh()
		return
	if event.is_action_pressed(&"item_turn_left", false, true) or event.is_action_pressed(&"item_turn_right", false, true):
		get_viewport().set_input_as_handled()
		var step := -1 if event.is_action(&"item_turn_left") else 1
		_show_section(posmod(_section + step, Section.size()) as Section)
		Sfx.play("menu_move")
		return
	# Clicking a section's name opens it.
	if MenuMouse.is_click(event):
		var tab := MenuMouse.control_at(_tabs, (event as InputEventMouse).position)
		if tab >= 0:
			get_viewport().set_input_as_handled()
			if tab != _section:
				Sfx.play("menu_move")
				_show_section(tab as Section)
			return
	if _section == Section.CONTROLS and _device_page_input(event):
		get_viewport().set_input_as_handled()
		return
	var cursor_before := _menu.index
	var answer := _menu.handle(event)
	if answer == &"":
		if _section == Section.CONTROLS and (event.is_action_pressed(&"menu_up", false, true)
				or event.is_action_pressed(&"menu_down", false, true) or _menu.index != cursor_before):
			_note = ""
			_reset_until_ms = 0
			_refresh()
		return
	if answer == &"cancel":
		Sfx.play("menu_cancel")
		closed.emit()
		return
	var row := String(_rows_of(_section)[_menu.index])
	if answer == &"confirm" and _menu.clicked_share >= 0.0 and SIDED_ROWS.has(row):
		# A mouse click on a value that Left / Right change steps it by the side that was clicked (on
		# a button's row it waits for the new button, like Confirm).
		answer = &"left" if MenuMouse.side_of(_menu.clicked_share) < 0 else &"right"
	var step := -1 if answer == &"left" else 1
	if row.begins_with("ctl:"):
		_controls_answer(StringName(row.substr(4)), answer)
		return
	if _section == Section.CONTROLS and answer != &"confirm" and not (PAGE_OPTION_ROWS[_device_page] as Array).has(row):
		# Left / Right turn the page from the reset and Back rows too (a page's own options use them).
		_controls_answer(&"", answer)
		return
	match row:
		"master", "music", "effects", "voice":
			if answer != &"confirm":
				PlayerSettings.set_channel_percent(row, PlayerSettings.channel_percent(row) + step * PlayerSettings.VOLUME_STEP_PERCENT)
				Sfx.play("menu_move")
		"fullscreen":
			PlayerSettings.set_fullscreen(not PlayerSettings.fullscreen())
			Sfx.play("menu_confirm")
		"window_size":
			if PlayerSettings.fullscreen():
				Sfx.play("locked")
			else:
				PlayerSettings.set_window_size_index(PlayerSettings.window_size_index() + step)
				Sfx.play("menu_move")
		"vsync":
			PlayerSettings.set_vsync(not PlayerSettings.vsync())
			Sfx.play("menu_confirm")
		"fps_limit":
			PlayerSettings.set_fps_limit_index(PlayerSettings.fps_limit_index() + step)
			Sfx.play("menu_move")
		"fog", "bloom", "shadows", "ambient_occlusion", "depth_of_field":
			PlayerSettings.set_graphics(row, not PlayerSettings.graphics(row))
			StageBuilder.apply_settings(get_tree().root)
			Sfx.play("menu_confirm")
		"text_size":
			PlayerSettings.set_text_size_index(PlayerSettings.text_size_index() + (1 if answer == &"confirm" else step))
			Sfx.play("menu_move")
			# Every hint bar redraws at the new size; this page is built again.
			ButtonPrompts.refresh()
			_rebuild_page()
			return
		"screen_shake":
			if answer == &"confirm":
				step = 1 if PlayerSettings.screen_shake_percent() < 100 else -4
			PlayerSettings.set_screen_shake_percent(PlayerSettings.screen_shake_percent() + step * PlayerSettings.SHAKE_STEP_PERCENT)
			Sfx.play("menu_move")
		"flashes":
			PlayerSettings.set_flash_mode(PlayerSettings.flash_mode() + (1 if answer == &"confirm" else step))
			Sfx.play("menu_move")
		"vibration":
			if answer == &"confirm":
				step = 1 if PlayerSettings.rumble_percent() < 100 else -4
			PlayerSettings.set_rumble_percent(PlayerSettings.rumble_percent() + step * PlayerSettings.RUMBLE_STEP_PERCENT)
			Sfx.play("menu_move")
			PadRumble.test()
		"timing_ring":
			PlayerSettings.set_show_timing_ring(not PlayerSettings.show_timing_ring(_tuning))
			Sfx.play("menu_confirm")
		"take_turns":
			# Online, as host (card #314): from the next choice screen on.
			PlayerSettings.set_take_turns(not PlayerSettings.take_turns())
			Sfx.play("menu_confirm")
		"calibrate":
			if answer == &"confirm":
				Sfx.play("menu_confirm")
				open_calibration()
		"reset_lag":
			if answer == &"confirm":
				if PlayerSettings.is_calibrated():
					PlayerSettings.reset_latency_compensation()
					Sfx.play("menu_confirm")
				else:
					Sfx.play("locked")
		"back":
			if answer == &"confirm":
				Sfx.play("menu_cancel")
				closed.emit()
				return
		"reset":
			if answer == &"confirm":
				_reset_controls()
				return
		"reset_progress":
			if answer == &"confirm":
				_ask_reset_progress()
				return
	_refresh()


## Reset progress: asks, then asks again, then emits progress_reset.
func _ask_reset_progress() -> void:
	if not _allow_reset:
		Sfx.play("locked")
		_set_note("Progress can only be reset from the main menu, not during a run.", true)
		_refresh()
		return
	Sfx.play("menu_confirm")
	# Two lines: as one, the list ran off both sides of the screen at the largest text size.
	_confirm("Reset all progress?", RESET_DETAIL, "Reset", "Keep my progress", func() -> void:
				_confirm("Are you sure?", "This cannot be undone.", "Yes, wipe it", "No", func() -> void:
					progress_reset.emit()
					Sfx.play("menu_confirm")
					_set_note("Progress reset: a fresh start.", false)
					_refresh()))


func _confirm(question: String, detail: String, yes: String, no: String, on_yes: Callable) -> void:
	_prompt = ConfirmPrompt.new()
	add_child(_prompt)
	_prompt.setup(question, detail, yes, no)
	_prompt.answered.connect(func(answer: bool) -> void:
		get_viewport().set_input_as_handled()
		_prompt.queue_free()
		_prompt = null
		if answer:
			on_yes.call_deferred()
		else:
			Sfx.play("menu_cancel"))


## Opens the lag calibration over this screen (also for --screen=calibration pictures).
func open_calibration() -> void:
	_page.visible = false
	_footer.visible = false
	_calibration.open()


## Shows a section from its first row. Controls opens on the page of the device in use.
func _show_section(section: Section) -> void:
	if section == Section.CONTROLS:
		_device_page = page_for_device(ButtonPrompts.pad_in_use())
	_section = section
	_fill_section()


## Lays out the section (and, on Controls, the page) in _section from its first row.
func _fill_section() -> void:
	for i: int in _tabs.size():
		_tabs[i].label_settings.font_color = HudStyle.GOLD if i == _section else HudStyle.TEXT_DIM
	var rows := _rows_of(_section)
	var controls := _section == Section.CONTROLS
	_device_strip.visible = controls
	_redraw_device_strip()
	_menu.row_width = CONTROLS_ROW_WIDTH if controls else ROW_WIDTH
	# Bigger text shows fewer rows at once (the list scrolls with the cursor). On Controls the page
	# tabs take one row's room.
	var fit := fitting_rows(HudStyle.text_scale_percent())
	_menu.window_rows = mini(CONTROLS_WINDOW, fit) - 1 if controls else (fit if rows.size() > fit else 0)
	var blank: Array[Dictionary] = []
	for i: int in rows.size():
		blank.append({})
	_menu.index = 0
	_menu.set_items(blank, _detail)
	_note = ""
	_reset_until_ms = 0
	_footer.set_entries(CONTROLS_HINTS if controls else SECTION_HINTS)
	_refresh()


## How many list rows fit on the screen at a text size (percent): all ROWS_AT_NORMAL_SIZE at normal
## size, fewer when the text is bigger (never fewer than 4). Pure.
static func fitting_rows(percent: int) -> int:
	@warning_ignore("integer_division")
	return maxi(4, ROWS_AT_NORMAL_SIZE * 100 / maxi(100, percent))


func _on_calibration_closed() -> void:
	_page.visible = true
	_footer.visible = true
	_refresh()


func _refresh() -> void:
	var rows := _rows_of(_section)
	for i: int in rows.size():
		var row := String(rows[i])
		if row.begins_with("ctl:"):
			_refresh_control(i, StringName(row.substr(4)))
			continue
		match row:
			"master", "music", "effects", "voice":
				_menu.set_item(i, String(VOLUME_DETAIL[row][0]), true, String(VOLUME_DETAIL[row][1]), _percent(row))
			"fullscreen":
				_menu.set_item(i, "Fullscreen", true, "", _on_off(PlayerSettings.fullscreen()))
			"window_size":
				_menu.set_item(i, "Window size", not PlayerSettings.fullscreen(),
						"When not fullscreen", "<  %s  >" % _window_text())
			"vsync":
				_menu.set_item(i, "VSync", true, "No tearing", _on_off(PlayerSettings.vsync()))
			"fps_limit":
				var limit := PlayerSettings.fps_limit()
				_menu.set_item(i, "Frame limit", true, "Most frames a second",
						"<  %s  >" % ("No limit" if limit <= 0 else str(limit)))
			"fog", "bloom", "shadows", "ambient_occlusion", "depth_of_field":
				_menu.set_item(i, String(PlayerSettings.GRAPHICS[row]), true, String(GRAPHICS_DETAIL[row]),
						_on_off(PlayerSettings.graphics(row)))
			"text_size":
				_menu.set_item(i, "Text size", true, "HUD: from next fight",
						"<  %s  >" % String(PlayerSettings.TEXT_SIZE_NAMES[PlayerSettings.text_size_index()]))
			"screen_shake":
				_menu.set_item(i, "Screen shake", true, "On hits and parries",
						"<  %d%%  >" % PlayerSettings.screen_shake_percent())
			"flashes":
				_menu.set_item(i, "Flashes", true, "Lower if flashing bothers",
						"<  %s  >" % String(PlayerSettings.FLASH_NAMES[PlayerSettings.flash_mode()]))
			"vibration":
				var rumble := PlayerSettings.rumble_percent()
				_menu.set_item(i, "Vibration", true, "Pad buzz on hits",
						"<  %s  >" % ("OFF" if rumble <= 0 else "%d%%" % rumble))
			"timing_ring":
				_menu.set_item(i, "Training ring", true, "Practice fights only",
						_on_off(PlayerSettings.show_timing_ring(_tuning)))
			"take_turns":
				_menu.set_item(i, "Take turns", true, "Online: friends choose too", _on_off(PlayerSettings.take_turns()))
			"calibrate":
				# Which kinds of input are measured, never the milliseconds (phase 22).
				_menu.set_item(i, "Lag calibration", true, "Parry with the beat", calibrated_text(
						PlayerSettings.is_calibrated(PlayerSettings.INPUT_KEYBOARD),
						PlayerSettings.is_calibrated(PlayerSettings.INPUT_PAD)))
			"reset_lag":
				_menu.set_item(i, "Reset lag to default", PlayerSettings.is_calibrated(), "Forget the measured lag")
			"reset_progress":
				_menu.set_item(i, "Reset progress", _allow_reset, "Asks twice" if _allow_reset else "Main menu only")
			"reset":
				_menu.set_item(i, "Reset to defaults", true, "This page only",
						"" if _bindings.is_kind_default(_kind()) else "changed")
			"back":
				_menu.set_item(i, "Back", true, "")
	_show_note()


## The Lag calibration row's value: which kinds of input are measured ("Keys", "Pad", "Keys, Pad"),
## or "Default" for neither. Pure.
static func calibrated_text(keys: bool, pad: bool) -> String:
	var kinds := PackedStringArray()
	if keys:
		kinds.append("Keys")
	if pad:
		kinds.append("Pad")
	return ", ".join(kinds) if not kinds.is_empty() else "Default"


static func _window_text() -> String:
	var size := PlayerSettings.window_size()
	return "Maximised" if size == Vector2i.ZERO else "%d x %d" % [size.x, size.y]


static func _percent(channel: String) -> String:
	return "<  %d%%  >" % PlayerSettings.channel_percent(channel)


static func _on_off(value: bool) -> String:
	return "ON" if value else "OFF"


# --- controls (cards #190 and #277) ---------------------------------------------------------

## The rows of a section by id (Controls: see controls_rows, for the page shown).
func _rows_of(section: Section) -> Array:
	if section != Section.CONTROLS:
		return section_rows(section, OS.is_debug_build())
	return controls_rows(_device_page, _bindings, OS.is_debug_build())


## The rows of a section other than Controls by id; DEBUG_ROWS only when `debug`
## (OS.is_debug_build() in the game). Pure.
static func section_rows(section: Section, debug: bool) -> Array:
	var rows: Array = []
	for row: String in SECTION_ROWS[section]:
		if debug or not DEBUG_ROWS.has(row):
			rows.append(row)
	return rows


## The rows of a Controls page by id: "ctl:<action>" for each action the page lists (only the
## device's own buttons; the stats overlay only when `debug`), then the page's own options, then
## its reset and Back. Pure.
static func controls_rows(page: ControlsPage, bindings: ControlBindings, debug: bool) -> Array:
	var rows: Array = []
	for action: StringName in bindings.listed_actions(PAGE_KINDS[page], debug):
		rows.append("ctl:" + String(action))
	rows.append_array(PAGE_OPTION_ROWS[page])
	rows.append("reset")
	rows.append("back")
	return rows


## The page Settings > Controls opens on for the device in the player's hands. Pure.
static func page_for_device(pad_in_use: bool) -> ControlsPage:
	return ControlsPage.CONTROLLER if pad_in_use else ControlsPage.KEYBOARD


## Opens the screen on a section (for pictures and tests).
func open_section(section: Section) -> void:
	_show_section(section)


## Puts the cursor on row `row_id` of the section shown, scrolling to it (for pictures and tests).
## False if the section has no such row.
func select_row(row_id: String) -> bool:
	var at := _rows_of(_section).find(row_id)
	if at < 0:
		return false
	_menu.index = at
	_menu.redraw()
	_refresh()
	return true


## Shows a Controls page (for pictures and tests; the section opens too if it was not shown).
func open_page(page: ControlsPage) -> void:
	if _section != Section.CONTROLS:
		_section = Section.CONTROLS
		_device_page = page
		_fill_section()
		return
	_set_device_page(page)


## The kind of input the shown page lists and rebinds: ControlBindings.KEY or PAD.
func _kind() -> String:
	return PAGE_KINDS[_device_page]


## Turns to another Controls page, keeping the cursor on the same row (the same action) when the
## new page has it.
func _set_device_page(page: ControlsPage) -> void:
	if page == _device_page:
		return
	var rows := _rows_of(Section.CONTROLS)
	var row: String = String(rows[_menu.index]) if _menu.index < rows.size() else ""
	var index := _menu.index
	_device_page = page
	_fill_section()
	var fresh := _rows_of(Section.CONTROLS)
	var at := fresh.find(row)
	_menu.index = at if at >= 0 else clampi(index, 0, fresh.size() - 1)
	_refresh()


## The page keys and clicks on the Controls section: LT / RT (T / K) open the Keyboard /
## Controller page, so does a click on a page's tab. True when the event was used.
func _device_page_input(event: InputEvent) -> bool:
	var page := -1
	if _page_pressed(event, &"party_attributes"):
		page = ControlsPage.KEYBOARD
	elif _page_pressed(event, &"party_skills"):
		page = ControlsPage.CONTROLLER
	elif MenuMouse.is_click(event):
		page = MenuMouse.control_at(_device_tabs, (event as InputEventMouse).position)
	if page < 0:
		return false
	if page != _device_page:
		Sfx.play("menu_move")
		_set_device_page(page as ControlsPage)
	return true


## A page key going down. A trigger sends many motion events while held: only the first counts.
static func _page_pressed(event: InputEvent, action: StringName) -> bool:
	if not event.is_action_pressed(action, false, true):
		return false
	return not (event is InputEventJoypadMotion) or Input.is_action_just_pressed(action)


## The two page tabs, side by side: [LT] (keyboard picture) Keyboard  (pad picture) Controller [RT].
func _build_device_strip(column: VBoxContainer) -> void:
	_device_tabs.clear()
	_device_words.clear()
	_device_glyphs.clear()
	_device_strip = HBoxContainer.new()
	_device_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_device_strip.alignment = BoxContainer.ALIGNMENT_CENTER
	_device_strip.add_theme_constant_override("separation", PAGE_TAB_GAP)
	column.add_child(_device_strip)
	_device_strip.add_child(_page_key_hint(&"party_attributes"))
	for page: int in PAGE_NAMES.size():
		var tab := PanelContainer.new()
		tab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tab.custom_minimum_size.x = PAGE_TAB_WIDTH
		var line := HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.alignment = BoxContainer.ALIGNMENT_CENTER
		line.add_theme_constant_override("separation", PAGE_TAB_PAD + 4)
		tab.add_child(line)
		var glyph := UiGlyph.make(PAGE_GLYPHS[page], float(HudStyle.scaled(PAGE_GLYPH_PX)), HudStyle.TEXT_DIM)
		glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(glyph)
		var word := HudStyle.make_title(PAGE_NAMES[page], PAGE_TAB_SIZE, HudStyle.TEXT_DIM)
		word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(word)
		_device_strip.add_child(tab)
		_device_tabs.append(tab)
		_device_words.append(word)
		_device_glyphs.append(glyph)
	_device_strip.add_child(_page_key_hint(&"party_skills"))


## The chip of a page key next to the tabs; it follows the keyboard / pad hints (HintBar listens).
static func _page_key_hint(action: StringName) -> HintBar:
	var hint := HintBar.new([[action, ""]], PAGE_TAB_SIZE)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return hint


## Lights the shown page's tab in gold.
func _redraw_device_strip() -> void:
	for page: int in _device_tabs.size():
		var on := page == _device_page
		_device_tabs[page].add_theme_stylebox_override("panel", HudStyle.slant(PAGE_TAB_ON_BG if on else HudStyle.INK,
				HudStyle.GOLD if on else HudStyle.EDGE_DIM, 2, PAGE_TAB_PAD, float(HudStyle.scaled(PAGE_GLYPH_PX)), HudStyle.SLANT, false))
		_device_words[page].label_settings.font_color = HudStyle.GOLD if on else HudStyle.TEXT_DIM
		_device_glyphs[page].color = HudStyle.GOLD if on else HudStyle.TEXT_DIM
		_device_glyphs[page].queue_redraw()


func _refresh_control(i: int, action: StringName) -> void:
	var kind := _kind()
	var waiting := i == _menu.index and _capture_kind != "" and _capture_action == action
	# The binding is drawn as its button picture (a key cap, a pad's ring, pill or D-pad, like the
	# hints); only "press a key ..." while waiting is written out.
	var value := "press a %s ..." % ("key" if kind == ControlBindings.KEY else "button") if waiting else ""
	var also := _aliases(action)
	var detail := String(ControlBindings.DETAILS.get(action, ""))
	if not also.is_empty():
		detail += "   (also %s)" % also
	_menu.set_item(i, String(ControlBindings.LABELS.get(action, String(action))), true, detail, value)
	_set_binding_chip(i, "" if waiting else HudStyle.input_name(_bindings.primary(action, kind)),
			kind == ControlBindings.PAD)


## Puts the button picture `button` (a key on the Keyboard page, a pad button on the Controller
## page) at the end of row `i`, in place of the one there; "" takes it away.
func _set_binding_chip(i: int, button: String, pad: bool) -> void:
	var line := _menu.row_box(i)
	if line == null:
		return
	var old := binding_chip(i)
	if old != null and String(old.get_meta(&"button", "")) == button and bool(old.get_meta(&"pad", false)) == pad:
		return
	if old != null:
		line.remove_child(old)
		old.queue_free()
	if button.is_empty():
		return
	var chip := HudStyle.button_chip(button, pad, BINDING_CHIP_SIZE)
	chip.set_meta(&"button", button)
	chip.set_meta(&"pad", pad)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(chip)


## The button picture on row `i` of a Controls page (null for none: another section, or waiting).
func binding_chip(i: int) -> ButtonChip:
	var line := _menu.row_box(i)
	if line == null:
		return null
	for child: Node in line.get_children():
		if child is ButtonChip and not child.is_queued_for_deletion():
			return child as ButtonChip
	return null


## What row `i` shows on its right: the button's name under its picture, else the row's value text
## (for tests).
func shown_value(i: int) -> String:
	var chip := binding_chip(i)
	if chip != null:
		return String(chip.get_meta(&"button", ""))
	return String(_menu.items[i].get("value", "")) if i >= 0 and i < _menu.items.size() else ""


## The other keys or buttons of the shown page that still do the action's job ("E, Enter"; a stick
## is just "stick").
func _aliases(action: StringName) -> String:
	var names := PackedStringArray()
	var inputs := _bindings.inputs(action, _kind())
	for i: int in range(1, inputs.size()):
		var label := HudStyle.input_name(inputs[i])
		if inputs[i].get("k", "") == "axis" and not ControlBindings.TRIGGER_AXES.has(int(inputs[i].get("code", -1))):
			label = "stick"
		if not names.has(label):
			names.append(label)
	return ", ".join(names)


## Confirm on a button's row starts waiting for the page's new key or pad button; Left / Right open
## the Keyboard / Controller page (the cursor stays on the action).
func _controls_answer(action: StringName, answer: StringName) -> void:
	if answer == &"left" or answer == &"right":
		var page := ControlsPage.CONTROLLER if answer == &"right" else ControlsPage.KEYBOARD
		if page != _device_page:
			Sfx.play("menu_move")
			_set_device_page(page)
		return
	var keyboard := _kind() == ControlBindings.KEY
	_capture_action = action
	_capture_kind = _kind()
	_capture_until_ms = Time.get_ticks_msec() + _tuning.rebind_capture_ms
	_set_note("Press the new %s for %s.   %s: cancel." % ["key" if keyboard else "pad button",
			ControlBindings.LABELS.get(action, String(action)), "Escape" if keyboard else "The pad's Menu button"], false)
	Sfx.play("menu_confirm")
	_refresh()


## A pad button on the Keyboard page (or a key on the Controller page) while waiting: says which
## device this page takes and keeps waiting.
func _wrong_device_note() -> void:
	Sfx.play("locked")
	if _capture_kind == ControlBindings.KEY:
		_set_note("This is the Keyboard page: press a key (Escape: cancel).", true)
	else:
		_set_note("This is the Controller page: press a pad button (the pad's Menu button: cancel).", true)
	_refresh()


## A key or button arrived while waiting. Rebinds, or says why not and keeps waiting.
func _try_assign(input: Dictionary) -> void:
	var result := _bindings.assign(_capture_action, input)
	if bool(result.ok):
		_end_capture("%s is now %s." % [ControlBindings.LABELS.get(_capture_action, ""), HudStyle.input_name(input)], true)
		return
	_capture_until_ms = Time.get_ticks_msec() + _tuning.rebind_capture_ms
	Sfx.play("locked")
	match String(result.why):
		"reserved":
			_set_note("%s cannot be used (it cancels this step, or is the calibration key). Press another."
					% HudStyle.input_name(input), true)
		"conflict":
			var other: StringName = (result.with as Array)[0]
			var other_name := String(ControlBindings.LABELS.get(other, String(other)))
			if _bindings.can_swap(_capture_action, input):
				_swap = {"action": _capture_action, "input": input, "other": other}
				_capture_kind = ""
				_set_note("%s is already %s. Confirm: swap them.   Back: leave it." % [HudStyle.input_name(input), other_name], true)
			else:
				_set_note("%s is already %s, and they cannot trade places. Press another."
						% [HudStyle.input_name(input), other_name], true)
		_:
			_set_note("That cannot be used. Press another.", true)
	_refresh()


func _do_swap() -> void:
	var action: StringName = _swap.action
	var input: Dictionary = _swap.input
	_swap = {}
	var result := _bindings.assign(action, input, true)
	if bool(result.ok):
		_commit()
		Sfx.play("menu_confirm")
		_set_note("%s is now %s, and %s took the old button." % [ControlBindings.LABELS.get(action, ""),
				HudStyle.input_name(input), ControlBindings.LABELS.get(result.swapped, "")], false)
	else:
		Sfx.play("locked")
		_set_note("They cannot trade places.", true)
	_refresh()


func _end_capture(message: String, changed: bool) -> void:
	_capture_kind = ""
	_capture_action = &""
	if changed:
		_commit()
		Sfx.play("menu_confirm")
	else:
		Sfx.play("menu_cancel")
	_set_note(message, false)
	_refresh()


## Saves the bindings, puts them in the Input Map and redraws every button hint.
func _commit() -> void:
	PlayerSettings.set_control_overrides(_bindings.overrides())
	_bindings.apply_to_input_map(true)
	ButtonPrompts.refresh()


## The page's "Reset to defaults": the first Confirm asks, a second one soon after puts back only
## this page's keys or pad buttons (the other device keeps its changes).
func _reset_controls() -> void:
	var now := Time.get_ticks_msec()
	var kind := _kind()
	var what := "key" if kind == ControlBindings.KEY else "pad button"
	if _bindings.is_kind_default(kind):
		_set_note("Every %s is already as the game came." % what, false)
		Sfx.play("locked")
	elif now <= _reset_until_ms:
		_bindings.reset_kind(kind)
		_commit()
		_reset_until_ms = 0
		_set_note("Every %s is back to the default." % what, false)
		Sfx.play("menu_confirm")
	else:
		_reset_until_ms = now + _tuning.rebind_reset_confirm_ms
		_set_note("Press Confirm again to put every %s back to the default." % what, true)
		Sfx.play("menu_move")
	_refresh()


func _set_note(text: String, problem: bool) -> void:
	_note = text
	_note_is_problem = problem


func _show_note() -> void:
	if _note.is_empty():
		_detail.label_settings.font_color = HudStyle.TEXT_DIM
		return
	_detail.text = _note
	_detail.label_settings.font_color = HudStyle.LATE if _note_is_problem else HudStyle.GOLD
