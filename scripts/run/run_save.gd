class_name RunSave
extends RefCounted
## A saved run (Save & Quit, DESIGN.md 8.14): a JSON file holding RunState.to_dict() as it is (this
## class never looks at its keys), a format version, the content fingerprint (DataHash), the game's
## version and whether the party is inside a stop. Two slots, so neither overwrites the other: the
## local run's (PATH) and the online run's (ONLINE_PATH, card #313), kept by the host only. An online
## save also holds its seats (`online`: SavedSeats.capture, who held which hero and each seat's
## token), and the game only loads it in the same game version (`version`).
##
## Writes are crash safe: the new save goes to a temp file first, the old one is kept as a backup
## until the new one is in place, and a load falls back to the backup if the main file is gone or
## broken. Every function takes the path so tests never touch the player's real save.

## Bump when the file's shape changes (an older or newer file is then refused). 2: phase 26, a run
## without zones (DESIGN.md 8.22); a run saved inside a zone is kept on disk but never offered.
## 3: the Key's file went (card #319), and the first phase 26 builds (format 2) could still give a
## Key; such a pack would no longer load and the menu would delete the run, so format 2 is kept too.
## 4: three acts (card #323, DESIGN.md 8.23): an old save's act 2 was the Ashen Deep, now it is the
## Drowned Mire, so a format 3 run would carry on in the wrong place; it is kept but not offered.
## 5: the guards joined the Elite stops (map rules 4, DESIGN.md 8.22): a format 4 run's map still has
## its row of Guard stops, so it is kept but not offered either.
## 6: Relics without slots and no Echoes (cards #326, #327, DESIGN.md 8.24): a format 5 run's slots,
## Relic levels and Echo progress have no place now, so it is kept but not offered.
const FORMAT_VERSION: int = 6
const PATH := "user://run_save.json"
## The online run's slot (card #313), on the host.
const ONLINE_PATH := "user://online_run_save.json"
const TEMP_SUFFIX := ".tmp"
const BACKUP_SUFFIX := ".bak"

## load_save() statuses.
const LOADED := "loaded"
const MISSING := "missing"
## A file exists but cannot be used (wrong version or content, damaged); `reason` says why, and
## `keep` is true when the file is intact and just belongs to another build (leave it on disk).
const REJECTED := "rejected"


## Writes the save. `run` is RunState.to_dict(); `in_stop` is true right after a stop was chosen
## (continuing re-enters that stop from its start); `players` is the player count (local co-op
## continues through the players screen). `online` (an online run's save, card #313): its seats,
## kept as they are. False if the file could not be written; the old save is then left as it was.
static func save(run: Dictionary, fingerprint: String, in_stop: bool, players: int, path: String = PATH,
		online: Dictionary = {}) -> bool:
	var body := {
		"format": FORMAT_VERSION, "fingerprint": fingerprint, "version": game_version(), "in_stop": in_stop,
		"players": players, "run": run,
	}
	if not online.is_empty():
		body["online"] = online
	var temp := path + TEMP_SUFFIX
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(body))
	file.flush()
	var failed := file.get_error() != OK
	file.close()
	if failed:
		DirAccess.remove_absolute(temp)
		return false
	return _put_in_place(temp, path)


## Reads the save. {status: LOADED, run, in_stop, players, online}, {status: MISSING}, or {status:
## REJECTED, reason, keep}. `fingerprint`: if not empty, a save made by other content is rejected;
## empty (what the game passes, card #208): any save RunState can take is loaded, whatever changed
## since. `version`: if not empty, a save written by another game version is rejected and kept (the
## online slot, card #313). `online`: the file must hold an online run's seats (`online` in the
## result; {} for a local save).
static func load_save(fingerprint: String, path: String = PATH, version: String = "", online: bool = false) -> Dictionary:
	var result := _read(path, fingerprint, version, online)
	if result.status == LOADED:
		return result
	# The main file is gone or damaged (a crash between the two renames): the backup is the
	# previous good save.
	var backup := _read(path + BACKUP_SUFFIX, fingerprint, version, online)
	if backup.status == LOADED:
		return backup
	return result if result.status == REJECTED else backup


## True if a save file (or its backup) is there, usable or not.
static func exists(path: String = PATH) -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + BACKUP_SUFFIX)


## Deletes the save, its backup and any temp file.
static func delete(path: String = PATH) -> void:
	for file_path: String in [path, path + BACKUP_SUFFIX, path + TEMP_SUFFIX]:
		if FileAccess.file_exists(file_path):
			DirAccess.remove_absolute(file_path)


## The game's own version (Project Settings > Application > Config > Version), as the main menu
## shows it.
static func game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))


static func _read(path: String, fingerprint: String, version: String = "", online: bool = false) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"status": MISSING}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return _rejected("the file is damaged")
	var body: Dictionary = json.data
	if not _is_number(body.get("format")) or int(body.format) != FORMAT_VERSION:
		return _rejected("it was saved by another version of the game", true)
	if not fingerprint.is_empty() and (typeof(body.get("fingerprint")) != TYPE_STRING
			or String(body.fingerprint) != fingerprint):
		return _rejected("the game's content has changed since it was saved", true)
	if not version.is_empty() and (typeof(body.get("version")) != TYPE_STRING or String(body.version) != version):
		return _rejected("it was saved by another version of the game", true)
	if not body.get("run") is Dictionary or typeof(body.get("in_stop")) != TYPE_BOOL:
		return _rejected("the file is damaged")
	if online and not body.get("online") is Dictionary:
		return _rejected("the file is damaged")
	var players := 1
	if _is_number(body.get("players")):
		players = clampi(int(body.players), 1, PlayerRoster.MAX_PLAYERS)
	var seats: Dictionary = _whole_numbers(body.online) if online else {}
	return {"status": LOADED, "run": _whole_numbers(body.run), "in_stop": bool(body.in_stop), "players": players,
			"online": seats}


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT


## `keep`: the file is intact, only another build's (it must not be deleted: that build can still read it).
static func _rejected(reason: String, keep: bool = false) -> Dictionary:
	return {"status": REJECTED, "reason": reason, "keep": keep}


## Moves the finished temp file over `path`, keeping the old save as the backup until the new
## one is in place (a rename over an existing file is not atomic everywhere).
static func _put_in_place(temp: String, path: String) -> bool:
	var backup := path + BACKUP_SUFFIX
	var had_old := FileAccess.file_exists(path)
	if had_old:
		if FileAccess.file_exists(backup):
			DirAccess.remove_absolute(backup)
		if DirAccess.rename_absolute(path, backup) != OK:
			DirAccess.remove_absolute(temp)
			return false
	if DirAccess.rename_absolute(temp, path) != OK:
		# Put the old save back, drop the temp.
		if had_old:
			DirAccess.rename_absolute(backup, path)
		DirAccess.remove_absolute(temp)
		return false
	return true


## JSON has one number type (a float): whole numbers become ints again, because RunState.apply_dict
## wants ints. The core never holds floats, so nothing else is lost.
static func _whole_numbers(value: Variant) -> Variant:
	if value is Dictionary:
		var out: Dictionary = {}
		for key: Variant in (value as Dictionary):
			out[key] = _whole_numbers(value[key])
		return out
	if value is Array:
		var list: Array = []
		for item: Variant in (value as Array):
			list.append(_whole_numbers(item))
		return list
	if typeof(value) == TYPE_FLOAT and is_equal_approx(value, roundf(value)):
		return int(roundf(value))
	return value
