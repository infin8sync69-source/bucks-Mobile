"""Picks one photo per demo product: searches Wikimedia Commons (CC0 / public domain / CC BY / CC BY-SA, JPEG, >= 800 px), keeps files
whose title names the product, prefers landscape and large. Writes picks.json and a contact sheet of the picks for a last look."""
import json, re, sys, time
from catalog import SHOPS
import fetch_images as F
KW = {"rice bowl":["rice"],"lentils dal":["lentil","dal","dhal"],"coffee powder":["coffee"],"pure honey":["honey"],"cow ghee":["ghee","butter"],"turmeric":["turmeric"],"peppercorns":["pepper"],"tea leaves loose":["tea"],
      "south indian filter coffee":["coffee","kaapi"],"indian vegetarian thali":["thali","meal"],"masala chai glass":["chai","tea"],"idli sambar":["idli","idly"],"chicken biryani plate":["biryani","biriyani"],
      "gulab jamun":["gulab","jamun"],"paneer butter masala":["paneer"],"masala dosa":["dosa","dosai"],"samosa":["samosa"],"loaf of whole wheat bread":["bread"],"butter croissant":["croissant"],
      "chocolate truffle cake":["cake"],"plum cake slice":["cake"],"glazed donuts box":["donut","doughnut"],"blueberry muffin":["muffin"],"chocolate chip cookies":["cookie"],
      "tomatoes":["tomato"],"onions":["onion"],"potatoes":["potato"],"carrots":["carrot"],"spinach leaves":["spinach"],"bananas bunch":["banana"],"mangoes":["mango"],"cauliflower":["cauliflower"],
      "raw chicken pieces":["chicken"],"chicken breast raw":["chicken"],"eggs carton":["egg"],"fresh fish seer kingfish":["fish","seer","kingfish"],"raw prawns":["prawn","shrimp"],"raw mutton meat":["mutton","lamb","meat"],
      "fresh sardines":["sardine"],"brown eggs basket":["egg"],"cotton kurta":["kurta","kurti"],"men formal shirt":["shirt"],"blue denim jeans":["jeans","denim"],"silk saree":["saree","sari"],"kids t-shirt":["shirt"],
      "dupatta scarf":["dupatta","scarf"],"leather belt":["belt"],"canvas sneakers":["sneaker","shoe"],"wireless earbuds":["earbud","earphone","airpod","headphone"],"power bank":["power bank","powerbank","battery"],
      "smartwatch":["watch"],"bluetooth speaker":["speaker"],"usb-c cable":["usb","cable"],"smartphone case":["case","phone"],"over-ear headphones":["headphone"],"webcam":["webcam","camera"],
      "notebooks stack":["notebook"],"gel pens set":["pen"],"coloured pencils box":["pencil"],"geometry box compass":["compass","geometry"],"desk organizer":["organi"],"sketchbook":["sketch"],
      "highlighter pens":["highlighter","marker"],"school backpack":["backpack","bag"],"hand sanitizer bottle":["sanitiz","sanitis"],"face masks":["mask"],"vitamin tablets bottle":["vitamin","tablet","pill"],
      "digital thermometer":["thermometer"],"first aid kit":["first aid"],"baby diapers":["diaper","nappy"],"herbal balm jar":["balm"],"blood pressure monitor":["blood pressure","sphygmo"],
      "ceramic plant pot":["pot","planter"],"table lamp":["lamp"],"cushion covers":["cushion","pillow"],"wall clock":["clock"],"scented candles":["candle"],"photo frames wall":["frame"],"brass diya lamp":["diya","lamp"],"doormat":["mat"]}
SKIP = re.compile(r"diagram|map|logo|icon|svg|poster|stamp|painting|drawing|illustration|plant\b|flower|tree", re.I)
def pick(q, n=25):
    kws = KW.get(q) or [q.split()[-1].lower()]
    best = None
    for c in F.candidates(q) if False else []: pass
    return kws
def rank(q):
    kws = KW.get(q) or [q.split()[-1].lower()]
    out = []
    pages = F.api(q, 25).get("query", {}).get("pages", {}).values()
    for p in pages:
        i = p["imageinfo"][0]; m = i.get("extmetadata", {}); lic = m.get("LicenseShortName", {}).get("value", "")
        t = p["title"].lower()
        if i["mime"] != "image/jpeg" or i["width"] < 800 or not F.OK.match(lic) or SKIP.search(t) and not any(k in t for k in kws): continue
        if not any(k in t for k in kws): continue
        art = re.sub(r"<[^>]+>", "", m.get("Artist", {}).get("value", "")).strip()[:80]
        score = (2 if i["width"] >= i["height"] else 0) + (1 if i["width"] >= 1500 else 0) + (1 if lic.startswith(("CC0", "Public", "PD")) else 0)
        out.append((score, dict(title=p["title"], url=F.clean(i["thumburl"]), lic=lic, author=art, page="https://commons.wikimedia.org/wiki/" + p["title"].replace(" ", "_"))))
    out.sort(key=lambda x: -x[0]); return [o[1] for o in out]
if __name__ == "__main__":
    picks = {}
    for s in SHOPS:
        for it in s["items"]:
            r = rank(it[5]); picks[s["key"] + "|" + it[0]] = r[:3]; print(s["key"], it[0], len(r), flush=True); time.sleep(0.5)
    json.dump(picks, open("picks.json", "w"), indent=1)
