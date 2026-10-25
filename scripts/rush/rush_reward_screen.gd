class_name RushRewardScreen
extends StopScreen
## The Fight Rush screen between fights (DESIGN.md 8.21, card #305). After a win it is the reward
## pick, titled REWARD: one of the cards side by side (Heal, Train, an item or a Relic; elites and
## bosses offer Relics), as many times as the party has picks. Then it is the ready phase, titled with
## the next fight's number (FIGHT 8): Fight goes on, Party opens the party screen. Chips under the
## title show the fight just won, the best record and any extra picks; the party's HP and levels sit
## under them (no gold). An item is handed out the StopScreen way (a full pack opens the party screen
## over this one); a Relic card first asks who gets it ("Who gets it?", RelicGift, DESIGN.md 8.24;
## skipped when only one hero may). Online, clients watch (`remote`): they can open the party screen
## but take nothing. The screen never touches files or Net. The bot calls take() and fight_now().

## A card was taken (Main logs it; online, only the host's screen takes cards).
signal acted(text: String)
## Fight was chosen in the ready phase (sent once).
signal fight_requested
## Party was chosen (the card or the party button).
signal party_requested
## Host: a pick is done (its gift settled) and the next pick's cards or the ready phase are up:
## online, the next pick is the next player's turn (card #314).
signal pick_done

## The ready phase's cards, in order.
const READY_FIGHT: int = 0
const READY_PARTY: int = 1
## A watching friend's footer (online, `remote`): the party button, the one thing they can do here.
const REMOTE_FOOTER: Array = [[&"party_menu", "Party"]]
## The chips under the title: icon size, text size and the gap between chips.
const CHIP_ICON_PX: float = 36.0
const CHIP_TEXT_SIZE: int = 28
const CHIP_GAP: int = 22
## A card's picture (the art is 24x24, drawn 4x) and an item's fallback size.
const CARD_ICON_SIZE := Vector2i(24, 24)
const ITEM_ICON_SIZE := Vector2i(16, 16)

var _look: StopVisuals
var _map_look: MapVisuals
var _title: Label
var _chips: HBoxContainer
var _menu: ListMenu
var _footer: HintBar
## The footer's hints now (tests read them).
var _footer_now: Array = []
## The best fight reached before this Rush (0: none or not shown).
var _best: int = 0
## The phase and pick drawn last: a new phase or a new pick puts the cursor on its first card that
## can be taken (never on a greyed Heal).
var _drawn_picking: bool = true
var _drawn_pick_no: int = -1
var _fight_sent: bool = false
## A taken item is being handed out (gifts_settled rolls the next pick).
var _waiting_gift: bool = false
## The Relic card waiting for its hero (the "Who gets it?" step; -1: none), and the pad that took it
## (local co-op: that player's heroes get it).
var _giving: int = -1
var _device: int = PlayerRoster.ANY


## Builds the screen for `p_run` in its current phase. `best`: the party size's best fight before
## this Rush (0 leaves the Best chip out).
func setup(p_run: RushState, best: int = 0) -> void:
	run = p_run
	_best = maxi(0, best)
	_look = StopVisuals.load_default()
	_map_look = load(ShopScreen.MAP_VISUALS_PATH) as MapVisuals
	if _map_look == null:
		_map_look = MapVisuals.new()
	var column := ListMenu.screen_column(self, "REWARD", TITLE_SIZE)
	_title = column.get_child(0) as Label
	_chips = HBoxContainer.new()
	_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chips.alignment = BoxContainer.ALIGNMENT_CENTER
	_chips.add_theme_constant_override("separation", CHIP_GAP)
	column.add_child(_chips)
	_add_bar(column)
	_menu = ListMenu.new()
	_menu.horizontal = true
	column.add_child(_menu)
	_footer = ListMenu.screen_footer(self, [])
	gifts_settled.connect(_on_gifts_settled)
	refresh()


## The Rush shown.
func rush() -> RushState:
	return run as RushState


