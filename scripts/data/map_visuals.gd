class_name MapVisuals
extends Resource
## Presentation-only data for the run map (DESIGN.md 8, card #111): the old paper map, its
## painted stops, the ink paths and how it unrolls. The art is drawn by tools/art_kit/assets/
## map_art.py; zone pictures sit on each ZoneData (map_icon_path), the lair on the RunData. Edit
## data/presentation/map_visuals.tres.

@export_group("Art")
@export_file("*.png") var paper_path: String = "res://assets/sprites/ui/map_paper.png"
## One rolled-up end of the paper; one stands at each edge of the open part while it unrolls.
@export_file("*.png") var roller_path: String = "res://assets/sprites/ui/map_roller.png"
@export_file("*.png") var shop_icon_path: String = "res://assets/sprites/ui/map_shop.png"
@export_file("*.png") var rest_icon_path: String = "res://assets/sprites/ui/map_rest.png"
## Phase 15 stops (DESIGN.md 8.6 to 8.8): an Elite stop (an elite group or, since 8.22, its place's
## guard; a map rules 3 Guard stop shows it too), a "?" event, a treasure chest.
@export_file("*.png") var elite_icon_path: String = "res://assets/sprites/ui/map_elite.png"
@export_file("*.png") var event_icon_path: String = "res://assets/sprites/ui/map_event.png"
@export_file("*.png") var treasure_icon_path: String = "res://assets/sprites/ui/map_treasure.png"
## The party's banner, planted where the party is.
@export_file("*.png") var flag_path: String = "res://assets/sprites/ui/map_flag.png"
## The red ink circle around the stop picked (the big one for the final fight's lair).
@export_file("*.png") var ring_path: String = "res://assets/sprites/ui/map_ring.png"
@export_file("*.png") var ring_big_path: String = "res://assets/sprites/ui/map_ring_big.png"
## Screen pixels per art pixel for everything on the map (paper, pictures, ink dots).
@export_range(1, 8, 1) var pixel_scale: int = 3

@export_group("Run info icons (phase 22)")
## The run's info screens show an icon and a word instead of a sentence: the line under the map,
## the shop and the run's end. The gold coin and the hit icons come from combat_visuals.tres.
## A guard's skull and a Fight stop's enemies (DESIGN.md 8.22).
@export_file("*.png") var guard_icon_path: String = "res://assets/sprites/ui/map_elite.png"
@export_file("*.png") var foe_icon_path: String = "res://assets/sprites/ui/goal_foe.png"
## New wares (the shop's Restock) and back to the map (the shop's Leave). Drawn by
## tools/art_kit/assets/ui_runinfo.py.
@export_file("*.png") var restock_icon_path: String = "res://assets/sprites/ui/restock.png"
@export_file("*.png") var leave_icon_path: String = "res://assets/sprites/ui/door.png"
## The campfire before the boss (card #287) offers Keep watch instead of Train: the team gauge filled
## (the same chip as its stop screen, stop_visuals.tres). The AP pip is the shop items' AP chip.
@export_file("*.png") var gauge_icon_path: String = "res://assets/sprites/ui/chip_gauge.png"
@export_file("*.png") var ap_icon_path: String = "res://assets/sprites/ui/ap_pip.png"

@export_group("Shop item chips (card #295)")
## What a shop item does, as icon chips on the line under the shelves instead of its sentence
## (ShopScreen.item_chips). A heal, damage, a revive or a cleanse shows the fight's Items-list chips
## (ActionMenu.item_chips: drawn glyphs, its AP with ap_icon_path); treasure the gold coin
## (combat_visuals.tres). Only a curse, which a fight never shows, has its picture here (the run's
## strip, RunPartyBar, draws each of the party's curses with its own icon_path, card #332).
@export_file("*.png") var item_curse_icon_path: String = "res://assets/sprites/ui/chip_skull.png"
## The line stays short: at most this many chips, and this many words in all of them (a chip that
## would go over is left out; the Glossary has the rules).
@export_range(1, 6, 1) var item_chips_max: int = 3
@export_range(1, 12, 1) var item_words_max: int = 6

