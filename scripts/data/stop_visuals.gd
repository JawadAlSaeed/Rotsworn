class_name StopVisuals
extends Resource
## Presentation-only data for the run's stop screens (DESIGN.md 8.7, card #199): how big an event's
## picture is drawn and the frame around it. The pictures themselves are painted by
## tools/art_kit/assets/event_art.py (128x64 art pixels each). Edit data/presentation/stop_visuals.tres.

const PATH := "res://data/presentation/stop_visuals.tres"

@export_group("Event picture")
## Screen pixels per art pixel (nearest filter, never blurred). 4 makes a 128x64 picture 512x256.
@export_range(1, 8, 1) var event_picture_scale: int = 4
## Shown when an event (or an act's ambush page) has no picture file: the old question mark.
@export_file("*.png") var fallback_picture_path: String = "res://assets/sprites/ui/map_event.png"
## The fallback is a small icon, so it is drawn bigger.
@export_range(1, 8, 1) var fallback_picture_scale: int = 4

@export_group("Frame")
## Width of the worn-gold border around the picture, in screen pixels.
@export_range(0, 12, 1, "suffix:px") var frame_border: int = 3
## Dark gap between the border and the picture.
@export_range(0, 24, 1, "suffix:px") var frame_padding: int = 4
@export var frame_border_color: Color = Color(0.56, 0.44, 0.22, 1.0)
@export var frame_backing_color: Color = Color(0.04, 0.035, 0.05, 1.0)
## Soft shadow under the frame (0 = none).
@export_range(0, 40, 1, "suffix:px") var frame_shadow: int = 16
@export_range(0.0, 1.0, 0.05) var frame_shadow_alpha: float = 0.7


## The resource saved at PATH, or the defaults when it cannot be loaded.
static func load_default() -> StopVisuals:
	if ResourceLoader.exists(PATH):
		var res := load(PATH) as StopVisuals
		if res != null:
			return res
	return StopVisuals.new()
