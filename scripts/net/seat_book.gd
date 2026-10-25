class_name SeatBook
extends RefCounted
## Host: the seats of an online game and their secret tokens, so a client that dropped can take its
## own seat back (DESIGN.md 9.2, card #205). Pure: no network, times are passed in (ms).
##
## Every welcomed client gets a token (random, made by NetSession) that only it knows. When its
## connection goes during a run its seat is kept "away" for the grace time. A new connection that
## shows the token gets that seat (and only that one) back under its new peer id. A token proves the
## seat: if the old connection still looks alive (the host has not noticed the drop yet), the
## claim wins and the old one is let go. A seat away long enough may go to a newcomer (card #304).
## A continued online run's seats come back held (card #313): away from the moment the host
## continued, each waiting for its own token as long as its own grace time. A newcomer never takes a
## held seat: it waits for its owner's token until its time is up, and is then given up (free).

## peer -> token.
var _tokens: Dictionary = {}
## peer -> when it went away (ms). Only away seats are here.
var _away_since: Dictionary = {}
## peer -> its own grace time (ms), for a held seat (hold()); the others use the caller's.
var _grace_of: Dictionary = {}


## Gives peer `peer` its seat with `token`. False if the peer already has one or the token is empty
## or taken.
func add(peer: int, token: String) -> bool:
	if peer <= 0 or token.is_empty() or _tokens.has(peer) or _tokens.values().has(token):
		return false
	_tokens[peer] = token
	return true


## A seat of a saved online run comes back (card #313): peer `peer` (the id it had) with `token`,
## away from `now_ms` and kept `grace_ms` for its token. False like add().
func hold(peer: int, token: String, now_ms: int, grace_ms: int) -> bool:
	if not add(peer, token):
		return false
	_away_since[peer] = now_ms
	_grace_of[peer] = maxi(0, grace_ms)
	return true


func has(peer: int) -> bool:
	return _tokens.has(peer)


## The token of peer `peer` ("" if it has no seat).
func token_of(peer: int) -> String:
	return String(_tokens.get(peer, ""))


## The peer holding the seat of `token` (0 if none).
func peer_of(token: String) -> int:
	if token.is_empty():
		return 0
	for peer: int in _tokens:
		if String(_tokens[peer]) == token:
			return peer
	return 0


## Peer `peer`'s connection went: its seat waits from `now_ms`. False if it has no seat or is
## already away.
func set_away(peer: int, now_ms: int) -> bool:
	if not _tokens.has(peer) or _away_since.has(peer):
		return false
	_away_since[peer] = now_ms
	return true


func is_away(peer: int) -> bool:
	return _away_since.has(peer)


## The away peers, in id order.
func away_peers() -> Array[int]:
	var list: Array[int] = []
	list.assign(_away_since.keys())
	list.sort()
	return list


## How many seats there are (welcomed and away).
func size() -> int:
	return _tokens.size()


## The away peer whose seat has waited longest, if it has waited at least `min_age_ms` by `now_ms`
## (0: none). A newcomer may take that seat (#304); a fresher one is held for its token. A held seat
## (hold()) is never one: its owner's token is still good until its own grace time runs out (#313).
func longest_away(now_ms: int, min_age_ms: int) -> int:
	var oldest := 0
	for peer: int in away_peers():
		if _grace_of.has(peer):
			continue
		# Id order: of two seats that went at the same moment, the lower peer is chosen.
		if oldest == 0 or int(_away_since[peer]) < int(_away_since[oldest]):
			oldest = peer
	if oldest == 0 or now_ms - int(_away_since[oldest]) < min_age_ms:
		return 0
	return oldest


## How long peer `peer`'s seat is still kept (ms, 0 when it is not away or the time is up). A held
## seat has its own grace time; the others `grace_ms`.
func time_left(peer: int, now_ms: int, grace_ms: int) -> int:
	if not _away_since.has(peer):
		return 0
	return maxi(0, int(_away_since[peer]) + _grace(peer, grace_ms) - now_ms)


## True for a seat that came back from a saved online run and still waits for its token (hold()).
func is_held(peer: int) -> bool:
	return _grace_of.has(peer)


func _grace(peer: int, grace_ms: int) -> int:
	return int(_grace_of.get(peer, grace_ms))


## A new connection `new_peer` shows `token`: it takes that seat (away or not). Returns the peer id
## the seat had (the caller rebinds the player and lets an old connection go), or 0 when the token
## is unknown or `new_peer` already has a seat.
func claim(token: String, new_peer: int) -> int:
	var old := peer_of(token)
	if old == 0 or new_peer <= 0 or old == new_peer or _tokens.has(new_peer):
		return 0
	_tokens.erase(old)
	_away_since.erase(old)
	# Back in: from now on the usual rules (a later drop keeps it for the usual grace time).
	_grace_of.erase(old)
	_tokens[new_peer] = token
	return old


## The away seats whose grace time ran out by `now_ms` (a held seat's own, the others `grace_ms`);
## they are forgotten (the caller gives the seat up as when a player leaves).
func expired(now_ms: int, grace_ms: int) -> Array[int]:
	var list: Array[int] = []
	for peer: int in away_peers():
		if now_ms - int(_away_since[peer]) >= _grace(peer, grace_ms):
			list.append(peer)
	for peer: int in list:
		remove(peer)
	return list


## Forgets peer `peer`'s seat.
func remove(peer: int) -> void:
	_tokens.erase(peer)
	_away_since.erase(peer)
	_grace_of.erase(peer)


func clear() -> void:
	_tokens.clear()
	_away_since.clear()
	_grace_of.clear()
