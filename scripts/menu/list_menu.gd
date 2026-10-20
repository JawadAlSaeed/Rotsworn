class_name ListMenu
extends VBoxContainer
## A vertical list of choices for the menus outside a fight (main menu, settings, shop, rest).
## Driven by the menu_* input actions, like the fight list, and by the mouse (card #202): the
## screen that owns it passes each input event to handle(), which moves the cursor itself and
## reports the rest. Pointing at a row chooses it, a left click confirms it, a right click or the
## mouse's back button goes back and the wheel moves the cursor.
## Each item is a row: its text, and an optional value on the right (a price, a setting). The
## chosen row's text is drawn like the logo's letters: bigger, in worn gold, its edges flickering
## like static (text_static.gdshader); the others are a little dimmer (DESIGN.md 7.7).
## With `horizontal` (phase 22: two or three choices go side by side, never in a column) each item is
## a card in a row: its icon on top (optional), its word under it, then its value and a few icon
## chips (what it costs or gives, card #288); left and right move the cursor. A card the party
## cannot take is greyed, icon and chips too.

const ITEM_SIZE: int = 40
const DETAIL_SIZE: int = 26
## Width of the rows in a centred menu, and in a left-aligned one (pixels).
const CENTRED_ROW_WIDTH: float = 560.0
const LEFT_ROW_WIDTH: float = 720.0
const ROW_PAD_X: int = 22
const ROW_PAD_Y: int = 4
const ACCENT_PX: int = 5
const SELECTED_BG := Color(1.0, 0.78, 0.3, 0.16)
## The chosen row lights up for a moment when the cursor lands on it.
const SELECTED_FLASH := Color(1.5, 1.4, 1.2)
const SELECTED_FLASH_S: float = 0.16
const TITLE_DIVIDER_WIDTH: float = 620.0
const TITLE_DIVIDER_PX: float = 3.0
const FOOTER_SIZE: int = 26
const FOOTER_STRIP := Color(0.0, 0.0, 0.0, 0.45)
const FOOTER_STRIP_PX: float = 76.0
## Side-by-side cards (horizontal): the narrowest card, gap between cards, icon size and the chosen
## card's frame. Cards grow so every word sits on one line (owner, phase 22), all as wide as the
## widest, the whole row never wider than CARD_ROW_MAX_WIDTH; a word still too long there gets a
## smaller font, down to CARD_MIN_TITLE_SIZE.
const CARD_WIDTH: float = 320.0
const CARD_ROW_MAX_WIDTH: float = 1760.0
const CARD_MIN_TITLE_SIZE: int = 24
const CARD_GAP: int = 28
const CARD_ICON_PX: float = 96.0
const CARD_PAD: int = 18
const CARD_BORDER_PX: int = 3
const CARD_BG := Color(0.03, 0.025, 0.04, 0.72)
## A card's value line (a tag like "New"), smaller than its word.
const CARD_VALUE_SIZE: int = 28
## A greyed card's icon and chips.
const DISABLED_CARD_ALPHA: float = 0.4
## Icon chips (on cards and under a question): text size, the icon's largest side, the gap between
## chips and between the icon and the text, the plate's padding and colour.
const CHIP_SIZE: int = 26
const CHIP_ICON_PX: float = 36.0
const CHIP_GAP: int = 8
const CHIP_PAD: int = 6
const CHIP_BG := Color(0.0, 0.0, 0.0, 0.42)

