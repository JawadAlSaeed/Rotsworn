class_name QuietWindow
extends RefCounted
## Quiet picture runs (card #168, DESIGN.md 10). `quiet_run.bat` starts the game from a shadow
## project whose project.godot sets Godot's `display/window/size/no_focus`, so the window opens
## without taking keyboard or mouse focus. The game reads that same setting to know it runs quiet:
## it then leaves the window exactly as the launcher placed it (second screen, fixed size) instead
## of applying the saved fullscreen / window-size choice, because maximising or fullscreening a
## window activates it and would pull focus away from whatever the owner is playing.
## No normal start sets the flag, so a normal run is never quiet.

const SETTING := "display/window/size/no_focus"


## True when this run was started by the quiet launcher.
static func active() -> bool:
	return is_quiet(ProjectSettings.get_setting(SETTING, false))


## Split out so a test can check both answers without touching the project setting.
static func is_quiet(no_focus_setting: Variant) -> bool:
	return typeof(no_focus_setting) == TYPE_BOOL and no_focus_setting
