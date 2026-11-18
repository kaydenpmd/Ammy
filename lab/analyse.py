"""pip-bar-lab: read one run's artifacts and print what the bar and Picture in Picture did.

    python lab/analyse.py <runs dir> <out dir>

<runs dir> holds one folder per setup (lab-se-pip-ios27, ...) as `gh run download` leaves them. Prints, per setup:
  - PiP over Ammy with each bar (main = build 201, fix = this branch): where it rested at each corner, how far above the bar's top button its bottom edge is (negative: it covers the button), with the keyboard, and over History;
  - the room SpringBoard says it rests PiP inside, and what it derived it from;
  - the room BarRoom gave the page, as the probe saw it;
  - every keyboard case, as keyboard-lab printed them, plus where the focused field ended against the bar;
  - how many pixels differ between fix and main at rest, below the status bar;
  - for every scroll, how far the content got from the finger;
  - the end of the page: History's bottom against the bar;
  - the slides to History: every frame the probe saw each copy of the bar laid out at.
Writes dark contact sheets to <out dir>.
"""
import datetime
import json
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

RECT = re.compile(r"x=([-\d.]+) y=([-\d.]+) w=([-\d.]+) h=([-\d.]+) maxY=([-\d.]+)")
NAMED = re.compile(r"(\w+)=\[([^\]]*)\]")
FRAME = re.compile(r"^(\w+) exists=(\w+) hittable=(\w+) frame=\(([-\d.]+), ([-\d.]+), ([-\d.]+), ([-\d.]+)\)")


def rect(text):
    m = RECT.search(text)
    if not m:
        return None
    x, y, w, h, maxy = map(float, m.groups())
    return dict(x=x, y=y, w=w, h=h, maxY=maxy)


def jsonl(path):
    out = []
    if not path.exists():
        return out
    for line in path.read_text(errors="replace").splitlines():
        try:
            out.append(json.loads(line))
        except ValueError:
            pass
    return out


# MARK: PiP

def pip_lines(d):
    """pip.txt: {tag: pip rect or None}, {tag: {button: rect}}, [(epoch, text)]."""
    pips, buttons, events = {}, {}, []
    p = d / "pip.txt"
    if not p.exists():
        return pips, buttons, events
    for line in p.read_text().splitlines():
        stamp, _, rest = line.partition(" ")
        try:
            events.append((float(stamp), rest))
        except ValueError:
            continue
        tag = rest.split(" ")[0]
        if " pip=" in rest:
            pips[tag] = rect(rest.split(" pip=")[1]) if "pip=none" not in rest else None
        elif any(f"{b}=[" in rest for b in ("Start", "Stop", "Restart")):
            buttons[tag] = {name: rect(body) for name, body in NAMED.findall(rest)}
    return pips, buttons, events


def pip_report(d, screen_h):
    pips, buttons, _ = pip_lines(d)
    rows = []
    for variant in ("main", "fix"):
        for state in ("idle", "running"):
            base = f"pip-{variant}-{state}"
            for corner in ("arrive", "bottomLeft", "bottomRight", "kb"):
                tag = f"{base}__{corner}"
                if tag not in pips:
                    continue
                r = pips[tag]
                bs = buttons.get(f"{base}__kb" if corner == "kb" else base, {})
                tops = [b["y"] for n, b in bs.items() if n in ("Start", "Stop", "Restart") and b]
                kb = bs.get("keyboard")
                if r is None:
                    rows.append(f"  {tag}: no PiP")
                    continue
                gap = f"{min(tops) - r['maxY']:+.2f}" if tops else "?"
                top = f"{min(tops):.2f}" if tops else "-"
                names = "+".join(n for n in ("Stop", "Restart", "Start") if bs.get(n))
                extra = f", keyboard top {kb['y']:.2f}" if kb else ""
                rows.append(f"  {tag}: PiP {r['y']:.2f}-{r['maxY']:.2f} x {r['x']:.2f} ({screen_h - r['maxY']:.2f} from the bottom), "
                            f"{names} top {top}, PiP's bottom {gap} pt above it{extra}")
        tag = f"pip-{variant}-history"
        for where in ("main", "history", "historyBottomRight", "back"):
            r = pips.get(f"{tag}__{where}")
            if f"{tag}__{where}" in pips:
                rows.append(f"  {tag}__{where}: " + (f"PiP {r['y']:.2f}-{r['maxY']:.2f} ({screen_h - r['maxY']:.2f} from the bottom)" if r else "no PiP"))
    return rows


