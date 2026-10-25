class_name NetSession
extends Node
## Online sessions (DESIGN.md 9.2), registered as the autoload "Net" so every machine has it at the
## same node path (/root/Net), which Godot's RPCs need. Host-authoritative: the host listens, each
## client connects to it, clients never talk to each other.
##
## The transport is a Godot MultiplayerPeer (ENet over an IP address today). Everything above it
## (handshake, messages) only uses the high-level multiplayer API, so another peer type (for
## example Steam's) can replace ENet without touching the game.
##
## Handshake: a client sends its content fingerprint (DataHash) first. The host answers welcome or
## refuse (JoinGate decides who gets in, and how); a refused client is dropped. Until welcomed, a
## client's messages are ignored.
##
## Rejoining (card #205): the welcome carries a secret seat token (SeatBook), kept in memory on both
## sides. A client whose connection goes during a run keeps its seat "away" for
## `net_rejoin_grace_ms`; joining again from the Join screen sends the token with the hello and
## gets that seat back (the build fingerprint is checked first, as always). Both ends ping each
## other, and a connection that stays silent for `net_drop_min_ms` .. `net_drop_max_ms` counts as
## lost, so a pulled cable never freezes a fight for long.
##
## Dropping in (card #304): while the host has `drop_in_open`, a newcomer is welcomed into the run
## going on (a free seat, or a seat away at least `net_takeover_after_ms`: a friend whose game
## crashed comes back this way when their seat file kept no token), once Main's `drop_in_check` lets them in. A player who got in
## mid-run (dropped in, or back with a token) gets their heroes in two steps: their machine catches
## up with the host (the place screen built, or the fight showing the host's resume) and sends
## "seated_ready"; the host hands the heroes over then, or at the fight's next quiet moment.
##
## Messages are (kind: String, payload: Dictionary) pairs of plain data. They are reliable and keep
## their order on one channel (game flow and combat must never overtake each other).

## The connection state changed (State).
signal state_changed(state: int)
## Client: the host refused us or could not be reached (reason for the player).
signal refused(reason: String)
## Host: a client passed the handshake. Client: we were welcomed (peer = our own id).
signal peer_joined(peer: int)
## Host: a welcomed client left (or its seat's grace time ran out).
signal peer_left(peer: int)
## Host: a welcomed client's connection went during a run; its seat is kept for the grace time.
signal peer_away(peer: int)
## Host: the client that had `old_peer` joined again as `new_peer` (its seat token matched).
signal peer_rejoined(old_peer: int, new_peer: int)
## Host: a newcomer got in during a run (card #304): a new seat (old_peer 0) or the away seat of old_peer.
signal peer_dropped_in(peer: int, old_peer: int)
## Client: the host is gone.
signal host_lost
## A message from `from_peer` (1 = the host).
signal message_received(from_peer: int, kind: String, payload: Dictionary)

enum State { OFFLINE, HOSTING, CONNECTING, CONNECTED }

const TUNING_PATH := "res://data/tuning/tuning.tres"
const HOST_PEER: int = 1
## Bumped when the handshake or the message format changes in a way the fingerprint cannot show.
## 3: the welcome says whether it seats us mid-run, combat batches carry their fight's seed, and a
## client that got in mid-run sends "seated_ready" (card #304).
## 4: "lobby", "again" and "run_start" say which game mode it is, and that mode's own screens go
## out (card #312; that second mode is cut in 8).
## 5: a run without zones (DESIGN.md 8.22): "stop_fight" starts a Fight or Guard stop's fight, which
## the friend builds from the run state; the zone messages ("zone", "zone_fight", "zone_back") and
## the unreliable zone positions are gone.
## 6: the run's choices go in turns (card #314): choice screens carry "turn", a friend sends "choice"
## on their turn, the host sends "turn" when it passes on and "gift" (a find to place, numbered), and
## the friend's backpack answers with a "hand_out" bag op carrying that number.
## Card #313's "saved" (the host saved the run; the friends go home keeping their seats) needs no
## bump: the fingerprint (DataHash.of_game) already keeps other builds out, as for #320's "opening".
## 7: Relics without slots (cards #326, #327, DESIGN.md 8.24): a friend's pick carries "hero" (who
## gets the Relic), the rotten chest's pick is its own "relic" choice, the "give" bag op replaces
## "wear", "swap_gear" and "take_off", and the Echo ops are gone.
## 8: the second game mode is cut (card #331, DESIGN.md 8.21): "lobby", "again" and "run_start"
## carry no "mode" (nor "run_start" its "records"), and that mode's screens are gone.
## 9: the pack holds consumables only (card #332, DESIGN.md 8.1): the run state carries "curses" and
## no "tonics_used", a pack entry has no level, the "combine" bag op and the campfire's "upgrade"
## choice are gone, and the shop's "cleanse" choice names a curse by its "index".
const PROTOCOL: int = 9
## Client: the host could not be reached (short: it can end as a main menu notice).
const REASON_UNREACHABLE := "Host not found"
## Channel for every message (flow and combat).
const RELIABLE_CHANNEL: int = 0
## Most clients the host takes (three players: the host and two clients).
const MAX_CLIENTS: int = PlayerRoster.MAX_PLAYERS - 1
## A refused client is dropped this long after the refusal, so the message arrives first.
const REFUSE_LINGER_S: float = 0.5
## A client leaving on purpose closes its connection this long after its goodbye.
const BYE_LINGER_S: float = 0.25
## ENet's own factor for its resend timeout (its default); the drop times come from tuning.
const ENET_TIMEOUT_LIMIT: int = 32
## Bytes of randomness in a seat token.
const TOKEN_BYTES: int = 16

