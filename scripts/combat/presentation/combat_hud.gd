class_name CombatHud
extends CanvasLayer
## The combat HUD on the 1920x1080 canvas (DESIGN.md 7.1, restyled in card #154: slanted ink
## plates edged in worn gold). The turn order as a turn track down the left edge,
## the attack or skill banner at the top centre, a slanted panel per enemy with its HP, status
## badges and the attack it will use next (top right; the practice keys are in the F1 panel, card
## #275), party cards
## and the team gauge (with the ultimate's UNLEASH button) bottom left, the defence buttons while
## an enemy attack plays (each with the hits it answers) and the skill press while a skill plays
## (bottom right); the action menu
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
## Status icons under an enemy's bar (phase 22: icons with the turns left, HudStyle.status_chip).
const BADGE_GAP: int = 6
const PANEL_GAP: int = 14
## The defence and skill press buttons (bottom right): one slanted plate per button.
const PRESS_PLATE_SIZE: int = 24
const PRESS_CHIP_SIZE: int = 28
## The skill press plate's word (the button chip says which button).
const SKILL_PRESS_TEXT := "PRESS"

const END_TITLE_SIZE: int = 150
const END_HINT_SIZE: int = 40
const END_DIM := Color(0.0, 0.0, 0.0, 0.62)
const DEFEAT_COLOR := Color(0.9, 0.3, 0.28)
const TARGET_MARKER_SIZE: int = 40
## The arrow over a chosen or attacked fighter.
const TARGET_ARROW := "▼"
const END_SUMMARY_SIZE: int = 30
## The end screen's icon rows (phase 22): word size under an icon, gaps between chips and rows.
const END_CHIP_SIZE: int = 28
const END_CHIP_GAP: int = 22
const END_ROW_GAP: int = 18
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
## The defence streak chip over the team gauge (card #300): word and shield sizes, and its gap above
## the gauge card.
const STREAK_SIZE: int = 24
const STREAK_GLYPH_PX: float = 26.0
const STREAK_GAP_PX: float = 6.0
const STREAK_TEXT := "STREAK %d"
const ENEMY_STATUS_SIZE: int = 18
const INTENT_SIZE: int = 22
## The intent sign's hit row is never wider than this, so a long attack fits beside its name on the
## panel instead of stretching the panel and its HP bar (card #279).
const INTENT_ROW_MAX_WIDTH: float = 210.0
## The break bar under a gathering enemy's HP (card #195).
const DOOM_BAR_HEIGHT: float = 10.0
## The extra badge of a staggered enemy (its icon is mark_staggered.png, HudStyle.mark_icon).
const STAGGER_BADGE_ID := "staggered"
## A gathering Doom's line over its break bar: the turns left (card #195, phase 22).
const DOOM_TEXT := "DOOM %d"
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
## Enemy id -> {panel: PanelContainer, bar: TrailBar, hp: Label, badges: HFlowContainer (status
## icons), badge_key: String (what the badges show now)}.
var _enemy_rows: Dictionary = {}
var _party_box: HBoxContainer
var _party_panels: Dictionary = {}
var _popup_layer: Control
var _ring_layer: RingLayer
var _marker_layer: HitMarkerLayer
var _aim_layer: RangedAimLayer
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
## A won run fight's rewards and heroes as icon rows (show_end's `rewards`).
var _end_rewards: VBoxContainer
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
## The defence streak chip (card #300), floating over the gauge card: its shield and word, and the
## pop or fade playing on it.
var _streak_panel: PanelContainer
var _streak_glyph: UiGlyph
var _streak_label: Label
var _streak_tween: Tween
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
## The killing blow's impact frame (card #308): a dark hold over the scene, under the HUD.
var _impact_rect: ColorRect
var _impact_tween: Tween
var _danger: TextureRect
var _in_danger: bool = false
var _time_s: float = 0.0
## Enemy id -> the intent line on its panel: {panel: the line, label: Label, row: HitRowView,
## shown: Array (kinds and times on the row), next: the NEXT / DOOM word, doom: the Doom block,
## doom_label: Label, doom_bar: TrailBar}.
var _intent_signs: Dictionary = {}
## HitRowView.icon_key -> Texture2D.
var _hit_icons: Dictionary = {}
## The enemy panels' see-through: back during enemy attacks, full at once on a parry or counter.
var _enemy_fade := EnemyPanelsFade.new()
## A fight's intro (card #335): each enemy's name over it while the camera sweeps (id -> Label).
var _intro_names: Dictionary = {}
var _intro_tween: Tween
## A Fight stop's First Strike ring, centred over the fight (card #335).
var _ring_holder: CenterContainer


