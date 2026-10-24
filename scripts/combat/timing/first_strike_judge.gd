class_name FirstStrikeJudge
extends RefCounted
## Judges the First Strike press (DESIGN.md 8.22, card #320): the one press ring on a Fight stop's
## name card. Pure, like DefenseJudge: every time is passed in, in microseconds since the ring
## appeared (the presenter stamps presses with DefenseInput, rule 3), and the result is a
## CombatSetup.Opening that goes into the fight's setup before the fight is built.
##
## The ring closes on its moment tuning.first_strike_ring_lead_ms after it appears and is judged
## with the windows a skill press has (Defense.build_windows of a PRESS hit: skill_press_window_ms
## and skill_perfect_window_ms, split by window_late_percent), the same lockout, lag compensation
## and reach-back. One prompt per player who may press, each in that player's own judge (JudgeSet):
## in local co-op any player's press counts, and one player's early press or lockout spends only
## their own try. Online only the host's players are given (the friends watch).
## - A GOOD or PERFECT press decides FIRST_STRIKE at once.
## - A press before the window is EARLY and spends that player's try (one press per ring, as a
##   skill ring); a press while locked out is ignored and restarts the lockout (mashing never pays).
## - Once every player's try is spent (early, or the window passed) it is NORMAL.
## - After a NORMAL start whose window passed unpressed, a press up to tuning.late_press_report_ms
##   after the moment (late_until_us) is still judged: a LATE whiff, as on a skill ring (DefenseJudge
##   reports it). It never changes the opening.

## Every press the judge is given came while the ring was on screen (the presenter arms the button
## when it appears), so each prompt's ring counts as shown this much before its moment: an early
## press always spends it, even when lag compensation moves it before the ring appeared.
const SHOWN_SLACK_US: int = 1000000

var _judges: JudgeSet
var _moment_us: int = 0
var _windows: Dictionary = {}
var _players: Array[int] = []
var _late_report_ms: int = 0
var _decided: bool = false
var _opening: CombatSetup.Opening = CombatSetup.Opening.NORMAL
var _outcome: int = Defense.Outcome.NONE
var _winner: int = -1


## `players`: the players who may press (player indexes of the roster). `latency_compensation_ms`:
## the base lag compensation (PlayerSettings.base_latency_compensation_ms); a press from a laggier
## device adds its own extra in press().
func _init(tuning: Tuning, players: Array[int], latency_compensation_ms: int) -> void:
	_moment_us = maxi(0, tuning.first_strike_ring_lead_ms) * 1000
	_windows = Defense.build_windows(AttackHitData.Kind.PRESS, tuning)
	_players = players.duplicate()
	_late_report_ms = maxi(0, tuning.late_press_report_ms)
	_judges = JudgeSet.new(tuning.whiff_lockout_ms, latency_compensation_ms, tuning.press_reach_back_max_ms,
			tuning.late_press_report_ms)
	var prompts: Array = []
	var owners: Dictionary = {}
	for i: int in _players.size():
		prompts.append({
			"idx": i,
			"hit": 0,
			"character": i,
			"at_ms": maxi(0, tuning.first_strike_ring_lead_ms),
			"windows": _windows,
			"ring_lead_us": _moment_us + SHOWN_SLACK_US,
		})
		owners[i] = _players[i]
	_judges.set_prompts(prompts, owners)
	_settle()


## The ring's moment: when it reaches its target (microseconds since it appeared).
func moment_us() -> int:
	return _moment_us


## The windows the ring is judged with: {Defense.Outcome.PRESS: [early_us, late_us],
## Defense.Outcome.PRESS_PERFECT: [...]}, relative to the moment (the ring draws its bands from them).
func windows() -> Dictionary:
	return _windows


## The players who may press.
func players() -> Array[int]:
	return _players.duplicate()


## True once the opening is known.
func is_decided() -> bool:
	return _decided


## FIRST_STRIKE after a GOOD or PERFECT press, else NORMAL (also before it is decided).
func opening() -> CombatSetup.Opening:
	return _opening


## The press that gave First Strike: Defense.Outcome.PRESS (GOOD) or PRESS_PERFECT; NONE otherwise.
func outcome() -> int:
	return _outcome


## The player whose press gave First Strike (-1: none).
func winner() -> int:
	return _winner


## The last ring time at which a press from a device with lag compensation `latency_ms` can still
## be reported LATE once the window passed unpressed: tuning.late_press_report_ms after the moment,
## as on a skill ring. The ring listens until then.
func late_until_us(latency_ms: int) -> int:
	return _moment_us + (_late_report_ms + maxi(0, latency_ms)) * 1000


## Judges a skill press by player `player` at ring time `t_us` (`earliest_us`: the previous input
## pump, or -1; `extra_latency_ms`: how much more the pressing device lags than the base). Returns a
## DefenseJudge report ({result, reason, outcome, offset_us, ...}); a player who may not press, or
## any press once First Strike is won, gets DONE. Once it is NORMAL a press is still judged (a late
## one is a LATE whiff, a spent try's DONE) but changes nothing.
func press(player: int, t_us: int, earliest_us: int = -1, extra_latency_ms: int = 0) -> Dictionary:
	if _decided and _opening == CombatSetup.Opening.FIRST_STRIKE:
		return {"result": DefenseJudge.Result.DONE, "reason": DefenseJudge.Reason.NONE, "prompts": [] as Array[int],
				"outcome": Defense.Outcome.NONE, "offset_us": 0, "hit": -1}
	var report := _judges.press(player, Defense.Outcome.PRESS, t_us, earliest_us, extra_latency_ms)
	if int(report.result) == DefenseJudge.Result.SUCCESS and not _decided:
		_decide(CombatSetup.Opening.FIRST_STRIKE, int(report.outcome), player)
	_settle()
	return report


## Call every frame with the ring's time: tries whose window passed are spent. Returns how many
## players' tries ran out with no press since the last call (each one a MISS).
func advance(t_us: int) -> int:
	if _decided:
		return 0
	_judges.advance(t_us)
	return _settle()


## Releases the judges' results; NORMAL once every try is spent without a GOOD or PERFECT press.
## Returns the tries released unpressed.
func _settle() -> int:
	var missed := 0
	for result: Dictionary in _judges.pop_ready():
		if not Defense.is_press(int(result.outcome)) and not bool(result.pressed):
			missed += 1
	if not _decided and _judges.is_complete():
		_decide(CombatSetup.Opening.NORMAL, Defense.Outcome.NONE, -1)
	return missed


func _decide(opening: CombatSetup.Opening, outcome: int, player: int) -> void:
	_decided = true
	_opening = opening
	_outcome = outcome
	_winner = player
