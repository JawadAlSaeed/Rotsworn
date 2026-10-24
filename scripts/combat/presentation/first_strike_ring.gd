class_name FirstStrikeRing
extends VBoxContainer
## The First Strike press (DESIGN.md 8.22, card #320) on a Fight stop's name card: one press ring
## drawn like a skill press ring (RingLayer: the faint target, the GOOD band and the gold PERFECT
## band, the ring closing onto the target at the perfect moment and turning gold inside the PERFECT
## band), the skill press button with "First Strike" under it and the press's word over it
## (PERFECT, GOOD, EARLY, LATE, MISS), with the skill press sounds and the presser's buzz. Main puts
## it on the card (ScreenTransition.show_tip), holds the card until is_finished() and builds the
## fight with opening(). Real time, from the moment it is added: the ring shows
## tuning.first_strike_ring_delay_ms later. The look is combat_visuals.tres (Skills and First Strike
## press groups).
## - PRESS: this machine decides (a local game, any player's press; online, the host's). Presses
##   are stamped by its own DefenseInput the moment they arrive (rule 3) and judged on the ring's
##   clock by a pure FirstStrikeJudge; the autoplay bots press through the same path
##   (FirstStrikeBot). A window that passes unpressed says MISS at once, as a skill ring does, and
##   the button stays armed until FirstStrikeJudge.late_until_us: a press by then turns it into
##   LATE (the opening stays NORMAL). decided() fires once, when the press's word is final.
## - WATCH: an online friend's: the ring dimmed and no button to press (it takes no press). The result
##   is the host's (show_host_result); a normal start if none came within tuning.net_opening_wait_ms
##   after the ring closed (the host's fight decides the opening either way).
## - LOOP: the --screen=first_strike picture: pressable, starts over after each result, never done.

## The press's result is final (PRESS and LOOP): the opening, and `word` its readout (WORD_*), sent
## to friends. At once after a GOOD, PERFECT or EARLY press that decides it; after a window that
## passed unpressed, once a LATE press came or the time for one is over.
signal decided(opening: CombatSetup.Opening, word: String)

enum Mode { PRESS, WATCH, LOOP }

const WORD_PERFECT := "PERFECT"
const WORD_GOOD := "GOOD"
const WORD_EARLY := "EARLY"
const WORD_LATE := "LATE"
const WORD_MISS := "MISS"
## The chip's word, and the tag a friend sees instead of the button (the host is P1).
const CHIP_TEXT := "First Strike"
const HOST_TAG := "P1"
## A good (not perfect) press sounds quieter than a perfect one (as SkillSequenceRunner's).
const GOOD_PRESS_VOLUME_DB: float = -6.0
## The ring keeps shrinking past the target after the perfect moment, down to this radius.
const RING_MIN_RADIUS_PX: float = 4.0
## Room around the ring for its outline (share of the ring width).
const RING_MARGIN_SHARE: float = 2.0
## The target circle's fill once First Strike is won (alpha of the gold).
const WON_TARGET_ALPHA: float = 0.35

var _tuning: Tuning
var _visuals: CombatVisuals
var _options: CombatOptions
var _roster: PlayerRoster
var _mode: Mode = Mode.PRESS
var _bot_seed: int = -1

var _input: DefenseInput
var _judge: FirstStrikeJudge
var _clock := AttackClock.new()
var _rng := RandomNumberGenerator.new()
var _latency_ms: int = 0
## The laggiest device's lag compensation here: a late press is listened for until its LATE span ends.
var _late_latency_ms: int = 0
## Real time (Time.get_ticks_usec()) the ring shows; whether it has.
var _shows_at_us: int = 0
var _started: bool = false
## The ring's moment and windows (the judge's; WATCH builds them the same way for drawing).
var _moment_us: int = 0
var _windows: Dictionary = {}
var _opening: CombatSetup.Opening = CombatSetup.Opening.NORMAL
var _word: String = ""
## Real time the result showed (0: not yet); whether its word is final (no press can change it any
## more, decided() was sent); and whether the card may go.
var _result_at_us: int = 0
var _final: bool = false
var _finished: bool = false
## Ring time until which a late press can still say LATE, after a window that passed unpressed
## (-1: no such span, the result is final when it shows).
var _late_until_us: int = -1
## WATCH: the host's result once it came ({opening, word}).
var _host_result: Dictionary = {}
## The bots: each local player's planned press (player -> ring time, us; pressed ones removed), and
## the masher's next press (ring time, us).
var _bot_presses: Dictionary = {}
var _next_mash_us: int = 0

var _word_label: Label
var _ring_box: Control
var _rings: RingLayer
var _chip_holder: CenterContainer


