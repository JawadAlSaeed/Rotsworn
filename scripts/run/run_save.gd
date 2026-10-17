class_name RunSave
extends RefCounted
## The one saved run (Save & Quit, DESIGN.md 8.14): a JSON file holding RunState.to_dict() as it
## is (this class never looks at its keys), a format version, the content fingerprint (DataHash)
## and whether the party is inside a stop. Local runs only; online runs are never saved.
##
## Writes are crash safe: the new save goes to a temp file first, the old one is kept as a backup
## until the new one is in place, and a load falls back to the backup if the main file is gone or
## broken. Every function takes the path so tests never touch the player's real save.

## Bump when the file's shape changes (an older or newer file is then refused).
const FORMAT_VERSION: int = 1
const PATH := "user://run_save.json"
const TEMP_SUFFIX := ".tmp"
const BACKUP_SUFFIX := ".bak"

## load_save() statuses.
const LOADED := "loaded"
const MISSING := "missing"
## A file exists but cannot be used (wrong version or content, damaged); `reason` says why, and
## `keep` is true when the file is intact and just belongs to another build (leave it on disk).
const REJECTED := "rejected"


## Writes the save. `run` is RunState.to_dict(); `in_stop` is true right after a stop was chosen
## (continuing re-enters that stop from its start); `players` is the local player count (co-op
## continues through the players screen). False if the file could not be written; the old save
## is then left as it was.
static func save(run: Dictionary, fingerprint: String, in_stop: bool, players: int, path: String = PATH) -> bool:
	var body := {
		"format": FORMAT_VERSION, "fingerprint": fingerprint, "in_stop": in_stop, "players": players, "run": run,
	}
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


## Reads the save. {status: LOADED, run, in_stop, players}, {status: MISSING}, or {status:
## REJECTED, reason}. `fingerprint` is the running game's; a save made by other content is rejected.
static func load_save(fingerprint: String, path: String = PATH) -> Dictionary:
	var result := _read(path, fingerprint)
	if result.status == LOADED:
		return result
	# The main file is gone or damaged (a crash between the two renames): the backup is the
	# previous good save.
	var backup := _read(path + BACKUP_SUFFIX, fingerprint)
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


static func _read(path: String, fingerprint: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"status": MISSING}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return _rejected("the file is damaged")
	var body: Dictionary = json.data
	if not _is_number(body.get("format")) or int(body.format) != FORMAT_VERSION:
		return _rejected("it was saved by another version of the game", true)
	if typeof(body.get("fingerprint")) != TYPE_STRING or String(body.fingerprint) != fingerprint:
		return _rejected("the game's content has changed since it was saved", true)
	if not body.get("run") is Dictionary or typeof(body.get("in_stop")) != TYPE_BOOL:
		return _rejected("the file is damaged")
	var players := 1
	if _is_number(body.get("players")):
		players = clampi(int(body.players), 1, PlayerRoster.MAX_PLAYERS)
	return {"status": LOADED, "run": _whole_numbers(body.run), "in_stop": bool(body.in_stop), "players": players}


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
