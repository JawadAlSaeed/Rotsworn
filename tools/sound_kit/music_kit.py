# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Soundtrack: free tracks (CC0 / CC-BY) for each music slot. Needs ffmpeg.

  uv run tools/sound_kit/music_kit.py options
      Download every option in music_candidates.json (audio/music_dl/), measure it, and write a
      75 s preview per option (audio/options_music/<slot>/<a|b|c>.mp3), all at the same loudness.
  uv run tools/sound_kit/music_kit.py final
      Encode the option picked in music_selection.json for each slot ("a", or "other_slot/b") to
      assets/audio/music/<slot>.ogg (same loudness for every song) and write CREDITS.md there.
      Add --only SLOT to encode just that slot (the other songs stay as they are).
"""
import argparse, json, os, re, subprocess, sys, urllib.parse, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
CANDIDATES = os.path.join(HERE, "music_candidates.json")
SELECTION = os.path.join(HERE, "music_selection.json")
SEARCH = os.path.join(HERE, "audio", "music_search.json")
DL = os.path.join(HERE, "audio", "music_dl")
PREVIEW = os.path.join(HERE, "audio", "options_music")
GAME = os.path.join(REPO, "assets", "audio", "music")
LUFS, TRUE_PEAK = -16.0, -1.5     # every song the same loudness, so no place jumps out
PREVIEW_S, PREVIEW_FADE_S = 75, 3


def options():
    c = json.load(open(CANDIDATES, encoding="utf-8"))
    for slot, d in c.items():
        for key in ("a", "b", "c"):
            if key in d:
                yield slot, key, d[key]


def source_url(opt):
    found = json.load(open(SEARCH, encoding="utf-8")) if os.path.exists(SEARCH) else {}
    it = found.get(opt["page"])
    if it is None:   # not searched yet: read the page for its files
        page = urllib.request.urlopen(urllib.request.Request(opt["page"], headers={"User-Agent": "Mozilla/5.0"}), timeout=60).read().decode("utf-8", "replace")
        files = re.findall(r'href="(https://opengameart\.org/sites/default/files/[^"]+)"', page)
    else:
        files = it["files"]
    for f in files:
        if urllib.parse.unquote(os.path.basename(f)) == opt["file"]:
            return f
    raise SystemExit(f"{opt['name']}: file {opt['file']} not on {opt['page']}")


def download(slot, key, opt):
    ext = os.path.splitext(opt["file"])[1].lower()
    dst = os.path.join(DL, f"{slot}_{key}{ext}")
    if not os.path.exists(dst):
        os.makedirs(DL, exist_ok=True)
        req = urllib.request.Request(source_url(opt), headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=300) as r, open(dst + ".part", "wb") as fh:
            fh.write(r.read())
        os.replace(dst + ".part", dst)
    return dst


def measure(path):
    err = subprocess.run(["ffmpeg", "-hide_banner", "-i", path, "-af", "ebur128=peak=true", "-f", "null", "-"],
                         capture_output=True, text=True, encoding="utf-8", errors="replace").stderr
    dur = re.search(r"Duration: (\d+):(\d+):([\d.]+)", err)
    secs = int(dur.group(1)) * 3600 + int(dur.group(2)) * 60 + float(dur.group(3)) if dur else 0.0
    i = re.findall(r"I:\s+(-?[\d.]+) LUFS", err)
    tp = re.findall(r"Peak:\s+(-?[\d.]+) dBFS", err)
    return dict(seconds=round(secs, 1), lufs=float(i[-1]) if i else None, true_peak=float(tp[-1]) if tp else None)


def encode(src, dst, args, seconds=None):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    af = f"loudnorm=I={LUFS}:TP={TRUE_PEAK}:LRA=11"
    cmd = ["ffmpeg", "-v", "error", "-y", "-i", src]
    if seconds:
        af += f",afade=t=out:st={seconds - PREVIEW_FADE_S}:d={PREVIEW_FADE_S}"
        cmd += ["-t", str(seconds)]
    subprocess.run(cmd + ["-af", af, "-ar", "44100", "-ac", "2"] + args + [dst], check=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["options", "final"])
    ap.add_argument("--only", help="final: encode only this slot (CREDITS.md still lists every slot)")
    a = ap.parse_args()
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    if a.mode == "options":
        for slot, key, opt in options():
            src = download(slot, key, opt)
            m = measure(src)
            encode(src, os.path.join(PREVIEW, slot, key + ".mp3"), ["-c:a", "libmp3lame", "-b:a", "128k"], PREVIEW_S)
            print(f"{slot:11s} {key} {m['seconds']:6.1f}s {m['lufs']} LUFS  {opt['name']}")
        return
    sel = json.load(open(SELECTION, encoding="utf-8"))
    c = json.load(open(CANDIDATES, encoding="utf-8"))
    lines = ["# Music credits", "",
             "Free tracks from OpenGameArt.org, levelled to the same loudness (tools/sound_kit/music_kit.py).", ""]
    for slot, pick in sel.items():
        # "key" picks from the slot's own options; "other_slot/key" borrows another slot's option.
        src_slot, key = pick.split("/") if "/" in pick else (slot, pick)
        opt = c[src_slot][key]
        lines.append(f"- **{slot}.ogg**: \"{opt['name']}\" by {opt['author']}, {opt['license']}, {opt['page']}")
        if a.only and a.only != slot:
            continue
        encode(download(src_slot, key, opt), os.path.join(GAME, slot + ".ogg"), ["-c:a", "libvorbis", "-q:a", "6"])
        print(f"ok {slot} <- {key} ({opt['name']})")
    open(os.path.join(GAME, "CREDITS.md"), "w", encoding="utf-8").write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
