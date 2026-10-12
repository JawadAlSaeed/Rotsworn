class_name DataHash
extends RefCounted
## A fingerprint of the game's content (DESIGN.md 9.2): every file under data/ (characters,
## enemies, attacks, abilities, encounters, zones, the run, gear, tuning...) and the game version.
## Two machines play together only if their fingerprints match, because the host's events name
## content by id and rely on the same numbers on every machine.

const DATA_DIR := "res://data"
const TEXT_EXTENSIONS: Array[String] = ["tres", "tscn", "cfg", "json", "txt", "csv"]


## SHA-256 (hex) of the files under `root` (sorted paths and their bytes) and `version`.
static func compute(root: String = DATA_DIR, version: String = "") -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(("version:" + version + "\n").to_utf8_buffer())
	for path: String in files_under(root):
		ctx.update(("file:" + path.trim_prefix(root) + "\n").to_utf8_buffer())
		if TEXT_EXTENSIONS.has(path.get_extension()):
			# Line endings depend on how the files were checked out (Windows or not): ignore them.
			ctx.update(FileAccess.get_file_as_string(path).replace("\r", "").to_utf8_buffer())
		else:
			ctx.update(FileAccess.get_file_as_bytes(path))
	return ctx.finish().hex_encode()


## The game's own fingerprint (its data and the project's version).
static func of_game() -> String:
	return compute(DATA_DIR, str(ProjectSettings.get_setting("application/config/version", "")))


## Every file under `root`, recursively, sorted. Godot's import side files (.import, .uid) are
## left out: they differ per machine without changing the content.
static func files_under(root: String) -> Array[String]:
	var list: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return list
	for name: String in dir.get_files():
		if not name.ends_with(".import") and not name.ends_with(".uid"):
			list.append(root.path_join(name))
	for sub: String in dir.get_directories():
		list.append_array(files_under(root.path_join(sub)))
	list.sort()
	return list
