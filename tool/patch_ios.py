#!/usr/bin/env python3
"""Run after `flutter create . --platforms=ios`: adds the Local Network usage text."""
import plistlib

P = "ios/Runner/Info.plist"
with open(P, "rb") as f:
    d = plistlib.load(f)
d["NSLocalNetworkUsageDescription"] = (
    "Needed to send the package to your PS4 on the local network."
)
with open(P, "wb") as f:
    plistlib.dump(d, f)
print("Info.plist patched")
