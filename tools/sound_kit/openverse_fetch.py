"""Find three free Openverse recordings for every game sound and make listening previews.

  python openverse_fetch.py search     ask api.openverse.org (cached in audio/openverse/cache/)
  python openverse_fetch.py pick       choose a, b, c per slot -> openverse_candidates.json
  python openverse_fetch.py previews   download the picks and write audio/openverse/previews/
  python openverse_fetch.py redo a,b   new finds for slots marked "none fit" (words in
                                       openverse_queries_redo.json); every other slot is kept

Slots: every cue in assets/audio/sfx, "music:<song>" and "ambience:<loop>". Search words live in
openverse_queries.json (first words first; later words only when the first find too little).
Only CC0, public domain and CC BY recordings are kept, so the game can use them freely (CC BY
needs a credit line, written when a pick is built into the game).
The anonymous API allows 20 searches a minute and 200 a day, so searches are spaced and cached.
"""
import json, os, subprocess, sys, time, urllib.parse, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(HERE, "audio", "openverse")
CACHE, DL, PREV = (os.path.join(OUT, d) for d in ("cache", "dl", "previews"))
API = "https://api.openverse.org/v1/audio/"
UA = "Rotsworn-sound-kit/1.0 (https://github.com/JawadAlSaeed/Rotsworn)"
LICENSES = "cc0,by,pdm"
CANDS = os.path.join(HERE, "openverse_candidates.json")
OVERRIDES = os.path.join(HERE, "openverse_overrides.json")   # slot -> title starts picked by hand


def slots():
    """slot -> dict(kind, original file, length limits in ms)."""
    rules = json.load(open(os.path.join(HERE, "cue_rules.json"), encoding="utf-8"))
    out = {}
    sfx = os.path.join(ROOT, "assets", "audio", "sfx")
    for f in sorted(os.listdir(sfx)):
        if f.endswith(".wav"):
            cue = f[:-4]
            r = rules.get(cue, {})
            out[cue] = dict(kind="sfx", original=os.path.join(sfx, f), min_ms=r.get("min_ms", 50),
                            max_ms=r.get("max_ms", 2000), title=r.get("title", cue), plays=r.get("plays", ""),
                            group=r.get("group", "other"))
    music = json.load(open(os.path.join(HERE, "music_candidates.json"), encoding="utf-8"))
    for f in sorted(os.listdir(os.path.join(ROOT, "assets", "audio", "music"))):
        if f.endswith(".ogg"):
            s = f[:-4]
            m = music.get(s, {})
            short = s in ("victory", "defeat")
            out["music:" + s] = dict(kind="music", original=os.path.join(ROOT, "assets", "audio", "music", f),
                                     min_ms=15000 if short else 60000, max_ms=180000 if short else 600000,
                                     title=m.get("title", "Credits" if s == "credits" else s),
                                     plays=m.get("plays", "the credits screen" if s == "credits" else ""), group="music")
    amb = json.load(open(os.path.join(HERE, "ambience_candidates.json"), encoding="utf-8"))
    for f in sorted(os.listdir(os.path.join(ROOT, "assets", "audio", "ambience"))):
        if f.endswith(".ogg"):
            s = f[:-4]
            out["ambience:" + s] = dict(kind="ambience", original=os.path.join(ROOT, "assets", "audio", "ambience", f),
                                        min_ms=30000, max_ms=900000, title=amb.get(s, {}).get("title", s),
                                        plays=amb.get(s, {}).get("plays", ""), group="ambience")
    return out


def cache_path(q):
    return os.path.join(CACHE, urllib.parse.quote(q, safe="") + ".json")


def ask(q):
    """One API search (20 results), cached forever."""
    p = cache_path(q)
    if os.path.exists(p):
        return json.load(open(p, encoding="utf-8")), False
    url = API + "?" + urllib.parse.urlencode(dict(q=q, page_size=20, license=LICENSES))
    tries = 0
    while True:
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=90) as r:
                data = json.load(r)
                left = r.headers.get("x-ratelimit-available-anon_sustained")
            break
        except urllib.error.HTTPError as e:
            if e.code != 429:
                raise
            wait = int(e.headers.get("Retry-After") or 60)
            print(f"  rate limited, waiting {wait} s", flush=True)
            if wait > 600:
                sys.exit("daily search limit reached: run search again tomorrow (cached searches are kept)")
            time.sleep(wait)
        except (TimeoutError, urllib.error.URLError):
            tries += 1
            if tries > 3:
                raise
            print(f"  slow answer for '{q}', trying again", flush=True)
            time.sleep(10)
    os.makedirs(CACHE, exist_ok=True)
    json.dump(data, open(p, "w", encoding="utf-8"))
    print(f"  searched '{q}' ({data.get('result_count')} found, {left} searches left today)", flush=True)
    return data, True


