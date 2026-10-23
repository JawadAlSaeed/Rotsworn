# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy", "soundfile"]
# ///
"""Zone ambience (card #99): CC0 field recordings from Freesound made into seamless loops.

  uv run tools/sound_kit/ambience_kit.py options
      Download every option in ambience_candidates.json, cut a seamless loop (the end crossfades
      into the start), level it, and write audio/options_music/<slot>/<a|b|c>.mp3 to listen to.
  uv run tools/sound_kit/ambience_kit.py final [--only=ambience_rain,ambience_wind]
      Write the option picked in ambience_selection.json to assets/audio/ambience/<slot>.ogg (every
      slot, or only those) and its line in CREDITS.md there (other lines stay). A loop picked through
      the Openverse pass (openverse_selection.json, openverse_build.py) is always skipped.
"""
import argparse, html, json, os, re, subprocess, sys
import numpy as np
import soundfile as sf

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
CANDIDATES = os.path.join(HERE, "ambience_candidates.json")
SELECTION = os.path.join(HERE, "ambience_selection.json")
DL = os.path.join(HERE, "audio", "ambience_dl")
PREVIEW = os.path.join(HERE, "audio", "options_music")
GAME = os.path.join(REPO, "assets", "audio", "ambience")
LOOP_S, FADE_S, START_S = 60.0, 4.0, 2.0   # loop length, crossfade, skip the recording's first seconds
LUFS = -30.0                                # quiet bed under the music and effects


def options():
    for slot, d in json.load(open(CANDIDATES, encoding="utf-8")).items():
        for key in ("a", "b", "c"):
            yield slot, key, d[key]


def _curl(url, binary=False):
    """Fetch with curl: these hosts refuse Python's own HTTP client."""
    out = subprocess.run(["curl", "-sSfL", "-A", "Mozilla/5.0", url], capture_output=True, check=True, timeout=300).stdout
    return out if binary else out.decode("utf-8")


def find(opt):
    """The sound's Freesound page: its title and HQ preview, and a check that it is CC0."""
    page = _curl(opt["page"])
    title = re.search(r"<title>(.*?)</title>", page, re.S).group(1).split(" by ")[0].replace("Freesound - ", "").strip().strip('"')
    mp3 = re.search(r"https://cdn\.freesound\.org/previews/[^\"]+-hq\.mp3", page)
    if mp3 is None or "publicdomain/zero" not in page:
        raise SystemExit(f"{opt['name']}: no CC0 preview on {opt['page']}")
    return dict(title=html.unescape(title), creator=opt["author"], foreign_landing_url=opt["page"], url=mp3.group(0), license="cc0")


def download(slot, key, opt):
    dst = os.path.join(DL, f"{slot}_{key}.mp3")
    meta = dst[:-4] + ".json"
    if not os.path.exists(dst):
        os.makedirs(DL, exist_ok=True)
        r = find(opt)
        open(dst, "wb").write(_curl(r["url"], binary=True))
        json.dump(dict(title=r["title"], creator=r["creator"], landing=r["foreign_landing_url"], license=r["license"]),
                  open(meta, "w", encoding="utf-8"))
    return dst, json.load(open(meta, encoding="utf-8"))


def seamless(src, wav):
    """A loop whose end flows into its start: the bit after the loop crossfades over its head."""
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", src, "-ac", "2", "-ar", "44100", "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    x = np.frombuffer(raw, np.float32).reshape(-1, 2).astype(np.float64)
    sr = 44100
    start = int(START_S * sr) if len(x) > (START_S + 30) * sr else 0
    x = x[start:]
    fade = int(FADE_S * sr)
    length = min(int(LOOP_S * sr), len(x) - fade)
    body = x[:length].copy()
    w = np.linspace(0.0, 1.0, fade)[:, None]
    body[:fade] = body[:fade] * np.sqrt(w) + x[length:length + fade] * np.sqrt(1.0 - w)
    sf.write(wav, body, sr, subtype="PCM_16")
    return length / sr


def encode(wav, dst, args):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", wav, "-af", f"loudnorm=I={LUFS}:TP=-3:LRA=11"] + args + [dst], check=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["options", "final"])
    # final --only=ambience_rain,ambience_wind: build only those loops (final_only never undoes a
    # loop the Openverse pass picked).
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    if a.mode == "final":
        sel = json.load(open(SELECTION, encoding="utf-8"))
        return final_only(a.only.split(",") if a.only else list(sel))
    if a.mode == "options":
        for slot, key, opt in options():
            src, meta = download(slot, key, opt)
            wav = os.path.join(DL, f"{slot}_{key}_loop.wav")
            secs = seamless(src, wav)
            encode(wav, os.path.join(PREVIEW, slot, key + ".mp3"), ["-c:a", "libmp3lame", "-b:a", "128k"])
            print(f"{slot:16s} {key} loop {secs:5.1f}s  {meta['title'][:50]}")
        return


def final_only(slots):
    """Builds the picked option of each slot in `slots` and puts its line in CREDITS.md (replaced if
    there, else added); every other loop and line stays as it is. A slot the Openverse pass picked
    (openverse_build.py owns it) is skipped: this script must never undo it."""
    sel = json.load(open(SELECTION, encoding="utf-8"))
    c = json.load(open(CANDIDATES, encoding="utf-8"))
    ov_path = os.path.join(HERE, "openverse_selection.json")
    ov = json.load(open(ov_path, encoding="utf-8")) if os.path.exists(ov_path) else {}
    skipped = [s for s in slots if ov.get("ambience:" + s, "o") != "o"]
    if skipped:
        print("skipped (picked through openverse_build.py):", ", ".join(skipped))
    path = os.path.join(GAME, "CREDITS.md")
    header = ["# Ambience credits", "", "Field recordings from Freesound, cut into seamless loops "
              "(tools/sound_kit/ambience_kit.py and openverse_build.py).", ""]
    lines = open(path, encoding="utf-8").read().rstrip("\n").split("\n") if os.path.exists(path) else header
    for slot in [s for s in slots if s not in skipped]:
        key = sel[slot]
        src, meta = download(slot, key, c[slot][key])
        wav = os.path.join(DL, f"{slot}_{key}_loop.wav")
        seamless(src, wav)
        encode(wav, os.path.join(GAME, slot + ".ogg"), ["-c:a", "libvorbis", "-q:a", "5"])
        line = f"- **{slot}.ogg**: \"{meta['title']}\" by {meta['creator']}, CC0, {meta['landing']}"
        at = next((i for i, l in enumerate(lines) if l.startswith(f"- **{slot}.ogg**")), -1)
        if at >= 0:
            lines[at] = line
        else:
            lines.append(line)
        print(f"ok {slot} <- {key}")
    open(path, "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
