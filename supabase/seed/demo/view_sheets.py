"""Builds one contact sheet per shop (rows = products, columns = candidate photos) so the pictures can be checked by eye."""
import hashlib, io, json, os, sys, urllib.request
from concurrent.futures import ThreadPoolExecutor
from PIL import Image, ImageDraw
OUT = sys.argv[1]; os.makedirs(OUT, exist_ok=True)
res = json.load(open("images.json")); UA = {"User-Agent": "BucksDemoSeed/1.0 (closed-test demo data)"}
def get(u):
    p = os.path.join(OUT, hashlib.md5(u.encode()).hexdigest() + ".jpg")
    if not os.path.exists(p):
        for _ in range(3):
            try:
                open(p, "wb").write(urllib.request.urlopen(urllib.request.Request(u, headers=UA), timeout=30).read()); break
            except Exception: pass
    return p
urls = [c["url"] for v in res.values() for c in v["cands"]]
with ThreadPoolExecutor(6) as ex: list(ex.map(get, urls))
shops = {}
for k, v in res.items(): shops.setdefault(k.split("|")[0], []).append((k.split("|")[1], v))
W, H = 200, 140
for s, rows in shops.items():
    sheet = Image.new("RGB", (4 * W + 150, len(rows) * H), "white"); d = ImageDraw.Draw(sheet)
    for r, (name, v) in enumerate(rows):
        d.text((4, r * H + 4), name[:22], fill="black")
        for c, cand in enumerate(v["cands"]):
            try:
                im = Image.open(get(cand["url"])).convert("RGB"); im.thumbnail((W - 4, H - 4)); sheet.paste(im, (150 + c * W, r * H))
                d.text((150 + c * W + 3, r * H + 3), str(c), fill="red")
            except Exception: pass
    sheet.save(os.path.join(OUT, f"sheet_{s}.png"))
print("ok")
