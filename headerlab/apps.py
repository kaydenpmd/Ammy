"""Turns `simctl listapps` into the lists the UI tests read.

Usage: python3 headerlab/apps.py OUT_DIR

Reads OUT_DIR/listapps.json (plutil's conversion) or, failing that,
OUT_DIR/listapps.txt, and writes:
  apps.tsv          bundle id, display name, application type, hidden or visible
  apps-all.txt      every bundle id, comma-separated (what is installed)
  apps-visible.txt  the system apps a person can see on the Home Screen
"""
import json
import os
import re
import sys

out = sys.argv[1]
rows = []
try:
    with open(os.path.join(out, "listapps.json")) as f:
        data = json.load(f)
    for bid, info in data.items():
        tags = info.get("SBAppTags") or []
        rows.append((
            bid,
            info.get("CFBundleDisplayName") or info.get("CFBundleName") or "",
            info.get("ApplicationType") or "",
            "hidden" if "hidden" in tags else "visible",
        ))
except Exception as e:  # noqa: BLE001 - any failure falls back to the text
    print("listapps.json unreadable (%s); reading the text instead" % e)
    with open(os.path.join(out, "listapps.txt")) as f:
        text = f.read()
    for m in re.finditer(r'CFBundleIdentifier = "?([^";]+)"?;', text):
        rows.append((m.group(1), "", "", "unknown"))

rows.sort(key=lambda r: r[0].lower())
with open(os.path.join(out, "apps.tsv"), "w") as f:
    for r in rows:
        f.write("\t".join(r) + "\n")
with open(os.path.join(out, "apps-all.txt"), "w") as f:
    f.write(",".join(r[0] for r in rows))
with open(os.path.join(out, "apps-visible.txt"), "w") as f:
    f.write(",".join(r[0] for r in rows if r[3] != "hidden" and r[2] != "User"))
print("%d apps, %d visible system apps" % (
    len(rows), sum(1 for r in rows if r[3] != "hidden" and r[2] != "User")))
