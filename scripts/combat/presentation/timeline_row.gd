class_name TimelineRow
extends Control
## The turn order: a turn track down the left edge (card #154; a column since 2026-10-16, so the
## top of the screen is free for the attack banner, clear of the enemies' throws). A thin gold
## track runs down the side with a marker per turn; each turn is just a slanted portrait card, like
## Expedition 33's (user, 2026-10-16: no names, HP or intent here; the cards and panels show those).
## The current actor steps out of the column, bigger, glowing, with a gold NOW ribbon; later turns
## fade back. Enemies wear red, heroes their own colour. When a turn ends
## the column slides up one place and the old leader slides off to the left.

const CURRENT_SCALE: float = 1.35
## The track's line and its markers, then the cards to the right of it.
const SPINE_X: float = 10.0
const ENTRY_X: float = 26.0
## The current turn's card stands this far out of the column.
const STEP_OUT: float = 12.0
const ENTRY_GAP: float = 8.0
const PAD_TOP: float = 14.0
const PAD_BOTTOM: float = 12.0
## The dark band behind the column fades out over this width.
const BAND_WIDTH: float = 150.0
const BAND_COLOR := Color(0.0, 0.0, 0.0, 0.62)
const CURRENT_BORDER_PX: int = 3
const OTHER_BORDER_PX: int = 2
const CARD_SLANT: float = 0.1
## The Doom tag on an enemy's card (card #195): its countdown, DOOM on the turn it unleashes, or
## STAGGER on the turn it will lose.
const TAG_SIZE: int = 13
const TAG_DOOM := "DOOM"
const TAG_STAGGER := "STAGGER"
const TAG_TEXT_COLOR := Color(0.07, 0.04, 0.04)
const NOW_TEXT := "NOW"
const NOW_SIZE: int = 14
const NOW_TEXT_COLOR := Color(0.12, 0.08, 0.02)
## Turns after the current one fade back a little each, down to this.
const LATER_FADE_STEP: float = 0.07
const LATER_FADE_MIN: float = 0.65
const ENEMY_FRAME_BG := Color(0.24, 0.05, 0.05, 0.9)
## Markers on the track: radius for a turn, and for the current one.
const MARK_PX: float = 4.0
const MARK_NOW_PX: float = 7.0
## The slide when a turn ends.
const SLIDE_S: float = 0.3
const POP_S: float = 0.22
const LEAVE_PX: float = 70.0

var _entries: Array[Dictionary] = []
var _portrait_px: float = 48.0
## What was shown at the front last time (to see when a turn ended).
var _first_id: int = -1
var _first_turn: int = -1
## How many turns are shown now (for _draw).
var _shown: int = 0


## `count` turns are shown, portraits `portrait_px` big (the current one bigger).
func setup(count: int, portrait_px: float) -> void:
	_portrait_px = portrait_px
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i: int in count:
		_entries.append(_make_entry())


## Shows `order` (combatant ids, current actor first). `portraits` and `colors` map id -> value.
func show_order(order: Array[int], mirror: CombatMirror, portraits: Dictionary, colors: Dictionary) -> void:
	visible = not order.is_empty()
	var advanced := not order.is_empty() and _first_id >= 0 \
			and (order[0] != _first_id or mirror.turn != _first_turn)
	if advanced and is_inside_tree():
		_leave(_entries[0])
	var y := PAD_TOP
	var slot_h := 0.0
	_shown = 0
	for i: int in _entries.size():
		var e: Dictionary = _entries[i]
		var holder: Control = e.holder
		if i >= order.size():
			holder.visible = false
			continue
		holder.visible = true
		_shown += 1
		var id := order[i]
		var current := i == 0 and id == mirror.active_actor
		var enemy := not mirror.party_ids.has(id)
		_fill_entry(e, id, current, enemy, portraits, colors)
		_fill_tag(e, doom_tag(order, i, mirror))
		var size_now := _layout_entry(e)
		var target := Vector2(ENTRY_X + (STEP_OUT if current else 0.0), y)
		e["side"] = _side_color(id, enemy, colors)
		e["current"] = current
		holder.modulate.a = 1.0 if current else maxf(LATER_FADE_MIN, 1.0 - LATER_FADE_STEP * float(i))
		if i == 1:
			slot_h = size_now.y + ENTRY_GAP
		if advanced and is_inside_tree():
			_slide(e, target, slot_h if slot_h > 0.0 else size_now.y + ENTRY_GAP, current)
		else:
			holder.position = target
		y += size_now.y + ENTRY_GAP
	_first_id = order[0] if not order.is_empty() else -1
	_first_turn = mirror.turn
	custom_minimum_size = Vector2(BAND_WIDTH, y - ENTRY_GAP + PAD_BOTTOM)
	size = custom_minimum_size
	queue_redraw()


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