def fits(r, s):
    """A result fits a slot when it is free to use and about the right length (it gets trimmed later)."""
    d = r.get("duration") or 0
    if r.get("license") not in ("cc0", "by", "pdm") or not r.get("url") or r.get("mature"):
        return False
    if r.get("title", "").startswith("LL-Q"):  # Lingua Libre: someone saying a word
        return False
    if s["kind"] == "sfx":
        return max(80, s["min_ms"] // 2) <= d <= max(3 * s["max_ms"], 4000)
    return s["min_ms"] <= d <= s["max_ms"]


def pool(slot, s, queries, used):
    """Every fitting result from the cached searches for a slot, in search order, not used elsewhere."""
    out, seen = [], set()
    for q in queries:
        p = cache_path(q)
        if not os.path.exists(p):
            continue
        for r in json.load(open(p, encoding="utf-8"))["results"]:
            if r["id"] in seen or r["id"] in used or not fits(r, s):
                continue
            seen.add(r["id"])
            out.append(dict(r, query=q))
    return out


def search():
    q = json.load(open(os.path.join(HERE, "openverse_queries.json"), encoding="utf-8"))
    ss = slots()
    missing = [k for k in ss if k not in q]
    if missing:
        sys.exit(f"no search words for: {missing}")
    for slot, s in ss.items():
        for i, words in enumerate(q[slot]):
            if i and len(pool(slot, s, q[slot][:i], set())) >= 6:
                break
            _, fresh = ask(words)
            if fresh:
                time.sleep(3.2)  # stay under 20 a minute


def redo(names):
    """Search again for slots whose three finds were all rejected: new words, never the old finds."""
    q = json.load(open(os.path.join(HERE, "openverse_queries.json"), encoding="utf-8"))
    redo_q = json.load(open(os.path.join(HERE, "openverse_queries_redo.json"), encoding="utf-8"))
    c = json.load(open(CANDS, encoding="utf-8"))
    for slot, d in c.items():
        if slot in names:
            d["rejected"] = sorted(set(d.get("rejected", [])) | {o["id"] for o in d["options"].values()})
            d["locked"] = False
            q[slot] = redo_q[slot]
            for key in "abc":  # the old previews must not be reused for new finds
                f = os.path.join(PREV, f"{slot.replace(':', '_')}_{key}.mp3")
                if os.path.exists(f):
                    os.remove(f)
        else:
            d["locked"] = True
    json.dump(q, open(os.path.join(HERE, "openverse_queries.json"), "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    json.dump(c, open(CANDS, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    hand = json.load(open(OVERRIDES, encoding="utf-8")) if os.path.exists(OVERRIDES) else {}
    json.dump({k: v for k, v in hand.items() if k not in names}, open(OVERRIDES, "w", encoding="utf-8"),
              indent=1, ensure_ascii=False)
    for slot in names:
        for words in q[slot]:
            _, fresh = ask(words)
            if fresh:
                time.sleep(3.2)
    pick()


def pick():
    """a, b, c = the best fitting results, taken in turn from each search so the three differ."""
    q = json.load(open(os.path.join(HERE, "openverse_queries.json"), encoding="utf-8"))
    old = json.load(open(CANDS, encoding="utf-8")) if os.path.exists(CANDS) else {}
    used, out = set(), {}
    hand = json.load(open(OVERRIDES, encoding="utf-8")) if os.path.exists(OVERRIDES) else {}
    every = [r for f in sorted(os.listdir(CACHE)) for r in json.load(open(os.path.join(CACHE, f), encoding="utf-8"))["results"]]
    # results picked by hand for some slot are never handed out to another slot
    reserved = {r["id"] for r in every for ws in hand.values() for w in ws if r["title"].startswith(w)}
    for slot, s in slots().items():
        if slot in old and old[slot].get("locked"):  # hand-picked: keep
            out[slot] = old[slot]
            used.update(o["id"] for o in old[slot]["options"].values())
            continue
        rejected = set(old.get(slot, {}).get("rejected", []))
        p = [r for r in pool(slot, s, q[slot], used) if r["id"] not in rejected]
        chosen = []
        for want in hand.get(slot, []):
            hit = next((r for r in p + every if r["title"].startswith(want) and fits(r, s)
                        and r["id"] not in used and r not in chosen), None)
            if hit is None:
                print(f"{slot}: no result titled '{want}'")
            else:
                used.add(hit["id"])
                chosen.append(dict(hit, query=hit.get("query", "")))
        p = [r for r in p if r["id"] not in reserved and r["id"] not in {c["id"] for c in chosen}]
        by_q = {}
        for r in p:
            by_q.setdefault(r["query"], []).append(r)
        while len(chosen) < 3 and any(by_q.values()):
            for words in q[slot]:
                if by_q.get(words) and len(chosen) < 3:
                    chosen.append(by_q[words].pop(0))
        opts = {}
        for key, r in zip("abc", chosen):
            used.add(r["id"])
            opts[key] = dict(id=r["id"], title=r["title"], creator=r.get("creator") or "unknown",
                             license=r["license"], license_version=r.get("license_version") or "",
                             page=r.get("foreign_landing_url") or "", url=r["url"], filetype=r.get("filetype") or "mp3",
                             ms=r.get("duration") or 0, source=r.get("source") or "", query=r["query"])
        out[slot] = dict(options=opts, pool=len(p))
        if rejected:
            out[slot]["rejected"] = sorted(rejected)
        if len(opts) < 3:
            print(f"{slot}: only {len(opts)} fitting results")
    json.dump(out, open(CANDS, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    print(f"{CANDS}: {len(out)} slots")


def ffmpeg(args):
    subprocess.run(["ffmpeg", "-v", "error", "-y", *args], check=True)


def preview(src, dst, kind):
    """A listening copy: sound effects start at the first sound and are levelled alike; songs are cut short."""
    if kind == "sfx":
        af = ("silenceremove=start_periods=1:start_threshold=-45dB,atrim=0:8,"
              "loudnorm=I=-16:TP=-1.5:LRA=11,aresample=44100")
        ffmpeg(["-i", src, "-af", af, "-ac", "1", "-b:a", "96k", dst])
    else:
        length = 60 if kind == "music" else 40
        af = f"atrim=0:{length},afade=t=out:st={length - 3}:d=3,loudnorm=I=-16:TP=-1.5:LRA=11,aresample=44100"
        ffmpeg(["-i", src, "-af", af, "-ac", "2", "-b:a", "96k", dst])


def previews():
    c = json.load(open(CANDS, encoding="utf-8"))
    ss = slots()
    os.makedirs(DL, exist_ok=True)
    os.makedirs(PREV, exist_ok=True)
    for slot, d in c.items():
        s, safe = ss[slot], slot.replace(":", "_")
        o = os.path.join(PREV, f"{safe}_o.mp3")
        if not os.path.exists(o):
            preview(s["original"], o, s["kind"])
        for key, opt in d["options"].items():
            raw = os.path.join(DL, f"{opt['id']}.{opt['filetype']}")
            if not os.path.exists(raw):
                req = urllib.request.Request(opt["url"], headers={"User-Agent": UA})
                try:
                    with urllib.request.urlopen(req, timeout=60) as r, open(raw + ".part", "wb") as f:
                        f.write(r.read())
                    os.replace(raw + ".part", raw)
                except Exception as e:
                    print(f"{slot} {key}: download failed ({e})")
                    continue
            dst = os.path.join(PREV, f"{safe}_{key}.mp3")
            if not os.path.exists(dst) or os.path.getmtime(dst) < os.path.getmtime(raw):
                try:
                    preview(raw, dst, s["kind"])
                except subprocess.CalledProcessError:
                    print(f"{slot} {key}: could not read the download")
    print("previews in", PREV)


if __name__ == "__main__":
    if sys.argv[1] == "redo":   # redo slot,slot,...
        redo(sys.argv[2].split(","))
    else:
        {"search": search, "pick": pick, "previews": previews}[sys.argv[1]]()
