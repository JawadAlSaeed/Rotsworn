class_name RunData
extends Resource
## One kind of run (DESIGN.md 8): who goes, where they can go and what waits at the end. The
## numbers that shape the map and the rules live in tuning.tres ("Run" group).

@export var id: String = ""
@export var display_name: String = ""
## The party, in formation order (slot 0 first).
@export var party: Array[CharacterData] = []
## Offered to every party member when the team gauge is full.
@export var team_ultimate: AbilityData
## Each zone stop is one of these, picked at random when the map is made.
@export var zones: Array[ZoneData] = []
## The fight at the top of the map. Until the boss exists (Part B) it is a hard normal fight.
@export var final_encounter: EncounterData
## How the final fight's place looks.
@export var final_look: StageLook
## What every shop sells (each item once per visit).
@export var shop_items: Array[ShopItemData] = []
