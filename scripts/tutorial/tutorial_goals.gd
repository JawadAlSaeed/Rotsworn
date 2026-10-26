class_name TutorialGoals
extends RefCounted
## Whether a combat event shows the player did what a tutorial step asks (DESIGN.md 7.8). Pure:
## reads the event and the sequence it belongs to (CombatMirror.sequence), nothing else.

const GOOD_PRESS := "good_press"
const SKILL_USED := "skill_used"
const SKILL_FOLLOW_UP := "skill_follow_up"
const PARRY := "parry"
const DODGE := "dodge"
const JUMP := "jump"
const COUNTER := "counter"
const ULTIMATE := "ultimate"
## The marks lesson (card #264): defend a hit that would leave a mark; lift a mark with a skill.
const MARK_DEFENDED := "mark_defended"
const CLEANSE := "cleanse"

const FIGHT_GOALS: Array[String] = [GOOD_PRESS, SKILL_USED, SKILL_FOLLOW_UP, PARRY, DODGE, JUMP, COUNTER, ULTIMATE,
		MARK_DEFENDED, CLEANSE]
## A card to read, no fight action (the First Strike and Relics cards, DESIGN.md 8.17): closing it moves on.
const READ := "read"


## True if `event` (applied in a fight whose current timed sequence is `sequence`) reaches `goal`.
## `not_skills`: ability ids that are not skills (basic attacks, the ultimate, Run).
static func reached(goal: String, event: Dictionary, sequence: Dictionary, ultimate_id: String = "team_ultimate",
		not_skills: Array = []) -> bool:
	var type := String(event.get("type", ""))
	match goal:
		SKILL_USED:
			var used := String(event.get("ability", ""))
			return type == "ability_used" and used != ultimate_id and not not_skills.has(used)
		COUNTER:
			return type == "counter"
		ULTIMATE:
			return type == "ability_used" and String(event.get("ability", "")) == ultimate_id
		CLEANSE:
			# A skill lifted a hero's mark (not one that just wore off).
			return type == "status_changed" and not bool(event.get("active", true)) 					and Status.is_debuff(String(event.get("status", ""))) 					and String(sequence.get("kind", "")) == CombatEngine.SEQUENCE_SKILL
	if type != "prompt_resolved" or int(event.get("seq", -1)) != int(sequence.get("seq", -2)):
		return false
	var outcome := int(event.get("outcome", Defense.Outcome.NONE))
	var role := _role_of(sequence, int(event.get("prompt", -1)))
	var good := outcome == Defense.Outcome.PRESS or outcome == Defense.Outcome.PRESS_PERFECT
	match goal:
		GOOD_PRESS:
			return good and role == CombatEngine.ROLE_PRESS
		SKILL_FOLLOW_UP:
			return good and role == CombatEngine.ROLE_FOLLOW_UP
		PARRY:
			return outcome == Defense.Outcome.PARRY
		DODGE:
			return outcome == Defense.Outcome.DODGE
		JUMP:
			return outcome == Defense.Outcome.JUMP
		MARK_DEFENDED:
			return outcome != Defense.Outcome.NONE and role == CombatEngine.ROLE_DEFEND 					and not _mark_of(sequence, int(event.get("hit", -1))).is_empty()
	return false


## The mark a declared hit leaves ("" for a plain hit).
static func _mark_of(sequence: Dictionary, hit: int) -> String:
	var hits: Array = sequence.get("hits", [])
	if hit < 0 or hit >= hits.size():
		return ""
	return String((hits[hit] as Dictionary).get("mark", ""))


static func _role_of(sequence: Dictionary, idx: int) -> String:
	var prompts: Array = sequence.get("prompts", [])
	if idx < 0 or idx >= prompts.size():
		return ""
	return String((prompts[idx] as Dictionary).get("role", ""))
