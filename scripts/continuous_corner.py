"""Prints the CSS clip paths that give the site's app icons Apple's corner.

The App Store app's icons have Apple's continuous corner, which CSS's
border-radius can't draw. public/store.css clips them with path() instead, and
this script writes those paths, so they can be made again if a size changes:

    python scripts/continuous_corner.py

The curve is the reverse-engineered form published as
UIBezierPath+IOS7RoundedRect (not an Apple source), the same one the design
library's measuring scripts fitted to the owner's captures
(design-research/apple/app-store-ios/measure/owner-dark/shapes.py). The radii
are the fitted ones from that spec: 30.65 on the 118 pt icon, 16.2 on the
62 pt one.
"""

# One corner, in units of the radius: (distance from the corner along the edge
# the path arrives on, distance along the edge it leaves on).
START = 1.52866483
CORNER = [
    ("C", (1.08849323, 0.0), (0.86840689, 0.0), (0.66993427, 0.06549600)),
    ("L", (0.63149399, 0.07491100)),
    ("C", (0.37282392, 0.16905899), (0.16905899, 0.37282401), (0.07491100, 0.63149399)),
    ("C", (0.0, 0.86840701), (0.0, 1.08849299), (0.0, START)),
]


def continuous(size, radius, inset=0.0):
    """A square of `size` with a continuous corner of `radius`, moved in by `inset`."""
    lo, hi, r = inset, size - inset, radius - inset
    # Clockwise from the top edge. Each entry turns (along, across) into x, y.
    corners = [
        lambda a, b: (hi - a * r, lo + b * r),   # top right, arriving on the top edge
        lambda a, b: (hi - b * r, hi - a * r),   # bottom right, arriving on the right edge
        lambda a, b: (lo + a * r, hi - b * r),   # bottom left, arriving on the bottom edge
        lambda a, b: (lo + b * r, lo + a * r),   # top left, arriving on the left edge
    ]
    fmt = lambda p: "%s %s" % tuple(("%.2f" % v).rstrip("0").rstrip(".") for v in p)
    out = ["M" + fmt((lo + START * r, lo))]
    for at in corners:
        out.append("L" + fmt(at(START, 0.0)))
        for seg in CORNER:
            out.append(seg[0] + " ".join(fmt(at(*p)) for p in seg[1:]))
    return "".join(out) + "Z"


if __name__ == "__main__":
    for size, radius in ((118, 30.65), (62, 16.2)):
        outer = continuous(size, radius)
        inner = continuous(size, radius, 1)
        print("/* %d px icon, radius %s */" % (size, radius))
        print('clip-path: path("%s");' % outer)
        print("/* its ring: the same shape less the one moved in by 1 px */")
        print('clip-path: path(evenodd, "%s%s");' % (outer, inner))
        print()
