class_name SettingsScreen
extends CanvasLayer
## Settings (DESIGN.md 7.5, card #112) in four sections, changed with LB / RB (Z / C):
## Graphics (fullscreen, window size, vsync, frame limit, fog, bloom, shadows, soft shadows, depth
## of field), Sound (overall, music, effects, voices), Controls (the list of buttons) and Game
## (screen shake, the training ring, lag calibration). Everything is saved per machine at once
## (PlayerSettings, user://settings.cfg) and graphics changes show at once, even over a fight.
## Left/right change a value, confirm toggles or opens.

signal closed

const TITLE_SIZE: int = 56
const TAB_SIZE: int = 34
const TAB_GAP: int = 48
const CONTROLS_SIZE: int = 26
const DETAIL_SIZE: int = 26
const ROW_WIDTH: float = 760.0
## Smaller rows than other menus: the graphics section has ten.
const ITEM_SIZE: int = 32
const CONTROL_ROWS: Array[Array] = [
	["Attack", &"fight_attack"], ["Skills", &"fight_skills"], ["Items", &"fight_items"],
	["Ultimate", &"fight_ultimate"],
	["Parry", &"defend_parry"], ["Dodge", &"defend_dodge"], ["Jump", &"defend_jump"],
	["Skill press", &"skill_press"], ["Confirm", &"menu_confirm"], ["Back", &"menu_cancel"],
	["Strike (zone)", &"field_strike"], ["Pick up (zone)", &"field_pickup"], ["Move (zone)", &"@move"],
	["Party and backpack", &"party_menu"], ["Attributes", &"party_attributes"], ["Skills", &"party_skills"], ["Move item", &"item_move"],
	["Turn item", &"item_turn_right"], ["Pause", &"pause"], ["Stats overlay", &"debug_overlay"],
]
const CONTROLS_TITLE_SIZE: int = 24
const CONTROLS_GAP: int = 10

enum Section { GRAPHICS, SOUND, CONTROLS, GAME }
const SECTION_NAMES: Array[String] = ["Graphics", "Sound", "Controls", "Game"]

## The rows of each section, by id (Back closes the screen from any section).
const SECTION_ROWS := {
	Section.GRAPHICS: ["fullscreen", "window_size", "vsync", "fps_limit", "fog", "bloom", "shadows",
		"ambient_occlusion", "depth_of_field", "back"],
	Section.SOUND: ["master", "music", "effects", "voice", "back"],
	Section.CONTROLS: [],
	Section.GAME: ["screen_shake", "flashes", "timing_ring", "calibrate", "reset_lag", "back"],
}
const GRAPHICS_DETAIL := {
	"fog": "Mist over the zones and fights. Off is faster on slow PCs.",
	"bloom": "The soft glow around lights and bright things.",
	"shadows": "Shadows cast by the sun.",
	"ambient_occlusion": "Soft shading where things meet the ground.",
	"depth_of_field": "Blurs what is far from the action.",
}
const VOLUME_DETAIL := {
	"master": ["Volume", "Everything louder or quieter."],
	"music": ["Music", "The songs only."],
	"effects": ["Effects", "Hits, parries, steps and menu sounds."],
	"voice": ["Voices", "Heroes and enemies shouting and growling."],
}

var _tuning: Tuning
var _visuals: CombatVisuals
var _section: Section = Section.GRAPHICS
var _tabs: Array[Label] = []
var _menu: ListMenu
var _detail: Label
var _controls: Control
var _input: DefenseInput
var _calibration: CalibrationPanel
var _page: Control
var _footer: HintBar


func setup(tuning: Tuning, visuals: CombatVisuals) -> void:
	_tuning = tuning
	_visuals = visuals
	var column := ListMenu.screen_column(self, "Settings", TITLE_SIZE)
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
	_menu = ListMenu.new()
	_menu.centred = false
	_menu.row_width = ROW_WIDTH
	_menu.item_size = ITEM_SIZE
	_menu.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_menu)
	_controls = _controls_panel()
	_controls.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_controls)
	_detail = ListMenu.centred_label("", DETAIL_SIZE, HudStyle.TEXT_DIM)
	column.add_child(_detail)
	_footer = ListMenu.screen_footer(self, [[&"item_turn_left", "Section"], [&"item_turn_right", "Section"],
			[&"@updown", "Choose"], [&"@leftright", "Change"], [&"menu_confirm", "Select"], [&"menu_cancel", "Back"]])
	_show_section(Section.GRAPHICS)

	_input = DefenseInput.new()
	_input.name = "DefenseInput"
	add_child(_input)
	_calibration = CalibrationPanel.new()
	_calibration.name = "Calibration"
	add_child(_calibration)
	_calibration.setup(_visuals, _tuning, _input)
	_calibration.closed.connect(_on_calibration_closed)


