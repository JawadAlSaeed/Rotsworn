class_name PlayerRoster
extends RefCounted
## Who is playing and which heroes each player controls (DESIGN.md 9.1). Pure: no scene tree.
##
## Every player has one input device. A hero is a party slot (0, 1, 2), so a roster fits any fight
## with the same party size. With one player (solo) every device controls everything, exactly as
## before co-op. With two or three players a device controls only its own player's heroes: their
## turn menus, their defence and their skill presses.
##
## Device codes: a joypad's Godot device id (0 and up), KEYBOARD for any keyboard or mouse, ANY for
## presses made by code (the autoplay bot in solo).
##
## Online (DESIGN.md 9.2) every player is one machine (a network peer; the host is peer 1). Each
## machine has its own copy of the roster with `local_peer` set to itself: any device on that
## machine controls its own player, and only its own player.
##
## Mid-run (DESIGN.md 9.3, cards #304, #311) players join and leave without the heroes being dealt
## out again: a newcomer takes one hero from whoever holds the most, a leaver's heroes go to P1, and
## nobody else's heroes change. Before a run the players screen keeps join(), leave() and move_hero().

const KEYBOARD: int = -2
const ANY: int = -1
const MAX_PLAYERS: int = 3

## Player index -> device code. Player 0 is P1.
var devices: Array[int] = []
## Hero slot -> player index.
var owners: Array[int] = []
## Online: player index -> network peer id (empty in a local game).
var peers: Array[int] = []
## Online: the peer id of this machine.
var local_peer: int = 0
## Online, mid-run: players whose machine lost the connection (DESIGN.md 9.2). They keep their seat
## (and their heroes in `owners`) for the rejoin grace time; meanwhile the host (P1) plays those
## heroes (owner_of() says so).
var away: Array[int] = []
## Online, mid-run: players who just got in (dropped in, or took an away seat, card #304) and are
## still catching up. Always also in `away` (the host plays their heroes until set_back()), but no
## seat time runs for them and the chip says "joining".
var joining: Array[int] = []


## One player owning every hero. `device` is the one that started it (any device still works).
static func solo(hero_count: int, device: int = KEYBOARD) -> PlayerRoster:
	var roster := PlayerRoster.new()
	roster.devices = [device]
	roster.owners.resize(maxi(0, hero_count))
	roster.owners.fill(0)
	return roster


## An online roster with the host (peer `host_peer`) alone. `local_peer` is this machine.
static func online(hero_count: int, host_peer: int, p_local_peer: int) -> PlayerRoster:
	var roster := PlayerRoster.solo(hero_count, ANY)
	roster.peers = [host_peer]
	roster.local_peer = p_local_peer
	return roster


## A copy (the lobby edits a copy, so Back leaves the old one alone).
func copy() -> PlayerRoster:
	var roster := PlayerRoster.new()
	roster.devices = devices.duplicate()
	roster.owners = owners.duplicate()
	roster.peers = peers.duplicate()
	roster.local_peer = local_peer
	roster.away = away.duplicate()
	roster.joining = joining.duplicate()
	return roster


## Same devices, heroes, peers, away and joining as `other` (a Players overlay closed with no
## change applies nothing). local_peer is not compared (it is per machine).
func same_as(other: PlayerRoster) -> bool:
	return other != null and devices == other.devices and owners == other.owners \
			and peers == other.peers and away == other.away and joining == other.joining


## The roster as plain data, to send over the network (local_peer is not sent: it is per machine).
func to_dict() -> Dictionary:
	return {"devices": Array(devices), "owners": Array(owners), "peers": Array(peers), "away": Array(away),
			"joining": Array(joining)}


## A roster from to_dict() data, seen from machine `p_local_peer`. Null if the data is malformed.
static func from_dict(d: Dictionary, p_local_peer: int) -> PlayerRoster:
	var roster := PlayerRoster.new()
	for key: String in ["devices", "owners", "peers"]:
		if not d.get(key) is Array:
			return null
		for v: Variant in d[key]:
			if typeof(v) != TYPE_INT:
				return null
	roster.devices.assign(d.devices)
	roster.owners.assign(d.owners)
	roster.peers.assign(d.peers)
	# "away" came with rejoining (card #205), "joining" with drop-in (#304); an older message without
	# them has nobody away or joining.
	for key: String in ["away", "joining"]:
		if d.get(key) is Array:
			for v: Variant in d[key]:
				if typeof(v) != TYPE_INT:
					return null
	if d.get("away") is Array:
		roster.away.assign(d.away)
	if d.get("joining") is Array:
		roster.joining.assign(d.joining)
	roster.local_peer = p_local_peer
	if not roster.validate().is_empty():
		return null
	return roster


## True in an online game.
func is_online() -> bool:
	return not peers.is_empty()


