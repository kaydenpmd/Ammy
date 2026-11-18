"""pip-lab only, never merged.

The stock iPhone simulators say Picture in Picture isn't supported
(isPictureInPictureSupported is false on iOS 27.0, run 44275708353), while
real iPhones have had it since iOS 14. This writes every property list of the
iPhone SE's and an iPad's simulator device types to OUT (as JSON) with the
keys that name PiP, then makes a copy of the SE's device type, in the user's
own device types folder, that claims each such capability the iPad has.

usage: python3 fakepip.py OUT
prints: the copy's device type identifier, or nothing when no key was found
"""
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys

OUT = sys.argv[1]
PATTERN = re.compile(r"pip|picture", re.I)


def log(line):
    with open(os.path.join(OUT, "fakepip.txt"), "a") as f:
        f.write(line + "\n")


def load(path):
    with open(path, "rb") as f:
        return plistlib.load(f)


def flatten(value, path=()):
    if isinstance(value, dict):
        for k, v in value.items():
            yield from flatten(v, path + (k,))
    else:
        yield path, value


def resources(t):
    return os.path.join(t["bundlePath"], "Contents", "Resources")


types = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devicetypes", "-j"]))["devicetypes"]
se = next(t for t in types if t["identifier"].endswith(".iPhone-SE-3rd-generation"))
ipads = [t for t in types if t.get("productFamily") == "iPad"]
ipad = next((t for t in ipads if "Air 11" in t["name"]), ipads[-1])

wanted = {}  # plist name -> {key path: value} the iPad has and names PiP
for t in (se, ipad):
    res = resources(t)
    log(f"== {t['name']} ({t['identifier']}) {res}")
    for name in sorted(os.listdir(res)):
        if not name.endswith(".plist"):
            continue
        try:
            data = load(os.path.join(res, name))
        except Exception as e:  # noqa: BLE001 - a lab dump; record and go on
            log(f"{name}: unreadable: {e}")
            continue
        tag = t["identifier"].split(".")[-1]
        with open(os.path.join(OUT, f"devicetype-{tag}-{name}.json"), "w") as f:
            json.dump(data, f, indent=1, default=str)
        for path, value in flatten(data):
            if any(PATTERN.search(str(k)) for k in path):
                log(f"{name}: {'/'.join(map(str, path))} = {value!r}")
                if t is ipad:
                    wanted.setdefault(name, {})[path] = value

if not wanted:
    log("no PiP-looking key on the iPad's device type: nothing to copy")
    sys.exit(0)

dest_root = os.path.expanduser("~/Library/Developer/CoreSimulator/Profiles/DeviceTypes")
os.makedirs(dest_root, exist_ok=True)
dest = os.path.join(dest_root, "iPhone SE PiP.simdevicetype")
shutil.rmtree(dest, ignore_errors=True)
shutil.copytree(se["bundlePath"], dest, symlinks=True)
info_path = os.path.join(dest, "Contents", "Info.plist")
info = load(info_path)
identifier = "com.apple.CoreSimulator.SimDeviceType.iPhone-SE-PiP-lab"
info["CFBundleIdentifier"] = identifier
info["CFBundleName"] = "iPhone SE PiP"
with open(info_path, "wb") as f:
    plistlib.dump(info, f)
for name, keys in wanted.items():
    path = os.path.join(dest, "Contents", "Resources", name)
    data = load(path) if os.path.exists(path) else {}
    for key_path, value in keys.items():
        node = data
        for k in key_path[:-1]:
            node = node.setdefault(k, {})
        before = node.get(key_path[-1], "<absent>")
        node[key_path[-1]] = value
        log(f"copy: {name}: {'/'.join(map(str, key_path))}: {before!r} -> {value!r}")
    with open(path, "wb") as f:
        plistlib.dump(data, f)
log(f"copy written: {dest} as {identifier}")
print(identifier)
