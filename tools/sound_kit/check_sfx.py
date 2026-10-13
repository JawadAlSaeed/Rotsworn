# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy", "scipy", "soundfile", "matplotlib"]
# ///
"""Check sound effects by measurement, because nobody here can hear them. Exit 1 on any FAIL.

  uv run tools/sound_kit/check_sfx.py options [--only parry,dodge]
      Checks audio/options/<cue>/<a|b|c>.wav and draws audio/options/<cue>/sheet.png.
  uv run tools/sound_kit/check_sfx.py final
      Checks assets/audio/sfx/<cue>.wav for every cue in selection.json.

Checks (limits per cue in cue_rules.json; never loosen one to make a check pass):
  format    44.1 kHz, mono, 16-bit PCM (what the game imports)
  length    between the cue's min_ms and max_ms
  start     sound within 1 ms of the file start (the game plays a cue at the moment it happens)
  rise      start to loudest point within the cue's max_rise_ms
  peak      sample peak at or under -1 dBFS
  loudness  loudest 100 ms (K-weighted) within 1.5 LU of the cue's target_lu
  ends      no click: first 0.2 ms under -30 dBFS, last 5 ms under -45 dBFS; DC under 0.005
  source    every layer is a kit recording or a credited file, never synthesized
  build     (peak_at_end cues) loudest point in the last 30% of the sound
  distinct  (options) the three options of a cue use different main recordings
"""
import argparse, json, os, sys
import numpy as np
import sfx_tools as t
import build_sfx as b


def judge(m, r):
    res = []
    def add(name, ok, detail):
        res.append((name, ok, detail))
    add("format", m["rate"] == t.OUT_SR and m["channels"] == 1 and m["subtype"] == "PCM_16",
        f"{m['rate']} Hz, {m['channels']} ch, {m['subtype']}")
    add("length", r["min_ms"] <= m["len_ms"] <= r["max_ms"], f"{m['len_ms']:.0f} ms (allowed {r['min_ms']}-{r['max_ms']})")
    add("start", m["onset_ms"] <= 1.0, f"{m['onset_ms']:.2f} ms")
    add("rise", m["rise_ms"] <= r["max_rise_ms"], f"{m['rise_ms']:.1f} ms (max {r['max_rise_ms']})")
    if r.get("peak_at_end"):   # a build-up: its loudest point must come in its last 30%
        add("build", m["rise_ms"] >= 0.7 * m["len_ms"], f"loudest at {m['rise_ms']:.0f} of {m['len_ms']:.0f} ms (needs the last 30%)")
    add("peak", m["peak_db"] <= t.CEILING_DB + 0.01, f"{m['peak_db']:.2f} dBFS")
    add("loudness", abs(m["lu"] - r["target_lu"]) <= 1.5, f"{m['lu']:.1f} (target {r['target_lu']})")
    add("ends", m["head_db"] <= -30 and m["tail_db"] <= -45 and abs(m["dc"]) < 0.005,
        f"head {m['head_db']:.0f} dBFS, tail {m['tail_db']:.0f} dBFS, dc {m['dc']:.4f}")
    return res


def sources_ok(opt, cat):
    for layer in opt.get("layers", []):
        s = layer.get("sound", "")
        if s.startswith("synth:"):
            return False, f"{s} is synthesized"
        if s not in cat and not layer.get("credit"):
            return False, f"{s} is not in the kit and has no credit"
    return bool(opt.get("layers")), "recordings only"


def sheet(rows, png):
    import matplotlib; matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig, axes = plt.subplots(len(rows), 2, figsize=(12, 1.6 * len(rows) + 0.4), squeeze=False,
                             gridspec_kw=dict(width_ratios=[1, 2]))
    for row, (label, path, m) in zip(axes, rows):
        x = t.load(path)
        tt = np.arange(len(x)) / t.SR * 1000.0
        row[0].plot(tt, x, lw=0.5, color="k"); row[0].set_xlim(0, max(tt[-1], 1)); row[0].set_ylim(-1, 1)
        row[0].axvline(m["onset_ms"] + m["rise_ms"], color="tab:red", lw=0.7)
        row[0].set_title(label, fontsize=7, loc="left"); row[0].tick_params(labelsize=6)
        row[1].specgram(x, NFFT=512, Fs=t.SR, noverlap=384, cmap="magma", vmin=-120)
        row[1].set_ylim(0, 12000); row[1].set_yticks([150, 2000, 6000, 12000]); row[1].tick_params(labelsize=6)
        row[1].set_title(f"{m['len_ms']:.0f} ms  rise {m['rise_ms']:.0f} ms  peak {m['peak_db']:.1f} dBFS  loud {m['lu']:.1f}",
                         fontsize=7, loc="left")
    fig.tight_layout(); fig.savefig(png, dpi=90); plt.close(fig)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["options", "final"])
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    only = {s for s in a.only.split(",") if s}
    rules, cat, cands = t.rules(), t.catalog(), b.all_candidates()
    fails = 0

    def report(label, res):
        nonlocal fails
        bad = [r for r in res if not r[1]]
        fails += len(bad)
        print(f"{'FAIL' if bad else 'pass'} {label}: " + "; ".join(f"{n} {d}" for n, ok, d in res if not ok or n in ("length", "rise", "loudness")))

    if a.mode == "options":
        for cue, opts in cands.items():
            if only and cue not in only:
                continue
            r = rules.get(cue)
            if r is None:
                print(f"FAIL {cue}: no entry in cue_rules.json"); fails += 1; continue
            rows = []
            for key, opt in opts.items():
                p = os.path.join(b.OPTIONS_OUT, cue, key + ".wav")
                if not os.path.exists(p):
                    print(f"FAIL {cue}/{key}: not built"); fails += 1; continue
                m = t.measure(p)
                ok, why = sources_ok(opt, cat)
                report(f"{cue}/{key}", judge(m, r) + [("source", ok, why)])
                rows.append((f"{cue}/{key}: {opt.get('name', '')}", p, m))
            mains = [o["layers"][0]["sound"] for o in opts.values() if o.get("layers")]
            if len(opts) != 3 or len(set(mains)) != len(mains):
                print(f"FAIL {cue}: needs 3 options with different main recordings ({mains})"); fails += 1
            if rows:
                sheet(rows, os.path.join(b.OPTIONS_OUT, cue, "sheet.png"))
    else:
        sel = json.load(open(b.SELECTION, encoding="utf-8"))
        for cue, key in sel.items():
            if only and cue not in only:
                continue
            p = os.path.join(b.GAME_SFX, cue + ".wav")
            if not os.path.exists(p):
                print(f"FAIL {cue}: {p} missing"); fails += 1; continue
            ok, why = sources_ok(cands.get(cue, {}).get(key, {}), cat)
            report(cue, judge(t.measure(p), rules[cue]) + [("source", ok, why)])
    print(f"\n{'PASSED' if not fails else 'FAILED'}: {fails} failed checks")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