## The player of network peer `peer` (-1 if none).
func player_of_peer(peer: int) -> int:
	return peers.find(peer)


## The players on this machine: all of them in a local game, this machine's one online.
func local_players() -> Array[int]:
	var list: Array[int] = []
	if not is_online():
		for i: int in devices.size():
			list.append(i)
	elif peers.has(local_peer):
		list.append(peers.find(local_peer))
	return list


func is_local(player: int) -> bool:
	return local_players().has(player)


func player_count() -> int:
	return devices.size()


func hero_count() -> int:
	return owners.size()


## True with two or more players: devices are told apart.
func is_coop() -> bool:
	return devices.size() > 1


## The player using this device: always 0 in solo; in local co-op the player who joined with it,
## or -1; online this machine's player, whatever the device.
func player_of_device(device: int) -> int:
	if not is_coop():
		return 0
	if is_online():
		return peers.find(local_peer)
	return devices.find(device)


## The device of player `player` (ANY if there is no such player).
func device_of_player(player: int) -> int:
	return devices[player] if player >= 0 and player < devices.size() else ANY


## Local players whose pad is no longer in `connected` (the Godot joypad ids that are plugged in),
## as player indexes. The keyboard and code-driven devices never go missing. Empty online.
func missing_players(connected: Array[int]) -> Array[int]:
	var list: Array[int] = []
	if is_online():
		return list
	for player: int in devices.size():
		if devices[player] >= 0 and not connected.has(devices[player]):
			list.append(player)
	return list


## Player `player` carries on with another device (their pad came back under a new id, or they
## took another pad or the keyboard). Refused if the device is already someone's or the player is
## unknown.
func replace_device(player: int, new_device: int) -> bool:
	if is_online() or player < 0 or player >= devices.size() or devices.has(new_device):
		return false
	if new_device == ANY:
		return false
	devices[player] = new_device
	return true


## Before a run starts: players whose pad is gone leave (their heroes are dealt out again); if P1's
## pad is gone and the keyboard is free, P1 plays on the keyboard. Returns how many were changed.
func drop_missing(connected: Array[int]) -> int:
	var changed := 0
	# Leave from the back so the indexes stay valid.
	var gone := missing_players(connected)
	gone.reverse()
	for player: int in gone:
		if devices.size() > 1:
			leave(player)
			changed += 1
		elif not devices.has(KEYBOARD):
			devices[player] = KEYBOARD
			changed += 1
	return changed


## The player who controls hero `slot` now (0 for an unknown slot, so a bigger party still plays).
## A hero whose player is away is played by the host (P1) until they are back.
func owner_of(slot: int) -> int:
	var player := seat_of(slot)
	return 0 if away.has(player) else player


## The player whose seat hero `slot` belongs to, away or not (0 for an unknown slot).
func seat_of(slot: int) -> int:
	return owners[slot] if slot >= 0 and slot < owners.size() else 0


## The hero slots player `player` controls now, in slot order (none while they are away).
func heroes_of(player: int) -> Array[int]:
	var list: Array[int] = []
	for slot: int in owners.size():
		if owner_of(slot) == player:
			list.append(slot)
	return list


## How many heroes sit in player `player`'s seat (away or not).
func seats_held(player: int) -> int:
	return owners.count(player)


## The hero a player who joins mid-run as player `player` takes (#304): from the player holding
## the most heroes (ties: the lower player, so P1 first) the usual deal's hero for that seat (slot
## `player`: P2 Brin, P3 Cass) if they hold it, else their last one (highest slot). -1 when nobody
## holds two. An away (or joining) player never gives: their seat and heroes stay theirs until they
## are back (or the seat goes), even when only they hold two.
func donor_hero(player: int) -> int:
	var most := 1
	var donor := -1
	for p: int in devices.size():
		if away.has(p):
			continue
		var held := seats_held(p)
		if held > most:
			most = held
			donor = p
	if donor < 0:
		return -1
	if player >= 0 and player < owners.size() and owners[player] == donor:
		return player
	for slot: int in range(owners.size() - 1, -1, -1):
		if owners[slot] == donor:
			return slot
	return -1


## True when one more player could join mid-run (#304): a seat is free and someone who is not away
## holds two heroes (the host asks this before it welcomes a newcomer).
func can_join_midrun() -> bool:
	return devices.size() < MAX_PLAYERS and donor_hero(devices.size()) >= 0


## Online, mid-run: peer `peer` lost the connection. Their seat and heroes stay theirs; the host
## plays the heroes meanwhile. False for the host, an unknown peer, or one already away.
func set_away(peer: int) -> bool:
	var player := peers.find(peer)
	if player <= 0 or away.has(player):
		return false
	away.append(player)
	away.sort()
	return true


func is_away(player: int) -> bool:
	return away.has(player)


