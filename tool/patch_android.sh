#!/usr/bin/env bash
# Run after `flutter create . --platforms=android`.
# Adds the foreground service, permissions and the MethodChannel activity.
set -euo pipefail

MA=$(find android/app/src/main -name MainActivity.kt | head -1)
[ -n "$MA" ] || { echo "MainActivity.kt not found"; exit 1; }
DIR=$(dirname "$MA")
PKG=$(grep -m1 '^package ' "$MA" | awk '{print $2}')
echo "Android package: $PKG"

sed "s/^package .*/package $PKG/" native/MainActivity.kt > "$MA"
sed "s/^package .*/package $PKG/" native/KeepAliveService.kt > "$DIR/KeepAliveService.kt"

python3 - android/app/src/main/AndroidManifest.xml <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
names = ["INTERNET", "WAKE_LOCK", "FOREGROUND_SERVICE",
         "FOREGROUND_SERVICE_DATA_SYNC", "POST_NOTIFICATIONS",
         "ACCESS_NETWORK_STATE", "ACCESS_WIFI_STATE", "CHANGE_WIFI_STATE",
         "REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"]
perms = "".join('<uses-permission android:name="android.permission.%s"/>' % n for n in names)
s = re.sub(r"(<manifest[^>]*>)", lambda m: m.group(1) + perms, s, count=1)
svc = '<service android:name=".KeepAliveService" android:exported="false" android:foregroundServiceType="dataSync"/>'
assert "</application>" in s
s = s.replace("<application", '<application android:usesCleartextTraffic="true"', 1)
s = s.replace("</application>", svc + "</application>", 1)
open(p, "w").write(s)
PY
echo "Manifest patched"
