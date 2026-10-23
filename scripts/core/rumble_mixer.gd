class_name RumbleMixer
extends RefCounted
## Plays buzz patterns on controllers (card #299). Pure, so it is tested without a pad: several
## patterns on one pad mix by taking the stronger of each motor at every moment, and a finished
## pattern drops out. PadRumble turns the levels into Input.start_joy_vibration calls.

## Device -> the patterns playing on it: [{steps: Array[Vector3i], from_ms: int, scale: float}].
var _playing: Dictionary = {}
## Devices that buzzed last time levels() was asked, so a pad that just went quiet is told once.
var _buzzing: Dictionary = {}


## Starts `steps` on `device` at `now_ms`, at `scale` of their strength (1: as written; above 1
## stronger, each motor still capped at full). Past `max_per_pad` patterns the oldest one stops.
func play(device: int, steps: Array[Vector3i], now_ms: int, scale: float = 1.0, max_per_pad: int = 6) -> void:
	if device < 0 or steps.is_empty() or scale <= 0.0:
		return
	var list: Array = _playing.get(device, [])
	list.append({"steps": steps, "from_ms": now_ms, "scale": scale})
	while list.size() > maxi(1, max_per_pad):
		list.pop_front()
	_playing[device] = list


## The motor levels now, per device: Vector3(weak 0..1, strong 0..1, seconds until the levels may
## change). A pad whose last pattern just ended is reported once at zero (stop it), then drops out.
func levels(now_ms: int) -> Dictionary:
	var out: Dictionary = {}
	for device: int in _playing.keys():
		var weak := 0.0
		var strong := 0.0
		var next_change_ms := 0
		var alive: Array = []
		for entry: Dictionary in _playing[device]:
			var at := step_at(entry.steps, now_ms - int(entry.from_ms))
			if at.x < 0:
				continue
			alive.append(entry)
			var step: Vector3i = (entry.steps as Array[Vector3i])[at.x]
			var scale := float(entry.scale)
			weak = maxf(weak, clampf(float(step.x) / 100.0 * scale, 0.0, 1.0))
			strong = maxf(strong, clampf(float(step.y) / 100.0 * scale, 0.0, 1.0))
			next_change_ms = at.y if next_change_ms == 0 else mini(next_change_ms, at.y)
		if alive.is_empty():
			_playing.erase(device)
		else:
			_playing[device] = alive
		if not alive.is_empty() or _buzzing.has(device):
			out[device] = Vector3(weak, strong, float(next_change_ms) / 1000.0)
	_buzzing.clear()
	for device: int in out:
		if not _playing.has(device):
			continue
		_buzzing[device] = true
	return out


## Every pad that is buzzing; the mixer forgets them all (the caller stops them).
func stop_all() -> Array[int]:
	var devices: Array[int] = []
	for device: int in _playing.keys():
		devices.append(device)
	for device: int in _buzzing.keys():
		if not devices.has(device):
			devices.append(device)
	_playing.clear()
	_buzzing.clear()
	return devices


func is_idle() -> bool:
	return _playing.is_empty() and _buzzing.is_empty()


## Which step of `steps` plays `elapsed_ms` after the start, and how long it has left:
## Vector2i(index, ms left), or Vector2i(-1, 0) before the start or after the end.
static func step_at(steps: Array[Vector3i], elapsed_ms: int) -> Vector2i:
	if elapsed_ms < 0:
		return Vector2i(-1, 0)
	var end := 0
	for i: int in steps.size():
		end += maxi(0, steps[i].z)
		if elapsed_ms < end:
			return Vector2i(i, end - elapsed_ms)
	return Vector2i(-1, 0)


## The pads that buzz for player `player` of `roster` on this machine: their own pad in local co-op;
## the pad in use when one person plays here (solo, or this machine's player online), if a pad was the
## last thing used; none for a keyboard player in local co-op or another machine's player online.
## `last_pad` is the joypad id that sent the last input (-1: none). No roster: the pad in use.
static func pads_of_player(roster: PlayerRoster, player: int, last_pad: int, pad_in_use: bool) -> Array[int]:
	var pads: Array[int] = []
	if roster != null and not roster.is_local(player):
		return pads
	var device := roster.device_of_player(player) if roster != null else PlayerRoster.ANY
	if device >= 0 and (roster.is_coop() and not roster.is_online()):
		pads.append(device)
	elif (roster == null or roster.local_players().size() <= 1) and pad_in_use and last_pad >= 0:
		pads.append(last_pad)
	return pads
