class_name CombatHud
extends CanvasLayer
## The combat HUD on the 1920x1080 canvas (DESIGN.md 7.1, restyled in card #154: slanted ink
## plates edged in worn gold). The turn order as a turn track down the left edge,
## the attack or skill banner at the top centre, a slanted panel per enemy with its HP, status
## badges and the attack it will use next (top right), practice status (top right), party cards
## and the team gauge (with the ultimate's UNLEASH button) bottom left, the defence buttons while
## an enemy attack plays and the skill press while a skill plays (bottom right); the action menu
## floats beside the acting hero. Also popups and damage numbers, training and press rings, hit
## markers, lock icon, the target lock-on, F1 overlay, calibration and the end screen. It shows
## what the CombatMirror says; world positions are projected through the CombatView camera.

const MARGIN: float = 24.0
## The attack banner sits at the top edge (the turn order is a column on the left since card #154,
## so the top is free and the banner stays above the enemies' throws).
const BANNER_TOP: float = 24.0
const BANNER_GAP: float = 10.0
const BANNER_SIZE: int = 46
const BANNER_FROM_SIZE: int = 20
const CENTER_BANNER_SIZE: int = 96
## The big centre words (TEAM COUNTER): under the attack banner's slot, above the heads.
const CENTER_BANNER_TOP: float = 120.0
## Share of a centre banner's time it stays fully visible before fading.
const CENTER_BANNER_HOLD_SHARE: float = 0.7
const POPUP_SIZE: int = 40
const DAMAGE_SIZE: int = 52
const POPUP_WIDTH: float = 480.0
## The bottom left corners (defence controls, skill press hint): see-through panels.
const HINT_SIZE: int = 20
const CORNER_TITLE_SIZE: int = 22
const CORNER_BG := Color(0.02, 0.02, 0.04, 0.6)
const CORNER_PAD: int = 12
const CORNER_GAP: int = 6
const PRACTICE_SIZE: int = 17
## Enemy panels (top right).
const ENEMY_NAME_SIZE: int = 26
const ENEMY_HP_SIZE: int = 21
const ENEMY_BAR_WIDTH: float = 380.0
const ENEMY_BAR_HEIGHT: float = 14.0
const ENEMY_PANEL_PAD: int = 8
const ENEMY_PANEL_GAP: int = 4
## Between the enemy panels.
const ENEMY_STACK_GAP: int = 10
const ENEMY_PANEL_BORDER := Color(0.55, 0.18, 0.16, 0.9)
## Enemy names are their own colour, lifted so dark ones read on the panel.
const ENEMY_NAME_LIGHTEN: float = 0.3
## A beaten enemy's panel fades back to this.
const DEFEATED_TINT := Color(0.75, 0.75, 0.78, 0.55)
## Status badges under an enemy's bar.
const BADGE_PAD_X: int = 7
const BADGE_PAD_Y: int = 1
const BADGE_RADIUS: int = 5
const BADGE_BORDER_PX: int = 2
const BADGE_GAP: int = 6
const BADGE_BG_DARKEN: float = 0.72
const BADGE_BG_ALPHA: float = 0.92
const PANEL_GAP: int = 14
## The defence and skill press buttons (bottom right): one slanted plate per button.
const PRESS_PLATE_SIZE: int = 24
const PRESS_CHIP_SIZE: int = 28
const PRESS_NOTE_SIZE: int = 17

const END_TITLE_SIZE: int = 150
const END_HINT_SIZE: int = 40
const END_DIM := Color(0.0, 0.0, 0.0, 0.62)
const DEFEAT_COLOR := Color(0.9, 0.3, 0.28)
const TARGET_MARKER_SIZE: int = 40
## The arrow over a chosen or attacked fighter.
const TARGET_ARROW := "▼"
const END_SUMMARY_SIZE: int = 30
## Team gauge panel (bottom right).
const GAUGE_WIDTH: float = 300.0
const UNLEASH_TEXT := "UNLEASH"
const UNLEASH_SIZE: int = 26
const UNLEASH_CHIP_SIZE: int = 26
const UNLEASH_LOCKED := Color(0.6, 0.6, 0.64, 0.4)
const GAUGE_HEIGHT: float = 28.0
const GAUGE_LABEL_SIZE: int = 22
const GAUGE_TEXT_SIZE: int = 21
const GAUGE_PAD: int = 12
const GAUGE_BORDER_PX: int = 2
const GAUGE_READY_BORDER_PX: int = 3
## The ready gauge's bar brightens toward this at the top of each pulse.
const GAUGE_READY_BRIGHT := Color(1.6, 1.4, 1.0)
## The ready glow never fades below this share of its size and strength, so it always reads as lit.
const GAUGE_GLOW_MIN_SHARE: float = 0.35
const GAUGE_GLOW_ALPHA: float = 0.75
const ENEMY_STATUS_SIZE: int = 18
const INTENT_SIZE: int = 22
## The turn order column's see-through while an attack or a skill plays, and how fast it fades.
const TIMELINE_BUSY_ALPHA: float = 0.3
const TIMELINE_FADE_S: float = 0.2
## Gap kept between stacked popups (pixels).
const POPUP_GAP_PX: float = 4.0
## Popups whose spots are closer than this share of POPUP_WIDTH horizontally share a column.
const POPUP_COLUMN_SHARE: float = 0.3
## A popup pushed against the ceiling fades out over this share of its life (not a hard cut).
const POPUP_LEAVE_SHARE: float = 0.12
## Popup animation shape: punch settle, then fade over the end of the life.
const POPUP_PUNCH_SHARE: float = 0.15
const POPUP_FADE_FROM_SHARE: float = 0.6

var action_menu: ActionMenu
var overlay: DebugOverlay
var calibration: CalibrationPanel

