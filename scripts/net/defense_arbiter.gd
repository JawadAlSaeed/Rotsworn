class_name DefenseArbiter
extends RefCounted
## Host-only referee for online timed sequences (DESIGN.md 9.2). Pure: every time is passed in
## (host clock, microseconds).
##
## Each client plays an attack (or a skill) on its own clock and judges its own player's prompts,
## so network lag never moves a window. The host cannot judge those presses; it only makes sure
## the fight never waits forever:
## - a client says when it started playing the sequence (ack); its prompts get deadlines from then:
##   lead-in + the prompt's close time + a hit-stop allowance per hit so far + grace. With no ack,
##   the start counts as declare time + ack timeout (a later ack still moves it, while nothing of
##   that client's has been resolved yet);
## - a prompt past its deadline with no result is resolved as NONE (a hit taken, or a missed
##   press) by an explicit command, so the replay log has it;
## - results from a client are accepted only for prompts of that client's own heroes, for the
##   current sequence, and once per prompt (duplicates and stale sequences are dropped);
## - a client that leaves has all its open prompts resolved as NONE at once.
## The host's own players' prompts are not tracked here: the host's runner answers them.

var _ack_timeout_us: int = 0
var _grace_us: int = 0
var _hitstop_per_hit_us: int = 0
var _seq: int = -1
var _lead_in_us: int = 0
var _declared_us: int = 0
## Prompt idx -> {peer, close_us (sequence time), hit, resolved}
var _prompts: Dictionary = {}
## Peer -> host time its ack arrived.
var _acks: Dictionary = {}
## Peers whose prompts are already being resolved (a late ack no longer moves their start).
var _started_resolving: Dictionary = {}


## Numbers from Tuning: net_ack_timeout_ms, net_deadline_grace_ms, and the largest hit-stop a hit
## can cause (it pauses the client's clock, so it pushes its deadlines back).
func _init(ack_timeout_ms: int, grace_ms: int, hitstop_per_hit_ms: int) -> void:
	_ack_timeout_us = ack_timeout_ms * 1000
	_grace_us = grace_ms * 1000
	_hitstop_per_hit_us = hitstop_per_hit_ms * 1000


## A new sequence was declared at host time `now_us`. `owners` maps prompt idx -> the peer that
## answers it (only remote peers; prompts not in it are not tracked). `lead_in_ms` is the time
## between a client starting the sequence and its clock starting (an enemy attack's banner).
func declare(seq: int, prompts: Array, owners: Dictionary, lead_in_ms: int, now_us: int) -> void:
	_seq = seq
	_lead_in_us = lead_in_ms * 1000
	_declared_us = now_us
	_prompts.clear()
	_acks.clear()
	_started_resolving.clear()
	for p: Dictionary in prompts:
		var idx := int(p.idx)
		if not owners.has(idx):
			continue
		var latest := 0
		for action: Variant in (p.windows as Dictionary):
			latest = maxi(latest, int((p.windows[action] as Array)[1]))
		_prompts[idx] = {"peer": int(owners[idx]), "close_us": int(p.at_ms) * 1000 + latest, "hit": int(p.hit),
				"resolved": false}


## The sequence being refereed (-1 if none).
func seq() -> int:
	return _seq


## The sequence is over: nothing more to referee.
func clear() -> void:
	_seq = -1
	_prompts.clear()
	_acks.clear()
	_started_resolving.clear()


## Client `peer` started playing sequence `seq` (host time of arrival).
func ack(peer: int, seq: int, now_us: int) -> void:
	if seq == _seq and not _started_resolving.has(peer) and not _acks.has(peer):
		_acks[peer] = now_us


## Filters a client's results: only this sequence, only its own open prompts, each once. The
## accepted ones count as resolved. Returns them in prompt order.
func accept(peer: int, seq: int, results: Array) -> Array[Dictionary]:
	var accepted: Array[Dictionary] = []
	if seq != _seq:
		return accepted
	for r: Variant in results:
		if not r is Dictionary:
			continue
		var idx: Variant = (r as Dictionary).get("prompt")
		if typeof(idx) != TYPE_INT or not _prompts.has(idx):
			continue
		var p: Dictionary = _prompts[idx]
		if int(p.peer) != peer or bool(p.resolved):
			continue
		p.resolved = true
		accepted.append(r as Dictionary)
	accepted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.prompt) < int(b.prompt))
	return accepted


## Prompts the engine resolved or voided some other way: never send anything for them.
func mark_resolved(idxs: Array) -> void:
	for idx: Variant in idxs:
		if _prompts.has(idx):
			(_prompts[idx] as Dictionary).resolved = true


## Prompts past their deadline at host time `now_us`, resolved as NONE (prompt order). They count
## as resolved.
func overdue(now_us: int) -> Array[Dictionary]:
	var due: Array[Dictionary] = []
	if _seq < 0:
		return due
	var idxs: Array = _prompts.keys()
	idxs.sort()
	for idx: int in idxs:
		var p: Dictionary = _prompts[idx]
		if bool(p.resolved) or now_us < deadline_us(idx):
			continue
		p.resolved = true
		_started_resolving[int(p.peer)] = true
		due.append(CombatCommands.prompt_result(idx, Defense.Outcome.NONE, 0))
	return due


## Host time after which prompt `idx` is resolved as NONE (-1 if not tracked).
func deadline_us(idx: int) -> int:
	if not _prompts.has(idx):
		return -1
	var p: Dictionary = _prompts[idx]
	if bool(p.get("dropped", false)):
		return 0
	var peer := int(p.peer)
	var start := int(_acks[peer]) if _acks.has(peer) else _declared_us + _ack_timeout_us
	return start + _lead_in_us + int(p.close_us) + (int(p.hit) + 1) * _hitstop_per_hit_us + _grace_us


## Client `peer` left: its open prompts are due at once.
func drop_peer(peer: int) -> void:
	for idx: int in _prompts:
		var p: Dictionary = _prompts[idx]
		if int(p.peer) == peer:
			p.dropped = true


## True if any tracked prompt is still waiting for a result.
func has_open() -> bool:
	for idx: int in _prompts:
		if not bool((_prompts[idx] as Dictionary).resolved):
			return true
	return false
