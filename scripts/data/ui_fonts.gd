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