## The tag for turn `index` of `order` (card #195): for an enemy gathering a Doom, the turns before
## the unleash count down (the number is the turns until the Doom, counting that one) and the
## unleash turn reads DOOM; the next turn of a staggered enemy reads STAGGER. The enemy's turn in
## progress is not tagged. "" for every other turn.
static func doom_tag(order: Array[int], index: int, mirror: CombatMirror) -> String:
	var id := order[index]
	if mirror.party_ids.has(id) or not mirror.is_alive(id):
		return ""
	if index == 0 and id == mirror.active_actor:
		return ""
	var nth := 0
	for i: int in range(index + 1):
		if order[i] == id and not (i == 0 and id == mirror.active_actor):
			nth += 1
	var left := int(mirror.fighter(id).get("charge_left", 0))
	if left > 0:
		if nth > left:
			return ""
		return TAG_DOOM if nth == left else str(left - nth + 1)
	if nth > 0 and int(mirror.fighter(id).get("staggered", 0)) >= nth:
		return TAG_STAGGER
	return ""


## The dark band fading to the right, the gold track and a marker beside each turn.
func _draw() -> void:
	if _shown == 0:
		return
	var h := size.y
	var clear := Color(BAND_COLOR, 0.0)
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(BAND_WIDTH, 0.0), Vector2(BAND_WIDTH, h), Vector2(0.0, h)]),
			PackedColorArray([BAND_COLOR, clear, clear, BAND_COLOR]))
	var marks: Array[Vector2] = []
	for i: int in _shown:
		var e: Dictionary = _entries[i]
		var holder: Control = e.holder
		var frame: Control = e.frame
		marks.append(Vector2(SPINE_X, holder.position.y + frame.position.y + frame.size.y * 0.5))
	if marks.size() > 1:
		draw_line(marks[0], marks[marks.size() - 1], HudStyle.EDGE_DIM, 2.0, true)
	for i: int in marks.size():
		var e: Dictionary = _entries[i]
		var holder: Control = e.holder
		var current := bool(e.get("current", false))
		var color: Color = HudStyle.GOLD if current else (e.get("side", HudStyle.EDGE) as Color)
		color.a *= holder.modulate.a
		var r := MARK_NOW_PX if current else MARK_PX
		var c := marks[i]
		if current:
			draw_circle(c, r + 5.0, Color(HudStyle.GOLD, 0.25))
			# A short gold arm from the track to the card that stepped out.
			draw_line(c, Vector2(holder.position.x, c.y), Color(HudStyle.GOLD, 0.8), 2.0, true)
		var diamond := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
		draw_colored_polygon(diamond, color)
		draw_polyline(diamond + PackedVector2Array([diamond[0]]), Color(0.0, 0.0, 0.0, 0.7 * holder.modulate.a), 1.5, true)


# --- one turn ------------------------------------------------------------------------------------

func _make_entry() -> Dictionary:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	var frame := PanelContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(frame)
	var portrait := TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(portrait)
	var now := _make_now_tag()
	holder.add_child(now)
	var tag := PanelContainer.new()
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.visible = false
	var tag_label := HudStyle.make_title("", TAG_SIZE, TAG_TEXT_COLOR)
	tag_label.label_settings.outline_size = 0
	tag.add_child(tag_label)
	holder.add_child(tag)
	return {"holder": holder, "frame": frame, "portrait": portrait, "now": now, "tag": tag, "tag_label": tag_label}


