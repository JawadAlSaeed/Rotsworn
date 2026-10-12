class_name ScreenTransition
extends CanvasLayer
## Full-screen transitions (DESIGN.md 7.4), above every HUD. Into a fight: the current picture is
## frozen and swirls into black (swirl_out), then the fight fades in from black (fade_in). Back to
## a zone: fade to black (fade_out), then fade in. Each call can be awaited. Real time.

const SWIRL_SHADER := preload("res://scripts/stage/swirl.gdshader")

var _explore: ExploreVisuals
var _picture: TextureRect
var _black: ColorRect


func setup(explore: ExploreVisuals) -> void:
	_explore = explore
	layer = 60
	_picture = TextureRect.new()
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_SCALE
	var mat := ShaderMaterial.new()
	mat.shader = SWIRL_SHADER
	mat.set_shader_parameter("turns", explore.swirl_turns)
	mat.set_shader_parameter("flash", explore.transition_flash)
	_picture.material = mat
	_picture.visible = false
	add_child(_picture)
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.modulate.a = 0.0
	_black.visible = false
	add_child(_black)


## Freezes the screen and swirls it into black over transition_out_ms.
func swirl_out() -> void:
	var seconds := float(_explore.transition_out_ms) / 1000.0
	# Headless runs have no picture to read back.
	var image: Image = null
	if DisplayServer.get_name() != "headless":
		image = get_viewport().get_texture().get_image()
	if image != null and not image.is_empty():
		_picture.texture = ImageTexture.create_from_image(image)
		var mat := _picture.material as ShaderMaterial
		mat.set_shader_parameter("aspect", float(image.get_width()) / float(maxi(1, image.get_height())))
		mat.set_shader_parameter("progress", 0.0)
		_picture.visible = true
		var tween := create_tween()
		tween.tween_method(func(p: float) -> void: mat.set_shader_parameter("progress", p), 0.0, 1.0, seconds)
		await tween.finished
	else:
		# No picture to swirl (headless): just fade.
		await _fade_black(1.0, seconds)
	_black.visible = true
	_black.modulate.a = 1.0
	_picture.visible = false


## Fades to black over transition_in_ms.
func fade_out() -> void:
	await _fade_black(1.0, float(_explore.transition_in_ms) / 1000.0)


## Fades from black over transition_in_ms.
func fade_in() -> void:
	_picture.visible = false
	await _fade_black(0.0, float(_explore.transition_in_ms) / 1000.0)
	_black.visible = false


func _fade_black(to_alpha: float, seconds: float) -> void:
	_black.visible = true
	var tween := create_tween()
	tween.tween_property(_black, "modulate:a", to_alpha, seconds)
	await tween.finished
