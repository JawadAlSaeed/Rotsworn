class_name ZoneData
extends Resource
## One of the run's places (DESIGN.md 8.22; the walkable zones of 7.4 and 8.5 are gone, the class
## name stays): its name and map picture, the look and air its fights are fought in, the weathers
## they can have, the monsters of its Fight stops and its guard.

## Unique id used in commands and save data.
@export var id: String = ""
@export var display_name: String = ""
## Its picture on the run map (DESIGN.md 8): the place painted on the old paper.
@export_file("*.png") var map_icon_path: String = ""
## Lighting, post-processing, ground art and arena decoration of the fights fought here.
@export var look: StageLook
## What always drifts through the air here: fireflies, ash, leaves, spores, mist (DESIGN.md 8.12),
## played thinner in its fights.
@export var ambient: Array[ZoneAmbientData] = []
## The fights of a run's Fight stops in this place (DESIGN.md 8.22), and of a Fight Rush tier that
## names the place (8.21).
@export var roamer_pool: Array[EncounterData] = []
## The place's guard (a mini-boss): some of a run's Elite stops here fight it, in its deep version
## in a deep act or row (DESIGN.md 8.22).
@export var guard: EncounterData
## This place's song and its quiet background loop (wind, frogs, creaking wood; card #99). Nothing
## plays them since the walkable zones went (DESIGN.md 8.22 G6): they stay named here so a talk
## that brings them back into the place's fights still knows which belong where.
@export_file("*.wav", "*.ogg", "*.mp3") var music_path: String = ""
@export_file("*.wav", "*.ogg", "*.mp3") var ambience_path: String = ""
@export_range(-40.0, 12.0, 0.5, "suffix:dB") var ambience_volume_db: float = 0.0

@export_group("Weather")
## The weather a fight here can have (DESIGN.md 8.20, card #303), each with its weight in
## weather_weights (missing: 1), and the weight of clear weather. Picked from the run's seed for each
## fight (RunState.weather_now), so every machine online gets the same.
@export var weathers: Array[WeatherData] = []
@export var weather_weights: Array[int] = []
@export_range(0, 100) var clear_weight: int = 2
@export_group("")
