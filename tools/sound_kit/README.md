# Sound kit: real recorded sound effects

The game's sound effects (`assets/audio/sfx/<cue>.wav`) are built from real CC0 recordings, never
synthesized. The library and its picker come from
[opus-sound-layer](https://github.com/Bodila51/opus-sound-layer) (its scripts are used as they
are, never edited).

## Set up (once per machine, needs ffmpeg and uv)

```bash
cd tools/sound_kit
git clone --depth 1 https://github.com/Bodila51/opus-sound-layer sound-layer
uv run sound-layer/scripts/sfx.py kit        # downloads about 1,100 CC0 sounds (several minutes)
```

`sound-layer/` and `audio/` are not in git (`.gdignore` keeps Godot from importing them).

## Files

- `cue_rules.json`: every cue, when it plays, and its limits (length, how fast it must start,
  loudness target). Loudness targets kept the balance of the old placeholder sounds.
- `candidates/<group>.json`: three options (a, b, c) per cue, each a list of recording layers.
- `selection.json`: the option picked for each cue.
- `build_sfx.py`: `options` renders every option to `audio/options/`; `final` renders the picks
  into `assets/audio/sfx/` and writes `assets/audio/sfx/CREDITS.md`.
- `make_picker.py` + `picker_template.html`: the listening page (audio/picker/), published as
  an Artifact; picks come back as `picks/<cue>` = {choice}.
- `volume_offset_db` in `cue_rules.json`: that cue's file is levelled this much quieter than its
  old target (a clicky recording cannot reach it), so its `volume_db` in
  `data/audio/sfx_library.tres` is that much higher.
- `check_sfx.py`: measures the results (format, length, instant start, rise, peak, loudness,
  clean ends, real sources) and draws waveform sheets. Exit 1 on any failure.

## Find a sound

```bash
uv run sound-layer/scripts/sfx.py browse --type hit --like "metal heavy" --png audio/browse.png
```

Then look at the picture it draws. Types: hit boom riser reverse transition whoosh swish glitch
ui click key tick tap pop thump paper chime shimmer zap.

## Music, ambience and voices

- `find_music.py` searches OpenGameArt (CC0 / CC-BY only); `music_candidates.json` +
  `music_selection.json` + `music_kit.py final` write `assets/audio/music/` (-16 LUFS, credits).
- `ambience_candidates.json` + `ambience_selection.json` + `ambience_kit.py final` write seamless
  CC0 loops to `assets/audio/ambience/`.
- `freesound_fetch.py search|get` finds and downloads CC0 Freesound recordings (used for the enemy
  voices in `candidates/voices.json`).
- `make_picker.py --music`, `--ambience` or `--group=voices` makes a listening page.


## Openverse pass (every sound against free finds)

```bash
python openverse_fetch.py search     # asks api.openverse.org (20 a minute, 200 a day; cached in audio/openverse/cache)
python openverse_fetch.py pick       # a, b, c per slot -> openverse_candidates.json (hand picks: openverse_overrides.json)
python openverse_fetch.py previews   # downloads and listening copies
uv run make_picker.py --openverse    # the page: NOW (keep) plus A, B, C; --slots=x,y for a smaller page
python openverse_fetch.py redo x,y   # new finds for slots marked "none fit" (words in openverse_queries_redo.json)
uv run openverse_build.py            # builds openverse_selection.json {slot: o|a|b|c} into the game, with credits
```

Slots are the cue names, `music:<song>` and `ambience:<loop>`. Only CC0, public domain and CC BY are
kept; CC BY sources also go on the credits screen (`data/branding/credits.tres`). A find from
Freesound or OpenGameArt can be added by hand to `openverse_candidates.json` (file in
`audio/openverse/dl/<id>.<filetype>`, `"locked": true`).