var state: int = State.OFFLINE
var _tuning: Tuning
var _fingerprint: String = ""
## Host: peers that passed the handshake (peer -> true), and when each unverified peer connected.
var _welcomed: Dictionary = {}
var _pending_since_ms: Dictionary = {}
## Host: clients that said goodbye (they left on purpose: no seat is kept for them).
var _leaving: Dictionary = {}
var _connect_started_ms: int = 0
## When on, a run started: the host refuses new clients unless drop_in_open; a seat's token always
## gets back into its own seat.
var closed: bool = false
## Host: newcomers are seated in the running run (Main opens it once the run is on and shuts it when
## the run is decided, card #304). Off: only a seat's token gets into a started game.
var drop_in_open: bool = false
## Host: asked before a newcomer is welcomed into the run (card #304) with the away seat it would
## take (0: a new seat); returns "" to let them in, else the refusal text. Main sets it, so a
## refusal never comes after a welcome.
var drop_in_check: Callable = Callable()
## Host: the seats and their tokens.
var seats := SeatBook.new()
## Client: our seat token and the address we joined (kept after leave(), so a dropped player can
## join again; forget_seat() clears the token), and whether the last welcome gave a seat back.
var _seat_token: String = ""
var _seat_address: String = ""
var rejoined: bool = false
## Client: the last welcome seated us in a run already going (card #304).
var joined_mid_run: bool = false
## Client: the file that keeps our seat in a host's saved run (SeatFile, card #313; "" : none, a bot
## without --seat-path). Joining with no token in memory sends the one kept there for that address.
var seat_file: String = ""
## Host: the token each players screen hello carried (peer -> token), so a Continue can give a friend
## back their seat in the saved run (card #313).
var _shown_tokens: Dictionary = {}
## Dev (--drop-after): the connection we dropped without a word, kept but never serviced again, so
## the host only notices through the heartbeat, as with a pulled cable.
var _silent_peer: MultiplayerPeer
## Connections that said goodbye and close a moment later (held so they are not freed at once).
var _closing: Array[MultiplayerPeer] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_tuning = load(TUNING_PATH) as Tuning
	if _tuning == null:
		_tuning = Tuning.new()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if state == State.CONNECTING and now - _connect_started_ms > _tuning.net_connect_timeout_ms:
		_fail("The host did not answer.")
	elif state == State.HOSTING:
		for peer: int in _pending_since_ms.keys():
			if now - int(_pending_since_ms[peer]) > _tuning.net_connect_timeout_ms:
				_pending_since_ms.erase(peer)
				_kick(peer)
		for peer: int in seats.expired(now, _tuning.net_rejoin_grace_ms):
			peer_left.emit(peer)


