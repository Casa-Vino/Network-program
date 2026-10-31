import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/discovery_beacon.dart';
import '../services/dropbox_server.dart';
import '../services/net_util.dart';

/// Two ways to receive:
///  * browse nearby *sharing* devices and pull their files as a zip, or
///  * become a *drop box* so other devices push files into this one's Inbox.
class ReceiveFilesScreen extends StatefulWidget {
  const ReceiveFilesScreen({super.key});

  @override
  State<ReceiveFilesScreen> createState() => _ReceiveFilesScreenState();
}

class _ReceiveFilesScreenState extends State<ReceiveFilesScreen> {
  final _discovery = ShareDiscovery();
  final _dropbox = DropBoxServer();
  final _dropBeacon = ShareBeacon();
  StreamSubscription<List<ShareInfo>>? _sub;
  List<ShareInfo> _shares = [];
  bool _dropActive = false;
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
    _dropBeacon.stop();
    _dropbox.stop();
    super.dispose();
  }

  Future<void> _toggleDropBox() async {
    if (_dropActive) {
      await _dropBeacon.stop();
      await _dropbox.stop();
      if (mounted) setState(() => _dropActive = false);
      return;
    }
    try {
      await _dropbox.start();
      await _dropBeacon.start(
        name: deviceName(),
        port: _dropbox.port,
        token: _dropbox.token,
        fileCount: 0,
        totalSize: 0,
        role: 'dropbox',
      );
      if (mounted) setState(() => _dropActive = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not start drop box: $e');
    }
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

    // (bytesReceived, totalBytes) — total filled once we see Content-Length.
    final progress = ValueNotifier<(int, int)>((0, 0));
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text('Receiving from ${share.name}'),
        content: ValueListenableBuilder<(int, int)>(
          valueListenable: progress,
          builder: (_, v, __) {
            final (rec, tot) = v;
            final frac = tot > 0 ? (rec / tot).clamp(0.0, 1.0) : null;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: frac),
                const SizedBox(height: 8),
                Text(tot > 0
                    ? '${_fmt(rec)} / ${_fmt(tot)}  (${(rec / tot * 100).toStringAsFixed(0)}%)'
                    : '${_fmt(rec)} received'),
              ],
            );
          },
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
      final totalBytes = resp.contentLength; // exact (zip sends Content-Length)
      final out = File(path).openWrite();
      var total = 0;
      try {
        await for (final chunk in resp) {
          out.add(chunk);
          total += chunk.length;
          progress.value = (total, totalBytes > 0 ? totalBytes : 0);
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
      progress.dispose();
    }

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          savedPath != null ? 'Saved to $savedPath' : 'Receive failed: $err'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final sharers = _shares.where((s) => s.role != 'dropbox').toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Receive from a device')),
      body: Column(
        children: [
          _dropBoxCard(context),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const Divider(height: 1),
          Expanded(
            child: sharers.isEmpty
                ? _waiting(context)
                : ListView.separated(
                    itemCount: sharers.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final s = sharers[i];
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
          ),
        ],
      ),
    );
  }

  Widget _dropBoxCard(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: _dropActive
          ? theme.colorScheme.secondaryContainer
          : theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_dropActive ? Icons.inbox : Icons.move_to_inbox,
                  color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _dropActive
                      ? 'Drop box ON — "${deviceName()}"'
                      : 'Act as a drop box',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Switch(value: _dropActive, onChanged: (_) => _toggleDropBox()),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _dropActive
                ? 'Other devices can now push files here (Send → to a device). '
                    'Files land in Downloads/DeviceScanner/Inbox. Keep this '
                    'screen open.'
                : 'Turn on to let other devices push files to this one without '
                    'any setup — no shared folder, no password.',
            style: theme.textTheme.bodySmall,
          ),
          if (_dropActive)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ValueListenableBuilder<int>(
                valueListenable: _dropbox.received,
                builder: (_, v, __) => Text('Received this session: $v file(s)',
                    style: theme.textTheme.bodyMedium),
              ),
            ),
        ],
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
                width: 36, height: 36, child: CircularProgressIndicator()),
            const SizedBox(height: 18),
            Text('Looking for nearby devices sharing…',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'To pull files, the other device opens Send and taps Start '
              'sharing. To receive pushes instead, turn on the drop box above.',
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