## Every item: {text: String, enabled: bool, detail: String, value: String, color: Color (optional,
## the text colour while not chosen), icon: Texture2D (optional; drawn on a horizontal card)}.
## A horizontal card also takes (all optional): icon_make: Callable returning a Control to draw
## instead of `icon` (a Relic's drawn icon), icon_color: Color (tints the icon), icon_scale: int (screen
## pixels per art pixel; default: the most that fits CARD_ICON_PX), chips: Array of chip()
## dictionaries.
var items: Array[Dictionary] = []
var index: int = 0
var item_size: int = ITEM_SIZE
## Centre the items (main menu) or line them up on the left (shop, settings).
var centred: bool = true
## Row width in pixels (0: CENTRED_ROW_WIDTH or LEFT_ROW_WIDTH).
var row_width: float = 0.0
## How many rows show at once (0: all). A longer list scrolls with the cursor (the Controls list).
var window_rows: int = 0
## Side by side: one card per item in a row (for two or three choices, phase 22). Set before
## set_items().
var horizontal: bool = false
## The row of cards when horizontal.
var _strip: HBoxContainer
## Each card's icon and chips (greyed with the card), in item order; empty lists when vertical.
var _card_parts: Array[Array] = []
## The cards' width now, and each card's word size (fitted to one line; _fit_cards()).
var _card_w: float = CARD_WIDTH
var _card_sizes: Array[int] = []
var _top: int = 0
var _rows: Array[PanelContainer] = []
## Rows still in the list (the cursor stops on them) but drawn elsewhere by the owner.
var _hidden: Dictionary = {}
var _labels: Array[Label] = []
var _values: Array[Label] = []
var _detail: Label
var _shown_index: int = -1
## Process frame of the last stick move (a held stick sends many motion events).
var _stick_frame: int = -1
## After a left click was reported as &"confirm": how far across the row it landed (0 to 1), and
## across the row's value text (-1 when it was not on the value). -1 after any other answer. A screen
## can use them to step a setting down or up by the side that was clicked.
var clicked_share: float = -1.0
var clicked_value_share: float = -1.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_theme_constant_override("separation", 6)


## Replaces the items (keeps the cursor where it was if it still fits).
func set_items(new_items: Array[Dictionary], detail_label: Label = null) -> void:
	items = new_items
	if detail_label != null:
		_detail = detail_label
	for row: PanelContainer in _rows:
		row.queue_free()
	_rows.clear()
	_labels.clear()
	_values.clear()
	_card_parts.clear()
	custom_minimum_size.x = row_width if row_width > 0.0 else (CENTRED_ROW_WIDTH if centred else LEFT_ROW_WIDTH)
	if not horizontal and _strip != null:
		# Back to a column (a screen that showed cards now lists items): the row of cards goes at
		# once (nothing else holds its cards).
		_strip.free()
		_strip = null
	if horizontal:
		custom_minimum_size.x = 0.0
		_fit_cards()
		if _strip == null:
			_strip = HBoxContainer.new()
			_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_strip.alignment = BoxContainer.ALIGNMENT_CENTER
			_strip.add_theme_constant_override("separation", CARD_GAP)
			add_child(_strip)
	for i: int in items.size():
		var row := PanelContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_stylebox_override("panel", card_style(false) if horizontal else row_style(false))
		var line: BoxContainer = VBoxContainer.new() if horizontal else HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_theme_constant_override("separation", 10 if horizontal else 24)
		row.add_child(line)
		var parts: Array[Control] = []
		if horizontal:
			row.custom_minimum_size.x = _card_w
			var picture := _card_picture(items[i])
			if picture != null:
				line.add_child(picture)
				parts.append(picture)
		# Choices in the title font, like the logo (card #83); values stay in the body font.
		var label := HudStyle.make_title("", item_size)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centred or horizontal else HORIZONTAL_ALIGNMENT_LEFT
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Every row is as tall as a chosen one, so nothing moves when the choice changes.
		label.custom_minimum_size.y = ceilf(HudStyle.select_font().get_height(_select_size()))
		if horizontal:
			# The word is fitted to one line (_fit_cards); wrapping is only a last resort. A card of
			# words alone (Yes / No) centres them in its height; a card with a picture or chips keeps
			# its word under the picture, level with its neighbours.
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.custom_minimum_size.x = _card_inner()
			if parts.is_empty() and (items[i].get("chips", []) as Array).is_empty():
				label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		line.add_child(label)
		# A card's tag (New, Lv 1 > 2) is never bigger than its fitted word.
		var value := HudStyle.make_label("", mini(CARD_VALUE_SIZE, card_title_size(i)) if horizontal else item_size)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if horizontal else HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(value)
		if horizontal:
			var chips: Array = items[i].get("chips", []) as Array
			if not chips.is_empty():
				var lines := chip_lines(chips, _card_inner())
				line.add_child(lines)
				parts.append(lines)
		_card_parts.append(parts)
		row.visible = not _hidden.has(i) and _in_window(i)
		if horizontal:
			_strip.add_child(row)
		else:
			add_child(row)
		_rows.append(row)
		_labels.append(label)
		_values.append(value)
	index = clampi(index, 0, maxi(0, items.size() - 1))
	_top = 0
	_shown_index = -1
	redraw()