var _view: CombatView
var _visuals: CombatVisuals
var _tuning: Tuning
var _root: Control
var _timeline: TimelineRow
var _banner: PanelContainer
var _banner_label: Label
## The banner's small line over the move's name: who uses it (and on whom).
var _banner_from: Label
## The attack's hits under the banner text, spaced by time (hidden for skills).
var _banner_row: HitRowView
var _center_banner: Label
var _enemy_box: VBoxContainer
## Enemy id -> {panel: PanelContainer, bar: TrailBar, hp: Label, badges: HBoxContainer,
## badge_key: String (what the badges show now)}.
var _enemy_rows: Dictionary = {}
var _party_box: HBoxContainer
var _party_panels: Dictionary = {}
var _practice_label: Label
var _popup_layer: Control
var _ring_layer: RingLayer
var _marker_layer: HitMarkerLayer
var _lock_icon: TextureRect
## More lock icons when several co-op players are locked out at once.
var _extra_locks: Array[TextureRect] = []
var _target_marker: Label
## The lock-on frame around the fighter being targeted in the menu.
var _reticle: Reticle
## One arrow per targeted character while an attack winds up.
var _target_arrows: Array[Label] = []
var _end_screen: Control
var _end_title: Label
var _end_summary: Label
var _end_hint: HintBar
var _end_note: Label
var _portraits: Dictionary = {}
var _colors: Dictionary = {}
## Popups on screen, oldest first: [{label: Label, base: Vector2 (spawn centre), born_us: int}].
var _popups: Array[Dictionary] = []
var _center_tween: Tween
var _targeted: Array[int] = []
var _gauge_bar: ProgressBar
var _gauge_label: Label
## The percentage drawn on the gauge bar.
var _gauge_text: Label
## The gauge panel's frame: it turns gold and glows while the ultimate is ready.
var _gauge_style: StyleBoxFlat
var _gauge_full: bool = false
var _gauge_panel: PanelContainer
## The ultimate's button on the gauge card, and its word.
var _unleash: HBoxContainer
var _unleash_label: Label
## Bottom left: the defence controls while an enemy attack plays (set_defending) and the skill
## press hint during a skill (set_skill_pressing); empty otherwise, for the action menu.
var _controls: Control
var _controls_tween: Tween
var _skill_hint: Control
var _skill_hint_tween: Tween
## Full-screen flash (counters, the ultimate, a hero going down) and the red edge pulse while a
## hero is low on HP (card #38).
var _flash_rect: ColorRect
var _flash_tween: Tween
var _danger: TextureRect
var _in_danger: bool = false
var _time_s: float = 0.0
## Enemy id -> the intent line on its panel: {panel: the line, label: Label, row: HitRowView,
## shown: Array (kinds and times on the row)}.
var _intent_signs: Dictionary = {}
## AttackHitData.Kind -> Texture2D.
var _hit_icons: Dictionary = {}


## Builds the parts that do not depend on the fighters.
func setup(view: CombatView, visuals: CombatVisuals, tuning: Tuning) -> void:
	_view = view
	_visuals = visuals
	_tuning = tuning
	layer = 10

	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_danger = TextureRect.new()
	_danger.name = "Danger"
	_danger.texture = _vignette_texture(HudStyle.HP_LOW)
	_danger.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_danger.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_danger.stretch_mode = TextureRect.STRETCH_SCALE
	_danger.set_anchors_preset(Control.PRESET_FULL_RECT)
	_danger.visible = false
	_root.add_child(_danger)

	_flash_rect = ColorRect.new()
	_flash_rect.name = "ScreenFlash"
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_flash_rect.material = add
	_flash_rect.color = Color(0, 0, 0, 0)
	_flash_rect.visible = false
	_root.add_child(_flash_rect)

	_ring_layer = RingLayer.new()
	_ring_layer.name = "Rings"
	_root.add_child(_ring_layer)

	_marker_layer = HitMarkerLayer.new()
	_marker_layer.name = "HitMarkers"
	_root.add_child(_marker_layer)

	_popup_layer = Control.new()
	_popup_layer.name = "Popups"
	_popup_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popup_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_popup_layer)

	_lock_icon = TextureRect.new()
	_lock_icon.name = "Lock"
	_lock_icon.texture = AssetLoader.texture(visuals.lock_icon_path, Vector2i(12, 12))
	_lock_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_lock_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_lock_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_lock_icon.size = Vector2(visuals.lock_icon_px, visuals.lock_icon_px)
	_lock_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lock_icon.visible = false
	_root.add_child(_lock_icon)

	_target_marker = HudStyle.make_label(TARGET_ARROW, TARGET_MARKER_SIZE, HudStyle.GOLD)
	_target_marker.visible = false
	_root.add_child(_target_marker)
	_reticle = Reticle.new()
	_reticle.name = "TargetReticle"
	_reticle.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_reticle)

	_hit_icons = {
		AttackHitData.Kind.NORMAL: AssetLoader.texture(visuals.hit_icon_normal_path, Vector2i(12, 12)),
		AttackHitData.Kind.GROUND: AssetLoader.texture(visuals.hit_icon_ground_path, Vector2i(12, 12)),
		AttackHitData.Kind.REND: AssetLoader.texture(visuals.hit_icon_rend_path, Vector2i(12, 12)),
		AttackHitData.Kind.SWEEP: AssetLoader.texture(visuals.hit_icon_sweep_path, Vector2i(12, 12)),
	}
	_timeline = TimelineRow.new()
	_timeline.name = "Timeline"
	_timeline.position = Vector2(MARGIN, MARGIN)
	_timeline.setup(tuning.turn_order_preview, visuals.portrait_px)
	_root.add_child(_timeline)

	_banner = PanelContainer.new()
	_banner.name = "Banner"
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_theme_stylebox_override("panel", HudStyle.slant(Color(0.09, 0.02, 0.025, 0.93), HudStyle.LATE, 3, 12, 80.0, 0.18))
	var banner_column := VBoxContainer.new()
	banner_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_column.add_theme_constant_override("separation", 6)
	_banner.add_child(banner_column)
	_banner_from = HudStyle.make_title("", BANNER_FROM_SIZE, HudStyle.TEXT_DIM.lightened(0.3))
	_banner_from.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_column.add_child(_banner_from)
	_banner_label = HudStyle.make_worn_title("", BANNER_SIZE, HudStyle.TEXT)
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_column.add_child(_banner_label)
	_banner_row = HitRowView.new()
	_banner_row.name = "HitRow"
	_banner_row.setup(visuals.banner_icon_px, visuals, true)
	_banner_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_banner_row.visible = false
	banner_column.add_child(_banner_row)
	_banner.visible = false
	# Anchored at the top centre and growing both ways, so it stays centred for any text length.
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.offset_top = BANNER_TOP
	_root.add_child(_banner)

	_center_banner = HudStyle.make_worn_title("", CENTER_BANNER_SIZE)
	_center_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_banner.add_theme_stylebox_override("normal", _band(3))
	_center_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_center_banner.offset_top = CENTER_BANNER_TOP
	_center_banner.visible = false
	_root.add_child(_center_banner)

	# Top right: a framed panel per enemy (HP, statuses), then the practice status under them.
	var right_column := VBoxContainer.new()
	right_column.name = "RightColumn"
	right_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_column.add_theme_constant_override("separation", 18)
	right_column.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right_column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right_column.offset_right = -MARGIN
	right_column.offset_top = MARGIN
	_root.add_child(right_column)
	_root.move_child(_reticle, -1)
	# Popups and the lock icon draw above the banners and timeline (never hidden under them);
	# everything added after this (panels, menu, overlay, end screen) draws above them.
	_root.move_child(_popup_layer, -1)
	_root.move_child(_lock_icon, -1)
	_enemy_box = VBoxContainer.new()
	_enemy_box.name = "Enemies"
	_enemy_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enemy_box.add_theme_constant_override("separation", ENEMY_STACK_GAP)
	_enemy_box.size_flags_horizontal = Control.SIZE_SHRINK_END
	right_column.add_child(_enemy_box)
	_practice_label = HudStyle.make_label("", PRACTICE_SIZE, HudStyle.GOLD)
	_practice_label.name = "PracticeStatus"
	_practice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_practice_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	_practice_label.visible = tuning.practice_tools_enabled
	right_column.add_child(_practice_label)

	_party_box = HBoxContainer.new()
	_party_box.name = "Party"
	_party_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_party_box.add_theme_constant_override("separation", PANEL_GAP)
	_party_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_party_box.grow_horizontal = Control.GROW_DIRECTION_END
	_party_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_party_box.offset_left = MARGIN
	_party_box.offset_right = MARGIN
	_party_box.offset_bottom = -MARGIN
	_root.add_child(_party_box)
	_build_gauge()

	# Bottom right, hidden until needed (the action menu uses this corner on the party's turn).
	_controls = _make_corner("ControlsHint", "DEFEND", HudStyle.LATE, _defend_row(),
			"Ground wave: Jump only    Parry every hit: counterattack")
	_skill_hint = _make_corner("SkillPressHint", "PRESS ON THE BEAT", HudStyle.GOLD,
			_press_row([[&"skill_press", "SKILL PRESS"]], HudStyle.GOLD))

	action_menu = ActionMenu.new()
	action_menu.name = "ActionMenu"
	_root.add_child(action_menu)
	action_menu.ultimate_pressed.connect(_on_ultimate_pressed)

	overlay = DebugOverlay.new()
	overlay.name = "DebugOverlay"
	_root.add_child(overlay)

	calibration = CalibrationPanel.new()
	calibration.name = "Calibration"
	_root.add_child(calibration)

	_build_end_screen()


