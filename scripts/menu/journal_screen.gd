class_name JournalScreen
extends CanvasLayer
## The Rot Journal (DESIGN.md 7.11, card #200), from the main menu: a book of every enemy and attack
## the player has met. Left, the enemies in a ListMenu (alphabetical; one never met reads "???"); right,
## the chosen one: its portrait (a dark silhouette until met), where it was met, how often it was met
## and beaten, then each of its attacks with the hit kinds and marks seen and the player's record
## against it (parried, dodged, jumped, hit). An attack never seen reads "???". Up/down chooses,
## Back closes. Reads the journal it is given; the file is JournalFile's business.

signal closed

const ENEMY_DIR := "res://data/enemies"
const TITLE_SIZE: int = 64
const SUMMARY_SIZE: int = 26
const LIST_ITEM_SIZE: int = 32
const LIST_WIDTH: float = 360.0
const LIST_ROWS: int = 9
const PANEL_WIDTH: float = 1430.0
const PANEL_HEIGHT: float = 660.0
const PANEL_GAP: float = 36.0
const PORTRAIT_PX: float = 128.0
const NAME_SIZE: int = 44
const FACT_SIZE: int = 26
const SMALL_SIZE: int = 20
const ATTACK_SIZE: int = 22
const NAME_COLUMN_PX: float = 270.0
const INFO_COLUMN_PX: float = 500.0
const ROW_GAP: int = 4
const UNKNOWN := "???"
## The portrait of an enemy not met yet: a dark shape.
const SILHOUETTE := Color(0.03, 0.03, 0.05, 0.9)
const DOOM_COLOR := Color(0.9, 0.12, 0.3)
## What a hit kind is called, and what answers it (DESIGN.md 3.8).
const KIND_NAMES := {"normal": "Normal", "ground": "Ground", "rend": "Rend", "sweep": "Sweep"}
const LEGEND := "Normal: parry or dodge     Ground: jump     Rend: parry only     Sweep: dodge only"

var _journal: RotJournal
var _enemies: Array[EnemyData] = []
var _menu: ListMenu
var _summary: Label
var _panel: VBoxContainer
var _shown: int = -1


## Every enemy in the data folder, alphabetical by name.
static func load_enemies() -> Array[EnemyData]:
	var list: Array[EnemyData] = []
	var files := DirAccess.get_files_at(ENEMY_DIR)
	files.sort()
	for file: String in files:
		var file_name := file.trim_suffix(".remap")
		if not file_name.ends_with(".tres"):
			continue
		var data := load(ENEMY_DIR.path_join(file_name)) as EnemyData
		if data != null:
			list.append(data)
	list.sort_custom(func(a: EnemyData, b: EnemyData) -> bool: return a.display_name.naturalnocasecmp_to(b.display_name) < 0)
	return list


## `journal` is what the player has met; `enemies` every enemy the game has (load_enemies()).
func setup(journal: RotJournal, enemies: Array[EnemyData]) -> void:
	_journal = journal
	_enemies = enemies
	var column := ListMenu.screen_column(self, "Rot Journal", TITLE_SIZE)
	_summary = ListMenu.centred_label("", SUMMARY_SIZE, HudStyle.TEXT_DIM)
	column.add_child(_summary)
	var body := HBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_theme_constant_override("separation", int(PANEL_GAP))
	column.add_child(body)
	_menu = ListMenu.new()
	_menu.centred = false
	_menu.row_width = LIST_WIDTH
	_menu.item_size = LIST_ITEM_SIZE
	_menu.window_rows = LIST_ROWS
	_menu.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	body.add_child(_menu)
	var frame := PanelContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	frame.add_theme_stylebox_override("panel", HudStyle.panel(HudStyle.INK, HudStyle.EDGE_DIM, 2, 20))
	body.add_child(frame)
	_panel = VBoxContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_constant_override("separation", 10)
	frame.add_child(_panel)
	var rows: Array[Dictionary] = []
	for data: EnemyData in _enemies:
		var met := _journal.has_met(data.id)
		rows.append({"text": data.display_name if met else UNKNOWN, "enabled": met})
	_menu.set_items(rows)
	_summary.text = summary_text(_journal, _enemies)
	ListMenu.screen_footer(self, [[&"@updown", "Choose"], [&"menu_cancel", "Back"]])
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	var answer := _menu.handle(event)
	if answer == &"cancel":
		Sfx.play("menu_cancel")
		closed.emit()
	elif _menu.index != _shown:
		_refresh()


## "Met 7 of 19 enemies" (the book's progress line).
static func summary_text(journal: RotJournal, enemies: Array[EnemyData]) -> String:
	var met := 0
	for data: EnemyData in enemies:
		if journal.has_met(data.id):
			met += 1
	if met == 0:
		return "Nothing met yet. What you fight in a run is written here."
	return "Met %d of %d enemies" % [met, enemies.size()]


