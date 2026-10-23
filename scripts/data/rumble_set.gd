class_name RumbleSet
extends Resource
## Every controller buzz by name (data/presentation/rumble.tres, card #299) and how strong they all
## are. The player's Vibration setting scales this again.

## Every pattern at this share of its own strength (100: as written).
@export_range(0, 200, 5, "suffix:%") var strength_percent: int = 100
## At most this many buzzes play on one pad at once (the oldest stops for a new one).
@export_range(1, 16) var max_per_pad: int = 6
## The buzz Settings plays when the Vibration value changes, so the player feels the new strength.
@export var test_pattern: String = "parry"
@export var patterns: Array[RumblePattern] = []


func find(pattern_name: String) -> RumblePattern:
	for pattern: RumblePattern in patterns:
		if pattern != null and pattern.name == pattern_name:
			return pattern
	return null
