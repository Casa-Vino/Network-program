import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'models/device.dart';
import 'services/discovery.dart';

void main() => runApp(const DeviceScannerApp());

class DeviceScannerApp extends StatelessWidget {
  const DeviceScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final seed = const Color(0xFF0E8388);
    return MaterialApp(
      title: 'Device Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
          colorSchemeSeed: seed, useMaterial3: true, brightness: Brightness.light),
      darkTheme: ThemeData(
          colorSchemeSeed: seed, useMaterial3: true, brightness: Brightness.dark),
      home: const ScanPage(),
    );
  }
}

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  bool _scanning = false;
  double _progress = 0;
  String _status = '';
  String? _error;
  List<Device> _devices = [];

  Future<void> _scan() async {
    // Wi-Fi details (and mDNS) need location/nearby-devices permission on
    // modern Android. Requesting both covers API levels < 33 and >= 33.
    await [Permission.locationWhenInUse, Permission.nearbyWifiDevices].request();

    setState(() {
      _scanning = true;
      _error = null;
      _devices = [];
      _progress = 0;
      _status = 'Starting…';
    });

    try {
      final scanner = NetworkScanner();
      final result = await scanner.scan(onProgress: (s, p) {
        if (mounted) setState(() {
          _status = s;
          _progress = p;
        });
      });
      if (mounted) setState(() => _devices = result);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices on your network'),
        bottom: _scanning
            ? PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: LinearProgressIndicator(value: _progress == 0 ? null : _progress),
              )
            : null,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _scanning ? null : _scan,
        icon: Icon(_scanning ? Icons.hourglass_top : Icons.wifi_find),
        label: Text(_scanning ? 'Scanning…' : 'Scan'),
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_error != null) {
      return _Centered(
          icon: Icons.error_outline,
          title: 'Scan failed',
          subtitle: _error!);
    }
    if (_scanning && _devices.isEmpty) {
      return _Centered(
          icon: Icons.radar, title: _status, subtitle: 'Probing the local subnet…');
    }
    if (_devices.isEmpty) {
      return const _Centered(
        icon: Icons.wifi_tethering,
        title: 'Tap Scan to discover devices',
        subtitle: 'Scans only the Wi-Fi you are connected to. '
            'Use on networks you own or are authorized to manage.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: _devices.length + 1,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('${_devices.length} device(s) found',
                style: Theme.of(context).textTheme.labelLarge),
          );
        }
        return _DeviceTile(device: _devices[i - 1]);
      },
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device});
  final Device device;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ports = (device.openPorts.toList()..sort()).join(', ');
    final confidencePct = (device.confidence * 100).round();

    return ExpansionTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.secondaryContainer,
        child: Icon(_iconFor(device.category),
            color: theme.colorScheme.onSecondaryContainer),
      ),
      title: Row(
        children: [
          Expanded(
              child: Text(device.role,
                  style: theme.textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis)),
          if (device.confidence > 0)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Chip(
                label: Text('$confidencePct%'),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
            ),
        ],
      ),
      subtitle: Text(
        [device.ip, if (device.hostname != null) device.hostname!].join('  •  '),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(72, 0, 16, 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ports.isNotEmpty) _kv('Open ports', ports),
        if (device.services.isNotEmpty)
          _kv('mDNS services', device.services.join(', ')),
        if (device.reasons.isNotEmpty)
          _kv('Why', device.reasons.join(', ')),
        if (device.notes != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(device.notes!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontStyle: FontStyle.italic)),
          ),
      ],
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 13, height: 1.3),
            children: [
              TextSpan(
                  text: '$k: ',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              TextSpan(text: v),
            ],
          ),
        ),
      );

  IconData _iconFor(String? category) {
    switch (category) {
      case 'gateway / router':
        return Icons.router;
      case 'printer':
        return Icons.print;
      case 'file server / nas':
        return Icons.storage;
      case 'media / airplay':
      case 'media renderer':
        return Icons.cast;
      case 'speaker':
        return Icons.speaker;
      case 'homekit accessory':
      case 'iot hub':
      case 'unidentified device':
        return Icons.sensors;
      case 'camera':
        return Icons.videocam;
      case 'host':
      case 'host (windows)':
        return Icons.computer;
      case 'mobile (apple)':
        return Icons.smartphone;
      case 'web device':
        return Icons.language;
      default:
        return Icons.devices_other;
    }
  }
}

class _Centered extends StatelessWidget {
  const _Centered(
      {required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
