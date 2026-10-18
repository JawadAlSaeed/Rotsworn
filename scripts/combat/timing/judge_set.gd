class_name JudgeSet
extends RefCounted
## One DefenseJudge per player for one timed sequence (DESIGN.md 9.1). Pure, like DefenseJudge.
##
## Each player's judge gets only the prompts of the heroes that player controls, so a press
## answers only that player's heroes, and a whiff locks out only that player. A player with no
## prompt in this sequence has no judge: their presses are ignored (DONE, no lockout).
## Results are released per player in prompt order, which keeps every hero's prompts in hit order
## (all of a hero's prompts are in one judge), the order the engine requires.

var _lockout_ms: int = 0
var _latency_ms: int = 0
var _reach_back_ms: int = 0
var _late_report_ms: int = 0
## Player index -> DefenseJudge (only players with prompts).
var _judges: Dictionary = {}
## Prompt idx -> player index.
var _player_of_prompt: Dictionary = {}


## The same numbers as DefenseJudge._init. `latency_compensation_ms` is the base every judge works
## from; a press from a laggier device adds its own extra in `press` (card #204).
func _init(whiff_lockout_ms: int, latency_compensation_ms: int, reach_back_max_ms: int, late_press_report_ms: int) -> void:
	_lockout_ms = whiff_lockout_ms
	_latency_ms = latency_compensation_ms
	_reach_back_ms = reach_back_max_ms
	_late_report_ms = late_press_report_ms


## Loads a sequence's prompts. `owners` maps a character id to its player; characters not in it
## belong to player 0 (solo passes {}). Online, `only_players` lists this machine's players: the
## other players' prompts are judged on their own machines and left out here (empty = all).
func set_prompts(prompts: Array, owners: Dictionary, only_players: Array[int] = []) -> void:
	_judges.clear()
	_player_of_prompt.clear()
	var by_player: Dictionary = {}
	for p: Dictionary in prompts:
		var player := int(owners.get(int(p.character), 0))
		if not only_players.is_empty() and not only_players.has(player):
			continue
		_player_of_prompt[int(p.idx)] = player
		if not by_player.has(player):
			by_player[player] = []
		(by_player[player] as Array).append(p)
	for player: int in by_player:
		var judge := DefenseJudge.new(_lockout_ms, _latency_ms, _reach_back_ms, _late_report_ms)
		judge.set_prompts(by_player[player] as Array)
		_judges[player] = judge


## The players with prompts in this sequence, in order.
func players() -> Array[int]:
	var list: Array[int] = []
	list.assign(_judges.keys())
	list.sort()
	return list


## The player who answers prompt `idx` here (-1 if unknown, or judged on another machine).
func player_of_prompt(idx: int) -> int:
	return int(_player_of_prompt.get(idx, -1))


## Judges a press by player `player` (see DefenseJudge.press). A player with no prompt here gets
## a DONE report and no lockout. `extra_latency_ms` is how much more the pressing device lags than
## the base given to _init (a pad against a keyboard, card #204): the press is judged that much
## earlier, exactly as if the judge had been built with that device's own compensation. Never
## negative: the base is the smallest compensation, so no window is cut short.
func press(player: int, action: int, t_us: int, earliest_us: int = -1, extra_latency_ms: int = 0) -> Dictionary:
	var judge := _judges.get(player) as DefenseJudge
	if judge == null:
		return {"result": DefenseJudge.Result.DONE, "reason": DefenseJudge.Reason.NONE, "prompts": [] as Array[int],
				"outcome": Defense.Outcome.NONE, "offset_us": 0, "hit": -1}
	var shift_us := maxi(0, extra_latency_ms) * 1000
	return judge.press(action, t_us - shift_us, maxi(0, earliest_us - shift_us) if earliest_us >= 0 else earliest_us)


## Every judge's overdue prompts (see DefenseJudge.advance), in idx order.
func advance(t_us: int) -> Array[int]:
	var expired: Array[int] = []
	for player: int in _judges:
		expired.append_array((_judges[player] as DefenseJudge).advance(t_us))
	expired.sort()
	return expired


func void_prompts(idxs: Array) -> void:
	for player: int in _judges:
		(_judges[player] as DefenseJudge).void_prompts(idxs)


func resolve_all_remaining() -> void:
	for player: int in _judges:
		(_judges[player] as DefenseJudge).resolve_all_remaining()


## Every judge's released results (see DefenseJudge.pop_ready), player by player.
func pop_ready() -> Array[Dictionary]:
	var ready: Array[Dictionary] = []
	for player: int in players():
		ready.append_array((_judges[player] as DefenseJudge).pop_ready())
	return ready


## True once every judge is complete.
func is_complete() -> bool:
	for player: int in _judges:
		if not (_judges[player] as DefenseJudge).is_complete():
			return false
	return true


## True if player `player` is locked out by a whiff at this time.
func is_locked_out(player: int, t_us: int) -> bool:
	var judge := _judges.get(player) as DefenseJudge
	return judge != null and judge.is_locked_out(t_us)
