#!/usr/bin/env python3
"""Creates the AltStore / SideStore source (altstore.json) for the iOS build.

usage: make_source.py <owner/repo> <ipa> <bundle id> <version> <build> <output>
Add the source once in SideStore/AltStore and updates show up there.
"""
import datetime
import json
import os
import sys

repo, ipa, bundle, version, build, out = sys.argv[1:7]
owner = repo.split("/")[0]
base = f"https://github.com/{repo}/releases/download/ios-latest"
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
size = os.path.getsize(ipa)
desc = "Send PKG links and files to a PS4 running GoldHEN."

app = {
    "name": "PS4 Sender",
    "bundleIdentifier": bundle,
    "developerName": owner,
    "subtitle": "Send PKG files to your PS4",
    "localizedDescription": desc,
    "iconURL": f"https://raw.githubusercontent.com/{repo}/main/assets/icon/icon.png",
    "tintColor": "1B3FD8",
    "screenshotURLs": [],
    "versions": [{
        "version": version,
        "buildVersion": build,
        "date": now,
        "localizedDescription": f"Build {build}",
        "downloadURL": f"{base}/ps4-sender.ipa",
        "size": size,
        "minOSVersion": "14.0",
    }],
    # older readers of the format look at these fields
    "version": version,
    "versionDate": now,
    "versionDescription": f"Build {build}",
    "downloadURL": f"{base}/ps4-sender.ipa",
    "size": size,
}
source = {
    "name": "PS4 Sender",
    "identifier": f"{bundle}.source",
    "sourceURL": f"{base}/altstore.json",
    "subtitle": "Updates for PS4 Sender",
    "description": desc,
    "website": f"https://github.com/{repo}",
    "tintColor": "1B3FD8",
    "apps": [app],
    "news": [],
}
with open(out, "w") as f:
    json.dump(source, f, indent=2)
print("source written:", out)