## Redraws everything from the Rush's state (after a pick; online clients after each new state).
func refresh() -> void:
	var r := rush()
	var picking := r.picking()
	if not picking:
		_giving = -1
	if _giving >= 0:
		_title.text = RelicGift.ASK
		_fill_chips(true)
		_refresh_bar()
		var heroes := RelicGift.hero_cards(r, relic_heroes(), is_greyed())
		_menu.set_items(heroes)
		_set_footer(REMOTE_FOOTER if is_greyed() else [[&"@leftright", "Choose"], [&"menu_confirm", "Give"],
				[&"menu_cancel", "Back"]])
		return
	var cards := pick_cards() if picking else ready_cards()
	if picking != _drawn_picking or r.pick_no != _drawn_pick_no:
		_drawn_picking = picking
		_drawn_pick_no = r.pick_no
		_menu.index = _first_enabled(cards)
	_title.text = "REWARD" if picking else "FIGHT %d" % (r.fight + 1)
	_fill_chips(picking)
	_refresh_bar()
	_menu.set_items(cards)
	var confirm := "Take" if picking else "Select"
	var entries: Array = [[&"menu_confirm", confirm], [&"party_menu", "Party"]]
	if _menu.items.size() > 1:
		entries.push_front([&"@leftright", "Choose"])
	# A watching friend takes no card, but the party is everyone's: its button is all they can press.
	_set_footer(REMOTE_FOOTER if is_greyed() else entries)


## The list of cards (tests and the bot).
func menu() -> ListMenu:
	return _menu


## The footer's hints now (tests): [[action, text], ...].
func footer_entries() -> Array:
	return _footer_now


## The title's text now (tests).
func title_text() -> String:
	return _title.text


## The chips under the title now, as their texts (tests).
func chip_texts() -> Array[String]:
	var texts: Array[String] = []
	for chip: Node in _chips.get_children():
		if chip.is_queued_for_deletion():
			continue
		for label: Node in chip.find_children("*", "Label", true, false):
			texts.append((label as Label).text)
	return texts


## True while reward picks are left (the cards are Heal, Train, items and Relics).
func is_picking() -> bool:
	return rush().picking()


## True while a Relic card waits for its hero ("Who gets it?").
func is_giving() -> bool:
	return _giving >= 0


## The heroes who may get a Relic card's Relic here (RelicGift.allowed).
func relic_heroes() -> Array[int]:
	return RelicGift.allowed(give_heroes, run, _device)


## True if card `i` is a Relic card.
func is_relic_card(i: int) -> bool:
	return rush().card_thing(i) is GearData


## Takes card `i` in the pick phase (an enabled card only): its heal or points at once, its Relic to
## hero `hero` (one of relic_heroes(); a Relic card needs one), or its item handed out; once that has
## settled, the next pick's cards or the ready phase. False if nothing was taken.
func take(i: int, hero: int = -1) -> bool:
	var r := rush()
	if (remote and not asks.is_valid()) or _waiting_gift or is_settling() or not r.picking() or r.is_over():
		return false
	# On a friend's turn the host's cards are greyed: the Rush's state says what can be taken.
	if not r.card_enabled(i) or (not is_greyed() and _giving < 0 and not _menu.is_enabled(i)):
		Sfx.play("locked")
		return false
	if is_relic_card(i) and not relic_heroes().has(hero):
		Sfx.play("locked")
		return false
	if _ask({"do": "take", "index": i, "hero": hero}):
		return true
	var got := r.take_card(i, hero)
	if got.is_empty():
		Sfx.play("locked")
		return false
	_giving = -1
	_device = PlayerRoster.ANY
	match String(got.kind):
		RushState.CARD_HEAL:
			Sfx.play("heal")
		RushState.CARD_POINT:
			Sfx.play("level_up")
		RushState.CARD_RELIC:
			Sfx.play("buff")
	acted.emit(_taken_text(got))
	var thing: Resource = got.give
	if not thing is ItemData:
		_after_pick()
		return true
	_waiting_gift = true
	give([thing])
	return true


