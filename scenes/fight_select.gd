class_name FightSelect
extends CanvasLayer
## Phase 2 test menu: lists every encounter in data/encounters (DESIGN.md 2.11). Up/down picks,
## confirm starts it. Driven only by the menu_* input actions, like the action menu.

signal chosen(encounter: EncounterData)

const ENCOUNTER_DIR := "res://data/encounters"
const TITLE_SIZE: int = 64
const ITEM_SIZE: int = 40
const DETAIL_SIZE: int = 26
const HINT_SIZE: int = 24
const CURSOR := "> "
const BACKGROUND := Color(0.04, 0.04, 0.06)

var _encounters: Array[EncounterData] = []
var _labels: Array[Label] = []
var _detail: Label
var _index: int = 0
## Process frame of the last stick move (a held stick sends many motion events).
var _stick_frame: int = -1


## Every encounter in the data folder, sorted by file name.
static func load_encounters() -> Array[EncounterData]:
	var list: Array[EncounterData] = []
	var files := DirAccess.get_files_at(ENCOUNTER_DIR)
	files.sort()
	for file: String in files:
		var file_name := file.trim_suffix(".remap")
		if not file_name.ends_with(".tres"):
			continue
		var encounter := load(ENCOUNTER_DIR.path_join(file_name)) as EncounterData
		if encounter != null:
			list.append(encounter)
	return list


## Builds the menu with `start_index` selected.
func setup(encounters: Array[EncounterData], start_index: int) -> void:
	_encounters = encounters
	_index = clampi(start_index, 0, maxi(0, encounters.size() - 1))
	var bg := ColorRect.new()
	bg.color = BACKGROUND
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 14)
	add_child(column)
	var title := HudStyle.make_label("Choose a fight", TITLE_SIZE, HudStyle.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	for encounter: EncounterData in _encounters:
		var label := HudStyle.make_label("", ITEM_SIZE)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(label)
		_labels.append(label)
	_detail = HudStyle.make_label("", DETAIL_SIZE, HudStyle.TEXT_DIM)
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_detail)
	var hint := HudStyle.make_label("Up/Down choose   %s start" % HudStyle.binding_text(&"menu_confirm"), HINT_SIZE, HudStyle.TEXT_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)
	_redraw()


func selected_index() -> int:
	return _index


func _unhandled_input(event: InputEvent) -> void:
	if _encounters.is_empty():
		return
	if _pressed(event, &"menu_up"):
		_index = wrapi(_index - 1, 0, _encounters.size())
		Sfx.play("menu_move")
		_redraw()
	elif _pressed(event, &"menu_down"):
		_index = wrapi(_index + 1, 0, _encounters.size())
		Sfx.play("menu_move")
		_redraw()
	elif _pressed(event, &"menu_confirm"):
		Sfx.play("menu_confirm")
		get_viewport().set_input_as_handled()
		chosen.emit(_encounters[_index])
		return
	else:
		return
	get_viewport().set_input_as_handled()


func _pressed(event: InputEvent, action: StringName) -> bool:
	if not event.is_action_pressed(action, false, true):
		return false
	if event is InputEventJoypadMotion:
		var frame := Engine.get_process_frames()
		if not Input.is_action_just_pressed(action) or frame == _stick_frame:
			return false
		_stick_frame = frame
	return true


func _redraw() -> void:
	for i: int in _labels.size():
		var selected := i == _index
		_labels[i].text = (CURSOR if selected else "  ") + _encounters[i].display_name
		_labels[i].label_settings.font_color = HudStyle.GOLD if selected else HudStyle.TEXT
	var names := PackedStringArray()
	for enemy: EnemyData in _encounters[_index].enemies:
		if enemy != null:
			names.append(enemy.display_name)
	_detail.text = "Enemies: " + ", ".join(names)
