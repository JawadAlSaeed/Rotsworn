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
