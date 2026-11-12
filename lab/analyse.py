"""keyboard-lab: read one run's artifacts and print what the bar did.

    python lab/analyse.py <runs dir> <out dir>

<runs dir> holds one folder per setup (lab-se-ios27, ...) as `gh run
download` leaves them. Prints, per setup:
  - for every keyboard case, where the keyboard and the bar's buttons ended
    up after the letter was typed, and the gap between them (positive: the
    button's bottom is above the keyboard's top);
  - the readings the app logged (the probe's "inset" records);
  - how many pixels differ between the fix and build 172 at rest, below the
    status bar, with and without a session;
  - for every scroll, how far the content got from the finger.
Writes dark contact sheets of the keyboard cases to <out dir>.
"""
import json
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

FRAME = re.compile(r"^(\w+) exists=(\w+) hittable=(\w+) frame=\(([-\d.]+), ([-\d.]+), ([-\d.]+), ([-\d.]+)\)")


def blocks(path):
    """The frames blocks of a keyboard case: launched, focused, typed."""
    out, cur = [], {}
    for line in path.read_text().splitlines():
        m = FRAME.match(line)
        if m:
            name, exists, hit, x, y, w, h = m.groups()
            cur[name] = dict(exists=exists == "true", hit=hit == "true",
                             x=float(x), y=float(y), w=float(w), h=float(h))
        elif line.startswith("window frame="):
            nums = [float(v) for v in re.findall(r"[-\d.]+", line)]
            cur["window"] = dict(x=nums[0], y=nums[1], w=nums[2], h=nums[3])
            out.append(cur)
            cur = {}
    return out


def gap(b, kb):
    return kb["y"] - (b["y"] + b["h"])


def keyboard_cases(d):
    rows = []
    for p in sorted(d.glob("*__kb*.txt")):
        if p.name.endswith("__tree.txt"):
            continue
        bs = blocks(p)
        if len(bs) < 3:
            rows.append(f"  {p.stem}: incomplete ({len(bs)} blocks)")
            continue
        rest, focused, typed = bs[0], bs[1], bs[2]
        # The keyboard's real top, its bar above the keys included, from the
        # probe's last keyboardDidShow; XCUI's keyboard element leaves the bar out.
        top = None
        j = p.with_suffix(".jsonl")
        if j.exists():
            for line in j.read_text().splitlines():
                try:
                    r = json.loads(line)
                except ValueError:
                    continue
                if r.get("k") == "kb" and "DidShow" in r.get("what", "") and "y" in r:
                    top = r["y"]
        for blk in (focused, typed):
            if top is not None and blk.get("keyboard", {}).get("exists"):
                blk["keyboard"] = dict(blk["keyboard"], y=top)
        win = rest["window"]
        parts = []
        for name in ("Start", "Stop", "Restart"):
            b = rest.get(name)
            if b and b["exists"]:
                parts.append(f"rest {name} y={b['y']:.1f}-{b['y'] + b['h']:.1f} ({win['h'] - b['y'] - b['h']:.1f} from the edge)")
        for label, blk in (("focused", focused), ("typed", typed)):
            kb = blk.get("keyboard")
            if not kb or not kb["exists"]:
                parts.append(f"{label}: no keyboard")
                continue
            items = [f"kb top {kb['y']:.1f}"]
            for name in ("Start", "Stop", "Restart"):
                b = blk.get(name)
                if b and b["exists"]:
                    items.append(f"{name} {b['y']:.1f}-{b['y'] + b['h']:.1f} gap {gap(b, kb):+.1f} hit={'y' if b['hit'] else 'n'}")
            parts.append(f"{label}: " + ", ".join(items))
        rows.append(f"  {p.stem}\n    " + "\n    ".join(parts))
    return rows


def insets(d):
    rows = []
    for p in sorted(d.glob("*__kb*.jsonl")):
        seq = []
        for line in p.read_text().splitlines():
            try:
                r = json.loads(line)
            except ValueError:
                continue
            if r.get("k") == "inset":
                key = "with" if "with" in r else "without"
                seq.append(f"{key}={r[key]:g}")
            elif r.get("k") == "kb" and "DidShow" in r.get("what", ""):
                seq.append(f"[kb {r.get('y', '?')}+{r.get('h', '?')}]")
        rows.append(f"  {p.stem}: " + " ".join(seq))
    return rows