## Sizes the cards: wide enough for the longest word on one line (at least CARD_WIDTH), sharing
## CARD_ROW_MAX_WIDTH; each word that still does not fit gets a smaller font, step by step.
func _fit_cards() -> void:
	_card_sizes.clear()
	var count := maxi(1, items.size())
	var room := (CARD_ROW_MAX_WIDTH - float(CARD_GAP * (count - 1))) / float(count)
	var widest := 0.0
	for item: Dictionary in items:
		widest = maxf(widest, title_width(String(item.get("text", "")), item_size))
	_card_w = clampf(widest + float(CARD_PAD + CARD_BORDER_PX) * 2.0, CARD_WIDTH, maxf(CARD_WIDTH, room))
	for item: Dictionary in items:
		var size := item_size
		while size > CARD_MIN_TITLE_SIZE and title_width(String(item.get("text", "")), size) > _card_inner():
			size -= 2
		_card_sizes.append(size)


## The room for words inside a card.
func _card_inner() -> float:
	return _card_w - float(CARD_PAD + CARD_BORDER_PX) * 2.0


## A card's word size (item_size until the cards are fitted).
func card_title_size(i: int) -> int:
	return _card_sizes[i] if i >= 0 and i < _card_sizes.size() else item_size


## How wide `text` is drawn in the title font at `size` (with the text-size setting and the outline).
static func title_width(text: String, size: int) -> float:
	var settings := HudStyle.title_settings(size)
	if settings.font == null:
		return 0.0
	return settings.font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, settings.font_size).x \
			+ float(settings.outline_size)


func set_item(i: int, text: String, enabled: bool = true, detail: String = "", value: String = "") -> void:
	if i < 0 or i >= items.size():
		return
	items[i] = {"text": text, "enabled": enabled, "detail": detail, "value": value}
	redraw()


## Hides row `i` while keeping it in the list: the cursor still stops on it (the owner shows the
## choice some other way, like the players screen's hero cards).
func set_row_shown(i: int, shown: bool) -> void:
	if shown:
		_hidden.erase(i)
	else:
		_hidden[i] = true
	if i >= 0 and i < _rows.size():
		_rows[i].visible = shown and _in_window(i)


func is_enabled(i: int) -> bool:
	return i >= 0 and i < items.size() and bool(items[i].get("enabled", true))


## Handles one input event. Moves the cursor on up/down and returns &"" then; returns &"confirm",
## &"cancel", &"left" or &"right" for the owner to act on, or &"" if the event was not for menus.
## Marks every menu event as handled.
func handle(event: InputEvent) -> StringName:
	if event is InputEventMouse:
		return _handle_mouse(event)
	clicked_share = -1.0
	clicked_value_share = -1.0
	var answer := &""
	if _pressed(event, &"menu_up"):
		_move(-1)
	elif _pressed(event, &"menu_down"):
		_move(1)
	elif horizontal and _pressed(event, &"menu_left"):
		_step(-1)
	elif horizontal and _pressed(event, &"menu_right"):
		_step(1)
	elif _pressed(event, &"menu_confirm"):
		answer = &"confirm"
	elif _pressed(event, &"menu_cancel"):
		answer = &"cancel"
	elif _pressed(event, &"menu_left"):
		answer = &"left"
	elif _pressed(event, &"menu_right"):
		answer = &"right"
	else:
		return &""
	if is_inside_tree():
		get_viewport().set_input_as_handled()
	return answer


