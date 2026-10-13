class_name CreditsData
extends Resource
## The credits screen's text (DESIGN.md 7.7). Edit data/branding/credits.tres. One line per line
## on screen: "# Name" is a heading, "~ text" is small print (licences), an empty line is a gap,
## anything else is a normal line.

@export_multiline var text: String = ""
## How fast the credits roll up the screen (Down rolls them faster, Up rolls them back).
@export_range(5.0, 1000.0, 1.0, "suffix:px/s") var scroll_px_per_s: float = 55.0
## Holding Down or Up rolls this many times faster.
@export_range(1.0, 20.0, 0.5) var fast_multiplier: float = 6.0
@export_range(12, 120, 1) var heading_size: int = 40
@export_range(12, 120, 1) var line_size: int = 30
@export_range(10, 60, 1) var small_size: int = 20
## The logo at the top of the credits.
@export_range(40, 800, 1, "suffix:px") var logo_height_px: int = 260
