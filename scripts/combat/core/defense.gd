class_name Defense
extends RefCounted
## Defence outcomes and the one place that decides which defence works against which hit.
## The engine builds each prompt's windows here and validates results here, so what a client's
## judge accepts and what the host accepts can never drift apart.
## The same enum is used for the three defence buttons (DODGE, PARRY, JUMP) and the skill press
## button (PRESS: skill and follow-up presses, DESIGN.md 2.10). A skill press has two nested
## windows: PRESS (good: normal damage) and, inside it, PRESS_PERFECT (extra damage). The button
## is always PRESS; the judge reports PRESS_PERFECT when the press is inside the perfect window.

enum Outcome {
	## No (successful) defence: the hit connects.
	NONE,
	DODGE,
	PARRY,
	JUMP,
	## A good skill or follow-up press.
	PRESS,
	## A perfect skill or follow-up press (inside the narrow perfect window).
	PRESS_PERFECT,
}


## Actions that work against a hit kind, each with its window edges in microseconds relative to
## impact: {Outcome: [early_us (negative), late_us]}. Plain arrays so events stay serialisable.
## Phase 4 passives that change windows per character plug in here.
static func build_windows(kind: int, tuning: Tuning) -> Dictionary:
	var windows: Dictionary = {}
	if kind == AttackHitData.Kind.NORMAL:
		var dodge: Vector2i = tuning.window_edges_us(tuning.dodge_window_ms)
		var parry: Vector2i = tuning.window_edges_us(tuning.parry_window_ms)
		windows[Outcome.DODGE] = [dodge.x, dodge.y]
		windows[Outcome.PARRY] = [parry.x, parry.y]
	elif kind == AttackHitData.Kind.GROUND:
		var jump: Vector2i = tuning.window_edges_us(tuning.jump_window_ms)
		windows[Outcome.JUMP] = [jump.x, jump.y]
	elif kind == AttackHitData.Kind.PRESS:
		var press: Vector2i = tuning.window_edges_us(tuning.skill_press_window_ms)
		var perfect: Vector2i = tuning.window_edges_us(tuning.skill_perfect_window_ms)
		windows[Outcome.PRESS] = [press.x, press.y]
		windows[Outcome.PRESS_PERFECT] = [perfect.x, perfect.y]
	return windows


## Windows of a follow-up press prompt.
static func build_follow_up_windows(tuning: Tuning) -> Dictionary:
	var edges: Vector2i = tuning.window_edges_us(tuning.follow_up_window_ms)
	var perfect: Vector2i = tuning.window_edges_us(tuning.follow_up_perfect_window_ms)
	return {Outcome.PRESS: [edges.x, edges.y], Outcome.PRESS_PERFECT: [perfect.x, perfect.y]}


## True for a good or perfect skill press.
static func is_press(outcome: int) -> bool:
	return outcome == Outcome.PRESS or outcome == Outcome.PRESS_PERFECT


## Outcomes that count toward a counterattack for this hit kind.
static func perfect_outcomes(kind: int) -> Array[int]:
	var list: Array[int] = []
	if kind == AttackHitData.Kind.NORMAL:
		list.append(Outcome.PARRY)
	elif kind == AttackHitData.Kind.GROUND:
		list.append(Outcome.JUMP)
	elif kind == AttackHitData.Kind.PRESS:
		list.append(Outcome.PRESS_PERFECT)
	return list


## The outcome if the prompt allows it, otherwise NONE.
static func sanitize(outcome: int, windows: Dictionary) -> int:
	if outcome != Outcome.NONE and windows.has(outcome):
		return outcome
	return Outcome.NONE


## AP earned for a successful defence.
static func ap_reward(outcome: int, tuning: Tuning) -> int:
	match outcome:
		Outcome.PARRY:
			return tuning.ap_per_parry
		Outcome.JUMP:
			return tuning.ap_per_jump
	return 0


static func outcome_name(outcome: int) -> String:
	match outcome:
		Outcome.DODGE:
			return "dodge"
		Outcome.PARRY:
			return "parry"
		Outcome.JUMP:
			return "jump"
		Outcome.PRESS:
			return "press"
		Outcome.PRESS_PERFECT:
			return "perfect press"
	return "none"