## Builds the parts that do not depend on the fighters.
func setup(view: CombatView, visuals: CombatVisuals, tuning: Tuning) -> void:
	_view = view
	_visuals = visuals
	_tuning = tuning
	layer = 10
	_enemy_fade.configure(visuals.enemy_panels_attack_alpha, visuals.enemy_panels_fade_ms,
			visuals.enemy_panels_parry_hold_ms)

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

	_impact_rect = ColorRect.new()
	_impact_rect.name = "ImpactFrame"
	_impact_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_impact_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_impact_rect.visible = false
	_root.add_child(_impact_rect)

	_ring_layer = RingLayer.new()
	_ring_layer.name = "Rings"
	_root.add_child(_ring_layer)

	_marker_layer = HitMarkerLayer.new()
	_marker_layer.name = "HitMarkers"
	_root.add_child(_marker_layer)

	_aim_layer = RangedAimLayer.new()
	_aim_layer.name = "RangedAims"
	_root.add_child(_aim_layer)

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

	_hit_icons = HitRowView.load_icons(visuals)
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

	# Top right: a framed panel per enemy (HP, statuses) and nothing under them (card #275).
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
	# The rules (a ground wave wants Jump, parrying every hit counters) are taught by the hit icons
	# on the plates and in the tutorial and Glossary, not written here (phase 22).
	_controls = _make_corner("ControlsHint", "DEFEND", HudStyle.LATE, _defend_row())
	_skill_hint = _make_corner("SkillPressHint", "", HudStyle.GOLD,
			_press_row([[&"skill_press", SKILL_PRESS_TEXT]], HudStyle.GOLD))

	action_menu = ActionMenu.new()
	action_menu.name = "ActionMenu"
	action_menu.visuals = visuals
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


## Updates every bar, panel and the timeline from the mirror. `practice_text` (the practice keys,
## "" outside practice) goes to the F1 panel, never on the fight screen itself (card #275).
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
		_show_badges(row, (f.get("statuses", {}) as Dictionary) if alive else {}, int(f.get("staggered", 0)) if alive else 0)
		_refresh_intent_sign(id, mirror)
	overlay.practice_text = practice_text
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
## `times` impacts in ms, `ranged` which are thrown), all upcoming.
func set_banner_hits(kinds: Array, times: Array, feints: Array = [], marks: Array = [], ranged: Array = []) -> void:
	_banner_row.set_hits(kinds, times, _hit_icons, feints, marks, ranged)
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


## The intent icon texture of an AttackHitData.Kind (`ranged`: the hit is thrown, card #278).
func hit_icon(kind: int, ranged: bool = false) -> Texture2D:
	return _hit_icons.get(HitRowView.icon_key(kind, ranged)) as Texture2D


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


## Shows these ranged-hit indicators (see RangedAimLayer); empty hides them all.
func set_ranged_aims(aims: Array[Dictionary]) -> void:
	_aim_layer.set_aims(aims)


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
## turn. The enemy panels step back meanwhile (card #268).
func set_defending(on: bool) -> void:
	_controls_tween = _fade_corner(_controls, on, _controls_tween)
	_enemy_fade.set_attacking(on)


## A parry or a counter: the enemy panels come back to full at once (no fade), so its effect shows
## on the HP bar straight away. `to_end` keeps them full until the attack is over (a parried last
## hit, before the counter).
func show_enemy_panels(to_end: bool = false) -> void:
	_enemy_fade.show_now(to_end)
	_enemy_box.modulate.a = _enemy_fade.alpha()


## Shows the skill press button (bottom left) while a skill's presses play, like set_defending.
func set_skill_pressing(on: bool) -> void:
	_skill_hint_tween = _fade_corner(_skill_hint, on, _skill_hint_tween)


