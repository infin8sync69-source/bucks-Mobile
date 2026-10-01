"""Renders branding/preview_splash.gif and preview_loader.gif with the same spring and timings as ui/components/Brand.kt. Run from the repo root."""
import json, io, math, cairosvg
from PIL import Image
L = [l for l in json.load(open('branding/letters.json'))['letters']]
x0 = min(l['bb'][0] for l in L); y0 = min(l['bb'][1] for l in L); W = max(l['bb'][2] for l in L) - x0; H = max(l['bb'][3] for l in L) - y0
PUR = '#811FF0'
def spring(t, zeta=0.52, k=260.0):   # unit step response of a damped spring (mass 1), as Compose's spring() from 0 to 1
    if t <= 0: return 0.0
    w0 = math.sqrt(k); wd = w0 * math.sqrt(1 - zeta ** 2)
    return 1 - math.exp(-zeta * w0 * t) * (math.cos(wd * t) + zeta * w0 / wd * math.sin(wd * t))
def emph(u):  # cubic-bezier(0.2,0,0,1) approximated by solving x(t)
    u = min(max(u, 0), 1); lo, hi = 0.0, 1.0
    for _ in range(30):
        m = (lo + hi) / 2; x = 3 * (1 - m) ** 2 * m * 0.2 + 3 * (1 - m) * m * m * 0 + m ** 3
        lo, hi = (m, hi) if x < u else (lo, m)
    m = (lo + hi) / 2; return 3 * (1 - m) * m * m * 1 + m ** 3
def word(poses, sheen, scale, tx, ty, color='#fff'):
    g = []
    for (l, (dy, sx, sy, a)) in zip(L, poses):
        if a <= 0: continue
        cx = (l['bb'][0] + l['bb'][2]) / 2; by = l['bb'][3]
        g.append(f'<g transform="translate(0 {dy * H}) translate({cx} {by}) scale({sx} {sy}) translate({-cx} {-by})"><path fill="{color}" fill-opacity="{min(a,1)}" fill-rule="evenodd" d="{l["d"]}"/></g>')
    sh = ''
    if sheen >= 0:
        band = W * 0.28; x = x0 - band + (W + 2 * band) * sheen
        sh = (f'<defs><linearGradient id="s" gradientUnits="userSpaceOnUse" x1="{x - band}" y1="{y0}" x2="{x}" y2="{y0 + H * 0.6}"><stop offset="0" stop-color="#BE98FF" stop-opacity="0"/><stop offset=".5" stop-color="#BE98FF" stop-opacity=".85"/><stop offset="1" stop-color="#BE98FF" stop-opacity="0"/></linearGradient>'
              f'<clipPath id="m">{"".join(g)}</clipPath></defs><rect x="{x0}" y="{y0 - H}" width="{W}" height="{H * 3}" fill="url(#s)" clip-path="url(#m)"/>')
    return f'<g transform="translate({tx} {ty}) scale({scale}) translate({-x0} {-y0})">{"".join(g)}{sh}</g>'
def pose_entrance(t):
    out = []
    for i in range(5):
        p = spring(t - i * 0.075); out.append(((1 - p) * 0.6, 1 + (1 - p) * 0.12, 0.55 + 0.45 * p, max(0, min(1, p * 1.6))))
    return out
def sheen_at(t): return -1 if t < 0.56 or t > 1.08 else emph((t - 0.56) / 0.52) * 0 + (lambda u: 1 - (1 - u) ** 2)((t - 0.56) / 0.52)
FW, FH = 360, 760; frames = []
# welcome screen: entrance 0..1.1 s, glide 1.1..1.72, copy 1.72..2.18, hold
for f in range(int(2.9 * 30)):
    t = f / 30; settle = emph((t - 1.1) / 0.62) if t > 1.1 else 0; copy = emph((t - 1.72) / 0.46) if t > 1.72 else 0
    h = 72 * (1 - 0.12 * settle); w = h * W / H; s = h / H
    cy = FH / 2 - FH * 0.16 * settle
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{FW}" height="{FH}"><rect width="{FW}" height="{FH}" fill="{PUR}"/>'
           + word(pose_entrance(t), sheen_at(t), s, FW / 2 - w / 2, cy - h / 2)
           + f'<g opacity="{copy}" transform="translate(0 {(1 - copy) * 24})"><text x="{FW/2}" y="{FH - 150}" font-family="sans-serif" font-size="15" fill="#fff" fill-opacity=".88" text-anchor="middle">Rides, food, skilled people and local shops,</text>'
           + f'<text x="{FW/2}" y="{FH - 128}" font-family="sans-serif" font-size="15" fill="#fff" fill-opacity=".88" text-anchor="middle">ranked only by the people who used them.</text>'
           + f'<rect x="32" y="{FH - 96}" width="{FW - 64}" height="52" rx="14" fill="#fff"/><text x="{FW/2}" y="{FH - 64}" font-family="sans-serif" font-weight="bold" font-size="15" fill="#4A0AA6" text-anchor="middle">Get started</text></g></svg>')
    frames.append(Image.open(io.BytesIO(cairosvg.svg2png(bytestring=svg.encode()))).convert('P', palette=Image.ADAPTIVE, colors=64))
frames[0].save('branding/preview_splash.gif', save_all=True, append_images=frames[1:], duration=33, loop=0, optimize=True)
# loader
lf = []
for f in range(int(1.15 * 30)):
    ph = f / (1.15 * 30); poses = []
    for i in range(5):
        x = ph - i * 0.11; x += 1 if x < 0 else 0; b = math.sin(x / 0.42 * math.pi) if x < 0.42 else 0
        poses.append((-0.2 * b, 1 - 0.03 * b, 1 + 0.07 * b, 0.5 + 0.5 * b))
    h = 28; s = h / H; w = h * W / H
    svg = f'<svg xmlns="http://www.w3.org/2000/svg" width="240" height="90"><rect width="240" height="90" fill="#fff"/>' + word(poses, -1, s, 120 - w / 2, 45 - h / 2, PUR) + '</svg>'
    lf.append(Image.open(io.BytesIO(cairosvg.svg2png(bytestring=svg.encode(), scale=2))).convert('P', palette=Image.ADAPTIVE, colors=64))
lf[0].save('branding/preview_loader.gif', save_all=True, append_images=lf[1:], duration=33, loop=0, optimize=True)
frames[int(0.3*30)].convert('RGB').save('/tmp/claude-0/-home-user/1f03ebc4-2678-5dce-b408-070b118e81d9/scratchpad/f1.png'); frames[int(0.78*30)].convert('RGB').save('/tmp/claude-0/-home-user/1f03ebc4-2678-5dce-b408-070b118e81d9/scratchpad/f2.png'); frames[-1].convert('RGB').save('/tmp/claude-0/-home-user/1f03ebc4-2678-5dce-b408-070b118e81d9/scratchpad/f3.png')
lf[5].convert('RGB').save('/tmp/claude-0/-home-user/1f03ebc4-2678-5dce-b408-070b118e81d9/scratchpad/l1.png')
print('ok')
