import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'multicast_lock.dart';
import 'net_util.dart';

/// Peer discovery for "send to a nearby device" without typing URLs.
///
/// Rather than mDNS (which needs Bonjour/Avahi — not present on stock Windows),
/// this uses a tiny UDP broadcast protocol in pure dart:io, so it behaves the
/// same on Android and desktop. A device that is currently *sharing* beacons
/// its presence; other devices listen and show it in a "nearby" list.
const int kDiscoveryPort = 50808;
const String _magic = 'DEVSCAN1';

/// Best-effort friendly name for this device.
String deviceName() {
  var n = '';
  try {
    n = Platform.localHostname.trim();
  } catch (_) {}
  if (n.isEmpty || n.toLowerCase() == 'localhost') {
    final os = Platform.isAndroid
        ? 'Android'
        : Platform.isWindows
            ? 'Windows'
            : Platform.isMacOS
                ? 'Mac'
                : Platform.isLinux
                    ? 'Linux'
                    : 'Unknown';
    n = '$os device';
  }
  return n;
}

/// A sharing device seen on the network.
class ShareInfo {
  ShareInfo({
    required this.name,
    required this.ip,
    required this.port,
    required this.token,
    required this.files,
    required this.size,
    required this.lastSeen,
    this.role = 'share',
  });

  final String name;
  final String ip;
  final int port;
  final String token;
  final int files;
  final int size;
  final String role; // 'share' (serves files) or 'dropbox' (accepts uploads)
  DateTime lastSeen;

  String get key => '$ip:$port';
  String get baseUrl => 'http://$ip:$port/$token';
}

/// Advertises this device while it is sharing.
class ShareBeacon {
  RawDatagramSocket? _sock;
  Timer? _timer;

  Future<void> start({
    required String name,
    required int port,
    required String token,
    required int fileCount,
    required int totalSize,
    String role = 'share',
  }) async {
    await MulticastLock.acquire(); // helps Android receive/send broadcast
    _sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _sock!.broadcastEnabled = true;

    final payload = utf8.encode(jsonEncode({
      'magic': _magic,
      'name': name,
      'port': port,
      'token': token,
      'files': fileCount,
      'size': totalSize,
      'role': role,
    }));

    Future<void> beacon() async {
      final targets = <String>['255.255.255.255'];
      final ip = await localIPv4();
      if (ip != null && ip.contains('.')) {
        targets.add('${ip.substring(0, ip.lastIndexOf('.'))}.255');
      }
      for (final t in targets) {
        try {
          _sock?.send(payload, InternetAddress(t), kDiscoveryPort);
        } catch (_) {}
      }
    }

    await beacon();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => beacon());
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _sock?.close();
    _sock = null;
    await MulticastLock.release();
  }
}

/// Listens for sharing devices and emits the current list.
class ShareDiscovery {
  RawDatagramSocket? _sock;
  Timer? _expiry;
  String? _selfIp;
  final Map<String, ShareInfo> _shares = {};
  final _controller = StreamController<List<ShareInfo>>.broadcast();

  Stream<List<ShareInfo>> get stream => _controller.stream;

  Future<void> start() async {
    _selfIp = await localIPv4();
    await MulticastLock.acquire();
    _sock = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4, kDiscoveryPort,
        reuseAddress: true);
    _sock!.broadcastEnabled = true;
    _sock!.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = _sock!.receive();
      if (dg == null) return;
      try {
        final j = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
        if (j['magic'] != _magic) return;
        if (dg.address.address == _selfIp) return; // ignore our own beacon
        final info = ShareInfo(
          name: (j['name'] ?? 'Device').toString(),
          ip: dg.address.address,
          port: (j['port'] as num).toInt(),
          token: j['token'].toString(),
          files: (j['files'] as num?)?.toInt() ?? 0,
          size: (j['size'] as num?)?.toInt() ?? 0,
          role: (j['role'] ?? 'share').toString(),
          lastSeen: DateTime.now(),
        );
        _shares[info.key] = info;
        _emit();
      } catch (_) {}
    });

    _expiry = Timer.periodic(const Duration(seconds: 3), (_) {
      final now = DateTime.now();
      final before = _shares.length;
      _shares.removeWhere((_, v) => now.difference(v.lastSeen).inSeconds > 7);
      if (_shares.length != before) _emit();
    });
  }

  void _emit() {
    final list = _shares.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (!_controller.isClosed) _controller.add(list);
  }

  Future<void> stop() async {
    _expiry?.cancel();
    _sock?.close();
    _sock = null;
    await MulticastLock.release();
    await _controller.close();
  }
}