## Big text in the middle of the screen (TEAM COUNTER) for `ms` milliseconds.
func show_center_banner(text: String, color: Color, ms: int) -> void:
	_center_banner.offset_top = _banner_top(CENTER_BANNER_TOP)
	# Over the enemy panels: a long name (a Doom's "CROWN OF ROT IN 3") used to slide under them.
	_center_banner.move_to_front()
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


## A fight's intro (card #335): `names` (enemy id -> name) show small over their enemies, fading in
## and out over intro_name_fade_ms, for `ms` in all. They follow the camera as it sweeps.
func show_intro_names(names: Dictionary, ms: int) -> void:
	hide_intro_names()
	for id: Variant in names:
		var label := HudStyle.make_label(String(names[id]), _visuals.intro_name_size, HudStyle.TEXT)
		label.label_settings = HudStyle.punch_settings(_visuals.intro_name_size, HudStyle.TEXT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.name = "IntroName%d" % int(id)
		_popup_layer.add_child(label)
		_intro_names[int(id)] = label
	_place_intro_names()
	var fade := clampf(float(_visuals.intro_name_fade_ms) / 1000.0, 0.0, float(ms) / 2000.0)
	var hold := maxf(0.0, float(ms) / 1000.0 - fade * 2.0)
	for label: Label in _intro_names.values():
		label.modulate.a = 0.0 if fade > 0.0 else 1.0
	_intro_tween = _popup_layer.create_tween().set_parallel(true)
	for label: Label in _intro_names.values():
		_intro_tween.tween_property(label, "modulate:a", 1.0, fade)
	_intro_tween.chain().tween_interval(hold)
	_intro_tween.chain().set_parallel(true)
	for label: Label in _intro_names.values():
		_intro_tween.tween_property(label, "modulate:a", 0.0, fade)
	_intro_tween.chain().tween_callback(_free_intro_names)


## The intro's names go (the intro is over, or the fight was left).
func hide_intro_names() -> void:
	if _intro_tween != null and _intro_tween.is_valid():
		_intro_tween.kill()
	_free_intro_names()


func _free_intro_names() -> void:
	_intro_tween = null
	for label: Label in _intro_names.values():
		if is_instance_valid(label):
			label.queue_free()
	_intro_names.clear()


## The intro's names showing now (tests and pictures).
func intro_names() -> Array[String]:
	var list: Array[String] = []
	for label: Label in _intro_names.values():
		list.append(label.text)
	return list


## Each intro name centred just over its enemy's head.
func _place_intro_names() -> void:
	for id: int in _intro_names:
		var label := _intro_names[id] as Label
		var rect := _fighter_rect(id)
		label.reset_size()
		label.position = Vector2(rect.get_center().x - label.size.x * 0.5, rect.position.y - label.size.y)


## A Fight stop's First Strike ring (card #335), in the middle of the fight's screen until
## hide_first_strike_ring().
func show_first_strike_ring(ring: Control) -> void:
	hide_first_strike_ring()
	_ring_holder = CenterContainer.new()
	_ring_holder.name = "FirstStrikeHolder"
	_ring_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_ring_holder)
	_ring_holder.add_child(ring)


func hide_first_strike_ring() -> void:
	if _ring_holder != null and is_instance_valid(_ring_holder):
		_ring_holder.queue_free()
	_ring_holder = null


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
	if not _intro_names.is_empty():
		_place_intro_names()
	_place_streak()
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
	_enemy_box.modulate.a = _enemy_fade.step(delta)
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


## What the action menu should not cover: each standing enemy and the enemy panels.
func _menu_avoid() -> Array[Rect2]:
	var boxes: Array[Rect2] = [_enemy_box.get_global_rect()]
	if _banner.visible:
		boxes.append(_banner.get_global_rect())
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


## The killing blow's impact frame (card #308): the scene held under `color` for `ms` (the HUD
## stays on top), then the screen flash of `flash_color` at `flash_strength`. The Flashes setting
## scales the dark frame like a flash; Off skips it (the flash follows the setting on its own).
func impact_frame(color: Color, ms: int, flash_color: Color, flash_strength: float) -> void:
	var alpha := color.a * _visuals.screen_flash_scale(PlayerSettings.flash_mode())
	if _impact_tween != null:
		_impact_tween.kill()
	if alpha <= 0.0 or ms <= 0:
		_impact_rect.visible = false
		screen_flash(flash_color, flash_strength)
		return
	_impact_rect.color = Color(color.r, color.g, color.b, alpha)
	_impact_rect.visible = true
	_impact_tween = _impact_rect.create_tween()
	_impact_tween.tween_interval(float(ms) / 1000.0)
	_impact_tween.tween_callback(_impact_rect.hide)
	_impact_tween.tween_callback(screen_flash.bind(flash_color, flash_strength))


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


