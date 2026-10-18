class_name GlossaryEntry
extends Resource
## One term of the glossary (DESIGN.md 7.12): what it is called, a short plain explanation, and
## the picture the game shows for it when there is one. Lives inside data/glossary/glossary.tres.

## Stable name, for tests and `--screen=glossary_<topic>`.
@export var id: String = ""
## The id of the topic (GlossaryData.topic_ids) this term is listed under.
@export var topic: String = ""
## The name in the list.
@export var term: String = ""
## Two or three short lines in the game's tone.
@export_multiline var text: String = ""
## The word as the game prints it on screen ("ROT", "MUST PARRY"); empty: none.
@export var tag: String = ""
## The game's own icon for it (a 12 px hit icon, a map stop picture); empty: none.
@export_file("*.png") var icon_path: String = ""
## Its colour in the game, drawn as a swatch when there is no icon (and on the tag); alpha 0: none.
@export var color: Color = Color(0.0, 0.0, 0.0, 0.0)


## True when the entry has a colour (the default, fully clear, means none).
func has_color() -> bool:
	return color.a > 0.0
