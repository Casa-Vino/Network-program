# Device Scanner (Flutter: Android + Windows)

> Windows desktop build: CI (`.github/workflows/build-windows.yml`) produces
> `device-scanner-windows-x64.zip` on the rolling release. Unzip and run
> `device_scanner.exe`. Platform differences are handled in code: desktop skips
> Android runtime permissions, uses the OS folder dialog for "Share a folder",
> finds the LAN IP via network interfaces (works on Ethernet), and saves
> downloads to the Downloads folder. In-app update is Android-only; on desktop,
> grab the latest zip from Releases.



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
>
> The repo commits a fixed debug keystore (`android-debug.keystore`) and CI
> signs every build with it, so successive updates install over the top. This
> is a *debug* key (well-known password `android`) — not a secret, and it
> cannot publish to the Play Store. The first install after introducing it
> still needs one uninstall+reinstall, because the previously-installed APK
> was signed with a different (per-run) key.

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

## Getting into a device (default-login helper + audit)

Expanding a device card that has a web admin port shows:

- **Likely default login** — a vendor hint (e.g. Wavlink → `admin/admin`) from
  `fingerprint/default_logins.dart`, with an honest note that new routers use a
  **unique password on the label**, not a universal default.
- **Open <url>** — launches the admin page in your browser.
- **Check default login** — an ownership-gated, read-only audit
  (`services/admin_audit.dart`). It asks you to confirm you're authorized, then
  for devices using **HTTP Basic** auth it tries a short list of well-known
  defaults and tells you if one is accepted (a weakness to fix). It never
  changes anything, never submits login *forms* (detected but not auto-filled),
  and only detects HTTP Digest rather than testing it.

This mirrors the desktop tool's `drivers/http_admin.py`. It's an aid for setting
up or auditing **your own / authorized** networks — not a way into others'.

## In-app updates

The toolbar overflow menu has **Check for updates** (`services/updater.dart`).
CI publishes a `version.json` next to the APK on the rolling release; the app
compares its `versionCode` (the CI run number, set via `--build-number`) and,
when a newer build exists, downloads the APK and launches Android's installer.
Because every build is signed with the committed debug keystore, it updates in
place — no uninstall. Needs the one-time "Install unknown apps" permission.

## Send files to a computer (no USB, no PC install)

The toolbar's **Send files to a computer** button
(`ui/send_files.dart` + `services/file_server.dart`) copies files off the phone
over Wi-Fi when USB/MTP won't work:

1. **Pick files** (multi-select) or **Share a folder** (e.g. your whole Camera
   roll — needs "All files access"; files stream from their original location,
   nothing is copied, so GBs are fine).
2. Tap **Start sharing** — the app runs a tiny web server and shows a URL + QR
   code, plus the file count and total size.
3. On any computer on the same Wi-Fi, open that URL (or scan the QR) in a
   browser. Click **Download all** to grab everything (approve the browser's
   "allow multiple downloads" prompt), or download files individually. Nothing
   is installed on the computer.
4. **Stop sharing** when done.

A random token in the URL keeps it LAN-private (convenience, not strong
security); keep the screen open during the transfer.

## Browsing SMB shares (file transfer)

Devices with SMB open (ports 445/139) get a **Browse shared folders** button.
It opens an SMB client (`ui/smb_browser.dart` + `services/smb_client.dart`,
built on the pure-Dart `smb_connect`) that lets you:

- connect with the server's Windows/Samba username + password (or blank for a
  guest attempt);
- list shares, navigate folders, and see file sizes;
- **download** a file to the phone (`Android/data/<pkg>/files/Downloads/`);
- **upload** a local file into the current folder (via the file picker).

Notes:
- `smb_connect` speaks SMB 1.0/CIFS/2.0/2.1 — fine for Windows and Samba, which
  negotiate down. It does not do SMB 3.x.
- Downloads land in the app's external files dir (no storage permission needed);
  browse there with any file manager.
- Use only on shares you own or are authorized to access.

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