## The victory or defeat screen, with a short summary of the fight (practice only; "" hides it);
## `hints` ([[action, text], ...]) say what the buttons do (the controller knows whether this is a
## test fight or a run fight) and `note` adds a line above them. `rewards` (a won run
## fight, CombatController._end_rewards) shows as icon rows: what was won, then each hero's XP.
func show_end(result: String, summary: String, hints: Array, note: String = "", rewards: Dictionary = {}) -> void:
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
	_end_summary.visible = not summary.is_empty()
	_fill_end_rewards(rewards)
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


## Rebuilds the end screen's icon rows: a row of chips (icon + word) and a row of heroes (portrait,
## "+N XP", a gold "Lv N" when they level; a downed hero greyed). Hidden when `rewards` is empty.
func _fill_end_rewards(rewards: Dictionary) -> void:
	for child: Node in _end_rewards.get_children():
		_end_rewards.remove_child(child)
		child.queue_free()
	_end_rewards.visible = not rewards.is_empty()
	var chips := HBoxContainer.new()
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	chips.add_theme_constant_override("separation", END_CHIP_GAP)
	for chip: Dictionary in rewards.get("chips", []):
		chips.add_child(_end_chip(chip.get("icon") as Texture2D, String(chip.get("text", "")),
				chip.get("color", HudStyle.TEXT) as Color))
	if chips.get_child_count() > 0:
		_end_rewards.add_child(chips)
	else:
		chips.free()
	var heroes := HBoxContainer.new()
	heroes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heroes.alignment = BoxContainer.ALIGNMENT_CENTER
	heroes.add_theme_constant_override("separation", END_CHIP_GAP * 2)
	for hero: Dictionary in rewards.get("heroes", []):
		heroes.add_child(_end_hero(hero))
	if heroes.get_child_count() > 0:
		_end_rewards.add_child(heroes)
	else:
		heroes.free()