func _fill_entry(e: Dictionary, id: int, current: bool, enemy: bool, portraits: Dictionary,
		colors: Dictionary) -> void:
	var px := _portrait_px * (CURRENT_SCALE if current else 1.0)
	var portrait: TextureRect = e.portrait
	portrait.custom_minimum_size = Vector2(px, px)
	portrait.texture = portraits.get(id) as Texture2D
	var side := _side_color(id, enemy, colors)
	var card := HudStyle.slant(ENEMY_FRAME_BG if enemy else HudStyle.INK_SOLID, HudStyle.GOLD if current else side,
			CURRENT_BORDER_PX if current else OTHER_BORDER_PX, 3, px, CARD_SLANT)
	if current:
		card.shadow_color = Color(HudStyle.GOLD, 0.5)
		card.shadow_size = 9
		card.shadow_offset = Vector2.ZERO
	else:
		card.shadow_offset = Vector2(3.0, 3.0)
	(e.frame as PanelContainer).add_theme_stylebox_override("panel", card)
	(e.now as Control).visible = current


## Shows or hides the Doom tag of one entry.
func _fill_tag(e: Dictionary, text: String) -> void:
	var tag: PanelContainer = e.tag
	tag.visible = not text.is_empty()
	if text.is_empty():
		return
	var color := HudStyle.JUMP if text == TAG_STAGGER else HudStyle.LATE
	(e.tag_label as Label).text = text
	tag.add_theme_stylebox_override("panel", HudStyle.slant(color, HudStyle.OUTLINE_COLOR, 1, 1, 18.0))


## Places the parts of one turn inside its holder; returns the holder's size.
func _layout_entry(e: Dictionary) -> Vector2:
	var frame: PanelContainer = e.frame
	var now: PanelContainer = e.now
	frame.reset_size()
	frame.position = Vector2.ZERO
	now.reset_size()
	now.position = Vector2(-4.0, -now.size.y * 0.55)
	var tag: PanelContainer = e.tag
	tag.reset_size()
	tag.position = Vector2(frame.size.x - tag.size.x + 8.0, frame.size.y - tag.size.y * 0.55)
	var holder: Control = e.holder
	holder.size = frame.size
	holder.pivot_offset = frame.size * 0.5
	return holder.size


func _side_color(id: int, enemy: bool, colors: Dictionary) -> Color:
	return HudStyle.LATE if enemy else (colors.get(id, HudStyle.EDGE) as Color)


## A small slanted gold NOW ribbon over the current card's top-left corner.
func _make_now_tag() -> PanelContainer:
	var tag := PanelContainer.new()
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := HudStyle.slant(HudStyle.GOLD, HudStyle.OUTLINE_COLOR, 1, 1, 20.0)
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	tag.add_theme_stylebox_override("panel", style)
	var label := HudStyle.make_title(NOW_TEXT, NOW_SIZE, NOW_TEXT_COLOR)
	# Dark text on gold: an outline would only blur it.
	label.label_settings.outline_size = 0
	tag.add_child(label)
	tag.visible = false
	return tag


# --- motion ------------------------------------------------------------------------------------

## A turn ended: every card glides up from one place lower; the new current one pops a little.
func _slide(e: Dictionary, target: Vector2, from_below: float, current: bool) -> void:
	var holder: Control = e.holder
	var running: Tween = e.get("tween")
	if running != null and running.is_valid():
		running.kill()
	holder.scale = Vector2.ONE
	holder.position = Vector2(ENTRY_X, target.y + from_below)
	var tween := holder.create_tween().set_parallel(true)
	tween.tween_property(holder, "position", target, SLIDE_S).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if current:
		holder.scale = Vector2(0.86, 0.86)
		tween.tween_property(holder, "scale", Vector2.ONE, POP_S).set_delay(SLIDE_S * 0.5) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	e["tween"] = tween


## The turn that just ended slides off to the left and fades (a picture of its card, so the real
## entry can take its new place at once).
func _leave(e: Dictionary) -> void:
	var frame: PanelContainer = e.frame
	var portrait: TextureRect = e.portrait
	if portrait.texture == null or not (e.holder as Control).visible:
		return
	var ghost := TextureRect.new()
	ghost.texture = portrait.texture
	ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.size = portrait.size
	ghost.position = (e.holder as Control).position + frame.position + portrait.position
	add_child(ghost)
	var tween := ghost.create_tween().set_parallel(true)
	tween.tween_property(ghost, "position:x", ghost.position.x - LEAVE_PX, SLIDE_S).set_trans(Tween.TRANS_CUBIC) \
			.set_ease(Tween.EASE_IN)
	tween.tween_property(ghost, "modulate:a", 0.0, SLIDE_S)
	tween.chain().tween_callback(ghost.queue_free)
