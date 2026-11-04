import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'net_config.dart';

/// A subnet to scan: a display label plus the concrete host IPs to probe.
class ScanNet {
  ScanNet(this.label, this.hosts, {this.truncated = false});
  final String label; // "192.168.1" for a /24, else "10.0.0.0/22"
  final List<String> hosts;
  final bool truncated; // real subnet larger than the host cap
}

int _ipToInt(String ip) {
  final p = ip.split('.');
  if (p.length != 4) return 0;
  return ((int.parse(p[0]) << 24) |
          (int.parse(p[1]) << 16) |
          (int.parse(p[2]) << 8) |
          int.parse(p[3])) &
      0xFFFFFFFF;
}

String _intToIp(int v) =>
    '${(v >> 24) & 0xFF}.${(v >> 16) & 0xFF}.${(v >> 8) & 0xFF}.${v & 0xFF}';

/// Host addresses of the subnet that [ip]/[prefix] belongs to, capped.
List<String> hostsForCidr(String ip, int prefix, {int maxHosts = 4096}) {
  if (prefix >= 31) return [ip];
  final ipn = _ipToInt(ip);
  final mask = (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
  final network = ipn & mask;
  final broadcast = network | (~mask & 0xFFFFFFFF);
  final hosts = <String>[];
  for (var a = network + 1; a <= broadcast - 1 && hosts.length < maxHosts; a++) {
    hosts.add(_intToIp(a));
  }
  return hosts;
}

/// Build the set of subnets to scan from this device's detected interfaces and
/// their real masks (falling back to /24 where the mask is unknown).
Future<List<ScanNet>> defaultScanNets({int maxHostsPerNet = 4096}) async {
  final cfg = await readNetConfig();
  final nets = <ScanNet>[];
  final seen = <String>{};
  for (final iface in cfg.interfaces) {
    for (final ip in iface.ipv4) {
      if (!_isPrivate(ip)) continue;
      final prefix = iface.prefix ?? 24;
      final mask = prefix >= 32
          ? 0xFFFFFFFF
          : (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
      final base = _intToIp(_ipToInt(ip) & mask);
      if (!seen.add('$base/$prefix')) continue;
      final hosts = hostsForCidr(ip, prefix, maxHosts: maxHostsPerNet);
      final total = prefix >= 31 ? 1 : (1 << (32 - prefix)) - 2;
      final label =
          prefix == 24 ? ip.substring(0, ip.lastIndexOf('.')) : '$base/$prefix';
      nets.add(ScanNet(label, hosts, truncated: total > hosts.length));
    }
  }
  if (nets.isEmpty) {
    final ip = await localIPv4();
    if (ip != null && ip.contains('.')) {
      final pfx = ip.substring(0, ip.lastIndexOf('.'));
      nets.add(ScanNet(pfx, [for (var i = 1; i <= 254; i++) '$pfx.$i']));
    }
  }
  return nets;
}

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
