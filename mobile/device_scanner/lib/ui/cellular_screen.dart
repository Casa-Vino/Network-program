import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Shows the serving mobile network and registered cell/tower identifiers,
/// read via the native TelephonyManager method channel. Observational only —
/// it reports what the modem already sees, it does not transmit or probe.
class CellularScreen extends StatefulWidget {
  const CellularScreen({super.key});

  @override
  State<CellularScreen> createState() => _CellularScreenState();
}

class _CellularScreenState extends State<CellularScreen> {
  static const _channel = MethodChannel('device_scanner/cell');

  Map<String, dynamic>? _info;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Cell identities (ci/tac/pci) require location permission on modern
      // Android; operator/network type work with phone state alone.
      await [Permission.phone, Permission.locationWhenInUse].request();
      final res = await _channel.invokeMethod<Map>('info');
      setState(() {
        _info = res == null
            ? null
            : res.map((k, v) => MapEntry(k.toString(), v));
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!Platform.isAndroid) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mobile network')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Mobile network info is available on Android phones only.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final info = _info;
    final cells =
        (info?['cells'] as List?)?.cast<Map>().toList() ?? const <Map>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mobile network'),
        bottom: _loading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator())
            : null,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _load,
        icon: const Icon(Icons.refresh),
        label: const Text('Refresh'),
      ),
      body: _error != null
          ? Center(
              child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(_error!, textAlign: TextAlign.center)))
          : info == null
              ? Center(
                  child: Text(_loading ? 'Reading…' : 'No data',
                      style: theme.textTheme.bodyMedium))
              : ListView(
                  padding: const EdgeInsets.only(bottom: 88),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Text('Serving network',
                          style: theme.textTheme.labelLarge),
                    ),
                    _kv('Operator', info['operator']),
                    _kv('SIM', info['sim']),
                    _kv('MCC/MNC', info['mccMnc']),
                    _kv('Network type', info['networkType']),
                    const Divider(height: 24),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: Text('Registered cells (${cells.length})',
                          style: theme.textTheme.labelLarge),
                    ),
                    if (cells.isEmpty)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: Text(
                          'No cell identifiers reported. Grant Location to the '
                          'app and make sure a SIM is active.',
                        ),
                      )
                    else
                      ...cells.map(_cellTile),
                  ],
                ),
    );
  }

  Widget _kv(String k, Object? v) {
    final s = (v == null || '$v'.isEmpty) ? '—' : '$v';
    return ListTile(
      dense: true,
      title: Text(k),
      trailing: Text(s, style: Theme.of(context).textTheme.titleSmall),
    );
  }

  Widget _cellTile(Map c) {
    final parts = <String>[];
    void add(String label, Object? v) {
      if (v != null) parts.add('$label $v');
    }

    add('CI', c['ci']);
    add('CID', c['cid']);
    add('TAC', c['tac']);
    add('LAC', c['lac']);
    add('PCI', c['pci']);
    final dbm = c['dbm'];
    return ListTile(
      leading: const Icon(Icons.cell_tower),
      title: Text('${c['type'] ?? 'Cell'}'),
      subtitle: parts.isEmpty ? null : Text(parts.join('  •  ')),
      trailing: dbm == null
          ? null
          : Text('$dbm dBm', style: Theme.of(context).textTheme.titleSmall),
    );
  }
}
