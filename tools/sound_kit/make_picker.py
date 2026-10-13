# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy", "scipy", "soundfile"]
# ///
"""Make the listening page: audio/picker/index.html plus audio/picker/s/<cue>_<option>.mp3.

  uv run tools/sound_kit/make_picker.py      (after build_sfx.py options)

The page is published as an Artifact; picks come back as db documents picks/<cue> = {choice}.
"""
import json, os, shutil
import sfx_tools as t
import build_sfx as b

GROUPS = [
    ("defence", "Defence", "Your answers to enemy hits. These play the instant you press, so they must start sharp."),
    ("offence", "Attacks", "Your heroes hitting enemies: strikes, skills, counters, the ultimate."),
    ("enemy", "Enemies", "Warnings and motion from enemies, so you can read an attack by ear."),
    ("state", "Heroes and effects", "Healing, buffs, AP, the team gauge, falling and getting back up."),
    ("explore", "Exploring", "Walking a zone and meeting roaming enemies."),
    ("run", "Wins and rewards", "Winning and losing fights and runs, gold, levels and loot."),
    ("ui", "Menus and fight flow", "Moving and choosing in menus, your turn, pausing, running away, calibration."),
    ("coop", "Co-op", "Friends joining, leaving and getting ready."),
    ("voices", "Enemy voices", "Each enemy's voice: it plays when the enemy starts an attack, and quieter and higher when it is hit."),
]


PAGES = {
    "--music": dict(cands="music_candidates.json", dl="music_dl", out="picker_music", heading="Rotten Lands Music Picks",
                    lede="Three free tracks for each place in the game. Each preview is the first 75 seconds; the time on each card is the full song. Pick the one that fits.",
                    group="Soundtrack", about="Every song plays at the same loudness in the game."),
    "--ambience": dict(cands="ambience_candidates.json", dl="ambience_dl", out="picker_ambience", heading="Rotten Lands Ambience Picks",
                       lede="Background sounds that loop quietly under the music while you explore. Each preview is the whole loop; listen to the end, it flows back into the start.",
                       group="Zone ambience", about="Plays on the Effects volume, quietly under the music."),
}


def music(kind="--music"):
    """A listening page for songs or ambience loops: one row per slot, previews from audio/options_music."""
    import subprocess
    cfg = PAGES[kind]
    c = json.load(open(os.path.join(t.HERE, cfg["cands"]), encoding="utf-8"))
    out = os.path.join(t.HERE, "audio", cfg["out"])
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(os.path.join(out, "s"))
    cues = []
    for slot, d in c.items():
        opts = []
        for key in ("a", "b", "c"):
            o = d[key]
            src = os.path.join(t.HERE, "audio", "options_music", slot, key + ".mp3")
            shutil.copy(src, os.path.join(out, "s", f"{slot}_{key}.mp3"))
            timed = src if kind == "--ambience" else os.path.join(t.HERE, "audio", cfg["dl"], [
                f for f in os.listdir(os.path.join(t.HERE, "audio", cfg["dl"])) if f.startswith(f"{slot}_{key}.")][0])
            err = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", timed],
                                 capture_output=True, text=True).stdout
            opts.append(dict(key=key, name=o["name"], desc=f"{o['desc']} By {o['author']} ({o.get('license', 'CC0')}).",
                             ms=int(float(err.strip() or 0) * 1000), src=f"s/{slot}_{key}.mp3"))
        cues.append(dict(id=slot, title=d["title"], plays=d["plays"], new=False, sharp=False, options=opts))
    data = dict(heading=cfg["heading"], lede=cfg["lede"], groups=[dict(title=cfg["group"], about=cfg["about"], cues=cues)])
    page = open(os.path.join(t.HERE, "picker_template.html"), encoding="utf-8").read()
    page = page.replace("<title>Rotten Lands Sound Picks</title>", f"<title>{cfg['heading']}</title>")
    open(os.path.join(out, "index.html"), "w", encoding="utf-8").write(
        page.replace("/*DATA*/", json.dumps(data, ensure_ascii=False).replace("</", "<\\/")))
    print(f"{out}/index.html: {len(cues)} slots")


def main():
    import sys
    for kind in PAGES:
        if kind in sys.argv:
            return music(kind)
    rules, cands = t.rules(), b.all_candidates()
    # --group=voices: a page with only that group (audio/picker_voices/)
    only = next((a.split("=", 1)[1] for a in sys.argv if a.startswith("--group=")), "")
    out = os.path.join(t.HERE, "audio", "picker_" + only if only else "picker")
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(os.path.join(out, "s"))
    groups = []
    known = {g for g, _, _ in GROUPS}
    order = GROUPS + [(g, g.title(), "") for g in sorted({r["group"] for r in rules.values()} - known)]
    for gid, title, about in order:
        if only and gid != only:
            continue
        cues = []
        for cue, r in rules.items():
            if r["group"] != gid or cue not in cands:
                continue
            opts = []
            for key in sorted(cands[cue]):
                o = cands[cue][key]
                src = os.path.join(b.OPTIONS_OUT, cue, key + ".mp3")
                shutil.copy(src, os.path.join(out, "s", f"{cue}_{key}.mp3"))
                m = t.measure(os.path.join(b.OPTIONS_OUT, cue, key + ".wav"))
                opts.append(dict(key=key, name=o.get("name", ""), desc=o.get("desc", ""),
                                 ms=int(round(m["len_ms"])), src=f"s/{cue}_{key}.mp3"))
            cues.append(dict(id=cue, title=r.get("title", cue), plays=r["plays"], new=r.get("new", False),
                             sharp=r["max_rise_ms"] <= 20, options=opts))
        if cues:
            groups.append(dict(title=title, about=about, cues=cues))
    page = open(os.path.join(t.HERE, "picker_template.html"), encoding="utf-8").read()
    extra = {}
    if only:
        extra = dict(heading=f"Rotten Lands {only.title()} Picks",
                     lede="Three real recordings for each. Press play, then pick the one that fits.")
        page = page.replace("<title>Rotten Lands Sound Picks</title>", f"<title>{extra['heading']}</title>")
    data = json.dumps(dict(groups=groups, **extra), ensure_ascii=False).replace("</", "<\\/")
    open(os.path.join(out, "index.html"), "w", encoding="utf-8").write(page.replace("/*DATA*/", data))
    n = sum(len(g["cues"]) for g in groups)
    print(f"{out}/index.html: {n} cues, {sum(len(c['options']) for g in groups for c in g['cues'])} sounds")


if __name__ == "__main__":
    main()
