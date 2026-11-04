#!/usr/bin/env python3
"""Add (or replace) a version entry in altstore/source.json.

Usage: update_source.py <version> <build> <ipa_path> [notes]
"""
import datetime, json, os, sys

version, build, ipa = sys.argv[1], sys.argv[2], sys.argv[3]
notes = sys.argv[4] if len(sys.argv) > 4 else f"SendIt {version}"
repo = os.environ.get("GITHUB_REPOSITORY", "atsrxl/sendit")
path = os.path.join(os.path.dirname(__file__), "..", "altstore", "source.json")

with open(path, encoding="utf-8") as f:
    src = json.load(f)

app = src["apps"][0]
entry = {
    "version": version,
    "buildVersion": str(build),
    "date": datetime.date.today().isoformat(),
    "localizedDescription": notes,
    "downloadURL": f"https://github.com/{repo}/releases/download/v{version}/SendIt.ipa",
    "size": os.path.getsize(ipa),
    "minOSVersion": "16.0",
}
app["versions"] = [entry] + [v for v in app.get("versions", []) if v["version"] != version]

with open(path, "w", encoding="utf-8") as f:
    json.dump(src, f, ensure_ascii=False, indent=2)
    f.write("\n")
print(f"source.json -> {version} ({entry['size']} bytes)")
