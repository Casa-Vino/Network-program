import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// Scans for nearby Bluetooth LE devices and lists them by signal.
/// Observational only — it discovers and identifies, it doesn't pair or probe.
class BleScreen extends StatefulWidget {
  const BleScreen({super.key});

  @override
  State<BleScreen> createState() => _BleScreenState();
}

class _BleScreenState extends State<BleScreen> {
  final Map<String, ScanResult> _devices = {};
  StreamSubscription<List<ScanResult>>? _resultsSub;
  StreamSubscription<bool>? _scanningSub;
  bool _scanning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _resultsSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        _devices[r.device.remoteId.str] = r;
      }
      if (mounted) setState(() {});
    }, onError: (e) {
      if (mounted) setState(() => _error = '$e');
    });
    _scanningSub = FlutterBluePlus.isScanning.listen((s) {
      if (mounted) setState(() => _scanning = s);
    });
  }

  @override
  void dispose() {
    _resultsSub?.cancel();
    _scanningSub?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _devices.clear();
    });
    try {
      if (Platform.isAndroid) {
        await [
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.locationWhenInUse,
        ].request();
      }
      if (!await FlutterBluePlus.isSupported) {
        setState(() => _error = 'Bluetooth is not supported on this device.');
        return;
      }
      final state = await FlutterBluePlus.adapterState.first;
      if (state != BluetoothAdapterState.on) {
        setState(() => _error = 'Turn Bluetooth on, then scan again.');
        return;
      }
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidUsesFineLocation: false,
      );
    } catch (e) {
      setState(() => _error = 'Scan failed: $e');
    }
  }

  String _name(ScanResult r) {
    final n = r.device.platformName.trim();
    if (n.isNotEmpty) return n;
    final a = r.advertisementData.advName.trim();
    if (a.isNotEmpty) return a;
    return '(unknown)';
  }

  IconData _rssiIcon(int rssi) {
    if (rssi >= -60) return Icons.bluetooth_connected;
    if (rssi >= -80) return Icons.bluetooth;
    return Icons.bluetooth_searching;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = _devices.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bluetooth devices'),
        bottom: _scanning
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator())
            : null,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _scanning ? null : _start,
        icon: Icon(_scanning ? Icons.hourglass_top : Icons.bluetooth_searching),
        label: Text(_scanning ? 'Scanning…' : 'Scan'),
      ),
      body: _error != null
          ? Center(
              child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(_error!, textAlign: TextAlign.center)))
          : list.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      _scanning
                          ? 'Listening for Bluetooth LE devices…'
                          : 'Tap Scan to discover nearby Bluetooth LE devices.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: list.length + 1,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text('${list.length} device(s) found',
                            style: theme.textTheme.labelLarge),
                      );
                    }
                    final r = list[i - 1];
                    final svc = r.advertisementData.serviceUuids.length;
                    return ListTile(
                      leading: Icon(_rssiIcon(r.rssi)),
                      title: Text(_name(r)),
                      subtitle: Text([
                        r.device.remoteId.str,
                        if (svc > 0) '$svc service(s)',
                        if (r.advertisementData.connectable) 'connectable',
                      ].join('  •  ')),
                      trailing: Text('${r.rssi} dBm',
                          style: theme.textTheme.titleSmall),
                    );
                  },
                ),
    );
  }
}
