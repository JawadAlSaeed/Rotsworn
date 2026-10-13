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
const ITEM_SIZE: int = 32
const DETAIL_SIZE: int = 26

var _encounters: Array[EncounterData] = []
var _zones: Array[ZoneData] = []
var _menu: ListMenu


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
	var column := ListMenu.screen_column(self, "Practice", TITLE_SIZE)
	_menu = ListMenu.new()
	_menu.centred = false
	_menu.item_size = ITEM_SIZE
	column.add_child(_menu)
	var detail := ListMenu.centred_label("", DETAIL_SIZE, HudStyle.TEXT_DIM)
	column.add_child(detail)
	ListMenu.screen_footer(self, [[&"@updown", "Choose"], [&"menu_confirm", "Start"], [&"menu_cancel", "Main menu"]])
	var items: Array[Dictionary] = []
	for zone: ZoneData in zones:
		items.append({"text": zone.display_name, "value": "Explore",
				"detail": "Walk around, strike enemies first. %d enemies roam here." % zone.enemies.size()})
	for encounter: EncounterData in encounters:
		var names := PackedStringArray()
		for enemy: EnemyData in encounter.enemies:
			if enemy != null:
				names.append(enemy.display_name)
		items.append({"text": encounter.display_name, "value": "Fight", "detail": "Enemies: " + ", ".join(names)})
	_menu.index = clampi(start_index, 0, maxi(0, items.size() - 1))
	_menu.set_items(items, detail)


func selected_index() -> int:
	return _menu.index


func _unhandled_input(event: InputEvent) -> void:
	if _menu.items.is_empty():
		return
	match _menu.handle(event):
		&"confirm":
			Sfx.play("menu_confirm")
			if _menu.index < _zones.size():
				zone_chosen.emit(_zones[_menu.index])
			else:
				chosen.emit(_encounters[_menu.index - _zones.size()])
		&"cancel":
			Sfx.play("menu_cancel")
			back.emit()