## The mouse: pointing at a row chooses it (and returns &""), a left click on a row returns
## &"confirm" (after choosing it), a right click or the back button returns &"cancel", the wheel
## moves the cursor (stopping at the ends). Clicks and the wheel are marked handled; so is a move
## that lands on another row. Nothing happens while the list is not shown.
func _handle_mouse(event: InputEvent) -> StringName:
	clicked_share = -1.0
	clicked_value_share = -1.0
	if items.is_empty() or not is_visible_in_tree():
		return &""
	var answer := &""
	if event is InputEventMouseMotion:
		var hovered := row_at((event as InputEventMouse).position)
		if hovered < 0 or hovered == index:
			return &""
		_choose_row(hovered)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var button := (event as InputEventMouseButton).button_index
		var wheel := MenuMouse.wheel_step(button)
		if wheel != 0:
			var next := clampi(index + wheel, 0, items.size() - 1)
			if next != index:
				_choose_row(next)
		else:
			answer = MenuMouse.answer_for_button(button)
			if answer == &"confirm":
				var row := row_at((event as InputEventMouse).position)
				if row < 0:
					return &""
				if row != index:
					_choose_row(row)
				_remember_click(row, (event as InputEventMouse).position)
			elif answer == &"":
				return &""
	else:
		return &""
	if is_inside_tree():
		get_viewport().set_input_as_handled()
	return answer


## The row (item index) under a viewport point, -1 for none. Only rows that are shown count.
func row_at(point: Vector2) -> int:
	return MenuMouse.control_at(_rows, point)


func _choose_row(i: int) -> void:
	index = i
	Sfx.play("menu_move")
	redraw()


func _remember_click(row: int, point: Vector2) -> void:
	clicked_share = MenuMouse.share_across(_rows[row], point)
	clicked_value_share = MenuMouse.share_across(_values[row], point)


func redraw() -> void:
	_scroll_to_index()
	for i: int in _labels.size():
		var selected := i == index
		var enabled := is_enabled(i)
		_labels[i].text = String(items[i].get("text", ""))
		var value := String(items[i].get("value", ""))
		_values[i].text = value
		_values[i].visible = not value.is_empty()
		var look := HudStyle.fonts()
		var color := look.select_color if selected else look.idle_color
		if not enabled:
			color = HudStyle.TEXT_DIM.lightened(0.15) if selected else HudStyle.TEXT_DIM
		elif not selected and items[i].get("color") is Color:
			# A row's own colour (for example an item's rarity) while it is not chosen.
			color = items[i].color
		if selected and enabled and horizontal:
			# A card keeps the same font and size when chosen (the gold frame and colour show it), so
			# its words never re-wrap and jump.
			_labels[i].label_settings = HudStyle.title_settings(card_title_size(i), color)
			_labels[i].material = HudStyle.worn_material()
		elif selected and enabled:
			var chosen := LabelSettings.new()
			chosen.font = HudStyle.select_font()
			chosen.font_size = _select_size()
			chosen.font_color = color
			_labels[i].label_settings = chosen
			_labels[i].material = HudStyle.worn_material()
		else:
			_labels[i].label_settings = HudStyle.title_settings(card_title_size(i) if horizontal else item_size, color)
			_labels[i].material = null
		_values[i].label_settings.font_color = color
		_rows[i].add_theme_stylebox_override("panel", card_style(selected) if horizontal else row_style(false))
		if i < _card_parts.size():
			for part: Control in _card_parts[i]:
				part.modulate.a = 1.0 if enabled else DISABLED_CARD_ALPHA
	if index != _shown_index and index < _rows.size():
		_shown_index = index
		var row := _rows[index]
		row.modulate = SELECTED_FLASH
		row.create_tween().tween_property(row, "modulate", Color.WHITE, SELECTED_FLASH_S)
	if _detail != null:
		_detail.text = String(items[index].get("detail", "")) if index < items.size() else ""


## True when row `i` is inside the visible window (always, without one).
func _in_window(i: int) -> bool:
	return window_rows <= 0 or (i >= _top and i < _top + window_rows)


## Moves the window so the chosen row is inside it, and shows only the rows in it.
func _scroll_to_index() -> void:
	if window_rows <= 0:
		return
	if index < _top:
		_top = index
	elif index >= _top + window_rows:
		_top = index - window_rows + 1
	_top = clampi(_top, 0, maxi(0, items.size() - window_rows))
	for i: int in _rows.size():
		_rows[i].visible = not _hidden.has(i) and _in_window(i)


## The first row shown (0 without a window).
func top_row() -> int:
	return _top


func _select_size() -> int:
	return HudStyle.scaled(roundi(float(item_size) * float(HudStyle.fonts().select_size_percent) / 100.0))


func _move(step: int) -> void:
	if items.is_empty():
		return
	index = wrapi(index + step, 0, items.size())
	Sfx.play("menu_move")
	redraw()


