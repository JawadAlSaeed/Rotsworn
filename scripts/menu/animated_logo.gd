class_name AnimatedLogo
extends Control
## The Rotsworn logo, alive (DESIGN.md 7.7), for the title screen and the main menu: drawn in three
## layers of the same size (crest, ribbon tails, letters) so the ribbon's tails sway
## (ribbon_sway.gdshader) and the letters' worn edges flicker like static
## (letters_static.gdshader). The pictures keep their shape, centred in this control's box. If a
## layer is missing it shows the still logo instead. Numbers live in data/branding/branding.tres.

const SWAY_SHADER := preload("res://scripts/menu/ribbon_sway.gdshader")
const STATIC_SHADER := preload("res://scripts/menu/letters_static.gdshader")
## Sideways sway, as a share of the up-and-down sway.
const SIDEWAYS_SHARE: float = 0.35

## The pictures' size in pixels (their shape decides the logo's shape on screen).
var logo_size := Vector2(1.0, 1.0)


func setup(branding: BrandingData) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var layered := true
	for path: String in [branding.title_logo_back_path, branding.title_logo_tails_path, branding.title_logo_front_path]:
		layered = layered and not path.is_empty() and ResourceLoader.exists(path)
	if not layered:
		_layer(branding.logo_path)
		return
	_layer(branding.title_logo_back_path)
	var tails := _layer(branding.title_logo_tails_path)
	var front := _layer(branding.title_logo_front_path)
	tails.material = _sway_material(branding, tails.texture)
	var edge_path := branding.title_logo_front_edge_path
	if not edge_path.is_empty() and ResourceLoader.exists(edge_path):
		front.material = _static_material(branding, front.texture, load(edge_path) as Texture2D)


## One picture of the logo, filling this box; the first one sets the logo's shape.
func _layer(path: String) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = AssetLoader.texture(path, Vector2i(512, 288))
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(rect)
	if get_child_count() == 1:
		logo_size = rect.texture.get_size()
	return rect


static func _sway_material(branding: BrandingData, texture: Texture2D) -> ShaderMaterial:
	var size := texture.get_size()
	var mat := ShaderMaterial.new()
	mat.shader = SWAY_SHADER
	mat.set_shader_parameter("root", branding.ribbon_root)
	mat.set_shader_parameter("aspect", size.x / maxf(1.0, size.y))
	mat.set_shader_parameter("reach", branding.ribbon_reach)
	var px := float(branding.ribbon_sway_px)
	mat.set_shader_parameter("amp", Vector2(px * SIDEWAYS_SHARE / maxf(1.0, size.x), px / maxf(1.0, size.y)))
	mat.set_shader_parameter("speed", TAU / maxf(0.1, float(branding.ribbon_sway_ms) / 1000.0))
	mat.set_shader_parameter("ripple", branding.ribbon_ripple)
	return mat


static func _static_material(branding: BrandingData, texture: Texture2D, edge: Texture2D) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = STATIC_SHADER
	mat.set_shader_parameter("edge_map", edge)
	mat.set_shader_parameter("tex_size", texture.get_size())
	mat.set_shader_parameter("edge_range", branding.letters_edge_range_px)
	mat.set_shader_parameter("fps", branding.letters_static_fps)
	mat.set_shader_parameter("motion", branding.letters_static_motion)
	mat.set_shader_parameter("wear", branding.letters_wear)
	mat.set_shader_parameter("specks", branding.letters_specks)
	mat.set_shader_parameter("speck_color", branding.letters_speck_color)
	return mat
