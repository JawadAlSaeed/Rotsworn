class_name LootScreen
extends CanvasLayer
## Spoils after a Guard stop's guard, an elite or an act's boss (DESIGN.md 8, 8.6, 8.22): pick one of a few
## Relics (8.17) that are not in the run yet or that a copy would still level up this run (rare or
## better while the run has them; levels last one run, 8.19). A Relic never found before is kept for
## good; the party screen comes next to put it on someone.
## The Relics sit side by side as cards (card #288): each Relic's own icon, its name in its rarity's
## colour, New (or Home, or "Lv 1 > 2" for a copy) and a few chips: what it does, its drawback and
## its stat line. No sentence: what a Relic means is in the Glossary.
## Online the pick goes in turns (card #314, DESIGN.md 9.2): on another player's turn the cards are
## greyed and the footer offers nothing to press (`watching`).

## The item picked (null: the party took nothing).
signal chosen(item: GearData)

const TITLE_SIZE: int = 72
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
## asks.call({"do": "take", "index": i}).
var asks: Callable = Callable()
var _taken: bool = false


## `text`: kept for the callers (online sends it); the screen shows the cards alone. `run`: to say
## which Relics are new and which a copy would level up.
func setup(items: Array[GearData], _text: String = "", run: RunState = null) -> void:
	_items = items
	_run = run
	var column := ListMenu.screen_column(self, "Spoils", TITLE_SIZE)
	_menu = ListMenu.new()
	_menu.horizontal = not items.is_empty()
	column.add_child(_menu)
	_footer = ListMenu.screen_footer(self, [])
	_fill()


## The cards and the footer, lit on this machine's turn, greyed on another player's.
func _fill() -> void:
	var list: Array[Dictionary] = []
	for item: GearData in _items:
		var level := _run.relic_level(item) if _run != null else 0
		var home := _run != null and _run.is_home(item)
		var tag := ("Home" if home else "New") if level <= 0 else "Lv %d > %d" % [level, level + 1]
		var top := _run.tuning.relic_max_level if _run != null else 0
		# Its pips show the level it would have once taken.
		var make := func() -> Control: return RelicIcon.make(item, ICON_PX, true, level + 1, top)
		list.append({"text": item.display_name, "value": tag, "chips": relic_chips(item, level + 1), "icon_make": make,
				"enabled": not watching,
				"color": GearData.ROT_TOUCHED_COLOR if item.rot_touched else BackpackGrid.rarity_color(BackpackGrid.gear_step(item))})
	if _items.is_empty():
		list.append({"text": "Nothing left to find", "enabled": not watching})
	# The cursor stays where it was (set_items keeps it in range).
	_menu.set_items(list)
	var entries: Array = []
	if not watching:
		entries = [[&"@leftright", "Choose"], [&"menu_confirm", "Take"]] if not _items.is_empty() \
				else [[&"menu_confirm", "Continue"]]
	_footer_now = entries
	_footer.set_entries(entries)


## A Relic's chips at `level`: its effect (with its category's sign), its drawback, its stat line.
static func relic_chips(item: GearData, level: int) -> Array[Dictionary]:
	var chips: Array[Dictionary] = []
	var effect := GearData.effect_text(item.effect, item.amount)
	if not effect.is_empty():
		chips.append({"glyph": CATEGORY_GLYPHS[clampi(item.category(), 0, CATEGORY_GLYPHS.size() - 1)], "text": effect,
				"color": HudStyle.TEXT})
	if item.has_drawback():
		chips.append({"glyph": &"skull", "text": GearData.drawback_text(item.drawback, item.drawback_amount),
				"color": DRAWBACK_COLOR})
	var points := item.stat_points_at(maxi(1, level))
	if points > 0:
		chips.append({"glyph": UiGlyph.attribute_glyph(item.stat), "text": "+%d" % points, "color": HudStyle.GOLD})
	return chips


## The pieces on offer, in the order shown.
func choices() -> Array[GearData]:
	return _items


## The list of cards (tests).
func menu() -> ListMenu:
	return _menu


## The footer's hints now (tests): [[action, text], ...].
func footer_entries() -> Array:
	return _footer_now


## Takes item `index` (the bot calls this; the player uses confirm), once.
func take(index: int) -> void:
	if _taken:
		return
	Sfx.play("buff")
	if asks.is_valid():
		asks.call({"do": "take", "index": index})
		return
	_taken = true
	chosen.emit(_items[index] if index >= 0 and index < _items.size() else null)


## True once a pick was taken here.
func is_taken() -> bool:
	return _taken


## Online (card #314): whose turn it is changed: the cards redraw, lit or greyed.
func set_turn(p_watching: bool, p_asks: Callable = Callable()) -> void:
	watching = p_watching
	asks = p_asks
	if _menu != null:
		_fill()


func _unhandled_input(event: InputEvent) -> void:
	if watching:
		return
	if _menu.handle(event) == &"confirm":
		take(_menu.index)