## Call before adding it to the tree. `roster`: who plays (PRESS: its local players may press).
## `bot_seed`: the autoplay bots' luck (-1: random; --seed makes it repeat).
func setup(tuning: Tuning, visuals: CombatVisuals, options: CombatOptions, roster: PlayerRoster, mode: Mode,
		bot_seed: int = -1) -> void:
	_tuning = tuning
	_visuals = visuals
	_options = options
	_roster = roster
	_mode = mode
	_bot_seed = bot_seed


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 6)
	_word_label = HudStyle.make_label("", _visuals.first_strike_word_size, HudStyle.TEXT)
	_word_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# The word's line keeps its height while empty, so the ring never moves when it shows.
	_word_label.custom_minimum_size.y = float(_visuals.first_strike_word_size) * 1.4
	add_child(_word_label)
	_ring_box = Control.new()
	_ring_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var side := 2.0 * (_visuals.press_ring_start_radius_px * _visuals.first_strike_ring_scale
			+ _visuals.ring_width_px * RING_MARGIN_SHARE)
	_ring_box.custom_minimum_size = Vector2(side, side)
	_ring_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(_ring_box)
	_rings = RingLayer.new()
	_rings.name = "Rings"
	_ring_box.add_child(_rings)
	_chip_holder = CenterContainer.new()
	_chip_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_chip_holder)
	if _mode == Mode.WATCH:
		_ring_box.modulate.a = _visuals.first_strike_watch_alpha
		_chip_holder.modulate.a = _visuals.first_strike_watch_alpha
	else:
		_input = DefenseInput.new()
		_input.name = "Input"
		add_child(_input)
		_input.pressed.connect(_on_pressed)
	_latency_ms = PlayerSettings.base_latency_compensation_ms(_tuning)
	_late_latency_ms = maxi(PlayerSettings.latency_compensation_ms(_tuning, PlayerSettings.INPUT_KEYBOARD),
			PlayerSettings.latency_compensation_ms(_tuning, PlayerSettings.INPUT_PAD))
	if _bot_seed >= 0:
		_rng.seed = _bot_seed
	else:
		_rng.randomize()
	_begin(Time.get_ticks_usec())


## True once the card may go: the result is final and has been shown its while (never in LOOP).
func is_finished() -> bool:
	return _finished


## FIRST_STRIKE after a GOOD or PERFECT press (WATCH: the host's), else NORMAL.
func opening() -> CombatSetup.Opening:
	return _opening


## The press's readout (WORD_*; "" before the result).
func word() -> String:
	return _word


func mode() -> Mode:
	return _mode


## WATCH: the host's result arrived (`opening` a CombatEngine.OPENING_NAMES name, `word` its
## readout). It shows at once, even while the ring here is still closing (the host's came first).
func show_host_result(opening_name: String, press_word: String) -> void:
	if _mode != Mode.WATCH or not _host_result.is_empty():
		return
	_host_result = {"opening": opening_name, "word": press_word}


## Starts (again) at real time `now_us`: the ring shows after the delay.
func _begin(now_us: int) -> void:
	_started = false
	_result_at_us = 0
	_final = false
	_late_until_us = -1
	_opening = CombatSetup.Opening.NORMAL
	_word = ""
	_word_label.text = ""
	_shows_at_us = now_us + maxi(0, _tuning.first_strike_ring_delay_ms) * 1000
	_set_chip(HudStyle.TEXT)
	_rings.set_rings([] as Array[Dictionary], _visuals.ring_width_px)


func _start(now_us: int) -> void:
	_started = true
	_clock.start(now_us)
	var players: Array[int] = []
	if _mode != Mode.WATCH:
		players = _roster.local_players()
	_judge = FirstStrikeJudge.new(_tuning, players, _latency_ms)
	_moment_us = _judge.moment_us()
	_windows = _judge.windows()
	if _input != null:
		_input.arm_press()
	_plan_bots(players)


func _process(_delta: float) -> void:
	if _finished:
		return
	var now := Time.get_ticks_usec()
	if not _started:
		# A friend whose host already decided shows it at once, ring or not.
		if now < _shows_at_us and (_mode != Mode.WATCH or _host_result.is_empty()):
			return
		_start(now)
	var t := _clock.attack_time_us(now)
	if _mode == Mode.WATCH:
		if _result_at_us == 0:
			_watch(t, now)
	elif not _final:
		_press_bots(t)
		if _result_at_us == 0:
			if _judge.advance(t) > 0:
				# MISS at once, as on a skill ring; a press in the next moment still says LATE.
				_say(WORD_MISS, HudStyle.MISS)
				Sfx.play("skill_miss")
				_late_until_us = _judge.late_until_us(_late_latency_ms)
			if _judge.is_decided():
				_on_decided(now)
		if _result_at_us > 0 and not _final and t > _late_until_us:
			_finalize()
	_draw_ring(t)
	if _final and now - _result_at_us >= maxi(0, _visuals.first_strike_result_ms) * 1000:
		if _mode == Mode.LOOP:
			_begin(now)
		else:
			_finished = true


