# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Search OpenGameArt for music a slot could use; keep only CC0 and CC-BY tracks.

  uv run tools/sound_kit/find_music.py "dark forest" "haunted forest" [--out audio/music_search.json]

Prints one line per track (licence, author, title, file, tags) and adds it to the JSON file, so
the candidates can be reviewed and downloaded later. Only reads public pages.
"""
import argparse, html, json, os, re, sys, time, urllib.parse, urllib.request

UA = "Mozilla/5.0 (RottenLands music search)"
BASE = "https://opengameart.org"
FREE = ("CC0", "CC-BY 3.0", "CC-BY 4.0")


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read().decode("utf-8", "replace")


def search(query, n):
    q = urllib.parse.urlencode({"keys": query, "field_art_type_tid[]": "12", "sort_by": "count",
                                "sort_order": "DESC", "items_per_page": "48"})
    page = get(f"{BASE}/art-search-advanced?{q}")
    links = re.findall(r'<div class="field-item even"><a href="(/content/[^"]+)">', page)
    if not links:
        links = re.findall(r'href="(/content/[a-z0-9\-]+)"', page)
    seen, out = set(), []
    for l in links:
        if l in seen or l in ("/content/faq",) or "art-challenge" in l:
            continue
        seen.add(l)
        out.append(l)
    return out[:n]


def item(path):
    page = get(BASE + path)
    title = html.unescape(re.search(r"<title>(.*?) \|", page).group(1)) if re.search(r"<title>(.*?) \|", page) else path
    lic = [html.unescape(x).strip() for x in re.findall(r"class='license-name'>([^<]*)<", page)]
    files = [u for u in re.findall(r'href="(https://opengameart\.org/sites/default/files/[^"]+)"', page)
             if re.search(r"\.(ogg|mp3|wav|flac)$", u, re.I)]
    author = re.search(r'field-name-author-submitter.*?href="/users/[^"]*">([^<]*)<', page, re.S)
    tags_block = re.search(r"field-name-field-art-tags(.*?)</div></div></div>", page, re.S)
    tags = re.findall(r">([^<>]+)</a>", tags_block.group(1)) if tags_block else []
    return dict(url=BASE + path, title=title, licenses=lic, files=files,
                author=html.unescape(author.group(1)) if author else "?", tags=[t.strip() for t in tags][:12])


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser()
    ap.add_argument("queries", nargs="+")
    ap.add_argument("--n", type=int, default=15)
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "audio", "music_search.json"))
    a = ap.parse_args()
    found = json.load(open(a.out, encoding="utf-8")) if os.path.exists(a.out) else {}
    for q in a.queries:
        print(f"## {q}")
        for path in search(q, a.n):
            if BASE + path in found:
                it = found[BASE + path]
            else:
                try:
                    it = item(path)
                except Exception as ex:
                    print("  skip", path, ex, file=sys.stderr); continue
                time.sleep(0.3)
            free = [l for l in it["licenses"] if l in FREE]
            if not free or not it["files"]:
                continue
            it.setdefault("queries", [])
            if q not in it["queries"]:
                it["queries"].append(q)
            found[it["url"]] = it
            names = ", ".join(os.path.basename(urllib.parse.unquote(f)) for f in it["files"][:3])
            print(f"  {free[0]:9s} {it['author'][:18]:18s} {it['title'][:42]:42s} | {names[:60]} | {' '.join(it['tags'][:6])}")
        os.makedirs(os.path.dirname(a.out), exist_ok=True)
        json.dump(found, open(a.out, "w", encoding="utf-8"), indent=1)


if __name__ == "__main__":
    main()
