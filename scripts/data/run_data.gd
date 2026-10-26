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
## The acts of the run, in order (DESIGN.md 8.9). Empty: one act made of the fields below.
@export var acts: Array[ActData] = []
## The places of a run without acts: each Fight, Guard or elite stop is in one of these (DESIGN.md
## 8.22).
@export var zones: Array[ZoneData] = []
## The fight at the top of the map. Until the boss exists (Part B) it is a hard normal fight.
@export var final_encounter: EncounterData
## How the final fight's place looks.
@export var final_look: StageLook
## The final fight's picture on the run map: the boss's lair.
@export_file("*.png") var final_map_icon_path: String = ""
## What every shop sells (each item once per visit); it goes into the backpack (DESIGN.md 8.1).
@export var shop_items: Array[ItemData] = []
## What finds (events, treasure, pacts) hold and a Fight stop's fight drops (picked by find weight).
@export var found_items: Array[ItemData] = []
## Every piece of gear a run can find (as spoils after a guard, an elite or a boss) or buy (in shops).
@export var gear: Array[GearData] = []
## The difficulty ladder (DESIGN.md 8.15), in order: Oath 1 is index 0. A run at Oath N has the
## rules of oaths 1 to N. Empty: no ladder.
@export var oaths: Array[OathData] = []

@export_group("Starting pact (card #285, DESIGN.md 8.19)")
## Before the first stop of a run (not a first-ever run) the host may take one of
## tuning.run_pact_choices of these, picked by the run's seed, or none. Each is good for a real price.
@export var pacts: Array[EventChoiceData] = []
@export var pact_title: String = "The Crossroads"
@export_multiline var pact_text: String = ""
@export_file("*.png") var pact_picture_path: String = ""
