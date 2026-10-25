class_name SeatFile
extends RefCounted
## An online friend's seat in the host's saved run (DESIGN.md 9.2, card #313): the host's address and
## this machine's secret seat token, written when the host saves the run, so that joining that address
## again later (the game closed in between) takes the same seat back. One small JSON file; every
## function takes the path, so tests and bots never touch the player's own (NetSession.seat_file).

const PATH := "user://online_seat.json"


## Keeps `token` for the host at `address`. False if it could not be written (or nothing to keep).
static func save(address: String, token: String, path: String = PATH) -> bool:
	if path.is_empty() or address.strip_edges().is_empty() or token.is_empty():
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"address": address.strip_edges(), "token": token}))
	file.flush()
	var ok := file.get_error() == OK
	file.close()
	return ok


## The token kept for the host at `address` ("" : none, another host's, or a broken file).
static func token_for(address: String, path: String = PATH) -> String:
	if path.is_empty() or not FileAccess.file_exists(path):
		return ""
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return ""
	var kept := json.data as Dictionary
	if typeof(kept.get("address")) != TYPE_STRING or typeof(kept.get("token")) != TYPE_STRING:
		return ""
	return String(kept.token) if String(kept.address) == address.strip_edges() else ""


static func delete(path: String = PATH) -> void:
	if not path.is_empty() and FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
