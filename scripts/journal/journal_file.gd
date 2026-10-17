class_name JournalFile
extends RefCounted
## The Rot Journal's file (card #200): JSON in user://journal.json, per machine, separate from the
## run save. Written like RunSave: the new file goes to a temp file first, the old one is kept as a
## backup until the new one is in place, and a load falls back to the backup if the main file is gone
## or broken. Every function takes the path so tests never touch the player's real journal.
##
## A file of another FORMAT_VERSION is refused and left alone (a newer build may still read it; this
## build never overwrites it). Only the journal itself is saved: nothing here depends on the content
## fingerprint, since an entry only names an enemy and an attack by id and the screen shows what the
## current data still knows.

const PATH := "user://journal.json"
const TEMP_SUFFIX := ".tmp"
const BACKUP_SUFFIX := ".bak"

## load_journal() statuses.
const LOADED := "loaded"
const MISSING := "missing"
## The file is another version's (intact: keep it and do not write over it) or damaged (nothing to
## keep: the next write replaces it).
const REJECTED := "rejected"


## Writes the journal. False if the file could not be written; the old file is then left as it was.
static func save(journal: RotJournal, path: String = PATH) -> bool:
	var body := {"format": RotJournal.FORMAT_VERSION, "journal": journal.to_dict()}
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


## Reads the journal: {status: LOADED, journal: RotJournal}, {status: MISSING, journal: empty one}, or
## {status: REJECTED, journal: empty one, reason, keep}.
static func load_journal(path: String = PATH) -> Dictionary:
	var result := _read(path)
	# An intact file of another version is not damage: its backup is no better, and it stays.
	if result.status == LOADED or (result.status == REJECTED and bool(result.keep)):
		return result
	# The main file is gone or damaged (a crash between the two renames): the backup is the
	# previous good file.
	var backup := _read(path + BACKUP_SUFFIX)
	if backup.status == LOADED:
		return backup
	return result if result.status == REJECTED else backup


## Adds one fight to the journal file: load, record, save. Returns false if nothing was written (the
## file belongs to another version, or could not be saved).
static func record(fight: Dictionary, where: String, path: String = PATH) -> bool:
	var loaded := load_journal(path)
	if loaded.status == REJECTED and bool(loaded.keep):
		return false
	var journal: RotJournal = loaded.journal
	journal.record_fight(fight, where)
	return save(journal, path)


## Deletes the file, its backup and any temp file.
static func delete(path: String = PATH) -> void:
	for file_path: String in [path, path + BACKUP_SUFFIX, path + TEMP_SUFFIX]:
		if FileAccess.file_exists(file_path):
			DirAccess.remove_absolute(file_path)


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"status": MISSING, "journal": RotJournal.new()}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return _rejected("the file is damaged", false)
	var body: Dictionary = json.data
	var format: Variant = body.get("format")
	if typeof(format) != TYPE_FLOAT and typeof(format) != TYPE_INT:
		return _rejected("the file is damaged", false)
	if int(format) != RotJournal.FORMAT_VERSION:
		return _rejected("it was saved by another version of the game", true)
	if not body.get("journal") is Dictionary:
		return _rejected("the file is damaged", false)
	return {"status": LOADED, "journal": RotJournal.from_dict(body.journal)}


static func _rejected(reason: String, keep: bool) -> Dictionary:
	return {"status": REJECTED, "journal": RotJournal.new(), "reason": reason, "keep": keep}


## Moves the finished temp file over `path`, keeping the old file as the backup until the new one is
## in place (a rename over an existing file is not atomic everywhere).
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
		if had_old:
			DirAccess.rename_absolute(backup, path)
		DirAccess.remove_absolute(temp)
		return false
	return true
