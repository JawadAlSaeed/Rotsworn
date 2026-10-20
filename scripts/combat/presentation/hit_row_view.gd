class_name HitRowView
extends Control
## A row of an enemy attack's hit icons spaced by time (HitRhythm.layout), joined by a faint
## line, so the beat and the pauses of a string read at a glance (DESIGN.md 3.8). Used on the
## intent sign and in the attack banner. During the attack each icon shows its HitRhythm.State:
## upcoming as is, active bigger, done faded. A feint's icon wears a broken ring (card #129), so
## players know a false start is coming; a hit that leaves a mark wears that mark's icon on its
## lower right corner (phase 22; HudStyle.mark_icon), so the intent needs no mark words.

## A mark with no icon gets a dot in its colour instead: its radius as a share of the hit icon.
const MARK_DOT_SHARE: float = 0.24
## How far the mark icon's centre sits inside the hit icon's corner, as a share of the mark icon.
const MARK_INSET_SHARE: float = 0.2
## The hit-icon key of a thrown hit (card #278), next to the AttackHitData.Kind keys.
const RANGED_ICON: int = -1

## The widest the row may get (0: the visuals' rhythm_max_width_px). The enemy panels' intent row
## stays narrower than their HP bar, so a long attack never stretches the panel (card #279).
var max_width_px: float = 0.0
var _icon_px: float = 30.0
## Rows that show an active hit are tall enough for it to grow without moving the row.
var _room_to_grow: bool = false
var _visuals: CombatVisuals
var _textures: Array[Texture2D] = []
var _feints: Array[bool] = []
## Per hit: the mark it leaves ("" = none; a debuff id or Status.MARK_AP_DRAIN), card #194.
var _marks: Array[String] = []
var _centres := PackedFloat32Array()
var _states: Array[int] = []


## `room_to_grow`: the row will show an active (grown) icon, as in the attack banner.
func setup(icon_px: float, visuals: CombatVisuals, room_to_grow: bool = false) -> void:
	_icon_px = icon_px
	_room_to_grow = room_to_grow
	_visuals = visuals
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## One icon per hit: `kinds` are AttackHitData.Kind values, `times` their impacts (ms), and
## `hit_icons` maps an icon_key to its texture; `feints` says which hits are feints (empty: none);
## `marks` the mark each hit leaves (empty: none do); `ranged` which hits are thrown (empty: none
## are). Every hit starts UPCOMING.
func set_hits(kinds: Array, times: Array, hit_icons: Dictionary, feints: Array = [], marks: Array = [],
		ranged: Array = []) -> void:
	_textures.clear()
	_feints.clear()
	_marks.clear()
	for i: int in kinds.size():
		var thrown := i < ranged.size() and bool(ranged[i])
		_textures.append(hit_icons.get(icon_key(int(kinds[i]), thrown)) as Texture2D)
		_feints.append(i < feints.size() and bool(feints[i]))
		_marks.append(String(marks[i]) if i < marks.size() else "")
	_centres = HitRhythm.layout(times, _icon_px, _visuals.rhythm_px_per_ms, _visuals.rhythm_min_gap_px,
			max_width_px if max_width_px > 0.0 else _visuals.rhythm_max_width_px)
	_states.clear()
	var height := _icon_px * (_visuals.rhythm_active_scale if _room_to_grow else 1.0)
	custom_minimum_size = Vector2(HitRhythm.row_width(_centres, _icon_px), height)
	size = custom_minimum_size
	queue_redraw()


## The mark icon each hit wears (null: it leaves no mark, or its mark has no icon and shows a dot).
func mark_textures() -> Array[Texture2D]:
	var list: Array[Texture2D] = []
	for mark: String in _marks:
		list.append(null if mark.is_empty() else HudStyle.mark_icon(mark))
	return list


## HitRhythm.State per hit (empty: all upcoming). Redraws only when something changed.
func set_states(states: Array[int]) -> void:
	if states == _states:
		return
	_states = states.duplicate()
	queue_redraw()


## The hit-icon key of a hit (card #278): a thrown normal hit shows the ranged icon so the throw
## reads before the wind-up; any other hit its kind's icon. A thrown rend or sweep keeps its own,
## since its one right button matters more than how it travels.
static func icon_key(kind: int, ranged: bool) -> int:
	return RANGED_ICON if ranged and kind == AttackHitData.Kind.NORMAL else kind


