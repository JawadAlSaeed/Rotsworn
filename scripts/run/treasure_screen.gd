class_name TreasureScreen
extends StopScreen
## A treasure stop (DESIGN.md 8.8, 8.24): two chests, a plain one (gold and a rare item, into the
## backpack) and a rotten one (a pick of rare Relics, but maybe a curse or a fight; card #287); one can
## be opened (RunState.open_treasure). The rotten chest's Relics show as cards: pick one, then the hero
## who gets it ("Who gets it?", RelicGift; skipped when only one hero may). Then back to the map. The
## bot calls open_chest(), take_relic() and leave().
## The two chests are side-by-side cards (card #288): the chest's picture, a word, and chips for what
## it holds (gold and a rare item; rare Relics) and what the rotten one may bring (a curse, a fight,
## each with its chance). Once one is open, the two chests stand above the result as they were left.

signal done
## Host: the chest was opened, or its Relic taken (Main tells the clients).
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
var _footer: HintBar
var _menu: ListMenu
var _look: StopVisuals
## The two big chests above the result (shown once one is open).
var _chests: HBoxContainer
## Which chest was opened (1: the rotten one), for the pictures.
var _opened_rotten: bool = false
var _open: bool = false
var _closed_path: String = ""
var _open_path: String = ""
## The rotten chest's Relic waiting for its hero (-1: choosing a Relic), and the pad that picked it
## (local co-op: that player's heroes get it).
var _giving: int = -1
var _device: int = PlayerRoster.ANY
var _ask_label: Label


## `already_open`: online clients show the chest as the host left it.
func setup(p_run: RunState, already_open: bool = false, text: String = "") -> void:
	run = p_run
	_look = StopVisuals.load_default()
	_closed_path = _look.chest_closed_path
	_open_path = _look.chest_open_path
	var column := ListMenu.screen_column(self, "Treasure", TITLE_SIZE)
	_add_bar(column)
	_chests = HBoxContainer.new()
	_chests.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chests.alignment = BoxContainer.ALIGNMENT_CENTER
	_chests.add_theme_constant_override("separation", CHEST_GAP)
	column.add_child(_chests)
	_chest = _chest_picture()
	_chests.add_child(_chest)
	_rotten = _chest_picture()
	_rotten.self_modulate = ROTTEN_TINT
	_chests.add_child(_rotten)
	# Empty while choosing (the cards say it all); what was inside shows here once opened.
	_text = ListMenu.centred_label("", TEXT_SIZE)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(1000.0, 0.0)
	_text.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_text)
	_ask_label = ListMenu.centred_label(RelicGift.ASK, LootScreen.ASK_SIZE, HudStyle.GOLD)
	_ask_label.visible = false
	column.add_child(_ask_label)
	_menu = ListMenu.new()
	column.add_child(_menu)
	_footer = ListMenu.screen_footer(self, [])
	_opened_rotten = already_open and run.stop_rotten
	_show(already_open)
	if already_open and not text.is_empty():
		_text.text = text
	_text.visible = not _text.text.is_empty()


func _chest_picture() -> TextureRect:
	var picture := TextureRect.new()
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return picture


func is_open() -> bool:
	return _open


## True while the rotten chest's Relics wait for one to be taken.
func relic_waiting() -> bool:
	return _open and not run.stop_relics.is_empty()


## The rotten chest's Relics on offer (RunState.stop_relic_choices).
func relic_choices() -> Array[GearData]:
	return run.stop_relic_choices()


## Takes the rotten chest's Relic `index` and gives it to hero `hero` (one RelicGift.allowed lets
## have it). The bot calls this; the player uses the cards. False if refused.
func take_relic(index: int, hero: int) -> bool:
	if not relic_waiting() or index < 0 or index >= relic_choices().size() \
			or not RelicGift.allowed(give_heroes, run, _device).has(hero):
		return false
	if _ask({"do": "relic", "index": index, "hero": hero}):
		return true
	var got := run.take_stop_relic(index, hero)
	if got.is_empty():
		return false
	print("Run treasure Relic: %s hero=%d" % [(got.item as GearData).id, hero])
	Sfx.play("buff")
	_giving = -1
	_device = PlayerRoster.ANY
	_text.text = run.stop_text
	_text.visible = not _text.text.is_empty()
	_show(true)
	opened.emit()
	# Saves the stop (Main listens to gifts_settled).
	give([], _text)
	return true


## Opens one chest: the plain one (gold and an item) or the rotten one (a better Relic, maybe a curse
## or a fight). The bot calls this; the player uses the menu.
func open_chest(rotten: bool = false) -> void:
	if _open or _ask({"do": "open", "rotten": rotten}):
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
	_text.visible = true
	_show(true)
	# The chest stays open for a continued run (Main saves once the prize is settled).
	opened.emit()
	var gifts: Array = []
	if prize is ItemData:
		gifts.append(prize)
	give(gifts, _text)


func leave() -> void:
	if _ask({"do": "leave"}):
		return
	done.emit()


## Online (card #314): the turn changed: the chest cards (or the Relics, or Continue) redraw, lit or
## greyed; a Relic waiting for its hero goes back to the Relics.
func _turn_changed() -> void:
	_giving = -1
	_device = PlayerRoster.ANY
	_show(_open)


