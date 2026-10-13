class_name MusicSet
extends Resource
## Which song plays where (menus, run screens, zones, fights, the boss). The Audio autoload loops the
## song; a place that names the song already playing lets it go on without restarting. An empty
## path means silence there. Edit data/audio/music.tres; drop new songs into assets/audio/music/.

## Title screen and menus (the main theme, card #84).
@export_file("*.wav", "*.ogg", "*.mp3") var menu_path: String = ""
## Run screens: map, shop, rest, loot, party, run end. Empty: the menu song.
@export_file("*.wav", "*.ogg", "*.mp3") var run_path: String = ""
## Zones without a song of their own (ZoneData.music_path).
@export_file("*.wav", "*.ogg", "*.mp3") var zone_path: String = ""
@export_file("*.wav", "*.ogg", "*.mp3") var fight_path: String = ""
## Boss fights. Empty: the fight song.
@export_file("*.wav", "*.ogg", "*.mp3") var boss_path: String = ""
## The boss fight once the boss rages (its phase change, card #97). Empty: the boss song goes on.
@export_file("*.wav", "*.ogg", "*.mp3") var boss_rage_path: String = ""
## A new song fades in over this long while the old one fades out (a crossfade between places).
@export_range(0, 10000, 10, "suffix:ms") var fade_in_ms: int = 1500
@export_range(0, 10000, 10, "suffix:ms") var fade_out_ms: int = 1000
## Music volume, relative to the master volume (sound effects stay at their own levels).
@export_range(-40.0, 6.0, 0.5, "suffix:dB") var volume_db: float = -8.0