## Online: peer `peer`'s player is catching up (a takeover of an away seat, #304): away and
## joining. False for the host or an unknown peer. Idempotent.
func set_joining(peer: int) -> bool:
	var player := peers.find(peer)
	if player <= 0:
		return false
	if not away.has(player):
		away.append(player)
		away.sort()
	if not joining.has(player):
		joining.append(player)
		joining.sort()
	return true


func is_joining(player: int) -> bool:
	return joining.has(player)


## Online: the player who had peer `old_peer` came back as `new_peer` (a new connection has a new
## id). They stay away (the host still plays their heroes) until set_back(). Returns the player, or
## -1 if `old_peer` has no seat (or is the host) or `new_peer` already has one.
func rebind_peer(old_peer: int, new_peer: int) -> int:
	var player := peers.find(old_peer)
	if player <= 0 or new_peer <= 0 or peers.has(new_peer):
		return -1
	peers[player] = new_peer
	return player


## Online: peer `peer`'s player plays their own heroes again (and is no longer joining). False if
## they were not away.
func set_back(peer: int) -> bool:
	var player := peers.find(peer)
	if player < 0 or not away.has(player):
		return false
	away.erase(player)
	joining.erase(player)
	return true


## True if this device may act for hero `slot` (its menu, presses).
func may_control(device: int, slot: int) -> bool:
	return not is_coop() or player_of_device(device) == owner_of(slot)


## A new player with this device. Returns the player index, or -1 if the device is already in or
## the roster is full. The heroes are split again (split_evenly).
func join(device: int) -> int:
	if devices.has(device) or devices.size() >= MAX_PLAYERS:
		return -1
	devices.append(device)
	split_evenly()
	return devices.size() - 1


## Online: a new player for network peer `peer` (see join()).
func join_peer(peer: int) -> int:
	if peers.has(peer) or devices.size() >= MAX_PLAYERS:
		return -1
	devices.append(ANY)
	peers.append(peer)
	split_evenly()
	return devices.size() - 1


## Local, mid-run (#304): a new player with `device` takes donor_hero() and nobody else's heroes
## change. Returns the new player, or -1 (online, ANY, device already in, roster full, no spare hero).
func join_midrun(device: int) -> int:
	if is_online() or device == ANY or devices.has(device) or not can_join_midrun():
		return -1
	var player := devices.size()
	var slot := donor_hero(player)
	devices.append(device)
	owners[slot] = player
	return player


## Online, mid-run (#304): the same for network peer `peer` (device ANY). The new player is away
## and joining: the host plays the hero until the hand-over (set_back). -1 like join_peer, or
## when no hero is spare (or the roster is not online).
func join_peer_midrun(peer: int) -> int:
	if not is_online() or peers.has(peer) or not can_join_midrun():
		return -1
	var player := devices.size()
	var slot := donor_hero(player)
	devices.append(ANY)
	peers.append(peer)
	owners[slot] = player
	away.append(player)
	away.sort()
	joining.append(player)
	joining.sort()
	return player


## Removes player `player` (never the last one). Later players move up; the heroes are split again.
func leave(player: int) -> bool:
	if player < 0 or player >= devices.size() or devices.size() <= 1:
		return false
	devices.remove_at(player)
	if player < peers.size():
		peers.remove_at(player)
	split_evenly()
	return true


## Local, mid-run (#311): player `player` leaves; _remove_player rules (their heroes to P1, later
## players move up, nobody else changes). False online, for a bad index or the last player.
## Player 0 may leave too (a lost P1 pad's Give heroes): the old P2 becomes P1 with those heroes.
func leave_midrun(player: int) -> bool:
	if is_online() or player < 0 or player >= devices.size() or devices.size() <= 1:
		return false
	_remove_player(player)
	return true


## Online, mid-run: peer `peer` dropped out. Their heroes go to player 1 (the host) and later
## players move up; the other heroes keep their players. False if the peer is not in the game.
func drop_peer(peer: int) -> bool:
	var player := peers.find(peer)
	if player <= 0:
		return false
	_remove_player(player)
	return true


## Removes player `player`: their heroes go to player 0 (after the removal, so the old P2 when P1
## goes), later players move up, everyone else keeps their heroes; `away` and `joining` follow.
func _remove_player(player: int) -> void:
	devices.remove_at(player)
	if player < peers.size():
		peers.remove_at(player)
	for slot: int in owners.size():
		if owners[slot] == player:
			owners[slot] = 0
		elif owners[slot] > player:
			owners[slot] -= 1
	away = _without_player(away, player)
	joining = _without_player(joining, player)


## `list` (player indexes) once player `player` is gone: it drops out, later players move up.
static func _without_player(list: Array[int], player: int) -> Array[int]:
	var kept: Array[int] = []
	for p: int in list:
		if p != player:
			kept.append(p - 1 if p > player else p)
	return kept


