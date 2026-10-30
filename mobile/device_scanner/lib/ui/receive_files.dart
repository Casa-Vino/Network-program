import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/discovery_beacon.dart';
import '../services/net_util.dart';

/// Discovers nearby devices that are sharing and pulls their files in-app —
/// no URL typing. Tap a device to save everything it's sharing as a zip.
class ReceiveFilesScreen extends StatefulWidget {
  const ReceiveFilesScreen({super.key});

  @override
  State<ReceiveFilesScreen> createState() => _ReceiveFilesScreenState();
}

class _ReceiveFilesScreenState extends State<ReceiveFilesScreen> {
  final _discovery = ShareDiscovery();
  StreamSubscription<List<ShareInfo>>? _sub;
  List<ShareInfo> _shares = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      await _discovery.start();
      _sub = _discovery.stream.listen((s) {
        if (mounted) setState(() => _shares = s);
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Discovery failed: $e');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _discovery.stop();
    super.dispose();
  }

  Future<void> _receive(ShareInfo share) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Receive from ${share.name}?'),
        content: Text('${share.files} file(s) • ${_fmt(share.size)}\n\n'
            'Saves a single zip to your Downloads folder.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Receive')),
        ],
      ),
    );
    if (go != true || !mounted) return;

    final received = ValueNotifier<int>(0);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text('Receiving from ${share.name}'),
        content: ValueListenableBuilder<int>(
          valueListenable: received,
          builder: (_, v, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text('${_fmt(v)} received'),
            ],
          ),
        ),
      ),
    );

    String? savedPath;
    String? err;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final base = await downloadsDir();
      final dir = Directory('${base.path}/DeviceScanner');
      await dir.create(recursive: true);
      final safe = share.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final path = '${dir.path}/$safe.zip';

      final req = await client.getUrl(Uri.parse('${share.baseUrl}/all.zip'));
      final resp = await req.close();
      if (resp.statusCode != 200) throw 'HTTP ${resp.statusCode}';
      final out = File(path).openWrite();
      var total = 0;
      try {
        await for (final chunk in resp) {
          out.add(chunk);
          total += chunk.length;
          received.value = total;
        }
        await out.flush();
      } finally {
        await out.close();
      }
      savedPath = path;
    } catch (e) {
      err = '$e';
    } finally {
      client.close(force: true);
      received.dispose();
    }

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // close progress
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(savedPath != null
          ? 'Saved to $savedPath'
          : 'Receive failed: $err'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Receive from a device')),
      body: _error != null
          ? Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!, textAlign: TextAlign.center)))
          : _shares.isEmpty
              ? _waiting(context)
              : ListView.separated(
                  itemCount: _shares.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final s = _shares[i];
                    return ListTile(
                      leading: const Icon(Icons.phonelink_ring),
                      title: Text(s.name),
                      subtitle: Text(
                          '${s.ip} • ${s.files} file(s) • ${_fmt(s.size)}'),
                      trailing: const Icon(Icons.download),
                      onTap: () => _receive(s),
                    );
                  },
                ),
    );
  }

  Widget _waiting(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
                width: 40, height: 40, child: CircularProgressIndicator()),
            const SizedBox(height: 20),
            Text('Looking for nearby devices…',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'On the device you want to receive from, open Send files, choose '
              'files or a folder, and tap Start sharing. It will appear here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) return '${(b / 1048576).toStringAsFixed(1)} MB';
    return '${(b / 1073741824).toStringAsFixed(2)} GB';
  }
}
