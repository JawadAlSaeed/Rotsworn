class_name RunAutoplay
extends RefCounted
## The run bot's (`--autoplay --run`, DESIGN.md 10) shared habits: when the party is fit for a harder
## fight it could leave alone. Main's map bot (elite stops) and EventAutoplay (a risky "?" choice)
## both ask it. A careful player's habits, not game rules.
## Pure.

## Fit means: the weakest hero has at least READY_MIN_LOWEST_PERCENT of their HP, the party averages
## READY_MIN_AVERAGE_PERCENT and every hero is at least level READY_MIN_LEVEL (an elite is 40%
## tougher than a normal fight, so a fresh party leaves it alone).
const READY_MIN_LOWEST_PERCENT: int = 60
const READY_MIN_AVERAGE_PERCENT: int = 80
const READY_MIN_LEVEL: int = 3


## True if the party is fit for a harder fight. `health`: x the weakest hero's HP percent of max,
## y the party's average HP percent, z the lowest hero level.
static func is_ready(health: Vector3i) -> bool:
	return health.x >= READY_MIN_LOWEST_PERCENT and health.y >= READY_MIN_AVERAGE_PERCENT \
			and health.z >= READY_MIN_LEVEL