## Builds the timeline portraits, party panels and enemy bars once the fighters are known.
## `data_by_id` maps combatant id -> CharacterData or EnemyData.
func build_fighters(mirror: CombatMirror, data_by_id: Dictionary) -> void:
	for id: int in mirror.fighters:
		var data: Resource = data_by_id.get(id)
		if data is CharacterData:
			_portraits[id] = AssetLoader.texture((data as CharacterData).portrait_path, Vector2i(48, 48))
			_colors[id] = (data as CharacterData).color
		elif data is EnemyData:
			_portraits[id] = AssetLoader.texture((data as EnemyData).portrait_path, Vector2i(48, 48))
			_colors[id] = (data as EnemyData).color
	# Panels in the same left-to-right order as the fighters on screen.
	var party: Array[int] = mirror.party_ids.duplicate()
	party.sort_custom(func(a: int, b: int) -> bool:
		return _view.screen_position(_view.home_of(a)).x < _view.screen_position(_view.home_of(b)).x)
	for id: int in party:
		var f := mirror.fighter(id)
		var panel := PartyPanel.new()
		panel.setup(id, String(f.display_name), color_of(id), portrait(id), _tuning.max_ap, _visuals)
		_party_box.add_child(panel)
		_party_panels[id] = panel
	# The gauge card goes after the heroes.
	_party_box.move_child(_gauge_panel, -1)
	for id: int in mirror.enemy_ids:
		_enemy_rows[id] = _make_enemy_panel(id, String(mirror.fighter(id).display_name))


## Updates every bar, panel and the timeline from the mirror.
func refresh(mirror: CombatMirror, practice_text: String) -> void:
	var order: Array[int] = []
	if mirror.result.is_empty():
		order = mirror.turn_order
	_timeline.show_order(order, mirror, _portraits, _colors)
	for id: int in _party_panels:
		var panel := _party_panels[id] as PartyPanel
		panel.refresh(mirror.fighter(id), id == mirror.active_actor)
		panel.set_targeted(_targeted.has(id))
	for id: int in _enemy_rows:
		var f := mirror.fighter(id)
		var row: Dictionary = _enemy_rows[id]
		var alive := bool(f.alive)
		(row.bar as TrailBar).set_values(int(f.hp), int(f.max_hp))
		var hp_label := row.hp as Label
		hp_label.text = "%d / %d" % [int(f.hp), int(f.max_hp)] if alive else "DEFEATED"
		hp_label.label_settings.font_color = HudStyle.TEXT if alive else HudStyle.TEXT_DIM
		(row.panel as Control).modulate = Color.WHITE if alive else DEFEATED_TINT
		_show_badges(row, (f.get("statuses", {}) as Dictionary) if alive else {})
		_refresh_intent_sign(id, mirror)
	_practice_label.text = practice_text
	_refresh_gauge(mirror.team_gauge)
	_in_danger = false
	if mirror.result.is_empty():
		for id: int in mirror.party_ids:
			var f := mirror.fighter(id)
			if bool(f.get("alive", false)) and int(f.hp) * 100 <= int(f.max_hp) * _visuals.danger_hp_percent:
				_in_danger = true


func portrait(id: int) -> Texture2D:
	return _portraits.get(id) as Texture2D


func color_of(id: int) -> Color:
	return _colors.get(id, Color.WHITE) as Color


## The attack banner (red border), or a skill banner with another accent colour: the move's name
## big, and over it a small line saying who uses it (and on whom).
func show_banner(text: String, accent: Color = HudStyle.LATE, from: String = "") -> void:
	# A fading TEAM COUNTER banner from the previous turn never sits under a new attack banner.
	if _center_tween != null and _center_tween.is_valid():
		_center_tween.kill()
	_center_banner.visible = false
	var style := _banner.get_theme_stylebox("panel") as StyleBoxFlat
	style.border_color = accent
	style.border_width_left = 8
	style.border_width_right = 8
	var was_shown := _banner.visible and _banner_label.text == text.to_upper()
	_banner_label.text = text.to_upper()
	_banner_from.text = from
	_banner_from.visible = not from.is_empty()
	_banner_row.visible = false
	_fit_banner()
	if not was_shown:
		_punch(_banner)


## Shows the attack's hits under the banner text, spaced by time (`kinds` AttackHitData.Kind,
## `times` impacts in ms), all upcoming.
func set_banner_hits(kinds: Array, times: Array, feints: Array = [], marks: Array = []) -> void:
	_banner_row.set_hits(kinds, times, _hit_icons, feints, marks)
	_banner_row.set_states([])
	_banner_row.modulate.a = 1.0
	_banner_row.visible = not kinds.is_empty()
	_fit_banner()


## HitRhythm.State per hit of the banner row.
func set_banner_hit_states(states: Array[int]) -> void:
	_banner_row.set_states(states)


## Shows or hides the banner's hit row (hidden once the first hit lands, tuning
## hide_intent_after_first_hit); the banner keeps its size so the text does not jump.
func show_banner_hits(shown: bool) -> void:
	_banner_row.modulate.a = 1.0 if shown else 0.0


## The intent icon texture of an AttackHitData.Kind.
func hit_icon(kind: int) -> Texture2D:
	return _hit_icons.get(kind) as Texture2D


