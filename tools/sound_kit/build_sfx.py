# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy", "scipy", "soundfile"]
# ///
"""Build the game's sound effects from real recordings (the sound-layer CC0 kit in audio/kit).

  uv run tools/sound_kit/build_sfx.py options [--only parry,dodge]
      Render every option in candidates/*.json to audio/options/<cue>/<a|b|c>.wav (+ .mp3 to
      listen to in a browser).
  uv run tools/sound_kit/build_sfx.py final
      Render the option chosen in selection.json for each cue to assets/audio/sfx/<cue>.wav
      and write assets/audio/sfx/CREDITS.md.

A cue option is a list of layers. Layer fields: sound (kit id such as "hit/fs-198113-clang-4-1",
or a file under tools/sound_kit with "credit"), gain_db, at_ms (where its start lands), start_ms
and len_ms (which part of the recording), pitch (semitones, by playback speed), highpass_hz,
lowpass_hz. Option fields: name, layers, len_ms, fade_ms, note. Loudness targets and limits come
from cue_rules.json. Check the result with check_sfx.py.
"""
import argparse, glob, json, os, subprocess, sys
import sfx_tools as t

CANDIDATES = os.path.join(t.HERE, "candidates")
SELECTION = os.path.join(t.HERE, "selection.json")
OPTIONS_OUT = os.path.join(t.HERE, "audio", "options")
GAME_SFX = os.path.join(t.REPO, "assets", "audio", "sfx")


def all_candidates():
    out = {}
    for f in sorted(glob.glob(os.path.join(CANDIDATES, "*.json"))):
        try:
            data = json.load(open(f, encoding="utf-8"))
        except (OSError, ValueError) as ex:   # a file being written by someone else: skip it, say so
            print(f"warning: skipped {os.path.basename(f)}: {ex}", file=sys.stderr)
            continue
        for cue, opts in data.items():
            if cue in out:
                sys.exit(f"cue '{cue}' is in two candidate files")
            out[cue] = opts
    return out


def mp3(wav):
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", wav, "-c:a", "libmp3lame", "-b:a", "192k",
                    wav[:-4] + ".mp3"], check=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["options", "final"])
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    only = {s for s in a.only.split(",") if s}
    rules, cat, cands = t.rules(), t.catalog(), all_candidates()
    bad = 0
    if a.mode == "options":
        for cue, opts in cands.items():
            if only and cue not in only:
                continue
            if cue not in rules:
                print(f"FAIL {cue}: no entry in cue_rules.json"); bad += 1; continue
            for key, opt in opts.items():
                try:
                    x, _ = t.render(opt, rules[cue]["target_lu"], cat)
                except Exception as ex:
                    print(f"FAIL {cue}/{key}: {ex}"); bad += 1; continue
                p = os.path.join(OPTIONS_OUT, cue, key + ".wav")
                t.write(p, x); mp3(p)
                print(f"ok   {cue}/{key}  {len(x) / t.OUT_SR * 1000:.0f} ms  {opt.get('name', '')}")
    else:
        sel = json.load(open(SELECTION, encoding="utf-8"))
        credits = t.kit_credits()
        lines = ["# Sound effect credits", "",
                 "Every sound effect here is built from real recordings (cut, pitched, layered and",
                 "levelled by tools/sound_kit/build_sfx.py). All sources are CC0 (public domain):",
                 "credit is not required but given.", ""]
        for cue, key in sel.items():
            if only and cue not in only:
                continue
            opt = cands.get(cue, {}).get(key)
            if opt is None:
                print(f"FAIL {cue}: option '{key}' not found"); bad += 1; continue
            x, _ = t.render(opt, rules[cue]["target_lu"], cat)
            t.write(os.path.join(GAME_SFX, cue + ".wav"), x)
            print(f"ok   {cue} <- {key} ({opt.get('name', '')})")
            src = []
            for layer in opt["layers"]:
                s = layer["sound"]
                src.append(f"{s} ({credits.get(s) or layer.get('credit') or 'NO CREDIT'})")
            lines.append(f"- **{cue}**: " + "; ".join(src))
        if not only:
            open(os.path.join(GAME_SFX, "CREDITS.md"), "w", encoding="utf-8").write("\n".join(lines) + "\n")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
