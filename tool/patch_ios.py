#!/usr/bin/env python3
"""Run after `flutter create . --platforms=ios`: adds the Local Network usage text."""
import glob
import json
import os
import plistlib
import shutil

P = "ios/Runner/Info.plist"
with open(P, "rb") as f:
    d = plistlib.load(f)
d["CFBundleDisplayName"] = "PS4 Sender"
d["NSLocalNetworkUsageDescription"] = (
    "Needed to send the package to your PS4 on the local network."
)
with open(P, "wb") as f:
    plistlib.dump(d, f)
print("Info.plist patched")

# App icon: a single 1024 px image (Xcode 14+ asset catalog format).
ICONSET = "ios/Runner/Assets.xcassets/AppIcon.appiconset"
for old in glob.glob(os.path.join(ICONSET, "*.png")):
    os.remove(old)
shutil.copy("native/ios_icon/icon-1024.png", os.path.join(ICONSET, "icon-1024.png"))
with open(os.path.join(ICONSET, "Contents.json"), "w") as f:
    json.dump({
        "images": [{
            "filename": "icon-1024.png",
            "idiom": "universal",
            "platform": "ios",
            "size": "1024x1024",
        }],
        "info": {"author": "xcode", "version": 1},
    }, f, indent=2)
print("App icon installed")
