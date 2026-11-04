import 'dart:convert';
import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';

/// This machine's own network configuration — what an IT person checks first on
/// an unfamiliar network. Interfaces + IPs come from dart:io everywhere; the
/// subnet prefix, gateway and DNS are enriched per-platform and degrade
/// gracefully (anything we can't read is just omitted).
class IfaceInfo {
  IfaceInfo(this.name);
  final String name;
  final List<String> ipv4 = [];
  int? prefix; // CIDR prefix length for the primary IPv4 (the subnet mask)
}

class NetConfig {
  NetConfig(this.interfaces, this.gateways, this.dns);
  final List<IfaceInfo> interfaces;
  final List<String> gateways;
  final List<String> dns;
}

/// 255.255.255.0 -> 24
int? maskToPrefix(String mask) {
  final parts = mask.split('.');
  if (parts.length != 4) return null;
  var bits = 0;
  for (final p in parts) {
    final n = int.tryParse(p.trim());
    if (n == null || n < 0 || n > 255) return null;
    bits += n.toRadixString(2).split('').where((c) => c == '1').length;
  }
  return bits;
}

Future<NetConfig> readNetConfig() async {
  final ifaces = <String, IfaceInfo>{};
  try {
    for (final ni in await NetworkInterface.list(
        type: InternetAddressType.IPv4, includeLoopback: false)) {
      final info = IfaceInfo(ni.name);
      for (final a in ni.addresses) {
        if (!a.isLoopback) info.ipv4.add(a.address);
      }
      if (info.ipv4.isNotEmpty) ifaces[ni.name] = info;
    }
  } catch (_) {}

  final gateways = <String>{};
  final dns = <String>{};

  try {
    if (Platform.isWindows) {
      await _windows(ifaces, gateways, dns);
    } else if (Platform.isLinux || Platform.isMacOS) {
      await _unix(ifaces, gateways, dns);
    } else if (Platform.isAndroid) {
      await _android(ifaces, gateways);
    }
  } catch (_) {}

  return NetConfig(ifaces.values.toList(), gateways.toList(), dns.toList());
}

void _setPrefix(Map<String, IfaceInfo> ifaces, String ip, int prefix) {
  for (final i in ifaces.values) {
    if (i.ipv4.contains(ip)) i.prefix ??= prefix;
  }
}

Future<String> _run(String exe, List<String> args) async {
  try {
    final r = await Process.run(exe, args);
    return (r.stdout ?? '').toString();
  } catch (_) {
    return '';
  }
}

dynamic _tryJson(String s) {
  try {
    return jsonDecode(s);
  } catch (_) {
    return null;
  }
}

List<T> _asList<T>(dynamic v) {
  if (v == null) return [];
  if (v is List) return v.cast<T>();
  return [v as T];
}

Future<void> _windows(
    Map<String, IfaceInfo> ifaces, Set<String> gw, Set<String> dns) async {
  // Structured JSON from PowerShell is locale-independent (unlike ipconfig).
  final addrs = _tryJson(await _run('powershell', [
    '-NoProfile',
    '-Command',
    'Get-NetIPAddress -AddressFamily IPv4 | Select-Object IPAddress,PrefixLength | ConvertTo-Json -Compress'
  ]));
  for (final a in _asList<dynamic>(addrs)) {
    if (a is Map && a['IPAddress'] != null && a['PrefixLength'] != null) {
      _setPrefix(ifaces, a['IPAddress'].toString(),
          (a['PrefixLength'] as num).toInt());
    }
  }

  final routes = _tryJson(await _run('powershell', [
    '-NoProfile',
    '-Command',
    "Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' | Select-Object -ExpandProperty NextHop | ConvertTo-Json -Compress"
  ]));
  for (final g in _asList<dynamic>(routes)) {
    final s = g.toString();
    if (s.contains('.') && s != '0.0.0.0') gw.add(s);
  }

  final servers = _tryJson(await _run('powershell', [
    '-NoProfile',
    '-Command',
    '(Get-DnsClientServerAddress -AddressFamily IPv4).ServerAddresses | ConvertTo-Json -Compress'
  ]));
  for (final d in _asList<dynamic>(servers)) {
    final s = d.toString();
    if (s.contains('.')) dns.add(s);
  }
}

Future<void> _unix(
    Map<String, IfaceInfo> ifaces, Set<String> gw, Set<String> dns) async {
  final addr = await _run('ip', ['-o', '-4', 'addr', 'show']);
  for (final line in addr.split('\n')) {
    final m = RegExp(r'inet (\d+\.\d+\.\d+\.\d+)/(\d+)').firstMatch(line);
    if (m != null) _setPrefix(ifaces, m.group(1)!, int.parse(m.group(2)!));
  }
  final route = await _run('ip', ['route', 'show', 'default']);
  for (final m in RegExp(r'default via (\d+\.\d+\.\d+\.\d+)').allMatches(route)) {
    gw.add(m.group(1)!);
  }
  try {
    for (final line in await File('/etc/resolv.conf').readAsLines()) {
      final m = RegExp(r'^\s*nameserver\s+(\d+\.\d+\.\d+\.\d+)').firstMatch(line);
      if (m != null) dns.add(m.group(1)!);
    }
  } catch (_) {}
}

Future<void> _android(Map<String, IfaceInfo> ifaces, Set<String> gw) async {
  final info = NetworkInfo();
  try {
    final ip = await info.getWifiIP();
    final mask = await info.getWifiSubmask();
    if (ip != null && mask != null) {
      final p = maskToPrefix(mask);
      if (p != null) _setPrefix(ifaces, ip, p);
    }
    final g = await info.getWifiGatewayIP();
    if (g != null && g.contains('.')) gw.add(g);
  } catch (_) {}
}
