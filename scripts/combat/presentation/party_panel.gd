class_name PartyPanel
extends PanelContainer
## One party member's card at the bottom left of the screen (restyled in card #154 as a slanted
## ink plate): portrait, name (title font, in the hero's accent colour), HP bar with the numbers
## drawn on it (damage trail, red when low), AP gems (up to max_ap), status line, DOWN state, co-op
## player tag, the active-turn highlight (gold edge and glow, the card steps up a little) and the
## "being attacked" highlight (red). Values come from the mirror. The three cards leave the bottom
## right corner to the action menu and the defence buttons.

const PANEL_WIDTH: float = 300.0
## The card's slant and its glow while it is this hero's turn (or they are under attack).
const CARD_HEIGHT: float = 112.0
const GLOW_PX: int = 10
const ACTIVE_SCALE: float = 1.04
const PADDING: int = 10
const PORTRAIT_PX: float = 64.0
const PORTRAIT_PAD: int = 2
const PORTRAIT_BG := Color(0.0, 0.0, 0.0, 0.45)
const NAME_SIZE: int = 26
const TAG_SIZE: int = 18
const HP_BAR_HEIGHT: float = 28.0
const HP_TEXT_SIZE: int = 22
const STATUS_SIZE: int = 18
const LOW_HP_PERCENT: int = 30
const ACTIVE_BORDER_PX: int = 4
const IDLE_BORDER_PX: int = 2
const ROW_GAP: int = 4
const COLUMN_GAP: int = 10
const GEM_GAP: int = 2
## The name is the accent lifted a little, so dark accents still read on the dark panel.
const NAME_LIGHTEN: float = 0.25
const DOWN_TINT := Color(0.6, 0.6, 0.65)
const DOWN_TEXT := "DOWN"
## A hero who ran from the fight (DESIGN.md 2.13).
const ESCAPED_TEXT := "ESCAPED"

var fighter_id: int = -1

var _style: StyleBoxFlat
var _name_label: Label
var _player_label: Label
var _hp_bar: TrailBar
var _hp_text: Label
var _status_label: Label
## The hero debuffs (rot, blight, weakness) with their turns left, each in its own colour (card #194).
var _debuff_box: BoxContainer
var _debuff_key: String = ""
var _pips: Array[TextureRect] = []
var _pip_full: Texture2D
var _pip_empty: Texture2D
var _active: bool = false
var _targeted: bool = false
## Whether the card is (or is growing to be) stepped up for this hero's turn.
var _lifted: bool = false


## `portrait` is the hero's face (null leaves the frame empty).
func setup(id: int, display_name: String, accent: Color, portrait: Texture2D, max_ap: int,
		visuals: CombatVisuals) -> void:
	fighter_id = id
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	_style = HudStyle.slant(HudStyle.INK, HudStyle.EDGE_DIM, IDLE_BORDER_PX, PADDING, CARD_HEIGHT, 0.12)
	add_theme_stylebox_override("panel", _style)
	_pip_full = AssetLoader.texture(visuals.ap_pip_path, Vector2i(10, 10))
	_pip_empty = AssetLoader.texture(visuals.ap_pip_empty_path, Vector2i(10, 10))

	var column := _box(VBoxContainer.new(), ROW_GAP)
	add_child(column)
	var top := _box(HBoxContainer.new(), COLUMN_GAP)
	column.add_child(top)
	top.add_child(_make_portrait(portrait, accent))
	var info := _box(VBoxContainer.new(), ROW_GAP)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(info)

	var name_row := _box(HBoxContainer.new(), COLUMN_GAP)
	info.add_child(name_row)
	_name_label = HudStyle.make_title(display_name, NAME_SIZE, accent.lightened(NAME_LIGHTEN))
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_row.add_child(_name_label)
	_player_label = HudStyle.make_label("", TAG_SIZE)
	_player_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_player_label.visible = false
	name_row.add_child(_player_label)

	_hp_bar = TrailBar.new(HudStyle.HP_FILL, HP_BAR_HEIGHT, visuals.hp_trail_color, visuals.hp_trail_hold_ms,
			visuals.hp_trail_drain_ms, visuals.heal_fill_ms)
	_hp_text = HudStyle.make_number("", HP_TEXT_SIZE)
	info.add_child(PartyPanel.text_on_bar(_hp_bar, _hp_text))

	var gems := _box(HBoxContainer.new(), GEM_GAP)
	info.add_child(gems)
	var gem_px := _gem_px(visuals.ap_pip_px, max_ap)
	for i: int in max_ap:
		var pip := TextureRect.new()
		pip.custom_minimum_size = Vector2(gem_px, gem_px)
		pip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pip.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pip.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.texture = _pip_empty
		gems.add_child(pip)
		_pips.append(pip)

	# Full panel width, so a few statuses fit; an empty label keeps its line, so the panel does
	# not change height when a status comes or goes.
	var status_row := _box(HBoxContainer.new(), COLUMN_GAP)
	column.add_child(status_row)
	_debuff_box = _box(HBoxContainer.new(), COLUMN_GAP)
	status_row.add_child(_debuff_box)
	_status_label = HudStyle.make_label("", STATUS_SIZE, HudStyle.GOLD)
	_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_child(_status_label)


