import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Best-effort local IPv4 for the active network.
///
/// On a phone the Wi-Fi IP is the answer; on a desktop (often wired, where
/// getWifiIP is null) we fall back to enumerating network interfaces and
/// picking a private-range address.
Future<String?> localIPv4() async {
  try {
    final ip = await NetworkInfo().getWifiIP();
    if (_usable(ip)) return ip;
  } catch (_) {}

  try {
    final ifaces = await NetworkInterface.list(
      includeLoopback: false,
      includeLinkLocal: false,
      type: InternetAddressType.IPv4,
    );
    // Prefer a private LAN address.
    for (final iface in ifaces) {
      for (final addr in iface.addresses) {
        if (_isPrivate(addr.address)) return addr.address;
      }
    }
    // Otherwise any non-loopback IPv4.
    for (final iface in ifaces) {
      for (final addr in iface.addresses) {
        if (!addr.isLoopback) return addr.address;
      }
    }
  } catch (_) {}
  return null;
}

bool _usable(String? ip) =>
    ip != null && ip.contains('.') && !ip.startsWith('169.254');

bool _isPrivate(String ip) {
  if (ip.startsWith('192.168.') || ip.startsWith('10.')) return true;
  final m = RegExp(r'^172\.(\d+)\.').firstMatch(ip);
  if (m != null) {
    final o = int.tryParse(m.group(1)!) ?? 0;
    return o >= 16 && o <= 31;
  }
  return false;
}

/// A writable directory for downloads that works on both Android and desktop.
Future<Directory> downloadsDir() async {
  try {
    final d = await getDownloadsDirectory(); // desktop
    if (d != null) return d;
  } catch (_) {}
  try {
    final d = await getExternalStorageDirectory(); // android
    if (d != null) return d;
  } catch (_) {}
  return getApplicationDocumentsDirectory();
}