## Shows these hit markers (see HitMarkerLayer); empty hides them all.
## Who an enemy attack is aimed at, for its intent sign and banner: WHOLE PARTY, one name, or for
## an each-in-turn attack the names in the order it strikes them ("CASS > ALDER > BRIN").
static func target_text(mirror: CombatMirror, mode: int, targets: Array) -> String:
	if mode == EnemyAttackData.TargetMode.PARTY or targets.is_empty():
		return "WHOLE PARTY"
	if mode == EnemyAttackData.TargetMode.SINGLE and targets.size() != 1:
		return "WHOLE PARTY"
	var names := PackedStringArray()
	for id: Variant in targets:
		names.append(String(mirror.fighter(int(id)).get("display_name", "?")).to_upper())
	return " > ".join(names)


func set_hit_markers(markers: Array[Dictionary]) -> void:
	_marker_layer.set_markers(markers)


## A full-width ink band edged in worn gold, tilted a touch (behind the big words: TEAM COUNTER,
## VICTORY).
static func _band(edge_px: int) -> StyleBoxFlat:
	var band := StyleBoxFlat.new()
	band.bg_color = Color(0.02, 0.015, 0.03, 0.84)
	band.border_color = HudStyle.EDGE
	band.border_width_top = edge_px
	band.border_width_bottom = edge_px
	band.skew = Vector2(0.0, -0.02)
	band.content_margin_top = 10 + edge_px
	band.content_margin_bottom = 4 + edge_px
	band.shadow_color = HudStyle.PLATE_SHADOW
	band.shadow_size = 1
	band.shadow_offset = Vector2(0.0, 8.0)
	return band


## A plate arrives with a punch: a little big and see-through, snapping to size (Persona 5's
## slam-in, kept short so it never hides a hit).
func _punch(node: Control) -> void:
	node.reset_size()
	node.pivot_offset = node.size * 0.5
	node.scale = Vector2(1.18, 1.18)
	node.modulate.a = 0.0
	var tween := node.create_tween().set_parallel(true)
	tween.tween_property(node, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "modulate:a", 1.0, 0.1)


## Shows the banner and lets it take the size of its content again (centred), under the turn
## order strip.
func _fit_banner() -> void:
	var top := _banner_top(BANNER_TOP)
	_banner.visible = true
	_banner.offset_left = 0.0
	_banner.offset_right = 0.0
	_banner.offset_top = top
	_banner.offset_bottom = top
	# Never under the enemy panels: when it would reach them, it moves left to clear them.
	_banner.reset_size()
	var right_edge := _enemy_box.get_global_rect().position.x - MARGIN
	var half := _banner.get_combined_minimum_size().x * 0.5
	var centre := _root.size.x * 0.5
	if _enemy_box.get_global_rect().end.y > top and centre + half > right_edge:
		var shift := maxf(centre + half - right_edge, 0.0)
		_banner.offset_left = -shift
		_banner.offset_right = -shift


func hide_banner() -> void:
	_banner.visible = false


## Shows the defence controls (bottom left) while an enemy attack plays, fading them in or out
## over controls_fade_ms. The corner is empty otherwise: the action menu uses it on the party's
## turn.
func set_defending(on: bool) -> void:
	_controls_tween = _fade_corner(_controls, on, _controls_tween)


## Shows the skill press button (bottom left) while a skill's presses play, like set_defending.
func set_skill_pressing(on: bool) -> void:
	_skill_hint_tween = _fade_corner(_skill_hint, on, _skill_hint_tween)


## Big text in the middle of the screen (TEAM COUNTER) for `ms` milliseconds.
func show_center_banner(text: String, color: Color, ms: int) -> void:
	_center_banner.offset_top = _banner_top(CENTER_BANNER_TOP)
	_center_banner.text = text
	_center_banner.label_settings.font_color = HudStyle.worn_color(color)
	_center_banner.visible = true
	_center_banner.modulate = Color.WHITE
	_center_banner.scale = Vector2.ONE
	if _center_tween != null and _center_tween.is_valid():
		_center_tween.kill()
	_center_tween = _center_banner.create_tween()
	_center_tween.tween_interval(float(ms) / 1000.0 * CENTER_BANNER_HOLD_SHARE)
	_center_tween.tween_property(_center_banner, "modulate:a", 0.0, float(ms) / 1000.0 * (1.0 - CENTER_BANNER_HOLD_SHARE))
	_center_tween.tween_callback(_center_banner.hide)


## A floating text that rises and fades over tuning popup_ms, at a world position.
func popup(text: String, world_pos: Vector3, color: Color, font_size: int = POPUP_SIZE) -> void:
	popup_screen(text, _view.screen_position(world_pos), color, font_size)


## A floating text at a HUD canvas position. It rises and fades over tuning popup_ms; popups in
## the same column stack (see _layout_popups).
func popup_screen(text: String, screen_pos: Vector2, color: Color, font_size: int = POPUP_SIZE) -> void:
	var label := _make_popup_label(text, color, font_size)
	_popups.append({"label": label, "base": screen_pos, "born_us": Time.get_ticks_usec()})
	_layout_popups()


func _process(delta: float) -> void:
	_time_s += delta
	if not _popups.is_empty():
		_layout_popups()
	# The ready ultimate breathes (bar brightens, gold glow around its frame); the screen edges
	# pulse red while a hero is in danger.
	var glow := 0.5 + 0.5 * sin(_time_s * TAU * _visuals.gauge_ready_pulse_hz)
	_gauge_bar.modulate = Color.WHITE.lerp(GAUGE_READY_BRIGHT, glow) if _gauge_full else Color.WHITE
	# The unleash button: breathing gold while a hero can use the ultimate now, steady gold while
	# full on someone else's turn, faded while the gauge fills.
	var can_unleash := action_menu.ultimate_ready()
	_unleash_label.label_settings.font_color = HudStyle.GOLD if _gauge_full else HudStyle.TEXT_DIM
	if can_unleash:
		_unleash.modulate = Color.WHITE.lerp(GAUGE_READY_BRIGHT, glow)
	elif _gauge_full:
		_unleash.modulate = Color(1.0, 1.0, 1.0, 0.7)
	else:
		_unleash.modulate = UNLEASH_LOCKED
	if _gauge_full:
		var reach := lerpf(GAUGE_GLOW_MIN_SHARE, 1.0, glow)
		_gauge_style.shadow_size = roundi(_visuals.gauge_ready_glow_px * reach)
		_gauge_style.shadow_color = Color(HudStyle.GOLD, GAUGE_GLOW_ALPHA * reach)
	# The turn order column steps back while an attack or a skill plays (the camera moves in close
	# then and the column would cover the heroes on the left).
	var busy := _controls.visible or _skill_hint.visible
	var wanted := TIMELINE_BUSY_ALPHA if busy else 1.0
	_timeline.modulate.a = move_toward(_timeline.modulate.a, wanted, delta / TIMELINE_FADE_S)
	if action_menu.visible:
		action_menu.follow(_fighter_rect(action_menu.actor_id), _menu_area(), _menu_avoid(), delta)
	if _reticle.visible:
		_reticle.frame = _fighter_rect(_reticle.target)
		_reticle.time_s = _time_s
		_reticle.queue_redraw()
	_danger.visible = _in_danger
	if _in_danger:
		var pulse := 0.5 + 0.5 * sin(_time_s * TAU * _visuals.danger_pulse_hz)
		_danger.modulate = Color(1.0, 1.0, 1.0, _visuals.danger_vignette_alpha * (0.5 + 0.5 * pulse))


