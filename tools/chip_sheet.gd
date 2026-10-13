extends SceneTree
## Dev tool: draws every button chip (HudStyle.button_chip: pad buttons and keyboard keys, at a
## few hint sizes) and saves a picture plus each chip's rectangle, to check by eye or by script
## that every label sits in the middle of its button. Needs a window (not headless):
##   godot --path . -s tools/chip_sheet.gd
## Writes user://shots/chips/chips.png and chips.json.

const OUT_DIR := "user://shots/chips"
const SIZES: Array[int] = [24, 26, 40, 64]
const PAD_BUTTONS: Array[String] = ["A", "B", "X", "Y", "LB", "RB", "Menu", "View", "LS", "RS", "L-stick",
		"D-pad ↑↓", "D-pad ←→", "D-pad", "D-pad up", "Guide"]
const KEYS: Array[String] = ["Space", "Shift", "W", "E", "Q", "J", "F1", "Enter", "Backspace", "Escape", "Tab", "WASD",
		"↑↓", "←→"]

var _frames: int = 0
var _chips: Array[Dictionary] = []
var _root_ctl: Control


func _initialize() -> void:
	HudStyle.load_fonts()
	_root_ctl = Control.new()
	_root_ctl.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_ctl.add_child(bg)
	var column := VBoxContainer.new()
	column.position = Vector2(30, 30)
	column.custom_minimum_size.x = 1840.0
	column.add_theme_constant_override("separation", 14)
	_root_ctl.add_child(column)
	for font_size: int in SIZES:
		for pad: bool in [true, false]:
			var row := HFlowContainer.new()
			row.add_theme_constant_override("h_separation", 22)
			row.add_theme_constant_override("v_separation", 12)
			column.add_child(row)
			for button: String in (PAD_BUTTONS if pad else KEYS):
				var chip := HudStyle.button_chip(button, pad, font_size)
				row.add_child(chip)
				_chips.append({"chip": chip, "text": button, "pad": pad, "size": font_size})
	root.add_child(_root_ctl)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 6:
		return false
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var image := root.get_texture().get_image()
	image.save_png(OUT_DIR + "/chips.png")
	var visible := root.get_visible_rect().size
	var list: Array = []
	for entry: Dictionary in _chips:
		var chip := entry.chip as ButtonChip
		var r := chip.get_global_rect()
		list.append({"text": entry.text, "pad": entry.pad, "size": entry.size, "shape": int(chip.shape),
				"chip": [r.position.x, r.position.y, r.size.x, r.size.y],
				"text_color": chip.text_color().to_html(false)})
	var file := FileAccess.open(OUT_DIR + "/chips.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"image": [image.get_width(), image.get_height()],
			"canvas": [visible.x, visible.y], "chips": list}, "  "))
	file.close()
	print("Chips: %d saved to %s" % [list.size(), ProjectSettings.globalize_path(OUT_DIR)])
	return true
