class_name StopVisuals
extends Resource
## Presentation-only data for the run's stop screens (DESIGN.md 8.7, card #199): how big an event's
## picture is drawn and the frame around it, and the icons on the choice cards and their chips
## (card #288). The pictures themselves are painted by
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

@export_group("Choice cards")
## The pictures on the side-by-side choice cards (card #288, tools/art_kit/assets/ui_choices.py):
## the campfire's choices, Host and Join on the main menu's Online page, and the Fight Rush screen's
## Heal, Fight and Party (DESIGN.md 8.21).
@export_file("*.png") var rest_icon_path: String = "res://assets/sprites/ui/choice_rest.png"
@export_file("*.png") var train_icon_path: String = "res://assets/sprites/ui/choice_train.png"
@export_file("*.png") var upgrade_icon_path: String = "res://assets/sprites/ui/choice_upgrade.png"
@export_file("*.png") var watch_icon_path: String = "res://assets/sprites/ui/choice_watch.png"
@export_file("*.png") var sharpen_icon_path: String = "res://assets/sprites/ui/choice_sharpen.png"
@export_file("*.png") var host_icon_path: String = "res://assets/sprites/ui/choice_host.png"
@export_file("*.png") var join_icon_path: String = "res://assets/sprites/ui/choice_join.png"
@export_file("*.png") var heal_icon_path: String = "res://assets/sprites/ui/choice_heal.png"
@export_file("*.png") var fight_icon_path: String = "res://assets/sprites/ui/choice_fight.png"
@export_file("*.png") var party_icon_path: String = "res://assets/sprites/ui/choice_party.png"
## Screen pixels per art pixel for a treasure chest on its card (the chests are 28x24).
@export_range(1, 8, 1) var chest_card_scale: int = 4

@export_group("Chips")
## The small icons on a choice's chips (what it costs or gives; RunState.offer_chips names the
## kind of each).
@export_file("*.png") var chip_gold_path: String = "res://assets/sprites/ui/chip_coin.png"
@export_file("*.png") var chip_heart_path: String = "res://assets/sprites/ui/chip_heart.png"
@export_file("*.png") var chip_max_hp_path: String = "res://assets/sprites/ui/chip_heart_cracked.png"
@export_file("*.png") var chip_item_path: String = "res://assets/sprites/ui/chip_bag.png"
@export_file("*.png") var chip_curse_path: String = "res://assets/sprites/ui/chip_skull.png"
@export_file("*.png") var chip_fight_path: String = "res://assets/sprites/ui/chip_fight.png"
@export_file("*.png") var chip_risk_path: String = "res://assets/sprites/ui/chip_die.png"
@export_file("*.png") var chip_up_path: String = "res://assets/sprites/ui/chip_up.png"
@export_file("*.png") var chip_gauge_path: String = "res://assets/sprites/ui/chip_gauge.png"
@export_file("*.png") var chip_relic_path: String = "res://assets/sprites/ui/chip_relic.png"
@export_file("*.png") var chip_ap_path: String = "res://assets/sprites/ui/ap_pip.png"
## Chip text colours: a price, a gift, and what a risk may do.
@export var chip_cost_color: Color = Color(1.0, 0.45, 0.4, 1.0)
@export var chip_gift_color: Color = Color(0.6, 0.95, 0.55, 1.0)
@export var chip_risk_color: Color = Color(1.0, 0.68, 0.3, 1.0)


## The icon path for a chip of `kind` (RunState.offer_chips: gold, hp, heal, max_hp, item, find,
## curse, fight, risk, xp, up, gauge, relic, ap; boss: the Fight Rush's next fight is a boss), "" for
## an unknown kind.
func chip_icon_path(kind: String) -> String:
	match kind:
		"gold":
			return chip_gold_path
		"hp", "heal":
			return chip_heart_path
		"max_hp":
			return chip_max_hp_path
		"item", "find":
			return chip_item_path
		"curse", "boss":
			return chip_curse_path
		"fight":
			return chip_fight_path
		"risk":
			return chip_risk_path
		"xp", "up":
			return chip_up_path
		"gauge":
			return chip_gauge_path
		"relic":
			return chip_relic_path
		"ap":
			return chip_ap_path
	return ""


## The resource saved at PATH, or the defaults when it cannot be loaded.
static func load_default() -> StopVisuals:
	if ResourceLoader.exists(PATH):
		var res := load(PATH) as StopVisuals
		if res != null:
			return res
	return StopVisuals.new()
