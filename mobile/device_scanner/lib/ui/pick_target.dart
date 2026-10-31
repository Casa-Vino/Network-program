import 'dart:async';

import 'package:flutter/material.dart';

import '../services/discovery_beacon.dart';
import '../services/file_server.dart';
import '../services/pusher.dart';

/// Discovers nearby drop boxes and pushes the given files to the chosen one.
class PickTargetScreen extends StatefulWidget {
  const PickTargetScreen({super.key, required this.files});
  final List<SharedFile> files;

  @override
  State<PickTargetScreen> createState() => _PickTargetScreenState();
}

class _PickTargetScreenState extends State<PickTargetScreen> {
  final _discovery = ShareDiscovery();
  StreamSubscription<List<ShareInfo>>? _sub;
  List<ShareInfo> _boxes = [];
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
        if (mounted) {
          setState(() => _boxes = s.where((e) => e.role == 'dropbox').toList());
        }
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

  Future<void> _send(ShareInfo box) async {
    final progress = ValueNotifier<String>('Starting…');
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text('Sending to ${box.name}'),
        content: ValueListenableBuilder<String>(
          valueListenable: progress,
          builder: (_, v, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(v),
            ],
          ),
        ),
      ),
    );

    String? err;
    try {
      await pushFiles(box, widget.files, onProgress: (done, total, bytes) {
        progress.value = '$done / $total files • ${_fmt(bytes)} sent';
      });
    } catch (e) {
      err = '$e';
    } finally {
      progress.dispose();
    }

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // close progress
    if (err == null) {
      Navigator.of(context).pop(); // leave the picker
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sent ${widget.files.length} file(s) to ${box.name}')),
      );
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Send failed: $err')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Send to a device')),
      body: _error != null
          ? Center(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, textAlign: TextAlign.center)))
          : _boxes.isEmpty
              ? _waiting(context)
              : ListView.separated(
                  itemCount: _boxes.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final b = _boxes[i];
                    return ListTile(
                      leading: const Icon(Icons.move_to_inbox),
                      title: Text(b.name),
                      subtitle: Text(b.ip),
                      trailing: const Icon(Icons.send),
                      onTap: () => _send(b),
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
                width: 36, height: 36, child: CircularProgressIndicator()),
            const SizedBox(height: 18),
            Text('Looking for devices accepting files…',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'On the destination device, open Receive and turn on '
              '"Act as a drop box". It will appear here.',
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
