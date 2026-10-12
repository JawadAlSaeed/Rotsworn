class_name FightSelect
extends CanvasLayer
## Practice list (from the main menu): the zones to explore (data/zones, DESIGN.md 7.4) first,
## then every test fight in data/encounters (DESIGN.md 2.11). Up/down picks, confirm starts it,
## cancel goes back to the main menu. Driven only by the menu_* input actions, like the action menu.

signal chosen(encounter: EncounterData)
signal zone_chosen(zone: ZoneData)
signal back

const ENCOUNTER_DIR := "res://data/encounters"
const ZONE_DIR := "res://data/zones"
const TITLE_SIZE: int = 64
const ITEM_SIZE: int = 40
const DETAIL_SIZE: int = 26
const HINT_SIZE: int = 24
const CURSOR := "> "
const BACKGROUND := Color(0.04, 0.04, 0.06)

var _encounters: Array[EncounterData] = []
var _zones: Array[ZoneData] = []
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


## Every zone in the data folder, sorted by file name.
static func load_zones() -> Array[ZoneData]:
	var list: Array[ZoneData] = []
	var files := DirAccess.get_files_at(ZONE_DIR)
	files.sort()
	for file: String in files:
		var file_name := file.trim_suffix(".remap")
		if not file_name.ends_with(".tres"):
			continue
		var zone := load(ZONE_DIR.path_join(file_name)) as ZoneData
		if zone != null:
			list.append(zone)
	return list


## Builds the menu with `start_index` selected (zones come first, then encounters).
func setup(zones: Array[ZoneData], encounters: Array[EncounterData], start_index: int) -> void:
	_zones = zones
	_encounters = encounters
	_index = clampi(start_index, 0, maxi(0, _count() - 1))
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
	var title := HudStyle.make_label("Practice", TITLE_SIZE, HudStyle.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	for i: int in _count():
		var label := HudStyle.make_label("", ITEM_SIZE)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(label)
		_labels.append(label)
	_detail = HudStyle.make_label("", DETAIL_SIZE, HudStyle.TEXT_DIM)
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_detail)
	var hint := HudStyle.make_label("Up/Down choose   %s start   %s main menu" % [HudStyle.binding_text(&"menu_confirm"),
			HudStyle.binding_text(&"menu_cancel")], HINT_SIZE, HudStyle.TEXT_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)
	_redraw()


func selected_index() -> int:
	return _index


func _unhandled_input(event: InputEvent) -> void:
	if _count() == 0:
		return
	if _pressed(event, &"menu_up"):
		_index = wrapi(_index - 1, 0, _count())
		Sfx.play("menu_move")
		_redraw()
	elif _pressed(event, &"menu_down"):
		_index = wrapi(_index + 1, 0, _count())
		Sfx.play("menu_move")
		_redraw()
	elif _pressed(event, &"menu_confirm"):
		Sfx.play("menu_confirm")
		get_viewport().set_input_as_handled()
		if _index < _zones.size():
			zone_chosen.emit(_zones[_index])
		else:
			chosen.emit(_encounters[_index - _zones.size()])
		return
	elif _pressed(event, &"menu_cancel"):
		Sfx.play("menu_cancel")
		get_viewport().set_input_as_handled()
		back.emit()
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


func _count() -> int:
	return _zones.size() + _encounters.size()


func _redraw() -> void:
	for i: int in _labels.size():
		var selected := i == _index
		var item_name := "Explore: " + _zones[i].display_name if i < _zones.size() else \
				"Fight: " + _encounters[i - _zones.size()].display_name
		_labels[i].text = (CURSOR if selected else "  ") + item_name
		_labels[i].label_settings.font_color = HudStyle.GOLD if selected else HudStyle.TEXT
	if _count() == 0:
		return
	if _index < _zones.size():
		var zone := _zones[_index]
		_detail.text = "Walk around, strike enemies first. %d enemies roam here." % zone.enemies.size()
		return
	var names := PackedStringArray()
	for enemy: EnemyData in _encounters[_index - _zones.size()].enemies:
		if enemy != null:
			names.append(enemy.display_name)
	_detail.text = "Enemies: " + ", ".join(names)
