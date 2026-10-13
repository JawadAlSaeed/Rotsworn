extends SceneTree
## Renders SVGs to PNGs with Godot's own SVG renderer (the same one the game uses). Run (after
## --import):
##   Godot --headless --path . -s tools/branding/render_svg.gd -- SCALE IN.svg OUT.png [IN2.svg OUT2.png ...]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3 or args.size() % 2 == 0:
		push_error("usage: -- SCALE IN.svg OUT.png [IN2.svg OUT2.png ...]")
		quit(1)
		return
	var scale := float(args[0])
	var failed := false
	for i: int in range(1, args.size(), 2):
		var image := Image.new()
		var err := image.load_svg_from_string(FileAccess.get_file_as_string(args[i]), scale)
		if err == OK:
			err = image.save_png(args[i + 1])
		if err != OK:
			push_error("could not render %s (error %d)" % [args[i], err])
			failed = true
		else:
			print("rendered %s (%dx%d)" % [args[i + 1].get_file(), image.get_width(), image.get_height()])
	quit(1 if failed else 0)
