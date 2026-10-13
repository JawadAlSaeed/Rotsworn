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
]


def main():
    rules, cands = t.rules(), b.all_candidates()
    out = os.path.join(t.HERE, "audio", "picker")
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(os.path.join(out, "s"))
    groups = []
    known = {g for g, _, _ in GROUPS}
    order = GROUPS + [(g, g.title(), "") for g in sorted({r["group"] for r in rules.values()} - known)]
    for gid, title, about in order:
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
    data = json.dumps(dict(groups=groups), ensure_ascii=False).replace("</", "<\\/")
    open(os.path.join(out, "index.html"), "w", encoding="utf-8").write(page.replace("/*DATA*/", data))
    n = sum(len(g["cues"]) for g in groups)
    print(f"{out}/index.html: {n} cues, {sum(len(c['options']) for g in groups for c in g['cues'])} sounds")


if __name__ == "__main__":
    main()