## Fight (the ready phase only): asks Main for the next fight, once.
func fight_now() -> void:
	if (remote and not asks.is_valid()) or _fight_sent or is_settling() or rush().picking() or run.is_over():
		return
	if _ask({"do": "fight"}):
		return
	_fight_sent = true
	fight_requested.emit()


## Party: asks Main for the party screen (not while a gift is being handed out).
func party_now() -> void:
	if is_settling() or _waiting_gift:
		return
	party_requested.emit()


## The pick phase's cards: {text, enabled, icon or icon_make, value, color, chips}, one per card on
## offer and in its order (a card's index is its offer index).
func pick_cards() -> Array[Dictionary]:
	var r := rush()
	var gift := _look.chip_gift_color
	var cards: Array[Dictionary] = []
	for i: int in r.offer.size():
		var card: Dictionary = r.offer[i]
		var enabled := not is_greyed() and r.card_enabled(i)
		match String(card.get("kind", "")):
			RushState.CARD_HEAL:
				cards.append({"text": "Heal", "enabled": enabled, "icon": _icon(_look.heal_icon_path),
						"chips": _heal_chips(int(card.get("amount", 0)))})
			RushState.CARD_POINT:
				cards.append({"text": "Train", "enabled": enabled, "icon": _icon(_look.train_icon_path),
						"chips": [StopScreen.chip_entry(_look, "up", points_text(int(card.get("amount", 0))), gift)]})
			RushState.CARD_ITEM:
				var item := r.card_thing(i) as ItemData
				cards.append(_item_card(item, enabled) if item != null else _unknown_card())
			RushState.CARD_RELIC:
				var gear := r.card_thing(i) as GearData
				cards.append(_relic_card(gear, enabled) if gear != null else _unknown_card())
			_:
				cards.append(_unknown_card())
	return cards


## The ready phase's cards: Fight (with Elite or Boss when the next fight is one) and Party (with the
## points left to spend).
func ready_cards() -> Array[Dictionary]:
	var r := rush()
	var fight_chips: Array[Dictionary] = []
	match r.kind_of(r.fight + 1):
		RushState.Kind.ELITE:
			fight_chips.append(StopScreen.chip_entry(_look, "fight", "Elite", _look.chip_risk_color))
		RushState.Kind.BOSS:
			fight_chips.append(StopScreen.chip_entry(_look, "boss", "Boss", _look.chip_cost_color))
	var party_chips: Array[Dictionary] = []
	var unspent := r.unspent_points()
	if unspent > 0:
		party_chips.append(StopScreen.chip_entry(_look, "up", points_text(unspent), _look.chip_gift_color))
	# Party stays lit for a watching friend (the cursor starts on it): the party is everyone's.
	var cards: Array[Dictionary] = [
		{"text": "Fight", "enabled": not is_greyed(), "icon": _icon(_look.fight_icon_path), "chips": fight_chips},
		{"text": "Party", "enabled": true, "icon": _icon(_look.party_icon_path), "chips": party_chips},
	]
	return cards


## "+1 point", "+3 points".
static func points_text(points: int) -> String:
	return "+%d point%s" % [points, "" if points == 1 else "s"]


## A rarity's word with a capital ("Common", "Rot-touched").
static func rarity_word(step: int) -> String:
	var word := BackpackGrid.rarity_name(step)
	return word.left(1).to_upper() + word.substr(1)


# --- drawing ------------------------------------------------------------------------------------