func _unhandled_input(event: InputEvent) -> void:
	if _calibration.is_running():
		_calibration.handle_input(event)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"item_turn_left", false, true) or event.is_action_pressed(&"item_turn_right", false, true):
		get_viewport().set_input_as_handled()
		var step := -1 if event.is_action(&"item_turn_left") else 1
		_show_section(posmod(_section + step, Section.size()) as Section)
		Sfx.play("menu_move")
		return
	if _section == Section.CONTROLS:
		if event.is_action_pressed(&"menu_cancel", false, true):
			get_viewport().set_input_as_handled()
			Sfx.play("menu_cancel")
			closed.emit()
		return
	var answer := _menu.handle(event)
	if answer == &"":
		return
	if answer == &"cancel":
		Sfx.play("menu_cancel")
		closed.emit()
		return
	var step := -1 if answer == &"left" else 1
	var row := String(SECTION_ROWS[_section][_menu.index])
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
		"screen_shake":
			if answer == &"confirm":
				step = 1 if PlayerSettings.screen_shake_percent() < 100 else -4
			PlayerSettings.set_screen_shake_percent(PlayerSettings.screen_shake_percent() + step * PlayerSettings.SHAKE_STEP_PERCENT)
			Sfx.play("menu_move")
		"flashes":
			PlayerSettings.set_flash_mode(PlayerSettings.flash_mode() + (1 if answer == &"confirm" else step))
			Sfx.play("menu_move")
		"timing_ring":
			PlayerSettings.set_show_timing_ring(not PlayerSettings.show_timing_ring(_tuning))
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
	_refresh()


## Opens the lag calibration over this screen (also for --screen=calibration pictures).
func open_calibration() -> void:
	_page.visible = false
	_footer.visible = false
	_calibration.open()


func _show_section(section: Section) -> void:
	_section = section
	for i: int in _tabs.size():
		_tabs[i].label_settings.font_color = HudStyle.GOLD if i == section else HudStyle.TEXT_DIM
	var rows: Array = SECTION_ROWS[section]
	_menu.visible = not rows.is_empty()
	_controls.visible = rows.is_empty()
	var blank: Array[Dictionary] = []
	for i: int in rows.size():
		blank.append({})
	_menu.index = 0
	_menu.set_items(blank, _detail)
	_detail.text = "Changing keys comes later." if rows.is_empty() else ""
	_refresh()


func _on_calibration_closed() -> void:
	_page.visible = true
	_footer.visible = true
	_refresh()


func _refresh() -> void:
	var rows: Array = SECTION_ROWS[_section]
	for i: int in rows.size():
		var row := String(rows[i])
		match row:
			"master", "music", "effects", "voice":
				_menu.set_item(i, String(VOLUME_DETAIL[row][0]), true, String(VOLUME_DETAIL[row][1]), _percent(row))
			"fullscreen":
				_menu.set_item(i, "Fullscreen", true, "Fill the whole screen, or a window.",
						_on_off(PlayerSettings.fullscreen()))
			"window_size":
				_menu.set_item(i, "Window size", not PlayerSettings.fullscreen(),
						"The window's size when not fullscreen.", "<  %s  >" % _window_text())
			"vsync":
				_menu.set_item(i, "VSync", true, "Matches the screen's refresh: no tearing. Off can feel a little quicker.",
						_on_off(PlayerSettings.vsync()))
			"fps_limit":
				var limit := PlayerSettings.fps_limit()
				_menu.set_item(i, "Frame limit", true, "The most frames a second the game draws.",
						"<  %s  >" % ("No limit" if limit <= 0 else str(limit)))
			"fog", "bloom", "shadows", "ambient_occlusion", "depth_of_field":
				_menu.set_item(i, String(PlayerSettings.GRAPHICS[row]), true, String(GRAPHICS_DETAIL[row]),
						_on_off(PlayerSettings.graphics(row)))
			"screen_shake":
				_menu.set_item(i, "Screen shake", true, "How much the camera shakes on hits and parries.",
						"<  %d%%  >" % PlayerSettings.screen_shake_percent())
			"flashes":
				_menu.set_item(i, "Flashes", true,
						"How bright the screen and hit flashes are. Reduced or Off helps if flashing bothers you.",
						"<  %s  >" % String(PlayerSettings.FLASH_NAMES[PlayerSettings.flash_mode()]))
			"timing_ring":
				_menu.set_item(i, "Training ring", true,
						"A shrinking ring shows when each enemy hit lands. Practice fights only; off by default.",
						_on_off(PlayerSettings.show_timing_ring(_tuning)))
			"calibrate":
				_menu.set_item(i, "Lag calibration", true,
						"Press Parry with a beat to measure your screen and pad lag. Do this once per setup.",
						"%s ms%s" % [HudStyle.signed_ms(PlayerSettings.latency_compensation_ms(_tuning)),
						"" if PlayerSettings.is_calibrated() else " (default)"])
			"reset_lag":
				_menu.set_item(i, "Reset lag to default", PlayerSettings.is_calibrated(),
						"Forget the measured lag and use the default (%d ms) again." % _tuning.input_latency_compensation_ms)
			"back":
				_menu.set_item(i, "Back", true, "")


static func _window_text() -> String:
	var size := PlayerSettings.window_size()
	return "Maximised" if size == Vector2i.ZERO else "%d x %d" % [size.x, size.y]


static func _percent(channel: String) -> String:
	return "<  %d%%  >" % PlayerSettings.channel_percent(channel)


static func _on_off(value: bool) -> String:
	return "ON" if value else "OFF"


## The controls, one button chip per action (keyboard keys or pad buttons, see ButtonPrompts).
static func _controls_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", HudStyle.panel(HudStyle.PANEL_BG, HudStyle.PANEL_BORDER, 2, 22))
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", CONTROLS_GAP)
	panel.add_child(box)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", CONTROLS_GAP)
	box.add_child(grid)
	for pair: Array in CONTROL_ROWS:
		grid.add_child(HudStyle.make_label(String(pair[0]), CONTROLS_SIZE, HudStyle.TEXT))
		var chips := HintBar.new([[StringName(pair[1]), ""]], CONTROLS_SIZE)
		chips.alignment = BoxContainer.ALIGNMENT_BEGIN
		grid.add_child(chips)
	return panel
