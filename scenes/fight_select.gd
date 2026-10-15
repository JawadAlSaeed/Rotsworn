class_name FightSelect
extends CanvasLayer
## Practice list (from the main menu): the tutorial (DESIGN.md 7.8) first, then the zones to
## explore (data/zones, DESIGN.md 7.4), then every test fight in data/encounters (DESIGN.md 2.11), the deep fights (variants, 2.16)
## last. A grid of picture cards, three to a row, that scrolls (user request 2026-10-14): a zone
## card shows the zone's backdrop, a fight card its monsters. The arrows (menu_* actions) move the
## choice, confirm starts it, cancel goes back to the main menu; the mouse wheel scrolls, a click
## picks a card and a click on the picked card starts it.

signal chosen(encounter: EncounterData)
signal zone_chosen(zone: ZoneData)
signal tutorial_chosen
signal back

const ENCOUNTER_DIR := "res://data/encounters"
const ZONE_DIR := "res://data/zones"
const TITLE_SIZE: int = 64
const DETAIL_SIZE: int = 26
const COLUMNS: int = 3
const CARD_SIZE := Vector2(400.0, 300.0)
## Height of a card's picture, and the most monsters one card shows side by side.
const PICTURE_HEIGHT: float = 190.0
const MAX_PICTURES: int = 3
const CARD_GAP: int = 24
const NAME_SIZE: int = 30
const KIND_SIZE: int = 22
const CARD_PADDING: int = 12
const CARD_BORDER_PX: int = 2
const CHOSEN_BORDER_PX: int = 4
const CHOSEN_BG := Color(0.16, 0.13, 0.07, 0.9)
## Deep fights (variants) are tagged in this colour.
const DEEP_COLOR := Color(1.0, 0.45, 0.35)

var _encounters: Array[EncounterData] = []
var _zones: Array[ZoneData] = []
## Cards before the zones (1 with the tutorial card).
var _lead: int = 0
var _index: int = 0
var _cards: Array[PanelContainer] = []
var _names: Array[Label] = []
var _details: PackedStringArray = PackedStringArray()
var _scroll: ScrollContainer
var _detail: Label
## Process frame of the last stick move (a held stick sends many motion events).
var _stick_frame: int = -1


## Every encounter in the data folder: the ordinary fights by file name, then the deep fights
## (those another fight names as its `deep` version) by file name.
static func load_encounters() -> Array[EncounterData]:
	var all: Array[EncounterData] = []
	var files := DirAccess.get_files_at(ENCOUNTER_DIR)
	files.sort()
	for file: String in files:
		var file_name := file.trim_suffix(".remap")
		if not file_name.ends_with(".tres"):
			continue
		var encounter := load(ENCOUNTER_DIR.path_join(file_name)) as EncounterData
		if encounter != null:
			all.append(encounter)
	var deep := deep_ids(all)
	var list: Array[EncounterData] = []
	for encounter: EncounterData in all:
		if not deep.has(encounter.id):
			list.append(encounter)
	for encounter: EncounterData in all:
		if deep.has(encounter.id):
			list.append(encounter)
	return list


## Ids of the fights that are another fight's deep version.
static func deep_ids(encounters: Array[EncounterData]) -> Dictionary:
	var ids: Dictionary = {}
	for encounter: EncounterData in encounters:
		if encounter.deep != null:
			ids[encounter.deep.id] = true
	return ids


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


## The first frame (idle) of an enemy's sheet, for a picture.
static func idle_frame(enemy: EnemyData) -> Texture2D:
	var sheet := AssetLoader.texture(enemy.sprite_path, Vector2i(64, 64))
	var size := Vector2(sheet.get_size())
	if enemy.sprite_clips != null and enemy.sprite_clips.frame_size.x > 0:
		size = Vector2(enemy.sprite_clips.frame_size)
	elif enemy.sprite_hframes > 1:
		size.x = size.x / float(enemy.sprite_hframes)
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(Vector2.ZERO, size)
	return atlas


## Builds the grid with `start_index` chosen (the tutorial, if given, then zones, then encounters).
func setup(zones: Array[ZoneData], encounters: Array[EncounterData], start_index: int,
		tutorial: TutorialData = null) -> void:
	_zones = zones
	_encounters = encounters
	var column := ListMenu.screen_column(self, "Practice", TITLE_SIZE)
	column.alignment = BoxContainer.ALIGNMENT_BEGIN
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_scroll.custom_minimum_size.x = CARD_SIZE.x * COLUMNS + CARD_GAP * (COLUMNS - 1) + CARD_GAP
	column.add_child(_scroll)
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", CARD_GAP)
	grid.add_theme_constant_override("v_separation", CARD_GAP)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(grid)
	_detail = ListMenu.centred_label("", DETAIL_SIZE, HudStyle.TEXT_DIM)
	column.add_child(_detail)
	ListMenu.screen_footer(self, [[&"@arrows", "Choose"], [&"menu_confirm", "Start"], [&"menu_cancel", "Main menu"]])

	if tutorial != null and tutorial.encounter != null:
		# The heroes' faces: the tutorial teaches them, not a monster.
		var faces: Array[Texture2D] = []
		for hero: CharacterData in tutorial.encounter.party:
			if hero != null and not hero.portrait_path.is_empty() and faces.size() < MAX_PICTURES:
				faces.append(AssetLoader.texture(hero.portrait_path, Vector2i(64, 64)))
		grid.add_child(_card("Tutorial", "%d short lessons" % tutorial.lesson_count(), faces, false))
		_details.append("Learn to fight: attacking, skills, defending and the team ultimate.")
		_lead = 1
	for zone: ZoneData in zones:
		var pictures: Array[Texture2D] = []
		if zone.look != null and not zone.look.backdrop_path.is_empty():
			pictures.append(AssetLoader.texture(zone.look.backdrop_path, Vector2i(320, 120)))
		grid.add_child(_card(zone.display_name, "Explore: %d roaming" % zone.enemies.size(), pictures, false))
		_details.append("Walk around, strike enemies first. %d enemies roam here." % zone.enemies.size())
	var deep := deep_ids(encounters)
	for encounter: EncounterData in encounters:
		var names := PackedStringArray()
		var pictures: Array[Texture2D] = []
		var shown: Dictionary = {}
		for enemy: EnemyData in encounter.enemies:
			if enemy == null:
				continue
			names.append(enemy.display_name)
			if not shown.has(enemy.id) and pictures.size() < MAX_PICTURES:
				shown[enemy.id] = true
				pictures.append(idle_frame(enemy))
		var is_deep := deep.has(encounter.id)
		var kind := "Deep fight" if is_deep else ("Fight: %d enemies" % names.size() if names.size() > 1 else "Fight")
		grid.add_child(_card(encounter.display_name, kind, pictures, is_deep))
		_details.append("Enemies: " + ", ".join(names))
	_index = clampi(start_index, 0, maxi(0, _cards.size() - 1))
	_redraw()
	_show_chosen_after_layout.call_deferred()