## Where the action menu may go: right of the turn order column, above the party cards, inside the
## screen's margins.
func _menu_area() -> Rect2:
	var left := _timeline.get_global_rect().end.x + BANNER_GAP if _timeline.visible else MARGIN
	var top := MARGIN
	var bottom := _party_box.get_global_rect().position.y - BANNER_GAP
	return Rect2(Vector2(left, top), Vector2(_root.size.x - MARGIN - left, maxf(0.0, bottom - top)))


## What the action menu should not cover: each standing enemy, the enemy panels and the practice
## lines.
func _menu_avoid() -> Array[Rect2]:
	var boxes: Array[Rect2] = [_enemy_box.get_global_rect()]
	if _banner.visible:
		boxes.append(_banner.get_global_rect())
	if _practice_label.visible and not _practice_label.text.is_empty():
		boxes.append(_practice_label.get_global_rect())
	for id: int in _enemy_rows:
		var v := _view.fighter(id)
		if v != null and v.visible and not v.is_dissolving():
			boxes.append(_fighter_rect(id))
	return boxes


## A fighter's box on screen, from the top of the head to the feet (empty if unknown).
func _fighter_rect(id: int) -> Rect2:
	if id < 0:
		return Rect2()
	var v := _view.fighter(id)
	if v == null:
		return Rect2()
	# The visible body's middle to its feet is about half its height.
	var centre := _view.screen_position(v.centre_position())
	var feet := _view.screen_position(v.body_position())
	var half := maxf(40.0, feet.y - centre.y)
	var wide := half * 1.4
	return Rect2(Vector2(centre.x - wide * 0.5, centre.y - half * 1.1), Vector2(wide, half * 2.1))


## A full-screen flash of `color` at `strength` (0 to 1) that fades over screen_flash_ms. A
## stronger flash replaces a weaker one still fading. The player's Flashes setting scales it
## (card #185).
func screen_flash(color: Color, strength: float) -> void:
	strength *= _visuals.screen_flash_scale(PlayerSettings.flash_mode())
	if strength <= 0.0:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		if _flash_rect.color.a > strength:
			return
		_flash_tween.kill()
	_flash_rect.visible = true
	_flash_rect.color = Color(color.r, color.g, color.b, strength)
	_flash_tween = _flash_rect.create_tween()
	_flash_tween.tween_property(_flash_rect, "color:a", 0.0, float(_visuals.screen_flash_ms) / 1000.0) 			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_flash_tween.tween_callback(_flash_rect.hide)


