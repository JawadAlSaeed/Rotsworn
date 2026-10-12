class_name EncounterData
extends Resource
## A fight: which enemies appear (and, until the run structure exists, which party fights).

@export var id: String = ""
@export var display_name: String = ""
## Phase 1 only. From phase 4 the party comes from the run.
@export var party: Array[CharacterData] = []
@export var enemies: Array[EnemyData] = []
## The team ultimate offered to every party member when the team gauge is full. Phase 2 only:
## from phase 4 the run provides it.
@export var team_ultimate: AbilityData
## A boss fight: its name is announced when the fight starts.
@export var boss: bool = false
