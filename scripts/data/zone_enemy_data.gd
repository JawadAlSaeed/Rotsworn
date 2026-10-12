class_name ZoneEnemyData
extends Resource
## A roaming enemy in a zone (DESIGN.md 7.4): it wanders near its spot, chases the leader when it
## notices them, and starts its encounter on touch. Its look is the encounter's first enemy.

@export var encounter: EncounterData
## Where it starts (feet).
@export var position: Vector3 = Vector3.ZERO
## It wanders up to this far from its start (world units).
@export_range(0.0, 20.0, 0.1) var wander_radius: float = 2.5
