class_name UiFonts
extends Resource
## The game's fonts (DESIGN.md 7.6): a storybook serif for titles, names and banners, and a clean
## font for everything else (menus, numbers, hints). Edit data/presentation/ui_fonts.tres; replace
## a font by dropping a file at the same path. A missing file falls back to Godot's built-in font
## with a warning.

## Titles, hero and enemy names, banners (Cinzel, a variable font: title_weight picks the weight).
@export_file("*.ttf", "*.otf") var title_font_path: String = "res://assets/fonts/Cinzel.ttf"
@export_range(400, 900, 100) var title_weight: int = 700
## Everything else.
@export_file("*.ttf", "*.otf") var body_font_path: String = "res://assets/fonts/AlegreyaSans-Medium.ttf"

@export_group("Menu choices")
## The chosen choice in a menu is drawn like the logo's letters (DESIGN.md 7.7): the title font at
## the logo's weight, bigger, in worn gold, its edges flickering like static (text_static.gdshader).
@export_range(400, 900, 100) var select_weight: int = 600
@export_range(100, 200, 1, "suffix:%") var select_size_percent: int = 118
@export var select_color: Color = Color(0.88, 0.74, 0.52)
## The other choices, a little dimmer so the chosen one stands out.
@export var idle_color: Color = Color(0.78, 0.76, 0.7)
@export_range(0.0, 60.0, 0.5) var select_static_fps: float = 9.0
@export_range(0.0, 1.0, 0.05) var select_static_motion: float = 0.6
@export_range(0.0, 2.0, 0.05) var select_wear: float = 1.0
## How much of the static shows on menu text, in percent (100 = all of it; 0 = no effect at all:
## plain gold letters). The logo's own static (BrandingData) is separate.
@export_range(0, 100, 1, "suffix:%") var select_static_percent: int = 100

@export_group("Numbers and popups")
## HP, AP, the team gauge and damage numbers (card #154): a bold font with lining figures (every
## digit the same height; the body font's default old-style digits looked uneven and cheap).
@export_file("*.ttf", "*.otf") var number_font_path: String = "res://assets/fonts/AlegreyaSans-Bold.ttf"
## The fight's floating words and damage numbers (PERFECT, PARRY, 128) lean like Persona 5's: how
## far the letters slant (a share of their height).
@export_range(0.0, 0.5, 0.01) var popup_slant: float = 0.2

@export_group("Text size")
## Settings > Game > Text size (card #203): Normal, Large, Larger, each as a percent of the sizes the
## screens are drawn with (HudStyle.scaled). Kept gentle: the fight HUD's plates and the menus' lists
## are laid out for 1920 x 1080 and must still fit at the largest.
@export var text_size_percents: PackedInt32Array = PackedInt32Array([100, 115, 130])


## The percent for a text size index (an index out of range is limited; 100 if the list is empty).
func text_percent(index: int) -> int:
	if text_size_percents.is_empty():
		return 100
	return maxi(1, text_size_percents[clampi(index, 0, text_size_percents.size() - 1)])
