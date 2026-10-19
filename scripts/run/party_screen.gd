class_name PartyScreen
extends CanvasLayer
## The Y screen (DESIGN.md 8.18, card #270), opened with Tab / Y from the map or a zone, after loot,
## from a shop and from treasure and event stops. Four tabs, one job each, switched with LB / RB
## (Z / C): Relics (every hero's Relic slots next to the team's shared Relic bag, RelicsTab), Bag
## (the backpack, BagTab), Hero (attributes, stats and the Echoes, HeroTab) and Skills (the skill
## tree, SkillsTab, when a hero has one). Around the tabs this screen draws the tab bar with a gold
## badge for points waiting and the gold, one info strip along the bottom that never moves (the
## thing under the cursor: its icon, name, a few chips and one line), toasts (an icon and a word or
## two) instead of sentences, and at most four button hints.
## The screen can open with something new in hand: a Relic (loot) opens the Relics tab, an item
## (a find that did not fit) the Bag tab. Online, a client's changes go to the host as RunState ops
## (op_requested); the host's run state comes back and refresh() redraws.

signal done
## A new item in hand was left behind (it is not in the backpack).
signal left_behind(item: ItemData)
## An item was sold here (the shop saves the run then).
signal sold
## Online client: a change for the host to make (RunState.apply_op data).
signal op_requested(op: Dictionary)

enum Tab { RELICS, BAG, HERO, SKILLS }
const TAB_NAMES: Array[String] = ["Relics", "Bag", "Hero", "Skills"]
const TAB_GLYPHS: Array[StringName] = [&"gem", &"bag", &"person", &"branch"]
const VISUALS_PATH := "res://data/presentation/combat_visuals.tres"

const TAB_SIZE: int = 30
const TAB_GLYPH_PX: float = 30.0
const TAB_TOP: float = 22.0
const TAB_HEIGHT: float = 58.0
const PAGE_TOP: float = 110.0
const GOLD_SIZE: int = 32
const STRIP_RECT := Rect2(70.0, 868.0, 1780.0, 124.0)
const STRIP_ICON_PX: float = 92.0
const STRIP_TITLE_SIZE: int = 32
const STRIP_LINE_SIZE: int = 23
const CHIP_SIZE: int = 22
const BAR_SEGMENT := Vector2(34.0, 10.0)
const TOAST_TOP: float = 92.0
const TOAST_ICON_PX: float = 40.0
const TOAST_SIZE: int = 28

## The tab the screen opens on next time (the last one used), unless something in hand picks one.
static var _last_tab: int = Tab.RELICS

## Online client: changes are asked of the host instead of made here.
var remote: bool = false
## Close by itself once the new thing in hand is placed, worn or left (shop and zone finds).
var close_when_settled: bool = false
## Opened from a shop: items can be sold (DESIGN.md 8.1); the Bag tab opens first.
var shop_mode: bool = false
var _run: RunState
var _visuals: CombatVisuals
## Tab -> PartyTab (Skills is missing when no hero has a skill tree).
var _tabs: Dictionary = {}
## The tabs in bar order.
var _order: Array[int] = []
var _tab: int = Tab.RELICS
var _relics: RelicsTab
var _bag: BagTab
var _hero: HeroTab
var _skills: SkillsTab
## The Echoes page while it is open over this screen (DESIGN.md 8.17).
var _echoes: EchoesScreen
## Everything placed on the 1920 x 1080 canvas, kept centred when the window is wider or taller
## (aspect expand); the backdrop and the footer stay full width.
var _frame: Control
var _bar_box: HBoxContainer
## Each tab's plate in the bar (for the mouse), by Tab.
var _tab_plates: Dictionary = {}
var _gold: Label
var _strip: Panel
var _strip_icon: Control
var _strip_title: Label
var _strip_chips: HBoxContainer
var _strip_line: Label
var _strip_bar: HBoxContainer
var _toast: PanelContainer
var _toast_tween: Tween
var _hint: HintBar


