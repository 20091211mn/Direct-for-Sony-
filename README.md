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
- `packageDigest` is sent empty (the original sends the PKG header digest).
- No segmented mode / archives / file-host resolvers yet.
- Proxy mode relays on the phone; no Android foreground service yet, keep the app open.