# --- presses ----------------------------------------------------------------------------------

func _on_pressed(action: int, stamp_us: int, previous_pump_us: int, device: int) -> void:
	if action != Defense.Outcome.PRESS or not _started or _judge == null or _final:
		return
	var player := _roster.player_of_device(device)
	var t := _clock.attack_time_us(stamp_us)
	var earliest := -1
	if previous_pump_us > 0 and previous_pump_us < stamp_us:
		var e := _clock.attack_time_us(previous_pump_us)
		if e >= 0:
			earliest = e
	var extra := PlayerSettings.latency_compensation_ms(_tuning, PlayerSettings.input_kind_of_device(device)) - _latency_ms
	var report := _judge.press(player, t, earliest, extra)
	match int(report.result):
		DefenseJudge.Result.SUCCESS:
			var perfect := int(report.outcome) == Defense.Outcome.PRESS_PERFECT
			_say(WORD_PERFECT if perfect else WORD_GOOD, HudStyle.GOLD if perfect else HudStyle.TEXT)
			Sfx.play("skill_press", 0.0 if perfect else GOOD_PRESS_VOLUME_DB)
			# Only the presser's pad, as a skill press (no fight party is set on the card).
			PadRumble.for_player("press_perfect" if perfect else "press_good", _roster, player)
		DefenseJudge.Result.WHIFF:
			var early := int(report.reason) == DefenseJudge.Reason.EARLY
			_say(WORD_EARLY if early else WORD_LATE, HudStyle.EARLY if early else HudStyle.LATE)
			Sfx.play("whiff")
		DefenseJudge.Result.LOCKED:
			Sfx.play("locked", _visuals.locked_click_volume_db)
	if _result_at_us == 0:
		if _judge.is_decided():
			_on_decided(Time.get_ticks_usec())
	elif int(report.result) == DefenseJudge.Result.WHIFF:
		# A late press after the MISS: LATE is the press's word.
		_finalize()


func _on_decided(now_us: int) -> void:
	if _result_at_us > 0:
		return
	_opening = _judge.opening()
	if _word.is_empty():
		_say(WORD_MISS, HudStyle.MISS)
	_show_result(now_us)
	if _late_until_us < 0:
		_finalize()


## The result is on the card: the chip lights gold for First Strike (or dims), and the card holds it
## first_strike_result_ms (once its word is final).
func _show_result(now_us: int) -> void:
	_result_at_us = maxi(1, now_us)
	_set_chip(HudStyle.GOLD if _opening == CombatSetup.Opening.FIRST_STRIKE else HudStyle.TEXT_DIM)


## The word is final: the button goes back to the menus and the result is told (PRESS and LOOP).
func _finalize() -> void:
	_final = true
	if _input != null:
		_input.disarm()
	if _mode != Mode.WATCH:
		decided.emit(_opening, _word)


## WATCH: the host's result, or a normal start once the wait ran out.
func _watch(t: int, now_us: int) -> void:
	if not _host_result.is_empty():
		var first := String(_host_result.opening) == CombatEngine.OPENING_NAMES[CombatSetup.Opening.FIRST_STRIKE]
		_opening = CombatSetup.Opening.FIRST_STRIKE if first else CombatSetup.Opening.NORMAL
		_watch_word(String(_host_result.word), first)
		_show_result(now_us)
		_finalize()
		return
	var good: Array = _windows.get(Defense.Outcome.PRESS, [0, 0])
	if t > _moment_us + int(good[1]) + maxi(0, _tuning.net_opening_wait_ms) * 1000:
		_opening = CombatSetup.Opening.NORMAL
		_show_result(now_us)
		_finalize()


## The host's word, with its sound (an unknown word: just the result).
func _watch_word(press_word: String, first: bool) -> void:
	match press_word:
		WORD_PERFECT:
			_say(press_word, HudStyle.GOLD)
			Sfx.play("skill_press")
		WORD_GOOD:
			_say(press_word, HudStyle.TEXT)
			Sfx.play("skill_press", GOOD_PRESS_VOLUME_DB)
		WORD_EARLY, WORD_LATE:
			_say(press_word, HudStyle.EARLY if press_word == WORD_EARLY else HudStyle.LATE)
			Sfx.play("whiff")
		WORD_MISS:
			_say(press_word, HudStyle.MISS)
			Sfx.play("skill_miss")
		_:
			_say(WORD_GOOD if first else WORD_MISS, HudStyle.TEXT if first else HudStyle.MISS)


func _say(text: String, color: Color) -> void:
	_word = text
	_word_label.text = text
	_word_label.label_settings = HudStyle.label_settings(_visuals.first_strike_word_size, color)