## A soft frame of `color` around the screen edges (clear in the middle).
static func _vignette_texture(color: Color) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(color, 0.0))
	gradient.set_color(1, Color(color, 1.0))
	gradient.add_point(0.55, Color(color, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 256
	texture.height = 256
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 1.15)
	return texture


func _make_popup_label(text: String, color: Color, font_size: int) -> Label:
	var seconds := float(_tuning.popup_ms) / 1000.0
	var label := HudStyle.make_label(text, font_size, color)
	label.label_settings = HudStyle.punch_settings(font_size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(POPUP_WIDTH, 0.0)
	_popup_layer.add_child(label)
	label.reset_size()
	label.pivot_offset = label.size * 0.5
	label.scale = Vector2.ONE * _visuals.popup_punch_scale
	var tween := label.create_tween().set_parallel(true)
	tween.tween_property(label, "scale", Vector2.ONE, seconds * POPUP_PUNCH_SHARE).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, seconds * (1.0 - POPUP_FADE_FROM_SHARE)).set_delay(seconds * POPUP_FADE_FROM_SHARE)
	tween.chain().tween_callback(label.queue_free)
	return label


## A damage number at a world position; `big` (a hit that took a large share of the target's HP)
## shows it bigger.
func damage_number(amount: int, world_pos: Vector3, color: Color, big: bool = false) -> void:
	popup(str(amount), world_pos, color, roundi(DAMAGE_SIZE * (_visuals.big_hit_scale if big else 1.0)))


func set_rings(rings: Array[Dictionary]) -> void:
	_ring_layer.set_rings(rings, _visuals.ring_width_px)


## Shows a lock icon at each of these world positions (one per locked-out player; empty hides),
## placed lock_icon_offset_px from it on screen.
func set_locks(spots: Array[Vector3]) -> void:
	while 1 + _extra_locks.size() < spots.size():
		var icon := _lock_icon.duplicate() as TextureRect
		_lock_icon.add_sibling(icon)
		_extra_locks.append(icon)
	var icons: Array[TextureRect] = [_lock_icon]
	icons.append_array(_extra_locks)
	for i: int in icons.size():
		icons[i].visible = i < spots.size()
		if icons[i].visible:
			icons[i].position = _view.screen_position(spots[i]) + _visuals.lock_icon_offset_px - icons[i].size * 0.5


## Tags each party panel with its co-op player (`owners`: party member id -> player; empty hides).
func set_player_tags(owners: Dictionary) -> void:
	for id: int in _party_panels:
		(_party_panels[id] as PartyPanel).set_player(int(owners.get(id, -1)))


## Highlights the party panels of the characters an enemy attack targets (empty clears).
func set_targeted(ids: Array[int]) -> void:
	_targeted = ids.duplicate()
	for id: int in _party_panels:
		(_party_panels[id] as PartyPanel).set_targeted(_targeted.has(id))


## Shows an arrow above each of these world positions (empty hides them all).
func set_target_arrows(heads: Array[Vector3]) -> void:
	while _target_arrows.size() < heads.size():
		var arrow := HudStyle.make_label(TARGET_ARROW, TARGET_MARKER_SIZE, HudStyle.LATE)
		_root.add_child(arrow)
		_target_arrows.append(arrow)
	for i: int in _target_arrows.size():
		var arrow := _target_arrows[i]
		arrow.visible = i < heads.size()
		if arrow.visible:
			arrow.reset_size()
			arrow.position = _view.screen_position(heads[i]) - Vector2(arrow.size.x * 0.5, arrow.size.y)


## Locks a gold frame onto the fighter being chosen as a target in the menu (-1 hides it).
func set_target(id: int) -> void:
	_reticle.target = id
	_reticle.visible = id >= 0
	_reticle.born_s = _time_s


## Points at the enemy being targeted (only shown when there is a choice); -1 hides it.
func set_target_marker(world_pos: Vector3, shown: bool) -> void:
	_target_marker.visible = shown
	if shown:
		_target_marker.reset_size()
		_target_marker.position = _view.screen_position(world_pos) - Vector2(_target_marker.size.x * 0.5, _target_marker.size.y)


## The victory or defeat screen, with a short summary of the fight; `hints` ([[action, text], ...])
## say what the buttons do (the controller knows whether this is a test fight, a zone fight or a
## run fight) and `note` adds a line above them.
func show_end(result: String, summary: String, hints: Array, note: String = "") -> void:
	match result:
		"victory":
			_end_title.text = "VICTORY"
			_end_title.label_settings.font_color = HudStyle.worn_gold()
		"escaped":
			_end_title.text = "ESCAPED"
			_end_title.label_settings.font_color = HudStyle.JUMP
		_:
			_end_title.text = "DEFEAT"
			_end_title.label_settings.font_color = DEFEAT_COLOR
	_end_summary.text = summary
	_end_hint.set_entries(hints)
	_end_note.text = note
	_end_note.visible = not note.is_empty()
	set_defending(false)
	set_skill_pressing(false)
	_end_screen.visible = true
	_end_screen.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_end_title.pivot_offset = _end_title.size * 0.5
	_end_title.scale = Vector2(1.25, 1.25)
	_end_title.create_tween().tween_property(_end_title, "scale", Vector2.ONE, 0.35) 			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_end_screen.create_tween().tween_property(_end_screen, "modulate:a", 1.0, float(_visuals.end_fade_ms) / 1000.0)
	# The F1 stats can be read on the end screen: draw them above its dim.
	_root.move_child(overlay, -1)


func is_end_shown() -> bool:
	return _end_screen.visible


## Draws the lock icon and a popup once, nearly invisible, so nothing compiles mid-fight.
func warm_up() -> void:
	_lock_icon.visible = true
	_lock_icon.modulate = Color(1.0, 1.0, 1.0, CombatView.WARM_UP_ALPHA)
	var label := _make_popup_label(" ", HudStyle.TEXT, POPUP_SIZE)
	label.position = Vector2(-POPUP_WIDTH, -100.0)


func finish_warm_up() -> void:
	_lock_icon.visible = false
	_lock_icon.modulate = Color.WHITE


## A banner's top (the turn order column is beside it, never above it).
func _banner_top(wanted: float) -> float:
	return wanted


## The bottom-right corner (where the action menu sits on the party's turn): a slanted title tag
## in `title_color`, `content` (button plates) under it and an optional `note`, right-aligned.
## Hidden until _fade_corner shows it.
func _make_corner(node_name: String, title: String, title_color: Color, content: Control, note: String = "") -> VBoxContainer:
	var corner := VBoxContainer.new()
	corner.name = node_name
	corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	corner.alignment = BoxContainer.ALIGNMENT_END
	corner.add_theme_constant_override("separation", 10)
	var tag := PanelContainer.new()
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.size_flags_horizontal = Control.SIZE_SHRINK_END
	tag.add_theme_stylebox_override("panel", HudStyle.slant(Color(title_color.darkened(0.7), 0.94), title_color, 3, 6, 44.0))
	tag.add_child(HudStyle.make_title(title, CORNER_TITLE_SIZE + 8, title_color.lightened(0.2)))
	corner.add_child(tag)
	content.size_flags_horizontal = Control.SIZE_SHRINK_END
	corner.add_child(content)
	if not note.is_empty():
		var label := HudStyle.make_label(note, PRESS_NOTE_SIZE, HudStyle.TEXT_DIM.lightened(0.25))
		label.size_flags_horizontal = Control.SIZE_SHRINK_END
		corner.add_child(label)
	corner.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	corner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	corner.grow_vertical = Control.GROW_DIRECTION_BEGIN
	corner.offset_right = -MARGIN
	corner.offset_bottom = -MARGIN
	corner.visible = false
	corner.modulate.a = 0.0
	_root.add_child(corner)
	return corner


## The three defence buttons as plates side by side, each in its defence colour.
func _defend_row() -> HBoxContainer:
	return _press_row([[&"defend_parry", "PARRY", HudStyle.PARRY], [&"defend_dodge", "DODGE", HudStyle.DODGE],
			[&"defend_jump", "JUMP", HudStyle.JUMP]], HudStyle.EDGE)


## A row of button plates: [[action, word, colour?], ...] (colour: the word's and the edge's).
func _press_row(entries: Array, edge: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	for entry: Array in entries:
		var color: Color = entry[2] if entry.size() > 2 else edge
		var plate := PanelContainer.new()
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := HudStyle.slant(HudStyle.INK_SOLID, color, 2, 8, 50.0)
		style.border_width_left = 5
		plate.add_theme_stylebox_override("panel", style)
		var line := HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_theme_constant_override("separation", 10)
		plate.add_child(line)
		line.add_child(HintBar.new([[StringName(entry[0]), ""]], PRESS_CHIP_SIZE, HudStyle.TEXT))
		var word := HudStyle.make_title(String(entry[1]), PRESS_PLATE_SIZE, color)
		word.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(word)
		row.add_child(plate)
	return row


## Fades a bottom left corner in or out over controls_fade_ms (hidden once faded out). Takes the
## corner's running fade and returns the new one (null when the corner is already there).
func _fade_corner(corner: Control, on: bool, running: Tween) -> Tween:
	if running != null and running.is_valid():
		running.kill()
	var alpha := 1.0 if on else 0.0
	if corner.visible == on and is_equal_approx(corner.modulate.a, alpha):
		return null
	corner.visible = true
	var tween := corner.create_tween()
	tween.tween_property(corner, "modulate:a", alpha, float(_visuals.controls_fade_ms) / 1000.0)
	if not on:
		tween.tween_callback(corner.hide)
	return tween


## Bottom left, after the party cards (a card of its own, so it sits with the team): the shared
## team gauge, its percentage on the bar.
func _build_gauge() -> void:
	var panel := PanelContainer.new()
	panel.name = "TeamGauge"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauge_style = HudStyle.slant(HudStyle.INK, HudStyle.EDGE_DIM, GAUGE_BORDER_PX, GAUGE_PAD, PartyPanel.CARD_HEIGHT, 0.12)
	panel.add_theme_stylebox_override("panel", _gauge_style)
	panel.custom_minimum_size = Vector2(GAUGE_WIDTH, 0.0)
	_party_box.add_child(panel)
	_gauge_panel = panel
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", CORNER_GAP)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(column)
	_gauge_label = HudStyle.make_title("TEAM GAUGE", GAUGE_LABEL_SIZE, HudStyle.GAUGE_FILL)
	column.add_child(_gauge_label)
	_gauge_bar = HudStyle.bar(HudStyle.GAUGE_FILL, GAUGE_HEIGHT)
	var track := _gauge_bar.get_theme_stylebox("background") as StyleBoxFlat
	track.border_color = HudStyle.EDGE_DIM
	track.set_border_width_all(1)
	_gauge_bar.custom_minimum_size.x = GAUGE_WIDTH
	_gauge_text = HudStyle.make_number("", GAUGE_TEXT_SIZE)
	column.add_child(PartyPanel.text_on_bar(_gauge_bar, _gauge_text))
	# The ultimate's button lives here, not in the action menu (user, 2026-10-16): faded while the
	# gauge fills, gold and breathing while a hero can unleash it.
	_unleash = HBoxContainer.new()
	_unleash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_unleash.alignment = BoxContainer.ALIGNMENT_CENTER
	_unleash.add_theme_constant_override("separation", 10)
	column.add_child(_unleash)
	_unleash.add_child(HintBar.new([[&"fight_ultimate", ""]], UNLEASH_CHIP_SIZE, HudStyle.TEXT))
	_unleash_label = HudStyle.make_title(UNLEASH_TEXT, UNLEASH_SIZE, HudStyle.TEXT_DIM)
	_unleash_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_unleash.add_child(_unleash_label)
	_unleash.modulate = UNLEASH_LOCKED


## The ultimate's button was pressed: the gauge card flashes.
func _on_ultimate_pressed() -> void:
	_gauge_panel.modulate = Color(2.0, 1.8, 1.2)
	_gauge_panel.create_tween().tween_property(_gauge_panel, "modulate", Color.WHITE, 0.25)


func _refresh_gauge(value: int) -> void:
	var gauge_max := maxi(1, _tuning.team_gauge_max)
	var full := value >= gauge_max
	_gauge_bar.max_value = gauge_max
	_gauge_bar.value = value
	@warning_ignore("integer_division")
	var pct := value * 100 / gauge_max
	_gauge_text.text = "%d%%" % pct
	_gauge_label.text = "ULTIMATE READY" if full else "TEAM GAUGE"
	_gauge_label.label_settings.font_color = HudStyle.GOLD if full else HudStyle.GAUGE_FILL
	if full != _gauge_full:
		HudStyle.set_bar_color(_gauge_bar, HudStyle.GOLD if full else HudStyle.GAUGE_FILL)
		_gauge_style.border_color = HudStyle.GOLD if full else HudStyle.EDGE_DIM
		_gauge_style.set_border_width_all(GAUGE_READY_BORDER_PX if full else GAUGE_BORDER_PX)
		# _process draws the glow while full.
		_gauge_style.shadow_size = 0
	_gauge_full = full


## One enemy's framed panel (top right): name in the title font, HP bar with the numbers on it,
## status badges under it (hidden while there are none).
func _make_enemy_panel(id: int, display_name: String) -> Dictionary:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Every enemy panel as wide as the widest, so the stack reads as one column.
	panel.size_flags_horizontal = Control.SIZE_FILL
	var style := HudStyle.slant(HudStyle.INK, ENEMY_PANEL_BORDER, 2, ENEMY_PANEL_PAD, 110.0, 0.12)
	style.border_width_right = 6
	panel.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", ENEMY_PANEL_GAP)
	panel.add_child(column)
	# Name and HP numbers on one line, a slim bar under them: a short panel, so the stack stays
	# clear of the enemies' heads.
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_constant_override("separation", 14)
	column.add_child(header)
	var hp_label := HudStyle.make_number("", ENEMY_HP_SIZE)
	hp_label.size_flags_vertical = Control.SIZE_SHRINK_END
	header.add_child(hp_label)
	var name_label := HudStyle.make_title(display_name.to_upper(), ENEMY_NAME_SIZE, color_of(id).lightened(ENEMY_NAME_LIGHTEN))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)
	var bar := TrailBar.new(HudStyle.ENEMY_HP_FILL, ENEMY_BAR_HEIGHT, _visuals.hp_trail_color,
			_visuals.hp_trail_hold_ms, _visuals.hp_trail_drain_ms, _visuals.heal_fill_ms)
	bar.custom_minimum_size.x = ENEMY_BAR_WIDTH
	column.add_child(bar)
	var badges := HBoxContainer.new()
	badges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badges.alignment = BoxContainer.ALIGNMENT_END
	badges.add_theme_constant_override("separation", BADGE_GAP)
	badges.visible = false
	column.add_child(badges)
	# What it will do next: "NEXT  Sting String > CASS" and one icon per hit, spaced by time.
	var intent := HBoxContainer.new()
	intent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	intent.alignment = BoxContainer.ALIGNMENT_END
	intent.add_theme_constant_override("separation", 8)
	intent.visible = false
	column.add_child(intent)
	var next := HudStyle.make_title("NEXT", INTENT_SIZE - 4, HudStyle.LATE)
	next.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	intent.add_child(next)
	var intent_label := HudStyle.make_label("", INTENT_SIZE)
	intent_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	intent.add_child(intent_label)
	var hits := HitRowView.new()
	hits.setup(_visuals.intent_icon_px, _visuals)
	hits.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	intent.add_child(hits)
	_enemy_box.add_child(panel)
	_intent_signs[id] = {"panel": intent, "label": intent_label, "row": hits, "shown": []}
	return {"panel": panel, "bar": bar, "hp": hp_label, "badges": badges, "badge_key": ""}


## Rebuilds an enemy panel's status badges, only when what they say changed.
func _show_badges(row: Dictionary, statuses: Dictionary) -> void:
	var badges := _status_badges(statuses)
	var key := str(badges)
	if key == String(row.badge_key):
		return
	row["badge_key"] = key
	var box := row.badges as HBoxContainer
	for child: Node in box.get_children():
		box.remove_child(child)
		child.queue_free()
	for badge: Array in badges:
		box.add_child(_make_badge(String(badge[0]), String(badge[1])))
	box.visible = not badges.is_empty()


## [[status id, "SLOWED 2"], ...] from a fighter's statuses (mirror format) in Status.ALL order:
## HudStyle.status_text's words, one badge each.
static func _status_badges(statuses: Dictionary) -> Array[Array]:
	var badges: Array[Array] = []
	for id: String in Status.ALL:
		if not statuses.has(id):
			continue
		var text := String(HudStyle.STATUS_NAMES.get(id, id.to_upper()))
		var turns := int((statuses[id] as Dictionary).get("turns", 0))
		if Status.shows_count(id) and turns > 0:
			text += " %d" % turns
		badges.append([id, text])
	return badges


## A small rounded badge in the status's colour (HudStyle.STATUS_COLORS).
func _make_badge(status: String, text: String) -> PanelContainer:
	var color := HudStyle.STATUS_COLORS.get(status, HudStyle.TEXT) as Color
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.darkened(BADGE_BG_DARKEN), BADGE_BG_ALPHA)
	style.border_color = color
	style.set_border_width_all(BADGE_BORDER_PX)
	style.set_corner_radius_all(BADGE_RADIUS)
	style.content_margin_left = BADGE_PAD_X
	style.content_margin_right = BADGE_PAD_X
	style.content_margin_top = BADGE_PAD_Y
	style.content_margin_bottom = BADGE_PAD_Y
	var badge := PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_stylebox_override("panel", style)
	badge.add_child(HudStyle.make_label(text, ENEMY_STATUS_SIZE, color))
	return badge


