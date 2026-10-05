"""Traces the Bucks wordmark from the supplied 1080x1080 JPEG into clean vector paths, one group per letter.
Run: python3 branding/trace_logo.py <source.jpg>. Writes branding/bucks_wordmark.svg and branding/letters.json."""
import sys, json
import numpy as np
from PIL import Image, ImageFilter
import potrace

SRC = sys.argv[1]
S = 4  # trace at 4x for sub-pixel edges
im = Image.open(SRC).convert('RGB')
# whiteness: min channel (purple has a low green channel, white is high everywhere)
g = np.array(im).astype(np.float32).min(axis=2)
big = Image.fromarray(g.astype(np.uint8)).resize((im.width * S, im.height * S), Image.LANCZOS).filter(ImageFilter.GaussianBlur(S * 0.6))
mask = np.array(big) > (31 + 255) / 2
bmp = potrace.Bitmap(~mask)  # potracer fills False pixels
path = bmp.trace(turdsize=200, turnpolicy=potrace.POTRACE_TURNPOLICY_MINORITY, alphamax=1.0, opticurve=True, opttolerance=0.2)

def fmt(v): return f"{v / S:.2f}".rstrip('0').rstrip('.')
def curve_d(c):
    d = [f"M{fmt(c.start_point.x)},{fmt(c.start_point.y)}"]
    for seg in c.segments:
        if seg.is_corner:
            d.append(f"L{fmt(seg.c.x)},{fmt(seg.c.y)}L{fmt(seg.end_point.x)},{fmt(seg.end_point.y)}")
        else:
            d.append(f"C{fmt(seg.c1.x)},{fmt(seg.c1.y)} {fmt(seg.c2.x)},{fmt(seg.c2.y)} {fmt(seg.end_point.x)},{fmt(seg.end_point.y)}")
    return "".join(d) + "Z"
def bbox(c):
    pts = [c.start_point] + [p for s in c.segments for p in ((s.c, s.end_point) if s.is_corner else (s.c1, s.c2, s.end_point))]
    xs = [p.x / S for p in pts]; ys = [p.y / S for p in pts]
    return min(xs), min(ys), max(xs), max(ys)

curves = list(path)
outers = [c for c in curves if c.children is not None] if False else None
# group holes into the outer shape that contains them (bbox containment), then order letters left to right
items = [(bbox(c), c) for c in curves]
items.sort(key=lambda t: (t[0][2] - t[0][0]) * (t[0][3] - t[0][1]), reverse=True)
groups = []
for bb, c in items:
    parent = next((g for g in groups if g['bb'][0] <= bb[0] and g['bb'][1] <= bb[1] and g['bb'][2] >= bb[2] and g['bb'][3] >= bb[3]), None)
    if parent: parent['d'] += curve_d(c)
    else: groups.append({'bb': bb, 'd': curve_d(c)})
groups.sort(key=lambda g: g['bb'][0])
print(len(curves), 'curves ->', len(groups), 'letters', [tuple(round(v) for v in g['bb']) for g in groups])
x0 = min(g['bb'][0] for g in groups); y0 = min(g['bb'][1] for g in groups); x1 = max(g['bb'][2] for g in groups); y1 = max(g['bb'][3] for g in groups)
json.dump({'box': [x0, y0, x1, y1], 'letters': [{'bb': g['bb'], 'd': g['d']} for g in groups]}, open('letters.json', 'w'), indent=1)
svg = f'<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="1080" viewBox="0 0 1080 1080"><rect width="1080" height="1080" fill="#811FF0"/>' + \
      ''.join(f'<path fill="#FFFFFF" fill-rule="evenodd" d="{g["d"]}"/>' for g in groups) + '</svg>'
open('bucks_logo_square.svg', 'w').write(svg)
