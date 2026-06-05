#!/usr/bin/env python3
"""Validate a latest.json manifest before publishing.

Checks: version matches the tag, URLs reference the tag, sha256 are 64 hex chars,
sizes are positive, and pub_date is ISO-8601 UTC.

Usage: validate_latest_json.py <path> <expected_version>
"""
import json
import re
import sys
from datetime import datetime

path, expected_version = sys.argv[1], sys.argv[2]
manifest = json.loads(open(path).read())

errors = []

if manifest.get("version") != expected_version:
    errors.append(f"version {manifest.get('version')} != {expected_version}")

try:
    datetime.strptime(manifest["pub_date"], "%Y-%m-%dT%H:%M:%SZ")
except (KeyError, ValueError):
    errors.append(f"pub_date not ISO-8601 UTC: {manifest.get('pub_date')}")

for name, asset in manifest.get("assets", {}).items():
    if not asset:
        continue
    if f"v{expected_version}/" not in asset.get("url", ""):
        errors.append(f"{name}: url does not reference v{expected_version}")
    if not re.fullmatch(r"[0-9a-fA-F]{64}", asset.get("sha256", "")):
        errors.append(f"{name}: sha256 is not 64 hex chars")
    if not isinstance(asset.get("size"), int) or asset["size"] <= 0:
        errors.append(f"{name}: size must be a positive integer")

if errors:
    print("Manifest validation FAILED:")
    for e in errors:
        print(f"  - {e}")
    sys.exit(1)

print("Manifest valid.")
