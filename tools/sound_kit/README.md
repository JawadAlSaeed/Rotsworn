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
