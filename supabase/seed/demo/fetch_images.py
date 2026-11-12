"""Finds freely licensed photos on Wikimedia Commons for every demo shop and product, and records the link, author and licence.
Run: python3 fetch_images.py  (writes images.json). Only JPEGs wider than 800 px under a CC0 / public-domain / CC BY / CC BY-SA licence.
A browser pane or `view_sheets.py` is used afterwards to check the pictures by eye."""
import json, re, sys, time, urllib.parse, urllib.request
from catalog import SHOPS
UA = "BucksDemoSeed/1.0 (closed-test demo data; contact via project repo)"
OK = re.compile(r"^(CC0|Public domain|PD|CC BY(-SA)? [0-9.]+)", re.I)
def api(q, n=8):
    url = "https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode({"action":"query","format":"json","generator":"search","gsrnamespace":6,"gsrlimit":n,"gsrsearch":q+" filetype:bitmap",
        "prop":"imageinfo","iiprop":"url|size|mime|extmetadata","iiurlwidth":640,"iiextmetadatafilter":"LicenseShortName|Artist"})
    for _ in range(3):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=25) as r: return json.load(r)
        except Exception as e: time.sleep(2)
    return {}
def clean(u): return u.split("?")[0]
def candidates(q):
    out = []
    for p in sorted(api(q).get("query", {}).get("pages", {}).values(), key=lambda p: p.get("index", 99)):
        i = p["imageinfo"][0]; m = i.get("extmetadata", {}); lic = m.get("LicenseShortName", {}).get("value", "")
        if i["mime"] != "image/jpeg" or i["width"] < 800 or not OK.match(lic): continue
        art = re.sub(r"<[^>]+>", "", m.get("Artist", {}).get("value", "")).strip()[:80]
        out.append(dict(title=p["title"], url=clean(i["thumburl"]), lic=lic, author=art, page="https://commons.wikimedia.org/wiki/" + urllib.parse.quote(p["title"].replace(" ", "_")), w=i["width"], h=i["height"]))
    return out
if __name__ == "__main__":
    res = {}
    for s in SHOPS:
        qs = [("cover", s["cover"])] + [(it[0], it[5]) for it in s["items"]]
        for name, q in qs:
            c = candidates(q); res[s["key"] + "|" + name] = dict(query=q, cands=c[:4]); print(s["key"], name, len(c), flush=True); time.sleep(0.4)
    json.dump(res, open("images.json", "w"), indent=1)
