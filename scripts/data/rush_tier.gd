class_name RushTier
extends Resource
## One stretch of a Fight Rush (DESIGN.md 8.21): from `from_fight` on, until the next tier's, the
## normal and elite fights come from these pools and take their look from these places.

## From this fight on (1 = the first) the Rush draws from this tier, until the next tier's from_fight.
@export_range(1, 1000) var from_fight: int = 1
## Places whose look, air and weather the tier's normal and elite fights use (picked per fight).
@export var zones: Array[ZoneData] = []
## Normal fights (picked per fight, never the same twice in a row while there is a choice).
@export var fights: Array[EncounterData] = []
## Elite fights (every tuning rush_elite_every fights), picked the same way.
@export var elites: Array[EncounterData] = []
## Fights here use their deep versions (EncounterData.deep) where one exists.
@export var deep: bool = false