## `note`: a toast at the start (for example what was just found). `held`: something new in hand,
## {gear: GearData} or {item: ItemData}.
func setup(run: RunState, note: String = "", held: Dictionary = {}) -> void:
	_run = run
	_visuals = load(VISUALS_PATH) as CombatVisuals
	if _visuals == null:
		_visuals = CombatVisuals.new()
	add_child(MenuBackdrop.new())
	_frame = Control.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.set_anchors_preset(Control.PRESET_CENTER)
	_frame.offset_left = -960.0
	_frame.offset_top = -540.0
	_frame.offset_right = 960.0
	_frame.offset_bottom = 540.0
	add_child(_frame)
	_build_tabs()
	_build_bar()
	_build_strip()
	_build_toast()
	_hint = ListMenu.screen_footer(self, [])
	var icon: Variant = held.get("icon")
	if held.get("gear") is GearData:
		_relics.hold_new(held.gear as GearData)
		_tab = Tab.RELICS
		icon = held.gear
	elif held.get("item") is ItemData:
		_bag.hold_new(held.item as ItemData, bool(held.get("refund", false)))
		_tab = Tab.BAG
		icon = held.item
	elif shop_mode:
		_tab = Tab.BAG
	else:
		_tab = _last_tab if _tabs.has(_last_tab) else Tab.RELICS
	_show_tab(_tab, false)
	if not note.is_empty():
		show_toast(note, icon)


## The run changed (online, another player's change arrived): redraw every tab.
func refresh() -> void:
	for tab: PartyTab in _tabs.values():
		tab.refresh()
	if _echoes != null:
		_echoes.refresh()
	_redraw_chrome()


## Something new is in hand (loot, a find, a swap).
func holding_new() -> bool:
	return _relics.holding_new() or _bag.holding_new()


## The bot (and tests): settles what is in hand the simple way (RelicsTab / BagTab auto_settle).
func auto_settle() -> void:
	_relics.auto_settle()
	_bag.auto_settle()
	_redraw_chrome()


func close() -> void:
	done.emit()


## The tab on screen (a Tab).
func current_tab() -> int:
	return _tab


## The footer's hint entries now (tests).
func hint_entries() -> Array:
	return _hint._entries if _hint != null else []


## The tab object for `tab` (null if this run has none; tests and Main's dev screens).
func tab_node(tab: int) -> PartyTab:
	return _tabs.get(tab) as PartyTab


## Shows tab `tab` (not while the current one is busy). False if it cannot.
func select_tab(tab: int) -> bool:
	if not _tabs.has(tab) or (tab != _tab and (_tabs[_tab] as PartyTab).busy()):
		return false
	_show_tab(tab)
	return true


## The Hero tab (attributes) for the hero the cursor is on (T / LT in older builds).
func open_attributes() -> void:
	var hero := (_tabs[_tab] as PartyTab).hero
	if select_tab(Tab.HERO):
		_hero.set_hero(hero)
		_redraw_chrome()
	else:
		Sfx.play("locked")


## The Skills tab for the hero the cursor is on.
func open_skills() -> void:
	var hero := (_tabs[_tab] as PartyTab).hero
	if select_tab(Tab.SKILLS):
		_skills.set_hero(hero)
		_redraw_chrome()
	else:
		Sfx.play("locked")


## The Echoes page over this screen (DESIGN.md 8.17), for hero `hero` (-1: the one in focus).
func open_echoes(hero: int = -1) -> void:
	if (_tabs[_tab] as PartyTab).busy() and _tab != Tab.HERO:
		Sfx.play("locked")
		return
	var shown := (_tabs[_tab] as PartyTab).hero if hero < 0 else hero
	_echoes = EchoesScreen.new()
	_echoes.name = "Echoes"
	_echoes.layer = layer + 1
	_echoes.remote = remote
	add_child(_echoes)
	_echoes.setup(_run, clampi(shown, 0, _run.party_size() - 1))
	_echoes.op_requested.connect(func(op: Dictionary) -> void: op_requested.emit(op))
	_echoes.done.connect(func() -> void:
		_echoes.queue_free()
		_echoes = null
		refresh())
	Sfx.play("menu_confirm")


## The Relics tab, on hero `hero` (-1: the one in focus); `gear_slot` >= 0 puts the cursor on that
## slot and opens the bag to pick a Relic for it.
func open_relics(hero: int = -1, gear_slot: int = -1) -> void:
	var focus := (_tabs[_tab] as PartyTab).hero if hero < 0 else hero
	if not select_tab(Tab.RELICS):
		Sfx.play("locked")
		return
	_relics.focus_slot(focus, maxi(0, gear_slot), gear_slot >= 0)
	_redraw_chrome()


## A toast under the tab bar: `text` (a word or two) and an optional icon (GearData, ItemData,
## Texture2D or a UiGlyph kind), shown for party_toast_s, then faded.
func show_toast(text: String, icon: Variant = null) -> void:
	_clear(_toast.get_child(0))
	var line := _toast.get_child(0) as HBoxContainer
	var picture := _icon_for(icon, TOAST_ICON_PX)
	if picture != null:
		line.add_child(picture)
	line.add_child(HudStyle.make_title(text, TOAST_SIZE, HudStyle.TEXT))
	_toast.visible = true
	_toast.modulate.a = 1.0
	if _toast_tween != null:
		_toast_tween.kill()
	if not is_inside_tree():
		# Set up before it joins the tree (Main's party screen): the fade starts in _ready.
		return
	_fade_toast()