# --- the bots ---------------------------------------------------------------------------------

## The autoplay bots' presses for this ring (FirstStrikeBot): one plan per local player.
func _plan_bots(players: Array[int]) -> void:
	_bot_presses.clear()
	_next_mash_us = 0
	if _options == null or not _options.is_autoplay() or _mode == Mode.WATCH:
		return
	for player: int in players:
		var at := FirstStrikeBot.press_at(_options.autoplay_mode, _options.bot_skill, _rng, _moment_us, _windows)
		if at >= 0:
			_bot_presses[player] = at
	if FirstStrikeBot.mashes(_options.autoplay_mode):
		_next_mash_us = FirstStrikeBot.mash_gap_us(_rng)


## Presses each planned press when the ring's time reaches it (plus the lag compensation the judge
## takes off, half a frame early as the fight bot does); the masher presses on its beat.
func _press_bots(t: int) -> void:
	if _bot_presses.is_empty() and _next_mash_us <= 0:
		return
	var frame_us := int(get_process_delta_time() * 1000000.0)
	@warning_ignore("integer_division")
	var lead_us := frame_us / 2
	for player: int in _bot_presses.keys():
		if t + lead_us >= int(_bot_presses[player]) + _latency_ms * 1000:
			_bot_presses.erase(player)
			_input.inject_press(Defense.Outcome.PRESS, _roster.device_of_player(player))
	if _next_mash_us > 0 and t >= _next_mash_us:
		_next_mash_us = t + FirstStrikeBot.mash_gap_us(_rng)
		var players := _roster.local_players()
		if not players.is_empty():
			var player := players[_rng.randi_range(0, players.size() - 1)]
			_input.inject_press(FirstStrikeBot.mash_action(_rng), _roster.device_of_player(player))


# --- drawing ----------------------------------------------------------------------------------

## The ring at ring time `t`: closing until the result; then held gold on the target for First
## Strike, or gone.
func _draw_ring(t: int) -> void:
	if not _started:
		return
	var scale := _visuals.first_strike_ring_scale
	var good: Array = _windows.get(Defense.Outcome.PRESS, [0, 0])
	var perfect: Array = _windows.get(Defense.Outcome.PRESS_PERFECT, good)
	var lead := maxi(1, _moment_us)
	var rel := t - _moment_us
	var won := _result_at_us > 0 and _opening == CombatSetup.Opening.FIRST_STRIKE
	var color := HudStyle.TEXT
	if won or (_result_at_us == 0 and rel >= int(perfect[0]) and rel <= int(perfect[1])):
		color = HudStyle.GOLD
	var ring := {
		"pos": _ring_box.size * 0.5,
		"radius": _radius(0 if won else rel, lead, scale),
		"color": color,
		"target_radius": _visuals.press_ring_end_radius_px * scale,
		"target_color": Color(HudStyle.GOLD, WON_TARGET_ALPHA) if won else _visuals.press_target_color,
		"bands": [_band(good, lead, scale, _visuals.press_good_band_color),
				_band(perfect, lead, scale, _visuals.press_perfect_band_color)],
	}
	if _result_at_us > 0 and not won:
		# A normal start: the ring is gone.
		_rings.set_rings([] as Array[Dictionary], _visuals.ring_width_px * scale)
		return
	_rings.set_rings([ring] as Array[Dictionary], _visuals.ring_width_px * scale)


func _radius(rel_us: int, lead_us: int, scale: float) -> float:
	return PressNotes.radius(rel_us, lead_us, _visuals.press_ring_start_radius_px * scale,
			_visuals.press_ring_end_radius_px * scale, RING_MIN_RADIUS_PX)


## The ring of radii the shrinking ring passes through during a window [early_us, late_us].
func _band(edges: Array, lead_us: int, scale: float, color: Color) -> Dictionary:
	var outer := _radius(int(edges[0]), lead_us, scale)
	var inner := _radius(int(edges[1]), lead_us, scale)
	return {"radius": (outer + inner) * 0.5, "width": outer - inner, "color": color}


## The line under the ring: the skill press button and "First Strike" (a friend sees P1's tag
## instead of a button: the host presses), in `color`.
func _set_chip(color: Color) -> void:
	# Freed at once (never called from the chip's own code), so no old chip lingers for a frame.
	for child: Node in _chip_holder.get_children():
		child.free()
	var size := _visuals.first_strike_chip_size
	if _mode == Mode.WATCH:
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", HintBar.CHIP_GAP)
		var tag := HudStyle.button_chip(HOST_TAG, false, size)
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tag)
		var label := HudStyle.make_label(CHIP_TEXT, size, color)
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(label)
		_chip_holder.add_child(row)
		return
	_chip_holder.add_child(HintBar.new([[&"skill_press", CHIP_TEXT]], size, color))
