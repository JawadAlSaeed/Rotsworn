class_name SeatFile
extends RefCounted
## An online friend's seats in hosts' saved runs (DESIGN.md 9.2, card #313): for each host address,
## this machine's secret seat token there, so that joining that address again later (the game closed
## in between) takes the same seat back. Written whenever a run starts or goes on with this machine in
## it (so it always holds the token the host's autosaves keep, even when the host crashes or this
## machine was away when it saved) and when the host saves. A token the host no longer knows is
## harmless: it counts as none. One small JSON file; every function takes the path, so tests and bots
## never touch the player's own (NetSession.seat_file).

const PATH := "user://online_seat.json"


## Keeps `token` for the host at `address` (the tokens kept for other hosts stay). False if it could
## not be written (or nothing to keep).
static func save(address: String, token: String, path: String = PATH) -> bool:
	var host := address.strip_edges()
	if path.is_empty() or host.is_empty() or token.is_empty():
		return false
	var seats := _read(path)
	if String(seats.get(host, "")) == token:
		# Kept already (a rejoin, or the host's save after the run start): no write.
		return true
	seats[host] = token
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"seats": seats}))
	file.flush()
	var ok := file.get_error() == OK
	file.close()
	return ok


## The token kept for the host at `address` ("" : none, or a broken file).
static func token_for(address: String, path: String = PATH) -> String:
	return String(_read(path).get(address.strip_edges(), ""))


static func delete(path: String = PATH) -> void:
	if not path.is_empty() and FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## The kept tokens, address -> token (empty for no file or a broken one; a bad entry is left out).
static func _read(path: String) -> Dictionary:
	var out := {}
	if path.is_empty() or not FileAccess.file_exists(path):
		return out
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary \
			or not (json.data as Dictionary).get("seats") is Dictionary:
		return out
	var seats := (json.data as Dictionary).seats as Dictionary
	for address: Variant in seats:
		if typeof(address) == TYPE_STRING and typeof(seats[address]) == TYPE_STRING \
				and not String(seats[address]).is_empty():
			out[String(address)] = String(seats[address])
	return out
