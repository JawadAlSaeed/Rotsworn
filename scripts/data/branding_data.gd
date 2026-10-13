class_name BrandingData
extends Resource
## The game's face (DESIGN.md 7.7): the logo, the title screen's look and feel, the main menu's
## logo and tagline, and the story blurb. Edit data/branding/branding.tres; replace the logo by
## dropping a file with the same name into assets/branding/.

## The logo (transparent PNG).
@export_file("*.png") var logo_path: String = "res://assets/branding/rotsworn_logo.png"

@export_group("Title screen")
## The logo's width as a percent of the screen's width.
@export_range(10, 100, 1, "suffix:%") var title_logo_width_percent: int = 66
## The logo fades in (and grows a little) over this long.
@export_range(0, 5000, 10, "suffix:ms") var logo_fade_in_ms: int = 1800
## How much smaller the logo starts before it grows to full size.
@export_range(0, 50, 1, "suffix:%") var logo_grow_percent: int = 6
## The soft glow behind the logo, and how it breathes (one full pulse every glow_pulse_ms).
@export var glow_color: Color = Color(0.55, 0.85, 0.15, 0.55)
@export_range(100, 20000, 10, "suffix:ms") var glow_pulse_ms: int = 3600
@export_range(0, 100, 1, "suffix:%") var glow_low_percent: int = 45
## The fog drifting over the background.
@export var fog_color: Color = Color(0.42, 0.5, 0.3, 0.32)
@export_range(0.0, 0.2, 0.001) var fog_speed: float = 0.018
## "Press any button" under the logo, shown once the logo is in; it fades in and out once every
## prompt_blink_ms.
@export var prompt_text: String = "Press any button"
@export_range(12, 120, 1) var prompt_size: int = 36
@export_range(100, 10000, 10, "suffix:ms") var prompt_blink_ms: int = 2000
## Presses in the first moments are ignored (a key held from the intro must not skip the title).
@export_range(0, 3000, 1, "suffix:ms") var skip_guard_ms: int = 500

@export_group("Title screen ribbon")
## The title screen draws the logo as three layers of the same size, so the ribbon's tails can
## sway between the crest and the ribbon's wraps and letters (tools/branding/paint_branding.py
## writes them). Any missing: the plain logo, standing still.
@export_file("*.png") var title_logo_back_path: String = "res://assets/branding/rotsworn_logo_back.png"
@export_file("*.png") var title_logo_tails_path: String = "res://assets/branding/rotsworn_logo_tails.png"
@export_file("*.png") var title_logo_front_path: String = "res://assets/branding/rotsworn_logo_front.png"
## How far each pixel of the front layer is from a letter's edge (0.5 on the edge); with it the
## letters' worn edges flicker like static (letters_static.gdshader). Missing: they stand still.
@export_file("*.png") var title_logo_front_edge_path: String = "res://assets/branding/rotsworn_logo_front_edge.png"
## The knot the tails hang from, as a share of the logo's width and height (the painter prints it).
@export var ribbon_root: Vector2 = Vector2(0.5222, 0.5117)
## How far from the knot (in logo heights) the sway grows to its full size.
@export_range(0.01, 1.0, 0.01) var ribbon_reach: float = 0.2
## The ends move up and down this far at most (pixels of the logo image), sideways a third of it.
@export_range(0, 60, 1, "suffix:px") var ribbon_sway_px: int = 10
## One full sway.
@export_range(100, 20000, 10, "suffix:ms") var ribbon_sway_ms: int = 3800
## How much the wave bends along the tails (radians from the knot to the ends).
@export_range(0.0, 20.0, 0.1) var ribbon_ripple: float = 5.0

@export_group("Title screen letters")
## The edge map spans this many pixels each way from an edge (the painter prints it).
@export_range(1.0, 100.0, 0.5, "suffix:px") var letters_edge_range_px: float = 24.0
## How many times a second the worn edges change, like static.
@export_range(0.0, 60.0, 0.5) var letters_static_fps: float = 9.0
## How much of the wear moves (0: still, 1: all of it jumps); the rest keeps the letters' shape.
@export_range(0.0, 1.0, 0.05) var letters_static_motion: float = 0.6
## How worn the edges are (1: like the printed logo).
@export_range(0.0, 2.0, 0.05) var letters_wear: float = 1.0
## How many gold flakes crumble off the edges (1: like the printed logo).
@export_range(0.0, 3.0, 0.05) var letters_specks: float = 1.0
@export var letters_speck_color: Color = Color(0.84, 0.7, 0.48, 0.85)

@export_group("Main menu")
## The logo's height above the main menu.
@export_range(40, 800, 1, "suffix:px") var menu_logo_height_px: int = 300
## The line under the main menu's logo.
@export var tagline: String = "a short run through the rot"

@export_group("Story")
## What the world is and why the heroes are "sworn" (card #90): store page, trailer, credits.
@export_multiline var story: String = ""
