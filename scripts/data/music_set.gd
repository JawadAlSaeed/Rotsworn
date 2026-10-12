class_name MusicSet
extends Resource
## Which song plays where (menus and run screens, zones, fights). The Audio autoload loops the
## song; a place that names the song already playing lets it go on without restarting. An empty
## path means silence there. Edit data/audio/music.tres; drop new songs into assets/audio/music/.

@export_file("*.wav", "*.ogg", "*.mp3") var menu_path: String = ""
@export_file("*.wav", "*.ogg", "*.mp3") var zone_path: String = ""
@export_file("*.wav", "*.ogg", "*.mp3") var fight_path: String = ""
## Music volume, relative to the master volume (sound effects stay at their own levels).
@export_range(-40.0, 6.0, 0.5, "suffix:dB") var volume_db: float = -8.0
