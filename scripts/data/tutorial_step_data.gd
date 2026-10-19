class_name TutorialStepData
extends Resource
## One step of the tutorial (DESIGN.md 7.8, card #131). Each step is staged: the game stops and a
## card explains it, the player tries, the game stops again to say how it went (a retry repeats
## the same step). A lesson can have several steps (Defend: parry, then dodge, then jump).

## Which lesson this step belongs to (1, 2, ...), shown as "Lesson N of M".
@export_range(1, 20) var lesson: int = 1
@export var title: String = ""
## The card's explanation. Each {action} (an input action name, or @move / @leftright) is drawn as
## that button's picture.
@export_multiline var text: String = ""
## A second, dimmer line on the card (why it matters), or empty.
@export_multiline var tip: String = ""
## The one line shown at the bottom while the player tries.
@export var reminder: String = ""
## The card after a try that did not reach the goal.
@export_multiline var retry: String = ""
## What the player must do (TutorialGoals): "good_press", "skill_used", "skill_follow_up",
## "parry", "dodge", "jump", "counter", "ultimate", "mark_defended", "cleanse".
@export var goal: String = ""
## Fight staging: whose turns pass ("enemies": the heroes act; "party": the enemy attacks).
@export var hold: String = ""
## The hero who acts in a hero step (a character id, e.g. "brin"); the others' turns pass.
@export var hero: String = ""
## The one choice the hero's menu allows (an ability id); everything else is locked and the
## allowed row glows.
@export var ability: String = ""
## The enemy's attacks are always this one (practice stage_attack; empty: its own choice).
@export var forced_attack: String = ""
## Enemy attacks at this tempo, in percent (0: normal; higher is slower).
@export_range(0, 400, 5, "suffix:%") var tempo_percent: int = 0
## Every hero to full AP when the step starts (skills).
@export var full_ap: bool = false
## Fill the team gauge when the step starts (the Team Ultimate lesson).
@export var fill_gauge: bool = false
## The marks lesson (card #264): this hero (a character id) carries this mark (a hero debuff id)
## when the step starts, for the healer to lift. Empty: no mark.
@export var mark_hero: String = ""
@export var mark_status: String = ""
