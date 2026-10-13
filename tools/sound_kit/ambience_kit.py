# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy", "soundfile"]
# ///
"""Zone ambience (card #99): CC0 field recordings from Freesound made into seamless loops.

  uv run tools/sound_kit/ambience_kit.py options
      Download every option in ambience_candidates.json, cut a seamless loop (the end crossfades
      into the start), level it, and write audio/options_music/<slot>/<a|b|c>.mp3 to listen to.
  uv run tools/sound_kit/ambience_kit.py final
      Write the option picked in ambience_selection.json to assets/audio/ambience/<slot>.ogg and
      CREDITS.md there.
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
    a = ap.parse_args()
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    if a.mode == "options":
        for slot, key, opt in options():
            src, meta = download(slot, key, opt)
            wav = os.path.join(DL, f"{slot}_{key}_loop.wav")
            secs = seamless(src, wav)
            encode(wav, os.path.join(PREVIEW, slot, key + ".mp3"), ["-c:a", "libmp3lame", "-b:a", "128k"])
            print(f"{slot:16s} {key} loop {secs:5.1f}s  {meta['title'][:50]}")
        return
    sel = json.load(open(SELECTION, encoding="utf-8"))
    c = json.load(open(CANDIDATES, encoding="utf-8"))
    lines = ["# Ambience credits", "", "CC0 field recordings from Freesound, cut into seamless loops "
             "(tools/sound_kit/ambience_kit.py). Credit is not required but given.", ""]
    for slot, key in sel.items():
        src, meta = download(slot, key, c[slot][key])
        wav = os.path.join(DL, f"{slot}_{key}_loop.wav")
        seamless(src, wav)
        encode(wav, os.path.join(GAME, slot + ".ogg"), ["-c:a", "libvorbis", "-q:a", "5"])
        lines.append(f"- **{slot}.ogg**: \"{meta['title']}\" by {meta['creator']}, CC0, {meta['landing']}")
        print(f"ok {slot} <- {key}")
    open(os.path.join(GAME, "CREDITS.md"), "w", encoding="utf-8").write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