SB = re.compile(r"^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+).*Applying new edge insets: \{([^}]*)\}.*safeAreaInsets: \{([^}]*)\}.*padding: \{([^}]*)\}")


def springboard(d):
    """SpringBoard's PiP insets in order, each beside the last pip.txt step before it."""
    p = d / "springboard-pip.log"
    if not p.exists():
        return ["  no springboard-pip.log"]
    _, _, events = pip_lines(d)
    rows, last = [], None
    for line in p.read_text(errors="replace").splitlines():
        m = SB.match(line)
        if not m:
            continue
        when, edge, safe, pad = m.groups()
        key = (edge, safe, pad)
        if key == last:
            continue
        last = key
        try:
            t = datetime.datetime.strptime(when[:26], "%Y-%m-%d %H:%M:%S.%f").replace(tzinfo=datetime.timezone.utc).timestamp()
            step = max((e for e in events if e[0] <= t), default=(0, "?"))[1].split(" ")[0]
        except ValueError:
            step = "?"
        rows.append(f"  {when[11:23]} after {step}: edge insets {{{edge}}} from safe area {{{safe}}} and the app's padding {{{pad}}}")
    return rows or ["  no inset lines"]


def rooms(d):
    rows = []
    for p in sorted(d.glob("pip-*.jsonl")) + sorted(d.glob("*__ends.jsonl")):
        seq = []
        for r in jsonl(p):
            if r.get("k") == "room":
                seq.append(f"room {r['old']:g}->{r['new']:g}")
            elif r.get("k") == "roomSafe":
                seq.append(f"[page safe bottom {r['safeBottom']:g}, top {r['safeTop']:g}]")
        if seq:
            rows.append(f"  {p.stem}: " + " ".join(seq[:12]) + (" ..." if len(seq) > 12 else ""))
    return rows


# MARK: Keyboard (keyboard-lab's, with the focused field added)

def blocks(path):
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
        field = "URL" if p.stem.endswith("URL") else "Key"
        # The keyboard's real top, its bar above the keys included, from the probe's last keyboardDidShow; XCUI's keyboard element leaves the bar out.
        top = None
        for r in jsonl(p.with_suffix(".jsonl")):
            if r.get("k") == "kb" and "DidShow" in r.get("what", "") and "y" in r:
                top = r["y"]
        win = rest["window"]
        parts = []
        for name in ("Start", "Stop", "Restart"):
            b = rest.get(name)
            if b and b["exists"]:
                parts.append(f"rest {name} y={b['y']:.2f}-{b['y'] + b['h']:.2f} ({win['h'] - b['y'] - b['h']:.2f} from the edge)")
        for label, blk in (("focused", focused), ("typed", typed)):
            kb = blk.get("keyboard")
            if not kb or not kb["exists"]:
                parts.append(f"{label}: no keyboard")
                continue
            kbtop = top if top is not None else kb["y"]
            items = [f"kb top {kbtop:.2f}"]
            btop = None
            for name in ("Start", "Stop", "Restart"):
                b = blk.get(name)
                if b and b["exists"]:
                    items.append(f"{name} {b['y']:.2f}-{b['y'] + b['h']:.2f} gap {kbtop - b['y'] - b['h']:+.2f} hit={'y' if b['hit'] else 'n'}")
                    btop = b["y"] if btop is None else min(btop, b["y"])
            f = blk.get(field)
            if f and f["exists"]:
                items.append(f"{field} {f['y']:.2f}-{f['y'] + f['h']:.2f}" + (f", {btop - 16 - f['y'] - f['h']:+.2f} above the bar's top" if btop is not None else ""))
            parts.append(f"{label}: " + ", ".join(items))
        rows.append(f"  {p.stem}\n    " + "\n    ".join(parts))
    return rows


