class_name EventScreen
extends StopScreen
## A "?" stop (DESIGN.md 8.7): the event's picture, its story and its choices (each with its price
## and gift; ones the party cannot pay are greyed), plus Leave. Taking a choice tells what happened
## (RunState.choose_event: a risk may strike), hands out any items, then Continue goes back to the
## map. The bot calls choose() and leave().

signal done
## Host: a choice was taken (Main tells the clients, who show the same result).
signal chosen(index: int, text: String)

const PICTURE_SCALE: int = 4

var _event: EventData
var _menu: ListMenu
var _text: Label
var _result: Label
var _decided: bool = false


## `result`: online clients show the host's result once it chose (empty: still choosing).
func setup(p_run: RunState, event: EventData, result: String = "") -> void:
	run = p_run
	_event = event
	var column := ListMenu.screen_column(self, event.title if event != null else "A strange place", TITLE_SIZE)
	_add_bar(column)
	if event != null and not event.picture_path.is_empty():
		var picture := TextureRect.new()
		picture.texture = AssetLoader.texture(event.picture_path, Vector2i(48, 48))
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.custom_minimum_size = picture.texture.get_size() * PICTURE_SCALE
		picture.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(picture)
	_text = ListMenu.centred_label(event.text if event != null else "Nothing here.", TEXT_SIZE)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(1100.0, 0.0)
	_text.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_text)
	_result = ListMenu.centred_label("", TEXT_SIZE, HudStyle.GOLD)
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result.custom_minimum_size = Vector2(1100.0, 0.0)
	_result.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_result)
	_menu = ListMenu.new()
	column.add_child(_menu)
	var detail := ListMenu.centred_label("", DETAIL_SIZE, HudStyle.TEXT_DIM)
	column.add_child(detail)
	ListMenu.screen_footer(self, [[&"@updown", "Choose"], [&"menu_confirm", "Select"]])
	_menu.set_items([], detail)
	if not result.is_empty():
		_show_result(result)
	else:
		_show_choices()


## How many choices the event has (not counting Leave).
func choice_count() -> int:
	return _event.choices.size() if _event != null else 0


func can_choose(index: int) -> bool:
	return not _decided and _event != null and index >= 0 and index < choice_count() \
			and run.can_choose(_event.choices[index])


## Takes choice `index` (the bot calls this; the player uses the menu).
func choose(index: int) -> bool:
	if not can_choose(index):
		Sfx.play("locked")
		return false
	var got := run.choose_event(_event.choices[index], run.at, index)
	if not bool(got.ok):
		Sfx.play("locked")
		return false
	Sfx.play("menu_confirm")
	Sfx.play("hurt" if bool(got.risk) else "buff")
	print("Run event: %s choice %d%s" % [_event.id, index, " (risk)" if bool(got.risk) else ""])
	_show_result(String(got.text))
	chosen.emit(index, String(got.text))
	give(got.items as Array, _result)
	return true


func leave() -> void:
	done.emit()


func _show_choices() -> void:
	var list: Array[Dictionary] = []
	for i: int in choice_count():
		var c := _event.choices[i]
		var detail := c.detail
		if c.risk_percent > 0 and not detail.is_empty():
			detail += "  (risky)"
		list.append({"text": c.text, "enabled": not remote and run.can_choose(c), "detail": detail})
	list.append({"text": "Leave", "enabled": not remote, "detail": "Walk on without touching anything."})
	_menu.set_items(list)


func _show_result(text: String) -> void:
	_decided = true
	_result.text = text if not text.is_empty() else "You walk on."
	var list: Array[Dictionary] = [{"text": "Continue", "enabled": not remote, "detail": "Back to the map."}]
	_menu.set_items(list)
	_refresh_bar()


func _unhandled_input(event: InputEvent) -> void:
	if remote or _overlay != null:
		return
	if _menu.handle(event) != &"confirm":
		return
	if _decided:
		if is_settling():
			return
		Sfx.play("menu_confirm")
		leave()
	elif _menu.index >= choice_count():
		Sfx.play("menu_cancel")
		_show_result("")
		chosen.emit(-1, "")
	else:
		choose(_menu.index)
