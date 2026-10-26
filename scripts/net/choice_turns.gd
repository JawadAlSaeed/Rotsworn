class_name ChoiceTurns
extends RefCounted
## Host: whose turn it is to make the run's choices online (DESIGN.md 9.2 "Taking turns", card #314).
## Pure: Main asks it before each new choice screen (one map step, one stop's screen, one spoils
## pick), and the new screen belongs to the next seated player in seat order (P1, P2, P3, back to
## P1), skipping a seat that is away or still joining. The same screen shown
## again (a redraw, a result, a restock) keeps its owner. When the owner drops or leaves, the turn
## passes on to the next seated player. A friend's choice is applied only when it comes from the
## owner's machine for the screen now up (allows()). With taking turns off the host makes every
## choice, as before.

const HOST_PEER: int = 1

## Off: every choice is the host's (P1), the old way.
var enabled: bool = true
## The choice screen the turn is for ("" before the first one).
var key: String = ""
## The owner: their player index (seat, 0 = P1) and their machine's network peer.
var player: int = -1
var peer: int = HOST_PEER


## Forgets the turns (a new run begins with P1).
func reset() -> void:
	key = ""
	player = -1
	peer = HOST_PEER


## The players who can take a turn now, in seat order: the seated ones, not away and not joining
## (joining players are away too). P1, the host, is always there.
static func seated(roster: PlayerRoster) -> Array[int]:
	var list: Array[int] = []
	if roster == null:
		return list
	for i: int in roster.player_count():
		if not roster.is_away(i) and (i == 0 or i < roster.peers.size()):
			list.append(i)
	return list


## The first seated player at or after seat `from` (wrapping round to P1). P1 when none is.
static func next_seated(roster: PlayerRoster, from: int) -> int:
	var list := seated(roster)
	if list.is_empty():
		return 0
	for i: int in list:
		if i >= from:
			return i
	return list[0]


## The turn for choice screen `p_key`: a new screen goes to the next seated player after the owner
## (P1 for the first one); the same screen keeps its owner unless they are gone. True if the owner
## changed.
func turn_for(p_key: String, roster: PlayerRoster) -> bool:
	if p_key == key and player >= 0:
		return pass_if_gone(roster)
	key = p_key
	var before := peer
	var before_player := player
	if not enabled or roster == null or not roster.is_online():
		_give(0, roster)
	elif player < 0:
		_give(next_seated(roster, 0), roster)
	else:
		# The owner's seat now (seats move up when someone leaves), then the one after it.
		var at := roster.player_of_peer(peer)
		var from := (at + 1) if at >= 0 else player
		if from >= roster.player_count():
			from = 0
		_give(next_seated(roster, from), roster)
	return peer != before or player != before_player


## The owner went away, left, or is joining again: the turn passes to the next seated player (the
## one after their seat). True if it passed. Also follows the owner's seat moving up when someone
## before them left.
func pass_if_gone(roster: PlayerRoster) -> bool:
	if player < 0 or roster == null:
		return false
	if not enabled or not roster.is_online():
		var was := peer
		_give(0, roster)
		return peer != was
	var at := roster.player_of_peer(peer)
	if at >= 0 and not roster.is_away(at):
		player = at
		return false
	# Away: the seat after theirs. Gone: whoever moved up into their seat, or the next one.
	var from := (at + 1) if at >= 0 else player
	if from >= roster.player_count():
		from = 0
	_give(next_seated(roster, from), roster)
	return true


## True when a friend's choice from machine `from_peer` for screen `for_key` may be applied: it is
## that machine's turn on that screen.
func allows(from_peer: int, for_key: String) -> bool:
	return not key.is_empty() and for_key == key and from_peer == peer


## True when machine `my_peer` owns the turn.
func owns(my_peer: int) -> bool:
	return peer == my_peer


## What the clients get with each choice screen: {"key", "peer", "player"}.
func to_dict() -> Dictionary:
	return {"key": key, "peer": peer, "player": maxi(0, player)}


func _give(p_player: int, roster: PlayerRoster) -> void:
	player = p_player
	peer = HOST_PEER
	if roster != null and roster.is_online() and p_player >= 0 and p_player < roster.peers.size():
		peer = roster.peers[p_player]