func _ready() -> void:
	if _toast != null and _toast.visible:
		_fade_toast()


func _fade_toast() -> void:
	_toast_tween = create_tween()
	_toast_tween.tween_interval(_visuals.party_toast_s)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, _visuals.party_toast_fade_s)
	_toast_tween.tween_callback(func() -> void: _toast.visible = false)


# --- building -----------------------------------------------------------------------------------

func _build_tabs() -> void:
	var page := Control.new()
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.position = Vector2(0.0, PAGE_TOP)
	page.size = PartyTab.PAGE_SIZE
	_frame.add_child(page)
	_relics = RelicsTab.new()
	_bag = BagTab.new()
	_bag.shop_mode = shop_mode
	_hero = HeroTab.new()
	_tabs = {Tab.RELICS: _relics, Tab.BAG: _bag, Tab.HERO: _hero}
	_order = [Tab.RELICS, Tab.BAG, Tab.HERO]
	if _any_tree():
		_skills = SkillsTab.new()
		_tabs[Tab.SKILLS] = _skills
		_order.append(Tab.SKILLS)
	for tab: int in _order:
		var node := _tabs[tab] as PartyTab
		node.name = TAB_NAMES[tab]
		node.visible = false
		page.add_child(node)
		node.setup(_run, remote)
		node.changed.connect(_redraw_chrome)
		node.op_requested.connect(func(op: Dictionary) -> void: op_requested.emit(op))
		node.toast.connect(show_toast)
	_relics.settled.connect(_settled)
	_bag.settled.connect(_settled)
	_bag.left_behind.connect(func(item: ItemData) -> void: left_behind.emit(item))
	_bag.sold.connect(func() -> void: sold.emit())
	_hero.echoes_requested.connect(open_echoes)


func _build_bar() -> void:
	# Full width and centred by the container itself, so it stays centred however it is built
	# (the screen may be set up before it joins the tree, when nothing has a size yet).
	_bar_box = HBoxContainer.new()
	_bar_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_bar_box.add_theme_constant_override("separation", 14)
	_bar_box.position = Vector2(0.0, TAB_TOP)
	_bar_box.size = Vector2(1920.0, TAB_HEIGHT)
	_frame.add_child(_bar_box)
	var gold_line := HBoxContainer.new()
	gold_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gold_line.add_theme_constant_override("separation", 10)
	gold_line.position = Vector2(1680.0, TAB_TOP + 10.0)
	_frame.add_child(gold_line)
	gold_line.add_child(UiGlyph.make(&"coin", 32.0, HudStyle.GOLD))
	_gold = HudStyle.make_number("", GOLD_SIZE, HudStyle.GOLD)
	gold_line.add_child(_gold)


func _build_strip() -> void:
	_strip = Panel.new()
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.position = STRIP_RECT.position
	_strip.size = STRIP_RECT.size
	_strip.add_theme_stylebox_override("panel", HudStyle.slant(HudStyle.INK, HudStyle.EDGE_DIM, 2, 10, STRIP_RECT.size.y,
			HudStyle.SLANT * 0.08))
	_frame.add_child(_strip)
	_strip_icon = Control.new()
	_strip_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip_icon.position = Vector2(34.0, (STRIP_RECT.size.y - STRIP_ICON_PX) * 0.5)
	_strip_icon.size = Vector2(STRIP_ICON_PX, STRIP_ICON_PX)
	_strip.add_child(_strip_icon)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 18)
	head.position = Vector2(150.0, 14.0)
	_strip.add_child(head)
	_strip_title = HudStyle.make_title("", STRIP_TITLE_SIZE, HudStyle.TEXT)
	head.add_child(_strip_title)
	_strip_chips = HBoxContainer.new()
	_strip_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip_chips.add_theme_constant_override("separation", 10)
	_strip_chips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_strip_chips)
	# Up to two lines, so a skill's whole text (perfect-press bonus included) fits.
	_strip_line = HudStyle.make_label("", STRIP_LINE_SIZE, HudStyle.TEXT_DIM)
	_strip_line.position = Vector2(150.0, 60.0)
	_strip_line.size = Vector2(STRIP_RECT.size.x - 520.0, 58.0)
	_strip_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_strip_line.max_lines_visible = 2
	_strip_line.clip_text = true
	_strip_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_strip.add_child(_strip_line)
	_strip_bar = HBoxContainer.new()
	_strip_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip_bar.add_theme_constant_override("separation", 6)
	_strip_bar.position = Vector2(STRIP_RECT.size.x - 330.0, 48.0)
	_strip.add_child(_strip_bar)