## Pick phase: the fight just won, the best record, the extra picks; ready phase: the best record.
func _fill_chips(picking: bool) -> void:
	for chip: Node in _chips.get_children():
		chip.queue_free()
	var r := rush()
	var shown: Array[Array] = []
	if picking:
		shown.append([_look.chip_fight_path, "Fight %d" % r.fight, HudStyle.TEXT])
	if _best > 0:
		shown.append([&"star", "Best %d" % _best, HudStyle.GOLD])
	if picking and r.picks_left > 1:
		var extra := r.picks_left - 1
		shown.append([_look.chip_up_path, "+%d pick%s" % [extra, "" if extra == 1 else "s"], _look.chip_gift_color])
	for part: Array in shown:
		_chips.add_child(MapScreen.icon_chip(part[0], String(part[1]), part[2] as Color, CHIP_ICON_PX, CHIP_TEXT_SIZE))
	_chips.visible = not shown.is_empty()


## What Heal gives: everyone's percent, and by name any hero whose Relics change it (copied from the
## campfire's Rest chips).
func _heal_chips(amount: int) -> Array[Dictionary]:
	var r := rush()
	var chips: Array[Dictionary] = [StopScreen.chip_entry(_look, "heal", "+%d%% HP" % amount, _look.chip_gift_color)]
	for slot: int in r.party_size():
		var percent := r.card_heal_percent_of(slot)
		if percent != amount:
			chips.append(StopScreen.chip_entry(_look, "heal", "%s +%d%%" % [r.data.party[slot].display_name, percent],
					HudStyle.TEXT_DIM))
	return chips


## An item's card: its icon and name in its rarity's colour, a rarity chip, then what it does (the
## shop's chips).
func _item_card(item: ItemData, enabled: bool) -> Dictionary:
	var step := int(item.rarity)
	var color := BackpackGrid.rarity_color(step)
	var chips: Array[Dictionary] = [StopScreen.chip_entry(_look, "item", rarity_word(step), color)]
	for part: Array in ShopScreen.item_chips(item, _map_look, ""):
		chips.append(_chip_from(part))
	return {"text": item.display_name, "enabled": enabled, "color": color,
			"icon": AssetLoader.texture(item.icon_path, ITEM_ICON_SIZE), "chips": chips}


## A Relic's card, as on the spoils screen: its own icon, its name in its rarity's colour, New (or
## Home), a rarity chip and what it does.
func _relic_card(gear: GearData, enabled: bool) -> Dictionary:
	var r := rush()
	var step := BackpackGrid.gear_step(gear)
	var color := GearData.ROT_TOUCHED_COLOR if gear.rot_touched else BackpackGrid.rarity_color(step)
	var make := func() -> Control: return RelicIcon.make(gear, LootScreen.ICON_PX)
	var chips: Array[Dictionary] = [StopScreen.chip_entry(_look, "relic", rarity_word(step), color)]
	chips.append_array(LootScreen.relic_chips(gear))
	return {"text": gear.display_name, "enabled": enabled, "color": color, "icon_make": make, "chips": chips,
			"value": "Home" if r.is_home(gear) else "New"}


## A card this build cannot show (bad data): greyed, so the cards keep their offer order.
static func _unknown_card() -> Dictionary:
	return {"text": "?", "enabled": false}


## A shop chip ([icon: path, glyph or texture, text, colour]) as a ListMenu chip.
static func _chip_from(part: Array) -> Dictionary:
	var entry := {"text": String(part[1]), "color": part[2] as Color}
	var icon: Variant = part[0]
	if icon is StringName:
		entry["glyph"] = icon
	elif icon is Texture2D:
		entry["icon"] = icon
	elif icon is String and not String(icon).is_empty():
		entry["icon"] = AssetLoader.texture(String(icon), Vector2i(12, 12))
	return entry


## The first card that can be taken (0 when none can).
static func _first_enabled(cards: Array[Dictionary]) -> int:
	for i: int in cards.size():
		if bool(cards[i].get("enabled", true)):
			return i
	return 0


func _icon(path: String) -> Texture2D:
	return AssetLoader.texture(path, CARD_ICON_SIZE)


func _set_footer(entries: Array) -> void:
	if entries == _footer_now and _footer.get_child_count() == entries.size():
		return
	_footer_now = entries
	_footer.set_entries(entries)


