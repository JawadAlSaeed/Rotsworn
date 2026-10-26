class_name TipSet
extends Resource
## Loading-screen tips (DESIGN.md 7.7): one shows, with the place's name, while a Fight or Guard
## stop's fight is built (DESIGN.md 8.22). Edit data/branding/tips.tres.

@export_multiline var tips: PackedStringArray = PackedStringArray()
## The tip card stays at least this long (the fight is built at its end, so it starts when shown).
## 0: only for as long as building takes.
@export_range(0, 10000, 10, "suffix:ms") var hold_ms: int = 2600
## The card fades in and out over this long.
@export_range(0, 2000, 10, "suffix:ms") var fade_ms: int = 260
## Art behind the tip (a picture that fills the screen, darkened). Empty: the menu background.
@export_file("*.png", "*.jpg") var background_path: String = ""
@export_range(0, 100, 1, "suffix:%") var background_dim_percent: int = 55
@export_range(12, 120, 1) var title_size: int = 64
@export_range(12, 120, 1) var tip_size: int = 34
## The logo in the corner of the card.
@export_range(0, 600, 1, "suffix:px") var logo_height_px: int = 140
