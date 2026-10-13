class_name TrailBar
extends Control
## An HP bar with a damage trail (card #38): when the value drops, the lost part stays lit in a
## pale colour for a moment, then drains away, so a big hit reads at a glance. When the value
## rises (a heal) the bar fills up smoothly instead.

var _trail: ProgressBar
var _bar: ProgressBar
var _hold_s: float = 0.35
var _drain_s: float = 0.45
var _fill_s: float = 0.3
var _value: float = -1.0
var _tween: Tween


## `fill` is the bar colour, `trail` the colour of the lost part; times in milliseconds.
func _init(fill: Color, height: float, trail: Color, hold_ms: int, drain_ms: int, fill_ms: int) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0.0, height)
	_hold_s = float(hold_ms) / 1000.0
	_drain_s = float(drain_ms) / 1000.0
	_fill_s = float(fill_ms) / 1000.0
	_trail = HudStyle.bar(trail, height)
	_trail.step = 0.0
	_trail.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_trail)
	_bar = HudStyle.bar(fill, height)
	_bar.step = 0.0
	var clear := StyleBoxEmpty.new()
	_bar.add_theme_stylebox_override("background", clear)
	_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_bar)


## Shows `value` out of `max_value` (the first call sets it at once, later ones animate).
func set_values(value: int, max_value: int) -> void:
	var top := float(maxi(1, max_value))
	_trail.max_value = top
	_bar.max_value = top
	var v := float(clampi(value, 0, maxi(1, max_value)))
	if is_equal_approx(v, _value):
		return
	var first := _value < 0.0
	var dropped := v < _value
	_value = v
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if first or not is_inside_tree():
		_bar.value = v
		_trail.value = v
		return
	if dropped:
		_bar.value = v
		_tween = create_tween()
		_tween.tween_interval(_hold_s)
		_tween.tween_property(_trail, "value", v, _drain_s).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	else:
		_trail.value = v
		_tween = create_tween()
		_tween.tween_property(_bar, "value", v, _fill_s).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func set_fill_color(color: Color) -> void:
	HudStyle.set_bar_color(_bar, color)
