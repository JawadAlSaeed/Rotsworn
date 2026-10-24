class_name EventScreen
extends StopScreen
## A "?" stop (DESIGN.md 8.7): the event's picture, its story and its choices as side-by-side cards
## (card #288), each with its price, reward and risk as icon chips (coin -40, heart +30%, a skull for
## a curse, crossed swords for a fight, a die with the risk's chance); ones the party cannot pay are
## greyed. Leave is the cancel button (a hint in the footer), not a card. The starting pact (card
## #285) is shown the same way. A choice that asks for a hero or a backpack item opens a short pick
## first: cards when PICK_CARDS_MAX or fewer, else a column; cancel returns to the cards. Taking a choice tells what happened
## (RunState.choose_event: a risk may strike), hands out any items, then Continue goes
## back to the map, or into the fight when the choice sprang an ambush. A "?" stop that turned into
## an ambush shows its own page ("An Ambush!") with one choice, Fight. The bot calls choose() and
## leave().

signal done
## Host: a choice was taken (Main tells the clients, who show the same result).
signal chosen(index: int, text: String)

## A pick list of this many or fewer (who pays, what goes) shows as cards side by side.
const PICK_CARDS_MAX: int = 3

const TEXT_WIDTH: float = 1400.0

var _event: EventData
var _look: StopVisuals
var _menu: ListMenu
var _text: Label
var _result: Label
var _detail: Label
var _footer: HintBar
## The footer's hints now (tests read them).
var _footer_now: Array = []
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
	_result.visible = false
	column.add_child(_result)
	_menu = ListMenu.new()
	column.add_child(_menu)
	# Only the pick list says more about the chosen row (a hero's HP, an item).
	_detail = ListMenu.centred_label("", DETAIL_SIZE, HudStyle.TEXT_DIM)
	_wrap(_detail)
	_detail.visible = false
	column.add_child(_detail)
	_footer = ListMenu.screen_footer(self, [])
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


## The rows of the menu as drawn now: {text, enabled, chips, ...}; while choosing, one card per
## choice (Leave is the cancel button, not a row).
func rows() -> Array[Dictionary]:
	return _menu.items


## The menu (tests).
func menu() -> ListMenu:
	return _menu


## The footer's hints now (tests): [[action, text], ...].
func footer_entries() -> Array:
	return _footer_now


func _set_footer(entries: Array) -> void:
	_footer_now = entries
	_footer.set_entries(entries)


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
	if _ask({"do": "choose", "index": index, "pick": pick}):
		Sfx.play("menu_confirm")
		return true
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


## Continue (or Fight) once the choice is made, or on an ambush page.
func leave() -> void:
	if _ask({"do": "leave"}):
		return
	done.emit()


## Leave while choosing: walk on, taking nothing. False once the choice is made or on an ambush page.
func walk_on() -> bool:
	if _decided or _ambush_page or _event == null:
		return false
	Sfx.play("menu_cancel")
	if _ask({"do": "walk_on"}):
		return true
	_show_result("")
	chosen.emit(-1, "")
	return true


## True once a choice is made (or Leave walked on).
func is_decided() -> bool:
	return _decided


## True on an ambush page (its one choice is Fight).
func is_ambush_page() -> bool:
	return _ambush_page


## Online (card #314): the turn changed: the cards (or Continue) redraw, lit or greyed. A pick list
## open goes back to the cards.
func _turn_changed() -> void:
	if _decided:
		_show_result(_result.text)
	elif _ambush_page:
		_show_ambush()
	else:
		var keep := _picking if _picking >= 0 else _menu.index
		_menu.index = clampi(keep, 0, maxi(0, choice_count() - 1))
		_show_choices()


func _show_ambush() -> void:
	var list: Array[Dictionary] = [{"text": "Fight", "enabled": not is_greyed()}]
	_show_list(list, false)
	_set_footer([[&"menu_confirm", "Fight"]])


