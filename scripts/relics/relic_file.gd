class_name RelicFile
extends RefCounted
## The Relic book's file (DESIGN.md 8.17, 8.24): JSON in user://progress.json, per machine, apart
## from the run save and the Journal. Written like them: the new file goes to a temp file first, the
## old one is kept as a backup until the new one is in place, and a load falls back to the backup if
## the main file is gone or broken. Every function takes the path so tests never touch the player's
## real file. A file of an older format (RelicCollection.OLD_FORMATS: levels, Echo pips, the bag)
## loads with every Relic it holds found and is written back as the current format at the next bank;
## a file of any other format is refused and left alone (never written over).

const PATH := "user://progress.json"
const TEMP_SUFFIX := ".tmp"
const BACKUP_SUFFIX := ".bak"

## load_collection() statuses.
const LOADED := "loaded"
const MISSING := "missing"
const REJECTED := "rejected"


## Writes the collection. False if the file could not be written; the old file is then as it was.
static func save(collection: RelicCollection, path: String = PATH) -> bool:
	var body := {"format": RelicCollection.FORMAT_VERSION, "relics": collection.to_dict()}
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


## Reads the collection: {status: LOADED, collection}, {status: MISSING, collection: empty}, or
## {status: REJECTED, collection: empty, reason, keep}.
static func load_collection(path: String = PATH) -> Dictionary:
	var result := _read(path)
	if result.status == LOADED or (result.status == REJECTED and bool(result.keep)):
		return result
	var backup := _read(path + BACKUP_SUFFIX)
	if backup.status == LOADED:
		return backup
	return result if result.status == REJECTED else backup


## The collection, or an empty one if there is none (or it cannot be read).
static func load_or_empty(path: String = PATH) -> RelicCollection:
	return load_collection(path).collection as RelicCollection


## Takes a run into the file: load, merge, save (RelicCollection.merge: the Relics found). False if
## nothing was written (nothing new, the file belongs to another version, or it could not be saved).
static func bank(found_ids: Array, path: String = PATH) -> bool:
	var loaded := load_collection(path)
	if loaded.status == REJECTED and bool(loaded.keep):
		return false
	var collection: RelicCollection = loaded.collection
	if not collection.merge(found_ids):
		return false
	return save(collection, path)


## True if the file (or its backup) exists.
static func exists(path: String = PATH) -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + BACKUP_SUFFIX)


## Deletes the file, its backup and any temp file (Settings > Reset progress).
static func delete(path: String = PATH) -> void:
	for file_path: String in [path, path + BACKUP_SUFFIX, path + TEMP_SUFFIX]:
		if FileAccess.file_exists(file_path):
			DirAccess.remove_absolute(file_path)


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"status": MISSING, "collection": RelicCollection.new()}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return _rejected("the file is damaged", false)
	var body: Dictionary = json.data
	var format: Variant = body.get("format")
	if typeof(format) != TYPE_FLOAT and typeof(format) != TYPE_INT:
		return _rejected("the file is damaged", false)
	if int(format) != RelicCollection.FORMAT_VERSION and not RelicCollection.OLD_FORMATS.has(int(format)):
		return _rejected("it was saved by another version of the game", true)
	if not body.get("relics") is Dictionary:
		return _rejected("the file is damaged", false)
	return {"status": LOADED, "collection": RelicCollection.from_dict(body.relics)}


static func _rejected(reason: String, keep: bool) -> Dictionary:
	return {"status": REJECTED, "collection": RelicCollection.new(), "reason": reason, "keep": keep}


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
