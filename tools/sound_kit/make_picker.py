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
    ("monsters", "New monsters and attacks", "Phase 12: the Carrion Fly, Rot Hyena and Mire Toad voices, spits, throws, shadow bolts, globs splatting and rock waves."),
    ("phase24", "Feel and atmosphere", "Phase 24: a voice of their own for the rats (they barked like a dog), thunder for storms, and the swell when your party keeps up a defence streak."),
    ("backpack", "Backpack and finds", "Picking up, putting down, turning and combining items in the backpack; finding things in zones; opening chests."),
]


PAGES = {
    "--music": dict(cands="music_candidates.json", dl="music_dl", out="picker_music", heading="Rotsworn Music Picks",
                    lede="Three free tracks for each place in the game. Each preview is the first 75 seconds; the time on each card is the full song. Pick the one that fits.",
                    group="Soundtrack", about="Every song plays at the same loudness in the game."),
    "--ambience": dict(cands="ambience_candidates.json", dl="ambience_dl", out="picker_ambience", heading="Rotsworn Ambience Picks",
                       lede="Background sounds that loop quietly under the music while you explore. Each preview is the whole loop; listen to the end, it flows back into the start.",
                       group="Zone ambience", about="Plays on the Effects volume, quietly under the music."),
}


def music(kind="--music"):
    """A listening page for songs or ambience loops: one row per slot, previews from audio/options_music."""
    import sys
    cfg = PAGES[kind]
    out = os.path.join(t.HERE, "audio", cfg["out"])
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(os.path.join(out, "s"))
    # --slots=victory,defeat: only those slots (a page for new songs only).
    slots = next((a.split("=", 1)[1].split(",") for a in sys.argv if a.startswith("--slots=")), [])
    cues = loop_cues(kind, out, slots)
    data = dict(heading=cfg["heading"], lede=cfg["lede"], groups=[dict(title=cfg["group"], about=cfg["about"], cues=cues)])
    page = open(os.path.join(t.HERE, "picker_template.html"), encoding="utf-8").read()
    page = page.replace("<title>Rotsworn Sound Picks</title>", f"<title>{cfg['heading']}</title>")
    open(os.path.join(out, "index.html"), "w", encoding="utf-8").write(
        page.replace("/*DATA*/", json.dumps(data, ensure_ascii=False).replace("</", "<\\/")))
    print(f"{out}/index.html: {len(cues)} slots")


def loop_cues(kind, out, slots):
    """The picker rows for songs or loops (`slots` only; all when empty), previews copied to out/s."""
    import subprocess
    cfg = PAGES[kind]
    c = json.load(open(os.path.join(t.HERE, cfg["cands"]), encoding="utf-8"))
    cues = []
    for slot, d in c.items():
        if slots and slot not in slots:
            continue
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
    return cues


LICENSE_NAMES = {"cc0": "CC0", "pdm": "public domain", "by": "CC BY"}


