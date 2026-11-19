"""bar-width-lab: where each glass element sits at the bottom of a Widths screenshot.

    python lab/measure.py <runs dir>

<runs dir> holds one folder per device (lab-se-ios27, ...) as `gh run download` leaves them. Widths draws its pages on flat grey (white 0.5), so every pixel in the bottom part of a row that differs from the row's first pixel by more than THRESH belongs to a bar, a button or its shadow. Ammy's page isn't flat, but its rows start with the page's own colour too, so its list cells (16 pt in) show up as pieces beside its bar. For each screenshot of a Widths variant and of Ammy, this finds the separate pieces, row by row, and prints each piece's left and right edges on its widest row, its top and bottom, in points, with the distance to each side of the screen and to the bottom. The scale is the screenshot's width over the window's width in frames-*.txt.
"""
import re
import sys
from pathlib import Path

from PIL import Image

THRESH = 14


def window_width(d, mode):
    p = d / f"frames-{mode}.txt"
    if not p.exists():
        return None
    m = re.search(r"window=\[x=[-\d.]+ y=[-\d.]+ w=([\d.]+) h=([\d.]+)", p.read_text())
    return (float(m.group(1)), float(m.group(2))) if m else None


def pieces(img, top_frac=0.62):
    """Runs of pixels that differ from the page's grey, on every row of the bottom part, joined into pieces that overlap from one row to the next."""
    im = img.convert("RGB")
    w, h = im.size
    px = im.load()
    bg = px[1, int(h * 0.45)]
    rows = {}
    for y in range(int(h * top_frac), h):
        # Each row's own background, from its first pixel: Widths' grey, or the page's colour at the screen's edge in Ammy and Apple's apps, whose cells start 16 pt in.
        bg = px[1, y]
        run, runs = None, []
        for x in range(w):
            r, g, b = px[x, y]
            off = max(abs(r - bg[0]), abs(g - bg[1]), abs(b - bg[2])) > THRESH
            if off and run is None:
                run = [x, x]
            elif off:
                run[1] = x
            elif run is not None and x - run[1] > 3:
                runs.append(tuple(run))
                run = None
        if run is not None:
            runs.append(tuple(run))
        rows[y] = [r for r in runs if r[1] - r[0] > 6]
    # Join runs into pieces by overlap with the previous row's.
    found = []  # each: dict(top, bottom, rows={y: (l, r)})
    open_ = []
    for y in sorted(rows):
        nxt = []
        for l, r in rows[y]:
            home = next((p for p in open_ if p["last"][0] <= r and l <= p["last"][1]), None)
            if home is None:
                home = {"top": y, "rows": {}}
                found.append(home)
            home["rows"].setdefault(y, (l, r))
            l0, r0 = home["rows"][y]
            home["rows"][y] = (min(l0, l), max(r0, r))
            home["last"] = home["rows"][y]
            home["bottom"] = y
            nxt.append(home)
        open_ = nxt
    return bg, [p for p in found if len(p["rows"]) > 8]


def describe(path, scale, screen):
    img = Image.open(path)
    bg, ps = pieces(img)
    w, h = img.size
    out = [f"  {path.stem} (page grey {bg}):"]
    for p in sorted(ps, key=lambda p: (p["top"], min(l for l, _ in p["rows"].values()))):
        widest_y = max(p["rows"], key=lambda y: p["rows"][y][1] - p["rows"][y][0])
        l, r = p["rows"][widest_y]
        L, R = l / scale, (r + 1) / scale
        T, B = p["top"] / scale, (p["bottom"] + 1) / scale
        out.append(f"    x {L:.2f} to {R:.2f} ({R - L:.2f} wide; {L:.2f} from the left, {screen[0] - R:.2f} from the right), "
                   f"y {T:.2f} to {B:.2f} ({B - T:.2f} tall; {screen[1] - B:.2f} from the bottom), widest at y {widest_y / scale:.2f}")
    return out


def main():
    runs = Path(sys.argv[1])
    for d in sorted(runs.glob("lab-*")):
        print(f"=== {d.name[4:]}")
        dev = d / "device.txt"
        if dev.exists():
            print("  " + " | ".join(l.strip() for l in dev.read_text().splitlines() if l.strip())[:260])
        for mode in ("dark", "light"):
            screen = window_width(d, mode)
            if not screen:
                print(f"  {mode}: no frames")
                continue
            print(f" {mode}, screen {screen[0]:g} x {screen[1]:g} pt")
            for p in sorted(d.glob(f"widths-*-{mode}.png")) + sorted(d.glob(f"ammy-{mode}.png")):
                scale = Image.open(p).size[0] / screen[0]
                print("\n".join(describe(p, scale, screen)))


if __name__ == "__main__":
    main()
