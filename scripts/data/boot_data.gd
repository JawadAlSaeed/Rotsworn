class_name BootData
extends Resource
## What plays when the game starts, before the main menu (the studio intro). Edit
## data/presentation/boot.tres; replace the video by dropping a file with the same name into
## assets/video/ (Godot plays Ogg Theora: convert with ffmpeg -c:v libtheora -c:a libvorbis).

## The intro video (empty or missing: straight to the main menu).
@export_file("*.ogv") var intro_video_path: String = ""
## Presses in the first moments are ignored (a key still held from launching the game must not
## skip the intro at once); after that any key, button or click skips it.
@export_range(0, 3000, 1, "suffix:ms") var skip_guard_ms: int = 300
## The intro's own volume relative to the master volume.
@export_range(-40.0, 6.0, 0.5, "suffix:dB") var intro_volume_db: float = 0.0
