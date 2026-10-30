#!/usr/bin/env bash
# Insert the network permissions the scanner needs into the Android manifest
# that `flutter create` generates. Idempotent: a second run is a no-op.
set -euo pipefail

cd "$(dirname "$0")/.."  # -> mobile/device_scanner
MANIFEST="android/app/src/main/AndroidManifest.xml"

[[ -f "$MANIFEST" ]] || {
  echo "No $MANIFEST — run 'flutter create .' first." >&2
  exit 1
}

if grep -q "ACCESS_WIFI_STATE" "$MANIFEST"; then
  echo "Permissions already present; nothing to do."
  exit 0
fi

read -r -d '' PERMS <<'XML' || true
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.NEARBY_WIFI_DEVICES" android:usesPermissionFlags="neverForLocation" />
XML

# Insert the block right after the opening <manifest ...> tag.
awk -v perms="$PERMS" '
  /<manifest/ && !ins { print; print perms; ins=1; next }
  { print }
' "$MANIFEST" > "$MANIFEST.tmp"
mv "$MANIFEST.tmp" "$MANIFEST"

echo "Injected network permissions into $MANIFEST"