func _show(is_open: bool) -> void:
	_open = is_open
	for pair: Array in [[_chest, false], [_rotten, true]]:
		var picture := pair[0] as TextureRect
		var this_one := is_open and bool(pair[1]) == _opened_rotten
		picture.texture = AssetLoader.texture(_open_path if this_one else _closed_path, Vector2i(28, 24))
		picture.custom_minimum_size = picture.texture.get_size() * CHEST_SCALE
		picture.modulate.a = UNCHOSEN_ALPHA if is_open and not this_one else 1.0
	# While choosing, the chests are on the cards; the big ones show how they were left.
	_chests.visible = is_open
	var list: Array[Dictionary] = [{"text": "Back to the map", "enabled": not is_greyed()}]
	_menu.horizontal = not is_open or relic_waiting()
	_ask_label.visible = relic_waiting() and _giving >= 0
	if relic_waiting():
		if _giving >= 0:
			list = RelicGift.hero_cards(run, RelicGift.allowed(give_heroes, run, _device), is_greyed())
			_footer.set_entries([[&"@leftright", "Choose"], [&"menu_confirm", "Give"], [&"menu_cancel", "Back"]])
		else:
			list = relic_cards()
			_footer.set_entries([[&"@leftright", "Choose"], [&"menu_confirm", "Take"]])
	elif not is_open:
		list = chest_cards()
		_footer.set_entries([[&"@leftright", "Choose"], [&"menu_confirm", "Open"]])
	else:
		if run.in_ambush():
			list = [{"text": "Fight", "enabled": not is_greyed()}]
		_footer.set_entries([[&"menu_confirm", "Fight" if run.in_ambush() else "Continue"]])
	_menu.set_items(list)
	_refresh_bar()


## The two chest cards: the plain one (gold and a rare item) and the rotten one (a rare Relic, and
## the chance of a curse and of a fight), each with its chest's picture.
func chest_cards() -> Array[Dictionary]:
	var closed := AssetLoader.texture(_closed_path, Vector2i(28, 24))
	var gift := _look.chip_gift_color
	var risk := _look.chip_risk_color
	var rotten_chips: Array[Dictionary] = [StopScreen.chip_entry(_look, "relic", "Rare Relics", gift)]
	if run.tuning.rotten_chest_curse_percent > 0:
		rotten_chips.append(StopScreen.chip_entry(_look, "curse", "Curse %d%%" % run.tuning.rotten_chest_curse_percent, risk))
	if run.tuning.rotten_chest_fight_percent > 0:
		rotten_chips.append(StopScreen.chip_entry(_look, "fight", "Fight %d%%" % run.tuning.rotten_chest_fight_percent, risk))
	var cards: Array[Dictionary] = [
		{"text": "Plain", "enabled": not is_greyed(), "icon": closed, "icon_scale": _look.chest_card_scale,
				"chips": [StopScreen.chip_entry(_look, "gold", "+%d gold" % run.tuning.run_treasure_gold, gift),
						StopScreen.chip_entry(_look, "find", "Rare item", gift)]},
		{"text": "Rotten", "enabled": not is_greyed(), "icon": closed, "icon_scale": _look.chest_card_scale,
				"icon_color": ROTTEN_TINT, "chips": rotten_chips},
	]
	return cards


## The rotten chest's Relics as cards (LootScreen's look): icon, name, New or Home, chips.
func relic_cards() -> Array[Dictionary]:
	var cards: Array[Dictionary] = []
	for item: GearData in relic_choices():
		var make := func() -> Control: return RelicIcon.make(item, LootScreen.ICON_PX)
		cards.append({"text": item.display_name, "value": "Home" if run.is_home(item) else "New",
				"chips": LootScreen.relic_chips(item), "icon_make": make, "enabled": not is_greyed(),
				"color": GearData.ROT_TOUCHED_COLOR if item.rot_touched else BackpackGrid.rarity_color(BackpackGrid.gear_step(item))})
	return cards


## The menu (tests).
func menu() -> ListMenu:
	return _menu


func _unhandled_input(event: InputEvent) -> void:
	if is_greyed() or _overlay != null:
		return
	var answer := _menu.handle(event)
	if relic_waiting():
		_relic_input(answer, event)
		return
	if answer != &"confirm" or is_settling():
		return
	Sfx.play("menu_confirm")
	if _open:
		leave()
	else:
		open_chest(_menu.index == 1)


## The rotten chest's pick: a Relic card, then (if more than one hero may get it) a hero card;
## cancel goes back from the heroes to the Relics.
func _relic_input(answer: StringName, event: InputEvent) -> void:
	if _giving >= 0:
		if answer == &"cancel":
			Sfx.play("menu_cancel")
			var back := _giving
			_giving = -1
			_device = PlayerRoster.ANY
			_show(true)
			_menu.index = back
		elif answer == &"confirm":
			var slot := int(_menu.items[_menu.index].get("slot", -1)) if _menu.index < _menu.items.size() else -1
			if not take_relic(_giving, slot):
				Sfx.play("locked")
		return
	if answer != &"confirm" or is_settling():
		return
	_device = PlayerRoster.device_of(event)
	var heroes := RelicGift.allowed(give_heroes, run, _device)
	if heroes.size() == 1:
		if not take_relic(_menu.index, heroes[0]):
			_device = PlayerRoster.ANY
			Sfx.play("locked")
		return
	Sfx.play("menu_confirm")
	_giving = _menu.index
	_show(true)
	_menu.index = RelicGift.first_lit(_menu.items)