def pixel_diff(d):
    rows = []
    for state in ("running", "idle"):
        a, b = d / f"fix__{state}__rest.png", d / f"main__{state}__rest.png"
        if not (a.exists() and b.exists()):
            rows.append(f"  {state}: missing")
            continue
        A = np.asarray(Image.open(a).convert("RGB")).astype(int)
        B = np.asarray(Image.open(b).convert("RGB")).astype(int)
        if A.shape != B.shape:
            rows.append(f"  {state}: sizes differ")
            continue
        top = int(A.shape[0] * 0.08)  # below the status bar
        diff = np.abs(A[top:] - B[top:]).sum(axis=2) > 0
        ys = np.nonzero(diff.any(axis=1))[0]
        where = f", rows {ys.min() + top}-{ys.max() + top} px" if len(ys) else ""
        rows.append(f"  {state}: {int(diff.sum())} differing pixels below the status bar{where}")
    for v in ("ignore", "form148"):
        a, b = d / f"{v}__running__rest.png", d / "main__running__rest.png"
        if a.exists() and b.exists():
            A = np.asarray(Image.open(a).convert("RGB")).astype(int)
            B = np.asarray(Image.open(b).convert("RGB")).astype(int)
            top = int(A.shape[0] * 0.08)
            n = int((np.abs(A[top:] - B[top:]).sum(axis=2) > 0).sum())
            rows.append(f"  {v} vs main, running: {n} differing pixels below the status bar")
    return rows


def scrolls(d):
    rows = []
    for p in sorted(d.glob("scroll-*.jsonl")):
        frames = []
        for line in p.read_text().splitlines():
            try:
                r = json.loads(line)
            except ValueError:
                continue
            if r.get("k") == "f" and "pan" in r and isinstance(r.get("pcy"), (int, float)):
                frames.append((r["pan"], r["pcy"]))
        if len(frames) < 3:
            rows.append(f"  {p.stem}: no pan recorded ({len(frames)} frames)")
            continue
        f0, c0 = frames[0]
        leads = [(c - c0) - (f - f0) for f, c in frames]
        steps = [abs(leads[i] - leads[i - 1]) for i in range(1, len(leads))]
        moved = frames[-1][0] - f0
        rows.append(f"  {p.stem}: {len(frames)} frames, finger {moved:+.1f} pt, "
                    f"content ahead of the finger by at most {max(leads, key=abs):+.1f} pt, "
                    f"biggest one-frame change {max(steps):.1f} pt")
    return rows


def sheet(d, setup, out):
    """The keyboard cases side by side, in dark mode, as the tests left them."""
    order = [("fix", "running"), ("main", "running"), ("form148", "running"), ("ignore", "running"),
             ("fix", "idle"), ("main", "idle")]
    for field in ("URL", "Key"):
        shots = [(f"{v} {s}", d / f"{v}__{s}__kb{field}.png") for v, s in order]
        shots = [(t, p) for t, p in shots if p.exists()]
        if not shots:
            continue
        ims = [Image.open(p).convert("RGB") for _, p in shots]
        scale = 0.5
        ims = [im.resize((int(im.width * scale), int(im.height * scale))) for im in ims]
        w, h = ims[0].width, ims[0].height
        pad, label = 12, 28
        S = Image.new("RGB", (len(ims) * (w + pad) + pad, h + label + pad), (0, 0, 0))
        dr = ImageDraw.Draw(S)
        try:
            font = ImageFont.truetype("segoeui.ttf", 18)
        except OSError:
            font = ImageFont.load_default()
        for i, ((t, _), im) in enumerate(zip(shots, ims)):
            x = pad + i * (w + pad)
            dr.text((x, 4), t, fill=(235, 235, 245), font=font)
            S.paste(im, (x, label))
            # A hairline around each picture.
            dr.rectangle([x - 1, label - 1, x + w, label + h], outline=(84, 84, 88))
        S.save(out / f"sheet-{setup}-kb{field}.png")


def main():
    runs, out = Path(sys.argv[1]), Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    for d in sorted(runs.glob("lab-*")):
        setup = d.name[4:]
        print(f"=== {setup}")
        dev = d / "device.txt"
        if dev.exists():
            print("  " + " | ".join(l.strip() for l in dev.read_text().splitlines() if l.strip())[:300])
        print("keyboard cases:")
        print("\n".join(keyboard_cases(d)))
        print("readings (probe):")
        print("\n".join(insets(d)))
        print("at rest, fix against build 172:")
        print("\n".join(pixel_diff(d)))
        print("scrolls:")
        print("\n".join(scrolls(d)))
        sheet(d, setup, out)


if __name__ == "__main__":
    main()
