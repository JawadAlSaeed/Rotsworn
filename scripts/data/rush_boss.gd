class_name RushBoss
extends Resource
## One boss of a Fight Rush's boss cycle (DESIGN.md 8.21): a guard or an act boss, where it is
## fought, and how deep a run meets it (it grows only by the depth past that).

## The fight (its `deep` version in a deep tier, when it has one).
@export var encounter: EncounterData
## The look, air and weather of the fight. May be empty when `look` is set (no weather then).
@export var zone: ZoneData
## The look of the fight in place of the zone's (the Hollow King's throne).
@export var look: StageLook
## The depth (map rows) this boss is built for: where a run meets it. A boss grows only by the depth past it.
@export_range(0, 100) var home_depth: int = 0