## One reward chip: its icon (none: the word alone) and its word on a dark plate.
func _end_chip(icon: Texture2D, text: String, color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", HudStyle.panel())
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	if icon != null:
		row.add_child(_end_icon(icon, _visuals.end_icon_px))
	var label := HudStyle.make_label(text, END_CHIP_SIZE, color)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	return panel


## One hero on the end screen: the portrait, "+N XP" under it, and a gold "Lv N" when they level up.
## A downed hero's portrait is greyed out.
func _end_hero(hero: Dictionary) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	var picture := _end_icon(hero.get("portrait") as Texture2D, _visuals.end_portrait_px)
	picture.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var down := bool(hero.get("down", false))
	if down:
		picture.modulate = _visuals.end_down_tint
	box.add_child(picture)
	var xp := HudStyle.make_label(String(hero.get("text", "")), END_CHIP_SIZE, HudStyle.TEXT_DIM if down else HudStyle.TEXT)
	xp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(xp)
	var level := int(hero.get("level", 0))
	if level > 0:
		var up := HudStyle.make_title("Lv %d" % level, END_CHIP_SIZE, HudStyle.GOLD)
		up.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(up)
	return box


func _end_icon(texture: Texture2D, px: int) -> TextureRect:
	var picture := TextureRect.new()
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.texture = texture
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.custom_minimum_size = Vector2(px, px)
	return picture


## How many icon rows the end screen shows (tests).
func end_reward_rows() -> int:
	return _end_rewards.get_child_count() if _end_rewards.visible else 0


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
## in `title_color` ("" for none) and `content` (button plates) under it, right-aligned. Hidden
## until _fade_corner shows it.
func _make_corner(node_name: String, title: String, title_color: Color, content: Control) -> VBoxContainer:
	var corner := VBoxContainer.new()
	corner.name = node_name
	corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	corner.alignment = BoxContainer.ALIGNMENT_END
	corner.add_theme_constant_override("separation", 10)
	if not title.is_empty():
		var tag := PanelContainer.new()
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.size_flags_horizontal = Control.SIZE_SHRINK_END
		tag.add_theme_stylebox_override("panel", HudStyle.slant(Color(title_color.darkened(0.7), 0.94), title_color, 3, 6, 44.0))
		tag.add_child(HudStyle.make_title(title, CORNER_TITLE_SIZE + 8, title_color.lightened(0.2)))
		corner.add_child(tag)
	content.size_flags_horizontal = Control.SIZE_SHRINK_END
	corner.add_child(content)
	corner.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	corner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	corner.grow_vertical = Control.GROW_DIRECTION_BEGIN
	corner.offset_right = -MARGIN
	corner.offset_bottom = -MARGIN
	corner.visible = false
	corner.modulate.a = 0.0
	_root.add_child(corner)
	return corner


## The three defence buttons as plates stacked in the corner, each in its defence colour, with the
## hit icons it answers (DESIGN.md 3.8): Parry a normal hit or a rend, Dodge a normal hit or a
## sweep, Jump a ground wave. Stacked, not side by side: with their icons, three plates in a row
## reached over the team gauge card (owner's picture, phase 22).
func _defend_row() -> BoxContainer:
	var normal := AttackHitData.Kind.NORMAL
	return _press_row([[&"defend_parry", "PARRY", HudStyle.PARRY, [normal, AttackHitData.Kind.REND]],
			[&"defend_dodge", "DODGE", HudStyle.DODGE, [normal, AttackHitData.Kind.SWEEP]],
			[&"defend_jump", "JUMP", HudStyle.JUMP, [AttackHitData.Kind.GROUND]]], HudStyle.EDGE, true)


## A row of button plates: [[action, word, colour?, hit kinds?], ...] (colour: the word's and the
## edge's; hit kinds: the HitRowView icons drawn after the word). `stacked`: one plate under the
## other, all as wide as the widest, their icons lined up on the right.
func _press_row(entries: Array, edge: Color, stacked: bool = false) -> BoxContainer:
	var row: BoxContainer = VBoxContainer.new() if stacked else HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8 if stacked else 12)
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
		if stacked:
			word.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(word)
		var kinds: Array = entry[3] if entry.size() > 3 else []
		for kind: Variant in kinds:
			var picture := HudStyle.icon(_hit_icons.get(int(kind)) as Texture2D, _visuals.defend_hit_icon_px)
			picture.name = "Hit%d" % int(kind)
			line.add_child(picture)
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
	_build_streak()


## The defence streak chip (card #300): a shield and "STREAK n" on a small plate over the gauge card,
## hidden until the party has streak_show_from perfect defences in a row.
func _build_streak() -> void:
	_streak_panel = PanelContainer.new()
	_streak_panel.name = "DefenceStreak"
	_streak_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_streak_panel.add_theme_stylebox_override("panel", HudStyle.slant(HudStyle.INK, HudStyle.GOLD, GAUGE_BORDER_PX, 6, 40.0, 0.12))
	_streak_panel.visible = false
	_root.add_child(_streak_panel)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	_streak_panel.add_child(row)
	_streak_glyph = UiGlyph.make(&"shield", STREAK_GLYPH_PX, HudStyle.GOLD)
	_streak_glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_streak_glyph)
	_streak_label = HudStyle.make_title("", STREAK_SIZE, HudStyle.GOLD)
	_streak_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_streak_label)


