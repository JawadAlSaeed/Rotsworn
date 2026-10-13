# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Find and fetch CC0 recordings on Freesound (its public search pages, CC0 filter on).

  uv run tools/sound_kit/freesound_fetch.py search "zombie groan" "monster roar" [--max-s 8]
      One line per CC0 result: id, length, downloads, title, user.
  uv run tools/sound_kit/freesound_fetch.py get 754438 196722 --out audio/search/voices
      Saves each sound's HQ preview as <out>/fs-<id>.mp3 with fs-<id>.json (title, user, page, CC0),
      after checking its page says CC0. A layer uses it as {"sound": "<path>", "credit": "..."}.
"""
import argparse, html, json, os, re, subprocess, sys, urllib.parse

UA = "Mozilla/5.0 (RottenLands sound search)"


def curl(url, binary=False):
    out = subprocess.run(["curl", "-sSfL", "-A", UA, url], capture_output=True, check=True, timeout=300).stdout
    return out if binary else out.decode("utf-8", "replace")


def attr(block, name):
    m = re.search(name + r'="([^"]*)"', block)
    return html.unescape(m.group(1)) if m else ""


def search(query):
    q = urllib.parse.urlencode({"q": query, "f": 'license:"Creative Commons 0"'})
    page = curl("https://freesound.org/search/?" + q)
    out = []
    for block in page.split("data-sound-id=")[1:]:
        block = "data-sound-id=" + block[:3000]
        out.append(dict(id=int(attr(block, "data-sound-id") or 0), title=attr(block, "data-title"),
                        user=attr(block, "data-username"), seconds=float(attr(block, "data-duration") or 0),
                        downloads=int(attr(block, "data-num-downloads") or 0)))
    return [r for r in out if r["id"]]


def get(sound_id, out_dir):
    dst = os.path.join(out_dir, f"fs-{sound_id}.mp3")
    if os.path.exists(dst) and os.path.exists(dst[:-4] + ".json"):
        return dst
    page = curl(f"https://freesound.org/s/{sound_id}/")
    if "publicdomain/zero" not in page:
        raise SystemExit(f"{sound_id}: not CC0")
    mp3 = re.search(r"https://cdn\.freesound\.org/previews/[^\"]+-hq\.mp3", page).group(0)
    title = html.unescape(re.search(r"<title>(.*?)</title>", page, re.S).group(1)).replace("Freesound - ", "").split(" by ")[0].strip().strip('"')
    user = re.search(r"/people/([^/]+)/sounds/%d/" % sound_id, page).group(1)
    os.makedirs(out_dir, exist_ok=True)
    open(dst, "wb").write(curl(mp3, binary=True))
    landing = f"https://freesound.org/people/{user}/sounds/{sound_id}/"
    json.dump(dict(title=title, creator=urllib.parse.unquote(user), landing=landing, license="cc0",
                   credit=f"\"{title}\" by {urllib.parse.unquote(user)}, CC0, {landing}"),
              open(dst[:-4] + ".json", "w", encoding="utf-8"), indent=1)
    return dst


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("search"); s.add_argument("queries", nargs="+"); s.add_argument("--max-s", type=float, default=8.0)
    g = sub.add_parser("get"); g.add_argument("ids", nargs="+", type=int); g.add_argument("--out", default="audio/search/freesound")
    a = ap.parse_args()
    if a.cmd == "search":
        for q in a.queries:
            print(f"## {q}")
            for r in search(q):
                if r["seconds"] <= a.max_s:
                    print(f"  {r['id']:7d} {r['seconds']:5.1f}s {r['downloads']:6d}dl  {r['title'][:50]:50s} {r['user']}")
    else:
        for i in a.ids:
            p = get(i, a.out)
            print(p, json.load(open(p[:-4] + ".json", encoding="utf-8"))["title"])


if __name__ == "__main__":
    main()
