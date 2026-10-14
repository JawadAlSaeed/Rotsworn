class_name ZoneHud
extends CanvasLayer
## The zone's screen text (DESIGN.md 7.4): the zone's name when you arrive, the controls, how many
## roaming enemies are left (in a run: the guard to beat), a "!" over every enemy chasing you, the
## name of the fight over enemies nearby, and big banners (FIRST STRIKE!, ZONE CLEAR).

const MARGIN: float = 24.0
const TITLE_SIZE: int = 72
const HINT_SIZE: int = 24
const COUNT_SIZE: int = 28
const TAG_SIZE: int = 22
const BANNER_SIZE: int = 88
const TITLE_TOP: float = 120.0
const BANNER_TOP: float = 300.0
## Share of a banner's time it stays fully visible before fading.
const HOLD_SHARE: float = 0.7
## Name tags float this far above the "!" spot (pixels).
const TAG_GAP: float = 6.0
## The pick-up hint sits this far above the bottom edge, in the middle.
const PICKUP_BOTTOM: float = 160.0

var _explore: ExploreVisuals
var _root: Control
var _title: Label
var _count: Label
var _banner: Label
var _banner_tween: Tween
## Roamer index -> {notice: Label, tag: Label}.
var _marks: Dictionary = {}
## "E Pick up" / "E Open chest", shown while a glinting spot or a chest is in reach (DESIGN.md 8.1).
var _pickup: Control
var _pickup_text: String = ""


## `run_mode`: the controls also name the backpack (Tab / Y, DESIGN.md 8.1).
func setup(explore: ExploreVisuals, zone_name: String, run_mode: bool = false) -> void:
	_explore = explore
	layer = 10
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_title = HudStyle.make_worn_title(zone_name, TITLE_SIZE)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_title.offset_top = TITLE_TOP
	_root.add_child(_title)
	_fade(_title, explore.zone_title_ms)

	_banner = HudStyle.make_worn_title("", BANNER_SIZE)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_banner.offset_top = BANNER_TOP
	_banner.visible = false
	_root.add_child(_banner)

	_count = HudStyle.make_label("", COUNT_SIZE, HudStyle.TEXT)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_count.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_count.offset_right = -MARGIN
	_count.offset_top = MARGIN
	_root.add_child(_count)

	var controls: Array = [[&"@move", "Move"], [&"field_strike", "Strike"], [&"pause", "Pause"]]
	if run_mode:
		controls.insert(2, [&"party_menu", "Backpack"])
	var hint := HintBar.stack(controls, HINT_SIZE,
			["Hit an enemy before it touches you: FIRST STRIKE"])
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.offset_left = MARGIN
	hint.offset_bottom = -MARGIN
	_root.add_child(hint)



func set_enemies_left(count: int) -> void:
	_count.text = "Enemies left: %d" % count if count > 0 else "All enemies beaten"


## A run zone's goal: the guard at the exit, and how many optional enemies are left.
func set_guard_goal(guard_beaten: bool, others_left: int) -> void:
	var goal := "The way out is open" if guard_beaten else "Beat the GUARD at the exit"
	_count.text = "%s\nOptional enemies: %d" % [goal, others_left]


## The "!" over roamer `index` at a screen position (its head), or hidden.
func set_notice(index: int, shown: bool, screen_pos: Vector2 = Vector2.ZERO) -> void:
	var mark := _mark(index)
	var notice := mark.notice as Label
	notice.visible = shown
	if shown:
		notice.reset_size()
		notice.position = screen_pos - Vector2(notice.size.x * 0.5, notice.size.y)


## The fight's name over roamer `index`, or hidden.
func set_tag(index: int, text: String, shown: bool, screen_pos: Vector2 = Vector2.ZERO,
		color: Color = HudStyle.TEXT) -> void:
	var mark := _mark(index)
	var tag := mark.tag as Label
	tag.visible = shown
	if shown:
		tag.text = text
		tag.label_settings.font_color = color
		tag.reset_size()
		var above := (mark.notice as Label).size.y if (mark.notice as Label).visible else 0.0
		tag.position = screen_pos - Vector2(tag.size.x * 0.5, tag.size.y + above + TAG_GAP)


## Big text in the middle (FIRST STRIKE!, ZONE CLEAR) for `ms` milliseconds.
## Shows the pick-up hint with this text ("" hides it).
func set_pickup_hint(text: String) -> void:
	if text == _pickup_text:
		return
	_pickup_text = text
	if _pickup != null:
		_pickup.queue_free()
		_pickup = null
	if text.is_empty():
		return
	_pickup = HintBar.entry_row(&"field_pickup", text, COUNT_SIZE, HudStyle.GOLD)
	_pickup.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_pickup.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pickup.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_pickup.offset_bottom = -PICKUP_BOTTOM
	_root.add_child(_pickup)


func banner(text: String, color: Color, ms: int) -> void:
	_banner.text = text
	_banner.label_settings.font_color = HudStyle.worn_color(color)
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_tween = _fade(_banner, ms)


func _mark(index: int) -> Dictionary:
	if not _marks.has(index):
		var notice := HudStyle.make_label("!", _explore.notice_size, _explore.notice_color)
		notice.visible = false
		_root.add_child(notice)
		var tag := HudStyle.make_label("", TAG_SIZE, HudStyle.TEXT)
		tag.visible = false
		_root.add_child(tag)
		_marks[index] = {"notice": notice, "tag": tag}
	return _marks[index]


func _fade(label: Label, ms: int) -> Tween:
	label.visible = true
	label.modulate = Color.WHITE
	var tween := label.create_tween()
	tween.tween_interval(float(ms) / 1000.0 * HOLD_SHARE)
	tween.tween_property(label, "modulate:a", 0.0, float(ms) / 1000.0 * (1.0 - HOLD_SHARE))
	tween.tween_callback(label.hide)
	return tween
