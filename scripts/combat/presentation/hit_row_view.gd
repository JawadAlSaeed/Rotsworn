class_name HitRowView
extends Control
## A row of an enemy attack's hit icons spaced by time (HitRhythm.layout), joined by a faint
## line, so the beat and the pauses of a string read at a glance (DESIGN.md 3.8). Used on the
## intent sign and in the attack banner. During the attack each icon shows its HitRhythm.State:
## upcoming as is, active bigger, done faded. A feint's icon wears a broken ring (card #129), so
## players know a false start is coming.

var _icon_px: float = 30.0
## Rows that show an active hit are tall enough for it to grow without moving the row.
var _room_to_grow: bool = false
var _visuals: CombatVisuals
var _textures: Array[Texture2D] = []
var _feints: Array[bool] = []
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
## `hit_icons` maps a kind to its texture; `feints` says which hits are feints (empty: none).
## Every hit starts UPCOMING.
func set_hits(kinds: Array, times: Array, hit_icons: Dictionary, feints: Array = []) -> void:
	_textures.clear()
	_feints.clear()
	for i: int in kinds.size():
		_textures.append(hit_icons.get(int(kinds[i])) as Texture2D)
		_feints.append(i < feints.size() and bool(feints[i]))
	_centres = HitRhythm.layout(times, _icon_px, _visuals.rhythm_px_per_ms, _visuals.rhythm_min_gap_px,
			_visuals.rhythm_max_width_px)
	_states.clear()
	var height := _icon_px * (_visuals.rhythm_active_scale if _room_to_grow else 1.0)
	custom_minimum_size = Vector2(HitRhythm.row_width(_centres, _icon_px), height)
	size = custom_minimum_size
	queue_redraw()


## HitRhythm.State per hit (empty: all upcoming). Redraws only when something changed.
func set_states(states: Array[int]) -> void:
	if states == _states:
		return
	_states = states.duplicate()
	queue_redraw()


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
