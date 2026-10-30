#!/usr/bin/env bash
# Prepare a freshly `flutter create`d Android scaffold for this app:
#   1. inject the network permissions + web-intent <queries> into the manifest
#   2. install the MainActivity.kt overlay (multicast-lock method channel)
# Idempotent: safe to run more than once. Run from anywhere.
set -euo pipefail

cd "$(dirname "$0")/.."  # -> mobile/device_scanner
MANIFEST="android/app/src/main/AndroidManifest.xml"
KOTLIN_DST="android/app/src/main/kotlin/com/casavino/device_scanner/MainActivity.kt"
OVERLAY="android_overlay/MainActivity.kt"

[[ -f "$MANIFEST" ]] || {
  echo "No $MANIFEST — run 'flutter create .' first." >&2
  exit 1
}

# 1) Manifest: permissions + queries (web admin links need package visibility
#    on Android 11+).
if grep -q "ACCESS_WIFI_STATE" "$MANIFEST"; then
  echo "Manifest already prepared."
else
  read -r -d '' BLOCK <<'XML' || true
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.NEARBY_WIFI_DEVICES" android:usesPermissionFlags="neverForLocation" />
    <queries>
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="https" />
        </intent>
        <intent>
            <action android:name="android.intent.action.VIEW" />
            <data android:scheme="http" />
        </intent>
    </queries>
XML
  awk -v block="$BLOCK" '
    /<manifest/ && !ins { print; print block; ins=1; next }
    { print }
  ' "$MANIFEST" > "$MANIFEST.tmp"
  mv "$MANIFEST.tmp" "$MANIFEST"
  echo "Injected permissions + queries into $MANIFEST"
fi

# 2) Native MainActivity with the multicast-lock channel.
if [[ -f "$OVERLAY" ]]; then
  mkdir -p "$(dirname "$KOTLIN_DST")"
  cp "$OVERLAY" "$KOTLIN_DST"
  echo "Installed MainActivity overlay at $KOTLIN_DST"
else
  echo "WARNING: $OVERLAY missing; mDNS multicast lock will be unavailable." >&2
fi
