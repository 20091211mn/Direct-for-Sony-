# PS4 Sender (Flutter)

Sends a direct PKG link to a PS4 running **GoldHEN** (BinLoader only; no Remote Package Installer).

Derived from [DirectPackageInstaller](https://github.com/marcussacana/DirectPackageInstaller)
by marcussacana (GPL-3.0). This project is also GPL-3.0; see LICENSE.
`assets/payload.bin` is the prebuilt payload from that project
(payload template by sleirsgoevy, PS4 exports by OpenOrbis SDK).

## Run

```bash
flutter create . --platforms=android      # generates the android/ folder
# add to android/app/src/main/AndroidManifest.xml (inside <manifest>):
#   <uses-permission android:name="android.permission.INTERNET"/>
flutter pub get
flutter run
```

On the PS4: GoldHEN > Servers > BinLoader (port 9090). Phone and PS4 must be on the same Wi-Fi.

## Status

First version, untested on a real console. Known gaps:
- `packageDigest` is a 64-zero placeholder (the original sends the PKG header digest).
- No segmented mode / archives / file-host resolvers yet.
- Proxy mode relays on the phone; no Android foreground service yet, keep the app open.

## Background operation

`native/` and `tool/patch_android.sh` add an Android foreground service (wake lock + Wi-Fi lock),
applied by the GitHub Actions workflow after `flutter create`. It runs only while a transfer is active.

## Features

- Send a direct link (optionally through the phone as a proxy) or a local PKG file.
- Progress percentage, speed and estimated time left while the phone serves the package.
- Fast mode: the phone downloads with parallel Range connections (like the original "Segmented Downloads"), without storing the file.
- Arabic / English UI (button in the app bar).

## iPhone

`.github/workflows/build-ios.yml` builds an unsigned `ps4-sender.ipa` (run it manually).
It must be signed/sideloaded (for example with AltStore or Sideloadly). iOS suspends apps in
the background, so keep the app open with the screen on while sending.

## Updates

Every Android build is published as a GitHub Release (`v1.0.<run number>`, asset `ps4-sender.apk`).
The app checks the latest release (gear icon > Check for updates), downloads the APK and opens the installer.
Updates only install over the old app if every build is signed with the **same key**: store a keystore in the
GitHub secret `ANDROID_KEYSTORE_BASE64` (alias `androiddebugkey`, password `android`). The repository must be public.
