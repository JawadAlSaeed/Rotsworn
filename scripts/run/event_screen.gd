class_name EventScreen
extends StopScreen
## A "?" stop (DESIGN.md 8.7): the event's picture, its story and its choices (each with its price,
## reward and risk written out; ones the party cannot pay are greyed), plus Leave. A choice that
## asks for a hero or a backpack item opens a short pick list first. Taking a choice tells what
## happened (RunState.choose_event: a risk may strike), hands out any items, then Continue goes
## back to the map, or into the fight when the choice sprang an ambush. A "?" stop that turned into
## an ambush shows its own page ("An Ambush!") with one choice, Fight. The bot calls choose() and
## leave().

signal done
## Host: a choice was taken (Main tells the clients, who show the same result).
signal chosen(index: int, text: String)

const TEXT_WIDTH: float = 1400.0

var _event: EventData
var _look: StopVisuals
var _menu: ListMenu
var _text: Label
var _result: Label
var _detail: Label
var _decided: bool = false
## The "?" stop is an ambush: its page shows instead of an event.
var _ambush_page: bool = false
## The choice waiting for a pick, and what each row of the pick list stands for (a hero slot or an
## item uid).
var _picking: int = -1
var _pick_ids: Array[int] = []


## `result`: online clients show the host's result once it chose (empty: still choosing).
func setup(p_run: RunState, event: EventData, result: String = "") -> void:
	run = p_run
	_event = event
	_look = StopVisuals.load_default()
	_ambush_page = result.is_empty() and run.in_ambush()
	var title := event.title if event != null else "A strange place"
	if _ambush_page:
		title = run.act_data().ambush_title
	var column := ListMenu.screen_column(self, title, TITLE_SIZE)
	_add_bar(column)
	var picture_path := event.picture_path if event != null else ""
	if _ambush_page or picture_path.is_empty():
		picture_path = run.act_data().ambush_picture_path
	column.add_child(_picture_frame(picture_path))
	_text = ListMenu.centred_label(_story(), TEXT_SIZE)
	_wrap(_text)
	column.add_child(_text)
	_result = ListMenu.centred_label("", TEXT_SIZE, HudStyle.GOLD)
	_wrap(_result)
	column.add_child(_result)
	_menu = ListMenu.new()
	column.add_child(_menu)
	_detail = ListMenu.centred_label("", DETAIL_SIZE, HudStyle.TEXT_DIM)
	_wrap(_detail)
	column.add_child(_detail)
	ListMenu.screen_footer(self, [[&"@updown", "Choose"], [&"menu_confirm", "Select"]])
	_menu.set_items([], _detail)
	if not result.is_empty():
		_show_result(result)
	elif _ambush_page:
		Sfx.play("hurt")
		_show_ambush()
	else:
		_show_choices()


## The event's painted picture in a thin worn-gold frame (StopVisuals), drawn with the nearest
## filter so it is never blurred. A missing file shows the old question mark, a little bigger.
func _picture_frame(path: String) -> Control:
	var scale := _look.event_picture_scale
	if path.is_empty() or not AssetLoader.has_art(path):
		path = _look.fallback_picture_path
		scale = _look.fallback_picture_scale
	var picture := TextureRect.new()
	picture.texture = AssetLoader.texture(path, Vector2i(48, 48))
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.custom_minimum_size = picture.texture.get_size() * scale
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = _look.frame_backing_color
	style.set_border_width_all(_look.frame_border)
	style.border_color = _look.frame_border_color
	style.set_content_margin_all(float(_look.frame_padding))
	style.shadow_size = _look.frame_shadow
	style.shadow_color = Color(0.0, 0.0, 0.0, _look.frame_shadow_alpha)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", style)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(picture)
	return frame


func _wrap(label: Label) -> void:
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(TEXT_WIDTH, 0.0)
	label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER


## The story under the title: the event's, or the ambush page's.
func _story() -> String:
	if _ambush_page:
		var encounter := run.ambush_encounter()
		var line := run.act_data().ambush_text
		return line if encounter == null else "%s\n%s" % [line, encounter.display_name]
	return _event.text if _event != null else "Nothing here."


## The rows of the menu as drawn now: {text, enabled, detail}; the last one is Leave while choosing.
func rows() -> Array[Dictionary]:
	return _menu.items


## The event shown (null on an ambush page).
func event() -> EventData:
	return _event


## How many choices the event has (not counting Leave).
func choice_count() -> int:
	return _event.choices.size() if _event != null and not _ambush_page else 0