## The streak changed (a defence_streak event): `value` perfect defences in a row now, `milestone`
## when it just reached a step (the gauge filled), `lost` the streak a hit just ended (else 0).
func show_streak(value: int, milestone: bool, lost: int) -> void:
	if _streak_tween != null:
		_streak_tween.kill()
	if value <= 0:
		if lost < _visuals.streak_show_from or not _streak_panel.visible:
			_streak_panel.visible = false
			return
		# A broken streak turns red, sags and fades.
		_set_streak_color(HudStyle.DAMAGE_TAKEN)
		_streak_panel.scale = Vector2.ONE
		_streak_panel.modulate = Color.WHITE
		_streak_tween = _streak_panel.create_tween()
		_streak_tween.tween_property(_streak_panel, "modulate:a", 0.0, float(_visuals.streak_lost_ms) / 1000.0) \
				.set_ease(Tween.EASE_IN)
		_streak_tween.tween_callback(_streak_panel.hide)
		return
	if value < _visuals.streak_show_from:
		_streak_panel.visible = false
		return
	_streak_label.text = STREAK_TEXT % value
	_set_streak_color(HudStyle.GOLD)
	_streak_panel.visible = true
	# In place before it is first drawn (this runs after the HUD's own _process this frame).
	_place_streak()
	_streak_panel.modulate = Color(1.8, 1.6, 1.1) if milestone else Color.WHITE
	_streak_panel.scale = Vector2.ONE * (_visuals.streak_milestone_scale if milestone else _visuals.streak_pop_scale)
	var pop_s := float(_visuals.streak_pop_ms) / 1000.0
	_streak_tween = _streak_panel.create_tween().set_parallel()
	_streak_tween.tween_property(_streak_panel, "scale", Vector2.ONE, pop_s).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_streak_tween.tween_property(_streak_panel, "modulate", Color.WHITE, pop_s * 2.0)


func _set_streak_color(color: Color) -> void:
	_streak_label.label_settings.font_color = color
	_streak_glyph.color = color
	_streak_glyph.queue_redraw()
	(_streak_panel.get_theme_stylebox("panel") as StyleBoxFlat).border_color = color


## Keeps the streak chip centred just over the gauge card (the card moves with the party row).
func _place_streak() -> void:
	if not _streak_panel.visible:
		return
	var card := _gauge_panel.get_global_rect()
	var chip := _streak_panel.get_combined_minimum_size()
	_streak_panel.size = chip
	_streak_panel.pivot_offset = chip * 0.5
	_streak_panel.global_position = Vector2(card.get_center().x - chip.x * 0.5, card.position.y - chip.y - STREAK_GAP_PX)


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
## status icons with their turns under it (hidden while there are none). Nothing on it may be wider
## than the HP bar (card #279): long words end in "...", the icons wrap onto a second line and the
## intent's hit row is capped, so every bar keeps ENEMY_BAR_WIDTH.
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
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(name_label)
	var bar := TrailBar.new(HudStyle.ENEMY_HP_FILL, ENEMY_BAR_HEIGHT, _visuals.hp_trail_color,
			_visuals.hp_trail_hold_ms, _visuals.hp_trail_drain_ms, _visuals.heal_fill_ms)
	bar.custom_minimum_size.x = ENEMY_BAR_WIDTH
	column.add_child(bar)
	var badges := HFlowContainer.new()
	badges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badges.alignment = FlowContainer.ALIGNMENT_END
	badges.add_theme_constant_override("h_separation", BADGE_GAP)
	badges.add_theme_constant_override("v_separation", BADGE_GAP)
	badges.visible = false
	column.add_child(badges)
	# A Doom being gathered (card #195): "DOOM 2" (turns left) over a bar filling toward the break.
	var doom := VBoxContainer.new()
	doom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	doom.add_theme_constant_override("separation", 2)
	doom.visible = false
	column.add_child(doom)
	var doom_label := HudStyle.make_title("", INTENT_SIZE, _visuals.doom_text_color)
	doom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	doom_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	doom_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	doom.add_child(doom_label)
	var doom_bar := TrailBar.new(_visuals.break_bar_color, DOOM_BAR_HEIGHT, _visuals.hp_trail_color,
			_visuals.hp_trail_hold_ms, _visuals.hp_trail_drain_ms, _visuals.heal_fill_ms)
	doom_bar.custom_minimum_size.x = ENEMY_BAR_WIDTH
	doom.add_child(doom_bar)
	# What it will do next: "NEXT  Sting String > CASS" and one icon per hit, spaced by time (a
	# marking hit wears its mark's icon).
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
	intent_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	intent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	intent_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	intent.add_child(intent_label)
	var hits := HitRowView.new()
	hits.max_width_px = INTENT_ROW_MAX_WIDTH
	hits.setup(_visuals.intent_icon_px, _visuals)
	hits.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	intent.add_child(hits)
	_enemy_box.add_child(panel)
	_intent_signs[id] = {"panel": intent, "label": intent_label, "row": hits, "shown": [], "next": next,
			"doom": doom, "doom_label": doom_label, "doom_bar": doom_bar}
	return {"panel": panel, "bar": bar, "hp": hp_label, "badges": badges, "badge_key": ""}


