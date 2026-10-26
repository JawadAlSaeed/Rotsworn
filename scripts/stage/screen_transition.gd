class_name ScreenTransition
extends CanvasLayer
## Full-screen transitions (DESIGN.md 7.4), above every HUD. Into a fight: the current picture is
## frozen and swirls into black (swirl_out), then the fight fades in from black (fade_in). Between
## other screens: fade to black (fade_out), then fade in. Each call can be awaited. Real time. The
## timings are CombatVisuals' Screen transitions group.
## Over the black, a loading card can show a tip (show_tip / hide_tip, DESIGN.md 7.7, card #86).
## While anything of it covers the screen, no input reaches what is behind (card #132).

const SWIRL_SHADER := preload("res://scripts/stage/swirl.gdshader")
const TIP_WIDTH_PX: float = 1200.0
const CARD_MARGIN_PX: float = 32.0

var _look: CombatVisuals
var _picture: TextureRect
var _black: ColorRect
var _tips: TipSet
var _logo_path: String = ""
var _card: Control
var _last_tip: int = -1


func setup(look: CombatVisuals) -> void:
	_look = look
	layer = 60
	_picture = TextureRect.new()
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_SCALE
	var mat := ShaderMaterial.new()
	mat.shader = SWIRL_SHADER
	mat.set_shader_parameter("turns", look.swirl_turns)
	mat.set_shader_parameter("flash", look.transition_flash)
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
	var seconds := float(_look.transition_out_ms) / 1000.0
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
	await _fade_black(1.0, float(_look.transition_in_ms) / 1000.0)


## Fades from black over transition_in_ms.
func fade_in() -> void:
	_picture.visible = false
	await _fade_black(0.0, float(_look.transition_in_ms) / 1000.0)
	_black.visible = false


## True while the black, the swirl or a loading card covers the screen.
func is_covering() -> bool:
	return (_black.visible and _black.modulate.a > 0.0) or _picture.visible or _card != null


## Eats every press, click and stick move while covering, so no button behind the loading card
## can be used. _input runs before any screen's GUI and _unhandled_input.
func _input(event: InputEvent) -> void:
	if _black != null and is_covering():
		get_viewport().set_input_as_handled()


## The tips and the logo for loading cards (without them show_tip does nothing).
func setup_tips(tips: TipSet, logo_path: String) -> void:
	_tips = tips
	_logo_path = logo_path


## Shows a loading card over the black (call after fade_out or swirl_out): `title` (the place's
## name) and a random tip, never the same twice in a row. `extra` (any control; the First Strike ring
## sat here until card #335 moved it into the fight) goes on the card under the title; with it the
## card shows even without tips.
func show_tip(title: String, extra: Control = null) -> void:
	var tips := _card_tips()
	if tips.tips.is_empty() and extra == null:
		return
	var tip := ""
	if not tips.tips.is_empty():
		var pick := randi() % tips.tips.size()
		if pick == _last_tip and tips.tips.size() > 1:
			pick = (pick + 1) % tips.tips.size()
		_last_tip = pick
		tip = tips.tips[pick]
	_card = _build_card(title, tip, extra)
	add_child(_card)
	_card.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_card, "modulate:a", 1.0, float(tips.fade_ms) / 1000.0)
	await tween.finished


## Fades the loading card out (the black stays until fade_in).
func hide_tip() -> void:
	if _card == null:
		return
	var card := _card
	_card = null
	var tween := create_tween()
	tween.tween_property(card, "modulate:a", 0.0, float(_card_tips().fade_ms) / 1000.0)
	await tween.finished
	card.queue_free()


## The loading cards' look: the tips given to setup_tips, else the built-in defaults (no tips).
func _card_tips() -> TipSet:
	if _tips == null:
		_tips = TipSet.new()
	return _tips


func _build_card(title: String, tip: String, extra: Control = null) -> Control:
	var card := Control.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	if _tips.background_path.is_empty():
		card.add_child(MenuBackdrop.new())
	else:
		var art := TextureRect.new()
		art.texture = AssetLoader.texture(_tips.background_path, Vector2i(64, 36))
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		card.add_child(art)
		var dim := ColorRect.new()
		dim.color = Color(0.0, 0.0, 0.0, float(_tips.background_dim_percent) / 100.0)
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dim.set_anchors_preset(Control.PRESET_FULL_RECT)
		card.add_child(dim)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 18)
	card.add_child(column)
	if not title.is_empty():
		var heading := ListMenu.centred_title(title, _tips.title_size)
		heading.label_settings.shadow_color = Color(0.0, 0.0, 0.0, 0.6)
		heading.label_settings.shadow_offset = Vector2(0.0, 4.0)
		column.add_child(heading)
		column.add_child(ListMenu.divider())
	if extra != null:
		extra.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(extra)
	if not tip.is_empty():
		var tip_head := HudStyle.make_title("Tip", int(_tips.tip_size * 0.75), HudStyle.TEXT_DIM)
		tip_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(tip_head)
		var text := ListMenu.centred_label(tip, _tips.tip_size)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size.x = TIP_WIDTH_PX
		text.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(text)
	if _tips.logo_height_px > 0 and not _logo_path.is_empty():
		var logo := TextureRect.new()
		logo.texture = AssetLoader.texture(_logo_path, Vector2i(256, 144))
		logo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var height := float(_tips.logo_height_px)
		var width := height * float(logo.texture.get_width()) / maxf(1.0, float(logo.texture.get_height()))
		logo.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		logo.offset_left = -width - CARD_MARGIN_PX
		logo.offset_top = -height - CARD_MARGIN_PX
		logo.offset_right = -CARD_MARGIN_PX
		logo.offset_bottom = -CARD_MARGIN_PX
		card.add_child(logo)
	return card


func _fade_black(to_alpha: float, seconds: float) -> void:
	_black.visible = true
	var tween := create_tween()
	tween.tween_property(_black, "modulate:a", to_alpha, seconds)
	await tween.finished