def openverse():
    """The page for openverse_fetch.py: the sound in the game now, then three Openverse finds."""
    import openverse_fetch as ov
    c = json.load(open(ov.CANDS, encoding="utf-8"))
    ss = ov.slots()
    import sys
    # --slots=a,b: a smaller page with only those slots (audio/picker_openverse_more/)
    only = next((a.split("=", 1)[1].split(",") for a in sys.argv if a.startswith("--slots=")), [])
    out = os.path.join(t.HERE, "audio", "picker_openverse_more" if only else "picker_openverse")
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(os.path.join(out, "s"))

    def ms(path):
        import subprocess
        r = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                           capture_output=True, text=True).stdout
        return int(float(r.strip() or 0) * 1000)

    by_group = {}
    for slot, d in c.items():
        if only and slot not in only:
            continue
        s, safe = ss[slot], slot.replace(":", "_")
        opts = []
        for key in ["o"] + sorted(d["options"]):
            src = os.path.join(ov.PREV, f"{safe}_{key}.mp3")
            if not os.path.exists(src):
                continue
            shutil.copy(src, os.path.join(out, "s", f"{safe}_{key}.mp3"))
            if key == "o":
                opts.append(dict(key="o", label="NOW", now=True, name="In the game now",
                                 desc="The sound Rotsworn plays today.", ms=ms(s["original"]), src=f"s/{safe}_o.mp3"))
                continue
            o = d["options"][key]
            lic = LICENSE_NAMES.get(o["license"], o["license"])
            opts.append(dict(key=key, name=o["title"], desc=f"By {o['creator']} ({lic}, {o['source']}).",
                             ms=o["ms"], src=f"s/{safe}_{key}.mp3"))
        if len(opts) < 2:
            continue
        name = slot.split(":", 1)[-1]
        by_group.setdefault(s["group"], []).append(dict(id=slot, title=s["title"], plays=s["plays"], new=False,
                                                        sharp=False, options=opts, name=name))
    order = GROUPS + [("music", "Music", "Songs. Each preview is the first minute; the time on each card is the full song."),
                      ("ambience", "Zone ambience", "Background loops under the music while you explore. Each preview is the first 40 seconds.")]
    groups = []
    for gid, title, about in order:
        if by_group.get(gid):
            groups.append(dict(title=title, about=about, cues=by_group.pop(gid)))
    for gid, cues in by_group.items():
        groups.append(dict(title=gid.title(), about="", cues=cues))
    heading = "Rotsworn Openverse Second Picks" if only else "Rotsworn Openverse Picks"
    data = dict(heading=heading, redo="None fit, search again",
                lede=("Every sound in the game. NOW is the sound Rotsworn plays today; A, B and C are free recordings "
                      "found on Openverse. Sound effect previews start at the first sound and play at the same loudness. "
                      "Pick one, or keep NOW.") if not only else
                     ("The sounds where none of the first three fit. NOW is the sound Rotsworn plays today; A, B "
                      "and C are new Openverse finds. Pick one, or keep NOW."),
                groups=groups)
    page = open(os.path.join(t.HERE, "picker_template.html"), encoding="utf-8").read()
    page = page.replace("<title>Rotsworn Sound Picks</title>", f"<title>{heading}</title>")
    open(os.path.join(out, "index.html"), "w", encoding="utf-8").write(
        page.replace("/*DATA*/", json.dumps(data, ensure_ascii=False).replace("</", "<\\/")))
    n = sum(len(g["cues"]) for g in groups)
    print(f"{out}/index.html: {n} sounds, {sum(len(x['options']) for g in groups for x in g['cues'])} files")


def main():
    import sys
    if "--openverse" in sys.argv:
        return openverse()
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
    # --with-ambience=ambience_rain,ambience_wind: those loops as one more group on the same page.
    loops = next((a.split("=", 1)[1].split(",") for a in sys.argv if a.startswith("--with-ambience=")), [])
    if loops:
        cfg = PAGES["--ambience"]
        groups.append(dict(title=cfg["group"], about=cfg["about"], cues=loop_cues("--ambience", out, loops)))
    page = open(os.path.join(t.HERE, "picker_template.html"), encoding="utf-8").read()
    extra = {}
    if only:
        extra = dict(heading=f"Rotsworn {only.title()} Picks",
                     lede="Three real recordings for each. Press play, then pick the one that fits.")
        page = page.replace("<title>Rotsworn Sound Picks</title>", f"<title>{extra['heading']}</title>")
    data = json.dumps(dict(groups=groups, **extra), ensure_ascii=False).replace("</", "<\\/")
    open(os.path.join(out, "index.html"), "w", encoding="utf-8").write(page.replace("/*DATA*/", data))
    n = sum(len(g["cues"]) for g in groups)
    print(f"{out}/index.html: {n} cues, {sum(len(c['options']) for g in groups for c in g['cues'])} sounds")


if __name__ == "__main__":
    main()
