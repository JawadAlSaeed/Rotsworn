class_name GlossaryScreen
extends CanvasLayer
## The glossary (DESIGN.md 7.12, card #207): a book that explains the game's terms and icons, from
## Extras on the main menu and from the pause menu. A topic strip under the title (LT / RT, keys
## 1 / 3, change topic: the switch inside a screen, card #336; left and right too), then two parts
## like the Rot Journal: the topic's terms in a ListMenu on the left,
## and the chosen term on the right in an ink plate with the picture or colour the game uses for
## it, the word as the game prints it, and a short plain explanation. The content is
## data/glossary/glossary.tres; this screen only lays it out. It changes nothing in the game, so it
## is safe over a paused fight.

signal closed

const GLOSSARY_PATH := "res://data/glossary/glossary.tres"
const TITLE_SIZE: int = 64
const STRIP_SIZE: int = 26
## The footer: up / down a term, LT / RT a topic (card #336), Back.
const FOOTER_HINTS: Array = [[&"@updown", "Term"], [ControlBindings.SWITCH_PREV, ""], [ControlBindings.SWITCH_NEXT, "Topic"],
		[&"menu_cancel", "Back"]]
const TOPIC_SIZE: int = 44
const COUNT_SIZE: int = 22
const LIST_ITEM_SIZE: int = 32
const LIST_WIDTH: float = 420.0
const LIST_ROWS: int = 10
const PANEL_WIDTH: float = 1340.0
const PANEL_HEIGHT: float = 600.0
const PANEL_GAP: float = 36.0
const NEIGHBOUR_WIDTH: float = 330.0
const TOPIC_WIDTH: float = 520.0
const PLATE_PX: float = 136.0
const PLATE_INNER_PX: float = 112.0
const SWATCH_PX: float = 72.0
const TERM_SIZE: int = 48
const TAG_SIZE: int = 30
const TEXT_SIZE: int = 32
const PAGE_PAD_PX: float = 80.0

var _data: GlossaryData
var _topic: int = 0
var _terms: Array[GlossaryEntry] = []
var _menu: ListMenu
var _prev: Label
var _topic_label: Label
var _next: Label
var _count: Label
var _panel: VBoxContainer
var _shown: int = -1


## The glossary file, or an empty one (with a warning) when it cannot be loaded.
static func load_glossary() -> GlossaryData:
	var data := load(GLOSSARY_PATH) as GlossaryData
	if data == null:
		push_warning("GlossaryScreen: could not load %s, the glossary is empty" % GLOSSARY_PATH)
		return GlossaryData.new()
	return data


## `start_topic`: the id of the topic to open on (the first when empty or unknown).
func setup(data: GlossaryData, start_topic: String = "") -> void:
	_data = data
	var column := ListMenu.screen_column(self, "Glossary", TITLE_SIZE)
	column.add_child(_strip())
	_count = ListMenu.centred_label("", COUNT_SIZE, HudStyle.TEXT_DIM)
	column.add_child(_count)
	var body := HBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_theme_constant_override("separation", int(PANEL_GAP))
	column.add_child(body)
	_menu = ListMenu.new()
	_menu.centred = false
	_menu.row_width = LIST_WIDTH
	_menu.item_size = LIST_ITEM_SIZE
	_menu.window_rows = LIST_ROWS
	_menu.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	body.add_child(_menu)
	var frame := PanelContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	frame.add_theme_stylebox_override("panel", HudStyle.panel(HudStyle.INK, HudStyle.EDGE_DIM, 2, 20))
	body.add_child(frame)
	_panel = VBoxContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_constant_override("separation", 14)
	frame.add_child(_panel)
	ListMenu.screen_footer(self, FOOTER_HINTS)
	_open_topic(maxi(0, _data.topic_index(start_topic)))


func _unhandled_input(event: InputEvent) -> void:
	if _switch_pressed(event, ControlBindings.SWITCH_PREV) or _switch_pressed(event, ControlBindings.SWITCH_NEXT):
		get_viewport().set_input_as_handled()
		_open_topic(_topic + (-1 if event.is_action(ControlBindings.SWITCH_PREV) else 1), true)
		return
	match _menu.handle(event):
		&"cancel":
			Sfx.play("menu_cancel")
			closed.emit()
		&"left":
			_open_topic(_topic - 1, true)
		&"right":
			_open_topic(_topic + 1, true)
		_:
			if _menu.index != _shown:
				_refresh()


## The term under the cursor, or null (an empty glossary).
func selected_entry() -> GlossaryEntry:
	return _terms[_menu.index] if _menu.index >= 0 and _menu.index < _terms.size() else null


## The topic shown (an index into GlossaryData.topic_ids).
func topic() -> int:
	return _topic


## A switch button going down (a trigger sends many motion events while held: only the first counts).
static func _switch_pressed(event: InputEvent, action: StringName) -> bool:
	if not event.is_action_pressed(action, false, true):
		return false
	return not (event is InputEventJoypadMotion) or Input.is_action_just_pressed(action)


