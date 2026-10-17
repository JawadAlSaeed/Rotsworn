class_name RotJournal
extends RefCounted
## The Rot Journal (DESIGN.md 7.11, card #200): every enemy and attack the player has met on this
## machine and how they fared against it. Pure data, no nodes, no files: JournalTally collects one
## fight, record_fight() adds it, to_dict() / from_dict() move it to and from JSON (JournalFile
## writes it). Counts are in hits, like the RUN OVER recap: "parried 3" is three hits parried.
##
## An enemy entry: {name, met (fights it was in), beaten (times one went down), places: [where it
## was met], attacks: {attack id: {name, seen (times it struck), broken (Dooms the party broke),
## parried, dodged, jumped, hit (undefended hits), kinds: {kind key: hits}, marks: {mark id: hits}}}}.

## Bump when the saved shape changes; JournalFile refuses a file of another version.
const FORMAT_VERSION: int = 1
## No count grows past this (a hand-edited file cannot overflow anything).
const MAX_COUNT: int = 999999
## At most this many places are kept per enemy (the first ones met).
const MAX_PLACES: int = 6
const MAX_TEXT: int = 80
const KIND_KEYS: Array[String] = ["normal", "ground", "rend", "sweep"]
const COUNTERS: Array[String] = ["seen", "broken", "parried", "dodged", "jumped", "hit"]

## Enemy data id -> enemy entry (see above).
var enemies: Dictionary = {}


## Whether a fight is written to the journal. A run's fights count; practice fights, the tutorial and
## bots do not (practice has cheats and would unlock every entry at once, a bot's numbers say nothing
## about a player). A dev path (--journal-path=) is a sandbox where every fight counts.
static func counts_fight(in_run: bool, autoplay: bool, tutorial: bool, custom_path: bool) -> bool:
	if custom_path:
		return true
	return in_run and not autoplay and not tutorial


## The journal's key for an AttackHitData.Kind ("" for a kind enemies never use).
static func kind_key(kind: int) -> String:
	match kind:
		AttackHitData.Kind.NORMAL:
			return "normal"
		AttackHitData.Kind.GROUND:
			return "ground"
		AttackHitData.Kind.REND:
			return "rend"
		AttackHitData.Kind.SWEEP:
			return "sweep"
	return ""


func has_met(enemy_id: String) -> bool:
	return enemies.has(enemy_id)


func met_count() -> int:
	return enemies.size()


## The enemy's entry (empty if never met). A copy: change the journal only through record_fight().
func enemy(enemy_id: String) -> Dictionary:
	return (enemies[enemy_id] as Dictionary).duplicate(true) if enemies.has(enemy_id) else {}


## The attack's record (empty if never met).
func attack(enemy_id: String, attack_id: String) -> Dictionary:
	var attacks: Dictionary = (enemies.get(enemy_id, {}) as Dictionary).get("attacks", {})
	return (attacks[attack_id] as Dictionary).duplicate(true) if attacks.has(attack_id) else {}


## True once the attack has been seen strike or broken.
func has_seen_attack(enemy_id: String, attack_id: String) -> bool:
	var record := attack(enemy_id, attack_id)
	return int(record.get("seen", 0)) + int(record.get("broken", 0)) > 0


## Adds one fight (JournalTally.to_dict()) met at `where` ("" : unknown place). Also reads a saved
## journal (from_dict), whose entries carry their own places. Junk in `fight` is dropped.
func record_fight(fight: Dictionary, where: String = "") -> void:
	var fighters: Variant = fight.get("enemies", {})
	if not fighters is Dictionary:
		return
	for id: Variant in fighters:
		if not (fighters[id] is Dictionary) or _text(id).is_empty():
			continue
		var places: Array = []
		if (fighters[id] as Dictionary).get("places") is Array:
			places.append_array((fighters[id] as Dictionary).places)
		if not where.is_empty():
			places.append(where)
		_add_enemy(_text(id), fighters[id], places)


## Adds everything another journal holds (counts add up, places join).
func merge(other: RotJournal) -> void:
	record_fight(other.to_dict())


func _add_enemy(id: String, source: Dictionary, places: Array) -> void:
	var entry: Dictionary = enemies.get(id, {})
	if entry.is_empty():
		entry = {"name": "", "met": 0, "beaten": 0, "places": [], "attacks": {}}
		enemies[id] = entry
	var enemy_name := _text(source.get("name", ""))
	if not enemy_name.is_empty():
		entry.name = enemy_name
	entry.met = _add(int(entry.met), source.get("met", 0))
	entry.beaten = _add(int(entry.beaten), source.get("beaten", 0))
	var known: Array = entry.places
	for place: Variant in places:
		var text := _text(place)
		if not text.is_empty() and not known.has(text) and known.size() < MAX_PLACES:
			known.append(text)
	var attacks: Dictionary = entry.attacks
	var theirs: Variant = source.get("attacks", {})
	if not theirs is Dictionary:
		return
	for attack_id: Variant in theirs:
		if not (theirs[attack_id] is Dictionary) or _text(attack_id).is_empty():
			continue
		var record: Dictionary = attacks.get(_text(attack_id), _empty_attack())
		var add: Dictionary = theirs[attack_id]
		var attack_name := _text(add.get("name", ""))
		if not attack_name.is_empty():
			record.name = attack_name
		for key: String in COUNTERS:
			record[key] = _add(int(record[key]), add.get(key, 0))
		_add_counts(record.kinds, add.get("kinds", {}), KIND_KEYS)
		_add_counts(record.marks, add.get("marks", {}), [])
		attacks[_text(attack_id)] = record


static func _empty_attack() -> Dictionary:
	return {"name": "", "seen": 0, "broken": 0, "parried": 0, "dodged": 0, "jumped": 0, "hit": 0,
			"kinds": {}, "marks": {}}


## Adds `add` (key -> count) into `into`; `allowed` limits the keys (empty: any short key).
static func _add_counts(into: Dictionary, add: Variant, allowed: Array[String]) -> void:
	if not add is Dictionary:
		return
	for key: Variant in add:
		var text := _text(key)
		if text.is_empty() or (not allowed.is_empty() and not allowed.has(text)):
			continue
		var total := _add(int(into.get(text, 0)), (add as Dictionary)[key])
		if total > 0:
			into[text] = total


## `have` plus `more` (any value; junk counts as 0), kept between 0 and MAX_COUNT.
static func _add(have: int, more: Variant) -> int:
	if typeof(more) != TYPE_INT and typeof(more) != TYPE_FLOAT:
		return clampi(have, 0, MAX_COUNT)
	return clampi(have + clampi(int(more), 0, MAX_COUNT), 0, MAX_COUNT)


static func _text(value: Variant) -> String:
	if typeof(value) != TYPE_STRING and typeof(value) != TYPE_STRING_NAME:
		return ""
	return String(value).strip_edges().left(MAX_TEXT)


## The journal as plain JSON-friendly data (a copy).
func to_dict() -> Dictionary:
	return {"enemies": enemies.duplicate(true)}


## A journal from saved data. Junk is dropped rather than refused: wrong types count as 0, unknown
## keys are ignored, counts are clamped. Always returns a journal.
static func from_dict(data: Dictionary) -> RotJournal:
	var journal := RotJournal.new()
	journal.record_fight(data)
	return journal
