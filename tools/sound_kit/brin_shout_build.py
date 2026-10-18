# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy", "scipy", "soundfile", "matplotlib"]
# ///
"""Build Brin's shout (card #171): four candidate recordings, one of them wired into the game.

  uv run brin_shout_build.py

Reads brin_shout_candidates.json ({"pick": N, "options": {"1".."4": layers like candidates/*.json}}),
renders each option like every other voice cue (cut to its first sound, faded, levelled to the
`shout_brin` loudness in cue_rules.json) into assets/audio/sfx/candidates/brin_shout_<N>.wav, and
renders the pick again as assets/audio/sfx/shout_brin.wav. Credits go to assets/audio/sfx/CREDITS.md
(the pick) and assets/audio/sfx/candidates/CREDITS.md (all four). The raw recordings stay in
audio/search/brin_shout (not in git; fetch with freesound_fetch.py get, or the page's preview
file for CC BY finds). Exits 1 when a rendered file fails the checks in check_sfx.py.
"""
import json, os, sys
import sfx_tools as t
import check_sfx
import openverse_build as ob

CANDS = os.path.join(t.HERE, "brin_shout_candidates.json")
GAME = os.path.join(t.REPO, "assets", "audio", "sfx")
OUT = os.path.join(GAME, "candidates")
CUE = "shout_brin"


def main():
    data = json.load(open(CANDS, encoding="utf-8"))
    rule = t.rules()[CUE]
    cat = t.catalog()
    bad = 0
    lines = ["# Brin's shout: candidates (card #171)", "",
             "Four short young-man battle shouts, levelled alike. `brin_shout_<N>.wav`; the one in the game is",
             f"number {data['pick']} (`../shout_brin.wav`). Built by tools/sound_kit/brin_shout_build.py.", ""]
    for key, opt in data["options"].items():
        x, _ = t.render(opt, rule["target_lu"], cat)
        t.write(os.path.join(OUT, f"brin_shout_{key}.wav"), x)
        m = t.measure(os.path.join(OUT, f"brin_shout_{key}.wav"))
        fails = [f"{n}: {d}" for n, ok, d in check_sfx.judge(m, rule) if not ok]
        print(f"{'FAIL' if fails else 'ok  '} brin_shout_{key} {m['len_ms']:.0f} ms {m['lu']:.1f} LU {opt['name']} {fails}")
        bad += bool(fails)
        lines.append(f"- **brin_shout_{key}** ({opt['name']}, {opt['license']}): {opt['layers'][0]['credit']}")
    open(os.path.join(OUT, "CREDITS.md"), "w", encoding="utf-8").write("\n".join(lines) + "\n")
    pick = data["options"][str(data["pick"])]
    x, _ = t.render(pick, rule["target_lu"], cat)
    t.write(os.path.join(GAME, CUE + ".wav"), x)
    ob.set_credit(os.path.join(GAME, "CREDITS.md"), CUE, pick["layers"][0]["credit"], [])
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