## Deals the heroes out in turn (hero 0 to P1, hero 1 to P2, ...), so P1 gets any extra.
func split_evenly() -> void:
	var players := maxi(1, devices.size())
	for slot: int in owners.size():
		owners[slot] = slot % players


## Hands hero `slot` to the next player (`step` +1) or the previous one (-1). Refused when that
## would leave its player with no hero, or in solo.
func move_hero(slot: int, step: int) -> bool:
	if not is_coop() or slot < 0 or slot >= owners.size() or step == 0:
		return false
	var from := owners[slot]
	if heroes_of(from).size() <= 1:
		return false
	owners[slot] = wrapi(from + signi(step), 0, devices.size())
	return true


## Hands hero `slot` on like move_hero(); when its player has no other hero, the two players trade
## instead (the target player's lowest-slot hero comes back), so everyone keeps one (#311). False
## in solo or for a bad slot or step. Only the in-run overlay uses it (the pre-run screen keeps
## move_hero).
func trade_hero(slot: int, step: int) -> bool:
	if move_hero(slot, step):
		return true
	if not is_coop() or slot < 0 or slot >= owners.size() or step == 0:
		return false
	var from := owners[slot]
	var to := wrapi(from + signi(step), 0, devices.size())
	for other: int in owners.size():
		if owners[other] == to:
			owners[other] = from
			owners[slot] = to
			return true
	return false


## Problems with this roster (empty = fine): every player has a device of their own and a hero.
func validate() -> Array[String]:
	var problems: Array[String] = []
	if devices.is_empty() or devices.size() > MAX_PLAYERS:
		problems.append("1 to %d players needed (has %d)" % [MAX_PLAYERS, devices.size()])
	if is_online():
		if peers.size() != devices.size():
			problems.append("every online player needs a peer")
		for i: int in peers.size():
			if peers.find(peers[i]) != i:
				problems.append("peer %d is two players" % peers[i])
	else:
		for i: int in devices.size():
			if devices.find(devices[i]) != i:
				problems.append("device %d is used by two players" % devices[i])
	for slot: int in owners.size():
		if owners[slot] < 0 or owners[slot] >= devices.size():
			problems.append("hero %d has no player" % slot)
	for player: int in away:
		if player <= 0 or player >= devices.size() or not is_online():
			problems.append("only an online client can be away (P%d)" % (player + 1))
	for player: int in joining:
		if not away.has(player):
			problems.append("P%d is joining but not away" % (player + 1))
	if owners.size() >= devices.size():
		for player: int in devices.size():
			var seats := 0
			for slot: int in owners.size():
				if owners[slot] == player:
					seats += 1
			if seats == 0:
				problems.append("P%d has no hero" % (player + 1))
	return problems


## "0,1,0" (hero slot -> player) for logs and AUTOPLAY lines.
func owners_text() -> String:
	var parts := PackedStringArray()
	for player: int in owners:
		parts.append(str(player))
	return ",".join(parts)


## The device code of an input event: a joypad's id, KEYBOARD for keys and the mouse, ANY else.
static func device_of(event: InputEvent) -> int:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return event.device
	if event is InputEventKey or event is InputEventMouse:
		return KEYBOARD
	return ANY


## "Keyboard", "Pad 1", ... for the lobby and hints.
static func device_name(device: int) -> String:
	if device == KEYBOARD:
		return "Keyboard"
	if device == ANY:
		return "Bot"
	return "Pad %d" % (device + 1)


## The lowest joypad id `roster` does not use (the bot's next pretend pad, --pad-join-after).
static func free_pad(roster: PlayerRoster) -> int:
	var pad := 0
	while roster.devices.has(pad):
		pad += 1
	return pad


## P1's real device while solo (#304): `device` when it pressed while the game itself was being
## played and the press was neither a pause nor a Back (both open the pause menu, maybe on a
## friend's pad); else `current`. ANY never counts, nor any press in co-op (`coop`: it may be a
## friend's, and the roster already knows P1's device). Pure.
static func play_device_after(current: int, device: int, is_pause_or_back: bool, in_play: bool,
		coop: bool = false) -> int:
	if device == ANY or is_pause_or_back or not in_play or coop:
		return current
	return device


## The device P1 gets when the in-run Players overlay opens solo (#304): the first of
## `play_device` (P1's real device, see play_device_after), `roster_p1` (the roster's own) and
## `last_device` (the one that pressed last, on the pause menu) that is the keyboard or a pad in
## `connected`; else the keyboard (always there). A pad that died never becomes P1's, so the device
## P1 holds now is never left out as one that has not joined (its Confirm would join them as P2).
static func overlay_p1_device(play_device: int, roster_p1: int, last_device: int, connected: Array[int]) -> int:
	for device: int in [play_device, roster_p1, last_device]:
		if device == KEYBOARD or (device >= 0 and connected.has(device)):
			return device
	return KEYBOARD
