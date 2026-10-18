class_name SeatBook
extends RefCounted
## Host: the seats of an online game and their secret tokens, so a client that dropped can take its
## own seat back (DESIGN.md 9.2, card #205). Pure: no network, times are passed in (ms).
##
## Every welcomed client gets a token (random, made by NetSession) that only it knows. When its
## connection goes during a run its seat is kept "away" for the grace time. A new connection that
## shows the token gets that seat (and only that one) back under its new peer id. A token proves the
## seat: if the old connection still looks alive (the host has not noticed the drop yet), the
## claim wins and the old one is let go.

## peer -> token.
var _tokens: Dictionary = {}
## peer -> when it went away (ms). Only away seats are here.
var _away_since: Dictionary = {}


## Gives peer `peer` its seat with `token`. False if the peer already has one or the token is empty
## or taken.
func add(peer: int, token: String) -> bool:
	if peer <= 0 or token.is_empty() or _tokens.has(peer) or _tokens.values().has(token):
		return false
	_tokens[peer] = token
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


## How long peer `peer`'s seat is still kept (ms, 0 when it is not away or the time is up).
func time_left(peer: int, now_ms: int, grace_ms: int) -> int:
	if not _away_since.has(peer):
		return 0
	return maxi(0, int(_away_since[peer]) + grace_ms - now_ms)


## A new connection `new_peer` shows `token`: it takes that seat (away or not). Returns the peer id
## the seat had (the caller rebinds the player and lets an old connection go), or 0 when the token
## is unknown or `new_peer` already has a seat.
func claim(token: String, new_peer: int) -> int:
	var old := peer_of(token)
	if old == 0 or new_peer <= 0 or old == new_peer or _tokens.has(new_peer):
		return 0
	_tokens.erase(old)
	_away_since.erase(old)
	_tokens[new_peer] = token
	return old


## The away seats whose grace time ran out by `now_ms`; they are forgotten (the caller gives the
## seat up as when a player leaves).
func expired(now_ms: int, grace_ms: int) -> Array[int]:
	var list: Array[int] = []
	for peer: int in away_peers():
		if now_ms - int(_away_since[peer]) >= grace_ms:
			list.append(peer)
	for peer: int in list:
		remove(peer)
	return list


## Forgets peer `peer`'s seat.
func remove(peer: int) -> void:
	_tokens.erase(peer)
	_away_since.erase(peer)


func clear() -> void:
	_tokens.clear()
	_away_since.clear()
