class_name LootScreen
extends CanvasLayer
## Spoils after an Elite stop (an elite group or its place's guard) or an act's boss (DESIGN.md 8,
## 8.6, 8.22, 8.24): pick one of a few Relics the run does not have (rare or better while the run has
## them), then the hero who gets it ("Who gets it?", RelicGift: skipped when only one hero may). A
## Relic never found before is kept for good in the collection.
## The Relics sit side by side as cards (card #288): each Relic's own icon, its name in its rarity's
## colour, New (a Relic the book lacks) and a few chips: what it does, its drawback and its stat
## line. No sentence: what a Relic means is in the Glossary.
## Online the pick goes in turns (card #314, DESIGN.md 9.2): on another player's turn the cards are
## greyed and the footer offers nothing to press (`watching`); the turn's player gives it to one of
## their own heroes.

## The item picked and the hero it goes to (null and -1: the party took nothing).
signal chosen(item: GearData, hero: int)

const TITLE_SIZE: int = 72
## The "Who gets it?" line over the hero cards.
const ASK_SIZE: int = 30
## The Relic's icon on its card.
const ICON_PX: float = 96.0
## A sign for each GearData.Category (offensive, defensive, support) on the effect chip.
const CATEGORY_GLYPHS: Array[StringName] = [&"sword", &"shield", &"leaf"]
## A drawback chip's text.
const DRAWBACK_COLOR := Color(1.0, 0.45, 0.4)

var _items: Array[GearData] = []
var _run: RunState
var _menu: ListMenu
var _footer: HintBar
## The footer's hints now (tests read them).
var _footer_now: Array = []
## Online (card #314): another player's turn: the cards are greyed and take no input.
var watching: bool = false
## Online friend whose turn it is (card #314): the pick goes to the host as a request,
## asks.call({"do": "take", "index": i, "hero": slot}).
var asks: Callable = Callable()
## Who may get the Relic (RelicGift.allowed; Main sets it): heroes.call(device) -> hero slots.
var give_heroes: Callable = Callable()
var _taken: bool = false
## The Relic waiting for its hero (the "Who gets it?" step), -1 while choosing a Relic, and the
## pad that picked it (local co-op: that player's heroes get it).
var _giving: int = -1
var _device: int = PlayerRoster.ANY
var _ask: Label


## `text`: kept for the callers (online sends it); the screen shows the cards alone. `run`: to say
## which Relics are new and to give the one taken.
func setup(items: Array[GearData], _text: String = "", run: RunState = null) -> void:
	_items = items
	_run = run
	var column := ListMenu.screen_column(self, "Spoils", TITLE_SIZE)
	_ask = ListMenu.centred_label(RelicGift.ASK, ASK_SIZE, HudStyle.GOLD)
	_ask.visible = false
	column.add_child(_ask)
	_menu = ListMenu.new()
	_menu.horizontal = true
	column.add_child(_menu)
	_footer = ListMenu.screen_footer(self, [])
	_fill()


## The cards and the footer, lit on this machine's turn, greyed on another player's: the Relics, or
## the heroes while one waits for its hero.
func _fill() -> void:
	_ask.visible = _giving >= 0
	if _giving >= 0:
		_menu.set_items(RelicGift.hero_cards(_run, RelicGift.allowed(give_heroes, _run, _device), watching))
		_set_footer([] if watching else [[&"@leftright", "Choose"], [&"menu_confirm", "Give"], [&"menu_cancel", "Back"]])
		return
	var list: Array[Dictionary] = []
	for item: GearData in _items:
		var make := func() -> Control: return RelicIcon.make(item, ICON_PX)
		list.append({"text": item.display_name, "value": new_tag(_run, item), "chips": relic_chips(item),
				"icon_make": make, "enabled": not watching,
				"color": GearData.ROT_TOUCHED_COLOR if item.rot_touched else BackpackGrid.rarity_color(BackpackGrid.gear_step(item))})
	if _items.is_empty():
		list.append({"text": "Nothing left to find", "enabled": not watching})
	# The cursor stays where it was (set_items keeps it in range).
	_menu.set_items(list)
	var entries: Array = []
	if not watching:
		entries = [[&"@leftright", "Choose"], [&"menu_confirm", "Take"]] if not _items.is_empty() \
				else [[&"menu_confirm", "Continue"]]
	_set_footer(entries)


