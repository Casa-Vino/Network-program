import 'dart:async';
import 'dart:io';

import 'package:multicast_dns/multicast_dns.dart';
import 'package:network_info_plus/network_info_plus.dart';

import '../fingerprint/engine.dart';
import '../models/device.dart';
import 'multicast_lock.dart';
import 'net_util.dart';

/// Discovers devices on the currently-joined Wi-Fi network.
///
/// Phones can't send ICMP echo (that needs a raw socket / root), so liveness
/// is inferred with a TCP connect scan: a connection that either *succeeds* or
/// is *refused* proves the host is up (refused just means that port is closed).
/// Only a timeout is treated as "no host". We then enrich with reverse-DNS
/// names and mDNS (under a multicast lock on Android) before fingerprinting.
///
/// Limitation: a host behind a firewall that silently drops packets looks
/// "down" to a connect scan unless it answers mDNS.
enum _Probe { open, refused, down }

typedef ProgressCallback = void Function(String status, double fraction);

class NetworkScanner {
  // Probed first to decide if a host is even there.
  static const List<int> livenessPorts = [80, 443, 22, 445, 7000, 8008];

  // Probed only on hosts already known to be up, for fingerprinting.
  static const List<int> fingerprintPorts = [
    53, 139, 515, 548, 554, 631, 1883, 3000, 3389, 5000, 5001,
    8001, 8009, 8060, 8080, 8123, 8443, 9100, 32400, 62078,
  ];

  // mDNS service types asked for directly (parallel, bounded) instead of
  // walking _services._dns-sd, which would be far slower.
  static const List<String> mdnsServiceTypes = [
    '_airplay._tcp', '_raop._tcp', '_mediaremotetv._tcp', '_googlecast._tcp',
    '_ipp._tcp', '_ipps._tcp', '_printer._tcp', '_pdl-datastream._tcp',
    '_smb._tcp', '_afpovertcp._tcp', '_hap._tcp', '_hue._tcp',
    '_ssh._tcp', '_sftp-ssh._tcp', '_http._tcp', '_sonos._tcp',
    '_spotify-connect._tcp', '_workstation._tcp', '_device-info._tcp',
    '_roku-rcp._tcp',
  ];

  static const Duration connectTimeout = Duration(milliseconds: 600);
  static const Duration reverseTimeout = Duration(seconds: 2);
  static const int concurrency = 60;

  final NetworkInfo _netInfo = NetworkInfo();

  Future<List<Device>> scan({ProgressCallback? onProgress}) async {
    onProgress?.call('Reading network info…', 0);
    final wifiIp = await localIPv4();
    if (wifiIp == null || !wifiIp.contains('.')) {
      throw const ScanException(
          'No local network detected. Connect to Wi-Fi or Ethernet and retry.');
    }
    final gateway = await _netInfo.getWifiGatewayIP();
    final prefix = wifiIp.substring(0, wifiIp.lastIndexOf('.') + 1);

    final devices = <String, Device>{};
    Device dev(String ip) => devices.putIfAbsent(ip, () => Device(ip));

    // Phase 1 — liveness across the /24.
    final candidates = [for (var i = 1; i <= 254; i++) '$prefix$i'];
    final up = <String>{};
    var done = 0;
    await _pool(candidates, (ip) async {
      for (final port in livenessPorts) {
        final r = await _probe(ip, port);
        if (r == _Probe.open) {
          dev(ip).openPorts.add(port);
          up.add(ip);
        } else if (r == _Probe.refused) {
          up.add(ip);
        }
      }
      done++;
      onProgress?.call('Finding hosts… ($done/254)', 0.05 + 0.40 * (done / 254));
    });

    // Phase 2 — fingerprint ports, live hosts only.
    final liveList = up.toList();
    done = 0;
    await _pool(liveList, (ip) async {
      for (final port in fingerprintPorts) {
        if (await _probe(ip, port) == _Probe.open) dev(ip).openPorts.add(port);
      }
      done++;
      final total = liveList.isEmpty ? 1 : liveList.length;
      onProgress?.call('Scanning ports… ($done/${liveList.length})',
          0.45 + 0.25 * (done / total));
    });

    // Phase 3 — mDNS under a multicast lock (non-fatal if blocked).
    onProgress?.call('Discovering mDNS services…', 0.72);
    await MulticastLock.acquire();
    try {
      await _mdns(dev);
    } catch (_) {
      // Multicast can still be filtered on some networks; keep what we have.
    } finally {
      await MulticastLock.release();
    }

    if (gateway != null && gateway.contains('.')) {
      dev(gateway).isGateway = true;
      up.add(gateway);
    }

    // Phase 4 — reverse DNS for hosts that mDNS didn't already name.
    onProgress?.call('Resolving names…', 0.88);
    await _pool(up.toList(), (ip) async {
      final d = dev(ip);
      if (d.hostname != null) return;
      try {
        final r = await InternetAddress(ip).reverse().timeout(reverseTimeout);
        if (r.host.isNotEmpty && r.host != ip) d.hostname = r.host;
      } catch (_) {
        // No PTR record; leave hostname null.
      }
    });

    onProgress?.call('Identifying…', 0.96);
    final result = devices.values
        .where((d) =>
            up.contains(d.ip) ||
            d.isGateway ||
            d.openPorts.isNotEmpty ||
            d.services.isNotEmpty)
        .toList()
      ..sort((a, b) => a.lastOctet.compareTo(b.lastOctet));

    for (final d in result) {
      annotate(d);
    }
    onProgress?.call('Done', 1);
    return result;
  }

  Future<_Probe> _probe(String ip, int port) async {
    Socket? socket;
    try {
      socket = await Socket.connect(ip, port, timeout: connectTimeout);
      return _Probe.open;
    } on SocketException catch (e) {
      final msg = (e.osError?.message ?? e.message).toLowerCase();
      if (e.osError?.errorCode == 111 || msg.contains('refused')) {
        return _Probe.refused; // host up, port closed
      }
      return _Probe.down; // timeout / unreachable
    } catch (_) {
      return _Probe.down;
    } finally {
      socket?.destroy();
    }
  }

  Future<void> _mdns(Device Function(String) dev) async {
    final client = MDnsClient();
    await client.start();
    try {
      await Future.wait(
          mdnsServiceTypes.map((svc) => _resolveService(client, svc, dev)));
    } finally {
      client.stop();
    }
  }

  Future<void> _resolveService(
      MDnsClient client, String service, Device Function(String) dev) async {
    const timeout = Duration(seconds: 3);
    final serviceType = '$service.local';
    await for (final ptr in client.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(serviceType),
        timeout: timeout)) {
      await for (final srv in client.lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(ptr.domainName),
          timeout: timeout)) {
        await for (final a in client.lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(srv.target),
            timeout: timeout)) {
          final d = dev(a.address.address);
          d.services.add(service);
          d.hostname ??= srv.target.replaceAll('.local', '');
        }
      }
    }
  }

  /// Runs [task] over [items] with a bounded number of concurrent futures.
  /// Safe with a shared iterator: moveNext()/current are synchronous, so no
  /// two workers ever observe the same element (single-threaded event loop).
  Future<void> _pool<T>(List<T> items, Future<void> Function(T) task) async {
    final it = items.iterator;
    Future<void> worker() async {
      while (it.moveNext()) {
        await task(it.current);
      }
    }

    await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
  }
}

class ScanException implements Exception {
  const ScanException(this.message);
  final String message;
  @override
  String toString() => message;
}
