"""Parsers for the a11y lab's output files (a11y-lab-nowplaying).

Imported by analyse.py; nothing here writes anything.
"""
import json
import os
import re

FRAME_RE = re.compile(r"\{\{(-?[0-9.]+), (-?[0-9.]+)\}, \{(-?[0-9.]+), (-?[0-9.]+)\}\}")


def swift_unquote(s):
    """A string as Swift's String.debugDescription writes it, decoded."""
    s = s.strip()
    assert s.startswith('"') and s.endswith('"'), s[:40]
    body = s[1:-1]
    out = []
    i = 0
    while i < len(body):
        c = body[i]
        if c == "\\" and i + 1 < len(body):
            n = body[i + 1]
            if n == "u" and body[i + 2:i + 3] == "{":
                j = body.index("}", i + 3)
                out.append(chr(int(body[i + 3:j], 16)))
                i = j + 1
                continue
            out.append({"n": "\n", "t": "\t", "r": "\r", "0": "\0", '"': '"', "'": "'", "\\": "\\"}.get(n, n))
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def parse_card(path):
    """<name>-<moment>-card.txt: every element whose label contains the
    state's text, as the UI test recorded it."""
    entries = []
    cur = None
    in_debug = False
    header = None
    for raw in open(path, encoding="utf-8").read().split("\n"):
        if header is None:
            header = raw
        m = re.match(r"^\[(\d+)\]$", raw)
        if m:
            cur = {"index": int(m.group(1)), "debug": []}
            entries.append(cur)
            in_debug = False
            continue
        if cur is None:
            continue
        if raw.startswith("  debugDescription:"):
            in_debug = True
            continue
        if in_debug:
            if raw.startswith("    "):
                cur["debug"].append(raw[4:])
                continue
            if raw.startswith("    ") is False and raw.strip() == "":
                cur["debug"].append("")
                continue
            in_debug = False
        m = re.match(r"^  (\w+(?: \w+)*): (.*)$", raw)
        if m:
            key, val = m.group(1), m.group(2)
            if key == "label":
                cur["label"] = swift_unquote(val)
            elif key == "value":
                cur["value_raw"] = val
                if val.startswith("String "):
                    cur["value"] = swift_unquote(val[len("String "):])
                elif val == "nil":
                    cur["value"] = None
                else:
                    cur["value"] = val
            elif key == "identifier":
                cur["identifier"] = swift_unquote(val)
            elif key == "frame":
                nums = [float(x) for x in re.findall(r"-?[0-9.]+", val)]
                cur["frame"] = nums[:4]
            elif key == "elementType":
                cur["elementType"] = int(val)
            else:
                cur[key] = val
    for e in entries:
        attr = next((l for l in e["debug"] if l.startswith("Attributes: ")), None)
        e["debugLine"] = attr[len("Attributes: "):] if attr else None
    return {"header": header, "entries": entries}


def card_element(card):
    """The card's own element: the largest of those whose label contains the
    state's text (the combined row; the others are its lines inside it)."""
    best = None
    for e in card["entries"]:
        f = e.get("frame")
        if not f:
            continue
        area = f[2] * f[3]
        if best is None or area > best[0]:
            best = (area, e)
    return best[1] if best else None


TREE_LINE = re.compile(r"^(\s*)(→)?([A-Za-z][A-Za-z ()]*?), 0x[0-9a-f]+(.*)$")


def parse_tree(path):
    """An XCUIApplication.debugDescription dump: one record per element line,
    in order, with depth, type, frame, label, identifier, value."""
    items = []
    text = open(path, encoding="utf-8").read()
    for raw in text.split("\n"):
        m = TREE_LINE.match(raw)
        if not m:
            continue
        indent, _, etype, rest = m.groups()
        fm = FRAME_RE.search(rest)
        frame = [float(x) for x in fm.groups()] if fm else None
        rec = {"depth": len(indent), "type": etype.strip(), "frame": frame, "line": raw.strip()}
        for key in ("label", "identifier", "value", "placeholderValue"):
            km = re.search(r"\b" + key + r": '((?:[^'\\]|\\.|'(?!,\s\w+:|$))*)'", rest)
            if km:
                rec[key] = km.group(1)
        items.append(rec)
    return items


def normalise_tree(path):
    """The tree with addresses and pids taken out, for comparing two runs."""
    out = []
    for raw in open(path, encoding="utf-8").read().split("\n"):
        line = re.sub(r"0x[0-9a-f]+", "0x…", raw)
        line = re.sub(r"pid: \d+", "pid: …", line)
        out.append(line)
    return out


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def probe(path):
    recs = []
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            line = line.strip()
            if line:
                try:
                    recs.append(json.loads(line))
                except json.JSONDecodeError:
                    pass
    return recs


def marks(path):
    out = []
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            parts = line.rstrip("\n").split(" ", 1)
            if len(parts) == 2:
                try:
                    out.append((float(parts[0]), parts[1]))
                except ValueError:
                    pass
    return out


def shots(path):
    """shots.txt: before, after, name for every screenshot the test took."""
    out = {}
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            parts = line.split()
            if len(parts) >= 3:
                out[parts[2]] = (float(parts[0]), float(parts[1]))
    return out
