class_name TimelineRow
extends HBoxContainer
## The turn order row (top left): the current actor first and highlighted, then the next turns
## from mirror.turn_order. Portraits and names come from the fighters' data. Under each enemy's
## next turn, one icon per hit of its intended attack (DESIGN.md 2.8).

const CURRENT_BORDER_PX: int = 4
const OTHER_BORDER_PX: int = 2
const CURRENT_SCALE: float = 1.3
const NAME_SIZE: int = 18
## Name width, as a multiple of the portrait size.
const NAME_WIDTH_FACTOR: float = 2.0

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
	add_theme_constant_override("separation", 10)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i: int in count:
		var box := VBoxContainer.new()
		box.alignment = BoxContainer.ALIGNMENT_END
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_constant_override("separation", 2)
		var frame := PanelContainer.new()
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var style := HudStyle.panel(HudStyle.PANEL_BG, HudStyle.PANEL_BORDER, OTHER_BORDER_PX, 3)
		frame.add_theme_stylebox_override("panel", style)
		var portrait := TextureRect.new()
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(portrait)
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
		add_child(box)
		_entries.append({"box": box, "frame": frame, "style": style, "portrait": portrait, "label": label, "icons": icons})


## Shows `order` (combatant ids, current actor first). `portraits` and `colors` map id -> value.
func show_order(order: Array[int], mirror: CombatMirror, portraits: Dictionary, colors: Dictionary) -> void:
	for i: int in _entries.size():
		var e: Dictionary = _entries[i]
		var box: VBoxContainer = e.box
		if i >= order.size():
			box.visible = false
			continue
		box.visible = true
		var id := order[i]
		var current := i == 0 and id == mirror.active_actor
		var px := _portrait_px * (CURRENT_SCALE if current else 1.0)
		var portrait: TextureRect = e.portrait
		portrait.custom_minimum_size = Vector2(px, px)
		portrait.texture = portraits.get(id) as Texture2D
		var style: StyleBoxFlat = e.style
		style.border_color = HudStyle.GOLD if current else (colors.get(id, HudStyle.PANEL_BORDER) as Color)
		style.set_border_width_all(CURRENT_BORDER_PX if current else OTHER_BORDER_PX)
		var label: Label = e.label
		label.text = String(mirror.fighter(id).get("display_name", "?"))
		label.label_settings.font_color = HudStyle.GOLD if current else HudStyle.TEXT
		var kinds: Array = []
		if mirror.intents.has(id) and order.find(id) == i:
			kinds = (mirror.intents[id] as Dictionary).get("kinds", [])
		_show_icons(e.icons as HBoxContainer, kinds)


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