## "LT previous   TOPIC   next RT": the neighbours are dim so the way round is clear, and the
## switch's buttons sit at the ends (card #336).
func _strip() -> HBoxContainer:
	var strip := HBoxContainer.new()
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.alignment = BoxContainer.ALIGNMENT_CENTER
	strip.add_theme_constant_override("separation", 24)
	strip.add_child(_switch_chip(ControlBindings.SWITCH_PREV))
	_prev = HudStyle.make_label("", STRIP_SIZE, HudStyle.TEXT_DIM)
	_prev.custom_minimum_size.x = NEIGHBOUR_WIDTH
	_prev.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	strip.add_child(_prev)
	_topic_label = HudStyle.make_worn_title("", TOPIC_SIZE)
	_topic_label.custom_minimum_size.x = TOPIC_WIDTH
	_topic_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	strip.add_child(_topic_label)
	_next = HudStyle.make_label("", STRIP_SIZE, HudStyle.TEXT_DIM)
	_next.custom_minimum_size.x = NEIGHBOUR_WIDTH
	strip.add_child(_next)
	strip.add_child(_switch_chip(ControlBindings.SWITCH_NEXT))
	return strip


## A switch button's chip at an end of the topic strip.
static func _switch_chip(action: StringName) -> HintBar:
	var chip := HintBar.new([[action, ""]], STRIP_SIZE)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return chip


## Shows topic `index` (wrapping round the ends) with the cursor on its first term.
func _open_topic(index: int, with_sound: bool = false) -> void:
	var count := _data.topic_ids.size()
	if count == 0:
		_terms = []
		var none: Array[Dictionary] = []
		_menu.set_items(none)
		_refresh()
		return
	_topic = wrapi(index, 0, count)
	if with_sound:
		Sfx.play("menu_move")
	_terms = _data.topic_entries(_data.topic_ids[_topic])
	_prev.text = _data.topic_names[wrapi(_topic - 1, 0, count)] if count > 1 else ""
	_next.text = _data.topic_names[wrapi(_topic + 1, 0, count)] if count > 1 else ""
	_topic_label.text = _data.topic_names[_topic]
	_count.text = "Topic %d of %d    %d %s" % [_topic + 1, count, _terms.size(), "term" if _terms.size() == 1 else "terms"]
	var rows: Array[Dictionary] = []
	for entry: GlossaryEntry in _terms:
		rows.append({"text": entry.term})
	_menu.index = 0
	_menu.set_items(rows)
	_refresh()


func _refresh() -> void:
	_shown = _menu.index
	for child: Node in _panel.get_children():
		_panel.remove_child(child)
		child.queue_free()
	var entry := selected_entry()
	if entry == null:
		_panel.add_child(HudStyle.make_label("Nothing here yet.", TEXT_SIZE, HudStyle.TEXT_DIM))
		return
	_panel.add_child(_header(entry))
	_panel.add_child(ListMenu.divider(PANEL_WIDTH - PAGE_PAD_PX))
	var text := HudStyle.make_label(entry.text, TEXT_SIZE, HudStyle.TEXT)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.x = PANEL_WIDTH - PAGE_PAD_PX
	_panel.add_child(text)


## The picture or colour (when the term has one), the term's name and the word the game prints.
func _header(entry: GlossaryEntry) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 24)
	var plate := picture(entry)
	if plate != null:
		row.add_child(plate)
	var names := VBoxContainer.new()
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	names.add_theme_constant_override("separation", 6)
	row.add_child(names)
	names.add_child(HudStyle.make_worn_title(entry.term, TERM_SIZE))
	if not entry.tag.is_empty():
		var tag_color := entry.color if entry.has_color() else HudStyle.TEXT_DIM
		var tag := HudStyle.make_label("Shown as  " + entry.tag, TAG_SIZE, tag_color)
		names.add_child(tag)
	return row


## A square plate holding the term's icon (whole-number scaled so the pixel art stays crisp), or a
## swatch of its colour; null when it has neither.
static func picture(entry: GlossaryEntry) -> PanelContainer:
	var accent := entry.color if entry.has_color() else HudStyle.EDGE
	var content: Control
	if not entry.icon_path.is_empty():
		var texture := AssetLoader.texture(entry.icon_path, Vector2i(12, 12))
		var size := texture.get_size()
		var scale := maxf(1.0, floorf(PLATE_INNER_PX / maxf(1.0, maxf(size.x, size.y))))
		var icon := TextureRect.new()
		icon.texture = texture
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.custom_minimum_size = size * scale
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content = icon
	elif entry.has_color():
		var swatch := ColorRect.new()
		swatch.color = Color(entry.color, 1.0)
		swatch.custom_minimum_size = Vector2(SWATCH_PX, SWATCH_PX)
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content = swatch
	else:
		return null
	var plate := PanelContainer.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.custom_minimum_size = Vector2(PLATE_PX, PLATE_PX)
	plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plate.add_theme_stylebox_override("panel", HudStyle.panel(Color(0.0, 0.0, 0.0, 0.45), accent, 3, 4))
	var centre := CenterContainer.new()
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(content)
	plate.add_child(centre)
	return plate
