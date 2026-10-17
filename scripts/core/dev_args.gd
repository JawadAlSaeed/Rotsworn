class_name DevArgs
extends RefCounted
## The command-line switches after `--` (the dev tools: --autoplay, --tuning, --seed, --encounter,
## --first-strike, --host ...). Only debug builds (the editor, run_game.bat) read them; a release
## build (build_game.bat) ignores them all, so nobody can swap the tuning or start a bot on a
## shared build.


## The user args, or none in a release build.
static func user_args() -> PackedStringArray:
	return filter(OS.get_cmdline_user_args(), OS.is_debug_build())


## `args` when `dev_allowed`, else an empty list (split out so a test can check both).
static func filter(args: PackedStringArray, dev_allowed: bool) -> PackedStringArray:
	return args if dev_allowed else PackedStringArray()
