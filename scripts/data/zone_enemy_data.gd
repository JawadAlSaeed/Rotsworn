class_name ZoneEnemyData
extends Resource
## A roaming enemy in a zone (DESIGN.md 7.4): it wanders near its spot, chases the leader when it
## notices them, and starts its encounter on touch. Its look is the encounter's first enemy.

## Empty in a section (DESIGN.md 8.5): the zone's roamer_pool picks one each visit.
@export var encounter: EncounterData
## Where it starts (feet).
@export var position: Vector3 = Vector3.ZERO
## It wanders up to this far from its start (world units).
@export_range(0.0, 20.0, 0.1) var wander_radius: float = 2.5
## The guard at the zone's exit: in a run, beating it clears the zone (DESIGN.md 8). Every other
## roaming enemy is optional there.
@export var guard: bool = false
## In a section: how often it is there on a visit (DESIGN.md 8.5).
@export_range(0, 100, 1, "suffix:%") var chance_percent: int = 100
## A champion (DESIGN.md 8.5): never chases, always fights its encounter's deep version, and
## guards a prize chest at prize_spot that opens once it is beaten (no key needed).
@export var champion: bool = false
@export var prize_spot: Vector3 = Vector3.ZERO