# --- picking ------------------------------------------------------------------------------------

func _on_gifts_settled() -> void:
	if not _waiting_gift:
		return
	_waiting_gift = false
	_after_pick()


## A pick is done (its gift settled): the next pick's cards, or the ready phase.
func _after_pick() -> void:
	rush().next_offer()
	refresh()
	pick_done.emit()


## Online (card #314): the turn changed: the cards redraw, lit or greyed (a Relic waiting for its
## hero goes back to the cards).
func _turn_changed() -> void:
	_giving = -1
	_device = PlayerRoster.ANY
	refresh()


## What a taken card did, in a few words (Main logs it).
func _taken_text(got: Dictionary) -> String:
	var r := rush()
	match String(got.kind):
		RushState.CARD_HEAL:
			var parts := PackedStringArray()
			var healed: Array = got.get("healed", [])
			for slot: int in mini(healed.size(), r.party_size()):
				parts.append("%s +%d" % [r.data.party[slot].display_name, int(healed[slot])])
			return "Heal: " + ", ".join(parts)
		RushState.CARD_POINT:
			return "Train: %s each" % points_text(int(got.get("points", 0)))
	var found: Dictionary = got.get("relic", {})
	if found.get("item") is GearData:
		var hero := int(got.get("hero", -1))
		var who := r.data.party[hero].display_name if hero >= 0 and hero < r.party_size() else "?"
		return "Relic: %s to %s" % [(found.item as GearData).display_name, who]
	var thing: Resource = got.get("give")
	var name := String(thing.get("display_name")) if thing != null else "?"
	return "Item: %s" % name


func _unhandled_input(event: InputEvent) -> void:
	if _overlay != null or _waiting_gift:
		return
	if event.is_action_pressed(&"party_menu", false, true):
		if is_inside_tree():
			get_viewport().set_input_as_handled()
		Sfx.play("menu_confirm")
		party_now()
		return
	if is_greyed():
		# A watching friend: Confirm on the ready phase's Party card (the cursor's only lit card) opens
		# the party screen; the cursor does not move and nothing is taken.
		if event.is_action_pressed(&"menu_confirm", false, true) and not rush().picking() \
				and _menu.index == READY_PARTY:
			if is_inside_tree():
				get_viewport().set_input_as_handled()
			Sfx.play("menu_confirm")
			party_now()
		return
	var answer := _menu.handle(event)
	if _giving >= 0:
		_give_input(answer)
		return
	if answer != &"confirm" or is_settling():
		return
	# A greyed card (Heal with everyone at full HP) answers confirm too: refuse it here.
	if not _menu.is_enabled(_menu.index):
		Sfx.play("locked")
		return
	Sfx.play("menu_confirm")
	if rush().picking() and is_relic_card(_menu.index):
		# Who gets it: straight to the one hero who may, else the hero cards.
		_device = PlayerRoster.device_of(event)
		var heroes := relic_heroes()
		if heroes.size() == 1:
			if not take(_menu.index, heroes[0]):
				_device = PlayerRoster.ANY
			return
		_giving = _menu.index
		refresh()
		_menu.index = RelicGift.first_lit(_menu.items)
	elif rush().picking():
		take(_menu.index)
	elif _menu.index == READY_FIGHT:
		fight_now()
	elif _menu.index == READY_PARTY:
		party_now()


## The "Who gets it?" step: a hero card gives the waiting Relic card's Relic; cancel goes back to the
## cards.
func _give_input(answer: StringName) -> void:
	if answer == &"cancel":
		Sfx.play("menu_cancel")
		var back := _giving
		_giving = -1
		_device = PlayerRoster.ANY
		refresh()
		_menu.index = back
	elif answer == &"confirm" and not is_settling():
		var slot := int(_menu.items[_menu.index].get("slot", -1)) if _menu.index < _menu.items.size() else -1
		if not take(_giving, slot):
			Sfx.play("locked")