func can_choose(index: int) -> bool:
	return not _decided and _event != null and index >= 0 and index < choice_count() \
			and run.can_choose(_event.choices[index], run.at)


## What choice `index` asks the player to pick first (ZoneOfferData.Pick).
func pick_kind(index: int) -> ZoneOfferData.Pick:
	var deal := _event.choices[index].deal if index >= 0 and index < choice_count() else null
	return deal.pick_kind() if deal != null else ZoneOfferData.Pick.NONE


## Takes choice `index` (the bot calls this; the player uses the menu). `pick`: the hero slot or
## item uid a choice that asks for one needs.
func choose(index: int, pick: int = -1) -> bool:
	if not can_choose(index):
		Sfx.play("locked")
		return false
	var got := run.choose_event(_event.choices[index], run.at, index, pick)
	if not bool(got.ok):
		Sfx.play("locked")
		return false
	Sfx.play("menu_confirm")
	Sfx.play("hurt" if bool(got.risk) or bool(got.ambush) else "buff")
	print("Run event: %s choice %d%s%s" % [_event.id, index, " (risk)" if bool(got.risk) else "",
			" (ambush)" if bool(got.ambush) else ""])
	_picking = -1
	_show_result(String(got.text))
	chosen.emit(index, String(got.text))
	give(got.items as Array, _result)
	return true


func leave() -> void:
	done.emit()


func _show_ambush() -> void:
	var list: Array[Dictionary] = [{"text": "Fight", "enabled": not remote, "detail": "There is no way around it."}]
	_menu.set_items(list)


func _show_choices() -> void:
	_picking = -1
	_result.text = ""
	var list: Array[Dictionary] = []
	for i: int in choice_count():
		var c := _event.choices[i]
		var detail := run.choice_summary(c, run.at)
		if not c.detail.is_empty():
			detail += "\n" + c.detail
		list.append({"text": c.text, "enabled": not remote and run.can_choose(c, run.at), "detail": detail.strip_edges()})
	list.append({"text": "Leave", "enabled": not remote, "detail": "Walk on without touching anything."})
	_menu.set_items(list)


## The list for a choice that asks for a hero or an item: one row each, then Back.
func _show_pick(index: int) -> void:
	_picking = index
	_pick_ids.clear()
	var list: Array[Dictionary] = []
	if pick_kind(index) == ZoneOfferData.Pick.HERO:
		_result.text = "Who pays?"
		for slot: int in run.party_size():
			_pick_ids.append(slot)
			var able := run.hero_can_lose_max_hp(slot)
			list.append({"text": run.data.party[slot].display_name, "enabled": able,
					"detail": "HP %d of %d%s" % [run.hp[slot], run.max_hp(slot), "" if able else "  (nothing left to take)"]})
	else:
		_result.text = "What goes?"
		for uid: int in run.losable_uids():
			_pick_ids.append(uid)
			var e := run.backpack.entry(uid)
			list.append({"text": RunState.entry_name(e), "enabled": true, "detail": (e.item as ItemData).description})
	list.append({"text": "Back", "enabled": true, "detail": "Think again."})
	_menu.index = 0
	_menu.set_items(list)


func _show_result(text: String) -> void:
	_decided = true
	_result.text = text if not text.is_empty() else "You walk on."
	var detail := "There is no way around it." if run.in_ambush() else "Back to the map."
	var list: Array[Dictionary] = [{"text": "Fight" if run.in_ambush() else "Continue", "enabled": not remote,
			"detail": detail}]
	_menu.set_items(list)
	_refresh_bar()


func _unhandled_input(event: InputEvent) -> void:
	if remote or _overlay != null:
		return
	if _menu.handle(event) != &"confirm":
		return
	if _decided or _ambush_page:
		if is_settling():
			return
		Sfx.play("menu_confirm")
		leave()
	elif _picking >= 0:
		if _menu.index >= _pick_ids.size():
			Sfx.play("menu_cancel")
			var back := _picking
			_show_choices()
			_menu.index = back
			_menu.redraw()
		else:
			choose(_picking, _pick_ids[_menu.index])
	elif _menu.index >= choice_count():
		Sfx.play("menu_cancel")
		_show_result("")
		chosen.emit(-1, "")
	elif pick_kind(_menu.index) != ZoneOfferData.Pick.NONE:
		Sfx.play("menu_confirm")
		_show_pick(_menu.index)
	else:
		choose(_menu.index)
