class_name TimelineRow
extends PanelContainer
## The turn order (top left) on a dark see-through strip: the current actor first, bigger, framed
## in gold and tagged NOW, then the next turns from mirror.turn_order. Enemies get red frames and
## red names, so heroes and enemies part at a glance. Under each enemy's next turn, one icon per
## hit of its intended attack (DESIGN.md 2.8).

const CURRENT_BORDER_PX: int = 4
const OTHER_BORDER_PX: int = 2
const CURRENT_SCALE: float = 1.3
const NAME_SIZE: int = 18
## Name width, as a multiple of the portrait size.
const NAME_WIDTH_FACTOR: float = 2.0
const ENTRY_GAP: int = 10
const FRAME_PAD: int = 3
const STRIP_BG := Color(0.02, 0.02, 0.04, 0.55)
const STRIP_PAD: int = 10
## The top leaves room for the NOW tag, which pokes up over the current frame's top edge.
const STRIP_PAD_TOP: int = 14
const NOW_TEXT := "NOW"
const NOW_SIZE: int = 14
const NOW_TEXT_COLOR := Color(0.12, 0.08, 0.02)
const NOW_PAD_X: int = 6
## The tag rises this share of its font size above the frame's top edge (about half its height),
## so it sits on the edge instead of over the face.
const NOW_RISE_SHARE: float = 0.65
const ENEMY_FRAME_BG := Color(0.24, 0.05, 0.05, 0.85)
## Enemy names are the red of their frames, lifted so they read on the strip.
const ENEMY_NAME_LIGHTEN: float = 0.3

var _row: HBoxContainer
var _entries: Array[Dictionary] = []
var _portrait_px: float = 56.0
## AttackHitData.Kind -> Texture2D.
var _hit_icons: Dictionary = {}
var _icon_px: float = 20.0


## `hit_icons` maps AttackHitData.Kind to its icon texture.
func setup(count: int, portrait_px: float, hit_icons: Dictionary, icon_px: float) -> void:
	_portrait_px = portrait_px
	_hit_icons = hit_icons
	_icon_px = icon_px
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var strip := HudStyle.panel(STRIP_BG, Color(0.0, 0.0, 0.0, 0.0), 0, STRIP_PAD)
	strip.content_margin_top = STRIP_PAD_TOP
	add_theme_stylebox_override("panel", strip)
	_row = HBoxContainer.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override("separation", ENTRY_GAP)
	add_child(_row)
	for i: int in count:
		_entries.append(_make_entry())


## Shows `order` (combatant ids, current actor first). `portraits` and `colors` map id -> value.
func show_order(order: Array[int], mirror: CombatMirror, portraits: Dictionary, colors: Dictionary) -> void:
	visible = not order.is_empty()
	for i: int in _entries.size():
		var e: Dictionary = _entries[i]
		var box: VBoxContainer = e.box
		if i >= order.size():
			box.visible = false
			continue
		box.visible = true
		var id := order[i]
		var current := i == 0 and id == mirror.active_actor
		var enemy := not mirror.party_ids.has(id)
		var px := _portrait_px * (CURRENT_SCALE if current else 1.0)
		var portrait: TextureRect = e.portrait
		portrait.custom_minimum_size = Vector2(px, px)
		portrait.texture = portraits.get(id) as Texture2D
		var side_color := HudStyle.LATE if enemy else (colors.get(id, HudStyle.PANEL_BORDER) as Color)
		var style: StyleBoxFlat = e.style
		style.bg_color = ENEMY_FRAME_BG if enemy else HudStyle.PANEL_BG
		style.border_color = HudStyle.GOLD if current else side_color
		style.set_border_width_all(CURRENT_BORDER_PX if current else OTHER_BORDER_PX)
		(e.now as Control).visible = current
		var label: Label = e.label
		label.text = String(mirror.fighter(id).get("display_name", "?"))
		var name_color := HudStyle.GOLD if current else HudStyle.TEXT
		if enemy:
			name_color = HudStyle.LATE.lightened(ENEMY_NAME_LIGHTEN)
		label.label_settings.font_color = name_color
		var kinds: Array = []
		if mirror.intents.has(id) and order.find(id) == i:
			kinds = (mirror.intents[id] as Dictionary).get("kinds", [])
		_show_icons(e.icons as HBoxContainer, kinds)
	# Not in a container: shrink the strip back when entries hide or get smaller.
	reset_size()


func _make_entry() -> Dictionary:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_END
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	var frame := PanelContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var style := HudStyle.panel(HudStyle.PANEL_BG, HudStyle.PANEL_BORDER, OTHER_BORDER_PX, FRAME_PAD)
	frame.add_theme_stylebox_override("panel", style)
	var portrait := TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(portrait)
	var now := _make_now_tag()
	portrait.add_child(now)
	var label := HudStyle.make_label("", NAME_SIZE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(_portrait_px * NAME_WIDTH_FACTOR, 0.0)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var icons := HBoxContainer.new()
	icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icons.alignment = BoxContainer.ALIGNMENT_CENTER
	icons.add_theme_constant_override("separation", 1)
	icons.custom_minimum_size = Vector2(0.0, _icon_px)
	box.add_child(frame)
	box.add_child(label)
	box.add_child(icons)
	_row.add_child(box)
	return {"box": box, "style": style, "portrait": portrait, "now": now, "label": label, "icons": icons}


## A small gold NOW tag centred on the top edge of a portrait frame (placed by anchors, so it
## follows the portrait's size).
func _make_now_tag() -> PanelContainer:
	var tag := PanelContainer.new()
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := HudStyle.panel(HudStyle.GOLD, HudStyle.OUTLINE_COLOR, 1, 0)
	style.content_margin_left = NOW_PAD_X
	style.content_margin_right = NOW_PAD_X
	tag.add_theme_stylebox_override("panel", style)
	var label := HudStyle.make_label(NOW_TEXT, NOW_SIZE, NOW_TEXT_COLOR)
	# Dark text on gold: an outline would only blur it.
	label.label_settings.outline_size = 0
	tag.add_child(label)
	tag.set_anchors_preset(Control.PRESET_CENTER_TOP)
	tag.grow_horizontal = Control.GROW_DIRECTION_BOTH
	tag.offset_top = -(float(FRAME_PAD) + NOW_SIZE * NOW_RISE_SHARE)
	tag.offset_bottom = tag.offset_top
	tag.visible = false
	return tag


func _show_icons(box: HBoxContainer, kinds: Array) -> void:
	while box.get_child_count() < kinds.size():
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(_icon_px, _icon_px)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(icon)
	for j: int in box.get_child_count():
		var icon := box.get_child(j) as TextureRect
		icon.visible = j < kinds.size()
		if icon.visible:
			icon.texture = _hit_icons.get(int(kinds[j])) as Texture2D
