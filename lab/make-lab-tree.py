#!/usr/bin/env python3
# Lab only (keepalive-lab). Makes trees/lab: a copy of this checkout (the fix
# exactly as the working tree had it) plus the fault hooks below, each of
# which must match exactly once. The pure builds use the checkout itself.
#   python3 -I lab/make-lab-tree.py
import pathlib
import shutil
import sys

root = pathlib.Path.cwd()
dst = root / "trees" / "lab"
if dst.exists():
    shutil.rmtree(dst)
shutil.copytree(root, dst, ignore=shutil.ignore_patterns(".git", "trees", "out", "build*", "apps", "*.xcodeproj"))
shutil.copy(root / "lab" / "LabFaults.swift", dst / "Ammy" / "LabFaults.swift")

HOOKS = {
    "Ammy/KeepAlive.swift": [
        ("            try session.setActive(true)\n",
         "            try LabFaults.activate(session)\n"),
        ("            try engine.start()\n",
         "            try LabFaults.start(engine)\n"),
        ("    private func holdOpen(_ why: String) {\n",
         "    private func holdOpen(_ why: String) {\n        if LabFaults.noHold { return }\n"),
        ("    // MARK: - The hold\n",
         "    func labStopEngine() { node.stop(); engine.stop() }\n\n    // MARK: - The hold\n"),
    ],
    "Ammy/PresenceController.swift": [
        ("    init() {\n",
         "    init() {\n"
         "        LabFaults.install(stopEngine: { [weak self] in self?.keepAlive.labStopEngine() },\n"
         "                          verify: { [weak self] in self?.keepAlive.verify() },\n"
         "                          state: { [weak self] in self?.keepAlive.diagnostics })\n"),
    ],
    "Ammy/SilenceWatchdog.swift": [
        ("    func requestAuthorizationIfNeeded() async {\n",
         "    func requestAuthorizationIfNeeded() async {\n        if LabFaults.skipNotificationAsk { return }\n"),
    ],
}

for rel, pairs in HOOKS.items():
    p = dst / rel
    text = p.read_text(encoding="utf-8")
    for old, new in pairs:
        n = text.count(old)
        if n != 1:
            sys.exit(f"{rel}: expected one match, found {n}: {old!r}")
        text = text.replace(old, new)
    p.write_text(text, encoding="utf-8")
    print(f"hooked {rel}: {len(pairs)} change(s)")