func _show_choices() -> void:
	_picking = -1
	_say_result("")
	var list: Array[Dictionary] = []
	for i: int in choice_count():
		var c := _event.choices[i]
		list.append({"text": c.text, "enabled": not is_greyed() and run.can_choose(c, run.at),
				"chips": StopScreen.chip_entries(run.choice_chips(c, run.at), _look)})
	_show_list(list, true)
	_set_footer([[&"@leftright", "Choose"], [&"menu_confirm", "Select"], [&"menu_cancel", "Leave"]])


## Shows `list` as cards side by side, or as a column (a pick list, one row to go on).
func _show_list(list: Array[Dictionary], cards: bool) -> void:
	_menu.horizontal = cards
	_detail.visible = not cards and _picking >= 0
	_menu.set_items(list)


## The list for a choice that asks for a hero or an item: a card each (the hero's face and HP, the
## item's picture) side by side when there are PICK_CARDS_MAX or fewer, else a column. Back is the
## cancel button, never a row (owner, phase 22).
func _show_pick(index: int) -> void:
	_picking = index
	_pick_ids.clear()
	var list: Array[Dictionary] = []
	if pick_kind(index) == ZoneOfferData.Pick.HERO:
		_say_result("Who pays?")
		for slot: int in run.party_size():
			_pick_ids.append(slot)
			var hero := run.data.party[slot]
			list.append({"text": hero.display_name, "enabled": run.hero_can_lose_max_hp(slot),
					"icon": AssetLoader.texture(hero.portrait_path, Vector2i(48, 48)),
					"detail": "HP %d of %d" % [run.hp[slot], run.max_hp(slot)],
					"chips": [{"glyph": &"heart", "text": "%d / %d" % [run.hp[slot], run.max_hp(slot)], "color": HudStyle.TEXT}]})
	else:
		_say_result("What goes?")
		for uid: int in run.losable_uids():
			_pick_ids.append(uid)
			var e := run.backpack.entry(uid)
			list.append({"text": RunState.entry_name(e), "enabled": true,
					"icon": AssetLoader.texture((e.item as ItemData).icon_path, Vector2i(16, 16)),
					"detail": (e.item as ItemData).description})
	_menu.index = 0
	var cards := list.size() <= PICK_CARDS_MAX
	_show_list(list, cards)
	_set_footer([[&"@leftright" if cards else &"@updown", "Choose"], [&"menu_confirm", "Select"],
			[&"menu_cancel", "Back"]])


func _show_result(text: String) -> void:
	_decided = true
	_say_result(text if not text.is_empty() else "You walk on.")
	var go := "Fight" if run.in_ambush() else "Continue"
	var list: Array[Dictionary] = [{"text": go, "enabled": not is_greyed()}]
	_show_list(list, false)
	_set_footer([[&"menu_confirm", go]])
	_refresh_bar()


func _unhandled_input(event: InputEvent) -> void:
	if is_greyed() or _overlay != null:
		return
	var answer := _menu.handle(event)
	if answer == &"cancel":
		_cancel()
		return
	if answer != &"confirm":
		return
	if _decided or _ambush_page:
		if is_settling():
			return
		Sfx.play("menu_confirm")
		leave()
	elif _picking >= 0:
		if _menu.index >= _pick_ids.size():
			_back_from_pick()
		else:
			choose(_picking, _pick_ids[_menu.index])
	elif pick_kind(_menu.index) != ZoneOfferData.Pick.NONE and can_choose(_menu.index):
		Sfx.play("menu_confirm")
		_show_pick(_menu.index)
	else:
		choose(_menu.index)


## Cancel: back from a pick list, or Leave while choosing (walk on, taking nothing). Nothing once
## the choice is made or on an ambush page.
func _cancel() -> void:
	if _picking >= 0:
		_back_from_pick()
	else:
		walk_on()


## The gold line over the menu; hidden while empty, so the cards keep the room.
func _say_result(text: String) -> void:
	_result.text = text
	_result.visible = not text.is_empty()


## Back from a pick list to the cards, the cursor on the choice that asked.
func _back_from_pick() -> void:
	Sfx.play("menu_cancel")
	var back := _picking
	_picking = -1
	_menu.index = back
	_show_choices()