## "Flurry  >  BRIN" (or "WHOLE PARTY") and one icon per hit spaced by time (the attack's
## rhythm), from the enemy's intent, on the enemy's panel.
func _refresh_intent_sign(id: int, mirror: CombatMirror) -> void:
	var entry: Dictionary = _intent_signs.get(id, {})
	if entry.is_empty():
		return
	var intent: Dictionary = mirror.intents.get(id, {})
	var panel := entry.panel as Control
	if intent.is_empty() or not mirror.is_alive(id) or not mirror.result.is_empty():
		panel.visible = false
		return
	var who := target_text(mirror, int(intent.get("mode", 0)), intent.get("targets", []) as Array)
	var marks: Array = intent.get("marks", [])
	(entry.label as Label).text = "%s  >  %s%s" % [String(intent.get("name", "?")), who, HudStyle.mark_text(marks)]
	var kinds: Array = intent.get("kinds", [])
	var times: Array = intent.get("times", [])
	var feints: Array = intent.get("feints", [])
	var shown := [kinds, times, feints, marks]
	if shown != entry.shown:
		entry.shown = shown
		(entry.row as HitRowView).set_hits(kinds, times, _hit_icons, feints, marks)
	panel.visible = true


## Places every live popup, newest first. Each rises popup_rise_px over its life from its spot
## (never above the ceiling). In a column, every older popup stays above every newer one with a
## small gap, pushed up as needed, so a column always reads oldest at the top and nothing
## overlaps. A popup that would be pushed past the ceiling (the attack banner, or the timeline)
## stops there and fades out quickly instead. One pass over the list: always terminates.
func _layout_popups() -> void:
	var now := Time.get_ticks_usec()
	var life := float(maxi(1, _tuning.popup_ms * 1000))
	var ceiling := _popup_ceiling()
	var placed: Array[Dictionary] = []
	var kept: Array[Dictionary] = []
	for i: int in range(_popups.size() - 1, -1, -1):
		var entry: Dictionary = _popups[i]
		if not is_instance_valid(entry.label) or (entry.label as Label).is_queued_for_deletion():
			continue
		var label := entry.label as Label
		var base: Vector2 = entry.base
		var half := label.size.y * 0.5
		var age := clampf(float(now - int(entry.born_us)) / life, 0.0, 1.0)
		var y := maxf(base.y - _visuals.popup_rise_px * (1.0 - (1.0 - age) * (1.0 - age)), ceiling + half)
		for newer: Dictionary in placed:
			if absf(float(newer.x) - base.x) < POPUP_WIDTH * POPUP_COLUMN_SHARE:
				y = minf(y, float(newer.top) - POPUP_GAP_PX - half)
		if y - half < ceiling:
			y = ceiling + half
			if not bool(entry.get("leaving", false)):
				entry["leaving"] = true
				var fade := label.create_tween()
				fade.tween_property(label, "modulate:a", 0.0, float(_tuning.popup_ms) / 1000.0 * POPUP_LEAVE_SHARE)
				fade.tween_callback(label.queue_free)
		label.position = Vector2(base.x - POPUP_WIDTH * 0.5, y - half)
		placed.append({"x": base.x, "top": y - half})
		kept.push_front(entry)
	_popups = kept