func selected_index() -> int:
	return _index


## One card: its picture(s) on top, the name and what it is under them.
func _card(title: String, kind: String, pictures: Array[Texture2D], deep: bool) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var i := _cards.size()
	card.gui_input.connect(_on_card_input.bind(i))
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.custom_minimum_size.y = PICTURE_HEIGHT
	row.add_theme_constant_override("separation", 0)
	box.add_child(row)
	for texture: Texture2D in pictures:
		var picture := TextureRect.new()
		picture.texture = texture
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		picture.custom_minimum_size.y = PICTURE_HEIGHT
		row.add_child(picture)
	var name_label := HudStyle.make_title(title, NAME_SIZE)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(name_label)
	var kind_label := HudStyle.make_label(kind, KIND_SIZE, DEEP_COLOR if deep else HudStyle.TEXT_DIM)
	kind_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(kind_label)
	_cards.append(card)
	_names.append(name_label)
	return card


func _redraw() -> void:
	for i: int in _cards.size():
		var chosen := i == _index
		var style := HudStyle.panel(CHOSEN_BG if chosen else HudStyle.PANEL_BG,
				HudStyle.GOLD if chosen else HudStyle.PANEL_BORDER,
				CHOSEN_BORDER_PX if chosen else CARD_BORDER_PX, CARD_PADDING)
		_cards[i].add_theme_stylebox_override("panel", style)
		_names[i].label_settings = HudStyle.title_settings(NAME_SIZE,
				HudStyle.fonts().select_color if chosen else HudStyle.fonts().idle_color)
		_names[i].material = HudStyle.worn_material() if chosen else null
	_detail.text = _details[_index] if _index < _details.size() else ""


## Scrolls just far enough that the chosen card is fully in view.
func _show_chosen() -> void:
	if _index >= _cards.size() or _scroll == null:
		return
	var card := _cards[_index]
	var top := int(card.position.y)
	var bottom := int(card.position.y + card.size.y)
	if top < _scroll.scroll_vertical:
		_scroll.scroll_vertical = top
	elif bottom > _scroll.scroll_vertical + int(_scroll.size.y):
		_scroll.scroll_vertical = bottom - int(_scroll.size.y)


## The first scroll waits until the grid has been laid out (card positions are known).
func _show_chosen_after_layout() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_scroll.scroll_vertical = 0
	_show_chosen()


func _choose(i: int) -> void:
	if i == _index or i < 0 or i >= _cards.size():
		return
	_index = i
	Sfx.play("menu_move")
	_redraw()
	_show_chosen()


func _start() -> void:
	Sfx.play("menu_confirm")
	if _index < _lead:
		tutorial_chosen.emit()
	elif _index < _lead + _zones.size():
		zone_chosen.emit(_zones[_index - _lead])
	else:
		chosen.emit(_encounters[_index - _lead - _zones.size()])


func _on_card_input(event: InputEvent, i: int) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if i == _index:
		_start()
	else:
		_choose(i)


func _unhandled_input(event: InputEvent) -> void:
	if _cards.is_empty():
		return
	var handled := true
	if _pressed(event, &"menu_left"):
		_choose(wrapi(_index - 1, 0, _cards.size()))
	elif _pressed(event, &"menu_right"):
		_choose(wrapi(_index + 1, 0, _cards.size()))
	elif _pressed(event, &"menu_up"):
		_choose(_index - COLUMNS if _index >= COLUMNS else _index)
	elif _pressed(event, &"menu_down"):
		_choose(mini(_index + COLUMNS, _cards.size() - 1))
	elif _pressed(event, &"menu_confirm"):
		_start()
	elif _pressed(event, &"menu_cancel"):
		Sfx.play("menu_cancel")
		back.emit()
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


## Like ListMenu: a held stick sends many motion events, only the first counts.
func _pressed(event: InputEvent, action: StringName) -> bool:
	if not event.is_action_pressed(action, false, true):
		return false
	if event is InputEventJoypadMotion:
		var frame := Engine.get_process_frames()
		if not Input.is_action_just_pressed(action) or frame == _stick_frame:
			return false
		_stick_frame = frame
	return true
