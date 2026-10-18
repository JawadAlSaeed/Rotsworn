class_name ControllerNotice
extends CanvasLayer
## The "Controller recommended" screen (DESIGN.md 7.7, card #167), after the studio intro and
## before the title: the controller picture and a worn-gold heading (and an optional line) over the
## menu's background. It fades in, holds and fades out by itself; any key, button or click (after the skip
## guard) ends it early. `done` comes once. Text, icon and every time live in
## data/branding/branding.tres (BrandingData). A missing icon falls back to the placeholder.

signal done

## Room between the icon, the heading and the line (pixels on the 1920x1080 canvas).
const GAP_PX: int = 38

var _branding: BrandingData
var _root: Control
var _started_ms: int = 0
var _finished: bool = false


## Whether the notice shows at all: a hold time of 0 turns it off, and `skip_with_pad` leaves it
## out for a player whose pad is already plugged in. Pure, so it is tested.
static func is_due(branding: BrandingData, pad_connected: bool) -> bool:
	return branding.controller_hold_ms > 0 and not (branding.controller_skip_with_pad and pad_connected)


## The whole notice's length in ms (fade in, hold, fade out).
static func total_ms(branding: BrandingData) -> int:
	return branding.controller_fade_in_ms + branding.controller_hold_ms + branding.controller_fade_out_ms


func setup(branding: BrandingData) -> void:
	_branding = branding
	layer = 40
	# A black floor that never fades: without it the fade showed Godot's grey clear colour (a grey
	# flash between the intro and the title, seen in a picture run).
	var floor_rect := ColorRect.new()
	floor_rect.color = Color.BLACK
	floor_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	floor_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(floor_rect)
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_root.add_child(MenuBackdrop.new())
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", GAP_PX)
	_root.add_child(column)
	var icon := TextureRect.new()
	icon.texture = AssetLoader.texture(branding.controller_icon_path, Vector2i(32, 22))
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Drawn in the logo's worn-gold line style (tools/branding/controller_mark.py) and shown smaller
	# than its file, so smooth with mipmaps, not the pixel art's nearest filter.
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	icon.custom_minimum_size = Vector2(0.0, float(branding.controller_icon_height_px))
	column.add_child(icon)
	var heading := HudStyle.make_worn_title(branding.controller_title, branding.controller_title_size)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(heading)
	# No second line by default (user 2026-10-18: "only the yellow line is enough").
	if not branding.controller_text.is_empty():
		var line := HudStyle.make_label(branding.controller_text, branding.controller_text_size, HudStyle.TEXT_DIM)
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(line)


func _ready() -> void:
	_started_ms = Time.get_ticks_msec()
	_root.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 1.0, float(_branding.controller_fade_in_ms) / 1000.0) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_interval(float(_branding.controller_hold_ms) / 1000.0)
	tween.tween_property(_root, "modulate:a", 0.0, float(_branding.controller_fade_out_ms) / 1000.0) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(_finish)


func _input(event: InputEvent) -> void:
	if _finished or Time.get_ticks_msec() - _started_ms < _branding.controller_skip_guard_ms:
		return
	var pressed := (event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton) \
			and event.is_pressed() and not event.is_echo()
	if pressed:
		get_viewport().set_input_as_handled()
		_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	done.emit()