## Popups never go above this canvas y: below the screen's margin, and below the attack or TEAM
## COUNTER banner while one shows.
func _popup_ceiling() -> float:
	var ceiling := MARGIN
	if _banner.visible:
		ceiling = maxf(ceiling, _banner.get_global_rect().end.y)
	if _center_banner.visible:
		ceiling = maxf(ceiling, _center_banner.get_global_rect().end.y)
	return ceiling + POPUP_GAP_PX


func _build_end_screen() -> void:
	_end_screen = Control.new()
	_end_screen.name = "EndScreen"
	_end_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_end_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_screen.visible = false
	var dim := ColorRect.new()
	dim.color = END_DIM
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_screen.add_child(dim)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 24)
	_end_screen.add_child(column)
	_end_title = HudStyle.make_worn_title("", END_TITLE_SIZE)
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_title.add_theme_stylebox_override("normal", _band(6))
	column.add_child(_end_title)
	_end_summary = HudStyle.make_label("", END_SUMMARY_SIZE)
	_end_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_end_summary)
	_end_note = HudStyle.make_label("", END_SUMMARY_SIZE, HudStyle.TEXT_DIM)
	_end_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_end_note)
	_end_hint = HintBar.new([], END_HINT_SIZE, HudStyle.TEXT)
	column.add_child(_end_hint)
	_root.add_child(_end_screen)


## Persona 5's lock-on: four gold corner brackets around the target that snap in from wide and
## then breathe, with a bouncing chevron over the head.
class Reticle extends Control:
	const ARM_SHARE: float = 0.28
	const LINE_PX: float = 6.0
	const SNAP_S: float = 0.14
	const BREATHE_HZ: float = 1.8
	const BREATHE_PX: float = 6.0
	const CHEVRON_PX: float = 26.0

	var target: int = -1
	var frame: Rect2 = Rect2()
	var time_s: float = 0.0
	var born_s: float = 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false

	func _draw() -> void:
		if target < 0 or frame.size.x <= 0.0:
			return
		var age := clampf((time_s - born_s) / SNAP_S, 0.0, 1.0)
		var grow := (1.0 - age) * 60.0 + sin(time_s * TAU * BREATHE_HZ) * BREATHE_PX * age
		var r := frame.grow(grow)
		var arm := minf(r.size.x, r.size.y) * ARM_SHARE
		var corners := [[r.position, Vector2(1, 0), Vector2(0, 1)],
				[Vector2(r.end.x, r.position.y), Vector2(-1, 0), Vector2(0, 1)],
				[Vector2(r.position.x, r.end.y), Vector2(1, 0), Vector2(0, -1)],
				[r.end, Vector2(-1, 0), Vector2(0, -1)]]
		var gold := Color(HudStyle.GOLD, age)
		var ink := Color(0.0, 0.0, 0.0, 0.7 * age)
		for c: Array in corners:
			var p: Vector2 = c[0]
			var pts := PackedVector2Array([p + (c[1] as Vector2) * arm, p, p + (c[2] as Vector2) * arm])
			draw_polyline(pts, ink, LINE_PX + 4.0, true)
			draw_polyline(pts, gold, LINE_PX, true)
		var bob := sin(time_s * TAU * BREATHE_HZ) * 6.0
		var tip := Vector2(r.get_center().x, r.position.y - 14.0 + bob)
		var chevron := PackedVector2Array([tip, tip + Vector2(-CHEVRON_PX, -CHEVRON_PX * 0.8),
				tip + Vector2(-CHEVRON_PX * 0.45, -CHEVRON_PX * 0.8), tip + Vector2(0.0, -CHEVRON_PX * 0.35),
				tip + Vector2(CHEVRON_PX * 0.45, -CHEVRON_PX * 0.8), tip + Vector2(CHEVRON_PX, -CHEVRON_PX * 0.8)])
		draw_colored_polygon(chevron, gold)
		draw_polyline(chevron + PackedVector2Array([tip]), ink, 2.0, true)