## Rebuilds an enemy panel's status icons, only when what they say changed.
func _show_badges(row: Dictionary, statuses: Dictionary, staggered: int = 0) -> void:
	var badges := enemy_badges(statuses, staggered)
	var key := str(badges)
	if key == String(row.badge_key):
		return
	row["badge_key"] = key
	var box := row.badges as HFlowContainer
	for child: Node in box.get_children():
		box.remove_child(child)
		child.free()
	for badge: Array in badges:
		var id := String(badge[0])
		var color := _visuals.stagger_text_color if id == STAGGER_BADGE_ID else Color(0.0, 0.0, 0.0, 0.0)
		box.add_child(HudStyle.status_chip(id, int(badge[1]), _visuals.status_icon_px, ENEMY_STATUS_SIZE, color))
	box.visible = not badges.is_empty()


## [[status id, turns], ...] an enemy panel draws as icons (phase 22): its statuses
## (HudStyle.status_badges; turns 0 when the status shows no count), then the stagger with its turns.
static func enemy_badges(statuses: Dictionary, staggered: int = 0) -> Array[Array]:
	var badges := HudStyle.status_badges(statuses)
	if staggered > 0:
		badges.append([STAGGER_BADGE_ID, staggered])
	return badges


## "Flurry  >  BRIN" (or "WHOLE PARTY") and one icon per hit spaced by time (the attack's
## rhythm), from the enemy's intent, on the enemy's panel. The marks its hits leave are icons on
## those hits (HitRowView), not words (phase 22).
func _refresh_intent_sign(id: int, mirror: CombatMirror) -> void:
	var entry: Dictionary = _intent_signs.get(id, {})
	if entry.is_empty():
		return
	var intent: Dictionary = mirror.intents.get(id, {})
	var panel := entry.panel as Control
	_refresh_doom_sign(entry, id, mirror)
	if intent.is_empty() or not mirror.is_alive(id) or not mirror.result.is_empty():
		panel.visible = false
		return
	var who := target_text(mirror, int(intent.get("mode", 0)), intent.get("targets", []) as Array)
	var marks: Array = intent.get("marks", [])
	(entry.label as Label).text = intent_text(String(intent.get("name", "?")), who)
	var kinds: Array = intent.get("kinds", [])
	var times: Array = intent.get("times", [])
	var feints: Array = intent.get("feints", [])
	var ranged: Array = intent.get("ranged", [])
	var shown := [kinds, times, feints, marks, ranged]
	if shown != entry.shown:
		entry.shown = shown
		(entry.row as HitRowView).set_hits(kinds, times, _hit_icons, feints, marks, ranged)
	panel.visible = true


## The intent sign's words: the attack's name and who it is aimed at ("Sting String  >  CASS").
static func intent_text(attack_name: String, who: String) -> String:
	return "%s  >  %s" % [attack_name, who]


## The Doom block of an enemy's panel (card #195): "DOOM 2" (its turns left) over a bar that fills
## as the party deals damage toward the break (phase 22: no break numbers); hidden unless the enemy
## is gathering a Doom. The NEXT word turns into DOOM.
func _refresh_doom_sign(entry: Dictionary, id: int, mirror: CombatMirror) -> void:
	var next := entry.next as Label
	var charging := mirror.result.is_empty() and mirror.is_charging(id)
	(entry.doom as Control).visible = charging
	next.text = "DOOM" if charging else "NEXT"
	next.label_settings.font_color = _visuals.doom_text_color if charging else HudStyle.LATE
	if not charging:
		return
	var f := mirror.fighter(id)
	var left := int(f.charge_left)
	(entry.doom_label as Label).text = DOOM_TEXT % left
	(entry.doom_bar as TrailBar).set_values(int(f.charge_damage), int(f.break_hp))


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
	_end_rewards = VBoxContainer.new()
	_end_rewards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_end_rewards.add_theme_constant_override("separation", END_ROW_GAP)
	_end_rewards.visible = false
	column.add_child(_end_rewards)
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