func _set_footer(entries: Array) -> void:
	_footer_now = entries
	_footer.set_entries(entries)


## A Relic's chips: its effect (with its category's sign), its drawback, its stat line.
static func relic_chips(item: GearData) -> Array[Dictionary]:
	var chips: Array[Dictionary] = []
	var effect := GearData.effect_text(item.effect, item.amount)
	if not effect.is_empty():
		chips.append({"glyph": CATEGORY_GLYPHS[clampi(item.category(), 0, CATEGORY_GLYPHS.size() - 1)], "text": effect,
				"color": HudStyle.TEXT})
	if item.has_drawback():
		chips.append({"glyph": &"skull", "text": GearData.drawback_text(item.drawback, item.drawback_amount),
				"color": DRAWBACK_COLOR})
	if item.stat_points > 0:
		chips.append({"glyph": UiGlyph.attribute_glyph(item.stat), "text": "+%d" % item.stat_points, "color": HudStyle.GOLD})
	return chips


## A Relic on offer's tag: "New" when it is not in the Relic book yet (picking it puts it there), ""
## for one the book has. Never in a Fight Rush, which keeps nothing (DESIGN.md 8.21, 8.24).
static func new_tag(run: RunState, item: GearData) -> String:
	if run == null or run is RushState or item == null or run.is_home(item):
		return ""
	return "New"


## The pieces on offer, in the order shown.
func choices() -> Array[GearData]:
	return _items


## The list of cards (tests).
func menu() -> ListMenu:
	return _menu


## The footer's hints now (tests): [[action, text], ...].
func footer_entries() -> Array:
	return _footer_now


## Takes item `index` and gives it to hero `hero` (the bot calls this; the player uses confirm), once.
## `hero` must be one RelicGift.allowed lets have it; with no Relics on offer (Continue) it is not
## needed. False if refused.
func take(index: int, hero: int = -1) -> bool:
	if _taken:
		return false
	var item: GearData = _items[index] if index >= 0 and index < _items.size() else null
	if item != null and not RelicGift.allowed(give_heroes, _run, _device).has(hero):
		return false
	Sfx.play("buff")
	if asks.is_valid():
		asks.call({"do": "take", "index": index, "hero": hero})
		return true
	_taken = true
	chosen.emit(item, hero if item != null else -1)
	return true


## True once a pick was taken here.
func is_taken() -> bool:
	return _taken


## True while a Relic waits for its hero ("Who gets it?").
func is_giving() -> bool:
	return _giving >= 0


## Online (card #314): whose turn it is changed: the cards redraw, lit or greyed (back to the
## Relics: the new turn's player picks afresh).
func set_turn(p_watching: bool, p_asks: Callable = Callable()) -> void:
	watching = p_watching
	asks = p_asks
	_giving = -1
	_device = PlayerRoster.ANY
	if _menu != null:
		_fill()


func _unhandled_input(event: InputEvent) -> void:
	if watching:
		return
	var answer := _menu.handle(event)
	if _giving >= 0:
		if answer == &"cancel":
			Sfx.play("menu_cancel")
			var back := _giving
			_giving = -1
			_device = PlayerRoster.ANY
			_fill()
			_menu.index = back
		elif answer == &"confirm":
			var slot := int(_menu.items[_menu.index].get("slot", -1)) if _menu.index < _menu.items.size() else -1
			if not take(_giving, slot):
				Sfx.play("locked")
		return
	if answer != &"confirm":
		return
	if _menu.index >= _items.size():
		take(_menu.index)
		return
	# Who gets it: straight to the one hero who may, else the hero cards.
	_device = PlayerRoster.device_of(event)
	var heroes := RelicGift.allowed(give_heroes, _run, _device)
	if heroes.size() == 1:
		if not take(_menu.index, heroes[0]):
			_device = PlayerRoster.ANY
		return
	Sfx.play("menu_confirm")
	_giving = _menu.index
	_fill()
	_menu.index = RelicGift.first_lit(_menu.items)