## Every hit icon (12x12) by icon_key, from the paths in `visuals`.
static func load_icons(visuals: CombatVisuals) -> Dictionary:
	var size := Vector2i(12, 12)
	return {
		AttackHitData.Kind.NORMAL: AssetLoader.texture(visuals.hit_icon_normal_path, size),
		AttackHitData.Kind.GROUND: AssetLoader.texture(visuals.hit_icon_ground_path, size),
		AttackHitData.Kind.REND: AssetLoader.texture(visuals.hit_icon_rend_path, size),
		AttackHitData.Kind.SWEEP: AssetLoader.texture(visuals.hit_icon_sweep_path, size),
		RANGED_ICON: AssetLoader.texture(visuals.hit_icon_ranged_path, size),
	}


func _draw() -> void:
	if _centres.is_empty():
		return
	var mid := size.y * 0.5
	if _centres.size() > 1:
		draw_line(Vector2(_centres[0], mid), Vector2(_centres[_centres.size() - 1], mid), _visuals.rhythm_line_color, 2.0)
	var active := HitRhythm.active_hit(_states)
	for i: int in _centres.size():
		if i != active:
			_draw_icon(i, mid)
	# The grown active icon goes on top of its neighbours in a tight string.
	if active >= 0:
		_draw_icon(active, mid)


func _draw_icon(i: int, mid: float) -> void:
	var texture := _textures[i] if i < _textures.size() else null
	if texture == null:
		return
	var state := _states[i] if i < _states.size() else HitRhythm.State.UPCOMING
	var px := _icon_px
	var tint := Color.WHITE
	match state:
		HitRhythm.State.ACTIVE:
			px *= _visuals.rhythm_active_scale
		HitRhythm.State.DONE:
			tint = Color(1.0, 1.0, 1.0, _visuals.rhythm_done_alpha)
	draw_texture_rect(texture, Rect2(Vector2(_centres[i] - px * 0.5, mid - px * 0.5), Vector2(px, px)), false, tint)
	if i < _feints.size() and _feints[i]:
		_draw_feint_ring(Vector2(_centres[i], mid), px, tint.a)
	if i < _marks.size() and not _marks[i].is_empty():
		_draw_mark(Vector2(_centres[i], mid), px, tint.a, _marks[i])


## The mark's icon on the hit icon's lower right corner (visuals hit_mark_icon_share of its size):
## this hit leaves that mark (rot, burn, daze, an AP drain...) if it lands. A mark with no icon
## gets a dot in its colour.
func _draw_mark(centre: Vector2, px: float, alpha: float, mark: String) -> void:
	var icon := HudStyle.mark_icon(mark)
	if icon != null:
		var side := px * _visuals.hit_mark_icon_share
		var middle := centre + Vector2(px, px) * 0.5 - Vector2(side, side) * MARK_INSET_SHARE
		draw_texture_rect(icon, Rect2(middle - Vector2(side, side) * 0.5, Vector2(side, side)), false,
				Color(1.0, 1.0, 1.0, alpha))
		return
	var color := HudStyle.STATUS_COLORS.get(mark, HudStyle.TEXT) as Color
	color.a *= alpha
	var radius := maxf(3.0, px * MARK_DOT_SHARE)
	var at := centre + Vector2(px, px) * 0.5 - Vector2(radius, radius) * 0.5
	draw_circle(at, radius, Color(0.03, 0.025, 0.04, 0.9 * alpha))
	draw_circle(at, radius * 0.72, color)


## A dashed ring around a feint's icon: a broken outline for a broken rhythm.
func _draw_feint_ring(centre: Vector2, px: float, alpha: float) -> void:
	var color := _visuals.rhythm_feint_color
	color.a *= alpha
	var radius := px * 0.5 * _visuals.rhythm_feint_ring_scale
	var dashes := maxi(2, _visuals.rhythm_feint_dashes)
	var step := TAU / float(dashes)
	for d: int in dashes:
		var start := float(d) * step
		draw_arc(centre, radius, start, start + step * 0.55, 6, color, _visuals.rhythm_feint_ring_px, true)
