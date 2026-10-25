class_name RunPartyBar
extends HBoxContainer
## The run's status strip (DESIGN.md 8): gold, the party's curses (card #332: each its picture and
## name, in the rot green; only while there are any), then every character's level and HP, with a
## gold "+N" while they have attribute points to spend (DESIGN.md 8.2).
## Shown on the map, in shops and at the run's other stops. refresh() after anything changes.

const NAME_SIZE: int = 26
const HP_SIZE: int = 22
const GOLD_SIZE: int = 32
const BAR_WIDTH: float = 200.0
const BAR_HEIGHT: float = 14.0
## HP at or under this percent shows in the low colour.
const LOW_HP_PERCENT: int = 30
const GOLD_TEXT := "Gold  %d"
## A curse chip's picture and words.
const CURSE_ICON_PX: float = 32.0
const CURSE_SIZE: int = 22

var _gold: Label
## The curses' panel and its chips (hidden with no curse).
var _curse_panel: PanelContainer
var _curse_row: HBoxContainer
## The curse ids the chips show now (rebuilt only when they change).
var _curses_shown: Array[String] = []
## Per slot: {hp: Label, level: Label, points: Label, bar: ProgressBar}.
var _slots: Array[Dictionary] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 18)


func setup(run: RunState) -> void:
	var gold_panel := _panel()
	_gold = HudStyle.make_label("", GOLD_SIZE, HudStyle.GOLD)
	gold_panel.add_child(_gold)
	_curse_panel = _panel()
	_curse_row = HBoxContainer.new()
	_curse_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_curse_row.add_theme_constant_override("separation", 14)
	_curse_panel.add_child(_curse_row)
	_curse_panel.visible = false
	for slot: int in run.party_size():
		var c := run.data.party[slot]
		var panel := _panel()
		var box := VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_constant_override("separation", 4)
		panel.add_child(box)
		var top := HBoxContainer.new()
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_theme_constant_override("separation", 14)
		box.add_child(top)
		top.add_child(HudStyle.make_label(c.display_name, NAME_SIZE, c.color.lightened(0.25)))
		var level := HudStyle.make_label("", HP_SIZE, HudStyle.TEXT_DIM)
		top.add_child(level)
		var points := HudStyle.make_label("", HP_SIZE, HudStyle.GOLD)
		top.add_child(points)
		var hp := HudStyle.make_label("", HP_SIZE)
		top.add_child(hp)
		var bar := HudStyle.bar(HudStyle.HP_FILL, BAR_HEIGHT)
		bar.custom_minimum_size.x = BAR_WIDTH
		box.add_child(bar)
		_slots.append({"hp": hp, "level": level, "points": points, "bar": bar})
	refresh(run)


func refresh(run: RunState) -> void:
	if _gold != null:
		_gold.text = GOLD_TEXT % run.gold
	if _curse_panel != null and _curses_shown != run.curses:
		_show_curses(run)
	for slot: int in mini(_slots.size(), run.party_size()):
		var max_hp := run.max_hp(slot)
		var bar := _slots[slot].bar as ProgressBar
		bar.max_value = max_hp
		bar.value = run.hp[slot]
		HudStyle.set_bar_color(bar, HudStyle.HP_LOW if run.hp[slot] * 100 <= max_hp * LOW_HP_PERCENT else HudStyle.HP_FILL)
		(_slots[slot].hp as Label).text = "%d / %d" % [run.hp[slot], max_hp]
		(_slots[slot].level as Label).text = "Lv %d" % run.levels[slot]
		var free := run.free_points(slot)
		(_slots[slot].points as Label).text = "+%d" % free if free > 0 else ""


## The curse chips (curse_chips) in their panel.
func _show_curses(run: RunState) -> void:
	_curses_shown = run.curses.duplicate()
	for child: Node in _curse_row.get_children():
		_curse_row.remove_child(child)
		child.queue_free()
	for chip: Array in curse_chips(run):
		_curse_row.add_child(MapScreen.icon_chip(chip[0], String(chip[1]), chip[2] as Color, CURSE_ICON_PX, CURSE_SIZE,
				false))
	_curse_panel.visible = not run.curses.is_empty()


## The party's curses as chips, in the order first taken: [[picture path, name, colour]], one chip per
## kind of curse with "x2" and up for more of the same (so the strip stays one short row). Tests
## read them.
static func curse_chips(run: RunState) -> Array:
	var chips: Array = []
	var counts := {}
	var order: Array[ItemData] = []
	for curse: ItemData in run.curse_items():
		if not counts.has(curse.id):
			order.append(curse)
		counts[curse.id] = int(counts.get(curse.id, 0)) + 1
	for curse: ItemData in order:
		var count := int(counts[curse.id])
		var text := curse.display_name if count == 1 else "%s x%d" % [curse.display_name, count]
		chips.append([curse.icon_path, text, BackpackGrid.ROTTEN_COLOR])
	return chips


func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", HudStyle.panel())
	add_child(panel)
	return panel
