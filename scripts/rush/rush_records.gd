class_name RushRecords
extends RefCounted
## The Fight Rush records (DESIGN.md 8.21): one per party size (Solo, Duo, Trio), each the highest
## fight a party of that size entered and the day it did. Pure rules, so they are tested without a
## settings file; PlayerSettings keeps the entries in user://settings.cfg.

## The party sizes that keep a record of their own.
const SIZES: Array[int] = [1, 2, 3]
## Each size's name, in SIZES order.
const LABELS: Array[String] = ["Solo", "Duo", "Trio"]
## The keys `allowed` reads, with the value each must have for a record to count: any dev or bot
## switch (DESIGN.md 8.21, default D9) and a late online join (D20) keep the records out of it.
const CLEAN_FLAGS := {
	"autoplay": false, "screen": "", "start_fight": 1, "rush_fights": 0, "relics_mode": "",
	"relics_path": "", "fixed_seed": 0, "tuning_default": true, "late": false,
}


## The record a party of `players` counts toward (1 to 3).
static func bucket(players: int) -> int:
	return clampi(players, int(SIZES.front()), int(SIZES.back()))


## The record's name: "Solo", "Duo" or "Trio".
static func label(players: int) -> String:
	return LABELS[SIZES.find(bucket(players))]


## A record entry: the fight reached and the day ("2026-10-24").
static func entry(fight: int, date: String) -> Dictionary:
	return {"fight": fight, "date": date}


## True if `e` is an entry: a Dictionary with an int fight of at least 1 and a String date.
static func is_valid(e: Variant) -> bool:
	if not e is Dictionary:
		return false
	var d := e as Dictionary
	return typeof(d.get("fight")) == TYPE_INT and int(d.fight) >= 1 and typeof(d.get("date")) == TYPE_STRING


## True if `new_e` should replace `old_e`: it is valid, and the old one is not or reached a lower fight.
static func better(new_e: Dictionary, old_e: Variant) -> bool:
	if not is_valid(new_e):
		return false
	return not is_valid(old_e) or int(new_e.fight) > int((old_e as Dictionary).fight)


## The highest fight among `entries` (0: none valid), for the main menu's Fight Rush card.
static func best_of(entries: Array) -> int:
	var best := 0
	for e: Variant in entries:
		if is_valid(e):
			best = maxi(best, int((e as Dictionary).fight))
	return best


## True if a Rush started with these switches may read and write records. `f` must hold every key of
## CLEAN_FLAGS plus "seed_override" (an int; a seed given on the command line is 0 or more). A
## missing key counts as a switch in use.
static func allowed(f: Dictionary) -> bool:
	for key: String in CLEAN_FLAGS:
		if not f.has(key) or typeof(f[key]) != typeof(CLEAN_FLAGS[key]) or f[key] != CLEAN_FLAGS[key]:
			return false
	return typeof(f.get("seed_override")) == TYPE_INT and int(f.seed_override) < 0
