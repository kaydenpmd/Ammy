"""App icon: an album cover, sent. Albums' black tile, a little larger, with
two waves leaving it to the right in Albums' two greys, fading as they go.
Issun's icon is the other half of the sentence: the same two waves arriving at
a speech bubble. Black on white, and white on black for dark mode, like Albums.

    python scripts/make_icon.py Ammy/Assets.xcassets/AppIcon.appiconset

writes AppIcon.png, AppIcon-Dark.png and AppIcon-Tinted.png. Needs Pillow."""
import math
import sys
from PIL import Image, ImageDraw, ImageFilter

S = 1024
SS = 4  # supersample for smooth edges
W = S * SS

def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))

def bezier(p0, p1, p2, p3, n=48):
    pts = []
    for i in range(n + 1):
        t = i / n
        mt = 1 - t
        pts.append(tuple(mt**3 * p0[k] + 3 * mt**2 * t * p1[k] + 3 * mt * t**2 * p2[k] + t**3 * p3[k] for k in range(2)))
    return pts

def squircle_corner(R, smoothing, budget):
    """Figma's corner smoothing, as figma-squircle implements it (after Figma's
    "Desperately seeking squircles"): one corner, from the top edge to the right
    edge, in coordinates relative to the corner point (x left is negative)."""
    p = (1 + smoothing) * R
    if p > budget:
        smoothing = min(smoothing, budget / R - 1)
        p = min(p, budget)
    arc_measure = 90 * (1 - smoothing)
    arc_len = math.sin(math.radians(arc_measure / 2)) * R * math.sqrt(2)
    alpha = (90 - arc_measure) / 2
    p3p4 = R * math.tan(math.radians(alpha / 2))
    beta = 45 * smoothing
    c = p3p4 * math.cos(math.radians(beta))
    d = c * math.tan(math.radians(beta))
    b = (p - arc_len - c - d) / 3
    a = 2 * b
    pts = bezier((-p, 0), (-p + a, 0), (-p + a + b, 0), (-p + a + b + c, d))
    cx, cy = -R, R
    t0, t1 = -45 - arc_measure / 2, -45 + arc_measure / 2
    for i in range(1, 48):
        t = math.radians(t0 + (t1 - t0) * i / 48)
        pts.append((cx + R * math.cos(t), cy + R * math.sin(t)))
    q0 = (-p + a + b + c + arc_len, d + arc_len)
    pts += bezier(q0, (q0[0] + d, q0[1] + c), (q0[0] + d, q0[1] + b + c), (q0[0] + d, q0[1] + a + b + c))
    return pts

def squircle(x0, y0, x1, y1, R, smoothing=0.6):
    corner = squircle_corner(R, smoothing, min(x1 - x0, y1 - y0) / 2)
    pts = [(x1 + u, y0 + v) for u, v in corner]          # top right
    pts += [(x1 - v, y1 + u) for u, v in corner]         # bottom right
    pts += [(x0 - u, y1 - v) for u, v in corner]         # bottom left
    pts += [(x0 + v, y0 - u) for u, v in corner]         # top left
    return pts

def wave(cx, cy, r, w, phi, n=160):
    """A thick arc about (cx, cy), phi degrees either side of pointing right,
    with round ends, as SF Symbols draws its waves."""
    def at(radius, deg):
        a = math.radians(deg)
        return (cx + radius * math.cos(a), cy + radius * math.sin(a))
    def cap(deg, turn):
        ex, ey = at(r, deg)
        a = math.radians(deg) + turn
        return [(ex + w / 2 * math.cos(a + math.pi * i / 32), ey + w / 2 * math.sin(a + math.pi * i / 32))
                for i in range(1, 32)]
    pts = [at(r + w / 2, -phi + 2 * phi * i / n) for i in range(n + 1)]
    pts += cap(phi, 0)
    pts += [at(r - w / 2, phi - 2 * phi * i / n) for i in range(n + 1)]
    pts += cap(-phi, math.pi)
    return pts

# The cover is one of Albums' tiles, a little larger (300 on Albums' 274), with
# its corner in proportion. The waves are centred on the cover, so they read as
# leaving it, and thick enough to stay two waves at 40 px (2.9 px each there).
COVER, WAVE, FIRST_GAP, GAP, SPREAD = 300, 74, 92, 50, 38
R1 = COVER / 2 + FIRST_GAP + WAVE / 2
R2 = R1 + WAVE + GAP
# Centring the box would leave the solid cover pulling the picture left; this
# puts its centre of weight on the icon's centre line, near enough.
CX = S / 2 - (R2 + WAVE / 2 - COVER / 2) / 2 + 30
CY = S / 2

def scaled(pts, dy=0):
    return [(x * SS, (y + dy) * SS) for x, y in pts]

def icon(top, bottom, cover, near, far, shadow_rgba, out, grayscale=False):
    img = Image.new("RGB", (W, W))
    d = ImageDraw.Draw(img)
    for y in range(W):
        d.line([(0, y), (W, y)], fill=lerp(top, bottom, y / (W - 1)))
    img = img.convert("RGBA")

    h = COVER / 2
    shapes = [(squircle(CX - h, CY - h, CX + h, CY + h, 46 / 274 * COVER), cover),
              (wave(CX, CY, R1, WAVE, SPREAD), near),
              (wave(CX, CY, R2, WAVE, SPREAD), far)]
    shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    for pts, _ in shapes:
        sd.polygon(scaled(pts, dy=12), fill=shadow_rgba)
    img = Image.alpha_composite(img, shadow.filter(ImageFilter.GaussianBlur(18 * SS)))
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    for pts, fill in shapes:
        ld.polygon(scaled(pts), fill=fill + (255,))
    img = Image.alpha_composite(img, layer)

    img = img.convert("RGB").resize((S, S), Image.LANCZOS)
    if grayscale:
        img = img.convert("L").convert("RGB")
    img.save(out)

folder = sys.argv[1]
icon((255, 255, 255), (238, 238, 242), (20, 20, 22), (88, 88, 92), (160, 160, 166), (0, 0, 0, 40), f"{folder}/AppIcon.png")
icon((40, 40, 44), (6, 6, 8), (250, 250, 252), (172, 172, 178), (104, 104, 110), (0, 0, 0, 120), f"{folder}/AppIcon-Dark.png")
icon((40, 40, 44), (6, 6, 8), (250, 250, 252), (172, 172, 178), (104, 104, 110), (0, 0, 0, 120), f"{folder}/AppIcon-Tinted.png", grayscale=True)
