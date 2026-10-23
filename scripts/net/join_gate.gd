class_name JoinGate
extends RefCounted
## Host: who may come into an online game, and how (DESIGN.md 9.2, 9.3; cards #205, #304). Pure:
## NetSession._hello asks it after the build check; Main asks ready_action() when a client that got
## in mid-run says it has caught up.
##
## Before a run (the players screen is up) friends join the lobby while a seat is free. Once a run
## started only a seat's token gets back into its own seat, unless the host has drop-in open: then a
## newcomer gets a free seat, or the seat of the player away longest (a friend whose game crashed
## comes back this way) once that seat has waited long enough to not be a quick rejoin.

enum Verdict { REFUSE, LOBBY, REJOIN, NEW_SEAT, TAKE_AWAY }
## What the host does with a client's "seated_ready": nothing yet, hand the heroes over now (no fight
## on), or at the fight's next quiet moment.
enum Ready { IGNORE, SEAT_NOW, AT_QUIET }

## Refusal texts (short, no second sentence: they can end as a main menu notice).
const REASON_FULL := "Game full"
const REASON_CLOSED := "Run busy, try again"


## `closed`: a run started (the players screen is shut). `drop_in_open`: the host seats newcomers in
## the run now. `token_peer`: the peer whose seat the hello's token names (0: none or unknown).
## `seats_used`: seats taken (welcomed, joining and away). `away_peer`: the away seat that has waited
## longest, if it has waited at least net_takeover_after_ms (0: none; a fresher one is held for its
## token). Returns {verdict: Verdict, old_peer: int, reason: String}.
static func decide(closed: bool, drop_in_open: bool, token_peer: int, seats_used: int, away_peer: int,
		max_clients: int) -> Dictionary:
	if closed and token_peer > 0:
		# A seat's token works even with drop-in shut, as before drop-in existed (card #205).
		return _verdict(Verdict.REJOIN, token_peer)
	if not closed:
		if seats_used < max_clients:
			return _verdict(Verdict.LOBBY)
		return _refusal(REASON_FULL)
	if not drop_in_open:
		return _refusal(REASON_CLOSED)
	if away_peer > 0:
		# An old enough away seat goes before a free one: it is most likely the crashed friend.
		return _verdict(Verdict.TAKE_AWAY, away_peer)
	if seats_used < max_clients:
		return _verdict(Verdict.NEW_SEAT)
	return _refusal(REASON_FULL)


## A client that got in mid-run says it shows `client_fight` (the fight seed, 0: a place screen);
## the host is in fight `host_fight` (see host_fight(); 0: none). Same fight: AT_QUIET; neither in a fight:
## SEAT_NOW; else IGNORE (the client is behind or ahead and says so again at its next screen or fight).
static func ready_action(client_fight: int, host_fight: int) -> int:
	if client_fight != host_fight:
		return Ready.IGNORE
	return Ready.SEAT_NOW if client_fight == 0 else Ready.AT_QUIET


## The fight the host is in, for ready_action: the one it announced (`announced`, its seed; 0: none),
## even while its swirl runs and nothing is built yet, else the one in the tree (`built`; 0: none).
## So a client's "caught up on the place screen" that lands during the swirl is ignored, and its
## heroes never come back before its own screen shows that fight.
static func host_fight(announced: int, built: int) -> int:
	return announced if announced != 0 else built


static func _verdict(verdict: Verdict, old_peer: int = 0) -> Dictionary:
	return {"verdict": verdict, "old_peer": old_peer, "reason": ""}


static func _refusal(reason: String) -> Dictionary:
	return {"verdict": Verdict.REFUSE, "old_peer": 0, "reason": reason}