def insets(d):
    rows = []
    for p in sorted(d.glob("*__kb*.jsonl")):
        seq = []
        for r in jsonl(p):
            if r.get("k") == "inset":
                key = "with" if "with" in r else "without"
                seq.append(f"{key}={r[key]:g}")
            elif r.get("k") == "room":
                seq.append(f"room={r['new']:g}")
            elif r.get("k") == "roomSafe":
                seq.append(f"(page {r['safeBottom']:g})")
            elif r.get("k") == "kb" and "DidShow" in r.get("what", ""):
                seq.append(f"[kb {r.get('y', '?')}+{r.get('h', '?')}, list inset {r.get('aib', '?')}]")
        rows.append(f"  {p.stem}: " + " ".join(seq))
    return rows


def diff_count(a, b):
    if not (a.exists() and b.exists()):
        return "missing"
    A = np.asarray(Image.open(a).convert("RGB")).astype(int)
    B = np.asarray(Image.open(b).convert("RGB")).astype(int)
    if A.shape != B.shape:
        return "sizes differ"
    top = int(A.shape[0] * 0.08)  # below the status bar
    diff = np.abs(A[top:] - B[top:]).sum(axis=2) > 0
    ys = np.nonzero(diff.any(axis=1))[0]
    where = f", rows {ys.min() + top}-{ys.max() + top} px, largest step {int(np.abs(A[top:] - B[top:]).max())}" if len(ys) else ""
    return f"{int(diff.sum())} differing pixels below the status bar{where}"


def pixel_diff(d):
    rows = []
    for name in ("running__rest", "idle__rest", "ends__top", "ends__end", "endsXXXL__top", "endsXXXL__end"):
        rows.append(f"  {name}: {diff_count(d / f'fix__{name}.png', d / f'main__{name}.png')}")
    return rows


def scrolls(d):
    rows = []
    for p in sorted(d.glob("scroll-*.jsonl")):
        frames = [(r["pan"], r["pcy"]) for r in jsonl(p)
                  if r.get("k") == "f" and "pan" in r and isinstance(r.get("pcy"), (int, float))]
        if len(frames) < 3:
            rows.append(f"  {p.stem}: no pan recorded ({len(frames)} frames)")
            continue
        f0, c0 = frames[0]
        leads = [(c - c0) - (f - f0) for f, c in frames]
        steps = [abs(leads[i] - leads[i - 1]) for i in range(1, len(leads))]
        rows.append(f"  {p.stem}: {len(frames)} frames, finger {frames[-1][0] - f0:+.1f} pt, "
                    f"content ahead of the finger by at most {max(leads, key=abs):+.1f} pt, "
                    f"biggest one-frame change {max(steps):.1f} pt")
    return rows


def ends(d):
    rows = []
    for p in sorted(d.glob("*__ends*.txt")):
        if p.name.endswith("__tree.txt"):
            continue
        bs = blocks(p)
        if len(bs) < 2:
            rows.append(f"  {p.stem}: incomplete")
            continue
        end = bs[1]
        h, b = end.get("History"), end.get("Stop")
        last = [r for r in jsonl(p.with_suffix(".jsonl")) if r.get("k") == "f" and "aib" in r]
        inset = f", list's bottom inset {last[-1]['aib']:g} (safe area {last[-1].get('sab', '?')}, content inset {last[-1].get('cib', '?')}), scroll bar's track ends {last[-1].get('viy', 0) + last[-1].get('vih', 0):.2f}" if last else ""
        if h and b and h["exists"] and b["exists"]:
            rows.append(f"  {p.stem}: History ends {h['y'] + h['h']:.2f}, Stop's top {b['y']:.2f}: {b['y'] - h['y'] - h['h']:.2f} pt between{inset}")
        else:
            rows.append(f"  {p.stem}: History or Stop missing{inset}")
    return rows