## Moves along a row of cards, stopping at the ends: Left on No never wraps round to Yes.
func _step(step: int) -> void:
	var next := clampi(index + step, 0, maxi(0, items.size() - 1))
	if next == index:
		return
	index = next
	Sfx.play("menu_move")
	redraw()


func _pressed(event: InputEvent, action: StringName) -> bool:
	if not event.is_action_pressed(action, false, true):
		return false
	if event is InputEventJoypadMotion:
		var frame := Engine.get_process_frames()
		if not Input.is_action_just_pressed(action) or frame == _stick_frame:
			return false
		_stick_frame = frame
	return true


## The chosen row: a soft gold bar with a bright edge on the left. Other rows keep the same
## margins with no bar, so the text never jumps. `pad_x`: the side padding.
static func row_style(selected: bool, pad_x: int = ROW_PAD_X) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = SELECTED_BG if selected else Color(0, 0, 0, 0)
	box.border_color = HudStyle.GOLD if selected else Color(0, 0, 0, 0)
	box.border_width_left = ACCENT_PX
	box.set_corner_radius_all(4)
	box.content_margin_left = pad_x + ACCENT_PX
	box.content_margin_right = pad_x
	box.content_margin_top = ROW_PAD_Y
	box.content_margin_bottom = ROW_PAD_Y
	return box


## A side-by-side card's frame: dark ink, edged in gold while chosen (the same margins either way,
## so nothing jumps).
static func card_style(selected: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = CARD_BG.blend(SELECTED_BG) if selected else CARD_BG
	box.border_color = HudStyle.GOLD if selected else HudStyle.EDGE_DIM
	box.set_border_width_all(CARD_BORDER_PX)
	box.set_corner_radius_all(6)
	box.set_content_margin_all(CARD_PAD)
	return box


## A card's picture: the item's icon_make Control, else its icon (pixel art, whole screen pixels per
## art pixel, tinted by icon_color), else null.
func _card_picture(item: Dictionary) -> Control:
	var made: Control = null
	if item.get("icon_make") is Callable:
		made = (item.icon_make as Callable).call() as Control
	if made != null:
		made.mouse_filter = Control.MOUSE_FILTER_IGNORE
		made.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		return made
	if not item.get("icon") is Texture2D:
		return null
	var picture := icon_rect(item.icon as Texture2D, CARD_ICON_PX, int(item.get("icon_scale", 0)))
	picture.size_flags_horizontal = Control.SIZE_FILL
	if item.get("icon_color") is Color:
		picture.self_modulate = item.icon_color
	return picture


## A pixel-art picture as big as fits `box` px on its longer side in whole screen pixels per art
## pixel (or `scale` of them; a picture bigger than the box is shrunk to it).
static func icon_rect(texture: Texture2D, box: float, scale: int = 0) -> TextureRect:
	var picture := TextureRect.new()
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.texture = texture
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var art := texture.get_size()
	var side := maxf(1.0, maxf(art.x, art.y))
	var factor := float(scale) if scale > 0 else (floorf(box / side) if side <= box else box / side)
	picture.custom_minimum_size = (art * factor).round()
	return picture


## One icon chip: {icon: Texture2D or glyph: StringName (a UiGlyph kind; optional), text: String,
## color: Color (the text's; default the body text)} on a small dark plate. `newline` in the
## dictionary starts a new line in chip_lines().
static func chip(entry: Dictionary, font_size: int = CHIP_SIZE, max_width: float = 0.0) -> PanelContainer:
	var plate := PanelContainer.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_theme_stylebox_override("panel", HudStyle.panel(CHIP_BG, Color(0.0, 0.0, 0.0, 0.0), 0, CHIP_PAD))
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", CHIP_GAP)
	plate.add_child(row)
	var color: Color = entry.color if entry.get("color") is Color else HudStyle.TEXT
	var room := max_width - CHIP_PAD * 2
	if entry.get("icon") is Texture2D:
		var picture := icon_rect(entry.icon as Texture2D, CHIP_ICON_PX)
		picture.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(picture)
		room -= picture.custom_minimum_size.x + CHIP_GAP
	elif not String(entry.get("glyph", "")).is_empty():
		var glyph := UiGlyph.make(StringName(entry.glyph), CHIP_ICON_PX * 0.8, color)
		glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(glyph)
		room -= glyph.custom_minimum_size.x + CHIP_GAP
	var text := String(entry.get("text", ""))
	if not text.is_empty():
		var label := HudStyle.make_label(text, font_size, color)
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		# A few words that would not fit the card wrap instead of widening it.
		var font := label.get_theme_font(&"font")
		if max_width > 0.0 and font != null \
				and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.label_settings.font_size).x > room:
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.custom_minimum_size.x = maxf(room, 40.0)
		row.add_child(label)
	return plate