func _build_toast() -> void:
	_toast = PanelContainer.new()
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.add_theme_stylebox_override("panel", HudStyle.slant(HudStyle.INK_SOLID, HudStyle.GOLD, 2, 10, 60.0))
	_toast.visible = false
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 14)
	_toast.add_child(line)
	# A full-width row that centres the toast (works before the screen is in the tree).
	var lane := HBoxContainer.new()
	lane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lane.alignment = BoxContainer.ALIGNMENT_CENTER
	lane.position = Vector2(0.0, TOAST_TOP)
	lane.size = Vector2(1920.0, 60.0)
	lane.add_child(_toast)
	_frame.add_child(lane)


# --- input --------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _echoes != null:
		return
	var tab := _tabs[_tab] as PartyTab
	if not tab.busy():
		if _pressed(event, &"item_turn_left") or _pressed(event, &"item_turn_right"):
			_handled()
			_step_tab(-1 if event.is_action(&"item_turn_left") else 1)
			return
		if MenuMouse.is_click(event):
			for t: int in _tab_plates:
				var plate := _tab_plates[t] as Control
				if Rect2(Vector2.ZERO, plate.size).has_point(MenuMouse.local_point(plate, (event as InputEventMouse).position)):
					_handled()
					if t != _tab:
						Sfx.play("menu_move")
						_show_tab(t)
					return
	if tab.handle_input(event):
		_handled()
		return
	if not tab.busy() and (_pressed(event, &"menu_cancel") or _pressed(event, &"party_menu") or MenuMouse.is_back(event)):
		_handled()
		Sfx.play("menu_cancel")
		close()


func _step_tab(step: int) -> void:
	var at := _order.find(_tab)
	_show_tab(_order[wrapi(at + step, 0, _order.size())])
	Sfx.play("menu_move")


func _show_tab(tab: int, remember: bool = true) -> void:
	var from := _tabs.get(_tab) as PartyTab
	var to := _tabs[tab] as PartyTab
	if from != null and from != to:
		# The hero in focus follows from tab to tab.
		to.hero = from.hero
	_tab = tab
	if remember:
		_last_tab = tab
	for t: int in _tabs:
		(_tabs[t] as PartyTab).visible = t == tab
	to.shown()
	_redraw_chrome()


## The new thing in hand is dealt with.
func _settled() -> void:
	_redraw_chrome()
	if close_when_settled:
		close()


# --- drawing ------------------------------------------------------------------------------------

## Redraws what is around the tab: the bar (badges), the gold, the strip and the hints.
func _redraw_chrome() -> void:
	if _bar_box == null:
		return
	_redraw_bar()
	_gold.text = str(_run.gold)
	_redraw_strip((_tabs[_tab] as PartyTab).info())
	_redraw_hint()


func _redraw_bar() -> void:
	_clear(_bar_box)
	_tab_plates.clear()
	_bar_box.add_child(HintBar.entry_row(&"item_turn_left", "", TAB_SIZE - 4))
	for tab: int in _order:
		var on := tab == _tab
		var plate := PanelContainer.new()
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate.custom_minimum_size.y = TAB_HEIGHT
		plate.add_theme_stylebox_override("panel", HudStyle.slant(Color(0.3, 0.24, 0.1, 0.9) if on else HudStyle.INK,
				HudStyle.GOLD if on else HudStyle.EDGE_DIM, 3 if on else 2, 8, TAB_HEIGHT))
		var line := HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_theme_constant_override("separation", 10)
		plate.add_child(line)
		var tint := HudStyle.GOLD if on else HudStyle.TEXT_DIM
		var glyph := UiGlyph.make(TAB_GLYPHS[tab], TAB_GLYPH_PX, tint)
		glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(glyph)
		var name := HudStyle.make_title(TAB_NAMES[tab], TAB_SIZE, tint)
		name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(name)
		var badge := (_tabs[tab] as PartyTab).badge()
		if badge > 0:
			line.add_child(_badge(badge))
		_bar_box.add_child(plate)
		_tab_plates[tab] = plate
	_bar_box.add_child(HintBar.entry_row(&"item_turn_right", "", TAB_SIZE - 4))


