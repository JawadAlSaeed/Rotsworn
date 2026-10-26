class_name SavedSeats
extends RefCounted
## The seats of an online run kept in the host's online save slot (DESIGN.md 8.14, 9.3, card #313).
## Pure: no network, no files, no clock.
##
## The save keeps who held which hero (the roster, each friend's seat with the peer id it had then)
## and each seat's secret token (SeatBook). Continuing brings the roster back with every friend's seat
## away: the host plays those heroes, as for a dropped friend, until their owner is back. Friends on
## the host's players screen when it continues sit down at once (seat_lobby): a token that names a
## saved seat takes that seat; anyone else takes the next saved seat nobody took (most likely their
## own, back without the token), then a free seat by the drop-in donor rule; with neither they are
## turned away ("Game full"). Friends who come later get in by the usual rejoin and drop-in rules
## (JoinGate), the saved seats waiting for their tokens (SeatBook.hold).

const HOST_PEER: int = 1


## What the save keeps of `roster` (the host's) and `seats` (their tokens): {roster:
## PlayerRoster.to_dict(), tokens: {"<peer>": token}}. Every friend with a seat is kept, here or away.
static func capture(roster: PlayerRoster, seats: SeatBook) -> Dictionary:
	if roster == null or seats == null:
		return {}
	var tokens := {}
	for player: int in range(1, roster.peers.size()):
		var token := seats.token_of(roster.peers[player])
		if not token.is_empty():
			tokens[str(roster.peers[player])] = token
	return {"roster": roster.to_dict(), "tokens": tokens}


## The saved tokens, old peer -> token (an entry that is not a friend's peer and a token is left out).
static func tokens_of(data: Dictionary) -> Dictionary:
	var out := {}
	if not data.get("tokens") is Dictionary:
		return out
	var tokens := data.tokens as Dictionary
	for key: Variant in tokens:
		var peer := str(key).to_int() if str(key).is_valid_int() else 0
		var token: Variant = tokens[key]
		if peer > HOST_PEER and typeof(token) == TYPE_STRING and not String(token).is_empty():
			out[peer] = String(token)
	return out


## The saved roster as it comes back on the host (local peer HOST_PEER) for a party of `hero_count`
## heroes: every friend's seat away (none joining), the heroes as they were. A seat with no token
## cannot be claimed, so it is given up (its heroes go to the host, later seats move up). Null when
## the data does not fit (the caller then continues with the host alone).
static func restore(data: Dictionary, hero_count: int) -> PlayerRoster:
	if not data.get("roster") is Dictionary:
		return null
	var roster := PlayerRoster.from_dict(data.roster as Dictionary, HOST_PEER)
	if roster == null or not roster.is_online() or roster.peers[0] != HOST_PEER or roster.hero_count() != hero_count:
		return null
	var tokens := tokens_of(data)
	for player: int in range(roster.player_count() - 1, 0, -1):
		if not tokens.has(roster.peers[player]):
			roster.drop_peer(roster.peers[player])
	roster.joining.clear()
	roster.away.clear()
	for player: int in range(1, roster.player_count()):
		roster.away.append(player)
	return roster


## Seats the friends on the host's players screen into `roster` (from restore(); changed in place).
## `tokens`: tokens_of() the save; `lobby`: their peers in the order they joined; `shown`: peer -> the
## token their hello carried ("" or missing: none). Returns {seated: {peer: player}, refused: [peer],
## waiting: {old peer: token}}: `waiting` are the saved seats still away, to keep for their tokens.
static func seat_lobby(roster: PlayerRoster, tokens: Dictionary, lobby: Array[int], shown: Dictionary) -> Dictionary:
	var waiting := tokens.duplicate()
	var seated := {}
	var refused: Array[int] = []
	var rest: Array[int] = []
	# A token that names a saved seat takes it, whatever the order they joined in.
	for peer: int in lobby:
		var old := _peer_with(waiting, String(shown.get(peer, "")))
		if old > 0 and _sit(roster, old, peer):
			waiting.erase(old)
			seated[peer] = roster.player_of_peer(peer)
		else:
			rest.append(peer)
	# Anyone else: the next saved seat nobody took (seat order), then a free seat.
	for peer: int in rest:
		var old := _first_waiting(roster, waiting)
		if old > 0 and _sit(roster, old, peer):
			waiting.erase(old)
			seated[peer] = roster.player_of_peer(peer)
		elif roster.join_peer_midrun(peer) >= 0 and roster.set_back(peer):
			seated[peer] = roster.player_of_peer(peer)
		else:
			refused.append(peer)
	return {"seated": seated, "refused": refused, "waiting": waiting}


## The old peer whose saved token is `token` (0: none).
static func _peer_with(waiting: Dictionary, token: String) -> int:
	if token.is_empty():
		return 0
	for old: int in waiting:
		if String(waiting[old]) == token:
			return old
	return 0


## The waiting saved seat that comes first in seat order (0: none).
static func _first_waiting(roster: PlayerRoster, waiting: Dictionary) -> int:
	for player: int in range(1, roster.peers.size()):
		if waiting.has(roster.peers[player]):
			return roster.peers[player]
	return 0


## Peer `peer` takes the seat `old` had and plays it at once.
static func _sit(roster: PlayerRoster, old: int, peer: int) -> bool:
	return roster.rebind_peer(old, peer) > 0 and roster.set_back(peer)
