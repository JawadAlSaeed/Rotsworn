class_name ActData
extends Resource
## One act of a run (DESIGN.md 8.9): its own map, zones, elite fights, events and boss. A run plays
## its acts in order; beating an act's boss opens the next act's map.

@export var id: String = ""
@export var display_name: String = ""
## Each zone stop of this act is one of these.
@export var zones: Array[ZoneData] = []
## The boss at the top of this act's map, where its fight happens and its picture on the map.
@export var final_encounter: EncounterData
@export var final_look: StageLook
@export_file("*.png") var final_map_icon_path: String = ""
## Elite stops pick one of these (DESIGN.md 8.6).
@export var elites: Array[EncounterData] = []
## "?" stops pick one of these, never the same one twice in a run (DESIGN.md 8.7).
@export var events: Array[EventData] = []
## Every zone fight here is its deep (variant) version (DESIGN.md 2.16).
@export var deep: bool = false
## A "?" stop can turn into an ambush instead of an event (tuning unknown_fight_percent_base and
## unknown_fight_percent_step; DESIGN.md 8.7): it fights one of these. A deep act fights their deep
## versions.
@export var ambushes: Array[EncounterData] = []
@export var ambush_title: String = "An Ambush!"
@export_multiline var ambush_text: String = "The mark on the map was bait. Something was waiting for you."
## The picture on an ambush page (the event picture fallback).
@export_file("*.png") var ambush_picture_path: String = "res://assets/sprites/ui/map_event.png"