## `bar` with `text` drawn centred on top of it (HP and gauge numbers on their bars); add the
## returned container where the bar would go.
static func text_on_bar(bar: Control, text: Label) -> MarginContainer:
	var stack := MarginContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(bar)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stack.add_child(text)
	return stack


## Updates from a mirror fighter dictionary.
func refresh(f: Dictionary, active: bool) -> void:
	if f.is_empty():
		return
	var hp := int(f.hp)
	var max_hp := maxi(1, int(f.max_hp))
	var ap := int(f.ap)
	var alive := bool(f.alive)
	_hp_bar.set_values(hp, max_hp)
	_hp_bar.set_fill_color(HudStyle.HP_LOW if hp * 100 <= max_hp * LOW_HP_PERCENT else HudStyle.HP_FILL)
	var escaped := bool(f.get("escaped", false))
	_hp_text.text = "%d / %d" % [hp, max_hp] if alive else (ESCAPED_TEXT if escaped else DOWN_TEXT)
	_hp_text.label_settings.font_color = HudStyle.TEXT if alive else (HudStyle.JUMP if escaped else HudStyle.HP_LOW)
	for i: int in _pips.size():
		_pips[i].texture = _pip_full if i < ap else _pip_empty
	var statuses := f.get("statuses", {}) as Dictionary
	_status_label.text = HudStyle.status_text(statuses, true)
	_show_debuffs(HudStyle.debuff_words(statuses))
	modulate = Color.WHITE if alive else DOWN_TINT
	_active = active
	_apply_border()


## Rebuilds the debuff words ([[id, "ROT 2"], ...]) only when they changed.
func _show_debuffs(words: Array[Array]) -> void:
	var key := str(words)
	if key == _debuff_key:
		return
	_debuff_key = key
	for child: Node in _debuff_box.get_children():
		_debuff_box.remove_child(child)
		child.queue_free()
	for word: Array in words:
		_debuff_box.add_child(HudStyle.make_label(String(word[1]), STATUS_SIZE,
				HudStyle.STATUS_COLORS.get(String(word[0]), HudStyle.TEXT) as Color))


## Shows which co-op player controls this character (player < 0 hides the tag).
func set_player(player: int) -> void:
	_player_label.visible = player >= 0
	if player >= 0:
		_player_label.text = HudStyle.player_tag(player)
		_player_label.label_settings.font_color = HudStyle.player_color(player)


## Red border while an enemy attack targets this character.
func set_targeted(targeted: bool) -> void:
	_targeted = targeted
	_apply_border()


func _apply_border() -> void:
	var color := HudStyle.EDGE_DIM
	if _targeted:
		color = HudStyle.LATE
	elif _active:
		color = HudStyle.GOLD
	var lit := _targeted or _active
	_style.border_color = color
	_style.set_border_width_all(ACTIVE_BORDER_PX if lit else IDLE_BORDER_PX)
	_style.border_width_left = ACTIVE_BORDER_PX * 2 if lit else IDLE_BORDER_PX
	# A lit card glows in its colour instead of the usual hard ink shadow.
	_style.shadow_color = Color(color, 0.55) if lit else HudStyle.PLATE_SHADOW
	_style.shadow_size = GLOW_PX if lit else 1
	_style.shadow_offset = Vector2.ZERO if lit else HudStyle.PLATE_SHADOW_OFFSET
	pivot_offset = Vector2(size.x * 0.5, size.y)
	if _lifted != _active:
		_lifted = _active
		var wanted := Vector2.ONE * (ACTIVE_SCALE if _active else 1.0)
		create_tween().tween_property(self, "scale", wanted, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _make_portrait(texture: Texture2D, accent: Color) -> PanelContainer:
	return HudStyle.portrait_frame(texture, accent, PORTRAIT_PX, PORTRAIT_PAD, PORTRAIT_BG)


## The gem size: visuals ap_pip_px, made smaller when max_ap gems would not fit beside the
## portrait.
static func _gem_px(wanted: float, count: int) -> float:
	if count <= 0:
		return wanted
	var room := PANEL_WIDTH - 2.0 * PADDING - PORTRAIT_PX - 2.0 * PORTRAIT_PAD - COLUMN_GAP
	return minf(wanted, floorf((room - GEM_GAP * (count - 1)) / float(count)))


static func _box(box: BoxContainer, gap: int) -> BoxContainer:
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", gap)
	return box
