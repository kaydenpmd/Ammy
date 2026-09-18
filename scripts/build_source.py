#!/usr/bin/env python3
"""
Regenerate the AltStore/SideStore source JSON with a newly built version.

Static metadata (name, icon, description, screenshots) lives in
source.config.json and is re-applied on every run, so fixing a typo there and
cutting any release publishes the fix. Per-build facts arrive as arguments from
publish-source.yml. Older version entries are preserved — that list is what lets
someone install a previous build when a new one breaks on their device.

Usage:
    build_source.py --config source.config.json \
                    --source public/source.json \
                    --ipa dist/Ammy-1.0-b42-abc1234.ipa \
                    --version 1.0 \
                    --build-version 42 \
                    --download-url https://github.com/.../Ammy-1.0-b42-abc1234.ipa \
                    --changelog-file changelog.txt
"""

import argparse
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path


def die(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def hex_color(value):
    """AltStore wants bare hex. Accept '#5b8def' or '5b8def', emit the latter."""
    if not value:
        return None
    return value.lstrip("#").lower()


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def version_sort_key(entry):
    """
    Newest first. "1.10" must sort above "1.2", which string comparison gets
    backwards, so each dot-separated chunk is compared as a number. Non-numeric
    chunks (a "1.0-beta2") fall back to 0 rather than raising — they'll land
    beside their release version, which is close enough for a list nobody reads
    past the first entry of.
    """
    raw = str(entry.get("version", "0"))
    parts = []
    for chunk in raw.replace("-", ".").split("."):
        parts.append(int(chunk) if chunk.isdigit() else 0)
    return parts


def apply_app_metadata(app, app_cfg):
    """Write config metadata onto an app entry, leaving its version list alone."""
    app["name"] = app_cfg["name"]
    app["bundleIdentifier"] = app_cfg["bundleIdentifier"]
    app["developerName"] = app_cfg.get("developerName", app.get("developerName", ""))
    app["localizedDescription"] = app_cfg.get(
        "localizedDescription", app.get("localizedDescription", "")
    )
    app["iconURL"] = app_cfg.get("iconURL", app.get("iconURL", ""))
    app.setdefault("versions", [])

    for optional in ("subtitle", "category"):
        if app_cfg.get(optional):
            app[optional] = app_cfg[optional]
    if hex_color(app_cfg.get("tintColor")):
        app["tintColor"] = hex_color(app_cfg["tintColor"])
    if app_cfg.get("screenshots"):
        app["screenshots"] = app_cfg["screenshots"]
    if app_cfg.get("appPermissions"):
        app["appPermissions"] = app_cfg["appPermissions"]
    return app


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--config", required=True, help="source.config.json")
    p.add_argument("--source", required=True, help="source.json to create or update")
    p.add_argument("--ipa", required=True, help="built .ipa, read for size and hash")
    p.add_argument("--version", required=True, help="MARKETING_VERSION, e.g. 1.0")
    p.add_argument(
        "--build-version",
        help="CURRENT_PROJECT_VERSION. AltStore compares this against the "
        "installed CFBundleVersion, so passing it makes update detection exact.",
    )
    p.add_argument("--download-url", required=True)
    p.add_argument("--changelog-file")
    p.add_argument("--changelog", default="")
    p.add_argument("--date", help="ISO 8601 release date. Defaults to now (UTC).")
    args = p.parse_args()

    cfg_path = Path(args.config)
    if not cfg_path.is_file():
        die(f"config not found: {cfg_path}")
    cfg = json.loads(cfg_path.read_text(encoding="utf-8"))

    for required in ("sourceName", "sourceIdentifier", "sourceURL", "app"):
        if not cfg.get(required):
            die(f"'{required}' missing from {cfg_path}")
    for required in ("name", "bundleIdentifier"):
        if not cfg["app"].get(required):
            die(f"'app.{required}' missing from {cfg_path}")

    ipa_path = Path(args.ipa)
    if not ipa_path.is_file():
        die(f"ipa not found: {ipa_path}")
    size = ipa_path.stat().st_size
    digest = sha256_of(ipa_path)

    changelog = args.changelog
    if args.changelog_file:
        cl_path = Path(args.changelog_file)
        if cl_path.is_file():
            changelog = cl_path.read_text(encoding="utf-8").strip()
    if not changelog:
        changelog = f"Version {args.version}"

    date = args.date or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S+00:00")

    source_path = Path(args.source)
    if source_path.is_file():
        source = json.loads(source_path.read_text(encoding="utf-8"))
    else:
        source_path.parent.mkdir(parents=True, exist_ok=True)
        source = {"apps": [], "news": []}

    # Top-level source metadata is rewritten from config every run.
    source["name"] = cfg["sourceName"]
    source["identifier"] = cfg["sourceIdentifier"]
    source["sourceURL"] = cfg["sourceURL"]
    if cfg.get("website"):
        source["website"] = cfg["website"]
    if hex_color(cfg.get("tintColor")):
        source["tintColor"] = hex_color(cfg["tintColor"])
    source.setdefault("apps", [])
    source.setdefault("news", [])

    bundle_id = cfg["app"]["bundleIdentifier"]
    app = next(
        (a for a in source["apps"] if a.get("bundleIdentifier") == bundle_id), None
    )
    if app is None:
        app = apply_app_metadata({}, cfg["app"])
        source["apps"].append(app)
    else:
        apply_app_metadata(app, cfg["app"])

    entry = {
        "version": args.version,
        "date": date,
        "localizedDescription": changelog,
        "downloadURL": args.download_url,
        "size": size,
        "sha256": digest,
    }
    if args.build_version:
        entry["buildVersion"] = str(args.build_version)
    if cfg["app"].get("minOSVersion"):
        entry["minOSVersion"] = cfg["app"]["minOSVersion"]
    if cfg["app"].get("maxOSVersion"):
        entry["maxOSVersion"] = cfg["app"]["maxOSVersion"]

    # A republished version replaces its old entry rather than duplicating it.
    versions = [v for v in app["versions"] if str(v.get("version")) != args.version]
    versions.append(entry)
    versions.sort(key=version_sort_key, reverse=True)
    app["versions"] = versions

    source_path.write_text(
        json.dumps(source, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )

    print(f"Wrote {source_path}")
    print(f"  app       {app['name']} ({bundle_id})")
    print(f"  version   {args.version}" + (f" (build {args.build_version})" if args.build_version else ""))
    print(f"  size      {size:,} bytes")
    print(f"  sha256    {digest}")
    print(f"  versions  {len(versions)} total, newest first")


if __name__ == "__main__":
    main()