## Starts hosting on `port` (0 = the tuning port). Returns OK or the error.
func host(port: int = 0) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	# One spare connection: a player coming back can get in before the host has noticed their old
	# connection die (the handshake still keeps the game at MAX_CLIENTS).
	var err := peer.create_server(port if port > 0 else _tuning.net_port, MAX_CLIENTS + 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	multiplayer.server_relay = false
	closed = false
	seats.clear()
	_set_state(State.HOSTING)
	return OK


## Connects to a host at `address` (`port` 0 = the tuning port). The answer comes as peer_joined
## (welcomed) or refused.
func join(address: String, port: int = 0) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address.strip_edges(), port if port > 0 else _tuning.net_port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_connect_started_ms = Time.get_ticks_msec()
	rejoined = false
	joined_mid_run = false
	if _seat_address != address.strip_edges():
		# A seat token is only worth showing to the host that gave it.
		_seat_token = ""
	_seat_address = address.strip_edges()
	if _seat_token.is_empty():
		# A seat in this host's saved run, kept when it saved (the game was closed since, card #313).
		_seat_token = SeatFile.token_for(_seat_address, seat_file)
	_set_state(State.CONNECTING)
	return OK


## Closes the connection (if any) and goes back offline. A client still connected says goodbye
## first, so the host gives its seat up at once instead of keeping it for a rejoin (`goodbye`
## false: the host is already gone).
func leave(goodbye: bool = true) -> void:
	if goodbye and state == State.CONNECTED:
		_bye.rpc_id(HOST_PEER)
		var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
		if enet != null and enet.host != null:
			enet.host.flush()
		_seat_token = ""
		# The host handles a disconnect before the messages that came with it, so the line goes
		# down a moment later, after the goodbye was read.
		_closing.append(multiplayer.multiplayer_peer)
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		get_tree().create_timer(BYE_LINGER_S, true, false, true).timeout.connect(_close_oldest)
	if multiplayer.multiplayer_peer != null and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_welcomed.clear()
	_pending_since_ms.clear()
	_leaving.clear()
	_shown_tokens.clear()
	seats.clear()
	closed = false
	drop_in_open = false
	_set_state(State.OFFLINE)


func _close_oldest() -> void:
	if not _closing.is_empty():
		_closing.pop_front().close()


## Client: true while we hold a seat token (we were in a game and may join it again).
func has_seat() -> bool:
	return not _seat_token.is_empty()


## Client: the address of the host whose seat we hold ("" if none).
func seat_address() -> String:
	return _seat_address if has_seat() else ""


## Client: forgets our seat (the run is over, or the host ended the game).
func forget_seat() -> void:
	_seat_token = ""


## Client: our seat token ("" : none), to keep for the host's saved run (card #313).
func seat_token() -> String:
	return _seat_token


## Host: the seat token peer `peer`'s hello carried on the players screen ("" : none).
func shown_token(peer: int) -> String:
	return String(_shown_tokens.get(peer, ""))


## Host: a seat of the saved run comes back away, kept for its token (card #313): peer `peer` (the id
## it had) for `net_saved_seat_grace_ms`, the usual rejoin and drop-in rules otherwise.
func hold_seat(peer: int, token: String) -> bool:
	return state == State.HOSTING and peer != HOST_PEER and not _welcomed.has(peer) \
			and seats.hold(peer, token, Time.get_ticks_msec(), _tuning.net_saved_seat_grace_ms)


## Client: the address we joined (the pause menu shows it so a friend can drop in too).
func joined_address() -> String:
	return _seat_address


## Dev (--drop-after): the client drops off the network without telling the host, like a pulled
## cable. The host finds out through the heartbeat; this machine reacts as to a lost host.
func drop_silently() -> void:
	if state != State.CONNECTED:
		return
	# Never polled again: no answer, no goodbye.
	_silent_peer = multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_welcomed.clear()
	_set_state(State.OFFLINE)
	host_lost.emit()


## Host: how long the seat of away peer `peer` is still kept (ms).
func seat_time_left(peer: int) -> int:
	return seats.time_left(peer, Time.get_ticks_msec(), _tuning.net_rejoin_grace_ms)


func is_online() -> bool:
	return state == State.HOSTING or state == State.CONNECTED


func is_host() -> bool:
	return state == State.HOSTING


func is_client() -> bool:
	return state == State.CONNECTED


## This machine's peer id (1 for the host, 0 offline).
func my_peer() -> int:
	return multiplayer.get_unique_id() if is_online() else 0


## Host: the welcomed clients.
func clients() -> Array[int]:
	var list: Array[int] = []
	list.assign(_welcomed.keys())
	list.sort()
	return list


## Host: removes a client.
func kick(peer: int) -> void:
	_kick(peer)


## Host: turns away a peer that was already welcomed (a seat that could not be given after all):
## the reason reaches it first, its seat is forgotten, and no away or left signal follows.
func refuse(peer: int, reason: String) -> void:
	if state != State.HOSTING:
		return
	_welcomed.erase(peer)
	seats.remove(peer)
	_refuse_peer(peer, reason)


## The content fingerprint (computed once).
func fingerprint() -> String:
	if _fingerprint.is_empty():
		_fingerprint = DataHash.of_game()
	return _fingerprint


## The local network addresses a friend can join (IPv4, not loopback), for the host's screen.
static func local_addresses() -> Array[String]:
	var list: Array[String] = []
	for address: String in IP.get_local_addresses():
		if address.count(".") == 3 and not address.begins_with("127.") and not address.begins_with("169.254."):
			list.append(address)
	list.sort()
	return list


# --- sending ----------------------------------------------------------------------------------

## Client: a message to the host.
func send_to_host(kind: String, payload: Dictionary = {}) -> void:
	if state == State.CONNECTED:
		_to_host.rpc_id(HOST_PEER, kind, payload)


## Host: a message to every welcomed client.
func broadcast(kind: String, payload: Dictionary = {}) -> void:
	if state != State.HOSTING:
		return
	for peer: int in _welcomed:
		_to_client.rpc_id(peer, kind, payload)


## Host: a message to one welcomed client.
func send_to(peer: int, kind: String, payload: Dictionary = {}) -> void:
	if state == State.HOSTING and _welcomed.has(peer):
		_to_client.rpc_id(peer, kind, payload)


# --- RPCs -------------------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable", RELIABLE_CHANNEL)
func _hello(their_fingerprint: Variant, their_protocol: Variant, their_token: Variant) -> void:
	if state != State.HOSTING:
		return
	var peer := multiplayer.get_remote_sender_id()
	_pending_since_ms.erase(peer)
	var token := String(their_token) if typeof(their_token) == TYPE_STRING else ""
	if typeof(their_protocol) != TYPE_INT or int(their_protocol) != PROTOCOL \
			or typeof(their_fingerprint) != TYPE_STRING or String(their_fingerprint) != fingerprint():
		var theirs := DataHash.short_id(String(their_fingerprint)) if typeof(their_fingerprint) == TYPE_STRING else "?"
		_refuse_peer(peer, "Your game is a different version from the host's (yours %s, the host's %s). Both need the same build." \
				% [theirs, DataHash.short_id(fingerprint())])
		return
	var gate := JoinGate.decide(closed, drop_in_open, seats.peer_of(token), seats.size(),
			seats.longest_away(Time.get_ticks_msec(), _tuning.net_takeover_after_ms), MAX_CLIENTS)
	match int(gate.verdict):
		JoinGate.Verdict.REJOIN:
			# Our player is back: a seat's token gets into a started game, and only into that seat.
			var old := seats.claim(token, peer)
			if _welcomed.erase(old):
				# The host had not noticed the old connection die yet: it is let go.
				_kick(old)
			_welcomed[peer] = true
			_welcome.rpc_id(peer, token, true, false)
			peer_rejoined.emit(old, peer)
		JoinGate.Verdict.LOBBY:
			if not token.is_empty():
				# It may name a seat of the host's saved run (a Continue gives it back, card #313).
				_shown_tokens[peer] = token
			var fresh := _new_token()
			seats.add(peer, fresh)
			_welcomed[peer] = true
			_welcome.rpc_id(peer, fresh, false, false)
			peer_joined.emit(peer)
		JoinGate.Verdict.NEW_SEAT, JoinGate.Verdict.TAKE_AWAY:
			_drop_in(peer, int(gate.old_peer))
		_:
			_refuse_peer(peer, String(gate.reason))


## Host: a newcomer comes into the running run (card #304): a new seat (`old_peer` 0) or the away
## seat of `old_peer`, whose token stops working. Main is asked first, so it never has to turn away
## a peer that was already welcomed.
func _drop_in(peer: int, old_peer: int) -> void:
	var answer: Variant = drop_in_check.call(old_peer) if drop_in_check.is_valid() else JoinGate.REASON_CLOSED
	var why := String(answer) if typeof(answer) == TYPE_STRING else JoinGate.REASON_CLOSED
	if not why.is_empty():
		_refuse_peer(peer, why)
		return
	if old_peer > 0:
		seats.remove(old_peer)
	var fresh := _new_token()
	seats.add(peer, fresh)
	_welcomed[peer] = true
	_welcome.rpc_id(peer, fresh, false, true)
	peer_dropped_in.emit(peer, old_peer)


@rpc("authority", "call_remote", "reliable", RELIABLE_CHANNEL)
func _welcome(token: Variant, was_rejoin: Variant, mid_run: Variant) -> void:
	if state != State.CONNECTING:
		return
	_seat_token = String(token) if typeof(token) == TYPE_STRING else ""
	rejoined = typeof(was_rejoin) == TYPE_BOOL and bool(was_rejoin)
	joined_mid_run = typeof(mid_run) == TYPE_BOOL and bool(mid_run)
	_set_state(State.CONNECTED)
	peer_joined.emit(multiplayer.get_unique_id())


@rpc("any_peer", "call_remote", "reliable", RELIABLE_CHANNEL)
func _bye() -> void:
	var peer := multiplayer.get_remote_sender_id()
	if state == State.HOSTING and _welcomed.has(peer):
		_leaving[peer] = true


@rpc("authority", "call_remote", "reliable", RELIABLE_CHANNEL)
func _refuse(reason: Variant) -> void:
	_fail(str(reason))


@rpc("any_peer", "call_remote", "reliable", RELIABLE_CHANNEL)
func _to_host(kind: Variant, payload: Variant) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if state != State.HOSTING or not _welcomed.has(peer):
		return
	if typeof(kind) != TYPE_STRING or typeof(payload) != TYPE_DICTIONARY:
		return
	message_received.emit(peer, String(kind), payload as Dictionary)


@rpc("authority", "call_remote", "reliable", RELIABLE_CHANNEL)
func _to_client(kind: Variant, payload: Variant) -> void:
	if state != State.CONNECTED or typeof(kind) != TYPE_STRING or typeof(payload) != TYPE_DICTIONARY:
		return
	message_received.emit(HOST_PEER, String(kind), payload as Dictionary)


# --- connection events ------------------------------------------------------------------------

func _on_peer_connected(peer: int) -> void:
	if state == State.HOSTING:
		_pending_since_ms[peer] = Time.get_ticks_msec()
		_set_heartbeat(peer)


func _on_peer_disconnected(peer: int) -> void:
	_pending_since_ms.erase(peer)
	_shown_tokens.erase(peer)
	var said_goodbye := _leaving.erase(peer)
	if state != State.HOSTING or not _welcomed.erase(peer):
		return
	if closed and not said_goodbye and _tuning.net_rejoin_grace_ms > 0 and seats.set_away(peer, Time.get_ticks_msec()):
		peer_away.emit(peer)
	else:
		seats.remove(peer)
		peer_left.emit(peer)


func _on_connected_to_server() -> void:
	_set_heartbeat(HOST_PEER)
	_hello.rpc_id(HOST_PEER, fingerprint(), PROTOCOL, _seat_token)


## The heartbeat: ENet pings the other end all the time; this bounds how long a silent connection
## may go unanswered before it counts as lost (tuning).
func _set_heartbeat(peer: int) -> void:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return
	var link := enet.get_peer(peer)
	if link != null:
		link.set_timeout(ENET_TIMEOUT_LIMIT, _tuning.net_drop_min_ms, maxi(_tuning.net_drop_min_ms, _tuning.net_drop_max_ms))


func _new_token() -> String:
	return Crypto.new().generate_random_bytes(TOKEN_BYTES).hex_encode()


func _on_connection_failed() -> void:
	_fail(REASON_UNREACHABLE)


func _on_server_disconnected() -> void:
	var was_connected := state == State.CONNECTED
	leave(false)
	if was_connected:
		host_lost.emit()
	else:
		refused.emit("The host closed the connection.")


func _refuse_peer(peer: int, reason: String) -> void:
	_refuse.rpc_id(peer, reason)
	# Let the refusal arrive before the line goes down.
	get_tree().create_timer(REFUSE_LINGER_S).timeout.connect(_kick.bind(peer))


func _kick(peer: int) -> void:
	# A refused client usually hangs up itself before the linger is over: nothing left to cut (ENet
	# would print an error).
	if state == State.HOSTING and multiplayer.get_peers().has(peer):
		multiplayer.multiplayer_peer.disconnect_peer(peer)


func _fail(reason: String) -> void:
	leave()
	refused.emit(reason)


func _set_state(new_state: int) -> void:
	if state == new_state:
		return
	state = new_state
	state_changed.emit(state)
