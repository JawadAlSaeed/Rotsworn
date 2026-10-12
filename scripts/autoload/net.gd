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
## refuse; a refused client is dropped. Until welcomed, a client's messages are ignored.
##
## Messages are (kind: String, payload: Dictionary) pairs of plain data. Reliable ones keep their
## order on one channel (game flow and combat must never overtake each other); position updates go
## unreliable on their own channel.

## The connection state changed (State).
signal state_changed(state: int)
## Client: the host refused us or could not be reached (reason for the player).
signal refused(reason: String)
## Host: a client passed the handshake. Client: we were welcomed (peer = our own id).
signal peer_joined(peer: int)
## Host: a welcomed client left.
signal peer_left(peer: int)
## Client: the host is gone.
signal host_lost
## A message from `from_peer` (1 = the host).
signal message_received(from_peer: int, kind: String, payload: Dictionary)

enum State { OFFLINE, HOSTING, CONNECTING, CONNECTED }

const TUNING_PATH := "res://data/tuning/tuning.tres"
const HOST_PEER: int = 1
## Channel for reliable messages (flow and combat) and for unreliable position updates.
const RELIABLE_CHANNEL: int = 0
const FAST_CHANNEL: int = 1
## Most clients the host takes (three players: the host and two clients).
const MAX_CLIENTS: int = PlayerRoster.MAX_PLAYERS - 1
## A refused client is dropped this long after the refusal, so the message arrives first.
const REFUSE_LINGER_S: float = 0.5

var state: int = State.OFFLINE
var _tuning: Tuning
var _fingerprint: String = ""
## Host: peers that passed the handshake (peer -> true), and when each unverified peer connected.
var _welcomed: Dictionary = {}
var _pending_since_ms: Dictionary = {}
var _connect_started_ms: int = 0
## When on, the host refuses new clients (a run started).
var closed: bool = false


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


## Starts hosting on `port` (0 = the tuning port). Returns OK or the error.
func host(port: int = 0) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port if port > 0 else _tuning.net_port, MAX_CLIENTS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	multiplayer.server_relay = false
	closed = false
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
	_set_state(State.CONNECTING)
	return OK


## Closes the connection (if any) and goes back offline.
func leave() -> void:
	if multiplayer.multiplayer_peer != null and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_welcomed.clear()
	_pending_since_ms.clear()
	closed = false
	_set_state(State.OFFLINE)


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


## Host: an unreliable message (positions) to every welcomed client; a lost one is just skipped.
func broadcast_fast(kind: String, payload: Dictionary = {}) -> void:
	if state != State.HOSTING:
		return
	for peer: int in _welcomed:
		_to_client_fast.rpc_id(peer, kind, payload)


# --- RPCs -------------------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable", RELIABLE_CHANNEL)
func _hello(their_fingerprint: Variant) -> void:
	if state != State.HOSTING:
		return
	var peer := multiplayer.get_remote_sender_id()
	_pending_since_ms.erase(peer)
	if closed:
		_refuse_peer(peer, "The game has already started.")
	elif _welcomed.size() >= MAX_CLIENTS:
		_refuse_peer(peer, "The game is full.")
	elif typeof(their_fingerprint) != TYPE_STRING or String(their_fingerprint) != fingerprint():
		_refuse_peer(peer, "Your game is a different version from the host's. Both need the same build.")
	else:
		_welcomed[peer] = true
		_welcome.rpc_id(peer)
		peer_joined.emit(peer)


@rpc("authority", "call_remote", "reliable", RELIABLE_CHANNEL)
func _welcome() -> void:
	if state != State.CONNECTING:
		return
	_set_state(State.CONNECTED)
	peer_joined.emit(multiplayer.get_unique_id())


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


@rpc("authority", "call_remote", "unreliable_ordered", FAST_CHANNEL)
func _to_client_fast(kind: Variant, payload: Variant) -> void:
	if state != State.CONNECTED or typeof(kind) != TYPE_STRING or typeof(payload) != TYPE_DICTIONARY:
		return
	message_received.emit(HOST_PEER, String(kind), payload as Dictionary)


# --- connection events ------------------------------------------------------------------------

func _on_peer_connected(peer: int) -> void:
	if state == State.HOSTING:
		_pending_since_ms[peer] = Time.get_ticks_msec()


func _on_peer_disconnected(peer: int) -> void:
	_pending_since_ms.erase(peer)
	if state == State.HOSTING and _welcomed.erase(peer):
		peer_left.emit(peer)


func _on_connected_to_server() -> void:
	_hello.rpc_id(HOST_PEER, fingerprint())


func _on_connection_failed() -> void:
	_fail("Could not reach the host. Check the address, and that the host is on the players screen.")


func _on_server_disconnected() -> void:
	var was_connected := state == State.CONNECTED
	leave()
	if was_connected:
		host_lost.emit()
	else:
		refused.emit("The host closed the connection.")


func _refuse_peer(peer: int, reason: String) -> void:
	_refuse.rpc_id(peer, reason)
	# Let the refusal arrive before the line goes down.
	get_tree().create_timer(REFUSE_LINGER_S).timeout.connect(_kick.bind(peer))


func _kick(peer: int) -> void:
	if state == State.HOSTING:
		multiplayer.multiplayer_peer.disconnect_peer(peer)


func _fail(reason: String) -> void:
	leave()
	refused.emit(reason)


func _set_state(new_state: int) -> void:
	if state == new_state:
		return
	state = new_state
	state_changed.emit(state)
