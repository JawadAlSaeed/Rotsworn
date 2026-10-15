class_name TutorialData
extends Resource
## The tutorial (DESIGN.md 7.8, card #131): its practice fight and its steps in order. Edit
## data/tutorial/tutorial.tres.

## The practice fight the fight lessons use.
@export var encounter: EncounterData
## The enemy's speed in the tutorial fight, in percent of its own (the Husk is twice as fast as
## the heroes; slowed, each hero gets about one turn per enemy attack).
@export_range(10, 200, 1, "suffix:%") var enemy_speed_percent: int = 50
@export var steps: Array[TutorialStepData] = []
## Shown when the last step is done.
@export var done_title: String = "Tutorial complete"
@export_multiline var done_text: String = ""


## How many lessons there are (the highest lesson number).
func lesson_count() -> int:
	var count := 0
	for step: TutorialStepData in steps:
		if step != null:
			count = maxi(count, step.lesson)
	return count
