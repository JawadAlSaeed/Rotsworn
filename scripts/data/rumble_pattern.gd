class_name RumblePattern
extends Resource
## One controller buzz (DESIGN.md 7.14, card #299): a few steps played one after another. A pad has
## two motors: the weak one buzzes high and fine, the strong one shakes low and heavy. Listed in
## data/presentation/rumble.tres and played by PadRumble.

@export var name: String = ""
## Each step: x = the weak motor's strength (percent), y = the strong motor's (percent), z = how long
## the step lasts (ms). A step with both at 0 is a gap.
@export var steps: Array[Vector3i] = []


## How long the whole pattern lasts (ms).
func length_ms() -> int:
	var total := 0
	for step: Vector3i in steps:
		total += maxi(0, step.z)
	return total
