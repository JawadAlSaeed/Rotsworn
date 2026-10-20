class_name TreasureScreen
extends StopScreen
## A treasure stop (DESIGN.md 8.8, 8.19): two chests, a plain one (gold and an item) and a rotten one
## (a better Relic, but maybe a curse or a fight; card #287); one can be opened
## (RunState.open_treasure). Older words: a big old chest. Open it: its prize (RunState.treasure_contents,
## always rare or better: gear goes on a hero, an item into the backpack) and some gold. Then back
## to the map. The bot calls open_chest() and leave().

signal done
## Host: the chest was opened (Main tells the clients).
signal opened

const CHEST_SCALE: int = 8
## The rotten chest: the same chest, tinted with rot.
const ROTTEN_TINT := Color(0.55, 0.78, 0.4)
## The chest not opened, once the other one is.
const UNCHOSEN_ALPHA: float = 0.35
const CHEST_GAP: int = 120

var _chest: TextureRect
var _rotten: TextureRect
var _text: Label
var _detail: Label
var _menu: ListMenu
## Which chest was opened (1: the rotten one), for the pictures.
var _opened_rotten: bool = false
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
	var chests := HBoxContainer.new()
	chests.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chests.alignment = BoxContainer.ALIGNMENT_CENTER
	chests.add_theme_constant_override("separation", CHEST_GAP)
	column.add_child(chests)
	_chest = _chest_picture()
	chests.add_child(_chest)
	_rotten = _chest_picture()
	_rotten.self_modulate = ROTTEN_TINT
	chests.add_child(_rotten)
	_text = ListMenu.centred_label("Two chests, half sunk in the mud. One is plain. One weeps black rot.", TEXT_SIZE)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(1000.0, 0.0)
	_text.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_text)
	_menu = ListMenu.new()
	column.add_child(_menu)
	_detail = ListMenu.centred_label("", TEXT_SIZE, HudStyle.TEXT_DIM)
	column.add_child(_detail)
	ListMenu.screen_footer(self, [[&"@updown", "Choose"], [&"menu_confirm", "Select"]])
	_opened_rotten = already_open and run.stop_rotten
	_show(already_open)
	if already_open and not text.is_empty():
		_text.text = text


func _chest_picture() -> TextureRect:
	var picture := TextureRect.new()
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return picture


func is_open() -> bool:
	return _open


## Opens one chest: the plain one (gold and an item) or the rotten one (a better Relic, maybe a curse
## or a fight). The bot calls this; the player uses the menu.
func open_chest(rotten: bool = false) -> void:
	if _open:
		return
	_opened_rotten = rotten
	var got := run.open_treasure(run.at, rotten)
	var prize: Resource = got.prize
	print("Run treasure: %s chest, %s +%d gold%s%s" % ["rotten" if rotten else "plain",
			String(prize.get("id")) if prize != null else "nothing", int(got.gold),
			" curse" if got.curse != null else "", " ambush" if bool(got.ambush) else ""])
	Sfx.play("chest_open")
	Sfx.play("hurt" if got.curse != null or bool(got.ambush) else "gold_gain")
	_text.text = String(got.text)
	_show(true)
	# The chest stays open for a continued run (Main saves once the prize is settled).
	opened.emit()
	var gifts: Array = []
	if prize != null:
		gifts.append(prize)
	give(gifts, _text)


func leave() -> void:
	done.emit()


func _show(is_open: bool) -> void:
	_open = is_open
	for pair: Array in [[_chest, false], [_rotten, true]]:
		var picture := pair[0] as TextureRect
		var this_one := is_open and bool(pair[1]) == _opened_rotten
		picture.texture = AssetLoader.texture(_open_path if this_one else _closed_path, Vector2i(28, 24))
		picture.custom_minimum_size = picture.texture.get_size() * CHEST_SCALE
		picture.modulate.a = UNCHOSEN_ALPHA if is_open and not this_one else 1.0
	var list: Array[Dictionary] = [{"text": "Back to the map", "enabled": not remote}]
	if not is_open:
		list = [{"text": "Open the plain chest", "enabled": not remote,
				"detail": "%d gold and a rare item." % run.tuning.run_treasure_gold},
				{"text": "Open the rotten chest", "enabled": not remote,
				"detail": "A rare or better Relic. It may bring a curse, or a fight."}]
	elif run.in_ambush():
		list = [{"text": "Fight", "enabled": not remote}]
	_menu.set_items(list, _detail)
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
		open_chest(_menu.index == 1)
