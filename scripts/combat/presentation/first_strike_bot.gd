class_name FirstStrikeBot
extends RefCounted
## The autoplay bots' habits on the First Strike ring (DESIGN.md 8.22, 10), the same habits they have
## on a skill press ring (Autoplay). Pure: the caller passes the random generator (seeded from
## --seed, so the average bot's luck repeats) and presses through DefenseInput like a person.
## - perfect (and escape): one press in the middle of the PERFECT window: First Strike;
## - miss: never presses: a normal start;
## - mash: a random button every Autoplay.MASH_INTERVAL_MS (jittered), judged like anyone's (only the
##   skill press counts on the ring, and its first one is most likely EARLY);
## - average: lands it with bot_skill percent chance, half of those PERFECT and half GOOD (early in
##   the GOOD window), else lets the ring pass.

## When player `player`'s bot presses, in microseconds of ring time before lag compensation (the
## caller adds the judge's), or -1 for no planned press (miss, and mash, which presses on its own
## beat). `moment_us` and `windows` are the judge's (FirstStrikeJudge.moment_us, windows).
static func press_at(mode: String, bot_skill: int, rng: RandomNumberGenerator, moment_us: int,
		windows: Dictionary) -> int:
	var good: Array = windows.get(Defense.Outcome.PRESS, [0, 0])
	var perfect: Array = windows.get(Defense.Outcome.PRESS_PERFECT, good)
	match mode:
		CombatOptions.AUTOPLAY_PERFECT, CombatOptions.AUTOPLAY_ESCAPE:
			return moment_us + _middle(perfect[0], perfect[1])
		CombatOptions.AUTOPLAY_AVERAGE:
			if rng.randi_range(1, 100) > bot_skill:
				return -1
			if rng.randi_range(0, 1) == 1:
				# A good press: early, between the good and the perfect edges.
				return moment_us + _middle(good[0], perfect[0])
			return moment_us + _middle(perfect[0], perfect[1])
	return -1


## True for the bot that mashes its buttons on the ring.
static func mashes(mode: String) -> bool:
	return mode == CombatOptions.AUTOPLAY_MASH


## The masher's wait before its next press, in microseconds.
static func mash_gap_us(rng: RandomNumberGenerator) -> int:
	return (Autoplay.MASH_INTERVAL_MS + rng.randi_range(-Autoplay.MASH_JITTER_MS, Autoplay.MASH_JITTER_MS)) * 1000


## The masher's next button (a Defense.Outcome: only PRESS reaches the ring's judge).
static func mash_action(rng: RandomNumberGenerator) -> int:
	return Autoplay.MASH_ACTIONS[rng.randi_range(0, Autoplay.MASH_ACTIONS.size() - 1)]


static func _middle(a: Variant, b: Variant) -> int:
	@warning_ignore("integer_division")
	return (int(a) + int(b)) / 2