## Chips in centred lines, `width` px wide at most (a line too long wraps); a chip with `newline`
## starts a new line.
static func chip_lines(entries: Array, width: float, font_size: int = CHIP_SIZE) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", CHIP_GAP)
	var flow: HFlowContainer = null
	for entry: Variant in entries:
		if not entry is Dictionary:
			continue
		if flow == null or bool((entry as Dictionary).get("newline", false)):
			flow = HFlowContainer.new()
			flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
			flow.alignment = FlowContainer.ALIGNMENT_CENTER
			flow.custom_minimum_size.x = width
			flow.add_theme_constant_override("h_separation", CHIP_GAP)
			flow.add_theme_constant_override("v_separation", CHIP_GAP)
			box.add_child(flow)
		flow.add_child(chip(entry as Dictionary, font_size, width))
	return box


## The chips under item `i`'s card (tests), or [] for none.
func card_chips(i: int) -> Array:
	return items[i].get("chips", []) as Array if i >= 0 and i < items.size() else []


## The menu background (MenuBackdrop) and a centred column with a title and a thin gold line
## under it, for a menu screen. Returns the column; the background and column are added to
## `parent`. The title is the column's first child.
static func screen_column(parent: Node, title: String, title_size: int = 64) -> VBoxContainer:
	parent.add_child(MenuBackdrop.new())
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_bottom = -FOOTER_STRIP_PX
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 18)
	parent.add_child(column)
	if not title.is_empty():
		var label := HudStyle.make_worn_title(title, title_size)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.label_settings.shadow_color = Color(0.0, 0.0, 0.0, 0.6)
		label.label_settings.shadow_offset = Vector2(0.0, maxf(3.0, float(title_size) * 0.06))
		column.add_child(label)
		column.add_child(divider())
	return column


## A thin gold line that fades out at both ends.
static func divider(width: float = TITLE_DIVIDER_WIDTH) -> TextureRect:
	var gradient := Gradient.new()
	var gold := HudStyle.worn_gold()
	gradient.set_color(0, Color(gold, 0.0))
	gradient.set_color(1, Color(gold, 0.0))
	gradient.add_point(0.5, Color(gold, 0.85))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 256
	texture.height = 1
	var line := TextureRect.new()
	line.texture = texture
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	line.stretch_mode = TextureRect.STRETCH_SCALE
	line.custom_minimum_size = Vector2(width, TITLE_DIVIDER_PX)
	line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return line


## Button hints along the bottom of a screen, on a dark strip ([[action, text], ...], see
## HintBar). Returns the bar (set_entries() changes it later).
static func screen_footer(parent: Node, entries: Array) -> HintBar:
	var strip := ColorRect.new()
	strip.color = FOOTER_STRIP
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	strip.offset_top = -FOOTER_STRIP_PX
	parent.add_child(strip)
	var bar := HintBar.new(entries, FOOTER_SIZE)
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -FOOTER_STRIP_PX
	strip.add_sibling(bar)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	return bar


## A centred title-font label for a screen column (titles outside screen_column).
static func centred_title(text: String, size: int, color: Color = HudStyle.GOLD) -> Label:
	var label := HudStyle.make_worn_title(text, size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


## Row `i`'s own line (its word and value side by side; a card's column when horizontal), so a
## screen can put a picture of its own in a row (a button chip, a glyph); null for no such row. The
## row is rebuilt by set_items(), so whatever is added goes with it.
func row_box(i: int) -> BoxContainer:
	if i < 0 or i >= _rows.size() or _rows[i].get_child_count() == 0:
		return null
	return _rows[i].get_child(0) as BoxContainer


## A centred label for a screen column.
static func centred_label(text: String, size: int, color: Color = HudStyle.TEXT) -> Label:
	var label := HudStyle.make_label(text, size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label