def history(d):
    rows = []
    for p in sorted(d.glob("*__history.jsonl")):
        seen = {}
        for r in jsonl(p):
            if r.get("k") == "bar":
                seen.setdefault(r["w"], []).append((round(r["x"], 2), round(r["y"], 2), round(r["wd"], 2), round(r["h"], 2)))
        rows.append(f"  {p.stem}:")
        for w, frames in seen.items():
            ys = sorted({f[1] for f in frames})
            hs = sorted({f[3] for f in frames})
            xs = sorted({f[0] for f in frames})
            rows.append(f"    {w}: {len(frames)} layouts, y {ys}, height {hs}, x from {xs[0]} to {xs[-1]}")
    for p in sorted(d.glob("*__history-marks.txt")):
        rows.append(f"  {p.stem}:")
        for line in p.read_text().splitlines():
            rows.append("    " + line.split(" ", 1)[1])
    return rows


# MARK: Sheets

def sheet(d, names, path, scale=0.5):
    shots = [(n, d / f"{n}.png") for n in names]
    shots = [(n, p) for n, p in shots if p.exists()]
    if not shots:
        return
    ims = [Image.open(p).convert("RGB") for _, p in shots]
    ims = [im.resize((int(im.width * scale), int(im.height * scale))) for im in ims]
    w, h = ims[0].width, ims[0].height
    pad, label = 12, 28
    cols = min(len(ims), 4)
    rows = (len(ims) + cols - 1) // cols
    S = Image.new("RGB", (cols * (w + pad) + pad, rows * (h + label + pad) + pad), (0, 0, 0))
    dr = ImageDraw.Draw(S)
    try:
        font = ImageFont.truetype("segoeui.ttf", 18)
    except OSError:
        font = ImageFont.load_default()
    for i, ((n, _), im) in enumerate(zip(shots, ims)):
        x = pad + (i % cols) * (w + pad)
        y = pad + (i // cols) * (h + label + pad)
        dr.text((x, y), n, fill=(235, 235, 245), font=font)
        S.paste(im, (x, y + label))
        # A hairline around each picture.
        dr.rectangle([x - 1, y + label - 1, x + w, y + label + h], outline=(84, 84, 88))
    S.save(path)


def sheets(d, setup, out):
    for corner in ("bottomRight", "bottomLeft", "kb"):
        sheet(d, [f"pip-{v}-{s}__{corner}" for s in ("idle", "running") for v in ("main", "fix")],
              out / f"sheet-{setup}-pip-{corner}.png")
    sheet(d, [f"pip-{v}-history__{w}" for v in ("main", "fix") for w in ("main", "history", "historyBottomRight", "back")],
          out / f"sheet-{setup}-pip-history.png")
    for field in ("URL", "Key"):
        sheet(d, [f"{v}__{s}__kb{field}" for s in ("running", "idle") for v in ("main", "fix")],
              out / f"sheet-{setup}-kb{field}.png")
    sheet(d, [f"{v}__{n}" for n in ("ends__top", "ends__end", "endsXXXL__end") for v in ("main", "fix")],
          out / f"sheet-{setup}-ends.png")


def main():
    runs, out = Path(sys.argv[1]), Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    for d in sorted(runs.glob("lab-*")):
        setup = d.name[4:]
        print(f"=== {setup}")
        dev = d / "device.txt"
        if dev.exists():
            print("  " + " | ".join(l.strip() for l in dev.read_text().splitlines() if l.strip())[:400])
        screen_h = None
        p = d / "pip.txt"
        if p.exists():
            m = re.search(r"screen [\d.]+ x ([\d.]+) pt", p.read_text())
            screen_h = float(m.group(1)) if m else None
        print("Picture in Picture over Ammy:")
        print("\n".join(pip_report(d, screen_h or 0)) or "  none")
        print("SpringBoard's room for PiP:")
        print("\n".join(springboard(d)))
        print("BarRoom (probe):")
        print("\n".join(rooms(d)) or "  none")
        print("keyboard cases:")
        print("\n".join(keyboard_cases(d)))
        print("readings (probe):")
        print("\n".join(insets(d)))
        print("fix against main, pixels:")
        print("\n".join(pixel_diff(d)))
        print("scrolls:")
        print("\n".join(scrolls(d)))
        print("ends of the page:")
        print("\n".join(ends(d)))
        print("History:")
        print("\n".join(history(d)))
        sheets(d, setup, out)


if __name__ == "__main__":
    main()
