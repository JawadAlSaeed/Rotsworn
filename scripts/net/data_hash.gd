class_name DataHash
extends RefCounted
## A fingerprint of the game's content and code (DESIGN.md 9.2): every file under data/ (characters,
## enemies, attacks, abilities, encounters, zones, the run, gear, tuning...), the scripts and scenes
## (so a code-only fix also splits the builds) and the game version.
## Two machines play together only if their fingerprints match, because the host's events name
## content by id and rely on the same numbers on every machine.

const DATA_DIR := "res://data"
const CODE_DIRS: Array[String] = ["res://scripts", "res://scenes"]
const TEXT_EXTENSIONS: Array[String] = ["tres", "tscn", "cfg", "json", "txt", "csv", "gd", "gdshader"]


## SHA-256 (hex) of the files under `root` (sorted paths and their bytes) and `version`.
static func compute(root: String = DATA_DIR, version: String = "") -> String:
	return compute_roots([root], version)


## Like compute(), over several folders (each is hashed under its own name, so the same file name
## in two folders still counts).
static func compute_roots(roots: Array[String], version: String = "") -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(("version:" + version + "
").to_utf8_buffer())
	for root: String in roots:
		ctx.update(("root:" + root + "
").to_utf8_buffer())
		for path: String in files_under(root):
			ctx.update(("file:" + path.trim_prefix(root) + "
").to_utf8_buffer())
			if TEXT_EXTENSIONS.has(path.get_extension()):
				# Line endings depend on how the files were checked out (Windows or not): ignore them.
				ctx.update(FileAccess.get_file_as_string(path).replace("", "").to_utf8_buffer())
			else:
				ctx.update(FileAccess.get_file_as_bytes(path))
	return ctx.finish().hex_encode()


## The game's own fingerprint (its data, scripts, scenes and the project's version).
static func of_game() -> String:
	var roots: Array[String] = [DATA_DIR]
	roots.append_array(CODE_DIRS)
	return compute_roots(roots, str(ProjectSettings.get_setting("application/config/version", "")))


## What a saved run is checked against (DESIGN.md 8.14): the data and the version, not the code, so
## a code-only fix keeps a saved run going (card #208). A run saved under other ids or numbers is
## not loaded.
static func of_content() -> String:
	var roots: Array[String] = [DATA_DIR]
	return compute_roots(roots, str(ProjectSettings.get_setting("application/config/version", "")))


## A short form of a fingerprint to show people ("a1b2c3d4"), so two builds are easy to compare.
static func short_id(fingerprint: String) -> String:
	return fingerprint.substr(0, 8)


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
