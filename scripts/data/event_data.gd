class_name EventData
extends Resource
## A "?" stop on the map (DESIGN.md 8.7): a short scene with a few choices, each with a price and
## a gift, and some with a risk. Leaving is always one of the choices.

@export var id: String = ""
@export var title: String = ""
@export_multiline var text: String = ""
## A small picture over the text (the event's painted place on the map style).
@export_file("*.png") var picture_path: String = ""
@export var choices: Array[EventChoiceData] = []
