import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/file_server.dart';

/// Pick files on the phone and serve them over the local Wi-Fi so any computer
/// can download them from a browser — no USB, nothing to install on the PC.
class SendFilesScreen extends StatefulWidget {
  const SendFilesScreen({super.key});

  @override
  State<SendFilesScreen> createState() => _SendFilesScreenState();
}

class _SendFilesScreenState extends State<SendFilesScreen> {
  final _server = FileServer();
  List<SharedFile> _files = [];
  String? _url;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _server.stop();
    super.dispose();
  }

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null) return;
    final files = <SharedFile>[];
    for (final f in result.files) {
      if (f.path != null) {
        files.add(SharedFile(name: f.name, path: f.path!, size: f.size));
      }
    }
    setState(() => _files = files);
  }

  Future<void> _start() async {
    if (_files.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ip = await NetworkInfo().getWifiIP();
      if (ip == null || !ip.contains('.')) {
        throw 'No Wi-Fi connection — join the same network as the computer.';
      }
      await _server.start(_files);
      setState(() => _url = 'http://$ip:${_server.port}/${_server.token}/');
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    await _server.stop();
    setState(() => _url = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Send files to a computer')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Pick files, start sharing, then open the shown link in a browser '
            'on any computer on this Wi-Fi to download them. Nothing to install '
            'on the computer.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _url != null ? null : _pick,
                icon: const Icon(Icons.attach_file),
                label: Text(_files.isEmpty
                    ? 'Pick files'
                    : '${_files.length} file(s) selected'),
              ),
            ],
          ),
          if (_files.isNotEmpty && _url == null) ...[
            const SizedBox(height: 8),
            ..._files.map((f) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('• ${f.name}',
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis),
                )),
          ],
          const SizedBox(height: 16),
          if (_url == null)
            FilledButton.icon(
              onPressed: (_files.isEmpty || _busy) ? null : _start,
              icon: const Icon(Icons.wifi_tethering),
              label: const Text('Start sharing'),
            )
          else
            _sharingCard(theme),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
        ],
      ),
    );
  }

  Widget _sharingCard(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text('Open this on the computer:',
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 12),
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(12),
                  child: QrImageView(
                      data: _url!,
                      version: QrVersions.auto,
                      size: 200,
                      backgroundColor: Colors.white),
                ),
                const SizedBox(height: 12),
                SelectableText(
                  _url!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontFeatures: const []),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Keep this screen open during the transfer. '
          'Sharing ${_files.length} file(s).',
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _stop,
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text('Stop sharing'),
        ),
      ],
    );
  }
}
