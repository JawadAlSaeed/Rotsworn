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
## The party may try to run from this fight (DESIGN.md 2.13). Bosses, guards and elite fights never
## allow it, whatever this says (CombatSetup).
@export var can_run: bool = true
## A zone's guard (DESIGN.md 8.6): its name is announced like a boss's, but it grows with depth
## like any fight.
@export var mini_boss: bool = false
## An elite fight (DESIGN.md 8.6): tougher (tuning elite_hp_percent, elite_power_percent), more
## gold, rarer spoils. Elite map stops and zone champions hold these.
@export var elite: bool = false
## Deeper in a run (map row tuning run_deep_row on) a zone holds this fight instead: the same kind
## of fight with variant monsters (DESIGN.md 2.16). Empty: always this fight.
@export var deep: EncounterData
