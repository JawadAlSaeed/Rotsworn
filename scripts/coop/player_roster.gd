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

const KEYBOARD: int = -2
const ANY: int = -1
const MAX_PLAYERS: int = 3

## Player index -> device code. Player 0 (P1) leads in zones.
var devices: Array[int] = []
## Hero slot -> player index.
var owners: Array[int] = []


## One player owning every hero. `device` is the one that started it (any device still works).
static func solo(hero_count: int, device: int = KEYBOARD) -> PlayerRoster:
	var roster := PlayerRoster.new()
	roster.devices = [device]
	roster.owners.resize(maxi(0, hero_count))
	roster.owners.fill(0)
	return roster


## A copy (the lobby edits a copy, so Back leaves the old one alone).
func copy() -> PlayerRoster:
	var roster := PlayerRoster.new()
	roster.devices = devices.duplicate()
	roster.owners = owners.duplicate()
	return roster


func player_count() -> int:
	return devices.size()


func hero_count() -> int:
	return owners.size()


## True with two or more players: devices are told apart.
func is_coop() -> bool:
	return devices.size() > 1


## The player using this device: always 0 in solo; in co-op the player who joined with it, or -1.
func player_of_device(device: int) -> int:
	if not is_coop():
		return 0
	return devices.find(device)


## The device of player `player` (ANY if there is no such player).
func device_of_player(player: int) -> int:
	return devices[player] if player >= 0 and player < devices.size() else ANY


## The player who controls hero `slot` (0 for an unknown slot, so a bigger party still plays).
func owner_of(slot: int) -> int:
	return owners[slot] if slot >= 0 and slot < owners.size() else 0


## The hero slots player `player` controls, in slot order.
func heroes_of(player: int) -> Array[int]:
	var list: Array[int] = []
	for slot: int in owners.size():
		if owners[slot] == player:
			list.append(slot)
	return list


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


## Removes player `player` (never the last one). Later players move up; the heroes are split again.
func leave(player: int) -> bool:
	if player < 0 or player >= devices.size() or devices.size() <= 1:
		return false
	devices.remove_at(player)
	split_evenly()
	return true


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


## Problems with this roster (empty = fine): every player has a device of their own and a hero.
func validate() -> Array[String]:
	var problems: Array[String] = []
	if devices.is_empty() or devices.size() > MAX_PLAYERS:
		problems.append("1 to %d players needed (has %d)" % [MAX_PLAYERS, devices.size()])
	for i: int in devices.size():
		if devices.find(devices[i]) != i:
			problems.append("device %d is used by two players" % devices[i])
	for slot: int in owners.size():
		if owners[slot] < 0 or owners[slot] >= devices.size():
			problems.append("hero %d has no player" % slot)
	if owners.size() >= devices.size():
		for player: int in devices.size():
			if heroes_of(player).is_empty():
				problems.append("P%d has no hero" % (player + 1))
	return problems


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
