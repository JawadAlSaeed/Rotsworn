class_name SpellShot
extends RefCounted
## When a hero's spell bolt leaves the staff and when it lands (DESIGN.md 2.10, card #166). The bolt
## leaves at the moment of the timed press (like Expedition 33), or, if the press never comes, at
## the end of the press window, so a skill never stalls. It flies `flight_us` and lands then: the
## strike (damage numbers, hit-stop) belongs to the landing. Presentation only: press timing,
## judging and damage are the judge's and the engine's, unchanged. Pure, unit-tested; times are
## microseconds of skill time.


## The moment the bolt leaves. `now_us` is the press (a judged press, or the early press that used
## the ring up) or the moment the judge found the window closed; `window_end_us` is when the
## window really closed on this machine. A window that closed earlier than we noticed releases
## at its end, not a frame later.
static func release_us(now_us: int, window_end_us: int) -> int:
	return mini(now_us, window_end_us)


## When the bolt lands.
static func landing_us(release_at_us: int, flight_us: int) -> int:
	return release_at_us + maxi(1, flight_us)


## Flight progress at `t_us`: below 0 before the release, above 1 after the landing.
static func progress(t_us: int, release_at_us: int, flight_us: int) -> float:
	return float(t_us - release_at_us) / float(maxi(1, flight_us))


## True while the bolt is in the air (the release moment included, the landing moment not).
static func in_flight(t_us: int, release_at_us: int, flight_us: int) -> bool:
	return t_us >= release_at_us and t_us < landing_us(release_at_us, flight_us)


## When a press prompt's window closes on this machine: its moment plus the latest late edge of
## its windows plus the lag compensation. `prompt` is a declared prompt (at_ms, windows).
static func window_end_us(prompt: Dictionary, latency_us: int) -> int:
	var latest := 0
	for action: Variant in (prompt.windows as Dictionary):
		latest = maxi(latest, int((prompt.windows[action] as Array)[1]))
	return int(prompt.at_ms) * 1000 + latest + latency_us
