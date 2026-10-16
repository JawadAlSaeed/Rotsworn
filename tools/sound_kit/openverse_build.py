# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy", "scipy", "soundfile"]
# ///
"""Build the Openverse picks into the game.

  uv run openverse_build.py      reads openverse_selection.json {slot: "o" | "a" | "b" | "c"}

"o" keeps the sound the game has now. A sound effect pick is cut to start at its first sound,
trimmed to the cue's longest length and levelled to the cue's loudness target (cue_rules.json),
like every other effect, so its volume_db in data/audio/sfx_library.tres stays right. A song is
levelled like music_kit.py; an ambience loop is made seamless like ambience_kit.py. Credits go
into the CREDITS.md next to the files (CC BY needs one; CC0 gets one anyway).
"""
import json, os, re, subprocess, sys
import sfx_tools as t
import music_kit
import ambience_kit
import openverse_fetch as ov

SELECTION = os.path.join(t.HERE, "openverse_selection.json")
WAV = os.path.join(ov.OUT, "wav")
LICENSES = {"cc0": "CC0", "pdm": "public domain", "by": "CC BY"}


def credit(o):
    lic = LICENSES.get(o["license"], o["license"])
    if o["license"] == "by" and o.get("license_version"):
        lic += " " + o["license_version"]
    where = "" if o.get("source") == "opengameart" else " (found on Openverse)"
    return f"\"{o['title']}\" by {o['creator']}, {lic}, {o['page'] or o['url']}{where}"


def set_credit(path, name, text, header):
    """Replace (or add) the '- **name**: ...' line in a CREDITS.md."""
    lines = open(path, encoding="utf-8").read().splitlines() if os.path.exists(path) else header
    line = f"- **{name}**: {text}"
    for i, l in enumerate(lines):
        if l.startswith(f"- **{name}**:"):
            lines[i] = line
            break
    else:
        lines.append(line)
    open(path, "w", encoding="utf-8").write("\n".join(lines) + "\n")


def main():
    sel = json.load(open(SELECTION, encoding="utf-8"))
    cands = json.load(open(ov.CANDS, encoding="utf-8"))
    slots, rules = ov.slots(), t.rules()
    os.makedirs(WAV, exist_ok=True)
    bad = 0
    for slot, key in sel.items():
        if key not in ("a", "b", "c"):
            continue
        o = cands[slot]["options"][key]
        raw = os.path.join(ov.DL, f"{o['id']}.{o['filetype']}")
        if not os.path.exists(raw):
            print(f"FAIL {slot}: {raw} missing (run openverse_fetch.py previews)"); bad += 1; continue
        s = slots[slot]
        kind, name = s["kind"], slot.split(":", 1)[-1]
        if kind == "sfx":
            wav = os.path.join(WAV, o["id"] + ".wav")
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", raw, "-ac", "1", "-ar", "48000", wav], check=True)
            r = rules[name]
            x, _ = t.render(dict(layers=[dict(sound=wav, highpass_hz=30)], len_ms=r["max_ms"],
                                 fade_ms=max(40, min(200, r["max_ms"] // 5))),   # a long find cut short fades out softly
                            r["target_lu"], t.catalog())
            t.write(os.path.join(t.REPO, "assets", "audio", "sfx", name + ".wav"), x)
            set_credit(os.path.join(t.REPO, "assets", "audio", "sfx", "CREDITS.md"), name, credit(o), [])
        elif kind == "music":
            dst = os.path.join(music_kit.GAME, name + ".ogg")
            music_kit.encode(raw, dst, ["-c:a", "libvorbis", "-q:a", "6"])
            set_credit(os.path.join(music_kit.GAME, "CREDITS.md"), name + ".ogg", credit(o), [])
        else:
            wav = os.path.join(WAV, o["id"] + "_loop.wav")
            ambience_kit.seamless(raw, wav)
            ambience_kit.encode(wav, os.path.join(ambience_kit.GAME, name + ".ogg"), ["-c:a", "libvorbis", "-q:a", "5"])
            set_credit(os.path.join(ambience_kit.GAME, "CREDITS.md"), name + ".ogg", credit(o), [])
        print(f"ok   {slot} <- {key} ({o['title']}, {o['license']})")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
