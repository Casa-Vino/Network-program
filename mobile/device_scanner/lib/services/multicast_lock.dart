import 'package:flutter/services.dart';

/// Holds an Android Wi-Fi MulticastLock across the method channel implemented
/// in MainActivity.kt. Without it, Android filters inbound multicast and mDNS
/// discovery returns nothing. No-ops safely off Android or if the native side
/// isn't wired up.
class MulticastLock {
  static const MethodChannel _channel = MethodChannel('device_scanner/multicast');

  static Future<void> acquire() => _invoke('acquire');
  static Future<void> release() => _invoke('release');

  static Future<void> _invoke(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // Not Android, or the overlay wasn't installed — mDNS may be limited.
    } on PlatformException {
      // Lock unavailable; carry on without it.
    }
  }
}
