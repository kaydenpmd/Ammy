"""Analyses an a11y lab run (a11y-lab-nowplaying).

    python -I analyse.py RUNDIR OUTDIR

RUNDIR holds one folder per lab job artifact (lab-<setup>/), as
`gh run download` leaves them; several RUNDIRs can be given, separated by
commas, and a later one's files fill what an earlier one lacks. OUTDIR gets
results.json and report.txt; sheets.py draws the pictures from results.json.

For every setup, state, appearance and build it reads:
  the card's element as XCUITest saw it   <b>-<state>-<a>-<moment>-card.txt
  the whole XCUITest tree                 <b>-<state>-<a>-<moment>-tree.txt
  what the app vends to VoiceOver         <b>-<state>-<a>-ax-<moment>.json
  the probe (status bar, song shown)      <b>-<state>-<a>.probe.jsonl
  the screenshot                          <b>-<state>-<a>-top.png (-moving)
and compares change with control.
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import parse  # noqa: E402
import pixels  # noqa: E402

SETUPS = ["se-ios27", "se-ios26", "17e-ios27", "se-ios27-sdk26", "17e-ios27-sdk26"]
STATES = [
    ("notPlaying", "Not Playing"),
    ("notAvailable", "Not Available"),
    ("short", "Blue"),
    ("explicit", "HUMBLE."),
    ("long", "Prime Time Golden Hour Show (Soundtrack)"),
]
BUILDS = ["change", "control"]
APPEARANCES = ["dark", "light"]
PREFIX = "Now Playing"


def find(dirs, name):
    for d in dirs:
        p = os.path.join(d, name)
        if os.path.exists(p):
            return p
    return None


def card_info(dirs, base, moment, expect):
    out = {}
    p = find(dirs, f"{base}-{moment}-card.txt")
    if p:
        card = parse.parse_card(p)
        el = parse.card_element(card)
        out["xcui"] = {
            "count": len(card["entries"]),
            "all": [{"label": e.get("label"), "frame": e.get("frame"), "elementType": e.get("elementType"),
                     "debugLine": e.get("debugLine")} for e in card["entries"]],
        }
        if el:
            out["xcui"].update({
                "label": el.get("label"), "value": el.get("value"), "value_raw": el.get("value_raw"),
                "elementType": el.get("elementType"), "frame": el.get("frame"),
                "identifier": el.get("identifier"), "debugLine": el.get("debugLine"),
                "enabled": el.get("enabled"), "keys": el.get("attribute keys"),
            })
    p = find(dirs, f"{base}-ax-{moment}.json")
    if p:
        ax = parse.load_json(p)
        els = ax.get("elements", [])
        matches = [e for e in els if isinstance(e.get("label"), str) and expect in e["label"]]
        out["ax"] = {"count": len(els), "matches": len(matches), "voiceOver": ax.get("voiceOver"),
                     "cells": ax.get("cells", [])}
        if matches:
            e = matches[0]
            out["ax"].update({k: e.get(k) for k in ("label", "value", "hint", "traits", "traitsRaw", "frame",
                                                    "class", "attributedLabel", "attributedRuns", "index",
                                                    "identifier", "language", "inputLabels", "customActions",
                                                    "path")})
        out["ax"]["sequence"] = [
            {"label": e.get("label"), "value": e.get("value"), "traits": e.get("traits"),
             "frame": e.get("frame"), "class": e.get("class")} for e in els]
    return out


def relation(change_label, control_label):
    """How the change's label is made from the control's."""
    if change_label is None or control_label is None:
        return None
    if change_label == control_label:
        return {"same": True}
    if change_label.startswith(PREFIX) and change_label.endswith(control_label):
        sep = change_label[len(PREFIX):len(change_label) - len(control_label)]
        return {"prefixThenControl": True, "separator": sep,
                "separatorCodepoints": [f"U+{ord(c):04X}" for c in sep]}
    return {"other": True}


def sequence_diff(a, b):
    """Positions where two in-app element sequences differ, by field."""
    out = {"lengths": [len(a), len(b)], "differences": []}
    for i in range(max(len(a), len(b))):
        x = a[i] if i < len(a) else None
        y = b[i] if i < len(b) else None
        if x != y:
            fields = sorted(k for k in set((x or {}).keys()) | set((y or {}).keys())
                            if (x or {}).get(k) != (y or {}).get(k))
            out["differences"].append({"index": i, "fields": fields, "change": x, "control": y})
    return out


LINES = {
    "short": ("Blue", "Joni Mitchell"),
    "explicit": ("HUMBLE. ", "Kendrick Lamar"),
    "long": ("Prime Time Golden Hour Show (Soundtrack)", "Shiori Sasaki, ATLUS Sound Team & ATLUS GAME MUSIC"),
}


def classify(line, state, card_frame):
    """What a differing tree line is: the card's own element, one of the
    lines inside it (whose position depends on when the marquee was read),
    the artwork inside it (listed in a different place when a line has
    scrolled left of it), or anything else."""
    m = parse.FRAME_RE.search(line)
    f = [float(x) for x in m.groups()] if m else None
    lab = None
    lm = parse.re.search(r"label: '(.*)'$", line)
    if lm:
        lab = lm.group(1)
    if f and card_frame and all(abs(f[k] - card_frame[k]) < 0.06 for k in range(4)) and lab is not None:
        return "card"
    if lab is not None and state in LINES and lab in LINES[state]:
        return "line"
    if f and abs(f[2] - 57) < 1 and abs(f[3] - 57) < 1 and lab is None:
        return "artwork"
    return "other"


def tree_diff(pa, pb, state=None, card_frame=None):
    if not (pa and pb):
        return None
    a, b = parse.normalise_tree(pa), parse.normalise_tree(pb)
    import difflib
    lines = [l for l in difflib.unified_diff(b, a, "control", "change", n=0, lineterm="")]
    changed = [l for l in lines if (l.startswith("+") or l.startswith("-")) and not l.startswith(("+++", "---"))]
    kinds = {}
    for l in changed:
        k = classify(l[1:].strip(), state, card_frame)
        kinds[k] = kinds.get(k, 0) + 1
    return {"controlLines": len(b), "changeLines": len(a), "diff": changed, "kinds": kinds}


def geometry_from_tree(path, card_frame):
    """The card's cell and the 57 x 57 artwork inside it, from the XCUITest
    tree: the Cell whose frame is the card's, and the first element of about
    57 x 57 after it."""
    items = parse.parse_tree(path)
    if not card_frame:
        return None
    cell = None
    art = None
    for i, it in enumerate(items):
        f = it.get("frame")
        if it["type"] == "Cell" and f and all(abs(f[k] - card_frame[k]) < 0.06 for k in range(4)):
            cell = it
            for jt in items[i + 1:]:
                if jt["depth"] <= it["depth"]:
                    break
                g = jt.get("frame")
                if g and abs(g[2] - 57) < 1.5 and abs(g[3] - 57) < 1.5:
                    art = jt
                    break
            break
    if not (cell and art):
        return {"error": "cell or artwork not found", "cell": cell and cell["frame"], "art": art and art["frame"]}
    c, a = cell["frame"], art["frame"]
    return {
        "cell": c, "artwork": a,
        "card_height": round(c[3], 3),
        "side": round(a[0] - c[0], 3),
        "top": round(a[1] - c[1], 3),
        "bottom": round((c[1] + c[3]) - (a[1] + a[3]), 3),
        "artwork_line": art["line"], "cell_line": cell["line"],
    }


def labelled_order(path):
    """Every element in the XCUITest tree that has a label, in tree order."""
    if not path:
        return None
    return [{"type": it["type"], "label": it.get("label"), "frame": it.get("frame"), "depth": it["depth"]}
            for it in parse.parse_tree(path) if it.get("label")]


def probe_info(dirs, base):
    p = find(dirs, f"{base}.probe.jsonl")
    recs = parse.probe(p) if p else []
    info = {}
    for r in recs:
        if r.get("k") == "metrics":
            info["metrics"] = r
        elif r.get("k") == "track":
            info["trackShown"] = r.get("wall")
        elif r.get("k") == "start":
            info["start"] = r.get("wall")
            info["os"] = r.get("os")
    return info


def audit_info(dirs, build, track):
    p = find(dirs, f"{build}-audit-{track}-dark.txt")
    if not p:
        return None
    lines = open(p, encoding="utf-8").read().split("\n")
    issues = [l for l in lines if l.startswith("type=")]
    tail = [l for l in lines if l.startswith("audit ")]
    norm = [re.sub(r"0x[0-9a-f]+", "0x…", l) for l in issues]
    return {"issues": issues, "normalised": norm, "end": tail}


def analyse_setup(dirs, setup):
    res = {"setup": setup, "dirs": dirs}
    p = find(dirs, "device.txt")
    res["device"] = open(p, encoding="utf-8").read() if p else None
    res["states"] = {}
    for state, expect in STATES:
        for app in APPEARANCES:
            key = f"{state}-{app}"
            entry = {"state": state, "appearance": app, "expect": expect}
            moments = ["rest", "moving", "loop2"] if state == "long" else ["rest"]
            for b in BUILDS:
                base = f"{b}-{state}-{app}"
                entry[b] = {"probe": probe_info(dirs, base)}
                for m in moments:
                    entry[b][m] = card_info(dirs, base, m, expect)
                early = find(dirs, f"{base}-ax-early.json")
                if early:
                    entry[b]["early"] = card_info(dirs, base, "early", expect).get("ax")
                first = find(dirs, f"{base}-first-card.txt")
                if first:
                    txt = open(first, encoding="utf-8").read().strip()
                    fm = parse.re.match(r"^([0-9.]+) first read: label=(\".*\") frame=(.*)$", txt)
                    if fm:
                        entry[b]["first"] = {"wall": float(fm.group(1)), "label": parse.swift_unquote(fm.group(2)),
                                             "frame": fm.group(3)}
                # When each read was made, in seconds after the song showed.
                song = entry[b]["probe"].get("trackShown")
                shots_file = find(dirs, "shots.txt")
                sh = parse.shots(shots_file) if shots_file else {}
                mk = parse.marks(find(dirs, f"{base}.marks.txt") or "")
                timing = {}
                if song:
                    for nm in ("top", "moving", "loop2"):
                        if f"{base}-{nm}" in sh:
                            timing[f"shot_{nm}"] = round(sh[f"{base}-{nm}"][0] - song, 2)
                    for t, what in mk:
                        if what.startswith(("rest:", "moving:", "loop2:")) and "recorded" in what:
                            timing["read_" + what.split(":")[0]] = round(t - song, 2)
                        if what.startswith("in-app dump"):
                            timing["dump_" + what.split()[2].rstrip(":")] = round(t - song, 2)
                    if entry[b].get("first"):
                        timing["first_read"] = round(entry[b]["first"]["wall"] - song, 2)
                entry[b]["timing"] = timing
                entry[b]["top"] = find(dirs, f"{base}-top.png")
                entry[b]["tree"] = find(dirs, f"{base}-rest-tree.txt")
                if state == "long":
                    entry[b]["moving_png"] = find(dirs, f"{base}-moving.png")
            # Labels compared.
            if entry["change"].get("early") and entry["control"].get("early"):
                entry["relation_ax_early"] = relation(entry["change"]["early"].get("label"),
                                                      entry["control"]["early"].get("label"))
                entry["sequence_diff_early"] = sequence_diff(entry["change"]["early"].get("sequence") or [],
                                                             entry["control"]["early"].get("sequence") or [])
            if entry["change"].get("first") and entry["control"].get("first"):
                entry["relation_first"] = relation(entry["change"]["first"]["label"], entry["control"]["first"]["label"])
            for m in moments:
                ch = entry["change"][m].get("xcui", {}).get("label")
                co = entry["control"][m].get("xcui", {}).get("label")
                entry[f"relation_xcui_{m}"] = relation(ch, co)
                cha = entry["change"][m].get("ax", {}).get("label")
                coa = entry["control"][m].get("ax", {}).get("label")
                entry[f"relation_ax_{m}"] = relation(cha, coa)
                sa = entry["change"][m].get("ax", {}).get("sequence")
                sb = entry["control"][m].get("ax", {}).get("sequence")
                if sa is not None and sb is not None:
                    entry[f"sequence_diff_{m}"] = sequence_diff(sa, sb)
                entry[f"tree_diff_{m}"] = tree_diff(find(dirs, f"change-{state}-{app}-{m}-tree.txt"),
                                                   find(dirs, f"control-{state}-{app}-{m}-tree.txt"),
                                                   state, entry["change"][m].get("xcui", {}).get("frame"))
            # Pixels at the top of the page.
            metrics = entry["change"]["probe"].get("metrics") or entry["control"]["probe"].get("metrics") or {}
            scale = metrics.get("scale", 2.0)
            status = (metrics.get("statusBar") or [0, 0, 0, 20])[3]
            entry["scale"] = scale
            entry["statusBar_pt"] = status
            if entry["change"]["top"] and entry["control"]["top"]:
                entry["pixels_top"] = pixels.diff(entry["change"]["top"], entry["control"]["top"], status, scale)
            if state == "long" and entry["change"].get("moving_png") and entry["control"].get("moving_png"):
                entry["pixels_moving"] = pixels.diff(entry["change"]["moving_png"], entry["control"]["moving_png"],
                                                     status, scale)
            # Geometry, from the tree and from the pixels.
            for b in BUILDS:
                frame = entry[b]["rest"].get("xcui", {}).get("frame")
                tp = entry[b]["tree"]
                g = geometry_from_tree(tp, frame) if tp else None
                entry[b]["geometry_tree"] = g
                if g and "artwork" in g and entry[b]["top"]:
                    try:
                        entry[b]["geometry_pixels"] = pixels.geometry(entry[b]["top"], g["artwork"], g["cell"], scale)
                    except Exception as ex:  # noqa: BLE001
                        entry[b]["geometry_pixels"] = {"error": repr(ex)}
                entry[b]["order_xcui"] = labelled_order(tp)
            res["states"][key] = entry
    res["audit"] = {}
    for track in ("short", "long"):
        a = {b: audit_info(dirs, b, track) for b in BUILDS}
        if a["change"] and a["control"]:
            sa, sb = sorted(a["change"]["normalised"]), sorted(a["control"]["normalised"])
            a["identical"] = sa == sb
            a["onlyChange"] = [l for l in sa if l not in sb]
            a["onlyControl"] = [l for l in sb if l not in sa]
        res["audit"][track] = a
    return res


def main():
    rundirs = sys.argv[1].split(",")
    outdir = sys.argv[2]
    os.makedirs(outdir, exist_ok=True)
    results = {}
    for setup in SETUPS:
        dirs = [os.path.join(r, f"lab-{setup}") for r in rundirs if os.path.isdir(os.path.join(r, f"lab-{setup}"))]
        if not dirs:
            continue
        results[setup] = analyse_setup(dirs, setup)
    with open(os.path.join(outdir, "results.json"), "w", encoding="utf-8") as f:
        json.dump(results, f, indent=1, ensure_ascii=False, default=str)
    print("wrote", os.path.join(outdir, "results.json"))


if __name__ == "__main__":
    main()
