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
sed "s/^package .*/package $PKG/" native/UpdateFileProvider.kt > "$DIR/UpdateFileProvider.kt"

# app icon (adaptive + legacy) and its background colour
cp -r native/res/. android/app/src/main/res/

mkdir -p android/app/src/main/res/xml
cat > android/app/src/main/res/xml/ps4sender_file_paths.xml <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<paths>
    <cache-path name="cache" path="." />
</paths>
XML

python3 - android/app/src/main/AndroidManifest.xml <<'PY'
import os, re, sys
p = sys.argv[1]
s = open(p).read()
names = ["INTERNET", "WAKE_LOCK", "FOREGROUND_SERVICE",
         "FOREGROUND_SERVICE_DATA_SYNC", "POST_NOTIFICATIONS",
         "ACCESS_NETWORK_STATE", "ACCESS_WIFI_STATE", "CHANGE_WIFI_STATE",
         "REQUEST_IGNORE_BATTERY_OPTIMIZATIONS", "REQUEST_INSTALL_PACKAGES"]
perms = "".join('<uses-permission android:name="android.permission.%s"/>' % n for n in names)
s = re.sub(r"(<manifest[^>]*>)", lambda m: m.group(1) + perms, s, count=1)
svc = '<service android:name=".KeepAliveService" android:exported="false" android:foregroundServiceType="dataSync"/>'
assert "</application>" in s
assert "</activity>" in s
share = ('<intent-filter><action android:name="android.intent.action.SEND"/>'
         '<category android:name="android.intent.category.DEFAULT"/>'
         '<data android:mimeType="text/plain"/></intent-filter>'
         '<intent-filter><action android:name="android.intent.action.SEND"/>'
         '<action android:name="android.intent.action.SEND_MULTIPLE"/>'
         '<category android:name="android.intent.category.DEFAULT"/>'
         '<data android:mimeType="application/octet-stream"/></intent-filter>')
admin = os.environ.get("APP_KIND") == "admin"
if not admin:  # the admin app must not appear in the Share menu
    s = s.replace("</activity>", share + "</activity>", 1)
label = "PS4 Store Admin" if admin else "PS4 Sender"
s = s.replace('android:label="ps4_sender"', 'android:label="%s"' % label)
s = s.replace("<application", '<application android:usesCleartextTraffic="true"', 1)
prov = ('<provider android:name=".UpdateFileProvider" '
        'android:authorities="${applicationId}.fileprovider" '
        'android:exported="false" android:grantUriPermissions="true">'
        '<meta-data android:name="android.support.FILE_PROVIDER_PATHS" '
        'android:resource="@xml/ps4sender_file_paths"/></provider>')
s = s.replace("</application>", svc + prov + "</application>", 1)
open(p, "w").write(s)
PY
echo "Manifest patched"