## A gold round badge with a number (points waiting on that tab).
func _badge(n: int) -> Control:
	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style := StyleBoxFlat.new()
	style.bg_color = HudStyle.GOLD
	style.set_corner_radius_all(14)
	style.content_margin_left = 9.0
	style.content_margin_right = 9.0
	box.add_theme_stylebox_override("panel", style)
	box.add_child(HudStyle.make_number(str(n), CHIP_SIZE, Color(0.08, 0.06, 0.04)))
	return box


func _redraw_strip(data: Dictionary) -> void:
	_clear(_strip_icon)
	_clear(_strip_chips)
	_clear(_strip_bar)
	var picture := _icon_for(data.get("icon"), STRIP_ICON_PX)
	if picture != null:
		_strip_icon.add_child(picture)
	_strip_title.text = String(data.get("title", ""))
	_strip_title.label_settings.font_color = data.get("color", HudStyle.TEXT) as Color
	for chip: Variant in data.get("chips", []):
		var parts := chip as Array
		_strip_chips.add_child(_chip(StringName(parts[0]) if parts.size() > 0 else &"", String(parts[1]) if parts.size() > 1 else "",
				parts[2] as Color if parts.size() > 2 else HudStyle.TEXT))
	_strip_line.text = String(data.get("line", ""))
	var bar: Variant = data.get("bar")
	var has_bar := bar is Array and (bar as Array).size() == 2 and int(bar[1]) > 0
	# Without a bar the line takes the strip's whole width.
	_strip_line.size.x = STRIP_RECT.size.x - (520.0 if has_bar else 190.0)
	if has_bar:
		_strip_bar.add_child(UiGlyph.make(&"echo", 26.0, HudStyle.TEXT_DIM))
		for i: int in int(bar[1]):
			var seg := ColorRect.new()
			seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
			seg.custom_minimum_size = BAR_SEGMENT
			seg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			seg.color = Color(0.62, 0.32, 0.72) if i < int(bar[0]) else Color(HudStyle.EDGE_DIM, 0.5)
			_strip_bar.add_child(seg)
		_strip_bar.add_child(HudStyle.make_number("%d / %d" % [int(bar[0]), int(bar[1])], CHIP_SIZE, HudStyle.TEXT_DIM))


## A small box on the strip: an optional glyph and a short text.
func _chip(glyph: StringName, text: String, color: Color) -> Control:
	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_stylebox_override("panel", HudStyle.slant(HudStyle.INK_SOLID, HudStyle.EDGE_DIM, 1, 4, 34.0, HudStyle.SLANT, false))
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 6)
	box.add_child(line)
	if not String(glyph).is_empty():
		var g := UiGlyph.make(glyph, 20.0, color)
		g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(g)
	line.add_child(HudStyle.make_number(text, CHIP_SIZE, color))
	return box


func _redraw_hint() -> void:
	var tab := _tabs[_tab] as PartyTab
	var entries: Array = tab.hints()
	if not tab.busy():
		# A tab gives at most three hints when not busy (a chip pair with one label counts once).
		entries.append([&"item_turn_left", ""])
		entries.append([&"item_turn_right", "Tabs"])
	_hint.set_entries(entries)


## How many hints a footer list shows: an entry with no label joins the next one (LB / RB Tabs).
static func visible_hints(entries: Array) -> int:
	var count := 0
	for entry: Variant in entries:
		if not String((entry as Array)[1]).is_empty():
			count += 1
	return count


## A picture for a strip or a toast: a Relic's icon, an item's sprite, a texture or a glyph.
func _icon_for(icon: Variant, px: float) -> Control:
	if icon is GearData:
		var relic := RelicIcon.new()
		relic.setup(icon as GearData, px, true, _run.relic_level(icon as GearData), _run.tuning.relic_max_level)
		return relic
	if icon is ItemData:
		var item := icon as ItemData
		return _texture_box(AssetLoader.texture(item.icon_path, item.size() * 16), px)
	if icon is Texture2D:
		return _texture_box(icon as Texture2D, px)
	if icon is StringName and not String(icon).is_empty():
		return UiGlyph.make(icon as StringName, px * 0.8, HudStyle.GOLD)
	return null


func _texture_box(texture: Texture2D, px: float) -> Control:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.custom_minimum_size = Vector2(px, px)
	rect.size = Vector2(px, px)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return rect


func _any_tree() -> bool:
	for slot: int in _run.party_size():
		if _run.has_tree(slot):
			return true
	return false


static func _clear(node: Node) -> void:
	for child: Node in node.get_children():
		node.remove_child(child)
		child.free()


func _handled() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _pressed(event: InputEvent, action: StringName) -> bool:
	return PartyTab.pressed(event, action)
