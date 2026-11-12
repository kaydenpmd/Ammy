"""Writes report.txt from analyse.py's results.json (a11y-lab-nowplaying).

    python -I report.py OUTDIR
"""
import json
import os
import sys


def r(s):
    """A string with anything outside ASCII escaped, so U+FFFC shows."""
    return "None" if s is None else ascii(s)


def kind(debug_line):
    """The element type as debugDescription names it: the text before the
    first comma."""
    return debug_line.split(",")[0] if debug_line else None


def main():
    outdir = sys.argv[1]
    res = json.load(open(os.path.join(outdir, "results.json"), encoding="utf-8"))
    L = []
    for setup, S in res.items():
        L.append("=" * 100)
        L.append(f"SETUP {setup}")
        L.append((S.get("device") or "").strip())
        for key, E in S["states"].items():
            L.append("-" * 100)
            L.append(f"{setup} | {key}")
            moments = ["rest", "moving", "loop2"] if E["state"] == "long" else ["rest"]
            for b in ("change", "control"):
                if E[b].get("timing"):
                    L.append(f"  timing {b:7s} (s after the song showed): {E[b]['timing']}")
                if E[b].get("first"):
                    L.append(f"  first quick XCUITest read {b:7s}: label={r(E[b]['first']['label'])} frame={E[b]['first']['frame']}")
                if E[b].get("early"):
                    e = E[b]["early"]
                    L.append(f"  early in-app dump {b:7s}: label={r(e.get('label'))} attributed={r(e.get('attributedLabel'))} value={r(e.get('value'))} traits={e.get('traits')} ({e.get('traitsRaw')})")
            if E.get("relation_ax_early"):
                L.append(f"  early relation (in-app): {E['relation_ax_early']}")
            if E.get("relation_first"):
                L.append(f"  first-read relation (XCUIElement): {E['relation_first']}")
            sde = E.get("sequence_diff_early")
            if sde:
                L.append(f"  early in-app sequence: lengths {sde['lengths']}, {len(sde['differences'])} difference(s): "
                         + "; ".join(f"#{d['index']} {d['fields']}" for d in sde["differences"]))
            for m in moments:
                if not E["change"].get(m, {}).get("xcui") and not E["change"].get(m, {}).get("ax"):
                    continue
                for b in ("change", "control"):
                    x = E[b][m].get("xcui", {})
                    a = E[b][m].get("ax", {})
                    L.append(f"  [{m}] {b:7s} XCUIElement label={r(x.get('label'))}")
                    L.append(f"  [{m}] {b:7s}             value={x.get('value_raw')} type={x.get('elementType')} ({kind(x.get('debugLine'))}) frame={x.get('frame')}")
                    L.append(f"  [{m}] {b:7s}             debugDescription: {x.get('debugLine')}")
                    L.append(f"  [{m}] {b:7s} in-app      label={r(a.get('label'))} value={r(a.get('value'))} hint={r(a.get('hint'))} traits={a.get('traits')} ({a.get('traitsRaw')}) class={a.get('class')} index={a.get('index')}/{a.get('count')}")
                    if a.get("attributedRuns") is not None:
                        runs = [(x["range"], x["text"], "font tokens" if x["keys"] else "no attributes") for x in a.get("attributedRuns")]
                        L.append(f"  [{m}] {b:7s} in-app      attributedLabel={r(a.get('attributedLabel'))} runs={ascii(runs)}")
                L.append(f"  [{m}] relation (XCUIElement): {E.get('relation_xcui_' + m)}")
                L.append(f"  [{m}] relation (in-app):      {E.get('relation_ax_' + m)}")
                sd = E.get("sequence_diff_" + m)
                if sd:
                    L.append(f"  [{m}] in-app sequence: lengths {sd['lengths']}, {len(sd['differences'])} difference(s): "
                             + "; ".join(f"#{d['index']} {d['fields']}" for d in sd["differences"]))
                td = E.get("tree_diff_" + m)
                if td:
                    L.append(f"  [{m}] XCUITest tree: {td['controlLines']} vs {td['changeLines']} lines, {len(td['diff'])} differing line(s), by kind {td.get('kinds')}:")
                    for line in td["diff"][:12]:
                        L.append("      " + line.strip())
            p = E.get("pixels_top")
            if p:
                L.append(f"  pixels top (status bar {E['statusBar_pt']} pt @{E['scale']}x): status bar {p.get('statusDiffer')} px differ; "
                         f"outside it {p.get('outsideDiffer')} of {p.get('outsidePixels')} px differ (>8: {p.get('outsideDifferBy8')}, max {p.get('outsideMax')})"
                         + (f", box {p.get('outsideBox_pt')}" if p.get('outsideBox_pt') else ""))
            p = E.get("pixels_moving")
            if p:
                L.append(f"  pixels moving: status bar {p.get('statusDiffer')}; outside {p.get('outsideDiffer')} (>8: {p.get('outsideDifferBy8')}), box {p.get('outsideBox_pt')}")
            for b in ("change", "control"):
                g = E[b].get("geometry_tree") or {}
                gp = E[b].get("geometry_pixels") or {}
                L.append(f"  geometry {b:7s} tree: card h={g.get('card_height')} side={g.get('side')} top={g.get('top')} bottom={g.get('bottom')} cell={g.get('cell')} art={g.get('artwork')}")
                L.append(f"  geometry {b:7s} pixels: card h={gp.get('card_height')} art h={gp.get('artwork_height')} side={gp.get('side')} top={gp.get('top')} bottom={gp.get('bottom')} colours={gp.get('colors')}")
            for b in ("change", "control"):
                pr = E[b].get("probe", {})
                L.append(f"  probe {b:7s} os={pr.get('os')} trackShown={pr.get('trackShown')} metrics={ {k: v for k, v in (pr.get('metrics') or {}).items() if k in ('statusBar', 'safeArea', 'scale', 'style', 'voiceOver')} }")
        for track, A in S.get("audit", {}).items():
            L.append("-" * 100)
            L.append(f"{setup} | audit {track}")
            for b in ("change", "control"):
                a = A.get(b)
                if not a:
                    L.append(f"  {b}: missing")
                    continue
                L.append(f"  {b}: {len(a['issues'])} issue(s); {a['end']}")
                for i in a["issues"]:
                    L.append("     " + i)
            if "identical" in A:
                L.append(f"  identical issue lists (addresses aside): {A['identical']}")
                for l in A.get("onlyChange", []):
                    L.append("   only in change: " + l)
                for l in A.get("onlyControl", []):
                    L.append("   only in control: " + l)
    open(os.path.join(outdir, "report.txt"), "w", encoding="utf-8").write("\n".join(L) + "\n")
    print("wrote", os.path.join(outdir, "report.txt"), len(L), "lines")


if __name__ == "__main__":
    main()
