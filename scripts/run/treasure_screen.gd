class_name TreasureScreen
extends StopScreen
## A treasure stop (DESIGN.md 8.8): a big old chest. Open it: its prize (RunState.treasure_contents,
## always rare or better: gear goes on a hero, an item into the backpack) and some gold. Then back
## to the map. The bot calls open_chest() and leave().

signal done
## Host: the chest was opened (Main tells the clients).
signal opened

const CHEST_SCALE: int = 8

var _chest: TextureRect
var _text: Label
var _menu: ListMenu
var _open: bool = false
var _closed_path: String = ""
var _open_path: String = ""


## `already_open`: online clients show the chest as the host left it.
func setup(p_run: RunState, explore: ExploreVisuals, already_open: bool = false, text: String = "") -> void:
	run = p_run
	_closed_path = explore.chest_closed_path
	_open_path = explore.chest_open_path
	var column := ListMenu.screen_column(self, "Treasure", TITLE_SIZE)
	_add_bar(column)
	_chest = TextureRect.new()
	_chest.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_chest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_chest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_chest.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_chest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_chest)
	_text = ListMenu.centred_label("An old chest, half sunk in the mud, its lock rusted through.", TEXT_SIZE)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(1000.0, 0.0)
	_text.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_text)
	_menu = ListMenu.new()
	column.add_child(_menu)
	ListMenu.screen_footer(self, [[&"menu_confirm", "Select"]])
	_show(already_open)
	if already_open and not text.is_empty():
		_text.text = text


func is_open() -> bool:
	return _open


## Opens the chest: gold at once, then the prize (the bot calls this; the player uses confirm).
func open_chest() -> void:
	if _open:
		return
	var prize := run.treasure_contents(run.at)
	var coins := run.take_treasure_gold()
	print("Run treasure: %s +%d gold" % [String(prize.get("id")) if prize != null else "nothing", coins])
	Sfx.play("chest_open")
	Sfx.play("gold_gain")
	var name := ""
	if prize is GearData:
		name = (prize as GearData).display_name
	elif prize is ItemData:
		name = (prize as ItemData).display_name
	_text.text = ("Inside: %s and %d gold." % [name, coins]) if not name.is_empty() else "Only %d gold." % coins
	_show(true)
	# The chest stays open for a continued run (Main saves once the prize is settled).
	run.stop_done = true
	run.stop_text = _text.text
	opened.emit()
	var gifts: Array = []
	if prize != null:
		gifts.append(prize)
	give(gifts, _text)


func leave() -> void:
	done.emit()


func _show(is_open: bool) -> void:
	_open = is_open
	_chest.texture = AssetLoader.texture(_open_path if is_open else _closed_path, Vector2i(28, 24))
	_chest.custom_minimum_size = _chest.texture.get_size() * CHEST_SCALE
	var list: Array[Dictionary] = [{"text": "Back to the map" if is_open else "Open the chest", "enabled": not remote}]
	_menu.set_items(list)
	_refresh_bar()


func _unhandled_input(event: InputEvent) -> void:
	if remote or _overlay != null:
		return
	if _menu.handle(event) != &"confirm" or is_settling():
		return
	Sfx.play("menu_confirm")
	if _open:
		leave()
	else:
		open_chest()
