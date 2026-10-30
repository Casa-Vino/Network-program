# Device Scanner (Flutter, Android-first)

A phone app that scans the Wi-Fi network you're joined to and tells you what
each device probably is. It shares its identification approach with the Python
`netinv` tool in this repo (scored signatures, saturating confidence), adapted
to what a phone can actually observe.

> **Authorized use only.** Scan only networks you own or are authorized to
> manage. The app observes hosts (TCP connect probes + mDNS); it does not log
> in to anything or change any device.

## Get it on your phone (no toolchain needed)

A GitHub Actions workflow (`.github/workflows/build-apk.yml`) builds an
installable debug APK in the cloud and publishes it to a rolling release:

1. Push to the `add-mobile-scanner-app` branch (or run the **Build Android
   APK** workflow manually from the repo's **Actions** tab). Wait for it to go
   green — a few minutes.
2. On your phone, open the repo's **Releases** page and the
   **`mobile-latest`** release, or go straight to:
   `https://github.com/Casa-Vino/Network-program/releases/download/mobile-latest/app-debug.apk`
3. Android will ask to allow installing from your browser/Files app the first
   time ("Install unknown apps") — allow it, then open the APK to install.
4. Launch **Device Scanner**, tap **Scan**, and grant the location / nearby-
   devices permission it requests.

The APK is also attached to each workflow run as an artifact (**Actions** →
the run → **Artifacts**) if you prefer that over the release.

> It's a *debug* build (signed with the standard Android debug key), which is
> why it installs without extra signing setup — fine for personal use. For a
> Play Store build you'd set up a release keystore.

## What it can and cannot see

Phones are sandboxed far more tightly than a laptop:

- **No MAC addresses / no vendor (OUI).** Android does not expose other hosts'
  MACs, so there is no manufacturer signal — unlike the Python tool.
- **No ICMP ping.** Raw sockets need root, so liveness is inferred from TCP:
  a connection that *succeeds* or is *refused* proves a host is up. A host
  that silently drops packets (strict firewall) may look absent unless it
  answers mDNS.
- **Signals used:** open TCP ports, advertised mDNS/Bonjour service types,
  the gateway flag, and mDNS hostnames.

## Project layout

```
lib/
  main.dart                 UI (scan button, progress, device list)
  models/device.dart        one host record
  services/discovery.dart   TCP connect scan + mDNS (dart:io + multicast_dns)
  fingerprint/
    signatures.dart         the device signature database (extend here)
    engine.dart             scoring + confidence
```

These are source files only. Generate the platform scaffold with Flutter, then
drop them in.

## Build & run

1. Install Flutter: https://docs.flutter.dev/get-started/install

2. Scaffold a project and overlay these files:

   ```bash
   flutter create --org com.example --platforms=android device_scanner_app
   cd device_scanner_app
   # copy this folder's lib/ and pubspec.yaml over the generated ones
   cp -r /path/to/mobile/device_scanner/lib .
   cp /path/to/mobile/device_scanner/pubspec.yaml .
   ```

3. Prepare the Android scaffold — injects the permissions and `<queries>` and
   installs the native `MainActivity.kt` (the mDNS multicast-lock channel):

   ```bash
   bash tool/prepare_android.sh
   ```

4. Fetch packages and run on a **physical phone** joined to the Wi-Fi you want
   to scan (an emulator is NAT'd and can't see your real LAN):

   ```bash
   flutter pub get
   flutter run
   ```

## Known gotchas

- **mDNS needs a multicast lock on Android.** The `multicast_dns` package opens
  a multicast socket, but some Android builds filter multicast until a
  `WifiManager.MulticastLock` is held. The TCP scan works regardless, so the
  app is useful even where mDNS is quiet; if mDNS comes back empty, that's the
  likely cause and is the first thing to add a tiny platform channel for.
- **Permissions.** On first scan the app requests location / nearby-devices;
  Wi-Fi details return null if denied.
- **Speed.** A /24 is 254 hosts; the two-phase scan (liveness, then port
  fingerprint on live hosts only) keeps a typical home network to well under a
  minute. Tune `concurrency` and `connectTimeout` in `discovery.dart`.

## Dependencies

`network_info_plus` (Wi-Fi IP/gateway), `multicast_dns` (mDNS, official Flutter
team package), `permission_handler` (runtime permissions). Versions are pinned
in `pubspec.yaml`; if `flutter pub get` reports a conflict with your Flutter
version, let it suggest an upgrade.