@export_group("Legend (card #294)")
## The legend of stop pictures down the left of the map, kept small and dim so the map stands out:
## its text size (the player's text size applies), screen pixels per art pixel for its pictures,
## the width (art pixels) each picture is centred in so the words line up, the gap between rows
## and its distance from the screen's left edge.
@export_range(8, 64, 1) var legend_size: int = 18
@export_range(1, 4, 1) var legend_icon_scale: int = 1
@export_range(8, 64, 1) var legend_icon_box: int = 32
@export_range(0, 40, 1, "suffix:px") var legend_gap: int = 4
@export_range(0, 400, 1, "suffix:px") var legend_left: int = 32
## How strongly the legend is drawn, and its row for the picked stop's kind (lit, so the legend
## names the ringed stop).
@export_range(0.0, 1.0, 0.05) var legend_alpha: float = 0.45
@export_range(0.0, 1.0, 0.05) var legend_lit_alpha: float = 0.95

@export_group("Layout")
## Space between the gold and HP strip and the top of the paper (screen pixels).
@export_range(0, 200, 1, "suffix:px") var paper_top_gap: int = 32
## Space between the bottom of the paper on screen and the line of text under the map.
@export_range(0, 200, 1, "suffix:px") var paper_bottom_gap: int = 32
## The rest of the layout is in art pixels, from the paper's own edges.
## The top stop's centre below the paper's top edge.
@export_range(0, 120, 1) var top_margin: int = 30
## The first row's centre above the paper's bottom edge.
@export_range(0, 120, 1) var bottom_margin: int = 70
## The start point (before the first stop) below the first row.
@export_range(0, 60, 1) var start_gap: int = 26
## Columns of stops are this far apart.
@export_range(20, 200, 1) var column_gap: int = 110
## The flag's top-left corner from the party's stop centre (beside the picture), and from the
## start point before the first stop (the pole standing on the start mark).
@export var flag_offset: Vector2i = Vector2i(-16, -21)
@export var flag_start_offset: Vector2i = Vector2i(-2, -20)

@export_group("Ink")
## Names and the next routes.
@export var ink_color: Color = Color(0.25, 0.16, 0.11)
## The rot crown over the act's crowned elite (card #286).
@export var crown_color: Color = Color(0.86, 0.66, 0.2)
## Planning (card #162): stops and routes the picked stop cannot lead to are drawn this much
## weaker, so the roads ahead of the pick stand out.
@export_range(0.0, 1.0, 0.05) var unreachable_alpha: float = 0.35
## The path the party has walked.
@export var walked_color: Color = Color(0.56, 0.17, 0.13)
## Routes further up the map (not open yet) are drawn this strong.
@export_range(0.0, 1.0, 0.05) var route_alpha: float = 0.6
## Routes and stops left behind fade to this much.
@export_range(0.0, 1.0, 0.05) var faded_alpha: float = 0.35
## Ink dots along a path: every this many art pixels; the walked path's dots are bigger.
@export_range(2, 12, 1) var dot_spacing: int = 3
@export_range(1, 4, 1) var walked_dot_size: int = 2
## Stop names, written beside the picture.
@export_range(8, 64, 1) var label_size: int = 24
@export_range(0, 40, 1) var label_gap: int = 4

@export_group("Scrolling")
## The paper is taller than the screen. Up/down held scroll this many art pixels a second, a
## mouse wheel notch this many.
@export_range(10, 2000, 10) var scroll_speed: int = 300
@export_range(1, 200, 1) var wheel_step: int = 24
## The map glides to where it is heading with this time constant.
@export_range(10, 2000, 10, "suffix:ms") var scroll_follow_ms: int = 120
## At a run's start the map opens on the boss's lair and pans down to the start this long.
@export_range(0, 5000, 10, "suffix:ms") var start_pan_ms: int = 1400

@export_group("Unrolling")
## The paper unrolls from the middle out to the top and the bottom.
@export_range(0, 5000, 10, "suffix:ms") var unroll_ms: int = 900
## Then the ink soaks in: routes and stops appear row by row, outward from the row in view.
@export_range(0, 5000, 10, "suffix:ms") var ink_ms: int = 260
@export_range(0, 1000, 5, "suffix:ms") var row_stagger_ms: int = 70
## Last, the party's flag drops onto its spot.
@export_range(0, 2000, 10, "suffix:ms") var flag_drop_ms: int = 220
@export_range(0, 60, 1) var flag_drop_height: int = 10
## The picked stop's ring pulses this often.
@export_range(0.1, 10.0, 0.1) var pulse_hz: float = 1.6