## "Normal, Ground" from an attack record's kinds (in the fixed kind order); "" when none.
static func kinds_text(kinds: Dictionary) -> String:
	var words := PackedStringArray()
	for key: String in RotJournal.KIND_KEYS:
		if int(kinds.get(key, 0)) > 0:
			words.append(String(KIND_NAMES[key]))
	return ", ".join(words)


## "parried 3  dodged 2  jumped 0  hit 4" from an attack record (a Doom the party broke adds "broken 1").
static func record_text(record: Dictionary) -> String:
	var text := "parried %d  dodged %d  jumped %d  hit %d" % [int(record.get("parried", 0)),
			int(record.get("dodged", 0)), int(record.get("jumped", 0)), int(record.get("hit", 0))]
	if int(record.get("broken", 0)) > 0:
		text += "  broken %d" % int(record.broken)
	return text


## "met in 3 fights, beaten 7 times" from an enemy entry.
static func facts_text(entry: Dictionary) -> String:
	var met := int(entry.get("met", 0))
	var beaten := int(entry.get("beaten", 0))
	return "Met in %d %s     Beaten %d %s" % [met, "fight" if met == 1 else "fights", beaten, "time" if beaten == 1 else "times"]


func _refresh() -> void:
	_shown = _menu.index
	for child: Node in _panel.get_children():
		_panel.remove_child(child)
		child.queue_free()
	if _shown < 0 or _shown >= _enemies.size():
		return
	var data := _enemies[_shown]
	var entry := _journal.enemy(data.id)
	var met := not entry.is_empty()
	_panel.add_child(_header(data, entry, met))
	if not met:
		_panel.add_child(HudStyle.make_label("Not met yet. Face it in a run to learn how it fights.", FACT_SIZE, HudStyle.TEXT_DIM))
		return
	_panel.add_child(ListMenu.divider(PANEL_WIDTH - 80.0))
	for attack: EnemyAttackData in data.all_attacks():
		_panel.add_child(_attack_row(attack, _journal.attack(data.id, attack.id)))
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(spacer)
	_panel.add_child(HudStyle.make_label(LEGEND, SMALL_SIZE, HudStyle.TEXT_DIM))


func _header(data: EnemyData, entry: Dictionary, met: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 20)
	var frame := HudStyle.portrait_frame(AssetLoader.texture(data.portrait_path), data.color if met else HudStyle.EDGE_DIM, PORTRAIT_PX)
	if not met:
		frame.get_child(0).modulate = SILHOUETTE
	row.add_child(frame)
	var text := VBoxContainer.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.add_theme_constant_override("separation", 4)
	row.add_child(text)
	var title := HudStyle.make_worn_title(data.display_name if met else UNKNOWN, NAME_SIZE)
	text.add_child(title)
	if met:
		text.add_child(HudStyle.make_label(facts_text(entry), FACT_SIZE, HudStyle.TEXT))
		var places := PackedStringArray(entry.get("places", []))
		if not places.is_empty():
			var where := HudStyle.make_label("Met at " + ", ".join(places), SMALL_SIZE, HudStyle.TEXT_DIM)
			where.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			where.custom_minimum_size.x = PANEL_WIDTH - PORTRAIT_PX - 120.0
			text.add_child(where)
	return row


## One attack: its name, the kinds and marks seen (and DOOM), and the record against it. An attack
## never seen shows only "???".
func _attack_row(attack: EnemyAttackData, record: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 16)
	var seen := int(record.get("seen", 0)) + int(record.get("broken", 0)) > 0
	var name_label := HudStyle.make_label(attack.display_name if seen else UNKNOWN, ATTACK_SIZE, HudStyle.GOLD if seen else HudStyle.TEXT_DIM)
	name_label.custom_minimum_size.x = NAME_COLUMN_PX
	name_label.clip_text = true
	row.add_child(name_label)
	if not seen:
		return row
	var info := HBoxContainer.new()
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_theme_constant_override("separation", 12)
	info.custom_minimum_size.x = INFO_COLUMN_PX
	row.add_child(info)
	var kinds := kinds_text(record.get("kinds", {}))
	if not kinds.is_empty():
		info.add_child(HudStyle.make_label(kinds, ATTACK_SIZE, HudStyle.TEXT))
	var marks: Dictionary = record.get("marks", {})
	for mark: String in marks:
		info.add_child(HudStyle.make_label(String(HudStyle.STATUS_NAMES.get(mark, mark.to_upper())), SMALL_SIZE,
				HudStyle.STATUS_COLORS.get(mark, HudStyle.TEXT) as Color))
	if attack.is_doom():
		info.add_child(HudStyle.make_label("DOOM", SMALL_SIZE, DOOM_COLOR))
	row.add_child(HudStyle.make_label(record_text(record), ATTACK_SIZE, HudStyle.TEXT_DIM.lightened(0.25)))
	return row
